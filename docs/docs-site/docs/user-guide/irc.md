# Reaction paths (IRC)

The `--lirc` run type follows the intrinsic reaction coordinate from a
transition state downhill to the two minima.  The input geometry **is** the
transition state and must have exactly one imaginary mode.

```bash
oxtb hcn.xyz --gfn 2 --lirc --lirc-method hpc
```

## Integrators

`--lirc-method NAME` (alias `--method NAME`) selects the integrator; the name is
not case-sensitive:

| Method | The program's help describes it as |
|---|---|
| `hpc` | the default; Hessian-based predictor-corrector, "most accurate and 1.98 E/g per point" |
| `lqa` | Page-McIver analytic quadratic propagation, "cheapest at 1.00 E/g" |
| `eulerpc` | Euler predictor-corrector, "use a step of 0.20 or less" |
| `gs` | Gonzalez-Schlegel sphere relaxation, a "compatible reference; 1.9-2.1 E/g per point and the largest path deviation, validated for steps up to 0.15" |

`--lirc-step` is the arc-length step.  The supporting options control the
corrector (`--lirc-micro-cycles`, `--lirc-micro-thresh`), the endpoint handling
(`--lirc-no-endpoint-relax`, `--lirc-rmsd-end`), the oscillation guard
(`--lirc-osc-window`, `--lirc-e-rise`) and the convergence level
(`--lirc-level`, `--lirc-max-steps`).  `--lirc-oneway` follows only the forward
direction.

!!! warning "`--lirc-adaptive` only affects `gs`"
    The adaptive-step switch is read by the `gs` integrator only.  For
    `lqa`, `hpc` and `eulerpc` it is a silent no-op, and the step stays at
    `--lirc-step`.

## Output

| File | Content |
|---|---|
| `irc_forward.xyz` | the forward branch |
| `irc_backward.xyz` | the backward branch |
| `irc_path.xyz` | both branches as a single path |
| `irc.log` | the integration log |

See [The IRC line search](../method-notes/irc-line-search.md) for how the `gs`
corrector was made to converge on the constraint sphere.

!!! note "To be written"
    A worked example that starts from a real saddle and reports the two minima
    reached is not written yet.
