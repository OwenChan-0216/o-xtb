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

!> Tests of the public entry point of the landscape suite.
!>
!> `run_landscape` is the only symbol the xtb main program calls, so it has to
!> dispatch the task of the settings object (`sp` and `opt`), to reject
!> unsupported settings types and to refuse geometries with periodic boundary
!> conditions.  The `opt` and `sp` tasks are exercised with the real GFN2
!> calculator; the `sp` energy is compared with a plain cold start single
!> point.
module test_landscape_api
   use testdrive, only : new_unittest, unittest_type, error_type, check
   use xtb_mctc_accuracy, only : wp
   use xtb_type_environment
   use xtb_type_molecule
   use xtb_type_restart, only : TRestart
   use xtb_type_data, only : scc_results
   use xtb_xtb_calculator, only : TxTBCalculator, newXTBCalculator, &
      & newWavefunction
   use xtb_landscape, only : run_landscape
   use xtb_landscape_settings, only : landscape_settings, &
      & landscape_opt_settings, landscape_sp_settings, p_landscape_opt_lbfgs, &
      & landscape_log_failed
   use xtb_landscape_results, only : landscape_result
   implicit none
   private

   integer, parameter :: nat = 3
   character(len=*), parameter :: sym(nat) = ["O", "H", "H"]
   !> Distorted water in bohr
   real(wp), parameter :: xyz(3, nat) = reshape([ &
      &  0.0_wp,  0.0_wp,  0.0_wp, &
      &  0.0_wp,  1.8_wp,  0.0_wp, &
      &  0.0_wp, -0.9_wp,  1.5_wp], [3, nat])

   !> Settings type of an unknown task, used to probe the dispatch error path
   type, extends(landscape_settings) :: landscape_bogus_settings
   contains
      !> Task name that the driver does not know
      procedure :: task => bogus_settings_task
   end type landscape_bogus_settings

   public :: collect_landscape_api

contains

!> Collect all exported unit tests
subroutine collect_landscape_api(testsuite)
   !> Collection of tests
   type(unittest_type), allocatable, intent(out) :: testsuite(:)

   testsuite = [ &
      new_unittest("single-point-task", test_single_point_task), &
      new_unittest("opt-task", test_opt_task), &
      new_unittest("unknown-task", test_unknown_task), &
      new_unittest("pbc-rejected", test_pbc_rejected) &
      ]

end subroutine collect_landscape_api

!> The `sp` task reports the energy of a cold start single point.
subroutine test_single_point_task(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env, env_ref
   type(TMolecule) :: mol, mol_ref
   type(TRestart) :: chk, chk_ref
   type(TxTBCalculator) :: calc, calc_ref
   type(landscape_sp_settings) :: set
   type(landscape_result) :: result
   type(scc_results) :: res
   real(wp) :: etot, gradient(3, nat), sigma(3, 3), egap

   call setup(env, mol, chk, calc)
   set = landscape_sp_settings()
   set%printlevel = 0
   set%write_gradient = .true.
   set%write_hessian = .true.

   call run_landscape(env, mol, chk, calc, set, result)
   call check(error, .not. landscape_log_failed(env, 0), "the sp task reported an error")
   if (allocated(error)) return
   call check(error, result%converged)
   if (allocated(error)) return
   call check(error, result%n_eval, 1)
   if (allocated(error)) return
   call check(error, result%gnorm > 0.0_wp)

   ! reference: the same geometry evaluated by the calculator directly
   call setup(env_ref, mol_ref, chk_ref, calc_ref)
   egap = 0.0_wp
   call calc_ref%singlepoint(env_ref, mol_ref, chk_ref, 0, .true., etot, &
      & gradient, sigma, egap, res)

   call check(error, result%energy, etot, thr=1.0e-9_wp)
   if (allocated(error)) return
   call check(error, result%gnorm, norm2(gradient), thr=1.0e-7_wp)

end subroutine test_single_point_task

!> The `opt` task minimises the geometry and reports the convergence.
subroutine test_opt_task(error)
   type(error_type), allocatable, intent(out) :: error
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

   call run_landscape(env, mol, chk, calc, set, result)
   call check(error, .not. landscape_log_failed(env, 0), "the opt task reported an error")
   if (allocated(error)) return
   call check(error, result%converged)
   if (allocated(error)) return
   call check(error, result%gmax < set%g_max)
   if (allocated(error)) return
   call check(error, result%n_eval > 0)
   if (allocated(error)) return
   call check(error, maxval(abs(mol%xyz - xyz)) > 0.0_wp)

end subroutine test_opt_task

!> An unknown task name must be reported, not silently ignored.
subroutine test_unknown_task(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_bogus_settings) :: set
   type(landscape_result) :: result
   integer :: nlog

   call setup(env, mol, chk, calc)
   set%printlevel = 0

   nlog = env%nLog
   call run_landscape(env, mol, chk, calc, set, result)
   call check(error, landscape_log_failed(env, nlog), &
      & "an unknown task was not reported")
   if (allocated(error)) return
   call check(error, result%n_eval, 0)

end subroutine test_unknown_task

!> Periodic boundary conditions are not supported and must be refused up front.
subroutine test_pbc_rejected(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_sp_settings) :: set
   type(landscape_result) :: result
   integer :: nlog

   call setup(env, mol, chk, calc)
   set%printlevel = 0
   mol%npbc = 3

   nlog = env%nLog
   call run_landscape(env, mol, chk, calc, set, result)
   call check(error, landscape_log_failed(env, nlog), &
      & "periodic boundary conditions were not refused")
   if (allocated(error)) return
   call check(error, result%n_eval, 0)

end subroutine test_pbc_rejected

!> Name of the unknown task of `landscape_bogus_settings`.
function bogus_settings_task(self) result(name)
   !> Settings instance
   class(landscape_bogus_settings), intent(in) :: self
   !> Task name
   character(len=:), allocatable :: name

   name = 'bogus'

end function bogus_settings_task

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

end module test_landscape_api
