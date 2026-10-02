# 43 — M6 IRC 第二阶段（HPC + EulerPC + 端点终止与归属）实现报告

> 里程碑：M6（第二阶段）。范围：**HPC、EulerPC、四方法的端点终止与归属、CLI 补齐、验证实验、注入**。
> HEAD：`2ed7750`（M5 提交之后的工作树，未提交；父会话统一提交）。
> 所有 `xtb` / `ctest` 调用均带 `OMP_NUM_THREADS=1`。
> 第一阶段报告：`42-m6-irc-core-implementation-report.md`。

---

## 0. 摘要

| 项 | 结果 |
|---|---|
| 新增源文件 | `src/landscape/irc/{hpc,eulerpc}.f90` |
| 改动既有文件 | `irc/corrector.f90`（λ→0 分支、corrector step、path reset）、`irc/gs.f90`（拆出 `gs_step`）、`irc/lqa.f90`（path reset）、`tasks/irc.f90`（hpc/eulerpc 分派、Kabsch 对齐 RMSD）、`types/results.f90`（RMSD 语义）、`prog/main.F90`/`xhelp.f90`（新 CLI） |
| LOC | hpc 380 / eulerpc 355 / corrector +210 / gs 拆分后 487 / 测试 1770 |
| 构建 | 0 warning（`touch` 全部 IRC 文件后重建） |
| `ctest -R landscape` | **77/77**（M6 第一阶段结束 77；本轮删 1 个「hpc 未实现」测试、加 1 个 `xtb/landscape-irc-pc`，数量不变） |
| 回归子集 | `-R 'Singlepoint\|GFN\|model-hessian\|optimizer\|Argparser\|CAPI'` → **12/12** |
| 重名检查 | `grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt \| sort \| uniq -d` → **空** |
| 单元套件 | `landscape-irc` **28/28**（+10 用例：HPC/EulerPC 极小点、E/g 分布、回退、loose_cycles、收敛阶、三信号全方法、梯度判据量级、四法互校） |
| 端到端 | `--lirc-method hpc` 与 `--lirc-method eulerpc` 均 exit 0，四文件齐全，端点 = HNC / HCN（§9） |
| 可证伪注入 | **4/4 按预期变红并已还原**（§12），另加 1 个「旧 skip 逻辑」变体 |
| 修掉的回归 | Phase 1 的 GS 重构回归 `mb-gs-minima`（§4）与一个**路径累积真 bug**（§5） |
| **关键测量** | HPC/EulerPC 每点 **~1.9–2.0 E/g**（不是论文的 1，也不是 GS 的 16.9；根因见 §6） |

---

## 1. 交付物与文件

| 文件 | 内容 |
|---|---|
| `src/landscape/irc/hpc.f90`（380 行） | HPC：LQA 预测（Eqs.2–11）+ DWI/mBS 校正 + Bofill + GS 回退 + 三终止信号 |
| `src/landscape/irc/eulerpc.f90`（355 行） | EulerPC：一阶 Euler 预测（Eq.2）+ 同 HPC 的校正 + `loose_cycles` 粗/细 + GS 回退 + 三终止信号 |
| `src/landscape/irc/corrector.f90` | 新增 `landscape_irc_corrector_step`（两点 DWI + mBS + DWI 取值）、`landscape_irc_path_reset`；`lqa_displacement`/`speed` 加 **λ→0 的可去奇点分支 `a_ii → -t`** |
| `src/landscape/irc/gs.f90` | 拆出公开 `landscape_irc_gs_step`（HPC/EulerPC 回退复用），`gs_walk` 变薄环 |
| `src/landscape/tasks/irc.f90` | `hpc`/`eulerpc` 分派；端点 RMSD 改为 **Kabsch 对齐**；`irc.log` 记录对齐方式 |
| `src/prog/main.F90` / `src/xhelp.f90` | `--lirc-loose-cycles`、`--lirc-endpoint-relax`、`--lirc-erise-steps`（`--lirc-e-rise` 的别名）；修正 `--lirc-grad-tol` 的 help 默认值（1e-4 → 1e-3） |
| `test/unit/test_landscape_irc.f90`（1770 行） | +10 单元用例（共 28） |
| `test/unit/CMakeLists.txt` / `meson.build` | 删 `landscape-irc-hpc-unimplemented`；加 `xtb/landscape-irc-pc`（HPC+EulerPC 端到端 + 新 flag + 端点归属负例） |
| `test/unit/landscape_cli_check.py` | 新增 `ircpc` 模式（meson 镜像，本机手工执行通过） |
| `src/landscape/CMakeLists.txt` / `meson.build` | 注册 `irc/hpc.f90`、`irc/eulerpc.f90`（两处手工同步） |

