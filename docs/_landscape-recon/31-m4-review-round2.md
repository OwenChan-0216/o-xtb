## 摘要（≤30 行）

**结论：接受（M4 可宣称完成）** — 29 号的 4 HIGH + 8 MEDIUM 全部真修或按复核指定的最小方案闭合；无 CRITICAL、无 HIGH。**新发现 3 条 MEDIUM / 6 条 LOW / 4 条 INFO**，均不推翻 M4 的交付物与验收数字，但 3 条 MEDIUM 应在 M5 前处理或写入 PLAN。

| 29 号条目 | 判定 | 关键证据 |
|---|---|---|
| H1 带内收紧 FD | **已修复（真修）** | `ts.f90:443-463` 谓词（有符号 `abs(freq)`、只看内模）；`ts.f90:296-340` 只重算一次、同 etemp/restart、两组谱都打印；`ts.f90:314-315` 改 `ctrl%hess_step/acc`，而 `engine.f90:651/667` 在**调用时**读取 → 参数真正生效；`main.F90:2848-2893` 新增 `--lts-step/--lts-sccacc` |
| H2 非鞍点 exit 0 | **已修复（真修）** | `ts.f90:342-380`（is_saddle + `converged=.false.` + 三互斥分支消息）→ `main.F90:988 env%checkpoint` → `mctc/error.f90:48-67 error stop`（实测 exit 1）；文件仍写出、`res` 回写保留 |
| H3 线性虚频被吞 | **已修复（真修）** | `modes.f90:190-250`（按与质量加权刚体子空间的重叠选零模，不足时 warning+回退）；`modes.f90:450-560` 基与 `massWeightHessian` 同空间；新测 `linear-saddle-imaginary`（n_imag=2），CO₂/H₂ 仍绿 |
| H4 lifted 恒真 | **已修复（核心）** | `eigenfollow.f90:600-633` `P H P` + 相对噪声阈；`prfo.f90:440-443/480-492` 在判 nneg **之前**投影；`prfo.f90:500-521` warning 每轮一次；CLI 断言无 `lifted=T` |
| M1 etemp 死字段 | **已修复，测试有缺口 → MEDIUM-3** | `engine.f90:771-789` 从 `calc%etemp` 回读；`ts.f90:201`；`results.f90:380-386` 打印；CLI 只查 stdout 两条，**没查 result 字段** |
| M2 prfo reset_result | **已修复** | `prfo.f90:766-795` 现与 `dimer.f90:1050-1077` 逐行一致 |
| M3 namespace | **已修复** | `ts.f90:488/500 get_namespace`；`setparam.f90:601` 单前缀；CLI `landscape-ts-namespace` |
| M4 驱动投影无测试 | **已修复（复核预测被证伪）** | `test_landscape_saddle.f90:883-931` 9 维刚性漂移模型（drift 7.5e-16 vs 0.231） |
| M5 最终过渡向量 | **部分修复 → LOW-1** | `prfo.f90:626-635` 已重定相+报告，但向量来自**上一步**的 Hessian |
| M6 step0 | **已修复** | `settings.f90` 文档改「上限」+ `main.F90:2880-2893 --lts-step0` |
| M7 trust 列 | **已修复** | `results.f90:66-96/342-356` bound_kind + `stepmax/bohr`；`dimer.f90:955-961` |
| M8 κ<0 / 零步 | **(a) 已修复；(b) 已修复但无测试 → LOW-4** | `dimer.f90:374-385 1/abs(kappa)`；`dimer.f90:822-831` 力方向回退 |

**进 M5 前**：① 跑完 §5 的运行清单（含 3 个注入）；② MEDIUM-1（从极小点起步时选中的是刚体零模，文档承诺的「沿最低模式上坡」不成立）→ 修或写入 PLAN §9.5；③ MEDIUM-2（`λ_n` 对分不验证残差，噪声门把 (−tol,0) 的本征值留在方程里）→ 测量并考虑把抬升作为**回退**恢复；④ MEDIUM-3 加一条断言（5 分钟）。全部为我无法执行的静态复核，测试绿/注入红来自报告 30 的自述。

---

# 31 — M4 修复轮独立复核（第二轮）

> 复核者：fresh-context read-only reviewer（只有 read/grep/find/ls/watchdog_diff，**未运行任何命令**）。
> 对象：`docs/_landscape-recon/30-m4-fix-report.md`、29 号的 H1-H4/M1-M8、以及修复涉及的源码
> （`tasks/ts.f90`、`saddle/{eigenfollow,prfo,bprfo,dimer}.f90`、`vib/modes.f90`、
> `types/{results,settings}.f90`、`engine/engine.f90`、`main.F90`、`test/unit/*`）。
> 纪律：每条判定附 `file:line`；无证据的静态猜测只进「需运行验证」，不作为 finding。

