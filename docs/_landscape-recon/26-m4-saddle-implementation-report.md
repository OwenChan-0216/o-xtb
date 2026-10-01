# 26 — M4 (stage 1) implementation report: P-RFO / B-P-RFO transition state search

> Scope of this round: **P-RFO / B-P-RFO only**.  `--lts-method dimer` is a recognised
> value whose task aborts with `env%error("dimer is not implemented yet")`; the dimer
> search is the second stage of M4.  NEB/CI-NEB/AutoNEB/String stay in M5, IRC in M6.

All commands below were run with `OMP_NUM_THREADS=1` (AGENTS.md §4) in
`/tmp/xtb-land/build` (configured `-DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON
-DCMAKE_BUILD_TYPE=Release`).

---

## 1. Deliverables

| File | LOC | Content |
|---|---|---|
| `src/landscape/saddle/eigenfollow.f90` | 593 | spectrum, mode selection / following, rigid body basis + projection, shared RFO secular solver |
| `src/landscape/saddle/prfo.f90` | 731 | `landscape_prfo_step` (double shift, Eq. 4.16–4.20), `landscape_saddle_optimize` (macro driver) |
| `src/landscape/saddle/bprfo.f90` | 397 | `landscape_bprfo_step` (restricted step, `alpha` partition + micro iterations) |
| `src/landscape/tasks/ts.f90` | 339 | `--lts` task driver, `xtbts.xyz` / `xtbts.log`, frequency confirmation |
| `src/landscape/types/settings.f90` | +207 | `landscape_ts_settings`, `p_landscape_ts_*`, name lookups |
| `src/landscape/types/results.f90` | +9 | `n_imag`, `imag_freq`, `etemp` in `landscape_result` |
| `test/unit/test_landscape_saddle.f90` | 808 | 21 unit tests (analytic Müller-Brown + synthetic spectra) |
| CLI | — | `--lts` + 18 sub-options, `p_run_lts = 19`, `set_module`, `main.F90`, `xhelp.f90` |

---

## 2. Algorithms as implemented

### 2.1 P-RFO (PLAN §6.3, Eq. 4.16 / 4.18 / 4.19 / 4.20)

`landscape_prfo_step` diagonalises the symmetrised Hessian (`mctc_syev`, **ascending**
eigenvalues, eigenvectors as columns), identifies the followed mode `k` by
`argmax_i |V_i^T v_tracked|`, and builds

```
lambda_p = 1/2 b_k + 1/2 sqrt(b_k^2 + 4 F_k^2)          (4.18a)
sum_{i/=k} F_i^2/(lambda_n - b_i) = lambda_n,  lambda_n < 0   (4.18b)
dq_k   = -(F_k V_k)/(b_k - lambda_p)                     (4.19)
dq_i   = -(F_i V_i)/(b_i - lambda_n),  i /= k            (4.19)
dq     = sum_j dq_j                                      (4.20)
```

* `lambda_n` is solved by bisection on the strictly decreasing function
  `residual(lambda) = sum F_i^2/(lambda - b_i) - lambda`, bracketed by doubling below
  `min_{i/=k} b_i`.  The sign condition `lambda_n < 0` is asserted in code (the
  residual is negative at `lambda = 0` for a non-empty downhill subspace).
* A negative eigenvalue in the **downhill subspace** (more than one negative
  eigenvalue, or a single one that was not selected as the followed mode) makes
  Eq. 4.18b unsolvable below zero, so the downhill modes are lifted
  `b_i -> max(b_i, hlow)`; the lift is reported through `lifted` plus an
  `env%warning` (PLAN §6.3, ORCA style).  The trigger is "the downhill subspace
  contains a negative curvature" rather than literally "more than one negative
  eigenvalue": the PLAN's wording covers the common case, but the
  `--lts-init-mode force` path (a forced mode that is not the negative one) hits
  the same singularity and was an internal assertion failure until the trigger
  was generalised.  Unit test `prfo-negative-downhill` pins it.
* Denominators are guarded by `evals_eps`; the step is clipped to the trust radius.
* `landscape_prfo_step` optionally returns `lambda_p`, `lambda_n`, `lifted`.

### 2.2 B-P-RFO (PLAN §6.3, restricted step)

