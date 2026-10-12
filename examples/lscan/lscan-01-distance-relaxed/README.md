# lscan-01 — bidirectional relaxed distance scan of a forming bond

**System.** `anthracene_maleic_anhydride/product.xyz` from `examples/structures` — the
9,10-cycloadduct of anthracene + maleic anhydride, **33 atoms**. The scanned coordinate is the
forming bond **C9-C28** (anthracene C9 = atom **7**, the maleic anhydride vinyl carbon = atom
**28**), exactly as `examples/structures/anthracene_maleic_anhydride/scan_coordinate.md` defines
it.

**What it shows.** A relaxed 1D scan in both directions (the default). Each point relaxes the rest
of the molecule under a harmonic constraint on the C9-C28 distance; the task then reports the
dead-ended profile, the largest step-to-step jump, and the **hysteresis** between the forward and
the reverse branch — the built-in convergence self-check.

**Command** (`run.sh`):

```bash
export OMP_NUM_THREADS=1
export XTBPATH=<repository root>
oxtb input.xyz --gfn 2 --lscan --lscan-coord distance --lscan-atoms 7,28 \
    --lscan-step 0.1 --lscan-nstep 17 --lscan-level normal --lscan-max-steps 150 --norestart
```

This is the validated command from the structures lane (the only addition is `--norestart`).

**Observed result** (`oxtb.log`, forward branch):

| d(C9-C28) / A | energy / Eh | | d(C9-C28) / A | energy / Eh |
|---|---|---|---|---|
| 1.5548 | -56.913775059 | | 2.4548 | -56.843990053 |
| 1.6548 | -56.911274314 | | 2.5548 | -56.839495062 |
| 1.7548 | -56.904696708 | | 2.6548 | -56.835837981 |
| 1.8548 | -56.895368343 | | 2.7548 | -56.832929915 |
| 1.9548 | -56.884810490 | | 2.8548 | -56.830547387 |
| 2.0548 | -56.874572020 | | 2.9548 | -56.828476732 |
| 2.1548 | -56.865262064 | | 3.0548 | -56.826757858 |
| 2.2548 | -56.856764667 | | 3.1548 | -56.825160577 |
| 2.3548 | -56.849646992 | | 3.2548 | -56.823903186 |

| quantity | value |
|---|---|
| frames written | 35 (18 forward + 17 reverse), 0 failed points |
| profile | **monotone rising**, -56.913775 Eh -> -56.823903 Eh |
| energy span over the window | **0.089872 Eh = 56.4 kcal/mol** |
| hysteresis (max forward-vs-reverse gap) | **1.713341e-04 Eh**, at d = 1.95478849 A |
| largest jump between points | 1.076e-02 Eh |
| line of interest | the `hysteresis: max`/`Eh` gap line printed near the end of `oxtb.log` |
| wall time | **29.8 s** |

There is **no barrier** on this coordinate: the scan runs the reverse of the C-C bond *formation*,
so the energy rises monotonically as the bond is pulled apart (56.4 kcal/mol over 1.7 A). The
"profile" is therefore a ramp and the only reaction-path quantity the task can certify is the
hysteresis. `1.7e-04 Eh` is the same order as the documented convergence artefact (measured
1.25e-5 Eh at `superloose` shrinking to 7.5e-7 Eh at `vtight`); tighten with
`--lscan-level vtight` if a smaller number is needed. Beyond d ~ 3.35 A the profile is no longer
smooth (the *other* forming bond, C10-C29, breaks), which is why the range stops at 3.25 A.

**Reading the output files.** `oxtb.log` prints the per-point table
(`point / value / reached / drift / energy / residual / steps / conv`), the hysteresis report and
the frame count. `xtbscan.log` is the trajectory: one xmol frame per point, each preceded by a
comment line `energy: <Eh> xtb: 6.7.1 (<commit>) iter: <n>`, in forward-then-reverse order.

**Reproduce.**

```bash
cd examples/lscan/lscan-01-distance-relaxed
rm -f oxtb.log xtbscan.log xtbtopo.mol charges wbo xtbrestart
./run.sh
grep -E 'hysteresis|largest jump' oxtb.log
```

A clean re-run reproduces `xtbscan.log` **byte for byte** (sha256 `8ceca6fd…`).
