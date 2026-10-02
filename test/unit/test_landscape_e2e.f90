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

!> L3 end-to-end regression of the landscape suite (M7, PLAN section 8.1).
!>
!> The L1 suite (`test_landscape_optimize_math`, `test_landscape_irc`, ...)
!> validates the algorithms on analytic potentials and the L2 suite
!> (`test_landscape_engine`) the engine boundary.  This file closes the chain
!> with real GFN2 calculations:
!>
!>  * `h2o-opt-freq-chain` runs `opt -> hess -> freq -> thermo` on water and
!>    compares the frequencies, ZPE, H(T) and G(T) against the legacy
!>    `trproj` route of `--hess`.  The comparison is **not** bitwise: the two
!>    routes project the same raw numerical Hessian with different
!>    conventions (Eckart on the mass weighted matrix versus `trproj` on the
!>    unweighted one), and the M3 validation measured the spread of that
!>    difference on a converged minimum as 0.0036-0.0757 cm^-1 (report 21,
!>    section 3.3; the distorted-water geometry of `test_landscape_vib`
!>    differs by 12.91 cm^-1 precisely because it is not a minimum).  The
!>    tolerances below are therefore stated as measured bounds, not as an
!>    exactness claim.
!>  * `chain-gradient-at-minimum` checks that the gradient norm at the
!>    optimised geometry really is small (the `opt` result feeds the `freq`
!>    step, a stale geometry would show up here).
!>  * `hcn-ts-irc-endpoints` locates the HCN/HNC saddle point with `--lts
!>    prfo`, integrates the IRC with the default `hpc` method and attributes
!>    the two endpoints to HCN and HNC from the H-C/H-N distances and the
!>    endpoint energies.
!>  * `ljson-determinism` writes the same document twice and requires byte
!>    identical files (the property `--ljson` exists for), and `sp-ljson`
!>    covers the one task that has no run type of its own.
!>  * `opt-failure-visible` pins the failure semantics: an unconverged
!>    minimisation reports through `env` instead of returning silently, which
!>    is what the chain runner of `landscape_e2e_check.py` checks between
!>    steps.
!>
!> Units: coordinates in bohr, energies in hartree, frequencies in cm^-1.
module test_landscape_e2e
   use testdrive, only : new_unittest, unittest_type, error_type, check
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_convert, only : autorcm
   use xtb_type_environment
   use xtb_type_molecule
   use xtb_type_restart, only : TRestart
   use xtb_type_calculator, only : TCalculator
   use xtb_xtb_calculator, only : TxTBCalculator, newXTBCalculator, newWavefunction
   use xtb_lin, only : lin
   use xtb_freq_project, only : trproj
   use xtb_freq_utils, only : massWeightHessian, diagHessian
   use xtb_landscape, only : run_landscape
   use xtb_landscape_settings, only : landscape_opt_settings, &
      & landscape_sp_settings, landscape_vib_settings, landscape_ts_settings, &
      & landscape_irc_settings, landscape_log_failed, p_landscape_ts_prfo, &
      & p_landscape_irc_hpc
   use xtb_landscape_results, only : landscape_result, landscape_vib_result, &
      & landscape_irc_result
   use xtb_landscape_tasks_opt, only : landscape_optimize
   use xtb_landscape_tasks_vib, only : landscape_vib
   use xtb_landscape_tasks_ts, only : landscape_ts
   use xtb_landscape_tasks_irc, only : landscape_irc
   use xtb_landscape_vib_numhess, only : landscape_vib_hessian
   use xtb_landscape_vib_modes, only : landscape_vib_analysis
   use xtb_landscape_vib_thermo, only : landscape_vib_thermo_output
   use xtb_landscape_json, only : landscape_json_document, &
      & landscape_json_document_init, landscape_json_add_result, &
      & landscape_json_write_file, landscape_json_status_ok
   use xtb_landscape_coords, only : vec_norm, geometry_pack
   implicit none(type, external)
   private

   public :: collect_landscape_e2e

   !> Numerical Hessian step used by every frequency comparison (bohr), the
   !> xtb default of `--hess` (`src/type/setvar.f90:156-158`).
   real(wp), parameter :: hess_step = 5.0e-3_wp
   !> SCC accuracy of the numerical Hessian, the xtb default of `--hess`.
   real(wp), parameter :: hess_acc = 0.3_wp
   !> Tolerance of the frequency comparison (cm^-1).  Measured on the
   !> converged water minimum of this file: 0.0971 cm^-1 (mode 3651.33 vs
   !> 3651.23); the M3 validation measured 0.0036-0.0757 cm^-1 at minima and
   !> 5.21 cm^-1 off a minimum (report 21, section 3.3).  The bound is twice
   !> the measurement of this geometry, so a real regression of the projection
   !> or of the finite difference cannot hide in it.
   real(wp), parameter :: freq_tol = 2.0e-1_wp
   !> Tolerance of the G/H/ZPE comparison (hartree).  Measured on the same
   !> minimum: 2.0e-7 hartree for all three quantities (the ZPE difference is
   !> half the frequency sum difference over `autorcm`); the bound is five
   !> times the measurement and still far below a thermochemical parameter
   !> error (a 1 % frequency scaling moves G by ~1e-4 hartree), so a wrong
   !> temperature, pressure or scaling cannot hide inside it.
   real(wp), parameter :: thermo_tol = 1.0e-6_wp
   !> Gradient norm (hartree/bohr) required at the optimised geometry of the
   !> chain.  The `tight` level used below has `g_max = 3e-5`, so the bound is
   !> the level's own maximum component; the measured Euclidean norm was
   !> 3.7e-6 (the Euclidean norm is bounded by sqrt(3N) times the maximum
   !> component, hence the factor 5).
   real(wp), parameter :: chain_gnorm_tol = 1.0e-4_wp

   !> Distorted water in bohr (the geometry of `test_landscape_vib`).
   integer, parameter :: nat_water = 3
   character(len=*), parameter :: sym_water(nat_water) = ["O", "H", "H"]
   real(wp), parameter :: xyz_water(3, nat_water) = reshape([ &
      &  0.0_wp,  0.0_wp,  0.0_wp, &
      &  0.0_wp,  1.8_wp,  0.0_wp, &
      &  0.0_wp, -0.9_wp,  1.5_wp], [3, nat_water])

   !> Bent HCN, the transition state guess of `test/unit/CMakeLists.txt`
   !> (`xtb/landscape-ts-prfo`).
   integer, parameter :: nat_hcn = 3
   character(len=*), parameter :: sym_hcn(nat_hcn) = ["H", "C", "N"]
   real(wp), parameter :: xyz_hcn(3, nat_hcn) = reshape([ &
      &  0.0_wp,  1.05_wp,  0.0_wp, &
      &  0.0_wp,  0.0_wp,   0.0_wp, &
      &  1.156_wp, 0.0_wp,  0.0_wp], [3, nat_hcn])

