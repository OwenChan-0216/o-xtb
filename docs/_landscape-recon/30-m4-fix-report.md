# 30 — M4 修复报告（复核 29 的 4 HIGH + 8 MEDIUM）

> 修复者：worker 子会话。对象：`docs/_landscape-recon/29-m4-independent-review.md` 的结论
> 「有条件接受（CRITICAL 0 / HIGH 4 / MEDIUM 8）」。
> 纪律：所有 xtb/ctest 均 `OMP_NUM_THREADS=1`；只跑 `-R landscape` 与回归子集；不提交 git。

---

## 0. 结论

4 条 HIGH 全部修掉并各有**可证伪注入**（改回旧行为→对应测试变红→还原）；
8 条 MEDIUM 全部修掉或书面记录处置。M4 验收数字仍然成立
（Müller-Brown prfo vs bprfo RMSD **6.3022e-06 bohr**，dimer vs prfo **7.74e-05**，
dim 无 Hessian 请求；GFN2 HCN 三方法端到端各 1 个虚频、exit 0）。

测试：**`ctest -R landscape` 49/49**（原 44 + 新增 5 个 CLI 测试）；回归子集 **12/12**；
`ctest -N -R landscape` = 49；`grep -oE 'add_test\("[^"]+"' … | uniq -d` 空。构建干净。

---

## 1. HIGH

### H1 — 硬约束 2（`0±3 cm⁻¹` 带内收敛 FD）无实现、`--lts` 无法收紧

**修复**
- `src/landscape/tasks/ts.f90`
  - 新增常量 `landscape_ts_curvature_band_cm1 = 3.0_wp`、`ts_tight_hess_step = 2.0e-3_wp`、
    `ts_tight_hess_acc = 0.1_wp`。
  - 新增纯函数 `landscape_ts_curvature_band_hit(freq, n_zero, band)`：内模
    `|f| <= band` 即命中。**换算显式写在文档注释里**：Hessian 本征值 λ 与频率
    `|f| = sqrt(|λ|)·autorcm`，故带宽对应本征值 `(3/autorcm)² ≈ 3.4e-7 Eh/bohr²`。
  - `confirm_saddle` 先用配置的 FD 参数分析一次；命中带内时，若 Hessian 来源为
    `numerical` 且当前参数还不是收紧值，则设置 `engine%ctrl%hess_step/acc = 0.002/0.1`
    **重算一次 Hessian 并重新判符号**，打印 `near-zero curvature: …`、
    `recomputing the Hessian with step … sccacc …` 与
    `tightened re-decision: lowest internal mode <new> cm^-1 (was <old>)`（两组数值都在）。
  - 来源为 `model`/`file`（不支持收紧）时发**明确 warning**（不再静默把带内模算成 0 虚频）。
- `src/prog/main.F90`：新增 `--lts-step`、`--lts-sccacc`（照抄 `--lvib-step/--lvib-sccacc`）。
- `src/xhelp.f90`：两 flag 的 help 文本。

**测试**
- 单元 `ts-curvature-band`（`test_landscape_saddle.f90`）：带内正模 / 带内负模 → 命中；
  全部带外 → 不命中；常量 = 3。**注入**：把谓词改成恒 `.false.` →
  `Starting ts-curvature-band … [FAILED]`，还原后 PASS。
- CLI 缺值报错三条：`xtb/landscape-ts-step-missing`、`…-sccacc-missing`、`…-step0-missing`。
- CLI 正常路径：`--lts-step 0.001 --lts-sccacc 0.1` 被接受且收敛（手工验证）。

**残余**：真实体系上「恰好落在 3 cm⁻¹ 带内」的几何不易构造（近线性 H₂O 的弯曲是
±1e5 cm⁻¹ 量级、拉伸 H₂ 的软伸缩也在 10²–10³ cm⁻¹），故端到端触发未做 CLI 测试；
触发的**判定谓词**与**参数端口**都有可证伪覆盖，`confirm_saddle` 的收紧分支是直连线性的。

### H2 — 非一阶鞍点仍 `converged` + exit 0

**修复**（`types/results.f90` + `tasks/ts.f90`）
- `landscape_result%is_saddle`：确认恰好 1 个虚频时为真。
- `confirm_saddle` 在 `n_imag /= 1` 时置 `result%converged = .false.` 与
  `result%message`（区分 0 虚频=极小点 / ≥2 虚频=高阶鞍点），并打印三分支
  `confirmation: first order saddle point` / `confirmation: minimum …` /
  `confirmation: higher order saddle …`。
