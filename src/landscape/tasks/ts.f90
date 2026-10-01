! This file is part of xtb.
!
! Copyright (C) 2026 xtb contributors
!
! xtb is free software: you can redistribute it and/or modify it under
! the terms of the GNU Lesser General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! xtb is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU Lesser General Public License for more details.
!
! You should have received a copy of the GNU Lesser General Public License
! along with xtb.  If not, see <https://www.gnu.org/licenses/>.

!> Transition state search task of the landscape suite (PLAN section 9.5).
!>
!> This is the task level entry point of the `--lts` run type.  It builds the
!> engine, wraps it into the injectable `landscape_energy_model`
!> (`xtb_landscape_tasks_opt::landscape_engine_model`) and runs one of the two
!> M4 searches:
!>
!>  * `xtb_landscape_saddle_prfo::landscape_saddle_optimize` for P-RFO and
!>    B-P-RFO, which follow an eigenvector of the (numerical) Hessian;
!>  * `xtb_landscape_saddle_dimer::landscape_dimer_optimize` for the dimer,
!>    which uses only first derivatives and therefore never asks the engine for
!>    a Hessian during the search.
!>
!> After the search the stationary point is confirmed with a frequency analysis
!> (`xtb_landscape_vib_modes::landscape_vib_analysis`, the analysis of the M3
!> `--lvib` task) and exactly one imaginary mode is required.
!>
!> Output:
!>
!> | file         | content |
!> |--------------|---------|
!> | `xtbts.xyz`  | converged geometry (energy and gradient norm in the comment) |
!> | `xtbts.log`  | method, frozen `etemp`, step table, frequency confirmation |
!>
!> M4 hard constraint 1 (PLAN section 9.5): the electronic temperature is
!> frozen for the whole run.  `settings%etemp` is the single source; it is
!> pushed into the engine control (and from there into the xTB calculator) and
!> the effective value is printed both from the settings and, read back from
!> the calculator, by `engine%report`.
!>
!> M4 hard constraint 2: the confirmation reports the number and value of the
!> imaginary modes, so a search that ended on a minimum (0) or on a higher
!> order saddle (>1) is reported and **fails** the task (H2 of
!> `29-m4-independent-review.md`): a non-saddle aborts with a non-zero exit
!> status after writing the geometry and the log for debugging.  A mode whose
!> |frequency| lies inside `0 +/- 3 cm^-1` is re-decided with a tighter finite
!> difference (`step = 2e-3` bohr, `sccacc = 0.1`) before its sign is trusted;
!> both spectra are printed (H1).  The dimer search applies the same rule to
!> its own curvature: a point whose gradient meets the criteria but whose
!> curvature along the dimer axis is not negative is not accepted
!> (`xtb_landscape_saddle_dimer`).
!>
!> Units: coordinates in bohr, energies in hartree, gradients in hartree/bohr,
!> frequencies in cm^-1, `etemp` in kelvin.
module xtb_landscape_tasks_ts
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_filetypes, only : fileType
   use xtb_io_writer, only : writeMolecule
   use xtb_type_environment, only : TEnvironment
   use xtb_type_molecule, only : TMolecule
   use xtb_type_restart, only : TRestart
   use xtb_type_calculator, only : TCalculator
   use xtb_landscape_settings, only : landscape_ts_settings, landscape_vib_settings, &
      & landscape_engine_control, landscape_restart_name, &
      & landscape_ts_method_name, p_landscape_ts_dimer
   use xtb_landscape_results, only : landscape_result, landscape_vib_result
   use xtb_landscape_coords, only : geometry_pack, geometry_unpack
   use xtb_landscape_engine, only : landscape_engine, new_landscape_engine, &
      & landscape_hessian_provider, new_landscape_hessian_provider
   use xtb_landscape_tasks_opt, only : landscape_engine_model
   use xtb_landscape_saddle_prfo, only : landscape_saddle_optimize
   use xtb_landscape_saddle_dimer, only : landscape_dimer_optimize
   use xtb_landscape_vib_modes, only : landscape_vib_analysis
   use xtb_setparam, only : get_namespace
   implicit none(type, external)
   private

   public :: landscape_ts
   public :: landscape_ts_curvature_band_hit
   public :: landscape_ts_curvature_band_cm1

   !> Half width of the curvature band around zero (cm^-1) inside which the
   !> sign of a mode is limited by the resolution of the numerical Hessian of
   !> the confirmation.  Requirement 2 of the M4 hard constraints: a mode whose
   !> |frequency| falls inside `0 +/- 3 cm^-1` is recomputed with a tighter
   !> finite difference before its sign is trusted, because the sign is not
   !> meaningful at the default resolution there.
   real(wp), parameter :: landscape_ts_curvature_band_cm1 = 3.0_wp
   !> Tightened finite difference step (bohr) of the recomputation
   real(wp), parameter :: ts_tight_hess_step = 2.0e-3_wp
   !> Tightened SCC accuracy of the recomputation
   real(wp), parameter :: ts_tight_hess_acc = 0.1_wp

