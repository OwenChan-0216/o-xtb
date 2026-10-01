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

!> Mathematical kernel of the growing string method (Peters, Heyden, Bell &
!> Chakraborty, J. Chem. Phys. **120**, 114101 (2004)).
!>
!> The string is a sequence of nodes `R_1, ..., R_m` between the two fixed
!> endpoints (`R_1` the reactant, `R_m` the product) that is relaxed
!> **perpendicular** to itself; a reparametrisation that keeps the nodes
!> equidistant in arc length, rather than a spring force, is what controls
!> the node distribution.  All routines of this module are pure mathematics
!> on plain arrays; the phases of the method (growth, optimisation, climbing
!> node) live in `xtb_landscape_path_gsm`.
!>
!> **Normal force** (Eq. 1).  With the unit tangent `tau` of the string at a
!> node,
!>
!>     `f_perp = -grad V + (tau . grad V) tau`
!>
!> is the component of the physical force perpendicular to the string.  A
!> node is "converged" when `f_perp` vanishes, i.e. when the string is the
!> minimum energy path at that node; the component along `tau` (which moves
!> the node along the path and does not change the path) is removed on
!> purpose, because the path, not the position of one node on it, is the
!> object being optimised.
!>
!> **Growth indicator** (Eq. 7).  `i(f_perp) = 1` if `|f_perp| <= tol` and
!> `0` otherwise.  The indicator gates the growth of the string: a new node
!> is appended only once the frontier node has relaxed perpendicular to the
!> string, so the growth never runs away from the path.  The norm of the
!> vector is used (not a component RMS), because Eq. 7 is written in terms of
!> the vector; the threshold `string_grow_tol` is therefore a norm in
!> hartree/bohr.
!>
!> **Arc length advance** (Eq. 9).  `a_1(k+1) = a_1(k) + ds * i(f_perp)`: the
!> arc length coordinate of the frontier advances by `ds` once, and only
!> once, the frontier node has converged perpendicular to the string.
!>
!> **Node spacing condition**.  A string whose nodes are too close together
!> develops a kink: the finite difference tangent of three nearly collinear
!> but unequally spaced nodes is dominated by the unequal spacing, so the
!> perpendicular force of Eq. 1 is misestimated.  The publication therefore
!> requires a minimum spacing
!>
!>     `R > |grad V . tau| / (2 nu2)`,
!>
!> where `nu2` is a lower bound of the curvature of the potential along the
!> string (the second derivative; for a saddle it is the magnitude of the
!> negative eigenvalue of the Hessian along the reaction coordinate).  The
!> curvature along the string is **unknown during the growth** - that is the
!> point of the growth - so `nu2` is a user supplied lower bound rather than
!> a measured quantity.  The default `nu2 = 5.0e-2` hartree/bohr^2 is an
!> **engineering default without a literature calibration** (report 38 L-10):
!> it is the value that makes the condition consistent with the calibrated
!> default spacing, i.e. for a `|gradV . tau|` of the order of 5e-2
!> hartree/bohr it gives the lower bound `R > 0.5` bohr of the default
!> `ds = 0.5` bohr.  The curvatures of the analytic reference surfaces are of
!> a different order and are quoted only to show the spread: the LEPS saddle
!> has `|lambda| = 1.0049` hartree/bohr^2 in its 9 Cartesian components (a
!> Cartesian Hessian eigenvalue, not a reaction coordinate curvature) and the
!> two dimensional Mueller-Brown saddle is of the order of 0.1-1 in its
!> dimensionless surface coordinates.  A system specific `nu2` cannot be
!> measured before the path is known; the cap `string_spacing_cap` is what
!> keeps a badly chosen value usable.
!>
!> **Tangent**.  Two conventions are available and both are implemented:
!> central differences of the node positions (`tau_k ~ R_{k+1} - R_{k-1}`,
!> one sided at the endpoints) and the derivative of a cubic spline through
!> the nodes, parametrised by arc length.  The spline tangent is the smoother
!> of the two and is the default; it is the idea of the existing
!> `cqpath_spline_repos` of `src/cqpath.f90` (reimplemented here, no code is
!> copied).  Its boundary condition is **not-a-knot**, because a natural
!> spline has an `O(h)` error in the end tangents that a measured comparison
!> on a quarter circle exposes (see `spline_derivatives`).  A degenerate knot
!> vector (two nodes on top of each other) and a string of fewer than four
!> nodes fall back to the central differences.
!>
!> **Reparametrisation**.  After every step the nodes are redistributed
!> equidistantly in arc length by linear interpolation along the
!> piecewise-linear string.  The endpoints never move.
!>
!> Units: coordinates and lengths in bohr, energies in hartree, gradients and
!> forces in hartree/bohr, curvature `nu2` in hartree/bohr^2.
module xtb_landscape_path_string
   use xtb_mctc_accuracy, only : wp
   implicit none(type, external)
   private

   public :: landscape_string_normal_force
   public :: landscape_string_growth_indicator
   public :: landscape_string_spacing
   public :: landscape_string_parallel_component
   public :: landscape_string_tangents
   public :: landscape_string_arc_length
   public :: landscape_string_reparameterize
   public :: landscape_string_component_rms

   !> Upper bound of the enlargement of the node spacing by the curvature
   !> condition, as a multiple of the requested spacing.  The condition
   !> `R > |grad V . tau| / (2 nu2)` is a **lower** bound of the spacing, and
   !> in a steep region of the surface it can demand a spacing far above the
   !> requested one.  A node placed that far from its parent lands in an even
   !> steeper region, so an uncapped condition is a measured positive feed
   !> back: the Mueller-Brown string of the unit tests reached a spacing of
   !> `3.2e2` bohr from a requested `0.5` and left the path completely.  The
   !> cap keeps the growth usable; a condition that binds at the cap is
   !> reported by the caller (`landscape_string_type%spacing_adjusted`) and is
   !> a signal that `nu2` is too small for the surface.
   real(wp), parameter :: string_spacing_cap = 2.0_wp

