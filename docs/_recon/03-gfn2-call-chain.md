# GFN2-xTB 调用链完整 Recon（xtb 6.7.1）

> 仓库：`grimme-lab/xtb`，版本 `6.7.1`（`CMakeLists.txt:29`）。
> 所有引用均为仓库根目录相对路径 `file:line`。本报告只做侦察，不修改任何受版本控制的文件。
> 任务描述里给出的「入口 `src/prog/main.F90`」并不准确：真正的 `program` 是 `src/prog/primary.f90`，`main.F90` 只是 `module xtb_prog_main`。详见 §1。

---

## 0. 一页速览（TL;DR）

- 可执行文件是一个**单体（monolithic）**程序：`src/CMakeLists.txt` 把几乎所有方法（GFN0/1/2、GFN-FF、IFF、PTB、TBLite、ONIOM、外部程序接口）编译进同一目标，运行时靠 `set%runtyp` / `set%mode_extrun` / `set%gfn_method` 分派。**GFN2 单点这一条分支只用到其中很小一部分，但为了链接需要整个对象库存在。**
- 真实入口：`src/prog/primary.f90:19 program xtb_prog_primary` → `:57 call xtbMain`（`case(xtbSubmodule%main)`）。子命令（info/thermo/topo/dock/ir）是**平级的另一个 program 分支**，`main.F90` 到不了它们。
- 方法分派：`--gfn2` → `src/prog/main.F90:1556-1558` → `set_gfn(env,'method','2')` + `set_gfn(env,'d4','true')` → 写入全局 `set%gfn_method`（`src/set_module.f90:1510`）。默认值就是 `set%gfn_method = 2`（`src/prog/main.F90:1360`）。
- 计算器：`src/main/setup.f90` 的 `newCalculator` 造出多态的 `TxTBCalculator`（`src/xtb/calculator.f90:60`），它持有 `TxTBData`（`src/xtb/data.f90`）。`TxTBData%level==2` 就是 GFN2。
- 单点：`calc%singlepoint`（`src/xtb/calculator.f90:195`）在 `case(1,2)` 下调用 `scf`（`src/scf_module.F90:258`）。GFN0（`level==0`）才走 `peeq`。
- SCF：`scf`（`src/scf_module.F90:74`）做全部经典项与积分设置，然后调用 `scc`（`src/scc_core.f90:255`）跑 SCC 迭代；对角化用 mctc-lib 的 `solver%fact_solve`（`src/scc_core.f90:473`）。**`david.f` / `david2.f90` / `pseudodiag.f90` 在 GFN2 路径里是死代码/其它用途**（见 §4）。
- 参数/数据：`param_gfn2-xtb.txt` **优先从磁盘读**（`src/xtb/calculator.f90:149`），失败则回退到**编译进二进制的** GFN2 参数（`src/gfn_paramset.f90:64-83` + `src/xtb/gfn2.f90:731`）。GFN2 参数本身有两套：磁盘 `.txt` 与内置 `initGFN2`。`symmetry/` 是源码目录（点群 C 库），不是运行时数据目录（§5）。

---

## 1. 入口与子命令分派

### 1.1 program 真正在哪里

| hop | 位置 | 说明 |
|---|---|---|
| 1 | `src/prog/primary.f90:19` | `program xtb_prog_primary`——真正的可执行入口 |
| 2 | `src/prog/primary.f90:44-49` | `call mctc_init` / `init(env)` / `init(argParser)` |
| 3 | `src/prog/primary.f90:51` | `call getRunmode(argParser, runMode)` |
| 4 | `src/prog/primary.f90:55-57` | `case(xtbSubmodule%main)` → `call xtbMain(env, argParser)` |
| 5 | `src/prog/main.F90:111` | `subroutine xtbMain(env, argParser)` 开始 |

`getRunmode`（`src/prog/primary.f90:82-113`）取第一个命令行参数（`--gfn2` 之前的位置参数），默认 `runMode = xtbSubmodule%main`（`:94`），用 `getSubmodule` 把字符串翻译成枚举。

### 1.2 子命令枚举（`src/prog/submodules.f90`）

`type TSubmoduleEnum`（`src/prog/submodules.f90:34-57`）定义：`main=1, info=2, thermo=3, topo=4, dock=5, ir=6`。
`getSubmodule`（`:63-91`）把 `'info'`/`'thermo'`/`'topo'`/`'dock'`/`'ir'` 字符串映射到枚举，其它返回 `invalid`。

### 1.3 备选子命令：都是独立入口，**从 main.F90 不可达**

`primary.f90` 的 `select case` 分支直接调用各自模块的顶层过程：

