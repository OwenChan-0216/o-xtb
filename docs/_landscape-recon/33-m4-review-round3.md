# 33 — M4 最终小修轮独立复核（第三轮，read-only）

## 摘要（≤30 行）

**结论：接受（无条件接受本轮 5 项任务；M4 现在可以提交）。** CRITICAL 0 / HIGH 0 / MEDIUM 0 / **LOW 6** / **INFO 4**，无 CRITICAL/HIGH/MEDIUM，LOW 全部为报告措辞、记录完整性、输入校验与测试覆盖类，均不改变本轮交付物与验收判据。

| 任务 | 判定 | 关键证据 |
|---|---|---|
| 1 MEDIUM-1（极小点起步） | **已修复（真修）** | 选了 (a)：`eigenfollow.f90:217-237` 选最低内模 + `prfo.f90:760-846` 逃逸行走；触发条件双重（无显著负曲率 `prfo.f90:771-772` + 首步非上升 `prfo.f90:702-727`）；**CLI 真覆盖极小点路径**：`CMakeLists.txt:1167-1231` 与 `landscape_cli_check.py:456-499` 用与 `ts-minimum` **同一**线性输入，注入 A/B 均红（`injections/expA`、`expB-*-cli.txt`） |
| 2 MEDIUM-3（`result%etemp`） | **已修复（真修，边界已如实披露）** | `CMakeLists.txt:1000-1010` + python `check_ts_etemp` 加 `etemp:`/`xtbts.log` 两条断言；删赋值即红（`injections/expD-*.txt`）；「赋设置值」不可区分系设计必然（`ts.f90:172/207`），报告 §2 末段已写明 |
| 3 MEDIUM-2（λ_n 残差） | **已修复（真修）** | `eigenfollow.f90:484-491` 加**上端**残差校验 + `λ_n=0` 回退；单测 `test_landscape_saddle.f90:626-671` 自带前置断言，注入 C 红（`injections/expC-*.txt`）；19 次实测落盘 `m4-final-fix-data/med2/*.log` |
| 4 几何依赖性文档 | **已完成** | PLAN §9.5（1230-1272）+ 报告 26:314 / 27:519 / 28:381 / 30:188-208 各补节，含两起点对照表；无自相矛盾（仅 INFO-3 措辞） |
| 5 §5 运行清单 | **具体可核** | 9 项注入、acceptance/debug/m3/med2 四类原始输出齐；两处证据未落盘（INFO-1/2） |

**回归（攻击面 6-8）**：MB `6.3022e-06`、dimer-vs-prfo `7.7397e-05`（与 round 30 值一致，报告 30:156）、`n_hess=0`、弯曲 HCN 三方法 1 虚频 exit 0 —— 均**未被本轮改动触及**，因为逃逸只在「无显著负曲率」时触发，而 MB/弯曲起点都有负曲率（选模分支 `nneg>=1` 与原行为等价）；新逻辑全部落在 `saddle/`（只被 `tasks/ts.f90` 使用），`--lopt/--lscan/--lvib` 不受影响；M3 线性行为未动（`vib/modes.f90` 本轮未改，CO₂/HCN 打印谱逐位相同）。
**唯一需要父会话注意的数字出入见 LOW-1**：报告 32 §6 的「弯曲 HCN prfo 与修复前逐位相同」与仓库已记录的修复前值矛盾（详见正文）。

---

# 33 — M4 最终小修轮独立复核（第三轮）

> 复核者：fresh-context read-only reviewer（只有 read/grep/find/ls/watchdog_diff，**未运行任何命令**）。
> 对象：报告 32（本轮修复）、报告 31（上一轮「接受」）、以及当前工作树中的
> `src/landscape/saddle/{prfo,bprfo,eigenfollow,dimer}.f90`、`tasks/ts.f90`、
> `types/{settings,results}.f90`、`engine/engine.f90`、`prog/main.F90`、`xhelp.f90`、
> `test/unit/{test_landscape_saddle.f90,CMakeLists.txt,landscape_cli_check.py,meson.build,main.f90}`、
> `docs/xtb-landscape-PLAN.md`、`docs/_landscape-recon/{26,27,28,30,31,32}*.md` 与
> `docs/_landscape-recon/m4-final-fix-data/`。
> 纪律：每条判定附 `file:line`；测试绿/红取自落盘产物（父会话已跑），我无法执行命令。

