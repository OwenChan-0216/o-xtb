# 01-lopt — relax the starting structure

**Consumes:** `../00-structure/reactant.xyz` -> `input.xyz`.
**Command:** `oxtb input.xyz --gfn 2 --lopt --lopt-engine lbfgs --lopt-level normal --lopt-max-steps 300`
**Produces:** `xtbopt.xyz` (consumed by step 02), `xtbopt.log`.

| quantity | value |
|---|---|
| converged | T |
| final energy | **-52.373771818978 Eh** |
| steps | 1 (the delivered structure is already a minimum) |
| wall time | 0.03 s |
