#!/usr/bin/env bash
# Relaxed 2D scan of the two proton-transfer distances of the benzoic acid
# dimer: a concerted-transfer valley with a stepwise ridge.   [OxTB 0.1.0 / xTB 6.7.1, 8a0ad67]
set -euo pipefail
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../..")"
oxtb input.xyz --gfn 2 --lscan --lscan-ndim 2 \
    --lscan-coord  distance --lscan-atoms  9,10  --lscan-step  0.125 --lscan-nstep  8 \
    --lscan-coord2 distance --lscan-atoms2 24,25 --lscan-step2 0.125 --lscan-nstep2 8 \
    --lscan-level normal --lscan-max-steps 150 --norestart > oxtb.log 2>&1
