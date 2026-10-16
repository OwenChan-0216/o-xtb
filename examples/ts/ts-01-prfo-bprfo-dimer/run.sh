#!/usr/bin/env bash
# ts-01: one 30-atom system, three saddle searches, and the shipped-default
# behaviour of each.  PRFO converges straight from the delivered TS guess;
# B-PRFO and the dimer need the guess displaced 0.15 A along the transfer
# coordinate.                                             [OxTB 0.1.0 / xTB 6.7.1, 8a0ad67]
set -uo pipefail
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../..")"

# 1. PRFO from the TS guess exactly as delivered (the guess is the P-RFO saddle).
oxtb input.xyz --gfn 2 --lts --lts-method prfo --lts-level normal --lts-max-steps 60 \
    --namespace prfo --norestart > prfo.log 2>&1
echo "prfo exit=$?"

# 2. B-PRFO from the same guess with shipped defaults: bounded, does not converge.
oxtb input.xyz --gfn 2 --lts --lts-method bprfo --lts-level normal --lts-max-steps 30 \
    --namespace bprfo-default --norestart > bprfo-default.log 2>&1
echo "bprfo-default exit=$?"

# 3. B-PRFO from the guess displaced 0.15 A along the transfer coordinate: converges.
oxtb input-displaced.xyz --gfn 2 --lts --lts-method bprfo --lts-level normal --lts-max-steps 150 \
    --namespace bprfo --norestart > bprfo.log 2>&1
echo "bprfo exit=$?"

# 4. Dimer from the same guess with shipped defaults: bounded, aborts (SCF failure).
oxtb input.xyz --gfn 2 --lts --lts-method dimer --lts-level normal --lts-max-steps 120 \
    --namespace dimer-default --norestart > dimer-default.log 2>&1
echo "dimer-default exit=$?"

# 5. Dimer from the displaced guess with the tuned separation and initial axis: converges.
oxtb input-displaced.xyz --gfn 2 --lts --lts-method dimer --lts-level normal --lts-max-steps 150 \
    --lts-delta 0.1 --lts-ninit force --lts-rot-max-iter 30 \
    --namespace dimer --norestart > dimer.log 2>&1
echo "dimer exit=$?"

# The primary transcript is the PRFO run; the others are kept next to it.
cat prfo.log > oxtb.log
