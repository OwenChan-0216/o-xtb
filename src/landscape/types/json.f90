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

!> Structured result output of the landscape suite (`--ljson`).
!>
!> Every landscape task can write a machine readable summary of its result to
!> `landscape_<task>.json` (PLAN section 5.5).  The file exists for one reason
!> only: to make regression comparison of a run possible without parsing the
!> human readable stdout table.  The format is therefore deliberately frozen:
!>
!>  * the top level keys are always the same and always in the same order
!>    (`format`, `task`, `status`, `status_name`, `converged`, `message`,
!>    `counters`, `values`, `flags`, `history`);
!>  * all counters and values are written in the order the task added them, so
!>    a diff of two files of the same task is stable;
!>  * real numbers are written with 17 significant digits (`es25.17e3`), enough
!>    for a bitwise double round trip, and the conversion is deterministic for
!>    a fixed compiler, so two runs of the same input **at the same
!>    `OMP_NUM_THREADS`** produce byte identical files (different thread counts
!>    differ by up to 2.4e-10, PLAN section 12.16).  **No wall time, no path and
!>    no random quantity is written** -
!>    every one of them would break that property.
!>
!> Missing values are written as JSON `null`, never as a number: JSON has no
!> `NaN`/`Infinity` literal and a fabricated `0.0` would survive unnoticed in
!> a numerical diff (the rule PLAN section 5.5 established for the scan table).
!>
!> The counters are the *same* numbers the task prints on stdout, they are not
!> a second bookkeeping: each task adds them from its own result object, and
!> the CLI validation asserts the two agree
!> (`test/unit/landscape_e2e_check.py`, mode `ljson`).
!>
!> Implementation note: the document holds only intrinsic arrays.  An array
!> of a derived type with allocatable components would be the natural
!> container for the history series, but gfortran 12.2.0 has a stride defect
!> in the intrinsic assignment of exactly that shape
!> (`docs/_landscape-recon/10-m0-m1-fix-round-report.md` section 4.1); the
!> series are therefore stored as one flat real pool plus an offset/length
!> table per series, which is both safe and deterministic.
!>
!> Units: whatever the task documents; the file carries no unit strings, the
!> key names are the ones of the result types (`energy` in hartree, `gnorm` in
!> hartree/bohr, `etemp` in kelvin, ...).
module xtb_landscape_json
   use xtb_mctc_accuracy, only : wp
   use xtb_type_environment, only : TEnvironment
   use xtb_setparam, only : get_namespace
   use xtb_landscape_results, only : landscape_result, &
      & landscape_convergence_report
   implicit none(type, external)
   private

   public :: landscape_json_document
   public :: landscape_json_document_init
   public :: landscape_json_add_counter, landscape_json_add_value
   public :: landscape_json_add_flag, landscape_json_add_series
   public :: landscape_json_add_history, landscape_json_add_result
   public :: landscape_json_write, landscape_json_write_file
   public :: landscape_json_status_ok, landscape_json_status_incomplete
   public :: landscape_json_status_error, landscape_json_status_name

   !> Status of a landscape task in the JSON document: the task finished and
   !> its result is usable.
   integer, parameter :: landscape_json_status_ok = 0
   !> Status: the task finished but did not meet every criterion (an
   !> unconverged minimisation, a scan with unconverged points).  The result
   !> is still written, the caller decides whether it is usable.
   integer, parameter :: landscape_json_status_incomplete = 1
   !> Status: the task did not produce a usable result (an error was reported
   !> through `env`; the process exits non-zero).
   integer, parameter :: landscape_json_status_error = -1

   !> Maximum key length of a counter/value/flag/series name.
   integer, parameter :: landscape_json_key_len = 40
   !> Length of the task name field.
   integer, parameter :: landscape_json_task_len = 32
   !> Length of the message field; a longer termination message is truncated.
   !> Every message of the suite is far below this bound.
   integer, parameter :: landscape_json_message_len = 256

   !> A task result as an ordered set of named scalars, series and a status.
   !>
   !> The document is a simple builder: the task appends counters, values,
   !> flags and series in a fixed order and `landscape_json_write` serialises
   !> them.  No module level state is involved, so two documents never
   !> interfere.
   !>
   !> The history series live in a single real pool (`series_value`); series
   !> `k` occupies `series_value(offset(k) : offset(k) + length(k) - 1)`.
   type :: landscape_json_document
      !> Task name, part of the file name (`landscape_<task>.json`)
      character(len=landscape_json_task_len) :: task = ''
      !> Status code, one of `landscape_json_status_*`
      integer :: status = landscape_json_status_error
      !> True if the task met every convergence criterion
      logical :: converged = .false.
      !> Human readable termination message
      character(len=landscape_json_message_len) :: message = ''
      !> Integer counters (names and values, insertion order)
      character(len=landscape_json_key_len), allocatable :: counter_key(:)
      integer, allocatable :: counter_value(:)
      !> Number of counters added
      integer :: n_counter = 0
      !> Real values (names and values, insertion order)
      character(len=landscape_json_key_len), allocatable :: value_key(:)
      real(wp), allocatable :: value_value(:)
      !> Number of values added
      integer :: n_value = 0
      !> Logical flags (names and values, insertion order)
      character(len=landscape_json_key_len), allocatable :: flag_key(:)
      logical, allocatable :: flag_value(:)
      !> Number of flags added
      integer :: n_flag = 0
      !> Names of the history series
      character(len=landscape_json_key_len), allocatable :: series_key(:)
      !> Start index of each series in `series_value`
      integer, allocatable :: series_offset(:)
      !> Number of values of each series
      integer, allocatable :: series_length(:)
      !> Flat pool holding every series back to back
      real(wp), allocatable :: series_value(:)
      !> Number of series added
      integer :: n_series = 0
   end type landscape_json_document

