! This file is part of xtb.
!
! Copyright (C) 2017-2020 Stefan Grimme
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

!> Banner of the OxTB command line program.
!>
!> Prints the three line ASCII wordmark of the logo, the product description,
!> the version lines of `xtb_version` and the legal notice.  Every line is
!> centred in one common block width, so the banner keeps its shape in a
!> monospace terminal; the wordmark itself is printed character for character
!> (the backslashes and the trailing blanks are part of the drawing).
subroutine xtb_header(iunit)

   implicit none
   integer,intent(in) :: iunit
      !! I/O unit

   !> Width of the banner block in characters: the length of the longest line
   !> of the banner (the `Original Author - ...` line of `xtb_version`).
   integer,parameter :: width = 94
   !> OxTB wordmark, three lines, printed as authored.
   character(len=24),parameter :: wordmark(3) = [character(len=24) :: &
      " ___   _    _____  ___  ", &
      "/ / \ \ \_/  | |  | |_) ", &
      "\_\_/ /_/ \  |_|  |_|_) "]

   integer :: i, offset

   do i = 1, size(wordmark)
      offset = max(0, (width - len_trim(wordmark(i))) / 2)
      write(iunit,'(a)') repeat(' ', offset)//wordmark(i)
   end do

   call banner_line(iunit, &
      & "OxTB - An Omni-functional PES Exploration and "// &
      & "Exploitation Toolkit Based on xTB", width)
   call banner_line(iunit, &
      & "Original Author - S. Grimme from Mulliken Center for "// &
      & "Theoretical Chemistry, University of Bonn", width)

   call xtb_version(iunit, width)

   !> The appropriate legal notices stay on the banner (GPL-3.0 section 5(d));
   !> the full disclaimer text is printed by `disclaimer` (also on
   !> `--license`) and stays next to the banner at startup.
   call banner_line(iunit, &
      & "Copyright (C) 2017-2020 Stefan Grimme, 2019-2020 "// &
      & "Sebastian Ehlert and contributors", width)
   call banner_line(iunit, &
      & "LGPL-3.0-or-later - NO WARRANTY; see `oxtb "// &
      & "--license` for the full text", width)
   write(iunit,'(a)')

end subroutine xtb_header

