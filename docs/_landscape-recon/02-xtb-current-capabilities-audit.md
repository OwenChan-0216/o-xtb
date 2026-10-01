# xtb 6.7.1 现有 PES 能力审计 (02-xtb-current-capabilities-audit)

> 目的：评估以 GFN2-xTB 为能量/梯度引擎，能否构建一个 Fortran 套件实现
> `sp / opt / scan / ts / hessian / freq / irc`。本文只审计 xtb 6.7.1 **已经提供**的
> 能力，并逐项定位缺口。所有引用格式为 `path:line`。
>
> 仓库：`/home/owenchan/work_path/coding/fortran/xtb`（只读）。
> 结论速览：`sp / opt / scan / hessian / freq` 已具备（含 RRHO 热化学）；
> **`ts / irc` 基本不存在**（只有零散的 mode-following、虚假 TS 标志和 RMSD-biased path finder，
> 没有真正的 TS 优化与内禀反应坐标积分）。

---

## 0. 总体能力矩阵

| 任务 | xtb 6.7.1 状态 | 主要入口 |
|---|---|---|
| sp (单点) | ✅ 完整 | `xtb_single::singlepoint` (`src/single.f90:37`), `TCalculator%singlepoint` (`src/type/calculator.f90:65`) |
| opt (最小化) | ✅ 完整，4 种引擎 | `ancopt` (`src/optimizer.f90:122`), `fire/l_ancopt` (`src/relaxation_engine.f90:131/400`), `relax_pbc` (`src/lbfgs_anc/driver.f90:39`) |
| scan (弛豫扫描) | ✅ sequential + concerted | `relaxed_scan` (`src/scan_driver.f90:21`) |
| ts (鞍点) | ❌ 无真正 TS 优化 | 仅有 `set%tsopt` 标志位（仅改 Hessian 更新为 Powell + 提高 hlow）；`modef`/`path` 是近似替代 |
| hessian | ✅ 数值 Hessian（全维/ODLR 近似），有投影/部分 | `numhess` (`src/hessian.F90:33`), `TCalculator%hessian` (`src/type/calculator.f90:112`) |
| freq/thermo | ✅ 完整 RRHO 热化学 | `main_freq` (`src/main/property.F90:695`), `thermodyn` (`src/thermo.f90:79`) |
| irc | ❌ 完全不存在 | 无任何 IRC/内禀反应坐标/路径积分代码 |

---

## 1. ANCopt 优化器 (`src/optimizer.f90` + `src/type/anc.f90`)

### 1.1 `tb_anc` 类型定义位置
`tb_anc` 定义在 **`src/type/anc.f90:31-49`**（module `xtb_type_anc`），
其公开字段：`n, n3, nvar, hlow, hmax, hess(:), B(:,:), eigv(:), coord(:), xyz(:,:)`。
关键方法：`allocate`/`deallocate`/`write`/`new => generate_anc_blowup`/`get_cartesian`/`get_normal`
(`src/type/anc.f90:33-46`)。

### 1.2 算法主线
ANCopt = **Approximate Normal Coordinate + rational-function (RF) trust-region** 优化器。

- **主例程**：`ancopt` (`src/optimizer.f90:122`)。
  - 设定阈值/默认值：`modef=0; iupdat=0; hmax=5.0; s6=20.0; maxdispl=set%optset%maxdispl_opt (1.0); hlow=set%optset%hlow_opt (0.01); maxmicro=set%optset%micro_opt (20)`（`src/optimizer.f90:329-337`）。
  - 调用 `get_optthr(mol%n,tight,ethr,gthr,maxopt,acc)` 取阈值 (`src/optimizer.f90:338`)。
  - **只在 TS 优化时**：`if(set%tsopt) then hlow=max(hlow,0.25); iupdat=1`（即用 Powell 更新），见 `src/optimizer.f90:341-344`。
  - nvar = nat3-6（非线性）或 nat3-5（线性），有固定原子时减去 `3*fixset%n+3`（`src/optimizer.f90:369-384`）。
  - 读取 `.xtbtmpmode` 做 mode-following 重启（`src/optimizer.f90:387-398`），nvar 减去 modef。
  - **外层 micro-iteration** `ANC_microiter` (`src/optimizer.f90:452`)：
    1. 生成模型 Hessian：`call modhes(env, calc, set%mhset, molopt%n, molopt%xyz, molopt%at, fc, pr)`（`src/optimizer.f90:466`），默认 Lindh (1995)。
    2. 投影掉平移/旋转：`call trproj(molopt%n,nat3,molopt%xyz,fc,.false.,modef,pmode,1)`（`src/optimizer.f90:492-499`）。
    3. 生成 ANC：`call anc%new(env%unit,molopt%xyz,h,pr,linear)` → `generate_anc_blowup`（`src/optimizer.f90:519`）。
    4. 内层优化：`call relax(...)`（`src/optimizer.f90:524`）。
    5. 用 RMSD 判断是否内重启（`src/optimizer.f90:534-543`）。

- **内层循环** `relax` (`src/optimizer.f90:622`)：
  - 每步 `anc%get_cartesian(mol%xyz)` 生成笛卡尔坐标（`src/optimizer.f90:747`），
    调用 `calc%singlepoint(...)` 得到 E + 解析梯度（`src/optimizer.f90:757`）。
  - 笛卡尔梯度 → 内部梯度：`dgemv('t', anc%n3, anc%nvar, 1.0, anc%B, anc%n3, g, 1, 0.0, gint,1)`
    （即 `gint = B^T g`）（`src/optimizer.f90:780`），等价于 `tb_anc%get_normal`。
  - 动态调整 SCC 精度 `acc` 与步长 `alp`（`src/optimizer.f90:806-812, 861-869`）。
  - Hessian 更新：`bfgs(...)`（iupdat=0）或 `powell(...)`（iupdat=1）（`src/optimizer.f90:884-890`）。
  - **RF (rational function) 步骤** (`src/optimizer.f90:895-927`)：求解增广本征问题
    `[[H g],[g^T 0]] [dx;1] = λ [dx;1]`，其中 `H=anc%hess`(packed)、`g=gint`。
    解算器：`solver_sspevx`（exact_rf 或 nvar<50）否则 `solver_sdavidson`，失败回退 `sspevx`
    (`src/optimizer.f90:903-918`)。步长 = `Uaug(1:nvar,1)/Uaug(nvar1,1)`，再按 `maxdispl` 截断
    (`src/optimizer.f90:922-932`)。
  - 收敛判据：`abs(echng)<ethr .and. gnorm<gthr .and. echng<1e-10`（`src/optimizer.f90:972-978`）。

