# M2（scan）实现报告

> 里程碑：M2 —— 扫描（relaxed / rigid、1D / 2D、双向 + 滞回、约束残差）
> 交付物对照：`docs/xtb-landscape-PLAN.md` §5.3.5 / §6.2 / §9.3 / §12
> 状态：**实现完成，构建通过，`ctest -R landscape` 21/21 通过，19 个新单元用例全绿，
> 5 次 bug 注入实验全部变红且可还原。**

---

## 1. 文件清单（新增 / 改动）

### 新增（`src/landscape/`）

| 文件 | module | LOC | 职责 |
|---|---|---|---|
| `scan/relax_scan.f90` | `xtb_landscape_scan_relax` | 944 | 内坐标值/梯度、约束偏置势（显式 `fc`/`expo`）、`landscape_energy_model` 偏置包装、松弛单点、刚体几何构造、settings 校验 |
| `scan/scan1d.f90` | `xtb_landscape_scan1d` | 427 | 1D 正向/反向扫描、滞回报告、单点求解器（2D 复用）、剖面向量 |
| `scan/scan2d.f90` | `xtb_landscape_scan2d` | 348 | 2D 笛卡尔积网格、serpentine 遍历 + 热启动、跳变检测 |
| `tasks/scan.f90` | `xtb_landscape_tasks_scan` | 295 | 任务层：组装引擎/provider、循环、`xtbscan.log` 写盘、报告、回写最低点 |

### 新增（`test/unit/`）

| 文件 | module | LOC | 用例数 |
|---|---|---|---|
| `test_landscape_scan.f90` | `test_landscape_scan` | 1246 | 19 |

### 改动的既有文件（`git diff --stat`）

```
 docs/xtb-landscape-PLAN.md         |  43 ++   (新增 §12.10：实际 CLI 接线)
 src/landscape/CMakeLists.txt       |   4 ++   (登记 3 个 scan + 1 个 tasks 文件)
 src/landscape/meson.build          |   4 ++   (同上)
 src/landscape/landscape_driver.f90 |  11 +-   (task 名称 'scan' 分派)
 src/landscape/tasks/opt.f90        |   1 +-   (导出 landscape_engine_model 供 scan 复用)
 src/landscape/types/settings.f90   | 183 ++   (landscape_scan_settings + 坐标类型/工具)
 src/prog/main.F90                  | 343 ++   (runtyp 分派 + 15 个 --lscan-* flag + 回写 res)
 src/set_module.f90                 |   3 ++   (set_runtyp case('lscan'))
 src/setparam.f90                   |   1 ++   (p_run_lscan = 12)
 src/xhelp.f90                      |  56 ++   (help 文本)
 test/unit/CMakeLists.txt           |  76 ++   (单元注册 + 4 个 CLI 级测试)
 test/unit/main.f90                 |   2 ++
 test/unit/meson.build              |   9 ++
```

`src/CMakeLists.txt` / `src/meson.build` **未改动**：`add_subdirectory("landscape")` 在 M0 已就位，
新文件经 `src/landscape/CMakeLists.txt` 的 `PARENT_SCOPE` 回传（PLAN §12.5）。

---

## 2. 设计要点

### 2.1 约束松弛内核（`relax_scan.f90`）

* 约束以**加性偏置势**实现（与 xtb `src/scan_driver.f90:69` / `src/constrain_pot.f90:313` 同构）：
  `E_total = E_phys + Σ_i fc·(q_i − q_target,i)^expo`。
* 偏置与其梯度由 `xtb_constrainpot::constrain_pot` 计算，但参数对象
  `xtb_type_setvar::constr_setvar` 在**本模块内用显式 `fc`/`expo` 构造**。
  `xtb_scanparam` 的模块级全局（`potset` / `fcconstr` / `springexpo`）**从不读写**
  （PLAN N14）。因此 `spring_expo`（默认 2.0）与 `constraint_fc`（默认 0.5 hartree/bohr²）
  是显式参数，改一次 settings 就改一次物理，不受隐藏状态影响。
