# Stage 3b recon — facts (HEAD b822c1f, -O2, /tmp/xtb-3af/build/xtb)

> **Note on the prerequisite:** `docs/_simplify-recon/41-stage3-recon.md` **does not exist**
> (`ls docs/_simplify-recon/` → highest numbered files are `48-stage3a-fix-review.md`; there is
> no 41). The task text pointed at a missing file; I read `11-cli-redesign.md` §3.5/§3.10/§3.10b
> instead. Anything already covered there is still restated here because that prior recon is absent.
>
> Scope: **read-only**. All commands with `OMP_NUM_THREADS=1`, absolute paths under `/tmp/s3b-recon`.
> Items I did not get to are marked **未查**.

---

## A — R5 four axes (the only item that can move accepted numbers)

### A1. Are `e_tol` / `acc` / `max_steps` fixed or level-driven? (current state)

**Fixed.** `landscape_settings` declares them as compile-time defaults:
- `src/landscape/types/settings.f90:373` `integer :: max_steps = 256`
- `src/landscape/types/settings.f90:375` `real(wp) :: e_tol = 5.0e-6_wp`
- `src/landscape/types/settings.f90:325` `real(wp) :: acc = 1.0_wp` (inside `landscape_engine_control`)

`landscape_settings_set_conv_level` (`src/landscape/types/settings.f90:1120-1155`) writes **only the four
threshold fields** — `g_max`, `g_rms`, `d_max`, `d_rms` — once per level case. It never touches
`e_tol`, `max_steps` or `engine%acc`:

```
case ('tight')
   self%g_max = 1.0e-4_wp
   self%g_rms = 3.0e-5_wp
   self%d_max = 1.0e-3_wp
   self%d_rms = 6.0e-4_wp
```
(five identical-shaped cases: superloose/loose/normal/tight/vtight.)

⇒ **3b must add `e_tol` (and optionally an `acc`/`max_steps` multiplier) to this routine**, exactly
as the design §3.5 says.

### A2. `acc` source chain

**Write points of `engine%acc` in `src/prog/main.F90`** (all **unconditional**, one per suite branch):

| line | branch | statement |
|---|---|---|
| `main.F90:1076` | `--lopt` (`p_run_lopt`) | `lset%engine%acc = set%acc` |
| `main.F90:1095` | `--ohess` vib half | `lvset%engine%acc = set%acc` |
| `main.F90:1142` | `--lscan` | `lsset%engine%acc = set%acc` |
| `main.F90:1162` | `--lts` | `ltset%engine%acc = set%acc` |
| `main.F90:1191` | `--lirc` | `lircset%engine%acc = set%acc` |
| `main.F90:1207` | `--lvib` | `lvset%engine%acc = set%acc` |

`set%acc` comes from CLI `--acc` (default `1.0`, `src/setparam.f90:227`); the `case ('-a','--acc')`
parser is `main.F90:1665`. **It is not level-derived today.** Per design §3.5 item 3 (R27/L-5) all
six lines must become `if (acc_was_set) ...` so a level-derived `acc` is not overwritten by the
global default. Measured grep of writes:

```
$ grep -n "engine%acc = set%acc" src/prog/main.F90
1076, 1095, 1142, 1162, 1191, 1207   (6 hits)
```

Do not confuse with `hess_acc` (a **different** field, default `0.3`, `settings.f90:330`), written
by the CLI `--l*-sccacc`/`--l*-hess-step` and by `src/landscape/tasks/ts.f90:469/484`; it feeds the
numerical Hessian provider, not the SCF.

### A3. Consumption points (file:line)

**`e_tol`** (4 reads):
- `src/landscape/types/settings.f90:1099` `converged = abs(de) <= self%e_tol &` — the only
  behavioural read (an `AND` guard with the four thresholds).
- copied into sub-settings: `src/landscape/scan/relax_scan.f90:601`, `src/landscape/tasks/irc.f90:725`,
  `src/landscape/tasks/ts.f90:1218` (`opt%e_tol = settings%e_tol`).

