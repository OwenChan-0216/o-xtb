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

!> Unit tests of the Cartesian/mass-metric utilities of the landscape suite.
module test_landscape_coords
   use testdrive, only : new_unittest, unittest_type, error_type, check
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_convert, only : autoaa, aatoau
   use xtb_type_environment
   use xtb_type_molecule
   use xtb_param_atomicmass, only : getAtomicMass
   use xtb_landscape_coords
   use xtb_landscape_settings, only : landscape_log_failed
   implicit none
   private

   public :: collect_landscape_coords

contains

!> Collect all exported unit tests
subroutine collect_landscape_coords(testsuite)
   !> Collection of tests
   type(unittest_type), allocatable, intent(out) :: testsuite(:)

   testsuite = [ &
      new_unittest("pack-unpack", test_pack_unpack), &
      new_unittest("vector-tools", test_vector_tools), &
      new_unittest("mass-weight", test_mass_weight), &
      new_unittest("mass-weight-invalid", test_mass_weight_invalid), &
      new_unittest("remove-translation", test_remove_translation), &
      new_unittest("remove-rotation", test_remove_rotation), &
      new_unittest("remove-rotation-reference", test_remove_rotation_reference), &
      new_unittest("remove-rotation-degenerate", test_remove_rotation_degenerate), &
      new_unittest("unit-conversion", test_unit_conversion) &
      ]

end subroutine collect_landscape_coords

!> Flattening and unflattening must be exact round trips.
subroutine test_pack_unpack(error)
   type(error_type), allocatable, intent(out) :: error

   real(wp), parameter :: xyz(3, 3) = reshape([ &
      &  0.1_wp,  0.2_wp,  0.3_wp, &
      &  1.1_wp, -1.2_wp,  1.3_wp, &
      & -2.1_wp,  2.2_wp, -2.3_wp], [3, 3])
   real(wp), allocatable :: x(:), buffer(:, :)
   integer :: i

   x = geometry_pack(xyz)
   call check(error, size(x), 9)
   if (allocated(error)) return
   call check(error, x(1), xyz(1, 1))
   if (allocated(error)) return
   call check(error, x(2), xyz(2, 1))
   if (allocated(error)) return
   call check(error, x(3), xyz(3, 1))
   if (allocated(error)) return
   call check(error, x(4), xyz(1, 2))
   if (allocated(error)) return
   call check(error, x(9), xyz(3, 3))
   if (allocated(error)) return

   allocate(buffer(3, 3))
   buffer = 0.0_wp
   call geometry_unpack(x, buffer)
   do i = 1, 3
      call check(error, maxval(abs(buffer(:, i) - xyz(:, i))), 0.0_wp, thr=1.0e-16_wp)
      if (allocated(error)) return
   end do

end subroutine test_pack_unpack

!> Norm, RMS, maximum absolute value, scaling and axpy on known vectors.
subroutine test_vector_tools(error)
   type(error_type), allocatable, intent(out) :: error

   real(wp) :: x(4), y(4)

   x = [3.0_wp, -4.0_wp, 0.0_wp, 0.0_wp]

   call check(error, vec_norm(x), 5.0_wp)
   if (allocated(error)) return
   call check(error, vec_rms(x), 2.5_wp)
   if (allocated(error)) return
   call check(error, vec_maxabs(x), 4.0_wp)
   if (allocated(error)) return

   call vec_scale(x, 2.0_wp)
   call check(error, vec_norm(x), 10.0_wp)
   if (allocated(error)) return
   call vec_scale(x, 0.5_wp)

   y = [1.0_wp, 1.0_wp, 1.0_wp, 1.0_wp]
   call vec_axpy(2.0_wp, x, y)
   call check(error, y(1), 7.0_wp)
   if (allocated(error)) return
   call check(error, y(2), -7.0_wp)
   if (allocated(error)) return
   call check(error, y(3), 1.0_wp)

end subroutine test_vector_tools

