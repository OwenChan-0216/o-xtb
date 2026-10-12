#!/usr/bin/env bash
# irc-02: the direction convention of the IRC: default (both directions),
# --lirc-oneway (forward only) and --lirc-swap (the two directions exchanged).
#                                                          [OxTB 0.1.0 / xTB 6.7.1, c712f9e]
set -euo pipefail
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../..")"

# default: both directions
oxtb input.xyz --gfn 2 --lirc --lirc-method hpc --lirc-max-steps 40 --norestart > oxtb.log 2>&1

# forward direction only (no backward integration)
oxtb input.xyz --gfn 2 --lirc --lirc-method hpc --lirc-oneway --lirc-max-steps 40 \
    --namespace oneway --norestart > oneway.log 2>&1

# the two directions exchanged
oxtb input.xyz --gfn 2 --lirc --lirc-method hpc --lirc-swap --lirc-max-steps 40 \
    --namespace swap --norestart > swap.log 2>&1
