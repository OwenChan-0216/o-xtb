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

!> Image dependent pair potential (IDPP) initial path of the chain-of-states
!> searches (Smidstrup, Pedersen, Stokbro & Jonsson, J. Chem. Phys. **140**,
!> 214106 (2014)).
!>
!> The IDPP path is the answer to a purely geometric question: given a
!> reactant and a product, what does a "smooth" sequence of geometries
!> between them look like?  A straight linear interpolation of the Cartesian
!> coordinates is **not** an answer: two atoms that are far apart in the
!> reactant and close together in the product traverse a region in which the
!> interpolated pair distance first grows and then shrinks, so the
!> interpolated path contains a spurious maximum and, worse, one and the same
!> pair distance can appear twice with different neighbouring geometries
!> (the "discontinuity" of the original publication).  The resulting band
!> then has to be dragged onto the minimum energy path by the elastic band
!> force, which costs iterations and can leave images stuck on the wrong side
!> of a barrier.
!>
!> IDPP replaces the interpolation of **positions** by an interpolation of
!> **pair distances** followed by a relaxation that realises those distances.
!> For the internal image `k` of a band with `n_images` frames,
!> `lam = (k - 1)/(n_images - 1)`, the target inverse pair distances are
!>
!>     `t_ab = (1 - lam)/d_ab^reactant + lam/d_ab^product`,
!>
!> and the image is the minimiser of the dimensionless objective
!>
!>     `S(x) = sum_{a<b} (1/|x_a - x_b| - t_ab)^2`
!>
!> (Eq. 4 of the publication, with the uniform weight `w = 1`; a
!> distance dependent weight is the "weighted" variant used for strongly
!> inhomogeneous systems and is deliberately not implemented here).  `S` is
!> a pure function of the geometry: **no energy evaluation is needed**, which
!> is what makes IDPP cheap enough to be the default initial path of a band.
!> Each internal image is independent of the others and is relaxed on its
!> own with the L-BFGS of `xtb_landscape_lbfgs`; the two endpoints are never
!> touched.
!>
!> Units: coordinates and distances in bohr, the objective in 1/bohr^2 and
!> its gradient in 1/bohr^3.  The step length criterion is a length in bohr.
module xtb_landscape_path_idpp
   use xtb_mctc_accuracy, only : wp
   use xtb_type_environment, only : TEnvironment
   use xtb_landscape_lbfgs, only : landscape_lbfgs_type, new_landscape_lbfgs
   implicit none(type, external)
   private

   public :: landscape_idpp_path
   public :: landscape_idpp_pair_count, landscape_idpp_pair_indices
   public :: landscape_idpp_targets, landscape_idpp_objective

   !> Default maximum number of L-BFGS iterations per internal image
   integer, parameter :: idpp_max_steps = 400
   !> Default upper bound of one displacement component (bohr)
   real(wp), parameter :: idpp_max_displ = 1.0e-1_wp
   !> Default step length below which an image counts as relaxed (bohr)
   real(wp), parameter :: idpp_step_tol = 1.0e-4_wp
   !> Number of L-BFGS correction pairs of the IDPP relaxation
   integer, parameter :: idpp_lbfgs_memory = 7
   !> Minimum pair distance used by the inverse distance guard (bohr)
   real(wp), parameter :: idpp_min_distance = 1.0e-8_wp

contains

!> Number of atom pairs `nat (nat - 1)/2`.
pure function landscape_idpp_pair_count(nat) result(npair)
   !> Number of atoms
   integer, intent(in) :: nat
   !> Number of pairs
   integer :: npair

   npair = nat*(nat - 1)/2

end function landscape_idpp_pair_count

!> Upper triangular pair list `(a, b)` with `a < b`, shape `(2, npair)`.
!>
!> The order of the list is the order of the target vector of
!> `landscape_idpp_targets` and of the gradient of
!> `landscape_idpp_objective`, so all three can be passed around together.
pure function landscape_idpp_pair_indices(nat) result(pairs)
   !> Number of atoms
   integer, intent(in) :: nat
   !> Pair list, shape `(2, nat*(nat-1)/2)`
   integer, allocatable :: pairs(:, :)

   integer :: a, b, p

   allocate(pairs(2, landscape_idpp_pair_count(nat)))
   p = 0
   do a = 1, nat
      do b = a + 1, nat
         p = p + 1
         pairs(1, p) = a
         pairs(2, p) = b
      end do
   end do

