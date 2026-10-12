# ts-01 — three saddle searches on one system: PRFO, B-PRFO, dimer

**System.** The **30-atom** benzoic-acid dimer (`examples/structures/benzoic_acid_dimer`), a
symmetric concerted double proton transfer.  The two hydroxyl protons `H10` and `H25` hop between
`O9`/`O23` and `O24`/`O8`; the reaction is its own reverse, so the saddle is the cleanest possible
comparison of three independent saddle-search methods.

`input.xyz` is the delivered TS guess (O-H 1.17 A, H...O 1.48 A, one imaginary mode -715.9 cm^-1).
`input-displaced.xyz` is the same geometry with the two transferring protons moved **0.15 A** along
their transfer coordinate (`H10` toward `O23`, `H25` toward `O8`) - the perturbation that B-PRFO and
the dimer need (see below).

**What it shows.**  PRFO, B-PRFO and the dimer all locate the same first-order saddle when each is
given a usable starting point; their energies agree to 8e-6 Eh and their geometries to < 0.004 A.
It also shows, honestly, that B-PRFO and the dimer do **not** work from the exact stationary guess
with the shipped defaults - a method that needs tuning is a fact worth teaching, not hiding.

**Commands** (`run.sh`):

```bash
export OMP_NUM_THREADS=1
export XTBPATH=<repository root>
oxtb input.xyz           --gfn 2 --lts --lts-method prfo  --lts-level normal --lts-max-steps 60  --namespace prfo
oxtb input-displaced.xyz --gfn 2 --lts --lts-method bprfo --lts-level normal --lts-max-steps 150 --namespace bprfo
oxtb input-displaced.xyz --gfn 2 --lts --lts-method dimer --lts-level normal --lts-max-steps 150 \
     --lts-delta 0.1 --lts-ninit force --lts-rot-max-iter 30 --namespace dimer
# the shipped-default behaviour of the two methods that need the displacement:
oxtb input.xyz --gfn 2 --lts --lts-method bprfo --lts-level normal --lts-max-steps 30  --namespace bprfo-default
oxtb input.xyz --gfn 2 --lts --lts-method dimer --lts-level normal --lts-max-steps 120 --namespace dimer-default
```

**Observed results.**  `oxtb.log` is the PRFO transcript; `prfo.log`, `bprfo.log`, `dimer.log`,
`bprfo-default.log`, `dimer-default.log` are the five runs.  `prfo.xtbts.xyz`, `bprfo.xtbts.xyz`
and `dimer.xtbts.xyz` are the three optimised saddles; `*.xtbts.log` is the per-run confirmation.

| run | start | method | converged | final E / Eh | confirmation | steps | wall time |
|---|---|---|---|---|---|---|---|
| 1 | `input.xyz` | PRFO | **T** | **-52.363974790630** | 1 imaginary, **-1202.82 cm^-1** | 5 | 16.2 s |
| 2 | `input-displaced.xyz` | B-PRFO | **T** | **-52.363974790676** | 1 imaginary, **-1202.65 cm^-1** | 5 | 16.3 s |
| 3 | `input-displaced.xyz` | dimer | **T** | **-52.363967980984** | 1 imaginary, **-1208.09 cm^-1** | 58 | 8.6 s |
| 4 | `input.xyz` | B-PRFO (shipped defaults) | F | -52.353023 | 2 imaginary, -53.9 cm^-1 -> **higher-order saddle** | 30 | 88 s* |
| 5 | `input.xyz` | dimer (shipped defaults) | F | -52.041005 | 6 imaginary -> **higher-order saddle** | 120 | 24 s* |

\* The two aborted runs exit before the wall-time line is printed, so their times were measured
with `time` around the same command; every other number in this table is a line in the logs.

**Do the three methods agree?**  Yes.  The three converged saddles are found from slightly different
starts (`input.xyz` vs `input-displaced.xyz`) and their least-squares (unrotated) RMSD is

| pair | RMSD / A | max component / A |
|---|---|---|
| PRFO - B-PRFO | **0.0022** | 0.0035 |
| PRFO - dimer | **0.0039** | 0.0050 |
| B-PRFO - dimer | **0.0033** | 0.0059 |

The delivered guess is 0.118 A (RMSD) from the PRFO saddle.  These RMSDs are computed directly from
the three `*.xtbts.xyz` files in this folder (no rotation, no reordering); they are the geometry
agreement between the three methods, not a number the tasks print themselves.

**The sensitivity, stated plainly.**  Starting *exactly* at the stationary guess (gradient ~0) the
finite-difference curvature is ill-defined, and only PRFO converges: B-PRFO drifts onto a
higher-order saddle (2 imaginary modes) and never recovers within its budget, and the dimer does the
same (6 imaginary modes).  Both work after a 0.15 A displacement of the transfer coordinate; the
dimer additionally needs its separation raised above the naive value (`--lts-delta 0.1`, the default
is 0.01 bohr) and its initial axis taken from the force (`--lts-ninit force`).  B-PRFO also prints a
benign notice, `the downhill subspace has 15 negative curvature eigenvalue(s) ... lifted to hlow`,
which does not stop it converging here.

**How to read the output files.**

* `prfo.log` / `bprfo.log` / `dimer.log` - the full stdout+stderr: settings header, the per-step
  table (`iter energy gmax dmax trust`), the saddle confirmation, the engine counters and the wall
  time.  The lines to grep: `final energy:`, `saddle confirmation - imaginary modes:`,
  `most negative frequency:`, `steps:`, `landscape: converged`.
* `prfo.xtbts.log` / `bprfo.xtbts.log` / `dimer.xtbts.log` - the short per-run summary.
* `prfo.xtbts.xyz` etc. - the optimised saddle geometry (the file to feed to `--lvib` or `--lirc`).
* `bprfo-default.log` / `dimer-default.log` - the honest record of the shipped-default failures.

**One number per file (to grep).**  `grep "final energy" prfo.log` -> `-52.363974790630`;
`grep "most negative frequency" bprfo.log` -> `-1202.65 cm^-1`;
`grep "imaginary modes" dimer-default.log` -> `6`.