contains

!> Task level entry point: locate a first order saddle point.
!>
!> On return `mol%xyz` holds the converged geometry and `result` the search and
!> confirmation summary.  Every fatal condition (unknown method, a failed
!> search, an unconverged SCC) is reported through `env%error`, which the
!> caller turns into a non-zero exit status.
subroutine landscape_ts(env, mol, chk, calc, settings, result)
   character(len=*), parameter :: source = 'landscape_ts'
   !> Computational environment
   type(TEnvironment), intent(inout), target :: env
   !> Molecular structure, updated to the transition state
   type(TMolecule), intent(inout), target :: mol
   !> Wavefunction data
   type(TRestart), intent(inout), target :: chk
   !> Single point calculator
   class(TCalculator), intent(in) :: calc
   !> Transition state settings
   type(landscape_ts_settings), intent(in) :: settings
   !> Search result
   type(landscape_result), intent(inout) :: result

   type(landscape_engine), target :: engine
   type(landscape_engine_model) :: model
   class(landscape_hessian_provider), allocatable :: hp
   type(landscape_engine_control) :: ctrl
   real(wp), allocatable :: x0(:), xfinal(:), traj(:, :)
   integer :: n_scf_fail

   if (settings%printlevel > 0) then
      write(env%unit, '(1x,a,a,a)') "landscape: transition state search (", &
         & landscape_ts_method_name(settings%method), ")"
      write(env%unit, '(1x,a,es15.6,a)') "initial trust radius:     ", &
         & settings%trust, " bohr"
      write(env%unit, '(1x,a,es15.6,a)') "maximum trust radius:     ", &
         & settings%trust_max, " bohr"
      write(env%unit, '(1x,a,i0)') "maximum number of steps:  ", settings%max_steps
      write(env%unit, '(1x,a,a)') "restart policy:           ", &
         & landscape_restart_name(settings%engine%restart_mode)
      ! The dimer search itself never builds a Hessian; the provider is still
      ! created because the frequency confirmation of the located point uses
      ! it, so the source is reported for every method.
      write(env%unit, '(1x,a,a)') "Hessian source:           ", &
         & trim(settings%hessian_source)
      if (settings%method /= p_landscape_ts_dimer) then
         ! MEDIUM-1 of `31-m4-review-round2.md`: the escape from a minimum is
         ! reported with the run so the displacement is visible in the log.
         write(env%unit, '(1x,a,f12.6,a)') "escape from a minimum:      ", &
            & settings%escape_step, " bohr along the lowest internal mode"
      end if
      if (settings%method == p_landscape_ts_dimer) then
         write(env%unit, '(1x,a,es13.6,a)') "dimer separation:         ", &
            & settings%delta, " bohr"
         write(env%unit, '(1x,a,es13.6,a)') "dimer rotation probe:     ", &
            & settings%rot_dtheta, " rad"
         write(env%unit, '(1x,a,i0)') "dimer rotation iterations: ", &
            & settings%rot_max_iter
         write(env%unit, '(1x,a,a,a,i0)') "dimer initial axis:       ", &
            & trim(settings%n_init), " (seed ", settings%seed, ")"
      end if
      ! M4 hard constraint 1: the frozen electronic temperature is part of the
      ! result, not an implicit default.
      write(env%unit, '(1x,a,f12.3,a)') "electronic temperature:   ", &
         & settings%etemp, " K (frozen for the whole run)"
   end if

   ! The engine owns a copy of the calculator.  The frozen etemp is the one of
   ! the task settings, copied into the control object the engine pushes into
   ! the calculator, so a CLI `--etemp` reaches the SCF of every evaluation.
   ctrl = settings%engine
   ctrl%etemp = settings%etemp
   call new_landscape_engine(engine, ctrl)
   call new_landscape_hessian_provider(env, settings%hessian_source, hp, &
      & sccacc=settings%engine%hess_acc, filename=settings%hessian_file)
   if (.not. allocated(hp)) then
      result%message = "transition state search failed"
      call engine%destroy()
      return
   end if
   call engine%set_hessian_provider(hp)
   call engine%set_calculator(calc)
   model%engine => engine
   model%env => env
   model%mol => mol
   model%chk => chk

   x0 = geometry_pack(mol%xyz)
   select case (settings%method)
   case (p_landscape_ts_dimer)
      call landscape_dimer_optimize(env, model, settings, x0, result, xfinal, traj)
   case default
      call landscape_saddle_optimize(env, model, settings, x0, result, xfinal, traj)
   end select
   if (.not. allocated(xfinal)) then
      call env%error("the transition state search did not return a geometry", source)
      call engine%destroy()
      return
   end if

   call geometry_unpack(xfinal, mol%xyz)
   result%n_cache_miss = engine%n_eval
   ! M1 (review 29): record the *effective* electronic temperature read back
   ! from the calculator, not the setting echoed from the request.  A value
   ! that never reached the calculator would otherwise be invisible in the
   ! result object (the M3 MEDIUM-B "dead field" defect).
   result%etemp = engine%effective_etemp()
   n_scf_fail = engine%n_scf_fail

   if (settings%printlevel > 0) then
      call result%write_log(env%unit)
      call result%conv%write_log(env%unit)
   end if

   ! Frequency confirmation of the stationary point.  The Hessian is the one of
   ! the configured provider at the converged geometry; the analysis is the M3
   ! implementation, so the mode count and the 3N-6 / 3N-5 handling are
   ! identical to `--lvib`.
   if (settings%verify_ts) then
      call confirm_saddle(env, mol, chk, engine, settings, result)
   end if

   if (settings%write_files) then
      call write_ts_files(env, mol, settings, result)
   end if

   call engine%report(env%unit)
   call engine%destroy()

   if (n_scf_fail > 0) then
      call env%error("transition state search aborted: the SCC did not "//&
         & "converge at least once", source)
   end if

   if (.not. result%converged) then
      if (allocated(result%message)) then
         call env%error("transition state search did not converge: "//&
            & result%message, source)
      else
         call env%error("transition state search did not converge", source)
      end if
   end if

