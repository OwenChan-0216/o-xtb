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

!> Numerical tests of the landscape minimisers on analytic potentials.
!>
!> The optimisers are exercised on an anisotropic harmonic oscillator, the
!> Rosenbrock banana function and the Mueller-Brown surface; all three have
!> known minima, so the tests check the converged geometry, not just the
!> gradient.  In addition the evaluation cache of the engine and the
!> restricted trust radius path of the RFO optimiser are covered.
module test_landscape_optimize_math
   use testdrive, only : new_unittest, unittest_type, error_type, check
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_io, only : stdout
   use xtb_type_environment
   use xtb_type_molecule
   use xtb_type_restart, only : TRestart
   use xtb_landscape_settings, only : landscape_opt_settings, &
      & landscape_engine_control, &
      & p_landscape_opt_sd, p_landscape_opt_lbfgs, p_landscape_opt_bfgs, &
      & p_landscape_opt_diis, p_landscape_opt_rfo, &
      & landscape_opt_algorithm_name
   use xtb_landscape_results, only : landscape_result
   use xtb_landscape_engine, only : landscape_engine, new_landscape_engine, &
      & landscape_energy_model, landscape_numerical_hessian_provider
   use xtb_landscape_rfo, only : landscape_rfo_step
   use xtb_landscape_lbfgs, only : landscape_lbfgs_type, new_landscape_lbfgs
   use xtb_landscape_diis, only : landscape_diis_type, new_landscape_diis
   use xtb_landscape_testpot, only : landscape_harmonic_model, &
      & landscape_rosenbrock_model, landscape_muller_brown_model, &
      & new_harmonic_model, new_rosenbrock_model, new_muller_brown_model
   use xtb_landscape_optimize, only : landscape_optimize_model
   implicit none
   private

   !> All minimisation algorithms
   integer, parameter :: algorithms(5) = [p_landscape_opt_sd, &
      & p_landscape_opt_lbfgs, p_landscape_opt_bfgs, p_landscape_opt_diis, &
      & p_landscape_opt_rfo]

   !> Algorithms whose step must never fall back to steepest descent on a
   !> smooth convex problem (PLAN section 5.4)
   integer, parameter :: qn_algorithms(3) = [p_landscape_opt_lbfgs, &
      & p_landscape_opt_bfgs, p_landscape_opt_rfo]

   public :: collect_landscape_optimize_math

contains

!> Collect all exported unit tests
subroutine collect_landscape_optimize_math(testsuite)
   !> Collection of tests
   type(unittest_type), allocatable, intent(out) :: testsuite(:)

   testsuite = [ &
      new_unittest("harmonic", test_harmonic), &
      new_unittest("rosenbrock", test_rosenbrock), &
      new_unittest("muller-brown", test_muller_brown), &
      new_unittest("lbfgs-direction", test_lbfgs_direction), &
      new_unittest("diis-coefficients", test_diis_coefficients), &
      new_unittest("diis-extrapolation", test_diis_extrapolation), &
      new_unittest("fallback-counters", test_fallback_counters), &
      new_unittest("lbfgs-vs-bfgs", test_lbfgs_vs_bfgs), &
      new_unittest("rfo-invalid-trust", test_rfo_invalid_trust), &
      new_unittest("rfo-trust-limited", test_rfo_trust_limited), &
      new_unittest("engine-cache", test_engine_cache), &
      new_unittest("engine-hvp", test_engine_hvp), &
      new_unittest("rfo-after-warning", test_rfo_after_warning), &
      new_unittest("line-search-toggle", test_line_search_toggle), &
      new_unittest("hess-acc-wiring", test_hess_acc_wiring) &
      ]

end subroutine collect_landscape_optimize_math

!> All algorithms must find the exact minimum of an anisotropic harmonic
!> oscillator in nine dimensions.
subroutine test_harmonic(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_harmonic_model) :: model
   real(wp), allocatable :: k(:), x0(:), xstart(:)
   integer, parameter :: ndim = 9
   integer :: i

   call init(env)
   allocate(k(ndim), x0(ndim), xstart(ndim))
   do i = 1, ndim
      k(i) = 0.5_wp + 0.25_wp*real(mod(i, 4), wp)
      x0(i) = 0.3_wp*real(i, wp) - 1.4_wp
   end do
   xstart = 0.0_wp
   call new_harmonic_model(model, k, x0)

   call run_algorithms(env, error, model, xstart, x0, 1.0e-3_wp, 2000, "normal")
   if (allocated(error)) return

end subroutine test_harmonic

!> L-BFGS, BFGS, DIIS and RFO must find the minimum of the Rosenbrock function.
!>
!> Steepest descent is not included here: the condition number of the
!> Rosenbrock Hessian at the minimum (~2500) makes it prohibitively slow.
subroutine test_rosenbrock(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_rosenbrock_model) :: model
   real(wp), parameter :: xstart(2) = [-1.2_wp, 1.0_wp]
   real(wp), parameter :: xref(2) = [1.0_wp, 1.0_wp]

   call init(env)
   call new_rosenbrock_model(model)

   call run_algorithm(env, error, p_landscape_opt_lbfgs, model, xstart, xref, &
      & 2.0e-3_wp, 5000, "normal")
   if (allocated(error)) return
   call run_algorithm(env, error, p_landscape_opt_bfgs, model, xstart, xref, &
      & 2.0e-3_wp, 5000, "normal")
   if (allocated(error)) return
   call run_algorithm(env, error, p_landscape_opt_diis, model, xstart, xref, &
      & 2.0e-3_wp, 5000, "normal")
   if (allocated(error)) return
   call run_algorithm(env, error, p_landscape_opt_rfo, model, xstart, xref, &
      & 2.0e-3_wp, 5000, "normal")

