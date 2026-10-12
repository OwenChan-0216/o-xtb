#!/usr/bin/env bash
# chain step 03: IRC from the refined saddle (step 02's xtbts.xyz).  System 1 has
# a soft imaginary mode, so the arc-length step is raised and the gradient
# threshold loosened.                                     [OxTB 0.1.0 / xTB 6.7.1, c712f9e]
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f ../../../..)"
cp ../02-refine/xtbts.xyz input.xyz
oxtb input.xyz --gfn 2 --lirc --lirc-method hpc --lirc-max-steps 80 \
    --lirc-step 0.4 --lirc-grad-tol 1e-4 --norestart > oxtb.log 2>&1