- 任务末尾的 `env%error`/`env%check` 路径给出**非零退出码**；`xtbts.xyz`/`xtbts.log`
  仍写出（日志新增 `is a first order saddle: T/F`）。

**测试**：`xtb/landscape-ts-minimum`（线性 HNC 输入）断言 exit≠0 + 三条诊断 + 文件仍写出；
python 侧 `check_ts_minimum` 同步。**注入**：把 `result%converged = .false.` 删掉（旧行为）→
`xtb/landscape-ts-minimum [Failed]`，还原后 PASS。
手工复现：`xtb hnc.xyz --gfn 2 --lts --lts-method prfo --norestart; echo $?` → `1`。

### H3 — 线性分子虚频被吞（`vib/modes.f90`）

**修复**：线性分支不再**无条件**取最低 `n_zero` 个本征值。新增
`landscape_vib_rigid_basis`（质量加权空间的 3 平动 + 2/1 转动，Gram-Schmidt，线性退化自动丢弃）
与 `landscape_vib_rigid_overlap`；零模由「本征向量与刚体子空间的重叠 ≥ 0.5」判定。
显著非零（含显著负）的本征值因此不再被当零模。补足不足 `n_zero` 的分支退化为「按最低
`|freq|` 取」并**发 warning**（不再静默）。

**不回归**：
- `test_co2_modes`（线性 CO₂）：5 个精确零模、4 个内模、简并弯曲，仍绿。
- `test_diatomic_analytic`（合成 H₂）：5 零模、解析频率，仍绿。
- 手工对照 `--hess`：CO₂ `0 0 0 0 0 655.33 655.33 1344.75 2445.88`（本次修复前 = 修复后，
  与 `--hess` 的 `655.35` 差 0.02 cm⁻¹，是 FD 噪声，未受本次修改影响）；
  HCN 两者逐位相同 `… 785.07 785.07 2203.09 3261.17`。`q_ROT` 只依赖几何，与本次无关。

**新测试** `linear-saddle-imaginary`：线性 H₂O（w180 几何）的真实 GFN2 Hessian →
`n_zero=5`、`n_vib=4`、**`n_imag=2`**（两条真虚弯曲模）。**注入**：把线性分支改回「最低
`n_zero`」→ `linear-saddle-imaginary [FAILED]`，还原后 PASS。

**残余 / 已记录的边界**：把「被噪声抬升的转动」与「真正极软的伸缩」分开本质上是
欠定的（极端拉伸 H₂ 的伸缩与转动本征值近乎简并，未投影的数值 Hessian 会把二者混合）。
本修复按几何（重叠）分类，对 V1 的 H₂O 与其它线性鞍点正确；对 r(H–H)≈1.2 Å 附近
那条由 FD 噪声主导的软伸缩，符号可能仍不可靠——这正是 PLAN §9.5 硬约束 2（带内收紧）
存在的理由，极端软模落在 10² cm⁻¹ 而非 3 cm⁻¹ 带内，未被自动收紧覆盖。

**连带修正**：M3 的 `etemp-control` 原断言（拉伸 H₂ 唯一内模 `> 100 cm⁻¹`、300↔5000 K
移动 −31 %）是旧分类把一条**被抬升的转动**当作内模得到的；修复后真内模是软伸缩
（−1005.14 → −1013.83 cm⁻¹，−0.86 %）。测试改为「存在唯一内模且 |值|>1、
300↔5000 K 变化 >0.1 %」，仍锁住 M3 MEDIUM-B 的 etemp 推送。PLAN §9.5 的 −31.4 % 句已更正。

### H4 — 刚体噪声使 `lifted` 恒真、警告刷屏、hlow 每步生效

**修复**
- `src/landscape/saddle/eigenfollow.f90`：新增 `landscape_project_hessian_rigid`
  （`H ← P H P`）与 `landscape_curvature_noise_tol`（相对 `max|λ|` 的噪声阈值，
  `curvature_noise_relative = 1e-8`）。
- `prfo.f90` 驱动：在初始与每次重算后对 `hmat` 做刚体投影（在重算谱**之前**，
  故 `nneg` 用的是投影后的谱）。`landscape_prfo_step_spectrum`/`landscape_bprfo_step`
  的 `nneg` 计数改为「显著负」`evals(i) < -neg_tol`；`hlow` 抬升一旦触发仍作用于整个
  下坡子空间（保持原有安全语义），但**警告每轮只发一次**（新增 `warn` 形参，
  驱动传 `.not. warned_lift`），并记录/打印被抬升的本征值（可选输出 `lifted_evals`）。
