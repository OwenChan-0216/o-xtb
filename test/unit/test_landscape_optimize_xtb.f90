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

!> End-to-end test of the landscape minimiser with the real GFN2 calculator.
!>
!> A distorted water molecule is relaxed with the L-BFGS optimiser and the
!> engine boundary.  The SCF determinism probe (same geometry, two single
!> points with an invalidated cache) asserts the default `off` restart policy:
!> two evaluations of the identical geometry must be bitwise identical.  The
!> `warm` policy is reported with its magnitude, because reusing the previous
!> wavefunction introduces a SCF-history dependency of about 4e-7 Eh/bohr.
module test_landscape_optimize_xtb
   use testdrive, only : new_unittest, unittest_type, error_type, check
   use, intrinsic :: ieee_arithmetic, only : ieee_value, ieee_quiet_nan
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_io, only : stdout
   use xtb_mctc_convert, only : autoaa
   use xtb_type_environment
   use xtb_type_molecule
   use xtb_type_restart, only : TRestart
   use xtb_xtb_calculator, only : TxTBCalculator, newXTBCalculator, &
      & newWavefunction
   use xtb_landscape_settings, only : landscape_opt_settings, &
      & landscape_engine_control, landscape_log_failed, &
      & p_landscape_opt_lbfgs, p_landscape_opt_bfgs, &
      & p_landscape_opt_rfo, p_landscape_restart_warm
   use xtb_landscape_results, only : landscape_result
   use xtb_landscape_engine, only : landscape_engine, new_landscape_engine
   use xtb_landscape_tasks_opt, only : landscape_optimize
   implicit none
   private

   integer, parameter :: nat = 3
   character(len=*), parameter :: sym(nat) = ["O", "H", "H"]
   !> Distorted water in bohr (stretched and over-bent)
   real(wp), parameter :: xyz(3, nat) = reshape([ &
      &  0.0_wp,  0.0_wp,  0.0_wp, &
      &  0.0_wp,  1.8_wp,  0.0_wp, &
      &  0.0_wp, -0.9_wp,  1.5_wp], [3, nat])

   public :: collect_landscape_optimize_xtb

contains

!> Collect all exported unit tests
subroutine collect_landscape_optimize_xtb(testsuite)
   !> Collection of tests
   type(unittest_type), allocatable, intent(out) :: testsuite(:)

   testsuite = [ &
      new_unittest("water-gfn2-minimization", test_water_minimization), &
      new_unittest("water-gfn2-output-files", test_output_files), &
      new_unittest("water-gfn2-determinism", test_water_determinism), &
      new_unittest("gfn2-singlepoint-determinism", test_gfn2_determinism), &
      new_unittest("model-initial-hessian", test_model_initial_hessian), &
      new_unittest("hessian-cost-accounting", test_hessian_cost_accounting), &
      new_unittest("scf-non-convergence", test_scf_non_convergence), &
      new_unittest("missing-geometry", test_missing_geometry) &
      ]

end subroutine collect_landscape_optimize_xtb

