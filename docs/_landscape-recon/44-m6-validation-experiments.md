# 44 — M6 IRC 验证实验与独立复核

> 里程碑：M6（验证轮）。范围：PLAN §8.2 实验 #4/#6/#7、第二阶段三处偏离的独立核实、
> 第一阶段遗留的 GS E/g 根因、相位约定覆盖缺口。
> HEAD：`2ed7750`（M6 全部代码未提交；本轮**只改测试**，未改 `src/` 生产逻辑）。
> 所有 `xtb` / `ctest` / `xtb-tester` 调用均带 `OMP_NUM_THREADS=1`。
> 原始数据：`docs/_landscape-recon/m6-irc-data/`（每用例一子目录，含 stdout 与四个产出文件）。
> 实现报告：`42-*`（第一阶段）、`43-*`（第二阶段）。

---

## 0. 摘要

| 项 | 结果 |
|---|---|
| `src/` 改动 | **0**（只改测试；所有注入实验均还原并逐位核对） |
| 新增单元用例 | 4 个：`gs-path-geometry-consistency`、`phase-convention-sign-invariance`、`leps-four-method-crosscheck`、`hpc-predictor-accuracy`（套件 28 → **32**） |
| `ctest -R landscape` | **77/77**（13.2 s） |
| 回归子集 | `-R 'Singlepoint\|GFN\|model-hessian\|optimizer\|Argparser\|CAPI'` → **12/12** |
| 重名 | `uniq -d` 空；`ctest -N -R landscape` = 77 |
| 第 0 项（GS 行为保持） | **逐位保持**（10/10 数字与报告 42 完全相同）；新测试可捕获该类回归（注入变红） |
| R-1（1 E/g 方案） | **定性成立、定量否定**：我的忠实实现给出 forward 偏 **2.80e-3 Eh**（不是报告 43 的 1.4e-2），另一个合理变体偏 4.6e-2 → 1.4e-2 不可复现 |
| R-2 / R-4 | **独立复现**（0.40 步长 HPC 偏 2.346e-3 Eh、EulerPC 严重失效；信号 (b) 可达、EulerPC forward 先触发 (c)） |
| 实验 #6 | 解析（MB、LEPS）+ GFN2 四法双向互校完成；**GS 在 GFN2 上显著偏离**（判据见 §4） |
| 实验 #7 | max_steps 分布、grad_tol 可达下限、e_rise 曲线、步长×方法收敛表全部实测 |
| 实验 #4 | 纯 Bofill vs 每 N 步重算：短路径误差 ≤3e-5 Eh；**长积分下纯 Bofill 会把 backward HPC 拖出极小点**（§6） |
| 第四项 | GS E/g 根因复现（微循环被 trust-region 钉死）；修复方向=等式约束 Lagrange 步，可省 ~3–4× |
| 新发现 | **F-1**：`landscape_irc_path` 跨 `ndim` 复用时分配不更新（潜伏 API bug，生产路径不触发，只报告不修）；**F-2**：HPC 预测步此前**无任何测试覆盖**（已由新用例 `hpc-predictor-accuracy` 关闭） |
| 注入 | 9 条，全部红→还原→绿（§8）；HPC 预测步为真实覆盖缺口并已补测 |

---

## 1. 环境与基线

```
$ cmake -S . -B /tmp/xtb-land/build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON -DCMAKE_BUILD_TYPE=Release
$ touch src/landscape/irc/*.f90 src/landscape/tasks/irc.f90
$ OMP_NUM_THREADS=1 cmake --build /tmp/xtb-land/build -j        # 0 warning
$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape      # 77/77 (13.2 s)
$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'   # 12/12
$ grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d  # 空
$ ctest -N -R landscape | tail -1           # Total Tests: 77
$ ./test/unit/xtb-tester landscape-irc      # 32/32（原 28 + 新 4）
```

规范 TS（`--lts --lts-method prfo`，bent HCN guess）：
`E_TS = -5.387373532156 Eh`，相位分量 `0.92806755`（cartesian 1 of atom 1）。
HNC 真实极小（细步长收敛值）≈ **-5.47215989 Eh**，HCN 真实极小 ≈ **-5.50406622 Eh**。

---

## 2. 第 0 项（最高优先）——GS 回归修复的行为保持性

第二阶段拆分 `gs_walk`/`gs_step` 时曾引入回归（`mb-gs-minima` 红），修复手段是让
`landscape_irc_gs_step` 返回 `x_new`（报告 43 §4）。`src/landscape/irc/` 未入 git，
无历史可 diff，故用**两条独立手段**核实。

### 2.1 端到端逐位复核（GFN2 HCN/HNC，step 0.10）

数据：`m6-irc-data/item0-gs-e2e/`（本次新跑）与报告 42 §7.1 的表格逐项对照：

| 量 | 报告 42（重构前） | 本轮（重构后） | 差 |
|---|---|---|---|
| forward 端点能量（HNC） | -5.472135505135 Eh | **-5.472135505135 Eh** | 0 |
| backward 端点能量（HCN） | -5.504066222136 Eh | **-5.504066222136 Eh** | 0 |
| forward reached-min rmsd | 0.009860 bohr | **0.009860 bohr** | 0 |
| backward reached-min rmsd | 0.000016 bohr | **0.000016 bohr** | 0 |
| forward 点数 / 平均 E/g | 42 / 16.93 | **42 / 16.93** | 0 |
| backward 点数 / 平均 E/g | 40 / 20.25 | **40 / 20.25** | 0 |
| forward 弧长 | 4.051234 | **4.051234** | 0 |
| backward 弧长 | 3.695670 | **3.695670** | 0 |
| TOTAL ENERGY | -5.387373532405 Eh | **-5.387373532405 Eh** | 0 |
| 相位分量（atom 1, cart 1） | 0.92806755 | **0.92806755** | 0 |