## 0. 结论

| 项 | 判定 |
|---|---|
| 29 号 4 HIGH | **4/4 真修**（H1/H2/H3 完全闭合，H4 核心闭合、文档半条留 INFO） |
| 29 号 8 MEDIUM | **7 条真修，1 条（M5）按复核指定的最小方案闭合但留有残余（LOW-1）** |
| 硬约束 1（etemp 冻结+记录） | 成立（stdout + `result%etemp` + `xtbts.log` 三处；测试只覆盖前两处链路，M1 字段无断言） |
| 硬约束 2（0±3 cm⁻¹ 收紧 FD） | 成立（谓词 + 一次收紧 + model/file 明确 warning + CLI 端口） |
| 硬约束 3（不用与 `--hess` 逐位一致作判据） | 遵守（无测试以此断言；HCN 的「逐位相同」是线性分子两路径都跳过投影的**预期**观察，非判据） |
| M4 验收数字 | 代码与测试层面仍成立（`mb-agree` 断言 <1e-3；dimer 无 Hessian；HCN 三方法 exit 0 + 1 虚频由 CLI 断言）；**数字本体需重跑**（§5） |
| **M4 是否可宣称完成** | **是**（有条件下：§5 必须实跑；3 条 MEDIUM 记录或修复） |
| 计数 | **CRITICAL 0 / HIGH 0 / MEDIUM 3 / LOW 6 / INFO 4** |

## 1. 逐条判定（29 号 H1-H4 + M1-M8）

### H1 — 已修复（真修）
- 谓词：`ts.f90:443-463` `landscape_ts_curvature_band_hit(freq, n_zero, band)`，对 `i > n_zero`（只内模）用 `abs(freq(i)) <= band`。**有符号**：`freq` 由 M3 的约定 `f = autorcm*sign(sqrt(|λ|),λ)` 给出，虚频为负，`abs` 正确处理；阈值作用在**频率（cm⁻¹）**上，与硬约束原文「曲率落在 0±3 cm⁻¹」一致，且本征值换算 `|f|=sqrt(|λ|)·autorcm`、带宽 `(3/autorcm)²≈3.4e-7` 写在 `ts.f90:436-441` 与 PLAN §9.5。
- 收紧：`ts.f90:296-340`。`can_tighten = (trim(settings%hessian_source) == 'numerical')`（`ts.f90:298`，与 `settings.f90:169` 默认 `'numerical'`、`hessian.f90:202` 的已知名一致）；参数已是收紧值时不重算；**只重算一次**（无循环，上界明确，`ts.f90:307-334`）；重算仍带内时不再动作，但两组数值都打印（`ts.f90:322-328`）。etemp/restart **未动**：只改 `engine%ctrl%hess_step/hess_acc`（`ts.f90:314-315`），`engine%hessian` 的 restart 序列仍是 `engine_apply_restart`（`engine.f90:670`）→ 满足 AGENTS §6-2 的「一次 FD 序列内策略统一」。
- **参数真的到达 FD**：`engine.f90:651 step_used = self%ctrl%hess_step`（调用时读）与 `engine.f90:667 call set_numerical_accuracy(self)` → `engine.f90:248-255` 把 `ctrl%hess_acc` 拷进 provider（调用时）。这是 H1 能被判为「真修」的关键，而 29 号当时的怀疑点（provider 构造时固定 sccacc）已被证伪。
- 非 numerical 来源：`ts.f90:335-339` 明确 warning（不再静默把带内模算成 0 虚频），符合复核的最小修复 (b)/(c)。
- 客户端口：`main.F90:2848-2893`（`--lts-step`/`--lts-sccacc`/`--lts-step0`）+ `xhelp.f90` + 3 条缺值 CLI 测试（`CMakeLists.txt:1184-1199`）。
- 测试：单元 `ts-curvature-band`（`test_landscape_saddle.f90:838-869`，带内正/负模、带外、常数 3）；注入（谓词恒假→红）为自述。
- 残余：**重算分支本身零覆盖**（LOW-2）。

