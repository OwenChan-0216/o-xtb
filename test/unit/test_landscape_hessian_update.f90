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

!> Unit tests of the Hessian update formulas.
module test_landscape_hessian_update
   use testdrive, only : new_unittest, unittest_type, error_type, check
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_lapack, only : mctc_syev
   use xtb_type_environment, only : TEnvironment, init
   use xtb_landscape_settings, only : p_landscape_hess_update_none, &
      & p_landscape_hess_update_bfgs, p_landscape_hess_update_sr1, &
      & p_landscape_hess_update_bofill, p_landscape_hess_update_powell
   use xtb_landscape_hessian_update
   implicit none
   private

   integer, parameter :: ndim = 6

   public :: collect_landscape_hessian_update

contains

!> Collect all exported unit tests
subroutine collect_landscape_hessian_update(testsuite)
   !> Collection of tests
   type(unittest_type), allocatable, intent(out) :: testsuite(:)

   testsuite = [ &
      new_unittest("secant-condition", test_secant_condition), &
      new_unittest("symmetrization", test_symmetrization), &
      new_unittest("powell-damping", test_powell_damping), &
      new_unittest("sr1-skip", test_sr1_skip), &
      new_unittest("bofill-skip", test_bofill_skip), &
      new_unittest("dispatch", test_dispatch) &
      ]

end subroutine collect_landscape_hessian_update

!> Every update must reproduce the secant condition `B_new s = y` on a
!> quadratic model and must return a symmetric matrix.
subroutine test_secant_condition(error)
   type(error_type), allocatable, intent(out) :: error
   real(wp) :: exact(ndim, ndim), hess(ndim, ndim)
   real(wp) :: step(ndim), dgrad(ndim), residual(ndim)
   real(wp), parameter :: seed(ndim) = [1.0_wp, -0.5_wp, 0.3_wp, &
      & -0.8_wp, 0.6_wp, 0.2_wp]
   logical :: ok
   integer :: i, j, k

   call build_hessian(exact, seed)
   step = [0.3_wp, -0.2_wp, 0.4_wp, 0.1_wp, -0.5_wp, 0.25_wp]
   dgrad = matmul(exact, step)

   do k = 1, 4
      hess = 2.0_wp*exact
      select case (k)
      case (1)
         call update_bfgs(step, dgrad, hess, ok)
      case (2)
         call update_sr1(step, dgrad, hess, ok)
      case (3)
         call update_bofill(step, dgrad, hess, ok)
      case (4)
         call update_powell(step, dgrad, hess, ok)
      end select
      call check(error, ok)
      if (allocated(error)) return
      residual = matmul(hess, step) - dgrad
      call check(error, maxval(abs(residual)), 0.0_wp, thr=1.0e-10_wp)
      if (allocated(error)) return
      do j = 1, ndim
         do i = 1, ndim
            call check(error, hess(i, j), hess(j, i), thr=1.0e-14_wp)
            if (allocated(error)) return
         end do
      end do
   end do

end subroutine test_secant_condition

!> A non-symmetric input matrix must come back symmetrised.
subroutine test_symmetrization(error)
   type(error_type), allocatable, intent(out) :: error
   real(wp) :: exact(ndim, ndim), hess(ndim, ndim)
   real(wp) :: step(ndim), dgrad(ndim)
   real(wp), parameter :: seed(ndim) = [1.0_wp, -0.5_wp, 0.3_wp, &
      & -0.8_wp, 0.6_wp, 0.2_wp]
   logical :: ok
   integer :: i, j, k

   call build_hessian(exact, seed)
   step = [0.3_wp, -0.2_wp, 0.4_wp, 0.1_wp, -0.5_wp, 0.25_wp]
   dgrad = matmul(exact, step)

   do k = 1, 4
      hess = 2.0_wp*exact
      do j = 1, ndim
         do i = 1, ndim
            if (i > j) hess(i, j) = hess(i, j) + 0.1_wp*real(i - j, wp)
         end do
      end do
      select case (k)
      case (1)
         call update_bfgs(step, dgrad, hess, ok)
      case (2)
         call update_sr1(step, dgrad, hess, ok)
      case (3)
         call update_bofill(step, dgrad, hess, ok)
      case (4)
         call update_powell(step, dgrad, hess, ok)
      end select
      call check(error, maxval(abs(hess - transpose(hess))), 0.0_wp, thr=1.0e-14_wp)
      if (allocated(error)) return
   end do

end subroutine test_symmetrization

