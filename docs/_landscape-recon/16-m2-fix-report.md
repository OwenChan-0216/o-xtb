# M2（scan）复核轮修复报告

> 里程碑：**M2 复核轮**（F-1 HIGH / F-2 MED / F-3 PLAN 自洽 / F-4 重跑）
> 输入：实现报告 `13-m2-scan-implementation-report.md`；验证轮 `14-m2-validation-experiments.md`
> （§8 = R9 rigid 片段播种错误，§5 = R10 失败点写成 0.0 且 `conv=T`）
> 输出：本报告 + PLAN（`docs/xtb-landscape-PLAN.md` §5.3.5 / §5.5 / §8.3 / §9.3 / §12.3 / 附录 A）修正
> 纪律：**所有 xtb 调用 `OMP_NUM_THREADS=1`**（实测 340× 反向加速，见 §7）；不跑全量 ctest；
> 数值卫生未回退（`wp`、无裸 `real`、无 `stop`、无 module 级可变量、内部 a.u.）。

---

## 0. 结论速览

| # | 项 | 修复前（实测复现） | 修复后（实测） | 判定 |
|---|---|---|---|---|
| F-1 | rigid 二面角片段播种（`l–k` → `j–k`） | DCE 12° 双向 rigid 扫描滞回 **1.294821e−1 Eh**（81 kcal/mol），第 7 点起到达值**冻结在 −119.99°**（drift 最大 +60°） | 同一命令滞回 **1.776357e−14 Eh**，21 点到达值 drift **< 5e−9°** | ✅ 修复 |
| F-2 | 失败扫描点写成 `energy = 0.0` 且 `conv = T` | 刚性 5.96/10.96 Å 点：`energy 0.000000000000`、`conv T`、`residual 0.0`；`xtbscan.log` **4 帧其中 2 帧 `energy: 0.0`**；滞回报成 5.07 Eh | 同一点：`NaN`、`conv F`；log **2 帧、无 0.0 行**；滞回 0；退出码 1 + 可读诊断 | ✅ 修复 |
| F-3 | PLAN 自洽 | §5.3.5 事实错误已由验证轮更正，但 `spring_expo`/验收项/表列仍不完整 | §5.3.5 / §5.5 / §8.3 / §9.3 / §12.3 / 附录 A 逐条补全（§6） | ✅ |
| F-4 | 重跑 | —— | `ctest -R landscape` **25/25，8.8 s**；回归子集 **12/12，10.3 s**；扩展子集 **38/38，18.3 s** | ✅ |
| 附带 | **ctest 测试名撞名**（新发现） | CLI 冒烟测试与单元套件同名 `xtb/landscape-scan` ⇒ CMake **静默丢掉单元套件**，19 个 scan 单元用例从未在 ctest 下运行 | CLI 测试改名 `xtb/landscape-scan-cli`，单元套件恢复注册（+1 测试目标） | ✅ 修复 |

新增：**5 个单元用例**（scan 套件 19 → 24）、**1 个 CLI 测试**（CMake + meson）、
`landscape_cli_check.py` 新增 `scanfail` 模式。

---

## 1. F-1（HIGH）rigid 二面角扫描的片段播种错误

### 1.1 根因

`src/landscape/scan/relax_scan.f90` dihedral 分支原为
`landscape_scan_fragments(at, xyz, l, k, moving)`。该子程序的语义是
「`seed` = 片段必须包含的原子，`blocked` = 不被跨越的**单个**邻居」
（`:828-839`），因此 `(l, k)` 只切断 `l–k` 这条边：

* 当 `l` 是端基（如 H）时片段退化成 `{l}`，**`k` 上其余取代基留在原地**——这已不是刚体扫描；
* 更糟的是 BFS 只封锁 `seed → blocked` 一条边。几何一旦演化到 `l` 与近侧原子成键距离，
  BFS 就经 `H8 → C2 → C1` 吞掉 `i` 侧、最终吞掉整个分子。此时被旋转的集合里
  **近侧与远侧同时转动**，对二面角的贡献互相抵消 ⇒ **被扫坐标冻结**。

