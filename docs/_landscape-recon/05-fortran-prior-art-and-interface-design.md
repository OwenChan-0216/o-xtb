# 05 — Fortran 同类实现调研与新套件接口设计

> 目标：判断能否在 xtb (grimme-lab/xtb 6.7.1) 内用 Fortran 实现
> `sp / opt / scan / ts / hessian / freq / irc` 这一整套 PES 任务，
> 以 GFN2-xTB 作为主能量/梯度引擎，并在设计上对照 MAPLE 的 Python dispatcher。
>
> 本报告全部为**只读调研**。所有外部仓库（`/home/owenchan/work_path/coding/fortran/xtb`
> 与 `/home/owenchan/work_path/coding/python/MAPLE`）均未做任何修改。
> 引用格式为 `path:line`。所有内部模块名、算法名保留英文，叙述用中文。

---

## 摘要（结论先行）

1. **离线环境没有 DL-FIND / geomeTRIC / pysisyphus / sella 的任何源码副本**。
   文件系统搜索仅命中无关文件（`dl_find_object.h`、boost 的 hypergeometric、gstreamer
   的 geometrictransform 等）。DL-FIND 只能通过 web（STFC GitLab 公有镜像）研究。
2. **xtb 内部已经存在一套相当完整的可复用构件**：L-BFGS / ANC / FIRE / BFGS/Powell 更新、
   P-RFO 风格的 displace（`ancopt`/`relax`）、数值 Hessian（`numhess`/`o1numhess`）、
   Hessian 投影/去平动平转（`projectHessian`/`trproj`/`detrotra`）、内坐标（`internals/*` +
   `bmatrix`）、约束/扫描（`constrain_*`/`scanparam`/`scan_driver`）、路径 `cqpath`/`bias_path`、
   TS 的模态跟随 `modefollow`。这些是 **M1–M3 的主要复用对象**。
3. xtb 已经有一个**抽象计算器接口** `class(TCalculator)`（`src/type/calculator.f90:43`），
   含 deferred `singlepoint` 与可复用 `hessian`。新套件应直接以它为引擎边界，天然支持
   GFN0/1/2、GFN-FF、tblite、extern 等任意 `class(TCalculator)`。
4. 建议新增顶层目录 `src/landscape/`，模块统一前缀 `xtb_landscape_*`，并通过
   `set_runtyp`（`src/set_module.f90:1032`）与 `prog/main.F90` 的 dispatch
   （`src/prog/main.F90:1095` 起）接入新 runtyp（`scan/ts/irc/neb/string` 等）。
5. 给出 6 个 settings 类型（sp/opt/scan/ts/irc/vib）、result 类型、日志/轨迹文件格式，
   以及 M0–M7 的分阶段里程碑与验收测试。

---

# Part 1 — 同类实现调研（prior art）

## 1.1 DL-FIND

### 1.1.1 本机是否存在副本？

执行（在 `/usr /opt /home /root /srv /usr/local` 范围内，带超时）：

```
find / -iname '*dl_find*' -o -iname '*dlfind*'
```

命中的全部为无关内容：

- `/usr/include/x86_64-linux-gnu/bits/dl_find_object.h`（glibc 头文件）
- `/usr/lib/x86_64-linux-gnu/gstreamer-1.0/libgstgeometrictransform.so`
- boost / scipy / sympy / mpmath / pythran 的 `hypergeometric*` 等

**结论：本机没有 DL-FIND 源码，也没有 geomeTRIC / pysisyphus / sella 的本地副本。**

### 1.1.2 Web 调研（DL-FIND）

- 官方页：`https://chemshell.org/dl-find`（HTTP 200）。要点：
  - DL-FIND 是 **open-source geometry optimisation library**，作者 Jo Carr,
    Johannes Kästner, Tom Keal, Judith Rommel（Kästner 2006 起），当前由 STFC 的
    Tom Keal 维护。
  - **License：GNU LGPL**（网页原文 “released under the open source GNU LGPL licence”，
    仓库内 `COPYING.LESSER` 为 LGPLv3）。与 xtb 的 LGPL 兼容。
  - 支持坐标：Cartesian（含 frozen atoms/components）、Delocalised Internal
    Coordinates (DLC)、Hybrid DLC (HDLC)、DLC-TC/HDLC-TC；I/O 用 Cartesian。
  - 支持的算法：
    - 局部极小：Steepest descent、Conjugate gradient、Newton-Raphson/quasi-Newton
      (BFGS)、L-BFGS、damped dynamics
    - 鞍点：P-RFO（Powell 或 Bofill 更新）、Dimer
    - 反应路径：NEB
    - 圆锥交叉：penalty function、gradient projection、Lagrange-Newton
    - 全局：genetic algorithm、stochastic search
  - 并行：NEB、GA、随机搜索、有限差分 Hessian 采用 task-farming。
  - 完全可 restart。
  - 引用：Kästner, Carr, Keal, Thiel, Wander, Sherwood, *J. Phys. Chem. A* **2009**,
    113, 11856。
  - 源码托管于 STFC GitLab；**在 gitlab.com 上有公有镜像**（见下）。

### 1.1.3 DL-FIND 模块结构（从公有镜像获取）

通过 GitLab API 拉取仓库目录（project id 74496069，`chemshell/dl-find`，
`repository/tree?recursive=true`），得到顶层文件清单（节选）：

```
dl-find.f90              dlf_allocate.f90     dlf_checkpoint.f90
dlf_conint.f90           dlf_convergence.f90  dlf_coords.f90
dlf_dimer.f90            dlf_formstep.f90     dlf_global_module.f90
dlf_hdlc_constraint.f90  dlf_hdlc_hdlclib.f90 dlf_hdlc_interface.f90
dlf_hdlc_matrixlib.f90   dlf_hdlc_primitive.f90
dlf_lbfgs.f90            dlf_linalg.f90       dlf_microiter.f90
dlf_mpi.f90              dlf_neb.f90          dlf_parallel_opt.f90
dlf_qts.f90              dlf_scalestep.f90    dlf_serial.f90
dlf_sort.f90             dlf_stat_module.f90  dlf_task.f90
dlf_time.f90             dlf_util.f90         main.f90
dependencies.txt         Makefile.standalone  COPYING / COPYING.LESSER
```

关键子程序签名（`dl-find.f90`、`dlf_coords.f90`、`dlf_formstep.f90`）：

```
! dl-find.f90:69   —— 库的总入口，由宿主程序调用
subroutine dl_find(nvarin,nvarin2,nspec,master [,core])
   integer,intent(in) :: nvarin   ! 3*nat
   integer,intent(in) :: nvarin2  ! coords2 的变量数
   integer,intent(in) :: nspec    ! spec 整型数组长度
   integer,intent(in) :: master   ! MPI master 标志
end subroutine

! dl-find.f90:329  —— 主优化循环 + checkpoint
subroutine dlf_run(...)

! dlf_coords.f90  —— 坐标系统一层
subroutine dlf_coords_init
subroutine dlf_coords_xtoi(trerun_energy,testconv,iimage)   ! Cartesian -> Internal
subroutine dlf_coords_itox(iimage)                          ! Internal -> Cartesian
subroutine dlf_direct_xtoi(nvar,nivar,nicore,xcoords,xgradient,icoords,...)
subroutine dlf_cartesian_xtoi(nat,nivar,nicore,massweight,xcoords,xgradient,...)
subroutine dlf_coords_tranrot(nvar,vector)                   ! 去平动/平转
subroutine dlf_cartesian_align(nat,coords1,coords2)          ! Kabsch 对齐

! dlf_formstep.f90 —— 步长生成（含 Hessian 更新与 P-RFO）
subroutine dlf_formstep
subroutine dlf_formstep_init(needhessian_)
subroutine dlf_makehessian(trerun_energy,tconv)
subroutine dlf_fdhessian(nvar_,fracrecalc,energy,coords,gradient,hess,havehessian)
subroutine dlf_hessian_update(nvar,coords,oldcoords,gradient,...)   ! Powell / Bofill 更新
subroutine dlf_prfo_step(nvar,coords,gradient,hessian,step)          ! P-RFO 步
subroutine dlf_thermal()                                             ! 热化学分析

! dlf_convergence.f90 — 收敛判据
subroutine convergence_test(icycle,tene,tconv)
subroutine convergence_set_info(msg,nvar,energy,gradient,step)

! dlf_neb.f90 / dlf_dimer.f90 / dlf_microiter.f90 / dlf_lbfgs.f90
!   —— NEB、Dimer、micro-iteration（IRC/线搜索微步）、L-BFGS
```