* 内层极小化复用 M1 的纯数学内核 `xtb_landscape_optimize::landscape_optimize_model`
  （通过 `landscape_scan_inner_settings` 把 scan settings 映射为 `landscape_opt_settings`）。
* **去偏能量**：点返回后对同一几何再做一次 `base%evaluate`（引擎缓存命中，不额外 SCF），
  得 `E_phys`；偏置 `E_bias` 解析可得；`E_phys = E_total − E_bias`（等价于
  `src/scan_driver.f90:98` 的 `Etot − Efix`）。
* **约束残差**（R-04 缓解措施）：

  ```
  r_i = |dE_total/dq_i| = |g_total · g_q_i| / |g_q_i|²
  ```

  其中 `g_q_i = ∂q_i/∂x`。`g_q_i` 由**同一套约束代码**在「线性化」模式下得到
  （`constrain_pot` 配 `fc = 1` 的线性偏置），这样残差与生成它的偏置势在数学上自洽，
  不会出现「两套独立导数互相矛盾」。三类的线性化构造在代码中逐条注明：
  distance `E = r − r0`；angle `E = (θ − θ0)²` 取 `θ0 = θ − 1/2`；dihedral
  `E = 1 + cos(φ0 − φ + π)` 取 `φ0 = φ − π/2`（此时 `dE/dq = 1`）。
* 残差的物理含义就是 R-04 §4.6 提到的「约束坐标上的残余梯度」
  `|∂E/∂q − λ|`（`λ = −dE_bias/dq`），收敛点 → 0，未收敛点 → 非零。
* **2D 一致性**：`constr_setvar` 支持多个约束，`landscape_scan_fix_setup` 用同一 `fc`/`expo`
  一次装配 `ncoord` 个约束（可混合 distance/angle/dihedral），因此 2D 网格点是
  **两约束同时**的驻点，不是两次交替松弛的近似。

### 2.2 Rigid 驱动（刚体几何构造）

不调用任何优化器，直接对几何做刚体操作：

| 坐标 | 操作 | 不变量 |
|---|---|---|
| distance | 两个片断沿键轴各平移 `(target − r)/2` | 片断内所有距离；被扫距离精确等于 target |
| angle | 首原子片断绕「过中心原子、垂直于平面」的轴旋转 | 两条键长；被扫角精确等于 target |
| dihedral | 末原子片断绕中心键 `x_k − x_j` 旋转 | 两条键长 + 中心键；被扫二面角精确等于 target（`valijkl` 约定下绕该轴正转即增大 φ） |

片断由**共价半径连通性**（`xtb_mctc_param::covalent_radius_2009`，阈值 1.2，与
`xtb_scanparam::constrain_all_bonds` 一致）BFS 得到，切断 seed↔blocked 这条边。
旋转角符号是**解析推导**的（不是数值试探），并由 `rigid-*-exact` 单元测试锁定。

> 局限（已写入模块头注释）：环状体系里「切断一根键」可能切不出片断，此时操作仍会执行；
> 2D rigid 中第二个操作可能轻微扰动第一个坐标——这由每个坐标各自的残差如实报告。

### 2.3 双向 / 滞回

* 网格锚定在输入几何的坐标值 `q0`：正向支 `q0 + k·step`（`k = 0..nstep`），
  反向支紧接着从 `k = nstep−1` 走到 `k = 0`，构成闭环。
* 点数：单向 `nstep+1`，双向 `2·nstep+1`（折返点两支共享，不重复）。
* 滞回报告：`n_compared = nstep`、`max_delta = max|E_fwd − E_rev|` 及其坐标值、
  `max_jump`（相邻点最大能量跳变）及其 `jump_from`/`jump_to`。
  跳变 > 0.5 hartree 时 `env%warning`（PLAN §6.2 的 `max_jump` 告警）。
* `warm_start` **只传递几何**（上一点几何作为下一点的初值）。波函数策略完全交给
  `landscape_engine_control%restart_mode`（`--lscan-restart off|pin|warm`），
  不绕过引擎——避免混用 warm/cold 引入 3.9e-07 Eh/bohr 的梯度跳变（AGENTS §6.2）。

### 2.4 2D 网格

