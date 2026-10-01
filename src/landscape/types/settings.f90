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
   use, intrinsic :: ieee_arithmetic, only : ieee_value, ieee_quiet_nan
   use xtb_mctc_accuracy, only : wp
   use xtb_type_environment, only : TEnvironment
   implicit none(type, external)
   private

   public :: landscape_settings, landscape_sp_settings, landscape_opt_settings
   public :: landscape_scan_settings, landscape_scan_coord_settings
   public :: landscape_vib_settings, landscape_ts_settings
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
   public :: landscape_missing_value, landscape_value_present
   public :: p_landscape_scan_coord_distance, p_landscape_scan_coord_angle
   public :: p_landscape_scan_coord_dihedral
   public :: landscape_scan_coord_name, landscape_scan_coord_from_name
   public :: landscape_scan_coord_natoms, landscape_scan_coord_known
   public :: landscape_scan_mode_known
   public :: p_landscape_ts_prfo, p_landscape_ts_bprfo, p_landscape_ts_dimer
   public :: landscape_ts_method_name, landscape_ts_method_from_name
   public :: landscape_ts_method_known
   public :: landscape_ts_init_mode_known
   public :: landscape_ts_ninit_known

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

   !> Scanned internal coordinate types (`landscape_scan_coord_settings%ctype`)
   integer, parameter :: p_landscape_scan_coord_distance = 1
   integer, parameter :: p_landscape_scan_coord_angle = 2
   integer, parameter :: p_landscape_scan_coord_dihedral = 3

   !> Transition state search methods (`landscape_ts_settings%method`)
   integer, parameter :: p_landscape_ts_prfo = 1
   integer, parameter :: p_landscape_ts_bprfo = 2
   integer, parameter :: p_landscape_ts_dimer = 3

   !> Immutable run-time control of one landscape engine instance.
   !>
   !> `etemp`, `maxiter` and `printlevel` are forwarded verbatim to the xtb
   !> single point driver (`src/single.f90:37`).  `etemp` and `acc` additionally
   !> have to be pushed into the calculator by the engine, because that driver
   !> drops both arguments and the calculator reads its own fields
   !> (`landscape_engine%set_calculator`, `engine_report`).  `hess_step` and
   !> `hess_acc` default to the values xtb uses for numerical Hessians
   !> (`src/type/setvar.f90:156-158`).  The Hessian backend itself is selected
   !> by the task settings field `hessian_source` (see
   !> `xtb_landscape_hessian::new_landscape_hessian_provider`).
   type :: landscape_engine_control
      !> Electronic temperature (kelvin), 300 K is the xtb default.  The value
      !> in effect during a run: it is pushed into the xTB calculator by the
      !> engine (`landscape_engine%set_calculator`), because
      !> `xtb_single::singlepoint` drops the argument and the calculator would
      !> otherwise keep the value its constructor copied from the global
      !> `set%etemp` (`src/xtb/calculator.f90:144`).
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
      !> Hessian backend, one of `numerical`, `model` or `file`
      !> (`xtb_landscape_hessian`); unknown names are rejected by the provider
      !> factory (`src/landscape/types/hessian.f90`)
      character(len=16) :: hessian_source = 'numerical'
      !> File read by `hessian_source = 'file'` (TURBOMOLE format, the layout
      !> of the `hessian` file written by `--hess` and by the `vib` task).
      !> Unused - and unallocated - for the other sources.
      character(len=:), allocatable :: hessian_file
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

   !> Definition of one scanned internal coordinate.
   !>
   !> Atom indices are **1-based** (`TMolecule%at`/`xyz` indexing); the MAPLE
   !> reference converts its 1-based input with `a-1` internally
   !> (`scan.py:83`), this suite keeps the Fortran convention throughout.
   !> Only the first `landscape_scan_coord_natoms(ctype)` entries of `atoms`
   !> are used: two for a distance, three for an angle and four for a
   !> dihedral.
   type :: landscape_scan_coord_settings
      !> Coordinate type, one of `p_landscape_scan_coord_*`
      integer :: ctype = p_landscape_scan_coord_distance
      !> 1-based atom indices, unused entries are ignored
      integer :: atoms(4) = 0
      !> Step size: bohr for a distance, radian for an angle/dihedral.
      !> The command line accepts angstrom/degree and converts at the
      !> boundary, the settings object always stores atomic units.
      real(wp) :: step = 0.0_wp
      !> Number of steps of one sweep direction
      integer :: nstep = 0
   end type landscape_scan_coord_settings

   !> Settings of a relaxed or rigid scan (`scan` task, PLAN section 5.3.5).
   !>
   !> `ndim` is restricted to 1 and 2: the 3D scan of the MAPLE reference has
   !> no practical value and is deliberately not implemented.  The scan grid is
   !> anchored at the coordinate value of the input geometry: a sweep visits
   !> `q0 + k*step` for `k = 0..nstep`, and with `bidirectional` the same values
   !> are visited again in reverse order (see
   !> `xtb_landscape_scan1d::landscape_scan1d`).
   !>
   !> `spring_expo` and `constraint_fc` are explicit parameters of the bias
   !> potential `E_bias = fc * (q - q0)^spring_expo`; they are deliberately
   !> **not** taken from the xtb globals `xtb_scanparam::fcconstr`/`springexpo`,
   !> which would make the scan result depend on hidden module state (PLAN N14).
   type, extends(landscape_settings) :: landscape_scan_settings
      !> Scan mode, `relaxed` (constraint relaxation per point) or `rigid`
      !> (pure geometry construction followed by a single point)
      character(len=16) :: mode = 'relaxed'
      !> Inner minimiser of a relaxed scan, name of a `p_landscape_opt_*`
      !> algorithm; unknown names are rejected by the task
      character(len=16) :: method = 'lbfgs'
      !> Number of scanned coordinates, 1 or 2
      integer :: ndim = 1
      !> Scanned coordinates; entry `i > ndim` is ignored
      type(landscape_scan_coord_settings) :: coord(2)
      !> Scan the grid forwards and backwards and report the hysteresis
      logical :: bidirectional = .true.
      !> Sequential semantics for `ndim = 1`; `ndim = 2` always uses the
      !> Cartesian product grid
      logical :: sequential = .true.
      !> Warm start every point from the geometry of the previous point
      !> (only the geometry is reused, the wavefunction policy stays with the
      !> engine restart mode, see `landscape_engine_control%restart_mode`)
      logical :: warm_start = .true.
      !> Exponent of the constraint bias potential
      real(wp) :: spring_expo = 2.0_wp
      !> Force constant of the constraint bias potential (hartree/bohr^2)
      real(wp) :: constraint_fc = 0.5_wp
      !> Write the scan log and the profile to disk
      logical :: write_files = .true.
      !> File name prefix of the secondary output files
      character(len=64) :: output_prefix = 'xtb'
   contains
      !> This type implements the scan task
      procedure :: task => landscape_scan_settings_task
   end type landscape_scan_settings

   !> Settings of a vibrational analysis (`vib` task, PLAN section 5.3.8).
   !>
   !> The Hessian itself is described by the inherited `hessian_source`/
   !> `hessian_file` and by the engine control (`engine%hess_step`,
   !> `engine%hess_acc`, `engine%odlr`), so the finite difference step and the
   !> SCC accuracy of the differentiation are explicit parameters and the task
   !> never reads the xtb globals `set%step_hess`/`set%accu_hess`
   !> (their `$hess` control block is silently ignored on the non-`--copy`
   !> path, `docs/_landscape-recon/07-*.md`).
   !>
   !> The thermochemical fields are the ones consumed by the existing xtb
   !> implementation (`src/setparam.f90:284-291`): they are copied into the set
   !> object by `xtb_landscape_vib_thermo` immediately before `main_freq` runs,
   !> because `print_thermo` and `thermodyn` read them from there.
   type, extends(landscape_settings) :: landscape_vib_settings
      !> Project translations and rotations out of the mass weighted Hessian
      !> before the diagonalisation (Eckart projection,
      !> `xtb_freq_project::projectHessian`)
      logical :: project_tr = .true.
      !> Linearity threshold: the smallest unit-mass moment of inertia (bohr^2)
      !> below which a molecule counts as linear and has 3n-5 instead of
      !> 3n-6 internal modes.  The default is the threshold of the existing
      !> xtb check (`xtb_axis::is_linear`, `linthr_bohr2 = 1.0e-4`), so the
      !> mode count of this task agrees with `--hess`.
      real(wp) :: linear_tol = 1.0e-4_wp
      !> Temperatures of the thermochemical table (kelvin); only the first
      !> `n_temperature` entries are used
      real(wp) :: temperature(50) = [298.15_wp, spread(0.0_wp, 1, 49)]
      !> Number of temperatures used
      integer :: n_temperature = 1
      !> Rotor cutoff of the quasi-RRHO treatment (cm^-1, xtb
      !> `set%thermo_sthr`): low frequency modes below this value are treated
      !> by the Grimme free-rotor interpolation instead of the harmonic
      !> partition function
      real(wp) :: rotor_cutoff = 50.0_wp
      !> Imaginary frequency cutoff (cm^-1, xtb `set%thermo_ithr`): a mode
      !> with a smaller magnitude is treated as a numerical artifact of the
      !> projected Hessian rather than as a saddle point
      real(wp) :: imag_cutoff = -20.0_wp
      !> Frequency scaling factor applied by the thermochemistry (xtb
      !> `set%thermo_fscal`, recommended value 1.0 for GFN2-xTB)
      real(wp) :: freq_scal = 1.0_wp
      !> Write `hessian`, `vibspectrum`, `vib_normal_modes` and `g98.out`
      logical :: write_files = .true.
   contains
      !> This type implements the frequency task
      procedure :: task => landscape_vib_settings_task
   end type landscape_vib_settings

   !> Settings of a transition state search (`ts` task, PLAN section 5.3.6 / 6.3).
   !>
   !> Both stages of M4 are implemented here: the P-RFO / B-P-RFO eigenvector
   !> following search (`method = prfo` / `bprfo`) and the dimer search of
   !> Henkelman & Jonsson (`method = dimer`).  The dimer ignores the Hessian
   !> fields and uses its own block (`delta`, `dR`, `rot_dtheta`,
   !> `rot_max_iter`, `rot_alpha`, `rot_f_rms_th`, `step0`, `step_max`,
   !> `translate_max_iter`, `n_init`, `seed`), so a single settings object
   !> describes every method; the deterministic seeding rule of PLAN N10 is
   !> documented on `seed`.  `init_mode` selects the initial mode of the
   !> eigenvector following methods, `n_init` the initial axis of the dimer.
   !>
   !> The force thresholds are the inherited four convergence criteria
   !> (`g_max`, `g_rms`, `d_max`, `d_rms`); their values were **not**
   !> re-calibrated for transition states in this round, so the question of
   !> PLAN experiment 4 (gradient noise vs. reachable force threshold) stays
   !> open and is marked `[待校准]` here.
   !>
   !> Units: `trust`, `trust_min`, `trust_max`, `hlow`-related lengths in bohr,
   !> `hlow` and `evals_eps` in hartree/bohr^2, `imag_cutoff` in cm^-1,
   !> `etemp` in kelvin, `delta`, `dR`, `step0` and `step_max` in bohr,
   !> `rot_dtheta` in rad and `rot_f_rms_th` in hartree/bohr.
   type, extends(landscape_settings) :: landscape_ts_settings
      !> Search method, one of `p_landscape_ts_*`
      integer :: method = p_landscape_ts_prfo
      !> Initial trust radius of the P-RFO step (bohr), the `--lts trust=0.1`
      !> shortcut of PLAN section 6.3
      real(wp) :: trust = 3.7795e-1_wp
      !> Lower bound of the trust radius (bohr)
      real(wp) :: trust_min = 1.8897e-3_wp
      !> Upper bound of the trust radius (bohr)
      real(wp) :: trust_max = 1.8897_wp
      !> Trust radius shrink factor after a rejected or poorly predicted step
      real(wp) :: eta_shrink = 0.75_wp
      !> Trust radius expansion factor after a well predicted step
      real(wp) :: eta_expand = 1.75_wp
      !> Curvature floor (hartree/bohr^2) applied to the downhill modes when
      !> the Hessian has more than one negative eigenvalue
      !> (`b_i -> max(b_i, hlow)`, PLAN section 6.3)
      real(wp) :: hlow = 1.0e-2_wp
      !> Relative denominator guard of the two shifts (hartree/bohr^2)
      real(wp) :: evals_eps = 1.0e-10_wp
      !> Margin between the `lambda_n` bracket and the smallest downhill
      !> eigenvalue (hartree/bohr^2)
      real(wp) :: mu_margin = 1.0e-8_wp
      !> Maximum number of bisections of the `lambda_n` secular equation
      integer :: max_bisect_it = 60
      !> Which negative mode is followed (1-based, 1 = most negative) -
      !> the `tsroot` semantics that xtb does not provide
      integer :: target_mode = 1
      !> Mode following guard: an overlap `|V^T v|` below this value
      !> reselects the transition vector and emits a warning
      real(wp) :: mode_overlap_min = 0.3_wp
      !> Fraction of the trust radius assigned to the uphill subspace by the
      !> restricted-step B-P-RFO
      real(wp) :: alpha = 0.5_wp
      !> Maximum number of restricted-step micro cycles of the B-P-RFO
      integer :: max_micro_cycles = 50
      !> Recompute the exact Hessian every `recalc` macro steps (0 disables)
      integer :: recalc = 1
      !> Hessian update formula, one of `p_landscape_hess_update_*`; Bofill is
      !> the consensus default for path/TS optimisation
      integer :: hessian_update = p_landscape_hess_update_bofill
      !> Project translations and rotations out of every Cartesian step
      logical :: remove_rigid = .true.
      !> Confirm the converged structure with a frequency analysis
      logical :: verify_ts = .true.
      !> Eckart projection of the confirmation Hessian
      logical :: project_tr = .true.
      !> Linearity threshold of the confirmation analysis (bohr^2)
      real(wp) :: linear_tol = 1.0e-4_wp
      !> Imaginary frequency cutoff of the confirmation (cm^-1)
      real(wp) :: imag_cutoff = -20.0_wp
      !> Electronic temperature (kelvin) frozen for the whole run; the task
      !> copies it into `engine%etemp` and prints the effective value read back
      !> from the calculator (M4 hard constraint 1)
      real(wp) :: etemp = 300.0_wp
      !> Initial transition vector source, `h0` (most negative Hessian mode) or
      !> `force` (largest Cartesian gradient component direction)
      character(len=16) :: init_mode = 'h0'
      !> Displacement along the lowest internal mode applied before the search
      !> when the start geometry is a **minimum** (bohr, Cartesian).
      !>
      !> P-RFO maximises along the followed mode and minimises the rest, so it
      !> can only start uphill if the followed mode has a direction to climb: on
      !> a minimum the search first has to be moved off the stationary point
      !> (MEDIUM-1 of `31-m4-review-round2.md`).  A displacement of the order of
      !> 0.1 - 0.3 `bohr*amu^0.5` along the lowest mode is the usual recipe; the
      !> mode vector of this module is a plain Cartesian (mass independent) unit
      !> vector, so the value is given as a Cartesian length in bohr.  For a
      !> mass weighted step `d_mw` the corresponding Cartesian length is
      !> `d_mw / ||M^(1/2) v||`, which for the HCN bend (`||M^(1/2) v|| = 1.07`)
      !> maps the default 0.2 bohr to 0.21 `amu^0.5*bohr`.  The escape is only
      !> attempted when there is no significantly negative curvature at all;
      !> `0` disables it.
      real(wp) :: escape_step = 2.0e-1_wp
      !> Half separation of the two dimer images (bohr), i.e. the distance of
      !> each image from the common midpoint.  This is the pysisyphus
      !> convention of PLAN section 5.3.6 (`1.8897e-2` bohr = 1e-2 Angstrom),
      !> not the VASP one where `DdR` denotes twice that value.  The
      !> `[待校准]` marker is retired: report 28 section 6.4 measured that
      !> `delta x 8` changes the dimer curvature by 0.0013 % and the analytic
      !> Mueller-Brown check pins the value to 0.07 %, so the convention only
      !> has to be the documented one.
      real(wp) :: delta = 1.8897e-2_wp
      !> Finite difference step of the force along the translation direction
      !> (bohr), the `dR = 1e-3` Angstrom of Henkelman & Jonsson
      real(wp) :: dR = 1.8897e-3_wp
      !> Finite difference angle of the dimer rotation (rad), the
      !> `delta theta = 1e-4` rad of Henkelman & Jonsson
      real(wp) :: rot_dtheta = 1.0e-4_wp
      !> Damping factor applied to the rotation angle of Eq. 13 (1 = the full
      !> angle of the two term Fourier model)
      real(wp) :: rot_alpha = 0.5_wp
      !> Maximum number of dimer rotations per macro iteration
      integer :: rot_max_iter = 5
      !> RMS of the perpendicular force difference below which the dimer axis
      !> is considered aligned with the lowest curvature mode (hartree/bohr);
      !> exhausting `rot_max_iter` without reaching it emits the VASP
      !> diagnostic warning (PLAN section 6.3)
      real(wp) :: rot_f_rms_th = 2.65e-4_wp
      !> Upper bound of the first dimer translation (bohr): together with
      !> `step_max` it fixes the mobility of the quick-min propagation
      !> (`--lts` dimer), `tau = min(step0, step_max)/|F^dagger|`.  The actual
      !> first displacement can be shorter because the `dR` curvature probe
      !> limits the mobility to `1/|kappa|` (measured on GFN2 HCN: 0.1032 bohr
      !> instead of `min(step0, step_max) = 0.28346`)
      real(wp) :: step0 = 3.7795e-1_wp
      !> Upper bound of every dimer translation step (bohr)
      real(wp) :: step_max = 2.8346e-1_wp
      !> Maximum number of quick-min displacement updates per dimer
      !> translation (1 = the single translation per macro iteration of
      !> Henkelman & Jonsson)
      integer :: translate_max_iter = 1
      !> Source of the initial dimer axis, either `random` (uniform random
      !> direction, reproducible through `seed`) or `force` (the largest
      !> Cartesian gradient component direction, a deterministic substitute)
      character(len=16) :: n_init = 'random'
      !> Seed of the dimer initial axis (`random_seed`), the only place in the
      !> suite where a random number is allowed (PLAN N10); the generator
      !> state is set from this seed before every draw, so a run is exactly
      !> reproducible
      integer :: seed = 42
      !> Write `xtbts.xyz` and `xtbts.log`
      logical :: write_files = .true.
      !> File name prefix of the two output files; the default `xtb` yields
      !> `<prefix>ts.xyz` = `xtbts.xyz`, the same scheme as `<prefix>opt.xyz`
      character(len=64) :: output_prefix = 'xtb'
   contains
      !> This type implements the transition state search task
      procedure :: task => landscape_ts_settings_task
   end type landscape_ts_settings

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