**与宿主程序的接口方式**：DL-FIND 不直接调用具体 QM 代码，而是由宿主把
energy/gradient 写入全局数组，DL-FIND 通过 `glob%dotask` 之类的标志驱动一次
“算一次能量+梯度”的往返（`dlf_coords_xtoi` 中触发 `testconv`/energy 计算）。
这是一种“控制反转”的回调式接口；它对新套件的启示是：**引擎应当是一个可
被反复调用的纯函数边界，而非被动数据结构**。

**对本项目的可用性**：DL-FIND 是 LGPL，理论上可整体嵌入 xtb。但它的架构是面向
外部 QM 程序的“库+回调”，与 xtb 的 `class(TCalculator)`/`singlepoint` 风格差异大，
整体搬运引入的耦合（HDLC、MPI task-farm、checkpoint 格式）远超收益。
**建议：仅借鉴其坐标/收敛/P-RFO/热化学设计，不搬运其代码。**

## 1.2 其它 Fortran 化学/PES 优化器

文件系统搜索（`find / ... -iname '*geometric*' -o -iname '*pysisyphus*' -o -iname '*sella*'`）
**未命中任何相关源码**，仅命中 scipy/networkx/boost 的数学文件与 gstreamer 插件。

- **geomeTRIC**：Python，无 Fortran；本机无副本。
- **pysisyphus**：Python，无 Fortran；本机无副本。
- **sella**：Python，无 Fortran；本机无副本。
- 其它已知 Fortran PES 优化器（如 GAMESS 内建、ORCA 内建、pDynamo/CHARMM、ASE 的
  Fortran 后端）在本机**也没有离线副本**。

## 1.3 离线 vs 仅 Web 可用性汇总

| 资源 | 本机离线？ | 仅 Web？ | 备注 |
|---|---|---|---|
| DL-FIND 源码 | 否 | 是（STFC GitLab / gitlab.com 镜像 `chemshell/dl-find`） | LGPL，模块结构已在上文列出 |
| DL-FIND 论文/手册 | 否 | 是（J. Phys. Chem. A 2009, 113, 11856；chemshell.org） | 可引用 |
| geomeTRIC | 否 | 是（GitHub） | Python |
| pysisyphus | 否 | 是（GitHub） | Python |
| sella | 否 | 是（GitHub） | Python，Python 优化器 |
| **xtb 内部构件** | **是** | — | 见 Part 2，主要复用来源 |
| **MAPLE dispatcher** | **是** | — | `/home/owenchan/work_path/coding/python/MAPLE` |

**总体判断**：实现新套件所需的一切核心算法（优化/鞍点/路径/Hessian/IRC/约束扫描）
在 xtb 内部都有可复用基础或可参照的成熟范例（DL-FIND）。无需引入外部 Fortran 库。

---

# Part 2 — xtb 内部复用候选（含精确签名与分类）

分类约定：
- **(a) 可直接调用**：签名稳定、无副作用耦合，可直接 `use` 后调用。
- **(b) 需要重构**：算法可用，但接口/状态耦合过强，需薄封装或小幅改造。
- **(c) 应重写**：实现与旧设计绑死，或与目标接口不匹配，另行实现更省事。

## 2.1 优化器核心

### `src/bfgs.f90` — BFGS/Powell Hessian 更新
```
src/bfgs.f90:20   subroutine bfgs(nat3,gnorm,grad,grado,dx,hess)
   integer,intent(in)      :: nat3
   real(wp),intent(in)     :: grad(nat3), grado(nat3), dx(nat3), gnorm
   real(wp),intent(inout)  :: hess(nat3*(nat3+1)/2)   ! packed lower triangle
src/bfgs.f90:105  subroutine powell(nat3,gnorm,grad,grado,dx,hess)  ! 同上
src/bfgs.f90:164  subroutine hdamp(gnorm,dampO,dampD)
```
- 纯数值、无环境依赖（只 `use xtb_mctc_accuracy/blas`），packed 存储。
- **判定：(a) 直接可调用。**

### `src/relaxation_engine.f90` — FIRE / L-ANC / LBFGS / 惯性松弛（1576 行）
```
src/relaxation_engine.f90:131 subroutine fire(env,ilog,mol,chk,calc,
                         optlevel,maxstep,energy,egap,gradient,sigma,printlevel,fail,iter_needed)
src/relaxation_engine.f90:400 subroutine l_ancopt(env,ilog,mol,chk,calc,
                         optlevel,maxcycle_in,energy,egap,gradient,sigma,printlevel,fail,iter_needed)
src/relaxation_engine.f90:802 subroutine lbfgs_step(iter,memory,nvar,gradient,glast,displacement,
                         hdiag,s,y,rho)   ! 纯数值 L-BFGS 两步递推
src/relaxation_engine.f90:874 subroutine lbfgs_relax(env,iter,maxcycle,opt,mol,chk,calc,
                         energy,egap,g_xyz,sigma,nvar,hdiag,trafo,xyz0,converged,fail,timer,avconv)
src/relaxation_engine.f90:1148 subroutine inertial_relax(env,iter,maxstep,opt,mol,chk,calc,
                         energy,egap,gradient,sigma,hessp,velocities,lat_velocities,
                         optcell,converged,fail,timer)
src/relaxation_engine.f90:1484 function predict_energy_change(nat3,grad,displ,hess) result(depred)
src/relaxation_engine.f90:1516 subroutine get_preconditioner_metric(nvar,hess,grad,pinvg,fail)
```
- `lbfgs_step` / `get_preconditioner_metric` / `predict_energy_change` 是纯数值，可单独复用。
- `fire` / `l_ancopt` / `inertial_relax` / `lbfgs_relax` 与 `TMolecule`、`TRestart`、
  `TCalculator`、`set%`、`xtb_axis`、`xtb_lsrmsd` 强耦合（`env/mol/chk/calc` 四处传参），
  且内部含打印、PBC、frozen-atom、RMSD 逻辑。
- **判定：`lbfgs_step`/`predict_energy_change`/`get_preconditioner_metric` = (a)；
  `fire`/`l_ancopt`/`inertial_relax`/`lbfgs_relax` = (b)（封装为 optimizer 后端，不改内核）。**

### `src/optimizer.f90` — ANC 优化器 + P-RFO 风格步长（1559 行）
```
src/optimizer.f90:48   subroutine get_optthr(n,olev,ethr,gthr,maxcycle,acc)
src/optimizer.f90:122  subroutine ancopt(env,ilog,mol,chk,calc, ...)
src/optimizer.f90:622  subroutine relax(env,iter,mol,anc,restart,maxcycle,maxdispl,ethr,gthr,...)
src/optimizer.f90:1107 subroutine prdechng(nat3,grad,displ,hess,depred)
src/optimizer.f90:1155 subroutine trfp2xyz(nvar,nat3,p,xyz0,h,dspl)
src/optimizer.f90:1187 subroutine prdispl(nvar,displ)
src/optimizer.f90:1227 subroutine modhes(env, calc, modh, natoms, xyz, chg, Hess, pr)
src/optimizer.f90:1325 subroutine itochess(nvar,nat3,b,hess,fc)   ! internal->Cartesian Hessian
src/optimizer.f90:1369 subroutine read_hessian(ihess, ndim, hessian, error)
```
- `ancopt`/`relax` 内含**位移限制（trust-region 前身）与 Hessian 投影到冗余内坐标**，
  是 P-RFO 步长的近似实现。`itochess`（B 矩阵变换 Hessian）非常有用。
