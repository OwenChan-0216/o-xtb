## Summary (≤30 lines)

**Verdict: ACCEPT** — no CRITICAL/HIGH/MEDIUM *code* finding. All three review‑50 MEDIUMs (M‑1 ts counter, M‑2 maple false‑green, M‑3 PLAN backfill) are **truly fixed** at the source, with named tests and semantically‑valid injections. M7 **can be declared complete**; the suite **can be declared complete** (16/16 entry points).

1. **M‑1 真修**: `result%n_cache_miss = engine%n_eval` now sits *after* `confirm_saddle` at **both** call sites (`ts.f90:279`, `ts.f90:932`), and the *print* moved with the sample (`ts.f90:282,935`) — so stdout `cache misses:` == `landscape engine: energy evaluations` == JSON `n_cache_miss`. New `xtb/landscape-e2e-ts-counters` asserts printed==engine, JSON==printed **and** `confirmed−unconfirmed == k·6N`; injection vi is a genuine *move* (= pre‑fix code, verified by reading `ts.f90:279` vs the diff) and reds it.
2. **M‑2 真修**: probe now imports the dispatcher + instantiates (`landscape_e2e_check.py:928‑946`); `maple_importable=False` on this machine, non‑empty error, `missing=[ase,torch,fairchem]`; the check **fails if the probe ever succeeds**, and asserts non‑empty error — not skippable, not vacuous. Sweep for the same false‑green class elsewhere: **none** (only other `*_importable/available/*_ok`-like fields are `env%warning` fallbacks and the layers `passed` flag, which is keyed to the real exit code).
3. **M‑3 真修**: §12.16 present with schema/order, per‑counter sampling point, 17‑digit + `null`, namespace, cross‑OMP non‑bitwise ⇒ pin `OMP_NUM_THREADS`; §9.8 backfilled with all four systems; 1547 row fixed; INFO‑3/4/5 written.
4. **L‑1 部分修复**: 20× is exact (0.2/0.0100); **the "71×" is arithmetically 70.0×** (1.0e‑6/1.4288e‑8) — stated in 5 places (guide:178, runner:30/102, PLAN:1380, report 51:340).
5. **F1/F4/F5/F7 + L3–L6 真修**: `shutil.rmtree` at entry (root cause, no sleep/loosened assertion); `n_eval` cross‑assertion added; `abspath` in `run()`; layers = 15 suites + 2 L3 legs = 17 checks; 2D/scan counters covered by two new targets.
6. **LOW/P2 (6)**: stale "PLAN line 1805/1511" citations; "for every task equals the engine line" is false for `irc` (no such key) and can be 0 on failed band runs (§4.2/PLAN:1865); §8.1 row 3 `n_valid` definition + dangling "§4.2"; status=1 "usable" vs §6 "non‑zero exit" wording; §8.2 list omits 5 PLAN §11 rows + §12.4 xcontrol; `sp-ljson` counter assertion is a substring test (`"n_eval": 1` also matches 12/19); `--lvib-hessian file` "19→1" has no assertion.
7. **Blocker for full adjudication**: `50-m7-independent-review.md` is **not in the repo** → L‑2/L‑7/L‑8/L‑9 and 7 of 8 INFO items have no recorded disposition (report 51 §9.5 admits this). Evidence gap, not a product defect.
8. Counts: CRITICAL 0 / HIGH 0 / MEDIUM 0 (code) / MEDIUM 1 (evidence gap) / LOW 6 / INFO 3. Merge verdict: **OK with notes**.
9. **Nothing I could not verify by reading was assumed**: everything above is from the working tree at reviewer‑launch HEAD; I ran no commands (list of commands for the parent is in §14).

---

# 52 — M7 fix round, independent review round 2

## 0. Scope, inputs, and one limitation

**Input available**: `docs/_landscape-recon/51-m7-fix-report.md`, `49-m7-validation-experiments.md`, `m7-e2e-data/**` (committed evidence), the working‑tree delta (`watchdog_diff`), `docs/xtb-landscape-PLAN.md`, `docs/xtb-landscape-M7-validation.md`, `test/unit/*`, `src/landscape/*`.