## 0. 覆盖范围声明（重要限制）

M4 整体**尚未提交**：`watchdog_diff` 对 `src/landscape/saddle/*`、`tasks/ts.f90`、`test_landscape_saddle.f90` 只返回「untracked」，对 `types/settings.f90` 等返回的是相对 **M3 HEAD** 的差（含 round 26/27/28/30/32 全部改动）。因此我**无法产出一个「仅本轮」的有界 diff**；本复核判定的是**当前源码状态** + 本轮报告/数据，并对「本轮是否破坏已验收数字」按代码因果链分析（§2）。这一点请父会话在归档时知悉。

## 1. 逐条判定

### 任务 1（核心）— **已修复（真修，选项 a）**

**(i) 选模**：`eigenfollow.f90:217-237` 现在 `nneg = count(evals < -tol)`，`nneg==0` 时走
`landscape_lowest_internal_mode`（`eigenfollow.f90:674-693`，第一个 `evals(i) > tol`），并发出 warning；
`nneg>=1 but target>nneg` 仍回退到最负模（`eigenfollow.f90:224-230`）。`tol = landscape_curvature_noise_tol`
（`eigenfollow.f90:701-713`，相对 `max|λ|`，`curvature_noise_relative = 1e-8`）——**旧代码的 `index=1` 恒选刚体零模这一路径确实被移除**。

**(ii) 逃逸行走**：`prfo.f90:492`（`if (.not. initial_step_ascends()) call escape_from_minimum()`）+
`prfo.f90:760-846`。
- 触发条件**两条都满足**才动：无显著负曲率（`prfo.f90:771-772`）+ 首步模型步非上升
  （`prfo.f90:702-727`，`predicted < -escape_ascent_tol`，判据与驱动**同一**例程、`warn=.false.`）。
- 位移量：`settings%escape_step` 默认 0.2 bohr（`settings.f90:488`，量级论证在同处 `!>` 文档：笛卡尔 vs
  `d_mw/‖M^{1/2}v‖`，实测 `escape/` 未落盘但 HCN bend 的 `‖M^{1/2}v‖≈1.07` 在正文档里），
  CLI `--lts-escape-step`（`main.F90:2895-2910`，`xhelp.f90:398-401`），`0` 关闭。
- 记录：头部回显（`ts.f90:147-151`）+ 每次推走（`prfo.f90:830-834`，printlevel≥2）+ 收尾汇总
  （`prfo.f90:839-844`）。默认 `printlevel=1`（`settings.f90:163`）→ CLI 测试看到的汇总行确实会打印。
- **是否真的沿最低内模上坡**：推走方向 = 当前几何的最低内模（每次推走重新 `select_initial_mode`，
  `prfo.f90:820-825`），推走后重算 Hessian 并重投影（`prfo.f90:801-807`）。落盘实测
  `acceptance/min-prfo/stdout.txt:229-254`：index 6 → 7 → … → **1**，`0.08238897 → -0.00529919 Eh/bohr²`，
  7 push / 1.4 bohr，随后 5 步收敛、`imaginary modes: 1`、exit 0（`exit.txt = 0`）、
  E = −5.387373532908；`min-bprfo` 7 push + 7 步，E = −5.387373532839。**不会落回极小点**（若落回，H2 的
  确认路径会以 exit 1 + 诊断结束，如 `acceptance/hnc-escape-off/stdout.txt:245-291`）。
- **稳健性（新体系）**：停止条件是 `any(evals < -tol)`，总位移上限 `escape_max_walk = 3.0 bohr`
  （`prfo.f90:104`），单体系标定（GFN2 HCN/HNC）已在报告 32 §8.2 披露为启发式残余风险；
  没有任何机制保证推到的是「同一个 TS 的 basin」，但结果必须经 1 虚频确认（`ts.f90:342-380`），
  失败会给出非零退出码。属**已披露的启发式**，不是缺陷。

