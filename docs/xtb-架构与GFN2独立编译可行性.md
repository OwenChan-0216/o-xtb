# xtb 仓库架构、模块依赖与「GFN2-only 独立二进制」可行性分析

> **分析对象**：`grimme-lab/xtb`，版本 `6.7.1`
> **基线提交**：`17790202eb14eeb40effc05008f5508fb0a52157`（`git describe` = `bleed`）
> **分析方式**：4 路并行只读侦察 + 静态 `use` 传递闭包分析（`docs/_recon/closure.py`）+ **真实构建与缩减链接实验**（全部在 `/tmp` 进行，仓库工作树未被修改）
> **证据附录**：`docs/_recon/`（见文末索引）
> **撰写日期**：在本地实测环境上完成（gfortran 12.2.0 / cmake 4.3.2 / OpenBLAS）

---

## 0. 直接回答核心问题

> **「我是否能单独编译出一个二进制文件，专门用于例如 GFN2-xTB 的计算？」**

| 情形 | 结论 | 实测置信度 |
|---|---|---|
| **(i) 只改构建系统、一行源码都不改** | ❌ **不可行** | 高（≈95%） |
| **(ii) 允许新增/裁剪源码** | ✅ **可行**，且风险低 | 中高（≈85%） |
| 一个能跑 GFN2 的完整 `xtb` 二进制所需外部依赖下限 | 仅 **mctc-lib** + BLAS/LAPACK + OpenMP | 已实测成功 |
| 独立 GFN2 二进制是否需要运行时数据文件 | ❌ **不需要**（GFN2 参数已编译进二进制） | 已实测 |

**一句话结论**：仓库目前**不存在**任何「按方法裁剪」的构建开关，唯一可执行入口 `src/prog/main.F90` **无条件** `use` 了 gfnff / iff / ptb / tblite / solv / oniom / dipro / extern / docking 全套特性模块，因此**只动构建系统必然断链**（实测：删掉 `src/gfnff/` 目标文件 → 46 处 undefined reference；删掉全部特性目录 → 251 处）。但只要允许**新写一个约 200–400 行、只 `use` GFN2 所需模块的最小 driver**，并在 CMake/Meson 里加一个显式源列表的可执行目标，就能得到一个真正只支持 GFN2 的独立二进制——因为 **GFN2 的计算内核（SCF/SCC、Coulomb、Dispersion、Repulsion、Multipole、H0）全部是 in-tree 自包含实现**，不依赖 dftd4 / s-dftd3 / multicharge / tblite 这些外部半经验库。预估工作量：**最小 driver 约 0.5–1 人日**；彻底裁剪现有 CLI 约 **3–5 人日**。

---

## 1. 仓库总览

### 1.1 顶层目录

| 路径 | 作用 |
|---|---|
| `CMakeLists.txt`, `cmake/` | CMake 构建（≥3.17）：目标定义、依赖查找、安装规则 |
| `meson.build`, `meson/`, `meson_options.txt` | Meson 构建（≥0.62）：与 CMake 等价的第二套构建 |
| `src/` | 全部实现源码（362 个 Fortran/C 文件，23 个子目录） |
| `symmetry/` | 独立对称性子库（`symmetry.f90` + C 接口 `symmetry_i.c`），**源码**而非运行时数据 |
| `include/xtb.h` | C/C++ 公共 API 头文件 |
| `subprojects/` | 仅 6 个 `.wrap` 文件（`wrap-git`），**没有 vendored 源码** |
| `param_gfn0/1/1-si/2/ipea-xtb.txt`, `.param_gfnff.xtb` | 方法参数表（**运行时可选**，见 §4.6） |
| `test/` | `test/api`（C API 示例）、`test/unit`（31 个测试套件 + CLI 冒烟测试） |
| `python/`, `scripts/`, `man/`, `assets/` | 绑定、脚本、手册、打包资源 |
| `.github/workflows/fortran-build.yml` | CI：gcc/intel × meson/cmake × 多种依赖组合 |

### 1.2 两套构建系统

CMake 目标图（`CMakeLists.txt`）：

| 目标 | 类型 | 组成 | 链接 |
|---|---|---|---|
| `xtb-object` | OBJECT | **全部 `${srcs}`（≈355 文件，无条件）** | mctc-lib、cpcmx?、tblite?、OpenMP? |
| `lib-xtb-static` | STATIC | `xtb-object` 的对象集合 | BLAS/LAPACK、OpenMP?、mctc-lib、cpcmx?、tblite? |
| `lib-xtb-shared` | SHARED | 同上，**仅 `WITH_OBJECT=ON` 时生成** | 同上 |
| `xtb-exe` → 输出名 `xtb` | EXECUTABLE | `${prog}`（`src/prog/` 9 个文件） | `lib-xtb-static` |
| `xtb_tests_capi` | EXECUTABLE | `test/api/c_api_example.c` | `lib-xtb-shared` |
| `xtb-tester` | EXECUTABLE | `test/unit/*.f90` | `lib-xtb-static` + test-drive |

> 关键：`xtb-object` 是**唯一**把库源码编进的目标，静态/共享库都只是它的对象包装。**`${srcs}` 的组装没有任何 `WITH_*` 条件**——没有 `WITH_GFNFF` 之类的功能开关（`src/CMakeLists.txt:17-42`）。

Meson 侧同构：`xtb_lib`（`library()`，默认 both）、`xtb_exe`（`executable()`）、`xtb_c_test`、`tester`。差异：Meson 有 `gpu`/`nvtx` 选项并仅在 `-Dnvtx=true` 时编译 `src/nvtx.f90`（CMake 从不编译它）。

### 1.3 只有「一个」可执行文件，内含 6 个子命令

真正含 `program` 的只有 `src/prog/primary.f90`（`program xtb_prog_primary`）。`main.F90`、`info.f90`、`thermo.f90`、`topology.f90`、`dock.f90`、`irmod.f90` 都是**模块 + 顶层过程**，由 `primary.f90:51-57` 的 `select case` 分派：

| 子命令 | 过程 | 用途 |
|---|---|---|
| （默认）`main` | `xtbMain`（`src/prog/main.F90:111`） | 单结构计算 / 优化 / MD —— **GFN2 走这条** |
| `info` | `xtbInfo` | 只读几何+参数，打印元素信息，不跑电子结构 |
| `thermo` | `xtbThermo` | 由外部 Hessian 算热化学 |
| `topo` | `xtbTopology` | 生成 GFN-FF 力场拓扑 |
| `dock` | `xtbDock` | 片段对接 |
| `ir` | `xtbIR` | 由 DFTB+ Hessian 算 IR/Raman |