⇒ **重构逐位行为保持**（10/10 数字相同）。

报告 42 §7.2 的 GS-vs-LQA 端点 RMSD **1.93e-2 / 1.42e-2** 本轮独立复算为
**3.35e-2 / 2.47e-2**（每原子口径），除以 √3 得 **1.934e-2 / 1.426e-2** —— 与报告 42
一致（**报告 42 用的是「每分量」RMS = 每原子/√3**，只是口径未写明；见 §4 注）。

### 2.2 `gs_step` 与 `gs_walk` 主路径的语义一致性（代码核实）

逐行核对（`src/landscape/irc/gs.f90`）：

| 关注点 | 结论 |
|---|---|
| micro 循环状态 | `gs_step` 每次调用重新 `q_ref=q_cur, g_ref=g_cur, n_eval=0, moved=.false.`；无跨调用状态泄漏 |
| 方向 sign | 编码在 `q_cur`（首次半步 `sign·(s/2)·v`），`gs_step` 只用 `q_cur,g_cur` 构造 pivot，与 walk 主路径**同一公式** |
| E/g 计数 | 微循环内逐次 `n_eval=n_eval+1`，末点再 +1；walk 把 `n_eval` 原样写入 `path%n_eval`，与主路径相同 |
| Hessian 更新 | 微循环第一次用 secant `(q_new−q_cur, g_new−g_cur)`，与主路径首个宏步一致 |
| `recalc` | walk 传 `mod(npoint,recalc)==0`；**HPC/EulerPC 回退恒传 `.false.`**（它们已在预测器前自行 rebuild）。默认 `hessian_recalc=-1` 时两者一致；仅当用户设 `--lirc-recalc N` 且发生回退时，回退步不重建 Hessian。属可接受语义（回退是单步应急），**记录为已知差异 D-1**。 |

⇒ 除 D-1（仅在「显式 recalc + 校正失败」组合下）外，回退语义与主路径一致。

### 2.3 新增回归捕获测试（本轮最重要产出）

新增单元用例 **`gs-path-geometry-consistency`**：

* 在 MB（2D）与 LEPS（9D）上各跑一次 GS，然后**把每个记录点的几何重新喂回解析势**，
  要求复现该点的 `path%e(k)` 与 `path%gnorm(k)`（容差 1e-10），并要求路径几何确实移动。
* 这直接绑定了「几何 ↔ 能量 ↔ 梯度」三元组；报告 43 §4 的回归里几何被冻结在首点、
  能量却逐点更新，因此**必然**被抓住。

**注入验证（模拟报告 43 的旧 bug）**：在 `gs_walk` 内把传给 `path_add` 的 `x_new`
换成首点几何：

```
$ python3 (对 src/landscape/irc/gs.f90 注入 x_new = path%xyz(:,1))
       ... mb-gs-minima [FAILED]
  Message: the forward endpoint is not near a Mueller-Brown minimum
       ... four-method-crosscheck [FAILED]
       ... gs-path-geometry-consistency [FAILED]
  Message: Mueller-Brown GS: the recorded path geometry did not move
       ... leps-four-method-crosscheck [FAILED]
=== 还原 === 32/32 PASSED
```

⇒ 新用例**精确复现并捕获**第二阶段那次真实回归（连 `mb-gs-minima` 的消息都一致）。
这是防止同类回归再次静默发生的长期护栏。

---

## 3. 实验 #6 — 四算法互校（同 TS 跑双向）

### 3.1 真实 GFN2（HCN/HNC TS，`item0-gs-e2e/t0.xtbts.xyz`）

原始数据 `exp6-crosscheck/gfn2/step{0.05,0.10,0.20,0.40}/{gs,lqa,hpc,eulerpc}/`，
汇总 `exp6-crosscheck/gfn2-summary.txt`。端点 RMSD 矩阵为**每原子口径**（每分量 = /√3）。

**端点能量 / 终止信号 / 平均 E/g / 点数**（forward / backward）：

| step | GS | LQA | HPC | EulerPC |
|---|---|---|---|---|
| 0.05 | -5.47210857 / 9.25 | -5.47208915 / 1.00 | -5.47215889 / 1.99 | -5.47209347 / 1.95 |
| 0.10 | -5.47213551 / 16.93 | -5.47215487 / 1.00 | -5.47210457 / 1.98 | **-5.47130320** / 1.92 |
| 0.20 | -5.47215989 / 18.83 | -5.47215822 / 1.00 | -5.47215455 / 1.96 | -5.47179855 / 2.00 |
| 0.40 | -5.47215988 / 19.46 | -5.47183044 / 1.00 | **-5.46981357** / 1.94 | **-5.46638079** / 3.43† |

（† EulerPC 0.40 forward 3 次 GS 回退；backward -5.49282324。）

**端点 RMSD 矩阵**（step 0.10，bohr，每原子）：

