# 46 — M6 修复报告（复核 45 的 5 条 MEDIUM + 相关 LOW + 验证数据驱动的决策）

**对象**：`docs/_landscape-recon/45-m6-independent-review.md`（有条件接受，CRITICAL 0 / HIGH 0 /
MEDIUM 5 / LOW 9 / INFO 4）与 `44-m6-validation-experiments.md` 的实测结论。
**HEAD**：`2ed7750`（M6 全部未提交）。**本轮不提交 git**（父会话统一提交）。
**纪律**：所有 `xtb` / `ctest` 调用 `OMP_NUM_THREADS=1`；未跑全量 ctest（`-R landscape` 与回归子集）。

---

## 0. 摘要

| 项 | 结论 |
|---|---|
| M-1（`--lirc-level` / `--lirc-rmsd-end` 死旋钮） | **关闭**：两者都真正生效，各配 CLI 断言 + 单元断言 + 可证伪注入 |
| M-2（1.4e-2 被否定的数字） | **关闭**：`hpc.f90`、PLAN §12.15、报告 43 三处全部改为实测「1e-3..1e-2」并注明两个构造值 |
| M-3（`xtb/landscape-irc-pc` 缺 OMP 属性） | **关闭**：补上；并逐条审计全部 9 个 IRC ctest 条目（见 §4） |
| M-4（GS 球内弛豫质量无断言） | **关闭（文档 + 断言 + 记录 + 待办登记）**：按 Q2 的决定**不实现** Lagrange 修复，改为「缺陷可见化 + 基线钉死 + PLAN 待办」 |
| M-5 / L-8（`landscape_irc_path` 跨 ndim 复用） | **关闭**：`path_reset` 释放存储、异维点重绑、新增单元用例 |
| 复核 LOW | L-1、L-2、L-3、L-4、L-5、L-6、L-7、L-9 全部处理；I-2 一并修正（见 §8） |
| 决策落实（GS 降级 / 默认 hpc / recalc / max_steps / 步长 0.40 / 弧长标注） | 全部落到 PLAN + 模块文档 + 代码默认值（见 §7） |
| 计数 | `ctest -R landscape` **79/79**（原 77，新增 CLI `xtb/landscape-irc-knobs`、`xtb/landscape-irc-dwi-n`）；单元 `landscape-irc` **35/35**（原 32）；回归子集 **12/12**；重名检查空；构建 0 warning |
| 已验收数字 | **未破坏**：GS 端到端 10 个数字与报告 42/44 逐位一致（§11.1）；实验 #6/#7/#4 结论不变 |

**行为变更（显式记录）**：默认积分方法 `gs` → **`hpc`**（Q1 批准，见 §7.1）。
`--lirc-method gs` 的行为**完全不变**（逐位复核见 §11.1）。

---

## 1. 改动文件

| 文件 | 改动 |
|---|---|
| `src/landscape/tasks/irc.f90` | 端点弛豫继承 `--lirc-level` 四判据 + budget；`endpoint_reached` 接入 `rmsd_end`（并 `public`）；新增 `e_min/n_relax` 输出；`irc.log` 新增弧长定义、rmsd 判据、弛豫极小点、pinned 计数、oneway 诚实化；`check_irc_settings` 校验 `dwi_n >= 2` 与 `rmsd_end >= 0` |
| `src/landscape/types/results.f90` | `e_min_*`、`n_relax_*`、`n_pinned_*` 新字段；`write_log` 的归属行按「是否做了弛豫」两种写法 + oneway 诚实化（+ 新过程 `write_attribution`） |
| `src/landscape/types/settings.f90` | `method` 默认 `hpc`；`max_micro_cycles`/`micro_step_thresh`/`dwi_n`/`hessian_recalc`/`rmsd_end` 文档改为实测 + 语义订正；类型头补 `--lirc-level` 语义 |
| `src/landscape/irc/corrector.f90` | `landscape_irc_path` 新增 `n_pinned`；`path_add` 异维重绑 + `allocated` 守卫；`path_reset` 释放存储（新私有 `path_release`）；`corrector_step` 的 Hessian 记账措辞订正 |
| `src/landscape/irc/gs.f90` | 模块头新增「GS 代价 4 项实测」；`n_pinned` 计数；零梯度守卫（L-4）；`sphere_newton` 信任域注释改为实测（L-7）；移除 4 个恒为 no-op 的 `path_reserve` 调用 |
| `src/landscape/irc/{hpc,eulerpc,lqa}.f90` | 1.4e-2 → 实测；HPC Hessian 记账措辞；HPC/EulerPC 回退步计入 `n_pinned`；移除 no-op `path_reserve` |
| `src/prog/main.F90`、`src/xhelp.f90` | 四条 `--help`/注释文案订正（默认方法、hpc/eulerpc「已实现」、level 语义、rmsd-end 语义、dwi-n 语义、recalc 建议） |
| `test/unit/test_landscape_irc.f90` | +3 单元用例（`gs-sphere-relaxation-quality`、`path-cross-dimension-reuse`、`endpoint-rmsd-criterion`）；`direction-rejects-minimum` 扩展 target_mode 分支；sphere 用例含 `micro_step_thresh` 生效断言 |
| `test/unit/CMakeLists.txt`、`meson.build`、`landscape_cli_check.py` | 新增 CLI 目标 `xtb/landscape-irc-knobs`、`xtb/landscape-irc-dwi-n`；主 CLI 目标补 GS 黄金值/pinned 断言；OMP 属性表补 `irc-pc`、`irc-minimum`、`irc-knobs` |
| `docs/xtb-landscape-PLAN.md` | §5.3.7 默认值表重写（实测回填）、§6.5 IRC 表重写（GS 降级 / Lagrange 待办 / 弧长定义 / recalc / 0.40 失效）、§12.15 新增「M6 最终修复轮行为变更表」 |
| `docs/_landscape-recon/43-*.md` | 1.4e-2 三处加更正标记（保留原始记录，指向 44 §6.1 / 46 §M-2） |
| `docs/_landscape-recon/46-m6-fix-report.md` | 本报告 |