**同一 `program` 的所有 `case` 分支都会被链接进同一个二进制**——这正是不改源码、只改构建就无法裁剪的根因之一。

---

## 2. 模块地图与职责

### 2.1 `src/` 子目录职责

| 目录 | 文件数 | 定位 | 关键模块 |
|---|---|---|---|
| `src/mctc/` | 49 | **基础数值/IO/元素库**（内嵌的 MCTC 库）：精度、常量、BLAS/LAPACK 包装、字符串、数学、元素符号、路径工具 | `xtb_mctc_accuracy`, `xtb_mctc_convert`, `xtb_mctc_blas`, `xtb_mctc_lapack`, `xtb_mctc_systools`, `xtb_mctc_symbols`, `xtb_mctc_global` |
| `src/type/` | 28 | **核心数据类型**：environment / molecule / calculator（抽象基类）/ restart / param / wavefunction / data | `xtb_type_environment`, `xtb_type_molecule`, `xtb_type_calculator`, `xtb_type_restart`, `xtb_type_data` |
| `src/param/` | 10 | 静态元素参数表（原子质量/半径/电负性/R4R2/…） | `xtb_param_atomicmass`, `xtb_param_covalentrad`, `xtb_param_vdwrad*` |
| `src/xtb/` | 15 | **xTB 方法本体**：GFN0/1/2 参数与哈密顿量、EEQ、多极、三阶、排斥、Coulomb、色散、GPU H | `xtb_xtb_gfn2`, `xtb_xtb_gfn1`, `xtb_xtb_gfn0`, `xtb_xtb_hamiltonian`, `xtb_xtb_calculator`, `xtb_xtb_coulomb`, `xtb_xtb_multipole` |
| `src/coulomb/` | 3 | 解析库仑核：Ewald / Gaussian / **Klopman–Ohno** | `xtb_coulomb_klopmanohno`, `xtb_coulomb_ewald`, `xtb_coulomb_gaussian` |
| `src/disp/` | 7 | **in-tree 的 D3/D4 色散**与配位数 | `xtb_disp_dftd4`, `xtb_disp_dftd3`, `xtb_disp_ncoord`, `xtb_disp_coordinationnumber` |
| `src/gfnff/` | 19 | GFN-FF 力场全套（拓扑、参数、能量/梯度、邻居表） | `xtb_gfnff_calculator`, `xtb_gfnff_param`, `xtb_gfnff_topology` |
| `src/iff/` | 6 | Intrinsic Fragmentation Framework（LMO 片段能量） | `xtb_iff_calculator`, `xtb_iff_data` |
| `src/ptb/` | 18 | PTB 半经验哈密顿量（property/response）—— **唯一用外部 dftd4/multicharge 的方法** | `xtb_ptb_calculator`, `xtb_ptb_hamiltonian` |
| `src/tblite/` | 3 | 与外部 **tblite** 库的桥接（受 `WITH_TBLITE` 控制） | `xtb_tblite_calculator` |
| `src/solv/` | 14 | 隐式溶剂化：GBSA / COSMO / CPCM-X / SASA / Lebedev / DDCOSMO | `xtb_solv_gbsa`, `xtb_solv_cosmo`, `xtb_solv_cpx`, `xtb_solv_model` |
| `src/io/` | 8 | 分子读/写（通用 + ORCA/Turbomole/Gaussian 片段格式） | `xtb_io_reader`, `xtb_io_writer` |
| `src/main/` | 6 | 顶层装配：默认值、几何准备、calculator 工厂、JSON/属性输出 | `xtb_main_setup`, `xtb_main_defaults`, `xtb_propertyoutput` |
| `src/prog/` | 9 | CLI 层：参数解析、子命令分派、主驱动 | `xtb_prog_main`, `xtb_prog_argparser`, `xtb_prog_submodules` |
| `src/api/` | 7 | C/Fortran 公共 API（`bind(C)`） | `xtb_api_calculator`, `xtb_api_interface` |
| `src/freq/` | 3 | 频率分析：投影、IO、工具 | `xtb_freq_project` |
| `src/model_hessian/` | 7 | 模型 Hessian（Lindh/Swart/EEQ/GFF/Internal） | `xtb_modelhessian_swart` |
| `src/internals/` | 3 | 冗余内坐标 | `xtb_internals_redundant` |
| `src/lbfgs_anc/` | 6 | 周期体系 L-BFGS 优化器 | `xtb_pbc_optimizer_lbfgs` |
| `src/dipro/` | 5 | Dimer Projection 方法 | `xtb_dipro` |
| `src/docking/` | 3 | 非共价 docking 搜索 | `xtb_docking_search_nci` |
| `src/extern/` | 4 | 外部 QM 程序驱动（MOPAC/ORCA/Turbomole） | `xtb_extern_driver` |

> ⚠️ 常见误解澄清：`src/mctc/` **不是**「密度泛函/多组态」，而是从 mctc-lib 项目复制进仓库内部的**基础数值与 IO 库**，是全仓库最底层依赖。

### 2.2 顶层 `src/*.f90` 功能聚类（126 个文件）

| 聚类 | 主要文件 |
|---|---|
| **SCF / SCC 与电子结构核心** | `scf_module.F90`, `scc_core.f90`, `broyden.f90`, `screening.f90`, `hlex.f90`, `onetri.f90`, `slater.f90`, `intgrad.f90`, `grad_core.f90`, `aoparam.f90`, `lin.f90`, `lin_mod.f90`, `matinv.f90`, `htosq.f90` |
| **EEQ / 电荷模型** | `eeq_model.f90`, `charge_model.f90`, `iniq.f90`, `rabguess.f90`, `peeq_module.f90` |
| **几何优化 & PES** | `geoopt_driver.f90`, `optimizer.f90`, `relaxation_engine.f90`, `bfgs.f90`, `lopt.f90`, `scan_driver.f90`, `scanparam.f90`, `metadynamic.f90`, `mdoptim.f90`, `local.f90` |
| **Hessian / 频率 / 热化学** | `hessian.F90`, `o1numhess.f90`, `anharmlib.f90`, `thermo.f90`, `detrotra.f90`, `compliance.f90` |
| **IO / 打印** | `printout.f90`, `dipole.f90`, `aespot.F90`, `restart.f90`, `readin.f90`, `wrmo.f90`, `cube.f90`, `esp.f`, `stm.f`, `surfac.f` |
| **遗留固定格式（fixed-form）** | `david.f`, `drsp.f`, `esp.f`, `stm.f`, `surfac.f`, `disp/dftd3.f`, `gfnff/gfnff_rab.f`, `gfnff/math.f` |
| **约束 / 动力学** | `constr.f90`, `constrain_param.f90`, `constrain_pot.f90`, `shake_module.f90`, `dynamic.f90` |
| **碎片化 / ONIOM / 嵌入** | `fragment.f90`, `oniom.f90`, `embedding.f90`, `splitparam.f90` |
| **GFN0/1 参数与读取** | `gfn0param.f90`, `read_gfn_param.f90`, `gfn_paramset.f90`, `gfn_prparam.f90` |
| **PBC** | `pbc.f90`, `pbc_tools.f90`, `generate_wsc.f90` |