| 子命令 | 文件 | 过程 | 用途 |
|---|---|---|---|
| `main` | `src/prog/main.F90` | `xtbMain` (`:111`) | 默认：单结构计算（本文重点） |
| `info` | `src/prog/info.f90` | `xtbInfo` (`:42`) | 读几何/参数，打印元素信息，不跑电子结构 |
| `thermo` | `src/prog/thermo.f90` | `xtbThermo` (`:45`) | 由已有 Hessian（DFT-B/DFTB+ 等）算热化学/频率 |
| `topo` | `src/prog/topology.f90` | `xtbTopology` (`:43`) | 生成 GFN-FF 力场拓扑 |
| `dock` | `src/prog/dock.f90` | `xtbDock` (`:66`) | 片段对接（`docking/` 模块） |
| `ir` | `src/prog/irmod.f90` | `xtbIR` (`:45`) | 由 DFTB+ Hessian 算 IR/Raman 强度（模块名 `xtb_prog_ir`） |

**结论**：`info/dock/irmod/thermo/topology` 与 `main` 是**互斥的分派分支**，`main.F90` 里没有任何 `call xtbInfo/xtbThermo/...`，因此对「普通单结构计算」而言它们**不参与运行**，但因为是同一 program 的其它 `case`，会被链接进可执行文件（见 §7）。
另外 `src/prog/irmod.f90` 对应子命令名是 `ir`，文件名叫 `irmod.f90`，不要混淆。

### 1.4 `xtbMain` 主线（GFN2 单点相关）

| hop | 位置 | 动作 |
|---|---|---|
| a | `src/prog/main.F90:296` | 初始化 `set%gfn_method = 2`（默认 GFN2） |
| b | `src/prog/main.F90:~1380` | `parseArguments` 解析 CLI，`--gfn2` 见 §2 |
| c | `src/prog/main.F90:613` | `call newCalculator(env, mol, calc, fnv, restart, set%acc, oniom, iff_data, tblite)` → `src/main/setup.f90` |
| d | `src/prog/main.F90:616` | `call initDefaults(env, calc, mol, gsolvstate)` → `src/main/defaults.f90` |
| e | `src/prog/main.F90:623` | `call chk%wfn%allocate(...)` 分配波函数 |
| f | `src/prog/main.F90:650` | `call iniqcn(...)` 初猜电荷（`src/iniq.f90:257 iniqcn_gfn2`） |
| g | `src/prog/main.F90:661` | `call iniqshell(...)` 壳层电荷初猜（`src/scc_core.f90:1475`） |
| h | `src/prog/main.F90:682` | `call calc%writeInfo(...)` |
| i | `src/prog/main.F90:692` | `call readRestart(...)` 可选读取 `xtbrestart` |
| j | `src/prog/main.F90:736` | `call calc%singlepoint(env, mol, chk, 2, exist, etot, g, sigma, egap, res)` ← **电子结构主调用** |
| k | `src/prog/main.F90:1077` | `call main_property(...)`（`src/main/property.F90:104`）汇总输出 |
| l | `src/prog/main.F90:882 / 1204` | 几何优化时 `call geometry_optimization(...)`（`src/geoopt_driver.f90:23`） |

### 1.5 `src/main/run.f90` 是死文件

`src/main/run.f90` 只有 28 行、内容是空模块 `xtb__`（`src/main/run.f90:21-28`，注释 `!> TODO`），**没有被任何地方 `use`**，而且**根本没被 `src/main/CMakeLists.txt` 收录**（该 CMake 只列 `defaults/geometry/json/property/setup`）。所以它既不是调用链的一环，也不参与编译。
`src/main/property.F90` 的模块名是 `xtb_propertyoutput`（`src/main/property.F90:22`），被 `main.F90:49 use xtb_propertyoutput` 引入，用于能量/梯度/频率/JSON 输出。

---

## 2. 方法分派：`--gfn2` 如何被选中

### 2.1 CLI → 全局状态

- `src/prog/main.F90:1556-1558`：
  ```fortran
  case ('--gfn2')
     call set_gfn(env, 'method', '2')
     call set_gfn(env, 'd4', 'true')
     tblite%method = "gfn2"
  ```
- 对应的旧式 `--gfn 2` 走 `src/prog/main.F90:1539-1548`（`set_gfn(env,'method',sec)`），`--gfn 1/0` 走 `:1550-1565`。
- 默认值：`src/prog/main.F90:1360 set%gfn_method = 2`。
- `set_gfn` 定义在 `src/set_module.f90:1510-1561`，`case('version','method')` 里把整数范围 0..2 写进 `set%gfn_method`（`:1539`），数值 3 会被降级为 2 并告警。
- `set%gfn_method` 是**普通整数**（`src/setparam.f90` 中 `set` 结构体成员），不是枚举；GFN 方法常量只有隐含 0/1/2 约定。真正的枚举是「运行类型」`p_run_*`（`src/setparam.f90:197-215`）和「外部方法」`p_ext_*`（`src/setparam.f90:183-195`，其中 `p_ext_xtb=1`）。**没有专门的 GFN method enum**——任务里说的「method enum」在 `src/main/defaults.f90` 里并不存在，`defaults.f90` 只做优化器引擎/溶剂默认值。