### H2 — 已修复（真修）
- `confirm_saddle` 后段：`ts.f90:342-380` 写 `n_imag`/`imag_freq`/`is_saddle`，`n_imag/=1` 时 `result%converged=.false.` + 分支化 `result%message` + warning；三分支（1 / 0 / default）互斥且穷尽（`ts.f90:352-367`，`n_imag = count(...)` 恒 ≥ 0）。
- 退出码链路**真的通**：`ts.f90:186-215`（末尾 `env%error`）→ `main.F90:988 env%checkpoint("Landscape task terminated")` → `environment.f90:176-195` → `terminateRun` → `mctc/error.f90:48-67`（signal=1 → `error stop`）。这不是「只打 warning」。
- 文件与回写：`write_ts_files`（`ts.f90:500-530`）在 `env%error` 之前，`xtbts.xyz`/`xtbts.log` 仍写出；`main.F90:986-987` 的 `res` 回写仍在 checkpoint 之前 → AGENTS §6-7 未回归。
- 不污染外层：`result%converged` 的消费者只有 `landscape_ts`（`ts.f90:211-215`）与 `write_ts_files` 的日志行；M6 若读 `xtbts.xyz` 不依赖该标志。
- 测试：`CMakeLists.txt:1138-1170`（exit≠0 + 3 条诊断 + 文件存在）、python `check_ts_minimum`、注入（删 `converged=.false.` → 红）。

### H3 — 已修复（真修，边界已记录）
- `modes.f90:190-250`：线性分支改为「按与**质量加权**刚体子空间的重叠」选零模（`rigid_overlap_tol=0.5`，取重叠最大的前 `n_zero` 个 → 天然优先真正的刚体模）；不足时 `modes.f90:225-250` 回退为最低 `|freq|` 并 **warning**（不再静默吞模）。
- 空间约定正确：`landscape_vib_rigid_basis`（`modes.m90:450-527`）用 `sqrt(m_at)` 加权、绕质量加权质心，与 `massWeightHessian`(M3 复用) 同一空间，因此可与 `work(:,i)`（投影后的质量加权矩阵）直接做重叠；`landscape_vib_rigid_overlap`（`modes.f90:530-556`）是投影范数 ∈[0,1]。
- 真线性分子的误判风险：Eckart 弯曲模与质量加权转动向量正交（Σ m_i z_i v_y,i = 0 正是转动向量与该模的正交条件），所以弯曲的重叠 ~0、刚体模 ~1，0.5 阈值有量级裕度；极端软伸缩与转角近简并的情形已由报告 30 §1 记录为欠定残余（落在 10² cm⁻¹，不在 3 cm⁻¹ 带内）——属**已披露的边界**，不是新缺陷。
- 不回归：非线性分支代码等价改写（`selected()` 取代 `order()` 计数，`modes.f90:253-283`），`test_co2_modes`（真 GFN2 数值 Hessian：`vib%n_zero=5`、`n_vib=4`、弯曲简并）与 `test_diatomic_analytic` 仍绿；新测 `linear-saddle-imaginary`（`test_landscape_vib.f90:492-540`，线性 H₂O `n_imag=2`）。
- 关键回归（M3 的 CO₂/HCN 3N−5、5 零模、`q_ROT`）在报告 30 §4 有数字，**方法学与 M3 一致**（同一 `--hess` vs `--lvib` 对照），但 CO₂ 的 0.02 cm⁻¹（HCN 0.00）在「两者都是线性、都跳过投影」的前提下需要解释（§5-6）。

### H4 — 已修复（核心）+ 文档半条（INFO）
- 谱投影：`eigenfollow.f90:600-617 landscape_project_hessian_rigid` = `P H P`（先列后行两次投影，P 对称、幂等；`n_rigid ≤ 0` 早退）；调用点在 `prfo.f90:440-443`（初始）与 `prfo.f90:486-492`（每次重算），**都在 `landscape_spectrum` / mode-follow 之前** → 判 `nneg`、抬升、模态跟随用的都是投影后的谱。
- 退化正确：非线性 6、线性 5（Gram-Schmidt 丢弃沿轴转动）、单体 0、维数非 3 倍数 0（`eigenfollow.f90:456-470`），且与步向量投影共用同一基（同一约定，无质量加权混用）。
- 噪声阈：`eigenfollow.f90:618-633 landscape_curvature_noise_tol`（相对 `max|λ|`，`curvature_noise_relative=1e-8`），用于 `prfo.f90:253-257` 与 `bprfo.f90:166-171` 的 `evals(i) < -neg_tol`。
- 警告去重与可诊断性：`prfo.f90:500-521`（`warn=.not. warned_lift`），每轮最多一条 warning；被抬升本征值仍打印（`lifted_evals`），每步 `lifted=` 仍进步表 → **不会静默吞掉真问题**（攻击面 4 通过）。
- 证据：CLI `xtb/landscape-ts-prfo` 断言输出不含 `lifted=T`（`CMakeLists.txt:929-934`）；单元 `prfo-noise-negative`（−1e-11 → `lifted=F` 且无 warning）与 `prfo-negative-downhill`（真负曲率仍抬升）。
- **未闭合的一小块（INFO-2）**：报告 30 声称「删掉 `project_hessian_rigid` → `xtb/landscape-ts-prfo` 红」。按修复自己的文档（`eigenfollow.f90:113-120`：未投影刚体模 ~1e-11），噪声阈 `1e-8·max|λ| ≈ 5e-9` **本身就足以**压掉 1e-11 的抬升；而 9 维驱动测试只对步投影敏感（drift 由 `project_rigid` 归零，Hessian 投不投影都不漂移）。因此「Hessian 投影」这一半的**边际必要性未被测试证明**。这不影响正确性（两个机制都安全），但报告里那条注入结论需要实测确认。
- **新风险（MEDIUM-2，见 §2）**：噪声门把 (−tol, 0) 的本征值留在 λ_n 方程里，而修复前是无条件抬升——那正是方程可解性的保护。