contains

!> Initialise a document for one task.
subroutine landscape_json_document_init(self, task)
   !> Document to initialise
   type(landscape_json_document), intent(out) :: self
   !> Task name (`sp`, `opt`, `scan`, `vib`, `ts`, `irc`)
   character(len=*), intent(in) :: task

   self%task = task
   self%status = landscape_json_status_error
   self%converged = .false.
   self%message = ''
   allocate(self%counter_key(32))
   self%counter_key = ''

   allocate(self%counter_value(32), source=0)
   allocate(self%value_key(32))
   self%value_key = ''

   allocate(self%value_value(32), source=0.0_wp)
   allocate(self%flag_key(16))
   self%flag_key = ''

   allocate(self%flag_value(16), source=.false.)
   allocate(self%series_key(16))
   self%series_key = ''

   allocate(self%series_offset(16), source=0)
   allocate(self%series_length(16), source=0)
   allocate(self%series_value(0), source=0.0_wp)

end subroutine landscape_json_document_init

!> Append an integer counter.
subroutine landscape_json_add_counter(self, key, value)
   !> Document to extend
   type(landscape_json_document), intent(inout) :: self
   !> Counter name
   character(len=*), intent(in) :: key
   !> Counter value
   integer, intent(in) :: value

   integer :: capacity
   character(len=landscape_json_key_len), allocatable :: cbuffer(:)
   integer, allocatable :: ibuffer(:)

   self%n_counter = self%n_counter + 1
   if (self%n_counter > size(self%counter_key)) then
      capacity = 2*size(self%counter_key)
      allocate(cbuffer(capacity))
      cbuffer = ''
      cbuffer(:size(self%counter_key)) = self%counter_key
      call move_alloc(cbuffer, self%counter_key)
      allocate(ibuffer(capacity), source=0)
      ibuffer(:size(self%counter_value)) = self%counter_value
      call move_alloc(ibuffer, self%counter_value)
   end if
   self%counter_key(self%n_counter) = key
   self%counter_value(self%n_counter) = value

end subroutine landscape_json_add_counter

!> Append a real value.
subroutine landscape_json_add_value(self, key, value)
   !> Document to extend
   type(landscape_json_document), intent(inout) :: self
   !> Value name
   character(len=*), intent(in) :: key
   !> Value (in the unit the task documents)
   real(wp), intent(in) :: value

   integer :: capacity
   character(len=landscape_json_key_len), allocatable :: cbuffer(:)
   real(wp), allocatable :: rbuffer(:)

   self%n_value = self%n_value + 1
   if (self%n_value > size(self%value_key)) then
      capacity = 2*size(self%value_key)
      allocate(cbuffer(capacity))
      cbuffer = ''
      cbuffer(:size(self%value_key)) = self%value_key
      call move_alloc(cbuffer, self%value_key)
      allocate(rbuffer(capacity), source=0.0_wp)
      rbuffer(:size(self%value_value)) = self%value_value
      call move_alloc(rbuffer, self%value_value)
   end if
   self%value_key(self%n_value) = key
   self%value_value(self%n_value) = value

