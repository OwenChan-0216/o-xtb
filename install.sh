#!/usr/bin/env bash
#
# This file is part of xtb.
#
# Copyright (C) 2026 xtb contributors
#
# xtb is free software: you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# xtb is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with xtb.  If not, see <https://www.gnu.org/licenses/>.
#
# One command to configure, build, test, install and register o-xtb.
#
#   ./install.sh
#
# The script stops at the first failing step and leaves that step's exit
# status behind, so it is usable from a release checklist or from CI.  It is
# idempotent: rerunning it reconfigures, rebuilds what changed, reruns the
# tests, reinstalls and refreshes the registration.
#
# Environment overrides (all optional):
#
#   XTB_PREFIX     install prefix           default: $HOME/programs/o-xtb
#   XTB_BIN_DIR    registration directory    default: $HOME/.local/bin
#   XTB_CMAKE      cmake executable         default: the one in PATH
#   XTB_JOBS       parallel build jobs      default: 8
#   XTB_MAN_DIR    man registration dir     default: $HOME/.local/share/man
#   XTB_REGISTER_MAN  ON installs the rendered man pages into $XTB_MAN_DIR
#                     (default: OFF, like XTB_REGISTER_COMMAND; `man` reads
#                     $XTB_MAN_DIR/man1/oxtb.1 and $XTB_MAN_DIR/man7/xcontrol.7
#                     only when that directory is in MANPATH)
#
# The executable this script produces is fully static on glibc systems:
# CMAKE_EXE_LINKER_FLAGS=-static, BLA_STATIC=ON and the static libgomp.  That
# needs WITH_OBJECT=OFF, because WITH_OBJECT=ON also builds the shared library
# and the C API test links it - an executable cannot be linked statically
# against a shared object.  The consequence is that the C API test
# (`xtb/CAPI`) is not part of this configuration; run the default (dynamic)
# configuration to exercise it.
#
# -O2 is required for GNU Fortran: this checkout is not supported at -O3
# (cmake/CMakeLists.txt explains why), so CMAKE_Fortran_FLAGS_RELEASE is
# pinned instead of relying on CMake's `Release` default of -O3.
#
# -DXTB_REGISTER_COMMAND=OFF is passed explicitly because it is a cached
# option: a tree that was once configured with the registration switch on
# would otherwise keep writing into the user's PATH after a build.  This
# script registers explicitly in its own step instead.
#
# -Wl,-u,pthread_mutex_destroy is not cosmetic.  libgfortran's exit handler
# calls pthread_mutex_destroy through a weak reference that is guarded by a
# proxy symbol (__pthread_key_create in gthr-posix.h).  Under -static a weak
# reference cannot pull a member out of libc.a, so if anything in the link
# references the guard but nothing references pthread_mutex_destroy, the guard
# reads true and the call goes to address 0: the process SIGSEGVs while
# flushing its units during exit, with RIP=0 and no warning.  This build is
# only safe by luck - OpenBLAS's blas_server.o happens to reference the symbol
# - and -u turns that luck into a guarantee.  Full analysis, including the
# three falsifying experiments: docs/_simplify-recon/96-static-exit-sigsegv.md.
#
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${XTB_BUILD_DIR:-${SOURCE_DIR}/build}"
LOG_DIR="${BUILD_DIR}/logs"
PREFIX="${XTB_PREFIX:-${HOME}/programs/o-xtb}"
BIN_DIR="${XTB_BIN_DIR:-${HOME}/.local/bin}"
MAN_DIR="${XTB_MAN_DIR:-${HOME}/.local/share/man}"
REGISTER_MAN="${XTB_REGISTER_MAN:-OFF}"
CMAKE="${XTB_CMAKE:-$(command -v cmake)}"
JOBS="${XTB_JOBS:-8}"

# The command line program is called `oxtb` in this renamed tree and `xtb` in
# the upstream tree; it is the single name this script needs from the rename.
COMMAND_NAME="${XTB_COMMAND:-oxtb}"

STEP=""
trap 'rc=$?; printf "\n!!! FAILED at step: %s (exit %d)\n" "${STEP:-unknown}" "$rc" >&2; exit "$rc"' ERR

step() { STEP="$1"; printf '\n=== %s\n' "$STEP"; }
ok()   { printf '    ok: %s\n' "$1"; }

selfcheck_dir="$(mktemp -d)"
trap 'rm -rf "${selfcheck_dir}"' EXIT
mkdir -p "${LOG_DIR}"

step "configure (static executable, -O2, tests on)"
GOMP_A="$(gfortran -print-file-name=libgomp.a)"
if [ ! -f "${GOMP_A}" ]; then
   printf '    note: no static libgomp found, OpenMP will stay shared\n' >&2
   GOMP_A=""
fi
"${CMAKE}" -S "${SOURCE_DIR}" -B "${BUILD_DIR}" \
   -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON -DWITH_OBJECT=OFF \
   -DCMAKE_BUILD_TYPE=Release \
   -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG" \
   -DCMAKE_EXE_LINKER_FLAGS="-static -Wl,-u,pthread_mutex_destroy" \
   -DBUILD_SHARED_LIBS=OFF -DBLA_STATIC=ON \
   -DXTB_REGISTER_COMMAND=OFF \
   ${GOMP_A:+-DOpenMP_gomp_LIBRARY="${GOMP_A}"} \
   >"${LOG_DIR}/configure.log" 2>&1
ok "configured ${SOURCE_DIR} -> ${BUILD_DIR}"

