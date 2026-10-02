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

!> Shared integration kernel of the xtb landscape IRC task.
!>
!> The module holds the three pieces the four IRC integrators (GS, HPC, LQA,
!> EulerPC) share, all of them on a **quadratic model** of the surface and
!> therefore unit testable without a single SCF:
!>
!>  * **Mass weighted coordinates.**  The IRC is defined in mass weighted
!>    Cartesian coordinates (Hratchian & Schlegel, J. Chem. Phys. **120**,
!>    9918 (2004), Eq. 1),
!>
!>        `dx(s)/ds = -g(x)/|g(x)|`,
!>
!>    where `s` is the arc length, `g` the mass weighted gradient and the
!>    norm the mass weighted norm.  **One atomic unit along the path is
!>    1 bohr*amu^1/2**; the weighted coordinate is `q_i = sqrt(m_i/amu) r_i`
!>    and the weighted gradient is `g^q_i = g_i / sqrt(m_i/amu)`.  This is
!>    *not* the electron mass metric of the vibrational analysis: the IRC
!>    metric uses amu so that the literature step size (`IRC=StepSize=10`,
!>    i.e. 0.10 bohr*amu^1/2) is reproduced exactly.
!>
!>  * **Analytic quadratic (LQA) propagation.**  With the local quadratic
!>    model `E(x) = E_0 + g_0^T dx + 1/2 dx^T H dx` the ODE above is solved
!>    in closed form by diagonalising `H`:
!>
!>        `x(t) = x_0 + U a(t) U^T g_0`,  `a_ii(t) = (e^{-lambda_i t} - 1)/lambda_i`,
!>        `ds/dt = |g(t)|`,  `g(t) = U e^{-Lambda t} U^T g_0`
!>
!>    (Hratchian & Schlegel, Eqs. 7-9, the `N_Euler = 5000` substeps of
!>    Eq. 10).  The parameter `t` of the requested arc length is found by
!>    bisection on the arc length integral, which is evaluated by composite
!>    Simpson quadrature with `euler_n` panels; that is the same ODE march
!>    the paper describes, at higher order.
!>
!>    **The `lambda_i -> 0` limit.**  Both the displacement factor and the
!>    speed have a removable singularity at a vanishing eigenvalue:
!>    `a_ii(t) -> -t` and `g_i(t) -> g_i(0)`.  The branch is taken explicitly
!>    (`|lambda_i| <= irc_curvature_tol max(1,|lambda|max)`) instead of
!>    dividing by the eigenvalue, so a Hessian with an exactly vanishing
!>    eigenvalue (a rigid mode of an analytic model, a linear molecule) is
!>    propagated with the correct limit rather than dropped or divided by
!>    zero.  The limit contribution `-t g_i` vanishes for a rigid body mode
!>    of a real molecule (its gradient component is zero) and is the correct
!>    soft-mode contribution otherwise; dropping the mode (the previous
!>    behaviour) silently lost the latter.
!>
!>  * **Double-weighted interpolation (DWI) surface and modified
!>    Bulirsch-Stoer (mBS) corrector.**  The DWI surface of Hratchian &
!>    Schlegel (Eqs. 5-6) and Meisner & Kaestner, J. Chem. Phys. **133**,
!>    224101 (2010), Eqs. 3-4, interpolates the quadratic expansions
!>    `T_i(x) = E_i + g_i^T (x - x_i) + 1/2 (x - x_i)^T H (x - x_i)` at the
!>    sample points with distance weights `w_i = 1/(|x - x_i|^2 + eps^2)`,
!>    `E_DWI = sum_i w_i T_i / sum_i w_i`.  The weight function of the
!>    published DWI could not be retrieved verbatim (report 04 marks this as
!>    missing evidence); the inverse squared distance (Shepard) form is used
!>    here and is documented as a deviation.  The mBS integrates the DWI
!>    steepest-descent ODE with **simple Euler** as the basic step.  The
!>    published method uses the modified midpoint method as the basic step;
!>    Hratchian & Schlegel reject it explicitly because it "greatly amplifies"
!>    the stiffness of Eq. 1, and use simple Euler instead (report 04
!>    section 1.3).  Because a simple Euler expansion carries both odd and
!>    even powers of the step, the Richardson extrapolation below is taken in
!>    the step size itself (a factor `2^j` per level), not in its square.
!>    The acceptance threshold is `mbs_tol` (MAPLE default 1.0e-5, the HPC
!>    paper's 1.0e-6 available through `--lirc-mbs-tol`).  A failed
!>    convergence returns `converged = .false.` (and a total blow-up
!>    `fail = .true.`) so the caller can fall back to one GS step and warn,
!>    exactly as PLAN section 6.5 requires.
!>
!> **LQA lineage (PLAN R-12 / report 04 Contradictions #3).**  The analytic
!> propagation implemented here is the **Page & McIver branch** (Page &
!> McIver, J. Chem. Phys. **88**, 922 (1988)), i.e. the quadratic Taylor
!> solution of the IRC ODE that the HPC/EulerPC papers and Gaussian attribute
!> to Page & McIver.  The Sun-Ruedenberg / Eckert & Werner quadratic steepest
!> descent (QSD) form is a **different derivation**: it writes the step as
!> `x(u) = x^(k) - H^{-1}(I - uH) g` with a curvature dependent step size
!> function and distinguishes three points along the path, whereas the branch
!> used here has one expansion centre and a fixed arc length.  The two agree
!> to first order in the step but are not the same algorithm; the QSD form is
!> deliberately not implemented (report 04 section 1.4).
!>
!> Units: geometries and displacements in `bohr*amu^1/2` for the mass
!> weighted vectors (Cartesian bohr at the boundary), energies in hartree,
!> Hessian elements in hartree/(bohr^2 amu).
module xtb_landscape_irc_corrector
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_convert, only : autoamu
   use xtb_mctc_lapack, only : mctc_syev
   use xtb_type_environment, only : TEnvironment
   use xtb_type_molecule, only : TMolecule
   use xtb_param_atomicmass, only : getAtomicMass
   use xtb_landscape_coords, only : vec_norm, vec_rms
   use xtb_landscape_settings, only : landscape_log_failed
   use xtb_landscape_saddle_eigenfollow, only : landscape_transition_mode, &
      & landscape_transition_mode_set_phase
   implicit none(type, external)
   private

   public :: landscape_irc_masses, landscape_irc_sqrt_mass
   public :: landscape_irc_to_weighted, landscape_irc_from_weighted
   public :: landscape_irc_gradient_to_weighted, landscape_irc_hessian_to_weighted
   public :: landscape_irc_select_direction
   public :: landscape_irc_lqa_step
   public :: landscape_irc_dwi_surface, landscape_irc_dwi_init, &
      & landscape_irc_dwi_add, landscape_irc_dwi_evaluate
   public :: landscape_irc_mbs_integrate
   public :: landscape_irc_corrector_step
   public :: landscape_irc_path, landscape_irc_path_add, landscape_irc_path_reserve
   public :: landscape_irc_path_reset
   !> Termination of a path that was never started.
   integer, parameter :: p_irc_path_error = 0

   !> Regulariser of the DWI weights (bohr^2 amu, relative to the squared
   !> distance to a sample point).  Keeps the weight finite at the samples and
   !> is small enough that the interpolant reproduces a sample gradient to
   !> better than 1e-8 relative error.
   real(wp), parameter :: dwi_regulariser = 1.0e-12_wp
   !> Relative threshold below which a Hessian eigenvalue counts as a rigid
   !> body / numerical zero mode rather than a curvature.  The IRC metric
   !> carries the same six (five for a linear molecule) vanishing directions
   !> as the vibrational analysis; they must not enter the analytic
   !> propagation (where `1/lambda` would blow up).
   real(wp), parameter :: irc_curvature_tol = 1.0e-10_wp
   !> Guard below which the gradient is considered vanishing (hartree/bohr);
   !> the steepest descent direction is undefined there.
   real(wp), parameter :: irc_gradient_guard = 1.0e-14_wp


!> A distance weighted interpolation (DWI) surface.
!>
!> The surface is the weighted average of the quadratic expansions of up to
!> `dwi_n` sample points with weights `w_i = 1/(|x - x_i|^2 + eps^2)`.  One
!> shared Hessian is stored: the corrector always expands about the predicted
!> end point, whose Hessian is the current path Hessian, and the DWI is a
!> local model between the two ends of the step (Hratchian & Schlegel,
!> Eqs. 5-6).  A surface with a single sample reduces exactly to that
!> quadratic.
type :: landscape_irc_dwi_surface
   !> Number of stored sample points
   integer :: n = 0
   !> Sample positions (bohr*amu^1/2), `(ndim, n)`
   real(wp), allocatable :: x(:, :)
   !> Sample energies (hartree)
   real(wp), allocatable :: e(:)
   !> Sample gradients (hartree/(bohr*amu^1/2)), `(ndim, n)`
   real(wp), allocatable :: g(:, :)
   !> Shared Hessian (hartree/(bohr^2 amu)), `(ndim, ndim)`
   real(wp), allocatable :: hess(:, :)
   !> Capacity of the sample arrays
   integer :: capacity = 0
end type landscape_irc_dwi_surface

!> One direction of an IRC integration: the points after the transition state.
!>
!> The geometries are stored flat, `xyz(3*nat, n)`, in the `x1,y1,z1,x2,...`
!> order of the suite (PLAN N4); a point is added to `s` in `bohr*amu^1/2`
!> from the transition state.  The transition state itself is not stored: it
!> is the common origin of the two directions and lives in the result object.
!>
!> **One path object holds points of one dimension.**  `landscape_irc_path_reset`
!> restores the empty state - including the release of the storage - so the same
!> object can be reused for another walk and for another dimension; a point of
!> a different dimension added without the reset releases the old storage and
!> starts a new path (the container has no environment and cannot report the
!> programming error, see report 45 finding F-1).
type :: landscape_irc_path
   !> Number of stored points
   integer :: n = 0
   !> Number of stored components (3*nat for a molecular path, 2 for the
   !> analytic two dimensional test surfaces)
   integer :: ndim = 0
   !> Termination signal, one of the `p_landscape_irc_term_*` identifiers
   integer :: term = p_irc_path_error
   !> Number of points whose Gonzalez-Schlegel sphere relaxation was stopped by
   !> the micro cycle budget instead of its own convergence criterion (the GS
   !> cost documented in `xtb_landscape_irc_gs`); the predictor-corrector
   !> integrators count only the GS steps of a corrector fallback
   integer :: n_pinned = 0
   !> Geometry of every point `(ndim, capacity)` (bohr)
   real(wp), allocatable :: xyz(:, :)
   !> Energy of every point (hartree)
   real(wp), allocatable :: e(:)
   !> Arc length from the transition state (bohr*amu^1/2)
   real(wp), allocatable :: s(:)
   !> Euclidean Cartesian gradient norm (hartree/bohr)
   real(wp), allocatable :: gnorm(:)
   !> Maximum absolute gradient component (hartree/bohr)
   real(wp), allocatable :: gmax(:)
   !> Energy/gradient evaluations spent on the point
   integer, allocatable :: n_eval(:)
   !> Capacity of the arrays
   integer :: capacity = 0
end type landscape_irc_path

contains

!> Atomic masses in amu, one entry per Cartesian component (3N).
!>
!> The IRC metric uses amu (not the electron mass of `xtb_landscape_coords`)
!> because the unit of the step length is the literature `bohr*amu^1/2`.
function landscape_irc_masses(mol) result(mass)
   !> Molecular structure
   type(TMolecule), intent(in) :: mol
   !> Masses in amu, repeated three times per atom (length 3N)
   real(wp), allocatable :: mass(:)

   integer :: i, ic

   allocate(mass(3*mol%n), source=0.0_wp)
   do i = 1, mol%n
      ic = 3*(i - 1)
      mass(ic + 1:ic + 3) = getAtomicMass(mol%at(i))*autoamu
   end do

end function landscape_irc_masses

!> Square root of a per-component mass vector.
pure function landscape_irc_sqrt_mass(mass) result(sqrt_mass)
   !> Masses in amu (length 3N)
   real(wp), intent(in) :: mass(:)
   !> `sqrt(mass)` (length 3N)
   real(wp), allocatable :: sqrt_mass(:)

   sqrt_mass = sqrt(mass)

end function landscape_irc_sqrt_mass

!> Mass weight a Cartesian geometry: `q_i = sqrt(m_i) r_i`.
pure subroutine landscape_irc_to_weighted(sqrt_mass, xyz, q)
   !> `sqrt(mass)` (length 3N)
   real(wp), intent(in) :: sqrt_mass(:)
   !> Flattened Cartesian geometry (bohr)
   real(wp), intent(in) :: xyz(:)
   !> Mass weighted geometry (bohr*amu^1/2)
   real(wp), intent(out) :: q(:)

   q = xyz*sqrt_mass

end subroutine landscape_irc_to_weighted

!> Remove the mass weighting from a weighted geometry: `r_i = q_i / sqrt(m_i)`.
pure subroutine landscape_irc_from_weighted(sqrt_mass, q, xyz)
   !> `sqrt(mass)` (length 3N)
   real(wp), intent(in) :: sqrt_mass(:)
   !> Mass weighted geometry (bohr*amu^1/2)
   real(wp), intent(in) :: q(:)
   !> Flattened Cartesian geometry (bohr)
   real(wp), intent(out) :: xyz(:)

   xyz = q/sqrt_mass

end subroutine landscape_irc_from_weighted

!> Mass weight a Cartesian gradient: `g^q_i = g_i / sqrt(m_i)`.
pure subroutine landscape_irc_gradient_to_weighted(sqrt_mass, gradient, gq)
   !> `sqrt(mass)` (length 3N)
   real(wp), intent(in) :: sqrt_mass(:)
   !> Cartesian gradient (hartree/bohr)
   real(wp), intent(in) :: gradient(:)
   !> Mass weighted gradient (hartree/(bohr*amu^1/2))
   real(wp), intent(out) :: gq(:)

   gq = gradient/sqrt_mass

end subroutine landscape_irc_gradient_to_weighted

!> Mass weight a Cartesian Hessian, `H^q_ij = H_ij / sqrt(m_i m_j)`.
pure subroutine landscape_irc_hessian_to_weighted(sqrt_mass, hess, hq)
   !> `sqrt(mass)` (length 3N)
   real(wp), intent(in) :: sqrt_mass(:)
   !> Cartesian Hessian (hartree/bohr^2)
   real(wp), intent(in) :: hess(:, :)
   !> Mass weighted Hessian (hartree/(bohr^2 amu))
   real(wp), intent(out) :: hq(:, :)

   integer :: i, j

   do j = 1, size(hess, 2)
      do i = 1, size(hess, 1)
         hq(i, j) = hess(i, j)/(sqrt_mass(i)*sqrt_mass(j))
      end do
   end do

end subroutine landscape_irc_hessian_to_weighted

!> Deterministic initial direction of the integration (the transition vector).
!>
!> The mass weighted Hessian is diagonalised (eigenvalues ascending,
!> `mctc_syev`); the followed mode is the `target`-th most negative one
!> (`target = 1` = the most negative).  A Hessian with fewer negative
!> eigenvalues than requested follows its most negative one and emits a
!> warning; a Hessian without any negative eigenvalue is an error, because
!> the input is then not a first order saddle point (the task additionally
!> confirms the mode count with the M3 frequency analysis).
!>
!> The **forward direction is fixed deterministically** by the M4 phase
!> convention: the vector is oriented so that its largest absolute component
!> is positive and the component index and value are recorded (PLAN section
!> 6.3).  The caller reports them, so the two directions are reproducible
!> from the output alone.
subroutine landscape_irc_select_direction(env, hess, target, mode, fail)
   character(len=*), parameter :: source = 'landscape_irc_select_direction'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Mass weighted Hessian (hartree/(bohr^2 amu))
   real(wp), intent(in) :: hess(:, :)
   !> Requested negative mode (1 = most negative)
   integer, intent(in) :: target
   !> Transition mode, filled on return (weighted, unit vector)
   type(landscape_transition_mode), intent(inout) :: mode
   !> Failure flag
   logical, intent(out) :: fail

   real(wp), allocatable :: work(:, :), evals(:)
   real(wp) :: tol
   integer :: n, nneg, index, nlog

   fail = .false.
   n = size(hess, 1)
   if (n == 0 .or. size(hess, 2) /= n) then
      call env%error("the Hessian of the initial direction must be square", source)
      fail = .true.
      return
   end if

   allocate(work(n, n))
   work = 0.5_wp*(hess + transpose(hess))
   allocate(evals(n))
   nlog = env%nLog
   call mctc_syev(env, work, evals)
   if (landscape_log_failed(env, nlog)) then
      fail = .true.
      return
   end if

   tol = irc_curvature_tol*max(1.0_wp, maxval(abs(evals)))
   nneg = count(evals < -tol)
   if (nneg == 0) then
      call env%error("the mass weighted Hessian has no negative eigenvalue: "//&
         & "the geometry is not a transition state", source)
      fail = .true.
      return
   end if
   index = max(1, target)
   if (index > nneg) then
      call env%warning("the Hessian has fewer negative eigenvalues than the "//&
         & "requested target mode; the most negative one is followed", source)
      index = 1
   end if

   if (allocated(mode%vector)) deallocate(mode%vector)
   allocate(mode%vector(n))
   mode%vector = work(:, index)
   mode%vector = mode%vector/vec_norm(mode%vector)
   mode%index = index
   mode%eigenvalue = evals(index)
   mode%overlap = 1.0_wp
   mode%followed = .false.
   mode%target = max(1, target)
   call landscape_transition_mode_set_phase(mode)

end subroutine landscape_irc_select_direction

!> Analytic (LQA, Page-McIver branch) propagation along a local quadratic.
!>
!> The quadratic model is `E(x) = E_0 + g_0^T dx + 1/2 dx^T H dx` about the
!> current point.  The steepest descent ODE of Eq. 1 has the closed form
!> `dx(t) = U a(t) U^T g_0` with `a_ii(t) = (e^{-lambda_i t} - 1)/lambda_i`
!> (Hratchian & Schlegel, Eq. 9).  The parameter `t*` that realises the
!> requested arc length `s` is the root of
!>
!>    `S(t) = int_0^t sqrt( sum_i (g'_i)^2 e^{-2 lambda_i t'} ) dt' = s`,
!>
!> which is monotone in `t` and is solved here by bisection.  `S` is
!> evaluated by composite Simpson quadrature with `euler_n` panels (the
!> `N_Euler = 5000` of Eq. 10) and `euler_n` is rounded up to the next even
!> number.
!>
!> Eigenvalues with `|lambda_i| <= 1e-10 max(1, |lambda|max)` are the rigid
!> body zero modes of a numerical Hessian (or a linear molecule) or genuine
!> soft modes; they are handled with the `lambda -> 0` limit `a_ii -> -t`
!> rather than by dividing by the eigenvalue (see the module header).
subroutine landscape_irc_lqa_step(env, b, hess, s_target, euler_n, dx, s_reached, fail)
   character(len=*), parameter :: source = 'landscape_irc_lqa_step'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Mass weighted gradient at the expansion point (hartree/(bohr*amu^1/2))
   real(wp), intent(in) :: b(:)
   !> Mass weighted Hessian at the expansion point (hartree/(bohr^2 amu))
   real(wp), intent(in) :: hess(:, :)
   !> Requested arc length (bohr*amu^1/2)
   real(wp), intent(in) :: s_target
   !> Number of Euler/Simpson substeps of the arc length integral
   integer, intent(in) :: euler_n
   !> Displacement along the quadratic (bohr*amu^1/2)
   real(wp), intent(out) :: dx(:)
   !> Arc length actually realised (bohr*amu^1/2)
   real(wp), intent(out) :: s_reached
   !> Failure flag (the gradient vanishes at the expansion point)
   logical, intent(out) :: fail

   real(wp), allocatable :: work(:, :), evals(:), gq(:)
   real(wp) :: tol, gn, t_lo, t_hi, s_t, t_mid, t_best
   integer :: n, i, npanel, iter, nlog

   fail = .false.
   dx = 0.0_wp
   s_reached = 0.0_wp
   n = size(b)
   if (size(hess, 1) /= n .or. size(hess, 2) /= n .or. size(dx) /= n) then
      call env%error("the LQA step needs matching gradient, Hessian and "//&
         & "displacement dimensions", source)
      fail = .true.
      return
   end if
   gn = vec_norm(b)
   if (gn <= irc_gradient_guard) then
      ! A vanishing gradient defines no descent direction; the caller stops.
      fail = .true.
      return
   end if
   if (s_target <= 0.0_wp) return

   allocate(work(n, n))
   work = 0.5_wp*(hess + transpose(hess))
   allocate(evals(n))
   nlog = env%nLog
   call mctc_syev(env, work, evals)
   if (landscape_log_failed(env, nlog)) then
      fail = .true.
      return
   end if

   tol = irc_curvature_tol*max(1.0_wp, maxval(abs(evals)))
   allocate(gq(n), source=0.0_wp)
   do i = 1, n
      gq(i) = dot_product(work(:, i), b)
   end do

   npanel = max(2, euler_n)
   if (mod(npanel, 2) /= 0) npanel = npanel + 1

   ! bracket the root of S(t) - s: S is monotone increasing
   t_hi = s_target/max(speed(evals, gq, 0.0_wp, tol), irc_gradient_guard)
   if (t_hi <= 0.0_wp) t_hi = s_target
   s_t = arc_length(evals, gq, tol, t_hi, npanel)
   iter = 0
   do while (s_t < s_target .and. iter < 200)
      t_hi = 2.0_wp*t_hi
      s_t = arc_length(evals, gq, tol, t_hi, npanel)
      iter = iter + 1
   end do
   if (s_t < s_target) then
      call env%error("the arc length of the quadratic propagation did not "//&
         & "reach the requested step", source)
      fail = .true.
      return
   end if

   t_lo = 0.0_wp
   t_best = t_hi
   do iter = 1, 100
      t_mid = 0.5_wp*(t_lo + t_hi)
      s_t = arc_length(evals, gq, tol, t_mid, npanel)
      if (s_t < s_target) then
         t_lo = t_mid
      else
         t_hi = t_mid
         t_best = t_mid
      end if
      if (abs(s_t - s_target) <= 1.0e-12_wp*max(s_target, 1.0_wp)) exit
   end do

   call lqa_displacement(work, evals, gq, tol, t_best, dx)
   s_reached = arc_length(evals, gq, tol, t_best, npanel)

end subroutine landscape_irc_lqa_step

!> Arc length `S(t)` of the quadratic descent (Simpson, `npanel` panels).
pure function arc_length(evals, gq, tol, t, npanel) result(s)
   !> Eigenvalues (ascending)
   real(wp), intent(in) :: evals(:)
   !> Gradient in the eigenbasis
   real(wp), intent(in) :: gq(:)
   !> Curvature tolerance of the zero mode mask
   real(wp), intent(in) :: tol
   !> Parameter of the propagation
   real(wp), intent(in) :: t
   !> Number of Simpson panels (even)
   integer, intent(in) :: npanel
   !> Arc length `S(t)`
   real(wp) :: s

   real(wp) :: h, sum_odd, sum_even
   integer :: i, n

   if (t == 0.0_wp) then
      s = 0.0_wp
      return
   end if
   n = npanel
   h = t/real(n, wp)
   sum_odd = 0.0_wp
   sum_even = 0.0_wp
   do i = 1, n - 1
      if (mod(i, 2) == 1) then
         sum_odd = sum_odd + speed(evals, gq, real(i, wp)*h, tol)
      else
         sum_even = sum_even + speed(evals, gq, real(i, wp)*h, tol)
      end if
   end do
   s = speed(evals, gq, 0.0_wp, tol) + speed(evals, gq, t, tol) &
      & + 4.0_wp*sum_odd + 2.0_wp*sum_even
   s = s*h/3.0_wp

end function arc_length

!> Speed `|g(t)|` of the quadratic descent.
pure function speed(evals, gq, t, tol) result(v)
   !> Eigenvalues (ascending)
   real(wp), intent(in) :: evals(:)
   !> Gradient in the eigenbasis
   real(wp), intent(in) :: gq(:)
   !> Parameter of the propagation
   real(wp), intent(in) :: t
   !> Curvature tolerance of the zero mode mask
   real(wp), intent(in) :: tol
   !> `|g(t)|`
   real(wp) :: v

   real(wp) :: acc
   integer :: i, n

   n = size(evals)
   acc = 0.0_wp
   do i = 1, n
      if (abs(evals(i)) <= tol) then
         ! lambda -> 0 limit of g_i exp(-lambda_i t): the mode is a rigid
         ! body / soft direction and its speed is |g_i|
         acc = acc + gq(i)**2
      else
         acc = acc + (gq(i)*exp(-evals(i)*t))**2
      end if
   end do
   if (n == 0) then
      v = 0.0_wp
   else
      v = sqrt(acc)
   end if

end function speed

!> Displacement `dx(t) = U a(t) U^T g_0` of the analytic propagation.
pure subroutine lqa_displacement(evecs, evals, gq, tol, t, dx)
   !> Eigenvectors as columns
   real(wp), intent(in) :: evecs(:, :)
   !> Eigenvalues (ascending)
   real(wp), intent(in) :: evals(:)
   !> Gradient in the eigenbasis
   real(wp), intent(in) :: gq(:)
   !> Curvature tolerance of the zero mode mask
   real(wp), intent(in) :: tol
   !> Parameter of the propagation
   real(wp), intent(in) :: t
   !> Displacement (bohr*amu^1/2)
   real(wp), intent(out) :: dx(:)

   real(wp), allocatable :: coeff(:)
   real(wp) :: a
   integer :: i, n

   n = size(evals)
   allocate(coeff(n), source=0.0_wp)
   do i = 1, n
      if (abs(evals(i)) <= tol) then
         ! lambda -> 0 limit of (e^{-lambda t} - 1)/lambda: -t, reached
         ! without dividing by the (vanishing) eigenvalue
         a = -t
      else
         a = (exp(-evals(i)*t) - 1.0_wp)/evals(i)
      end if
      coeff(i) = a*gq(i)
   end do
   dx = matmul(evecs, coeff)

end subroutine lqa_displacement


!> Allocate a DWI surface with a shared Hessian and `max_points` slots.
subroutine landscape_irc_dwi_init(surf, hess, max_points)
   !> Surface
   type(landscape_irc_dwi_surface), intent(out) :: surf
   !> Shared Hessian (hartree/(bohr^2 amu))
   real(wp), intent(in) :: hess(:, :)
   !> Number of sample points the surface may hold (>= 1)
   integer, intent(in) :: max_points

   integer :: ndim

   ndim = size(hess, 1)
   surf%n = 0
   surf%capacity = max(1, max_points)
   allocate(surf%x(ndim, surf%capacity), source=0.0_wp)
   allocate(surf%e(surf%capacity), source=0.0_wp)
   allocate(surf%g(ndim, surf%capacity), source=0.0_wp)
   allocate(surf%hess(ndim, ndim), source=0.0_wp)
   surf%hess = 0.5_wp*(hess + transpose(hess))

end subroutine landscape_irc_dwi_init

!> Append a sample point to a DWI surface.
!>
!> The oldest sample is dropped when the surface is full, so the weights always
!> describe the neighbourhood of the current step.
subroutine landscape_irc_dwi_add(surf, x, energy, gradient)
   !> Surface
   type(landscape_irc_dwi_surface), intent(inout) :: surf
   !> Sample position (bohr*amu^1/2)
   real(wp), intent(in) :: x(:)
   !> Sample energy (hartree)
   real(wp), intent(in) :: energy
   !> Sample gradient (hartree/(bohr*amu^1/2))
   real(wp), intent(in) :: gradient(:)

   integer :: i

   if (surf%capacity <= 0) return
   if (surf%n >= surf%capacity) then
      do i = 1, surf%capacity - 1
         surf%x(:, i) = surf%x(:, i + 1)
         surf%e(i) = surf%e(i + 1)
         surf%g(:, i) = surf%g(:, i + 1)
      end do
      surf%n = surf%capacity - 1
   end if
   surf%n = surf%n + 1
   surf%x(:, surf%n) = x
   surf%e(surf%n) = energy
   surf%g(:, surf%n) = gradient

end subroutine landscape_irc_dwi_add

!> Energy and gradient of the DWI surface at `x`.
subroutine landscape_irc_dwi_evaluate(surf, x, energy, gradient)
   !> Surface
   type(landscape_irc_dwi_surface), intent(in) :: surf
   !> Position (bohr*amu^1/2)
   real(wp), intent(in) :: x(:)
   !> Energy (hartree)
   real(wp), intent(out) :: energy
   !> Gradient (hartree/(bohr*amu^1/2))
   real(wp), intent(out) :: gradient(:)

   real(wp) :: dx(size(x)), hdx(size(x))
   real(wp) :: w, wsum, ti, d2, wi, sum_e, sum_dw(size(x))
   real(wp) :: sum_g(size(x))
   integer :: i

   if (surf%n <= 0) then
      energy = 0.0_wp
      gradient = 0.0_wp
      return
   end if
   wsum = 0.0_wp
   sum_e = 0.0_wp
   sum_g = 0.0_wp
   sum_dw = 0.0_wp
   do i = 1, surf%n
      dx = x - surf%x(:, i)
      d2 = dot_product(dx, dx)
      w = 1.0_wp/(d2 + dwi_regulariser)
      hdx = matmul(surf%hess, dx)
      ti = surf%e(i) + dot_product(surf%g(:, i), dx) + 0.5_wp*dot_product(dx, hdx)
      wsum = wsum + w
      sum_e = sum_e + w*ti
      ! d/dx [w_i T_i] = w_i grad T_i + (grad w_i) T_i with
      ! grad w_i = -2 w_i / (d^2 + eps^2) dx
      wi = -2.0_wp*w/(d2 + dwi_regulariser)
      sum_g = sum_g + w*(surf%g(:, i) + hdx) + wi*ti*dx
      sum_dw = sum_dw + wi*dx
   end do
   if (wsum <= 0.0_wp) then
      energy = 0.0_wp
      gradient = 0.0_wp
      return
   end if
   ! E_DWI = sum w T / sum w, so
   ! grad E_DWI = [ sum (w grad T + (grad w) T) - E sum grad w ] / sum w
   energy = sum_e/wsum
   gradient = (sum_g - energy*sum_dw)/wsum

end subroutine landscape_irc_dwi_evaluate

!> Modified Bulirsch-Stoer integration of the DWI steepest-descent ODE.
!>
!> Integrates `dx/ds = -g(x)/|g(x)|` (Eq. 1) on the DWI surface from `x0`
!> over the arc length `s_target` with **simple Euler** as the basic step and
!> Richardson extrapolation over the step refinement.  Level `k` uses
!> `mbs_points * 2^k` Euler substeps of size `s_target/(mbs_points 2^k)`, and
!> the extrapolation table is built with the standard factor `2^j`.  The
!> refinement stops when the RMS difference between the two last diagonal
!> entries falls below `tol` (`converged = .true.`) or after `max_k` levels
!> (`converged = .false.`, the current estimate is returned so the caller can
!> decide to fall back).  `n_ode` counts the energy/gradient evaluations and
!> is capped by `max_points` to bound the cost of one corrector call.
!>
!> A vanishing gradient ends the integration early with the point reached so
!> far (a stationary point of the DWI surface) and is reported through
!> `converged = .false.` without being an error.
subroutine landscape_irc_mbs_integrate(env, surf, x0, s_target, tol, base_points, &
      & max_k, max_points, x1, n_ode, converged, fail)
   character(len=*), parameter :: source = 'landscape_irc_mbs_integrate'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> DWI surface to integrate
   type(landscape_irc_dwi_surface), intent(in) :: surf
   !> Starting point (bohr*amu^1/2)
   real(wp), intent(in) :: x0(:)
   !> Requested arc length (bohr*amu^1/2)
   real(wp), intent(in) :: s_target
   !> Acceptance threshold of the RMS difference of two levels
   real(wp), intent(in) :: tol
   !> Base number of Euler substeps of the first level (`mbs_points`)
   integer, intent(in) :: base_points
   !> Maximum number of extrapolation levels
   integer, intent(in) :: max_k
   !> Maximum number of ODE/energy-gradient evaluations
   integer, intent(in) :: max_points
   !> End point of the integration (bohr*amu^1/2)
   real(wp), intent(out) :: x1(:)
   !> Number of energy/gradient evaluations used
   integer, intent(out) :: n_ode
   !> True if the extrapolation reached `tol`
   logical, intent(out) :: converged
   !> Failure flag (a hard error, e.g. an exhausted point budget)
   logical, intent(out) :: fail

   real(wp), allocatable :: table(:, :, :), euler_x(:), e(:, :), g(:, :)
   real(wp) :: h, gn, err, diff(size(x0))
   integer :: lev, j, isub, nsub, ndim, kmax
   logical :: hit_stationary

   fail = .false.
   converged = .false.
   n_ode = 0
   x1 = x0
   ndim = size(x0)
   if (ndim == 0 .or. surf%n <= 0) then
      call env%error("the DWI surface of the mBS integration is empty", source)
      fail = .true.
      return
   end if
   kmax = max(1, min(max_k, 30))
   allocate(table(ndim, kmax, kmax), source=0.0_wp)
   allocate(euler_x(ndim), source=0.0_wp)
   allocate(e(ndim, 1), g(ndim, 1))

   do lev = 1, kmax
      nsub = max(1, mbs_substeps(base_points, lev))
      h = s_target/real(nsub, wp)
      euler_x = x0
      hit_stationary = .false.
      do isub = 1, nsub
         if (n_ode >= max_points) then
            call env%warning("the mBS corrector exhausted its evaluation "//&
               & "budget", source)
            exit
         end if
         call landscape_irc_dwi_evaluate(surf, euler_x, e(1, 1), g(:, 1))
         n_ode = n_ode + 1
         gn = vec_norm(g(:, 1))
         if (gn <= irc_gradient_guard) then
            hit_stationary = .true.
            exit
         end if
         euler_x = euler_x + h*(-g(:, 1)/gn)
      end do
      table(:, lev, 1) = euler_x
      do j = 2, lev
         table(:, lev, j) = (2.0_wp**(j - 1)*table(:, lev, j - 1) &
            & - table(:, lev - 1, j - 1))/(2.0_wp**(j - 1) - 1.0_wp)
      end do
      if (lev >= 2) then
         diff = table(:, lev, lev) - table(:, lev - 1, lev - 1)
         err = vec_rms(diff)
         if (err <= tol) then
            converged = .true.
            x1 = table(:, lev, lev)
            return
         end if
      end if
      if (hit_stationary) then
         ! a stationary point of the DWI surface: the arc length cannot be
         ! covered, but the point is a valid (better) estimate
         x1 = euler_x
         return
      end if
      if (n_ode >= max_points) then
         x1 = table(:, lev, lev)
         return
      end if
   end do
   x1 = table(:, kmax, kmax)

end subroutine landscape_irc_mbs_integrate

!> Number of Euler substeps of extrapolation level `lev` (1-based).
pure function mbs_substeps(base_points, lev) result(nsub)
   !> Base number of substeps (`mbs_points`)
   integer, intent(in) :: base_points
   !> Extrapolation level (1-based)
   integer, intent(in) :: lev
   !> Number of Euler substeps
   integer :: nsub

   nsub = max(1, base_points)*2**(lev - 1)

end function mbs_substeps

!> One correction step of the Hessian based predictor-corrector (HPC) and the
!> Euler predictor-corrector (EulerPC): DWI surface + modified Bulirsch-Stoer.
!>
!> The two samples of the distance weighted interpolation are the **current
!> point** (`q_a`, with its true energy/gradient) and the **predicted point**
!> (`q_b`, evaluated once); this is the two point DWI of Hratchian & Schlegel,
!> J. Chem. Phys. **120**, 9918 (2004), Eqs. 5-6, and Meisner & Kaestner,
!> J. Chem. Phys. **133**, 224101 (2010), Eqs. 3-4.  The shared Hessian is the
!> mass weighted Hessian of the caller: **EulerPC** updates it with the
!> predicted secant before the correction, **HPC** does not (its predictor is
!> the analytic propagation, which does not produce a secant), so the caller
!> decides and the argument is simply `hq`.  The modified Bulirsch-Stoer
!> integrator marches the steepest
!> descent ODE of the DWI surface from `q_a` over the requested arc length and
!> returns the corrected point `q_corr` together with the DWI energy and
!> gradient there - **no further energy/gradient evaluation of the real
!> surface is made**, which is the per point cost claim of the HPC paper
!> ("one E/g per IRC point").
!>
!> `converged = .false.` (or `fail = .true.`) is the documented failure mode:
!> the caller falls back to one Gonzalez-Schlegel step and warns (PLAN
!> section 6.5).
subroutine landscape_irc_corrector_step(env, hq, q_a, e_a, g_a, q_b, e_b, g_b, &
      & s_target, tol, base_points, max_k, max_points, dwi_n, &
      & q_corr, e_corr, g_corr, converged, fail)
   character(len=*), parameter :: source = 'landscape_irc_corrector_step'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Mass weighted Hessian shared by the two samples (hartree/(bohr^2 amu))
   real(wp), intent(in) :: hq(:, :)
   !> Current point (bohr*amu^1/2)
   real(wp), intent(in) :: q_a(:)
   !> Energy of the current point (hartree)
   real(wp), intent(in) :: e_a
   !> Mass weighted gradient of the current point
   real(wp), intent(in) :: g_a(:)
   !> Predicted point (bohr*amu^1/2)
   real(wp), intent(in) :: q_b(:)
   !> Energy of the predicted point (hartree)
   real(wp), intent(in) :: e_b
   !> Mass weighted gradient of the predicted point
   real(wp), intent(in) :: g_b(:)
   !> Requested arc length (bohr*amu^1/2)
   real(wp), intent(in) :: s_target
   !> Acceptance threshold of the mBS extrapolation
   real(wp), intent(in) :: tol
   !> Base number of Euler substeps (`mbs_points`)
   integer, intent(in) :: base_points
   !> Maximum number of extrapolation levels (`mbs_max_k`)
   integer, intent(in) :: max_k
   !> Maximum number of DWI evaluations of one correction
   integer, intent(in) :: max_points
   !> Capacity of the DWI surface (>= 2)
   integer, intent(in) :: dwi_n
   !> Corrected point (bohr*amu^1/2)
   real(wp), intent(out) :: q_corr(:)
   !> DWI energy at the corrected point (hartree)
   real(wp), intent(out) :: e_corr
   !> DWI gradient at the corrected point (hartree/(bohr*amu^1/2))
   real(wp), intent(out) :: g_corr(:)
   !> True if the mBS extrapolation reached `tol`
   logical, intent(out) :: converged
   !> Failure flag of the mBS integration
   logical, intent(out) :: fail

   type(landscape_irc_dwi_surface) :: surf
   integer :: n_ode_dummy

   call landscape_irc_dwi_init(surf, hq, max(2, dwi_n))
   call landscape_irc_dwi_add(surf, q_a, e_a, g_a)
   call landscape_irc_dwi_add(surf, q_b, e_b, g_b)
   call landscape_irc_mbs_integrate(env, surf, q_a, s_target, tol, base_points, &
      & max_k, max_points, q_corr, n_ode_dummy, converged, fail)
   if (fail .or. .not. converged) then
      e_corr = e_a
      g_corr = g_a
      return
   end if
   call landscape_irc_dwi_evaluate(surf, q_corr, e_corr, g_corr)

end subroutine landscape_irc_corrector_step

!> Append one point to a path, growing the storage geometrically.
subroutine landscape_irc_path_add(path, xyz, energy, s, gnorm, gmax, n_eval)
   !> Path to extend
   type(landscape_irc_path), intent(inout) :: path
   !> Flattened geometry (bohr), length 3*nat
   real(wp), intent(in) :: xyz(:)
   !> Energy (hartree)
   real(wp), intent(in) :: energy
   !> Arc length from the transition state (bohr*amu^1/2)
   real(wp), intent(in) :: s
   !> Gradient norm (hartree/bohr)
   real(wp), intent(in) :: gnorm
   !> Maximum absolute gradient component (hartree/bohr)
   real(wp), intent(in) :: gmax
   !> Energy/gradient evaluations of the point
   integer, intent(in) :: n_eval

   integer :: nadd

   if (path%ndim /= 0 .and. path%ndim /= size(xyz)) then
      ! a path holds points of one dimension only; a different dimension means
      ! the object is being re-bound.  The container has no environment and
      ! cannot report the programming error, so it releases the storage of the
      ! old dimension instead of writing through mismatched shapes (finding
      ! F-1 of `45-m6-independent-review.md`; the production paths use one
      ! object per direction, `landscape_irc_path_reset` is the documented way
      ! to reuse one object)
      call landscape_irc_path_release(path)
   end if
   if (path%ndim == 0) path%ndim = size(xyz)
   nadd = path%n + 1
   if (.not. allocated(path%xyz) .or. nadd > path%capacity) then
      call landscape_irc_path_reserve(path, max(nadd, 32, 2*path%capacity))
   end if
   path%n = nadd
   path%xyz(:, nadd) = xyz
   path%e(nadd) = energy
   path%s(nadd) = s
   path%gnorm(nadd) = gnorm
   path%gmax(nadd) = gmax
   path%n_eval(nadd) = n_eval

end subroutine landscape_irc_path_add

!> Restore a path to its empty state so it can be reused by a new walk.
!>
!> Without the reset a second `landscape_irc_*_walk` on the same path object
!> would **append** to the first one (the storage is grown, never truncated);
!> every integrator therefore starts with this call.  The reset releases the
!> storage as well, so the same object can be reused for a path of another
!> dimension in one statement (finding F-1 of the M6 review; the caller must
!> not rely on the capacity of the released storage).
subroutine landscape_irc_path_reset(path)
   !> Path to reset
   type(landscape_irc_path), intent(inout) :: path

   path%term = p_irc_path_error
   path%n_pinned = 0
   call landscape_irc_path_release(path)

end subroutine landscape_irc_path_reset

!> Drop every point of a path and release its storage.
subroutine landscape_irc_path_release(path)
   !> Path
   type(landscape_irc_path), intent(inout) :: path

   if (allocated(path%xyz)) deallocate(path%xyz)
   if (allocated(path%e)) deallocate(path%e)
   if (allocated(path%s)) deallocate(path%s)
   if (allocated(path%gnorm)) deallocate(path%gnorm)
   if (allocated(path%gmax)) deallocate(path%gmax)
   if (allocated(path%n_eval)) deallocate(path%n_eval)
   path%n = 0
   path%ndim = 0
   path%capacity = 0

end subroutine landscape_irc_path_release

!> Reserve storage for at least `capacity` points of a path.
!>
!> The dimension of the points has to be known (`ndim > 0`, i.e. at least one
!> point was added since the last reset); `landscape_irc_path_add` allocates a
!> fresh path on its first point and calls this routine for the capacity it
!> needs.
subroutine landscape_irc_path_reserve(path, capacity)
   !> Path
   type(landscape_irc_path), intent(inout) :: path
   !> Requested capacity
   integer, intent(in) :: capacity

   real(wp), allocatable :: xyz(:, :)
   integer :: cap

   cap = max(capacity, path%capacity, 1)
   if (path%ndim == 0) return
   if (.not. allocated(path%xyz)) then
      allocate(path%xyz(path%ndim, cap), source=0.0_wp)
   else if (size(path%xyz, 2) < cap) then
      allocate(xyz(path%ndim, cap), source=0.0_wp)
      xyz(:, 1:path%n) = path%xyz(:, 1:path%n)
      call move_alloc(xyz, path%xyz)
   end if
   if (.not. allocated(path%e)) then
      allocate(path%e(cap), source=0.0_wp)
      allocate(path%s(cap), source=0.0_wp)
      allocate(path%gnorm(cap), source=0.0_wp)
      allocate(path%gmax(cap), source=0.0_wp)
      allocate(path%n_eval(cap), source=0)
   else if (size(path%e) < cap) then
      call grow_real(path%e, cap)
      call grow_real(path%s, cap)
      call grow_real(path%gnorm, cap)
      call grow_real(path%gmax, cap)
      call grow_int(path%n_eval, cap)
   end if
   path%capacity = cap

end subroutine landscape_irc_path_reserve

!> Grow a real buffer to `cap` entries, keeping the stored values.
subroutine grow_real(buffer, cap)
   !> Buffer
   real(wp), allocatable, intent(inout) :: buffer(:)
   !> New capacity
   integer, intent(in) :: cap

   real(wp), allocatable :: copy(:)

   allocate(copy(cap), source=0.0_wp)
   copy(1:size(buffer)) = buffer
   call move_alloc(copy, buffer)

end subroutine grow_real

!> Grow an integer buffer to `cap` entries, keeping the stored values.
subroutine grow_int(buffer, cap)
   !> Buffer
   integer, allocatable, intent(inout) :: buffer(:)
   !> New capacity
   integer, intent(in) :: cap

   integer, allocatable :: copy(:)

   allocate(copy(cap), source=0)
   copy(1:size(buffer)) = buffer
   call move_alloc(copy, buffer)

end subroutine grow_int

end module xtb_landscape_irc_corrector
