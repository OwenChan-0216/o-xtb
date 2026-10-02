# M7 validation experiments — independent recheck of the thermo/validation close-out

> Report **49**. Role: independent validation of the M7 delivery
> (`48-m7-e2e-closeout-report.md`, `docs/xtb-landscape-M7-validation.md`).
> Everything below was measured on this checkout with `OMP_NUM_THREADS=1`
> (AGENTS.md §6.8). No production code was changed: the sha256 manifest of all
> 398 `src/**/*.f90|F90` and 59 `test/**` files is identical before and after
> (`/tmp/m7-src-before.sha256` vs `/tmp/m7-src-after.sha256`, `diff` empty).
> Raw data: `docs/_landscape-recon/m7-e2e-data/` (528 files, 3.7 MB).
>
> **Verdict: no CRITICAL/HIGH finding. The M7 acceptance numbers reproduce.
> 11 findings (1 MEDIUM on counter semantics, 1 MEDIUM on the honesty of the
> MAPLE record, the rest LOW/INFO), all with raw evidence and a disposition.**

---

## 0. What was verified and what was not

| # | Experiment | Outcome |
|---|---|---|
| 1 | G/H/ZPE of `--lvib` vs `--hess` on 4 systems + **independent recompute** | reproduce; §1 |
| 2 | `--ljson` per task/method, counters vs stdout, determinism, threads, namespace | reproduce; 1 semantics finding; §2 |
| 3 | Hand re-run of `sp → opt → hess → freq → thermo`, handover + silent-recompute audit | clean; §3 |
| 4 | MAPLE topology comparison | **MAPLE was NOT executed** — evidence in §4 |
| 5 | Re-run of the delivered validation script (all modes) | reproduce with 3 caveats; §5 |
| 6 | Falsifiability: 7 injections | 7/7 caught by at least one named test; §6 |

Not verifiable here (stated, not pretended): the meson registrations (meson is
not installed, unchanged from every earlier milestone); the `sp` task's
`--ljson` document through the command line (`sp` has no run type, API only).

---

## 1. Experiment 1 — G/H/ZPE against `xtb --hess`

Driver: `m7-e2e-data/exp1_thermo_check.py`; raw outputs
`exp1-thermo/<system>/{opt,lvib,hess}.out`, summary `exp1-thermo/summary.json`.

Protocol: `--lopt --lopt-level tight` → `xtbopt.xyz`; then **`--lvib` and
`--hess` on that same file**, so the only difference left is the projection
convention and the FD discretisation. Systems: H2O, CH3OH (12 modes), CO2 and
C2H2 (**linear, 3N−5**, the PLAN §8.2 experiment #12 case that the M7
documents do not cover).

### 1.1 Result (all values in hartree unless stated)

| system | route | ZPE | H(298.15 K) | G(298.15 K) |
|---|---|---|---|---|
| H2O | `--lvib` | 0.020124779439 | −5.046638762610 | −5.068045210878 |
| H2O | `--hess` | 0.020124765151 | −5.046638776873 | −5.068045225170 |
| CH3OH | `--lvib` | 0.045065355355 | −8.028441545302 | −8.056408109211 |
| CH3OH | `--hess` | 0.045065057893 | −8.028441852260 | −8.056408362210 |
| CO2 | `--lvib` | 0.011888568934 | −10.292932758390 | −10.317260578079 |
| CO2 | `--hess` | 0.011888551846 | −10.292932771353 | −10.317260597164 |
| C2H2 | `--lvib` | 0.026466099021 | −5.176410239961 | −5.199334884732 |
| C2H2 | `--hess` | 0.026466099055 | −5.176410239940 | −5.199334884690 |

| system | max Δν (cm⁻¹) | ΔZPE | ΔH | ΔG | ΔS (cal/mol/K) |
|---|---|---|---|---|---|
| H2O | **0.0100** | 1.429·10⁻⁸ | 1.426·10⁻⁸ | 1.429·10⁻⁸ | 0.0 (table prints 4 dp) |
| CH3OH | **0.0600** | 2.975·10⁻⁷ | 3.070·10⁻⁷ | 2.530·10⁻⁷ | 1.0·10⁻⁴ |
| CO2 | **0.0000** | 1.709·10⁻⁸ | 1.296·10⁻⁸ | 1.908·10⁻⁸ | 0.0 |
| C2H2 | **0.0000** | −3.4·10⁻¹¹ | −2.1·10⁻¹¹ | −4.2·10⁻¹¹ | 0.0 |

