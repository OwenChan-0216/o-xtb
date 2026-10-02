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

!> Euler predictor-corrector (EulerPC) intrinsic reaction coordinate.
!>
!> The path is followed with the integrator of Meisner & Kaestner,
!> J. Chem. Phys. **133**, 224101 (2010), Eqs. 2-4, in the same mass weighted
!> Cartesian metric as the other integrators of the suite (`1 a.u. =
!> 1 bohr*amu^1/2`):
!>
!>     `dx(s)/ds = -g(x)/|g(x)|`.
!>
!> **Predictor (Eq. 2).**  A first order explicit Euler step along the
!> steepest descent direction,
!>
!>     `x~_{i+1} = x_i - (g_i/|g_i|) s`,
!>
!> i.e. no Hessian is needed for the prediction (unlike HPC, whose predictor
!> is the analytic quadratic propagation of Hratchian & Schlegel).  The
!> predictor is therefore **first order** in the step; its measured log-log
!> slope on the analytic Mueller-Brown surface is reported in
!> `docs/_landscape-recon/43-m6-irc-predictor-corrector-report.md`.
!>
!> **Corrector (Eqs. 3-4).**  Identical to HPC: the predicted point is
!> evaluated once, together with the current point it forms the two samples
!> of the distance weighted interpolation (DWI) surface, and the modified
!> Bulirsch-Stoer integrator (simple Euler base step + Richardson
!> extrapolation) advances the DWI steepest-descent ODE from the current
!> point over the requested arc length.  The corrected point is evaluated
!> once as well, so the fine phase costs **two E/g per point** and every
!> recorded energy/gradient is a true PES value (the module header of
!> `irc/hpc.f90` records why the single-evaluation DWI reconstruction of the
!> papers is not used: it drifts the path).
!>
!> **`loose_cycles` (coarse/fine schedule).**  The first `loose_cycles` macro
!> steps are the **coarse** phase: the Euler prediction is recorded directly
!> (no corrector) and only the evaluated predicted point is kept.  From step
!> `loose_cycles + 1` on, the **fine** phase applies the DWI/mBS corrector.
!> `loose_cycles = 0` disables the coarse phase entirely.  The definition is
!> a deliberate sharpening of the MAPLE `loose_cycles` flag (which only
!> loosened the predictor-length convergence) so that the branch is
!> observable and testable; it is recorded as a deviation in the report.
!>
!> **Failure mode.**  The paper reports that a 0.20 step "cannot follow the
!> path" with a plain Euler predictor; the measured deviation for 0.10/0.20
!> with and without the corrector is in the report.  When the mBS
!> extrapolation itself does not converge, the step **falls back to one
!> Gonzalez-Schlegel step** and warns (PLAN section 6.5), like HPC.
!>
!> The path is left by one of the three termination signals of PLAN section
!> 6.5: (a) `max_steps`, (b) `|g|` below `grad_tol`, (c) the energy rising
!> over `e_rise_steps` consecutive points.
!>
!> Units: mass weighted coordinates and arc lengths in `bohr*amu^1/2`,
!> Cartesian geometries in bohr, energies in hartree, gradients in
!> hartree/bohr, Hessian elements in hartree/(bohr^2 amu).
module xtb_landscape_irc_eulerpc
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
      & landscape_irc_corrector_step, landscape_irc_path, &
      & landscape_irc_path_add, landscape_irc_path_reset
   use xtb_landscape_irc_gs, only : landscape_irc_gs_step
   implicit none(type, external)
   private

   public :: landscape_irc_eulerpc_walk

   !> Upper bound on the DWI evaluations of one mBS correction (see HPC).
   integer, parameter :: eulerpc_corrector_max_points = 400000
   !> Guard of the Euler direction (`|g|` below this defines no direction).
   real(wp), parameter :: euler_gradient_guard = 1.0e-14_wp

contains

