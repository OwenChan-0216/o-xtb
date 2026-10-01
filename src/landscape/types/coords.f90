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

!> Cartesian coordinate and mass-metric utilities of the landscape suite.
!>
!> This module is the single place where the landscape suite (i) flattens and
!> unflattens Cartesian geometries, (ii) applies the mass metric and (iii)
!> performs unit conversions at the I/O boundary.  All quantities are in
!> atomic units: lengths in bohr, energies in hartree, masses in atomic units
!> (electron masses).
!>
!> Flattening convention: a geometry `xyz(3, nat)` is stored as the vector
!> `x(3*nat)` with the ordering `x1, y1, z1, x2, y2, z2, ...`.  This is the
!> column-major order of `reshape(xyz, [3*nat])` and matches the `xyz(3, nat)`
!> convention mandated by the landscape plan (no `xyz(nat, 3)` arrays).
!>
!> Mass weighting of a Cartesian vector follows the standard convention
!> `y_i = x_i / sqrt(m_atom(i))`, so that the mass-weighted Hessian
!> `H'_ij = H_ij / sqrt(m_i m_j)` reproduces the vibrational frequencies in
!> atomic units (`sqrt(w)` with `w` in hartree/(bohr^2 m_e)).
!>
!> Rigid body removal (`remove_rotation`) has two modes.  Without a reference
!> geometry it diagonalises the moment of inertia tensor with
!> `xtb_mctc_lapack::mctc_syev` and aligns its principal axes with the
!> Cartesian axes; the eigenvector sign convention is fixed (largest magnitude
!> component positive, right-handed frame), which makes the result reproducible
!> for one and the same input but **not** continuous across frames when the
!> moments of inertia are degenerate (linear molecules, symmetric tops).  With
!> a reference geometry the coordinates are instead rotated by the Kabsch
!> (quaternion) rotation that best reproduces the reference, which removes the
!> eigenvector ambiguity and gives a frame that is continuous along a
!> trajectory.
module xtb_landscape_coords
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_convert, only : autoaa, aatoau, autokcal, kcaltoau
   use xtb_mctc_lapack, only : mctc_syev
   use xtb_type_environment, only : TEnvironment
   use xtb_type_molecule, only : TMolecule
   use xtb_param_atomicmass, only : getAtomicMass
   use xtb_landscape_settings, only : landscape_log_failed
   implicit none(type, external)
   private

   public :: geometry_pack, geometry_unpack
   public :: vec_norm, vec_rms, vec_maxabs, vec_scale, vec_axpy
   public :: atomic_masses, mass_weight_vector, mass_weight_hessian
   public :: mass_unweight_vector, mass_unweight_hessian
   public :: mass_weight, mass_unweight
   public :: center_of_mass, remove_translation, remove_rotation
   public :: bohr_to_angstrom, angstrom_to_bohr, hartree_to_kcalmol, kcalmol_to_hartree

   !> Apply the inverse square root mass metric to a Cartesian vector or matrix
   interface mass_weight
      module procedure :: mass_weight_vector
      module procedure :: mass_weight_hessian
   end interface mass_weight

   !> Remove the inverse square root mass metric from a Cartesian vector or matrix
   interface mass_unweight
      module procedure :: mass_unweight_vector
      module procedure :: mass_unweight_hessian
   end interface mass_unweight

contains

!> Flatten a geometry from `xyz(3, nat)` to a contiguous vector of length 3N.
pure function geometry_pack(xyz) result(x)
   !> Cartesian geometry (bohr)
   real(wp), intent(in) :: xyz(:, :)
   !> Flattened geometry (bohr), ordered `x1, y1, z1, x2, ...`
   real(wp), allocatable :: x(:)

   integer :: i

   allocate(x(3*size(xyz, 2)))
   do i = 1, size(xyz, 2)
      x(3*(i - 1) + 1:3*i) = xyz(:, i)
   end do

end function geometry_pack