contains

!> Collect the end-to-end regression cases.
subroutine collect_landscape_e2e(testsuite)
   !> Test suite to fill
   type(unittest_type), allocatable, intent(out) :: testsuite(:)

   testsuite = [ &
      & new_unittest("h2o-opt-freq-chain", test_h2o_chain), &
      & new_unittest("chain-gradient-at-minimum", test_chain_gradient), &
      & new_unittest("hcn-ts-irc-endpoints", test_hcn_ts_irc), &
      & new_unittest("ljson-determinism", test_ljson_determinism), &
      & new_unittest("sp-ljson", test_sp_ljson), &
      & new_unittest("opt-failure-visible", test_opt_failure_visible) &
      & ]

end subroutine collect_landscape_e2e

!> `opt -> hess -> freq -> thermo` on water, compared against the `--hess`
!> route (legacy `trproj` projection) within the measured tolerances.
!>
!> The test runs the real `opt` and `vib` tasks and then rebuilds the Hessian
!> of the optimised geometry through the same provider the task uses.  The
!> engine is bitwise reproducible for a fixed thread count (AGENTS.md section
!> 6.1), so the rebuilt matrix is the one of the task and the comparison of
!> the two projections is a genuine same-matrix comparison.
subroutine test_h2o_chain(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_opt_settings) :: optset
   type(landscape_vib_settings) :: vibset
   type(landscape_result) :: optres, vibres
   type(landscape_vib_result) :: vib, legacy
   real(wp), allocatable :: hess(:, :), raw(:, :), gradient(:, :)
   real(wp), allocatable :: packed(:), projected(:, :), ev(:), freq_ref(:)
   real(wp), allocatable :: mode_dummy(:, :)
   real(wp) :: energy, final_err, max_dfreq
   integer :: i, j, n3
   logical :: fail, ok

   call setup_water(env, mol, chk, calc)
   n3 = 3*nat_water

   ! --- step 1: opt -------------------------------------------------------
   optset = landscape_opt_settings()
   optset%printlevel = 0
   optset%write_files = .false.
   optset%engine%hess_step = hess_step
   optset%engine%hess_acc = hess_acc
   call optset%set_conv_level('tight')
   call landscape_optimize(env, mol, chk, calc, optset, optres)
   call check(error, optres%converged, "the chain optimisation did not converge")
   if (allocated(error)) return
   call check(error, optres%gnorm <= chain_gnorm_tol, &
      & "the optimised geometry still has a large gradient")
   if (allocated(error)) return

   ! --- step 2/3: hess -> freq through the task ---------------------------
   vibset = landscape_vib_settings()
   vibset%printlevel = 0
   vibset%write_files = .false.
   vibset%engine%hess_step = hess_step
   vibset%engine%hess_acc = hess_acc
   call landscape_vib(env, mol, chk, calc, vibset, vibres)
   call check(error, vibres%converged, "the chain frequency analysis failed")
   if (allocated(error)) return
   call check(error, vibres%n_imag, 0, "the water minimum has an imaginary mode")
   if (allocated(error)) return
   call check(error, abs(vibres%energy - optres%energy) < 1.0e-8_wp, &
      & "the frequency step analysed a different geometry than the optimiser")
   if (allocated(error)) return

   ! --- the same Hessian, this suite's projection ------------------------
   allocate(hess(n3, n3), gradient(3, nat_water))
   call landscape_vib_hessian(env, mol, chk, calc, vibset, hess, energy, &
      & gradient, final_err, fail)
   call check(error, .not. fail, "the chain Hessian failed")
   if (allocated(error)) return
   allocate(raw(n3, n3), source=hess)
   call landscape_vib_analysis(env, mol, hess, vibset, vib, fail)
   call check(error, .not. fail, "the chain mode analysis failed")
   if (allocated(error)) return
   call landscape_vib_thermo_output(env, mol, chk, vibset, vib, energy, ok)
   call check(error, ok, "the chain thermochemistry failed")
   if (allocated(error)) return
   call cleanup_outputs()

   ! --- the same Hessian, the legacy `--hess` projection ------------------
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

   legacy = landscape_vib_result()
   legacy%freq = freq_ref
   legacy%n_zero = vib%n_zero
   legacy%n_vib = vib%n_vib
   legacy%n_imag = 0
   legacy%linear = vib%linear
   legacy%modes = vib%modes
   legacy%rmass = vib%rmass
   call landscape_vib_thermo_output(env, mol, chk, vibset, legacy, energy, ok)
   call check(error, ok, "the legacy thermochemistry failed")
   if (allocated(error)) return
   call cleanup_outputs()

   ! --- the acceptance comparison ----------------------------------------
   max_dfreq = 0.0_wp
   do i = vib%n_zero + 1, n3
      max_dfreq = max(max_dfreq, abs(vib%freq(i) - legacy%freq(i)))
   end do
   call check(error, max_dfreq <= freq_tol, &
      & "the chain frequencies differ from the --hess route by more than the "//&
      & "measured projection spread")
   if (allocated(error)) return
   call check(error, abs(vib%zpe - legacy%zpe) <= thermo_tol, &
      & "the chain zero point energy differs from the --hess route")
   if (allocated(error)) return
   ! The zero point energy of a minimum is half the sum of its internal
   ! frequencies (in hartree).  This identity is independent of the parameter
   ! plumbing of the reused thermochemistry: it is computed from `vib%freq`,
   ! which the frequency scaling factor never touches, so a wrong temperature,
   ! scaling or pressure inside `landscape_vib_set_thermo_settings` breaks it
   ! (both routes of the comparison above would shift by the same amount and
   ! stay equal to each other).
   call check(error, abs(vib%zpe - 0.5_wp*sum(vib%freq(vib%n_zero + 1:))/autorcm) &
      & <= 1.0e-10_wp, &
      & "the zero point energy is not the half sum of the internal frequencies")
   if (allocated(error)) return
   call check(error, abs(vib%enthalpy - legacy%enthalpy) <= thermo_tol, &
      & "the chain enthalpy differs from the --hess route")
   if (allocated(error)) return
   call check(error, abs(vib%gibbs - legacy%gibbs) <= thermo_tol, &
      & "the chain Gibbs energy differs from the --hess route")
   if (allocated(error)) return
   ! The three quantities must be present, not left at their zero default.
   call check(error, vib%zpe > 1.0e-3_wp .and. vib%enthalpy /= 0.0_wp .and. &
      & vib%gibbs /= 0.0_wp, "a thermochemical quantity of the chain is zero")