!> GFN2 water must converge to a gradient below 1e-4 hartree/bohr.
subroutine test_water_minimization(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_opt_settings) :: set
   type(landscape_result) :: result
   real(wp) :: r_oh(2), angle

   call setup(env, mol, chk, calc)
   set = landscape_opt_settings()
   set%algorithm = p_landscape_opt_lbfgs
   set%printlevel = 0
   set%write_files = .false.

   call landscape_optimize(env, mol, chk, calc, set, result)

   write(stdout, '(1x,a,i0,a,l1)') "landscape water: ", result%n_steps, &
      & " steps, converged ", result%converged
   write(stdout, '(1x,a,es15.6,a)') "landscape water: final gmax ", result%gmax, &
      & " Eh/bohr"
   write(stdout, '(1x,a,i0)') "landscape water: energy evaluations ", result%n_eval

   call check(error, result%converged)
   if (allocated(error)) return
   call check(error, result%gmax < 1.0e-4_wp)
   if (allocated(error)) return
   call check(error, result%n_eval > 0)
   if (allocated(error)) return
   ! the optimised water must reproduce the GFN2-xTB reference geometry
   ! (obtained independently with `xtb water.xyz --gfn2 --opt`): two O-H
   ! distances of 0.9593 angstrom and an H-O-H angle of 107.2 degrees.  The
   ! distances and the angle are computed from `mol%xyz` using the element
   ! identities in `mol%at`.
   call water_geometry(mol, r_oh, angle)
   write(stdout, '(1x,a,f10.5,a,f10.5,a,f9.4)') "landscape water: r(OH) ", &
      & r_oh(1), "/", r_oh(2), " A, HOH ", angle
   call check(error, abs(r_oh(1) - 0.9593_wp) < 0.01_wp, &
      & "first O-H distance is not the GFN2 equilibrium value")
   if (allocated(error)) return
   call check(error, abs(r_oh(2) - 0.9593_wp) < 0.01_wp, &
      & "second O-H distance is not the GFN2 equilibrium value")
   if (allocated(error)) return
   call check(error, abs(angle - 107.2_wp) < 1.0_wp, &
      & "H-O-H angle is not the GFN2 equilibrium value")

end subroutine test_water_minimization

!> The driver must write the optimised geometry and the trajectory when
!> `write_files` is enabled, the trajectory must contain one frame per recorded
!> step plus the starting frame, and the first and last frame must reproduce
!> the starting and final geometries.  The files are removed again so that the
!> test does not leave artefacts in the working directory.
subroutine test_output_files(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_opt_settings) :: set
   type(landscape_result) :: result
   real(wp) :: first(3, nat), last(3, nat)
   logical :: have_xyz, have_trj
   integer :: nframes, ierr

   call setup(env, mol, chk, calc)
   set = landscape_opt_settings()
   set%algorithm = p_landscape_opt_lbfgs
   set%printlevel = 0
   set%write_files = .true.
   set%output_prefix = 'landscape_unittest'

   call landscape_optimize(env, mol, chk, calc, set, result)
   inquire(file='landscape_unittestopt.xyz', exist=have_xyz)
   inquire(file='landscape_unittest.trj', exist=have_trj)

   call check(error, have_xyz, "landscape_unittestopt.xyz was not written")
   if (allocated(error)) return
   call check(error, have_trj, "landscape_unittest.trj was not written")
   if (allocated(error)) return

   call read_trajectory('landscape_unittest.trj', nat, nframes, first, last, ierr)
   call check(error, ierr, 0, "cannot read the trajectory")
   if (allocated(error)) return
   ! one frame per accepted step plus the starting geometry
   call check(error, nframes, result%n_steps + 1)
   if (allocated(error)) return
   ! The xyz writer uses the CODATA bohr->angstrom factor of mctc-lib, while
   ! `xtb_mctc_convert::autoaa` is the rounded constant 0.52917726; the two
   ! differ by about 1e-7 relative.  The comparison therefore uses 1e-6
   ! angstrom, which is still five orders of magnitude tighter than any real
   ! geometry error.
   ! the first frame is the starting geometry
   call check(error, maxval(abs(first - xyz*autoaa)), 0.0_wp, thr=1.0e-6_wp)
   if (allocated(error)) return
   ! the last frame is the optimised geometry (`result%energy` belongs to it)
   call check(error, maxval(abs(last - mol%xyz*autoaa)), 0.0_wp, thr=1.0e-6_wp)
   if (allocated(error)) return
   ! the trajectory really moved away from the starting geometry
   call check(error, maxval(abs(last - first)) > 1.0e-2_wp)
   if (allocated(error)) return

   call delete_file('landscape_unittestopt.xyz')
   call delete_file('landscape_unittest.trj')
   inquire(file='landscape_unittest.trj', exist=have_trj)
   call check(error, .not. have_trj, "the trajectory was not cleaned up")

end subroutine test_output_files

