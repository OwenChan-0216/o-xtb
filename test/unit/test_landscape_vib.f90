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

!> Tests of the frequency task of the landscape suite (M3).
!>
!> Coverage, one independent check per property:
!>
!>  * mass weighting: the inverse of `xtb_freq_utils::massWeightHessian`
!>    reproduces its input, and the weighted element is the explicitly coded
!>    `h(i,j)/sqrt(m_i m_j)` (an inverted mass exponent passes the round trip
!>    but fails the explicit value).
!>  * analytic frequencies: a diatomic bond stretch has the exact solution
!>    `freq = autorcm*sqrt(k/mu)`; the Hessian comes from the injectable
!>    analytic model of the engine (`landscape_rosenbrock_model` and a
!>    hand-built stretch Hessian), so no SCF is involved.
!>  * mode counting: GFN2 water has 3N-6 = 3 internal modes and 6 projected
!>    zero modes, CO2 is linear and has 3N-5 = 4 (PLAN experiment 12).
!>  * projection: the raw numerical Hessian of water has **no** usable zero
!>    modes without the projection, which is why the projection is mandatory.
!>  * consistency with the existing `--hess`: the same raw Hessian through the
!>    legacy `trproj` route gives the same internal frequencies within the
!>    measured projection spread (see `test_water_vs_trproj`).
!>  * `hessian` file: write/read round trip is bitwise for values the record
!>    format can represent, the writer is byte identical to
!>    `xtb_freq_io::wrhess`, and every corruption mode is reported instead of
!>    terminating the program.
!>  * task level: the `vib` task writes `hessian`, `vibspectrum`,
!>    `vib_normal_modes` and `g98.out`, and reports the analysed energy.
module test_landscape_vib
   use testdrive, only : new_unittest, unittest_type, error_type, check
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_convert, only : autorcm
   use xtb_type_environment
   use xtb_type_molecule
   use xtb_type_restart, only : TRestart
   use xtb_type_calculator, only : TCalculator
   use xtb_xtb_calculator, only : TxTBCalculator, newXTBCalculator, newWavefunction
   use xtb_freq_io, only : wrhess
   use xtb_lin, only : lin
   use xtb_freq_project, only : trproj
   use xtb_freq_utils, only : massWeightHessian, diagHessian
   use xtb_landscape_settings, only : landscape_vib_settings, landscape_log_failed
   use xtb_landscape_results, only : landscape_result, landscape_vib_result
   use xtb_landscape_hessian, only : landscape_hessian_file, &
      & new_landscape_hessian_provider, landscape_hessian_provider, &
      & landscape_read_hessian_file, landscape_write_hessian_file
   use xtb_landscape_vib_numhess, only : landscape_vib_hessian
   use xtb_landscape_vib_modes, only : landscape_vib_analysis, &
      & landscape_vib_mass_unweight, landscape_vib_linear_geometry
   use xtb_landscape_tasks_vib, only : landscape_vib
   use xtb_landscape_testpot, only : landscape_rosenbrock_model, &
      & new_rosenbrock_model
   implicit none(type, external)
   private

   !> Test geometry: slightly distorted water in bohr (the same geometry as
   !> `test_landscape_hessian`, so the two suites probe the same point of the
   !> GFN2 surface)
   integer, parameter :: nat_water = 3
   character(len=*), parameter :: sym_water(nat_water) = ["O", "H", "H"]
   real(wp), parameter :: xyz_water(3, nat_water) = reshape([ &
      &  0.0_wp,  0.0_wp,  0.0_wp, &
      &  0.0_wp,  1.8_wp,  0.0_wp, &
      &  0.0_wp, -0.9_wp,  1.5_wp], [3, nat_water])

   !> Test geometry: linear CO2 in bohr
   integer, parameter :: nat_co2 = 3
   character(len=*), parameter :: sym_co2(nat_co2) = ["C", "O", "O"]
   real(wp), parameter :: xyz_co2(3, nat_co2) = reshape([ &
      &  0.0_wp,  0.0_wp, -2.2_wp, &
      &  0.0_wp,  0.0_wp,  0.0_wp, &
      &  0.0_wp,  0.0_wp,  2.2_wp], [3, nat_co2])

   !> Finite difference step and SCC accuracy of the test Hessians (the values
   !> of `landscape_engine_control`)
   real(wp), parameter :: hess_step = 5.0e-3_wp
   real(wp), parameter :: hess_acc = 0.3_wp

   public :: collect_landscape_vib

contains

!> Collect all exported unit tests
subroutine collect_landscape_vib(testsuite)
   !> Collection of tests
   type(unittest_type), allocatable, intent(out) :: testsuite(:)

   testsuite = [ &
      new_unittest("mass-weight-roundtrip", test_mass_weight), &
      new_unittest("linear-detection", test_linear_detection), &
      new_unittest("diatomic-analytic-frequency", test_diatomic_analytic), &
      new_unittest("rosenbrock-analytic-hessian", test_rosenbrock_hessian), &
      new_unittest("projection-required", test_projection_required), &
      new_unittest("water-modes-gfn2", test_water_modes), &
      new_unittest("water-vs-trproj", test_water_vs_trproj), &
      new_unittest("co2-linear-modes", test_co2_modes), &
      new_unittest("linear-saddle-imaginary", test_linear_saddle), &
      new_unittest("linear-rigid-fallback", test_linear_rigid_fallback), &
      new_unittest("extra-zero-modes", test_extra_zero_modes), &
      new_unittest("etemp-control", test_etemp_control), &
      new_unittest("hessian-file-roundtrip", test_hessian_file_roundtrip), &
      new_unittest("hessian-file-provider", test_hessian_file_provider), &
      new_unittest("hessian-file-failures", test_hessian_file_failures), &
      new_unittest("odlr-unsupported", test_odlr_unsupported), &
      new_unittest("vib-task-water", test_vib_task) &
      ]

end subroutine collect_landscape_vib

!> `massWeightHessian` followed by its inverse reproduces the input, and the
!> weighted element is `h(i,j)/sqrt(m_i m_j)`.
!>
!> The explicit value check is the falsifiable part: an inverted mass
!> exponent (`sqrt(m_i m_j)`) would pass a round trip trivially.
subroutine test_mass_weight(error)
   type(error_type), allocatable, intent(out) :: error
   real(wp) :: h(9, 9), weighted(9, 9), roundtrip(9, 9)
   real(wp) :: atmass(3), deviation, expected
   integer :: i, j

   atmass = [15.99940492_wp, 1.00794075_wp, 1.00794075_wp]*1822.888486_wp
   do i = 1, 9
      do j = 1, 9
         h(i, j) = 0.1_wp*real(i, wp) - 0.05_wp*real(j*j, wp)
      end do
      h(i, i) = 0.5_wp + 0.01_wp*real(i, wp)
   end do

   weighted = h
   call massWeightHessian(weighted, atmass)
   roundtrip = weighted
   call landscape_vib_mass_unweight(roundtrip, atmass)

   deviation = maxval(abs(roundtrip - h))/maxval(abs(h))
   call check(error, deviation < 1.0e-14_wp, &
      & "the mass weighting is not invertible")
   if (allocated(error)) return

   ! element (2,5): 5 -> atom 2, y component; 2 -> atom 1, y component
   expected = h(2, 5)/sqrt(atmass(2)*atmass(1))
   call check(error, abs(weighted(2, 5) - expected) <= 1.0e-13_wp*abs(expected), &
      & "the mass weighted element is not h(i,j)/sqrt(m_i m_j)")

end subroutine test_mass_weight