- `modhes` 支持从模型 Hessian 生成初始 Hessian（对 TS/IRC 冷启动关键）。
- **判定：`ancopt`/`relax` = (b)（作为优化后端复用）；`itochess`/`prdechng`/`trfp2xyz`/
  `modhes` = (a) 或 (b)。**

### `src/david2.f90` — Davidson 对角化
```
src/david2.f90:25  subroutine sdavid2(n,crite,H,C,e,fail)        ! single precision
                     integer n; real(sp) H(n,n), C(n,nr), e(nr)
src/david2.f90:221 subroutine solver_sdavidson(n,crite,Hp,C,e,fail,pr)  ! packed
                     real(sp) Hp(n*(n+1)/2)
```
- 用于大体系最低若干本征值（P-RFO 需要最低本征对）。注意 `wp => sp`（单精度）。
- **判定：(a)（可直接调用；若需双精度以更稳健可 (b) 加一个 dp wrapper）。**

### `src/geoopt_driver.f90` — 优化调度入口
```
src/geoopt_driver.f90:23 subroutine geometry_optimization(env,mol,wfn,calc,
                         egap,et,maxiter,maxcycle_in,etot,g,sigma,tight,pr,initial_sp,fail,iter_needed)
```
- 按 `set%opt_engine` 分派 `p_engine_rf/lbfgs/pbc_lbfgs/inertial`。是**新 opt/扫描/TS
  内部松弛**应复用的统一入口。
- **判定：(a) 直接复用（这是新套件做“受约束松弛”时的标准调用）。**

## 2.2 Hessian

### `src/hessian.F90` — 数值 Hessian 与振动分析
```
src/hessian.F90:33  subroutine numhess(env,mol,chk0,calc,egap,et,maxiter,etot,gr,sr,res)
src/hessian.F90:581 subroutine numhess_rmsd(...)
src/hessian.F90:666 subroutine distort(mol,freq,u)
src/hessian.F90:727 subroutine rescale_freq(n3,htb,hess,hbias,freq,fc_tb,fc_bias,freq_scal)
```
- `numhess` 是**完整的频率+Hessian+热化学**实现（含 `freq_results`），与 PTB、metadyn 耦合。
- **判定：`numhess` = (b)（作为 freq 后端复用；其内部包含 PTB/metadyn 分支需解耦）；
  `distort`/`rescale_freq` = (a)。**

### `src/freq/project.f90` — Hessian 投影（去平动平转）
```
src/freq/project.f90:34  subroutine projectHessian(hessian, mol, removeTrans, removeRot)
                            real(wp),intent(inout) :: hessian(:,:); type(TMolecule),intent(in)
                            logical,intent(in) :: removeTrans, removeRot
src/freq/project.f90:151 subroutine trproj(natoms,nat3,xyz,hess,ldebug,nmode,mode,ndim)
src/freq/project.f90:218 subroutine gtrprojm(natoms,nat3,xyzucm,hess,ldebug,nmode,mode,ndim)
```
- `projectHessian` 直接面向 `TMolecule`，无全局 set 依赖，**是 TS/IRC/RFO 去刚性自由度
  的关键构件**，可直接用。
- **判定：(a) 直接可调用。**

### `src/freq/utils.f90` — 质量加权与对角化
```
src/freq/utils.f90:32 subroutine massWeightHessian(hessian, atmass)   ! in-place
src/freq/utils.f90:59 subroutine diagHessian(env, hessian, freq)      ! lapack_syev，得 signed freq
```
- **判定：(a) 直接可调用。**

### `src/freq/io.f90` — Hessian / 简正模式 IO
```
src/freq/io.f90:30  subroutine writeHessianOut(fname, hessian)
src/freq/io.f90:51  subroutine wrhess(nat3, h, fname)
src/freq/io.f90:82  subroutine rdhess(nat3, h, fname)
src/freq/io.f90:190 subroutine write_tm_vibspectrum(...)
src/freq/io.f90:283 subroutine g98fake2(fname, n, at, xyz, freq, red_mass, ir_int, u2)
```
- 注意：任务里提到的 `trproj/rdhess` 已在重构中迁至 `src/freq/`（`project.f90`/`io.f90`）。
- **判定：(a)。**

### `src/o1numhess.f90` — O1 近似数值 Hessian（792 行）
```
src/o1numhess.f90:71  subroutine gen_local_hessian(env, ndispl_final, distmat, displdir, g, dmax, hess_out)
src/o1numhess.f90:263 subroutine lr_loop(env, ndispl, g, hess_out, displdir, final_err)
src/o1numhess.f90:433 subroutine gen_displdir(n, ndispl0, h0, max_nb, nblist, nbcounts, ...)
src/o1numhess.f90:694 subroutine find_projected_imag_modes(env, mol, hess, linear, max_modes,
                         sig_min_rcm, modes, freqs, nmodes)
```
- `find_projected_imag_modes`：在投影、质量加权后挑出虚频模式——**正是 TS/IRC 冷启动
  首步方向所需**。它内部完成 mass-weight + 投影 + 诊断，直接可用。
- `gen_local_hessian`/`lr_loop` 实现 ODLR 近似 Hessian（对 ~10³ 原子级体系重要）。
- **判定：(a)（可直接调用；`gen_local_hessian` 依赖 `odlr_operator_data` 内部类型，
  对外仍可通过 `hessian(...,odlr=.true.)` 调用）。**

### `src/type/calculator.f90` — 抽象计算器上的通用 Hessian
```
src/type/calculator.f90:43  type, abstract :: TCalculator
src/type/calculator.f90:61  subroutine singlepoint(self,env,mol,chk,printlevel,restart,
                            energy,gradient,sigma,hlgap,results)   ! deferred
src/type/calculator.f90:103 subroutine hessian(self, env, mol0, chk0, list, step, hess,
                            dipgrad, polgrad, odlr, final_err)     ! 已实现（非 deferred）
   class(TCalculator),intent(inout) :: self
   type(TEnvironment),intent(inout) :: env
   type(TMolecule),intent(in)       :: mol0
   type(TRestart),intent(in)        :: chk0
   integer,intent(in)               :: list(:)
   real(wp),intent(in)              :: step
   real(wp),intent(inout)           :: hess(:,:)
   real(wp),intent(inout)           :: dipgrad(:,:)
   real(wp),intent(inout),optional  :: polgrad(:,:)
   logical,intent(in),optional      :: odlr
   real(wp),intent(out),optional    :: final_err
```
- **判定：(a)。这是新套件引擎边界的核心，详见 Part 3.2。**

## 2.3 内坐标与 B 矩阵

### `src/internals/` 与 `src/bmatrix.f90`
```
src/internals/type.f90:41      type :: internal_coords_set_type
                                  integer :: ncoords
                                  integer, allocatable :: kind(:)        ! coord_bond/angle/dihedral/linbend
                                  integer, allocatable :: atoms(:,:)      ! (4,ncoords)
                                  real(wp), allocatable :: frame(:,:)     ! linbend 方向
src/internals/redundant.f90:35 public :: redundant_type, init
src/internals/redundant.f90:41 type, extends(internal_coords_set_type) :: redundant_type
                                  integer :: n, nbond, nangle, ndihedral
                                  real(wp), allocatable :: q(:)           ! 参考几何坐标值
src/internals/redundant.f90:73 pure subroutine new_redundant(self, graph, xyz)
                                  type(redundant_type),intent(out) :: self
                                  type(graph_type),intent(in)      :: graph
                                  real(wp),intent(in)              :: xyz(:,:)
src/internals/graph.f90:33     type :: graph_type
src/internals/graph.f90:54     module procedure new_graph

src/bmatrix.f90:321 pure subroutine get_bmatrix(internals, xyz, bmat)
                       class(internal_coords_set_type),intent(in) :: internals
                       real(wp),intent(in)  :: xyz(:,:)
                       real(wp),intent(out) :: bmat(:,:)
src/bmatrix.f90:456 pure subroutine bmat_accum_packed(nat, hess, atoms, brow, scale)
src/bmatrix.f90:508 pure subroutine bmat_accum_dense(hess, atoms, brow, scale)
src/bmatrix.f90:527 pure subroutine bmat_accum_pairblock_packed(nat, hess, i, j, mat)
src/bmatrix.f90:  pure function bmat_bond(vec) / bmat_angle(vec1,vec2) /
                  bmat_torsion / bmat_outofplane / oop_angle / linbend_frame
```
- **这是相对新且干净的纯函数模块**（`pure`），完全可复用来构建 DL/冗余内坐标的
  B 矩阵、Hessian 变换（`itochess` 的现代替代）。
