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

!> Subspace of the coordinates that `$fix` leaves free.
!>
!> xtb treats `$fix` in the **calculator**: `src/xtb/calculator.f90:304-306`
!> zeroes the gradient of every fixed atom (and the same happens in the other
!> calculators).  For a **first order** search direction that is sufficient,
!> because every such direction is a linear combination of the gradient and of
!> history vectors that inherit its zeros (the seed qualification of BFGS
!> below is the one exception):
!>
!>  * SD: `d = -g` (`optimize/sd.f90:43`)
!>  * CG: `d = -g + beta*d_old`, both terms zero on a fixed atom
!>    (`optimize/cg.f90`)
!>  * L-BFGS: the inverse Hessian is built from the correction pairs
!>    `(s, y)`, and both are zero on the fixed components, which keeps the
!>    fixed block of the matrix decoupled from the free one
!>    (`optimize/lbfgs.f90`)
!>  * BFGS: the update has the same property, but **only when its seed is
!>    decoupled as well**.  The default seed is `hlow*I`, which is; with
!>    `--lopt-hessian model` the approximation is seeded with the Lindh-D2
!>    curvature matrix (`landscape_bfgs%set_hessian`, reached from
!>    `optimize/driver.f90`), whose fixed and free blocks are coupled, and the
!>    direction is expanded in the eigenvectors of that matrix
!>    (`d = -sum_i (V_i.g)/max(w_i, hlow) V_i`, `optimize/bfgs.f90`), so the
!>    fixed components of the direction need not vanish and the projection is
!>    **not** a no-op for `--lopt-engine bfgs --lopt-hessian model` + `$fix`
!>    (covered by the CLI check `xtb/landscape-fix-rfo`,
!>    `test/unit/landscape_cli_check.py`)
!>  * GDIIS: `d = sum_i c_i x_i - x` with `sum_i c_i = 1` and every stored
!>    geometry equal to the current one on the fixed components
!>    (`optimize/diis.f90:202`)
!>
!> A **second order** step does not have that property either.  The RFO step
!> `d = -sum_i (V_i.g)/(w_i - lambda) V_i` (`optimize/rfo.f90`) is expanded in
!> the eigenvectors of the Hessian, and those mix the free and the fixed
!> components even when `g` vanishes on the fixed ones, so a fixed atom moves.
!> The fix is the projection onto the subspace `$fix` leaves free - the same
!> structural treatment ANCopt applies through its reduced variable set
!> (`nvar = nat3 - 3*fixset%n`, `src/optimizer.f90:367-371`) and its `trproj`
!> call (`src/optimizer.f90:501`).
!>
!> Units: the mask is a per Cartesian component (3N) logical array, the
!> components are ordered `x1, y1, z1, x2, ...` exactly like the flattened
!> geometries of `xtb_landscape_coords`.
module xtb_landscape_constraints
   use xtb_mctc_accuracy, only : wp
   use xtb_fixparam, only : fixset
   implicit none(type, external)
   private

   public :: landscape_frozen_mask, landscape_project_frozen
   public :: landscape_project_fixed_atoms

contains

!> Mask of the Cartesian components held fixed by `$fix` (length `3*nat`).
!>
!> `fixset` is the parameter state of xtb; it is filled by
!> `xtb_constrain_param::read_userdata` before any task runs (the
!> `read_userdata` call of the program driver).  A component is frozen when its atom is listed
!> in `$fix`; `$freeze` (the Hessian-only variant) is deliberately **not**
!> considered, because it changes the Hessian projection and not the
!> optimisation.
function landscape_frozen_mask(nat) result(frozen)
   !> Number of atoms
   integer, intent(in) :: nat
   !> Frozen mask (length `3*nat`)
   logical, allocatable :: frozen(:)

   integer :: i, iat

   allocate(frozen(3*nat), source=.false.)
   if (fixset%n <= 0) return
   if (.not. allocated(fixset%atoms)) return
   do i = 1, min(fixset%n, size(fixset%atoms))
      iat = fixset%atoms(i)
      ! atom indices are 1-based (`fix_setvar%atoms`, `src/fixparam.f90`); a
      ! value outside the molecule is ignored rather than corrupting memory
      if (iat < 1 .or. iat > nat) cycle
      frozen(3*(iat - 1) + 1:3*(iat - 1) + 3) = .true.
   end do

end function landscape_frozen_mask

!> Remove the frozen components of a Cartesian vector.
!>
!> `vector` and `frozen` must have the same length.  The operation is the
!> orthogonal projection onto the subspace `$fix` leaves free; it preserves a
!> descent direction, because the gradient vanishes on the removed components.
pure subroutine landscape_project_frozen(vector, frozen)
   !> Cartesian vector (bohr for a step, hartree/bohr for a gradient)
   real(wp), intent(inout) :: vector(:)
   !> Frozen mask (length of `vector`)
   logical, intent(in) :: frozen(:)

   if (size(vector) /= size(frozen)) return
   where (frozen) vector = 0.0_wp

end subroutine landscape_project_frozen

!> Remove the `$fix` components of a step, reading the mask from the xtb
!> parameter state.
!>
!> This is the entry point of the methods that **do not** carry a mask argument:
!> the transition state searches (`saddle/prfo` for P-RFO and B-PRFO, and
!> `saddle/dimer`).  Going through `fixset` here is deliberate: it makes
!> the parameter state the **single** source of truth for "which atoms are
!> fixed", so a search loop cannot end up with a different opinion than the
!> minimiser of `optimize/driver` (which receives the mask from
!> `landscape_frozen_mask` at its call site).
!>
!> The band searches (`path/`) and the reaction path correctors (`irc/`)
!> do **not** use this entry point: they **refuse** a frozen parameter state
!> with an error instead, because the reaction path advance is defined in
!> mass weighted arc length and the interaction of a frozen subspace with that
!> metric (and with the LQA `sum n` fixed point) is not settled yet.  Reporting
!> the refusal loudly is deliberate - silently ignoring `$fix` would produce a
!> path that walks through the frozen atoms.
!>
!> `vector` is a Cartesian step of a whole geometry (length `3N`); a length that
!> is not a multiple of three leaves the tail untouched.
subroutine landscape_project_fixed_atoms(vector)
   !> Cartesian step (bohr), modified in place
   real(wp), intent(inout) :: vector(:)

   integer :: nat

   if (fixset%n <= 0) return
   if (.not. allocated(fixset%atoms)) return
   nat = size(vector)/3
   if (nat <= 0) return
   call landscape_project_atom_list(vector, nat)

end subroutine landscape_project_fixed_atoms

!> Zero the three components of every atom of `fixset` that lies inside `nat`.
subroutine landscape_project_atom_list(vector, nat)
   !> Cartesian step (bohr), modified in place
   real(wp), intent(inout) :: vector(:)
   !> Number of atoms of the step
   integer, intent(in) :: nat

   integer :: i, iat, n

   if (size(vector) < 3*nat) return
   n = min(fixset%n, size(fixset%atoms))
   do i = 1, n
      iat = fixset%atoms(i)
      if (iat < 1 .or. iat > nat) cycle
      vector(3*(iat - 1) + 1:3*(iat - 1) + 3) = 0.0_wp
   end do

end subroutine landscape_project_atom_list

end module xtb_landscape_constraints