The H2O row reproduces the delivered **frequency** number exactly
(0.0100 cm⁻¹); the ZPE difference is 1.43·10⁻⁸ instead of the document's
1.82·10⁻⁸, which is the same order — my optimum is one `tight` iteration
further converged (‖g‖ 7.6·10⁻⁶), so the projection spread is slightly
smaller. CO2 and C2H2 (linear) are
**bit-identical in the frequency table**: with 3N−5 modes and no rotation about
the molecular axis, `trproj` and the Eckart projection coincide on the printed
precision. The ZPE/H/G residual of the linear cases is the printed frequency
precision alone (0.005 cm⁻¹ · n/2 / autorcm ≈ 2·10⁻⁸).

### 1.2 Tolerance provenance, and a documentation finding

The tolerances are defensible, and I measured their provenance independently:

* the spread is the projection convention, and it **grows with ‖g‖** and with
  the softness of the lowest mode. Displacing the converged water along random
  directions (`exp1-thermo/spread/`, 9 geometries):

  | displacement (bohr) | ‖g‖ (Eh/bohr) | max Δν (cm⁻¹) |
  |---|---|---|
  | 0 (minimum) | 7.5·10⁻⁶ | 0.0100 |
  | 0.02 | 3.5–3.9·10⁻² | 3.30–5.23 |
  | 0.05 | 1.6–6.3·10⁻² | 0.03–2.33 |
  | 0.10 | 2.0·10⁻²–1.4·10⁻¹ | 13.67–70.76 |
  | 0.20 | 1.5–4.0·10⁻¹ | 15.05–130.19 |

  This is the first *measured* confirmation of the mechanism claim in the M3
  reports (the difference is not a fixed constant, it is a gradient-dependent
  quantity).
* **Finding F2 (LOW, documentation accuracy).** The validation document §3.1
  reports CH3OH as a *"tight minimum"* with 0.5200 cm⁻¹ and ΔZPE −1.71·10⁻⁶.
  My tight minimum gives **0.0600 cm⁻¹ / +2.98·10⁻⁷** (6–10× smaller). Running
  the *same* methanol at the **default** `--lopt` level gives ‖g‖ = 3.86·10⁻⁴
  and **0.8900 cm⁻¹**, which brackets the reported 0.52. So the reported CH3OH
  row is a *default-level* minimum (or a different input), not a tight one.
  Consequence: the 1.00 cm⁻¹ CH3OH tolerance has only ~12 % margin at the
  default level and no margin at all if the soft torsion mode is slightly
  softer; it is 17× the tight-level measurement. **Disposition:** documentation
  fix (state the input, the level and the measured value per level). The
  delivered CLI chain test uses H2O at `tight` (0.0100 vs 0.20 tolerance, 20×
  margin) and is unaffected. Raw: `exp1-thermo/ch3oh-normal/`.

### 1.3 Independent recompute (not a second run of the same code)

`m7-e2e-data/thermo_independent.py` is a from-scratch Python implementation of
the same physical model — rigid rotor + harmonic oscillator with the
Head-Gordon free-rotor switching at the rotor cutoff, Sackur-Tetrode
translation at 1 atm, symmetry number taken from the printed SETUP block,
principal moments from the geometry and the atomic masses. It reads the
*printed frequency table* and the geometry, so it shares no code with xtb.

Residual `xtb printed − my recompute`:

| system | route | ΔZPE (Eh) | ΔS_tot (cal/mol/K) | ΔH_thermal (Eh) | ΔG (Eh) |
|---|---|---|---|---|---|
| H2O | lvib / hess | −6.7·10⁻⁹ / +1.8·10⁻⁹ | +3.44·10⁻⁵ | +4.21·10⁻⁹ | −1.6·10⁻⁹ |
| CH3OH | lvib / hess | −1.27·10⁻⁸ / −1.40·10⁻⁸ | +4.63·10⁻⁵ / +3.47·10⁻⁵ | +9.85·10⁻⁹ | +2.0·10⁻⁸ |
| CO2 | lvib / hess | −3.3·10⁻⁹ / −2.0·10⁻⁸ | −1.08·10⁻⁵ | −2.6·10⁻⁹ | −2.2·10⁻⁹ |
| C2H2 | lvib / hess | +1.05·10⁻⁸ | +3.28·10⁻⁵ | +4.5·10⁻⁹ | +7.2·10⁻⁹ |

The ΔZPE residual is exactly the 2-decimal rounding of the printed frequency
table (0.005 cm⁻¹ × n/2 / autorcm), i.e. **the recompute agrees with xtb to the
precision of the data it was given**. ΔS_tot agrees to ≤4.7·10⁻⁵ cal/mol/K
(≤1.0·10⁻⁶ relative), which is the mass table + geometry + constant
difference. This is a genuine independent validation of the *model*, not just
of the two routes agreeing with each other.