### 2.2 全局状态 → 计算器类型

- `src/main/calculator` 的 `newCalculator`（`src/main/setup.f90:54-206`）根据 `set%mode_extrun` 分派。绝大多数 GFN2 情形落到 `case (p_ext_eht, p_ext_xtb)`（`src/main/setup.f90:97-117`）：
  ```fortran
  allocate (xtb)
  call newXTBCalculator(env, mol, xtb, fname, set%gfn_method, accuracy)
  call move_alloc(xtb, calc)
  ```
  即把 `set%gfn_method` 作为 `method` 传入。
- `TxTBCalculator` 类型：`src/xtb/calculator.f90:60`（`type, extends(TCalculator) :: TxTBCalculator`），抽象基类 `TCalculator` 在 `src/type/calculator.f90:43-55`（含 deferred 的 `singlepoint`/`writeInfo`）。
- `newXTBCalculator`（`src/xtb/calculator.f90:101`）：
  - `method==2` 时选文件名 `param_gfn2-xtb.txt`（`src/xtb/calculator.f90:127-129`）；
  - 造 `calc%xtbData` 并 `readParam`（`:152`）或 `use_parameterset`（`:155`）；
  - `method /= calc%xtbData%level` 会报错（`:164-168`）——即**方法号必须与参数文件里的 `level` 一致**；
  - 造基组 `call newBasisset(calc%xtbData, ...)`（`:177`）。
- GFN2 的“level=2”由数据模块决定：`src/xtb/gfn2.f90:738 self%level = 2`。磁盘参数文件则在 `src/read_gfn_param.f90` 的 `read_info` 里读 `case('level')`（`:332-333`）。

### 2.3 计算器 → Hamiltonian/参数数据

- `TxTBData` 定义在 `src/xtb/data.f90:287`，字段：`level`、`nShell`、`repulsion`、`hamiltonian`、`coulomb`、`dispersion`、`multipole`、`halogen`、`srb`、`ipeashift`。它**不是**“一个 Hamiltonian 对象”，而是“方法参数数据库”。
- GFN2 的具体填充在 `src/xtb/gfn2.f90`（`initData`，`:731`）：
  ```fortran
  self%level = 2
  call initGFN2(self%repulsion)
  call initGFN2(self%dispersion)
  call initGFN2(self%coulomb, self%nShell)
  allocate(self%multipole); call initGFN2(self%multipole)
  call initGFN2(self%hamiltonian, self%nShell)
  ```
  （注意：GFN2 **不分配 `halogen`**，详见 §3。）

---

## 3. GFN2 各能量项的构成与来源（含 in-tree / 外部库判定）

任务里假设 `src/xtb/gfn2.f90` 是“接线各贡献”的文件。**实际上 `gfn2.f90` 是“编译内置的 GFN2 参数数据 + 各子数据结构初始化器”**，它本身**不**在运行时调用 coulomb/dispersion/… 的计算例程。真正的“接线”发生在 `src/scf_module.F90` 与 `src/scc_core.f90`。下表同时给出两侧信息。

