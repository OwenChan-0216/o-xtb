# xtb landscape 套件实施计划（PLAN）

> 状态：**已批准方向的落地计划**（PLAN 阶段交付物，不含 Fortran 代码）
> 目标仓库：`/home/owenchan/work_path/coding/fortran/xtb`（graf 模式；当前 HEAD `1779020`，版本 `6.7.1`，见 `CMakeLists.txt:29`）
> 引擎：GFN2-xTB（`TxTBCalculator`，`src/xtb/calculator.f90:60`）
> 证据来源（本计划全部技术断言的出处）：
> - **R01** `docs/_landscape-recon/01-maple-dispatcher-architecture.md`（MAPLE 算法清单与默认值）
> - **R02** `docs/_landscape-recon/02-xtb-current-capabilities-audit.md`（xtb 现状与复用面）
> - **R03** `docs/_landscape-recon/03-python-to-fortran-feasibility.md`（可行性分级、数值卫生、LOC）
> - **R04** `docs/_landscape-recon/04-web-research-ts-irc-state-of-art.md`（公式/步长/失效模式/去风险清单）
> - **R05** `docs/_landscape-recon/05-fortran-prior-art-and-interface-design.md`（DL-FIND、复用判定、建议设计、M0–M7）
>
> 本计划中形如 `(file:line)` 的行号均为**本次写作时在本仓库实测确认**；形如 `[R04 §2.1]` 的引用指向上述报告。
> 唯一允许的例外标注：`[待校准]` 表示该默认值存在单位/取值歧义，已指定承担校准的里程碑与实验编号。

---

## 目录

1. 摘要与决策记录（D1–D4）
2. 问题陈述：ANCopt 的任务完整性缺口
3. MAPLE 对照矩阵
4. 总体架构
5. 接口契约
6. 算法清单与出处
7. 数值卫生规范
8. 测试策略
9. 分阶段里程碑 M0–M7
10. 风险登记册
11. 明确不做的事
12. 集成点

---

## 1. 摘要与决策记录

### 1.1 摘要

xtb 6.7.1 已具备 `sp / opt / scan / hessian / freq`（R02 §0 能力矩阵），
但**没有过渡态优化器、没有内禀反应坐标积分、没有 chain-of-states**（R02 §5）。
官方在 issue #494 明确回答 "xtb does not implement a transition state optimizer"（R04 §83）。
本计划在 xtb 仓库内新增 `src/landscape/` 模块树，用 Fortran 重建
`sp / opt / scan / ts / hessian / freq / irc` 全套 PES 任务，算法以文献与
MAPLE（Python）实现为对照基线（R01/R03），复用 xtb 私有内核
（`TCalculator`、`tb_anc`、`bfgs/powell`、`numhess`、`trproj`、`model_hessian`、`constrain_pot`）。
设计原则：**抽象引擎边界 + 可替换 Hessian 提供者 + 无全局状态 + a.u. 内部单位**。

### 1.2 决策记录（上游仓库所有者拍板，原文记录）

**D1 — 落地位置。**
> 集成进 xtb 仓库，新增 `src/landscape/` 模块树，模块前缀 `xtb_landscape_*`，通过 `set_runtyp` +
> `src/prog/main.F90` 分派接入新子命令。直接复用 xtb 私有模块
> (`class(TCalculator)%singlepoint/hessian`, `tb_anc`, `numhess`, `trproj`, `freq/*`, `constrain_pot`)。
> 不新建独立项目，不做可独立编译的子库。

*后果*：新代码成为 `libxtb` 的一部分（与 `src/freq/**` 相同机制，
`src/CMakeLists.txt:24` 的 `add_subdirectory("freq")` + `src/freq/CMakeLists.txt:18-26` 的
`set(dir ...)` / `list(APPEND srcs ...)` / `set(srcs ${srcs} PARENT_SCOPE)`）。因此 **必须遵守 xtb 现有的编译标志与语言级约束**
（GNU：`-fdefault-real-8 -fdefault-double-8 -ffree-line-length-none -fbacktrace`，R02 §7.3），
并且**不得引入任何新的外部依赖**（无 Ipopt、无 torch、无 scipy 等价物）。
新模块可以直接 `use` xtb 私有模块，但**禁止**反向依赖（xtb 现有模块不得 `use xtb_landscape_*`）。

**D2 — 范围。**
> 实现 sp / opt / scan / ts / hessian / freq / irc 全套。TS 含 PRFO、B-PRFO(单体系)、dimer、
> NEB、CI-NEB、AutoNEB、string(GSM)。IRC 含 GS、HPC、LQA、EulerPC。
> 明确排除：DMF(需 cyipopt/Ipopt)、blbfgs/BPRFO 的批量 GPU 版、ML 势 calculator、parmfit、MD 系综。

*后果*：目标算法的 Fortran LOC 规模约 **20k 行**（R03 §B 各文件估算求和 + 驱动/测试），
必须分 8 个里程碑推进（§9）。`B-PRFO` 的术语在公开文献中无法唯一定位（R04 §25，confidence low）；
**本计划采用的解释**：B-PRFO = MAPLE `ts/algorithm/BPRFO.py` 所实现的 **RS-P-RFO（restricted-step
partitioned RFO）单体系版本**（`BPRFO.py:52-80` 的参数 `trust_init/trust_min/trust_max/hessian_update`
与单体 PRFO 同族），其与 PRFO 的唯一结构差异是 uphill/downhill 子空间的 trust-radius 分配比例
`alpha`（`PRFO.py:140-351` 的 `alpha∈[0.05,0.95]`）以及不依赖批量张量。
若仓库所有者对 "B" 另有定义（Baker / Banerjee），只需替换 M4 的 `saddle/bprfo.f90` 一个文件，
不影响接口契约。

**D3 — Hessian 策略。**
> 数值 Hessian 为主。初猜用 model_hessian (Lindh/Swart/EEQ)，重算用 numhess(中心差分, step 0.005 bohr)，
> 沿路径用 Bofill/BFGS/Powell/SR1 更新。但必须把 Hessian 提供者抽象为可替换的 abstract interface，
> 为将来插入解析实现预留。

*后果*：Hessian 是**唯一跨任务的公共依赖**（RFO/PRFO/全部 IRC/freq 都需要，R01 §0），
因此抽象必须放在 M0，而不是等到 M3。数值 Hessian 的成本是 **6N 次 E+G**
（R04 §85；`TCalculator%hessian` 两侧差分，`src/type/calculator.f90:103`），
`Δt` 与 `accu_hess` 的默认值**沿用 xtb**（`step_hess = 5.0e-3` bohr、
`accu_hess = 0.3`，`src/type/setvar.f90:156-158`），但必须在设置里可覆盖，
并由 §8 实验 #2/#3 校准。

**D4 — 本轮深度。**
> 只做 M0 + M1。M0 = 骨架 + 引擎边界 + settings/result 类型 + 构建接入 + 测试骨架。
> M1 = 极小化器 sd/lbfgs/bfgs/diis/rfo + Hessian 更新公式 + 线搜索 + 统一 driver。
> M2-M7 只写进 plan，不在本轮实现。

*后果*：本文件对 M0/M1 给出**文件级**规格（§9.1/§9.2），对 M2–M7 只到模块级。
本轮不实现 `--lscan/--lts/--lirc`，只注册 `--lopt`（§12）。

---

## 2. 问题陈述：ANCopt 的任务完整性缺口

### 2.1 确定性 grep 证据（本仓库实测，可复现）

复现命令（在仓库根执行）：

```bash
for k in popt prfo nudged neb lqa gonzalez 'intrinsic reaction' 'reaction path'; do
  printf "%-20s %s\n" "$k" "$(grep -ril "$k" src/ | tr '\n' ' ')"
done
grep -rni dimer src/ | wc -l          # -> 13
grep -rln irc src/                    # -> 3 files
```

| 关键字 | 命中文件 | 结论 |
|---|---|---|
| `popt` | （无） | 0 命中 |
| `prfo` | （无） | 0 命中 |
| `nudged` | （无） | 0 命中 |
| `lqa` | （无） | 0 命中 |
| `gonzalez` | （无） | 0 命中 |
| `intrinsic reaction` | （无） | 0 命中 |
| `reaction path` | （无） | 0 命中 |
| `neb` | `src/define.f90:26`、`src/xhelp.f90:560` | 仅命中 `de**fine**banner` / `definebanner` 的字母子串，**无 NEB** |
| `dimer` | `src/dipro.F90`（12 行）、`src/prog/main.F90:719` | 12 处全在 `src/dipro.F90`，属 **DIPRO 电子结构方法**（dimer projection，`src/dipro.F90:21,77,145-156,273,338-347`）；`main.F90:719` 是 DIPRO 的调度注释。**与 Dimer TS 方法无关** |
| `irc` | `src/lidep.f90:143`、`src/readin.f90:50`、`src/optimizer.f90:618` | 3 处全为英文子串：`circumvent`（×2）、`mirco`。**无 IRC** |

（与 R02 §5.1 的结论逐条一致。）

### 2.2 ANCopt 的实际能力边界

| 能力 | 位置 | 说明 |
|---|---|---|
| 极小化 | `src/optimizer.f90:122 ancopt`（RF trust-region）、`src/relaxation_engine.f90:400 l_ancopt`、`:131 fire`、`src/lbfgs_anc/driver.f90:39 relax_pbc` | 4 引擎，全部是**极小化 only** |
| `tsopt` 标志 | `src/setparam.f90:515`；唯一效果在 `src/optimizer.f90:341-344` | 把 `hlow` 抬到 0.25、`iupdat=1`（Powell 更新）。**没有本征向量跟随、没有 RFO→RFO、没有 Dimer/NEB** |
| `tsroot` | `src/setparam.f90:501` | 默认 0，只在 `set_module.f90` 读写，**无计算用途** |
| 近似替代 | `src/modef.f90:34 modefollow`、`src/hessian.F90:666 distort`、`src/bias_path.f90:30 bias_path` | 模式扫描、沿虚频位移生成初猜、RMSD push/pull metadynamics pathfinder。**都不是标准 TS 优化** |
| 收敛判据 | `src/optimizer.f90:48 get_optthr` + `:972-978` | 仅 **2 判据**：`abs(echng)<ethr .and. gnorm<gthr`。**无 max/RMS 力与位移四判据** |
| Hessian | `src/hessian.F90:33 numhess`、`src/type/calculator.f90:103 hessian` | 数值（两侧差分），可 ODLR 近似 |

**结论**：`ts` 需要从零实现（P-RFO/Dimer/NEB/string 与选模/跟随逻辑）；
`irc` 需要从零实现（质量加权积分器 + 路径 Hessian 更新）；
`opt/scan/hessian/freq` 已存在但**缺少统一调度与四判据收敛报告**，
且既有引擎不暴露可复用的算法原语（`solver_sspevx/solver_ssyevx` 是
`src/optimizer.f90` 的 module-private，R02 §10 风险 1）。

---

## 3. MAPLE 对照矩阵

评级沿用 R03 §B/§E.1 的 4 级：**1:1**（机械改写）/ **redesign**（需重构语义）/
**impl**（需新实现辅助算法）/ **excl**（排除）。

| 任务 | MAPLE 实现（R01） | xtb 现状（R02） | 本计划目标 | 移植评级 | 阻塞 |
|---|---|---|---|---|---|
| sp | `dispatcher/sp/sp.py:14`（112 行） | ✅ `src/single.f90:37`、`TCalculator%singlepoint` | `tasks/sp.f90` 包装 + 梯度输出 | 1:1 | 无 |
| opt: sd | `optimization/algorithm/SDCG.py`（557 行，`SD=SDCG`） | ⚠️ FIRE 是惯性松弛，非纯 SD | `optimize/sd.f90` | 1:1 | 无 |
| opt: cg(PRP+) | 同上（`SDCG.py:16-20`） | ❌ | `optimize/cg.f90` | 1:1 | 无 |
| opt: lbfgs | `optimization/algorithm/LBFGS.py`（219 行，两循环 `:61-84`） | ✅ `lbfgs_step`（`src/relaxation_engine.f90:802`） | `optimize/lbfgs.f90` | 1:1 | 无 |
| opt: bfgs(全) | 隐式在 `RFO.py`/`PRFO.py` 的更新中 | ✅ `src/bfgs.f90:20 bfgs`（packed） | `optimize/bfgs.f90` | 1:1 | 无 |
| opt: diis | `optimization/algorithm/DIIS.py`（218 行，`:20-25`） | ❌（ANCopt 无 GDIIS） | `optimize/diis.f90` | 1:1 | 无 |
| opt: rfo | `optimization/algorithm/RFO.py`（389 行，质量加权 + trust） | ⚠️ ANCopt 的 RF 步是**内坐标近似**（`src/optimizer.f90:895-927`） | `optimize/rfo.f90`（MWC，单 shift + bisection） | 1:1 | 需 Hessian 提供者（D3） |
| scan: relaxed 1D | `scan/scan.py:13`（491 行） | ✅ `src/scan_driver.f90:21 relaxed_scan` | `scan/scan1d.f90`（重写，含双向/滞回报告） | 1:1 | `constrain_pot` 有限势垒（R05 §3.8.3） |
| scan: rigid | `scan.py:159` | ❌ 无 rigid 模式（R02 §3.3） | `scan/scan1d.f90`（`mode=rigid`） | 1:1 | 无 |
| scan: 2D grid | `scan.py:380-405` | ❌ 只有 sequential/concerted（R02 §3.4） | `scan/scan2d.f90`（笛卡尔积） | 1:1 | 无 |
| ts: PRFO | `ts/algorithm/PRFO.py`（892 行，RS dual-shift） | ❌ | `saddle/prfo.f90` | 1:1 | Hessian + 选模重叠判据 |
| ts: B-PRFO(单体) | `ts/algorithm/BPRFO.py:52-80`（944 行，死代码） | ❌ | `saddle/bprfo.f90` | redesign（去批量） | 术语歧义（D2 后果） |
| ts: dimer | `ts/algorithm/dimer.py`（537 行，运行时 torch） | ❌ | `saddle/dimer.f90`（纯 Fortran） | 1:1 | 需 HVP；随机 seed |
| ts: NEB | `ts/algorithm/neb.py`（1540 行，改进切线 + 动态弹簧） | ❌ | `path/neb.f90` | 1:1 | 无（只需 E+G） |
| ts: CI-NEB | `neb.py:318-370, 789-855` | ❌ | `path/cineb.f90` | 1:1 | climbing 切换阈值 [待校准] |
| ts: AutoNEB | `ts/algorithm/autoneb.py`（1214 行，树管理） | ❌ | `path/autoneb.f90` | redesign | 无阻塞构造（R03 §E.2） |
| ts: string/GSM | `ts/algorithm/string.py`（954 行） | ❌ | `path/string.f90` | 1:1 | 无 |
| hessian (数值) | `hessian/hessian.py:11`（torch autograd，孤立） | ✅ `numhess` / `TCalculator%hessian`（step 0.005） | `types/hessian.f90` + `vib/numhess.f90` | redesign（autograd→数值） | `accu_hess=0.3` 噪声（R04 §77） |
| hessian (model 初猜) | 无（MAPLE 无模型 Hessian） | ✅ `src/model_hessian/lindh.f90`、`swart.f90`、`eeq.f90` | `types/hessian.f90`：`model` provider | 新增（xtb 独有） | 无 |
| freq/thermo | `frequency/frequency.py`（1306 行，RRHO + 低频校正） | ✅ `main_freq`（`src/main/property.F90:695`）+ `thermodyn`（`src/thermo.f90:79`） | `tasks/vib.f90` 包装（**不重写**热化学） | 1:1（复用） | 无 |
| irc: GS | `irc/algorithm/gs.py`（768 行） | ❌ | `irc/gs.f90` | 1:1 | 需 Hessian |
| irc: HPC | `irc/algorithm/hpc.py`（919 行） | ❌ | `irc/hpc.f90` + `irc/corrector.f90` | 1:1 | 需 Hessian |
| irc: EulerPC | `irc/algorithm/eulerpc.py`（964 行） | ❌ | `irc/eulerpc.f90` | 1:1 | 需 Hessian |
| irc: LQA | `irc/algorithm/lqa.py`（722 行） | ❌ | `irc/lqa.f90` | 1:1 | 谱系歧义（R04 Contradictions #3） |
| DMF | `ts/algorithm/dmf.py`（2767 行，`import cyipopt`） | — | **排除** | excl | 外部 NLP 求解器 |
| blbfgs / BPRFO 批量 | `optimization/algorithm/blbfgs.py`（535 行）、`BPRFO.py` | — | **排除** | excl | torch 批量语义 |
| parmfit | `dispatcher/parmfit/`（~40 文件） | — | **排除** | excl | 参数开发工具链 |
| MD 系综 | `dispatcher/md/`（~6000 行） | ✅ `src/mdoptim.f90`、`prog/main.F90:1153` md 分派 | **排除** | excl | xtb 已有 `md`/`omd` |

---

## 4. 总体架构

### 4.1 模块树（完整清单，每个文件都列出）

对照 R05 §3.1；表中 `★` 表示相对 R05 §3.1 的**新增文件**及原因。

```
src/landscape/
  CMakeLists.txt              # 单一构建文件（集中列出全部路径，不嵌套 subdir）
  meson.build                 # 同构
  landscape_api.f90           # 对外唯一入口
  landscape_driver.f90        # 任务分发
  types/
    settings.f90  results.f90  engine.f90  hessian.f90  updater.f90  conv.f90  log.f90
  coords/
    cartesian.f90  internal.f90  transform.f90
  tasks/
    sp.f90  opt.f90  scan.f90  ts.f90  irc.f90  vib.f90
  optimize/
    sd.f90  cg.f90  lbfgs.f90  bfgs.f90  diis.f90  rfo.f90  linesearch.f90  trust.f90
  saddle/
    prfo.f90  bprfo.f90  dimer.f90  eigenfollow.f90
  path/
    idpp.f90  neb.f90  cineb.f90  autoneb.f90  string.f90  gsm.f90
  irc/
    gs.f90  hpc.f90  lqa.f90  eulerpc.f90  corrector.f90
  scan/
    scan1d.f90  scan2d.f90  relax_scan.f90
  vib/
    numhess.f90  modes.f90  thermo.f90
```

> **M0/M1 已落地的实际文件树**（与上表模块名有差异，以本节为准；详见 §9.1/§9.2/§12.8）：
>
> ```
> src/landscape/
>   CMakeLists.txt  meson.build
>   landscape_api.f90        # xtb_landscape
>   landscape_driver.f90     # xtb_landscape_driver
>   engine/engine.f90        # xtb_landscape_engine
>   types/{settings,results,coords,log,hessian}.f90
>                             # xtb_landscape_{settings,results,coords,log,hessian}
>   tasks/{sp,opt}.f90        # xtb_landscape_sp / xtb_landscape_tasks_opt
>   optimize/{hessian_update,line_search,sd,cg,lbfgs,bfgs,diis,rfo,driver}.f90
>                             # xtb_landscape_{hessian_update,line_search,sd,cg,
>                             #   lbfgs,bfgs,diis,rfo,optimize}
> ```
>
> 差异（§12.8 D1）：无 `types/conv.f90`（判据/收敛报告并入 `settings.f90`/`results.f90`）、
> 无 `types/updater.f90`（= `optimize/hessian_update.f90`）、无 `coords/*`
> （= `types/coords.f90`）、无 `optimize/trust.f90`（并入 `rfo.f90`）。