### M1 — 已修复（真修），测试有缺口（MEDIUM-3）
`engine.f90:771-789` 的 `effective_etemp` 从**计算器**回读（`TxTBCalculator`），否则回落 `ctrl%etemp`；`ts.f90:201` 赋值给 `result%etemp`；`results.f90:380-386` 在 `write_log` 打印 `etemp:`；`ts.f90:510-511` 让 `xtbts.log` 写**回读值**而非 settings。赋值的是**实际生效值**，正确。

### M2 — 已修复
`prfo.f90:766-795` 现清 `conv`（7 个 history 数组 + `n_iter` + `converged`），并清 `n_imag/imag_freq/is_saddle`，与 `dimer.f90:1050-1077`、`optimize/driver.f90` 对齐。M4 生产路径每进程一次，不可见 —— 与 29 号判断一致。

### M3 — 已修复
`ts.f90:488/500 get_namespace(trim(output_prefix)//'ts.xyz'|'ts.log')`（默认前缀 `xtb` → `xtbts.*`）；`setparam.f90:588-606` 只在 `namespace` 已分配时前置一次 → `ns.xtbts.xyz`，**无双前缀**。其余主程序级文件（`xtbtopo.mol`/`xtbrestart`/`xtbout.json`）对所有任务都不过 namespace，行为一致。测试 `CMakeLists.txt:1173-1179` + python `check_ts_namespace` + meson。

### M4 — 已修复（真修），且复核预测被证伪
新 `rigid_drift_model`（`test_landscape_saddle.f90:933-985`：9 维、内模 −0.5/+0.8/+1.2、刚性曲率 +0.05、梯度带 `+0.02·b_1` 的刚体分量）驱动测试 `driver-rigid-projection`（`test_landscape_saddle.f90:883-931`）：`remove_rigid=T` 时逐帧质心漂移 <1e-8（实测 7.5e-16）、`=F` 时 >1e-4（0.231）、末几何差 >1e-3 —— 断言是**驱动级**、含前置条件，非恒真；删掉 `prfo.f90:498-500` 的 `project_rigid` 必红（报告已实测）。缺口：该测试对 `project_hessian_rigid` 不敏感（INFO-2）。

### M5 — 部分修复（LOW-1）
`prfo.f90:626-635` 在 `finish()` 前对 final `mode` 调 `set_phase` + `report`（相位约定与初选一致，`eigenfollow.f90:403-417`），与 dimer 对齐，CLI 断言 `final transition vector` 存在。**但向量不是收敛点算的**：`prfo.f90:483-492` 只在宏迭代**开头**重算 Hessian 并 follow，`mode%vector` 因此对应「收敛前一步」的几何（其 `eigenvalue` 亦然）。收敛判据（位移/梯度阈值）很小，实际方向差异有限，但字面上的「在收敛点计算」未做到。

### M6 — 已修复
`settings.f90` 的 `step0` 文档改为「首次平移**上限**，`dR` 曲率探测可再缩短（实测 0.1032 而非 min(...)=0.28346）」；`main.F90:2880-2893 --lts-step0`；`dimer.f90:795` 的 `mobility=min(step0,step_max)/|F†|` 与 `dimer.f90:817-826` 的 `tau_eff/min(·,step_max)` 链已与文档一致。

### M7 — 已修复
`results.f90:66-73` 新增 `p_landscape_bound_trust/step_max`、`results.f90:90-96` `bound_kind`（默认 trust）、`results.f90:342-356` 表头按 `bound_kind` 打印 `trust/bohr` 或 `stepmax/bohr`；dimer 记录 `step_max` + `p_landscape_bound_step_max`（`dimer.f90:955-961`）。opt/scan/PRFO 不受影响。

### M8 — (a) 已修复 + 单测；(b) 已修复但无测试（LOW-4）
(a) `dimer.f90:374-385`：`if (abs(kappa) > dimer_kappa_floor) tau = min(mobility, 1/abs(kappa))` → κ<0 与 κ>0 同限幅；`dimer-mobility` 单测更新为 κ=−2.0 → τ=0.5。
(b) `dimer.f90:822-831`：quick-min 丢弃速度（`landscape_dimer_velocity_update` 的 `dot(v,F)<=0` 分支）导致 `|step|≤tiny` 时，回退为 `min(tau_eff*|F†|, step_max)·u`，消掉零步宏迭代（自述实测 dmax=0 计数 0/29 vs 4/39）。

