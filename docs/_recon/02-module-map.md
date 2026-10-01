# xtb 6.7.1 源码模块地图与依赖图

> 只读侦察报告。所有路径相对仓库根目录。统计口径：`src/` 下全部 `.f90/.F90/.f`（共 361 个文件），模块名由 `^\s*module <name>` 提取，`use` 由 `^\s*use ... :: <mod>` 提取。fan-in = 引用该模块的 **不同文件数**。

---

## 1. src/ 各子目录职责

| 目录 | 文件数 | 定位 | 关键模块 |
|---|---|---|---|
| `src/api/` | 7 | C/Fortran 公共 API（`bind(C)` 接口、环境、calculator、molecule、results） | `xtb_api_calculator`, `xtb_api_environment`, `xtb_api_interface`, `xtb_api_molecule`, `xtb_api_results`, `xtb_api_utils`, `xtb_api_version` |
| `src/coulomb/` | 3 | 周期性/解析库仑 (Ewald、Gaussian、Klopman–Ohno) | `xtb_coulomb_ewald`, `xtb_coulomb_gaussian`, `xtb_coulomb_klopmanohno` |
| `src/dipro/` | 5 | Dimer Projection 方法（GFN1 下的 embedding/键级/输出） | `xtb_dipro`, `xtb_dipro_bondorder`, `xtb_dipro_fragment`, `xtb_dipro_output`, `xtb_dipro_xtb` |
| `src/disp/` | 7 | 色散模型 D3/D4、配位数、D4 参数 | `xtb_disp_dftd3`, `xtb_disp_dftd4`, `xtb_disp_dftd3param`, `xtb_disp_dftd4param`, `xtb_disp_ncoord`, `xtb_disp_coordinationnumber`, `xtb_disp_encharges` |
| `src/docking/` | 3 | 非共价 docking 搜索 | `xtb_docking_param`, `xtb_docking_search_nci`, `xtb_docking_set_module` |
| `src/extern/` | 4 | 外部 QM 程序后端驱动（MOPAC/ORCA/Turbomole） | `xtb_extern_driver`, `xtb_extern_mopac`, `xtb_extern_orca`, `xtb_extern_turbomole` |
| `src/freq/` | 3 | 频率分析：投影、工具、IO | `xtb_freq_io`, `xtb_freq_project`, `xtb_freq_utils` |
| `src/gfnff/` | 19 | GFN-FF 力场的全部实现（生成器、拓扑、参数、能量/梯度、邻居表） | `xtb_gfnff_calculator`, `xtb_gfnff_data`, `xtb_gfnff_eg`, `xtb_gfnff_ini`, `xtb_gfnff_topology`, `xtb_gfnff_neighbor`, `xtb_gfnff_generator`, `xtb_gfnff_shake` 等 |
| `src/iff/` | 6 | Intrinsic Fragmentation Framework（LMO 片段能量） | `xtb_iff_calculator`, `xtb_iff_data`, `xtb_iff_iffenergy`, `xtb_iff_iffini`, `xtb_iff_ifflmo`, `xtb_iff_iffprepare` |
| `src/internals/` | 3 | 冗余内坐标（用于优化/振动） | `xtb_internals_graph`, `xtb_internals_redundant`, `xtb_internals_type` |
| `src/io/` | 8 | 分子读/写（通用 format、ORCA、Turbomole、Gaussian） | `xtb_io_reader`, `xtb_io_writer`, `xtb_io_reader_*`, `xtb_io_writer_*` |
| `src/lbfgs_anc/` | 6 | 周期体系 L-BFGS 优化器 + 滤波 | `xtb_pbc_optimizer_driver`, `xtb_pbc_optimizer_filter*`, `xtb_pbc_optimizer_lbfgs`, `xtb_pbc_optimizer_optimizer` |
| `src/main/` | 6 | 顶层装配：默认值、几何准备、calculator 工厂、json 输出、property 输出、run 入口 | `xtb_main_defaults`, `xtb_main_setup`, `xtb_main_json`, `xtb_propertyoutput`, `xtb__`(run), `geometry`(无模块) |
| `src/mctc/` | 49 | 内嵌复用的 **MCTC 数值库**：精度/常量、BLAS/LAPACK 包装、IO、字符串、数学、元素符号与参数、timing | `xtb_mctc_accuracy`, `xtb_mctc_convert`, `xtb_mctc_constants`, `xtb_mctc_blas`, `xtb_mctc_lapack`, `xtb_mctc_io`, `xtb_mctc_systools`, `xtb_mctc_param`, `xtb_mctc_symbols`, `xtb_mctc_global` |
| `src/model_hessian/` | 7 | 模型 Hessian（Lindh/Swart/EEQ/GFF/internal） | `xtb_modelhessian_swart`, `xtb_modelhessian_lindh`, `xtb_modelhessian_eeq`, `xtb_modelhessian_gff`, `xtb_modelhessian_internal`, `xtb_modelhessian_shared`, `xtb_modelhessian_type` |
| `src/param/` | 10 | 静态元素参数表（原子质量/半径/电负性/R4R2…） | `xtb_param_atomicmass`, `xtb_param_atomicrad`, `xtb_param_paulingen`, `xtb_param_covalentrad(d3)`, `xtb_param_sqrtzr4r2`, `xtb_param_uffvdwrad`, `xtb_param_vdwradcosmo/d3` 等 |
| `src/prog/` | 9 | CLI 程序层：参数解析、子命令分发、主驱动、拓扑/thermo 子程序 | `xtb_prog_main`, `xtb_prog_argparser`, `xtb_prog_submodules`, `xtb_prog_dock`, `xtb_prog_ir`, `xtb_prog_thermo`, `xtb_prog_topology` |
| `src/ptb/` | 18 | 半经验 **PTB**（property/response）哈密顿量：积分、SCF、响应、U 修正、vdZP 基 | `xtb_ptb_calculator`, `xtb_ptb_hamiltonian`, `xtb_ptb_scf`, `xtb_ptb_integrals`, `xtb_ptb_solver`, `xtb_ptb_response`, `xtb_ptb_data`, `xtb_ptb_param` |
| `src/solv/` | 14 | 隐式溶剂化：GB/SA、COSMO/CPCM-X、SASA、Lebedev、DDCOSMO | `xtb_solv_gbsa`, `xtb_solv_cosmo`, `xtb_solv_cpx`, `xtb_solv_model`, `xtb_solv_sasa`, `xtb_solv_born`, `xtb_solv_cm5`, `xtb_solv_lebedev`, `xtb_solv_ddcosmo_*` |
| `src/tblite/` | 3 | 与外部 **tblite** 库接口的 calculator/映射/重启 | `xtb_tblite_calculator`, `xtb_tblite_mapping`, `xtb_tblite_restart` |
| `src/type/` | 28 | 全部**核心数据类型**（environment/molecule/calculator/restart/param/wavefunction/data…） | `xtb_type_environment`, `xtb_type_molecule`, `xtb_type_calculator`, `xtb_type_restart`, `xtb_type_param`, `xtb_type_data`, `xtb_type_wavefunction`, `xtb_type_setvar` 等 |
| `src/xtb/` | 15 | xTB 方法本体：GFN0/1/2 参数与哈密顿量、色散、EEQ、多极、三阶、排斥、Coulomb、GPU 哈密顿量 | `xtb_xtb_gfn2`, `xtb_xtb_gfn1`, `xtb_xtb_gfn0`, `xtb_xtb_hamiltonian`, `xtb_xtb_data`, `xtb_xtb_calculator`, `xtb_xtb_dispersion`, `xtb_xtb_eeq`, `xtb_xtb_repulsion`, `xtb_xtb_thirdorder`, `xtb_xtb_multipole`, `xtb_xtb_coulomb`, `xtb_xtb_halogen` |
| `symmetry/`（仓库根，非 src 下） | 2 | 独立对称性子库（`symmetry.f90` + `symmetry_i.c`），含 `symmetry`/`molecule_type` 等模块 | `symmetry`, C 侧 `symmetry_i.c` |

