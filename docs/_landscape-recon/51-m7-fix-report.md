# M7 fix round — report 51

> Round: fix of the findings of the independent review of the M7 delivery
> (`50-m7-independent-review.md`, verdict “conditional accept: CRITICAL 0 /
> HIGH 0 / MEDIUM 3 / LOW 9 / INFO 8”) plus the validation round
> (`49-m7-validation-experiments.md`, findings F1–F11).
>
> **Note on the input.** `50-m7-independent-review.md` **was not on disk** in
> this checkout when this round started (`ls docs/_landscape-recon/` ends at
> `49-m7-validation-experiments.md`; the review workflow that produced it,
> `m7fix-workflow.js`, is present but unwritten). The findings were therefore
> worked from (a) the task text, which lists them, and (b) `49`, which is the
> validation round the review built on and which enumerates the same F-numbers
> with raw evidence. Where a finding is identified only by a number from `50`
> (L1, L3–L6, I2) its content is taken from the task text; nothing was assumed
> beyond that, and §7 records the disposition of every finding of `49` as well.
>
> Everything below was measured on this checkout with `OMP_NUM_THREADS=1`
> (AGENTS.md §6.8). No commit was made (the parent session commits).

---

## 0. Verdict and summary of changes

| # | Finding | Severity | Fix |
|---|---|---|---|
| M-1 | `ts` samples `n_cache_miss` **before** `confirm_saddle`: one stdout prints `cache misses: 77` next to `energy evaluations 95`; JSON carries the 77 | MEDIUM | sampling (and the result print) moved **after** the confirmation, at both call sites; new CLI check `xtb/landscape-e2e-ts-counters`; PLAN §12.11 INFO-5 |
| M-2 | `maple_importable: true` next to an **empty** error although MAPLE cannot import its dispatcher — a false green | MEDIUM | the probe now imports the dispatcher and instantiates an object, names the missing packages, keeps the shallow result under its own key, and **fails the check** if the deep probe ever reports MAPLE usable |
| M-3 | PLAN untouched in the round: 1511 “`--ljson` not implemented”, 1805 stale exit semantics, §12.16 missing, §9.8 not backfilled | MEDIUM | PLAN §9.8, §12.11, §12.16 written; 1511/1805 corrected |
| L-1 | tolerance provenance arithmetic wrong (“2× 0.097”, “5× 1.8e-8”; real factors 20× / 70×) | LOW (doc) | honest statement with the measured values and the real factors, in the runner and in the validation guide |
| F1 | `landscape-e2e-chain-failure` fails on stale artefacts in its rundir (flaky) | LOW | rundir removed at entry (root cause, not a sleep or a weakened assertion) |
| F2 | validation guide reports the **default** level CH3OH number (0.8900) as a “tight minimum” | LOW | both levels stated, 12 % margin at the default level called out |
| F4 | `xtb/landscape-ljson-scan` does not cross-assert `n_eval` | LOW | added (`n_eval`, `n_cache_miss` vs the engine report) |
| F5 | runner fails with a misleading message on a relative rundir | LOW | `os.path.abspath` on exe/inp/rundir in the runner |
| F7 | `layers` covered 6 of 14 unit suites and lacked the `ts → irc` leg | LOW | all 15 suite targets + both L3 legs (17 checks) |
| L3/L4/L5/L6 | 2D scan JSON and `n_valid`/`n_fail`/`n_unconverged` untested | LOW | `xtb/landscape-ljson-scan2d` + `xtb/landscape-e2e-scan-counters` (converged and unconverged run) |
| I2/F8 | JSON not byte identical across OMP thread counts | INFO | recorded in PLAN §12.16 and in §4.2 of the validation guide (re-measured) |

Deliverable of the round: `docs/xtb-landscape-M7-validation.md` §8, the
**“suite completeness and known limitations”** list (task entry points, deferred
/D2-excluded items, reproducible verification entry points).

Final state: build **0 warnings**; `OMP_NUM_THREADS=1 ctest -R landscape`
**93/93 passed** (was 90); regression subset **12/12**; no duplicate
`add_test` names; no staged files.

