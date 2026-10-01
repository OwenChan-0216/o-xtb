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

!> Run-time settings for the xtb landscape task suite.
!>
!> Units: all lengths are in bohr, energies in hartree, gradients (forces) in
!> hartree/bohr, Hessian matrix elements in hartree/bohr^2, masses in atomic
!> units (electron masses) and temperatures in kelvin.  Conversions to
!> angstrom / kcal/mol / amu happen exclusively at the I/O boundary through
!> `xtb_mctc_convert` or `xtb_landscape_coords`.
!>
!> The settings are plain parameter objects; there is deliberately no
!> module-level mutable state (see PLAN N14).  Every algorithm receives its
!> settings explicitly as an `intent(in)` dummy argument.
!>
!> References
!>   - Four-criterion convergence test: MAPLE `optimization/algorithm/_common.py:74-89`,
!>     cross-checked against ORCA 6.1 Table 4.1 and geomeTRIC.
!>   - Engine control defaults are copied from xtb (`src/setparam.f90:221-287`,
!>     `src/type/setvar.f90:156-158`).
module xtb_landscape_settings
   use xtb_mctc_accuracy, only : wp
   use xtb_type_environment, only : TEnvironment
   implicit none(type, external)
   private

   public :: landscape_settings, landscape_sp_settings, landscape_opt_settings
   public :: landscape_engine_control
   public :: p_landscape_opt_sd, p_landscape_opt_cg, p_landscape_opt_lbfgs
   public :: p_landscape_opt_bfgs
   public :: p_landscape_opt_diis, p_landscape_opt_rfo
   public :: p_landscape_hess_update_none, p_landscape_hess_update_bfgs
   public :: p_landscape_hess_update_sr1, p_landscape_hess_update_bofill
   public :: p_landscape_hess_update_powell
   public :: p_landscape_restart_off, p_landscape_restart_pin, p_landscape_restart_warm
   public :: landscape_opt_algorithm_name, landscape_opt_algorithm_from_name
   public :: landscape_hessian_update_name
   public :: landscape_restart_name, landscape_conv_level_known
   public :: landscape_convergence_measures, landscape_log_failed

   !> Minimisation algorithm identifiers (`landscape_opt_settings%algorithm`)
   integer, parameter :: p_landscape_opt_sd = 1
   integer, parameter :: p_landscape_opt_lbfgs = 2
   integer, parameter :: p_landscape_opt_bfgs = 3
   integer, parameter :: p_landscape_opt_diis = 4
   integer, parameter :: p_landscape_opt_rfo = 5
   integer, parameter :: p_landscape_opt_cg = 6

   !> Hessian update formula identifiers (`landscape_opt_settings%hessian_update`)
   integer, parameter :: p_landscape_hess_update_none = 0
   integer, parameter :: p_landscape_hess_update_bfgs = 1
   integer, parameter :: p_landscape_hess_update_sr1 = 2
   integer, parameter :: p_landscape_hess_update_bofill = 3
   integer, parameter :: p_landscape_hess_update_powell = 4

   !> Restart policy of the landscape engine (see `landscape_engine_control`)
   integer, parameter :: p_landscape_restart_off = 0
   integer, parameter :: p_landscape_restart_pin = 1
   integer, parameter :: p_landscape_restart_warm = 2

   !> Immutable run-time control of one landscape engine instance.
   !>
   !> `etemp`, `maxiter` and `printlevel` are forwarded verbatim to the xtb
   !> single point driver (`src/single.f90:37`).  `hess_step` and `hess_acc`
   !> default to the values xtb uses for numerical Hessians
   !> (`src/type/setvar.f90:156-158`).  The Hessian backend itself is selected
   !> by the task settings field `hessian_source` (see
   !> `xtb_landscape_hessian::new_landscape_hessian_provider`).
   type :: landscape_engine_control
      !> Electronic temperature (kelvin), 300 K is the xtb default
      real(wp) :: etemp = 300.0_wp
      !> Maximum number of SCC iterations
      integer :: maxiter = 250
      !> SCC convergence threshold
      real(wp) :: acc = 1.0_wp
      !> Print level forwarded to the single point driver
      integer :: printlevel = 0
      !> Request the analytic gradient
      logical :: lgrad = .true.
      !> Restart policy, one of `p_landscape_restart_*`
      integer :: restart_mode = p_landscape_restart_off
      !> Finite difference step of the numerical Hessian (bohr)
      real(wp) :: hess_step = 5.0e-3_wp
      !> SCC accuracy used while building the numerical Hessian
      real(wp) :: hess_acc = 0.3_wp
      !> Finite difference step of the Hessian-vector product (bohr)
      real(wp) :: hvp_step = 5.0e-3_wp
      !> Use the ODLR approximation of the numerical Hessian
      !> (`src/o1numhess.f90`); the self-built dense provider rejects it
      !> explicitly instead of silently returning the full Hessian
      logical :: odlr = .false.
   end type landscape_engine_control

   !> Common convergence thresholds shared by all landscape tasks.
   !>
   !> The four minimisation criteria are tested simultaneously (`AND`):
   !> maximum and RMS gradient component as well as maximum and RMS
   !> displacement component.  The RMS values are normalised by the number of
   !> Cartesian components (3N), not by the number of atoms.
   !>
   !> `e_tol` is an additional `AND` guard against convergence on a noisy
   !> plateau (xtb uses an energy criterion in `src/optimizer.f90:48-119`).
   type, abstract :: landscape_settings
      !> Maximum number of macro iterations
      integer :: max_steps = 256
      !> Energy change threshold (hartree)
      real(wp) :: e_tol = 5.0e-6_wp
      !> Maximum gradient component (hartree/bohr)
      real(wp) :: g_max = 3.0e-4_wp
      !> RMS gradient (hartree/bohr)
      real(wp) :: g_rms = 1.0e-4_wp
      !> Maximum displacement component (bohr)
      real(wp) :: d_max = 4.0e-3_wp
      !> RMS displacement (bohr)
      real(wp) :: d_rms = 2.0e-3_wp
      !> Print level: 0 silent, 1 one line per step, >=2 verbose
      integer :: printlevel = 1
      !> Engine control forwarded to the xtb single point driver
      type(landscape_engine_control) :: engine
      !> Hessian backend, one of `numerical` or `model`
      !> (`xtb_landscape_hessian`); unknown names are rejected by the provider
      !> factory (`src/landscape/types/hessian.f90`)
      character(len=16) :: hessian_source = 'numerical'
   contains
      !> Test the four convergence criteria plus the energy guard
      procedure :: is_converged => landscape_settings_is_converged
      !> Overwrite the thresholds from a named convergence level
      procedure :: set_conv_level => landscape_settings_set_conv_level
      !> Task name implemented by the concrete settings type
      procedure(landscape_settings_task_name), deferred :: task
   end type landscape_settings

   abstract interface
      !> Name of the task implemented by a concrete settings type
      function landscape_settings_task_name(self) result(name)
         import :: landscape_settings
         !> Settings instance
         class(landscape_settings), intent(in) :: self
         !> Lower case task name, `sp` or `opt`
         character(len=:), allocatable :: name
      end function landscape_settings_task_name
   end interface

   !> Settings of a single point (energy + optional gradient/Hessian) task
   type, extends(landscape_settings) :: landscape_sp_settings
      !> Print all gradient components exceeding `grad_threshold`
      logical :: write_gradient = .false.
      !> Gradient print threshold (hartree/bohr), 0.0 prints everything
      real(wp) :: grad_threshold = 0.0_wp
      !> Compute and report the Hessian through the engine provider
      logical :: write_hessian = .false.
   contains
      !> This type implements the single point task
      procedure :: task => landscape_sp_settings_task
   end type landscape_sp_settings

   !> Settings of a landscape geometry minimisation (`opt` task).
   !>
   !> Defaults follow the PLAN default table: `max_displ` and `trust_radius`
   !> are 0.2 angstrom, `lbfgs_memory` matches MAPLE `LBFGSParams.memory=5`,
   !> `hlow` matches the xtb ANC minimum curvature `set%optset%hlow_opt`
   !> (`src/setparam.f90:263`) and the Hessian update defaults to Bofill
   !> (Bofill, J. Comput. Chem. 15, 1 (1994)).
   type, extends(landscape_settings) :: landscape_opt_settings
      !> Algorithm selector, one of `p_landscape_opt_*`
      integer :: algorithm = p_landscape_opt_lbfgs
      !> Maximum displacement of a single macro step (bohr).  The RFO trust
      !> radius is additionally bounded by this value (`min(trust_max,
      !> max_displ)`), so a single step never exceeds it for any algorithm.
      real(wp) :: max_displ = 3.7795e-1_wp
      !> Initial trust radius of the RFO step (bohr)
      real(wp) :: trust_radius = 3.7795e-1_wp
      !> Number of L-BFGS correction pairs kept in memory
      integer :: lbfgs_memory = 5
      !> Curvature clamp of the initial inverse L-BFGS Hessian
      real(wp) :: curvature = 70.0_wp
      !> Hessian update formula, one of `p_landscape_hess_update_*`
      integer :: hessian_update = p_landscape_hess_update_bofill
      !> Curvature floor for negative eigenvalues (hartree/bohr^2)
      real(wp) :: hlow = 1.0e-2_wp
      !> Use an Armijo backtracking line search
      logical :: line_search = .true.
      !> Lower trust radius bound (bohr)
      real(wp) :: trust_min = 1.8897e-3_wp
      !> Upper trust radius bound of the RFO step (bohr); the effective upper
      !> bound is `min(trust_max, max_displ)` so that the documented
      !> single-step limit holds for every algorithm.
      real(wp) :: trust_max = 1.8897_wp
      !> Denominator guard of the RFO secular equation
      real(wp) :: evals_eps = 1.0e-10_wp
      !> Margin between the RFO shift bracket and the smallest eigenvalue
      real(wp) :: mu_margin = 1.0e-8_wp
      !> Maximum number of RFO shift bisections
      integer :: max_bisect_it = 60
      !> Recompute the exact Hessian every `recalc` RFO steps (0 disables).
      !> A default of 5 is a deliberate compromise: the numerical Hessian of a
      !> molecule with N atoms costs 6N single points, so `recalc = 1` would
      !> evaluate 6N+1 single points on **every** RFO macro step.  With the
      !> cheap `model` source a smaller value would be affordable, but the
      !> default (`numerical`) must stay tractable.
      integer :: recalc = 5
      !> Trust radius shrink factor for rejected steps
      real(wp) :: eta_shrink = 0.75_wp
      !> Trust radius expansion factor for accepted steps
      real(wp) :: eta_expand = 1.75_wp
      !> Armijo sufficient decrease constant
      real(wp) :: armijo_c1 = 1.0e-4_wp
      !> Maximum number of line search backtracks
      integer :: max_backtrack = 10
      !> Number of GDIIS snapshots kept in memory
      integer :: diis_memory = 6
      !> Store a GDIIS snapshot every N accepted steps
      integer :: diis_store_every = 5
      !> Minimum number of GDIIS snapshots before extrapolation is used
      integer :: diis_min_snapshots = 3
      !> Tikhonov regularisation of the GDIIS linear system
      real(wp) :: diis_regularization = 1.0e-10_wp
      !> Write the final geometry and the trajectory to disk
      logical :: write_files = .true.
      !> File name prefix of the output files, `xtbopt.xyz`, `xtb.trj`, ...
      character(len=64) :: output_prefix = 'xtb'
   contains
      !> This type implements the geometry minimisation task
      procedure :: task => landscape_opt_settings_task
   end type landscape_opt_settings