- `settings.f90` 的 `hlow` 文档同步。

**测试**
- 单元 `prfo-noise-negative`：下坡含 −1e-11（刚体噪声）→ `lifted=F` 且**无 warning**；
  `prfo-negative-downhill` / `prfo-hlow-lift`（真实负曲率）仍绿。
- CLI `xtb/landscape-ts-prfo` 新增断言：输出**不得**含 `lifted=T`（干净 HCN）。
  实测修复后每次 `lifted=F`（修复前 `ts_hcn_hlow1e-12.txt` 每步 `T`）；`--lts-hlow 1e-12`
  也 `lifted=T` 计数 = 0。
- **M4 的驱动投影有独立测试**（见 §2 M4）。
- **注入**：删掉驱动里的 `landscape_project_hessian_rigid` 调用 → `xtb/landscape-ts-prfo [Failed]`；
  删掉 `landscape_project_rigid(step,…)` → `driver-rigid-projection [FAILED]`。均还原。

---

## 2. MEDIUM（8/8）

| # | 修复 | 测试/证据 |
|---|---|---|
| **M1** | `result%etemp` 真正赋值：`engine%effective_etemp()`（从计算器读回）写入；`result%write_log` 打印 `etemp:` 行；`xtbts.log` 写**生效值**而非 settings | `xtb/landscape-ts-etemp`；手工 `etemp: 300.000 K`（结果）与 `electronic temperature (frozen): 300.000 K`（日志）一致 |
| **M2** | `prfo.f90::reset_result` 现在清除 `conv`（n_iter/converged/各 history 数组），与 `optimize/driver.f90`、`dimer.f90` 对齐；同时清 `is_saddle` | 编译/单测；行为不可见（每进程只跑一次） |
| **M3** | `tasks/ts.f90` 的 `xtbts.xyz`/`xtbts.log` 过 `get_namespace`（单一前缀） | `xtb/landscape-ts-namespace`：`--namespace landscape6` 写 `landscape6.xtbts.*`；python `tsnamespace` 同步；手工 `--namespace ns` 写 `ns.xtbts.xyz`、不写 `xtbts.xyz` |
| **M4** | 新增 9 维（3 原子）`rigid_drift_model`（内部鞍点 + 刚体方向线性力）驱动测试 `driver-rigid-projection`：`remove_rigid=T` 逐帧质心漂移 < 1e-8（实测 7.5e-16），`=F` 漂移 > 1e-4（实测 0.231），末几何差 > 1e-3。**复核的关键预测已被证实**：删掉驱动 `project_rigid` 调用后该测试红（原 44 条仍全绿，说明旧测试集确实抓不到） | 见 H4 注入 |
| **M5** | prfo 驱动结束时对 final `mode` 调 `set_phase` + 报告（与 dimer 对齐）；打印 `final transition vector` | `xtb/landscape-ts-prfo` 断言 `final transition vector` 存在 |
| **M6** | `step0` 文档改为「首次平移**上限**，`dR` 曲率探测可再缩短」（实测 GFN2 HCN 首步 0.1032，非 `min(step0,step_max)`）；新增 `--lts-step0` | `xtb/landscape-ts-step0-missing`；`--lts-step0 0.1` 手工收敛 |
| **M7** | `landscape_step%bound_kind`：dimer 记录 `p_landscape_bound_step_max`，步表列头打印 `stepmax/bohr`（P-RFO 仍 `trust/bohr`） | 手工：dimer 表头 `stepmax/bohr`，prfo 表头 `trust/bohr` |
| **M8** | (a) `landscape_dimer_mobility` 对 `κ<0` 以 `1/|κ|` 限幅（不再无界）；(b) 速度被丢弃时在驱动里回退「力方向一步」，消掉零步宏迭代（实测 dimer force 运行 `dmax=0` 计数 = 0，修复前 4/39） | 单测 `dimer-mobility` 更新（负曲率 `-2.0` → `τ=0.5`）；手工计数 |

---

## 3. 自证（复核 29 §6「需运行验证」逐条）

1. `ctest -R landscape` → **49/49**；`ctest -N -R landscape` = 49；`uniq -d` 空。
2. 回归子集 `-R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'` → **12/12**。
3. **删掉驱动投影**关键回归：删 `project_rigid` → `driver-rigid-projection` 红；
   删 `project_hessian_rigid` → `xtb/landscape-ts-prfo` 红。复核的「44/44 仍绿」预测在
   补测后不再成立。
