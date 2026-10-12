#!/usr/bin/env bash
# Numerical Hessian of the relaxed benzoic acid dimer: frequencies, zero-mode
# count and the thermochemistry block.                       [OxTB 0.1.0 / xTB 6.7.1, c712f9e]
set -euo pipefail
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../..")"
oxtb input.xyz --gfn 2 --lvib --norestart > oxtb.log 2>&1