实测复现（DCE，`--lscan-mode rigid --lscan-coord dihedral --lscan-atoms 3,1,2,4
--lscan-step 12 --lscan-nstep 10`，GFN2，`OMP_NUM_THREADS=1`）：

| 点 | 目标/° | 到达/° | drift/° | E/Eh |
|---|---|---|---|---|
| 1–6 | −179.99 … −119.99 | 精确等于目标 | 0 | 正常下降 |
| 7 | −107.99 | **−119.99** | −12.00 | −15.286739739372 |
| 8–11 | −95.99 … −59.99 | **−119.99** | −24 … −60 | −15.286739739（同一数值） |
| 12–21（反向支） | −71.99 … −179.99 | **−119.99** | +48 … +60 | 同上 |

```
hysteresis: max |E_fwd - E_rev|    1.294821E-01 Eh        <- 81 kcal/mol 纯伪影
largest jump between points:       4.633363E-02 Eh
```
（与验证轮 `rigid_driver.csv` 的 0.1295 Eh 逐位一致。）

### 1.2 约定选择：转 **k 侧**（含 `l` 的整侧）

`j–k` 是中心键，`j` 在近侧、`k` 在远侧（`l` 挂在 `k` 上）。两种合法约定（转远侧 / 转近侧）
对二面角的改变量符号相反，都会到达目标；选定 **远侧（seed = `k`，blocked = `j`）**，理由：

1. 与模块头注释声明的语义一致（“the fragment of the last atom is rotated about the central bond”）——
   `l` 必须在移动侧，否则 `l` 的取代基几何无从上位；
2. 与 `valijkl` 的符号约定 + 既有测试期望一致（`alpha = target − value`，转 `k` 侧使
   `value` 增加恰好 `alpha`，见 §1.3 的独立参考几何）；
3. 与另两种坐标类型的语义一致：distance 切被扫键本身、angle 切 `i–j` 并转 `i` 侧，
   即“总转最远端那一侧”。

```fortran
      ! The moving side is the one behind the central bond `j-k`, i.e. the
      ! fragment seeded at `k` (which contains `l` and every substituent of `k`).
      call landscape_scan_fragments(at, xyz, k, j, moving)
      call rotate_fragment(xyz, moving, xyz(:, j), axis/delta, alpha)
```
两个中心原子位于旋转轴上（`k` 在片段内但 `|x_k − x_j|` 沿轴）⇒ 不动，`l` 与
`k` 的所有取代基一起作为刚体转动 ⇒ 二面角改变恰好 `alpha`。

### 1.3 测试：把编码 bug 的用例换成能抓住 bug 的用例

原 `rigid-dihedral-exact` 的 fixture 是 H–O–O–H，`l` 的“取代基”是**非成键** H，
`fragments(…,4,2)` 恒返回 `{H2}`，因此它**断言了错误语义却通过**。替换为：

| 用例 | 内容 |
|---|---|
| `rigid-dihedral-fragment`（替换 `rigid-dihedral-exact`） | 8 原子 1,2-二氯乙烷 fixture（GFN2 优化 `anti` 构型，Cl3–C1–C2–Cl4 = −179.99°，`l` = Cl4 带**真实**取代基 C2 的 H7/H8）。断言：①片段掩码 = 远侧 `{C2, Cl4, H7, H8}`；②到达二面角 = 目标（1e−12）；③近侧 4 个原子**逐位不动**（thr = 0）；④远侧 4 个原子等于**测试内部独立实现**的 Rodrigues 旋转结果（1e−12）；⑤远侧所有内距守恒（刚体） |
| `rigid-dihedral-scan`（新增） | 同一分子的 `gauche` fixture（由 `anti` 经**独立 +120° 旋转**得到），12° 步长、nstep 10、双向 rigid 扫描。断言：①逐点 `profile%reached == 目标`（1e−12）；②逐点 `conv = T`；③近侧原子在**所有**点逐位不动；④剖面不是常数（span > 1e−3 Eh，实测 7.92e−2）；⑤滞回 `max_delta ≤ 1e−14`（实测 2.498e−16）；⑥正反两支逐点几何相同（1e−12，实测 3.55e−15） |