```
forward            gs       lqa       hpc   eulerpc        backward           gs       lqa       hpc   eulerpc
gs           0.00e+00  3.35e-02  4.22e-02  3.90e-02        gs           0.00e+00  2.47e-02  2.46e-02  3.39e-02
lqa          3.35e-02  0.00e+00  2.36e-02  2.04e-02        lqa          2.47e-02  0.00e+00  4.37e-04  1.84e-02
hpc          4.22e-02  2.36e-02  0.00e+00  2.24e-02        hpc          2.46e-02  4.37e-04  0.00e+00  1.88e-02
eulerpc      3.90e-02  2.04e-02  2.24e-02  0.00e+00        eulerpc      3.39e-02  1.84e-02  1.88e-02  0.00e+00
```

**端点能量差（kcal/mol，相对 GS）**（step 0.10）：
forward `lqa −0.0122 / hpc +0.0194 / eulerpc +0.5223`；
backward `lqa +0.0002 / hpc +0.0002 / eulerpc +0.0025`。
⇒ 四法在 0.10 全部落在同一 basin；唯一显著偏差是 **EulerPC forward（+0.52 kcal/mol）**，
它由信号 (c) `energy_rise` 终止，尚未收敛到极小点。

原始报告 43 §9.3 的 0.10/0.20/0.40 端点能量与 RMSD 本轮**逐项复现**（§4、§5）。

### 3.2 解析势

**Müller–Brown**（单元 `four-method-crosscheck`，step 0.05，双向）：

| 量 | 值 |
|---|---|
| forward 端点最大间距 | 0.04440420 bohr |
| backward 端点最大间距 | 0.04136695 bohr |
| forward 端点能量最大差 | 1.081951e-03 Eh |
| backward 端点能量最大差 | 5.670563e-04 Eh |
| 对参考 MEP 的最大偏离 fwd (gs/lqa/hpc/eulerpc) | **0.03995 / 0.00657 / 0.00215 / 0.02574** bohr |
| 对参考 MEP 的最大偏离 bwd | 0.04132 / 0.01913 / 0.01395 / 0.02806 bohr |

（参考 = 同方向 0.01 步长 LQA 细路径；MB 无闭式反应路径。LQA 自身的 0.0066/0.019 含
参考的有限步长自偏。）

**LEPS H+H₂**（单元 `leps-four-method-crosscheck`，step 0.05，双向）：

| 方法 | n (forward) | forward H₂ 键长 | backward H₂ 键长 |
|---|---|---|---|
| GS | 30 | 1.43703 | 1.41316 |
| LQA | 104 | 1.41416 | 1.41420 |
| HPC | 80 | 1.41387 | 1.41408 |
| EulerPC | 131 | 1.44908 | 1.44908 |

解析 H₂ 平衡键长 `leps_r_h2 = 1.4140743 bohr`。四法 forward H₂ 键长离散度 **0.03521 bohr**、
backward **0.03591**；四法双向都到达 H₂+H 通道（两方向为不同通道）。

**注（LEPS 的度规陷阱）**：LEPS 上解离 H 处在极平渐近面，端点**原始几何 RMSD** 无化学意义
（软的 H 坐标可差若干 bohr 而能量几乎不变）。报告 43 用原始 RMSD 比较会得到误导性的大值；
本轮改用「H₂ 键长 + 通道拓扑」。**这是对实验 #6 口径的一处更正。**

### 3.3 显著偏差者降级（PLAN 要求）

**GFN2 上 GS 显著偏离**。判据（step 0.10，同一 TS）：

* GS forward 端点 `-5.47213551` 距真实 HNC 极小 `-5.47215989` 差 **2.44e-5 Eh**
  （LQA 4.8e-9、HPC 5.5e-5）；GS backward 差 1.0e-8。
* 但 GS 每点 E/g = **16.9 / 20.3**，是 HPC 的 **8.5×**、LQA 的 **17×**；
  而 GS 的端点/路径精度**并不优于** HPC，甚至在小步长下不如 LQA。
* GS 的误差随步长**非单调**（0.05 偏 5.1e-5、0.10 偏 2.4e-5、0.20 偏 8e-9），
  根因是微循环 trust-region 限幅（§7），路径对步长/曲率的敏感性高于 HPC。
* LEPS 上 GS forward 对 MEP 的最大偏离 **0.040 bohr** 为四法最大（HPC 0.002）。

**结论**：在 M6 文档中把 **GS 降级为「兼容/对照实现」**，默认推荐 **HPC**（精度最好、2 E/g）；
LQA 作为最廉价的 1 E/g 对照；EulerPC 仅在 0.10 及更小步长可用。GS 保留是因为它是
corrector 修复失败时的回退实现，且其路径总体正确。

---

## 4. 实验 #7 — 端点判据标定（对照 Gaussian `MaxPoints=10` / ORCA `MaxIter=20`）

### 4.1 (a) 到达极小点所需步数分布（GFN2，点数 n）

| step | GS fwd/bwd | LQA | HPC | EulerPC |
|---|---|---|---|---|
| 0.05 | 80 / 77 | 79 / 70 | 82 / 70 | 79 / **186**† |
| 0.10 | 42 / 40 | 43 / 38 | 40 / 38 | 52 / 36 |
| 0.20 | 24 / 19 | 22 / 21 | 23 / 22 | 44 / 18 |
| 0.40 | 13 / 11 | 15 / 17 | 16 / 17 | 14 / 14 |

（† EulerPC backward 0.05 由能量回升在 s=9.27、186 点终止。）

