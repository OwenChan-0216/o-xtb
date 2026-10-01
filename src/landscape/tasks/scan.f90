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

!> Scan task of the landscape suite.
!>
!> This is the task level entry point of `--lscan`: it builds the engine,
!> wraps it into the `landscape_engine_model` of `xtb_landscape_tasks_opt`,
!> drives the 1D (`xtb_landscape_scan1d`) or the 2D
!> (`xtb_landscape_scan2d`) scan, writes the scan log and reports the
!> hysteresis and residual diagnostics.
!>
!> The scan log `xtbscan.log` (honouring the `--namespace` prefix) is written
!> frame by frame with `xtb_io_writer::writeMolecule`, exactly like the
!> existing relaxed scan (`src/scan_driver.f90:98,129`).  Every frame carries
!> the **de-biased** electronic energy (`Etot - Efix`), so the file is a drop
!> in replacement for the one produced by `--scan`, and its trajectory
!> semantics are preserved: frames are written in visit order, which for a
!> bidirectional scan includes the reverse branch.
!>
!> Units: coordinates in bohr, energies in hartree, gradients in hartree/bohr.
module xtb_landscape_tasks_scan
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_filetypes, only : fileType
   use xtb_type_environment, only : TEnvironment
   use xtb_type_molecule, only : TMolecule, init
   use xtb_type_restart, only : TRestart
   use xtb_type_calculator, only : TCalculator
   use xtb_io_writer, only : writeMolecule
   use xtb_setparam, only : get_namespace
   use xtb_landscape_settings, only : landscape_scan_settings, &
      & landscape_restart_name, landscape_scan_coord_name, &
      & landscape_missing_value
   use xtb_landscape_results, only : landscape_result
   use xtb_landscape_coords, only : geometry_pack, geometry_unpack
   use xtb_landscape_engine, only : landscape_engine, new_landscape_engine, &
      & landscape_hessian_provider, new_landscape_hessian_provider
   use xtb_landscape_tasks_opt, only : landscape_engine_model
   use xtb_landscape_scan_relax, only : landscape_scan_check
   use xtb_landscape_scan1d, only : landscape_scan_profile, landscape_scan1d, &
      & landscape_scan_profile_write
   use xtb_landscape_scan2d, only : landscape_scan_grid, landscape_scan2d, &
      & landscape_scan_grid_write
   implicit none(type, external)
   private

   public :: landscape_scan

contains