**独立参考**（不调用被测模块）：`reference_dihedral`（按 `xtb_basic_geo::valijkl` 的
约定重写：法向夹角 + 由中心键定向定号；并断言它与 `landscape_scan_coord_value` 在
fixture 上一致 < 1e−12）、`reference_rotate`（显式组装 Rodrigues 矩阵，而非
`rotate_fragment` 的矢量写法）。

### 1.4 自证可证伪（注入实验）

把该行临时改回 `(l, k)`、重编译：

```
  rigid-dihedral-fragment ... [FAILED]
  Message: the far side is not the rigid rotation of the whole side
     rigid dihedral: max deviation from the independent rigid rotation   7.2238E-01
  rigid-dihedral-scan ... [FAILED]
  Message: a rigid torsion point did not reach its target
     rigid torsion point   9 requested  -123.986619 reached  -115.986619   <- 冻结
```
还原后：`rigid dihedral: max deviation … 4.4409E-16`、21 点全部
`reached == requested`、`exit 0`。CLI 层面同一注入给出 §1.1 的 0.1295 Eh 表。

---

## 2. F-2（MED）失败的扫描点被写成 `energy = 0.0` 且 `conv = T`

### 2.1 两条独立的根因（都已实测）

**(a) 引擎把“被丢弃的评估”当成成功。** `xtb_calculator_singlepoint` 把 `results`
声明为 `intent(out)`，但在 `call env%check(exitRun)` 提前返回
（“Electronic structure method terminated”）时**从不赋值**，`intent(out)` 语义下该分量
变为未定义；`energy` 则保留 `singlepoint` 进入时写的 `0.0`。
`landscape_engine` 单看 `results%converged` 就会读到上一次成功评估的**陈旧 `.true.`**，
于是“返回成功 + `energy = 0.0` + 梯度 0”一路传到扫描点：内层判据在零梯度上平凡满足
⇒ `conv = T`、`residual = 0.0`（验证轮 §5.3 的“点 3”）。

**(b) 失败点无“没有值”的表示。** `landscape_scan_point%energy` 初值 `0.0`、`profile%energy`
初值 `0.0`、`point%xyz` 初值全零；失败时既不置 NaN 也不排除，于是 0.0 直接进 stdout 表
与 `xtbscan.log`。

### 2.2 修复

| 位置 | 修复 |
|---|---|
| `engine/engine.f90` | 在 `singlepoint` 前后取 `nlog = env%nLog`，**先**用 `landscape_log_failed(env, nlog)` 判断“计算器是否终止”（这是该模块已有的探测约定，见 `settings.f90:667-687` 的注释），**此时才**读 `cache_results%converged`（避免读未定义分量）；另加“能量/梯度非有限 ⇒ 丢弃”的兜底 |
| `types/settings.f90` | 新增 `landscape_missing_value()`（`ieee_value` 静默 NaN，debug 下 `-ffpe-trap=invalid` 也安全）与 `landscape_value_present()`（有限性判断） |
| `scan/relax_scan.f90` | `landscape_scan_point` 新增 `energy_valid` 字段并写下**不变量**：`energy_valid = .false.` ⇔ `energy`/`residuals` 为 NaN 且 `converged = .false.`；relaxed/rigid 两个构造函数进入时即把这些量置为 NaN，只有去偏评估成功（且有限）才置有效；rigid 点不再“先假定 converged”。`values`（到达坐标）在几何存在时**仍如实报告**（它是构造的性质，不是被丢弃评估的性质），仅当几何本身构造失败时才为 NaN |
| `scan/scan1d.f90` / `scan2d.f90` | profile/grid 新增 `energy_valid`；`store_point`/`solve_grid_point` 对无效点写 NaN（**绝不**写 0.0）；2D 的极小搜索跳过无能量点（`min_energy` 无合格点时保持 NaN）；滞回/跳变报告天然跳过含 NaN 的配对（NaN 与任何界比较为假），已在类型注释里写明 |
| `tasks/scan.f90` | ① `xtbscan.log` **只写有能量的点**（无效点省略），并打印 `wrote <f> with N frame(s), M failed point(s) omitted`；② log 以 `status='replace'` 打开；③ 无任何有效点时 `result%energy = NaN` 且**不**用零帧覆盖输入几何；④ 诊断改为 `landscape scan aborted: N of M scan points failed (no energy; the failed points are the NaN rows of the scan table)`，退出码仍为 1（`env%error`） |
| `scan/scan1d.f90` 打印层 | 1D 表新增 `reached` 与 `drift`（= reached − value）两列（同时落实 F-3 的表列要求，并顺带修掉 F3-low：负步长时 `value` 列不再是未回绕的目标值——它本就是“请求值”，到达值现在单列可见） |