---

## 2. M-1 —— 两条死旋钮（已完成，M6 第三次「死旋钮」结案）

### 2.1 事实的**一处更正**（对任务书的输入）

任务书写「main.F90 里根本没有解析 `--lirc-level`（被前缀匹配吞掉）」。**实测不成立**：
`src/prog/main.F90:3307` 有 `case ('--lirc-level')`，且 `--lirc-level vtight` 运行**不打印**
`Unknown option`（该提示是 unknown flag 的固定输出）。真正的缺陷是**解析进 `lircset%g_*` 后无人读取**
（`tasks/irc.f90` 的 `relax_endpoint` 只拷贝了 `write_files/printlevel/engine/etemp`）。
所以两条旋钮的修复方向都成立，但「前缀匹配吞掉」这一机制描述要更正。

### 2.2 修复前的证伪（真实输出，修复前二进制）

```
base vs lvlvtight (--lirc-level vtight) : BITWISE IDENTICAL
base vs lvlsuper  (--lirc-level superloose): BITWISE IDENTICAL
base vs rmsd1e3   (--lirc-rmsd-end 1e-3) : BITWISE IDENTICAL
base vs dwi20     (--lirc-dwi-n 20)      : BITWISE IDENTICAL
base vs dwi4      (--lirc-dwi-n 4)       : BITWISE IDENTICAL
正对照 grad-tol 0.01 vs 1e-3             : 端点 -5.3875 vs -5.4721（开关可见性对照，通过）
```
⇒ 与复核 45 的 M-1/M-2 判定一致（`dwi-n` 见 §8-L2）。

### 2.3 修复后的效果（真实输出，修复后二进制）

```
post-fix 默认 vs --lirc-level superloose : 4 行改变
post-fix 默认 vs --lirc-level vtight     : 8 行改变
post-fix 默认 vs --lirc-rmsd-end 1e-3    : 4 行改变
post-fix 默认 vs --lirc-no-endpoint-relax: 6 行改变
post-fix --lirc-dwi-n 4 vs 20            : BITWISE IDENTICAL（按设计，见 L-2）
```

`--lirc-level`（GS，同一 TS）：

| level | 弛豫步数 | 弛豫后 forward 极小点 / Eh | 报告 rmsd |
|---|---|---|---|
| superloose | **1** | −5.472138432182 | 0.000598 |
| normal（默认） | 6 | −5.472159883741 | 0.009860 |
| vtight | **7** | **−5.472159888097** | 0.009956 |

CLI 断言（`xtb/landscape-irc-knobs`）：`N_vtight > N_superloose` **且** `E_vtight < E_superloose`。
（注意：**不能**用 rmsd 的大小关系作断言——superloose 的松弛极小点离端点更近，rmsd 反而更小；
能量与步数是单调可断言的口径，这一点已写进测试注释。）

`--lirc-rmsd-end`（GS，同一次运行 rmsd/fwd = 0.009860、bwd = 0.000016）：

| `--lirc-rmsd-end` | forward `reached_min` | backward `reached_min` |
|---|---|---|
| 0.18897（默认） | T | T |
| 1e-3 | **F** | T |
| 1e-6 | **F** | **F** |

`--lirc-no-endpoint-relax`：`irc.log` 打印「the rmsd_end criterion was skipped: no endpoint
relaxation was requested」，归属退回终止信号，且**不**打印「relaxed minimum」行。

### 2.4 M6 全部 CLI 选项 × 是否有测试证明其生效（强制表格）

「生效证明」= 存在测试断言「改这个值 → 结果/输出改变」或「非法值 → 被拒绝」；「读取点」= 源码里真正消费该字段的位置。

