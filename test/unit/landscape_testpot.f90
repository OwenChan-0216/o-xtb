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

!> Analytic test potentials for the landscape unit tests.
!>
!> The potentials implement the injectable `landscape_energy_model` interface
!> of `xtb_landscape_engine`, so the optimisers can be validated against
!> problems with a known analytical solution without running a single SCF.
!>
!> Units: energies in hartree, coordinates in bohr, gradients in hartree/bohr
!> and Hessian elements in hartree/bohr^2.
!>
!>  * `landscape_harmonic_model` - anisotropic harmonic oscillator with
!>    arbitrary dimension, exact minimiser `x0`.
!>  * `landscape_rosenbrock_model` - Rosenbrock banana function
!>    `f = (a - x)^2 + b (y - x^2)^2`, minimum at `(a, a^2)`, strongly convex
!>    near the minimum.
!>  * `landscape_muller_brown_model` - Mueller-Brown surface (Mueller & Brown,
!>    Theor. Chim. Acta 53, 75 (1979)); the dimensionless surface is
!>    interpreted as kcal/mol and converted to hartree.  It has the two
!>    minima `(-0.558, 1.442)` (global) and `(0.623, 0.028)` as well as the
!>    saddle point `(-0.822, 0.624)`.
module xtb_landscape_testpot
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_convert, only : kcaltoau
   use xtb_landscape_engine, only : landscape_energy_model
   implicit none(type, external)
   private

   public :: landscape_harmonic_model, new_harmonic_model
   public :: landscape_rosenbrock_model, new_rosenbrock_model
   public :: landscape_muller_brown_model, new_muller_brown_model

   !> Anisotropic harmonic oscillator, `E = 1/2 sum_i k_i (x_i - x0_i)^2`.
   !>
   !> `k` are the force constants in hartree/bohr^2 and `x0` the exact
   !> minimiser in bohr; both are element-wise in the order of the flattened
   !> coordinate vector.
   type, extends(landscape_energy_model) :: landscape_harmonic_model
      !> Force constants (hartree/bohr^2)
      real(wp), allocatable :: k(:)
      !> Position of the minimum (bohr)
      real(wp), allocatable :: x0(:)
   contains
      !> Energy and gradient
      procedure :: evaluate => harmonic_evaluate
      !> Exact Hessian
      procedure :: hessian => harmonic_hessian
   end type landscape_harmonic_model

   !> Rosenbrock function `f = (a - x)^2 + b (y - x^2)^2` in two dimensions.
   !>
   !> Default parameters `a = 1`, `b = 100` place the minimum at `(1, 1)`.
   type, extends(landscape_energy_model) :: landscape_rosenbrock_model
      !> Parameter `a` of the banana term
      real(wp) :: a = 1.0_wp
      !> Parameter `b` of the quadratic coupling term
      real(wp) :: b = 100.0_wp
   contains
      !> Energy and gradient
      procedure :: evaluate => rosenbrock_evaluate
      !> Exact Hessian
      procedure :: hessian => rosenbrock_hessian
   end type landscape_rosenbrock_model

   !> Mueller-Brown surface, sum of four Gaussians
   !> `V = sum_i A_i exp(a_i u_i^2 + b_i u_i v_i + c_i v_i^2)` with
   !> `u_i = x - x0_i`, `v_i = y - y0_i`.
   type, extends(landscape_energy_model) :: landscape_muller_brown_model
      !> Gaussian amplitudes
      real(wp) :: amplitude(4) = [-200.0_wp, -100.0_wp, -170.0_wp, 15.0_wp]
      !> Quadratic exponents of `u^2`
      real(wp) :: expa(4) = [-1.0_wp, -1.0_wp, -6.5_wp, 0.7_wp]
      !> Bilinear exponents of `u v`
      real(wp) :: expb(4) = [0.0_wp, 0.0_wp, 11.0_wp, 0.6_wp]
      !> Quadratic exponents of `v^2`
      real(wp) :: expc(4) = [-10.0_wp, -10.0_wp, -6.5_wp, 0.7_wp]
      !> Gaussian centres in `x`
      real(wp) :: x0(4) = [1.0_wp, 0.0_wp, -0.5_wp, -1.0_wp]
      !> Gaussian centres in `y`
      real(wp) :: y0(4) = [0.0_wp, 0.5_wp, 1.5_wp, 1.0_wp]
      !> Energy scale factor (dimensionless surface -> hartree)
      real(wp) :: scale = kcaltoau
   contains
      !> Energy and gradient
      procedure :: evaluate => muller_brown_evaluate
      !> Exact Hessian
      procedure :: hessian => muller_brown_hessian
   end type landscape_muller_brown_model