!> Follow one direction of the IRC with the EulerPC scheme.
!>
!> On return `path` holds the points after the transition state, in order, with
!> their arc length from the transition state and their termination signal.
!> `fail` is true only for a hard error (a failed model evaluation or
!> eigensolve); the termination signals are not errors.
subroutine landscape_irc_eulerpc_walk(env, model, settings, mass, x0, hess0, v, &
      & sign, path, fail)
   character(len=*), parameter :: source = 'landscape_irc_eulerpc_walk'
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
   real(wp), allocatable :: q_cur(:), g_cur(:), q_pred(:), g_pred(:)
   real(wp), allocatable :: q_new(:), g_new(:), x_new(:)
   real(wp) :: e_ts, e_cur, e_pred, e_new, e_min, gnorm_cur, gnorm_new
   real(wp) :: s_cur, ds, step, gn
   integer :: ndim, npoint, nrise, neval, istep
   logical :: ok, corr_ok, corr_fail, micro_converged, fallback, coarse

   fail = .false.
   ndim = size(x0)
   step = settings%step_length
   allocate(sqrt_mass(ndim), hq(ndim, ndim), q_ts(ndim), g_ts(ndim))
   allocate(g_cart(ndim), q_cur(ndim), g_cur(ndim), q_pred(ndim), g_pred(ndim))
   allocate(q_new(ndim), g_new(ndim), x_new(ndim))

   sqrt_mass = landscape_irc_sqrt_mass(mass)
   ! start from an empty path: the storage of a reused path is appended to
   call landscape_irc_path_reset(path)

   ! --- transition state reference --------------------------------------
   call model%evaluate(x0, e_ts, g_cart, fail)
   if (fail) then
      call env%error("the transition state could not be evaluated", source)
      return
   end if
   call landscape_irc_to_weighted(sqrt_mass, x0, q_ts)
   call landscape_irc_gradient_to_weighted(sqrt_mass, g_cart, g_ts)
   call landscape_irc_hessian_to_weighted(sqrt_mass, hess0, hq)

   ! --- starting point: half a step along the transition vector ----------
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

   ! --- macro steps ------------------------------------------------------
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

      ! optional exact Hessian rebuild before the step
      if (settings%hessian_recalc > 0) then
         if (mod(npoint, settings%hessian_recalc) == 0) then
            call landscape_irc_from_weighted(sqrt_mass, q_cur, x_new)
            call rebuild_hessian(env, model, sqrt_mass, x_new, hq, fail)
            if (fail) return
         end if
      end if

      ! --- predictor: first order explicit Euler (Eq. 2) ------------------
      gn = vec_norm(g_cur)
      if (gn <= euler_gradient_guard) then
         path%term = p_landscape_irc_term_grad
         exit
      end if
      q_pred = q_cur - step*(g_cur/gn)

      ! --- evaluate the predicted point (the single E/g of the step) ------
      call landscape_irc_from_weighted(sqrt_mass, q_pred, x_new)
      call model%evaluate(x_new, e_pred, g_cart, fail)
      if (fail) then
         call env%error("the predicted IRC point could not be evaluated", source)
         return
      end if
      call landscape_irc_gradient_to_weighted(sqrt_mass, g_cart, g_pred)

      ! Hessian update with the predicted secant
      call update_by_enum(settings%hessian_update, q_pred - q_cur, &
         & g_pred - g_cur, hq, ok)

      ! --- coarse / fine phase -------------------------------------------
      istep = npoint
      coarse = istep <= settings%loose_cycles
      neval = 1
      if (coarse) then
         ! coarse phase: record the first order Euler prediction directly
         q_new = q_pred
         e_new = e_pred
         g_new = g_pred
      else
         ! fine phase: DWI/mBS corrector from the current point
         call landscape_irc_corrector_step(env, hq, q_cur, e_cur, g_cur, &
            & q_pred, e_pred, g_pred, step, settings%mbs_tol, &
            & settings%mbs_points, settings%mbs_max_k, &
            & eulerpc_corrector_max_points, settings%dwi_n, &
            & q_new, e_new, g_new, corr_ok, corr_fail)
         fallback = corr_fail .or. (.not. corr_ok)
         neval = 1
         if (fallback) then
            call env%warning("the DWI/mBS corrector did not converge at "//&
               & "IRC point; falling back to one Gonzalez-Schlegel step", source)
            call landscape_irc_gs_step(env, model, settings, sqrt_mass, q_cur, &
               & g_cur, hq, step, .false., q_new, x_new, e_new, g_new, neval, &
               & micro_converged, fail)
            if (fail) return
            if (.not. micro_converged) path%n_pinned = path%n_pinned + 1
         else
            call landscape_irc_from_weighted(sqrt_mass, q_new, x_new)
            call model%evaluate(x_new, e_new, g_cart, fail)
            if (fail) then
               call env%error("the corrected IRC point could not be evaluated", source)
               return
            end if
            neval = 2
            call landscape_irc_gradient_to_weighted(sqrt_mass, g_cart, g_new)
         end if
      end if

      ! Hessian update with the secant of the point just accepted
      call update_by_enum(settings%hessian_update, q_new - q_cur, &
         & g_new - g_cur, hq, ok)

      ! the (mass weighted) gradient of the point; the Cartesian gradient is
      ! `g_i = g^q_i sqrt(m_i)`
      g_cart = g_new*sqrt_mass
      gnorm_new = vec_norm(g_cart)
      ds = vec_norm(q_new - q_cur)
      s_cur = s_cur + ds
      call landscape_irc_path_add(path, x_new, e_new, s_cur, gnorm_new, &
         & vec_maxabs(g_cart), neval)
      npoint = npoint + 1

      ! signal (c): the energy has stopped setting a new minimum for
      ! `e_rise_steps` consecutive points (the implemented form of the PLAN
      ! "the energy rises again", see report 42 section 10 R-3)
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

end subroutine landscape_irc_eulerpc_walk

!> Rebuild the mass weighted Hessian from the model at a Cartesian geometry.
subroutine rebuild_hessian(env, model, sqrt_mass, x, hq, fail)
   character(len=*), parameter :: source = 'landscape_irc_eulerpc_rebuild_hessian'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Potential
   class(landscape_energy_model), intent(inout) :: model
   !> `sqrt(mass)` (length 3N)
   real(wp), intent(in) :: sqrt_mass(:)
   !> Cartesian geometry (bohr)
   real(wp), intent(in) :: x(:)
   !> Mass weighted Hessian, overwritten
   real(wp), intent(inout) :: hq(:, :)
   !> Failure flag
   logical, intent(out) :: fail

   real(wp), allocatable :: hc(:, :)

   fail = .false.
   allocate(hc(size(hq, 1), size(hq, 2)), source=0.0_wp)
   call model%hessian(x, hc, fail)
   if (fail) then
      call env%error("the Hessian of the IRC path could not be rebuilt", source)
      return
   end if
   call landscape_irc_hessian_to_weighted(sqrt_mass, hc, hq)

end subroutine rebuild_hessian

end module xtb_landscape_irc_eulerpc
