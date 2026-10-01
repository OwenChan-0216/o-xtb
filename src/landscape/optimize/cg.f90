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

!> Conjugate gradient minimiser of the landscape suite.
!>
!> Nonlinear conjugate gradients with the Polak-Ribiere+ update
!> (Polak & Ribiere, Rev. Franc. Inform. Rech. Oper. 16, 35 (1969);
!> Gilbert & Nocedal, SIAM J. Optim. 2, 21 (1992))
!>
!> ```
!> beta_k = max(0, g_k.(g_k - g_{k-1}) / (g_{k-1}.g_{k-1}))
!> d_k    = -g_k + beta_k d_{k-1}
!> ```
!>
!> This is Algorithm 5.4 of Nocedal & Wright, *Numerical Optimization*
!> (2nd ed., 2006).  Truncating the negative part of the classical
!> Polak-Ribiere coefficient is the restart mechanism of the method: it makes
!> `d_k` a descent direction for every step size and restores the global
!> convergence properties of the Fletcher-Reeves variant.  The direction is
!> additionally reset to steepest descent if the conjugated direction is not a
!> descent direction (`g_k.d_k >= 0`), if no correction pair is stored (first
!> iteration), or if the caller dropped the history after a rejected step or a
!> steepest descent fallback (`reset`).
!>
!> Deliberate deviation from PLAN section 6.1: Powell's alignment restart
!> (`|g_k.g_{k-1}|/|g_k|^2 >= 0.2`, Powell, Math. Prog. 12, 241 (1977)) is
!> **not** applied.  It presupposes a line search that satisfies a curvature
!> condition; the suite deliberately uses Armijo backtracking only
!> (PLAN section 5.3.4), for which successive gradients of a descent path stay
!> strongly aligned.  Measured on the four dimensional test quadratic
!> (`test/unit/test_landscape_cg.f90`, `k = (0.1, 1, 10, 100)`): with the
!> alignment test the iteration needs 337 steps, without it 190 steps, while
!> steepest descent needs 3439 steps; on GFN2 water the alignment test made the
!> conjugate gradient reproduce steepest descent bitwise.
!>
!> The caller is responsible for clipping the step to the maximum
!> displacement; the stored direction is the one that was actually used, so a
!> clipped direction enters the next `beta` exactly as it entered the line
!> search.
!>
!> Units: coordinates and steps in bohr, gradients in hartree/bohr.
module xtb_landscape_cg
   use xtb_mctc_accuracy, only : wp
   implicit none(type, external)
   private

   public :: landscape_cg_type, new_landscape_cg

   !> Conjugate gradient state.
   type :: landscape_cg_type
      !> Number of iterations whose direction fell back to steepest descent
      !> (the first iteration always does, no history exists yet)
      integer :: n_restart = 0
      !> True once a correction pair has been stored
      logical :: has_history = .false.
      !> Gradient of the previous accepted step (hartree/bohr)
      real(wp), allocatable :: g_prev(:)
      !> Direction of the previous accepted step (bohr)
      real(wp), allocatable :: d_prev(:)
   contains
      !> Drop the stored history without counting a restart
      procedure :: reset => cg_reset
      !> Store the gradient and direction of an accepted step
      procedure :: push => cg_push
      !> Conjugate gradient direction
      procedure :: direction => cg_direction
   end type landscape_cg_type

contains

!> Allocate the state of a conjugate gradient minimiser.
subroutine new_landscape_cg(self, ndim)
   !> New optimiser state
   type(landscape_cg_type), intent(out) :: self
   !> Dimension of the coordinate vector (3N)
   integer, intent(in) :: ndim

   allocate(self%g_prev(ndim), source=0.0_wp)
   allocate(self%d_prev(ndim), source=0.0_wp)
   self%has_history = .false.
   self%n_restart = 0

end subroutine new_landscape_cg

!> Drop the stored correction pair.
!>
!> Called by the driver after a rejected step or after a steepest descent
!> fallback, because the stored direction was then not the one that produced
!> the new gradient.
subroutine cg_reset(self)
   !> Optimiser state
   class(landscape_cg_type), intent(inout) :: self

   self%has_history = .false.

end subroutine cg_reset

!> Store the gradient and the direction of an accepted step.
subroutine cg_push(self, gradient, direction)
   !> Optimiser state
   class(landscape_cg_type), intent(inout) :: self
   !> Gradient before the accepted step (hartree/bohr)
   real(wp), intent(in) :: gradient(:)
   !> Direction of the accepted step (bohr)
   real(wp), intent(in) :: direction(:)

   self%g_prev = gradient
   self%d_prev = direction
   self%has_history = .true.

end subroutine cg_push

!> Polak-Ribiere+ direction with the negative coefficient truncated to zero.
!>
!> `restarted` reports whether the steepest descent direction was returned
!> instead of the conjugated one.
subroutine cg_direction(self, gradient, direction, restarted)
   !> Optimiser state
   class(landscape_cg_type), intent(inout) :: self
   !> Current gradient (hartree/bohr)
   real(wp), intent(in) :: gradient(:)
   !> Search direction (bohr)
   real(wp), intent(out) :: direction(:)
   !> True if the direction was reset to steepest descent
   logical, intent(out), optional :: restarted

   real(wp) :: gg_prev, beta
   logical :: fallback

   fallback = .true.

   if (self%has_history) then
      gg_prev = dot_product(self%g_prev, self%g_prev)
      if (gg_prev > tiny(1.0_wp)) then
         beta = dot_product(gradient, gradient - self%g_prev)/gg_prev
         if (beta > 0.0_wp) then
            direction = -gradient + beta*self%d_prev
            ! only keep the conjugated direction if it still descends
            if (dot_product(gradient, direction) < 0.0_wp) fallback = .false.
         end if
      end if
   end if

   if (fallback) then
      direction = -gradient
      self%n_restart = self%n_restart + 1
   end if

   if (present(restarted)) restarted = fallback

end subroutine cg_direction

end module xtb_landscape_cg