### 1.3 `get_optthr` optlevel 表（`src/optimizer.f90:48-119`）
| olev | 常量 (`setparam.f90:68-75`) | ethr (Eh) | gthr (Eh/α) | maxcycle | acc |
|---|---|---|---|---|---|
| crude | -3 | 5e-4 | 1e-2 | n | 3.0 |
| sloppy | -2 | 1e-4 | 6e-3 | n | 3.0 |
| loose | -1 | 5e-5 | 4e-3 | 2n | 2.0 |
| lax | -4 | 2e-5 | 2.5e-3 | 2n | 2.0 |
| normal | 0 (default) | 5e-6 | 1e-3 | 3n | 1.0 |
| tight | 1 | 1e-6 | 8e-4 | 5n | 0.20 |
| vtight | 2 | 1e-7 | 2e-4 | 20n | 0.05 |
| extreme | 3 | 5e-8 | 5e-5 | 20n | 0.01 |

`maxcycle` 最后 clamp 到 `[200,10000]`（`src/optimizer.f90:116-118`）。
`normal` 默认值同时写死在 `setparam.f90:259`；`optset` 默认：`micro_opt=20, maxdispl_opt=1.0, hlow_opt=0.01, exact_rf=.false., average_conv=.false.`（`src/setparam.f90:259-264`）。

### 1.4 其余子程序
- `modhes` (`src/optimizer.f90:1227`)：选择模型 Hessian。非 GFN-FF 用 `newLindhD2ModelHessian`/`newLindhModelHessian`/`newSwartModelHessian`；GFN-FF 可用 `newGFFModelHessian`（`src/optimizer.f90:1269-1310`）。末尾调 `constrhess` 加约束 Hessian。
- `sort` (`src/optimizer.f90:1066`) 与 `src/type/anc.f90:392` 各有一份（按特征值升序重排 Hessian/`B`）。
- `findlroot` (`src/optimizer.f90:1048`)：找最低非零根（供 RFO/模式选择）。
- `trfp2xyz` (`src/optimizer.f90:1155`)：把内部模式位移转回 xyz 位移。
- `itochess` (`src/optimizer.f90:1325`)：`H_cart = B^T H_int B`。
- `geoconvav` (`src/optimizer.f90:1389`)：对末 5 步能量/梯度做滑动平均，用于 noisy 收敛判断。
- `convergence_log` 类（`src/optimizer.f90:39-46, 1438-1557`）：能量/梯度平均，含 Turbomole log 读取 `load_turbomole_log`。

### 1.5 ANC 坐标的构造/更新
- **ANC (Approximate Normal Coordinates)**：不是冗余内坐标，而是**模型 Hessian 的本征向量作为 B 矩阵**
  （`anc%B(:,i) = 大特征值对应的本征向量`），见 `generate_anc_blowup` (`src/type/anc.f90:230-312`)。
- 特征值用 `min(max(λ,hlow),hmax)` 截断（`src/type/anc.f90:290-291`），谱下界低于 `hlow` 时整体平移
  `damp = hlow - elow`（`src/type/anc.f90:270-275`）。
- 平移/旋转模式被 `detrotra` 归零后剔除（`src/type/anc.f90:263`）。
- 只在每个 **micro-iteration** 重建 ANC；micro 循环内 `coord` 逐步累加位移，
  `get_cartesian` 用 `xyz = xyz0 + B*coord` 回到笛卡尔（`src/type/anc.f90:441-448`）。

---

## 2. 所有“优化类”引擎清单

| 引擎 | 文件/例程 | 目标 | 极小化/鞍点 | 最小化对象 |
|---|---|---|---|---|
| ANCopt (RF) | `src/optimizer.f90:122` `ancopt` + `:622` `relax` | 极小值 | 极小化 only | 能量（梯度），ANC 坐标中 RF 步 |
| L-ANCopt (LBFGS) | `src/relaxation_engine.f90:400` `l_ancopt` → `:874` `lbfgs_relax` | 极小值 | 极小化 only | 能量，受限记忆 BFGS + RF |
| FIRE | `src/relaxation_engine.f90:131` `fire` → `:1148` `inertial_relax` | 极小值 | 极小化 only | 能量（阻尼 MD 惯性弛豫） |
| PBC-LBFGS | `src/lbfgs_anc/driver.f90:39` `relax_pbc` | 极小值（含晶胞） | 极小化 only | 能量 + 晶格应变（`sigma`） |
| MDOPT | `src/mdoptim.f90:40` `mdopt` | 轨迹逐帧 minimize | 极小化 only | 对 `xtb.trj` 每隔 `set%skip_md` 帧做 `geometry_optimization` |
| Metadynamics | `src/metadynamic.f90:21` `metadynamic` | bias 修正 | 不是优化器 | 给能量/梯度加 metric bias（供 opt/MD/scan） |

### 2.1 优化引擎分派
`geometry_optimization` (`src/geoopt_driver.f90:29`) 按 `set%opt_engine` 分派（`src/geoopt_driver.f90:152-175`）：
- `p_engine_rf` → `ancopt`
- `p_engine_lbfgs` → `l_ancopt`
- `p_engine_pbc_lbfgs` → `relax_pbc`
- `p_engine_inertial` → `fire`

引擎名从 CLI 映射（`src/set_module.f90:1870-1877`）：
`rf|ancopt`、`lbfgs|l-ancopt`、`pbc_lbfgs`、`inertial|fire`。

