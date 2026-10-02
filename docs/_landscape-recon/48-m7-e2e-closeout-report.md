# M7 close-out report — end-to-end chain, `--ljson`, validation

> Milestone **M7** (PLAN §9.8 / §12.11). Deliverables: `--ljson`, the
> `sp → opt → hess → freq → thermo` chain close-out, the L3 regression test
> `test/unit/test_landscape_e2e.f90`, the layered validation script
> `test/unit/landscape_e2e_check.py`, the MAPLE comparison record, and the two
> PLAN close-out items. The user-facing guide is
> `docs/xtb-landscape-M7-validation.md`.

**Result: build clean (0 warnings), `ctest -R landscape` 90/90 (was 79),
regression subset 12/12, no duplicate test names.** Five bug injections turn
the named tests red and are reverted (§4).

---

## 1. Deliverable 1 — `--ljson`

### 1.1 Design

New module `src/landscape/types/json.f90` (`xtb_landscape_json`):

| Symbol | Purpose |
|---|---|
| `landscape_json_document` | builder: ordered counters/values/flags + a flat history pool |
| `landscape_json_document_init` | fresh document for one task |
| `landscape_json_add_counter/value/flag/series` | append in call order |
| `landscape_json_add_result` | the fields every task shares (`landscape_result`) |
| `landscape_json_add_history` | the series of `landscape_convergence_report` |
| `landscape_json_write` | namespaced name + serialise + `wrote <file>` |
| `landscape_json_write_file` | explicit name (the determinism test) |
| `landscape_json_status_ok/incomplete/error` | `0 / 1 / -1` |

* the ten top-level keys are fixed and ordered;
* reals are written with 17 significant digits (`es25.17e3`) → bitwise double
  round trip; non-finite values become JSON `null`;
* **no wall time, no path, no random value** is written, so the file is byte
  identical between two runs of the same input (tested);
* the history series live in **one flat real pool** plus an offset/length table.
  An array of a derived type with allocatable components would be the natural
  container, but gfortran 12.2.0 corrupts the heap on exactly that shape
  (`docs/_landscape-recon/10-m0-m1-fix-round-report.md` §4.1) — the flat pool
  avoids the defect. **A second instance of the same compiler defect was hit
  here**: `allocate(character(len=40) :: arr(32), source='')` allocated a
  1-character element array (the character length came from the source), and the
  subsequent element write ran 34 bytes past the 32-byte block (ASan:
  `heap-buffer-overflow … json.f90:187`). The character arrays are now allocated
  first and assigned afterwards. This is worth recording because it is a
  *silent* memory corruption that only shows up later (it crashed in an
  unrelated `generic_header` call).

### 1.2 Wiring

| File | Change |
|---|---|
| `src/landscape/types/settings.f90:384` | `landscape_settings%ljson` (base type, all tasks) |
| `src/prog/main.F90:2179-2190` | `--ljson` sets the flag on all five settings objects |
| `src/xhelp.f90` | help text |
| `tasks/sp.f90:166`, `tasks/opt.f90:194`, `tasks/scan.f90:287/333`, `tasks/vib.f90:259`, `tasks/ts.f90:310`, `tasks/irc.f90:379` | per-task document (task-specific counters/values/flags/history) |

`ljson` is independent of `write_files`: the geometry/Hessian files may be
suppressed in a chain while the machine readable result stays.

### 1.3 Every task × the test that proves the option takes effect

Project rule (handover 6, three earlier “dead knob” defects): every new CLI
option needs a test that shows it changes the result. `--ljson` is the only new
CLI option of M7.

| Task | `--ljson` document | Test | Assertion (not “the file exists”) |
|---|---|---|---|
| `sp` | `tasks/sp.f90:166` | `landscape-e2e` `sp-ljson` (API; `sp` has no run type) | `"task": "sp"`, `"status": 0`, `"n_eval": 1`, energy key |
| `opt` | `tasks/opt.f90:194` | `xtb/landscape-ljson-opt`, `landscape-e2e` `ljson-determinism` | `n_steps`/`n_eval`/`n_cache_miss` == stdout, `energy` == `final energy`, key order, byte identity, namespace |
| `scan` | `tasks/scan.f90:287` (1D), `:333` (2D) | `xtb/landscape-ljson-scan` | `n_points` == frames of `xtbscan.log`, `energy` == `lowest energy`, byte identity, namespace |
| `vib` | `tasks/vib.f90:259` | `xtb/landscape-ljson-vib` | `zpe` == printed `zero point energy`, `n_imag` == 0, byte identity, namespace |
| `ts` | `tasks/ts.f90:310` | `xtb/landscape-ljson-ts` | `n_steps`/`n_eval`/`n_cache_miss`/`n_imag` == stdout, byte identity, namespace |
| `irc` | `tasks/irc.f90:379` | `xtb/landscape-ljson-irc` | `n_fwd`/`n_bwd` == stdout, `energy_ts` == printed value, `n_imag` == 1, byte identity, namespace |

