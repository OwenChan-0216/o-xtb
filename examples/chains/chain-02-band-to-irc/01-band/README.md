# 01-band — CI-NEB from the product to the saddle

**Consumes:** `../00-endpoints/product.xyz` -> `input.xyz`, `--lts-product ../00-endpoints/ts_guess.xyz`.
**Command:** `oxtb input.xyz --gfn 2 --lts --lts-method cineb --lts-product ../00-endpoints/ts_guess.xyz --lts-images 9 --lts-level normal --lts-max-steps 200`
**Produces:** `xtbts.xyz` (the confirmed saddle candidate, consumed by step 02), `path.xyz` (the band).

| quantity | value |
|---|---|
| converged | T |
| images | 9 (7 internal, 2 fixed endpoints) |
| highest image | 8, -56.834307439160 Eh |
| barrier (TS - product) | **49.87 kcal/mol** |
| saddle confirmation | 1 imaginary mode, -360.45 cm^-1 |
| wall time | 10.2 s |

Note: plain NEB/CI-NEB write the saddle candidate to `xtbts.xyz`; `path_ts_list.xyz` is written by
AutoNEB and the string method, not here.