### 2.2 `relaxation_engine.f90` 的选项派生类型
- `relax_options`（基类，`src/relaxation_engine.f90:35-58`）：`printlevel, acc, max_displacement, logstep, ilog, ftype, e_thr, g_thr, d_thr, g_max, d_max`。
- `fire_options extends relax_options`（`:61-90`）：`micro_cycle, time_step, lat_time_step, astart, fa, nmin, finc, fdec, dtmax, pcut, mass, lat_mass, precon, update`。
- `lbfgs_options extends relax_options`（`:93-106`）：`micro_cycle, rfthr, memory, hlow, hmax, cycle_inc`。

### 2.3 `src/lbfgs_anc/*`
- `lbfgs_optimizer` / `optimizer_type`（`src/lbfgs_anc/lbfgs.f90`），
  `optimizer_input`(`src/lbfgs_anc/optimizer.f90:28`)、`new_optimizer`/`new_lbfgs_optimizer`（`:36,:50`）。
- `filter_type` 抽象类（`src/lbfgs_anc/filter_type.f90:23`）：`get_dimension`/`transform_structure`/`transform_derivative`；
  具体 `cartesian_filter`（`src/lbfgs_anc/filter_cart.f90`）。
- `driver.f90` 的 `relax_pbc` 主循环用 `optimizer_type` + filter，另含 `num_grad`/`num_sigma`（晶格数值导数，`src/lbfgs_anc/driver.f90:336,409`）。

### 2.4 鞍点相关（存在但非真 TS）
- `set%tsopt`（`src/setparam.f90:515`）**唯一实际效果**：`ancopt` 里 `hlow↑0.25`、`iupdat=1`（Powell 更新），
  见 `src/optimizer.f90:341-344`。**没有任何本征向量跟随、RFO→RFO、Dimer、NEB 逻辑。**
- `set%tsroot`（`src/setparam.f90`，默认 0）仅在 `set_module.f90:1830` 读写，未发现计算用途。
- `modefollow`（`src/modef.f90:34`）：用于构象搜索/1D 非谐，可沿简正模式位移做 PES 扫描；能产生鞍点近似位移，但不是 TS 优化。
- `distort`（`src/hessian.F90:666`）：沿虚频模式位移生成初猜结构并写出 `xtbhess.xyz`，用于“后续优化”（注释 `src/hessian.F90:716`），是 TS 初猜生成器而非 TS 搜索。

---

## 3. Scan 能力 (`src/scan_driver.f90`, `src/scanparam.f90`)

### 3.1 扫描模式
`src/scanparam.f90:26-28`：
- `p_scan_sequential = 1`（默认）：逐约束依次扫（`src/scan_driver.f90:77-107`）。
- `p_scan_concerted = 2`：所有约束同步扫（要求各约束步数相同，`src/scan_driver.f90:108-133`）。

### 3.2 可扫描的坐标类型
扫描对象是**约束 (constraint)**，不是任意内坐标。约束类型由 `atconstr` 行数推断
（`src/scanparam.f90:44-48`，`src/constrain_param.f90:926-930`）：
- distance / angle / dihedral（以及 pos / zaxis / cma 约束体系）。
- 用户通过 `set_scan`（`src/constrain_param.f90:844-947`）解析 `key = start,end,nstep`；
  距离用 Å，角/二面角用度（`src/constrain_param.f90:932-947`）。
- 也支持 `constrain_all_bonds/angles/torsions`（`src/scanparam.f90:325,353,393`）批量生成约束。

### 3.3 是刚性扫描还是弛豫扫描？
**只有弛豫扫描**：每个 scan step 调 `geometry_optimization`（`src/scan_driver.f90:86-89, 119-123`）
在被约束的 PES 切片上做完整几何优化。**没有 rigid scan 模式。**

### 3.4 2D 扫描
**没有原生 2D 扫描**。`concerted` 模式扫描多个约束但它们是同一个“步骤号”同步推进，
不是笛卡尔积式 2D 网格；sequential 模式是逐个约束扫描。要实现 2D 需自行嵌套循环或多次调用。

### 3.5 约束如何施加
- 势：`constrpot`/`constrain_pot` (`src/constrain_pot.f90:355`) → `constrain_pos/dist/angle/dihedral`。
  - 距离约束是软弹簧：`e += fc*d^expo`，梯度 `ff = fc*expo*d^(expo-1)/r`（`src/constrain_pot.f90:207-217`）；`springexpo` 默认 2.0（`src/scanparam.f90:31`）。
  - 角/二面角约束同样是势能项（`src/constrain_pot.f90:283-345`）。
- Hessian：`constrain_hess`（`src/constrain_pot.f90:388`）用数值差分，`qpothess2`（`:95`）为位置约束解析二阶导。
- 参数定义在 `xtb_type_setvar` 的 `constr_setvar`/`fix_setvar`（`src/type/setvar.f90`）。

### 3.6 输出
- `xtbscan.log`（xyz 轨迹，带 `energy=etot-efix`，即去偏后的真实能量），
  见 `src/scan_driver.f90:73, 105, 130` 调 `writeMolecule`。
- 每步打印 `current energy / bias energy / unbiased energy`（`src/scan_driver.f90:94-100`）。
- `cqpath.f90`（`src/cqpath.f90`）与 `bias_path.f90`（`src/bias_path.f90`）不是 scan 输出，
  而是 **path finder**（RMSD-biased push/pull）使用的路径重排/样条工具：
  `cqpath_spline_repos`(`:32`)、`cqpath_repos`(`:128`)、样条 `cqpath_cube_spline`(`:270`)。

---

## 4. Hessian 与 freq/thermo

### 4.1 数值 Hessian
- **`numhess`**（`src/hessian.F90:33`）：驱动全维数值 Hessian。
  签名：`numhess(env,mol,chk0,calc,egap,et,maxiter,etot,gr,sr,res)`，
  输出 `res` 为 `freq_results`（`src/hessian.F90:80`）。
  - 逐原子位移，通过 `calc%hessian(env,mol,chk0,indx,step,h,dipd,...)` 累加（`src/type/calculator.f90:112` 起）。
  - 支持 `set%o1numhess` 的 **ODLR 近似 Hessian**（`src/hessian.F90:183-192`）。
  - 有解析 TM Hessian 分支（`set%mode_extrun==p_ext_turbomole`）。
