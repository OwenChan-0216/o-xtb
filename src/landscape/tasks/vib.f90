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

!> Frequency task of the landscape suite (PLAN section 9.4).
!>
!> The task driver is the task level entry point of the `vib` run type: it
!> builds the Hessian through `xtb_landscape_vib_numhess` (i.e. through the
!> configured `hessian_source`), analyses it (`xtb_landscape_vib_modes`) and
!> produces the output.
!>
!> Output files, all with the names and formats of the existing `--hess` run
!> so that existing tool chains keep working:
!>
!> | file                | written by |
!> |---------------------|------------|
!> | `hessian`           | this task (TURBOMOLE layout, non mass weighted, projected) |
!> | `vibspectrum`       | `main_freq` (reused) |
!> | `vib_normal_modes`  | this task (`writeNormalModesTurbomole`, the routine `main_freq` uses) |
!> | `g98.out`           | `main_freq` (reused) |
!> | `xtbhess.xyz`       | `main_freq` -> `distort`, only if imaginary modes exist |
!>
!> `write_files` of the settings controls the two files this suite writes
!> itself (`hessian`, `vib_normal_modes`); the reused xtb printout has no
!> output switch and always produces `vibspectrum`, `g98.out` and the
!> thermodynamic table.  All names go through the xtb file namespace, exactly
!> like the files of `--hess`.
!>
!> The result reports the reference energy, so the caller can write it back
!> into `res`: without that write-back the generic total energy line would
!> report the energy of an unrelated state (`--lopt` had exactly that bug).
!>
!> Units: Hessian elements in hartree/bohr^2, frequencies in cm^-1, energies
!> in hartree; the printed kcal/mol conversion is labelled in the output.
module xtb_landscape_tasks_vib
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_convert, only : autokcal, autoamu
   use xtb_type_environment, only : TEnvironment
   use xtb_type_molecule, only : TMolecule
   use xtb_type_restart, only : TRestart
   use xtb_type_calculator, only : TCalculator
   use xtb_setparam, only : get_namespace
   use xtb_io_writer_turbomole, only : writeNormalModesTurbomole
   use xtb_landscape_settings, only : landscape_vib_settings, landscape_restart_name, &
      & landscape_log_failed
   use xtb_landscape_results, only : landscape_result, landscape_vib_result
   use xtb_landscape_coords, only : vec_norm, geometry_pack
   use xtb_landscape_hessian, only : landscape_write_hessian_file
   use xtb_landscape_vib_numhess, only : landscape_vib_hessian
   use xtb_landscape_vib_modes, only : landscape_vib_analysis
   use xtb_landscape_vib_thermo, only : landscape_vib_thermo_output
   implicit none(type, external)
   private

   public :: landscape_vib

contains