| 贡献 | 参数侧（数据来源） | 运行计算侧（调用点） | in-tree / 外部库 |
|---|---|---|---|
| Repulsion（原子对排斥） | `src/xtb/gfn2.f90:752 initRepulsion` → `src/xtb/data.f90` 的 `initRepulsion` | `src/scf_module.F90:498 call repulsionEnGrad(mol, xtbData%repulsion, ...)`；实现 `src/xtb/repulsion.F90:41` | **in-tree** |
| Coulomb（二阶，Klopman–Ohno 壳层） | `src/xtb/gfn2.f90:777 initCoulomb`（写 `shellHardness`/`thirdOrderShell`，`setGFN1ShellHardness` 复用） | 类型 `TxTBCoulomb`（`src/xtb/coulomb.f90:19`）由 `src/scf_module.F90:410 call init(ies, xtbData%coulomb, ...)`；矩阵 `coulomb%getCoulombMatrix`（`src/scf_module.F90:439`）来自 `src/coulomb/klopmanohno.F90`（`module xtb_coulomb_klopmanohno`，`src/scf_module.F90:24` 引入） | **in-tree**（Klopman–Ohno 在 `src/coulomb/klopmanohno.F90`） |
| Third-order（三阶静电） | `src/xtb/gfn2.f90:940 setGFN2ThirdOrderShell` | `src/xtb/coulomb.f90` 的 `TxTBCoulomb` 内嵌 `TThirdOrder`（`src/xtb/coulomb.f90:34`），实际在 `addShift`/能量里用（`src/xtb/thirdorder.f90`） | **in-tree** |
| Dispersion（D4） | `src/xtb/gfn2.f90:762 initDispersion` → `call newD4Model(self%dispm, self%g_a, self%g_c, p_refq_gfn2xtb)`（`:772`） | GFN2（level≠1）走 `call init(scD4, xtbData%dispersion, mol)`（`src/scf_module.F90:536`）；SCC 内 `scD4%getEnergy/addShift`（`src/scc_core.f90:415`/`:547`）；梯度 `d4_gradient`（`src/scf_module.F90:753`） | **in-tree 的 dftd4**：`module xtb_disp_dftd4` 位于 `src/disp/dftd4.F90:19`（+ `src/disp/dftd4_parameters.f90`）。**不是**外部 `dftd4`/`s-dftd3` 包 |
| D3（仅 GFN1/GFN0） | — | `src/scf_module.F90:531 call d3_gradient`（`src/disp/dftd3.f90`，`module xtb_disp_dftd3`） | in-tree，但 **GFN2 不走** |
| Multipole / AES（偶极-四极静电） | `src/xtb/gfn2.f90:798 initMultipole`（`allocate(self%multipole)` 在 `:745`） | `src/scf_module.F90:567-586` + `:689-690`；`src/scc_core.f90:389-392`（`setvsdq`）、`:526`（`aniso_electro`）；类型 `TxTBMultipole`（`src/xtb/multipole.f90:25`） | **in-tree**（`src/aespot.F90` 提供 `mmompop/aniso_electro/setvsdq/get_radcn/dradcn`） |
| Core Hamiltonian（H0） | `src/xtb/gfn2.f90:809 initHamiltonian` | `src/scf_module.F90:558 call build_SDQH0(...)`；`src/xtb/hamiltonian.F90:146`；自能 `getSelfEnergy`（`src/scf_module.F90:548`，`src/xtb/hamiltonian.F90:47/98`） | **in-tree**（`src/xtb/hamiltonian.F90`，依赖 `src/intgrad.f90`、`src/slater.f90`、`src/scc_core.f90:shellPoly/h0scal`、`src/grad_core.f90:dshellPoly`） |
| Basis set | 数据来自 `TxTBData%hamiltonian`（`selfEnergy/slaterExponent/numberOfPrimitives`） | `src/xtb/calculator.f90:177 call newBasisset(...)`；实现在 `src/xtb/basisset.f90:33`（aux: `src/slater.f90`） | **in-tree，无外部基组文件** |
| EEQ 电荷均衡 | `src/xtb/eeq.f90`（`module xtb_xtb_eeq`，`:19`） | **不在 GFN2 路径**：只被 `src/disp/encharges.f90:24`（→ `src/peeq_module.f90:28`，GFN0/PEEQ）使用 | in-tree，但 **GFN2 不使用** |
| Halogen bond（XB） | GFN2 **不分配** `xtbData%halogen` | `src/scf_module.F90:505-511` 用 `if (allocated(xtbData%halogen))` 守门；`src/scf_module.F90:372` 明确注释 `! not used in GFN2`；实现 `src/xtb/halogen.f90:33 xbpot` | **in-tree，但 GFN2 不使用**（GFN1 才用，见 `src/xtb/gfn1.f90:578`） |

### 3.1 外部库判定小结

- GFN2 的**静电/色散/排斥/多极/哈密顿量全部是 in-tree** 实现。
- 外部包（`subprojects/*.wrap`、`CMakeLists.txt:51` 的 `multicharge dftd4 s-dftd3 tblite`）只被 **PTB**（`src/ptb/calculator.F90:41 use multicharge_model`、`src/ptb/coulomb.F90:35 use dftd4_data_hardness`）和 `solv/cpx.F90`（`use mctc_env`）路径使用，GFN2 关键路径不依赖它们。
- 外部 **mctc-lib** 是底层数值库（`use xtb_mctc_*`），GFN2 依赖它（eigensolver、BLAS/LAPACK、`rdpath` 等）。

---

## 4. SCF / SCC 驱动结构

### 4.1 两层结构

1. **`src/scf_module.F90`（模块 `xtb_scf`，`scf` 子程序，`:74`）**——负责“一次 SCC 调用的全部准备与收尾”：
   - 维度/基组/占用（`occu` `:346`）、壳层自能（`setzshell` `:338`）；
   - 经典项：Coulomb 矩阵（`:410/430/439`）、排斥（`:498`）、色散 `scD4`（`:536`）、多极 AES（`:567-586`）、卤键（`:505`，GFN2 不触发）；
   - H0/积分：`getSelfEnergy`（`:548`）、`build_SDQH0`（`:558`）；
   - 进入迭代：`call scc(...)`（`:615`，`src/scc_core.f90:255`）；
   - 梯度：`build_dSDQH0(_noreset)`（`:712/718`）、多极梯度（`:731-742`）、D4 梯度（`:753`）、Coulomb 导数（`:784`）、偶极/键级（`:868+`）。