end subroutine landscape_ts

!> Confirm the stationary point with a frequency analysis.
!>
!> Exactly one imaginary mode is the definition of a first order saddle point.
!> A different count is not silently accepted: the result carries it (`n_imag`)
!> and `is_saddle`, and the task turns a non-saddle into a failure (H2 of
!> `29-m4-independent-review.md`): the three outcomes - first order saddle, a
!> minimum (0 imaginary modes) and a higher order saddle (>= 2) - are printed
!> explicitly and a non-saddle aborts the run with a non-zero exit status (the
!> geometry and the log are still written for debugging).
!>
!> M4 hard constraint 2 (H1): the sign of a mode whose |frequency| falls inside
!> `0 +/- 3 cm^-1` is not meaningful at the default finite difference
!> resolution, so such a Hessian is recomputed once with `step = 2e-3` bohr and
!> `sccacc = 0.1` and the two spectra are printed.  The conversion is explicit:
!> the Hessian eigenvalues are in hartree/bohr^2 and a curvature `lambda`
!> corresponds to `sqrt(|lambda|)*autorcm` cm^-1, so the band is
!> `(3/autorcm)^2 ~ 3.4e-7` hartree/bohr^2 wide in eigenvalue units.
subroutine confirm_saddle(env, mol, chk, engine, settings, result)
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Molecular structure at the converged geometry
   type(TMolecule), intent(inout) :: mol
   !> Wavefunction data
   type(TRestart), intent(inout) :: chk
   !> Engine
   type(landscape_engine), intent(inout) :: engine
   !> Transition state settings
   type(landscape_ts_settings), intent(in) :: settings
   !> Search result, updated with the mode count and the imaginary frequency
   type(landscape_result), intent(inout) :: result

   type(landscape_vib_settings) :: vib_settings
   type(landscape_vib_result) :: vib
   real(wp), allocatable :: hess(:, :)
   real(wp) :: imag_freq, step_used, acc_used
   logical :: fail, band_hit, can_tighten, tightened
   integer :: n3

   n3 = 3*mol%n
   vib_settings%project_tr = settings%project_tr
   vib_settings%linear_tol = settings%linear_tol
   vib_settings%imag_cutoff = settings%imag_cutoff

   ! --- first analysis with the configured finite difference parameters ---
   call build_confirmation_hessian(env, mol, chk, engine, hess, fail)
   if (fail) return
   call landscape_vib_analysis(env, mol, hess, vib_settings, vib, fail)
   if (fail) then
      call env%warning("the saddle confirmation failed; the imaginary mode "//&
         & "count is unknown", 'landscape_ts')
      return
   end if
   imag_freq = lowest_internal_frequency(vib, n3)

   ! M4 hard constraint 2: near-zero curvature is resolution limited.  Tighten
   ! the finite differences once and re-decide the sign.
   band_hit = landscape_ts_curvature_band_hit(vib%freq, vib%n_zero, &
      & landscape_ts_curvature_band_cm1)
   can_tighten = trim(settings%hessian_source) == 'numerical'
   step_used = engine%ctrl%hess_step
   acc_used = engine%ctrl%hess_acc
   tightened = .false.
   if (band_hit) then
      if (settings%printlevel > 0) then
         write(env%unit, '(1x,a,f8.3,a)') "near-zero curvature: a mode lies "//&
            & "inside 0 +/- ", landscape_ts_curvature_band_cm1, " cm^-1"
      end if
      if (can_tighten .and. (abs(step_used - ts_tight_hess_step) > 1.0e-12_wp .or. &
            & abs(acc_used - ts_tight_hess_acc) > 1.0e-12_wp)) then
         if (settings%printlevel > 0) then
            write(env%unit, '(1x,a,es10.3,a,es10.3)') &
               & "  recomputing the Hessian with step ", ts_tight_hess_step, &
               & " bohr and sccacc ", ts_tight_hess_acc
         end if
         engine%ctrl%hess_step = ts_tight_hess_step
         engine%ctrl%hess_acc = ts_tight_hess_acc
         call build_confirmation_hessian(env, mol, chk, engine, hess, fail)
         if (.not. fail) then
            call landscape_vib_analysis(env, mol, hess, vib_settings, vib, fail)
            tightened = .not. fail
         end if
         fail = .false.
         if (tightened) then
            if (settings%printlevel > 0) then
               write(env%unit, '(1x,a,f16.2,a,es10.3)') &
                  & "  tightened re-decision: lowest internal mode ", &
                  & lowest_internal_frequency(vib, n3), " cm^-1 (was ", imag_freq, ")"
            end if
            imag_freq = lowest_internal_frequency(vib, n3)
         else
            call env%warning("the tightened Hessian of the confirmation could "//&
               & "not be built; the sign of the near-zero mode keeps the "//&
               & "default resolution", 'landscape_ts')
         end if
      else if (.not. can_tighten) then
         call env%warning("a near-zero curvature cannot be re-decided: the "//&
            & "Hessian source '"//trim(settings%hessian_source)//"' does not "//&
            & "support tighter finite differences, so the sign of the mode is "//&
            & "resolution limited", 'landscape_ts')
      end if
   end if

   result%n_imag = vib%n_imag
   result%imag_freq = imag_freq
   result%is_saddle = (vib%n_imag == 1)

   if (settings%printlevel > 0) then
      write(env%unit, '(1x,a,i0)') "saddle confirmation - imaginary modes: ", &
         & result%n_imag
      if (result%n_imag > 0) then
         write(env%unit, '(1x,a,f16.2,a)') "most negative frequency: ", &
            & imag_freq, " cm^-1"
      end if
      select case (result%n_imag)
      case (1)
         write(env%unit, '(1x,a)') "confirmation: first order saddle point"
      case (0)
         write(env%unit, '(1x,a)') "confirmation: minimum (0 imaginary "//&
            & "modes) - not a transition state"
      case default
         write(env%unit, '(1x,a,i0,a)') "confirmation: higher order saddle ("//&
            & "point with ", result%n_imag, " imaginary modes) - not a "//&
            & "transition state"
      end select
   end if

   if (.not. result%is_saddle) then
      ! H2: a converged search that did not land on a first order saddle is a
      ! failure, not a warning.  The geometry and the log are still written by
      ! the caller; this only carries the diagnosis to the exit status.
      result%converged = .false.
      if (result%n_imag == 0) then
         result%message = "the located stationary point is a minimum (0 "//&
            & "imaginary modes), not a first order saddle point"
      else
         result%message = "the located stationary point is a higher order "//&
            & "saddle ("//trim(int_to_string(result%n_imag))//& 
            & " imaginary modes), not a first order saddle point"
      end if
      call env%warning(trim(result%message), 'landscape_ts')
   end if