!> Name of the task implemented by the scan settings.
function landscape_scan_settings_task(self) result(name)
   !> Settings instance
   class(landscape_scan_settings), intent(in) :: self
   !> Task name
   character(len=:), allocatable :: name

   name = 'scan'

end function landscape_scan_settings_task

!> Task name of the vibrational analysis
function landscape_vib_settings_task(self) result(name)
   !> Settings instance
   class(landscape_vib_settings), intent(in) :: self
   !> Task name
   character(len=:), allocatable :: name

   name = 'vib'

end function landscape_vib_settings_task

!> Task name of the transition state search
function landscape_ts_settings_task(self) result(name)
   !> Settings instance
   class(landscape_ts_settings), intent(in) :: self
   !> Task name
   character(len=:), allocatable :: name

   name = 'ts'

end function landscape_ts_settings_task

!> Human readable name of a transition state search method identifier
pure function landscape_ts_method_name(method) result(name)
   !> Method identifier
   integer, intent(in) :: method
   !> Lower case method name
   character(len=:), allocatable :: name

   select case (method)
   case (p_landscape_ts_prfo)
      name = 'prfo'
   case (p_landscape_ts_bprfo)
      name = 'bprfo'
   case (p_landscape_ts_dimer)
      name = 'dimer'
   case default
      name = 'unknown'
   end select

