# 01 — ANCopt / scan 的可剥离性（调查员 A）

- 仓库：`/home/owenchan/work_path/coding/fortran/xtb`，HEAD `24c069f`（上游 grimme-lab/xtb 6.7.1 + 已交付的 `src/landscape`，M0..M7）
- 性质：**只调查**。本报告之外没有改动任何源码/构建/测试。
- 参照二进制：`/home/owenchan/programs/xtb/bin/xtb`（6.7.1 edcfbbe，静态，无 landscape）
- 本构建：`/tmp/xtb-land/build/xtb`（只读执行，输出落在 `/tmp/xtb-invest-A/`）

> **一句话结论：套件不是 ANCopt 的超集；ANCopt 只能「有条件」手术式移除；`scan_driver.f90` 可删，但 `scanparam.f90` 不可整体删——它不是 scan 的实现，而是约束/限制层的基础设施。**

---

## 0. 证据来源与可信度分级

| 证据类型 | 含义 | 本报告标记 |
|---|---|---|
| 实测 | 真的跑了二进制/编译器 | 直接给数字 |
| 编译器验证 | 用 `gfortran -fsyntax-only` + 删 `.mod` 得到「谁编译失败」 | 见 §7 方法 |
| 静态阅读 | 只读代码，未跑 | 标 `[静态]` |
| 无法确认 | 需要外部程序/环境，本机没有 | 标 `[未验证]` |

**没有实测的地方我会明说。** 本项目历史上已有 5 次静态结论被实测推翻，本报告在 §6 也证伪了任务书里的若干前提。

---

## 1. ANCopt 侧能力清单（穷举）

### 1.1 文件与入口

| 文件 | 行数 | 模块 | 作用 |
|---|---|---|---|
| `src/optimizer.f90` | 1559 | `xtb_optimizer` | ANCopt 主体：`ancopt`/`relax`/`modhes`/`get_optthr` |
| `src/geoopt_driver.f90` | 225 | `xtb_geoopt` | `geometry_optimization`：**引擎分派器**（不是 ANCopt 本身） |
| `src/relaxation_engine.f90` | 1576 | `xtb_relaxation_engine` | 另外三个引擎：`fire`/`l_ancopt`/`inertial_relax`/`lbfgs_relax` |
| `src/bias_path.f90` | 928 | `xtb_biaspath` | `p_run_path`：RMSD 偏置 push/pull 路径搜索 |
| `src/scan_driver.f90` | 142 | `xtb_scan` | `relaxed_scan`：**`$scan` 的执行器** |
| `src/bfgs.f90` | 186 | `xtb_bfgs` | `bfgs`/`powell` 更新公式（ANCopt 用） |
| `src/type/anc.f90` | 504 | `xtb_type_anc` | `tb_anc`：近似简正坐标（ANC）类型 |

`geometry_optimization` 是分派器，按 `set%opt_engine` 选四个引擎之一（`src/geoopt_driver.f90:152-176`）：

```
p_engine_rf        = 1  -> ancopt          (ANCopt, 默认)
p_engine_lbfgs     = 2  -> l_ancopt        (L-ANCopt)
p_engine_inertial  = 3  -> fire            (FIRE)
p_engine_pbc_lbfgs = 4  -> relax_pbc       (PBC LBFGS, src/lbfgs_anc/*)
```

`p_engine_*` 定义：`src/setparam.f90:77-80`；CLI 无选择器，只能通过 xcontrol `$opt engine=` 设置（`src/set_module.f90:1885-1891`）。PBC + GFN-FF 时 main.F90 强制 `pbc_lbfgs`（`src/prog/main.F90:896-898`）。

### 1.2 优化算法（`ancopt` + `relax`）

- **ANC 坐标 + RFO（rational function optimisation）**：`src/optimizer.f90:622` `relax`，RFO 五步式在 `:900-931`（`Aaug` 增广 Hessian → 本征求解 → 除以最后一元）。
  - 求解器二选一：`solver_sspevx`（精确/小体系，`:996`）或 Davidson（`:1043` 起，`nvar1>=50` 时）；`set%optset%exact_rf` 控制（`src/optimizer.f90:911-917`）。
- **微迭代外层循环**：`ancopt` 的 `ANC_microiter`（`:432-556`），每轮重建 ANC；`maxmicro` 默认 20，动态放大到 `2*micro_opt`（`:548`）；`micro_opt` 来自 `set%optset%micro_opt`（`src/setparam.f90:265`）。
- **Hessian 更新**：`iupdat=0` → `bfgs`，`iupdat=1` → `powell`（`:884-890`）；`set%tsopt` 时强制 Powell + `hlow>=0.25`（`:341-345`）。
- **trust radius / 最大位移**：`maxd = maxdispl`（`set%optset%maxdispl_opt`，默认 1.0，`src/setparam.f90:267`），逐分量截断（`:932-938`）。
- **步长 `alp` 动态放大**：按 `gnorm` 分档 1.0/1.5/2.0/3.0（`:872-881`）。
- **动态 SCC 精度**：按 `gnorm` 把 `acc` 放大 1×/3×/6×（`:833-841`）。
- **收敛判据（2 条）**：`|ΔE| < ethr` **且** `|g| < gthr`（`:847-849`），阈值由 `get_optthr` 按 `optlev` 给出（`:48-119`）。**没有位移判据**。
- **能量/梯度平均**：`set%optset%average_conv`（默认 `.false.`），TM 计算器走 `load_turbomole_log`（`:347-357`, `:1446-1484`）。

### 1.3 约束 / FIX / 扫描坐标 / wall / 边界 —— **关键：谁消费**

