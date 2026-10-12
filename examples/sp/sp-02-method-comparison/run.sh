#!/usr/bin/env bash
# The same dimer at four levels of theory (--gfn 0, 1, 2 and ff): compare the
# four single-point energies.                                 [OxTB 0.1.0 / xTB 6.7.1, c712f9e]
set -euo pipefail
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../..")"
oxtb input.xyz --gfn 0  --sp --norestart > oxtb-gfn0.log  2>&1
oxtb input.xyz --gfn 1  --sp --norestart > oxtb-gfn1.log  2>&1
oxtb input.xyz --gfn 2  --sp --norestart > oxtb-gfn2.log  2>&1
oxtb input.xyz --gfn ff --sp --norestart > oxtb-gfn-ff.log 2>&1