**为什么不写 NaN 帧而选择“从输出中省略”**：一帧 xyz 的唯一数值载荷就是能量注释行
（`writeMolecule(..., energy=)`），而失效点**没有能量**——写 NaN 注释会破坏
`xtbscan.log` 作为“带能量的轨迹”的契约（且会被现有 `energy:` 列解析器误读），写 0.0
则是直接造假；当几何构造本身失败时（验证轮 §5.3：“point%xyz 也保持 0”）连几何都是零帧。
轨迹文件容许缺帧，不允许伪造数据，所以选择省略。逐点信息并不丢：stdout 表仍然为**每个
请求点**保留一行，`value/reached/drift` 如实打印，`energy/residual` 为 `NaN`、`conv = F`
——**表格不撒谎，轨迹不含伪帧**。

`status='replace'` 是必需的：Fortran 的 `status='unknown'` + `action='write'` 在
**一条记录都没写**时**不会**截断旧文件（只是从文件头开始覆盖），空扫描会残留上一次
运行的帧。这个坑在写 `scan-task-no-energy` 时实测踩到：命令打印了
`wrote xtbscan.log with 0 frame(s)`，但 `count_frames` 仍然读到上一用例留下的 1 帧。

### 2.3 自证可证伪（注入实验）

临时把引擎里的 `landscape_log_failed` 判断摘掉（即恢复修复前行为）、重编译：

```
    point      value/Ang reached/Ang drift/Ang         energy/Eh      residual      steps  conv
        4       5.96000009       5.96000009       0.00000000       0.000000000000   0.0000E+00      0 T   <- 0.0 + conv T
        5       0.96000009       0.96000009       0.00000000       0.000000000000   0.0000E+00      0 T
hysteresis: max |E_fwd - E_rev|    5.070383E+00 Eh                                                   <- 伪影
xtbscan.log: 4 帧，其中 2 帧 "energy: 0.000000000000"
```
单元层面（同一注入）：`scan-task-missing-energy [FAILED] — the scan log contains a
fabricated zero energy`、`scan-task-no-energy [FAILED]`。还原后两条转绿、`exit 0`。

**修复后同一命令（刚性 5 Å 步长）**：

```
    point      value/Ang reached/Ang drift/Ang         energy/Eh      residual      steps  conv
        1       0.96000009       0.96000009       0.00000000      -5.070383095219   1.2886E-03      0 T
        2       5.96000009       5.96000009       0.00000000      -4.831779805132   2.9209E-04      0 T
        3      10.96000009      10.96000009       0.00000000                  NaN          NaN      0 F
        4       5.96000009       5.96000009       0.00000000                  NaN          NaN      0 F
        5       0.96000009       0.96000009       0.00000000                  NaN          NaN      0 F
   landscape scan: 3 point(s) carry no energy (their single point failed)
   wrote rig2.xtbscan.log with 2 frame(s), 3 failed point(s) omitted
   landscape task terminated: some scan points failed           exit = 1
   landscape_scan: landscape scan aborted: 3 of 5 scan points failed (no energy; …)
```
`rig2.xtbscan.log` = 2 帧，两帧都是真实负能量，**没有任何 `0.0` 行**。三列语义明确：
几何构造成功 ⇒ `reached` 如实报告（它是构造的性质）；能量被丢弃 ⇒ `energy`、`residual`
为 NaN 且 `conv = F`（见表头下文 §2.2 的不变量）。

### 2.4 覆盖三条要求的测试