!> Two independent minimisations of the same starting geometry must be bitwise
!> identical.  The default `off` restart policy evaluates every geometry from a
!> fixed reference wavefunction, so the result must not depend on the SCF
!> history of the run (measured in docs/_landscape-recon/07-*.md, section 3).
subroutine test_water_determinism(error)
   type(error_type), allocatable, intent(out) :: error
   real(wp) :: energy1, energy2

   call run_water(energy1)
   call run_water(energy2)

   write(stdout, '(1x,a,f20.12)') "landscape water: energy run 1 ", energy1
   write(stdout, '(1x,a,f20.12)') "landscape water: energy run 2 ", energy2
   call check(error, energy1 == energy2, &
      & "the off restart policy is not bitwise reproducible (energy)")

end subroutine test_water_determinism

!> Single point determinism probe: two evaluations of the identical geometry
!> (with an invalidated cache in between) must be bitwise identical under the
!> default `off` restart policy.  The `warm` policy is probed and reported.
subroutine test_gfn2_determinism(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_engine) :: engine
   type(landscape_engine_control) :: ctrl
   real(wp) :: energy1, energy2, grad1(3, nat), grad2(3, nat), difference
   logical :: fail

   ! default policy: off -> cold start before each evaluation
   call setup(env, mol, chk, calc)
   call new_landscape_engine(engine)
   call engine%set_calculator(calc)

   call engine%energy_gradient(env, mol, chk, energy1, grad1, fail)
   call check(error, .not. fail)
   if (allocated(error)) return
   call engine%invalidate()
   call engine%energy_gradient(env, mol, chk, energy2, grad2, fail)
   call check(error, .not. fail)
   if (allocated(error)) return

   write(stdout, '(1x,a,f20.12)') "gfn2 single point [off ]: energy 1 ", energy1
   write(stdout, '(1x,a,f20.12)') "gfn2 single point [off ]: energy 2 ", energy2
   write(stdout, '(1x,a,es12.4,a)') "gfn2 single point [off ]: gradient difference ", &
      & maxval(abs(grad1 - grad2)), " Eh/bohr"

   call check(error, energy1 == energy2, &
      & "off restart policy is not bitwise reproducible (energy)")
   if (allocated(error)) return
   call check(error, maxval(abs(grad1 - grad2)) == 0.0_wp, &
      & "off restart policy is not bitwise reproducible (gradient)")
   if (allocated(error)) return
   call check(error, engine%n_eval, 2)
   if (allocated(error)) return

   ! warm policy: the previous wavefunction is reused, a difference is allowed
   call setup(env, mol, chk, calc)
   ctrl = landscape_engine_control()
   ctrl%restart_mode = p_landscape_restart_warm
   call new_landscape_engine(engine, ctrl)
   call engine%set_calculator(calc)

   call engine%energy_gradient(env, mol, chk, energy1, grad1, fail)
   call check(error, .not. fail)
   if (allocated(error)) return
   call engine%invalidate()
   call engine%energy_gradient(env, mol, chk, energy2, grad2, fail)
   call check(error, .not. fail)
   if (allocated(error)) return

   difference = abs(energy1 - energy2)
   write(stdout, '(1x,a,es12.4,a)') "gfn2 single point [warm]: energy difference ", &
      & difference, " hartree"
   write(stdout, '(1x,a,es12.4,a)') "gfn2 single point [warm]: gradient difference ", &
      & maxval(abs(grad1 - grad2)), " Eh/bohr"

   ! only a loose guard: warm start is measured at ~4e-7 Eh/bohr
   call check(error, difference < 1.0e-8_wp)

end subroutine test_gfn2_determinism