end subroutine test_rosenbrock

!> All algorithms must find the global minimum of the Mueller-Brown surface.
subroutine test_muller_brown(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_muller_brown_model) :: model
   real(wp) :: xstart(2), xref(2)

   call init(env)
   call new_muller_brown_model(model)

   xstart = [-0.4_wp, 1.2_wp]
   xref = [-0.55822363_wp, 1.44172584_wp]

   ! The geometry error is not implied by the convergence criteria, so the
   ! tolerance is taken from the active level: `loose` allows a maximum
   ! displacement component of 1.0e-2 bohr.
   call run_algorithms(env, error, model, xstart, xref, 1.0e-2_wp, 20000, "loose")
   if (allocated(error)) return

   ! and the same starting from the second basin
   xstart = [0.5_wp, 0.1_wp]
   xref = [0.62349940_wp, 0.02803776_wp]
   call run_algorithms(env, error, model, xstart, xref, 1.0e-2_wp, 20000, "loose")

end subroutine test_muller_brown

!> The L-BFGS two loop recursion must reproduce the direction of an
!> independent dense BFGS recursion on the inverse Hessian.
!>
!> The history is built by hand from fixed `(s, y)` pairs, so the test does
!> not depend on convergence.  Three properties are pinned down:
!>
!>  * the overall sign and structure, by an analytically hand computed case
!>    (`s=e1, y=2e1; s=e2, y=0.5e2; g=(1,1)` gives `d=(-0.5, -2)`);
!>  * the update order and the `gamma = s.y / y.y` of the **most recent** pair,
!>    by comparing against a dense recursion that uses exactly that `gamma`;
!>  * the drop-oldest policy of the store, by inspecting the retained pairs
!>    after the memory is exceeded.
subroutine test_lbfgs_direction(error)
   type(error_type), allocatable, intent(out) :: error
   type(landscape_lbfgs_type) :: lbfgs
   real(wp) :: d(2), d3(3), dref(3)
   real(wp) :: s_pair(3, 2), y_pair(3, 2), gamma
   logical :: ok, steepest

   ! --- analytic reference: exactly two independent axes ---------------
   call new_landscape_lbfgs(lbfgs, 2, 4)
   call lbfgs%push([1.0_wp, 0.0_wp], [2.0_wp, 0.0_wp])
   call lbfgs%push([0.0_wp, 1.0_wp], [0.0_wp, 0.5_wp])
   call lbfgs%direction([1.0_wp, 1.0_wp], d, ok, steepest)
   call check(error, ok)
   if (allocated(error)) return
   call check(error, steepest, .false.)
   if (allocated(error)) return
   call check(error, d(1), -0.5_wp, thr=1.0e-12_wp)
   if (allocated(error)) return
   call check(error, d(2), -2.0_wp, thr=1.0e-12_wp)
   if (allocated(error)) return

   ! --- general case: independent dense recursion -----------------------
   call new_landscape_lbfgs(lbfgs, 3, 4)
   call lbfgs%push([1.0_wp, 0.0_wp, 0.0_wp], [2.0_wp, 1.0_wp, 0.0_wp])
   call lbfgs%push([0.0_wp, 1.0_wp, 0.0_wp], [0.5_wp, 0.1_wp, 0.0_wp])
   s_pair(:, 1) = [1.0_wp, 0.0_wp, 0.0_wp]
   s_pair(:, 2) = [0.0_wp, 1.0_wp, 0.0_wp]
   y_pair(:, 1) = [2.0_wp, 1.0_wp, 0.0_wp]
   y_pair(:, 2) = [0.5_wp, 0.1_wp, 0.0_wp]
   gamma = dot_product(s_pair(:, 2), y_pair(:, 2)) &
      & /dot_product(y_pair(:, 2), y_pair(:, 2))
   call lbfgs%direction([1.0_wp, 2.0_wp, 3.0_wp], d3, ok, steepest)
   call check(error, ok)
   if (allocated(error)) return
   dref = dense_lbfgs_direction(s_pair, y_pair, gamma, [1.0_wp, 2.0_wp, 3.0_wp])
   call check(error, maxval(abs(d3 - dref)), 0.0_wp, thr=1.0e-12_wp)
   if (allocated(error)) return

   ! --- drop-oldest policy ---------------------------------------------
   call new_landscape_lbfgs(lbfgs, 3, 2)
   call lbfgs%push([1.0_wp, 0.0_wp, 0.0_wp], [3.0_wp, 1.0_wp, 0.0_wp])
   call lbfgs%push([0.0_wp, 1.0_wp, 0.0_wp], [1.0_wp, 2.0_wp, 0.0_wp])
   call lbfgs%push([0.0_wp, 0.0_wp, 1.0_wp], [2.0_wp, 1.0_wp, 3.0_wp])
   call check(error, lbfgs%nstore, 2)
   if (allocated(error)) return
   call check(error, maxval(abs(lbfgs%s(:, 1) - [0.0_wp, 1.0_wp, 0.0_wp])), &
      & 0.0_wp, thr=1.0e-16_wp)
   if (allocated(error)) return
   call check(error, maxval(abs(lbfgs%y(:, 1) - [1.0_wp, 2.0_wp, 0.0_wp])), &
      & 0.0_wp, thr=1.0e-16_wp)
   if (allocated(error)) return
   call check(error, maxval(abs(lbfgs%s(:, 2) - [0.0_wp, 0.0_wp, 1.0_wp])), &
      & 0.0_wp, thr=1.0e-16_wp)
   if (allocated(error)) return
   call check(error, maxval(abs(lbfgs%y(:, 2) - [2.0_wp, 1.0_wp, 3.0_wp])), &
      & 0.0_wp, thr=1.0e-16_wp)
   if (allocated(error)) return

   s_pair(:, 1) = [0.0_wp, 1.0_wp, 0.0_wp]
   s_pair(:, 2) = [0.0_wp, 0.0_wp, 1.0_wp]
   y_pair(:, 1) = [1.0_wp, 2.0_wp, 0.0_wp]
   y_pair(:, 2) = [2.0_wp, 1.0_wp, 3.0_wp]
   gamma = dot_product(s_pair(:, 2), y_pair(:, 2)) &
      & /dot_product(y_pair(:, 2), y_pair(:, 2))
   call lbfgs%direction([1.0_wp, 1.0_wp, 1.0_wp], d3, ok, steepest)
   call check(error, ok)
   if (allocated(error)) return
   dref = dense_lbfgs_direction(s_pair, y_pair, gamma, [1.0_wp, 1.0_wp, 1.0_wp])
   call check(error, maxval(abs(d3 - dref)), 0.0_wp, thr=1.0e-12_wp)
   if (allocated(error)) return

   ! --- empty history is plain steepest descent -------------------------
   call new_landscape_lbfgs(lbfgs, 3, 4)
   call lbfgs%direction([1.0_wp, -2.0_wp, 0.5_wp], d3, ok, steepest)
   call check(error, ok)
   if (allocated(error)) return
   call check(error, steepest, .true.)
   if (allocated(error)) return
   call check(error, maxval(abs(d3 - [-1.0_wp, 2.0_wp, -0.5_wp])), 0.0_wp, &
      & thr=1.0e-16_wp)