**Limitation, stated up front.** The review I was asked to adjudicate, `50-m7-independent-review.md`, **does not exist in the repository** (`ls docs/_landscape-recon/` ends at `49-…`, then `51-…`; the fix report says the same and notes the workflow file was never written). I reconstructed the finding list from the two places that still carry it: the task text and `m7fix-workflow.js` (`head` + `fix` prompts). Those enumerate **M‑1…M‑3, L‑1, L‑3…L‑6, I2** and re‑state F1/F2/F4/F5/F7; they do **not** enumerate **L‑2, L‑7, L‑8, L‑9** or **INFO‑1, INFO‑3…INFO‑8**. For those 11 items my verdict is *"cannot be adjudicated: review 50 absent, no per‑item disposition recorded in 51"*. I did **not** invent content for them. Everything else below is verified from code/artefacts, with `file:line`.

Aliases: review‑50 M‑1 = report‑49 F3, M‑2 = F6; review‑50 M‑3 is the PLAN item.

## 1. Item‑by‑item verdicts

| # | Verdict | Evidence |
|---|---|---|
| **M‑1** ts counter sampling | **真修 (fixed)** | `tasks/ts.f90:267` confirm → `:279` sample → `:282` print; band path `:925` → `:932` → `:935`. `write_json` at `:293` (single) / `:235` (band) reads the sampled field. Stdout label `cache misses:` = `results.f90:503`; engine total = `engine.f90:802`. New target `xtb/landscape-e2e-ts-counters` (`CMakeLists.txt:2799`, `meson.build` `'landscape e2e ts counters'`), checker `landscape_e2e_check.py:614‑637`. Injection vi is a *move* (add pre‑confirmation sample **and** delete the post one) ⇒ semantically the pre‑fix code (`-` `result%n_cache_miss = engine%n_eval` at old `:255`) ⇒ red on both targets. |
| **M‑2** maple false green | **真修** | `probe_maple` `landscape_e2e_check.py:928‑946` (deep import + instantiation, `maple_toplevel_importable` kept, missing modules named, last stderr line as error); assertions `:881` (self‑consistency), `:885` (**must be False here**), `:890` (non‑empty diagnosis), `:894`; `maple_not_executed_reason` set on both branches `:868`. Injection vii (shallow probe) ⇒ red. |
| **M‑3** PLAN backfill | **真修** | §12.16 at `PLAN:2105‑2180`; schema+order vs `types/json.f90:434‑480` and `landscape_e2e_check.py:360‑367` ✔; counter table `:2141‑2149` ✔; `null`/17‑digit vs `json.f90:520‑541` ✔; namespace `json.f90:399` ✔; OMP paragraph `:2162‑2175` ✔ with both measurements. §9.8 backfill `:1359‑1392` (four systems + default‑level CH3OH + provenance + chain + MAPLE) ✔. CLI row `:1547` corrected ✔. INFO‑3 `:1838‑1850`, INFO‑4 `:1852`, INFO‑5 `:1859‑1874` ✔. |
| **L‑1** tolerance arithmetic | **部分修复** | 20× correct; **71× is 70.0×** (see §5). All other factors check out (0.0100→20×, 0.0600→17×, 0.8900→1.12×; effective 96×/92×/88×/107×). |
| **L‑3/L‑4/L‑5/L‑6** scan/2D JSON counters | **真修** | `xtb/landscape-ljson-scan2d` (`CMakeLists.txt:2765` foreach) + `xtb/landscape-e2e-scan-counters` (`:2809`); assertions `landscape_e2e_check.py:414‑463` (sandwich + `n_points==nframe+omitted`, `n_fail==omitted`, `n1*n2==n_points`) and `:640‑708` (converged **and** all‑unconverged run incl. status −1 and non‑zero exit). Injections viii/ix red. |
| **L‑2, L‑7, L‑8, L‑9** | **无法判定** | review 50 absent; not named in 51 §0/§6. |
| **F1** flaky chain‑failure | **真修 (root cause)** | `landscape_e2e_check.py:305‑306` `shutil.rmtree(rundir)` before the absence assertions; no sleep, no relaxed assertion; injection x red. |
| **F2** CH3OH level | **真修** | guide `:113‑145` (tight 0.0600 / default 0.8900, 12 % margin); runner docstring `:161‑168`. |
| **F4** scan `n_eval` | **真修** | `landscape_e2e_check.py:395‑399` (`n_eval`+`n_cache_miss` vs `energy evaluations`). |
| **F5** relative rundir | **真修** | `landscape_e2e_check.py:180‑186` `os.path.abspath` on exe/inp/rundir (docstring `:150‑156`). Residual: `check_ljson_methods` (`:527`) ignores `run()`'s status, so with a *relative* rundir the band searches silently fail on the relative `--lts-product` and the mode still passes (it only asserts the document). Not reachable from ctest (absolute paths). |
| **F7** layers coverage | **真修** | `:713‑739`: 11 L1 + 4 L2 = the complete 15 `main.f90` landscape suites (verified name‑by‑name against `test/unit/main.f90:96‑110`), `ts-irc` leg `:748`, 17 checks. Nit: the L1 sub‑list is described as "suites that build no SCF" (guide `:107`) — `landscape-scan` contains GFN2 cases (`test_landscape_scan.f90:1446‑1460` `newXTBCalculator`). |
| **F8/I2** OMP non‑bitwise | **documented** | PLAN `:2162‑2175`, guide `:303‑311`; all 13 M7 targets pin `OMP_NUM_THREADS=1` (`CMakeLists.txt:2660‑2875`; meson `landscape_env :142`). |
| **F9** `n_imag=-1`, per‑task `n_eval` | **documented** | PLAN `:2141‑2145`, `:1852`; defaults verified `results.f90:286` (result), `:74` (vib), `:174` (irc); vib writes `result%n_imag = vib%n_imag` (`tasks/vib.f90:191`). |
| **F10** hessian round trip re‑projects | **documented** | guide `:411‑418`; re‑measured 19→1 (report 51 §4). |
| **F11** unit determinism cannot see builder non‑determinism | **接受, no action** | CLI `ljson` mode byte‑compares two processes (`:474‑487`). |
| **INFO‑1, 3..8 of review 50** | **无法判定** | only I2 is identifiable in the available material. |