| 目录 / 文件 | module 名 | 职责 | 依赖（仅向下） |
|---|---|---|---|
| `landscape_api.f90` | `xtb_landscape` | 公开 `run_landscape(env,mol,chk,calc,settings,result)`：唯一被 `src/prog/main.F90` 调用的符号 | `landscape_driver`, `types/settings`, `types/results` |
| `landscape_driver.f90` | `xtb_landscape_driver` | 按 `task` 字符串分派到 `tasks/*`；组装 provider/updater；计时与汇总报告 | 全部 `tasks/*`、`types/*` |
| `types/settings.f90` | `xtb_landscape_settings` | 全部 settings 派生类型 + 单位换算辅助 + `set_conv_level` | `xtb_mctc_accuracy`, `xtb_mctc_convert` |
| `types/results.f90` | `xtb_landscape_results` | result / path_result / irc_result / convergence_report 类型与打印 | `xtb_mctc_accuracy`, `xtb_mctc_io` |
| `types/engine.f90` | `xtb_landscape_engine` | 引擎边界：持有 `env/mol/wfn/calc`，缓存，`energy_gradient` / `hessian` / `hvp`，abstract `hessian_provider` 接口 + **数值实现** | `xtb_type_*`, `xtb_single`, `xtb_type_data` |
| `types/hessian.f90` | `xtb_landscape_hessian` | 具体 provider：`model`（Lindh/Swart/EEQ）、`file`（`rdhess`）；**解析扩展点即 abstract `compute`** | `xtb_landscape_engine`, `xtb_modelhessian_*`, `xtb_freq_io` |
| `types/updater.f90` | `xtb_landscape_updater` | Hessian 更新：Bofill / BFGS / Powell / SR1，强制对称化 + Powell 阻尼 | `xtb_mctc_blas`, `xtb_bfgs` |
| `types/conv.f90` ★ | `xtb_landscape_conv` | 四判据收敛测试 + 等级表；MAPLE 风格 `is_converged` 语义 | `xtb_mctc_accuracy` |
| `types/log.f90` | `xtb_landscape_log` | 轨迹/日志写入；统一调用 `xtb_io_writer::writeMolecule` | `xtb_io_writer`, `xtb_mctc_filetypes` |
| `coords/cartesian.f90` | `xtb_landscape_cartesian` | 平面化/展开约定、质量加权度规、去刚体分量、Kabsch/RMSD | `xtb_mctc_la`, `xtb_lsrmsd`, `xtb_detrotra` |
| `coords/internal.f90` | `xtb_landscape_internal` | 冗余内坐标封装（bond/angle/dihedral/linbend） | `xtb_internals_*`, `xtb_bmatrix` |
| `coords/transform.f90` | `xtb_landscape_transform` | `x↔q`、B 矩阵、`H_cart = Bᵀ H_int B`（对应 `src/optimizer.f90:1325 itochess`） | `coords/internal`, `xtb_mctc_blas` |
| `tasks/sp.f90` | `xtb_landscape_sp` | 单点：E + 可选梯度 + 报告 | `types/engine`, `types/results` |
| `tasks/opt.f90` | `xtb_landscape_tasks_opt` | 极小化任务层（组装引擎/provider、写盘、报告） | `optimize/*`, `types/*` |
| `tasks/scan.f90` | `xtb_landscape_scan` | 扫描 driver（含双向/滞回、热启动、约束残差报告） | `scan/*`, `tasks/opt`, `xtb_constrainpot` |
| `tasks/ts.f90` | `xtb_landscape_ts` | TS driver（prfo/bprfo/dimer/neb/cineb/autoneb/string） | `saddle/*`, `path/*` |
| `tasks/irc.f90` | `xtb_landscape_irc` | IRC driver（gs/hpc/lqa/eulerpc，双向，三终止信号） | `irc/*` |
| `tasks/vib.f90` | `xtb_landscape_vib` | Hessian 输出 + 调用既有 `main_freq`(`xtb_propertyoutput`, `src/main/property.F90:22`) / `thermodyn`(`xtb_thermo`, `src/thermo.f90:18`) 打印 | `vib/*`, `xtb_hessian`, `xtb_propertyoutput`, `xtb_thermo` |
| `optimize/sd.f90` | `xtb_landscape_opt_sd` | 最速下降（含相切换前段） | `types/*` |
| `optimize/cg.f90` | `xtb_landscape_cg` | PRP+ 共轭梯度（负 beta 截零 = 重启，非下降方向守卫） | `types/*` |
| `optimize/lbfgs.f90` | `xtb_landscape_lbfgs` | L-BFGS 两循环历史 | `types/*` |
| `optimize/bfgs.f90` | `xtb_landscape_opt_bfgs` | 全 BFGS（默认走 `xtb_bfgs::bfgs`，packed） | `xtb_bfgs` |
| `optimize/diis.f90` | `xtb_landscape_opt_diis` | GDIIS 外推 + Tikhonov 正则 | `xtb_mctc_lapack` |
| `optimize/rfo.f90` | `xtb_landscape_opt_rfo` | 质量加权单 shift RFO + trust region | `types/engine`, `optimize/trust`, `xtb_freq_project` |
| `optimize/linesearch.f90` | `xtb_landscape_opt_linesearch` | Armijo 回退线搜索 + `max_step` 裁剪 | `types/engine` |
| `optimize/trust.f90` | `xtb_landscape_opt_trust` | 通用 trust-region 状态机（`rho`、`eta_shrink/expand`、min/max） | `types/*` |
| `saddle/prfo.f90` | `xtb_landscape_saddle_prfo` | RS dual-shift P-RFO + 模态跟随 | `optimize/trust`, `types/*` |
| `saddle/bprfo.f90` | `xtb_landscape_saddle_bprfo` | 单体系 RS-P-RFO（alpha 可调） | 同上 |
| `saddle/dimer.f90` | `xtb_landscape_saddle_dimer` | Dimer 旋转 + 平移（Eq.13/18/21） | `types/engine`(HVP), `coords/cartesian` |
| `saddle/eigenfollow.f90` | `xtb_landscape_saddle_eigenfollow` | 选模：overlap 判据 + 符号重对齐 + 投影 | `xtb_freq_project`, `xtb_freq_utils` |
| `path/idpp.f90` | `xtb_landscape_path_idpp` | IDPP 初始路径（无能量评价） | `xtb_mctc_blas` |
| `path/neb.f90` | `xtb_landscape_path_neb` | 改进切线（Eqs.8–12）+ 动态弹簧 + 投影 L-BFGS（切线/弹簧为模块内 **private** 过程，不额外拆文件） | `types/*` |
| `path/cineb.f90` | `xtb_landscape_path_cineb` | climbing image 力 + 切换 | `path/neb` |
| `path/autoneb.f90` | `xtb_landscape_path_autoneb` | 自适应插点/分裂（`PathNode` 树） | `path/neb` |
| `path/string.f90` | `xtb_landscape_path_string` | GSM 生长 + 重参数化 | `path/neb`(公用工具), `xtb_cqpath` |
| `path/gsm.f90` | `xtb_landscape_path_gsm` | GSM 顶层（`string` 的收敛/CI 包装） | `path/string` |
| `irc/gs.f90` | `xtb_landscape_irc_gs` | Gonzalez–Schlegel pivot + 球约束 | `irc/corrector`, `types/*` |
| `irc/hpc.f90` | `xtb_landscape_irc_hpc` | LQA 预测 + DWI/mBS 校正 | `irc/corrector` |
| `irc/lqa.f90` | `xtb_landscape_irc_lqa` | 单步 LQA 传播 | `irc/corrector` |
| `irc/eulerpc.f90` | `xtb_landscape_irc_eulerpc` | Euler 预测 + DWI/mBS 校正 | `irc/corrector` |
| `irc/corrector.f90` | `xtb_landscape_irc_corrector` | DWI 面拟合 + modified Bulirsch–Stoer + LQA 解析传播（四法共享） | `types/engine`(Hessian) |
| `scan/scan1d.f90` | `xtb_landscape_scan1d` | 1D 扫描（relaxed/rigid，双向） | `tasks/opt`, `xtb_constrainpot` |
| `scan/scan2d.f90` | `xtb_landscape_scan2d` | 2D 笛卡尔积网格 + 热启动 | `scan/scan1d` |
| `scan/relax_scan.f90` | `xtb_landscape_scan_relax` | 约束松弛内核（设置 `valconstr` → 内层 opt → 去偏能量） | `tasks/opt`, `xtb_geoopt`(可选) |
| `vib/numhess.f90` | `xtb_landscape_vib_numhess` | 经 provider 取稠密 Hessian；可选 ODLR | `types/engine`, `xtb_o1numhess` |
| `vib/modes.f90` | `xtb_landscape_vib_modes` | 投影 + 质量加权 + 对角化 + 频率（**复用** `xtb_freq_project/utils`） | `xtb_freq_project`, `xtb_freq_utils` |
| `vib/thermo.f90` | `xtb_landscape_vib_thermo` | 薄封装既有 RRHO 打印（**不重写**） | `xtb_thermo`, `xtb_hessian` |

**注意（避免无效嵌套）**：`types/`、`coords/` 等目录**不放置** `CMakeLists.txt`/`meson.build`。
`src/landscape/CMakeLists.txt` 用显式相对路径列全部 47 个 `.f90`（沿用
`src/CMakeLists.txt:113-119` 列出 `model_hessian/*` 的既有风格），`meson.build` 同构，
最后 `set(srcs ${srcs} PARENT_SCOPE)`（对照 `src/freq/CMakeLists.txt:18-26`）。
理由：减少文件数、避免 CMake 变量作用域错误，且与仓库既有两种风格中的一种完全一致
（`src/CMakeLists.txt:113-119` 直接列出 `model_hessian/*`，不为该目录建子文件）。

### 4.2 依赖方向（严格单向，无环）

```
        src/prog/main.F90   (runtyp 分派)
                 │ 唯一入口
                 ▼
        xtb_landscape_api ──► xtb_landscape_driver
                                     │
        ┌────────────┬───────────────┼──────────────┬────────────┐
        ▼            ▼               ▼              ▼            ▼
     tasks/sp   tasks/opt      tasks/(scan,ts,   tasks/vib   types/results
     tasks/opt   optimize/*     irc) ─► saddle/*,  vib/*      types/settings
                       │              path/*, irc/*    │
                       └──────────────┴────────────────┴────► types/engine
                                                                   │
                                              ┌────────────────────┼──────────────┐
                                              ▼                    ▼              ▼
                                       types/hessian        coords/*        types/updater
                                              │                    │
                                              ▼                    ▼
                                 xtb_modelhessian_*      xtb_internals_*, xtb_bmatrix
                                              │
                                              ▼
        xtb 私有层: xtb_single, xtb_type_calculator/molecule/restart/environment,
                    xtb_geoopt, xtb_optimizer, xtb_bfgs, xtb_freq_*, xtb_constrainpot,
                    xtb_hessian, xtb_o1numhess, xtb_mctc_{accuracy,convert,blas,lapack,la,filetypes}
```

**规则（M0 必须在 `landscape_api.f90` 头部写明的边界）**

1. `optimize/**`、`saddle/**`、`path/**`、`irc/**`、`scan/**`、`vib/**` **只允许**
   `use xtb_landscape_*` 与 `xtb_mctc_*`；不得 `use xtb_type_molecule` / `xtb_single` /
   `xtb_optimizer` / `xtb_geoopt` / `xtb_setparam`（`types/engine.f90` 是唯一的 xtb 私有类型入口，
   `types/hessian.f90` 是唯一的 `model_hessian`/`freq_io` 入口，`coords/*` 是唯一的
   `internals`/`bmatrix`/`detrotra` 入口，`vib/*` 是唯一的 `xtb_freq_*`/`xtb_hessian` 入口）。
2. **禁止**任何模块级可变量（R01 §9.7：MAPLE 的双轨默认值正是 Fortran settings 类型要避免的坑）。
   `settings` 一律按参数对象显式传递（`type(...), intent(in)`）。
3. xtb 现有模块**不得** `use xtb_landscape_*`；唯一例外是 §12 列出的 5 处既有文件的最小改动。

### 4.3 与 xtb 私有模块的边界（可复用清单）

| 新模块要用的能力 | xtb 来源（模块 / 过程） | 边界模块 |
|---|---|---|
| 能量+解析梯度 | `xtb_single::singlepoint`（`src/single.f90:37`），形参 `(env,mol,chk,calc,egap,et,maxiter,prlevel,restart,lgrad,acc,etot,g,sigma,res)` | `types/engine.f90` |
| 数值 Hessian | `TCalculator%hessian`（`src/type/calculator.f90:103`） | `types/engine.f90` |
| 模型 Hessian | `newLindhModelHessian`/`newLindhD2ModelHessian`（`src/model_hessian/lindh.f90:41`）、`newSwartModelHessian`（`swart.f90:34`）、`add_eeq_hessian`（`eeq.f90`） | `types/hessian.f90` |
| Hessian 打包/稠密合同 | `TModelHessian%compute_packed`(`src/model_hessian/type.f90:37`)、`generic compute`(`:41`) / `compute_dense` | `types/hessian.f90` |
| Hessian 投影 | `projectHessian`(`src/freq/project.f90:34`)、`trproj`(`:151`)、`gtrprojm`(`:218`) | `saddle/eigenfollow.f90`, `vib/modes.f90` |
| 质量加权/对角化 | `massWeightHessian`(`src/freq/utils.f90:32`)、`diagHessian`(`:59`) | `vib/modes.f90` |
| 虚频模式（cold start） | `find_projected_imag_modes`（`src/o1numhess.f90:694`） | `saddle/eigenfollow.f90` |
| Hessian IO | `wrhess`/`rdhess`/`writeHessianOut`（`src/freq/io.f90:30,51,82`） | `types/hessian.f90` |
| Hessian 更新 | `bfgs`(`src/bfgs.f90:20`)、`powell`(`:105`)、`hdamp`(`:164`) | `types/updater.f90` |
| 最低本征对 | `sdavid2`/`solver_sdavidson`（`src/david2.f90:25/221`，**单精度**） | `optimize/rfo.f90`(可选) |
| 内坐标 | `redundant_type`(`src/internals/redundant.f90:41`)、`new_redundant`(`:73`)、`graph_type`(`graph.f90:33`)、`get_bmatrix`(`src/bmatrix.f90:321`)、`bmat_accum_*`(`:456,:508`) | `coords/internal.f90`, `coords/transform.f90` |
| 去平动转动 | `detrotra`(`src/detrotra.f90:18`)、`axis3`(`src/axis_trafo.f90:377`)、`rmrottr`(`src/rmrottr.f90:19`) | `coords/cartesian.f90` |
| RMSD | `xtb_lsrmsd::rmsd`（`src/ls_rmsd.f90:33`） | `coords/cartesian.f90` |
| 约束势/扫描 | `constrain_pot`(`src/constrain_pot.f90:313`)、`constrain_hess`(`:331`)、`qpothess2`(`:88`)、`relaxed_scan`(`src/scan_driver.f90:21`) | `scan/*` |
| 约束参数对象 | `xtb_type_setvar::constr_setvar`(`src/type/setvar.f90:135`)、`xtb_scanparam::constrain_all_bonds`(`src/scanparam.f90:322`，仅取 `bond_factor = 1.2` 作为连通性阈值) | `scan/*` |
| 角度/二面角约定 | `xtb_basic_geo::bangl`(`src/basic_geo.f90:502`) / `valijkl`(`:245`) | `scan/*` |
| 路径插值 | `cqpath_*`（`src/cqpath.f90:32,128,270`） | `path/string.f90` |
| 统一松弛入口 | `geometry_optimization`（`src/geoopt_driver.f90:23`） | `scan/relax_scan.f90`(可选) |
| 轨迹写入 | `writeMolecule`（`src/io/writer.f90:36`） | `types/log.f90` |
| 单位/常数 | `xtb_mctc_convert`（`src/mctc/convert.f90:25-66`） | `types/settings.f90` |
| BLAS/LAPACK | `xtb_mctc_blas`, `xtb_mctc_lapack`, `xtb_mctc_la` | 全层 |
| 错误处理 | `env%error`(`src/type/environment.f90:298`)、`env%check`(`:162`)、`env%warning`(`:324`) | 全层 |

---

## 5. 接口契约

> 本节是计划的核心。M0 的验收标准就是本节全部内容可编译、可通过单元测试。

### 5.1 抽象引擎边界

**设计目标**：算法层只见「E+G」「Hessian」「HVP」三个动作；引擎持有并全权管理
`env/mol/wfn/calc`；同一几何**绝不重复做 SCF**；给定相同输入**逐位可复现**。

```fortran
! types/engine.f90
module xtb_landscape_engine
   use xtb_mctc_accuracy, only : wp
   use xtb_type_environment, only : TEnvironment
   use xtb_type_molecule, only : TMolecule
   use xtb_type_restart, only : TRestart
   use xtb_type_calculator, only : TCalculator
   use xtb_type_data, only : scc_results
   implicit none(type, external)

   !> Restart/state policy
   integer, parameter :: p_restart_off = 0, p_restart_pin = 1, p_restart_warm = 2

   !> Immutable run-time control for one engine instance
   type :: landscape_engine_control
      real(wp) :: etemp = 300.0_wp     ! K,      SCC Fermi broadening (src/setparam.f90:233)
      integer  :: maxiter = 250        ! 1,      max SCC iterations   (src/setparam.f90:221)
      real(wp) :: acc = 1.0_wp         ! 1,      SCC convergence      (src/setparam.f90:222)
      integer  :: printlevel = 1
      logical  :: lgrad = .true.
      integer  :: restart_mode = p_restart_off
      real(wp) :: hess_step = 5.0e-3_wp ! bohr,  numerical Hessian step (src/type/setvar.f90:158)
      real(wp) :: hess_acc = 0.3_wp     ! 1,     SCC acc during Hessian (src/type/setvar.f90:156)
      real(wp) :: hvp_step = 5.0e-3_wp  ! bohr,  HVP central difference step
   end type landscape_engine_control
```

> **实测结论（R2-02，2026-10）**：`xtb_single::singlepoint`（`src/single.f90:37`）的签名虽然含
> `etemp/maxiter/acc`，但**函数体并不转发它们**，而是转调 `calc%singlepoint(env, mol, chk,
> prlevel, restart, ...)`。因此引擎控制里这三项的**真实生效路径**是：
>
> - `acc`：必须由引擎在 `engine_set_calculator` 时写入 `calc%accuracy`，并且 `xtbMain` 要把
>   CLI 解析出的 `set%acc` 同步进 `lset%engine%acc`（否则引擎会把它压回默认 1.0）；
> - `etemp`：实测 `--lopt --etemp 5000` 会改变收敛能量（`-5.070544450318` vs `-5.070544447778`），
>   生效路径是 `newXTBCalculator` 构造时的 `calc%etemp = set%etemp`（本例之外）——**不再改代码**；
> - `maxiter`：没有 CLI flag；SCC 最大迭代通过 xcontrol `$scc maxiterations=`
>   （`src/set_module.f90:1758` → `set%maxscciter`）在构造时进入 `calc%maxiter`——**不再改代码**。
>
> 修复轮只把 `acc` 接上（`src/prog/main.F90` 的 `lset%engine%acc = set%acc` + `engine_set_calculator`
> 写 `calc%accuracy`），并由 `xtb/landscape-opt-acc` 做 CLI 级回归。

**`landscape_engine_type`（字段）**

| 字段 | 类型 | 物理含义 / 单位 |
|---|---|---|
| `env` | `TEnvironment` | 错误/I/O 环境；`env%unit` 为输出流 |
| `mol` | `TMolecule` | 当前几何；`mol%xyz(3,n)` **bohr**（xtb 内部单位，`src/type/molecule.f90:53-169`） |
| `wfn` | `TRestart` | 波函数/重启状态；`copy` 方法可用（`src/type/restart.F90:48,53`） |
| `wfn_ref` | `TRestart` | 确定性参考态（构造时或 `engine_pin_state` 时快照） |
| `calc` | `class(TCalculator), allocatable` | 多态计算器（GFN0/1/2/FF/tblite/extern） |
| `ctrl` | `landscape_engine_control` | 见上 |
| `hp` | `class(landscape_hessian_provider), allocatable` | Hessian 提供者（§5.2） |
| `cache_xyz` | `real(wp), allocatable :: (:,:)` | 上次求值的几何（bohr） |
| `cache_energy`, `cache_gradient`, `cache_sigma`, `cache_hlgap`, `cache_results` | | 缓存输出 |
| `cache_valid` | `logical` | 缓存有效性 |
| `n_eval`, `n_hess`, `n_hvp` | `integer` | 计数器（用于成本报告与确定性测试） |
| `n_scf_fail` | `integer` | `results%converged == .false.` 次数 |

**公开过程（M0 全部实现）**

| 过程 | 签名要点 | 语义 |
|---|---|---|
| `new_engine(self, env, mol, wfn, calc, ctrl, hp)` | `hp` 为 `class(landscape_hessian_provider), intent(in), optional` | 深拷贝 `env/mol/wfn/calc`；`wfn_ref` 快照；`allocate(self%hp, source=hp)` 取动态类型；给出 `mol` 的**自有副本**（避免别名） |
| `engine_destroy(self)` | — | 释放所有 allocatable 分量（含 `calc`/`hp`/缓存） |
| `engine_set_xyz(self, xyz)` | `real(wp), intent(in) :: xyz(3,*)` bohr | 写入 `mol%xyz` 并**无条件失效缓存** |
| `engine_get_xyz(self, xyz)` | `intent(out)` | 读当前几何（bohr） |
| `engine_invalidate(self)` | — | 手动失效缓存 |
| `engine_pin_state(self)` | — | `call self%wfn_ref%copy(self%wfn)`：把当前波函数钉为参考态（`p_restart_pin` 用） |
| `engine_energy_gradient(self, energy, gradient, sigma, hlgap, results)` | `energy` hartree；`gradient(3,n)` hartree/bohr；`sigma(3,3)` hartree | 见下方缓存算法；SCC 未收敛 → `env%warning` + `n_scf_fail++` + `fail=.true.`，并且**不缓存、不把该 E/g 当可用值返回**（R2-03；任务层 `tasks/opt.f90` 再升级为 `env%error`） |
| `engine_hessian(self, hess, step, odlr, final_err)` | `hess(3n,3n)` hartree/bohr²（**稠密、已对称化**） | 委托 `self%hp%compute(self, hess, step, odlr, final_err)`；`n_hess++` |
| `engine_hvp(self, vec, hv, delta)` | `vec(3n)` 无量纲方向；`hv(3n)` hartree/bohr² | `hv = (g(x+δv) − g(x−δv)) / (2δ)`，δ 默认 `ctrl%hvp_step`；恢复原几何；`n_hvp++` |
| `engine_report(self, unit)` | — | 打印 `n_eval/n_hess/n_hvp/n_scf_fail`（成本证据） |

**缓存与可重复性算法（M0 必须逐条实现并被测试覆盖）**

```text
engine_energy_gradient:
    if (cache_valid .and. all(self%mol%xyz == self%cache_xyz)) then
        energy=...; gradient=...; sigma=...; hlgap=...; results=...    ! 命中缓存, n_eval 不变
        return
    end if
    if (ctrl%restart_mode == p_restart_off .or. ctrl%restart_mode == p_restart_pin) &
        call self%wfn%copy(self%wfn_ref)             ! 确定性重置
    call singlepoint(self%env, self%mol, self%wfn, self%calc, hlgap, ctrl%etemp, &
                     ctrl%maxiter, ctrl%printlevel, restart=.true., &
                     lgrad=ctrl%lgrad, acc=ctrl%acc, etot=energy, g=gradient, &
                     sigma=sigma, res=results)
    n_eval = n_eval + 1
    cache_xyz = self%mol%xyz ; ... ; cache_valid = .true.
```

关键点（写入模块头注释 + 单元测试断言）：

1. **判等是逐位相等**（`all(a == b)`），不是容差比较。理由是「同一几何不重复 SCF」的语义；
   算法若真的把坐标改了再改回来，位模式通常不同 → 会重算（安全侧）。
2. `engine_set_xyz` **无条件**失效缓存：算法可以用它强制重算（例如 NEB 更新后）。
3. `p_restart_off`（默认）：每次 E+G 前从 `wfn_ref` 重置波函数 → 与上游 issue #1378
   「restart 被隐式使用导致同几何两次梯度不同」（R04 §79）直接对抗。
   `p_restart_pin`：重置到某个被显式钉住的收敛态（用于 scan 的一致性）。
   `p_restart_warm`：保留上一状态（opt/NEB/scan 的连续点，追求速度）。
   三种模式必须在输出中**显式打印**（复现要求）。
4. `engine_hvp` 在返回前必须恢复 `mol%xyz`（否则调用者的几何被污染）；
   恢复后**再次失效缓存**（因为缓存保存的是原几何，恢复后位模式相同其实可保留；
   实现选择「保守失效」，理由：避免依赖浮点恢复的位等价性）。
5. `engine_energy_gradient` 不得修改 `ctrl`（`intent(in)`）。

### 5.2 Hessian 提供者抽象（D3）

```fortran
! types/engine.f90 —— 抽象接口（与 engine 同模块，以打破循环依赖）
   type, abstract :: landscape_hessian_provider
      character(len=:), allocatable :: name          ! 'numerical' | 'model' | 'file'
      logical :: exact = .false.                     ! 是否解析/精确 Hessian
   contains
      procedure(hessian_compute), deferred :: compute
   end type landscape_hessian_provider

   abstract interface
      subroutine hessian_compute(self, engine, hess, step, odlr, final_err)
         import :: landscape_hessian_provider, landscape_engine_type, wp
         class(landscape_hessian_provider), intent(inout) :: self
         class(landscape_engine_type),      intent(inout) :: engine
         real(wp), intent(inout) :: hess(:, :)     ! (3n,3n) hartree/bohr^2, 稠密对称
         real(wp), intent(in), optional  :: step   ! bohr, 数值差分步
         logical,  intent(in), optional  :: odlr
         real(wp), intent(out), optional :: final_err
      end subroutine hessian_compute
   end interface
```