contains

!> Perpendicular component of the physical force at one node (Eq. 1).
!>
!> `f_perp = -grad V + (tau . grad V) tau`, i.e. the physical force with the
!> component along the string tangent removed.  The result is exactly
!> perpendicular to `tau` up to round off.
pure subroutine landscape_string_normal_force(gradient, tangent, force)
   !> Cartesian gradient (hartree/bohr), flattened in `x1, y1, z1, x2, ...`
   real(wp), intent(in) :: gradient(:)
   !> Unit tangent of the string at the node (dimensionless)
   real(wp), intent(in) :: tangent(:)
   !> Perpendicular force (hartree/bohr)
   real(wp), intent(out) :: force(:)

   real(wp) :: parallel

   parallel = dot_product(gradient, tangent)
   force = -gradient + parallel*tangent

end subroutine landscape_string_normal_force

!> Component of the gradient along the string tangent, `grad V . tau`.
!>
!> The absolute value of this scalar is the `|grad V . tau|` of the node
!> spacing condition; its sign distinguishes "the tangent points downhill"
!> from "the tangent points uphill".
pure function landscape_string_parallel_component(gradient, tangent) result(parallel)
   !> Cartesian gradient (hartree/bohr)
   real(wp), intent(in) :: gradient(:)
   !> Unit tangent (dimensionless)
   real(wp), intent(in) :: tangent(:)
   !> Scalar projection (hartree/bohr)
   real(wp) :: parallel

   parallel = dot_product(gradient, tangent)

end function landscape_string_parallel_component