2. **`src/scc_core.f90`（模块 `xtb_scc_core`，`scc` 子程序，`:255-641`）**——真正的 SCC 迭代循环 `scc_iterator`（`:371`）：
   - 每轮：`ies%addShift` + `setvsdq` + `solvation%addShift` + `scD4%addShift`（`:376-393`）；
   - 构造电荷依赖的 H1：`buildIsoAnisotropicH1`（`:439`）/`buildIsotropicH1`（`:441`）；
   - **对角化**：`call solver%fact_solve(env, H, S_factorized, emo)`（`:473`），`solver` 是 mctc-lib 的 `TEigenSolver`（`init` 在 `src/scf_module.F90:614`）；
   - Fermi 展宽（`:483`）、密度矩阵 `dmat`（`:503`）、Mulliken 布居 `mpopsh`（`:506`）、能量 `electro`（`:512`）、AES `aniso_electro`（`:524`）、D4（`:529`）、收敛判据（`:556-565`）；
   - 收敛加速：简单阻尼（`:568-599`）或 **Broyden**（`:601-615`，`call broyden`，`src/broyden.f90`）；
   - 收敛后 `lastdiag` 再做一次完整对角化退出（`:628-632`）。

### 4.2 逐个文件的必要性判定

| 文件 | 模块/符号 | GFN2 单点是否需要 | 依据 |
|---|---|---|---|
| `src/scf_module.F90` | `xtb_scf::scf` | **必须** | `src/xtb/calculator.f90:258` 直接调用 |
| `src/scc_core.f90` | `xtb_scc_core::scc`，`build*`，`occu/dmat/mpopsh/electro/…` | **必须** | `src/scf_module.F90:615` 调用 `scc`；Hamiltonian/初猜也用它 |
| `src/broyden.f90` | `xtb_broyden::broyden` | **必须（默认路径）** | `src/scc_core.f90:31 use xtb_broyden`，`:608 call broyden`；仅 `--nobroy`（`broy=.false.`）时才退回简单阻尼 |
| `src/iniq.f90` | `xtb_iniq::iniqcn`→`iniqcn_gfn2` | **必须** | `src/prog/main.F90:650` |
| `src/lin.f90` | `xtb_lin::lin/lina`（一维压缩下标函数） | **必须** | 被 `hamiltonian.F90:23`、`halogen.f90:23`、`prmat*.f90` 等广泛使用 |
| `src/pseudodiag.f90` | 外部子程序 `pseudodiag` | **不必要（死代码）** | 仅被 `src/scc_core.f90:970`（`subroutine solve` 内）调用；而 `solve` 在 `scc` 里已被 `solver%fact_solve` 取代（`:472-473` 注释掉的 `call solve`）。GFN2 路径不触发 |
| `src/david.f` | `ddavid/sdavid/dvdssvd` 等外部子程序 | **不必要（死代码）** | 全仓库无 `call ddavid/sdavid`（`grep` 未见调用），GFN2 用 mctc-lib 特征求解器 |
| `src/david2.f90` | `xtb_david2::sdavid2/solver_sdavidson` | **单点不必要；优化/弛豫时需要** | 仅被 `src/optimizer.f90:26`、`src/relaxation_engine.f90:28` 引入（`use xtb_david2`），即几何优化路径 |
| `src/set_module.f90` | `xtb_setmod`（`set`、`set_gfn`、`set_exttyp`、`set_opt`、`set_runtyp`、`rdblock`…） | **必须** | 全局 `set` 与命令行/`.xtbrc` 解析核心 |
| `src/setparam.f90` | `xtb_setparam`（`set` 类型、`p_*` 常量） | **必须** | 被几乎所有模块 `use` |

> 关于 `--scc`/`--sp`/`--grad`/`-o`/`--opt`：都在 `src/prog/main.F90` 的 flag `select case` 里（`--scc/sp`=`:1909`，`--grad`=`:1946`，`-o/--opt`=`:1950`），分别 `call set_runtyp('scc'|'grad'|'opt')`。梯度**总是被计算**：`src/xtb/calculator.f90:258` 的 `scf(... restart, .true., ...)` 第 9 个实参（`grd`）恒为 `.true.`，梯度数组始终填充；纯单点与“单点+梯度”在电子结构层面同一条调用。

---

## 5. 运行时数据文件

### 5.1 参数文件搜索与打开（GFN2）

`src/xtb/calculator.f90` 中：