| 具体 provider | 文件 | 里程碑 | `exact` | 实现 |
|---|---|---|---|---|
| `landscape_numerical_hessian_provider` | `types/hessian.f90` | **M0/M1** | `.false.` | **自建**中心差分：逐笛卡尔分量把 `mol%xyz` 位移 `±step`，每个位移从同一波函数（`chk` 入口快照）冷启动调 `TCalculator%singlepoint`（`prlevel=-1`）；调用前把 `calc%accuracy` 置为 `sccacc`，返回后复位（对照 `src/hessian.F90:174` 置位、`:259` 复位）；返回前对称化 `hess = 0.5*(hess+transpose(hess))`。**不**转调 `TCalculator%hessian`（理由见 `07-*.md` §4.3 与 §12.8 D2）；`odlr=.true.` 报错 |
| `landscape_model_hessian_provider` | `types/hessian.f90` | **M1（已实现）** | `.false.` | 复用 `newLindhD2ModelHessian`（`src/model_hessian/lindh.f90:41`，默认 `set%mhset%model=p_modh_old`）与 `set%mhset` 默认力常数（`src/setparam.f90:267-278`），经 `TModelHessian%compute`（`src/model_hessian/type.f90:41`）得稠密对称 Hessian；纯几何、`n_eval=0`。作为 RFO/BFGS 的**初猜**注入（`driver.f90` 的 BFGS 分支经 `bfgs%set_hessian`；RFO 本就走 `objective%hessian`）。**已在 M1 完成（R2/D3 补齐）** |
| `landscape_hessian_file` | `types/hessian.f90` | M3 | `.true.` | `rdhess`（`src/freq/io.f90:82`）读入外部 Hessian（用于 `--hess` 复用与数值基线对比） |
| 解析钩子（**预留**） | `types/hessian.f90` | ≥M3 | `.true.` | **即上面这个 abstract interface**。将来新增 `landscape_hessian_analytic`：`type, extends(landscape_hessian_provider) :: ...`，实现 `compute` 直接返回 GFN2 解析二阶导，并置 `exact=.true.`。选择 provider 的入口是 settings 的 `hessian_source` 字符串（§5.3 `THessianSettings`），驱动层用 `select case` 构造 —— **无需改动任何算法层代码**。 |

M0/M1 **不**添加空的 stub 类型（避免死代码 / 占位实现）；"预留"由抽象接口本身落实。

`hessian_source` 取值：`'numerical'`（默认）、`'model'`（M1 起）、`'file'`（M3 起）；
未识别的取值 → `call env%error("unknown hessian source: "//src, source)` + 返回（不 `stop`）。

### 5.3 各任务 settings 派生类型（字段 / 单位 / 默认值）

单位约定：**长度 bohr、能量 hartree、力 hartree/bohr、Hessian hartree/bohr²、
质量 amu、频率 cm⁻¹、温度 K、压力 kPa、IRC 步长 bohr·amu^1/2**。
内部一律 a.u.；仅在 I/O 边界用 `xtb_mctc_convert`（`aatoau/autoaa/autokcal/autokj/autorcm`，
`src/mctc/convert.f90:25-42`）转换。

#### 5.3.1 `TConvSettings`（公共收敛判据，四判据）

四判据定义严格对齐 MAPLE（`optimization/algorithm/_common.py:74-89`，R01 §3.1）：
`max_f = max|g_i|`（i 遍历 3N 个分量）、`rms_f = sqrt(Σg_i²/(3N))`、
`max_dp = max|Δx_i|`、`rms_dp = sqrt(ΣΔx_i²/(3N))`。
**注意 `rms` 的分母是 3N（每分量），不是 N（每原子）** —— 改动会改变收敛步数（R03 §C.7）。

| 字段 | 单位 | 默认 | 含义 |
|---|---|---|---|
| `level` | — | `'normal'` | 等级名（映射下表） |
| `f_max` | hartree/bohr | 3.0e-4 | 最大力分量 |
| `f_rms` | hartree/bohr | 1.0e-4 | RMS 力 |
| `dp_max` | bohr | 4.0e-3 | 最大位移分量 |
| `dp_rms` | bohr | 2.0e-3 | RMS 位移 |
| `e_chg` | hartree | 5.0e-6 | 能量变化（与四判据 **AND**，对照 xtb `normal` 的 ethr，`src/optimizer.f90:48-119`） |
| `max_iter` | — | 256 | 最大迭代（对照 MAPLE `max_iter=256`） |

等级表（`set_conv_level(self, name)`）：

| level | f_max | f_rms | dp_max | dp_rms | 出处 |
|---|---|---|---|---|---|
| `superloose` | 4.6e-3 | 3.0e-3 | 7.9e-3 | 5.2e-3 | MAPLE superloose 换算（8.5e-2/5.5e-2 Ha/Å；1.45e-1/9.5e-2 Å） |
| `loose` | 2.0e-3 | 5.0e-4 | 1.0e-2 | 7.0e-3 | ORCA 6.1 Table 4.1 Loose（R04 §64） |
| **`normal`（默认）** | 3.0e-4 | 1.0e-4 | 4.0e-3 | 2.0e-3 | ORCA 6.1 Table 4.1 Normal |
| `tight` | 1.0e-4 | 3.0e-5 | 1.0e-3 | 6.0e-4 | ORCA 6.1 Table 4.1 Tight |
| `vtight` | 3.0e-5 | 8.0e-6 | 2.0e-4 | 1.0e-4 | ORCA 6.1 Table 4.1 VeryTight |

**与 MAPLE 的差异及理由**

| 项 | MAPLE | 本计划 | 理由 |
|---|---|---|---|
| 等级命名 | extratight/tight/medium/loose/extraloose/superloose（`dispatcher.py:154-195`） | ORCA 五档 | MAPLE 的 medium≈ORCA loose、tight≈ORCA normal 附近，一一对应会造成误导；直接用 ORCA 命名 + 数值更可审计 |
| 单位 | Å、Ha/Å | bohr、Ha/bohr | D1：内部 a.u.；强制在 settings 层换算，禁止算法层出现 Å |
| `default` 等级 | `medium`（fallback） | `normal` | `normal` 的 f_rms=1.0e-4 Ha/bohr = 5.3e-5 Ha/Å，比 MAPLE medium（1.9e-3 Ha/Å）紧 36 倍。理由：GFN2 梯度噪声尚未量化（R04 §9#4），初期取偏紧值并在 §8 实验 #4 后回填 |
| 能量判据 | 无 | `e_chg=5e-6` | xtb 侧有 `ethr`（`src/optimizer.f90:48-119`）；作为 **AND** 附加判据可防止在噪声平台上的抖动判收敛 |

> `[待校准]`：`normal` 的四个阈值在 M4（TS）与 M6（IRC）之前必须由 §8 实验 #2/#4 复核；
> 若 xtb 梯度噪声 σ_g > f_rms/10，则 `normal` 对 TS/IRC 不可达，届时把 TS/IRC 默认降为 `loose`（否则迭代数爆炸）。

#### 5.3.2 `TDriverSettings`

| 字段 | 单位 | 默认 | 含义 |
|---|---|---|---|
| `task` | — | `'opt'` | `sp\|opt\|scan\|ts\|irc\|hessian\|freq` |
| `verbose` | — | 1 | 0=静默，1=每步一行，≥2=每步全量 |
| `engine` | `landscape_engine_control` | §5.1 | 引擎控制 |
| `conv` | `TConvSettings` | §5.3.1 | 收敛判据 |
| `hessian_source` | — | `'numerical'` | `numerical\|model\|file`（§5.2） |
| `out_xyz` | — | `''`（自动命名） | 最终几何输出路径 |
| `out_traj` | — | `''`（自动命名） | 轨迹输出路径 |
| `write_traj` | — | `.true.` | 是否写轨迹 |
| `traj_every` | — | 1 | 每 N 步写一帧 |
| `prefix` | — | `'xtb'` | 输出文件名前缀 |

#### 5.3.3 `TSpSettings`

| 字段 | 单位 | 默认 | 含义 / 对照 |
|---|---|---|---|
| `write_gradient` | — | `.false.` | 打印梯度（MAPLE `SPParams.verbose=1` 的行为，`sp/sp.py:9`） |
| `grad_threshold` | hartree/bohr | 0.0 | 仅打印 ‖g‖ > 阈值的分量；0.0 = 全部打印 |
| `write_hessian` | — | `.false.` | 附带 Hessian（走 provider） |

#### 5.3.4 `TOptSettings`（M1 主体）

| 字段 | 单位 | 默认 | 物理含义 | 对照 / 理由 |
|---|---|---|---|---|
| `method` | — | `'lbfgs'` | `sd\|cg\|lbfgs\|bfgs\|diis\|rfo` | MAPLE `optimization.py:17-33` 仅 `lbfgs/rfo/sd/sdcg`；本计划把 cg/bfgs/diis 显式化（MAPLE 把 CG/DIIS 藏在 SDCG 内，`SDCG.py:34-57`） |
| `memory` | — | 5 | L-BFGS 历史长度 | MAPLE `LBFGSParams.memory=5` |
| `curvature` | — | 70.0 | 回退 H0 的曲率下限 | MAPLE 同值 |
| `max_step` | bohr | 3.7795e-1 | 单步最大位移 | MAPLE `max_step=0.2 Å` |
| `sd_enabled` | — | `.true.` | 先做 SD 相 | MAPLE `SDCGParams` |
| `sd_max_iter` | — | 50 | SD→CG 切换的最迟步 | MAPLE 同值 |
| `cg_switch_fmax` | hartree/bohr | 0.0 | 0 = auto（0.5×初始 max_f） | MAPLE 语义（`SDCG.py:459-468`） |
| `cg_beta_method` | — | `'prp+'` | PRP+ 且负值截零 | MAPLE `cg_beta_method="prp+"`。**本轮不提供该设置**：PRP+ 是本套件支持的唯一 beta，负值截零就是重启机制（§12.8 D5） |
| `cg_restart_threshold` | — | 0.2 | CG 重启判据 | MAPLE 同值。**本轮不实现该设置**：Powell 对齐判据在 Armijo-only 线搜索下使 CG 退化为 SD（实测，§12.8 D5）|
| `diis_enabled` | — | `.true.` | 启用 GDIIS | MAPLE 同值 |
| `diis_memory` | — | 6 | DIIS 向量数 | MAPLE `DIISParams.memory=6` |
| `diis_store_every` | — | 5 | 存快照间隔 | MAPLE 同值 |
| `diis_min_snapshots` | — | 3 | 最少快照数 | MAPLE `DIISParams.min_vectors=3` |
| `diis_regularization` | — | 1.0e-10 | Tikhonov 正则 | MAPLE 同值 |
| `trust_init` | bohr | 3.7795e-1 | RFO 初始 trust radius | MAPLE `RFO.RFOParams.trust_radius_init=0.2 Å` |
| `trust_min` | bohr | 1.8897e-3 | 最小 trust radius | MAPLE `1e-3 Å` |
| `trust_max` | bohr | 1.8897 | 最大 trust radius | MAPLE `1.0 Å` |
| `eta_shrink` | — | 0.75 | 拒绝步的半径收缩因子 | MAPLE 同值（`RFO.py:295-304`） |
| `eta_expand` | — | 1.75 | 接受步的半径扩张因子 | MAPLE 同值 |
| `evals_eps` | — | 1.0e-10 | 本征值分母保护 | MAPLE 同值 |
| `mu_margin` | — | 1.0e-8 | shift 与 min(w) 的间隔 | MAPLE 同值 |
| `max_bisect_it` | — | 60 | shift 二分上限 | MAPLE 同值 |
| `recalc` | — | **5** | 每 N 步重算精确 Hessian（RFO 用） | MAPLE `RFO` 每步重算（`RFO.py:193-201`）；本计划取 5：数值 Hessian 每次 = 6N 次单点，`recalc=1` 会让 RFO 每步付 6N+1 次单点（R2-07） |
| `linesearch` | — | `'armijo'` | 线搜索类型 | MAPLE 无显式线搜索（靠 trust radius）；新增后仍受 `max_step` + trust 双重限制 |
| `max_backtrack` | — | 10 | Armijo 回退上限 | 新增；防无限回退 |
| `armijo_c1` | — | 1.0e-4 | Armijo 常数 | 标准值（Nocedal & Wright, *Numerical Optimization* 2006, Alg. 3.1） |

#### 5.3.5 `TScanSettings`

| 字段 | 单位 | 默认 | 含义 / 对照 |
|---|---|---|---|
| `mode` | — | `'relaxed'` | `relaxed\|rigid`（MAPLE `scan.py:14-17`） |
| `method` | — | `'lbfgs'` | 内层优化器（MAPLE `method="lbfgs"`） |
| `ndim` | — | 1 | 1 或 2（D2 要求；MAPLE scan 支持 1–3，但 3D 无实用价值 → 本计划只做 1–2） |
| `coord(i)%ctype` | — | `'distance'` | `distance\|angle\|dihedral` |
| `coord(i)%atoms(4)` | — | 0 | 1-based 原子编号（**从 1 开始**，MAPLE 输入 1-based 但内部 `a-1`，`scan.py:83`） |
| `coord(i)%step` | bohr / rad | 0.0 | 步长（距离 bohr，角 rad；用户输入可用 Å/度，边界换算） |
| `coord(i)%nstep` | — | 0 | 步数 |
| `bidirectional` | — | `.true.` | 正反双向扫描并报告滞回（**新增**，理由见 R04 §4.6 失效模式 1） |
| `sequential` | — | `.true.` | ndim=1 时用 sequential 语义；ndim=2 时改为笛卡尔积网格 |
| `warm_start` | — | `.true.` | 每个扫描点从前一点几何热启动（R04 §4 工程建议 (b)） |
| `spring_expo` | — | 2.0 | 约束势指数，**仅对 distance 生效**：xtb `constrain_pot` 中角度用 `fc·(θ−θ0)²`、二面角用 `fc·(1−cos(φ−φ0))`，`expo` 只进入距离项（`src/constrain_pot.f90:196-212, 253-258, 282-312`）。二面角这一**有界**周期形式在 Δφ = 180° 处**恢复力矩为零**（仅在 90° 处达到最大值 `fc`，势垒上界 `2fc`），因此被转坐标接近反式时的实际刚度远小于名义 `fc`——这是“二面角扫描比距离扫描更容易漂移”的原因，也是 spring_expo 对它无效的直接后果（实测见 `docs/_landscape-recon/14-m2-validation-experiments.md` §4.2） |
| `constraint_fc` | hartree/bohr²（距离）或 hartree（角/二面角） | 0.5 | 约束力常数。**0.5 不是 xtb 既有默认值**：`src/scanparam.f90:77` 实测为 `fcconstr = 0.05_wp`（初版计划此处误读，M2 复核实测更正，见 `docs/_landscape-recon/14-m2-validation-experiments.md` §4）。保留 0.5 的理由：有限弹簧势会让约束坐标产生系统偏移，实测（1,2-二氯乙烷二面角，GFN2，24° 网格，`normal` 档）fc=0.05 时最大偏移 6.84°、势垒 2.731 kcal/mol；fc=0.5 时 0.82° / 2.864 kcal/mol；fc≥2 收敛到 0.04° / 2.873 kcal/mol（极限值），即 fc=0.5 的势垒误差 0.33%、fc=0.05 为 4.9%。要与既有 `--scan`（`xtbscan.log` 工具链）逐点对齐时显式使用 `--lscan-fc 0.05` |

#### 5.3.6 `TTsSettings`（含子块）

公共字段：

| 字段 | 单位 | 默认 | 含义 / 对照 |
|---|---|---|---|
| `method` | — | `'prfo'` | `prfo\|bprfo\|dimer\|neb\|cineb\|autoneb\|string` |
| `conv` | — | `normal` | 见 §5.3.1；MAPLE 的 PRFO 用 `loose` 量级（9.5e-3/5e-3 Ha/Å），可用 `--lts level=loose` 复现 |
| `verify_ts` | — | `.true.` | 收敛后做一次频率确认（虚频个数 == 1） |
| `verify_hess_source` | — | `'file'` | 确认用的 Hessian（M4 起） |

**P-RFO / B-P-RFO 子块（`TPrfoSettings`）**

| 字段 | 单位 | 默认 | 对照 / 理由 |
|---|---|---|---|
| `trust_init` / `trust_min` / `trust_max` | bohr | 3.7795e-1 / 1.8897e-3 / 1.8897 | MAPLE `PRFOParams.trust_radius=0.2, trust_min=1e-3, trust_max=1.0`（Å） |
| `eta_shrink` / `eta_expand` | — | 0.75 / 1.75 | MAPLE 同值 |
| `max_attempts` | — | 8 | MAPLE `PRFO.py:820-834` |
| `evals_eps` / `mu_margin` / `max_bisect_it` | — | 1e-10 / 1e-8 / 60 | MAPLE 同值 |
| `recalc` | — | 1 | MAPLE `recalc=1`（每步精确 Hessian）；pysisyphus 建议 1–5（R04 §27） |
| `hessian_update` | — | `'bofill'` | MAPLE 默认；pysisyphus 明说 "Should not be modified for TS optimizations"（R04 §27） |
| `target_mode` | — | 1 | 跟随第几个负模（1-based，对应 xtb `tsroot` 语义空缺，`src/setparam.f90:501`） |
| `alpha` | — | 0.5 | uphill/downhill 子空间 trust 分配比例（MAPLE `alpha∈[0.05,0.95]`，`PRFO.py:140-351`） |
| `max_micro_cycles` | — | 50 | RS 变体的 micro 迭代（pysisyphus 默认，R04 §27） |
| `mode_overlap_min` | — | 0.3 | 模式跟随守卫：`\|Vᵀ·v_tracked\| < 该值` → 重新选模并告警（**新增**，防 R03 §C.4 的模态跳变） |
| `bprfo_delta_alpha` | — | 0.05 | bprfo 的 alpha 自适应步（**新增**） |

**Dimer 子块（`TDimerSettings`）**

| 字段 | 单位 | 默认 | 对照 / 理由 |
|---|---|---|---|
| `delta` | bohr | 1.8897e-2 | Henkelman 的 dimer separation ΔR=1e-2 Å（R04 §30）；**注意定义歧义**（VASP 的 DdR 是两像间距，pysisyphus 的 length 是中点到像，R04 Contradictions #1）→ 本计划取「中点→像」（与 pysisyphus 一致），文档中写明 |
| `hvp_step` | bohr | 5.0e-3 | HVP 差分步；MAPLE `delta=0.005 Å = 9.45e-3 bohr`（`dimer.py:105-139`），差异理由：与 xtb `step_hess` 一致便于审计 |
| `rot_max_iter` | — | 5 | MAPLE 同值 |
| `rot_alpha` | — | 0.5 | MAPLE 同值 |
| `rot_f_max_th` / `rot_f_rms_th` | hartree/bohr | 5.29e-4 / 2.65e-4 | MAPLE `rot_f_max_th=1.0e-3, rot_f_rms_th=5.0e-4`（Ha/Å）换算 |
| `step0` | bohr | 3.7795e-1 | MAPLE `step0=0.2 Å` |
| `step_max` | bohr | 2.8346e-1 | MAPLE `step_max=0.15 Å` |
| `trust_radius` | bohr | 2.8346e-1 | MAPLE 同值 |
| `kappa_to_flip` | — | 0.0 | MAPLE 同值（`dimer.py:105-139`）；曲率判据 C<0（R04 §29 Eq.21） |
| `use_mass_weight` | — | `.false.` | MAPLE 同值 |
| `remove_rigid` | — | `.true.` | MAPLE 同值 |
| `n_init` | — | `'random'` | `random\|force`（MAPLE 另有 `given`，M4 只做前两种以避免输入格式膨胀） |
| `seed` | — | 42 | **新增，强制**：MAPLE `dimer.py:258` 用无种子的 `default_rng()`（R03 §C.6），Fortran 侧必须可复现 |

**NEB / CI-NEB 子块（`TNebSettings`）**

| 字段 | 单位 | 默认 | 对照 / 理由 |
|---|---|---|---|
| `n_images` | — | 10 | MAPLE `NEBParams.n_images=10` |
| `k_min` / `k_max` | hartree/bohr² | 2.083e-3 / 2.083e-2 | MAPLE `0.03/0.3`，其单位在 MAPLE 文档中缺失；本计划按 ASE 惯例（eV/Å²）换算（0.03 eV/Å² = 2.083e-3 Eh/bohr²；ASE 默认 `k=0.1 eV/Å` 落在该区间，参 R04 §42）`[待校准]` |
| `use_dynamic_k` / `k_decay` | — | `.true.` / 0.5 | MAPLE 同值；公式见 §6.4 |
| `ifidpp` | — | 1 | MAPLE 默认；IDPP 见 R04 §47 |
| `lbfgs_m` | — | 20 | MAPLE 同值 |
| `step0` | bohr | 3.7795e-2 | MAPLE `2e-2 Å` |
| `band_f_rms_avg` | hartree/bohr | 1.736e-3 | geomeTRIC 0.025 eV/Å（R04 §46）换算 |
| `band_f_rms_max` | hartree/bohr | 3.472e-3 | geomeTRIC 0.05 eV/Å |
| `climb_switch_rms` | hartree/bohr | 3.472e-2 | geomeTRIC `--climb 0.5` eV/Å；`[待校准]` 由实验 #8 定 |
| `climb` | — | `.true.` | CI-NEB 默认开启（R04 §45：CI 修正 NEB 低估约 0.4 eV） |
| `refine` | — | `''` | `''\|cineb\|nebts`（MAPLE `refine=None`） |
| `remove_rotation_and_translation` | — | `.true.` | ASE 非周期默认（R04 §39） |

**AutoNEB 子块（`TAutoNebSettings`）**

| 字段 | 单位 | 默认 | 对照 |
|---|---|---|---|
| `n_images` | — | 20 | MAPLE `AutoNEBParams.n_images=20` |
| `ang_max` / `ang_iter` / `path_iter` | — | 0.3 / 20 / 50 | MAPLE 同值 |
| `min_e_drop` | hartree | 3.6749e-5 | MAPLE `0.001`（eV）换算 |
| `ep_iter` / `ep_e_drop` | — / hartree | 30 / 1.8375e-5 | MAPLE 30 / 0.0005 eV |
| `max_depth` / `max_paths` | — | 5 / 10 | MAPLE 同值 |
| `do_final_refine` / `final_refine_factor` / `final_refine_max_iter` | — | `.true.` / 2.0 / 200 | MAPLE 同值 |