!> Growth indicator of Eq. 7, `|f_perp| <= tol`.
!>
!> The **norm** of the perpendicular force is compared with the threshold,
!> exactly as the equation is written; the component RMS would differ by the
!> constant factor `sqrt(3 nat)`.
pure function landscape_string_growth_indicator(force, tol) result(ready)
   !> Perpendicular force (hartree/bohr)
   real(wp), intent(in) :: force(:)
   !> Threshold (hartree/bohr)
   real(wp), intent(in) :: tol
   !> True if the frontier node may grow (Eq. 7 gives 1)
   logical :: ready

   ready = sqrt(sum(force**2)) <= tol

end function landscape_string_growth_indicator

!> Component RMS of a force-like vector (hartree/bohr).
pure function landscape_string_component_rms(vector) result(rms)
   !> Vector (hartree/bohr)
   real(wp), intent(in) :: vector(:)
   !> Component RMS (hartree/bohr)
   real(wp) :: rms

   if (size(vector) < 1) then
      rms = 0.0_wp
   else
      rms = sqrt(sum(vector**2)/real(size(vector), wp))
   end if

end function landscape_string_component_rms

!> Node spacing of the next growth step.
!>
!> The spacing is the larger of the requested `ds` and the minimum
!> `R_min = |grad V . tau| / (2 nu2)` of the publication's node spacing
!> condition, capped at `string_spacing_cap * ds`.  `adjusted` reports whether
!> the curvature bound forced a larger spacing than requested, so the caller
!> can report it instead of silently changing the user's step.  A non positive
!> `nu2` or `ds` is an error (`fail = .true.`): the spacing condition cannot be
!> evaluated without a curvature bound, and the module never invents one.
pure subroutine landscape_string_spacing(gradient, tangent, ds, nu2, spacing, &
      & adjusted, fail)
   !> Cartesian gradient at the frontier node (hartree/bohr)
   real(wp), intent(in) :: gradient(:)
   !> Unit tangent at the frontier node (dimensionless)
   real(wp), intent(in) :: tangent(:)
   !> Requested spacing (bohr)
   real(wp), intent(in) :: ds
   !> Curvature floor (hartree/bohr^2)
   real(wp), intent(in) :: nu2
   !> Actual spacing (bohr)
   real(wp), intent(out) :: spacing
   !> True if the curvature bound enlarged the spacing
   logical, intent(out) :: adjusted
   !> Failure flag (a non positive curvature floor)
   logical, intent(out) :: fail

   real(wp) :: parallel, r_min

   fail = .true.
   spacing = ds
   adjusted = .false.
   if (nu2 <= 0.0_wp) return
   if (ds <= 0.0_wp) return
   parallel = abs(dot_product(gradient, tangent))
   r_min = parallel/(2.0_wp*nu2)
   if (r_min > ds) then
      spacing = min(r_min, string_spacing_cap*ds)
      adjusted = .true.
   end if
   fail = .false.

end subroutine landscape_string_spacing

!> Cumulative arc length of the string nodes (bohr).
!>
!> `arc(1) = 0` and `arc(k + 1) = arc(k) + |R_{k+1} - R_k|`; the last entry is
!> the total length of the piecewise-linear string.
pure subroutine landscape_string_arc_length(xyz, arc)
   !> String nodes `(3, nat, n_nodes)`
   real(wp), intent(in) :: xyz(:, :, :)
   !> Cumulative arc length (bohr), allocated on return
   real(wp), allocatable, intent(out) :: arc(:)

   integer :: k, n

   n = size(xyz, 3)
   allocate(arc(max(n, 1)), source=0.0_wp)
   do k = 2, n
      arc(k) = arc(k - 1) + sqrt(sum((xyz(:, :, k) - xyz(:, :, k - 1))**2))
   end do

end subroutine landscape_string_arc_length