end function landscape_ts_method_name

!> Reverse lookup of a transition state search method from its name.
!>
!> Returns 0 for an unknown name, which is not a valid method identifier; the
!> caller is responsible for reporting the error.
function landscape_ts_method_from_name(name) result(method)
   !> Lower case method name
   character(len=*), intent(in) :: name
   !> Method identifier, 0 for an unknown name
   integer :: method

   select case (trim(name))
   case ('prfo')
      method = p_landscape_ts_prfo
   case ('bprfo')
      method = p_landscape_ts_bprfo
   case ('dimer')
      method = p_landscape_ts_dimer
   case default
      method = 0
   end select

end function landscape_ts_method_from_name

!> True if `name` names one of the supported transition state methods.
function landscape_ts_method_known(name) result(known)
   !> Method name
   character(len=*), intent(in) :: name
   !> True if the name resolves to a method identifier
   logical :: known

   known = landscape_ts_method_from_name(name) /= 0

end function landscape_ts_method_known

!> True if `name` names a supported initial transition vector source.
function landscape_ts_init_mode_known(name) result(known)
   !> Init mode name
   character(len=*), intent(in) :: name
   !> True if the name is supported
   logical :: known

   select case (trim(name))
   case ('h0', 'force')
      known = .true.
   case default
      known = .false.
   end select

