# 08 — 四向能力边界调查（W1）

> **性质**：**只调查，不改代码**。本文件是本次唯一产出。
> **仓库**：`/home/owenchan/work_path/coding/fortran/xtb`，HEAD `bdd8eb8`（含 W0）。
> **本构建**：`/tmp/xtb-w1/build/xtb`（`-O2 -DNDEBUG`，`WITH_TBLITE=OFF WITH_CPCMX=OFF`，
> 与 `/tmp/xtb-w0/build` 同配置，独立目录）。
> **参照二进制**：`/home/owenchan/programs/xtb/bin/xtb`（6.7.1 `edcfbbe`，静态，无 landscape）。
> **MAPLE**：`/home/owenchan/work_path/coding/python/MAPLE`（**本机不可运行**，见 §5.7）。
> **纪律**：所有 xtb 运行 `OMP_NUM_THREADS=1`；未跑全量 ctest；未触碰 `/tmp/xtb-w0/build`。
> **证据类型**：`[实测]` = 真跑了二进制；`[代码]` = 读代码 + file:line；`[未验证]` = 环境缺失。

---

## 订正记录（W3 定点订正，2026-10）

> 依据：`09-w1-review.md`（独立复核）+ 父会话独立核实。**本节之后正文已按下列条目就地改过**，
> 表中用 `~~删除线~~` 标出的旧措辞保留可追溯性。订正**只改判断与数字，不重写报告**。

| # | 复核条目 | 位置 | 改了什么 | 依据 |
|---|---|---|---|---|
| C1 | review HIGH-1 | §0 bullet 4、§0 缺口数、§3 P1→G14、§5.7、§6#2、§8#3 | DMF 由「**永久**（需 torch 可微后端）」改为「**待补**」：`dmf.py:638` 默认 `backend="numpy"`，`:727-729` numpy 分支 `return None, None`（不加载 torch），硬依赖只有 `cyipopt`（`:23 import cyipopt`、`:1058 class VariationalPathOpt(ABC, cyipopt.Problem)`）；`_load_torch_backend()` 仅在 `backend='torch'` 时调用（`:726-731,751-759`）。⇒ 阻塞是**通用 NLP 求解器 cyipopt**，不是 MLIP，与 D2 排除它的原由一致 | review 一/五；父会话实测 |
| C2 | review MEDIUM-1 | §2.1 表头、§4.2 | `p_run_*` 由「**21 个**」改为「**24 个**」（`src/setparam.f90:197-220` 恰 24 行：prescc/scc/grad/opt/hess/ohess/bhess/md/omd/lopt/path/screen/lscan/modef/mdopt/metaopt/lts/lirc/lvib/vip/vea/vipea/vfukui/vomega）。**表本身逐行完整，只有总数写错** | `sed -n '197,220p' src/setparam.f90 \| grep -c 'p_run_'` = 24 |
| C3 | review MEDIUM-2 | §1.2 标题与表、§2 矩阵（新 row 31–38）、§3 新 G15 | 补上**整层属性/分析能力**（`--esp/--stm/--dipole/--raman/--alpha/--pop/--wbo/--molden/--lmo/--fod/--cma`）、溶剂变体（`--cosmo/--tmcosmo/--gbe/--gb`）、`--efield`、子模块（`xtb topo/info/ir`）；§1.2 撤下「穷举」自称。套件侧实现数 **0**（`grep -rniE 'esp\|stm\|dipole\|raman\|...' src/landscape/**` 无能力命中） | review 二表 #1–#8；`src/xhelp.f90:158-244`、`src/prog/main.F90:1729,1872-1942,2064,2134-2137`、`src/prog/submodules.f90:36-50`、`src/prog/primary.f90:55-75` |
| C4 | review MEDIUM-3 | §5.7「torch 的两种用法」 | 「必需 torch」集合由 3 处扩为 **6 处**：加 `ts/algorithm/BPRFO.py:17`、`ts/algorithm/dimer.py:14`、`ts/ts.py:4`（**模块级硬 import**，对比 `ts/algorithm/PRFO.py:32` 在 `try` 内）⇒ MAPLE 的 **TS 子系统无 torch 连 import 都失败**（不改变「算法可迁移」结论） | 逐行核对上述文件 |
| C5 | review LOW | §1.1（两处）、§4.1 | 引用行号订正：`getkopt`→`main.F90:821-824`（原写 786，那是 DIPRO 区）；`relaxed_scan`→`main.F90:952-954`（原写 914-916，那是数值应力张量循环） | `sed -n '821,824p;952,954p' src/prog/main.F90` |
| C6 | review LOW | §1.2、§2 row 22、§2.1 注、§4.1 | `--dock` 订正为 **`xtb dock` 子模块**（位置参数，非旗标）：`src/prog/submodules.f90:82-83` `case('dock')`；`src/prog/primary.f90:71-73`；`grep -rn "'--dock'" src/` **无命中** | 同上 |
| C7 | review LOW | §2 row 29、§2.1 注 | 「S 写 `xtb.trj`」补为「S **同时写 `xtbopt.xyz`** 与 `xtb.trj`」（`types/log.f90:74` `opt.xyz`、`:87` `.trj`，均经 `get_namespace`） | 同上 |
| C8 | review LOW | §2 row 18/19 | PBC 的 N 列由 `✅` 改为 **`⚠️`（仅 GFN1/FF）**：`[实测]` `--gfn2 --sp/--opt` exit 128 `-1- scf: Multipoles not available with PBC`（§5.4） | 报告自身 §5.4 |
| C9 | review 六 | §6 新增 #7/#8 | 把「DMF 永久依赖 MLIP」与「Native 支持 PBC 优化（对 GFN2 为假）」补进**被证伪前提**清单（原表只列 6 条，漏了这两条自相矛盾的前提） | review 六；报告 §5.4 |
| C10 | **W3 新发现** | §1.2 溶剂行、§2 row 34 | `--cosmo/--tmcosmo` **不是** tblite 专属上层：native 有内在实现 `src/solv/cosmo.f90`（`use xtb_solv_ddcosmo_core`）并走 `set_gbsa`（`main.F90:2064-2067`），但**同时**写 `tblite%solvation`（`:2069-2077`）；`--gbe/--gb` 才是 tblite 专属（`main.F90:2034,2049`）。旧报告把「隐式溶剂」一行笼统写成 GBSA/ALPB，掩盖了这个分叉。**未验证**：套件经计算器层继承 ddCOSMO 的行为（未跑） | `src/solv/cosmo.f90:19-27`、`src/prog/main.F90:2034-2077` |
| C11 | **W3 新发现** | §2 row 33、§3 表头 | （a）row 33 的 M 列不能标 ⚠️：`grep -rln 'raman\|polarizab' maple/function/dispatcher/` **无命中** ⇒ MAPLE 无极化率/拉曼，应为 ❌；（b）§3 表头的「代价」口径与行内「影响/代价」两列含义不一致，已加口径说明（P/G/E 三段统一只按「代价」估计） | `maple/function/dispatcher/` 目录列表与 grep；报告自身 §3 |
| C12 | **W3 新发现** | §0 数字、§3 | 复核说「约 14 待补 + 1-2 永久」；本次把属性/分析层也计入待补 ⇒ 最终 **15 待补 + 2 永久 + 4 环境**（见 §3 尾注的口径说明：若只看「GFN2 无法表达的物理能力」，永久 = 1，仅 P3） | 由 C1/C3 重算 |

**未改动的复核意见**：review §7「`[实测]` 无原始 stdout、不可审计」——W1 报告正文确实只有汇总表，
本订正**不伪造**原文输出；`10-w1-report-corrections.md` §4 保留该审计缺口为遗留项。

---

## 0. 摘要（先看这段）

**四者边界（一句话 + 关键文件）：**

1. **ANCopt** = `src/optimizer.f90`（`xtb_optimizer`）+ `src/relaxation_engine.f90` +
   分派器 `src/geoopt_driver.f90` + 其 6 个 ANCopt-家族任务
   （`scan_driver`/`bias_path`/`modef`/`mdoptim`/`screening`/`getkopt`）。
   它的**独占能力**是「重复的惰性 RFO 最小化 + 模式跟随 + RMSD 偏置路径」。
