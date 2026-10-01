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

!> Tests of the Polak-Ribiere+ conjugate gradient minimiser.
!>
!> The direction recursion is checked against hand computed reference values and
!> both restart paths of the method (negative Polak-Ribiere coefficient, not a
!> descent direction) are exercised explicitly.  The step count is then compared
!> with steepest descent on a strongly convex quadratic.
!>
!> The quadratic is deliberately ill conditioned (force constants
!> `(0.1, 1, 10, 100)`, condition number 1000): the conjugate gradient is the
!> method of choice for exactly that regime.  On mildly conditioned problems the
!> suite's Armijo backtracking (no curvature condition) limits the benefit, so
!> the step count is reported for those cases instead of being asserted.
module test_landscape_cg
   use testdrive, only : new_unittest, unittest_type, error_type, check
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_io, only : stdout
   use xtb_type_environment
   use xtb_landscape_settings, only : landscape_opt_settings, &
      & p_landscape_opt_sd, p_landscape_opt_cg, p_landscape_opt_lbfgs
   use xtb_landscape_results, only : landscape_result
   use xtb_landscape_cg, only : landscape_cg_type, new_landscape_cg
   use xtb_landscape_testpot, only : landscape_harmonic_model, new_harmonic_model
   use xtb_landscape_optimize, only : landscape_optimize_model
   implicit none
   private

   !> Force constants of the asserted comparison (condition number 1000)
   real(wp), parameter :: k_stiff(4) = [0.1_wp, 1.0_wp, 10.0_wp, 100.0_wp]
   !> Force constants of the reported, mildly conditioned case
   real(wp), parameter :: k_mild(4) = [1.0_wp, 2.0_wp, 4.0_wp, 8.0_wp]
   !> Starting point of both comparisons (bohr)
   real(wp), parameter :: xstart(4) = [1.0_wp, 1.0_wp, 1.0_wp, 1.0_wp]
   !> Exact minimiser of both potentials (bohr)
   real(wp), parameter :: xref(4) = 0.0_wp

   public :: collect_landscape_cg

contains

!> Collect all exported unit tests
subroutine collect_landscape_cg(testsuite)
   !> Collection of tests
   type(unittest_type), allocatable, intent(out) :: testsuite(:)

   testsuite = [ &
      new_unittest("direction-prp-plus", test_direction_prp_plus), &
      new_unittest("restart-negative-beta", test_restart_negative_beta), &
      new_unittest("restart-non-descent", test_restart_non_descent), &
      new_unittest("reset-history", test_reset_history), &
      new_unittest("quadratic-anisotropic", test_quadratic_anisotropic) &
      ]

end subroutine collect_landscape_cg

!> The PRP+ direction must reproduce the hand computed reference value.
!>
!> With `g_{k-1} = (1, 0)`, `d_{k-1} = (-1, 0)` and `g_k = (0, 1)`:
!> `beta = max(0, g_k.(g_k - g_{k-1})/|g_{k-1}|^2) = 1` and hence
!> `d_k = -g_k + beta d_{k-1} = (-1, -1)`.
subroutine test_direction_prp_plus(error)
   type(error_type), allocatable, intent(out) :: error
   type(landscape_cg_type) :: cg
   real(wp) :: direction(2)
   logical :: restarted

   call new_landscape_cg(cg, 2)
   call check(error, cg%has_history, .false.)
   if (allocated(error)) return

   call cg%push([1.0_wp, 0.0_wp], [-1.0_wp, 0.0_wp])
   call cg%direction([0.0_wp, 1.0_wp], direction, restarted)

   call check(error, restarted, .false.)
   if (allocated(error)) return
   call check(error, direction(1), -1.0_wp)
   if (allocated(error)) return
   call check(error, direction(2), -1.0_wp)
   if (allocated(error)) return
   call check(error, cg%n_restart, 0)
   if (allocated(error)) return

   ! no history: the first direction is the steepest descent direction
   call new_landscape_cg(cg, 2)
   call cg%direction([1.0_wp, 2.0_wp], direction, restarted)
   call check(error, restarted, .true.)
   if (allocated(error)) return
   call check(error, direction(1), -1.0_wp)
   if (allocated(error)) return
   call check(error, direction(2), -2.0_wp)
   if (allocated(error)) return
   call check(error, cg%n_restart, 1)

end subroutine test_direction_prp_plus

!> A negative Polak-Ribiere coefficient is truncated to zero
!> (`beta = max(0, beta_PR)`, Nocedal & Wright, Algorithm 5.4), which restarts
!> the method with the steepest descent direction.
!>
!> `g_{k-1} = (2, 0)`, `g_k = (1, 0)` gives
!> `beta_PR = g_k.(g_k - g_{k-1})/|g_{k-1}|^2 = -1/4 < 0`.
subroutine test_restart_negative_beta(error)
   type(error_type), allocatable, intent(out) :: error
   type(landscape_cg_type) :: cg
   real(wp) :: direction(2)
   logical :: restarted

   call new_landscape_cg(cg, 2)
   call cg%push([2.0_wp, 0.0_wp], [-2.0_wp, 0.0_wp])
   call cg%direction([1.0_wp, 0.0_wp], direction, restarted)

   call check(error, restarted, .true.)
   if (allocated(error)) return
   call check(error, direction(1), -1.0_wp)
   if (allocated(error)) return
   call check(error, direction(2), 0.0_wp)
   if (allocated(error)) return
   call check(error, cg%n_restart, 1)