end function landscape_idpp_pair_indices

!> Target inverse pair distances of one internal image.
!>
!> `lam` is the position of the image in the band (`0` at the reactant, `1`
!> at the product).  The inverse distances are interpolated linearly, which
!> is the convention of the reference implementation and of the ASE
!> `IDPP` class; interpolating the distances themselves is the variant of
!> the original publication that behaves poorly for pairs whose distance
!> changes sign of curvature along the path.
pure function landscape_idpp_targets(reactant, product, lam) result(target)
   !> Reactant geometry (bohr), shape `(3, nat)`
   real(wp), intent(in) :: reactant(:, :)
   !> Product geometry (bohr), shape `(3, nat)`
   real(wp), intent(in) :: product(:, :)
   !> Position of the image in the band
   real(wp), intent(in) :: lam
   !> Target inverse pair distances (1/bohr), length `nat*(nat-1)/2`
   real(wp), allocatable :: target(:)

   real(wp), allocatable :: inv0(:), inv1(:)
   integer :: i

   inv0 = inverse_pair_distances(reactant)
   inv1 = inverse_pair_distances(product)
   allocate(target(size(inv0)))
   do i = 1, size(target)
      target(i) = (1.0_wp - lam)*inv0(i) + lam*inv1(i)
   end do

end function landscape_idpp_targets

!> Inverse pair distances of a geometry (1/bohr), length `nat*(nat-1)/2`.
!>
!> A zero pair distance would make the objective infinite; it is replaced by
!> `idpp_min_distance`, which only affects a degenerate input geometry (two
!> atoms on top of each other) and keeps the relaxation finite.
pure function inverse_pair_distances(xyz) result(inv)
   !> Geometry (bohr), shape `(3, nat)`
   real(wp), intent(in) :: xyz(:, :)
   !> Inverse pair distances (1/bohr)
   real(wp), allocatable :: inv(:)

   real(wp) :: xyz_dist
   integer, allocatable :: pairs(:, :)
   integer :: p

   pairs = landscape_idpp_pair_indices(size(xyz, 2))
   allocate(inv(size(pairs, 2)))
   do p = 1, size(pairs, 2)
      xyz_dist = pair_distance(xyz, pairs(1, p), pairs(2, p))
      inv(p) = 1.0_wp/max(xyz_dist, idpp_min_distance)
   end do

end function inverse_pair_distances

!> Euclidean distance between two atoms of a geometry.
pure function pair_distance(xyz, a, b) result(dist)
   !> Geometry (bohr)
   real(wp), intent(in) :: xyz(:, :)
   !> First atom
   integer, intent(in) :: a
   !> Second atom
   integer, intent(in) :: b
   !> Pair distance (bohr)
   real(wp) :: dist

   dist = sqrt(sum((xyz(:, a) - xyz(:, b))**2))

end function pair_distance

!> IDPP objective and its analytic gradient for one image.
!>
!> `x` is the flattened geometry (`x1, y1, z1, x2, ...`), `target` the array
!> of target inverse pair distances returned by `landscape_idpp_targets`.
!> The energy is `sum (1/d - t)^2` (1/bohr^2) and the gradient is its exact
!> derivative with respect to the Cartesian coordinates (1/bohr^3); the
!> derivative of one pair contribution with respect to the pair distance
!> `d` is `dS/dd = -2 (1/d - t)/d^2`.
pure subroutine landscape_idpp_objective(x, target, value, gradient)
   !> Flattened geometry (bohr), length `3 nat`
   real(wp), intent(in) :: x(:)
   !> Target inverse pair distances (1/bohr)
   real(wp), intent(in) :: target(:)
   !> Objective (1/bohr^2)
   real(wp), intent(out) :: value
   !> Gradient (1/bohr^3), length `3 nat`
   real(wp), intent(out) :: gradient(:)

   real(wp) :: xyz(3, max(size(x)/3, 1)), diff, dist, dsd, scale
   real(wp) :: dr(3)
   integer, allocatable :: pairs(:, :)
   integer :: p, a, b, nat

   nat = size(x)/3
   value = 0.0_wp
   gradient = 0.0_wp
   if (nat < 2 .or. size(gradient) /= 3*nat) return

   xyz = reshape(x, [3, nat])
   pairs = landscape_idpp_pair_indices(nat)
   do p = 1, min(size(target), size(pairs, 2))
      a = pairs(1, p)
      b = pairs(2, p)
      dr = xyz(:, a) - xyz(:, b)
      dist = sqrt(sum(dr**2))
      if (dist <= idpp_min_distance) cycle
      diff = 1.0_wp/dist - target(p)
      value = value + diff**2
      dsd = -2.0_wp*diff/dist**2
      scale = dsd/dist
      gradient(3*(a - 1) + 1:3*a) = gradient(3*(a - 1) + 1:3*a) + scale*dr
      gradient(3*(b - 1) + 1:3*b) = gradient(3*(b - 1) + 1:3*b) - scale*dr
   end do