The CLI checks parse the file with the standard-library JSON parser, assert
the **key order** (`landscape_e2e_check.py:365`, the fixed
`format task status status_name converged message counters values flags
history`) and cross-assert the counters against the printed numbers; the unit
test `ljson-determinism` pins **byte identity** and the counter values at the
API level (it writes one document twice, so it cannot see a builder that is
deterministically shuffled — finding I-1 of `50-m7-independent-review.md`).  **Method coverage**: `xtb/landscape-e2e-ljson-methods` runs all
eight `ts` methods (four of them band searches with their own code path) and all
four `irc` methods with `--ljson` and checks the `method` counter of each
document against the identifier of the method.

---

## 2. Deliverable 2 — the end-to-end chain

### 2.1 What “close-out” meant here

The chain `opt → hess → freq → thermo` already consumed the previous step's
`xtbopt.xyz`; the missing pieces were *reported values* and *assertions*:

* `landscape_vib_result` gained `enthalpy` and `gibbs`
  (`types/results.f90`), filled by the thermochemistry wrapper
  (`vib/thermo.f90`). `print_thermo` stores only the **thermal** contributions
  in `freq_results%htot/%gtot` and prints the totals as `etot + htot`
  (`src/main/property.F90:1315`), so the wrapper adds the electronic energy;
  the fields are the totals `--hess` prints as `TOTAL ENTHALPY` and
  `TOTAL FREE ENERGY`.
* `landscape_vib` now prints `total enthalpy H(T):` and `total free energy
  G(T):` next to the zero point energy, so the chain can be compared from
  stdout (the reused thermodynamic table prints G but not H).
* `landscape_vib_hessian` returns the **effective** electronic temperature
  (optional `etemp`, read back from the calculator); `opt` and `scan` now store
  `engine%effective_etemp()` in the result too (M4 hard constraint 1; before
  this round the field was 0 for those three tasks and the JSON would have
  reported a dead value).
* `landscape_vib` stores `result%n_imag = vib%n_imag`, so stdout and the JSON
  cannot report two different imaginary-mode counts.
* `landscape_result` no longer leaves `etemp` at 0 for `vib`/`opt`/`scan`.

### 2.2 Acceptance (measured)

| Quantity | H2O | CH3OH | Tolerance |
|---|---|---|---|
| max frequency difference | 0.0100 cm⁻¹ | 0.5200 cm⁻¹ | 0.20 / 1.00 cm⁻¹ (2× measurement) |
| ΔZPE | 1.82·10⁻⁸ Eh | −1.71·10⁻⁶ Eh | 1.4·10⁻⁶ / 2.7·10⁻⁵ Eh |
| ΔH(298.15 K) | 1.81·10⁻⁸ Eh | −1.14·10⁻⁶ Eh | same |
| ΔG(298.15 K) | 1.82·10⁻⁸ Eh | −2.18·10⁻⁶ Eh | same |

The tolerance provenance (projection convention, mode-count propagation of the
frequency spread) is in the validation document §3.1. The Fortran test adds the
parameter-independent identity `ZPE = ½·Σν/autorcm`, which is what makes
injection (iv) red in the unit suite as well.

---

## 3. A latent crash fixed on the way (found by the chain work)

`src/landscape/optimize/driver.f90`: the trajectory `frames` was allocated and
`nframes` set **after** the first energy evaluation, but the failure paths
(“initial energy evaluation failed”, “initial energy or gradient is not
finite”) call `finish()`, which copies `frames(:, :nframes)` into the returned
trajectory. On those paths both were undefined. The release build had survived
it by luck; the layout shift of adding a field to `landscape_settings` turned it
into a deterministic `SIGSEGV` in `test_landscape_optimize_xtb`
(`scf-non-convergence`), diagnosed with a bounds-checked/ASan build as

```
Fortran runtime error: Array bound mismatch for dimension 1 of array 'trimmed' (9/1)
  at src/landscape/optimize/driver.f90:505, in finish
```

Fix: allocate the trajectory and store the starting frame **before** the first
evaluation (same content as before — the first frame was always the starting
geometry). This is a genuine M1 defect, not a test artefact.

---

## 4. Bug injections (each applied, run, recorded, reverted)

Methodology rule of this project: before trusting an injection, prove that the
mutation is semantically the logic it claims to replace. Each injection below is
a one-line change to the production code or to the runner, and the named test
was run in the same build.

### (i) JSON counter is a wrong constant

`landscape_json_add_result`: `n_eval` → `n_eval + 1`.