## 2. Attack surface 1 — M‑1 in depth

**Correct now.** For one run the three numbers are one number by construction: `result%write_log` prints `result%n_cache_miss` (`results.f90:503`), `engine%report` prints `engine%n_eval` (`engine.f90:802`), the JSON writes `result%n_cache_miss` (`json.f90:354`), and the task assigns `result%n_cache_miss = engine%n_eval` **after** the confirmation (`ts.f90:279`, `:932`). Verified against committed artefacts: the pre‑fix document `m7-e2e-data/exp2-ljson/ts-prfo/m7m.landscape_ts.json` still carries `"n_cache_miss": 77` with the same energy (`-5.38737353215649595`) that report 51 §1.3 prints post‑fix with `cache misses: 95` — i.e. the acceptance energy is untouched and only the counter moved. ✔

**Falsifiability is real, and the three assertions are independent.**
* sample moved back + print moved back (injection vi) ⇒ printed 77 ≠ engine 95 ⇒ both `ts-counters` and `ljson-ts` red;
* sample moved back, print left in place ⇒ JSON 77 vs printed 95 ⇒ `ljson-ts` (counter vs stdout) + `e2e-ts-counters` (JSON vs printed) red;
* print moved back, sample left ⇒ printed 77 vs JSON 95 ⇒ red as well.
The check additionally pins the *size* (`difference % 6N == 0 and > 0`, `landscape_e2e_check.py:632‑637`), which a "both numbers wrong in the same way" mutation cannot survive. The author's own record that the first injection attempt was *invalid* (adding a sample without deleting the old one) is exactly the AGENTS §6 discipline; that is a credit, not a concern.

**No M4/M6 regression.** The diff touches only the assignment/print positions (`ts.f90` diff: 3 hunks, all moves). M4/M6 numbers do not involve the counter: the committed `ts-prfo` energy/imaginary frequency match report 51 §4 and guide §3.2 (`-5.387373532156 Eh`, `-1426.12 cm⁻¹`); failure semantics are unchanged (`ts.f90:295‑310` still `env%error`s; `xtb/landscape-ts-minimum` still requires `xtbts.xyz`/`xtbts.log` to exist despite the failure — those writes stay *before* the error at `:287`). All `MATCHES`-style CLI assertions are order‑independent, so the reprint position cannot flip them.