!> Task level entry point: harmonic frequencies and thermochemistry.
!>
!> On return `result` holds the reference energy and the summary of the
!> frequency analysis; `mol` is left at its input geometry (the imaginary mode
!> distortion of the reused printout restores it).
subroutine landscape_vib(env, mol, chk, calc, settings, result)
   character(len=*), parameter :: source = 'landscape_vib'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Molecular structure (geometry is not modified)
   type(TMolecule), intent(inout) :: mol
   !> Wavefunction data
   type(TRestart), intent(inout) :: chk
   !> Single point calculator
   class(TCalculator), intent(in) :: calc
   !> Frequency settings
   type(landscape_vib_settings), intent(in) :: settings
   !> Task result
   type(landscape_result), intent(inout) :: result

   type(landscape_vib_result) :: vib
   real(wp), allocatable :: hess(:, :), gradient(:, :)
   real(wp) :: energy, final_err, lowest, highest
   logical :: fail, ok
   integer :: nlog, n_eval

   fail = .false.
   allocate(hess(3*mol%n, 3*mol%n), gradient(3, mol%n))

   ! Reject thermochemical settings the reused RRHO model cannot handle before
   ! any single point is evaluated.
   call check_thermo_settings(env, settings, ok)
   if (.not. ok) then
      result%message = "frequency analysis failed"
      return
   end if

   if (settings%printlevel > 0) then
      write(env%unit, '(1x,a)') "landscape: harmonic frequencies"
      write(env%unit, '(1x,a,a)') "restart policy:           ", &
         & landscape_restart_name(settings%engine%restart_mode)
      write(env%unit, '(1x,a,a)') "Hessian source:           ", &
         & trim(settings%hessian_source)
      if (allocated(settings%hessian_file)) then
         write(env%unit, '(1x,a,a)') "Hessian file:             ", &
            & trim(settings%hessian_file)
      end if
      write(env%unit, '(1x,a,es15.6,a)') "Hessian step:             ", &
         & settings%engine%hess_step, " bohr"
      write(env%unit, '(1x,a,es15.6)') "Hessian SCC accuracy:     ", &
         & settings%engine%hess_acc
      write(env%unit, '(1x,a,l1)') "project translations/rotations: ", &
         & settings%project_tr
   end if

   ! A file based Hessian without a file name is a configuration error; it is
   ! reported here with the flag that is missing from the command line (the
   ! provider factory refuses it too, with a more generic message).
   if (trim(settings%hessian_source) == 'file') then
      if (.not. allocated(settings%hessian_file)) then
         result%message = "no Hessian file given"
         call env%error("the Hessian source 'file' needs --lvib-hessian-file", source)
         return
      end if
   end if

   call landscape_vib_hessian(env, mol, chk, calc, settings, hess, energy, &
      & gradient, final_err, fail, n_eval)
   if (fail) then
      result%message = "frequency analysis failed"
      return
   end if

   call landscape_vib_analysis(env, mol, hess, settings, vib, fail)
   if (fail) then
      result%message = "frequency analysis failed"
      return
   end if

   if (settings%write_files) then
      nlog = env%nLog
      call write_hessian_file(env, settings, hess)
      if (landscape_log_failed(env, nlog)) then
         result%message = "frequency analysis failed"
         return
      end if
   end if

   call landscape_vib_thermo_output(env, mol, chk, settings, vib, energy, ok)
   if (.not. ok) then
      result%message = "frequency analysis failed"
      return
   end if

   if (settings%write_files) then
      nlog = env%nLog
      call write_normal_modes(env, mol, vib)
      if (landscape_log_failed(env, nlog)) then
         result%message = "frequency analysis failed"
         return
      end if
   end if

   result%energy = energy
   result%gnorm = vec_norm(geometry_pack(gradient))
   result%gmax = result%gnorm
   result%n_eval = n_eval
   result%n_cache_miss = n_eval
   result%converged = .true.
   if (settings%printlevel > 0) then
      write(env%unit, '(1x,a,i0,a,i0,a)') "modes: ", vib%n_vib, " internal, ", &
         & vib%n_zero, " projected zero modes"
      write(env%unit, '(1x,a,l1)') "linear molecule:          ", vib%linear
      write(env%unit, '(1x,a,i0)') "imaginary modes:          ", vib%n_imag
      if (vib%n_vib > 0) then
         lowest = vib%freq(vib%n_zero + 1)
         highest = vib%freq(3*mol%n)
         write(env%unit, '(1x,a,f12.2,a,f12.2,a)') "lowest mode: ", lowest, &
            & " cm^-1, highest mode: ", highest, " cm^-1"
      end if
      write(env%unit, '(1x,a,f20.12,a)') "energy:                   ", energy, " Eh"
      write(env%unit, '(1x,a,f20.12,a)') "energy:                   ", &
         & energy*autokcal, " kcal/mol"
      write(env%unit, '(1x,a,es15.6,a)') "gradient norm:            ", &
         & result%gnorm, " Eh/bohr"
      write(env%unit, '(1x,a,es15.6,a)') "zero point energy:        ", &
         & vib%zpe, " Eh"
      write(env%unit, '(1x,a,es15.6)') "Hessian residual:         ", final_err
   end if

   if (vib%n_imag > 0) then
      result%message = "frequency analysis completed with imaginary modes"
      call env%warning("the Hessian has "//trim(int_to_string(vib%n_imag))//&
         & " imaginary mode(s): the geometry is not a minimum", source)
   else
      result%message = "frequency analysis completed"
   end if

   ! The existing `--hess` always warns about a Hessian of a geometry that is
   ! not a stationary point (`src/hessian.F90:161-170`); the same threshold and
   ! the same wording keep the two paths consistent, so a user who runs `--lvib`
   ! instead of `--hess` gets the same reminder that the frequencies belong to
   ! a non-minimum structure.
   if (result%gnorm > 2.0e-3_wp) then
      write(env%unit, '(1x,a)') "!! INCOMPLETELY OPTIMIZED GEOMETRY !!"
      call env%warning("Hessian on incompletely optimized geometry!", source)
   end if

