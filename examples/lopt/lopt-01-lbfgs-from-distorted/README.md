# lopt-01 — L-BFGS minimisation from a distorted geometry

**System.** A deliberately distorted **33-atom** Diels-Alder system: the 9,10-cycloadduct of
anthracene + maleic anhydride from `examples/structures/anthracene_maleic_anhydride/product.xyz`.
`input.xyz` is that minimum with a fixed displacement added to every atom, `i = 1..33`:

```
dx = 0.20*sin(1.7 i)  A      dy = 0.20*sin(2.9 i + 0.5)  A      dz = 0.20*cos(3.1 i + 1.1)  A
```

so the starting geometry is up to ~0.35 A per atom away from the minimum.

**What it shows.** The default first-order engine, L-BFGS, driving a badly distorted geometry back
to the minimum: how large the energy drop is, how many steps it takes, and the gradient norm at
which the run stops.

**Command** (`run.sh`):

```bash
export OMP_NUM_THREADS=1
export XTBPATH=<repository root>
oxtb input.xyz --gfn 2 --lopt --lopt-engine lbfgs --lopt-level normal \
    --lopt-max-steps 300 --norestart
```

**Observed result** (`oxtb.log`):

| quantity | value |
|---|---|
| start energy (step 1) | -55.957309694174 Eh |
| final energy | **-56.913729348717 Eh** |
| energy drop | **-0.956419654543 Eh = -600.2 kcal/mol** |
| converged | T |
| steps | **41** |
| energy calls | 43 |
| final gradient norm | 9.871240e-04 Eh/bohr |
| max gradient component | 2.691619e-04 Eh/bohr (threshold 3.0e-04) |
| wall time | **1.11 s** |

The run stops on the `normal`-level thresholds (`gmax 3.0e-04`, `etol 5e-06`); the geometry is a
true minimum, but not converged to machine precision — that is what the `vtight` level is for.

**Reading the output files.** `oxtb.log` holds the setup banner, the step table
(`iter / energy / dE / gmax / dmax / trust`), the `convergence history` block and the final
summary (`steps`, `final energy`, `final gradient`). `xtbopt.xyz` is the optimised geometry (xmol,
Angstrom); `xtbopt.log` is the trajectory of the same geometry (xmol, one frame per accepted step).
`xtb.trj` (a trajectory), `xtbtopo.mol`/`charges`/`wbo` (topology and charges) and the empty
`.xtboptok` convergence flag are byproducts, not committed here.

**Comparison with case 02.** The same input with `--lopt-engine rfo --lopt-hessian model`
converges in **24** steps (see `lopt-02-rfo-from-distorted`), i.e. the second-order step is worth
about 1.7x fewer evaluations here.

**Reproduce.**

```bash
cd examples/lopt/lopt-01-lbfgs-from-distorted
rm -f oxtb.log xtbopt.xyz xtbopt.log xtb.trj xtbtopo.mol charges wbo xtbrestart
./run.sh
grep -E 'steps:|final energy|final gradient' oxtb.log
```

A clean re-run reproduces `xtbopt.xyz` and `xtbopt.log` **byte for byte**
(sha256 `b0d670fa…` / `68197e04…`).