| 输入块 | 解析位置 | 消费位置 | 是 ANCopt 的功能吗？ |
|---|---|---|---|
| `$constrain`（`potset`） | `src/constrain_param.f90:386` `set_constr` | **计算器**：`src/xtb/calculator.f90:293`、`src/tblite/calculator.F90:551`、`src/gfnff/calculator.f90:267`、`src/extern/{orca,turbomole,mopac,driver}.f90` 各自 `constrain_pot(potset,...)` | **否**。这是 calculator 层，`--lopt` 一样吃 |
| `$fix`（`fixset`） | `src/constrain_param.f90:272` `set_fix` | **双消费**：① 计算器把固定原子梯度置零 `src/xtb/calculator.f90:304-306`；② **ANCopt 额外**把 `nvar = nat3-3*fixset%n-3`（`src/optimizer.f90:367-371`）并用 `trproj(...,-1,...)` 投影掉固定模式（`:501`） | **部分**。见 §5 实测差异 |
| `$scan`（`scan_list`/`nscan`） | `src/constrain_param.f90:844` `set_scan` | **`relaxed_scan`**：`src/scan_driver.f90:77-119`，由 `src/prog/main.F90:914-916` 在 anyopt 之后调用 | **是**。ANCopt 家族独有 |
| `$wall`（`wallset`/`sphere`） | `src/constrain_param.f90:949` `set_wall` | **计算器**：`cavity_egrad`，`src/xtb/calculator.f90:295` 等 | **否**，calculator 层 |
| `$metadyn` | `src/constrain_param.f90:1429` | 计算器 `metadynamic(...)`，`src/xtb/calculator.f90:296-297` | 否 |

**结论：`$constrain`/`$wall`/`$metadyn` 完全不属于 ANCopt；`$fix` 只在「自由度收缩」这一半属于 ANCopt；只有 `$scan` 真正属于 ANCopt 家族。**

### 1.4 `--opt` 之外的入口：谁经过 ANCopt

`anyopt` 分组（`src/prog/main.F90:314-316`）：
```
anyopt = (runtyp==p_run_opt) .or. (runtyp==p_run_ohess) .or. (runtyp==p_run_omd)
         .or. (runtyp==p_run_screen) .or. (runtyp==p_run_metaopt)
```

| runtyp | 值 | 经过 ANCopt？ | 独立算法还是包装？ | 证据 |
|---|---|---|---|---|
| `p_run_opt` | 4 | 是 | `geometry_optimization` 分派到 `ancopt` | `main.F90:906`, `geoopt_driver.f90:152` |
| `p_run_ohess` | 7 | 是（先 opt 再 freq） | ANCopt + `main_freq` | `main.F90:1239-1243`, `:1245` |
| `p_run_omd` | 8 | 是（先 opt 再 MD） | ANCopt + `md` | `main.F90:1239`, `:1297-1315` |
| `p_run_screen` | 11 | 是 | 多结构批量 `screen`（内部调 `geometry_optimization`） | `main.F90:1381-1386`, `screening.f90:147` |
| `p_run_metaopt` | 15 | 是 | 反复随机化 + `geometry_optimization` 的构象搜索（**不是 MD**） | `main.F90:1324-1366` |
| `p_run_path` | 10 | 是 | `bias_path`，内部直接调 `ancopt`（`bias_path.f90:230,390`）与 `geometry_optimization` | `main.F90:1369-1378` |
| `p_run_modef` | 13 | 是 | `modefollow`，内部反复调 `geometry_optimization`，靠 `.xtbtmpmode` 开模式跟随 | `main.F90:1389-1397`, `modef.f90:157,298,341,455,491` |
| `p_run_mdopt` | 14 | 是 | `mdopt`，沿 `xtb.trj` 逐帧 `geometry_optimization` | `main.F90:1400-1405`, `mdoptim.f90:89` |
| `p_run_bhess` | 71 | 是（`get_kopt`） | 偏置 Hessian：`get_kopt` 内部 `geometry_optimization` | `main.F90:786`, `getkopt.f90:142` |
| `p_run_md` | 6 | 否 | `md`（MD 本身） | `main.F90:1297` |
| `p_run_hess` | 5 | 否 | `numhess` 直接 | `main.F90:1245` |
| `p_run_grad` | 3 | 否 | 数值梯度 | — |

**注意：`p_run_metaopt` 不跑 MD**（读代码：随机扰动 + `geometry_optimization` 循环，`main.F90:1338-1363`）。任务书把它归入「MD 相关」不准确。

### 1.5 与 extern / MD / metadynamics 的耦合

- **extern**：`TOrcaCalculator`/`TTMCalculator`/`TMopacCalculator`/`TDriverCalculator` 都 `extends(TCalculator)` 并实现 `singlepoint`（`src/extern/orca.f90:45,52`；`turbomole.f90:49,55`；`mopac.f90:46,50`；`driver.f90:45,49`）。外部程序只提供 E/G，优化仍由 xtb 侧驱动。
  - `optimizer.f90` 只在一处直接依赖 extern：`use xtb_extern_turbomole, only: TTMCalculator`（`:23`），用于 `average_conv` 的 `load_turbomole_log`；`relaxation_engine.f90:412` 同。
- **MD**：`src/dynamic.f90`（`xtb_dynamic`, 957 行）与 ANCopt 无直接耦合；耦合点是 `main.F90`（`p_run_omd` 先 opt 后 md）和 `p_run_mdopt`（读 `xtb.trj`）。
- **metadynamics**：`src/metadynamic.f90`（`xtb_metadynamic`）是**势函数**，被所有计算器消费（`src/xtb/calculator.f90:41,296`），**不依赖 ANCopt**。
- **`.xtbtmpmode`**：模式跟随的二进制重启文件，写于 `modef.f90:280,324,569`，读于 `optimizer.f90:374`，删于 `modef.f90:436`/`bias_path.f90:192`。这是 ANCopt 与 modef/path 之间的隐式接口。

### 1.6 输入/输出契约

