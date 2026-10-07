! This file is part of xtb.
!
! Copyright (C) 2019-2020 Sebastian Ehlert
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

! Modified by the o-xtb landscape task suite, 2026.

!> Calculation environment
module xtb_type_environment
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_io, only : stdout
   use xtb_mctc_systools, only : rdvar, rdarg, pathdel, pathsep
   use xtb_type_iohandler, only : TIOHandler, init_ => init
   use, intrinsic :: iso_c_binding, only : c_char, c_intptr_t, c_null_char, c_size_t
   implicit none
   private

   public :: TEnvironment, init


   !> Wrapper for characters
   type :: TMessage
      logical :: error
      character(len=:), allocatable :: message
   end type TMessage


   !> Calculation environment
   type :: TEnvironment

      !> Unit for IO
      integer :: unit

      !> Number of logged messages
      integer :: nLog

      !> Message log
      type(TMessage), allocatable :: log(:)
      
      !> Handle warnings as errors
      logical :: strict

      !> Actual executable name
      character(len=:),allocatable :: whoami

      !> Name of hosting machine
      character(len=:),allocatable :: hostname

      !> User's home directory
      character(len=:),allocatable :: home

      !> Systems path variable
      character(len=:),allocatable :: path

      !> Calculations path variable
      character(len=:),allocatable :: xtbpath

      !> Calculations home directory
      character(len=:),allocatable :: xtbhome

      !> File input/output handling
      type(TIOHandler) :: io

   contains

      !> Add a warning to the message log
      procedure :: warning

      !> Add an error to the message log
      procedure :: error

      !> Check status of environment
      procedure :: check

      !> Check status of environment
      procedure :: checkpoint

      !> Show and clear error log
      procedure :: show

      !> Forceful terminate the current run, use only in main drivers!
      procedure :: terminate => terminateRun

      !> Return log to string
      procedure :: getLog

      !> Rescue errors
      procedure :: rescue

   end type TEnvironment


   !> Constructor for the calculation environment
   interface init
      module procedure :: initEnvironment
   end interface


   !> Overloaded resize interface
   interface resize
      module procedure :: resizeMessage
   end interface resize


   !> POSIX `readlink(2)` (`man 2 readlink`), used only by the `XTBPATH`
   !> fallback.  `argv[0]` is the name the caller typed, so a command found
   !> through `PATH` - in particular the `~/.local/bin/oxtb` symlink that
   !> `cmake --install` / `install.sh` register - arrives as the bare name
   !> `oxtb` and carries no directory at all.  `/proc/self/exe` is the
   !> kernel's own answer to "where does this process live", so the fallback
   !> also survives a relocated install tree.
   interface
      function c_readlink(path, buf, bufsiz) bind(c, name='readlink') result(n)
         import :: c_char, c_intptr_t, c_size_t
         character(kind=c_char) :: path(*)
         character(kind=c_char) :: buf(*)
         integer(c_size_t), value :: bufsiz
         integer(c_intptr_t) :: n
      end function c_readlink
   end interface


   !> Installed data directory below the install prefix (`share/o-xtb`), the
   !> run time counterpart of `CMAKE_INSTALL_DATADIR`/`PROJECT_NAME` in the
   !> install rules of `CMakeLists.txt`.
   character(len=*), parameter :: dataDirName = 'o-xtb'


   !> Initial size of the message log
   integer, parameter :: initialSize = 20


contains


!> Construct the calculation environment
subroutine initEnvironment(self, strict)

   !> Calculation environment
   type(TEnvironment), intent(out) :: self
   
   !> Handle warnings as errors
   logical, intent(in), optional :: strict

   integer :: err

   self%unit = stdout
   self%nLog = 0
   allocate(self%log(initialSize))

   call rdarg(0, self%whoami, err)
   call rdvar('HOSTNAME', self%hostname, err)
   call rdvar('HOME', self%home, err)
   call rdvar('PATH', self%path, err)
   call rdvar('XTBHOME', self%xtbhome, err)
   if (.not.allocated(self%xtbhome)) self%xtbhome = ''
   if (err /= 0 .or. len(self%xtbhome) <= 0) then
      self%xtbhome = self%home
   end if
   call rdvar('XTBPATH', self%xtbpath, err)
   if (.not.allocated(self%xtbpath)) self%xtbpath = ''
   if (err /= 0 .or. len(self%xtbpath) <= 0) then
      ! No explicit `XTBPATH`: an install is asked to find its own parameter
      ! files before falling back to the historical `xtbhome` lookup.
      call setDefaultXtbPath(self)
      if (len(self%xtbpath) <= 0) self%xtbpath = self%xtbhome
   end if
   
   if (present(strict)) then
      self%strict = strict
   else
      self%strict = .false.
   end if

   call init_(self%io)

end subroutine initEnvironment


