# M2（scan）终轮修复报告（第 18 号）

> 输入：`docs/_landscape-recon/17-m2-independent-review.md` §3.1 / §3.2 / §3.3（3 条 MEDIUM）与 §4（LOW）
> 目标：全部修掉 3 条 MEDIUM，使 M2 可以宣称完成
> 纪律：所有 xtb 调用 `OMP_NUM_THREADS=1`；只跑 `-R landscape` 与 `-R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'`
> 结果：**M2 可宣称完成**（25/25 landscape + 12/12 回归全绿；3 条 MEDIUM 均以可证伪测试封口）

---

## 0. 结论

| 项 | 处置 | 证据 |
|---|---|---|
| §3.1 MEDIUM `result%converged` 语义 | **改字段**：`= (n_fail == 0) .and. (n_unconverged == 0)`，并改写 docstring 使「错误 / 告警」分工与代码一致 | 新测试 `scan-task-unconverged`；注入实验转红 |
| §3.2 MEDIUM rigid 守卫 + drift 判据 | 切割切不出两侧 → `env%error` + `fail`；每个 rigid 点按 `rigid_drift_tol = 1e−8` 检查 `wrapped(reached − target)`（1D 判错，2D 告警） | 新测试 `rigid-ring-cut-guard`、`rigid-drift-guard`；注入两项均转红 |
| §3.3 MEDIUM PLAN §9.3 验收项 2/4 | 改写为可达成且可证伪；drift 列改为**回绕差** | 新测试 `coord-wrap-delta`；CLI 实跑跨 ±180° 打印 0.00000000（不再 ±360） |
| §4 LOW | L1、L2、L5、L6 已修；L3、L4 见 §5（L4 的部分即 PLAN §4.3 补表，已做） | 见各节 |

---

## 1. M-1：`result%converged` 与 docstring 一致

### 1.1 选了什么，为什么

用户倾向的方案 (a)：**让字段本身要求「无失败点 且 无未收敛点」**。理由：

1. 自动化消费的是字段，不是 stdout 消息。旧定义让「部分点未收敛」的扫描返回 `converged = .true.`，
   任何只看该字段的调用方（含后续 M3..M7 的任务结果复用）无法区分。
2. 与 `xtb_landscape_tasks_opt`（未收敛极小化 → 非零退出）的"对标"承诺此时才成立一半。

**没有**把未收敛点升级为 `env%error`（即不改 CLI 退出码）：PLAN R-04 要求的是**可见**，而扫描点
允许宽松收敛；把它变成硬错误会让一次正常但稍松的扫描整体失败，属超出本任务的行为变更。
因此同步把 docstring 的"错误"承诺收窄到它的真实含义：

- 无能量的点（单点失败）→ `env%error`（与 `tasks/opt.f90` 一致，非零退出）；
- 未收敛但有能量的点 → `env%warning` + 逐点 residual，且令 `result%converged = .false.`。

docstring 现在逐句对应代码，`:67-70` 与 `:215` 不再互相矛盾。

### 1.2 改动

| 文件:行 | 改动 |
|---|---|
| `src/landscape/tasks/scan.f90:67-76` | docstring 重写：两类不完整点分别说明其对 `result%converged` 与对退出码的影响 |
| `src/landscape/tasks/scan.f90:190-192` | `result%converged = (n_fail == 0) .and. (n_unconverged == 0)` |
| `test/unit/CMakeLists.txt`（`xtb/landscape-scan-cli`） | 追加 `if(output MATCHES "scan completed with unconverged points")` 断言，堵掉 §3.1 指出的「子串命中」盲区 |

### 1.3 新测试 `scan-task-unconverged`（真 GFN2）

构造「有未收敛点、但没有失败点」：`set%max_steps = 1` + `set%conv_level('vtight')`，水分子 O–H 距离 3 点扫描。
每个内层极小化只走一步、必定不达阈值，但仍返回几何与能量 ⇒ 无点失败（`n_fail == 0`）、
每个点都进 `xtbscan.log`、每点 `conv = F`。