| 文件 | 谁写 | 证据 |
|---|---|---|
| `xtbopt.log` | `geometry_optimization`（轨迹，每 cycle 一帧） | `geoopt_driver.f90:120-128`；帧写于 `optimizer.f90:801` |
| `xtbopt.xyz` | `main.F90`（收敛几何） | `main.F90:1239-1243,1273-1281` |
| `.xtboptok` / `NOT_CONVERGED` | `geometry_optimization` 哨兵文件 | `geoopt_driver.f90:112-113,183-186` |
| `xtblast.xyz` | `main.F90`（失败时的最后几何） | `main.F90:919-928` |
| `xtbscan.log` | `relaxed_scan` | `scan_driver.f90:75-76` |
| `xtbrestart` | `main.F90`（波函数重启） | `main.F90:1412-1419` |
| `.xtbtmpmode` | modef（见上） | — |

- **`--copy`**：`main.F90:1596` 设 `copycontrol`，透传给 `rdcontrol(xcontrol, env, copy_file=copycontrol)`（`main.F90:330`），作用是把输入文件「镜像」一份（`set_module.f90:748-750,783+`）。与 ANCopt 无关，删 ANCopt 不影响。
- **`$hess` 数值键失效**（AGENTS.md §6.3）：`set%accu_hess`/`set%step_hess` 读入在 `set_module.f90:2191,2194`，只有 `--copy` 打开镜像时才真正写回；`modhes` 的模型 Hessian 路径并不使用这两个键（`optimizer.f90:1227-1319` 全文未出现 `step_hess`/`accu_hess`）。**与本次剥离无关**，但说明 `$hess` 与 ANCopt 的耦合比想象的弱。

### 1.7 收敛判据与设置来源

`src/type/setvar.f90:74-99` 的 `ancopt_setvar`（实例 `set%optset`，`src/setparam.f90:263-269`）：

| 字段 | 默认 | 用在哪 |
|---|---|---|
| `optlev` | 0（normal） | `get_optthr` → ethr/gthr/maxcycle/acc |
| `micro_opt` | 20 | 微迭代数 |
| `maxoptcycle` | 0 | 外层最大 cycle |
| `maxdispl_opt` | 1.000 | trust radius |
| `hlow_opt` | 0.010 | 负本征值下限 |
| `exact_rf` | .false. | RFO 求解器 |
| `average_conv` | .false. | 能量/梯度平均 |

另用 `set%mhset`（模型 Hessian：`p_modh_old/lindh_d2/lindh/swart/gff/read`）、`set%tsopt`、`set%linear`。

---

## 2. landscape 套件能力清单（穷举）

`src/landscape/`：45 个 `.f90`，24,391 行。`optimize/**` + `tasks/opt.f90`：

| 文件 | 行数 | 内容 |
|---|---|---|
| `optimize/driver.f90` | 582 | `landscape_optimize_model`：宏迭代、算法分派、收敛、停滞计数、SD 回退 |
| `optimize/sd.f90` | 47 | 最速下降 |
| `optimize/cg.f90` | 167 | 共轭梯度 |
| `optimize/lbfgs.f90` | 180 | L-BFGS（memory 默认 5） |
| `optimize/bfgs.f90` | 158 | BFGS |
| `optimize/diis.f90` | 207 | GDIIS |
| `optimize/rfo.f90` | 235 | RFO（P-RFO 式，trust radius） |
| `optimize/line_search.f90` | 131 | Armijo 回溯线搜索 |
| `optimize/hessian_update.f90` | 294 | Bofill/BFGS/SR1/Powell 更新 |
| `tasks/opt.f90` | 260 | `--lopt` 任务驱动 + JSON |

**支持**（`src/landscape/types/settings.f90:425-486`）：
- 6 种算法：sd/cg/lbfgs/bfgs/diis/rfo（`:79-84`）
- Hessian 来源：`numerical`（中心差分）/ `model`（Lindh-D2）/ `file`（`:373-374`）
- Hessian 更新：Bofill/BFGS/SR1/Powell（`:439`）
- trust radius（`:432-449`）、线搜索（`:443`）、GDIIS 参数、`recalc` 重算 Hessian 间隔
- **4 条收敛判据**：`e_tol`、`g_max`、`g_rms`、`d_max`、`d_rms`（`:1000-1006`）；级别 `superloose/loose/normal/tight/vtight`（`:1024-1056`）
- 停滞检测（`driver.f90` `stagnate_patience=10`）、RFO 拒绝后 SD 回退并计数（`rfo_reject_patience=3`）
- 输出 `xtbopt.xyz` + `xtb.trj`（`types/log.f90:74,87`）、`--ljson`

**不支持**（明确点名）：
- ❌ `$scan` 块的执行（`--lopt` 静默忽略，见 §5 实测）
- ❌ 单次运行完成 opt+hess（无 `--ohess` 等价物；`--lvib` 不优化，`tasks/vib.f90:236-242` 只会对非驻点报警告）
- ❌ `.xtboptok` / `NOT_CONVERGED` / `xtblast.xyz` 输出契约（实测：`--lopt` 不产生）
- ❌ `xtbopt.log`（`--lopt` 的轨迹叫 `xtb.trj`）
- ❌ `$fix` 的自由度收缩（只靠梯度置零，见 §5 rfo 反例）
- ❌ PBC / 晶格优化
- ❌ MD 耦合、metadynamics 优化、构象搜索、批量 screening
- ❌ RMSD 偏置路径搜索（`p_run_path`）、模式跟随（`p_run_modef`）
- ❌ `.xtbtmpmode` 模式跟随重启

---

## 3. 超集判定（核心）

### 3.1 逐能力对照表

