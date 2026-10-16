#!/usr/bin/env bash
# chain step 04: refine the step-03 saddle with P-RFO (a second, independent
# saddle search started from the dimer result).          [OxTB 0.1.0 / xTB 6.7.1, 8a0ad67]
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f ../../../..)"
cp ../03-dimer/xtbts.xyz input.xyz
oxtb input.xyz --gfn 2 --lts --lts-method prfo --lts-level normal --lts-max-steps 60 \
    --norestart > oxtb.log 2>&1
