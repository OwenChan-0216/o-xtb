# 05-irc — integrate the IRC from the refined saddle

**Consumes:** `../04-ts/xtbts.xyz` -> `input.xyz`.
**Command:** `oxtb input.xyz --gfn 2 --lirc --lirc-method hpc --lirc-max-steps 60 --lirc-grad-tol 1e-5`
**Produces:** `irc_forward.xyz`, `irc_backward.xyz`, `irc_path.xyz`, `irc.log`.

| quantity | value |
|---|---|
| forward points | 44 (termination: energy_rise) |
| backward points | 50 (termination: gradient) |
| forward minimum | -52.373778976413 Eh (rmsd 0.0009 bohr) |
| backward minimum | -52.373782339853 Eh (rmsd 9e-6 bohr) |
| wall time | 11.3 s |

`--lirc-grad-tol 1e-5` is needed here: the step-04 saddle has gradient ~0, so the default
`--lirc-grad-tol 1e-3` stops the walk after one point.  Both endpoints are the degenerate pair of
benzoic-acid dimer minima of step 00.
