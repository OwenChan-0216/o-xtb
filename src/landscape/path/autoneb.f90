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

!> AutoNEB: incremental chain-of-states path building (Kolsbjerg, Groves &
!> Hammer, J. Chem. Phys. **145**, 094107 (2016); erratum J. Chem. Phys.
!> **148**, 029903 (2018)).
!>
!> Instead of placing all images of a band at once, AutoNEB starts from a
!> **coarse** path, relaxes it, and then inserts one additional image
!> wherever the path is least resolved, re-relaxing the enlarged band.  The
!> loop repeats until the requested number of images is reached.  The
!> advantage is that the expensive part of the work (the electronic
!> structure evaluations) is spent where the path still has structure, and
!> that the intermediate stages already give a usable barrier estimate.
!>
!> **Insertion rule** (the `add` step of the publication).  The resolution of
!> a discrete path is taken as the sequence of the adjacent energy
!> differences `dE_k = |E_{k+1} - E_k|`; the interval
!>
!>     `k* = argmax_k dE_k`
!>
!> is the one in which the energy profile changes fastest, i.e. the interval
!> the saddle point is hidden in, and the new image is inserted at its
!> **geometric midpoint**.  The erratum of the publication clarifies that the
!> new image is placed at the midpoint of the selected interval (and then
!> relaxed with the band), not at a linearly extrapolated position; the
!> implementation follows the corrected rule.  The alternative "insert at the
!> longest geometric gap `argmax_k |R_{k+1} - R_k|`" is deliberately **not**
!> used: a relaxed band has an almost uniform image spacing (its Eq. 12
!> spring term equalises the distances), so the geometric criterion would
!> place the new image in an energy flat region picked by round off, while
!> the energy criterion keeps it at the barrier.  The unit test
!> `autoneb-insertion` pins the two rules apart on a path where they differ.
!>
!> **Stages.** Every stage is a full relaxation of the current path with the
!> caller's band settings (`xtb_landscape_path_neb::landscape_band_optimize`
!> with `initial_images`), so the two-stage CI-NEB protocol, the improved
!> tangent, the dynamic springs and the Kabsch alignment are exactly the
!> phase-one implementations and are not duplicated here.  The first stage
!> either builds the coarse path (`autoneb_nstart` images) or adopts a
!> supplied path (the restart reuse below).
!>
!> **Restart reuse** (`landscape_path_settings%autoneb_restart_file`).  The
!> task layer reads the multi-frame path of an earlier run and passes it as
!> `initial_images`.  Because every stage is a deterministic function of its
!> input path, restarting from a partially grown path and continuing produces
!> the same final band as one uninterrupted run (the unit test
!> `autoneb-restart` measures the difference).  The semantics are therefore
!> "the completed stages are not repeated"; the restart file is never written
!> automatically and its name is checked by the task layer.
!>
!> **Resource bounds** (PLAN section 6.4).  The branching AutoNEB of the
!> publication manages a *tree* of paths; the tree is deliberately not
!> implemented and two hard bounds stand in for it:
!>
!>  * `max_paths` is the hard upper bound of the number of images of the
!>    path.  A request above it (`n_images > max_paths`), a coarse path above
!>    it (`autoneb_nstart > max_paths`) and an inconsistent start
!>    (`autoneb_nstart > n_images`) are `env%error`s: the driver never grows
!>    a path beyond a bound and never silently truncates a request.
!>  * `max_depth` is the hard upper bound of the number of insertion stages.
!>    A run that stops at it reports the cap (`autoneb%cap_reached` and the
!>    message) together with the number of images it reached; that is a
!>    diagnostic of an under-budgeted run and not an error, because the last
!>    stage is still a valid (if coarser) band.
!>
!> Units: coordinates in bohr, energies in hartree, forces and gradients in
!> hartree/bohr; the printed barrier uses `autokcal` and is labelled.
module xtb_landscape_path_autoneb
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_convert, only : autokcal
   use xtb_type_environment, only : TEnvironment
   use xtb_landscape_settings, only : landscape_path_settings
   use xtb_landscape_engine, only : landscape_energy_model
   use xtb_landscape_path_neb, only : landscape_band_type, landscape_band_optimize
   implicit none(type, external)
   private

   public :: landscape_autoneb_type, landscape_autoneb_optimize
   public :: landscape_autoneb_interval, landscape_autoneb_insert
   public :: landscape_autoneb_check

   !> Result of an AutoNEB run.
   type :: landscape_autoneb_type
      !> True if the last stage met the band convergence criterion
      logical :: converged = .false.
      !> True if the insertion loop stopped at `max_paths` or `max_depth`
      logical :: cap_reached = .false.
      !> Number of band relaxations performed (>= 1)
      integer :: n_stages = 0
      !> Number of images inserted (<= `max_depth`)
      integer :: n_insert = 0
      !> Total number of band iterations over all stages
      integer :: n_iter = 0
      !> Total number of image evaluations over all stages
      integer :: n_eval = 0
      !> Number of images of the final path
      integer :: n_images = 0
      !> Highest energy image of the final path (the saddle candidate)
      integer :: saddle_image = 0
      !> Ignited climbing image of the final path (0 if none)
      integer :: climbing_image = 0
      !> Energy of the saddle candidate (hartree)
      real(wp) :: ts_energy = 0.0_wp
      !> Barrier of the final path relative to the reactant (hartree)
      real(wp) :: barrier = 0.0_wp
      !> Average perpendicular force RMS of the final path (hartree/bohr)
      real(wp) :: f_rms_avg = 0.0_wp
      !> Largest per-image perpendicular force RMS (hartree/bohr)
      real(wp) :: f_rms_max = 0.0_wp
      !> Unprojected force RMS at the climbing image (hartree/bohr)
      real(wp) :: ci_f_rms = 0.0_wp
      !> Energy of every image of the final path (hartree)
      real(wp), allocatable :: energies(:)
      !> Distance between consecutive images of the final path (bohr)
      real(wp), allocatable :: distances(:)
      !> Energy of the saddle candidate of every stage (hartree), length
      !> `n_stages`; the candidate list written to `path_ts_list.xyz`
      real(wp), allocatable :: stage_energies(:)
      !> Geometry of the saddle candidate of every stage, `(3, nat, n_stages)`
      real(wp), allocatable :: stage_images(:, :, :)
      !> Number of images of every stage, length `n_stages`
      integer, allocatable :: stage_n_images(:)
      !> Left image index of the interval the new image was inserted into,
      !> one entry per insertion (length `max_depth`); the unit test
      !> `autoneb-insertion` pins the resolution rule with it
      integer, allocatable :: insert_interval(:)
      !> Human readable termination message
      character(len=:), allocatable :: message
   end type landscape_autoneb_type

