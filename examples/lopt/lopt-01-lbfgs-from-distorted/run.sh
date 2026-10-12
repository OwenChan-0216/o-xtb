#!/usr/bin/env bash
# L-BFGS minimisation of a deliberately distorted geometry: the energy drop,
# the step count and the final gradient norm.                 [OxTB 0.1.0 / xTB 6.7.1, c712f9e]
set -euo pipefail
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../..")"
oxtb input.xyz --gfn 2 --lopt --lopt-engine lbfgs --lopt-level normal \
    --lopt-max-steps 300 --norestart > oxtb.log 2>&1