| 要求 | 测试 |
|---|---|
| 失败点不得写 0.0 | `scan-missing-energy`（解析模型 + `scan_fragile_model`：预算耗尽后每次评估都失败且**故意**留下 `energy = 0.0`，断言 profile/2D grid 里无 `0.0`、无效点必为 NaN、`n_fail` 计数一致）；`scan-task-missing-energy`（GFN2 真实 SCF 失败，断言 log 无 `energy: 0.000000000000` 且帧数 < 请求点数） |
| 梯度被丢弃时 `converged` 不得为 `.true.` | 同上（逐点断言无效 ⇒ `conv = F`）；`scan-task-no-energy`（全部点失败 ⇒ log 0 帧、`result%energy` 为 NaN、`result%converged = F`、**输入几何被保留**） |
| `xtbscan.log` 无伪 0.0 行 | 上述两条 + CLI 层 `xtb/landscape-scan-failed-point`（CMake）/`landscape scan failed point`（meson）：退出码 ≠ 0、含 `scan points failed`、log 无 `0.0` 行且帧数 < 5 |
| 退出码语义 | CLI 测试直接断言 `status != 0`；单元层断言 `landscape_log_failed` 与 `result%converged = F` |

---

## 3. F-3 PLAN 核对与补全

逐条核对（`docs/xtb-landscape-PLAN.md`）：

| 位置 | 状态 | 动作 |
|---|---|---|
| §5.3.5 `constraint_fc` | 验证轮已改正（保留 0.5、删掉“0.5 = xtb `fcconstr` 默认”的错误说法、给出 fc=0.05 → 势垒 −4.9 %/漂移 6.84°、fc=0.5 → −0.33 %/0.82°、`--lscan-fc 0.05` 为兼容档） | **核对通过**，未再改（仅在验收项里显式写出“两侧 fc 必须对齐”） |
| §5.3.5 `spring_expo` | 原文只说“仅对 distance 生效” | **补**：二面角的有界周期形式在 Δφ = 180° 处恢复力矩为**零**、势垒上界 `2fc`（“二面角比 distance 更容易漂移”的直接后果） |
| §9.3 验收项 | 原文仍写“容差 1e-6 hartree” | **改写为**「**在同一约束残差水平下**与参考扫描剖面一致（1e-6 hartree），两侧 `constraint_fc` 必须显式设定并对齐」，并把实测数字写进验收项本身（default：水 1.316e−5 / H₂O₂ 4.830e−6 **未达成**；vtight：H₂O₂ 6.672e−7 **达成**、水 1.615e−6 差 1.6×；根因 = 参照 ANCopt default↔vtight 漂移 3.96e−6 Eh） |
| §9.3 1D 表 | 原文未写 | **补**：1D 表打印 `value/reached/drift` 三列（已实现，见 §2.2）并作为验收判据之一 |
| §9.3 / 附录 A 工程约定 | 无 | **补**：scan / Hessian 相关实验、基准与 ctest 一律 `OMP_NUM_THREADS=1`（0.13 s vs 44.12 s = 340×；`ctest -R landscape` 38 s → ≈9 s），并把该约定落实到测试注册（§4.1） |
| §5.5 输出约定 | 无“缺失值”规则 | **补**：能量/梯度被丢弃的量化值一律 NaN，绝不写 0.0；`xtbscan.log` 对这类点不写帧并以 `status='replace'` 打开 |
| §8.3 测试注册 | 无撞名警告 | **补**：ctest 测试名必须全局唯一（撞名会静默丢掉先注册者，见 §4.1），新增测试后 `ctest -N -R landscape` 核对名字与数量 |
| §12.3 | 验证轮已加 `--lopt-hessian` 行；但 (a) 的代码片段是初版（缺 `--acc` 同步、结果回写、scan 分派） | **改成实际代码**（`main.F90:928-961`），并写明两个已实测的接口事实：`singlepoint` 丢弃 `acc`（只有 `calc%accuracy` 生效）与 `maxiter`（限制 SCF 迭代必须设 `calc%maxiter`） |
| §12.10 | —— | 核对通过：表内 16 行覆盖 `main.F90` 里全部 18 个 `--lscan*` flag |

---

## 4. F-4 重跑与真实数字

