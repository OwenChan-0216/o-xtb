# M7 final fix round — report 53

> Round: the final fix of the M7 delivery after the second review
> (`52-m7-review-round2.md`, verdict ACCEPT with 6 LOW / 3 INFO) **plus the new
> defect the parent session found end to end**: `--namespace` did not reach the
> `--lopt` geometry and trajectory (N-1 here).
>
> Inputs: `50-m7-independent-review.md` (**now on disk** — the previous round
> could not read it and recorded that as an evidence gap), `51-m7-fix-report.md`,
> `52-m7-review-round2.md`, `49-m7-validation-experiments.md`,
> `docs/xtb-landscape-M7-validation.md`, `docs/xtb-landscape-PLAN.md` §9.8/§12.
>
> Everything below was measured on this checkout with `OMP_NUM_THREADS=1`
> (AGENTS.md §6.8). No commit was made (the parent session commits).

## 0. Verdict

| # | Item | Severity | Disposition |
|---|---|---|---|
| **N-1** | `--namespace` never reached `xtbopt.xyz` / `xtb.trj` of `--lopt`: two namespaced minimisations in one directory overwrote each other | **HIGH (functional)** | **fixed** at the writer (`types/log.f90`), default names unchanged, new test `xtb/landscape-opt-namespace` + the M1 smoke test now assert the namespaced names; injection xiii |
| **N-2** | full output × namespace table for sp/opt/scan/vib/ts/irc | MEDIUM | **delivered** (§2); the two real gaps found are closed (N-1, `vibspectrum`/`vib_normal_modes`/`g98.out` assertions) and the rest carry a stated reason |
| **N-3** | dispositions of `50`'s **L-2, L-7, L-8, L-9** and **I-1…I-8**, which round 51 could not adjudicate | MEDIUM (evidence gap) | **closed** — table in §3: 8 fixed, 3 accepted with a reason, 1 already fixed in round 51 |
| **N-4.1** | “71×” is arithmetically 70.0× | LOW (doc) | fixed in all 5 named places (+2 summary rows of report 51) |
| **N-4.2** | `sp-ljson` counter assertion was a substring match | LOW (test) | fixed: numeric extraction (new helper `json_counter`), injection xiv shows the old form would have passed a wrong document |
| **N-4.3** | the `--lvib-hessian file` “19 → 1” claim had no assertion | LOW (coverage) | fixed: both the CMake and the Python vib checks assert 19 (direct) and 1 (file) evaluations |
| **N-4.4** | stale PLAN line citations (1805/1511) | LOW (doc) | fixed: §-references (PLAN §12.11 INFO-3) in the guide and report 48; the `@@ -1511 +1547 @@` strings of report 51 are git hunk headers and stay |
| **N-4.5** | “`n_cache_miss` equals the engine line **for every task**” false for `irc` and for failed band runs | LOW (doc) | fixed: softened to “completed run” + both exceptions named, in the guide and in PLAN §12.11 INFO-5 / §12.16 |
| **N-4.6** | §8.1 row 3 `n_valid` definition + dangling §4.2 ref; `status=1` “usable” vs §6 “non-zero exit”; §8.2 missing 6 PLAN §11 rows + §12.4 xcontrol | LOW (doc/test) | all three fixed (§4) |

Final state: build **0 warnings**; `OMP_NUM_THREADS=1 ctest -R landscape`
**95/95 passed** (27.4 s, was 93); regression subset
`-R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'` **12/12**; no
duplicate `add_test` names (`ctest -N -R landscape` = 95,
`grep -oE 'add_test\("[^"]+"' | sort | uniq -d` = empty); **no staged files**;
the four-system M7 acceptance table reproduces report 49/51 digit for digit
(§4.1).

---

## 1. N-1 — `--namespace` did not reach the `--lopt` geometry and trajectory

### 1.1 The defect, reproduced on the pre-fix binary

`xtb w.xyz --gfn2 --lopt --lopt-level loose --ljson --namespace c1` (water,
`--norestart`) produced, in a fresh directory:

```
c1.charges                 c1.landscape_opt.json      c1.wbo
c1.xtbtopo.mol             xtbopt.xyz                xtb.trj        <- no prefix
```

and without `--norestart` also `c1.xtbrestart`. Every task was affected only in
this one place: the counter of `get_namespace` call sites was `scan` 3,
`vib` 2, `ts` 7, `irc` 4 and **`opt` 0** — `tasks/opt.f90` delegates the
geometry and the trajectory to
`xtb_landscape_log::landscape_write_files`, which used the bare names
`trim(settings%output_prefix)//'opt.xyz'` / `'...trj'`.

The intent is unambiguous and doubly documented:

* PLAN §12.9/§9.2 prints the M1 command with `--namespace landscape1` and PLAN
  §12.9 asserts the output files of exactly that run;