## 2. 新发现（修复本身引入/暴露的问题）

**MEDIUM-1 `eigenfollow.f90:204`（模式选择不含噪声容差）**
- 现象：`nneg = count(evals < 0.0_wp)`，`index = target`（`target=1` 时即 index 1）。投影后的 Hessian 的刚体零模本征值是 `O(eps‖H‖)`（`eigenfollow.f90:113-120` 自己写了 ~1e-11；`P H P` 后更小），符号随机。
- 为什么是问题：初始 Hessian 无显著负本征值（从**极小点**起步）时，`count` 会把若干刚体零模算成负；`index=1` 因此是**刚体/零方向**而不是文档承诺的「最低（内）模式」（`eigenfollow.f90:173-176` 的语义：「at a minimum the search has to start uphill anyway → the lowest mode is followed」）。跟随刚体方向 = 步的上坡分量被 `project_rigid` 抹掉 → 搜索退化为极小化。报告 30 自己的证据正好落在这个行为上：线性 HNC（极小点）起步的 `--lts` **收敛到极小点**（0 虚频），而这是把「从极小点出发」这一正常用法变成了必失败路径。
- 最小修复：`nneg = count(evals < -landscape_curvature_noise_tol(evals))`（或在 nneg==0 时排除 `|λ| ≤ tol` 的模态与刚体子空间后取最低内模）；补一条合成谱单测（`evals = [-1e-16, -1e-17, +0.3, +0.5]`，断言选中的是 +0.3 而不是索引 1）。

**MEDIUM-2 `eigenfollow.f90:429-453` + `prfo.f90:253-257`/`bprfo.f90:166-171`（λ_n 对分不验证残差 + 噪声门留下的窗口）**
- 现象：`landscape_rfo_downhill_shift` 只检查**下端** `residual(lo) > 0`；上端 `hi = bmin − margin`（`eigenfollow.f90:429`）的残差从不检查。严格递减函数在 `[lo,hi]` 上没有根时（`residual(hi) > 0`），60 次对分会把 `lo→hi`，返回 `λ_n ≈ bmin − margin`（**不是方程的根**），而 `λ_n < 0` 的断言照旧通过。
- 为什么是问题：修复前「无条件抬升」把所有下坡本征值抬到 `hlow=1e-2`，方程天然良态；修复引入的噪声门（`prfo.f90:253-257`）恰好把 `(−tol, 0)` 区间留在方程里，而投影后的刚体零模**正落在这个窗口**。此时该模态的系数 `−F/(b−λ_n) ≈ F/margin = F·1e8`。触发「无根」需要 `F ≲ 1e-8`，故量级上限 ~1 bohr：不会给出错答案，但会**浪费信任半径**（步在投影前被裁剪，投影后内模分量变小）、并让 `predicted`（`prfo.f90:333-337`）无意义 → 经 `rho` 影响信任半径调整。修复前的无条件抬升反而掩盖了这一点。
- 最小修复：对分后加 `if (abs(landscape_rfo_downhill_residual(λ,f,b,k)) > tol_res) → 把 |b_i|<margin 的下坡本征值抬到 hlow 并 warning`（即把抬升降级为**回退**，保留 H4 的「只在需要时」语义）；加一条合成谱单测 `hess=diag(-0.5,-1e-16,0.5), g=[0.1,1e-11,0.1]`，断言 `|step|` 合理且残差 ≈0。

**MEDIUM-3 M1 的 `result%etemp` 无断言（`ts.f90:201` vs `CMakeLists.txt:994-1010`）**
- 现象：CLI `xtb/landscape-ts-etemp` 只断言 settings 打印（`electronic temperature: 5000.000 K`）与 engine 回读（`landscape engine: etemp 5000.000 K`）；`result%etemp`（`result%write_log` 的 `etemp:` 行，`results.f90:380-386`；`xtbts.log` 的 `electronic temperature (frozen)` 行，`ts.f90:510-511`）无人断言。报告 30 的 M1 证据是**手工**观察。
- 为什么是问题：把 `result%etemp = engine%effective_etemp()` 改成 `= settings%etemp` 或删掉该行，**全部 49 条仍绿**——正是 M3 MEDIUM-B「死字段」的复发形态，也是任务书攻击面 5 的直接提问。
- 最小修复：在 `xtb/landscape-ts-etemp`（CMake 与 python 两侧）加一条 `output MATCHES "etemp: +5000[.]000 K"` 或读 `xtbts.log` 断言 `electronic temperature (frozen): 5000.000 K`。

