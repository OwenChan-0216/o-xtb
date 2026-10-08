<!-- The development review reports cited below (the numbered reports under docs/_landscape-recon/ and docs/_simplify-recon/) and AGENTS.md are not part of this repository. -->
# Landscape suite — M7 validation guide

> Deliverable of milestone **M7** (PLAN §9.8). It answers four questions:
> *how do I reproduce the validation*, *what does each layer assert*,
> *what is deliberately not comparable*, and *what is finished and what is
> not* (§8, the completion and known-limitations list). The implementation
> report with the bug-injection evidence is
> `docs/_landscape-recon/48-m7-e2e-closeout-report.md`; the fix round that
> closed the findings of the independent review is
> `docs/_landscape-recon/51-m7-fix-report.md`.
>
> Everything here was measured on this checkout with `OMP_NUM_THREADS=1`
> (AGENTS.md §6.8: the 340× OpenMP anti-scaling of many small single points).

---

## 1. What M7 added

| Item | Where |
|---|---|
| `--ljson` — structured result of every landscape task | `src/landscape/types/json.f90`, `tasks/*.f90`, `src/prog/main.F90` |
| End-to-end chain `sp → opt → hess → freq → thermo` | `test/unit/test_landscape_e2e.f90` (`landscape-e2e`), `test/unit/landscape_e2e_check.py` (mode `chain`) |
| Layered validation script (L1/L2/L3, 15 unit suites + 2 L3 legs) | `test/unit/landscape_e2e_check.py` (mode `layers`) |
| MAPLE comparison record (topology only, **probe asserted**) | `test/unit/landscape_e2e_check.py` (mode `maple`) |
| “Result not usable ⇒ non-zero exit” unified | `src/landscape/tasks/scan.f90` (see §6) |
| `ts` evaluation counter sampled after the confirmation Hessian | `src/landscape/tasks/ts.f90` (see §4.2) |
| Fix of the latent early-failure crash of the minimiser | `src/landscape/optimize/driver.f90` (see the report §3) |

---

## 2. How to reproduce

```bash
# configure + build
cmake -S . -B /tmp/xtb-land/build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF \
      -DWITH_TESTS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/xtb-land/build -j

# all landscape checks (95 targets, ~28 s)
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape

# regression subset
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build \
    -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'

# the three layers of PLAN §8.1 in one structured report (17 checks);
# the last argument is the transition state input of the second L3 leg -
# without it that leg is simply absent from layers.json
export XTBPATH=$PWD OMP_NUM_THREADS=1
python3 test/unit/landscape_e2e_check.py layers \
    /tmp/xtb-land/build/xtb /tmp/xtb-land/build/test/unit/xtb-tester \
    <input.xyz> /tmp/e2e-layers <bent-hcn.xyz>   # writes layers.json

# one chain by hand (relative rundirs are supported)
python3 test/unit/landscape_e2e_check.py chain \
    /tmp/xtb-land/build/xtb water.xyz /tmp/e2e-chain

# the `--ljson` checks of one task (scan2d is the second command line of
# the `scan` task; it reads the same landscape_scan.json)
python3 test/unit/landscape_e2e_check.py ljson \
    /tmp/xtb-land/build/xtb water.xyz /tmp/e2e-ljson opt

# the counter semantics checks
python3 test/unit/landscape_e2e_check.py ts-counters \
    /tmp/xtb-land/build/xtb hcn.xyz /tmp/e2e-ts-counters
python3 test/unit/landscape_e2e_check.py scan-counters \
    /tmp/xtb-land/build/xtb water.xyz /tmp/e2e-scan-counters

# the MAPLE comparison record (never claims MAPLE was executed, and fails
# if the probe reports MAPLE usable - see §7.2)
python3 test/unit/landscape_e2e_check.py maple \
    /tmp/xtb-land/build/xtb hcn_ts.xyz /tmp/e2e-maple
```

Expected output of the modes (measured):

```
chain:          max dfreq 0.0100 cm^-1 (tol 0.20), dZPE 1.429e-08, dH 1.426e-08,
                dG 1.429e-08 hartree (tol 1.4e-06)
                frequencies 1539.58 3643.01 3651.17 cm^-1
chain-failure:  step 2 exited 1 and the reference step did not run
ljson:          <task> valid, counters cross-checked, byte identical, namespace ok
ljson-methods:  8 ts methods and 4 irc methods write their document
layers:         17 checks passed
maple:          executed=False importable=False missing=['ase', 'torch', 'fairchem']
                topology={'saddle_points': 1, 'endpoint_minima': 2, ...}
scan-counters:  converged run 3 valid of 3 points, unconverged run 3 unconverged
                of 3 points with status error and non-zero exit
ts-counters:    95 vs 77 evaluations, difference 18 = 1 x 6N (N=3); both agree
                with the engine report
```

The script needs a JSON parser and therefore runs under the Python interpreter
(`Python3_EXECUTABLE` of the CMake build); `test/unit/meson.build` registers the
same checks for the meson build. **Meson is not installed on this machine**, so
the meson registrations are written but unverified (as in every earlier
milestone).

---

## 3. The three layers and their criteria