---

## 1. M-1 — the `ts` evaluation counter

### 1.1 The defect, reproduced

One run, one stdout (`/tmp/m7fix/ts/stdout.txt`, pre-fix binary):

```
 steps:          4
 energy calls:   5
 cache misses:   77          <- sampled before the confirmation Hessian
 ...
 saddle confirmation - imaginary modes: 1
 ...
 landscape engine: energy evaluations 95
 landscape engine: cache hits         0
 landscape engine: Hessians           5
```

`95 − 77 = 18 = 6N` for N = 3: exactly one central-difference confirmation
Hessian (2·3N). The JSON carried the 77 while the engine report of the *same
run* printed 95, and `landscape_e2e_check.py ljson` cross-checked the JSON
against the task's own `cache misses` line — i.e. it verified the **search-only**
number and called it correct.

### 1.2 The fix (option (a): one number, sampled after the confirmation)

Option (a) was chosen over (b) (two named fields) because the suite already has
one meaning for this counter in `opt`/`scan`/`vib`/`sp` (measured in report 49
§2.3: cache misses == engine evaluations, 7/7, 43/43, 19/19), and because a
second field would have kept the ambiguity alive for every reader who compares
two tasks. With (a) *all* tasks have the same rule: **the counter is the
complete run**.

`src/landscape/tasks/ts.f90`, both call sites:

* `landscape_ts` (single geometry) — `result%n_cache_miss = engine%n_eval` and
  the `result%write_log` / `conv%write_log` block moved to **after**
  `confirm_saddle` (the print has to move with the sample, otherwise the *printed*
  number would keep the old value and a new stdout/JSON mismatch would appear);
* `landscape_ts_finish` (the band path, NEB/CI-NEB/AutoNEB/string/GSM) — same
  move; the candidate file write stays before the confirmation, the result print
  and the `xtbts.*` files after it.

Nothing else was touched: the search, the trust radius, the failure messages and
the exit codes are unchanged, so the M4/M6 acceptance numbers and the failure
semantics cannot move (§4 verifies this).

### 1.3 After the fix (same input, same binary options)

```
 saddle confirmation - imaginary modes: 1
 most negative frequency:         -1426.12 cm^-1
 confirmation: first order saddle point
 --------------------------------------------------------------
 landscape: converged
 converged:      T
 steps:          4
 energy calls:   5
 cache misses:   95          <- complete run
 final energy:        -5.387373532156 Eh
 ...
 --------------------------------------------------------------
 wrote xtbts.xyz
 wrote xtbts.log
 landscape engine: energy evaluations 95
```

| run | printed `cache misses` | engine `energy evaluations` | JSON `n_cache_miss` |
|---|---|---|---|
| before | 77 | 95 | 77 |
| after, with confirmation | **95** | **95** | **95** |
| after, `--lts-no-verify` | **77** | **77** | **77** |
| difference | | | **18 = 6N (N = 3)** |

### 1.4 The assertions that now pin it

* `xtb/landscape-ljson-ts` — the JSON counter must equal the
  `landscape engine: energy evaluations` number of the same stdout. Injection
  (below) shows the message it produces: *“the counter is 77 but the engine of
  the same run reports 95”*.
* `xtb/landscape-e2e-ts-counters` (new, `landscape_e2e_check.py` mode
  `ts-counters`) — runs the same search with and without
  `--lts-no-verify` and asserts
  1. `cache misses` == engine total for **each** run,
  2. JSON == printed == engine for each run,
  3. `confirmed − unconfirmed` is a **positive multiple of 6N** (measured
     **95 − 77 = 18 = 1 × 6N**, N = 3).

```
$ python3 test/unit/landscape_e2e_check.py ts-counters <xtb> <hcn.xyz> /tmp/tc
ts-counters: 95 vs 77 evaluations, difference 18 = 1 x 6N (N=3); both agree with the engine report
```

### 1.5 Falsifiability (injection vi, semantically equivalent to the old logic)