**LOW-1 M5 的最终向量来自收敛前一步的 Hessian**（`prfo.f90:483-492` vs `626-635`；dimer 同理 `dimer.f90:886-892` 的 final curvature 取自最后一次旋转的轴）。最小修复：在 `finish()` 前用最终几何重算一次谱再报（一次 Hessian 成本），或在文档里写明「最后一步宏迭代的谱」。

**LOW-2 H1 的自动收紧分支零覆盖**：`ts.f90:300-334` 的重算/再判/打印没有任何测试（`ts-curvature-band` 只测谓词；报告自认端到端触发未做）。建议把「命中带内 → 选哪组参数」抽成纯函数并测，或找一条曲率≈0 的几何（拉伸 H₂ 越过曲线极大点的 `--lts` 或 `--lts-hessian file` 注入一个带内谱）。

**LOW-3 H3 的回退 warning 路径未覆盖**：`modes.f90:225-250`（刚体基识别不全 → warning + 按最低 |freq| 补足）没有任何测试；只有「畸变/秩亏 Hessian」能触发（例如 `--lvib-hessian file` 读入非同几何矩阵）。建议用一个手工构造的畸变线性 Hessian 单测覆盖。

**LOW-4 M8b 的零步回退未覆盖**：`dimer.f90:822-831` 只有手工 dmax 计数；`dimer-velocity-update` 单测只覆盖快-min 原语。建议在驱动级单测（MB + 特定初速）断言 `result%steps(:)%dispnorm > 0` 全部成立。

**LOW-5 meson/python 镜像弱于 CMake 侧**：`landscape_cli_check.py check_ts`（新增）没有 CMake 侧的两条关键断言——不得含 `lifted=T`（H4 的主要证据）与必须含 `final transition vector`（M5 的证据）。meson 侧因此对 H4/M5 回归免疫。最小修复：把两条断言补进 python `check_ts`。

**LOW-6 `landscape_result%imag_freq` 语义**（`results.f90:157-160` 文档「Most negative (imaginary) frequency」）：`ts.f90:292/328` 在 `n_imag=0` 时把它设成**最低的正**内模频率；日志打印有 `n_imag>0` 守卫（`ts.f90:519-525`），但字段本身对极小点会给出正数。建议改名/改文档或仅在 `n_imag>0` 时赋值。

**INFO-1** `test/unit/test_landscape_optimize_xtb.f90:235-244` 被加入了与 M4 修复无关的「全精度梯度 dump」（注释说是 PLAN 实验 #4 的跨线程探针）。不破坏测试，但是修复轮的 scope creep，且让一条已提交的 M1 测试多出一大段 stdout；建议单独提交或删除。

**INFO-2** H4 的注入结论（删 `landscape_project_hessian_rigid` → `xtb/landscape-ts-prfo` 红）与 `eigenfollow.f90:113-120`（刚体模 ~1e-11 < `1e-8·max|λ|`）的算术相互矛盾——噪声阈本身可能已足够；需实测，否则「Hessian 投影」这一半是未被证伪的冗余。

**INFO-3** `results.f90:166-169` 的 `etemp` 文档写「zero when the task does not touch the engine」，但 opt/scan/vib 都会碰 engine 却从不赋值（同样为 0）。措辞不准。

**INFO-4** `settings.f90:430-433` 的 `hlow` 文档仍写「applied ... when the Hessian has more than one negative eigenvalue」，没有提新加入的噪声判据，也没写它一旦触发就把**整个**下坡子空间抬到 `hlow`（复核 29 H4 的第 2 点）。代码注释（`prfo.f90:238-251`、`bprfo.f90:161-165`）已说清，字段文档可再补一句。

## 3. 攻击面逐条（问题 1-11）