* the **pre-existing** `--opt` *does* namespace its geometry, because it writes
  through `open_file` → `persistentEnv%io%writeFile`:
  `xtb w.xyz --gfn2 --opt --namespace core1` → `core1.xtbopt.xyz`,
  `core1.xtbopt.log`, `core1.charges`, `core1.wbo`, `core1.xtbtopo.mol`,
  `core1.xtbrestart`. So `--lopt` was inconsistent with both the rest of the
  suite and the run type it replaces.

Consequence: two minimisations in one directory with different namespaces
silently overwrote `xtbopt.xyz`/`xtb.trj`, i.e. the namespace did not do the one
thing it exists for.

### 1.2 The fix (the mechanism of the other tasks, reused — nothing new invented)

`src/landscape/types/log.f90`, the single writer of both names:

```fortran
   fname = get_namespace(trim(settings%output_prefix)//'opt.xyz')
   ...
   fname = get_namespace(trim(settings%output_prefix)//'.trj')
```

with `use xtb_setparam, only : get_namespace` — the same call, at the same
layer, as `tasks/scan.f90:419`, `tasks/vib.f90:390`, `tasks/ts.f90:600`,
`tasks/irc.f90:948`. `settings%output_prefix` stays un-namespaced (as in every
other task), so `get_namespace` is still applied **exactly once** (the M3
double-prefix defect cannot return). Module and procedure headers document the
rule and the default-name guarantee.

### 1.3 Before / after, same command, same directory layout

| file | pre-fix (`--namespace c1`) | post-fix (`--namespace c1`) | post-fix (no `--namespace`) |
|---|---|---|---|
| geometry | `xtbopt.xyz` | **`c1.xtbopt.xyz`** | `xtbopt.xyz` |
| trajectory | `xtb.trj` | **`c1.xtb.trj`** | `xtb.trj` |
| JSON | `c1.landscape_opt.json` | `c1.landscape_opt.json` | `landscape_opt.json` |
| restart / charges / wbo / topo | `c1.xtbrestart`, `c1.charges`, `c1.wbo`, `c1.xtbtopo.mol` | unchanged | `xtbrestart`, `charges`, … |

Post-fix listing of
`xtb w.xyz --gfn2 --lopt --lopt-level loose --lopt-engine lbfgs --ljson --namespace c1`
(fresh directory):

```
c1.charges  c1.landscape_opt.json  c1.wbo  c1.xtbopt.xyz
c1.xtbrestart  c1.xtbtopo.mol  c1.xtb.trj
```

### 1.4 The other task outputs, for contrast (same sweep, `--namespace ns`)

| task (command) | files written |
|---|---|
| `sp` | no run type — API only (`landscape_sp.json`) |
| `opt` | `ns.charges ns.landscape_opt.json ns.wbo ns.xtbopt.xyz ns.xtbtopo.mol ns.xtb.trj` |
| `lscan` 1D/2D | `ns.charges ns.landscape_scan.json ns.wbo ns.xtbscan.log ns.xtbtopo.mol` |
| `lvib` | `ns.charges ns.g98.out ns.hessian ns.landscape_vib.json ns.vib_normal_modes ns.vibspectrum ns.wbo ns.xtbtopo.mol` |
| `lts` prfo | `ns.charges ns.landscape_ts.json ns.wbo ns.xtbtopo.mol ns.xtbts.log ns.xtbts.xyz` |
| `lts` neb | `ns.charges  ns.landscape_ts.json  ns.path.xyz  ns.wbo  ns.xtbtopo.mol  ns.xtbts.log  ns.xtbts.xyz` (the run itself stopped at the step budget, exit 1 — file names unaffected) |
| `lirc` hpc | `ns.charges ns.irc_backward.xyz ns.irc_forward.xyz ns.irc.log ns.irc_path.xyz ns.landscape_irc.json ns.wbo ns.xtbtopo.mol` |

Before the fix, only the `opt` row had two unprefixed entries; every other row
was already fully prefixed. The sweep also covered the pre-existing core files,
which are prefixed everywhere (`ns.charges`, `ns.wbo`, `ns.xtbtopo.mol`,
`ns.xtbrestart`).

### 1.5 Tests, and the injection that proves them

* **`xtb/landscape-opt` (M1 smoke test, extended)**: it runs with
  `--namespace landscape1`; it now asserts `landscape1.xtbopt.xyz` /
  `landscape1.xtb.trj` **and** the *absence* of the unprefixed `xtbopt.xyz` /
  `xtb.trj`. The rundir is rebuilt at entry, because the absence assertion
  would otherwise be satisfied by a leftover file of an earlier run (the L-7
  lesson; the pre-fix form of this test only asserted existence and therefore
  passed even with the injection — measured, see below).
* **`xtb/landscape-opt-namespace` (new)**: (1) without `--namespace` the names
  are still `xtbopt.xyz`/`xtb.trj`; (2) in **one** directory, `--namespace c1`
  at `loose` and `--namespace c2` at `vtight` write `c1.*` and `c2.*`, the
  `c1` geometry survives the second run byte for byte (MD5 before/after), the
  two geometries differ (the two convergence levels make them genuinely
  different — comparing one input twice could not distinguish an overwrite from
  a correct pair of identical files), and no unprefixed `xtbopt.xyz` appears.