The first attempt at this injection **failed to be a valid mutation** — it added
a pre-confirmation sample without deleting the post-confirmation one, so the
later assignment still won and every test stayed green. That is the M4 lesson
(AGENTS.md §6) and it is recorded here because it happened *in this round*: the
injection was redone as a **move** (add the old sample, delete the new one),
which is exactly the pre-fix code.

| injection | build | test | result |
|---|---|---|---|
| sampling point moved back before `confirm_saddle` (post-confirmation sample deleted) | `compiled: True` | `xtb/landscape-e2e-ts-counters` | **RED** — `FAIL: confirmed: the same stdout prints 'cache misses: 77' and the engine reports 95` |
| same | | `xtb/landscape-ljson-ts` | **RED** — `FAIL: landscape_ts.json: the counter is 77 but the engine of the same run reports 95` |
| same | | `xtb/landscape-e2e-maple` (negative control) | green |
| file restored, rebuilt | `restored: True` | all three | green again |

---

## 2. M-2 — `maple_importable` was a false green

### 2.1 Before and after, same machine, same checkout

Old probe (`python3 -c "import maple"`, i.e. the code of the delivery):

```
OLD probe (shallow) returncode: 0
OLD stderr ->  import_error = ''
OLD maple_importable = True
```

so the delivered `maple.json` said

```json
"maple_importable": true, "maple_import_error": "", "maple_executed": false
```

while nothing in the package can be used:

```
$ python3 -c 'from maple.function.dispatcher import Dispatcher'
  File ".../maple/function/dispatcher/dispatcher.py", line 3, in <module>
    from ase import Atoms
ModuleNotFoundError: No module named 'ase'
```

New record (`python3 test/unit/landscape_e2e_check.py maple …`):

```
maple: executed=False importable=False missing=['ase', 'torch', 'fairchem'] topology={'saddle_points': 1, 'endpoint_minima': 2, ...}

maple_toplevel_importable  = True      <- the shallow import, kept but renamed
maple_importable           = False     <- dispatcher import + instantiation
maple_import_error         = "ModuleNotFoundError: No module named 'ase'"
maple_missing_dependencies = ['ase', 'torch', 'fairchem']
maple_not_executed_reason  = "no MAPLE job was run here.  The dispatcher itself cannot be
                              imported in this environment (missing Python packages: ase,
                              torch, fairchem; ModuleNotFoundError: No module named 'ase'),
                              so no task can be dispatched at all; and even with those
                              packages the example tree drives machine learning potentials
                              (ANI-1xnr, AIMNet2, MACE, ...) whose checkpoints and GPU stack
                              are not part of the checkout. ..."
```

### 2.2 What was changed

* the probe is now a **real** attempt: `from maple.function.dispatcher import
  Dispatcher; from maple.function.dispatcher.jobABC import JobABC; Dispatcher`
  (`maple_import_probe` records the exact command);
* `maple_importable` is true only if that command exits 0 — i.e. the dispatcher
  imported **and** the object was instantiated;
* the shallow `import maple` result survives as
  `maple_toplevel_importable` (it is a true statement, it is just not the one
  that answers “can MAPLE run anything?”);
* the failing import's last stderr line goes into `maple_import_error`, and the
  missing packages `ase`/`torch`/`fairchem` are probed individually into
  `maple_missing_dependencies`; the reason text names them;
* `maple_not_executed_reason` is now set on **both** branches (it used to be
  set only when the committed fixture existed).

### 2.3 The test, and why it is not vacuous

`xtb/landscape-e2e-maple` now asserts:

1. `maple_importable == (maple_import_error == "")` (the probe and the record
   cannot disagree);
2. **`maple_importable` must be false in this environment** — if the deep probe
   ever succeeds, the check fails with “the record, the reason text and
   `docs/xtb-landscape-M7-validation.md` have to be rewritten by hand before
   this check may pass again”. This is the anti-false-green guard: a green
   `importable` would make the delivered record stale, and this checkout's
   record states MAPLE was not run;
3. `maple_executed` must be false;
4. on a failing probe the error string must be non-empty (the empty string is
   exactly what the previous round shipped).

Both branches assert something, so the check cannot be satisfied vacuously.