Same double shift, different trust handling: the radius is partitioned into an uphill
and a downhill sub-radius (`r_p = alpha*trust`, `r_n = sqrt(1-alpha^2)*trust`).  A
subspace whose double-shift component already fits its sub-radius is used unchanged;
only a component that exceeds it is restricted — the uphill one analytically, the
downhill one by solving `sum (F_i/(b_i - lambda_n))^2 = r_n^2` by bisection
(`max_micro_cycles` = the micro iteration count of the restricted step variant).

**Deviation from the PLAN table (documented, deliberate):** the PLAN only says "trust
radius 的子空间划分 + micro 迭代".  A variant that *always* takes `|dq_k| = r_p`,
`|dq_n| = r_n` cannot converge: near the saddle the step stays of order `trust` and the
`d_max`/`d_rms` criteria are unreachable (measured: 400 steps, no convergence, slide to
the global minimum).  The "restrict only where binding" form reduces to the double shift
near the stationary point and is what makes the Müller-Brown acceptance criterion
attainable (4 steps, table in §4).

### 2.3 Mode selection / following (PLAN §6.3, pysisyphus `PRFO.py:634-672`)

* Selection: the `target`-th negative eigenvalue (1 = most negative, the missing
  `tsroot` semantics); with too few negative eigenvalues the lowest mode is followed and
  a warning is emitted.
* Following: `idx = argmax_i |V_i^T v|`, then the sign is realigned,
  `v_new = sign(V_idx^T v_old) V_idx`, so the dot product with the *previous* vector
  stays positive.  `|overlap| < mode_overlap_min` reselects the mode, sets
  `followed = .false.` and warns.
* **Phase convention** (`forward` = the direction in which the largest component is
  positive): applied **only at selection**, with the component index / value / atom
  number printed.  The PLAN asks for both the phase convention and the overlap sign
  realignment; re-applying the phase after following would silently undo the
  realignment (the largest component carries no information about the overlap sign), so
  the two are separated by scope.  The report prints the current largest component every
  selection and (printlevel ≥ 2) every follow step.

### 2.4 Rigid body projection — closing the M1 debt (PLAN §9.5, AGENTS.md §6 item 6)

`landscape_rigid_modes` builds three translations and three rotations
(`e_a x (x_i - x_c)` about the geometric centre) and Gram-Schmidt-orthonormalises them.
They are mass independent: translations and rotations are exact null vectors of the
Cartesian Hessian for any geometry, so removing them from a step removes motion that
cannot change the energy while keeping the trust radius for internal motion.  A linear
molecule yields 5 independent directions, an isolated atom 0.  `landscape_project_rigid`
removes the component of a step along the basis; the driver applies it after every step
when `remove_rigid = .true.` (default), rebuilding the basis from the *current* geometry.

---

## 3. Module boundaries and deviations (code is authoritative)

1. `prfo.f90` hosts both the double shift step **and** the macro driver
   (`landscape_saddle_optimize`), mirroring the M1 `optimize/driver.f90` split; it uses
   `bprfo.f90` for the dispatch, `bprfo.f90` uses only `eigenfollow.f90` (no cycle).
2. `eigenfollow.f90` additionally hosts the shared RFO secular solver
   (`landscape_rfo_downhill_shift`, Eq. 4.18b) and the rigid body utilities.  Both are
   pure spectrum/coordinate linear algebra, and putting the solver there is what keeps
   the `prfo -> bprfo` direction acyclic (the reverse would be needed if it lived in
   `prfo.f90`).
3. `landscape_ts_settings` keeps the dimer fields (`delta`, `rot_alpha`, `rot_max_iter`,
   `step0`, `step_max`, `n_init`, `seed`) so the stage-2 settings object does not change
   shape and the deterministic seeding rule (PLAN N10) is documented in one place.  They
   have no consumer yet — that is a deliberate stage boundary, not dead code.
4. `hlow` defaults to `1.0e-2` (the GFN2-oriented value of `landscape_opt_settings`).
   The L1 Müller-Brown tests override it to `1.0e-6` because the dimensionless surface
   has curvatures of order `kcaltoau ≈ 1.6e-3 Eh/bohr²`; with the GFN2 default every
   downhill mode would be lifted to a single value.