---

## 2. 接口契约（延续 PLAN §12.14）

1. 输入几何 = TS 本身；虚频确认复用 M3；`hpc`/`eulerpc` 与 `gs`/`lqa` 同一入口。
2. 单位契约不变：**质量加权 Cartesian，1 a.u. = 1 bohr*amu^1/2**。
3. **校正**：复用 `corrector.f90` 的 DWI 面 + 修改 Bulirsch–Stoer（简单 Euler 基步 + Richardson 外推）。
   两点 DWI = **当前点 + 预测点**（Hratchian & Schlegel Eqs.5–6）。
4. **校正失败 → 回退到 GS 一步 + `env%warning`**：由拆出的 `landscape_irc_gs_step` 执行。
5. **每点 E/g**：新建同一套插桩（`path%n_eval`）实测，见 §6。
6. Hessian 沿路径：Bofill（更新后强制对称化），`--lirc-recalc N` 可选重建；DWI 共用当前 Hessian。
7. 三终止信号与 Phase 1 完全一致：(a) `max_steps`、(b) RMS 每分量 `|g| ≤ grad_tol`、(c) 连续 `e_rise_steps` 步未刷新运行最小值。

---

## 3. 算法与实现要点

### 3.1 HPC（`irc/hpc.f90`）

每一个宏步：

1. **预测**：`landscape_irc_lqa_step`（0 E/g）——二次模型解析传播
   `x(t) = x_0 + U a(t) U^T g_0`，`a_ii(t) = (e^{-λ_i t} − 1)/λ_i`，`t` 由请求弧长定（`euler_n` 子步）。
   **λ→0 走可去奇点分支 `a_ii → −t`**（`corrector.f90` 显式分支，不做除零、也不丢模）。
2. **评估预测点**（1 E/g）。
3. **Bofill 更新**：`(q_pred − q_cur, g_pred − g_cur)`。
4. **校正**：`landscape_irc_corrector_step` —— 用 (当前点, 预测点) 两点 DWI + mBS 从当前点积分 `step` 弧长 → 校正点。
5. **评估校正点**（1 E/g）→ 记录并前进。
6. 校正不收敛（mBS 未达 `mbs_tol` 或耗尽预算）→ **回退 `landscape_irc_gs_step` + `env%warning`**，路径继续。

### 3.2 EulerPC（`irc/eulerpc.f90`）

1. **预测**：一阶显式 Euler `q_pred = q_cur − step·g_cur/|g_cur|`（0 E/g，**不需要 Hessian**）。
2. 其余与 HPC 相同（评估预测点 → Bofill → DWI/mBS → 评估校正点）。
3. **`loose_cycles` 的「粗/细」定义**（写清，可测）：
   - **粗（coarse）阶段** = 最前 `loose_cycles` 个宏步，**直接记录 Euler 预测点**（1 E/g），不调用校正器；
   - **细（fine）阶段** = 从第 `loose_cycles+1` 步起，使用 DWI/mBS 校正（2 E/g）；
   - `loose_cycles = 0` 关闭粗阶段（全程细）。
   这是对 MAPLE `loose_cycles`（只放宽预测器长度收敛）的**有意收紧**，以便分支可观测；已记录为偏离（§14 D-4）。

### 3.3 corrector step（共享）

`landscape_irc_corrector_step(env, hq, q_a, e_a, g_a, q_b, e_b, g_b, s_target, tol, base_points, max_k, max_points, dwi_n, q_corr, e_corr, g_corr, converged, fail)`：
建两点 DWI（共享 `hq`），`landscape_irc_mbs_integrate` 从 `q_a` 积分 `s_target`，返回 `q_corr` 及其 DWI 能量/梯度（**本实现不使用 DWI 值记录路径**，见 §6）。

---

## 4. 先修：GS 重构回归（父会话实测 `mb-gs-minima` 红）

### 根因（file:line）