end subroutine confirm_saddle

!> Build a fresh confirmation Hessian through the engine provider.
!>
!> The engine's finite difference parameters (`ctrl%hess_step`, `ctrl%hess_acc`)
!> are used, so the caller can tighten them before the call.  A failed build is
!> reported with a warning and `fail = .true.`; the caller then keeps the
!> unknown mode count instead of aborting the whole run.
subroutine build_confirmation_hessian(env, mol, chk, engine, hess, fail)
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Molecular structure at the converged geometry
   type(TMolecule), intent(inout) :: mol
   !> Wavefunction data
   type(TRestart), intent(inout) :: chk
   !> Engine
   type(landscape_engine), intent(inout) :: engine
   !> Hessian (3N, 3N), allocated on return
   real(wp), allocatable, intent(out) :: hess(:, :)
   !> Failure flag
   logical, intent(out) :: fail

   integer :: n3

   fail = .false.
   n3 = 3*mol%n
   if (allocated(hess)) deallocate(hess)
   allocate(hess(n3, n3), source=0.0_wp)
   call engine%hessian(env, mol, chk, hess, fail)
   if (fail) then
      call env%warning("the Hessian of the saddle confirmation could not be "//&
         & "built; the imaginary mode count is unknown", 'landscape_ts')
   end if