断言：`landscape_log_failed == .false.`（无硬失败）、`frames == result%n_steps`（无点丢能量，
即确证 `n_fail == 0`）、`result%converged == .false.`。

> 注：CLI 目前**没有** `--lscan-max-steps` 开关（`src/xhelp.f90` 的 `--lscan-*` 全集里没有），
> 所以这条路径只能在单元层驱动。已实测 `--lscan-method sd --lscan-level vtight` 的 CLI 扫描
> 5/5 点仍全收敛，无法在 CLI 层构造该场景。

---

## 2. M-2：rigid 守卫 + 漂移判据

### 2.1 切割守卫（消除机制）

`landscape_scan_rigid_geometry` 的每个分支在拿到片段掩码后立即调用新的
`landscape_scan_check_cut`：若 `moving(blocked)` 为真（切不出两侧：环、非成键切割、
或距离截断图上的跨切割伪桥接），`env%error` + `fail = .true.` + `return`，**不静默继续**。
四个调用点（distance 两个片段、angle、dihedral）全覆盖。

为什么这条就是原 bug 的机制关闭：伪桥接必然经近侧连通图回到被挡原子 `j`，
所以守卫必然触发——触发条件从"静默冻结"变成"报错停止"。

### 2.2 漂移判据（运行期检查）

`landscape_scan_rigid_point` 在构造完几何、算出 `point%values(i)` 之后、单点评估之前，
对每个坐标算 `drift = wrap(reached − target)`；`|drift| > rigid_drift_tol` 时：

- `ncoord == 1` → `env%error` + `fail = .true.`（点无效，无能量）；
- `ncoord == 2` → `env%warning`（2D rigid 的两次刚体操作互相扰动是**固有**的，不是错误）。

**阈值选 `1.0e-8`（bohr / rad）的理由**：rigid 是纯几何构造，1D 的到达值除浮点舍入外应为 0。
实测 DCE 扫描逐点 drift `< 5e-9` 度（`16`§3），即观测噪声约 `8.7e-11` rad；取 `1e-8` rad
≈ 观测值的 `1e2` 倍余量，仍比最细扫描步（CLI 最小步约 `1e-3` rad）小 5 个数量级，
既不会误报也不会漏报"坐标没动"（这种漂移就是整个步长量级）。

**结构上的诚实说明**：掩码仍逐点重算在演化几何上（R9-a 的结构化修法留 M4），
因此 `landscape_scan_rigid_geometry` 的 docstring 已改为事实描述（"切割必须分离两侧，
否则报错"），删掉了原先"环上 rigid 仅对被扫坐标有意义"这种过于宽容的措辞。

### 2.3 新测试（两条，均实测注入转红）

- `rigid-ring-cut-guard`：等边三角形（3×C，边长 2.8346 bohr < 1.2·(r_cov+r_cov)），
  切一条边切不开 ⇒ 断言 `fail == .true.` 且 `landscape_log_failed == .true.`。
- `rigid-drift-guard`：**守卫不能捕获**的场景——1 与 3 互成键、但都与中心原子 2 不成键
  （角 1–2–3 = 30°，两腰 2.0 bohr > H–H 阈值 1.451 bohr，1–3 = 1.035 bohr < 阈值）。
  片段 = `{1,3}`，绕轴转 `{1,3}` 时**两个端点同时转**，被扫角**完全不变**。
  先断言默认切割守卫**不**报错（证明拒绝来自 drift 判据而非守卫），再断言
  `landscape_scan_rigid_point` 的 `fail == .true.`、`point%converged == .false.`、且记录的是 error。
- `scan-2d-bookkeeping` 追加：2D rigid 耦合漂移**必须**告警（`env%nLog` 增加）且**不得**是 error。

---

## 3. M-3：PLAN §9.3 验收项改写 + drift 列回绕

### 3.1 代码

新增共享定义 `xtb_landscape_scan_relax::landscape_scan_coord_wrap_delta(ctype, delta)`：

- distance：非周期，原样返回；
- angle / dihedral：`wrapped = modulo(delta + pi, 2*pi) − pi`，值域 `[−pi, pi)`。