## 3. Attack surface 2 — M‑2, and the false‑green sweep

`maple_importable` is now `proc.returncode == 0` of `from maple.function.dispatcher import Dispatcher; …` executed with `cwd=maple_dir` (so the local package is what is imported) — on this machine that fails on `ase`, giving `error = "ModuleNotFoundError: No module named 'ase'"` and `missing = ['ase','torch','fairchem']` (`numpy` present). The check **asserts** `maple_importable == (error=="")`, `not maple_importable`, `not maple_executed`, and non‑empty error; it is a normal (non‑skipped) ctest target with a real GFN2 HCN chain in it. The one deliberate coupling (fails if MAPLE ever becomes importable here, forcing the record + guide §7.2 to be rewritten) is honest and documented (report 51 §9.1).

**Sweep for the same pattern.** `src/landscape/**` + `test/unit/*.py` for `*_importable|available|installed|*_ok|executed|passed`: one availability probe (this one). The others are *reported degradations* printed on stdout with named tests: `optimize/driver.f90:168,181`, `saddle/prfo.f90:448,473,824`, `saddle/dimer.f90:731,741`, `vib/numhess.f90:111` (ODLR refused, `env%error`), `vib/thermo.f90:128`; and `layers.json`'s `passed`, which mirrors the tester's real exit code (an unknown suite name makes `main.f90:135‑141` `error stop 1`). No second false green.

## 4. Attack surface 3 — M‑3 and "new self‑contradictions"

§12.16 is materially complete (schema+order, counter semantics + sampling point, 17‑digit/`null`, namespace, runtyp‑free wiring, determinism with the "pin OMP for any byte baseline" rule, tests + injections). Residual gaps, all wording‑level:

1. **`恒等` overreach** (`PLAN:1865‑1866`, guide `:288‑290`): "for every task … equals `landscape engine: energy evaluations`" is not true for **`irc`** — `tasks/irc.f90:405‑430` writes no `n_eval`/`n_cache_miss` at all (confirmed in the committed `m7-e2e-data/exp2-ljson/irc-hpc/m7m.landscape_irc.json`), and the guide §4.1 row for `irc` correctly does not claim it. It is also not true for **failed band runs**: `ts.f90:235` writes the document before the counter is sampled, and `:837‑839`/`:909‑913` return early → `n_cache_miss` stays at the `0` default while the engine report (`:236`) prints the real total; with `--lts-no-verify` that document can even say `status: 0`. Failure paths only, run exits non‑zero — but "恒等" and "status ↔ exit code 一致" should be softened to "on a completed run".
2. **Per‑task key inventory incomplete**: §12.16 enumerates the shared counters and the 7 shared history series, but not the extra keys a regression author will actually see (`vib`: `n_atoms/n_modes/n_zero/n_vib/zpe/enthalpy/gibbs/temperature/freq_scal/linear/project_tr` + series `frequency`; `irc`: `n_eval_fwd/bwd`, `n_relax_*`, `n_pinned_*`, `term_*`, series `energy_fwd/s_fwd/gnorm_fwd`(+`_bwd`); `opt`: `n_fallback`; `ts`: `verify_ts`).
3. **Stale line citations**: guide `:344` «(PLAN line 1805)» and report 48 `:263` "PLAN line 1805"; the convention now lives at `PLAN:1841` / `:2158‑2160`. 1511 likewise resolves at `:1547` now. Content fixed, pointers stale.

No statement in §9.8/§12.16 contradicts the code except item 1 above.

## 5. L‑1 — is the arithmetic honest now?

