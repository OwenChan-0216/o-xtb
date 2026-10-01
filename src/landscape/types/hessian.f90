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

!> Hessian providers of the xtb landscape task suite (PLAN D3).
!>
!> The Hessian is the only quantity that every landscape task needs
!> (RFO/PRFO, IRC and frequency analysis), so the way it is produced is
!> abstracted behind `landscape_hessian_provider`.  The settings field
!> `hessian_source` selects the implementation through
!> `new_landscape_hessian_provider`; an unknown name is reported with
!> `env%error` and no provider is returned (never a silent fallback).
!>
!> Available sources:
!>
!>  * `numerical` -- `landscape_numerical_hessian_provider`, a self-built
!>    central difference Hessian.  The finite difference step and the SCC
!>    accuracy of the displaced single points are **explicit parameters**
!>    (`step` argument, `sccacc` component); the suite must not rely on the
!>    `$hess` control block, whose numeric keys are silently ignored on the
!>    non-`--copy` path (`docs/_landscape-recon/07-*.md`, section 4).
!>    Every displaced geometry is evaluated from the same wavefunction, so
!>    the whole differentiation sequence uses one restart policy (07-*.md,
!>    section 3.3) and the Hessian is deterministic.
!>  * `model` -- `landscape_model_hessian_provider`, an approximate model
!>    Hessian (Lindh-D2, `src/model_hessian/`) used as a cheap initial guess
!>    for RFO/BFGS.  It reuses the existing xtb model-Hessian implementation
!>    with the default force constants of `set%mhset`
!>    (`src/setparam.f90:267-278`) and does not evaluate the calculator at all
!>    (`n_eval = 0`).
!>  * an analytic GFN2 Hessian only has to add another extension of
!>    `landscape_hessian_provider` and a `hessian_source` name.
!>
!> Units: coordinates in bohr, energies in hartree, gradients in hartree/bohr
!> and Hessian matrix elements in hartree/bohr^2.  The returned Hessian is
!> dense and exactly symmetric.
module xtb_landscape_hessian
   use xtb_mctc_accuracy, only : wp
   use xtb_type_environment, only : TEnvironment
   use xtb_type_molecule, only : TMolecule
   use xtb_type_restart, only : TRestart
   use xtb_type_calculator, only : TCalculator
   use xtb_type_data, only : scc_results
   use xtb_type_setvar, only : modhess_setvar
   use xtb_modelhessian_type, only : TModelHessian
   use xtb_modelhessian_lindh, only : newLindhD2ModelHessian
   use xtb_landscape_settings, only : landscape_log_failed
   implicit none(type, external)
   private

   public :: landscape_hessian_provider
   public :: landscape_numerical_hessian_provider
   public :: landscape_model_hessian_provider
   public :: landscape_hessian_source_known
   public :: new_landscape_hessian_provider

   !> Print level of the displaced single points of the numerical Hessian.
   !> Negative values silence the calculator, exactly like the numerical
   !> Hessian of xtb itself (`get_gradient_derivs` in
   !> `src/type/calculator.f90`).
   integer, parameter :: displacement_printlevel = -1

   !> Abstract Hessian provider.
   !>
   !> `name` repeats the `hessian_source` string that selected the provider
   !> (for reports), `exact` is true for analytic implementations.
   type, abstract :: landscape_hessian_provider
      !> Provider name, one of the `hessian_source` values
      character(len=:), allocatable :: name
      !> True if the provider returns an exact (analytic) Hessian
      logical :: exact = .false.
      !> Number of energy/gradient evaluations performed by the last `compute`
      !> (0 for providers that do not displace the geometry); the engine adds
      !> it to its cost counter so the reported cost is not underestimated.
      integer :: n_eval = 0
   contains
      !> Compute a dense, symmetric Hessian (hartree/bohr^2)
      procedure(hessian_compute), deferred :: compute
   end type landscape_hessian_provider

   abstract interface
      subroutine hessian_compute(self, env, mol, chk, calc, hess, step, odlr, final_err)
         import :: landscape_hessian_provider, TEnvironment, TMolecule, &
            & TRestart, TCalculator, wp
         !> Provider instance
         class(landscape_hessian_provider), intent(inout) :: self
         !> Computational environment
         type(TEnvironment), intent(inout) :: env
         !> Molecular structure, restored on return
         type(TMolecule), intent(inout) :: mol
         !> Wavefunction data
         type(TRestart), intent(inout) :: chk
         !> Single point calculator
         class(TCalculator), intent(inout) :: calc
         !> Dense Hessian (3N, 3N) in hartree/bohr^2, symmetrised on return
         real(wp), intent(inout) :: hess(:, :)
         !> Finite difference step (bohr)
         real(wp), intent(in) :: step
         !> Use the ODLR approximation
         logical, intent(in) :: odlr
         !> Residual error estimate of the approximation (0 for exact data)
         real(wp), intent(out) :: final_err
      end subroutine hessian_compute
   end interface

   !> Self-built central difference Hessian.
   !>
   !> `hess(:, 3(i-1)+c) = (g(x + step*e_ic) - g(x - step*e_ic)) / (2 step)`.
   !> The calculator accuracy is set to `sccacc` for the displaced geometries
   !> and restored afterwards; the wavefunction of every displacement is reset
   !> from the incoming state, so the sequence never mixes restart policies.
   !>
   !> Cost: 6N energy/gradient evaluations (`src/hessian.F90`, PLAN D3).
   type, extends(landscape_hessian_provider) :: landscape_numerical_hessian_provider
      !> SCC accuracy used while building the Hessian (explicit parameter)
      real(wp) :: sccacc = 0.3_wp
   contains
      !> Central difference Hessian
      procedure :: compute => numerical_hessian_compute
   end type landscape_numerical_hessian_provider

   !> Model Hessian provider (Lindh-D2 initial guess, PLAN D3).
   !>
   !> Reuses the xtb model Hessian of `src/model_hessian/lindh.f90`
   !> (`newLindhD2ModelHessian`, the parameterisation selected by the default
   !> `set%mhset%model = p_modh_old`) with the default force constants
   !> (`src/setparam.f90:267-278`).  The construction is purely algebraic, so
   !> the provider never touches the calculator and reports `n_eval = 0`.
   type, extends(landscape_hessian_provider) :: landscape_model_hessian_provider
   contains
      !> Lindh-D2 model Hessian
      procedure :: compute => model_hessian_compute
   end type landscape_model_hessian_provider

