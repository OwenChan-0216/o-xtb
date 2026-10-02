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

!> Result containers of the xtb landscape task suite.
!>
!> Units: energies in hartree, gradient norms in hartree/bohr and
!> displacements in bohr.  All arrays use 1-based Fortran indexing and flat
!> Cartesian vectors are ordered `x1, y1, z1, x2, ...`, matching the
!> `reshape(..., [3, nat])` convention of `TMolecule%xyz`.
module xtb_landscape_results
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_convert, only : autokcal
   implicit none(type, external)
   private

   public :: landscape_vib_result
   public :: landscape_irc_result
   public :: landscape_step, landscape_result, landscape_convergence_report
   public :: landscape_result_add_step, landscape_report_add, landscape_result_trim
   public :: landscape_print_step, landscape_result_write, landscape_report_write
   public :: landscape_irc_result_write
   public :: p_landscape_bound_trust, p_landscape_bound_step_max
   public :: p_landscape_irc_term_error, p_landscape_irc_term_max_steps
   public :: p_landscape_irc_term_grad, p_landscape_irc_term_energy_rise
   public :: landscape_irc_term_name

   !> Termination signal of an IRC integration: an error (no path was built).
   integer, parameter :: p_landscape_irc_term_error = 0
   !> Termination signal (a) of PLAN section 6.5: the step budget is exhausted.
   integer, parameter :: p_landscape_irc_term_max_steps = 1
   !> Termination signal (b): `|g|` fell below the threshold (a stationary
   !> point was reached).
   integer, parameter :: p_landscape_irc_term_grad = 2
   !> Termination signal (c): the energy rose over `e_rise_steps` consecutive
   !> points (the path passed the minimum and is climbing again).
   integer, parameter :: p_landscape_irc_term_energy_rise = 3

   !> Result of a vibrational analysis (`vib` task, PLAN section 5.4).
   !>
   !> The frequency layout follows the existing xtb frequency output exactly
   !> (`numhess` in `src/hessian.F90`): the array holds **all** 3n modes, the
   !> first `n_zero` of which are the projected translations and rotations and
   !> are set to exactly zero, followed by the `n_vib` internal modes in
   !> ascending order.  Imaginary modes are negative, so `freq(1)` is the
   !> lowest frequency and a negative `freq(n)` is the highest imaginary one.
   type :: landscape_vib_result
      !> Frequencies (cm^-1), imaginary modes negative
      real(wp), allocatable :: freq(:)
      !> Mass weighted normal modes (columns, same order as `freq`)
      real(wp), allocatable :: modes(:, :)
      !> Reduced masses of the modes (amu, xtb `freq_results%rmass`)
      real(wp), allocatable :: rmass(:)
      !> Number of projected translation/rotation modes: 6, or 5 for a linear
      !> molecule, or 3 for a single atom (all its modes are translations)
      integer :: n_zero = 0
      !> Number of internal vibrational modes, 3n-6 (3n-5 if linear, 0 for a
      !> single atom)
      integer :: n_vib = 0
      !> Number of imaginary internal modes, counted against `imag_cutoff`
      integer :: n_imag = 0
      !> True if the geometry was detected as linear (`linear_tol`)
      logical :: linear = .false.
      !> Zero point energy (hartree) as reported by the thermochemistry
      !> wrapper (`print_thermo`), zero until that wrapper has run
      real(wp) :: zpe = 0.0_wp
   end type landscape_vib_result

   !> Result of an intrinsic reaction coordinate integration (`irc` task,
   !> PLAN section 5.4).
   !>
   !> One path point is a geometry `(3, n)` (bohr) together with its energy
   !> (hartree), the mass weighted arc length from the transition state
   !> (bohr*amu^1/2) and the cost of the point (number of energy/gradient
   !> evaluations the integrator spent on it).  The transition state itself is
   !> the common first point of both directions and is not duplicated in the
   !> arrays: `xyz_fwd(:,:,1)` is the first point **after** the transition
   !> state (half a step away), the same for `xyz_bwd`.
   type :: landscape_irc_result
      !> Integration method, one of the `p_landscape_irc_*` identifiers
      integer :: method = 0
      !> Number of recorded points of the forward direction
      integer :: n_fwd = 0
      !> Number of recorded points of the backward direction
      integer :: n_bwd = 0
      !> Forward geometries `(3, nat, n_fwd)` (bohr)
      real(wp), allocatable :: xyz_fwd(:, :, :)
      !> Backward geometries `(3, nat, n_bwd)` (bohr)
      real(wp), allocatable :: xyz_bwd(:, :, :)
      !> Forward energies (hartree)
      real(wp), allocatable :: e_fwd(:)
      !> Backward energies (hartree)
      real(wp), allocatable :: e_bwd(:)
      !> Forward arc lengths from the transition state (bohr*amu^1/2)
      real(wp), allocatable :: s_fwd(:)
      !> Backward arc lengths from the transition state (bohr*amu^1/2)
      real(wp), allocatable :: s_bwd(:)
      !> Forward gradient norms (hartree/bohr, Euclidean Cartesian norm)
      real(wp), allocatable :: gnorm_fwd(:)
      !> Backward gradient norms (hartree/bohr)
      real(wp), allocatable :: gnorm_bwd(:)
      !> Energy/gradient evaluations spent on each forward point
      integer, allocatable :: n_eval_fwd(:)
      !> Energy/gradient evaluations spent on each backward point
      integer, allocatable :: n_eval_bwd(:)
      !> Termination signal of the forward direction, one of the
      !> `p_landscape_irc_term_*` identifiers
      integer :: term_fwd = p_landscape_irc_term_error
      !> Termination signal of the backward direction
      integer :: term_bwd = p_landscape_irc_term_error
      !> True if the forward endpoint reached a minimum: termination by (b) or
      !> (c), a converged endpoint relaxation and an aligned RMSD below
      !> `rmsd_end`
      logical :: reached_min_fwd = .false.
      !> True if the backward endpoint reached a minimum
      logical :: reached_min_bwd = .false.
      !> Kabsch aligned RMSD between the forward endpoint and its relaxed
      !> minimum (bohr); the endpoint is rigid-body aligned to the minimum
      !> with the mass free Kabsch rotation before the distance is taken
      real(wp) :: rmsd_to_min_fwd = 0.0_wp
      !> Kabsch aligned RMSD between the backward endpoint and its relaxed
      !> minimum (bohr)
      real(wp) :: rmsd_to_min_bwd = 0.0_wp
      !> Energy of the relaxed forward minimum (hartree); zero when the
      !> endpoint relaxation was not requested
      real(wp) :: e_min_fwd = 0.0_wp
      !> Energy of the relaxed backward minimum (hartree)
      real(wp) :: e_min_bwd = 0.0_wp
      !> Macro steps of the forward endpoint relaxation (`--lirc-level` sets
      !> its thresholds)
      integer :: n_relax_fwd = 0
      !> Macro steps of the backward endpoint relaxation
      integer :: n_relax_bwd = 0
      !> Number of forward points whose Gonzalez-Schlegel sphere relaxation was
      !> stopped by the micro cycle budget instead of its own convergence
      !> criterion.  Measured: on a GFN2 path this is every GS point (16.9 /
      !> 20.3 E/g per point instead of the 3-5 of PLAN section 6.5); the
      !> predictor-corrector methods report 0
      integer :: n_pinned_fwd = 0
      !> Number of backward points whose sphere relaxation was pinned
      integer :: n_pinned_bwd = 0
      !> Energy of the transition state (hartree)
      real(wp) :: energy_ts = 0.0_wp
      !> Gradient norm at the transition state (hartree/bohr)
      real(wp) :: gnorm_ts = 0.0_wp
      !> Frozen electronic temperature read back from the calculator (kelvin)
      real(wp) :: etemp = 0.0_wp
      !> Arc length of one macro step (bohr*amu^1/2)
      real(wp) :: step_length = 0.0_wp
      !> Number of imaginary modes of the transition state confirmation
      integer :: n_imag = -1
      !> Component index (flat, 1-based) of the largest absolute component of
      !> the mass weighted transition vector after the phase convention
      integer :: phase_index = 0
      !> Value of that component (bohr*amu^1/2, unit mass weighted vector)
      real(wp) :: phase_value = 0.0_wp
      !> True if `--lirc-swap` exchanged the two directions
      logical :: swapped = .false.
      !> True if exactly one imaginary mode was found, i.e. the input really is
      !> a first order saddle point
      logical :: is_saddle = .false.
      !> Human readable termination message
      character(len=:), allocatable :: message
   contains
      !> Print a summary of the integration
      procedure :: write_log => landscape_irc_result_write
   end type landscape_irc_result

   !> Semantics of `landscape_step%trust_radius`: a genuine trust radius
   !> (the minimisers, P-RFO and B-P-RFO).
   integer, parameter :: p_landscape_bound_trust = 0
   !> Semantics of `landscape_step%trust_radius`: the dimer has no trust
   !> radius, so the recorded value is the upper bound `step_max` of its
   !> translation.
   integer, parameter :: p_landscape_bound_step_max = 1

   !> Bookkeeping of a single macro step of an optimisation.
   type :: landscape_step
      !> Macro iteration index (1-based)
      integer :: istep = 0
      !> Total energy after the step (hartree)
      real(wp) :: energy = 0.0_wp
      !> Energy change of the step (hartree)
      real(wp) :: delta_e = 0.0_wp
      !> Euclidean norm of the gradient (hartree/bohr)
      real(wp) :: gnorm = 0.0_wp
      !> Maximum absolute gradient component (hartree/bohr)
      real(wp) :: gmax = 0.0_wp
      !> Euclidean norm of the displacement (bohr)
      real(wp) :: dispnorm = 0.0_wp
      !> Maximum absolute displacement component (bohr)
      real(wp) :: disp_max = 0.0_wp
      !> Bound active in this step (bohr): the trust radius for the trust
      !> region methods, the translation bound `step_max` for the dimer.  The
      !> meaning is given by `bound_kind`.
      real(wp) :: trust_radius = 0.0_wp
      !> What `trust_radius` means, one of `p_landscape_bound_*`
      integer :: bound_kind = p_landscape_bound_trust
      !> Algorithm that actually produced this step, one of the
      !> `p_landscape_opt_*` identifiers.  A value of `p_landscape_opt_sd`
      !> in a run of another algorithm means the configured direction was
      !> replaced by steepest descent (see `landscape_step%fallback`).
      integer :: method = 0
      !> True if a steepest descent fallback was entered in this step instead
      !> of (or after) the configured algorithm (PLAN section 5.4
      !> `history_method`).  The recorded displacement is zero if the fallback
      !> was itself rejected.
      logical :: fallback = .false.
   end type landscape_step

   !> Convergence history of an optimisation (can be written to a log file).
   type :: landscape_convergence_report
      !> Number of recorded iterations
      integer :: n_iter = 0
      !> Status of the four criteria: gradient max, gradient rms,
      !> displacement max, displacement rms
      logical :: converged(4) = .false.
      !> Energy per iteration (hartree)
      real(wp), allocatable :: history_energy(:)
      !> Gradient norm per iteration (hartree/bohr)
      real(wp), allocatable :: history_gnorm(:)
      !> Maximum gradient component per iteration (hartree/bohr)
      real(wp), allocatable :: history_gmax(:)
      !> Displacement norm per iteration (bohr)
      real(wp), allocatable :: history_dispnorm(:)
      !> Maximum displacement component per iteration (bohr)
      real(wp), allocatable :: history_dispmax(:)
      !> Trust radius per iteration (bohr)
      real(wp), allocatable :: history_trust(:)
      !> Algorithm actually used per iteration, one of the
      !> `p_landscape_opt_*` identifiers (`p_landscape_opt_sd` marks a
      !> steepest descent fallback)
      integer, allocatable :: history_method(:)
   contains
      !> Print the convergence history
      procedure :: write_log => landscape_report_write
   end type landscape_convergence_report

   !> Result of a landscape minimisation.
   type :: landscape_result
      !> True if the four convergence criteria were fulfilled
      logical :: converged = .false.
      !> Number of macro steps performed
      integer :: n_steps = 0
      !> Final total energy (hartree)
      real(wp) :: energy = 0.0_wp
      !> Norm of the final gradient (hartree/bohr)
      real(wp) :: gnorm = 0.0_wp
      !> Maximum absolute value of the final gradient (hartree/bohr)
      real(wp) :: gmax = 0.0_wp
      !> Number of objective evaluations, including cache hits
      integer :: n_eval = 0
      !> Number of energy/gradient evaluations that missed the engine cache
      integer :: n_cache_miss = 0
      !> Number of macro steps in which the configured algorithm degraded to a
      !> steepest descent fallback whose step was accepted.  A non-zero value
      !> for `lbfgs`, `bfgs`, `cg` or `rfo` proves that the quasi-Newton /
      !> rational step was replaced and the run did not use the configured
      !> method throughout.
      integer :: n_fallback = 0
      !> Number of imaginary modes of the saddle point confirmation (-1 if
      !> the confirmation was not performed, e.g. for the minimisation tasks)
      integer :: n_imag = -1
      !> Most negative (imaginary) frequency of the confirmation (cm^-1)
      real(wp) :: imag_freq = 0.0_wp
      !> True if the confirmation found exactly one imaginary mode, i.e. the
      !> located stationary point really is a first order saddle point.  A
      !> converged search that ended on a minimum or a higher order saddle has
      !> `is_saddle = .false.` and is reported as a failure by the task.
      logical :: is_saddle = .false.
      !> Effective electronic temperature of the run (kelvin, read back from
      !> the calculator); zero when the task does not touch the engine
      real(wp) :: etemp = 0.0_wp
      !> Human readable termination message
      character(len=:), allocatable :: message
      !> Recorded macro steps
      type(landscape_step), allocatable :: steps(:)
      !> Convergence history
      type(landscape_convergence_report) :: conv
   contains
      !> Print a summary of the optimisation
      procedure :: write_log => landscape_result_write
   end type landscape_result

