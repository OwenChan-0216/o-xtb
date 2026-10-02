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

!> Unit tests of the landscape scan task (M2).
!>
!> The internal coordinate helpers are checked against finite differences of
!> the coordinate value itself; the rigid driver is checked against a hand
!> constructed two/three atom geometry, where the rigid operation is exact;
!> and the relaxed driver is checked against the closed form minimum of an
!> analytic bond potential.  The residual and the hysteresis report are
!> recomputed independently from the stored profile, so a wrong index mapping
!> or a wrong normalisation of the residual fails the test.
!>
!> Units: coordinates in bohr, energies in hartree.
module test_landscape_scan
   use, intrinsic :: ieee_arithmetic, only : ieee_is_nan
   use testdrive, only : new_unittest, unittest_type, error_type, check
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_constants, only : pi
   use xtb_mctc_io, only : stdout
   use xtb_mctc_convert, only : autoaa
   use xtb_type_environment
   use xtb_type_molecule
   use xtb_type_restart, only : TRestart
   use xtb_xtb_calculator, only : TxTBCalculator, newXTBCalculator, &
      & newWavefunction
   use xtb_landscape, only : run_landscape
   use xtb_landscape_settings, only : landscape_scan_settings, &
      & landscape_opt_settings, landscape_scan_coord_settings, &
      & landscape_log_failed, &
      & landscape_scan_coord_name, landscape_scan_coord_from_name, &
      & landscape_scan_coord_natoms, landscape_scan_coord_known, &
      & landscape_scan_mode_known, &
      & p_landscape_scan_coord_distance, p_landscape_scan_coord_angle, &
      & p_landscape_scan_coord_dihedral, landscape_value_present
   use xtb_landscape_results, only : landscape_result
   use xtb_landscape_engine, only : landscape_energy_model
   use xtb_landscape_coords, only : geometry_pack, geometry_unpack
   use xtb_landscape_scan_relax, only : landscape_scan_coord_value, &
      & landscape_scan_coord_gradient, landscape_scan_coord_wrap_delta, &
      & landscape_scan_check, landscape_scan_rigid_geometry, &
      & landscape_scan_rigid_point, landscape_scan_point, &
      & landscape_scan_fragments
   use xtb_landscape_scan1d, only : landscape_scan_profile, landscape_scan1d
   use xtb_landscape_scan2d, only : landscape_scan_grid, landscape_scan2d
   implicit none
   private

   public :: collect_landscape_scan

   !> Number of atoms of the test molecule (water geometry, only used for the
   !> coordinate helpers and the rigid geometry checks)
   integer, parameter :: nat = 3
   character(len=*), parameter :: sym(nat) = ["O", "H", "H"]
   !> Water-like test geometry in bohr
   real(wp), parameter :: xyz(3, nat) = reshape([ &
      &  0.0_wp,  0.0_wp,  0.0_wp, &
      &  0.0_wp,  0.0_wp,  1.8_wp, &
      &  1.7_wp,  0.0_wp, -0.45_wp], [3, nat])

   !> Number of atoms of the 1,2-dichloroethane fixture
   integer, parameter :: dce_nat = 8
   !> Atom numbers (1-based) of the fixture
   integer, parameter :: dce_at(dce_nat) = [6, 6, 17, 17, 1, 1, 1, 1]
   !> `anti` 1,2-dichloroethane (bohr), the GFN2 optimised conformer
   !> (E = -15.416 Eh); the scanned torsion Cl3-C1-C2-Cl4 is -179.99 degrees
   !> and the last atom Cl4 carries a bonded substituent, which is what
   !> distinguishes a rigid torsion scan from the rotation of a single atom.
   real(wp), parameter :: dce_xyz(3, dce_nat) = reshape([ &
      &  0.027541808072_wp, -0.294762391679_wp,  0.000071927701_wp, &
      &  2.863771256589_wp, -0.675903935228_wp,  0.000138264470_wp, &
      & -0.639681166339_wp,  3.008488755979_wp, -0.000272005002_wp, &
      &  3.531502129537_wp, -3.979681821363_wp, -0.000261686403_wp, &
      & -0.838156709684_wp, -1.100110204499_wp, -1.686483860219_wp, &
      & -0.838215490665_wp, -1.099827858607_wp,  1.686771509582_wp, &
      &  3.729087116995_wp,  0.129000059841_wp,  1.686791211876_wp, &
      &  3.729274943297_wp,  0.129488744758_wp, -1.686755362005_wp], &
      & [3, dce_nat])
   !> The scanned torsion of the fixture, Cl3-C1-C2-Cl4
   integer, parameter :: dce_torsion(4) = [3, 1, 2, 4]
   !> Far side of the central bond C1-C2 for the scanned torsion: the fragment
   !> of the third atom (C2), which contains the last atom (Cl4) and both of
   !> its hydrogen substituents; the four atoms a rigid torsion scan has to
   !> move.  The near side is {C1, Cl3, H5, H6}.
   logical, parameter :: dce_far(dce_nat) = [ &
      & .false., .true., .false., .true., .false., .false., .true., .true.]

   !> Maximum number of bonds of `scan_bond_model`
   integer, parameter :: max_bonds = 4

   !> Analytic potential built from pairwise bonds, each a harmonic term plus
   !> an optional quartic double-well term,
   !>
   !>     E = sum_b [ 1/2 k_b (r_b - re_b)^2 + c_b (r_b - a_b)^2 (r_b - b_b)^2 ]
   !>
   !> With `c_b = 0` the bond is harmonic, so the constrained scan minimum
   !> `r* = (k re + 2 fc r0)/(k + 2 fc)` is available in closed form; with
   !> `k_b = 0` and `c_b > 0` it is a double well that can support a
   !> history dependent scan.
   type, extends(landscape_energy_model) :: scan_bond_model
      !> Number of active bonds
      integer :: nbond = 0
      !> Atom pairs of the bonds (1-based)
      integer :: bond_at(2, max_bonds) = 0
      !> Harmonic force constants (hartree/bohr^2)
      real(wp) :: bond_k(max_bonds) = 0.0_wp
      !> Harmonic reference lengths (bohr)
      real(wp) :: bond_re(max_bonds) = 0.0_wp
      !> Quartic coefficients (hartree/bohr^4)
      real(wp) :: bond_c(max_bonds) = 0.0_wp
      !> First minimum of the quartic term (bohr)
      real(wp) :: bond_a(max_bonds) = 0.0_wp
      !> Second minimum of the quartic term (bohr)
      real(wp) :: bond_b(max_bonds) = 0.0_wp
   contains
      !> Energy and gradient
      procedure :: evaluate => bond_model_evaluate
      !> Hessian
      procedure :: hessian => bond_model_hessian
   end type scan_bond_model

   !> Analytic potential whose evaluation stops working after a budget.
   !>
   !> Every call after `budget` evaluations is reported as failed, which
   !> reproduces a scan whose inner SCF breaks down at an extreme geometry
   !> (`docs/_landscape-recon/14-m2-validation-experiments.md` section 5.3):
   !> the first points are evaluated normally and every later point has no
   !> energy.  The failure deliberately leaves `energy = 0.0` behind, exactly
   !> like `xtb_single::singlepoint` does, so a profile that copies the value
   !> of a discarded evaluation is caught.
   !>
   !> The counter lives on the instance, and a scan point minimises a *copy* of
   !> the model (`new_landscape_scan_bias_model`), so the counter of the
   !> instance handed to the driver counts the de-biased evaluations, i.e. one
   !> per scan point.
   type, extends(landscape_energy_model) :: scan_fragile_model
      !> Underlying analytic potential
      type(scan_bond_model) :: bond
      !> Number of evaluations that still succeed
      integer :: budget = 0
      !> Number of evaluations requested so far
      integer :: n_eval = 0
   contains
      !> Energy and gradient
      procedure :: evaluate => fragile_model_evaluate
      !> Hessian
      procedure :: hessian => fragile_model_hessian
   end type scan_fragile_model

contains

!> Collect all exported unit tests
subroutine collect_landscape_scan(testsuite)
   !> Collection of tests
   type(unittest_type), allocatable, intent(out) :: testsuite(:)

   testsuite = [ &
      new_unittest("coord-value", test_coord_value), &
      new_unittest("coord-gradient-finite-difference", test_coord_gradient), &
      new_unittest("coord-name-roundtrip", test_coord_name_roundtrip), &
      new_unittest("coord-wrap-delta", test_wrap_delta), &
      new_unittest("rigid-distance-exact", test_rigid_distance), &
      new_unittest("rigid-angle-exact", test_rigid_angle), &
      new_unittest("rigid-dihedral-fragment", test_rigid_dihedral_fragment), &
      new_unittest("rigid-dihedral-scan", test_rigid_dihedral_scan), &
      new_unittest("rigid-ring-cut-guard", test_rigid_ring_cut_guard), &
      new_unittest("rigid-drift-guard", test_rigid_drift_guard), &
      new_unittest("relaxed-scan-profile", test_relaxed_profile), &
      new_unittest("relaxed-scan-residual", test_relaxed_residual), &
      new_unittest("scan-hysteresis-report", test_hysteresis), &
      new_unittest("rigid-scan-hysteresis-zero", test_rigid_hysteresis), &
      new_unittest("scan-2d-grid", test_grid_2d), &
      new_unittest("scan-invalid-coordinate", test_invalid_coordinate), &
      new_unittest("scan-atom-out-of-range", test_atom_out_of_range), &
      new_unittest("scan-zero-nstep", test_zero_nstep), &
      new_unittest("scan-unknown-mode", test_unknown_mode), &
      new_unittest("scan-unknown-method", test_unknown_method), &
      new_unittest("scan-missing-energy", test_missing_energy), &
      new_unittest("scan-2d-bookkeeping", test_2d_bookkeeping), &
      new_unittest("scan-task-gfn2", test_scan_task), &
      new_unittest("scan-task-unconverged", test_scan_task_unconverged), &
      new_unittest("scan-task-partial-unconverged", &
      & test_scan_task_partial_unconverged), &
      new_unittest("scan-task-no-converged-point", test_scan_task_no_converged_point), &
      new_unittest("scan-task-missing-energy", test_scan_task_missing_energy), &
      new_unittest("scan-task-no-energy", test_scan_task_no_energy), &
      new_unittest("scan-task-invalid", test_scan_task_invalid) &
      ]

end subroutine collect_landscape_scan

!> Internal coordinate values of a hand constructed geometry.
!>
!> `xyz` has an O-H distance of 1.8 bohr, an O-H distance of
!> `sqrt(1.7^2 + 0.45^2)` bohr and an H-O-H angle below 90 degrees.
subroutine test_coord_value(error)
   type(error_type), allocatable, intent(out) :: error
   type(landscape_scan_coord_settings) :: coord
   real(wp) :: value, expected

   coord%ctype = p_landscape_scan_coord_distance
   coord%atoms(1:2) = [1, 2]
   value = landscape_scan_coord_value(coord, xyz)
   call check(error, value, 1.8_wp, thr=1.0e-14_wp)
   if (allocated(error)) return

   coord%atoms(1:2) = [1, 3]
   value = landscape_scan_coord_value(coord, xyz)
   expected = sqrt(1.7_wp**2 + 0.45_wp**2)
   call check(error, value, expected, thr=1.0e-14_wp)
   if (allocated(error)) return

   ! angle between the two O-H bonds
   coord%ctype = p_landscape_scan_coord_angle
   coord%atoms(1:3) = [2, 1, 3]
   value = landscape_scan_coord_value(coord, xyz)
   expected = acos(dot_product(xyz(:, 2) - xyz(:, 1), xyz(:, 3) - xyz(:, 1))/ &
      & (1.8_wp*sqrt(1.7_wp**2 + 0.45_wp**2)))
   call check(error, value, expected, thr=1.0e-12_wp)
   if (allocated(error)) return

   ! dihedral: a 90 degree torsion is reproduced exactly
   block
      real(wp), parameter :: geom(3, 4) = reshape([ &
         &  0.0_wp, 0.0_wp, 0.0_wp, &
         &  0.0_wp, 0.0_wp, 1.45_wp, &
         &  0.95_wp, 0.0_wp, 0.0_wp, &
         &  0.0_wp, 0.95_wp, 1.45_wp], [3, 4])
      coord%ctype = p_landscape_scan_coord_dihedral
      coord%atoms(1:4) = [3, 1, 2, 4]
      value = landscape_scan_coord_value(coord, geom)
      call check(error, value, 0.5_wp*pi, thr=1.0e-12_wp)
   end block