| 选项 | 读取点（代码为准） | 测试证明生效？ | 证据 |
|---|---|---|---|
| `--lirc` | 任务入口 | ✅ | `xtb/landscape-irc-cli`（+ knobs）：四文件、相位、etemp、pinned、端点窗口 |
| `--lirc-method` | `walk_direction` dispatch | ✅ | `xtb/landscape-irc-pc`（hpc/eulerpc）、`-cli`/`-swap`（gs）、单元 `four-method-crosscheck`；四法端点/hash 差异为实测 |
| `--lirc-step` | `settings%step_length` → 四 walk | ✅ | `xtb/landscape-irc-cli` 断言打印 `2.000000E-01`；结果差异由单元 `lqa-step-scan`、`eulerpc-convergence-order`（步长 ⊂ {0.05,0.10,0.20}）与报告 44 §4.4 表覆盖 |
| `--lirc-max-steps` | 每个 walk 的步数门限 | ✅ | `xtb/landscape-irc-pc`：`--lirc-max-steps 3` → `termination forward: max_steps` + `reached minimum: F` |
| `--lirc-level` | **本轮修复**：`relax_endpoint` 的四判据 + budget | ✅（新） | `xtb/landscape-irc-knobs`（1 步 vs 7 步、E_min 单调）；注入 (1) 红 |
| `--lirc-swap` | `isign_fwd/bwd` | ✅ | `xtb/landscape-irc-swap`：两端点能量互换（逐位） |
| `--lirc-oneway` | `both_directions` | ✅ | `xtb/landscape-irc-cli`：只写 forward，不写 backward；本轮另修 `irc.log`/summary 的「not requested」 |
| `--lirc-target-mode` | `select_direction(..., target)` | ✅（本轮补） | 单元 `direction-rejects-minimum`：`target=3` ⇒ 警告 + `mode%index==1`、`mode%target==3`。**物理上不能改方向**：任务在调用前强制「恰好 1 个虚频」，故 N>1 只会告警并跟随同一模式（文档已写明） |
| `--lirc-micro-cycles` | `gs_step` 的 micro 循环上界 | ✅ | 单元 `gs-sphere-relaxation-quality`：预算 5/20/21/200 的 gap/E_g 与**奇偶两点循环**断言 |
| `--lirc-micro-thresh` | `gs_step` 的接受判据 | ✅（本轮补） | 单元同上：阈值 = 球半径 ⇒ 第 1 个 micro 步即「收敛」且 `n_eval == 1`；注入 (9) 红 |
| `--lirc-euler-n` | `lqa_step` 子步数（LQA 预测 / HPC 预测） | ⚠️ 部分 | 内核参数在单元 `lqa-1d-exact`/`lqa-step-scan` 中以显式实参覆盖；**无**测试证明 CLI 值改变结果（读取路径 `hpc.f90:226`、`lqa.f90:177` 明确，风险低） |
| `--lirc-loose-cycles` | EulerPC 粗阶段长度 | ✅ | 单元 `eulerpc-loose-cycles`：1e5 ⇒ 1.00 E/g，0 ⇒ >1 E/g 且端点差 >1e-4 |
| `--lirc-mbs-tol` | mBS 接受阈值 | ✅ | 单元 `hpc-corrector-fallback`：`mbs_tol=0` + `mbs_max_k=1` ⇒ 回退触发（`env%nLog` 增加） |
| `--lirc-mbs-max-k` | mBS 最大外推级 | ✅ | 同上 |
| `--lirc-mbs-points` | mBS 基础子步 | ⚠️ 部分 | 读取路径 `corrector.f90:775`（`mbs_substeps`）明确；仅作积分精度参数，无独立测试隔离（报告 43 §9 的 E/g 分布含其效应） |
| `--lirc-dwi-n` | DWI 面**容量** | ✅（本轮补） | 实测 4 vs 20 逐位相同（两点插值按构造，已写入 `settings`/`xhelp`）；`--lirc-dwi-n 1` → `env%error` + exit 1，新测试 `xtb/landscape-irc-dwi-n`；注入见 §8-L2 |
| `--lirc-e-rise` / `--lirc-erise-steps` | 信号 (c) 计数 | ✅ | 单元 `termination-energy-rise`、`termination-all-methods`（显式改 `e_rise_steps`）；CLI `-termination`（grad_tol 0 ⇒ 由 (c) 终止）。注：CLI 侧 `--lirc-erise-steps 5` 只断言 exit 0（⚠️ 弱） |
| `--lirc-grad-tol` | 信号 (b) 阈值 | ✅ | 单元 `termination-grad-tol`、`termination-gradient-scale`；CLI `-termination`（0 ⇒ (c) 先触发）；正对照实测 0.01 vs 1e-3 端点大不同 |
| `--lirc-recalc` | 每 N 步重算 Hessian | ⚠️ 部分 | 读取路径在四个 walk 中明确；效应由报告 44 §5 实测（短/长积分、recalc=5/10），**无**单元断言 |
| `--lirc-no-endpoint-relax` | **本轮补测试**：弛豫门 + `reached_min` 语义 | ✅（新） | `xtb/landscape-irc-knobs`：无「relaxed minimum」行 + 「skipped」行 + 终止信号归属；注入 (10) 红 |
| `--lirc-endpoint-relax` | 同上（恢复默认） | ✅ | `xtb/landscape-irc-pc` 显式传该 flag 后仍 exit 0 且端点正确（弱）；语义与 no-endpoint 用例互补 |
| `--lirc-rmsd-end` | **本轮修复**：`endpoint_reached` | ✅（新） | `xtb/landscape-irc-knobs`（1e-3 ⇒ F/T）+ 单元 `endpoint-rmsd-criterion`；注入 (2) 两处红 |
| `--lirc-hessian` / `--lirc-hessian-file` | `new_landscape_hessian_provider` | ⚠️ 部分 | provider 的 `numerical|model|file` 由 M3 测试覆盖（`landscape-hessian`、`landscape-vib-cli`），IRC 侧仅透传；无 IRC 专属断言 |
| `--lirc-step-hess` / `--lirc-sccacc` | `engine%hess_step/hess_acc` | ⚠️ 部分 | M3 已实测（报告 21）并用于 `--lvib`；IRC 侧仅透传 |
| `--lirc-restart` | `engine%restart_mode` | ⚠️ 部分 | 引擎三态策略由 M1/M4 测试覆盖（`landscape-engine`）；IRC 侧仅透传，无 IRC 专属断言 |