* **meson counterpart** `landscape opt namespace` (`landscape_cli_check.py`
  mode `optnamespace`, the same conditions; the input is written by the check).

**Injection xiii** — the two `get_namespace` calls removed from
`types/log.f90` (that is the pre-fix code, byte for byte):

| test | result |
|---|---|
| `xtb/landscape-opt` | **RED** — `landscape1.xtbopt.xyz was not written` |
| `xtb/landscape-opt-namespace` | **RED** — `--namespace c1 wrote no c1.xtbopt.xyz` |

file restored (`sha1 240f2b5f…`), rebuilt, both green again. Note the first
attempt was informative: with the *old* `xtb/landscape-opt` (existence of the
unprefixed names only) the injection stayed **green** on the second ctest run
because the earlier pass had left `landscape1.xtbopt.xyz` in the reused rundir
— the hygiene fix is therefore part of the finding, not cosmetic.

---

## 2. N-2 — every task output against `--namespace`

The three earlier occurrences of this defect class (M3 double prefix,
M4 `--namespace`, and N-1) justify a complete table. “Writer” is the code that
opens the file; “namespace” is what the delivered binary actually does with
`--namespace ns` (measured in §1.4 and by the tests named).

| # | Output file | Task | Writer | namespace | Test that proves it |
|---|---|---|---|---|---|
| 1 | `xtbopt.xyz` | `opt` | `types/log.f90:74` (`get_namespace`) | ✅ (**fixed here**) | `xtb/landscape-opt` (`landscape1.xtbopt.xyz`), `xtb/landscape-opt-namespace`, Python `optnamespace` |
| 2 | `xtb.trj` | `opt` | `types/log.f90:87` | ✅ (**fixed here**) | same three |
| 3 | `landscape_<task>.json` | `opt` `scan` `scan2d` `vib` `ts` `irc` | `types/json.f90:400` | ✅ | `xtb/landscape-ljson-{opt,scan,scan2d,vib,ts,irc}` (mode `ljson`, step 4 asserts `e2ens.<name>`) |
| 4 | `landscape_sp.json` | `sp` | `types/json.f90:400` (same line) | ✅ structurally | **no namespace assertion** — reason below |
| 5 | `xtbscan.log` | `scan` 1D + 2D | `tasks/scan.f90:419`, `:468` | ✅ | `xtb/landscape-scan-cli` (`landscape2.xtbscan.log`), `-scan-failed-point` (`landscape3`), `-scan-max-steps` (`landscape4`), `-ljson-scan`, `-ljson-scan2d` |
| 6 | `hessian` (write + read-back) | `vib` | `types/hessian.f90:783` / `:756` | ✅ exactly once | `xtb/landscape-vib-cli`, `xtb/landscape-vib-namespace` (`ns.hessian`, and `ns.ns.hessian` must **not** exist) |
| 7 | `vibspectrum` | `vib` | pre-existing `main/property.F90:754` via `open_file` → mctc io | ✅ (`ns.vibspectrum`) | `xtb/landscape-vib-namespace` (**assertion added here**) |
| 8 | `vib_normal_modes` | `vib` | `tasks/vib.f90:390` | ✅ | `xtb/landscape-vib-namespace` (**added here**) |
| 9 | `g98.out` | `vib` | pre-existing `g98fake2` (`src/freq/io.f90`), opened through mctc io | ✅ (`ns.g98.out`) | `xtb/landscape-vib-namespace` (**added here**) |
| 10 | `xtbts.xyz`, `xtbts.log` | `ts` single geometry | `tasks/ts.f90:600`, `:612` | ✅ | `xtb/landscape-ts-prfo` (default `xtbts.xyz`), `xtb/landscape-ts-namespace` (`landscape6.xtbts.*`) |
| 11 | `path.xyz` | `ts` `neb` `cineb` `string` `gsm` | `tasks/ts.f90:772/800/824` → `write_path_frames` (`:1239`) | ✅ | `xtb/landscape-path-cli` (`p1.path.xyz`), `xtb/landscape-path-string` (`p3.path.xyz`) |
| 12 | `path_autoneb.xyz` | `ts` `autoneb` (also its restart file) | `write_path_frames` (`:772`) | ✅ | `xtb/landscape-path-autoneb` (`p2.path_autoneb.xyz`, and the restart run re-reads it) |
| 13 | `path_ts_list.xyz` | `ts` `autoneb`/`string`/`gsm` | `tasks/ts.f90:1298` | ✅ | `xtb/landscape-path-autoneb` (`p2.path_ts_list.xyz`), `xtb/landscape-path-string` (`p3.path_ts_list.xyz`) |
| 14 | `irc_forward.xyz`, `irc_backward.xyz`, `irc_path.xyz` | `irc` | `tasks/irc.f90:779-785` → `:819`/`:861` | ✅ | `xtb/landscape-irc-cli` (`irc1.irc_*`), `-irc-pc`, `-irc-swap`, `-irc-minimum` |
| 15 | `irc.log` | `irc` | `tasks/irc.f90:948` | ✅ | `xtb/landscape-irc-cli` (`irc1.irc.log`), `-irc-knobs` (`irc4/5.irc.log`) |
| 16 | `charges`, `wbo`, `xtbtopo.mol`, `gfnff_charges`, `gfnff_topo`, `xtbrestart`, `xtbout.json` | all | pre-existing core (`open_file` / mctc io) | ✅ (`ns.charges`, `ns.wbo`, `ns.xtbtopo.mol`, `ns.xtbrestart`) | **none in this suite** — reason below |