!> Unflatten a contiguous vector of length 3N into the geometry `xyz(3, nat)`.
pure subroutine geometry_unpack(x, xyz)
   !> Flattened geometry (bohr)
   real(wp), intent(in) :: x(:)
   !> Cartesian geometry (bohr), must have shape `(3, size(x)/3)`
   real(wp), intent(out) :: xyz(:, :)

   integer :: i

   do i = 1, size(xyz, 2)
      xyz(:, i) = x(3*(i - 1) + 1:3*i)
   end do

end subroutine geometry_unpack

!> Euclidean norm of a vector
pure function vec_norm(x) result(norm)
   real(wp), intent(in) :: x(:)
   real(wp) :: norm

   norm = sqrt(sum(x**2))

end function vec_norm

!> Root mean square of the vector components, normalised by the vector length
pure function vec_rms(x) result(rms)
   real(wp), intent(in) :: x(:)
   real(wp) :: rms

   if (size(x) > 0) then
      rms = sqrt(sum(x**2)/real(size(x), wp))
   else
      rms = 0.0_wp
   end if

end function vec_rms

!> Largest absolute component of a vector
pure function vec_maxabs(x) result(maxabs)
   real(wp), intent(in) :: x(:)
   real(wp) :: maxabs

   if (size(x) > 0) then
      maxabs = maxval(abs(x))
   else
      maxabs = 0.0_wp
   end if

end function vec_maxabs

!> Scale a vector in place
pure subroutine vec_scale(x, scale)
   real(wp), intent(inout) :: x(:)
   real(wp), intent(in) :: scale

   x = x*scale

end subroutine vec_scale

!> In-place axpy: `y = a*x + y`
pure subroutine vec_axpy(a, x, y)
   real(wp), intent(in) :: a
   real(wp), intent(in) :: x(:)
   real(wp), intent(inout) :: y(:)

   y = a*x + y

end subroutine vec_axpy

!> Atomic masses of a molecule in atomic units (electron masses).
!>
!> The masses are taken from `xtb_param_atomicmass`, which is the same source
!> used to initialise `TMolecule%atmass`, so both access paths agree bitwise.
pure function atomic_masses(mol) result(mass)
   !> Molecular structure
   type(TMolecule), intent(in) :: mol
   !> Atomic masses in atomic units (electron masses)
   real(wp), allocatable :: mass(:)

   integer :: i

   allocate(mass(mol%n))
   do i = 1, mol%n
      mass(i) = getAtomicMass(mol%at(i))
   end do

end function atomic_masses

!> Apply the inverse square root mass metric to a flat Cartesian vector
!>
!> A non-positive atomic mass (invalid atom number) would turn the metric into
!> a NaN/Inf; it is reported through `env` and the vector is left untouched,
!> consistent with the Hessian version below.
subroutine mass_weight_vector(env, mol, x)
   !> Computational environment for the mass error report
   type(TEnvironment), intent(inout) :: env
   !> Molecular structure
   type(TMolecule), intent(in) :: mol
   !> Cartesian vector of length 3N (bohr), overwritten in place
   real(wp), intent(inout) :: x(:)

   real(wp), allocatable :: mass(:)
   integer :: i, ic

   mass = atomic_masses(mol)
   if (any(mass <= 0.0_wp)) then
      call env%error("non-positive atomic mass in mass weighting", &
         & "landscape_mass_weight_vector")
      return
   end if
   do i = 1, mol%n
      ic = 3*(i - 1)
      x(ic + 1:ic + 3) = x(ic + 1:ic + 3)/sqrt(mass(i))
   end do

end subroutine mass_weight_vector

!> Remove the inverse square root mass metric from a flat Cartesian vector
!>
!> A non-positive atomic mass (invalid atom number) is reported through `env`
!> and the vector is left untouched, consistent with the Hessian version below.
subroutine mass_unweight_vector(env, mol, x)
   !> Computational environment for the mass error report
   type(TEnvironment), intent(inout) :: env
   !> Molecular structure
   type(TMolecule), intent(in) :: mol
   !> Mass-weighted Cartesian vector of length 3N, overwritten in place
   real(wp), intent(inout) :: x(:)

   real(wp), allocatable :: mass(:)
   integer :: i, ic

   mass = atomic_masses(mol)
   if (any(mass <= 0.0_wp)) then
      call env%error("non-positive atomic mass in mass weighting", &
         & "landscape_mass_unweight_vector")
      return
   end if
   do i = 1, mol%n
      ic = 3*(i - 1)
      x(ic + 1:ic + 3) = x(ic + 1:ic + 3)*sqrt(mass(i))
   end do