- **`numhess_rmsd`**（`src/hessian.F90:581`）：`p_run_bhess`（biased hess）用（`src/hessian.F90:264`）。
- **`TCalculator%hessian`**（`src/type/calculator.f90:112`）：有限差分，支持 `odlr` 与 `final_err`。
- **`src/o1numhess.f90`**：ODLR/局部 Hessian 近似。关键接口：
  `gen_local_hessian`(`:71`)、`lr_loop`(`:263`)、`gen_displdir`(`:433`)、
  `get_vdw_neighbor_list`(`:374`)、`find_projected_imag_modes`(`:694`, 找投影后的虚频模式)、
  抽象 `matvec_operator`(`:42`)。
- **`src/model_hessian/*`**：解析模型 Hessian（用于 ANCopt 初猜）。
  - 基类 `TModelHessian`（`src/model_hessian/type.f90:34`），`compute`/`compute_packed`/`compute_dense`。
  - `TInternalModelHessianBase`（`src/model_hessian/internal.f90:39`），
    `TLindhModelHessian`/`TLindhD2ModelHessian`（`src/model_hessian/lindh.f90:35-38`）、
    `TSwartModelHessian`（`src/model_hessian/swart.f90:29`）、`TGFFModelHessian`（`src/model_hessian/gff.f90:40`）。
  - 电荷项 `add_eeq_hessian`（`src/model_hessian/eeq.f90:55`）。

### 4.2 部分/截断 Hessian 与投影
- `trproj`（`src/freq/project.f90:151`）：把 Hessian 投影掉平移/转动态；
  `gtrprojm`（`:218`）构造投影矩阵。支持 `nmode` 个额外模式投影（NMF）与固定原子投影
  （`nmode<0` 时 `nprj = 6 + fixset%n*3`，`:233-235`）。
- `projectHessian`（`src/freq/project.f90:34`）：按 `removeTrans/removeRot` 屏蔽。
- `rdhess`（`src/freq/io.f90:82`，读 Turbomole `$hessian`）、`wrhess`(`:51`)、
  `writeHessianOut`(`:30`)；`src/optimizer.f90:1369` 另有一份简化 `read_hessian`。
- **注意**：`trproj` 有 **两份不同实现**：`src/hessian.F90` 通过 `use xtb_hessian` 重导出
  （`src/hessian.F90:29`），实体在 `src/freq/project.f90:151`。

### 4.3 频率分析 / 热化学 (RRHO)
- `main_freq`（`src/main/property.F90:695`）：打印频率、约化质量、IR/Raman 强度，
  写 `vibspectrum`、`g98.out`（`g98fake2`，`src/freq/io.f90:283`）、`vib_normal_modes`。
- `print_thermo` → `thermodyn`（`src/thermo.f90:79`）：**RRHO 配分函数**（平动/转动/振动/内转动），
  输出 H(T)、G(T)、S、ZPE、Cv/Cp（`src/thermo.f90:79-258`；`lnqrot`/`lnqvib`/`lnqvibmod` `:260-329`）。
- 对称性：`getsymmetry`（`src/thermo.f90:24`），反应路径对称数 `getsymnum`。
- 虚频处理：阈值 `set%thermo_ithr`（默认 -20 cm⁻¹，`src/setparam.f90:288`），
  虚频打印由 `PREIGF`（`src/hessian.F90:503`）与 `res%nimag` 完成。
- 频率标定：`rescale_freq`（`src/hessian.F90:727`）；模式扭曲 `distort`（`src/hessian.F90:666`）。
- `massWeightHessian`/`diagHessian`（`src/freq/utils.f90:32,59`）。
- `freq_results` 字段见 `src/type/data.F90:105-129`（`freq, hess, rmass, dipt, polt, nimag, zp, htot, gtot, pg, n3true, linear` 等）。

### 4.4 模式跟随 (mode-following)
- `modefollow`（`src/modef.f90:34`）：三种模式（注释 `src/modef.f90:28-31`）：
  `mode_local=0` 简正坐标构象 PES 扫描；`=1` 局域简正坐标；`=-1` 非谐校正 PES 扫描。
  这是**沿模式方向的 PES 扫描**，不是鞍点优化。

---

## 5. TS / IRC 能力——确定性结论

对以下关键字做了全仓库 grep（结果均为**文件命中在无关词**或 **0 命中**）：

| 关键字 | 命中 | 结论 |
|---|---|---|
| `popt` | 0 | 不存在 |
| `prfo` | 0 | 不存在 |
| `rfo` (词) | 仅 `src/optimizer.f90:697,714,717` 注释中的 “dimensions for RFO / RFO eigenvalues / RFO eigenvectors”（指 RF 步骤，非独立 RFO 优化器） | 无独立 RFO 优化器 |
| `dimer` | 12 处，全在 `src/dipro.F90`（DIPRO = dimer projection 电子结构方法，`src/dipro.F90:21,77,145`） | **与 Dimer TS 方法无关** |
| `nudged` | 0 | 无 NEB |
| `neb` (词) | 0 | 无 NEB |
| `lqa` | 0 | 无 LQA |
| `gonzalez` | 0 | 无 Gonzalez-Schlegel IRC |
| `intrinsic reaction` | 0 | 无 |
| `reaction path` | 0 | 无 |

### 5.1 `grep -rln irc src/` 的三个命中——逐个确认
1. **`src/lidep.f90:143`**：注释 `!  matrix X. In practice, this X can be modified to circumvent`
   —— 是英文单词 **cir**cumven**t** 的子串，与 IRC 无关。
2. **`src/readin.f90:50`**：注释 `!  circumvent this. Also as a gimmick, ...` —— 同上，无关。
3. **`src/optimizer.f90:618`**：注释 `!! procedure INSIDE the mirco iterator which is implemented by the calling`
   —— “mirco” 的变体，仍与 IRC 无关（`grep -o` 确认此处匹配为字母子串，非 IRC 语义）。