| # | ANCopt 能力 | 套件有？ | 替代/代价 |
|---|---|---|---|
| 1 | RFO/ANC 最小化 | ✅ `--lopt --lopt-engine rfo` | 等价类别；实测水分子两者能量一致到 ~3e-9 Eh |
| 2 | L-BFGS / FIRE / PBC-LBFGS / L-ANCopt | ✅ lbfgs；❌ FIRE/PBC；L-ANCopt≈lbfgs | PBC 优化无替代 |
| 3 | BFGS / Powell Hessian 更新 | ✅ BFGS + Bofill/SR1/Powell | 覆盖 |
| 4 | 微迭代重建 ANC | ❌（有 `recalc` 定期重算 Hessian，语义不同） | 算法差异，非缺口 |
| 5 | trust radius / max displacement | ✅ | 覆盖 |
| 6 | 动态 SCC 精度 | ❌（固定 `acc`，`engine.f90`） | 缺一个自适应；成本优化项 |
| 7 | 2 条收敛判据（E, gnorm） | ✅ 5 条判据（含位移） | 超集 |
| 8 | 模型 Hessian 初猜（Lindh/Swart/GFNFF） | ✅ Lindh-D2（`model`）；❌ Swart/GFNFF | 部分缺口 |
| 9 | 读 `$hess`/`hessian` 文件 | ✅ `--lopt-hessian-file` | 覆盖 |
| 10 | trproj 投影平移/转动 | ✅（Eckart 投影，数值 Hessian 提供器） | 覆盖 |
| 11 | 线性分子 3N-5 | ✅（`vib/modes.f90`；优化层无显式处理）`[静态]` | 需复核 |
| 12 | `$constrain` | ✅（计算器层，实测水 O–H 1.00394 Å） | 覆盖 |
| 13 | `$fix` | ⚠️ 部分（lbfgs/bfgs/diis/cg 精确定住；**rfo 漂移 0.18 Å**） | **反例，见 §3.2** |
| 14 | `$wall` | ✅（计算器层 `cavity_egrad`）`[静态]` | 覆盖 |
| 15 | `$scan` 执行 | ❌（`--lscan` 是**另一套**实现，输入方式不同） | 见 §5 |
| 16 | `--ohess`（opt+hess 一次） | ❌ | 可分两步：`--lopt` → `--lvib xtbopt.xyz`（实测通过） |
| 17 | `--bhess`（偏置 Hessian） | ❌ | 无替代 |
| 18 | `--path`（RMSD push/pull） | ❌（`--lts` 是 NEB/string，不是同一算法） | 无替代 |
| 19 | `--modef`（模式跟随构象搜索） | ⚠️ M4 的 eigenfollow 是 TS 用，不是构象搜索 | 目的不同 |
| 20 | `--screen`（批量筛选） | ❌ | 可脚本化 |
| 21 | `--mdopt` / `--omd`（MD 耦合） | ❌ | D2 已排除 MD |
| 22 | `--metaopt`（构象搜索） | ❌ | 可脚本化（重复 `--lopt` + 随机化） |
| 23 | extern 外部程序嵌入优化 | ✅ 结构上支持（引擎对 `class(TCalculator)` 泛型，`engine.f90:531` 调 `singlepoint`；extern 计算器实现 `singlepoint`） | `[未验证]`（本机无 ORCA/TM/MOPAC） |
| 24 | `.xtboptok`/`NOT_CONVERGED`/`xtblast.xyz` | ❌ | 脚本兼容性缺口 |
| 25 | `xtbopt.log` 轨迹名 | ❌（叫 `xtb.trj`） | 工具链兼容性缺口 |
| 26 | `.xtbtmpmode` 重启 | ❌ | 无替代 |
| 27 | 能量/梯度平均（average_conv） | ❌ | 无替代 |
| 28 | TS 搜索 / IRC / scan / freq / 热化学 | ❌（ANCopt 没有） | **套件独有（这才是真超集部分）** |

### 3.2 明确回答：**不是超集**

**反例 1（实测）：`--lopt` 静默忽略 `$scan`。**
同一 `$constrain`+`$scan` 输入：
- `--lopt`：E = −5.063359810332 Eh，无 `xtbscan.log`，结果与「只有 `$constrain`」逐位相同。
- `--opt`：产生 `xtbscan.log`，3 个扫描点（本构建与参照二进制都是 3 点）。
证据：`/tmp/xtb-invest-A/F_lopt_scan/`、`/tmp/xtb-invest-A/our_opt_scan/`。

**反例 2（实测）：`--lopt-engine rfo` 下 `$fix` 失效。**
`$fix atoms:1` 固定 O 原子（初始 z=−0.735 Å）：

| 引擎 | 收敛后 O 的 z | 是否定住 |
|---|---|---|
| lbfgs | −0.73500000000000 | ✅ |
| bfgs | −0.73500000000000 | ✅ |
| diis | −0.73500000000000 | ✅ |
| cg | −0.73500000000000 | ✅ |
| **rfo** | **−0.91773685597219**（漂移 0.183 Å） | ❌ |

两次重复完全一致（确定性）。机制：套件只靠计算器把固定原子梯度置零（`src/xtb/calculator.f90:304-306`），而 RFO 用带交叉项的 Hessian 求步，梯度为零不等于位移为零。ANCopt 通过 `nvar` 收缩 + `trproj` 投影（`optimizer.f90:367-371,501`）从结构上排除固定模式。

**反例 3：无 `--ohess`。** 需要两条命令，且 `--lvib` 对非驻点几何只报警告（`tasks/vib.f90:236-242`）。

**反例 4：输出契约不同。** 实测 `--lopt` 目录：`xtbopt.xyz`, `xtb.trj`, 无 `xtbopt.log`/`.xtboptok`；`--opt` 目录：`xtbopt.log`, `.xtboptok`, `xtbopt.xyz`（+`xtbscan.log`）。

**真超集部分**：TS（PRFO/BPRFO/dimer/NEB/CI-NEB/AutoNEB/string）、IRC（GS/LQA/HPC/EulerPC）、scan（relaxed/rigid/1D/2D）、freq/热化学、JSON、更丰富的 Hessian 更新——这些 ANCopt 完全没有。

---

## 4. 剥离方案与影响面（三档）

### 方法说明（§7 有细节）
「谁会编译失败」用**编译器验证**得到：从基线构建的 `.mod` 拷贝中删掉某个模块的 `.mod`，再对全部 `src/**/*.f90` 跑 `gfortran -fsyntax-only`，收集 `Cannot open module file`。这给出**直接消费者**（Fortran 模块是编译期依赖，直接消费者 = 级联根）。