5. Output files: `output_prefix = 'xtb'` and the suffixes `ts.xyz` / `ts.log`, so the
   default run writes `xtbts.xyz` / `xtbts.log` (mirrors `xtbopt.xyz`).
6. `--lts` **writes the converged energy back into `res`** in `main.F90`
   (AGENTS.md §6 item 7): the demo below reports `TOTAL ENERGY -5.387373532487 Eh`,
   which is exactly the `xtbts.xyz` energy.

---

## 4. Validation

### 4.1 Müller-Brown analytic benchmark (PLAN §8.2 / §9.5 acceptance)

Exact saddle `(-0.82200156, 0.62431280)`, Hessian eigenvalues `-1.1966 / +0.7813
Eh/bohr²` (one negative → no `hlow` lift at the saddle).  Both methods start from
different points:

```
prfo   start (-0.6, 0.4): 5 steps, converged, gmax 9.65e-06, |x-x_ref| 9.92e-06
bprfo  start (-0.7, 0.45): 4 steps, converged, gmax 1.04e-06, |x-x_ref| 1.06e-06
prfo vs bprfo RMSD: 6.30e-06
```

Acceptance (RMSD < 1e-3 bohr) met with a margin of > 150×.

### 4.2 Real GFN2 end-to-end (`xtb hcn.xyz --gfn2 --lts --lts-method prfo`)

The linear HCN equilibrium geometry is a **minimum**: the search converges immediately
to zero imaginary modes.  The input used here is therefore a **bent HCN**, the standard
guess for the HCN/HNC transition state:

```
$ cat hcn.xyz
3
bent HCN (transition state guess)
H   0.0000000000   1.0500000000   0.0000000000
C   0.0000000000   0.0000000000   0.0000000000
N   1.1560000000   0.0000000000   0.0000000000

$ OMP_NUM_THREADS=1 XTBPATH=$PWD xtb hcn.xyz --gfn2 --lts --lts-method prfo
 landscape: transition state search (prfo)
 Hessian source:           numerical
 electronic temperature:        300.000 K (frozen for the whole run)
 transition mode: index 1, eigenvalue      -0.12585349 Eh/bohr^2
 transition vector component:     0.646037 (cartesian 2 of atom 3)
   shifts: lambda_p=  4.404775E-02 lambda_n= -1.466039E-02 lifted=T followed=F
   shifts: lambda_p=  1.959429E-02 lambda_n= -6.955457E-04 lifted=T followed=T
   shifts: lambda_p=  4.356930E-04 lambda_n= -5.926308E-04 lifted=T followed=T
   shifts: lambda_p=  9.354169E-10 lambda_n= -3.380565E-06 lifted=T followed=T
 converged:      T
 steps:          4
 criteria (gmax,grms,dmax,drms):  T T T T
 saddle confirmation - imaginary modes: 1
 most negative frequency:         -1426.11 cm^-1
 wrote xtbts.xyz
 wrote xtbts.log
 landscape engine: etemp                   300.000 K
 landscape task terminated: converged
 | TOTAL ENERGY               -5.387373532487 Eh   |
```

`--lts-method bprfo` reaches the same kind of point in 6 steps (1 imaginary mode).
`--etemp 5000` reaches 1 imaginary mode in 5 steps and prints both
`electronic temperature: 5000.000 K` and `landscape engine: etemp 5000.000 K`.

`xtbts.xyz` (final frame): `H 0.1417 1.0331 0.0000 / C -0.0831 -0.1071 0.0000 /
N 1.0974 0.1240 0.0000` (bohr), `gnorm 7.69e-06`.

### 4.3 Test suites

```
$ ctest --test-dir /tmp/xtb-land/build -R landscape
100% tests passed, 0 tests failed out of 41
$ ctest --test-dir /tmp/xtb-land/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
100% tests passed, 0 tests failed out of 12
$ grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d
(empty: no duplicate test names)
```