**结论：xtb 6.7.1 完全没有 IRC / 内禀反应坐标 / 反应路径积分能力。**

### 5.2 与 TS 相关的“近似”设施（可用于新套件的复用，但不是 TS 求解）
- **RMSD-biased push/pull path finder**（nano-reactor, RMSD-BPP）：`bias_path`（`src/bias_path.f90:30`），
  由 `runtyp = p_run_path` 触发（`src/prog/main.F90:1225-1231`）。
  参数 `pathset`：`nrun, nopt, kpush, kpull, ppull, alp, fname, nat, atoms`（`src/set_module.f90:446-456, 2644-2671`）。
  用 RMSD 高斯 bias 在 reactant/product 间推拉并找近似 TS（`src/bias_path.f90:17-20`）。
  辅助：`screenpath`(`:464`)、`metadyn_tsmode`(`:514`)、`guess_tsmode`(`:554`)、`alignpath`(`:595`)、
  `cleanpath`(`:852`)、样条 `cqpath_*`。
- **mode-following**：`modefollow`（`src/modef.f90:34`），`runtyp=p_run_modef`（`src/prog/main.F90:1245-1250`）。
- **虚频扭曲生成 TS 初猜**：`distort`（`src/hessian.F90:666`）。
- **metadynamics / RMSD bias**：`metadynamic`（`src/metadynamic.f90:21`）给能量/梯度加 bias，可用于增强采样。

---

## 6. 复用面（REUSE SURFACE）——接口目录

> 每条给出新模块应写的 **精确 `use` 行**。

### 6.1 能量+梯度入口

| 能力 | 源码位置 | 建议 `use` |
|---|---|---|
| 抽象计算器 | `src/type/calculator.f90:40`（`type, abstract :: TCalculator`） | `use xtb_type_calculator, only : TCalculator` |
| 多态单点 | `deferred :: singlepoint`（`src/type/calculator.f90:44`） | 通过 `class(TCalculator) % singlepoint` 调用 |
| 多态 Hessian | `procedure :: hessian`（`src/type/calculator.f90:46`, 实现 `:112`） | `call calc%hessian(env,mol,chk,list,step,hess,dipgrad[,polgrad][,odlr,final_err])` |
| GFN2/1/0 计算器 | `src/xtb/calculator.f90:60`（`TxTBCalculator`） | `use xtb_xtb_calculator, only : TxTBCalculator, newXTBCalculator, newWavefunction` |
| 单点包装 | `src/single.f90:37` | `use xtb_single, only : singlepoint` |

`newXTBCalculator(env, mol, calc, fname, method, accuracy)`（`src/xtb/calculator.f90:91`）。

### 6.2 几何/状态/环境类型

| 类型 | 位置 | `use` |
|---|---|---|
| `TMolecule` | `src/type/molecule.f90:53` | `use xtb_type_molecule, only : TMolecule, init` |
| `TRestart` | `src/type/restart.F90:38` | `use xtb_type_restart, only : TRestart` |
| `TEnvironment` | `src/type/environment.f90:38` | `use xtb_type_environment, only : TEnvironment` |
| `tb_timer` | `src/type/timer.f90:18` | `use xtb_type_timer, only : tb_timer` |
| `scc_results` / `freq_results` | `src/type/data.F90:66,105` | `use xtb_type_data, only : scc_results, freq_results` |
| `set` 全局参数 | `src/setparam.f90` | `use xtb_setparam` |

**`TMolecule` 公开字段**（`src/type/molecule.f90:53-169`）：
`n, nId, chrg, uhf, pbc(3), npbc, boundaryCondition, sym(:), at(:), id(:), xyz(:,:), abc(:,:),
dist(:,:), atmass(:), z(:), cn(:), linear, cellpar(6), lattice(3,3), rec_lat(3,3), volume, ftype, name, pdb(:), sdf(:)`。
方法：`allocate/deallocate/calculate_distances/set_nuclear_charge/set_atomic_masses/update/wrap_back/
center_of_geometry/center_of_mass/shift_to_*/moments_of_inertia/align_to_principal_axes/copy`。

**错误处理 idiom**（`src/type/environment.f90`）：
- `call env%error("msg", source)`（`:298`）记录错误；
- `call env%check(fail)`（`:162`）取终止标志，然后 `if(fail) return`；
- `call env%warning("msg", source)`（`:324`）仅警告；
- 另有 `checkpoint`(`:176`)、`rescue`(`:350`)、`terminate`(`:266`)。

### 6.3 坐标机制

| 组件 | 位置 | `use` |
|---|---|---|
| `tb_anc` | `src/type/anc.f90:31` | `use xtb_type_anc, only : tb_anc` |
| Wilson B 矩阵 | `src/bmatrix.f90:321` `get_bmatrix` | `use xtb_bmatrix, only : get_bmatrix, bmat_bond, bmat_angle, bmat_torsion, bmat_linbend, bmat_outofplane` |
| 分子图 | `src/internals/graph.f90:33` | `use xtb_internals_graph, only : graph_type, init` |
| 冗余内坐标 | `src/internals/redundant.f90:62` | `use xtb_internals_redundant, only : redundant_type, init` |
| 内坐标类型 | `src/internals/type.f90:41` | `use xtb_internals_type, only : internal_coords_set_type, coord_bond, coord_angle, coord_dihedral, coord_linbend` |
| 去平移/转动 | `src/detrotra.f90:23` | `use xtb_detrotra, only : detrotra` |
| 主轴/旋转 | `src/axis_trafo.f90:18` | `use xtb_axis, only : axis, axis2, axis3, axisvec, is_linear` |
| 质心/去转动 | `src/rmrottr.f90:19` | （无 module，外部子程序）`external :: rmrottr` |
| RMSD 对齐 | `src/ls_rmsd.f90:33` | `use xtb_lsrmsd, only : rmsd` |

注：新 `internals` 模块（graph/redundant/type/bmatrix）目前只被 `src/compliance.f90:69-72` 与
`src/bmatrix.f90:24` 使用；ANCopt **不使用**它们（ANC 直接用 Hessian 特征向量）。

### 6.4 Hessian 投影 / 模型 / 数值

