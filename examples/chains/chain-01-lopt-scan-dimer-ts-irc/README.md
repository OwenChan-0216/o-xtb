# chain-01 — lopt -> lscan -> dimer -> ts -> irc on one structure

**System.** The **30-atom** benzoic-acid dimer (`examples/structures/benzoic_acid_dimer`): a
symmetric concerted double proton transfer.  One structure is carried through five tasks in
sequence; each numbered folder is a complete little case (input, `run.sh`, `oxtb.log`, outputs,
`README.md`).

**What it shows.**  The full PES workflow on a real system: relax, map the reaction coordinate,
locate the saddle with the dimer method, refine it with P-RFO, and integrate the IRC both ways.  It
also shows which file flows into which task - every step consumes the previous step's output.

## Step table

| step | folder | consumes | command (see the step README for the full line) | produces | headline number | wall time |
|---|---|---|---|---|---|---|
| 00 | `00-structure/` | - | - | `reactant.xyz`, `ts_guess.xyz` | start -52.373771244067 Eh | - |
| 01 | `01-lopt/` | `../00-structure/reactant.xyz` | `--lopt --lopt-engine lbfgs --lopt-level normal` | `xtbopt.xyz` | **-52.373771818978 Eh** (1 step) | 0.05 s |
| 02 | `02-lscan/` | `../01-lopt/xtbopt.xyz` | `--lscan --lscan-coord distance --lscan-atoms 9,10` | `xtbscan.log` | **barrier 6.18 kcal/mol** at O9-H10 = 1.25 A | 22.5 s |
| 03 | `03-dimer/` | `../00-structure/ts_guess.xyz` (displaced 0.15 A) | `--lts --lts-method dimer --lts-delta 0.1 --lts-ninit force` | `xtbts.xyz` | **-52.363967980984 Eh**, 1 imaginary (-1208.09 cm^-1) | 8.8 s |
| 04 | `04-ts/` | `../03-dimer/xtbts.xyz` | `--lts --lts-method prfo --lts-level normal` | `xtbts.xyz` | **-52.363974789450 Eh**, 1 imaginary (-1199.70 cm^-1) | 6.9 s |
| 05 | `05-irc/` | `../04-ts/xtbts.xyz` | `--lirc --lirc-method hpc --lirc-grad-tol 1e-5` | `irc_forward/backward/path.xyz`, `irc.log` | 44 / 50 points, both endpoints are the degenerate minima | 11.3 s |

Total wall time ~50 s at `OMP_NUM_THREADS=1`.

## What flows into what

```
00-structure/reactant.xyz
        |
        v   (01-lopt)
01-lopt/xtbopt.xyz   -52.373771818978 Eh  (the relaxed minimum)
        |
        v   (02-lscan)   scan the O9-H10 distance
02-lscan/xtbscan.log  barrier 6.18 kcal/mol at d(O9-H10)=1.25 A
                              (the delivered TS guess is used for step 03 instead)

00-structure/ts_guess.xyz --displace.py--> 03-dimer/input.xyz
        |
        v   (03-dimer)
03-dimer/xtbts.xyz   -52.363967980984 Eh  (first-order saddle, dimer)
        |
        v   (04-ts, P-RFO)
04-ts/xtbts.xyz      -52.363974789450 Eh  (refined first-order saddle)
        |
        v   (05-irc, hpc)
05-irc/irc_forward.xyz  -> minimum -52.373778976 Eh
05-irc/irc_backward.xyz -> minimum -52.373782340 Eh
```

Each step's `run.sh` copies the file it consumes into its own `input.xyz` first (so every folder is
self-contained and re-runnable), then runs the task on it.

## The energy profile of the chain

| point | energy / Eh | note |
|---|---|---|
| step 00 / 01 minimum | -52.373771818978 | the relaxed starting structure |
| step 02 scan maximum | **-52.363916131491** | the barrier peak, +6.18 kcal/mol |
| step 03 dimer saddle | -52.363967980984 | 4.9e-5 Eh above the scan maximum |
| step 04 P-RFO saddle | **-52.363974789450** | the two saddle searches agree to 6.8e-6 Eh |
| step 05 IRC minima | -52.373778976 / -52.373782340 | both back in the step-01 well (degenerate reaction) |

The dimer and P-RFO saddles agree to 6.8e-6 Eh and both confirm a single imaginary mode; the scan
maximum is 4.9e-5 Eh above them because it is a constrained point, not a relaxed saddle.

## Honesty notes (bounds and tuning actually used)

* **Every run is bounded** by `--lopt-max-steps` / `--lscan-max-steps` / `--lts-max-steps` /
  `--lirc-max-steps`; none needed the bound to finish - each converged on its own criterion (the
  IRC forward half stopped on `energy_rise`, the backward half on `gradient`).
* **Step 03 needs a displaced start.**  `displace.py` moves the two transferring protons 0.15 A
  along the transfer coordinate.  From the exact guess the dimer drifts to a higher-order saddle
  (see `examples/ts/ts-01-prfo-bprfo-dimer`); that pair of runs is documented there.
* **Step 05 needs a looser gradient threshold.**  The step-04 saddle has gradient ~0, so the default
  `--lirc-grad-tol 1e-3` would terminate the IRC after one point; `1e-5` lets it walk to the minima.
* The scan uses the suite's own default force constant (`--lscan-fc 0.5`, 10x the legacy xtb value);
  the barrier is insensitive to it at the `normal` level.
