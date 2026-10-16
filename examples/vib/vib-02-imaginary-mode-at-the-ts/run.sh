#!/usr/bin/env bash
# vib-02: harmonic analysis of the optimised saddle: the single imaginary mode,
# the imaginary-mode displacement, and the "not a minimum" flags.
#                                                          [OxTB 0.1.0 / xTB 6.7.1, 8a0ad67]
set -uo pipefail
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../..")"

oxtb input.xyz --gfn 2 --lvib --lvib-temp 298.15 --norestart > oxtb.log 2>&1
echo "lvib exit=$?"