2. **xtb Native（非 ANCopt）** = 上游除 ANCopt 外的全部：SCF/单点/梯度、
   `--hess`（`src/hessian.F90`）、MD（`src/dynamic.f90`）、metadynamics
   （`src/metadynamic.f90`）、docking（`xtb dock` **子模块**，`src/prog/dock.f90`）、extern 嵌入
   （`src/extern/*`）、全局反应性 `--vip/--vea/--vipea/--vomega/--vfukui`、
   **PBC（`src/pbc*.f90` + `src/lbfgs_anc/**`；仅 GFN1/FF）**、gfnff（`src/gfnff/**`）、
   **属性/分析层**（`--esp/--stm/--pop/--wbo/--dipole/--raman/--alpha/...`）与
   **子模块**（`xtb info/thermo/topo/ir`）（**订正 C3/C6**）。
3. **我们的套件** = `src/landscape/**`（24,782 行，46 个 `.f90`）+ CLI
   `--lopt/--lscan/--lts/--lirc/--lvib/--ljson`（122 个参数）。它的**独占能力**是
   PES 任务链：TS（prfo/bprfo/dimer/neb/cineb/autoneb/string）、IRC（gs/hpc/lqa/eulerpc）、
   relaxed/rigid scan、模式 Hessian + 4 条收敛判据、JSON。
4. **MAPLE 中依赖 MLIP 的算法** = `maple/function/dispatcher/**`（46,330 行）。
   **关键结论：绝大多数 MAPLE 算法与势无关**（只经 ASE `Calculator` 接口取
   E/F/Hessian：`atoms.get_potential_energy()` / `atoms.get_forces()` /
   `calc.get_hessian()`），因此**可迁移**；真正**永久**依赖 MLIP 的只有 ~~DMF（torch+cyipopt）、~~
   autograd Hessian、batch-GPU blbfgs 两处（**DMF 已改判为待补，见订正记录 C1**）。

**实际缺口数**（订正后，C1/C3/C12）：见 §3 表。**15 条「待补」**（可用 GFN2/套件补齐）
+ **2 条「永久」**（GFN2 无法表达；其中只有 1 条是**物理能力**层——batch-GPU）
+ **4 条「环境缺失」**（gfnff-topo/tblite/cpcmx/外部程序 → 未验证）。
（原报告写「13 待补 + 3 永久」，见订正记录 C1/C3。）

**最值得补的 3 个缺口**（影响/代价）：
1. **PBC（周期）支持**（影响：整个材料化学分支不可用；代价：大 —— 套件是有限分子设计，
   `types/coords.f90` / `engine` 都要引入晶格）。
2. **`$scan` 执行**（影响：`--lopt` 静默换个任务，已由 W0 改为**响亮报错**；
   代价：小 —— 套件已有 `--lscan`，缺的是把 `$scan` 块映射到它）。
3. **`--ohess` 等价物（opt+hess 一次）**（影响：工具链两条命令；代价：小 ——
   套件已有 `--lopt` 与 `--lvib`，缺的是任务链）。

**证伪的前提**：**8 条**（§6；订正 C9 新增 #7 DMF、#8 GFN2-PBC 两条），最重要的一条：**参照二进制（edcfbbe）的 `--opt` 在 `$fix` 下会把
固定原子移走**（O 从 z=−0.735 Å 移到 −0.308 Å），而**我们的基座（`bleed`）与套件都不动** ——
即「ANCopt 支持 `$fix`」这个前提对**参照二进制**是假的，对**我们的基座**是真的。

**订正新增的两层缺口**（C1/C3）：① **DMF 不再是「永久」**，而是**待补**（阻塞为 cyipopt）；
② Native 矩阵补上**属性/分析层**（`--esp/--stm/--pop/--wbo/--dipole/--raman/--alpha/...`）、
溶剂变体、`--efield` 与子模块（套件侧实现数 **0**）；§1.2 的「穷举」自称已撤下。

---

## 1. 四者的精确定义

### 1.1 ANCopt（文件级归属，逐个核实）

**方法说明**：归属判据 = ① 该文件是否实现 `geometry_optimization` 分派链上的一环
（`src/geoopt_driver.f90`），或 ② 是否只被该链消费。逐文件核实：

| 文件 | 行数 | 模块 | 属于 ANCopt？ | 证据 |
|---|---|---|---|---|
| `src/optimizer.f90` | 1559 | `xtb_optimizer` | **是**（核心） | `ancopt`/`relax`/`modhes`/`get_optthr`；`geoopt_driver.f90:152-158` 分派 |
| `src/relaxation_engine.f90` | 1576 | `xtb_relaxation_engine` | **是** | `fire`/`l_ancopt`/`inertial_relax`/`lbfgs_relax`；`geoopt_driver.f90:160-176` |
| `src/geoopt_driver.f90` | 225 | `xtb_geoopt` | **是**（分派器，非算法） | `geometry_optimization`；`case(p_engine_*)` |
| `src/bfgs.f90` | 186 | `xtb_bfgs` | **是**（只被 optimizer/relaxation 用） | `optimizer.f90:884-890` 调 `bfgs`/`powell` |
| `src/type/anc.f90` | 504 | `xtb_type_anc` | **是** | `tb_anc`，只被 `optimizer.f90` 用 |
| `src/model_hessian/**` | — | `xtb_modelhessian_*` | **部分是**（也是套件 `model` 提供器） | 见备注 |
| `src/scan_driver.f90` | 142 | `xtb_scan` | **是**（`$scan` 执行器） | `main.F90:952-954`（`call relaxed_scan`，anyopt 之后；**订正 C5**，原写 914-916） |
| `src/bias_path.f90` | 928 | `xtb_biaspath` | **是**（`p_run_path`） | `bias_path.f90:230,390` 直接调 `ancopt` |
| `src/modef.f90` | 578 | `xtb_modef` | **是**（`p_run_modef`） | `main.F90:1389-1397`；`.xtbtmpmode` |
| `src/mdoptim.f90` | 106 | `xtb_mdoptim` | **是**（`p_run_mdopt`） | `main.F90:1400-1405` |
| `src/screening.f90` | 324 | `xtb_screening` | **是**（`p_run_screen`） | `main.F90:1381-1386` |
| `src/getkopt.f90` | 152 | `xtb_kopt` | **是**（`p_run_bhess`） | `main.F90:821-824`（`call get_kopt`，**订正 C5**，原写 786）；`getkopt.f90:142` |

> ⚠️ 任务书候选清单里的 **`geoopt_driver.f90` 同时提供 PBC-LBFGS 与 FIRE 引擎**
> （`geoopt_driver.f90:159-176`）——所以删它 = 放弃 `--opt` 的 PBC 优化与 FIRE；这一点调查 A 已记录。
> **`model_hessian/**` 不专属 ANCopt**：套件的 `types/hessian.f90` 也 `use xtb_modelhessian_*`
> （调查 A §4 Tier B 编译器验证）。

### 1.2 xtb Native（非 ANCopt，按 CLI/runtyp 归类）

> **订正 C3**：原标题自称「穷举」——**该自称已撤下**。本节按 runtyp / CLI 入口归类，
> 但这**不是**一份穷举的 native 能力清单：当属遗漏的**属性/分析层**（`--esp/--stm/--dipole/--raman/--alpha/--pop/--wbo/--molden/--lmo/--fod/--cma`）、
> **溶剂模型变体**（`--cosmo/--tmcosmo/--gbe/--gb`）、`--efield` 与**子模块**（`xtb topo/info/ir`）
> 现已补入（见下表末 4 行与 §2 矩阵 row 31–38）。

按 runtyp / 入口归类（`src/setparam.f90:197-220` 的全部 `p_run_*`）：