end subroutine mass_unweight_vector

!> Apply the inverse square root mass metric to a Cartesian Hessian,
!> `H'_ij = H_ij / sqrt(m_i m_j)`.
!>
!> A non-positive atomic mass (invalid atom number) would turn the metric into
!> a NaN/Inf; it is reported through `env` and the Hessian is left untouched.
subroutine mass_weight_hessian(env, mol, hess)
   !> Computational environment for the mass error report
   type(TEnvironment), intent(inout) :: env
   !> Molecular structure
   type(TMolecule), intent(in) :: mol
   !> Hessian `(3N, 3N)` in hartree/bohr^2, overwritten in place
   real(wp), intent(inout) :: hess(:, :)

   real(wp), allocatable :: mass(:), smass(:)
   integer :: i, j, iat, ic

   mass = atomic_masses(mol)
   if (any(mass <= 0.0_wp)) then
      call env%error("non-positive atomic mass in mass weighting", &
         & "landscape_mass_weight_hessian")
      return
   end if
   allocate(smass(size(hess, 1)), source=0.0_wp)
   do iat = 1, mol%n
      ic = 3*(iat - 1)
      smass(ic + 1:ic + 3) = 1.0_wp/sqrt(mass(iat))
   end do
   do j = 1, size(hess, 2)
      do i = 1, size(hess, 1)
         hess(i, j) = hess(i, j)*smass(i)*smass(j)
      end do
   end do

end subroutine mass_weight_hessian

!> Remove the inverse square root mass metric from a Cartesian Hessian
!>
!> A non-positive atomic mass is reported through `env` and the Hessian is
!> left untouched.
subroutine mass_unweight_hessian(env, mol, hess)
   !> Computational environment for the mass error report
   type(TEnvironment), intent(inout) :: env
   !> Molecular structure
   type(TMolecule), intent(in) :: mol
   !> Mass-weighted Hessian `(3N, 3N)`, overwritten in place
   real(wp), intent(inout) :: hess(:, :)

   real(wp), allocatable :: mass(:), smass(:)
   integer :: i, j, iat, ic

   mass = atomic_masses(mol)
   if (any(mass <= 0.0_wp)) then
      call env%error("non-positive atomic mass in mass weighting", &
         & "landscape_mass_unweight_hessian")
      return
   end if
   allocate(smass(size(hess, 1)), source=0.0_wp)
   do iat = 1, mol%n
      ic = 3*(iat - 1)
      smass(ic + 1:ic + 3) = sqrt(mass(iat))
   end do
   do j = 1, size(hess, 2)
      do i = 1, size(hess, 1)
         hess(i, j) = hess(i, j)*smass(i)*smass(j)
      end do
   end do

end subroutine mass_unweight_hessian

!> Centre of mass of a geometry (bohr)
pure function center_of_mass(mol, xyz) result(com)
   !> Molecular structure
   type(TMolecule), intent(in) :: mol
   !> Cartesian geometry (bohr)
   real(wp), intent(in) :: xyz(:, :)
   !> Centre of mass (bohr)
   real(wp) :: com(3)

   real(wp), allocatable :: mass(:)
   real(wp) :: total
   integer :: i

   mass = atomic_masses(mol)
   total = sum(mass)
   com = 0.0_wp
   if (total > 0.0_wp) then
      do i = 1, mol%n
         com = com + mass(i)*xyz(:, i)
      end do
      com = com/total
   end if

end function center_of_mass

!> Translate a geometry such that the centre of mass is at the origin.
pure subroutine remove_translation(mol, xyz)
   !> Molecular structure
   type(TMolecule), intent(in) :: mol
   !> Cartesian geometry (bohr), overwritten in place
   real(wp), intent(inout) :: xyz(:, :)

   real(wp) :: com(3)
   integer :: i

   com = center_of_mass(mol, xyz)
   do i = 1, mol%n
      xyz(:, i) = xyz(:, i) - com
   end do