`scan1d` 的 `drift` 列改用它（`src/landscape/scan/scan1d.f90:441`），
所以 1D 输出表显示的**就是**回绕差，与 rigid 判据、与 PLAN 验收项同一定义。

### 3.2 PLAN §9.3 改写（可达成 + 可证伪）

- 项 2 分成两模式：
  - rigid：`wrapped(reached − target) == 0`，容差 `1e−8`（= 运行期判据 `rigid_drift_tol`）；
  - relaxed：`reached − target` 等于约束弹簧的**已知**偏移 `F_phys(q*)/(2 fc)`
    （§5.3.5 实测：fc=0.5 约 0.82°、fc=0.05 约 6.84°），**不要求为 0**；
  - 并写明 stdout 表 `drift = wrapped(reached − value)`，回绕到 `(−180°, 180°]`。
- 项 4：`reached == value` → `wrapped(reached − target) == 0`（同容差）。
- 顺带：把 §9.3 标题改为「M2（已实现）」，表格补 LOC 实/估与状态，补「M2 验收测试」一行；
  §4.3 边界表补 `constr_setvar` 与 `bangl`/`valijkl` 两行（§4 L4 的文档部分）；
  §9.3 补 Hessian 策略项（§4 L6）。

### 3.3 端到端验证（跨 ±180°）

`OMP_NUM_THREADS=1 xtb dce.xyz --gfn2 --lscan --lscan-mode rigid --lscan-coord dihedral
--lscan-atoms 3,1,2,4 --lscan-step -30 --lscan-nstep 4 --norestart`（DCE = 1,2-二氯乙烷 8 原子）：

```
    point      value/deg reached/deg drift/deg         energy/Eh      residual      steps  conv
        1    -179.98661864    -179.98661864       0.00000000     -15.416221829985   9.0927E-05      0 T
        2    -209.98661864     150.01338136       0.00000000     -15.413778338629   1.7172E-04      0 T
        3    -239.98661864     120.01338136       0.00000000     -15.410904512406   3.9695E-03      0 T
        ...
        9    -179.98661864    -179.98661864       0.00000000     -15.416221829985   9.0927E-05      0 T
 hysteresis: points compared 4
```

第 2 点目标 −209.99°、到达 +150.01°：几何是对的（回绕），`drift` 列打印 **0.00000000**，
而不是修复前的 **+360.00**。反向支逐点重建同一位形/能量 ⇒ 第 4 项（滞回 ≤ 1e−14）依旧成立。
`status = 0`。

---

## 4. 测试清单与真实输出

新增/扩充的 case（全部在既有 `landscape-scan` testsuite 内，无需新增 ctest 目标，故无重名风险）：

| case | 覆盖 |
|---|---|
| `coord-wrap-delta`（新） | 回绕函数四种输入（distance 不变、±356° → ∓4°、350° → −10°、12° 不动） |
| `rigid-ring-cut-guard`（新） | 切不开 ⇒ error + fail |
| `rigid-drift-guard`（新） | 守卫通过但到不了目标 ⇒ error + fail（1D drift 判据） |
| `scan-task-unconverged`（新） | 任务级 `result%converged` 的未收敛分支 |
| `scan-2d-bookkeeping`（扩） | 2D rigid 耦合漂移**告警不报错** |
| `scan-missing-energy`（扩） | 无效点的 `total` 为 NaN（L5）；全失败双向扫描 `n_compared == 0`（L1） |

`ctest -N -R landscape` = **25** 个目标，与实跑数一致（无撞名丢测）。

```
$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape
100% tests passed, 0 tests failed out of 25        (其中 xtb/landscape-scan 27/27 case)

$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build \
      -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
100% tests passed, 0 tests failed out of 12
```