- **判定：(a) 直接可调用，强烈推荐作为新套件内坐标层的地基。**

### `src/intmodes.f90` — 经典 Z-matrix 内坐标（旧）
```
src/intmodes.f90:23  subroutine intmodestep(n,bmat,u,step,geo,na,nb,nc,coord)
src/intmodes.f90:264 subroutine cart2zmat(...)
src/intmodes.f90:388 subroutine zmat2cart(...)
```
- 旧式 Z-matrix，耦合较多。**判定：(c) 用 internals/* 取代，不搬运。**

## 2.4 刚性/平转/平动处理

```
src/detrotra.f90:33  subroutine detrotra_sp(linear, n, xyz, h, eig)  ! interface detrotra
src/detrotra.f90:52  subroutine detrotra_wp(linear, n, xyz, h, eig)
src/detrotra.f90:71  subroutine detrotra_worker(linear, n, xyz, h, eig, rigid)
src/axis_trafo.f90:59  subroutine axis(numat,nat,xyz,aa,bb,cc)
src/axis_trafo.f90:156 subroutine axis2(n,xyz,aa,bb,cc,avmom,sumw)
src/axis_trafo.f90:277 subroutine axisvec(numat,nat,xyz,aa,bb,cc,evec)
src/axis_trafo.f90:377 subroutine axis3(mode,numat,nat,coord,coordout,eig)
src/rmrottr.f90:19    subroutine rmrottr(natoms,mass,vel_atom,c)   ! 去 COM 速度
src/rmrottr.f90:92    subroutine centerofmass(natoms,c,mass,totmass,COM)
```
- `detrotra`（识别并置零平动/转动模式）与 `axis3`（转动惯量轴）是 TS/IRC/RFO 判定
  刚性自由度所必需。
- **判定：`detrotra` = (a)；`axis3` = (a)；`rmrottr` = (a)。**

## 2.5 约束 / 扫描

### `src/scanparam.f90` — 约束与扫描参数
```
src/scanparam.f90:64  subroutine init_constr(n,at)
src/scanparam.f90:85  subroutine init_scan
src/scanparam.f90:90  subroutine clear_scan
src/scanparam.f90:94  subroutine clear_constr
src/scanparam.f90:99  subroutine read_reference(fname,n,at,xyz)
src/scanparam.f90:121 subroutine setup_constrain_pot(n,at,xyz)
src/scanparam.f90:146 subroutine pot_info(iunit,n,at,xyz)
src/scanparam.f90:325 subroutine constrain_all_bonds(n,at,xyz)
src/scanparam.f90:353 subroutine constrain_all_angles(n,at,xyz)
src/scanparam.f90:393 subroutine constrain_all_torsions(n,at,xyz)
```

### `src/constrain_pot.f90` — 约束势/梯度/Hessian
```
src/constrain_pot.f90:20  subroutine constrain_zaxis(fix,n,at,xyz,g,e)
src/constrain_pot.f90:46  subroutine constrain_pos(fix,n,at,xyz,g,e)
src/constrain_pot.f90:88  subroutine qpothess2(fix,n,at,xyz,h)
src/constrain_pot.f90:166 subroutine constrain_dist(fix,n,at,xyz,g,e)
src/constrain_pot.f90:210 subroutine constrain_angle(fix,n,at,xyz,g,e)
src/constrain_pot.f90:267 subroutine constrain_dihedral(fix,n,at,xyz,g,e)
src/constrain_pot.f90:313 subroutine constrain_pot(fix,n,at,xyz,g,e)
src/constrain_pot.f90:331 subroutine constrain_hess(fix,n,at,xyz0,Hess)
```
- 这是**把键长/键角/二面角约束以“势+梯度”方式加入能量与梯度**的实现（`g` 与 `e`
  被就地修改）——正是 relaxed/rigid scan 与 TS 约束所需。
- **判定：(a) 直接调用（新 scan 在每步设置 `valconstr` 后调用 `geometry_optimization`
  再做 `constrpot` 修正，见 `src/scan_driver.f90:60-70`）。**

### `src/scan_driver.f90` — 已存在的 relaxed scan 驱动
```
src/scan_driver.f90:24 subroutine relaxed_scan(env, mol, chk, calc)
```
- 支持 sequential / concerted 扫描模式，但**只支持 sequential/concerted，不支持 2D grid**，
  且逻辑与 `scan_list` 全局态耦合。
- **判定：(b) 参考并重写为支持 1D/2D grid 的新 scan 模块。**

### `src/constrain_param.f90` — xcontrol 解析
```
src/constrain_param.f90:272  subroutine set_fix(env,key,val,nat,at,idMap,xyz)
src/constrain_param.f90:386  subroutine set_constr(...)
src/constrain_param.f90:844  subroutine set_scan(...)
src/constrain_param.f90:949  subroutine set_wall(...)
src/constrain_param.f90:1229 subroutine set_hess(...)
src/constrain_param.f90:1382 subroutine set_path(...)
src/constrain_param.f90:1429 subroutine set_metadyn(...)
src/constrain_param.f90:1578 subroutine set_legacy(...)
```
- 独立的 xcontrol 关键字解析 + handler 机制。新套件可注册新的 set_* handler
  （例如 `set_ts`、`set_irc`）以复用现有 `$constrain/$scan` 生态。
- **判定：(b) 扩展。**

## 2.6 路径 / TS 相关

```
src/cqpath.f90:32  subroutine cqpath_spline_repos(nat,sn,m_repos,m_spline,xyz,e,g)
src/cqpath.f90:128 subroutine cqpath_repos(n,m_repos,x,e,g,x2)
src/cqpath.f90:270 subroutine cqpath_cube_spline(n,x,y,x2,y2)
src/cqpath.f90:427 subroutine cqpath_interpolate_nm(k,von,bis,nat,nstr,file_xyz,pn,xyz)
src/cqpath.f90:512 subroutine cqpath_read_pathfile(fn,nl,nat,nstr,file_xyz,iat,energy)
src/bias_path.f90:30 subroutine bias_path(env, mol, chk, calc, egap, et, maxiter, epot, grd, sigma)
src/bias_path.f90:464 subroutine screenpath(np,npwanted,npnew,n,xyz,e,xyzdum)
src/bias_path.f90:514 subroutine metadyn_tsmode(n,sn,its,xyzpath,xyzact,kpull)
src/bias_path.f90:554 subroutine guess_tsmode(n,sn,its,xyz,pvec1,pvec2)
src/bias_path.f90:595 subroutine alignpath(nat,sn,xyz)
src/modef.f90:34  subroutine modefollow(env, mol, chk, calc, egap, et, maxiter, epot, grd, sigma)
```
- `cqpath`：三次样条路径插值/重参数化（NEB/string 的插值器可直接复用）。
- `bias_path`：基于 metadynamics 自举路径（非标准 NEB），`guess_tsmode`/`alignpath` 的
  切向与 TS 猜测思路可借鉴。
- `modefollow`：沿最低虚频模态推进的 TS 搜索雏形（可作 M4 的起点）。
- **判定：`cqpath` 插值 = (a)/(b)；`bias_path` = (b) 借鉴；`modefollow` = (b)/(c) 重写。**

## 2.7 复用判定总表

| 文件 / 子程序 | 分类 | 用途 |
|---|---|---|
| `bfgs.f90` bfgs/powell/hdamp | (a) | Hessian 更新 |
| `relaxation_engine.f90` lbfgs_step/predict_energy_change/get_preconditioner_metric | (a) | L-BFGS/预条件 |
| `relaxation_engine.f90` fire/l_ancopt/lbfgs_relax/inertial_relax | (b) | 优化后端 |
| `optimizer.f90` ancopt/relax | (b) | ANC/P-RFO 近似 |
| `optimizer.f90` itochess/prdechng/trfp2xyz/modhes/get_optthr | (a)/(b) | Hessian 变换/初始 Hessian |
| `david2.f90` sdavid2/solver_sdavidson | (a) | 最低本征对 |
| `geoopt_driver.f90` geometry_optimization | (a) | 受约束松弛入口 |
| `hessian.F90` numhess/distort/rescale_freq | (b)/(a) | 频率+Hessian |
| `freq/project.f90` projectHessian/trproj | (a) | 投影 |
| `freq/utils.f90` massWeightHessian/diagHessian | (a) | 质量加权/对角化 |
| `freq/io.f90` rdhess/wrhess/… | (a) | Hessian IO |
| `o1numhess.f90` gen_local_hessian/lr_loop/find_projected_imag_modes | (a) | ODLR/虚频模式 |
| `internals/*` + `bmatrix.f90` | (a) | 内坐标/B 矩阵 |
| `detrotra.f90`, `axis_trafo.f90`, `rmrottr.f90` | (a) | 刚性/平转 |
| `constrain_pot.f90` / `scanparam.f90` | (a) | 约束势 |
| `constrain_param.f90` | (b) | xcontrol 扩展 |
| `scan_driver.f90` relaxed_scan | (b) | 重写 1D/2D scan |
| `cqpath.f90` 插值 | (a)/(b) | 路径插值 |
| `bias_path.f90`, `modef.f90` | (b)/(c) | 借鉴/重写 |
| `intmodes.f90` Z-matrix | (c) | 弃用 |

---

# Part 3 — 建议设计（deliverable）

## 3.1 目录与模块布局

```
src/landscape/                 # 公共 API + 任务驱动
  landscape_api.f90            # xtb_landscape：对外的总入口 (run_landscape)
  landscape_driver.f90         # 任务分发：sp/opt/scan/ts/hess/irc
  CMakeLists.txt / meson.build
  types/
    settings.f90               # xtb_landscape_settings：各任务设置类型
    results.f90                # xtb_landscape_results：结果/轨迹类型
    engine.f90                 # xtb_landscape_engine：抽象引擎 + 具体 wrapper
    log.f90                    # xtb_landscape_log：日志/轨迹写入
  coords/
    cartesian.f90              # 笛卡尔/mass-weighted
    internal.f90               # 冗余内坐标（封装 xtb_internals_* + bmatrix）
    transform.f90             # x<->q 变换，B 矩阵，Hessian 变换
  optimize/
    sd.f90  lbfgs.f90  bfgs.f90  diis.f90  rfo.f90
    trust_region.f90
  saddle/
    prfo.f90  bprfo.f90  dimer.f90  eigenfollow.f90
  path/
    idpp.f90  neb.f90  cineb.f90  autoneb.f90  string.f90  gsm.f90
  irc/
    gs.f90  hpc.f90  lqa.f90  eulerpc.f90
  scan/
    scan1d.f90  scan2d.f90  relax_scan.f90
  vib/
    numhess.f90  project.f90  modes.f90  thermo.f90
test/unit/
  landscape_settings.f90  landscape_coords.f90  landscape_optimize.f90
  landscape_scan.f90  landscape_saddle.f90  landscape_path.f90
  landscape_irc.f90  landscape_vib.f90
```

命名约定：所有模块 `xtb_landscape_<area>_<thing>`，公开类型 `T<Name>` 或 `<name>_type`，
公开过程动词开头（`new_`、`init_`、`run_`、`get_`）。

---

## 3.2 抽象引擎接口（engine boundary）

**核心思想**：新套件不直接编程到 GFN2，而是编程到 xtb 现有的
`class(TCalculator)` + `singlepoint` + `hessian`。为了在算法层只需要“E+G”和“Hessian”
两个动作，定义薄 wrapper 类型 `landscape_engine_type`：

```fortran
module xtb_landscape_engine
   use xtb_mctc_accuracy, only : wp
   use xtb_type_environment, only : TEnvironment
   use xtb_type_molecule, only : TMolecule
   use xtb_type_restart, only : TRestart
   use xtb_type_calculator, only : TCalculator
   use xtb_type_data, only : scc_results
   implicit none
   private
   public :: landscape_engine_type, new_engine, engine_energy_gradient, &
             engine_hessian, engine_reset, engine_set_state

   !> Determinism / accuracy knob passed at construction
   type :: landscape_engine_control
      real(wp) :: etemp   = 300.0_wp   ! 电子温度 (K), GFN2 default
      integer  :: maxiter = 250        ! 每点 SCC 最大迭代
      logical  :: restart = .false.    ! 是否用上一点波函数热启动
      logical  :: lgrad   = .true.     ! 是否计算梯度
   end type

   !> An engine tightly bound to one (env, mol, chk, calc) tuple.
   !> Mirrors MAPLE's calculator object: one object per running job.
   type :: landscape_engine_type
      type(TEnvironment)    :: env
      type(TMolecule)       :: mol
      type(TRestart)        :: wfn
      class(TCalculator), allocatable :: calc   ! polymorphic GFN0/1/2/FF/tblite/extern
      type(landscape_engine_control) :: ctrl
      !> running counters for diagnostics / determinism checks
      integer :: n_eval = 0        ! number of E+G calls
      integer :: n_hess = 0        ! number of Hessian calls
      logical :: converged_scf = .true.
   end type

   abstract interface
      !> The single primitive the whole suite depends on:
      !> fill energy and gradient for the *current* mol%xyz.
      subroutine engine_energy_gradient(self, energy, gradient, hlgap, results)
         import :: landscape_engine_type, wp, scc_results
         class(landscape_engine_type), intent(inout) :: self
         real(wp), intent(out) :: energy
         real(wp), intent(out) :: gradient(:,:)   ! (3, nat), hartree/bohr
         real(wp), intent(out) :: hlgap
         type(scc_results), intent(out) :: results
      end subroutine
   end interface

   !> Concrete Hessian call (single point + analytical/numerical Hessian).
   abstract interface
      subroutine engine_hessian(self, hess, step, odlr, final_err)
         import :: landscape_engine_type, wp
         class(landscape_engine_type), intent(inout) :: self
         real(wp), intent(out) :: hess(:,:)     ! (3n,3n) hartree/bohr^2
         real(wp), intent(in), optional :: step ! finite-diff step, bohr
         logical, intent(in), optional :: odlr  ! O1NumHess approximation
         real(wp), intent(out), optional :: final_err
      end subroutine
   end interface
contains
   !> Bind to any class(TCalculator); GFN2 is just one instantiation.
   subroutine new_engine(self, env, mol, wfn, calc, ctrl)
      type(landscape_engine_type), intent(out) :: self
      type(TEnvironment),  intent(in)  :: env
      type(TMolecule),     intent(in)  :: mol
      type(TRestart),      intent(in)  :: wfn
      class(TCalculator),  intent(in)  :: calc
      type(landscape_engine_control), intent(in), optional :: ctrl
   end subroutine

   !> Implementation simply delegates to xtb_single::singlepoint
   subroutine engine_energy_gradient(self, energy, gradient, hlgap, results)
      use xtb_single, only : singlepoint
      ! ... calls singlepoint(self%env,self%mol,self%wfn,self%calc, ...)
   end subroutine

   !> Delegates to TCalculator::hessian(self%calc, ...)
   subroutine engine_hessian(self, hess, step, odlr, final_err)
      ! ... calls self%calc%hessian(self%env,self%mol,self%wfn, [1..nat], step, hess, ...)
   end subroutine

   subroutine engine_reset(self)             ! clear stale state
   subroutine engine_set_state(self, wfn)    ! restart/state passing (IRC/NEB)
end module
```

**关键契约（写进模块 doc-comment 与单元测试）：**

1. **单一调用语义**：`engine_energy_gradient` 必须无副作用地（除波函数热启动缓存外）
   返回当前 `self%mol%xyz` 的 E 与 G；调用者负责在所有修改坐标之后调用它。
2. **单位**：内部一律 **bohr / hartree / atomic units**；`gradient` 为 **hartree/bohr**，
   `hess` 为 **hartree/bohr²**。**单位转换只在 I/O 边界**（见 3.5）。
3. **Hessian**：`engine_hessian` 走 `TCalculator%hessian`（默认数值差分），
   可选 `odlr=.true.` 使用 O1NumHess。返回 `(3n,3n)` 稠密对称阵。
4. **restart/state passing**：为 NEB 多像、IRC 多步、扫描连续点保留波函数热启动，
   通过 `engine_set_state`/`engine_reset` 显式管理；算法层不得直接触碰 `wfn`。
5. **确定性**：给定相同 `(mol%xyz, chg, uhf, etemp)`，`engine_energy_gradient` 必须
   逐位可复现。要求：GFN2 SCC 收敛判据固定、无随机初始化。测试时对 `n_eval`
   与能量列表做逐位比对（见 M0 验收）。

> 因为 `TCalculator` 是抽象类型，任何未来计算器（Python/tblite/extern）只要实现
> `singlepoint` 就自动获得整套 `opt/scan/ts/hess/irc`——这正是 MAPLE 用
> `calculator_base` 达到的效果，而 xtb 已经原生具备。

---

## 3.3 各任务 settings 类型与默认值

约定：**内部量子化学单位（bohr, hartree）**；默认值对照 MAPLE 的 dataclass，
在保持物理意义的前提下换算为 a.u.（MAPLE 用 Å、Eh/Å）。

### 3.3.1 公共基底

```fortran
type :: landscape_common_settings
   real(wp) :: etemp      = 300.0_wp     ! 电子温度 K
   logical  :: verbose    = .true.
   integer  :: printlevel = 1
   real(wp) :: f_max_th   = 1.0e-4_wp    ! hartree/bohr  (= 5e-3 Eh/Å 量级)
   real(wp) :: f_rms_th   = 5.0e-5_wp
   real(wp) :: dp_max_th  = 3.0e-3_wp    ! bohr
   real(wp) :: dp_rms_th  = 2.0e-3_wp
   integer  :: max_iter   = 256
end type
```

### 3.3.2 sp

```fortran
type :: landscape_sp_settings
   integer  :: verbose = 0               ! 0=E+charge, 1=+gradient（对照 MAPLE SPParams）
   logical  :: write_gradient = .false.
end type
```

### 3.3.3 opt（对照 MAPLE LBFGSParams / RFOParams / SDCGParams）

```fortran
type :: landscape_opt_settings
   character(len=16) :: method = 'lbfgs'  ! lbfgs|rfo|sd|sdcg（对照 Optimization.run）
   integer  :: max_iter       = 256
   ! L-BFGS（MAPLE LBFGSParams）
   integer  :: memory         = 5
   real(wp) :: curvature      = 70.0_wp
   real(wp) :: max_step       = 3.78e-1_wp  ! 0.2 Å -> bohr
   ! RFO trust region（MAPLE RFOParams）
   real(wp) :: trust_radius_init = 3.78e-1_wp
   real(wp) :: trust_radius_min  = 1.89e-3_wp
   real(wp) :: trust_radius_max  = 1.89_wp
   real(wp) :: eta_shrink = 0.75_wp
   real(wp) :: eta_expand = 1.75_wp
   ! SD/CG（MAPLE SDCGParams）
   integer  :: sd_max_iter = 50
   logical  :: diis_enabled = .true.
   integer  :: diis_memory  = 6
   integer  :: diis_min_snapshots = 3
end type
```

### 3.3.4 scan（对照 MAPLE Scan + FixInternals）

```fortran
type :: scan_coord_setting
   character(len=8) :: ctype = 'distance'   ! distance|angle|dihedral
   integer :: atoms(4) = 0
   real(wp):: step  = 0.0_wp                 ! bohr 或 rad
   integer :: nstep = 0
end type

type :: landscape_scan_settings
   character(len=8) :: mode   = 'relaxed'    ! relaxed|rigid
   character(len=16):: method = 'lbfgs'      ! 松弛用优化器
   integer :: ndim = 1
   type(scan_coord_setting) :: coord(3)      ! 最多 3D
   logical :: sequential = .true.            ! sequential | concerted (grid)
end type
```

### 3.3.5 ts（对照 MAPLE PRFOParams / DimerParams / NEBParams / AutoNEBParams / GSMParams）

```fortran
type :: landscape_ts_settings
   character(len=16) :: method = 'prfo'   ! prfo|dimer|neb|cineb|autoneb|string|gsm
   integer :: max_iter = 256
   ! P-RFO（MAPLE PRFOParams）
   real(wp) :: trust_radius = 3.78e-1_wp
   real(wp) :: trust_min    = 1.89e-3_wp
   real(wp) :: trust_max    = 1.89_wp
   real(wp) :: eta_shrink   = 0.75_wp
   real(wp) :: eta_expand   = 1.75_wp
   real(wp) :: evals_eps    = 1e-10_wp
   real(wp) :: mu_margin    = 1e-8_wp
   integer  :: max_bisect_it = 60
   integer  :: recalc        = 1            ! Hessian 重算间隔
   character(len=8) :: hessian_update = 'bofill'   ! bofill|bfgs|powell
   integer  :: target_mode = 1              ! 用第几个负模
   ! Dimer（MAPLE DimerParams）
   real(wp) :: dimer_delta   = 9.45e-3_wp   ! 0.005 Å -> bohr
   integer  :: rot_max_iter  = 5
   real(wp) :: rot_alpha     = 0.5_wp
   real(wp) :: rot_f_max_th  = 1.0e-3_wp
   real(wp) :: rot_f_rms_th  = 5.0e-4_wp
   logical  :: use_mass_weight = .false.
   character(len=8) :: n_init = 'random'    ! random|force|given
   ! NEB / CI-NEB（MAPLE NEBParams）
   integer  :: n_images = 10
   real(wp) :: k_min = 0.03_wp
   real(wp) :: k_max = 0.3_wp
   logical  :: use_dynamic_k = .true.
   real(wp) :: k_decay = 0.5_wp
   integer  :: lbfgs_m = 20
   real(wp) :: step0   = 3.78e-2_wp         ! 2e-2 Å -> bohr
   integer  :: ifidpp  = 1                  ! IDPP 初始路径
   character(len=8) :: refine = ''          ! ''|cineb|nebts
   ! AutoNEB（MAPLE AutoNEBParams）
   real(wp) :: ang_max = 0.3_wp
   integer  :: ang_iter = 20
   integer  :: max_depth = 5
   integer  :: max_paths = 10
   ! String/GSM（MAPLE GSMParams）
   real(wp) :: grow_step = 6.8e-2_wp        ! 0.12 Å
   real(wp) :: grow_step_min = 1.1e-2_wp
   real(wp) :: merge_threshold = 0.5_wp
   integer  :: string_n_images = 9
end type
```

### 3.3.6 irc（对照 MAPLE GSParams / HPCParams / LQAParams / EulerPCParams）

```fortran
type :: landscape_irc_settings
   character(len=16) :: method = 'gs'       ! gs|hpc|lqa|eulerpc
   integer  :: target_mode = 1
   real(wp) :: step_length_bohr = 0.10_wp   ! 已是 bohr
   integer  :: max_steps = 50
   integer  :: max_micro_cycles = 20        ! GS
   real(wp) :: micro_step_thresh = 1e-3_wp
   integer  :: euler_n = 5000               ! LQA/HPC
   integer  :: max_pred_steps = 500         ! EulerPC
   integer  :: loose_cycles = 3
   integer  :: hessian_recalc = -1          ! -1 = never（MAPLE None）
   character(len=8) :: hessian_update = 'bofill'  ! bofill|bfgs
   ! DWI / mBS corrector
   integer  :: dwi_n = 4
   integer  :: mbs_max_k = 15
   integer  :: mbs_points = 20
   real(wp) :: mbs_tol = 1e-5_wp
   logical  :: integrate_forward = .true.
   logical  :: integrate_backward = .true.
   logical  :: print_each = .true.
end type
```

### 3.3.7 vib / hessian / thermo（对照 MAPLE FrequencyParams）

```fortran
type :: landscape_vib_settings
   character(len=8) :: method = 'mw'        ! mw | cart（mass-weighted 与否）
   real(wp) :: temperature = 298.15_wp
   real(wp) :: pressure_kpa = 101.325_wp
   integer  :: ilowfreq = 2                 ! 低频处理方案（对照 numhess）
   logical  :: treat_imag_as_real = .false.
   real(wp) :: imag_tol_cm1 = 10.0_wp
   integer  :: n_freqs_print = 10
   integer  :: hessian_type = 0             ! 0=数值差分,1=ODLR(O1NumHess)
   real(wp) :: numdiff_step = 5.0e-3_wp     ! bohr
end type
```

### 3.3.8 单位边界

- **内部**：长度 bohr、能量 hartree、力 hartree/bohr、Hessian hartree/bohr²、
  频率 cm⁻¹、温度 K、压力 kPa。
- **外部 I/O**：`.xyz`/`.coord` 用 Å（沿用 xtb `writeMolecule`），输出能量表用 hartree + kcal/mol。
- 转换函数集中放在 `types/settings.f90` 的 `to_bohr`/`to_angstrom`/`to_hartree` 中，
  使用 `xtb_mctc_convert`（`autoaa`, `aatoau` 等），避免散落各处。

---

## 3.4 结果类型与日志/轨迹格式

### 结果/返回类型

```fortran
type :: landscape_result
   integer  :: status = 0                ! 0=converged, 1=maxiter, <0=error
   integer  :: n_iter = 0
   integer  :: n_eval = 0                ! E+G calls
   integer  :: n_hess = 0
   real(wp) :: energy = 0.0_wp           ! hartree (final / TS / endpoint)
   real(wp) :: gnorm  = 0.0_wp           ! hartree/bohr
   real(wp) :: egap   = 0.0_wp
   real(wp), allocatable :: xyz(:,:)     ! final geometry (bohr)
   real(wp), allocatable :: gradient(:,:)
   real(wp), allocatable :: hess(:,:)    ! optional
end type

type :: landscape_path_result               ! NEB/string/scan
   integer :: n_images = 0
   real(wp), allocatable :: xyz(:,:,:)      ! (3, nat, n_images)
   real(wp), allocatable :: energy(:)       ! (n_images)
   real(wp) :: e_barrier = 0.0_wp           ! 势垒 hartree
   integer  :: ts_image = 0
end type

type :: landscape_irc_result
   integer :: n_forward = 0, n_backward = 0
   real(wp), allocatable :: xyz_fwd(:,:,:)  ! (3,nat,n)
   real(wp), allocatable :: xyz_bwd(:,:,:)
   real(wp), allocatable :: e_fwd(:), e_bwd(:)
   logical :: reached_min_fwd = .false., reached_min_bwd = .false.
end type

type :: landscape_vib_result
   real(wp), allocatable :: freq(:)         ! cm⁻¹ (含虚频为负)
   real(wp), allocatable :: modes(:,:)      ! (3n, 3n) 简正模式
   real(wp) :: zpe = 0.0_wp                 ! hartree
   real(wp) :: g_correction = 0.0_wp        ! hartree
   type(thermo_block) :: thermo(2)          ! T1, T2（对照 xtb 输出）
end type
```

### 输出文件约定（与 xtb/MAPLE 兼容）

| 任务 | 文件 | 内容 |
|---|---|---|
| opt | `xtbopt.xyz` | 最终几何（现有；`prog/main.F90:1131`） |
| opt | `xtbopt.log` | 每步几何（现有；`geoopt_driver.f90` 打开） |
| opt/ts/irc | `xtb.trj` | 轨迹（现有命名习惯） |
| scan | `xtbscan.log` | 每步几何+能量（现有；`scan_driver.f90:57`） |
| scan | `xtbscan.xyz` | 追加式轨迹（可选） |
| ts (NEB/string) | `path.xyz` | 多帧初始/最终路径，comment 含 energy |
| ts (dimer) | `ts_dimer_traj.xyz` | dimer 轨迹（对照 MAPLE `*_dimer_traj`） |
| ts (autoneb) | `mep.xyz`, `all_intermediates.xyz`, `all_ts.xyz` | 对照 MAPLE autoneb 输出 |
| irc | `irc_forward.xyz`, `irc_backward.xyz`, `irc_path.xyz` | 对照 MAPLE |
| vib | `vibspectrum`, `vib_normal_modes`, `hessian.out` | 现有 `freq/io.f90` |
| 通用日志 | stdout（`env%unit`） | MAPLE 风格分节表头（`=...`） |

日志格式：沿用 xtb `generic_header` 风格；每步打印 `iter / energy(hartree) /
gnorm / f_max / dp_max / egap`，与 `relaxation_engine` 现有表格一致。

---

## 3.5 集成点

### 3.5.1 CLI：新 runtyp

现有点位：
- `src/setparam.f90:197-215` 定义 `p_run_*` 常量。
- `src/set_module.f90:1032 set_runtyp(typ)` 是 runtyp 字符串->常量的映射。
- `src/prog/main.F90` 在 ~1095 起按 `set%runtyp` 分派各计算模块。

**新增**（示意）：
```
src/setparam.f90:
   integer, parameter :: p_run_scan = 16   ! (数值需避开已用: 现最大 15, 另有 71,100..)
   integer, parameter :: p_run_ts   = 17
   integer, parameter :: p_run_irc  = 18
   integer, parameter :: p_run_neb  = 19
   integer, parameter :: p_run_string = 20

src/set_module.f90: set_runtyp()
   case('scan'); set%runtyp = p_run_scan
   case('ts')  ; set%runtyp = p_run_ts
   case('irc') ; set%runtyp = p_run_irc
   case('neb') ; set%runtyp = p_run_neb
   case('string'); set%runtyp = p_run_string
```
在 `main.F90` 的主分派（`src/prog/main.F90:1095-1260`）加入：
```
if (set%runtyp == p_run_scan)  call run_landscape_scan(env, mol, chk, calc, ...)
if (set%runtyp == p_run_ts)    call run_landscape_ts(...)
if (set%runtyp == p_run_irc)   call run_landscape_irc(...)
```
新命令行 flag（与现有 `--ohess/--opt/--hess` 并列）：`--scan`, `--ts`, `--irc`,
`--neb`, `--string`，以及参数透传 `--tsmethod prfo|dimer|neb|...`。

### 3.5.2 xcontrol 扩展

在 `src/constrain_param.f90` 的 handler 机制（`main.F90:449 call read_userdata`）
注册新 `set_ts` / `set_irc` / `set_scanmode`，复用现有 `$constrain`/`$scan`。

### 3.5.3 构建：CMake 与 Meson

`src/CMakeLists.txt` 目前通过 `add_subdirectory(...)` + `list(APPEND srcs ...)`
（`src/CMakeLists.txt:17-38`；子目录用 `freq/CMakeLists.txt` 模式回传 `PARENT_SCOPE`）。
**新增**：
```cmake
# src/CMakeLists.txt
add_subdirectory("landscape")
```
`src/landscape/CMakeLists.txt`（模仿 `src/freq/CMakeLists.txt`）：
```cmake
set(dir "${CMAKE_CURRENT_SOURCE_DIR}")
add_subdirectory("types")
add_subdirectory("coords")
# ... optimize / saddle / path / irc / scan / vib
list(APPEND srcs
  "${dir}/landscape_api.f90"
  "${dir}/landscape_driver.f90"
)
set(srcs ${srcs} PARENT_SCOPE)
```
`src/meson.build` 类似：`subdir('landscape')`，`landscape/meson.build` 用
`srcs += files('landscape_api.f90', ...)`（对照 `src/freq/meson.build`）。

### 3.5.4 测试注册

`test/unit/CMakeLists.txt`（TEST 列表，`test/unit/CMakeLists.txt:24-56`）与
`test/unit/meson.build`（`tests = [...]`，`test/unit/meson.build:38-68`）各加：
```
landscape-settings landscape-coords landscape-optimize
landscape-scan landscape-saddle landscape-path
landscape-irc landscape-vib
```
对应 `test/unit/test_landscape_*.f90`，用 test-drive（参照 `test_hessian.f90` 头部）。
CMake 会自动 `add_test`（`test/unit/CMakeLists.txt:88`），Meson 自动 `test()`。

---

## 3.6 分阶段里程碑（M0–M7）

| 阶段 | 交付物 | 验收测试 |
|---|---|---|
| **M0** 骨架+测试 | `src/landscape/` 空壳、`xtb_landscape_engine`、settings/results 类型、构建接入（CMake+Meson）、test-drive 骨架 | `test_landscape_settings` 默认值逐项断言；`test_landscape_engine` 对同一水分子两次 `engine_energy_gradient` 能量逐位相等（确定性），并核对 `n_eval`；构建在两套系统均通过 |
| **M1** 极小化 | `optimize/{sd,lbfgs,bfgs,diis,rfo}.f90`，封装现有 `bfgs.f90`/`relaxation_engine`/`geometry_optimization` | water/coffee 优化到 `f_max<1e-4`；`test_landscape_optimize` 与 xtb 现有 `--opt` 对同一初值收敛到相同极小（能量差 < 1e-6 hartree） |
| **M2** 扫描 | `scan/scan1d.f90`、`scan2d.f90`（复用 `constrain_pot` + `geometry_optimization`），`set_scan` 扩展 | relaxed dihedral scan 能量剖面单调性/极值位置与 MAPLE scan 对照；rigid scan 与手工几何一致；`test_landscape_scan` 2D grid 计数正确 |
| **M3** Hessian/freq | `vib/{numhess,project,modes,thermo}.f90`（封装 `hessian.F90`+`freq/*`+`o1numhess`） | `test_landscape_vib` 对 water 频率与现有 `--hess` 输出逐位/容差一致；ZPE 与解析参考一致；简正模式正交性检验 |
| **M4** P-RFO/dimer | `saddle/{prfo,bprfo,dimer,eigenfollow}.f90`（P-RFO 复用 `david2`+`projectHessian`+`find_projected_imag_modes`；dimer 新写） | HCN/H2CO 异构化 TS：找到 1 个虚频，`|f|<thr`；dimer 从偏置初值收敛到同一 TS；`test_landscape_saddle` |
| **M5** NEB/string | `path/{idpp,neb,cineb,autoneb,string,gsm}.f90` + `cqpath` 插值复用 | 已知反应（如 HCN↔HNC）CI-NEB 势垒与文献/ MAPLE 对照 < 0.5 kcal/mol；IDPP 初始路径无自交；`test_landscape_path` |
| **M6** IRC | `irc/{gs,hpc,lqa,eulerpc}.f90`（mass-weighted，复用投影+Hessian+`david2`） | 从 M4 的 TS 出发 IRC 两端收敛到正确极小；forward/backward 能量连续、步长稳定；`test_landscape_irc` |
| **M7** thermo/validation | 热化学输出整合、与 MAPLE 全流程对照、文档 | 端到端测试：GFN2 + opt→hess→freq→thermo 给出与 xtb `--hess` 一致的 G/H/ZPE；对 MAPLE 的 sp/opt/scan/ts/irc/freq 各任务做数值对照记录 |

每阶段都要求：新模块有独立 `test_landscape_*.f90`，且不破坏现有 `test/unit` 全绿。

---

## 3.7 明确不移植的范围

| 不移植项 | 原因 |
|---|---|
| **torch / GPU 后端** | MAPLE 的 `torch`、`device='cuda'`、ML 计算器（ANI/MACE/UMA/AIMNet2/Fennol）本质是 Python 生态；xtb 定位是量子化学半经验方法，无 GPU 张量需求 |
| **ML-potential calculators** | 同上；xtb 的引擎边界是 `class(TCalculator)`，ML 势应作为外部 `extern` 计算器接入，而非内建 |
| **`parmfit`（参数拟合全套：NCAA/TorsionFit/ChargeFit/MetalAA/QMInterface/Scan）** | 属参数开发工具链，与本套件“PES 任务执行”目标正交；建议独立项目 |
| **DMF (Direct MaxFlux)** | 依赖 `cyipopt` 外部 NLP 求解器（`ts/algorithm/dmf.py` 中 `import cyipopt`），且是独立算法族；可作为 M5 之后的扩展 |
| **MD 系综（NVE/NVT/NPT、thermostat/barostat/integrator）** | xtb 已有独立 `md`/`omd`（`prog/main.F90:1153`）；重复实现无收益。MD 不在本次 sp/opt/scan/ts/hess/freq/irc 范围内 |
| **`intmodes.f90` 旧 Z-matrix** | 被 `internals/*`+`bmatrix` 取代 |
| **`bias_path` 的 metadynamics 自举路径** | 与标准 NEB/string 目标不同，仅借鉴 `guess_tsmode`/`alignpath` |

---

## 3.8 风险与开放问题

1. **`wp => sp` 单精度**：`david2.f90` 内部用单精度；P-RFO 若要求双精度本征对，需
   增加双精度 wrapper 或改用 LAPACK 全对角化（小体系）。**风险：中等。**
2. **`numhess` 与 PTB/metadyn 耦合**：直接复用需以 `set%` 开关把 PTB 分支静默关闭。
   建议 M3 优先用 `class(TCalculator)%hessian`（更干净）而非 `numhess`。
3. **`constrain_pot` 的“势+梯度”是有限势垒**：对严格约束的 TS/scan，需确认其刚度足够
   或改用真正投影约束。**风险：对定量势垒影响需 M5 验证。**
4. **单位混用历史**：xtb 内部多处 Å/Eh-Å 混用（MAPLE 亦然）。设计已强制 a.u. 内部 +
   显式边界转换，但复用旧子程序（如 `scan_driver`）时需逐点审计。
5. **runtyp 编号冲突**：`p_run_*` 有非连续编号（71、100+），新增常量的取值需全仓库
   grep 确认无冲突。
6. **DL-FIND 版权**：其 LGPL 与 xtb 兼容，但**本设计不搬运其代码**，仅借鉴设计，无版权风险。

---

## 3.9 首个应打开的文件

实现者应先打开 **`src/type/calculator.f90`（`TCalculator` 抽象接口，第 43–155 行）**，
因为整套新套件的引擎边界完全建立在此之上；随后打开 `src/single.f90:41`
（`singlepoint` wrapper）与 `src/geoopt_driver.f90:23`（`geometry_optimization` 统一松弛入口），
即可掌握“算一次 E+G”和“做一次受约束松弛”的两个核心原语。