| 能力 | 关键文件 | runtyp | 说明 |
|---|---|---|---|
| SCF 单点 | `src/xtb/**`、`src/tblite/**`（需 tblite）、`src/gfnff/**`、`src/iff/**`、`src/ptb/**` | `p_run_prescc`=1、`p_run_scc`=2 | |
| 数值梯度 | — | `p_run_grad`=3 | |
| Hessian/频率/热化学 | `src/hessian.F90`、`src/main/property.F90`、`src/prog/thermo.f90` | `p_run_hess`=5 | `--hess`/`--thermo` |
| MD | `src/dynamic.f90` | `p_run_md`=6 | |
| metadynamics（势） | `src/metadynamic.f90` | 由 `$metadyn` 块触发 | 计算器层消费 |
| docking | `src/prog/dock.f90`、`src/docking/**` | 无独立 runtyp；**入口是 `xtb dock` 子模块（位置参数），不是 `--dock` 旗标**（订正 C6：`submodules.f90:82-83`、`primary.f90:71-73`；`grep -rn "'--dock'" src/` 无命中） | |
| extern 嵌入 | `src/extern/{driver,mopac,orca,turbomole}.f90` | `p_ext_*`（`setparam.f90:183-195`） | 外部程序提供 E/G |
| 全局反应性 | `src/main/property.F90` 等 | `p_run_vip`=100、`vea`=101、`vipea`=102、`vfukui`=103、`vomega`=104 | |
| PBC 单点/优化 | `src/pbc*.f90`、`src/lbfgs_anc/**` | 由 `mol%npbc>0` + `$opt engine=pbc_lbfgs` | `geoopt_driver.f90:159-168` |
| 约束 | `src/constrain_pot.f90`、`src/constrain_param.f90`、`src/fixparam.f90`、`src/sphereparam.f90` | `$constrain`/`$fix`/`$wall` | **计算器层**，非 ANCopt |
| **属性/分析层**（新增，C3） | `src/main/property.F90`、`src/xtb/printoutput.f90` | `p_run_scc` 内的 write 旗标；`--alpha/--raman` 为 `set_elprop` | `--esp`/`--stm`（`xhelp.f90:158,161`；`main.F90:1872,1876`）、`--pop/--wbo/--dipole/--molden/--lmo`（`xhelp.f90:219,236,225,222,239`；`main.F90:1918-1930`）、`--fod`（`xhelp.f90:242`；`main.F90:1942`）、`--cma`（`xhelp.f90:215`；`main.F90:1880`）、`--alpha/--raman`（`xhelp.f90:233,228`；`main.F90:2134,2137`） |
| **溶剂模型变体**（新增，C3/C10） | `src/solv/{cosmo,ddcosmo,*}.f90`（内建 ddCOSMO）；`tblite%solvation`（tblite） | `--cosmo/--tmcosmo`：`main.F90:2064-2077`（同时走 `set_gbsa` 与 `tblite%solvation`）；`--gbe/--gb`：`main.F90:2034,2049`（**tblite 专属**） | COSMO 有内建实现；GBe/GB 需 tblite |
| **`--efield`**（新增，C3） | `src/xtb/calculator.f90` 等字段消费 | `main.F90:1729` | `xhelp.f90:151-153`：「works only via tblite for the xTB Hamiltonians, or with GFN-FF and PTB」 |
| **子模块 `xtb info/thermo/topo/dock/ir`**（新增，C3） | `src/prog/submodules/*`、`src/prog/dock.f90` | 位置参数（非旗标） | `submodules.f90:67-88`（`getSubmodule`）；`primary.f90:55-75`。**注意：docking 是子模块，不是 `--dock` 旗标**（订正 C6） |

### 1.3 我们的 Fortran 套件

`src/landscape/**`（`engine/`、`optimize/`、`saddle/`、`path/`、`irc/`、`vib/`、`scan/`、
`tasks/`、`types/`、`landscape_api.f90`、`landscape_driver.f90`）。
CLI runtyp：`p_run_lopt`=9、`p_run_lscan`=12、`p_run_lts`=19、`p_run_lirc`=20、`p_run_lvib`=21。
入口：`src/prog/main.F90:989-1093`（`run_landscape`）+ `src/landscape/landscape_driver.f90:63`。

> **重要**：套件里有一个 `sp` 任务（`src/landscape/tasks/sp.f90`），但 **CLI 没有 `--lsp`**，
> `src/prog/main.F90` 里从不构造 `landscape_sp_settings` ⇒ **该任务仅 API/单测可达**
> （`test/unit/test_landscape_api.f90:83,174`）。`[代码]`

### 1.4 MAPLE 中依赖 MLIP 的算法

- 算法层：`maple/function/dispatcher/**`（133 个 `.py`，46,330 行）。
- 势层：`maple/function/calculator/**`，全部是 MLIP：
  `ani`（ANI-2x/1x/1ccx/1xnr）、`aimnet`（AIMNet2/2nse）、`mace`（off23/omol/pol）、
  `fennol`、`uma`；选择器 `set_calculator.py:_BUILTIN_NAME_TO_MODULE`。
- **没有 xTB 计算器**（`grep -i xtb maple/function/calculator/` 无结果）。
- 算法通过 **ASE `Calculator` 接口**取量：`atoms.get_potential_energy()`、
  `atoms.get_forces()`、`calc.get_hessian(atoms)`（见 §5.7 证据）。
- 计算器基类：`maple/function/calculator/calculator_base.py:266`
  `class CalcABC(ase.calculators.calculator.Calculator)`。

### 1.5 依赖图（ASCII）

```
                        src/prog/main.F90  (唯一 CLI 入口)
     ┌───────────────────────┬──────────────────────────┬──────────────────────┐
     │                       │                          │                      │
  ANCopt 家族             Native                    OUR SUITE             (无 MAPLE 入口)
     │                       │                          │
 geoopt_driver  ────┐    xtb/tblite/gfnff/iff/ptb      landscape_driver
     │              │        │  (计算器)                  │
 optimizer ── relaxation_   hessian.F90  dynamic.F90    tasks/{opt,scan,ts,irc,vib,sp}
   │  │       engine       metadynamic  prog/dock         │
 type/anc bfgs             extern/*     pbc*.f90      engine/engine.f90
     │                       │                          │  (泛型 class(TCalculator))
 scan_driver/bias_path/  特性: PBC, --vip/vea/fukui/     optimize/{sd,cg,lbfgs,bfgs,diis,rfo}
 modef/mdoptim/screening/ getkopt  --ohess/--bhess,       saddle/{prfo,bprfo,dimer,eigenfollow}
 getkopt  (每个只被       MD, docking, extern          path/{neb,cineb,autoneb,string,gsm,idpp}
 main.F90 消费)                                     irc/{gs,lqa,hpc,eulerpc,corrector}
                                                    vib/{numhess,modes,thermo}
                                                    scan/{relax_scan,scan1d,scan2d}
                                                    types/{settings,hessian(抽象),json,log,coords,constraints,results}
```

**唯一的跨层耦合点**：ANCopt/Native/套件共享 **计算器层**（`mctc-calculator`），
所以 `$constrain`/`$fix`/`$wall`/`$metadyn`/extern 对三者"天然共享"（调查 A 已证），
而**套件引擎对 `class(TCalculator)` 泛型** ⇒ 结构上可以直接吃任何计算器（含 gfnff、tblite、extern）。

---

## 2. 能力矩阵

列：**A**=ANCopt（我们的基座） **N**=xtb Native（非 ANCopt） **S**=套件 **M**=MAPLE（MLIP）。
格 = ✅有 / ❌无 / ⚠️部分 / 🚫不适用。`[实测]` 见 §5。