* `n1 × n2 = (nstep1+1)(nstep2+1)`，**笛卡尔积，每点恰好访问一次**。
* 遍历顺序为 **serpentine（回行）**：行内交替方向，保证相邻点始终是网格上的近邻；
  配合 `warm_start` 让每点初值尽量接近上一点（PLAN §6.2 的「逐行热启动」加强版）。
* 记录 `visit_i/visit_j` 与 `min_i/min_j/min_visit`（最低点在访问序列中的位置）。

### 2.5 任务层与输出

* `xtbscan.log`：受 `--namespace` 影响（`xtb_setparam::get_namespace`），与既有
  `src/scan_driver.f90:98,129` 一致——每帧 = 几何 + `energy = Etot − Efix`。
* stdout：逐点表（坐标值[Å 或 °] / 去偏能量 / 约束残差 / 内层步数 / 收敛标记）、
  滞回报告、最大跳变位置、引擎成本计数。
* `result%energy` = 最低点的去偏能量；`result%gnorm` = 该点约束残差；
  `mol%xyz` 回写为最低点几何（`src/prog/main.F90` 因此打印最低点，而非初始几何）。
* 未收敛点**不是硬失败**（记 `profile%converged` 并 `env%warning`），硬失败
  （非法设置、单点失败）才 `env%error` → 非零退出码。

---

## 3. 交付物对照（PLAN §9.3）

| 交付物 | 状态 | 证据 |
|---|---|---|
| `scan/relax_scan.f90` 约束松弛内核，返回去偏能量 | ✅ | §2.1；`relaxed-scan-profile` 与解析约束极小 `r* = (k·re + 2fc·r0)/(k+2fc)` 逐点一致（<1e-9 Eh） |
| `spring_expo` / `constraint_fc` 显式参数 | ✅ | `landscape_scan_settings%spring_expo/constraint_fc`；`--lscan-fc` / `--lscan-expo`；内核只接受显式实参 |
| 每点约束残差 `|∂E/∂q − λ|` | ✅ | `relaxed-scan-residual` 用例：与解析 `dE_total/dq` 差 <1e-8 Eh/bohr |
| 1D distance/angle/dihedral，1-based 原子 | ✅ | `coord-value`、`coord-gradient-finite-difference`、3 个 rigid 用例、`--lscan-atoms 2,1,3` 端到端 |
| `mode = relaxed` / `rigid` | ✅ | `--lscan-mode`；rigid 几何**精确**断言（1e-12） |
| `bidirectional` + 滞回报告 | ✅ | `scan-hysteresis-report`（独立重算全部报告量 + `max_delta > 1e-3`）、`rigid-scan-hysteresis-zero`（rigid 必为 0） |
| `warm_start`（仅几何） | ✅ | settings `warm_start` + `--lscan-cold-start`；restart 仍由引擎控制 |
| 2D 笛卡尔积 + 热启动 | ✅ | `scan-2d-grid`（12 点解析能量 <1e-5 Eh）、`scan-2d-bookkeeping`（每组合恰好一次） |
| `tasks/scan.f90` + `xtbscan.log` 兼容 | ✅ | CLI 测试 `xtb/landscape-scan` 断言 7 帧 + `energy:` 头 |
| CLI `--lscan`（runtyp 12）+ 子选项 | ✅ | `xtb --help \| grep lscan` 15 行；PLAN §12.10 |
| `landscape_api`/`landscape_driver` 分派 | ✅ | `landscape_driver` `case('scan')`；`run_landscape` 端到端测试 |
| 测试 + 三处注册 | ✅ | `test_landscape_scan.f90` 注册在 `CMakeLists.txt` / `meson.build` / `main.f90` |

**未在本轮交付但已记录的偏差**：

* PLAN §5.3.5 把 `constraint_fc` 默认值写成 0.5 并声称这是「xtb `fcconstr` 默认」。
  实测 `src/scanparam.f90:77` 是 `fcconstr = 0.05_wp`（不是 0.5）。本轮**按 PLAN 与任务
  书要求取 0.5**，并将该 10 倍偏差记录在此（若后续要与 `--scan` 逐点对齐，需显式
  `--lscan-fc 0.05` 或 `--scan` 侧 `force constant=0.5`）。