**结论**：M6 的 27 个 `--lirc*` 选项（含 1 个别名）里，**19 个有直接的「改变结果 / 非法值被拒」断言**
（其中本轮新增或补强 6 个：`--lirc-level`、`--lirc-rmsd-end`、`--lirc-no-endpoint-relax`、
`--lirc-dwi-n` 合法性、`--lirc-target-mode` 回退告警、`--lirc-micro-thresh`），
**8 个只有「部分/间接」证据**（上表 ⚠️：`--lirc-euler-n`、`--lirc-mbs-points`、`--lirc-recalc`、
`--lirc-hessian`、`--lirc-hessian-file`、`--lirc-step-hess`、`--lirc-sccacc`、`--lirc-restart`）。
**这 8 个都有明确的读取点**（透传参数或积分精度参数），不是「解析后无人读」；
真正属于「死旋钮」的两条（`--lirc-level`、`--lirc-rmsd-end`）已修复并各自有断言 + 注入。

---

## 3. M-2 —— 被否定的 `1.4e-2`

1. `src/landscape/irc/hpc.f90:54` 段改写为：1 E/g 变体端点落在真实 HNC 极小上方 **1e-3..1e-2 Eh**，
   并给出验证轮的两个构造实测：**V1 = 2.80e-3**（只评预测点、信 DWI 梯度）、**V2 = 4.56e-2**
   （再加预测 secant 更新），两者均 1.00 E/g；2 E/g 为 **5.5e-5**（50–800× 更近）⇒ 取舍不变。
   明确写「报告 43 的 1.4e-2 是同一量级但两种构造成因都复现不出来，故在此退役」。
2. PLAN §12.15 第 3 条与 §6.5 的 HPC 行同步改为实测值。
3. **全局搜索 `1.4e-2`**：现存引用只剩三处**历史记录 + 更正标记**（报告 43 §6.3 正文、§13 R-1、
   偏离表 D-1），每处都加了「更正（报告 44 §6.1 / 46 §M-2）；原记不可复现」。
   `src/`、PLAN、其它报告已无未更正的引用（`grep -rn "1\.4e-2" src/ docs/`）。

---

## 4. M-3 —— OMP 属性审计（全部 9 个 IRC ctest 条目）

```
landscape-irc-cli          : OMP_NUM_THREADS=1 in env: 1   （原有）
landscape-irc-knobs        : OMP_NUM_THREADS=1 in env: 1   （本轮新增，已带属性）
landscape-irc-swap         : OMP_NUM_THREADS=1 in env: 1   （原有）
landscape-irc-termination  : OMP_NUM_THREADS=1 in env: 1   （原有）
landscape-irc-pc           : OMP_NUM_THREADS=1 in env: 1   （**本轮补**，原缺失 → 复核 M-4）
landscape-irc-minimum      : OMP_NUM_THREADS=1 in env: 1   （**本轮补**：该负例仍跑数值 Hessian）
landscape-irc-method-unknown: OMP_NUM_THREADS=1 in env: 0  （纯参数校验，未进入引擎；按既有约定保持）
landscape-irc-dwi-n        : OMP_NUM_THREADS=1 in env: 0   （同上，本轮新增）
unit suite xtb/landscape-irc: OMP_NUM_THREADS=1（原有）
```

**「为什么要 OMP=1」的实测依据（比复核给的墙钟论证更强）**：同一 `hpc` IRC，
`OMP_NUM_THREADS=1` vs `8` 的 `irc.log` **不同**——弧长第 10 位不同
（点 26：`2.5497138374` vs `2.5497138375`；端点：`3.9418832066` vs `3.9418832067`），
`irc_forward.xyz` **逐位不同**。即：跨线程数**不是位相可复现的**（AGENTS §6.1 的 ~1e-14 Eh/bohr
还原阶数差异被路径积分放大）。墙钟差异反而可忽略（`irc-pc` 测试 OMP=1 1214 ms vs 默认 1227 ms，
HCN 3 原子规模太小；340× 反向加速只在大体系出现）。

---

## 5. M-4 —— GS 球内弛豫：断言 + 记录 + 待办（不实现 Lagrange 修复，Q2 决定）

### 5.1 新增的**可证伪**质量断言（独立球面参考）

单元 `gs-sphere-relaxation-quality`（新）：在 Müller-Brown 面上取 `q = 鞍点 − (0,0.25)`，
用 `landscape_irc_gs_step` 做一步，再用**独立方法**（极角 20000 点密集采样 + 黄金分割细化，
不用梯度/Hessian/微循环）求同一球面上的能量极小点，比较：

```
GS sphere relaxation, budget 5  : gap 1.267822E-03 Eh, E/g 6,   micro cycles converged F
GS sphere relaxation, budget 20 : gap 3.400828E-04 Eh, E/g 21,  micro cycles converged F
GS sphere relaxation, budget 21 : gap 1.267822E-03 Eh, E/g 22,  micro cycles converged F
GS sphere relaxation, budget 200: gap 3.400828E-04 Eh, E/g 201, micro cycles converged F
GS micro threshold = radius, one cycle gap 3.400828E-04
```

