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

!> Geometry minimisation task of the landscape suite.
!>
!> This is the task level entry point: it builds the engine, wraps it into a
!> `landscape_energy_model`, runs the pure mathematical core
!> `xtb_landscape_optimize::landscape_optimize_model` and delegates the
!> geometry/trajectory output to `xtb_landscape_log::landscape_write_files`.
!> It is the only part of the landscape suite that holds the xtb private types
!> (`TMolecule`, `TRestart`, `TCalculator`), keeping the `optimize/**` layer
!> free of them (PLAN section 4.2).
!>
!> Units: coordinates in bohr, energies in hartree, gradients in hartree/bohr.
module xtb_landscape_tasks_opt
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_convert, only : autokcal
   use xtb_type_environment, only : TEnvironment
   use xtb_type_molecule, only : TMolecule
   use xtb_type_restart, only : TRestart
   use xtb_type_calculator, only : TCalculator
   use xtb_landscape_settings, only : landscape_opt_settings, &
      & landscape_opt_algorithm_name, landscape_restart_name
   use xtb_landscape_results, only : landscape_result
   use xtb_landscape_coords, only : geometry_pack, geometry_unpack
   use xtb_landscape_engine, only : landscape_engine, new_landscape_engine, &
      & landscape_energy_model, landscape_hessian_provider, &
      & new_landscape_hessian_provider
   use xtb_landscape_optimize, only : landscape_optimize_model
   use xtb_landscape_constraints, only : landscape_frozen_mask
   use xtb_landscape_log, only : landscape_write_files
   use xtb_landscape_json, only : landscape_json_document, &
      & landscape_json_document_init, landscape_json_add_result, &
      & landscape_json_add_counter, landscape_json_add_value, &
      & landscape_json_write, landscape_json_status_ok, &
      & landscape_json_status_incomplete, landscape_json_status_error
   implicit none(type, external)
   private

   public :: landscape_optimize
   public :: landscape_engine_model

   !> Engine backed potential, bridges the abstract optimiser objective to
   !> `landscape_engine`.
   type, extends(landscape_energy_model) :: landscape_engine_model
      !> Engine performing the energy/gradient evaluation
      type(landscape_engine), pointer :: engine => null()
      !> Computational environment
      type(TEnvironment), pointer :: env => null()
      !> Molecular structure used by the engine
      type(TMolecule), pointer :: mol => null()
      !> Wavefunction data used by the engine
      type(TRestart), pointer :: chk => null()
   contains
      !> Energy and gradient through the engine
      procedure :: evaluate => engine_model_evaluate
      !> Hessian through the engine
      procedure :: hessian => engine_model_hessian
   end type landscape_engine_model

contains

!> Task level entry point: minimise the geometry of `mol` with the calculator
!> `calc`.
!>
!> The engine owns a copy of the calculator, evaluates through
!> `xtb_single::singlepoint` and caches repeated geometries.  On return
!> `mol%xyz` holds the minimised geometry.  The engine restart policy is
!> printed because the default (`off`) determines the level of numerical
!> noise of the gradient.
subroutine landscape_optimize(env, mol, chk, calc, settings, result)
   character(len=*), parameter :: source = 'landscape_optimize'
   !> Computational environment
   type(TEnvironment), intent(inout), target :: env
   !> Molecular structure, updated to the minimised geometry
   type(TMolecule), intent(inout), target :: mol
   !> Wavefunction data
   type(TRestart), intent(inout), target :: chk
   !> Single point calculator
   class(TCalculator), intent(in) :: calc
   !> Optimisation settings
   type(landscape_opt_settings), intent(in) :: settings
   !> Optimisation result
   type(landscape_result), intent(inout) :: result

   type(landscape_engine), target :: engine
   type(landscape_engine_model) :: model
   class(landscape_hessian_provider), allocatable :: hp
   real(wp), allocatable :: x0(:), xfinal(:), traj(:, :)
   logical, allocatable :: fix_mask(:)
   integer :: n_scf_fail

   if (settings%printlevel > 0) then
      write(env%unit, '(1x,a,a,a)') "landscape: ", &
         & landscape_opt_algorithm_name(settings%algorithm), " minimisation"
      write(env%unit, '(1x,a,es15.6,a)') "gradient threshold (max): ", &
         & settings%g_max, " Eh/bohr"
      write(env%unit, '(1x,a,i0)') "maximum number of steps:  ", settings%max_steps
      write(env%unit, '(1x,a,a)') "restart policy:           ", &
         & landscape_restart_name(settings%engine%restart_mode)
      write(env%unit, '(1x,a,a)') "Hessian source:           ", &
         & trim(settings%hessian_source)
   end if

   call new_landscape_engine(engine, settings%engine)
   ! The provider factory reports an unknown `hessian_source`; the caller must
   ! abort instead of silently running with the default provider.
   call new_landscape_hessian_provider(env, settings%hessian_source, hp, &
      & sccacc=settings%engine%hess_acc, filename=settings%hessian_file)
   if (.not. allocated(hp)) return
   call engine%set_hessian_provider(hp)
   call engine%set_calculator(calc)
   model%engine => engine
   model%env => env
   model%mol => mol
   model%chk => chk

   x0 = geometry_pack(mol%xyz)
   ! `$fix`: every search direction is projected onto the subspace the fixed
   ! atoms leave free, so a second order step cannot move them.
   fix_mask = landscape_frozen_mask(mol%n)
   if (any(fix_mask)) then
      write(env%unit, '(1x,a,i0,a)') "fixed atoms ($fix):       ", &
         & count(fix_mask)/3, " (three components each)"
   end if
   call landscape_optimize_model(env, model, settings, x0, result, xfinal, traj, &
      & frozen=fix_mask)
   if (.not. allocated(xfinal)) then
      call env%error("landscape optimisation did not return a geometry", source)
      call engine%destroy()
      return
   end if

   call geometry_unpack(xfinal, mol%xyz)
   ! `result%n_eval` counts every objective evaluation (including cache hits);
   ! the number of evaluations that actually ran a single point is reported
   ! separately as the engine cache misses.
   result%n_cache_miss = engine%n_eval
   n_scf_fail = engine%n_scf_fail
   ! M4 hard constraint 1: the effective electronic temperature is part of the
   ! result object (read back from the calculator), not only of the printed
   ! engine report.
   result%etemp = engine%effective_etemp()

   if (settings%printlevel > 0) then
      call result%write_log(env%unit)
      call result%conv%write_log(env%unit)
      call engine%report(env%unit)
   end if

   if (settings%write_files) then
      call landscape_write_files(env, mol, settings, traj, result)
   end if

   if (settings%ljson) call write_json(env, result, n_scf_fail)

   call engine%destroy()

   ! Any unconverged SCC along the minimisation is an error: the engine refused
   ! to return the affected energy/gradient (`engine_energy_gradient`), so the
   ! reported geometry cannot be trusted.  The escalation happens here (and not
   ! in the engine) because only the task knows whether the run as a whole may
   ! continue; the caller (`run_landscape` from `src/prog/main.F90`) turns any
   ! logged error into a non-zero exit status.
   if (n_scf_fail > 0) then
      call env%error("landscape minimisation aborted: the SCC did not "//&
         & "converge at least once", source)
   end if

   ! A non-converged minimisation is an error: the caller (`run_landscape` from
   ! `src/prog/main.F90`) turns it into a non-zero exit status, exactly like the
   ! existing ANC optimiser does on failure.
   if (.not. result%converged) then
      if (allocated(result%message)) then
         call env%error("landscape minimisation did not converge: "//&
            & result%message, source)
      else
         call env%error("landscape minimisation did not converge", source)
      end if
   end if