- 在 `newXTBCalculator`（`:101`）里，若未显式给 `fname` 且给了 `method`，则 `method==2` 时构造文件名 `param_gfn2-xtb.txt`（`:127-129`）。
- 上层 `src/prog/main.F90:582-583` 用 `xfind(p_fname_param_gfn2)` 解析实际路径（`p_fname_param_gfn2` 定义于 `src/prog/main.F90:148`）。
- 打开与读取（关键引用）：
  - `src/xtb/calculator.f90:149 call open_file(ich, filename, 'r')`
  - `src/xtb/calculator.f90:152 call readParam(env, ich, globpar, calc%xtbData, .true.)`（读取在 `src/read_gfn_param.f90:29 readParam`）
  - `src/xtb/calculator.f90:154-160`：**若文件打不开（`ich==-1`），回退到编译内置参数**：
    ```fortran
    else ! no parameter file, check if we have one compiled into the code
       call use_parameterset(filename, globpar, calc%xtbData, exist)
    ```

### 5.2 内置参数（可完全无文件运行）

`src/gfn_paramset.f90:64-83 use_parameterset`：

```fortran
case('param_gfn2-xtb.txt')
   globpar = gfn2Globals
   call initGFN2(xtbData)
```
其中 `gfn2Globals`（`src/xtb/gfn2.f90:52`）与 `initGFN2`（`src/xtb/gfn2.f90:731`）把整张 GFN2 参数表（含 `selfEnergy`、`slaterExponent`、`chemicalHardness`、`thirdOrderAtom`、D4 参考电荷等）编译进二进制。
**因此 GFN2 单点不需要磁盘上的任何数据文件**；`param_gfn2-xtb.txt` 只是“可选的优先来源”。

### 5.3 路径解析与环境变量

- `env%xtbpath` / `env%xtbhome` 来自环境变量：`src/type/environment.f90:140-148`（`rdvar('XTBHOME',...)`、`rdvar('XTBPATH',...)`，缺省 `XTBPATH=XTBHOME`）。
- `xfind`（`src/readin.f90:54-69`）用 `rdpath(xenv%path, name, ...)` 在 `PATH` 里找；找不到就返回原名（交给 `open_file` 在 cwd 试开）。
- `rdpath` 本身来自 mctc-lib（`use xtb_mctc_systools, only: rdpath`，`src/readin.f90:56`；`src/xtb/calculator.f90:44,120-129`）。
- 安装时参数文件被放到 `${datadir}/xtb`：`CMakeLists.txt:274-282` 安装 `param_gfn0/gfn1/gfn1-si/gfn2/ipea-xtb.txt` 与 `.param_gfnff.xtb`。

### 5.4 `symmetry/`

`symmetry/` 是**源码目录**（`symmetry/CMakeLists.txt:21-24` 把 `symmetry.f90` 与 `symmetry_i.c` 编入 `srcs`），提供点群识别（`get_schoenflies`，`symmetry/symmetry.f90:17`，C 端 `schoenflies`）。它**不被 GFN2 单点路径调用**，只被 `src/thermo.f90:59`（热化学）使用；`paramar(11)` 是内存数组，不读盘。**没有任何运行时“symmetry/ 数据文件”**。

### 5.5 其它可选运行时文件

- `xtbrestart`（重启动）：`src/prog/main.F90:692/708` 读、`:742/1268` 写。
- `.xtbrc`（`src/prog/main.F90:146` 定义名）、`.xtb`/`--input` 控制文件：可选。
- 控制文件与几何文件由 `readMolecule`（`src/prog/main.F90:46 use xtb_io_reader`）解析。

---

## 6. 最小 in-tree 源文件清单（按目录分组）

> 说明：GFN2 的计算链在 `src/xtb/`、`src/scf_module.F90`、`src/scc_core.f90` 一带。但**可执行文件是单体**，`primary.f90`/`main.F90`/各 `type`/各 calculator 会 `use` 到几乎所有模块，故下列“单点最小集”是**编译+链接**意义上的最小集；真正仅“运行时被调用”的集合更小（在 §7 标注）。

### (a) GFN2 单点（SP）

`src/prog/`
- `primary.f90`（`program xtb_prog_primary`）
- `main.F90`（`xtb_prog_main::xtbMain`）
- `argparser.f90`（`TArgParser`）
- `submodules.f90`（`getSubmodule`）
（`info/dock/irmod/thermo/topology.f90` 是其它 program 分支，可运行上不需要，但同属该 program 目标，见 §7）

`src/main/`
- `setup.f90`（`newCalculator`）
- `defaults.f90`（`initDefaults`）
- `property.F90`（`xtb_propertyoutput::main_property/write_energy`）
- `geometry.f90`（`main_geometry`，仅 `--opt/--hess` 打印用；SP 非必须）
- `json.F90`（`main_xtb_json`，仅 `--json`）

