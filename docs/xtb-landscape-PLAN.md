<!-- The development review reports cited below (the numbered reports under docs/_landscape-recon/ and docs/_simplify-recon/) and AGENTS.md are not part of this repository. -->
# xtb landscape suite implementation plan (PLAN)

> Status: **the landing plan for an approved direction** (a PLAN-stage deliverable, containing no Fortran code)
> Target repository: `/home/owenchan/work_path/coding/fortran/xtb` (graf mode; current HEAD `1779020`, version `6.7.1`, see `CMakeLists.txt:29`)
> Engine: GFN2-xTB (`TxTBCalculator`, `src/xtb/calculator.f90:60`)
> Evidence sources (the provenance of every technical assertion in this plan):
> - **R01** `docs/_landscape-recon/01-maple-dispatcher-architecture.md` (the MAPLE algorithm list and defaults)
> - **R02** `docs/_landscape-recon/02-xtb-current-capabilities-audit.md` (xtb's status and reuse surface)
> - **R03** `docs/_landscape-recon/03-python-to-fortran-feasibility.md` (feasibility grading, numerical hygiene, LOC)
> - **R04** `docs/_landscape-recon/04-web-research-ts-irc-state-of-art.md` (formulas/step lengths/failure modes/de-risking list)
> - **R05** `docs/_landscape-recon/05-fortran-prior-art-and-interface-design.md` (DL-FIND, reuse decisions, the recommended design, M0–M7)
>
> Line numbers of the form `(file:line)` in this plan were **measured and confirmed in this repository at the time of writing**; references of the form `[R04 §2.1]` point at the reports above.
> The only permitted exception annotation is `[to be calibrated]`, meaning the default value has a unit/value ambiguity, with the milestone and experiment number responsible for calibrating it already specified.

---

## Table of contents

1. Summary and decision record (D1–D4)
2. Problem statement: the task-completeness gap of ANCopt
3. MAPLE comparison matrix
4. Overall architecture
5. Interface contract
6. Algorithm list and sources
7. Numerical-hygiene rules
8. Test strategy
9. Phased milestones M0–M7
10. Risk register
11. Things explicitly not done
12. Integration points

---

## 1. Summary and decision record

### 1.1 Summary

xtb 6.7.1 already has `sp / opt / scan / hessian / freq` (the capability matrix of R02 §0),
but it has **no transition-state optimiser, no intrinsic-reaction-coordinate integration and no chain-of-states** (R02 §5).
The maintainers answer explicitly in issue #494, "xtb does not implement a transition state optimizer" (R04 §83).
This plan adds a `src/landscape/` module tree inside the xtb repository, rebuilding the whole
`sp / opt / scan / ts / hessian / freq / irc` PES task set in Fortran, with the algorithms based on the literature and on the
MAPLE (Python) implementation as a comparison baseline (R01/R03), reusing xtb's private kernels
(`TCalculator`, `tb_anc`, `bfgs/powell`, `numhess`, `trproj`, `model_hessian`, `constrain_pot`).
Design principles: **an abstract engine boundary + a replaceable Hessian provider + no global state + a.u. internal units**.

### 1.2 Decision record (ruled by the upstream repository owner, recorded verbatim)

**D1 — landing location.**
> Integrate into the xtb repository, adding a `src/landscape/` module tree with the module prefix `xtb_landscape_*`, wired in through `set_runtyp` +
> the `src/prog/main.F90` dispatch of the new subcommands. Reuse xtb's private modules directly
> (`class(TCalculator)%singlepoint/hessian`, `tb_anc`, `numhess`, `trproj`, `freq/*`, `constrain_pot`).
> Do not create a standalone project and do not make an independently compilable sub-library.

*Consequence*: the new code becomes part of `libxtb` (the same mechanism as `src/freq/**`,
the `add_subdirectory("freq")` of `src/CMakeLists.txt:24` + the
`set(dir ...)` / `list(APPEND srcs ...)` / `set(srcs ${srcs} PARENT_SCOPE)` of `src/freq/CMakeLists.txt:18-26`). It must therefore **obey xtb's existing compilation flags and language-level constraints**
(GNU: `-fdefault-real-8 -fdefault-double-8 -ffree-line-length-none -fbacktrace`, R02 §7.3),
and **must not introduce any new external dependency** (no Ipopt, no torch, no scipy equivalent).
A new module may `use` xtb private modules directly, but reverse dependencies are **forbidden** (existing xtb modules must not `use xtb_landscape_*`).

**D2 — scope.**
> Implement the whole set sp / opt / scan / ts / hessian / freq / irc. TS includes PRFO, B-PRFO (monomolecular), dimer,
> NEB, CI-NEB, AutoNEB, string (GSM). IRC includes GS, HPC, LQA, EulerPC.
> Explicitly excluded: DMF (needs cyipopt/Ipopt), the batch GPU version of blbfgs/BPRFO, ML-potential calculators, parmfit, MD ensembles.

*Consequence*: the target algorithms are about **20k lines** of Fortran LOC (the sum of the per-file estimates of R03 §B + drivers/tests),
and must be advanced in 8 milestones (§9). The term `B-PRFO` cannot be uniquely localised in the public literature (R04 §25, confidence low);
**the interpretation this plan adopts**: B-PRFO = the **RS-P-RFO (restricted-step
partitioned RFO) monomolecular version** implemented by MAPLE `ts/algorithm/BPRFO.py` (`BPRFO.py:52-80`'s parameters `trust_init/trust_min/trust_max/hessian_update`
are of the same family as monomolecular PRFO), whose only structural difference from PRFO is the trust-radius split ratio
`alpha` between the uphill/downhill subspaces (`alpha∈[0.05,0.95]` at `PRFO.py:140-351`) and its not relying on batched tensors.
If the repository owner has a different definition of "B" (Baker / Banerjee), only the single file `saddle/bprfo.f90` of M4 needs replacing,
without affecting the interface contract.

**D3 — Hessian strategy.**
> Numerical Hessians take priority. The initial guess uses model_hessian (Lindh/Swart/EEQ), recomputation uses numhess (central differences, step 0.005 bohr),
> and along a path Bofill/BFGS/Powell/SR1 updates are used. But the Hessian provider must be abstracted into a replaceable abstract interface,
> reserved for inserting an analytic implementation in the future.

*Consequence*: the Hessian is the **only cross-task common dependency** (needed by RFO/PRFO/all IRC/freq, R01 §0),
so the abstraction must be placed in M0, not deferred to M3. A numerical Hessian costs **6N E+G calls**
(R04 §85; `TCalculator%hessian` is a two-sided difference, `src/type/calculator.f90:103`),
and the defaults of `Δt` and `accu_hess` **follow xtb** (`step_hess = 5.0e-3` bohr,
`accu_hess = 0.3`, `src/type/setvar.f90:156-158`), but they must be overridable in the settings
and calibrated by the §8 experiments #2/#3.

**D4 — the depth of this round.**
> Do only M0 + M1. M0 = skeleton + engine boundary + settings/result types + build wiring + test skeleton.
> M1 = the minimisers sd/lbfgs/bfgs/diis/rfo + Hessian update formulas + line search + a unified driver.
> M2-M7 are only written into the plan, not implemented this round.

*Consequence*: this file gives **file-level** specifications for M0/M1 (§9.1/§9.2) and only module-level ones for M2–M7.
This round does not implement `--lscan/--lts/--lirc`; only `--lopt` is registered (§12).

---

## 2. Problem statement: the task-completeness gap of ANCopt

### 2.1 Deterministic grep evidence (measured in this repository, reproducible)

Reproduction commands (run at the repository root):

```bash
for k in popt prfo nudged neb lqa gonzalez 'intrinsic reaction' 'reaction path'; do
  printf "%-20s %s\n" "$k" "$(grep -ril "$k" src/ | tr '\n' ' ')"
done
grep -rni dimer src/ | wc -l          # -> 13
grep -rln irc src/                    # -> 3 files
```

| Keyword | Hits | Conclusion |
|---|---|---|
| `popt` | (none) | 0 hits |
| `prfo` | (none) | 0 hits |
| `nudged` | (none) | 0 hits |
| `lqa` | (none) | 0 hits |
| `gonzalez` | (none) | 0 hits |
| `intrinsic reaction` | (none) | 0 hits |
| `reaction path` | (none) | 0 hits |
| `neb` | `src/define.f90:26`, `src/xhelp.f90:560` | only the letter substring of `de**fine**banner` / `definebanner` is hit, **no NEB** |
| `dimer` | `src/dipro.F90` (12 lines), `src/prog/main.F90:719` | all 12 occurrences are in `src/dipro.F90`, belonging to the **DIPRO electronic-structure method** (dimer projection, `src/dipro.F90:21,77,145-156,273,338-347`); `main.F90:719` is DIPRO's dispatch comment. **Unrelated to the Dimer TS method** |
| `irc` | `src/lidep.f90:143`, `src/readin.f90:50`, `src/optimizer.f90:618` | all 3 are English substrings: `circumvent` (×2), `mirco`. **No IRC** |

(Consistent item by item with the conclusion of R02 §5.1.)

### 2.2 ANCopt's actual capability boundary

| Capability | Location | Note |
|---|---|---|
| minimisation | `src/optimizer.f90:122 ancopt` (RF trust-region), `src/relaxation_engine.f90:400 l_ancopt`, `:131 fire`, `src/lbfgs_anc/driver.f90:39 relax_pbc` | 4 engines, all **minimisation only** |
| the `tsopt` flag | `src/setparam.f90:515`; its only effect is in `src/optimizer.f90:341-344` | raises `hlow` to 0.25 and sets `iupdat=1` (Powell update). **No eigenvector following, no RFO→RFO, no Dimer/NEB** |
| `tsroot` | `src/setparam.f90:501` | defaults to 0, read/written only in `set_module.f90`, **no computational use** |
| approximate substitutes | `src/modef.f90:34 modefollow`, `src/hessian.F90:666 distort`, `src/bias_path.f90:30 bias_path` | mode scanning, generating an initial guess by displacing along an imaginary frequency, and an RMSD push/pull metadynamics pathfinder. **None is a standard TS optimisation** |
| convergence criterion | `src/optimizer.f90:48 get_optthr` + `:972-978` | only **2 criteria**: `abs(echng)<ethr .and. gnorm<gthr`. **No four criteria of max/RMS force and displacement** |
| Hessian | `src/hessian.F90:33 numhess`, `src/type/calculator.f90:103 hessian` | numerical (two-sided difference), with an ODLR approximation available |

**Conclusion**: `ts` must be implemented from scratch (P-RFO/Dimer/NEB/string plus the mode-selection/following logic);
`irc` must be implemented from scratch (a mass-weighted integrator + a path Hessian update);
`opt/scan/hessian/freq` exist but **lack unified dispatch and a four-criteria convergence report**,
and the existing engines expose no reusable algorithm primitives (`solver_sspevx/solver_ssyevx` are
module-private in `src/optimizer.f90`, R02 §10 risk 1).

---

## 3. MAPLE comparison matrix

The rating follows the 4 levels of R03 §B/§E.1: **1:1** (mechanical rewrite) / **redesign** (semantics need restructuring) /
**impl** (auxiliary algorithms need new implementations) / **excl** (excluded).

| Task | MAPLE implementation (R01) | xtb status (R02) | This plan's target | Porting rating | Blocker |
|---|---|---|---|---|---|
| sp | `dispatcher/sp/sp.py:14` (112 lines) | ✅ `src/single.f90:37`, `TCalculator%singlepoint` | `tasks/sp.f90` wrapper + gradient output | 1:1 | none |
| opt: sd | `optimization/algorithm/SDCG.py` (557 lines, `SD=SDCG`) | ⚠️ FIRE is inertial relaxation, not pure SD | `optimize/sd.f90` | 1:1 | none |
| opt: cg(PRP+) | same as above (`SDCG.py:16-20`) | ❌ | `optimize/cg.f90` | 1:1 | none |
| opt: lbfgs | `optimization/algorithm/LBFGS.py` (219 lines, two-loop `:61-84`) | ✅ `lbfgs_step` (`src/relaxation_engine.f90:802`) | `optimize/lbfgs.f90` | 1:1 | none |
| opt: bfgs(full) | implicit in the updates of `RFO.py`/`PRFO.py` | ✅ `src/bfgs.f90:20 bfgs` (packed) | `optimize/bfgs.f90` | 1:1 | none |
| opt: diis | `optimization/algorithm/DIIS.py` (218 lines, `:20-25`) | ❌ (ANCopt has no GDIIS) | `optimize/diis.f90` | 1:1 | none |
| opt: rfo | `optimization/algorithm/RFO.py` (389 lines, mass-weighted + trust) | ⚠️ ANCopt's RF step is an **internal-coordinate approximation** (`src/optimizer.f90:895-927`) | `optimize/rfo.f90` (MWC, single shift + bisection) | 1:1 | needs a Hessian provider (D3) |
| scan: relaxed 1D | `scan/scan.py:13` (491 lines) | ✅ `src/scan_driver.f90:21 relaxed_scan` | `scan/scan1d.f90` (rewrite, with bidirectional/hysteresis report) | 1:1 | the finite barrier of `constrain_pot` (R05 §3.8.3) |
| scan: rigid | `scan.py:159` | ❌ no rigid mode (R02 §3.3) | `scan/scan1d.f90` (`mode=rigid`) | 1:1 | none |
| scan: 2D grid | `scan.py:380-405` | ❌ only sequential/concerted (R02 §3.4) | `scan/scan2d.f90` (Cartesian product) | 1:1 | none |
| ts: PRFO | `ts/algorithm/PRFO.py` (892 lines, RS dual-shift) | ❌ | `saddle/prfo.f90` | 1:1 | Hessian + a mode-selection overlap criterion |
| ts: B-PRFO(monomolecular) | `ts/algorithm/BPRFO.py:52-80` (944 lines, dead code) | ❌ | `saddle/bprfo.f90` | redesign (remove batching) | terminology ambiguity (consequence of D2) |
| ts: dimer | `ts/algorithm/dimer.py` (537 lines, runtime torch) | ❌ | `saddle/dimer.f90` (pure Fortran) | 1:1 | needs HVP; a random seed |
| ts: NEB | `ts/algorithm/neb.py` (1540 lines, improved tangent + dynamic spring) | ❌ | `path/neb.f90` | 1:1 | none (only E+G) |
| ts: CI-NEB | `neb.py:318-370, 789-855` | ❌ | `path/cineb.f90` | 1:1 | the climbing switch threshold 9.7234e-3 Eh/bohr (= 0.5 eV/Å, report 37 §3.1; measured ignition iterations 0/26/31) |
| ts: AutoNEB | `ts/algorithm/autoneb.py` (1214 lines, tree management) | ❌ | `path/autoneb.f90` | redesign | no blocking construct (R03 §E.2) |
| ts: string/GSM | `ts/algorithm/string.py` (954 lines) | ❌ | `path/string.f90` | 1:1 | none |
| hessian (numerical) | `hessian/hessian.py:11` (torch autograd, isolated) | ✅ `numhess` / `TCalculator%hessian` (step 0.005) | `types/hessian.f90` + `vib/numhess.f90` | redesign (autograd→numerical) | the `accu_hess=0.3` noise (R04 §77) |
| hessian (model initial guess) | none (MAPLE has no model Hessian) | ✅ `src/model_hessian/lindh.f90`, `swart.f90`, `eeq.f90` | `types/hessian.f90`: a `model` provider | new (xtb-only) | none |
| freq/thermo | `frequency/frequency.py` (1306 lines, RRHO + low-frequency correction) | ✅ `main_freq` (`src/main/property.F90:695`) + `thermodyn` (`src/thermo.f90:79`) | `tasks/vib.f90` wrapper (**no rewrite** of the thermochemistry) | 1:1 (reuse) | none |
| irc: GS | `irc/algorithm/gs.py` (768 lines) | ❌ | `irc/gs.f90` | 1:1 | needs a Hessian |
| irc: HPC | `irc/algorithm/hpc.py` (919 lines) | ❌ | `irc/hpc.f90` + `irc/corrector.f90` | 1:1 | needs a Hessian |
| irc: EulerPC | `irc/algorithm/eulerpc.py` (964 lines) | ❌ | `irc/eulerpc.f90` | 1:1 | needs a Hessian |
| irc: LQA | `irc/algorithm/lqa.py` (722 lines) | ❌ | `irc/lqa.f90` | 1:1 | lineage ambiguity (R04 Contradictions #3) |
| DMF | `ts/algorithm/dmf.py` (2767 lines, `import cyipopt`) | — | **excluded** | excl | an external NLP solver |
| blbfgs / BPRFO batch | `optimization/algorithm/blbfgs.py` (535 lines), `BPRFO.py` | — | **excluded** | excl | torch batched semantics |
| parmfit | `dispatcher/parmfit/` (~40 files) | — | **excluded** | excl | a parameter-development tool chain |
| MD ensembles | `dispatcher/md/` (~6000 lines) | ✅ `src/mdoptim.f90`, the md dispatch at `prog/main.F90:1153` | **excluded** | excl | xtb already has `md`/`omd` |

---

## 4. Overall architecture

### 4.1 Module tree (the complete list, every file listed)

Against R05 §3.1; `★` in the table marks a **new file** relative to R05 §3.1 and its reason.

```
src/landscape/
  CMakeLists.txt              # single build file (lists all paths centrally, no nested subdir)
  meson.build                 # isomorphic
  landscape_api.f90           # the only external entry point
  landscape_driver.f90        # task dispatch
  types/
    settings.f90  results.f90  engine.f90  hessian.f90  updater.f90  conv.f90  log.f90
  coords/
    cartesian.f90  internal.f90  transform.f90
  tasks/
    sp.f90  opt.f90  scan.f90  ts.f90  irc.f90  vib.f90
  optimize/
    sd.f90  cg.f90  lbfgs.f90  bfgs.f90  diis.f90  rfo.f90  linesearch.f90  trust.f90
  saddle/
    prfo.f90  bprfo.f90  dimer.f90  eigenfollow.f90
  path/
    idpp.f90  neb.f90  cineb.f90  autoneb.f90  string.f90  gsm.f90
  irc/
    gs.f90  hpc.f90  lqa.f90  eulerpc.f90  corrector.f90
  scan/
    scan1d.f90  scan2d.f90  relax_scan.f90
  vib/
    numhess.f90  modes.f90  thermo.f90
```

> **The actual file tree that has landed in M0/M1** (it differs from the module names above; take this section as authoritative; details in §9.1/§9.2/§12.8):
>
> ```
> src/landscape/
>   CMakeLists.txt  meson.build
>   landscape_api.f90        # xtb_landscape
>   landscape_driver.f90     # xtb_landscape_driver
>   engine/engine.f90        # xtb_landscape_engine
>   types/{settings,results,coords,log,hessian}.f90
>                             # xtb_landscape_{settings,results,coords,log,hessian}
>   tasks/{sp,opt}.f90        # xtb_landscape_sp / xtb_landscape_tasks_opt
>   optimize/{hessian_update,line_search,sd,cg,lbfgs,bfgs,diis,rfo,driver}.f90
>                             # xtb_landscape_{hessian_update,line_search,sd,cg,
>                             #   lbfgs,bfgs,diis,rfo,optimize}
> ```
>
> Differences (§12.8 D1): no `types/conv.f90` (the criteria/convergence report merged into `settings.f90`/`results.f90`),
> no `types/updater.f90` (= `optimize/hessian_update.f90`), no `coords/*`
> (= `types/coords.f90`), no `optimize/trust.f90` (merged into `rfo.f90`).

| Directory / file | module name | Responsibility | Dependencies (downward only) |
|---|---|---|---|
| `landscape_api.f90` | `xtb_landscape` | exposes `run_landscape(env,mol,chk,calc,settings,result)`: the only symbol called by `src/prog/main.F90` | `landscape_driver`, `types/settings`, `types/results` |
| `landscape_driver.f90` | `xtb_landscape_driver` | dispatches by the `task` string to `tasks/*`; assembles provider/updater; timing and summary report | all `tasks/*`, `types/*` |
| `types/settings.f90` | `xtb_landscape_settings` | all settings derived types + unit-conversion helpers + `set_conv_level` | `xtb_mctc_accuracy`, `xtb_mctc_convert` |
| `types/results.f90` | `xtb_landscape_results` | the result / path_result / irc_result / convergence_report types and printing | `xtb_mctc_accuracy`, `xtb_mctc_io` |
| `types/engine.f90` | `xtb_landscape_engine` | the engine boundary: holds `env/mol/wfn/calc`, cache, `energy_gradient` / `hessian` / `hvp`, the abstract `hessian_provider` interface + the **numerical implementation** | `xtb_type_*`, `xtb_single`, `xtb_type_data` |
| `types/hessian.f90` | `xtb_landscape_hessian` | concrete providers: `model` (Lindh/Swart/EEQ), `file` (`rdhess`); **the analytic extension point is the abstract `compute`** | `xtb_landscape_engine`, `xtb_modelhessian_*`, `xtb_freq_io` |
| `types/updater.f90` | `xtb_landscape_updater` | Hessian updates: Bofill / BFGS / Powell / SR1, forced symmetrisation + Powell damping | `xtb_mctc_blas`, `xtb_bfgs` |
| `types/conv.f90` ★ | `xtb_landscape_conv` | the four-criteria convergence test + the level table; the MAPLE-style `is_converged` semantics | `xtb_mctc_accuracy` |
| `types/log.f90` | `xtb_landscape_log` | trajectory/log writing; uniformly calls `xtb_io_writer::writeMolecule` | `xtb_io_writer`, `xtb_mctc_filetypes` |
| `coords/cartesian.f90` | `xtb_landscape_cartesian` | flatten/unflatten convention, mass-weighted metric, rigid-component removal, Kabsch/RMSD | `xtb_mctc_la`, `xtb_lsrmsd`, `xtb_detrotra` |
| `coords/internal.f90` | `xtb_landscape_internal` | redundant internal-coordinate wrapper (bond/angle/dihedral/linbend) | `xtb_internals_*`, `xtb_bmatrix` |
| `coords/transform.f90` | `xtb_landscape_transform` | `x↔q`, the B matrix, `H_cart = Bᵀ H_int B` (corresponding to `src/optimizer.f90:1325 itochess`) | `coords/internal`, `xtb_mctc_blas` |
| `tasks/sp.f90` | `xtb_landscape_sp` | single point: E + optional gradient + report | `types/engine`, `types/results` |
| `tasks/opt.f90` | `xtb_landscape_tasks_opt` | the minimisation task layer (assemble engine/provider, write to disk, report) | `optimize/*`, `types/*` |
| `tasks/scan.f90` | `xtb_landscape_scan` | the scan driver (with bidirectional/hysteresis, hot start, constraint-residual report) | `scan/*`, `tasks/opt`, `xtb_constrainpot` |
| `tasks/ts.f90` | `xtb_landscape_ts` | the TS driver (prfo/bprfo/dimer/neb/cineb/autoneb/string) | `saddle/*`, `path/*` |
| `tasks/irc.f90` | `xtb_landscape_irc` | the IRC driver (gs/hpc/lqa/eulerpc, bidirectional, three termination signals) | `irc/*` |
| `tasks/vib.f90` | `xtb_landscape_vib` | Hessian output + calling the existing `main_freq`(`xtb_propertyoutput`, `src/main/property.F90:22`) / `thermodyn`(`xtb_thermo`, `src/thermo.f90:18`) printing | `vib/*`, `xtb_hessian`, `xtb_propertyoutput`, `xtb_thermo` |
| `optimize/sd.f90` | `xtb_landscape_opt_sd` | steepest descent (with the pre-switch phase) | `types/*` |
| `optimize/cg.f90` | `xtb_landscape_cg` | PRP+ conjugate gradient (negative beta truncated to zero = restart, non-descent-direction guard) | `types/*` |
| `optimize/lbfgs.f90` | `xtb_landscape_lbfgs` | L-BFGS two-loop history | `types/*` |
| `optimize/bfgs.f90` | `xtb_landscape_opt_bfgs` | full BFGS (defaults to `xtb_bfgs::bfgs`, packed) | `xtb_bfgs` |
| `optimize/diis.f90` | `xtb_landscape_opt_diis` | GDIIS extrapolation + Tikhonov regularisation | `xtb_mctc_lapack` |
| `optimize/rfo.f90` | `xtb_landscape_opt_rfo` | mass-weighted single-shift RFO + trust region | `types/engine`, `optimize/trust`, `xtb_freq_project` |
| `optimize/linesearch.f90` | `xtb_landscape_opt_linesearch` | Armijo backtracking line search + `max_step` clip | `types/engine` |
| `optimize/trust.f90` | `xtb_landscape_opt_trust` | a general trust-region state machine (`rho`, `eta_shrink/expand`, min/max) | `types/*` |
| `saddle/prfo.f90` | `xtb_landscape_saddle_prfo` | RS dual-shift P-RFO + mode following | `optimize/trust`, `types/*` |
| `saddle/bprfo.f90` | `xtb_landscape_saddle_bprfo` | monomolecular RS-P-RFO (alpha adjustable) | as above |
| `saddle/dimer.f90` | `xtb_landscape_saddle_dimer` | Dimer rotation + translation (Eq.13/18/21) | `types/engine`(HVP), `coords/cartesian` |
| `saddle/eigenfollow.f90` | `xtb_landscape_saddle_eigenfollow` | mode selection: overlap criterion + sign realignment + projection | `xtb_freq_project`, `xtb_freq_utils` |
| `path/idpp.f90` | `xtb_landscape_path_idpp` | IDPP initial path (no energy evaluations) | `xtb_mctc_blas` |
| `path/neb.f90` | `xtb_landscape_path_neb` | improved tangent (Eqs.8–12) + dynamic spring + projected L-BFGS (tangent/spring are **private** procedures in the module, not split into extra files) | `types/*` |
| `path/cineb.f90` | `xtb_landscape_path_cineb` | climbing-image force + switch | `path/neb` |
| `path/autoneb.f90` | `xtb_landscape_path_autoneb` | adaptive point insertion/splitting (the `PathNode` tree) | `path/neb` |
| `path/string.f90` | `xtb_landscape_path_string` | GSM growth + reparametrisation | `path/neb`(shared tools), `xtb_cqpath` |
| `path/gsm.f90` | `xtb_landscape_path_gsm` | GSM top level (`string`'s convergence/CI wrapper) | `path/string` |
| `irc/gs.f90` | `xtb_landscape_irc_gs` | Gonzalez–Schlegel pivot + spherical constraint | `irc/corrector`, `types/*` |
| `irc/hpc.f90` | `xtb_landscape_irc_hpc` | LQA prediction + DWI/mBS correction | `irc/corrector` |
| `irc/lqa.f90` | `xtb_landscape_irc_lqa` | single-step LQA propagation | `irc/corrector` |
| `irc/eulerpc.f90` | `xtb_landscape_irc_eulerpc` | Euler prediction + DWI/mBS correction | `irc/corrector` |
| `irc/corrector.f90` | `xtb_landscape_irc_corrector` | DWI surface fit + modified Bulirsch–Stoer + LQA analytic propagation (shared by the four methods) | `types/engine`(Hessian) |
| `scan/scan1d.f90` | `xtb_landscape_scan1d` | 1D scan (relaxed/rigid, bidirectional) | `tasks/opt`, `xtb_constrainpot` |
| `scan/scan2d.f90` | `xtb_landscape_scan2d` | 2D Cartesian-product grid + hot start | `scan/scan1d` |
| `scan/relax_scan.f90` | `xtb_landscape_scan_relax` | the constraint-relaxation kernel (set `valconstr` → inner opt → de-biased energy) | `tasks/opt`, `xtb_geoopt`(optional) |
| `vib/numhess.f90` | `xtb_landscape_vib_numhess` | obtain a dense Hessian through the provider; optional ODLR | `types/engine`, `xtb_o1numhess` |
| `vib/modes.f90` | `xtb_landscape_vib_modes` | projection + mass weighting + diagonalisation + frequencies (**reuses** `xtb_freq_project/utils`) | `xtb_freq_project`, `xtb_freq_utils` |
| `vib/thermo.f90` | `xtb_landscape_vib_thermo` | a thin wrapper over the existing RRHO printing (**no rewrite**) | `xtb_thermo`, `xtb_hessian` |

**Note (avoid pointless nesting)**: directories such as `types/`, `coords/` do **not** carry a `CMakeLists.txt`/`meson.build`.
`src/landscape/CMakeLists.txt` lists all 47 `.f90` files with explicit relative paths (following the existing style of
`src/CMakeLists.txt:113-119` listing `model_hessian/*`), `meson.build` is isomorphic,
and finally `set(srcs ${srcs} PARENT_SCOPE)` (compare `src/freq/CMakeLists.txt:18-26`).
Reason: fewer files, avoiding CMake variable-scope errors, and fully consistent with one of the repository's two existing styles
(`src/CMakeLists.txt:113-119` lists `model_hessian/*` directly and creates no sub-file for that directory).

### 4.2 Dependency direction (strictly one-way, no cycles)

```
        src/prog/main.F90   (runtyp dispatch)
                 │ the only entry point
                 ▼
        xtb_landscape_api ──► xtb_landscape_driver
                                     │
        ┌────────────┬───────────────┼──────────────┬────────────┐
        ▼            ▼               ▼              ▼            ▼
     tasks/sp   tasks/opt      tasks/(scan,ts,   tasks/vib   types/results
     tasks/opt   optimize/*     irc) ─► saddle/*,  vib/*      types/settings
                       │              path/*, irc/*    │
                       └──────────────┴────────────────┴────► types/engine
                                                                   │
                                              ┌────────────────────┼──────────────┐
                                              ▼                    ▼              ▼
                                       types/hessian        coords/*        types/updater
                                              │                    │
                                              ▼                    ▼
                                 xtb_modelhessian_*      xtb_internals_*, xtb_bmatrix
                                              │
                                              ▼
        xtb private layer: xtb_single, xtb_type_calculator/molecule/restart/environment,
                    xtb_geoopt, xtb_optimizer, xtb_bfgs, xtb_freq_*, xtb_constrainpot,
                    xtb_hessian, xtb_o1numhess, xtb_mctc_{accuracy,convert,blas,lapack,la,filetypes}
```

**Rules (the boundary M0 must state in the header of `landscape_api.f90`)**

1. `optimize/**`, `saddle/**`, `path/**`, `irc/**`, `scan/**`, `vib/**` may **only**
   `use xtb_landscape_*` and `xtb_mctc_*`; they must not `use xtb_type_molecule` / `xtb_single` /
   `xtb_optimizer` / `xtb_geoopt` / `xtb_setparam` (`types/engine.f90` is the only entry to xtb private types,
   `types/hessian.f90` the only entry to `model_hessian`/`freq_io`, `coords/*` the only entry to
   `internals`/`bmatrix`/`detrotra`, and `vib/*` the only entry to `xtb_freq_*`/`xtb_hessian`).
2. **module-level mutable variables are forbidden** (R01 §9.7: MAPLE's dual default values are exactly the pitfall that Fortran settings types avoid).
   `settings` is always passed explicitly as a parameter object (`type(...), intent(in)`).
3. existing xtb modules **must not** `use xtb_landscape_*`; the only exception is the minimal changes to the 5 existing files listed in §12.

### 4.3 Boundary with xtb private modules (the reusable list)

| Capability the new module needs | xtb source (module / procedure) | Boundary module |
|---|---|---|
| energy + analytic gradient | `xtb_single::singlepoint` (`src/single.f90:37`), arguments `(env,mol,chk,calc,egap,et,maxiter,prlevel,restart,lgrad,acc,etot,g,sigma,res)` | `types/engine.f90` |
| numerical Hessian | `TCalculator%hessian` (`src/type/calculator.f90:103`) | `types/engine.f90` |
| model Hessian | `newLindhModelHessian`/`newLindhD2ModelHessian` (`src/model_hessian/lindh.f90:41`), `newSwartModelHessian` (`swart.f90:34`), `add_eeq_hessian` (`eeq.f90`) | `types/hessian.f90` |
| Hessian packing/dense contraction | `TModelHessian%compute_packed` (`src/model_hessian/type.f90:37`), the `generic compute` (`:41`) / `compute_dense` | `types/hessian.f90` |
| Hessian projection | `projectHessian` (`src/freq/project.f90:34`), `trproj` (`:151`), `gtrprojm` (`:218`) | `saddle/eigenfollow.f90`, `vib/modes.f90` |
| mass weighting/diagonalisation | `massWeightHessian` (`src/freq/utils.f90:32`), `diagHessian` (`:59`) | `vib/modes.f90` |
| imaginary mode (cold start) | `find_projected_imag_modes` (`src/o1numhess.f90:694`) | `saddle/eigenfollow.f90` |
| Hessian IO | `wrhess`/`rdhess`/`writeHessianOut` (`src/freq/io.f90:30,51,82`) | `types/hessian.f90` |
| Hessian update | `bfgs` (`src/bfgs.f90:20`), `powell` (`:105`), `hdamp` (`:164`) | `types/updater.f90` |
| lowest eigenpair | `sdavid2`/`solver_sdavidson` (`src/david2.f90:25/221`, **single precision**) | `optimize/rfo.f90` (optional) |
| internal coordinates | `redundant_type` (`src/internals/redundant.f90:41`), `new_redundant` (`:73`), `graph_type` (`graph.f90:33`), `get_bmatrix` (`src/bmatrix.f90:321`), `bmat_accum_*` (`:456,:508`) | `coords/internal.f90`, `coords/transform.f90` |
| remove translation/rotation | `detrotra` (`src/detrotra.f90:18`), `axis3` (`src/axis_trafo.f90:377`), `rmrottr` (`src/rmrottr.f90:19`) | `coords/cartesian.f90` |
| RMSD | `xtb_lsrmsd::rmsd` (`src/ls_rmsd.f90:33`) | `coords/cartesian.f90` |
| constraint potential/scan | `constrain_pot` (`src/constrain_pot.f90:313`), `constrain_hess` (`:331`), `qpothess2` (`:88`), `relaxed_scan` (`src/scan_driver.f90:21`) | `scan/*` |
| constraint parameter object | `xtb_type_setvar::constr_setvar` (`src/type/setvar.f90:135`), `xtb_scanparam::constrain_all_bonds` (`src/scanparam.f90:322`, taking only `bond_factor = 1.2` as the connectivity threshold) | `scan/*` |
| angle/dihedral convention | `xtb_basic_geo::bangl` (`src/basic_geo.f90:502`) / `valijkl` (`:245`) | `scan/*` |
| path interpolation | `cqpath_*` (`src/cqpath.f90:32,128,270`) | `path/string.f90` |
| unified relaxation entry | `geometry_optimization` (`src/geoopt_driver.f90:23`) | `scan/relax_scan.f90` (optional) |
| trajectory writing | `writeMolecule` (`src/io/writer.f90:36`) | `types/log.f90` |
| units/constants | `xtb_mctc_convert` (`src/mctc/convert.f90:25-66`) | `types/settings.f90` |
| BLAS/LAPACK | `xtb_mctc_blas`, `xtb_mctc_lapack`, `xtb_mctc_la` | all layers |
| error handling | `env%error` (`src/type/environment.f90:298`), `env%check` (`:162`), `env%warning` (`:324`) | all layers |

---

## 5. Interface contract

> This section is the core of the plan. M0's acceptance criterion is that everything in this section compiles and passes the unit tests.

### 5.1 Abstract engine boundary

**Design goal**: the algorithm layer sees only three actions, "E+G", "Hessian" and "HVP"; the engine holds `env/mol/wfn/calc` and manages them fully;
the **same geometry is never SCF'd twice**; given the same input it is **bitwise reproducible**.

```fortran
! types/engine.f90
module xtb_landscape_engine
   use xtb_mctc_accuracy, only : wp
   use xtb_type_environment, only : TEnvironment
   use xtb_type_molecule, only : TMolecule
   use xtb_type_restart, only : TRestart
   use xtb_type_calculator, only : TCalculator
   use xtb_type_data, only : scc_results
   implicit none(type, external)

   !> Restart/state policy
   integer, parameter :: p_restart_off = 0, p_restart_pin = 1, p_restart_warm = 2

   !> Immutable run-time control for one engine instance
   type :: landscape_engine_control
      real(wp) :: etemp = 300.0_wp     ! K,      SCC Fermi broadening (src/setparam.f90:233)
      integer  :: maxiter = 250        ! 1,      max SCC iterations   (src/setparam.f90:221)
      real(wp) :: acc = 1.0_wp         ! 1,      SCC convergence      (src/setparam.f90:222)
      integer  :: printlevel = 1
      logical  :: lgrad = .true.
      integer  :: restart_mode = p_restart_off
      real(wp) :: hess_step = 5.0e-3_wp ! bohr,  numerical Hessian step (src/type/setvar.f90:158)
      real(wp) :: hess_acc = 0.3_wp     ! 1,     SCC acc during Hessian (src/type/setvar.f90:156)
      real(wp) :: hvp_step = 5.0e-3_wp  ! bohr,  HVP central difference step
   end type landscape_engine_control
```

> **Measured conclusion (R2-02, 2026-10)**: although the signature of `xtb_single::singlepoint` (`src/single.f90:37`) contains
> `etemp/maxiter/acc`, its **body does not forward them**; it forwards to `calc%singlepoint(env, mol, chk,
> prlevel, restart, ...)`. The **real effective paths** of those three engine-control items are therefore:
>
> - `acc`: the engine must write it into `calc%accuracy` in `engine_set_calculator`, and `xtbMain` must synchronise the CLI-parsed `set%acc` into `lset%engine%acc` (otherwise the engine pushes it back to the default 1.0);
> - `etemp`: measured, `--lopt --etemp 5000` changes the converged energy (`-5.070544450318` vs `-5.070544447778`),
>   and the effective path is `calc%etemp = set%etemp` at the construction of `newXTBCalculator` (outside this example) — **no further code change**;
> - `maxiter`: there is no CLI flag; the maximum SCC iteration count reaches `calc%maxiter` at construction through the xcontrol `$scc maxiterations=`
>   (`src/set_module.f90:1758` → `set%maxscciter`) — **no further code change**.
>
> The fix round wired up only `acc` (`lset%engine%acc = set%acc` in `src/prog/main.F90` + `engine_set_calculator`
> writing `calc%accuracy`), with a CLI-level regression `xtb/landscape-opt-acc`.

**`landscape_engine_type` (fields)**

| Field | Type | Physical meaning / unit |
|---|---|---|
| `env` | `TEnvironment` | error/I/O environment; `env%unit` is the output stream |
| `mol` | `TMolecule` | the current geometry; `mol%xyz(3,n)` in **bohr** (the xtb internal unit, `src/type/molecule.f90:53-169`) |
| `wfn` | `TRestart` | wavefunction/restart state; the `copy` method is available (`src/type/restart.F90:48,53`) |
| `wfn_ref` | `TRestart` | the deterministic reference state (snapshotted at construction or at `engine_pin_state`) |
| `calc` | `class(TCalculator), allocatable` | polymorphic calculator (GFN0/1/2/FF/tblite/extern) |
| `ctrl` | `landscape_engine_control` | see above |
| `hp` | `class(landscape_hessian_provider), allocatable` | Hessian provider (§5.2) |
| `cache_xyz` | `real(wp), allocatable :: (:,:)` | the geometry of the last evaluation (bohr) |
| `cache_energy`, `cache_gradient`, `cache_sigma`, `cache_hlgap`, `cache_results` | | cached outputs |
| `cache_valid` | `logical` | cache validity |
| `n_eval`, `n_hess`, `n_hvp` | `integer` | counters (used for the cost report and the determinism tests) |
| `n_scf_fail` | `integer` | number of times `results%converged == .false.` |

**Public procedures (all implemented in M0)**

| Procedure | Signature points | Semantics |
|---|---|---|
| `new_engine(self, env, mol, wfn, calc, ctrl, hp)` | `hp` is `class(landscape_hessian_provider), intent(in), optional` | deep-copy `env/mol/wfn/calc`; snapshot `wfn_ref`; `allocate(self%hp, source=hp)` taking the dynamic type; give `mol` an **own copy** (avoid aliasing) |
| `engine_destroy(self)` | — | release all allocatable components (including `calc`/`hp`/the caches) |
| `engine_set_xyz(self, xyz)` | `real(wp), intent(in) :: xyz(3,*)` bohr | write `mol%xyz` and **unconditionally invalidate the cache** |
| `engine_get_xyz(self, xyz)` | `intent(out)` | read the current geometry (bohr) |
| `engine_invalidate(self)` | — | invalidate the cache manually |
| `engine_pin_state(self)` | — | `call self%wfn_ref%copy(self%wfn)`: pin the current wavefunction as the reference state (used by `p_restart_pin`) |
| `engine_energy_gradient(self, energy, gradient, sigma, hlgap, results)` | `energy` hartree; `gradient(3,n)` hartree/bohr; `sigma(3,3)` hartree | see the cache algorithm below; an unconverged SCC → `env%warning` + `n_scf_fail++` + `fail=.true.`, and **do not cache, do not return that E/g as a usable value** (R2-03; the task layer `tasks/opt.f90` raises it further to `env%error`) |
| `engine_hessian(self, hess, step, odlr, final_err)` | `hess(3n,3n)` hartree/bohr² (**dense, symmetrised**) | delegates to `self%hp%compute(self, hess, step, odlr, final_err)`; `n_hess++` |
| `engine_hvp(self, vec, hv, delta)` | `vec(3n)` a dimensionless direction; `hv(3n)` hartree/bohr² | `hv = (g(x+δv) − g(x−δv)) / (2δ)`, δ defaults to `ctrl%hvp_step`; restores the original geometry; `n_hvp++` |
| `engine_report(self, unit)` | — | prints `n_eval/n_hess/n_hvp/n_scf_fail` (cost evidence) |

**The caching and repeatability algorithm (M0 must implement each item and cover it by tests)**

```text
engine_energy_gradient:
    if (cache_valid .and. all(self%mol%xyz == self%cache_xyz)) then
        energy=...; gradient=...; sigma=...; hlgap=...; results=...    ! cache hit, n_eval unchanged
        return
    end if
    if (ctrl%restart_mode == p_restart_off .or. ctrl%restart_mode == p_restart_pin) &
        call self%wfn%copy(self%wfn_ref)             ! deterministic reset
    call singlepoint(self%env, self%mol, self%wfn, self%calc, hlgap, ctrl%etemp, &
                     ctrl%maxiter, ctrl%printlevel, restart=.true., &
                     lgrad=ctrl%lgrad, acc=ctrl%acc, etot=energy, g=gradient, &
                     sigma=sigma, res=results)
    n_eval = n_eval + 1
    cache_xyz = self%mol%xyz ; ... ; cache_valid = .true.
```

Key points (written into the module header comment + asserted by unit tests):

1. **The equality test is bitwise** (`all(a == b)`), not a tolerance comparison. The reason is the semantics of "do not repeat the SCF for the same geometry";
   if an algorithm really changes the coordinates and changes them back, the bit pattern is usually different → it recomputes (the safe side).
2. `engine_set_xyz` invalidates the cache **unconditionally**: an algorithm can use it to force recomputation (e.g. after a NEB update).
3. `p_restart_off` (default): reset the wavefunction from `wfn_ref` before every E+G → directly countering upstream issue #1378
   "restart is used implicitly, so two gradients of the same geometry differ" (R04 §79).
   `p_restart_pin`: reset to some explicitly pinned converged state (for scan consistency).
   `p_restart_warm`: keep the previous state (for consecutive points of opt/NEB/scan, aiming for speed).
   The three modes must be **printed explicitly** in the output (a reproduction requirement).
4. `engine_hvp` must restore `mol%xyz` before returning (otherwise the caller's geometry is contaminated);
   after restoring it **invalidates the cache again** (because the cache holds the original geometry, and although the bit pattern is actually the same after the restore,
   the implementation chooses "conservative invalidation", to avoid relying on the bit-equivalence of a floating-point restore).
5. `engine_energy_gradient` must not modify `ctrl` (`intent(in)`).

### 5.2 Hessian provider abstraction (D3)

```fortran
! types/engine.f90 -- the abstract interface (in the same module as engine, to break a circular dependency)
   type, abstract :: landscape_hessian_provider
      character(len=:), allocatable :: name          ! 'numerical' | 'model' | 'file'
      logical :: exact = .false.                     ! whether an analytic/exact Hessian
   contains
      procedure(hessian_compute), deferred :: compute
   end type landscape_hessian_provider

   abstract interface
      subroutine hessian_compute(self, engine, hess, step, odlr, final_err)
         import :: landscape_hessian_provider, landscape_engine_type, wp
         class(landscape_hessian_provider), intent(inout) :: self
         class(landscape_engine_type),      intent(inout) :: engine
         real(wp), intent(inout) :: hess(:, :)     ! (3n,3n) hartree/bohr^2, dense symmetric
         real(wp), intent(in), optional  :: step   ! bohr, the numerical difference step
         logical,  intent(in), optional  :: odlr
         real(wp), intent(out), optional :: final_err
      end subroutine hessian_compute
   end interface
```

| Concrete provider | File | Milestone | `exact` | Implementation |
|---|---|---|---|---|
| `landscape_numerical_hessian_provider` | `types/hessian.f90` | **M0/M1** | `.false.` | an **own** central difference: displace `mol%xyz` by `±step` for each Cartesian component, each displacement cold-starting from the same wavefunction (a `chk` snapshot at entry) and calling `TCalculator%singlepoint` (`prlevel=-1`); before the call `calc%accuracy` is set to `sccacc` and restored afterwards (compare `src/hessian.F90:174` set, `:259` restore); symmetrise `hess = 0.5*(hess+transpose(hess))` before returning. It does **not** forward to `TCalculator%hessian` (reason in `07-*.md` §4.3 and §12.8 D2); `odlr=.true.` errors |
| `landscape_model_hessian_provider` | `types/hessian.f90` | **M1 (implemented)** | `.false.` | reuses `newLindhD2ModelHessian` (`src/model_hessian/lindh.f90:41`, default `set%mhset%model=p_modh_old`) and the default force constants of `set%mhset` (`src/setparam.f90:267-278`), obtaining a dense symmetric Hessian via `TModelHessian%compute` (`src/model_hessian/type.f90:41`); purely geometric, `n_eval=0`. Injected as the **initial guess** of RFO/BFGS (the BFGS branch of `driver.f90` via `bfgs%set_hessian`; RFO already goes through `objective%hessian`). **Completed in M1 (filled in by R2/D3)** |
| `landscape_hessian_file` | `types/hessian.f90` | M3 | `.true.` | `rdhess` (`src/freq/io.f90:82`) reads an external Hessian (for `--hess` reuse and a numerical baseline comparison) |
| analytic hook (**reserved**) | `types/hessian.f90` | ≥M3 | `.true.` | **the abstract interface above itself**. A future `landscape_hessian_analytic` would be `type, extends(landscape_hessian_provider) :: ...`, implementing `compute` to return GFN2 analytic second derivatives directly and setting `exact=.true.`. The entry point for choosing a provider is the settings `hessian_source` string (§5.3 `THessianSettings`), with the driver constructing it via `select case` — **no algorithm-layer code needs changing**. |

M0/M1 do **not** add empty stub types (to avoid dead code / placeholder implementations); the "reservation" is realised by the abstract interface itself.

`hessian_source` values: `'numerical'` (default), `'model'` (from M1), `'file'` (from M3);
an unrecognised value → `call env%error("unknown hessian source: "//src, source)` + return (no `stop`).

### 5.3 Per-task settings derived types (fields / units / defaults)

Unit convention: **length bohr, energy hartree, force hartree/bohr, Hessian hartree/bohr²,
mass amu, frequency cm⁻¹, temperature K, pressure kPa, IRC step length bohr·amu^1/2**.
a.u. throughout internally; conversion with `xtb_mctc_convert` (`aatoau/autoaa/autokcal/autokj/autorcm`,
`src/mctc/convert.f90:25-42`) only at the I/O boundary.

#### 5.3.1 `TConvSettings` (the common convergence criteria, four criteria)

The four criteria are defined in strict alignment with MAPLE (`optimization/algorithm/_common.py:74-89`, R01 §3.1):
`max_f = max|g_i|` (i over the 3N components), `rms_f = sqrt(Σg_i²/(3N))`,
`max_dp = max|Δx_i|`, `rms_dp = sqrt(ΣΔx_i²/(3N))`.
**Note that the `rms` denominator is 3N (per component), not N (per atom)** — changing it changes the convergence step count (R03 §C.7).

| Field | Unit | Default | Meaning |
|---|---|---|---|
| `level` | — | `'normal'` | the level name (mapped in the table below) |
| `f_max` | hartree/bohr | 3.0e-4 | maximum force component |
| `f_rms` | hartree/bohr | 1.0e-4 | RMS force |
| `dp_max` | bohr | 4.0e-3 | maximum displacement component |
| `dp_rms` | bohr | 2.0e-3 | RMS displacement |
| `e_chg` | hartree | 5.0e-6 | energy change (**AND**ed with the four criteria, against the `ethr` of xtb `normal`, `src/optimizer.f90:48-119`) |
| `max_iter` | — | 256 | maximum iterations (against MAPLE's `max_iter=256`) |

The level table (`set_conv_level(self, name)`):

| level | f_max | f_rms | dp_max | dp_rms | Source |
|---|---|---|---|---|---|
| `superloose` | 4.6e-3 | 3.0e-3 | 7.9e-3 | 5.2e-3 | MAPLE superloose converted (8.5e-2/5.5e-2 Ha/Å; 1.45e-1/9.5e-2 Å) |
| `loose` | 2.0e-3 | 5.0e-4 | 1.0e-2 | 7.0e-3 | ORCA 6.1 Table 4.1 Loose (R04 §64) |
| **`normal` (default)** | 3.0e-4 | 1.0e-4 | 4.0e-3 | 2.0e-3 | ORCA 6.1 Table 4.1 Normal |
| `tight` | 1.0e-4 | 3.0e-5 | 1.0e-3 | 6.0e-4 | ORCA 6.1 Table 4.1 Tight |
| `vtight` | 3.0e-5 | 8.0e-6 | 2.0e-4 | 1.0e-4 | ORCA 6.1 Table 4.1 VeryTight |

**Differences from MAPLE and the reasons**

| Item | MAPLE | This plan | Reason |
|---|---|---|---|
| level naming | extratight/tight/medium/loose/extraloose/superloose (`dispatcher.py:154-195`) | ORCA's five levels | MAPLE's medium≈ORCA loose and tight≈ORCA normal are close, and a one-to-one mapping would mislead; using the ORCA names + values directly is more auditable |
| units | Å, Ha/Å | bohr, Ha/bohr | D1: a.u. internally; force the conversion in the settings layer, forbid Å in the algorithm layer |
| `default` level | `medium` (fallback) | `normal` | `normal`'s f_rms=1.0e-4 Ha/bohr = 5.3e-5 Ha/Å, 36 times tighter than MAPLE medium (1.9e-3 Ha/Å). Reason: GFN2 gradient noise has not yet been quantified (R04 §9#4), so a tighter value is taken initially and backfilled after the §8 experiment #4 |
| energy criterion | none | `e_chg=5e-6` | xtb has `ethr` (`src/optimizer.f90:48-119`); as an **AND**ed additional criterion it prevents jitter on a noise plateau from being judged converged |

> `[to be calibrated]`: `normal`'s four thresholds must be reviewed by the §8 experiments #2/#4 before M4 (TS) and M6 (IRC);
> if the xtb gradient noise σ_g > f_rms/10, then `normal` is unreachable for TS/IRC, in which case the TS/IRC default drops to `loose` (otherwise the iteration count explodes).

#### 5.3.2 `TDriverSettings`

| Field | Unit | Default | Meaning |
|---|---|---|---|
| `task` | — | `'opt'` | `sp\|opt\|scan\|ts\|irc\|hessian\|freq` |
| `verbose` | — | 1 | 0=silent, 1=one line per step, ≥2=full per step |
| `engine` | `landscape_engine_control` | §5.1 | engine control |
| `conv` | `TConvSettings` | §5.3.1 | convergence criteria |
| `hessian_source` | — | `'numerical'` | `numerical\|model\|file` (§5.2) |
| `out_xyz` | — | `''` (auto-named) | final-geometry output path |
| `out_traj` | — | `''` (auto-named) | trajectory output path |
| `write_traj` | — | `.true.` | whether to write the trajectory |
| `traj_every` | — | 1 | write one frame every N steps |
| `prefix` | — | `'xtb'` | output file-name prefix |

#### 5.3.3 `TSpSettings`

| Field | Unit | Default | Meaning / comparison |
|---|---|---|---|
| `write_gradient` | — | `.false.` | print the gradient (the behaviour of MAPLE `SPParams.verbose=1`, `sp/sp.py:9`) |
| `grad_threshold` | hartree/bohr | 0.0 | print only components with ‖g‖ > the threshold; 0.0 = print everything |
| `write_hessian` | — | `.false.` | include the Hessian (through the provider) |

#### 5.3.4 `TOptSettings` (the M1 main body)

| Field | Unit | Default | Physical meaning | Comparison / reason |
|---|---|---|---|---|
| `method` | — | `'lbfgs'` | `sd\|cg\|lbfgs\|bfgs\|diis\|rfo` | MAPLE `optimization.py:17-33` has only `lbfgs/rfo/sd/sdcg`; this plan makes cg/bfgs/diis explicit (MAPLE hides CG/DIIS inside SDCG, `SDCG.py:34-57`) |
| `memory` | — | 5 | L-BFGS history length | MAPLE `LBFGSParams.memory=5` |
| `curvature` | — | 70.0 | the curvature lower bound for falling back to H0 | the same value as MAPLE |
| `max_step` | bohr | 3.7795e-1 | maximum single-step displacement | MAPLE `max_step=0.2 Å` |
| `sd_enabled` | — | `.true.` | do an SD phase first | MAPLE `SDCGParams` |
| `sd_max_iter` | — | 50 | the latest step for the SD→CG switch | the same value as MAPLE |
| `cg_switch_fmax` | hartree/bohr | 0.0 | 0 = auto (0.5× the initial max_f) | the MAPLE semantics (`SDCG.py:459-468`) |
| `cg_beta_method` | — | `'prp+'` | PRP+ with negative values truncated to zero | MAPLE `cg_beta_method="prp+"`. **This round does not provide this setting**: PRP+ is the only beta this suite supports, and truncating negative values to zero is the restart mechanism (§12.8 D5) |
| `cg_restart_threshold` | — | 0.2 | the CG restart criterion | the same value as MAPLE. **This round does not implement this setting**: under an Armijo-only line search the Powell alignment criterion degrades CG into SD (measured, §12.8 D5) |
| `diis_enabled` | — | `.true.` | enable GDIIS | the same value as MAPLE |
| `diis_memory` | — | 6 | number of DIIS vectors | MAPLE `DIISParams.memory=6` |
| `diis_store_every` | — | 5 | snapshot interval | the same value as MAPLE |
| `diis_min_snapshots` | — | 3 | minimum number of snapshots | MAPLE `DIISParams.min_vectors=3` |
| `diis_regularization` | — | 1.0e-10 | Tikhonov regularisation | the same value as MAPLE |
| `trust_init` | bohr | 3.7795e-1 | RFO initial trust radius | MAPLE `RFO.RFOParams.trust_radius_init=0.2 Å` |
| `trust_min` | bohr | 1.8897e-3 | minimum trust radius | MAPLE `1e-3 Å` |
| `trust_max` | bohr | 1.8897 | maximum trust radius | MAPLE `1.0 Å` |
| `eta_shrink` | — | 0.75 | radius shrink factor for a rejected step | the same value as MAPLE (`RFO.py:295-304`) |
| `eta_expand` | — | 1.75 | radius expansion factor for an accepted step | the same value as MAPLE |
| `evals_eps` | — | 1.0e-10 | eigenvalue denominator protection | the same value as MAPLE |
| `mu_margin` | — | 1.0e-8 | the gap between the shift and min(w) | the same value as MAPLE |
| `max_bisect_it` | — | 60 | shift-bisection cap | the same value as MAPLE |
| `recalc` | — | **5** | recompute the exact Hessian every N steps (for RFO) | MAPLE `RFO` recomputes every step (`RFO.py:193-201`); this plan takes 5: a numerical Hessian is 6N single points each time, and `recalc=1` would make RFO pay 6N+1 single points per step (R2-07) |
| `linesearch` | — | `'armijo'` | the line-search type | MAPLE has no explicit line search (it relies on the trust radius); after adding it, it is still doubly limited by `max_step` + trust |
| `max_backtrack` | — | 10 | Armijo backtracking cap | added; prevents infinite backtracking |
| `armijo_c1` | — | 1.0e-4 | the Armijo constant | a standard value (Nocedal & Wright, *Numerical Optimization* 2006, Alg. 3.1) |

#### 5.3.5 `TScanSettings`

| Field | Unit | Default | Meaning / comparison |
|---|---|---|---|
| `mode` | — | `'relaxed'` | `relaxed\|rigid` (MAPLE `scan.py:14-17`) |
| `method` | — | `'lbfgs'` | inner optimiser (MAPLE `method="lbfgs"`) |
| `ndim` | — | 1 | 1 or 2 (required by D2; MAPLE scan supports 1–3, but 3D has no practical value → this plan does only 1–2) |
| `coord(i)%ctype` | — | `'distance'` | `distance\|angle\|dihedral` |
| `coord(i)%atoms(4)` | — | 0 | 1-based atom indices (**starting from 1**; MAPLE input is 1-based but internally `a-1`, `scan.py:83`) |
| `coord(i)%step` | bohr / rad | 0.0 | step (distance bohr, angle rad; the user may input Å/degrees, converted at the boundary) |
| `coord(i)%nstep` | — | 0 | number of steps |
| `bidirectional` | — | `.true.` | scan in both directions and report the hysteresis (**new**, reason: failure mode 1 of R04 §4.6) |
| `sequential` | — | `.true.` | with ndim=1 use sequential semantics; with ndim=2 switch to a Cartesian-product grid |
| `warm_start` | — | `.true.` | hot-start every scan point from the previous point's geometry (engineering recommendation (b) of R04 §4) |
| `spring_expo` | — | 2.0 | the constraint-potential exponent, **effective only for distance**: in xtb `constrain_pot` the angle uses `fc·(θ−θ0)²` and the dihedral `fc·(1−cos(φ−φ0))`, so `expo` enters only the distance term (`src/constrain_pot.f90:196-212, 253-258, 282-312`). This **bounded** periodic form for the dihedral has a **restoring torque of zero** at Δφ = 180° (reaching the maximum `fc` only at 90°, with a barrier upper bound `2fc`), so the actual stiffness near a trans coordinate is far smaller than the nominal `fc` — this is why "dihedral scans drift more easily than distance scans", and a direct consequence of spring_expo having no effect on it (measurement in `docs/_landscape-recon/14-m2-validation-experiments.md` §4.2) |
| `constraint_fc` | hartree/bohr² (distance) or hartree (angle/dihedral) | 0.5 | the constraint force constant. **0.5 is not xtb's existing default**: `src/scanparam.f90:77` measures `fcconstr = 0.05_wp` (the initial plan misread this; corrected by the M2 review measurement, see `docs/_landscape-recon/14-m2-validation-experiments.md` §4). The reason for keeping 0.5: the finite spring potential gives the constrained coordinate a systematic offset; measured (1,2-dichloroethane dihedral, GFN2, 24° grid, `normal` level) at fc=0.05 the maximum offset is 6.84° with a barrier of 2.731 kcal/mol; at fc=0.5 it is 0.82° / 2.864 kcal/mol; fc≥2 converges to 0.04° / 2.873 kcal/mol (the limit), i.e. the barrier error is 0.33% at fc=0.5 and 4.9% at fc=0.05. To align point by point with the existing `--scan` (`xtbscan.log` tool chain), use `--lscan-fc 0.05` explicitly |

#### 5.3.6 `TTsSettings` (with sub-blocks)

Common fields:

| Field | Unit | Default | Meaning / comparison |
|---|---|---|---|
| `method` | — | `'prfo'` | `prfo\|bprfo\|dimer\|neb\|cineb\|autoneb\|string` |
| `conv` | — | `normal` | see §5.3.1; MAPLE's PRFO uses the `loose` magnitude (9.5e-3/5e-3 Ha/Å), reproducible with `--lts level=loose` |
| `verify_ts` | — | `.true.` | after convergence, one frequency confirmation (imaginary-frequency count == 1) |
| `verify_hess_source` | — | `'file'` | the Hessian used for the confirmation (from M4) |

**The P-RFO / B-P-RFO sub-block (`TPrfoSettings`)**

| Field | Unit | Default | Comparison / reason |
|---|---|---|---|
| `trust_init` / `trust_min` / `trust_max` | bohr | 3.7795e-1 / 1.8897e-3 / 1.8897 | MAPLE `PRFOParams.trust_radius=0.2, trust_min=1e-3, trust_max=1.0` (Å) |
| `eta_shrink` / `eta_expand` | — | 0.75 / 1.75 | the same value as MAPLE |
| `max_attempts` | — | 8 | MAPLE `PRFO.py:820-834` |
| `evals_eps` / `mu_margin` / `max_bisect_it` | — | 1e-10 / 1e-8 / 60 | the same value as MAPLE |
| `recalc` | — | 1 | MAPLE `recalc=1` (exact Hessian every step); pysisyphus suggests 1–5 (R04 §27) |
| `hessian_update` | — | `'bofill'` | the MAPLE default; pysisyphus says explicitly "Should not be modified for TS optimizations" (R04 §27) |
| `target_mode` | — | 1 | which negative mode to follow (1-based, filling the semantic gap of xtb `tsroot`, `src/setparam.f90:501`) |
| `alpha` | — | 0.5 | the trust split ratio between the uphill/downhill subspaces (MAPLE `alpha∈[0.05,0.95]`, `PRFO.py:140-351`) |
| `max_micro_cycles` | — | 50 | the micro iterations of the RS variant (the pysisyphus default, R04 §27) |
| `mode_overlap_min` | — | 0.3 | the mode-following guard: `\|Vᵀ·v_tracked\| < this value` → re-select the mode and warn (**new**, preventing the mode hopping of R03 §C.4) |
| `bprfo_delta_alpha` | — | 0.05 | bprfo's alpha adaptation step (**new**) |

**The Dimer sub-block (`TDimerSettings`)**

| Field | Unit | Default | Comparison / reason |
|---|---|---|---|
| `delta` | bohr | 1.8897e-2 | Henkelman's dimer separation ΔR=1e-2 Å (R04 §30); **note the definition ambiguity** (VASP's DdR is the distance between the two images, pysisyphus's length is midpoint-to-image, R04 Contradictions #1) → this plan takes "midpoint→image" (consistent with pysisyphus) and states it in the documentation. **[M4 fix round disposition] `[to be calibrated]` closed**: report 28 §6.4 measures that `delta×8` changes the curvature by only 0.0013 %, and the analytic MB check is within 0.07 %; no longer relying on the VASP doubling claim, the pysisyphus convention is adopted uniformly and written into the header comment |
| `hvp_step` | bohr | 5.0e-3 | the HVP difference step; MAPLE `delta=0.005 Å = 9.45e-3 bohr` (`dimer.py:105-139`), the difference being that matching xtb `step_hess` eases auditing |
| `rot_max_iter` | — | 5 | the same value as MAPLE |
| `rot_alpha` | — | 0.5 | the same value as MAPLE |
| `rot_f_max_th` / `rot_f_rms_th` | hartree/bohr | 5.29e-4 / 2.65e-4 | MAPLE `rot_f_max_th=1.0e-3, rot_f_rms_th=5.0e-4` (Ha/Å) converted |
| `step0` | bohr | 3.7795e-1 | MAPLE `step0=0.2 Å`; **[M4 fix round] it is only the** upper bound **of the first translation, and the `dR` curvature probe may shorten it further (measured GFN2 HCN first step 0.1032, not `min(step0,step_max)=0.28346`); `--lts-step0` was added** |
| `step_max` | bohr | 2.8346e-1 | MAPLE `step_max=0.15 Å` |
| `trust_radius` | bohr | 2.8346e-1 | the same value as MAPLE |
| `kappa_to_flip` | — | 0.0 | the same value as MAPLE (`dimer.py:105-139`); the curvature criterion C<0 (R04 §29 Eq.21) |
| `use_mass_weight` | — | `.false.` | the same value as MAPLE |
| `remove_rigid` | — | `.true.` | the same value as MAPLE |
| `n_init` | — | `'random'` | `random\|force` (MAPLE also has `given`; M4 does only the first two, to avoid bloating the input format) |
| `seed` | — | 42 | **new, mandatory**: MAPLE `dimer.py:258` uses an unseeded `default_rng()` (R03 §C.6), so the Fortran side must be reproducible |

**The NEB / CI-NEB sub-block (`TNebSettings`)**

| Field | Unit | Default | Comparison / reason |
|---|---|---|---|
| `n_images` | — | 10 | MAPLE `NEBParams.n_images=10` |
| `k_min` / `k_max` | hartree/bohr² | 2.083e-3 / 2.083e-2 | MAPLE `0.03/0.3`, whose unit is missing from the MAPLE documentation; this plan converts per ASE convention (eV/Å²) (0.03 eV/Å² = 2.083e-3 Eh/bohr²; the ASE default `k=0.1 eV/Å` falls in that interval, cf. R04 §42). **[M5 disposition] `[to be calibrated]` closed (report 37 §3.2/§4.3)**: the calibration target is the **dynamic schedule**, not a single k — on LEPS the band measures that the dynamic `1e-2/1e-1` (48 steps) and the dynamic PLAN initial value (30 steps) both converge with a barrier error < 1e-4 kcal/mol, while the **static** `1e-2` and static `1e-1` do not converge within 400 steps (the static `1e-3`, `1` and `10` converge). On NH3 the dynamic calibrated value is 11 steps / the PLAN initial value 20 steps |
| `use_dynamic_k` / `k_decay` | — | `.true.` / 0.5 | the same value as MAPLE; the formula is in §6.4 |
| `ifidpp` | — | 1 | the MAPLE default; IDPP see R04 §47 |
| `lbfgs_m` | — | 20 | the same value as MAPLE |
| `step0` | bohr | 3.7795e-2 | MAPLE `2e-2 Å` |
| `band_f_rms_avg` | hartree/bohr | 1.736e-3 | geomeTRIC 0.025 eV/Å (R04 §46) converted |
| `band_f_rms_max` | hartree/bohr | 3.472e-3 | geomeTRIC 0.05 eV/Å |
| `climb_switch_rms` | hartree/bohr | **9.7234e-3** | geomeTRIC `--climb 0.5` eV/Å; **[M5 disposition] `[to be calibrated]` closed (report 37 §3.1)**: 0.5 eV/Å = 0.5·evtoau/aatoau = 9.7234532e-3 Eh/bohr; the PLAN initial value 3.472e-2 is an **inverse** conversion (0.5/14.4), 3.57 times larger. `settings.f90` stores 5 significant digits, 9.7234e-3 (off by 5.3e-8 = 5.5e-6 relative) |
| `climb` | — | `.true.` | CI-NEB is on by default (R04 §45: the CI correction for NEB underestimating by about 0.4 eV) |
| `refine` | — | `''` | `''\|cineb\|nebts` (MAPLE `refine=None`) |
| `remove_rotation_and_translation` | — | `.true.` | the ASE non-periodic default (R04 §39) |

**The AutoNEB sub-block (`TAutoNebSettings`)**

| Field | Unit | Default | Comparison |
|---|---|---|---|
| `n_images` | — | 20 | MAPLE `AutoNEBParams.n_images=20` |
| `ang_max` / `ang_iter` / `path_iter` | — | 0.3 / 20 / 50 | the same values as MAPLE |
| `min_e_drop` | hartree | 3.6749e-5 | MAPLE `0.001` (eV) converted |
| `ep_iter` / `ep_e_drop` | — / hartree | 30 / 1.8375e-5 | MAPLE 30 / 0.0005 eV |
| `max_depth` / `max_paths` | — | 5 / 10 | the same values as MAPLE |
| `do_final_refine` / `final_refine_factor` / `final_refine_max_iter` | — | `.true.` / 2.0 / 200 | the same values as MAPLE |

**The String/GSM sub-block (`TStringSettings`)**

| Field | Unit | Default | Comparison / reason |
|---|---|---|---|
| `grow_step` / `grow_step_min` | bohr | 2.2677e-1 / 3.7795e-2 | MAPLE `0.12/0.02 Å` |
| `grow_backtrack` | — | 0.5 | the same value as MAPLE |
| `grow_relax_iters` | — | 10 | the same value as MAPLE |
| `grow_relax_frms` | hartree/bohr | 1.323e-3 | MAPLE `grow_relax_tol=2.5e-3` (Ha/Å) converted |
| `merge_threshold` | — | 0.5 | the same value as MAPLE |
| `n_images` | — | 9 | MAPLE 9; pysisyphus `max_nodes=9` (R04 §50) is the common point |
| `reparam_every` | — | 3 | the same value as MAPLE |
| `perp_thresh` | — | 0.05 | pysisyphus `perp_thresh=0.05` (R04 §50) |
| `string_f_max` / `string_f_rms` | hartree/bohr | 2.646e-3 / 5.29e-4 | MAPLE 5e-3/1e-3 Ha/Å converted |
| `cistring_f_max` / `cistring_f_rms` | hartree/bohr | 2.117e-3 / 1.058e-3 | MAPLE 4e-3/2e-3 Ha/Å converted |

#### 5.3.7 `TIrcSettings`

| Field | Unit | Default | Meaning / comparison |
|---|---|---|---|
| `method` | — | `'hpc'` | `gs\|hpc\|lqa\|eulerpc`. **M6 behaviour change (report 46)**: the default changes from `gs` to `hpc` — measured, HPC is more accurate (the maximum deviation from the reference MEP on MB is 0.0022 vs GS 0.040 bohr) and cheaper by 8.5× (1.98 vs 16.9/20.3 E/g, report 44 §3.3). `gs` is kept as a compatibility/comparison implementation and as the fallback for a failed correction; the default CLI path is asserted by `xtb/landscape-irc-knobs` |
| `target_mode` | — | 1 | the starting mode (1-based, matching MAPLE `target_mode=1`) |
| `step_length` | bohr·amu^1/2 | 0.10 | MAPLE `step_length_bohr=0.10`; Gaussian `IRC=StepSize` defaults to 0.10 (R04 §67); **the recommended range is 0.05(tight)–0.20; but GS's clean range measured on MB is only 0.05–0.15** (0.20 forward is already supercritical: 87 macro steps, arc length 17.39, the endpoint 0.106 bohr from min2; report 67); **0.40 fails in measurement** (LQA off by 3.3e-4, HPC-forward 2.4e-3, EulerPC 5.8e-3/1.1e-2 Eh in both directions with 3 fallbacks, report 44 §4.4) ⇒ allowed by the paper, but not recommended by this implementation |
| `max_steps` | — | 256 | **backfilled from measurement (report 44 §4.5)**: reaching the minimum needs only ≤104 steps (at step 0.05), so the PLAN's original citation of MAPLE's 50 would **truncate a normal 0.05-step path**; the physical signals (b)/(c) always end a normal path first, so a wide upper bound `--lirc-max-steps` is kept |
| `grad_tol` | Eh/bohr (RMS per component) | 1.0e-3 | termination signal (b); measured, the endpoint RMS is reachable for gs 5.98e-4, lqa 7.57e-4, hpc 9.59e-4, ≈2553 times the warm noise (3.916e-7 Eh/bohr) (report 44 §4.2, report 43 §7.2) |
| `max_micro_cycles` | — | 20 | GS-only (the same value as MAPLE). **No longer a bottleneck after report 64**: before the fix, the micro loop was measured to be truncated by this budget every time (the criterion was never satisfied, see §6.5); after the fix, budgets 5/20/21/200 give the same result (the micro loop converges in 1–3 evaluations), and the budget is only an upper bound |
| `micro_step_thresh` | — | 1.0e-3 | GS micro-loop convergence (the same value as MAPLE); measured, the tangential-space Newton step is 1.8–2.4 ≫ the sphere radius 0.05 ⇒ the criterion is unreachable |
| `euler_n` | — | 5000 | LQA/HPC prediction sub-steps (Hratchian & Schlegel Eq.10, R04 §8) |
| `max_pred_steps` | — | — | **not implemented (an explicit deviation, report 46)**: EulerPC's prediction is a **single explicit Euler step** (`eulerpc.f90:206`), so no prediction-step cap parameter exists. MAPLE's 500 has no corresponding implementation point, so it is recorded as an API deviation rather than a dead knob |
| `loose_cycles` | — | 3 | EulerPC (the same value as MAPLE) |
| `hessian_recalc` | — | -1 | -1 = never recompute (MAPLE `hessian_recalc=None`); a positive number = recompute every N steps. **Measured (report 44 §5.2)**: on a short path (4 bohr) pure Bofill is enough (endpoint error ~1e-5 Eh); over a long integration (150 steps) HPC-backward drifts to 6.0e-4 Eh from the true HCN minimum with \|g\|=4.1e-2, and `recalc=10` returns to the minimum (\|g\|=4.4e-7) ⇒ the default stays -1 (all accepted numbers come from it), but long/strongly curved paths **must explicitly** use `--lirc-recalc 5..10` |
| `hessian_update` | — | `'bofill'` | the EulerPC paper measures with Bofill (R04 §17) |
| `dwi_n` / `mbs_max_k` / `mbs_points` | — | 4 / 15 / 20 | `dwi_n` is measured to be a **capacity**: the interpolation surface by construction has only 2 points (the current + the predicted point), and ≥2 is equivalent (measured, `--lirc-dwi-n 4` and `20` are bit-identical), while <2 is refused (report 46) |
| `mbs_tol` | bohr·amu^1/2 | 1.0e-5 | the same value as MAPLE; the HPC paper's mBS acceptance threshold 1e-6 a.u. is stricter (R04 §8) |
| `forward` / `backward` | — | `.true.` / `.true.` | bidirectional (`--lirc-oneway` disables backward); with oneway, `irc.log` states explicitly "not requested" (no longer printing error/F, report 46) |
| `e_rise_steps` | — | 3 | termination signal (c): the energy rising for N consecutive steps judges that the minimum has been passed (R04 §20); measured, the endpoint is insensitive to it (<5e-6 Eh) and it is 1e9 times above the noise |
| `rmsd_end` | bohr | 1.8897e-1 | the endpoint-attribution criterion: only a Kabsch-aligned RMSD to the relaxed minimum ≤ this value counts as "reached the minimum" (`endpoint_reached`); with `--lirc-no-endpoint-relax` there is no relaxed minimum, the criterion is unusable, and `irc.log` states that it was skipped (M-1/M-2, report 46) |
| `conv` (`--lirc-level`) | — | `normal` | the four criteria acting **only on the endpoint relaxation** (the same `set_conv_level` as `--lopt-level`/`--lscan-level`); measured, superloose reaches −5.47213843 Eh in 1 step and vtight −5.47215989 Eh in 7 steps (report 46). The path criteria are `grad_tol`/`e_rise_steps`, which do not enter this level |

#### 5.3.8 `THessianSettings` and `TVibSettings`

| Field | Unit | Default | Comparison / reason |
|---|---|---|---|
| `source` | — | `'numerical'` | see §5.2; `numerical\|model\|file` |
| `step` | bohr | 5.0e-3 | xtb `step_hess` (`src/type/setvar.f90:158`); MAPLE uses 0.002 Å (`calculator_base.py:355`), the difference being that it matches xtb + the baseline of the §8 experiment #2 |
| `sccacc` | — | 0.3 | xtb `accu_hess` (`src/type/setvar.f90:156`). **Exposed explicitly**, reason: R04 §77 points out that 0.3 is an artificially relaxed accuracy that directly determines imaginary-frequency stability |
| `odlr` | — | `.false.` | the ODLR approximation (`src/o1numhess.f90:71`), for large systems |
| `project_tr` | — | `.true.` | project translation/rotation (Eckart, R04 §71) |
| `linear_tol` | — | 1.0e-8 | linear-molecule decision (3N-5 vs 3N-6) |
| `temperature(50)` | K | 298.15, the rest 0 | follows xtb `thermotemp` (`src/setparam.f90:283`) |
| `pressure` | kPa | 101.325 | RRHO reference pressure |
| `rotor_cutoff` | cm⁻¹ | 50.0 | xtb `thermo_sthr` (`src/setparam.f90:285`) |
| `imag_cutoff` | cm⁻¹ | -20.0 | xtb `thermo_ithr` (`src/setparam.f90:287`) |
| `freq_scal` | — | 1.0 | xtb officially recommends 1.0 (R04 §73) |
| `ilowfreq` | — | 2 | the Grimme low-frequency entropy scheme (MAPLE `FrequencyParams.ilowfreq=2`) |

**Trade-off note**: the `freq` task does **not rewrite** the thermochemistry. `vib/thermo.f90` only "copies the settings into
`set%thermoset` → calls the existing `main_freq`/`thermodyn`", because xtb already has a complete RRHO + symmetry number
+ low-frequency correction (R02 §4.3, `src/thermo.f90:79`). This suite's **incremental value** for `freq` is:
(a) exposing the Hessian as a reusable intermediate quantity to TS/IRC (the provider semantics);
(b) promoting `step`/`sccacc`/`odlr` to explicitly adjustable parameters.


### 5.4 Result types and convergence report
```fortran
! types/results.f90
type :: landscape_convergence_report
   integer :: n_iter = 0
   character(len=:), allocatable :: level
   logical :: converged(4) = .false.     ! f_max, f_rms, dp_max, dp_rms
   real(wp), allocatable :: history_energy(:), history_gnorm(:)
   real(wp), allocatable :: history_f_max(:), history_f_rms(:)
   real(wp), allocatable :: history_dp_max(:), history_dp_rms(:)
   real(wp), allocatable :: history_trust(:)
   integer,  allocatable :: history_method(:)  ! 1=sd,2=cg,3=lbfgs,4=bfgs,5=diis,6=rfo,7=prfo,...
end type

type :: landscape_result
   integer  :: status = 0          ! 0=converged, 1=max_iter, 2=stagnated, <0=error
   real(wp) :: energy = 0.0_wp     ! hartree
   real(wp) :: gnorm = 0.0_wp      ! hartree/bohr (Euclidean norm of gradient)
   real(wp) :: f_max = 0.0_wp, f_rms = 0.0_wp          ! hartree/bohr
   real(wp) :: dp_max = 0.0_wp, dp_rms = 0.0_wp        ! bohr
   real(wp) :: egap = 0.0_wp       ! hartree
   integer  :: n_eval = 0, n_hess = 0, n_hvp = 0, n_scf_fail = 0
   real(wp), allocatable :: xyz(:,:)        ! (3, natoms) bohr
   real(wp), allocatable :: gradient(:,:)   ! (3, natoms) hartree/bohr
   type(landscape_convergence_report) :: conv
end type
```

| Type | Key fields | Used by |
|---|---|---|
| `landscape_path_result` | `n_images`; `xyz(3,n,n_images)` bohr; `energy(n_images)` hartree; `e_barrier` hartree; `ts_image`; `spline_node(n_images)` | scan / NEB / CI-NEB / AutoNEB / string |
| `landscape_saddle_result` | `result` (`landscape_result`) + `n_imag`; `imag_freq(nimag)` cm⁻¹; `mode(3n)` (the followed mode, sign already aligned) | prfo/bprfo/dimer |
| `landscape_irc_result` | `n_fwd`,`n_bwd`; `xyz_fwd(3,n,n_fwd)`,`xyz_bwd(3,n,n_bwd)`; `e_fwd(n_fwd)`,`e_bwd(n_bwd)`; `s_fwd(n_fwd)`,`s_bwd(n_bwd)`; `reached_min_fwd/bwd`; `rmsd_to_min_fwd/bwd` | irc |
| `landscape_vib_result` | `freq(n)` cm⁻¹ (negative for imaginary); `modes(3n,3n)`; `zpe` hartree; `n_imag`; `linear` | hessian/freq |
| `landscape_cost_report` | `n_eval`,`n_hess`,`n_hvp`,`n_scf_fail`,`wall_seconds` | all (performance evidence) |

The `status` semantics are fixed: `0` converged; `1` reached `max_iter`; `2` stagnated (N consecutive steps with no improvement, N=`stagnate_patience`, default 10);
`<0` error (`env%error` already recorded, the caller `return`s).

### 5.5 Logging and trajectory output conventions

Every trajectory is written through `writeMolecule(mol, unit, fileType%xyz, energy=, gnorm=, number=)`
(`src/io/writer.f90:36`); the geometry is in **Å** (the xyz format convention), the energy in `hartree`, and `gnorm` is printed in `hartree/bohr`.

| Task | File | Content | Note |
|---|---|---|---|
| all | stdout (`env%unit`) | section headers (the `generic_header` style) + one line per step `iter / E / gnorm / f_max / dp_max / trust / method` | consistent with the existing table style of `relaxation_engine` |
| opt | `xtbopt.xyz` | the final optimised geometry | **keeps the existing name** (`src/prog/main.F90:1129-1136`) |
| opt | `xtb.trj` | one trajectory frame per step | keeps the existing name |
| opt | `xtb.trj` | trajectory (the `fileType%trj` semantics) | keeps the existing name |
| scan | `xtbscan.log` | each frame's geometry + `energy=Etot−Efix` (the de-biased energy) | **keeps the existing name** (`src/scan_driver.f90:98,129`); the new driver still writes that name for compatibility. **A scan point whose geometry is discarded is not written as a frame** (it has no energy, and its geometry may be an unevaluated zero frame); in that case the energy on that stdout row is `NaN` and `conv = F`, and the file is opened with `status='replace'` so that no frames of a previous run remain |
| scan | `xtbscan.log` (the same file when ndim=2) | grid frames (the comment carries the two coordinate values) | new |
| ts (prfo/bprfo/dimer) | `xtbts.xyz` (the final TS), `xtbts.log` (the trajectory) | geometry + `n_imag` | new |
| ts (neb/cineb/autoneb/string) | `path.xyz` | `n_images` frames, the comment carrying `energy` and the frame number | consistent with R05 §3.4 |
| ts (autoneb) | `path_autoneb.xyz`, `path_ts_list.xyz` | the global MEP and all local TSs | new |
| irc | `irc_forward.xyz`, `irc_backward.xyz`, `irc_path.xyz`, `irc.log` | single-direction forward/backward paths, the merged path (sorted by arc length, the highest-energy point marked `TS`), a per-point table | `irc_path.xyz` corresponds to MAPLE `inp1_full.xyz` (R03 §D) |
| hessian/freq | `vibspectrum`, `vib_normal_modes`, `g98.out`, `hessian` | keeps the existing output of `src/freq/io.f90` | **no duplicate files are added** |
| all | `landscape_<task>.json` (optional, `--ljson`) | structured `status/counters/conv history` output | for regression comparison |

**A common rule**: every file prints `wrote <filename>` once on `env%unit`; file handles use `open_file`/`close_file` (xtb's existing `filetools`),
and a failure → `env%error` (no `stop`).

**Representation of a missing value (settled in the M2 review round)**: any quantified value whose energy/gradient the engine discarded is represented by **NaN**
(`xtb_landscape_settings::landscape_missing_value`), and **must not** be written as `0.0`:
`0.0` is a fully credible energy value (a `0.0` point in a profile would silently survive in a script), whereas NaN is caught by
any `isnan`/comparison check. The rule and the measurement (a `0.0` adjacent to `-5.07 Eh` in one profile) are in
`docs/_landscape-recon/14-m2-validation-experiments.md` §5.3 and `16-m2-fix-report.md`.

---

## 6. Algorithm list and sources

> Each entry gives: the literature, the key formula/parameters, the failure mode, the protection. The formulas are from R04 (whose evidence grades are annotated in R04).

### 6.1 Minimisation (M1)

| Algorithm | Literature | Key parameters | Failure mode | Protection |
|---|---|---|---|---|
| steepest descent (SD) | — | `max_step=0.37795 bohr` | oscillation along ill-conditioned directions, extremely slow convergence | used only as a startup phase; switched after `sd_max_iter=50` |
| conjugate gradient (PRP+) | Polak–Ribière 1969; Gilbert & Nocedal 1992 (PR+) | `beta=max(g_k·(g_k−g_{k−1})/‖g_{k−1}‖², 0)`; a non-descent direction → restart as `-g` | non-quadraticity makes the direction fail | negative beta truncated to zero (= restart) + a non-descent-direction guard + a per-step `max_step` clip; the Powell alignment restart is **not** used (§12.8 D5) |
| L-BFGS | Nocedal 1980; MAPLE `LBFGS.py:61-84` | `m=5`; `gamma=y·s/y·y`; `curvature=70` | the Hessian approximation is destroyed when the curvature pair has `y·s≤0` | `y·s ≤ 1e-12` → discard the pair (`LBFGS.py:92-102`); `max_step` clip |
| full BFGS | Broyden/Fletcher/Goldfarb/Shanno 1970; xtb `src/bfgs.f90:20` | `hdamp` Powell damping | divergence under negative curvature | **force Powell damping** (`src/bfgs.f90:164 hdamp`); force symmetrisation |
| GDIIS | Császár & Pulay 1984; Farkas & Schlegel PCCP 2002 | `memory=6`; Tikhonov `1e-10` | linear dependence → an ill-conditioned B matrix | augmented `[B,-1;-1,0]` + regularisation (`DIIS.py:70-127`); not enabled before `min_vectors=3` |
| RFO (single shift + trust) | Banerjee 1985; Baker 1986; pysisyphus §7 (R04 §24) | solve the augmented eigenproblem; `μ < min(w)` found by bisection | a near-degenerate small eigenvalue → a huge step | `evals_eps=1e-10` denominator protection; the hard cap `trust_max=1.889 bohr`; `rho<eta_shrink` rejects and shrinks |
| line search | Nocedal & Wright 2006, Alg. 3.1 | Armijo `c1=1e-4`, `max_backtrack=10` | backtracking fails on a noisy PES | backtracking exhausted → accept the smallest step + a `stagnate` count |
| convergence decision | MAPLE `_common.py:74-89` | four criteria AND | judging only energy/gradient → false convergence | the four criteria of §5.3.1 + `dp_*` |

### 6.2 Scan (M2)

| Algorithm | Literature/basis | Key points | Failure mode | Protection |
|---|---|---|---|---|
| relaxed scan | the Gaussian semantics are equivalent to "constrained optimisation with Lagrange multipliers" (R04 §56) | each point: set `valconstr` → inner `tasks/opt` → the de-biased energy `Etot−Efix` | (1) hysteresis/catastrophe points (R04 §60.1); (2) a discontinuous SCF solution → fake/missing saddle (R04 §60.2); (3) scanned-coordinate definition drift (R04 §60.3) | (a) `bidirectional=.true.` with an explicit hysteresis report; (b) hot-start every point; (c) report the constraint residual; (d) `restart=p_restart_pin` to pin the wavefunction |
| rigid scan | xtb has no such mode (R02 §3.3); MAPLE `scan.py:159` | a single point after rigidly moving the internal coordinate (distance/angle/dihedral) | stretch/bend coupling distorts the geometry | defaults to `relaxed`; rigid is only a fast coarse scan, marked `mode=rigid` in the output |
| 2D grid | MAPLE `scan.py:380-405` | Cartesian product + row-by-row hot start | a grid point crosses a basin | row-by-row hot start + warn when the energy jump to a neighbour exceeds `max_jump` (default 0.5 hartree) |

### 6.3 TS optimisation (M4)

**P-RFO (dual shift, ORCA 6.1 §4.3.1 / Baker 1986, R04 §21)**

```
E      = E0 + gᵀ Δq + ½ Δqᵀ H Δq                          (4.16)
Δq_k   = −(F_k V_k)/(b_k − λ_p),   F_i = V_iᵀ g           (4.18a,4.19)
λ_p    = ½ b_k + ½ sqrt(b_k² + 4 F_k²)                    (4.18a)
Σ_{i≠k} F_i²/(λ_n − b_i) = λ_n    (iterative solve, requires λ_n < 0) (4.18b)
Δq_i   = −(F_i V_i)/(b_i − λ_n),  i ≠ k                   (4.19)
Δq     = Σ_j Δq_j                                         (4.20)
```

| Failure mode | Protection |
|---|---|
| the Newton step slides to the nearest minimum (ORCA §4.3.1 wording, R04 §22) | the dual shift forces a target stationary point with "exactly one negative eigenvalue" |
| the Hessian has >1 negative eigenvalue | shift/sign-flip the diagonal entries as ORCA does (R04 §21); this plan's implementation: `b_i → max(b_i, hlow)` and record it |
| mode hopping | the **overlap criterion**: `idx = argmax\|Vᵀ v_tracked\|` + sign realignment `sign = sign(overlap)` (PRFO.py:634-672, R03 §C.4); at `mode_overlap_min=0.3` re-select the mode and `env%warning` |
| a near-degenerate small eigenvalue → a huge step | `evals_eps` protection + trust radius (ORCA replaces small eigenvalues, which is community lore, R04 §36, for reference only) |
| too large a trust radius enters a wrong basin | pysisyphus suggests `trust ≤ 0.1`, `trust_max 0.3–0.5` (R04 §38); this plan accordingly provides the `--lts trust=0.1` shortcut level |
| numerical noise makes the force criterion unreachable | a tight SCF (`p_restart_off`) + experiment #4 to set the threshold |

**B-PRFO (monomolecular RS-P-RFO)**: the same as above, differing in the **subspace partition** of the trust radius
(`alpha` divides the total radius between the uphill/downhill subspaces) and up to `max_micro_cycles=50`
micro iterations; no batched tensor. See the terminology explanation under the consequences of D2.

**Dimer (Henkelman & Jónsson 1999, R04 §29-32)**

| Formula/parameter | Protection/note |
|---|---|
| `C = [(F2−F1)·N̂]/(2ΔR) = (E2−E0)/(ΔR)²` (Eq.2) | the sign of the curvature decides the translation direction (Eq.21) |
| rotation angle `Δθ = −½ arctan(2F0/F0')` (Eq.13, better than Eq.6) | more stable in the `F→0, F'→0` limit (the original text) |
| translation force `F† = F_R − 2F∥` (C<0); `F† = −F∥` (C>0) (Eq.21) | quick-min / CG propagation, limited by `step_max` |
| `ΔR = 1e-2 Å`, `δθ = 1e-4 rad`, `dR = 1e-3 Å` (the original's example, R04 §30) | this plan takes `delta` = 1.8897e-2 bohr (midpoint→image, consistent with the pysisyphus definition, R04 Contradictions #1) |
| **VASP diagnostic rule**: torque not decreasing ⇒ insufficient force accuracy, should lower EDIFF or increase DdR (R04 §31) | ported as a runtime diagnostic: if `rot_max_iter` is exhausted while `rot_f_rms > rot_f_rms_th`, `env%warning("dimer rotation did not converge; consider increasing delta or tightening SCF")` |
| random initial direction | `seed` passed explicitly; `n_init='force'` uses the direction of the largest gradient component as a deterministic substitute |

**GSM/String, NEB, CI-NEB, AutoNEB, IDPP** see §6.4.

**TS starting point and rigid projection**:
- initial mode direction: `find_projected_imag_modes` (`src/o1numhess.f90:694`) or
  the most negative mode after diagonalising the Hessian; the projection uses `projectHessian`/`trproj` (`src/freq/project.f90:34,151`).
- **transition-vector phase fixed** (R04 §35): the forward direction is defined as the direction in which the transition vector points when its largest component is positive;
  the output prints that largest component and the atom index, for reproduction (matching the Gaussian `Phase=(N1,N2,...)` semantics).
- translation/rotation projection: the Cartesian step is **projected** (`projectHessian`); `remove_rigid=.true.` by default.

### 6.4 Chain-of-states (M5)

| Algorithm | Literature | Key formula/parameters | Failure mode | Protection |
|---|---|---|---|---|
| improved-tangent NEB | Henkelman & Jónsson, JCP **113**, 9978 (2000) Eqs.8–12 | energy-monotonicity upwind; weighted average at extrema; the improved spring uses the **scalar distance difference** | a naive tangent causes kinks and path jitter | use the Eq.12 spring (the original Eq.5 is known to be suboptimal, R04 §41) |
| dynamic spring | ORCA style, MAPLE `neb.py:214-281` | `k_i = k_max − (k_max−k_min)·exp(−decay·ΔE_i/ΔE_max)` | too large a k hinders convergence (VASP warning, R04 Contradictions #2) | `k_min=1.0e-2`, `k_max=1.0e-1 Eh/bohr²`, `use_dynamic_k=.true.` (report 37 §3.2: within that window the static value actually fails, so the schedule is load-bearing) |
| CI-NEB | Henkelman/Uberuaga/Jónsson, JCP **113**, 9901 (2000) Eq.5 | `F_max = −∇E + 2(∇E·τ̂)τ̂`; the highest point is free of the spring force | igniting too early distorts the energy curve | run a normal NEB first, switch to CI after `band_f_rms_max < climb_switch_rms`; the threshold is set to 9.7234e-3 Eh/bohr (experiment #8, report 37 §3.1: on LEPS the ignition iteration is 31, and enlarging the threshold to 1.0 only ignites earlier and **does not change** the converged saddle and barrier) |
| IDPP initial path | Smidstrup et al., JCP **140**, 214106 (2014) | run NEB on a target surface that interpolates distances, **no energy evaluations needed** | linear interpolation produces discontinuities (the original text) | `ifidpp=1` by default |
| AutoNEB | Kolsbjerg/Groves/Hammer, JCP **145**, 094107 (2016); erratum JCP **148**, 029903 (2018) | build the path step by step + insert a point where the geometry/energy resolution is worst | complex tree management → resource overrun | the hard caps `max_paths=10`, `max_depth=5` |
| GSM/String | Peters/Heyden/Bell/Chakraborty, JCP **120**, 114101 (2004) Eqs.1,7,9 | normal force `f⊥ = −∇V + (τ̂ᵀ∇V)τ̂` (Eq.1); growth indicator `i(f⊥)=1 if \|f⊥\|≤tol` (Eq.7); `a1(k+1)=a1(k)+Δs·i(·)` (Eq.9) | too small a node spacing produces a kink | the spacing condition `R > \|∇V·τ̂\|/(2ν₂)` (the original text); the tangent uses a cubic spline (`cqpath_spline_repos`, `src/cqpath.f90:32`) |
| convergence | geomeTRIC | both the mean and the maximum `g_RMS` over all images are within tolerance (R04 §46) | a single-point criterion falsely converges on one bad image | use the two criteria `band_f_rms_avg` + `band_f_rms_max` |
| Kabsch/alignment | MAPLE `neb.py:55` | remove rotation and translation every step | path drift | `remove_rotation_and_translation=.true.` |

**Measured boundaries after the M5 closure (report 39, the M5 fix round)**

1. **Band propagation has no line search, and convergence is non-monotone in `n_images` (a measured window).** A band step is a truncated
   L-BFGS step, and neither of the two natural acceptance criteria (the band-force norm, the total image energy) is a descent function of the
   propagation: the tangential spring must temporarily raise both in order to redistribute the images. Measured (GFN2 NH3 inversion, report 39 §6.1): the step of the 3rd
   iteration raises the force norm under **either** scaling factor, while the band is still 2.8 times above the criterion; on LEPS, taking "the force norm
   decreases monotonically" as the acceptance criterion makes the band stagnate after 2 iterations. A **line search was therefore rejected by measurement** (both a backtracking line search
   and a "bounded growth" version were tried: the former makes NH3 stagnate, the latter's convergence window is still non-monotone, see report 39 §6.2),
   and instead: at `max_displ=0.37795` (default) 3/5/9/11 images converge and 7/13/15 diverge; at `max_displ=1e-1`
   3/5/7/9/11 images converge and 13/15 diverge (the initial band force is independent of the image count: IDPP `f_rms_max=1.199e-1`).
   The protection = an **explicit diagnostic**: the `diverged` flag (terminate early when the force norm exceeds 1e3 times the initial value, which on LEPS cuts the wasted 512 steps
   down to 147-390 steps) + an iteration-cap report, and **any** non-convergence ends with `env%error` (a non-zero exit),
   never silently returning the last iteration. The unit cases `band-initial-path-scan` (convergence count lower bound = the measured 9) and
   `band-divergence-guard` pin the window, and a regression turns them red. AutoNEB inherits the same window.
2. **The direction of GSM's first growth node** (report 38 M-2): the first growth node **must** be placed along `unit(P - R)`;
   the original implementation passed a "grid budget" as the index, so `tau` pointed at the coordinate origin. After the fix, string's measured numbers on NH3 change:
   growth 8 steps / 10 nodes (was 6 steps / 8 nodes), barrier **6.0702** kcal/mol (was 5.9789; the band gives
   6.0825) ⇒ the string-vs-band cross-check difference falls from 0.104 to **0.012** kcal/mol, and the TS-geometry RMSD falls from
   0.0140 Å to **0.0054 Å**. It was also found that when the curvature condition enlarges the spacing to the cap `2 ds = 1.0` bohr,
   the spherical-constraint relaxation stagnates on NH3; growth now **falls back to the requested step** (`ds = 0.5`) and retries once in that case
   (report 39 §3.4).
3. **String's force criterion on a molecular surface needs relaxing** (report 38 L-4): on NH3 with the **default** thresholds
   (`f_rms_avg=3e-4`, `f_rms_max=1e-3`) the measured residual is `3.79e-4 / 1.05e-3` ⇒ `converged F`,
   a non-zero exit; the CLI case therefore relaxes explicitly to `1e-3 / 2e-3`. String's default force criterion (`3e-4`/`1e-3`) is
   **unreachable** on a molecular surface, so `string%converged` is only a statement about the "node force residual", and IRC (M6) **must not**
   treat it as a criterion for the usability of a starting point.
4. **`neb` / `cineb` do not write `path_ts_list.xyz`** (report 38 L-6, an interface difference that must be recorded explicitly):
   only **AutoNEB** (one frame per stage) and **string/GSM** (the internal local maxima of the final path) write that file;
   plain NEB / CI-NEB write only `path.xyz`. Their highest image / climbing image is the most natural saddle candidate but is not put into
   that file. Any M6/M7 flow that consumes `path_ts_list.xyz` must tolerate "the file does not exist after an NEB/CI-NEB run".

### 6.5 IRC (M6)

Common convention (R04 §1.1, §67): **mass-weighted Cartesian, 1 a.u. along the path = 1 bohr·amu^1/2**;
`dx(s)/ds = −g(x)/|g(x)|` (Hratchian & Schlegel, JCP **120**, 9918 (2004), Eq.1).

| Method | Literature | Update / parameters | Failure mode | Protection |
|---|---|---|---|---|
| GS | Gonzalez & Schlegel, J. Phys. Chem. **94**, 5523 (1990) Eqs.8–10 | pivot `q*_{k+1} = q_k − ½ s N G g_k`, `N = (gᵀGg)^{-1/2}`; then constrained optimisation on the sphere of radius `s/2` (an **equality-constrained Lagrange step**, report 64) | the micro loop does not converge (strongly curved paths/large step, R04 §7). **Measured (report 64, after the fix)**: 1.88/2.14 E/g per point (16.93/20.25 before the fix; HPC 1.98/LQA 1.00), `n_pinned` 0/0 (33/38 before the fix); the maximum deviation from the MB reference MEP is 0.0192 (fwd)/0.0344 (bwd) bohr (0.040 before the fix, the largest of the four methods; HPC 0.0022) ⇒ **GS remains a non-default compatibility implementation (the default is hpc)**, but is no longer the worst integrator in cost/accuracy | `max_micro_cycles=20`, `micro_step_thresh=1e-3`; trust-region clamping; another known limitation: **at step 0.40 the GS macro step oscillates between the two basins** (both the old and new implementations: `(-0.28352,0.49222)↔(0.10872,0.44407)`, the new implementation differing by 2.5e-4), a large step outside the validated range (0.05–0.20) |
| GS's Lagrange fix (**landed, report 64**) | equality-constrained Newton (KKT): `[H+2λI, 2r; 2rᵀ, 0][d; dλ] = [-(g+2λr); -(|r|²-R²)]` | replace "a tangential-space Newton step + a per-eigenvalue floor + a clip" with a Lagrange step: λ = the current KKT residual multiplier `2λ = -(rᵀg)/|r|²` (making the radial residual zero), and level-shift to positive-definite when the tangential descent is insufficient | the old implementation's micro loop entered a **two-point cycle**: the returned point was 3.4e-4 (even budget)/1.3e-3 (odd budget) Eh away from the spherical-constraint minimum, and budgets 5/20/21/200 gave exactly the same result (measured in tests) | acceptance (**done, measured item by item**): the unit `gs-sphere-relaxation-quality` upper bound 2e-3 → **1e-10** (measured 8.5e-14), a budget-independence assertion, a `micro_converged` flip; the unit `gs-kkt-system` (the two KKT rows 1e-16 + the descent direction + the λ update trajectory + the level-shift branch); the CLI `xtb/landscape-irc-cli` golden values updated explicitly (4.051234→3.949160, 3.695670→3.538733, 16.9/20.2→1.88/2.14 E/g, `pinned>=1`→`==0`); `hpc`/`lqa`/`eulerpc` are bitwise unchanged at the validated step lengths (with evidence) |
| LQA | Page & McIver, JCP **88**, 922 (1988) (R04 §12); the QSD form is in Eckert & Werner, Theor. Chem. Acc. **100**, 21 (1998) Eq.6 | quadratic Taylor analytic propagation, `euler_n=5000` sub-steps | **oscillates on strongly curved paths and deviates largely from the MEP** (R04 §13); step 0.20 is "mildly difficult", 0.40 runs away | step defaults to 0.10, the `tight` level 0.05; the documentation **states explicitly which derivation is used** (the lineage ambiguity of R04 Contradictions #3) |
| HPC | Hratchian & Schlegel JCP **120**, 9918 (2004) Eqs.2–11 | prediction: `x(t)=x0+A(t)g0`, `a_ii(t)=(e^{−λ_i t}−1)/λ_i`; correction: the DWI surface + modified Bulirsch–Stoer (a simple Euler, not a modified midpoint), acceptance threshold 1e-6 a.u.; the step can reach 0.40 | a failed correction (the DWI derivatives untrustworthy, the semi-implicit mBS judged infeasible); step 0.40 degrades in measurement (the endpoint off by 2.35e-3 Eh, report 44 §4.4) | `mbs_max_k=15`, `mbs_points=20`, `mbs_tol` adjustable; on failure → fall back one GS step with a warning. **The implementation chooses 2 E/g** (the paper's 1 E/g): measured, the 1 E/g variant's endpoint lands **1e-3..5e-2 Eh** above the true HNC minimum (a faithful implementation V1 2.80e-3, V2 with a predicted secant 4.56e-2, report 44 §6.1), whereas 2 E/g gives 5.5e-5 |
| EulerPC | Meisner & Kästner JCP **133**, 224101 (2010) Eqs.2–4 | prediction: `x̃_{i+1} = x_i − (g_i/\|g_i\|)·s`; correction: the same DWI + mBS as HPC; a **first-order method** (log-log slope 2.016) | at step 0.20 it "cannot follow the path" (the original text); at 0.10 it is measured to be off forward by 0.52 kcal/mol and terminated by signal (c) (not converged to a minimum); **at 0.40 it fails in both directions** (5.8e-3/1.1e-2 Eh, 3 fallbacks) | default 0.10; `loose_cycles=3` allows coarse before fine; the error is ~O(step) ⇒ needs denser points |
| Hessian along the path | the EulerPC paper uniformly uses a **Bofill** update, and tests replacing it with an analytic Hessian every 2/5/10 steps (R04 §17) | `hessian_update='bofill'`, `hessian_recalc=-1` | a pure update drifts after a long integration. **Measured (report 44 §5.2)**: no problem on short paths; in a 150-step integration, pure Bofill's HPC-backward stops 6.0e-4 Eh from the true HCN minimum with \|g\|=4.1e-2, and `recalc=10` recovers it (4.4e-7) | provide `hessian_recalc=N` (long/strongly curved paths **must** set 5..10 explicitly); force symmetrisation after a Bofill update |
| endpoint termination | no uniform standard (R04 §19) | three signals: (a) `max_steps`; (b) `\|g\|` below `grad_tol`; (c) the energy rising for `e_rise_steps` consecutive steps | "which minimum it lands in" is unknowable | `reached_min_fwd/bwd` = signal (b)/(c) **and** the relaxation converged **and** the Kabsch-aligned RMSD ≤ `rmsd_end`; `irc.log` also prints the energy of the relaxed minimum and the `rmsd_end` criterion; with no relaxation the criterion is unusable and the log states that it was skipped |
| arc-length definition (LOW-4) | — | `s` is a **chord-length accumulation in gs/hpc/eulerpc**, and only **lqa is the integrated arc length** | comparing `s` across methods directly (on one and the same path GS 4.0512 vs LQA 4.2500, a 4.7% difference) | `irc.log` prints the definition used each time (`arc length s is ...`); the documentation states explicitly "not cross-method comparable" |

### 6.6 Hessian and frequencies (M3)

| Item | Parameters | Failure mode | Protection |
|---|---|---|---|
| numerical Hessian | central difference, `step=5.0e-3 bohr` (`src/type/setvar.f90:158`) | too small a step → subtractive cancellation error; too large → anharmonic contamination | `step` adjustable; the §8 experiment #2 scans `{0.002, 0.005, 0.010}` |
| the Hessian's SCF accuracy | `sccacc=0.3` (`src/type/setvar.f90:156`) | **a half-converged SCF injects noise directly into the Hessian**, and imaginary and low-frequency modes drift (R04 §77) | expose `sccacc` explicitly; default to following xtb, but give tightening options (0.1/1.0) in the documentation and experiments |
| symmetrisation | the existing xtb practice `h(jj,ii)=0.5*(h(ii,jj)+h(jj,ii))` (near `src/hessian.F90:291`) | non-symmetric → `dsyev` results meaningless | force symmetrisation before the provider returns (§5.2) |
| projection | Eckart projection removes translation/rotation (R04 §71) | no projection → 6 spurious zero frequencies contaminate the mode decision | `project_tr=.true.` + `projectHessian`/`trproj` |
| linear molecules | 3N-5 internal degrees of freedom | the frequency count is wrong, the rotational partition function is wrong | `linear_tol` + reuse of xtb's `linear` flag (`src/type/data.F90:111`); §8 experiment #12 |
| frequency scaling | xtb recommends 1.0 (R04 §73) | blindly applying a literature scaling factor → inconsistent thermochemistry | default `freq_scal=1.0` and print it |
| thermochemistry | RRHO + rotor cutoff 50 cm⁻¹ + imaginary-frequency cutoff −20 cm⁻¹ (`src/setparam.f90:285,287`) | low-frequency-mode entropy divergence | reuse the quasi-RRHO of `thermodyn` (`src/thermo.f90:79`); follow the xtb defaults |

### 6.7 Hessian update family (M1)

| Update | Literature | Applies to | Protection |
|---|---|---|---|
| BFGS | the four authors, 1970 | minimisation | **Powell damping** (`src/bfgs.f90:164 hdamp`), a `y·s>0` check |
| Powell | Powell 1971 | TS optimisation (already used by xtb `tsopt`, `src/optimizer.f90:341-344`) | symmetrisation |
| Bofill | Bofill 1994/1995 | the **consensus default for paths/TS** (pysisyphus says explicitly not to change it, R04 §27) | symmetrisation + denominator protection |
| SR1 | Murtagh–Sargent 1970; Conn–Gould–Toint 2000 | indefinite Hessians | a double threshold guard on the denominators `\|y·s\|` and `\|sᵀ(H−…)s\|`; skip the update when close to zero |
| common requirements | — | — | **force symmetrisation** after the update; a covariance/curvature anomaly → `env%warning` + skip |

### 6.9 `$fix` support matrix (new this round: what existing behaviour was fixed, what explicitly errors)

xtb implements `$fix` at the **calculator layer** (`src/xtb/calculator.f90:304-306`: the fixed atoms' gradients are zeroed).
That suffices for a **first-order** direction but does **not** imply that the fixed components of a second-order step are zero: the RFO/P-RFO step
is expanded in the eigenvectors, and the eigenvectors mix the fixed and the free components (`docs/_simplify-recon/04-o2-and-silent-defects-fix.md` §2.1).
Therefore every path that can produce a second-order step must **additionally project** or **explicitly refuse**, never be silent.

| Path | Handling | Location | Status |
|---|---|---|---|
| `--lopt` (sd/cg/lbfgs/bfgs/diis/rfo) | project the direction vector | `src/landscape/optimize/driver.f90` (`landscape_project_frozen`) | ✅ fixed this round + test + injection |
| `--lscan` relaxed inner loop | as above (the same driver) | `src/landscape/scan/relax_scan.f90` (`landscape_scan_relax_point`) | ✅ |
| `--lts` endpoint relaxation, `--lirc` endpoint relaxation | as above | `src/landscape/tasks/ts.f90` (`relax_one_endpoint`), `tasks/irc.f90` (`relax_endpoint`) | ✅ |
| `--lts --lts-method prfo\|bprfo\|dimer` | project the accepted step (reusing the same place as the rigid projection) | `saddle/prfo.f90` (main step + escape walk), `saddle/dimer.f90` | ✅ this round (report §5.2) |
| `--lts --lts-method neb\|cineb\|autoneb\|string\|gsm` | **`env%error` refusal** | `src/landscape/tasks/ts.f90` (before the band branch) | ⛔ **TODO**: the interpolation/IDPP/redistribution of band images is undefined with `$fix` (when the two endpoints are inconsistent) |
| `--lirc` (gs\|lqa\|hpc\|eulerpc) | **`env%error` refusal** | `src/landscape/tasks/irc.f90` (entry) | ⛔ **TODO**: see below |
| `--lscan --lscan-mode rigid` | not covered (a purely geometric construction) | `scan/scan1d.f90`/`scan2d.f90` | ⛔ TODO (no experiment done) |

**The `--lirc` TODO (why it is not done this round)**: the IRC propagation is in the **mass-weighted** metric (`bohr*amu^1/2`),
and the `s` column is M6's **contract** (mass-weighted arc length, the "arc-length definition" row of §6.5). After projecting the step onto the `$fix` subspace:

1. **The arc-length semantics must choose one of two and be written into the contract**: is `s` "the accumulation of the requested step" or "the arc length actually walked"?
   The projection shortens the actual step, so the two are no longer equal; the self-consistent choice is to **count only the arc length within the allowed subspace**
   (`s_cur = s_cur + |Δq_projected|`), but that would make `s` differ in convention from an unprojected run on the same path,
   which is a contract change and must be ruled on first.
2. **LQA's corrector has a fixed point of uncertain existence under projection**: the `Sigma_n` step uses **Newton iteration to hit the requested `s_target`**
   (`irc/corrector.f90:399-493`), and the projected step **cannot** reach that arc-length target ⇒ the iteration's fixed point is not "the projected correction point".
   That is the basis for the "not confidently correct" judgement.
3. **GS's spherical relaxation** has closed its Lagrange open item (report 64), but `--lirc` + `$fix` is still refused per items 1/2 (arc-length semantics and the LQA fixed point), for reasons unrelated to GS.

⇒ Following the "prefer to fail loudly" principle, this round turns `--lirc` + `$fix` into an **explicit error** and registers it as a TODO;
the fix (already analysed as feasible) is to project each method's accepted-point **mass-weighted displacement** (zeroing the fixed components of `Δq` ⇔ zeroing the fixed components of `Δx`,
because `Δq_i = sqrt(m_i) Δx_i`), rewrite the accumulation of `s` per item 1, and then re-run the M6 acceptance for each method.

---

## 7. Numerical-hygiene rules

> An executable checklist taken from R03 §C. **Every item is a blocker for code review.**

| # | Rule | Reason / source |
|---|---|---|
| N1 | every new module's first line is `use xtb_mctc_accuracy, only : wp`, and `implicit none(type, external)` | xtb enforces double precision (`cmake/CMakeLists.txt:50` `-fdefault-real-8`; `src/mctc/accuracy.f90:31` `wp = dp`). `implicit none(type, external)` is the existing style of new modules (`src/model_hessian/type.f90:31`) |
| N2 | no bare literals in numerical expressions: always the `_wp` suffix; no bare `real` / `real*8` / `double precision` | R03 §C.1; if the build configuration lacks `-fdefault-real-8`, a bare `real` degrades to single precision |
| N3 | all array indices **1-based**; when comparing with MAPLE, annotate the `±1` conversion points explicitly | R03 §C.2 (MAPLE `scan.py:83` has `a-1`) |
| N4 | flatten always as `xyz(3, n)` (flattening order `x1,y1,z1,x2,…`, consistent with numpy's `reshape(-1)`); **`xyz(n,3)` is forbidden** | R03 §C.3 (the biggest semantic pitfall) |
| N5 | declare two-dimensional matrices as `(dim, n)`; `matmul`/`dgemm` use column-major semantics; transposition must be explicit `transpose()` | R03 §C.3, the `.T` placement table |
| N6 | always use the `xtb_mctc_blas` / `xtb_mctc_lapack` / `xtb_mctc_la` wrappers; calling `dgemm/dsyev` directly is **forbidden** | R02 §6.5; `src/mctc/blas.f90:19`, `lapack.f90:19`, `linalg.f90:18` |
| N7 | after an eigenvalue solve, **state the ascending-order convention explicitly**; mode tracking must do `argmax\|overlap\| + sign realign` | LAPACK `dsyev/dsyevd` and `np.linalg.eigh` are both ascending (R03 §C.4); sign alignment in `PRFO.py:634-672` |
| N8 | declare units in the **module header comment**; a.u. throughout internally (bohr, hartree, amu); boundary conversion only through `xtb_mctc_convert` | R03 §C.5 (MAPLE has inlined constants scattered around with inconsistent precision: `627.509` vs `627.509474`); xtb constants in `src/mctc/convert.f90:25-42` |
| N9 | a bitwise comparison with MAPLE is **not feasible**: xtb `autoaa=0.52917726` vs MAPLE `0.529177210903`; `autokcal=627.50947428` vs `627.509474` | R03 §C.5; only compare a physical order of magnitude / topological consistency |
| N10 | random numbers must seed explicitly (set `random_seed` first, then `random_number`); **the only permitted random use is the dimer initial direction** | R03 §C.6 (MAPLE `dimer.py:258` has no seed) |
| N11 | the convergence criterion is fixed to the four criteria, with the `rms` denominator = **3N (per component)** | R03 §C.7 |
| N12 | division by zero/square root/logarithm must have a guard (`abs(x) > tiny` / `max(x, eps)`); Hessian updates force symmetrisation; BFGS must use Powell damping | task hard constraint + section 6.7 |
| N13 | error handling is uniformly `call env%error(...)` + `call env%check(fail)` (`src/type/environment.f90:298,162`) or returning `logical fail`; **`stop` / `error stop` are forbidden** | R02 §7.6 |
| N14 | **module-level mutable variables are forbidden**; settings are passed explicitly through parameter objects | R01 §9.7 (the lesson of MAPLE's dual default values) |
| N15 | every `allocate` paired with a `deallocate`; every `intent` explicit; an `intent(in)` argument must not be written | repository existing style |
| N16 | every module / type / public procedure needs a `!>` documentation comment: physical meaning, units, algorithm, references | task hard constraint; style in the header of `src/type/molecule.f90` |
| N17 | floating-point equality is allowed only for a "same geometry" cache hit (§5.1); numerical equality always goes through a tolerance parameter | §5.1 |
| N18 | new code must not change the existing semantics of `set%`; when a new switch is needed, use landscape's own settings; only the 5 existing files listed in §12 may be modified | D1 + the minimal-change constraint |

---

## 8. Test strategy

### 8.1 Three layers of tests

| Layer | Goal | Carrier | Criterion |
|---|---|---|---|
| **L1 pure mathematics** (analytic potentials) | verify the **algorithmic correctness** of the optimiser/saddle/path/IRC, independent of GFN2 | `test/unit/landscape_*.f90`, using `TlandscapeAnalyticEngine` (an `extends` engine defined inside the test + built-in analytic potentials) | the step sequence, convergence rate and final-point geometry agree with the analytic solution; **bitwise reproducible** |
| **L2 xtb-engine integration** | verify the engine boundary: determinism, caching, Hessian symmetry, cost counting | `test/unit/landscape_engine.f90` etc., using the real `TxTBCalculator` (H2O, CH3OH, HCN) | the energy of repeated calls is bitwise identical; `n_eval` matches the expectation; the Hessian symmetry error < 1e-14 |
| **L3 end-to-end regression** | verify the task chains and output files | `test/unit/landscape_e2e.f90` + `ctest` (auto `add_test` in `test/unit/CMakeLists.txt:95-96`) | H2O: the `opt → freq` frequencies agree with `--hess` (tolerance); HCN↔HNC: `ts → irc` lands at the correct minima on both ends |

**The choice of L1 analytic potentials** (the strong-validation substitute of R03 §E.3, §D):
- 2D: the **Müller–Brown surface** (with 2 minima + 1 saddle, analytic gradient/Hessian) → PRFO, dimer, NEB, string and IRC can all be verified point by point.
- higher-dimensional: the **LEPS potential** (H + H₂) → 3 atoms, analytic gradient/Hessian, a known TS geometry and barrier → for a quantitative comparison of NEB/CI-NEB/IRC.
- linear: **CO₂ / acetylene** (3N-5) → frequency counting and the Eckart projection.
**Reason**: all of MAPLE's fixtures are based on ML potentials (R03 §D), so they cannot serve as a GFN2 numerical benchmark and cannot be compared bitwise.

### 8.2 De-risking experiments (the 12 items of R04 §9)

The `Gate` column = which milestone it must be completed **before**; the `Covering test` column = which test file is responsible.

| # | Experiment | Gate | Covering test | Output |
|---|---|---|---|---|
| 1 | determinism of repeated xtb calls (N consecutive `singlepoint` on the same geometry; `restart=off` vs reusing `TRestart`) | **before M0 is complete** | `test_landscape_engine.f90` | a bitwise-equality conclusion + if not equal, the magnitude of the difference (Eh/bohr); decides whether `p_restart_off` is the default (this plan already defaults to off) |
| 2 | Hessian step × sccacc sensitivity (H2O/CH3OH, step∈{0.002,0.005,0.010}, sccacc∈{0.3,0.1,1.0}) | **before M3 is complete** | `test_landscape_vib.f90` | a drift table of frequencies/lowest eigenvalues/the imaginary-frequency count; backfills the `THessianSettings` defaults |
| 3 | the effect of `etemp` (0/300/1000/5000 K) on the lowest 3 eigenvalues | **before M4** | `test_landscape_vib.f90` + `test_landscape_saddle.f90` | if significant, TS/IRC freeze `etemp` and write it to the output |
| 4 | gradient noise σ_g vs the trust-radius infimum | **before M4 / M5 / M6** | `test_landscape_engine.f90` (σ_g) + `test_landscape_saddle.f90` (threshold) | gives the reachable lower bound of the force threshold; backfills `TConvSettings.normal` and `TTsSettings` (`[to be calibrated]`) |
| 5 | P-RFO mode following vs a Sella/pysisyphus(+xtb) cross-check (SN2, HCN→HNC, Diels–Alder) | during M4 | `test_landscape_saddle.f90` | convergence generations, TS-geometry RMSD, the imaginary-frequency count and value |
| 6 | four-algorithm IRC cross-check (run forward+backward from the same TS) | during M6 | `test_landscape_irc.f90` | the endpoint geometry/energy/attributed minimum; a significantly deviating method is downgraded in the documentation |
| 7 | calibration of the IRC endpoint criterion (against Gaussian `MaxPoints=10` / ORCA `MaxIter=20`) | during M6 | `test_landscape_irc.f90` | calibration of the three termination-signal thresholds |
| 8 | the CI-NEB climbing switch threshold (would 0.5 eV/Å be spuriously triggered by noise) | **before M5** | `test_landscape_path.f90` (`climb-switch-calibration`, `band-spring-schedule`) | **closed (report 37 §3)**: `climb_switch_rms = 9.7234e-3 Eh/bohr` (= 0.5 eV/Å); noise does not spuriously trigger it (σ_g ≤ 1.2e-15, warm 3.9e-7, smaller by 13/4 orders of magnitude) and the switch is decided entirely by the band (a measured same-position bitwise-equality check); `k_min/k_max = 1.0e-2/1.0e-1` dynamic schedule |
| 9 | DMF feasibility | **not executed** (excluded by D2) | — | recorded as `not-applicable` |
| 10 | DL-FIND reusability (legal + technical) | before M0 (already done) | — | R05 §1.1: DL-FIND is LGPL-3.0, compatible with xtb, but its architecture (callback-style + HDLC + MPI task-farm) differs greatly from `TCalculator`, so **do not carry over the code, only borrow the design** (end of R05 §1.1.2) |
| 11 | quantifying the rigid vs relaxed scan hysteresis (bidirectional dihedral) | during M2 | `test_landscape_scan.f90` | the maximum forward/reverse E(q) difference and the discontinuity points; decides the `bidirectional` default (this plan already defaults to true) |
| 12 | linear molecules / 3N-5 (CO₂, acetylene) | **before M3** | `test_landscape_vib.f90` | frequency counting, the Eckart projection, the correctness of the rotational partition function |

### 8.3 Test naming and registration

- File: `test/unit/test_landscape_<area>.f90`, module `test_landscape_<area>`, exporting `collect_landscape_<area>`.
- Registered in two places (fully isomorphic with the existing `test_hessian`):
  - add `landscape-engine`, `landscape-settings`,
    `landscape-conv`, `landscape-optimize` to the `tests` list of `test/unit/CMakeLists.txt:22-55` (M0/M1); M2–M6 add in turn `landscape-scan`,
    `landscape-vib`, `landscape-saddle`, `landscape-path`, `landscape-irc`.
  - add `use test_landscape_engine, only : collect_landscape_engine` etc. to `test/unit/main.f90:22-53`,
    and append `new_testsuite(...)` into `testsuites = [...]`.
  - keep the `tests` list of `test/unit/meson.build:34-66` in step (cannot be verified on this machine, see §10 R-16).
- The naming style aligns with the existing: `new_unittest("single-atom-ancopt", test_single_atom_ancopt)` (R02 §7.5).
- **ctest test names must be globally unique**: when a unit-suite name of the form `xtb/<suite>` clashes with a CLI test name,
  CMake **silently drops the one registered first**. M2 once named the CLI smoke test `xtb/landscape-scan` as well,
  so 23 scan unit cases never ran under ctest (in `test/unit/CTestTestfile.cmake`
  only the `cmake -P` line was left); the M2 review round renamed the CLI test `xtb/landscape-scan-cli`.
  After adding tests, check the names and the count with `ctest -N -R landscape`.

---

## 9. Phased milestones M0–M7

Dependencies: `M0 → M1 → M2 → M3 → M4 → M5 → M6 → M7`;
`M3` depends on `M1` (reusing `types/updater`); `M4` depends on `M3` (the initial Hessian provider);
`M5` depends only on `M1` (can run in parallel with M3/M4); `M6` depends on `M3` (Hessian) + `M4` (the TS starting point).

### 9.1 M0 (implemented): skeleton + engine boundary + types + build wiring + test skeleton

> Status legend: **✅ delivered**; **🔁 merged** (merged into another file, see §12.8 difference D1);
> **❌ not delivered**. The line counts are the actual line counts after implementation (`wc -l`).

| File | LOC actual/est | Content delivered | Status |
|---|---|---|---|
| `src/landscape/types/settings.f90` | 525 / 350 | the task settings base class (four criteria, `engine`, `hessian_source`, the `task()` binding) + `landscape_opt_settings` + `landscape_sp_settings` + `set_conv_level` + the name↔identifier table | ✅ delivered |
| `src/landscape/types/results.f90` | 289 / 150 | `landscape_step`, `landscape_result`, `landscape_convergence_report` + printing | ✅ delivered |
| `src/landscape/engine/engine.f90` | 693 / 400 | `landscape_engine` + `landscape_engine_control` + `landscape_energy_model` (analytic-potential injection) + cache/counters/`hvp`/the three restart states | ✅ delivered |
| `src/landscape/types/conv.f90` | — / 120 | the four-criteria `is_converged` + `landscape_convergence_measures` | 🔁 merged into `types/settings.f90` (the criteria) and `types/results.f90` (the convergence report) |
| `src/landscape/types/log.f90` | 93 / 140 | trajectory/final-geometry writing (`writeMolecule` wrapper, `<prefix>opt.xyz` / `<prefix>.trj`) | ✅ delivered |
| `src/landscape/tasks/sp.f90` | 181 / 120 | `landscape_single_point` (E + optional gradient report + optional Hessian) | ✅ delivered |
| `src/landscape/landscape_api.f90` | 77 / 130 | `run_landscape(env, mol, chk, calc, set, res)` (the single entry point from `main.F90`) | ✅ delivered |
| `src/landscape/landscape_driver.f90` | 107 / 150 | dispatch `tasks/*` by `settings%task()`, the PBC guard, a one-line closing summary | ✅ delivered |
| `src/landscape/CMakeLists.txt` | 44 / 40 | all paths + `PARENT_SCOPE` | ✅ delivered |
| `src/landscape/meson.build` | 44 / 30 | isomorphic (no meson on this machine, see R-16) | ✅ delivered |
| `test/unit/test_landscape_settings.f90` | 390 / 180 | item-by-item default-value assertions + `set_conv_level` over all levels + a name↔identifier round trip | ✅ delivered |
| `test/unit/test_landscape_conv.f90` | — / 120 | the four-criteria boundaries (exactly at the threshold, the `rms` denominator 3N) | 🔁 merged into `test_landscape_settings.f90` (`convergence-boundary`, `convergence-measures`) |
| `test/unit/test_landscape_engine.f90` | — / 260 | cache/counters/Hessian symmetry/HVP recovery/`off` vs `warm` | 🔁 merged into `test_landscape_optimize_math.f90` (`engine-cache`, `engine-hvp`) and `test_landscape_optimize_xtb.f90` (the determinism probe) |

**M0 acceptance tests**
1. `ctest -R landscape` fully green (see the real run output of §12.9);
2. **the build really passes**: `cmake -S . -B /tmp/xtb-o2/build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON -DCMAKE_BUILD_TYPE=Release -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"` + `cmake --build` (see the §10 environment constraints);
3. no regression in the existing `test/unit` (`ctest -R 'landscape|api'` + the CLI smoke fully green);
4. `xtb --help` / `xtb --version` still work (`xtb/Argparser_print_help`, `xtb/Argparser_print_version` fully green);
5. code review: the N1–N18 checklist (`engine%ctrl%hessian_source` has been removed, see §12.8 D3).

**M0 actual LOC ≈ 2400 (implementation + test skeleton).**

### 9.2 M1 (implemented): minimisers + update formulas + line search + unified driver

| File | LOC actual/est | Content delivered | Status |
|---|---|---|---|
| `src/landscape/optimize/hessian_update.f90` | 294 / 300 | `update_bofill`/`update_bfgs` (Powell damping)/`update_powell`/`update_sr1`, forced symmetrisation + denominator guards | ✅ delivered |
| `src/landscape/types/hessian.f90` | ~390 / 220 | abstract `landscape_hessian_provider` + the own-central-difference `landscape_numerical_hessian_provider` + the **implemented** `landscape_model_hessian_provider` (Lindh-D2 initial guess) + the `hessian_source` factory; the provider's `n_eval` counts into the engine cost | ✅ delivered (the model-Hessian body was filled in in M1, see §12.8 D4) |
| `src/landscape/optimize/sd.f90` | 47 / 130 | SD step (the displacement clipping is done uniformly by the driver) | ✅ delivered |
| `src/landscape/optimize/cg.f90` | 167 / 250 | PRP+ CG (negative coefficient truncated to zero + restart on a non-descent direction) | ✅ delivered (the Powell alignment restart is not used, see §12.8 D5) |
| `src/landscape/optimize/lbfgs.f90` | 180 / 260 | L-BFGS two-loop recursion + dynamic `gamma` + curvature filtering | ✅ delivered |
| `src/landscape/optimize/bfgs.f90` | 158 / 180 | dense BFGS (spectral decomposition for the step + `hlow` lifting) | ✅ delivered |
| `src/landscape/optimize/diis.f90` | 201 / 220 | GDIIS + Tikhonov regularisation + snapshot management | ✅ delivered |
| `src/landscape/optimize/rfo.f90` | 235 / 320 | mass-weighted single-shift RFO + bisection + trust clamping | ✅ delivered |
| `src/landscape/optimize/trust.f90` | — / 200 | trust-region state machine | 🔁 merged into `rfo.f90` (`landscape_rfo_update_trust`) |
| `src/landscape/optimize/line_search.f90` | 131 / 180 | Armijo fallback + displacement clipping | ✅ delivered |
| `src/landscape/optimize/driver.f90` | 497 / — | the pure-math kernel `landscape_optimize_model` (algorithm dispatch + four criteria + stagnation detection + trajectory buffer) | ✅ delivered (not listed in §9.2 for M1, see the §4.2 layering) |
| `src/landscape/tasks/opt.f90` | 205 / 260 | task-level driver: assemble the engine/provider, call the kernel, write to disk, report | ✅ delivered |
| `test/unit/test_landscape_optimize_math.f90` | 533 / 420 | sd/cg/lbfgs/bfgs/diis/rfo convergence on analytic potentials (harmonic oscillator/Rosenbrock/Müller–Brown) + cache/HVP/line-search switches/Hessian-provider wiring | ✅ delivered |
| `test/unit/test_landscape_optimize_xtb.f90` | 261 / — | GFN2 water minimisation, output files, determinism probe (`off` bitwise reproducible) | ✅ delivered |
| `test/unit/landscape_testpot.f90` | 351 / — | analytic test potentials (the 351-line `testpot.f90` of M6 has been moved out of `libxtb`) | ✅ delivered |
| `test/unit/test_landscape_cg.f90` | 252 / — | CG direction reproduction + the two restart paths + a step-count comparison on a strongly convex quadratic | ✅ delivered |
| `test/unit/test_landscape_hessian.f90` | 318 / — | `hessian_source` dispatch + an error on an unrecognised value + a pointwise comparison of the own FD Hessian with `TCalculator%hessian` | ✅ delivered |
| `test/unit/test_landscape_api.f90` | 216 / — | the `sp`/`opt` dispatch of `run_landscape`, unknown tasks and the PBC refusal | ✅ delivered |

**M1 acceptance test**: as M0's 1–5, plus
"`--lopt` end-to-end: `xtb h2o.xyz --lopt --lopt-engine lbfgs --lopt-level normal` converges and writes `xtbopt.xyz` + `xtb.trj` (with `--namespace ns` these are `ns.xtbopt.xyz` + `ns.xtb.trj`, see §12.9 and report 53 §N-1)"
(the `xtb/landscape-opt` of `ctest -R landscape`, see §12.9),
and "`--lopt` does not change the behaviour of the existing `--opt` (regression)": `ctest -R 'Singlepoint|IP|GFN'` fully green.

**M1 actual LOC ≈ 2700 (implementation + tests).**

### 9.3 M2 (implemented): Scan

| Module | File | LOC actual/est | Status |
|---|---|---|---|
| constraint-relaxation kernel | `scan/relax_scan.f90` | 1139 / 300 | ✅ delivered (with a rigid-fragment guard + drift criterion + wrap function) |
| 1D | `scan/scan1d.f90` | 473 / 350 | ✅ delivered |
| 2D | `scan/scan2d.f90` | 363 / 320 | ✅ delivered |
| task driver | `tasks/scan.f90` | 352 / 180 | ✅ delivered |
| test | `test/unit/test_landscape_scan.f90` | 2098 / 400 | ✅ delivered (27 cases) |

Deliverable: `--lscan`; `xtbscan.log`-compatible output; bidirectional scan + hysteresis report; constraint-residual report.
**M2 acceptance test**: `ctest -R landscape` fully green at 25/25 (of which `xtb/landscape-scan` contains 27 cases); + `ctest -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'` 12/12 with no regression.
Acceptance (rewritten into a reachable form in the M2 review round; the three MEDIUM findings were fixed in the final round, see `docs/_landscape-recon/18-m2-final-fix-report.md`):

1. Experiment #11 (hysteresis quantification): the hysteresis of a relaxed bidirectional scan decreases monotonically as the convergence level is tightened (measured 5.63e−6 Eh on the default-level 12° grid);
2. 1D/2D grid-point count and **coordinate correctness** (per mode, each falsifiable):
   - **rigid**: `wrapped(reached − target) == 0` (the construction is purely geometric, tolerance 1e−8 bohr / 1e−8 rad, i.e. the per-point runtime criterion `xtb_landscape_scan_relax::rigid_drift_tol`; 1D judges an out-of-range value as an error, 2D only warns because two rigid operations perturb each other);
   - **relaxed**: `reached − target` equals the **known** offset of the constraint spring `F_phys(q*)/(2 fc)` (measured in §5.3.5: about 0.82° at fc=0.5, about 6.84° at fc=0.05), read directly from the `reached` column, and is **not required to be 0**;
   the stdout table prints the three columns `value/reached/drift`, where **drift = wrapped(reached − value)**, wrapped into [−180°, 180°), so a scan crossing ±180° no longer prints a false ±360° drift (the 2D path already has two sets, requested/value);
3. **at the same constraint-residual level**, the energy profile agrees with the reference scan (`--scan`/`relaxed_scan`) (tolerance 1e-6 hartree) — **`constraint_fc` on both sides must be set explicitly and aligned** (this suite defaults to 0.5, xtb `fcconstr` defaults to 0.05, see §5.3.5);
4. a rigid scan must have **no hysteresis** (a purely geometric construction ⇒ the forward and reverse branches are pointwise mutually inverse, hysteresis ≤ 1e−14 Eh) and pointwise `wrapped(reached − target) == 0` (tolerance 1e−8 bohr / 1e−8 rad, the same `rigid_drift_tol` as item 2).

**Convergence level and tolerance (measured)**: at both sides' default level item 3 was **not achieved**: for the water molecule 5 distance points the maximum is 1.316e−5 Eh, and for H₂O₂ 13 dihedral points 4.830e−6 Eh; after tightening both sides to `vtight`, H₂O₂ gives 6.672e−7 Eh (**achieved**) and water 1.615e−6 Eh (off by a factor of 1.6). The root cause is the **reference implementation ANCopt itself** drifting by 3.96e−6 Eh between default↔vtight (the same order as the two-side difference), not a problem of this suite (this suite's constraint residual at vtight is already ≤1e−5 Eh/rad). **Experiment-baseline discipline: scan / Hessian-related experiments always use `OMP_NUM_THREADS=1`** (measured, the same 2-point scan 0.13 s vs 44.12 s, a 340× reverse scaling ratio; see §Appendix A).
**Rigid scan (fixed in the M2 review round, see `docs/_landscape-recon/16-m2-fix-report.md`)**: the rotating fragment of a dihedral rigid point must be cut at the **central bond `j–k`** (take the far-side fragment containing the third atom `k`, which includes the terminal atom `l` and its substituents). Cutting at `l–k` degenerates the fragment into `{l}`, the substituents stay in place, and once the connectivity crosses the cut it swallows the `i` side, so the scanned dihedral **freezes** from the 7th point on (measured on a DCE 12° scan: hysteresis 0.1295 Eh = 81 kcal/mol, purely an artefact; after the fix the same scan gives 1.78e−14 Eh with a per-point drift < 5e−9°).
**The rigid runtime criterion (M2 final round, see `docs/_landscape-recon/18-m2-final-fix-report.md`)**: if the cut cannot separate two sides (`moving(blocked)` true: a ring, a non-bonded cut, a spurious bridge across the cut), it is always `env%error` + failure, no longer silently continuing; each rigid point additionally checks `wrapped(reached − target)` against `rigid_drift_tol = 1e−8` (bohr / rad), judging 1D out-of-range as an error and 2D only warning (two rigid operations perturbing each other is intrinsic to 2D rigid). The rigid-point drift criterion relies on `landscape_scan_coord_wrap_delta`, which is also the definition of the 1D table's `drift` column.
**Hessian (a policy item left to M3)**: `--lscan-method rfo` pays 6N single points to build a numerical Hessian **for every** scan point, while `--lopt-hessian` acts only on `lset`; the scan currently has **no** `--lscan-hessian` switch (`landscape_scan_settings%hessian_source` inherits the default `numerical` and can only be changed from the API). Adding that switch is handled together with M3's `file` provider.
**LOC ≈ 4400 (implementation 2330 + tests 2100).**

### 9.4 M3: Hessian / freq / thermo

| Module | File | LOC estimate |
|---|---|---|
| numerical-Hessian task layer | `vib/numhess.f90` | 200 |
| projection/modes/frequencies | `vib/modes.f90` | 260 |
| thermochemistry thin wrapper | `vib/thermo.f90` | 150 |
| `file` provider (the first concrete implementation of the parsing hook) | `types/hessian.f90` (append `landscape_hessian_file`) | 120 |
| task driver | `tasks/vib.f90` | 180 |
| test | `test/unit/test_landscape_vib.f90` | 400 |

Deliverable: `hessian_source=file`; `vibspectrum`/`vib_normal_modes`/`g98.out` aligned with the existing `--hess`.
Acceptance: experiments #2, #3, #12. **LOC ≈ 1310.**

**Status: implemented (M3)**, the implementation and wiring details are in §12.11, and the reports are
`docs/_landscape-recon/20-m3-vib-implementation-report.md` (implementation),
`21-m3-validation-experiments.md` (acceptance experiments) and
`23-m3-fix-report.md` (post-review fixes); the actual LOC: implementation 1407
(`vib/numhess.f90` 147 + `vib/modes.f90` 349 + `vib/thermo.f90` 173 +
`tasks/vib.f90` 277 + the `file` provider/reader-writer 461 newly added to `types/hessian.f90`)
+ tests 1036.
Experiment #2 (step×sccacc sensitivity), #3 (`etemp` on the lowest eigenvalue) and #12 (the 3N−5 of a linear molecule)
were all completed in the validation round, with data in `docs/_landscape-recon/m3-vib-data/` (79 jobs):
#2 → the default 0.005/0.3 has an error of ≤0.10 (H₂O)/≤0.35 (CH₃OH) cm⁻¹ relative to the strictest setting,
and must be tightened to 0.002/0.1 when |λ| ≲ 3 cm⁻¹; #3 → `etemp` changes the lowest curvature on near-degenerate systems by
5 %–31 % (stretched H₂ 0→5000 K gives −31.4 %), far larger than every error of step/sccacc;
#12 → the 3N−5 and the rotational partition function of CO₂/HCN are correct.
The only residual capability boundary is IR/Raman intensities (the Hessian provider carries no dipole derivatives, see §12.11).

### 9.5 M4: P-RFO / B-PRFO / Dimer

| Module | File | LOC estimate |
|---|---|---|
| mode selection and following | `saddle/eigenfollow.f90` | 260 |
| RS-P-RFO | `saddle/prfo.f90` | 900 |
| monomolecular B-P-RFO | `saddle/bprfo.f90` | 700 |
| Dimer | `saddle/dimer.f90` | 620 |
| task driver | `tasks/ts.f90` | 220 |
| test | `test/unit/test_landscape_saddle.f90` | 700 |

Deliverable: `--lts [method=prfo|bprfo|dimer]`; `xtbts.xyz`/`xtbts.log`; imaginary-frequency confirmation.
Acceptance: experiments #3, #4, #5; on Müller–Brown, prfo and bprfo converge to the same saddle (geometry RMSD < 1e-3 bohr).
**LOC ≈ 3400.**

**M4 hard constraints (from the M3 validation round, report 21 §3 and §7 R2/R3):**

1. **`etemp` must be frozen and recorded**. The electronic temperature is the largest single error source in this class of method: measured, the
   lowest curvature of stretched H₂ drifts by **−31.4 %** between `etemp` 0→5000 K (near-degenerate CH₃· −4.8 %,
   O₂ −0.26 %), far larger than every error of step/sccacc. `etemp` must not change within one run of
   `ts`/`irc` (the engine's `landscape_engine_control%etemp` is written into the xTB calculator, see §12.11),
   and the **actually effective value must be recorded** in the output/restart files (`engine_report` already prints it, and the four tasks
   `sp`/`opt`/`scan`/`vib` all call it, see §12.11; `xtb/landscape-vib-etemp` locks the CLI synchronisation).
   **[M4 fix round] It has also landed at the result-object level** (review 29 M1): `landscape_result%etemp`
   is written by `landscape_engine%effective_etemp()` after **reading it back** from the calculator (no longer a dead field never assigned),
   and `xtb/landscape-ts-etemp` together with `result%write_log` locks "result value == printed value".
   **[M4 fix round] On −31.4 %**: that was the result of an old linear classification treating a lifted rotation as an internal mode;
   after the H3 fix (see below) the true internal mode of stretched H₂ is a soft stretch, moving only **−0.86 %** from 300→5000 K
   (measured −1005.14 → −1013.83 cm⁻¹). The conclusion (etemp must be frozen + the effective value recorded) is unchanged.
2. **FD uncertainty near an imaginary frequency**: the default `step=0.005 bohr`/`sccacc=0.3` has been accepted, with a frequency error relative to the strictest
   setting (0.002/0.1) of ≤0.10 cm⁻¹ (H₂O), ≤0.35 cm⁻¹ (CH₃OH); a step of 0.02 or `sccacc=1.0` degrades to 1.7–4.4 cm⁻¹. **When some curvature falls within
   0±3 cm⁻¹, it must first be tightened to step 0.002 (and sccacc 0.1 if needed) before deciding the sign.**
   **[M4 fix round] Implemented** (review 29 H1): `tasks/ts.f90`'s `landscape_ts_curvature_band_hit`
   detects in cm^-1 whether an internal mode falls within `0±3 cm^-1` (the conversion from a Hessian eigenvalue is
   `|f| = sqrt(|λ|)·autorcm`, i.e. an eigenvalue bandwidth `(3/autorcm)^2 ≈ 3.4e-7 Eh/bohr^2`); on a hit,
   `confirm_saddle` automatically recomputes the Hessian once with `step=0.002`, `sccacc=0.1` and re-decides the sign,
   printing both results. The client ports `--lts-step`/`--lts-sccacc` were added (the same 15-line template as `--lvib`);
   if the Hessian source does not support tightening (`model`/`file`), an **explicit warning** is issued, and an in-band mode is no longer silently counted as 0 imaginary frequencies.
   Tests: the unit `ts-curvature-band` (including an injection: making the predicate always false turns it red) + three CLI missing-value errors.
   **[to-be-calibrated disposition] `imag_cutoff = -20 cm⁻¹`** keeps its original value (it is an imaginary-frequency counting threshold, a different concept
   from the 3 cm⁻¹ band); an in-band mode is now re-decided before counting, so the in-band "imaginary frequency is swallowed" defect is gone.
3. **Do not use "bitwise agreement with `--hess`" as a criterion**: the two paths use different projection conventions (Eckart vs
   `trproj`), and the difference grows with the distance from the stationary point (measured 0.076–5.21 cm⁻¹, §12.11).

**[M4 fix round] (the 4 HIGH + 8 MEDIUM of review 29)**:

- **H2 (a non-saddle must fail)**: `landscape_result%is_saddle` explicitly distinguishes "numerically converged" from "really a saddle";
  `confirm_saddle` sets `result%converged = .false.` and `result%message` when `n_imag /= 1`,
  and at the end of the task `env%error`/`env%check` gives a **non-zero exit code**; the geometry and `xtbts.log` are still written for debugging.
  The three outcomes (a true saddle / a minimum with 0 imaginary frequencies / a higher-order saddle with ≥2 imaginary frequencies) are each printed with their own exit code.
  Tests: `xtb/landscape-ts-minimum` (linear HNC → exit≠0) and a unit injection.
- **H3 (the imaginary frequency of a linear molecule swallowed)**: the linear branch of `vib/modes.f90` no longer **unconditionally** takes the lowest `n_zero` eigenvalues;
  it decides the zero modes using the overlap of the Hessian eigenvectors with the **mass-weighted rigid-body subspace** (3 translations + 2/1 rotations, Gram-Schmidt),
  and eigenvalues that are significantly non-zero (including significantly negative) are no longer treated as zero modes. The 5 zero modes and the internal-mode frequencies of CO2/HCN are **each unchanged**
  (an overlap of ~1 selects exactly the same 5 lowest modes); `q_ROT` depends only on the geometry and is unrelated to this change.
  The two true imaginary bending modes of linear H2O are now reported as 2 imaginary frequencies.
- **H4 (rigid-body noise makes lifted always true)**: the driver performs a rigid-body projection of the Hessian spectrum (`landscape_project_hessian_rigid`)
  **before** deciding `nneg`/`hlow`, and uses a **noise-aware threshold** `landscape_curvature_noise_tol`
  (relative to `max|λ|`) to judge a significantly negative curvature; lifted is true only when there really is significant negative curvature, warnings are de-duplicated (at most one per round)
  and the lifted eigenvalues are recorded. On clean GFN2 HCN `lifted=F` (before the fix it was `T` at every step).
- **The M items**: `result%etemp` really assigned (M1); prfo `reset_result` clears `conv` (M2); `xtbts.*` goes through
  `get_namespace` (M3); the driver-level projection has a 9-dimensional driver test (M4); the converged point is re-phased and the final transition vector printed (M5);
  `--lts-step0` + the `step0` documentation changed to "upper bound" (M6); the dimer step table's `trust/bohr` column relabelled `stepmax/bohr` (M7);
  `landscape_dimer_mobility` caps κ<0 by `1/|κ|`, and when the velocity is discarded it falls back one step to the force direction to remove zero-step macro iterations (M8).

Reports and data: `docs/_landscape-recon/30-m4-fix-report.md`.

**[M4 final fix round] (the 3 MEDIUM + geometry dependence of review 31)**:

- **MEDIUM-1 (starting from a minimum selects a rigid-body zero mode)**: `saddle/eigenfollow.f90`'s
  `landscape_select_transition_mode` now counts **significantly negative eigenvalues** within `-landscape_curvature_noise_tol`
  only (`nneg`), and when `nneg == 0` it follows the **lowest internal mode** (the first
  mode with `evals(i) > tol`) — i.e. `landscape_lowest_internal_mode` — instead of a constant `index = 1`.
  The first 6 (5 for a linear molecule) modes of an ascending spectrum are rigid-body zero modes (~1e-17 after
  `P H P`, with the sign decided by rounding); the old code's `index = 1` selected exactly those, and the step was then erased by `project_rigid`, so the search degenerated into a minimisation.
- **The real behaviour when starting from a minimum (measurable)**: **P-RFO / B-P-RFO need a saddle guess or a transition vector**.
  Fixing mode selection alone is not enough: at a (near-)stationary minimum the ascending component of the followed mode `-F_k/(b_k - λ_p)`
  vanishes along with the gradient, the initial model step is a **downhill step**, and the search returns to the minimum (measured, the HCN linear minimum:
  3 steps back to E = −5.504066 Eh, 0 imaginary frequencies, exit 1). The driver therefore gains an **escape walk**
  `prfo.f90:escape_from_minimum`: when (a) the spectrum has no significantly negative curvature and (b) the initial model step is not an ascending step,
  it walks **uphill** along the lowest internal mode with a step of `--lts-escape-step` (default 0.2 bohr), recomputing the Hessian at each step
  and following the mode until that mode's curvature turns negative (the cap `escape_max_walk = 3.0 bohr`), and then starts the search from there.
  Measured, the HCN linear minimum needs 7 pushes (1.4 bohr, curvature +0.0824 → −0.0053 Eh/bohr²),
  after which prfo converges in 5 steps / bprfo in 7 steps to the **same** saddle as the bent guess (E = −5.38737353 Eh).
  CLI-level evidence: `xtb/landscape-ts-escape` (the same linear HNC input, both prfo and bprfo require exit 0 +
  1 imaginary frequency + the escape record in the log); with `--lts-escape-step 0` disabling the escape, the same input degenerates into H2's
  "a minimum is not a saddle" path (`xtb/landscape-ts-minimum` locks that branch).
- **dimer needs no Hessian, so starting from a minimum is directly usable**: dimer uses only first derivatives (2 single points per macro iteration)
  and finds the lowest-curvature direction by axial rotation, without relying on the initial spectrum/mode selection. From the same linear minimum:
  prfo/bprfo need the escape walk, dimer needs **29 steps**, exit 0, 1 imaginary frequency, E = −5.387373461989 Eh
  (`dimer Hessian requests: 0`, also locked by the unit test `dimer-no-hessian`).
- **MEDIUM-2 (`λ_n` bisection does not verify the residual)**: `landscape_rfo_downhill_shift` now also checks the **upper end** of the interval:
  `residual(hi) > 0` means the equation has no root on `(-inf, min b_i)` (it needs
  `sum_{i≠k} F_i² ≲ mu_margin·(mu_margin − bmin)`, i.e. `|F_i| ≲ 1e-8` for the default `mu_margin = 1e-8`),
  in which case it **no longer returns the interval endpoint** but falls back to the degenerate `λ_n = 0` with a warning.
  Measured on the four real M4 runs (bent HCN and post-escape HCN, 19 solves in total for prfo/bprfo):
  `residual(hi) = −5e-4 … −2e-2`, the residual of the returned root `|≤5e-16|`, i.e. this failure mode never triggered;
  `bmin ~ −2e-16` (projection noise) is harmless. The unit test `prfo-lambda-n-no-root` uses a synthetic spectrum
  (`diag(-0.5, -1e-16, 0.5)`, `F = [0, 1e-11, 1e-11]`) to lock the fallback behaviour.
- **MEDIUM-3 (`result%etemp` has no assertion)**: `xtb/landscape-ts-etemp` gains two assertions
  (the `etemp:` line of stdout and the `electronic temperature (frozen)` line of `xtbts.log`),
  and deleting `tasks/ts.f90`'s `result%etemp = engine%effective_etemp()` turns it red (measured).
- **A written record of the geometry dependence**: reports 26/27/28/30 all add this section's two-starting-point measured comparison; the data is in
  `docs/_landscape-recon/m4-final-fix-data/`, report `32-m4-final-fix-report.md`.

| Starting point (GFN2) | prfo | bprfo | dimer |
|---|---|---|---|
| bent TS guess H(0,1.05,0) Å | 4 steps, 1 imaginary frequency −1426.12 cm⁻¹, exit 0, E=−5.387373532156 | 5 steps, 1 imaginary frequency, exit 0, E=−5.387373532550 | 15 steps, 1 imaginary frequency −1425.24 cm⁻¹, exit 0, E=−5.387373500230 |
| linear minimum H(−1.0,0,0) Å | escape 7 push/1.4 bohr + 5 steps, 1 imaginary frequency −1426.19 cm⁻¹, exit 0 | escape 7 push + 7 steps, 1 imaginary frequency, exit 0 | 29 steps, 1 imaginary frequency −1426.73 cm⁻¹, exit 0 |
| linear minimum + `--lts-escape-step 0` | 3 steps, 0 imaginary frequencies, exit 1 (an explicit diagnosis) | — | — |

### 9.6 M5: NEB / CI-NEB / AutoNEB / String(GSM)

| Module | File | LOC estimate |
|---|---|---|
| IDPP | `path/idpp.f90` | 220 |
| NEB kernel | `path/neb.f90` | 1400 |
| CI-NEB | `path/cineb.f90` | 360 |
| AutoNEB | `path/autoneb.f90` | 900 |
| String/GSM | `path/string.f90` + `path/gsm.f90` | 1100 |
| task driver | `tasks/ts.f90` (path branch appended) | 200 |
| test | `test/unit/test_landscape_path.f90` | 700 |

Deliverable: `path.xyz`, `path_autoneb.xyz`, `path_ts_list.xyz`.
Acceptance: experiment #8; the LEPS barrier differs from the analytic value by < 0.5 kcal/mol (matching the M5 criterion of R05 §3.6).
**LOC ≈ 4880.**

**M5 fix-round closure (report 39, `39-m5-fix-report.md`)**: all 4 MEDIUM findings of independent review report 38 were
fixed (M-1 `gsm.f90` uninitialised `n_eval`; M-2 the direction of the first growth node `unit(P − R)`; M-3 `neb.f90` /
`cineb.f90` documentation aligned with the formulas/measurements; M-4 the root guard of `landscape_testpot.f90` really eliminating division by zero),
F1/F2 (band-propagation robustness) were closed by the **measurement-driven option (b)** (a line search was rejected by measurement, replaced by an explicit
`diverged` diagnostic + a documented convergence window + a regression test), and LOW/INFO were disposed of item by item. The acceptance numbers after the fix:
the LEPS four-way cross-check barrier difference is unchanged (NEB/CI-NEB +0.0000, AutoNEB −0.0004, String +0.0003 kcal/mol);
NH3 NEB/CI-NEB **6.0825** and AutoNEB **6.0823** kcal/mol are unchanged; NH3 String/GSM changes to
**6.0702** kcal/mol because of M-2 (was 5.9789, while the band gives 6.0825 ⇒ the cross-check difference goes 0.104 → **0.012** kcal/mol),
and GSM vs CI-NEB TS-geometry RMSD is **0.0103 bohr (0.0054 Å)** (was 0.0265 bohr / 0.0140 Å).

### 9.7 M6: IRC (GS / HPC / LQA / EulerPC)

| Module | File | LOC estimate |
|---|---|---|
| DWI + mBS + LQA propagation (shared) | `irc/corrector.f90` | 420 |
| GS | `irc/gs.f90` | 820 |
| LQA | `irc/lqa.f90` | 700 |
| HPC | `irc/hpc.f90` | 900 |
| EulerPC | `irc/eulerpc.f90` | 950 |
| task driver | `tasks/irc.f90` | 260 |
| test | `test/unit/test_landscape_irc.f90` | 700 |

Deliverable: `--lirc [method=gs|hpc|lqa|eulerpc]`; `irc_*.xyz` + `irc.log`; three termination signals.
Acceptance: experiments #4, #6, #7. #6 is a cross-check of the four algorithms (bidirectional reconvergence of the same TS).
**LOC ≈ 4750.**

### 9.8 M7: thermo/validation close-out

| Module | File | LOC estimate |
|---|---|---|
| end-to-end chain: `sp→opt→hess→freq→thermo` | `tasks/*` (close-out + `--ljson`) | 250 |
| cross-validation script and documentation | `docs/` + `test/unit/test_landscape_e2e.f90` | 400 |

Deliverable: G/H/ZPE consistent with xtb's `--hess`; a **topology/geometry consistency** comparison record against each MAPLE task (not bitwise).
**LOC ≈ 650.**

**Actual delivery and acceptance results (backfilled in the M7 fix round; the `--ljson` specification is in §12.16)**

New files: `src/landscape/types/json.f90`, `test/unit/test_landscape_e2e.f90`,
`test/unit/landscape_e2e_check.py`, `docs/xtb-landscape-M7-validation.md`;
the 6 tasks (`sp`/`opt`/`scan`/`vib`/`ts`/`irc`) hook `--ljson`; the CLI gains
`--ljson`; 13 new ctest targets (`xtb/landscape-ljson-{opt,scan,scan2d,vib,ts,irc}`,
`xtb/landscape-e2e-{ljson-methods,ts-counters,scan-counters,chain,chain-failure,layers,maple}`).

**Acceptance numbers (four systems, `OMP_NUM_THREADS=1`, `--lopt --lopt-level tight` → the same
`xtbopt.xyz` with `--lvib` vs `--hess`; report 49 §1.1 / report 51 §4 re-measured and consistent)**

| System (mode count) | max Δν (cm⁻¹) | ΔZPE (Eh) | ΔH(298.15 K) (Eh) | ΔG(298.15 K) (Eh) | Tolerance |
|---|---|---|---|---|---|
| H2O (3N−6 = 3) tight | **0.0100** | 1.429·10⁻⁸ | 1.426·10⁻⁸ | 1.429·10⁻⁸ | 0.20 cm⁻¹ / 1.37·10⁻⁶ Eh |
| CH3OH (12) tight | **0.0600** | 2.975·10⁻⁷ | 3.070·10⁻⁷ | 2.530·10⁻⁷ | 1.00 cm⁻¹ / 2.7·10⁻⁵ Eh |
| CH3OH (12) `--lopt` **default** level | **0.8900** | −1.71·10⁻⁶ | — | — | 1.00 cm⁻¹ (only 12 % margin) |
| CO2 (linear 3N−5 = 4) tight | **0.0000** | 1.709·10⁻⁸ | 1.296·10⁻⁸ | 1.908·10⁻⁸ | 0.20 cm⁻¹ |
| C2H2 (linear 3N−5 = 7) tight | **0.0000** | −3.4·10⁻¹¹ | −2.1·10⁻¹¹ | −4.2·10⁻¹¹ | 0.20 cm⁻¹ |

* The tolerances come from **measurement** (report 49 §1.2): the H2O tight minimum measures 0.0100 cm⁻¹ / 1.43·10⁻⁸ Eh,
  and the CLI chain tolerances 0.20 cm⁻¹ (**20×**) and 1.0·10⁻⁶ Eh (**70×**, with the H2O effective value being the propagation-dominated
  1.37·10⁻⁶ = **96×**); the margin covers running the same check at **a less well converged minimum** — measured, deviating from the minimum
  by 0.02 bohr already gives 3.3–5.2 cm⁻¹ and default-level CH3OH gives 0.89 cm⁻¹ — plus cross-compiler LAPACK/OMP reduction-order
  differences. It is **not** the "2×0.097" or "5×1.8e-8" kind of arithmetic (the old document's formula was wrong, see report 51 §5).
* For linear molecules (CO2/C2H2) the two paths are **bitwise identical**: `trproj` and Eckart coincide within printing precision
  at 3N−5 with no molecular-axis rotation, so dfreq is 0.0000 (the linear-molecule case of PLAN §8.2 experiment #12).
* An independent recompute (a Python RRHO + free-rotor implementation not reusing xtb code, report 49 §1.3) agrees with the values xtb prints
  to ΔS ≤ 4.7·10⁻⁵ cal/mol/K, with ΔZPE equal to the rounding of the frequency table to 2 decimals.
* Chain measurement (report 49 §3.1): `sp` −5.070383095219 → `opt` −5.070544447778
  (== the `xtbopt.xyz` header line) → `--hess` == the same value → `--lvib` == the same value, ‖g‖ 7.5·10⁻⁶;
  moving one H in the geometry file by 0.05 bohr changes the energy (**no geometry caching**);
  `--lvib-hessian file` lowers the number of evaluations from 19 to 1.
* MAPLE: **not run** (on this machine `maple.function.dispatcher` cannot be imported for lack of `ase`/`torch`/`fairchem`),
  only the topology is compared; `maple.json` now records `maple_importable: false` + a non-empty error
  + the missing dependency names (report 51 §2 — before the fix it was a **false green** of `true` + an empty error).

**Total ≈ 21,960 lines** (including tests), on the same order as the sum of the per-file estimates of R03 §B.

---

## 10. Risk register

| ID | Risk | Impact | Probability | Mitigation | Covering test |
|---|---|---|---|---|---|
| **R-01** | **Hessian noise of `accu_hess=0.3`**: the SCF accuracy during a Hessian run is artificially relaxed (`src/type/setvar.f90:156`), so every displacement point is a "half-converged" SCF | high: the Hessian eigenvalues (especially low/imaginary frequencies) drift with `sccacc`/`step`/restart; PRFO's λ_p/λ_n and mode selection are contaminated; the Bofill update along an IRC path drifts | high | promote `sccacc`/`step` to explicit settings; default to following xtb (0.3/0.005) but provide a tightened level (0.1/0.002); attach `sccacc` and `step` metadata to the Hessian output for reproduction; experiment #2 | `test_landscape_vib.f90` (experiment #2), `test_landscape_saddle.f90` (experiment #4) |
| **R-02** | **SCF repeatability unknown**: upstream issue #1378 reports that "restart information is used implicitly", so two gradients of the same geometry differ (R04 §79) | very high: the symmetry of the finite-difference Hessian, the trust-region `rho` criterion and the IRC step control all rely on "same geometry, same gradient" | high | the engine defaults to `p_restart_off` (resetting from `wfn_ref` before every E+G, §5.1); the three restart modes are explicitly selectable and printed; an `n_scf_fail` counter; experiment #1 quantifies it | `test_landscape_engine.f90` (experiment #1, required in M0) |
| **R-03** | **`wp => sp` single precision**: `sdavid2`/`solver_sdavidson` of `src/david2.f90:25,221` are single precision | medium: if RFO/PRFO use Davidson for the lowest eigenpair, `b_k`/`F_k` lack precision → the shift solution jitters | medium | M0/M1 do **not** use Davidson: RFO uses `lapack_syev` (`src/mctc/lapack.f90:19`) for a full diagonalisation (acceptable for small systems n≤500); only after M4 is Davidson introduced for large systems, and it must have a "dp full diagonalisation vs sp Davidson" cross-check | `test_landscape_optimize.f90` (RFO accuracy), `test_landscape_saddle.f90` (large-system cross-check, M4) |
| **R-04** | **The finite barrier of `constrain_pot`**: the constraint is a soft spring potential (`src/constrain_pot.f90:313`; `springexpo=2.0`, `src/scanparam.f90:36`; the default `fcconstr`) | medium: the quantitative barrier of TS/scan depends on the spring stiffness; too little stiffness → the constrained coordinate drifts; too much → the condition number worsens | medium | expose `constraint_fc`, `spring_expo` explicitly in scan/TS; **report the constraint residual** `\|∂E/∂q − λ\|` at every scan point (engineering recommendation (c) of R04 §4); for the TS constraint use "a Cartesian step projection + Hessian projection" instead of a spring potential (`saddle/eigenfollow.f90` uses `projectHessian`/`trproj`) | `test_landscape_scan.f90` (experiment #11), `test_landscape_saddle.f90` |
| **R-05** | **`runtyp` number clash**: the `p_run_*` numbers are non-contiguous (`src/setparam.f90:197-215`, including 71 and 100–104), and the same file has `p_ext_*` occupying 13–18 | medium: taking a wrong value → silently entering the wrong branch | low | grep-confirmed: `p_run_*` uses {1..8,10,11,13,14,15,71,100..104}, **9 and 12 are free**; `p_ext_*` occupies {13..18}. This plan takes `p_run_lopt=9`, `p_run_lscan=12`, `p_run_lts=19`, `p_run_lirc=20` (19/20 are free in the `p_run_*` namespace and do not clash with `p_ext_*`); the CLI only adds `--l*` prefix flags and changes no existing branch | the current all-green `test/unit` + the `--lopt` e2e; review the grep result in code review (§12.1) |
| **R-06** | **A history of mixed units**: xtb internally already mixes Å/Eh-Å (R05 §3.8.4; so does MAPLE, R03 §C.5) | high: one missing conversion amplifies the error by a factor of 1.89, with no error raised | medium | N8/N9: a.u. throughout internally, explicit conversion at the boundary; `coords/cartesian.f90` is the only place doing mass weighting/flattening; every settings field states its unit at the type definition; audit the units point by point for reused old routines (`relaxed_scan`, `geometry_optimization`, `numhess`) | `test_landscape_settings.f90` (unit-conversion round trip), `test_landscape_scan.f90` (aligned with the existing `xtbscan.log`) |
| **R-07** | gradient noise σ_g makes the four criteria unreachable | high: the TS/IRC iteration count explodes or falsely converges | medium | experiment #4 quantifies σ_g, requiring `f_rms ≥ 10σ_g`; drop to `loose` when `normal` is unreachable; `stagnate_patience` detects stagnation | `test_landscape_engine.f90` (σ_g), `test_landscape_saddle.f90` |
| **R-08** | row/column-major order and flattening-order errors | high: silently wrong results (the energy is right but the gradient is misaligned) | medium | N4: enforce `xyz(3,n)`; `coords/cartesian.f90` provides the single `pack/unpack` pair; a LEPS analytic-gradient unit test can expose misalignment immediately | `test_landscape_optimize.f90` (component-by-component comparison of the analytic gradient) |
| **R-09** | mode-tracking sign flip → mode hopping | high: the TS search diverges to a minimum | medium | `argmax\|overlap\| + sign realign` (PRFO.py:634-672); a `mode_overlap_min=0.3` guard + a warning | `test_landscape_saddle.f90` (a mode-continuity assertion on Müller–Brown) |
| **R-10** | ambiguity in the definition of Dimer separation (R04 Contradictions #1) | medium: the curvature C differs by 2–4× and the convergence behaviour differs | medium | document **explicitly** that the "midpoint→image" definition is taken; `delta` explicitly adjustable; port the VASP diagnostic rule (torque not decreasing ⇒ increase delta or tighten the SCF) as a runtime warning | `test_landscape_saddle.f90` (dimer branch) |
| **R-11** | contradiction about the NEB spring constant (R04 Contradictions #2: k can vary by orders of magnitude vs too large hinders convergence) | medium | medium | distinguish "insensitive to the equilibrium position" from "sensitive to the convergence rate": `k_min/k_max` are provided, `use_dynamic_k=.true.` by default. **[closed in M5]** experiment #8 (report 37 §3.2): the dynamic `1e-2/1e-1` converges, the static `1e-2/1e-1` in the window does not → the calibration target is the schedule; the upper bound that the static value `k=1e2` does not converge is falsifiable | `test_landscape_path.f90` (`band-spring-schedule`, `neb-spring-calibration`) |
| **R-12** | LQA lineage ambiguity (R04 Contradictions #3: Page–McIver vs Sun–Ruedenberg QSD) | medium: implementing a different algorithm without being aware of it | medium | **state explicitly in the header comment of `irc/lqa.f90` which branch is taken** (this plan takes the Page–McIver LQA analytic propagation cited by the HPC/EulerPC paper, consistent with R04 §12), and record the QSD difference in the documentation | `test_landscape_irc.f90` (experiment #6, cross-checked against GS) |
| **R-13** | the units of some MAPLE thresholds/spring constants are unlabelled (`k_min/k_max`, `grow_relax_tol`) | medium: the defaults may be off by 1.9–3.6× | medium | all are marked `[to be calibrated]`; inferred from MAPLE's energy/length units (Ha/Å) with the conversion basis given. **[closed in M5]** experiment #8 (report 37 §3): the 1.9–3.6× uncertainty in `k_min/k_max` **does not change the convergence** on either LEPS or NH3 (both the dynamic PLAN initial value and the calibrated value converge), so an indefinite value is not blocking; the unit error of `climb_switch_rms` (3.57×) was corrected with a definite value. `grow_relax_tol` (= `string_grow_tol`) is kept at 5e-3 by the string measurements of reports 36/37 | `test_landscape_path.f90` |
| **R-14** | all MAPLE fixtures are based on ML potentials (R03 §D), so they cannot serve as a GFN2 numerical benchmark | high: misuse would cause a "false pass" | high | L1 uses analytic potentials (Müller–Brown/LEPS/CO₂) for quantitative validation; MAPLE's output is used only for a **topology/geometry consistency** spot check, never a bitwise comparison | `test_landscape_*.f90` (the L1 layer) |
| **R-15** | licence: the **code** of pysisyphus (GPL-3.0) and geomeTRIC (non-standard) cannot be merged into xtb (LGPL-3.0-or-later); DL-FIND/sella are LGPL-3.0 (R04 §76, R05 §1.1) | high (legal) | low | **use the literature and the Python implementations only as algorithm references, do not carry over any code**; DL-FIND only informs the design (R05 §1.1.2); from M0, register "the algorithm is from the literature, no third-party code is copied" in the header of `landscape_api.f90` | code review (manual) |
| **R-16** | **meson/ninja are not installed** on this machine (`meson: command not found`), so `meson.build` cannot be verified | medium: the Meson path may carry an error into the trunk | high | `src/landscape/meson.build` strictly copies the structure of `src/freq/meson.build` (`srcs += files(...)`), checked line by line; verify it later in CI/an environment with meson; the CMake path **must** be really verified on this machine | CI (external); local `cmake` build |
| **R-17** | under cmake 4.3.2 the cpcmx and toml-f targets clash by name and the configure fails | medium: blocks build verification | high | always pass `-DWITH_CPCMX=OFF` explicitly (the option at `cmake/CMakeLists.txt:20` defaults TRUE); fix the build directory at `/tmp/...`, no `build/` may appear in the repository | the `cmake` configure command itself |
| **R-18** | the copy semantics of `TRestart` and the performance cost of `p_restart_off` | medium: deep-copying `wfn` at every E+G may slow things down significantly (O(n²) for large systems) | medium | `wfn_ref` is copied only at construction/`engine_pin_state`; the cost of each `copy` inside E+G is negligible compared with the SCF (the SCF is O(n³)), yet `p_restart_warm` is still provided for opt/NEB; `landscape_cost_report.wall_seconds` records the cost | `test_landscape_engine.f90` (timing comparison, optional in M0) |
| **R-19** | B-PRFO terminology ambiguity (consequence of D2) | low: the implementation may differ from the repository owner's expectation | medium | already implemented as the "RS-P-RFO monomolecular version" and stated in the documentation; the replacement cost is limited to the single file `saddle/bprfo.f90` | `test_landscape_saddle.f90` (bprfo branch) |

---

## 11. Things explicitly not done (the D2 exclusion list)

| Not done | Reason (evidence) |
|---|---|
| **DMF (Direct MaxFlux)** | the only module that really needs an external numerical library: `ts/algorithm/dmf.py:23` `import cyipopt`, `:1058 class VariationalPathOpt(cyipopt.Problem)`, plus scipy `BSpline/interp1d/Rotation` (`:30-32`) and 19 `einsum/tensordot/matmul` sites (a very high column-major translation risk). R03 §E.2 judges it "not recommended for porting", R04 §55 judges it "an optional item for phase two". **Note**: DMF itself needs no Hessian and does not rely on a neural-network potential (R04 §53), so the exclusion is decided purely by **dependency and translation cost**, unrelated to GFN2 capability |
| **the batch GPU version of blbfgs / BPRFO** | centred on `(B, n)` torch tensors (`blbfgs.py:220-289`, `BPRFO.py:366-415`), it would need restructuring into `(n,B)` column-major + BLAS-3 batched (R03 §B.1/B.3). Moreover both are **dead code** in MAPLE (not referenced by the dispatcher, R01 §3.1/§3.3). D2 requires only the monomolecular version of B-PRFO |
| **ML-potential calculators** (ANI/MACE/UMA/AIMNet2/Fennol) | they belong to the Python ecosystem (the whole table of R01 §5.3); xtb's engine boundary is already `class(TCalculator)` (`src/type/calculator.f90:43`), and an ML potential should be attached as an external `extern` calculator, not built in (R05 §3.7) |
| **parmfit (NCAA/TorsionFit/ChargeFit/MetalAA/QMInterface)** | a parameter-development tool chain orthogonal to "PES task execution"; it also needs to call Gaussian/ORCA external QM (R01 §2.9, R03 §A.3). Recommended as a separate project (R05 §3.7) |
| **MD ensembles (NVE/NVT/NPT, thermostat/barostat/integrator)** | xtb already has a separate `md`/`omd` (`src/mdoptim.f90`, the md dispatch at `prog/main.F90:1153`), so a duplicate implementation yields nothing (R05 §3.7). This plan contains no time-scale dynamics |
| **torch / GPU tensor backend** | clashes with D1 "introduce no new dependency"; every core algorithm is implementable in pure Fortran (the conclusion of R03 §A.5) |
| **PBC / unit-cell optimisation** | needs an extra contract for stress/`sigma` and the lattice gradient (`src/lbfgs_anc/driver.f90:39 relax_pbc`, `:336,:409 num_grad/num_sigma`). Every task of this plan works when `mol%npbc == 0`; `npbc > 0` → `env%error("landscape tasks do not support PBC yet")` and return (**no silent degradation**) |
| **internal coordinates (DLC/HDLC/redundant) as the step space of TS/IRC** | R05 §3.1 keeps `coords/internal.f90` and `coords/transform.f90` for scan and Hessian transformations, but the TS/IRC step computation is fixed to mass-weighted Cartesian (consistent with MAPLE/ORCA IRC: `Follow_CoordType cartesian`, R04 §66). Reason: the orbital-free projection/overlap criterion is most stable in Cartesian, whereas internal coordinates would introduce extra Jacobian error |
| **the metadynamics bootstrapping path of `bias_path`, `modefollow`, `intmodes` Z-matrix** | different goals from standard NEB/GSM/PRFO; `intmodes` has been superseded by `internals/*`+`bmatrix` (R05 §3.7). These three existing features **stay untouched**, the new suite simply does not depend on them |
| **global optimisation / GA / random search / conical intersection (MECI)** | provided by DL-FIND but outside the D2 scope of sp/opt/scan/ts/hessian/freq/irc (R05 §1.1.2) |
| **rewriting the thermochemistry (RRHO) and the frequency printing** | xtb is already complete (`src/main/property.F90:695`, `src/thermo.f90:79`); this suite only wraps them and exposes parameters (§5.3.8) |

---

## 12. Integration points

> **This section describes the implementation that has landed** (M0+M1 fix round, code is authoritative). The parts of each subsection marked "implemented"
> correspond line by line to the code; unimplemented milestone items remain as planning. The differences from the initial plan are gathered in §12.8.

### 12.1 `set_runtyp` new constant values (grep-confirmed to have no clash) [implemented]

The measured commands and results:

```bash
grep -n "p_run_" src/setparam.f90          # 197-215: uses {1..8,10,11,13,14,15,71,100..104}
grep -n "p_ext_" src/setparam.f90          # 193-195: uses {13..18}
grep -rn "set%mode_extrun = p_ext_" src/set_module.f90   # :958,:978 -- p_ext_* belongs to set%mode_extrun
```

Conclusion: in the `p_run_*` namespace, **9 and 12 are free**; `p_ext_*` occupies 13–18.
The following are therefore taken (and guaranteed not to overlap the `p_ext_*` values, to avoid misreading):

| Constant | Value | Milestone | Use | Status |
|---|---|---|---|---|
| `p_run_lopt` | 9 | **M0/M1** | the new minimisation suite (`--lopt`) | ✅ implemented in `src/setparam.f90` (after `p_run_omd = 8`) |
| `p_run_lscan` | 12 | **M2** | scan (`--lscan`) | ✅ implemented in `src/setparam.f90` (after `p_run_screen = 11`) |
| `p_run_lts` | 19 | **M4** | transition state (`--lts`) | ✅ implemented in `src/setparam.f90` (after `p_run_metaopt = 15`) |
| `p_run_lirc` | 20 | **M6** | IRC (`--lirc`) | ✅ implemented in `src/setparam.f90` (after `p_run_lts = 19`) |

If the repository owner prefers "not reusing low numbers", the fallback is to take 105–108 (the current `p_run_*` maximum is 104);
both schemes were confirmed to clash with no existing value, and **this round's implementation takes `p_run_lopt = 9`**.

If the repository owner prefers "not reusing low numbers", the fallback is to take 105–108 (the current `p_run_*` maximum is 104);
both schemes were confirmed to clash with no existing value, and **the M0 implementation takes 9/12/19/20**.

Placement: 4 lines appended after the `p_run_*` block of `src/setparam.f90` (`src/setparam.f90:197-215`).

### 12.2 `src/set_module.f90`: `set_runtyp` [implemented]

In the `select case(typ)` of `subroutine set_runtyp` (`src/set_module.f90:1031`), append:

```fortran
   case('lopt')          ! implemented (M0/M1)
      set%runtyp = p_run_lopt

   case('lscan'); set%runtyp = p_run_lscan    ! M2
   case('lts');   set%runtyp = p_run_lts      ! M4
   case('lirc');  set%runtyp = p_run_lirc     ! M6
```

(Only `lopt` is added this round; the rest are appended in the corresponding milestones.)

### 12.3 `src/prog/main.F90` [implemented]

**(a) runtyp dispatch**: the main dispatch area (after the `anyopt` block, before VIP/VEA) gains
(the following is the **actual** code of `src/prog/main.F90:928-961`, checked against this section in the M2 review round):

```fortran
      ! landscape suite (minimisation with the algorithms of src/landscape)
      if (set%runtyp == p_run_lopt) then
         lset%engine%acc = set%acc          ! the CLI's --acc synchronised into the engine control object
         call start_timing(3)
         call run_landscape(env, mol, chk, calc, lset, lres)
         call stop_timing(3)
         ! write-back: the TOTAL ENERGY line/xtbout.json read res, the geometry is written by the task layer
         res%e_total = lres%energy
         res%gnorm   = lres%gnorm
         call env%checkpoint("Landscape task terminated")
      end if

      ! landscape suite (scan with the algorithms of src/landscape)
      if (set%runtyp == p_run_lscan) then
         lsset%engine%acc = set%acc
         call start_timing(3)
         call run_landscape(env, mol, chk, calc, lsset, lres)
         call stop_timing(3)
         res%e_total = lres%energy          ! the de-biased energy of the lowest scan point
         res%gnorm   = lres%gnorm
         call env%checkpoint("Landscape task terminated")
      end if
```

Both `%engine%acc = set%acc` are necessary: although `xtb_single::singlepoint` accepts the `acc` argument it **discards**
it, and only `calc%accuracy` really takes effect (`docs/_landscape-recon/12-*.md` R2-02). Likewise
`engine%maxiter` is **not** passed to SCC (`singlepoint` forwards only `printlevel`/`restart`),
and to limit the SCF iteration count one must set `calc%maxiter` (the unit test `scan-task-no-energy` uses exactly this method).

Here `lset` (`landscape_opt_settings`)/`lsset` (`landscape_scan_settings`)/`lres`
(`landscape_result`) are added in the declaration area of `xtbMain` and brought in through new `use` statements
(`use xtb_landscape, only : run_landscape`;
`use xtb_landscape_settings, only : landscape_opt_settings, landscape_scan_settings, …`;
`use xtb_landscape_results, only : landscape_result`).
`lset`/`lsset` are filled by `parseArguments` (a new `intent(inout)` argument), with no xcontrol handler needed (§12.4).
In addition `p_run_lopt`/`p_run_lscan` must be added to the `select case (set%runtyp)` list of the parameter-file selection block,
and `prtiming(3, 'landscape optimizer')` must be added in `finalize_xtb`.

**(b) CLI flags**: the main flag loop's `select case(flag)` (`src/prog/main.F90:1378-2070`,
`case ('-o', '--opt')` at `:1950`, `--hess` at `:1957`, `--path` at `:2004`, `--modef` at `:2018`)
has gained:

| New flag | Behaviour | Status |
|---|---|---|
| `--lopt` | `set_runtyp('lopt')`, consuming no positional argument (to avoid eating the geometry file name); the algorithm/convergence level use the next two flags | ✅ **implemented** |
| `--lopt-engine <sd\|cg\|lbfgs\|bfgs\|diis\|rfo>` | sets `lset%algorithm` (`landscape_opt_algorithm_from_name`); an unrecognised name → `env%error` and terminate (exit 1) | ✅ **implemented** |
| `--lopt-level <superloose\|loose\|normal\|tight\|vtight>` | `lset%set_conv_level`; an unrecognised level name → `env%error` | ✅ **implemented** |
| `--lopt-hessian <numerical\|model>` | sets `lset%hessian_source` (validated by `landscape_hessian_source_known`); `model` = the Lindh-D2 model Hessian, used as the BFGS initial Hessian and the RFO trust-region Hessian; an unrecognised name → `env%error` | ✅ **implemented in the M2 review round** (R2-09 leftover) |
| `--lscan` | `set_runtyp('lscan')`, consuming no positional argument; every scan parameter goes through `--lscan-*` | ✅ **implemented in M2** (see §12.10) |
| `--lts` / `--lirc` / `--ljson` | `--lts` (M4), `--lirc` (M6 phase one), `--ljson` (M7) are **all implemented** | ✅ `--lirc` see §12.14; ✅ `--ljson` see §12.16 (backfilled in this round's fix round: this line used to say "`--ljson` not implemented") |

**Differences from the initial plan**: `--lopt` does **not** accept a positional argument (the original plan was `--lopt [level]`). Reason:
`TArgParser%nextArg` has no peek, so an unconditional consumption would make `xtb --lopt water.xyz` eat the file name as the level;
using a separate flag removes the ambiguity. `--lopt-engine`/`--lopt-level` can also be used on their own (they set `runtyp=lopt` automatically).

**Reason**: everything uses the `--l*` prefix, with **zero clash** with existing flags (`--license`, `--lmo` are different strings,
and Fortran's `select case` matches exactly). The behaviour of `--opt`/`--hess` is **completely unchanged** (regression tests in §12.9).

### 12.4 xcontrol (optional, from M2)

`src/constrain_param.f90` already has a handler registration mechanism (`set_scan` at `:844`, `set_hess` at `:1229`).
From M2, `set_landscape(env, key, val, ...)` is registered, supporting:

```
$landscape
   convlevel=normal
   hessian=numerical
   engine=rf|lbfgs      ! info purpose only
   restart=off|pin|warm
$end
```

M0 does **not** add an xcontrol handler (to reduce the surface of changes to existing files); configuration first goes entirely through the CLI.

### 12.5 Build registration

**CMake** (`src/CMakeLists.txt`):
1. Insert `add_subdirectory("landscape")` (i.e. the new line 29) after `add_subdirectory("iff")` (`src/CMakeLists.txt:28`) and before
   `add_subdirectory("main")` (`:29`).
2. Add no top-level `list(APPEND srcs ...)` at all (it is returned by `src/landscape/CMakeLists.txt`'s
   `set(srcs ${srcs} PARENT_SCOPE)`; the pattern is in `src/freq/CMakeLists.txt:18-26`).
   When implementing, **copy the structure of `src/freq/CMakeLists.txt` line by line** (`set(dir ...)` → `list(APPEND srcs ...)` →
   `set(srcs ${srcs} PARENT_SCOPE)`), making no "improvement", because the `freq` spelling has proved to work in this repository.
3. The content structure of `src/landscape/CMakeLists.txt`: `set(dir "${CMAKE_CURRENT_SOURCE_DIR}")` +
   `list(APPEND srcs "${dir}/landscape_api.f90" ... "${dir}/vib/thermo.f90")` +
   `set(srcs ${srcs} PARENT_SCOPE)` (with the copyright header, consistent with `src/freq/CMakeLists.txt:1-16`).

**Meson** (`src/meson.build`):
1. Insert `subdir('landscape')` after `subdir('iff')` (`src/meson.build:28`) and before `subdir('main')` (`:29`).
2. `src/landscape/meson.build`: `srcs += files('landscape_api.f90', 'types/settings.f90', ...)`
   (the structure copied from `src/freq/meson.build:18-22`). **No meson on this machine, cannot be verified (R-16)**.

### 12.6 Test registration [implemented]

| File | Change | Status |
|---|---|---|
| `test/unit/CMakeLists.txt` | `tests` list gains `landscape-api`, `landscape-settings`, `landscape-coords`, `landscape-hessian-update`, `landscape-hessian`, `landscape-cg`, `landscape-optimize-math`, `landscape-optimize-xtb` | ✅ implemented |
| `test/unit/main.f90` | the corresponding 8 `use test_landscape_<area>` and `new_testsuite(...)` entries | ✅ implemented |
| `test/unit/meson.build` | `tests` list kept in step (cannot be verified on this machine, R-16) | ✅ implemented |

In addition, a **CLI-level end-to-end regression** is also registered in `test/unit/CMakeLists.txt` (the existing style is at the end of the file,
for example `add_test("xtb/Singlepoint" ${XTB-EXE} --coffee --strict --norestart --namespace test1)`):

```cmake
# The geometry file is generated in the build directory (the repository stays free of test data),
# a small CMake script checks the exit code, the convergence flag and the output files together.
add_test("xtb/landscape-opt" ${CMAKE_COMMAND} -DEXE=... -DINPUT=... -DRUNDIR=...
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_check.cmake")
```

The command actually run is
`xtb <landscape_h2o.xyz> --gfn 2 --lopt --lopt-engine lbfgs --lopt-level normal --norestart --namespace landscape1`,
and the script asserts: (i) exit code 0; (ii) stdout contains `landscape: converged`; (iii) `landscape1.xtbopt.xyz` and
`landscape1.xtb.trj` exist and are non-empty (the geometry and the trajectory follow `--namespace` like the other outputs; without `--namespace`
they are still `xtbopt.xyz` / `xtb.trj`. This convention was originally missed by `types/log.f90` and fixed in the final round, report 53 §N-1, which added
`xtb/landscape-opt-namespace`). On the meson side `run_command(python, '-c', ...)` generates the same geometry in the build directory
(meson always has Python, see the root `meson.build`) and registers a test of the same name.
(The `--coffee` version of the original plan was abandoned: caffeine's 72 degrees of freedom are too slow for an untuned L-BFGS.)

M2/M4/M6 append `--lscan` / `--lts` / `--lirc` isomorphically (each with its own `--namespace`).
This repository has **no** `test/cli/` directory, so the CLI-level regressions are registered in `test/unit/CMakeLists.txt` just like the unit tests.

**Note**: `test/unit/CMakeLists.txt` uses `string(MAKE_C_IDENTIFIER ...)` to turn
`landscape-hessian` into an identifier and then concatenates `test_${t}.f90` → the file name must be `test_landscape_hessian.f90`
(the hyphen `-` maps to an underscore, consistent with the existing `model-hessian` → `test_model_hessian.f90`).

### 12.7 Existing files actually changed this round (M0+M1)

| File | Change | Lines (git diff) |
|---|---|---|
| `src/CMakeLists.txt` | +1 line `add_subdirectory("landscape")` | +1 |
| `src/meson.build` | +1 line `subdir('landscape')` | +1 |
| `src/setparam.f90` | +1 line `p_run_lopt = 9` | +1 |
| `src/set_module.f90` | +3 lines (`case('lopt')` and the assignment) | +3 |
| `src/prog/main.F90` | +5 `use` lines, +2 declaration lines, +8 dispatch-block lines, +3 flag branches ~45 lines, `parseArguments` 2 parameter lines, +3 `prtiming` lines | see `git diff --stat` |
| `test/unit/CMakeLists.txt` | `tests` list +3 items + CLI smoke test (~50 lines) | see `git diff --stat` |
| `test/unit/main.f90` | +3 `use`s and 3 `new_testsuite`s | +6 |
| `test/unit/meson.build` | `tests` list +3 items + meson CLI smoke (~15 lines) | see `git diff --stat` |

**Every other existing file is left untouched.** `src/optimizer.f90` is not modified (the `set%tsopt` semantics are unchanged),
nor `src/hessian.F90`, nor `src/type/calculator.f90`, and **`src/xhelp.f90` is not modified**
(so `xtb --help` does not yet list `--lopt*`, see §12.8 D7).

### 12.8 Differences of the implementation from the initial plan (code is authoritative)

| Number | Difference | Reason / evidence |
|---|---|---|
| **D1** | `types/conv.f90` is not created separately: the four criteria live in `types/settings.f90` (`landscape_settings_is_converged`, `landscape_convergence_measures`) and the convergence report in `types/results.f90` (`landscape_convergence_report`). Likewise `test_landscape_conv.f90`/`test_landscape_engine.f90` are merged into `test_landscape_settings.f90`/`test_landscape_optimize_math.f90` + `test_landscape_optimize_xtb.f90` respectively | avoids creating a module for a ~30-line criterion, and avoids storing the same concept (the convergence report) twice in two modules (PLAN §11 "no dead code"); the test-case names correspond one-to-one (`convergence-boundary`/`convergence-measures`/`engine-cache`/`engine-hvp`/`gfn2-singlepoint-determinism`) |
| **D2** | the numerical provider **builds its own central differences** (`landscape_numerical_hessian_provider`, calling `TCalculator%singlepoint` displacement by displacement), and does **not** forward to `TCalculator%hessian`; `odlr=.true.` → `env%error` | a hard requirement of `07-*.md` §4.3: the `step`/`sccacc` of the `$hess` control block silently stop working on the non-`--copy` path, so it must carry its own step/SCF accuracy. Measured: point by point it differs from `TCalculator%hessian` by < 1e-8 at the same step/acc (`test_landscape_hessian.f90::numerical-vs-calculator`) |
| **D3** | the provider types are named `landscape_hessian_provider` / `landscape_numerical_hessian_provider` / `landscape_model_hessian_provider` (PLAN §5.2 writes `landscape_hessian_numerical`); `hessian_source` is in the task settings base class (`landscape_settings%hessian_source`), **not** in `landscape_engine_control` | the naming is unified as "the form in the name"; `hessian_source` is task-level configuration (PLAN §5.3.2 also puts it in `TDriverSettings`), and the engine holds only the already-selected provider (`engine%hp`), avoiding two sources of truth. An unrecognised value → `new_landscape_hessian_provider` errors and does not return a provider |
| **D4** | `landscape_model_hessian_provider` is **already filled in in M1**: it implements the Lindh-D2 construction (reusing `src/model_hessian/lindh.f90`) and injects it as the RFO/BFGS initial guess | the original plan put the body in M3; the fix round (R2/D3) judged "the D3 wording requires a model initial guess" to be a real gap, so it was brought forward to M1. The `swart`/`eeq`/`file` variants still await a later milestone |
| **D5** | CG uses PRP+ (`beta = max(0, beta_PR)`, Nocedal & Wright Alg. 5.4) + a restart on a non-descent direction; it does **not** use the Powell alignment restart (`|g_k.g_{k-1}|/|g_k|^2 >= 0.2`), so the settings have no `cg_restart_threshold` | the Powell alignment criterion presupposes a line search with a curvature condition; this suite has only an Armijo fallback (PLAN §5.3.4), and the criterion was measured to degrade CG into SD (GFN2 water: the CG trajectory is **bit-identical** to SD), and on a 4-dimensional strongly convex quadratic the step count goes from 190 to 337 (i.e. it gets worse) (`test_landscape_cg.f90`) |
| **D6** | `tasks/opt.f90` raises `env%error` (exit≠0) when it **does not converge**; the `landscape_optimize_model` kernel still only returns `result%converged` | consistent with the existing ANCopt failure behaviour, and lets the CLI smoke test really assert "converged" |
| **D7** | `xtb --help` does not list `--lopt*` | `src/xhelp.f90` is not in this round's set of files allowed to change; the next round is advised to add it in the `help` table (referring to the `--opt` entry, `src/xhelp.f90:270`) |
| **D8** | the CLI-level smoke test uses a **water molecule** (its geometry generated in the build directory) rather than `--coffee` | caffeine (72 degrees of freedom) far exceeds the test time budget on an untuned L-BFGS; the water molecule converges in 5 steps |

### 12.9 This round's acceptance evidence (really executed)

```
$ cmake --build /tmp/xtb-land/build -j
[100%] Built target xtb-tester / xtb-exe ...

$ ctest --test-dir /tmp/xtb-land/build --output-on-failure -R landscape
1/9  xtb/landscape-api ............... Passed
2/9  xtb/landscape-settings .......... Passed
3/9  xtb/landscape-coords ............ Passed
4/9  xtb/landscape-hessian-update .... Passed
5/9  xtb/landscape-optimize-math ..... Passed
6/9  xtb/landscape-cg ................ Passed
7/9  xtb/landscape-hessian ........... Passed
8/9  xtb/landscape-optimize-xtb ...... Passed
9/9  xtb/landscape-opt ............... Passed  (CLI smoke test: exit code 0 + converged flag + output files)
100% tests passed, 0 tests failed out of 9

$ /tmp/xtb-land/build/xtb /tmp/dt.xyz --gfn2 --lopt --lopt-engine lbfgs --lopt-level normal
gradient threshold (max):    3.000000E-04 Eh/bohr
restart policy:           off
Hessian source:           numerical
      1      -5.070432957755 ...   1
      2      -5.070540211546 ...
      3      -5.070543386304 ...
      4      -5.070544355967 ...
      5      -5.070544447778      -0.0001  5.877463E-06
landscape: converged
criteria (gmax,grms,dmax,drms):  T T T T
wrote xtbopt.xyz
wrote xtb.trj
landscape task terminated: converged
# exit code 0
```

The remaining algorithms (the same water molecule, `--lopt-level normal`): `sd` 20 steps, `cg` 20 steps, `bfgs` 4 steps,
`diis` 12 steps, `rfo` (`--lopt-level loose`, own FD Hessian) 2 steps, all exit 0.

---

### 12.10 M2 (scan) actual CLI wiring

`--lscan` is isomorphic to `--lopt`: the flag itself consumes no positional argument, and all parameters use separate
`--lscan-*` flags. Every name was measured to exist in the `select case(flag)` of `src/prog/main.F90`,
and `xtb --help | grep lscan` has output (`src/xhelp.f90`).

| flag | Semantics | Corresponding settings field |
|---|---|---|
| `--lscan` | selects `p_run_lscan` (runtyp 12) | — |
| `--lscan-coord <distance\|angle\|dihedral>` | the type of the 1st scan coordinate | `coord(1)%ctype` |
| `--lscan-atoms <i[,j[,k[,l]]]>` | the 1-based atom indices of the 1st coordinate (comma/space separated) | `coord(1)%atoms(1:4)` |
| `--lscan-step <x>` | the step of the 1st coordinate, **Å (distance)/degrees (angle, dihedral)**, uniformly converted to a.u. at the end of parsing | `coord(1)%step` |
| `--lscan-nstep <n>` | the number of steps of the 1st coordinate (must be ≥ 1) | `coord(1)%nstep` |
| `--lscan-coord2` / `--lscan-atoms2` / `--lscan-step2` / `--lscan-nstep2` | as above, the 2nd coordinate; **the appearance of any one sets `ndim = 2`** (a Cartesian-product grid) | `coord(2)%*`, `ndim` |
| `--lscan-ndim <1\|2>` | set the dimension explicitly | `ndim` |
| `--lscan-mode <relaxed\|rigid>` | relaxed / rigid | `mode` |
| `--lscan-method <sd\|cg\|lbfgs\|bfgs\|diis\|rfo>` | the inner minimisation algorithm | `method` |
| `--lscan-level <superloose\|loose\|normal\|tight\|vtight>` | the inner convergence level | `g_max/g_rms/d_max/d_rms` |
| `--lscan-restart <off\|pin\|warm>` | the wavefunction policy (**not** a geometry hot start) | `engine%restart_mode` |
| `--lscan-oneway` | scan forward only (disables the reverse branch and the hysteresis report) | `bidirectional = .false.` |
| `--lscan-cold-start` | start every point from the input geometry (disables the geometry hot start) | `warm_start = .false.` |
| `--lscan-fc <hartree/bohr^2>` | the constraint-force constant | `constraint_fc` |
| `--lscan-expo <x>` | the constraint-potential exponent | `spring_expo` |

**Where the unit conversion happens**: `--lscan-step` is converted uniformly according to the finally determined
`ctype` after the flag loop ends (at the end of `parseArguments`) (Å→bohr with `aatoau`, degrees→rad with `pi/180`), so the order of
`--lscan-coord` and `--lscan-step` does not affect the result. The settings use a.u. throughout.

**Output**: `xtbscan.log` (affected by `--namespace`, consistent with the existing `src/scan_driver.f90:98,129`;
each frame = geometry + the de-biased energy `energy = Etot − Efix`; **a point whose energy is discarded is not written as a frame**,
see §5.5), stdout prints a per-point table (**requested value / reached value / drift** / de-biased energy / constraint residual /
inner step count / convergence flag; a point without energy is `NaN` + `F`), the hysteresis report and the position of the largest jump.

`landscape_scan` writes to disk and reports for every scan point; `result%energy` = the de-biased energy of the lowest point,
`result%gnorm` = the constraint residual at that point, and `mol%xyz` is written back as the lowest-point geometry (so `main.F90`
prints the lowest point rather than the initial geometry).

### 12.11 M3 (vib) actual wiring and deviations

**Measured runtyp values**: the value set of `grep -n "p_run_" src/setparam.f90` is
`{1..15, 71, 100..104}` (`p_ext_*` occupies 13–18, belonging to `set%mode_extrun`, which has different
semantics from `p_run_*` but does not overlap, to avoid misreading). 19/20 stay reserved for `--lts`/`--lirc` (§12.1),
so M3 takes **21**:

| Constant | Value | Milestone | Use | Status |
|---|---|---|---|---|
| `p_run_lvib` | 21 | **M3** | frequency/thermochemistry (`--lvib`) | ✅ implemented in `src/setparam.f90` (after `p_run_metaopt`) |

**New CLI flags** (the `select case(flag)` of `src/prog/main.F90`, with `src/xhelp.f90` kept in step):

| flag | Semantics | Corresponding settings field |
|---|---|---|
| `--lvib` | selects `p_run_lvib`, does not consume the positional argument | — |
| `--lvib-hessian <numerical\|model\|file>` | Hessian backend | `hessian_source` |
| `--lvib-hessian-file <name>` | the file read by the `file` source (TURBOMOLE layout) | `hessian_file` |
| `--lvib-step <bohr>` | the numerical-Hessian difference step | `engine%hess_step` |
| `--lvib-sccacc <acc>` | the SCC accuracy of the difference points | `engine%hess_acc` |
| `--lvib-odlr` | requests ODLR (**not implemented, explicit error**) | `engine%odlr` |
| `--lvib-no-project` | no translation/rotation projection | `project_tr = .false.` |
| `--lvib-temp <K>` | thermochemistry table temperature (single value) | `temperature(1)`, `n_temperature` |
| `--lvib-rotor-cutoff <cm^-1>` | quasi-RRHO rotor cutoff | `rotor_cutoff` |
| `--lvib-imag-cutoff <cm^-1>` | imaginary-frequency cutoff (must carry a minus sign; `-20` contains no letter, so `TArgParser` treats it as an argument rather than a flag) | `imag_cutoff` |
| `--lvib-freq-scal <x>` | thermochemistry frequency scaling | `freq_scal` |

**Also filled in (leftovers of PLAN §9.3)**: `--lopt-hessian-file`, `--lscan-hessian`,
`--lscan-hessian-file` (so the backend of `--lscan-method rfo` and of the inner BFGS initial guess is selectable from the CLI),
`--lscan-max-steps` (M2 leftover M-1).

**Deviations from §5.3.8 (code is authoritative)**:

1. `step`/`sccacc`/`odlr` do not get separate fields; they reuse `landscape_engine_control`'s
   `hess_step`/`hess_acc`/`odlr` (one spelling kept for one concept).
2. `pressure` and `ilowfreq` are **not implemented**: xtb's RRHO has no pressure parameter and no
   `ilowfreq`; `rotor_cutoff` (= `set%thermo_sthr`) is Grimme's free-rotor scheme itself.
   Exposing a field with no consumer is dead code.
3. `linear_tol` defaults to **1.0e-4 bohr²** (`linthr_bohr2` of `src/axis_trafo.f90:31`),
   not the 1e-8 of the plan table: it must match the existing `--hess` `mol%linear` criterion, otherwise
   the 3N−5/3N−6 count would differ from the existing output.
4. `landscape_vib_settings%write_files` controls only the `hessian` and
   `vib_normal_modes` that this suite writes itself; `vibspectrum`, `g98.out` and the thermochemistry table are produced
   unconditionally by the reused `main_freq` (that function has no output switch).
5. `landscape_vib_result` gains `rmass(3n)` (the definition of xtb's `freq_results%rmass`),
   because `g98.out` and `vibspectrum` need a "Red. masses" column.

**The global writes of the thermochemistry**: `vib/thermo.f90` is the only place in the whole suite that writes existing global
state, writing `set%thermotemp/nthermo/thermo_sthr/thermo_ithr/thermo_fscal` (`src/setparam.f90:284-291`)
and `xtb_splitparam::atmass` (amu, which `axis2` reads; `src/prog/main.F90:461`
and `src/prog/thermo.f90:103` do the same). The settings object remains the single source of truth, and the write happens before
calling `main_freq`.

**The projection convention and its relation to `--hess` (measured; updated in fix round 23)**: this suite uses the Eckart projection
(`xtb_freq_project::projectHessian`, i.e. the `xtb thermo` path, PLAN §5.3.8/R04 §71),
while the existing `--hess` uses the legacy `trproj` (a non-mass-weighted space). Both are numerical (central-difference) Hessians,
step 0.005 bohr, SCC accuracy 0.3 (`--hess`'s own stdout prints `| Numerical Hessian |`,
`step length 0.00500`, `SCC accuracy 0.30000`; the `analytical hessian` in the timing table is only
a fixed label of `src/prog/main.F90:2840` and **does not mean an analytic Hessian**). The difference comes **mainly** from the projection:
feeding the **same** raw Hessian through the two projections separately (unit test `water-vs-trproj`, the same matrix):

| Geometry | Eckart | trproj | max‖Δf‖ |
|---|---|---|---|
| GFN2 minimum (`h2o_opt`) | 1539.1480 3644.0560 3652.3753 | 1539.1469 3644.0557 3652.3013 | **0.074** cm⁻¹ |
| strongly distorted water (test geometry) | 1318.0122 3716.0701 4141.5458 | 1318.5519 3706.8595 4128.6366 | **12.91** cm⁻¹ |
| non-stationary water (`h2o_raw`) | 1565.0991 3629.7342 3642.9892 | 1565.0984 3634.9475 3643.6359 | **5.213** cm⁻¹ |

Mechanism: the two projection operators remove the **same** 6-dimensional rigid-body-motion **space**, but they define it in **different metrics** —
`trproj` projects the **non-mass-weighted** Hessian with **unit-mass** translation/rotation vectors (about the unit-mass centre of mass)
(`src/freq/project.f90:151`), whereas Eckart first mass-weights and then projects with mass-weighted rigid-body vectors
(about the mass-weighted centre of mass) (`projectHessian`, `:34`). So at a **stationary point** the two nearly agree
(the null space of the true Hessian coincides with it), and the difference grows with the distance from the stationary point (three measured points: minimum 0.074,
non-stationary 5.213, strongly distorted water 12.91 cm⁻¹; no proportionality test was done, so it is not written as ∝ ‖g‖); `trproj` itself
**contains no gradient term at all** (that statement in the early documentation was wrong).

The same-geometry comparison at the CLI level (`--lvib` vs `--hess`, re-measured this round, consistent with report 21):
**0.0757 (H2O minimum) / 0.9972 (CH3OH minimum) / 0.0036 (CO2) / 5.2109 (non-stationary H2O)**
cm⁻¹. CO2 is a linear molecule and **both paths skip the projection**, so 0.0036 cm⁻¹ is the upper bound of the "non-projected" residual
(the difference between the two numerical-Hessian implementations, `--hess` and the suite; the source is not further attributed, report 23 §8.1);
the projection term at the minimum is 0.0757−0.0036 ≈ 0.072 cm⁻¹. The **single number 5.71 cm⁻¹ is no longer used**
(that number came from a geometry not committed to the repository and is no longer reproducible as of report 21 §5.5).
Linear molecules **skip the projection** following the existing practice and take the lowest 5 eigenvalues as zero modes, so CO2's two paths agree.
Feeding each `hessian` file back into the suite (Eckart) **reproduces itself** to 0.01 cm⁻¹ (reprojecting an already projected
matrix is approximately idempotent), so file-level interoperability is unaffected.

**Electronic-temperature (`etemp`) wiring (fix round 23; P2-B/P1-1 added in round 25)**: `xtb_single::singlepoint`
**discards** the `et` argument passed in (`src/single.f90:52`), and the calculator actually uses its own `etemp` field
(copied once from the global `set%etemp` at construction, `src/xtb/calculator.f90:144`). The engine therefore
writes `landscape_engine_control%etemp` explicitly into the xTB calculator inside
`landscape_engine%set_calculator` (the same mechanism as the existing `acc`), and on the CLI side
`engine%etemp = set%etemp` is synchronised at the three landscape entry points of `main.F90`; `engine_report` **reads back** from the calculator
and prints the effective value, making "the setting did not get in" externally visible. `sp`/`opt`/`scan` call `engine_report` at the end of the task;
`--lvib`'s engine is created and destroyed inside `vib/numhess.f90` and now also calls it before destruction,
so all four tasks' stdout contains the effective `etemp` (the M4 gate of PLAN §9.5 depends on this).
The behaviour is locked by three layers of tests: the unit test `etemp-control` (stretched H₂ 300 K vs 5000 K, locking
"pushed into the calculator") and the CLI test `xtb/landscape-vib-etemp` (`--etemp 300` vs `--etemp 5000`,
asserting the printed value equals the passed value and that `eigval` really changes, locking the `main.F90` synchronisation).

**INFO-1 (the index convention of `vib_normal_modes`)**: `writeNormalModesTurbomole` treats the
**first index of the passed matrix as a Cartesian component** when mass-deweighting, yet prints the **first index as the mode number**,
so in that file **each row is a Cartesian component and only each column (column group) is a mode** (the opposite of the common reading,
`src/io/writer/turbomole.f90:164-188`). A downstream tool reading it as "rows = modes" reaches wrong conclusions.

**INFO-2 (the frequency-constant difference from MAPLE; must not be used as a tight-tolerance reference)**: MAPLE's `2721.1383`
uses the **Hartree/Å² + amu** convention, while xtb's `autorcm = 219474.63067`
(`src/mctc/convert.f90:40`) uses the **Hartree/bohr² + electron mass** convention; the two differ for the same physical frequency
by ~0.04 % (~1.5 cm⁻¹ at 3644 cm⁻¹). A comparison against MAPLE can only compare topology/magnitude (N9),
not 0.01 cm⁻¹.

**INFO-3 (the exit code of an all-unconverged scan; changed in M7, see below)**: the "no converged point"
branch of `tasks/scan.f90` emitted only `env%warning` in M2, so `xtb --lscan-max-steps 0` ended with **exit code 0**
(while TOTAL ENERGY printed NaN). **The M7 close-out round unified it to `env%error` as this note foresaw**:
"an unusable result ⇒ a non-zero exit". The semantics are now

| Scan result | Behaviour | Exit code |
|---|---|---|
| some points fail (no energy) | `env%error` | non-zero |
| **no point at all converges** (the energy stays NaN) | `env%error` (**changed in M7, was warning**) | non-zero |
| some unconverged points but ≥1 converged point | `env%warning`, result usable | 0 |

Locked by three layers of tests: the CLI `xtb/landscape-scan-max-steps` (asserting a non-zero exit code), the unit
`landscape-scan`'s `scan-task-unconverged` / `scan-task-no-converged-point`, and the
CLI `xtb/landscape-e2e-scan-counters` (which also cross-asserts `n_valid`/`n_fail`/`n_unconverged`).
The injection experiment (changing `env%error` back to `env%warning`) turns the first two red (report 49 §6 injection 6).

**INFO-4 (the `n_imag = -1` sentinel)**: `landscape_result%n_imag` is initialised to `-1`, and only a task that really performed a
frequency confirmation (`--lvib`, `--lts` without `--lts-no-verify`) writes it as the real mode count;
so in the JSON of `--lopt`/`--lscan`/`--sp` it is `-1` (not 0! 0 means "confirmed and no imaginary frequency").
The documentation of `--lts-no-verify` likewise says `n_imag = -1`.

**INFO-5 (`ts` counter sampling time, M-1 fixed this round)**: `tasks/ts.f90`'s
`result%n_cache_miss` must be sampled **after** `confirm_saddle` (that one 6N confirmation Hessian).
It used to be sampled before it, so the **same stdout** showed both `cache misses: 77` and
`landscape engine: energy evaluations 95` (difference 18 = 6N, N=3), while the JSON and the CLI assertion
had their source in the former — the regression comparison's semantics were wrong. The convention now:

* `result%n_cache_miss` = **the engine's total number of evaluations of a completed run**, **identical** to
  `landscape engine: energy evaluations` at the end of the same stdout (`opt`/`vib`/`scan` have always behaved this way, `ts` now agrees).
  Two **exceptions** must be read together: `irc` does not write `n_cache_miss` (it writes `n_eval_fwd`/`n_eval_bwd` per direction);
  a **failed band search** may return early before the sampling (`tasks/ts.f90:235` writes the document first; the band path's early returns
  at `tasks/ts.f90:718-724`, and the search's internal path-construction failures at `path/neb.f90:739`, `:837-839`, `:909-913`
  all miss the sampling point at `tasks/ts.f90:932`): a failure **before the first evaluation** was measured this round
  (a missing product file: `n_cache_miss: 0` agreeing with `energy evaluations 0`, exit 1);
  but the two returns triggered **after** the band search leave the field at the default `0` while the engine total on the same stdout is non-zero
  — the latter is a **reading of the code, not a measurement** (it takes a band collapse or a candidate-point SCC failure to trigger), the process still exits non-zero,
  and the field is the default value and **not** a measured one;
* `result%write_log` (printing `cache misses:`) is likewise moved after the confirmation, at both call sites
  (the single-geometry search `landscape_ts` and the band close-out `landscape_ts_finish`) consistently;
* therefore the counter of `--lts-no-verify` is lower by exactly **one whole** 6N central-difference Hessian;
* assertions: the CLI `xtb/landscape-e2e-ts-counters` (`cache misses` == the engine total, and
  `with confirmation − without confirmation` is a positive integer multiple of 6N), `xtb/landscape-ljson-ts` (JSON == the engine total);
  injecting "move the sampling point back before the confirmation (and delete the latter one, i.e. the original logic)" turns both red, report 51 §3.
* **M4/M6 acceptance numbers are not broken**: geometry, energy, imaginary frequency and failure semantics do not involve this counter;
  M4/M6's CLI assertions and acceptance numbers are each unchanged after this round's re-run (report 51 §4).

### 12.12 M5 (chain-of-states phase one: IDPP / NEB / CI-NEB) actual wiring and interface contract

**runtyp**: **no new number is added**. `--lts --lts-method neb|cineb` reuses `p_run_lts = 19`
(the reservation of §12.1), `landscape_ts_settings%method` gains `p_landscape_ts_neb = 4` /
`p_landscape_ts_cineb = 5`, and `tasks/ts.f90` branches into the band branch at the method dispatch.
The measured value set of `grep -n "integer, parameter :: p_run_" src/setparam.f90` is
`{1..15, 19, 21, 71, 100..104}`; the band methods need no new number, so R-05 does not trigger.

**New files** (`src/landscape/path/`): `idpp.f90` (the IDPP initial path), `cineb.f90`
(Eq. 5 climbing-image force + ignition criterion), `neb.f90` (the band kernel: improved tangent, Eq. 12 spring,
dynamic spring, Kabsch alignment, two-criterion convergence, two-phase CI switch).

**New CLI flags** (all `if (set%runtyp /= p_run_lts) call set_runtyp('lts')`):

| flag | Semantics | settings field |
|---|---|---|
| `--lts-product <file>` | product endpoint (**single-frame xyz**, same atom count and atom order as the input) | `path%product_file` |
| `--lts-images <n>` | number of images (including the two fixed endpoints, >= 3) | `path%n_images` |
| `--lts-kmin <k>` / `--lts-kmax <k>` | dynamic-spring lower/upper bound (Eh/bohr²) | `path%k_min` / `path%k_max` |
| `--lts-kdecay <d>` | dynamic-spring decay factor | `path%k_decay` |
| `--lts-no-dynamic-k` | use `k_max` everywhere | `path%use_dynamic_k = .false.` |
| `--lts-climb` | enable the climbing-image phase (turned on automatically by `--lts-method cineb`) | `path%climb` |
| `--lts-climb-switch <f>` | ignition threshold (Eh/bohr) | `path%climb_switch_rms` |
| `--lts-no-idpp` | linear interpolation instead of IDPP | `path%ifidpp = .false.` |
| `--lts-no-align` | disable the Kabsch alignment | `path%align = .false.` |
| `--lts-relax-ends` | first minimise the endpoints with M1 | `path%relax_ends = .true.` |
| `--lts-frms-avg <f>` / `--lts-frms-max <f>` | the band's two-criterion thresholds (Eh/bohr) | `path%f_rms_avg_tol` / `path%f_rms_max_tol` |
| `--lts-max-displ <d>` | upper bound on a single component in a single step (bohr) | `path%max_displ` |

`--lts-max-steps` writes both `ltset%max_steps` and `ltset%path%max_steps` (the band's iteration budget).

**Input contract (also applies to the AutoNEB / String of phase two)**:

1. The positional xyz argument = the **reactant**; `--lts-product <file>` = the **product** (single-frame xyz).
2. `path%input_file` is filled from the positional argument by `main.F90` and is used **only** to detect a multi-frame input
   (`landscape_ts_count_frames`, a counter that skips the atom line frame by frame, not a parser).
3. The validation matrix (each is `env%error` + a non-zero exit; the corresponding CLI test names are in report 35 §4):

| Case | Result |
|---|---|
| a product file present, single frame, atom count/order agree | build the band normally |
| the product file does not exist / cannot be opened | `cannot open the product geometry` |
| the product atom count differs | `the product geometry has N atoms but the reactant has M` |
| the product atom order differs | `the atom order of the product geometry differs` |
| the product has > 1 frame | `holds K frames; exactly one is required` |
| the product extension is not xyz | `must be a single frame xyz file` |
| the input has > 1 frame and **no** product | `the input holds K frames; pass the product with --lts-product` |
| the input has > 1 frame and **has** a product | `the two endpoints are ambiguous` |
| a single-frame input and no product | `a band search needs a product geometry` |
| a single-ended method (prfo/bprfo/dimer) with `--lts-product` | `env%warning` (a resource script setting that flag globally is not an error, but it is never silent) |

> **Decision record**: the **convenience path** for a multi-frame input (frame 1 = reactant, frame 2 = product) is **not implemented**:
> the existing `readMolecule` reads only a single frame, and reusing it to read the second frame would require writing a multi-frame parser of one's own, at a cost exceeding the benefit.
> It is therefore handled as "a single path + an explicit error" (report 35 §4).

**Output**: `path.xyz` (`get_namespace('path.xyz')`, frame 1 = the reactant, frame N = the product,
the comment line carrying the energy and the frame number), plus M4's `xtbts.xyz` / `xtbts.log` reused (their content is the
**TS candidate**, i.e. the climbing image; before ignition the highest-energy image is taken). The TS candidate also goes through the M3 frequency confirmation,
and an imaginary-frequency count != 1 exits non-zero.

**Calibration (PLAN §8.2 experiment #8, measurement in report 35 §3)**:

| Parameter | PLAN initial value | After calibration | Basis |
|---|---|---|---|
| `k_min` / `k_max` | 2.083e-3 / 2.083e-2 `[to be calibrated]` → **closed** | **1.0e-2 / 1.0e-1 Eh/bohr² (dynamic)** | the LEPS band scan (report 35 §3.2) + the M5 independent review (report 37 §3.2: both dynamic value sets converge, the static 1e-2/1e-1 does not; on NH3 11 steps vs 20 steps for the PLAN initial value) |
| `climb_switch_rms` | 3.472e-2 `[to be calibrated]` → **closed** | **9.7234e-3 Eh/bohr (= 0.5 eV/Å)** | the PLAN value used a **force** conversion factor for a **force constant/threshold**: 0.5 eV/Å = 9.7234e-3 Eh/bohr, not 3.472e-2 (3.472e-2 = 0.5/14.4, see report 35 §3.3). M5 review (report 37 §3.1): the three-digit unit conversion was independently recomputed and agrees; the value stored in `settings.f90` is 9.7234e-3, differing from the exact value by 5.3e-8 |
| `f_rms_avg_tol` / `f_rms_max_tol` | — | **3.0e-4 / 1.0e-3 Eh/bohr** | the LEPS band converges and the barrier error is < 1e-3 kcal/mol |
| whether σ_g spuriously triggers the climb switch | question | **no**: the random σ_g ≤ 1.2e-15 and the warm-restart bias 3.9e-7 (report 28 §3.1) are 13 / 4 orders of magnitude below 9.72e-3 |

**Known limitations (report 35 §6)**: the band propagation uses a fixed-step-truncated L-BFGS (the force field is non-conservative),
and it does not converge for large-amplitude heavy-atom exchange reactions such as HCN→HNC (the IDPP path itself is discontinuous);
it converges normally for the NH3 inversion, LEPS and Müller-Brown. This is a known gap of phase one, which phase two may close by adding a line search.

---

### 12.13 M5 (chain-of-states phase two: AutoNEB / String(GSM)) actual wiring

**runtyp**: **no new number is added**. `--lts --lts-method autoneb|string|gsm` reuses `p_run_lts = 19`;
`setparam.f90` / `set_module.f90` are unchanged (verified by measurement), the method name goes through
`landscape_ts_method_from_name`, and the three new constants are `p_landscape_ts_autoneb = 6` /
`p_landscape_ts_string = 7` / `p_landscape_ts_gsm = 8`.
`landscape_ts_method_is_band` covers all three (all three read `--lts-product`),
and a new `landscape_ts_method_is_string` distinguishes the string family.

**New files**: `path/autoneb.f90` (AutoNEB), `path/string.f90` (the mathematical kernel of normal force / growth indicator / spacing condition /
spline tangent / reparametrisation), `path/gsm.f90` (two-phase driver + climbing node + refinement round).

**New CLI flags** (all `if (set%runtyp /= p_run_lts) call set_runtyp('lts')`),
also written into `src/xhelp.f90`:

| flag | Semantics | settings field | Default |
|---|---|---|---|
| `--lts-autoneb-nstart N` | number of images of the coarse path | `path%autoneb_nstart` | 5 |
| `--lts-autoneb-max-paths N` | hard upper limit on images (violation → error) | `path%max_paths` | 10 |
| `--lts-autoneb-max-depth N` | hard upper limit on insertion stages | `path%max_depth` | 5 |
| `--lts-autoneb-restart NAME` | reuse an earlier `path_autoneb.xyz` | `path%autoneb_restart_file` | unset |
| `--lts-string-nnodes N` | node budget (upper bound) | `path%string_nnodes` | 9 |
| `--lts-string-grow-tol F` | the threshold of Eq.7 (magnitude) | `path%string_grow_tol` | 5e-3 |
| `--lts-string-ds F` | the arc-length increment of Eq.9 | `path%string_ds` | 0.5 |
| `--lts-string-nu2 F` | the curvature lower bound of the spacing condition | `path%string_nu2` | 0.05 |
| `--lts-string-grow-steps N` | upper limit on the relaxation steps of one frontier | `path%string_grow_steps` | 200 |
| `--lts-no-string-spline` | central-difference tangent | `path%string_spline = .false.` | spline |
| `--lts-string-history` | print the growth history | `path%string_history` | no |

`--lts-method cineb|autoneb|string|gsm` turns climbing on automatically (`path%climb = .true.`);
`--lts-images` for AutoNEB is the **requested final image count** (`max_paths` remains a hard upper limit).

**Output**: `path_autoneb.xyz` (the AutoNEB path, also the restart file),
`path.xyz` (string/gsm, the same format as NEB),
`path_ts_list.xyz` (saddle candidates: one frame per AutoNEB stage, and for string the internal local maxima of the final path;
the frame comment carries the energy and the **number of imaginary frequencies**), plus M4's `xtbts.xyz`/`xtbts.log` reused.

**Calibration and measurement** (details in `docs/_landscape-recon/36-m5-autoneb-string-report.md`):
on the NH3 inversion the AutoNEB barrier is 6.0823 kcal/mol (the same as CI-NEB) and string 5.9789 kcal/mol,
and on the same system the GSM/CI-NEB saddle-geometry RMSD is **0.0140 bohr**; string's convergence threshold has a measured lower bound
(`f_rms_avg 8.1e-4 / f_rms_max 1.78e-3`), which the end-to-end case relaxes explicitly and records in report §5.

**Known limitations**: string's growth phase does not converge on the **abstract 2-dimensional embedding** and on the **LEPS phase-one endpoint pair**
(the former's path turns sharply, the latter's straight line is orthogonal to the MEP exit direction); both are recorded with measured numbers in report §5;
a real molecule (NH3) behaves normally.

### 12.14 M6 (IRC phase one: GS / LQA / shared corrector / driver) actual wiring and interface contract

> Code is authoritative. Milestone M6, phase one, report `42-m6-irc-core-implementation-report.md`.
> HPC / EulerPC belong to phase two and are **not implemented** in this round.

**runtyp**: `p_run_lirc = 20` (`src/setparam.f90`, between `p_run_lts=19` and `p_run_lvib=21`).
Measured, `p_run_*` uses `{1..8,10..15,19,20,21,71,100..104}` and `p_ext_*` uses
`{-1,0,1,3,4,5,12..18}`; 20 is free in both namespaces and clashes with no existing value.
`src/set_module.f90` gains `case('lirc'); set%runtyp = p_run_lirc`.

**Interface contract (ruled by the parent session, followed by the implementation)**

1. **The input geometry = the TS itself**. `xtb xtbts.xyz --gfn2 --lirc --lirc-method gs` is the natural workflow.
   Before starting, M3's `landscape_vib_analysis` performs the **imaginary-frequency confirmation**: exactly 1 imaginary frequency counts as a TS;
   0 (a minimum) or ≥2 (a higher-order saddle) → `env%error` + a **non-zero exit code**,
   not a warning (the H2 lesson of M4).
2. **Deterministic forward direction**. Reusing the M4 phase convention
   (`xtb_landscape_saddle_eigenfollow::landscape_transition_mode_set_phase`: the largest absolute
   component is taken positive), printing that component's value and atom index on stdout and in `irc.log`; `--lirc-swap` explicitly negates it
   and records it in `irc.log` (`directions exchanged:`). Two runs of the same input give a bit-identical `irc_forward.xyz`
   (asserted by the CLI case).
3. **Unit contract**: the IRC step length unit = **`bohr*amu^1/2`** (mass-weighted arc length). The mass weighting uses **amu**
   (`getAtomicMass*autoamu`), not the electron-mass a.u. measure of the vibrational analysis. Every CLI, settings and
   log entry states that unit; the header comment of `irc/corrector.f90` gives the equivalent derivation of `G = M^{-1}`.
4. **LQA lineage**: implements the **Page & McIver branch** (JCP **88**, 922 (1988)), i.e. the quadratic Taylor analytic propagation
   cited by the HPC/EulerPC paper and by Gaussian; the module header comment explicitly records the difference from Sun–Ruedenberg /
   Eckert–Werner QSD (`x(u)=x^(k)-H^{-1}(I-uH)g`, three-point differentiation); QSD is **not implemented**.
5. **mBS uses a simple Euler** (not a modified midpoint), `mbs_max_k=15`, `mbs_points=20`;
   `mbs_tol` defaults to MAPLE's 1e-5, and the HPC paper's 1e-6 is selectable via `--lirc-mbs-tol 1e-6`;
   a convergence failure returns `converged=.false.` (for phase two to fall back to one GS step and warn).
6. **Hessian along the path**: Bofill by default (reusing `optimize/hessian_update.f90`, forced
   symmetric after the update), `--lirc-recalc N` rebuilds it with the provider every N steps; the initial Hessian goes through the M3 provider.
7. **Three termination signals**: (a) `max_steps`; (b) per-component RMS gradient ≤ `grad_tol`; (c) `e_rise_steps`
   consecutive steps without refreshing the **running minimum** (the "energy rise" implementation form of PLAN §6.5, reason in
   report §10 R-3).
8. **`res` write-back**: the `p_run_lirc` block of `src/prog/main.F90` writes `lres%energy` (= the TS energy,
   IRC's reference point) and `lres%gnorm` back to `res` (AGENTS.md §6 item 7); all four output file names
   go through `get_namespace`.

**Deliverables**: `src/landscape/irc/{corrector,gs,lqa}.f90`, `src/landscape/tasks/irc.f90`,
`landscape_irc_settings`, `landscape_irc_result` (with the per-point E/g count and the termination signal),
`--lirc` + 25 sub-options, `irc_forward.xyz` / `irc_backward.xyz` / `irc_path.xyz` (sorted by arc length,
the highest point marked `TS`) / `irc.log` (per-point table + endpoint attribution + effective etemp + phase).

**Known deviations** (report §10): GS averages E/g = 16.9/20.3 per point (PLAN expected 3–5; the root cause is that the micro-cycle
is pinned by the trust-region cap; phase two is recommended to switch to an equality-constrained Lagrange step); under a phase injection "bitwise
determinism" does not turn red (a coverage gap); `max_steps` defaults to inheriting 256 rather than 50.

### 12.15 M6 (IRC phase two: HPC / EulerPC / endpoint attribution) actual wiring and contract

> Code is authoritative. Milestone M6, phase two, report `43-m6-irc-predictor-corrector-report.md`.

**New modules**: `irc/hpc.f90` (`landscape_irc_hpc_walk`), `irc/eulerpc.f90`
(`landscape_irc_eulerpc_walk`); the shared correction kernel `irc/corrector.f90` gained
`landscape_irc_corrector_step` (two-point DWI + mBS + DWI value) and `landscape_irc_path_reset`.
`irc/gs.f90` was split to expose public `landscape_irc_gs_step` (reused by the GS fallback of HPC/EulerPC).

**Algorithm contract**

1. HPC prediction = `landscape_irc_lqa_step` (Eqs.2–11); EulerPC prediction = a first-order explicit Euler
   `q − step·g/|g|` (Eq.2). Both give the same correction: **two-point DWI (current point, predicted point) + mBS**.
2. **The removable-singularity branch `a_ii → −t` of `λ→0`** is implemented explicitly in `corrector.f90`
   (no division by zero, no lost mode), shared by LQA/HPC; `lqa-zero-curvature-limit` is falsifiable in both directions.
3. **E/g = 2 per point** (one each for the predicted point + the correction point). The paper's 1 E/g uses DWI to
   reconstruct the correction-point gradient; measured, that reconstruction makes the path drift (the forward endpoint is
   higher by **1e-3..5e-2 Eh**: a faithful implementation measured 2.80e-3 / 4.56e-2,
   report 44 §6.1; the original record of 1.4e-2 in report 43 §6.3 is not reproducible), so it was changed to evaluate the
   correction point. MAPLE, the reference implementation, uses 3 E/g for the same design. Measured, GS gives 16.9/20.3, LQA a constant 1.00.
4. **A failed correction → fall back to `landscape_irc_gs_step` + `env%warning`** (PLAN §6.5);
   covered by the unit `hpc-corrector-fallback` and the CLI `landscape-irc-pc`.
5. **`loose_cycles`** (EulerPC coarse/fine): the first `loose_cycles` macro steps record the Euler prediction directly (1 E/g),
   after which the corrector is enabled; `0` disables the coarse phase. See report §3.2 (the semantic difference from MAPLE is recorded as R-2/D-4).
6. **Endpoint RMSD = Kabsch alignment** (`align_geometry`, the mass-free proper rotation of M5);
   `irc.log` states the alignment method; the relaxation reuses the same engine ⇒ the same restart policy and frozen `etemp`;
   the relaxation's **four criteria** take the task thresholds (`--lirc-level`, `set_conv_level`), and the budget takes `--lirc-max-steps`
   (the same style as `tasks/ts.f90:1069-1075`, `scan/relax_scan.f90:577-585`).
7. **`endpoint_reached`**: only (b)/(c) (and it requires that the relaxation already converged **and** that the Kabsch-aligned RMSD ≤ `rmsd_end`)
   count as falling into a minimum; a path truncated by `max_steps` is recorded as `F` (CLI negative case + injection (iv)).
   With no relaxation there is no relaxed minimum, the `rmsd_end` criterion is **unusable**, and the log states explicitly that it was "skipped".
8. **New CLI**: `--lirc-loose-cycles N`, `--lirc-endpoint-relax`, `--lirc-erise-steps N`
   (an alias of `--lirc-e-rise`); `--lirc-grad-tol`/`--lirc-euler-n` carry over from Phase 1.
9. **Correction of the HPC 1 E/g deviation (a correction that was needed all along)**: the old version of this section wrote "measured, that reconstruction
   makes the path drift (the forward endpoint is higher by **1.4e-2 Eh**, report 43 §6.3)". The validation round **independently implemented** the 1 E/g scheme and
   obtained **2.80e-3** (V1: evaluate only the predicted point, trust the DWI gradient) and **4.56e-2** (V2: plus a predicted secant update)
   (report 44 §6.1); neither is 1.4e-2. The wording is now unified as "**magnitude 1e-3..5e-2 Eh**", and **the basis is changed to the two measured values above**
   (`hpc.f90:54` is corrected in step); the conclusion "so 2 E/g is chosen (5.5e-5)" is unchanged.

**Behaviour changes and new contracts of the M6 final fix round (report 46)**

| Item | Change | Basis / acceptance |
|---|---|---|
| default integration method | `gs` → **`hpc`** | report 44 §3.3 (more accurate 0.0022 vs 0.040 bohr, cheaper by 8.5×); the default path is asserted by the CLI `xtb/landscape-irc-knobs` as "what runs is hpc + the HNC/HCN window"; `--lirc-method gs` behaviour is **unchanged** (all 10 numbers of report 42 were re-run and are bit-identical) |
| `--lirc-level` | from "parsed but read by nobody" to **actually driving the endpoint relaxation** (4 criteria + budget copy) | CLI `xtb/landscape-irc-knobs`: superloose 1 step/ −5.47213843 Eh vs vtight 7 steps/ −5.47215989 Eh; injecting "delete the copy" → red |
| `--lirc-rmsd-end` | from "parsed but read by nobody" wired into `endpoint_reached` | CLI as above (1e-3 → forward `F`, backward `T`) + unit `endpoint-rmsd-criterion`; injecting "remove the criterion" → two reds |
| `--lirc-dwi-n` | made explicit as a **capacity** (two-point interpolation, ≥2 equivalent; <2 refused) | measured 4 vs 20 bit-identical (already recorded as a design choice); `--lirc-dwi-n 1` now exits 1 with `env%error` |
| GS quality | added `landscape_irc_path%n_pinned` → a "pinned" counter in `irc.log` / the result | the CLI `xtb/landscape-irc-cli` asserts non-zero for GS (33/42, 38/40) and 0 for hpc (the negative control); injecting "the counter does not increment"/"hpc also counts" → each red |
| arc-length definition | `irc.log` states explicitly that gs/hpc/eulerpc use a chord-length accumulation and lqa the integrated arc length | LOW-4; cross-method comparison is annotated as unusable |
| F-1 (path reuse across ndim) | `path_reset` frees the storage + rebinds points of a different dimension (no longer writing into a wrongly shaped array) | unit `path-cross-dimension-reuse`; injecting "the old reset (keeping capacity/ndim=0)" → red |
| test count | `ctest -R landscape` **78/78** (new CLI `xtb/landscape-irc-knobs`), unit `landscape-irc` 35/35 (3 new cases); regression 12/12 | — |

**Closure on the reachability of signal (b)** (M4 σ_g backfill): cold start bitwise equal, cross-OMP ≤ 1.11e-15, warm 3.916e-7 Eh/bohr;
the default `grad_tol = 1e-3` (RMS per component) is ≈2553 times the warm noise. Measured endpoint RMS: gs 5.98e-4, lqa 7.57e-4,
hpc 9.59e-4, all ≤ 1e-3 ⇒ **reachable (the default policy is not removed)**; but EulerPC forward is triggered first by signal (c),
and "(b) is reachable but not always the first to trigger" is recorded (report §7.2).

**New tests**: unit `landscape-irc` 28/28; CLI `xtb/landscape-irc-pc` (HPC+EulerPC end-to-end + the new flags
+ endpoint-attribution negative cases). `ctest -R landscape` 77/77, regression 12/12.
(After the M6 final fix round 78/78, unit 35/35; see the change table of the previous section and report `46-m6-fix-report.md`.)

### 12.16 M7 (thermo/validation close-out) actual wiring: the specification and conventions of `--ljson`

**runtyp**: **no new one is added**. `--ljson` is merely an output switch of every landscape task
(the `logical :: ljson` component of the abstract base type `landscape_settings`, which every task
settings type — including `landscape_sp_settings` — inherits, `types/settings.f90`);
it changes no runtyp, occupies no positional argument, and needs no constant of its own. `--ljson` is
registered in the flag loop of `src/prog/main.F90` (`case ('--ljson')`) and in `src/xhelp.f90`,
it sets the switches on the five settings objects to true **together** (`lset`/`lsset`/`lvset`/`ltset`/`lircset`),
and the task selected by the runtyp reads it itself; **`--ljson` does not select a task**, it must be
given together with one of `--lopt`/`--lscan`/`--lvib`/`--lts`/`--lirc`.

**Implementation files**: `src/landscape/types/json.f90` (document construction + serialisation),
`tasks/{sp,opt,scan,vib,ts,irc}.f90` (each task's `write_json*` hook),
registered in `src/landscape/CMakeLists.txt` / `meson.build`.

**File and naming**: `landscape_<task>.json`, `<task> ∈ {sp, opt, scan, vib, ts, irc}`,
through `get_namespace` (`--namespace ns` ⇒ `ns.landscape_<task>.json`); when done it prints one line
`wrote <file>` on `env%unit`. **A 2D scan writes the same `landscape_scan.json`** (the `task` field is
still `scan`, with two extra counters `n1`/`n2`), it does not start a new file name.

**Schema (10 top-level keys, fixed order)**:

```
format(1) task status status_name converged message counters values flags history
```

* `counters` / `values` / `flags` are written in the **order the task added them**, so the diff of two
  runs of the same task is stable;
* `history` is the convergence-history sequence (`energy`/`gnorm`/`gmax`/`dispnorm`/`dispmax`/`trust`/`method`,
  whichever is missing is not written), stored as "a flat real pool + offset/length per sequence" to avoid
  the gfortran 12.2.0 derived-type intrinsic-assignment stride defect (AGENTS §6.5);
* reals use **17 significant digits** (`es25.17e3`, a bitwise double round trip); a **non-finite value is written as JSON `null`**,
  never a fabricated `0.0` (the scan-table rule of PLAN §5.5);
* **no wall-clock time, path or random quantity is written** — this is the premise of "two runs of the same input are byte-identical".

**Counter semantics (item by item, including each task's sampling time)**

| Counter | Meaning | Sampling time |
|---|---|---|
| `n_eval` | `opt`/`ts`: number of objective-function calls (printed as `energy calls`); `scan`/`vib`: **total number of engine evaluations** | at the end of the task |
| `n_cache_miss` | the number of times the engine really called xTB (geometry-cache misses) | `opt`/`scan`/`vib` at the end of the task as always; **`ts` after `confirm_saddle`** (INFO-5) |
| `n_steps` | number of steps; on `scan` it is the **number of points** | — |
| `n_imag` | number of imaginary frequencies, **`-1` is the sentinel for "no frequency confirmation performed"** (INFO-4) | after the confirmation |
| `n_iter` | length of the convergence history | — |
| `n_points`/`n_forward`/`n_valid`/`n_fail`/`n_unconverged`/`n1`/`n2` | `scan`'s point accounting | the same data that prints `wrote xtbscan.log with N frame(s), M failed point(s) omitted` |
| `method` | the method identifier of `ts`/`irc` (1..8 / 1..4) | — |
| `n_fwd`/`n_bwd` | the number of points in the two directions of `irc` | — |

**stdout and JSON are same-source and same-meaning**: on a **completed run**, `counters` are exactly the
numbers the task prints on stdout, **not a second bookkeeping** — this is the very reason `--ljson` exists
(exceptions as in INFO-5: `irc` has no `n_cache_miss`, and in a failed band search that field is the default `0`).
Three old defects that weakened this were fixed this round: `ts`'s `n_cache_miss` was sampled before the
confirmation (INFO-5, now moved after); `scan`'s `n_eval` had no CLI cross-assertion (added); the three
counters `n_valid`/`n_fail`/`n_unconverged` had no test coverage
(now covered by `xtb/landscape-e2e-scan-counters`, including the "no converged point" non-zero-exit branch).

**status and exit code**: `0` ok; `1` incomplete (the **result** is interpretable with caveats: an unconverged
minimisation, a scan with unconverged points, an existing imaginary frequency); `-1` error (the result is
unusable, the process **exits non-zero**).
`status` is a **classification of the result, not a promise about the exit code**: the exit code of the three
cases is in the table of §12.11 INFO-3 (unconverged minimisation = `status 1` **and** a non-zero exit;
an imaginary frequency and a scan with unconverged points = `status 1`, exit 0;
an unusable result = `-1`, non-zero exit).

**Determinism (measured; must not be treated as a bitwise promise)**:

* **under the same thread count** two runs of the same input are **byte-identical** (verified on all 6 tasks);
* **across OMP thread counts it is not bitwise identical**: the recursive maximum absolute difference of OMP=2/4
  relative to OMP=1 is opt 1.8·10⁻¹², scan1D 2.7·10⁻¹², scan2D 3.2·10⁻¹², vib 2.4·10⁻¹⁰ (report 49)/
  3.7·10⁻¹⁰ (report 51, independently re-measured), ts 1.2·10⁻¹⁰, irc 4.3·10⁻¹²
  (the OpenMP reduction-order effect of AGENTS §6.1, amplified by the 17-digit writing);
  **the counters are unchanged under all thread counts**, so **counter-level comparison is thread-safe, byte-level comparison is not**.
* ⇒ **any JSON regression baseline (or gold-file comparison) must first pin `OMP_NUM_THREADS`**;
  the delivered ctest already pins it with `ENVIRONMENT "XTBPATH=...;OMP_NUM_THREADS=1"`.

**Tests**: CLI `xtb/landscape-ljson-{opt,scan,scan2d,vib,ts,irc}` (the `ljson` mode of
`landscape_e2e_check.py`: standard-library JSON parsing, key order, counters cross-asserted against stdout,
two processes byte-identical, namespace prefix); the unit `landscape-e2e`'s `sp-ljson` (`sp` has no runtyp,
so it can only go through the API) and `ljson-determinism`; CLI `xtb/landscape-e2e-{ljson-methods,ts-counters,scan-counters}`.
Injection evidence (report 49 §6, report 51 §3): `n_eval + 1`, a random message, `n_points + 1`,
`n_unconverged + 1`, `n1 + 1`, moving the sampling point back, making the MAPLE probe a shallow import again —
each has a named red test.

## Appendix A: Environment constraints (measured)

| Item | Measured value | Impact on this plan |
|---|---|---|
| `cmake --version` | 4.3.2 | `-DWITH_CPCMX=OFF` is required (otherwise cpcmx and toml-f have a target-name clash, `CMakeLists.txt:56-58`) |
| `gfortran --version` | GNU Fortran 12.2.0 | supports `implicit none(type, external)`, `allocate(polymorphic, source=)`, `select type` |
| optimisation level | **requires `-DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"`**; the GNU default of `Release` is `-O3` | ★measured (2026-10-03, `docs/_simplify-recon/04-o2-and-silent-defects-fix.md`): the Hessian path compiled from the `edcfbbe` source by gfortran 12.2.0 gives `-931.59/3329.78/3345.94 cm⁻¹` (wrong) under `-O3`, while `-O0/-O1/-O2` are all correct and bit-identical to the reference binary; `-O3 -fno-tree-vectorize` is wrong too ⇒ the mechanism is not localised. **Not reproduced on `24c069f`**, but the risk cannot be bounded ⇒ the official level is `-O2`. `cmake/CMakeLists.txt` emits `message(WARNING ...)` when it detects `-O3`. The four-system acceptance `hessian`/`vibspectrum` are **byte-identical** under -O2 and -O3 |
| `meson` / `ninja` | **not installed** (`command not found`) | `meson.build` must be written but cannot be verified (R-16) |
| mctc-lib | not present locally, CMake fetches v0.5.1 over the network via FetchContent | the build needs the network; verified feasible |
| build directory | always `/tmp/...` | a `build/` **must not** appear inside the repository |
| `git status` | only `?? docs/` | this round's deliverable is documents only + the permitted minimal changes to existing files |
| `OMP_NUM_THREADS` | when unset = the machine's core count (8 on this machine) | **scan / Hessian-related experiments, benchmarks and tests always use `OMP_NUM_THREADS=1`**: measured, the same 2-point scan 0.13 s (1 thread) vs 44.12 s (8 threads, 340× reverse scaling, AGENTS §6.8); `ctest -R landscape` drops from 38 s to 10.6 s, of which `xtb/landscape-scan` (the unit suite) drops from 19.6 s to 0.13 s and `xtb/landscape-scan-failed-point` from 28 s to 0.11 s; every engine-running landscape CLI check and unit suite is already pinned to a single thread on both the CMake and meson sides. Parallelism is used only to "run different scan points in multiple processes" |

**The verification commands of the M2 review round** (implementation stage; the full ctest must not be run):

```bash
ctest --test-dir /tmp/xtb-land/build -R landscape                       # 25/25, 12.6 s
ctest --test-dir /tmp/xtb-land/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'   # 12/12
```

**The verification commands that M0/M1 must run** (implementation stage):

```bash
cmake -S . -B /tmp/xtb-build-ls -DWITH_CPCMX=OFF -DCMAKE_BUILD_TYPE=Release -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"
cmake --build /tmp/xtb-build-ls -j
ctest --test-dir /tmp/xtb-build-ls --output-on-failure -R landscape
```

## Appendix B: List of differences of this plan relative to R05 §3.1

| Difference | Content | Reason |
|---|---|---|
| added `types/conv.f90` | the four criteria + the level table become a separate module | shared by all four of opt/scan/ts/irc; a separate module lets `test_landscape_conv.f90` test it on its own |
| added `types/updater.f90` | Bofill/BFGS/Powell/SR1 updates made separate | semantically orthogonal to the provider (the Hessian source); D3 explicitly lists 4 updates |
| added `tasks/*.f90` | one driver per task | avoids `landscape_driver.f90` ballooning into a 1000+ line giant select; `tasks/ts.f90` must hold the parameter validation of 7 methods |
| added `optimize/linesearch.f90`, `optimize/trust.f90` | the line search and the trust state machine extracted | shared by sd/cg/lbfgs/bfgs/rfo/prfo/bprfo/dimer; avoids 8 duplicate implementations |
| added `path/gsm.f90` | separated from `string.f90` | R05 §3.1 already lists both; GSM's CI/convergence wrapper and string's growth logic have different responsibilities |
| added `irc/corrector.f90` | DWI + mBS + LQA propagation shared | the four IRC methods share one correction kernel (the common skeleton of R01 §3.4) |
| no nested `CMakeLists.txt` | `src/landscape/` has only 1 build file | reduces 10+ boilerplate files and the risk of scope errors; consistent with the existing style of `src/CMakeLists.txt:113-119` listing `model_hessian/*` |
| `coords/*` kept but TS/IRC do not depend on it | serves only scan and Hessian transformations | see the exclusion reason of §11 |
