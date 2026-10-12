# 02-refine — refine the band's saddle candidate with P-RFO

**Consumes:** `../01-band/xtbts.xyz` -> `input.xyz`.
**Command:** `oxtb input.xyz --gfn 2 --lts --lts-method prfo --lts-level normal --lts-max-steps 80`
**Produces:** `xtbts.xyz` (consumed by step 03), `xtbts.log`.

| quantity | value |
|---|---|
| converged | T |
| final energy | **-56.834192216439 Eh** |
| saddle confirmation | 1 imaginary mode, **-308.92 cm^-1** |
| steps | 3 |
| wall time | 16.4 s |

**This step is required.**  The raw band candidate (-56.834307, imaginary mode -360.45 cm^-1) is
**not** a usable transition state: an IRC started from it returns to the product in *both*
directions.  P-RFO moves it 1.1e-4 Eh onto the true saddle, whose imaginary mode is the reaction
coordinate (-308.92 cm^-1, matching the delivered `ts_guess.xyz` at -308.68 cm^-1).