contains

!> True if `source` names a known Hessian provider.
pure function landscape_hessian_source_known(source) result(known)
   !> Value of the `hessian_source` setting
   character(len=*), intent(in) :: source
   !> True if the name can be resolved by `new_landscape_hessian_provider`
   logical :: known

   select case (trim(source))
   case ('numerical', 'model')
      known = .true.
   case default
      known = .false.
   end select

end function landscape_hessian_source_known

!> Construct the Hessian provider selected by `source`.
!>
!> On return `provider` is allocated if and only if the name is known;
!> an unknown name is reported with `env%error` and the caller must abort
!> (there is no default provider on this path, a silent fallback would make
!> the configured `hessian_source` a lie).
subroutine new_landscape_hessian_provider(env, source, provider, sccacc)
   character(len=*), parameter :: source_name = 'new_landscape_hessian_provider'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Value of the `hessian_source` setting
   character(len=*), intent(in) :: source
   !> Selected provider, unallocated for an unknown name
   class(landscape_hessian_provider), allocatable, intent(out) :: provider
   !> SCC accuracy of the numerical Hessian, defaults to xtb `accu_hess`
   real(wp), intent(in), optional :: sccacc

   real(wp) :: scc_accuracy

   scc_accuracy = 0.3_wp
   if (present(sccacc)) scc_accuracy = sccacc

   select case (trim(source))
   case ('numerical')
      allocate(landscape_numerical_hessian_provider :: provider)
      select type (hp => provider)
      type is (landscape_numerical_hessian_provider)
         hp%sccacc = scc_accuracy
      end select
      provider%name = 'numerical'
      provider%exact = .false.
   case ('model')
      allocate(landscape_model_hessian_provider :: provider)
      provider%name = 'model'
      provider%exact = .false.
   case default
      call env%error("unknown hessian source: "//trim(source), source_name)
   end select

end subroutine new_landscape_hessian_provider

!> Central difference Hessian of the attached calculator.
!>
!> The incoming geometry and wavefunction define the reference state of the
!> differentiation: every displaced single point starts from that state and the
!> calculator accuracy is swapped for `self%sccacc` for the whole sequence.
!> The geometry of `mol` and the accuracy of `calc` are restored before the
!> routine returns, also on the error path.
subroutine numerical_hessian_compute(self, env, mol, chk, calc, hess, step, odlr, final_err)
   character(len=*), parameter :: source = 'landscape_numerical_hessian_compute'
   !> Provider instance
   class(landscape_numerical_hessian_provider), intent(inout) :: self
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Molecular structure, restored on return
   type(TMolecule), intent(inout) :: mol
   !> Wavefunction data
   type(TRestart), intent(inout) :: chk
   !> Single point calculator
   class(TCalculator), intent(inout) :: calc
   !> Dense Hessian (3N, 3N), symmetrised on return
   real(wp), intent(inout) :: hess(:, :)
   !> Finite difference step (bohr)
   real(wp), intent(in) :: step
   !> Use the ODLR approximation
   logical, intent(in) :: odlr
   !> Residual error estimate (always zero for the full central difference)
   real(wp), intent(out) :: final_err

   real(wp), allocatable :: x0(:, :), xyz_plus(:, :), xyz_minus(:, :)
   real(wp), allocatable :: g_plus(:, :), g_minus(:, :)
   type(TRestart) :: wfn_ref
   type(scc_results) :: results
   real(wp) :: accuracy, egap, energy_plus, energy_minus
   real(wp) :: sigma(3, 3)
   integer :: iat, ic, icol, n, nlog

   final_err = 0.0_wp
   self%n_eval = 0
   n = mol%n
   if (n <= 0) return

   if (odlr) then
      call env%error("the numerical Hessian provider always builds the full "//&
         & "dense Hessian and does not support the ODLR approximation", source)
      return
   end if
   if (step <= 0.0_wp) then
      call env%error("the finite difference step of the numerical Hessian "//&
         & "must be positive", source)
      return
   end if

   allocate(x0(3, n), xyz_plus(3, n), xyz_minus(3, n))
   allocate(g_plus(3, n), g_minus(3, n))
   x0 = mol%xyz
   call wfn_ref%copy(chk)
   accuracy = calc%accuracy
   calc%accuracy = self%sccacc
   egap = 0.0_wp
   sigma = 0.0_wp

   do iat = 1, n
      do ic = 1, 3
         icol = 3*(iat - 1) + ic
         xyz_plus = x0
         xyz_plus(ic, iat) = x0(ic, iat) + step
         xyz_minus = x0
         xyz_minus(ic, iat) = x0(ic, iat) - step

         nlog = env%nLog
         mol%xyz = xyz_plus
         call chk%copy(wfn_ref)
         call calc%singlepoint(env, mol, chk, displacement_printlevel, .true., &
            & energy_plus, g_plus, sigma, egap, results)
         self%n_eval = self%n_eval + 1
         if (landscape_log_failed(env, nlog)) then
            call numerical_hessian_cleanup()
            return
         end if

         mol%xyz = xyz_minus
         call chk%copy(wfn_ref)
         call calc%singlepoint(env, mol, chk, displacement_printlevel, .true., &
            & energy_minus, g_minus, sigma, egap, results)
         self%n_eval = self%n_eval + 1
         if (landscape_log_failed(env, nlog)) then
            call numerical_hessian_cleanup()
            return
         end if

         hess(:, icol) = hess(:, icol) &
            & + reshape(g_plus - g_minus, [3*n])/(2.0_wp*step)
      end do
   end do

   call numerical_hessian_cleanup()
   hess = 0.5_wp*(hess + transpose(hess))

contains

   !> Restore the geometry, the calculator accuracy and the wavefunction of
   !> the reference state.  The wavefunction is restored because the last
   !> displaced evaluation above (and the `chk%copy` inside the loop) would
   !> otherwise leak a displaced SCF state back to the caller, which matters
   !> for the `warm` restart policy.
   subroutine numerical_hessian_cleanup()
      mol%xyz = x0
      calc%accuracy = accuracy
      call chk%copy(wfn_ref)
   end subroutine numerical_hessian_cleanup

end subroutine numerical_hessian_compute

!> Lindh-D2 model Hessian (initial guess for RFO/BFGS).
!>
!> The model Hessian is built in redundant internal coordinates and contracted
!> to Cartesian by the existing xtb implementation
!> (`TModelHessian%compute`, `src/model_hessian/type.f90:41`); the provider
!> only supplies the geometry and the atomic numbers.  The construction is
!> algebraic and deterministic, so it costs no energy evaluation.
subroutine model_hessian_compute(self, env, mol, chk, calc, hess, step, odlr, final_err)
   !> Provider instance
   class(landscape_model_hessian_provider), intent(inout) :: self
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Molecular structure
   type(TMolecule), intent(inout) :: mol
   !> Wavefunction data (unused, the model Hessian is geometry only)
   type(TRestart), intent(inout) :: chk
   !> Single point calculator (unused)
   class(TCalculator), intent(inout) :: calc
   !> Dense Hessian (3N, 3N), symmetrised on return
   real(wp), intent(inout) :: hess(:, :)
   !> Finite difference step (bohr), unused
   real(wp), intent(in) :: step
   !> Use the ODLR approximation, unused
   logical, intent(in) :: odlr
   !> Residual error estimate (0, the model is analytic in the geometry)
   real(wp), intent(out) :: final_err

   class(TModelHessian), allocatable :: model
   type(modhess_setvar) :: modh
   integer :: n

   final_err = 0.0_wp
   self%n_eval = 0
   n = mol%n
   if (n <= 0) return

   ! Defaults of `set%mhset` (`src/setparam.f90:267-278`): the 1995 Lindh
   ! parameterisation with the standard stretch/bend/torsion force constants.
   modh%kr = 0.4_wp
   modh%kf = 0.13_wp
   modh%kt = 0.0075_wp
   modh%ko = 0.0_wp
   modh%kd = 0.0_wp
   modh%kq = 0.0_wp
   modh%rcut = 70.0_wp
   modh%s6 = 20.0_wp

   allocate(model, source=newLindhD2ModelHessian(modh))
   hess = 0.0_wp
   call model%compute(env, mol%xyz, n, hess, mol%at)
   hess = 0.5_wp*(hess + transpose(hess))

end subroutine model_hessian_compute

end module xtb_landscape_hessian
