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

!> Failure path coverage of the landscape minimisation core.
!>
!> The other test modules only exercise runs that converge; this module injects
!> the failure modes that a real driver has to survive: an objective that
!> reports failure, a step budget of zero or one, a potential along which every
!> trial step increases the energy, and non-finite input or output.  The tests
!> assert the termination state (`converged`, `message`, `n_steps`) and that the
!> run never loops forever, which is what turns the error handling into
!> testable behaviour.
module test_landscape_failure
   use testdrive, only : new_unittest, unittest_type, error_type, check
   use, intrinsic :: ieee_arithmetic, only : ieee_value, ieee_quiet_nan, &
      & ieee_positive_inf
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_io, only : stdout
   use xtb_type_environment
   use xtb_type_molecule, only : TMolecule, init
   use xtb_type_restart, only : TRestart
   use xtb_landscape_settings, only : landscape_opt_settings, &
      & landscape_engine_control, landscape_log_failed, &
      & p_landscape_opt_lbfgs, p_landscape_opt_bfgs, p_landscape_opt_diis
   use xtb_landscape_results, only : landscape_result
   use xtb_landscape_engine, only : landscape_energy_model, landscape_engine, &
      & new_landscape_engine
   use xtb_landscape_log, only : landscape_write_files
   use xtb_landscape_optimize, only : landscape_optimize_model
   implicit none
   private

   public :: collect_landscape_failure

   !> Number of stagnated iterations the driver tolerates before it gives up
   !> (`xtb_landscape_optimize::stagnate_patience`)
   integer, parameter :: stagnate_patience = 10

   !> Objective that always reports failure from the first evaluation
   type, extends(landscape_energy_model) :: landscape_failing_model
   contains
      !> Energy and gradient (always fails)
      procedure :: evaluate => failing_evaluate
      !> Hessian (always fails)
      procedure :: hessian => failing_hessian
   end type landscape_failing_model

   !> Objective whose gradient points at an increasing energy, so that every
   !> trial step is rejected by the line search (a deliberately inconsistent
   !> model, used to force the steepest descent backstop and the stagnation
   !> guard)
   type, extends(landscape_energy_model) :: landscape_uphill_model
   contains
      !> Energy `1/2 sum x^2`, gradient `+1` everywhere
      procedure :: evaluate => uphill_evaluate
      !> Identity Hessian
      procedure :: hessian => uphill_hessian
   end type landscape_uphill_model

   !> Objective that returns non-finite values from the first evaluation
   type, extends(landscape_energy_model) :: landscape_nonfinite_model
      !> Return NaN instead of finite values
      logical :: emit_nan = .true.
   contains
      !> Energy and gradient, `NaN` when `emit_nan` is set
      procedure :: evaluate => nonfinite_evaluate
      !> Identity Hessian
      procedure :: hessian => nonfinite_hessian
   end type landscape_nonfinite_model

contains

!> Collect all exported unit tests
subroutine collect_landscape_failure(testsuite)
   !> Collection of tests
   type(unittest_type), allocatable, intent(out) :: testsuite(:)

   testsuite = [ &
      new_unittest("objective-failure", test_objective_failure), &
      new_unittest("step-budget", test_step_budget), &
      new_unittest("uphill-stagnation", test_uphill_stagnation), &
      new_unittest("non-finite-input", test_non_finite_input), &
      new_unittest("non-finite-output", test_non_finite_output), &
      new_unittest("invalid-restart-mode", test_invalid_restart_mode), &
      new_unittest("write-files-open-failure", test_write_files_open_failure) &
      ]

end subroutine collect_landscape_failure