### 1.4 The "false pass" traps — thermochemical parameters audited one by one

Both routes go through the same reused `main_freq`/`print_thermo`/`thermodyn`
(`src/thermo.f90:79`), so a parameter that is wrong *in both* cannot be seen by
comparing them. I therefore read the parameter block of every run and checked
it against xtb's own defaults (`src/setparam.f90:287-294`) and the landscape
settings defaults (`src/landscape/types/settings.f90:581-596`):

| parameter | `--lvib` printed | `--hess` printed | xtb default |
|---|---|---|---|
| temperature | 298.15 K | 298.15 K | 298.15 K ✓ |
| scaling factor | 1.0000000 | 1.0000000 | `thermo_fscal = 1.0` ✓ |
| rotor cutoff | 50.0 cm⁻¹ | 50.0 cm⁻¹ | `thermo_sthr = 50.0` ✓ |
| imaginary cutoff | −20.0 cm⁻¹ | −20.0 cm⁻¹ | `thermo_ithr = −20.0` ✓ |
| mode count | 3 / 12 / 4 / 7 | same | 3N−6 or 3N−5 ✓ (CO2/C2H2 → 4/7) |
| linear flag, symmetry, rotational number | false/c2v/2, false/c1/1, true/din/2, true/din/2 | identical | ✓ |

All nine fields are **identical between the two routes for all four systems**
(`params[...].equal == True`). The pressure is not a knob at all: `thermodyn`
hard-codes the 1 atm standard state (`s_tr = R·(… − log(atmtoau) …)`,
`src/thermo.f90:222`), so it cannot differ between routes. My independent
Sackur-Tetrode recompute at P = 101325 Pa reproduces the printed `TR` entropy
to 3·10⁻⁵ cal/mol/K, which *independently confirms* that the standard state is
1 atm and that the translational term is right.