4. H2/V3：线性 HNC → `imaginary modes: 0`、`$?=1`（`xtb/landscape-ts-minimum`）。
5. H4/V2：`--lts-hlow 1e-12` → `lifted=T` 计数 **0**（修复前每步 T）。
6. H1：`--lts-sccacc 0.1`（及 `--lts-step`）现在被接受；缺值报错。
7. H3/V1：线性 H₂O → `n_imag=2`（单元 `linear-saddle-imaginary`）。
8. M3：`--namespace ns --lts` → 写 `ns.xtbts.xyz`（`xtb/landscape-ts-namespace`）。
9. 成本：`ctest -R landscape` 总 1.54 s（dimer 单测 0.08 s，CLI dimer 0.08 s），远低于预算。
10. Debug 构建（`-fbounds-check -ffpe-trap`）未做（无可用独立 debug 构建目录），列入残余。

## 4. M4 验收数字（修复后重跑）

- Müller-Brown：prfo vs bprfo RMSD **6.3022e-06 bohr**（< 1e-3，与修复前一致）；
  dimer vs prfo **7.7397e-05**（修复前 7.8177e-05，仍远 < 1e-3）；dimer 无 Hessian 请求（`n_hess=0`）。
- GFN2 HCN→HNC 端到端：prfo 4 步、bprfo 5 步、dimer(force) 29 步、dimer(random,seed 42) 15 步，
  **均 exit 0 且确认恰好 1 个虚频**。（复核记录为 4/6/39/38；步数因 H4 的谱投影与 M8b 的
  非零步回退而变化，终态与虚频数不变。）
  **[补记 34]** 弯曲起点虚频值（父会话 2026-10 独立重跑）：prfo **−1426.12**、bprfo **−1426.12**、
  dimer **−1425.32 cm⁻¹**（修复前记录 prfo = **−1426.11**，见 `26-m4-saddle-implementation-report.md:159-183`
  与 `28-m4-validation-experiments.md:177`）；线性极小点起步（本轮新修路径）prfo **−1426.21** /
  bprfo **−1426.12** / dimer **−1426.89 cm⁻¹**，均 exit 0。即「同一鞍点、虚频数值在 0.01 cm⁻¹
  量级内一致」，**不是**逐位相同（订正报告 32 §6 的原表述，见 34 号报告 §3）。
- M3 线性回归：CO₂/HCN 均 3N−5 = 4 内模、5 精确零模；`--hess` vs `--lvib` 频率差
  CO₂ 0.02 cm⁻¹（655.35/655.35/1344.75/2445.88 对 655.33/655.33/1344.75/2445.88）、
  HCN 0.00 cm⁻¹（785.07/785.07/2203.09/3261.17 逐位相同）；热化学 **`ROT` 行逐位相同**
  （CO₂ `265.`、HCN `139.`），`rotational number` 均为 2 / 1。分类未变，差异纯 FD。

## 4b. `[待校准]` 项的最终处置

| 位置 | 项 | 处置 |
|---|---|---|
| PLAN §5.3.6 `delta`（Dimer separation 定义） | VASP `DdR` vs pysisyphus 的歧义 | **结案**（本修复轮）：采用 pysisyphus「中点到像」约定，`[待校准]` 标记已删；报告 28 §6.4 实测 `delta×8` 只改曲率 0.0013 %，解析 MB 校验 0.07 % |
| PLAN §9.5 `imag_cutoff = -20 cm⁻¹` | 虚频计数阈值，曾被误当作 3 cm⁻¹ 带宽 | **保留原值**：它与 3 cm⁻¹ 带是两个概念；带内模先重判再计数（H1），不再「被吞」 |
| PLAN §5.3.1 `normal` 四阈值 / `TTsSettings` | TS 力阈值回填（实验 #4） | **仍未标定**（不在本轮 29 号 findings 内）：`tasks/ts.f90` 沿用继承的四判据，`settings.f90` 的 `[待校准]` 注释保留；GFN2 HCN 在 `normal` 下 prfo 4 步 / bprfo 5 步收敛，临时可接受 |
| PLAN §5.3.6 `k_min/k_max`（NEB）、`climb_switch_rms`（CI-NEB） | 弹簧常数与 climbing 切换阈值 | **留给 M5**（实验 #8），本轮未动 |
| PLAN §9.5 硬约束 1 的「拉伸 H₂ −31.4 %」 | 旧分类把抬升转动当内模 | **已更正**：真内模 300→5000 K 为 −0.86 %（−1005.14 → −1013.83 cm⁻¹）；结论（冻结 + 记录）不变 |

