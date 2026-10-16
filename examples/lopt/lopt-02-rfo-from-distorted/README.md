# lopt-02 — RFO from the same distorted geometry

**System.** Identical to `lopt-01`: the **33-atom** anthracene + maleic anhydride cycloadduct
(`examples/structures/anthracene_maleic_anhydride/product.xyz`) distorted by the same fixed field.
`input.xyz` is byte-identical to the one in case 01.

**What it shows.** The second-order engine, RFO, with the **model (Lindh-D2) Hessian** instead of a
numerical one. Comparing with case 01 shows what the Hessian-based step buys: fewer iterations and
a tighter final gradient — while the model Hessian keeps the cost low (a numerical Hessian per
step would cost ~180 single points, see case `hess-01`).

**Command** (`run.sh`):

```bash
export OMP_NUM_THREADS=1
export XTBPATH=<repository root>
oxtb input.xyz --gfn 2 --lopt --lopt-engine rfo --lopt-hessian model \
    --lopt-level normal --lopt-max-steps 300 --norestart
```

**Observed result** (`oxtb.log`):

| quantity | value | vs case 01 (L-BFGS) |
|---|---|---|
| start energy (input geometry) | -55.957309694174 Eh | same input |
| final energy | **-56.913801582848 Eh** | 7.2e-05 Eh lower |
| energy drop | -0.956491888674 Eh = -600.2 kcal/mol | |
| steps | **24** | 41 (1.7x more) |
| energy calls | 25 | 43 |
| model Hessians built | 5 | 0 |
| final gradient norm | 1.075539e-04 Eh/bohr | 9.871240e-04 |
| max gradient component | 3.493370e-05 Eh/bohr | 2.691619e-04 |
| wall time | **0.45 s** | 0.61 s |

RFO reaches a slightly lower minimum because it converges the gradient further inside the same
`normal` budget; both runs end in the same basin (the cycloadduct). RFO requests a Hessian at the
start and refreshes it every few steps (5 model Hessians here) — with `--lopt-hessian model` that
is a cheap analytic guess, not a finite-difference matrix.

**Reading the output files.** Same layout as case 01: `oxtb.log` (step table + summary),
`xtbopt.xyz` (optimised geometry) and `xtbopt.log` (trajectory). The `Hessians` counter near the
end of `oxtb.log` is the number of Hessian builds — the line that separates a second-order engine
from a first-order one.

**Reproduce.**

```bash
cd examples/lopt/lopt-02-rfo-from-distorted
rm -f oxtb.log xtbopt.xyz xtbopt.log xtb.trj xtbtopo.mol charges wbo xtbrestart
./run.sh
grep -E 'steps:|final energy|final gradient|Hessians' oxtb.log
```

A clean re-run reproduces `xtbopt.xyz` and `xtbopt.log` byte for byte
(sha256 `4d18209d…` / `adde052d…`).