end subroutine build_confirmation_hessian

!> Lowest internal frequency (cm^-1) of a confirmation result, zero if none.
pure function lowest_internal_frequency(vib, n3) result(freq)
   !> Confirmation result
   type(landscape_vib_result), intent(in) :: vib
   !> Number of Cartesian components (3N)
   integer, intent(in) :: n3
   !> Lowest internal mode (cm^-1)
   real(wp) :: freq

   if (vib%n_vib > 0 .and. allocated(vib%freq)) then
      freq = minval(vib%freq(vib%n_zero + 1:n3))
   else
      freq = 0.0_wp
   end if

end function lowest_internal_frequency

!> True if an internal mode lies inside `0 +/- band` cm^-1.
!>
!> The band is expressed in cm^-1 because that is the unit of the frequency
!> table; the underlying Hessian eigenvalues are related by
!> `|frequency| = sqrt(|lambda|)*autorcm`, so the band corresponds to
!> `(band/autorcm)^2` in hartree/bohr^2 (about 3.4e-7 for the default 3 cm^-1).
!> Only the internal modes are tested: the projected zero modes are exactly
!> zero by construction and must not trigger the recomputation.
pure function landscape_ts_curvature_band_hit(freq, n_zero, band) result(hit)
   !> Frequency table (cm^-1, imaginary modes negative)
   real(wp), intent(in) :: freq(:)
   !> Number of projected zero modes at the front of `freq`
   integer, intent(in) :: n_zero
   !> Half width of the band (cm^-1)
   real(wp), intent(in) :: band
   !> True if a mode lies inside the band
   logical :: hit

   integer :: i

   hit = .false.
   do i = n_zero + 1, size(freq)
      if (abs(freq(i)) <= band) then
         hit = .true.
         return
      end if
   end do