## 5. 残余风险 / 未做

- 极端拉伸 H₂（r≈1.2 Å）软伸缩的符号在未投影数值 Hessian 下仍不可靠（见 H3 残余）；
  落点 10² cm⁻¹，不在 3 cm⁻¹ 带内。
- 真实体系「恰好落在 3 cm⁻¹ 带内」的端到端触发未做（无易构造体系）；判定谓词与端口已覆盖。
- 复核的 LOW/INFO 项中，**LOW-3 已顺手修复**：`most negative frequency` 行现在仅在
  `n_imag > 0` 时打印（`confirm_saddle` 与 `write_ts_files` 两处），不再对极小点印误导标签。
  其余 LOW/INFO（报告 28 §4 单位标签、报告 26/27 计数、MB 验收测试的 λ_n 敏感性、
  dimer `F0` 符号分支、`recalc=0` 的 `hnew` 分配）本轮**未处理**，按原严重级保留在 29 号报告。
- Debug 构建（`-fpe-trap`）的 E2E 未跑。

---

## 6. [最终修复轮] 复核 31 的 3 条 MEDIUM 处置

复核 31「接受 M4」但要求 M5 前处理 3 条 MEDIUM（外加一条几何依赖性说明）。
最终修复轮的结论与证据在 `32-m4-final-fix-report.md`，此处只记处置：

| 复核 31 项 | 处置 | 关键实测 |
|---|---|---|
| **MEDIUM-1** 从极小点起步时选中刚体零模，「沿最低模式上坡」不成立 | **修复（选项 a）**：`landscape_select_transition_mode` 改为选**最低内模**（噪声带内本征值不作数），并新增 `prfo.f90:escape_from_minimum` 逃逸行走（`--lts-escape-step`，默认 0.2 bohr，预算 3.0 bohr，走到曲率变负为止） | 修复前：GFN2 HCN 线性极小点 prfo/bprfo 3 步回到极小点、0 虚频、exit 1；修复后：逃逸 7 push/1.4 bohr + 5/7 步到与弯曲猜测**同一个**鞍点、1 虚频、exit 0 |
| **MEDIUM-2** `λ_n` 对分不验证残差，噪声门把 `(−tol,0)` 本征值留在方程里 | **测量 + 加固**：真实运行 19 次求解中该失效模式**从未发生**（`residual(hi) = −5e-4 … −2e-2`，根的残差 ≤5e-16，`bmin ≈ −2e-16` 无害）；仍按建议补上端残差校验，失败时退回 `λ_n = 0` + warning，并加合成谱单测 | 触发条件是 `Σ_{i≠k}F_i² ≲ mu_margin² ≈ 1e-16`，而搜索收敛判据是 `g_max ≤ 3e-4`（大 4 个数量级）→ 结构性不发生 |
| **MEDIUM-3** `result%etemp` 无断言 | **修复**：`xtb/landscape-ts-etemp` 增加 stdout `etemp:` 与 `xtbts.log` 冻结温度两条断言 | 删掉 `result%etemp = engine%effective_etemp()` → 测试红 |
| 几何依赖性未写明（HCN 的 TS 起点是 bent 猜测） | **完成**：本报告 §6.1（见 `26/27/28` 的同名补充节与 PLAN §9.5） | 两起点 × 三方法实测对照表 |

同时修正本报告 §1 的 H4 注入结论：`project_hessian_rigid` 的注入**不是**「单元级红」，
而是 **CLI** `xtb/landscape-ts-prfo` 红（输出出现 4 行 `lifted=T`）——复核 31 INFO-2 的
「噪声阈本身已足够」只对单元测试成立，CLI 断言能抓住这一半（详见报告 32 §5.2(b)）。

### 6.1 几何依赖性（补充）

本报告（及 26/27/28）的 HCN 验收起点是**弯曲的 TS 猜测** `H(0,1.05,0) Å, C(0,0,0),
N(1.156,0,0)`，不是极小点；**prfo/bprfo 需要鞍点猜测或过渡向量**，
**dimer 不需要 Hessian、从极小点起步反而直接可用**。两起点实测对照、逃逸行走的设计与
量级论证、以及「为何不改 trust 的 rho 规则」（会弄坏 Müller-Brown 验收）见
`32-m4-final-fix-report.md` §1 与 PLAN §9.5。