contains

!> Append one macro step to the result, growing the storage geometrically.
subroutine landscape_result_add_step(self, step)
   !> Result to extend
   class(landscape_result), intent(inout) :: self
   !> Step to append
   type(landscape_step), intent(in) :: step

   type(landscape_step), allocatable :: buffer(:)
   integer :: capacity

   if (.not. allocated(self%steps)) then
      allocate(self%steps(32))
   else if (self%n_steps >= size(self%steps)) then
      capacity = max(2*size(self%steps), self%n_steps + 1)
      allocate(buffer(capacity), source=self%steps)
      call move_alloc(buffer, self%steps)
   end if
   self%n_steps = self%n_steps + 1
   self%steps(self%n_steps) = step

end subroutine landscape_result_add_step

!> Shrink the storage of a result to the number of recorded steps.
subroutine landscape_result_trim(self)
   !> Result to shrink
   class(landscape_result), intent(inout) :: self

   type(landscape_step), allocatable :: steps(:)
   real(wp), allocatable :: buffer(:)
   integer, allocatable :: ibuffer(:)

   if (allocated(self%steps)) then
      if (size(self%steps) /= self%n_steps) then
         allocate(steps(self%n_steps), source=self%steps(:self%n_steps))
         call move_alloc(steps, self%steps)
      end if
   end if
   if (allocated(self%conv%history_energy)) then
      if (size(self%conv%history_energy) /= self%conv%n_iter) then
         allocate(buffer(self%conv%n_iter), source=self%conv%history_energy(:self%conv%n_iter))
         call move_alloc(buffer, self%conv%history_energy)
      end if
   end if
   if (allocated(self%conv%history_gnorm)) then
      if (size(self%conv%history_gnorm) /= self%conv%n_iter) then
         allocate(buffer(self%conv%n_iter), source=self%conv%history_gnorm(:self%conv%n_iter))
         call move_alloc(buffer, self%conv%history_gnorm)
      end if
   end if
   if (allocated(self%conv%history_gmax)) then
      if (size(self%conv%history_gmax) /= self%conv%n_iter) then
         allocate(buffer(self%conv%n_iter), source=self%conv%history_gmax(:self%conv%n_iter))
         call move_alloc(buffer, self%conv%history_gmax)
      end if
   end if
   if (allocated(self%conv%history_dispnorm)) then
      if (size(self%conv%history_dispnorm) /= self%conv%n_iter) then
         allocate(buffer(self%conv%n_iter), source=self%conv%history_dispnorm(:self%conv%n_iter))
         call move_alloc(buffer, self%conv%history_dispnorm)
      end if
   end if
   if (allocated(self%conv%history_dispmax)) then
      if (size(self%conv%history_dispmax) /= self%conv%n_iter) then
         allocate(buffer(self%conv%n_iter), source=self%conv%history_dispmax(:self%conv%n_iter))
         call move_alloc(buffer, self%conv%history_dispmax)
      end if
   end if
   if (allocated(self%conv%history_trust)) then
      if (size(self%conv%history_trust) /= self%conv%n_iter) then
         allocate(buffer(self%conv%n_iter), source=self%conv%history_trust(:self%conv%n_iter))
         call move_alloc(buffer, self%conv%history_trust)
      end if
   end if
   if (allocated(self%conv%history_method)) then
      if (size(self%conv%history_method) /= self%conv%n_iter) then
         allocate(ibuffer(self%conv%n_iter), &
            & source=self%conv%history_method(:self%conv%n_iter))
         call move_alloc(ibuffer, self%conv%history_method)
      end if
   end if

