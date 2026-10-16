#!/usr/bin/env bash
# chain step 05: integrate the IRC both ways from the step-04 saddle (hpc).
# The refined saddle has gradient ~0, so the default --lirc-grad-tol 1e-3 would
# stop after one point; loosen it to 1e-5.                 [OxTB 0.1.0 / xTB 6.7.1, 8a0ad67]
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f ../../../..)"
cp ../04-ts/xtbts.xyz input.xyz
oxtb input.xyz --gfn 2 --lirc --lirc-method hpc --lirc-max-steps 60 --lirc-grad-tol 1e-5 \
    --norestart > oxtb.log 2>&1
