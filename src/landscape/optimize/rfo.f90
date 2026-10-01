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

!> Rational function optimization (RFO) step with trust region control.
!>
!> The RFO step is obtained from the augmented Newton step
!> `d = -sum_i (V_i.g)/(w_i - lambda) V_i`, where `(w_i, V_i)` is the spectral
!> decomposition of the Hessian.  For a minimisation the shifted matrix has to
!> be positive definite, so eigenvalues below `hlow` are lifted to `hlow`
!> before the step is computed.  If the unconstrained step (`lambda = 0`)
!> exceeds the trust radius, the shift is obtained from the secular equation
!> `|d(lambda)| = trust` by bisection on `lambda < min(w)`
!> (Banerjee et al., J. Phys. Chem. 89, 52 (1985); pysisyphus `RFO`).
!>
!> Conventions:
!>
!>  * `xtb_mctc_lapack::mctc_syev` returns *ascending* eigenvalues, the
!>    eigenvectors are the columns of the overwritten matrix.
!>  * the overall sign of an eigenvector is arbitrary; it drops out of the step
!>    because the step only contains the products `(V_i.g) V_i`.
!>
!> Units: Hessian in hartree/bohr^2, gradient in hartree/bohr, trust radius and
!> step in bohr.
module xtb_landscape_rfo
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_lapack, only : mctc_syev
   use xtb_type_environment, only : TEnvironment
   use xtb_landscape_settings, only : landscape_log_failed
   implicit none(type, external)
   private

   public :: landscape_rfo_step, landscape_rfo_update_trust

   !> Maximum number of bracket refinements of the shift
   integer, parameter :: max_bracket = 200

contains

!> Compute an RFO step inside a trust region.
!>
!> `predicted` is the energy decrease predicted by the quadratic model with the
!> lifted (positive definite) Hessian; the caller uses it to compute the trust
!> region ratio `rho = (E - E_trial)/predicted`.  The routine reports failure
!> through `fail` if the eigenvalue solver breaks down or if no descent step
!> could be constructed.
subroutine landscape_rfo_step(env, hess, gradient, trust, hlow, step, predicted, fail, &
      & evals_eps, mu_margin, max_bisect_it)
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Hessian (hartree/bohr^2)
   real(wp), intent(in) :: hess(:, :)
   !> Gradient (hartree/bohr)
   real(wp), intent(in) :: gradient(:)
   !> Trust radius (bohr)
   real(wp), intent(in) :: trust
   !> Curvature floor of the negative eigenvalues (hartree/bohr^2)
   real(wp), intent(in) :: hlow
   !> RFO step (bohr)
   real(wp), intent(out) :: step(:)
   !> Predicted energy decrease (hartree)
   real(wp), intent(out) :: predicted
   !> Failure flag
   logical, intent(out) :: fail
   !> Relative denominator guard of the secular equation, defaults to 1e-10
   real(wp), intent(in), optional :: evals_eps
   !> Margin between the shift bracket and the smallest eigenvalue, defaults
   !> to 1e-8
   real(wp), intent(in), optional :: mu_margin
   !> Maximum number of shift bisections, defaults to 60
   integer, intent(in), optional :: max_bisect_it

   real(wp), allocatable :: work(:, :), eval(:), f(:), hx(:), buffer(:)
   real(wp) :: lambda, wmin, gap, lo, hi, mid, nrm, norm0, model
   real(wp) :: eps_guard, margin
   logical :: failed
   integer :: i, n, ibracket, ibisect, max_bisect, nlog

   fail = .false.
   step = 0.0_wp
   predicted = 0.0_wp
   eps_guard = 1.0e-10_wp
   if (present(evals_eps)) eps_guard = evals_eps
   margin = 1.0e-8_wp
   if (present(mu_margin)) margin = mu_margin
   max_bisect = 60
   if (present(max_bisect_it)) max_bisect = max(1, max_bisect_it)
   n = size(gradient)
   if (n == 0) return
   if (trust <= 0.0_wp) then
      fail = .true.
      return
   end if

   allocate(work(n, n), eval(n), f(n), hx(n), buffer(n))
   work = hess
   work = 0.5_wp*(work + transpose(work))
   nlog = env%nLog
   call mctc_syev(env, work, eval)
   ! Only inspect the messages appended by this call; env%check() is cumulative
   ! and would falsely report a failure under --strict after any warning.
   failed = landscape_log_failed(env, nlog)
   if (failed) then
      fail = .true.
      return
   end if

   do i = 1, n
      eval(i) = max(eval(i), hlow)
   end do

   f = matmul(transpose(work), gradient)

   if (all(abs(f) <= tiny(1.0_wp))) then
      step = 0.0_wp
      predicted = 0.0_wp
      fail = .true.
      return
   end if

   call rfo_step_norm(0.0_wp, f, eval, norm0)
   if (norm0 <= trust) then
      lambda = 0.0_wp
   else
      wmin = huge(1.0_wp)
      do i = 1, n
         if (abs(f(i)) > tiny(1.0_wp)) wmin = min(wmin, eval(i))
      end do
      gap = max(1.0_wp, abs(wmin))
      lo = wmin - gap
      call rfo_step_norm(lo, f, eval, nrm)
      ibracket = 0
      do while (nrm > trust .and. ibracket < max_bracket)
         gap = 2.0_wp*gap
         lo = wmin - gap
         call rfo_step_norm(lo, f, eval, nrm)
         ibracket = ibracket + 1
      end do
      if (nrm > trust) then
         fail = .true.
         return
      end if
      hi = wmin - max(margin, eps_guard*abs(wmin))
      do ibisect = 1, max_bisect
         mid = 0.5_wp*(lo + hi)
         call rfo_step_norm(mid, f, eval, nrm)
         if (nrm > trust) then
            hi = mid
         else
            lo = mid
         end if
      end do
      lambda = lo
   end if

   do i = 1, n
      step = step - (f(i)/(eval(i) - lambda))*work(:, i)
   end do

   ! predicted decrease of the (lifted) quadratic model
   buffer = matmul(transpose(work), step)
   hx = matmul(work, eval*buffer)
   model = dot_product(gradient, step) + 0.5_wp*dot_product(step, hx)
   predicted = -model
   if (predicted <= 0.0_wp .or. dot_product(gradient, step) >= 0.0_wp) then
      predicted = 0.0_wp
      step = 0.0_wp
      fail = .true.
   end if