断言：① 返回点严格在球面上（1e-12）；② 质量上界 `gap < 2e-3` Eh（= 最大实测 1.3e-3 的 2 倍，
论文/修复后仍然成立的上界）；③ **两点循环**（偶/奇预算的 gap 差 > 1e-4）；④ 默认预算下
`micro_converged = .false.`（**缺陷被演示，不是被描述**）；⑤ `micro_step_thresh` 读取生效。

**新增的实测事实（比报告 44 §7.1 更精确）**：微循环不是「跑满 20 次」，而是进入**两点循环**——
预算 20 与 200 给出**同一位数**的 gap（3.400828e-04），预算 5 与 21 给出另一个同位数
（1.267822e-03）。⇒ 偏差**结构性**，与预算无关。GFN2 路径上被预算钉住的宏步是
**forward 33/42、backward 38/40**（末段接近极小点的步 2 次评估即收敛），
与 `E/g = 16.93/20.25` 自洽（33×21 + 9×2 = 711 → 16.93）。

### 5.2 缺陷可见化：`landscape_irc_path%n_pinned` → `irc.log` / result

```
points whose sphere relaxation was pinned at the micro cycle budget: forward 33 of 42 points
                            backward 38 of 40 points        （gs）
points whose sphere relaxation was pinned at the micro cycle budget: forward 0 of 40 points  （hpc）
```
CLI 断言：`xtb/landscape-irc-cli` 要求 GS 上 **> 0**；`xtb/landscape-irc-knobs` 要求默认（hpc）为 **0**
（负对照）。result summary 打印 `sphere relaxation pinned: k of n points`。

### 5.3 信任域的必要性（L-7 的实验替代，报告 44 §2.3 式注入）

删掉 `sphere_newton` 的 `if (nd > radius)` 限幅后跑 GFN2 GS：

```
forward: termination = max_steps，弧长 25.274928 bohr*amu^1/2（256 点），E = -5.471657536459
```

⇒ **去掉限幅会让 forward 路径崩坏**（正常为 4.051234、42 点、到 HNC 极小）。故 `sphere_newton`
的注释改为**本轮实测**（不再引用不存在的报告 42 实验）：限幅保留的理由 = 路径正确性；
同时如实写明「限幅**并不能**让微循环收敛（仍是两点循环）」。

### 5.4 Lagrange 修复：登记为 PLAN 显式待办（未实现）

PLAN §6.5 IRC 表新增一行 **「GS 的 Open item（Lagrange 修复）」**，写明：
修复内容（等式约束 Lagrange 步）、预计收益（**省 3–4× E/g**）、
**验收方式**（单元 `gs-sphere-relaxation-quality` 的质量上界 + 两点循环断言 + CLI GS 黄金值/弧长/E-g
断言 + pinned 计数归零，全部**显式更新**）、以及本轮不做的原因
（GS 行为基线刚经报告 42 的拆分回归逐位验收，叠加算法改动无法区分「预期变化」与「又一次静默回归」）。
**该待办在 PLAN 里，不只在报告里**。

### 5.5 GS 的四项实测代价（写进 `gs.f90` 模块头 + PLAN §6.5）

1. 代价：**16.9 / 20.3 E/g**（PLAN 预期 3–5），HPC 1.98、LQA 1.00 ⇒ GS 是 HPC 的 **8.5×**；
2. 精度：MB 对参考 MEP 最大偏离 **0.040 bohr**（lqa 0.0066 / hpc 0.0022 / eulerpc 0.026）为四法最差；
3. 根因：切空间 Newton 步 **1.8–2.4** ≫ 球半径 **0.05** ⇒ 判据（1e-3）不可达，两点循环；
4. 结论：**GS 不是默认方法**（默认已改 `hpc`），保留为兼容/对照实现与校正失败的回退。

---

## 6. M-5 / L-8 —— `landscape_irc_path` 跨 `ndim` 复用

**修复（不是「写清为何安全」）**：`irc/` 无历史可 diff ⇒ 按任务书要求提高门槛，直接消除隐患：

* `landscape_irc_path_reset` 现在**释放全部存储**并清空 `n/ndim/capacity/n_pinned/term`
  （新私有 `landscape_irc_path_release`；文档同步改写为「restores the empty state —
  including the release of the storage」）。
* `landscape_irc_path_add` 在维度变化时**重绑**：释放旧维度存储 → 以新维度从 0 开始，
  不再写入形状不匹配的数组（容器没有 env，无法报 `env%error`，因此选择「总量正确」的守卫，
  理由写在代码注释里）。
* `path_add` 的分配条件补 `allocated` 守卫（reset 释放后首次添加也能正确分配）。
* 四个 walk 里 4 个恒为 no-op 的 `path_reserve` 调用（reset 后 `ndim==0` 提前返回）**删除**，
  避免又一处「声称做事的死代码」；`path_reserve` 的文档写明需要已知维度。

**新单元用例 `path-cross-dimension-reuse`**：2 维点 → reset（断言 `capacity==0`、`xyz` 未分配）→
9 维点（断言值/`n_eval` 正确）→ 不改 reset 直接加 2 维点（断言重绑、值正确）。
注入 (3)（把 reset 换回「只清计数、保留存储」的旧实现）→ **`path-cross-dimension-reuse` 红**
（`Message: the reset kept the capacity of the previous dimension`）→ 还原绿。

