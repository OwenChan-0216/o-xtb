#!/usr/bin/env bash
# chain step 02: relaxed 1D scan of the O9-H10 distance, starting from the step-01
# minimum; the profile maximum is the transfer barrier.  [OxTB 0.1.0 / xTB 6.7.1, c712f9e]
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f ../../../..)"
cp ../01-lopt/xtbopt.xyz input.xyz
oxtb input.xyz --gfn 2 --lscan --lscan-coord distance --lscan-atoms 9,10 \
    --lscan-step 0.05 --lscan-nstep 25 --lscan-level normal --lscan-max-steps 150 \
    --norestart > oxtb.log 2>&1