end subroutine landscape_result_trim

!> Append one iteration to the convergence history, growing the storage
!> geometrically.
subroutine landscape_report_add(self, step)
   !> Convergence report to extend
   class(landscape_convergence_report), intent(inout) :: self
   !> Step providing the new history entry
   type(landscape_step), intent(in) :: step

   integer :: n

   n = self%n_iter + 1
   call append_real(self%history_energy, n, step%energy)
   call append_real(self%history_gnorm, n, step%gnorm)
   call append_real(self%history_gmax, n, step%gmax)
   call append_real(self%history_dispnorm, n, step%dispnorm)
   call append_real(self%history_dispmax, n, step%disp_max)
   call append_real(self%history_trust, n, step%trust_radius)
   call append_int(self%history_method, n, step%method)
   self%n_iter = n

end subroutine landscape_report_add

!> Store a value at position `n` of a geometrically growing vector.
subroutine append_real(vector, n, value)
   !> Growing buffer
   real(wp), allocatable, intent(inout) :: vector(:)
   !> 1-based index of the new value
   integer, intent(in) :: n
   !> Value to store
   real(wp), intent(in) :: value

   real(wp), allocatable :: buffer(:)
   integer :: capacity

   if (.not. allocated(vector)) allocate(vector(32))
   if (n > size(vector)) then
      capacity = max(2*size(vector), n)
      allocate(buffer(capacity), source=vector)
      call move_alloc(buffer, vector)
   end if
   vector(n) = value