### 2.3 模块依赖分层（Level 0 叶 → Level 5 驱动）

```
L5 装配 / 驱动     src/prog/*   src/api/*   src/main/*   几何优化(geoopt_driver, optimizer, lbfgs_anc)
        ▲
L4 方法 / 模型     src/gfnff/*  src/iff/*  src/ptb/*  src/tblite/*  src/extern/*  src/dipro/*  src/docking/*  src/freq/*  src/io/*
        ▲
L3 电子结构核      src/xtb/*  (gfn0,gfn1,gfn2, hamiltonian, coulomb, dispersion, repulsion, eeq, multipole, thirdorder)
                   + src/scf_module.F90  src/scc_core.f90  src/grad_core.f90  src/intgrad.f90
        ▲
L2 数值 / 数学核   src/internals/*  src/model_hessian/*  src/disp/*  src/coulomb/*  src/solv/*
        ▲
L1 类型 / 常量     src/type/*  src/xtb/data.f90
        ▲
L0 叶 / 基础       src/mctc/*   src/param/*    [ 唯一外部硬依赖: mctc-lib ]  [ BLAS / LAPACK / OpenMP ]
```

**GFN2 哈密顿量位于 L3**：参数本体 `src/xtb/gfn2.f90`（`module xtb_xtb_gfn2`），积分核 `src/xtb/hamiltonian.F90`（`module xtb_xtb_hamiltonian`）。

### 2.4 依赖枢纽（fan-in Top 模块）

| 排名 | fan-in（引用文件数） | 模块 | 性质 |
|---|---|---|---|
| 1 | **269** | `xtb_mctc_accuracy` | 纯精度常量 `sp`/`wp` |
| 2 | **98** | `xtb_type_environment` | `TEnvironment`（**显式传递**，非单例） |
| 3 | **88** | `xtb_type_molecule` | 分子数据结构 |
| 4 | 79 | `xtb_mctc_convert` | 单位换算常量 |
| 5 | **54** | **`xtb_setparam`** | **全局 `set` 巨型结构（263 个成员）** |
| 6 | 47 | `xtb_mctc_constants` | 物理常量 |
| 7 | 38 | `xtb_type_data` | 结果容器 |
| 8 | 34 | `xtb_type_restart` | 波函数 + GFN-FF 邻居表 + tblite cache |
| 9 | 33 | `xtb_type_calculator` | **抽象基类 `TCalculator`**（所有方法实现都继承它） |
| 11 | 31 | `xtb_mctc_symbols` | 元素符号 |
| 14 | 25 | `xtb_xtb_data` | `TxTBData` 方法参数数据库 |
| 16 | **23** | **`xtb_fixparam`** | **全局约束/SHAKE/元动力学状态** |
| 17 | **22** | **`xtb_splitparam`** | **全局 fragmentation 状态** |

### 2.5 ⚠️ 全局状态：可分离性的最大阻碍

代码库中**两套风格并存**：

**(A) 真·全局单例** —— `src/mctc/mctc_global.F90:18-40`
```fortran
module xtb_mctc_global
   character(len=:),allocatable :: name, msgbuffer
   logical :: is_release, strict, mute, good
   type(TEnvironment), allocatable :: persistentEnv     !< 全局环境副本
   type(errormsg),allocatable :: errorbuffer(:)
```

**(B) 模块级全局输入容器** —— `src/setparam.f90:219` 定义 `type :: TSet`（约 263 行成员），`:540` 声明
```fortran
   type(TSet) :: set
```
`set` 被 **54 个文件**读取，涵盖 GFN 方法选择、SCF、温度、优化级别、MD、thermo、打印开关、cube/esp、`solvInput` 等**全部运行选项**。同类全局状态还有：

- `xtb_fixparam`（fan-in 23）：`fixset`/`shakeset`/`freezeset`/`metaset`/`rmsdset`
- `xtb_splitparam`（fan-in 22）：`maxsplit`/`splitlist`/`iatf`/`massf1`…
- `xtb_sphereparam`（14）、`xtb_scanparam`（16）、`xtb_constrain_param`、`xtb_metadynamic`（12）
- `xenv`（`env_setvar`，`src/readin.f90:56`）

> **含义**：即使只跑 GFN2，这些全局模块也必须存在（否则 `scf_module.F90`、`calculator.f90`、`main.F90` 编译不过）。它们是**静态必需的耦合**，不是可选功能。

### 2.6 反向依赖与循环（分层破口）

`src/type/` 作为「类型层」本应只被依赖，但它**反向 `use` 了多个 feature 实现**：

| 循环 | 证据 |
|---|---|
| `src/type` ↔ `src/model_hessian` | `src/type/calculator.f90:30` `use xtb_modelhessian_swart` |
| `src/type` ↔ `src/gfnff` | `src/type/restart.F90:24` 硬依赖 `xtb_gfnff_neighbourlist` |
| `src/type` ↔ `src/solv` | `src/type/calculator.f90` 持有 solvation 槽 |
| `src/type` ↔ `src/iff` / `src/coulomb` | 同上模式 |
| `src/xtb` ↔ `src/disp` | `src/xtb/gfn2.f90:26` `use xtb_disp_dftd4` |

**最典型的破口**：抽象基类 `TCalculator` 直接依赖 Swart 模型 Hessian，GFN-FF 邻居表被硬编码进核心 `TRestart` 类型 —— 这意味着**「纯 GFN2」在类型层就已经被污染**。

---

## 3. GFN2-xTB 调用链

### 3.1 完整 hop 序列