**`max_steps`** (budget reads that change iteration/point counts):
`src/landscape/optimize/driver.f90:225,422`; `src/landscape/saddle/prfo.f90:504,654`;
`src/landscape/saddle/dimer.f90:767,885`; `src/landscape/path/gsm.f90:693,699,908`;
`src/landscape/path/neb.f90:822,916,930`; `src/landscape/irc/{gs.f90:212,lqa.f90:151,hpc.f90:205,eulerpc.f90:177}`;
`src/landscape/scan/relax_scan.f90:600`; plus banner prints `tasks/{opt.f90:114,ts.f90:171,irc.f90:164}`.

**`engine%acc`** (5 reads): `src/landscape/engine/engine.f90:302`
`self%calc%accuracy = self%ctrl%acc` (**the only numeric one**), and cache-key/readback at
`:513`, `:542`, `:587`, `:829`.

⇒ Only `e_tol`, `max_steps` and `engine.f90:302` (`acc`) change numbers. The other acc reads are
consistency/cache bookkeeping.

### A4. Design four-axis table vs upstream

Design §3.5 R5 table (`docs/_simplify-recon/11-cli-redesign.md:604-612`):

| suite level | g_max | g_rms | d_max | d_rms | **e_tol (new)** | **acc (new)** | **max_steps multiplier (new)** |
|---|---|---|---|---|---|---|---|
| superloose | 4.6e-3 | 3.0e-3 | 7.9e-3 | 5.2e-3 | 5.0e-4 | 3.0 | 1 |
| loose | 2.0e-3 | 5.0e-4 | 1.0e-2 | 7.0e-3 | 5.0e-5 | 2.0 | 2 |
| normal | 3.0e-4 | 1.0e-4 | 4.0e-3 | 2.0e-3 | 5.0e-6 | 1.0 | 3 |
| tight | 1.0e-4 | 3.0e-5 | 1.0e-3 | 6.0e-4 | 1.0e-6 | 0.2 | 5 |
| vtight | 3.0e-5 | 8.0e-6 | 2.0e-4 | 1.0e-4 | 1.0e-7 | 0.05 | 20 |

`max_steps = clamp(n_atoms × multiplier, 200, 10000)` (design §3.5:612).

Upstream `get_optthr` (`src/optimizer.f90:48-119`) — **confirmed, line numbers still accurate**:

| olev | ethr | gthr | maxcycle | acc |
|---|---|---|---|---|
| crude | 5e-4 | 1e-2 | n | 3.00 |
| sloppy | 1e-4 | 6e-3 | n | 3.00 |
| loose | 5e-5 | 4e-3 | n*2 | 2.00 |
| lax | 2e-5 | 2.5e-3 | n*2 | 2.00 |
| normal (default) | 5e-6 | 1e-3 | n*3 | 1.0 |
| tight | 1e-6 | 8e-4 | n*5 | 0.20 |
| verytight/vtight | 1e-7 | 2e-4 | n*20 | 0.05 |
| extreme | 5e-8 | 5e-5 | n*20 | 0.01 |

`maxcycle=min(maxcycle,10000); maxcycle=max(maxcycle,200)` (`optimizer.f90:113-114`). The design's
`e_tol`/`acc`/multiplier columns match these values exactly (loose acc=2.0, tight acc=0.2,
normal mult=3, etc.).

### A5. Measured current observability (the falsifiability question)

**`--lopt` vs `--lopt --lopt-level tight` on water — all three axes identical today:**

```
$ cd /tmp/s3b-recon && OMP_NUM_THREADS=1 /tmp/xtb-3af/build/xtb water.xyz --gfn2 --lopt --lopt-engine sd --lopt-level tight 2>&1 | grep -iE "maximum number of steps|SCC accuracy"
 maximum number of steps:  256
 landscape engine: SCC accuracy              1.000000
$ ... (default) 2>&1 | grep -iE ...
 maximum number of steps:  256
 landscape engine: SCC accuracy              1.000000
```