Two entries carry a reason instead of a test:

* **#4 `landscape_sp.json`**: the `sp` task has no run type (PLAN §4 / review I-7),
  so no CLI check can reach it; the unit case `landscape-e2e` `sp-ljson` covers
  the document but not the namespace. The name comes from the *same single
  line* (`json.f90:400`) that the six CLI tasks exercise with `--namespace`
  (row 3), so the property is covered structurally, not by an independent
  observation. Recorded as the one remaining (accepted) gap of this table.
* **#16**: those names are owned by the pre-existing xtb core, not by the
  suite; the suite cannot make them inconsistent, and the core already prefixes
  them (`open_file` → `persistentEnv%io%writeFile`), which the N-1 sweep
  confirmed one by one. The core-side CLI tests (`xtb/Singlepoint` … `xtb/GFN2-FF`)
  run with `--namespace test1` … `test7` but assert only the exit status;
  tightening those is out of this round's scope (they are not landscape
  outputs).

Corrections to the review record, found while building the table: the name
`xtbscan_2d.xyz` (report 50 §L5, report 52 §0) **does not exist** — the 2D scan
writes the same `ns.xtbscan.log` (documented since M2,
`tasks/scan.f90:332`); and `vibspectrum`/`g98.out` are namespaced not by this
suite's writers but by the reused core writers.

---

## 3. N-3 — dispositions of report 50's L-2/L-7/L-8/L-9 and I-1…I-8

Report 51 could not adjudicate these (`50-m7-independent-review.md` was not on
disk); report 52 §0/§12 records that as an evidence gap (its P2-8). The review
is now on disk, so each item is settled here.