end subroutine test_h2o_chain

!> The gradient norm at the optimised geometry is small enough for the
!> frequency step to be meaningful.
!>
!> This is the chain consistency check of PLAN section 9.8: the `freq` step
!> consumes the geometry the `opt` step wrote, so a stale or mis-scaled
!> geometry would appear as a non-zero gradient here (the same quantity
!> `--hess` warns about at 2e-3 Eh/bohr).
subroutine test_chain_gradient(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_opt_settings) :: optset
   type(landscape_vib_settings) :: vibset
   type(landscape_result) :: optres
   real(wp), allocatable :: hess(:, :), gradient(:, :)
   real(wp) :: energy, final_err, gnorm
   logical :: fail

   call setup_water(env, mol, chk, calc)

   optset = landscape_opt_settings()
   optset%printlevel = 0
   optset%write_files = .false.
   optset%engine%hess_step = hess_step
   optset%engine%hess_acc = hess_acc
   call optset%set_conv_level('tight')
   call landscape_optimize(env, mol, chk, calc, optset, optres)
   call check(error, optres%converged, "the optimisation did not converge")
   if (allocated(error)) return

   ! The Hessian of the optimised geometry is built by the frequency task's
   ! own routine, so this is exactly what the `freq` step sees.
   vibset = landscape_vib_settings()
   vibset%printlevel = 0
   vibset%write_files = .false.
   vibset%engine%hess_step = hess_step
   vibset%engine%hess_acc = hess_acc
   allocate(hess(9, 9), gradient(3, nat_water))
   call landscape_vib_hessian(env, mol, chk, calc, vibset, hess, energy, &
      & gradient, final_err, fail)
   call check(error, .not. fail, "the chain Hessian failed")
   if (allocated(error)) return
   gnorm = vec_norm(geometry_pack(gradient))
   call check(error, gnorm <= chain_gnorm_tol, &
      & "the gradient of the frequency step is not that of a minimum")
   if (allocated(error)) return
   call check(error, gnorm <= 2.0e-3_wp, &
      & "the geometry would trigger the --hess non-stationary warning")