Observability verdict:
- **`max_steps`** → printed `maximum number of steps:  256` (`tasks/opt.f90:114` etc.) **and** in
  `landscape_opt.json`? **No** — the JSON `counters.n_steps` is the actual steps taken, not the
  budget. So `max_steps` is observable only on stdout.
- **`acc`** → printed `landscape engine: SCC accuracy  1.000000` (from `engine%report`). **Not in
  the JSON.**
- **`e_tol`** → **printed nowhere and not in `landscape_<task>.json`.** grep of stdout and of
  `landscape_opt.json` shows no `e_tol`/`etol` token.

⇒ After 3b, the `max_steps` and `acc` changes are directly falsifiable from stdout; **`e_tol` is
not directly observable** — it can only be falsified through a *numeric* trajectory/step-count
difference, or by adding an echo line. Note this when writing the 3b acceptance tests.

---

## B — Re-baseline source table (accepted numbers)

### B6. Sources, commands, current values, and the default-level judgement

| group | value | source file:line | re-run command (OMP_NUM_THREADS=1) |
|---|---|---|---|
| M3 dfreq H2O | **0.0100** cm⁻¹ | `docs/xtb-landscape-M7-validation.md:127`; `docs/_landscape-recon/49-m7-validation-experiments.md:60`; `docs/_landscape-recon/51-m7-fix-report.md:297` | `python3 test/unit/landscape_e2e_check.py chain /tmp/xtb-3af/build/xtb water.xyz /tmp/e2e-chain` |
| M3 dfreq CH3OH | **0.0600** cm⁻¹ | `docs/_landscape-recon/49-…:61`; `51-…:298` | `test/unit/landscape_e2e_check.py` has no CH3OH mode; it is a manual experiment under `docs/_landscape-recon/m7-e2e-data/exp1-thermo/` (`exp1_thermo_check.py`) |
| M4 MB prfo-vs-bprfo | **6.3022e-06** bohr | `docs/_landscape-recon/30-m4-fix-report.md:155`; `33-m4-review-round3.md:15` | `ctest --test-dir /tmp/xtb-3af/build -R 'xtb/landscape-saddle'` → prints `prfo vs bprfo RMSD (bohr)` |
| M4 dimer-vs-prfo | **7.7397e-05** bohr | `docs/_landscape-recon/30-m4-fix-report.md:156`; `33-…:126` | same ctest target |
| M5 LEPS barrier | **8.9985** kcal/mol | `docs/_landscape-recon/41-m5-doc-fix-report.md:348`; asserted `test/unit/test_landscape_path.f90:102` (`leps_barrier = 8.9985_wp`) | `ctest -R 'xtb/landscape-path'` |
| M5 "AutoNEB 6.0823" | **6.0823** kcal/mol | `docs/_landscape-recon/41-m5-doc-fix-report.md:360` | see correction below |
| M6 MEP dev fwd gs/lqa/hpc/eulerpc | **0.03995 / 0.00657 / 0.00215 / 0.02574** bohr | `docs/_landscape-recon/44-m6-validation-experiments.md:169` | `ctest -R 'xtb/landscape-irc'` → prints `MB max MEP deviation fwd (gs/lqa/hpc/eulerpc)` |

**Correction (flag it):** `6.0823` is the **NH3** AutoNEB barrier (`41-m5-doc-fix-report.md:359-360`,
"NH3（GFN2 反转，CLI，`nh3-cli-barriers.txt`）"), **not** a LEPS number. The LEPS AutoNEB barrier is
**8.9981** (`41-…:350`, "AutoNEB（5 stage / 9 像） | 8.9981"). The LEPS *analytic* endpoint barrier is
8.9985. So the task's "LEPS autoneb 6.0823" conflates two systems.

