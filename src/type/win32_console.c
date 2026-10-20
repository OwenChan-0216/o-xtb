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
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * UTF-8 console output for Windows targets.
 *
 * The labels this program prints are UTF-8: `Mol. C6AA /au·bohr⁶` carries
 * `·` U+00B7 = C2 B7, `⁶` U+2076 = E2 81 B6, the frequency table carries
 * `α` U+03B1 = CE B1 and `⁻¹` U+207B U+00B9 = E2 81 BB C2 B9
 * (`docs/_simplify-recon/194-windows-encoding.md` has the full inventory).
 * A Windows console decodes that byte stream with the code page it was
 * started with; on a Chinese-locale system that is GBK/CP936, where C2 B7 is
 * the CJK character 路 and CE B1 is 伪, so correct bytes are displayed as
 * mojibake.  The bytes are right - the console has to be told that they are
 * UTF-8, which is what `SetConsoleOutputCP(CP_UTF8)` does here.  Measured on
 * the reporting machine: the same binary prints every glyph correctly after
 * `chcp 65001`, so this call only saves the user that step.
 *
 * `src/prog/main.F90` calls this under `#ifdef _WIN32` and ignores the
 * result: a console nicety must never fail a run.  gfortran's Fortran
 * preprocessor defines no target macro at all, so that `_WIN32` comes from
 * the Windows block of the top-level `CMakeLists.txt` - the same mechanism
 * that already guards the `NUL` logfile and the MinGW path separator of this
 * tree.  This file is compiled only for a Windows target
 * (`src/type/CMakeLists.txt`, same rule as `win32_readlink.c`), so nothing
 * outside a Windows build references `xtb_console_utf8`.
 *
 * Redirected output needs nothing: the program's bytes are not translated on
 * the way to a file or a pipe, so `oxtb ... > out.txt` and every written
 * output file stay UTF-8.  A redirected run also leaves the console alone -
 * the code page is per-console state and outlives the process, so it is
 * changed only when this process actually talks to a console screen buffer.
 */

#include <windows.h>

/* Sets the console output code page to UTF-8.
   Returns 1 when it was set, 0 when stdout is not a console or the call
   failed. */
int
xtb_console_utf8(void)
{
   HANDLE out;
   DWORD mode;

   out = GetStdHandle(STD_OUTPUT_HANDLE);
   if (out == NULL || out == INVALID_HANDLE_VALUE) return 0;
   /* GetConsoleMode succeeds only for a console screen buffer, which is
      exactly the case where the console decodes the bytes. */
   if (!GetConsoleMode(out, &mode)) return 0;
   return SetConsoleOutputCP(CP_UTF8) ? 1 : 0;
}