end function landscape_ts_init_mode_known

!> True if `name` names a supported dimer initial axis source.
function landscape_ts_ninit_known(name) result(known)
   !> Initial axis name
   character(len=*), intent(in) :: name
   !> True if the name is supported
   logical :: known

   select case (trim(name))
   case ('random', 'force')
      known = .true.
   case default
      known = .false.
   end select

end function landscape_ts_ninit_known

!> Name of an internal coordinate type identifier.
pure function landscape_scan_coord_name(ctype) result(name)
   !> Coordinate type identifier
   integer, intent(in) :: ctype
   !> Lower case coordinate name
   character(len=:), allocatable :: name

   select case (ctype)
   case (p_landscape_scan_coord_distance)
      name = 'distance'
   case (p_landscape_scan_coord_angle)
      name = 'angle'
   case (p_landscape_scan_coord_dihedral)
      name = 'dihedral'
   case default
      name = 'unknown'
   end select

end function landscape_scan_coord_name

!> Internal coordinate type identifier from its name.
!>
!> Returns 0 for an unknown name, which is not a valid coordinate type; the
!> caller is responsible for reporting the error.
pure function landscape_scan_coord_from_name(name) result(ctype)
   !> Lower case coordinate name
   character(len=*), intent(in) :: name
   !> Coordinate type identifier, 0 for an unknown name
   integer :: ctype

   select case (trim(name))
   case ('distance')
      ctype = p_landscape_scan_coord_distance
   case ('angle')
      ctype = p_landscape_scan_coord_angle
   case ('dihedral')
      ctype = p_landscape_scan_coord_dihedral
   case default
      ctype = 0
   end select