step "build"
"${CMAKE}" --build "${BUILD_DIR}" -j "${JOBS}" >"${LOG_DIR}/build.log" 2>&1
if grep -qiE 'Error: |Fatal' "${LOG_DIR}/build.log"; then
   grep -iE 'Error: |Fatal' "${LOG_DIR}/build.log" >&2
   false
fi
ok "built ${BUILD_DIR}/${COMMAND_NAME}"

step "test (landscape, help, regression subset)"
OMP_NUM_THREADS=1 ctest --test-dir "${BUILD_DIR}" -R landscape -j "${JOBS}" \
   >"${LOG_DIR}/ctest-landscape.log" 2>&1
OMP_NUM_THREADS=1 ctest --test-dir "${BUILD_DIR}" -R help \
   >"${LOG_DIR}/ctest-help.log" 2>&1
OMP_NUM_THREADS=1 ctest --test-dir "${BUILD_DIR}" \
   -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI' \
   >"${LOG_DIR}/ctest-regression.log" 2>&1
for log in landscape help regression; do
   ok "$(grep -hE 'tests passed' "${LOG_DIR}/ctest-${log}.log" | tail -1) (-R ${log})"
done

step "install into ${PREFIX}"
"${CMAKE}" --install "${BUILD_DIR}" --prefix "${PREFIX}" >"${LOG_DIR}/install.log" 2>&1
# `ldd` itself exits non-zero for a static executable, so its output is
# captured first and never used at the end of a pipeline (`set -o pipefail`
# would otherwise report the check as failed).
ldd_out="$(ldd "${PREFIX}/bin/${COMMAND_NAME}" 2>&1 || true)"
case "${ldd_out}" in
   *"not a dynamic executable"*) ok "installed ${PREFIX}/bin/${COMMAND_NAME} (statically linked)" ;;
   *) printf '%s\n' "${ldd_out}" >&2; false ;;
esac

step "register ${BIN_DIR}/${COMMAND_NAME}"
mkdir -p "${BIN_DIR}"
ln -sfn "${PREFIX}/bin/${COMMAND_NAME}" "${BIN_DIR}/${COMMAND_NAME}"
ok "$(readlink "${BIN_DIR}/${COMMAND_NAME}")"

# Off by default, like XTB_REGISTER_COMMAND: the build must not silently write
# into the user's own trees.  The rendered pages are installed by CMake into
# ${PREFIX}/share/man; this step links them into the per-user man directory.
# That directory is in man's default search path on most systems, but an
# explicit MANPATH hides it, so the user has to add it to their own MANPATH.
if [ "${REGISTER_MAN}" = "ON" ]; then
   step "register man pages into ${MAN_DIR}"
   mkdir -p "${MAN_DIR}/man1" "${MAN_DIR}/man7"
   ln -sfn "${PREFIX}/share/man/man1/oxtb.1" "${MAN_DIR}/man1/oxtb.1"
   ln -sfn "${PREFIX}/share/man/man7/xcontrol.7" "${MAN_DIR}/man7/xcontrol.7"
   ok "$(readlink "${MAN_DIR}/man1/oxtb.1")"
   ok "$(readlink "${MAN_DIR}/man7/xcontrol.7")"
else
   printf '    note: man pages not registered (XTB_REGISTER_MAN=OFF); set it to ON\n'
fi

step "self check"
version_out="$("${PREFIX}/bin/${COMMAND_NAME}" --version)"
# The OxTB banner prints the product version and the engine version it is built
# on.  Only the product line is required here, so bumping either number does
# not have to touch this script.
case "${version_out}" in
   *"OxTB version"*) ;;
   *) printf 'no OxTB version banner\n' >&2; false ;;
esac
ok "$(printf '%s\n' "${version_out}" | grep -oE '(OxTB|xTB) version [0-9.]+' | tr '\n' ' ' || true)"

cat >"${selfcheck_dir}/water.xyz" <<'WATER'
3
water
O   0.00000000000000   0.00000000000000   0.00000000000000
H   0.75860200000000   0.00000000000000  -0.50428400000000
H  -0.75860200000000   0.00000000000000  -0.50428400000000
WATER
energy=""
sp_out="$(cd "${selfcheck_dir}" && OMP_NUM_THREADS=1 "${PREFIX}/bin/${COMMAND_NAME}" \
   water.xyz --sp --gfn 2 --norestart 2>/dev/null || true)"
match="$(grep -m1 -oE 'TOTAL ENERGY +[-0-9.]+' <<<"${sp_out}" || true)"
if [ -n "${match}" ]; then
   energy="${match##*TOTAL ENERGY}"
   energy="${energy// /}"
fi
[ -n "${energy}" ] || { printf 'the single point produced no energy\n' >&2; false; }
# The reference value of this geometry is -5.065772968305 Eh (measured with
# this configuration); the tolerance only absorbs unrelated float noise.
if ! awk -v e="${energy}" 'BEGIN { d = e + 5.065772968305; if (d < 0) d = -d; exit !(d < 1.0e-6) }'; then
   printf 'single point energy %s is outside the expected range\n' "${energy}" >&2
   false
fi
ok "single point water GFN2: ${energy} Eh"

printf '\ninstalled: %s\nregistered: %s -> %s\n' \
   "${PREFIX}/bin/${COMMAND_NAME}" "${BIN_DIR}/${COMMAND_NAME}" "${PREFIX}/bin/${COMMAND_NAME}"