拆 `gs_walk` / `gs_step` 时，`landscape_irc_gs_step` 返回 `q_new`（加权）/`e_new`/`g_new`，但 **没有返回 Cartesian 几何 `x_new`**，而 `x_new` 在重构后成了 `gs_step` 的**局部数组**。
`gs_walk` 里 `call landscape_irc_path_add(path, x_new, …)` 用的仍是 walk 自己的 `x_new`——**它只被赋过一次值（第一个点）**。
后果：**每个记录点的几何都是第一个点**，能量却逐点更新；路径能量单调下降但几何冻结，`mb-gs-minima` 的端点因此停在首个点附近（实测 `(-0.802967, 0.608106)`，即 saddle 邻域），报 "the forward endpoint is not near a Mueller-Brown minimum"。

### 修复

`landscape_irc_gs_step` 新增 `real(wp), intent(out) :: x_new(:)`（`gs.f90` 步签名 + walk 调用同时更新）。
**不是**改语义，只是把重构时丢掉的传参补回。

### 行为保持性（外部参照 = 报告 42，逐位对照）

规范 HCN/hnc TS 端到端 `--lirc --lirc-method gs`（Phase 2 重建后）：

| 量 | 报告 42 | 本轮 | 差 |
|---|---|---|---|
| forward 端点能量（HNC） | -5.472135505135 Eh | **-5.472135505135 Eh** | 0 |
| backward 端点能量（HCN） | -5.504066222136 Eh | **-5.504066222136 Eh** | 0 |
| forward reached min rmsd | 0.009860 bohr | 0.009860 bohr | 0 |
| backward reached min rmsd | 0.000016 bohr | 0.000016 bohr | 0 |
| TOTAL ENERGY | -5.387373532405 Eh | -5.387373532405 Eh | 0 |
| forward 点数 / 平均 E/g | 42 / 16.93 | 42 / **16.93** | 0 |
| backward 点数 / 平均 E/g | 40 / 20.25 | 40 / **20.25** | 0 |

⇒ **重构逐位行为保持**。`landscape-irc` 单元套件 18/18（当时）→ `ctest -R landscape` 77/77。

---

## 5. 顺带修掉的真 bug：路径对象跨 walk 累积

`landscape_irc_path_add` 只**追加**（`nadd = path%n + 1`），`landscape_irc_path_reserve` 从不截断。
生产路径（`tasks/irc.f90`）每次用新的 `path_fwd/path_bwd`，没暴露；但**同一个 `path` 对象被两次 walk 复用时，第二个方向会追加到第一个方向之后**，`path%n`、`s()`、`term` 全部被污染。
单元测试里 `termination-*`、新加的收敛阶测试都复用了 `path`，这是 §4 之外被发现的第二个真问题。

**修复**：新增 `landscape_irc_path_reset(path)`（`corrector.f90`），四个 walk 开头一律调用（并写清理由）。
这是接口层面的加固，不改任何工程语义。

---

## 6. 每点 E/g 实测（同一套插桩）

`irc.log` 的 `E/g` 列 = `path%n_eval`，由 `model%evaluate` 的实际调用点计数（GS 的微循环内、HPC/EulerPC 的预测点与校正点、LQA 的单点）。

### 6.1 真实 GFN2 HCN/HNC（step 0.10，双向）

| 方法 | forward 平均 E/g | backward 平均 E/g | 回退次数 | 终止信号 |
|---|---|---|---|---|
| GS | 16.93 | 20.25 | 0 | gradient / gradient |
| LQA | **1.00** | **1.00** | 0 | gradient / gradient |
| **HPC** | **1.98** | **1.97** | 0 | gradient / gradient |
| **EulerPC** | **1.92** | **1.89** | 0 | energy_rise / gradient |

### 6.2 解析 Müller–Brown（单元 `pc-eval-distribution`）

```
mean E/g  lqa 1.0000  hpc 1.9615  eulerpc 1.8000
HPC E/g histogram (0..5)      0     1    25     0     0     0
```
（1 个点 1 次 E/g = 首点/粗 E/g；其余全部 2 次。）

### 6.3 **HPC 为什么不是 1 次 E/g（"查明原因"）**

论文的「每点 1 次 E/g」来自：**只用预测点的一次评估**，校正点的梯度**从 DWI 解析重建**并喂给下一个预测器。我们**按论文原样实现并实测**了这条路线：

