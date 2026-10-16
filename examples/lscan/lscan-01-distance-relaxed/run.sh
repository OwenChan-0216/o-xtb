#!/usr/bin/env bash
# Bidirectional relaxed 1D distance scan of the forming C9-C28 bond of the
# Diels-Alder adduct, with the forward/reverse hysteresis report.  [OxTB 0.1.0 / xTB 6.7.1, 8a0ad67]
set -euo pipefail
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../..")"
oxtb input.xyz --gfn 2 --lscan --lscan-coord distance --lscan-atoms 7,28 \
    --lscan-step 0.1 --lscan-nstep 17 --lscan-level normal \
    --lscan-max-steps 150 --norestart > oxtb.log 2>&1