### Tier A — 可安全删除（前提：接受放弃对应能力）

| 文件 | 行数 | 模块 | 直接消费者（编译器验证） | 删除后连带失败 |
|---|---|---|---|---|
| `src/optimizer.f90` | 1559 | `xtb_optimizer` | `geoopt_driver.f90`, `relaxation_engine.f90`, `bias_path.f90` | 3 个消费者 |
| `src/relaxation_engine.f90` | 1576 | `xtb_relaxation_engine` | `geoopt_driver.f90` | 1 |
| `src/geoopt_driver.f90` | 225 | `xtb_geoopt` | `bias_path`, `docking/search_nci`, `getkopt`, `gfnff/struc_converter`, `mdoptim`, `modef`, `prog/main`, `scan_driver`, `screening`（9 个） | 9 |
| `src/bias_path.f90` | 928 | `xtb_biaspath` | `prog/main` | 1 |
| `src/scan_driver.f90` | 142 | `xtb_scan` | `prog/main` | 1 |
| `src/modef.f90` | 578 | `xtb_modef` | `prog/main` | 1 |
| `src/mdoptim.f90` | 106 | `xtb_mdoptim` | `prog/main` | 1 |
| `src/screening.f90` | 324 | `xtb_screening` | `prog/main` | 1 |
| `src/getkopt.f90` | 152 | `xtb_kopt` | `prog/main` | 1 |
| `src/bfgs.f90` | 186 | `xtb_bfgs` | `optimizer.f90`, `relaxation_engine.f90` | 2 |
| `src/type/anc.f90` | 504 | `xtb_type_anc` | `optimizer.f90` | 1 |
| `test/unit/test_optimizer.f90` | ~160 | `test_optimizer` | `test/unit/main.f90:56` | 1 |

合计 **≈6,400 行 src + 1 个单测**。

⚠️ **`geoopt_driver.f90` 同时提供 PBC-LBFGS 与 FIRE 引擎**（`geoopt_driver.f90:160-176`）。删掉它就等于放弃 `--opt` 的 PBC 优化与 FIRE，套件没有替代。这是**必须显式做的产品决策**。

### Tier B — 必须保留（共享基础设施，删了会破坏套件或核心）

| 文件 | 行数 | 为什么必须留 |
|---|---|---|
| `src/scanparam.f90` | 440 | 宿主是 `potset`（约束势集合）+ `valconstr`/`nconstr`/`atconstr`/`fcconstr`/`springexpo`/`maxconstr`/`lconstr_all_*`/`zconstr`。**16 个翻译单元**直接依赖（编译器验证）：`constrain_param`, `constr`, `docking/search_nci`, `dynamic`, `extern/{driver,mopac,orca,turbomole}`, `gfnff/calculator`, `prog/dock`, `prog/main`, `scan_driver`, `set_module`, `splitparam`, `tblite/calculator`, `xtb/calculator` |
| `src/constrain_pot.f90` | 388 | `xtb_constrainpot`。消费者含 **`src/landscape/scan/relax_scan.f90`**（编译器验证） |
| `src/constrain_param.f90` | 1612 | `xtb_constrain_param`（`read_userdata`），`main.F90:42,473` |
| `src/fixparam.f90` | 137 | `xtb_fixparam`，23 个消费者（含计算器、hessian、freq/project、landscape 无关） |
| `src/sphereparam.f90` | 867 | `xtb_sphereparam`（wall/cavity），14 个消费者 |
| `src/splitparam.f90` | 240 | `xtb_splitparam`，22 个消费者，含 **`src/landscape/vib/thermo.f90:67`** |
| `src/metadynamic.f90` | 216 | `xtb_metadynamic`，12 个消费者（计算器势函数） |
| `src/hessian.F90` | 789 | `xtb_hessian`（`--hess`/`--thermo`/`--ohess` 用；`main/property.F90`, `prog/thermo.f90`） |
| `src/model_hessian/**` | — | `xtb_modelhessian_*`，**landscape `model` 提供器也用**（`src/landscape/types/hessian.f90`） |
| `src/dynamic.f90` | 957 | `xtb_dynamic`。若保留 MD 则留；若要删，需同时改 `prog/main`, `screening`, `gfnff/struc_converter` |

### Tier C — 建议保留 / 需单独评估

| 文件 | 说明 |
|---|---|
| `src/extern/*.f90` | 计算器实现，`--hess`/单点/`--lopt` 都可用；不要因 ANCopt 一起删 |
| `src/lbfgs_anc/*.f90` | PBC LBFGS。只被 `geoopt_driver.f90` 使用；若删 geoopt_driver，它变死代码 |
| `src/qpot.f90` | 242 行，**`qpotini`/`countfix`/`rdfix`/`fixmetal`/`getf` 在 `src/` 内无调用者** `[静态]`；但 `constrain_pot.f90` 有独立的 `qpothess2`，二者无编译依赖。疑似死代码，建议单独复核 |

### 需要同时改动的地方（全量剥离）

1. **`src/prog/main.F90`**
   - 删 `use`：`xtb_scanparam`(:38)、`xtb_dynamic`(:68)、`xtb_geoopt`(:82)、`xtb_modef`(:69)、`xtb_mdoptim`(:70)、`xtb_screening`(:71)、`xtb_biaspath`(:87)、`xtb_scan`(:91)、`xtb_kopt`(:92)、`xtb_metadynamic`(:86) —— 注意：其中 `xtb_scanparam`/`xtb_metadynamic`/`xtb_dynamic` 若保留 Tier B/C 则不能全删。
   - 删 `anyopt` 分组与执行块 `:894-935`，删 `:1239-1243`、`:1273-1281`、`:1297-1410` 各 runtyp 块。
   - 删 argparser 分支 `:2116`（`-o/--opt`）、`:2123`（`--hess` 若留则保留）、`:2129`（`--ohess`）、`:2136`（`--bhess`）、`:2170`（`--path`）、`:2177`（`--screen`）、`:2184`（`--modef`）、`:2191`（`--mdopt`）、`:3800`（`--metaopt`）。
   - 删 `:786` 的 `get_kopt` 调用（`--bhess`）。