| Layer | Command | What it asserts |
|---|---|---|
| **L1** analytic potentials | the 11 `xtb-tester landscape-*` suites that build no SCF: `landscape-api`, `landscape-settings`, `landscape-coords`, `landscape-hessian-update`, `landscape-optimize-math`, `landscape-cg`, `landscape-hessian`, `landscape-scan`, `landscape-saddle`, `landscape-path`, `landscape-irc` | the algorithms themselves: step sequences, convergence, geometry against the analytic solution (Müller-Brown, LEPS, Rosenbrock), constraint kernels, Hessian update formulas. |
| **L2** real GFN2 engine | `landscape-optimize-xtb`, `landscape-vib`, `landscape-failure`, `landscape-e2e` | engine boundary: bitwise reproducibility of a cold single point, cache/cost accounting, Hessian symmetry, the frequency chain, the early-failure paths. |
| **L3** end-to-end chain | `landscape_e2e_check.py chain` and the `ts-irc` leg it runs, `xtb-tester landscape-e2e` | the task chains and their output files: `opt → hess → freq → thermo` **and** `ts → irc`. |

`layers.json` records one entry per check (`layer`, `suite`, `status`,
`passed`) and the mode fails if any entry is red. The list is the complete set
of landscape unit suites of `test/unit/main.F90` (the first version of this
mode listed 6 of the 14 and the `ts → irc` leg lived only in the `maple` mode —
findings F7 of the validation round).

### 3.1 L3 acceptance: the `opt → freq` chain against `--hess`

`--lvib` (this suite) and `--hess` (the pre-existing xtb path) both build a
**numerical central-difference Hessian** (step 5·10⁻³ bohr, SCC accuracy 0.3)
and differ in exactly one respect: `--lvib` projects the mass-weighted matrix
with the **Eckart** projection (`projectHessian`), `--hess` projects the
unweighted matrix with the legacy **`trproj`**. PLAN §9.5 forbids “bitwise
equality with `--hess`” as a criterion, so the acceptance is a tolerance whose
source is stated **with the measured value it is derived from**:

| Quantity | H2O (tight minimum) | CH3OH (tight minimum) | CH3OH (`--lopt` **default** level) | Tolerance used | Measured / tolerance |
|---|---|---|---|---|---|
| max frequency difference | **0.0100 cm⁻¹** | **0.0600 cm⁻¹** | **0.8900 cm⁻¹** (‖g‖ 3.86·10⁻⁴) | 0.20 cm⁻¹ (H2O), 1.00 cm⁻¹ (CH3OH) | 20× (H2O); 17× tight / **1.12×** default (CH3OH) |
| ZPE | 1.429·10⁻⁸ Eh | 2.975·10⁻⁷ Eh | −1.71·10⁻⁶ Eh | 1.37·10⁻⁶ Eh (H2O), 2.7·10⁻⁵ Eh (CH3OH) | 96× / 91× |
| H(T) at 298.15 K | 1.426·10⁻⁸ Eh | 3.070·10⁻⁷ Eh | — | same | 96× / 88× |
| G(T) at 298.15 K | 1.429·10⁻⁸ Eh | 2.530·10⁻⁷ Eh | — | same | 96× / 107× |

(The CH3OH numbers of this table are the tight-level measurement of report 49
§1.1, **not** the older default-level run that an earlier version of this
document reported as a “tight minimum” — finding F2 of the validation round.
At the default `--lopt` level the same molecule gives 0.8900 cm⁻¹, so the
1.00 cm⁻¹ tolerance retains only **12 % margin** there; that is why the
validation script states the level of its input and why the delivered CLI
chain test uses H2O at `tight`.)

Absolute values of the table (Eh):

| System | route | ZPE | H(298.15 K) | G(298.15 K) |
|---|---|---|---|---|
| H2O | `--lvib` | 0.020124779439 | −5.046638762610 | −5.068045210878 |
| H2O | `--hess` | 0.020124765151 | −5.046638776873 | −5.068045225170 |
| CH3OH | `--lvib` | 0.045065355355 | −8.028441545302 | −8.056408109211 |
| CH3OH | `--hess` | 0.045065057893 | −8.028441852260 | −8.056408362210 |
| CO2 (linear) | `--lvib` | 0.011888568934 | −10.292932758390 | −10.317260578079 |
| CO2 (linear) | `--hess` | 0.011888551846 | −10.292932771353 | −10.317260597164 |
| C2H2 (linear) | `--lvib` | 0.026466099021 | −5.176410239961 | −5.199334884732 |
| C2H2 (linear) | `--hess` | 0.026466099055 | −5.176410239940 | −5.199334884690 |

**Provenance of the tolerances — measured, not asserted.**

* *Frequency*: the compared quantity is the residual of two rigid-body
  projectors acting on the **same** raw finite difference matrix. Measured on
  the water minimum this check drives (tight level, ‖g‖ = 7.5·10⁻⁶ Eh/bohr):
  **0.0100 cm⁻¹**, which is 20× below the 0.20 cm⁻¹ floor.
* The margin is *not* solver noise of that input: the residual grows with ‖g‖.
  Measured on the same molecule, `exp1-thermo/spread/` of report 49 §1.2:

  | displacement (bohr) | ‖g‖ (Eh/bohr) | max Δν (cm⁻¹) |
  |---|---|---|
  | 0 (minimum) | 7.5·10⁻⁶ | 0.0100 |
  | 0.02 | 3.5–3.9·10⁻² | 3.30–5.23 |
  | 0.05 | 1.6–6.3·10⁻² | 0.03–2.33 |
  | 0.10 | 2.0·10⁻²–1.4·10⁻¹ | 13.67–70.76 |
  | 0.20 | 1.5–4.0·10⁻¹ | 15.05–130.19 |

  A **default** level `--lopt` minimum (‖g‖ 3.86·10⁻⁴) already gives
  0.8900 cm⁻¹ for methanol. The 0.20/1.00 cm⁻¹ floors therefore cover “the
  same check run on a less converged minimum, on another compiler/BLAS build”,
  not “anything goes”; the arithmetic that *produces* them is
  “floor = 20× the measured value of this input” (and 17× for the tighter
  methanol tolerance at its stated level), **not** the earlier “twice 0.097”
  claim, which used a residual from a different geometry and level and made
  the factor look like 2 while the real one is 20.