end subroutine landscape_json_add_value

!> Append a logical flag.
subroutine landscape_json_add_flag(self, key, value)
   !> Document to extend
   type(landscape_json_document), intent(inout) :: self
   !> Flag name
   character(len=*), intent(in) :: key
   !> Flag value
   logical, intent(in) :: value

   integer :: capacity
   character(len=landscape_json_key_len), allocatable :: cbuffer(:)
   logical, allocatable :: lbuffer(:)

   self%n_flag = self%n_flag + 1
   if (self%n_flag > size(self%flag_key)) then
      capacity = 2*size(self%flag_key)
      allocate(cbuffer(capacity))
      cbuffer = ''
      cbuffer(:size(self%flag_key)) = self%flag_key
      call move_alloc(cbuffer, self%flag_key)
      allocate(lbuffer(capacity), source=.false.)
      lbuffer(:size(self%flag_value)) = self%flag_value
      call move_alloc(lbuffer, self%flag_value)
   end if
   self%flag_key(self%n_flag) = key
   self%flag_value(self%n_flag) = value

end subroutine landscape_json_add_flag

!> Append a real series to the convergence history.
subroutine landscape_json_add_series(self, key, values)
   !> Document to extend
   type(landscape_json_document), intent(inout) :: self
   !> Series name
   character(len=*), intent(in) :: key
   !> Series values in iteration order
   real(wp), intent(in) :: values(:)

   integer :: capacity, offset
   character(len=landscape_json_key_len), allocatable :: cbuffer(:)
   integer, allocatable :: ibuffer(:)
   real(wp), allocatable :: rbuffer(:)

   if (self%n_series > 0) then
      offset = self%series_offset(self%n_series) + &
         & self%series_length(self%n_series)
   else
      offset = 1
   end if

   self%n_series = self%n_series + 1
   if (self%n_series > size(self%series_key)) then
      capacity = 2*size(self%series_key)
      allocate(cbuffer(capacity))
      cbuffer = ''
      cbuffer(:size(self%series_key)) = self%series_key
      call move_alloc(cbuffer, self%series_key)
      allocate(ibuffer(capacity), source=0)
      ibuffer(:size(self%series_offset)) = self%series_offset
      call move_alloc(ibuffer, self%series_offset)
      allocate(ibuffer(capacity), source=0)
      ibuffer(:size(self%series_length)) = self%series_length
      call move_alloc(ibuffer, self%series_length)
   end if

   allocate(rbuffer(offset - 1 + size(values)), source=0.0_wp)
   if (offset > 1) rbuffer(:offset - 1) = self%series_value
   rbuffer(offset:) = values
   call move_alloc(rbuffer, self%series_value)

   self%series_key(self%n_series) = key
   self%series_offset(self%n_series) = offset
   self%series_length(self%n_series) = size(values)

end subroutine landscape_json_add_series

!> Append the convergence history of a result.
!>
!> The series are the ones of `landscape_convergence_report`, in a fixed
!> order; the iteration count is added as the counter `n_iter`, so a reader
!> can detect a truncated series without trusting the array lengths.
subroutine landscape_json_add_history(self, conv)
   !> Document to extend
   type(landscape_json_document), intent(inout) :: self
   !> Convergence report (may hold no history at all)
   type(landscape_convergence_report), intent(in) :: conv

   call landscape_json_add_counter(self, 'n_iter', conv%n_iter)
   if (.not. allocated(conv%history_energy)) return
   call landscape_json_add_series(self, 'energy', conv%history_energy)
   call landscape_json_add_series(self, 'gnorm', conv%history_gnorm)
   call landscape_json_add_series(self, 'gmax', conv%history_gmax)
   call landscape_json_add_series(self, 'dispnorm', conv%history_dispnorm)
   call landscape_json_add_series(self, 'dispmax', conv%history_dispmax)
   call landscape_json_add_series(self, 'trust', conv%history_trust)
   if (allocated(conv%history_method)) then
      call landscape_json_add_series(self, 'method', &
         & real(conv%history_method, wp))
   end if

end subroutine landscape_json_add_history