**Every parameter is also proven live by a knob experiment** (so that "it is
in the settings object" is not confused with "it reaches the model"), H2O,
`exp1-thermo/knobs/`:

| run | ZPE | H(T) | G(T) | exit |
|---|---|---|---|---|
| default | 0.020124779439 | −5.046638762610 | −5.068045210878 | 0 |
| `--lvib-temp 500` | 0.020124779439 (unchanged, correct) | −5.044000559037 | −5.083270525523 | 0 |
| `--lvib-freq-scal 1.01` | 0.020326027234 = **exactly 1.01×** | −5.046437774686 | −5.067843922926 | 0 |
| `--lvib-rotor-cutoff 1e5` | unchanged | unchanged | −5.067415444247 | 0 |
| `--lvib-temp 0` | — | — | — | **1 (aborts)** |

My independent recompute tracks the `temp 500`, `scal 1.01` and
`rotor-cutoff 1e5` runs to 2.5·10⁻⁸ Eh and 4.3·10⁻⁵ cal/mol/K as well.

* **Honest limitation:** an independent recompute that *reads the parameters
  from the output* cannot detect a wrong parameter — it follows it. Only a
  cross-route comparison (`--hess`) or a parameter-independent identity
  (`ZPE = ½Σν/autorcm`, which the unit test asserts) can. Both exist; injection
  4 in §6 is red on both.

---

## 2. Experiment 2 — independent `--ljson` verification

Driver: `m7-e2e-data/ljson_verify.py` (written from scratch, shares no code
with `test/unit/landscape_e2e_check.py`); result `exp2-ljson/verify.json`, raw
runs under `exp2-ljson/<task>/`.

### 2.1 Per-task result

| task | JSON valid | key order | counters vs **its own stdout** | determinism (2 processes) | namespace | OMP 2/4 identical |
|---|---|---|---|---|---|---|
| opt | ✓ | ✓ | ✓ (`energy calls`/`cache misses`/`steps`/`final energy`/`etemp`) | ✓ | ✓ | ✗ |
| scan 1D | ✓ | ✓ | ✓ (`n_points` = frames of `xtbscan.log` **and** the printed "wrote … with N frame(s)", `lowest energy`, `energy evaluations`) | ✓ | ✓ | ✗ |
| scan 2D | ✓ | ✓ | ✓ (same, `lowest grid energy`) | ✓ | ✓ | ✗ |
| vib | ✓ | ✓ | ✓ (`energy evaluations`, `# imaginary freq.`, ZPE, H(T), G(T), temperature, scaling factor, `# frequencies`, etemp, n_zero+n_vib = n_modes) | ✓ | ✓ | ✗ |
| ts | ✓ | ✓ | ✓ (`energy calls`/`cache misses`/`steps`/`imaginary modes`/`final energy`) | ✓ | ✓ | ✗ |
| irc | ✓ | ✓ | ✓ (`forward/backward points`, `imaginary modes`, `transition state energy`, `step length`) | ✓ | ✓ | ✗ |

All 8 `ts` methods and all 4 `irc` methods write a parseable document whose
`method` counter equals the method identifier; the four band searches exit 1
(step budget exhausted at `--lts-max-steps 20`, which is the documented
"not usable ⇒ non-zero exit" semantics) while still writing their document.

### 2.2 Thread-count stability (recorded, quantified)

The document is **byte identical between two runs at the same thread count**
(6/6 tasks), but **not across thread counts**. Recursive numeric diff of the
two documents:

| task | max abs Δ (OMP=2) | max abs Δ (OMP=4) | differing float fields | counters changed |
|---|---|---|---|---|
| opt | 1.36·10⁻¹² | 1.82·10⁻¹² | 29 / 28 | none |
| scan 1D | 6.75·10⁻¹⁵ | 2.73·10⁻¹² | 20 / 25 | none |
| scan 2D | 9.09·10⁻¹³ | 3.18·10⁻¹² | 10 / 10 | none |
| vib | 2.42·10⁻¹⁰ | 2.44·10⁻¹⁰ | 9 / 9 | none |
| ts | 9.73·10⁻¹¹ | 1.16·10⁻¹⁰ | 24 / 21 | none |
| irc | 4.28·10⁻¹² | 2.42·10⁻¹² | 171 / 171 | none |

This is the AGENTS.md §6.1 OpenMP reduction-order effect (~10⁻¹⁴ Eh/bohr)
amplified by the 17-digit writer. **Finding F8 (INFO):** a JSON regression
baseline must pin `OMP_NUM_THREADS` (the delivered CLI checks do: the ctest
property sets it to 1). Counters are stable, so a *counter-level* comparison
is thread-safe; a *byte* comparison is not.

### 2.3 Counter semantics: `ts` reports two different evaluation counts

* **Finding F3 (MEDIUM, semantics/documentation).** In one and the same `ts`
  stdout (`exp2-ljson/ts/stdout.txt`):

  ```
  steps:          4
  energy calls:   5
  cache misses:   77
  ...
  landscape engine: energy evaluations 95
  landscape engine: cache hits         0
  landscape engine: Hessians           5
  ```

  `tasks/ts.f90:255` sets `result%n_cache_miss = engine%n_eval` **before**
  `confirm_saddle` runs, and the confirmation adds one FD Hessian (6N = 18
  evaluations for HCN); the engine report is printed after it. 95 − 77 = 18
  exactly. So the task's printed "cache misses" and the JSON `n_cache_miss`
  are the count *of the search*, not of the run, while the engine's own report
  at the end of the same stdout gives the run total. A regression comparison
  on `n_cache_miss` is therefore sensitive to where the counter was sampled,
  and a reader of the two printed lines cannot tell which is meant.
  Not a wrong physical result (`opt`/`vib`/`scan` have no post-count Hessian
  and agree: 7/7, 19/19, 43/43). **Disposition: report only** (I must not
  change `src/`); suggested fix: read the counter after `confirm_saddle`, or
  print the two numbers under distinct names.

### 2.4 Coverage gaps found by the injections (§6)

* **Finding F4 (LOW, coverage).** `xtb/landscape-ljson-scan` does **not**
  cross-check `n_eval`: with the injected `n_eval + 1` it stays green, while
  my independent checker reports `n_eval(engine): json=44 stdout=43`. The
  delivered check for `scan` covers `n_points`, `energy` and (in the other
  tasks) `n_eval`; adding the `landscape engine: energy evaluations` assertion
  would close it.
* **`sp` is API-only** (no run type). Its document is exercised by the unit
  case `sp-ljson` (asserts `"task": "sp"`, status, `n_eval`, an energy key);
  there is no printed counter table to cross-assert against, so this document
  has no CLI-level counter check. Recorded as a known gap, not a defect.

---

## 3. Experiment 3 — independent re-run of the chain

Driver: `m7-e2e-data/exp3_chain_check.py`; raw `exp3-chain/`, summary
`exp3-chain/chain.json`. Every step is a separate process in its own
directory; the "chain" is emulated with exit-status checks (there is no chain
runner in the product).

### 3.1 Handover audit

| step | command | result |
|---|---|---|
| sp | `xtb h2o.xyz --gfn 2` | E = −5.070383095219 (input geometry) |
| opt | `--lopt --lopt-level tight` | `final energy` **= −5.070544447778**, `xtbopt.xyz` header **= −5.070544447778** (bitwise equal at printed precision), `landscape: converged` |
| hess | `--hess xtbopt.xyz` | `TOTAL ENERGY` = −5.070544447778 **= the file's energy**, `hessian` written |
| vib | `--lvib xtbopt.xyz` | `TOTAL ENERGY` = −5.070544447778 **= the file's energy**; gradient norm 7.51·10⁻⁶ Eh/bohr (a stale geometry would show here); ZPE 0.020124779439, H −5.046638762610, G −5.068045210878 |

**The geometry is really read from the file:** moving one H by 0.05 bohr and
re-running the identical command changes the printed energy to −5.068148015168
(Δ = 2.4·10⁻³ Eh). No cached geometry.

### 3.2 Silent recomputation / fallback audit

* `--lvib` and `--hess` **both recompute** the FD Hessian (by design: the M7
  chain is a sequence of independent commands, not a session).
* `--lvib-hessian file --lvib-hessian-file 3-hess/hessian` does **not**
  recompute: energy evaluations drop from **19 → 1** and the frequencies come
  from the file. Verified live, not inferred from the flag's existence.
* **Finding F10 (INFO, behaviour a chain user must know):** the `hessian`
  file written by `--lvib` is the **projected, non-mass-weighted** matrix
  (`tasks/vib.f90:30,340`). The file route therefore applies a *second*
  projection. Measured: the file route reproduces `--hess` **exactly**
  (frequencies 1539.58 / 3643.01 / 3651.16 identical, ZPE 0.020124765152 vs
  0.020124765151) and differs from the `--lvib` FD route by 0.01 cm⁻¹ /
  1.4·10⁻⁸ Eh. The double projection is idempotent to 1.0·10⁻¹⁰ Eh/bohr²
  (max |Δ| over the 81 matrix elements of the round trip), which is why the
  result stays at the `trproj` numbers. This is a *strong* cross-validation
  (two independent implementations agreeing through a file interface), but a
  user expecting "freq on the `--hess` file = `--lvib`" gets the `--hess`
  numbers instead. Worth one sentence in the user guide.

### 3.3 Failure injection

`--lvib --lvib-hessian file --lvib-hessian-file missing_file`:
exit **1**, no `hessian`/`vibspectrum`/`g98.out`/`vib_normal_modes` written,
`[ERROR] … cannot open Hessian file` on stderr, and a `cmd1 && cmd2` shell
chain stops (`chain stopped (first step failed)`). The failure path is
therefore visible to a `set -e` chain *and* to a runner that looks for
artefacts.

---

## 4. Experiment 4 — MAPLE

### 4.1 MAPLE was NOT executed — evidence

`exp4-maple/maple_probe.txt`:

```
$ python3 -c 'import maple'                      -> OK  (the package __init__ is shallow)
$ python3 -c 'from maple.function.dispatcher import Dispatcher'
    from ase import Atoms
ModuleNotFoundError: No module named 'ase'
$ python3 -c 'import ase'      -> MISSING
$ python3 -c 'import torch'    -> MISSING
$ python3 -c 'import fairchem' -> MISSING
```

No `ase`, no `torch`, no `fairchem`, no virtualenv in the checkout. MAPLE's
dispatcher cannot even be imported, let alone run a task; and even with the
dependencies the example tree drives ANI-1xnr / AIMNet2 / MACE
(`examples/irc/hpc/inp1.inp` → `#model=ANI-1xnr`, `#device=gpu0`) with
checkpoints and a GPU stack that are not part of the checkout. **No MAPLE job
was run. Nothing below is a MAPLE measurement.**

### 4.2 Finding F6 (MEDIUM, honesty of the delivered record)

The delivered `maple` mode reports

```json
"maple_importable": true, "maple_import_error": "", "maple_executed": false
```

`maple_importable` is the return code of `python3 -c "import maple"`, which
succeeds although **MAPLE cannot execute anything** (the failure is one level
deeper, in `maple.function.dispatcher`). `maple_executed: false` is correct and
the conclusion text is honest, but `maple_importable: true` next to an empty
`maple_import_error` reads as "MAPLE is available here" — exactly the kind of
false green this project's honesty rule forbids. **Disposition: report only.**
Suggested fix: probe `from maple.function.dispatcher import Dispatcher` (and
record the missing dependency), or rename the field to
`maple_toplevel_importable`.

### 4.3 What *is* comparable (topology only) — independently reproduced

The committed fixture `examples/irc/hpc/inp1_full.xyz` analysed from scratch
(`exp4-maple/fixture_topology.txt`): 65 frames, 7 atoms, E(first) =
−29.6075593746, E(last) = −29.6804457521, E(min) = −29.7099845177,
**1 interior minimum (frame 29) and 1 interior maximum (frame 30)** — the path
overshoots its minimum and climbs back. The delivered mode reports the same
(1/1, 65 points), so its fixture analysis is correct; it is a property of the
committed file, not of a run.

This suite's own topology on the same task class (from `maple.json`, produced
by the delivered mode and reproduced in `exp5-script/maple.log`): HCN/HNC
`--lts prfo` → 1 first-order saddle; `--lirc hpc` → 2 endpoint minima
(−5.504037644799, −5.504031002295 Eh), both reached.