22 unit tests in `landscape-saddle`: method names, spectrum ordering, mode
selection/following (argmax / sign / low-overlap / no-negative / phase), rigid basis
(orthonormal, linear = 5, internal-distance comparison), P-RFO shifts, `lambda_n`
secular residual + step ratio, trust clip, `hlow` lift, the single-negative-downhill
lift, invalid input, rigid projection of a raw step, B-P-RFO radius split, and the
three Müller-Brown tests.
New CLI tests: `xtb/landscape-ts-prfo`, `xtb/landscape-ts-etemp`, `xtb/landscape-ts-dimer`,
`xtb/landscape-ts-method-unknown`.

---

## 5. Falsifiability injections (all reverted, all re-verified green)

| # | Injection | Red tests |
|---|---|---|
| (i) | `landscape_rfo_downhill_shift` returns `lambda_n = 0` without iterating | 7 (`prfo-lambda-n`, `prfo-shifts`, `prfo-trust-clip`, `prfo-hlow-lift`, `prfo-rigid-projection`, `mb-prfo-saddle`, `mb-methods-agree`) |
| (ii) | sign realignment removed in `landscape_follow_transition_mode` | 1 (`mode-follow-sign`) |
| (iii) | `landscape_project_rigid` made a no-op | 2 (`rigid-projection`, `prfo-rigid-projection`) |
| (iv) | `index = 1` instead of `argmax|overlap|` | 1 (`mode-follow-argmax`) |

Injection (ii) initially did **not** turn the test red, because the test asserted a
positive dot with `e1` (which the selection-time phase convention happens to restore)
and because `landscape_follow_transition_mode` re-applied the phase convention.  Both
were fixed: the phase convention is now applied only at selection, and the test asserts
continuity (`dot(v_new, v_old) > 0`).  This is the project's "green but wrong" pattern
again — the miss was caught by the injection, not by reading.

---

## 6. A bug found by measurement, not by reading