* 一次 E/g 变体的实测：`|g|` 降到 2.5e-3、`termination: gradient` 触发，
  但 forward 端点 **-5.458496467106 Eh**，比真实 HNC 极小 **高 1.4e-2 Eh**（GS/LQA 均为 -5.4721）。
  **更正（报告 44 §6.1，2026 M6 验证轮；此处保留原始记录）**：该 1.4e-2 **不能复现**。
  忠实实现给出 forward 端点偏 **2.80e-3 Eh**（V1：只评预测点、信 DWI 梯度）与 **4.56e-2 Eh**
  （V2：再加预测 secant 更新），均 @1.00 E/g；现统一表述为「量级 **1e-3..1e-2 Eh**」。
  2 E/g 的取舍不变（2 E/g 实测偏 5.5e-5）。源码 `hpc.f90:54` 与 PLAN §12.15 已同步订正（报告 46 §M-2）。
* 逐点对照：HPC 与 LQA 在 s≲2.5 一致，之后 HPC 能量持续高于 LQA（s=3.25 时 -5.4585 vs -5.4668），
  即 **DWI 重建的梯度把路径拽离 MEP**。根因：预测点与当前点构成的两点 DWI 在预测端被最近样本主导，
  重建梯度系统性偏小（`|g|_DWI ≈ 2.5e-3` 而该处真实 `|g| ≈ 2.6e-2`，小一个数量级），
  该偏置通过 `g_cur` 进入下一个预测器，30+ 步后积累成 1e-2 Eh 量级的路径漂移。

因此本实现对**校正点也做一次评估**：逐步 (几何, 能量, 梯度) 三元组自洽，路径不再漂移（端点回到 -5.4721），
代价是 **2 E/g/点**。参照实现 MAPLE 同样评估校正点，且额外重复评估当前点 ⇒ **3 E/g/点**；
本实现比参照实现少一次。**结论：本实现对「1 E/g」的偏离是经实测定位的算法后果，不是实现 bug**（详见 §13 R-1）。

---

## 7. 终止信号与信号 (b) 在真实 GFN2 上的可达性

### 7.1 三信号在四方法上各自独立触发（单元 `termination-all-methods`）

对 gs / lqa / hpc / eulerpc 分别构造：

| 信号 | 构造 | 断言 |
|---|---|---|
| (a) max_steps | `--lirc-max-steps 5`、`e_rise_steps` 极大 | `term == max_steps`、`n == 5` |
| (b) grad_tol | `grad_tol = 1.0`（MB 上任何梯度都低于它） | `term == grad` |
| (c) energy_rise | `grad_tol = 0`、`e_rise_steps = 3` | `term == energy_rise`、`n < 200` |

四方法 × 三信号 **12/12 通过**；`termination-gradient-scale` 进一步钉住判据的**量级**（见 §12 (iii)）。

### 7.2 信号 (b) **可达**——用 M4 的 σ_g 论证并实测

M4 实验 #4 实测（报告 28）：GFN2 冷启动**位相等**（重复调用差 0）、跨 `OMP_NUM_THREADS` ≤ **1.11e-15** Eh/bohr、
warm-restart **3.916e-7** Eh/bohr（系统偏置）。默认 `grad_tol = 1e-3`（RMS 每分量）：

* 阈值与噪声之比：`1e-3 / 3.916e-7 ≈ 2553`（warm）、`1e-3 / 1.11e-15 ≈ 9e11`（冷）→ **阈值远在噪声之上**；
* 与端点实测对照（step 0.10，3N=9 ⇒ RMS = |g|/3）：

| 方法 | 端点 `\|g\|` (Eh/bohr) | RMS 每分量 | ≤ grad_tol=1e-3？ |
|---|---|---|---|
| GS | 1.79e-3 | 5.98e-4 | ✅ |
| LQA | 2.27e-3 | 7.57e-4 | ✅ |
| HPC | 2.88e-3 | 9.59e-4 | ✅（余量 4%） |
| EulerPC（forward） | 3.86e-2 | 1.29e-2 | ❌（此方向先由 (c) `energy_rise` 终止） |

⇒ **信号 (b) 在真实 GFN2 上可达**（gs/lqa/hpc 三方法 forward 实测触发），**不必回填 PLAN 的 [待校准] 为"不可达"**。
但 **EulerPC 的 forward 方向实测由 (c) 先触发**：其 Euler 预测器在通往 HNC 的弯曲段偏早越谷，尚未把 RMS 压到 1e-3。
故 (b) **可达但非总是第一个触发**——这就是「物理信号优先、max_steps 只作上界」的设计代价，已写入 §13 R-4。

---

## 8. 端点归属（Kabsch 对齐）