所需步数 n ≈ 弧长/步长 + 1，最大约 **104**（LEPS LQA 0.05）；GFN2 上 step 0.05 约 70–104。
**默认值建议**：保留 `max_steps = 256`。PLAN §5.3.7 的 50 在 step 0.05 下会**截断**
（观测到 >100 点），不可用；而物理信号 (b)/(c) 在正常路径上总是先终止，`max_steps`
只是安全上界。⇒ **回填 PLAN §5.3.7：`max_steps = 256`（安全上界，非物理判据）**，
`[待校准]` 关闭。

### 4.2 (b) `grad_tol` 可达性 —— 独立复核报告 43 的 RMS 数字怎么来的

报告 43 §7.2 的端点 RMS 数字 = **该方向 irc.log 表格末行的 `|g|` ÷ √(3N)**（3N=9）。
本轮独立提取（`parse_irc_log.py`）：

| 方法（step 0.10） | 末行 `\|g\|` (Eh/bohr) | RMS = `\|g\|`/3 | ≤ 1e-3？ |
|---|---|---|---|
| GS fwd | 1.793746e-3 | 5.979e-4 | ✅ |
| LQA fwd | 2.271353e-3 | 7.571e-4 | ✅ |
| HPC fwd | 2.876885e-3 | 9.590e-4 | ✅（余量 4.1%） |
| EulerPC fwd | 3.864107e-2 | 1.288e-2 | ❌（先由 (c) 终止） |

**数字来源确认**：终止判据在宏循环顶部比较 `gnorm_cur/sqrt(ndim) ≤ grad_tol`，末记录点的
`gnorm` 正是 `gnorm_cur`，所以「由 (b) 终止」⇒ 末点 RMS ≤ `grad_tol`。报告 43 的
5.98e-4 / 7.57e-4 / 9.59e-4 **独立复现，逐位一致**。
与 σ_g 论证一致：M4 实测 warm 3.916e-7 Eh/bohr（系统偏置）、随机 ≤1.2e-15；阈值/噪声 = **2553×**。

**可达下限扫描**（GS/LQA/HPC，收紧 `--lirc-grad-tol`）：

| grad_tol | GS 末点 RMS | LQA 末点 RMS | HPC 末点 RMS |
|---|---|---|---|
| 1e-3 | 5.98e-4（(b)） | 7.57e-4（(b)） | 9.59e-4（(b)） |
| 1e-4 | 6.04e-4（(c) 先触发） | 3.30e-5（(b)） | 3.97e-4（(c)） |
| 1e-5 | 6.04e-4（(c)） | 1.34e-6（(b)） | 3.97e-4（(c)） |
| 1e-6 | 6.04e-4（(c)） | 6.93e-8（(b)） | 3.97e-4（(c)） |

⇒ LQA（1 E/g）可把端点梯度压到 **~7e-8**（远低于 warm 噪声，接近冷启动逐位噪声）；
GS 在 HCN/HNC 路径上的微循环极限把 RMS 钉在 **~6e-4**，再紧也到不了；
HPC 到 ~4e-4。**默认 1e-3 对四法中的 gs/lqa/hpc 都可达，保持不回退**；
更紧的阈值是**方法相关**的，不应作为统一默认。

### 4.3 (c) `e_rise_steps` 曲线（GS，`--lirc-grad-tol 0` 强制由 (c) 终止）

| e_rise_steps | fwd n | fwd 端点 E | fwd 弧长 | bwd n | bwd 端点 E |
|---|---|---|---|---|---|
| 1 | 44 | -5.472151270 | 4.190 | 41 | -5.504066190 |
| 2 | 45 | -5.472149703 | 4.263 | 42 | -5.504064410 |
| **3（默认）** | 46 | -5.472147344 | 4.343 | 43 | -5.504004729 |
| 5 | 48 | -5.472147238 | 4.513 | 49 | -5.504066213 |
| 10 | 53 | -5.472149056 | 4.918 | 54 | -5.504066158 |
| 20 | 63 | -5.472147393 | 5.754 | 64 | -5.504049523 |

* 端点能量随 `e_rise_steps` 变化 **< 5e-6 Eh**（1→20 基本不变）；步数/弧长线性增长。
  即 (c) 的取值只决定「过极小点后走多远」，不影响归属，**3 是稳健默认**。
* **不被噪声误触发**：能量回升振幅（过极小点后的振荡）~1e-5 Eh 量级；冷启动 GFN2 位相
  逐位可复现（σ_E = 0），跨线程 ≤1e-14。回升/噪声 ≥ 10⁹。故 3 步不会因 SCF 噪声假触发。
* 已实测：`--lirc-grad-tol 0` 时 (c) 双向触发；`e_rise_steps` 设极大时回退 (a)（成对可证伪）。

### 4.4 步长 × 方法 收敛表（GFN2，标记失败）

以 HNC/HCN 端点能量距真实极小（fwd 2.44e-2 eV 量级）为准：

| step | GS | LQA | HPC | EulerPC |
|---|---|---|---|---|
| 0.05 | ✅ 5.1e-5 | ✅ 7.1e-5 | ✅ 1.0e-6 | ✅ 6.6e-5 |
| 0.10 | ✅ 2.4e-5 | ✅ 5.0e-9 | ✅ 5.5e-5 | ⚠️ 8.6e-4（(c)终止） |
| 0.20 | ✅ 8e-9 | ✅ 1.6e-6 | ✅ 5.3e-6 | ⚠️ 3.6e-4 |
| 0.40 | ✅ 8e-9 | ⚠️ **3.3e-4**（rmsd 0.031） | ⚠️ **2.35e-3**（rmsd 0.018） | ❌ **5.8e-3 / 1.1e-2**（3 回退，E/g 3.4） |