`xtb/landscape-scan` 的 27 个 case 名称（顺序即运行顺序）：
`coord-value, coord-gradient-finite-difference, coord-name-roundtrip, coord-wrap-delta,
rigid-distance-exact, rigid-angle-exact, rigid-dihedral-fragment, rigid-dihedral-scan,
rigid-ring-cut-guard, rigid-drift-guard, relaxed-scan-profile, relaxed-scan-residual,
scan-hysteresis-report, rigid-scan-hysteresis-zero, scan-2d-grid, scan-invalid-coordinate,
scan-atom-out-of-range, scan-zero-nstep, scan-unknown-mode, scan-unknown-method,
scan-missing-energy, scan-2d-bookkeeping, scan-task-gfn2, scan-task-unconverged,
scan-task-missing-energy, scan-task-no-energy, scan-task-invalid`。

---

## 5. 可证伪性：四条注入实验（真实输出）

每次都只改被测逻辑、重建、跑 `ctest -R '^xtb/landscape-scan$'`，随后还原。

### 注入 1 — M-1：`result%converged` 退回旧定义
```
- result%converged = (n_fail == 0) .and. (n_unconverged == 0)
+ result%converged = n_fail == 0
```
```
   Starting scan-task-unconverged ... (24/27)
        ... scan-task-unconverged [FAILED]
   Message: a scan with unconverged points claimed to be converged
0% tests passed, 1 tests failed out of 1
```

### 注入 2 — M-2 drift 判据：`rigid_drift_tol = 1.0_wp`
```
   Starting rigid-drift-guard ... (10/27)
        ... rigid-drift-guard [FAILED]
   Message: a rigid point that cannot reach its target was accepted
        ... scan-2d-bookkeeping [FAILED]
   Message: the drift of the disturbed coordinate was not reported
```
（同一注入同时打掉 1D 判错分支与 2D 告警分支 ⇒ 两条判据都被测到。）

### 注入 3 — M-2 切割守卫：`landscape_scan_check_cut` 直接 `return`
```
   Starting rigid-ring-cut-guard ... (9/27)
        ... rigid-ring-cut-guard [FAILED]
   Message: a rigid scan of an unseparated cut was accepted
   Starting rigid-drift-guard ... (10/27)
        ... rigid-drift-guard [PASSED]
```
（`rigid-drift-guard` 仍绿是**预期**：它证明自己的场景与守卫无关，拒绝只可能来自 drift 判据。）

### 注入 4 — M-3 回绕：`wrapped = delta`（不取模）
```
   Starting coord-wrap-delta ... (4/27)
        ... coord-wrap-delta [FAILED]
   Message: Floating point value missmatch
            expected 0.69813170079773182E-1 but got -6.2133721370998130 (difference: 6.2831853071795862)
```
（`-356°` 的差被判成 `-6.283 rad = -360°`，正是 §3.3 的 ±360° 伪影。）

### 注入 5 — L1：去掉 `n_compared` 前的 `energy_valid` 门
```
   Starting scan-missing-energy ... (21/27)
        ... scan-missing-energy [FAILED]
   Message: a scan without energies reported compared grid points
```

---

## 6. §4 LOW 的处置

| # | 处置 | 说明 |
|---|---|---|
| L1 `n_compared` 无条件自增 | **已修** | `scan1d.f90:361-362` 自增前跳过无能量的配对；新测试断言全 NaN 双向扫描 `n_compared == 0`（注入 5 转红） |
| L2 rigid 失败分支漏设 `fail` | **已修** | `relax_scan.f90` rigid 的非有限能量分支补 `fail = .true.`（一行） |
| L3 `res%gnorm` 单位标签 | **未做**（记录） | 属既有报告层（`src/prog/main.F90:959` + `src/main/property.F90:51`）的标签问题：距离扫描写的是 Eh/bohr（与标签同量纲）只错在角度/二面角的 Eh/rad。修它要动被本任务排除的 `src/main/property.F90` 打印契约，收益/风险比不划算，留待有需要时统一处理 |
| L4 边界表与 `13`§5 表述 | **部分已做** | PLAN §4.3 补了两行（`constr_setvar`、`bangl`/`valijkl` → `scan/*`）。`13-*.md` 是历史报告，按其"过程记录"性质不改写 |
| L5 无效点的 `total`/`bias` 仍是 0.0 | **部分已做** | `point%total` 在两个点的初始化处改为 `landscape_missing_value()`，并由 `scan-missing-energy` 断言（1D + 2D）；`bias`（rigid 的 0 是**真值**）与无效点的 `n_steps = 0` 未动，二者当前无读者 |
| L6 `--lscan-method rfo` 无对应 Hessian 开关 | **已记录** | PLAN §9.3 新增一段写明该策略项：`--lopt-hessian` 只作用于 `lset`，扫描只能从 API 设 `hessian_source`；加 `--lscan-hessian` 留 M3 |