**(iii) 最关键的一条：CLI 是否真覆盖「极小点起步」**
**是。** `CMakeLists.txt:1112-1159`（`xtb/landscape-ts-minimum`）与 `1167-1231`（`xtb/landscape-ts-escape`）
用**同一个** `LANDSCAPE-HNC` 输入（线性，`N 0,1.156,0 / C 0,0,0 / H 0,-1.05,0`）。前者用
`--lts-escape-step 0` 锁住「该几何是一个极小点、不是鞍点」（`confirmation: minimum` + exit≠0），
后者用默认逃逸要求 escape 记录 + `rigid body overlap: 0.000000` + `imaginary modes: 1` + `first order saddle point`
+ exit 0，且 prfo/bprfo 都要求。**这不是又一次用 bent 猜测糊过去**：bent 猜测只出现在
`xtb/landscape-ts-prfo/dimer/etemp/namespace` 里。注入 A（逃逸立即 return）→ ts-escape 红
（`injections/expA-escape-disabled.txt:5` 「the escaped search terminated with status 1」）；注入 B
（选模回退成 `index=1`）→ ts-escape 红 **且** 单测红（`expB-selection-defect-cli.txt:5`、`expB-selection-defect-unit.txt:23`）。

### 任务 2 — **已修复（真修；断言能力边界已如实披露）**

`CMakeLists.txt:1000-1010`：`output MATCHES "etemp: +5000[.]000 K"`（来自
`results.f90:384-385`，`write(unit,'(1x,a,f12.3,a)') "etemp:          "`，只有 `self%etemp>0` 才打印）
+ `xtbts.log MATCHES "electronic temperature [(]frozen[)]: +5000[.]000 K"`（`ts.f90:513-517`，
写的是 `result%etemp`）。两条都是**与既有 settings/engine 回显不同的行**，正则不会串行匹配
（engine 行是 `landscape engine: etemp              <f12.3> K`，无冒号，`engine.f90:818-822`）。
注入 D（删 `ts.f90:207`）→ 红（`injections/expD-result-etemp-missing.txt:5`）。
**「把 `engine%effective_etemp()` 换成 `settings%etemp`」在本 CLI 上不可区分**——`ts.f90:172` 把
`settings%etemp` 拷进 `ctrl%etemp`，`engine.f90:779-793` 回读的就是同一个值，报告 32 §2 末段已明说，
并且已由「字段未赋值（D 红）」+「值未到达计算器（engine 回读 + M3 `etemp-control`）」两类断言补足。
判定：复核 31 的诉求（加断言）**已满足**；残余见 LOW-4。

### 任务 3 — **已修复（真修，且测量可检验）**

`eigenfollow.f90:466-491`：在 `residual(lo)>0` 之外新增 `residual(hi) > 0` 检查（hi = bmin − margin），
命中时 `λ_n = 0`、`solved=.false.` + `env%warning`（而不是返回区间端点）。B-P-RFO 侧因
`if (solved)` 守卫（`bprfo.f90:227-233`）不会进入半径方程，`fill_downhill` 取 λ=0 的牛顿下坡步——语义自洽。
**测量是可检验的**，不是「应该不会」：19 次真实求解落盘在
`m4-final-fix-data/med2/{bent-hcn-prfo,bent-hcn-bprfo,escaped-hcn-prfo}-shift-residuals.log`，
`residual(hi) = −5e-4 … −2e-2`、根的残差 ≤5e-16；推理也给了可达的量级条件
（`Σf² ≲ margin(margin−bmin)`）。单测 `test_landscape_saddle.f90:626-671`：
合成谱 `diag(-0.5,-1e-16,0.5)`、`F=[0,1e-11,1e-11]`，**先自行断言前置条件** `residual_hi>0`，再断言
`lam_n == 0.0_wp`、`env%nLog` 增加、`lifted` 为假、`|step| ≤ trust`；删校验即红（`expC-*.txt:44`）。
→ 真修 + 真可证伪。措辞精度问题见 LOW-5。

### 任务 4 — **已完成**

- PLAN §9.5（`xtb-landscape-PLAN.md:1230-1272`）：MEDIUM-1/2/3 处置 + 「**P-RFO / B-P-RFO 需要鞍点猜测或
  过渡向量**」+ 「dimer 不需要 Hessian，从极小点起步反而直接可用」+ 两起点 × 三方法实测表。