end subroutine test_coord_value

!> Every internal coordinate gradient agrees with central differences of the
!> coordinate value itself.
subroutine test_coord_gradient(error)
   type(error_type), allocatable, intent(out) :: error
   type(landscape_scan_coord_settings) :: coord
   real(wp) :: geom(3, 4), grad(3, 4), plus(3, 4), minus(3, 4)
   real(wp), parameter :: step = 1.0e-5_wp
   real(wp) :: num, worst

   integer :: ctype, ic, iat

   ! H-O-O-H chain with a torsion away from 0 and 180 degrees
   geom(:, 1) = [0.0_wp, 0.0_wp, 0.0_wp]
   geom(:, 2) = [0.0_wp, 0.0_wp, 1.45_wp]
   geom(:, 3) = [0.95_wp, 0.0_wp, 0.0_wp]
   geom(:, 4) = [0.0_wp, 0.95_wp, 1.45_wp]

   do ctype = p_landscape_scan_coord_distance, p_landscape_scan_coord_dihedral
      coord%ctype = ctype
      select case (ctype)
      case (p_landscape_scan_coord_distance)
         coord%atoms(1:2) = [3, 1]
      case (p_landscape_scan_coord_angle)
         coord%atoms(1:3) = [3, 1, 2]
      case (p_landscape_scan_coord_dihedral)
         coord%atoms(1:4) = [3, 1, 2, 4]
      end select
      call landscape_scan_coord_gradient(coord, [1, 1, 1, 1], geom, grad)
      worst = 0.0_wp
      do iat = 1, 4
         do ic = 1, 3
            plus = geom
            plus(ic, iat) = plus(ic, iat) + step
            minus = geom
            minus(ic, iat) = minus(ic, iat) - step
            num = (landscape_scan_coord_value(coord, plus) - &
               & landscape_scan_coord_value(coord, minus))/(2.0_wp*step)
            worst = max(worst, abs(num - grad(ic, iat)))
         end do
      end do
      write(stdout, '(1x,a,a,a,es12.4)') "scan coordinate gradient [", &
         & landscape_scan_coord_name(ctype), "]: max deviation ", worst
      call check(error, worst < 1.0e-6_wp, &
         & "the analytic coordinate gradient disagrees with finite differences")
      if (allocated(error)) return
   end do

end subroutine test_coord_gradient

!> Names and identifiers of the coordinate types round trip.
subroutine test_coord_name_roundtrip(error)
   type(error_type), allocatable, intent(out) :: error
   integer :: ctype

   call check(error, landscape_scan_coord_from_name("distance"), &
      & p_landscape_scan_coord_distance)
   if (allocated(error)) return
   call check(error, landscape_scan_coord_from_name("angle"), &
      & p_landscape_scan_coord_angle)
   if (allocated(error)) return
   call check(error, landscape_scan_coord_from_name("dihedral"), &
      & p_landscape_scan_coord_dihedral)
   if (allocated(error)) return
   call check(error, landscape_scan_coord_from_name("bogus"), 0)
   if (allocated(error)) return
   call check(error, .not. landscape_scan_coord_known(99))
   if (allocated(error)) return
   call check(error, .not. landscape_scan_mode_known("bogus"))
   if (allocated(error)) return
   call check(error, landscape_scan_mode_known("rigid"))
   if (allocated(error)) return
   do ctype = 1, 3
      call check(error, landscape_scan_coord_from_name(&
         & landscape_scan_coord_name(ctype)), ctype)
      if (allocated(error)) return
   end do
   call check(error, landscape_scan_coord_natoms(p_landscape_scan_coord_distance), 2)
   if (allocated(error)) return
   call check(error, landscape_scan_coord_natoms(p_landscape_scan_coord_angle), 3)
   if (allocated(error)) return
   call check(error, landscape_scan_coord_natoms(p_landscape_scan_coord_dihedral), 4)

end subroutine test_coord_name_roundtrip

!> The drift of a periodic coordinate is reduced to one period.
!>
!> A distance is not periodic and keeps its raw difference.  Angles and
!> dihedrals are: a raw difference of `356` degrees is a drift of `-4`
!> degrees, not a full turn, which is what a scan across the `+-180` degree
!> branch cut of `valijkl` produces
!> (`docs/_landscape-recon/17-m2-independent-review.md` section 3.3).
subroutine test_wrap_delta(error)
   type(error_type), allocatable, intent(out) :: error
   real(wp), parameter :: deg = pi/180.0_wp

   ! a distance is not periodic
   call check(error, landscape_scan_coord_wrap_delta(&
      & p_landscape_scan_coord_distance, 2.5_wp), 2.5_wp, thr=0.0_wp)
   if (allocated(error)) return
   call check(error, landscape_scan_coord_wrap_delta(&
      & p_landscape_scan_coord_distance, -2.5_wp), -2.5_wp, thr=0.0_wp)
   if (allocated(error)) return
   ! a dihedral of -356 degrees is 4 degrees away, not 356
   call check(error, landscape_scan_coord_wrap_delta(&
      & p_landscape_scan_coord_dihedral, -356.0_wp*deg), 4.0_wp*deg, &
      & thr=1.0e-12_wp)
   if (allocated(error)) return
   ! ... and the same in the other direction
   call check(error, landscape_scan_coord_wrap_delta(&
      & p_landscape_scan_coord_dihedral, 356.0_wp*deg), -4.0_wp*deg, &
      & thr=1.0e-12_wp)
   if (allocated(error)) return
   ! an angle wraps as well
   call check(error, landscape_scan_coord_wrap_delta(&
      & p_landscape_scan_coord_angle, 350.0_wp*deg), -10.0_wp*deg, &
      & thr=1.0e-12_wp)
   if (allocated(error)) return
   ! a difference inside one period is untouched (up to the round off of the
   ! `modulo`/`pi` round trip)
   call check(error, landscape_scan_coord_wrap_delta(&
      & p_landscape_scan_coord_dihedral, 12.0_wp*deg), 12.0_wp*deg, &
      & thr=1.0e-14_wp)

end subroutine test_wrap_delta

!> Rigid distance construction on a three atom geometry.
!>
!> The scanned O-H distance is set exactly, the second O-H distance (which
!> lives in the fragment translated as a whole) is untouched, and the
!> midpoint of the scanned bond moves by exactly half of the requested
!> change.
subroutine test_rigid_distance(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_scan_coord_settings) :: coord
   real(wp) :: geom(3, nat), midpoint(3), r_oh2
   real(wp), parameter :: target = 2.4_wp
   logical :: fail

   call init(env)
   coord%ctype = p_landscape_scan_coord_distance
   coord%atoms(1:2) = [1, 2]
   geom = xyz
   midpoint = 0.5_wp*(geom(:, 1) + geom(:, 2))
   r_oh2 = norm2(geom(:, 3) - geom(:, 1))

   call landscape_scan_rigid_geometry(env, coord, [8, 1, 1], geom, target, fail)

   call check(error, .not. fail)
   if (allocated(error)) return
   call check(error, norm2(geom(:, 2) - geom(:, 1)), target, thr=1.0e-12_wp)
   if (allocated(error)) return
   call check(error, norm2(geom(:, 3) - geom(:, 1)), r_oh2, thr=1.0e-12_wp)
   if (allocated(error)) return
   ! the midpoint of the scanned bond is preserved, and the O-H2 fragment is
   ! moved rigidly along the bond axis
   call check(error, norm2(0.5_wp*(geom(:, 1) + geom(:, 2)) - midpoint), &
      & 0.0_wp, thr=1.0e-12_wp)

end subroutine test_rigid_distance

!> Rigid angle construction: the angle is set exactly and both bond lengths
!> are preserved (the terminal fragment is rotated about the central atom).
subroutine test_rigid_angle(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_scan_coord_settings) :: coord
   real(wp) :: geom(3, nat), r1, r2
   real(wp), parameter :: target = 2.0_wp
   logical :: fail

   call init(env)
   coord%ctype = p_landscape_scan_coord_angle
   coord%atoms(1:3) = [2, 1, 3]
   geom = xyz
   r1 = norm2(geom(:, 2) - geom(:, 1))
   r2 = norm2(geom(:, 3) - geom(:, 1))

   call landscape_scan_rigid_geometry(env, coord, [8, 1, 1], geom, target, fail)

   call check(error, .not. fail)
   if (allocated(error)) return
   call check(error, landscape_scan_coord_value(coord, geom), target, &
      & thr=1.0e-12_wp)
   if (allocated(error)) return
   call check(error, norm2(geom(:, 2) - geom(:, 1)), r1, thr=1.0e-12_wp)
   if (allocated(error)) return
   call check(error, norm2(geom(:, 3) - geom(:, 1)), r2, thr=1.0e-12_wp)

end subroutine test_rigid_angle

!> Rigid dihedral construction on 1,2-dichloroethane: the torsion is set
!> exactly, the near side of the central bond C1-C2 stays where it is and the
!> whole far side {C2, Cl4, H7, H8} is rotated as one rigid body.
!>
!> The fixture has a bonded substituent on the last atom (Cl4 hangs on the
!> scanned third atom C2, which carries H7 and H8 as well), so the test fails
!> when the rotation is applied to the wrong fragment: cutting the edge `l-k`
!> instead of the central bond `j-k` leaves the fragment `{Cl4}` and lets the
!> substituents of C2 stay behind.  The expected geometry is rebuilt here by an
!> independent Rodrigues rotation (`reference_rotate`) of the independently
!> known far side, no routine of the module under test is used for it.
subroutine test_rigid_dihedral_fragment(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_scan_coord_settings) :: coord
   real(wp) :: geom(3, dce_nat), expected(3, dce_nat)
   real(wp) :: q0, target, worst, worst_distance
   logical, allocatable :: moving(:)
   integer :: iat, j, l
   logical :: fail

   call init(env)
   coord%ctype = p_landscape_scan_coord_dihedral
   coord%atoms(1:4) = dce_torsion
   geom = dce_xyz
   q0 = reference_dihedral(dce_xyz, dce_torsion)

   ! the reference reproduces the torsion convention of the driver
   call check(error, q0, landscape_scan_coord_value(coord, dce_xyz), &
      & thr=1.0e-12_wp, message="the reference torsion is not the scanned one")
   if (allocated(error)) return

   ! cutting the central bond C1-C2 leaves the far side of the third atom
   call landscape_scan_fragments(dce_at, dce_xyz, 2, 1, moving)
   call check(error, count(moving), count(dce_far), &
      & message="the fragment of the central bond has the wrong size")
   if (allocated(error)) return
   do iat = 1, dce_nat
      call check(error, moving(iat), dce_far(iat), &
         & message="the fragment of the central bond contains the wrong atom")
      if (allocated(error)) return
   end do

   target = q0 + 0.4_wp
   call landscape_scan_rigid_geometry(env, coord, dce_at, geom, target, fail)

   call check(error, .not. fail)
   if (allocated(error)) return
   call check(error, landscape_scan_coord_value(coord, geom), target, &
      & thr=1.0e-12_wp, message="the rigid torsion step missed its target")
   if (allocated(error)) return

   ! the near side of the central bond is untouched, exactly
   do iat = 1, dce_nat
      if (dce_far(iat)) cycle
      call check(error, maxval(abs(geom(:, iat) - dce_xyz(:, iat))), 0.0_wp, &
         & thr=0.0_wp, message="an atom of the near side moved")
      if (allocated(error)) return
   end do

   ! ... and the far side is the independent rigid rotation of the whole side
   expected = dce_xyz
   call reference_rotate(expected, dce_far, &
      & dce_xyz(:, dce_torsion(2)), dce_xyz(:, dce_torsion(3)) - &
      & dce_xyz(:, dce_torsion(2)), target - q0)
   worst = 0.0_wp
   do iat = 1, dce_nat
      if (.not. dce_far(iat)) cycle
      worst = max(worst, maxval(abs(geom(:, iat) - expected(:, iat))))
   end do
   write(stdout, '(1x,a,es12.4)') "rigid dihedral: max deviation from the "//&
      & "independent rigid rotation ", worst
   call check(error, worst < 1.0e-12_wp, &
      & message="the far side is not the rigid rotation of the whole side")
   if (allocated(error)) return

   ! a rigid body keeps every distance of the fragment; the substituents of
   ! the third atom are part of it, so C2-H7 and C2-H8 survive as well
   j = 1
   l = 4
   worst_distance = 0.0_wp
   do iat = 1, dce_nat
      if (.not. dce_far(iat)) cycle
      worst_distance = max(worst_distance, abs(norm2(geom(:, iat) - geom(:, 2)) - &
         & norm2(dce_xyz(:, iat) - dce_xyz(:, 2))))
   end do
   call check(error, worst_distance < 1.0e-12_wp, &
      & message="the far side was not moved as a rigid body")
   if (allocated(error)) return
   call check(error, norm2(geom(:, l) - dce_xyz(:, j)) > 0.0_wp)

