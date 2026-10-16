# 05-irc — integrate the IRC from the refined saddle

**Consumes:** `../04-ts/xtbts.xyz` -> `input.xyz`.
**Command:** `oxtb input.xyz --gfn 2 --lirc --lirc-method hpc --lirc-max-steps 60 --lirc-grad-tol 1e-5`
**Produces:** `irc_forward.xyz`, `irc_backward.xyz`, `irc_path.xyz`, `irc.log`.

| quantity | value |
|---|---|
| forward points | 52 (termination: gradient) |
| backward points | 44 (termination: energy_rise) |
| forward minimum | -52.373782362427 Eh (rmsd 8e-6 bohr) |
| backward minimum | -52.373778974769 Eh (rmsd 0.0009 bohr) |
| wall time | 10.3 s |

`--lirc-grad-tol 1e-5` is needed here: the step-04 saddle has gradient ~0, so the default
`--lirc-grad-tol 1e-3` stops the walk after one point.  Both endpoints are the degenerate pair of
benzoic-acid dimer minima of step 00.  (As in `irc-01`/`irc-02`, the transition vector's dominant
component sits on the symmetry-related proton whose index round-off picks; this release names atom
10, which is why the forward/backward labels are the opposite way round to the pre-refresh
edition.)