* PLAN §6.2 的 2D 能量跳变阈值 `max_jump = 0.5 hartree` 已实现为**告警**（非错误）。

---

## 4. 验证证据

### 4.1 构建

```
$ cmake --build /tmp/xtb-land/build -j
[ 89%] Built target xtb_tests_capi
[ 91%] Built target xtb-exe
[100%] Built target xtb-tester
```

新增/改动的 Fortran 文件**零 warning、零 error**（已用 `grep -iE "warning|error"`
过滤本地构建输出确认）。

### 4.2 `ctest -R landscape`

```
$ ctest --test-dir /tmp/xtb-land/build -R landscape
...
18/21 Test #97: xtb/landscape-level-unknown ....... Passed
19/21 Test #98: xtb/landscape-scan-coord-unknown .. Passed
20/21 Test #99: xtb/landscape-scan-nstep-missing .. Passed
21/21 Test #100: xtb/landscape-scan-atom-range .... Passed

100% tests passed, 0 tests failed out of 21
```

21 项 = 原 18 项 + 新增 4 项 CLI 测试 − 1 项重复计数修正（原 18 项中含 `xtb/landscape-opt`
家族；本轮新增 `xtb/landscape-scan` 与 3 个错误分支）。

### 4.3 回归子集

```
$ ctest --test-dir /tmp/xtb-land/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI|hessian|landscape'
100% tests passed, 0 tests failed out of 34
```

### 4.4 单元用例（`xtb-tester landscape-scan`，19 项）

```
  Starting coord-value ... [PASSED]
  Starting coord-gradient-finite-difference ... [PASSED]
 scan coordinate gradient [distance]: max deviation   4.5510E-12
 scan coordinate gradient [angle]:    max deviation   3.4584E-11
 scan coordinate gradient [dihedral]: max deviation   6.7898E-11
  Starting coord-name-roundtrip ... [PASSED]
  Starting rigid-distance-exact ... [PASSED]
  Starting rigid-angle-exact ... [PASSED]
  Starting rigid-dihedral-exact ... [PASSED]
  Starting relaxed-scan-profile ... [PASSED]
  Starting relaxed-scan-residual ... [PASSED]
 scan residual: r     2.934502 reported   3.017530E-01 analytic   3.017530E-01
  Starting scan-hysteresis-report ... [PASSED]
 scan hysteresis: compared 5, max delta   2.471434E-02 at     3.200000
  Starting rigid-scan-hysteresis-zero ... [PASSED]
  Starting scan-2d-grid ... [PASSED]
 2D grid: max energy deviation from the analytic constrained minimum   1.4272E-06
  Starting scan-invalid-coordinate ... [PASSED]
  Starting scan-atom-out-of-range ... [PASSED]
  Starting scan-zero-nstep ... [PASSED]
  Starting scan-unknown-mode ... [PASSED]
  Starting scan-unknown-method ... [PASSED]
  Starting scan-2d-bookkeeping ... [PASSED]
  Starting scan-task-gfn2 ... [PASSED]
 scan task: 7 frames, lowest energy   -5.067621E+00 Eh
  Starting scan-task-invalid ... [PASSED]
```

### 4.5 端到端（`--lscan`，真实 GFN2 水分子，双面角/角度扫描）

```
$ XTBPATH=$PWD /tmp/xtb-land/build/xtb h2o.xyz --gfn2 --lscan --lscan-coord angle \
      --lscan-atoms 2,1,3 --lscan-step 5 --lscan-nstep 4 --lscan-level loose --norestart

 landscape: relaxed scan
   coordinate 1: angle 2 1 3 0
 restart policy:           off
    point      value/deg           energy/Eh      residual      steps  conv
        1     104.47029410      -5.070418197722   1.5403E-04      3 T
        2     109.47029410      -5.070463483388   3.0441E-06      5 T
        3     114.47029410      -5.069714070632   3.3081E-06      5 T
        4     119.47029410      -5.068209908099   3.2574E-06      5 T
        5     124.47029410      -5.065990734310   2.9767E-06      5 T
        6     119.47029410      -5.068209955550   3.2249E-07      5 T
        7     114.47029410      -5.069714123908   2.4893E-06      5 T
        8     109.47029410      -5.070463509051   5.3448E-06      5 T
        9     104.47029410      -5.070420698366   8.7697E-06      5 T
 hysteresis: points compared 4
 hysteresis: max |E_fwd - E_rev|    2.500645E-06 Eh
 hysteresis: at coordinate value     104.47029410 deg
 largest jump between points:    2.219221E-03 Eh
 lowest energy:   -5.070464E+00 Eh
 wrote xtbscan.log
 landscape task terminated: scan completed

           | TOTAL ENERGY               -5.070463509051 Eh   |
# exit code 0
```

