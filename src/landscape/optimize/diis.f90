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

!> Geometry DIIS (GDIIS) extrapolation of the landscape suite.
!>
!> The extrapolated geometry is `x_diis = sum_i c_i x_i` with coefficients
!> minimising `|sum_i c_i g_i|` under `sum_i c_i = 1`, i.e. the solution of the
!> augmented linear system
!>
!> ```text
!>   [ B  -1 ] [ c ]   [ 0 ]
!>   [-1^T 0 ] [ l ] = [-1 ],   B_ij = g_i . g_j
!> ```
!>
!> which is regularised with a Tikhonov term on the diagonal of `B` to remain
!> solvable for linearly dependent gradient sets
!> (Csaszar & Pulay, J. Mol. Struct. 114, 31 (1984); Farkas & Schlegel,
!> Phys. Chem. Chem. Phys. 4, 11 (2002)).
!>
!> Units: coordinates in bohr, gradients in hartree/bohr.
module xtb_landscape_diis
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_lapack, only : mctc_getrf, mctc_getrs
   use xtb_type_environment, only : TEnvironment
   use xtb_landscape_settings, only : landscape_log_failed
   implicit none(type, external)
   private

   public :: landscape_diis_type, new_landscape_diis

   !> Smallest absolute floor added to the relative Tikhonov regularisation
   real(wp), parameter :: regularization_floor = 1.0e-14_wp

   !> GDIIS history store.
   type :: landscape_diis_type
      !> Maximum number of stored geometries
      integer :: memory = 6
      !> Number of stored geometries
      integer :: nstore = 0
      !> Minimum number of stored geometries before extrapolation is used
      integer :: min_vectors = 3
      !> Relative Tikhonov regularisation of the DIIS matrix
      real(wp) :: regularization = 1.0e-10_wp
      !> Stored geometries (bohr), shape `(ndim, memory)`
      real(wp), allocatable :: x(:, :)
      !> Stored gradients (hartree/bohr), shape `(ndim, memory)`
      real(wp), allocatable :: g(:, :)
   contains
      !> Drop the stored history
      procedure :: reset => diis_reset
      !> Store a geometry/gradient pair
      procedure :: push => diis_push
      !> GDIIS displacement from the current geometry
      procedure :: direction => diis_direction
   end type landscape_diis_type

contains

!> Allocate a GDIIS optimiser state.
subroutine new_landscape_diis(self, ndim, memory, regularization, min_vectors)
   !> New optimiser state
   type(landscape_diis_type), intent(out) :: self
   !> Dimension of the coordinate vector (3N)
   integer, intent(in) :: ndim
   !> Number of stored geometries
   integer, intent(in) :: memory
   !> Relative Tikhonov regularisation
   real(wp), intent(in), optional :: regularization
   !> Minimum number of snapshots before extrapolation is used
   integer, intent(in), optional :: min_vectors

   if (present(regularization)) self%regularization = regularization
   if (present(min_vectors)) self%min_vectors = max(min_vectors, 2)
   self%memory = max(memory, 1)
   allocate(self%x(ndim, self%memory), source=0.0_wp)
   allocate(self%g(ndim, self%memory), source=0.0_wp)
   self%nstore = 0

end subroutine new_landscape_diis

!> Drop all stored geometries.
subroutine diis_reset(self)
   !> Optimiser state
   class(landscape_diis_type), intent(inout) :: self

   self%nstore = 0

end subroutine diis_reset

!> Store a geometry/gradient pair, shifting out the oldest snapshot when the
!> store is full.
subroutine diis_push(self, x, gradient)
   !> Optimiser state
   class(landscape_diis_type), intent(inout) :: self
   !> Geometry (bohr)
   real(wp), intent(in) :: x(:)
   !> Gradient (hartree/bohr)
   real(wp), intent(in) :: gradient(:)

   integer :: i

   if (self%nstore >= self%memory) then
      do i = 2, self%memory
         self%x(:, i - 1) = self%x(:, i)
         self%g(:, i - 1) = self%g(:, i)
      end do
      self%nstore = self%memory - 1
   end if
   self%nstore = self%nstore + 1
   self%x(:, self%nstore) = x
   self%g(:, self%nstore) = gradient

end subroutine diis_push

!> GDIIS displacement `x_diis - x`.
!>
!> Returns `ok = .false.` if fewer than `min_vectors` snapshots are available
!> or if the augmented system is singular even after regularisation; the caller
!> should then fall back to a different step.  The optional `coefficients`
!> argument returns the GDIIS weights `c_i` of the `nstore` snapshots (the
!> first `nstore` entries are filled); they satisfy `sum(c_i) = 1` by the
!> constraint row of the augmented system.
subroutine diis_direction(self, env, x, direction, ok, coefficients)
   !> Optimiser state
   class(landscape_diis_type), intent(in) :: self
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Current geometry (bohr)
   real(wp), intent(in) :: x(:)
   !> GDIIS displacement (bohr)
   real(wp), intent(out) :: direction(:)
   !> True if an extrapolated step was produced
   logical, intent(out) :: ok
   !> GDIIS weights of the stored snapshots (must hold at least `nstore` items)
   real(wp), intent(out), optional :: coefficients(:)

   real(wp), allocatable :: amat(:, :), rhs(:), coeff(:), x_diis(:)
   integer, allocatable :: ipiv(:)
   real(wp) :: dscale, reg
   logical :: failed
   integer :: i, j, n, nlog

   ok = .false.
   direction = 0.0_wp
   n = self%nstore
   if (n < self%min_vectors) return

   allocate(amat(n + 1, n + 1), source=0.0_wp)
   allocate(rhs(n + 1), coeff(n + 1), ipiv(n + 1))
   allocate(x_diis(size(x)), source=0.0_wp)

   dscale = 0.0_wp
   do j = 1, n
      do i = 1, n
         amat(i, j) = dot_product(self%g(:, i), self%g(:, j))
      end do
      dscale = max(dscale, abs(amat(j, j)))
   end do
   ! A relative Tikhonov term: the floor only guards the fully collapsed
   ! (vanishing gradient) case, otherwise `reg` scales with the largest
   ! diagonal element of `B`.  The previous `max(dscale, 1.0_wp)` degenerated
   ! to the absolute value 1e-10 because |g_i|^2 < 1 for every molecular
   ! gradient.
   reg = self%regularization*max(dscale, regularization_floor)
   do i = 1, n
      amat(i, i) = amat(i, i) + reg
      amat(n + 1, i) = -1.0_wp
      amat(i, n + 1) = -1.0_wp
   end do

   rhs = 0.0_wp
   rhs(n + 1) = -1.0_wp

   ! Probe only the messages appended by this factorisation; env%check()
   ! accumulates over the whole run and would mis-classify the call under
   ! --strict after any earlier warning.
   nlog = env%nLog
   call mctc_getrf(env, amat, ipiv)
   call mctc_getrs(env, amat, rhs, ipiv)
   failed = landscape_log_failed(env, nlog)
   if (failed) return

   coeff = rhs
   if (present(coefficients)) coefficients(1:n) = rhs(1:n)
   do i = 1, n
      x_diis = x_diis + coeff(i)*self%x(:, i)
   end do
   direction = x_diis - x
   ok = .true.

end subroutine diis_direction

end module xtb_landscape_diis