!> Default `XTBPATH` derived from the running executable's location.
!>
!> `XTBPATH` is the *only* way towards the GFN0-xTB parameter file: GFN1,
!> GFN2 and GFN-FF carry a compiled-in parameter set, but `param_gfn0-xtb.txt`
!> has none (`use_parameterset`), so a relocated install aborted with
!> "Parameter file param_gfn0-xtb.txt not found!" unless the user exported
!> `XTBPATH`.  This routine closes that upstream UX gap by probing the two
!> layouts whose parameter location follows from the executable path:
!>
!>   * `<bindir>/../share/o-xtb` - the installed layout
!>     (`<prefix>/bin/oxtb` next to `<prefix>/share/o-xtb`);
!>   * `<bindir>/share/o-xtb` - the build tree, where the executable sits in
!>     the build root and CMake stages the parameter files below it.
!>
!> An explicit `XTBPATH` never reaches this routine, and `xtbhome` remains the
!> last resort, so the precedence is
!> `XTBPATH` > executable-relative directory > `xtbhome` > error.  The
!> executable-relative directory is prepended to (not replaced by) the
!> historical `xtbhome` entry, which keeps the `.xtbrc` lookup in `HOME`
!> working exactly as before.
subroutine setDefaultXtbPath(self)

   !> Calculation environment
   class(TEnvironment), intent(inout) :: self

   character(len=:), allocatable :: exedir, data, default

   default = ''
   exedir = executableDirectory(self)
   if (len(exedir) > 0) then
      data = exedir // pathsep // '..' // pathsep // 'share' // pathsep // dataDirName
      if (.not.paramFilePresent(data)) then
         data = exedir // pathsep // 'share' // pathsep // dataDirName
      end if
      if (paramFilePresent(data)) default = data
   end if
   if (len(default) <= 0) return
   if (len(self%xtbhome) > 0) then
      self%xtbpath = default // pathdel // self%xtbhome
   else
      self%xtbpath = default
   end if

end subroutine setDefaultXtbPath


!> Directory of the running executable, empty when it cannot be established.
!>
!> `argv[0]` comes first because it is the location the caller used; the
!> `/proc/self/exe` resolution only kicks in when the command was looked up
!> through `PATH` and `argv[0]` is a bare name.
function executableDirectory(self) result(dir)

   !> Calculation environment
   class(TEnvironment), intent(in) :: self

   character(len=:), allocatable :: dir
   character(len=:), allocatable :: resolved

   dir = directoryPart(self%whoami)
   if (len(dir) > 0) return
   resolved = procSelfExe()
   if (len(resolved) > 0) dir = directoryPart(resolved)

end function executableDirectory


!> Everything before the last path separator, empty for a bare command name.
function directoryPart(path) result(dir)

   character(len=*), intent(in) :: path

   character(len=:), allocatable :: dir
   integer :: i

   i = index(path, pathsep, back=.true.)
   if (i > 1) then
      dir = path(:i-1)
   else if (i == 1) then
      dir = pathsep
   else
      dir = ''
   end if

end function directoryPart


!> Target of the `/proc/self/exe` symlink, empty when it cannot be resolved.
function procSelfExe() result(path)

   character(len=:), allocatable :: path
   character(kind=c_char), allocatable :: target(:), buffer(:)
   integer(c_intptr_t) :: n
   integer :: i

   path = ''
   allocate(buffer(4096), source=c_null_char)
   target = toCString('/proc/self/exe')
   n = c_readlink(target, buffer, int(size(buffer), c_size_t))
   if (n <= 0 .or. n >= int(size(buffer), c_size_t)) return
   do i = 1, int(n)
      if (buffer(i) == c_null_char) exit
      path = path // buffer(i)
   end do

end function procSelfExe


!> Null terminated C string for a Fortran character scalar.
function toCString(string) result(buffer)

   character(len=*), intent(in) :: string

   character(kind=c_char), allocatable :: buffer(:)
   integer :: i

   allocate(buffer(len(string)+1))
   do i = 1, len(string)
      buffer(i) = string(i:i)
   end do
   buffer(len(string)+1) = c_null_char

end function toCString