end subroutine landscape_rfo_step

!> Update the trust radius from the ratio of actual to predicted decrease.
!>
!> The radius is shrunk if `rho < 0.25` and expanded if `rho > 0.75`, always
!> inside `[trust_min, trust_max]`.
pure subroutine landscape_rfo_update_trust(trust, rho, eta_shrink, eta_expand, &
      & trust_min, trust_max)
   !> Trust radius (bohr), updated in place
   real(wp), intent(inout) :: trust
   !> Ratio of actual to predicted decrease
   real(wp), intent(in) :: rho
   !> Shrink factor for poor steps
   real(wp), intent(in) :: eta_shrink
   !> Expansion factor for good steps
   real(wp), intent(in) :: eta_expand
   !> Lower bound of the trust radius (bohr)
   real(wp), intent(in) :: trust_min
   !> Upper bound of the trust radius (bohr)
   real(wp), intent(in) :: trust_max

   if (rho < 0.25_wp) then
      trust = max(trust_min, eta_shrink*trust)
   else if (rho > 0.75_wp) then
      trust = min(trust_max, eta_expand*trust)
   end if

end subroutine landscape_rfo_update_trust

!> Norm of the shifted RFO step for a trial shift.
pure subroutine rfo_step_norm(lam, f, eval, nrm)
   !> Trial shift
   real(wp), intent(in) :: lam
   !> Gradient in the eigenbasis
   real(wp), intent(in) :: f(:)
   !> Lifted eigenvalues
   real(wp), intent(in) :: eval(:)
   !> Resulting step norm
   real(wp), intent(out) :: nrm

   real(wp) :: acc
   integer :: i

   acc = 0.0_wp
   do i = 1, size(f)
      acc = acc + (f(i)/(eval(i) - lam))**2
   end do
   nrm = sqrt(acc)

end subroutine rfo_step_norm

end module xtb_landscape_rfo