---

## 7. 改了哪些行（汇总）

实现（≈ 40 行净增，含文档注释）：

- `src/landscape/tasks/scan.f90`：docstring（`67-76`）+ `result%converged`（`192`）
- `src/landscape/scan/relax_scan.f90`：
  - `rigid_drift_tol = 1.0e-8_wp`（`106`）+ 文档
  - `landscape_scan_coord_wrap_delta`（`269-283`）+ 导出
  - `landscape_scan_check_cut`（`985-1003`）+ 4 个调用点（`918,920,939,964`）
  - rigid 点 drift 判据（`780-805`）
  - rigid 失败分支补 `fail`（`809`）
  - `point%total` 两处初始化改 NaN（`641`、`754`）
  - `real_to_string`（`1126-1137`）
- `src/landscape/scan/scan1d.f90`：`drift` 列回绕（`441`）、`n_compared` 门（`361-362`）、导入（`63`）、表头注释
- `test/unit/CMakeLists.txt`：CLI 扫描测试的"未收敛"反断言
- `test/unit/test_landscape_scan.f90`：4 个新 case + 2 个扩写（≈ +180 行）
- `docs/xtb-landscape-PLAN.md`：§4.3 两行、§9.3 标题/表格/验收项 2&4/rigid 运行期判据/Hessian 策略项

未改：`main.F90` 的 `res` 回写、`scan2d` 逻辑、引擎层、其余既有测试。
数值卫生未回退（无裸 `real`、无 `stop`、无 module 级可变量、内部 a.u.、`!>` 文档注释齐备）。

---

## 8. 残留风险 / 留给下一轮

1. **未收敛扫描的 `result%energy` 是 NaN**（既有行为）：任务层的"最低能量点"搜索要求
   `profile%converged(i) .and. energy_valid(i)`，所以一个**所有点都未收敛**的扫描现在会得到
   `converged = .false.` + `energy = NaN`，而逐点能量其实都存在。语义上自洽（"没有任何可信点"），
   但对只想拿剖面最低点的调用方是信息损失。**属设计决策，不在本轮 3 条 MEDIUM 之内，未改**；
   若要改，应与 2D 的 `min_energy` 判据一并定，建议 M3 顺带评估。
2. rigid 掩码仍逐点重算在演化几何上（R9-a）。守卫把"静默冻结"变成"报错停止"，
   但结构化修法（掩码固定在参考几何、rigid 点由"参考几何 + 累计角"构造）留 M4。
3. 2D rigid 的坐标 1 漂移是**信息**而非错误（告警）；调用方若需要精确的多坐标 rigid 点，
   应改用 relaxed 或串行单坐标扫描。
4. CLI 无 `--lscan-max-steps`，未收敛路径只有单元层覆盖（见 §1.3）。
5. `bias`（无效点）与 `n_steps`（无效点）仍是 0.0/0（无读者），L5 只修了 `total`。

---

## 9. M2 是否可宣称完成

**可以。** 独立复核的 3 条 MEDIUM 全部修掉且各有可证伪测试 + 注入证据；
§4 LOW 中 4 条已修、2 条书面记录（L3 属既有报告层，L5 只做了有读者的部分）；
`ctest -R landscape` 25/25、回归 12/12 全绿；PLAN §9.3 已按「已实现」定稿并含可达成验收判据。
建议的下一步是 M3（Hessian / freq / thermo / `hessian_source=file`），并把 §8.1 与 L6 的
`--lscan-hessian` 一并纳入 M3 范围。
