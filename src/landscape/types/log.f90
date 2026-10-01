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

!> Geometry and trajectory output of the landscape task suite.
!>
!> This module is the single place in the landscape suite that touches the
!> molecule data type and the xtb writer (`xtb_io_writer::writeMolecule`), as
!> required by PLAN section 4.2: the `optimize/**` layer must stay free of the
!> xtb private types.
!>
!> Units: coordinates and trajectory frames in bohr, energies in hartree.
module xtb_landscape_log
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_filetypes, only : fileType
   use xtb_io_writer, only : writeMolecule
   use xtb_type_environment, only : TEnvironment
   use xtb_type_molecule, only : TMolecule, init
   use xtb_landscape_settings, only : landscape_opt_settings
   use xtb_landscape_results, only : landscape_result
   use xtb_landscape_coords, only : geometry_unpack
   implicit none(type, external)
   private

   public :: landscape_write_files

contains

!> Write the optimised geometry and the trajectory.
!>
!> The final geometry is stored as `<prefix>opt.xyz` and the trajectory as
!> `<prefix>.trj` (concatenated xyz frames), both through
!> `xtb_io_writer::writeMolecule`.
subroutine landscape_write_files(env, mol, settings, traj, result)
   character(len=*), parameter :: source = 'landscape_write_files'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Molecular structure holding the optimised geometry
   type(TMolecule), intent(in) :: mol
   !> Optimisation settings
   type(landscape_opt_settings), intent(in) :: settings
   !> Trajectory frames (bohr)
   real(wp), allocatable, intent(in) :: traj(:, :)
   !> Optimisation result
   type(landscape_result), intent(in) :: result

   type(TMolecule) :: buffer
   character(len=:), allocatable :: fname
   integer :: unit, ierr, iframe

   fname = trim(settings%output_prefix)//'opt.xyz'
   open(newunit=unit, file=fname, action='write', iostat=ierr)
   if (ierr /= 0) then
      call env%error("cannot open "//fname, source)
      return
   end if
   call writeMolecule(mol, unit, format=fileType%xyz, energy=result%energy, &
      & gnorm=result%gnorm)
   close(unit)
   write(env%unit, '(1x,a,a)') "wrote ", fname

   if (.not. allocated(traj)) return
   if (size(traj, 2) == 0) return
   fname = trim(settings%output_prefix)//'.trj'
   open(newunit=unit, file=fname, action='write', iostat=ierr)
   if (ierr /= 0) then
      call env%error("cannot open "//fname, source)
      return
   end if
   call init(buffer, mol%at, mol%xyz, chrg=mol%chrg, uhf=mol%uhf, &
      & lattice=mol%lattice, pbc=mol%pbc)
   ! The buffer is rebuilt with `init` instead of `buffer = mol`.  Minimally
   ! reproduced: with the derived assignment the element labels of the
   ! trajectory frames are written as NUL-prefixed garbage for every atom after
   ! the first (the coordinates stay correct), while the `init` reconstruction
   ! produces clean labels.  The corruption is already visible in `buffer%sym`
   ! right after the assignment (see docs/_landscape-recon/12-*.md).  The
   ! mechanism was not localised, so this comment records the observed symptom
   ! and the workaround, not a root cause.
   do iframe = 1, size(traj, 2)
      call geometry_unpack(traj(:, iframe), buffer%xyz)
      call writeMolecule(buffer, unit, format=fileType%xyz, number=iframe)
   end do
   close(unit)
   write(env%unit, '(1x,a,a)') "wrote ", fname

end subroutine landscape_write_files

end module xtb_landscape_log