**20× is exact**: 0.20 cm⁻¹ / 0.0100 cm⁻¹ (the H2O chain input, report 49 §1.1). ✔ **"71×" is not**: 1.0·10⁻⁶ Eh / 1.4288·10⁻⁸ Eh = **69.99 ≈ 70×**. The sentence "the floor 1.0·10⁻⁶ Eh is **71×** the measured 1.43·10⁻⁸ Eh" is internally inconsistent (70.0), and the same number is repeated in `PLAN:1380`, `landscape_e2e_check.py:30` and `:102`, and report 51 §5:340. It came from the review's own text (the task states "20x/71x"), so this is a *propagated* arithmetic slip — but it is the exact defect class L‑1 was raised for, in the exact sentence that was rewritten to fix it. Smallest fix: say **70×**, or state the measured value as 1.4·10⁻⁸ Eh. Everything else in §3.1 is self‑consistent: 0.0600→17×, 0.8900→1.12× (guide `:117`), effective 1.37·10⁻⁶ = 96×, 2.7·10⁻⁵ (12 modes, 1.0 cm⁻¹) = 92×/88×/107× against ZPE/H/G.

**Keeping the floors instead of tightening them is checkable** and I accept it: the compared quantity is a projector residual that grows with ‖g‖ (guide `:157‑172` table: 0.0100 at the minimum, 3.30–5.23 at 0.02 bohr, 0.89 for a default‑level methanol), and the runner is used with an explicit `freq_tol` for other molecules (`landscape_e2e_check.py:161‑168`). Tightening *for the delivered H2O target* would still pass (0.0100 measured ⇒ even 0.02 cm⁻¹ / 1e‑7 Eh would pass), but that is a different assertion than "the same check on a less converged minimum", and the current text says so explicitly. Verdict: **accept the margin, fix the factor.**

## 6. F1/F4/F5/F7 and L3–L6