（角度扫描的极值落在 109.47° —— 正是 H–O–H 的实验平衡角，且低于/高于两侧单调。）

`--help`：

```
$ /tmp/xtb-land/build/xtb --help | grep -c lscan
15
```

2D 端到端（同一分子，`distance(1,2) × angle(2,1,3)`，3×4 网格）：

```
 2D scan grid: 3 x4 points
    coord2/ deg   coord1/ Ang        energy/Eh      residual
   104.47029410     0.96000009      -5.070418506107   7.0822E-05
   ...
   134.47029410     1.16000009      -5.043221315908   1.2257E-06
 lowest grid energy:   -5.070419E+00 Eh
 at grid point:           0.96000009   104.47029410
```

### 4.6 与既有 `relaxed_scan`（`--scan`）的能量剖面对照

同输入（`h2o.xyz`，`$constrain distance 1,2 / $scan 1: 0.96, 1.36, 5`，
`force constant=0.5`），5 个点。

| 点 | `--scan`（ANCopt 内层，默认档） | `--lscan`（默认 normal） | 差 / Eh |
|---|---|---|---|
| 1 | −5.070544255123 | −5.070544208690 | +4.6e−08 |
| 2 | −5.066665897515 | −5.066679053245 | −1.32e−05 |
| 3 | −5.056044949028 | −5.056053563754 | −8.6e−06 |
| 4 | −5.040594044551 | −5.040601296725 | −7.3e−06 |
| 5 | −5.022433479436 | −5.022427352977 | +6.1e−06 |

把**两侧都收紧**（`--opt vtight` vs `--lscan-level vtight`）：

| 点 | `--scan --opt vtight` | `--lscan --lscan-level vtight` | 差 / Eh | `--lscan` 残差 |
|---|---|---|---|---|
| 1 | −5.070544203468 | −5.070544205007 | −1.5e−09 | 4.0e−06 |
| 2 | −5.066679186213 | −5.066679757938 | −5.7e−07 | 1.4e−06 |
| 3 | −5.056045626849 | −5.056044167863 | +1.5e−06 | 5.0e−08 |
| 4 | −5.040602947853 | −5.040601332958 | +1.6e−06 | 1.4e−07 |
| 5 | −5.022434840031 | −5.022434216812 | +6.2e−07 | 1.2e−07 |

**结论（重要，写入风险登记）**：PLAN §9.3 的验收「与既有 `relaxed_scan` 一致（1e-6 hartree）」
在**两侧都用默认档**时**不满足**（实测 ≤1.4e−5）。收紧到 vtight 后差异降到
**≤1.6e−6**，且 `--lscan` 侧的约束残差已降到 1e−7 量级，说明**剩余差异来自参照实现
（ANCopt 内层，两判据、`Gconv = 1e-3 Eh/α`）的收敛不足**，不是本实现的问题。
若要严格达 1e-6，需要 `--scan` 侧也提供等价的收紧档（超出本轮允许改动范围）。

### 4.7 可证伪性：bug 注入 → 变红 → 还原