### 4.1 ctest（`OMP_NUM_THREADS` 由测试注册固定为 1 的项已注明）

```
cmake -S . -B /tmp/xtb-land/build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON \
      -DCMAKE_BUILD_TYPE=Release && cmake --build /tmp/xtb-land/build -j   # 0 error / 0 warning

ctest --test-dir /tmp/xtb-land/build -R landscape
  100% tests passed, 0 tests failed out of 25        Total Test time (real) =   8.84 sec
ctest --test-dir /tmp/xtb-land/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
  100% tests passed, 0 tests failed out of 12        Total Test time (real) =  10.25 sec
ctest --test-dir /tmp/xtb-land/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI|hessian|landscape'
  100% tests passed, 0 tests failed out of 38        Total Test time (real) =  18.33 sec
```

（本机还跑着其它负载，同一命令的重复实测：landscape 25/25 为 8.8 / 8.9 / 9.7 / 10.6 s，
扩展子集 18–32 s；本报告只引用「最后一次全绿运行」的数字。）
`landscape_cli_check.py` 的 `scanfail` 镜像在本机手工验证（meson 未安装，AGENTS §4）：
`python3 test/unit/landscape_cli_check.py scanfail <xtb> landscape_h2o.xyz <rundir>` → exit 0，
`error` 模式同样 exit 0。

**工程约定已落实到测试注册**：所有跑引擎的 landscape CLI 检查（`landscape-opt`、
`-opt-energy`、`-opt-acc`、`-opt-hessian`、`-scan-cli`）与单元套件 `landscape-scan`、
`landscape-scan-failed-point` 均固定 `OMP_NUM_THREADS=1`（CMake + meson 两侧）；
不跑计算的错误分支与 SCF 失败探针保持普通环境。实测单项：单元套件 19.6 s → **0.13 s**，
失败点 CLI 28 s → **0.11 s**，`ctest -R landscape` 38 s → **≈9 s**。

**附带缺陷（本轮发现并修复）**：M2 把 CLI 冒烟测试也叫 `xtb/landscape-scan`，与单元套件同名；
CMake 对同名测试是“后者替换前者”，因此 `test/unit/CTestTestfile.cmake` 里只剩
`cmake -P` 那一行、**整个 scan 单元套件（交付时 19 个用例，现 24 个）从未在 ctest 下
执行过**（本轮把 3 个用例改红、ctest 仍报 “24/24 passed” 才发现）。处置：CLI 测试改名 `xtb/landscape-scan-cli`（CMake；meson 侧同步改
显示名 `landscape scan cli`），单元套件恢复注册 ⇒ landscape 目标数 23 → 25。

### 4.2 rigid 二面角双向扫描（修正前 / 修正后）

命令（validation 同一输入、同一网格，`OMP_NUM_THREADS=1`）：

```bash
XTBPATH=$PWD /tmp/xtb-land/build/xtb dceopt.xtbopt.xyz --gfn2 --lscan --lscan-mode rigid \
  --lscan-coord dihedral --lscan-atoms 3,1,2,4 --lscan-step 12 --lscan-nstep 10 --namespace rigidfix
```

| 指标 | 修正前 | 修正后 |
|---|---|---|
| 滞回 `max |E_fwd − E_rev|` | **1.294821e−01 Eh**（81 kcal/mol，纯伪影） | **1.776357e−14 Eh**（≈1.1e−5 kcal/mol） |
| 最大逐点 drift（到达 − 目标） | **+60.00000000°**（第 7 点起冻结在 −119.99°） | **< 5e−9°**（全部 21 点，表内打印 0.00000000） |
| 最大相邻跳变 | 4.633363e−02 Eh（冻结造成） | 1.563792e−03 Eh（光滑，与 12° 步长成正比） |
| 能量评估次数 / 点数 | 20 / 21（缓存去重） | 21 / 21 |
| 退出码 | 0 | 0 |
| 势垒位置（网格极大点） | 假平台 | −107.99°（E = −15.411051178655） |
| 极小点 | 冻结段 | anti −179.99°（−15.416221829986）、gauche −59.99°（−15.413498300463） |

