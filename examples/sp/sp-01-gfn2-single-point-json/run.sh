#!/usr/bin/env bash
# GFN2 single point of the benzoic acid dimer plus the unified machine-readable
# result document (--ljson).                                  [OxTB 0.1.0 / xTB 6.7.1, c712f9e]
set -euo pipefail
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../..")"
oxtb input.xyz --gfn 2 --sp --ljson --norestart > oxtb.log 2>&1