> 注：`src/mctc/` 本身不是“可选密度/密度泛函”，而是从 mctc-lib 复制进项目的**基础数值/IO/元素库**（见 `src/mctc/io.f90:1` `!> IO units`、`src/mctc/accuracy.f90` 的 `sp/wp` 定义）。它是全仓库最底层的依赖。

---

## 2. 顶层 src/*.f90 功能聚类

顶层共 **126** 个 Fortran 文件（`src/*.f90 + *.F90 + *.f`）。按职责聚类（文件名为准）：

- **SCF / SCC 与电子结构核心**：`scf_module.F90`(`xtb_scf`)、`scc_core.f90`(`xtb_scc_core`)、`broyden.f90`、`david.f`、`david2.f90`、`pseudodiag.f90`、`screening.f90`、`hlex.f90`、`onetri.f90`、`slater.f90`、`intgrad.f90`、`intmodes.f90`、`intpack.f90`、`grad_core.f90`、`aoparam.f90`、`lin.f90`、`lin_mod.f90`、`lidep.f90`、`shiftlp.f90`、`matinv.f90`、`htosq.f90`
- **EEQ / 电荷模型**：`eeq_model.f90`(`xtb_eeq`)、`charge_model.f90`、`iniq.f90`、`rabguess.f90`、`peeq_module.f90`
- **几何优化 & PES**：`geoopt_driver.f90`、`optimizer.f90`、`relaxation_engine.f90`、`bfgs.f90`、`lopt.f90`、`geosum.f90`、`neighbor.f90`、`ifind.f90`、`getkopt.f90`、`scan_driver.f90`、`scanparam.f90`、`cqpath.f90`、`bias_path.f90`、`metadynamic.f90`、`mdoptim.f90`、`modef.f90`、`locmode.f90`、`local.f90`
- **Hessian / 频率 & 热化学**：`hessian.F90`、`o1numhess.f90`、`anharmlib.f90`、`thermo.f90`、`detrotra.f90`、`dtrafo.f90`、`axis_trafo.f90`、`eqrot.f90`、`compliance.f90`、`modef.f90`；子目录 `src/freq/`、`src/model_hessian/`、`src/internals/`
- **IO / 打印**：`printout.f90`、`printmold.f90`、`header.f90`、`cube.f90`、`dipole.f90`、`esp.f`、`stm.f`、`surfac.f`、`aespot.F90`、`wrmo.f90`、`wrbas.f90`、`wrmodef.f90`、`wrgbw.f90`、`zmatpr.f90`、`prmat.f90`、`prmat2.f90`、`enso_printout.f90`、`xhelp.f90`、`getname.f90`、`filetools.F90`、`rdcoord2.f90`、`readl.f90`、`readl2.f90`、`restart.f90`、`define.f90`、`vertical.F90`
- **约束 / 动力学**：`constr.f90`、`constrain_param.f90`、`constrain_pot.f90`、`shake_module.f90`、`dynamic.f90`、`mdoptim.f90`、`qpot.f90`
- **碎片化 / ONIOM / 嵌入**：`fragment.f90`、`oniom.f90`、`embedding.f90`、`splitparam.f90`
- **GFN0/GFN1 遗留参数与读取**：`gfn0param.f90`、`read_gfn_param.f90`、`gfn_paramset.f90`、`gfn_prparam.f90`
- **PBC**：`pbc.f90`、`pbc_tools.f90`、`generate_wsc.f90`
- **杂项工具**：`basic_geo.f90`、`qsort.f90`、`ls_rmsd.f90`、`rmsd.f90`、`nvtx.f90`、`timing.f90`、`expire.f90`、`getsymnum.f90`、`rmrottr.f90`、`spline2.f90`、`spline3.f90`、`pocketscan.f90`、`drsp.f`、`makel.f90`