单元层面（解析模型，可判定到机器精度）：`rigid-scan-hysteresis-zero`（distance，未改动）
仍然 1e−14 严格成立；新的二面角版本 `max_delta = 2.498e−16 Eh`、正反几何差 3.55e−15 bohr。
两者相差 ~1e2 是因为实测 GFN2 剖面的两支几何只在最后几位比特上不同（旋转复合的舍入），
能量差 1.8e−14 Eh 属 SCF/舍入噪声；PLAN §9.3 因此把该验收写作“**≤ 1e−14 Eh 量级**”，
而把 1e−14 的严格判据留给不依赖 SCF 的解析模型用例。

### 4.3 本轮新增/变更的测试清单

| 类型 | 名称 | 说明 |
|---|---|---|
| 单元 | `rigid-dihedral-fragment` | 替换 `rigid-dihedral-exact`（fixture + 独立参考，见 §1.3） |
| 单元 | `rigid-dihedral-scan` | 新增，双向 rigid 二面角扫描的逐点/滞回/刚体断言 |
| 单元 | `scan-missing-energy` | 新增，profile + 2D grid 的“无能量”不变量 |
| 单元 | `scan-task-missing-energy` | 新增，GFN2 真实失败点 ⇒ log 无伪 0.0 |
| 单元 | `scan-task-no-energy` | 新增，全部点失败 ⇒ 0 帧 / NaN / 几何保留 |
| CLI | `xtb/landscape-scan-failed-point`（CMake）+ `landscape scan failed point`（meson） | 新增，退出码 + 诊断 + log 内容 |
| 注册 | CLI 冒烟测试改名 `xtb/landscape-scan-cli` | 修撞名（§4.1） |
| 注册 | 所有跑引擎的 landscape 检查固定 `OMP_NUM_THREADS=1`（CMake + meson） | 单元套件 19.6 s → 0.13 s、失败点 CLI 28 s → 0.11 s |

scan 单元用例 19 → **24**；`landscape-scan` 套件本身 24/24 通过。

---

## 5. 变更文件

| 文件 | 变更 |
|---|---|
| `src/landscape/scan/relax_scan.f90` | dihedral 片段播种 `(l,k)` → `(k,j)` + 注释；`landscape_scan_point%energy_valid` 不变量（energy/residuals/converged 一致地“无值”，reached 仍如实）；relaxed/rigid 构造函数重构（先取到达坐标、再评估能量）；有限性兜底 |
| `src/landscape/scan/scan1d.f90` | profile 的 `reached`/`energy_valid`；`store_point` 不写伪 0.0；1D 表加 reached/drift 列 |
| `src/landscape/scan/scan2d.f90` | grid 的 `energy_valid`；极小搜索跳过无能量点；初始化改 NaN |
| `src/landscape/tasks/scan.f90` | log 省略无能量帧 + `status='replace'` + 帧数/省略数报告；无有效点时 `result%energy = NaN` 且不覆盖输入几何；可读诊断 |
| `src/landscape/engine/engine.f90` | `landscape_log_failed` 探测计算器终止 + 有限性兜底（修 §2.1(a)） |
| `src/landscape/types/settings.f90` | `landscape_missing_value`、`landscape_value_present` |
| `test/unit/test_landscape_scan.f90` | DCE fixture、独立参考几何、5 个新用例（1246 → 1864 行） |
| `test/unit/landscape_cli_check.py` | `scanfail` 模式（meson 侧镜像） |
| `test/unit/CMakeLists.txt` | 新 CLI 测试 + 撞名修复 + landscape 检查固定单线程 |
| `test/unit/meson.build` | 同步（名字、新测试、`landscape_env = xtbenv + OMP_NUM_THREADS=1`） |
| `docs/xtb-landscape-PLAN.md` | §5.3.5 / §5.5 / §8.3 / §9.3 / §12.3 / 附录 A |

未改动的既有层：`src/type`、`src/xtb`、`src/mctc`、`src/param`、`src/io`、`src/disp`、`src/coulomb` 仍为 0 处引用（`xtb_landscape_*` 只在 `src/prog/main.F90` 出现）。

---

## 6. 残留风险与已知限制