end subroutine test_restart_negative_beta

!> A conjugated direction that is not a descent direction must be rejected.
!>
!> With `g_{k-1} = (0, 1)`, `d_{k-1} = (1, 0)` and `g_k = (1, 0)` the PRP+
!> coefficient is 1, so `d_k = -g_k + d_{k-1} = (0, 0)` and `g_k.d_k = 0`
!> is not strictly negative: the direction must be reset.
subroutine test_restart_non_descent(error)
   type(error_type), allocatable, intent(out) :: error
   type(landscape_cg_type) :: cg
   real(wp) :: direction(2)
   logical :: restarted

   call new_landscape_cg(cg, 2)
   call cg%push([0.0_wp, 1.0_wp], [1.0_wp, 0.0_wp])
   call cg%direction([1.0_wp, 0.0_wp], direction, restarted)

   call check(error, restarted, .true.)
   if (allocated(error)) return
   call check(error, direction(1), -1.0_wp)
   if (allocated(error)) return
   call check(error, direction(2), 0.0_wp)
   if (allocated(error)) return
   call check(error, cg%n_restart, 1)

end subroutine test_restart_non_descent

!> `reset` must drop the stored pair without counting a restart, so that the
!> next direction is the steepest descent direction.
subroutine test_reset_history(error)
   type(error_type), allocatable, intent(out) :: error
   type(landscape_cg_type) :: cg
   real(wp) :: direction(2)
   logical :: restarted

   call new_landscape_cg(cg, 2)
   call cg%push([1.0_wp, 0.0_wp], [-1.0_wp, 0.0_wp])
   call cg%reset()
   call check(error, cg%has_history, .false.)
   if (allocated(error)) return

   call cg%direction([0.0_wp, 1.0_wp], direction, restarted)
   call check(error, restarted, .true.)
   if (allocated(error)) return
   call check(error, direction(1), 0.0_wp)
   if (allocated(error)) return
   call check(error, direction(2), -1.0_wp)
   if (allocated(error)) return
   call check(error, cg%n_restart, 1)

end subroutine test_reset_history

!> Conjugate gradient must beat steepest descent on a strongly convex quadratic.
!>
!> The convergence level bounds the maximum gradient component by
!> `g_max`, and `|g_i| = k_i |x_i - x0_i|`, so a gradient below `1e-4` implies
!> a geometry error below `1e-3` bohr for the stiffest mode (force constant 0.1).
subroutine test_quadratic_anisotropic(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_harmonic_model) :: model
   type(landscape_opt_settings) :: set
   type(landscape_result) :: result
   real(wp), allocatable :: xfinal(:)
   integer :: n_sd, n_cg, n_mild

   call init(env)

   set = landscape_opt_settings()
   set%printlevel = 0
   set%write_files = .false.
   set%max_steps = 20000
   call set%set_conv_level("tight")

   ! ill conditioned quadratic, condition number 1000
   call new_harmonic_model(model, k_stiff, xref)

   set%algorithm = p_landscape_opt_sd
   call landscape_optimize_model(env, model, set, xstart, result, xfinal)
   n_sd = result%n_steps
   call check(error, result%converged, "steepest descent did not converge")
   if (allocated(error)) return

   set%algorithm = p_landscape_opt_cg
   call landscape_optimize_model(env, model, set, xstart, result, xfinal)
   n_cg = result%n_steps
   write(stdout, '(1x,a,i6,a,es12.4)') "quadratic cg: steps ", n_cg, ", |dx| ", &
      & maxval(abs(xfinal - xref))
   call check(error, result%converged, "conjugate gradient did not converge")
   if (allocated(error)) return
   call check(error, maxval(abs(xfinal - xref)) < 1.0e-3_wp, &
      & "conjugate gradient did not reach the minimum")
   if (allocated(error)) return
   write(stdout, '(1x,a,i6,a,i6)') "quadratic steps: sd ", n_sd, ", cg ", n_cg
   call check(error, n_cg < n_sd, "conjugate gradient is not better than SD")
   if (allocated(error)) return

   ! mildly conditioned quadratic, reported only (the Armijo backtracking
   ! without curvature condition limits the benefit of the conjugacy here)
   call new_harmonic_model(model, k_mild, xref)
   set%algorithm = p_landscape_opt_cg
   call landscape_optimize_model(env, model, set, xstart, result, xfinal)
   n_mild = result%n_steps
   call check(error, result%converged, "conjugate gradient did not converge")
   if (allocated(error)) return
   write(stdout, '(1x,a,i6)') "quadratic steps: cg (k = 1...8) ", n_mild

   ! L-BFGS as the quasi-Newton reference on the same problem
   set%algorithm = p_landscape_opt_lbfgs
   call landscape_optimize_model(env, model, set, xstart, result, xfinal)
   call check(error, result%converged, "L-BFGS did not converge")
   if (allocated(error)) return
   write(stdout, '(1x,a,i6)') "quadratic steps: lbfgs (k = 1...8) ", result%n_steps

end subroutine test_quadratic_anisotropic

end module test_landscape_cg