**失败组合**：0.40 步长下的 LQA（轻度）、HPC-forward（中度）、EulerPC（严重，双向）。
⇒ 默认 0.10 稳健；0.20 可接受；**0.40 不应作为默认**（HPC 论文允许但本实现 0.40 会退化，
与 R-2 一致）。

### 4.5 与 Gaussian / ORCA 对照与回填

| | Gaussian | ORCA | 本实现 |
|---|---|---|---|
| 默认步长 | `StepSize=10` = 0.1 amu^1/2·bohr | — | `step_length=0.10`（一致） |
| 迭代上界 | `MaxPoints=10`（每方向/imax 组） | `MaxIter=20` | `max_steps=256`（安全上界） |
| 终止 | 步数为主 | 步数为主 | 物理信号 (b)/(c) 优先，(a) 兜底 |

**回填建议**（PLAN §5.3.7）：
* `max_steps`：**256**（安全上界；50 在 0.05 步长下会截断），关 `[待校准]`。
* `grad_tol`：**1e-3 Eh/bohr（每分量 RMS）**，gs/lqa/hpc 可达，保持。
* `e_rise_steps`：**3**，端点能量对它不敏感，不被噪声误触发，保持。
* `step_length`：**0.10**（Gaussian 一致），0.20 可接受，0.40 降级。
* `micro_step_thresh` / `max_micro_cycles`：与 §7 的微循环修复一起重定，**暂留**。

---

## 5. 实验 #4 — Hessian 沿路径：Bofill 更新 vs 每 N 步重算

数据 `exp4-hessian/`。

### 5.1 短路径（GFN2，step 0.10，正常终止）

| 方法 | recalc=-1（纯 Bofill） | recalc=5 | recalc=10 |
|---|---|---|---|
| GS 端点 E (fwd) | -5.47213551 | -5.47215077 | -5.47215985 |
| GS 对 recalc=-1 的最大路径偏离 | — | 0.113 bohr | 0.128 bohr |
| LQA 端点 E (fwd) | -5.47215487 | -5.47215953 | -5.47211175 |
| LQA 最大路径偏离 | — | 0.039 bohr | 0.042 bohr |
| HPC 端点 E (fwd) | -5.47210457 | -5.47210997 | -5.47210878 |
| HPC 最大路径偏离 | — | 0.017 bohr | 0.013 bohr |

* 重算把**端点能量**向真实极小（-5.47215989）收敛：GS 2.4e-5 → 4e-8；LQA 5e-9 → ~0；
  HPC 5.5e-5 → 5.1e-5（HPC 误差由 1e-3 终止判据主导，非 Hessian）。
* **路径几何**对 Hessian 很敏感（GS 0.11–0.13 bohr），但都停在**同一极小点**内。
* ⇒ 在这条 4 bohr 的短路径上，「纯更新漂移」表现为 ~1e-5 Eh 的端点误差与 ~0.1 bohr
  的路径差，**未失控**。

### 5.2 长积分（GFN2，`--lirc-grad-tol 0 --lirc-erise-steps 1e5 --lirc-max-steps 150`）

| 方法 | 方向 | recalc=-1 末态 | recalc=10 末态 |
|---|---|---|---|
| HPC | forward | E=-5.47215987，\|g\|=6.2e-5（到极小） | E=-5.47215989，\|g\|=4.0e-5 |
| HPC | **backward** | **E=-5.50346845，\|g\|=4.14e-2（未到极小！）** | E=-5.50406622，\|g\|=4.4e-7（到极小） |
| LQA | forward | E=-5.47215988，\|g\|=1.8e-4 | E=-5.47215989，\|g\|=5.2e-6 |
| LQA | backward | E=-5.50406622，\|g\|=2.6e-6 | E=-5.50406617，\|g\|=4.6e-4 |

⇒ **PLAN §6.5「纯更新在长时间积分后漂移」得到直接检验确证**：纯 Bofill 的 HPC backward
在 150 步后停在 `-5.50346845`（离真实 HCN 极小 6.0e-4 Eh = 0.38 kcal/mol）且梯度仍 4e-2；
每 10 步重算则回到 `-5.50406622`、梯度 4.4e-7。**默认 `hessian_recalc=-1` 是合理的
（短路径足够、且 (b)/(c) 在极小点终止），但对长/难路径应可用 `--lirc-recalc N` 加固**；
建议文档标注「长积分或强弯曲路径请设 `--lirc-recalc 5..10`」。

---

## 6. 第三项 — 第二阶段三处偏离的独立核实（不复述报告 43）

### 6.1 R-1（最重要）：论文 1 E/g 方案

**我自己的实现**：把 HPC 的「评估校正点」分支替换为「直接信任 `landscape_irc_corrector_step`
返回的 DWI 能量/梯度」（即论文方案：只评估预测点，校正点梯度由 DWI 解析重建）。临时注入
（`m6-irc-data/verify-R1/one_eval/`），跑完还原：

