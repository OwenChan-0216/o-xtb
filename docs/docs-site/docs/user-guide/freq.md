# Frequencies and thermochemistry

Two run types do harmonic analysis:

* `--hess` - the native numerical Hessian of the input geometry;
* `--lvib` - the suite's frequency task: harmonic frequencies, normal modes
  and a thermodynamic table.

`--ohess` first minimises the geometry with the suite and then runs the
harmonic analysis, so it is the usual way to characterise a stationary point.

```bash
oxtb water.xyz --gfn 2 --lvib
```

## How the Hessian is built

The Hessian is **numerical**: central differences of the electronic gradient,
with a finite-difference step of 0.005 bohr and an SCC accuracy of 0.3 for the
displaced points.  `--lvib-hessian` selects `numerical` (the default), `model`
(the Lindh-D2 model Hessian) or `file` (read a Hessian written by an earlier
run, named by `--lvib-hessian-file`).  `--lvib-hess-step` and `--lvib-sccacc`
change the step and the displacement SCC accuracy.  Trailing translations and
rotations are projected out of the Hessian unless `--lvib-no-project` is given.

`g98.out` and `vibspectrum` use the same names and formats as the native
`--hess` output, so downstream tools that read the native files keep working.

## Thermochemistry

The thermodynamic table temperature is `--lvib-temp` (default 298.15 K).  The
quasi-RRHO rotor cutoff is `--lvib-rotor-cutoff` (default 50.0 cm^-1), the
imaginary-mode cutoff is `--lvib-imag-cutoff` (default -20.0 cm^-1, and the
minus sign is required) and the frequency scaling factor is `--lvib-freq-scal`
(default 1.0).

An xcontrol `$thermo` block (`temp`, `sthr`, `imagthr`, `scale`) is honoured
**unless** the matching command-line option is given: the precedence is
explicit command line > `$thermo` block > built-in default.

## Output

| File | Content |
|---|---|
| `hessian` | the Hessian in the native layout |
| `vibspectrum` | the harmonic spectrum |
| `vib_normal_modes` | the normal-mode displacements |
| `g98.out` | the Gaussian-style output (frequencies, thermochemistry) |
| `compliance.dat` | compliance constants, relaxed force constants and bond local-mode frequencies (multi-atom runs without frozen atoms or periodicity) |

For the non-stationary water example the three real modes are
1565.10, 3629.74 and 3642.97 cm^-1.

!!! note "To be written"
    Guidance on imaginary modes and on non-minimum structures is not written
    yet.