end function landscape_ts_curvature_band_hit

!> Write `xtbts.xyz` and `xtbts.log`.
!>
!> The names follow the `<prefix>ts.xyz` scheme of the minimisation task
!> (`xtbopt.xyz`), so a default prefix of `xtb` yields the `xtbts.xyz` /
!> `xtbts.log` pair of PLAN section 9.5.  The log holds the header, the step
!> table and the frequency confirmation, so the file alone documents the run.
subroutine write_ts_files(env, mol, settings, result)
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Molecular structure (converged geometry)
   type(TMolecule), intent(in) :: mol
   !> Transition state settings
   type(landscape_ts_settings), intent(in) :: settings
   !> Search result
   type(landscape_result), intent(in) :: result

   character(len=:), allocatable :: xyzname, logname, name
   integer :: xyzunit, unit, ierr

   ! M3 (review 29): the file names pass through `get_namespace`, exactly like
   ! the scan (`xtbscan.log`) and vib (`vib_normal_modes`) tasks, so a
   ! `--namespace ns --lts` run writes `ns.xtbts.xyz` / `ns.xtbts.log` instead
   ! of colliding with a plain run in the same directory.
   name = get_namespace(trim(settings%output_prefix)//'ts.xyz')
   xyzname = name
   open(newunit=xyzunit, file=xyzname, action='write', iostat=ierr)
   if (ierr /= 0) then
      call env%error("cannot open "//xyzname, 'landscape_ts')
      return
   end if
   call writeMolecule(mol, xyzunit, format=fileType%xyz, energy=result%energy, &
      & gnorm=result%gnorm)
   close(xyzunit)
   write(env%unit, '(1x,a,a)') "wrote ", xyzname

   logname = get_namespace(trim(settings%output_prefix)//'ts.log')
   open(newunit=unit, file=logname, action='write', iostat=ierr)
   if (ierr /= 0) then
      call env%error("cannot open "//logname, 'landscape_ts')
      unit = -1
      return
   end if
   write(unit, '(1x,a,a)') "landscape transition state search: ", &
      & landscape_ts_method_name(settings%method)
   ! the effective (read back) temperature, not the echoed setting (M1)
   write(unit, '(1x,a,f12.3,a)') "electronic temperature (frozen): ", &
      & result%etemp, " K"
   write(unit, '(1x,a,es15.6,a)') "initial trust radius: ", settings%trust, " bohr"
   write(unit, '(1x,a,a)') "Hessian source: ", trim(settings%hessian_source)
   if (allocated(result%message)) then
      write(unit, '(1x,a,a)') "termination: ", result%message
   end if
   call result%write_log(unit)
   call result%conv%write_log(unit)
   if (result%n_imag >= 0) then
      write(unit, '(1x,a,i0)') "confirmation imaginary modes: ", result%n_imag
      write(unit, '(1x,a,l1)') "is a first order saddle: ", result%is_saddle
      if (result%n_imag > 0) then
         write(unit, '(1x,a,f16.2,a)') "most negative frequency: ", &
            & result%imag_freq, " cm^-1"
      end if
   end if
   close(unit)
   write(env%unit, '(1x,a,a)') "wrote ", logname

end subroutine write_ts_files

!> Decimal representation of an integer for a message.
pure function int_to_string(value) result(string)
   !> Value to convert
   integer, intent(in) :: value
   !> Decimal string
   character(len=:), allocatable :: string

   character(len=16) :: buffer

   write(buffer, '(i0)') value
   string = trim(buffer)

end function int_to_string

end module xtb_landscape_tasks_ts