!> Version lines of the OxTB banner.
!>
!> `oxtb_version` is the product version of this program, `engine_version`
!> the version of the xTB engine it is built from (both generated into
!> `xtb_version.fh`).
subroutine xtb_version(iunit,width)

   implicit none
   integer,intent(in) :: iunit
      !! I/O unit
   integer,intent(in) :: width
      !! Banner block width in characters, see `xtb_header`

   include 'xtb_version.fh'
   call banner_line(iunit, "* OxTB version "//oxtb_version//" *", width)
   call banner_line(iunit, "* xTB version "//engine_version//" *", width)
   call banner_line(iunit, "Compiled on "//date, width)
   write(iunit,'(a)')

end subroutine xtb_version

!> Write one banner line centred in `width` characters.
!>
!> The centring is the leading padding `(width - len)/2` `generic_header`
!> below uses; a line longer than the block width is not truncated and starts
!> in the first column.
subroutine banner_line(iunit,line,width)

   implicit none
   integer,intent(in) :: iunit
      !! I/O unit
   character(len=*),intent(in) :: line
      !! Banner line, trailing blanks are not printed
   integer,intent(in) :: width
      !! Banner block width in characters

   write(iunit,'(a)') &
      & repeat(' ', max(0, (width - len_trim(line)) / 2))//trim(line)

end subroutine banner_line

subroutine disclaimer(iunit)
integer,intent(in) :: iunit
write(iunit,'(3x,a)') &
   !< < < < < < < < < < < < < < < > > > > > > > > > > > > > > > >!
   "xtb is free software: you can redistribute it and/or modify it under", &
   "the terms of the GNU Lesser General Public License as published by", &
   "the Free Software Foundation, either version 3 of the License, or", &
   "(at your option) any later version.", &
   "", &
   "xtb is distributed in the hope that it will be useful,", &
   "but WITHOUT ANY WARRANTY; without even the implied warranty of", &
   "MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the", &
   "GNU Lesser General Public License for more details.", &
   ""
end subroutine disclaimer

subroutine gfn0_header(iunit)
integer,intent(in) :: iunit
write(iunit,'(10x,a)') &
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
   " ------------------------------------------------- ",&
   "|                 G F N 0 - x T B                 |",&
   "| Geometry, Frequencies, Noncovalent interactions |",&
   "|           preliminary parametrisation           |",&
   " ------------------------------------------------- "
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
end subroutine gfn0_header

subroutine peeq_header(iunit)
integer,intent(in) :: iunit
write(iunit,'(10x,a)') &
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
   " ------------------------------------------------- ",&
   "|                   P E E Q                       |",&
   "|  Periodic Electronegativity Equilibration Model |",&
   "|              based on GFN0-xTB                  |",&
   " ------------------------------------------------- "
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
end subroutine peeq_header

subroutine gfn1_header(iunit)
integer,intent(in) :: iunit
write(iunit,'(10x,a)') &
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
   " ------------------------------------------------- ",&
   "|                  G F N - x T B                  |",&
   "| Geometry, Frequencies, Noncovalent interactions |",&
   "|            JCTC 2017 parametrisation            |",&
   " ------------------------------------------------- "
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
end subroutine gfn1_header

subroutine gfn2_header(iunit)
integer,intent(in) :: iunit
write(iunit,'(10x,a)') &
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
   " ------------------------------------------------- ",&
   "|                 G F N 2 - x T B                 |",&
   "| Geometry, Frequencies, Noncovalent interactions |",&
   "|            JCTC 2019 parametrisation            |",&
   " ------------------------------------------------- "
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
end subroutine gfn2_header

subroutine gfnff_header(iunit,version)
use xtb_gfnff_param, only : gffVersion
integer,intent(in) :: iunit
integer,intent(in) :: version
character(len=52)  :: nr
select case(version)
case(gffVersion%angewChem2020, gffVersion%harmonic2020,gffVersion%mcgfnff2023)
  nr="|                  Version 1.0.0                  |"
case(gffVersion%angewChem2020_1)
  nr="|                  Version 1.0.2                  |"
case(gffVersion%angewChem2020_2)
  nr="|                  Version 1.0.3                  |"
end select  

write(iunit,'(10x,a)') &
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
   " ------------------------------------------------- ",&
   "|                   G F N - F F                   |",&
   "|          A general generic force-field          |",nr,&
   !|                  Version 1.0.x                  |
   " ------------------------------------------------- "
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
end subroutine gfnff_header

subroutine struc_convert_header(iunit)
integer,intent(in) :: iunit
write(iunit,'(10x,a)') &
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
   " ------------------------------------------------- ",&
   "|                     2D => 3D                    |",&
   "|          A structure converter based on         |",&
   "|                   G F N - F F                   |",&
   " ------------------------------------------------- "
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
end subroutine struc_convert_header

subroutine ipea_header(iunit)
integer,intent(in) :: iunit
write(iunit,'(10x,a)') &
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
   " ------------------------------------------------- ",&
   "|                 I P E A - x T B                 |",&
   "|  Ionisation Potentials and Electron Affinities  |",&
   " ------------------------------------------------- "
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
end subroutine ipea_header

subroutine stda_header(iunit)
integer,intent(in) :: iunit
write(iunit,'(10x,a)') &
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
   " ------------------------------------------------- ",&
   "|                 s T D A - x T B                 |",&
   "|      simplified Tamm-Dancoff Approximation      |",&
   " ------------------------------------------------- "
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
end subroutine stda_header

subroutine qmdff_header(iunit)
integer,intent(in) :: iunit
write(iunit,'(10x,a)') &
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
   " ------------------------------------------------- ",&
   "|                    Q M D F F                    |",&
   "|     quantum mechanical derived force field      |",&
   " ------------------------------------------------- "
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
end subroutine qmdff_header

subroutine driver_header(iunit)
integer,intent(in) :: iunit
write(iunit,'(10x,a)') &
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
   " ------------------------------------------------- ",&
   "|                   D R I V E R                   |",&
   "|     running other programs in this program      |",&
   " ------------------------------------------------- "
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
end subroutine driver_header

subroutine eht_header(iunit)
integer,intent(in) :: iunit
write(iunit,'(10x,a)') &
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
   " ------------------------------------------------- ",&
   "|        Valence Tight Binding Calculation        |",&
   " ------------------------------------------------- "
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
end subroutine eht_header

subroutine scc_header(iunit)
integer,intent(in) :: iunit
write(iunit,'(10x,a)') &
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
   " ------------------------------------------------- ",&
   "|        Self-Consistent Charge Iterations        |",&
   " ------------------------------------------------- "
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
end subroutine scc_header

subroutine vip_header(iunit)
integer,intent(in) :: iunit
write(iunit,'(10x,a)') &
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
   " ------------------------------------------------- ",&
   "|        vertical delta SCC IP calculation        |",&
   " ------------------------------------------------- "
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
end subroutine vip_header

subroutine vea_header(iunit)
integer,intent(in) :: iunit
write(iunit,'(10x,a)') &
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
   " ------------------------------------------------- ",&
   "|        vertical delta SCC EA calculation        |",&
   " ------------------------------------------------- "
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
end subroutine vea_header

subroutine ancopt_header(iunit,verbose)
integer,intent(in) :: iunit
logical,intent(in) :: verbose
if (verbose) then
write(iunit,'(a)') &
   !< < < < < < < < < < < < < < < < < < > > > > > > > > > > > > > > > > > >!
   "                    ___    _   _ _____             _              ",&
   "                   / _ \  | \ | /  __ \ ___  _ __ | |_            ",&
   "                  / /_\ \ |  \| | /  \// _ \| '_ \|  _|           ",&
   "      -----------/ _____ \| . ` | |---| (_) | |_) | |_----------- ",&
   "     |          / /     \ | |\  | \__/\\___/| .__/ \__|          |",&
   "     |         / /       \\_| \_/\____/     | |                  |",&
   "     |         |/ ==========================|_|=======           |"
else
write(iunit,'(a)') &
   !< < < < < < < < < < < < < < < < < < > > > > > > > > > > > > > > > > > >!
   "      ----------------------------------------------------------- ",&
   "     |                   =====================                   |",&
   "     |                        A N C O P T                        |",&
   "     |                   =====================                   |"
endif
write(iunit,'(a)') &
   "     |               Approximate Normal Coordinate               |",&
   "     |                Rational Function Optimizer                |",&
   "      ----------------------------------------------------------- "
   !< < < < < < < < < < < < < < < < < < > > > > > > > > > > > > > > > > > >!
end subroutine ancopt_header

subroutine numhess_header(iunit)
integer,intent(in) :: iunit
write(iunit,'(10x,a)') &
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
   " ------------------------------------------------- ",&
   "|                Numerical Hessian                |",&
   " ------------------------------------------------- "
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
end subroutine numhess_header

subroutine md_header(iunit)
integer,intent(in) :: iunit
write(iunit,'(10x,a)') &
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
   " ------------------------------------------------- ",&
   "|               Molecular Dynamics                |",&
   " ------------------------------------------------- "
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
end subroutine md_header

subroutine metadyn_header(iunit)
integer,intent(in) :: iunit
write(iunit,'(10x,a)') &
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
   " ------------------------------------------------- ",&
   "|                  Meta Dynamics                  |",&
   " ------------------------------------------------- "
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
end subroutine metadyn_header

subroutine rmsdpath_header(iunit)
integer,intent(in) :: iunit
write(iunit,'(10x,a)') &
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
   " ------------------------------------------------- ",&
   "|                     P A T H                     |",&
   "|            RMSD-Push/Pull Path Finder           |",&
   " ------------------------------------------------- "
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
end subroutine rmsdpath_header

subroutine reactor_header(iunit)
integer,intent(in) :: iunit
write(iunit,'(10x,a)') &
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
   " ------------------------------------------------- ",&
   "|                  R E A C T O R                  |",&
   "|        RMSD-biased meta-dynamic reactions       |",&
   " ------------------------------------------------- "
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
end subroutine reactor_header

subroutine siman_header(iunit)
integer,intent(in) :: iunit
write(iunit,'(10x,a)') &
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
   " ------------------------------------------------- ",&
   "|                    S I M A N                    |",&
   "|               Simulated Annealing               |",&
   "|              conformational search              |",&
   " ------------------------------------------------- "
   !< < < < < < < < < < < < < > > > > > > > > > > > > >!
end subroutine siman_header

subroutine generic_header(iunit,string,width,offset)
implicit none
integer,intent(in) :: iunit
integer,intent(in) :: offset
integer,intent(in) :: width
character(len=*),intent(in) :: string
character(len=width) :: dum1,dum2
character(len=2*width) :: outstring
character(len=width) :: formatstr
integer :: strlen,ifront,iback
strlen = len(string)
ifront = (width - strlen)/2
iback  = width - ifront - strlen
write(dum1,*) width
write(dum2,*) offset
write(formatstr,'(i0,"x,a,",i0,"x")') ifront,iback
write(outstring,'("|",'//formatstr//',"|")') string
write(iunit,'('//dum2//'x,1x,'//dum1//'("-"),1x)')
write(iunit,'('//dum2//'x,a)') trim(outstring)
write(iunit,'('//dum2//'x,1x,'//dum1//'("-"),1x)')
end subroutine generic_header