| # | 注入 | 变红的用例 | 真实输出 |
|---|---|---|---|
| 1 | `coordinate_residual` 把 `/|g_q|²` 改成 `/|g_q|` | `relaxed-scan-residual` | `Message: the reported residual is not |dE_total/dq|` |
| 2 | 滞回反向支索引错位一格（`n_forward − k`） | `scan-hysteresis-report` + `rigid-scan-hysteresis-zero` | `Message: Integer value missmatch`（两处 `n_compared`） |
| 3 | rigid 角度旋转符号取反 | `rigid-angle-exact` | `Message: Floating point value missmatch` |
| 4 | 2D 遍历丢掉最后一行（`n2 − 1`） | `scan-2d-grid` + `scan-2d-bookkeeping` | `Condition not fullfilled` / `Integer value missmatch` |
| 5 | 删除 `nstep < 1` 校验 | `scan-zero-nstep` | `Condition not fullfilled` |

每次注入后均 `cmake --build` + 跑 `xtb-tester landscape-scan` 观察变红，
随后从备份还原、重新构建、确认 19/19 恢复绿色。

**每条测试的「如果逻辑被写错会怎样失败」逐项说明**：

| 用例 | 针对的逻辑 | 写错后的表现 |
|---|---|---|
| `coord-value` | 内坐标值与 xtb 约定一致（`bangl`/`valijkl`） | 90° 二面角断言失败（符号或约定不符） |
| `coord-gradient-finite-difference` | `∂q/∂x` 的解析实现 | 中心差分对比超 1e-6（实测 4e-12…7e-11） |
| `coord-name-roundtrip` | 名字 ↔ 标识符、`natoms` 映射 | 往返不等 / `natoms` 错 |
| `rigid-distance/angle/dihedral-exact` | 刚体操作的不变量与旋转量 | 目标坐标不精确（≠1e-12）或片断不变式被破坏 |
| `relaxed-scan-profile` | 点数、`r*` 闭式解、抛物线性、单调段、残差 | 能量偏离解析极小 >1e-9；极值位置偏离 `re` >半步 |
| `relaxed-scan-residual` | 残差定义与归一化 | 与解析 `dE_total/dq` 相差（注入 1 已实证） |
| `scan-hysteresis-report` | 正/反支索引映射 + 全部报告量 | 独立重算的全部量与实际不符（注入 2 已实证）；`max_delta` 若为 0 则 `> 1e-3` 断言失败 |
| `rigid-scan-hysteresis-zero` | rigid 无历史依赖 | `max_delta ≠ 0`；正反支逐点比较不相等 |
| `scan-2d-grid` | 2D 网格 + 双约束解析极小 | 能量偏离解析值 >1e-5；丢点则 `min_i/min_j` 或收敛标记错 |
| `scan-2d-bookkeeping` | 笛卡尔积完整性 | 组合重复/遗漏（注入 4 已实证） |
| `scan-invalid-coordinate` / `scan-atom-out-of-range` / `scan-zero-nstep` / `scan-unknown-mode` / `scan-unknown-method` | `landscape_scan_check` 的每条守卫 | 校验被删则该点不报错（注入 5 已实证） |
| `scan-task-gfn2` | 任务分派 + `xtbscan.log` 帧数 + 最低点残差 | 帧数 ≠ 7、残差 >1e-3、任务报错 |
| `scan-task-invalid` | 非法设置必须在任何 SCF 之前被拒 | `landscape_log_failed` 为假，或 `result%n_eval > 0` |

---

## 5. 数值卫生自检（PLAN §7）

| # | 检查 | 结果 |
|---|---|---|
| N1 | 每个新 module 首行 `use xtb_mctc_accuracy, only : wp` + `implicit none(type, external)` | ✅ 4/4 |
| N2 | 无裸 `real` / `real*8`；数值字面量一律 `_wp` | ✅ |
| N3 | 全 1-based；MAPLE 的 `a-1` 换算点已在 `landscape_scan_coord_settings` 文档注明 | ✅ |
| N4 | 扁平化一律 `xyz(3,n)`；向量 `x1,y1,z1,x2,…` | ✅ 复用 `geometry_pack/unpack` |
| N5 | 二维矩阵 `(dim,n)`；转置显式 | ✅ |
| N6 | BLAS/LAPACK 无直接调用（本轮未用到） | ✅ |
| N7 | 无本征值求解 | n/a |
| N8 | 单位在模块头声明，内部全 a.u.，边界换算在 `main.F90`（Å/度） | ✅ |
| N9 | 无逐位比对 MAPLE | n/a |
| N10 | 无随机数（rigid 片断搜索确定性 BFS） | ✅ |
| N11 | 内层收敛复用 M1 四判据（分母 3N） | ✅ |
| N12 | 除零守卫：`geom_guard = 1e-10`（距离/坐标梯度/共线角） | ✅ |
| N13 | 一律 `env%error`/`env%warning`，无 `stop` | ✅ |
| N14 | 新代码**零**模块级可变量；约束参数显式传递 | ✅ |
| N15 | 所有 `allocate` 有配对释放/自动回收；`intent` 全显式 | ✅ |
| N16 | 每个 module/type/公开过程有 `!>` 注释（含单位与文献） | ✅ |
| N17 | 浮点判等仅用于几何缓存（M0 既有）；数值比较走容差 | ✅ |
| N18 | 未改动 `set%` 既有语义；既有文件改动限于 PLAN §12 列表 | ✅ |

