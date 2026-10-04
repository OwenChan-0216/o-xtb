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
!> The file names pass through the xtb file namespace (`get_namespace`), like
!> every other landscape output name (`tasks/scan.f90:419`, `tasks/vib.f90:390`,
!> `tasks/ts.f90:600`, `tasks/irc.f90:948`) and like the pre-existing `--opt`,
!> whose `xtbopt.xyz` is written through `open_file` and therefore carries the
!> prefix as well.  Without `--namespace` the names stay `xtbopt.xyz` and
!> `xtb.trj`, so tool chains which read the default names are unaffected.
!>
!> Units: coordinates and trajectory frames in bohr, energies in hartree.
module xtb_landscape_log
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_filetypes, only : fileType, generateFileName
   use xtb_io_writer, only : writeMolecule
   use xtb_type_environment, only : TEnvironment
   use xtb_type_molecule, only : TMolecule, init
   use xtb_setparam, only : get_namespace
   use xtb_landscape_settings, only : landscape_opt_settings
   use xtb_landscape_results, only : landscape_result
   use xtb_landscape_coords, only : geometry_unpack
   implicit none(type, external)
   private

   public :: landscape_write_files
   public :: landscape_file_contract_reset
   public :: landscape_file_contract_mark
   public :: landscape_write_last_geometry

contains

!> Write the optimised geometry and the trajectory.
!>
!> The final geometry is stored as `<prefix>opt.xyz` and the trajectory as
!> `<prefix>.trj` (concatenated xyz frames), both through
!> `xtb_io_writer::writeMolecule`.  Both names go through `get_namespace`, so a
!> run with `--namespace ns` writes `ns.<prefix>opt.xyz` / `ns.<prefix>.trj`
!> and a run without it keeps `xtbopt.xyz` / `xtb.trj`.
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

   character(len=:), allocatable :: fname
   integer :: unit, ierr

   fname = get_namespace(trim(settings%output_prefix)//'opt.xyz')
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
   ! The step-by-step trajectory is written under both names: `xtb.trj` is the
   ! name the landscape suite has always used, `xtbopt.log` is the name the
   ! native ANCopt optimiser uses (`src/geoopt_driver.f90:121` opens it, the
   ! frames are appended by `src/optimizer.f90:801`).  Both are XMOL multi
   ! frame files, and both names carry the namespace, so a `--namespace ns`
   ! run keeps them apart (`ns.xtb.trj`, `ns.xtbopt.log`).  BC-3 of the CLI
   ! redesign allows the added `xtbopt.log` because the set of files written
   ! without `--namespace` never shrinks.
   call write_trajectory_file(env, mol, trim(settings%output_prefix)//'.trj', &
      & traj)
   call write_trajectory_file(env, mol, 'xtbopt.log', traj)

end subroutine landscape_write_files

!> Write one concatenated XMOL trajectory file under `basename`.
subroutine write_trajectory_file(env, mol, basename, traj)
   character(len=*), parameter :: source = 'write_trajectory_file'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Molecular structure holding the optimised geometry
   type(TMolecule), intent(in) :: mol
   !> File name before the namespace prefix is applied
   character(len=*), intent(in) :: basename
   !> Trajectory frames (bohr)
   real(wp), intent(in) :: traj(:, :)

   type(TMolecule) :: buffer
   character(len=:), allocatable :: fname
   integer :: unit, ierr, iframe

   fname = get_namespace(basename)
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

end subroutine write_trajectory_file

!> Remove the convergence sentinels of a previous run.
!>
!> The upstream geometry task deletes `NOT_CONVERGED` and `.xtboptok` when it
!> starts (`src/geoopt_driver.f90:112-113`), so a stale sentinel of an earlier
!> run can never mask the outcome of the current one.  The names go through
!> the namespace, exactly like the upstream `delete_file`
!> (`src/filetools.F90:28` -> `iohandler%getName`).
subroutine landscape_file_contract_reset(env)
   !> Computational environment
   type(TEnvironment), intent(inout) :: env

   call delete_namespaced('NOT_CONVERGED')
   call delete_namespaced('.xtboptok')

end subroutine landscape_file_contract_reset

!> Record the outcome of the geometry task in the sentinel files.
!>
!> Upstream semantics (`src/geoopt_driver.f90:183-186`): a converged run
!> creates `.xtboptok` (the convergence flag external pipelines test) and a
!> failed run creates `NOT_CONVERGED` instead - never both.  The names carry
!> the namespace: `.xtboptok` starts with a dot, so the prefixed name is
!> `.ns.xtboptok` (`src/setparam.f90:596-614`).
subroutine landscape_file_contract_mark(env, converged)
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Whether the geometry task converged
   logical, intent(in) :: converged

   if (converged) then
      call touch_namespaced('.xtboptok')
   else
      call touch_namespaced('NOT_CONVERGED')
   end if

end subroutine landscape_file_contract_mark

!> Write the geometry a failed task stopped at and announce the file name.
!>
!> This mirrors the `murks` path of the native `--opt` (`src/prog/main.F90:
!> 1012-1018`): `generateFileName(tmpname,'xtblast',extension,mol%ftype)`, the
!> message `last geometry written to: <name>` and an XMOL structure file.  The
!> file is written only on failure; the extension follows the input file type.
subroutine landscape_write_last_geometry(env, mol, result)
   character(len=*), parameter :: source = 'landscape_write_last_geometry'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Molecular structure holding the geometry of the last step
   type(TMolecule), intent(in) :: mol
   !> Result carrying the energy and gradient norm of that step
   type(landscape_result), intent(in) :: result

   character(len=:), allocatable :: tmpname, fname
   integer :: unit, ierr

   call generateFileName(tmpname, 'xtblast', '', mol%ftype)
   fname = get_namespace(tmpname)
   open(newunit=unit, file=fname, action='write', iostat=ierr)
   if (ierr /= 0) then
      call env%error("cannot open "//fname, source)
      return
   end if
   write(env%unit, '(/,a,1x,a,/)') "last geometry written to:", fname
   call writeMolecule(mol, unit, energy=result%energy, gnorm=result%gnorm)
   close(unit)

end subroutine landscape_write_last_geometry

!> Create an empty file, honouring the xtb file namespace.
subroutine touch_namespaced(name)
   !> File name before the namespace prefix is applied
   character(len=*), intent(in) :: name

   character(len=:), allocatable :: fname
   integer :: unit, ierr
   logical :: exist

   fname = get_namespace(name)
   inquire(file=fname, exist=exist)
   if (exist) return
   open(newunit=unit, file=fname, action='write', iostat=ierr)
   if (ierr == 0) close(unit)

end subroutine touch_namespaced

!> Delete a file if it exists, honouring the xtb file namespace.
subroutine delete_namespaced(name)
   !> File name before the namespace prefix is applied
   character(len=*), intent(in) :: name

   character(len=:), allocatable :: fname
   integer :: unit, ierr
   logical :: exist

   fname = get_namespace(name)
   inquire(file=fname, exist=exist)
   if (.not. exist) return
   open(newunit=unit, file=fname, iostat=ierr)
   if (ierr == 0) close(unit, status='delete')

end subroutine delete_namespaced

end module xtb_landscape_log