* *ZPE/H/G*: the floor 1.0·10⁻⁶ Eh is **70×** the measured 1.43·10⁻⁸ Eh of
  the water minimum. The effective tolerance of a run is the larger of that
  floor and the worst-case propagation of the frequency tolerance over the
  internal modes, `0.5 · n_modes · freq_tol / autorcm`
  (`autorcm = 219474.63067`, the xtb constant): for the water chain
  (3 modes, 0.2 cm⁻¹) that is 1.37·10⁻⁶ Eh, i.e. **96×** the measured
  residual; for CH3OH (12 modes, 1.0 cm⁻¹) 2.7·10⁻⁵ Eh, 91×. It still cannot
  hide a parameter error: a 1 % frequency-scaling error moves G by
  ≈1·10⁻⁴ Eh and is caught (§5, injection iv).
* *Why not simply tighten the floor to the measured value?* Because the same
  runner is used for other molecules and inputs through its `freq_tol`
  argument, and because a cross-compiler LAPACK/BLAS build changes the last
  digits of the same finite difference matrix. The floors are stated as
  multiples of a measurement, which is checkable; a tighter floor would have
  to be re-derived per molecule and per toolchain.
* *The `--lvib` geometry is the `xtbopt.xyz` of the preceding `--lopt` step*,
  not the input file — the chain runner consumes the output of the previous
  step and fails if the file is missing.

A second, independent assertion of the Fortran test is the identity
`ZPE = ½·Σ ν_internal / autorcm` computed from `vib%freq`, which the
frequency scaling factor never touches. It makes the test sensitive to a wrong
thermochemical parameter even when both projection routes shift together
(§5, injection iv).

### 3.2 L3 acceptance: the `ts → irc` chain

`hcn-ts-irc-endpoints` (Fortran) and the `chain` mode of the script use the
bent-HCN transition state guess of `test/unit/CMakeLists.txt`:

* `--lts prfo` converges to a first-order saddle: 1 imaginary mode,
  ν_imag ≈ −1426 cm⁻¹, E = −5.387373532 Eh;
* `--lirc` (default `hpc`) integrates both directions and reaches a minimum on
  each side;
* the endpoints are attributed **from the geometry**, not from the printed
  label: HCN has the shorter H–C distance, HNC the shorter H–N distance
  (measured endpoint energies −5.504037644799 and −5.504031002295 Eh, both
  below the saddle).

The two isomer minima are nearly degenerate (ΔE ≈ 1.2·10⁻³ Eh), so no ordering
between them is asserted — only that they are different isomers.

---

## 4. `--ljson` — the structured result

Every landscape task can write `landscape_<task>.json` (`--ljson`), through the
xtb file namespace (`--namespace ns` ⇒ `ns.landscape_<task>.json`).

```json
{
  "format": 1,
  "task": "opt",
  "status": 0,
  "status_name": "ok",
  "converged": true,
  "message": "converged",
  "counters": { "n_eval": 6, "n_cache_miss": 6, "n_steps": 5, "n_imag": -1, "n_iter": 5, "n_fallback": 0 },
  "values":   { "energy": -5.07054444780945701E+000, "gnorm": 3.67697626709295011E-006, "gmax": 2.81785151009725232E-006, "etemp": 3.00000000000000000E+002, "imag_freq": 0.0, "kcal_per_mol": -3.18181468075828479E+003 },
  "flags":    { "is_saddle": false },
  "history":  { "energy": [...], "gnorm": [...], "gmax": [...], "dispnorm": [...], "dispmax": [...], "trust": [...], "method": [...] }
}
```

Design rules (they are what makes the file useful for regression comparison):

* the ten top level keys are always present and always in the same order;
* counters/values/flags are written in the order the task added them;
* reals use 17 significant digits (`es25.17e3`) — enough for a bitwise double
  round trip; **no wall time, path or random quantity is written**, so two runs
  of the same input are byte identical;
* a non-finite value is written as JSON `null`, never as a fabricated number
  (PLAN §5.5);
* `status`: `0` ok, `1` incomplete (the *result* is interpretable with
  caveats: unconverged minimisation, scan with unconverged points, imaginary
  frequency), `−1` error (no usable result; the process exits non-zero).
  `status` is a **classification of the result, not a promise about the exit
  code**: §6 lists which of these conditions the process turns into a non-zero
  exit, and an unconverged minimisation is one of them (`status: 1` **and** a
  non-zero exit, `tasks/opt.f90:169-184`), while an imaginary frequency or a
  scan with unconverged points is `status: 1` with exit 0.

`counters` are the **same numbers** the task prints on stdout, not a second
bookkeeping — `landscape_e2e_check.py ljson` cross-asserts them. The assertion
holds for every **completed** run; see the `n_cache_miss` bullet of §4.2 for the
two exceptions (`irc` has no such key, a failed band search samples late).