- 报告 26 §10（`26-...md:314-333`）、27 §12（`27-...md:519-536`）、28 §12（`28-...md:381-394`）、
  30 §6/§6.1（`30-...md:188-208`）各补一节，均点明「原稿的 HCN 验收起点是**弯曲**猜测」。
- **无自相矛盾**：三处仍可能被误读的地方已核查——
  (a) `eigenfollow.f90:173-176` 仍保留旧句式「at a minimum the search has to start uphill anyway」，
      但**同一 docstring 的下一段**（`178-188`）明确写了旧 `index=1` 导致搜索退化为极小化，
      且现在逃逸行走使该句重新成立 → 不构成矛盾（措辞见 INFO-3）；
  (b) PLAN §6.3（算法规格，`840-905`）与 `tasks/ts.f90` module doc（`20-61`）未提起点要求 → INFO-4；
  (c) 报告 26/27/28 中标「从极小点也能启动」的旧暗示已全部被 §10/§12 覆盖。
- 遗漏：无（在任务书点名的 4 个文件 + PLAN §9.5 范围内）。

### 任务 5 — **具体可核（非复述）**

§5 的 8 项都能在 `m4-final-fix-data/` 找到对应产物：acceptance（9 组 stdout+exit）、debug（6 组 log+exit）、
m3（CO₂/HCN 的 `--lvib`/`--hess` 输出，`4 internal, 5 projected zero modes`、`TR`）、med2（19 次残差打印）、
injections（9 份真实 ctest 输出）。两条复核预测被证伪也落盘：
`inj-e-linear-zero-modes.txt`（两次全绿、diff 空）与 `inj-b-hessian-projection-{unit,cli}.txt`（单元绿、CLI 红，
`lifted=T` 出现 4 次）。**证据缺口 2 处**见 INFO-1/2。

## 2. 回归攻击面（问题 6-10）

6. **是否弄坏已验收 M4 数字**：MB `prfo vs bprfo RMSD` 在注入产物中逐位复现
   `injections/inj-c-curvature-band.txt:102 = 6.3022E-06`（报告 28 §4.1 记 6.302e-6，裕度 159×）；
   dimer-vs-prfo 现为 `7.7397E-05`（同文件 :114，报告 30:156 记录 round 30 值就是 7.7397e-05，修复前 7.8177e-05）；
   `dimer Hessian requests 0`（:117）；弯曲起点三方法 1 虚频 exit 0（`acceptance/bent-*/`）。
   **机制上本轮不可能动它们**：逃逸的前置条件是「谱中无显著负曲率」（`prfo.f90:772`），而 MB/弯曲起点都有负曲率，
   因此选模分支与原行为等价（`eigenfollow.f90:219-222`）、逃逸不进入；`--lts-hlow 1e-12` 与默认都 `lifted=F`
   （`acceptance/bent-prfo/stdout.txt:235-241`）。→ **结论：未弄坏**。
   但报告 32 §6「弯曲 HCN prfo 与修复前**逐位相同**」的证据不成立，见 **LOW-1**（数字差 3.3e-7 Eh，机制上是
   round 30 的 H4，不是本轮）。
7. **是否弄坏 M3 线性分子**：`src/landscape/vib/modes.f90` 本轮未改；ts 侧新逻辑只在 `saddle/`，
   确认分析走 M3 原路径。落盘 CO₂/HCN 的 `eigval` 行两条路径（`--lvib` vs `--hess`）**逐位相同**
   （`m3/co2-{lvib,hess}/stdout.txt:238/265`、`hcn-*`），`4 internal, 5 projected zero modes` + `linear: T`。
   → **未弄坏**。注意：报告引用的 0.0036/0.0023 cm⁻¹ 出自 2 位小数以上的比较，落盘文件只证明「打印到 2 位小数相同」
   （|Δf| < 0.005），属一致但不独立复现（INFO-2）。
8. **是否影响 `--lopt/--lscan/--lvib`**：`landscape_select_transition_mode`/`landscape_lowest_internal_mode`/
   `escape_from_minimum` 的调用者只有 `saddle/prfo.f90`（grep 全层仅 `prfo.f90:471/959/962`、`eigenfollow.f90:310`），
   `escape_step` 字段属 `landscape_ts_settings`（`settings.f90:390-488`），opt/scan/vib 的 settings 是**独立类型**；
   `results.f90` 只新增 od 字段（`etemp`，`results.f90:168-170`），未改旧默认值。→ **无影响**。