1. **H1 带内检测**：有符号（`abs(freq)`，虚频为负）✓；阈值作用在频率（cm⁻¹）✓；重算用同一 etemp/restart（只改 step/acc，`ts.f90:314-315`；restart 由 `engine_apply_restart` 统一）✓；收紧次数上界 1 ✓；重算仍带内 → 不动作但两组都打印（`ts.f90:322-328`）✓。**新问题见 MEDIUM-2**。
2. **H2 失败语义**：不污染外层（唯一消费者是 `landscape_ts`）✓；退出码经 `env%error`→`main.F90:988 env%checkpoint`→`error stop` **真传播** ✓；`res` 回写仍在（`main.F90:986-987` 在 checkpoint 之前）✓；三分支互斥穷尽（`select case(1/0/default)`）✓；`--lts-no-verify` 下不确认是有意开关 ✓。
3. **H3 线性分支**：真内模与刚体模用重叠区分（Eckart 正交性给量级裕度）✓；**回退 warning 路径未被测试走到**（LOW-3）；M3 的 CO₂/HCN 回归数字用与 M3 相同的方法学（`--hess` vs `--lvib` + `xtb thermo`）✓，但 CO₂ 的 0.02 cm⁻¹ 需解释（§5-6）。
4. **H4 谱投影**：做在 **Hessian** 上（`P H P`，`eigenfollow.f90:600-617`），步向量投影仍保留 ✓；基与步共用同一「质量无关」基（与 vib 的质量加权基是**不同空间**，各自内部一致，非混用）✓；非线性/线性/单体/非 3 倍维数退化齐备 ✓；warning 去重后仍每步记 `lifted=` 且打印被抬升本征值 → 不静默 ✓。**新问题见 MEDIUM-2**；Hessian 投影的边际必要性见 INFO-2。
5. **M1**：赋的是**实际生效值**（`engine.f90:771-789` 从 `calc%etemp` 读）✓；**没有测试能捕获「赋成设置值」** → MEDIUM-3。
6. **M3**：`--lts` 只写 `xtbts.xyz`/`xtbts.log`，两者都过 namespace；无双前缀（`setparam.f90:601`）；不存在同名不同内容的新旧路径（`--lopt`→`xtbopt.*`、`--lvib`→`hessian`/`vibspectrum`，互不重叠）✓。
7. **M4 驱动投影测试**：真覆盖驱动级调用（9 维、含刚体力的模型 + 前置断言 + 两轨迹分裂），不是构造恒真 ✓。
8. **M5 收敛点模态报告**：在收敛点**重定相**但**未重算**（LOW-1）；相位约定与初选一致 ✓。
9. **可证伪性（新/改测试）**：`ts-curvature-band`（谓词 + 常数，注入红）✓；`driver-rigid-projection`（两级前置 + 差异断言）✓；`prfo-noise-negative`（`env%nLog` 不变 + `lifted=F`，删噪声阈必红）✓；`linear-saddle-imaginary`（`n_imag=2`，回退旧分支必红）✓；`dimer-mobility`（公式数值）✓；CLI `ts-minimum`（exit≠0 + 3 诊断 + 文件）✓；`ts-etemp`/`ts-namespace`/`ts-dimer`/`ts-prfo` 检查了行为而非「不崩溃」✓。**弱项**：H1 重算分支、H3 回退路径、M8b 回退、M1 字段（LOW-2/3/4、MEDIUM-3）；meson 镜像缺两条关键断言（LOW-5）。
10. **回归（M0..M3）**：`modes.f90` 的非线性分支是等价改写（行为不变，`test_co2_modes`/`water-modes-gfn2`/`hessian-file-roundtrip` 仍在）；线性分支的非线性分子（H₂ 对角）分类**改变**——`etemp-control` 的断言已相应改写（|内模|>1、变化 >1e-3；实测 −1005.14→−1013.83 = −0.86%，去掉 etemp 推送仍必红），PLAN §9.5 的 −31.4 % 已更正；`--hess` 互操作不受影响（`--hess` 走 `src/hessian.F90`，不经过 `modes.f90`）。`settings.f90`/`results.f90` 为纯新增字段，M0..M3 默认值未动。
11. **数值卫生**：`implicit none(type,external)`、`only: wp`、`_wp` 字面量在新增/改动处齐备；无裸 `real`/`real*8`/直调 LAPACK；新常量都是 `parameter`（`landscape_ts_curvature_band_cm1`、`ts_tight_hess_*`、`rigid_overlap_tol`、`rigid_dependent_tol`、`curvature_noise_relative`），无 module 级可变量；除零/开方/归一化守卫齐（`1/abs(kappa)` 有 floor、`sqrt(max(s,0))`、`if (mtot>0)`、`if (nrm>0)`、投影/裁剪不放大）；`!>` 文档覆盖新过程与单位。唯一提示：`rigid_dependent_tol=1e-8` 在两处重复定义（`modes.f90:100`、`eigenfollow.f90:86`），可提取但无害。

## 4. 无 CRITICAL 的说明：我主动检查过的攻击面