!> The linearity test of the mode analysis separates a linear from a bent
!> geometry, and a single atom counts as linear.
subroutine test_linear_detection(error)
   type(error_type), allocatable, intent(out) :: error
   real(wp) :: single(3, 1), bent(3, 3)

   call check(error, landscape_vib_linear_geometry(xyz_co2, 1.0e-4_wp), &
      & "CO2 was not detected as linear")
   if (allocated(error)) return
   call check(error, .not. landscape_vib_linear_geometry(xyz_water, 1.0e-4_wp), &
      & "water was detected as linear")
   if (allocated(error)) return

   single(:, 1) = 0.0_wp
   call check(error, landscape_vib_linear_geometry(single, 1.0e-4_wp), &
      & "a single atom was not detected as linear")
   if (allocated(error)) return

   ! bent CO2: 0.1 bohr off axis.  The smallest unit-mass moment of such a
   ! geometry is ~1e-2 bohr^2, two orders of magnitude above the threshold of
   ! the existing xtb check (`xtb_axis::is_linear`, 1.0e-4 bohr^2); a bend
   ! small enough to stay inside the threshold counts as linear on purpose,
   ! because that is what the 3N-5 rule of `--hess` assumes.
   bent = xyz_co2
   bent(1, 3) = 0.1_wp
   call check(error, .not. landscape_vib_linear_geometry(bent, 1.0e-4_wp), &
      & "a visibly bent CO2 was detected as linear")

end subroutine test_linear_detection

!> Analytic frequencies of a diatomic bond stretch.
!>
!> The Hessian of `E = k (r - r0)^2/2` at `r = r0` is `k*u u^T` with the unit
!> vector `u = (e_z, -e_z)` in the two atomic z coordinates.  Its mass
!> weighted matrix has the single non-zero eigenvalue `k/mu`
!> (`mu = m1 m2/(m1+m2)`), so the exact frequency is
!> `autorcm*sqrt(k/mu)`; all other five modes are exactly zero.
subroutine test_diatomic_analytic(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(landscape_vib_settings) :: settings
   type(landscape_vib_result) :: vib
   real(wp) :: xyz(3, 2), hess(6, 6), expected, mu, deviation
   logical :: fail

   ! two hydrogen atoms 1.4 bohr apart along z
   xyz(:, 1) = [0.0_wp, 0.0_wp, -0.7_wp]
   xyz(:, 2) = [0.0_wp, 0.0_wp, 0.7_wp]
   call init(env)
   call init(mol, [character(len=1) :: "H", "H"], xyz)

   hess = 0.0_wp
   hess(3, 3) = 0.5_wp
   hess(6, 6) = 0.5_wp
   hess(3, 6) = -0.5_wp
   hess(6, 3) = -0.5_wp

   settings = landscape_vib_settings()
   call landscape_vib_analysis(env, mol, hess, settings, vib, fail)
   call check(error, .not. fail, "the analysis of the diatomic Hessian failed")
   if (allocated(error)) return

   call check(error, vib%linear, "H2 was not detected as linear")
   if (allocated(error)) return
   call check(error, vib%n_zero, 5, "a linear molecule must have 5 zero modes")
   if (allocated(error)) return
   call check(error, vib%n_vib, 1, "a diatomic molecule has exactly one mode")
   if (allocated(error)) return
   call check(error, maxval(abs(vib%freq(1:5))), 0.0_wp, &
      & "the projected zero modes are not exactly zero")
   if (allocated(error)) return

   mu = mol%atmass(1)*mol%atmass(2)/(mol%atmass(1) + mol%atmass(2))
   expected = autorcm*sqrt(0.5_wp/mu)
   deviation = abs(vib%freq(6) - expected)/expected
   call check(error, deviation < 1.0e-10_wp, &
      & "the analytic diatomic frequency was not reproduced")
   if (allocated(error)) return
   call check(error, vib%n_imag, 0, "the stretch was reported as imaginary")

end subroutine test_diatomic_analytic

!> The Rosenbrock Hessian has a closed form; the engine model backend must
!> return exactly that matrix, and its eigenvalues must be the analytic ones.
!>
!> The frequency conversion itself is covered by the diatomic test above; this
!> test closes the "the Hessian we analyse is the Hessian of the potential"
!> precondition with a second, non-trivial analytic matrix.
subroutine test_rosenbrock_hessian(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_rosenbrock_model) :: model
   real(wp) :: x(2), hess(2, 2), expect(2, 2), ev(2), mean, half_diff
   logical :: fail

   call init(env)
   call new_rosenbrock_model(model, a=1.0_wp, b=100.0_wp)
   x = [1.0_wp, 1.0_wp]
   hess = 0.0_wp
   call model%hessian(x, hess, fail)
   call check(error, .not. fail, "the analytic Rosenbrock Hessian failed")
   if (allocated(error)) return

   ! closed form at (1, 1): [[2 + 12b - 4b, -4b], [-4b, 2b]] = [[802, -400], [-400, 200]]
   expect = reshape([802.0_wp, -400.0_wp, -400.0_wp, 200.0_wp], [2, 2])
   call check(error, maxval(abs(hess - expect)), 0.0_wp, &
      & "the analytic Rosenbrock Hessian is wrong")
   if (allocated(error)) return

   ! eigenvalues mean -/+ sqrt(half_diff^2 + b c) of the closed form
   ev = eigenvalues2x2(expect)
   mean = 0.5_wp*(expect(1, 1) + expect(2, 2))
   half_diff = sqrt((0.5_wp*(expect(1, 1) - expect(2, 2)))**2 + expect(1, 2)*expect(2, 1))
   call check(error, abs(ev(1) - (mean - half_diff)) < 1.0e-12_wp, &
      & "the Rosenbrock eigenvalue is wrong")
   if (allocated(error)) return
   call check(error, abs(ev(2) - (mean + half_diff)) < 1.0e-12_wp, &
      & "the Rosenbrock eigenvalue is wrong")
   if (allocated(error)) return
   ! a second point of the surface: the Hessian must change with the geometry
   x = [0.5_wp, 0.5_wp]
   hess = 0.0_wp
   call model%hessian(x, hess, fail)
   call check(error, .not. fail, "the analytic Rosenbrock Hessian failed")
   if (allocated(error)) return
   call check(error, abs(hess(2, 2) - 200.0_wp) < 1.0e-12_wp, &
      & "the analytic Rosenbrock Hessian is wrong off the minimum")

end subroutine test_rosenbrock_hessian

!> Without the projection the numerical Hessian of water has no usable
!> translation/rotation modes, so the analysis has to refuse it.
!>
!> This is the protection of PLAN section 6.6: the numerical Hessian lifts the
!> six null modes well above the 0.01 cm^-1 threshold, and a frequency list
!> built from such a matrix is meaningless.
subroutine test_projection_required(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_vib_settings) :: settings
   type(landscape_vib_result) :: vib
   real(wp), allocatable :: hess(:, :)
   real(wp), allocatable :: xyz_saved(:, :)
   integer :: nlog
   logical :: fail

   call setup_water(env, mol, chk, calc)
   allocate(xyz_saved(3, nat_water), source=mol%xyz)
   allocate(hess(9, 9))
   call raw_hessian(env, mol, chk, calc, hess)

   settings = landscape_vib_settings()
   settings%project_tr = .false.
   nlog = env%nLog
   call landscape_vib_analysis(env, mol, hess, settings, vib, fail)

   call check(error, fail, "the unprojected Hessian was accepted")
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog), &
      & "the refusal was not reported")
   if (allocated(error)) return
   ! the geometry is untouched by the analysis
   call check(error, maxval(abs(mol%xyz - xyz_saved)), 0.0_wp)

end subroutine test_projection_required

!> The GFN2 Hessian of water has 3N-6 = 3 internal modes and 6 projected zero
!> modes.
subroutine test_water_modes(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_vib_settings) :: settings
   type(landscape_vib_result) :: vib
   real(wp), allocatable :: hess(:, :)
   logical :: fail

   call setup_water(env, mol, chk, calc)
   allocate(hess(9, 9))
   call raw_hessian(env, mol, chk, calc, hess)

   settings = landscape_vib_settings()
   call landscape_vib_analysis(env, mol, hess, settings, vib, fail)
   call check(error, .not. fail, "the water analysis failed")
   if (allocated(error)) return
   call check(error, vib%linear, .false., "water was detected as linear")
   if (allocated(error)) return
   call check(error, vib%n_zero, 6, "water must have 6 projected zero modes")
   if (allocated(error)) return
   call check(error, vib%n_vib, 3, "water must have 3N-6 = 3 modes")
   if (allocated(error)) return
   call check(error, vib%n_imag, 0, "the distorted water Hessian is not stable")
   if (allocated(error)) return
   call check(error, maxval(abs(vib%freq(1:6))), 0.0_wp, &
      & "the projected zero modes are not exactly zero")
   if (allocated(error)) return
   ! the frequencies are above the noise of the Hessian and grow monotonically
   call check(error, vib%freq(7) > 100.0_wp, "the lowest mode is not a vibration")
   if (allocated(error)) return
   call check(error, vib%freq(8) > vib%freq(7), "the modes are not sorted")