!> Does `dir` hold `param_gfn0-xtb.txt` (the marker of a parameter directory)?
function paramFilePresent(dir) result(present)

   character(len=*), intent(in) :: dir

   logical :: present

   inquire(file=dir // pathsep // 'param_gfn0-xtb.txt', exist=present)

end function paramFilePresent


subroutine check(self, terminate)

   !> Calculation environment
   class(TEnvironment), intent(in) :: self

   !> Recommendation for terminating run
   logical, intent(out) :: terminate

   terminate = any(self%log(:self%nLog)%error)

end subroutine check


!> Check status of calculation environment
subroutine checkpoint(self, message)

   !> Calculation environment
   class(TEnvironment), intent(inout) :: self

   !> Message in case of error
   character(len=*), intent(in) :: message

   !> Recommendation for terminating run
   logical :: terminate

   integer :: iLog

   call self%check(terminate)

   if (terminate) then
      call self%terminate(message)
   end if

end subroutine checkpoint


!> Check status of calculation environment
subroutine show(self, message, isError)

   !> Calculation environment
   class(TEnvironment), intent(inout) :: self

   !> Message in case of error
   character(len=*), intent(in) :: message

   !> Recommendation for terminating run
   logical, intent(in), optional :: isError

   integer :: iLog
   logical :: isError0

   if (self%nLog > 0) then
      if (present(isError)) then
         isError0 = isError
      else
         call self%check(isError0)
      end if
      if (isError0) then
         write(self%unit, '(72("#"), /, "[ERROR]", 1x, a)') message
      else
         write(self%unit, '(72("#"), /, "[WARNING]", 1x, a)') message
      end if
      do iLog = self%nLog, 1, -1
         write(self%unit, '("-", i0, "-", 1x, a)') iLog, self%log(iLog)%message
         deallocate(self%log(iLog)%message)
      end do
      write(self%unit, '(72("#"))')
      self%nLog = 0
   end if

end subroutine show


!> Check status of calculation environment
subroutine getLog(self, message)

   !> Calculation environment
   class(TEnvironment), intent(inout) :: self

   !> Message in case of error
   character(len=:), allocatable, intent(out) :: message

   integer :: iLog
   logical :: isError0
   character(len=512) :: buffer

   message = ''

   if (self%nLog > 0) then
      do iLog = self%nLog, 1, -1
         write(buffer, '("-", i0, "-", 1x, a)') iLog, self%log(iLog)%message
         deallocate(self%log(iLog)%message)
         if (len_trim(message) > 0) then
            message = message // new_line('a') // trim(buffer)
         else
            message = trim(buffer)
         end if
      end do
      self%nLog = 0
   end if

end subroutine getLog


subroutine terminateRun(self, message, code)

   !> Calculation environment
   class(TEnvironment), intent(inout) :: self

   !> Message in case of error
   character(len=*), intent(in) :: message

   !> Exit code for termination
   integer, intent(in), optional :: code

   interface
      subroutine terminate(code)
         integer, intent(in) :: code
      end subroutine terminate
   end interface


   call self%error(message)

   call self%show("Program stopped due to fatal error", .true.)

   if (present(code)) then
      call terminate(code)
   else
      call terminate(1)
   end if

end subroutine terminateRun


!> Create and push back a new error to the message log
subroutine error(self, message, source)

   !> Calculation environment
   class(TEnvironment), intent(inout) :: self

   !> Error message
   character(len=*), intent(in) :: message

   !> Source of the error message
   character(len=*), intent(in), optional :: source

   if (self%nLog >= size(self%log)) then
      call resize(self%log)
   end if

   self%nLog = self%nLog + 1
   if (present(source)) then
      self%log(self%nLog) = TMessage(.true., source // ": " // message)
   else
      self%log(self%nLog) = TMessage(.true., message)
   end if

end subroutine error


!> Create and push back a new error to the message log
subroutine warning(self, message, source)

   !> Calculation environment
   class(TEnvironment), intent(inout) :: self

   !> Error message
   character(len=*), intent(in) :: message

   !> Source of the error message
   character(len=*), intent(in), optional :: source

   if (self%nLog >= size(self%log)) then
      call resize(self%log)
   end if

   self%nLog = self%nLog + 1
   if (present(source)) then
      self%log(self%nLog) = TMessage(self%strict, source // ": " // message)
   else
      self%log(self%nLog) = TMessage(self%strict, message)
   end if

end subroutine warning


!> Catch errors and continue
subroutine rescue(self, message, source)

   !> Calculation environment
   class(TEnvironment), intent(inout) :: self

   !> Error message
   character(len=*), intent(in) :: message

   !> Source of the error message
   character(len=*), intent(in), optional :: source

   integer :: iLog

   do iLog = 1, self%nLog
      self%log(iLog)%error = self%strict
   end do

   call self%warning(message, source)

end subroutine rescue


!> Reallocate message list
subroutine resizeMessage(var, n)

   !> Message list
   type(TMessage), allocatable, intent(inout) :: var(:)

   !> Desired size
   integer, intent(in), optional :: n

   type(TMessage), allocatable :: tmp(:)
   integer :: length, currentLength

   currentLength = size(var)
   if (currentLength > 0) then
      if (present(n)) then
         if (n <= currentLength) return
         length = n
      else
         length = currentLength + currentLength/2 + 1
      endif
      allocate(tmp(length))
      tmp(:currentLength) = var(:currentLength)
      deallocate(var)
      call move_alloc(tmp, var)
   else
      if (present(n)) then
         length = n
      else
         length = 64
      endif
      allocate(var(length))
   endif

end subroutine resizeMessage


end module xtb_type_environment