代表性声明：`src/scf_module.F90:1` `module xtb_scf`；`src/scc_core.f90:20` `module xtb_scc_core`；`src/hessian.F90:20` `module xtb_hessian`；`src/eeq_model.f90:20` `module xtb_eeq`。

---

## 3. 模块依赖图

### 3.1 fan-in 最高的 25 个模块（口径：引用文件数）

| # | count | 模块 | 提供文件 |
|---|---|---|---|
| 1 | 269 | `xtb_mctc_accuracy` | `src/mctc/accuracy.f90` |
| 2 | 98 | `xtb_type_environment` | `src/type/environment.f90` |
| 3 | 88 | `xtb_type_molecule` | `src/type/molecule.f90` |
| 4 | 79 | `xtb_mctc_convert` | `src/mctc/convert.f90` |
| 5 | 54 | `xtb_setparam` | `src/setparam.f90` |
| 6 | 47 | `xtb_mctc_constants` | `src/mctc/mctc_constants.f90` |
| 7 | 38 | `xtb_type_data` | `src/type/data.F90` |
| 8 | 34 | `xtb_type_restart` | `src/type/restart.F90` |
| 9 | 33 | `xtb_type_calculator` | `src/type/calculator.f90` |
| 10 | 33 | `xtb_mctc_blas` | `src/mctc/blas.f90` |
| 11 | 31 | `xtb_mctc_symbols` | `src/mctc/symbols.f90` |
| 12 | 29 | `xtb_type_param` | `src/type/param.f90` |
| 13 | 25 | `xtb_xtb_data` | `src/xtb/data.f90` |
| 14 | 25 | `xtb_readin` | `src/readin.f90` |
| 15 | 24 | `xtb_mctc_filetypes` | `src/mctc/filetypes.f90` |
| 16 | 23 | `xtb_fixparam` | `src/fixparam.f90` |
| 17 | 22 | `xtb_splitparam` | `src/splitparam.f90` |
| 18 | 20 | `xtb_mctc_lapack` | `src/mctc/lapack.f90` |
| 19 | 19 | `xtb_mctc_systools` | `src/mctc/systools.F90` |
| 20 | 18 | `xtb_mctc_io` | `src/mctc/io.f90` |
| 21 | 17 | `xtb_type_basisset` | `src/type/basisset.f90` |
| 22 | 16 | `xtb_io_writer` | `src/io/writer.f90` |
| 23 | 16 | `xtb_scanparam` | `src/scanparam.f90` |
| 24 | 15 | `xtb_mctc_math` | `src/mctc/math.f90` |
| 25 | 14 | `xtb_scc_core` / `xtb_sphereparam` | `src/scc_core.f90` / `src/sphereparam.f90` |

