#!/usr/bin/env bash
# chain step 01: CI-NEB band from the product to the saddle; the confirmed
# saddle candidate is written to xtbts.xyz.               [OxTB 0.1.0 / xTB 6.7.1, 8a0ad67]
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f ../../../..)"
cp ../00-endpoints/product.xyz input.xyz
oxtb input.xyz --gfn 2 --lts --lts-method cineb --lts-product ../00-endpoints/ts_guess.xyz \
    --lts-images 9 --lts-level normal --lts-max-steps 200 --norestart > oxtb.log 2>&1
