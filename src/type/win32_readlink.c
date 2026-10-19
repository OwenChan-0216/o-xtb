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
 * POSIX `readlink(2)` for Windows targets.
 *
 * `src/type/environment.f90` asks `/proc/self/exe` where the running image
 * lives so that an install finds its own parameter directory from the
 * executable path even when the command was looked up through `PATH`
 * (`setDefaultXtbPath`, `docs/_simplify-recon/97-xtbpath-default.md`).  That
 * file is a `.f90` source and therefore **not** preprocessed by this build
 * (`cmake/CMakeLists.txt` sets no `-cpp`), so an `#ifdef` there would be an
 * ignored preprocessor line rather than a conditional; the portable place for
 * the platform split is this file, which is compiled only for a Windows
 * target (`src/type/CMakeLists.txt`).
 *
 * Windows has no `/proc` and no symlink to read, but it has the same single
 * authoritative answer: `GetModuleFileNameA(NULL, ...)` returns the full path
 * of the running executable, which is exactly what `/proc/self/exe` is on
 * Linux.  For any other path the call reports failure, so the Fortran side
 * keeps its "the symlink cannot be resolved" branch: `procSelfExe` leaves the
 * path empty and `executableDirectory` falls back to `argv[0]`.
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <windows.h>

/* The pseudo-symlink `procSelfExe` in src/type/environment.f90 asks for */
#define XTB_PROC_SELF_EXE "/proc/self/exe"

intptr_t
readlink(const char *path, char *buf, size_t bufsiz)
{
   DWORD len;

   if (path == NULL || buf == NULL || bufsiz == 0) return -1;
   if (strcmp(path, XTB_PROC_SELF_EXE) != 0) return -1;
   len = GetModuleFileNameA(NULL, buf, (DWORD) bufsiz);
   /* 0 is an error, and a value equal to the buffer size means the path was
      truncated: both are reported as "not resolvable" rather than handed to
      the caller as a partial path. */
   if (len == 0 || len >= (DWORD) bufsiz) return -1;
   return (intptr_t) len;
}
