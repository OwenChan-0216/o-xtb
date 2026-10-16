#!/usr/bin/env bash
# The same geometry with the model (Lindh-D2) Hessian and with the numerical
# Hessian: a cheap approximation versus the real frequencies.  [OxTB 0.1.0 / xTB 6.7.1, 8a0ad67]
#
# The model run goes first; its two comparison files are renamed so that the
# natural output names (hessian, vibspectrum, ...) belong to the numerical run.
set -euo pipefail
export OMP_NUM_THREADS=1
export XTBPATH="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../..")"
oxtb input.xyz --gfn 2 --lvib --lvib-hessian model --norestart > oxtb-model.log 2>&1
mv -f hessian hessian.model
mv -f vibspectrum vibspectrum.model
rm -f vib_normal_modes g98.out compliance.dat
oxtb input.xyz --gfn 2 --lvib --lvib-hessian numerical --norestart > oxtb-numerical.log 2>&1