!> Run the scan described by `settings`.
!>
!> On return `mol%xyz` holds the geometry of the lowest energy scan point,
!> `result%energy` that de-biased energy and `result%converged` whether every
!> scan point converged.  Both kinds of incomplete point make it false: a
!> point whose single point failed carries no energy and is reported as an
!> error (exactly like an unconverged minimisation in
!> `xtb_landscape_tasks_opt`), and a point whose inner relaxation stopped
!> without meeting its thresholds still carries its energy but is reported as
!> a warning together with its per point residual.  The flag therefore tells
!> a caller that only inspects it the same thing as the `conv` column of the
!> scan table (`docs/_landscape-recon/17-m2-independent-review.md`
!> section 3.1).
!>
!> A point whose single point was discarded has **no** energy.  It is reported
!> as NaN in the scan table and left out of `xtbscan.log` (a missing frame is
!> honest, a frame carrying `energy: 0.0` or the all-zero geometry of a point
!> that never produced one is not, see
!> `docs/_landscape-recon/14-m2-validation-experiments.md` section 5.3).  When
!> no point at all carries an energy, `result%energy` is NaN as well and the
!> input geometry is left in place instead of being overwritten by a zero
!> frame.
subroutine landscape_scan(env, mol, chk, calc, settings, result)
   character(len=*), parameter :: source = 'landscape_scan'
   !> Computational environment
   type(TEnvironment), intent(inout), target :: env
   !> Molecular structure
   type(TMolecule), intent(inout), target :: mol
   !> Wavefunction data
   type(TRestart), intent(inout), target :: chk
   !> Single point calculator
   class(TCalculator), intent(in) :: calc
   !> Scan settings
   type(landscape_scan_settings), intent(in) :: settings
   !> Scan result
   type(landscape_result), intent(inout) :: result

   type(landscape_engine), target :: engine
   type(landscape_engine_model) :: model
   class(landscape_hessian_provider), allocatable :: hp
   type(landscape_scan_profile) :: profile
   type(landscape_scan_grid) :: grid
   real(wp), allocatable :: x0(:), xbest(:)
   real(wp) :: best_energy, best_residual
   integer :: n_fail, n_unconverged, n_valid, i
   logical :: fail

   if (settings%printlevel > 0) then
      write(env%unit, '(1x,a,a,a)') "landscape: ", trim(settings%mode), &
         & " scan"
      do i = 1, settings%ndim
         write(env%unit, '(1x,a,i0,a,a,4(1x,i0))') "  coordinate ", i, ": ", &
            & trim(landscape_scan_coord_name(settings%coord(i)%ctype)), &
            & settings%coord(i)%atoms(1:4)
      end do
      write(env%unit, '(1x,a,i0)') "number of coordinates:    ", settings%ndim
      write(env%unit, '(1x,a,a)') "restart policy:           ", &
         & landscape_restart_name(settings%engine%restart_mode)
      write(env%unit, '(1x,a,a)') "Hessian source:           ", &
         & trim(settings%hessian_source)
   end if

   ! All preconditions are checked before a single SCF is run, so an invalid
   ! request is reported instead of producing a partial scan.
   if (.not. landscape_scan_check(env, settings, mol%n)) then
      result%message = "invalid scan settings"
      return
   end if

   call new_landscape_engine(engine, settings%engine)
   call new_landscape_hessian_provider(env, settings%hessian_source, hp, &
      & settings%engine%hess_acc)
   if (.not. allocated(hp)) return
   call engine%set_hessian_provider(hp)
   call engine%set_calculator(calc)
   model%engine => engine
   model%env => env
   model%mol => mol
   model%chk => chk

   x0 = geometry_pack(mol%xyz)

   fail = .false.
   allocate(xbest(3*mol%n))
   ! The starting geometry is the fallback: a scan in which no point produced
   ! an energy must not report the all-zero coordinates of an unevaluated
   ! point as its result.
   xbest = x0
   if (settings%ndim == 2) then
      call landscape_scan2d(env, model, mol%at, settings, x0, grid, fail)
      n_fail = grid%n_fail
      n_unconverged = count(.not. grid%converged)
      n_valid = count(grid%energy_valid)
      best_energy = grid%min_energy
      best_residual = 0.0_wp
      if (n_valid > 0) then
         best_residual = grid%residual(grid%min_i, grid%min_j)
         xbest = grid%xyz(:, grid%min_visit)
      end if
      result%n_steps = grid%n_points
   else
      call landscape_scan1d(env, model, mol%at, settings, x0, profile, fail)
      n_fail = profile%n_fail
      n_unconverged = count(.not. profile%converged)
      n_valid = 0
      best_energy = landscape_missing_value()
      best_residual = 0.0_wp
      do i = 1, profile%n_points
         if (.not. profile%converged(i)) cycle
         if (.not. profile%energy_valid(i)) cycle
         n_valid = n_valid + 1
         if (n_valid == 1 .or. profile%energy(i) < best_energy) then
            best_energy = profile%energy(i)
            best_residual = profile%residual(i)
            xbest = profile%xyz(:, i)
         end if
      end do
      result%n_steps = profile%n_points
   end if

   result%n_eval = engine%n_eval
   result%n_cache_miss = engine%n_eval
   result%energy = best_energy
   result%gnorm = best_residual
   result%gmax = best_residual
   ! Every scan point, not merely every evaluated one: a point whose inner
   ! relaxation stopped short keeps its energy and only reaches the warning
   ! below, so it has to make the aggregate flag false as well.
   result%converged = (n_fail == 0) .and. (n_unconverged == 0)

   call geometry_unpack(xbest, mol%xyz)

   if (settings%printlevel > 0) then
      if (settings%ndim == 2) then
         call landscape_scan_grid_write(grid, env%unit, settings%coord(1)%ctype, &
            & settings%coord(2)%ctype)
      else
         call landscape_scan_profile_write(profile, env%unit, &
            & settings%coord(1)%ctype)
         write(env%unit, '(1x,a,es15.6,a)') "lowest energy: ", best_energy, " Eh"
      end if
      call engine%report(env%unit)
   end if

   if (settings%write_files) then
      if (settings%ndim == 2) then
         call write_scan_grid(env, mol, settings, grid)
      else
         call write_scan_profile(env, mol, settings, profile)
      end if
   end if

   call engine%destroy()

   if (n_fail > 0) then
      result%message = "some scan points failed"
      call env%error("landscape scan aborted: "//int_to_string(n_fail)//&
         & " of "//int_to_string(result%n_steps)//" scan points failed (no "//&
         & "energy; the failed points are the NaN rows of the scan table)", &
         & source)
   else if (n_unconverged > 0) then
      ! An inner relaxation that hit its step budget is not a hard failure - a
      ! scan point may legitimately converge loosely - but it has to be
      ! visible, because the constraint residual of such a point is non-zero
      ! (PLAN R-04).
      result%message = "scan completed with unconverged points"
      call env%warning(int_to_string(n_unconverged)//" scan point(s) did "//&
         & "not converge; check the reported residual", source)
   else
      result%message = "scan completed"
   end if