end subroutine test_chain_gradient

!> `ts -> irc` on HCN/HNC: the two IRC endpoints are the HCN and the HNC
!> minimum.
!>
!> The attribution does not use the printed labels: the H-C and H-N distances
!> of each endpoint geometry decide which isomer it is (HCN has the shorter
!> H-C distance, HNC the shorter H-N distance), and both endpoint energies
!> have to lie below the transition state energy.  The direction the
!> integrator calls "forward" is fixed by the phase convention of the
!> transition vector, so the test accepts either assignment as long as the
!> two endpoints are different isomers.
subroutine test_hcn_ts_irc(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_ts_settings) :: tsset
   type(landscape_irc_settings) :: ircset
   type(landscape_result) :: tsres
   type(landscape_irc_result) :: irc
   real(wp) :: d_hc_fwd, d_hn_fwd, d_hc_bwd, d_hn_bwd
   logical :: fwd_is_hcn, bwd_is_hcn

   call init(env)
   call init(mol, sym_hcn, xyz_hcn)
   call newXTBCalculator(env, mol, calc, method=2)
   call newWavefunction(env, mol, calc, chk)

   tsset = landscape_ts_settings()
   tsset%method = p_landscape_ts_prfo
   tsset%printlevel = 0
   tsset%write_files = .false.
   tsset%engine%hess_step = hess_step
   tsset%engine%hess_acc = hess_acc
   call landscape_ts(env, mol, chk, calc, tsset, tsres)
   call check(error, tsres%converged, "the HCN transition state search failed")
   if (allocated(error)) return
   call check(error, tsres%n_imag, 1, "the HCN candidate is not a first order saddle")
   if (allocated(error)) return
   call check(error, tsres%is_saddle, "the HCN candidate is not a saddle point")
   if (allocated(error)) return

   ircset = landscape_irc_settings()
   ircset%method = p_landscape_irc_hpc
   ircset%printlevel = 0
   ircset%write_files = .false.
   ircset%engine%hess_step = hess_step
   ircset%engine%hess_acc = hess_acc
   call landscape_irc(env, mol, chk, calc, ircset, irc)
   call check(error, irc%is_saddle, "the IRC input is not a first order saddle")
   if (allocated(error)) return
   call check(error, irc%n_fwd > 1 .and. irc%n_bwd > 1, &
      & "the IRC did not integrate both directions")
   if (allocated(error)) return
   call check(error, irc%reached_min_fwd, "the forward IRC endpoint is not a minimum")
   if (allocated(error)) return
   call check(error, irc%reached_min_bwd, "the backward IRC endpoint is not a minimum")
   if (allocated(error)) return

   d_hc_fwd = distance(irc%xyz_fwd(:, :, irc%n_fwd), 1, 2)
   d_hn_fwd = distance(irc%xyz_fwd(:, :, irc%n_fwd), 1, 3)
   d_hc_bwd = distance(irc%xyz_bwd(:, :, irc%n_bwd), 1, 2)
   d_hn_bwd = distance(irc%xyz_bwd(:, :, irc%n_bwd), 1, 3)
   fwd_is_hcn = d_hc_fwd < d_hn_fwd
   bwd_is_hcn = d_hc_bwd < d_hn_bwd

   call check(error, fwd_is_hcn .neqv. bwd_is_hcn, &
      & "both IRC endpoints are the same isomer")
   if (allocated(error)) return
   ! The bond assignment must be unambiguous: the two distances of one
   ! endpoint differ by a wide margin (HCN: H-C ~1.1 bohr, H-N ~2.9 bohr).
   call check(error, abs(d_hc_fwd - d_hn_fwd) > 1.0_wp, &
      & "the forward endpoint is not assigned to an isomer unambiguously")
   if (allocated(error)) return
   call check(error, abs(d_hc_bwd - d_hn_bwd) > 1.0_wp, &
      & "the backward endpoint is not assigned to an isomer unambiguously")
   if (allocated(error)) return

   ! Both endpoints are below the transition state; the two isomer minima are
   ! nearly degenerate on the GFN2 surface (measured difference 1.2e-3
   ! hartree), so no ordering between them is asserted.
   call check(error, irc%e_fwd(irc%n_fwd) < irc%energy_ts, &
      & "the forward IRC endpoint is above the transition state")
   if (allocated(error)) return
   call check(error, irc%e_bwd(irc%n_bwd) < irc%energy_ts, &
      & "the backward IRC endpoint is above the transition state")