end subroutine test_rigid_dihedral_fragment

!> A rigid torsion scan of 1,2-dichloroethane stays on its grid.
!>
!> The fixture is the `gauche` conformer, built here by an independent +120
!> degree rotation of the far side of the `anti` geometry, and the scan steps
!> the torsion towards `anti` in 8 degree steps.  Every visited point has to
!> reach its requested value, the near side must never move, the two branches
!> of the bidirectional scan must rebuild the same geometry and the hysteresis
!> must vanish: a rigid scan is a pure geometry construction and therefore
!> history free.
!>
!> This is the regression test of the wrong fragment seeding: with the
!> rotation applied to `{Cl4}` alone the substituents of C2 stay behind, Cl4
!> ends up within the covalent radius of H8, the BFS swallows the whole
!> molecule and the torsion freezes at -115.99 degrees for the last three
!> points of the scan.
subroutine test_rigid_dihedral_scan(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_scan_settings) :: set
   type(scan_bond_model) :: model
   type(landscape_scan_profile) :: profile
   real(wp) :: start(3, dce_nat), x0(3*dce_nat), geom(3, dce_nat)
   real(wp) :: q0, target, step, span, worst, worst_near
   integer :: i, k
   logical :: fail

   call init(env)

   ! fixture: the far side of the `anti` geometry rotated by +120 degrees
   start = dce_xyz
   call reference_rotate(start, dce_far, &
      & dce_xyz(:, dce_torsion(2)), dce_xyz(:, dce_torsion(3)) - &
      & dce_xyz(:, dce_torsion(2)), 120.0_wp*pi/180.0_wp)
   q0 = reference_dihedral(start, dce_torsion)
   x0 = geometry_pack(start)

   set = landscape_scan_settings()
   set%printlevel = 0
   set%write_files = .false.
   set%mode = 'rigid'
   set%bidirectional = .true.
   set%coord(1)%ctype = p_landscape_scan_coord_dihedral
   set%coord(1)%atoms(1:4) = dce_torsion
   step = -8.0_wp*pi/180.0_wp
   set%coord(1)%step = step
   set%coord(1)%nstep = 10

   ! Analyic model whose energy carries the torsion: C1-Cl4 and Cl3-H8 run
   ! across the rotated bond, so the profile is not constant and the
   ! comparison of the two branches is a statement about the scan and not
   ! about a degenerate surface.
   call new_dce_bond_model(model, start)

   call landscape_scan1d(env, model, dce_at, set, x0, profile, fail)
   call check(error, .not. fail, "the rigid scan reported a failure")
   if (allocated(error)) return
   call check(error, profile%n_points, 2*set%coord(1)%nstep + 1)
   if (allocated(error)) return

   ! every point reaches its requested torsion (the broken fragment seeding
   ! moves the near side as well, which cancels the rotation of the scanned
   ! torsion, so the reached value stays at the starting value)
   do i = 1, profile%n_points
      if (i <= profile%n_forward) then
         k = i - 1
      else
         k = profile%n_points - i
      end if
      target = q0 + real(k, wp)*step
      write(stdout, '(1x,a,i3,a,f12.6,a,f12.6)') "rigid torsion point ", i, &
         & " requested ", target*180.0_wp/pi, " reached ", &
         & profile%reached(i)*180.0_wp/pi
      call check(error, profile%reached(i), target, thr=1.0e-12_wp, &
         & message="a rigid torsion point did not reach its target")
      if (allocated(error)) return
      call check(error, profile%converged(i), &
         & message="a rigid scan point is not flagged as converged")
      if (allocated(error)) return
   end do

   ! the near side never moves, at any point of the scan
   worst_near = 0.0_wp
   do i = 1, profile%n_points
      call geometry_unpack(profile%xyz(:, i), geom)
      do k = 1, dce_nat
         if (dce_far(k)) cycle
         worst_near = max(worst_near, maxval(abs(geom(:, k) - dce_xyz(:, k))))
      end do
   end do
   call check(error, worst_near, 0.0_wp, thr=0.0_wp, &
      & message="the rigid scan moved an atom of the near side")
   if (allocated(error)) return

   ! the profile is a real torsion profile (not a constant surface)
   span = maxval(profile%energy(1:profile%n_forward)) - &
      & minval(profile%energy(1:profile%n_forward))
   write(stdout, '(1x,a,es12.4)') "rigid torsion profile span ", span
   call check(error, span > 1.0e-3_wp, &
      & message="the test profile is constant and proves nothing")
   if (allocated(error)) return

   ! history free: both branches rebuild the same geometry and energy
   call check(error, profile%hysteresis%max_delta, 0.0_wp, thr=1.0e-14_wp, &
      & message="a rigid scan must be free of hysteresis")
   if (allocated(error)) return
   worst = 0.0_wp
   do i = 1, set%coord(1)%nstep
      worst = max(worst, maxval(abs(profile%xyz(:, i) - &
         & profile%xyz(:, profile%n_points + 1 - i))))
      call check(error, profile%reached(i), &
         & profile%reached(profile%n_points + 1 - i), thr=1.0e-12_wp)
      if (allocated(error)) return
      call check(error, profile%energy(i), profile%energy(profile%n_points + 1 - i), &
         & thr=1.0e-14_wp, message="rigid forward and reverse branches differ")
      if (allocated(error)) return
   end do
   write(stdout, '(1x,a,es12.4)') "rigid scan: max forward/reverse geometry "//&
      & "difference ", worst
   call check(error, worst < 1.0e-12_wp, &
      & message="the two branches of the rigid scan rebuild different geometries")

end subroutine test_rigid_dihedral_scan

!> A cut that does not separate the molecule is refused by the rigid driver.
!>
!> The three atoms form an equilateral triangle, so cutting one edge leaves
!> the two sides connected: the fragment of atom 1 still reaches atom 2
!> through atom 3.  Both sides would be rotated (or translated), the scanned
!> coordinate would not change and the point would be silently wrong, which is
!> the failure mode of the wrong dihedral seeding
!> (`docs/_landscape-recon/17-m2-independent-review.md` section 3.2).
subroutine test_rigid_ring_cut_guard(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_scan_coord_settings) :: coord
   real(wp) :: geom(3, 3)
   real(wp), parameter :: edge = 2.8345891881866233_wp
   integer :: nlog
   logical :: fail

   call init(env)
   geom(:, 1) = [0.0_wp, 0.0_wp, 0.0_wp]
   geom(:, 2) = [edge, 0.0_wp, 0.0_wp]
   geom(:, 3) = [0.5_wp*edge, 0.8660254037844386_wp*edge, 0.0_wp]

   coord%ctype = p_landscape_scan_coord_angle
   coord%atoms(1:3) = [1, 2, 3]

   nlog = env%nLog
   call landscape_scan_rigid_geometry(env, coord, [6, 6, 6], geom, 1.0_wp, fail)
   call check(error, fail, "a rigid scan of an unseparated cut was accepted")
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog), &
      & "the unseparated cut was not reported as an error")

end subroutine test_rigid_ring_cut_guard

!> A rigid point that cannot reach its target is rejected by the drift check.
!>
!> Atoms 1 and 3 are bonded to each other but neither is bonded to the central
!> atom 2 (the angle `1-2-3` is 30 degrees with 2.0 bohr legs, while the H-H
!> cut off is 1.45 bohr and the `1-3` distance is 1.04 bohr), so the cut
!> `1-2` *does* separate the two sides and passes the cut guard.  The moving
!> fragment is therefore `{1, 3}`, and rotating it about the axis through 2
!> rotates *both* endpoints of the scanned angle, which leaves the angle
!> unchanged: the reached value stays at the starting value however large the
!> requested step is.  The drift criterion of a rigid point has to reject the
!> point instead of reporting a converged one that never moved
!> (`docs/_landscape-recon/17-m2-independent-review.md` section 3.2).
subroutine test_rigid_drift_guard(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_scan_coord_settings) :: coord, coords(1)
   type(landscape_scan_point) :: point
   type(scan_bond_model) :: model
   real(wp) :: geom(3, 3), probe(3, 3), x0(9), value, targets(1)
   real(wp), allocatable :: xout(:)
   integer :: nlog
   logical :: fail

   call init(env)
   geom(:, 1) = [2.0_wp, 0.0_wp, 0.0_wp]
   geom(:, 2) = [0.0_wp, 0.0_wp, 0.0_wp]
   geom(:, 3) = [2.0_wp*cos(pi/6.0_wp), 2.0_wp*sin(pi/6.0_wp), 0.0_wp]

   coord%ctype = p_landscape_scan_coord_angle
   coord%atoms(1:3) = [1, 2, 3]
   coords(1) = coord
   value = landscape_scan_coord_value(coord, geom)
   x0 = geometry_pack(geom)
   targets(1) = value + 0.3_wp
   write(stdout, '(1x,a,f12.6,a)') "rigid drift fixture: angle ", &
      & value*180.0_wp/pi, " deg"

   ! the cut guard passes for this fixture ...
   probe = geom
   nlog = env%nLog
   call landscape_scan_rigid_geometry(env, coord, [1, 1, 1], probe, &
      & targets(1), fail)
   call check(error, .not. fail, &
      & "the cut guard rejected a cut that does separate the molecule")
   if (allocated(error)) return
   ! ... so the rejection below can only come from the drift criterion
   call landscape_scan_rigid_point(env, model, coords, targets, 1, [1, 1, 1], &
      & x0, xout, point, fail)
   call check(error, fail, &
      & "a rigid point that cannot reach its target was accepted")
   if (allocated(error)) return
   call check(error, .not. point%converged, &
      & "the unreachable rigid point is flagged as converged")
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog), &
      & "the unreachable rigid target was not reported as an error")

end subroutine test_rigid_drift_guard