| Item (report 50) | Disposition | Evidence |
|---|---|---|
| **L-2** — `chain-failure` documentation says the **first** step is forced to fail (implementation: step 2 is misconfigured) | **fixed (doc)** | `test/unit/landscape_e2e_check.py:32-36` and `test/unit/CMakeLists.txt:3018-3020` now say: step 1 succeeds, step 2 (`--lvib` with a missing Hessian file) is misconfigured and the runner must abort. The implementation already behaved that way and is unchanged (`:309-345`) |
| **L-7** — assertions about the *absence* of files without clearing the rundir first | **fixed** | `chain-failure`: `shutil.rmtree(rundir)` at entry (round 51, F1; `landscape_e2e_check.py:305-306`). `sp-ljson`: the fixed file name is now deleted **at entry** as well (`test/unit/test_landscape_e2e.f90`, `call delete_text(file)` before the run), so a leftover document cannot satisfy the existence assertion. The two new namespace checks clear their rundirs for the same reason (`CMakeLists.txt` `landscape_cli_opt_namespace.cmake`, `landscape_cli_vib_namespace.cmake`) |
| **L-8** — PLAN §9.8 asks for a MAPLE record “per task”; only the IRC fixture was read | **fixed** | `landscape_e2e_check.py` now carries `MAPLE_FIXTURES` and reads one committed fixture **per task**: `sp/sp.out` (22 atoms, −383.47223856 Eh), `opt/lbfgs/inp1_traj.xyz` (55 frames), `scan/C18_scan_final.xyz` (51 frames), `ts/dmf/inp1_prfo_ts.xyz` (1 frame), `freq/mw/inp1.xyz` (1 frame), `irc/hpc/inp1_full.xyz` (65 frames, 1 minimum/1 maximum); each entry records path, frames, atoms and the extrema of the committed energy series (`maple.json` → `maple_fixtures`). The mode **fails** if a fixture disappears from the checkout, and the conclusion is generated from what was actually read. The `maple_fixture*` keys of the IRC file are kept (the validation guide cites them). Guide §7.2 and §8.2 updated; re-run live: `maple: executed=False importable=False missing=['ase','torch','fairchem']` |
| **L-9** — `--ljson` is a silent no-op without a landscape run type | **fixed (product)** | `src/prog/main.F90` (before the `p_run_lopt` branch) emits `env%warning("--ljson writes nothing without a landscape run type: add --lopt, --lscan, --lvib, --lts or --lirc")` when the run type is none of the five — the check is placed after parsing, because flag and run type may be given in either order. `src/xhelp.f90` says the same in the `--ljson` help text. Test `xtb/landscape-ljson-no-runtype` (meson `landscape ljson no runtype`) asserts exit 0 **and** the message **and** that no `landscape_*.json` appeared; injection xii (warning removed) reds it |
| **I-1** — report 48 claims the unit test `ljson-determinism` “additionally pins the key order” | **fixed (doc)** | `48-m7-e2e-closeout-report.md:80` and `:180-182`: the key order is asserted by the **CLI** mode `ljson` (`landscape_e2e_check.py:365`, `has an unexpected key order`); the unit case pins byte identity and the counters (it writes one document twice and structurally cannot see a deterministically shuffled builder) |
| **I-2** — JSON not byte identical across thread counts | **accepted (documented, round 51)** | PLAN §12.16 (OMP paragraph, both measurements), guide §4.2; all landscape CLI targets pin `OMP_NUM_THREADS=1` |
| **I-3** — `n_imag = -1` sentinel and the per-task meaning of `n_eval` need a §12.11-style INFO entry | **accepted (done in round 51)** | PLAN §12.11 INFO-4 (`n_imag = -1` is not `0`) and the counter table of §12.16 (row `n_eval`: “`opt`/`ts` = objective calls; `scan`/`vib` = engine total”); guide §4.2 bullets |
| **I-4** — the `hessian` file path projects a second time, so a file re-run reproduces the `--hess` number | **accepted (documented, round 51) + now asserted** | guide §7.7; the 19 → 1 evaluation drop of that path is now **asserted** (N-4.3), which is the observable consequence of the re-projection |
| **I-5** — the unit determinism case cannot detect builder-level non-determinism | **accepted, no action** | the CLI `ljson` mode byte-compares two **processes** (`:497-509`); the unit case is the API-level complement. Documented here and in report 51 §5 |
| **I-6** — the CMake comment “non-zero exit next to the NaN total energy” is imprecise | **fixed (comment)** | `test/unit/CMakeLists.txt` (scan `--lscan-max-steps 0` target): `env%error` terminates the process in `env%checkpoint` **before** the trailing `TOTAL ENERGY` block, so the NaN appears in the scan table (`lowest energy: +NaN`) and there is no NaN total energy line; the pointer now says PLAN §12.11 INFO-3 instead of “line 1805” |
| **I-7** — `sp` has no run type, so “all tasks have the optional output” is CLI-incomplete | **accepted (documented)** | report 48 §8.3 declares it; guide §4.1/§8.1 row 1; the new `--ljson` help text of `src/xhelp.f90` names it too |
| **I-8** — no injection pinned the **frequency** tolerance (only the energy tolerance) | **fixed (evidence)** | injection **xi**: `vib/modes.f90` scaled by 1.0001 → `xtb/landscape-e2e-chain` **RED** (`the chain frequencies differ from --hess by 0.3700 cm^-1`), i.e. the 0.20 cm⁻¹ floor is live and a sub-cm⁻¹ regression is caught. The limitation that remains is the floor itself (a shift below ≈0.2 cm⁻¹ passes by design — the margin exists for less converged minima, §3.1 of the guide); recorded in the guide's injection table (row xi) |

No item of report 50 is left unadjudicated.

---

## 4. N-4 — the six LOW findings of report 52

### 4.1 N-4.1 — the factor is 70.0×, not 71×

`1.0·10⁻⁶ / 1.4288·10⁻⁸ = 69.99`. Corrected in every named place and in the
two summary rows of report 51 that repeat it:

| file | before | after |
|---|---|---|
| `docs/xtb-landscape-M7-validation.md:178` | **71×** | **70×** |
| `test/unit/landscape_e2e_check.py:30` (docstring) | 71x | 70x |
| `test/unit/landscape_e2e_check.py:102` (`THERMO_TOL` comment) | 71x | 70x |
| `docs/xtb-landscape-PLAN.md:1380` | **71×** | **70×** |
| `docs/_landscape-recon/51-m7-fix-report.md:340` (and `:30`, `:278`) | 71× | 70× |

Reports 50 and 52 are the reviewers' own texts and are left untouched; 52 §5
already records the arithmetic.

### 4.2 N-4.2 — the `sp-ljson` counter assertion is numeric now

`test/unit/test_landscape_e2e.f90` gets a helper

```fortran
!> Integer value of one counter of a JSON document.
subroutine json_counter(text, key, value, found)
```

which consumes the digits after `"<key>": ` until the first non-digit, and the
three counter assertions of the suite (`sp-ljson` `n_eval == 1`;
`ljson-determinism` `n_eval == 42`, `n_cache_miss == 7`) compare **numbers**
instead of searching substrings.