**Honest statement of the comparison:** the two topologies are *not* the same
object (different molecule, different direction count, one path, one
potential). What may be compared is only "the TS task produces a first-order
saddle and the IRC produces two distinct endpoint minima"; a numerical
comparison is forbidden (MAPLE fixtures are ML potentials, PLAN R-14/N9) and
the frequency constants differ by ≈0.04 % (PLAN §12.11 INFO-2). No claim of
numerical agreement is made anywhere in this report.

---

## 5. Experiment 5 — re-running the delivered validation script

`exp5-script/`, logs `chain-abs.log`, `chain-relative.log`, `layers-abs.log`,
`maple.log`.

| mode | exit | output |
|---|---|---|
| `chain` (absolute rundir) | 0 | `max dfreq 0.0100 cm⁻¹ (tol 0.20), dZPE 1.429e-08, dH 1.426e-08, dG 1.429e-08 (tol 1.4e-06)` — identical to my independent measurement |
| `chain-failure` | 0 | `step 2 exited 1 and the reference step did not run` |
| `ljson-methods` | 0 | 8 ts + 4 irc methods |
| `maple` | 0 | topology record (see §4) |
| `layers` (absolute rundir) | 0 | `layers: 7 checks passed` |

**Finding F5 (LOW, robustness).** With a **relative** `rundir` the `chain` and
`layers` modes fail with a misleading message: `FAIL: the chain frequency step
exited 1 … No input file given, so there is nothing to do`
(`chain-relative.log`). Cause: the runner passes an absolute-relative path as
the input and then sets `cwd=rundir`, so the relative input no longer resolves.
The documented reproduction example uses `/tmp/...` (absolute) and ctest passes
an absolute `-DRUNDIR`, so the delivered tests are unaffected; a user
following the natural "give it a directory name" habit hits it. Suggested fix:
`rundir = os.path.abspath(rundir)` at entry.

