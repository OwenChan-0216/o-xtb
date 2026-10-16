#!/usr/bin/env bash
# vib-01: harmonic frequencies and thermochemistry of a relaxed minimum, and the
# effect of the temperature on H(T) and G(T).             [OxTB 0.1.0 / xTB 6.7.1, 8a0ad67]
set -euo pipefail
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../..")"

# primary run: 298.15 K, outputs kept under their natural names
oxtb input.xyz --gfn 2 --lvib --lvib-temp 298.15 --norestart > oxtb.log 2>&1

# the same analysis at 1000 K (namespaced so it does not overwrite the above)
oxtb input.xyz --gfn 2 --lvib --lvib-temp 1000 --namespace t1000 --norestart > vib1000.log 2>&1
