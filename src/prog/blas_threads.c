/*
 * This file is part of xtb.
 *
 * Copyright (C) 2026 xtb contributors
 *
 * xtb is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * xtb is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with xtb.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-Identifier: LGPL-3.0-or-later
 *
 * Weak-symbol bridge to the runtime entry points of the linked BLAS.
 *
 * `--blas-threads` (`set_blas_threads` in src/prog/main.F90) has to reach the
 * runtime entry point itself: the pool cannot be resized through the
 * environment from inside the program, because a pthread OpenBLAS sizes it in
 * an ELF constructor that runs before `main()`.  The original route is
 * `dlopen(NULL, RTLD_NOW)` + `dlsym`, which works for a dynamically linked BLAS
 * but can never work for a fully static executable: such an image has no
 * `.dynsym` at all, so the entry points live in `.symtab` only and are
 * invisible to `dlsym` even though the code is in the image.  In a static
 * build the flag therefore used to change nothing.
 *
 * The weak references below add a link-time binding in front of that lookup.
 * A weak undefined reference does **not** by itself make an archive member be
 * extracted - members of `libopenblas.a` are only pulled in to satisfy strong
 * references - so this route depends on something else extracting the members
 * that define the entry points.  xtb always calls BLAS (`dgemm`, `dsymm`, ...),
 * which extracts `blas_server.o` (the setter) and `memory.o` (the getter) in
 * the OpenBLAS 0.3.21 layout shipped by Debian.  If that ever stops holding,
 * the weak symbol stays NULL, the functions below report 0 and
 * `set_blas_threads` falls through to the `dlopen`/`dlsym` route: no call goes
 * through a NULL pointer and no message is invented.
 *
 * A weak reference is a GNU extension, so the whole route is compiled out
 * where it is unavailable; both functions then report 0 and the dynamic route
 * is the only one, exactly as before this file existed.
 */

#include <stddef.h>

#if defined(__GNUC__) || defined(__clang__)
#  define XTB_BLAS_WEAK __attribute__((weak))
#  define XTB_BLAS_LINK_TIME_BINDING 1
#else
#  define XTB_BLAS_LINK_TIME_BINDING 0
#endif

/* Backend codes, mirrored by `set_blas_threads` in src/prog/main.F90 */
#define XTB_BLAS_OPENBLAS 1
#define XTB_BLAS_MKL 2

#if XTB_BLAS_LINK_TIME_BINDING
extern void openblas_set_num_threads(int) XTB_BLAS_WEAK;
extern int openblas_get_num_threads(void) XTB_BLAS_WEAK;
extern void mkl_set_num_threads(int) XTB_BLAS_WEAK;
extern int mkl_get_max_threads(void) XTB_BLAS_WEAK;
#endif

/*
 * Set the pool size of `backend` to `n`.  Returns 1 when the entry point was
 * bound at link time and called, 0 when this backend has no link-time binding
 * - the caller then falls back to dlopen/dlsym.  An unbound symbol is never
 * called.
 */
int
xtb_blas_set_threads(int backend, int n)
{
#if XTB_BLAS_LINK_TIME_BINDING
   if (backend == XTB_BLAS_OPENBLAS) {
      if (openblas_set_num_threads == NULL)
         return 0;
      openblas_set_num_threads(n);
      return 1;
   }
   if (backend == XTB_BLAS_MKL) {
      if (mkl_set_num_threads == NULL)
         return 0;
      mkl_set_num_threads(n);
      return 1;
   }
#else
   (void) backend;
   (void) n;
#endif
   return 0;
}

/*
 * Read the pool size `backend` reports into `*n`.  Returns 1 when the entry
 * point was bound at link time and the value was written, 0 otherwise.
 */
int
xtb_blas_get_threads(int backend, int *n)
{
#if XTB_BLAS_LINK_TIME_BINDING
   if (backend == XTB_BLAS_OPENBLAS) {
      if (openblas_get_num_threads == NULL)
         return 0;
      *n = openblas_get_num_threads();
      return 1;
   }
   if (backend == XTB_BLAS_MKL) {
      if (mkl_get_max_threads == NULL)
         return 0;
      *n = mkl_get_max_threads();
      return 1;
   }
#else
   (void) backend;
   (void) n;
#endif
   return 0;
}