| # | 能力项 | A | N | S | M | 关键 file:line（S 侧） |
|---|---|---|---|---|---|---|
| 1 | 单点能量/梯度 | ✅ | ✅ | ⚠️ | ✅ | S：`tasks/sp.f90` **API-only**（无 `--lsp`）；CLI 用 N 的 `--sp` |
| 2 | Hessian（数值） | ✅ | ✅ | ✅ | ✅ | S：`vib/numhess.f90`；N：`hessian.F90`；`[实测]` `--lvib` |
| 3 | 频率/RRHO 热化学 | ✅ | ✅ | ✅ | ✅ | S：`vib/modes.f90`、`vib/thermo.f90` |
| 4 | 最小化 | ✅ | ❌ | ✅ | ✅ | S：`optimize/driver.f90`；A：`optimizer.f90:622` |
| 5 | TS 搜索（PRFO/dimer） | ❌ | ❌ | ✅ | ✅ | S：`saddle/{prfo,bprfo,dimer}.f90`；`--lts-method` |
| 6 | NEB/CI-NEB/AutoNEB/string | ❌ | ❌ | ✅ | ✅ | S：`path/{neb,cineb,autoneb,string,gsm}.f90` |
| 7 | IRC（GS/LQA/HPC/EulerPC） | ❌ | ❌ | ✅ | ✅ | S：`irc/{gs,lqa,hpc,eulerpc}.f90`；`--lirc-method` |
| 8 | relaxed / rigid scan | ✅ | ❌ | ✅ | ✅ | A：`scan_driver.f90`（`$scan`）；S：`scan/*`（`--lscan`） |
| 9 | opt+Hess 一次（`--ohess`） | ✅ | ✅ | ❌ | ❌ | A/N：`main.F90:1276-1285`（`main_geometry` + `main_freq`）；S 需两步 |
| 10 | 偏置 Hessian（`--bhess`） | ✅ | ✅ | ❌ | ❌ | A：`getkopt.f90:142` |
| 11 | RMSD 偏置路径（`--path`） | ✅ | ❌ | ❌ | ❌ | A：`bias_path.f90:230,390` |
| 12 | 模式跟随构象搜索（`--modef`） | ✅ | ❌ | ❌ | ❌ | A：`modef.f90`（`.xtbtmpmode`） |
| 13 | 构象搜索（`--metaopt`） | ✅ | ❌ | ❌ | ❌ | A：`main.F90:1361-1402` |
| 14 | 批量筛选（`--screen`） | ✅ | ❌ | ❌ | ❌ | A：`screening.f90:147` |
| 15 | MD 耦合优化（`--omd`/`--mdopt`） | ✅ | ✅ | ❌ | ✅ | A：`mdoptim.f90`；N：`dynamic.f90` |
| 16 | MD（纯） | ❌ | ✅ | ❌ | ✅ | N：`dynamic.f90` |
| 17 | metadynamics | ❌ | ✅ | ❌ | 🚫 | N：`metadynamic.f90` |
| 18 | PBC 单点 | ❌ | ⚠️ | ❌ | ✅ | N：`pbc*.f90`；**⚠️ 仅 GFN1/FF，GFN2 失败**（订正 C8）；S：`landscape_driver.f90:73-76` 报错 |
| 19 | PBC 优化（含晶胞） | ❌ | ⚠️ | ❌ | ✅ | N：`geoopt_driver.f90:159-168`（`p_engine_pbc_lbfgs`）；**⚠️ 仅 GFN1/FF，GFN2 失败**（订正 C8）；S：同上报错 |
| 20 | extern 嵌入（ORCA/TM/MOPAC/driver） | ✅ | ✅ | ⚠️ | ❌ | S：引擎泛型（`engine/engine.f90`），`[未验证]` |
| 21 | 全局反应性（vip/vea/vipea/vfukui/vomega） | ❌ | ✅ | ❌ | ❌ | N：`p_run_vip`… `setparam.f90:216-220` |
| 22 | docking | ❌ | ✅ | ❌ | ❌ | N：`prog/dock.f90`，入口为 **`xtb dock` 子模块**（非 `--dock` 旗标，订正 C6） |
| 23 | 力场（gfnff） | ❌ | ✅ | ✅ | 🚫 | N：`src/gfnff/**`；S `[实测]` `--lopt --gfnff` 可跑 |
| 24 | 约束 `$constrain`/`$fix`/`$wall` | ✅ | ✅ | ✅ | 🚫 | 计算器层（`xtb/calculator.f90:293-306`） |
| 25 | JSON 输出 | ❌ | ⚠️（`--json`） | ✅ | ❌ | S：`types/json.f90`（`--ljson`） |
| 26 | 隐式溶剂（GBSA/ALPB） | ❌ | ✅ | ⚠️ | ✅ | 计算器层（`$solvation`）；S 继承 |
| 27 | CPCM-X | ❌ | ⚠️（需 cpcmx） | ⚠️ | ❌ | `WITH_CPCMX=OFF` ⇒ 未验证 |
| 28 | 批量/GPU（batched L-BFGS 等） | ❌ | ❌ | ❌ | ✅ | M：`optimization/algorithm/blbfgs.py` |
| 29 | 输出契约 `.xtboptok`/`xtbopt.log`/`xtblast.xyz` | ✅ | ✅ | ❌ | 🚫 | S 写 `xtb.trj` **且也写 `xtbopt.xyz`**（`types/log.f90:74` = `opt.xyz`、`:87` = `.trj`，均经 `get_namespace`；订正 C7） |
| 30 | 自动微分 Hessian | ❌ | ❌ | ❌ | ✅ | M：`hessian/hessian.py:6` |
| 31 | 静电势 / STM 图（`--esp`/`--stm`） | ❌ | ✅ | ❌ | ❌ | N：`xhelp.f90:158,161`；`main.F90:1872-1878`（订正 C3，新增；套件侧 **0**） |
| 32 | 布居/键级/偶极/轨道（`--pop`/`--wbo`/`--dipole`/`--molden`/`--lmo`/`--fod`/`--cma`） | ❌ | ✅ | ❌ | ❌ | N：`xhelp.f90:215-242`；`main.F90:1880,1918-1942`（订正 C3，新增；套件侧 **0**） |
| 33 | 电性质（`--alpha` 极化率 / `--raman` 拉曼） | ❌ | ✅ | ❌ | ❌ | N：`xhelp.f90:228,233`；`main.F90:2134,2137`（订正 C3，新增）。**套件 `--lvib` 的 IR/Raman 强度恒 0**；M 无 raman/polarizab 模块（`grep -rln 'raman\|polarizab' dispatcher/` 无命中，订正 C11） |
| 34 | 溶剂模型变体（`--cosmo`/`--tmcosmo`/`--gbe`/`--gb`） | ❌ | ✅ | ⚠️ | ❌ | N：`main.F90:2034,2049,2064`（订正 C3/C10，新增）。⚠️ = 计算器层，套件**结构上继承但未验证** |
| 35 | 外电场（`--efield`） | ❌ | ⚠️ | ⚠️ | ❌ | N：`main.F90:1729`；`xhelp.f90:151-153`（**仅经 tblite / GFN-FF+PTB**；订正 C3，新增） |
| 36 | 子模块 `xtb topo`（GFN-FF 拓扑） | ❌ | ✅ | ❌ | 🚫 | `submodules.f90:42-43,79-80`；`primary.f90:65-67`（订正 C3，新增） |
| 37 | 子模块 `xtb info` / `xtb thermo` / `xtb ir` | ❌ | ✅ | ❌ | 🚫 | `submodules.f90:36-40,48-49,73-77,85-86`；`primary.f90:59,63,75`（订正 C3，新增） |
| 38 | 子模块 `xtb dock` | ❌ | ✅ | ❌ | ❌ | `submodules.f90:45-46,82-83`；`primary.f90:71-73`（订正 C3/C6，新增） |

### 2.1 runtyp 全景表

来源：`src/setparam.f90:197-220`（全部 **24** 个 `p_run_*`；订正 C2，原写 21；`sed -n '197,220p' src/setparam.f90 | grep -c 'p_run_'` = 24）+ `src/set_module.f90:1043-1103`（`set_runtyp` 映射）。
「服务者」= 谁执行；「套件覆盖」= 套件是否有等价 runtyp；「缺口等级」= 见 §3 编号。