| 组件 | 位置 | `use` |
|---|---|---|
| `trproj` (重导出) | `src/hessian.F90:29` | `use xtb_hessian, only : trproj, numhess, rdhess, distort, rescale_freq, numhess_rmsd, write_tm_vibspectrum, g98fake2` |
| `projectHessian`/`gtrprojm` | `src/freq/project.f90:34,218` | `use xtb_freq_project, only : projectHessian, trproj, gtrprojm` |
| ODLR 局部 Hessian | `src/o1numhess.f90:71,263,433,694` | `use xtb_o1numhess, only : gen_local_hessian, lr_loop, gen_displdir, get_vdw_neighbor_list, find_projected_imag_modes, adj_list` |
| 模型 Hessian 基类 | `src/model_hessian/type.f90:34` | `use xtb_modelhessian_type, only : TModelHessian` |
| Lindh / Swart / GFF | `lindh.f90:41`, `swart.f90:34`, `gff.f90:51` | `use xtb_modelhessian_lindh/swart/gff, only : newLindhModelHessian, newSwartModelHessian, newGFFModelHessian` |
| 频率投影工具 | `src/freq/utils.f90:26` | `use xtb_freq_utils, only : massWeightHessian, diagHessian` |

### 6.5 trust-region / 特征值求解器

| 组件 | 位置 | `use` |
|---|---|---|
| BFGS/Powell 更新 | `src/bfgs.f90` | `use xtb_bfgs, only : bfgs, powell` |
| Davidson / sdavid2 | `src/david2.f90:18` | `use xtb_david2, only : sdavid2, solver_sdavidson` |
| RFO 求解器 | `solver_sspevx/solver_ssyevx` (`src/optimizer.f90:992,1021`，module-private) | 不可直接 `use`，需复制或重构 |
| LAPACK 封装 | `src/mctc/lapack.f90:19` | `use xtb_mctc_lapack, only : lapack_syev, lapack_spevx, lapack_spevd, lapack_syevd, ...` |
| BLAS 封装 | `src/mctc/blas.f90:19` | `use xtb_mctc_blas` |
| `xtb_mctc_la` | `src/mctc/linalg.f90:18` | `use xtb_mctc_la`（重导出 BLAS/LAPACK + `syprj`, `blckmgs`, `dhtosq`） |

### 6.6 I/O

| 组件 | 位置 | `use` |
|---|---|---|
| 写分子/xyz | `src/io/writer.f90:36` | `use xtb_io_writer, only : writeMolecule` |
| 读分子/Hessian | `src/io/reader.f90:40,100` | `use xtb_io_reader, only : readMolecule, readHessian` |
| 文件类型常量 | `src/mctc/filetypes.f90` | `use xtb_mctc_filetypes, only : fileType` |
| 几何屏幕输出 | `src/main/geometry.f90` | `use xtb_main_geometry`（按需） |
| 通用头/表格 | `src/header.f90` | `use xtb_header, only : generic_header` |
| 输出工具 | `src/printout.f90`, `src/enso_printout.f90` | 按需 |
| 重启 | `src/restart.F90` | 按需 |

`writeMolecule(self, unit, format, energy, gnorm, number)`（`src/io/writer.f90:36`）——
轨迹输出即每次循环 `call writeMolecule(mol, ilog, format=fileType%xyz, energy=..., gnorm=..., number=iter)`
（模式见 `src/optimizer.f90:773-775`）。

### 6.7 数值基底

| 组件 | 位置 | `use` |
|---|---|---|
| 精度 | `src/mctc/accuracy.f90:19` | `use xtb_mctc_accuracy, only : wp, sp` |
| 单位换算 | `src/mctc/convert.f90:18` | `use xtb_mctc_convert`（`aatoau, autokcal, autoaa, fstoau, amutoau, rcmtoau, ...`） |
| 常数 | `src/mctc/mctc_constants.f90` | `use xtb_mctc_constants, only : pi, kB_SI, ...` |
| 符号 | `src/mctc/symbols.f90` | `use xtb_mctc_symbols, only : toSymbol` |
| 计时 | `src/mctc/mctc_timings.f90:18` / `src/type/timer.f90:18` | `use xtb_mctc_timings` / `use xtb_type_timer, only : tb_timer` |
| I/O stdout | `src/mctc/mctc_io.f90` | `use xtb_mctc_io, only : stdout` |

### 6.8 扫描/约束复用

| 组件 | 位置 | `use` |
|---|---|---|
| 弛豫扫描驱动 | `src/scan_driver.f90:21` | `use xtb_scan, only : relaxed_scan` |
| 扫描参数 | `src/scanparam.f90:18` | `use xtb_scanparam`（`p_scan_sequential/concerted, scan_list, valconstr, nscan`） |
| 约束势 | `src/constrain_pot.f90:19` | `use xtb_constrainpot, only : constrain_pot, constrain_hess, constrain_pos/dist/angle/dihedral` |
| 约束读入 | `src/constrain_param.f90:60` | `use xtb_constrain_param`（set_fix/set_constr/set_scan/set_reactor/set_path/...） |
| 元动力学 | `src/metadynamic.f90:18` | `use xtb_metadynamic, only : metadynamic, load_metadynamic, set_metadynamic` |
| 路径工具 | `src/cqpath.f90:17` | `use xtb_cqpath` |
| 路径查找 | `src/bias_path.f90:17` | `use xtb_biaspath, only : bias_path` |

---

## 7. 构建/测试约定

### 7.1 CMake (`src/CMakeLists.txt`)
- 新子目录：`add_subdirectory("...")`（`src/CMakeLists.txt:21-39`）。
- 顶层源文件：`list(APPEND srcs "${dir}/xxx.f90")`（`src/CMakeLists.txt:43` 起；示例 `hessian.F90` 在列）。
- 子目录内 `model_hessian/*.f90` 以显式路径列出（`src/CMakeLists.txt:106-112`）。

### 7.2 Meson (`src/meson.build`)
- 新子目录：`subdir('...')`（`src/meson.build:18-40`）。
- 顶层源文件：`srcs += files('xxx.f90', ...)`（`src/meson.build:42` 起）。