!> Unit tangents of the string at every node.
!>
!> With `spline` the tangent is the arc length derivative of a cubic spline
!> (not-a-knot boundary, see `spline_derivatives`) through the nodes; without
!> it the central difference of the
!> neighbours is used (`R_{k+1} - R_{k-1}` for the interior nodes, the
!> one-sided difference at the two endpoints).  Both conventions return a
!> unit vector for every node; a node whose difference vector vanishes
!> degenerates to the first unit vector through the normalization guard of
!> `unit_vector`, so the caller never divides by zero.
subroutine landscape_string_tangents(xyz, tangents, spline)
   !> String nodes `(3, nat, n_nodes)`
   real(wp), intent(in) :: xyz(:, :, :)
   !> Unit tangents `(3*nat, n_nodes)`, allocated on return
   real(wp), allocatable, intent(out) :: tangents(:, :)
   !> Use the cubic spline tangent instead of central differences
   logical, intent(in) :: spline

   real(wp), allocatable :: flat(:, :)
   integer :: k, n, ndim
   logical :: fail

   ndim = 3*size(xyz, 2)
   n = size(xyz, 3)
   allocate(flat(ndim, max(n, 1)))
   do k = 1, n
      flat(:, k) = reshape(xyz(:, :, k), [ndim])
   end do
   allocate(tangents(ndim, max(n, 1)), source=0.0_wp)
   if (n < 2) return

   if (spline) then
      call spline_derivatives(flat, tangents, fail)
      if (fail) call difference_tangents(flat, tangents)
   else
      call difference_tangents(flat, tangents)
   end if
   do k = 1, n
      call unit_vector(tangents(:, k))
   end do

end subroutine landscape_string_tangents

!> Central (interior) and one-sided (endpoint) tangents of the nodes.
subroutine difference_tangents(flat, tangents)
   !> Node coordinates `(ndim, n_nodes)`
   real(wp), intent(in) :: flat(:, :)
   !> Tangents `(ndim, n_nodes)`
   real(wp), intent(out) :: tangents(:, :)

   integer :: k, n

   n = size(flat, 2)
   tangents = 0.0_wp
   if (n < 2) return
   do k = 2, n - 1
      tangents(:, k) = flat(:, k + 1) - flat(:, k - 1)
   end do
   tangents(:, 1) = flat(:, 2) - flat(:, 1)
   tangents(:, n) = flat(:, n) - flat(:, n - 1)

end subroutine difference_tangents

