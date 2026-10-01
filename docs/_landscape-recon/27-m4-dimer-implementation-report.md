# 27 — M4 (stage 2) implementation report: dimer transition state search

> Scope of this round: **`--lts --lts-method dimer`**, the second stage of M4.
> Stage 1 (P-RFO / B-P-RFO, `26-m4-saddle-implementation-report.md`) is
> untouched except for the two integration points listed in §7.  NEB / CI-NEB /
> AutoNEB / string stay in M5, IRC in M6.

All commands were run with `OMP_NUM_THREADS=1` (AGENTS.md §4) in
`/tmp/xtb-land/build` (Release) and `/tmp/xtb-land/build-debug`
(`-DCMAKE_BUILD_TYPE=Debug`, i.e. `-fbounds-check -ffpe-trap=invalid,zero,overflow`),
both configured `-DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON`.

---

## 1. Deliverables

| File | LOC | Content |
|---|---|---|
| `src/landscape/saddle/dimer.f90` | 1082 (new) | curvature (Eq. 2), translation force (Eq. 21), rotation direction (Eq. 5) and angle (Eq. 13), quick-min update, mobility limiter, initial axis, rotation kernel, macro driver |
| `src/landscape/types/settings.f90` | 1019 → 1061 | `dR`, `rot_dtheta`, `rot_f_rms_th`, `translate_max_iter`, `n_init` (now a *name*: `random`/`force`), `landscape_ts_ninit_known` |
| `src/landscape/saddle/eigenfollow.f90` | 593 → 597 | `transition_mode_set_phase` → `landscape_transition_mode_set_phase`, exported (the dimer applies the same phase convention to its final axis) |
| `src/landscape/tasks/ts.f90` | 339 → 362 | `method = dimer` dispatches to the dimer driver, dimer settings printed in the header; the `"dimer is not implemented yet"` branch is gone |
| `src/prog/main.F90`, `src/xhelp.f90` | 9 new flags + help | `--lts-delta`, `--lts-dr`, `--lts-rot-max-iter`, `--lts-rot-alpha`, `--lts-rot-frms`, `--lts-ninit`, `--lts-seed`, `--lts-step-max`, `--lts-translate-max-iter` |
| `test/unit/test_landscape_saddle.f90` | 808 → 1506 | 14 new dimer unit tests (34 in the module) |
| `test/unit/CMakeLists.txt`, `test/unit/meson.build`, `test/unit/landscape_cli_check.py` | +4 / +3 tests | `xtb/landscape-ts-dimer` is now a real end-to-end test, plus three new error-branch tests |
| CLI | — | `--lts-delta`, `--lts-dr`, `--lts-rot-max-iter`, `--lts-rot-alpha`, `--lts-rot-frms`, `--lts-ninit`, `--lts-seed`, `--lts-step-max`, `--lts-translate-max-iter` |

New defaults of the dimer block (PLAN §5.3.6 values unless noted): `delta =
1.8897e-2` bohr (centre→image, pysisyphus convention), `dR = 1.8897e-3` bohr
(1e-3 Å), `rot_dtheta = 1e-4` rad, `rot_alpha = 0.5`, `rot_max_iter = 5`,
`rot_f_rms_th = 2.65e-4` hartree/bohr, `step0 = 3.7795e-1` bohr, `step_max =
2.8346e-1` bohr, `translate_max_iter = 1`, `n_init = 'random'`, `seed = 42`.

---

## 2. Curvature (Eq. 2) — what is implemented and why it equals the paper's forms

Implemented:

```
C = (F(R - delta*N) - F(R + delta*N)) . N / (2 delta)        (Eq. 2)
```

`landscape_dimer_curvature` takes the **forces** `F = -g`; image 1 is at
`R + delta*N`, image 2 at `R - delta*N`.  With those labels
`F2 - F1 = 2 delta (H N)`, so `C = N^T H N`, the **energy curvature** along the
axis, and the `C < 0` branch of Eq. 21 becomes the physical one (ascend along
the axis, relax perpendicularly).  The image labels matter: swapping them flips
the sign of `C` and would invert Eq. 21, so the assignment is part of the
convention and is pinned by the unit test `dimer-translation-force`.