end subroutine append_real

!> Store an integer at position `n` of a geometrically growing vector.
subroutine append_int(vector, n, value)
   !> Growing buffer
   integer, allocatable, intent(inout) :: vector(:)
   !> 1-based index of the new value
   integer, intent(in) :: n
   !> Value to store
   integer, intent(in) :: value

   integer, allocatable :: buffer(:)
   integer :: capacity

   if (.not. allocated(vector)) allocate(vector(32), source=0)
   if (n > size(vector)) then
      capacity = max(2*size(vector), n)
      allocate(buffer(capacity), source=vector)
      call move_alloc(buffer, vector)
   end if
   vector(n) = value

end subroutine append_int

!> Print one optimisation step in the compact table style used by the
!> landscape drivers.
!>
!> A header with the column units is printed before the first step.  All
!> columns are in atomic units except the energy change, which is converted to
!> kcal/mol (`autokcal`) for readability.
subroutine landscape_print_step(step, unit)
   !> Step to print
   type(landscape_step), intent(in) :: step
   !> Output unit
   integer, intent(in) :: unit

   character(len=:), allocatable :: bound_label

   if (step%istep <= 1) then
      ! The last column is the active bound: a trust radius for the trust
      ! region methods, the translation ceiling `step_max` for the dimer (which
      ! has no trust radius).  The label makes that distinction visible instead
      ! of reporting `step_max` under a `trust/bohr` header.
      bound_label = "trust/bohr"
      if (step%bound_kind == p_landscape_bound_step_max) bound_label = "stepmax/bohr"
      write(unit, '(1x,a)') "   iter            energy/Eh        dE/(kcal/mol) "//&
         & "  gmax/(Eh/bohr)  dmax/bohr     "//bound_label
   end if
   write(unit, '(1x,i6,1x,f20.12,1x,f12.4,1x,es13.6,1x,es13.6,1x,es13.6)') &
      & step%istep, step%energy, step%delta_e*autokcal, step%gmax, &
      & step%disp_max, step%trust_radius