Injection vii — the probe reverted to the shallow import (the pre-fix code):
`xtb/landscape-e2e-maple` **RED** (`FAIL: the deep MAPLE probe now reports MAPLE
usable; …`), `xtb/landscape-e2e-layers` green (negative control).

### 2.4 Why this was the most dangerous finding of the round

Every other finding of the round is visible in a number, a file or an exit code.
This one was a **statement about what had been validated** that was not true: a
machine-readable record saying “MAPLE is importable here” next to an empty error
field invites a reader (human or agent) to conclude that the suite's task matrix
had been cross-checked against the reference implementation. It had not — MAPLE
cannot dispatch a single job on this machine. False greens are the one class of
defect that survives review *because* the artefact looks like evidence; it is
now removed at the source (the probe), at the record (the named missing
packages), at the test (the assertion), and in the document (§7.2 of the
validation guide carries the removal in a call-out).

### 2.5 No other false green of this shape

Both rounds asked whether the same pattern exists elsewhere. A sweep of
`src/landscape/**` and `test/unit/*.py` for `*_importable` / `available` /
`installed` / `*_ok` semantics finds exactly one availability **probe** (this
one); the other hits are `env%warning`s or result messages that describe a
genuine fallback and are printed on stdout
(`driver.f90:168,181` “initial Hessian unavailable, using hlow*I”,
`prfo.f90:448,473` / `dimer.f90:731,741` “initial transition vector/axis
unavailable”, `numhess.f90:111` ODLR not implemented, `thermo.f90:128` no dipole
derivatives). Each of those is a *reported* degradation with a named test, not a
success claim. The `status` field of the JSON documents is a third case and is
checked against the process exit code by the CLI targets.

---

## 3. M-3 — PLAN backfill (diff summary)

`git diff --stat docs/xtb-landscape-PLAN.md` → **155 changed lines** (4 hunks):

| hunk | content |
|---|---|
| `@@ -1359 +1360,36 @@` | **§9.8 backfilled**: actual deliverables (files, 6 task hooks, 13 ctest targets), the four-system acceptance table (dfreq **0.0100 / 0.0600 / 0.0000 / 0.0000**, dZPE, dH, dG in Eh), the honest tolerance provenance (20× / 70× and the effective 96×, with the reason the margin is needed), the linear-molecule 0.0000 result, the independent recompute, the chain measurements, the MAPLE-not-run fact |
| `@@ -1511 +1547 @@` | the CLI table row: `--ljson` **未实现** → **已实现（M7，见 §12.16）** |
| `@@ -1802,4 +1838,37 @@` | **§12.11**: INFO-3 rewritten — the scan “no converged point” branch **is now `env%error`** (the old note promised this change and described the old behaviour), with the three-row semantics table and the tests that pin it; **INFO-4** new: the `n_imag = -1` sentinel; **INFO-5** new: the `ts` counter sampling rule (M-1), including the “same stdout” relation, the `--lts-no-verify` difference and the test/injection that pin it |
| `@@ -2036 +2105,75 @@` | **§12.16 added**: `--ljson` specification — no new run type; file name and namespace; the 10-key schema and key order; the flat history pool; 17-digit reals and `null`; counter semantics **per task including sampling time**; the “status ↔ exit code” table; determinism (byte identical per thread count, **not** across thread counts → any JSON baseline must pin `OMP_NUM_THREADS`); the tests and the injections |

The PLAN now contains no statement that contradicts the code, and §9.8/§12.16
cross-reference each other and the reports.

---

## 4. Regression: the M7 acceptance numbers and the M0–M6 behaviour

The only product-code change of the round is `src/landscape/tasks/ts.f90`
(sampling/print position). The four-system acceptance table was re-measured on
the **fixed** binary (`docs/_landscape-recon/m7-e2e-data/exp1-thermo/<system>/xtbopt.xyz`,
`--lvib` vs `--hess`, `OMP_NUM_THREADS=1`):

