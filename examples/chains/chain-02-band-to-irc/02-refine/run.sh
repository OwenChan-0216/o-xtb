#!/usr/bin/env bash
# chain step 02: refine the saddle candidate the band reported with P-RFO.
# The raw band candidate is not a usable transition state (see the README), so
# this step is required before the IRC.                   [OxTB 0.1.0 / xTB 6.7.1, c712f9e]
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f ../../../..)"
cp ../01-band/xtbts.xyz input.xyz
oxtb input.xyz --gfn 2 --lts --lts-method prfo --lts-level normal --lts-max-steps 80 \
    --norestart > oxtb.log 2>&1