!> The model Hessian (`hessian_source='model'`) is injected as the initial
!> quasi-Newton Hessian and must not make the minimisation worse than the
!> identity seed (BFGS) or the numerical seed (RFO).
!>
!> The measured step counts are printed so the M1 D3 claim is backed by real
!> GFN2 data.
subroutine test_model_initial_hessian(error)
   type(error_type), allocatable, intent(out) :: error
   integer :: steps_bfgs_model, steps_bfgs_identity, steps_rfo_model, &
      & steps_rfo_numerical
   logical :: ok_bfgs_model, ok_bfgs_identity, ok_rfo_model, ok_rfo_numerical

   call minimize_water(p_landscape_opt_bfgs, 'model', steps_bfgs_model, &
      & ok_bfgs_model)
   call minimize_water(p_landscape_opt_bfgs, 'numerical', steps_bfgs_identity, &
      & ok_bfgs_identity)
   call minimize_water(p_landscape_opt_rfo, 'model', steps_rfo_model, &
      & ok_rfo_model)
   call minimize_water(p_landscape_opt_rfo, 'numerical', steps_rfo_numerical, &
      & ok_rfo_numerical)

   write(stdout, '(1x,a,i0,a,l1)') "landscape model hessian: bfgs model seed     ", &
      & steps_bfgs_model, " steps, converged ", ok_bfgs_model
   write(stdout, '(1x,a,i0,a,l1)') "landscape model hessian: bfgs identity seed ", &
      & steps_bfgs_identity, " steps, converged ", ok_bfgs_identity
   write(stdout, '(1x,a,i0,a,l1)') "landscape model hessian: rfo  model seed     ", &
      & steps_rfo_model, " steps, converged ", ok_rfo_model
   write(stdout, '(1x,a,i0,a,l1)') "landscape model hessian: rfo  numerical seed ", &
      & steps_rfo_numerical, " steps, converged ", ok_rfo_numerical

   call check(error, ok_bfgs_model, "bfgs with a model seed did not converge")
   if (allocated(error)) return
   call check(error, ok_bfgs_identity, "bfgs with an identity seed did not converge")
   if (allocated(error)) return
   call check(error, steps_bfgs_model <= steps_bfgs_identity, &
      & "the model seed made BFGS worse than the identity seed")
   if (allocated(error)) return
   call check(error, ok_rfo_model, "rfo with a model seed did not converge")
   if (allocated(error)) return
   call check(error, ok_rfo_numerical, "rfo with a numerical seed did not converge")
   if (allocated(error)) return
   call check(error, steps_rfo_model <= steps_rfo_numerical, &
      & "the model seed made RFO worse than the numerical seed")

end subroutine test_model_initial_hessian

!> An unconverged SCC must never be handed back as a usable energy/gradient:
!> the engine refuses the result (and the task escalates it to an error).
!>
!> The failure is forced with `calc%maxiter = 1`, which makes every SCC stop
!> after one iteration.
subroutine test_scf_non_convergence(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_engine) :: engine
   type(landscape_opt_settings) :: set
   type(landscape_result) :: result
   real(wp) :: energy, grad(3, nat)
   logical :: fail
   integer :: nlog

   ! engine level: the unconverged evaluation is refused and counted
   call setup(env, mol, chk, calc)
   calc%maxiter = 1
   call new_landscape_engine(engine)
   call engine%set_calculator(calc)

   nlog = env%nLog
   call engine%energy_gradient(env, mol, chk, energy, grad, fail)
   call check(error, fail, "the engine returned an unconverged energy")
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog), &
      & "the unconverged SCC was not reported")
   if (allocated(error)) return
   call check(error, engine%n_scf_fail, 1)
   if (allocated(error)) return
   call engine%destroy()

   ! task level: no convergence report and an error in the log
   call setup(env, mol, chk, calc)
   calc%maxiter = 1
   set = landscape_opt_settings()
   set%algorithm = p_landscape_opt_lbfgs
   set%printlevel = 0
   set%write_files = .false.

   nlog = env%nLog
   call landscape_optimize(env, mol, chk, calc, set, result)
   call check(error, .not. result%converged, "the opt task reported convergence")
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog), &
      & "the opt task did not escalate the unconverged SCC")

end subroutine test_scf_non_convergence

!> A non-finite starting geometry makes the core return without a geometry;
!> the task must report it instead of continuing.
subroutine test_missing_geometry(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_opt_settings) :: set
   type(landscape_result) :: result
   integer :: nlog

   call setup(env, mol, chk, calc)
   mol%xyz(1, 1) = ieee_value(0.0_wp, ieee_quiet_nan)
   set = landscape_opt_settings()
   set%algorithm = p_landscape_opt_lbfgs
   set%printlevel = 0
   set%write_files = .false.

   nlog = env%nLog
   call landscape_optimize(env, mol, chk, calc, set, result)
   call check(error, .not. result%converged)
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog), &
      & "the missing geometry was not reported")