### 4.1 Task × `--ljson` coverage

| Task | `--ljson` written by | Test that proves it | What the test asserts |
|---|---|---|---|
| `sp` | `tasks/sp.f90` | `landscape-e2e` case `sp-ljson` (API only) | `"task": "sp"`, `"status": 0`, `"n_eval": 1`, an energy key |
| `opt` | `tasks/opt.f90` | `xtb/landscape-ljson-opt` + `landscape-e2e` `ljson-determinism` | valid JSON, key order, `n_steps`/`n_eval`/`n_cache_miss` == stdout, energy == `final energy`, byte identical, namespace |
| `scan` | `tasks/scan.f90` | `xtb/landscape-ljson-scan` + `xtb/landscape-e2e-scan-counters` | valid JSON, key order, `n_points`/`n_eval`/`n_cache_miss` == stdout, `n_valid`/`n_fail`/`n_unconverged` against the printed frame report (converged **and** unconverged run), energy == `lowest energy`, byte identical, namespace |
| `scan` (2D grid, same file) | `tasks/scan.f90` (`write_json_grid`) | `xtb/landscape-ljson-scan2d` | same as above plus `n_points == n1 * n2` and the printed `2D scan grid: n1 x n2 points`, energy == `lowest grid energy` |
| `vib` | `tasks/vib.f90` | `xtb/landscape-ljson-vib` | valid JSON, `zpe` == printed `zero point energy`, `n_imag` == 0, byte identical, namespace |
| `ts` | `tasks/ts.f90` | `xtb/landscape-ljson-ts` + `xtb/landscape-e2e-ts-counters` | valid JSON, `n_steps`/`n_eval`/`n_cache_miss`/`n_imag` == stdout, **`n_cache_miss` == the engine's `energy evaluations` of the same run** (`--lts-no-verify` lowers it by whole 6N Hessians), byte identical, namespace |
| `irc` | `tasks/irc.f90` | `xtb/landscape-ljson-irc` | valid JSON, `n_fwd`/`n_bwd` == stdout, `energy_ts` == printed value, `n_imag` == 1, byte identical, namespace |

**Method coverage.** `xtb/landscape-e2e-ljson-methods` runs **all eight `ts`
methods** (`prfo`, `bprfo`, `dimer`, `neb`, `cineb`, `autoneb`, `string`, `gsm`)
and **all four `irc` methods** (`gs`, `hpc`, `lqa`, `eulerpc`) with `--ljson`
and asserts that each writes a parseable document whose `method` counter is the
identifier of the method (1…8 and 1…4). The four band searches take a different
code path in `tasks/ts.f90` and return early, so they are covered explicitly.

`sp` has no run type of its own (`p_run_lopt/lscan/lts/lirc/lvib` are the only
landscape run types), so its document is exercised through the API in the
`landscape-e2e` unit suite.

### 4.2 Counter semantics, and the sampling point of the `ts` counter

The full specification is PLAN §12.16. The one semantic that a regression
comparison can silently get wrong is *when* a counter is sampled:

* `n_eval` is the number of objective calls for `opt`/`ts` (printed as
  `energy calls`) and the engine evaluation total for `scan`/`vib`;
* `n_cache_miss` is the engine's evaluation count on a **completed** run of
  `opt`/`scan`/`vib`/`ts` — there it equals the `landscape engine: energy
  evaluations` line of the same stdout. The two exceptions are stated rather
  than glossed over: `irc` writes no `n_cache_miss` at all (it reports
  `n_eval_fwd`/`n_eval_bwd`, one counter per direction), and a **failed** band
  search can return before the counter is sampled: `tasks/ts.f90:235` writes the
  document first and the early returns of the band path never reach the sample
  at `tasks/ts.f90:932` — `:718-724` (product unreadable), a band that fails to
  build inside the search (`path/neb.f90:739`, the case measured below),
  `:837-839` (no internal node) and `:909-913` (candidate not evaluable). The
  failures that stop before the first evaluation were **measured this round** and
  agree with the engine line (a missing product file: `n_cache_miss: 0` next to
  `energy evaluations 0`, exit 1); for the two returns that fire *after* a band
  search the field stays at the default `0` while the same stdout prints a
  non-zero engine total — that case is a **code reading, not a measured run**
  (it needs a collapsed band or an SCC failure at the candidate to trigger), the
  run exits non-zero, and the field is a default rather than a measurement;
* `n_imag = -1` means “no frequency confirmation was done” (`--lopt`,
  `--lscan`, `--sp`, and `--lts-no-verify`); `0` means “confirmed, no imaginary
  mode”. The two are **not** the same statement.
* the `scan` point bookkeeping is exact but not one number: `n_points` is the
  number of requested points, `n_fail` the points whose single point produced no
  energy (**equal** to the omitted frames the task prints in
  `wrote <log> with N frame(s), M failed point(s) omitted`),
  `n_unconverged` the points whose constraint relaxation did not converge, and
  `n_valid` the points that are **both converged and evaluated** in the 1D
  profile (`tasks/scan.f90:176-183`) but the *evaluated* points
  (`count(grid%energy_valid)`) in the 2D grid (`tasks/scan.f90:164`). The
  written frame count is the evaluated points in both cases, i.e.
  `n_points == nframe + n_fail` and, for the 1D profile,
  `n_valid <= nframe <= n_valid + n_unconverged`; the 2D grid has
  `n_valid == nframe`. `xtb/landscape-e2e-scan-counters` asserts the relations
  on a converged and on a fully unconverged run.