---

## 7. 验证数据驱动的决策（全部落到 PLAN + 模块文档 + 代码）

### 7.1 GS 降级 + **默认方法改为 `hpc`**（Q1 批准的行为变更）

* 代码：`landscape_irc_settings%method = p_landscape_irc_hpc`（原 `gs`）。
* 文档：`settings.f90` 类型头、PLAN §5.3.7/§6.5、`--help` 全部写明「hpc 默认；更准 0.0022 vs 0.040 bohr、
  便宜 8.5×」；`gs.f90` 模块头写明「GS 不是默认方法」。
* **CLI 级默认路径测试**：`xtb/landscape-irc-knobs` 跑 `--lirc`（不带 `--lirc-method`），断言
  `irc.log` 的方法名 = `hpc`、两端点落在 HNC/HCN 窗口内、pinned = 0；注入 (5)（默认改回 gs）→ 红。
* **`--lirc-method gs` 行为不变**：见 §11.1（逐位复核）。
* **既有测试的隐式耦合排查**：全部 IRC CLI 脚本都**显式**带 `--lirc-method`（`-cli`/`-swap`/`-termination`
  用 `gs`，`-pc` 用 `hpc|eulerpc`），单元测试用 `settings%method = ...` 显式设置；
  `test/unit/*.f90` 中唯一使用默认值的地方是 `default_settings(..., method)` 实参。⇒ 无隐式依赖默认 gs 的测试。
* PLAN §12.15 新增「M6 最终修复轮的行为变更表」显式记录该变更（不是静默并入）。

### 7.2 `hessian_recalc` 保留 −1（**测量驱动的决定**）

依据（报告 44 §5.2）：短路径纯 Bofill 足够（端点误差 ~1e-5 Eh）；**长积分**（150 步）HPC-backward
漂到离真实 HCN 极小 **6.0e-4 Eh、|g| = 4.1e-2**，`recalc=10` 恢复（|g| = 4.4e-7）。
**决定：保留 −1**，理由（写入 PLAN §5.3.7 + `settings.f90` 字段注释）：① 短路径（默认用法）无问题；
② 所有已验收 M6 数字都由 −1 产生，改默认将作废全部已验收表；
③ 长/强弯曲路径**必须显式** `--lirc-recalc 5..10`（同时写入 `--help` 与 PLAN）。

### 7.3 `max_steps = 256` 保留

依据（报告 44 §4.5）：到达极小点 ≤104 步（0.05 步长），PLAN 原引 MAPLE 的 **50 会截断** 0.05 步长的正常路径。
写入 PLAN §5.3.7（并顺带把 `max_pred_steps = 500` 标为**未实现的显式偏离**——EulerPC 预测是单次
显式 Euler 步，MAPLE 的该参数在代码中无对应点）。

### 7.4 步长 0.40 的失效模式

写入 PLAN §5.3.7（`step_length` 行）与 §6.5（LQA/HPC/EulerPC 三行）：
0.40 下 LQA 偏 3.3e-4、HPC-forward 2.35e-3、EulerPC 双向 5.8e-3/1.1e-2 Eh 且 3 次回退 ⇒
论文允许但**本实现不推荐**，默认 0.10、上限 0.20。

### 7.5 弧长定义差异（LOW-4）

`irc.log` 每次运行打印一行：
```
arc length s is the accumulated chord length of the macro steps (not comparable with the integrated length of --lirc-method lqa)
arc length s is the integrated path length of the quadratic propagation        （lqa）
```
PLAN §6.5 新增「弧长定义」行（同路径 GS 4.0512 vs LQA 4.2500 = 定义差，不是路径更长）。

---

## 8. 「文档承诺 vs 代码行为」逐条订正表

| 编号 | 位置 | 原承诺 | 现状 | 处理 |
|---|---|---|---|---|
| M-1 | `xhelp.f90:558`、`main.F90:3307` | `--lirc-level` 控制端点弛豫阈值 | 从不被读 | **代码生效**（+新断言/注入） |
| M-2 | `xhelp.f90:617`、`settings.f90` | `--lirc-rmsd-end` 是端点归属判据 | 从不被读 | **代码生效**（+新断言/注入）；无弛豫时「不可用」并**在日志写明已跳过** |
| L-1 | `xhelp.f90:547`、`main.F90` | hpc/eulerpc「not implemented yet」 | 早已实现（错误文案） | 文案改写（含新默认） |
| L-2 | `xhelp.f90:594`、`settings.f90:811` | `--lirc-dwi-n` = 采样点数 | 实为**容量**，两点插值按构造 | 文档改写为容量 + `>=2` 校验 + `--lirc-dwi-n 1` 拒绝测试 |
| L-3 | 报告 44 §3/§4 跨方法弧长表 | 隐含可比 | 弦长 vs 积分弧长 | §7.5（`irc.log` + PLAN） |
| L-4 | `gs.f90:275` | —（缺守卫） | 恰好驻点会记重复点 | 加 `gs_gradient_guard = 1e-14`（与 lqa/hpc/eulerpc 一致，转信号 (b)） |
| L-5 | PLAN §5.3.7 | `max_steps=50`；`max_pred_steps=500` | 代码 256；后者未实现 | PLAN 回填 256；500 标为显式偏离 |
| L-6 | `hpc.f90:54`、PLAN §12.15 | 1.4e-2 | 实测 2.80e-3/4.56e-2 | §3（含报告 43 的三处更正标记） |
| L-7 | `gs.f90:317` | 「measured ... report 42」（不存在的实验） | — | 改为本轮 `noclamp` 实测（§5.3） |
| L-9 | `landscape_cli_irc.cmake` | 只查两端点互异 | 无数值锚点 | 新增 GS/hpc 端点窗口、弧长、E-g、pinned 断言（§11.2） |
| I-2 | `tasks/irc.f90:840` | oneway 仍打印 `termination backward: error` / `F` | 误导 | `irc.log` 与 result summary 均改为「not requested (--lirc-oneway)」 |
| I-2b | `results.f90` write_log | 未弛豫时打印 `(rmsd 0.000000)` | 误导 | 按「是否做了弛豫」两种写法，未弛豫时写明判据被跳过 |