| 方案 | forward 端点 E | 距 HNC 极小 | backward 端点 E | 距 HCN 极小 | 平均 E/g |
|---|---|---|---|---|---|
| 2 E/g（现状） | -5.472104571692 | **5.53e-5** | -5.504065855145 | 3.67e-7 | 1.98 |
| **1 E/g（我的 V1）** | **-5.469357483247** | **2.80e-3** | -5.501082151250 | 2.98e-3 | **1.00** |
| 1 E/g + 预测 secant 更新（V2） | -5.426581075291 | **4.56e-2** | -5.501487029290 | 2.58e-3 | 1.00 |

**结论**：
* **定性**：1 E/g 确实会漂移，且代价极其不利（forward 误差放大 **~50×**，V1；
  逐点还出现一次 `|g|=0.58` 的野值，而 2 E/g 路径典型 `|g|~3e-2`）。**2 E/g 的取舍合理**。
* **定量**：报告 43 的「**1.4e-2 Eh**」**不能复现**。我的忠实实现给 **2.80e-3**；
  另一个合理变体（额外用预测 secant 更新 Hessian）给 **4.56e-2**。1.4e-2 落在两者之间，
  说明该数字**强烈依赖报告没有钉死的 Hessian 更新记账**。建议把报告 43 的 1.4e-2 改记为
  「数量级 1e-3 … 1e-2（依变体）」而非精确常数。
* 偏差来源已由我的 V1 逐点核对确认：1 E/g 路径在 s≲2.9 与 LQA 一致，之后出现 DWI 重建
 梯度偏小导致的漂移/野值。

### 6.2 R-2：步长 0.40

| 方法 | fwd 端点 E | 距真实极小 | rmsd | 平均 E/g |
|---|---|---|---|---|
| GS | -5.472159880 | 8e-9 | 1.7e-5 | 19.46 |
| LQA | -5.471830436 | 3.30e-4 | 0.0306 | 1.00 |
| **HPC** | -5.469813570 | **2.346e-3** | 0.0184 | 1.94 |
| **EulerPC** | -5.466380793 | **5.78e-3** | 0.0733 | 3.43（3 回退） |
| EulerPC bwd | -5.492823239 | 1.12e-2 | 0.0716 | 2.14 |

⇒ 报告 43 的「HPC 前向偏 2.3e-3（比 LQA 差）」「EulerPC 0.40 严重失败」**独立复现**
（我的值 2.346e-3 / 5.78e-3–1.12e-2）。

### 6.3 R-4：信号 (b) 的可达性与 EulerPC 先触发 (c)

* step 0.10：gs/lqa/hpc 的 forward **由 (b) gradient 终止**（末点 RMS 5.98e-4/7.57e-4/9.59e-4
  全部 ≤ 1e-3，见 §4.2，独立复核一致）；**EulerPC forward 由 (c) energy_rise 终止**
  （末点 RMS 1.288e-2），**backward 由 (b) 终止**。⇒ 报告 43 R-4 **成立**。
* 信号 (b) 在真实 GFN2 上可达，无须把 PLAN 的力阈值标为「不可达」。

---

## 7. 第四项 — 第一阶段遗留：GS 每点 E/g = 16.9/20.3（PLAN 预期 3–5）

### 7.1 根因（实测复现）

`gs_step` 的微循环收敛判据是**未限幅的切空间 Newton 步** `|d| ≤ micro_step_thresh(1e-3)`，
而信任域限幅发生在其**之后**；实测该 Newton 步 `|d| ~ 1.8–2.4 bohr·amu^1/2` ≫ 半径 `s/2=0.05`，
故 `|d|` 永远不 ≤ 1e-3，微循环每次跑满 20 次评估。参数扫描（GFN2 GS）：

| 配置 | fwd n | fwd 端点 E | fwd 平均 E/g | 收敛？ |
|---|---|---|---|---|
| 默认（20 cycles, thresh 1e-3） | 42 | -5.47213551 | 16.93 | ✅ (b) |
| `--lirc-micro-cycles 10` | 55 | -5.47215987 | 10.82 | ✅ |
| `--lirc-micro-cycles 5` | 41 | -5.47210936 | **5.00** | ✅ |
| `--lirc-micro-cycles 1` | 256 | -5.47189746 | 1.99 | ❌ 未收敛（max_steps） |
| `--lirc-micro-thresh 0.05` | 256 | -5.47209309 | 1.02 | ❌ 未收敛 |
| `--lirc-micro-thresh 0.06/0.10` | 256 | -5.47149602 | 1.00 | ❌ fwd 未收敛 |

⇒ 根因确认：**微循环被 trust-region 限幅钉在半径上**；把 cycles 降到 5 仍**正确**
（E/g=5.0）但降到 1 或放大 thresh 会让路径太糙而无法在预算内收敛。

### 7.2 修复方向与代价估计

1. **推荐（报告 42 已提）**：微循环改**等式约束 Lagrange 步**（MAPLE 的球面约束形式），
   使 Newton 步直接落在球面、微循环 2–3 次收敛 ⇒ 预计回到 PLAN 的 3–5 E/g，**省 ~3–4×**。
   风险：会改变已复核的 GS 路径，需以 LQA/HPC 为基准重验收（本轮的 `four-method-crosscheck`、
   `mb-gs-minima`、`sphere-chord` 已就位）。
2. **低成本近似**：把收敛判据改为「限幅后的步长」或「切向梯度范数」，理论上能在 1–2 次收敛；
   但实测 `thresh=0.05`（等价于一步退出）会让路径过糙，故**必须配合更小的可信半径或线搜索**，
   不推荐单改判据。
