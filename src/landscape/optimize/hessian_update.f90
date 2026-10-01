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

!> Hessian update formulas of the landscape suite.
!>
!> All routines update a dense Hessian approximation `B` (hartree/bohr^2)
!> from a step `s = x_new - x_old` (bohr) and a gradient difference
!> `y = g_new - g_old` (hartree/bohr).  Every update (i) enforces symmetry,
!> (ii) checks the curvature `s.y` and the denominators against relative
!> guards and (iii) reports through `ok` whether the update was actually
!> applied.  A rejected update leaves `B` untouched.
!>
!> References:
!>  * BFGS: Broyden (1970), Fletcher (1970), Goldfarb (1970), Shanno (1970);
!>    the Powell damping follows `src/bfgs.f90:164` and
!>    Powell, Math. Prog. 1, 26 (1971).
!>  * SR1: Murtagh & Sargent, Comput. J. 13, 185 (1970).
!>  * Bofill: Bofill, J. Comput. Chem. 15, 1 (1994), Eq. (8).
!>  * Powell (symmetric Broyden): Powell, Math. Prog. 1, 26 (1971);
!>    the same formula is used by `src/bfgs.f90:105`.
module xtb_landscape_hessian_update
   use xtb_mctc_accuracy, only : wp
   use xtb_landscape_settings, only : p_landscape_hess_update_bfgs, &
      & p_landscape_hess_update_sr1, p_landscape_hess_update_bofill, &
      & p_landscape_hess_update_powell
   implicit none(type, external)
   private

   public :: symmetrize_hessian
   public :: update_bfgs, update_sr1, update_bofill, update_powell, update_by_enum

   !> Relative guard below which a scalar product is considered degenerate
   real(wp), parameter :: curvature_guard = 1.0e-12_wp
   !> Relative guard of the SR1 denominator `s.(y - B s)`
   real(wp), parameter :: sr1_guard = 1.0e-8_wp
   !> Powell damping factor (0.8 in the original publication)
   real(wp), parameter :: powell_theta = 0.8_wp

contains

!> Force a matrix to be exactly symmetric.
pure subroutine symmetrize_hessian(hess)
   !> Matrix to symmetrise
   real(wp), intent(inout) :: hess(:, :)

   hess = 0.5_wp*(hess + transpose(hess))

end subroutine symmetrize_hessian

!> BFGS update of a dense Hessian approximation with Powell damping.
!>
!> If the curvature is insufficient, `y` is damped towards `B s`,
!> `ybar = theta y + (1 - theta) B s` with
!> `theta = 0.8 s.B s / (s.B s - s.y)` for `s.y < 0.2 s.B s`, which keeps the
!> updated Hessian positive definite (Powell, Math. Prog. 1, 26 (1971)).
pure subroutine update_bfgs(step, dgrad, hess, ok)
   !> Step `s` (bohr)
   real(wp), intent(in) :: step(:)
   !> Gradient difference `y` (hartree/bohr)
   real(wp), intent(in) :: dgrad(:)
   !> Hessian approximation (hartree/bohr^2), updated in place
   real(wp), intent(inout) :: hess(:, :)
   !> True if the update was applied
   logical, intent(out) :: ok

   real(wp), allocatable :: hs(:), ybar(:)
   real(wp) :: sy, shs, ss, yy, theta, denom, guard

   ok = .false.
   hs = matmul(hess, step)
   ss = dot_product(step, step)
   yy = dot_product(dgrad, dgrad)
   shs = dot_product(step, hs)
   sy = dot_product(step, dgrad)
   guard = curvature_guard*sqrt(ss)*sqrt(yy)

   if (shs <= curvature_guard*max(ss, 1.0_wp)) return

   theta = 1.0_wp
   if (sy < 0.2_wp*shs) then
      denom = shs - sy
      if (abs(denom) <= curvature_guard*abs(shs)) return
      theta = powell_theta*shs/denom
      theta = min(max(theta, 0.0_wp), 1.0_wp)
   end if

   ybar = theta*dgrad + (1.0_wp - theta)*hs
   sy = dot_product(step, ybar)
   if (abs(sy) <= max(guard, curvature_guard*ss)) return

   call add_outer(hess, ybar, ybar, 1.0_wp/sy)
   call add_outer(hess, hs, hs, -1.0_wp/shs)
   call symmetrize_hessian(hess)
   ok = .true.

end subroutine update_bfgs

!> SR1 update, `B+ = B + u u^T/(u^T s)` with `u = y - B s`.
!>
!> Skipped when `|s.u|` is small compared to `|s| |u|`, because the update is
!> then numerically ill-defined (Murtagh & Sargent, Comput. J. 13, 185 (1970)).
pure subroutine update_sr1(step, dgrad, hess, ok)
   !> Step `s` (bohr)
   real(wp), intent(in) :: step(:)
   !> Gradient difference `y` (hartree/bohr)
   real(wp), intent(in) :: dgrad(:)
   !> Hessian approximation, updated in place
   real(wp), intent(inout) :: hess(:, :)
   !> True if the update was applied
   logical, intent(out) :: ok

   real(wp), allocatable :: u(:)
   real(wp) :: su, guard

   ok = .false.
   u = dgrad - matmul(hess, step)
   su = dot_product(step, u)
   guard = sr1_guard*sqrt(dot_product(step, step))*sqrt(dot_product(u, u))
   if (abs(su) <= max(guard, tiny(1.0_wp))) return

   call add_outer(hess, u, u, 1.0_wp/su)
   call symmetrize_hessian(hess)
   ok = .true.

end subroutine update_sr1

