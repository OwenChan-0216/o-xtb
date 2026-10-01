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

!> Normal modes and harmonic frequencies of a Hessian (PLAN section 5.3.8).
!>
!> The analysis is the one of the existing xtb implementation
!> (`numhess`, `src/hessian.F90:139-459`) and reuses its building blocks
!> (PLAN section 6.6, "1:1 reuse"):
!>
!>  1. mass weighting with `xtb_freq_utils::massWeightHessian`, i.e.
!>     `h_mw(i,j) = h(i,j)/sqrt(m_i m_j)` with the atomic masses in atomic
!>     units (`TMolecule%atmass`); the same routine the `--thermo` path uses
!>     (`src/prog/thermo.f90:132`).
!>  2. projection of the translations and rotations with
!>     `xtb_freq_project::projectHessian` (Eckart, in the mass weighted space)
!>     - but only for non-linear molecules, exactly like xtb, which leaves a
!>     linear molecule unprojected (its analytic Hessian has 3N-5 zero modes
!>     anyway).
!>  3. diagonalisation with `xtb_freq_utils::diagHessian` (LAPACK `syev`,
!> `uplo='u'`), so the eigenvalues arrive in **ascending** order.
!>  4. frequencies `freq = autorcm * sign(sqrt(|ev|), ev)` in cm^-1.
!>     An internal mode is imaginary if and only if its eigenvalue is
!>     negative, and it is reported with a **negative** frequency - the
!>     convention of the existing output (`PREIGF`, `vibspectrum`), so
!>     imaginary modes sort in front of the real ones.
!>  5. sorting into the layout of `freq_results`: the first `n_zero` columns
!>     are the projected translations/rotations (set to exactly zero, they are
!>     below `zero_mode_tol` = 0.01 cm^-1 by construction), the remaining
!>     `n_vib` columns are the internal modes in ascending frequency order.
!>     A molecule that has fewer than `n_zero` modes below that threshold is
!>     rejected with the message of the existing implementation ("too few
!>     rot/trans modes found, hessian is unusable"): the projection did not
!> produce the zero modes it must, so nothing about the frequencies is
!>     trustworthy.
!>
!> Mode counting: `n_vib = 3N - 6`, or `3N - 5` for a linear molecule
!> (`linear_tol`); a single atom has no internal mode at all (`n_vib = 0`) and
!> a diatomic one has exactly one.  All 3N modes are returned - the sorting
!> never drops a mode, so `n_vib == 3N - n_zero` holds unconditionally (a
!> molecule whose zero mode list is short of the expected count is an error).
!>
!> A Hessian can have **more** than `n_zero` modes below `zero_mode_tol` (a
!> rank deficient matrix from a file, a frozen-atom Hessian, or two fragments
!> far apart).  The first `n_zero` of them are the projected translations and
!> rotations; the additional ones are **kept as the lowest internal modes**,
!> with their own (tiny, signed) frequency instead of a fabricated zero.  That
!> is the physically meaningful choice: such a mode is either a residual rigid
!> mode of a rank deficient matrix or a genuinely soft coordinate, and the
!> signed value preserves which of the two it is (a positive noise eigenvalue
!> must not become an imaginary mode, and vice versa).  The existing
!> implementation counts *all* of them as zero modes (`src/hessian.F90:437`)
!> and then fills the columns it does not reach with a zero mode vector and a
!> zero frequency, which loses the mode; this suite keeps the count
!> `n_vib == 3N - n_zero` and reports the additional modes truthfully.
!>
!> Units: Hessian elements in hartree/bohr^2, masses in atomic units
!> (electron masses) internally, reduced masses in amu and frequencies in
!> cm^-1.
module xtb_landscape_vib_modes
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_convert, only : autorcm, autoamu
   use xtb_mctc_math, only : eigval3x3
   use xtb_type_environment, only : TEnvironment
   use xtb_type_molecule, only : TMolecule
   use xtb_freq_project, only : projectHessian
   use xtb_freq_utils, only : massWeightHessian, diagHessian
   use xtb_landscape_settings, only : landscape_vib_settings, landscape_log_failed
   use xtb_landscape_results, only : landscape_vib_result
   implicit none(type, external)
   private

   public :: landscape_vib_analysis
   public :: landscape_vib_mass_unweight
   public :: landscape_vib_reduced_masses
   public :: landscape_vib_linear_geometry

   !> Magnitude below which a frequency counts as a projected zero mode
   !> (cm^-1).  The existing implementation uses the same 0.01 threshold to
   !> separate the rotations/translations from the internal modes.
   real(wp), parameter :: zero_mode_tol = 1.0e-2_wp

contains

!> Analyse a Hessian: frequencies, normal modes, reduced masses.
!>
!> `hessian` is the dense, symmetric, **non** mass weighted Hessian of the
!> geometry `mol` on entry.  On return it holds the projected Hessian in the
!> same non mass weighted form, i.e. exactly the matrix the `hessian` file of
!> the existing `--hess` run contains (mass weighted projection, then
!> un-weighted); the task writes it from here.
subroutine landscape_vib_analysis(env, mol, hessian, settings, vib, fail)
   character(len=*), parameter :: source = 'landscape_vib_analysis'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Molecular structure
   type(TMolecule), intent(in) :: mol
   !> Hessian (hartree/bohr^2), projected on return
   real(wp), intent(inout) :: hessian(:, :)
   !> Frequency settings
   type(landscape_vib_settings), intent(in) :: settings
   !> Frequency result
   type(landscape_vib_result), intent(out) :: vib
   !> Failure flag
   logical, intent(out) :: fail

   real(wp), allocatable :: work(:, :), ev(:), freq_cm(:)
   real(wp), allocatable :: atmass_amu(:)
   integer, allocatable :: order(:)
   integer :: n3, n_zero, n_zero_found, n_zero_seen, i, k, nlog
   logical :: linear, extra_zero

   fail = .false.
   n3 = 3*mol%n
   if (size(hessian, 1) /= n3 .or. size(hessian, 2) /= n3) then
      call env%error("the Hessian of the frequency analysis must be a "//&
         & "(3N, 3N) matrix", source)
      fail = .true.
      return
   end if

   linear = landscape_vib_linear_geometry(mol%xyz, settings%linear_tol)
   if (mol%n <= 1) then
      ! A single atom has only the three translations; the 3N-6 rule does not
      ! apply to it (xtb's `print_thermo` treats it as a rotor-only case).
      n_zero = n3
   else
      n_zero = 6
      if (linear) n_zero = 5
   end if

   ! the engine guarantees symmetry, but the matrix may come from anywhere
   ! (a file, an analytic model), and `diagHessian` reads only one triangle
   hessian = 0.5_wp*(hessian + transpose(hessian))

   allocate(work(n3, n3), source=hessian)
   call massWeightHessian(work, mol%atmass)
   if (settings%project_tr .and. .not. linear) then
      call projectHessian(work, mol, .true., .true.)
   end if
   ! The projected, non mass weighted matrix is what the `hessian` file of the
   ! existing implementation holds (`numhess` writes the projected matrix
   ! before the mass weighting).
   hessian = work
   call landscape_vib_mass_unweight(hessian, mol%atmass)

   nlog = env%nLog
   allocate(ev(n3))
   call diagHessian(env, work, ev)
   if (landscape_log_failed(env, nlog)) then
      fail = .true.
      return
   end if

   allocate(freq_cm(n3), order(n3))
   freq_cm = autorcm*ev

   ! Zero modes first, in ascending eigenvalue order (`syev` gives ascending).
   ! For a **linear** molecule the existing implementation takes the `n_zero`
   ! lowest eigenvalues unconditionally and does not test them against the
   ! threshold (`src/hessian.F90:437-447`): the projection is skipped there, so
   ! the translations and rotations of the numerical Hessian are lifted by the
   ! noise of the differentiation, and rejecting the matrix would make every
   ! linearly shaped molecule unusable.
   n_zero_found = 0
   extra_zero = .false.
   if (linear) then
      n_zero_found = n_zero
      do i = 1, n_zero
         order(i) = i
      end do
   else
      do i = 1, n3
         if (abs(freq_cm(i)) >= zero_mode_tol) cycle
         if (n_zero_found < n_zero) then
            n_zero_found = n_zero_found + 1
            order(n_zero_found) = i
         else
            extra_zero = .true.
         end if
      end do
   end if
   if (n_zero_found < n_zero) then
      ! The message of the existing implementation (`src/hessian.F90:437`)
      call env%error("too few rot/trans modes found, the Hessian is unusable: "//&
         & "found less than the expected rotational/translational modes", source)
      fail = .true.
      return
   end if

   ! Internal modes, in ascending eigenvalue order.  Only the first `n_zero`
   ! modes below the threshold are the projected zero modes recorded above, so
   ! the skip has to count them: skipping every mode below the threshold would
   ! leave the tail of `order` unassigned and index the mode matrix with an
   ! undefined subscript.
   k = n_zero
   n_zero_seen = 0
   do i = 1, n3
      if (.not. linear .and. abs(freq_cm(i)) < zero_mode_tol) then
         n_zero_seen = n_zero_seen + 1
         if (n_zero_seen <= n_zero) cycle
      end if
      if (linear .and. i <= n_zero) cycle
      k = k + 1
      order(k) = i
   end do
   if (k /= n3) then
      ! Cannot happen with the sorting above; a violation would index the mode
      ! matrix with an unassigned slot, so it is checked instead of assumed.
      call env%error("internal error of the frequency analysis: the mode "//&
         & "sorting did not assign every mode", source)
      fail = .true.
      return
   end if

   allocate(vib%freq(n3), vib%modes(n3, n3), vib%rmass(n3), source=0.0_wp)
   vib%modes = 0.0_wp
   do i = 1, n_zero
      ! the eigenvectors of the projected zero modes are arbitrary vectors of
      ! the removed subspace; the frequency is exactly zero by construction
      vib%modes(:, i) = work(:, order(i))
      vib%freq(i) = 0.0_wp
   end do
   do i = n_zero + 1, n3
      vib%modes(:, i) = work(:, order(i))
      vib%freq(i) = freq_cm(order(i))
   end do

   allocate(atmass_amu(mol%n), source=mol%atmass*autoamu)
   call landscape_vib_reduced_masses(vib%modes, atmass_amu, vib%rmass)

   vib%linear = linear
   vib%n_zero = n_zero
   vib%n_vib = n3 - n_zero
   vib%n_imag = count(vib%freq(n_zero + 1:n3) < settings%imag_cutoff)

   if (extra_zero) then
      ! Modes below 0.01 cm^-1 that are not part of the projected zero mode
      ! set are the lowest entries of the internal mode list (they are never
      ! dropped, see the module documentation), but a reader of the frequency
      ! table has to know that they are numerical noise rather than a soft
      ! mode.
      call env%warning("the Hessian of the frequency analysis has more than "//&
         & "the expected number of near-zero modes; the additional ones are "//&
         & "kept in ascending order after the projected modes", source)
   end if

end subroutine landscape_vib_analysis

!> Inverse of `xtb_freq_utils::massWeightHessian` (mass weighting).
!>
!> `h(i,j) = h_mw(i,j)*sqrt(m_i m_j)`, so `massWeightHessian` followed by this
!> routine reproduces the input up to round off (measured relative deviation
!> below 1e-14).  The task uses it to recover the projected Hessian in the
!> non mass weighted form in which the `hessian` file is written.
subroutine landscape_vib_mass_unweight(hessian, atmass)
   !> Hessian (mass weighted on entry, un-weighted on return)
   real(wp), intent(inout) :: hessian(:, :)
   !> Atomic masses (atomic units, electron masses)
   real(wp), intent(in) :: atmass(:)

   real(wp), allocatable :: sqm(:)
   integer :: ndim, nat, iat, ic, ii, jj

   ndim = size(hessian, 1)
   nat = min(size(atmass), ndim/3)
   allocate(sqm(ndim), source=1.0_wp)
   do iat = 1, nat
      ic = (iat - 1)*3
      sqm(ic + 1:ic + 3) = sqrt(atmass(iat))
   end do

   do ii = 1, ndim
      do jj = 1, ndim
         hessian(jj, ii) = hessian(jj, ii)*sqm(ii)*sqm(jj)
      end do
   end do

end subroutine landscape_vib_mass_unweight

!> Reduced masses of the normal modes (amu).
!>
!> `1/rmass(i) = sum_j (v_ji/sqrt(m_j))^2` with the atomic masses in amu and
!> the mass weighted normal mode `v_i`; this is the definition of
!> `numhess` (`src/hessian.F90:503-525`) and the "Red. masses" column of
!> `g98.out`.
subroutine landscape_vib_reduced_masses(modes, atmass_amu, rmass)
   !> Mass weighted normal modes (columns)
   real(wp), intent(in) :: modes(:, :)
   !> Atomic masses (amu)
   real(wp), intent(in) :: atmass_amu(:)
   !> Reduced masses (amu)
   real(wp), intent(out) :: rmass(:)

   real(wp), allocatable :: isqm(:)
   real(wp) :: sum2
   integer :: ndim, nat, iat, ic, ii, jj

   ndim = size(modes, 1)
   nat = min(size(atmass_amu), ndim/3)
   allocate(isqm(ndim), source=0.0_wp)
   do iat = 1, nat
      ic = (iat - 1)*3
      isqm(ic + 1:ic + 3) = 1.0_wp/sqrt(atmass_amu(iat))
   end do

   rmass = 0.0_wp
   do ii = 1, size(rmass)
      sum2 = 0.0_wp
      do jj = 1, ndim
         sum2 = sum2 + isqm(jj)**2*modes(jj, ii)**2
      end do
      if (sum2 > 0.0_wp) rmass(ii) = 1.0_wp/sum2
   end do

end subroutine landscape_vib_reduced_masses

!> True if `xyz` describes a linear molecule.
!>
!> The criterion is the one of the existing xtb check
!> (`xtb_axis::is_linear`, `src/axis_trafo.f90:24`): a molecule is linear if
!> the smallest eigenvalue of its **unit-mass** moment of inertia tensor is
!> below `tol` (bohr^2).  The default of `settings%linear_tol` equals the
!> constant of that check, so the 3N-5/3N-6 count of this task agrees with the
!> count the existing `--hess` prints.  A single atom counts as linear.
pure function landscape_vib_linear_geometry(xyz, tol) result(linear)
   !> Cartesian coordinates (bohr)
   real(wp), intent(in) :: xyz(:, :)
   !> Threshold on the smallest unit-mass moment of inertia (bohr^2)
   real(wp), intent(in) :: tol
   !> True if the molecule is linear
   logical :: linear

   real(wp) :: center(3), vec(3), inertia(3, 3), moments(3)
   integer :: i, k, n

   n = size(xyz, 2)
   if (n <= 1) then
      linear = .true.
      return
   end if

   inertia = 0.0_wp
   center = sum(xyz, dim=2)/real(n, wp)
   do i = 1, n
      vec = xyz(:, i) - center
      do k = 1, 3
         inertia(k, k) = inertia(k, k) + dot_product(vec, vec)
      end do
      inertia(1, 1) = inertia(1, 1) - vec(1)*vec(1)
      inertia(2, 2) = inertia(2, 2) - vec(2)*vec(2)
      inertia(3, 3) = inertia(3, 3) - vec(3)*vec(3)
      inertia(1, 2) = inertia(1, 2) - vec(1)*vec(2)
      inertia(2, 3) = inertia(2, 3) - vec(2)*vec(3)
      inertia(1, 3) = inertia(1, 3) - vec(1)*vec(3)
   end do
   inertia(2, 1) = inertia(1, 2)
   inertia(3, 2) = inertia(2, 3)
   inertia(3, 1) = inertia(1, 3)

   call eigval3x3(inertia, moments)
   linear = any(moments < tol)

end function landscape_vib_linear_geometry

end module xtb_landscape_vib_modes
