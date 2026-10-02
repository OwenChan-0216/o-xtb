#!/bin/bash
# $1=outdir $2=method $3=extra args...
set -u
export OMP_NUM_THREADS=1
export XTBPATH=/home/owenchan/work_path/coding/fortran/xtb
XTB=/tmp/xtb-land/build/xtb
D="$1"; METHOD="$2"; shift 2
mkdir -p "$D"
$XTB item0-gs-e2e/t0.xtbts.xyz --gfn 2 --lirc --lirc-method "$METHOD" --norestart --namespace m "$@" > "$D/out" 2>&1
echo "$D exit=$?"
mv m.irc_forward.xyz m.irc_backward.xyz m.irc_path.xyz m.irc.log "$D/" 2>/dev/null