end subroutine landscape_optimize

!> Write the structured result `landscape_opt.json`.
!>
!> `n_scf_fail` separates "the minimisation stopped short" (status
!> `incomplete`, the caller may still look at the geometry) from "the run is
!> not trustworthy" (status `error`, the energy/gradient pair of an
!> unconverged SCC was never accepted by the engine).
subroutine write_json(env, result, n_scf_fail)
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Minimisation result
   type(landscape_result), intent(in) :: result
   !> Number of unconverged SCCs of the run
   integer, intent(in) :: n_scf_fail

   type(landscape_json_document) :: doc = landscape_json_document()
   logical :: ok
   integer :: status

   status = landscape_json_status_ok
   if (.not. result%converged) status = landscape_json_status_incomplete
   if (n_scf_fail > 0) status = landscape_json_status_error
   call landscape_json_document_init(doc, 'opt')
   call landscape_json_add_result(doc, result, status)
   call landscape_json_add_counter(doc, 'n_fallback', result%n_fallback)
   call landscape_json_add_value(doc, 'kcal_per_mol', result%energy*autokcal)
   call landscape_json_write(env, doc, ok)

end subroutine write_json

!> Energy and gradient of the engine backed model at the flattened coordinates.
subroutine engine_model_evaluate(self, x, energy, gradient, fail)
   !> Engine backed model
   class(landscape_engine_model), intent(inout) :: self
   !> Flattened coordinates (bohr)
   real(wp), intent(in) :: x(:)
   !> Total energy (hartree)
   real(wp), intent(out) :: energy
   !> Flattened gradient (hartree/bohr)
   real(wp), intent(out) :: gradient(:)
   !> Failure flag
   logical, intent(out) :: fail

   real(wp), allocatable :: gmat(:, :)

   fail = .false.
   allocate(gmat(3, self%mol%n))
   call geometry_unpack(x, self%mol%xyz)
   call self%engine%energy_gradient(self%env, self%mol, self%chk, energy, gmat, fail)
   if (fail) then
      gradient = 0.0_wp
      return
   end if
   gradient = geometry_pack(gmat)

end subroutine engine_model_evaluate

!> Hessian of the engine backed model at the flattened coordinates.
subroutine engine_model_hessian(self, x, hess, fail)
   !> Engine backed model
   class(landscape_engine_model), intent(inout) :: self
   !> Flattened coordinates (bohr)
   real(wp), intent(in) :: x(:)
   !> Dense Hessian (hartree/bohr^2)
   real(wp), intent(out) :: hess(:, :)
   !> Failure flag
   logical, intent(out) :: fail

   call geometry_unpack(x, self%mol%xyz)
   call self%engine%hessian(self%env, self%mol, self%chk, hess, fail)

end subroutine engine_model_hessian

end module xtb_landscape_tasks_opt