`src/xtb/`
- `calculator.f90`（`xtb_xtb_calculator::TxTBCalculator::singlepoint`）
- `data.f90`（`xtb_xtb_data::TxTBData` 及子类型）
- `gfn2.f90`（GFN2 参数/`initGFN2`）
- `gfn1.f90`、`gfn0.f90`（被 `gfn_paramset.f90:21-23` `use`，链接需要）
- `hamiltonian.F90`（H0/自能）
- `coulomb.f90`（`TxTBCoulomb`）
- `dispersion.f90`（`TxTBDispersion`）
- `repulsion.F90`（`repulsionEnGrad`）
- `thirdorder.f90`（`TThirdOrder`）
- `multipole.f90`（`TxTBMultipole`）
- `basisset.f90`（`newBasisset`）
- `halogen.f90`（`xbpot`，GFN2 不触发但被 `scf_module` `use`）

`src/`（根）
- `scf_module.F90`、`scc_core.f90`、`iniq.f90`、`lin.f90`、`broyden.f90`
- `set_module.f90`、`setparam.f90`、`readin.f90`、`read_gfn_param.f90`、`gfn_paramset.f90`
- `aespot.F90`（AES 计算）、`grad_core.f90`（`dshellPoly`）、`intgrad.f90`（重叠积分）、`slater.f90`（Slater 基）
- `dipole.f90`（`calc_dipole`）、`hlex.f90`、`local.f90`、`embedding.f90`、`charge_model.f90`
- `fixparam.f90`、`scanparam.f90`、`sphereparam.f90`、`splitparam.f90`、`metadynamic.f90`、`constrain_pot.f90`、`constrain_param.f90`（`calculator.f90` 的 `singlepoint` 收尾/约束调用）

`src/coulomb/`
- `klopmanohno.F90`（实际 Coulomb 矩阵）

`src/disp/`
- `dftd4.F90`、`dftd4_parameters.f90`（GFN2 色散）
- `ncoord.f90`（`ncoord_gfn/ncoord_erf/ncoord_d4`）、`coordinationnumber.F90`（`getCoordinationNumber`）

`src/type/`
- `molecule.f90`、`calculator.f90`、`restart.f90`、`wavefunction.f90`、`basisset.f90`、`environment.f90`、`param.f90`、`data.F90`、`setvar.f90`、`timer.f90`、`coulomb.f90`、`dispersion_model.f90`、`latticepoint.f90`、`neighbourlist.f90`、`solvation.f90`、`pcem.f90`、`iohandler.f90`、`reader.F90` 等（被上述模块 `use`）

`src/param/`
- `atomicrad.f90`、`paulingen.f90`（`gfn2.f90:21-22`）、`covalentrad*.f90`、`vdwrad*.f90` 等（元素常量）

`src/mctc/`
- `accuracy.f90`、`blas.f90`、`lapack.f90`、`convert.f90`、`systools.F90`、`io.f90`、`timings.f90`、`param.f90`、`strings`、`filetypes.f90`、`mctc_init`/`mctc_global` 等（几乎全量）

`src/solv/`（气体相非必须，但被 `scf_module`/`calculator` `use`：`model.f90`、`gbsa.f90`、`cm5.f90`、`cosmo.f90`）

### (b) GFN2 单点 + 梯度

在 (a) 基础上，**计算链本身没有额外文件**：`scf` 已在同一次调用里算梯度（`src/xtb/calculator.f90:258` 的 `grd=.true.`）。
额外需要的只是**输出路径**：
- `src/main/property.F90` 的 `main_property`（`:104`）——写 `.grad`/能量摘要。
- 梯度写盘由 `src/prog/main.F90:1331` 附近逻辑使用 `writeMolecule`（`xtb_io_writer`）。
（若走 `--grad`，`set%runtyp=p_run_grad` 只影响 print/lgrad，不改变电子结构调用。）

### (c) GFN2 几何优化

在 (a)+(b) 基础上：
- `src/geoopt_driver.f90`（`xtb_geoopt::geometry_optimization`，`:23`；调用点 `src/prog/main.F90:882`）
- `src/optimizer.f90`（ANC 优化器；`use xtb_david2`，`:26`）
- `src/relaxation_engine.f90`（弛豫/FIRE；`use xtb_david2`，`:28`）
- `src/single.f90`（`singlepoint` 包装，`geometry_optimization` 每步调用）
- `src/david2.f90`（`sdavid2/solver_sdavidson`，被上面的 optimizer/relaxation 引入）
- `src/lbfgs_anc/`（内部 LBFGS，被 optimizer 使用）
- 打印：`src/main/geometry.f90`（`main_geometry`，`src/prog/main.F90:1097` 调用）

---

## 7. 全局状态“拉入”的符号（不属 GFN2 路径但静态必需链接）

由于 `primary.f90`→`main.F90`→`setup.f90`/`type/*` 用无 `only` 的 `use` 并且 `select type`/`case` 覆盖所有计算器，以下模块**即使 GFN2 路径从不调用**，也会被编译并链接进可执行文件（`grep` 证据）：