* **F1** — root cause removed (rundir wiped at entry), not papered over: the assertion is unchanged (`:341‑344` still requires the *absence* of `hessian`/`vibspectrum`/`g98.out` and a non‑zero exit), and injection x reproduces the reported flake exactly. ✔
* **F4** — the missing `n_eval` cross‑assertion is in `expected["scan"]` (`:395‑399`); report 49's own `n_eval + 1` checker now overlaps the delivered target. ✔
* **F5** — `abspath` in `run()` fixes the misleading message; verified by reading that all four `run()` callers pass through it. Residual (INFO): `check_ljson_methods` never checks `run()`'s status, so a relative rundir degrades that mode silently instead of failing. ✔
* **F7** — coverage is *added*, not restated: 15/15 suites + both L3 legs, 17 checks, and the guide no longer claims more than that. Both L3 legs now share `check_ts_irc` (`:765`), which also removed the duplicated copy inside `maple`. ✔
* **L3–L6** — 2D document and the three point counters are asserted against the printed frame report on the same run (`:414‑463`), plus a second, fully unconverged run (`:640‑708`). Coverage caveat is honestly recorded as residual risk §2 of report 51 (a *partially* failed scan's document is still only covered by the unit target). ✔

## 7. "Suite completeness and known limitations" (guide §8)

**Honest and specific for what it lists**: 16 reachable entry points with tests and per‑entry‑point limitations; GS Lagrange repair "deferred on purpose" with a pointer to PLAN §6.5 and the M6 handover; DMF/blbfgs/BPRFO/ML/parmfit/MD all present as D2 exclusions; MAPLE "not done and not possible here" stated three times (guide §7.2, §8.2, `maple.json`). The three items the task singled out are all there. ✔

**Not complete, however, against PLAN §9/§11.** Missing from §8.2 (each is a PLAN §11 "明确不做的事" row or a PLAN integration item; verified absent by full read of the guide):
1. **PBC / cell optimisation** — PLAN §11 requires `mol%npbc > 0` ⇒ `env%error` (implemented, `landscape_driver.f90` PBC guard); never listed as a limitation in the guide.
2. **Internal coordinates (DLC/HDLC) as the TS/IRC step space** — PLAN §11 exclusion.
3. **`bias_path`/`modefollow`/`intmodes`** — PLAN §11 "kept untouched, not depended on".
4. **Global optimisation / GA / MECI** — PLAN §11 exclusion.
5. **torch/GPU tensor backend** — PLAN §11 row (only implied by the ML row).
6. **"Rewrite thermo/RRHO"** — PLAN §11 row (the guide only says the RRHO is reused).
7. **PLAN §12.4 optional `$landscape` xcontrol handler** — documented as "M2 起" optional; never implemented (`grep set_landscape src/constrain_param.f90` → 0 hits) and not mentioned anywhere in the guide.

Against **§9.1–§9.8 deliverables** I found nothing unlanded: every file/flag/output of §9.1–§9.8 is present and marked ✅ in the PLAN itself (`--lscan`+`xtbscan.log`+hysteresis+residual; `hessian_source=file`+`vibspectrum`/`vib_normal_modes`/`g98.out`; `--lts` methods + `xtbts.*`; `path.xyz`/`path_autoneb.xyz`/`path_ts_list.xyz`; `--lirc` methods + `irc_*.xyz`/`irc.log`/three termination signals; M7 `--ljson` + G/H/ZPE + MAPLE record + guide). The M7 evidence directory also still contains the *pre‑fix* `ts-prfo` document with `n_cache_miss: 77` — fine as history, but it must not be mistaken for a current baseline (INFO).

## 8. Regression risk (M0…M6)

Only two non‑test files outside `tasks/ts.f90` could affect earlier milestones, and both are additive:
* `optimize/driver.f90` — the trajectory is now allocated *before* the first evaluation (`:122‑129`), removing an undefined‑array copy on the early‑failure paths (`finish` at `:505`, the crash quoted in report 48 §3). The first frame is still the starting geometry, every later path is unchanged.
* `types/results.f90` `enthalpy`/`gibbs` (new fields, defaults `0.0_wp`), `types/settings.f90` `ljson` (new field, default `.false.`), `vib/numhess.f90` optional `etemp` (present‑guarded), `vib/thermo.f90` two read‑backs from the *existing* `res%htot/%gtot`. No existing reader of these types changes behaviour, and the JSON writers are only reached when `ljson` was set (CLI‑only).
* The JSON writers only *read* results; they cannot perturb numerics. The determinism/byte‑identity property of a document is asserted for all six tasks (`:474‑487`).

## 9. Test falsifiability, one by one

| Test | Would it stay green if the logic were wrong? |
|---|---|
| `ts-counters` | No — sample or print displacement reds it (3 independent ways). |
| `ljson-ts` | No — JSON vs engine‑report cross‑check. |
| `scan-counters` / `ljson-scan2d` | No — injections viii/ix red. |
| `chain-failure` | No — injection x red. |
| `maple` | No — injection vii red; also fails the other way if the environment changes. |
| `chain` | No — injection iv (1 % scaling) red; **and** the CLI mode compares H(T)/G(T) against `--hess` **absolutely**, so the Fortran case's same‑matrix comparison (both sides share `energy`, `test_landscape_e2e.f90:245‑262`) cannot hide a wrong "energy+htot" definition. |
| `layers` | No — a non‑zero suite/layer exit reds it (`:759`); unknown suite names exit non‑zero. |
| `ljson-methods` | Weak by design (document + method id only, `run()` status ignored) — documented. |
| `sp-ljson` | **Partly weak**: `test_landscape_e2e.f90:549` `index(text,'"n_eval": 1') > 0` also matches 12/19/…; smallest fix = match `'"n_eval": 1,'` (or parse the counter). |
| `--lvib-hessian file` “19→1” | **No test asserts the drop**; `xtb/landscape-vib-cli`/`-namespace` compare *printed eigval strings*, which are identical whether the file is read or silently recomputed (same geometry, double projection idempotent to 1e‑10 — the effect the guide itself documents at §7.7). The knob is not dead (the error targets `landscape-vib-hessian-missing-file`/`-unknown` prove the source selector and the file open are live), but the *cost* claim is manual only. |

## 10. Doc claims vs code (`!>` and `xhelp`), remaining

* `xhelp` `--ljson` entry: "write the structured result … for every landscape task" — true only together with a `--l*` run type; `xtb x.xyz --ljson` alone is a silent no‑op. PLAN §12.16 says this, the help text does not. (INFO)
* `opt.f90:190‑193` and guide §4 (`:251`) call `incomplete` "the caller may still look at the geometry" / "usable with caveats", while guide §6 (`:349`) and `opt.f90:174‑184` make the same condition a non‑zero exit. Suggest one clarifying sentence. (LOW)
* `landscape_json_document` module doc (`json.f90:33‑35`) claims "two runs of the same input produce byte identical files" without the thread‑count caveat that the class doc block itself then qualifies elsewhere; the guide and PLAN do state it. (INFO, cosmetic)
* No remaining claim in `!>`/`xhelp` asserts an unverified behaviour that I could falsify by reading.

## 11. Numerical hygiene (N‑items) on the new code

`implicit none(type, external)` everywhere; `wp` via `xtb_mctc_accuracy`; new literals carry `_wp` (`results.f90:80‑89` `0.0_wp`; test file uses `0.0971`/`1.0e-6_wp`‑style constants); `autokcal` from `xtb_mctc_convert` (`opt.f90:31`, `scan.f90:37`, `sp.f90:31`); no new module‑level mutable state (the JSON builder is a derived type, `json.f90:105‑140`); `env%error` (no `stop`) on every new failure path; units documented (hartree/bohr·amu^1/2/kmol per key); `write_real` handles NaN/Inf → `null` (`json.f90:520‑532`); no BLAS/LAPACK calls added; the new public procedures all carry `!>` headers. `es25.17e3` is the documented 17‑digit round‑trip format. Nothing to report.

## 12. Findings

| ID | Sev | Finding | Location / evidence | Smallest fix |
|---|---|---|---|---|
| P2‑1 | LOW (doc) | Factor is 70×, stated as 71× (arithmetic in the very sentence L‑1 rewrote) | guide `:178`; `landscape_e2e_check.py:30,102`; `PLAN:1380`; report 51 `:340` | write 70× (or 1.4·10⁻⁸) |
| P2‑2 | LOW (doc) | "equals the engine line **for every task** / 恒等" false for `irc` (no such key) and false for failed band runs (`n_cache_miss` unsampled ⇒ 0; `--lts-no-verify` can even report `status: 0`) | guide `:288‑290`; PLAN `:1865‑1866`; `tasks/irc.f90:405‑430`; `tasks/ts.f90:235,837‑839,909‑913,932`; committed `irc-hpc/m7m.landscape_irc.json` | add "…on a completed run; `irc` reports `n_eval_fwd/bwd` instead" |
| P2‑3 | LOW (doc) | §8.1 row 3 defines `n_valid` as "converged *and* evaluated" (1D only; 2D is `count(grid%energy_valid)`) and cross‑references §4.2, which never discusses `n_valid` | guide `:430`; `tasks/scan.f90:164` vs `:176‑183`; `landscape_e2e_check.py:426` | one sentence + working cross‑reference |
| P2‑4 | LOW (doc) | `status: 1` described as "usable with caveats" in §4 but listed as an unusable outcome (non‑zero exit) in §6 for the same condition | guide `:251` vs `:349`; `PLAN:2158`; `tasks/opt.f90:174‑184` | one sentence |
| P2‑5 | LOW (doc) | Completeness list §8.2 omits 5 PLAN §11 exclusion rows and the optional §12.4 xcontrol handler | guide §8.2; `PLAN:1130‑1220` (§11), `:1556‑1570`; `grep set_landscape src/constrain_param.f90` = 0 | extend the table (7 rows) |
| P2‑6 | LOW (test) | `sp-ljson` counter assertion is a substring match (`"n_eval": 1` matches 12/19) | `test_landscape_e2e.f90:549` | require the trailing comma / parse |
| P2‑7 | LOW (coverage) | The claimed `--lvib-hessian file` cost drop (19→1) is not asserted; delivered vib targets stay green if the provider silently recomputes | guide `§7.7`; `CMakeLists.txt:614‑632, 738‑754`; `vib/numhess.f90:160` prints the count | assert `energy evaluations 1` in the existing script |
| P2‑8 | LOW (evidence) | Review 50 absent ⇒ **L‑2/L‑7/L‑8/L‑9 + 7 INFO items have no recorded disposition**; per‑item adjudication impossible from the repository | `ls docs/_landscape-recon/` (no 50); report 51 §9.5 admits it | land review 50 and re‑map §6 |
| INFO‑1 | INFO | Stale line pointers "PLAN line 1805" (guide `:344`, report 48 `:263`) and "1511" | PLAN content now at `:1841`, `:2158‑2160`, `:1547` | renumber |
| INFO‑2 | INFO | §12.16 does not enumerate the per‑task extra JSON keys (vib/irc/opt/ts) a regression author will diff | `PLAN:2105‑2180`; `tasks/{vib,irc,opt,ts}.f90` writers | add a per‑task key table |
| INFO‑3 | INFO | `m7-e2e-data/exp2-ljson/ts-prfo/m7m.landscape_ts.json` is the pre‑fix document (`n_cache_miss: 77`); fresh evidence exists in report 51 but not as a file | committed evidence dir | regenerate or annotate as pre‑fix |

Non‑findings, explicitly: `layers` L1 sub‑listing (`landscape-scan` builds SCF), `xhelp --ljson` wording, and the `ljson-methods` status insensitivity are reported above as notes only, because each is either documented or unreachable from the delivered ctest.

## 13. Verdict

* **M‑1/M‑2/M‑3: 真修.** No CRITICAL/HIGH/MEDIUM **code** finding. **M7 can be declared complete** (code + tests + documents) — with P2‑1 (one number, 4 places) fixed at the next touch.
* **The suite can be declared complete**: 16/16 entry points implemented, tested, reachable; no stubs. **Deliverable: yes** — the known‑limitation list is **`docs/xtb-landscape-M7-validation.md` §8** (plus the findings table §12 of this report, which must be merged into §8: P2‑5's 7 PLAN §11/§12.4 rows are the only *substantive* addition).
* **Accept** (CRITICAL 0 / HIGH 0 / MEDIUM 0 code + 1 evidence gap / LOW 6 / INFO 3). Merge verdict **OK with notes**; nothing blocks delivery, and no acceptance number, M0–M6 behaviour or failure semantic is touched by this round. The one condition I attach: record P2‑2/P2‑5 in §8 and P2‑8 as a known process limitation, so the completeness list is not read as exhaustive.

## 14. Must‑run verification list (parent)

1. `cmake --build /tmp/xtb-land/build -j` → 0 warnings.
2. `OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape` → **93/93**; `ctest -N -R landscape` → 93; `grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d` → empty.
3. `OMP_NUM_THREADS=1 ctest -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'` → 12/12.
4. `OMP_NUM_THREADS=1 XTBPATH=$PWD python3 test/unit/landscape_e2e_check.py ts-counters <xtb> <hcn.xyz> /tmp/tc` → `95 vs 77 … 18 = 1 x 6N (N=3)`.
5. **P2‑2 probe (new)**: `… --lts --lts-method neb --lts-product missing.xyz --ljson` and compare `landscape_ts.json`'s `n_cache_miss` with the printed `landscape engine: energy evaluations` — expected: they differ (0 vs N), confirming the softened wording is needed.
6. `… maple <xtb> <hcn.xyz> /tmp/m` → `executed=False importable=False missing=['ase','torch','fairchem']`; and `python3 -c "from maple.function.dispatcher import Dispatcher"` inside the MAPLE dir → non‑zero, `ModuleNotFoundError: ase`.
7. `… layers <xtb> <xtb-tester> <in.xyz> /tmp/l <hcn.xyz>` → `17 checks passed`; `… scan-counters <xtb> <water.xyz> /tmp/s` → converged 3/3, unconverged 3/3 error + non‑zero exit.
8. Re‑measure the four‑system dfreq/dZPE/dH/dG on the fixed binary (expect 0.0100/0.0600/0.0000/0.0000 and ≤3.07·10⁻⁷ Eh) — none of my findings predicts a change.
9. Re‑run injection vi (move the ts sample back) and injection vii (shallow maple probe) → both red (evidence exists in `m7-e2e-data/injections/`; re‑run if a fresh binary must be certified).
10. Check `git status` for staged files and confirm no duplicate `add_test` names after any edit.

## 15. Final statement

**The suite is deliverable.** At delivery, the authoritative list of known limitations is `docs/xtb-landscape-M7-validation.md` §8 — which must first absorb the seven PLAN §11/§12.4 items (P2‑5) and the two semantic caveats (P2‑2, P2‑3/P2‑4), and this review must record that review 50 is missing from the repository so that L‑2/L‑7/L‑8/L‑9 and 7 INFO items remain unadjudicated (P2‑8).