!> An objective that fails on the first call must be reported, not crash.
subroutine test_objective_failure(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_failing_model) :: model
   type(landscape_opt_settings) :: set
   type(landscape_result) :: result
   real(wp), parameter :: xstart(3) = [0.1_wp, -0.2_wp, 0.3_wp]
   real(wp), allocatable :: xfinal(:)

   call init(env)
   set = landscape_opt_settings()
   set%algorithm = p_landscape_opt_lbfgs
   set%max_steps = 50
   set%printlevel = 0
   set%write_files = .false.

   call landscape_optimize_model(env, model, set, xstart, result, xfinal)

   call check(error, .not. result%converged)
   if (allocated(error)) return
   call check(error, allocated(result%message))
   if (allocated(error)) return
   call check(error, result%message, "initial energy evaluation failed")
   if (allocated(error)) return
   call check(error, result%n_steps, 0)
   if (allocated(error)) return
   ! the starting geometry is returned unchanged, nothing was attempted
   call check(error, allocated(xfinal))
   if (allocated(error)) return
   call check(error, maxval(abs(xfinal - xstart)), 0.0_wp)

end subroutine test_objective_failure

!> A step budget of zero or one must terminate with the documented message and
!> must not be reported as converged.
subroutine test_step_budget(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_uphill_model) :: uphill
   type(landscape_nonfinite_model) :: finite
   type(landscape_opt_settings) :: set
   type(landscape_result) :: result
   real(wp), parameter :: xstart(2) = [1.0_wp, -1.0_wp]
   real(wp), allocatable :: xfinal(:)

   ! a well behaved quadratic to make sure the budgets, not the objective,
   ! decide the outcome
   finite%emit_nan = .false.
   call init(env)
   set = landscape_opt_settings()
   set%algorithm = p_landscape_opt_lbfgs
   set%printlevel = 0
   set%write_files = .false.

   set%max_steps = 0
   call landscape_optimize_model(env, finite, set, xstart, result, xfinal)
   call check(error, .not. result%converged, "max_steps = 0 must not converge")
   if (allocated(error)) return
   call check(error, allocated(result%message))
   if (allocated(error)) return
   call check(error, result%message, "no step performed")
   if (allocated(error)) return
   call check(error, result%n_steps, 0)
   if (allocated(error)) return

   set%max_steps = 1
   call landscape_optimize_model(env, finite, set, xstart, result, xfinal)
   call check(error, .not. result%converged, "max_steps = 1 must not converge")
   if (allocated(error)) return
   call check(error, allocated(result%message))
   if (allocated(error)) return
   call check(error, result%message, "maximum number of steps reached")
   if (allocated(error)) return
   call check(error, result%n_steps, 1)

end subroutine test_step_budget

!> A potential along which every trial step increases the energy must exhaust
!> the steepest descent backstop and terminate through the stagnation guard
!> without moving the geometry.
subroutine test_uphill_stagnation(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_uphill_model) :: model
   type(landscape_opt_settings) :: set
   type(landscape_result) :: result
   real(wp), parameter :: xstart(3) = [0.0_wp, 0.0_wp, 0.0_wp]
   real(wp), allocatable :: xfinal(:)

   call init(env)
   set = landscape_opt_settings()
   set%algorithm = p_landscape_opt_lbfgs
   set%max_steps = 5000
   set%printlevel = 0
   set%write_files = .false.

   call landscape_optimize_model(env, model, set, xstart, result, xfinal)

   call check(error, .not. result%converged)
   if (allocated(error)) return
   call check(error, allocated(result%message))
   if (allocated(error)) return
   call check(error, result%message, "stagnated: no acceptable step found")
   if (allocated(error)) return
   ! the run stops after the patience is exhausted instead of looping forever
   call check(error, result%n_steps, stagnate_patience)
   if (allocated(error)) return
   ! the backstop was actually exercised (rejected, so no accepted fallback)
   call check(error, any(result%steps(:)%fallback))
   if (allocated(error)) return
   call check(error, result%n_fallback, 0)
   if (allocated(error)) return
   ! no displacement was accepted
   call check(error, allocated(xfinal))
   if (allocated(error)) return
   call check(error, maxval(abs(xfinal - xstart)), 0.0_wp)

end subroutine test_uphill_stagnation

