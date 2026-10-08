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

!> Task dispatch of the xtb landscape suite.
!>
!> `landscape_run` is the single place that turns a settings object into a
!> task: it checks the preconditions that hold for every task (no periodic
!> boundary conditions, PLAN section 11), selects the `tasks/` implementation
!> through the task name of the settings type (`landscape_settings%task`) and
!> prints the one line summary that closes a landscape run.
!>
!> The task name and the concrete settings type are two views of the same
!> choice: a mismatch (e.g. task `sp` with minimisation settings) is reported
!> as an error instead of being silently accepted.
!>
!> Units: see the individual task modules; the driver itself is unit free.
module xtb_landscape_driver
   use xtb_type_environment, only : TEnvironment
   use xtb_type_molecule, only : TMolecule
   use xtb_type_restart, only : TRestart
   use xtb_type_calculator, only : TCalculator
   use xtb_landscape_settings, only : landscape_settings, landscape_opt_settings, &
      & landscape_sp_settings, landscape_scan_settings, landscape_vib_settings, &
      & landscape_ts_settings, landscape_irc_settings
   use xtb_landscape_results, only : landscape_result, landscape_irc_result
   use xtb_landscape_tasks_opt, only : landscape_optimize
   use xtb_landscape_tasks_scan, only : landscape_scan
   use xtb_landscape_tasks_vib, only : landscape_vib
   use xtb_landscape_tasks_ts, only : landscape_ts
   use xtb_landscape_tasks_irc, only : landscape_irc
   use xtb_landscape_sp, only : landscape_single_point
   implicit none(type, external)
   private

   public :: landscape_run

contains

!> Run one landscape task.
!>
!> On return `result` holds the task result; `mol%xyz` is the final geometry
!> (unchanged for the `sp` task).  Errors are reported through `env`; the
!> caller decides whether to continue (`env%checkpoint`).
subroutine landscape_run(env, mol, chk, calc, settings, result)
   character(len=*), parameter :: source = 'landscape_run'
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

   if (mol%npbc > 0) then
      call env%error("landscape tasks do not support periodic boundary "//&
         & "conditions yet", source)
      return
   end if

   select case (settings%task())
   case ('sp')
      select type (sp => settings)
      type is (landscape_sp_settings)
         call landscape_single_point(env, mol, chk, calc, sp, result)
      class default
         call env%error("the 'sp' task requires landscape_sp_settings", source)
         return
      end select
   case ('opt')
      select type (opt => settings)
      type is (landscape_opt_settings)
         call landscape_optimize(env, mol, chk, calc, opt, result)
      class default
         call env%error("the 'opt' task requires landscape_opt_settings", source)
         return
      end select
   case ('scan')
      select type (scan => settings)
      type is (landscape_scan_settings)
         call landscape_scan(env, mol, chk, calc, scan, result)
      class default
         call env%error("the 'scan' task requires landscape_scan_settings", source)
         return
      end select
   case ('vib')
      select type (vib => settings)
      type is (landscape_vib_settings)
         call landscape_vib(env, mol, chk, calc, vib, result)
      class default
         call env%error("the 'vib' task requires landscape_vib_settings", source)
         return
      end select
   case ('ts')
      select type (ts => settings)
      type is (landscape_ts_settings)
         call landscape_ts(env, mol, chk, calc, ts, result)
      class default
         call env%error("the 'ts' task requires landscape_ts_settings", source)
         return
      end select
   case ('irc')
      call run_irc_task(env, mol, chk, calc, settings, result)
   case default
      call env%error("unknown landscape task: "//settings%task(), source)
      return
   end select

   if (settings%printlevel > 0) then
      if (allocated(result%message)) then
         write(env%unit, '(1x,a,a)') "landscape task terminated: ", result%message
      else
         write(env%unit, '(1x,a)') "landscape task terminated"
      end if
   end if

end subroutine landscape_run

!> The `irc` task returns a `landscape_irc_result`, not the generic
!> `landscape_result` the driver hands to every other task.  It is dispatched
!> through a small wrapper that keeps the driver signature uniform while the
!> IRC result (two paths, arc lengths, endpoint assignment) is filled by the
!> task itself.  The generic `result` receives the transition state energy so
!> that the caller can write it back into `res`.
subroutine run_irc_task(env, mol, chk, calc, settings, result)
   character(len=*), parameter :: source = 'landscape_run'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Molecular structure
   type(TMolecule), intent(inout) :: mol
   !> Wavefunction data
   type(TRestart), intent(inout) :: chk
   !> Single point calculator
   class(TCalculator), intent(in) :: calc
   !> Task settings
   class(landscape_settings), intent(in) :: settings
   !> Task result
   type(landscape_result), intent(inout) :: result

   type(landscape_irc_result) :: irc

   select type (ircset => settings)
   type is (landscape_irc_settings)
      call landscape_irc(env, mol, chk, calc, ircset, irc)
   class default
      call env%error("the 'irc' task requires landscape_irc_settings", source)
      return
   end select

   ! The generic result carries the transition state energy (the reference of
   ! the IRC), the gradient norm and the message; the paths themselves are
   ! written by the task.  Without this write-back the caller would report the
   ! energy of the starting geometry as 0.0.
   result%energy = irc%energy_ts
   result%gnorm = irc%gnorm_ts
   result%n_imag = irc%n_imag
   result%is_saddle = irc%is_saddle
   result%etemp = irc%etemp
   result%converged = (irc%n_imag == 1)
   if (allocated(irc%message)) result%message = irc%message

end subroutine run_irc_task

end module xtb_landscape_driver
