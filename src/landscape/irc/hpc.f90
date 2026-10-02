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

!> Hessian based predictor-corrector (HPC) intrinsic reaction coordinate.
!>
!> The path is followed with the predictor-corrector integrator of Hratchian
!> & Schlegel, J. Chem. Phys. **120**, 9918 (2004), Eqs. 2-11, in the same
!> mass weighted Cartesian metric as the other integrators of the suite
!> (`1 a.u. = 1 bohr*amu^1/2`, Eq. 1):
!>
!>     `dx(s)/ds = -g(x)/|g(x)|`.
!>
!> **Predictor (Eqs. 2-11).**  With the local quadratic model
!> `E(x) = E_0 + g_0^T dx + 1/2 dx^T H dx` the ODE has the closed form
!>
!>     `x(t) = x_0 + U a(t) U^T g_0`,
!>     `a_ii(t) = (e^{-lambda_i t} - 1)/lambda_i`,
!>
!> where `lambda_i` are the eigenvalues of the **mass weighted** Hessian and
!> `t` is fixed by the requested arc length (the `N_Euler = 5000` sub-step
!> march of Eq. 10, here solved by the same `landscape_irc_lqa_step` the LQA
!> integrator uses).  The `lambda_i -> 0` limit is the removable branch
!> `a_ii -> -t`, taken explicitly in the shared corrector (never a division
!> by a vanishing eigenvalue).
!>
!> **Corrector (Eqs. 5-6, Meisner & Kaestner Eqs. 3-4).**  The predicted
!> point is **evaluated once** and used together with the current point as
!> the two samples of a distance weighted interpolation (DWI) surface; the
!> modified Bulirsch-Stoer integrator (simple Euler base step + Richardson
!> extrapolation) then integrates the DWI steepest-descent ODE from the
!> current point over the requested arc length to give the corrected point,
!> which is **evaluated once** as well and becomes the next IRC point.  The
!> cost is therefore **two E/g per IRC point** in this implementation.
!>
!> **Why not the paper's one E/g?**  The HPC paper reconstructs the gradient
!> of the corrected point from the DWI and feeds it to the next predictor,
!> which would cost a single E/g.  Measured on the GFN2 HCN/HNC path this
!> reconstruction is systematically too small (the DWI gradient is dominated
!> by the predicted sample) and the reconstructed gradient drifts the path:
!> the endpoint lands **1e-3..5e-2 hartree above the true HNC minimum**
!> instead of entering the basin.  The M6 validation round implemented the
!> one-E/g scheme independently and measured **2.80e-3 hartree** for
!> "evaluate the predicted point only and trust the DWI gradient" (V1) and
!> **4.56e-2 hartree** for the same scheme with the predicted secant update
!> (V2), both at exactly 1.00 E/g
!> (`44-m6-validation-experiments.md` section 6.1).  The `1.4e-2` quoted by
!> `43-m6-irc-predictor-corrector-report.md` is a number of that order but is
!> not reproduced by either construction and is therefore retired here.
!> Evaluating the corrected point removes the drift - the two-E/g variant
!> ends 5.5e-5 hartree above the minimum, i.e. 50 to 800 times closer - and
!> keeps every recorded energy/gradient a true PES value (the same reason the
!> MAPLE reference implementation evaluates its corrected point - it costs
!> three E/g because it also re-evaluates the current one).  The measured
!> `E/g` distribution is in
!> `docs/_landscape-recon/43-m6-irc-predictor-corrector-report.md`.
!>
!> **Failure mode.**  When the mBS extrapolation does not reach `mbs_tol`
!> within `mbs_max_k` levels (or its evaluation budget), the step **falls
!> back to one Gonzalez-Schlegel step** and emits `env%warning`, exactly as
!> PLAN section 6.5 requires.  The fallback is exercised by the unit test
!> `hpc-corrector-fallback` (which forces a non-converging correction).
!>
!> **Hessian.**  The mass weighted Hessian is updated with the secant of the
!> **accepted** point with the configured formula (Bofill by default, Bofill,
!> J. Comput. Chem. **15**, 1 (1994)); unlike EulerPC, HPC does **not** update
!> the Hessian with the predicted secant (its predictor is the analytic
!> propagation, which produces no secant - see
!> `landscape_irc_corrector_step`).  `hessian_recalc=N` rebuilds the exact
!> Hessian from the provider every N macro steps when positive, and the DWI
!> shares the current Hessian.
!>
!> **Step size.**  The paper recommends 0.05-0.20 on model surfaces and up to
!> **0.40** in chemical systems, where the plain LQA step is already marginal
!> at 0.10.  The 0.10/0.20/0.40 comparison is recorded in
!> `docs/_landscape-recon/43-m6-irc-predictor-corrector-report.md`.
!>
!> The path is left by one of the three termination signals of PLAN section
!> 6.5: (a) `max_steps`, (b) `|g|` below `grad_tol`, (c) the energy rising
!> over `e_rise_steps` consecutive points.
!>
!> Units: mass weighted coordinates and arc lengths in `bohr*amu^1/2`,
!> Cartesian geometries in bohr, energies in hartree, gradients in
!> hartree/bohr, Hessian elements in hartree/(bohr^2 amu).
module xtb_landscape_irc_hpc
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
      & landscape_irc_lqa_step, landscape_irc_corrector_step, &
      & landscape_irc_path, landscape_irc_path_add, landscape_irc_path_reset
   use xtb_landscape_irc_gs, only : landscape_irc_gs_step
   implicit none(type, external)
   private

   public :: landscape_irc_hpc_walk

   !> Upper bound on the DWI evaluations of one mBS correction.  The
   !> corrected point is analytic (the DWI surface), so this only bounds the
   !> pathological case in which the Richardson extrapolation never reaches
   !> `mbs_tol`; reaching it triggers the GS fallback instead of hanging.
   integer, parameter :: hpc_corrector_max_points = 400000