**String/GSM 子块（`TStringSettings`）**

| 字段 | 单位 | 默认 | 对照 / 理由 |
|---|---|---|---|
| `grow_step` / `grow_step_min` | bohr | 2.2677e-1 / 3.7795e-2 | MAPLE `0.12/0.02 Å` |
| `grow_backtrack` | — | 0.5 | MAPLE 同值 |
| `grow_relax_iters` | — | 10 | MAPLE 同值 |
| `grow_relax_frms` | hartree/bohr | 1.323e-3 | MAPLE `grow_relax_tol=2.5e-3`（Ha/Å）换算 |
| `merge_threshold` | — | 0.5 | MAPLE 同值 |
| `n_images` | — | 9 | MAPLE 9；pysisyphus `max_nodes=9`（R04 §50）共同点 |
| `reparam_every` | — | 3 | MAPLE 同值 |
| `perp_thresh` | — | 0.05 | pysisyphus `perp_thresh=0.05`（R04 §50） |
| `string_f_max` / `string_f_rms` | hartree/bohr | 2.646e-3 / 5.29e-4 | MAPLE 5e-3/1e-3 Ha/Å 换算 |
| `cistring_f_max` / `cistring_f_rms` | hartree/bohr | 2.117e-3 / 1.058e-3 | MAPLE 4e-3/2e-3 Ha/Å 换算 |

#### 5.3.7 `TIrcSettings`

| 字段 | 单位 | 默认 | 含义 / 对照 |
|---|---|---|---|
| `method` | — | `'gs'` | `gs\|hpc\|lqa\|eulerpc` |
| `target_mode` | — | 1 | 起点模式（1-based，对应 MAPLE `target_mode=1`） |
| `step_length` | bohr·amu^1/2 | 0.10 | MAPLE `step_length_bohr=0.10`；Gaussian `IRC=StepSize` 默认 0.10（R04 §67）；**推荐区间 0.05(tight)–0.40(HPC)** |
| `max_steps` | — | 50 | MAPLE `max_steps=50` |
| `max_micro_cycles` | — | 20 | GS 专用（MAPLE 同值） |
| `micro_step_thresh` | — | 1.0e-3 | GS 微循环收敛（MAPLE 同值） |
| `euler_n` | — | 5000 | LQA/HPC 预测子步（Hratchian & Schlegel Eq.10，R04 §8） |
| `max_pred_steps` | — | 500 | EulerPC 预测步上限（MAPLE 同值） |
| `loose_cycles` | — | 3 | EulerPC（MAPLE 同值） |
| `hessian_recalc` | — | -1 | -1 = 从不重算（MAPLE `hessian_recalc=None`）；正数 = 每 N 步重算 |
| `hessian_update` | — | `'bofill'` | EulerPC 论文实测用 Bofill（R04 §17） |
| `dwi_n` / `mbs_max_k` / `mbs_points` | — | 4 / 15 / 20 | MAPLE 同值 |
| `mbs_tol` | bohr·amu^1/2 | 1.0e-5 | MAPLE 同值；HPC 论文的 mBS 接受阈值 1e-6 a.u. 更严（R04 §8） |
| `forward` / `backward` | — | `.true.` / `.true.` | 双向 |
| `e_rise_steps` | — | 3 | 终止信号 (c)：能量连续回升 N 步判定已过极小点（R04 §20） |
| `rmsd_end` | bohr | 1.8897e-1 | 用于报告「落在哪个极小点」（RMSD 到优化后的 R/P） |
| `conv` | — | `normal` | MAPLE 用 `f_max=2e-3, f_rms=5e-4`（Ha/Å）→ 1.058e-3/2.646e-4 Eh/bohr |

#### 5.3.8 `THessianSettings` 与 `TVibSettings`

| 字段 | 单位 | 默认 | 对照 / 理由 |
|---|---|---|---|
| `source` | — | `'numerical'` | 见 §5.2；`numerical\|model\|file` |
| `step` | bohr | 5.0e-3 | xtb `step_hess`（`src/type/setvar.f90:158`）；MAPLE 用 0.002 Å（`calculator_base.py:355`），差异理由：xtb 对齐 + 与 §8 实验 #2 的基线一致 |
| `sccacc` | — | 0.3 | xtb `accu_hess`（`src/type/setvar.f90:156`）。**显式暴露**，理由：R04 §77 指出 0.3 是人工放宽的精度，直接决定虚频稳定性 |
| `odlr` | — | `.false.` | ODLR 近似（`src/o1numhess.f90:71`），大体系用 |
| `project_tr` | — | `.true.` | 投影平动/转动（Eckart，R04 §71） |
| `linear_tol` | — | 1.0e-8 | 线性分子判定（3N-5 vs 3N-6） |
| `temperature(50)` | K | 298.15, 其余 0 | 沿用 xtb `thermotemp`（`src/setparam.f90:283`） |
| `pressure` | kPa | 101.325 | RRHO 参考压力 |
| `rotor_cutoff` | cm⁻¹ | 50.0 | xtb `thermo_sthr`（`src/setparam.f90:285`） |
| `imag_cutoff` | cm⁻¹ | -20.0 | xtb `thermo_ithr`（`src/setparam.f90:287`） |
| `freq_scal` | — | 1.0 | xtb 官方推荐 1.0（R04 §73） |
| `ilowfreq` | — | 2 | Grimme 低频熵方案（MAPLE `FrequencyParams.ilowfreq=2`） |

**取舍说明**：`freq` 任务**不重写**热化学。`vib/thermo.f90` 只做「把 settings 拷进
`set%thermoset` → 调既有 `main_freq`/`thermodyn`」，因为 xtb 已具备完整 RRHO + 对称数
+ 低频校正（R02 §4.3，`src/thermo.f90:79`）。本套件对 `freq` 的**增量价值**是：
(a) 把 Hessian 作为可复用中间量暴露给 TS/IRC（provider 语义）；
(b) 把 `step`/`sccacc`/`odlr` 提升为显式可调参数。

### 5.4 结果类型与收敛报告

```fortran
! types/results.f90
type :: landscape_convergence_report
   integer :: n_iter = 0
   character(len=:), allocatable :: level
   logical :: converged(4) = .false.     ! f_max, f_rms, dp_max, dp_rms
   real(wp), allocatable :: history_energy(:), history_gnorm(:)
   real(wp), allocatable :: history_f_max(:), history_f_rms(:)
   real(wp), allocatable :: history_dp_max(:), history_dp_rms(:)
   real(wp), allocatable :: history_trust(:)
   integer,  allocatable :: history_method(:)  ! 1=sd,2=cg,3=lbfgs,4=bfgs,5=diis,6=rfo,7=prfo,...
end type

type :: landscape_result
   integer  :: status = 0          ! 0=converged, 1=max_iter, 2=stagnated, <0=error
   real(wp) :: energy = 0.0_wp     ! hartree
   real(wp) :: gnorm = 0.0_wp      ! hartree/bohr (Euclidean norm of gradient)
   real(wp) :: f_max = 0.0_wp, f_rms = 0.0_wp          ! hartree/bohr
   real(wp) :: dp_max = 0.0_wp, dp_rms = 0.0_wp        ! bohr
   real(wp) :: egap = 0.0_wp       ! hartree
   integer  :: n_eval = 0, n_hess = 0, n_hvp = 0, n_scf_fail = 0
   real(wp), allocatable :: xyz(:,:)        ! (3, natoms) bohr
   real(wp), allocatable :: gradient(:,:)   ! (3, natoms) hartree/bohr
   type(landscape_convergence_report) :: conv
end type
```

| 类型 | 关键字段 | 用于 |
|---|---|---|
| `landscape_path_result` | `n_images`; `xyz(3,n,n_images)` bohr; `energy(n_images)` hartree; `e_barrier` hartree; `ts_image`; `spline_node(n_images)` | scan / NEB / CI-NEB / AutoNEB / string |
| `landscape_saddle_result` | `result`（`landscape_result`）+ `n_imag`; `imag_freq(nimag)` cm⁻¹; `mode(3n)`（跟随的模式，符号已对齐） | prfo/bprfo/dimer |
| `landscape_irc_result` | `n_fwd`,`n_bwd`; `xyz_fwd(3,n,n_fwd)`,`xyz_bwd(3,n,n_bwd)`; `e_fwd(n_fwd)`,`e_bwd(n_bwd)`; `s_fwd(n_fwd)`,`s_bwd(n_bwd)`; `reached_min_fwd/bwd`; `rmsd_to_min_fwd/bwd` | irc |
| `landscape_vib_result` | `freq(n)` cm⁻¹（虚频为负）; `modes(3n,3n)`; `zpe` hartree; `n_imag`; `linear` | hessian/freq |
| `landscape_cost_report` | `n_eval`,`n_hess`,`n_hvp`,`n_scf_fail`,`wall_seconds` | 全部（性能证据） |

`status` 语义固定：`0` 收敛；`1` 达 `max_iter`；`2` 停滞（连续 N 步无改善，N=`stagnate_patience`，默认 10）；
`<0` 错误（`env%error` 已记录，调用者 `return`）。

### 5.5 日志与轨迹输出约定

全部轨迹经 `writeMolecule(mol, unit, fileType%xyz, energy=, gnorm=, number=)`
（`src/io/writer.f90:36`）写出；几何为 **Å**（xyz 格式约定），能量 `hartree`，`gnorm` 打印用 `hartree/bohr`。

| 任务 | 文件 | 内容 | 备注 |
|---|---|---|---|
| 全部 | stdout（`env%unit`） | 分节头（`generic_header` 风格）+ 每步一行 `iter / E / gnorm / f_max / dp_max / trust / method` | 与 `relaxation_engine` 现有表格风格一致 |
| opt | `xtbopt.xyz` | 最终优化几何 | **沿用现有命名**（`src/prog/main.F90:1129-1136`） |
| opt | `xtbopt.log` | 每步轨迹 | 沿用现有命名 |
| opt | `xtb.trj` | 轨迹（`fileType%trj` 语义） | 沿用现有命名 |
| scan | `xtbscan.log` | 每帧几何 + `energy=Etot−Efix`（去偏能量） | **沿用现有**（`src/scan_driver.f90:98,129`）；新 driver 仍写该名以保证兼容。**几何被丢弃的扫描点不写帧**（既无能量，几何也可能是未评估的零帧）；此时 stdout 表里该行能量为 `NaN`、`conv = F`，文件以 `status='replace'` 打开以免残留上一次运行的帧 |
| scan | `xtbscan_2d.xyz`（ndim=2 时） | 网格帧（comment 带两个坐标值） | 新增 |
| ts (prfo/bprfo/dimer) | `xtbts.xyz`（最终 TS）、`xtbts.log`（轨迹） | 几何 + `n_imag` | 新增 |
| ts (neb/cineb/autoneb/string) | `path.xyz` | `n_images` 帧，comment 含 `energy` 与帧号 | 与 R05 §3.4 一致 |
| ts (autoneb) | `path_autoneb.xyz`、`path_ts_list.xyz` | 全局 MEP 与所有局部 TS | 新增 |
| irc | `irc_forward.xyz`、`irc_backward.xyz`、`irc_path.xyz`、`irc.log` | 单向前/后路径、合并路径（按弧长排序，能量最高点标 `TS`）、逐点表 | `irc_path.xyz` 与 MAPLE `inp1_full.xyz` 对应（R03 §D） |
| hessian/freq | `vibspectrum`、`vib_normal_modes`、`g98.out`、`hessian` | 沿用 `src/freq/io.f90` 既有输出 | **不新增重复文件** |
| 全部 | `landscape_<task>.json`（可选，`--ljson`） | `status/counters/conv history` 结构化输出 | 便于回归比对 |

**统一规则**：所有文件在 `env%unit` 打印一次
`wrote <filename>`；文件句柄用 `open_file`/`close_file`（xtb 既有 `filetools`），
失败 → `env%error`（不 `stop`）。

**缺失值的表示（M2 复核轮确定）**：能量/梯度被引擎丢弃的量化值一律以 **NaN**
表示（`xtb_landscape_settings::landscape_missing_value`），**不得**写成 `0.0`：
`0.0` 是一个完全可信的能量值（剖面里一个 `0.0` 点会在脚本中静默存活），而 NaN 会被
任何 `isnan`/比较检查抓住。规则与实测（同一剖面里 `0.0` 与 `-5.07 Eh` 相邻）见
`docs/_landscape-recon/14-m2-validation-experiments.md` §5.3 与 `16-m2-fix-report.md`。

---

## 6. 算法清单与出处

> 每条给出：文献、关键公式/参数、失效模式、防护措施。公式取自 R04（其证据等级已在 R04 标注）。

### 6.1 极小化（M1）

| 算法 | 文献 | 关键参数 | 失效模式 | 防护 |
|---|---|---|---|---|
| 最速下降 (SD) | — | `max_step=0.37795 bohr` | 病态方向振动，收敛极慢 | 仅作启动相；`sd_max_iter=50` 后切换 |
| 共轭梯度 (PRP+) | Polak–Ribière 1969；Gilbert & Nocedal 1992（PR+） | `beta=max(g_k·(g_k−g_{k−1})/‖g_{k−1}‖², 0)`；非下降方向 → 重启为 `-g` | 非二次性导致方向失效 | 负 beta 截零（= 重启）+ 非下降方向守卫 + 每步 `max_step` 裁剪；**不**用 Powell 对齐重启（§12.8 D5） |
| L-BFGS | Nocedal 1980；MAPLE `LBFGS.py:61-84` | `m=5`；`gamma=y·s/y·y`；`curvature=70` | 曲率对 `y·s≤0` 时 Hessian 近似破坏 | `y·s ≤ 1e-12` → 丢弃该对（`LBFGS.py:92-102`）；`max_step` 裁剪 |
| 全 BFGS | Broyden/Fletcher/Goldfarb/Shanno 1970；xtb `src/bfgs.f90:20` | `hdamp` Powell 阻尼 | 负曲率发散 | **强制 Powell 阻尼**（`src/bfgs.f90:164 hdamp`）；强制对称化 |
| GDIIS | Császár & Pulay 1984；Farkas & Schlegel PCCP 2002 | `memory=6`；Tikhonov `1e-10` | 线性依赖 → 病态 B 矩阵 | 增广 `[B,-1;-1,0]` + 正则（`DIIS.py:70-127`）；`min_vectors=3` 前不启用 |
| RFO（单 shift + trust） | Banerjee 1985；Baker 1986；pysisyphus §7（R04 §24） | 解增广本征问题；`μ < min(w)` 由二分求 | 近简并小本征值 → 巨大步 | `evals_eps=1e-10` 分母保护；`trust_max=1.889 bohr` 硬上限；`rho<eta_shrink` 拒绝并收缩 |
| 线搜索 | Nocedal & Wright 2006, Alg. 3.1 | Armijo `c1=1e-4`，`max_backtrack=10` | 噪声 PES 上回退失败 | 回退耗尽 → 接受最小步 + `stagnate` 计数 |
| 收敛判定 | MAPLE `_common.py:74-89` | 四判据 AND | 只判能量/梯度 → 假收敛 | §5.3.1 四判据 + `dp_*` |

### 6.2 Scan（M2）

| 算法 | 文献/依据 | 关键点 | 失效模式 | 防护 |
|---|---|---|---|---|
| relaxed scan | Gaussian 语义上等价于「带 Lagrange 乘子的约束优化」（R04 §56） | 每点：设 `valconstr` → 内层 `tasks/opt` → 去偏能量 `Etot−Efix` | (1) 滞回/灾变点（R04 §60.1）；(2) SCF 解不连续 → fake/missing saddle（R04 §60.2）；(3) 扫描坐标定义漂移（R04 §60.3） | (a) `bidirectional=.true.` 并显式报告滞回；(b) 每点热启动；(c) 报告约束残差；(d) `restart=p_restart_pin` 固定波函数 |
| rigid scan | xtb 无此模式（R02 §3.3）；MAPLE `scan.py:159` | 刚体移动内坐标（距离/角/二面角）后单点 | 拉伸/弯曲耦合导致几何失真 | 默认 `relaxed`；rigid 仅作快速粗扫，输出中标注 `mode=rigid` |
| 2D grid | MAPLE `scan.py:380-405` | 笛卡尔积 + 逐行热启动 | 网格点跨 basin | 逐行热启动 + 检查相邻点能量跳变 > `max_jump`（默认 0.5 hartree）时告警 |

### 6.3 TS 优化（M4）

**P-RFO（双 shift，ORCA 6.1 §4.3.1 / Baker 1986，R04 §21）**

```
E      = E0 + gᵀ Δq + ½ Δqᵀ H Δq                          (4.16)
Δq_k   = −(F_k V_k)/(b_k − λ_p),   F_i = V_iᵀ g           (4.18a,4.19)
λ_p    = ½ b_k + ½ sqrt(b_k² + 4 F_k²)                    (4.18a)
Σ_{i≠k} F_i²/(λ_n − b_i) = λ_n    （迭代求解，需 λ_n < 0） (4.18b)
Δq_i   = −(F_i V_i)/(b_i − λ_n),  i ≠ k                   (4.19)
Δq     = Σ_j Δq_j                                         (4.20)
```

| 失效模式 | 防护 |
|---|---|
| Newton 步滑到最近极小点（ORCA §4.3.1 原文，R04 §22） | 双 shift 强制「恰有一个负本征值」的目标驻点 |
| Hessian 有 >1 个负本征值 | 按 ORCA 做法平移/反号对角元（R04 §21）；本计划的实现：`b_i → max(b_i, hlow)` 并记录 |
| 模态切换（mode hopping） | **overlap 判据**：`idx = argmax\|Vᵀ v_tracked\|` + 符号重对齐 `sign = sign(overlap)`（PRFO.py:634-672，R03 §C.4）；`mode_overlap_min=0.3` 时重新选模并 `env%warning` |
| 近平简小本征值 → 巨大步 | `evals_eps` 保护 + trust radius（ORCA 会替换小本征值，属社区 lore，R04 §36，仅作参考） |
| trust radius 过大进入错误 basin | pysisyphus 建议 `trust ≤ 0.1`、`trust_max 0.3–0.5`（R04 §38）；本计划据此提供 `--lts trust=0.1` 快捷档 |
| 数值噪声使力判据不可达 | 紧 SCF（`p_restart_off`）+ 实验 #4 定阈值 |

**B-PRFO（单体系 RS-P-RFO）**：与上式相同，差别在 trust radius 的**子空间划分**
（`alpha` 把总半径分给 uphill/downhill 两个子空间）与最多 `max_micro_cycles=50`
的 micro 迭代；不依赖批量张量。参见 D2 后果中的术语解释。

**Dimer（Henkelman & Jónsson 1999，R04 §29-32）**

| 公式/参数 | 防护/说明 |
|---|---|
| `C = [(F2−F1)·N̂]/(2ΔR) = (E2−E0)/(ΔR)²` (Eq.2) | 曲率符号决定平移方向（Eq.21） |
| 旋转角 `Δθ = −½ arctan(2F0/F0')` (Eq.13，优于 Eq.6) | `F→0, F'→0` 极限更稳（原文） |
| 平移力 `F† = F_R − 2F∥`（C<0）；`F† = −F∥`（C>0）(Eq.21) | quick-min / CG 传播，`step_max` 限制 |
| `ΔR = 1e-2 Å`、`δθ = 1e-4 rad`、`dR = 1e-3 Å`（原文算例，R04 §30） | 本计划 `delta` 取 1.8897e-2 bohr（中点→像，与 pysisyphus 定义一致，R04 Contradictions #1） |
| **VASP 诊断规则**：Torque 不下降 ⇒ 受力精度不足，应降 EDIFF 或增大 DdR（R04 §31） | 移植为运行时诊断：若 `rot_max_iter` 用尽而 `rot_f_rms > rot_f_rms_th`，`env%warning("dimer rotation did not converge; consider increasing delta or tightening SCF")` |
| 随机初始方向 | `seed` 显式传入；`n_init='force'` 用最大梯度分量方向作为确定性替代 |

**GSM/String、NEB、CI-NEB、AutoNEB、IDPP** 见 §6.4。

**TS 起点与刚性投影**：
- 初始模式方向：`find_projected_imag_modes`（`src/o1numhess.f90:694`）或
  Hessian 对角化后的最负模；投影用 `projectHessian`/`trproj`（`src/freq/project.f90:34,151`）。
- **过渡向量相位固定**（R04 §35）：定义 forward 方向 = 过渡向量最大分量为正时其指向；
  输出中打印该最大分量与原子编号，便于复现（对应 Gaussian `Phase=(N1,N2,...)` 语义）。
- 平移/转动投影：Cartesian 步 **投影**（`projectHessian`）；`remove_rigid=.true.` 默认。

### 6.4 Chain-of-states（M5）

| 算法 | 文献 | 关键公式/参数 | 失效模式 | 防护 |
|---|---|---|---|---|
| 改进切线 NEB | Henkelman & Jónsson, JCP **113**, 9978 (2000) Eqs.8–12 | 能量单调性 upwind；极值点加权平均；改进弹簧用**标量距离差** | 朴素切线导致 kink 与路径抖动 | 用 Eq.12 弹簧（原 Eq.5 已知次优，R04 §41） |
| 动态弹簧 | ORCA 风格，MAPLE `neb.py:214-281` | `k_i = k_max − (k_max−k_min)·exp(−decay·ΔE_i/ΔE_max)` | k 过大妨碍收敛（VASP 警告，R04 Contradictions #2） | `k_max=2.083e-2 Eh/bohr²`，`use_dynamic_k=.true.` |
| CI-NEB | Henkelman/Uberuaga/Jónsson, JCP **113**, 9901 (2000) Eq.5 | `F_max = −∇E + 2(∇E·τ̂)τ̂`；最高点不受弹簧力 | 过早点火导致能量曲线失真 | 先跑常规 NEB，`band_f_rms_max < climb_switch_rms` 后再切 CI；`[待校准]` 实验 #8 |
| IDPP 初始路径 | Smidstrup et al., JCP **140**, 214106 (2014) | 对距离插值的目标面做 NEB，**无需能量评价** | 线性插值产生间断（原文） | `ifidpp=1` 默认 |
| AutoNEB | Kolsbjerg/Groves/Hammer, JCP **145**, 094107 (2016)；勘误 JCP **148**, 029903 (2018) | 逐步建路 + 在几何/能量分辨率最差处插点 | 树管理复杂 → 资源超支 | `max_paths=10`、`max_depth=5` 硬上限 |
| GSM/String | Peters/Heyden/Bell/Chakraborty, JCP **120**, 114101 (2004) Eqs.1,7,9 | 法向力 `f⊥ = −∇V + (τ̂ᵀ∇V)τ̂`（Eq.1）；生长指示 `i(f⊥)=1 if \|f⊥\|≤tol`（Eq.7）；`a1(k+1)=a1(k)+Δs·i(·)`（Eq.9） | 节点间距过小产生 kink | 间距条件 `R > \|∇V·τ̂\|/(2ν₂)`（原文）；切线用三次样条（`cqpath_spline_repos`，`src/cqpath.f90:32`） |
| 收敛 | geomeTRIC | 所有图像 `g_RMS` 的平均与最大都达标（R04 §46） | 用单点判据会在一条不良图像上假收敛 | 用 `band_f_rms_avg` + `band_f_rms_max` 双判据 |
| Kabsch/对齐 | MAPLE `neb.py:55` | 每步去转动平移 | 路径漂移 | `remove_rotation_and_translation=.true.` |

