# irc-01 — one transition state, four IRC integrations

**System.** The **30-atom** benzoic-acid dimer, the symmetric concerted double proton transfer
(`examples/structures/benzoic_acid_dimer`).  `input.xyz` is the delivered TS guess (-52.360890 Eh,
gradient 0.082 Eh/bohr, one imaginary mode; it is a guess, not a fully converged saddle, which is
why the default `--lirc-grad-tol` does not terminate the walk at the first point).  Starting from a
*fully optimised* saddle (gradient ~0) the same defaults stop after one point - use
`--lirc-grad-tol 1e-5` then.

**What it shows.**  All four IRC integrators (`hpc`, `lqa`, `eulerpc`, `gs`) walking from the same
saddle to the two symmetry-equivalent minima, with the step count, the endpoint energy and the
endpoint-to-minimum RMSD each one reports.  The two minima are degenerate (reactant and product are
the same species), so each integrator has to reach the *same* two wells by different routes.

**Command** (`run.sh`):

```bash
export OMP_NUM_THREADS=1
export XTBPATH=<repository root>
oxtb input.xyz --gfn 2 --lirc --lirc-method hpc     --lirc-max-steps 40   # -> oxtb.log, irc_forward/backward/log
oxtb input.xyz --gfn 2 --lirc --lirc-method lqa     --lirc-max-steps 40 --namespace lqa
oxtb input.xyz --gfn 2 --lirc --lirc-method eulerpc --lirc-max-steps 40 --namespace eulerpc
oxtb input.xyz --gfn 2 --lirc --lirc-method gs      --lirc-max-steps 40 --namespace gs
```

**Observed result.**  Both directions of every method stop on the gradient criterion (eulerpc on
`energy_rise`) well inside the 40-step budget:

| method | forward steps | backward steps | forward endpoint / Eh | backward endpoint / Eh | fwd rmsd to min / bohr | bwd rmsd to min / bohr | wall time |
|---|---|---|---|---|---|---|---|
| **hpc** (default) | 6 | 5 | -52.373672 | -52.373673 | 0.0056 | 0.0055 | 2.3 s |
| lqa | 6 | 5 | -52.373667 | -52.373662 | 0.0057 | 0.0056 | 1.8 s |
| eulerpc | 15 | 8 | -52.373370 | -52.373331 | 0.0068 | 0.0070 | 5.2 s |
| gs | 6 | 5 | -52.373721 | -52.373732 | 0.0046 | 0.0042 | 1.5 s |

Every method reports `forward reached minimum: T` and `backward reached minimum: T`.  The two
minima it points to are degenerate:

* forward minimum **-52.373772129 Eh** (rmsd to the forward endpoint 0.0056 bohr)
* backward minimum **-52.373773548 Eh** (rmsd to the backward endpoint 0.0055 bohr)

hpc, lqa and gs agree closely (6/5 steps, endpoints within 1e-4 Eh of each other); eulerpc takes a
different route (15/8 steps) and stops earlier because it uses a different corrector and triggers on
`energy_rise`, so its endpoints are 3e-4 Eh higher - still the same two minima.

The transition vector of this symmetric double proton transfer has equal-sized dominant components
on the two symmetry-related protons, so which of the two atoms the `phase component` line names (and
hence which half is called *forward*) is decided by round-off. This release names atom **10**, where
the pre-refresh release named atom **25**, so the *forward* and *backward* columns of the table
above carry the opposite labels to the earlier edition even though the two physical halves are the
same. `irc-02` shows the convention directly.

**How to read the output files.**

* `irc_forward.xyz`, `irc_backward.xyz` - the two half-paths as xyz frames (frame 1 the saddle).
* `irc_path.xyz` - the joined forward+backward path (the file to plot).
* `irc.log` - the short per-run summary: `termination forward/backward`, `forward points`,
  `backward points`, `forward/backward arc length`, `forward/backward endpoint energy`,
  `forward/backward reached minimum (rmsd ...)`.
* `oxtb.log` - the full hpc transcript; `lqa.log`, `eulerpc.log`, `gs.log` - the other three.
  The `lqa.*`, `eulerpc.*`, `gs.*` prefixes are the `--namespace` outputs of the other methods.