end subroutine test_missing_geometry

!> Minimise the distorted water with one algorithm and Hessian source.
subroutine minimize_water(algorithm, hessian_source, nsteps, converged, ncost)
   !> Minimisation algorithm
   integer, intent(in) :: algorithm
   !> Value of `hessian_source`
   character(len=*), intent(in) :: hessian_source
   !> Number of macro steps
   integer, intent(out) :: nsteps
   !> True if the run converged
   logical, intent(out) :: converged
   !> Number of engine single points (including the Hessian single points)
   integer, intent(out), optional :: ncost

   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_opt_settings) :: set
   type(landscape_result) :: result

   call setup(env, mol, chk, calc)
   set = landscape_opt_settings()
   set%algorithm = algorithm
   set%hessian_source = hessian_source
   set%printlevel = 0
   set%write_files = .false.

   call landscape_optimize(env, mol, chk, calc, set, result)
   nsteps = result%n_steps
   converged = result%converged
   if (present(ncost)) ncost = result%n_cache_miss

end subroutine minimize_water

!> A numerical Hessian costs 6N single points and those must appear in the
!> engine cost counter (`n_eval` / `result%n_cache_miss`); otherwise an RFO run
!> would report a fraction of its real cost.
subroutine test_hessian_cost_accounting(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_engine) :: engine
   real(wp) :: energy, grad(3, nat), hess(3*nat, 3*nat)
   logical :: fail, converged
   integer :: nsteps, ncost

   call setup(env, mol, chk, calc)
   call new_landscape_engine(engine)   ! default: numerical provider
   call engine%set_calculator(calc)

   call engine%energy_gradient(env, mol, chk, energy, grad, fail)
   call check(error, .not. fail)
   if (allocated(error)) return
   call check(error, engine%n_eval, 1)
   if (allocated(error)) return

   call engine%hessian(env, mol, chk, hess, fail)
   call check(error, .not. fail)
   if (allocated(error)) return
   ! 6N single points, N = number of atoms
   call check(error, engine%n_eval, 1 + 6*nat)
   if (allocated(error)) return
   call check(error, engine%n_hess, 1)
   if (allocated(error)) return

   ! the counter grows monotonically from call to call
   mol%xyz(1, 1) = mol%xyz(1, 1) + 0.05_wp
   call engine%energy_gradient(env, mol, chk, energy, grad, fail)
   call check(error, .not. fail)
   if (allocated(error)) return
   call check(error, engine%n_eval, 2 + 6*nat)
   if (allocated(error)) return
   call engine%destroy()

   ! an RFO run over the same molecule pays for at least its initial 6N Hessian
   call minimize_water(p_landscape_opt_rfo, 'numerical', nsteps, converged, &
      & ncost=ncost)
   write(stdout, '(1x,a,i0,a,i0,a,i0)') "landscape rfo cost: ", ncost, &
      & " single points for ", nsteps, " steps (", 6*nat, " = 6N in the Hessian)"
   call check(error, converged)
   if (allocated(error)) return
   call check(error, ncost >= 6*nat, &
      & "the RFO cost did not include the initial numerical Hessian")
   if (allocated(error)) return

end subroutine test_hessian_cost_accounting

!> Create a fresh environment, molecule, wavefunction and GFN2 calculator.
subroutine setup(env, mol, chk, calc)
   type(TEnvironment), intent(out) :: env
   type(TMolecule), intent(out) :: mol
   type(TRestart), intent(out) :: chk
   type(TxTBCalculator), intent(out) :: calc

   call init(env)
   call init(mol, sym, xyz)
   call newXTBCalculator(env, mol, calc, method=2)
   call newWavefunction(env, mol, calc, chk)

end subroutine setup