2. **`src/setparam.f90`**：`p_run_opt=4`、`p_run_ohess=7`、`p_run_omd=8`、`p_run_path=10`、`p_run_screen=11`、`p_run_modef=13`、`p_run_mdopt=14`、`p_run_metaopt=15`、`p_run_bhess=71`。**建议保留常量**（多处 `select case` 引用），只删入口，避免大范围改 `main.F90` 的 `case` 表。
3. **`src/set_module.f90`**：`set_runtyp` 的 `case('omd'/'path'/'screen'/'modef'/'mdopt'/'metaopt')`（`:1059-1092`）、`write_set_scan`（`:539-568`）、`rdcontrol` 的 `$scan` 计数（`:816-820`）、`set_opt` 的引擎解析（`:1885-1891`）。
4. **`src/xhelp.f90`**：`--opt`(:270)、`--ohess`(:696)、`--metaopt`(:732)、`--path`(:736)、`--modef`(:740)、`--mdopt`(:858)、`--screen`(:944) 等文本。
5. **测试**：`test/unit/main.f90:56`（`test_optimizer`）、`test/unit/CMakeLists.txt:58`（`"optimizer"`）、`test/unit/meson.build:69`。`test/unit/relaxation_engine.f90` 实测只测 **PBC LBFGS**（`test_pbc_lancopt`），与 `xtb_relaxation_engine` 无关，**不要误删**。
6. **CAPI**：`test/api/c_api_example.c` 只测 `xtb_hessian`（`:318-340`），**不涉及优化**，无需改动。
7. **构建清单**：`src/CMakeLists.txt` 与 `src/meson.build`（新文件必须两处登记，删文件同理）。

### 风险等级

| 方案 | 风险 | 工作量 |
|---|---|---|
| **中间方案**：只删 CLI 入口 + 执行块，保留实现文件 | **低**。实现仍在，无模块级连带；gfortran 默认不警告未用 `use` | ~0.5–1 天 |
| **全量剥离**（Tier A） | **中—高**。跨 `main.F90`/`setparam`/`set_module`/`xhelp`/测试/两个构建清单；且必须先决定 PBC/FIRE/MD/extern 的取舍 | ~3–5 天（含回归） |
| **全量剥离 + 用套件补齐能力** | **高**。`$scan`（小）、opt+hess 链（脚本）、path/modef/metaopt/screen（大，不在 D2 范围） | ≥1–2 周 |

**中间方案完全可行**：因为 `main.F90` 只是「调用方」，删掉 `case` 与执行块后，`xtb_optimizer` 等模块不再被引用，但文件仍在、仍能编译；`setparam` 常量保留避免 `select case` 表被改。

---

## 5. 用户两个具体问题的回答

### Q1：ANCopt 能否手术般精准移除？

**有条件能。** 条件与估计：

1. 先做产品决策（不可由我代定）：
   - 是否放弃 PBC/晶格优化与 FIRE（`geoopt_driver.f90:160-176`，套件无替代）；
   - 是否放弃 `--ohess`/`--bhess`/`--path`/`--modef`/`--mdopt`/`--metaopt`/`--screen`/`--omd`；
   - 是否接受输出契约变化（无 `.xtboptok`/`xtbopt.log`/`xtblast.xyz`）。
2. 手术点：Tier A 的 11 个 src 文件 + 1 个单测（≈6,400 行），以及 §4 列出的 7 处配套改动。
3. 风险：**中—高**（跨文件、跨测试、跨构建清单）。
4. 工作量：中间方案 0.5–1 天；全量 3–5 天（不含能力补齐）。
5. **不需要**改动：`scanparam.f90` 的约束核心、`constrain_pot.f90`、计算器、`model_hessian`、landscape 套件本身（编译器验证：删 `xtb_optimizer` 不使任何 `src/landscape/**` 失败）。

**关键约束**：`geoopt_driver.f90` 是分派器，删它 = 删掉**全部** `--opt` 家族；但 `scan_driver.f90`/`modef.f90`/`mdoptim.f90`/`screening.f90`/`getkopt.f90`/`bias_path.f90` 各自只有一个消费者（`main.F90`），可以逐个摘除。

### Q2：scan 能否剥离？

**要分成两个文件回答：**

**(a) `src/scan_driver.f90`（142 行，`xtb_scan`）——能删。**
- 直接消费者只有 `src/prog/main.F90:91,916`（编译器验证）。
- 删掉后 `$scan` 块不再执行（`nscan>0` 分支消失），`--opt` 家族失去扫描能力。
- 但 **`--lscan` 不受影响**：它是 `src/landscape/scan/*` 的另一套实现（`relax_scan.f90` + `scan1d.f90` + `scan2d.f90` + `tasks/scan.f90`），写同样的 `xtbscan.log`（`tasks/scan.f90:419,468`）。

**(b) `src/scanparam.f90`（440 行）——不能整体删。**
- 实测它的 16 个直接消费者（编译器验证），其中包括**所有计算器**（`xtb/calculator.f90:36`、`tblite/calculator.F90:62`、`gfnff/calculator.f90:31`）、4 个 extern 计算器、`constrain_param.f90`、`constr.f90`、`set_module.f90`、`dynamic.f90`、`splitparam.f90`、`prog/main.F90`、`prog/dock.f90`、`docking/search_nci.f90`、`scan_driver.f90`。
- 它其实混装了两类符号：