（外部/内在模块对照：`mctc_env` 25、`iso_fortran_env` 19、`tblite_basis_type` 19、`mctc_io` 19、`iso_c_binding` 17。）

### 3.2 枢纽模块（fan-in > 20）内容性质

- **`xtb_mctc_accuracy`（269）** `src/mctc/accuracy.f90` —— 纯常量模块：定义 `sp`/`wp` 数值精度。全仓库最底层。
- **`xtb_type_environment`（98）** `src/type/environment.f90` —— 定义 `TEnvironment`（IO 单元、消息日志、strict、hostname 等），是**显式传递的环境对象**，非全局单例。
- **`xtb_type_molecule`（88）** `src/type/molecule.f90` —— 分子数据结构（原子、坐标、晶格、电荷、自旋）。
- **`xtb_mctc_convert`（79）** `src/mctc/convert.f90` —— 单位换算常量（`autoaa` 等）。
- **`xtb_setparam`（54）** `src/setparam.f90` —— **全局输入参数**（见 §4）。
- **`xtb_mctc_constants`（47）** `src/mctc/mctc_constants.f90` —— 物理常量（`pi` 等）。
- **`xtb_type_data`（38）** `src/type/data.F90` —— 结果容器 `scc_results`、`freq_results`、IFF 结果、PCEM。
- **`xtb_type_restart`（34）** `src/type/restart.F90` —— `TRestart`：包裹波函数 + GFF 邻居表 + tblite cache。
- **`xtb_type_calculator`（33）** `src/type/calculator.f90` —— **抽象基类 `TCalculator`**（`singlepoint`/`hessian`/`writeInfo` 虚函数 + solvation 槽）。所有方法实现（xTB、GFF、IFF、PTB、tblite、extern）都继承它。
- **`xtb_mctc_blas`（33）** `src/mctc/blas.f90` —— BLAS 包装。
- **`xtb_mctc_symbols`（31）** `src/mctc/symbols.f90` —— 元素符号/序数。
- **`xtb_type_param`（29）** `src/type/param.f90` —— 参数派生类型（`scc_parameter`、`TRepulsionData` 等）。
- **`xtb_xtb_data`（25）** `src/xtb/data.f90` —— xTB 参数数据集容器（`TxTBData`、色散/排斥/哈密顿数据类型）。
- **`xtb_readin`（25）** `src/readin.f90` —— 输入文件解析。
- **`xtb_mctc_filetypes`（24）** `src/mctc/filetypes.f90` —— 文件类型探测。
- **`xtb_fixparam`（23）** `src/fixparam.f90` —— **全局约束/元动力学状态**（见 §4）。
- **`xtb_splitparam`（22）** `src/splitparam.f90` —— **全局 fragmentation/split 状态**（见 §4）。