contains

!> Evaluate the four convergence measures of a displacement based optimisation.
!>
!> The RMS values are normalised by the number of vector components, i.e. by
!> 3N for a molecular geometry.  This is the MAPLE convention
!> (`optimization/algorithm/_common.py:74-89`).
pure subroutine landscape_convergence_measures(gradient, displ, g_max, g_rms, d_max, d_rms)
   !> Cartesian gradient (hartree/bohr), any length
   real(wp), intent(in) :: gradient(:)
   !> Cartesian displacement (bohr), any length
   real(wp), intent(in) :: displ(:)
   !> Maximum absolute gradient component (hartree/bohr)
   real(wp), intent(out) :: g_max
   !> RMS gradient (hartree/bohr)
   real(wp), intent(out) :: g_rms
   !> Maximum absolute displacement component (bohr)
   real(wp), intent(out) :: d_max
   !> RMS displacement (bohr)
   real(wp), intent(out) :: d_rms

   integer :: n

   n = size(gradient)
   if (n > 0) then
      g_max = maxval(abs(gradient))
      g_rms = sqrt(sum(gradient**2)/real(n, wp))
   else
      g_max = 0.0_wp
      g_rms = 0.0_wp
   end if

   n = size(displ)
   if (n > 0) then
      d_max = maxval(abs(displ))
      d_rms = sqrt(sum(displ**2)/real(n, wp))
   else
      d_max = 0.0_wp
      d_rms = 0.0_wp
   end if