### 7.3 Fortran 方言/标志 (`cmake/CMakeLists.txt:49-60`)
- GNU：`-fdefault-real-8 -fdefault-double-8 -ffree-line-length-none -fbacktrace`（`:50`）。
- Debug：`-fbounds-check -ffpe-trap=invalid,zero,overflow`（`:51`）。
- Intel：`-axAVX2 -r8 -traceback`；`-check all -fpe0`。
- **注意**：默认 `real-8`，所以裸 `real` 即 `real(wp)`；源码里大量 `real*8`/`real(sp)` 混用。

### 7.4 命名约定
- 模块名：`xtb_<area>_<thing>`，如 `xtb_type_anc`、`xtb_modelhessian_lindh`、
  `xtb_relaxation_engine`、`xtb_pbc_optimizer_lbfgs`。
- 类型名：`T` 前缀（`TMolecule`, `TCalculator`, `TEnvironment`, `TModelHessian`）或小写 `tb_*`（`tb_anc`, `tb_timer`）。
- 文件扩展名：`.f90` 为主，模板/宏文件用 `.F90`（`hessian.F90`, `restart.F90`, `dipro.F90`）。

### 7.5 测试框架 (test-drive)
- 测试位于 `test/unit/`，一个文件一个 `module test_<name>`，导出 `collect_<name>`。
- `test/unit/main.f90:20-40` 逐个 `use test_<name>, only : collect_<name>` 并汇总到 `new_testsuite`。
- 注册：CMake `test/unit/CMakeLists.txt:24-58` 的 `tests` 列表 + 自动 `test_${t}.f90` 拼接；
  Meson `test/unit/meson.build:31-64` 同构。
- 依赖 `test-drive >= 0.3`（`test/unit/meson.build:20`）。

**完整示例**（`test/unit/test_optimizer.f90`，节选 1-121 行核心）：
```fortran
module test_optimizer
   use testdrive, only : new_unittest, unittest_type, error_type, check
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_io, only : stdout
   use xtb_type_environment
   use xtb_type_molecule
   use xtb_type_restart, only : TRestart
   use xtb_xtb_calculator, only : TxTBCalculator, newXTBCalculator, newWavefunction
   use xtb_setparam, only : p_olev_normal
   use xtb_optimizer, only : ancopt
   use xtb_relaxation_engine, only : fire, l_ancopt
   implicit none
   private
   public :: collect_optimizer
contains
subroutine collect_optimizer(testsuite)
   type(unittest_type), allocatable, intent(out) :: testsuite(:)
   testsuite = [ &
      new_unittest("single-atom-ancopt", test_single_atom_ancopt), &
      new_unittest("single-atom-fire", test_single_atom_fire), &
      new_unittest("single-atom-l-ancopt", test_single_atom_l_ancopt) ]
end subroutine collect_optimizer

subroutine test_single_atom_ancopt(error)
   type(error_type), allocatable, intent(out) :: error
   type(TEnvironment) :: env
   type(TMolecule) :: mol
   type(TRestart) :: chk
   type(TxTBCalculator) :: calc
   real(wp) :: energy, egap, gradient(3, 1), sigma(3, 3)
   logical :: fail
   integer :: iter_needed
   call setup_single_atom(env, mol, chk, calc, energy, egap, gradient, sigma, &
      & fail, iter_needed)
   call ancopt(env, stdout, mol, chk, calc, egap, 300.0_wp, 50, 50, &
      & energy, gradient, sigma, p_olev_normal, .false., fail, iter_needed)
   call check_single_atom_result(error, fail, iter_needed)
end subroutine test_single_atom_ancopt
! ... setup_single_atom: init(env); init(mol,sym,xyz,chrg=1); newXTBCalculator(...); newWavefunction(...)
end module test_optimizer
```
`check_single_atom_ancopt` 用 `check(error, fail, .false., "must converge")` 风格断言。

### 7.6 错误处理 idiom（新模块必须遵循）
```fortran
character(len=*), parameter :: source = "my_module_routine"
call env%error("something failed", source)
call env%check(fail)          ! fail 为局域 logical
if (fail) return
! or
call env%warning("mildly odd", source)
```
参考 `src/optimizer.f90:466-470`、`src/geoopt_driver.f90:192-196`。

---

## 8. GAP ANALYSIS（到 MAPLE 对等的差距）

| 任务 | xtb 6.7.1 状态 | 到达 MAPLE 对等缺什么 | 复用 vs 新代码 |
|---|---|---|---|
| sp | ✅ 完整（E + 解析梯度 + sigma） | 无 | 直接复用 `xtb_single`/`TxTBCalculator%singlepoint` |
| opt (极小值) | ✅ 4 引擎（RF/L-ANCopt/FIRE/PBC-LBFGS） | 需统一调度接口/收敛报告、暴露给新套件 | 复用 `xtb_optimizer::ancopt`、`xtb_relaxation_engine::l_ancopt/fire`、`xtb_geoopt` |
| scan (1D 弛豫) | ✅ 距离/角/二面角，sequential+concerted | 无 rigid scan；concerted 非乘积；无统一 scan 驱动 API | 复用 `xtb_scan::relaxed_scan`、`xtb_constrainpot`；新写外层循环/输出 |
| scan (2D/composite) | ❌ | 乘积式 2D 网格、多约束组合、重启动 | 新代码（可基于 `relaxed_scan` 模式循环） |
| ts (鞍点优化) | ❌ 无真正 TS | RFO/准牛顿鞍点搜索、本征向量跟随、`tsroot` 选择、虚频确认、坐标/模式投影 | **新代码**；可复用 `tb_anc`、`bfgs/powell`、`david2`、`model_hessian`、`trproj`、`numhess` 求虚频 |
| ts (初猜生成) | ⚠️ 部分（`distort` 沿虚频位移） | 从虚频生成初猜可选、mode-following 上坡 | 复用 `src/hessian.F90::distort`、`xtb_o1numhess::find_projected_imag_modes`、`modef::modefollow` |
| ts (path-based) | ⚠️ 近似（RMSD-BPP `bias_path`） | 非标准、无 NEB/Dimer；无法给标准 TS 收敛 | 可参考 `bias_path`、`cqpath`，但需重写标准算法 |
| hessian | ✅ 数值全维 + ODLR 近似 + 解析 TM | 若需高精度 analytic GFN2 Hessian：目前只有数值 | 复用 `numhess`、`xtb_hessian`、`o1numhess`、`model_hessian` |
| hessian (partial/truncated) | ⚠️ 有 `trproj` 投影，无“截断维数” | 选择性原子/模式子空间 Hessian 需自行组合 | 复用 `trproj`(nmode 投影)、`calc%hessian(list,...)` 的原子列表参数 |
| freq | ✅ 完整（含 IR/Raman、projected freq） | 无 | 复用 `main_freq`、`freq_utils`、`freq_io` |
| thermo (RRHO) | ✅ 完整（H/G/S/ZPE/Cv/Cp，含 free-rotor） | 无 | 复用 `thermo::thermodyn`、`getsymmetry` |
| irc | ❌ 完全不存在 | IRC 积分器（Euler/RK4/Gonzalez-Schlegel）、质量加权步进、正/反方向追踪、路径 Hessian/能量曲线 | **全新代码**；可复用 `numhess`、`massWeightHessian`、`trproj`、`xtb_single` |
| 统一 PES 套件调度 | ❌ 无（逻辑散落在 `prog/main.F90`） | 需抽象出可在 Fortran 内部调用的 `run_sp/opt/scan/ts/freq/irc` API | 复用现有各 driver；新写调度层 |