### 6.5 IRC（M6）

统一约定（R04 §1.1、§67）：**质量加权 Cartesian，1 a.u. 沿路径 = 1 bohr·amu^1/2**；
`dx(s)/ds = −g(x)/|g(x)|`（Hratchian & Schlegel, JCP **120**, 9918 (2004), Eq.1）。

| 方法 | 文献 | 更新式 / 参数 | 失效模式 | 防护 |
|---|---|---|---|---|
| GS | Gonzalez & Schlegel, J. Phys. Chem. **94**, 5523 (1990) Eqs.8–10 | pivot `q*_{k+1} = q_k − ½ s N G g_k`，`N = (gᵀGg)^{-1/2}`；再在半径 `s/2` 球面上约束优化 | micro 循环不收敛（强弯曲路径/大 step，R04 §7）；每点 3–5 次 E/g | `max_micro_cycles=20`、`micro_step_thresh=1e-3`；球约束本身在步长过大时能把点拉回真实路径附近（原文） |
| LQA | Page & McIver, JCP **88**, 922 (1988)（R04 §12）；QSD 形式见 Eckert & Werner, Theor. Chem. Acc. **100**, 21 (1998) Eq.6 | 二阶泰勒解析传播，`euler_n=5000` 子步 | **强弯曲路径上振荡并大幅偏离 MEP**（R04 §13）；0.20 步长"轻微困难"，0.40 失控 | 步长默认 0.10，`tight` 档 0.05；文档中**明确写清用的是哪一支推导**（R04 Contradictions #3 的谱系歧义） |
| HPC | Hratchian & Schlegel JCP **120**, 9918 (2004) Eqs.2–11 | 预测：`x(t)=x0+A(t)g0`，`a_ii(t)=(e^{−λ_i t}−1)/λ_i`；校正：DWI 面 + modified Bulirsch–Stoer（简单 Euler，非 modified midpoint），接受阈值 1e-6 a.u.；每点仅 1 次 E/g；步长可到 0.40 | 校正失败（DWI 导数不可信，semi-implicit mBS 被判不可行） | `mbs_max_k=15`、`mbs_points=20`、`mbs_tol` 可调；失败 → 回退到 GS 一步并告警 |
| EulerPC | Meisner & Kästner JCP **133**, 224101 (2010) Eqs.2–4 | 预测：`x̃_{i+1} = x_i − (g_i/\|g_i\|)·s`；校正：同 HPC 的 DWI + mBS；**一阶方法**（log-log 斜率 2.016） | 0.20 步长下"无法跟随路径"（原文） | 默认 0.10；`loose_cycles=3` 允许先粗后细；误差 ~O(step) ⇒ 需要更密点 |
| Hessian 沿路径 | EulerPC 论文统一用 **Bofill** 更新，并测试每 2/5/10 步用解析 Hessian 替换（R04 §17） | `hessian_update='bofill'`、`hessian_recalc=-1` | 纯更新在长时间积分后漂移 | 提供 `hessian_recalc=N`；Bofill 更新后强制对称化 |
| 端点终止 | 无统一标准（R04 §19） | 三信号：(a) `max_steps`；(b) `\|g\|` 低于阈值；(c) 能量连续回升 `e_rise_steps` 步 | 「落在哪个极小点」不可知 | 输出 `rmsd_to_min_fwd/bwd`（RMSD 到优化后的 R 与 P），并在日志中标注终点归属 |

### 6.6 Hessian 与频率（M3）

| 项 | 参数 | 失效模式 | 防护 |
|---|---|---|---|
| 数值 Hessian | 中心差分，`step=5.0e-3 bohr`（`src/type/setvar.f90:158`） | 步长过小 → 相减抵消误差；过大 → 非谐振污染 | `step` 可调；§8 实验 #2 扫 `{0.002, 0.005, 0.010}` |
| Hessian 的 SCF 精度 | `sccacc=0.3`（`src/type/setvar.f90:156`） | **半收敛 SCF 直接注入 Hessian 噪声**，虚频与低频模漂移（R04 §77） | 显式暴露 `sccacc`；默认沿用 xtb，但文档与实验中给出收紧选项（0.1/1.0） |
| 对称化 | xtb 既有做法 `h(jj,ii)=0.5*(h(ii,jj)+h(jj,ii))`（`src/hessian.F90:291` 附近） | 不对称 → `dsyev` 结果无意义 | provider 返回前强制对称化（§5.2） |
| 投影 | Eckart 投影去平动/转动（R04 §71） | 未投影 → 6 个伪零频污染模式判定 | `project_tr=.true.` + `projectHessian`/`trproj` |
| 线性分子 | 3N-5 内自由度 | 频率计数错、转动配分函数错 | `linear_tol` + 复用 xtb `linear` 标志（`src/type/data.F90:111`）；§8 实验 #12 |
| 频率缩放 | xtb 推荐 1.0（R04 §73） | 盲目套用文献缩放因子 → 热化学不一致 | 默认 `freq_scal=1.0` 并打印 |
| 热化学 | RRHO + 转子 cutoff 50 cm⁻¹ + 虚频 cutoff −20 cm⁻¹（`src/setparam.f90:285,287`） | 低频模熵发散 | 复用 `thermodyn` 的 quasi-RRHO（`src/thermo.f90:79`）；沿用 xtb 默认 |

### 6.7 Hessian 更新族（M1）

| 更新 | 文献 | 适用 | 防护 |
|---|---|---|---|
| BFGS | 1970 四家 | 极小化 | **Powell 阻尼**（`src/bfgs.f90:164 hdamp`），`y·s>0` 检查 |
| Powell | Powell 1971 | TS 优化（xtb `tsopt` 已用，`src/optimizer.f90:341-344`） | 对称化 |
| Bofill | Bofill 1994/1995 | **路径/TS 的共识默认**（pysisyphus 明说不要改，R04 §27） | 对称化 + 分母保护 |
| SR1 | Murtagh–Sargent 1970；Conn–Gould–Toint 2000 | 不定 Hessian | 分母 `\|y·s\|` 与 `\|sᵀ(H−…)s\|` 双阈值守卫；接近零则跳过更新 |
| 通用要求 | — | — | 更新后**强制对称化**；协方差/曲率异常 → `env%warning` + 跳过 |

---

## 7. 数值卫生规范

> 可执行 checklist，取自 R03 §C。**每条都是 code review 的阻断项**（blocker）。

| # | 规则 | 理由 / 出处 |
|---|---|---|
| N1 | 每个新模块首行 `use xtb_mctc_accuracy, only : wp`，且 `implicit none(type, external)` | xtb 强制双精度（`cmake/CMakeLists.txt:50` `-fdefault-real-8`；`src/mctc/accuracy.f90:31` `wp = dp`）。`implicit none(type, external)` 是新模块的既有风格（`src/model_hessian/type.f90:31`） |
| N2 | 数值表达式禁止裸字面量：一律 `_wp` 后缀；禁止裸 `real` / `real*8` / `double precision` | R03 §C.1；若编译配置缺 `-fdefault-real-8`，裸 `real` 会退化为单精度 |
| N3 | 所有数组下标 **1-based**；与 MAPLE 对照时显式标注 `±1` 转换点 | R03 §C.2（MAPLE `scan.py:83` 有 `a-1`） |
| N4 | 扁平化一律 `xyz(3, n)`（展平顺序 `x1,y1,z1,x2,…`，与 numpy 的 `reshape(-1)` 一致）；**禁止 `xyz(n,3)`** | R03 §C.3（最大语义坑） |
| N5 | 二维矩阵声明为 `(dim, n)`；`matmul`/`dgemm` 用列主序语义；转置必须显式 `transpose()` | R03 §C.3 `.T` 落点表 |
| N6 | 一律用 `xtb_mctc_blas` / `xtb_mctc_lapack` / `xtb_mctc_la` 包装，**禁止**直接 `call dgemm/dsyev` | R02 §6.5；`src/mctc/blas.f90:19`、`lapack.f90:19`、`linalg.f90:18` |
| N7 | 特征值求解后**显式声明升序约定**；模式追踪必须 `argmax\|overlap\| + sign realign` | LAPACK `dsyev/dsyevd` 与 `np.linalg.eigh` 都是升序（R03 §C.4）；符号对齐见 `PRFO.py:634-672` |
| N8 | 单位在**模块头注释**声明；内部统一 a.u.（bohr, hartree, amu）；边界转换只用 `xtb_mctc_convert` | R03 §C.5（MAPLE 内联常数散落 + 精度不一致：`627.509` vs `627.509474`）；xtb 常数见 `src/mctc/convert.f90:25-42` |
| N9 | 与 MAPLE 逐位比对**不可行**：xtb `autoaa=0.52917726` vs MAPLE `0.529177210903`；`autokcal=627.50947428` vs `627.509474` | R03 §C.5；只做物理量级/拓扑一致性比对 |
| N10 | 随机数必须显式 `seed`（`random_seed` 先设，再 `random_number`）；**唯一允许的随机使用点是 dimer 初始方向** | R03 §C.6（MAPLE `dimer.py:258` 无种子） |
| N11 | 收敛判据固定为四判据，`rms` 分母 = **3N（每分量）** | R03 §C.7 |
| N12 | 除零/开方/对数前必须有守卫（`abs(x) > tiny` / `max(x, eps)`）；Hessian 更新强制对称化；BFGS 必须 Powell 阻尼 | 任务硬约束 + 6.7 节 |
| N13 | 错误处理统一 `call env%error(...)` + `call env%check(fail)`（`src/type/environment.f90:298,162`）或返回 `logical fail`；**禁止 `stop` / `error stop`** | R02 §7.6 |
| N14 | **禁止 module 级可变量**；settings 通过参数对象显式传递 | R01 §9.7（MAPLE 双轨默认值教训） |
| N15 | 所有 `allocate` 配 `deallocate`；所有 `intent` 显式；`intent(in)` 的参数不得被写入 | 仓库既有风格 |
| N16 | 每个 module / type / 公开过程都要 `!>` 文档注释：物理意义、单位、算法、参考文献 | 任务硬约束；风格见 `src/type/molecule.f90` 头部 |
| N17 | 浮点判等仅允许用于「同一几何」缓存命中（§5.1）；数值判等一律走容差参数 | §5.1 |
| N18 | 新增代码不得改动 `set%` 的既有语义；需要新开关时用 `landscape` 自己的 settings；只有 §12 列出的 5 处既有文件可被修改 | D1 + 最小改动约束 |

---

## 8. 测试策略

### 8.1 三层测试

| 层 | 目标 | 载体 | 判据 |
|---|---|---|---|
| **L1 纯数学**（解析势） | 验证优化器/鞍点/路径/IRC 的**算法正确性**，与 GFN2 无关 | `test/unit/landscape_*.f90`，用 `TlandscapeAnalyticEngine`（测试内定义的 `extends` 引擎 + 内置解析势） | 步序列、收敛速度、最终点几何与解析解一致；**逐位可复现** |
| **L2 xtb 引擎集成** | 验证引擎边界：确定性、缓存、Hessian 对称性、成本计数 | `test/unit/landscape_engine.f90` 等，用真实 `TxTBCalculator`（H2O、CH3OH、HCN） | 多次调用能量逐位相同；`n_eval` 与预期一致；Hessian 对称误差 < 1e-14 |
| **L3 端到端回归** | 验证任务链与输出文件 | `test/unit/landscape_e2e.f90` + `ctest`（`test/unit/CMakeLists.txt:95-96` 自动 `add_test`） | H2O：`opt → freq` 的频率与 `--hess` 一致（容差）；HCN↔HNC：`ts → irc` 两端落到正确极小 |

**L1 的解析势选择**（R03 §E.3、§D 的强验证替代方案）：
- 2D：**Müller–Brown 面**（含 2 个极小 + 1 个鞍点，解析梯度/Hessian）→ PRFO、dimer、NEB、string、IRC 全部可逐点验证。
- 高维：**LEPS 势**（H + H₂）→ 3 原子、解析梯度/Hessian、已知 TS 几何与势垒 → 用于 NEB/CI-NEB/IRC 的定量比对。
- 线性：**CO₂ / 乙炔**（3N-5）→ 频率计数与 Eckart 投影。
**理由**：MAPLE 的 fixture 全部基于 ML 势（R03 §D），不能作为 GFN2 数值基准，也无法逐位比对。

### 8.2 去风险实验（R04 §9 的 12 项）

`Gate` 列 = 必须在哪个里程碑**之前**完成；`承担测试` 列 = 由哪个测试文件负责。

| # | 实验 | Gate | 承担测试 | 产出 |
|---|---|---|---|---|
| 1 | xtb 反复调用确定性（同几何连续 N 次 `singlepoint`；`restart=off` vs 复用 `TRestart`） | **M0 完成前** | `test_landscape_engine.f90` | 位相等结论 + 若不等的差异量级（Eh/bohr）；决定 `p_restart_off` 是否为默认（本计划已默认 off） |
| 2 | Hessian 步长 × sccacc 敏感度（H2O/CH3OH，step∈{0.002,0.005,0.010}、sccacc∈{0.3,0.1,1.0}） | **M3 完成前** | `test_landscape_vib.f90` | 频率/最小本征值/虚频个数漂移表；回填 `THessianSettings` 默认 |
| 3 | `etemp`（0/300/1000/5000 K）对最低 3 个本征值的影响 | **M4 之前** | `test_landscape_vib.f90` + `test_landscape_saddle.f90` | 若显著，则 TS/IRC 冻结 `etemp` 并写入输出 |
| 4 | 梯度噪声 σ_g vs trust radius 下确界 | **M4 / M5 / M6 之前** | `test_landscape_engine.f90`（σ_g）+ `test_landscape_saddle.f90`（阈值） | 给出力阈值可达下限；回填 `TConvSettings.normal` 与 `TTsSettings`(`[待校准]`) |
| 5 | P-RFO 模态跟随 vs Sella/pysisyphus(+xtb) 交叉验证（SN2、HCN→HNC、Diels–Alder） | M4 期间 | `test_landscape_saddle.f90` | 收敛代数、TS 几何 RMSD、虚频个数与数值 |
| 6 | IRC 四算法互校（同 TS 跑 forward+backward） | M6 期间 | `test_landscape_irc.f90` | 端点几何/能量/归属极小点；显著偏差者在文档中降级 |
| 7 | IRC 端点判据标定（对照 Gaussian `MaxPoints=10` / ORCA `MaxIter=20`） | M6 期间 | `test_landscape_irc.f90` | 三终止信号阈值标定 |
| 8 | CI-NEB climbing 切换阈值（0.5 eV/Å 是否会被噪声误触发） | **M5 之前** | `test_landscape_path.f90` | `climb_switch_rms` 定值；同时校准 `k_min/k_max`（`[待校准]`） |
| 9 | DMF 可行性 | **不执行**（D2 已排除） | — | 记录为 `not-applicable` |
| 10 | DL-FIND 复用性（法律 + 技术） | M0 之前（已完成） | — | R05 §1.1：DL-FIND 为 LGPL-3.0 与 xtb 兼容，但架构（回调式 + HDLC + MPI task-farm）与 `TCalculator` 差异大，**不搬运代码，只借鉴设计**（R05 §1.1.2 末） |
| 11 | rigid vs relaxed scan 滞回量化（二面角双向） | M2 期间 | `test_landscape_scan.f90` | 正/反向 E(q) 最大差异与不连续点；决定 `bidirectional` 默认（本计划已默认 true） |
| 12 | 线性分子 / 3N-5（CO₂、乙炔） | **M3 之前** | `test_landscape_vib.f90` | 频率计数、Eckart 投影、转动配分函数正确性 |

### 8.3 测试命名与注册

- 文件：`test/unit/test_landscape_<area>.f90`，module `test_landscape_<area>`，导出 `collect_landscape_<area>`。
- 注册两处（与现有 `test_hessian` 完全同构）：
  - `test/unit/CMakeLists.txt:22-55` 的 `tests` 列表加 `landscape-engine`、`landscape-settings`、
    `landscape-conv`、`landscape-optimize`（M0/M1）；M2–M6 依次加 `landscape-scan`、
    `landscape-vib`、`landscape-saddle`、`landscape-path`、`landscape-irc`。
  - `test/unit/main.f90:22-53` 加 `use test_landscape_engine, only : collect_landscape_engine` 等，
    并在 `testsuites = [...]` 中追加 `new_testsuite(...)`。
  - `test/unit/meson.build:34-66` 的 `tests` 列表同步（无法在本机验证，见 §10 R-16）。
- 命名风格对齐现有：`new_unittest("single-atom-ancopt", test_single_atom_ancopt)`（R02 §7.5）。
- **ctest 测试名必须全局唯一**：`xtb/<suite>` 形式的单元套件名与 CLI 测试名撞名时，
  CMake 会**静默丢掉先注册的那一个**。M2 曾把 CLI 冒烟测试也叫 `xtb/landscape-scan`，
  导致 23 个 scan 单元用例从未在 ctest 下跑过（在 `test/unit/CTestTestfile.cmake` 里
  只剩 `cmake -P` 那一行）；M2 复核轮把 CLI 测试改名为 `xtb/landscape-scan-cli`。
  新增测试后用 `ctest -N -R landscape` 核对名字与数量。

---

## 9. 分阶段里程碑 M0–M7

依赖关系：`M0 → M1 → M2 → M3 → M4 → M5 → M6 → M7`；
`M3` 依赖 `M1`（复用 `types/updater`）；`M4` 依赖 `M3`（初始 Hessian provider）；
`M5` 只依赖 `M1`（可与 M3/M4 并行）；`M6` 依赖 `M3`（Hessian）+ `M4`（TS 起点）。

### 9.1 M0（已实现）：骨架 + 引擎边界 + 类型 + 构建接入 + 测试骨架

> 状态图例：**✅ 已交付**；**🔁 合并**（并入其它文件，见 §12.8 差异 D1）；
> **❌ 未交付**。行数为实现后的实际行数（`wc -l`）。

| 文件 | LOC 实/估 | 交付内容 | 状态 |
|---|---|---|---|
| `src/landscape/types/settings.f90` | 525 / 350 | 任务 settings 基类（四判据、`engine`、`hessian_source`、`task()` 绑定）+ `landscape_opt_settings` + `landscape_sp_settings` + `set_conv_level` + 名字↔标识符表 | ✅ 已交付 |
| `src/landscape/types/results.f90` | 289 / 150 | `landscape_step`、`landscape_result`、`landscape_convergence_report` + 打印 | ✅ 已交付 |
| `src/landscape/engine/engine.f90` | 693 / 400 | `landscape_engine` + `landscape_engine_control` + `landscape_energy_model`（解析势注入）+ 缓存/计数器/`hvp`/restart 三态 | ✅ 已交付 |
| `src/landscape/types/conv.f90` | — / 120 | 四判据 `is_converged` + `landscape_convergence_measures` | 🔁 合并进 `types/settings.f90`（判据）与 `types/results.f90`（收敛报告） |
| `src/landscape/types/log.f90` | 93 / 140 | 轨迹/最终几何写入（`writeMolecule` 封装，`<prefix>opt.xyz` / `<prefix>.trj`） | ✅ 已交付 |
| `src/landscape/tasks/sp.f90` | 181 / 120 | `landscape_single_point`（E + 可选梯度报告 + 可选 Hessian） | ✅ 已交付 |
| `src/landscape/landscape_api.f90` | 77 / 130 | `run_landscape(env, mol, chk, calc, set, res)`（对 `main.F90` 唯一入口） | ✅ 已交付 |
| `src/landscape/landscape_driver.f90` | 107 / 150 | 按 `settings%task()` 分派 `tasks/*`、PBC 守卫、收尾一行汇总 | ✅ 已交付 |
| `src/landscape/CMakeLists.txt` | 44 / 40 | 全部路径 + `PARENT_SCOPE` | ✅ 已交付 |
| `src/landscape/meson.build` | 44 / 30 | 同构（本机无 meson，见 R-16） | ✅ 已交付 |
| `test/unit/test_landscape_settings.f90` | 390 / 180 | 默认值逐项断言 + `set_conv_level` 全档 + 名字↔标识符往返 | ✅ 已交付 |
| `test/unit/test_landscape_conv.f90` | — / 120 | 四判据边界（恰好等于阈值、`rms` 分母 3N） | 🔁 合并进 `test_landscape_settings.f90`（`convergence-boundary`、`convergence-measures`） |
| `test/unit/test_landscape_engine.f90` | — / 260 | 缓存/计数器/Hessian 对称/HVP 恢复/`off` vs `warm` | 🔁 合并进 `test_landscape_optimize_math.f90`（`engine-cache`、`engine-hvp`）与 `test_landscape_optimize_xtb.f90`（determinism 探针） |

**M0 验收测试**
1. `ctest -R landscape` 全绿（见 §12.9 实跑输出）；
2. **构建真实通过**：`cmake -S . -B /tmp/xtb-land/build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON -DCMAKE_BUILD_TYPE=Release` + `cmake --build`（见 §10 环境约束）；
3. 现有 `test/unit` 无回归（`ctest -R 'landscape|api'` + CLI 冒烟全绿）；
4. `xtb --help` / `xtb --version` 仍正常（`xtb/Argparser_print_help`、`xtb/Argparser_print_version` 全绿）；
5. 代码审查：N1–N18 checklist（`engine%ctrl%hessian_source` 已删除，见 §12.8 D3）。

