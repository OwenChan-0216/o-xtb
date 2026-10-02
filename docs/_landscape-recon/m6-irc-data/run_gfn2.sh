#!/bin/bash
# run one GFN2 IRC method/step; $1=step $2=method ; writes to exp6-crosscheck/gfn2/step$1/$2
set -u
export OMP_NUM_THREADS=1
export XTBPATH=/home/owenchan/work_path/coding/fortran/xtb
XTB=/tmp/xtb-land/build/xtb
STEP=$1; METHOD=$2
D="exp6-crosscheck/gfn2/step${STEP}/${METHOD}"
mkdir -p "$D"
TS="item0-gs-e2e/t0.xtbts.xyz"
$XTB "$TS" --gfn 2 --lirc --lirc-method "$METHOD" --lirc-step "$STEP" --norestart --namespace m > "$D/out" 2>&1
echo "step=$STEP method=$METHOD exit=$?"
grep -E "termination (forward|backward)|forward points|backward points|forward arc length|backward arc length|forward endpoint energy|backward endpoint energy|forward reached minimum|backward reached minimum|mean energy/gradient" "$D/out"
mv m.irc_forward.xyz m.irc_backward.xyz m.irc_path.xyz m.irc.log "$D/" 2>/dev/null