end subroutine landscape_convergence_measures

!> Four-criterion convergence test.
!>
!> The result is true only if the maximum and RMS gradient, the maximum and
!> RMS displacement of the last step and the energy change are all below their
!> thresholds.  Equality is accepted (all comparisons use `<=`).
!>
!> A rejected step carries a zero displacement and would make both displacement
!> criteria trivially true; pass `check_displ = .false.` in that case so that
!> convergence is decided by the gradient and energy criteria alone.
pure function landscape_settings_is_converged(self, de, gradient, displ, check_displ) result(converged)
   !> Convergence thresholds
   class(landscape_settings), intent(in) :: self
   !> Energy change of the last step (hartree)
   real(wp), intent(in) :: de
   !> Cartesian gradient of the last step (hartree/bohr)
   real(wp), intent(in) :: gradient(:)
   !> Cartesian displacement of the last step (bohr)
   real(wp), intent(in) :: displ(:)
   !> Include the displacement criteria, defaults to `.true.`
   logical, intent(in), optional :: check_displ
   !> True if all requested criteria are fulfilled
   logical :: converged

   real(wp) :: g_max, g_rms, d_max, d_rms
   logical :: use_displ

   use_displ = .true.
   if (present(check_displ)) use_displ = check_displ

   call landscape_convergence_measures(gradient, displ, g_max, g_rms, d_max, d_rms)

   converged = abs(de) <= self%e_tol &
      & .and. g_max <= self%g_max &
      & .and. g_rms <= self%g_rms
   if (use_displ) then
      converged = converged &
         & .and. d_max <= self%d_max &
         & .and. d_rms <= self%d_rms
   end if