!> Relaxed 1D scan against the closed form constrained minimum.
!>
!> For a harmonic bond `1/2 k (r - re)^2` and the bias `fc (r - r0)^2` the
!> relaxed point is at `r* = (k re + 2 fc r0)/(k + 2 fc)`, its energy is
!> `1/2 k (r* - re)^2` and the residual vanishes.
subroutine test_relaxed_profile(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_scan_settings) :: set
   type(scan_bond_model) :: model
   type(landscape_scan_profile) :: profile
   real(wp), parameter :: k = 0.5_wp
   real(wp), parameter :: re = 2.2_wp
   real(wp), parameter :: fc = 0.5_wp
   real(wp), parameter :: step = 0.1_wp
   integer, parameter :: nstep = 8
   real(wp) :: x0(9), geom(3, 3), rtarget, rstar, estar, q0
   integer :: i, imin
   logical :: fail

   call init(env)
   set = landscape_scan_settings()
   set%printlevel = 0
   set%write_files = .false.
   set%bidirectional = .false.
   set%coord(1)%ctype = p_landscape_scan_coord_distance
   set%coord(1)%atoms(1:2) = [1, 2]
   set%coord(1)%step = step
   set%coord(1)%nstep = nstep

   call new_bond_model(model, k=k, re=re)
   ! atom 2 starts at 2.0 bohr, so the scan range 2.0 .. 2.8 brackets the
   ! force free minimum at 2.2 bohr
   geom(:, 1) = [0.0_wp, 0.0_wp, 0.0_wp]
   geom(:, 2) = [2.0_wp, 0.0_wp, 0.0_wp]
   geom(:, 3) = [0.5_wp, 2.2_wp, 0.0_wp]
   x0 = geometry_pack(geom)
   q0 = norm2(geom(:, 2) - geom(:, 1))

   call landscape_scan1d(env, model, [1, 1, 1], set, x0, profile, fail)

   call check(error, .not. fail, "the relaxed scan reported a failure")
   if (allocated(error)) return
   call check(error, profile%n_points, nstep + 1)
   if (allocated(error)) return
   call check(error, profile%n_forward, nstep + 1)
   if (allocated(error)) return

   do i = 1, profile%n_points
      rtarget = q0 + real(i - 1, wp)*step
      rstar = (k*re + 2.0_wp*fc*rtarget)/(k + 2.0_wp*fc)
      estar = 0.5_wp*k*(rstar - re)**2
      write(stdout, '(1x,a,i3,a,f12.6,a,f18.12,a,es10.3)') "scan point ", i, &
         & " target ", rtarget, " energy ", profile%energy(i), " residual ", &
         & profile%residual(i)
      call check(error, profile%values(i), rtarget, thr=1.0e-14_wp)
      if (allocated(error)) return
      call check(error, profile%energy(i), estar, thr=1.0e-9_wp, &
         & message="the de-biased energy is not the analytic constrained minimum")
      if (allocated(error)) return
      call check(error, profile%residual(i) < 1.0e-4_wp, &
         & "a converged scan point has a large constraint residual")
      if (allocated(error)) return
      call check(error, profile%converged(i))
      if (allocated(error)) return
   end do

   ! the profile is a parabola in the scanned coordinate: the minimum sits
   ! within half a step of the unconstrained minimum `re`
   imin = 1
   do i = 2, profile%n_points
      if (profile%energy(i) < profile%energy(imin)) imin = i
   end do
   call check(error, abs(profile%values(imin) - re) <= 0.5_wp*step + 1.0e-12_wp)
   if (allocated(error)) return
   do i = 2, imin
      call check(error, profile%energy(i) < profile%energy(i - 1))
      if (allocated(error)) return
   end do
   do i = imin + 1, profile%n_points
      call check(error, profile%energy(i) > profile%energy(i - 1))
      if (allocated(error)) return
   end do

end subroutine test_relaxed_profile

!> The constraint residual is `|dE_total/dq|` of the point that was reached.
!>
!> With a step budget of one the inner minimisation cannot converge from a
!> far away start, so the residual must be large and must reproduce the
!> analytic derivative of `E_phys + E_bias` along the scanned coordinate.
subroutine test_relaxed_residual(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_scan_settings) :: set
   type(scan_bond_model) :: model
   type(landscape_scan_profile) :: profile
   real(wp), parameter :: k = 0.5_wp
   real(wp), parameter :: re = 2.2_wp
   real(wp), parameter :: fc = 0.5_wp
   real(wp) :: x0(9), reached(3, 3), r, rtarget, expected
   logical :: fail

   call init(env)
   set = landscape_scan_settings()
   set%printlevel = 0
   set%write_files = .false.
   set%bidirectional = .false.
   set%max_steps = 1
   set%coord(1)%ctype = p_landscape_scan_coord_distance
   set%coord(1)%atoms(1:2) = [1, 2]
   set%coord(1)%step = 0.4_wp
   set%coord(1)%nstep = 1

   call new_bond_model(model, k=k, re=re)
   x0 = geometry_pack(triad())

   call landscape_scan1d(env, model, [1, 1, 1], set, x0, profile, fail)
   call check(error, .not. fail)
   if (allocated(error)) return

   call geometry_unpack(profile%xyz(:, 2), reached)
   r = norm2(reached(:, 2) - reached(:, 1))
   rtarget = profile%values(2)
   expected = abs(k*(r - re) + 2.0_wp*fc*(r - rtarget))
   write(stdout, '(1x,a,f12.6,a,es14.6,a,es14.6)') "scan residual: r ", r, &
      & " reported ", profile%residual(2), " analytic ", expected

   call check(error, profile%residual(2) > 1.0e-4_wp, &
      & "the non-converged point has no residual")
   if (allocated(error)) return
   call check(error, profile%residual(2), expected, thr=1.0e-8_wp, &
      & message="the reported residual is not |dE_total/dq|")

end subroutine test_relaxed_residual

!> A scan point whose evaluation was discarded has *no* energy.
!>
!> The profile must report NaN for such a point - never the `0.0` left behind
!> by the failed evaluation - and must not flag it as converged; the points
!> that were evaluated keep their energies.  The same guard is checked for the
!> 2D grid, whose minimum search has to skip the missing points.
subroutine test_missing_energy(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_scan_settings) :: set
   type(scan_fragile_model) :: model
   type(landscape_scan_profile) :: profile
   type(landscape_scan_grid) :: grid
   real(wp) :: x0(9)
   integer :: i, j, n_missing, n_present
   logical :: fail

   call init(env)
   set = landscape_scan_settings()
   set%printlevel = 0
   set%write_files = .false.
   set%bidirectional = .false.
   set%coord(1)%ctype = p_landscape_scan_coord_distance
   set%coord(1)%atoms(1:2) = [1, 2]
   set%coord(1)%step = 0.2_wp
   set%coord(1)%nstep = 3

   ! the first two de-biased evaluations succeed, every later one is discarded
   call new_bond_model(model%bond, k=0.5_wp, re=2.2_wp)
   model%budget = 2
   x0 = geometry_pack(triad())

   call landscape_scan1d(env, model, [1, 1, 1], set, x0, profile, fail)

   n_missing = count(.not. profile%energy_valid)
   n_present = count(profile%energy_valid)
   write(stdout, '(1x,a,i0,a,i0,a,i0,a)') "scan without energy: ", n_missing, &
      & " of ", profile%n_points, " points missing, ", profile%n_fail, &
      & " counted as failed"

   call check(error, fail, "the scan did not report its failed points")
   if (allocated(error)) return
   call check(error, n_missing > 0, "no scan point lost its energy")
   if (allocated(error)) return
   call check(error, n_present > 0, "every scan point lost its energy")
   if (allocated(error)) return
   call check(error, profile%n_fail, n_missing)
   if (allocated(error)) return
   do i = 1, profile%n_points
      if (profile%energy_valid(i)) then
         call check(error, profile%energy(i) /= 0.0_wp, &
            & message="the 0.0 of a discarded evaluation leaked into a profile energy")
      else
         call check(error, ieee_is_nan(profile%energy(i)), &
            & message="a scan point without an energy is not NaN")
         if (allocated(error)) return
         call check(error, .not. profile%converged(i), &
            & message="a scan point without an energy is flagged as converged")
         if (allocated(error)) return
         ! the biased energy of a point without an energy is missing as well
         call check(error, ieee_is_nan(profile%total(i)), &
            & message="a scan point without an energy kept a 0.0 biased energy")
      end if
      if (allocated(error)) return
   end do

   ! the 2D grid uses the same guard
   set%ndim = 2
   set%coord(1)%nstep = 2
   set%coord(2)%ctype = p_landscape_scan_coord_distance
   set%coord(2)%atoms(1:2) = [1, 3]
   set%coord(2)%step = 0.2_wp
   set%coord(2)%nstep = 2
   model%budget = 2
   model%n_eval = 0
   call new_bond_model(model%bond, k=0.5_wp, re=2.2_wp, k2=0.4_wp, re2=2.4_wp)

   call landscape_scan2d(env, model, [1, 1, 1], set, x0, grid, fail)
   n_missing = count(.not. grid%energy_valid)
   write(stdout, '(1x,a,i0,a,i0,a)') "2D grid without energy: ", n_missing, &
      & " of ", grid%n_points, " points missing"
   call check(error, fail, "the 2D scan did not report its failed points")
   if (allocated(error)) return
   call check(error, n_missing > 0, "no grid point lost its energy")
   if (allocated(error)) return
   call check(error, count(grid%energy_valid), grid%n_points - n_missing)
   if (allocated(error)) return
   call check(error, grid%n_fail, n_missing)
   if (allocated(error)) return
   do j = 1, grid%n2
      do i = 1, grid%n1
         if (grid%energy_valid(i, j)) then
            call check(error, grid%energy(i, j) /= 0.0_wp, &
               & message="the 0.0 of a discarded evaluation leaked into a grid energy")
         else
            call check(error, ieee_is_nan(grid%energy(i, j)), &
               & message="a grid point without an energy is not NaN")
            if (allocated(error)) return
            call check(error, .not. grid%converged(i, j), &
               & message="a grid point without an energy is flagged as converged")
            if (allocated(error)) return
            call check(error, ieee_is_nan(grid%total(i, j)), &
               & message="a grid point without an energy kept a 0.0 biased energy")
         end if
         if (allocated(error)) return
      end do
   end do
   ! the minimum of a partially failed grid comes from an evaluated point
   call check(error, grid%energy_valid(grid%min_i, grid%min_j), &
      & message="the grid minimum is a point without an energy")
   if (allocated(error)) return

   ! A bidirectional scan without a single energy compares nothing.  A `NaN`
   ! compares false against everything, so the maximum difference stays 0.0;
   ! counting the skipped pairs would report "n points compared, max 0.0" for
   ! a scan that was never compared, which reads like a perfectly
   ! reproducible surface.
   set%ndim = 1
   set%bidirectional = .true.
   set%coord(1)%nstep = 2
   model%budget = 0
   model%n_eval = 0
   call new_bond_model(model%bond, k=0.5_wp, re=2.2_wp)
   call landscape_scan1d(env, model, [1, 1, 1], set, x0, profile, fail)
   call check(error, profile%n_fail, profile%n_points, &
      & message="the all-failing bidirectional scan kept a valid point")
   if (allocated(error)) return
   write(stdout, '(1x,a,i0,a,i0,a)') "scan without energy: ", &
      & profile%hysteresis%n_compared, " of ", profile%n_points, &
      & " points compared"
   call check(error, profile%hysteresis%n_compared, 0, &
      & message="a scan without energies reported compared grid points")

end subroutine test_missing_energy