The `ts` task used to sample `n_cache_miss` *before* its 6N confirmation
Hessian: one and the same stdout printed `cache misses: 77` next to
`energy evaluations 95`, and the JSON carried the 77 — 95 − 77 = 18 = 6N exactly
(N = 3, finding M-1 of the fix round). The counter and the result print are now
after `confirm_saddle`, at **both** call sites (`landscape_ts` and the band
path `landscape_ts_finish`), so all three numbers of a run are the same number
and `--lts-no-verify` lowers the counter by exactly one 6N Hessian.

**Determinism is per thread count.** The document is byte identical between
two runs at the same `OMP_NUM_THREADS` (6 of 6 tasks verified) but **not**
across thread counts: the recursive maximum absolute difference at OMP = 2 and
4 is 1.8·10⁻¹² / 2.7·10⁻¹² / 3.2·10⁻¹² (opt/scan1D/scan2D), 2.4–3.7·10⁻¹⁰
(vib, two independent measurements), 1.2·10⁻¹⁰ (ts), 4.3·10⁻¹² (irc), while
**no counter changes**. Any JSON
regression baseline must therefore pin `OMP_NUM_THREADS` (the delivered ctest
targets do); a counter-level comparison is thread safe.

---

## 5. Bug-injection evidence (falsifiability)

Each injection was applied to the product code (or to the runner), the named
test was run, the failure recorded, and the code restored. Details and the
exact messages are in the report §4.

| # | Injection | Test that turned red |
|---|---|---|
| i | JSON counter `n_eval` written as `n_eval + 1` | `xtb/landscape-ljson-opt`, `landscape-e2e` `ljson-determinism` |
| ii | a random value appended to the JSON message | `xtb/landscape-ljson-opt` (byte comparison), `landscape-e2e` `ljson-determinism` |
| iii | chain runner continues after a failed step | `xtb/landscape-e2e-chain-failure` |
| iv | 1 % error in the thermochemical frequency scaling | `xtb/landscape-e2e-chain`, `landscape-e2e` `h2o-opt-freq-chain` |
| v | scan “no converged point” reverted from error to warning | `xtb/landscape-scan-max-steps`, `landscape-scan` `scan-task-unconverged` / `scan-task-no-converged-point` |
| vi | `ts` counter sampled **before** `confirm_saddle` again (i.e. the pre-fix code, the later sampling deleted for the injection) | `xtb/landscape-e2e-ts-counters` (`the same stdout prints 'cache misses: 77' and the engine reports 95`), `xtb/landscape-ljson-ts` (`the counter is 77 but the engine of the same run`) |
| vii | MAPLE probe reverted to the shallow `import maple` (the pre-fix code) | `xtb/landscape-e2e-maple` (`the deep MAPLE probe now reports MAPLE usable`) |
| viii | 1D scan document `n_unconverged + 1` | `xtb/landscape-e2e-scan-counters` (`the converged scan reports 1 unconverged and 0 failed points`) |
| ix | 2D scan document `n1 + 1` | `xtb/landscape-ljson-scan2d` (`the grid is 3 x 2 but n_points is 4`) |
| x | the `chain-failure` rundir cleanup removed, with a stale `hessian` in it | `xtb/landscape-e2e-chain-failure` (`the chain continued after a failed step (hessian exists)`) |
| xi | the projected frequencies of `--lvib` scaled by 1.0001 (`vib/modes.f90`, `freq_cm = 1.0001_wp*autorcm*ev`) | `xtb/landscape-e2e-chain` (`the chain frequencies differ from --hess by 0.3700 cm^-1`) — this is the injection that pins the **frequency** tolerance: 0.3700 > the 0.20 cm⁻¹ floor, so a sub-cm⁻¹ frequency regression is caught. A regression below the floor (≈0.2 cm⁻¹ at these frequencies) passes by design; the floor exists for less converged minima (see §3.1) |
| xii | the `--ljson` warning removed from `src/prog/main.F90` (the pre-fix behaviour: the switch is a silent no-op without a landscape run type) | `xtb/landscape-ljson-no-runtype` (`the --ljson no-op was not reported`) |
| xiii | the `--namespace` dropped from the `xtbopt.xyz`/`xtb.trj` names in `types/log.f90` (the pre-fix code) | `xtb/landscape-opt` (`landscape1.xtbopt.xyz was not written`) **and** `xtb/landscape-opt-namespace` (`--namespace c1 wrote no c1.xtbopt.xyz`) |
| xiv | the `sp` document counter written as 12 instead of 1 (`json.f90`, `n_eval + merge(11, 0, task == 'sp')`) | `landscape-e2e` (`sp-ljson`: `the single point counter of the document is not 1`). The document left behind by the red run carries `"n_eval": 12,` — the **old** substring assertion `index(text, '"n_eval": 1') > 0` matches that text, which is exactly why it was replaced by a numeric comparison (finding P2-6) |

Injections vi–x are the fix round of report 51; i–v are the delivery round of
report 49; xi–xiv are the final fix round (report 53). Every one of them was
applied with an exact-text replacement that
asserts the needle is unique, was verified to have **compiled** (the M4 lesson:
a green result from a failed build proves nothing), and was restored
byte-identically afterwards. The negative controls (the unrelated tests that
stay green) are recorded in report 51 §3: e.g. injection vi leaves
`xtb/landscape-e2e-maple` green, injection vii leaves `xtb/landscape-e2e-layers`
green.