**Injection xiv** — `json.f90` writes `n_eval + merge(11, 0, task == 'sp')`
(only the `sp` document is affected): `landscape-e2e` `sp-ljson` **RED** with
`the single point counter of the document is not 1`. The document the red run
left behind contains `"n_eval": 12,` — and the **old** assertion
`index(text, '"n_eval": 1') > 0` is satisfied by exactly that text (verified on
the written file), which is the proof that the strengthening was necessary and
not cosmetic.

### 4.3 N-4.3 — the `--lvib-hessian file` cost is asserted

Direct `--lvib` on water: `landscape engine: energy evaluations 19` = 1 + 6N
(the input gradient plus one central-difference displacement per Hessian entry).
The file run: `1`. Both the CMake script (`landscape_cli_vib.cmake`) and the
Python mode `vib` now assert `direct == 19`, `file == 1` and `direct > file`, so
a provider that silently recomputed the Hessian from the geometry can no longer
pass the target.

### 4.4 N-4.4 — stale PLAN line citations

* guide §6 heading: `(PLAN line 1805)` → `(PLAN §12.11 INFO-3)`;
* report 48 §6: `PLAN line 1805` → `PLAN §12.11 INFO-3 (cited as “line 1805” when
  this round ran)`;
* `test/unit/CMakeLists.txt` scan comment: `PLAN line 1805` → `PLAN section
  12.11 INFO-3`;
* report 51's `@@ -1511 +1547 @@` / `1511` strings are **git hunk headers** and
  a record of what was changed — they stay correct as history (the row now
  lives at `PLAN:1547`); PLAN line 1259 (the dimer-column item of report 48) was
  re-checked and is still accurate.

### 4.5 N-4.5 — “equals the engine line for every task” is false for `irc` and for failed band runs

* guide §4.2 `n_cache_miss` bullet: now “on a **completed** run of
  `opt`/`scan`/`vib`/`ts`”, with both exceptions spelled out — `irc` writes no
  `n_cache_miss` at all (it reports `n_eval_fwd`/`n_eval_bwd`), and a **failed**
  band search can return before the counter is sampled (`tasks/ts.f90:235`
  writes the document first; `:718-724`, `path/neb.f90:739`, `:837-839` and
  `:909-913` all return before the sample at `:932`).
  The probes suggested by report 52 (§14 item 5) were run, and they split the
  claim into a **measured** and a **code-read** half:
  * measured — `--lts-method neb --lts-product missing.xyz --ljson` → exit 1,
    `n_cache_miss: 0` next to `landscape engine: energy evaluations 0` (the
    failure precedes the first evaluation, so the two agree), and
    `--lts-images 2` → “band path construction failed”, likewise 0/0;
  * measured — a band that *runs* and stops at the budget (exit 1,
    `--lts-max-steps 20`) writes `n_cache_miss: 124` and the engine prints
    `124`: the sample is reached and the identity holds;
  * code reading — the two returns that fire **after** a band search
    (`:837-839` “no internal node”, `:909-913` “candidate not evaluable”) leave
    the field at the default `0` while the same stdout prints a non-zero engine
    total.  That scenario was **not** reproduced by a CLI run this round (it
    needs a collapsed band or an SCC failure at the candidate), so the guide and
    PLAN §12.11 INFO-5/§12.16 mark it as a code reading rather than a
    measurement — the failure class is still non-zero-exit either way, and the
    field is a default, not a measurement.
* PLAN §12.11 INFO-5 and §12.16 (“stdout 与 JSON 同源同义”) carry the same
  qualification, with the same two exceptions and `file:line`.

### 4.6 N-4.6 — `n_valid`, the `status: 1` wording, and §8.2

* guide §4.2 gains the scan point bookkeeping paragraph: `n_points`,
  `n_fail` (= omitted frames), `n_unconverged`, `n_valid` (1D: converged **and**
  evaluated, `tasks/scan.f90:176-183`; 2D: evaluated,
  `tasks/scan.f90:164`), the relations `n_points == nframe + n_fail`,
  `n_valid <= nframe <= n_valid + n_unconverged` (1D), `n_valid == nframe` (2D)
  and the test that asserts them. §8.1 row 3 now states the two different
  definitions and points at §4.2 (the dangling reference is resolved).
* guide §4: `status` is “a **classification of the result, not a promise about
  the exit code**” — `status: 1` **and** a non-zero exit for an unconverged
  minimisation (`tasks/opt.f90:169-184`), `status: 1` with exit 0 for an
  imaginary frequency or a scan with unconverged points, `-1` with a non-zero
  exit for an unusable result. PLAN §12.16 carries the same sentence.
* guide §8.2 gains the 7 items report 52 §7 named: PBC/cell (excluded, with the
  implemented guard `landscape_driver.f90:73-77`), internal coordinates as the
  TS/IRC step space, `bias_path`/`modefollow`/`intmodes`, global
  optimisation/GA/MECI, torch/GPU backend, “rewrite thermo/RRHO”, and the
  optional `$landscape` xcontrol handler of PLAN §12.4 (not implemented,
  `grep set_landscape src/` = 0 hits). Each row names its PLAN section.