end subroutine landscape_vib

!> Validate the thermochemical settings of the frequency task.
!>
!> The reused model (`print_thermo`/`thermodyn`, `src/main/property.F90`,
!> `src/thermo.f90`) divides by the temperature (`beta = 1/(kB T)`, hence
!> `log(sqrt(pi/beta ...))`) and by the frequency scaling factor, and it
!> classifies a mode as imaginary by `freq < imag_cutoff`; a non-positive
!> temperature, a non-positive scaling factor or a positive imaginary cutoff
!> therefore produce Inf/NaN entries or silently inverted flags instead of
!> failing.  The checks live here rather than in the parser so that every
!> caller of the task (command line and API) is covered.
subroutine check_thermo_settings(env, settings, ok)
   character(len=*), parameter :: source = 'landscape_vib'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Frequency settings
   type(landscape_vib_settings), intent(in) :: settings
   !> True if every parameter is usable
   logical, intent(out) :: ok

   integer :: ntemp

   ok = .true.
   ntemp = max(1, min(settings%n_temperature, size(settings%temperature)))
   if (any(settings%temperature(1:ntemp) <= 0.0_wp)) then
      call env%error("the thermochemical temperature must be positive", source)
      ok = .false.
   end if
   if (settings%freq_scal <= 0.0_wp) then
      call env%error("the frequency scaling factor must be positive", source)
      ok = .false.
   end if
   if (settings%imag_cutoff > 0.0_wp) then
      call env%error("the imaginary frequency cutoff must not be positive", source)
      ok = .false.
   end if
   if (settings%rotor_cutoff < 0.0_wp) then
      call env%error("the rotor cutoff of the quasi-RRHO treatment must not "//&
         & "be negative", source)
      ok = .false.
   end if

end subroutine check_thermo_settings

!> Write the projected, non mass weighted Hessian as the `hessian` file.
!>
!> The name and the layout are the ones of the `hessian` file of `--hess`
!> (`wrhess`, `src/freq/io.f90:53`), so the file can be read back by
!> `--lvib --lvib-hessian-file hessian`.  The file namespace is applied once,
!> inside `landscape_write_hessian_file` (exactly like `wrhess` through
!> `open_file`, and like the read path of the file provider); applying it here
!> as well would produce `ns.ns.hessian` and break the write-read round trip.
subroutine write_hessian_file(env, settings, hess)
   character(len=*), parameter :: source = 'landscape_vib_write_hessian_file'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Frequency settings
   type(landscape_vib_settings), intent(in) :: settings
   !> Projected Hessian (hartree/bohr^2)
   real(wp), intent(in) :: hess(:, :)
   !> Success flag
   logical :: ok

   call landscape_write_hessian_file(env, 'hessian', hess, ok)
   if (.not. ok) then
      call env%error("the Hessian file could not be written", source)
      return
   end if
   if (settings%printlevel > 0) then
      write(env%unit, '(1x,a)') "wrote hessian, containing the non-mass-"//&
         & "weighted Hessian matrix in atomic units (Eh/bohr^2)"
   end if

end subroutine write_hessian_file

!> Write the mass weighted normal modes in the TURBOMOLE format.
!>
!> The routine is the one `main_freq` uses for `--hess`; it removes the mass
!> weighting from the modes itself, so the masses are passed in amu (`autoamu`
!> converts the atomic units of `TMolecule%atmass`) and the file is exactly the
!> file the existing run writes for `set%pr_nmtm`.
subroutine write_normal_modes(env, mol, vib)
   character(len=*), parameter :: source = 'landscape_vib_write_normal_modes'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Molecular structure
   type(TMolecule), intent(in) :: mol
   !> Frequency result
   type(landscape_vib_result), intent(in) :: vib

   real(wp), allocatable :: atmass_amu(:)
   character(len=:), allocatable :: fname
   integer :: unit, ierr

   fname = get_namespace('vib_normal_modes')
   open(newunit=unit, file=fname, action='write', iostat=ierr)
   if (ierr /= 0) then
      call env%error("cannot write "//fname, source)
      return
   end if
   allocate(atmass_amu(mol%n), source=0.0_wp)
   atmass_amu = mol%atmass*autoamu
   call writeNormalModesTurbomole(unit, atmass_amu, vib%modes)
   close(unit)

end subroutine write_normal_modes

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

end module xtb_landscape_tasks_vib