end subroutine test_water_modes

!> The same **raw** Hessian through the route of the existing `--hess` (legacy
!> `trproj` projection) and through the Eckart projection of the landscape
!> suite gives the same internal frequencies within the projection spread.
!>
!> The two projections remove the same six rigid motions but define them in
!> different metrics: `trproj` builds unit-mass translation/rotation vectors
!> about the unit-mass centre of mass and projects the **non mass weighted**
!> Hessian (`src/freq/project.f90:151`), Eckart mass weights first and projects
!> the mass-weighted rigid vectors about the mass-weighted centre of mass
!> (`projectHessian`, `src/freq/project.f90:34`).  The removed subspaces
!> therefore differ, and so do the internal frequencies - the more, the further
!> the geometry is from a stationary point (measured on this build with the
!> distorted water of this file: 1318.01/3716.07/4141.55 (Eckart) against
!> 1318.55/3706.86/4128.64 (trproj), i.e. at most 12.91 cm^-1 or 0.31 %).
!>
!> Note that the reference must start from the **raw** matrix: the analysis
!> overwrites its argument, and re-projecting an already projected matrix makes
!> the two routes trivially agree (`vibspectrum` of `--hess` fed through
!> Eckart reproduces `--hess` to 0.01 cm^-1, docs/_landscape-recon/21-*.md
!> section 5.4).  The tolerance below is 0.5 % + 0.5 cm^-1, the measured spread
!> with margin.
subroutine test_water_vs_trproj(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_vib_settings) :: settings
   type(landscape_vib_result) :: vib
   real(wp), allocatable :: hess(:, :), raw(:, :), packed(:), projected(:, :)
   real(wp), allocatable :: mode_dummy(:, :)
   real(wp), allocatable :: freq_ref(:), ev(:)
   real(wp) :: tol
   integer :: i, j, n3
   logical :: fail

   call setup_water(env, mol, chk, calc)
   n3 = 3*nat_water
   allocate(hess(n3, n3))
   call raw_hessian(env, mol, chk, calc, hess)
   ! the analysis overwrites its argument, so keep the raw matrix for the
   ! reference route as well: both projections must act on the same input
   allocate(raw(n3, n3), source=hess)

   settings = landscape_vib_settings()
   call landscape_vib_analysis(env, mol, hess, settings, vib, fail)
   call check(error, .not. fail, "the water analysis failed")
   if (allocated(error)) return

   ! reference route: `trproj` on the packed lower triangle, exactly like
   ! `numhess` (`src/hessian.F90:358-374`), then mass weighting with the
   ! atomic units of `TMolecule%atmass`
   allocate(packed(n3*(n3 + 1)/2), projected(n3, n3), source=0.0_wp)
   do i = 1, n3
      do j = 1, i
         packed(lin(i, j)) = raw(i, j)
      end do
   end do
   allocate(mode_dummy(n3, 1), source=0.0_wp)
   call trproj(nat_water, n3, mol%xyz, packed, .false., 0, mode_dummy, 1)
   do i = 1, n3
      do j = 1, i
         projected(j, i) = packed(lin(i, j))
         projected(i, j) = packed(lin(i, j))
      end do
   end do
   call massWeightHessian(projected, mol%atmass)
   allocate(ev(n3), freq_ref(n3))
   call diagHessian(env, projected, ev)
   freq_ref = autorcm*ev

   do i = 7, n3
      tol = 0.005_wp*abs(freq_ref(i)) + 0.5_wp
      call check(error, abs(vib%freq(i) - freq_ref(i)) <= tol, &
         & "the Eckart frequency deviates from the trproj reference")
      if (allocated(error)) return
   end do
   ! the two routes must not agree trivially: the projection spread of this
   ! geometry is 12.91 cm^-1, so a bitwise match means the reference matrix was
   ! not the raw one (the analysis overwrites its argument)
   call check(error, maxval(abs(vib%freq(7:n3) - freq_ref(7:n3))) > 1.0_wp, &
      & "the two projections agree trivially; the raw matrix was not used")

end subroutine test_water_vs_trproj

!> CO2 is linear, so its Hessian has 3N-5 = 4 internal modes and 5 projected
!> zero modes (PLAN experiment 12).
!>
!> The two degenerate bends must come out as a pair; a wrong linearity
!> classification would report 3 instead of 4 modes.
subroutine test_co2_modes(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_vib_settings) :: settings
   type(landscape_vib_result) :: vib
   real(wp), allocatable :: hess(:, :)
   logical :: fail

   call init(env)
   call init(mol, sym_co2, xyz_co2)
   call newXTBCalculator(env, mol, calc, method=2)
   call newWavefunction(env, mol, calc, chk)
   allocate(hess(9, 9))
   call raw_hessian(env, mol, chk, calc, hess)

   settings = landscape_vib_settings()
   call landscape_vib_analysis(env, mol, hess, settings, vib, fail)
   call check(error, .not. fail, "the CO2 analysis failed")
   if (allocated(error)) return
   call check(error, vib%linear, "CO2 was not detected as linear")
   if (allocated(error)) return
   call check(error, vib%n_zero, 5, "a linear molecule has 5 zero modes")
   if (allocated(error)) return
   call check(error, vib%n_vib, 4, "CO2 must have 3N-5 = 4 modes")
   if (allocated(error)) return
   ! the two bends are degenerate: the first two internal modes
   call check(error, abs(vib%freq(7) - vib%freq(6)) < 5.0_wp, &
      & "the degenerate bends of CO2 are not degenerate")

end subroutine test_co2_modes

!> A linear molecule whose Hessian has genuine imaginary modes reports them.
!>
!> Linear H2O is a second order saddle on a straight line: its two bending
!> modes are really imaginary.  The pre-H3 classification took the `n_zero`
!> lowest eigenvalues unconditionally for a linear molecule, so it swallowed
!> the two bends as "zero modes" (and printed the lifted rotations as if they
!> were vibrations), which made the `--lts` imaginary-mode confirmation
!> meaningless for every linear saddle point (V1 / H3 of
!> `29-m4-independent-review.md`).
!>
!> The fix identifies the rigid body modes by their overlap with the analytic
!> translation/rotation subspace, so a genuinely imaginary bend - which is
!> orthogonal to that subspace - is kept as an internal mode.
subroutine test_linear_saddle(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_vib_settings) :: settings
   type(landscape_vib_result) :: vib
   real(wp) :: xyz(3, 3), hess(9, 9)
   logical :: fail

   ! linear H2O on the x axis (bohr); the geometry of the w180 case
   xyz(:, 1) = [0.0_wp, 0.0_wp, 0.0_wp]
   xyz(:, 2) = [0.96_wp, 0.0_wp, 0.0_wp]
   xyz(:, 3) = [-0.96_wp, 0.0_wp, 0.0_wp]
   call init(env)
   call init(mol, [character(len=1) :: "O", "H", "H"], xyz)
   call newXTBCalculator(env, mol, calc, method=2)
   call newWavefunction(env, mol, calc, chk)
   call raw_hessian(env, mol, chk, calc, hess)

   settings = landscape_vib_settings()
   call landscape_vib_analysis(env, mol, hess, settings, vib, fail)
   call check(error, .not. fail, "the linear H2O analysis failed")
   if (allocated(error)) return
   call check(error, vib%linear, "the linear H2O was not detected as linear")
   if (allocated(error)) return
   call check(error, vib%n_zero, 5, "a linear molecule has 5 zero modes")
   if (allocated(error)) return
   call check(error, vib%n_vib, 4, "a linear molecule has 3N-5 = 4 modes")
   if (allocated(error)) return
   ! the two degenerate bends are the imaginary pair
   call check(error, vib%n_imag, 2, &
      & "the two imaginary bends of linear H2O were not reported")
   if (allocated(error)) return
   ! ... and they are exactly those two modes, not just any two of the four
   ! internal modes.  Pinning the value and the sign (not only the count) makes
   ! the assertion sensitive to a classification that keeps the count but
   ! reports a lifted rigid mode:
   !   freq(6:9) = -10566.03, -10566.03, 20004.35, 21035.64 cm^-1
   call check(error, vib%freq(6) < -1000.0_wp .and. vib%freq(7) < -1000.0_wp, &
      & "the imaginary bends of linear H2O have the wrong sign or magnitude")
   if (allocated(error)) return
   call check(error, abs(vib%freq(6) - vib%freq(7)) < 1.0e-3_wp, &
      & "the two imaginary bends of linear H2O are not degenerate")
   if (allocated(error)) return
   call check(error, abs(vib%freq(6) + 10566.03_wp) < 5.0_wp, &
      & "the value of the imaginary bend of linear H2O changed")
   if (allocated(error)) return
   call check(error, vib%freq(8) > 0.0_wp .and. vib%freq(9) > vib%freq(8), &
      & "the two highest modes of linear H2O are not the positive stretches")