`relax_endpoint` 现在报告 **Kabsch 对齐后的 RMSD**：把端点几何按质心平移到 relaxed minimum，再用
`types/coords.f90` 的 `align_geometry`/`kabsch_align`（M5 的 mass-free 正旋转）旋转到最佳重合，然后取 RMS。
**对齐方式已写进 `irc.log`**：
```
endpoint rmsd is Kabsch aligned (mass free proper rotation onto the relaxed minimum)
```
`landscape_irc_result%rmsd_to_min_fwd/bwd` 的类型注释同步更新。端点弛豫复用**同一个 engine model**，
因此继承 IRC 的 **restart 策略与冻结 etemp**（M6 硬约束 5）。

`endpoint_reached`：只有 (b)/(c) 终止**且**（若要求弛豫）弛豫收敛，才记 `reached_min = T`；
被步预算截断的路径记 **F**（`xtb/landscape-irc-pc` 的负例断言，也是注入 (iv) 的靶点）。

---

## 9. 端到端实测（真实 GFN2，规范 HCN/hnc TS）

### 9.1 `--lirc --lirc-method hpc`（exit 0，OMP_NUM_THREADS=1）

```
 landscape: intrinsic reaction coordinate (hpc)
 step length:               1.000000E-01 bohr*amu^1/2
 Hessian update:           bofill
 restart policy:           off
 electronic temperature:        300.000 K (frozen for the whole run)
 transition state imaginary modes: 1
 confirmation: first order saddle point
 transition mode index:     1 (eigenvalue -7.695905E-02
 phase component:              0.928068 (cartesian 1 of atom 1)
 wrote e2e3.irc_forward.xyz with 41 frames
 wrote e2e3.irc_backward.xyz with 39 frames
 wrote e2e3.irc_path.xyz with 79 frames
 wrote e2e3.irc.log
 termination forward:      gradient
 termination backward:     gradient
 forward points:           40      backward points:          38
 forward arc length:               3.941883 bohr*amu^1/2
 backward arc length:              3.702040 bohr*amu^1/2
 forward endpoint energy:       -5.472104571692 Eh   (HNC)
 backward endpoint energy:      -5.504065855145 Eh   (HCN)
 forward reached minimum:  T (rmsd     0.014953 bohr)
 backward reached minimum: T (rmsd     0.000108 bohr)
normal termination of xtb
```
四个产出文件（`ls -la`）：`e2e2.irc_forward.xyz`(13275) / `e2e2.irc_backward.xyz`(12627) /
`e2e2.irc_path.xyz`(19191) / `e2e2.irc.log`(6909)。`irc_forward.xyz` 首帧 = TS（-5.387373532405 Eh），
末帧 = -5.472104571692 Eh 的 HNC。

### 9.2 `--lirc --lirc-method eulerpc`（exit 0）

```
 landscape: intrinsic reaction coordinate (eulerpc)
 electronic temperature:        300.000 K (frozen for the whole run)
 transition state imaginary modes: 1 ; confirmation: first order saddle point
 wrote e3e.irc_forward.xyz with 53 frames / e3e.irc_backward.xyz 37 / e3e.irc_path.xyz 89 / e3e.irc.log
 termination forward:      energy_rise      termination backward:     gradient
 forward points:  52   backward points: 36
 forward endpoint energy:  -5.471303196478 Eh   (HNC)   rmsd 0.020655 bohr
 backward endpoint energy: -5.504062206802 Eh   (HCN)   rmsd 0.003009 bohr
 mean energy/gradient evaluations per point:  1.92 forward / 1.89 backward
normal termination of xtb
```
四个文件：11979 / 17163 / 21621 / 7666 字节。

### 9.3 步长对照 0.10 / 0.20 / 0.40（真实 GFN2，双向）

端点能量 / RMSD·(bohr) / 平均 E/g；**粗体 = 端点明显偏离真实极小点**：

| step | GS | LQA | HPC | EulerPC |
|---|---|---|---|---|
| 0.10 | -5.4721355 / 16.9 | -5.4721549 (1.0) | -5.4721046 / rmsd 0.0150 (2.0) | -5.4713032 / rmsd 0.0207 (1.9) |
| 0.20 | -5.4721599 / 18.8 | -5.4721582 (1.0) | -5.4721545 / rmsd 0.0044 (2.0) | -5.4717986 / rmsd 0.0138 (2.0) |
| 0.40 | -5.4721599 / 19.5 | **-5.4718304 / rmsd 0.0306** | **-5.4698136 / rmsd 0.0184** | **-5.4663808 / rmsd 0.0733 (3.4, 3 回退)** |