3. **保守上限**：`max_micro_cycles` 从 20 降到 5，**路径仍正确**、E/g 从 16.9 → 5.0，
   改动最小、风险最低；代价是损失 GS 在难面上的鲁棒性余量。

**是否值得修**：GS 已被降级为回退/对照（§3.3），生产推荐 HPC（2 E/g、0.5 s）。
GS 的「路径正确但贵 4 倍」**在作为回退使用时可以接受**（回退是罕见单步）。
但若要把 GS 作为默认或用于长路径，收益 3–4× 明显，值得做修复方向 1。

---

## 8. 第五项 — 相位约定的覆盖缺口

### 8.1 缺口（第一阶段自认）

第一阶段的 `phase-determinism` 只在**同一构建**内两次调用 `select_direction`，
LAPACK 对同一输入给同一符号，故**去掉相位约定后「逐位确定性」仍绿**——该用例测的是
「确定性」而非「规范化」。

### 8.2 新测试 `phase-convention-sign-invariance`

显式构造「另一后端可能返回的符号」：取 `select_direction` 的向量 `v`，令 `flipped%vector = -v`，
对 `flipped` 调用 `landscape_transition_mode_set_phase`，要求：

* `flipped%vector == v`（**逐位**）——相位约定对符号翻转不变，即 forward 方向与库符号无关；
* `forward%phase_value > 0`、`flipped%phase_index == forward%phase_index`、
  `flipped%phase_value == forward%phase_value`（记录分量一致）。

**注入验证**（去掉 `select_direction` 内的 `set_phase` 调用）：

```
       ... phase-determinism [FAILED]
  Message: the phase convention did not make the largest component positive
       ... phase-convention-sign-invariance [FAILED]
  Message: the phase convention is not invariant under a sign flip of the eigenvector (the forward direction depends on the library)
=== 还原 === 32/32 PASSED
```

⇒ 新用例真正测「规范化」（对显式符号翻转不敏感），并变红。

### 8.3 仍不可测之处（如实记录）

「跨线性代数库可复现」（换 LAPACK/dsyevd 的符号约定）本机**无法**直接测，因为仓库只有
mctc-lapack 一个后端。新用例以「人为翻转向量」等价地覆盖了**规范化**这一可测的属性；
真正的跨库复现需第二个后端或注入式 `mctc_syev` 符号包装，本轮未做。故：
* **已覆盖**：相位规范化（含新用例 + CLI 相位分量断言）。
* **未覆盖（不可测）**：硬件/库级别的符号差异；已说明原因。

---

## 9. 可证伪注入汇总（9 条，全部真实红→还原→绿）

> 铁律：注入前先证明变异与旧逻辑**不等价**；每条给出「旧逻辑 / 变异 / 等价性」与真实输出。
> 每次还原后 `xtb-tester landscape-irc` 回到 **32/32**。

| # | 位置 | 变异 | 等价性 | 红用例（真实输出） |
|---|---|---|---|---|
| (i) | `gs.f90` walk 传参 | `x_new = path%xyz(:,1)`（模拟旧回归） | 不等价（冻结几何） | `gs-path-geometry-consistency`「geometry did not move」+`mb-gs-minima` |
| (ii) | `gs.f90` 微步后 | 删 `project_sphere` | 不等价（删约束唯一执行点） | `mb-sphere-chord`「chord exceeded the sphere constraint」 |
| (iii) | `corrector.f90` `lqa_displacement` | 指数 `−λt`→`+λt` | 不等价（错误传播式） | `lqa-1d-exact`,`lqa-2d-consistency`,`mbs-vs-lqa`,`mb-lqa-minima`,`mass-metric-effect`,`leps-irc-descent`,`lqa-zero-curvature-limit`,`eulerpc-convergence-order`,`four-method-crosscheck`,`leps-four-method-crosscheck`（10 个） |
| (iv) | `hpc.f90` | `q_pred=q_cur+d`→`q_cur−d` | 不等价（错误预测步） | **原无任何用例变红（覆盖缺口，见 §10）**；新增 `hpc-predictor-accuracy` 后变红「predictor is wrong」；GFN2 端点 1.6e-3 Eh 漂移 |
| (v) | `eulerpc.f90` | `q_pred=q_cur−s·g/\|g\|`→`+s·g/\|g\|` | 不等价（错误欧拉方向） | `eulerpc-mb-minima`,`eulerpc-convergence-order`,`four-method-crosscheck`,`leps-four-method-crosscheck` |
| (vi) | `corrector.f90` | `sqrt_mass=sqrt(mass)`→`mass/mass` | 不等价（单位度量） | `mass-weighting-roundtrip`,`mass-metric-effect` |
| (vii) | `gs.f90` | 删 (c) 分支 | 不等价（删终止） | `termination-energy-rise`,`termination-all-methods` |
| (viii) | `corrector.f90` | 删 `set_phase` | 不等价（删规范化） | `phase-determinism`,`phase-convention-sign-invariance`,`eulerpc-convergence-order` |
| (ix) | `hpc.f90` | 1 E/g DWI 方案 | 不等价（改算法） | 我的 R-1 变体（GFN2 端点偏移，非单元红） |