!> The BFGS update with Powell damping must stay positive definite for a
!> negative curvature pair.
subroutine test_powell_damping(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   real(wp) :: hess(ndim, ndim), work(ndim, ndim), eval(ndim)
   real(wp) :: step(ndim), dgrad(ndim)
   logical :: ok
   integer :: i

   call init(env)
   hess = 0.0_wp
   do i = 1, ndim
      hess(i, i) = 1.0_wp
   end do
   step = 0.0_wp
   step(1) = 1.0_wp
   dgrad = 0.0_wp
   dgrad(1) = -3.0_wp

   call update_bfgs(step, dgrad, hess, ok)
   call check(error, ok)
   if (allocated(error)) return

   work = hess
   call mctc_syev(env, work, eval)
   do i = 1, ndim
      call check(error, eval(i) > 0.0_wp)
      if (allocated(error)) return
   end do
   call check(error, eval(1), 0.2_wp, thr=1.0e-12_wp)

end subroutine test_powell_damping

!> The SR1 update is skipped when `s.(y - B s)` is (numerically) zero.
subroutine test_sr1_skip(error)
   type(error_type), allocatable, intent(out) :: error
   real(wp) :: hess(2, 2), reference(2, 2)
   real(wp) :: step(2), dgrad(2)
   logical :: ok

   hess = 0.0_wp
   hess(1, 1) = 2.0_wp
   hess(2, 2) = 2.0_wp
   reference = hess
   step = [1.0_wp, 1.0_wp]
   dgrad = matmul(hess, step)

   call update_sr1(step, dgrad, hess, ok)
   call check(error, .not. ok)
   if (allocated(error)) return
   call check(error, maxval(abs(hess - reference)), 0.0_wp, thr=1.0e-16_wp)

end subroutine test_sr1_skip

!> The Bofill update must report `ok = .false.` when both its SR1 and MS terms
!> are skipped; otherwise the caller would believe the history was updated.
subroutine test_bofill_skip(error)
   type(error_type), allocatable, intent(out) :: error
   real(wp) :: hess(2, 2), reference(2, 2)
   real(wp) :: step(2), dgrad(2)
   logical :: ok

   hess = 0.0_wp
   reference = hess
   step = [1.0_wp, 0.0_wp]
   dgrad = 0.0_wp

   call update_bofill(step, dgrad, hess, ok)
   call check(error, .not. ok)
   if (allocated(error)) return
   call check(error, maxval(abs(hess - reference)), 0.0_wp, thr=1.0e-16_wp)

end subroutine test_bofill_skip

!> The enumeration dispatch selects the same updates as the direct calls and
!> ignores unknown identifiers.
subroutine test_dispatch(error)
   type(error_type), allocatable, intent(out) :: error
   real(wp) :: exact(ndim, ndim), hess(ndim, ndim), reference(ndim, ndim)
   real(wp) :: step(ndim), dgrad(ndim)
   real(wp), parameter :: seed(ndim) = [1.0_wp, -0.5_wp, 0.3_wp, &
      & -0.8_wp, 0.6_wp, 0.2_wp]
   logical :: ok
   integer, parameter :: updates(4) = [p_landscape_hess_update_bfgs, &
      & p_landscape_hess_update_sr1, p_landscape_hess_update_bofill, &
      & p_landscape_hess_update_powell]
   integer :: k

   call build_hessian(exact, seed)
   step = [0.3_wp, -0.2_wp, 0.4_wp, 0.1_wp, -0.5_wp, 0.25_wp]
   dgrad = matmul(exact, step)

   do k = 1, 4
      hess = 2.0_wp*exact
      call update_by_enum(updates(k), step, dgrad, hess, ok)
      call check(error, ok)
      if (allocated(error)) return
      reference = 2.0_wp*exact
      select case (k)
      case (1)
         call update_bfgs(step, dgrad, reference, ok)
      case (2)
         call update_sr1(step, dgrad, reference, ok)
      case (3)
         call update_bofill(step, dgrad, reference, ok)
      case (4)
         call update_powell(step, dgrad, reference, ok)
      end select
      call check(error, maxval(abs(hess - reference)), 0.0_wp, thr=1.0e-14_wp)
      if (allocated(error)) return
   end do

   hess = 2.0_wp*exact
   reference = hess
   call update_by_enum(p_landscape_hess_update_none, step, dgrad, hess, ok)
   call check(error, .not. ok)
   if (allocated(error)) return
   call check(error, maxval(abs(hess - reference)), 0.0_wp, thr=1.0e-16_wp)

end subroutine test_dispatch

!> Build a dense symmetric positive definite matrix and its Cholesky-like
!> square root vector.
subroutine build_hessian(hess, seed)
   real(wp), intent(out) :: hess(ndim, ndim)
   real(wp), intent(in) :: seed(ndim)

   integer :: i, j

   hess = 0.0_wp
   do j = 1, ndim
      do i = 1, ndim
         hess(i, j) = seed(i)*seed(j)
      end do
   end do
   do i = 1, ndim
      hess(i, i) = hess(i, i) + 0.5_wp + 0.25_wp*real(i, wp)
   end do

end subroutine build_hessian

end module test_landscape_hessian_update
