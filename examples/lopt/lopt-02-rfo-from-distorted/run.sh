#!/usr/bin/env bash
# The same distorted geometry with the RFO engine and the model (Lindh-D2)
# Hessian: fewer steps than L-BFGS and a lower final energy.  [OxTB 0.1.0 / xTB 6.7.1, 8a0ad67]
set -euo pipefail
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../..")"
oxtb input.xyz --gfn 2 --lopt --lopt-engine rfo --lopt-hessian model \
    --lopt-level normal --lopt-max-steps 300 --norestart > oxtb.log 2>&1
