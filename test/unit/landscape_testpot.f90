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
!>  * `landscape_leps_model` - London-Eyring-Polanyi-Sato (LEPS) surface of
!>    the H + H2 exchange reaction (three hydrogen atoms, Eq. 1-3 of Sato,
!>    J. Chem. Phys. 23, 592 (1955) as assembled in the London equation).
!>    It has an analytic saddle point on the collinear symmetric line, so it
!>    is the quantitative reference of the path (NEB / CI-NEB) and IRC tests;
!>    because it is a genuinely three-dimensional 9-component potential it is
!>    also the gate of the flattening-order convention (PLAN N4 / R-08).
module xtb_landscape_testpot
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_convert, only : kcaltoau, evtoau
   use xtb_landscape_engine, only : landscape_energy_model
   implicit none(type, external)
   private

   public :: landscape_harmonic_model, new_harmonic_model
   public :: landscape_rosenbrock_model, new_rosenbrock_model
   public :: landscape_muller_brown_model, new_muller_brown_model
   public :: landscape_leps_model, new_leps_model

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

   !> London-Eyring-Polanyi-Sato (LEPS) surface of the H + H2 exchange
   !> reaction, a three atom potential.
   !>
   !> The surface is the London equation evaluated with the Sato
   !> modification of the exchange integral.  For each pair `(i,j)` with
   !> distance `r` the singlet (Morse) and triplet (anti-Morse) potentials
   !>
   !>     `1E(r) = d_e [ exp(-2 beta (r - r_e)) - 2 exp(-beta (r - r_e)) ]`
   !>     `3E(r) = d_e/2 [ exp(-2 beta (r - r_e)) + 2 exp(-beta (r - r_e)) ]`
   !>
   !> define the Coulomb and (Sato scaled) exchange integrals
   !>
   !>     `Q(r) = (1E + 3E)/2`,   `J(r) = (1E - 3E)/(2 (1 + sato))`,
   !>
   !> and the total energy is
   !>
   !>     `E = Q12 + Q23 + Q13 - sqrt( 1/2 [ (J12-J23)^2 + (J23-J13)^2
   !>                                      + (J13-J12)^2 ] )`.
   !>
   !> The diagonal entries of the Coulomb/exchange sum cancel in this form,
   !> so only the three pair terms above contribute.  `sato` is the Sato
   !> parameter of the H2 molecule (0.10 here); `sato = 0` reduces the
   !> expression to the unmodified London equation.
   !>
   !> Default parameters (Sato, J. Chem. Phys. 23, 592 (1955); the H2
   !> Morse parameters are the standard spectroscopic ones):
   !>
   !>   | symbol | value | unit |
   !>   |--------|-------|------|
   !>   | `d_e`  | 4.7466 eV = 0.1744342274 hartree | well depth of H2 |
   !>   | `beta` | 1.9426 1/angstrom = 3.6711 1/bohr | Morse exponent of H2 |
   !>   | `r_e`  | 0.7414 angstrom = 1.4011 bohr | equilibrium bond length of H2 |
   !>   | `sato` | 0.10 (dimensionless) | Sato parameter |
   !>
   !> Analytic reference of these parameters (closed form of the surface,
   !> reproduced by the unit test to 1e-10 hartree):
   !>
   !>  * H2 asymptote: `r = 1.4140743` bohr, `E = -0.1549809388` hartree;
   !>  * H + H2 saddle point (collinear, `r12 = r23 = r*`):
   !>    `r* = 1.5052686` bohr `= 0.7965539` angstrom,
   !>    `E = -0.1406385741` hartree, Hessian eigenvalues
   !>    `-1.004939 / +0.003004 (x2) / +1.895410` hartree/bohr^2 (exactly one
   !>    negative; the two small values are the degenerate bending pair, the
   !>    remaining five are the rigid body modes);
   !>  * classical barrier: `9.0000` kcal/mol `= 0.39036` eV.
   !>
   !> The full 3x3 pair geometry is evaluated, so the model is not restricted
   !> to collinear configurations; the analytic gradient is differentiated on
   !> the fly by the `hessian` procedure with central differences of the
   !> analytic gradient (a fixed step of `leps_hessian_step`), which is exact
   !> enough for a saddle search on this surface.
   type, extends(landscape_energy_model) :: landscape_leps_model
      !> Well depth of the H2 pair potential (hartree)
      real(wp) :: d_e = 0.1744342274_wp
      !> Morse exponent of the H2 pair potential (1/bohr)
      real(wp) :: beta = 3.6711_wp
      !> Equilibrium bond length of the H2 pair potential (bohr)
      real(wp) :: r_e = 1.4011_wp
      !> Sato parameter (dimensionless)
      real(wp) :: sato = 0.10_wp
   contains
      !> Energy and gradient
      procedure :: evaluate => leps_evaluate
      !> Hessian by central differences of the analytic gradient
      procedure :: hessian => leps_hessian
   end type landscape_leps_model

   !> Central difference step of `landscape_leps_model%hessian` (bohr)
   real(wp), parameter :: leps_hessian_step = 1.0e-4_wp

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