The energy form of the paper's Eq. 2, `C = (E2 - E0)/delta^2` (with `E0` the
midpoint energy of its Eq. 3), is the same quantity **at a stationary point
along the axis**: expanding the images at `+/- delta` gives
`(E2 - E0)/delta^2 = C/2 - (g.N)/delta`.  It therefore differs from the force
form by

* a factor **1/2**, because each image sits at `delta` (not `delta/2`) from the
  midpoint, and
* a gradient term that vanishes only for `g.N = 0`.

A further factor 2 appears if the denominator is written with the *image
separation* `2*delta` instead of `delta`.  That is exactly the definition
ambiguity of PLAN §5.3.6: VASP's `DdR` denotes twice the image-to-midpoint
distance, while `delta` here denotes the centre-to-image distance (pysisyphus
convention, `1.8897e-2` bohr = `1e-2` Å).  The implementation uses the force
form with the centre-to-image `delta`, so the same `delta` also sets the
denominator `2*delta` and the displacement `+/- delta*N` of the two images.
This is documented in the module header of `dimer.f90` (not only here).

Quantitative check (`dimer-curvature`): against the analytic Mueller-Brown
Hessian the finite difference curvature reproduces `N^T H N` to **0.07 %**
(along e1) and **0.09 %** (along e2) at the default `delta`; the unit test
asserts a 0.2 % relative tolerance and prints both numbers.

---

## 3. Rotation — Eq. 5/13, and a branch of Eq. 13 that has to be fixed

`landscape_dimer_rotation_direction` implements Eq. 5,
`F' = F1' - F2'`, `Fi' = Fi - (Fi.N) N`; `F'` is proportional to
`-(H N)_perp`, i.e. it points into the direction in which the axis must be
rotated to **lower** the curvature.  Its unit vector is the rotation direction
`q`, its norm/rms the torque (`rms` is compared against `rot_f_rms_th`).

`landscape_dimer_rotation_angle` implements Eq. 13 on the two term Fourier
model `F(theta) = A sin 2theta + B cos 2theta` of the paper, with
`F0 = B`, `F0' = 2A`:

```
theta = 1/2 atan2(-2 F0, F0')            (+ pi/2 when that is negative)
```

*(1) Why not the literal `-1/2 arctan(2 F0/F0')`.*  The two forms select
different roots of the same model: the model's roots are `pi/2` apart and the
rotation that **lowers** the curvature is the first *positive* one, while the
principal branch of the arctan returns the root nearest to zero - which is the
**maximising** root whenever the model needs a rotation of more than 45
degrees.  Measured on the GFN2 HCN start geometry (deterministic `force` axis):
the principal branch returns **-0.54 rad** where the correct root is
**+1.04 rad**; the search then follows the maximising direction into a stiff
mode, the reported curvature stays at **+2.57** hartree/bohr^2 (the true lowest
curvature there is -0.126) and the energy rises to **+1e2 Eh** within eight
macro steps; with the branch above the same start keeps the axis on the
negative mode (**-0.120** hartree/bohr^2 at the first step) and converges
(§6.3).  A three dimensional analytic probe of the rotation flow
(`H = diag(-0.126, 2.57, 5)`, random starts) confirms it: with the principal
branch the flow converges to the `+2.57` *saddle* of the curvature landscape
from most starts, with the first-positive-root branch to `-0.126` from all of
them (only a start exactly on an eigenvector stays there, which is correct).
The deviation is documented in the function header and pinned by the last
assertion of `dimer-rotation-angle`.

For a rotation of less than 45 degrees both forms agree, which is why stage 1
and the small-angle unit test are unaffected; the difference is `O(1)` only in
the misaligned regime.

*(2) The rotation direction is kept in the internal space.*  Translations and
rotations are (numerically) null vectors of the Hessian and therefore carry the
lowest curvature of the surface; measured on GFN2 HCN, the rotational force of
the *numerical* Hessian is dominated by that spurious component.  `keep_internal`
projects the rigid body basis and the axis direction out of `q` before the
rotation, and the axis itself is renormalised, so the whole rotation stays in
the subspace the axis already lives in.  (In the two dimensional unit tests
`landscape_rigid_modes` returns an empty basis, so they exercise the plain
path.)