| runtyp | 值 | CLI | 服务者 | 套件覆盖 | 缺口 |
|---|---|---|---|---|---|
| `p_run_prescc` | 1 | （内部） | Native | ❌ | 无需（套件 `sp` API-only） |
| `p_run_scc` | 2 | `--sp` | Native | ⚠️ `sp` API-only | G1 |
| `p_run_grad` | 3 | `--grad` | Native | ❌ | — |
| `p_run_opt` | 4 | `--opt` | **ANCopt** | ✅ `--lopt`（不同算法） | — |
| `p_run_hess` | 5 | `--hess`/`--thermo` | Native | ✅ `--lvib` | — |
| `p_run_ohess` | 7 | `--ohess` | ANCopt+Native | ❌ | **G2** |
| `p_run_bhess` | 71 | `--bhess` | ANCopt（`getkopt`） | ❌ | G3 |
| `p_run_md` | 6 | `--md` | Native | ❌ | D2 排除 |
| `p_run_omd` | 8 | `--omd` | ANCopt+Native | ❌ | D2 排除 |
| `p_run_lopt` | 9 | `--lopt` | **套件** | — | — |
| `p_run_path` | 10 | `--path` | ANCopt（`bias_path`） | ❌ | G4 |
| `p_run_screen` | 11 | `--screen` | ANCopt（`screening`） | ❌ | G7 |
| `p_run_lscan` | 12 | `--lscan` | **套件** | — | — |
| `p_run_modef` | 13 | `--modef` | ANCopt（`modef`） | ❌ | G5 |
| `p_run_mdopt` | 14 | `--mdopt` | ANCopt（`mdoptim`） | ❌ | D2 排除（小） |
| `p_run_metaopt` | 15 | `--metaopt` | ANCopt | ❌ | G6 |
| `p_run_lts` | 19 | `--lts` | **套件** | — | — |
| `p_run_lirc` | 20 | `--lirc` | **套件** | — | — |
| `p_run_lvib` | 21 | `--lvib` | **套件** | — | — |
| `p_run_vip` | 100 | `--vip` | Native | ❌ | G8 |
| `p_run_vea` | 101 | `--vea` | Native | ❌ | G8 |
| `p_run_vipea` | 102 | `--vipea` | Native | ❌ | G8 |
| `p_run_vfukui` | 103 | `--vfukui` | Native | ❌ | G8 |
| `p_run_vomega` | 104 | `--vomega` | Native | ❌ | G8 |

> 另有**无独立 runtyp 的 native 入口**：**`xtb dock` 子模块**（`prog/dock.f90`；订正 C6，原写 `--dock`）、
> `$scan`（`scan_driver.f90`，仅在 `anyopt` 路径执行）、PBC（`mol%npbc>0`）、
> 以及子模块 `xtb info/thermo/topo/ir`（订正 C3）。

---

## 3. 实际缺口清单

**分三类**（订正后的口径）：`待补` = 算法与势无关，可用 GFN2/套件补齐；
`永久` = 依赖可微 MLIP / GPU-batch，GFN2 无法表达；`环境` = 本机无法判定（不是能力缺口）。
「代价」按套件现有抽象复用度估计（S/M/L）。

> **订正 C1/C3/C12：本表最终计数 = 15 待补（G1–G15）+ 2 永久（P2,P3）+ 4 环境（E1–E4）。**
> 口径说明：P2 只是**实现层**永久（能力已被数值 Hessian 覆盖），如果把「永久」限定为
> 「GFN2 无法表达的物理能力」，则**永久 = 1**（仅 P3 batch-GPU 特征层）。
> 不在本表计数的矩阵行：row 34 溶剂变体与 row 35 `--efield` 是**计算器层**能力，
> 套件结构上继承（⚠️ 未验证）；row 36–38 子模块是**非 PES 能力**，不列为套件缺口。
> （原报告写「13 待补 + 3 永久」，含 P1 DMF 错判与 §1.2 穷举漏登两层。）

| # | 缺口 | 类型 | 影响 | 代价 | 建议 |
|---|---|---|---|---|---|
| G1 | 套件单点无 CLI 入口（`sp` 任务 API-only，无 `--lsp`） | 待补 | 小（native `--sp` 覆盖单点；套件只在 API 用） | S | 若要套件 JSON 单点，加 `--lsp`（`landscape_sp_settings` 已存在，接 1 个 case 即可）`[代码]` |
| G2 | `--ohess`（opt + Hessian 一次） | 待补 | 中（工具链两条命令；taxol 级两步之和 > 一步） | S | 在 `tasks/opt.f90` 末尾串 `tasks/vib.f90`；`[实测]` 两步已可用 |
| G3 | `--bhess`（偏置 Hessian，`getkopt`） | 待补 | 中（只对 TM/DFT 评审有意义） | M | 依赖 ANCopt 的 `get_kopt` 语义；低优先级 |
| G4 | `--path`（RMSD 偏置 push/pull 路径） | 待补 | 中（与 NEB 不是同一算法：RMSD 空间 vs 笛卡尔） | M/L | 复用 `path/idpp.f90` 的插值，但偏置项是新的 |
| G5 | `--modef`（模式跟随构象搜索） | 待补 | 中（套件 `saddle/eigenfollow.f90` 只服务 TS） | M | 需要 `.xtbtmpmode` 式模式锁存 |
| G6 | `--metaopt`（构象搜索） | 待补 | 中（可脚本化：重复 `--lopt` + 随机化） | M | 脚本级替代即可 |
| G7 | `--screen`（批量筛选） | 待补 | 小（可脚本化） | S | 脚本级替代 |
| G8 | 全局反应性 `--vip/--vea/--vipea/--vfukui/--vomega` | 待补 | 中（native 独占 5 个 runtyp） | M | 属性质计算，套件无 property 层（与 G15 同源） |
| G9 | PBC 单点 | 待补 | 大（整个材料化学分支不可用） | M/L | 套件 `[实测]` 报错；需 `types/coords.f90`+engine 引入晶格 |
| G10 | PBC 优化（含晶胞） | 待补 | 大 | L | native 只有 `p_engine_pbc_lbfgs`（GFN1/FF） |
| G11 | 输出契约 `.xtboptok`/`xtbopt.log`/`xtblast.xyz`/`.xtbtmpmode` | 待补 | 小（工具链兼容） | S | 套件写 `xtb.trj`（`types/log.f90:74,87`） |
| G12 | FIRE / inertial-relax 引擎、动态 SCC 精度、模型 Hessian 变体（Swart/GFNFF）、`average_conv` | 待补 | 小（算法近似项） | S | 套件有 `numerical`/`model(Lindh-D2)`，缺另外 3 种 |
| G13 | `$scan` 块执行（套件 `--lopt` 不执行，W0 后改为**响亮报错**） | 待补 | 中（工具链把 `$scan` 输入交给 `--lopt` 会直接失败） | S | 把 `$scan` 块映射到 `--lscan`（`scan_list` 已可读） |
| G14 | **DMF（Direct MaxFlux）**（订正 C1：**由「永久」改入「待补」**） | 待补 | 中（MAPLE 唯一的反应路径变分优化器） | M/L | `[代码]` `dmf.py:638` 默认 `backend="numpy"`，`:727-729` numpy 分支不加载 torch；**硬依赖仅 `cyipopt`**（`:23`、`:1058`）。⇒ 阻塞是**通用 NLP 求解器**，不是 MLIP。代价 = 提供 xTB 的 ASE 计算器 + 引入 cyipopt/Ipopt（或 Fortran 重写 NLP）。**此即 D2 当初排除它的理由**，不是「GFN2 无法表达」 |
| G15 | **属性/分析层**（`--esp/--stm/--dipole/--raman/--alpha/--pop/--wbo/--molden/--lmo/--fod/--cma`）（订正 C3） | 待补 | 中（套件侧实现数 **0**，`grep -rniE 'esp\|stm\|dipole\|raman\|...' src/landscape/**` 无能力命中） | M | 套件无 property 层；与 G8 同源。若只做 PES 任务可先不补，但矩阵不再漏登 |
| P2 | autograd Hessian | **永久**（实现层） | — | — | M：`hessian/hessian.py:6` `torch.autograd.grad`；能力可用数值 Hessian 覆盖（⇒ 非真能力缺口） |
| P3 | batch-GPU blbfgs / B-PRFO | **永久**（特征层） | — | — | M：`optimization/algorithm/blbfgs.py:2`；算法本身可迁移，batch 不可 |
| E1 | gfnff 拓扑 / tblite | 环境 | — | — | 我们的构建 **gfnff 可跑** `[实测]`；tblite `WITH_TBLITE=OFF` ⇒ 未验证 |
| E2 | CPCM-X | 环境 | — | — | `WITH_CPCMX=OFF` ⇒ 未验证 |
| E3 | extern 嵌入（ORCA/TM/MOPAC/driver） | 环境 | — | — | 无外部程序；代码级证据见 §5.6 |
| E4 | MAPLE 运行 | 环境 | — | — | `ase`/`torch`/`fairchem` 缺失 ⇒ 只做代码级分类 |

