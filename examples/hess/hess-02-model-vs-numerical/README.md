# hess-02 — model (Lindh-D2) Hessian versus the numerical Hessian

**System.** The same relaxed minimum as `hess-01`: the C2h benzoic acid dimer,
`benzoic_acid_dimer/reactant.xyz` from `examples/structures`, **30 atoms**. `input.xyz` is
byte-identical to case 01.

**What it shows.** The same geometry, the same `--lvib`, but two Hessian backends:
`--lvib-hessian model` (the analytic Lindh-D2 model Hessian — a cheap *guess*) and
`--lvib-hessian numerical` (the real central-difference matrix). The point is that the model
Hessian is a **cheap approximation, not a replacement**: it costs one Hessian instead of ~180
single points, but the frequencies are only qualitative.

**Command** (`run.sh`):

```bash
export OMP_NUM_THREADS=1
export XTBPATH=<repository root>

oxtb input.xyz --gfn 2 --lvib --lvib-hessian model     --norestart > oxtb-model.log     2>&1
mv -f hessian hessian.model; mv -f vibspectrum vibspectrum.model
rm -f vib_normal_modes g98.out compliance.dat
oxtb input.xyz --gfn 2 --lvib --lvib-hessian numerical --norestart > oxtb-numerical.log 2>&1
```

The model run goes first so that the *natural* output names (`hessian`, `vibspectrum`,
`vib_normal_modes`, `g98.out`) belong to the numerical run; the model run keeps `hessian.model`
and `vibspectrum.model`.

**Cost** (the headline result):

| | model | numerical |
|---|---|---|
| engine energy evaluations | **1** | **181** |
| Hessians built | 1 (analytic) | 1 (finite difference) |
| wall time | **0.05 s** | **2.43 s** (~46x) |

**Frequencies** (`eigval :` lines, cm^-1; the numerical column repeats `hess-01`):

| mode group | model | numerical |
|---|---|---|
| zero modes | 6 x 0.00 | 6 x 0.00 |
| first real mode | 21.09 | 14.20 |
| mid range | 156.88 … 1550.04 | 152.10 … 1461.62 |
| highest mode (O-H stretch) | **4090.17** | **3109.48** |

| thermochemistry | model | numerical |
|---|---|---|
| zero point energy | 0.271970985257 Eh | 0.222897688368 Eh |
| free energy G(T) at 298.15 K | -52.143511020138 Eh | -52.194894746191 Eh |

The model Hessian overestimates the stiff O-H stretch by ~30 % (4090 vs 3109 cm^-1) and puts the
ZPE ~0.049 Eh (~31 kcal/mol) too high. It is fine for a **minimiser's initial Hessian** (see
`lopt-02`, where 5 model Hessians drove RFO to the minimum) but it must not be used to report
vibrational frequencies or thermochemistry.

**Reading the output files.** `oxtb-model.log` and `oxtb-numerical.log` are the two full
transcripts; the `eigval :` list and the `modes / zero point energy / total free energy` block are
the comparison points. Among the data files, `vibspectrum` and `vibspectrum.model` are the two
frequency tables side by side; `hessian` and `hessian.model` are the two Hessians. The remaining
natural files (`vib_normal_modes`, `g98.out`) are kept from the numerical run only.

**Reproduce.**

```bash
cd examples/hess/hess-02-model-vs-numerical
rm -f oxtb-model.log oxtb-numerical.log hessian vibspectrum vib_normal_modes g98.out \
      hessian.model vibspectrum.model compliance.dat xtbtopo.mol charges wbo xtbrestart
./run.sh
grep -E 'energy evaluations' oxtb-*.log
grep '^eigval :' vibspectrum.model | head
```

A clean re-run reproduces `hessian`, `vibspectrum`, `vib_normal_modes`, `g98.out`, `hessian.model`
and `vibspectrum.model` **byte for byte** (sha256 `4965e179…`, `7717d79b…`, `c367384c…`,
`7273c21d…`, `0dfde7ef…`, `6c9b880a…`).
