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

!> Limited memory BFGS of the landscape suite.
!>
!> Two loop recursion of Nocedal, Math. Comp. 35, 773 (1980) and
!> Liu & Nocedal, Math. Prog. 45, 503 (1989).  Correction pairs `(s_i, y_i)`
!> are accepted only if the curvature condition
!> `s_i.y_i > 1e-12 |s_i| |y_i|` holds, which prevents the Hessian
!> approximation from becoming indefinite.  The initial inverse Hessian is
!> scaled with `gamma = s.y / y.y` of the most recent accepted pair, clamped
!> to `[1/curvature, curvature]`, and the first iteration falls back to
!> steepest descent because no history is available yet.
!>
!> Units: coordinates and steps in bohr, gradients in hartree/bohr.
module xtb_landscape_lbfgs
   use xtb_mctc_accuracy, only : wp
   implicit none(type, external)
   private

   public :: landscape_lbfgs_type, new_landscape_lbfgs

   !> L-BFGS history store.
   type :: landscape_lbfgs_type
      !> Maximum number of correction pairs
      integer :: memory = 5
      !> Number of stored correction pairs
      integer :: nstore = 0
      !> Curvature clamp of the initial inverse Hessian scaling
      real(wp) :: curvature = 70.0_wp
      !> Steps `s_i` (bohr), shape `(ndim, memory)`
      real(wp), allocatable :: s(:, :)
      !> Gradient differences `y_i` (hartree/bohr), shape `(ndim, memory)`
      real(wp), allocatable :: y(:, :)
      !> Inverse curvature `1/(y_i.s_i)`
      real(wp), allocatable :: rho(:)
   contains
      !> Drop the stored history
      procedure :: reset => lbfgs_reset
      !> Store a new correction pair (with curvature filtering)
      procedure :: push => lbfgs_push
      !> Compute the L-BFGS search direction
      procedure :: direction => lbfgs_direction
   end type landscape_lbfgs_type

   !> Relative curvature guard of the correction pairs
   real(wp), parameter :: curvature_guard = 1.0e-12_wp

contains

!> Allocate the history store of an L-BFGS optimiser.
subroutine new_landscape_lbfgs(self, ndim, memory, curvature)
   !> New optimiser state
   type(landscape_lbfgs_type), intent(out) :: self
   !> Dimension of the coordinate vector (3N)
   integer, intent(in) :: ndim
   !> Number of correction pairs kept in memory
   integer, intent(in) :: memory
   !> Curvature clamp, defaults to 70
   real(wp), intent(in), optional :: curvature

   if (present(curvature)) self%curvature = curvature
   self%memory = max(memory, 1)
   allocate(self%s(ndim, self%memory), source=0.0_wp)
   allocate(self%y(ndim, self%memory), source=0.0_wp)
   allocate(self%rho(self%memory), source=0.0_wp)
   self%nstore = 0

end subroutine new_landscape_lbfgs

!> Drop all stored correction pairs.
subroutine lbfgs_reset(self)
   !> Optimiser state
   class(landscape_lbfgs_type), intent(inout) :: self

   self%nstore = 0

end subroutine lbfgs_reset

!> Store a correction pair, dropping it if the curvature is insufficient.
subroutine lbfgs_push(self, step, dgrad)
   !> Optimiser state
   class(landscape_lbfgs_type), intent(inout) :: self
   !> Step `s` (bohr)
   real(wp), intent(in) :: step(:)
   !> Gradient difference `y` (hartree/bohr)
   real(wp), intent(in) :: dgrad(:)

   real(wp) :: sy, guard
   integer :: i

   sy = dot_product(step, dgrad)
   guard = curvature_guard*sqrt(dot_product(step, step)) &
      & *sqrt(dot_product(dgrad, dgrad))
   if (sy <= guard) return

   if (self%nstore >= self%memory) then
      do i = 2, self%memory
         self%s(:, i - 1) = self%s(:, i)
         self%y(:, i - 1) = self%y(:, i)
         self%rho(i - 1) = self%rho(i)
      end do
      self%nstore = self%memory - 1
   end if
   self%nstore = self%nstore + 1
   self%s(:, self%nstore) = step
   self%y(:, self%nstore) = dgrad
   self%rho(self%nstore) = 1.0_wp/sy

end subroutine lbfgs_push

!> Two loop recursion computing the L-BFGS direction `d = -H g`.
!>
!> The direction is a descent direction by construction; `steepest` is set if
!> the history was empty and the plain steepest descent direction was used.
subroutine lbfgs_direction(self, gradient, direction, ok, steepest)
   !> Optimiser state
   class(landscape_lbfgs_type), intent(in) :: self
   !> Gradient (hartree/bohr)
   real(wp), intent(in) :: gradient(:)
   !> Search direction (bohr)
   real(wp), intent(out) :: direction(:)
   !> Failure flag (allocation problems only)
   logical, intent(out) :: ok
   !> True if no history was available and `-g` was returned
   logical, intent(out), optional :: steepest

   real(wp), allocatable :: alpha(:), q(:)
   real(wp) :: beta, gamma, sy, yy
   integer :: i

   ok = .true.
   if (present(steepest)) steepest = .false.
   if (self%nstore <= 0) then
      direction = -gradient
      if (present(steepest)) steepest = .true.
      return
   end if

   allocate(alpha(self%nstore), q(size(gradient)))
   q = gradient
   do i = self%nstore, 1, -1
      alpha(i) = self%rho(i)*dot_product(self%s(:, i), q)
      q = q - alpha(i)*self%y(:, i)
   end do

   sy = dot_product(self%s(:, self%nstore), self%y(:, self%nstore))
   yy = dot_product(self%y(:, self%nstore), self%y(:, self%nstore))
   if (yy > tiny(1.0_wp)) then
      gamma = sy/yy
   else
      gamma = 1.0_wp
   end if
   gamma = min(max(gamma, 1.0_wp/self%curvature), self%curvature)
   q = gamma*q

   do i = 1, self%nstore
      beta = self%rho(i)*dot_product(self%y(:, i), q)
      q = q + (alpha(i) - beta)*self%s(:, i)
   end do

   direction = -q

end subroutine lbfgs_direction

end module xtb_landscape_lbfgs
