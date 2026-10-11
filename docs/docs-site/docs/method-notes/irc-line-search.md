# The IRC line search

**Applies to** `--lirc --lirc-method gs`.  The other three integrators (`lqa`,
`hpc`, `eulerpc`) do not use this line search and are unaffected.

The gradient-descent IRC integrator walks the reaction path in mass-weighted
coordinates.  Each macro step of length `s` alternates a *predictor* (advance
along the path) with a *corrector*: a line search that, from the current point,
solves a Newton step **tangent** to the reaction direction and clips it so the
point never leaves the sphere of radius `s/2` around the pivot.

## The problem

The original corrector stopped on the *unclipped* Newton step, which is roughly
1.8 to 2.4 bohr amu^1/2 - about 40 times the sphere radius of 0.05 - so it could
never satisfy its `|d| <= 1e-3` tolerance and always ran its full 20
iterations.  On the Müller-Brown surface the corrector's cost, counted as
gradient evaluations per macro step (`E/g`), was **16.93 (forward) and 20.25
(backward)**, and the resulting path deviated **0.040 bohr** from the analytic
minimum-energy path.

## The fix

Replace the clip-and-retry loop with an equality-constrained
(Karush-Kuhn-Tucker) step that lands directly on the sphere: solve

```text
min E(q)  subject to  |q - pivot|^2 = (s/2)^2
```

with a level-shifted reduced Hessian for the tangent block and an explicit
radial component.  The corrector then converges in 2 to 3 iterations.

## Measured result

| Quantity | Before | After |
|---|---|---|
| `gs` `E/g`, GFN2 HCN/HNC | 16.93 / 20.25 | **1.88 / 2.14** |
| KKT residual, unit model | 3.4e-4 / 1.3e-3 Eh | **8.5e-14 Eh** |
| Müller-Brown MEP deviation | 0.040 bohr | **0.0192 fwd / 0.0344 bwd** |

The `lqa`, `hpc` and `eulerpc` paths are bit-identical before and after, so
this is a pure cost-and-accuracy change to `gs`.

## How it is checked

A unit case builds a synthetic quadratic surface whose constrained minimum is
known in closed form and asserts the KKT residual; the command-line
cross-check runs all four integrators on one transition state and compares the
endpoints and the mean `E/g`.  `gs` remains a compatible reference integrator;
`hpc` stays the production default.

> **Internal evidence.**  The measurements behind this page are recorded in the
> internal engineering records report 44 (the diagnosis and the `E/g` scan),
> report 64 (the derivation and implementation of the KKT step) and report 65
> (the independent re-validation).  Those records are not published with this
> site; every number they supply is restated above so this page stands alone.
> Quote the report ids in a bug report or pull request when the provenance of a
> number matters.