end subroutine landscape_print_step

!> Print a summary of a landscape minimisation.
subroutine landscape_result_write(self, unit)
   !> Result to print
   class(landscape_result), intent(in) :: self
   !> Output unit
   integer, intent(in) :: unit

   write(unit, '(1x,a)') repeat('-', 62)
   if (allocated(self%message)) then
      write(unit, '(1x,a)') "landscape: "//self%message
   end if
   write(unit, '(1x,a,l1)') "converged:      ", self%converged
   write(unit, '(1x,a,i0)') "steps:          ", self%n_steps
   write(unit, '(1x,a,i0)') "energy calls:   ", self%n_eval
   write(unit, '(1x,a,i0)') "cache misses:   ", self%n_cache_miss
   write(unit, '(1x,a,f20.12,a)') "final energy:   ", self%energy, " Eh"
   write(unit, '(1x,a,es15.6,a)') "final gradient: ", self%gnorm, " Eh/bohr"
   write(unit, '(1x,a,es15.6,a)') "max gradient:   ", self%gmax, " Eh/bohr"
   ! M4 hard constraint 1: the effective (read back) electronic temperature is
   ! part of the result object, not only of the printed engine report.  It is
   ! zero for the tasks that never touched an xTB calculator.
   if (self%etemp > 0.0_wp) then
      write(unit, '(1x,a,f12.3,a)') "etemp:          ", self%etemp, " K"
   end if
   write(unit, '(1x,a)') repeat('-', 62)