!> Mass weighting must be exactly invertible for vectors and Hessians.
subroutine test_mass_weight(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   character(len=*), parameter :: sym(3) = ["O", "H", "H"]
   real(wp), parameter :: xyz(3, 3) = reshape([ &
      & 0.00000000000000_wp, -0.00000000077760_wp, 0.18829790750029_wp, &
      & 0.00000000000000_wp, 1.45987612440076_wp, -0.88615189669760_wp, &
      & 0.00000000000000_wp, -1.45987612362316_wp, -0.88615189608629_wp], [3, 3])
   real(wp), allocatable :: x(:), ref(:), mass(:)
   real(wp), allocatable :: hess(:, :), hess_ref(:, :)
   real(wp) :: dmax
   integer :: i, j

   call init(env)
   call init(mol, sym, xyz)

   mass = atomic_masses(mol)
   call check(error, size(mass), 3)
   if (allocated(error)) return
   do i = 1, 3
      call check(error, mass(i), getAtomicMass(mol%at(i)))
      if (allocated(error)) return
   end do

   x = geometry_pack(xyz)
   ref = x
   call mass_weight_vector(env, mol, x)
   call check(error, maxval(abs(x - ref)) > 0.0_wp)
   if (allocated(error)) return
   call mass_unweight_vector(env, mol, x)
   call check(error, maxval(abs(x - ref)), 0.0_wp, thr=1.0e-14_wp)
   if (allocated(error)) return

   allocate(hess(9, 9), hess_ref(9, 9))
   do j = 1, 9
      do i = 1, 9
         hess(i, j) = real(i, wp) - 0.5_wp*real(j, wp)
      end do
   end do
   hess_ref = hess
   call mass_weight_hessian(env, mol, hess)
   call mass_unweight_hessian(env, mol, hess)
   dmax = maxval(abs(hess - hess_ref))
   call check(error, dmax, 0.0_wp, thr=1.0e-14_wp)
   if (allocated(error)) return

   ! the mass weighted Hessian of a diagonal Hessian follows the metric
   hess = 0.0_wp
   hess(1, 1) = 1.0_wp
   hess(4, 4) = 1.0_wp
   call mass_weight_hessian(env, mol, hess)
   call check(error, hess(1, 1), 1.0_wp/mass(1), thr=1.0e-14_wp)
   if (allocated(error)) return
   call check(error, hess(4, 4), 1.0_wp/mass(2), thr=1.0e-14_wp)

end subroutine test_mass_weight

!> A non-positive atomic mass (invalid atom number) must be rejected by every
!> mass metric instead of producing NaN/Inf.
subroutine test_mass_weight_invalid(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   character(len=*), parameter :: sym(3) = ["O", "H", "H"]
   real(wp), parameter :: xyz(3, 3) = reshape([ &
      &  0.1_wp,  0.2_wp,  0.0_wp, &
      &  1.5_wp, -0.5_wp,  0.9_wp, &
      & -0.7_wp,  1.4_wp, -1.2_wp], [3, 3])
   real(wp), allocatable :: x(:), xref(:), hess(:, :), hess_ref(:, :)
   integer :: nlog

   call init(env)
   call init(mol, sym, xyz)
   ! atomic number 0 has no mass (`getAtomicMass` returns -1)
   mol%at(1) = 0
   call check(error, getAtomicMass(mol%at(1)) <= 0.0_wp)
   if (allocated(error)) return

   x = geometry_pack(xyz)
   xref = x

   nlog = env%nLog
   call mass_weight_vector(env, mol, x)
   call check(error, landscape_log_failed(env, nlog), &
      & "mass_weight_vector accepted mass <= 0")
   if (allocated(error)) return
   call check(error, maxval(abs(x - xref)), 0.0_wp, &
      & "mass_weight_vector modified the vector")
   if (allocated(error)) return

   nlog = env%nLog
   call mass_unweight_vector(env, mol, x)
   call check(error, landscape_log_failed(env, nlog), &
      & "mass_unweight_vector accepted mass <= 0")
   if (allocated(error)) return
   call check(error, maxval(abs(x - xref)), 0.0_wp)
   if (allocated(error)) return

   allocate(hess(9, 9), hess_ref(9, 9), source=0.0_wp)
   hess(1, 1) = 1.0_wp
   hess_ref = hess

   nlog = env%nLog
   call mass_weight_hessian(env, mol, hess)
   call check(error, landscape_log_failed(env, nlog), &
      & "mass_weight_hessian accepted mass <= 0")
   if (allocated(error)) return
   call check(error, maxval(abs(hess - hess_ref)), 0.0_wp)
   if (allocated(error)) return

   nlog = env%nLog
   call mass_unweight_hessian(env, mol, hess)
   call check(error, landscape_log_failed(env, nlog), &
      & "mass_unweight_hessian accepted mass <= 0")
   if (allocated(error)) return
   call check(error, maxval(abs(hess - hess_ref)), 0.0_wp)

end subroutine test_mass_weight_invalid

!> After removing the translation the centre of mass is at the origin.
subroutine test_remove_translation(error)
   type(error_type), allocatable, intent(out) :: error
   type(TMolecule) :: mol
   character(len=*), parameter :: sym(3) = ["O", "H", "H"]
   real(wp), parameter :: xyz(3, 3) = reshape([ &
      &  0.1_wp,  0.2_wp,  0.0_wp, &
      &  1.5_wp, -0.5_wp,  0.9_wp, &
      & -0.7_wp,  1.4_wp, -1.2_wp], [3, 3])
   real(wp) :: work(3, 3), com(3)

   call init(mol, sym, xyz)
   work = xyz
   call remove_translation(mol, work)
   com = center_of_mass(mol, work)
   call check(error, maxval(abs(com)), 0.0_wp, thr=1.0e-14_wp)
   if (allocated(error)) return

   ! the translation must not change internal distances
   call check(error, work(1, 2) - work(1, 1), xyz(1, 2) - xyz(1, 1), thr=1.0e-14_wp)

end subroutine test_remove_translation

!> After aligning the principal axes the products of inertia vanish and the
!> rotation is deterministic.
subroutine test_remove_rotation(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   character(len=*), parameter :: sym(4) = ["C", "H", "O", "H"]
   real(wp), parameter :: xyz(3, 4) = reshape([ &
      &  0.10_wp,  0.20_wp,  0.00_wp, &
      &  1.50_wp, -0.50_wp,  0.90_wp, &
      & -0.70_wp,  1.40_wp, -1.20_wp, &
      &  0.30_wp, -1.10_wp,  1.70_wp], [3, 4])
   real(wp) :: work(3, 4), again(3, 4), inertia(3, 3)

   call init(env)
   call init(mol, sym, xyz)

   work = xyz
   call remove_rotation(env, mol, work)
   inertia = inertia_tensor(mol, work)
   call check(error, abs(inertia(1, 2)), 0.0_wp, thr=1.0e-10_wp)
   if (allocated(error)) return
   call check(error, abs(inertia(1, 3)), 0.0_wp, thr=1.0e-10_wp)
   if (allocated(error)) return
   call check(error, abs(inertia(2, 3)), 0.0_wp, thr=1.0e-10_wp)
   if (allocated(error)) return
   call check(error, maxval(abs(center_of_mass(mol, work))), 0.0_wp, thr=1.0e-14_wp)
   if (allocated(error)) return

   again = xyz
   call remove_rotation(env, mol, again)
   call check(error, maxval(abs(again - work)), 0.0_wp, thr=1.0e-14_wp)

end subroutine test_remove_rotation

!> A rigidly rotated copy of a molecule must land in the same principal axis
!> system as the reference frame when the reference is supplied.
!>
!> This is the falsifiable counterpart of the sign convention: without the
!> reference, the eigenvector basis of a rotated geometry is only determined
!> up to the arbitrary orientation of the original frame, so the two frames
!> would differ by the applied rotation.
subroutine test_remove_rotation_reference(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   character(len=*), parameter :: sym(4) = ["C", "H", "O", "H"]
   real(wp), parameter :: xyz(3, 4) = reshape([ &
      &  0.10_wp,  0.20_wp,  0.00_wp, &
      &  1.50_wp, -0.50_wp,  0.90_wp, &
      & -0.70_wp,  1.40_wp, -1.20_wp, &
      &  0.30_wp, -1.10_wp,  1.70_wp], [3, 4])
   real(wp) :: canon(3, 4), rotated(3, 4), rot(3, 3)

   call init(env)
   call init(mol, sym, xyz)

   canon = xyz
   call remove_rotation(env, mol, canon)

   rot = rotation_matrix(0.5235987755982988_wp, [0.3_wp, 0.7_wp, -0.2_wp])
   rotated = matmul(rot, xyz)
   call remove_rotation(env, mol, rotated, xyz_ref=canon)

   call check(error, maxval(abs(rotated - canon)) < 1.0e-10_wp)
   if (allocated(error)) return

   ! control: the old, reference-free behaviour lands in the rotated principal
   ! frame, so it is not frame-consistent.  This is the assertion that fails
   ! without the reference argument.
   rotated = matmul(rot, xyz)
   call remove_rotation(env, mol, rotated)
   call check(error, maxval(abs(rotated - canon)) > 1.0e-3_wp)

end subroutine test_remove_rotation_reference

!> Degenerate moments of inertia (linear molecule and symmetric top) must also
!> be aligned consistently when a reference frame is given.
subroutine test_remove_rotation_degenerate(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   real(wp) :: canon3(3, 3), rotated3(3, 3), canon4(3, 4), rotated4(3, 4)
   real(wp) :: rot(3, 3)
   character(len=*), parameter :: sym_co2(3) = ["O", "C", "O"]
   character(len=*), parameter :: sym_nh3(4) = ["N", "H", "H", "H"]
   real(wp), parameter :: co2(3, 3) = reshape([ &
      &  0.0_wp,  0.0_wp,  0.0_wp, &
      &  2.2_wp,  0.0_wp,  0.0_wp, &
      & -2.2_wp,  0.0_wp,  0.0_wp], [3, 3])
   real(wp), parameter :: nh3(3, 4) = reshape([ &
      &  0.000_wp,  0.000_wp,  0.000_wp, &
      &  1.000_wp,  1.000_wp,  1.000_wp, &
      & -1.000_wp, -1.000_wp,  1.000_wp, &
      & -1.000_wp,  1.000_wp, -1.000_wp], [3, 4])

   call init(env)
   rot = rotation_matrix(0.7853981633974483_wp, [1.0_wp, -1.0_wp, 0.5_wp])

   ! linear CO2: two equal moments of inertia
   call init(mol, sym_co2, co2)
   canon3 = co2
   call remove_rotation(env, mol, canon3)
   rotated3 = matmul(rot, co2)
   call remove_rotation(env, mol, rotated3, xyz_ref=canon3)
   call check(error, maxval(abs(rotated3 - canon3)) < 1.0e-10_wp)
   if (allocated(error)) return

   ! symmetric top NH3: two equal moments of inertia
   call init(mol, sym_nh3, nh3)
   canon4 = nh3
   call remove_rotation(env, mol, canon4)
   rotated4 = matmul(rot, nh3)
   call remove_rotation(env, mol, rotated4, xyz_ref=canon4)
   call check(error, maxval(abs(rotated4 - canon4)) < 1.0e-10_wp)

end subroutine test_remove_rotation_degenerate

!> Right-handed rotation matrix about a (not necessarily normalised) axis.
pure function rotation_matrix(angle, axis) result(rot)
   real(wp), intent(in) :: angle
   real(wp), intent(in) :: axis(3)
   real(wp) :: rot(3, 3)
   real(wp) :: n(3), c, s, t, x, y, z

   n = axis/sqrt(sum(axis**2))
   x = n(1)
   y = n(2)
   z = n(3)
   c = cos(angle)
   s = sin(angle)
   t = 1.0_wp - c
   rot(1, 1) = t*x*x + c
   rot(1, 2) = t*x*y - s*z
   rot(1, 3) = t*x*z + s*y
   rot(2, 1) = t*x*y + s*z
   rot(2, 2) = t*y*y + c
   rot(2, 3) = t*y*z - s*x
   rot(3, 1) = t*x*z - s*y
   rot(3, 2) = t*y*z + s*x
   rot(3, 3) = t*z*z + c

end function rotation_matrix

!> Polynomial of the moment of inertia about the origin.
function inertia_tensor(mol, xyz) result(inertia)
   type(TMolecule), intent(in) :: mol
   real(wp), intent(in) :: xyz(:, :)
   real(wp) :: inertia(3, 3)
   real(wp) :: x, y, z, m
   integer :: i

   inertia = 0.0_wp
   do i = 1, mol%n
      x = xyz(1, i)
      y = xyz(2, i)
      z = xyz(3, i)
      m = getAtomicMass(mol%at(i))
      inertia(1, 1) = inertia(1, 1) + m*(y*y + z*z)
      inertia(2, 2) = inertia(2, 2) + m*(x*x + z*z)
      inertia(3, 3) = inertia(3, 3) + m*(x*x + y*y)
      inertia(1, 2) = inertia(1, 2) - m*x*y
      inertia(2, 1) = inertia(1, 2)
      inertia(1, 3) = inertia(1, 3) - m*x*z
      inertia(3, 1) = inertia(1, 3)
      inertia(2, 3) = inertia(2, 3) - m*y*z
      inertia(3, 2) = inertia(2, 3)
   end do

end function inertia_tensor

!> The unit conversions must be exact inverses of each other.
subroutine test_unit_conversion(error)
   type(error_type), allocatable, intent(out) :: error

   call check(error, bohr_to_angstrom(1.0_wp), autoaa)
   if (allocated(error)) return
   call check(error, angstrom_to_bohr(bohr_to_angstrom(2.5_wp)), 2.5_wp, &
      & thr=1.0e-14_wp)
   if (allocated(error)) return
   call check(error, angstrom_to_bohr(1.0_wp), aatoau)
   if (allocated(error)) return
   call check(error, kcalmol_to_hartree(hartree_to_kcalmol(0.5_wp)), 0.5_wp, &
      & thr=1.0e-14_wp)

end subroutine test_unit_conversion

end module test_landscape_coords