```
src/prog/primary.f90:19      program xtb_prog_primary
  └─ :44-49                  mctc_init / init(env) / init(argParser)
  └─ :51                     getRunmode(argParser, runMode)        → 默认 xtbSubmodule%main
  └─ :55-57 (case main)      call xtbMain(env, argParser)
       ▼
src/prog/main.F90:111        subroutine xtbMain(env, argParser)
  └─ :296                    set%gfn_method = 2                    (GFN2 为默认)
  └─ :~1380                  parseArguments  →  --gfn2
  └─ :613                    call newCalculator(...)               → src/main/setup.f90
  └─ :616                    call initDefaults(...)                → src/main/defaults.f90
  └─ :623                    chk%wfn%allocate(...)
  └─ :650                    call iniqcn(...)   (GFN2 初猜)         → src/iniq.f90:257
  └─ :661                    call iniqshell(...)                   → src/scc_core.f90:1475
  └─ :682                    calc%writeInfo(...)
  └─ :736                    call calc%singlepoint(..., 2, ...)     ← ★ 电子结构主调用
  └─ :1077                   call main_property(...)               → src/main/property.F90:104
  └─ :882 / :1204            (若几何优化) geometry_optimization     → src/geoopt_driver.f90:23
       ▼
src/xtb/calculator.f90:195   TxTBCalculator%singlepoint
  └─ case (1,2)              call scf(...)
       ▼
src/scf_module.F90:74        subroutine scf  — 经典项 + 积分准备
  └─ :410/430/439            Coulomb 矩阵 (Klopman–Ohno)
  └─ :498                    repulsionEnGrad
  └─ :536                    D4 色散 init
  └─ :548/558                getSelfEnergy / build_SDQH0
  └─ :567-586                Multipole (AES)
  └─ :615                    call scc(...)                          → src/scc_core.f90:255
  └─ :712/718/731/753/784    梯度相关
       ▼
src/scc_core.f90:255         subroutine scc
  └─ :371                    scc_iterator（迭代循环）
       ├─ :376-393           ies%addShift + setvsdq + solvation%addShift + scD4%addShift
       ├─ :439/441           buildIsoAnisotropicH1 / buildIsotropicH1
       ├─ :473               call solver%fact_solve(env, H, S_factorized, emo)  ← 对角化（mctc-lib）
       ├─ :483               Fermi 展宽
       ├─ :503/506/512       dmat / mpopsh / electro
       ├─ :524               aniso_electro (AES)
       ├─ :529               D4 色散
       ├─ :556-565           收敛判据
       └─ :601-615           call broyden（默认加速器）
```

### 3.2 `--gfn2` 的方法分派

| 步骤 | 位置 | 说明 |
|---|---|---|
| CLI 解析 | `src/prog/main.F90:1556-1558` | `case('--gfn2')` → `set_gfn(env,'method','2')` + `set_gfn(env,'d4','true')` |
| 默认值 | `src/prog/main.F90:1360` | `set%gfn_method = 2`（**GFN2 就是默认方法**） |
| 写入全局 | `src/set_module.f90:1510-1561` | `set_gfn` 把整数 0/1/2 写进 `set%gfn_method` |
| 构造计算器 | `src/main/setup.f90:97-117` | `case(p_ext_eht, p_ext_xtb)` → `newXTBCalculator(env, mol, xtb, fname, set%gfn_method, accuracy)` |
| 参数选择 | `src/xtb/calculator.f90:127-129` | `method==2` → 文件名 `param_gfn2-xtb.txt` |
| 参数一致性校验 | `src/xtb/calculator.f90:164-168` | `method /= calc%xtbData%level` 报错 |
| level 来源 | `src/xtb/gfn2.f90:738` | `self%level = 2` |

> ⚠️ **纠正常见误解**：源码中**没有** GFN method 枚举类型。`set%gfn_method` 就是一个普通整数，靠 0/1/2 的隐含约定。真正的枚举只有 `p_run_*`（运行类型，`src/setparam.f90:197-215`）与 `p_ext_*`（外部方法，`:183-195`）。`src/main/defaults.f90` 只做优化器/溶剂默认值，**不参与方法分派**。
>
> ⚠️ `src/main/run.f90` 是一个 **28 行的空死模块**（`module xtb__`，注释 `!> TODO`），既不被任何地方 `use`，也**未被 `src/main/CMakeLists.txt` 收录**（只列 `defaults/geometry/json/property/setup`）。

### 3.3 GFN2 各能量项：全部 in-tree

| 贡献 | 参数侧 | 运行侧调用点 | 来源 |
|---|---|---|---|
| **Repulsion** | `src/xtb/gfn2.f90:752` | `src/scf_module.F90:498` → `src/xtb/repulsion.F90:41` | ✅ **in-tree** |
| **Coulomb（二阶）** | `src/xtb/gfn2.f90:777` | `src/scf_module.F90:410/439` → `src/coulomb/klopmanohno.F90` | ✅ **in-tree** |
| **Third-order（三阶静电）** | `src/xtb/gfn2.f90:940` | `src/xtb/thirdorder.f90`（`TxTBCoulomb` 内嵌） | ✅ **in-tree** |
| **Dispersion（D4）** | `src/xtb/gfn2.f90:762/772` `newD4Model` | `src/scf_module.F90:536`；`src/scc_core.f90:415/547` | ✅ **in-tree 的 dftd4**（`src/disp/dftd4.F90`）—— 不是外部 dftd4 包 |
| **Multipole / AES** | `src/xtb/gfn2.f90:798` | `src/scf_module.F90:567-586`；`src/scc_core.f90:389/526` → `src/aespot.F90` | ✅ **in-tree** |
| **Core Hamiltonian H0** | `src/xtb/gfn2.f90:809` | `src/scf_module.F90:548/558` → `src/xtb/hamiltonian.F90:47/98/146` | ✅ **in-tree** |
| **Basis set** | 来自 `TxTBData%hamiltonian` | `src/xtb/calculator.f90:177` → `src/xtb/basisset.f90:33` | ✅ **in-tree，无外部基组文件** |
| ~~EEQ~~ | `src/xtb/eeq.f90` | 仅 `src/peeq_module.f90:28`（**GFN0/PEEQ**） | ❌ **GFN2 不使用** |
| ~~Halogen bond~~ | GFN2 **不分配** `xtbData%halogen` | `src/scf_module.F90:505-511` 有 `if (allocated(...))` 守门；`:372` 注释 `! not used in GFN2` | ❌ **GFN2 不使用** |
| ~~D3~~ | — | `src/scf_module.F90:531`（GFN1/GFN0 分支） | ❌ **GFN2 走 else 分支** |