end subroutine test_lbfgs_direction

!> Independent reference for the L-BFGS direction.
!>
!> Instead of the two loop recursion this builds the dense inverse Hessian
!> with the BFGS update `H = V H V^T + rho s s^T` (Nocedal & Wright, 2nd ed.,
!> eq. 7.17), `V = I - rho y s^T`, starting from `H_0 = gamma I`, and returns
!> `-H g`.  For the same correction pairs the two algorithms must agree to
!> machine precision; any mistake in the update order or in the choice of
!> `gamma` breaks the agreement.
function dense_lbfgs_direction(s_pair, y_pair, gamma, gradient) result(d)
   !> Stored steps `(ndim, npair)`
   real(wp), intent(in) :: s_pair(:, :)
   !> Stored gradient differences `(ndim, npair)`
   real(wp), intent(in) :: y_pair(:, :)
   !> Initial inverse Hessian scaling (most recent pair)
   real(wp), intent(in) :: gamma
   !> Gradient (hartree/bohr)
   real(wp), intent(in) :: gradient(:)
   !> Reference direction `-H g`
   real(wp) :: d(size(gradient))

   real(wp) :: hh(size(gradient), size(gradient))
   real(wp) :: vv(size(gradient), size(gradient))
   real(wp) :: tmp(size(gradient), size(gradient))
   real(wp) :: rho
   integer :: n, k, i, j

   n = size(gradient)
   hh = 0.0_wp
   do i = 1, n
      hh(i, i) = gamma
   end do
   do k = 1, size(s_pair, 2)
      rho = 1.0_wp/dot_product(s_pair(:, k), y_pair(:, k))
      vv = 0.0_wp
      do j = 1, n
         vv(j, j) = 1.0_wp
         do i = 1, n
            vv(i, j) = vv(i, j) - rho*s_pair(i, k)*y_pair(j, k)
         end do
      end do
      tmp = matmul(matmul(vv, hh), transpose(vv))
      do j = 1, n
         do i = 1, n
            tmp(i, j) = tmp(i, j) + rho*s_pair(i, k)*s_pair(j, k)
         end do
      end do
      hh = tmp
   end do
   d = -matmul(hh, gradient)

end function dense_lbfgs_direction