```
system    max dfreq         dZPE           dH           dG  modes
h2o          0.0100   1.4288e-08   1.4263e-08   1.4292e-08      3
ch3oh        0.0600   2.9746e-07   3.0696e-07   2.5300e-07     12
co2          0.0000   1.7088e-08   1.2963e-08   1.9085e-08      4
c2h2         0.0000  -3.4000e-11  -2.1000e-11  -4.2000e-11      7
```

digit for digit the numbers of report 49 §1.1 (H2O 0.0100 / 1.429·10⁻⁸; CH3OH
0.0600 / 2.975·10⁻⁷ / 3.070·10⁻⁷ / 2.530·10⁻⁷; CO2 0.0000; C2H2 0.0000). The
chain test reproduces its acceptance line as well:

```
chain: max dfreq 0.0100 cm^-1 (tol 0.20), dZPE 1.429e-08, dH 1.426e-08, dG 1.429e-08 hartree (tol 1.4e-06)
chain: frequencies 1539.58 3643.01 3651.17 cm^-1
```

M4/M6 CLI targets that read the `ts` stdout all still pass (`xtb/landscape-ts-prfo`,
`-ts-dimer`, `-ts-minimum`, `-ts-escape`, `-ts-etemp`, `-ts-namespace`,
`landscape-path-cli`, `xtb/landscape-path-autoneb*`, `xtb/landscape-path-string*`,
`xtb/landscape-ljson-methods`), and the band path (`landscape_ts_finish`, the
second call site) is exercised by the path targets — 93/93 landscape targets are
green. The reordering of the result block to *after* the saddle confirmation has
a visible side effect that is an improvement, not a regression: for a converged
search that lands on a minimum the block now prints `converged: F` **after** the
`confirmation: minimum (0 imaginary modes)` line instead of before it, so the
verdict and the diagnosis of the same stdout agree; the exit status (non-zero,
`xtb/landscape-ts-minimum`) is unchanged.

Other claims re-verified live this round:

| claim | command | measured |
|---|---|---|
| `--lvib-hessian file` reuses the Hessian instead of recomputing | `--lvib` on water, then the same with `--lvib-hessian file --lvib-hessian-file hessian` | `energy evaluations 19` → **1** |
| JSON is not byte identical across thread counts, counters are | `--lvib --ljson` at OMP 1 / 2 / 4 | max abs Δ = **3.65·10⁻¹⁰** (OMP 2) / **3.12·10⁻¹⁰** (OMP 4) over 9 float fields, **no counter differs** (report 49 measured 2.4·10⁻¹⁰; both orders recorded in PLAN §12.16) |
| the layers report covers the whole suite | `… layers …` | **17 checks passed** (11 L1 + 4 L2 + 2 L3) |

---

## 5. L-1 — the tolerance provenance, corrected

The old text argued the tolerances as “twice the measured 0.097 cm⁻¹” and “five
times the measured 2.0·10⁻⁸ hartree”, which described a **different geometry**
than the check drives. Measured on the input the check actually uses (H2O,
`tight`, ‖g‖ 7.5·10⁻⁶): **0.0100 cm⁻¹ / 1.43·10⁻⁸ Eh**, i.e. the real factors are
**20×** (frequency) and **70×** (thermo floor; the *effective* tolerance of the
H2O chain is 1.37·10⁻⁶ Eh from the mode-count propagation term = 96×). Kept the
floors rather than tightening them, because:

* they are used for other molecules and inputs through the `freq_tol`
  argument, and
* the compared quantity is a **projector residual** that grows with ‖g‖, so the
  margin is what makes the check meaningful for a *less* converged minimum: the
  measured ‖g‖ → Δν table (report 49 §1.2, reproduced in the guide) reaches
  3.3–5.2 cm⁻¹ at 0.02 bohr from the minimum and 0.8900 cm⁻¹ for a
  default-level `--lopt` methanol.

Files changed: the `FREQ_TOL`/`THERMO_TOL` comments and the `chain` docstring of
`test/unit/landscape_e2e_check.py`, and §3.1 of the validation guide (which now
carries the measured value, the factor and the ‖g‖ table, and states that the
old “2×/5×” arithmetic was wrong).

---

