#!/usr/bin/env bash
# chain step 03: dimer saddple search from the TS guess, displaced 0.15 A along
# the transfer coordinate (the dimer needs a non-stationary start).
#                                                          [OxTB 0.1.0 / xTB 6.7.1, 8a0ad67]
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f ../../../..)"
python3 ../00-structure/displace.py ../00-structure/ts_guess.xyz input.xyz
oxtb input.xyz --gfn 2 --lts --lts-method dimer --lts-level normal --lts-max-steps 150 \
    --lts-delta 0.1 --lts-ninit force --lts-rot-max-iter 30 --norestart > oxtb.log 2>&1