### 4.7 Acceptance numbers are untouched

The four-system table was re-measured on the fixed binary with the delivery
driver (run from a **copy** of the committed data tree, so the committed
evidence is not overwritten):

```
h2o    dfreq 0.0100 cm^-1  dZPE 1.429e-08  dH 1.426e-08  dG 1.429e-08 Eh  param-equal True
ch3oh  dfreq 0.0600 cm^-1  dZPE 2.975e-07  dH 3.070e-07  dG 2.530e-07 Eh  param-equal True
co2    dfreq 0.0000 cm^-1  dZPE 1.709e-08  dH 1.296e-08  dG 1.908e-08 Eh  param-equal True
c2h2   dfreq 0.0000 cm^-1  dZPE -3.400e-11 dH -2.100e-11 dG -4.200e-11 Eh param-equal True
```

digit for digit the numbers of report 49 §1.1 / report 51 §4. The chain target
still prints `max dfreq 0.0100 cm^-1 (tol 0.20)`. None of the product changes of
this round (namespace of two file names, one warning, test/doc changes) can
touch a frequency or an energy — and the measurement confirms it.

---

## 5. Injection log of this round

Every injection was an exact-text replacement that asserted the needle was
unique, was shown to **compile**, reddened the named target, and was restored
(sha1 re-checked) and rebuilt green afterwards.

| # | injection | build | red target(s) | observed message |
|---|---|---|---|---|
| xiii | `get_namespace` removed from `xtbopt.xyz`/`xtb.trj` (pre-fix code) | compiled | `xtb/landscape-opt`, `xtb/landscape-opt-namespace` | `landscape1.xtbopt.xyz was not written`; `--namespace c1 wrote no c1.xtbopt.xyz` |
| xii | the `--ljson` warning block removed from `main.F90` (pre-fix behaviour) | compiled | `xtb/landscape-ljson-no-runtype` | `the --ljson no-op was not reported` |
| xiv | `json.f90` writes `n_eval + 11` for the `sp` document | compiled | `landscape-e2e` `sp-ljson` | `the single point counter of the document is not 1` (and the old substring form matched the wrong document — verified) |
| xi | `vib/modes.f90` frequencies scaled by 1.0001 | compiled | `xtb/landscape-e2e-chain` | `the chain frequencies differ from --hess by 0.3700 cm^-1 (tolerance …)` |

Negative controls: xii/xiii/xiv leave the M6 IRC and the scan targets green (run
as part of the 95/95 sweep after each restore); the frequency injection is the
only one that can move `landscape-vib` unit numbers and was restored before the
suite run.

---

## 6. Test inventory after the round

| target | kind | new/for what |
|---|---|---|
| `xtb/landscape-opt-namespace` | CMake script | N-1: default names + two namespaces in one directory + no overwrite + no unprefixed name |
| `xtb/landscape-ljson-no-runtype` | CMake script | N-3/L-9: the `--ljson` no-op is reported, exit still 0, no document |
| `landscape opt namespace` (meson) | Python `optnamespace` | the same conditions as `xtb/landscape-opt-namespace` |
| `landscape ljson no runtype` (meson) | Python `ljsonnorun` | the same conditions as `xtb/landscape-ljson-no-runtype` |
| `xtb/landscape-opt` (extended) | CMake script | asserts `landscape1.*` **and** the absence of the unprefixed names, with a clean rundir |
| `xtb/landscape-vib-cli` (extended) | CMake script | the 19 → 1 evaluation assertion (N-4.3) |
| `xtb/landscape-vib-namespace` (extended) | CMake script | `ns.hessian`/`ns.vibspectrum`/`ns.vib_normal_modes`/`ns.g98.out`, and no unprefixed twin |
| `landscape-e2e` (unit) | Fortran | exact counter comparison (`json_counter`), `sp-ljson` file deleted at entry |
| `maple` (mode of the e2e runner) | Python | per-task committed fixtures (N-3/L-8) |

Counts: `ctest -N -R landscape` = **95** (93 + 2 new); the meson file registers
the two Python counterparts; `test/unit/main.f90` is unchanged (no new Fortran
unit case — the new checks are CLI-level, and the extended unit cases live in
existing subroutines).

---

## 7. Residual risks

1. **`landscape_sp.json` has no namespace test** (§2 row 4): the `sp` task is
   API-only, so the CLI cannot reach it; the property rests on the shared
   single-line writer. Accepted.
2. **The frequency tolerance floor is a floor** (I-8): a frequency regression
   below ≈0.2 cm⁻¹ passes `xtb/landscape-e2e-chain` by design (injection xi
   catches 0.37 cm⁻¹). A tighter assertion is available per molecule through the
   `freq_tol` argument; the delivered H2O target deliberately keeps the margin
   for less converged minima.