---

## 9. 可证伪注入汇总（10 条，全部真实红 → 还原 → 绿）

| # | 注入 | 命中测试 | 失败信息 |
|---|---|---|---|
| 1 | `relax_endpoint` 删掉四判据拷贝（=修复前状态） | `xtb/landscape-irc-knobs` | `landscape_cli_irc_knobs.cmake` 的 level 断言（红→还原绿） |
| 2 | `endpoint_reached` 去掉 `rmsd <= rmsd_end` | `xtb/landscape-irc`（单元）+ `-knobs` | `endpoint-rmsd-criterion`: "an endpoint outside the RMSD window was assigned to a minimum"；knobs 的 F/T 断言 |
| 3 | `path_reset` 换回「只清计数、保留存储」 | `xtb/landscape-irc`（单元） | `path-cross-dimension-reuse`: "the reset kept the capacity of the previous dimension" |
| 4 | `n_pinned` 永不递增 | `xtb/landscape-irc-cli` | "the GS forward sphere relaxation is no longer pinned (0 of ...)" |
| 5 | `settings%method` 默认改回 `gs` | `xtb/landscape-irc-knobs` | "the default IRC method is no longer hpc" |
| 6 | HPC 也（无条件）递增 `n_pinned` | `xtb/landscape-irc-knobs` | "the default (hpc) run reports pinned micro cycles" |
| 7 | GS 记录 `x_new = path%xyz(:,1)`（报告 44 §2.3 的冻结几何注入） | `xtb/landscape-irc`（单元） | `gs-path-geometry-consistency`（"the recorded path geometry did not move"）+ `mb-gs-minima` + `four-method-crosscheck` |
| 8 | 删掉 `project_sphere` 的球面投影（报告 42 §8.1 注入） | `xtb/landscape-irc`（单元） | `mb-sphere-chord`（"a chord exceeded the sphere constraint"）+ `gs-sphere-relaxation-quality`（"returned a point off the sphere"）+ `leps-four-method-crosscheck` + `hpc-predictor-accuracy` |
| 9 | `micro_step_thresh` 不参与判据 | `xtb/landscape-irc`（单元） | `gs-sphere-relaxation-quality`: "a micro step threshold above the sphere radius did not converge the first cycle" |
| 10 | `settings%endpoint_relax` 全部当 `.true.`（=flag 从不被读） | `xtb/landscape-irc-knobs` | 第 130 行（no-endpoint-relax 断言） |

（每条都执行了「注入 → build → ctest 红 → `revert` → build → ctest 绿」，还原后
`diff` 原始文件确认字节一致；日志在 `/tmp/m6fix/inj/*.ctest` / `.reverted`。）

---

## 10. 复核 45 §5「需运行验证」清单逐条执行

| # | 项 | 结果 |
|---|---|---|
| 1 | 基线（build 0 warning / 79-77 计数 / 重名 / 回归） | ✅ 见 §11.3；**本轮 b) 见 §4**：`irc-pc` 曾缺 OMP 属性，已补；计数由 77 → **79**（新增 2 个 CLI 目标）；重名 `grep ... uniq -d` 空 |
| 2 | 证伪 M-1（level） | ✅ **修复前** superloose/vtight 与默认**逐位相同**（判定成立）；**修复后** 4/8 行改变（§2.3） |
| 3 | 证伪 M-2（rmsd-end） | ✅ **修复前** 1e-3 与默认逐位相同；**修复后** forward `T→F`（§2.3） |
| 4 | 证伪 L-2（dwi-n） | ✅ 4 vs 20 **仍逐位相同**（按构造；已改为「容量」文档 + `>=2` 校验 + `1` 拒绝测试） |
| 5 | 正对照 | ✅ `--lirc-grad-tol 0.01` vs `1e-3`：端点 −5.387467523539/−5.387471760616 vs −5.472135505135/−5.504066222136，终止信号/点数均变 |
| 6 | M-4（OMP 属性） | ✅ 补属性；`ctest -V` 显示 `OMP_NUM_THREADS=1`；另测得 OMP=1 vs 8 的 `irc.log`/`irc_forward.xyz` **不同**（§4），墙钟 1214 vs 1227 ms |
| 7 | 护栏活性 | ✅ 注入 7、8（§9）：`gs-path-geometry-consistency`+`mb-gs-minima` 红；`project_sphere` 删除 ⇒ `mb-sphere-chord` 红 |
| 8 | L-7 的替代实验（去掉限幅） | ✅ 已跑：forward 崩坏（25.274928 vs 4.051234 bohr*amu^1/2，被 `max_steps` 截断）⇒ 保留限幅，注释改为实测 |
| 9 | M-5 的球面极小点对照测试 | ✅ 已实现为单元用例（独立采样+黄金分割），实测 gap 3.4e-4/1.3e-3 Eh（§5.1） |