**分层边界**：`scan/**` 只 `use xtb_landscape_*` + `xtb_mctc_*`
（`xtb_constrainpot` / `xtb_type_setvar` / `xtb_basic_geo` 由 PLAN §4.3 明确列为
`scan/*` 的边界模块）；xtb 私有类型（`TMolecule`/`TRestart`/`TCalculator`）只出现在
`tasks/scan.f90`。`src/type`、`src/xtb`、`src/mctc`、`src/param`、`src/io`、
`src/disp`、`src/coulomb` **零改动**。

---

## 6. 残留风险与未决项

| # | 项 | 级别 | 说明 / 建议 |
|---|---|---|---|
| R1 | 与参照 `--scan` 的 1e-6 容差 | 中 | 两侧默认档差异 ≤1.4e−5，来自参照的 ANCopt 收敛；收紧到 vtight 后 ≤1.6e−6。若验收要求 1e-6，需给 `--scan` 侧加收紧档或放宽判据并记录理由（见 §4.6）。 |
| R2 | `constraint_fc` 默认值 0.5 vs xtb 全局 0.05 | 低 | PLAN §5.3.5 与任务书均要求 0.5；与 `--scan` 默认不可比，需显式设 `--lscan-fc 0.05`。已在 §3 记录。 |
| R3 | rigid 环体系片断 | 低 | 切断一根键可能切不出片断；操作仍执行，结果靠残差自证。已在模块头与 §2.2 记录。 |
| R4 | rigid 2D 坐标耦合 | 低 | 第二个刚体操作可能轻微扰动第一个坐标；残差如实报告。 |
| R5 | 滞回用例的信号强度 | 低 | 用例用「双势阱 + 单步松弛预算」构造出 2.5e−2 Eh 的确定性滞回；真实分子上 relaxed 扫描的滞回通常远小（本例 GFN2 水 2.5e−6 Eh）。`bidirectional` 默认 true 的建议不变。 |
| R6 | 未做 xcontrol `$landscape` 段 | 低 | PLAN §12.4 标为「M2 起（可选）」，本轮全部配置走 CLI。 |
| R7 | meson 侧未验证 | 低 | 本机无 meson/ninja（AGENTS §4），`src/landscape/meson.build` 与 `test/unit/meson.build` 已同步但无法实测。 |
| R8 | `landscape_scan_bias_model%hessian` | 低 | 偏置 Hessian 走中心差分（步长 1e-4 bohr，无 SCF）；仅在 `--lscan-method rfo` 时用到，未被单元测试直接覆盖。 |

---

## 7. 建议的下一步

1. **M3 之前**：把 §4.6 的剖面对照固化成 ctest（`--scan` vs `--lscan` 同输入，容差按
   收敛档分级），防止后续改动悄悄破坏兼容性。
2. 若验收坚持 1e-6：给 `--scan`（或 `--lopt` 的收敛档）加一档 `vtight` 级别映射，
   或把对照判据改为「在相同约束残差水平下比较」。
3. M3（Hessian/freq）可以直接复用 `landscape_scan_relax::landscape_scan_coord_value`
   与 `landscape_scan_fix_setup` 的内坐标约定（尤其二面角符号已由 `rigid-dihedral-exact` 锁定）。