| 模块/文件 | 谁拉入 | 说明 |
|---|---|---|
| `src/xtb/gfn0.f90`、`src/xtb/gfn1.f90` | `src/gfn_paramset.f90:21-23`（`use xtb_xtb_gfn0/gfn1/gfn2`） | `use_parameterset` 同时识别三种方法，符号必须存在 |
| `src/gfn0param.f90` | `src/xtb/gfn0.f90` 等 | GFN0 常量 |
| `src/peeq_module.f90`（`xtb_peeq`） | `src/xtb/calculator.f90:42` | GFN0 才走 `case(0)`，但符号必须存在 |
| `src/xtb/eeq.f90`、`src/disp/encharges.f90` | `src/peeq_module.f90:28,31` | PEEQ/GFN0 用，GFN2 不进 |
| `src/pseudodiag.f90` | `src/scc_core.f90` 的 `solve`（死支） | 外部符号，编译进对象 |
| `src/david.f` | 全局源码列表 `src/CMakeLists.txt` | 无调用者 |
| `src/david2.f90` | `src/optimizer.f90:26`、`src/relaxation_engine.f90:28` | 优化/弛豫用 |
| `src/disp/dftd3.f90`（及 `dftd3.f`、`dftd3_parameters.f90`） | `src/scf_module.F90:26`（`use xtb_disp_dftd3, only: d3_gradient`） | GFN1 分支用，GFN2 走 `else` |
| `src/gfnff/**`（大量） | `src/main/setup.f90:37 use xtb_gfnff_calculator`、`src/main.F90:66` | GFN-FF 计算器 |
| `src/iff/**`（`iff_prepare`、`iff_data`…） | `src/main/setup.f90:39`、`src/prog/main.F90:86-87` | IFF 计算器 |
| `src/ptb/**`（`ptb_calculator` 等） | `src/main/setup.f90:34`、`src/prog/main.F90:90` | PTB / 依赖外部 `multicharge`/`dftd4` |
| `src/tblite/**` | `src/main/setup.f90:30`、`src/prog/main.F90:85` | TBLite 计算器 |
| `src/extern/**`（orca/mopac/turbomole/driver） | `src/main/setup.f90:25-28`、`src/prog/main.F90` | 外部程序接口 |
| `src/oniom.f90` | `src/main/setup.f90:38`、`src/prog/main.F90:88` | ONIOM |
| `src/dipro/**`（`dipro.F90`、`dipro/*`） | `src/prog/main.F90:89`（`use xtb_dipro`） | DIPRO 耦合积分 |
| `src/solv/cpx.F90` | `src/prog/main.F90:91`（`use xtb_solv_cpx`） | CPCM-X，需外部 `mctc_env` |
| `src/docking/**` | `src/prog/dock.f90`（program 分支） | 对接 |
| `src/thermo.f90` + `symmetry/**` | `src/prog/irmod.f90`/`thermo.f90`、`src/thermo.f90:59` | 热化学 + 点群 C 库 |
| `src/hessian.F90` | `src/type/calculator.f90`（`TCalculator::hessian` → `numhess`） | `--hess/--ohess` 用 |

> 换句话说：`xtb` 的可执行目标不存在“按方法裁剪”的链接边界——`src/CMakeLists.txt` 把根目录所有 `*.f90/*.F90/*.f/*.F` 连同全部子目录一起编进对象库，`prog` 目标把 `program`/各 calculator 全部链接。GFN2 只是运行时被选中的一条 `case`。

---

## 8. 关键风险 / 待确认点

1. **任务前提需修正**：入口是 `src/prog/primary.f90`，不是 `main.F90`；`src/main/run.f90` 是空死文件且不在 CMake 中；「method enum」在 `defaults.f90` 里不存在，GFN 方法仅是整数 `set%gfn_method`。
2. **`gfn2.f90` 的语义**：它是“内置参数数据模块”，不是运行时 Hamiltonain 装配器；装配在 `scf_module.F90`。
3. **参数双来源**：磁盘 `param_gfn2-xtb.txt` 优先、内置 `initGFN2` 兜底，二者都需与方法号 `level==2` 自洽（`src/xtb/calculator.f90:164`）。
4. **死代码**：`pseudodiag.f90`、`david.f` 在 GFN2 路径不可达；`david2.f90` 只服务优化/弛豫。不要把它们当作 SCF 必需。
5. **`src/xtb/eeq.f90` 与 `src/xtb/halogen.f90` 不在 GFN2 路径**（前者仅 PEEQ/GFN0，`src/scf_module.F90:372` 注释明确 halogen 不属于 GFN2）。任务把它俩列为 GFN2 贡献项需要纠正。
6. **外部库边界**：GFN2 用 in-tree dftd4 (`src/disp/dftd4.F90`)，外部 `dftd4`/`s-dftd3`/`multicharge` 包仅被 PTB/CPCM-X 使用；底层仅依赖外部 **mctc-lib**。