* LQA 在 **0.40** 出现报告的已知失效（偏离 MEP，rmsd 0.031）；
* EulerPC 在 **0.40** 严重失效（端点偏 5.8e-3 Eh，3 次 GS 回退，平均 E/g 升到 3.4）——与论文「0.20 步长 Euler 无法跟随路径」一致（我们实测 0.10/0.20 尚可、0.40 明显失败）；
* HPC 在 0.10/0.20 与 GS/LQA 同盆地且 RMSD ≤ 0.015，0.40 的 forward 偏 2.3e-3 Eh（比 LQA 差），backward 正常；
  0.40 的偏差来自两点 DWI/mBS 在强弯曲段的校正量偏大，与 §6.3 的 DWI 局限同源。
* 解析势（Müller–Brown 单元 `four-method-crosscheck`）：四方法 forward 端点最大间距 **0.0444 bohr**、backward **0.0414**；
  端点能量最大差 **1.08e-3 Eh** / **5.67e-4 Eh**（实验 #6 的解析侧数字）。

---

## 10. EulerPC 实测收敛阶

单元 `eulerpc-convergence-order`：以步长 0.01 的 LQA 细路径为参考，测 `s = 0.8 bohr*amu^1/2` 处的垂直偏离，
步长 {0.05, 0.10, 0.20}，**拟合区间 0.05–0.20，3 点**：

```
EulerPC deviation at s=0.8 (0.05/0.10/0.20)   1.0764E-03  4.0851E-02  9.3751E-02   (纯 Euler)
EulerPC deviation with corrector                 1.8880E-02  4.3027E-02  9.4590E-02   (含校正)
order slope (least squares over 0.05-0.20, 3 points)   3.2222  points 3
local order 0.10 -> 0.20  pure Euler   1.1985 with corrector   1.1364
```

* **渐近局部斜率 0.10→0.20 = 1.20（纯 Euler）/ 1.14（含校正）⇒ 一阶**，与论文的一阶定位一致
  （论文报的 log-log 斜率 2.016 是**端点误差**口径，与这里的「固定弧长处路径偏离」口径不同，不能直接比较）。
* 三点最小二乘斜率 3.22 被 **0.05 点的超收敛**拉高（0.05 处纯 Euler 路径恰好贴近参考，偏离仅 1.1e-3）。
  测试因此断言**渐近局部斜率 ∈ (0.5, 2.0)**，并把三点拟合值一并打印（诚实记录口径差异）。

---

## 11. CLI 补齐

| flag | 语义 |
|---|---|
| `--lirc-grad-tol VALUE` | 信号 (b) 阈值（Phase 1 已有；help 默认值本轮由 1e-4 修正为 **1e-3**，与 settings 一致） |
| `--lirc-euler-n N` | LQA/预测器积分子步（Phase 1 已有） |
| `--lirc-loose-cycles N` | **新增**：EulerPC 粗阶段步数，0 关闭 |
| `--lirc-endpoint-relax` | **新增**：显式开启端点弛豫（默认；可撤销 `--lirc-no-endpoint-relax`） |
| `--lirc-erise-steps N` | **新增**：`--lirc-e-rise N` 的别名（同一 `e_rise_steps`），`case ('--lirc-e-rise','--lirc-erise-steps')` |

接线：`src/prog/main.F90`（解析 + `set_runtyp('lirc')`）、`src/xhelp.f90`（help 文案）；
`p_run_lirc = 20`、`set_module.f90` 的 `case('lirc')` 沿用 Phase 1，无需改动。

---

## 12. 可证伪注入（4/4 + 1 变体，真实输出 + 等价性论证）

> 铁律：先证明变异**不是**与旧逻辑等价的改写；不等价的变异变红才支撑结论。
> 每条都给出「旧逻辑 / 变异 / 等价性」与真实红输出；全部已还原并确认变绿。

### (i) `a_ii(t)` 指数符号翻转