**How tightly are these asserted?**
- M4 RMSD: only `rmsd < 1.0e-3_wp` is asserted (`test_landscape_saddle.f90:969`, `:2013`); the
  literal 6.3022e-06 / 7.7397e-05 are **printed observations**, matched against the report.
- M5 `leps_barrier = 8.9985` is asserted as the *analytic* value (`abs(energy - leps_barrier) < 1e-3`,
  `test_landscape_path.f90:462-463`); AutoNEB asserts `abs(err_kcal) < 0.5` (`test_landscape_path.f90`
  in `test_leps_autoneb`, `abs(err_kcal) < 0.5_wp`). 6.0823 itself is **not asserted anywhere in
  `test/`** (grep found no 6.0823 in test/).
- M6 MEP deviations: printed (`test_landscape_irc.f90:1427-1432`), asserted only as
  `maxval(dev_f) < 0.15 .and. maxval(dev_b) < 0.15` (`:1433`). The literals are observations.

**Judgement for the default-level question (the key re-baseline decision):**

The design §3.5 item 2 states the default `normal` change: **`max_steps` 256 → clamp(3n,200,10000)**
(H2O→200); **`acc` unchanged (1.0)**; **`e_tol` unchanged (5e-6)**. So at the default `normal` level
**only `max_steps` moves** (256 → 200 for small molecules; *larger* for big ones). Therefore:

- **M4 (unit tests, MB/HCN):** run on model surfaces with their own settings objects and default
  `max_steps=256`; MB prfo converges in ~6 steps, HCN in 4/5/15. **Unaffected** unless a test calls
  `set_conv_level` (they do not drive SCF). ⇒ RMSD values should be bit-stable.
- **M6 (unit tests):** `walk_mb(..., 2000/400, ...)` uses an **explicit budget argument**, not
  `settings%max_steps`, and the MB/LEPS surfaces have no SCF. **Unaffected.**
- **M5 (unit tests):** model surfaces, no SCF; `max_steps` budget well above what LEPS needs.
  **Unaffected.**
- **M3/M7 (CLI):** the delivered chain uses **`--lopt --lopt-level tight`**
  (`test/unit/landscape_e2e_check.py:117`, `:248`). Under R5 `tight` gains **acc=0.2** and
  **e_tol=1e-6** and **max_steps=clamp(5n,200,10000)** (water 3n=9→200). Tighter SCF + tighter
  `e_tol` ⇒ the minimised geometry converges *further*, so the `--lvib`↔`--hess` dfreq **0.0100 may
  move** (report 49 §1.2 shows dfreq grows with ‖g‖; a tighter minimum should reduce it). ⇒ **M3/M7
  is the one accepted number group that 3b plausibly moves** (via `tight`, not the default). Needs a
  re-measure after 3b, with the expected direction (smaller or equal).

Net: **3b re-baseline workload = the `tight`-level CLI numbers (M3/M7 chain, and any CLI test pinned
at `--lopt-level loose|tight|vtight`)**; the model-surface unit numbers (M4/M5/M6) are insulated. The
design's own §3.10 re-baseline list (`11-cli-redesign.md:843-874`) agrees and names the same tests.

### B7. Tests that carry these numbers

| value | test file:line |
|---|---|
| M3 H2O dfreq 0.0100 | `test/unit/landscape_e2e_check.py:28`, `:92`, `:242-243` (CLI chain; tolerance 0.20/1.00) |
| M4 RMSD (printed) | `test/unit/test_landscape_saddle.f90:968-969` (prfo/bprfo), `:2003-2013` (dimer) |
| M5 LEPS barrier | `test/unit/test_landscape_path.f90:101-102`, `:462-463`; AutoNEB `test_leps_autoneb` (`abs(err_kcal) < 0.5`) |
| M6 MEP dev (printed) | `test/unit/test_landscape_irc.f90:1427-1433` (`test_four_method_crosscheck`) |

---

## C — R4 file contract