!> A non-finite starting geometry must be rejected before it poisons the line
!> search and the convergence test.
subroutine test_non_finite_input(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_nonfinite_model) :: model
   type(landscape_opt_settings) :: set
   type(landscape_result) :: result
   real(wp) :: xstart(3), nan
   real(wp), allocatable :: xfinal(:)

   call init(env)
   model%emit_nan = .false.
   nan = ieee_value(0.0_wp, ieee_quiet_nan)
   set = landscape_opt_settings()
   set%algorithm = p_landscape_opt_lbfgs
   set%max_steps = 50
   set%printlevel = 0
   set%write_files = .false.

   xstart = [nan, 0.0_wp, 0.0_wp]
   call landscape_optimize_model(env, model, set, xstart, result, xfinal)
   call check(error, .not. result%converged)
   if (allocated(error)) return
   call check(error, allocated(result%message))
   if (allocated(error)) return
   call check(error, result%message, "initial coordinates are not finite")
   if (allocated(error)) return
   call check(error, .not. allocated(xfinal))
   if (allocated(error)) return

   xstart = [0.0_wp, ieee_value(0.0_wp, ieee_positive_inf), 0.0_wp]
   call landscape_optimize_model(env, model, set, xstart, result, xfinal)
   call check(error, .not. result%converged)
   if (allocated(error)) return
   call check(error, result%message, "initial coordinates are not finite")

end subroutine test_non_finite_input

!> An objective that returns NaN from the first evaluation must be reported
!> instead of producing NaN throughout the run.
subroutine test_non_finite_output(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_nonfinite_model) :: model
   type(landscape_opt_settings) :: set
   type(landscape_result) :: result
   real(wp), parameter :: xstart(3) = [0.1_wp, -0.2_wp, 0.3_wp]
   real(wp), allocatable :: xfinal(:)

   call init(env)
   model%emit_nan = .true.
   set = landscape_opt_settings()
   set%algorithm = p_landscape_opt_lbfgs
   set%max_steps = 50
   set%printlevel = 0
   set%write_files = .false.

   call landscape_optimize_model(env, model, set, xstart, result, xfinal)

   call check(error, .not. result%converged)
   if (allocated(error)) return
   call check(error, allocated(result%message))
   if (allocated(error)) return
   call check(error, result%message, "initial energy or gradient is not finite")
   if (allocated(error)) return
   call check(error, result%n_steps, 0)

end subroutine test_non_finite_output