contains

!> Validate the AutoNEB resource bounds of a settings object.
!>
!> The bounds are checked **before** any geometry is built, so an inconsistent
!> request fails immediately and never grows a path beyond a limit.  `fail` is
!> set for every violation and the corresponding `env%error` names the two
!> numbers that conflict.
subroutine landscape_autoneb_check(env, settings, fail)
   character(len=*), parameter :: source = 'landscape_autoneb_check'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Band settings
   type(landscape_path_settings), intent(in) :: settings
   !> Failure flag
   logical, intent(out) :: fail

   character(len=16) :: s1, s2

   fail = .true.
   if (settings%max_paths < 3) then
      write(s1, '(i0)') settings%max_paths
      call env%error("the AutoNEB image limit max_paths ("//trim(s1)//&
         & ") must be at least 3", source)
      return
   end if
   if (settings%max_depth < 1) then
      call env%error("the AutoNEB insertion depth limit max_depth must be "//&
         & "at least 1", source)
      return
   end if
   if (settings%autoneb_nstart < 3) then
      write(s1, '(i0)') settings%autoneb_nstart
      call env%error("the coarse AutoNEB path autoneb_nstart ("//trim(s1)//&
         & ") must be at least 3 images", source)
      return
   end if
   if (settings%autoneb_nstart > settings%n_images) then
      write(s1, '(i0)') settings%autoneb_nstart
      write(s2, '(i0)') settings%n_images
      call env%error("the coarse AutoNEB path autoneb_nstart ("//trim(s1)//&
         & ") exceeds the requested number of images ("//trim(s2)//")", source)
      return
   end if
   if (settings%n_images > settings%max_paths) then
      write(s1, '(i0)') settings%n_images
      write(s2, '(i0)') settings%max_paths
      call env%error("the requested number of images ("//trim(s1)//&
         & ") exceeds the hard AutoNEB limit max_paths ("//trim(s2)//")", source)
      return
   end if
   fail = .false.

end subroutine landscape_autoneb_check

!> Interval of the worst energy resolution of a path.
!>
!> Returns `k` of the pair `(k, k+1)` with the largest adjacent energy
!> difference `|E_{k+1} - E_k|`; ties are broken by the lowest index, so the
!> choice is deterministic.  The caller inserts the new image into that
!> interval (see the module header for why the energy and not the geometric
!> gap is the resolution measure).
pure subroutine landscape_autoneb_interval(energies, interval)
   !> Image energies (hartree), endpoints included
   real(wp), intent(in) :: energies(:)
   !> 1-based index of the left image of the interval, 0 if there is none
   integer, intent(out) :: interval

   real(wp) :: largest, rise
   integer :: k

   interval = 0
   largest = -1.0_wp
   do k = 1, size(energies) - 1
      rise = abs(energies(k + 1) - energies(k))
      if (rise > largest) then
         largest = rise
         interval = k
      end if
   end do

end subroutine landscape_autoneb_interval

!> Insert one image at the midpoint of an interval of a path.
!>
!> `enlarged` holds the path with one additional image; the two endpoints and
!> the order of the images are preserved, and the new image is the arithmetic
!> midpoint of the two images that bracket the interval.  The inserted image
!> is the midpoint of two images of an already aligned path, so the path stays
!> in one frame; the band relaxation that follows re-aligns it anyway when
!> `settings%align` is set.
subroutine landscape_autoneb_insert(images, interval, enlarged, fail)
   !> Path images `(3, nat, n_images)`
   real(wp), intent(in) :: images(:, :, :)
   !> Interval the image is inserted into (between image `interval` and `+1`)
   integer, intent(in) :: interval
   !> Enlarged path `(3, nat, n_images + 1)`, allocated on return
   real(wp), allocatable, intent(out) :: enlarged(:, :, :)
   !> Failure flag
   logical, intent(out) :: fail

   integer :: k, n_images, nat

   fail = .true.
   if (size(images, 1) /= 3) return
   nat = size(images, 2)
   if (nat < 1) return
   n_images = size(images, 3)
   if (n_images < 3) return
   if (interval < 1 .or. interval >= n_images) return

   allocate(enlarged(3, nat, n_images + 1))
   do k = 1, interval
      enlarged(:, :, k) = images(:, :, k)
   end do
   enlarged(:, :, interval + 1) = 0.5_wp*(images(:, :, interval) + &
      & images(:, :, interval + 1))
   do k = interval + 1, n_images
      enlarged(:, :, k + 1) = images(:, :, k)
   end do
   fail = .false.

end subroutine landscape_autoneb_insert

!> AutoNEB driver: build a path incrementally and return the final band.
!>
!> `initial_images` starts the run from an existing path (restart reuse); when
!> it is absent the first stage builds the coarse path of
!> `settings%autoneb_nstart` images.  The driver owns the insertion loop; every
!> stage is a full band relaxation with the caller's settings, so the returned
!> `band` state - convergence, energies, climbing image - is that of the last
!> stage.
!>
!> On return `images` holds the final path, `energies` its energies and
!> `forces` its band forces; `auto` summarises the run, including the saddle
!> candidate of every stage (the frames of `path_ts_list.xyz`).
subroutine landscape_autoneb_optimize(env, model, settings, reactant, product, &
      & images, energies, forces, auto, initial_images)
   character(len=*), parameter :: source = 'landscape_autoneb_optimize'
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> Potential
   class(landscape_energy_model), intent(inout) :: model
   !> Band settings (`max_paths`, `max_depth`, `autoneb_nstart` are the caps)
   type(landscape_path_settings), intent(in) :: settings
   !> Reactant geometry (bohr), shape `(3, nat)`
   real(wp), intent(in) :: reactant(:, :)
   !> Product geometry (bohr), shape `(3, nat)`
   real(wp), intent(in) :: product(:, :)
   !> Final path images `(3, nat, n_images)`
   real(wp), allocatable, intent(out) :: images(:, :, :)
   !> Energy of every image of the final path (hartree)
   real(wp), allocatable, intent(out) :: energies(:)
   !> Band force of every image of the final path (hartree/bohr)
   real(wp), allocatable, intent(out) :: forces(:, :, :)
   !> AutoNEB result
   type(landscape_autoneb_type), intent(out) :: auto
   !> Path to start from (bohr), `(3, nat, n)`; absent = coarse build
   real(wp), intent(in), optional :: initial_images(:, :, :)

   type(landscape_band_type) :: band
   type(landscape_path_settings) :: stage
   real(wp), allocatable :: added(:, :, :)
   integer :: target, interval, stage_max
   logical :: fail
   character(len=160) :: buffer

   auto%converged = .false.
   auto%cap_reached = .false.
   auto%message = "autoneb completed"
   if (size(reactant, 1) /= 3 .or. size(product, 1) /= 3) then
      call env%error("the endpoints are not three dimensional", source)
      return
   end if
   if (size(reactant, 2) /= size(product, 2)) then
      call env%error("the endpoints do not have the same number of atoms", source)
      return
   end if

   call landscape_autoneb_check(env, settings, fail)
   if (fail) then
      auto%message = "the AutoNEB resource bounds are inconsistent"
      return
   end if

   stage_max = settings%max_depth + 1
   allocate(auto%stage_energies(stage_max), source=0.0_wp)
   allocate(auto%stage_n_images(stage_max), source=0)
   allocate(auto%insert_interval(stage_max - 1), source=0)
   allocate(auto%stage_images(3, size(reactant, 2), stage_max), source=0.0_wp)

   ! the target number of images: the request, which the bound check above
   ! already proved to be at most `max_paths`
   target = min(settings%n_images, settings%max_paths)

   if (settings%printlevel > 0) then
      write(env%unit, '(1x,a,i0,a,i0)') "autoneb: coarse path of ", &
         & settings%autoneb_nstart, " images, target ", target
      write(env%unit, '(1x,a,i0,a,i0)') "autoneb: limits max_paths ", &
         & settings%max_paths, ", max_depth ", settings%max_depth
   end if

   ! --- first stage ---------------------------------------------------
   if (present(initial_images)) then
      ! the adopted path is the restart of an earlier run; `max_paths` is the
      ! hard upper bound of the image count, so a path that is larger than it
      ! is rejected instead of being adopted verbatim (the size of a file can
      ! be anything; only the count of a freshly built path is bounded by the
      ! request)
      if (size(initial_images, 3) > settings%max_paths) then
         write(buffer, '(a,i0,a,i0,a)') "the adopted AutoNEB path has ", &
            & size(initial_images, 3), " images, more than the hard limit ", &
            & settings%max_paths, " (--lts-autoneb-max-paths)"
         call env%error(trim(buffer), source)
         auto%message = "the adopted path exceeds the AutoNEB image limit"
         return
      end if
      call landscape_band_optimize(env, model, settings, reactant, product, &
         & images, energies, forces, band, initial_images=initial_images)
   else
      ! the coarse start path has `autoneb_nstart` images; `n_images` is the
      ! *target* of the grown path, so the band kernel has to be asked for the
      ! coarse count (it builds exactly `n_images` images)
      stage = settings
      stage%n_images = settings%autoneb_nstart
      call landscape_band_optimize(env, model, stage, reactant, product, &
         & images, energies, forces, band)
   end if
   if (.not. allocated(images) .or. .not. allocated(band%energies)) then
      auto%message = band%message
      return
   end if
   auto%n_stages = 1
   call autoneb_record_stage(auto, band, images, 1)
   auto%n_iter = band%n_iter
   auto%n_eval = band%n_eval
   if (settings%printlevel > 0) call autoneb_print_stage(env, auto, band, 1)

   ! --- insertion loop ------------------------------------------------
   do while (size(images, 3) < target .and. auto%n_insert < settings%max_depth)
      call landscape_autoneb_interval(band%energies, interval)
      if (interval < 1) then
         auto%message = "the path has no interval to insert an image into"
         return
      end if
      auto%insert_interval(auto%n_insert + 1) = interval
      call landscape_autoneb_insert(images, interval, added, fail)
      if (fail) then
         call env%error("the image could not be inserted", source)
         auto%message = "the image insertion failed"
         return
      end if
      if (settings%printlevel > 0) then
         write(env%unit, '(1x,a,i0,a,es10.3,a)') "autoneb: inserted an image at ", &
            & interval + 1, " of ", abs(band%energies(interval + 1) - &
            & band%energies(interval)), " Eh (worst energy resolution)"
      end if
      call landscape_band_optimize(env, model, settings, reactant, product, &
         & images, energies, forces, band, initial_images=added)
      if (.not. allocated(images) .or. .not. allocated(band%energies)) then
         auto%message = band%message
         return
      end if
      auto%n_insert = auto%n_insert + 1
      auto%n_stages = auto%n_stages + 1
      auto%n_iter = auto%n_iter + band%n_iter
      auto%n_eval = auto%n_eval + band%n_eval
      call autoneb_record_stage(auto, band, images, auto%n_stages)
      if (settings%printlevel > 0) call autoneb_print_stage(env, auto, band, &
         & auto%n_stages)
   end do

   ! --- cap diagnosis -------------------------------------------------
   if (size(images, 3) < target) then
      auto%cap_reached = .true.
      ! the message is formatted into a fixed length buffer: an internal write
      ! straight into the deferred length component would use its current
      ! length and abort with "End of record" as soon as the text is longer
      ! than the previous message
      if (auto%n_insert >= settings%max_depth) then
         write(buffer, '(a,i0,a,i0,a,i0,a)') &
            & "stopped at the insertion depth limit max_depth = ", &
            & settings%max_depth, " with ", size(images, 3), " of ", target, &
            & " images"
      else
         write(buffer, '(a,i0,a,i0,a,i0,a)') &
            & "stopped at the image limit max_paths = ", settings%max_paths, &
            & " with ", size(images, 3), " of ", target, " images"
      end if
      auto%message = trim(buffer)
   end if

   auto%n_images = size(images, 3)
   auto%saddle_image = band%highest_image
   auto%climbing_image = band%climbing_image
   auto%converged = band%converged
   auto%ts_energy = band%ts_energy
   auto%barrier = band%barrier
   auto%f_rms_avg = band%f_rms_avg
   auto%f_rms_max = band%f_rms_max
   auto%ci_f_rms = band%ci_f_rms
   if (allocated(auto%energies)) deallocate(auto%energies)
   allocate(auto%energies(size(images, 3)), source=band%energies)
   if (allocated(auto%distances)) deallocate(auto%distances)
   allocate(auto%distances(size(band%distances)), source=band%distances)

   if (settings%printlevel > 0) then
      write(env%unit, '(1x,a,i0,a,i0,a,i0,a)') "autoneb: ", auto%n_stages, &
         & " stages, ", auto%n_insert, " inserted images, ", auto%n_images, &
         & " images in the final path"
      write(env%unit, '(1x,a,f20.12,a,f12.4,a,i0)') "autoneb: saddle candidate ", &
         & auto%ts_energy, " Eh, barrier ", auto%barrier*autokcal, &
         & " kcal/mol at image ", auto%saddle_image
      write(env%unit, '(1x,a,a)') "autoneb: termination ", trim(auto%message)
   end if

end subroutine landscape_autoneb_optimize

!> Record the saddle candidate of one stage.
!>
!> The candidate of a stage is the climbing image when the stage ignited one
!> (CI-NEB stages) and otherwise the highest energy internal image; its energy
!> and geometry are appended to the candidate list of the result, which the
!> task layer writes to `path_ts_list.xyz`.
subroutine autoneb_record_stage(auto, band, images, stage)
   !> AutoNEB result
   type(landscape_autoneb_type), intent(inout) :: auto
   !> Stage band result
   type(landscape_band_type), intent(in) :: band
   !> Path images of the stage `(3, nat, n_images)`
   real(wp), intent(in) :: images(:, :, :)
   !> 1-based stage number
   integer, intent(in) :: stage

   integer :: k

   if (stage < 1 .or. stage > size(auto%stage_images, 3)) return
   if (.not. allocated(band%energies)) return
   k = band%highest_image
   if (band%climbing_image > 0) k = band%climbing_image
   k = min(max(k, 1), size(images, 3))
   auto%stage_energies(stage) = band%energies(k)
   auto%stage_images(:, :, stage) = images(:, :, k)
   auto%stage_n_images(stage) = size(images, 3)

end subroutine autoneb_record_stage

!> Print the summary line of one AutoNEB stage.
subroutine autoneb_print_stage(env, auto, band, stage)
   !> Computational environment
   type(TEnvironment), intent(inout) :: env
   !> AutoNEB result (the recorded stage data)
   type(landscape_autoneb_type), intent(in) :: auto
   !> Stage band result
   type(landscape_band_type), intent(in) :: band
   !> 1-based stage number
   integer, intent(in) :: stage

   write(env%unit, '(1x,a,i0,a,i0,a,i0,a,f20.12,a,f12.4,a)') "autoneb stage ", &
      & stage, ": images ", auto%stage_n_images(stage), ", iterations ", &
      & band%n_iter, ", E(saddle) ", auto%stage_energies(stage), ", barrier ", &
      & (auto%stage_energies(stage) - band%energies(1))*autokcal, " kcal/mol"

end subroutine autoneb_print_stage

end module xtb_landscape_path_autoneb