```
FAIL: landscape_opt.json: counter n_eval is 8 but stdout says 7     # xtb/landscape-ljson-opt
Message: the counter of the result did not reach the document       # landscape-e2e ljson-determinism
```
**Red.** Reverted → both green.

### (ii) non-deterministic value in the document

A `random_number` probe appended to the `message` string (the key order is
unchanged, so the byte comparison is the only thing that can catch it):

```
Message: the two JSON files differ                                   # landscape-e2e ljson-determinism
FAIL: landscape_opt.json is not reproducible between two runs        # xtb/landscape-ljson-opt
```
**Red.** Reverted → green.

Note: a *deterministically* shuffled key order would **not** be caught by the
byte comparison (both runs would be equally shuffled); it is caught by the
separate key-order assertion of the **CLI** check mode `ljson`
(`landscape_e2e_check.py:365`, message `"has an unexpected key order"`), which
is why that assertion exists.

### (iii) the chain silently continues after a failed step

Runner: the exit-status check of step 2 removed and the reference step run
anyway.

```
FAIL: the chain continued after a failed step (hessian exists)       # xtb/landscape-e2e-chain-failure
```
**Red.** Reverted → green.

### (iv) a wrong thermochemical parameter

`landscape_vib_set_thermo_settings`: `set%thermo_fscal = settings%freq_scal*1.01`.

```
FAIL: the chain ZPE differs from --hess by 2.013e-04 hartree …       # xtb/landscape-e2e-chain
Message: the zero point energy is not the half sum of the internal frequencies
                                                                     # landscape-e2e h2o-opt-freq-chain
```
**Red.** Worth recording: with the *original* unit test (which compared the
`--lvib` route against the legacy `trproj` route through the same wrapper) the
injection stayed **green** — both routes shift by the same 1 %, so the
comparison cancels. The identity `ZPE = ½·Σν/autorcm` was added to the unit
test for exactly this reason, and it is red under the injection. The CLI chain
comparison (against the independent `--hess` implementation) was red from the
start. Reverted → green.

### (v) “result not usable ⇒ non-zero exit” reverted

`tasks/scan.f90`: the all-unconverged branch back to `env%warning`.

```
Message: the all-unconverged scan was not reported as an error
    # landscape-scan scan-task-unconverged, scan-task-no-converged-point
FAIL: a scan without a converged point exited 0                       # xtb/landscape-scan-max-steps
```
**Red.** Reverted → green.

### Injection summary

| # | Injection | Red tests | Reverted |
|---|---|---|---|
| i | JSON counter constant | `xtb/landscape-ljson-opt`, `landscape-e2e` | yes |
| ii | random value in the JSON | `xtb/landscape-ljson-opt`, `landscape-e2e` | yes |
| iii | chain continues after a failure | `xtb/landscape-e2e-chain-failure` | yes |
| iv | 1 % frequency scaling error | `xtb/landscape-e2e-chain`, `landscape-e2e` | yes |
| v | scan error → warning | `xtb/landscape-scan-max-steps`, `landscape-scan` | yes |

---

## 5. Deliverable 4 — validation script and MAPLE record

`test/unit/landscape_e2e_check.py` (modes `chain`, `chain-failure`, `ljson`,
`layers`, `maple`), registered in `test/unit/CMakeLists.txt` as nine ctest
targets (`xtb/landscape-ljson-{opt,scan,vib,ts,irc}`, `xtb/landscape-e2e-{chain,
chain-failure,layers,maple}`) and in `test/unit/meson.build`.

The `maple` mode:

* records `maple_executed: false` with the reason (the example tree drives
  ANI-1xnr / AIMNet2 / MACE; the checkpoints and the GPU stack are not part of
  the checkout) — MAPLE was **not** run;
* reads the *committed* MAPLE IRC fixture
  (`examples/irc/hpc/inp1_full.xyz`, a 7-atom molecule, 65 points, one interior
  minimum and one maximum in its energy series) and records that topology;
* runs this suite's HCN/HNC `ts → irc` and records its topology (1 first-order
  saddle, 2 endpoint minima at −5.504037644799 and −5.504031002295 Eh);
* states that no numerical comparison is possible (ML potentials vs GFN2,
  PLAN R-14/N9).

---

## 6. PLAN close-out items