**Finding F7 (LOW, coverage of the "layers" claim).** `layers` executes
4 L1 suites + 2 L2 suites + 1 L3 leg:

```
L1 landscape-optimize-math, landscape-irc, landscape-saddle, landscape-path
L2 landscape-optimize-xtb, landscape-vib
L3 chain
```

That is 6 of the **14** landscape unit suites (missing L1/L2:
`landscape-api`, `landscape-settings`, `landscape-coords`,
`landscape-hessian-update`, `landscape-cg`, `landscape-hessian`,
`landscape-failure`, `landscape-scan`), and the **`ts → irc` L3 leg is not
part of the layered report** (it exists only as the Fortran case
`hcn-ts-irc-endpoints` and inside the `maple` mode). The script does *execute*
what it lists (it is not merely a re-listing of names), but the "L1+L2+L3 in
one structured report" claim overstates the coverage. Suggested fix: extend
the two suite lists (cheap, they are already ctest targets) and add the
`ts → irc` leg.

**Finding F1 (LOW, test hygiene).** `xtb/landscape-e2e-chain-failure` asserts
the *absence* of `hessian`/`vibspectrum`/`g98.out` in its rundir **without
cleaning it first**. Any earlier run that left one of those files there (e.g.
the injected run of §6, or a manual run) makes the test fail with
`FAIL: the chain continued after a failed step (hessian exists)` although the
product behaved correctly. Measured: exit 8 with the stale files present,
`100% tests passed` after `rm -rf` of the rundir, and still passing on a
second run. Suggested fix: remove the artefacts (or the rundir) at the start
of `check_chain_failure`.

---

## 6. Falsifiability — 7 injections

Harness: `m7-e2e-data/run_injections.py` (exact-text replacement, uniqueness
asserted, file restored in a `finally` block, sha256 compared, rebuild
verified to have compiled the mutated unit — `compiled: true` for all 6 source
injections; the runner injection needs no build). Raw:
`m7-e2e-data/injections/injections.json` (+ full ctest output per test).