> ⚠️ **纠正常见误解**：
> - `src/xtb/gfn2.f90` 的语义是「**编译内置的 GFN2 参数数据 + 各子数据结构初始化器**」（`initGFN2`，`:731`），而**不是**运行时哈密顿量装配器。真正的装配在 `src/scf_module.F90` 与 `src/scc_core.f90`。
> - 外部包 `dftd4` / `s-dftd3` / `multicharge` **只被 PTB（`src/ptb/calculator.F90:41`、`src/ptb/coulomb.F90:35`）和 CPCM-X（`src/solv/cpx.F90`）使用**，GFN2 关键路径完全不依赖它们。

### 3.4 SCF / SCC 两层结构

**第一层 `scf`**（`src/scf_module.F90:74`）—— 一次 SCC 调用的全部准备与收尾：维度/基组/占用、壳层自能、Coulomb 矩阵、排斥、D4、AES、H0/积分；随后进入迭代；迭代后构造全部梯度（`build_dSDQH0`、多极梯度、D4 梯度、Coulomb 导数）、偶极/键级。

**第二层 `scc`**（`src/scc_core.f90:255`，核心循环 `scc_iterator` at `:371`）—— 真正的 SCC 迭代：每轮 `addShift` → 构造 H1 → 对角化 → Fermi 展宽 → 密度矩阵 → 能量 → 收敛判据 → Broyden 加速。

**关键实现细节**：对角化已从自研的 Davidson/PseudoDiag **迁移到 mctc-lib 的特征求解器**：
```fortran
src/scc_core.f90:473   !call solve(fulldiag,ndim,ihomo,scfconv,H,S,X,P,emo,fail)   ← 已注释
src/scc_core.f90:475    call solver%fact_solve(env, H, S_factorized, emo)         ← 实际路径
```

**GFN2 路径上的死代码（不要误当作必需）**：

| 文件 | GFN2 单点是否需要 | 依据 |
|---|---|---|
| `src/pseudodiag.f90` | ❌ 不需要 | 仅被 `src/scc_core.f90:970` 的 `solve` 调用；而 `solve` 的唯一活跃调用者是对 GFN0 的 `src/peeq_module.f90:481`（`:473` 的 `call solve` 已注释） |
| `src/david.f` | ❌ 不需要 | 全仓库无任何 `call ddavid/sdavid/dvdssvd`（已 grep 确认） |
| `src/david2.f90` | ⚠️ 单点不需要，**优化/弛豫需要** | 被 `src/optimizer.f90:26`、`src/relaxation_engine.f90:28` use |
| `src/xtb/eeq.f90`、`src/disp/encharges.f90` | ❌ 不需要 | 仅 GFN0/PEEQ 路径 |
| `src/xtb/halogen.f90` | ❌ 运行时不触发 | 但被 `src/scf_module.F90` 静态 `use`，**链接必需** |

### 3.5 「梯度总是被算」

`src/xtb/calculator.f90:258` 的 `scf(..., .true., ...)` 第 9 个实参（`grd`）**恒为 `.true.`**，梯度数组始终填充。因此「GFN2 单点」与「GFN2 单点 + 梯度」在电子结构层面是**同一条调用路径**，`--sp`/`--grad` 只影响打印与 `lgrad` 标志。

### 3.6 运行时数据：GFN2 **不需要任何磁盘数据文件**

参数读取逻辑（`src/xtb/calculator.f90:149-160`）：
```fortran
call open_file(ich, filename, 'r')          ! 先尝试磁盘 param_gfn2-xtb.txt
if (ich /= -1) then
   call readParam(env, ich, globpar, calc%xtbData, .true.)
else                                         ! 打不开 → 回退到编译内置参数
   call use_parameterset(filename, globpar, calc%xtbData, exist)
```

内置参数在 `src/gfn_paramset.f90:64-83`：
```fortran
case('param_gfn2-xtb.txt')
   globpar = gfn2Globals
   call initGFN2(xtbData)
```

`gfn2Globals`（`src/xtb/gfn2.f90:52`）与 `initGFN2`（`:731`）把**整张 GFN2 参数表**（selfEnergy、slaterExponent、chemicalHardness、thirdOrderAtom、D4 参考电荷…）编译进二进制。

> ✅ **结论**：一个 GFN2-only 二进制**可以做到零运行时数据文件依赖**（`param_gfn2-xtb.txt` 只是「可选的优先来源」）。`symmetry/` 是**源码目录**（点群识别 C 库），不是运行时数据目录。`XTBPATH`/`XTBHOME`（`src/type/environment.f90:140-149`）只在需要 `.xtbrc`、`xtbrestart`、控制文件时才有意义。

---

## 4. 核心问题：能否单独编译 GFN2-only 二进制？

### 4.1 为什么「只改构建系统」不可行

**根因 1：唯一入口无条件 `use` 全套特性模块。**

`src/prog/main.F90`（已 grep 确认，无任何 `#if` 或条件保护）：
```fortran
:29   use xtb_tblite_restart, only: loadRestart, dumpRestart
:43   use xtb_gfnff_shake, only: gff_init_shake => init_shake
:72   use xtb_gfnff_calculator
:73   use xtb_iff_calculator, only: TIFFCalculator
:87   use xtb_gfnff_param, only: gff_print
:88   use xtb_gfnff_topology, only: TPrintTopo
:89   use xtb_gfnff_convert, only: struc_convert
:92   use xtb_iff_iffprepare, only: prepare_IFF
:93   use xtb_iff_data, only: TIFFData
:94   use xtb_oniom, only: oniom_input, TOniomCalculator, calculateCharge
:96   use xtb_tblite_calculator, only: TTBLiteCalculator, ...
:98   use xtb_ptb_calculator, only: TPTBCalculator
:99   use xtb_solv_cpx, only: TCpcmx
:100  use xtb_dipro, only: get_jab, jab_input
```

计算器工厂 `src/main/setup.f90` 同样无条件：
```fortran
:21-23  use xtb_solv_input / xtb_solv_model
:24-26  use xtb_extern_orca / mopac / turbomole / driver
:27     use xtb_tblite_calculator
:34-38  use xtb_ptb_calculator / xtb_gfnff_calculator / xtb_iff_calculator / xtb_iff_data / xtb_oniom
```

