# 02-lscan — scan the reaction coordinate

**Consumes:** `../01-lopt/xtbopt.xyz` -> `input.xyz`.
**Command:** `oxtb input.xyz --gfn 2 --lscan --lscan-coord distance --lscan-atoms 9,10 --lscan-step 0.05 --lscan-nstep 25 --lscan-level normal --lscan-max-steps 150`
**Produces:** `xtbscan.log` (51 frames of the O9-H10 distance, 1.01 -> 2.26 A and back).

| quantity | value |
|---|---|
| frames | 51 (bidirectional, 0 failed points) |
| profile minimum | -52.373772 Eh (O9-H10 = 1.01 A) |
| profile maximum | **-52.363916 Eh at O9-H10 = 1.25 A** |
| barrier | **6.18 kcal/mol** |
| largest hysteresis jump | 3.56e-3 Eh |
| wall time | 22.5 s |

The maximum frame is the transfer saddle; step 03 uses the delivered `ts_guess.xyz` instead, but the
scan is the honest way to *see* the barrier before searching for the saddle.
