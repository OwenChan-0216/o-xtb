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
!>     micro step is a curvature shifted Newton step in the tangent space of
!>     the sphere (the projected Hessian `P H P`, `P = I - e_r e_r^T`), with
!>     the negative curvatures floored so the step stays a descent step; the
!>     trial point is projected back onto the sphere after every step.  The
!>     micro cycle converges when the step norm falls below
!>     `micro_step_thresh`, or is stopped after `max_micro_cycles`.
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
!> Cost of the sphere relaxation (measured, M6 validation report 44)
!> -------------------------------------------------------------------
!> The inner sphere relaxation is **the most expensive integrator of the
!> suite and the least accurate one**, and `gs` is therefore **not the default
!> method** any more (the default is `hpc`, M6 behaviour change recorded in
!> PLAN section 12.15).  All four facts below are measured, not conjectured:
!>
!>  1. **Cost.**  A GFN2 HCN/HNC run at step 0.10 costs **16.9 E/g per point
!>     forward and 20.3 backward** (PLAN section 6.5 expected 3-5).  HPC needs
!>     1.98, LQA 1.00: GS is 8.5 times more expensive than the default.
!>  2. **Accuracy.**  On the analytic Mueller-Brown surface the maximum
!>     deviation from the fine reference path is **0.040 bohr**, against
!>     0.0066 (LQA), 0.0022 (HPC) and 0.026 (EulerPC) - the largest of the
!>     four methods.  On GFN2 the endpoint error is non-monotonic in the step
!>     length (5.1e-5 at 0.05, 2.4e-5 at 0.10, 8e-9 at 0.20 bohr*amu^1/2).
!>  3. **Root cause.**  The micro cycle accepts a point when the tangent
!>     Newton step falls below `micro_step_thresh` (1e-3), but the measured
!>     Newton step is **1.8-2.4 bohr*amu^1/2**, i.e. 36-48 times the sphere
!>     radius `step_length/2` (0.05); the trust region of `sphere_newton`
!>     therefore clamps every micro step and the criterion is never met.  The
!>     cycle ends in a **two cycle** (measured this round with an independent
!>     spherical reference: the returned point is 3.4e-4 hartree above the
!>     constrained minimum and the alternating point 1.3e-3 hartree, with
!>     **identical values at micro cycle budgets 5, 20, 21 and 200**, so the
!>     deviation is structural and not a budget question).  On a GFN2 path 33
!>     of 42 forward and 38 of 40 backward points are stopped by
!>     `max_micro_cycles` instead of the criterion (counted in
!>     `landscape_irc_path%n_pinned`, printed in `irc.log`); the points of the
!>     final approach to the minimum do converge, in two evaluations.  The
!>     trust region is nevertheless required: removing it breaks the forward
!>     path (measured: 25.27 instead of 4.05 bohr*amu^1/2, stopped by the step
!>     budget, `noclamp` injection of `46-m6-fix-report.md`).
!>  4. **Planned fix (open item, not implemented).**  Replace the clamped
!>     tangent step by a properly constrained step - the equality constrained
!>     Lagrange step of the MAPLE reference, whose Newton step lies on the
!>     sphere by construction - and expect **3-4 times fewer evaluations**
!>     (report 44 section 7.2).  PLAN section 6.5 lists this as an open item
!>     with its acceptance route; it was deliberately **not** done in the M6
!>     final round, because the GS behaviour baseline of report 42 had just
!>     been verified bitwise and an algorithmic change on top of it could not
!>     have been distinguished from a regression.
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

   !> Relative floor of the curvature shift of the tangent space Newton step
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

      call sphere_newton(env, q_new, pivot, 0.5_wp*step, hq, g_new, d, s_fail)
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

!> Curvature shifted Newton step in the tangent space of the IRC sphere.
!>
!> The tangent space of the sphere `|q - pivot| = R` at `q` is spanned by the
!> two directions orthogonal to the radial unit vector `e_r`.  The step solves
!> the projected Newton system `(P H P) d = -P g` with the negative (and the
!> numerically vanishing) tangent curvatures floored at a positive shift, so
!> that the step is a descent step even when the Hessian is indefinite.
!> `P H P` is diagonalised (`mctc_syev`, eigenvalues ascending) and the radial
!> eigenvector (the one with the largest overlap with `e_r`, eigenvalue 0 by
!> construction) is dropped from the sum.
subroutine sphere_newton(env, q, pivot, radius, hess, grad, d, fail)
   character(len=*), parameter :: source = 'landscape_irc_gs_sphere_newton'
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
   !> Tangent step (bohr*amu^1/2)
   real(wp), intent(out) :: d(:)
   !> Failure flag (the eigensolve failed)
   logical, intent(out) :: fail

   real(wp), allocatable :: er(:), he(:), proj(:, :), gt(:), evals(:), overlap(:)
   real(wp) :: rr, c, shift, denom, nd
   integer :: i, j, n, irad, nlog

   fail = .false.
   d = 0.0_wp
   n = size(q)
   rr = vec_norm(q - pivot)
   if (rr <= tiny(1.0_wp)) return
   allocate(er(n), he(n), gt(n))
   er = (q - pivot)/rr
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

   ! curvature shift: floor every tangent curvature at a small positive value
   shift = 0.0_wp
   do i = 1, n
      if (i == irad) cycle
      shift = max(shift, -evals(i))
   end do
   shift = shift + max(tangent_curvature_floor, &
      & tangent_curvature_floor*max(1.0_wp, maxval(abs(evals))))

   ! accumulate the Newton step over the tangent eigenvectors
   do i = 1, n
      if (i == irad) cycle
      denom = max(evals(i), shift)
      d = d - proj(:, i)*(dot_product(proj(:, i), gt)/denom)
   end do
   ! Trust region of the micro step: the tangent step is limited to the sphere
   ! radius.  **Measured on the GFN2 HCN/HNC transition state** (this round, the
   ! injection experiment of `46-m6-fix-report.md`): without the limit the GS
   ! forward path breaks down - it wanders 25.27 bohr*amu^1/2 (256 macro steps,
   ! stopped by the budget) instead of reaching the HNC minimum after 4.05,
   ! because the unconstrained step (1.8-2.4) is projected to the far side of
   ! the sphere.  With the limit the path is correct.  The limit does **not**
   ! make the micro cycle converge: it still ends in a two cycle whose two
   ! points are 3.4e-4 / 1.3e-3 hartree above the constrained minimum (the same
   ! values at micro cycle budgets 5, 20, 21 and 200), which is the cost
   ! documented in the module header.
   nd = vec_norm(d)
   if (nd > radius .and. nd > tiny(1.0_wp)) d = d*(radius/nd)

end subroutine sphere_newton

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