---

## 6. “Result not usable ⇒ non-zero exit” (PLAN §12.11 INFO-3)

| Task | Outcome | Behaviour | Exit |
|---|---|---|---|
| `sp` | unconverged SCC | engine refuses the energy, `env%error` | non-zero |
| `opt` | unconverged minimisation | `env%error` | non-zero |
| `opt` | unconverged SCC at least once | `env%error` | non-zero |
| `scan` | ≥ 1 scan point failed (no energy) | `env%error` | non-zero |
| `scan` | **no** point converged (energy stays NaN) | `env%error` — **changed in M7** (was a warning) | non-zero |
| `scan` | some points unconverged, ≥ 1 converged | `env%warning`, usable minimum | 0 |
| `vib` | Hessian / analysis / thermo failed | inner routine reports `env%error` | non-zero |
| `vib` | imaginary modes present | `env%warning` (same as `--hess`) | 0 |
| `ts` | search unconverged, or not a first-order saddle, or SCC failed | `env%error` | non-zero |
| `irc` | input not a saddle, direction not built, SCC failed | `env%error` | non-zero |
| `irc` | a direction stopped by the step budget | `env%warning`, path usable | 0 |

Only the `scan` “no converged point” branch changed in M7; the other rows were
already unified (M1/M2/M4/M6) and are listed for completeness. The scan change
is covered by `xtb/landscape-scan-max-steps` (CLI) and by the two updated unit
cases, and pinned by injection (v).

---

## 7. Known non-comparabilities (do not “fix” these)

1. **`--lvib` vs `--hess` is never bitwise** — different projection conventions
   (Eckart vs `trproj`). Compare with the tolerances of §3.1 and never as an
   equality.
2. **MAPLE is not a GFN2 numerical baseline.** Every fixture of the MAPLE
   example tree drives a machine-learning potential (ANI-1xnr, AIMNet2, MACE,
   …; PLAN R-14), and PLAN N9 forbids bitwise comparison anyway (different unit
   constants: `autoaa`, `autokcal`). Only topology and order of magnitude may be
   compared. **MAPLE was not executed on this machine, and could not be**: its
   dispatcher `maple.function.dispatcher` does not even import (the Python
   packages `ase`, `torch` and `fairchem` are missing here), and even with them
   the checkpoints and the GPU stack are not part of the checkout. `maple.json`
   records `maple_executed: false`, `maple_importable: false`,
   `maple_missing_dependencies: [ase, torch, fairchem]`, a non-empty
   `maple_import_error`, the reason, and — in `maple_fixtures` — **one committed
   fixture per task** of the example tree (PLAN §9.8 asks for the record “per
   task”; the final fix round extended it from the IRC fixture alone): `sp`
   `examples/sp/sp.out` (22 atoms, energy −383.47223856 Eh), `opt`
   `examples/opt/lbfgs/inp1_traj.xyz` (55 frames), `scan`
   `examples/scan/C18_scan_final.xyz` (51 frames), `ts`
   `examples/ts/dmf/inp1_prfo_ts.xyz` (1 frame), `freq`
   `examples/freq/mw/inp1.xyz` (1 frame) and `irc`
   `examples/irc/hpc/inp1_full.xyz` (65 frames, 1 interior minimum and 1
   maximum — the 7-atom molecule of the original record). Each entry carries
   the path, the frame and atom counts and the extrema of the committed energy
   series, i.e. **properties of the committed files**, never of a MAPLE run;
   the mode *fails* if a fixture disappears from the checkout, so the record
   cannot silently go stale. Next to them `maple.json` carries this suite's own
   HCN/HNC topology (1 saddle, 2 endpoint minima).

   > **A false green was removed here.** The first version of the mode probed
   > with `python3 -c "import maple"`, which returns 0 although nothing in the
   > package can be used, and reported `maple_importable: true` next to an
   > **empty** error string. A reader of `maple.json` would have concluded that
   > the suite had been checked against MAPLE. The probe now imports the
   > dispatcher and instantiates an object, the shallow result is kept under
   > its own name (`maple_toplevel_importable`), the missing modules are named,
   > and the mode **fails** if the deep probe reports MAPLE usable — because
   > then this record and this document are stale. This is the most dangerous
   > class of defect the project can ship: it manufactures the impression of a
   > validation that never took place.
3. **IRC arc lengths are not comparable across methods.** In `gs`/`hpc`/
   `eulerpc` the `s` column is a chord summation, in `lqa` it is the integrated
   arc length (M6 handover LOW-4). The same holds for the `s_*` series of
   `landscape_irc.json`.
4. **The MAPLE frequency constant** (`2721.1383`, Hartree/Å² + amu) differs from
   xtb's `autorcm` (Hartree/bohr² + electron mass) by ≈0.04 % — never use a
   MAPLE frequency as a tight reference (PLAN §12.11 INFO-2).
5. **A rigid-body projection is mandatory.** A raw numerical Hessian of a
   non-linear molecule has no usable zero modes; the projected zero modes are
   set to exactly zero in both routes, so the frequency tables start with
   `n_zero` zeros.