### C8. Suite write points of the four legacy files: **confirmed 0**
```
$ grep -rn "xtboptok\|xtbopt\.log\|xtblast\|compliance" src/landscape/ | wc -l
0
```

### C9. Upstream writers (line numbers re-checked)
- `.xtboptok` / `NOT_CONVERGED`: `src/geoopt_driver.f90:112-113` `call delete_file('NOT_CONVERGED')` /
  `'.xtboptok'`; `:183` `call touch_file('NOT_CONVERGED')`; `:186` `call touch_file('.xtboptok')`.
  Also `src/prog/main.F90:1541` `call touch_file('NOT_CONVERGED')`.
- `xtbopt.log`: opened at `src/geoopt_driver.f90:121` `call open_file(ilog,'xtbopt.log','w')`.
  **Correction:** the task's `src/optimizer.f90:801` is `call writeMolecule(mol, ilog, …)` — it
  *writes to* the already-open log unit, it does not open the file. (`src/bias_path.f90:378`
  also opens `xtbopt.log`.)
- `xtblast.xyz`: `src/prog/main.F90:1026` `call generateFileName(tmpname, 'xtblast', extension, mol%ftype)`（3b 后行号；3b 前为 `:1014`）
  (guarded by "in case of failure create xtblast geometry", `:1012`).
- `compliance.dat`: written at `src/compliance.f90:287` `open(newunit=iunit, file="compliance.dat", status="replace")`
  (`write_compliance_dat`, `:253-356`). Caller/condition: `src/hessian.F90:331-334`
  `if (mol%n > 1 .and. freezeset%n == 0 .and. .not. set%periodic) call compliance_driver(env, mol, res%hess)`.

### C10. Namespace API the suite should call
`get_namespace` (`src/setparam.f90:596-614`, public through `use xtb_setparam, only: get_namespace`):
```fortran
function get_namespace(string) result(name)
   character(len=*), intent(in)  :: string
   character(len=:), allocatable :: name
! absolute path -> unchanged; leading '.' -> dot//namespace//string;
! else namespace//'.'//string; no namespace -> string
```
`iohandler`'s `getName` is **`procedure, private :: getName`** (`src/type/iohandler.f90:69`,
impl `:112-131`); the public interface is `writeFile`/`readFile`/`touchFile`/`readBinary`/`writeBinary`
(they call `getName` internally). The suite already uses `get_namespace`: `src/landscape/types/log.f90:39`,
`src/landscape/types/json.f90:61` / `:402` (`fname = get_namespace('landscape_'//trim(self%task)//'.json')`).
⇒ For a new legacy-name file (e.g. `.xtboptok`), call **`get_namespace('.xtboptok')`** (the leading
dot keeps the hidden-file spelling). `test/unit` also demonstrates the static `.xtboptok` fixture at
`test/unit/CMakeLists.txt:199,209,264`.

### C11. Best landing spots
- **`--lopt` failure path:** `src/landscape/tasks/opt.f90:216-223` — on `result%converged == .false.`
  it calls `env%error("landscape minimisation did not converge: "//result%message, source)`; the
  root message is set in `src/landscape/optimize/driver.f90:423`
  `result%message = "maximum number of steps reached"`. This is where a `.xtboptok`/`NOT_CONVERGED`
  write would belong (after `engine%destroy()` at `:201`).
- **`--lvib` Hessian call:** `src/landscape/tasks/vib.f90:161` `call landscape_vib_hessian(env, mol, chk, calc, settings, hess, …)`;
  the provider singlepoint is `src/landscape/vib/numhess.f90:138` `call engine%energy_gradient(...)`
  (a `fail` here triggers `vib.f90` `result%message = "frequency analysis failed"`).
- **File-writer wrapper shape:** `src/landscape/types/log.f90:46` `public :: landscape_write_files`;
  `:57` `subroutine landscape_write_files(env, mol, settings, traj, result)` → `:110 end subroutine`.
  One subroutine, output names routed through `get_namespace`.

---