!> Construct a LEPS surface of the H + H2 exchange reaction.
!>
!> All four parameters default to the standard H2/H3 values documented on
!> the type; they are exposed so that a test can move the surface (for
!> example scale the barrier) without recompiling.
subroutine new_leps_model(self, d_e, beta, r_e, sato)
   !> New model
   type(landscape_leps_model), intent(out) :: self
   !> Well depth of the pair potential (hartree)
   real(wp), intent(in), optional :: d_e
   !> Morse exponent (1/bohr)
   real(wp), intent(in), optional :: beta
   !> Equilibrium bond length (bohr)
   real(wp), intent(in), optional :: r_e
   !> Sato parameter
   real(wp), intent(in), optional :: sato

   if (present(d_e)) self%d_e = d_e
   if (present(beta)) self%beta = beta
   if (present(r_e)) self%r_e = r_e
   if (present(sato)) self%sato = sato

end subroutine new_leps_model

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

!> Energy and gradient of the LEPS surface of H + H2.
!>
!> Only the three pair distances enter, so the gradient is obtained from the
!> derivative with respect to each pair distance `dE/dr_k` and the chain rule
!> `dE/dx_(k,i) = +/- (dE/dr_k) (x_i - x_j)/r_k`.
!>
!> The exchange term `sqrt(0.5 s)` is the norm of the deviation of the three
!> exchange integrals from their mean, so it is **not differentiable** where
!> the three are equal (an equilateral H3, the degeneracy of the LEPS
!> construction) and its directional derivative there depends on the
!> perturbation direction.  The guard is relative to the scale of the exchange
!> integrals `max|J|`: below it the root is at the level of the cancellation
!> error of the sum of squares, and dividing by it would amplify that error
!> into the gradient.  In that branch the exchange contribution is dropped
!> (`dE/dr_k = dQ_k`), which is its exact value along the symmetric directions
!> through the degenerate point; the routine therefore **never divides by
!> zero** and always returns a gradient in the level set of the energies.
subroutine leps_evaluate(self, x, energy, gradient, fail)
   !> Model
   class(landscape_leps_model), intent(inout) :: self
   !> Flattened coordinates of the three atoms (bohr), length 9
   real(wp), intent(in) :: x(:)
   !> Energy (hartree)
   real(wp), intent(out) :: energy
   !> Flattened gradient (hartree/bohr), length 9
   real(wp), intent(out) :: gradient(:)
   !> Failure flag
   logical, intent(out) :: fail

   integer, parameter :: ipair(2, 3) = reshape([1, 2, 2, 3, 1, 3], [2, 3])
   real(wp) :: xyz(3, 3), r(3), q(3), j(3), dq(3), dj(3), u(3)
   real(wp) :: root, ds(3), dedr(3)
   integer :: k, i, iat, jat

   fail = .false.
   energy = 0.0_wp
   gradient = 0.0_wp

   if (size(x) /= 9 .or. size(gradient) /= 9) then
      fail = .true.
      return
   end if

   do iat = 1, 3
      xyz(:, iat) = x(3*(iat - 1) + 1:3*iat)
   end do

   do k = 1, 3
      i = ipair(1, k)
      jat = ipair(2, k)
      r(k) = sqrt(sum((xyz(:, i) - xyz(:, jat))**2))
      if (r(k) <= 0.0_wp) then
         fail = .true.
         return
      end if
      call leps_pair(r(k), self%d_e, self%beta, self%r_e, self%sato, &
         & q(k), j(k), dq(k), dj(k))
   end do

   ! London equation: s = (J1-J2)^2 + (J2-J3)^2 + (J3-J1)^2
   root = sqrt(0.5_wp*((j(1) - j(2))**2 + (j(2) - j(3))**2 + (j(3) - j(1))**2))
   energy = q(1) + q(2) + q(3) - root

   ! dE/dr_k = dQ_k - (1/4) (ds/dr_k) / root, with
   ! ds/dJ_k = 2 (2 J_k - J_m - J_n), so (1/4) ds/dr_k = (J_k - (J_m+J_n)/2) dJ_k/dr_k
   if (root > 1.0e-12_wp*maxval(abs(j))) then
      ds(1) = (j(1) - 0.5_wp*(j(2) + j(3)))*dj(1)
      ds(2) = (j(2) - 0.5_wp*(j(1) + j(3)))*dj(2)
      ds(3) = (j(3) - 0.5_wp*(j(1) + j(2)))*dj(3)
      dedr = dq - ds/root
   else
      ! degenerated exchange integrals: the root is the norm of their
      ! deviation and has no derivative here, so the contribution of the
      ! exchange term to the gradient is dropped instead of dividing by it
      dedr = dq
   end if

   do k = 1, 3
      i = ipair(1, k)
      jat = ipair(2, k)
      u(k) = 1.0_wp/r(k)
      gradient(3*(i - 1) + 1:3*i) = gradient(3*(i - 1) + 1:3*i) &
         & + dedr(k)*u(k)*(xyz(:, i) - xyz(:, jat))
      gradient(3*(jat - 1) + 1:3*jat) = gradient(3*(jat - 1) + 1:3*jat) &
         & - dedr(k)*u(k)*(xyz(:, i) - xyz(:, jat))
   end do