end subroutine test_linear_saddle

!> A linear Hessian whose eigenvectors avoid the rigid body subspace reaches
!> the fallback branch of the zero mode classification.
!>
!> The synthetic Hessian below is built from nine **prescribed** eigenvectors:
!> four are exact rigid body directions (overlap 1) and five span the
!> complement of those four rigid directions, so each of them carries only
!> `1/sqrt(5) = 0.447` of one rigid direction - below the 0.5 overlap
!> threshold.  A linear molecule needs `n_zero` = 5 zero modes, so the overlap
!> based selection finds only four of them and has to fall back to the lowest
!> remaining |frequency| mode, warning that the classification is unreliable.
!>
!> This is the only reachable case of the fallback path.  The test pins the
!> warning, the zero mode count, and *which* mode was swallowed: the remaining
!> eigenvector of smallest |frequency| (eigenvalue 0.15 hartree/bohr^2), whose
!> own frequency therefore disappears from the internal mode list.
subroutine test_linear_rigid_fallback(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(landscape_vib_settings) :: settings
   type(landscape_vib_result) :: vib
   real(wp) :: xyz(3, 3), hess(9, 9), expect(4)
   character(len=200) :: diag
   integer :: nlog
   logical :: fail

   ! linear H2O on the x axis (bohr) - the geometry of `test_linear_saddle`
   xyz(:, 1) = [0.0_wp, 0.0_wp, 0.0_wp]
   xyz(:, 2) = [0.96_wp, 0.0_wp, 0.0_wp]
   xyz(:, 3) = [-0.96_wp, 0.0_wp, 0.0_wp]
   call init(env)
   call init(mol, [character(len=1) :: "O", "H", "H"], xyz)

   call build_avoiding_linear_hessian(mol, hess)
   settings = landscape_vib_settings()
   nlog = env%nLog
   call landscape_vib_analysis(env, mol, hess, settings, vib, fail)

   call check(error, .not. fail, "the analysis of the distorted linear Hessian failed")
   if (allocated(error)) return
   call check(error, vib%linear, "the distorted geometry was not detected as linear")
   if (allocated(error)) return
   call check(error, vib%n_zero, 5, "the linear molecule must still have 5 zero modes")
   if (allocated(error)) return
   call check(error, vib%n_vib, 4, "the linear molecule must still have 4 internal modes")
   if (allocated(error)) return
   ! the fallback has to warn - it is the only warning of the linear branch
   call check(error, env%nLog > nlog, "the rigid body fallback did not warn")
   if (allocated(error)) return
   ! all five zero modes are reported as exactly zero
   call check(error, maxval(abs(vib%freq(1:5))), 0.0_wp, &
      & "the zero modes of the fallback are not exactly zero")
   if (allocated(error)) return
   ! four rigid directions were found; the missing zero mode is the remaining
   ! eigenvector of smallest |frequency| (eigenvalue 0.15), so the four internal
   ! modes are the other four prescribed eigenvectors, ascending
   expect = autorcm*[-sqrt(0.4_wp), -sqrt(0.25_wp), sqrt(0.3_wp), sqrt(0.6_wp)]
   write(diag, '("wrong zero mode filled: expected",4f11.2," got",4f11.2)') &
      & expect, vib%freq(6:9)
   call check(error, all(abs(vib%freq(6:9) - expect) < 1.0e-6_wp), trim(diag))
   if (allocated(error)) return
   call check(error, vib%n_imag, 2, "the two imaginary internal modes were lost")
   if (allocated(error)) return
   ! the swallowed mode (eigenvalue 0.15) kept no frequency of its own
   call check(error, all(abs(abs(vib%freq(6:9)) - autorcm*sqrt(0.15_wp)) > 1.0_wp), &
      & "the swallowed mode kept its own frequency")

end subroutine test_linear_rigid_fallback

!> Orthonormal basis of the rigid body directions in the mass weighted space.
!>
!> A test fixture that mirrors the (private) `landscape_vib_rigid_basis` of the
!> module under test: the three translations are `sqrt(m_a) e_c`, the rotations
!> `sqrt(m_a) (e_c x (x_a - x_cm))` about the mass weighted centre of mass,
!> Gram-Schmidt orthogonalised.  It is duplicated here (rather than exported)
!> so the production module surface is unchanged; the analysis is what the test
!> exercises.  The columns are orthonormal, `n_rigid` is 5 for a linear
!> molecule.
subroutine rigid_body_basis(mol, basis, n_rigid)
   !> Molecular structure
   type(TMolecule), intent(in) :: mol
   !> Orthonormal basis (3N rows, up to 6 columns)
   real(wp), allocatable, intent(out) :: basis(:, :)
   !> Number of valid columns
   integer, intent(out) :: n_rigid

   real(wp), allocatable :: raw(:, :), col(:)
   real(wp) :: centre(3), rvec(3), mtot, proj, nrm
   integer :: n3, iat, ic, a, k, c

   n3 = 3*mol%n
   allocate(basis(n3, 6), source=0.0_wp)
   allocate(raw(n3, 6), source=0.0_wp)
   n_rigid = 0

   ! translations
   do c = 1, 3
      do iat = 1, mol%n
         raw(3*(iat - 1) + c, c) = 1.0_wp
      end do
   end do

   ! rotations about the mass weighted centre of mass
   if (mol%n >= 2) then
      centre = 0.0_wp
      mtot = 0.0_wp
      do iat = 1, mol%n
         centre = centre + mol%atmass(iat)*mol%xyz(:, iat)
         mtot = mtot + mol%atmass(iat)
      end do
      if (mtot > 0.0_wp) centre = centre/mtot
      do iat = 1, mol%n
         rvec = mol%xyz(:, iat) - centre
         ic = 3*(iat - 1)
         raw(ic + 1, 4) = 0.0_wp
         raw(ic + 2, 4) = -rvec(3)
         raw(ic + 3, 4) = rvec(2)
         raw(ic + 1, 5) = rvec(3)
         raw(ic + 2, 5) = 0.0_wp
         raw(ic + 3, 5) = -rvec(1)
         raw(ic + 1, 6) = -rvec(2)
         raw(ic + 2, 6) = rvec(1)
         raw(ic + 3, 6) = 0.0_wp
      end do
   end if

   ! mass weight (the same factor as `massWeightHessian`)
   do iat = 1, mol%n
      ic = 3*(iat - 1)
      raw(ic + 1:ic + 3, :) = raw(ic + 1:ic + 3, :)*sqrt(mol%atmass(iat))
   end do

   do k = 1, 6
      nrm = sqrt(sum(raw(:, k)**2))
      if (nrm > 0.0_wp) raw(:, k) = raw(:, k)/nrm
   end do

   allocate(col(n3))
   do k = 1, 6
      col = raw(:, k)
      do a = 1, n_rigid
         proj = dot_product(basis(:, a), col)
         col = col - proj*basis(:, a)
      end do
      nrm = sqrt(dot_product(col, col))
      if (nrm <= 1.0e-8_wp) cycle
      n_rigid = n_rigid + 1
      basis(:, n_rigid) = col/nrm
   end do

end subroutine rigid_body_basis

!> Synthetic **mass weighted** Hessian of a linear molecule whose eigenvectors
!> deliberately avoid the rigid body subspace (fixture of
!> `test_linear_rigid_fallback`).
!>
!> The nine prescribed eigenvalues are all distinct, so the eigenvectors of the
!> assembled matrix are exactly the prescribed ones.  The matrix is returned in
!> the non mass weighted form (`h_ij = h_mw_ij*sqrt(m_i m_j)`) that
!> `landscape_vib_analysis` mass weights back into `h_mw`.
subroutine build_avoiding_linear_hessian(mol, hess)
   !> Linear molecule
   type(TMolecule), intent(in) :: mol
   !> Non mass weighted Hessian as expected by `landscape_vib_analysis`
   real(wp), intent(out) :: hess(:, :)
   !> Eigenvalues of the nine prescribed eigenvectors, all distinct
   real(wp), parameter :: lam(9) = [ &
      & -0.4_wp, -0.25_wp, 0.15_wp, 0.3_wp, 0.6_wp, &
      &  5.0_wp,  6.0_wp,  7.0_wp, 8.0_wp]

   real(wp), allocatable :: rigid(:, :), comp(:, :), b(:, :), q(:, :)
   real(wp) :: c5(5, 5), tmp(5), vec(9)
   real(wp) :: nrm
   integer :: n3, n_rigid, nc, ncomp, i, j, k, a

   n3 = 3*mol%n
   call rigid_body_basis(mol, rigid, n_rigid)

   ! orthonormal basis of the complement of the rigid body subspace
   allocate(comp(n3, n3), source=0.0_wp)
   ncomp = 0
   do k = 1, n3
      vec = 0.0_wp
      vec(k) = 1.0_wp
      do a = 1, n_rigid
         vec = vec - dot_product(rigid(:, a), vec)*rigid(:, a)
      end do
      do a = 1, ncomp
         vec = vec - dot_product(comp(:, a), vec)*comp(:, a)
      end do
      nrm = sqrt(sum(vec**2))
      if (nrm > 1.0e-10_wp) then
         ncomp = ncomp + 1
         comp(:, ncomp) = vec/nrm
      end if
   end do

   ! an orthogonal 5x5 matrix with a constant first row 1/sqrt(5), so every
   ! combination of the five basis vectors keeps the same 1/sqrt(5) of the
   ! single rigid direction and the set stays orthonormal
   c5 = 0.0_wp
   c5(1, :) = 1.0_wp/sqrt(5.0_wp)
   nc = 1
   do k = 1, 5
      tmp = 0.0_wp
      tmp(k) = 1.0_wp
      do a = 1, nc
         tmp = tmp - dot_product(c5(a, :), tmp)*c5(a, :)
      end do
      nrm = sqrt(sum(tmp**2))
      if (nrm > 1.0e-10_wp .and. nc < 5) then
         nc = nc + 1
         c5(nc, :) = tmp/nrm
      end if
   end do

   ! the nine eigenvectors: five combinations of rigid(:,1) and the four
   ! complement directions, then the four remaining rigid directions
   allocate(b(n3, 5), source=0.0_wp)
   b(:, 1) = rigid(:, 1)
   b(:, 2:5) = comp(:, 1:4)
   allocate(q(n3, n3), source=0.0_wp)
   do k = 1, 5
      do i = 1, 5
         q(:, k) = q(:, k) + c5(i, k)*b(:, i)
      end do
   end do
   do k = 6, 9
      q(:, k) = rigid(:, k - 4)
   end do

   ! assemble the mass weighted Hessian and un-weight it for the analysis
   hess = 0.0_wp
   do k = 1, 9
      do i = 1, n3
         hess(i, :) = hess(i, :) + lam(k)*q(i, k)*q(:, k)
      end do
   end do
   do i = 1, mol%n
      do j = 1, mol%n
         hess(3*(i - 1) + 1:3*i, 3*(j - 1) + 1:3*j) = &
            & hess(3*(i - 1) + 1:3*i, 3*(j - 1) + 1:3*j)*sqrt(mol%atmass(i)*mol%atmass(j))
      end do
   end do

end subroutine build_avoiding_linear_hessian

!> A Hessian with more near-zero modes than the six projected ones keeps every
!> mode: the additional ones become the lowest internal modes.
!>
!> The synthetic Hessian is rank one (a single H-H stretch, the third atom five
!> bohr away with an all-zero row and column), so the projected matrix has at
!> most one non-zero eigenvalue and eight near-zero ones - two more than the
!> six projected translations/rotations.  Every mode column must therefore be
!> a unit vector of the projected eigenbasis (the sorting may not drop a mode
!> or index the matrix with a slot it never assigned) and exactly one
!> frequency may be a vibration.
!>
!> This is the falsifiable coverage of the `extra_zero` branch, which no other
!> test of this file reaches: the analysis must not lose the two additional
!> modes and must not read an uninitialised `order` entry.
subroutine test_extra_zero_modes(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(landscape_vib_settings) :: settings
   type(landscape_vib_result) :: vib
   real(wp) :: xyz(3, 3), hess(9, 9), dot
   integer :: i, j, nlog
   logical :: fail

   ! the stretch pair on the z axis, the third atom far away and off axis
   xyz(:, 1) = [0.0_wp, 0.0_wp, -0.7_wp]
   xyz(:, 2) = [0.0_wp, 0.0_wp,  0.7_wp]
   xyz(:, 3) = [2.0_wp, 0.0_wp,  4.0_wp]
   call init(env)
   call init(mol, [character(len=1) :: "H", "H", "H"], xyz)

   hess = 0.0_wp
   hess(3, 3) =  0.5_wp
   hess(6, 6) =  0.5_wp
   hess(3, 6) = -0.5_wp
   hess(6, 3) = -0.5_wp

   settings = landscape_vib_settings()
   nlog = env%nLog
   call landscape_vib_analysis(env, mol, hess, settings, vib, fail)

   call check(error, .not. fail, "the analysis of the rank deficient Hessian failed")
   if (allocated(error)) return
   ! the warning of the additional near-zero modes is part of the contract
   call check(error, .not. landscape_log_failed(env, nlog), &
      & "the additional near-zero modes were reported as an error")
   if (allocated(error)) return
   call check(error, vib%linear, .false., "the test geometry is not linear")
   if (allocated(error)) return
   call check(error, vib%n_zero, 6, "the projected zero mode count changed")
   if (allocated(error)) return
   call check(error, vib%n_vib, 3, "the rank deficient Hessian lost a mode")
   if (allocated(error)) return
   ! the six projected modes are exactly zero, the two additional near-zero
   ! modes keep their own (noise level) frequency and the stretch is the only
   ! real vibration
   call check(error, maxval(abs(vib%freq(1:6))), 0.0_wp, &
      & "the projected zero modes are not exactly zero")
   if (allocated(error)) return
   call check(error, count(abs(vib%freq) > 1.0e-6_wp), 1, &
      & "the number of vibrational modes is wrong")
   if (allocated(error)) return
   call check(error, vib%freq(9) > 1000.0_wp, &
      & "the stretch is not the highest mode")
   if (allocated(error)) return
   call check(error, maxval(abs(vib%freq(7:8))) < 1.0e-6_wp, &
      & "the additional near-zero modes are not the two lowest internal modes")
   if (allocated(error)) return
   call check(error, vib%n_imag, 0, "the stretch was reported as imaginary")
   if (allocated(error)) return
   ! every column is an eigenvector of the projected Hessian: a duplicated or
   ! unassigned slot breaks the orthonormality of the mode matrix
   do j = 1, 9
      dot = sum(vib%modes(:, j)**2)
      call check(error, abs(dot - 1.0_wp) < 1.0e-10_wp, &
         & "a mode column is not normalised")
      if (allocated(error)) return
   end do
   do i = 1, 9
      do j = i + 1, 9
         dot = sum(vib%modes(:, i)*vib%modes(:, j))
         call check(error, abs(dot) < 1.0e-10_wp, &
            & "two mode columns are not orthogonal")
         if (allocated(error)) return
      end do
   end do
   ! the reduced masses of the three internal modes are defined
   call check(error, all(vib%rmass(7:9) > 0.0_wp), &
      & "an internal mode has no reduced mass")

end subroutine test_extra_zero_modes

!> The electronic temperature of the engine control reaches the calculator.
!>
!> `xtb_single::singlepoint` receives the temperature as an argument and drops
!> it (`src/single.f90:52`), so the value that is actually used is the
!> calculator's own field, which the engine has to write
!> (`landscape_engine%set_calculator` -> `push_calculator_etemp`).  Without
!> that push the control field would be dead and the two runs below would
!> return bitwise identical frequencies.
!>
!> The stretched H2 (2.4 A) is the soft-mode case measured in
!> `docs/_landscape-recon/21-m3-validation-experiments.md` section 3.1.  Its
!> only internal mode is the soft (here imaginary) H-H stretch; the electronic
!> temperature changes it by ~0.9 % between 300 K and 5000 K, which is far
!> above the round off of the finite difference, so the assertion is the
!> *change*, not an absolute frequency.  (The earlier version asserted a
!> 100 cm^-1 threshold on a value that the pre-H3 classification reported for a
!> *lifted rotation* instead of the real stretch; see
!> `29-m4-independent-review.md` H3.)
subroutine test_etemp_control(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_vib_settings) :: settings
   real(wp) :: xyz(3, 2), cold, hot, deviation

   call init(env)
   ! 2.4 A = 4.535 bohr, the stretched H2 of the validation experiment
   xyz(:, 1) = [0.0_wp, 0.0_wp, -2.26746_wp]
   xyz(:, 2) = [0.0_wp, 0.0_wp,  2.26746_wp]
   call init(mol, [character(len=1) :: "H", "H"], xyz)
   call newXTBCalculator(env, mol, calc, method=2)
   call newWavefunction(env, mol, calc, chk)

   settings = landscape_vib_settings()
   settings%engine%hess_step = hess_step
   settings%engine%hess_acc = hess_acc
   call stretched_h2_frequency(300.0_wp, cold)
   if (allocated(error)) return
   call stretched_h2_frequency(5000.0_wp, hot)
   if (allocated(error)) return

   call check(error, abs(cold) > 1.0_wp, "the 300 K mode is not a vibration")
   if (allocated(error)) return
   deviation = abs(hot - cold)/abs(cold)
   call check(error, deviation > 1.0e-3_wp, &
      & "the electronic temperature did not change the Hessian")

contains

   !> Frequency of the stretched H2 at one electronic temperature (cm^-1).
   subroutine stretched_h2_frequency(etemp, freq)
      !> Electronic temperature (kelvin)
      real(wp), intent(in) :: etemp
      !> Frequency of the only internal mode (cm^-1)
      real(wp), intent(out) :: freq

      type(landscape_vib_result) :: vib
      real(wp), allocatable :: hess(:, :), gradient(:, :)
      real(wp) :: energy, final_err
      logical :: fail

      freq = 0.0_wp
      allocate(hess(6, 6), gradient(3, 2))
      settings%engine%etemp = etemp
      call landscape_vib_hessian(env, mol, chk, calc, settings, hess, energy, &
         & gradient, final_err, fail)
      if (fail) then
         call check(error, .false., "the stretched H2 Hessian failed")
         return
      end if
      call landscape_vib_analysis(env, mol, hess, settings, vib, fail)
      if (fail) then
         call check(error, .false., "the stretched H2 analysis failed")
         return
      end if
      call check(error, vib%n_vib, 1, "H2 must have exactly one mode")
      if (allocated(error)) return
      freq = vib%freq(6)

   end subroutine stretched_h2_frequency

end subroutine test_etemp_control


!> Writing and reading a Hessian is a bitwise round trip, and the writer
!> produces exactly the bytes of `xtb_freq_io::wrhess`.
!>
!> The values are quantised to ten decimals, the resolution of the record
!> format `(5x,5f15.10)`, so the text round trip is exact.
subroutine test_hessian_file_roundtrip(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   real(wp) :: h(9, 9), readback(9, 9), packed(45)
   character(len=*), parameter :: file = "landscape_vib_roundtrip.dat"
   character(len=*), parameter :: reference = "landscape_vib_roundtrip_ref.dat"
   character(len=*), parameter :: crlf = "landscape_vib_roundtrip_crlf.dat"
   character(len=:), allocatable :: text_ours, text_ref
   integer :: i, j, k
   logical :: ok

   call init(env)
   ! values with exactly ten decimals: the record format `(5x,5f15.10)` can
   ! represent them, so writing and reading cannot lose anything
   do i = 1, 9
      do j = 1, i
         h(i, j) = real(nint(1.0e6_wp*sin(real(7*i + 3*j, wp))), wp)/1.0e10_wp
         h(j, i) = h(i, j)
      end do
      h(i, i) = real(nint(1.0e8_wp*cos(real(i, wp))), wp)/1.0e10_wp
   end do

   readback = 0.0_wp
   call landscape_write_hessian_file(env, file, h, ok)
   call check(error, ok, "the Hessian file was not written")
   if (allocated(error)) return
   call landscape_read_hessian_file(env, file, readback, ok)
   call check(error, ok, "the Hessian file was not read back")
   if (allocated(error)) return
   call check(error, maxval(abs(readback - h)), 0.0_wp, &
      & "the Hessian round trip is not bitwise")

   ! a file with CRLF line endings (produced on another platform) is read as
   ! well: the carriage return is a separator, not part of the number
   call write_text(crlf, split_lines(read_text(file)))
   readback = 0.0_wp
   call landscape_read_hessian_file(env, crlf, readback, ok)
   call check(error, ok, "a Hessian file with CRLF line endings was rejected")
   if (allocated(error)) return
   call check(error, maxval(abs(readback - h)), 0.0_wp, &
      & "the CRLF round trip is not bitwise")

   ! the same matrix through the writer of the existing implementation
   k = 0
   do i = 1, 9
      do j = 1, i
         packed(lin(i, j)) = h(i, j)
      end do
   end do
   call wrhess(9, packed, reference)
   text_ours = read_text(file)
   text_ref = read_text(reference)
   call check(error, text_ours, text_ref, "the writer differs from wrhess")

   call delete_text(file)
   call delete_text(reference)
   call delete_text(crlf)

end subroutine test_hessian_file_roundtrip

!> The file provider returns a Hessian that reproduces the frequencies of the
!> matrix it was written from.
subroutine test_hessian_file_provider(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_vib_settings) :: settings
   type(landscape_vib_result) :: vib_direct, vib_file
   class(landscape_hessian_provider), allocatable :: hp
   real(wp), allocatable :: hess(:, :), from_file(:, :)
   character(len=*), parameter :: file = "landscape_vib_provider.dat"
   real(wp) :: final_err
   integer :: nlog
   logical :: fail, ok

   call setup_water(env, mol, chk, calc)
   allocate(hess(9, 9), from_file(9, 9))
   call raw_hessian(env, mol, chk, calc, hess)

   settings = landscape_vib_settings()
   call landscape_vib_analysis(env, mol, hess, settings, vib_direct, fail)
   call check(error, .not. fail, "the direct analysis failed")
   if (allocated(error)) return

   ! the analysis projected the matrix; that is what the task writes to disk
   call landscape_write_hessian_file(env, file, hess, ok)
   call check(error, ok, "the Hessian file was not written")
   if (allocated(error)) return

   call new_landscape_hessian_provider(env, "file", hp, filename=file)
   call check(error, allocated(hp), "the file provider was not created")
   if (allocated(error)) return
   select type (hp)
   type is (landscape_hessian_file)
      call check(error, hp%filename, file, "the provider lost its file name")
   class default
      call check(error, .false., "unexpected provider type")
   end select
   if (allocated(error)) return

   from_file = 0.0_wp
   nlog = env%nLog
   call hp%compute(env, mol, chk, calc, from_file, hess_step, .false., final_err)
   call check(error, .not. landscape_log_failed(env, nlog), &
      & "reading the Hessian through the provider failed")
   if (allocated(error)) return
   call check(error, final_err, 0.0_wp)
   if (allocated(error)) return
   call check(error, hp%n_eval, 0, "the file provider evaluated the calculator")
   if (allocated(error)) return

   call landscape_vib_analysis(env, mol, from_file, settings, vib_file, fail)
   call check(error, .not. fail, "the analysis of the file Hessian failed")
   if (allocated(error)) return
   call check(error, maxval(abs(vib_file%freq - vib_direct%freq)) < 1.0e-6_wp, &
      & "the file Hessian does not reproduce the frequencies")
   if (allocated(error)) return
   call check(error, vib_file%n_vib, vib_direct%n_vib)

   call delete_text(file)

end subroutine test_hessian_file_provider

!> Every corruption mode of the Hessian reader is reported and leaves the
!> target matrix untouched.
subroutine test_hessian_file_failures(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   real(wp) :: hess(9, 9), saved(9, 9)
   character(len=*), parameter :: missing = "landscape_vib_does_not_exist.dat"
   character(len=*), parameter :: bad_header = "landscape_vib_bad_header.dat"
   character(len=*), parameter :: truncated = "landscape_vib_truncated.dat"
   character(len=*), parameter :: oversized = "landscape_vib_oversized.dat"
   character(len=*), parameter :: asymmetric = "landscape_vib_asymmetric.dat"
   character(len=*), parameter :: corrupt = "landscape_vib_corrupt.dat"
   character(len=*), parameter :: nonfinite = "landscape_vib_nonfinite.dat"
   class(landscape_hessian_provider), allocatable :: no_name
   integer :: nlog
   logical :: ok

   call init(env)
   saved = 0.0_wp
   saved(1, 1) = 42.0_wp

   ! 1. missing file
   hess = saved
   nlog = env%nLog
   call landscape_read_hessian_file(env, missing, hess, ok)
   call check(error, .not. ok, "a missing Hessian file was accepted")
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog), "the missing file was not reported")
   if (allocated(error)) return
   call check(error, maxval(abs(hess - saved)), 0.0_wp, &
      & "a failed read modified the target matrix")
   if (allocated(error)) return

   ! 2. wrong header
   call write_text(bad_header, [character(len=20) :: "not a hessian", "1.0 2.0"])
   hess = saved
   nlog = env%nLog
   call landscape_read_hessian_file(env, bad_header, hess, ok)
   call check(error, .not. ok, "a file without a $hessian header was accepted")
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog), "the wrong header was not reported")
   if (allocated(error)) return
   call check(error, maxval(abs(hess - saved)), 0.0_wp)

   ! 3. truncated matrix (only the first row)
   call write_text(truncated, [character(len=60) :: "$hessian", &
      & "       0.1000000000   0.0000000000   0.0000000000"])
   hess = saved
   nlog = env%nLog
   call landscape_read_hessian_file(env, truncated, hess, ok)
   call check(error, .not. ok, "a truncated Hessian file was accepted")
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog), "the truncation was not reported")
   if (allocated(error)) return
   call check(error, maxval(abs(hess - saved)), 0.0_wp)

   ! 4. dimension mismatch: the matrix of another molecule
   call write_square(oversized, 16, 1.0e-3_wp)
   hess = saved
   nlog = env%nLog
   call landscape_read_hessian_file(env, oversized, hess, ok)
   call check(error, .not. ok, "a Hessian of the wrong dimension was accepted")
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog), &
      & "the dimension mismatch was not reported")
   if (allocated(error)) return
   call check(error, maxval(abs(hess - saved)), 0.0_wp)

   ! 5. asymmetric matrix
   call write_asymmetric(asymmetric)
   hess = saved
   nlog = env%nLog
   call landscape_read_hessian_file(env, asymmetric, hess, ok)
   call check(error, .not. ok, "an asymmetric Hessian was accepted")
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog), &
      & "the asymmetry was not reported")
   if (allocated(error)) return
   call check(error, maxval(abs(hess - saved)), 0.0_wp)

   ! 6. a token that is not a number
   call write_text(corrupt, [character(len=60) :: "$hessian", &
      & "       0.1000000000  banana      0.0000000000"])
   hess = saved
   nlog = env%nLog
   call landscape_read_hessian_file(env, corrupt, hess, ok)
   call check(error, .not. ok, "a corrupt Hessian file was accepted")
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog), "the corrupt token was not reported")
   if (allocated(error)) return
   call check(error, maxval(abs(hess - saved)), 0.0_wp)

   ! 7. non-finite matrix
   call write_square(nonfinite, 9, 0.0_wp, nan_row=3)
   hess = saved
   nlog = env%nLog
   call landscape_read_hessian_file(env, nonfinite, hess, ok)
   call check(error, .not. ok, "a non-finite Hessian was accepted")
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog), "the NaN was not reported")
   if (allocated(error)) return
   call check(error, maxval(abs(hess - saved)), 0.0_wp)

   ! 8. a provider without a file name
   nlog = env%nLog
   call new_landscape_hessian_provider(env, "file", no_name)
   call check(error, .not. allocated(no_name), "the factory created an unusable provider")
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog), &
      & "the missing file name was not reported")
   if (allocated(error)) return

   call delete_text(bad_header)
   call delete_text(truncated)
   call delete_text(oversized)
   call delete_text(asymmetric)
   call delete_text(corrupt)
   call delete_text(nonfinite)

