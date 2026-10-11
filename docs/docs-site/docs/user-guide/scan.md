# Surface scans

The `--lscan` run type scans one or two internal coordinates.  A *relaxed* scan
relaxes every scan point under a constraint potential; a *rigid* scan only moves
the driven coordinate and leaves the rest of the geometry untouched.

```bash
oxtb water.xyz --gfn 2 --lscan \
    --lscan-coord distance --lscan-atoms 1,2 \
    --lscan-step 0.1 --lscan-nstep 5
```

## Driving the coordinate

`--lscan-coord TYPE` is `distance`, `angle` or `dihedral`.  `--lscan-atoms LIST`
lists the 1-based atom indices of the coordinate - two for a distance, three for
an angle, four for a dihedral - separated by commas or blanks.  `--lscan-step`
is the step in angstrom (distance) or degree (angle/dihedral) and
`--lscan-nstep` the number of steps.

A second coordinate with `--lscan-coord2`, `--lscan-atoms2`, `--lscan-step2`
and `--lscan-nstep2` switches the scan to a two-dimensional Cartesian product
grid.

## Mode and inner relaxation

`--lscan-mode` is `relaxed` (the default) or `rigid`.  A relaxed scan minimises
the other coordinates at every point with the inner engine selected by
`--lscan-method` (`sd`, `cg`, `lbfgs` (the default), `bfgs`, `diis`, `rfo`).
`--lscan-level` selects the convergence level of that inner minimisation.
`--lscan-fc` sets the force constant of the constraint potential in
hartree/bohr^2 (the suite default is 0.5, deliberately different from the
native `relaxed_scan` default of 0.05, which trades accuracy for step size).

## Output

The scan is written to `xtbscan.log`, one XYZ frame per converged point, with
the de-biased energy in the comment line.  The format is compatible with the
native `src/scan_driver.f90` output.  The file also carries a report of the
constraint residual and, for a bidirectional sweep, the hysteresis between the
forward and the reverse branch.

A water O-H distance scan of five points starts at

```text
3
 energy: -5.070544208690 xtb: 6.7.1 (...) iter: 1
```

!!! note "Hysteresis is a convergence artefact"
    The forward/reverse difference shrinks monotonically with the convergence
    level; it is not a physical quantity, so the bidirectional sweep is a
    self-check and must be compared at the *same* constraint-residual level
    rather than to an absolute threshold.

!!! note "To be written"
    Worked examples - a dihedral scan of a torsion and a two-dimensional angle
    plus distance scan - are not written yet.