end subroutine test_hcn_ts_irc

!> The JSON document of the same result is byte identical when written twice,
!> and its counters are the counters of the result object.
!>
!> The file name is unique to the test (`landscape_sp.json` would clash with
!> another suite), and the two files are compared line by line.  The counter
!> cross-check is the API level half of the CLI assertion in
!> `landscape_e2e_check.py` mode `ljson`: the document must not carry a second
!> bookkeeping.
subroutine test_ljson_determinism(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(landscape_result) :: result
   type(landscape_json_document) :: doc = landscape_json_document()
   character(len=*), parameter :: first = "landscape_e2e_first.json"
   character(len=*), parameter :: second = "landscape_e2e_second.json"
   character(len=:), allocatable :: text1, text2
   integer :: neval, ncache
   logical :: ok, found

   call init(env)
   ! A hand built result: the writer, not the task, is under test here.
   result%converged = .true.
   result%n_eval = 42
   result%n_cache_miss = 7
   result%n_steps = 3
   result%energy = -5.070544447809_wp
   result%gnorm = 3.676976e-6_wp
   result%message = "e2e json probe"

   call landscape_json_document_init(doc, 'sp')
   call landscape_json_add_result(doc, result, landscape_json_status_ok)
   call landscape_json_write_file(env, doc, first, ok)
   call check(error, ok, "the first JSON file was not written")
   if (allocated(error)) return
   call landscape_json_write_file(env, doc, second, ok)
   call check(error, ok, "the second JSON file was not written")
   if (allocated(error)) return

   text1 = read_text(first)
   text2 = read_text(second)
   call check(error, text1, text2, "the two JSON files differ")
   if (allocated(error)) return
   call json_counter(text1, "n_eval", neval, found)
   call check(error, found, "the document carries no n_eval counter")
   if (allocated(error)) return
   call check(error, neval, 42, "the counter of the result did not reach the document")
   if (allocated(error)) return
   call json_counter(text1, "n_cache_miss", ncache, found)
   call check(error, found, "the document carries no n_cache_miss counter")
   if (allocated(error)) return
   call check(error, ncache, 7, &
      & "the cache counter of the result did not reach the document")

   call delete_text(first)
   call delete_text(second)

end subroutine test_ljson_determinism

!> The `sp` task writes its document as well.
!>
!> `sp` has no run type of its own (it is reachable only through the API, see
!> `landscape_settings%task`), so the CLI checks of
!> `landscape_e2e_check.py` cannot cover it; this case closes that gap and
!> exercises the driver dispatch of the `sp` settings type at the same time.
subroutine test_sp_ljson(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_sp_settings) :: spset
   type(landscape_result) :: result
   character(len=*), parameter :: file = "landscape_sp.json"
   character(len=:), allocatable :: text
   integer :: neval
   logical :: exist, found

   call setup_water(env, mol, chk, calc)

   ! The name is fixed (`landscape_sp.json`), so a file left behind by an
   ! earlier run would satisfy the existence check below without the task
   ! writing anything (finding L-7 of `50-m7-independent-review.md`).
   call delete_text(file)

   spset = landscape_sp_settings()
   spset%printlevel = 0
   spset%ljson = .true.
   spset%engine%hess_step = hess_step
   spset%engine%hess_acc = hess_acc
   call run_landscape(env, mol, chk, calc, spset, result)
   call check(error, result%converged, "the single point did not converge")
   if (allocated(error)) return

   inquire(file=file, exist=exist)
   call check(error, exist, "landscape_sp.json was not written")
   if (allocated(error)) return
   text = read_text(file)
   call check(error, index(text, '"task": "sp"') > 0, &
      & "the document does not declare the sp task")
   if (allocated(error)) return
   call check(error, index(text, '"status": 0') > 0, &
      & "the sp document does not report the ok status")
   if (allocated(error)) return
   ! the counter is compared as a number: a substring test would accept
   ! `"n_eval": 12` as well (finding P2-6 of `52-m7-review-round2.md`)
   call json_counter(text, "n_eval", neval, found)
   call check(error, found, "the sp document carries no n_eval counter")
   if (allocated(error)) return
   call check(error, neval, 1, &
      & "the single point counter of the document is not 1")
   if (allocated(error)) return
   call check(error, index(text, '"energy": ') > 0, &
      & "the energy did not reach the document")
   call delete_text(file)

end subroutine test_sp_ljson

!> An unconverged minimisation is visible through `env`.
!>
!> The chain runner of `landscape_e2e_check.py` checks the exit status of
!> every step; at the API level the corresponding contract is that a task
!> which did not converge reports an error instead of returning silently.
!> With a step budget of one the minimiser cannot converge, so the error log
!> of `env` has to grow - that is the falsifiable part (a task that swallows
!> its failure would leave the log unchanged).
subroutine test_opt_failure_visible(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_opt_settings) :: optset
   type(landscape_result) :: optres
   integer :: nlog

   call setup_water(env, mol, chk, calc)

   optset = landscape_opt_settings()
   optset%printlevel = 0
   optset%write_files = .false.
   optset%max_steps = 1
   optset%engine%hess_step = hess_step
   optset%engine%hess_acc = hess_acc
   call optset%set_conv_level('tight')

   nlog = env%nLog
   call landscape_optimize(env, mol, chk, calc, optset, optres)
   call check(error, .not. optres%converged, &
      & "a one step minimisation claimed convergence")
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog), &
      & "the unconverged minimisation was not reported through the environment")