end subroutine landscape_scan

!> Write the 1D scan log, one xyz frame per point with a de-biased energy.
!>
!> Only points that carry an energy are written.  A point whose single point
!> was discarded has neither an energy nor, necessarily, a meaningful
!> geometry (a point that failed before its first step keeps a zero frame), so
!> it is left out instead of producing a frame with a fabricated `0.0` energy.
subroutine write_scan_profile(env, mol, settings, profile)
   character(len=*), parameter :: source = 'landscape_write_scan_profile'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Molecular structure (atom identities are copied from it)
   type(TMolecule), intent(in) :: mol
   !> Scan settings
   type(landscape_scan_settings), intent(in) :: settings
   !> Scan profile
   type(landscape_scan_profile), intent(in) :: profile

   type(TMolecule) :: buffer
   character(len=:), allocatable :: fname
   integer :: unit, ierr, iframe, nframe, nomitted

   fname = get_namespace('xtbscan.log')
   ! `status='replace'`: a scan that omits every frame (no point produced an
   ! energy) has to leave an empty log, not the frames of an earlier run - an
   ! open without `replace` keeps the old records until a new one is written.
   open(newunit=unit, file=fname, action='write', status='replace', iostat=ierr)
   if (ierr /= 0) then
      call env%error("cannot open "//fname, source)
      return
   end if
   ! The buffer is rebuilt with `init` instead of a derived type assignment,
   ! see the comment in `xtb_landscape_log::landscape_write_files`.
   call init(buffer, mol%at, mol%xyz, chrg=mol%chrg, uhf=mol%uhf, &
      & lattice=mol%lattice, pbc=mol%pbc)
   nframe = 0
   nomitted = 0
   do iframe = 1, profile%n_points
      if (.not. profile%energy_valid(iframe)) then
         nomitted = nomitted + 1
         cycle
      end if
      nframe = nframe + 1
      call geometry_unpack(profile%xyz(:, iframe), buffer%xyz)
      call writeMolecule(buffer, unit, format=fileType%xyz, &
         & energy=profile%energy(iframe), number=nframe)
   end do
   close(unit)
   write(env%unit, '(1x,a,a,a,i0,a,i0,a)') "wrote ", fname, " with ", nframe, &
      & " frame(s), ", nomitted, " failed point(s) omitted"

end subroutine write_scan_profile

!> Write the 2D scan log, one xyz frame per visited grid point with a
!> de-biased energy; failed grid points are omitted (see
!> `write_scan_profile`).
subroutine write_scan_grid(env, mol, settings, grid)
   character(len=*), parameter :: source = 'landscape_write_scan_grid'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Molecular structure (atom identities are copied from it)
   type(TMolecule), intent(in) :: mol
   !> Scan settings
   type(landscape_scan_settings), intent(in) :: settings
   !> Scan grid
   type(landscape_scan_grid), intent(in) :: grid

   type(TMolecule) :: buffer
   character(len=:), allocatable :: fname
   integer :: unit, ierr, iframe, nframe, nomitted

   fname = get_namespace('xtbscan.log')
   ! See `write_scan_profile` for the `replace` of the previous log.
   open(newunit=unit, file=fname, action='write', status='replace', iostat=ierr)
   if (ierr /= 0) then
      call env%error("cannot open "//fname, source)
      return
   end if
   call init(buffer, mol%at, mol%xyz, chrg=mol%chrg, uhf=mol%uhf, &
      & lattice=mol%lattice, pbc=mol%pbc)
   ! The frames carry the energy of the point whose grid indices are read from
   ! the visit order, so the file is consistent with the serpentine traversal.
   nframe = 0
   nomitted = 0
   do iframe = 1, grid%n_points
      if (.not. grid%energy_valid(grid%visit_i(iframe), grid%visit_j(iframe))) then
         nomitted = nomitted + 1
         cycle
      end if
      nframe = nframe + 1
      call geometry_unpack(grid%xyz(:, iframe), buffer%xyz)
      call writeMolecule(buffer, unit, format=fileType%xyz, &
         & energy=grid%energy(grid%visit_i(iframe), grid%visit_j(iframe)), &
         & number=nframe)
   end do
   close(unit)
   write(env%unit, '(1x,a,a,a,i0,a,i0,a)') "wrote ", fname, " with ", nframe, &
      & " frame(s), ", nomitted, " failed point(s) omitted"

end subroutine write_scan_grid

!> Decimal representation of an integer for an error message.
function int_to_string(value) result(string)
   !> Value to convert
   integer, intent(in) :: value
   !> Decimal string
   character(len=:), allocatable :: string

   character(len=16) :: buffer

   write(buffer, '(i0)') value
   string = trim(buffer)

end function int_to_string

end module xtb_landscape_tasks_scan