!> The hysteresis report is consistent with the stored profile and detects a
!> history dependent scan.
!>
!> The test scans a double well; the forward and the reverse branch end up in
!> different basins over part of the grid, which produces a non-zero
!> hysteresis.  Every reported quantity is recomputed independently from the
!> profile arrays.
subroutine test_hysteresis(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_scan_settings) :: set
   type(scan_bond_model) :: model
   type(landscape_scan_profile) :: profile
   real(wp) :: x0(9), delta, expected, at_value, jump, jump_from, jump_to
   integer :: i, ifwd, irev, n_fwd, npts, ncmp
   logical :: fail

   call init(env)
   set = landscape_scan_settings()
   set%printlevel = 0
   set%write_files = .false.
   set%bidirectional = .true.
   set%warm_start = .true.
   set%max_steps = 1
   set%coord(1)%ctype = p_landscape_scan_coord_distance
   set%coord(1)%atoms(1:2) = [1, 2]
   set%coord(1)%step = 0.2_wp
   set%coord(1)%nstep = 5

   ! double well with minima at 1.6 and 2.6 bohr (and a barrier in between)
   call new_bond_model(model, k=0.0_wp, re=0.0_wp, c=0.5_wp, a=1.6_wp, b=2.6_wp)
   x0 = geometry_pack(triad())

   call landscape_scan1d(env, model, [1, 1, 1], set, x0, profile, fail)
   call check(error, .not. fail)
   if (allocated(error)) return

   npts = 2*set%coord(1)%nstep + 1
   n_fwd = set%coord(1)%nstep + 1
   call check(error, profile%n_points, npts)
   if (allocated(error)) return
   call check(error, profile%n_forward, n_fwd)
   if (allocated(error)) return

   ! independent recomputation of the hysteresis maximum
   ncmp = 0
   at_value = 0.0_wp
   expected = 0.0_wp
   do i = 0, n_fwd - 2
      ifwd = i + 1
      irev = n_fwd + (n_fwd - 1 - i)
      ncmp = ncmp + 1
      delta = abs(profile%energy(ifwd) - profile%energy(irev))
      if (delta > expected) then
         expected = delta
         at_value = profile%values(ifwd)
      end if
   end do
   jump = 0.0_wp
   jump_from = 0.0_wp
   jump_to = 0.0_wp
   do i = 2, npts
      delta = abs(profile%energy(i) - profile%energy(i - 1))
      if (delta > jump) then
         jump = delta
         jump_from = profile%values(i - 1)
         jump_to = profile%values(i)
      end if
   end do

   write(stdout, '(1x,a,i0,a,es14.6,a,f12.6)') "scan hysteresis: compared ", &
      & profile%hysteresis%n_compared, ", max delta ", &
      & profile%hysteresis%max_delta, " at ", profile%hysteresis%at_value

   call check(error, profile%hysteresis%n_compared, ncmp)
   if (allocated(error)) return
   call check(error, profile%hysteresis%max_delta, expected, thr=1.0e-14_wp)
   if (allocated(error)) return
   call check(error, profile%hysteresis%at_value, at_value, thr=1.0e-14_wp)
   if (allocated(error)) return
   call check(error, profile%hysteresis%max_jump, jump, thr=1.0e-14_wp)
   if (allocated(error)) return
   call check(error, profile%hysteresis%jump_from, jump_from, thr=1.0e-14_wp)
   if (allocated(error)) return
   call check(error, profile%hysteresis%jump_to, jump_to, thr=1.0e-14_wp)
   if (allocated(error)) return
   ! the report must actually contain a hysteresis, otherwise the machinery
   ! could be a no-op that always returns zero
   ! the double well with a one-step relaxation budget is history dependent
   ! by construction, so the report has to see a sizeable hysteresis; an
   ! implementation that always returns zero fails here
   call check(error, profile%hysteresis%max_delta > 1.0e-3_wp, &
      & "the bidirectional scan reported no hysteresis")
   if (allocated(error)) return
   call check(error, profile%hysteresis%max_jump > 0.0_wp)

end subroutine test_hysteresis

!> A rigid scan is history free: the same grid value gives the same geometry
!> on both branches, so the hysteresis must vanish exactly.
subroutine test_rigid_hysteresis(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_scan_settings) :: set
   type(scan_bond_model) :: model
   type(landscape_scan_profile) :: profile
   real(wp) :: x0(9)
   integer :: i
   logical :: fail

   call init(env)
   set = landscape_scan_settings()
   set%printlevel = 0
   set%write_files = .false.
   set%mode = 'rigid'
   set%bidirectional = .true.
   set%coord(1)%ctype = p_landscape_scan_coord_distance
   set%coord(1)%atoms(1:2) = [1, 2]
   set%coord(1)%step = 0.1_wp
   set%coord(1)%nstep = 4

   call new_bond_model(model, k=0.5_wp, re=2.2_wp)
   x0 = geometry_pack(triad())

   call landscape_scan1d(env, model, [1, 1, 1], set, x0, profile, fail)
   call check(error, .not. fail)
   if (allocated(error)) return

   call check(error, profile%n_points, 2*set%coord(1)%nstep + 1)
   if (allocated(error)) return
   call check(error, profile%hysteresis%n_compared, set%coord(1)%nstep)
   if (allocated(error)) return
   call check(error, profile%hysteresis%max_delta, 0.0_wp, thr=1.0e-14_wp, &
      & message="a rigid scan must be free of hysteresis")
   if (allocated(error)) return
   ! the reverse branch reproduces the forward energies point by point: grid
   ! index i of the forward branch (value k = i-1) is stored at
   ! n_points + 1 - i on the reverse branch
   do i = 1, set%coord(1)%nstep
      call check(error, profile%energy(i), profile%energy(profile%n_points + 1 - i), &
         & thr=1.0e-14_wp, message="rigid forward and reverse branches differ")
      if (allocated(error)) return
   end do

end subroutine test_rigid_hysteresis

!> Two-dimensional grid against the closed form solution of two independent
!> harmonic bonds (both are scanned at once, the minimum of each is analytic).
subroutine test_grid_2d(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_scan_settings) :: set
   type(scan_bond_model) :: model
   type(landscape_scan_grid) :: grid
   real(wp), parameter :: k12 = 0.5_wp, re12 = 2.2_wp
   real(wp), parameter :: k13 = 0.4_wp, re13 = 2.4_wp
   real(wp), parameter :: fc = 0.5_wp
   real(wp) :: x0(9), geom(3, 3), target, rstar, expected, worst
   logical :: fail
   integer :: i, j

   call init(env)
   set = landscape_scan_settings()
   set%printlevel = 0
   set%write_files = .false.
   ! the closed form comparison needs a tight inner relaxation: the default
   ! `normal` level leaves a residual of up to 3e-4 Eh/bohr, which shows up as
   ! an energy deviation of about 1e-5 hartree
   call set%set_conv_level('tight')
   set%ndim = 2
   set%coord(1)%ctype = p_landscape_scan_coord_distance
   set%coord(1)%atoms(1:2) = [1, 2]
   set%coord(1)%step = 0.1_wp
   set%coord(1)%nstep = 2
   set%coord(2)%ctype = p_landscape_scan_coord_distance
   set%coord(2)%atoms(1:2) = [1, 3]
   set%coord(2)%step = 0.1_wp
   set%coord(2)%nstep = 3

   call new_bond_model(model, k=k12, re=re12, k2=k13, re2=re13)
   geom = triad()
   x0 = geometry_pack(geom)

   call landscape_scan2d(env, model, [1, 1, 1], set, x0, grid, fail)
   call check(error, .not. fail, "the 2D scan reported a failure")
   if (allocated(error)) return
   call check(error, grid%n1, 3)
   if (allocated(error)) return
   call check(error, grid%n2, 4)
   if (allocated(error)) return
   call check(error, grid%n_points, 12)
   if (allocated(error)) return

   worst = 0.0_wp
   do j = 1, grid%n2
      do i = 1, grid%n1
         target = norm2(geom(:, 2) - geom(:, 1)) + real(i - 1, wp)*0.1_wp
         rstar = (k12*re12 + 2.0_wp*fc*target)/(k12 + 2.0_wp*fc)
         expected = 0.5_wp*k12*(rstar - re12)**2
         target = norm2(geom(:, 3) - geom(:, 1)) + real(j - 1, wp)*0.1_wp
         rstar = (k13*re13 + 2.0_wp*fc*target)/(k13 + 2.0_wp*fc)
         expected = expected + 0.5_wp*k13*(rstar - re13)**2
         worst = max(worst, abs(grid%energy(i, j) - expected))
         call check(error, grid%converged(i, j))
         if (allocated(error)) return
      end do
   end do
   write(stdout, '(1x,a,es12.4)') "2D grid: max energy deviation from the "//&
      & "analytic constrained minimum ", worst
   ! the tolerance is the accuracy reachable with the `tight` inner
   ! relaxation; a wrong constraint or a wrong analytic reference would be
   ! off by orders of magnitude (the profile itself spans 2e-2 hartree)
   call check(error, worst < 1.0e-5_wp, &
      & message="2D grid energy is not the analytic constrained minimum")
   if (allocated(error)) return

   ! lowest energy belongs to the grid point closest to both force free
   ! minima (bond 1-2 is stretched, bond 1-3 is compressed)
   call check(error, grid%min_i, 1)
   if (allocated(error)) return
   call check(error, grid%min_j, 2)

end subroutine test_grid_2d

!> The grid visits every combination exactly once (Cartesian product).
subroutine test_2d_bookkeeping(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_scan_settings) :: set
   type(scan_bond_model) :: model
   type(landscape_scan_grid) :: grid
   integer, allocatable :: seen(:, :)
   real(wp) :: x0(9)
   integer :: i, ok, nlog
   logical :: fail

   call init(env)
   set = landscape_scan_settings()
   set%printlevel = 0
   set%write_files = .false.
   set%mode = 'rigid'
   set%ndim = 2
   set%coord(1)%ctype = p_landscape_scan_coord_distance
   set%coord(1)%atoms(1:2) = [1, 2]
   set%coord(1)%step = 0.1_wp
   set%coord(1)%nstep = 3
   set%coord(2)%ctype = p_landscape_scan_coord_distance
   set%coord(2)%atoms(1:2) = [1, 3]
   set%coord(2)%step = 0.2_wp
   set%coord(2)%nstep = 2

   call new_bond_model(model, k=0.5_wp, re=2.2_wp, k2=0.4_wp, re2=2.4_wp)
   x0 = geometry_pack(triad())

   nlog = env%nLog
   call landscape_scan2d(env, model, [1, 1, 1], set, x0, grid, fail)
   call check(error, .not. fail)
   if (allocated(error)) return
   ! The second rigid operation moves an atom of the first coordinate, so the
   ! first coordinate no longer sits exactly on its target.  That coupling is
   ! inherent to a rigid scan of two coordinates, so it must be a warning and
   ! never a failure ...
   call check(error, .not. landscape_log_failed(env, nlog), &
      & "a coupled rigid scan was reported as a failure")
   if (allocated(error)) return
   ! ... but it has to be visible
   call check(error, env%nLog > nlog, &
      & "the drift of the disturbed coordinate was not reported")
   if (allocated(error)) return
   call check(error, grid%n_points, 4*3)
   if (allocated(error)) return

   allocate(seen(grid%n1, grid%n2), source=0)
   do i = 1, grid%n_points
      seen(grid%visit_i(i), grid%visit_j(i)) = &
         & seen(grid%visit_i(i), grid%visit_j(i)) + 1
   end do
   ok = sum(seen)
   call check(error, ok, grid%n_points)
   if (allocated(error)) return
   call check(error, minval(seen), 1, "a grid combination was not visited")
   if (allocated(error)) return
   call check(error, maxval(seen), 1, "a grid combination was visited twice")

end subroutine test_2d_bookkeeping

!> An unknown coordinate type is rejected before any evaluation.
subroutine test_invalid_coordinate(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_scan_settings) :: set
   integer :: nlog

   call init(env)
   set = landscape_scan_settings()
   set%coord(1)%ctype = 99
   set%coord(1)%atoms(1:2) = [1, 2]
   set%coord(1)%step = 0.1_wp
   set%coord(1)%nstep = 3

   nlog = env%nLog
   call check(error, .not. landscape_scan_check(env, set, nat))
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog), &
      & "an unknown coordinate type was not reported")

end subroutine test_invalid_coordinate