---

## 9. 架构连接（Architecture）

```
                         ┌─────────────────────────────┐
                         │  prog/main.F90 (runtyp 分派) │
                         └──────────────┬──────────────┘
        sp/opt/scan/path/modef/mdopt/freq 各自调用
                         │
     ┌───────────────────┼────────────────────────────────────┐
     ▼                   ▼                                    ▼
 xtb_single::       xtb_geoopt::geometry_optimization     xtb_hessian::numhess
 singlepoint        (分派 opt_engine)                      (→ main_freq/thermo)
     │                   │                                    │
     ▼                   ▼                                    ▼
 TCalculator      ┌──────┴───────┬──────────────┐        calc%hessian
 (abstract)       ▼              ▼              ▼        (type/calculator.f90)
   │           ancopt        l_ancopt/fire    relax_pbc
   ▼              │              │              │
TxTBCalculator  tb_anc      lbfgs_options   lbfgs_anc/*
 (src/xtb/)      (RF step)   (relaxation_engine)
     │              │
     ▼              ▼
 GFN2 能量/梯度   model_hessian (Lindh/Swart/GFF) + trproj + bfgs/powell + david2
```
- 所有引擎共享 `TCalculator%singlepoint`（能量+解析梯度）与 `TEnvironment` 错误处理。
- Hessian 相关：`ancopt` 用 `model_hessian` 生成初猜并投影；`numhess` 用有限差分；
  `o1numhess` 提供 ODLR 近似。
- 扫描/路径：`scan_driver` 复调 `geometry_optimization`；`bias_path` 独立驱动 RMSD bias。
- 热化学：`numhess` 填充 `freq_results`，`main_freq` 打印并调 `thermodyn`。

---

## 10. 约束与风险

**约束**
- 只能读取 xtb 仓库；本报告全部为只读审计。
- 报告写入指定输出路径。

**风险 / 开放问题**
1. `solver_sspevx`/`solver_ssyevx` 是 `src/optimizer.f90` 的 module-private，新套件无法直接复用；
   需复制或提升可见性。
2. `relaxation_engine` 中 `l_ancopt` "L-ANCopt" 并非纯 LBFGS——它用 `modhes`+`detrotra` 构建 ANC 再 `lbfgs_relax`（`src/relaxation_engine.f90:622-736`），与 `ancopt` 关系需进一步确认。
3. 实现 TS 时，xtb 缺 `tsroot` 实际逻辑；需自建鞍点根选择与本征向量跟随，且 `tsopt` 现有语义会改变 Hessian 更新策略。
4. 实现 IRC 必须自建质量加权坐标与步长；可依托 `numhess` + `massWeightHessian`，但无现成积分器。
5. `TMolecule`/`TRestart` 完整字段与构造 API（`init`, `newWavefunction`）需在实现前再核对（`src/type/molecule.f90:53-194`）。
6. 2D scan/多约束组合无 API，须自行组合 `scanparam` 的 `tb_scan` 列表。

---

## 11. Start Here（下一个 agent 应从哪打开）

1. **`src/optimizer.f90:122-990`**：理解 ANCopt 主循环与 RF trust-region——这是复用度最高、也是最可能被 TS/IRC 新代码借鉴的核心。
2. **`src/type/anc.f90:31-260`**：`tb_anc` 构造（Hessian 特征向量即 B 矩阵）——TS 本征向量跟随可复用。
3. **`src/hessian.F90:33-579` + `src/freq/project.f90:151`**：数值 Hessian 与投影，IRC/TS 虚频确认的基础。
4. **`src/geoopt_driver.f90:29-225`**：引擎分派模式——统一 PES 套件的架构模板。
5. **`src/type/calculator.f90:40-200`**：`TCalculator` 抽象接口（sp/hessian）——所有引擎的复用锚点。

---

## 附：关键事实速查
- `tb_anc` 定义：`src/type/anc.f90:31`。
- optlevel 表：`src/optimizer.f90:48-119`；默认 normal。
- RF 步骤 5 行核心：`src/optimizer.f90:895-927`。
- `grep -rln irc src/` 的三处命中均为英文单词子串（`circumvent`/`mirco`），与 IRC 无关。
- `popt/prfo/nudged/neb/lqa/gonzalez/intrinsic reaction/reaction path` 全 0 命中。
- `dimer` 仅指 DIPRO 电子结构方法，非 Dimer TS。
- TS 相关仅有：`set%tsopt`（改 Hessian 更新）、`modefollow`、`distort`、`bias_path`(RMSD-BPP)。