| Item | Status |
|---|---|
| PLAN line 1259 — dimer step table column `trust/bohr` → `stepmax/bohr` (marked M7) | **already done** in M4: `types/results.f90:479` (`bound_label = "stepmax/bohr"` when `bound_kind == p_landscape_bound_step_max`) and `saddle/dimer.f90:961` sets that kind. Verified, no change. |
| PLAN line 1259 — `--lts-step0` / `step0` documented as an **upper bound** | **already done** in M6: `src/xhelp.f90:436-438` (“upper bound of the first dimer translation … the dR curvature probe can shorten the actual first displacement”) and the `step0` field comment in `types/settings.f90`. Verified, no change. |
| PLAN §12.11 INFO-3 (cited as “line 1805” when this round ran) — “result not usable ⇒ non-zero exit” unified | **changed for the scan all-unconverged branch** (`tasks/scan.f90`); the other tasks were already unified. Table in the validation document §6. |
| PLAN §12.11 INFO-3 (`--lscan-max-steps 0` exited 0) | **closed** — now `env%error`; the CMake and meson checks were updated to require a non-zero status. |
| PLAN §9.8 — end-to-end chain, `--ljson`, cross-validation doc, MAPLE topology record | **delivered** (§1, §2, §5). |
| PLAN §6.5 GS Lagrange repair | **not touched** — explicitly out of scope for M7. |

---

## 7. Test inventory

| Suite / target | Cases | Notes |
|---|---|---|
| `landscape-e2e` (unit) | 6 | `h2o-opt-freq-chain`, `chain-gradient-at-minimum`, `hcn-ts-irc-endpoints`, `ljson-determinism`, `sp-ljson`, `opt-failure-visible` |
| `landscape-scan` (unit) | 29 (was 28) | + `scan-task-partial-unconverged`; two cases updated to the M7 exit semantics |
| `xtb/landscape-ljson-*` | 5 | CLI JSON parse + cross-assert + determinism + namespace |
| `xtb/landscape-e2e-ljson-methods` | 1 | 8 `ts` methods + 4 `irc` methods write their document |
| `xtb/landscape-e2e-chain` | 1 | `--lvib` vs `--hess` within the documented tolerances |
| `xtb/landscape-e2e-chain-failure` | 1 | the runner must abort |
| `xtb/landscape-e2e-layers` | 1 | L1+L2+L3 structured report |
| `xtb/landscape-e2e-maple` | 1 | topology record, `maple_executed: false` |
| **`ctest -R landscape`** | **90** | 100 % |

One test-level note worth keeping: `TEnvironment%check` is **cumulative**
(`any(self%log(:nLog)%error)`), so an `env%error` of one sub-run makes every
later core routine that probes `env%check` fail in the *same* environment. In
production an error ends the run, so this is a test concern only; the updated
`test_scan_task_no_converged_point` uses a fresh environment for each of its
three sub-runs and says so in a comment.

---

## 8. Residual risks / open items

1. **Meson is not installed** — the meson registrations (`landscape-e2e`,
   `test/unit/meson.build`, the new CLI checks) are written but unverified, as
   in every earlier milestone.
2. **`--ljson` is not written on the early-error returns** of a task (an invalid
   configuration that aborts before the result exists, e.g. an unknown Hessian
   source, or `vib` with unusable thermochemical settings). The document is the
   result summary, so it exists only once a result does; the failure is reported
   through `env` and the exit status. Recorded as a deliberate scope decision.
3. **`sp` has no run type** (`--lsp` does not exist), so its `--ljson` document
   is only reachable through the API; the CLI coverage table is therefore
   `opt/scan/vib/ts/irc` and `sp` is covered by the unit suite.
4. **`scan-task-partial-unconverged`** (some points unconverged, exit 0) was
   added in M7 because no unit test covered that branch; the construction is
   deterministic (the geometry is optimised first so the unbiased first point
   converges with a one-step budget).
5. **`gs` Lagrange repair** (PLAN §6.5) remains open by explicit decision.
6. The **maple mode's fixture analysis** counts extrema of the committed energy
   series; it is a property of the file, not of a MAPLE run, and the mode says
   so in `maple.json`.

---

## 9. Files touched

```
src/landscape/types/json.f90              (new,  ~470 lines)
src/landscape/types/settings.f90          ljson field
src/landscape/types/results.f90           vib enthalpy/gibbs
src/landscape/vib/thermo.f90              totals + effective etemp
src/landscape/vib/numhess.f90             optional etemp
src/landscape/optimize/driver.f90         early-failure trajectory fix
src/landscape/tasks/{sp,opt,scan,vib,ts,irc}.f90   documents + semantics
src/prog/main.F90                         --ljson
src/xhelp.f90                             --ljson help
src/landscape/CMakeLists.txt              json.f90
src/landscape/meson.build                 json.f90
test/unit/test_landscape_e2e.f90          (new, ~660 lines)
test/unit/test_landscape_scan.f90         M7 semantics + new case
test/unit/landscape_e2e_check.py          (new, ~530 lines)
test/unit/landscape_cli_check.py          maxsteps expectation
test/unit/{CMakeLists.txt,meson.build,main.f90}   registration
docs/xtb-landscape-M7-validation.md       (new)
```