!> An atom index outside the molecule is rejected.
subroutine test_atom_out_of_range(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_scan_settings) :: set
   integer :: nlog

   call init(env)
   set = landscape_scan_settings()
   set%coord(1)%ctype = p_landscape_scan_coord_distance
   set%coord(1)%atoms(1:2) = [1, 5]
   set%coord(1)%step = 0.1_wp
   set%coord(1)%nstep = 3

   nlog = env%nLog
   call check(error, .not. landscape_scan_check(env, set, nat))
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog))
   if (allocated(error)) return

   ! a repeated atom inside one coordinate is rejected as well
   set%coord(1)%atoms(1:2) = [2, 2]
   nlog = env%nLog
   call check(error, .not. landscape_scan_check(env, set, nat))
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog))

end subroutine test_atom_out_of_range

!> `nstep = 0` and a zero step size are rejected.
subroutine test_zero_nstep(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_scan_settings) :: set
   integer :: nlog

   call init(env)
   set = landscape_scan_settings()
   set%coord(1)%ctype = p_landscape_scan_coord_distance
   set%coord(1)%atoms(1:2) = [1, 2]
   set%coord(1)%step = 0.1_wp
   set%coord(1)%nstep = 0

   nlog = env%nLog
   call check(error, .not. landscape_scan_check(env, set, nat))
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog))
   if (allocated(error)) return

   set%coord(1)%nstep = 3
   set%coord(1)%step = 0.0_wp
   nlog = env%nLog
   call check(error, .not. landscape_scan_check(env, set, nat))
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog))

end subroutine test_zero_nstep

!> An unknown scan mode is rejected.
subroutine test_unknown_mode(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_scan_settings) :: set
   integer :: nlog

   call init(env)
   set = landscape_scan_settings()
   set%mode = 'bogus'
   set%coord(1)%ctype = p_landscape_scan_coord_distance
   set%coord(1)%atoms(1:2) = [1, 2]
   set%coord(1)%step = 0.1_wp
   set%coord(1)%nstep = 3

   nlog = env%nLog
   call check(error, .not. landscape_scan_check(env, set, nat))
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog))

end subroutine test_unknown_mode

!> An unknown inner minimiser, a vanishing force constant and an
!> out-of-range `ndim` are rejected.
subroutine test_unknown_method(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_scan_settings) :: set
   integer :: nlog

   call init(env)
   set = landscape_scan_settings()
   set%method = 'bogus'
   set%coord(1)%ctype = p_landscape_scan_coord_distance
   set%coord(1)%atoms(1:2) = [1, 2]
   set%coord(1)%step = 0.1_wp
   set%coord(1)%nstep = 3

   nlog = env%nLog
   call check(error, .not. landscape_scan_check(env, set, nat))
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog))
   if (allocated(error)) return

   set%method = 'lbfgs'
   set%constraint_fc = 0.0_wp
   nlog = env%nLog
   call check(error, .not. landscape_scan_check(env, set, nat))
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog))
   if (allocated(error)) return

   set%constraint_fc = 0.5_wp
   set%ndim = 3
   nlog = env%nLog
   call check(error, .not. landscape_scan_check(env, set, nat))
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog))

end subroutine test_unknown_method

!> End-to-end scan with the real GFN2 calculator through `run_landscape`.
!>
!> Checks the task dispatch, the scan log (`xtbscan.log`, one frame per point
!> with the de-biased energy) and the returned result.  A small H-O-H angle
!> grid on a distorted water molecule keeps the cost at a handful of SCFs.
subroutine test_scan_task(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_scan_settings) :: set
   type(landscape_result) :: result
   real(wp), parameter :: distorted(3, nat) = reshape([ &
      &  0.0_wp,  0.0_wp,  0.0_wp, &
      &  0.0_wp,  1.8_wp,  0.0_wp, &
      &  0.0_wp, -0.9_wp,  1.5_wp], [3, nat])
   integer :: frames, nlog

   call init(env)
   call init(mol, sym, distorted)
   call newXTBCalculator(env, mol, calc, method=2)
   call newWavefunction(env, mol, calc, chk)

   set = landscape_scan_settings()
   set%printlevel = 0
   set%write_files = .true.
   set%bidirectional = .true.
   set%warm_start = .true.
   call set%set_conv_level('loose')
   set%coord(1)%ctype = p_landscape_scan_coord_angle
   set%coord(1)%atoms(1:3) = [2, 1, 3]
   set%coord(1)%step = 3.0_wp*pi/180.0_wp
   set%coord(1)%nstep = 3

   nlog = env%nLog
   call run_landscape(env, mol, chk, calc, set, result)
   call check(error, .not. landscape_log_failed(env, nlog), &
      & "the scan task reported an error")
   if (allocated(error)) return
   call check(error, result%converged)
   if (allocated(error)) return
   call check(error, result%n_steps, 2*3 + 1)
   if (allocated(error)) return
   call check(error, result%n_eval > 0)
   if (allocated(error)) return
   ! the lowest point of the grid must satisfy the constraint
   call check(error, result%gnorm < 1.0e-3_wp, &
      & "the lowest scan point has a large constraint residual")
   if (allocated(error)) return

   frames = count_frames('xtbscan.log')
   write(stdout, '(1x,a,i0,a,es15.6,a)') "scan task: ", frames, &
      & " frames, lowest energy ", result%energy, " Eh"
   call check(error, frames, 2*3 + 1, "xtbscan.log does not hold one frame per point")

end subroutine test_scan_task

!> A scan whose inner relaxations all fail to converge reports an error.
!>
!> The step budget is one and the thresholds are `vtight`, so no inner
!> relaxation can meet its criteria; each one still returns a geometry and an
!> energy, so no scan point *failed* and every frame reaches `xtbscan.log`.
!> `result%converged` is false and - since M7 - the task also reports through
!> `env`, because without a single converged point there is no minimum and the
!> result is not usable (PLAN §12.11 INFO-3, the semantics recorded as INFO-3 in
!> PLAN section 12.11).  A scan with **some** unconverged points still only
!> warns, see `test_scan_task_partial_unconverged`.
subroutine test_scan_task_unconverged(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_scan_settings) :: set
   type(landscape_result) :: result
   integer :: frames, nlog

   call init(env)
   call init(mol, sym, xyz)
   call newXTBCalculator(env, mol, calc, method=2)
   call newWavefunction(env, mol, calc, chk)

   set = landscape_scan_settings()
   set%printlevel = 0
   set%write_files = .true.
   set%bidirectional = .false.
   call set%set_conv_level('vtight')
   set%max_steps = 1
   set%coord(1)%ctype = p_landscape_scan_coord_distance
   set%coord(1)%atoms(1:2) = [1, 2]
   set%coord(1)%step = 0.05_wp
   set%coord(1)%nstep = 2

   nlog = env%nLog
   call run_landscape(env, mol, chk, calc, set, result)
   if (allocated(error)) return
   ! No point lost its energy, but **no** point met its criteria either, so
   ! there is no minimum to report.  M7 (PLAN §12.11 INFO-3) turned that branch
   ! from a warning into an error: a caller of a scan chain must not see exit
   ! 0 next to a NaN total energy.
   call check(error, landscape_log_failed(env, nlog), &
      & "the all-unconverged scan was not reported as an error")
   if (allocated(error)) return
   frames = count_frames('xtbscan.log')
   write(stdout, '(1x,a,i0,a,i0)') "unconverged scan: ", frames, &
      & " frames for ", result%n_steps, " points"
   call check(error, frames, result%n_steps, &
      & "a point of the unconverged scan has no energy")
   if (allocated(error)) return
   ! ... but the task as a whole did not converge
   call check(error, .not. result%converged, &
      & "a scan with unconverged points claimed to be converged")

end subroutine test_scan_task_unconverged

!> A scan with **some** unconverged points still has a usable minimum and
!> keeps exit 0.
!>
!> This is the other half of the M7 rule: only a scan without a single
!> converged point is an error (`test_scan_task_unconverged`).  The geometry is
!> brought to a minimum first, so the unbiased first scan point (which carries
!> no constraint bias) converges even with a one step budget while the
!> displaced points do not - a deterministic partial case without a random
!> ingredient.
subroutine test_scan_task_partial_unconverged(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_opt_settings) :: optset
   type(landscape_scan_settings) :: set
   type(landscape_result) :: result
   integer :: nlog

   call init(env)
   call init(mol, sym, xyz)
   call newXTBCalculator(env, mol, calc, method=2)
   call newWavefunction(env, mol, calc, chk)

   optset = landscape_opt_settings()
   optset%printlevel = 0
   optset%write_files = .false.
   call run_landscape(env, mol, chk, calc, optset, result)

   set = landscape_scan_settings()
   set%printlevel = 0
   set%write_files = .false.
   set%bidirectional = .false.
   set%max_steps = 1
   call set%set_conv_level('loose')
   set%coord(1)%ctype = p_landscape_scan_coord_distance
   set%coord(1)%atoms(1:2) = [1, 2]
   set%coord(1)%step = 0.05_wp
   set%coord(1)%nstep = 2

   nlog = env%nLog
   call run_landscape(env, mol, chk, calc, set, result)
   call check(error, .not. landscape_log_failed(env, nlog), &
      & "a scan with a converged point reported an error")
   if (allocated(error)) return
   call check(error, .not. result%converged, &
      & "a scan with unconverged points claimed convergence")
   if (allocated(error)) return
   call check(error, landscape_value_present(result%energy), &
      & "the partially unconverged scan reported no minimum")
   if (allocated(error)) return
   call check(error, result%message, "scan completed with unconverged points", &
      & "the scan did not report the unconverged points")

end subroutine test_scan_task_partial_unconverged