**M0 实际 LOC ≈ 2400（实现 + 测试骨架）。**

### 9.2 M1（已实现）：极小化器 + 更新公式 + 线搜索 + 统一 driver

| 文件 | LOC 实/估 | 交付内容 | 状态 |
|---|---|---|---|
| `src/landscape/optimize/hessian_update.f90` | 294 / 300 | `update_bofill`/`update_bfgs`(Powell 阻尼)/`update_powell`/`update_sr1`，强制对称化 + 分母守卫 | ✅ 已交付 |
| `src/landscape/types/hessian.f90` | ~390 / 220 | abstract `landscape_hessian_provider` + 自建中心差分 `landscape_numerical_hessian_provider` + **已实现** `landscape_model_hessian_provider`（Lindh-D2 初猜）+ `hessian_source` 工厂；provider 的 `n_eval` 计入引擎成本计数 | ✅ 已交付（模型 Hessian 本体已在 M1 补齐，见 §12.8 D4） |
| `src/landscape/optimize/sd.f90` | 47 / 130 | SD 步（位移裁剪由 driver 统一完成） | ✅ 已交付 |
| `src/landscape/optimize/cg.f90` | 167 / 250 | PRP+ CG（负系数截零 + 非下降方向重启） | ✅ 已交付（Powell 对齐重启未采用，见 §12.8 D5） |
| `src/landscape/optimize/lbfgs.f90` | 180 / 260 | L-BFGS 两循环 + 动态 `gamma` + 曲率过滤 | ✅ 已交付 |
| `src/landscape/optimize/bfgs.f90` | 158 / 180 | 稠密 BFGS（谱分解求步 + `hlow` 抬升） | ✅ 已交付 |
| `src/landscape/optimize/diis.f90` | 201 / 220 | GDIIS + Tikhonov 正则 + 快照管理 | ✅ 已交付 |
| `src/landscape/optimize/rfo.f90` | 235 / 320 | 质量加权单 shift RFO + bisection + trust 钳位 | ✅ 已交付 |
| `src/landscape/optimize/trust.f90` | — / 200 | trust-region 状态机 | 🔁 合并进 `rfo.f90`（`landscape_rfo_update_trust`） |
| `src/landscape/optimize/line_search.f90` | 131 / 180 | Armijo 回退 + 位移裁剪 | ✅ 已交付 |
| `src/landscape/optimize/driver.f90` | 497 / — | 纯数学内核 `landscape_optimize_model`（算法分派 + 四判据 + 停滞检测 + 轨迹缓冲） | ✅ 已交付（M1 未在 §9.2 中列出，见 §4.2 分层） |
| `src/landscape/tasks/opt.f90` | 205 / 260 | 任务级 driver：组装引擎/provider、调用内核、写盘、报告 | ✅ 已交付 |
| `test/unit/test_landscape_optimize_math.f90` | 533 / 420 | 解析势（谐振子/Rosenbrock/Müller–Brown）上的 sd/cg/lbfgs/bfgs/diis/rfo 收敛 + 缓存/HVP/线搜索开关/Hessian provider 接线 | ✅ 已交付 |
| `test/unit/test_landscape_optimize_xtb.f90` | 261 / — | GFN2 水分子极小化、输出文件、确定性探针（`off` 逐位可复现） | ✅ 已交付 |
| `test/unit/landscape_testpot.f90` | 351 / — | 解析测试势（M6 的 351 行 `testpot.f90` 已从 `libxtb` 移出） | ✅ 已交付 |
| `test/unit/test_landscape_cg.f90` | 252 / — | CG 方向复现 + 两条重启路径 + 强凸二次型步数对比 | ✅ 已交付 |
| `test/unit/test_landscape_hessian.f90` | 318 / — | `hessian_source` 分派 + 未识别取值报错 + 自建 FD Hessian 与 `TCalculator%hessian` 逐点对比 | ✅ 已交付 |
| `test/unit/test_landscape_api.f90` | 216 / — | `run_landscape` 的 `sp`/`opt` 分派、未知任务与 PBC 拒绝 | ✅ 已交付 |

**M1 验收测试**：同 M0 的 1–5，外加
「`--lopt` 端到端：`xtb h2o.xyz --lopt --lopt-engine lbfgs --lopt-level normal` 收敛并写 `xtbopt.xyz` + `xtb.trj`」
（`ctest -R landscape` 中的 `xtb/landscape-opt`，见 §12.9），
以及「`--lopt` 不改变既有 `--opt` 的行为（回归）」：`ctest -R 'Singlepoint|IP|GFN'` 全绿。

**M1 实际 LOC ≈ 2700（实现 + 测试）。**

### 9.3 M2（已实现）：Scan

| 模块 | 文件 | LOC 实/估 | 状态 |
|---|---|---|---|
| 约束松弛内核 | `scan/relax_scan.f90` | 1139 / 300 | ✅ 已交付（含 rigid 片段守卫 + drift 判据 + 回绕函数） |
| 1D | `scan/scan1d.f90` | 473 / 350 | ✅ 已交付 |
| 2D | `scan/scan2d.f90` | 363 / 320 | ✅ 已交付 |
| 任务 driver | `tasks/scan.f90` | 352 / 180 | ✅ 已交付 |
| 测试 | `test/unit/test_landscape_scan.f90` | 2098 / 400 | ✅ 已交付（27 个 case） |

交付物：`--lscan`；`xtbscan.log` 兼容输出；双向扫描 + 滞回报告；约束残差报告。
**M2 验收测试**：`ctest -R landscape` 25/25 全绿（其中 `xtb/landscape-scan` 含 27 个 case）；+ `ctest -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'` 12/12 无回归。
验收（M2 复核轮改写为可达到的形式；三项 MEDIUM 于终轮修完，见 `docs/_landscape-recon/18-m2-final-fix-report.md`）：

1. 实验 #11（滞回量化）：relaxed 双向扫描的滞回随收敛档收紧单调下降（默认档 12° 网格实测 5.63e−6 Eh）；
2. 1D/2D 网格点计数与**坐标正确性**（分模式，均可证伪）：
   - **rigid**：`wrapped(reached − target) == 0`（构造是纯几何的，容差 1e−8 bohr / 1e−8 rad，即点级运行期判据 `xtb_landscape_scan_relax::rigid_drift_tol`；1D 超限即判错，2D 因两次刚体操作互相扰动只告警）；
   - **relaxed**：`reached − target` 等于约束弹簧的**已知**偏移 `F_phys(q*)/(2 fc)`（§5.3.5 实测：fc=0.5 约 0.82°、fc=0.05 约 6.84°），由 `reached` 列直接读出，**不要求为 0**；
   stdout 表打印 `value/reached/drift` 三列，其中 **drift = wrapped(reached − value)**，回绕到 [−180°, 180°)，因此跨越 ±180° 的扫描不再打印 ±360° 的假漂移（2D 路径已有 requested/value 两组）；
3. **在同一约束残差水平下**，与参考扫描（`--scan`/`relaxed_scan`）的能量剖面一致（容差 1e-6 hartree）——**两侧的 `constraint_fc` 必须显式设定并对齐**（本套件默认 0.5，xtb `fcconstr` 默认 0.05，见 §5.3.5）；
4. rigid 扫描必须**无滞回**（纯几何构造 ⇒ 正反两支逐点互逆，滞回 ≤ 1e−14 Eh）且逐点 `wrapped(reached − target) == 0`（容差 1e−8 bohr / 1e−8 rad，同第 2 项的 `rigid_drift_tol`）。

**收敛档与容差（实测）**：两侧默认档下第 3 项**未达成**：水分子 distance 5 点最大 1.316e−5 Eh、H₂O₂ 二面角 13 点 4.830e−6 Eh；两侧都收紧到 `vtight` 后 H₂O₂ 6.672e−7 Eh（**达成**）、水分子 1.615e−6 Eh（差 1.6 倍）。根因是**参照实现 ANCopt 自身**在 default↔vtight 之间漂移 3.96e−6 Eh（与两侧差异同量级），不是本套件的问题（本套件侧约束残差 vtight 已 ≤1e−5 Eh/rad）。**实验基准纪律：scan / Hessian 相关实验一律 `OMP_NUM_THREADS=1`**（实测同一 2 点扫描 0.13 s vs 44.12 s，340× 反向加速比；见 §附录 A）。
**rigid 扫描（M2 复核轮修复，见 `docs/_landscape-recon/16-m2-fix-report.md`）**：二面角 rigid 点的旋转片段必须按**中心键 `j–k`** 切割（取含第三个原子 `k` 的远侧片段，它包含末端原子 `l` 及其取代基）。按 `l–k` 切割会把片段退化成 `{l}`，取代基留在原地、连通性一旦跨过切割就吞掉 `i` 侧，被扫二面角在第 7 点起**冻结**（实测 DCE 12° 扫描：滞回 0.1295 Eh = 81 kcal/mol，纯属伪影；修复后同一扫描 1.78e−14 Eh，逐点 drift < 5e−9°）。
**rigid 运行期判据（M2 终轮，见 `docs/_landscape-recon/18-m2-final-fix-report.md`）**：切割若切不出两侧（`moving(blocked)` 为真：环、非成键切割、跨切割伪桥接）一律 `env%error` + 失败，不再静默继续；每个 rigid 点另按 `rigid_drift_tol = 1e−8`（bohr / rad）检查 `wrapped(reached − target)`，1D 超限即判错、2D 只告警（两次刚体操作互相扰动是 2D rigid 的固有性质）。rigid 点的漂移判据依赖 `landscape_scan_coord_wrap_delta`，后者也是 1D 表 `drift` 列的定义。
**Hessian（留待 M3 的策略项）**：`--lscan-method rfo` 会为**每个**扫描点付 6N 次单点建数值 Hessian，而 `--lopt-hessian` 只作用于 `lset`；扫描目前**没有** `--lscan-hessian` 开关（`landscape_scan_settings%hessian_source` 继承默认 `numerical`，只能从 API 改）。加该开关与 M3 的 `file` provider 一并处理。
**LOC ≈ 4400（实现 2330 + 测试 2100）。**

### 9.4 M3：Hessian / freq / thermo

| 模块 | 文件 | LOC 估 |
|---|---|---|
| 数值 Hessian 任务层 | `vib/numhess.f90` | 200 |
| 投影/模式/频率 | `vib/modes.f90` | 260 |
| 热化学薄封装 | `vib/thermo.f90` | 150 |
| `file` provider（解析钩子的第一个具体实现） | `types/hessian.f90`（追加 `landscape_hessian_file`） | 120 |
| 任务 driver | `tasks/vib.f90` | 180 |
| 测试 | `test/unit/test_landscape_vib.f90` | 400 |

交付物：`hessian_source=file`；`vibspectrum`/`vib_normal_modes`/`g98.out` 与既有 `--hess` 对齐。
验收：实验 #2、#3、#12。**LOC ≈ 1310。**

**状态：已实现（M3）**，实现与接线细节见 §12.11，报告见
`docs/_landscape-recon/20-m3-vib-implementation-report.md`（实现）、
`21-m3-validation-experiments.md`（验收实验）与
`23-m3-fix-report.md`（复核后修复）；实际 LOC：实现 1407
（`vib/numhess.f90` 147 + `vib/modes.f90` 349 + `vib/thermo.f90` 173 +
`tasks/vib.f90` 277 + `types/hessian.f90` 新增的 `file` provider/读写器 461）
+ 测试 1036。
实验 #2（step×sccacc 敏感度）、#3（`etemp` 对最低本征值）与 #12（线性分子 3N−5）
均在验证轮完成，数据在 `docs/_landscape-recon/m3-vib-data/`（79 个作业）：
#2 → 默认 0.005/0.3 相对最严格设置误差 ≤0.10（H₂O）/≤0.35（CH₃OH）cm⁻¹，
|λ| ≲ 3 cm⁻¹ 时必须收紧到 0.002/0.1；#3 → `etemp` 在近简并体系上改变最低曲率
5 %–31 %（拉伸 H₂ 0→5000 K 为 −31.4 %），远大于 step/sccacc 的全部误差；
#12 → CO₂/HCN 的 3N−5 与转动配分函数正确。
残余能力边界只有 IR/Raman 强度（Hessian provider 不携带偶极导数，见 §12.11）。

### 9.5 M4：P-RFO / B-PRFO / Dimer

| 模块 | 文件 | LOC 估 |
|---|---|---|
| 选模与跟随 | `saddle/eigenfollow.f90` | 260 |
| RS-P-RFO | `saddle/prfo.f90` | 900 |
| 单体系 B-P-RFO | `saddle/bprfo.f90` | 700 |
| Dimer | `saddle/dimer.f90` | 620 |
| 任务 driver | `tasks/ts.f90` | 220 |
| 测试 | `test/unit/test_landscape_saddle.f90` | 700 |

交付物：`--lts [method=prfo|bprfo|dimer]`；`xtbts.xyz`/`xtbts.log`；虚频确认。
验收：实验 #3、#4、#5；Müller–Brown 上 prfo 与 bprfo 收敛到同一鞍点（几何 RMSD < 1e-3 bohr）。
**LOC ≈ 3400。**

**M4 硬约束（来自 M3 验证轮，报告 21 §3 与 §7 R2/R3）：**

1. **`etemp` 必须冻结并记录**。电子温度是这套方法里最大的单一误差源：实测拉伸 H₂
   的最低（也是唯一）曲率在 `etemp` 0→5000 K 之间漂移 **−31.4 %**（近简并 CH₃· −4.8 %、
   O₂ −0.26 %），远大于 step/sccacc 的全部误差。`ts`/`irc` 的一次运行内不得改变
   `etemp`（引擎的 `landscape_engine_control%etemp` 会写入 xTB 计算器，见 §12.11），
   且必须在输出/重启文件里**记录实际生效值**（`engine_report` 已打印，`sp`/`opt`/`scan`/`vib`
   四个任务均调用，见 §12.11；`xtb/landscape-vib-etemp` 锁住 CLI 同步）。
2. **虚频附近的 FD 不确定度**：默认 `step=0.005 bohr`/`sccacc=0.3` 已被验收，相对最严格
   设置（0.002/0.1）的频率误差 ≤0.10 cm⁻¹（H₂O）、≤0.35 cm⁻¹（CH₃OH）；步长 0.02 或
   `sccacc=1.0` 会退化到 1.7–4.4 cm⁻¹。**当某条曲率落在 0±3 cm⁻¹ 以内时，必须收紧到
   step 0.002（必要时 sccacc 0.1）后再判符号。**
3. **不要用「与 `--hess` 逐位一致」做判据**：两条路径的投影约定不同（Eckart vs
   `trproj`），离驻点越远差越大（实测 0.076–5.21 cm⁻¹，§12.11）。

### 9.6 M5：NEB / CI-NEB / AutoNEB / String(GSM)

| 模块 | 文件 | LOC 估 |
|---|---|---|
| IDPP | `path/idpp.f90` | 220 |
| NEB 内核 | `path/neb.f90` | 1400 |
| CI-NEB | `path/cineb.f90` | 360 |
| AutoNEB | `path/autoneb.f90` | 900 |
| String/GSM | `path/string.f90` + `path/gsm.f90` | 1100 |
| 任务 driver | `tasks/ts.f90`（追加路径分支） | 200 |
| 测试 | `test/unit/test_landscape_path.f90` | 700 |

交付物：`path.xyz`、`path_autoneb.xyz`、`path_ts_list.xyz`。
验收：实验 #8；LEPS 势垒与解析值差 < 0.5 kcal/mol（对应 R05 §3.6 M5 判据）。
**LOC ≈ 4880。**

### 9.7 M6：IRC（GS / HPC / LQA / EulerPC）

| 模块 | 文件 | LOC 估 |
|---|---|---|
| DWI + mBS + LQA 传播（共享） | `irc/corrector.f90` | 420 |
| GS | `irc/gs.f90` | 820 |
| LQA | `irc/lqa.f90` | 700 |
| HPC | `irc/hpc.f90` | 900 |
| EulerPC | `irc/eulerpc.f90` | 950 |
| 任务 driver | `tasks/irc.f90` | 260 |
| 测试 | `test/unit/test_landscape_irc.f90` | 700 |

交付物：`--lirc [method=gs|hpc|lqa|eulerpc]`；`irc_*.xyz` + `irc.log`；三终止信号。
验收：实验 #4、#6、#7。#6 是四算法互校（同 TS 的双向重聚）。
**LOC ≈ 4750。**

### 9.8 M7：thermo/validation 收口

| 模块 | 文件 | LOC 估 |
|---|---|---|
| 端到端链：`sp→opt→hess→freq→thermo` | `tasks/*`（收口 + `--ljson`） | 250 |
| 交叉验证脚本与文档 | `docs/` + `test/unit/test_landscape_e2e.f90` | 400 |

交付物：与 xtb `--hess` 一致的 G/H/ZPE；对 MAPLE 各任务做**拓扑/几何一致性**对照记录（非逐位）。
**LOC ≈ 650。**

**合计 ≈ 21,960 行**（含测试），与 R03 §B 的分文件估算求和同量级。

---

## 10. 风险登记册

| ID | 风险 | 影响 | 概率 | 缓解措施 | 覆盖测试 |
|---|---|---|---|---|---|
| **R-01** | **`accu_hess=0.3` 的 Hessian 噪声**：Hessian 运行时的 SCF 精度被人工放宽（`src/type/setvar.f90:156`），每个位移点都是"半收敛"SCF | 高：Hessian 本征值（尤其低频/虚频）随 `sccacc`/`step`/restart 漂移；PRFO 的 λ_p/λ_n 与选模被污染；IRC 沿路径的 Bofill 更新漂移 | 高 | 把 `sccacc`/`step` 提升为显式 settings；默认沿用 xtb（0.3/0.005）但提供收紧档（0.1/0.002）；Hessian 输出附 `sccacc` 与 `step` 元数据以便复现；实验 #2 | `test_landscape_vib.f90`（实验 #2）、`test_landscape_saddle.f90`（实验 #4） |
| **R-02** | **SCF 可重复性未知**：上游 issue #1378 报告「restart 信息被隐式使用」导致同几何两次梯度不同（R04 §79） | 极高：有限差分 Hessian 的对称性、trust-region 的 `rho` 判据、IRC 的步长控制全部依赖「同几何同梯度」 | 高 | 引擎默认 `p_restart_off`（每次 E+G 前从 `wfn_ref` 重置，§5.1）；三种 restart 模式显式可选并打印；`n_scf_fail` 计数；实验 #1 量化 | `test_landscape_engine.f90`（实验 #1，M0 必须） |
| **R-03** | **`wp => sp` 单精度**：`src/david2.f90:25,221` 的 `sdavid2`/`solver_sdavidson` 是单精度 | 中：RFO/PRFO 若用 Davidson 求最低本征对，`b_k`/`F_k` 精度不足 → shift 求解抖动 | 中 | M0/M1 **不用** Davidson：RFO 用 `lapack_syev`（`src/mctc/lapack.f90:19`）全对角化（小型体系 n≤500 可接受）；仅 M4 之后对大体系引入 Davidson，且必须做「dp 全对角化 vs sp Davidson」对照测试 | `test_landscape_optimize.f90`（RFO 精确性）、`test_landscape_saddle.f90`（大体系对照，M4） |
| **R-04** | **`constrain_pot` 的有限势垒**：约束是软弹簧势（`src/constrain_pot.f90:313`；`springexpo=2.0`，`src/scanparam.f90:36`；默认 `fcconstr`） | 中：TS/scan 的定量势垒受弹簧刚度影响；刚度不足 → 约束坐标漂移；刚度过大 → 条件数恶化 | 中 | scan/TS 中把 `constraint_fc`、`spring_expo` 显式暴露；**每个扫描点报告约束残差** `\|∂E/∂q − λ\|`（R04 §4 工程建议 (c)）；对 TS 的约束改为「笛卡尔步投影 + Hessian 投影」而非弹簧势（`saddle/eigenfollow.f90` 用 `projectHessian`/`trproj`） | `test_landscape_scan.f90`（实验 #11）、`test_landscape_saddle.f90` |
| **R-05** | **`runtyp` 编号冲突**：`p_run_*` 编号非连续（`src/setparam.f90:197-215`，含 71 与 100–104），且同文件另有 `p_ext_*` 占 13–18 | 中：取错值 → 静默走进错误分支 | 低 | 已 grep 确认：`p_run_*` 使用 {1..8,10,11,13,14,15,71,100..104}，**9 与 12 空闲**；`p_ext_*` 占 {13..18}。本计划取 `p_run_lopt=9`、`p_run_lscan=12`、`p_run_lts=19`、`p_run_lirc=20`（19/20 在 `p_run_*` 命名空间内空闲，且不撞 `p_ext_*`）；CLI 只新增 `--l*` 前缀 flag，不改既有分支 | `test/unit` 现有全绿 + `--lopt` e2e；代码审查时复核 grep 结果（§12.1） |
| **R-06** | **units 混用历史**：xtb 内部既有 Å/Eh-Å 混用（R05 §3.8.4；MAPLE 亦然，R03 §C.5） | 高：一个漏转换的量会把误差放大 1.89 倍，且不报错 | 中 | N8/N9：内部全 a.u.，边界显式转换；`coords/cartesian.f90` 是唯一做质量加权/展平的地方；每个 settings 字段在类型定义处标注单位；对复用旧子程序（`relaxed_scan`、`geometry_optimization`、`numhess`）逐点审计单位 | `test_landscape_settings.f90`（单位换算往返）、`test_landscape_scan.f90`（与既有 `xtbscan.log` 对齐） |
| **R-07** | 梯度噪声 σ_g 使四判据不可达 | 高：TS/IRC 迭代数爆炸或假收敛 | 中 | 实验 #4 量化 σ_g，要求 `f_rms ≥ 10σ_g`；`normal` 不可达时降 `loose`；`stagnate_patience` 检测停滞 | `test_landscape_engine.f90`（σ_g）、`test_landscape_saddle.f90` |
| **R-08** | 行/列主序与展平顺序错误 | 高：静默的错误结果（能量对但梯度错位） | 中 | N4：强制 `xyz(3,n)`；`coords/cartesian.f90` 提供唯一 `pack/unpack` 对；LEPS 解析梯度单元测试可立即暴露错位 | `test_landscape_optimize.f90`（解析梯度逐分量比对） |
| **R-09** | 模态跟踪符号翻转 → 模式跳变 | 高：TS 搜索发散到极小点 | 中 | `argmax\|overlap\| + sign realign`（PRFO.py:634-672）；`mode_overlap_min=0.3` 守卫 + 告警 | `test_landscape_saddle.f90`（Müller–Brown 上的模态连续性断言） |
| **R-10** | Dimer separation 定义歧义（R04 Contradictions #1） | 中：曲率 C 差 2–4 倍，收敛行为不同 | 中 | 文档**写明**取「中点→像」定义；`delta` 显式可调；VASP 诊断规则（Torque 不降 ⇒ 增大 delta 或收紧 SCF）移植为运行时告警 | `test_landscape_saddle.f90`（dimer 分支） |
| **R-11** | NEB 弹簧常数矛盾（R04 Contradictions #2：k 可变化数量级 vs 过大妨碍收敛） | 中 | 中 | 区分「平衡位置不敏感」与「收敛速率敏感」：`k_min/k_max` 提供，`use_dynamic_k=.true.` 默认，`[待校准]` 由实验 #8 定值 | `test_landscape_path.f90`（实验 #8） |
| **R-12** | LQA 谱系歧义（R04 Contradictions #3：Page–McIver vs Sun–Ruedenberg QSD） | 中：实现成另一种算法而不自知 | 中 | 在 `irc/lqa.f90` 头注释**明确写出采用的是哪一支**（本计划采用 HPC/EulerPC 论文所引的 Page–McIver LQA 解析传播，与 R04 §12 一致），并在文档中记录 QSD 的差异 | `test_landscape_irc.f90`（实验 #6 与 GS 互校） |
| **R-13** | MAPLE 部分阈值/弹簧常数的单位未标注（`k_min/k_max`、`grow_relax_tol`） | 中：默认值可能差 1.9–3.6 倍 | 中 | 全部标 `[待校准]`；按 MAPLE 能量/长度单位（Ha/Å）推断并给出换算依据；实验 #8 校准 | `test_landscape_path.f90` |
| **R-14** | MAPLE fixture 全部基于 ML 势（R03 §D），不能作 GFN2 数值基准 | 高：若误用会造成"假通过" | 高 | L1 用解析势（Müller–Brown/LEPS/CO₂）做定量验证；MAPLE 输出仅用于**拓扑/几何一致性**抽查，绝不逐位比对 | `test_landscape_*.f90`（L1 层） |
| **R-15** | 许可证：pysisyphus(GPL-3.0)、geomeTRIC(非标准) 的**代码**不可并入 xtb(LGPL-3.0-or-later)；DL-FIND/sella 为 LGPL-3.0（R04 §76、R05 §1.1） | 高（法律） | 低 | **只读文献与 Python 实现用于算法参考，不搬运任何代码**；DL-FIND 只借鉴设计（R05 §1.1.2）；M0 起在 `landscape_api.f90` 头部登记「算法来源为文献，不复制第三方代码」 | 代码审查（人工） |
| **R-16** | 本机 **meson/ninja 未安装**（`meson: command not found`），`meson.build` 无法验证 | 中：Meson 路径可能带着错误进入主干 | 高 | `src/landscape/meson.build` 严格照抄 `src/freq/meson.build` 的结构（`srcs += files(...)`），逐行核对；在 CI/有 meson 的环境补验；CMake 路径**必须**在本机真实验证 | CI（外部）；本机 `cmake` 构建 |
| **R-17** | cmake 4.3.2 下 cpcmx 与 toml-f 目标重名，配置失败 | 中：阻断构建验证 | 高 | 一律显式 `-DWITH_CPCMX=OFF`（`cmake/CMakeLists.txt:20` 的 option 默认 TRUE）；构建目录固定在 `/tmp/...`，仓库内不得出现 `build/` | `cmake` 配置命令本身 |
| **R-18** | `TRestart` 拷贝语义与 `p_restart_off` 的性能代价 | 中：每次 E+G 深拷贝 `wfn` 可能显著拖慢（大体系 O(n²)） | 中 | `wfn_ref` 只在构造/`engine_pin_state` 时拷贝；E+G 内每次 `copy` 的代价与 SCF 相比可忽略（SCF 是 O(n³)），但仍提供 `p_restart_warm` 供 opt/NEB 使用；`landscape_cost_report.wall_seconds` 记录开销 | `test_landscape_engine.f90`（计时对照，M0 可选） |
| **R-19** | B-PRFO 术语歧义（D2 后果） | 低：实现可能与仓库所有者预期不同 | 中 | 已按「RS-P-RFO 单体系版」实现并在文档写明；替换成本限于 `saddle/bprfo.f90` 一个文件 | `test_landscape_saddle.f90`（bprfo 分支） |

