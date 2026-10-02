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

!> Local quadratic approximation (LQA) intrinsic reaction coordinate.
!>
!> The path is followed with the analytic quadratic propagation of
!> `xtb_landscape_irc_corrector::landscape_irc_lqa_step`: at every macro step
!> the local quadratic model `E(x) = E_0 + g_0^T dx + 1/2 dx^T H dx` of the
!> current point is integrated exactly along the steepest descent ODE
!>
!>     `dx(s)/ds = -g(x)/|g(x)|`
!>
!> of Hratchian & Schlegel, J. Chem. Phys. **120**, 9918 (2004), Eq. 1, for
!> the requested arc length `step_length` (bohr*amu^1/2).
!>
!> **Lineage (PLAN R-12 / report 04 Contradictions #3).**  This is the
!> **Page & McIver branch** (Page & McIver, J. Chem. Phys. **88**, 922
!> (1988)): the quadratic Taylor solution that the HPC/EulerPC papers and
!> Gaussian attribute to Page & McIver.  It is **not** the Sun-Ruedenberg /
!> Eckert & Werner quadratic steepest descent (QSD), whose step
!> `x(u) = x^(k) - H^{-1}(I - uH) g` uses a curvature dependent step size
!> function and three distinct points along the path.  The two are the same
!> family but different derivations and are not interchangeable; see the
!> header of `irc/corrector.f90` for the full comparison.
!>
!> The Hessian is updated along the path with the configured formula (Bofill
!> by default) and rebuilt from the provider every `hessian_recalc` macro
!> steps when that is positive.  One macro step costs **one** energy/gradient
!> evaluation (the analytic propagation needs none; the new point is
!> evaluated once).
!>
!> **Measured failure mode (PLAN section 6.5, report 04 section 1.3).**  The
!> straightforward LQA step oscillates and deviates from the MEP on strongly
!> curved paths; the literature step sizes are 0.10 (the practical upper
!> limit) with 0.05 for the `tight` level, and 0.20 is "slightly difficult".
!> The M6 validation round measured the deviation on the analytic
!> Mueller-Brown and LEPS surfaces for the step sizes {0.05, 0.10, 0.20,
!> 0.40}; the numbers and the conclusions are recorded in
!> `docs/_landscape-recon/42-m6-irc-core-implementation-report.md`.
!>
!> Units: mass weighted coordinates and arc lengths in `bohr*amu^1/2`,
!> Cartesian geometries in bohr, energies in hartree, gradients in
!> hartree/bohr, Hessian elements in hartree/(bohr^2 amu).
module xtb_landscape_irc_lqa
   use xtb_mctc_accuracy, only : wp
   use xtb_type_environment, only : TEnvironment
   use xtb_landscape_settings, only : landscape_irc_settings
   use xtb_landscape_results, only : p_landscape_irc_term_max_steps, &
      & p_landscape_irc_term_grad, p_landscape_irc_term_energy_rise
   use xtb_landscape_coords, only : vec_norm, vec_maxabs
   use xtb_landscape_engine, only : landscape_energy_model
   use xtb_landscape_hessian_update, only : update_by_enum
   use xtb_landscape_irc_corrector, only : landscape_irc_sqrt_mass, &
      & landscape_irc_to_weighted, landscape_irc_from_weighted, &
      & landscape_irc_gradient_to_weighted, landscape_irc_hessian_to_weighted, &
      & landscape_irc_lqa_step, landscape_irc_path, landscape_irc_path_add, &
      & landscape_irc_path_reset
   implicit none(type, external)
   private

   public :: landscape_irc_lqa_walk

contains

!> Follow one direction of the IRC with the LQA analytic propagation.
subroutine landscape_irc_lqa_walk(env, model, settings, mass, x0, hess0, v, sign, &
      & path, fail)
   character(len=*), parameter :: source = 'landscape_irc_lqa_walk'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Potential
   class(landscape_energy_model), intent(inout) :: model
   !> IRC settings
   type(landscape_irc_settings), intent(in) :: settings
   !> Atomic masses in amu (length 3N)
   real(wp), intent(in) :: mass(:)
   !> Transition state geometry, flat Cartesian (bohr)
   real(wp), intent(in) :: x0(:)
   !> Cartesian Hessian at the transition state (hartree/bohr^2)
   real(wp), intent(in) :: hess0(:, :)
   !> Mass weighted transition vector (unit, phase fixed)
   real(wp), intent(in) :: v(:)
   !> Direction sign (`+1` forward, `-1` backward)
   real(wp), intent(in) :: sign
   !> Resulting path
   type(landscape_irc_path), intent(inout) :: path
   !> Failure flag
   logical, intent(out) :: fail

   real(wp), allocatable :: sqrt_mass(:), hq(:, :), q_ts(:), g_ts(:), g_cart(:)
   real(wp), allocatable :: q_cur(:), g_cur(:), q_new(:), g_new(:), d(:)
   real(wp), allocatable :: x_new(:), hc(:, :)
   real(wp) :: e_ts, e_cur, e_new, e_min, gnorm_cur, gnorm_new, s_cur, s_reached
   real(wp) :: step, shift
   integer :: ndim, npoint, nrise
   logical :: ok, s_fail

   fail = .false.
   ndim = size(x0)
   step = settings%step_length
   allocate(sqrt_mass(ndim), hq(ndim, ndim), q_ts(ndim), g_ts(ndim))
   allocate(g_cart(ndim), q_cur(ndim), g_cur(ndim), q_new(ndim), g_new(ndim))
   allocate(d(ndim), x_new(ndim), hc(ndim, ndim))

   sqrt_mass = landscape_irc_sqrt_mass(mass)
   ! start from an empty path: the storage of a reused path is appended to
   call landscape_irc_path_reset(path)

   call model%evaluate(x0, e_ts, g_cart, fail)
   if (fail) then
      call env%error("the transition state could not be evaluated", source)
      return
   end if
   call landscape_irc_to_weighted(sqrt_mass, x0, q_ts)
   call landscape_irc_gradient_to_weighted(sqrt_mass, g_cart, g_ts)
   call landscape_irc_hessian_to_weighted(sqrt_mass, hess0, hq)

   ! starting point: half a step along the transition vector
   q_cur = q_ts + sign*0.5_wp*step*v
   call landscape_irc_from_weighted(sqrt_mass, q_cur, x_new)
   call model%evaluate(x_new, e_cur, g_cart, fail)
   if (fail) then
      call env%error("the first IRC point could not be evaluated", source)
      return
   end if
   call landscape_irc_gradient_to_weighted(sqrt_mass, g_cart, g_cur)
   gnorm_cur = vec_norm(g_cart)
   s_cur = 0.5_wp*step
   call landscape_irc_path_add(path, x_new, e_cur, s_cur, gnorm_cur, &
      & vec_maxabs(g_cart), 1)
   e_min = e_cur
   call update_by_enum(settings%hessian_update, q_cur - q_ts, g_cur - g_ts, hq, ok)

   npoint = 1
   nrise = 0
   do
      if (npoint >= settings%max_steps) then
         path%term = p_landscape_irc_term_max_steps
         exit
      end if
      ! signal (b): a stationary point was reached (RMS gradient per
      ! Cartesian component)
      if (gnorm_cur/sqrt(real(ndim, wp)) <= settings%grad_tol) then
         path%term = p_landscape_irc_term_grad
         exit
      end if

      ! optional exact Hessian rebuild
      if (settings%hessian_recalc > 0) then
         if (mod(npoint, settings%hessian_recalc) == 0) then
            call landscape_irc_from_weighted(sqrt_mass, q_cur, x_new)
            call model%hessian(x_new, hc, fail)
            if (fail) then
               call env%error("the Hessian of the IRC path could not be "//&
                  & "rebuilt", source)
               return
            end if
            call landscape_irc_hessian_to_weighted(sqrt_mass, hc, hq)
         end if
      end if

      ! analytic quadratic propagation of one step
      call landscape_irc_lqa_step(env, g_cur, hq, step, settings%euler_n, &
         & d, s_reached, s_fail)
      if (s_fail) then
         ! a vanishing gradient defines no direction: the path has reached a
         ! stationary point and is terminated by signal (b)
         path%term = p_landscape_irc_term_grad
         exit
      end if
      q_new = q_cur + d
      call landscape_irc_from_weighted(sqrt_mass, q_new, x_new)
      call model%evaluate(x_new, e_new, g_cart, fail)
      if (fail) then
         call env%error("an IRC step could not be evaluated", source)
         return
      end if
      call landscape_irc_gradient_to_weighted(sqrt_mass, g_cart, g_new)
      call update_by_enum(settings%hessian_update, q_new - q_cur, &
         & g_new - g_cur, hq, ok)

      gnorm_new = vec_norm(g_cart)
      ! the arc length of the quadratic path is `s_reached`; the chord |d| is
      ! always shorter, so the recorded arc length uses the integral
      shift = s_reached
      if (shift <= 0.0_wp) shift = vec_norm(d)
      s_cur = s_cur + shift
      call landscape_irc_path_add(path, x_new, e_new, s_cur, gnorm_new, &
         & vec_maxabs(g_cart), 1)
      npoint = npoint + 1

      ! signal (c): the energy has stopped setting a new minimum for
      ! `e_rise_steps` consecutive points, i.e. the descent has turned
      ! around (the implemented form of the PLAN "the energy rises again").
      ! The comparison is against the **running minimum**, not the previous
      ! point: near a minimum both integrators produce a short limit cycle
      ! (the fixed arc length of LQA), so a strict `E_k > E_{k-1}` alternates
      ! and never fires (measured on the analytic Mueller-Brown surface,
      ! report 42).
      if (e_new < e_min) then
         e_min = e_new
         nrise = 0
      else
         nrise = nrise + 1
      end if
      if (nrise >= max(1, settings%e_rise_steps)) then
         path%term = p_landscape_irc_term_energy_rise
         exit
      end if

      q_cur = q_new
      g_cur = g_new
      gnorm_cur = gnorm_new
   end do

end subroutine landscape_irc_lqa_walk

end module xtb_landscape_irc_lqa
