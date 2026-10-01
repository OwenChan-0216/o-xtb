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

!> Public entry point of the xtb landscape task suite.
!>
!> `run_landscape` is the only symbol of `src/landscape/**` that
!> `src/prog/main.F90` calls: the run type (`p_run_lopt`) selects the task
!> settings, the driver dispatches to `tasks/*`, and the result is returned to
!> the caller.  Keeping the call site this narrow means the whole suite can be
!> exercised from the unit tests with an analytic potential or with a real
!> calculator, without going through the command line.
!>
!> Layer boundaries (PLAN section 4.2):
!>
!>  * `src/landscape/**` may `use` xtb private modules, xtb modules do **not**
!>    depend on the landscape suite.  The only exceptions are the integration
!>    points listed in PLAN section 12 (`src/setparam.f90`,
!>    `src/set_module.f90`, `src/prog/main.F90`).
!>  * no module level mutable state, everything is passed explicitly.
!>  * all quantities are atomic units (bohr, hartree, amu, kelvin); conversions
!>    happen at the I/O boundary only.
!>  * the algorithms are implemented from the publications cited in the module
!>    headers, no third party source code was copied (PLAN risk R-15).
module xtb_landscape
   use xtb_type_environment, only : TEnvironment
   use xtb_type_molecule, only : TMolecule
   use xtb_type_restart, only : TRestart
   use xtb_type_calculator, only : TCalculator
   use xtb_landscape_settings, only : landscape_settings
   use xtb_landscape_results, only : landscape_result
   use xtb_landscape_driver, only : landscape_run
   implicit none(type, external)
   private

   public :: run_landscape

contains

!> Run the landscape task described by `settings`.
!>
!> Thin wrapper around `landscape_run`; see the module documentation for the
!> layer contract.  `env` collects all diagnostics, so the caller can decide
!> between continuing and aborting (`call env%checkpoint(...)`).
subroutine run_landscape(env, mol, chk, calc, settings, result)
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Molecular structure, updated by the task
   type(TMolecule), intent(inout) :: mol
   !> Wavefunction data
   type(TRestart), intent(inout) :: chk
   !> Single point calculator
   class(TCalculator), intent(in) :: calc
   !> Task settings
   class(landscape_settings), intent(in) :: settings
   !> Task result
   type(landscape_result), intent(inout) :: result

   call landscape_run(env, mol, chk, calc, settings, result)

end subroutine run_landscape

end module xtb_landscape