* 旧逻辑：`corrector.f90:585` `a = (exp(-λ t) − 1)/λ`（Eq.9）。
* 变异：`a = (exp(+λ t) − 1)/λ`。
* 等价性：**不等价**——这正是任务指定的错误形式；翻转后 `dx` 反向/爆炸，测试测的是传播本身。
* 真实输出（单元套件，9 个用例变红）：
```
       ... lqa-1d-exact [FAILED]      Message: the 1D LQA step is not -s
       ... lqa-2d-consistency [FAILED]  the 2D LQA displacement disagrees with the closed form
       ... mbs-vs-lqa [FAILED]  the extrapolated mBS integration did not reach the analytic propagation
       ... mb-lqa-minima [FAILED]  Condition not fullfilled
       ... mass-metric-effect / leps-irc-descent / lqa-zero-curvature-limit / eulerpc-convergence-order / four-method-crosscheck [FAILED]
=== restored: 100% tests passed (landscape-irc) ===
```

### (ii) 去掉 `λ→0` 极限分支

* 旧逻辑：`corrector.f90:580-586` 显式分支 `if |λ| ≤ tol then a = −t`。
* 变异：删掉分支，直接 `a = (exp(-λ t) − 1)/λ` ⇒ `λ = 0` 时 `0/0 = NaN`。
* 等价性：**不等价**——正是任务指定的「去掉极限分支」。
* 真实输出：
```
       ... lqa-zero-curvature-limit [FAILED]
  Message: the zero curvature limit divided by the vanishing eigenvalue (NaN)
=== restored: 100% tests passed ===
```
* **额外变体（记录旧 Phase-1 逻辑）**：把分支换成 Phase 1 的 `if |λ| ≤ tol then cycle`（丢模而非 NaN）：
```
       ... lqa-zero-curvature-limit [FAILED]
  Message: the vanishing curvature mode was dropped instead of using a_ii -> -t
```
  ⇒ 该用例对「除零」与「丢模」两种变体**都**变红，覆盖完整。

### (iii) 终止信号 (b) 的判据量级（`|g|` 当 `|g|²`）

* 旧逻辑：`gnorm_cur/sqrt(ndim) ≤ grad_tol`（RMS 每分量）。
* 变异：`gnorm_cur**2/sqrt(ndim) ≤ grad_tol`（四方法同时）。
* 等价性：**不等价**——判据量级改变；且该变异对 `grad_tol=1.0` 的宽松用例**不敏感**（平方更小），
  只有量级敏感用例能抓住它，这正是新增 `termination-gradient-scale` 的理由。
* 真实输出：
```
       ... termination-gradient-scale [FAILED]
  Message: a threshold below the first point's gradient fired signal (b) there
=== restored: 100% tests passed ===
```
  （`termination-grad-tol`、`termination-all-methods` 保持绿——如实记录：宽松阈值用例**测不出**该变异。）

### (iv) 端点归属「总取第一个极小点」≡「总是判为落入极小点」

* 旧逻辑：`tasks/irc.f90` `endpoint_reached` 只在 (b)/(c) 终止（且要求弛豫时弛豫收敛）才 `.true.`。
* 变异：`reached = .true.`（无条件）。
* 等价性：**不等价**——删掉终止信号分类。
  **说明**：本实现没有「极小点候选列表」，「归属」= (1) 三信号分类（`endpoint_reached`）+ (2) 到弛豫极小点的 Kabsch 对齐 RMSD；
  解析势上的「归属哪个极小点」由单元测试对已知极小点判定。故注入落在 (1)。
* 真实输出（CLI 层）：
```
1/1 Test #136: xtb/landscape-irc-pc .............***Failed
  a path cut off by the step budget was assigned to a minimum
=== restored: 1/1 passed ===
```

---

## 13. 偏离、缺口与残余风险

**R-1（每点 E/g = 2，MEDIUM，已定位）。** 论文的 1 E/g 靠 DWI 重建校正点梯度实现；实测该重建把路径拽离 MEP
（forward 端点高 **1e-3..1e-2 Eh**，§6.3 的原记录 1.4e-2 已由报告 44 §6.1 更正为 2.80e-3/4.56e-2）。
本实现对校正点再评估一次 ⇒ 2 E/g（MAPLE 为 3）。**这是实测驱动的选择，已"查明原因"**。
若日后要回到 1 E/g，需改进 DWI 的权重/多点拟合并用四法互校验收。

**R-2（mBS 预算，MEDIUM）。** corrector 的 DWI 用 Shepard 逆平方距离权重（Phase 1 已记录的偏离），
在样本附近场很"刚"，Richardson 外推偶尔要到 k≈10+ 级才收敛。故 `corrector_max_points` 取 **400000**
（纯解析 DWI 求值，不计入 E/g；只影响墙钟）。HCN 实测 HPC 0.52 s / EulerPC 0.20 s。
`max_points` 不够时会触发 GS 回退（功能正确、代价升高），`--lirc-mbs-max-k` 可调。