!> The GDIIS weights must satisfy `sum(c_i) = 1` and reproduce the extrapolated
!> geometry.  This pins down the augmented linear system: a broken constraint
!> row (for example a flipped right hand side) violates the sum.
subroutine test_diis_coefficients(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_diis_type) :: diis
   real(wp) :: geo(3, 3), grad(3, 3), x(3), d(3), c(3), x_diis(3)
   logical :: ok

   call init(env)
   call new_landscape_diis(diis, 3, 6, min_vectors=2)
   geo(:, 1) = [0.0_wp, 0.0_wp, 0.0_wp]
   grad(:, 1) = [1.0_wp, 0.0_wp, 0.0_wp]
   geo(:, 2) = [1.0_wp, 0.5_wp, -0.2_wp]
   grad(:, 2) = [0.3_wp, 0.9_wp, 0.1_wp]
   geo(:, 3) = [-0.4_wp, 0.8_wp, 0.6_wp]
   grad(:, 3) = [0.2_wp, -0.3_wp, 0.95_wp]
   call diis%push(geo(:, 1), grad(:, 1))
   call diis%push(geo(:, 2), grad(:, 2))
   call diis%push(geo(:, 3), grad(:, 3))

   x = geo(:, 3)
   call diis%direction(env, x, d, ok, coefficients=c)
   call check(error, ok, "GDIIS did not produce an extrapolated step")
   if (allocated(error)) return
   call check(error, sum(c), 1.0_wp, thr=1.0e-10_wp)
   if (allocated(error)) return
   ! the weights must be a genuine extrapolation, not a uniform average
   call check(error, maxval(abs(c - 1.0_wp/3.0_wp)) > 1.0e-3_wp)
   if (allocated(error)) return
   x_diis = c(1)*geo(:, 1) + c(2)*geo(:, 2) + c(3)*geo(:, 3)
   call check(error, maxval(abs((x + d) - x_diis)), 0.0_wp, thr=1.0e-10_wp)

end subroutine test_diis_coefficients

!> The driver must actually use the GDIIS extrapolation when it is available.
!>
!> `history_method` records the algorithm of every step; if `diis_direction`
!> were short-circuited the run would silently become steepest descent and no
!> step would be labelled `diis`, even though convergence still succeeds.
subroutine test_diis_extrapolation(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_harmonic_model) :: model
   type(landscape_opt_settings) :: set
   type(landscape_result) :: result
   real(wp), allocatable :: k(:), x0(:), xstart(:), xfinal(:)
   integer, parameter :: ndim = 8
   integer :: i, n_diis, n_sd

   call init(env)
   allocate(k(ndim), x0(ndim), xstart(ndim))
   do i = 1, ndim
      k(i) = 0.5_wp + 0.25_wp*real(mod(i, 4), wp)
      x0(i) = 0.3_wp*real(i, wp) - 1.4_wp
   end do
   xstart = 0.0_wp
   call new_harmonic_model(model, k, x0)

   set = landscape_opt_settings()
   set%algorithm = p_landscape_opt_diis
   set%diis_store_every = 1
   set%diis_min_snapshots = 2
   set%max_steps = 2000
   set%printlevel = 0
   set%write_files = .false.
   call set%set_conv_level("tight")

   call landscape_optimize_model(env, model, set, xstart, result, xfinal)
   call check(error, result%converged, "DIIS did not converge")
   if (allocated(error)) return
   call check(error, allocated(result%conv%history_method))
   if (allocated(error)) return
   n_diis = count(result%conv%history_method == p_landscape_opt_diis)
   n_sd = count(result%conv%history_method == p_landscape_opt_sd)
   write(stdout, '(1x,a,i4,a,i4,a,i6)') "DIIS steps: extrapolated ", n_diis, &
      & ", steepest ", n_sd, ", total ", result%n_steps
   call check(error, n_diis > 0, "GDIIS extrapolation was never used")

end subroutine test_diis_extrapolation