end subroutine test_hessian_file_failures

!> The ODLR approximation is not implemented and must be reported instead of
!> silently returning the full dense Hessian.
subroutine test_odlr_unsupported(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_vib_settings) :: settings
   real(wp), allocatable :: hess(:, :), gradient(:, :)
   real(wp) :: energy, final_err
   integer :: nlog
   logical :: fail

   call setup_water(env, mol, chk, calc)
   allocate(hess(9, 9), gradient(3, nat_water))
   settings = landscape_vib_settings()
   settings%engine%odlr = .true.
   settings%engine%hess_step = hess_step
   settings%engine%hess_acc = hess_acc

   nlog = env%nLog
   call landscape_vib_hessian(env, mol, chk, calc, settings, hess, energy, &
      & gradient, final_err, fail)

   call check(error, fail, "the ODLR request was not refused")
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog), &
      & "the ODLR request was not reported")
   if (allocated(error)) return
   call check(error, maxval(abs(hess)), 0.0_wp, &
      & "the refused call filled the Hessian")
   if (allocated(error)) return
   call check(error, maxval(abs(gradient)), 0.0_wp)

end subroutine test_odlr_unsupported

!> Task level run: the `vib` task must analyse the Hessian, write the four
!> output files of `--hess` and report the analysed energy.
subroutine test_vib_task(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_vib_settings) :: settings
   type(landscape_result) :: result
   real(wp), allocatable :: xyz_saved(:, :)
   character(len=16) :: files(4)
   integer :: i, size_
   logical :: exist

   call setup_water(env, mol, chk, calc)
   allocate(xyz_saved(3, nat_water), source=mol%xyz)
   settings = landscape_vib_settings()
   settings%printlevel = 0
   settings%engine%hess_step = hess_step
   settings%engine%hess_acc = hess_acc

   call landscape_vib(env, mol, chk, calc, settings, result)

   call check(error, result%converged, "the vib task did not converge")
   if (allocated(error)) return
   call check(error, result%message, "frequency analysis completed", &
      & "the vib task reported an unexpected message")
   if (allocated(error)) return
   ! the energy is the one of the analysed geometry, not the 0.0 default
   call check(error, abs(result%energy + 5.0_wp) < 1.0_wp, &
      & "the vib task did not report the energy of the geometry")
   if (allocated(error)) return
   ! the geometry is untouched
   call check(error, maxval(abs(mol%xyz - xyz_saved)), 0.0_wp, &
      & "the vib task modified the geometry")
   if (allocated(error)) return

   files = [character(len=16) :: &
      & "hessian", "vibspectrum", "vib_normal_modes", "g98.out"]
   do i = 1, size(files)
      inquire(file=trim(files(i)), exist=exist)
      call check(error, exist, "output file "//trim(files(i))//" is missing")
      if (allocated(error)) return
      inquire(file=trim(files(i)), size=size_)
      call check(error, size_ > 0, "output file "//trim(files(i))//" is empty")
      if (allocated(error)) return
   end do

   call delete_text("hessian")
   call delete_text("vibspectrum")
   call delete_text("vib_normal_modes")
   call delete_text("g98.out")

end subroutine test_vib_task

!> Eigenvalues of a symmetric 2x2 matrix, ascending.
pure function eigenvalues2x2(a) result(ev)
   !> Symmetric 2x2 matrix
   real(wp), intent(in) :: a(2, 2)
   !> Eigenvalues (ascending)
   real(wp) :: ev(2)

   real(wp) :: mean, half_diff, offdiag

   mean = 0.5_wp*(a(1, 1) + a(2, 2))
   half_diff = 0.5_wp*(a(1, 1) - a(2, 2))
   offdiag = sqrt(half_diff**2 + a(1, 2)*a(2, 1))
   ev = [mean - offdiag, mean + offdiag]

end function eigenvalues2x2

!> Create a fresh environment, molecule, wavefunction and GFN2 calculator for
!> the distorted water geometry of this suite.
subroutine setup_water(env, mol, chk, calc)
   type(TEnvironment), intent(out) :: env
   type(TMolecule), intent(out) :: mol
   type(TRestart), intent(out) :: chk
   type(TxTBCalculator), intent(out) :: calc

   call init(env)
   call init(mol, sym_water, xyz_water)
   call newXTBCalculator(env, mol, calc, method=2)
   call newWavefunction(env, mol, calc, chk)

end subroutine setup_water

!> The numerical Hessian of the calculator itself.
!>
!> This is the matrix the landscape provider returns as well (the provider is
!> verified against it in `test_landscape_hessian`), and the raw input of both
!> frequency routes compared in `test_water_vs_trproj`.
subroutine raw_hessian(env, mol, chk, calc, hess)
   type(TEnvironment), intent(inout) :: env
   type(TMolecule), intent(inout) :: mol
   type(TRestart), intent(inout) :: chk
   type(TxTBCalculator), intent(inout) :: calc
   real(wp), intent(out) :: hess(:, :)

   real(wp), allocatable :: dipgrad(:, :)
   real(wp) :: accuracy
   integer, allocatable :: list(:)
   integer :: i

   allocate(list(mol%n), dipgrad(3, 3*mol%n))
   list = [(i, i=1, mol%n)]
   hess = 0.0_wp
   dipgrad = 0.0_wp
   accuracy = calc%accuracy
   calc%accuracy = hess_acc
   call calc%hessian(env, mol, chk, list, hess_step, hess, dipgrad)
   calc%accuracy = accuracy
   hess = 0.5_wp*(hess + transpose(hess))

end subroutine raw_hessian

!> Split a text into its records, with CRLF line endings.
function split_lines(text) result(records)
   !> Text to split (LF separated)
   character(len=*), intent(in) :: text
   !> Records with a trailing carriage return
   character(len=:), allocatable :: records(:)

   integer :: i, n, start, count_

   count_ = 0
   do i = 1, len(text)
      if (text(i:i) == achar(10)) count_ = count_ + 1
   end do
   allocate(character(len=len(text) + 2) :: records(max(count_, 1)))
   start = 1
   n = 0
   do i = 1, len(text)
      if (text(i:i) /= achar(10)) cycle
      n = n + 1
      records(n) = text(start:i - 1)//achar(13)
      start = i + 1
   end do
   if (n == 0) n = 1
   records = records(1:n)

end function split_lines

!> Read a whole text file into a string.
function read_text(name) result(text)
   !> File name
   character(len=*), intent(in) :: name
   !> File content
   character(len=:), allocatable :: text

   character(len=1024) :: line
   integer :: unit, ierr

   text = ""
   open(newunit=unit, file=name, status='old', action='read', iostat=ierr)
   if (ierr /= 0) return
   do
      read(unit, '(a)', iostat=ierr) line
      if (ierr /= 0) exit
      text = text//trim(line)//achar(10)
   end do
   close(unit)

end function read_text

!> Write a list of records to a file.
subroutine write_text(name, lines)
   !> File name
   character(len=*), intent(in) :: name
   !> Records
   character(len=*), intent(in) :: lines(:)

   integer :: unit, i

   open(newunit=unit, file=name, action='write', iostat=i)
   do i = 1, size(lines)
      write(unit, '(a)') trim(lines(i))
   end do
   close(unit)

end subroutine write_text

!> Write a `$hessian` file holding the identity-like matrix of dimension `n3`.
!>
!> `nan_row` fills a complete row and column with quiet NaNs.
subroutine write_square(name, n3, scale, nan_row)
   !> File name
   character(len=*), intent(in) :: name
   !> Dimension of the matrix
   integer, intent(in) :: n3
   !> Off-diagonal value
   real(wp), intent(in) :: scale
   !> Row and column filled with NaN, 0 for none
   integer, intent(in), optional :: nan_row

   real(wp) :: row(5), nan
   integer :: unit, i, j, k, nrow, ncol, invalid

   invalid = 0
   if (present(nan_row)) invalid = nan_row
   nan = nan_value()

   open(newunit=unit, file=name, action='write')
   write(unit, '(a)') '$hessian'
   do i = 1, n3
      ncol = 0
      do while (ncol < n3)
         nrow = 0
         do j = ncol + 1, min(ncol + 5, n3)
            nrow = nrow + 1
            row(nrow) = merge(1.0_wp, scale, i == j)
            if (invalid > 0 .and. (i == invalid .or. j == invalid)) row(nrow) = nan
         end do
         ncol = min(ncol + 5, n3)
         write(unit, '(5f15.10)') (row(k), k=1,nrow)
      end do
   end do
   close(unit)

end subroutine write_square

!> A quiet NaN that is safe under `-ffpe-trap=invalid`.
function nan_value() result(value)
   use, intrinsic :: ieee_arithmetic, only : ieee_value, ieee_quiet_nan
   !> NaN
   real(wp) :: value

   value = ieee_value(0.0_wp, ieee_quiet_nan)

end function nan_value

!> Write a `$hessian` file whose (1,2) and (2,1) elements differ.
subroutine write_asymmetric(name)
   !> File name
   character(len=*), intent(in) :: name

   integer :: unit, i, j, jj

   open(newunit=unit, file=name, action='write')
   write(unit, '(a)') '$hessian'
   do i = 1, 9
      do j = 1, 9, 5
         write(unit, '(5f15.10)') (element(i, jj), jj=j, min(j + 4, 9))
      end do
   end do
   close(unit)

contains

   pure real(wp) function element(i, j) result(v)
      integer, intent(in) :: i, j

      v = 0.0_wp
      if (i == j) v = 1.0_wp
      if (i == 1 .and. j == 2) v = 0.25_wp
      if (i == 2 .and. j == 1) v = 0.24_wp
   end function element

end subroutine write_asymmetric

!> Delete a file if it exists.
subroutine delete_text(name)
   !> File name
   character(len=*), intent(in) :: name

   integer :: unit, ierr
   logical :: exist

   inquire(file=name, exist=exist)
   if (.not. exist) return
   open(newunit=unit, file=name, iostat=ierr)
   if (ierr /= 0) return
   close(unit, status='delete')

end subroutine delete_text

end module test_landscape_vib