- H1：谓词定义域（`n_zero=size(freq)` 时不越界）、cm⁻¹↔Eh/bohr² 换算、收紧上界、etemp/restart 统一、「参数是否真到 FD」（`engine.hess_step` 调用时读取 + `set_numerical_accuracy` 调用时拷贝）——这是 29 号当时无法确认、也是本修复能否成立的关键。
- H2：退出码全链路（`env%error`→`checkpoint`→`mctc terminate`→`error stop`）、文件写出顺序、`res` 回写顺序、三分支穷尽、对其它消费者的污染。
- H3：质量加权约定与 `massWeightHessian`/`projectHessian` 的一致性（并在报告中辨析与 `eigenfollow` 的质量无关基为何**不**矛盾）、Gram-Schmidt 归一化顺序、线性退化（两条转动 → 5 列）、单体（3 列）、Eckart 正交性对 0.5 阈值的裕度、非线性分支等价性。
- H4：`P H P` 的对称性/幂等性/退化、投影调用点相对 `landscape_spectrum` 与 mode-follow 的**顺序**、噪声阈的标度（相对 `max|λ|`）、线性/单体退化、警告去重后是否仍可诊断、以及**噪声门新增的窗口**（MEDIUM-2，含量级上界推导）。
- M1/M3：回读路径（`calc%etemp` vs `ctrl%etemp`）、`get_namespace` 的前缀语义、所有 `--lts` 输出文件名。
- M2/M4/M5/M6/M7/M8：reset 对齐、驱动级测试的构造是否恒真、最终相位施加点、`step_max/step0` 消费链、`bound_kind` 默认值在 opt/scan 上是否为 `trust`、κ<0 与零步回退的边界。
- 回归面：`--hess` 与 `--lvib` 的路径分离、M3 线性分类变更的影响范围（CO₂/H₂/`etemp-control`）、`settings.f90`/`results.f90` 是否改动旧默认值、`test/unit/main.f90`/`CMakeLists.txt`/`meson.build` 三处注册、`add_test` 名（grep 未见重名）。
- 未运行任何命令（只读工具），`-ffpe-trap` Debug 构建与所有注入实验均由父会话/验证者执行。

## 5. 需运行验证（我无法执行）

1. 构建 + `OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape` → 期望 49/49；`ctest -N -R landscape | tail -1` = 49；`grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d` 空；回归子集 `-R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'` → 12/12。
2. **注入（必须逐条重做，报告 30 的红/绿是自述）**：(a) 删 `prfo.f90:498-500` 的 `project_rigid` → `landscape-saddle` 的 `driver-rigid-projection` 红；(b) 删 `prfo.f90:443/488` 的 `project_hessian_rigid` → 我预测**仍绿**（见 INFO-2），实测后修正报告；(c) `landscape_ts_curvature_band_hit` 恒 `.false.` → `ts-curvature-band` 红；(d) 删 `ts.f90:370` 的 `result%converged=.false.` → `xtb/landscape-ts-minimum` 红；(e) 线性分支回退到「最低 n_zero」→ `linear-saddle-imaginary` 红。
3. **MEDIUM-1 的判定实验**：`xtb hnc.xyz --gfn 2 --lts --lts-method prfo --norestart --lts-printlevel 2`（或临时打印 `mode%index/eigenvalue`）→ 看选中的是不是 `index=1` 且 `eigenvalue≈±1e-17`（刚体零模）而不是最低内模；若是，本 finding 成立。
4. **MEDIUM-2 的判定实验**：在 `landscape_rfo_downhill_shift` 出口打印 `λ_n` 与 `residual(λ_n)`（HCN prfo 全程）→ 若 `|residual|` 不小（相对 `max(1,|λ_n|)`），说明返回的不是根；顺便加合成谱单测 `diag(-0.5,-1e-16,0.5)`、`g=[0.1,1e-11,0.1]` 看 `|step|` 与 `predicted`。
5. H4/V2：`--lts-hlow 1e-12` 与默认两次运行，统计 `lifted=T` 出现次数（期望 0）。
6. M3 回归：CO₂/HCN 的 `--lvib` vs `--hess` 频率表 + `q_ROT` 行，**同 restart 策略下**复核（解释 CO₂ 的 0.02 cm⁻¹ 与 HCN 的 0.00）；`etemp-control` 的 −1005.14→−1013.83。
7. M4 验收数字：MB `prfo vs bprfo RMSD`、`dimer vs prfo rmsd`、`n_hess=0`、GFN2 HCN 三方法步数与 `saddle confirmation - imaginary modes: 1`（应从 unit/CLI 输出里读，不要只抄报告）。
8. Debug 构建（`-fbounds-check -ffpe-trap=invalid,zero,overflow`）跑三种方法的 E2E（报告 30 §3-10 自认未做）。

## 6. 需父会话/所有者裁决的两处措辞

- PLAN §9.5 应补一句「从极小点起步时，模式选择可能落在刚体零模上（MEDIUM-1），此路径当前不能指望自动上坡」——否则 §9.5 的「从极小点也能启动」隐含承诺与实测不符。
- 报告 30 的 H4 注入结论（`project_hessian_rigid`）需按 §5-2(b) 实测后改写为「噪声阈是主防线，谱投影是冗余保险」或证实投影必要。