end subroutine landscape_result_write

!> Print the convergence history of a minimisation.
subroutine landscape_report_write(self, unit)
   !> Convergence report to print
   class(landscape_convergence_report), intent(in) :: self
   !> Output unit
   integer, intent(in) :: unit

   integer :: i

   write(unit, '(1x,a)') "convergence history"
   write(unit, '(1x,a,4(1x,l1))') "criteria (gmax,grms,dmax,drms): ", self%converged
   if (.not. allocated(self%history_energy)) return
   write(unit, '(1x,a)') "   iter        energy            gnorm          trust"
   do i = 1, size(self%history_energy)
      write(unit, '(1x,i6,1x,f20.12,1x,es15.6,1x,es15.6)') &
         & i, self%history_energy(i), self%history_gnorm(i), self%history_trust(i)
   end do

end subroutine landscape_report_write

!> Human readable name of an IRC termination signal identifier.
pure function landscape_irc_term_name(term) result(name)
   !> Termination signal identifier
   integer, intent(in) :: term
   !> Lower case signal name
   character(len=:), allocatable :: name

   select case (term)
   case (p_landscape_irc_term_max_steps)
      name = 'max_steps'
   case (p_landscape_irc_term_grad)
      name = 'gradient'
   case (p_landscape_irc_term_energy_rise)
      name = 'energy_rise'
   case default
      name = 'error'
   end select

end function landscape_irc_term_name

