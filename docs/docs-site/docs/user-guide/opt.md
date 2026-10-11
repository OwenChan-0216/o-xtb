# Geometry optimisation

The `--lopt` run type minimises the geometry with the landscape suite.  The
native spelling `--opt` is served by the same suite; the legacy ANCopt is still
reachable as `--opt --method ancopt`.

```bash
oxtb water.xyz --gfn 2 --lopt --lopt-engine lbfgs --lopt-level normal
```

## Choosing the algorithm

`--lopt-engine NAME` (alias `--method NAME`) selects the minimiser.  The names
are not case-sensitive:

| Engine | Notes |
|---|---|
| `lbfgs` | the default; limited-memory BFGS, first derivatives only |
| `bfgs` | full BFGS, first derivatives only |
| `sd` | steepest descent |
| `cg` | conjugate gradient |
| `diis` | GDIIS |
| `rfo` | rational function optimisation; the only engine that builds a Hessian, so it is the slowest per step |

## Convergence level

`--lopt-level LEVEL` selects one of `superloose`, `loose`, `normal` (the
default), `tight`, `vtight`.  The level sets four things at once: the four
convergence thresholds, the energy tolerance `e_tol`, the SCC accuracy of the
engine, and the step budget.  The step budget is three steps per atom at level
`normal`, clamped to the range 200 to 10000; an explicit `--lopt-max-steps`,
`--cycles`, or `--acc` overrides the level.

## Hessian

The Hessian backend is chosen with `--lopt-hessian`: `numerical` (the default,
central differences of the electronic gradient), `model` (the Lindh-D2 model
Hessian) or `file` (read a TURBOMOLE-layout Hessian written by an earlier run,
named by `--lopt-hessian-file`).  Only the `rfo` engine requests a Hessian, so
`--lopt-hess-step` and `--lopt-sccacc` are ignored for the other engines and
the run says so.

## Output

| File | Content |
|---|---|
| `xtbopt.xyz` | the optimised geometry |
| `xtbopt.log` | the optimisation log |
| `xtb.trj` | the trajectory |

An example on the water geometry of the [getting started](../getting-started.md)
page finishes at

```text
          | TOTAL ENERGY               -5.070544447778 Eh   |
          | GRADIENT NORM               0.000007606232 Eh/α |
```

!!! note "To be written"
    This page documents the options that exist and the files that are written.
    A worked comparison of the six engines, and guidance on convergence
    problems, is not written yet.