!> Dense BFGS and L-BFGS must reach the analytic minimiser of a strongly convex
!> quadratic; the two quasi-Newton methods must agree coordinate-wise and use
!> far fewer iterations than steepest descent.  Neither may fall back to
!> steepest descent.
subroutine test_lbfgs_vs_bfgs(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_harmonic_model) :: model
   real(wp), allocatable :: k(:), x0(:), xstart(:), x_lbfgs(:), x_bfgs(:), x_sd(:)
   !> Force constants of the ill conditioned comparison (condition number 1000)
   real(wp), parameter :: k_stiff(4) = [0.1_wp, 1.0_wp, 10.0_wp, 100.0_wp]
   !> Minimiser of the ill conditioned comparison
   real(wp), parameter :: x_stiff(4) = 0.0_wp
   !> Starting point of the ill conditioned comparison
   real(wp), parameter :: xstart_stiff(4) = [1.0_wp, 1.0_wp, 1.0_wp, 1.0_wp]
   integer, parameter :: ndim = 12
   integer :: n_lbfgs, n_bfgs, n_sd, n_fb(3), i

   call init(env)
   allocate(k(ndim), x0(ndim), xstart(ndim))
   do i = 1, ndim
      k(i) = 1.0_wp + 0.5_wp*real(i, wp)
      x0(i) = 0.5_wp
   end do
   xstart = 0.0_wp
   call new_harmonic_model(model, k, x0)

   call harmonic_run(env, error, p_landscape_opt_lbfgs, model, xstart, x_lbfgs, &
      & n_lbfgs, n_fb(1))
   if (allocated(error)) return
   call harmonic_run(env, error, p_landscape_opt_bfgs, model, xstart, x_bfgs, &
      & n_bfgs, n_fb(2))
   if (allocated(error)) return
   call harmonic_run(env, error, p_landscape_opt_sd, model, xstart, x_sd, &
      & n_sd, n_fb(3))
   if (allocated(error)) return

   write(stdout, '(1x,a,i5,a,i5,a,i6)') "quadratic steps: lbfgs ", n_lbfgs, &
      & ", bfgs ", n_bfgs, ", sd ", n_sd

   ! both quasi-Newton methods reach the analytic minimum
   call check(error, maxval(abs(x_lbfgs - x0)) < 1.0e-3_wp, &
      & "L-BFGS did not reach the analytic minimum")
   if (allocated(error)) return
   call check(error, maxval(abs(x_bfgs - x0)) < 1.0e-3_wp, &
      & "BFGS did not reach the analytic minimum")
   if (allocated(error)) return
   call check(error, maxval(abs(x_lbfgs - x_bfgs)) < 1.0e-3_wp, &
      & "L-BFGS and BFGS converged to different geometries")
   if (allocated(error)) return
   call check(error, maxval(abs(x_sd - x0)) < 1.0e-3_wp)
   if (allocated(error)) return

   ! on a convex quadratic both quasi-Newton methods beat steepest descent
   call check(error, n_lbfgs < n_sd, "L-BFGS is not faster than steepest descent")
   if (allocated(error)) return
   call check(error, n_bfgs < n_sd, "BFGS is not faster than steepest descent")
   if (allocated(error)) return
   call check(error, n_fb(1), 0, "L-BFGS fell back to steepest descent")
   if (allocated(error)) return
   call check(error, n_fb(2), 0, "BFGS fell back to steepest descent")
   if (allocated(error)) return

   ! On an ill conditioned quadratic (condition number 1000) the quasi-Newton
   ! method must be dramatically faster than steepest descent, which only
   ! reduces the stiffest component of the gradient.
   call new_harmonic_model(model, k_stiff, x_stiff)
   call harmonic_run(env, error, p_landscape_opt_sd, model, xstart_stiff, x_sd, &
      & n_sd, n_fb(3))
   if (allocated(error)) return
   call harmonic_run(env, error, p_landscape_opt_lbfgs, model, xstart_stiff, &
      & x_lbfgs, n_lbfgs, n_fb(1))
   if (allocated(error)) return
   write(stdout, '(1x,a,i6,a,i6)') "ill conditioned steps: lbfgs ", n_lbfgs, &
      & ", sd ", n_sd
   call check(error, n_lbfgs < n_sd, &
      & "L-BFGS is not faster than steepest descent on an ill conditioned quadratic")
   if (allocated(error)) return
   call check(error, n_lbfgs*2 < n_sd, &
      & "L-BFGS is not significantly faster than steepest descent")
   if (allocated(error)) return
   call check(error, n_fb(1), 0, "L-BFGS fell back to steepest descent")

end subroutine test_lbfgs_vs_bfgs

!> Run one optimiser on a harmonic potential and return the final geometry.
subroutine harmonic_run(env, error, algorithm, model, xstart, xfinal, n_steps, n_fb)
   type(TEnvironment), intent(inout) :: env
   type(error_type), allocatable, intent(out) :: error
   integer, intent(in) :: algorithm
   class(landscape_energy_model), intent(inout) :: model
   real(wp), intent(in) :: xstart(:)
   real(wp), allocatable, intent(out) :: xfinal(:)
   integer, intent(out) :: n_steps
   integer, intent(out) :: n_fb

   type(landscape_opt_settings) :: set
   type(landscape_result) :: result

   set = landscape_opt_settings()
   set%algorithm = algorithm
   set%max_steps = 5000
   set%printlevel = 0
   set%write_files = .false.
   call set%set_conv_level("tight")

   call landscape_optimize_model(env, model, set, xstart, result, xfinal)
   if (.not. allocated(xfinal)) then
      call check(error, .false., "no final geometry")
      n_steps = -1
      n_fb = -1
      return
   end if
   call check(error, result%converged, trim(landscape_opt_algorithm_name(algorithm))//&
      & " did not converge")
   n_steps = result%n_steps
   n_fb = result%n_fallback

end subroutine harmonic_run