!> Print a summary of an intrinsic reaction coordinate integration.
subroutine landscape_irc_result_write(self, unit)
   !> Result to print
   class(landscape_irc_result), intent(in) :: self
   !> Output unit
   integer, intent(in) :: unit

   write(unit, '(1x,a)') repeat('-', 62)
   if (allocated(self%message)) then
      write(unit, '(1x,a)') "irc: "//self%message
   end if
   write(unit, '(1x,a,f20.12,a)') "transition state energy:  ", self%energy_ts, " Eh"
   write(unit, '(1x,a,es15.6,a)') "transition state gradient: ", self%gnorm_ts, " Eh/bohr"
   write(unit, '(1x,a,i0)') "imaginary modes:          ", self%n_imag
   write(unit, '(1x,a,l1)') "first order saddle point: ", self%is_saddle
   write(unit, '(1x,a,es13.6,a)') "step length:              ", &
      & self%step_length, " bohr*amu^1/2"
   write(unit, '(1x,a,a)') "termination forward:      ", &
      & landscape_irc_term_name(self%term_fwd)
   if (self%n_bwd > 0) then
      write(unit, '(1x,a,a)') "termination backward:     ", &
         & landscape_irc_term_name(self%term_bwd)
   else
      write(unit, '(1x,a)') "termination backward:     not requested (--lirc-oneway)"
   end if
   write(unit, '(1x,a,i0)') "forward points:           ", self%n_fwd
   write(unit, '(1x,a,i0)') "backward points:          ", self%n_bwd
   if (self%n_fwd > 0) then
      write(unit, '(1x,a,f16.6,a)') "forward arc length:       ", &
         & self%s_fwd(self%n_fwd), " bohr*amu^1/2"
      write(unit, '(1x,a,f20.12,a)') "forward endpoint energy:  ", &
         & self%e_fwd(self%n_fwd), " Eh"
   end if
   if (self%n_bwd > 0) then
      write(unit, '(1x,a,f16.6,a)') "backward arc length:      ", &
         & self%s_bwd(self%n_bwd), " bohr*amu^1/2"
      write(unit, '(1x,a,f20.12,a)') "backward endpoint energy: ", &
         & self%e_bwd(self%n_bwd), " Eh"
      call write_attribution(unit, "backward", self%reached_min_bwd, &
         & self%rmsd_to_min_bwd, self%e_min_bwd)
   else
      write(unit, '(1x,a)') "backward direction: not requested (--lirc-oneway)"
   end if
   call write_attribution(unit, "forward", self%reached_min_fwd, &
      & self%rmsd_to_min_fwd, self%e_min_fwd)
   write(unit, '(1x,a,i0,a,i0,a)') "sphere relaxation pinned:  ", &
      & self%n_pinned_fwd + self%n_pinned_bwd, " of ", self%n_fwd + self%n_bwd, &
      & " points (GS micro cycle budget; 0 for the predictor-corrector)"
   write(unit, '(1x,a,i0,a,f12.6,a)') "phase component:          ", &
      & self%phase_index, " (value ", self%phase_value, ")"
   write(unit, '(1x,a,l1)') "directions swapped:       ", self%swapped
   if (self%etemp > 0.0_wp) then
      write(unit, '(1x,a,f12.3,a)') "etemp:                    ", self%etemp, " K"
   end if
   write(unit, '(1x,a)') repeat('-', 62)

end subroutine landscape_irc_result_write

!> Print the endpoint attribution of one direction.
!>
!> Without an endpoint relaxation there is no relaxed minimum and therefore no
!> Kabsch aligned RMSD: the assignment rests on the termination signal alone
!> and `e_min` is zero.  The summary says so instead of printing a `0.000000`
!> distance next to a satisfied criterion (M-2 of `45-m6-independent-review.md`).
subroutine write_attribution(unit, direction, reached, rmsd, e_min)
   !> Output unit
   integer, intent(in) :: unit
   !> Direction label
   character(len=*), intent(in) :: direction
   !> True if the endpoint is assigned to a minimum
   logical, intent(in) :: reached
   !> Kabsch aligned RMSD to the relaxed minimum (bohr)
   real(wp), intent(in) :: rmsd
   !> Energy of the relaxed minimum (hartree, zero without a relaxation)
   real(wp), intent(in) :: e_min

   if (e_min == 0.0_wp) then
      write(unit, '(1x,a,a,l1,a)') direction, " reached minimum: ", reached, &
         & " (no endpoint relaxation, the rmsd criterion was skipped)"
   else
      write(unit, '(1x,a,a,l1,a,f12.6,a,f20.12,a)') direction, " reached minimum: ", &
         & reached, " (rmsd ", rmsd, " bohr, minimum ", e_min, " Eh)"
   end if

end subroutine write_attribution

end module xtb_landscape_results