contains

!> Construct an anisotropic harmonic oscillator.
subroutine new_harmonic_model(self, k, x0)
   !> New model
   type(landscape_harmonic_model), intent(out) :: self
   !> Force constants (hartree/bohr^2)
   real(wp), intent(in) :: k(:)
   !> Exact minimiser (bohr)
   real(wp), intent(in) :: x0(:)

   self%k = k
   self%x0 = x0

end subroutine new_harmonic_model

!> Construct a Rosenbrock function.
subroutine new_rosenbrock_model(self, a, b)
   !> New model
   type(landscape_rosenbrock_model), intent(out) :: self
   !> Parameter `a`
   real(wp), intent(in), optional :: a
   !> Parameter `b`
   real(wp), intent(in), optional :: b

   if (present(a)) self%a = a
   if (present(b)) self%b = b

end subroutine new_rosenbrock_model

!> Construct a Mueller-Brown surface.
subroutine new_muller_brown_model(self, scale)
   !> New model
   type(landscape_muller_brown_model), intent(out) :: self
   !> Energy scale factor, defaults to the kcal/mol -> hartree conversion
   real(wp), intent(in), optional :: scale

   if (present(scale)) self%scale = scale

end subroutine new_muller_brown_model

!> Energy and gradient of the anisotropic harmonic oscillator
subroutine harmonic_evaluate(self, x, energy, gradient, fail)
   !> Model
   class(landscape_harmonic_model), intent(inout) :: self
   !> Coordinates (bohr)
   real(wp), intent(in) :: x(:)
   !> Energy (hartree)
   real(wp), intent(out) :: energy
   !> Gradient (hartree/bohr)
   real(wp), intent(out) :: gradient(:)
   !> Failure flag
   logical, intent(out) :: fail

   real(wp), allocatable :: d(:)

   fail = .false.
   if (.not. allocated(self%k)) then
      fail = .true.
      energy = 0.0_wp
      gradient = 0.0_wp
      return
   end if
   if (size(x) /= size(self%k) .or. size(gradient) /= size(x)) then
      fail = .true.
      energy = 0.0_wp
      gradient = 0.0_wp
      return
   end if

   d = x - self%x0
   energy = 0.5_wp*sum(self%k*d**2)
   gradient = self%k*d

end subroutine harmonic_evaluate

!> Exact Hessian of the anisotropic harmonic oscillator
subroutine harmonic_hessian(self, x, hess, fail)
   !> Model
   class(landscape_harmonic_model), intent(inout) :: self
   !> Coordinates (bohr)
   real(wp), intent(in) :: x(:)
   !> Hessian (hartree/bohr^2)
   real(wp), intent(out) :: hess(:, :)
   !> Failure flag
   logical, intent(out) :: fail

   integer :: i

   fail = .false.
   if (.not. allocated(self%k)) then
      fail = .true.
      hess = 0.0_wp
      return
   end if
   if (size(x) /= size(self%k)) then
      fail = .true.
      hess = 0.0_wp
      return
   end if

   hess = 0.0_wp
   do i = 1, size(self%k)
      hess(i, i) = self%k(i)
   end do

end subroutine harmonic_hessian

!> Energy and gradient of the Rosenbrock function
subroutine rosenbrock_evaluate(self, x, energy, gradient, fail)
   !> Model
   class(landscape_rosenbrock_model), intent(inout) :: self
   !> Coordinates (bohr), exactly two components
   real(wp), intent(in) :: x(:)
   !> Energy (hartree)
   real(wp), intent(out) :: energy
   !> Gradient (hartree/bohr)
   real(wp), intent(out) :: gradient(:)
   !> Failure flag
   logical, intent(out) :: fail

   real(wp) :: u, v

   fail = .false.
   energy = 0.0_wp
   gradient = 0.0_wp
   if (size(x) /= 2 .or. size(gradient) /= 2) then
      fail = .true.
      return
   end if

   u = self%a - x(1)
   v = x(2) - x(1)**2
   energy = u**2 + self%b*v**2
   gradient(1) = -2.0_wp*u - 4.0_wp*self%b*x(1)*v
   gradient(2) = 2.0_wp*self%b*v