9. **可证伪性（逐个新/改测试）**：`mode-select-lowest-internal`（改回 `index=1` 必红，`expB-unit`）、
   `prfo-lambda-n-no-root`（删校验必红，`expC`）、`xtb/landscape-ts-escape`（关逃逸必红，`expA`；
   改回旧选模必红，`expB-cli`）、`xtb/landscape-ts-minimum`（删 `converged=.false.` 必红，`inj-d`）、
   `xtb/landscape-ts-etemp`（删赋值必红，`expD`）、`xtb/landscape-ts-escape-step-missing`（错误分支，
   与另 3 个缺值测试同款）——**全部有实测红**。弱项：逃逸的「不触发」一侧无断言（LOW-3）；
   `initial_step_ascends` 无单测（同上）。
10. **数值卫生（N1..N18）**：新代码 `use xtb_mctc_accuracy, only : wp`、`implicit none(type, external)`、
   所有字面量带 `_wp`（`1.0e-12_wp`/`3.0_wp`/`2.0e-1_wp`）、无裸 `real`/`real*8`、
   `real(npush, wp)` 显式转换、无直调 BLAS/LAPACK、新常量全部 `parameter`、无 module 级可变量、
   `env%warning`/`env%error` + 无 `stop`、单位 a.u.、扁平 `xyz(3,n)`、新过程都有 `!>` 文档。
   除零/下溢守卫：`escape_step <= 0` 早退（`prfo.f90:767`）、`vec_norm(dvec) <= tiny` 守卫（`780`）、
   对分上端检查（`eigenfollow.f90:484`）、`if (solved)` 守卫（`bprfo.f90:227`）。→ **合规**。

## 3. 新发现（本轮引入/暴露）

### LOW-1（report-only，**唯一与数字有关**）报告 32 §6 的「弯曲 HCN prfo 与修复前**逐位相同**」与仓库记录矛盾
- 位置：`32-m4-final-fix-report.md:265`（表格行「弯曲 HCN prfo / bprfo / dimer …（与修复前逐位相同）」）。
- 证据：仓库里**唯一**的修复前记录是 `26-m4-saddle-implementation-report.md:159-183`
  （同一输入、`--lts --lts-method prfo`、4 步、1 虚频 −1426.11、`TOTAL ENERGY -5.387373532487`，
  逐步 `lifted=T`、首步 `lambda_p= 4.404775E-02 lambda_n= -1.466039E-02`）与
  `28-m4-validation-experiments.md:177`（prfo 4 步 / −5.387373532487）。本轮实测
  （`m4-final-fix-data/acceptance/bent-prfo/stdout.txt:235/240/252`）为
  `lambda_p= 4.620059E-02 lambda_n= -2.297021E-03 lifted=F`、**E = −5.387373532156**，
  即差 **3.31e-7 Eh**；bprfo 步数也由 6 变 5（能量 −5.387373532550 相同）。
- 归因：与 round 30 的 **H4 谱投影**一致（`lifted=T → F`；报告 30:157-159 已承认步数变化，但**没有记能量**），
  因此**不是本轮**的回归；但报告 32 用「逐位相同」当回归证据，而该句在仓库记录面前不成立。
- 最小修复：把该行改为「同一鞍点，ΔE = 3.3e-7 Eh（< 搜索容差的 1 %），差异归因于 round 30 的 H4 谱投影」，
  并把弯曲起点的三个能量补进报告 30 §4。

### LOW-2（code，建议 M5 前加 1 个守卫）`--lts-escape-step` 无下界 → 推走次数无界
- 位置：`prfo.f90:767-773`（`ntries = max(1, ceiling(escape_max_walk/settings%escape_step))`）；
  CLI 侧无校验 `main.F90:2895-2910`；`ts.f90` 只校验 method/文件/message，未校验 `escape_step`。
- 理由：每次推走 = 1 次能量 + **1 次 Hessian**（数值 Hessian 是 6N 个单点，`prfo.f90:787-795`）。
  `--lts-escape-step 1e-5` → 最多 3×10⁵ 次 Hessian ≈ 挂死；即使「合理」的 0.01 bohr 也会把
  HCN 的 7 次推走变成 ~140 次（成本 ∝ 1/escape_step，文档只写了 push 上界 `prfo.f90:749-750`，没写成本）。