6. **Meson registrations are unverified** — meson/ninja are not installed here.
7. **The `hessian` file round trip re-projects.** `--lvib` writes the
   *projected, non-mass-weighted* matrix; feeding it back with
   `--lvib-hessian file` therefore projects a second time (idempotent to
   1.0·10⁻¹⁰ Eh/bohr²). The result is the `--hess` (i.e. `trproj`) number, not
   the `--lvib` one — a 0.01 cm⁻¹ / 1.4·10⁻⁸ Eh difference. Verified live
   (`--lvib-hessian file` drops the evaluation count from 19 to 1).

---

## 8. Suite completeness and known limitations

### 8.1 Task entry points

“Entry point” means the run type and its methods as reachable from the command
line; `sp` is API only (it has no run type of its own).

| # | Entry point | Status | Test that proves it | Known limitations |
|---|---|---|---|---|
| 1 | `sp` (`tasks/sp.f90`) | **done** | `landscape-e2e` `sp-ljson`; engine determinism in `landscape-optimize-xtb` | no run type / no CLI flag — reachable through the API only; its JSON document therefore has no CLI counter cross-check |
| 2 | `opt` — sd/cg/lbfgs/bfgs/diis/rfo | **done** | `xtb/landscape-opt`, `landscape-optimize-math`, `landscape-optimize-xtb`, `landscape-cg`, `xtb/landscape-ljson-opt` | the RFO trust-radius rule is conservative uphill (M4 note); model Hessian is a CLI option, not the default |
| 3 | `scan` — 1D and 2D, relaxed/rigid | **done** | `xtb/landscape-scan*`, `landscape-scan`, `xtb/landscape-ljson-scan`, `xtb/landscape-ljson-scan2d`, `xtb/landscape-e2e-scan-counters` | some scan controls have no consumer by design (`spring_expo` affects distance constraints only); the point counters are **not** one number — `n_valid` counts the points that are converged **and** evaluated in the 1D profile and the *evaluated* points in the 2D grid (the two differ), see §4.2 |
| 4 | `vib` — numerical/model/file Hessian, RRHO thermo | **done** | `xtb/landscape-vib*`, `landscape-vib`, `xtb/landscape-ljson-vib`, `xtb/landscape-e2e-chain` | hessian provider is abstract but only numerical/model/file exist (D3); IR/Raman intensities are zero (a Hessian provider carries no dipole derivatives) |
| 5 | `ts` — `prfo` | **done** | `xtb/landscape-ts-prfo`, `landscape-saddle`, `xtb/landscape-e2e-ts-counters` | escape walk needs ~1.4 bohr of cumulative displacement on a linear minimum (calibrated, `--lts-escape-step`) |
| 6 | `ts` — `bprfo` | **done** | `landscape-saddle` (unit, both P-RFO variants), `xtb/landscape-e2e-ljson-methods` (document) | no dedicated CLI target of its own; the shared `ts` CLI paths cover the code it has in common with `prfo` |
| 7 | `ts` — `dimer` | **done** | `xtb/landscape-ts-dimer`, `xtb/landscape-ts-minimum`, `xtb/landscape-ts-escape` | needs no Hessian but converges to a slightly different saddle than P-RFO (7.7·10⁻⁵ bohr RMSD on Müller-Brown) |
| 8 | `ts` — `neb` | **done** | `xtb/landscape-path-cli`, `landscape-path` | path methods need `--lts-product` |
| 9 | `ts` — `cineb` | **done** | `xtb/landscape-e2e-ljson-methods`, `landscape-path` | the climbing switch is a two-stage criterion with its own threshold |
| 10 | `ts` — `autoneb` | **done** | `xtb/landscape-path-autoneb`, `xtb/landscape-path-autoneb-depth-limit` | depth limit is a fixed budget (tested) |
| 11 | `ts` — `string` | **done** | `xtb/landscape-path-string`, `landscape-path` | spline/alignment switches exist and are tested (`--lts-no-string-spline`, `--lts-no-align`) |
| 12 | `ts` — `gsm` (growing string) | **done** | `xtb/landscape-e2e-ljson-methods`, `landscape-path` | the growth is the string algorithm itself; no separate growth schedule |
| 13 | `irc` — `gs` | **done** | `xtb/landscape-irc-cli`, `landscape-irc` (35 cases) | **open item (PLAN §6.5)**: the sphere-relaxation step budget vs. the sphere radius (`micro` steps 1.8–2.4 vs radius 0.05) — the equality-constrained Lagrange repair is **deferred on purpose** to keep the M6 baseline intact |
| 14 | `irc` — `hpc` (**default**) | **done** | `xtb/landscape-irc-pc`, `landscape-irc`, `xtb/landscape-irc-knobs` | arc length is a chord summation (not comparable with `lqa`) |
| 15 | `irc` — `lqa` | **done** | `xtb/landscape-irc-cli`, `landscape-irc` | arc length is the integrated one — do not compare `s` across methods |
| 16 | `irc` — `eulerpc` | **done** | `xtb/landscape-irc-pc`, `landscape-irc` | the forward direction can stop on the signal (c) criterion before (b) |

That is **16 reachable entry points**: `sp`, `opt`, `scan`, `vib`, the eight
`ts` methods (`prfo`, `bprfo`, `dimer`, `neb`, `cineb`, `autoneb`, `string`,
`gsm`) and the four `irc` methods (`gs`, `hpc`, `lqa`, `eulerpc`). All of them
are `done` in the sense of “implemented, tested and reachable”; none is stubbed
or placeholder. The limitations column and §8.2 are the honest part.

### 8.2 Not finished, deferred, or deliberately excluded

