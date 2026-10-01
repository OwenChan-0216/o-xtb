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

!> Steepest descent direction of the landscape suite.
!>
!> The steepest descent (SD) direction is `d = -g`, optionally restricted to
!> the subspace orthogonal to a set of directions (not required for M1, the
!> displacement clipping is done by the driver).  SD is only used as a robust
!> fallback direction, for example when a quasi-Newton step fails or when the
!> line search rejects a step repeatedly.
!>
!> Units: gradient in hartree/bohr, direction in bohr.
module xtb_landscape_sd
   use xtb_mctc_accuracy, only : wp
   implicit none(type, external)
   private

   public :: landscape_sd_direction

contains

!> Steepest descent direction `d = -g`.
pure subroutine landscape_sd_direction(gradient, direction)
   !> Cartesian gradient (hartree/bohr)
   real(wp), intent(in) :: gradient(:)
   !> Search direction (bohr), equal to `-gradient`
   real(wp), intent(out) :: direction(:)

   direction = -gradient

end subroutine landscape_sd_direction

end module xtb_landscape_sd