!> The quasi-Newton and RFO steps must never degrade to steepest descent on a
!> smooth convex problem.  `landscape_result%n_fallback` counts every such
!> degradation, so an inverted L-BFGS two loop (which returns an uphill
!> direction that the line search rejects) can no longer hide behind the SD
!> backstop and a green convergence flag.
subroutine test_fallback_counters(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_harmonic_model) :: harmonic
   type(landscape_rosenbrock_model) :: rosen
   type(landscape_opt_settings) :: set
   type(landscape_result) :: result
   real(wp), allocatable :: k(:), x0(:), xstart(:), xfinal(:)
   real(wp), parameter :: rosen_start(2) = [-1.2_wp, 1.0_wp]
   integer, parameter :: ndim = 9
   integer :: i, n, n_used

   call init(env)
   allocate(k(ndim), x0(ndim), xstart(ndim))
   do i = 1, ndim
      k(i) = 0.5_wp + 0.25_wp*real(mod(i, 4), wp)
      x0(i) = 0.3_wp*real(i, wp) - 1.4_wp
   end do
   xstart = 0.0_wp
   call new_harmonic_model(harmonic, k, x0)
   call new_rosenbrock_model(rosen)

   set = landscape_opt_settings()
   set%max_steps = 5000
   set%printlevel = 0
   set%write_files = .false.
   call set%set_conv_level("normal")

   do n = 1, size(qn_algorithms)
      set%algorithm = qn_algorithms(n)
      call landscape_optimize_model(env, harmonic, set, xstart, result, xfinal)
      call check(error, result%converged, &
         & trim(landscape_opt_algorithm_name(qn_algorithms(n)))//&
         & " did not converge on the convex quadratic")
      if (allocated(error)) return
      n_used = count(result%conv%history_method == qn_algorithms(n))
      write(stdout, '(1x,a,a,a,i4,a,i4)') "convex quadratic ", &
         & trim(landscape_opt_algorithm_name(qn_algorithms(n))), &
         & ": steps ", result%n_steps, ", fallbacks ", result%n_fallback
      call check(error, result%n_fallback, 0, &
         & trim(landscape_opt_algorithm_name(qn_algorithms(n)))//&
         & " degraded to steepest descent on a convex quadratic")
      if (allocated(error)) return
      call check(error, n_used > 0, &
         & trim(landscape_opt_algorithm_name(qn_algorithms(n)))//&
         & " never used its own direction")
      if (allocated(error)) return
   end do

   do n = 1, size(qn_algorithms)
      set%algorithm = qn_algorithms(n)
      call landscape_optimize_model(env, rosen, set, rosen_start, result, xfinal)
      call check(error, result%converged, &
         & trim(landscape_opt_algorithm_name(qn_algorithms(n)))//&
         & " did not converge on Rosenbrock")
      if (allocated(error)) return
      write(stdout, '(1x,a,a,a,i4,a,i4)') "rosenbrock ", &
         & trim(landscape_opt_algorithm_name(qn_algorithms(n))), &
         & ": steps ", result%n_steps, ", fallbacks ", result%n_fallback
      call check(error, result%n_fallback, 0, &
         & trim(landscape_opt_algorithm_name(qn_algorithms(n)))//&
         & " degraded to steepest descent on Rosenbrock")
      if (allocated(error)) return
   end do

end subroutine test_fallback_counters