**构建系统只能决定「编不编译某个文件」，无法移除源码里的 `use`。** 只要 `main.F90` 被编译，那些 `.mod` 就必须存在；一旦按「只留 GFN2 源文件」缩减，编译/链接立即失败。

**根因 2：仓库不存在任何现成的 GFN2-only 可执行目标。** `src/prog/` 只有全套 CLI，`test/` 是测试。

**根因 3：全局状态模块静态必需。** `set`（`src/setparam.f90:540`）、`fixparam`、`splitparam`、`sphereparam`、`scanparam`、`metadynamic`、`mctc_global%persistentEnv` 被 GFN2 核心链（`scf_module.F90`、`calculator.f90`、`main.F90`）直接 `use`，即使逻辑上只跑 GFN2 也无法省略。

### 4.2 实测证据：缩减链接实验

方法：用完整构建产出的 `xtb-object` 全部 `.o`，手工逐组剔除特性目录后重新链接，统计 undefined reference。

```bash
gfortran -fdefault-real-8 -fdefault-double-8 <prog objs> -o OUT \
         <xtb-object objs 减去 EXCLUDE> _deps/mctc-lib-build/libmctc-lib.a \
         -lopenblas -lm -ldl -fopenmp
```

| EXCLUDE | 退出码 | undefined reference 行数 | 典型未定义符号 |
|---|---|---|---|
| `/gfnff/` | 1 | **46** | `__xtb_gfnff_calculator_MOD_newgffcalculator`, `..._Tgffcalculator`(23×), `__xtb_gfnff_param_MOD_gff_print`, `__xtb_gfnff_shake_MOD_init_shake` |
| `/gfnff/\|/iff/` | 1 | **61** | 上面 + `__xtb_iff_iffenergy_MOD_iff_e`(5×), `..._iffprepare_MOD_precomp` |
| `/gfnff/\|/iff/\|/ptb/\|/solv/` | 1 | **102** | 上面 + `__xtb_ptb_calculator_MOD_...`, `__xtb_solv_gbsa_MOD_..._Tborn` |
| 全部特性目录（gfnff/iff/ptb/dipro/docking/solv/api/tblite） | 1 | **251** | `__xtb_docking_param_MOD_optlvl`(43×), `__xtb_docking_set_module_MOD_set_logicals`, `__xtb_tblite_calculator_MOD_...` |

> 完整原始输出：`docs/_recon/reduced-link-output.txt`

### 4.3 ⚠️ 模块闭包会「低估」真实链接依赖

**关键陷阱**：遗留 Fortran 代码用隐式外部过程（`external`）而非 `use`，这些**不会**出现在模块闭包里，但链接时必需。实测：

| 剔除文件 | 产生的 undefined reference |
|---|---|
| `src/lin.f90.o` | **`lin_`**（来自 `src/scc_core.f90:218`） |
| `src/pqn.f90.o` | **`ncore_`** |
| `src/lin_mod.f90.o` | **`__xtb_lin_MOD_lin`**（来自 `src/xtb/hamiltonian.F90:282`） |

源码证据：
```fortran
src/scc_core.f90:179   integer, external :: lin
src/scc_core.f90:394   integer,external :: lin
src/prog/main.F90:170  integer, external :: ncore
src/optimizer.f90:1139 real(wp), external :: ddot
src/main/geometry.f90:477  real(wp), external :: valijkl
```

`COMMON` 块仅存在于 `src/esp.f:66` 与 `src/intpack.f90`。此外多个文件**重复定义同名 standalone 符号**（`valijkl` 同时在 `src/basic_geo.f90:245` 与 `src/constr.f90:816`；`lin` 同时在 `src/lin.f90:22` 与 `src/lin_mod.f90:29` 的模块内），静态库链接「先到先得」，一旦改动源文件列表极易触发重复/未定义符号。

**结论**：不能简单地「按 `use` 闭包裁源文件」。必须同时把 legacy standalone 符号的提供者保留在源列表中。

### 4.4 闭包也会「高估」依赖

`closure.py` 数到的 54 个仓库外模块中含有大量 `tblite_*`，但这些 `use` 全部位于 `#if WITH_TBLITE` 之内（如 `src/tblite/calculator.F90:29-49`、`src/type/data.F90:26-27`），预处理后并不存在。**实测 `WITH_TBLITE=OFF` 时这些外部模块根本不出现。** 因此静态统计会误报 tblite 依赖，必须以实测开关为准。

### 4.5 外部依赖的真实下限

| 依赖 | 必需性 | 控制开关 | 版本 |
|---|---|---|---|
| **mctc-lib** | ✅ **无条件必需**（`CMakeLists.txt:42-43` `find_package(... REQUIRED)`） | 无 | v0.5.1 |
| BLAS / LAPACK | ✅ 必需 | 无 | 系统（OpenBLAS 等） |
| OpenMP | 可选（默认 ON） | `WITH_OpenMP` | 系统 |
| tblite | 可选（默认 ON） | `WITH_TBLITE` | v0.6.0 |
| cpcmx | 可选（默认 ON） | `WITH_CPCMX` | v1.1.0 |
| dftd4 / s-dftd3 / multicharge / mstore / numsa / toml-f | 传递依赖（**GFN2 路径不需要**） | 随 tblite/cpcmx | — |
| test-drive | 仅测试 | `WITH_TESTS` | v0.5.0 |

依赖查找策略（`cmake/modules/xtb-utils.cmake:31`）：`cmake config → pkgconf → subprojects/ → FetchContent`。离线环境下 `subprojects/` 只有 `.wrap` 文件（**无 vendored 源码**），因此**离线连普通构建都做不了**。

### 4.6 ✅ 实测：完整构建 + GFN2 真实运行成功

在本机（gfortran 12.2.0 / cmake 4.3.2 / OpenBLAS）实测：

```bash
cmake -S . -B /tmp/xtb-red2/build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=OFF
cmake --build /tmp/xtb-red2/build -j
```
```
-- Retrieving mctc-lib from https://github.com/grimme-lab/mctc-lib
-- Configuring done (20.7s)
[100%] Linking Fortran executable xtb
[100%] Built target xtb-exe
```

产物：`/tmp/xtb-red2/build/xtb`（13.9 MB）、`libxtb.a`（21.6 MB）。抓取的 mctc-lib = `v0.5.1`（`aa89d4b`）。

