# vib-02 — the imaginary mode of the optimised saddle

**System.** The **30-atom** benzoic-acid dimer saddle (`input.xyz` = the PRFO-optimised saddle from
`examples/ts/ts-01-prfo-bprfo-dimer/prfo.xtbts.xyz`, -52.363974790630 Eh, gradient 3.9e-06 Eh/bohr).
It is a genuine first-order saddle, not a guess.

**What it shows.**  What `--lvib` does on a non-minimum: the single imaginary mode comes out first
in the spectrum, the flat imaginary-mode displacement is written to `vib_normal_modes`, and the task
sets explicit **non-minimum flags** in the transcript.  It is the direct counterpart of
`examples/vib/vib-01-minimum-thermochemistry`, where the same code strikes none of these flags.

**Command** (`run.sh`):

```bash
export OMP_NUM_THREADS=1
export XTBPATH=<repository root>
oxtb input.xyz --gfn 2 --lvib --lvib-temp 298.15 --norestart
```

**Observed result** (from `oxtb.log` and `vibspectrum`):

| quantity | value |
|---|---|
| imaginary mode | **mode 7 = -1199.65 cm^-1** (the proton-transfer mode) |
| significant imaginary frequencies | **1** (`found 1 significant imaginary frequency`) |
| mode count | 84 internal, 6 projected zero modes |
| zero point energy | 0.216709 Eh |
| total enthalpy H(T) | -52.130666 Eh |
| total free energy G(T) | -52.189615 Eh |
| exit status | **0** (the run completes; the flags are warnings, not an abort) |
| wall time | 1.17 s |

**The non-minimum flags the task prints** (all in `oxtb.log`):

```
 found            1  significant imaginary frequency
 landscape task terminated: frequency analysis completed with imaginary modes
[WARNING] Runtime exception occurred
-1- landscape_vib: the Hessian has 1 imaginary mode(s): the geometry is not a minimum
```

So the thermochemistry (ZPE/H(T)/G(T)) is still computed, but it is **labelled as not physically
meaningful** - a saddle has no vibrational partition function.  The point of the case: read the flag
before you quote the numbers.  For comparison, the saddle confirmation of the search itself printed
`most negative frequency: -1202.82 cm^-1`; the 3 cm^-1 offset from `-1199.65` is the known
difference between the confirmation Hessian and the `--lvib` projection convention (the two
projectors define the same rigid motions in different metrics).

**How to read the output files.**

* `vibspectrum` - mode 7 is the imaginary mode; the six rows before it are the projected rigid
  motions (0.00 cm^-1).
* `vib_normal_modes` - the per-mode Cartesian displacements; the block of mode 7 (`7  <atom> ...`
  rows) is the imaginary-mode direction, i.e. the collective proton-transfer motion.
* `oxtb.log` - full stdout+stderr, including the flags quoted above.
* `g98.out`, `hessian` - the Gaussian-style archive and the raw numerical Hessian.