| # | injection | file | tests that turned RED | claim it falsifies |
|---|---|---|---|---|
| 1 | `n_eval → n_eval + 1` in the shared result block | `types/json.f90` | `xtb/landscape-ljson-opt` (`counter n_eval is 8 but stdout says 7`), `xtb/landscape-e2e` (`ljson-determinism`, `sp-ljson`) | the JSON counter is the printed number |
| 2 | random suffix on the message in the **builder** | `types/json.f90` | `xtb/landscape-ljson-opt` (`not reproducible between two runs`) | the document is process-deterministic |
| 3 | random suffix on the message in the **writer** | `types/json.f90` | `xtb/landscape-ljson-opt`, `xtb/landscape-e2e` (`the two JSON files differ`) | the writer is deterministic |
| 4 | chain runner ignores the exit status **and** runs the reference step | `test/unit/landscape_e2e_check.py` | `xtb/landscape-e2e-chain-failure` (`the chain continued after a failed step (hessian exists)`) | a silently continuing runner is caught |
| 5 | `set%thermo_fscal = freq_scal * 1.01` | `vib/thermo.f90` | `xtb/landscape-e2e-chain` (`chain ZPE differs from --hess by 2.013e-04 hartree`), `xtb/landscape-e2e` (`the zero point energy is not the half sum of the internal frequencies`) | the thermochemical parameters reach the reused model |
| 6 | scan "no converged point" `env%error` → `env%warning` | `tasks/scan.f90` | `xtb/landscape-scan-max-steps` (`a scan without a converged point exited 0`), `xtb/landscape-scan` (`scan-task-unconverged`, `scan-task-no-converged-point`) | a non-usable result exits non-zero |
| 7 | `n_points → n_points + 1` in the 1D scan document | `tasks/scan.f90` | `xtb/landscape-ljson-scan` (`n_points is 4 but xtbscan.log holds 3 frames`) | the scan counter is the written frame count |

All 7 restored byte-identically (`restored: true`) and the tree rebuilt clean;
after the revert every affected test is green again.

**Notes on two injections (the "prove the mutation is the logic you claim"
rule, AGENTS.md §6 / report 34 §1):**

* Injection 2 (builder) turns the **CLI** test red but leaves the **unit**
  case `ljson-determinism` green. That is *not* a hole: the unit case writes
  the **same document object twice**, so a value fixed once at build time
  cannot differ between the two writes. Injection 3 (writer) is the
  complementary mutation and turns the unit case red — the pair together
  covers both levels. **Finding F11 (INFO):** the unit case alone cannot
  falsify builder-level non-determinism; the CLI check is what does.
* Injection 1 leaves `xtb/landscape-ljson-scan` green (finding F4): the scan
  check does not cross-assert `n_eval`. My independent checker, run against
  the same injected build, reports
  `opt: n_eval: json=8 stdout=7`, `scan1d: json=44 stdout=43`,
  `scan2d: json=31 stdout=30`, `vib: json=20 stdout=19` — so the coverage
  exists outside the delivered suite, it is just not in it.
* A first ad-hoc attempt at injection 1 appended `+ 1` after the closing
  parenthesis (`… result%n_eval) + 1`), which is a **syntax error**: the build
  failed, the test ran the *unmutated* binary and stayed green. This is the
  M4 lesson again — a green result from a failed build proves nothing. The
  harness now records `compiled` for exactly this reason.

---

## 7. Build, tests, tree state (final)

| check | result |
|---|---|
| `cmake --build /tmp/xtb-land/build -j` | clean, **0 warnings** |
| `OMP_NUM_THREADS=1 ctest -R landscape` | **90/90 passed** (25.9 s) |
| `ctest -R 'Singlepoint\|GFN\|model-hessian\|optimizer\|Argparser\|CAPI'` | **12/12 passed** (0.23 s) |
| `ctest -N -R landscape` | 90 tests registered |
| duplicate `add_test` names | none (`uniq -d` empty) |
| `src/**` sha256 manifest (398 files) | **unchanged** by this round |
| `test/**` sha256 manifest (59 files) | **unchanged** by this round |
| repo artefacts | removed (`xtbopt.xyz`, `landscape_*.json`, `charges`, `wbo`, `xtbtopo.mol`, `compliance.dat`, `vibspectrum`, `vib_normal_modes`); no `Testing/` inside the repo |

The 20 modified `src/`+`test/` files in `git status` are the inherited M7
delivery (`48-m7-e2e-closeout-report.md` §9); none of them was touched here.

---

## 8. Findings and dispositions