### 3.3 子目录之间的 use 环（A↔B 双向）

（括号内为 A→B / B→A 的 use 次数）

- `src ↔ src/disp` (16/2)
- `src ↔ src/docking` (2/16)
- `src ↔ src/extern` (4/28)
- `src ↔ src/freq` (3/3)
- `src ↔ src/gfnff` (9/18)
- `src ↔ src/internals` (4/2)
- `src ↔ src/lbfgs_anc` (3/1)
- `src ↔ src/model_hessian` (4/4)
- `src ↔ src/ptb` (1/3)
- `src ↔ src/solv` (7/1)
- `src ↔ src/tblite` (1/6)
- `src ↔ src/type` (158/5)
- `src ↔ src/xtb` (31/25)
- `src/coulomb ↔ src/type` (11/1)
- `src/disp ↔ src/xtb` (1/5)
- `src/docking ↔ src/iff` (1/5)
- `src/gfnff ↔ src/main` (1/6)
- `src/gfnff ↔ src/type` (34/1)
- `src/iff ↔ src/main` (2/2)
- `src/iff ↔ src/type` (17/1)
- `src/mctc ↔ src/mctc/blas` (8/6)、`src/mctc ↔ src/mctc/lapack` (7/9)、`src/mctc ↔ src/mctc/param` (6/7)
- `src/mctc ↔ src/type` (2/53)
- `src/model_hessian ↔ src/type` (10/1)
- `src/solv ↔ src/type` (7/1)

> **关键循环**：`src/type ↔ src/model_hessian`（`xtb_type_calculator` 直接 use `xtb_modelhessian_swart`，见 `src/type/calculator.f90:30`）、`src/type ↔ src/solv`、`src/type ↔ src/iff`、`src/type ↔ src/gfnff`、`src/type ↔ src/coulomb`、`src/xtb ↔ src/disp`。这些环集中在 **type 层**，说明类型层反向依赖了 feature 实现，是分层的最主要破口。

---

## 4. 全局状态模块（separability 关键）

存在**两套并存的“全局状态”风格**：

### 4.1 `xtb_mctc_global` —— 真·全局单例
`src/mctc/mctc_global.F90:18-40`：
```fortran
module xtb_mctc_global
   use xtb_type_environment, only : TEnvironment
   character(len=:),allocatable :: name
   character(len=:),allocatable,target :: msgbuffer
   integer :: msgid
   integer :: maxmsg = 100
   logical :: is_release = .false.
   logical :: strict = .false.
   logical :: mute = .false.
   logical :: good = .true.
   type(TEnvironment), allocatable :: persistentEnv     !< Global environment
   type(errormsg),allocatable :: errorbuffer(:)
```
这是遗留的**进程级环境单例**（`persistentEnv` + 错误缓冲），被 12 个文件引用。

### 4.2 `xtb_setparam` 的 `set` —— 巨型全局输入结构
`src/setparam.f90:219` 定义 `type :: TSet`（219–538 行，~263 行成员），`src/setparam.f90:540`：
```fortran
   type(TSet) :: set
```
`set` 是模块级可变量（非 SAVE 显式声明但模块变量天然持久），被 **54** 个文件引用，涵盖 GFN 方法选择、SCF、温度、优化级别、MD、thermo、打印开关、cube/esp、solvInput 等所有运行选项。这是**输入参数的单体式全局容器**。
同类还有 `xenv`（`env_setvar`），被 `src/readin.f90:56` 引用。

### 4.3 其它模块级全局状态
- **`xtb_fixparam`**（fan-in 23）`src/fixparam.f90:27-38`：`fixset`、`shakeset`、`freezeset`、`metaset`、`rmsdset`（`type(fix_setvar)/metadyn_setvar` 模块变量）——约束、SHAKE、元动力学的全局状态。
- **`xtb_splitparam`**（fan-in 22）`src/splitparam.f90:30-43`：`maxsplit/iatf1/iatf2/splitlist(:)/iatf(:)/rcma/massf1/massf2/atmass(:)/maxfrag` —— fragmentation/split 的全局状态。
- **`xtb_sphereparam`**（fan-in 14）、**`xtb_scanparam`**（fan-in 16）、**`xtb_constrain_param`**、**`xtb_metadynamic`**（fan-in 12）等同样是模块级设置容器。
- **`xtb_type_setvar`** `src/type/setvar.f90`：定义各种 `*_setvar` 派生类型（`env_setvar/gfn_setvar/ancopt_setvar/modhess_setvar/fix_setvar/md_setvar/metadyn_setvar` 等），是 `TSet` 的成员类型来源。
- **`xtb_type_environment`**：`TEnvironment` 是**显式对象**（非单例），但 `xtb_mctc_global%persistentEnv` 保存了一份全局副本。

