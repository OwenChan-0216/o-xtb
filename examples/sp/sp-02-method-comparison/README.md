# sp-02 — the same dimer at four GFN levels

**System.** `benzoic_acid_dimer/reactant.xyz` from `examples/structures` — the C2h benzoic acid
dimer, **30 atoms**, GFN2-xTB minimum. The same `input.xyz` is used for all four runs.

**What it shows.** One geometry, four Hamiltonians: GFN0-xTB, GFN1-xTB, GFN2-xTB and GFN-FF.
The four energies are **not comparable with each other** (different parameterisations and
reference energies); the example shows the CLI spelling and the size of the spread.

**Command** (`run.sh`):

```bash
export OMP_NUM_THREADS=1
export XTBPATH=<repository root>
oxtb input.xyz --gfn 0  --sp --norestart > oxtb-gfn0.log   2>&1
oxtb input.xyz --gfn 1  --sp --norestart > oxtb-gfn1.log   2>&1
oxtb input.xyz --gfn 2  --sp --norestart > oxtb-gfn2.log   2>&1
oxtb input.xyz --gfn ff --sp --norestart > oxtb-gfn-ff.log 2>&1
```

(GFN0-xTB is the only method that reads an on-disk parameter file, `param_gfn0-xtb.txt`; the
installed binary finds its own copy, and `XTBPATH` is set to the repository root as a fallback.)

**Observed result** (the `total energy` lines of the four logs):

| level | total energy / Eh | log |
|---|---|---|
| `--gfn 0`  | **-49.259841189858** | `oxtb-gfn0.log` |
| `--gfn 1`  | **-54.888513527159** | `oxtb-gfn1.log` |
| `--gfn 2`  | **-52.373771244067** | `oxtb-gfn2.log` |
| `--gfn ff` | **-5.993927655063**  | `oxtb-gfn-ff.log` |

The GFN2 number matches `examples/structures/README.md` and case `sp-01`. The GFN-FF energy is a
force-field energy on a completely different scale and must not be put in the same comparison as
the tight-binding energies — it is shown only to demonstrate the `--gfn ff` spelling.

**Reading the logs.** Each log is a full single-point transcript; the line to look at is
`:: total energy … Eh ::` in the `SUMMARY` block. `oxtb-gfn0.log` additionally prints the GFN0
setup; `oxtb-gfn-ff.log` prints the force-field topology instead of an SCF table.

**Reproduce.**

```bash
cd examples/sp/sp-02-method-comparison
rm -f oxtb-gfn*.log
./run.sh
grep -h 'total energy' oxtb-gfn*.log
```

Wall time of all four runs together: **0.08 s**. A clean re-run reproduces the four energies.