| # | 项 | 级别 | 说明 / 处置 |
|---|---|---|---|
| R9-a | rigid 片段仍按**当前（热启动）几何**重算 | 低 | 修复后每次刚性操作是整体刚体转动 ⇒ 所有内距守恒 ⇒ 连通图不变 ⇒ 片段在同一次扫描中恒定（实测新代码路径无跨切割成键：最紧的跨界对比例 0.526 × 阈值）。但**参考几何本身**若有跨切割的伪键，仍会退化；彻底解法是片段只在参考几何上算一次（验证轮建议 2），留待 M4（P-RFO 也需要参考 Hessian 语义） |
| R9-b | 二面角在 φ ≈ ±180° 处 `valijkl` 的 `acos` 病态（放大 ~1/sin φ） | 低 | 实测把“请求值 − 到达值”的误差放大到 ~4e−13 rad（几何 ~1e−12 bohr）；远离 180° 时为 1e−15。测试 fixture 因此选在 [−140°, −60°] 内；如需高精度反式扫描，应在 M4/M6 一并处理坐标表示 |
| R10-a | 一旦某个扫描点的 SCF 记了 env error，**同一进程中后续所有**单点都在 `env%check` 处提前返回 | 中（行为事实，非新缺陷） | 修复后这些点被**如实**标成失败（NaN + conv F + 非零退出），不再伪造成 0.0。代价是失败点之后仍会重复尝试（实测 454 次评估 / 0.12 s）。若要“首点硬失败即中止整条扫描”，应作为司机层策略单独决策（会改变“记录失败点并继续”的既有语义） |
| R10-b | 滞回/跳变报告会跳过含 NaN 的配对 | 低 | 已在类型注释写明：NaN 与任何界比较为假 ⇒ 含缺失值的配对不参与最大/最小；此时剖面本身已由 `n_fail` 明确标为不可用 |
| R10-c | `landscape_engine_control%maxiter` 是**空转字段** | 中 | `xtb_single::singlepoint` 只转发 `printlevel`/`restart`，`maxiter`/`acc`/`lgrad` 形参被丢弃（`acc` 由引擎写进 `calc%accuracy` 绕过，见 PLAN §12.3）。本轮未改（超出 F-1..F-4 范围，且会影响既有 opt 语义）；单元测试改用 `calc%maxiter = 1`。建议 M3 一并处理并把结论写回 AGENTS §6.4 |
| R10-d | 2D 网格的“无能量”分支只有解析模型覆盖 | 低 | `scan-missing-energy` 的第二段已跑 2D（9 点中 7 点缺失，断言 NaN/conv F/极小点来自有值点）；GFN2 的 2D 失败路径未单独构造（成本高、代码路径与 1D 共用同一 `energy_valid` 机制） |

---

## 7. 复现命令汇总

```bash
export XTBPATH=/home/owenchan/work_path/coding/fortran/xtb
export OMP_NUM_THREADS=1                       # 强制，见 PLAN 附录 A（340×）
cmake -S . -B /tmp/xtb-land/build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON \
      -DCMAKE_BUILD_TYPE=Release && cmake --build /tmp/xtb-land/build -j

# 单元 + CLI + 回归
ctest --test-dir /tmp/xtb-land/build -R landscape                                  # 25/25
ctest --test-dir /tmp/xtb-land/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
ctest --test-dir /tmp/xtb-land/build -N -R landscape | tail -3                     # 名字/数量核对

# scan 套件（24 用例）
/tmp/xtb-land/build/test/unit/xtb-tester landscape-scan

# F-1/F-4：rigid 双向扫描
/tmp/xtb-land/build/xtb dceopt.xtbopt.xyz --gfn2 --lscan --lscan-mode rigid \
  --lscan-coord dihedral --lscan-atoms 3,1,2,4 --lscan-step 12 --lscan-nstep 10 --namespace rigidfix

# F-2：失败点
/tmp/xtb-land/build/xtb water.xyz --gfn2 --lscan --lscan-mode rigid --lscan-coord distance \
  --lscan-atoms 1,2 --lscan-step 5.0 --lscan-nstep 2 --namespace rig        # exit 1，log 2 帧无 0.0
```