## 6. The remaining findings

| # | disposition | evidence |
|---|---|---|
| F1 (flaky chain-failure) | **fixed, root cause** | `shutil.rmtree(rundir)` at the entry of `check_chain_failure` (the test asserts the *absence* of artefacts, so the rundir must start empty). Verified both ways: with two stale artefacts present (`hessian`, `vibspectrum`) the fixed check **passes** and the rundir is clean; with the cleanup removed by injection the same stale file gives `FAIL: the chain continued after a failed step (hessian exists)` — i.e. the reported flake reproduces exactly and is gone |
| F2 (CH3OH level) | **fixed** | guide §3.1 lists CH3OH at `tight` (**0.0600 cm⁻¹**, ΔZPE 2.975·10⁻⁷) **and** at the `--lopt` default (**0.8900 cm⁻¹**, ΔZPE −1.71·10⁻⁶), and says the 1.00 cm⁻¹ tolerance keeps only **12 % margin** at the default level; the runner docstring carries the same |
| F3 (= M-1) | fixed | §1 |
| F4 (`scan` `n_eval`) | **fixed** | `expected["scan"]` cross-asserts `n_eval`/`n_cache_miss` against `landscape engine: energy evaluations`; injection viii (see §6.1) plus report 49's own `n_eval + 1` injection now reds this target |
| F5 (relative rundir) | **fixed** | `run()` resolves `exe`, `inp`, `rundir` with `os.path.abspath`; verified `… chain <xtb> <h2o.xyz> relative-run` → `chain: max dfreq 0.0100 …` exit 0, and `… layers … relative-layers <hcn.xyz>` → `layers: 17 checks passed` |
| F6 (= M-2) | fixed | §2 |
| F7 (layers coverage) | **fixed** | 11 L1 + 4 L2 suites (the complete set of `test/unit/main.F90`) + the `chain` and the new `ts-irc` L3 leg ⇒ `layers: 17 checks passed`; the `ts → irc` leg is now shared by the `layers` and `maple` modes (it used to exist only inside `maple`), and the guide §3 no longer overstates the claim |
| F8 / I2 (OMP) | **documented** | PLAN §12.16 (with both measurements) and guide §4.2; ctest pins `OMP_NUM_THREADS=1` |
| F9 (`n_imag = -1`, per-task `n_eval`) | **documented** | PLAN §12.11 INFO-4, guide §4.2 (including the explicit “`-1` is not `0`” warning) |
| F10 (`--lvib` hessian file re-projects) | **documented** | guide §7.7 + re-measured live (19 → 1 evaluations) |
| F11 (unit determinism case cannot see builder-level non-determinism) | **accepted, no action** | the CLI check covers it (report 49 §6 note); the pair of injections 2/3 covers both levels |
| L3/L4/L5/L6 (2D scan, `n_valid`/`n_fail`/`n_unconverged`) | **fixed** | new target `xtb/landscape-ljson-scan2d` and mode `scan-counters`; the guide §4.1/§4.2 and PLAN §12.16 record the exact relations (`n_points == nframe + nomitted`, `n_fail == nomitted`, `n_valid ≤ nframe ≤ n_valid + n_unconverged`) |

### 6.1 New-injection evidence (F4, L3–L6)

| injection | build | test | result |
|---|---|---|---|
| 1D profile `n_unconverged + 1` | `compiled: True` | `xtb/landscape-e2e-scan-counters` | **RED** — `FAIL: the converged scan reports 1 unconverged and 0 failed points` |
| 2D grid `n1 + 1` | `compiled: True` | `xtb/landscape-ljson-scan2d` | **RED** — `FAIL: landscape_scan.json: the grid is 3 x 2 but n_points is 4` |
| `chain-failure` cleanup removed, stale `hessian` present | n/a (Python) | `xtb/landscape-e2e-chain-failure` | **RED** — `FAIL: the chain continued after a failed step (hessian exists)` |

### 6.2 Findings of `49` that were already “report only” and are now closed by code

