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

!> Tests of the Hessian providers of the landscape suite.
!>
!> Two groups are covered:
!>
!>  * the `hessian_source` dispatch of `new_landscape_hessian_provider`
!>    (numerical, model and the error path of an unknown name),
!>  * the self-built central difference Hessian: it has to reproduce the
!>    numerical Hessian of xtb itself (`TCalculator%hessian`, same step and same
!>    SCC accuracy), it has to be exactly symmetric, it must restore the
!>    geometry and the calculator accuracy, and it must reject the ODLR
!>    approximation it cannot provide.
module test_landscape_hessian
   use testdrive, only : new_unittest, unittest_type, error_type, check
   use xtb_mctc_accuracy, only : wp
   use xtb_type_environment
   use xtb_type_molecule
   use xtb_type_restart, only : TRestart
   use xtb_xtb_calculator, only : TxTBCalculator, newXTBCalculator, &
      & newWavefunction
   use xtb_landscape_settings, only : landscape_log_failed, landscape_engine_control
   use xtb_landscape_hessian, only : landscape_hessian_provider, &
      & landscape_numerical_hessian_provider, landscape_model_hessian_provider, &
      & landscape_hessian_source_known, new_landscape_hessian_provider
   use xtb_landscape_engine, only : landscape_engine, new_landscape_engine
   implicit none
   private

   integer, parameter :: nat = 3
   character(len=*), parameter :: sym(nat) = ["O", "H", "H"]
   !> Distorted water in bohr
   real(wp), parameter :: xyz(3, nat) = reshape([ &
      &  0.0_wp,  0.0_wp,  0.0_wp, &
      &  0.0_wp,  1.8_wp,  0.0_wp, &
      &  0.0_wp, -0.9_wp,  1.5_wp], [3, nat])
   !> Finite difference step of the Hessian (bohr)
   real(wp), parameter :: hess_step = 5.0e-3_wp
   !> SCC accuracy during the Hessian evaluation
   real(wp), parameter :: hess_acc = 0.3_wp

   public :: collect_landscape_hessian

contains

!> Collect all exported unit tests
subroutine collect_landscape_hessian(testsuite)
   !> Collection of tests
   type(unittest_type), allocatable, intent(out) :: testsuite(:)

   testsuite = [ &
      new_unittest("source-selection", test_source_selection), &
      new_unittest("source-known", test_source_known), &
      new_unittest("numerical-vs-calculator", test_numerical_vs_calculator), &
      new_unittest("numerical-odlr-rejected", test_numerical_odlr_rejected), &
      new_unittest("model-hessian", test_model_hessian), &
      new_unittest("engine-failure-propagates", test_engine_failure_propagates) &
      ]

end subroutine collect_landscape_hessian