| # | sev | finding | disposition |
|---|---|---|---|
| F3 | **MEDIUM** | `ts` prints `cache misses: 77` and the engine prints `energy evaluations 95` in the same stdout; the JSON carries the pre-confirmation number (`tasks/ts.f90:255`) | report only (no `src/` edits allowed); fix = sample after `confirm_saddle` or rename |
| F6 | **MEDIUM** | the `maple` mode reports `maple_importable: true` although MAPLE cannot import its dispatcher (`ase` missing) | report only; fix = probe the dispatcher / rename the field |
| F2 | LOW | validation doc §3.1 CH3OH row is a default-level minimum, not a "tight minimum" (measured 0.89 vs 0.06 cm⁻¹); the 1.00 cm⁻¹ tolerance has 12 % margin there | documentation fix |
| F4 | LOW | `xtb/landscape-ljson-scan` does not cross-check `n_eval` | add the `energy evaluations` assertion |
| F5 | LOW | `landscape_e2e_check.py` fails with a misleading message on a relative `rundir` | `os.path.abspath(rundir)` |
| F1 | LOW | `xtb/landscape-e2e-chain-failure` fails on stale artefacts in its rundir | clean the rundir before asserting absence |
| F7 | LOW | `layers` covers 6 of 14 landscape unit suites and one of the two L3 legs | extend the lists / restate the claim |
| F8 | INFO | the JSON is not byte identical across OMP thread counts (≤2.4·10⁻¹⁰ abs, counters stable) | pin `OMP_NUM_THREADS` in any JSON baseline (already done in ctest) |
| F9 | INFO | `n_imag = -1` sentinel in `opt`/`scan`; `n_eval` means "objective evaluations" for `opt`/`ts` and "engine evaluations" for `scan`/`vib` | document the sentinel and the per-task meaning |
| F10 | INFO | the `hessian` file round trip re-projects (idempotent to 1·10⁻¹⁰), so `--lvib --lvib-hessian file` reproduces `--hess`, not `--lvib` | one sentence in the user guide |
| F11 | INFO | the unit `ljson-determinism` case cannot catch builder-level non-determinism | none needed; the CLI check covers it |

No CRITICAL/HIGH finding. No finding requires a change to the delivered
acceptance numbers; F2/F5/F7 are documentation/coverage accuracy, F3/F6 are
semantics/naming.

---

## 9. PLAN backfill suggestions

1. **§9.8 acceptance table**: replace the CH3OH row with measured values at a
   *stated* level — `tight` 0.0600 cm⁻¹ / ΔZPE +2.98·10⁻⁷ Eh,
   `--lopt` default 0.8900 cm⁻¹ — and add CO2 and C2H2 (linear, 3N−5), where
   the two routes agree to the printed precision (0.0000 cm⁻¹).
2. **§9.8 / validation guide §3.1**: add the measured ‖g‖ → Δν table of §1.2 as
   the stated provenance of the tolerance (it replaces the qualitative
   "grows with ‖g‖" with a measurement).
3. **§12.11**: add the `ts` `n_cache_miss` sampling semantics (F3) next to the
   existing INFO items, and the `n_imag = -1` sentinel (F9).
4. **§12.11 / validation guide §4**: state that a byte-level JSON regression
   baseline requires a pinned `OMP_NUM_THREADS` (F8).
5. **§9.8 MAPLE record**: replace `maple_importable` with a probe of the
   dispatcher, and state the missing dependency (`ase`, `torch`,
   `fairchem`) rather than an empty import error (F6).
6. **§6.5 GS Lagrange repair**: untouched, as instructed.
7. Nothing in this round changes any acceptance number or any `src/` file.

---

## 10. Data inventory (`docs/_landscape-recon/m7-e2e-data/`)

| path | content |
|---|---|
| `thermo_independent.py` | independent RRHO/free-rotor recompute (reads stdout + xyz) |
| `exp1_thermo_check.py`, `exp1-thermo/` | 4 systems × {opt, lvib, hess}, `summary.json`, `knobs/` (5 runs), `spread/` (9 geometries), `ch3oh-normal/` |
| `ljson_verify.py`, `exp2-ljson/` | 6 tasks × {run, stdout.txt, json, `-again`, `-omp2`, `-omp4`, `-ns`}, 8 ts + 4 irc method runs, `verify.json` |
| `exp3_chain_check.py`, `exp3-chain/` | the hand-run chain, perturbation probe, Hessian-file reuse, failure probe, `chain.json` |
| `exp4-maple/` | `maple_probe.txt` (import evidence), `maple.json`, `fixture_topology.txt` |
| `exp5-script/` | re-run of every mode of `test/unit/landscape_e2e_check.py` + `layers.json` + the relative-path failure log |
| `run_injections.py`, `injections/` | the 7 injections, `injections.json` (full ctest output per test), sha256 before/after |