---

## 11. 验收证据

### 11.1 已验收数字未破坏（GS 逐位）

```
GS（--lirc-method gs, step 0.10, 同一 TS）：
  mean E/g            forward 16.93     backward 20.25        （报告 42/44 同）
  forward endpoint   -5.472135505135 Eh                     （报告 42 同，逐位）
  backward endpoint  -5.504066222136 Eh                     （报告 42 同，逐位）
  forward arc length  4.051234 / backward 3.695670 bohr*amu^1/2（同）
  点数 42 / 40；（报告 42 的 10 个数字全部一致）
  逐位比较：修复后 irc.log 的前 100 行（全部路径表 + 端点行）与修复前基线 diff 为空
```
⇒ 「GS 回归的逐位行为保持」在修复后仍然成立；`--lirc-method gs` 未被默认值变更影响到。

### 11.2 CLI 黄金值断言（新，LOW-9）

* GS：forward ∈ HNC 窗口 `[-5.47225988, -5.47205988]`、backward ∈ HCN 窗口
  `[-5.50416622, -5.50396622]`（= 实测极小 ±1e-4 Eh）；forward 弧长 `4.051234`、backward `3.695670`；
  E/g `16.9 / 20.2`；pinned `>0`。
  **容差依据（写在脚本注释里）**：step 0.10 下四法同盆地离散度实测 **5.0e-5 Eh**
  （gs −5.47213551 / lqa −5.47215487 / hpc −5.47210457），唯一出盆地的 eulerpc（−5.47130320）
  距盆地 **8.0e-4 Eh** ⇒ 窗口 = 观测离散度的 2 倍、且比必须排除的偏差窄 8 倍。
* 默认（hpc）：方法名 `hpc`、两端点同窗口、pinned = 0。

### 11.3 测试与计数

```
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape
  100% tests passed, 0 tests failed out of 79     (Total Test time 15.4 s)
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
  100% tests passed, 0 tests failed out of 12     (0.23 s)
ctest -N -R landscape | tail -1  ->  Total Tests: 79
grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d  ->  （空）
./xtb-tester landscape-irc  ->  35/35 PASSED（新增 gs-sphere-relaxation-quality、
  path-cross-dimension-reuse、endpoint-rmsd-criterion）
构建：cmake --build -j8，grep -i "warning|error" -> 0 行
```
新增 CLI 目标：`xtb/landscape-irc-knobs`（默认方法 + level + rmsd-end + no-endpoint-relax）、
`xtb/landscape-irc-dwi-n`（DWI 容量校验），均已同时在 `CMakeLists.txt`、`meson.build`、
`landscape_cli_check.py`（模式 `ircknobs`）三处注册。

---

## 12. 残余风险与未做事项

1. **GS Lagrange 修复未做**（Q2 决定）：登记在 PLAN §6.5 待办，收益 3–4×、验收方式已写明。
   风险 = GS 作为回退实现仍贵 ~8.5×（回退是罕见单步，可接受）。
2. **8 个 CLI 选项只有间接证据**（§2.4 表中 ⚠️）：`--lirc-euler-n`、`--lirc-mbs-points`、
   `--lirc-recalc`、`--lirc-hessian`、`--lirc-hessian-file`、`--lirc-step-hess`、`--lirc-sccacc`、
   `--lirc-restart`。它们**都有明确的读取点**（非死旋钮），但缺「改值→结果变」的专属断言。
   建议 M7 一并补，或在 PLAN 的选项表里统一标注「参数透传，效应由 M3 引擎测试 + 报告 44 §5 覆盖」。
3. **`--lirc-erise-steps` 的 CLI 断言偏弱**（`irc-pc` 里只断言 exit 0）；真正的 (c) 语义由
   单元 `termination-all-methods` 与 CLI `-termination` 覆盖。
4. **`endpoint_relax` 与 `--lirc-max-steps` 耦合**：缓豫的步数预算现在跟随路径预算
   （与 `tasks/ts.f90` 一致，已写入 `settings`/`xhelp`）。副作用：用户把 `--lirc-max-steps`
   设得很小（如 5）时，弛豫可能不收敛 ⇒ `reached_min=F`。这是**如实报告**（不是静默），
   但与「路径预算」的直觉不同，记入下表。
5. **`1e-14` 零梯度守卫（L-4）没有专门测试**：只在恰好驻点（需 `--lirc-grad-tol 0`）触发，
   本次新增的分支属防御性代码；已在 `gs.f90` 注释中说明。
6. `speed()` 对负本征值大 `t` 的 `exp` 溢出风险（复核 INFO）**仍未被构造出可达路径**，未改。
7. I-1（回退步的 `E/g` 少记 1）与 I-3（EulerPC 粗阶段重复预测 secant 更新，第二次为 no-op）
   复核已判定为非缺陷/死工作，本轮未动（改动会触碰已验收的 E/g/路径数字）。