---

## 11. 明确不做的事（D2 排除清单）

| 不做项 | 理由（证据） |
|---|---|
| **DMF（Direct MaxFlux）** | 唯一真正需要外部数值库的模块：`ts/algorithm/dmf.py:23` `import cyipopt`、`:1058 class VariationalPathOpt(cyipopt.Problem)`，另有 scipy `BSpline/interp1d/Rotation`（`:30-32`）与 19 处 `einsum/tensordot/matmul`（列主序翻译风险极高）。R03 §E.2 判为"不建议移植"，R04 §55 判为"第二阶段可选项"。**注意**：DMF 本身不需要 Hessian、也不依赖神经网络势（R04 §53），因此排除纯粹是**依赖与翻译成本**决定，与 GFN2 能力无关 |
| **blbfgs / BPRFO 的批量 GPU 版** | 以 `(B, n)` torch 张量为核心（`blbfgs.py:220-289`、`BPRFO.py:366-415`），需重构为 `(n,B)` 列主序 + BLAS-3 批量（R03 §B.1/B.3）。且两者在 MAPLE 中**是死代码**（dispatcher 未引用，R01 §3.1/§3.3）。D2 只要求 B-PRFO 的单体系版 |
| **ML 势 calculator**（ANI/MACE/UMA/AIMNet2/Fennol） | 属 Python 生态（R01 §5.3 全表）；xtb 的引擎边界已经是 `class(TCalculator)`（`src/type/calculator.f90:43`），ML 势应作为外部 `extern` calculator 接入，而非内建（R05 §3.7） |
| **parmfit（NCAA/TorsionFit/ChargeFit/MetalAA/QMInterface）** | 参数开发工具链，与「PES 任务执行」正交；且需调用 Gaussian/ORCA 外部 QM（R01 §2.9、R03 §A.3）。建议独立项目（R05 §3.7） |
| **MD 系综（NVE/NVT/NPT、thermostat/barostat/integrator）** | xtb 已有独立 `md`/`omd`（`src/mdoptim.f90`、`prog/main.F90:1153` 的 md 分派），重复实现无收益（R05 §3.7）。本计划不含时间尺度动力学 |
| **torch / GPU 张量后端** | 与 D1「不引入新依赖」冲突；核心算法全部可纯 Fortran（R03 §A.5 结论） |
| **PBC / 晶胞优化** | 需要 stress/`sigma` 与晶格梯度的额外契约（`src/lbfgs_anc/driver.f90:39 relax_pbc`、`:336,:409 num_grad/num_sigma`）。本计划所有任务在 `mol%npbc == 0` 时工作；`npbc > 0` → `env%error("landscape tasks do not support PBC yet")` 并返回（**不做静默降级**） |
| **内坐标（DLC/HDLC/冗余）作为 TS/IRC 的步空间** | R05 §3.1 保留 `coords/internal.f90` 与 `coords/transform.f90` 用于 scan 与 Hessian 变换，但 TS/IRC 的步计算固定质量加权 Cartesian（与 MAPLE/ORCA IRC 一致：`Follow_CoordType cartesian`，R04 §66）。理由：orbital-free 的投影/重叠判据在 Cartesian 下最稳，内坐标会引入额外的 Jacobian 误差 |
| **`bias_path` 的 metadynamics 自举路径、`modefollow`、`intmodes` Z-matrix** | 与标准 NEB/GSM/PRFO 目标不同；`intmodes` 已被 `internals/*`+`bmatrix` 取代（R05 §3.7）。这三个既有功能**保持不动**，只是新套件不依赖它们 |
| **全局优化 / GA / 随机搜索 / 圆锥交叉（MECI）** | DL-FIND 提供但不在 D2 的 sp/opt/scan/ts/hessian/freq/irc 范围内（R05 §1.1.2） |
| **重写热化学（RRHO）与频率打印** | xtb 已完整（`src/main/property.F90:695`、`src/thermo.f90:79`）；本套件只做 wrapper 与参数暴露（§5.3.8） |

---

## 12. 集成点

> **本节描述的是已落地实现**（M0+M1 修复轮，代码为准）。各小节标注「已实现」的部分
> 与代码逐行对应；未实现的里程碑条目保留为规划。与初版计划的差异集中在 §12.8。

### 12.1 `set_runtyp` 新常量取值（已 grep 确认无冲突）【已实现】

实测命令与结果：

```bash
grep -n "p_run_" src/setparam.f90          # 197-215: 使用 {1..8,10,11,13,14,15,71,100..104}
grep -n "p_ext_" src/setparam.f90          # 193-195: 使用 {13..18}
grep -rn "set%mode_extrun = p_ext_" src/set_module.f90   # :958,:978 —— p_ext_* 属于 set%mode_extrun
```

结论：`p_run_*` 命名空间中 **9 与 12 空闲**；`p_ext_*` 占 13–18。
因此取（并保证与 `p_ext_*` 取值不重叠，避免误读）：

| 常量 | 值 | 里程碑 | 用途 | 状态 |
|---|---|---|---|---|
| `p_run_lopt` | 9 | **M0/M1** | 新版极小化套件（`--lopt`） | ✅ 实现在 `src/setparam.f90`（`p_run_omd = 8` 之后） |
| `p_run_lscan` | 12 | **M2** | 扫描（`--lscan`） | ✅ 实现在 `src/setparam.f90`（`p_run_screen = 11` 之后） |
| `p_run_lts` | 19 | M4 | 过渡态（`--lts`） | ❌ 未实现 |
| `p_run_lirc` | 20 | M6 | IRC（`--lirc`） | ❌ 未实现 |

若仓库所有者倾向「不复用低编号」，退路是取 105–108（当前 `p_run_*` 最大为 104）；
两种方案都已确认不与任何现有取值冲突，**本轮实现以 `p_run_lopt = 9` 为准**。

若仓库所有者倾向「不复用低编号」，退路是取 105–108（当前 `p_run_*` 最大为 104）；
两种方案都已确认不与任何现有取值冲突，**M0 实现时以 9/12/19/20 为准**。

新增位置：`src/setparam.f90` 的 `p_run_*` 块（`src/setparam.f90:197-215`）之后追加 4 行。

### 12.2 `src/set_module.f90`: `set_runtyp`【已实现】

在 `subroutine set_runtyp`（`src/set_module.f90:1031`）的 `select case(typ)` 中追加：

```fortran
   case('lopt')          ! 已实现（M0/M1）
      set%runtyp = p_run_lopt

   case('lscan'); set%runtyp = p_run_lscan    ! M2
   case('lts');   set%runtyp = p_run_lts      ! M4
   case('lirc');  set%runtyp = p_run_lirc     ! M6
```

（本轮只加 `lopt`，其余在对应里程碑追加。）

### 12.3 `src/prog/main.F90`【已实现】

**（a）runtyp 分派**：主分派区（在 `anyopt` 块之后、VIP/VEA 之前）新增
（以下为 `src/prog/main.F90:928-961` 的**实际**代码，M2 复核轮核对了本节）：

```fortran
      ! landscape suite (minimisation with the algorithms of src/landscape)
      if (set%runtyp == p_run_lopt) then
         lset%engine%acc = set%acc          ! CLI 的 --acc 同步到引擎控制对象
         call start_timing(3)
         call run_landscape(env, mol, chk, calc, lset, lres)
         call stop_timing(3)
         ! 回写：TOTAL ENERGY 行/xtbout.json 读的是 res，几何由任务层写
         res%e_total = lres%energy
         res%gnorm   = lres%gnorm
         call env%checkpoint("Landscape task terminated")
      end if

      ! landscape suite (scan with the algorithms of src/landscape)
      if (set%runtyp == p_run_lscan) then
         lsset%engine%acc = set%acc
         call start_timing(3)
         call run_landscape(env, mol, chk, calc, lsset, lres)
         call stop_timing(3)
         res%e_total = lres%energy          ! 最低扫描点的去偏能量
         res%gnorm   = lres%gnorm
         call env%checkpoint("Landscape task terminated")
      end if
```

两处 `%engine%acc = set%acc` 是必需的：`xtb_single::singlepoint` 虽然收下了 `acc` 形参却**丢弃**
它，只有 `calc%accuracy` 真正生效（`docs/_landscape-recon/12-*.md` R2-02）。同理
`engine%maxiter` **不会**传到 SCC（`singlepoint` 只转发 `printlevel`/`restart`），
要限制 SCF 迭代数必须设 `calc%maxiter`（单元测试 `scan-task-no-energy` 即用此法）。

其中 `lset`（`landscape_opt_settings`）/`lsset`（`landscape_scan_settings`）/`lres`
（`landscape_result`）在 `xtbMain` 声明区加入，并通过新增的 `use` 语句引入
（`use xtb_landscape, only : run_landscape`；
`use xtb_landscape_settings, only : landscape_opt_settings, landscape_scan_settings, …`；
`use xtb_landscape_results, only : landscape_result`）。
`lset`/`lsset` 由 `parseArguments`（新增 `intent(inout)` 形参）填充，无需 xcontrol handler（§12.4）。
另外 `p_run_lopt`/`p_run_lscan` 必须加入参数文件选择块的 `select case (set%runtyp)` 列表，
并在 `finalize_xtb` 中加 `prtiming(3, 'landscape optimizer')`。

**（b）CLI flag**：主 flag 循环的 `select case(flag)`（`src/prog/main.F90:1378-2070`，
`case ('-o', '--opt')` 在 `:1950`、`--hess` 在 `:1957`、`--path` 在 `:2004`、`--modef` 在 `:2018`）
已新增：

| 新 flag | 行为 | 状态 |
|---|---|---|
| `--lopt` | `set_runtyp('lopt')`，不解桁任何位置参数（避免吃掉几何文件名）；算法/收敛档用下面两个 flag | ✅ **已实现** |
| `--lopt-engine <sd\|cg\|lbfgs\|bfgs\|diis\|rfo>` | 设 `lset%algorithm`（`landscape_opt_algorithm_from_name`）；未识别的名字 → `env%error` 并终止（exit 1） | ✅ **已实现** |
| `--lopt-level <superloose\|loose\|normal\|tight\|vtight>` | `lset%set_conv_level`；未识别的档名 → `env%error` | ✅ **已实现** |
| `--lopt-hessian <numerical\|model>` | 设 `lset%hessian_source`（`landscape_hessian_source_known` 校验）；`model` = Lindh-D2 模型 Hessian，作为 BFGS 的初始 Hessian 与 RFO 的 trust-region Hessian；未识别名字 → `env%error` | ✅ **M2 复核轮已实现**（R2-09 遗留项） |
| `--lscan` | `set_runtyp('lscan')`，不解桁位置参数；全部扫描参数走 `--lscan-*` | ✅ **M2 已实现**（见 §12.10） |
| `--lts` / `--lirc` / `--ljson` | —— | ❌ 未实现（后续里程碑） |

**与初版计划的差异**：`--lopt` **不**接受位置参数（原计划为 `--lopt [level]`）。原因：
`TArgParser%nextArg` 无 peek，无条件消费会让 `xtb --lopt water.xyz` 把文件名当作 level 吃掉；
改用独立 flag 后语义无歧义。`--lopt-engine`/`--lopt-level` 也可单独使用（会自动设 `runtyp=lopt`）。

**理由**：全部用 `--l*` 前缀，与既有 flag **零冲突**（`--license`、`--lmo` 为不同字符串，
Fortran 的 `select case` 是精确匹配）。`--opt`/`--hess` 的行为**完全不变**（回归测试见 §12.9）。

### 12.4 xcontrol（可选，M2 起）

`src/constrain_param.f90` 已有 handler 注册机制（`set_scan` 在 `:844`、`set_hess` 在 `:1229`）。
M2 起注册 `set_landscape(env, key, val, ...)`，支持：

```
$landscape
   convlevel=normal
   hessian=numerical
   engine=rf|lbfgs      ! 仅 info 用途
   restart=off|pin|warm
$end
```

M0 **不**加 xcontrol handler（减少既有文件改动面）；配置先全部走 CLI。

### 12.5 构建注册

**CMake**（`src/CMakeLists.txt`）：
1. 在 `add_subdirectory("iff")`（`src/CMakeLists.txt:28`）之后、`add_subdirectory("main")`（`:29`）之前
   插入 `add_subdirectory("landscape")`（即新的第 29 行）。
2. 不加任何顶层 `list(APPEND srcs ...)`（由 `src/landscape/CMakeLists.txt` 的
   `set(srcs ${srcs} PARENT_SCOPE)` 回传，模式见 `src/freq/CMakeLists.txt:18-26`）。
   实现时**逐行照抄 `src/freq/CMakeLists.txt` 的结构**（`set(dir ...)` → `list(APPEND srcs ...)` →
   `set(srcs ${srcs} PARENT_SCOPE)`），不做任何“改进”，因为 `freq` 的写法已被证明在本仓库生效。
3. `src/landscape/CMakeLists.txt` 内容结构：`set(dir "${CMAKE_CURRENT_SOURCE_DIR}")` +
   `list(APPEND srcs "${dir}/landscape_api.f90" ... "${dir}/vib/thermo.f90")` +
   `set(srcs ${srcs} PARENT_SCOPE)`（含版权头，与 `src/freq/CMakeLists.txt:1-16` 一致）。

**Meson**（`src/meson.build`）：
1. 在 `subdir('iff')`（`src/meson.build:28`）之后、`subdir('main')`（`:29`）之前插入 `subdir('landscape')`。
2. `src/landscape/meson.build`：`srcs += files('landscape_api.f90', 'types/settings.f90', ...)`
   （结构照抄 `src/freq/meson.build:18-22`）。**本机无 meson，无法验证（R-16）**。

### 12.6 测试注册【已实现】

| 文件 | 改动 | 状态 |
|---|---|---|
| `test/unit/CMakeLists.txt` | `tests` 列表新增 `landscape-api`、`landscape-settings`、`landscape-coords`、`landscape-hessian-update`、`landscape-hessian`、`landscape-cg`、`landscape-optimize-math`、`landscape-optimize-xtb` | ✅ 已实现 |
| `test/unit/main.f90` | 对应的 8 个 `use test_landscape_<area>` 与 `new_testsuite(...)` 条目 | ✅ 已实现 |
| `test/unit/meson.build` | `tests` 列表同步（无法本机验证，R-16） | ✅ 已实现 |

另外，**CLI 级端到端回归**也注册在 `test/unit/CMakeLists.txt`（现有风格见文件末尾，
例如 `add_test("xtb/Singlepoint" ${XTB-EXE} --coffee --strict --norestart --namespace test1)`）：

```cmake
# 几何文件在 build 目录生成（仓库保持无测试数据），
# 用一个小 CMake 脚本同时检查退出码、收敛标志与输出文件。
add_test("xtb/landscape-opt" ${CMAKE_COMMAND} -DEXE=... -DINPUT=... -DRUNDIR=...
  -P "${CMAKE_CURRENT_BINARY_DIR}/landscape_cli_check.cmake")
```

实际执行的命令为
`xtb <landscape_h2o.xyz> --gfn 2 --lopt --lopt-engine lbfgs --lopt-level normal --norestart --namespace landscape1`，
脚本断言：（i）退出码 0；（ii）stdout 含 `landscape: converged`；（iii）`xtbopt.xyz` 与 `xtb.trj`
存在且非空。meson 侧用 `run_command(python, '-c', ...)` 在 build 目录生成同一几何
（meson 总是有 Python，见根 `meson.build`）并注册同名 test。
（原计划的 `--coffee` 版本已放弃：caffeine 72 个自由度对未调优的 L-BFGS 太慢。）

M2/M4/M6 同构追加 `--lscan` / `--lts` / `--lirc`（各自独立 `--namespace`）。
本仓库**没有** `test/cli/` 目录，因此 CLI 级回归与单元测试一样注册在 `test/unit/CMakeLists.txt`。

**注意**：`test/unit/CMakeLists.txt` 用 `string(MAKE_C_IDENTIFIER ...)` 把
`landscape-hessian` 转成标识符再拼 `test_${t}.f90` → 文件名必须是 `test_landscape_hessian.f90`
（连字符 `-` 映射为下划线，与现有 `model-hessian` → `test_model_hessian.f90` 一致）。

### 12.7 本轮（M0+M1）实际改动的既有文件

| 文件 | 改动 | 行数（git diff） |
|---|---|---|
| `src/CMakeLists.txt` | +1 行 `add_subdirectory("landscape")` | +1 |
| `src/meson.build` | +1 行 `subdir('landscape')` | +1 |
| `src/setparam.f90` | +1 行 `p_run_lopt = 9` | +1 |
| `src/set_module.f90` | +3 行（`case('lopt')` 与赋值） | +3 |
| `src/prog/main.F90` | +`use` 5 行、+声明 2 行、+分派块 8 行、+3 个 flag 分支 ~45 行、`parseArguments` 形参 2 行、+`prtiming` 3 行 | 见 `git diff --stat` |
| `test/unit/CMakeLists.txt` | `tests` 列表 +3 项 + CLI 冒烟测试（~50 行） | 见 `git diff --stat` |
| `test/unit/main.f90` | +3 个 `use` 与 3 个 `new_testsuite` | +6 |
| `test/unit/meson.build` | `tests` 列表 +3 项 + meson CLI 冒烟（~15 行） | 见 `git diff --stat` |

**其他既有文件一律不动。** 不修改 `src/optimizer.f90`（不改 `set%tsopt` 语义）、
不改 `src/hessian.F90`、不改 `src/type/calculator.f90`、**不改 `src/xhelp.f90`**
（因此 `xtb --help` 尚未列出 `--lopt*`，见 §12.8 D7）。

### 12.8 实现相对初版计划的差异（代码为准）

