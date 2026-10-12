# 03-irc — IRC from the refined saddle

**Consumes:** `../02-refine/xtbts.xyz` -> `input.xyz`.
**Command:** `oxtb input.xyz --gfn 2 --lirc --lirc-method hpc --lirc-max-steps 80 --lirc-step 0.4 --lirc-grad-tol 1e-4`
**Produces:** `irc_forward.xyz`, `irc_backward.xyz`, `irc_path.xyz`, `irc.log`.

| quantity | value |
|---|---|
| forward points | 13 (termination: gradient) |
| backward points | 51 (termination: energy_rise) |
| forward minimum | -56.839109784760 Eh (a pre-reactive complex, rmsd 0.062 bohr) |
| backward minimum | -56.913763098229 Eh (the product, rmsd 0.006 bohr) |
| wall time | 11.9 s |

`--lirc-step 0.4 --lirc-grad-tol 1e-4` are needed because the -309 cm^-1 mode is soft: the default
`--lirc-step 0.1 --lirc-grad-tol 1e-3` stops the walk after one point.