*(3) `rot_alpha` damps the angle* (`theta_applied = rot_alpha*theta`), as
documented on the setting; the un-damped form (`rot_alpha = 1`) takes the exact
line-minimising angle of the two term model.

*(4) VASP diagnostic.*  Exhausting `rot_max_iter` while the rms torque is still
above `rot_f_rms_th` emits exactly
`"dimer rotation did not converge; consider increasing delta or tightening SCF"`
(PLAN §6.3).  It is a warning, not an error: a partially rotated axis still
gives a usable direction (measured: the GFN2 HCN run converges with 5 such
warnings in 39 steps).  `dimer-rotation-warning` pins the message.

---

## 4. Translation — Eq. 21, quick-min, and a measured deviation from the paper's step length

`landscape_dimer_translation_force` implements Eq. 21 verbatim:

```
F^dagger = F_R - 2 F_par       (C < 0)
F^dagger = -F_par              (C > 0)
```

i.e. the parallel component is always reversed (the axis is climbed) and the
perpendicular subspace is relaxed only for a negative curvature, where the axis
is the reaction coordinate.

`landscape_dimer_velocity_update` is quick-min (H&J §II D; Sheppard, Terrell &
Henkelman 2008): `v <- v + increment*F^dagger/|F^dagger|`, `v <- 0` when
`v.F^dagger <= 0` (an uphill velocity is discarded), and the momentum is capped
at `step_max`; the displacement of the update is `v`.

*The step length.*  The displacement is **proportional to the effective force**,
`step = tau F^dagger`, with the mobility `tau` fixed once, from the first
effective force, so that the first translation has the length
`min(step0, step_max)`; later translations follow the force and shrink with it,
which is what makes the displacement criteria reachable at the saddle.  The
finite difference `dR` of the paper supplies the curvature along the effective
force, which limits the mobility to `1/kappa` when that is smaller
(`landscape_dimer_mobility`): a stiff direction cannot overshoot its harmonic
length scale.  *Measured:* the limiter is **active** in the GFN2 HCN run
(`dimer translation: |F_dagger| 1.156E-01 Eh/bohr, step 1.395E-01 bohr,
mobility 1.207E+00 (kappa 8.285E-01 Eh/bohr^2)`, and `1/0.8285 = 1.207`) and
does **not** bind on Mueller-Brown (largest `kappa` on the path 0.9 against
`1/tau = 2.7`).

*Deviation from the literal reading of the paper.*  Taking the step length
itself as the Newton length `|F^dagger|/kappa` - the literal reading of the
paper's one dimensional minimisation along `F^dagger` with the finite difference
step `dR` - makes the search **ping-pong** around the saddle: the effective
force is not a gradient field (its parallel part ascends, its perpendicular part
descends), so `kappa = u^T H u` changes sign near the transition state and
`|F^dagger|/kappa` stops shrinking.  Measured on Mueller-Brown
(`delta = 1.8897e-2` bohr, start `(-0.6, 0.4)`, `step_max = 5e-2`): the Newton
form keeps taking the maximal step near the saddle and orbits it for 200+
macro steps (distance to the saddle alternating between 0.036 and 0.015 bohr,
`kappa` between -1.20 and -0.96, never converging), while the force proportional
implementation converges from the same start in 23 steps to 1.4e-4 bohr of the
saddle.  This is documented in the module header; the `dR` probe and the
mobility limiter keep their role as the finite difference protection of PLAN
§6.3.

---

## 5. Initial axis (PLAN N10) and the macro loop

* `n_init = 'random'` draws a uniform direction.  `random_seed(put=...)` is
  called with `settings%seed` **before** `random_number`, so the axis is a pure
  function of the seed: two draws with the same seed are bitwise identical
  (`dimer-initial-axis`), two runs with the same seed are bitwise identical
  (`dimer-reproducible`), and a different seed gives a different axis (measured
  max component difference 0.758 for seeds 42 vs 7).  This is the only random
  number in the suite.