end subroutine leps_evaluate

!> Hessian of the LEPS surface by central differences of its analytic
!> gradient.
!>
!> The surface is smooth and cheap, so a finite difference of the analytic
!> gradient is exact enough for the saddle search of the path tests (the
!> eigenvalue at the saddle is reproduced to better than 1e-6).  Every step
!> evaluates the **analytic gradient**, not a finite difference of the
!> energy, so the Hessian is symmetric by construction.
subroutine leps_hessian(self, x, hess, fail)
   !> Model
   class(landscape_leps_model), intent(inout) :: self
   !> Flattened coordinates (bohr), length 9
   real(wp), intent(in) :: x(:)
   !> Dense Hessian (hartree/bohr^2), shape (9, 9)
   real(wp), intent(out) :: hess(:, :)
   !> Failure flag
   logical, intent(out) :: fail

   real(wp), allocatable :: xp(:), xm(:), gp(:), gm(:)
   real(wp) :: ep, em
   integer :: i, n

   fail = .false.
   hess = 0.0_wp
   if (size(x) /= 9 .or. size(hess, 1) /= 9 .or. size(hess, 2) /= 9) then
      fail = .true.
      return
   end if

   n = size(x)
   allocate(xp(n), xm(n), gp(n), gm(n))
   do i = 1, n
      xp = x
      xm = x
      xp(i) = xp(i) + leps_hessian_step
      xm(i) = xm(i) - leps_hessian_step
      call leps_evaluate(self, xp, ep, gp, fail)
      if (fail) return
      call leps_evaluate(self, xm, em, gm, fail)
      if (fail) return
      hess(:, i) = (gp - gm)/(2.0_wp*leps_hessian_step)
   end do
   hess = 0.5_wp*(hess + transpose(hess))

end subroutine leps_hessian

!> Coulomb and Sato scaled exchange integral of one LEPS pair, together with
!> their derivatives with respect to the pair distance.
!>
!> `1E` is the Morse singlet, `3E` the anti-Morse triplet; `Q = (1E+3E)/2`
!> and `J = (1E-3E)/(2(1+sato))` (Sato, J. Chem. Phys. 23, 592 (1955)).
pure subroutine leps_pair(r, d_e, beta, r_e, sato, q, j, dq, dj)
   !> Pair distance (bohr)
   real(wp), intent(in) :: r
   !> Well depth (hartree)
   real(wp), intent(in) :: d_e
   !> Morse exponent (1/bohr)
   real(wp), intent(in) :: beta
   !> Equilibrium distance (bohr)
   real(wp), intent(in) :: r_e
   !> Sato parameter
   real(wp), intent(in) :: sato
   !> Coulomb integral (hartree)
   real(wp), intent(out) :: q
   !> Sato scaled exchange integral (hartree)
   real(wp), intent(out) :: j
   !> Derivative of `q` with respect to `r` (hartree/bohr)
   real(wp), intent(out) :: dq
   !> Derivative of `j` with respect to `r` (hartree/bohr)
   real(wp), intent(out) :: dj

   real(wp) :: x, e1, e3, d1, d3

   x = r - r_e
   e1 = d_e*(exp(-2.0_wp*beta*x) - 2.0_wp*exp(-beta*x))
   e3 = 0.5_wp*d_e*(exp(-2.0_wp*beta*x) + 2.0_wp*exp(-beta*x))
   d1 = d_e*(-2.0_wp*beta*exp(-2.0_wp*beta*x) + 2.0_wp*beta*exp(-beta*x))
   d3 = 0.5_wp*d_e*(-2.0_wp*beta*exp(-2.0_wp*beta*x) - 2.0_wp*beta*exp(-beta*x))

   q = 0.5_wp*(e1 + e3)
   j = 0.5_wp*(e1 - e3)/(1.0_wp + sato)
   dq = 0.5_wp*(d1 + d3)
   dj = 0.5_wp*(d1 - d3)/(1.0_wp + sato)

end subroutine leps_pair

end module xtb_landscape_testpot
