# 03-dimer — dimer saddle search from the TS guess

**Consumes:** `../00-structure/ts_guess.xyz`, displaced 0.15 A along the transfer coordinate by
`../00-structure/displace.py` -> `input.xyz`.
**Command:** `oxtb input.xyz --gfn 2 --lts --lts-method dimer --lts-level normal --lts-max-steps 150 --lts-delta 0.1 --lts-ninit force --lts-rot-max-iter 30`
**Produces:** `xtbts.xyz` (consumed by step 04), `xtbts.log`.

| quantity | value |
|---|---|
| converged | T |
| final energy | **-52.363967980984 Eh** |
| saddle confirmation | 1 imaginary mode, **-1208.09 cm^-1**, first-order saddle |
| steps | 58 |
| wall time | 5.1 s |

The 0.15 A displacement is **required**: from the exact guess the dimer drifts to a higher-order
saddle (`examples/ts/ts-01-prfo-bprfo-dimer` records that pair of runs).
