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

!> Gonzalez-Schlegel intrinsic reaction coordinate integration.
!>
!> One direction of the IRC is followed with the two stage scheme of
!> Gonzalez & Schlegel, J. Phys. Chem. **94**, 5523 (1990), Eqs. 8-10:
!>
!>  1. **pivot step.**  A pivot point is placed half a step upstream,
!>
!>        `q*_{k+1} = q_k - (1/2) s N G g_k`,  `N = (g_k^T G g_k)^{-1/2}`,
!>
!>     with `G` the inverse mass metric and `s` the step length.  In mass
!>     weighted coordinates (`q_i = sqrt(m_i) r_i`, `g^q_i = g_i/sqrt(m_i)`)
!>     the metric is the identity and `N = 1/|g^q|`, so the pivot is
!>     `q* = q_k - (1/2) s g^q_k/|g^q_k|`; the sphere of radius `s/2` about
!>     the pivot passes exactly through `q_k`.
!>  2. **constrained optimisation on the sphere.**  The next point is the
!>     minimum of the energy on that sphere, found with micro cycles.  Each
!>     micro step is the Newton step of the equality constrained problem
!>     `min E(q)` subject to `|q - pivot|^2 = R^2` (`R = s/2`), i.e. the
!>     solution of the linearised KKT system with the multiplier estimated at
!>     the current point and the reduced Hessian level shifted to be positive
!>     definite (see `landscape_irc_gs_lagrange_step`); the step is therefore
!>     a descent direction on the sphere and the linearised constraint is
!>     satisfied exactly.  The trial point is projected back onto the sphere
!>     after every step, which only removes the second order drift `O(d^2/R)`
!>     of the linearisation.  The micro cycle converges when the step norm
!>     falls below `micro_step_thresh`, or is stopped after
!>     `max_micro_cycles`.
!>
!> The first step leaves the transition state along the **transition vector**
!> (`+/- v`, the mass weighted imaginary mode with the M4 phase convention),
!> because the gradient vanishes there and the pivot formula is undefined.
!> The starting point of the walk is therefore the transition state displaced
!> by half a step along `v`; the pivot of the first macro step is the
!> transition state itself.
!>
!> The Hessian is updated along the path with the configured formula (Bofill
!> by default, Bofill, J. Comput. Chem. **15**, 1 (1994)) and rebuilt from the
!> provider every `hessian_recalc` macro steps when that is positive (long
!> paths need it: pure Bofill drifts after ~150 steps, measured 6.0e-4 hartree
!> off the minimum with `|g| = 4.1e-2`, recovered by `hessian_recalc = 10`;
!> report 44 section 5.2).
!>
!> The path is left by one of the three termination signals of PLAN section
!> 6.5: (a) `max_steps`, (b) `|g|` below `grad_tol`, (c) the energy rising
!> over `e_rise_steps` consecutive points.
!>
!> -------------------------------------------------------------------
!> Sphere relaxation (measured; the Lagrange step of report 64)
!> -------------------------------------------------------------------
!> `gs` is **not the default method** (the default is `hpc`, M6 behaviour
!> change recorded in PLAN section 12.15).  It used to be both the most
!> expensive and the least accurate integrator of the suite: the micro cycle
!> was driven by a *clamped tangent space* Newton step and therefore never met
!> its own convergence criterion.  The facts below are measured, not
!> conjectured; rows 1 and 2 are the **before/after** pair of the equality
!> constrained Lagrange step (report 64; the acceptance route is the PLAN
!> section 6.5 GS open item).
!>
!>  1. **Cost.**  A GFN2 HCN/HNC run at step 0.10 costs **1.88 E/g per point
!>     forward and 2.14 backward** (before: 16.93 / 20.25, and the PLAN
!>     section 6.5 estimate was 3-5).  HPC needs 1.98, LQA 1.00, so GS is now
!>     in the same class as the predictor-corrector; the reduction is 9.0x
!>     forward / 9.5x backward and comes from the micro cycle reaching its
!>     criterion in one to three evaluations instead of exhausting
!>     `max_micro_cycles` (measured `n_pinned`: 0 of 40 forward and 0 of 36
!>     backward; before 33 of 42 / 38 of 40, printed in `irc.log`).
!>  2. **Accuracy.**  On the analytic Mueller-Brown surface the maximum
!>     deviation from the fine reference path is **0.0192 bohr forward /
!>     0.0344 backward** (before 0.040; HPC 0.0022, LQA 0.0066, EulerPC
!>     0.026), and the returned point of the `gs-sphere-relaxation-quality`
!>     unit case is **8.5e-14 hartree** above the independently computed
!>     constrained minimum of the sphere (before 3.4e-4 / 1.3e-3 hartree,
!>     alternating with the parity of the micro cycle budget), the micro steps
!>     shrinking by an order of magnitude per cycle (measured 1.59e-2,
!>     1.3e-3, 1.1e-5 bohr*amu^1/2).  The GFN2 HCN/HNC endpoints stay inside
!>     their 1e-4 Eh basin windows (forward -5.4721229, backward -5.5040662 =
!>     the HNC/HCN minima) while the forward path now terminates one macro
!>     step earlier by the gradient criterion, so the reported forward arc
!>     length is 3.949160 instead of 4.051234 (backward 3.538733 instead of
!>     3.695670): the same path, one point shorter.
!>  3. **Root cause (fixed).**  The old micro step solved the projected Newton
!>     system `(P H P) d = -P g` with the negative curvatures floored
!>     *individually*, and clamped the result to the sphere radius.  The
!>     measured step was **1.8-2.4 bohr*amu^1/2**, 36-48 times the radius, so
!>     every micro step was clamped, the direction was no longer the
!>     constrained descent direction, the criterion `|d| <=
!>     micro_step_thresh` was never met and the cycle ended in a two cycle
!>     (measured: the accepted point alternated with the parity of the micro
!>     cycle budget at 3.4e-4 / 1.3e-3 hartree above the sphere minimum,
!>     identically at budgets 5, 20, 21 and 200).
!>  4. **The fix.**  The step is now the Newton step of the **equality
!>     constrained** problem (multiplier from the current KKT residual, reduced
!>     Hessian level shifted to positive definite), which is a descent
!>     direction on the sphere with an exactly satisfied linearised
!>     constraint; two rows of the KKT system are verified to 1e-16 by the
!>     `gs-kkt-system` unit case, including deliberately off-sphere points.
!>     The trust region is **kept**: it is inert on every validated path, but
!>     it is what bounds the level shift branch, where the smallest tangent
!>     curvature is shifted to the floor and the step would otherwise be
!>     unbounded.  The old `noclamp` injection (25.27 instead of 4.05 bohr*amu^1/2, `46-m6-fix-report.md`) clamped the
!>     *wrong* direction, so it does not carry over as evidence about the new
!>     one.
!>
!> Units: mass weighted coordinates and arc lengths in `bohr*amu^1/2`,
!> Cartesian geometries in bohr, energies in hartree, gradients in
!> hartree/bohr, Hessian elements in hartree/(bohr^2 amu).
module xtb_landscape_irc_gs
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_lapack, only : mctc_syev
   use xtb_type_environment, only : TEnvironment
   use xtb_landscape_settings, only : landscape_irc_settings, landscape_log_failed
   use xtb_landscape_results, only : p_landscape_irc_term_max_steps, &
      & p_landscape_irc_term_grad, p_landscape_irc_term_energy_rise
   use xtb_landscape_coords, only : vec_norm, vec_maxabs
   use xtb_landscape_engine, only : landscape_energy_model
   use xtb_landscape_hessian_update, only : update_by_enum
   use xtb_landscape_irc_corrector, only : landscape_irc_sqrt_mass, &
      & landscape_irc_to_weighted, landscape_irc_from_weighted, &
      & landscape_irc_gradient_to_weighted, landscape_irc_hessian_to_weighted, &
      & landscape_irc_path, landscape_irc_path_add, landscape_irc_path_reset
   implicit none(type, external)
   private

   public :: landscape_irc_gs_walk, landscape_irc_gs_step
   public :: landscape_irc_gs_lagrange_step

   !> Relative floor of the reduced Hessian level shift of the KKT step
   real(wp), parameter :: tangent_curvature_floor = 1.0e-10_wp
   !> Guard below which the gradient is considered vanishing (hartree/bohr);
   !> the descent direction is undefined there (the same guard as `lqa`, `hpc`
   !> and `eulerpc`, which turn it into termination signal (b))
   real(wp), parameter :: gs_gradient_guard = 1.0e-14_wp

