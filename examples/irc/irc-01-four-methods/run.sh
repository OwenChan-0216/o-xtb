#!/usr/bin/env bash
# irc-01: one transition state integrated by all four IRC methods (hpc, lqa,
# eulerpc, gs); the default method keeps its natural irc_forward/backward/log.
#                                                          [OxTB 0.1.0 / xTB 6.7.1, c712f9e]
set -uo pipefail
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../..")"

# default method: hpc, outputs kept under their natural names
oxtb input.xyz --gfn 2 --lirc --lirc-method hpc --lirc-max-steps 40 --norestart > oxtb.log 2>&1
echo "hpc exit=$?"

for m in lqa eulerpc gs; do
    oxtb input.xyz --gfn 2 --lirc --lirc-method "$m" --lirc-max-steps 40 \
        --namespace "$m" --norestart > "$m.log" 2>&1
    echo "$m exit=$?"
done
