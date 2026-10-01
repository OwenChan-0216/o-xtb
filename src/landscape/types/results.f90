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
   public :: landscape_step, landscape_result, landscape_convergence_report
   public :: landscape_result_add_step, landscape_report_add, landscape_result_trim
   public :: landscape_print_step, landscape_result_write, landscape_report_write

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
      !> Trust radius active in this step (bohr)
      real(wp) :: trust_radius = 0.0_wp
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

   if (step%istep <= 1) then
      write(unit, '(1x,a)') "   iter            energy/Eh        dE/(kcal/mol) "//&
         & "  gmax/(Eh/bohr)  dmax/bohr     trust/bohr"
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

end module xtb_landscape_results