contains

!> Follow one direction of the IRC with the Gonzalez-Schlegel scheme.
!>
!> On return `path` holds the points after the transition state, in order, with
!> their arc length from the transition state and their termination signal.
!> `fail` is true only for a hard error (a failed model evaluation or
!> eigensolve); the termination signals are not errors.
subroutine landscape_irc_gs_walk(env, model, settings, mass, x0, hess0, v, sign, &
      & path, fail)
   character(len=*), parameter :: source = 'landscape_irc_gs_walk'
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
   real(wp), allocatable :: q_cur(:), g_cur(:), q_new(:), g_new(:), x_new(:)
   real(wp) :: e_ts, e_cur, e_new, e_min, gnorm_cur, gnorm_new, s_cur, ds, step
   integer :: ndim, npoint, nrise, neval
   logical :: ok, micro_converged, recalc

   fail = .false.
   ndim = size(x0)
   step = settings%step_length
   allocate(sqrt_mass(ndim), hq(ndim, ndim), q_ts(ndim), g_ts(ndim))
   allocate(g_cart(ndim), q_cur(ndim), g_cur(ndim), q_new(ndim), g_new(ndim))
   allocate(x_new(ndim))

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

   ! seed the Hessian with the first secant pair (transition state -> point 1)
   call update_by_enum(settings%hessian_update, q_cur - q_ts, g_cur - g_ts, hq, ok)

   ! --- macro steps ------------------------------------------------------
   npoint = 1
   nrise = 0
   do
      if (npoint >= settings%max_steps) then
         path%term = p_landscape_irc_term_max_steps
         exit
      end if
      ! a vanishing gradient defines no direction: signal (b).  Without the
      ! guard a path started exactly at a stationary point (needs
      ! `--lirc-grad-tol 0`) would record duplicate points until signal (c).
      if (gnorm_cur <= gs_gradient_guard) then
         path%term = p_landscape_irc_term_grad
         exit
      end if
      ! signal (b): a stationary point was reached (RMS gradient per
      ! Cartesian component)
      if (gnorm_cur/sqrt(real(ndim, wp)) <= settings%grad_tol) then
         path%term = p_landscape_irc_term_grad
         exit
      end if

      recalc = .false.
      if (settings%hessian_recalc > 0) then
         recalc = mod(npoint, settings%hessian_recalc) == 0
      end if
      call landscape_irc_gs_step(env, model, settings, sqrt_mass, q_cur, g_cur, &
         & hq, step, recalc, q_new, x_new, e_new, g_new, neval, micro_converged, fail)
      if (fail) return
      if (.not. micro_converged) path%n_pinned = path%n_pinned + 1

      ! the step returns the mass weighted gradient; the Cartesian gradient is
      ! `g_i = g^q_i sqrt(m_i)` (the inverse of `landscape_irc_gradient_to_weighted`)
      g_cart = g_new*sqrt_mass
      gnorm_new = vec_norm(g_cart)
      ds = vec_norm(q_new - q_cur)
      s_cur = s_cur + ds
      call landscape_irc_path_add(path, x_new, e_new, s_cur, gnorm_new, &
         & vec_maxabs(g_cart), neval)
      npoint = npoint + 1

      ! signal (c): the energy has stopped setting a new minimum for
      ! `e_rise_steps` consecutive points, i.e. the descent has turned
      ! around (the implemented form of the PLAN "the energy rises again").
      ! The comparison is against the **running minimum**, not the previous
      ! point: near a minimum both integrators produce a short limit cycle
      ! (the sphere step of GS, the fixed arc length of LQA), so a strict
      ! `E_k > E_{k-1}` alternates and never fires (measured on the analytic
      ! Mueller-Brown surface, report 42).
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

