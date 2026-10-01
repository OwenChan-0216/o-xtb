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

!> Dense (full memory) quasi-Newton BFGS of the landscape suite.
!>
!> The Hessian approximation is stored densely and updated with one of the
!> formulas of `xtb_landscape_hessian_update` (BFGS with Powell damping, SR1,
!> Bofill or Powell).  The quasi-Newton step solves `B d = -g` in the
!> eigenbasis of `B` (LAPACK `dsyev`, ascending eigenvalues, eigenvectors in
!> the columns of the returned matrix); eigenvalues below `hlow` are lifted to
!> `hlow` so that an indefinite approximation still yields a well defined,
!> finite step.  The result is always a descent direction.
!>
!> Units: coordinates and steps in bohr, Hessian in hartree/bohr^2.
module xtb_landscape_bfgs
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_lapack, only : mctc_syev
   use xtb_type_environment, only : TEnvironment
   use xtb_landscape_settings, only : p_landscape_hess_update_bofill, &
      & landscape_log_failed
   use xtb_landscape_hessian_update, only : update_by_enum, symmetrize_hessian
   implicit none(type, external)
   private

   public :: landscape_bfgs_type, new_landscape_bfgs

   !> Full memory quasi-Newton optimiser state.
   type :: landscape_bfgs_type
      !> Dense Hessian approximation (hartree/bohr^2), shape `(ndim, ndim)`
      real(wp), allocatable :: hess(:, :)
      !> Curvature floor applied to the eigenvalues before solving for the step
      real(wp) :: hlow = 1.0e-2_wp
      !> Hessian update formula, see `xtb_landscape_settings`
      integer :: update = p_landscape_hess_update_bofill
   contains
      !> Overwrite the Hessian approximation
      procedure :: set_hessian => bfgs_set_hessian
      !> Quasi-Newton direction `d = -B^{-1} g`
      procedure :: direction => bfgs_direction
      !> Update the Hessian approximation from a step
      procedure :: update_hessian => bfgs_update_hessian
   end type landscape_bfgs_type

contains

!> Allocate a dense BFGS optimiser with an identity initial Hessian.
subroutine new_landscape_bfgs(self, ndim, update, hlow)
   !> New optimiser state
   type(landscape_bfgs_type), intent(out) :: self
   !> Dimension of the coordinate vector (3N)
   integer, intent(in) :: ndim
   !> Hessian update formula
   integer, intent(in), optional :: update
   !> Curvature floor of the eigenvalues
   real(wp), intent(in), optional :: hlow

   integer :: i

   if (present(update)) self%update = update
   if (present(hlow)) self%hlow = hlow
   allocate(self%hess(ndim, ndim), source=0.0_wp)
   do i = 1, ndim
      self%hess(i, i) = 1.0_wp
   end do

end subroutine new_landscape_bfgs

!> Overwrite the Hessian approximation (for example with a model Hessian) and
!> enforce symmetry.
subroutine bfgs_set_hessian(self, hess)
   !> Optimiser state
   class(landscape_bfgs_type), intent(inout) :: self
   !> New Hessian matrix (hartree/bohr^2)
   real(wp), intent(in) :: hess(:, :)

   self%hess = hess
   call symmetrize_hessian(self%hess)

end subroutine bfgs_set_hessian

!> Quasi-Newton direction obtained from the spectral decomposition of `B`.
!>
!> `d = -sum_i (V_i.g)/(max(w_i, hlow)) V_i`, which is finite and a descent
!> direction as long as `hlow > 0`.  If the eigenvalue solver fails, the
!> steepest descent direction is returned and `ok` is false.
subroutine bfgs_direction(self, env, gradient, direction, ok)
   !> Optimiser state
   class(landscape_bfgs_type), intent(in) :: self
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Gradient (hartree/bohr)
   real(wp), intent(in) :: gradient(:)
   !> Search direction (bohr)
   real(wp), intent(out) :: direction(:)
   !> True if the eigenvalue solver succeeded
   logical, intent(out) :: ok

   real(wp), allocatable :: work(:, :), eval(:), f(:)
   logical :: failed
   integer :: i, nlog

   ok = .false.
   allocate(work(size(self%hess, 1), size(self%hess, 2)), source=self%hess)
   allocate(eval(size(gradient)))
   call symmetrize_hessian(work)
   ! Probe only the messages appended by this call; env%check() is cumulative
   ! and would falsely report a failure under --strict after any warning.
   nlog = env%nLog
   call mctc_syev(env, work, eval)
   failed = landscape_log_failed(env, nlog)
   if (failed) then
      direction = -gradient
      return
   end if

   do i = 1, size(eval)
      eval(i) = max(eval(i), self%hlow)
   end do

   f = matmul(transpose(work), gradient)
   direction = 0.0_wp
   do i = 1, size(eval)
      direction = direction - (f(i)/eval(i))*work(:, i)
   end do
   ok = .true.

end subroutine bfgs_direction

!> Update the Hessian approximation with the configured formula.
subroutine bfgs_update_hessian(self, step, dgrad, ok)
   !> Optimiser state
   class(landscape_bfgs_type), intent(inout) :: self
   !> Step `s` (bohr)
   real(wp), intent(in) :: step(:)
   !> Gradient difference `y` (hartree/bohr)
   real(wp), intent(in) :: dgrad(:)
   !> True if the update was applied
   logical, intent(out) :: ok

   call update_by_enum(self%update, step, dgrad, self%hess, ok)

end subroutine bfgs_update_hessian

end module xtb_landscape_bfgs