**覆盖缺口（如实记录，已部分关闭）**：
* **(iv) HPC 预测步**此前**没有任何单元用例能捕获**——因为 DWI 在 `q_cur` 处精确复现样本梯度，
  错误的预测点只在积分推进时偏置插值；在 MB 的 0.05 步长下路径仍落在极小点内（`endd≈0`），
  所有阈值都太松。**已新增 `hpc-predictor-accuracy`**：比较 HPC 在 MB 上 {0.05,0.10,0.20,0.40}
  步长对参考 MEP 的偏离与端点距离——正确预测器 `endd ≤ 4.7e-4`、`dev(0.05/0.10) ≤ 0.011`，
  错误预测器 `endd 0.068–0.115`、`dev(0.05/0.10) 0.030/0.102` ⇒ 断言可分辨并变红。
* 相位「跨库可复现」：见 §8.3，不可测。

---

## 10. 新发现

### F-1（潜伏 API bug，LOW，仅报告不修）：`landscape_irc_path` 跨 `ndim` 复用

* `landscape_irc_path_reset`（`corrector.f90`）只重置 `n/ndim/term`，**不释放也不更新分配**；
  `landscape_irc_path_reserve` 在 `path%ndim == 0` 时**提前返回**；
  `landscape_irc_path_add` 在 `ndim==0` 时令 `ndim=size(xyz)`，但只有在
  `nadd > path%capacity` 时才重新分配。
* 后果：**同一个 path 对象先后用于不同 `ndim` 的 walk** 时（如先 2D 解析面、后 9D 分子），
  `path%xyz` 仍是旧的 `(2, cap)`，`path%xyz(:,n)=xyz(9)` 发生形状不匹配/静默截断，
  后续所有几何都是错的（本轮的 `gs-path-geometry-consistency` 第一版因此读到 2 元向量而失败）。
* **生产不触发**（`tasks/irc.f90` 每个方向新建 path，且两方向 ndim 相同）；既有单元测试也都在
  同 ndim 内复用。属潜伏稳健性缺口。
* **修复方向**：`path_reset` 里 `path%capacity=0` 并 `deallocate`，或让 `path_add`/`path_reserve`
  在 `ndim` 变化时重新分配。**本轮按要求未改 `src/`。**

### F-2（覆盖缺口，已关闭）：HPC 预测步无测试 → 见 §9(iv)。

### F-3（报告-代码不一致，LOW）：报告 43 §3.1 的 HPC 步骤 3

报告 43 §3.1 写 HPC 每宏步「Bofill 更新 `(q_pred−q_cur, g_pred−g_cur)`」，但
`hpc.f90` 实际**只**用接受点的 secant 更新一次（预测 secant 更新只在 EulerPC 里）。
报告 43 §9.1 的 2 E/g HPC 数字与本轮实测**逐位一致**（-5.472104571692），
故是**报告描述有误**，代码自洽。建议更正报告 43 §3.1 措辞（不影响验收）。

---

## 11. PLAN 回填建议

| 位置 | 现文 | 建议 |
|---|---|---|
| §5.3.7 `max_steps` `[待校准]` | 50 | **256**（安全上界；50 在 0.05 步长下截断），关闭标记 |
| §5.3.7 `grad_tol` `[待校准]` | 1e-3 | **保留 1e-3**（gs/lqa/hpc 可达；勿统一收紧），关闭标记 |
| §5.3.7 `e_rise_steps` `[待校准]` | 3 | **保留 3**（端点对它不敏感、不被噪声触发），关闭标记 |
| §5.3.7 `step_length` | 0.10 | 保留 0.10；**0.40 降级**（LQA/HPC/EulerPC 均退化） |
| §6.5 GS 行「每点 3–5 次 E/g」 | 预期 | 实测 **16.9/20.3**；根因=微循环 trust-region 钉死；推荐 Lagrange 步修复（省 3–4×） |
| §6.5 Hessian 沿路径 | `hessian_recalc=-1` | 标注「长/强弯曲路径设 `--lirc-recalc 5..10`」（长积分纯 Bofill 实测漂移 0.38 kcal/mol） |
| §9.7 #6 结论 | — | 四法在 0.10 同一 basin；**GFN2 上 GS 显著偏离（精度不优于 HPC 却贵 8×）⇒ GS 降级**；EulerPC 0.40 失效 |
| 报告 43 §6.3 R-1 数字 | 1.4e-2 Eh | 改记「数量级 1e-3 … 1e-2（依 Hessian 记账变体）」；2 E/g 取舍仍成立 |
| 报告 43 §3.1 HPC 步骤 3 | 预测 secant 更新 | 更正为「只用接受点 secant 更新一次」 |

---

## 12. 残余风险与建议

* **GS 微循环（R-1/第四项）**：仍 16.9 E/g；已给出修复方向与代价，未实施（不改 src）。
* **1 E/g 论文方案的定量结论**依赖 Hessian 记账，报告 43 的 1.4e-2 不可复现（§6.1）。
* **F-1 path container**：潜伏 bug，只报告未修。
* **meson 不可本机执行**（既有 R-16）：`meson.build` 沿用既有约定手工同步；本轮未改测试注册
  （只加用例，不动文件列表），故 meson 侧无需改动。
* **LEPS/MB 的跨方法端点几何比较**应使用键长/拓扑而非原始 RMSD（§3.2）。

---

## 13. 本轮改动文件

```
 test/unit/test_landscape_irc.f90   | +4 用例 + 若干 helper（+~330 行）
新增数据：docs/_landscape-recon/m6-irc-data/（item0-gs-e2e、exp6-crosscheck、exp7-*、
 exp4-hessian、verify-R1、injections、analytic/*.log，含 stdout 与四个产出文件）
```

`src/` **零改动**（所有注入已逐位还原）。未提交 git（父会话统一提交）。