真实 GFN2 单点（水分子，`/tmp/w.xyz`）：
```
$ XTBPATH=<repo> /tmp/xtb-red2/build/xtb /tmp/w.xyz --gfn2 --sp
      :  Hamiltonian                  GFN2-xTB          :
     :: total energy              -5.070383095219 Eh    ::
     :: HOMO-LUMO gap             14.518987926825 eV    ::
normal termination of xtb
```

> ✅ **一个能跑 GFN2 的完整二进制，其外部依赖下限就是 mctc-lib（+ BLAS/LAPACK/OpenMP）。**
>
> ⚠️ **环境坑 1**：用**默认选项**在 cmake 4.3.2 下配置会**直接失败**——`WITH_CPCMX=ON` 让 cpcmx 与 xtb 自己 fetch 的 toml-f 抢同名 imported target：
> ```
> add_library cannot create imported target "toml-f::toml-f" because another target with the same name already exists.
> ```
> 必须显式 `-DWITH_CPCMX=OFF`。
>
> ⚠️ **环境坑 2**：gfortran 需要 `-fdefault-real-8 -fdefault-double-8`（见 `cmake/CMakeLists.txt:50,58`、`meson/meson.build:30-31`），自己写最小 driver 时必须沿用，否则 `wp` 精度不一致。

### 4.7 ✅ 可行路径

#### 路径 A（推荐）：新写最小 GFN2 driver

复用现有引擎 API，写一个约 **200–400 行** 的 `program`，只 `use` GFN2 所需模块：

```fortran
program xtb_gfn2_only
   use xtb_type_environment        ! TEnvironment
   use xtb_type_molecule           ! TMolecule
   use xtb_type_restart            ! TRestart
   use xtb_type_calculator         ! TCalculator (class)
   use xtb_xtb_calculator, only : TxTBCalculator, newXTBCalculator
   use xtb_main_setup,     only : initDefaults
   use xtb_io_reader,      only : readMolecule
   use xtb_main_defaults
   use xtb_single                  ! 或直接调用 calc%singlepoint
   use xtb_printout
   ! 可选: xtb_geoopt_driver (优化), xtb_main_propertyoutput (输出)
```

GFN2 引擎链的**运行时必需 in-tree 文件**（按目录）：

| 目录 | 必需文件 |
|---|---|
| `src/xtb/` | `calculator.f90`, `data.f90`, `gfn2.f90`, `gfn1.f90`*, `gfn0.f90`*, `hamiltonian.F90`, `coulomb.f90`, `dispersion.f90`, `repulsion.F90`, `thirdorder.f90`, `multipole.f90`, `basisset.f90`, `halogen.f90`* |
| `src/` 根 | `scf_module.F90`, `scc_core.f90`, `iniq.f90`, `lin.f90`, `lin_mod.f90`, `pqn.f90`, `broyden.f90`, `set_module.f90`, `setparam.f90`, `readin.f90`, `read_gfn_param.f90`, `gfn_paramset.f90`, `aespot.F90`, `grad_core.f90`, `intgrad.f90`, `slater.f90`, `dipole.f90`, `hlex.f90`, `charge_model.f90`, `embedding.f90`, `local.f90`, `fixparam.f90`, `scanparam.f90`, `sphereparam.f90`, `splitparam.f90`, `metadynamic.f90`, `constrain_pot.f90`, `constrain_param.f90`, `basic_geo.f90`*, `intpack.f90`*, `readl.f90`* |
| `src/coulomb/` | `klopmanohno.F90` |
| `src/disp/` | `dftd4.F90`, `dftd4_parameters.f90`, `ncoord.f90`, `coordinationnumber.F90` |
| `src/type/` | `environment.f90`, `molecule.f90`, `calculator.f90`, `restart.f90`, `wavefunction.f90`, `basisset.f90`, `param.f90`, `data.F90`, `setvar.f90`, `timer.f90`, `coulomb.f90`, `dispersion_model.f90`, `latticepoint.f90`, `neighbourlist.f90`, `solvation.f90`, `pcem.f90`, `iohandler.f90`, `reader.F90` 等 |
| `src/param/` | `atomicrad.f90`, `paulingen.f90`, `covalentrad*.f90`, `vdwrad*.f90` 等 |
| `src/mctc/` | 几乎全量（`accuracy`, `blas`, `lapack`, `convert`, `systools`, `io`, `param`, `symbols`, `filetypes`, `mctc_global`, `mctc_init`, `timings`, `strings`…） |

(*) 标记项：运行时不调用，但因 `use`/隐式 external 而**静态必需**。

CMake 侧新增目标示意：
```cmake
add_executable(xtb-gfn2-exe ${gfn2_prog} ${gfn2_srcs})
target_link_libraries(xtb-gfn2-exe PRIVATE ${BLAS_LIBRARIES} ${LAPACK_LIBRARIES}
                      mctc-lib::mctc-lib "$<$<BOOL:${WITH_OpenMP}>:OpenMP::OpenMP_Fortran>")
```
**仍然需要独立编译一份对象文件**（不能复用 `xtb-object`，因为它包含全部目录）。

#### 路径 B：裁剪现有 CLI

把 `src/prog/main.F90`（2231 行）、`src/main/setup.f90`、`defaults.f90`、`argparser.f90`、`submodules.f90`、`topology.f90`、`dock.f90`、`property.F90`、`json.F90` 中的非 GFN2 分支与对应 `use` 删除。工作量更大（特性逻辑深度交织），收益是 CLI 行为与现有 `xtb` 完全一致。

### 4.8 ⚠️ 不能删的耦合清单

| 耦合 | 证据 | 后果 |
|---|---|---|
| GFN2 → GFN1 | `src/xtb/gfn2.f90:25` `use xtb_xtb_gfn1, only : setGFN1ShellHardness` | **GFN1 代码不能整块删除** |
| GFN2 → `gfn_paramset` | `src/gfn_paramset.f90:21-23` 同时 `use` gfn0/gfn1/gfn2 | 三种方法的符号都必须存在 |
| 隐式 standalone | `lin` / `ncore` / `pqn` / `valijkl` / `ddot` | 提供者必须在源列表中，或同步改调用点 |
| 分子 IO → mctc-lib | `src/io/reader.f90`, `src/io/writer.f90`, `src/mctc/filetypes.f90` | 无法回避（除非重写 IO） |
| 类型层反向依赖 | `src/type/calculator.f90:30` → `xtb_modelhessian_swart`；`src/type/restart.F90:24` → `xtb_gfnff_neighbourlist` | GFN-FF 邻居表 + 模型 Hessian 进了核心类型层 |
| `symmetry/` | `symmetry/symmetry.f90` + `symmetry_i.c` 参与几何处理 | 需保留 |
| 全局状态 | `set`, `fixparam`, `splitparam`, `sphereparam`, `scanparam`, `metadynamic`, `mctc_global` | 静态必需，不可省略 |
| `src/solv/` 被类型层拉入 | `src/setparam.f90:22` `use xtb_solv_input`（solv 输入类型进入全局 `set%solvInput`）；`src/xtb/calculator.f90:21-23` | 即使只跑气相 GFN2，solv 类型也需存在 |
| `src/disp/dftd3` | `src/scf_module.F90:26` `use xtb_disp_dftd3, only: d3_gradient` | GFN1/GFN0 分支用，但静态必需 |