end function landscape_scan_coord_from_name

!> Number of atoms that define an internal coordinate (2/3/4), 0 if unknown.
pure function landscape_scan_coord_natoms(ctype) result(natoms)
   !> Coordinate type identifier
   integer, intent(in) :: ctype
   !> Number of defining atoms
   integer :: natoms

   select case (ctype)
   case (p_landscape_scan_coord_distance)
      natoms = 2
   case (p_landscape_scan_coord_angle)
      natoms = 3
   case (p_landscape_scan_coord_dihedral)
      natoms = 4
   case default
      natoms = 0
   end select

end function landscape_scan_coord_natoms

!> True if `ctype` names one of the supported internal coordinates.
pure function landscape_scan_coord_known(ctype) result(known)
   !> Coordinate type identifier
   integer, intent(in) :: ctype
   !> True if the type is supported
   logical :: known

   known = landscape_scan_coord_natoms(ctype) > 0

end function landscape_scan_coord_known

!> True if `mode` names one of the scan modes.
!>
!> The check is duplicated in `xtb_landscape_scan_relax::landscape_scan_check`
!> for the library entry point; keeping the predicate here makes it usable
!> from the command line parser without pulling in the scan kernel.
pure function landscape_scan_mode_known(mode) result(known)
   !> Scan mode name
   character(len=*), intent(in) :: mode
   !> True if the mode is supported
   logical :: known

   select case (trim(mode))
   case ('relaxed', 'rigid')
      known = .true.
   case default
      known = .false.
   end select