3. **The failed-band-run counter (`n_cache_miss: 0`)** is documented rather than
   fixed: the document is written before the band search samples the counter,
   and a failure path that reports a default instead of a measurement is the
   price of writing the document early. Changing it would touch the M5/M6
   failure semantics; recorded in PLAN §12.11 INFO-5.
4. **meson/ninja remain unverified** (not installed, unchanged since M0): the
   two new Python modes were executed by hand against the built binary
   (`optnamespace`, `ljsonnorun`, `vibnamespace`, `vib` all exit 0), but the
   meson test *registration* cannot be executed here.
5. **`docs/xtb-landscape-M7-validation.md` §8.2 is long**; it now lists the
   PLAN §11 rows, which makes the “deliberately excluded” part of the guide the
   authoritative summary — keep it in sync when D2 changes.
6. The pre-existing M3 note stands: `--lvib` vs `--hess` is never bitwise
   (different projection conventions), so no criterion here uses bitwise
   equality of the two routes.

---

## 8. Files changed by this round

| file | change |
|---|---|
| `src/landscape/types/log.f90` | `get_namespace` for `xtbopt.xyz` / `xtb.trj` (+ header documentation) |
| `src/prog/main.F90` | warning when `--ljson` has no landscape run type |
| `src/xhelp.f90` | `--ljson` help text: needs a `--l*` run type, `sp` is API-only |
| `test/unit/CMakeLists.txt` | `xtb/landscape-opt-namespace`, `xtb/landscape-ljson-no-runtype`, `xtb/landscape-opt` extended (+ hygiene), `xtb/landscape-vib-cli` evaluation assertions, `xtb/landscape-vib-namespace` four-file assertions (+ hygiene), `chain-failure` comment, test-property lists |
| `test/unit/landscape_cli_check.py` | modes `optnamespace`, `ljsonnorun`, `vibnamespace` extended, `vib` evaluation assertions, `chain-failure` docstring, `70x` |
| `test/unit/meson.build` | registration of the two new Python tests |
| `test/unit/landscape_e2e_check.py` | per-task MAPLE fixtures, conditional conclusion + stale-check, `70x`, `chain-failure` docstring |
| `test/unit/test_landscape_e2e.f90` | exact counter comparison (`json_counter`), `sp-ljson` hygiene |
| `docs/xtb-landscape-PLAN.md` | §12.9 M1 file names, §9.2 M1 acceptance, §12.11 INFO-5 exceptions, §12.16 status/counter qualifications, `70×` |
| `docs/xtb-landscape-M7-validation.md` | §4.2 scan counters + `n_cache_miss` exceptions, §4 `status` wording, §5 injections xi–xiv, §7.2 per-task MAPLE fixtures, §8.1 row 3, §8.2 seven new rows, §6 heading, `70×` |
| `docs/_landscape-recon/48-m7-e2e-closeout-report.md` | I-1 wording, stale PLAN pointer |
| `docs/_landscape-recon/51-m7-fix-report.md` | `70×` in §5 and the two summary rows |

---

## Addendum — dispositions of review 54 (LOW 4 / INFO 5), applied after the review

The parent session applied the one-line documentation items the review recommended
for this commit; the rest are recorded here so nothing is lost.

| item | disposition |
|---|---|
| L-1 `xtbscan_2d.xyz` / `xtbopt.log` | **fixed** — PLAN 5.5 now says `xtbscan.log` for the 2D grid and `xtb.trj` for the opt trajectory; `tasks/scan.f90:332` says `xtbscan.log` |
| L-2 four stale `PLAN line 1805` pointers | **fixed** — `tasks/scan.f90:245`, `test/unit/test_landscape_scan.f90:1514,1547`, `test/unit/landscape_cli_check.py:614` now cite `PLAN 12.11 INFO-3` |
| L-3 guide said 93 targets | **fixed** — `xtb-landscape-M7-validation.md:39` now says 95 |
| L-4 report 53's `CMakeLists.txt:2967-2969` | **fixed** — corrected to `:3018-3020` (this file) |
| I-1 three conditional `--lvib` outputs missing from the N-2 table | **recorded**: `xtbhess.xyz` (imaginary modes, `hessian.F90:714`), `xtb_enso.json` (`--enso`), `xtb_localmodes` / `g98_locmode.out` (`set%pr_modef`).  All three go through the core `open_file` and are therefore namespaced, so the product behaviour is correct; the table listed the suite's own write points only |
| I-2 `json.f90` byte-identity promise lacked the thread qualifier | **fixed** — the module doc now says "at the same `OMP_NUM_THREADS`" and quotes the measured 2.4e-10 spread |
| I-3 section 0 summary label count | **accepted** — the summary is a count of dispositions, the section 3 table carries the per-item labels; a reader comparing the two is expected to read the table |
| I-4 three session workflow scripts in the repo root | **excluded** — the parent session removed `m7-workflow.js`, `m7fix-workflow.js`, `m7final-workflow.js` before the commit |
| I-5 `xtb-landscape-M7-validation.md` untracked | **fixed** — it is part of the M7 commit |