!> Append the fields every landscape task shares.
!>
!> `status` is the task's own verdict, not a second convergence test: the
!> caller passes it in so that a task that reports a warning (a scan with
!> unconverged points, a frequency analysis with imaginary modes) can
!> distinguish "usable with caveats" from "converged".
subroutine landscape_json_add_result(self, result, status)
   !> Document to extend
   type(landscape_json_document), intent(inout) :: self
   !> Generic task result
   type(landscape_result), intent(in) :: result
   !> Task verdict, one of `landscape_json_status_*`
   integer, intent(in) :: status

   self%status = status
   self%converged = result%converged
   if (allocated(result%message)) then
      self%message = result%message
   else
      self%message = ''
   end if
   call landscape_json_add_counter(self, 'n_eval', result%n_eval)
   call landscape_json_add_counter(self, 'n_cache_miss', result%n_cache_miss)
   call landscape_json_add_counter(self, 'n_steps', result%n_steps)
   call landscape_json_add_value(self, 'energy', result%energy)
   call landscape_json_add_value(self, 'gnorm', result%gnorm)
   call landscape_json_add_value(self, 'gmax', result%gmax)
   call landscape_json_add_value(self, 'etemp', result%etemp)
   call landscape_json_add_counter(self, 'n_imag', result%n_imag)
   call landscape_json_add_value(self, 'imag_freq', result%imag_freq)
   call landscape_json_add_flag(self, 'is_saddle', result%is_saddle)
   call landscape_json_add_history(self, result%conv)

end subroutine landscape_json_add_result

!> Human readable name of a status code.
pure function landscape_json_status_name(status) result(name)
   !> Status code
   integer, intent(in) :: status
   !> Lower case status name
   character(len=:), allocatable :: name

   select case (status)
   case (landscape_json_status_ok)
      name = 'ok'
   case (landscape_json_status_incomplete)
      name = 'incomplete'
   case default
      name = 'error'
   end select

end function landscape_json_status_name