* `n_init = 'force'` is the deterministic substitute: the unit vector of the
  largest Cartesian gradient component (and it may be `-e_i`; a dimer axis is a
  line).
* The axis is projected onto the internal space at the start and after every
  rotation.
* One macro iteration = one rotation (up to `rot_max_iter`) followed by
  `translate_max_iter` quick-min translations.  A step is always taken when the
  trial evaluation succeeds (the energy may rise at a saddle); a failed
  evaluation keeps the previous geometry and zeroes the velocity.
* Convergence = the inherited four criteria **and** `C < 0` along the final axis
  (the VASP rule).  A point whose gradient meets the criteria but whose
  curvature along the axis is not negative is *warned about* ("the point is a
  minimum rather than a saddle point") and the search continues; if
  `max_steps` then runs out the task aborts with a non-zero status.  This is the
  M4 hard constraint 2 rule applied to the dimer's own curvature.
* The final axis is phase fixed (largest component positive) and reported with
  `landscape_transition_mode_report`, i.e. with the same
  `transition mode: index 0, eigenvalue <C>` / `transition vector component:
  ... (cartesian c of atom a)` lines as the P-RFO search (`index 0` = no
  spectrum index: the dimer has no Hessian).

---

## 6. Validation

### 6.1 Unit tests (`xtb/landscape-saddle`, 34 cases, 14 new)

`dimer-curvature`, `dimer-translation-force`, `dimer-rotation-angle`,
`dimer-rotation-alignment`, `dimer-rotation-warning`, `dimer-velocity-update`,
`dimer-mobility`, `dimer-initial-axis`, `dimer-invalid`, `dimer-mb-saddle`,
`dimer-no-hessian`, `dimer-reproducible` (the last three each run a full
search).

Measured values the tests print and assert:

| quantity | measured | assertion |
|---|---|---|
| Eq. 13 vs the exact Fourier root 1e-3 / 0.3 | 1.0000e-3 / 2.9998e-1 | < 1e-7 / < 1e-3 |
| Eq. 6 reference for the same two cases | 9.5000e-4 / 3.4200e-1 | differ by > 1e-6 / > 1e-2 |
| torque rms before/after a rotation | 1.5112e-3 → 1.0126e-7 | drops below 20 % |
| Mueller-Brown dimer, start (-0.75, 0.5) | 14 steps, converged, `gmax` 1.0752e-4 | converged |
| distance to the exact MB saddle | 8.1093e-5 bohr | < 1e-3 |
| RMSD to P-RFO from the same start | **7.8177e-5 bohr** | < 1e-3 |
| Hessian requests of the dimer | **0** | == 0 |
| two runs, same seed | bitwise identical geometry | `all(first == second)` |
| seed 2 vs seed 7 | 6.3256e-11 bohr in the geometry | same saddle point, < 1e-4 |

The Release and the Debug build produce bitwise identical numbers for the whole
dimer suite (checked: 14 steps, `dist` 8.1093e-5, `rmsd` 7.8177e-5, seed
difference 6.3256e-11 in both).

The Mueller-Brown tests calibrate `step0 = step_max = 5e-2` bohr because the
surface is dimensionless (`kcaltoau` energy scale) and its whole span is ~2
units; with the GFN2-oriented defaults the translation jumps past the saddle
(measured: no convergence in 400 steps).  The start is `(-0.75, 0.5)`; from
`(-0.6, 0.4)` and `(-0.7, 0.45)` the dimer does not converge (all of 40 tested
seeds) and from `(-0.75, 0.5)` 31 of 40 seeds reach the saddle while 9 reach a
different stationary point - the initial axis decides, which is the documented
"the dimer can be trapped" failure mode of the method, not a numerical defect
(see §8.1).

`dimer-no-hessian` runs the dimer on a Mueller-Brown surface whose `hessian`
returns `fail = .true.`: the converged run is the assertion that the search
never asks for a Hessian (PLAN §9.5).

### 6.2 Build hygiene

* Release build: clean, no warnings (`gfortran -Wall -Wextra` on `dimer.f90`
  reports nothing).
* Debug build (`-fbounds-check -ffpe-trap=invalid,zero,overflow`): the whole
  `landscape-saddle` suite passes (no bounds violation, no floating point
  exception).
* `grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d` is
  empty; `ctest -N -R landscape` reports **44** targets (41 before).

### 6.3 Real GFN2 end-to-end (`--lts --lts-method dimer`)

`hcn.xyz` is the bent HCN guess used by the P-RFO stage.  Default settings
(`n_init = random`, seed 42), complete transcript in `/tmp/dimer-e2e/final`:

```
 landscape: transition state search (dimer)
 dimer separation:          1.889700E-02 bohr
 dimer rotation probe:      1.000000E-04 rad
 dimer rotation iterations: 5
 dimer initial axis:       random (seed 42)
 electronic temperature:        300.000 K (frozen for the whole run)
 dimer initial axis: random direction (seed 42)
 dimer separation:   1.889700E-02 bohr, finite difference step  1.889700E-03 bohr
    iter            energy/Eh        dE/(kcal/mol)   gmax/(Eh/bohr)  dmax/bohr     trust/bohr
      1      -5.401523001589       4.1215  7.957452E-02  7.376175E-02  2.834600E-01
   dimer rotation: iterations 5, torque rms  9.403526E-04 max  1.904949E-03 Eh/bohr, converged=F
   dimer curvature:   -1.200419E-01 Eh/bohr^2 (Eq. 2)
   dimer translation: |F_dagger|  1.155922E-01 Eh/bohr, step  1.032233E-01 bohr, mobility  8.929952E-01 (kappa  1.119827E+00 Eh/bohr^2)
      2      -5.390901056643       6.6654  3.478944E-02  1.177064E-01  2.834600E-01
   dimer rotation: iterations 5, torque rms  5.375372E-04 max  1.238721E-03 Eh/bohr, converged=F
   dimer curvature:   -1.190295E-01 Eh/bohr^2 (Eq. 2)
   dimer translation: |F_dagger|  1.095949E-01 Eh/bohr, step  1.968448E-01 bohr, mobility  1.444263E+00 (kappa  6.923949E-01 Eh/bohr^2)
   ...
     36      -5.387372301682    1.813267E-03    2.834600E-01
     37      -5.387373479498    3.145811E-04    2.834600E-01
     38      -5.387373479498    3.145811E-04    2.834600E-01
     39      -5.387373510767    1.337665E-04    2.834600E-01
 dimer final curvature:   -1.976752E-01 Eh/bohr^2
 transition mode: index 0, eigenvalue      -0.19767518 Eh/bohr^2
 transition vector component:     0.600694 (cartesian 1 of atom 1)
 transition vector overlap:     1.000000
 converged:      T
 steps:          39
 criteria (gmax,grms,dmax,drms):  T T T T
 saddle confirmation - imaginary modes: 1
 most negative frequency:         -1425.83 cm^-1
 wrote xtbts.xyz
 wrote xtbts.log
 landscape task terminated: converged
          | TOTAL ENERGY               -5.387373510767 Eh   |
```

`xtbts.xyz`: `H 0.14113 1.03305 0.00000 / C -0.08269 -0.10758 0.00000 /
N 1.09756 0.12453 0.00000` bohr, `gnorm 1.34e-4`.

Comparison with the P-RFO run of the same input (`--lts-method prfo`, 4 steps):

| | P-RFO | dimer (random 42) | dimer (`force`) |
|---|---|---|---|
| steps | 4 | 39 | 38 |
| energy / Eh | -5.387373532487 | -5.387373510767 | -5.387373451279 |
| lowest frequency / cm^-1 | -1426.11 | -1425.83 | -1426.50 |
| aligned RMSD vs P-RFO / bohr | — | **6.73e-5** | **1.17e-4** |
| max Cartesian component / bohr | — | 5.94e-4 | 4.94e-3 |

Both methods locate the same HCN/HNC transition state; the Cartesian difference
is dominated by a rigid rotation of the coordinate frame, which is why the
aligned RMSD is quoted next to the raw one.  With a deliberately different
dimer configuration (`--lts-ninit force --lts-seed 7 --lts-delta 0.019
--lts-dr 0.002 --lts-rot-max-iter 8 --lts-step-max 0.25
--lts-translate-max-iter 2`) the search needs 129 steps and reaches the same
point (aligned RMSD 4.86e-5 bohr, -1426.20 cm^-1).

`--lts-seed` reproducibility: two identical runs differ only in the timestamps,
xtb's own unrelated `random seed` line and the timing table; all dimer
diagnostics and `xtbts.xyz` are bitwise identical.

### 6.4 M4 hard constraint 2 (curvature resolution) — measured

First macro step of the same GFN2 HCN start (deterministic `force` axis), i.e.
one and the same geometry, varying only the finite difference parameter:

| `delta` / bohr | curvature / (Eh/bohr^2) |
|---|---|
| 4.72e-3 | -1.112498e-1 |
| 9.44e-3 | -1.112410e-1 |
| **1.8897e-2 (default)** | **-1.112383e-1** |
| 3.78e-2 | -1.112422e-1 |

| `--acc` | curvature / (Eh/bohr^2) |
|---|---|
| 0.3 (default) | -1.112129e-1 |
| 0.1 | -1.112123e-1 |
| 0.01 | -1.112122e-1 |

The curvature varies by **1.5e-6** (0.0013 %) over a factor 8 in `delta` and by
**7e-7** (0.0006 %) over a factor 30 in the SCC accuracy.  The statistical
resolution of the force difference is `sqrt(2) sigma_F/(2 delta) ~ 4e-8`
Eh/bohr^2 at the cold-start force noise of AGENTS.md §6.  Both are two orders
of magnitude below the 3 cm^-1 band of hard constraint 2 (about 1e-4
Eh/bohr^2), so the branch decision (`C < 0`) is not noise limited for any mode
outside that band; a mode *inside* the band is below the resolution of any
finite difference curvature and needs the remedy of the constraint (tighter
`--acc`) rather than a different sampling.  The argument is in the module
header, the numbers are here.

### 6.5 M4 hard constraint 1 (`etemp` frozen) and PLAN §8.2 experiments

* `etemp` is frozen in `settings%etemp`, pushed into the engine control by
  `tasks/ts.f90` (unchanged from stage 1) and printed both from the settings and
  from the calculator; the dimer prints it exactly as the P-RFO branch does
  (§6.3), and `xtb/landscape-ts-dimer` asserts the effective value.
* PLAN §8.2 experiment #3 (curvature vs `etemp`) is the M3 measurement
  (report 21); the dimer inherits the frozen value.
* PLAN §8.2 experiment #4 (gradient noise vs reachable threshold) is closed
  *for the dimer* by §6.4: the curvature sign and the force criteria are
  decided far above the SCC noise; the *convergence thresholds* of the search
  remain the inherited `--lts-level` values (`[待校准]`).
* PLAN §8.2 experiment #5 (cross-validation): the analytic Mueller-Brown
  reference (§6.1) and the GFN2 HCN/HNC transition state against the P-RFO
  branch (§6.3).  A cross-code comparison against MAPLE/pysisyphus is still not
  possible in this environment and is not claimed.

---

## 7. Integration points touched outside `src/landscape/saddle/dimer.f90`

1. `tasks/ts.f90` dispatches on the method; the header prints the dimer
   parameters when `method = dimer`; the `"dimer is not implemented yet"` error
   is gone.
2. `eigenfollow.f90` exports the (renamed) phase convention routine, so the
   dimer applies *the same* rule as the eigenvector following methods instead of
   duplicating it.
3. `types/settings.f90`: the dimer block grew the fields of §1 and `n_init`
   changed from an integer (stage 1 placeholder, no consumer) to the
   `random`/`force` name of PLAN §5.3.6.
4. CLI/flags and help (`main.F90`, `xhelp.f90`), tests and meson files.

Core layers (`src/type`, `src/xtb`, `src/mctc`, `src/param`, `src/io`,
`src/disp`, `src/coulomb`) are untouched.

---

## 8. Falsifiability injections (all reverted, all re-verified green)

Each injection was applied to the *final* `dimer.f90`, rebuilt and reverted;
the last row is the reverted code.  Red test names are from the single-injection
runs, the message lines from the combined run.

| # | Injection | Red tests | First message |
|---|---|---|---|
| (i) | Eq. 21 branch condition `C < 0` → `C > 0` | 4: `dimer-translation-force`, `dimer-mb-saddle`, `dimer-no-hessian`, `dimer-reproducible` | *the perpendicular force is not kept for C < 0* |
| (ii) | Eq. 13 replaced by the paper's earlier Eq. 6 | 2: `dimer-rotation-angle`, `dimer-mb-saddle` | *Eq. 13 does not recover the large angle Fourier root* |
| (iii) | `random_seed(put=...)` removed (PLAN N10) | 2: `dimer-initial-axis`, `dimer-reproducible` | *the random axis is not reproducible for one seed* |
| (iv) | VASP rotation diagnostic removed | 1: `dimer-rotation-warning` | *the exhausted rotation did not warn* |
| — | reverted | none | `100% tests passed, 0 tests failed out of 1` |

Injection (ii) note: in the **linear** regime the two formulas coincide here to
better than 1e-9 (the finite difference cancels the `O(dtheta)` term of Eq. 6 in
this particular Fourier model), so the assertion that separates them is the
large angle case, where Eq. 6 returns 0.3420 rad instead of the exact 0.3000 rad
(and Eq. 13 returns 0.29998).  Both cases are printed by the test.

Injection (ii) additionally turns `dimer-mb-saddle` red: with the wrong rotation
branch the Mueller-Brown search does not reach the saddle, which shows that the
branch is not a cosmetic detail.

---

## 9. Residual risks and open items

1. **The initial axis decides the outcome.**  The rotation converges to the
   *nearest* eigenvector of the Hessian, not necessarily the lowest one (the
   fixed points of the rotational force field are all eigenvectors).  Measured on
   Mueller-Brown: from `(-0.75, 0.5)` 31 of 40 seeds reach the saddle, 9 reach a
   different stationary point; from `(-0.6, 0.4)` and `(-0.7, 0.45)` none of 40
   seeds reach the saddle (the rotation stops on a stiff eigenvector and the
   `C > 0` branch then has no perpendicular relaxation, so the search stalls).
   This is the documented "dimer trapped in a basin" failure mode; the standard
   remedies (a chemically motivated initial vector, several restarts, or a
   better rotation, e.g. the Fourier rotation of pysisyphus) are **not**
   implemented.  The GFN2 HCN case works with both initial axis sources.
2. **`translate_max_iter > 1`** repeats the quick-min translation without
   re-rotating the axis within a macro step; the axis can go stale.  Measured
   with `translate_max_iter = 2` on GFN2 HCN it still converges (129 steps, same
   saddle), but no systematic study was done.
3. **`step0`/`step_max` are GFN2-scale.**  On a dimensionless analytic surface
   they must be recalibrated (the unit tests do, §6.1).  The mobility rule
   (`tau` from the initial force) makes the *first* step `min(step0, step_max)`
   regardless of the force scale, which is what couples the two.
4. **`rot_alpha = 0.5` costs iterations.**  From a badly misaligned axis the
   rotation needs ~8-11 iterations to converge instead of ~4-5 at
   `rot_alpha = 1`; with the default `rot_max_iter = 5` a macro step therefore
   often ends with a partially aligned axis (5 warnings in 39 steps of the
   reference run).  The MAPLE default is kept; `--lts-rot-alpha 1` is available.
5. **No Hessian-vector product / no restart of a stalled dimer.**  The dimer uses
   two extra single points per rotation instead of an HVP; the PLAN's
   `hvp_step` field was deliberately not added (it would be an unused knob).
6. **The rotation branch changes the step count by an order of magnitude.**
   With the principal branch of Eq. 13 (the pre-fix behaviour) the
   Mueller-Brown test needed 134 macro steps for the same saddle that the
   corrected branch reaches in 14 - the wrong root wastes rotations on the
   maximising direction.  The *result* was correct in both cases on this two
   dimensional surface; on GFN2 HCN it was not (§3).
7. `--lts-*` CLI coverage: the end-to-end test uses `--lts-ninit`,
   `--lts-method` and the frozen `etemp`; the remaining dimer flags are
   covered by the unit tests (`dimer-mobility` for `dR`, `dimer-velocity-update`
   for `step_max`) and by the three error-branch CLI tests, but no per-flag
   end-to-end test was added.

---

## 10. Commands

```bash
# build (Release) and the two suites
cmake --build /tmp/xtb-land/build -j8
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
# debug build of the unit tests (bounds check + FPE traps)
cmake --build /tmp/xtb-land/build-debug -j8 --target xtb-tester
OMP_NUM_THREADS=1 /tmp/xtb-land/build-debug/test/unit/xtb-tester landscape-saddle
# end-to-end
OMP_NUM_THREADS=1 XTBPATH=$PWD /tmp/xtb-land/build/xtb hcn.xyz --gfn 2 --lts \
    --lts-method dimer --norestart
```

Final state: `ctest -R landscape` → **44/44 pass** (~1.3 s), regression subset →
**12/12 pass** (~0.2 s), no duplicate test names, Release and Debug builds
clean.

---

## 11. Files changed in this round

```
 M src/landscape/CMakeLists.txt          (register saddle/dimer.f90)
 M src/landscape/meson.build             (register saddle/dimer.f90)
 M src/landscape/saddle/eigenfollow.f90  (phase convention exported/renamed)
 M src/landscape/tasks/ts.f90            (dimer dispatch, header, docs)
 M src/landscape/types/settings.f90      (dimer fields, n_init, ninit lookup)
 M src/prog/main.F90                     (nine --lts-* flags)
 M src/xhelp.f90                          (help text)
 M test/unit/CMakeLists.txt              (dimer end-to-end + error tests)
 M test/unit/landscape_cli_check.py      (meson mirror of the dimer check)
 M test/unit/meson.build                 (meson registration)
 M test/unit/test_landscape_saddle.f90   (13 dimer unit tests)
?? src/landscape/saddle/dimer.f90
?? docs/_landscape-recon/27-m4-dimer-implementation-report.md
```

---

## 12. [最终修复轮补充] dimer 的几何依赖性与 P-RFO 不同

本报告的 dimer 验收同样使用**弯曲的 TS 猜测**（HCN（→HNC）异构化）作为起点，
但 dimer 对起点的要求与 P-RFO / B-P-RFO **结构性不同**（复核 31 的几何依赖性发现）：

- dimer **不构造 Hessian、不选模**：每个宏迭代只有 2 次单点（±`delta` 两个像），
  用轴向转动把轴对齐到最低曲率方向（`landscape_dimer_curve`/`landscape_dimer_rotate`）。
  单元测试 `dimer-no-hessian` 锁住 `n_hess = 0`。
- 因此**从极小点起步时 dimer 反而可能直接成功**，而 prfo/bprfo 需要鞍点猜测或逃逸行走。
  实测（GFN2 HCN 线性极小点 H(−1.0,0,0) Å，1.0 Å 处的近极小点）：

| 方法 | 起点 = 极小点 | 起点 = 弯曲 TS 猜测 |
|---|---|---|
| prfo | 逃逸 7 push + **5 步**，1 虚频，exit 0，E = −5.387373532908 | 4 步，1 虚频，exit 0，E = −5.387373532156 |
| bprfo | 逃逸 7 push + **7 步**，1 虚频，exit 0，E = −5.387373532839 | 5 步，1 虚频，exit 0，E = −5.387373532550 |
| dimer | **29 步**，1 虚频 −1426.73 cm⁻¹，exit 0，E = −5.387373461989（`Hessian requests: 0`） | 15 步，1 虚频 −1425.24 cm⁻¹，exit 0，E = −5.387373500230 |

（`--lts-escape-step 0` 关闭逃逸后，prfo 从同一极小点 3 步回到极小点、0 虚频、exit 1；
CLI 测试 `xtb/landscape-ts-minimum` 锁住该诊断，`xtb/landscape-ts-escape` 锁住带逃逸的成功路径。）
数据：`docs/_landscape-recon/m4-final-fix-data/acceptance/`；报告 `32-m4-final-fix-report.md`。