> 结论：真正被“人人读取”的全局状态是 `set`（全部运行参数）、`fixparam`/`splitparam`/`scanparam`/`sphereparam` 等模块变量，以及 `mctc_global`。`TEnvironment`/`TMolecule`/`TRestart`/`TCalculator` 则是**显式参数传递**的新式设计，两者在当前代码中并存。

---

## 5. 建议的分层（Level 0 叶 → 顶层驱动）

| 层 | 内容 | 允许依赖 |
|---|---|---|
| **L0 叶/基础** | `xtb_mctc_accuracy`、`xtb_mctc_constants`、`xtb_mctc_convert`、`xtb_mctc_math`、`xtb_mctc_blas/lapack`、`xtb_mctc_io`、`xtb_mctc_systools`、`xtb_mctc_strings`、`xtb_mctc_symbols`、`xtb_mctc_filetypes`、`xtb_mctc_global`、`src/param/*`、`src/mctc/*` | 仅 OS/intrinsic/外部库 |
| **L1 类型/常量数据** | `src/type/*`（environment、molecule、basisset、param、wavefunction、data、setvar…）、`src/xtb/data.f90` | L0 |
| **L2 数值/数学核** | `src/internals/*`、`src/model_hessian/*`、`src/disp/*`、`src/coulomb/*`、`src/solv/*` | L0–L1 |
| **L3 电子结构核** | `src/xtb/*`（gfn0/1/2、`hamiltonian.F90`、eeq、repulsion、multipole、thirdorder、dispersion、coulomb、halogen）、`src/scc_core.f90`、`scf_module.F90`、`grad_core.f90`、integral 文件 | L0–L2 |
| **L4 方法/模型** | `src/gfnff/*`、`src/iff/*`、`src/ptb/*`、`src/tblite/*`、`src/extern/*`、`src/dipro/*`、`src/docking/*`、`src/freq/*`、`src/io/*` | L0–L3 |
| **L5 装配/驱动** | `src/main/*`、几何优化（`geoopt_driver`、`relaxation_engine`、`optimizer`、`lbfgs_anc`）、`src/prog/*`、`src/api/*` | L0–L4 |

**GFN2 哈密顿量所处层级：**
- 参数本体 `src/xtb/gfn2.f90`（`module xtb_xtb_gfn2`，`!> GFN2-xTB parametrisation data`，`src/xtb/gfn2.f90:19`）在 **L3**；它 `use xtb_xtb_gfn1`（`gfn2.f90:25`）与 `xtb_disp_dftd4`（`gfn2.f90:26`），即强依赖 L2 色散与 L3 的 GFN1。
- 核心哈密顿量积分 `src/xtb/hamiltonian.F90`（`module xtb_xtb_hamiltonian`，`src/xtb/hamiltonian.F90:19`）也在 **L3**；它 `use xtb_intgrad`、`xtb_lin`、`xtb_scc_core`、`xtb_grad_core`（`hamiltonian.F90:23-26`）——**反向依赖顶层/核心文件**，因此 L3 与“SCF/SCC 核心”实际上交织在 `src/` 顶层。
- 方法组装 `src/xtb/calculator.f90`（`module xtb_xtb_calculator`）在 **L3/L4 边界**，因为它 use `xtb_scf`、`xtb_peeq`、`xtb_solv_*`、`xtb_basis`、`xtb_embedding`、`xtb_metadynamic` 等（`src/xtb/calculator.f90:20-51`），即 GFN calculator 直接拉入了 solv/ptb/embedding 等 feature。

---

## 6. 可选 feature 孤岛