| 类别 | 符号 | 谁用 |
|---|---|---|
| **约束/限制核心**（必须留） | `potset`, `valconstr`, `nconstr`, `atconstr`, `fcconstr`, `springexpo`, `maxconstr`, `pmf`, `zconstr`, `p_typeid_*`, `lconstr_all_*`, `init_constr`, `clear_constr`, `setup_constrain_pot`, `constrain_all_bonds/angles/torsions`, `pot_info` | 计算器（`constrain_pot(potset,...)`）、`constr.f90`、`constrain_param.f90`、`set_module.f90`、`dynamic.f90`（`zconstr`）、`docking/search_nci.f90`、`prog/main.F90` |
| **scan 任务专用**（可随 `scan_driver` 一起删） | `scan_mode`, `p_scan_sequential`, `p_scan_concerted`, `nscan`, `scan_list`, `tb_scan`, `maxscan`, `valscan`, `iconstr`, `init_scan`, `clear_scan` | `scan_driver.f90`、`constrain_param.f90:844`（`set_scan`）、`set_module.f90:539-568`（`write_set_scan`）、`dynamic.f90:238`（`nscan` 决定 confdump）、`prog/main.F90:915` |

- 因此「剥离 scan」= 把第二类从 `scanparam.f90` 拆到新模块（或删掉），并同时改 `constrain_param.f90`、`set_module.f90`、`dynamic.f90`、`main.F90`。**工作量中等（~1–2 天），但必须保留第一类。**

**(c) 我们自己的 M2 是否会被破坏？——不会（任务书前提有误）。**
编译器验证：删 `xtb_scanparam.mod` 时 **`src/landscape/scan/relax_scan.f90` 不失败**；删 `xtb_constrainpot.mod` 时**它失败**。读代码：`relax_scan.f90:59` 只 `use xtb_constrainpot, only : constrain_pot`，`:58` 用 `xtb_type_setvar::constr_setvar` 自建参数对象，模块头 `:41-46` 明确写「`xtb_scanparam` 的模块级全局（`fcconstr`, `springexpo`, `potset`, ...）故意从不触碰」。

---

## 6. 反证：被证伪的前提

| # | 任务书/父会话的前提 | 判定 | 证据 |
|---|---|---|---|
| 1 | 「`src/landscape/scan/relax_scan.f90` 也使用 `scanparam`」 | **假** | 编译器验证：删 `xtb_scanparam.mod` → `relax_scan.f90` 不失败；`grep -n "use xtb_scanparam" src/landscape/` 无结果。它用的是 `xtb_constrainpot`（`relax_scan.f90:59`）+ `xtb_type_setvar`（`:58`） |
| 2 | 「`scanparam.f90` 被 **13 个模块**使用」 | **不准** | 编译器验证是 **16 个翻译单元**（见 §4 Tier B） |
| 3 | 「`scan` 可以剥离」 | **半假** | `scan_driver.f90` 可删；`scanparam.f90` 不可整体删（约束核心 + 16 消费者） |
| 4 | 「`extern/*` 外部程序嵌入（套件完全没有此类支持）」 | **假** | 引擎对 `class(TCalculator)` 泛型并调 `singlepoint`（`engine.f90:80,531`）；`TOrcaCalculator`/`TTMCalculator`/`TMopacCalculator`/`TDriverCalculator` 都实现 `singlepoint`（`extern/orca.f90:45,52` 等）。故 `--lopt --orca` 结构上可用 `[未验证]`（本机无 ORCA/TM/MOPAC，无法实跑） |
| 5 | 「`$constrain`/`$fix`/`$wall` 是 ANCopt 消费的」 | **假** | 三者都在**计算器层**：`constrain_pot(potset,...)`（`xtb/calculator.f90:293`）、`fixset` 梯度置零（`:304-306`）、`cavity_egrad`（`:295`）。实测 `--lopt --input`（含 `$constrain`）E=−5.063359810332，与 `--opt` 的 −5.063359808188 一致 |
| 6 | 「套件是 ANCopt 的超集」 | **假** | §3.2 四个反例 |
| 7 | 「`p_run_metaopt` 属 MD 相关」 | **不准** | `main.F90:1324-1366` 是「随机化 + 反复 `geometry_optimization`」的构象搜索，不调 `md`；`metaset` 只是随机数/结构池 |
| 8 | 「`--scan` 不是独立 runtyp」 | **真**（这条对） | `grep "'--scan'" src/prog/main.F90` 无结果；无 `p_run_scan` |
| 9 | 「ANCopt 是 `--opt` 的唯一引擎」 | **假** | `geometry_optimization` 还分派 L-ANCopt/FIRE/PBC-LBFGS（`geoopt_driver.f90:152-176`） |
| 10 | 编译器与运行库来自两套工具链（背景里已标注「请独立核实」） | **本条不在我职责内，未测** | 我只用 `/usr/bin/gfortran`（GCC 12.2.0）做了语法检查，未链接 |

---

## 7. 实验记录与复现命令

### 7.1 行为实测（`OMP_NUM_THREADS=1`，输出目录 `/tmp/xtb-invest-A/`）

```bash
# 上游 --opt + $constrain + $scan（参照二进制与我们的构建都跑）
# xcontrol2:
#   $constrain
#     distance: 1, 2, auto
#   $scan
#     1: 0.9, 1.1, 3
OMP_NUM_THREADS=1 /home/owenchan/programs/xtb/bin/xtb water.xyz --gfn2 --opt --input xcontrol2   # -> xtbscan.log, 3 点
OMP_NUM_THREADS=1 XTBPATH=$PWD /tmp/xtb-land/build/xtb water.xyz --gfn2 --opt --input xcontrol2   # -> xtbscan.log, 3 点

# --lopt 忽略 $scan
OMP_NUM_THREADS=1 XTBPATH=$PWD /tmp/xtb-land/build/xtb water.xyz --gfn2 --lopt --input xcontrol2   # -> 无 xtbscan.log，E 同「只有 $constrain」

# $fix + 各引擎（见 §3.2 表）
OMP_NUM_THREADS=1 XTBPATH=$PWD /tmp/xtb-land/build/xtb water.xyz --gfn2 --lopt --lopt-engine rfo --input xfix
```