end subroutine rosenbrock_evaluate

!> Exact Hessian of the Rosenbrock function
subroutine rosenbrock_hessian(self, x, hess, fail)
   !> Model
   class(landscape_rosenbrock_model), intent(inout) :: self
   !> Coordinates (bohr), exactly two components
   real(wp), intent(in) :: x(:)
   !> Hessian (hartree/bohr^2)
   real(wp), intent(out) :: hess(:, :)
   !> Failure flag
   logical, intent(out) :: fail

   real(wp) :: v

   fail = .false.
   hess = 0.0_wp
   if (size(x) /= 2 .or. size(hess, 1) /= 2 .or. size(hess, 2) /= 2) then
      fail = .true.
      return
   end if

   v = x(2) - x(1)**2
   hess(1, 1) = 2.0_wp - 4.0_wp*self%b*v + 8.0_wp*self%b*x(1)**2
   hess(1, 2) = -4.0_wp*self%b*x(1)
   hess(2, 1) = hess(1, 2)
   hess(2, 2) = 2.0_wp*self%b

end subroutine rosenbrock_hessian

!> Energy and gradient of the Mueller-Brown surface
subroutine muller_brown_evaluate(self, x, energy, gradient, fail)
   !> Model
   class(landscape_muller_brown_model), intent(inout) :: self
   !> Coordinates, exactly two components
   real(wp), intent(in) :: x(:)
   !> Energy (hartree)
   real(wp), intent(out) :: energy
   !> Gradient (hartree/bohr)
   real(wp), intent(out) :: gradient(:)
   !> Failure flag
   logical, intent(out) :: fail

   real(wp) :: u, v, q, gaussian, du, dv
   integer :: i

   fail = .false.
   energy = 0.0_wp
   gradient = 0.0_wp
   if (size(x) /= 2 .or. size(gradient) /= 2) then
      fail = .true.
      return
   end if

   do i = 1, 4
      u = x(1) - self%x0(i)
      v = x(2) - self%y0(i)
      q = self%expa(i)*u*u + self%expb(i)*u*v + self%expc(i)*v*v
      gaussian = self%amplitude(i)*exp(q)
      du = 2.0_wp*self%expa(i)*u + self%expb(i)*v
      dv = self%expb(i)*u + 2.0_wp*self%expc(i)*v
      energy = energy + gaussian
      gradient(1) = gradient(1) + gaussian*du
      gradient(2) = gradient(2) + gaussian*dv
   end do

   energy = self%scale*energy
   gradient = self%scale*gradient

end subroutine muller_brown_evaluate

!> Exact Hessian of the Mueller-Brown surface
subroutine muller_brown_hessian(self, x, hess, fail)
   !> Model
   class(landscape_muller_brown_model), intent(inout) :: self
   !> Coordinates, exactly two components
   real(wp), intent(in) :: x(:)
   !> Hessian (hartree/bohr^2)
   real(wp), intent(out) :: hess(:, :)
   !> Failure flag
   logical, intent(out) :: fail

   real(wp) :: u, v, q, gaussian, du, dv
   integer :: i

   fail = .false.
   hess = 0.0_wp
   if (size(x) /= 2 .or. size(hess, 1) /= 2 .or. size(hess, 2) /= 2) then
      fail = .true.
      return
   end if

   do i = 1, 4
      u = x(1) - self%x0(i)
      v = x(2) - self%y0(i)
      q = self%expa(i)*u*u + self%expb(i)*u*v + self%expc(i)*v*v
      gaussian = self%amplitude(i)*exp(q)
      du = 2.0_wp*self%expa(i)*u + self%expb(i)*v
      dv = self%expb(i)*u + 2.0_wp*self%expc(i)*v
      hess(1, 1) = hess(1, 1) + gaussian*(du*du + 2.0_wp*self%expa(i))
      hess(1, 2) = hess(1, 2) + gaussian*(du*dv + self%expb(i))
      hess(2, 2) = hess(2, 2) + gaussian*(dv*dv + 2.0_wp*self%expc(i))
   end do

   hess(2, 1) = hess(1, 2)
   hess = self%scale*hess

end subroutine muller_brown_hessian

end module xtb_landscape_testpot