| 孤岛 | 是否被核心拉入 | 拉入者（file:line） |
|---|---|---|
| **`src/gfnff/`** | 核心级（calculator 工厂） | `src/main/setup.f90:35` `use xtb_gfnff_calculator`；`src/prog/main.F90:72`。`newGFFCalculator` 分发（`setup.f90:128,140`）。且 `xtb_type_restart` 硬依赖 `xtb_gfnff_neighbourlist`（`src/type/restart.F90:24`），故 GFF 邻居表进了核心类型层。 |
| **`src/solv/`** | 核心级 | `src/setparam.f90:22` `use xtb_solv_input`、`xtb_solv_kernel`；`src/xtb/calculator.f90:21-23`；`src/main/setup.f90:21-22,232`。solv 输入类型进入全局 `set%solvInput`。 |
| **`src/ptb/`** | 可选方法 | `src/main/setup.f90:34` `use xtb_ptb_calculator`；`setup.f90:173,181` `newPTBcalculator`；`src/prog/main.F90`。仅当选择 PTB 方法时拉起。 |
| **`src/tblite/`** | 可选（编译开关） | 编译宏 `WITH_TBLITE`（`CMakeLists.txt:46-48`、`meson.build:119`）。使用者：`src/main/setup.f90:27`、`src/main/property.F90:292`、`src/prog/main.F90:96`、`src/dipro.F90:29`。`src/type/restart.F90` 在 `#if WITH_TBLITE` 下包裹 tblite。 |
| **`src/iff/`** | 可选方法 | `src/main/setup.f90:36-37` `use xtb_iff_calculator/xtb_iff_data`；`setup.f90:151-168` `newIFFCalculator`；`src/prog/main.F90:73`。 |
| **`src/dipro/`** | 独立 driver | `src/prog/main.F90`（`use xtb_dipro`）；`src/dipro.F90:29` 又 use tblite。是独立计算路径，不参与主 calculator。 |
| **`src/docking/`** | 可选搜索 | `src/prog/dock.f90`、`src/set_module.f90`、`src/local.f90`、及 `src/iff/*` 多个文件。`search_nci` 被 IFF 与 local 引用。 |
| **`src/extern/`** | 外部后端 | `src/main/setup.f90`（driver 分发）、`src/prog/main.F90`。 |
| **`src/model_hessian/`** | 被类型层拉入 | `src/type/calculator.f90:30` `use xtb_modelhessian_swart` —— 模型 Hessian 被抽象 calculator 直接依赖，属半核心。 |
| **`src/freq/`** | 可选后处理 | `src/prog/main.F90`、`src/prog/submodules.f90` 等（`src ↔ src/freq` 3/3）。 |
| **`src/mctc/`** | **非可选，是基础库** | 被全仓库 239 处引用；不是 feature 孤岛，而是 L0 底座。 |
| **`symmetry/`（仓库根）** | 独立库 | 独立 `symmetry.f90` + C 接口，供分子对称性分析调用（非 `src/` 内）。 |

---

## 7. 关键证据文件清单

- 全局状态：`src/setparam.f90:219,540`、`src/mctc/mctc_global.F90:18`、`src/fixparam.f90:27`、`src/splitparam.f90:30`、`src/type/setvar.f90:31`
- 抽象 calculator：`src/type/calculator.f90:35`
- 方法实现：`src/xtb/calculator.f90`、`src/gfnff/calculator.f90`、`src/iff/calculator.f90`、`src/ptb/calculator.F90`、`src/tblite/calculator.F90`
- GFN2/Hamiltonian：`src/xtb/gfn2.f90:19`、`src/xtb/hamiltonian.F90:19`
- 装配入口：`src/main/setup.f90`、`src/main/run.f90`、`src/prog/main.F90`
- 编译开关：`CMakeLists.txt:46`、`meson.build:119`（`WITH_TBLITE`）

## 8. 残差风险 / 开放问题

- `xtb_prog_main` 模块名与 `xtb__`（`src/main/run.f90`）入口命名不直观，子命令分发路径需进一步追踪 `src/prog/submodules.f90`。
- `src/mctc/lapack` 与 `src/mctc/blas` 间存在子目录双向环，属库内部封装细节，非架构破口。
- `symmetry/` 位于仓库根而非 `src/` 下，是否真被 `src/` 引用未在本轮确证，需单独核查。
- L3 内部（`src/*.f90` SCF/积分文件与 `src/xtb/*`）耦合紧密，实际物理分层比上表更扁平。