**排除项（D2 已定的实施范围，不作为本轮实施目标）**：DMF、batch-GPU blbfgs/BPRFO、ML-potential 计算器、parmfit、MD 系综。

> **订正 C1**：D2 把 DMF 排除在实施范围外，**不等于**它是一个「GFN2 无法表达」的永久缺口——
> 它在本表仍是 **G14「待补」**（阻塞是 cyipopt 不是 MLIP）。两件事不要混。

> **MD 家族的归属**：`--md`/`--omd`/`--mdopt`/`--metaopt` 在任务书里被统称「MD 相关」，
> 但 `p_run_metaopt` **不跑 MD**（`main.F90:1361-1402` 是随机化 + 反复 `geometry_optimization`），
> `p_run_mdopt` 也不跑 MD（`mdoptim.f90:89` 逐帧优化 `xtb.trj`）。只有 `--md`/`--omd` 真跑
> `src/dynamic.f90`。本表据此拆分。注：调查 A §6 已先记录此点，我复核确认。

---

## 4. runtyp 全景表

（表见 §2.1；此处补**无独立 runtyp 的 native 入口**与「新增 runtyp 的占用」）

### 4.1 无独立 runtyp 的 native 入口

| 入口 | 触发 | 服务者 | 套件覆盖 |
|---|---|---|---|
| **`xtb dock`**（子模块，非旗标；订正 C6） | `prog/dock.f90` | Native | ❌ |
| `$scan` 块 | `mol%npbc==0` 且 `anyopt`（`main.F90:952-954`；订正 C5） | ANCopt（`scan_driver.f90:77-119`） | ⚠️ `--lscan` 是另一套（`--lopt` 已改为响亮报错：`main.F90:493-503`）`[实测]` |
| PBC | `mol%npbc>0` | Native（**GFN1/FF only**，GFN2 失败；订正 C8） | ❌（`landscape_driver.f90:73-76`）`[实测]` |
| metadynamics | `$metadyn` 块 | Native（计算器层） | ❌ |
| 子模块 `xtb info/thermo/topo/ir` | 位置参数 | Native（`primary.f90:55-75`） | ❌（订正 C3） |

### 4.2 runtyp 编号占用

`setparam.f90:197-220` 共 **24 个** `p_run_*`（订正 C2，原写 21）；值 1..15、19-21 已用，**16/17/18 空**；
套件新增 9/12/19/20/21；native 高值 100-104（反应性）、71（bhess）。套件新增 runtyp 与
native 无编号冲突。`[代码]`

---

## 5. 实测证据（原始输出）

所有运行 `OMP_NUM_THREADS=1`，工作目录 `/tmp/xtb-w1/work/`，
**native `--opt` 用参照二进制**、**套件用 `/tmp/xtb-w1/build/xtb`**（除非另注）。

### 5.0 构型准备

- `water_dist.xyz`：O(0.1,0.05,−0.6)，H(0.3,1.4,0.9)，H(−0.4,−1.3,0.5)（远离极小点，逼优化器做功）。
- `ch3oh_dist.xyz`：6 原子扰动甲醇。
- `water_min.xyz`：套件收敛的 H2O 极小点（`E=−5.070544446522 Eh`）。

### 5.1 `--opt`（ANCopt）vs `--lopt`（套件）\| 同任务对照

| 体系 | 引擎 | 收敛 | 最终能量 / Eh | 末梯度 / (Eh/bohr) | Kabsch-RMSD vs ANCopt / Å |
|---|---|---|---|---|---|
| H2O_dist | **ANCopt** `--opt`（参照） | CONVERGED AFTER **15** it | −5.070544307934 | 2.65e−4 | — |
| H2O_dist | `--lopt` lbfgs | steps **16** | −5.070544446522 | 5.08e−5 | 3.84e−4 |
| H2O_dist | `--lopt` rfo | steps **11** | −5.070544447820 | 6.35e−7 | 3.97e−4 |
| CH3OH_dist | **ANCopt** `--opt`（参照） | CONVERGED AFTER **22** it | −8.226118185644 | 1.43e−4 | — |
| CH3OH_dist | `--lopt` lbfgs | steps **23** | −8.226118225048 | 2.69e−4 | 1.60e−3 |
| CH3OH_dist | `--lopt` rfo | steps **15** | −8.226118412195 | 1.13e−4 | 1.16e−3 |

**读法**：同任务（都在各自判据下「收敛」到同一个极小点），RMSD ≤2e−3 Å；套件 rfo 的步数更少、
末能量更低（因为套件有 4 条判据含位移，ANCopt 只有 2 条）。

**⚠️ 二进制对照污染**：`--opt` 用的是**参照 6.7.1 `edcfbbe`**，套件是我们的基座（多 156 提交）。
用**我们的基座**跑 `--ohess`（§5.3）证明二者 ANCopt 数值接近但不相同。任何「上游 vs 套件」的
数值结论都必须记住这一点。

### 5.2 `$fix` / `$constrain`（W0 刚改过套件这一块）

**`$fix atoms: 1`（固定 O）**，输入 `water.xyz`（O 初始 z=−0.735）：

| 运行 | O 的 z / Å | 是否定住 | 能量 / Eh |
|---|---|---|---|
| `--lopt` lbfgs | −0.73500000000000 | ✅ | −5.070544436053 |
| `--lopt` bfgs | −0.73500000000000 | ✅ | −5.070544447587 |
| `--lopt` diis | −0.73500000000000 | ✅ | −5.070544445761 |
| `--lopt` cg | −0.73500000000000 | ✅ | −5.070543947643 |
| `--lopt` rfo | −0.73500000000000 | ✅ | −5.070544436390 |
| `--lopt` sd | −0.73500000000000 | ✅ | −5.070543982717 |
| **`--opt`（参照 edcfbbe）** | **−0.30797685901253** | ❌ | −5.070543453746 |
| **`--opt`（我们的基座 `bdd8eb8`）** | **−0.73500000000000** | ✅ | −5.070543768737 |

⇒ 套件 6 引擎全部投影步向量、精确定住；**我们的基座 ANCopt 也定住**；只有**参照二进制**移走 O。

**`$constrain distance: 1,2,1.05`**（从 `water_min.xyz` 出发，轻约束）：

| 运行 | O–H1 / Å | 能量 / Eh |
|---|---|---|
| `--lopt` lbfgs（套件） | 0.949298 | −5.070024982109 |
| `--opt`（参照） | 0.949198 | −5.070024996089 |

⇒ 二者一致到 **1.4e−8 Eh / 1.0e−4 Å** ⇒ `$constrain` 是**计算器层**、两条路径消费一致。（约束是
软谐振子，`fc=0.05`，目标 0.90 Å 平衡在 ≈0.949 Å。）

> 反例：从**远离**极小点的 `water_dist.xyz` 出发、目标 1.05 Å 的强约束下，套件（O–H1=0.9759 Å,
> E=−5.069338668）与参照（O–H1=0.9920 Å, E=−4.875120634）落进**不同盆地**，参照在 gnorm=0.0517
> 就报「converged」——这是**收敛判据差异 + 盆地差异**，不是「能力缺失」。

### 5.3 `--ohess` vs（`--lopt` 再 `--lvib`）

**同任务对照**（大体系，**113 原子 taxol**；`--ohess`=**参照二进制**，`--lopt`/`--lvib`=**我们的构建**）：