end subroutine landscape_irc_gs_walk

!> One Gonzalez-Schlegel macro step: pivot + sphere constrained relaxation.
!>
!> Advances the path from `(q_cur, g_cur)` by one step length on the sphere of
!> radius `step/2` (see the module header).  The mass weighted Hessian `hq` is
!> updated in place with the configured formula along the micro cycles.  On
!> return `q_new` is the relaxed point, `e_new`/`g_new` its energy and
!> (Cartesian) gradient and `n_eval` the number of energy/gradient evaluations
!> spent.  The routine is shared by the GS walk and by the HPC/EulerPC
!> fallback of a failed corrector (PLAN section 6.5: "failure -> fall back to
!> one GS step and warn").
subroutine landscape_irc_gs_step(env, model, settings, sqrt_mass, q_cur, g_cur, &
      & hq, step, recalc, q_new, x_new, e_new, g_new, n_eval, micro_converged, fail)
   character(len=*), parameter :: source = 'landscape_irc_gs_step'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Potential
   class(landscape_energy_model), intent(inout) :: model
   !> IRC settings
   type(landscape_irc_settings), intent(in) :: settings
   !> `sqrt(mass)` (length 3N)
   real(wp), intent(in) :: sqrt_mass(:)
   !> Current point (bohr*amu^1/2)
   real(wp), intent(in) :: q_cur(:)
   !> Mass weighted gradient at the current point
   real(wp), intent(in) :: g_cur(:)
   !> Mass weighted Hessian, updated in place
   real(wp), intent(inout) :: hq(:, :)
   !> Step length (bohr*amu^1/2)
   real(wp), intent(in) :: step
   !> Rebuild the exact Hessian at the current point before the micro cycles
   logical, intent(in) :: recalc
   !> Relaxed next point (bohr*amu^1/2)
   real(wp), intent(out) :: q_new(:)
   !> Cartesian geometry of the next point (bohr)
   real(wp), intent(out) :: x_new(:)
   !> Energy of the next point (hartree)
   real(wp), intent(out) :: e_new
   !> Cartesian gradient of the next point (hartree/bohr)
   real(wp), intent(out) :: g_new(:)
   !> Number of energy/gradient evaluations spent
   integer, intent(out) :: n_eval
   !> True if the sphere relaxation converged
   logical, intent(out) :: micro_converged
   !> Failure flag
   logical, intent(out) :: fail

   real(wp), allocatable :: pivot(:), q_ref(:), g_ref(:), d(:), g_cart(:)
   real(wp) :: dlambda, kkt_shift
   integer :: imicro, ndim
   logical :: moved, s_fail, ok

   fail = .false.
   ndim = size(q_cur)
   allocate(pivot(ndim), q_ref(ndim), g_ref(ndim), d(ndim))
   allocate(g_cart(ndim))

   ! pivot and the first guess of the next point (both half a step)
   pivot = q_cur - 0.5_wp*step*(g_cur/gnorm_weighted(g_cur))
   q_new = q_cur - step*(g_cur/gnorm_weighted(g_cur))

   ! optional exact Hessian rebuild (before the micro cycles)
   if (recalc) then
      call landscape_irc_from_weighted(sqrt_mass, q_cur, x_new)
      call rebuild_hessian(env, model, sqrt_mass, x_new, hq, fail)
      if (fail) return
   end if

   ! micro cycles on the sphere of radius s/2 about the pivot
   q_ref = q_cur
   g_ref = g_cur
   n_eval = 0
   moved = .false.
   micro_converged = .false.
   do imicro = 1, max(1, settings%max_micro_cycles)
      call landscape_irc_from_weighted(sqrt_mass, q_new, x_new)
      call model%evaluate(x_new, e_new, g_cart, fail)
      if (fail) then
         call env%error("an IRC micro step could not be evaluated", source)
         return
      end if
      n_eval = n_eval + 1
      call landscape_irc_gradient_to_weighted(sqrt_mass, g_cart, g_new)
      call update_by_enum(settings%hessian_update, q_new - q_ref, &
         & g_new - g_ref, hq, ok)
      q_ref = q_new
      g_ref = g_new

      call landscape_irc_gs_lagrange_step(env, q_new, pivot, 0.5_wp*step, hq, &
         & g_new, d, dlambda, kkt_shift, s_fail)
      if (s_fail) then
         fail = .true.
         return
      end if
      moved = .false.
      if (vec_norm(d) <= settings%micro_step_thresh) then
         micro_converged = .true.
         exit
      end if
      q_new = project_sphere(q_new + d, pivot, 0.5_wp*step)
      moved = .true.
   end do
   if (moved) then
      call landscape_irc_from_weighted(sqrt_mass, q_new, x_new)
      call model%evaluate(x_new, e_new, g_cart, fail)
      if (fail) then
         call env%error("an IRC micro step could not be evaluated", source)
         return
      end if
      n_eval = n_eval + 1
      call landscape_irc_gradient_to_weighted(sqrt_mass, g_cart, g_new)
   end if
   if (.not. micro_converged .and. settings%printlevel > 1) then
      write(env%unit, '(1x,a)') &
         & "irc: micro cycles exhausted (the sphere relaxation did not converge)"
   end if

end subroutine landscape_irc_gs_step

!> Euclidean norm of the mass weighted gradient (the `|g^q|` of the pivot).
pure function gnorm_weighted(g) result(norm)
   !> Mass weighted gradient
   real(wp), intent(in) :: g(:)
   !> Norm
   real(wp) :: norm

   norm = vec_norm(g)
   if (norm <= tiny(1.0_wp)) norm = tiny(1.0_wp)

end function gnorm_weighted

!> Rebuild the mass weighted Hessian from the model at a Cartesian geometry.
subroutine rebuild_hessian(env, model, sqrt_mass, x, hq, fail)
   character(len=*), parameter :: source = 'landscape_irc_gs_rebuild_hessian'
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

!> Newton step of the equality constrained sphere relaxation (KKT step).
!>
!> The micro step advances the point `q` towards the minimum of the energy on
!> the sphere `|q - pivot| = R` by one Newton step of the equality constrained
!> problem
!>
!>     min E(q)   subject to   c(q) = -(|r|^2 - R^2) = 0,   r = q - pivot,
!>
!> i.e. the solution `(d, dlambda)` of the linearised KKT system of the
!> Lagrangian `L = E + lambda (|r|^2 - R^2)`,
!>
!>     [ H + 2 lambda I    2 r ] [ d  ]   [ -( g + 2 lambda r ) ]
!>     [ 2 r^T             0   ] [ dL ] = [ -( |r|^2 - R^2 )    ] .
!>
!> **Choice of the multiplier.**  `2 lambda = -( r^T g )/|r|^2` is the
!> multiplier of the current KKT residual: it is the value that makes the
!> residual `g + 2 lambda r` orthogonal to `r`, and it is the exact multiplier
!> of a constrained stationary point.  Using it (instead of a one dimensional
!> secant search for the constraint, whose residual is zero here by
!> construction, see below) is what makes the step a Newton step: it annihilates
!> the radial residual, so only the tangential residual `P g` is left to drive
!> the iteration, and the fixed point `d = 0` is exactly the tangent
!> stationarity `P g = 0` of the constrained minimum.
!>
!> **Level shift.**  The constrained Hessian is the *reduced* Hessian
!> `P (H + 2 lambda I) P` (`P = I - e_r e_r^T`), which may be indefinite.  When
!> its smallest tangent eigenvalue plus `2 lambda` is not positive, the step
!> from that multiplier would not be a descent direction, so `2 lambda` is
!> raised to the level shift `-eval_min + floor` that makes the reduced Hessian
!> positive definite (classical modified Newton / level shift of constrained
!> optimisation).  `floor` is `tangent_curvature_floor` relative to the largest
!> curvature.  `kkt_shift = 2 lambda` is returned so that a test can rebuild
!> the system.
!>
!> **Solution.**  Decompose `d = d_t + alpha e_r` with `d_t` tangential.  The
!> constraint row gives `alpha` directly, `2 |r| alpha = -(|r|^2 - R^2)` (zero
!> for a point on the sphere, and the only reason the routine has to be exact
!> off it); the tangential part of the first row is
!> `(P H P + 2 lambda P) d_t = -P g - alpha P H e_r`.  `P H P` is
!> diagonalised (`mctc_syev`, ascending) and the radial eigenvector (the one
!> with the largest overlap with `e_r`, eigenvalue 0 by construction) is dropped
!> from the sum.  `dlambda` follows from the radial part of the first row,
!> `dlambda = [ -(r^T g + 2 lambda |r|^2) - r^T (H + 2 lambda I) d ] / (2 |r|^2)`.
!>
!> **Trust region.**  The step is clamped to the sphere radius.  With the
!> correct (descent) direction the clamp is **inert** on every validated path
!> (measured on the GFN2 HCN/HNC and the Mueller-Brown baselines), but it is
!> retained as the guard against a nearly singular reduced Hessian, where
!> `2 lambda` is only the small floor and the step reverts to a huge
!> `-(P g)/(2 lambda)`.  Note that the historical evidence for the clamp -
!> "without it the forward path breaks down (25.27 instead of 4.05
!> bohr*amu^1/2)" - was measured on the *clamped tangent* step it replaced; a
!> clamped step is still tangential and the trial point is still projected onto
!> the sphere, so the constraint itself never depended on it.
subroutine landscape_irc_gs_lagrange_step(env, q, pivot, radius, hess, grad, &
      & d, dlambda, kkt_shift, fail)
   character(len=*), parameter :: source = 'landscape_irc_gs_lagrange_step'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Current point on the sphere (bohr*amu^1/2)
   real(wp), intent(in) :: q(:)
   !> Centre of the sphere (bohr*amu^1/2)
   real(wp), intent(in) :: pivot(:)
   !> Radius of the sphere (bohr*amu^1/2), the trust radius of the micro step
   real(wp), intent(in) :: radius
   !> Mass weighted Hessian (hartree/(bohr^2 amu))
   real(wp), intent(in) :: hess(:, :)
   !> Mass weighted gradient at `q` (hartree/(bohr*amu^1/2))
   real(wp), intent(in) :: grad(:)
   !> KKT Newton step (bohr*amu^1/2); its tangential part is the descent step
   real(wp), intent(out) :: d(:)
   !> Multiplier increment `dlambda` of the KKT system
   real(wp), intent(out) :: dlambda
   !> Level shift used, `kkt_shift = 2 lambda`
   real(wp), intent(out) :: kkt_shift
   !> Failure flag (the eigensolve failed)
   logical, intent(out) :: fail

   real(wp), allocatable :: er(:), he(:), proj(:, :), gt(:), evals(:), overlap(:)
   real(wp) :: rr, r2, rc, alpha, c, shift, denom, nd, lam_res, deficit, gfloor
   real(wp) :: r(size(q))
   real(wp) :: hd(size(grad))
   integer :: i, j, n, irad, nlog

   fail = .false.
   d = 0.0_wp
   dlambda = 0.0_wp
   kkt_shift = 0.0_wp
   n = size(q)
   r = q - pivot
   r2 = dot_product(r, r)
   rr = sqrt(r2)
   if (rr <= tiny(1.0_wp)) return
   allocate(er(n), he(n), gt(n))
   er = r/rr
   ! radial part of the step from the linearised constraint row, and the
   ! tangential residual of the KKT system
   rc = r2 - radius*radius
   alpha = -0.5_wp*rc/rr
   gt = grad - dot_product(grad, er)*er

   he = matmul(hess, er)
   c = dot_product(er, he)
   allocate(proj(n, n), source=0.0_wp)
   do j = 1, n
      do i = 1, n
         proj(i, j) = hess(i, j) - er(i)*he(j) - he(i)*er(j) + c*er(i)*er(j)
      end do
   end do
   proj = 0.5_wp*(proj + transpose(proj))

   allocate(evals(n))
   nlog = env%nLog
   call mctc_syev(env, proj, evals)
   if (landscape_log_failed(env, nlog)) then
      fail = .true.
      return
   end if

   ! the radial eigenvector is the null direction of P H P: the one with the
   ! largest overlap with the radial unit vector
   allocate(overlap(n), source=0.0_wp)
   do i = 1, n
      overlap(i) = abs(dot_product(proj(:, i), er))
   end do
   irad = maxloc(overlap, dim=1)

   ! multiplier of the current KKT residual, and the level shift that makes the
   ! reduced Hessian positive definite
   gfloor = max(tangent_curvature_floor, &
      & tangent_curvature_floor*max(1.0_wp, maxval(abs(evals))))
   lam_res = -0.5_wp*dot_product(r, grad)/r2
   shift = 2.0_wp*lam_res
   deficit = 0.0_wp
   if (n > 1) then
      deficit = huge(1.0_wp)
      do i = 1, n
         if (i == irad) cycle
         deficit = min(deficit, -evals(i) + gfloor)
      end do
   end if
   if (shift < deficit) shift = deficit
   kkt_shift = shift

   ! tangential part: (P H P + 2 lambda P) d_t = -P g - alpha P H e_r
   gt = -gt - alpha*(he - c*er)
   do i = 1, n
      if (i == irad) cycle
      denom = evals(i) + shift
      if (denom <= 0.0_wp) denom = gfloor
      d = d + proj(:, i)*(dot_product(proj(:, i), gt)/denom)
   end do
   d = d + alpha*er

   ! multiplier increment from the radial row of the KKT system
   hd = matmul(hess, d) + shift*d
   dlambda = (-(dot_product(r, grad) + shift*r2) - dot_product(r, hd))/ &
      & (2.0_wp*r2)

   ! Trust region of the micro step: the step is limited to the sphere radius.
   ! Inert with the constrained (descent) step of this routine - it only
   ! triggers for a nearly singular reduced Hessian, where the level shift is
   ! the tiny floor and the step would otherwise diverge.
   nd = vec_norm(d)
   if (nd > radius .and. nd > tiny(1.0_wp)) d = d*(radius/nd)

end subroutine landscape_irc_gs_lagrange_step

!> Project a point back onto the sphere about `pivot`.
pure function project_sphere(q, pivot, radius) result(qp)
   !> Point to project (bohr*amu^1/2)
   real(wp), intent(in) :: q(:)
   !> Centre (bohr*amu^1/2)
   real(wp), intent(in) :: pivot(:)
   !> Radius (bohr*amu^1/2)
   real(wp), intent(in) :: radius
   !> Projected point
   real(wp), allocatable :: qp(:)

   real(wp) :: rr

   qp = q - pivot
   rr = vec_norm(qp)
   if (rr <= tiny(1.0_wp)) then
      qp = q
      return
   end if
   qp = pivot + radius*qp/rr

end function project_sphere

end module xtb_landscape_irc_gs
