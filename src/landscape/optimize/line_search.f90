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

!> Backtracking line search of the landscape suite.
!>
!> Armijo sufficient decrease with step halving
!> (Nocedal & Wright, Numerical Optimization, 2nd ed., Algorithm 3.1):
!> accept the trial step `alpha*d` if
!> `E(x + alpha d) <= E(x) + c1 alpha g(x).d`.  The initial trial length is
!> supplied by the caller (already clipped to the maximum displacement), the
!> number of backtracks is bounded by `max_backtrack` and the step length by a
!> relative machine precision floor, so the routine always terminates.
!>
!> There is deliberately **no Wolfe curvature condition**: the accepted step
!> only guarantees sufficient decrease, so the quality of the curvature pair
!> passed on to the quasi-Newton update depends entirely on the caller's
!> filtering (`lbfgs_push`, `update_bfgs`, ...).  This is the same design as
!> MAPLE and matches the PLAN decision for M1.
!>
!> The energy and gradient are obtained exclusively through the injected
!> `landscape_energy_model`; no global state is read.
!>
!> Units: `x`, `direction` and `step` in bohr, energies in hartree and
!> gradients in hartree/bohr.
module xtb_landscape_line_search
   use xtb_mctc_accuracy, only : wp
   use xtb_landscape_engine, only : landscape_energy_model
   implicit none(type, external)
   private

   public :: landscape_line_search

contains

!> Armijo backtracking line search.
!>
!> On success `step = alpha_accepted * direction` and `energy_new`/`gradient_new`
!> hold the values at the accepted point; `fail` is `.false.` and `n_evals` the
!> number of objective evaluations.  On failure (`fail = .true.`) `step` is
!> zero, `energy_new`/`gradient_new` equal the values at `x` and the caller
!> should treat the iteration as stagnated.
subroutine landscape_line_search(objective, x, energy, gradient, direction, alpha, &
      & step, alpha_accepted, energy_new, gradient_new, n_evals, fail, &
      & c1, max_backtrack)
   !> Objective function (energy and gradient)
   class(landscape_energy_model), intent(inout) :: objective
   !> Current coordinates (bohr)
   real(wp), intent(in) :: x(:)
   !> Current energy (hartree)
   real(wp), intent(in) :: energy
   !> Current gradient (hartree/bohr)
   real(wp), intent(in) :: gradient(:)
   !> Search direction (bohr)
   real(wp), intent(in) :: direction(:)
   !> Initial trial step length
   real(wp), intent(in) :: alpha
   !> Accepted displacement (bohr)
   real(wp), intent(out) :: step(:)
   !> Accepted step length
   real(wp), intent(out) :: alpha_accepted
   !> Energy at the accepted point (hartree)
   real(wp), intent(out) :: energy_new
   !> Gradient at the accepted point (hartree/bohr)
   real(wp), intent(out) :: gradient_new(:)
   !> Number of objective evaluations
   integer, intent(out) :: n_evals
   !> Failure flag
   logical, intent(out) :: fail
   !> Armijo constant, defaults to 1e-4
   real(wp), intent(in), optional :: c1
   !> Maximum number of backtracks, defaults to 10
   integer, intent(in), optional :: max_backtrack

   real(wp), allocatable :: x_trial(:), g_trial(:)
   real(wp) :: armijo, slope, trial, e_trial, alpha_min
   integer :: iback, maxback
   logical :: bad

   armijo = 1.0e-4_wp
   if (present(c1)) armijo = c1
   maxback = 10
   if (present(max_backtrack)) maxback = max_backtrack
   alpha_min = sqrt(epsilon(1.0_wp))*max(alpha, 1.0_wp)

   fail = .true.
   n_evals = 0
   alpha_accepted = 0.0_wp
   step = 0.0_wp
   energy_new = energy
   gradient_new = gradient

   slope = dot_product(gradient, direction)
   if (slope >= 0.0_wp) return

   allocate(x_trial(size(x)), g_trial(size(x)))
   trial = alpha
   do iback = 0, maxback
      if (iback > 0 .and. trial <= alpha_min) exit
      x_trial = x + trial*direction
      call objective%evaluate(x_trial, e_trial, g_trial, bad)
      n_evals = n_evals + 1
      if (.not. bad) then
         if (e_trial <= energy + armijo*trial*slope) then
            step = trial*direction
            alpha_accepted = trial
            energy_new = e_trial
            gradient_new = g_trial
            fail = .false.
            return
         end if
      end if
      trial = 0.5_wp*trial
   end do

end subroutine landscape_line_search

end module xtb_landscape_line_search