end subroutine remove_translation

!> Align a geometry with a reference frame or with its principal axes.
!>
!> Without `xyz_ref` the geometry is translated to its centre of mass, the
!> moment of inertia tensor is diagonalised (eigenvalues ascending, LAPACK
!> convention) and the coordinates are rotated into the eigenvector frame, so
!> that all products of inertia vanish.  The eigenvector signs are fixed
!> deterministically (largest magnitude component positive, right-handed
!> frame).  This is reproducible for one and the same input, but for a
!> degenerate moment of inertia (linear molecules, symmetric tops, clusters)
!> the eigenvector basis of the degenerate subspace is arbitrary, so two
!> slightly different frames can be related by a rotation or axis permutation;
!> this mode must therefore not be used to compare geometries across frames.
!>
!> With `xyz_ref` both geometries are translated to their centre of mass and
!> `xyz` is rotated by the Kabsch (quaternion) rotation that best reproduces
!> `xyz_ref`.  This removes the degeneracy ambiguity and gives a frame that is
!> continuous along a trajectory; the reference must contain the same atoms in
!> the same order.
subroutine remove_rotation(env, mol, xyz, xyz_ref)
   !> Computational environment for the LAPACK error report
   type(TEnvironment), intent(inout) :: env
   !> Molecular structure
   type(TMolecule), intent(in) :: mol
   !> Cartesian geometry (bohr), overwritten in place
   real(wp), intent(inout) :: xyz(:, :)
   !> Reference geometry to align to (bohr), optional
   real(wp), intent(in), optional :: xyz_ref(:, :)

   real(wp), allocatable :: mass(:), refxyz(:, :)
   real(wp) :: inertia(3, 3), eval(3), com(3), axes(3, 3)
   real(wp) :: x, y, z, m, determinante
   integer :: i, k, imax

   if (present(xyz_ref)) then
      allocate(refxyz(3, mol%n), source=xyz_ref(:, 1:mol%n))
      call remove_translation(mol, xyz)
      call remove_translation(mol, refxyz)
      call kabsch_align(env, xyz, refxyz)
      return
   end if

   mass = atomic_masses(mol)
   com = center_of_mass(mol, xyz)

   inertia = 0.0_wp
   do i = 1, mol%n
      x = xyz(1, i) - com(1)
      y = xyz(2, i) - com(2)
      z = xyz(3, i) - com(3)
      m = mass(i)
      inertia(1, 1) = inertia(1, 1) + m*(y*y + z*z)
      inertia(2, 2) = inertia(2, 2) + m*(x*x + z*z)
      inertia(3, 3) = inertia(3, 3) + m*(x*x + y*y)
      inertia(1, 2) = inertia(1, 2) - m*x*y
      inertia(1, 3) = inertia(1, 3) - m*x*z
      inertia(2, 3) = inertia(2, 3) - m*y*z
   end do
   inertia(2, 1) = inertia(1, 2)
   inertia(3, 1) = inertia(1, 3)
   inertia(3, 2) = inertia(2, 3)

   eval = 0.0_wp
   call mctc_syev(env, inertia, eval)

   axes = inertia
   do k = 1, 3
      imax = maxloc(abs(axes(:, k)), dim=1)
      if (axes(imax, k) < 0.0_wp) axes(:, k) = -axes(:, k)
   end do

   determinante = axes(1, 1)*(axes(2, 2)*axes(3, 3) - axes(2, 3)*axes(3, 2)) &
      & - axes(2, 1)*(axes(1, 2)*axes(3, 3) - axes(1, 3)*axes(3, 2)) &
      & + axes(3, 1)*(axes(1, 2)*axes(2, 3) - axes(1, 3)*axes(2, 2))
   if (determinante < 0.0_wp) axes(:, 3) = -axes(:, 3)

   do i = 1, mol%n
      xyz(:, i) = matmul(transpose(axes), xyz(:, i) - com)
   end do

end subroutine remove_rotation