!> Arc length derivatives of a cubic spline through the nodes.
!>
!> The knots are the cumulative arc lengths of the piecewise-linear string,
!> the values are the `ndim = 3 nat` Cartesian components, and the returned
!> derivative is evaluated at the knots.  The boundary condition is
!> **not-a-knot** (the third derivative is continuous at the second and the
!> penultimate knot, i.e. the first two and the last two intervals share one
!> cubic each).  Measured on a quarter circle of 9 uniformly spaced nodes
!> (unit test `string-spline-tangent`), the not-a-knot tangents reproduce the
!> analytic tangent to `1.69e-4` while the central differences are off by
!> `4.91e-2`; a **natural** spline (zero second derivative at the ends) is
!> off by `1.6e-1` at the ends (report 36 section 7.5): the natural condition
!> forces the wrong curvature there, and its derivative error is only
!> `O(h)`.  The tangent of the string
!> is used by the perpendicular force of Eq. 1, so that bias is not
!> acceptable; the not-a-knot condition has the `O(h^4)` interior accuracy at
!> **every** knot.
!>
!> A non increasing knot vector (coinciding nodes) and a string of fewer than
!> four nodes are reported as `fail`; the caller then falls back to the
!> central differences (for three nodes the not-a-knot system is degenerate:
!> the two conditions coincide and leave the cubic determined by the three
!> points).
!>
!> The tridiagonal system is solved with the Thomas algorithm, which is exact
!> for its banded matrix and needs no LAPACK workspace.  The two not-a-knot
!> rows couple three unknowns each; they are used to **eliminate** the two
!> boundary second derivatives before the solve, so the reduced system stays
!> tridiagonal.
subroutine spline_derivatives(flat, tangents, fail)
   !> Node coordinates `(ndim, n_nodes)`
   real(wp), intent(in) :: flat(:, :)
   !> Spline derivatives at the knots `(ndim, n_nodes)`
   real(wp), intent(out) :: tangents(:, :)
   !> Failure flag (degenerate knot vector or fewer than four nodes)
   logical, intent(out) :: fail

   real(wp), allocatable :: h(:), m(:, :), rhs(:), sub(:), diag(:), super(:), work(:)
   real(wp) :: c, d
   integer :: k, i, n, ndim, m_int

   fail = .true.
   n = size(flat, 2)
   ndim = size(flat, 1)
   tangents = 0.0_wp
   if (n < 4) return

   allocate(h(n), source=0.0_wp)
   do k = 1, n - 1
      h(k) = sqrt(sum((flat(:, k + 1) - flat(:, k))**2))
      if (h(k) <= 1.0e-12_wp) return
   end do

   m_int = n - 2
   allocate(m(ndim, n), source=0.0_wp)
   allocate(rhs(m_int), sub(m_int), diag(m_int), super(m_int), work(m_int))

   ! reduced system on `M(2) .. M(n-1)`: row `k` belongs to the knot `k + 1`
   do k = 1, m_int
      i = k + 1
      diag(k) = 2.0_wp*(h(i - 1) + h(i))
      sub(k) = merge(h(i - 1), 0.0_wp, i > 2)
      super(k) = merge(h(i), 0.0_wp, i < n - 1)
   end do

   ! not-a-knot at the reactant end: eliminate `M(1)` from the equation of
   ! the knot 2 with `M(1) = (1 + h(1)/h(2)) M(2) - (h(1)/h(2)) M(3)`
   diag(1) = h(1)*(1.0_wp + h(1)/h(2)) + 2.0_wp*(h(1) + h(2))
   super(1) = h(2) - h(1)**2/h(2)

   ! not-a-knot at the product end: eliminate `M(n)` with
   ! `M(n) = -(h(n-1)/h(n-2)) M(n-2) + (1 + h(n-1)/h(n-2)) M(n-1)`
   c = h(n - 1)/h(n - 2)
   d = 1.0_wp + c
   diag(m_int) = 2.0_wp*(h(n - 2) + h(n - 1)) + h(n - 1)*d
   sub(m_int) = h(n - 2) - h(n - 1)*c
   super(m_int) = 0.0_wp

   ! solve one tridiagonal system per component
   do i = 1, ndim
      do k = 1, m_int
         rhs(k) = 6.0_wp*((flat(i, k + 2) - flat(i, k + 1))/h(k + 1) &
            & - (flat(i, k + 1) - flat(i, k))/h(k))
      end do
      ! `thomas` overwrites its right hand side with the solution; `work`
      ! only carries the eliminated diagonal
      call thomas(m_int, sub, diag, super, rhs, work)
      m(i, 2:n - 1) = rhs
   end do

   ! the eliminated boundary second derivatives
   m(:, 1) = (1.0_wp + h(1)/h(2))*m(:, 2) - (h(1)/h(2))*m(:, 3)
   m(:, n) = -c*m(:, n - 2) + d*m(:, n - 1)

   ! derivative at every knot from the interval on its left (right for the
   ! first node, which has no left interval)
   do k = 1, n
      if (k == 1) then
         tangents(:, 1) = (flat(:, 2) - flat(:, 1))/h(1) &
            & - (2.0_wp*m(:, 1) + m(:, 2))*h(1)/6.0_wp
      else
         tangents(:, k) = (flat(:, k) - flat(:, k - 1))/h(k - 1) &
            & - (2.0_wp*m(:, k - 1) + m(:, k))*h(k - 1)/6.0_wp &
            & + m(:, k - 1)*h(k - 1) &
            & + (m(:, k) - m(:, k - 1))*h(k - 1)/2.0_wp
      end if
   end do
   fail = .false.

end subroutine spline_derivatives