end subroutine landscape_idpp_objective

!> Replace the interior images of a band by their IDPP initial path.
!>
!> `images(3, nat, n_images)` holds the (already aligned) linearly
!> interpolated path on entry and the IDPP relaxed path on exit; the two
!> endpoints are never modified.  Each internal image is relaxed
!> independently on its own target surface with L-BFGS; the step length
!> below `step_tol` is the convergence criterion, because the objective has
!> no energy scale that could be compared against a threshold.
!>
!> `fail` is set when the settings are unusable (fewer than three images or
!> fewer than two atoms); the relaxation itself has no failure mode.
subroutine landscape_idpp_path(env, images, fail, max_steps, max_displ, step_tol)
   !> Computational environment (unused numerically, kept for the API)
   type(TEnvironment), intent(inout) :: env
   !> Band images `(3, nat, n_images)`, overwritten in place
   real(wp), intent(inout) :: images(:, :, :)
   !> Failure flag
   logical, intent(out) :: fail
   !> Maximum number of L-BFGS iterations per image
   integer, intent(in), optional :: max_steps
   !> Upper bound of one displacement component (bohr)
   real(wp), intent(in), optional :: max_displ
   !> Step length below which an image counts as relaxed (bohr)
   real(wp), intent(in), optional :: step_tol

   type(landscape_lbfgs_type) :: lbfgs
   real(wp), allocatable :: target(:), x(:), g(:), d(:), xnew(:), gnew(:)
   real(wp), allocatable :: reactant(:, :), product(:, :)
   real(wp) :: lam, stepmax, tol, value
   integer :: n_images, nat, ndim, k, it, nstep
   logical :: ok, steepest

   fail = .true.
   if (size(images, 1) /= 3) return
   nat = size(images, 2)
   n_images = size(images, 3)
   if (nat < 2 .or. n_images < 3) return

   nstep = idpp_max_steps
   if (present(max_steps)) nstep = max_steps
   stepmax = idpp_max_displ
   if (present(max_displ)) stepmax = max_displ
   tol = idpp_step_tol
   if (present(step_tol)) tol = step_tol

   reactant = images(:, :, 1)
   product = images(:, :, n_images)
   ndim = 3*nat
   allocate(x(ndim), g(ndim), d(ndim), xnew(ndim), gnew(ndim))

   do k = 2, n_images - 1
      lam = real(k - 1, wp)/real(n_images - 1, wp)
      target = landscape_idpp_targets(reactant, product, lam)
      x = reshape(images(:, :, k), [ndim])
      call new_landscape_lbfgs(lbfgs, ndim, idpp_lbfgs_memory)
      call landscape_idpp_objective(x, target, value, g)
      do it = 1, nstep
         call lbfgs%direction(g, d, ok, steepest)
         if (.not. ok) exit
         call clip_step(d, stepmax)
         xnew = x + d
         call landscape_idpp_objective(xnew, target, value, gnew)
         call lbfgs%push(xnew - x, gnew - g)
         x = xnew
         g = gnew
         if (maxval(abs(d)) < tol) exit
      end do
      images(:, :, k) = reshape(x, [3, nat])
   end do

   fail = .false.

end subroutine landscape_idpp_path

!> Clip a step so that no component exceeds `stepmax` (in place).
pure subroutine clip_step(step, stepmax)
   !> Step (bohr), overwritten in place
   real(wp), intent(inout) :: step(:)
   !> Upper bound of one component (bohr)
   real(wp), intent(in) :: stepmax

   real(wp) :: largest

   largest = maxval(abs(step))
   if (largest > stepmax .and. largest > 0.0_wp) then
      step = step*stepmax/largest
   end if

end subroutine clip_step

end module xtb_landscape_path_idpp
