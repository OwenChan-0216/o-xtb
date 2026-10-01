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

!> Single ended restricted step P-RFO (B-P-RFO, PLAN section 6.3).
!>
!> The step has the same double shift structure as the P-RFO of
!> `xtb_landscape_saddle_prfo`:
!>
!> ```text
!> dq = dq_k + dq_n,   dq_k = -(F_k V_k)/(b_k - lambda_p),
!>                     dq_i = -(F_i V_i)/(b_i - lambda_n), i /= k
!> ```
!>
!> The difference is the trust region.  A classical P-RFO step is the
!> unconstrained Newton-like step of Eq. 4.18 and the trust radius only clips
!> it afterwards; the restricted step variant partitions the radius between the
!> two subspaces instead:
!>
!> ```text
!> |dq_k| <= r_p = alpha       * trust          (uphill subspace, 1 mode)
!> |dq_n| <= r_n = sqrt(1 - alpha^2) * trust    (downhill subspace, n-1 modes)
!> ```
!>
!> The two subspaces are orthogonal, so `|dq|^2 <= r_p^2 + r_n^2 = trust^2`.
!> The restriction is active only where it is needed: as long as the P-RFO
!> component of a subspace stays inside its sub-radius it is used unchanged, so
!> the search reduces to the double shift method near the stationary point
!> (where the unconstrained step shrinks to zero and the displacement
!> convergence criteria become reachable).  Only a component that exceeds its
!> sub-radius is rescaled: the uphill one analytically, the downhill one by
!> solving `sum_{i/=k} (F_i/(b_i - lambda_n))^2 = r_n^2` for `lambda_n` by
!> bisection.  That bisection is the **micro iteration** of the restricted step
!> variant (`max_micro_cycles`, pysisyphus `RS_PRFO`); `alpha = 1/2` splits the
!> radius evenly.
!>
!> This implementation is single ended on purpose: it never evaluates batches
!> of geometries (the batch-GPU variant is excluded by PLAN decision D2).
!>
!> Units: Hessian in hartree/bohr^2, gradient in hartree/bohr, displacements
!> and trust radii in bohr, energies in hartree.
module xtb_landscape_saddle_bprfo
   use xtb_mctc_accuracy, only : wp
   use xtb_type_environment, only : TEnvironment
   use xtb_landscape_coords, only : vec_norm
   use xtb_landscape_saddle_eigenfollow, only : landscape_spectrum, &
      & landscape_curvature_noise_tol, landscape_rfo_downhill_shift
   implicit none(type, external)
   private

   public :: landscape_bprfo_step

contains