`landscape_rigid_modes` used one 3-element temporary (`vec(3)`) both for the rotation
vector and for the whole length-`3N` column inside the Gram-Schmidt loop.  The intrinsic
assignment `vec = raw(:, k)` (9 → 3 elements) is a shape mismatch that gfortran
**silently truncates**, so only the three translations survived (`n_rigid = 3` for water
and CO2).  Every static reading of the routine looked correct; the failure showed up in a
standalone probe printing `n_rigid`.  Fixed by using separate `rvec(3)` / `col(dim)`
temporaries and reported here because it is a textbook instance of AGENTS.md §6 ("static
analysis was wrong three times").  The unit tests `rigid-basis-orthonormal` (6 columns)
and `rigid-linear-basis` (5 columns) now pin the count.

---

## 7. PLAN §8.2 risk experiments

| # | Status |
|---|---|
| 3 (`etemp` vs lowest curvature) | measured in M3 (report 21).  M4 **freezes and records** `etemp` (hard constraint 1): settings → engine control → calculator, printed from both ends, locked by `xtb/landscape-ts-etemp`. |
| 4 (gradient noise σ_g vs reachable force threshold) | **not calibrated** this round.  The TS search uses the inherited four convergence criteria; the fields are marked `[待校准]` in the `landscape_ts_settings` documentation. |
| 5 (P-RFO cross-validation vs Sella/pysisyphus + xtb) | **partial**.  The analytic Müller-Brown benchmark (quantitative, exact reference) and one GFN2 TS (HCN/HNC guess → 1 imaginary mode) are done.  A cross-code comparison against MAPLE/pysisyphus is not possible in this environment (neither is installed) and is not claimed. |

---

## 8. Open items / residual risks

1. **Acceptance criterion of the macro loop.**  A step is taken whenever the trial
   evaluation succeeds (the energy may rise at a saddle); only the trust radius reacts
   to the predicted/actual ratio.  From a poor start this can climb a wall
   (measured on Müller-Brown: B-PRFO from `(-0.9, 0.9)` increases the energy for 25+
   steps without converging).  A step-rejection/threshold policy driven by experiment
   #4 is the natural follow-up; it is deliberately not invented here.  The same
   behaviour makes `--lts-init-mode force` on the bent HCN walk into a nonsense
   geometry (SCF failures, 49 steps, clean abort with a non-zero status and no NaN);
   the default `h0` mode is unaffected.
2. **SCF failures inside the search.**  A failed single point shrinks the trust radius
   and retries the same geometry; a persistently failing region is left after
   `stagnate_patience = 8` consecutive failures rather than immediately.  Bounded and
   reported, but an early abort on an unconverged SCC would be friendlier.
3. **`hlow` for soft modes.**  `1e-2 Eh/bohr²` is the GFN2 value; near-degenerate soft
   modes (e.g. a linear molecule's bends) can be lifted.  Deterministic and reported,
   but the value is not calibrated for TS searches.
4. **Dimer stage 2** (`--lts-method dimer`) is an explicit error; the dimer settings
   fields exist but have no consumer.
5. **CLI coverage.**  `--etemp` (the only option with a synchronisation layer) and
   `--lts-method` are covered end-to-end; the remaining options write straight into the
   settings fields consumed by the kernel, whose effect is covered by the unit tests
   (`--lts-hlow` → `prfo-hlow-lift`, `--lts-alpha` → `bprfo-radius-split`,
   `--lts-mode-overlap-min` → `mode-follow-low-overlap`, `--lts-recalc`/`--lts-no-rigid` →
   the driver).  No per-flag CLI test was added for them.
6. `n_init` / `seed` are carried but unused (stage 2); the seeded generator requirement
   of PLAN N10 is documented on the fields.

---

## 9. Files changed

```
 M src/landscape/CMakeLists.txt
 M src/landscape/landscape_driver.f90
 M src/landscape/meson.build
 M src/landscape/types/results.f90
 M src/landscape/types/settings.f90
 M src/prog/main.F90
 M src/set_module.f90
 M src/setparam.f90
 M src/xhelp.f90
 M test/unit/CMakeLists.txt
 M test/unit/landscape_cli_check.py
 M test/unit/main.f90
 M test/unit/meson.build
?? src/landscape/saddle/            (eigenfollow.f90, prfo.f90, bprfo.f90)
?? src/landscape/tasks/ts.f90
?? test/unit/test_landscape_saddle.f90
```

Core layers (`src/type`, `src/xtb`, `src/mctc`, `src/param`, `src/io`, `src/disp`,
`src/coulomb`) untouched; only PLAN §12 integration points were modified.

---

## 10. [最终修复轮补充] 几何依赖性：P-RFO / B-P-RFO 需要鞍点猜测

本节补记一条**本文档与 27/28/30 原稿都没有说清**的前提（复核 31 的 MEDIUM-1 与几何依赖性
发现）：本报告的验收用例 HCN **不是**从极小点起步的，而是从**弯曲的 TS 猜测几何**
`H(0,1.05,0) Å, C(0,0,0), N(1.156,0,0)` 起步。P-RFO / B-P-RFO 的这个起点选择并非无关紧要：

- **prfo / bprfo 需要鞍点猜测**（或一个显式的过渡向量）。它们跟随 Hessian 的一个模
  （`--lts-target-mode` / `--lts-init-mode`），并在初始几何没有显著负曲率时改跟**最低内模**
  （`eigenfollow.f90:landscape_select_transition_mode`）。
- 从（近）驻点**极小点**起步时，跟随模的上升分量随梯度一同消失，**初始模型步是下降步**，
  仅靠选模修正并不能上坡：修正前的代码甚至在 `nneg=0` 时选到刚体零模（`index = 1`），
  步的上坡分量再被 `project_rigid` 抹掉。实测（GFN2 HCN 线性极小点 H(−1.0,0,0) Å）：
  修正选模但**关闭逃逸**时，prfo **3 步回到极小点**（E = −5.504066223602 Eh、0 虚频、
  exit 1，`confirmation: minimum (0 imaginary modes) - not a transition state`）。
- **最终修复轮**为这条路径加了**逃逸行走**（`prfo.f90:escape_from_minimum`，`--lts-escape-step`）：
  从极小点沿最低内模推走到曲率变负再开始搜索。实测同一线性极小点：
  7 push / 1.4 bohr 之后 prfo **5 步**、bprfo **7 步**收敛到与弯曲猜测**同一个**鞍点
  （E = −5.38737353 Eh，1 虚频，exit 0）。细节与两起点对照表见报告
  `32-m4-final-fix-report.md` 与 PLAN §9.5。
- 因此本报告 §2–§9 的数字（弯曲起点）本身仍然成立，但**不能**读作「从极小点也能启动」。
