#!/usr/bin/env bash
# ts-02: the chain-of-states band family on the 33-atom Diels-Alder system.
# The full reactant -> product band cannot converge (the two fragments start
# 12.6 A apart and coplanar, so the interpolation walks the images through the
# anthracene); the working band runs on the compact product -> TS leg and on a
# constructed pre-reactive complex.                        [OxTB 0.1.0 / xTB 6.7.1, 8a0ad67]
set -uo pipefail
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../..")"

# 1. NEB on the product -> TS leg (the band that works): barrier = TS - product.
oxtb product.xyz --gfn 2 --lts --lts-method neb --lts-product ts_guess.xyz --lts-images 9 \
    --lts-level normal --lts-max-steps 200 --namespace local-neb --norestart > neb-local.log 2>&1
echo "neb-local exit=$?"

# 2. CI-NEB on the same leg.
oxtb product.xyz --gfn 2 --lts --lts-method cineb --lts-product ts_guess.xyz --lts-images 9 \
    --lts-level normal --lts-max-steps 200 --namespace local-cineb --norestart > cineb-local.log 2>&1
echo "cineb-local exit=$?"

# 3. String on the same leg (bounded; does not confirm a saddle - honest record).
oxtb product.xyz --gfn 2 --lts --lts-method string --lts-product ts_guess.xyz \
    --lts-level normal --lts-max-steps 300 --namespace local-string --norestart > string-local.log 2>&1
echo "string-local exit=$?"

# 4. The pinned full reaction, reactant -> product: bounded, does not converge.
oxtb reactant.xyz --gfn 2 --lts --lts-method neb --lts-product product.xyz --lts-images 9 \
    --lts-level normal --lts-max-steps 100 --namespace full-neb --norestart > neb-full.log 2>&1
echo "neb-full exit=$?"

# 5. The chemically correct band: pre-reactive complex -> product (monotone, no barrier).
oxtb precomplex.xyz --gfn 2 --lts --lts-method neb --lts-product product.xyz --lts-images 11 \
    --lts-level normal --lts-max-steps 300 --namespace precomplex-neb --norestart > neb-precomplex.log 2>&1
echo "neb-precomplex exit=$?"

# 6. Characterise the pre-complex: a plain minimisation shows it is only a
#    starting point, not a minimum (it falls back to the separated-reactant well).
oxtb precomplex.xyz --gfn 2 --lopt --lopt-engine lbfgs --lopt-level loose --lopt-max-steps 50 \
    --namespace precomplex-opt --norestart > precomplex-opt.log 2>&1
echo "precomplex-opt exit=$?"

# 7. The same pinned full band with 15 images (NEB, CI-NEB and no-align NEB),
#    for the pathological-barrier numbers quoted in the README.
oxtb reactant.xyz --gfn 2 --lts --lts-method neb --lts-product product.xyz --lts-images 15 \
    --lts-level normal --lts-max-steps 300 --namespace full-neb15 --norestart > neb-full15.log 2>&1
echo "neb-full15 exit=$?"
oxtb reactant.xyz --gfn 2 --lts --lts-method cineb --lts-product product.xyz --lts-images 15 \
    --lts-level normal --lts-max-steps 300 --namespace full-cineb15 --norestart > cineb-full15.log 2>&1
echo "cineb-full15 exit=$?"
oxtb reactant.xyz --gfn 2 --lts --lts-method neb --lts-product product.xyz --lts-images 15 \
    --lts-no-align --lts-level normal --lts-max-steps 300 --namespace full-neb15-na --norestart > neb-full15-noalign.log 2>&1
echo "neb-full15-na exit=$?"

# 8. The remaining two band methods on the pinned full reaction (gsm, AutoNEB):
#    both abort; kept as the honest record.
oxtb reactant.xyz --gfn 2 --lts --lts-method gsm --lts-product product.xyz \
    --lts-level normal --lts-max-steps 300 --namespace full-gsm --norestart > gsm-full.log 2>&1
echo "gsm-full exit=$?"
oxtb reactant.xyz --gfn 2 --lts --lts-method autoneb --lts-product product.xyz \
    --lts-level normal --lts-max-steps 300 --namespace full-autoneb --norestart > autoneb-full.log 2>&1
echo "autoneb-full exit=$?"

cat neb-local.log > oxtb.log