| 编号 | 差异 | 理由 / 证据 |
|---|---|---|
| **D1** | `types/conv.f90` 不单独建立：四判据在 `types/settings.f90`（`landscape_settings_is_converged`、`landscape_convergence_measures`），收敛报告在 `types/results.f90`（`landscape_convergence_report`）。同理 `test_landscape_conv.f90`/`test_landscape_engine.f90` 分别并入 `test_landscape_settings.f90`/`test_landscape_optimize_math.f90` + `test_landscape_optimize_xtb.f90` | 避免为 ~30 行的判据建一个模块，也避免同一概念（收敛报告）在两个模块各存一份（PLAN §11「不加死代码」）；测试用例名一一对应（`convergence-boundary`/`convergence-measures`/`engine-cache`/`engine-hvp`/`gfn2-singlepoint-determinism`） |
| **D2** | 数值 provider **自建中心差分**（`landscape_numerical_hessian_provider`，直接逐位移调用 `TCalculator%singlepoint`），**不**转调 `TCalculator%hessian`；`odlr=.true.` → `env%error` | `07-*.md` §4.3 硬要求：`$hess` 控制块的 `step`/`sccacc` 在非 `--copy` 路径下静默失效，必须自带步长/SCF 精度。实测：与 `TCalculator%hessian` 同 step/acc 逐点差 < 1e-8（`test_landscape_hessian.f90::numerical-vs-calculator`） |
| **D3** | provider 类型命名为 `landscape_hessian_provider` / `landscape_numerical_hessian_provider` / `landscape_model_hessian_provider`（PLAN §5.2 写作 `landscape_hessian_numerical`）；`hessian_source` 在任务 settings 基类（`landscape_settings%hessian_source`），**不在** `landscape_engine_control` 中 | 命名统一为「形态在名前」；`hessian_source` 是任务级配置（PLAN §5.3.2 也把它放在 `TDriverSettings`），引擎只持有已选定的 provider（`engine%hp`），避免两处真相。未识别取值 → `new_landscape_hessian_provider` 报错且不返回 provider |
| **D4** | `landscape_model_hessian_provider` **已在 M1 补齐**：实现 Lindh-D2 构造（复用 `src/model_hessian/lindh.f90`），并作为 RFO/BFGS 初猜注入 | 原计划把本体列入 M3；修复轮（R2/D3）认为「D3 口径要求 model 初猜」是真实缺口，故提前到 M1 完成。`swart`/`eeq`/`file` 变体仍留待后续里程碑 |
| **D5** | CG 采用 PRP+（`beta = max(0, beta_PR)`，Nocedal & Wright Alg. 5.4）+ 非下降方向重启；**不采用** Powell 对齐重启（`|g_k.g_{k-1}|/|g_k|^2 >= 0.2`），因此 settings 无 `cg_restart_threshold` | Powell 对齐判据预设了带曲率条件的线搜索；本套件只有 Armijo 回退（PLAN §5.3.4），实测该判据导致 CG 退化为 SD（GFN2 水：CG 轨迹与 SD **逐位相同**），且 4 维强凸二次型上步数从 190 变 337（即变差）（`test_landscape_cg.f90`） |
| **D6** | `tasks/opt.f90` 在 **不收敛** 时报 `env%error`（exit≠0）；`landscape_optimize_model` 内核保持只返回 `result%converged` | 与既有 ANCopt 失败行为一致，且使 CLI 冒烟测试能真正断言「收敛」 |
| **D7** | `xtb --help` 未列出 `--lopt*` | `src/xhelp.f90` 不在本轮允许改动的文件集内；建议下一轮在 `help` 表格（参考 `--opt` 条目，`src/xhelp.f90:270`）补上 |
| **D8** | CLI 级冒烟测试用**水分子**（几何在 build 目录生成）而非 `--coffee` | caffeine（72 自由度）在未调优的 L-BFGS 上远超测试时间预算；水分子 5 步收敛 |

### 12.9 本轮验收证据（真实执行）

```
$ cmake --build /tmp/xtb-land/build -j
[100%] Built target xtb-tester / xtb-exe ...

$ ctest --test-dir /tmp/xtb-land/build --output-on-failure -R landscape
1/9  xtb/landscape-api ............... Passed
2/9  xtb/landscape-settings .......... Passed
3/9  xtb/landscape-coords ............ Passed
4/9  xtb/landscape-hessian-update .... Passed
5/9  xtb/landscape-optimize-math ..... Passed
6/9  xtb/landscape-cg ................ Passed
7/9  xtb/landscape-hessian ........... Passed
8/9  xtb/landscape-optimize-xtb ...... Passed
9/9  xtb/landscape-opt ............... Passed  (CLI 冒烟：退出码 0 + 收敛标志 + 输出文件)
100% tests passed, 0 tests failed out of 9

$ /tmp/xtb-land/build/xtb /tmp/dt.xyz --gfn2 --lopt --lopt-engine lbfgs --lopt-level normal
gradient threshold (max):    3.000000E-04 Eh/bohr
restart policy:           off
Hessian source:           numerical
      1      -5.070432957755 ...   1
      2      -5.070540211546 ...
      3      -5.070543386304 ...
      4      -5.070544355967 ...
      5      -5.070544447778      -0.0001  5.877463E-06
landscape: converged
criteria (gmax,grms,dmax,drms):  T T T T
wrote xtbopt.xyz
wrote xtb.trj
landscape task terminated: converged
# exit code 0
```

其余算法（同一水分子、`--lopt-level normal`）：`sd` 20 步、`cg` 20 步、`bfgs` 4 步、
`diis` 12 步、`rfo`（`--lopt-level loose`，自建 FD Hessian）2 步，均 exit 0。

---

### 12.10 M2（scan）实际 CLI 接线

`--lscan` 与 `--lopt` 同构：flag 本身不解桁任何位置参数，所有参数用独立的
`--lscan-*` flag。全部名字实测存在于 `src/prog/main.F90` 的 `select case(flag)`，
`xtb --help | grep lscan` 有输出（`src/xhelp.f90`）。

| flag | 语义 | 对应 settings 字段 |
|---|---|---|
| `--lscan` | 选中 `p_run_lscan`（runtyp 12） | — |
| `--lscan-coord <distance\|angle\|dihedral>` | 第 1 个扫描坐标类型 | `coord(1)%ctype` |
| `--lscan-atoms <i[,j[,k[,l]]]>` | 第 1 个坐标的 1-based 原子编号（逗号/空格分隔） | `coord(1)%atoms(1:4)` |
| `--lscan-step <x>` | 第 1 个坐标步长，**Å（distance）/度（angle、dihedral）**，解析末尾统一换算为 a.u. | `coord(1)%step` |
| `--lscan-nstep <n>` | 第 1 个坐标步数（必须 ≥ 1） | `coord(1)%nstep` |
| `--lscan-coord2` / `--lscan-atoms2` / `--lscan-step2` / `--lscan-nstep2` | 同上，第 2 个坐标；**任一出现即置 `ndim = 2`**（笛卡尔积网格） | `coord(2)%*`、`ndim` |
| `--lscan-ndim <1\|2>` | 显式设置维数 | `ndim` |
| `--lscan-mode <relaxed\|rigid>` | 松弛 / 刚体 | `mode` |
| `--lscan-method <sd\|cg\|lbfgs\|bfgs\|diis\|rfo>` | 内层极小化算法 | `method` |
| `--lscan-level <superloose\|loose\|normal\|tight\|vtight>` | 内层收敛档 | `g_max/g_rms/d_max/d_rms` |
| `--lscan-restart <off\|pin\|warm>` | 波函数策略（**不是**几何热启动） | `engine%restart_mode` |
| `--lscan-oneway` | 只扫正向（关闭反向支与滞回报告） | `bidirectional = .false.` |
| `--lscan-cold-start` | 每点从输入几何出发（关闭几何热启动） | `warm_start = .false.` |
| `--lscan-fc <hartree/bohr^2>` | 约束势力常数 | `constraint_fc` |
| `--lscan-expo <x>` | 约束势指数 | `spring_expo` |

**单位换算位置**：`--lscan-step` 在 flag 循环结束后（`parseArguments` 末尾）统一
按最终确定的 `ctype` 换算（Å→bohr 用 `aatoau`，度→rad 用 `pi/180`），因此
`--lscan-coord` 与 `--lscan-step` 的先后顺序不影响结果。settings 内部一律 a.u.。

**输出**：`xtbscan.log`（受 `--namespace` 影响，与既有 `src/scan_driver.f90:98,129`
一致；每帧 = 几何 + `energy = Etot − Efix` 去偏能量；**能量被丢弃的点不写帧**，
见 §5.5），stdout 打印逐点表（**请求值 / 到达值 / 漂移** / 去偏能量 / 约束残差 /
内层步数 / 收敛标记；无能量的点为 `NaN` + `F`）、滞回报告与最大跳变位置。

`landscape_scan` 对每个扫描点写盘与报告；`result%energy` = 最低点去偏能量，
`result%gnorm` = 该点的约束残差，`mol%xyz` 回写为最低点几何（`main.F90` 因此
打印的是最低点而非初始几何）。

### 12.11 M3（vib）实际接线与偏离

**runtyp 取值实测**：`grep -n "p_run_" src/setparam.f90` 的取值集合为
`{1..15, 71, 100..104}`（`p_ext_*` 占 13–18，属 `set%mode_extrun`，与 `p_run_*`
语义不同但为避免误读不重合）。19/20 仍预留给 `--lts`/`--lirc`（§12.1），
因此 M3 取 **21**：

| 常量 | 值 | 里程碑 | 用途 | 状态 |
|---|---|---|---|---|
| `p_run_lvib` | 21 | **M3** | 频率/热化学（`--lvib`） | ✅ 实现在 `src/setparam.f90`（`p_run_metaopt` 之后） |

**新增 CLI flag**（`src/prog/main.F90` 的 `select case(flag)`，`src/xhelp.f90` 同步）：

| flag | 语义 | 对应 settings 字段 |
|---|---|---|
| `--lvib` | 选中 `p_run_lvib`，不解桁位置参数 | — |
| `--lvib-hessian <numerical\|model\|file>` | Hessian 后端 | `hessian_source` |
| `--lvib-hessian-file <name>` | `file` 源读取的文件（TURBOMOLE 布局） | `hessian_file` |
| `--lvib-step <bohr>` | 数值 Hessian 差分步 | `engine%hess_step` |
| `--lvib-sccacc <acc>` | 差分点的 SCC 精度 | `engine%hess_acc` |
| `--lvib-odlr` | 请求 ODLR（**未实现，显式报错**） | `engine%odlr` |
| `--lvib-no-project` | 不做平动/转动投影 | `project_tr = .false.` |
| `--lvib-temp <K>` | 热化学表温度（单值） | `temperature(1)`、`n_temperature` |
| `--lvib-rotor-cutoff <cm^-1>` | quasi-RRHO 转子 cutoff | `rotor_cutoff` |
| `--lvib-imag-cutoff <cm^-1>` | 虚频 cutoff（需带负号；`-20` 不含字母，`TArgParser` 判为参数而非 flag） | `imag_cutoff` |
| `--lvib-freq-scal <x>` | 热化学频率缩放 | `freq_scal` |

**顺带补齐（PLAN §9.3 遗留）**：`--lopt-hessian-file`、`--lscan-hessian`、
`--lscan-hessian-file`（`--lscan-method rfo` 与内层 BFGS 初猜因此可从 CLI 选择后端）、
`--lscan-max-steps`（M2 遗留 M-1）。

**与 §5.3.8 的偏离（代码为准）**：

1. `step`/`sccacc`/`odlr` 不另设字段，复用 `landscape_engine_control` 的
   `hess_step`/`hess_acc`/`odlr`（同一概念只保留一种拼写）。
2. `pressure` 与 `ilowfreq` **不实现**：xtb 的 RRHO 没有压力参数，也没有
   `ilowfreq`；`rotor_cutoff`（= `set%thermo_sthr`）就是 Grimme 自由转子方案本身。
   暴露无消费者的字段属于死代码。
3. `linear_tol` 默认取 **1.0e-4 bohr²**（`src/axis_trafo.f90:31` 的 `linthr_bohr2`），
   不是计划表里的 1e-8：必须与既有 `--hess` 的 `mol%linear` 判据一致，否则
   3N−5/3N−6 计数会与既有输出不同。
4. `landscape_vib_settings%write_files` 只控制本套件自己写的 `hessian` 与
   `vib_normal_modes`；`vibspectrum`、`g98.out` 与热化学表由复用的 `main_freq`
   无条件产生（该函数没有输出开关）。
5. `landscape_vib_result` 增加 `rmass(3n)`（xtb `freq_results%rmass` 的定义），
   因为 `g98.out` 与 `vibspectrum` 需要"Red. masses"列。

**热化学的全局写入**：`vib/thermo.f90` 是全套件唯一写既有全局状态的地方，写入
`set%thermotemp/nthermo/thermo_sthr/thermo_ithr/thermo_fscal`（`src/setparam.f90:284-291`）
与 `xtb_splitparam::atmass`（amu，`axis2` 读它；`src/prog/main.F90:461`、
`src/prog/thermo.f90:103` 同样如此）。settings 对象仍是唯一真源，写入发生在调用
`main_freq` 之前。

**投影约定与 `--hess` 的关系（实测，第 23 号修复轮更新）**：本套件用 Eckart 投影
（`xtb_freq_project::projectHessian`，即 `xtb thermo` 的路径，PLAN §5.3.8/R04 §71），
既有 `--hess` 用遗留的 `trproj`（非质量加权空间）。两者**都**是数值（中心差分）Hessian，
步长 0.005 bohr、SCC 精度 0.3（`--hess` 自己的 stdout 写的是 `| Numerical Hessian |`、
`step length 0.00500`、`SCC accuracy 0.30000`；计时表里的 `analytical hessian` 只是
`src/prog/main.F90:2840` 的固定标签，**不代表解析 Hessian**）。差异**主要**来自投影：
把**同一个**原始 Hessian 分别过两条投影（单元测试 `water-vs-trproj`，同一矩阵）：

| 几何 | Eckart | trproj | max‖Δf‖ |
|---|---|---|---|
| GFN2 极小点（`h2o_opt`） | 1539.1480 3644.0560 3652.3753 | 1539.1469 3644.0557 3652.3013 | **0.074** cm⁻¹ |
| 强扭曲水（测试几何） | 1318.0122 3716.0701 4141.5458 | 1318.5519 3706.8595 4128.6366 | **12.91** cm⁻¹ |
| 非驻点水（`h2o_raw`） | 1565.0991 3629.7342 3642.9892 | 1565.0984 3634.9475 3643.6359 | **5.213** cm⁻¹ |

机制：两个投影算子去掉的是**同一个** 6 维刚体运动的**空间**，但它们在**不同的度量**里
定义它——`trproj` 用**单位质量**的平动/转动向量（绕单位质量质心）投影**非质量加权**
Hessian（`src/freq/project.f90:151`），Eckart 先质量加权、再用质量加权的刚体向量
（绕质量加权质心）投影（`projectHessian`，`:34`）。因此在**驻点**上两者几乎一致
（真实 Hessian 的零空间与之重合），随偏离驻点程度增大而增大（实测三点：极小点 0.074、
非驻点 5.213、强扭曲水 12.91 cm⁻¹；未做比例性检验，不写成 ∝ ‖g‖）；`trproj` 本身
**不含任何梯度项**（早期文档里的这句话是错的）。

CLI 层面的同几何对比（`--lvib` vs `--hess`，本轮重测，与第 21 号报告一致）：
**0.0757（H2O 极小点）/ 0.9972（CH3OH 极小点）/ 0.0036（CO2）/ 5.2109（非驻点 H2O）**
cm⁻¹。CO2 是线性分子、两条路径**都跳过投影**，所以 0.0036 cm⁻¹ 是「非投影」残余的
上界（为 `--hess` 与套件两条数值 Hessian 实现之间的差异，来源未进一步归因，报告 23 §8.1）；
投影项在极小点上占 0.0757−0.0036 ≈ 0.072 cm⁻¹。**不再使用
单一数字 5.71 cm⁻¹**（该数字来自一个未入库的几何，第 21 号报告 §5.5 已无法复现）。
线性分子按既有做法**跳过投影**并取最低 5 个本征值为零模，因此 CO2 两路径一致。
把各自的 `hessian` 文件喂回套件（Eckart）会**各自复现自己**到 0.01 cm⁻¹（对已投影
矩阵再投影近似幂等），所以文件级互操作不受影响。

**电子温度（`etemp`）接线（第 23 号修复轮；第 25 号补 P2-B/P1-1）**：`xtb_single::singlepoint`
把传入的 `et` 参量**丢弃**（`src/single.f90:52`），计算器实际用的是自己的 `etemp` 字段
（构造时从全局 `set%etemp` 拷一次，`src/xtb/calculator.f90:144`）。引擎因此在
`landscape_engine%set_calculator` 里把 `landscape_engine_control%etemp` 显式写进
xTB 计算器（与已有的 `acc` 同一机制），CLI 侧在 `main.F90` 三个 landscape 入口处
`engine%etemp = set%etemp` 同步；`engine_report` 从计算器**读回**并打印生效值，
使「设置没进去」从外部可见。`sp`/`opt`/`scan` 在任务末尾调用 `engine_report`；
`--lvib` 的引擎在 `vib/numhess.f90` 内建内销毁，现在同样在销毁前调用它，
因此四个任务的 stdout 都含生效 `etemp`（PLAN §9.5 的 M4 gate 依赖这一点）。
行为由三层测试锁住：单元测试 `etemp-control`（拉伸 H₂ 300 K vs 5000 K，锁住
“推入计算器”）、CLI 测试 `xtb/landscape-vib-etemp`（`--etemp 300` vs `--etemp 5000`，
断言打印值等于传入值且 `eigval` 确实改变，锁住 `main.F90` 同步）。

**INFO-1（`vib_normal_modes` 的索引约定）**：`writeNormalModesTurbomole` 把传入矩阵的
**第一个下标当笛卡尔分量**做质量反加权、却把**第一个下标当模式号打印**，因此该文件里
**每一行是笛卡尔分量、每一列（列组）才是模式**（与常见读法相反，
`src/io/writer/turbomole.f90:164-188`）。下游工具按「行 = 模式」读会得到错误结论。

**INFO-2（与 MAPLE 的频率常数差异，不得用作紧容差参照）**：MAPLE 的 `2721.1383`
是 **Hartree/Å² + amu** 约定，xtb 的 `autorcm = 219474.63067`
（`src/mctc/convert.f90:40`）是 **Hartree/bohr² + 电子质量** 约定；两者对同一物理频率
系统差 ~0.04 %（3644 cm⁻¹ 处 ~1.5 cm⁻¹）。与 MAPLE 对拍只能比拓扑/量级（N9），
不能比 0.01 cm⁻¹。

**INFO-3（全域未收敛扫描的退出码）**：`tasks/scan.f90` 的「无收敛点」分支只发
`env%warning`，因此 `xtb --lscan-max-steps 0` 以**退出码 0** 结束（同时 TOTAL ENERGY
打印 NaN）。这是 M2 已接受的语义（R-04：点未收敛是告警不是失败）且已被测试固定；
M7 收口时若统一「结果不可用 ⇒ 非零退出」，这里要一并改。

---

## 附录 A：环境约束（已实测）

| 项 | 实测值 | 对本计划的影响 |
|---|---|---|
| `cmake --version` | 4.3.2 | 必须 `-DWITH_CPCMX=OFF`（否则 cpcmx 与 toml-f 目标重名，`CMakeLists.txt:56-58`） |
| `gfortran --version` | GNU Fortran 12.2.0 | 支持 `implicit none(type, external)`、`allocate(polymorphic, source=)`、`select type` |
| `meson` / `ninja` | **未安装**（`command not found`） | `meson.build` 必须写但无法验证（R-16） |
| mctc-lib | 本机无，CMake 经 FetchContent 联网拉取 v0.5.1 | 构建需网络；已验证可行 |
| 构建目录 | 一律 `/tmp/...` | 仓库内**不得**出现 `build/` |
| `git status` | 仅 `?? docs/` | 本轮交付物只有文档 + 允许的最小既有文件改动 |
| `OMP_NUM_THREADS` | 未设置时 = 机器核数（本机 8） | **scan / Hessian 相关实验、基准与测试一律 `OMP_NUM_THREADS=1`**：实测同一 2 点扫描 0.13 s（1 线程）vs 44.12 s（8 线程，340× 反向加速，AGENTS §6.8）；`ctest -R landscape` 由 38 s 降到 10.6 s，其中 `xtb/landscape-scan`（单元套件）从 19.6 s 降到 0.13 s、`xtb/landscape-scan-failed-point` 从 28 s 降到 0.11 s；所有跑引擎的 landscape CLI 检查与单元套件已在 CMake/meson 两侧固定单线程。并行只用于「多进程跑不同扫描点」 |

**M2 复核轮的验证命令**（实现阶段；不得跑全量 ctest）：

```bash
ctest --test-dir /tmp/xtb-land/build -R landscape                       # 25/25, 12.6 s
ctest --test-dir /tmp/xtb-land/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'   # 12/12
```

**M0/M1 必须执行的验证命令**（实现阶段）：

```bash
cmake -S . -B /tmp/xtb-build-ls -DWITH_CPCMX=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/xtb-build-ls -j
ctest --test-dir /tmp/xtb-build-ls --output-on-failure -R landscape
```

## 附录 B：本计划相对 R05 §3.1 的差异清单

| 差异 | 内容 | 理由 |
|---|---|---|
| 新增 `types/conv.f90` | 四判据 + 等级表独立成模块 | 被 opt/scan/ts/irc 四方共用；单独成模块便于 `test_landscape_conv.f90` 独立测试 |
| 新增 `types/updater.f90` | Bofill/BFGS/Powell/SR1 更新独立 | 与 provider（Hessian 来源）语义正交；D3 明确列出 4 种更新 |
| 新增 `tasks/*.f90` | 每个任务一个 driver | 避免 `landscape_driver.f90` 膨胀成 1000+ 行的巨型 select；`tasks/ts.f90` 需容纳 7 种方法的参数校验 |
| 新增 `optimize/linesearch.f90`、`optimize/trust.f90` | 线搜索与 trust 状态机抽出 | 被 sd/cg/lbfgs/bfgs/rfo/prfo/bprfo/dimer 共用；避免 8 处重复实现 |
| 新增 `path/gsm.f90` | 与 `string.f90` 分离 | R05 §3.1 已列出两者；GSM 的 CI/收敛包装与 string 的生长逻辑职责不同 |
| 新增 `irc/corrector.f90` | DWI + mBS + LQA 传播共享 | 四种 IRC 共享同一校正内核（R01 §3.4 的共同骨架） |
| 不采用嵌套 `CMakeLists.txt` | `src/landscape/` 只有 1 个构建文件 | 减少 10+ 个样板文件与作用域错误风险；与 `src/CMakeLists.txt:113-119` 列 `model_hessian/*` 的既有风格一致 |
| `coords/*` 保留但 TS/IRC 不依赖 | 只服务 scan 与 Hessian 变换 | 见 §11 的排除理由 |