| 任务 | 耗时 |
|---|---|
| `--ohess`（ANCopt 优化 + 数值 Hessian，一步） | **110.19 s** |
| `--lopt`（套件优化，**不含 Hessian**） | 37.05 s |
| `--lvib`（套件数值 Hessian） | 110.04 s |
| **`--lopt`+`--lvib` 之和**（与 `--ohess` 同任务口径） | **147.09 s** |

⇒ 同上任务口径下，套件的两步链比 ANCopt 的一步 **慢 ~1.34×**（`147.09 / 110.19`）。
**不要把 `--lopt` 的 37.05 s 与 `--ohess` 的 110.19 s 直接比**——前者不含 Hessian。

**小体系**（CH3OH_dist，同一构建 `--ohess` 两侧都跑了以隔离源码差异）：

| 构建 | 任务 | 耗时 | 收敛 | 最终能量 / Eh | 频率 / cm⁻¹ |
|---|---|---|---|---|---|
| 我们的 `bdd8eb8` | `--ohess` | 0.0433 s | 22 it | −8.226117321389 | 1485.11 1489.84 2918.35 2938.05 3032.87 3559.72 |
| 参照 `edcfbbe` | `--ohess` | 0.0393 s | 22 it | −8.226118185644 | 1485.11 1489.78 2918.24 2937.71 3032.95 3558.53 |

⇒ **我们的基座 vs 参照 ANCopt 本身就差 ~8.6e−7 Eh / 最多 1.19 cm⁻¹**（156 提交差异）。

**H2O 频率对照**（`--ohess`=参照 vs `--lopt`+`--lvib`=套件）：
`--ohess` 1539.16 / 3641.17 / 3649.98 cm⁻¹；`--lvib`（套件数值 Hessian + Eckart 投影）
1539.49 / 3642.94 / 3651.17 cm⁻¹。差异 ≤1.8 cm⁻¹（几何略不同 + 投影约定；与 AGENTS.md §6 的记录一致）。

### 5.4 PBC

**native（我们的基座）周期氨 `ammonia.vasp`（16 原子胞）**：

| 命令 | 结果 |
|---|---|
| `--gfn1 --sp` | exit 0，TOTAL ENERGY **−19.351964095196 Eh** |
| `--gfn1 --opt` | exit 0，**CONVERGED AFTER 8 ITERATIONS**，E=−19.359376052538 Eh |
| `--gfn2 --sp` / `--opt` | exit 128，`-1- scf: Multipoles not available with PBC` |

**套件**：`--gfn1 --lopt` on `ammonia.vasp` → exit 1，
`-1- landscape_run: landscape tasks do not support periodic boundary conditions yet`。

⇒ **native 支持 PBC（单点 + 优化）**，但 **⚠️ 仅限 GFN1/FF —— GFN2 直接报
`Multipoles not available with PBC`（订正 C8）**；**套件明确不支持且响亮报错**（非静默）。
（矩阵 row 18/19 的 N 列已由 `✅` 改为 `⚠️`。）

### 5.5 `--gfnff`（力场计算器）：套件引擎的泛型性

| 命令 | 结果 |
|---|---|
| 套件 `--gfnff --lopt --lopt-engine lbfgs` | exit 0，converged，E=−0.000271157697 Eh |
| 套件 `--gfnff --lvib` | exit 0，频率 −200.10 / 467.83 / 781.54 cm⁻¹ |
| 套件 `--gfnff --lts --lts-method prfo --lts-max-steps 5` | exit 1，`transition state search did not converge: maximum number of steps reached`（预算内未收敛，正常） |

⇒ 套件引擎对 `class(TCalculator)` 泛型，**直接吃 gfnff 计算器**。
（`src/landscape/engine/engine.f90:80,283,531`：`class(TCalculator)` + `singlepoint`）`[代码+实测]`

### 5.6 extern 嵌入（代码级，无法实跑）

- 套件引擎持 `class(TCalculator), allocatable :: calc`（`engine/engine.f90:150,283`），
  经 `xtb_single::singlepoint`（`engine.f90:531`）求值。
- extern 计算器都 `extends(TCalculator)` 并实现 `singlepoint`：
  `extern/orca.f90:45,52`、`extern/turbomole.f90:49,55`、`extern/mopac.f90:46,50`、
  `extern/driver.f90:45,49`。
- ⇒ **结构上 `--lopt`/`--lts`/`--lirc` 应当可以驱动 extern**，但**本机无 ORCA/TM/MOPAC ⇒ `[未验证]`**。

### 5.7 MAPLE（代码级分类，**本机不可运行**）

**可运行性**：

```
$ python3 -c "import ase"       -> ModuleNotFoundError
$ python3 -c "import torch"     -> ModuleNotFoundError
$ python3 -c "import fairchem"  -> ModuleNotFoundError
```

⇒ MAPLE **未运行**；以下全部是**代码级分类**。

**DMF 的后端事实（订正 C1；源码引用为 `ts/algorithm/dmf.py`）**：

| 声明 | 证据 | 结论 |
|---|---|---|
| DMF 默认**不**依赖 torch | `dmf.py:638` `backend: str = "numpy"`（注释：`tensor backend: numpy or torch`）；`:686-689` 只接受 `numpy`/`torch` | 默认 numpy |
| numpy 分支不加载 torch | `dmf.py:726-731` `_resolve_backend`：`if backend == "numpy": return None, None`；只有非 numpy 才 `_load_torch_backend()`（`:47-56`，失败时提示 “use backend='numpy'”） | torch **只是可选加速后端** |
| 硬依赖是 `cyipopt` | `dmf.py:23` 模块级 `import cyipopt`；`:1058` `class VariationalPathOpt(ABC, cyipopt.Problem)` | 通用 NLP 求解器，**非 MLIP** |
| numpy 路径的取量 | `dmf.py:753` `dmf_class = DirectMaxFlux`（numpy）；`:827` `mxflx = dmf_class(...)`；`:832` `img.calc = base_calc`；`:840,868,1787` 只调 `images[i].get_forces()` / `get_potential_energy()` | 与势无关 |

⇒ **DMF 的阻塞是引入 cyipopt/Ipopt，不是 MLIP** ⇒ 属「待补」（§3 G14），不是「永久」。

**关键证据（算法经 ASE 接口取量，与势无关）**：

| 文件 | 取量方式 | 判定 |
|---|---|---|
| `ts/algorithm/neb.py:410,596,686` | `at.get_forces()` / `at.get_potential_energy()` | 势无关 |
| `ts/algorithm/PRFO.py:366-367,720-723` | `calc.get_hessian(atoms)` / `atoms.get_forces()` | 势无关 |
| `irc/algorithm/gs.py:308-311` | `self.atoms.calc.get_hessian(self.atoms)` | 势无关 |
| `md/ensemble/nvt.py:491,538,581` | `self.atoms.get_forces()` / `get_potential_energy()` | 势无关 |
| `optimization/algorithm/LBFGS.py:166-181` | `atoms.get_forces()` / `get_potential_energy()` | 势无关 |
| `scan/algorithm/RFO.py:69-70,118` | `atoms.get_forces()` / `calc.get_hessian()` | 势无关 |
| `hessian/hessian.py:6` | `torch.autograd.grad` | **永久依赖可微势** |
| `ts/algorithm/_dmf_torch_backend.py:20-28` | vendored torch DMF + cyipopt（**仅 torch 后端**） | **待补**（订正 C1：`dmf.py:638` 默认 numpy 后端不加载 torch） |
| `optimization/algorithm/blbfgs.py:2` | `torch` GPU batch | **永久（batch 特征）** |

**torch 的两种用法**（订正 C4）：
- **可选**：`ts/algorithm/PRFO.py:32-33`、`optimization/algorithm/_common.py:55` 的 `to_numpy_f64`
  只是 `try: import torch` 的**类型转换兜底**（在 `try` 块内），无 torch 也能跑。