- 最小修复：在 `ts.f90`（或 `main.F90`）拒绝 `0 < escape_step < 1e-3`，或把推走次数硬上限设为 ~100
  （与 `--lvib-temp 0` 的既有校验风格一致）。不影响默认路径，故非阻塞。

### LOW-3（test gap）逃逸「不触发」一侧与 `initial_step_ascends` 无断言
- 位置：`CMakeLists.txt:897-968`（ts-prfo）、`landscape_cli_check.py check_ts` 只断言 converged/1 虚频/
  `lifted=T` 不出现，**没有**任何 `escape … push` **不出现**的断言；`prfo.f90:702-727` 的探针无单测。
- 影响：删掉 `prfo.f90:772` 的负曲率守卫（改成永远逃逸）时，弯曲起点的四个 CLI 测试仍可能通过
  （只要求收敛 + 1 虚频），MB 单测也只对终态敏感。与复核 31 的 LOW-2/3/4 属同一类覆盖缺口。
- 最小修复：在 ts-prfo 的脚本里加 `if(output MATCHES "escape from a minimum: +[0-9]+ push")` → FATAL
  （bent 起点不应逃逸），成本 3 行。

### LOW-4（断言边界，已披露）`result%etemp` 无法区分「生效值 vs 设置值」
见任务 2。若要真正区分，需要给 engine 注入一个 etemp 与 settings 不同的假 calculator（现有测试无此 harness）。
本轮已用「字段未赋值」+「值未到计算器」两类断言覆盖了复核 31 的真正担忧，**判为已闭合**，此处仅记账。

### LOW-5（report 措辞）报告 32 §3.1 的「充分条件」方向不严格
- 位置：`32-m4-final-fix-report.md:§3.1`「**充分条件**是 `Σ_{i≠k}F_i² > mu_margin·(mu_margin − bmin)`」。
- 分析（`eigenfollow.f90:505-521` 的 residual）：`R(hi) = D − S`，`D = −hi`，`S = Σ f_i²/(b_i − hi)`；
  每项 `b_i − hi ≥ delta` 只给出 `S ≤ Σf²/margin`（**上**界），因此「Σf² 大」**不能**推出 `R(hi)<0`。
  严格的充分条件是**最低下坡模**的 `f_j² ≥ margin·(mu_margin − bmin)`（`S ≥ f_j²/delta`）；反过来
  「`Σf² ≤ margin·(margin−bmin)` ⟹ 无根」是成立的，也正是代码/PLAN/单测**实际写的**方向
  （`eigenfollow.f90:470-472`、`PLAN:1256-1260`、`test_landscape_saddle.f90:618-625`）。
- 影响：**仅报告措辞**，代码与断言不受影响；建议把该句改成必要条件的说法。

### LOW-6（记录完整性）逃逸未进入 `xtbts.log`，也不在 `landscape_result` 里
- 位置：`ts.f90:477-534` 的 `write_ts_files` 写 method/etemp/trust/Hessian source/步表/确认，
  **不写** `escape_step`、推走次数与总位移；这些只在 stdout（`prfo.f90:830-844`）。
- 影响：`min-prfo` 这类「结果由 7 次推走决定」的运行**无法仅凭 `xtbts.log` 复现**，
  而 `ts.f90:475-476` 自称「the file alone documents the run」；`--lts-step/--lts-step0` 等也有同类问题，
  但本轮新增的开关至少应与 `trust` 同级。最小修复：在 `write_ts_files` 加一行
  `escape step: <f12.6> bohr`（成本 2 行）。

### INFO-1 `m4-final-fix-data/escape/` 为空目录
报告 32 §9 把它列为 6 个数据子目录之一，实际为空（`ls` 返回空）。请在报告或目录布局里删除/补数据。

### INFO-2 两处「清单证据」未落盘
(a) §5 第 5 项（`--lts-hlow 1e-12` vs 默认统计 `lifted=T`）的第二个运行以「现场对比」记录，无产物；
(b) §5 第 6 项引用的 `Δf = 0.0036 / 0.0023 cm⁻¹` 不在 `m3/*.txt` 中（文件只给出 2 位小数的谱，
与结论一致但不能独立复现该数字）。建议补一行 6 位小数的对比表。