!> `landscape_rfo_step` must report failure for a non-positive trust radius and
!> for a vanishing gradient (no descent step can be constructed) without
!> producing a spurious displacement.
subroutine test_rfo_invalid_trust(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   real(wp) :: hess(3, 3), grad(3), step(3), predicted
   logical :: fail
   integer :: i

   call init(env)
   hess = 0.0_wp
   do i = 1, 3
      hess(i, i) = 1.0_wp
   end do
   grad = [1.0_wp, -2.0_wp, 0.5_wp]

   call landscape_rfo_step(env, hess, grad, 0.0_wp, 1.0e-2_wp, step, &
      & predicted, fail)
   call check(error, fail, "trust = 0 must be rejected")
   if (allocated(error)) return
   call check(error, maxval(abs(step)), 0.0_wp)
   if (allocated(error)) return
   call check(error, predicted, 0.0_wp)
   if (allocated(error)) return

   call landscape_rfo_step(env, hess, grad, -1.0_wp, 1.0e-2_wp, step, &
      & predicted, fail)
   call check(error, fail, "a negative trust radius must be rejected")
   if (allocated(error)) return
   call check(error, maxval(abs(step)), 0.0_wp)
   if (allocated(error)) return

   ! vanishing gradient: every shifted step is zero, no descent step exists
   call landscape_rfo_step(env, hess, [0.0_wp, 0.0_wp, 0.0_wp], 1.0_wp, &
      & 1.0e-2_wp, step, predicted, fail)
   call check(error, fail, "a vanishing gradient must be reported as a failure")
   if (allocated(error)) return
   call check(error, maxval(abs(step)), 0.0_wp)

end subroutine test_rfo_invalid_trust

!> The RFO optimiser must converge even if the trust radius is smaller than
!> the distance to the minimum.
subroutine test_rfo_trust_limited(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_harmonic_model) :: model
   type(landscape_opt_settings) :: set
   type(landscape_result) :: result
   real(wp), allocatable :: k(:), x0(:), xstart(:), xfinal(:)
   integer, parameter :: ndim = 6
   integer :: i

   call init(env)
   allocate(k(ndim), x0(ndim), xstart(ndim))
   do i = 1, ndim
      k(i) = 0.5_wp*real(i, wp)
      x0(i) = 1.0_wp
   end do
   xstart = 0.0_wp
   call new_harmonic_model(model, k, x0)

   set = landscape_opt_settings()
   set%algorithm = p_landscape_opt_rfo
   set%trust_radius = 5.0e-2_wp
   set%trust_max = 5.0e-2_wp
   set%max_displ = 5.0e-2_wp
   set%max_steps = 2000
   set%printlevel = 0
   set%write_files = .false.

   call landscape_optimize_model(env, model, set, xstart, result, xfinal)
   call check(error, result%converged)
   if (allocated(error)) return
   call check(error, maxval(abs(xfinal - x0)) < 1.0e-3_wp)
   if (allocated(error)) return
   call check(error, result%n_steps > 10)

end subroutine test_rfo_trust_limited

!> Repeated geometries must not trigger a new evaluation.
subroutine test_engine_cache(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(landscape_engine) :: engine
   type(landscape_harmonic_model) :: model
   character(len=*), parameter :: sym(1) = ["H"]
   real(wp), parameter :: xyz(3, 1) = reshape([0.0_wp, 0.0_wp, 0.0_wp], [3, 1])
   real(wp) :: k(3), center(3), energy, grad(3, 1), hess(3, 3)
   logical :: fail

   call init(env)
   call init(mol, sym, xyz)

   k = [1.0_wp, 2.0_wp, 3.0_wp]
   center = 0.0_wp
   call new_harmonic_model(model, k, center)
   call new_landscape_engine(engine)
   call engine%set_model(model)

   call engine%energy_gradient(env, mol, chk, energy, grad, fail)
   call check(error, .not. fail)
   if (allocated(error)) return
   call check(error, engine%n_eval, 1)
   if (allocated(error)) return
   call check(error, engine%n_cache_hit, 0)
   if (allocated(error)) return
   call check(error, energy, 0.0_wp)
   if (allocated(error)) return

   ! identical geometry -> cache hit, no new evaluation
   call engine%energy_gradient(env, mol, chk, energy, grad, fail)
   call check(error, engine%n_eval, 1)
   if (allocated(error)) return
   call check(error, engine%n_cache_hit, 1)
   if (allocated(error)) return

   ! perturbe the geometry -> new evaluation with the analytic values
   mol%xyz(1, 1) = 0.25_wp
   call engine%energy_gradient(env, mol, chk, energy, grad, fail)
   call check(error, engine%n_eval, 2)
   if (allocated(error)) return
   call check(error, engine%n_cache_hit, 1)
   if (allocated(error)) return
   call check(error, energy, 0.5_wp*k(1)*0.25_wp**2, thr=1.0e-14_wp)
   if (allocated(error)) return
   call check(error, grad(1, 1), k(1)*0.25_wp, thr=1.0e-14_wp)
   if (allocated(error)) return
   call check(error, grad(2, 1), 0.0_wp)
   if (allocated(error)) return

   ! explicit invalidation forces a new evaluation
   call engine%invalidate()
   call engine%energy_gradient(env, mol, chk, energy, grad, fail)
   call check(error, engine%n_eval, 3)
   if (allocated(error)) return

   ! analytic Hessian through the engine
   call engine%hessian(env, mol, chk, hess, fail)
   call check(error, .not. fail)
   if (allocated(error)) return
   call check(error, hess(1, 1), k(1), thr=1.0e-14_wp)
   if (allocated(error)) return
   call check(error, hess(1, 2), 0.0_wp)
   if (allocated(error)) return
   call check(error, engine%n_hess, 1)

end subroutine test_engine_cache

!> The finite difference Hessian-vector product must reproduce `H v` for the
!> analytic harmonic oscillator and must restore the geometry.
subroutine test_engine_hvp(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(landscape_engine) :: engine
   type(landscape_harmonic_model) :: model
   character(len=*), parameter :: sym(1) = ["H"]
   real(wp), parameter :: xyz(3, 1) = reshape([0.1_wp, -0.2_wp, 0.3_wp], [3, 1])
   real(wp) :: k(3), center(3), hvec(3), reference(3), saved(3, 1)
   logical :: fail

   call init(env)
   call init(mol, sym, xyz)

   k = [1.0_wp, 2.0_wp, 3.0_wp]
   center = 0.0_wp
   call new_harmonic_model(model, k, center)
   call new_landscape_engine(engine)
   call engine%set_model(model)

   saved = mol%xyz
   reference = k*[0.1_wp, 0.1_wp, 0.1_wp]
   call engine%hvp(env, mol, chk, [0.1_wp, 0.1_wp, 0.1_wp], hvec, fail)
   call check(error, .not. fail)
   if (allocated(error)) return
   call check(error, maxval(abs(hvec - reference)), 0.0_wp, thr=1.0e-12_wp)
   if (allocated(error)) return
   call check(error, maxval(abs(mol%xyz - saved)), 0.0_wp, thr=1.0e-16_wp)
   if (allocated(error)) return
   call check(error, engine%n_hvp, 1)

end subroutine test_engine_hvp

!> A warning logged earlier in a strict run must not make the RFO eigenvalue
!> solver look broken (the old `env%check` probe accumulated over the whole
!> run and silently degraded the RFO step to steepest descent).
subroutine test_rfo_after_warning(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   real(wp) :: hess(4, 4), grad(4), step(4), predicted
   logical :: fail
   integer :: i

   call init(env, strict=.true.)
   call env%warning("injected warning before the eigenvalue solve")

   hess = 0.0_wp
   do i = 1, 4
      hess(i, i) = 1.0_wp
   end do
   grad = 1.0_wp

   call landscape_rfo_step(env, hess, grad, 1.0_wp, 1.0e-2_wp, step, predicted, fail)
   call check(error, .not. fail, "RFO degraded to SD after an unrelated warning")
   if (allocated(error)) return
   call check(error, predicted > 0.0_wp)

end subroutine test_rfo_after_warning

!> `line_search = .false.` must really disable the Armijo backtracking; the
!> setting is only effective if the run behaves differently.
subroutine test_line_search_toggle(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_harmonic_model) :: model
   type(landscape_opt_settings) :: set
   type(landscape_result) :: result
   real(wp) :: k(2), x0(2), xstart(2)
   real(wp), allocatable :: xfinal(:)

   call init(env)
   k = [3.0_wp, 3.0_wp]
   x0 = [1.0_wp, 1.0_wp]
   xstart = [0.0_wp, 0.0_wp]
   call new_harmonic_model(model, k, x0)

   set = landscape_opt_settings()
   set%algorithm = p_landscape_opt_sd
   set%line_search = .true.
   set%max_displ = 10.0_wp
   set%max_steps = 200
   set%printlevel = 0
   set%write_files = .false.

   call landscape_optimize_model(env, model, set, xstart, result, xfinal)
   call check(error, result%converged, "SD with line search did not converge")
   if (allocated(error)) return

   ! the full SD step increases the energy of this harmonic oscillator, so
   ! without the line search every step is rejected and the run stagnates
   set%line_search = .false.
   call landscape_optimize_model(env, model, set, xstart, result, xfinal)
   call check(error, .not. result%converged, "line_search=.false. had no effect")

end subroutine test_line_search_toggle

!> The engine must forward `hess_acc` to the numerical Hessian provider.
subroutine test_hess_acc_wiring(error)
   type(error_type), allocatable, intent(out) :: error
   type(landscape_engine) :: engine
   type(landscape_engine_control) :: ctrl

   ctrl = landscape_engine_control()
   ctrl%hess_acc = 0.42_wp
   call new_landscape_engine(engine, ctrl)

   select type (hp => engine%hp)
   type is (landscape_numerical_hessian_provider)
      call check(error, hp%sccacc, 0.42_wp)
   class default
      call check(error, .false., "unexpected Hessian provider")
   end select

end subroutine test_hess_acc_wiring

!> Run one algorithm on a potential and check convergence and geometry.
subroutine run_algorithm(env, error, algorithm, model, xstart, xref, tol, &
      & max_steps, level)
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Failure report
   type(error_type), allocatable, intent(out) :: error
   !> Algorithm identifier
   integer, intent(in) :: algorithm
   !> Potential
   class(landscape_energy_model), intent(inout) :: model
   !> Starting geometry
   real(wp), intent(in) :: xstart(:)
   !> Reference minimum
   real(wp), intent(in) :: xref(:)
   !> Geometrical tolerance
   real(wp), intent(in) :: tol
   !> Maximum number of macro steps
   integer, intent(in) :: max_steps
   !> Convergence level name
   character(len=*), intent(in) :: level

   type(landscape_opt_settings) :: set
   type(landscape_result) :: result
   real(wp), allocatable :: xfinal(:)

   set = landscape_opt_settings()
   set%algorithm = algorithm
   set%max_steps = max_steps
   set%printlevel = 0
   set%write_files = .false.
   call set%set_conv_level(level)

   call landscape_optimize_model(env, model, set, xstart, result, xfinal)
   if (.not. allocated(xfinal)) then
      call check(error, .false.,&
         & trim(landscape_opt_algorithm_name(algorithm))//&
         & " did not return a geometry")
      return
   end if
   write(stdout, '(1x,a,a,i6,a,l1,a,es12.4,a,es12.4)') "  ", &
      & landscape_opt_algorithm_name(algorithm), result%n_steps, &
      & " steps, converged ", result%converged, ", gmax ", result%gmax, &
      & ", dist ", maxval(abs(xfinal - xref))
   call check(error, result%converged,&
      & trim(landscape_opt_algorithm_name(algorithm))//" did not converge")
   if (allocated(error)) return
   call check(error, maxval(abs(xfinal - xref)) < tol,&
      & trim(landscape_opt_algorithm_name(algorithm))//&
      & " did not reach the minimum")

end subroutine run_algorithm

!> Run all minimisation algorithms on a potential.
subroutine run_algorithms(env, error, model, xstart, xref, tol, max_steps, level)
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Failure report
   type(error_type), allocatable, intent(out) :: error
   !> Potential
   class(landscape_energy_model), intent(inout) :: model
   !> Starting geometry
   real(wp), intent(in) :: xstart(:)
   !> Reference minimum
   real(wp), intent(in) :: xref(:)
   !> Geometrical tolerance
   real(wp), intent(in) :: tol
   !> Maximum number of macro steps
   integer, intent(in) :: max_steps
   !> Convergence level name
   character(len=*), intent(in) :: level

   integer :: i

   do i = 1, size(algorithms)
      call run_algorithm(env, error, algorithms(i), model, xstart, xref, tol, &
         & max_steps, level)
      if (allocated(error)) return
   end do

end subroutine run_algorithms

end module test_landscape_optimize_math