!> Minimise the distorted water from scratch and return the final energy.
subroutine run_water(energy)
   real(wp), intent(out) :: energy

   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_opt_settings) :: set
   type(landscape_result) :: result

   call setup(env, mol, chk, calc)
   set = landscape_opt_settings()
   set%algorithm = p_landscape_opt_lbfgs
   set%printlevel = 0
   set%write_files = .false.
   call landscape_optimize(env, mol, chk, calc, set, result)
   energy = result%energy

end subroutine run_water

!> O-H distances (angstrom) and H-O-H angle (degrees) of the water molecule.
!>
!> The oxygen and the two hydrogens are located through `mol%at`, so the
!> geometry is checked by element and not by a hardwired atom order.
subroutine water_geometry(mol, r_oh, angle)
   type(TMolecule), intent(in) :: mol
   !> O-H distances (angstrom)
   real(wp), intent(out) :: r_oh(2)
   !> H-O-H angle (degrees)
   real(wp), intent(out) :: angle

   real(wp), parameter :: rad_to_deg = 180.0_wp/3.1415926535897932_wp
   real(wp) :: vo(3), v1(3), v2(3)
   integer :: i, ioxygen, ihydrogen(2)

   ioxygen = 0
   ihydrogen = 0
   do i = 1, mol%n
      if (mol%at(i) == 8) then
         ioxygen = i
      else if (mol%at(i) == 1) then
         if (ihydrogen(1) == 0) then
            ihydrogen(1) = i
         else
            ihydrogen(2) = i
         end if
      end if
   end do

   vo = mol%xyz(:, ioxygen)
   v1 = mol%xyz(:, ihydrogen(1)) - vo
   v2 = mol%xyz(:, ihydrogen(2)) - vo
   r_oh(1) = sqrt(sum(v1**2))*autoaa
   r_oh(2) = sqrt(sum(v2**2))*autoaa
   angle = acos(dot_product(v1, v2)/(sqrt(sum(v1**2))*sqrt(sum(v2**2))))*rad_to_deg

end subroutine water_geometry

!> Read a concatenated xyz trajectory and return the frame count as well as the
!> first and last frame (`(3, nat)`, angstrom as written by the xyz writer).
subroutine read_trajectory(fname, natoms, nframes, first, last, ierr)
   character(len=*), intent(in) :: fname
   !> Number of atoms per frame
   integer, intent(in) :: natoms
   !> Number of frames found
   integer, intent(out) :: nframes
   !> First frame (angstrom)
   real(wp), intent(out) :: first(3, natoms)
   !> Last frame (angstrom)
   real(wp), intent(out) :: last(3, natoms)
   !> Read status, non-zero on a malformed file
   integer, intent(out) :: ierr

   real(wp) :: value(3)
   character(len=16) :: label
   character(len=256) :: line
   integer :: unit, iat, ncount, stat

   nframes = 0
   first = 0.0_wp
   last = 0.0_wp
   open(newunit=unit, file=fname, action='read', iostat=ierr)
   if (ierr /= 0) return
   do
      read(unit, '(i10)', iostat=stat) ncount
      if (stat /= 0) exit
      if (ncount /= natoms) then
         ierr = 1
         exit
      end if
      read(unit, '(a)', iostat=stat) line
      if (stat /= 0) then
         ierr = 1
         exit
      end if
      nframes = nframes + 1
      do iat = 1, ncount
         read(unit, '(a)', iostat=stat) line
         if (stat /= 0) then
            ierr = 1
            exit
         end if
         read(line, *, iostat=stat) label, value
         if (stat /= 0) then
            ierr = 1
            exit
         end if
         if (nframes == 1) first(:, iat) = value
         last(:, iat) = value
      end do
      if (ierr /= 0) exit
   end do
   close(unit)
   if (nframes == 0) ierr = 1

end subroutine read_trajectory

!> Remove a file left over by a test.
subroutine delete_file(fname)
   character(len=*), intent(in) :: fname

   integer :: unit, stat

   open(newunit=unit, file=fname, status='old', iostat=stat)
   if (stat /= 0) return
   close(unit, status='delete')

end subroutine delete_file

end module test_landscape_optimize_xtb