### INFO-3 措辞（低风险）`eigenfollow.f90:173-176`
`landscape_select_transition_mode` 的 docstring 顶部仍以「at a minimum the search has to start uphill anyway」
作为回退理由。同一 docstring 的下一步已纠正，但这句话正是 MEDIUM-1 的原始表述，建议改成
「…the driver's escape walk supplies the uphill direction（见 escape_from_minimum）」。

### INFO-4 文档位置补充
PLAN §6.3（`840-905`，实现者读的算法规格）与 `tasks/ts.f90` 的 module doc（`20-61`）未提「P-RFO 需要鞍点猜测/
有逃逸行走」；`PLAN §9.5` 与报告 26/27/28/30 已写。建议 §6.3 的「[失效模式] Newton 步滑到最近极小点」一行补一句指向逃逸行走。

## 4. 需运行验证（我无法执行；建议父会话逐条跑并落盘）

| # | 命令/实验 | 期望 |
|---|---|---|
| R1 | `cmake --build /tmp/xtb-land/build -j`；`OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape` | 51/51；`ctest -N -R landscape \| tail -1` = 51（我静态数得 12 套件 + 39 CLI = 51，与报告一致）；`grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt \| sort \| uniq -d` 空（我逐条核对 39 个字面名无重名） |
| R2 | 回归子集 `-R 'Singlepoint\|GFN\|model-hessian\|optimizer\|Argparser\|CAPI'` | 12/12 |
| R3 | **LOW-1 的判定**：`OMP_NUM_THREADS=1 xtb <bent-hcn.xyz> --gfn 2 --lts --lts-method prfo --norestart`（或从 unit 输出读） | 期望 E = −5.387373532156、`lambda_p=4.620059E-02`、`lifted=F`；与报告 26/28 的 −5.387373532487/`lifted=T` 对比，确认差异归因 round 30 的 H4，而不是本轮 |
| R4 | **LOW-2 的判定**：`xtb <hcn.xyz> --gfn 2 --lts --lts-escape-step 1e-5 --lts-printlevel 2`（超时 30 s） | 期望：明显不收敛/挂死（证实需要下界）；随后决定是否加校验 |
| R5 | LOW-3 的补丁验证：在 ts-prfo 脚本临时加「不得出现 `escape … push`」断言 | 期望仍绿（bent 起点不逃逸） |
| R6 | R6 复核本轮 9 项注入至少重跑 4 项（expA/B/C/D） | 与 `m4-final-fix-data/injections/*` 一致（红→还原→绿） |
| R7 | Debug 构建（`-fcheck=bounds -ffpe-trap=invalid,zero,overflow -fbacktrace`）跑 min/bent × prfo/bprfo/dimer | 6/6 exit 0、各 1 虚频；与 `m4-final-fix-data/debug/*` 一致（该目录已含 6 组，我核对无 ERROR/trap 行） |
| R8 | M3 回归：CO₂/HCN 的 `--lvib` vs `--hess`（含 6 位小数）与 `xtb thermo` 交叉 | `4 internal, 5 projected zero modes`、`TR` 行逐位、Δf ≤ 0.004 cm⁻¹（落盘文件只到 2 位小数） |

## 5. 「M4 现在是否可以提交」

**可以提交。** 本轮 5 项任务全部真修（1/3 有注入级可证伪，2 有注入级可证伪且边界如实披露，4 完整，5 可核）；
无 CRITICAL/HIGH/MEDIUM；已验收 M4 数字与 M3 线性行为**未被本轮改动触及**（机制 + 落盘证据双重支持）。
建议随提交一并做三件 ≤10 分钟的小事（不阻塞）：
① 按 LOW-1 改写报告 32 §6 的「逐位相同」并把弯曲起点能量补入报告 30 §4；
② 按 LOW-3 在 ts-prfo 脚本加 3 行「不逃逸」断言；
③ 删掉空的 `escape/` 目录（或补数据）。

**计数：CRITICAL 0 / HIGH 0 / MEDIUM 0 / LOW 6 / INFO 4。**