!> An unknown restart mode must be reported instead of silently degrading to
!> `warm` (the old `select case` had no `case default`).
subroutine test_invalid_restart_mode(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(landscape_engine) :: engine
   type(landscape_engine_control) :: ctrl
   character(len=*), parameter :: sym(1) = ["H"]
   real(wp), parameter :: xyz(3, 1) = reshape([0.0_wp, 0.0_wp, 0.0_wp], [3, 1])
   integer :: nlog

   call init(env)
   call init(mol, sym, xyz)
   ctrl = landscape_engine_control()
   ctrl%restart_mode = 99
   call new_landscape_engine(engine, ctrl)

   nlog = env%nLog
   call engine%apply_restart(env, mol, chk)
   call check(error, landscape_log_failed(env, nlog), &
      & "an unknown restart mode was not reported")
   if (allocated(error)) return
   call engine%destroy()

end subroutine test_invalid_restart_mode

!> `landscape_write_files` must report an output file it cannot open instead of
!> returning silently.
subroutine test_write_files_open_failure(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(landscape_opt_settings) :: set
   type(landscape_result) :: result
   real(wp), allocatable :: traj(:, :)
   character(len=*), parameter :: sym(1) = ["H"]
   real(wp), parameter :: xyz(3, 1) = reshape([0.0_wp, 0.0_wp, 0.0_wp], [3, 1])
   integer :: nlog

   call init(env)
   call init(mol, sym, xyz)
   set = landscape_opt_settings()
   ! a prefix in a directory that does not exist -> the first `open` fails
   set%output_prefix = '/nonexistent-landscape-dir/output'
   result%energy = -1.0_wp

   nlog = env%nLog
   call landscape_write_files(env, mol, set, traj, result)
   call check(error, landscape_log_failed(env, nlog), &
      & "the unopenable output file was not reported")

end subroutine test_write_files_open_failure

!> Energy and gradient of the always-failing objective.
subroutine failing_evaluate(self, x, energy, gradient, fail)
   !> Objective
   class(landscape_failing_model), intent(inout) :: self
   !> Coordinates (bohr)
   real(wp), intent(in) :: x(:)
   !> Energy (hartree)
   real(wp), intent(out) :: energy
   !> Gradient (hartree/bohr)
   real(wp), intent(out) :: gradient(:)
   !> Failure flag
   logical, intent(out) :: fail

   fail = .true.
   energy = 0.0_wp
   gradient = 0.0_wp

end subroutine failing_evaluate

!> Hessian of the always-failing objective.
subroutine failing_hessian(self, x, hess, fail)
   !> Objective
   class(landscape_failing_model), intent(inout) :: self
   !> Coordinates (bohr)
   real(wp), intent(in) :: x(:)
   !> Hessian (hartree/bohr^2)
   real(wp), intent(out) :: hess(:, :)
   !> Failure flag
   logical, intent(out) :: fail

   fail = .true.
   hess = 0.0_wp

end subroutine failing_hessian

!> Energy and gradient of the uphill objective.
!>
!> The energy is a well behaved quadratic `1/2 sum x^2`, but the gradient is
!> the constant `+1`.  Moving along `-gradient` therefore always increases the
!> energy (it pushes every component away from the origin), which makes the
!> Armijo line search reject every trial step.
subroutine uphill_evaluate(self, x, energy, gradient, fail)
   !> Objective
   class(landscape_uphill_model), intent(inout) :: self
   !> Coordinates (bohr)
   real(wp), intent(in) :: x(:)
   !> Energy (hartree)
   real(wp), intent(out) :: energy
   !> Gradient (hartree/bohr)
   real(wp), intent(out) :: gradient(:)
   !> Failure flag
   logical, intent(out) :: fail

   fail = .false.
   energy = 0.5_wp*sum(x**2)
   gradient = 1.0_wp

end subroutine uphill_evaluate

!> Identity Hessian of the uphill objective.
subroutine uphill_hessian(self, x, hess, fail)
   !> Objective
   class(landscape_uphill_model), intent(inout) :: self
   !> Coordinates (bohr)
   real(wp), intent(in) :: x(:)
   !> Hessian (hartree/bohr^2)
   real(wp), intent(out) :: hess(:, :)
   !> Failure flag
   logical, intent(out) :: fail

   fail = .false.
   call fill_identity_hessian(hess)

end subroutine uphill_hessian

!> Identity Hessian of the non-finite objective.
subroutine nonfinite_hessian(self, x, hess, fail)
   !> Objective
   class(landscape_nonfinite_model), intent(inout) :: self
   !> Coordinates (bohr)
   real(wp), intent(in) :: x(:)
   !> Hessian (hartree/bohr^2)
   real(wp), intent(out) :: hess(:, :)
   !> Failure flag
   logical, intent(out) :: fail

   fail = .false.
   call fill_identity_hessian(hess)

end subroutine nonfinite_hessian

!> Overwrite `hess` with the identity matrix.
subroutine fill_identity_hessian(hess)
   !> Hessian (hartree/bohr^2)
   real(wp), intent(out) :: hess(:, :)

   integer :: i

   hess = 0.0_wp
   do i = 1, min(size(hess, 1), size(hess, 2))
      hess(i, i) = 1.0_wp
   end do

end subroutine fill_identity_hessian

!> Energy and gradient of the configurable non-finite objective.
subroutine nonfinite_evaluate(self, x, energy, gradient, fail)
   !> Objective
   class(landscape_nonfinite_model), intent(inout) :: self
   !> Coordinates (bohr)
   real(wp), intent(in) :: x(:)
   !> Energy (hartree)
   real(wp), intent(out) :: energy
   !> Gradient (hartree/bohr)
   real(wp), intent(out) :: gradient(:)
   !> Failure flag
   logical, intent(out) :: fail

   fail = .false.
   if (self%emit_nan) then
      energy = ieee_value(0.0_wp, ieee_quiet_nan)
      gradient = ieee_value(0.0_wp, ieee_quiet_nan)
   else
      energy = 0.5_wp*sum(x**2)
      gradient = x
   end if

end subroutine nonfinite_evaluate

end module test_landscape_failure