| Item | State | Where it is recorded |
|---|---|---|
| **IRC `gs` sphere-relaxation (Lagrange) repair** | **deferred on purpose** — accepted with a measured route; the current behaviour is pinned by tests | PLAN §6.5; AGENTS.md M6 block |
| **DMF / cyipopt / Ipopt optimiser** | **excluded (D2)** — needs an external library | PLAN §11; AGENTS.md §1 |
| **batch/GPU `blbfgs` / B-PRFO** | **excluded (D2)** | PLAN §11 |
| **ML-potential calculators** (ANI-1xnr, AIMNet2, MACE, …) | **excluded (D2)** | PLAN §11, R-14 |
| **parmfit** | **excluded (D2)** | PLAN §11 |
| **MD ensembles** | **excluded (D2)** | PLAN §11 |
| **analytic Hessian** | not implemented; the provider is an abstract type so it can be added (D3) | PLAN §5.2, AGENTS.md §1 |
| **MAPLE executed as a numerical reference** | **not done and not possible here** — dispatcher does not import (`ase`/`torch`/`fairchem` missing); only the committed fixtures are read, one per task (`sp`, `opt`, `scan`, `ts`, `freq`, `irc`), and only their topology/frame counts are compared | §7.2, `maple.json` |
| **`sp` on the command line** | not implemented (API only) | §4.1 |
| **IR/Raman intensities in `--lvib`** | zero by design (no dipole derivatives in the Hessian provider) | PLAN §5.3.8 |
| **Meson/ninja verification** | impossible here (not installed) | §7.6, PLAN R-16 |
| **`--lvib` ↔ `--hess` bitwise equality** | never a criterion (different projection conventions) | PLAN §9.5, §3.1 |
| **IRC arc length across methods** | not comparable (`gs`/`hpc`/`eulerpc` chord vs `lqa` integrated) | §7.3, M6 handover LOW-4 |
| **`vib_normal_modes` index convention** | rows are Cartesian components, columns (groups) are modes — opposite of the common reading | PLAN §12.11 INFO-1 |
| **PBC / cell optimisation** | **excluded (D2, PLAN §11)** — the guard *is* implemented: `mol%npbc > 0` ⇒ `env%error("landscape tasks do not support periodic boundary conditions yet")` and return, no silent degradation (`landscape_driver.f90:73-77`); cell optimisation is not offered at all | PLAN §11 |
| **Internal coordinates (DLC/HDLC/redundant) as the TS/IRC step space** | **excluded (PLAN §11)** — the step space is mass-weighted Cartesian by design; the internal-coordinate machinery is used for the scan constraints and the Hessian transformation only | PLAN §11 |
| **`bias_path` metadynamics path, `modefollow`, `intmodes`** | **excluded (PLAN §11)** — kept untouched in xtb, deliberately **not** depended on by this suite (`grep bias_path src/landscape` = no hits) | PLAN §11 |
| **Global optimisation / GA / random search / MECI** | **excluded (PLAN §11)** — outside the D2 task matrix | PLAN §11 |
| **torch / GPU tensor backend** | **excluded (PLAN §11)** — conflicts with D1 “no new dependency”; every algorithm is pure Fortran | PLAN §11 |
| **Rewriting the thermo (RRHO) layer or the frequency printout** | **not done on purpose (PLAN §11)** — the suite is a thin wrapper around `main_freq`/`src/thermo.f90:79` and only exposes parameters (§5.3.8 of the PLAN) | PLAN §11 |
| **`$landscape` xcontrol handler** | **not implemented** — PLAN §12.4 marks it “optional, from M2”; no `set_landscape` is registered (`grep set_landscape src/` = 0 hits), so every landscape setting comes from the CLI/API | PLAN §12.4 |

### 8.3 Reproducible verification entry points

| What | Command | Expected |
|---|---|---|
| all landscape targets | `OMP_NUM_THREADS=1 ctest --test-dir <build> -R landscape` | **93/93 passed** |
| regression subset | `OMP_NUM_THREADS=1 ctest --test-dir <build> -R 'Singlepoint\|GFN\|model-hessian\|optimizer\|Argparser\|CAPI'` | **12/12 passed** |
| no duplicate test names | `grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt \| sort \| uniq -d` | empty |
| L1+L2+L3 report | `python3 test/unit/landscape_e2e_check.py layers <xtb> <tester> <input.xyz> <rundir> <hcn.xyz>` | `layers: 17 checks passed`; `layers.json` |
| thermo chain | `… chain <xtb> <input.xyz> <rundir>` | `max dfreq 0.0100 cm^-1 (tol 0.20), dZPE 1.429e-08 …` |
| `ts` counter sampling | `… ts-counters <xtb> <hcn.xyz> <rundir>` | `95 vs 77 evaluations, difference 18 = 1 x 6N (N=3)` |
| scan counters | `… scan-counters <xtb> <water.xyz> <rundir>` | converged 3/3 valid; unconverged 3/3, status error, non-zero exit |
| MAPLE record | `… maple <xtb> <hcn.xyz> <rundir>` | `executed=False importable=False missing=['ase', 'torch', 'fairchem']` |
| `--ljson` of one task | `… ljson <xtb> <input.xyz> <rundir> <task>` | `valid, counters cross-checked, byte identical, namespace ok` |

All of the above are registered as ctest targets as well (`xtb/landscape-*`,
0.1–8 s each), so the table is a manual entry point, not a second test suite.
