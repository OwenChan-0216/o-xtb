#!/bin/bash
# Robust M2 validation batch: no single failing point may abort the script.
cd /tmp/m2-exp || exit 0
export XTBPATH=/home/owenchan/work_path/coding/fortran/xtb
XT=/tmp/xtb-land/build/xtb
RUNS="${RUNS:-all}"

run() {
  local name="$1"; shift
  echo ">>> start $name : $*"
  "$XT" "$@" > "b_${name}.log" 2>&1
  local st=$?
  echo "<<< end   $name exit=$st"
}

common_dce="--gfn2 --lscan --lscan-coord dihedral --lscan-atoms 3,1,2,4 --norestart"

# 1) hysteresis at three convergence levels on the SAME grid (step 24 deg, nstep 5)
for lvl in superloose tight; do
  run "hyst_$lvl" dceopt.xtbopt.xyz $common_dce --lscan-step 24 --lscan-nstep 5 \
      --lscan-level "$lvl" --namespace "h$lvl"
done

# 2) constraint force constant sweep including the xtb default 0.05
for fc in 0.05 0.2 5.0; do
  run "fc_$fc" dceopt.xtbopt.xyz $common_dce --lscan-step 24 --lscan-nstep 5 \
      --lscan-oneway --lscan-fc "$fc" --namespace "fc2_$fc"
done

# 3) failure probes: negative step (targets beyond -180), very large step, cis start
run "wrap" dceopt.xtbopt.xyz $common_dce --lscan-step -24 --lscan-nstep 5 \
    --lscan-oneway --lscan-fc 0.05 --namespace wrap
run "bigstep" dceopt.xtbopt.xyz $common_dce --lscan-step 60 --lscan-nstep 4 \
    --lscan-oneway --lscan-fc 0.05 --namespace bigstep
run "cis" dce_cis.xyz $common_dce --lscan-step -24 --lscan-nstep 5 \
    --lscan-oneway --lscan-fc 0.05 --namespace cisx
run "cis_stiff" dce_cis.xyz $common_dce --lscan-step -24 --lscan-nstep 5 \
    --lscan-oneway --lscan-fc 0.5 --namespace cisx05
echo "BATCH COMPLETE"