## D — Verified failure: suite `--ohess` after a failed minimisation

### D12. Reproduction (full output)

```
$ cd /tmp/s3b-recon && OMP_NUM_THREADS=1 /tmp/xtb-3af/build/xtb water.xyz --gfn2 --ohess --cycles 2
...
 landscape task terminated: frequency analysis failed
[ERROR] Program stopped due to fatal error
-7- Landscape task terminated
-6- landscape_vib_hessian: landscape frequency analysis: the single point of the reference geometry failed
-5- landscape_engine_energy_gradient: SCC did not converge at the current geometry; the energy and gradient are discarded
-4- xtb_calculator_singlepoint: Electronic structure method terminated
-3- scf: Setup of Coulomb evaluator failed
-2- type_latticepoint_update: Could not generate lattice points
-1- landscape_optimize: landscape minimisation did not converge: maximum number of steps reached
########################################################################
abnormal termination of xtb
ERROR STOP
$ echo $?   # captured separately
1
$ ls hessian vibspectrum NOT_CONVERGED .xtboptok
(no such files)
```

**Comparisons:**
- **(a) `--lopt --cycles 2`** → exit **1**, clean single-cause message, no files:
  `-2- Landscape task terminated` / `-1- landscape_optimize: landscape minimisation did not converge:
  maximum number of steps reached`. No latticepoint/Coulomb cascade. (measured)
- **(b) native `--ohess --method ancopt --cycles 1`** → exit **0**; prints
  `*** FAILED TO CONVERGE GEOMETRY OPTIMIZATION IN 1 ITERATIONS ***`, then still runs the frequency
  analysis and **writes `hessian` + `vibspectrum` + `.xtboptok`**. (`--cycles 2` native actually
  converged and wrote `.xtboptok`.) ⇒ Native ohess never crashes and always emits the frequency
  files; the suite aborts with a misleading cascade and emits none.

**Verdict:** the defect is real — the suite's `--ohess` chain attempts the freq half after a failed
minimisation and produces a **misleading error stack** (and no frequency file).

### D13. Root cause
`Could not generate lattice points` is emitted at **`src/type/latticepoint.f90:198`**
`call env%error("Could not generate lattice points", source)` inside `type_latticepoint_update`. It
fires when `call env%check(exitRun)` at `:196` is already true — i.e. **an error was already pending
in `env`**. `generate()` for a cluster boundary condition cannot itself fail
(`src/type/latticepoint.f90:307-338`, the `cluster` case just sets `nTrans=1`, `trans=0`), so this
message is a **secondary artifact of the pre-existing error from the failed minimisation**.

The stack also carries a genuine second failure: `-5- landscape_engine_energy_gradient: SCC did not
converge`, from the `--lvib` reference singlepoint (`src/landscape/vib/numhess.f90:138`). That
singlepoint reuses the **same `calc`** object that the failed `--lopt` left in a bad state
(`main.F90:1094-1101`: the ohess chain calls `run_landscape` with `lvset`/`lres` **without checking
`lres%converged` first** and without rebuilding/resetting the calculator). The environment error is
never cleared between the two halves.

So: **two coupled defects** — (i) the chain runs vib after a non-converged opt with no guard, and
(ii) the stale calculator/env state turns the second phase's failure into the misleading
"lattice points" message.

### D14. Candidate fixes (not implemented) + side effects
1. **Guard the vib half on convergence** — after `call run_landscape(..., lres)` in the ohess chain
   (`src/prog/main.F90:1094-1101`), test `lres%converged` (or `lres%status`) and skip the vib block /
   `env%checkpoint` cleanly. *Side effect:* changes `--ohess` behaviour vs native (native still writes
   frequencies). Needs a decision: match native (always run freq) or abort cleanly. Least surprising
   for a "failed opt" is abort with the opt error only.
