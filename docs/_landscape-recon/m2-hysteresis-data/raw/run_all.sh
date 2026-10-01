#!/bin/bash
# Robust serial M2 validation batch.  OMP_NUM_THREADS=1: on this machine the
# OpenMP/OpenBLAS pool makes even a 16-argument scan ~340x slower at 8 threads
# (measured 44.1 s vs 0.13 s), so single thread is both faster and less noisy.
# No single failing point may abort the script.
cd /tmp/m2-exp || exit 0
export XTBPATH=/home/owenchan/work_path/coding/fortran/xtb
export OMP_NUM_THREADS=1
XT=/tmp/xtb-land/build/xtb
DCE=dceopt.xtbopt.xyz
H2O2=h2o2opt.xtbopt.xyz
BASE="--gfn2 --lscan --lscan-coord dihedral --lscan-atoms 3,1,2,4 --norestart"

run() {  # run <name> <input> <args...>
  local name="$1" inp="$2"; shift 2
  local t0=$(date +%s.%N)
  "$XT" "$inp" "$@" > "r_${name}.log" 2>&1
  local st=$?
  local t1=$(date +%s.%N)
  echo "RESULT $name exit=$st wall=$(echo "$t1-$t0"|bc) s"
}

# A) hysteresis, fine grid (12 deg, 11 forward points), bidirectional
for lvl in superloose loose normal tight vtight; do
  run "hyst12_$lvl" "$DCE" $BASE --lscan-step 12 --lscan-nstep 10 --lscan-level "$lvl" --namespace "h12$lvl"
done

# B) hysteresis, coarse grid (24 deg, 6 forward points), bidirectional
for lvl in superloose loose normal tight vtight; do
  run "hyst24_$lvl" "$DCE" $BASE --lscan-step 24 --lscan-nstep 5 --lscan-level "$lvl" --namespace "h24$lvl"
done

# C) constraint force constant sweep (one way, same grid)
for fc in 0.05 0.1 0.5 2.0 5.0 10.0; do
  run "fc_$fc" "$DCE" $BASE --lscan-step 24 --lscan-nstep 5 --lscan-oneway --lscan-fc "$fc" --namespace "f$fc"
done

# D) rigid vs relaxed / rigid reference (driver, fine grid)
run "rigid12" "$DCE" $BASE --lscan-step 12 --lscan-nstep 10 --lscan-oneway --lscan-mode rigid --namespace rigid12
run "rigid24" "$DCE" $BASE --lscan-step 24 --lscan-nstep 5 --lscan-oneway --lscan-mode rigid --namespace rigid24

# E) failure probes
run "wrap"    "$DCE" $BASE --lscan-step -24 --lscan-nstep 5 --lscan-oneway --lscan-fc 0.05 --namespace wrap
run "bigstep" "$DCE" $BASE --lscan-step 60 --lscan-nstep 4 --lscan-oneway --lscan-fc 0.05 --namespace bigstep
run "cis"     dce_cis.xyz $BASE --lscan-step -24 --lscan-nstep 5 --lscan-oneway --lscan-fc 0.05 --namespace cisx

# F) H2O2 consistency grids (dihedral 3-1-2-4), one way
H2BASE="--gfn2 --lscan --lscan-coord dihedral --lscan-atoms 3,1,2,4 --norestart"
for lvl in normal tight vtight; do
  run "h2o2_lscan_$lvl" "$H2O2" $H2BASE --lscan-step 15 --lscan-nstep 12 --lscan-oneway --lscan-fc 0.5 --lscan-level "$lvl" --namespace "h2l$lvl"
done
echo "ALL DONE"