!> A scan in which **no** point converges must not report a minimum.
!>
!> The step budget of the inner relaxation is zero, so every point keeps its
!> starting geometry: each point has an energy (the frames reach
!> `xtbscan.log`) but none of them satisfied its convergence criteria.  The
!> one-dimensional minimum search counts only converged points, so the result
!> has to report the missing value (NaN) instead of the best unconverged
!> energy, the run must say so in a diagnostic, and the reference geometry
!> must stay the input geometry - the `0.0` frame of an unevaluated point may
!> never be reported as a result
!> (`docs/_landscape-recon/20-m3-vib-implementation-report.md`, M2 leftover
!> M-2).
!>
!> `--lscan-max-steps` (M2 leftover M-1) is the flag that makes this branch
!> reachable from the command line; the second half of the test repeats the
!> scan with a real step budget and checks that the same settings then produce
!> a converged minimum, so the NaN is not an artefact of an invalid request.
subroutine test_scan_task_no_converged_point(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   ! A second and third environment: `env%check` (and every core routine that
   ! uses it, e.g. `xtb_calculator`) tests the **whole** log for errors, so an
   ! error of the first scan would abort the following ones for the wrong
   ! reason.  In production an error ends the run, so this is a test level
   ! concern only.
   type(TEnvironment) :: env_reference, env_grid
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_scan_settings) :: set
   type(landscape_result) :: result
   real(wp), allocatable :: xyz_saved(:, :)
   integer :: frames, nlog

   call init(env)
   call init(mol, sym, xyz)
   call newXTBCalculator(env, mol, calc, method=2)
   call newWavefunction(env, mol, calc, chk)
   allocate(xyz_saved(3, nat), source=mol%xyz)

   set = landscape_scan_settings()
   set%printlevel = 0
   set%write_files = .true.
   set%bidirectional = .false.
   set%max_steps = 0
   set%coord(1)%ctype = p_landscape_scan_coord_angle
   set%coord(1)%atoms(1:3) = [2, 1, 3]
   set%coord(1)%step = 3.0_wp*pi/180.0_wp
   set%coord(1)%nstep = 2

   nlog = env%nLog
   call run_landscape(env, mol, chk, calc, set, result)

   ! M7: no converged point means no usable result, so the task reports it
   ! through `env` (non-zero exit) instead of only warning.
   call check(error, landscape_log_failed(env, nlog), &
      & "the all-unconverged scan was not reported as an error")
   if (allocated(error)) return
   call check(error, result%n_steps, 3)
   if (allocated(error)) return
   call check(error, .not. result%converged, &
      & "a scan without a converged point claimed to be converged")
   if (allocated(error)) return
   call check(error, .not. landscape_value_present(result%energy), &
      & "an unconverged scan reported a minimum")
   if (allocated(error)) return
   call check(error, result%message, "scan completed without a converged point", &
      & "the scan did not report the missing convergence")
   if (allocated(error)) return
   ! the geometry of an unevaluated point must not become the reference
   call check(error, maxval(abs(mol%xyz - xyz_saved)), 0.0_wp, &
      & "the scan moved the geometry although no point converged")
   if (allocated(error)) return
   ! the points themselves were evaluated, so their frames carry energies
   frames = count_frames('xtbscan.log')
   call check(error, frames, result%n_steps, &
      & "a point of the unconverged scan has no energy")
   if (allocated(error)) return

   ! the same scan with a real step budget converges and reports a number
   set%max_steps = 256
   call set%set_conv_level('loose')
   call init(env_reference)
   nlog = env_reference%nLog
   call run_landscape(env_reference, mol, chk, calc, set, result)
   call check(error, .not. landscape_log_failed(env_reference, nlog), &
      & "the reference scan reported an error")
   if (allocated(error)) return
   call check(error, result%converged, &
      & "the scan with a step budget did not converge")
   if (allocated(error)) return
   call check(error, landscape_value_present(result%energy), &
      & "the converged scan reported no minimum")
   if (allocated(error)) return

   ! The two-dimensional minimum search has the same rule (only converged
   ! points qualify), so the same settings on a grid must report the missing
   ! value as well instead of the best evaluated point.
   set = landscape_scan_settings()
   set%printlevel = 0
   set%write_files = .false.
   set%max_steps = 0
   set%ndim = 2
   set%coord(1)%ctype = p_landscape_scan_coord_angle
   set%coord(1)%atoms(1:3) = [2, 1, 3]
   set%coord(1)%step = 3.0_wp*pi/180.0_wp
   set%coord(1)%nstep = 2
   set%coord(2)%ctype = p_landscape_scan_coord_distance
   set%coord(2)%atoms(1:2) = [1, 2]
   set%coord(2)%step = 0.05_wp
   set%coord(2)%nstep = 1

   call init(env_grid)
   nlog = env_grid%nLog
   call run_landscape(env_grid, mol, chk, calc, set, result)
   call check(error, landscape_log_failed(env_grid, nlog), &
      & "the two-dimensional all-unconverged scan was not reported as an error")
   if (allocated(error)) return
   call check(error, .not. result%converged, &
      & "the two-dimensional scan claimed to be converged")
   if (allocated(error)) return
   call check(error, result%message, "scan completed without a converged point", &
      & "the two-dimensional scan reported an unexpected message")
   if (allocated(error)) return
   call check(error, .not. landscape_value_present(result%energy), &
      & "the two-dimensional scan reported the best evaluated grid point as "//&
      & "its minimum although no point converged")

end subroutine test_scan_task_no_converged_point

!> A GFN2 scan whose points fail must not write a fabricated energy.
!>
!> The rigid geometry of the second point pulls the two atoms of the scanned
!> bond so far apart that the SCC of its single point fails; the run then has
!> to report an error, and the scan log may neither contain a frame with
!> `energy = 0.0` nor as many frames as requested points.
subroutine test_scan_task_missing_energy(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_scan_settings) :: set
   type(landscape_result) :: result
   integer :: frames, nlog

   call init(env)
   call init(mol, sym, xyz)
   call newXTBCalculator(env, mol, calc, method=2)
   call newWavefunction(env, mol, calc, chk)

   set = landscape_scan_settings()
   set%printlevel = 0
   set%write_files = .true.
   set%bidirectional = .true.
   set%mode = 'rigid'
   set%coord(1)%ctype = p_landscape_scan_coord_distance
   set%coord(1)%atoms(1:2) = [1, 2]
   ! 5 angstrom steps: the second point is at 5.96, the third at 10.96 angstrom
   set%coord(1)%step = 5.0_wp*1.8897261254578281_wp
   set%coord(1)%nstep = 2

   nlog = env%nLog
   call run_landscape(env, mol, chk, calc, set, result)
   call check(error, landscape_log_failed(env, nlog), &
      & "the failed scan points were not reported")
   if (allocated(error)) return
   call check(error, result%n_steps, 5)
   if (allocated(error)) return
   call check(error, count_frames('xtbscan.log') < result%n_steps, &
      & "the scan log holds a frame for a point without an energy")
   if (allocated(error)) return
   frames = zero_energy_frames('xtbscan.log')
   call check(error, frames, 0, &
      & "the scan log contains a fabricated zero energy")
   if (allocated(error)) return
   ! at least the first point is a real energy, not the 0.0 of a failure
   write(stdout, '(1x,a,es15.6,a)') "scan with failed points: lowest energy ", &
      & result%energy, " Eh"
   call check(error, result%energy < 0.0_wp)

end subroutine test_scan_task_missing_energy

!> A GFN2 scan in which no point can be evaluated reports no number at all.
!>
!> With a single allowed SCC iteration every single point fails: the scan log
!> stays empty, the result energy is NaN (not `0.0`) and the input geometry is
!> left in place instead of being overwritten by the zero frame of a point
!> that was never evaluated.
subroutine test_scan_task_no_energy(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_scan_settings) :: set
   type(landscape_result) :: result
   integer :: nlog

   call init(env)
   call init(mol, sym, xyz)
   call newXTBCalculator(env, mol, calc, method=2)
   call newWavefunction(env, mol, calc, chk)

   ! `engine%maxiter` is not forwarded to the SCC by `xtb_single::singlepoint`
   ! (only `printlevel` and `restart` are); the iteration limit of the SCF is a
   ! property of the calculator.
   calc%maxiter = 1

   set = landscape_scan_settings()
   set%printlevel = 0
   set%write_files = .true.
   set%bidirectional = .false.
   set%coord(1)%ctype = p_landscape_scan_coord_distance
   set%coord(1)%atoms(1:2) = [1, 2]
   set%coord(1)%step = 0.1_wp
   set%coord(1)%nstep = 2

   nlog = env%nLog
   call run_landscape(env, mol, chk, calc, set, result)
   call check(error, landscape_log_failed(env, nlog), &
      & "the failed scan points were not reported")
   if (allocated(error)) return
   call check(error, result%n_steps, 3)
   if (allocated(error)) return
   call check(error, .not. result%converged)
   if (allocated(error)) return
   ! not a single frame: a point without an energy must not be written, and a
   ! stale log of an earlier run must not survive an empty scan either
   write(stdout, '(1x,a,i0)') "scan log frames: ", count_frames('xtbscan.log')
   call check(error, count_frames('xtbscan.log'), 0, &
      & "a point without an energy was written to the scan log")
   if (allocated(error)) return
   call check(error, ieee_is_nan(result%energy), &
      & "the energy of a scan without results is not missing")
   if (allocated(error)) return
   ! the geometry of the input is preserved, not replaced by a zero frame
   call check(error, maxval(abs(mol%xyz - xyz)), 0.0_wp, thr=0.0_wp, &
      & message="a scan without results overwrote the input geometry")

end subroutine test_scan_task_no_energy

!> Invalid scan settings reach the task layer as an error and run no SCF.
subroutine test_scan_task_invalid(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_scan_settings) :: set
   type(landscape_result) :: result
   integer :: nlog

   call init(env)
   call init(mol, sym, xyz)
   call newXTBCalculator(env, mol, calc, method=2)
   call newWavefunction(env, mol, calc, chk)

   set = landscape_scan_settings()
   set%printlevel = 0
   set%write_files = .false.
   set%coord(1)%ctype = p_landscape_scan_coord_distance
   set%coord(1)%atoms(1:2) = [1, 7]
   set%coord(1)%step = 0.1_wp
   set%coord(1)%nstep = 2

   nlog = env%nLog
   call run_landscape(env, mol, chk, calc, set, result)
   call check(error, landscape_log_failed(env, nlog), &
      & "an out of range atom index was not reported")
   if (allocated(error)) return
   call check(error, result%n_eval, 0, "a single point was run for invalid settings")

end subroutine test_scan_task_invalid

!> Torsion `i-j-k-l` in the convention of the scanned coordinate.
!>
!> Independent reimplementation of the torsion convention of
!> `xtb_basic_geo::valijkl` (the routine behind `landscape_scan_coord_value`):
!> the angle between the normals of the `i-j-k` and the `j-k-l` plane, signed
!> by the orientation of the central bond.  The reference of a rigid scan must
!> not call the module under test, otherwise a wrong convention could not be
!> detected; `test_rigid_dihedral_fragment` asserts that the two agree.
pure function reference_dihedral(xyz, atoms) result(phi)
   !> Cartesian geometry (bohr)
   real(wp), intent(in) :: xyz(:, :)
   !> Atoms `i, j, k, l` of the torsion (1-based)
   integer, intent(in) :: atoms(4)
   !> Torsion (radian)
   real(wp) :: phi

   real(wp) :: ra(3), rb(3), rc(3), na(3), nb(3)
   real(wp) :: test, cosine

   ra = xyz(:, atoms(2)) - xyz(:, atoms(1))
   rb = xyz(:, atoms(3)) - xyz(:, atoms(2))
   rc = xyz(:, atoms(4)) - xyz(:, atoms(3))
   ra = ra/norm2(ra)
   rb = rb/norm2(rb)
   rc = rc/norm2(rc)
   na = cross_product(-ra, rc)
   test = sum(na*rb)
   na = cross_product(ra, rb)
   nb = cross_product(rb, rc)
   cosine = sum(na*nb)/sqrt(sum(na*na)*sum(nb*nb))
   phi = acos(max(-1.0_wp, min(1.0_wp, cosine)))
   if (test < 0.0_wp) phi = -phi

end function reference_dihedral

!> Cross product, local to the independent reference geometry of the tests.
pure function cross_product(a, b) result(c)
   !> First vector
   real(wp), intent(in) :: a(3)
   !> Second vector
   real(wp), intent(in) :: b(3)
   !> `a x b`
   real(wp) :: c(3)

   c(1) = a(2)*b(3) - a(3)*b(2)
   c(2) = a(3)*b(1) - a(1)*b(3)
   c(3) = a(1)*b(2) - a(2)*b(1)

end function cross_product

!> Rotate the atoms of `mask` about `axis` through `pivot` by `angle`.
!>
!> Independent reference: the rotation matrix is assembled explicitly instead
!> of using the vector expression of `rotate_fragment`.
pure subroutine reference_rotate(xyz, mask, pivot, axis, angle)
   !> Cartesian geometry (bohr), modified in place
   real(wp), intent(inout) :: xyz(:, :)
   !> Atoms to rotate
   logical, intent(in) :: mask(:)
   !> Point on the rotation axis (bohr)
   real(wp), intent(in) :: pivot(3)
   !> Rotation axis (bohr)
   real(wp), intent(in) :: axis(3)
   !> Rotation angle (radian)
   real(wp), intent(in) :: angle

   real(wp) :: u(3), rmat(3, 3), rel(3)
   real(wp) :: ca, sa, oc
   integer :: i

   u = axis/norm2(axis)
   ca = cos(angle)
   sa = sin(angle)
   oc = 1.0_wp - ca
   rmat(1, :) = [ca + oc*u(1)*u(1), oc*u(1)*u(2) - sa*u(3), &
      & oc*u(1)*u(3) + sa*u(2)]
   rmat(2, :) = [oc*u(2)*u(1) + sa*u(3), ca + oc*u(2)*u(2), &
      & oc*u(2)*u(3) - sa*u(1)]
   rmat(3, :) = [oc*u(3)*u(1) - sa*u(2), oc*u(3)*u(2) + sa*u(1), &
      & ca + oc*u(3)*u(3)]
   do i = 1, size(xyz, 2)
      if (.not. mask(i)) cycle
      rel = xyz(:, i) - pivot
      xyz(:, i) = pivot + matmul(rmat, rel)
   end do