end function landscape_scan_mode_known

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

!> Value reported for a quantity that does not exist.
!>
!> A quantity is missing - never zero - when the evaluation that would produce
!> it was discarded: an unconverged SCC yields neither energy nor gradient, and
!> a scan point built on it has no energy.  Writing `0.0` for such a point
!> fabricates a perfectly plausible energy (a scan reading `0.0` at one grid
!> point while its neighbours are at `-5 Eh` is silently broken, see
!> `docs/_landscape-recon/14-m2-validation-experiments.md` section 5.3), so the
!> suite reports a quiet NaN instead and callers have to test for it.
!>
!> The IEEE intrinsic is used instead of a `0/0` division so that the function
!> is safe in debug builds, where `-ffpe-trap=invalid` is active
!> (`cmake/CMakeLists.txt:51`).
pure function landscape_missing_value() result(value)
   !> NaN
   real(wp) :: value

   value = ieee_value(0.0_wp, ieee_quiet_nan)

end function landscape_missing_value

!> True if a real value is present, i.e. neither NaN nor +/- Inf.
!>
!> `NaN <= huge` and `Inf <= huge` are both false, so one comparison rejects
!> every non-finite value.  Elemental, so it also tests a whole array.
elemental function landscape_value_present(value) result(present)
   !> Value to test
   real(wp), intent(in) :: value
   !> True if the value is finite
   logical :: present

   present = abs(value) <= huge(1.0_wp)

end function landscape_value_present

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
