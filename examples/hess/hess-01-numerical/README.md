# hess-01 — numerical Hessian of a relaxed minimum

**System.** `benzoic_acid_dimer/reactant.xyz` from `examples/structures` — the C2h benzoic acid
dimer, **30 atoms**, a GFN2-xTB minimum. It is small and cheap, which is why the finite-difference
Hessian is affordable here.

**What it shows.** The full `--lvib` output with the **default numerical (central-difference)
Hessian**: the frequency list, the projected zero-mode count, and the RRHO thermochemistry block.
This is the reference the model Hessian of case `hess-02` is compared against.

**Command** (`run.sh`):

```bash
export OMP_NUM_THREADS=1
export XTBPATH=<repository root>
oxtb input.xyz --gfn 2 --lvib --norestart
```

**Observed result** (`oxtb.log`):

| quantity | value |
|---|---|
| modes | 84 internal, **6 projected zero modes**, 0 imaginary |
| lowest / highest real mode | 14.20 / 3109.48 cm^-1 |
| symmetry | C2h (detected, used in the thermo) |
| zero point energy | **0.222897688368 Eh** |
| total enthalpy H(T) at 298.15 K | -52.133632181787 Eh |
| total free energy G(T) at 298.15 K | **-52.194894746191 Eh** |
| energy evaluations (engine) | 181 |
| wall time | **2.41 s** |

**Frequency list** (`eigval :` lines, cm^-1, first row is the six zero modes):

```
    0.00     0.00     0.00     0.00     0.00     0.00
   14.20    22.38    44.51    57.88    61.61    76.35
   87.49   126.19   152.10   171.52   223.97   283.43
  363.72   363.76   373.42   400.83   405.83   420.67
  491.84   543.23   587.00   587.09   631.80   634.12
  640.40   642.47   688.97   690.36   783.42   783.52
  788.66   796.98   878.13   878.16   912.13   914.06
  916.08   931.31   931.45   934.96   934.98   954.81
  983.21   983.95  1077.88  1077.94  1115.29  1115.36
 1152.08  1155.29  1180.91  1180.92  1192.40  1193.89
 1233.04  1245.26  1273.94  1274.14  1315.34  1328.32
 1330.13  1336.47  1435.33  1435.40  1461.60  1461.62
 1586.04  1586.09  1593.82  1594.21  1663.44  1709.21
 2697.30  2803.35  3079.55  3079.55  3087.22  3087.23
 3093.90  3093.99  3100.75  3100.76  3109.43  3109.48
```

The smallest real mode (14.20 cm^-1) is the intermolecular dimer libration; the highest
(3109.48 cm^-1) is the O-H stretch.

**Reading the output files.** `oxtb.log` holds the `bond local-mode frequency` table, the `eigval`
list above, the IR/Raman intensity blocks, the `Thermodynamic Functions` setup (symmetry, rotor
cutoff, scaling) and the mode-by-mode entropy table, then the block `modes / imaginary modes /
lowest mode / zero point energy / total enthalpy H(T) / total free energy G(T)`. The four data
files are the suite's standard `--lvib` outputs, written with the same names and formats as
`--hess`: `hessian` (the raw Hessian), `vibspectrum` (mode, symmetry, wavenumber, IR intensity,
selection rule), `vib_normal_modes` (the normal-mode displacements) and `g98.out` (a Molden/Gaussian
fake output for external tools).

**Reproduce.**

```bash
cd examples/hess/hess-01-numerical
rm -f oxtb.log hessian vibspectrum vib_normal_modes g98.out compliance.dat \
      xtbtopo.mol charges wbo xtbrestart
./run.sh
grep -E 'imaginary modes|lowest mode|total free energy' oxtb.log
```

A clean re-run reproduces `hessian`, `vibspectrum`, `vib_normal_modes` and `g98.out` **byte for
byte** (sha256 `4965e179…`, `7717d79b…`, `c367384c…`, `7273c21d…`).