!> Restricted step B-P-RFO displacement.
!>
!> `alpha` is the fraction of the trust radius assigned to the uphill
!> subspace; the downhill subspace receives the complementary fraction.  The
!> optional outputs expose the two shifts and the curvature lift for reporting
!> and tests.
subroutine landscape_bprfo_step(env, hess, gradient, trans, trust, alpha, hlow, &
      & step, predicted, fail, evals_eps, mu_margin, max_micro_cycles, &
      & lambda_p, lambda_n, lifted, lifted_evals, warn)
   character(len=*), parameter :: source = 'landscape_bprfo_step'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Hessian (hartree/bohr^2)
   real(wp), intent(in) :: hess(:, :)
   !> Gradient (hartree/bohr)
   real(wp), intent(in) :: gradient(:)
   !> Transition vector (unit, Cartesian)
   real(wp), intent(in) :: trans(:)
   !> Trust radius (bohr)
   real(wp), intent(in) :: trust
   !> Fraction of the radius assigned to the uphill subspace
   real(wp), intent(in) :: alpha
   !> Curvature floor of the downhill modes (hartree/bohr^2)
   real(wp), intent(in) :: hlow
   !> B-P-RFO step (bohr)
   real(wp), intent(out) :: step(:)
   !> Predicted energy change of the quadratic model (hartree)
   real(wp), intent(out) :: predicted
   !> Failure flag
   logical, intent(out) :: fail
   !> Relative denominator guard, defaults to 1e-10
   real(wp), intent(in), optional :: evals_eps
   !> Margin of the `lambda_n` bracket, defaults to 1e-8
   real(wp), intent(in), optional :: mu_margin
   !> Maximum number of micro iterations, defaults to 50
   integer, intent(in), optional :: max_micro_cycles
   !> Shift of the uphill component
   real(wp), intent(out), optional :: lambda_p
   !> Shift of the downhill subspace
   real(wp), intent(out), optional :: lambda_n
   !> True if at least one downhill eigenvalue was lifted to `hlow`
   logical, intent(out), optional :: lifted
   !> Original eigenvalues that were lifted to `hlow` (hartree/bohr^2)
   real(wp), allocatable, intent(out), optional :: lifted_evals(:)
   !> Emit the curvature lift warning, defaults to `.true.`
   logical, intent(in), optional :: warn

   real(wp), allocatable :: evals(:), evecs(:, :), f(:), coeff(:), lifted_list(:)
   real(wp) :: fk, bk, r_p, r_n, lam_p, lam_n, denom, nrm_down
   real(wp) :: nrm, shs, eps_guard, margin, neg_tol
   character(len=160) :: msg
   logical :: was_lifted, solved, restricted, emit_warning
   integer :: n, i, k, nneg, n_lifted, n_micro

   fail = .false.
   step = 0.0_wp
   predicted = 0.0_wp
   if (present(lambda_p)) lambda_p = 0.0_wp
   if (present(lambda_n)) lambda_n = 0.0_wp
   if (present(lifted)) lifted = .false.

   eps_guard = 1.0e-10_wp
   if (present(evals_eps)) eps_guard = evals_eps
   margin = 1.0e-8_wp
   if (present(mu_margin)) margin = mu_margin
   n_micro = 50
   if (present(max_micro_cycles)) n_micro = max(1, max_micro_cycles)

   if (trust <= 0.0_wp) then
      call env%error("the B-P-RFO trust radius must be positive", source)
      fail = .true.
      return
   end if
   if (alpha <= 0.0_wp .or. alpha >= 1.0_wp) then
      call env%error("the B-P-RFO alpha must be strictly between 0 and 1", source)
      fail = .true.
      return
   end if

   call landscape_spectrum(env, hess, evals, evecs, fail)
   if (fail) return
   n = size(evals)
   if (size(gradient) /= n .or. size(step) /= n) then
      call env%error("the B-P-RFO step requires a matching gradient", source)
      fail = .true.
      return
   end if

   k = 1
   if (size(trans) == n) then
      k = maxloc(abs(matmul(transpose(evecs), trans)), dim=1)
   end if

   ! see `xtb_landscape_saddle_prfo`: a *noise-visible* negative eigenvalue in
   ! the downhill subspace gates the lift to the `hlow` floor, which then raises
   ! the whole downhill subspace (so the radius equation stays solvable and a
   ! near-zero mode cannot blow up the step).  Eigenvalues within round off of
   ! the rigid body directions do not gate it (H4).
   neg_tol = landscape_curvature_noise_tol(evals)
   nneg = 0
   do i = 1, n
      if (i == k) cycle
      if (evals(i) < -neg_tol) nneg = nneg + 1
   end do
   was_lifted = .false.
   n_lifted = 0
   allocate(lifted_list(n))
   if (nneg > 0) then
      do i = 1, n
         if (i == k) cycle
         if (evals(i) < hlow) then
            n_lifted = n_lifted + 1
            lifted_list(n_lifted) = evals(i)
            evals(i) = hlow
         end if
      end do
      was_lifted = n_lifted > 0
   end if
   emit_warning = .true.
   if (present(warn)) emit_warning = warn

   allocate(f(n), coeff(n), source=0.0_wp)
   do i = 1, n
      f(i) = dot_product(evecs(:, i), gradient)
   end do

   ! radius partition
   r_p = alpha*trust
   r_n = sqrt(max(1.0_wp - alpha**2, 1.0e-12_wp))*trust

   fk = f(k)
   bk = evals(k)

   ! uphill component from the double shift, restricted to r_p if necessary
   if (abs(fk) <= eps_guard) then
      coeff(k) = 0.0_wp
      lam_p = bk
   else
      lam_p = 0.5_wp*bk + 0.5_wp*sqrt(bk**2 + 4.0_wp*fk**2)
      denom = bk - lam_p
      if (abs(denom) <= eps_guard) then
         coeff(k) = 0.0_wp
      else
         coeff(k) = -fk/denom
      end if
      if (abs(coeff(k)) > r_p) then
         coeff(k) = sign(r_p, coeff(k))
         lam_p = bk + abs(fk)/r_p
      end if
   end if

   ! downhill component: the P-RFO shift, replaced by the radius equation when
   ! the resulting step exceeds the downhill sub-radius
   call landscape_rfo_downhill_shift(env, f, evals, k, margin, n_micro, lam_n, &
      & solved, fail, source)
   if (fail) then
      call env%error("the B-P-RFO downhill shift could not be solved", source)
      return
   end if
   call fill_downhill(coeff, f, evals, k, lam_n)
   nrm_down = 0.0_wp
   if (solved) then
      do i = 1, n
         if (i == k) cycle
         nrm_down = nrm_down + coeff(i)**2
      end do
      nrm_down = sqrt(nrm_down)
   end if

   restricted = .false.
   if (nrm_down > r_n) then
      call solve_downhill_radius(env, f, evals, k, r_n, margin, n_micro, &
         & lam_n, restricted, fail, source)
      if (fail) then
         call env%error("the B-P-RFO downhill radius equation could not be "//&
            & "solved", source)
         return
      end if
      call fill_downhill(coeff, f, evals, k, lam_n)
   end if

   do i = 1, n
      step = step + coeff(i)*evecs(:, i)
   end do

   if (was_lifted .and. emit_warning) then
      write(msg, '(a,i0,a,es12.4,a)') "the downhill subspace has ", n_lifted, &
         & " negative curvature eigenvalue(s) (most negative ", &
         & minval(lifted_list(1:n_lifted)), &
         & "); the downhill modes were lifted to hlow"
      call env%warning(trim(msg), source)
   end if
   if (present(lifted_evals)) then
      if (n_lifted > 0) then
         lifted_evals = lifted_list(1:n_lifted)
      else
         allocate(lifted_evals(0))
      end if
   end if

   nrm = vec_norm(step)
   if (nrm > trust) step = (trust/nrm)*step

   shs = 0.0_wp
   do i = 1, n
      shs = shs + evals(i)*dot_product(evecs(:, i), step)**2
   end do
   predicted = -(dot_product(gradient, step) + 0.5_wp*shs)

   if (present(lambda_p)) lambda_p = lam_p
   if (present(lambda_n)) lambda_n = lam_n
   if (present(lifted)) lifted = was_lifted