!> Serialise a document to `landscape_<task>.json`.
!>
!> The name goes through the xtb file namespace (`get_namespace`), exactly
!> like every other file of the suite; the name is printed once on `env%unit`
!> as `wrote <file>` (PLAN section 5.5).
subroutine landscape_json_write(env, self, ok)
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Document to write
   type(landscape_json_document), intent(in) :: self
   !> True if the file was written
   logical, intent(out) :: ok

   character(len=:), allocatable :: fname

   fname = get_namespace('landscape_'//trim(self%task)//'.json')
   call landscape_json_write_file(env, self, fname, ok)

end subroutine landscape_json_write

!> Serialise a document to an explicit file name (no namespace applied).
!>
!> This is the routine the determinism test drives directly
!> (`test_landscape_e2e`, `ljson-determinism`); the tasks use the namespaced
!> wrapper above.
subroutine landscape_json_write_file(env, self, filename, ok)
   character(len=*), parameter :: source = 'landscape_json_write_file'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Document to write
   type(landscape_json_document), intent(in) :: self
   !> File to write
   character(len=*), intent(in) :: filename
   !> True if the file was written
   logical, intent(out) :: ok

   character(len=:), allocatable :: fname
   integer :: unit, ierr, i

   ok = .false.
   fname = filename
   open(newunit=unit, file=fname, action='write', iostat=ierr)
   if (ierr /= 0) then
      call env%error("cannot write "//fname, source)
      return
   end if

   write(unit, '(a)') '{'
   write(unit, '(2x,a,i0,a)') '"format": ', 1, ','
   write(unit, '(2x,a,a,a)') '"task": "', trim(self%task), '",'
   write(unit, '(2x,a,i0,a)') '"status": ', self%status, ','
   write(unit, '(2x,a,a,a)') '"status_name": "', &
      & trim(landscape_json_status_name(self%status)), '",'
   write(unit, '(2x,a)', advance='no') '"converged": '
   call write_logical(unit, self%converged)
   write(unit, '(a)') ','
   write(unit, '(2x,a,a,a)') '"message": "', &
      & json_escape(trim(self%message)), '",'

   write(unit, '(2x,a)') '"counters": {'
   do i = 1, self%n_counter
      if (i < self%n_counter) then
         write(unit, '(4x,a,a,a,i0,a)') '"', trim(self%counter_key(i)), '": ', &
            & self%counter_value(i), ','
      else
         write(unit, '(4x,a,a,a,i0)') '"', trim(self%counter_key(i)), '": ', &
            & self%counter_value(i)
      end if
   end do
   write(unit, '(2x,a)') '},'

   write(unit, '(2x,a)') '"values": {'
   do i = 1, self%n_value
      if (i < self%n_value) then
         write(unit, '(4x,a,a,a)', advance='no') '"', trim(self%value_key(i)), '": '
         call write_real(unit, self%value_value(i))
         write(unit, '(a)') ','
      else
         write(unit, '(4x,a,a,a)', advance='no') '"', trim(self%value_key(i)), '": '
         call write_real(unit, self%value_value(i))
         write(unit, *)
      end if
   end do
   write(unit, '(2x,a)') '},'

   write(unit, '(2x,a)') '"flags": {'
   do i = 1, self%n_flag
      if (i < self%n_flag) then
         write(unit, '(4x,a,a,a)', advance='no') '"', trim(self%flag_key(i)), '": '
         call write_logical(unit, self%flag_value(i))
         write(unit, '(a)') ','
      else
         write(unit, '(4x,a,a,a)', advance='no') '"', trim(self%flag_key(i)), '": '
         call write_logical(unit, self%flag_value(i))
         write(unit, *)
      end if
   end do
   write(unit, '(2x,a)') '},'

   write(unit, '(2x,a)') '"history": {'
   do i = 1, self%n_series
      write(unit, '(4x,a,a,a)', advance='no') '"', trim(self%series_key(i)), '": ['
      call write_real_range(unit, self%series_value, self%series_offset(i), &
         & self%series_length(i))
      if (i < self%n_series) then
         write(unit, '(a)') '],'
      else
         write(unit, '(a)') ']'
      end if
   end do
   write(unit, '(2x,a)') '}'

   write(unit, '(a)') '}'
   close(unit)

   write(env%unit, '(1x,a,a)') "wrote ", fname
   ok = .true.

end subroutine landscape_json_write_file

!> Write a logical in JSON syntax (`true` / `false`).
!>
!> The Fortran `L` edit descriptor prints `T`/`F`, which JSON does not accept;
!> the conversion is explicit so a reader can parse the file unmodified.
subroutine write_logical(unit, value)
   !> Output unit
   integer, intent(in) :: unit
   !> Value to write
   logical, intent(in) :: value

   if (value) then
      write(unit, '(a)', advance='no') 'true'
   else
      write(unit, '(a)', advance='no') 'false'
   end if

end subroutine write_logical

!> Write one real number in JSON syntax; a non finite value becomes `null`.
subroutine write_real(unit, value)
   !> Output unit
   integer, intent(in) :: unit
   !> Value to write
   real(wp), intent(in) :: value

   character(len=32) :: buffer

   if (value /= value .or. abs(value) > huge(value)) then
      ! NaN (the only value not equal to itself) and infinity have no JSON
      ! literal; `null` is an honest placeholder that cannot be mistaken for
      ! a measured number.
      write(unit, '(a)', advance='no') 'null'
      return
   end if
   write(buffer, '(es25.17e3)') value
   write(unit, '(a)', advance='no') trim(adjustl(buffer))

end subroutine write_real

!> Write a contiguous range of the series pool in JSON syntax (one line).
subroutine write_real_range(unit, pool, offset, length)
   !> Output unit
   integer, intent(in) :: unit
   !> Series pool
   real(wp), intent(in) :: pool(:)
   !> Start index of the range in `pool`
   integer, intent(in) :: offset
   !> Number of values of the range (may be zero)
   integer, intent(in) :: length

   integer :: i

   do i = 0, length - 1
      if (i > 0) write(unit, '(a)', advance='no') ', '
      call write_real(unit, pool(offset + i))
   end do

end subroutine write_real_range

!> Escape the characters JSON cannot carry inside a string.
pure function json_escape(text) result(escaped)
   !> Input text
   character(len=*), intent(in) :: text
   !> Escaped text
   character(len=:), allocatable :: escaped

   character(len=1) :: c
   integer :: i

   escaped = ''
   do i = 1, len_trim(text)
      c = text(i:i)
      select case (c)
      case ('"')
         escaped = escaped//'\"'
      case ('\')
         escaped = escaped//'\\'
      case (achar(10))
         escaped = escaped//'\n'
      case (achar(13))
      case (achar(9))
         escaped = escaped//'\t'
      case default
         escaped = escaped//c
      end select
   end do

end function json_escape

end module xtb_landscape_json