**R-3（EulerPC 在 0.40 失效，INFO）。** 与论文一致；实测端点偏离 5.8e-3–1.2e-2 Eh、3 次回退。
默认步长 0.10 下正常。

**R-4（信号 (b) 非总是第一个触发，LOW）。** EulerPC forward 实测由 (c) 先触发（§7.2）。已如实记录；
默认策略不变（物理信号优先）。

**R-5（LQA 0.40 失效，INFO）。** Phase 1 已记录，本轮真实体系复现（rmsd 0.031）。

**R-6（meson 不可执行，既有）。** `meson.build` 镜像手工同步并通过 `landscape_cli_check.py ircpc` 本机手动执行验证。

**R-7（解析势偏差口径）。** 收敛阶测试在 0.05 处超收敛，三点 LS 斜率（3.22）与渐近局部斜率（1.20）不同；
两者都打印，断言只钉渐近一阶。

---

## 14. 与参照实现 / PLAN 的偏离清单

| # | 偏离 | 依据 |
|---|---|---|
| D-1 | 校正点做第二次 E/g 评估（2 E/g 而非论文 1） | §6.3 实测（DWI 重建梯度漂移，量级 1e-3..1e-2 Eh：报告 44 §6.1 实测 2.80e-3 / 4.56e-2；原记 1.4e-2 不可复现）；MAPLE 为 3 |
| D-2 | λ→0 显式取 `−t` 极限（Phase 1 为 `cycle` 丢模） | 任务要求；`lqa-zero-curvature-limit` 双向可证伪 |
| D-3 | 新增 `landscape_irc_path_reset` 并在四 walk 开头调用 | §5 真 bug |
| D-4 | `loose_cycles` 定义为「最前 N 步不用校正器」（MAPLE 只是放宽预测器长度收敛） | 使分支可观测、可测；§3.2 |
| D-5 | 端点 RMSD 改为 Kabsch 对齐并写明 | 任务要求；M5 Kabsch 复用 |
| D-6 | DWI 权重为 Shepard 逆平方距离（Phase 1 既有偏离，未改） | 报告 04 标 missing evidence |

---

## 15. 构建 / 测试数字

```
$ touch src/landscape/irc/*.f90 src/landscape/tasks/irc.f90
$ OMP_NUM_THREADS=1 cmake --build /tmp/xtb-land/build -j
（0 warning / 0 error）

$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape
100% tests passed, 0 tests failed out of 77        (9.07 s)

$ ... -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
100% tests passed, 0 tests failed out of 12

$ grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d
（空）
$ ctest -N -R landscape | tail -1
Total Tests: 77
```

`landscape-irc` 单元用例（28）：原 18 + `lqa-zero-curvature-limit`、`hpc-mb-minima`、`eulerpc-mb-minima`、
`pc-eval-distribution`、`hpc-corrector-fallback`、`eulerpc-loose-cycles`、`eulerpc-convergence-order`、
`termination-gradient-scale`、`termination-all-methods`、`four-method-crosscheck`。

CLI ctest：`xtb/landscape-irc`、`-cli`、`-swap`、`-termination`、`-pc`（新）、`-minimum`、`-method-unknown`。

---

## 16. 本轮改动的既有文件

```
 src/landscape/CMakeLists.txt       |   2 +
 src/landscape/meson.build          |   2 +
 src/landscape/irc/corrector.f90    |  ~210 +
 src/landscape/irc/gs.f90           |  重构（拆 gs_step）
 src/landscape/irc/lqa.f90          |   2 +
 src/landscape/tasks/irc.f90        |  ~90 +
 src/landscape/types/results.f90    |   8 +
 src/prog/main.F90                  |  ~60 +
 src/xhelp.f90                      |  ~14 +
 test/unit/CMakeLists.txt           |  ~120 +
 test/unit/landscape_cli_check.py   |  ~70 +
 test/unit/meson.build              |   5 +
 test/unit/test_landscape_irc.f90   |  ~730 +
新增（未跟踪）：src/landscape/irc/hpc.f90、src/landscape/irc/eulerpc.f90
```

`src/type`、`src/xtb`、`src/mctc`、`src/param`、`src/io`、`src/disp`、`src/coulomb` 核心层未改动。
未提交 git（父会话统一提交）。