!> The provider factory must return the implementation named by the source and
!> must report an unknown name instead of falling back to a default.
subroutine test_source_selection(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   class(landscape_hessian_provider), allocatable :: hp
   integer :: nlog

   call init(env)

   call new_landscape_hessian_provider(env, "numerical", hp, sccacc=0.42_wp)
   call check(error, allocated(hp), "numerical provider was not created")
   if (allocated(error)) return
   call check(error, hp%name, "numerical")
   if (allocated(error)) return
   call check(error, hp%exact, .false.)
   if (allocated(error)) return
   select type (hp)
   type is (landscape_numerical_hessian_provider)
      call check(error, hp%sccacc, 0.42_wp)
   class default
      call check(error, .false., "unexpected provider type")
   end select
   if (allocated(error)) return
   deallocate(hp)

   call new_landscape_hessian_provider(env, "model", hp)
   call check(error, allocated(hp), "model provider was not created")
   if (allocated(error)) return
   call check(error, hp%name, "model")
   if (allocated(error)) return
   select type (hp)
   type is (landscape_model_hessian_provider)
      call check(error, .true.)
   class default
      call check(error, .false., "unexpected provider type")
   end select
   if (allocated(error)) return
   deallocate(hp)

   ! the default sccacc of the numerical provider is the xtb value
   call new_landscape_hessian_provider(env, "numerical", hp)
   select type (hp)
   type is (landscape_numerical_hessian_provider)
      call check(error, hp%sccacc, 0.3_wp)
   class default
      call check(error, .false., "unexpected provider type")
   end select
   if (allocated(error)) return
   deallocate(hp)

   nlog = env%nLog
   call new_landscape_hessian_provider(env, "bogus", hp)
   call check(error, .not. allocated(hp), "unknown source returned a provider")
   if (allocated(error)) return
   call check(error, landscape_log_failed(env, nlog), &
      & "unknown hessian source was not reported")

end subroutine test_source_selection

!> Only the implemented source names are accepted.
subroutine test_source_known(error)
   type(error_type), allocatable, intent(out) :: error

   call check(error, landscape_hessian_source_known("numerical"))
   if (allocated(error)) return
   call check(error, landscape_hessian_source_known("model"))
   if (allocated(error)) return
   ! `file` joins the known sources in M3 (`landscape_hessian_file`); the
   ! reader itself is covered by `test_landscape_vib`
   call check(error, landscape_hessian_source_known("file"))
   if (allocated(error)) return
   call check(error, .not. landscape_hessian_source_known(""))
   if (allocated(error)) return
   call check(error, .not. landscape_hessian_source_known("Numerical"))

end subroutine test_source_known

!> The self-built finite difference Hessian must reproduce the numerical
!> Hessian of xtb (`TCalculator%hessian`) for the same step and the same SCC
!> accuracy, and must leave the geometry and the calculator accuracy untouched.
subroutine test_numerical_vs_calculator(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_numerical_hessian_provider) :: hp
   real(wp), allocatable :: reference(:, :), hess(:, :), dipgrad(:, :)
   real(wp), allocatable :: xyz_saved(:, :)
   real(wp) :: accuracy, final_err, deviation
   integer, allocatable :: list(:)
   integer :: i, n

   call setup(env, mol, chk, calc)
   n = 3*nat
   allocate(reference(n, n), hess(n, n), dipgrad(3, n))
   allocate(list(nat))
   list = [(i, i=1, nat)]
   reference = 0.0_wp
   dipgrad = 0.0_wp

   ! reference: the numerical Hessian of the calculator itself
   accuracy = calc%accuracy
   calc%accuracy = hess_acc
   call calc%hessian(env, mol, chk, list, hess_step, reference, dipgrad)
   calc%accuracy = accuracy
   reference = 0.5_wp*(reference + transpose(reference))

   ! the landscape provider
   allocate(xyz_saved(3, nat), source=mol%xyz)
   hp%sccacc = hess_acc
   hp%name = 'numerical'
   hp%exact = .false.
   hess = 0.0_wp
   call hp%compute(env, mol, chk, calc, hess, hess_step, .false., final_err)

   deviation = maxval(abs(hess - reference))
   call check(error, deviation < 1.0e-8_wp, "provider differs from the calculator Hessian")
   if (allocated(error)) return
   call check(error, maxval(abs(hess - transpose(hess))), 0.0_wp)
   if (allocated(error)) return
   call check(error, final_err, 0.0_wp)
   if (allocated(error)) return

   ! geometry and accuracy must be restored
   call check(error, maxval(abs(mol%xyz - xyz_saved)), 0.0_wp)
   if (allocated(error)) return
   call check(error, calc%accuracy, accuracy)
   if (allocated(error)) return

end subroutine test_numerical_vs_calculator

!> The dense provider cannot honour `odlr` and must say so (and still restore
!> the geometry).
subroutine test_numerical_odlr_rejected(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_numerical_hessian_provider) :: hp
   real(wp), allocatable :: hess(:, :), xyz_saved(:, :)
   real(wp) :: final_err
   integer :: nlog

   call setup(env, mol, chk, calc)
   allocate(hess(3*nat, 3*nat), source=0.0_wp)
   allocate(xyz_saved(3, nat), source=mol%xyz)
   hp%sccacc = hess_acc

   nlog = env%nLog
   call hp%compute(env, mol, chk, calc, hess, 0.0_wp, .true., final_err)

   call check(error, landscape_log_failed(env, nlog), &
      & "the ODLR request was not reported")
   if (allocated(error)) return
   call check(error, maxval(abs(hess)), 0.0_wp, &
      & "the rejected call modified the Hessian")
   if (allocated(error)) return
   call check(error, maxval(abs(mol%xyz - xyz_saved)), 0.0_wp)

   ! a non-positive step is rejected as well
   nlog = env%nLog
   call hp%compute(env, mol, chk, calc, hess, 0.0_wp, .false., final_err)
   call check(error, landscape_log_failed(env, nlog), &
      & "a zero finite difference step was not reported")

end subroutine test_numerical_odlr_rejected

!> The model provider must return a finite, symmetric Hessian without
!> evaluating the calculator.
subroutine test_model_hessian(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_model_hessian_provider) :: hp
   real(wp), allocatable :: hess(:, :)
   real(wp) :: final_err
   integer :: nlog

   call setup(env, mol, chk, calc)
   allocate(hess(3*nat, 3*nat), source=0.0_wp)
   hp%name = 'model'

   nlog = env%nLog
   call hp%compute(env, mol, chk, calc, hess, hess_step, .false., final_err)

   call check(error, .not. landscape_log_failed(env, nlog), &
      & "the model Hessian reported an error")
   if (allocated(error)) return
   call check(error, hp%n_eval, 0, "the model Hessian evaluated the calculator")
   if (allocated(error)) return
   call check(error, final_err, 0.0_wp)
   if (allocated(error)) return
   call check(error, maxval(abs(hess)) > 0.0_wp, "the model Hessian is zero")
   if (allocated(error)) return
   call check(error, all(hess == hess), "the model Hessian is not finite")
   if (allocated(error)) return
   call check(error, maxval(abs(hess - transpose(hess))), 0.0_wp, &
      & "the model Hessian is not symmetric")

end subroutine test_model_hessian

!> A provider that refuses must make `engine%hessian` report `fail = .true.`
!> instead of returning the untouched matrix.
!>
!> The numerical provider refuses the unsupported ODLR approximation, which
!> is the cleanest available refusal path (the model provider now succeeds).
subroutine test_engine_failure_propagates(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   type(landscape_engine) :: engine
   type(landscape_engine_control) :: ctrl
   real(wp), allocatable :: hess(:, :)
   logical :: fail

   call setup(env, mol, chk, calc)
   ctrl = landscape_engine_control()
   ctrl%odlr = .true.
   call new_landscape_engine(engine, ctrl)
   call engine%set_calculator(calc)

   allocate(hess(3*nat, 3*nat), source=0.0_wp)
   call engine%hessian(env, mol, chk, hess, fail)
   call check(error, fail, "the engine did not report the provider failure")
   if (allocated(error)) return
   call check(error, maxval(abs(hess)), 0.0_wp)
   if (allocated(error)) return
   call engine%destroy()

end subroutine test_engine_failure_propagates

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

end module test_landscape_hessian