### 4.9 工作量与障碍汇总

| 障碍 | 性质 | 影响 |
|---|---|---|
| `main.F90` 无条件 `use` 全部特性模块 | 源码结构 | **(i) 不可行的根因**；裁剪需动 2000+ 行 |
| `TCalculator` 类型层反向依赖 feature | 架构设计 | 类型层无法「纯净」，需保留 GFF/Solv/model-Hessian 类型 |
| 模块闭包低估链接依赖（隐式 external） | 遗留代码 | 按闭包裁源文件会 undefined reference（`lin`/`ncore`/`valijkl`） |
| 模块闭包高估依赖（`#if` 保护） | 预处理 | 静态统计误报 tblite；以实测开关为准 |
| 全局状态 `set` 等模块变量 | 设计遗留 | 静态必需，不可裁剪 |
| mctc-lib 本地缺失、只能联网 fetch | 环境 | 离线环境无法构建 |
| cmake 4.3.2 与默认 cpcmx/toml-f 目标冲突 | 环境 | 必须显式 `-DWITH_CPCMX=OFF` |
| 需 `-fdefault-real-8 -fdefault-double-8` | 构建 | 自写 driver 必须沿用 |
| 两套构建系统需同步（新增源文件要同时改 CMake 与 Meson） | 工程 | `src/model_hessian/` 无独立 CMakeLists，易漏 |

**估算**：
- 新写最小 GFN2 driver（含构建目标）：**≈0.5–1 人日**
- 扩展到支持几何优化：**+0.5 人日**
- 彻底裁剪现有 CLI：**≈3–5 人日**

---

## 5. 可复现命令

```bash
# ---------- 1. 静态 use 闭包分析 ----------
python3 docs/_recon/closure.py            > docs/_recon/closure-output.txt
python3 docs/_recon/closure.py --only-main >> docs/_recon/closure-output.txt

# ---------- 2. 真实构建（仅需 mctc-lib） ----------
cmake -S . -B /tmp/xtb-red2/build \
      -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=OFF
cmake --build /tmp/xtb-red2/build -j

# ---------- 3. GFN2 单点验证 ----------
printf '3\nwater\nO 0.0 0.0 0.0\nH 0.0 0.0 0.96\nH 0.93 0.0 -0.24\n' > /tmp/w.xyz
XTBPATH=$PWD /tmp/xtb-red2/build/xtb /tmp/w.xyz --gfn2 --sp

# ---------- 4. 缩减链接实验模板 ----------
gfortran -fdefault-real-8 -fdefault-double-8 <prog objs> -o OUT \
  <xtb-object objs 减去 EXCLUDE> _deps/mctc-lib-build/libmctc-lib.a \
  -lopenblas -lm -ldl -fopenmp
```

---

## 6. 证据附录索引

| 文件 | 内容 |
|---|---|
| `docs/_recon/01-build-system.md` | 构建目标图、外部依赖矩阵、构建选项、运行时数据路径、安装规则、CI |
| `docs/_recon/02-module-map.md` | `src/` 全目录职责、顶层文件聚类、fan-in 排序、use 环、全局状态、分层建议 |
| `docs/_recon/03-gfn2-call-chain.md` | GFN2 完整 hop 序列、方法分派、能量项构成、SCF/SCC 结构、最小文件清单 |
| `docs/_recon/04-separability-experiment.md` | 环境实测、静态闭包、缩减链接实验、判定与工作量 |
| `docs/_recon/closure.py` | 静态 `use` 传递闭包脚本（支持 `--only-main`） |
| `docs/_recon/closure-output.txt` | 闭包脚本的两份真实输出（455 行） |
| `docs/_recon/reduced-link-output.txt` | 缩减链接实验的真实 undefined reference 原始输出 |
| `docs/_recon/environment.txt` | 工具链与第三方库实测输出 |

---

## 7. 关键文件速查

| 目的 | 文件 |
|---|---|
| 全部 CMake 目标/依赖/安装规则 | `CMakeLists.txt` |
| `${srcs}` / `${prog}` 单体清单组装 | `src/CMakeLists.txt` |
| 单可执行 + 6 子命令分派 | `src/prog/primary.f90`、`src/prog/submodules.f90` |
| GFN2 主驱动 | `src/prog/main.F90`、`src/main/setup.f90` |
| 方法分派与参数选择 | `src/xtb/calculator.f90`、`src/set_module.f90:1510` |
| GFN2 参数数据（内置） | `src/xtb/gfn2.f90`、`src/gfn_paramset.f90` |
| 哈密顿量 / 积分 | `src/xtb/hamiltonian.F90`、`src/intgrad.f90`、`src/slater.f90` |
| SCF / SCC 驱动 | `src/scf_module.F90`、`src/scc_core.f90` |
| 抽象 calculator 基类 | `src/type/calculator.f90` |
| 全局输入参数 | `src/setparam.f90:219,540`（`type TSet` / `set`） |
| 全局环境单例 | `src/mctc/mctc_global.F90:18` |
| 抽象基类接口 | `src/type/calculator.f90:43-55` |
| 运行时路径解析 | `src/type/environment.f90:140`、`src/mctc/systools.F90:66`（`rdpath`） |
| 依赖四级查找 | `cmake/modules/xtb-utils.cmake` |
| C API | `include/xtb.h`、`src/api/` |

---

*本文档由 4 路并行只读侦察 + 静态闭包分析 + 真实构建/链接实验综合而成。所有「实测」标注的结论均已在本地工具链上复现，原始输出见 `docs/_recon/`。仓库工作树未被修改。*