2. **Rebuild / reset the calculator before the vib half** — create a fresh calculator (or call the
   suite engine's reset) so the second SCF starts cold. *Side effect:* an extra SCF; must keep the
   warm/cold restart policy uniform (AGENTS §6 item 2).
3. **Clear the pending `env` error between halves** — e.g. `call env%reset()`-style before the vib
   call. *Side effect:* hides the root cause unless the opt error is *reported first*; must not
   swallow the minimisation failure. If done, sequence it **after** the opt error is printed and only
   if the run is allowed to continue.
4. **Fix the misleading message in `latticepoint`** — at `src/type/latticepoint.f90:196-198`, only
   emit the error if `env%check` newly failed; otherwise fall through. *Side effect:* upstream file
   change (touching `src/type`, which AGENTS §5 says must stay untouched) — probably out of scope for
   the suite; prefer 1–3.

Recommended: **(1) + (2)**, with a test asserting `--ohess --cycles 2` exits without the
`latticepoint`/`Coulomb` cascade.

---

## E — Self-referential documentation cleanup (lowest priority)

`man/xtb.1.adoc` still describes `--opt` as `ancopt(3)`:
- `:239` `` call `ancopt(3)` to perform a geometry optimization, ``
- `:247` `` perform a numerical hessian calculation on an `ancopt(3)` optimized ``
- `:251` `--bhess`: `` perform a biased numerical hessian calculation on an `ancopt(3)` optimized ``
- `:280` `` molecular dynamics simulation on `ancopt(3)` optimized geometry, ``
- `:284` `` call `ancopt(3)` to perform a geometry optimization, ``

`src/xhelp.f90` remaining `ancopt` mentions (3a fixed some; these are the survivors):
- `:272` `"    ANCopt is reachable as --opt --method ancopt, and the level keyword follows",`
- `:283-284` `"    the default of the task.  With --opt and --ohess the native engines ancopt",` /
  `"... (alias rf), lancopt (alias l-ancopt), fire (alias inertial) and pbc_lbfgs are",`
- `:303` `"... (use --opt --method ancopt for that block, or --lscan with --lscan-coord)",`
- `:781-782` `"... frequency analysis (the legacy ancopt(3) plus numerical Hessian path is",` /
  `"... --ohess --method ancopt)",`
- `:785` `"... perform a biased numerical hessian calculation on an ancopt(3) optimized geometry",`
- `:814` `"... molecular dynamics simulation on ancopt(3) optimized geometry,",`
- `:818` `"... call ancopt(3) to perform a geometry optimization, then try to find other",`

(`xhelp.f90:272/283/303/781` are the *reworded* stage-3a survivors — they are accurate; only the
`ancopt(3)`-as-default spellings at `:785/:814/:818` and the man lines above are the stale
"`--opt` == ancopt" claims.)

---

## Not checked (未查)
- **A5 numerical falsifiability** of an `e_tol` change (no 3b code exists; only observability shown).
- **B6 CH3OH re-run command** — `landscape_e2e_check.py` has no CH3OH mode; the value lives in the
  manual `exp1-thermo` experiment, not a registered test.
- **D native `--ohess` with a *genuinely* failed SCF** — only the geometry-non-converged native path
  was exercised; the real question (does native also cascade) is open.
- **C** whether `.xtboptok` should be written by the suite at all (design decision, R4) — not located.
- Exact `e2e_check.py` and `cli_check.py` mode coverage for M4/M5/M6 re-runs (only unit targets
  given).

## Residual risks
- The M3/M7 **`tight`-level** dfreq will very likely move under 3b (acc 1.0→0.2, e_tol 5e-6→1e-6).
  Treat 0.0100 / 0.0600 as **to-be-re-measured**, not frozen.
- `max_steps` default 256→clamp(3n,200,10000) can *increase* the budget for large molecules and
  *decrease* it for small ones; any golden test that pins `n_steps` on a small molecule is at risk.
- `e_tol` has no stdout/JSON readout ⇒ a silent `e_tol` regression is unfalsifiable without a new
  echo or a numeric test.
```
