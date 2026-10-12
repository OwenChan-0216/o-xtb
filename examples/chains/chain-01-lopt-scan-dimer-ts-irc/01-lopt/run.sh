#!/usr/bin/env bash
# chain step 01: relax the starting structure with the suite minimiser (L-BFGS).
#                                                          [OxTB 0.1.0 / xTB 6.7.1, c712f9e]
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f ../../../..)"
cp ../00-structure/reactant.xyz input.xyz
oxtb input.xyz --gfn 2 --lopt --lopt-engine lbfgs --lopt-level normal \
    --lopt-max-steps 300 --norestart > oxtb.log 2>&1