- **必需**（模块级硬 `import torch`，共 **6 处**）：`hessian/hessian.py:1`、
  `ts/algorithm/_dmf_torch_backend.py`、`optimization/algorithm/blbfgs.py:2`，**另加**
  `ts/algorithm/BPRFO.py:17`、`ts/algorithm/dimer.py:14`、`ts.py:4`（`from torch import Tensor`）。
  ⇒ **MAPLE 的 TS 子系统无 torch 连 import 都失败**，但这是**打包/依赖**层面的阻塞，
  **不改变**「算法本身与势无关、可迁移」的结论（torch 在那三个模块里只用于张量容器/设备选择）。

**势层**：`maple/function/calculator/` 只有 MLIP（`ani`/`aimnet`/`mace`/`fennol`/`uma`），
**没有 xTB**（`grep -ri xtb calculator/` 无结果）；选择器 `set_calculator.py:31-52`。
计算器基类 `calculator_base.py:266` `class CalcABC(ase.calculators.calculator.Calculator)`。

⇒ **结论：MAPLE 的 TS/IRC/opt/scan/MD/frequency 算法是「势无关」的**——它们只要求
「一个能给 E/F/Hessian 的 ASE 计算器」。因此**可以**用一个 xTB-backed ASE 计算器驱动；
这是「**可迁移但尚未迁移**」，不是「永久缺口」。真正永久的是 ~~DMF /~~ autograd Hessian / batch-GPU
（**订正 C1：DMF 改判为待补**；其默认 `backend="numpy"` 只吃 E/F）。

### 5.8 构建与环境校验

- 独立构建：`/tmp/xtb-w1/build`（`-O2 -DNDEBUG`，`WITH_TBLITE=OFF WITH_CPCMX=OFF WITH_TESTS=ON`）。
- `OMP_NUM_THREADS=1 ctest -R landscape` → **101/101 passed**（total 34.36 s）。
- 未跑全量 ctest（按纪律）；未触碰 `/tmp/xtb-w0/build`。

---

## 6. 被证伪的前提

| # | 前提（任务书/父会话/历史文档） | 判定 | 证据 |
|---|---|---|---|
| 1 | 「ANCopt 支持 `$fix`」——（隐含在把套件 `$fix` 与 ANCopt 对照时） | **对参照二进制 `edcfbbe` 是假** | `[实测]` 参照 `--opt` + `$fix atoms:1`：O 由 z=−0.735 移到 **−0.30798**；我们的基座与套件都保持在 −0.735。即 `$fix` 是**基座版本差异**，不是 ANCopt 内建保证 |
| 2 | 「MAPLE 算法依赖 MLIP ⇒ 无法迁移到 xtb」 | **大部分假** | `[代码]` 算法只经 ASE 接口取 E/F/Hessian（§5.7 表）；只有 ~~DMF/~~autograd-Hessian/batch-GPU 永久依赖（**订正 C1**：DMF 已移出） |
| 3 | 「套件没有单点能力 / 套件 `sp` 可从 CLI 用」 | **后者假** | `[代码]` `src/landscape/tasks/sp.f90` 存在，但 `main.F90` 从不构造 `landscape_sp_settings`；**无 `--lsp`**，仅 `test/unit/test_landscape_api.f90` 可达 |
| 4 | 「套件与 ANCopt 可以用同一二进制直接数值对照」 | **假（污染）** | `[实测]` 我们的基座 `--ohess` vs 参照 `--ohess`（CH3OH）：E 差 8.6e−7 Eh、频率差 ≤1.19 cm⁻¹ |
| 5 | 「taxol 的 `--ohess` 110 s 与 `--lopt` 37 s 可直接比」 | **假（口径不同）** | `[实测]` `--lopt` 不含 Hessian；同口径是 `lopt+lvib = 147.09 s` vs `ohess = 110.19 s` |
| 6 | 调查 A 的 `[静态]`：套件 `$fix` 在 rfo 下漂移 0.18 Å（HEAD 24c069f） | **已过时** | `[实测]` W0 后（bdd8eb8）`--lopt --lopt-engine rfo` + `$fix`：O 精确保持 −0.735 |
| 7 | **报告自身隐含前提「DMF 永久依赖 MLIP」**（§3 P1/§5.7/§8#3） | **假**（订正 C1/C9） | `[代码]` `dmf.py:638` 默认 `backend="numpy"`；`:726-731` numpy 分支 `return None, None`（不加载 torch）；硬依赖仅 `cyipopt`（`:23`、`:1058`）。报告在 #2 说「大部分算法可迁移」，却把 DMF 排除在外；实际 DMF 也属「大部分」之列 |
| 8 | **报告自身隐含前提「Native 支持 PBC 优化」**（§2 矩阵 row 18/19 标 `N ✅`） | **对 GFN2 为假**（订正 C8/C9） | `[实测]` §5.4：`--gfn2 --sp` / `--opt` exit 128，`-1- scf: Multipoles not available with PBC`；只有 GFN1/FF 可 |

---

## 7. 未验证清单（区分证据等级）

**我实测的**（`[实测]`，可复现，见 §5）：
- `--opt` vs `--lopt`：水/甲醇；收敛步数、能量、RMSD（§5.1）。
- `$fix`×6 引擎 + ANCopt（我们的基座与参照）（§5.2）。
- `$constrain` 轻/强两档（§5.2）。
- `--ohess` vs `--lopt`+`--lvib`（taxol 大体系 + CH3OH 小体系）（§5.3）。
- PBC：native `--gfn1 --sp/--opt`、`--gfn2` 报错、套件报错（§5.4）。
- 套件 × `--gfnff`（§5.5）。

**我读代码推断的**（`[代码]`，file:line 可核，未实跑）：
- extern 嵌入对套件的适用性（§5.6）——**无外部程序**。
- MAPLE 算法的势无关性（§5.7）——**MAPLE 不可运行**（ase/torch/fairchem 缺失）。
- **DMF 默认 numpy 后端**（§5.7 新增块）——只读代码，**未实跑**（无 cyipopt/ase）。
- ANCopt/Native 的文件级归属与依赖图（§1）。
- runtyp 全景表（§2.1/§4）——`p_run_*` 常量与 `set_runtyp` 映射可核。
- **属性/分析层与子模块的 native 存在性**（§1.2/§2 row 31–38）——套件侧「实现数 0」是 `grep` 结果，非实跑对照。

**我无法确认的**：
- 113 原子 taxol 上 `--ohess` 用**我们的基座**跑到什么结果/耗时（只跑了参照；为省时未重跑）。
- tblite 计算器与套件的兼容性（`WITH_TBLITE=OFF`，未编译）。
- CPCM-X（`WITH_CPCMX=OFF`）。
- gfnff 拓扑文件在参照二进制下为何读不到（参照报 `Could not read topology file`，我们的构建却成功；**未定位**）。
- MAPLE 用 xTB ASE 计算器驱动时的**数值**表现（未跑）。
- `--bhess`/`--path`/`--modef`/`--screen`/`--metaopt` 是否真能跑（只做了 runtyp 存在性核查，未逐一实跑）。

---

## 8. 给决策者的最短路径

1. **套件与 ANCopt 的边界已清楚**：套件**不是** ANCopt 超集，也**不是**特例；两者在
   「最小化」上重叠（RMSD ≤2e−3 Å），套件在「TS/IRC/PES 任务链」上独占，ANCopt 在
   「`$scan`/`--path`/`--modef`/`--metaopt`/`--screen`/`--bhess`/构象搜索」上独占。
2. **最值得补**：PBC（影响最大，代价大）> `$scan` 映射（代价极小，已由 W0 改为报错）>
   `--ohess` 链（代价小，工具链体验）。
3. **不要做的事**：把 MAPLE 的 TS/IRC 算法判为「永久缺口」——它们**可迁移**；
   只有 ~~DMF /~~ autograd Hessian / batch-GPU 是永久（**订正 C1：DMF 归「待补」，阻塞是 cyipopt**）。
4. **做任何「上游 vs 套件」数值对照前**：先确认参照二进制与基座的 156 提交差异
   （§5.3：8.6e−7 Eh / 1.19 cm⁻¹），否则会把源码差异当成套件误差。