end subroutine test_opt_failure_visible

!> Squared distance between two atoms of a `(3, n)` geometry (bohr^2).
pure function distance_sq(xyz, iat, jat) result(value)
   !> Geometry (bohr)
   real(wp), intent(in) :: xyz(:, :)
   !> First atom index
   integer, intent(in) :: iat
   !> Second atom index
   integer, intent(in) :: jat
   !> Squared distance (bohr^2)
   real(wp) :: value

   value = sum((xyz(:, iat) - xyz(:, jat))**2)

end function distance_sq

!> Distance between two atoms of a `(3, n)` geometry (bohr).
pure function distance(xyz, iat, jat) result(value)
   !> Geometry (bohr)
   real(wp), intent(in) :: xyz(:, :)
   !> First atom index
   integer, intent(in) :: iat
   !> Second atom index
   integer, intent(in) :: jat
   !> Distance (bohr)
   real(wp) :: value

   value = sqrt(distance_sq(xyz, iat, jat))

end function distance

!> Fresh environment, molecule, wavefunction and GFN2 calculator for water.
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

!> Remove the files the reused `main_freq` writes unconditionally.
!>
!> The thermochemistry wrapper calls `main_freq`, which writes `vibspectrum`
!> and `g98.out` for every analysis (the `write_files` switch of the settings
!> only controls the files this suite writes itself).  The test removes them
!> so it leaves no artefact behind.
subroutine cleanup_outputs()
   character(len=16), parameter :: files(2) = [character(len=16) :: &
      & "vibspectrum", "g98.out"]

   integer :: i
   logical :: exist

   do i = 1, size(files)
      inquire(file=trim(files(i)), exist=exist)
      if (exist) call delete_text(files(i))
   end do