end subroutine landscape_bprfo_step

!> Fill the downhill coefficients `-F_i/(b_i - lambda_n)` for `i /= k`.
pure subroutine fill_downhill(coeff, f, b, k, lambda)
   !> Coefficient vector, the downhill entries are overwritten
   real(wp), intent(inout) :: coeff(:)
   !> Gradient in the eigenbasis
   real(wp), intent(in) :: f(:)
   !> (Lifted) eigenvalues
   real(wp), intent(in) :: b(:)
   !> Index of the uphill mode
   integer, intent(in) :: k
   !> Downhill shift
   real(wp), intent(in) :: lambda

   real(wp) :: denom
   integer :: i

   do i = 1, size(b)
      if (i == k) cycle
      denom = b(i) - lambda
      if (abs(denom) <= tiny(1.0_wp)) then
         coeff(i) = 0.0_wp
      else
         coeff(i) = -f(i)/denom
      end if
   end do

end subroutine fill_downhill

!> Solve `sum_{i/=k} (F_i/(b_i - lambda))^2 = radius^2` for `lambda`.
!>
!> The residual is strictly increasing in `lambda` and the root lies below
!> `min_{i/=k} b_i`; the bracket is opened by the same doubling scheme as the
!> RFO secular equation and then bisected (`max_micro_cycles` iterations).
subroutine solve_downhill_radius(env, f, b, k, radius, margin, n_micro, &
      & lambda, solved, fail, source)
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Gradient in the eigenbasis
   real(wp), intent(in) :: f(:)
   !> (Lifted) eigenvalues
   real(wp), intent(in) :: b(:)
   !> Index of the uphill mode
   integer, intent(in) :: k
   !> Target norm of the downhill step (bohr)
   real(wp), intent(in) :: radius
   !> Margin below the smallest downhill eigenvalue
   real(wp), intent(in) :: margin
   !> Maximum number of micro iterations
   integer, intent(in) :: n_micro
   !> Downhill shift
   real(wp), intent(out) :: lambda
   !> True if the restriction was active
   logical, intent(out) :: solved
   !> Failure flag
   logical, intent(out) :: fail
   !> Name of the calling routine
   character(len=*), intent(in) :: source

   real(wp) :: bmin, lo, hi, mid, gap
   integer :: i, n, it

   fail = .false.
   solved = .false.
   lambda = 0.0_wp
   n = size(b)

   bmin = huge(1.0_wp)
   do i = 1, n
      if (i == k) cycle
      bmin = min(bmin, b(i))
   end do
   if (bmin >= huge(1.0_wp)) then
      ! a single mode: there is nothing to minimise
      lambda = -1.0_wp
      return
   end if

   ! a downhill subspace whose unconstrained step already fits the radius
   ! needs no shift at all
   if (downhill_residual(0.0_wp, radius, f, b, k) <= 0.0_wp) then
      lambda = 0.0_wp
      return
   end if
   solved = .true.

   hi = bmin - max(margin, 1.0e-14_wp*max(1.0_wp, abs(bmin)))
   gap = max(1.0_wp, abs(hi))
   lo = min(hi, 0.0_wp) - gap
   it = 0
   do while (downhill_residual(lo, radius, f, b, k) >= 0.0_wp .and. it < 400)
      lo = lo - gap
      it = it + 1
   end do
   if (downhill_residual(lo, radius, f, b, k) >= 0.0_wp) then
      call env%warning("the B-P-RFO bracketing did not enclose the root", source)
      fail = .true.
      return
   end if

   do i = 1, n_micro
      mid = 0.5_wp*(lo + hi)
      if (downhill_residual(mid, radius, f, b, k) < 0.0_wp) then
         lo = mid
      else
         hi = mid
      end if
   end do
   lambda = 0.5_wp*(lo + hi)
   if (abs(downhill_residual(lambda, radius, f, b, k)) > &
         & 1.0e-6_wp*max(1.0_wp, radius**2)) then
      call env%warning("the B-P-RFO downhill radius equation is not "//&
         & "satisfied to tolerance", source)
   end if

end subroutine solve_downhill_radius

!> Residual `sum_{i/=k} (F_i/(b_i - lambda))^2 - radius^2` of the downhill
!> radius equation.  Strictly increasing in `lambda` for `lambda < min_i b_i`.
pure function downhill_residual(lambda, radius, f, b, k) result(value)
   !> Trial shift
   real(wp), intent(in) :: lambda
   !> Target norm of the downhill step (bohr)
   real(wp), intent(in) :: radius
   !> Gradient in the eigenbasis
   real(wp), intent(in) :: f(:)
   !> (Lifted) eigenvalues
   real(wp), intent(in) :: b(:)
   !> Index of the uphill mode
   integer, intent(in) :: k
   !> Residual
   real(wp) :: value

   real(wp) :: denom
   integer :: i

   value = -radius**2
   do i = 1, size(b)
      if (i == k) cycle
      denom = b(i) - lambda
      if (abs(denom) <= tiny(1.0_wp)) cycle
      value = value + (f(i)/denom)**2
   end do

end function downhill_residual

end module xtb_landscape_saddle_bprfo