F3 (=M-1) and F6 (=M-2) were marked “report only (no `src/` edits allowed)” in
the validation round; this fix round was allowed to edit, so both are closed in
the product rather than in prose. F2, F5, F7 became code/document changes rather
than a restatement of the measurements.

---

## 7. Test inventory after the round

| target | mode | what it is new for |
|---|---|---|
| `xtb/landscape-ljson-scan2d` | `ljson scan2d` | the 2D scan document (L3) |
| `xtb/landscape-e2e-ts-counters` | `ts-counters` | M-1: the sampling point and the 6N difference |
| `xtb/landscape-e2e-scan-counters` | `scan-counters` | L4–L6: point bookkeeping, converged and unconverged |

`ctest -N -R landscape` → **93** tests (was 90); `grep -oE 'add_test\("[^"]+"'
test/unit/CMakeLists.txt | sort | uniq -d` → empty. Every new target is
registered in **both** `test/unit/CMakeLists.txt` and `test/unit/meson.build`
(the meson file cannot be executed here — meson is not installed, unchanged from
every earlier milestone — and the runner is Python-driven, so there is no
`test/unit/main.f90` case list involved; no new **Fortran** unit case was added).

---

## 8. “Must run” verification list (review 50's list, executed)

`50-m7-independent-review.md` is not on disk, so the list could not be copied
verbatim; every check that the task names or that `49` requires was run and is
quoted above or below.

| # | check | result |
|---|---|---|
| 1 | `cmake --build /tmp/xtb-land/build -j` after touching the changed sources | **0 warnings** |
| 2 | `OMP_NUM_THREADS=1 ctest -R landscape` | **93/93 passed** (27.5 s) |
| 3 | `ctest -R 'Singlepoint\|GFN\|model-hessian\|optimizer\|Argparser\|CAPI'` | **12/12 passed** |
| 4 | unique test names (`ctest -N` count + `uniq -d`) | 93 registered, no duplicate |
| 5 | four-system dfreq/dZPE/dH/dG | reproduce report 49 exactly (§4) |
| 6 | chain acceptance line | unchanged (§4) |
| 7 | `--lvib-hessian file` cost | 19 → 1 evaluations (§4) |
| 8 | OMP 1/2/4 JSON | 3.7·10⁻¹⁰ max, counters stable, not byte identical (§4) |
| 9 | `layers` | 17 checks, `ts-irc` leg included (§6 F7) |
| 10 | relative rundir | `chain` and `layers` both work (§6 F5) |
| 11 | `maple` probe | `importable=False`, non-empty error, three missing packages (§2) |
| 12 | injections | vi (ts sampling), vii (maple shallow), viii (scan `n_unconverged`), ix (2D `n1`), x (stale artefact) — all red, negative controls green, all restored byte-identically and rebuilt green |
| 13 | `git status` | no staged files; the 21 modified + 5 untracked files are the inherited M7 delivery plus this round's edits |

---

## 9. Residual risks

1. **`maple` assertion is environment-dependent by design.** On a machine where
   MAPLE's dispatcher does import, `xtb/landscape-e2e-maple` fails until a human
   rewrites the record and §7.2 of the guide. That is the intended behaviour (a
   stale “we validated against MAPLE” claim must not survive silently), but it is
   a deliberate test-versus-environment coupling and is documented in the mode's
   docstring.
2. **The `scan` frame/counter relations are asserted on two runs only** (fully
   converged, and fully unconverged). A partially failed scan (`n_fail > 0`)
   exists as the unit target `xtb/landscape-scan-failed-point`, but the JSON
   document of that case is not compared at CLI level.
3. **The `ts` counter is a total, not a breakdown.** A reader who wants
   search-only cost has to use `--lts-no-verify` or the convergence history; the
   PLAN §12.11 entry states this.
4. **`--ljson` byte-level baselines remain thread-count sensitive** (≤4·10⁻¹⁰).
   Counters are not, and all delivered targets pin `OMP_NUM_THREADS=1`.
5. The review's `50` document is missing from the repository: this round's
   dispositions are keyed to the task text plus `49`. If `50` is delivered later,
   its L/INFO items should be re-mapped onto §6 of this report.