!> Rotate `xyz` by the Kabsch rotation that best reproduces `refxyz`.
!>
!> Both geometries must already be translated to their centre of mass.  The
!> optimal rotation is obtained from the eigenvector of the largest eigenvalue
!> of the symmetric 4x4 quaternion matrix built from the correlation matrix
!> `S = xyz * refxyz^T` (Horn, J. Opt. Soc. Am. A 4, 629 (1987)); the routine
!> always returns a proper rotation (`det = +1`).
subroutine kabsch_align(env, xyz, refxyz)
   !> Computational environment for the LAPACK error report
   type(TEnvironment), intent(inout) :: env
   !> Coordinates to rotate (bohr), overwritten in place
   real(wp), intent(inout) :: xyz(:, :)
   !> Reference coordinates (bohr), centred
   real(wp), intent(in) :: refxyz(:, :)

   real(wp) :: s(3, 3), kmat(4, 4), quat(4), eval(4)
   real(wp) :: q0, qx, qy, qz, rot(3, 3)
   integer :: nlog

   s = matmul(xyz, transpose(refxyz))
   kmat = 0.0_wp
   kmat(1, 1) = s(1, 1) + s(2, 2) + s(3, 3)
   kmat(1, 2) = s(2, 3) - s(3, 2)
   kmat(1, 3) = s(3, 1) - s(1, 3)
   kmat(1, 4) = s(1, 2) - s(2, 1)
   kmat(2, 2) = s(1, 1) - s(2, 2) - s(3, 3)
   kmat(2, 3) = s(1, 2) + s(2, 1)
   kmat(2, 4) = s(3, 1) + s(1, 3)
   kmat(3, 3) = -s(1, 1) + s(2, 2) - s(3, 3)
   kmat(3, 4) = s(2, 3) + s(3, 2)
   kmat(4, 4) = -s(1, 1) - s(2, 2) + s(3, 3)
   kmat(2, 1) = kmat(1, 2)
   kmat(3, 1) = kmat(1, 3)
   kmat(4, 1) = kmat(1, 4)
   kmat(3, 2) = kmat(2, 3)
   kmat(4, 2) = kmat(2, 4)
   kmat(4, 3) = kmat(3, 4)

   nlog = env%nLog
   call mctc_syev(env, kmat, eval)
   if (landscape_log_failed(env, nlog)) return
   quat = kmat(:, 4)
   q0 = quat(1)
   qx = quat(2)
   qy = quat(3)
   qz = quat(4)
   rot = 0.0_wp
   rot(1, 1) = 1.0_wp - 2.0_wp*(qy*qy + qz*qz)
   rot(1, 2) = 2.0_wp*(qx*qy - q0*qz)
   rot(1, 3) = 2.0_wp*(qx*qz + q0*qy)
   rot(2, 1) = 2.0_wp*(qx*qy + q0*qz)
   rot(2, 2) = 1.0_wp - 2.0_wp*(qx*qx + qz*qz)
   rot(2, 3) = 2.0_wp*(qy*qz - q0*qx)
   rot(3, 1) = 2.0_wp*(qx*qz - q0*qy)
   rot(3, 2) = 2.0_wp*(qy*qz + q0*qx)
   rot(3, 3) = 1.0_wp - 2.0_wp*(qx*qx + qy*qy)

   xyz = matmul(rot, xyz)

end subroutine kabsch_align

!> Convert a length from bohr to angstrom
pure function bohr_to_angstrom(x) result(y)
   real(wp), intent(in) :: x
   real(wp) :: y

   y = x*autoaa

end function bohr_to_angstrom

!> Convert a length from angstrom to bohr
pure function angstrom_to_bohr(x) result(y)
   real(wp), intent(in) :: x
   real(wp) :: y

   y = x*aatoau

end function angstrom_to_bohr

!> Convert an energy from hartree to kcal/mol
pure function hartree_to_kcalmol(x) result(y)
   real(wp), intent(in) :: x
   real(wp) :: y

   y = x*autokcal

end function hartree_to_kcalmol

!> Convert an energy from kcal/mol to hartree
pure function kcalmol_to_hartree(x) result(y)
   real(wp), intent(in) :: x
   real(wp) :: y

   y = x*kcaltoau

end function kcalmol_to_hartree

end module xtb_landscape_coords