contains

!> Follow one direction of the IRC with the HPC predictor-corrector scheme.
!>
!> On return `path` holds the points after the transition state, in order, with
!> their arc length from the transition state and their termination signal.
!> `fail` is true only for a hard error (a failed model evaluation or
!> eigensolve); the termination signals are not errors.
subroutine landscape_irc_hpc_walk(env, model, settings, mass, x0, hess0, v, sign, &
      & path, fail)
   character(len=*), parameter :: source = 'landscape_irc_hpc_walk'
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
   real(wp), allocatable :: q_new(:), g_new(:), d(:), x_new(:)
   real(wp) :: e_ts, e_cur, e_pred, e_new, e_min, gnorm_cur, gnorm_new
   real(wp) :: s_cur, ds, step, s_reached
   integer :: ndim, npoint, nrise, neval
   logical :: ok, s_fail, corr_ok, corr_fail, micro_converged, recalc, fallback

   fail = .false.
   ndim = size(x0)
   step = settings%step_length
   allocate(sqrt_mass(ndim), hq(ndim, ndim), q_ts(ndim), g_ts(ndim))
   allocate(g_cart(ndim), q_cur(ndim), g_cur(ndim), q_pred(ndim), g_pred(ndim))
   allocate(q_new(ndim), g_new(ndim), d(ndim), x_new(ndim))

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

      ! optional exact Hessian rebuild before the predictor uses it
      if (settings%hessian_recalc > 0) then
         if (mod(npoint, settings%hessian_recalc) == 0) then
            call landscape_irc_from_weighted(sqrt_mass, q_cur, x_new)
            call rebuild_hessian(env, model, sqrt_mass, x_new, hq, fail)
            if (fail) return
         end if
      end if

      ! --- predictor: analytic (Page-McIver) quadratic propagation --------
      call landscape_irc_lqa_step(env, g_cur, hq, step, settings%euler_n, d, &
         & s_reached, s_fail)
      if (s_fail) then
         ! a vanishing gradient defines no direction: signal (b)
         path%term = p_landscape_irc_term_grad
         exit
      end if
      q_pred = q_cur + d

      ! --- evaluate the predicted point (first E/g of the step) ----------
      call landscape_irc_from_weighted(sqrt_mass, q_pred, x_new)
      call model%evaluate(x_new, e_pred, g_cart, fail)
      if (fail) then
         call env%error("the predicted IRC point could not be evaluated", source)
         return
      end if
      call landscape_irc_gradient_to_weighted(sqrt_mass, g_cart, g_pred)

      ! --- corrector: DWI surface of (current, predicted) + mBS -----------
      call landscape_irc_corrector_step(env, hq, q_cur, e_cur, g_cur, q_pred, &
         & e_pred, g_pred, step, settings%mbs_tol, settings%mbs_points, &
         & settings%mbs_max_k, hpc_corrector_max_points, settings%dwi_n, &
         & q_new, e_new, g_new, corr_ok, corr_fail)
      neval = 1
      fallback = corr_fail .or. (.not. corr_ok)
      if (fallback) then
         call env%warning("the DWI/mBS corrector did not converge at IRC "//&
            & "point; falling back to one Gonzalez-Schlegel step", source)
         call landscape_irc_gs_step(env, model, settings, sqrt_mass, q_cur, &
            & g_cur, hq, step, .false., q_new, x_new, e_new, g_new, neval, &
            & micro_converged, fail)
         if (fail) return
         if (.not. micro_converged) path%n_pinned = path%n_pinned + 1
      else
         ! evaluate the corrected point (second E/g of the step); this keeps
         ! the recorded energy/gradient true PES values (see the module
         ! header: the DWI reconstruction of the paper drifts the path)
         call landscape_irc_from_weighted(sqrt_mass, q_new, x_new)
         call model%evaluate(x_new, e_new, g_cart, fail)
         if (fail) then
            call env%error("the corrected IRC point could not be evaluated", source)
            return
         end if
         neval = 2
         call landscape_irc_gradient_to_weighted(sqrt_mass, g_cart, g_new)
      end if

      ! Hessian update with the secant of the point just accepted
      call update_by_enum(settings%hessian_update, q_new - q_cur, &
         & g_new - g_cur, hq, ok)

      ! the Cartesian gradient is `g_i = g^q_i sqrt(m_i)`
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

end subroutine landscape_irc_hpc_walk

!> Rebuild the mass weighted Hessian from the model at a Cartesian geometry.
subroutine rebuild_hessian(env, model, sqrt_mass, x, hq, fail)
   character(len=*), parameter :: source = 'landscape_irc_hpc_rebuild_hessian'
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

end module xtb_landscape_irc_hpc