end subroutine reference_rotate

!> Three atom test geometry: atom 1 carries the two bonds.
pure function triad() result(geom)
   !> Cartesian geometry (bohr)
   real(wp) :: geom(3, 3)

   geom(:, 1) = [0.0_wp, 0.0_wp, 0.0_wp]
   geom(:, 2) = [2.6_wp, 0.0_wp, 0.0_wp]
   geom(:, 3) = [0.5_wp, 2.2_wp, 0.0_wp]

end function triad

!> Fill a bond model with one or two harmonic bonds (plus an optional
!> quartic double well on the first bond).
subroutine new_bond_model(self, k, re, k2, re2, c, a, b)
   !> New model
   type(scan_bond_model), intent(out) :: self
   !> Force constant of the first bond (hartree/bohr^2)
   real(wp), intent(in) :: k
   !> Reference length of the first bond (bohr)
   real(wp), intent(in) :: re
   !> Force constant of the second bond, 0 disables it
   real(wp), intent(in), optional :: k2
   !> Reference length of the second bond (bohr)
   real(wp), intent(in), optional :: re2
   !> Quartic coefficient of the first bond (hartree/bohr^4)
   real(wp), intent(in), optional :: c
   !> First minimum of the quartic term (bohr)
   real(wp), intent(in), optional :: a
   !> Second minimum of the quartic term (bohr)
   real(wp), intent(in), optional :: b

   self%nbond = 1
   self%bond_at(:, 1) = [1, 2]
   self%bond_k(1) = k
   self%bond_re(1) = re
   if (present(c)) self%bond_c(1) = c
   if (present(a)) self%bond_a(1) = a
   if (present(b)) self%bond_b(1) = b
   if (present(k2)) then
      self%nbond = 2
      self%bond_at(:, 2) = [1, 3]
      self%bond_k(2) = k2
      self%bond_re(2) = re
      if (present(re2)) self%bond_re(2) = re2
   end if

end subroutine new_bond_model

!> Energy and gradient of the fragile model.
subroutine fragile_model_evaluate(self, x, energy, gradient, fail)
   !> Fragile model
   class(scan_fragile_model), intent(inout) :: self
   !> Flattened coordinates (bohr)
   real(wp), intent(in) :: x(:)
   !> Energy (hartree)
   real(wp), intent(out) :: energy
   !> Flattened gradient (hartree/bohr)
   real(wp), intent(out) :: gradient(:)
   !> Failure flag
   logical, intent(out) :: fail

   self%n_eval = self%n_eval + 1
   if (self%n_eval > self%budget) then
      energy = 0.0_wp
      gradient = 0.0_wp
      fail = .true.
      return
   end if
   call self%bond%evaluate(x, energy, gradient, fail)

end subroutine fragile_model_evaluate

!> Hessian of the fragile model (a scan point never asks for it).
subroutine fragile_model_hessian(self, x, hess, fail)
   !> Fragile model
   class(scan_fragile_model), intent(inout) :: self
   !> Flattened coordinates (bohr)
   real(wp), intent(in) :: x(:)
   !> Dense Hessian (hartree/bohr^2)
   real(wp), intent(out) :: hess(:, :)
   !> Failure flag
   logical, intent(out) :: fail

   hess = 0.0_wp
   fail = .true.

end subroutine fragile_model_hessian

!> Analytic model of the 1,2-dichloroethane torsion.
!>
!> Three harmonic bonds: C1-C2, which the scanned rotation preserves, and
!> C1-Cl4 and Cl3-H8, which run across the rotated central bond and therefore
!> change with the torsion.  The reference lengths are those of the starting
!> geometry, so the model is a pure torsion profile.
subroutine new_dce_bond_model(self, geom)
   !> New model
   type(scan_bond_model), intent(out) :: self
   !> Starting geometry (bohr)
   real(wp), intent(in) :: geom(:, :)

   integer, parameter :: npair = 3
   integer, parameter :: pair(2, npair) = reshape([1, 2, 1, 4, 3, 8], [2, npair])
   integer :: i

   self%nbond = npair
   do i = 1, npair
      self%bond_at(:, i) = pair(:, i)
      self%bond_k(i) = 0.5_wp
      self%bond_re(i) = norm2(geom(:, pair(2, i)) - geom(:, pair(1, i)))
   end do

end subroutine new_dce_bond_model

!> Energy and gradient of the bond model.
subroutine bond_model_evaluate(self, x, energy, gradient, fail)
   !> Bond model
   class(scan_bond_model), intent(inout) :: self
   !> Flattened coordinates (bohr)
   real(wp), intent(in) :: x(:)
   !> Energy (hartree)
   real(wp), intent(out) :: energy
   !> Flattened gradient (hartree/bohr)
   real(wp), intent(out) :: gradient(:)
   !> Failure flag
   logical, intent(out) :: fail

   real(wp), allocatable :: xyz(:, :), gxyz(:, :)
   real(wp) :: e, d1, d2
   integer :: ib, i, j

   fail = .false.
   allocate(xyz(3, size(x)/3), gxyz(3, size(x)/3))
   call geometry_unpack(x, xyz)
   gxyz = 0.0_wp
   e = 0.0_wp
   do ib = 1, self%nbond
      i = self%bond_at(1, ib)
      j = self%bond_at(2, ib)
      call bond_derivs(self, ib, xyz, d1, d2, e)
      call bond_axis(xyz, i, j, d1, gxyz)
   end do
   energy = e
   gradient = geometry_pack(gxyz)

end subroutine bond_model_evaluate

!> Hessian of the bond model.
subroutine bond_model_hessian(self, x, hess, fail)
   !> Bond model
   class(scan_bond_model), intent(inout) :: self
   !> Flattened coordinates (bohr)
   real(wp), intent(in) :: x(:)
   !> Dense Hessian (hartree/bohr^2)
   real(wp), intent(out) :: hess(:, :)
   !> Failure flag
   logical, intent(out) :: fail

   real(wp), allocatable :: xyz(:, :)
   real(wp) :: e, d1, d2, r, axis(3), block(3, 3)
   integer :: ib, i, j, ic, jc, a, b

   fail = .false.
   allocate(xyz(3, size(x)/3))
   call geometry_unpack(x, xyz)
   hess = 0.0_wp
   do ib = 1, self%nbond
      i = self%bond_at(1, ib)
      j = self%bond_at(2, ib)
      e = 0.0_wp
      call bond_derivs(self, ib, xyz, d1, d2, e)
      r = norm2(xyz(:, j) - xyz(:, i))
      axis = (xyz(:, j) - xyz(:, i))/r
      do ic = 1, 3
         do jc = 1, 3
            block(ic, jc) = d2*axis(ic)*axis(jc)
            if (ic == jc) block(ic, jc) = block(ic, jc) + d1/r
            block(ic, jc) = block(ic, jc) - (d1/r)*axis(ic)*axis(jc)
         end do
      end do
      do ic = 1, 3
         a = 3*(i - 1) + ic
         do jc = 1, 3
            b = 3*(j - 1) + jc
            hess(a, b) = hess(a, b) - block(ic, jc)
            hess(b, a) = hess(b, a) - block(ic, jc)
            hess(3*(i - 1) + ic, 3*(i - 1) + jc) = &
               & hess(3*(i - 1) + ic, 3*(i - 1) + jc) + block(ic, jc)
            hess(3*(j - 1) + ic, 3*(j - 1) + jc) = &
               & hess(3*(j - 1) + ic, 3*(j - 1) + jc) + block(ic, jc)
         end do
      end do
   end do

end subroutine bond_model_hessian

!> Energy and first derivative of one bond.
subroutine bond_derivs(self, ib, xyz, d1, d2, energy)
   !> Bond model
   class(scan_bond_model), intent(in) :: self
   !> Bond index
   integer, intent(in) :: ib
   !> Cartesian geometry (bohr)
   real(wp), intent(in) :: xyz(:, :)
   !> First derivative with respect to the bond length (hartree/bohr)
   real(wp), intent(out) :: d1
   !> Second derivative with respect to the bond length (hartree/bohr^2)
   real(wp), intent(out) :: d2
   !> Energy contribution (hartree), accumulated
   real(wp), intent(inout) :: energy

   real(wp) :: r, d, t1
   integer :: i, j

   i = self%bond_at(1, ib)
   j = self%bond_at(2, ib)
   r = norm2(xyz(:, j) - xyz(:, i))
   d = r - self%bond_re(ib)
   d1 = self%bond_k(ib)*d
   d2 = self%bond_k(ib)
   energy = energy + 0.5_wp*self%bond_k(ib)*d*d
   if (self%bond_c(ib) /= 0.0_wp) then
      t1 = (r - self%bond_a(ib))*(r - self%bond_b(ib))
      energy = energy + self%bond_c(ib)*t1*t1
      d1 = d1 + 2.0_wp*self%bond_c(ib)*t1*(2.0_wp*r - self%bond_a(ib) - &
         & self%bond_b(ib))
      d2 = d2 + 2.0_wp*self%bond_c(ib)*((2.0_wp*r - self%bond_a(ib) - &
         & self%bond_b(ib))**2 + 2.0_wp*t1)
   end if

end subroutine bond_derivs

!> Accumulate `d1 * d r / d x` of one bond into the Cartesian gradient.
subroutine bond_axis(xyz, i, j, d1, gxyz)
   !> Cartesian geometry (bohr)
   real(wp), intent(in) :: xyz(:, :)
   !> First atom of the bond
   integer, intent(in) :: i
   !> Second atom of the bond
   integer, intent(in) :: j
   !> Derivative with respect to the bond length (hartree/bohr)
   real(wp), intent(in) :: d1
   !> Cartesian gradient (hartree/bohr), accumulated
   real(wp), intent(inout) :: gxyz(:, :)

   real(wp) :: r, axis(3)

   r = norm2(xyz(:, j) - xyz(:, i))
   if (r <= 0.0_wp) return
   axis = (xyz(:, j) - xyz(:, i))/r
   gxyz(:, i) = gxyz(:, i) - d1*axis
   gxyz(:, j) = gxyz(:, j) + d1*axis

end subroutine bond_axis

!> Number of frames of a scan log whose energy is exactly zero.
!>
!> A point that was never evaluated has no energy; a `0.0` in the log is
!> either a fabricated value or - for a scan of a minimum of exactly zero -
!> an extremely unlikely coincidence, so the regression test treats it as the
!> failure mode it is.
function zero_energy_frames(fname) result(frames)
   !> File name
   character(len=*), intent(in) :: fname
   !> Number of frames with `energy: 0.000000000000`
   integer :: frames

   character(len=256) :: line
   integer :: unit, ierr, stat

   frames = 0
   open(newunit=unit, file=fname, action='read', iostat=ierr)
   if (ierr /= 0) return
   do
      read(unit, '(a)', iostat=stat) line
      if (stat /= 0) exit
      if (index(line, 'energy:') == 0) cycle
      if (index(line, 'energy: 0.000000000000') > 0) frames = frames + 1
   end do
   close(unit)

end function zero_energy_frames

!> Number of xyz frames in a file written by `writeMolecule`.
function count_frames(fname) result(frames)
   !> File name
   character(len=*), intent(in) :: fname
   !> Number of frames
   integer :: frames

   integer :: unit, ierr, stat, n, i, iatom

   frames = 0
   open(newunit=unit, file=fname, action='read', iostat=ierr)
   if (ierr /= 0) return
   do
      read(unit, *, iostat=stat) n
      if (stat /= 0) exit
      frames = frames + 1
      read(unit, '(a)', iostat=stat)
      if (stat /= 0) exit
      do iatom = 1, n
         read(unit, '(a)', iostat=stat)
         if (stat /= 0) exit
      end do
   end do
   close(unit)

end function count_frames

end module test_landscape_scan