!> Bofill update, a rational interpolation between the MS (BFGS-like) and the
!> SR1 update.
!>
!> With `u = y - B s` the weight is
!> `phi = (u.s)^2 / ((u.s)^2 + (y.s)^2)`, so the update reduces to SR1 when
!> `u` is parallel to `s` and to the MS update otherwise
!> (Bofill, J. Comput. Chem. 15, 1 (1994), Eq. (8)).  Both components fulfil
!> the secant condition individually, so the interpolated Hessian does as well.
!>
!> `ok` is true only if at least one of the two rank-one components was
!> actually added; a pair that is skipped by both guards leaves `B` unchanged
!> and is reported as not applied.
pure subroutine update_bofill(step, dgrad, hess, ok)
   !> Step `s` (bohr)
   real(wp), intent(in) :: step(:)
   !> Gradient difference `y` (hartree/bohr)
   real(wp), intent(in) :: dgrad(:)
   !> Hessian approximation, updated in place
   real(wp), intent(inout) :: hess(:, :)
   !> True if the update was applied
   logical, intent(out) :: ok

   real(wp), allocatable :: hs(:), u(:)
   real(wp) :: su, sy, shs, ss, uu, yy, phi, guard_su, guard_sy
   logical :: sr1_added, ms_added

   ok = .false.
   hs = matmul(hess, step)
   u = dgrad - hs
   ss = dot_product(step, step)
   su = dot_product(step, u)
   sy = dot_product(step, dgrad)
   shs = dot_product(step, hs)
   uu = dot_product(u, u)
   yy = dot_product(dgrad, dgrad)

   guard_su = sr1_guard*sqrt(ss)*sqrt(uu)
   guard_sy = curvature_guard*sqrt(ss)*sqrt(yy)
   if (abs(su) <= guard_su .and. abs(sy) <= guard_sy) return

   if (abs(su) <= guard_su) then
      phi = 0.0_wp
   else if (abs(sy) <= guard_sy) then
      phi = 1.0_wp
   else
      phi = su**2/(su**2 + sy**2)
   end if

   sr1_added = abs(su) > guard_su
   ms_added = abs(sy) > guard_sy .and. shs > curvature_guard*max(ss, 1.0_wp)
   if (sr1_added) then
      call add_outer(hess, u, u, phi/su)
   end if
   if (ms_added) then
      call add_outer(hess, dgrad, dgrad, (1.0_wp - phi)/sy)
      call add_outer(hess, hs, hs, -(1.0_wp - phi)/shs)
   end if

   if (.not. (sr1_added .or. ms_added)) return

   call symmetrize_hessian(hess)
   ok = .true.

end subroutine update_bofill

!> Powell (symmetric Broyden) update.
!>
!> `B+ = B + (u s^T + s u^T)/(s.s) - (u.s)/(s.s)^2 s s^T` with `u = y - B s`.
!> The update is symmetric by construction and fulfils the secant condition
!> (Powell, Math. Prog. 1, 26 (1971)).
pure subroutine update_powell(step, dgrad, hess, ok)
   !> Step `s` (bohr)
   real(wp), intent(in) :: step(:)
   !> Gradient difference `y` (hartree/bohr)
   real(wp), intent(in) :: dgrad(:)
   !> Hessian approximation, updated in place
   real(wp), intent(inout) :: hess(:, :)
   !> True if the update was applied
   logical, intent(out) :: ok

   real(wp), allocatable :: u(:)
   real(wp) :: ss, su, fac
   integer :: i, j, n

   ok = .false.
   ss = dot_product(step, step)
   n = size(step)
   if (ss <= tiny(1.0_wp)) return

   u = matmul(hess, step)
   u = dgrad - u
   su = dot_product(step, u)
   fac = su/ss

   do j = 1, n
      do i = 1, n
         hess(i, j) = hess(i, j) + (u(i)*step(j) + step(i)*u(j) - step(i)*fac*step(j))/ss
      end do
   end do
   call symmetrize_hessian(hess)
   ok = .true.

end subroutine update_powell

!> Dispatch to the Hessian update selected by the settings identifier.
pure subroutine update_by_enum(update, step, dgrad, hess, ok)
   !> Update formula identifier, see `xtb_landscape_settings`
   integer, intent(in) :: update
   !> Step `s` (bohr)
   real(wp), intent(in) :: step(:)
   !> Gradient difference `y` (hartree/bohr)
   real(wp), intent(in) :: dgrad(:)
   !> Hessian approximation, updated in place
   real(wp), intent(inout) :: hess(:, :)
   !> True if the update was applied
   logical, intent(out) :: ok

   select case (update)
   case (p_landscape_hess_update_bfgs)
      call update_bfgs(step, dgrad, hess, ok)
   case (p_landscape_hess_update_sr1)
      call update_sr1(step, dgrad, hess, ok)
   case (p_landscape_hess_update_bofill)
      call update_bofill(step, dgrad, hess, ok)
   case (p_landscape_hess_update_powell)
      call update_powell(step, dgrad, hess, ok)
   case default
      ok = .false.
   end select

end subroutine update_by_enum

!> Add the rank one matrix `fac * a b^T` to `hess`.
pure subroutine add_outer(hess, a, b, fac)
   !> Matrix to update
   real(wp), intent(inout) :: hess(:, :)
   !> Left vector
   real(wp), intent(in) :: a(:)
   !> Right vector
   real(wp), intent(in) :: b(:)
   !> Scaling factor
   real(wp), intent(in) :: fac

   integer :: i, j

   do j = 1, size(hess, 2)
      do i = 1, size(hess, 1)
         hess(i, j) = hess(i, j) + fac*a(i)*b(j)
      end do
   end do

end subroutine add_outer

end module xtb_landscape_hessian_update