| 命令 | 结果 |
|---|---|
| `--lopt`（无 xcontrol） | E=−5.070544447327，O–H=0.95922 Å |
| `--lopt` + `$constrain` | E=−5.063359810332，O–H=1.00394 Å（**约束生效**） |
| `--opt` + `$constrain` | E=−5.063359808188 |
| 参照 `--opt` + `$constrain` | E=−5.063359808190 |
| `--lopt` + `$constrain`+`$scan` | 与「只有 `$constrain`」逐位相同，无 `xtbscan.log` |
| `--lopt` + `$fix`，lbfgs/bfgs/diis/cg | 固定原子**不动** |
| `--lopt` + `$fix`，rfo | 固定原子**漂移 0.183 Å** |
| `--lopt` → `--lvib xtbopt.xyz` | 频率 1539.51 / 3650.97 cm⁻¹（opt+hess 可分两步） |

### 7.2 编译消费者探测（本次新方法）

```bash
# 基线：拷贝父会话构建的 .mod（只读，未改 /tmp/xtb-land/build）
cp -r /tmp/xtb-land/build/include /tmp/xtb-invest-A/mods_test
# 对每个候选模块：删其 .mod，再对全部 src 文件 -fsyntax-only
#   gfortran -I<mods_test> -I<mctc-lib include> -I<repo>/include \
#            -fdefault-real-8 -fdefault-double-8 -ffree-line-length-none -fsyntax-only <file>
# 收集 "Cannot open module file"；-J 指向独立目录且每轮清空（否则 -fsyntax-only 会把 .mod 写回搜索路径，探测失效）
```

结果（直接消费者数）：

```
xtb_optimizer          -> bias_path, geoopt_driver, relaxation_engine            (3)
xtb_geoopt             -> bias_path, search_nci, getkopt, struc_converter,
                          mdoptim, modef, main, scan_driver, screening            (9)
xtb_relaxation_engine  -> geoopt_driver                                           (1)
xtb_scan               -> main                                                    (1)
xtb_biaspath           -> main                                                    (1)
xtb_modef              -> main                                                    (1)
xtb_mdoptim            -> main                                                    (1)
xtb_screening          -> main                                                    (1)
xtb_kopt               -> main                                                    (1)
xtb_type_anc           -> optimizer                                               (1)
xtb_bfgs               -> optimizer, relaxation_engine                            (2)
xtb_hessian            -> main/property, optimizer, main, thermo, relaxation_engine (5)
xtb_dynamic            -> search_nci, struc_converter, main, screening            (4)
xtb_metadynamic        -> bias_path, constr, dynamic, extern×4, gfnff/calc,
                          hessian, main, tblite/calc, xtb/calc                    (12)
xtb_scanparam          -> 16 个（见 §4 Tier B）
xtb_constrainpot       -> constr, extern×4, gfnff/calc, landscape/scan/relax_scan,
                          scanparam, tblite/calc, xtb/calc                        (10)
```

**方法学限制（必须声明）**：这只给出**直接**消费者（第一层级联根）。真正删除文件时，级联会沿依赖链继续（例如删 `geoopt_driver.f90` 会让它的 9 个消费者失败，进而它们的消费者也失败）。全量级联需要真正重建一次，本次**未做全量构建**（见 §8）。

---

## 8. 未验证 / 无法确认项（诚实清单）

1. **未做全量构建**：没有在独立构建目录里真正删文件后重建，因此「级联失败」只到第一层（编译器验证），更深层是 `[静态推断]`。
2. **extern 嵌入优化未实跑**：本机没有 ORCA/Turbomole/MOPAC，`--lopt --orca` 只做了代码论证 `[未验证]`。
3. **`$wall` 在 `--lopt` 下未实跑**：只做了代码论证（`cavity_egrad` 在计算器里）`[静态]`。
4. **线性分子（3N-5）在套件优化层的处理**：`vib/modes.f90` 有；优化层是否有等价处理未逐行核实 `[静态，未确认]`。
5. **`--lopt` 的失败退出码语义**：`tasks/opt.f90:177-183` 用 `env%error` 表示不收敛，是否与 `--opt` 的 `.xtboptok`/`NOT_CONVERGED` 语义完全等价，未逐条对比。
6. **本构建 `--opt` 与参照二进制 `--opt` 在 `$fix` 下的轨迹不同**（本构建 O 不动、参照 O 移到 −0.624 Å，见 `/tmp/xtb-invest-A/fix_opt*`）。二者应为同一份 ANCopt 代码，差异可能来自上游 commit/编译选项，**我无法确认原因**，因此 §3.2 的 `$fix` 对比只用于「套件 vs ANCopt 的设计差异」，不作为数值等价性结论。
7. **`src/qpot.f90` 是否死代码**：`qpotini`/`countfix`/`rdfix`/`fixmetal`/`getf` 在 `src/` 内无调用者 `[静态]`；可能被外部/遗留流程使用，未验证。
8. **`src/scanparam.f90` 的 `read_reference` 在 `src/` 内无调用者** `[静态]`，未进一步追查。

---

## 9. 给决策者的最短路径建议

1. **先定产品边界**：PBC/FIRE、MD 家族（`--omd`/`--mdopt`）、`--path`/`--modef`/`--screen`/`--metaopt`/`--bhess` 是否放弃。
2. **若只想去掉「重复能力」而不冒险**：采用中间方案（删 CLI 入口与执行块，保留实现），0.5–1 天，风险低，随时可回滚。
3. **若确定全量剥离**：按 Tier A 顺序删（从叶子往根：`kopt/modef/mdoptim/screening/scan_driver/bias_path` → `type/anc`+`bfgs` → `optimizer`+`relaxation_engine` → `geoopt_driver`），每步重建 + 跑 `ctest -R landscape` 与 `-R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'`。
4. **`scanparam.f90` 永远不要整体删**；要精简就先拆出 scan 专用符号，并保留 `potset` 等约束核心。
5. **不要动 landscape 套件**：编译器验证它不依赖任何 ANCopt 模块；`--lscan` 也不依赖 `scanparam`。
