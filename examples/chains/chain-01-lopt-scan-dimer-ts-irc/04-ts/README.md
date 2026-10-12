# 04-ts — refine the saddle with P-RFO

**Consumes:** `../03-dimer/xtbts.xyz` -> `input.xyz`.
**Command:** `oxtb input.xyz --gfn 2 --lts --lts-method prfo --lts-level normal --lts-max-steps 60`
**Produces:** `xtbts.xyz` (consumed by step 05), `xtbts.log`.

| quantity | value |
|---|---|
| converged | T |
| final energy | **-52.363974789450 Eh** |
| saddle confirmation | 1 imaginary mode, **-1199.70 cm^-1**, first-order saddle |
| steps | 2 |
| wall time | 6.9 s |

Starting from the dimer result, P-RFO polishes the saddle by 6.8e-6 Eh in two steps - the two
independent searches agree to 7e-6 Eh.