end function landscape_settings_is_converged

!> Overwrite the convergence thresholds from a named level.
!>
!> Levels follow the ORCA 6.1 naming (`superloose`, `loose`, `normal`, `tight`,
!> `vtight`); `normal` is the default.  The MAPLE aliases (`medium`,
!> `extraloose`, `extratight`) are deliberately not accepted: PLAN section
!> 5.3.1 rejects them because a one-to-one mapping to the ORCA levels would be
!> misleading.  Unknown names leave the settings untouched, the caller is
!> responsible for reporting the error.
subroutine landscape_settings_set_conv_level(self, level)
   !> Convergence thresholds to overwrite
   class(landscape_settings), intent(inout) :: self
   !> Level name
   character(len=*), intent(in) :: level

   select case (level)
   case ('superloose')
      self%g_max = 4.6e-3_wp
      self%g_rms = 3.0e-3_wp
      self%d_max = 7.9e-3_wp
      self%d_rms = 5.2e-3_wp
   case ('loose')
      self%g_max = 2.0e-3_wp
      self%g_rms = 5.0e-4_wp
      self%d_max = 1.0e-2_wp
      self%d_rms = 7.0e-3_wp
   case ('normal')
      self%g_max = 3.0e-4_wp
      self%g_rms = 1.0e-4_wp
      self%d_max = 4.0e-3_wp
      self%d_rms = 2.0e-3_wp
   case ('tight')
      self%g_max = 1.0e-4_wp
      self%g_rms = 3.0e-5_wp
      self%d_max = 1.0e-3_wp
      self%d_rms = 6.0e-4_wp
   case ('vtight')
      self%g_max = 3.0e-5_wp
      self%g_rms = 8.0e-6_wp
      self%d_max = 2.0e-4_wp
      self%d_rms = 1.0e-4_wp
   end select

end subroutine landscape_settings_set_conv_level

!> Human readable name of a minimisation algorithm identifier
pure function landscape_opt_algorithm_name(algorithm) result(name)
   !> Algorithm identifier
   integer, intent(in) :: algorithm
   !> Lower case algorithm name
   character(len=:), allocatable :: name

   select case (algorithm)
   case (p_landscape_opt_sd)
      name = 'sd'
   case (p_landscape_opt_cg)
      name = 'cg'
   case (p_landscape_opt_lbfgs)
      name = 'lbfgs'
   case (p_landscape_opt_bfgs)
      name = 'bfgs'
   case (p_landscape_opt_diis)
      name = 'diis'
   case (p_landscape_opt_rfo)
      name = 'rfo'
   case default
      name = 'unknown'
   end select

