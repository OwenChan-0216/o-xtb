# User guide

The task suite is reached through six run types.  Each performs one task family
and writes its own output files; the method inside a family is selected by a
`--l*-method` flag (or its canonical alias `--method`).

| Page | Run type | Task | Selects the method with |
|---|---|---|---|
| [Geometry optimisation](opt.md) | `--opt`, `--lopt` | energy minimisation | `--lopt-engine` |
| [Surface scans](scan.md) | `--lscan` | one- or two-dimensional surface scan | `--lscan-method` for the inner relaxation |
| [Transition states](ts.md) | `--lts` | saddle search or chain-of-states path | `--lts-method` |
| [Frequencies and thermochemistry](freq.md) | `--hess`, `--lvib` | harmonic analysis | `--lvib-hessian` |
| [Reaction paths](irc.md) | `--lirc` | intrinsic reaction coordinate | `--lirc-method` |

Common to every family:

* the engine is GFN2-xTB by default (`--gfn 2`); `--gfn 0/1/ff` are the other
  methods;
* `--ljson` writes a structured `landscape_<TASK>.json` document for every task
  (see [JSON output](../reference/ljson.md));
* the convergence level and the step budget are chosen with the family's
  `--l*-level` flag; an explicit `--acc`, `--l*-max-steps` or `--cycles` wins
  over the level.

The complete option list is in the generated
[command-line reference](../reference/cli.md).