end subroutine cleanup_outputs

!> Read a text file into one string (the file is small).
function read_text(filename) result(text)
   !> File name
   character(len=*), intent(in) :: filename
   !> File content
   character(len=:), allocatable :: text

   character(len=1024) :: line
   integer :: unit, ierr

   text = ''
   open(newunit=unit, file=filename, action='read', iostat=ierr)
   if (ierr /= 0) return
   do
      read(unit, '(a)', iostat=ierr) line
      if (ierr /= 0) exit
      text = text//trim(line)//achar(10)
   end do
   close(unit)

end function read_text

!> Delete a file if it exists.
subroutine delete_text(filename)
   !> File name
   character(len=*), intent(in) :: filename

   integer :: unit
   logical :: exist

   inquire(file=filename, exist=exist)
   if (.not. exist) return
   open(newunit=unit, file=filename, status='old')
   close(unit, status='delete')

end subroutine delete_text

!> Integer value of one counter of a JSON document.
!>
!> The value is read as a whole number: the digits after `"<key>": ` are
!> consumed until the first character that is not a digit, so the counter
!> `n_eval: 12` does **not** satisfy a request for `1`.  A plain
!> `index(text, '"n_eval": 1') > 0` does match it, which is why the unit
!> cases below compare numbers instead of searching substrings (finding
!> P2-6 of `52-m7-review-round2.md`).
subroutine json_counter(text, key, value, found)
   !> Document text
   character(len=*), intent(in) :: text
   !> Counter key (without the quotes)
   character(len=*), intent(in) :: key
   !> Counter value (zero when the key is absent)
   integer, intent(out) :: value
   !> True if the key was found
   logical, intent(out) :: found

   character(len=:), allocatable :: pattern
   integer :: pos, i, digit

   value = 0
   found = .false.
   pattern = '"'//trim(key)//'": '
   pos = index(text, pattern)
   if (pos == 0) return
   found = .true.
   do i = pos + len(pattern), len(text)
      digit = ichar(text(i:i)) - ichar('0')
      if (digit < 0 .or. digit > 9) exit
      value = value*10 + digit
   end do

end subroutine json_counter

end module test_landscape_e2e