end function landscape_opt_algorithm_name

!> Reverse lookup of a minimisation algorithm identifier from its name.
!>
!> Returns 0 if the name is not known, which is not a valid algorithm
!> identifier; the caller is responsible for reporting the error.
function landscape_opt_algorithm_from_name(name) result(algorithm)
   !> Lower case algorithm name
   character(len=*), intent(in) :: name
   !> Algorithm identifier, 0 for an unknown name
   integer :: algorithm

   select case (trim(name))
   case ('sd')
      algorithm = p_landscape_opt_sd
   case ('cg')
      algorithm = p_landscape_opt_cg
   case ('lbfgs')
      algorithm = p_landscape_opt_lbfgs
   case ('bfgs')
      algorithm = p_landscape_opt_bfgs
   case ('diis')
      algorithm = p_landscape_opt_diis
   case ('rfo')
      algorithm = p_landscape_opt_rfo
   case default
      algorithm = 0
   end select

end function landscape_opt_algorithm_from_name

!> Name of the task implemented by the single point settings.
function landscape_sp_settings_task(self) result(name)
   !> Settings instance
   class(landscape_sp_settings), intent(in) :: self
   !> Task name
   character(len=:), allocatable :: name

   name = 'sp'

end function landscape_sp_settings_task

!> Name of the task implemented by the minimisation settings.
function landscape_opt_settings_task(self) result(name)
   !> Settings instance
   class(landscape_opt_settings), intent(in) :: self
   !> Task name
   character(len=:), allocatable :: name

   name = 'opt'

end function landscape_opt_settings_task

!> True if `level` names one of the convergence levels understood by
!> `landscape_settings_set_conv_level`.
function landscape_conv_level_known(level) result(known)
   !> Level name
   character(len=*), intent(in) :: level
   !> True if the name sets at least one threshold
   logical :: known

   select case (trim(level))
   case ('superloose', 'loose', 'normal', 'tight', 'vtight')
      known = .true.
   case default
      known = .false.
   end select

end function landscape_conv_level_known

!> Human readable name of an engine restart policy identifier
pure function landscape_restart_name(mode) result(name)
   !> Restart policy identifier
   integer, intent(in) :: mode
   !> Lower case policy name
   character(len=:), allocatable :: name

   select case (mode)
   case (p_landscape_restart_off)
      name = 'off'
   case (p_landscape_restart_pin)
      name = 'pin'
   case (p_landscape_restart_warm)
      name = 'warm'
   case default
      name = 'unknown'
   end select

end function landscape_restart_name

!> True if the environment logged an error after message number `nlog_before`.
!>
!> `TEnvironment%check` accumulates over the whole run
!> (`terminate = any(log(:nLog)%error)`) and must not be used to probe whether a
!> single library call failed: under `--strict` an early warning would make
!> every later call look broken.  Callers record `env%nLog` before the call and
!> pass it here to inspect only the newly appended messages.
pure function landscape_log_failed(env, nlog_before) result(failed)
   !> Computational environment
   type(TEnvironment), intent(in) :: env
   !> Message count recorded before the call
   integer, intent(in) :: nlog_before
   !> True if a new error was logged by the call
   logical :: failed

   failed = .false.
   if (env%nLog > nlog_before) then
      failed = any(env%log(nlog_before + 1:env%nLog)%error)
   end if

end function landscape_log_failed

!> Human readable name of a Hessian update formula identifier
pure function landscape_hessian_update_name(update) result(name)
   !> Update formula identifier
   integer, intent(in) :: update
   !> Lower case update name
   character(len=:), allocatable :: name

   select case (update)
   case (p_landscape_hess_update_none)
      name = 'none'
   case (p_landscape_hess_update_bfgs)
      name = 'bfgs'
   case (p_landscape_hess_update_sr1)
      name = 'sr1'
   case (p_landscape_hess_update_bofill)
      name = 'bofill'
   case (p_landscape_hess_update_powell)
      name = 'powell'
   case default
      name = 'unknown'
   end select

end function landscape_hessian_update_name

end module xtb_landscape_settings