!> Thomas algorithm for a tridiagonal system (in place on `d`).
subroutine thomas(n, sub, diag, super, d, work)
   !> System size
   integer, intent(in) :: n
   !> Subdiagonal (`sub(1)` is unused)
   real(wp), intent(in) :: sub(:)
   !> Diagonal
   real(wp), intent(in) :: diag(:)
   !> Superdiagonal (`super(n)` is unused)
   real(wp), intent(in) :: super(:)
   !> Right hand side, overwritten with the solution
   real(wp), intent(inout) :: d(:)
   !> Workspace, length `n`
   real(wp), intent(out) :: work(:)

   real(wp) :: factor
   integer :: k

   if (n < 1) return
   work(1) = diag(1)
   if (abs(work(1)) <= tiny(1.0_wp)) then
      d = 0.0_wp
      return
   end if
   do k = 2, n
      factor = sub(k)/work(k - 1)
      work(k) = diag(k) - factor*super(k - 1)
      d(k) = d(k) - factor*d(k - 1)
   end do
   if (abs(work(n)) <= tiny(1.0_wp)) then
      d = 0.0_wp
      return
   end if
   d(n) = d(n)/work(n)
   do k = n - 1, 1, -1
      if (abs(work(k)) <= tiny(1.0_wp)) then
         d(k) = 0.0_wp
      else
         d(k) = (d(k) - super(k)*d(k + 1))/work(k)
      end if
   end do

end subroutine thomas

!> Normalize a vector in place; a zero vector becomes the first unit vector.
pure subroutine unit_vector(v)
   !> Vector, normalized in place
   real(wp), intent(inout) :: v(:)

   real(wp) :: norm

   norm = sqrt(sum(v**2))
   if (norm > 1.0e-16_wp) then
      v = v/norm
   else
      v = 0.0_wp
      if (size(v) > 0) v(1) = 1.0_wp
   end if

end subroutine unit_vector

!> Redistribute the string nodes equidistantly in arc length.
!>
!> The new nodes are taken from the piecewise-linear string by linear
!> interpolation at arc length positions `(k - 1)/(n - 1) * L`, so the node
!> count is preserved and the two endpoints are copied verbatim.  A string of
!> zero length or one with fewer than three nodes is returned unchanged: there
!> is no arc length to redistribute.
subroutine landscape_string_reparameterize(xyz, xyz_out)
   !> String nodes `(3, nat, n_nodes)`
   real(wp), intent(in) :: xyz(:, :, :)
   !> Redistributed nodes `(3, nat, n_nodes)`, allocated on return
   real(wp), allocatable, intent(out) :: xyz_out(:, :, :)

   real(wp), allocatable :: arc(:), one(:), two(:)
   real(wp) :: target, lam, total, seg
   integer :: j, k, n, nat

   nat = size(xyz, 2)
   n = size(xyz, 3)
   allocate(xyz_out(3, nat, n), source=xyz)
   if (n < 3) return
   call landscape_string_arc_length(xyz, arc)
   total = arc(n)
   if (total <= 1.0e-12_wp) return

   allocate(one(3*nat), two(3*nat))
   j = 1
   do k = 2, n - 1
      target = real(k - 1, wp)/real(n - 1, wp)*total
      do while (j < n - 1 .and. arc(j + 1) < target)
         j = j + 1
      end do
      seg = arc(j + 1) - arc(j)
      if (seg <= 1.0e-16_wp) then
         lam = 0.0_wp
      else
         lam = (target - arc(j))/seg
      end if
      lam = min(max(lam, 0.0_wp), 1.0_wp)
      one = reshape(xyz(:, :, j), [3*nat])
      two = reshape(xyz(:, :, j + 1), [3*nat])
      xyz_out(:, :, k) = reshape((1.0_wp - lam)*one + lam*two, [3, nat])
   end do
   xyz_out(:, :, 1) = xyz(:, :, 1)
   xyz_out(:, :, n) = xyz(:, :, n)

end subroutine landscape_string_reparameterize

end module xtb_landscape_path_string
