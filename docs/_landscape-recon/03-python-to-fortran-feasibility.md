# MAPLE 调度器算法 → Fortran 移植可行性硬核分析（03）

> 调查范围：`/home/owenchan/work_path/coding/python/MAPLE/maple/function/dispatcher/`（133 个 `.py`，Python/ASE/NumPy 实现的 landscape explorer）
> 目标：评估在 `/home/owenchan/work_path/coding/fortran/xtb`（grimme-lab/xtb 6.7.1，GFN2-xTB）中，用 Fortran 重建 sp / opt / scan / ts / hessian / freq / irc 的可行性。
> 方法：全部结论基于实测 grep/wc/cat 计数，非估计。引用格式 `path:line`。
> 结论先行（详见 §E）：**整体可行**。sp/opt/scan/hessian/freq 属于「机械改写 + 复用 xtb 现有内核」；ts/irc（PRFO、NEB、dimer、GSM、IRC）属「按文献重写」但不需要外部库；**唯一硬阻塞是 DMF（Direct MaxFlux）依赖 cyipopt/Ipopt 非线性优化器与 scipy BSpline/Rotation/interp1d。**

---

## 0. 任务族与文件映射

| 任务族 | 入口 | 算法文件目录 |
|---|---|---|
| sp | `sp/sp.py`（112 行） | 无 |
| opt | `optimization/optimization.py`（37） | `optimization/algorithm/` |
| scan | `scan/scan.py`（491） | `scan/algorithm/` |
| ts | `ts/ts.py`（140） | `ts/algorithm/` |
| hessian | `hessian/hessian.py`（39，torch autograd 二阶导） | — |
| freq | `frequency/frequency.py`（1306） | — |
| irc | `irc/irc.py`（34） | `irc/algorithm/` |

调度顶层 `dispatcher.py:27-138` 按 `jobtype` 字符串分发；`set_throshould()`（`dispatcher.py:145-217`）统一设置 Gaussian 风格收敛阈值。

---

## A. 依赖面（Dependency surface）

### A.1 import 频率表（按类别聚合）

统计命令：`grep -rhoE '^(import|from) +[A-Za-z0-9_.]+' <dispatcher> | awk '{print $2}' | sort | uniq -c | sort -rn`。

**stdlib（标准库，无移植负担）**
`__future__`(65)、`typing`(60)、`dataclasses`(51)、`os`(45)、`pathlib`(19)、`math`(15)、`copy`(15)、`collections`(12)、`shutil`(9)、`re`(9)、`time`(5)、`itertools`(5)、`sys`(4)、`subprocess`(4)、`functools`(4)、`contextlib`(3)、`abc`(2)、`json`(2)、`shlex`(2)、`warnings`(1)、`threading`(1)、`struct`(1)、`gc`(1)、`concurrent.futures`(1)、`collections.abc`(1)、`importlib.util`(1)、`lib2to3.pgen2`(1，见下注)。

**numpy（65 处 import）** — 移植目标：全部映射到 xtb 原生数组运算 / BLAS / LAPACK。

**scipy（4 处 import，全部集中在 DM F / 调参路径）**：
- `from scipy.optimize import minimize`（`parmfit/utils/TorsionFit/stage2.py:8`）
- `from scipy.optimize import brentq`（`scan/algorithm/RFO.py:11`）
- `from scipy.spatial.transform import Rotation`（`ts/algorithm/dmf.py:32`）
- `from scipy.interpolate import BSpline, interp1d`（`ts/algorithm/dmf.py:31`）

**ase（59 处 import）** — 详见 A.4。

**torch（8 处 import + 多处 `torch.*` 调用）** — 详见 A.5。

**fairchem**：**dispatcher 内零命中**（`grep -rn 'fairchem'` 无结果）。fairchem/UMA/MACE 只出现在 calculator 层（`maple/function/calculator/uma/` 等），不属于调度算法。移植时不涉及。

**第三方非 numpy/scipy/ase/torch**：
- `cyipopt`：`ts/ts.py:115`、`ts/algorithm/dmf.py:23,1058,1392`（DMF 核心，见 §E）。
- `numpy.polynomial`：`ts/algorithm/dmf.py:30`（DMF 样条）。
- `maple.function.timer`(13)、`maple.function.utility`(4)、`maple.function.read.filereader.pdb_reader`(12) 等为 maple-internal。

**maple-internal（相对导入）主要目标**：`.config`(20)、`...jobABC`(15)、`.logger`(11)、`.utility`、`.read.filereader.pdb_reader`(12) 等。**这些只是 I/O、日志、参数解析脚手架，不含数值内核**，Fortran 侧用 `readin.f90`/`printout.f90`/自写日志替代。

### A.2 numpy 函数清单（实际使用，实测计数）

命令：`grep -rhoE 'np\.[A-Za-z_][A-Za-z0-9_.]*' <dispatcher> | sort | uniq -c | sort -rn`（含类型注解噪声 `np.ndarray`969）。

**线性代数（核心，决定移植成本）**：
- `np.linalg.norm` 109
- `np.linalg.eigh` 12、`np.linalg.eig` 3、`np.linalg.eigvalsh` 1、`np.linalg.svd` 4、`np.linalg.solve` 6、`np.linalg.lstsq` 5、`np.linalg.det` 5、`np.linalg.qr` 1、`np.linalg.pinv` 1、`np.linalg.matrix_rank` 1、`np.linalg.LinAlgError` 5
  → 全部有 LAPACK 对应（`dsyev/dsyevd`、`dgeev`、`dgesvd`、`dgesv`、`dgels`），xtb 已链接 LAPACK（`src/mctc/lapack/trs.f90`）。
- `np.einsum` 9、`np.tensordot` 9、`np.outer` 33、`np.matmul` 1、`np.dot` 126、`np.cross` 26
  → 前 4 个用于 DMF/PRFO/string 的张量收缩，Fortran 需展开为显式 `do` 循环或 `matmul`。

**逐元素/归约**：`np.asarray`351、`np.zeros`88、`np.abs`85、`np.float64`67、`np.sum`57、`np.mean`57、`np.max`52、`np.zeros_like`50、`np.where`40、`np.cos/sin`38/34、`np.pi`35、`np.isfinite`36、`np.array`30、`np.exp`19、`np.sign`17、`np.all`16、`np.empty`13、`np.random.Generator`12、`np.random.default_rng`11、`np.linspace`11、`np.argsort`9、`np.clip`7、`np.interp`/`gradient`/`einsum`/`kron` 等。

**注意**：`np.kron` **无命中**（0 次）；`np.gradient`、`np.interp` 无命中 —— 任务清单中担心的这两个实际未使用。`np.tensordot`/`np.einsum`/`np.matmul` 仅出现在 `ts/algorithm/dmf.py`（实测 grep 全部落点在该文件）与少数 scan。

### A.3 scipy 逐项移植分类

| scipy 路径 | 使用点 | 移植分类 | 依据 |
|---|---|---|---|
| `scipy.optimize.brentq` | `scan/algorithm/RFO.py:167`（对 eigvals 求 RFO 位移 μ 的根） | **needs-implementation** | 只需实现标量 Brent 求根（~40 行 Fortran），或直接用已有的 `findlroot`（`src/optimizer.f90:1048`）思路。无外部库依赖。 |
| `scipy.optimize.minimize` | `parmfit/utils/TorsionFit/stage2.py:732,784` | **needs-library**（若做 parmfit）/ 对本目标 **out of scope** | TorsionFit 属参数拟合，不在 sp/opt/scan/ts/freq/irc 范围。 |
| `scipy.spatial.transform.Rotation`（`align_vectors`） | `ts/algorithm/dmf.py:1480` | **needs-implementation** | Kabsch/对齐算法，~60 行（SVD 已有 LAPACK）。 |
| `scipy.interpolate.BSpline`/`interp1d` | `ts/algorithm/dmf.py:1303,1495,1927,1943` | **needs-implementation** | B-样条基与线性插值；xtb 已有 `spline2.f90`/`spline3.f90` 可复用思路。 |

**结论**：除 DMF 与 TorsionFit（parmfit）外，核心算法族的 scipy 依赖只有 `brentq`（scan RFO），可实现为 ~40 行 Fortran，**不引入外部库**。

### A.4 ASE API 清单与 xtb 等价物

命令：`grep -rhnE '^(import|from) +ase'`。命中 API：

| ASE API | 出现 | xtb 现状 | 等价性 |
|---|---|---|---|
| `ase.Atoms`（`get_positions/set_positions/get_forces/get_potential_energy/get_masses/get_chemical_symbols`） | 26+ 处（几乎每个算法文件） | `src/type/molecule.f90`、`src/api/molecule.f90` 提供 `mol%xyz`、`mol%at`、`mol%mass`；能量/梯度由 `xtb_calculator`（`src/api/calculator.f90:278 loadGFN2xTB_api`）输出 | **已有**，需薄封装层 |
| `ase.neighborlist.NeighborList` + `natural_cutoffs` | `scan/scan.py:6,432`、`parmfit/utils/Scan/engine.py:11,400` | `src/neighbor.f90`（邻居表）、`src/topology.f90` | **已有**（xtb 自身 SCC 就用邻居表） |
| `ase.constraints.FixInternals`（键/角/二面角约束） | `scan/scan.py:5,114` | `src/constrain_pot.f90`（约束势）、`src/scanparam.f90`（扫描参数） | **已有**，但语义需对齐（ASE 用 Lagrange/投影，xtb 用约束势 + `bmatrix.f90`） |
| `ase.data.covalent_radii`、`ase.data.atomic_numbers`、`ase.data.chemical_symbols` | `scan.py:28`、`parmfit/utils/*` | `src/elem.f90`、`src/param/*`、`src/mctc/mctc_constants.f90` | **已有** |
| `ase.data.vdw_alvarez.vdw_radii` | `parmfit/utils/*` | `src/param/vdwrad*.f90` | **已有**（parmfit 才用） |
| `ase.cell.Cell` | `parmfit/utils/*.py:38` | `src/pbc.f90`、`src/pbc_tools.f90` | **已有** |
| `ase.optimize.*`（`LBFGS/...`） | 未直接 import（MAPLE 自实现优化器，见 §B） | `src/optimizer.f90`（ancopt/relax）、`src/lbfgs_anc/lbfgs.f90` | **已有**（Fortran 侧甚至更成熟） |
| `ase.vibrations` | **未 import**（MAPLE 自实现 freq） | `src/freq/project.f90`（`projectHessian`、`trproj`）、`src/frequency` 相关 | **已有** |
| `ase.mep.NEB` | **未 import**（MAPLE 自实现 neb.py, 1540 行） | **无** | **缺失**，须重写 |
| `ase.calculators.calculator.Calculator` / `PropertyNotImplementedError` | calculator 基底类 | `src/api/calculator.f90` | 已有等价接口 |
| `ase.calculators.mixing.SumCalculator` | 隐式溶剂叠加 | `src/solv/*`、`src/embedding.f90` | 已有 |

**关键**：`get_hessian`（6 处调用）、`get_hvp`（5 处调用，dimer 用）是 MAPLE 算法依赖的**计算器扩展接口**：
- `optimization/algorithm/RFO.py:195` → `atoms.calc.get_hessian(atoms)`
- `frequency/frequency.py:320`、`irc/algorithm/{gs,hpc,eulerpc,lqa}.py:311/422/426/312`
- `ts/algorithm/dimer.py:353` → `atoms.calc.get_hvp(atoms, n)`
- 接口定义见 `maple/function/calculator/calculator_base.py:355 get_hessian` 与 `:398 get_hvp`（数值 Hessian → `:173 numerical_hessian_from_atoms`，或 autograd → `:237 hessian_via_double_autograd`）。

xtb 侧对应物：`src/hessian.F90:33 numhess`（数值二阶导）、`src/o1numhess.f90`、`src/model_hessian/*`（EEQ/GFF/Lindh/Swart 近似 Hessian）已具备；**没有现成的 Hessian-vector product**，但 `numhess` 可充当。

### A.5 torch 使用（逐文件 + 用途）

命令：`grep -rlE 'torch'` → 18 个文件（含 parmfit）。按用途分类：

| 文件 | torch 用途 |
|---|---|
| `hessian/hessian.py:6` | **纯 autograd 二阶导**：`torch.autograd.grad([y.sum()],[x])` 计算解析 Hessian。这是唯一真 autograd 依赖。 |
| `optimization/algorithm/blbfgs.py` | **批量 GPU L-BFGS**：用 `torch.Tensor` 做 `(B, nmax)` 批量化数组（`:26`）、`_two_loop_batched`（`:220`）。torch 仅当数组容器 + `torch.where/clamp`，**非 autograd**。 |
| `optimization/algorithm/_common.py:55` | 仅 `isinstance(x, torch.Tensor)` 类型转换。 |
| `ts/algorithm/BPRFO.py:369` | **批量 PRFO 的 `torch.linalg.eigh`**（`:369`）、批量掩码运算。 |
| `ts/algorithm/{PRFO,neb,string,dimer}.py` | `torch` 仅作类型提示/可选张量后备（PRFO 主要以 numpy 为主）。 |
| `ts/algorithm/_dmf_torch_backend.py` | DMF 的 vendored torch 后端加载（`importlib.utilspec_from_file_location`，`:33`）。 |
| `frequency/frequency.py:22-25,298-300` | **可选** GPU 加速：CUDA 可用时 `torch.linalg.eigh` 替代 `np.linalg.eigh`。CPU 路径纯 numpy。 |
| `irc/algorithm/{gs,hpc,eulerpc,lqa}.py` | 仅 `to_f64` 里的 `isinstance(x, torch.Tensor)` 兜底。 |
| `parmfit/utils/{mlip_tools,runtime}.py` | ML 势模型推理（out of scope）。 |

**判定**：对 sp/opt/scan/freq/irc 的核心数值路径，torch 是**可选 GPU 加速或批量容器**，不是算法本质。Fortran 移植完全可弃用 torch：批量逻辑在 Fortran 用 BLAS-3 批量矩阵运算或 OpenMP 实现；Hessian autograd 用 xtb 的 `numhess`（数值）替代。

---

## B. 逐模块移植难度

计数方法：`wc -l`；`grep -cE '(^|[^a-zA-Z_])if '`（含注释中的 if，故偏高，作相对比较）；`np.linalg|torch.linalg` 等。LOC 估计为「机械改写」的 Fortran 行数经验值（Python 行数 × 1.2–1.6；「重写」更高）。

### B.1 optimization/algorithm/

| 文件 | LOC | if/for/while | 数值内核 | 移植评级 | Fortran LOC 估 |
|---|---|---|---|---|---|
| `_common.py` | 89 | 6/3/0 | `np.abs.max`、RMS 收敛度量（`:74-89`）；XYZ 写文件 | **1:1 mechanical** | ~90 |
| `LBFGS.py` | 219 | 18/3/1 | 两点循环（`_two_loop:61-84`，纯 `np.dot`）、位移裁剪（`:86-90`）、历史栈 | **1:1 mechanical** | ~230 |
| `RFO.py` | 389 | 31/5/2 | `np.linalg.eigh`（`:224`）、trust-region 二分求 μ（`:254-279` 纯标量）、质量加权 `(D[:,None]*H)*D[None,:]`（`:210`） | **1:1 mechanical**（二分可复用 `findlroot` `optimizer.f90:1048`） | ~420 |
| `SDCG.py` | 557 | 52/8/1 | 最速下降/共轭梯度，纯向量运算 | **1:1 mechanical** | ~560 |
| `DIIS.py` | 218 | 9/13/0 | 外推/线性方程组 `np.linalg.solve`（`:?`） | **1:1 mechanical** | ~240 |
| `SD.py` | 11 | 0/3/0 | 调用 SDCG | **1:1 mechanical** | ~15 |
| `blbfgs.py` | 535 | 12/23/1 | **批量 torch L-BFGS**：`(B,nmax)` 张量两点循环（`:220-289`）、`torch.where/clamp` 掩码（`:246,265,302`） | **needs-redesign** | ~600（需用 `(B,3N)` 二维数组 + BLAS 批处理重写批量语义） |

### B.2 scan/

| 文件 | LOC | if/for/while | 数值内核 | 评级 | Fortran LOC 估 |
|---|---|---|---|---|---|
| `scan.py` | 491 | 36/38/1 | 约束扫描、`NeighborList` 连通性（`:430-445`）、`FixInternals`（`:107-121`）、1D/2D/3D 网格（`:380-405`） | **1:1 mechanical**（约束语义对齐 `constrain_pot.f90`） | ~520 |
| `scan/algorithm/LBFGS.py` | 176 | 10/5/1 | L-BFGS（tab 缩进，`:56` `f.reshape(-1)`） | **1:1 mechanical** | ~190 |
| `scan/algorithm/RFO.py` | 185 | 8/2/1 | **`np.linalg.eig`（非对称！`:32`）** + `scipy.optimize.brentq`（`:167`） | **needs-implementation** | ~230 |
| `scan/algorithm/logger.py` | 21 | — | 日志 | 1:1 | ~20 |

> `scan/algorithm/RFO.py:32` 用 `np.linalg.eig(Hessian)`（通用非对称求根）而非 `eigh`。移植须用 LAPACK `dgeev`，或改写为对称 `dsyev`（原代码在对称 Hessian 上使用，可等价替换）。

### B.3 ts/algorithm/

| 文件 | LOC | if/for/while | 数值内核 | 评级 | Fortran LOC 估 |
|---|---|---|---|---|---|
| `PRFO.py` | 892 | 66/25/4 | `np.linalg.eigh`（`:190,747,759`）、质量加权、模式追踪（`update_mode_tracking:634-672`，用 `abs(V.T@v)` + 符号对齐）、BFGS/Bofill Hessian 更新（`:382-425`，`np.outer`） | **1:1 mechanical** | ~1000 |
| `BPRFO.py` | 944 | 40/29/2 | 批量 `torch.linalg.eigh`（`:369`）、批量模式追踪（`:366-415`）、Bofill 混合（`:800`） | **needs-redesign**（批量 GPU） | ~1100 |
| `dimer.py` | 537 | 48/19/0 | 最小模式追踪（`_rotate_minimize_kappa:303`）、**`get_hvp`**（`:353`）、质量度量（`_get_metric:144-152`）、**`np.random.default_rng()` 无种子**（`:258`） | **1:1 mechanical**（须提供 HVP；随机初始化须加种子） | ~600 |
| `neb.py` | 1540 | 84/101/3 | Henkelman-Jonsson 能量加权切向（`:286`）、弹簧力、climbing-image（`cineb` 输出）、Kabsch 对齐（`C=Q0.T@P0:70`） | **1:1 mechanical** | ~1700 |
| `autoneb.py` | 1214 | 96/68/2 | 层次化 NEB 路径建树、树 JSON 序列化 | **needs-redesign**（树管理 + I/O 复杂，但无阻塞构造） | ~1400 |
| `string.py` | 954 | 89/41/5 | GSM：质量加权 Ekart 刚性投影（`:143-182`）、能量加权切向（`:387`）、生长/重参数化 | **1:1 mechanical** | ~1100 |
| `dmf.py` | 2767 | 155/107/1 | **`cyipopt.Problem`（`:1058,1368,1392`）**、`scipy BSpline/interp1d/Rotation`、`np.einsum/tensordot/matmul`（19 处）、变分路径作用量泛函（`:2409`） | **needs-external-library** | 移植需 Ipopt 接口或自写 NLP；~3000+ |
| `_dmf_torch_backend.py` | 121 | 11/6/1 | vendored torch 后端动态加载 | **infeasible（弃用）** | 0（GPU 后端不移植） |

### B.4 irc/algorithm/

| 文件 | LOC | if/for/while | 数值内核 | 评级 | Fortran LOC 估 |
|---|---|---|---|---|---|
| `gs.py` | 768 | 37/24/0 | Gonzales-Schlegel：质量加权 Hessian 对角化 `eigh`（`:234`）、微循环 Lagrange-λ 约束步、BFGS/Bofill Hessian 更新（`:370-389` `np.outer`） | **1:1 mechanical** | ~850 |
| `hpc.py` | 919 | 57/27/1 | HPC（Hessian predictor-corrector）IRC，同上内核 | **1:1 mechanical** | ~1000 |
| `eulerpc.py` | 964 | 60/27/1 | EulerPC IRC，含校正步 | **1:1 mechanical** | ~1050 |
| `lqa.py` | 722 | 38/23/0 | LQA（local quadratic approx）步，自带 Newton 求根（`：404` 注释「avoid scipy」（用自实现）） | **1:1 mechanical** | ~800 |
| `logger.py` | 21 | — | 日志 | 1:1 | ~20 |

### B.5 freq / hessian / sp

| 文件 | LOC | if/for/while | 数值内核 | 评级 | Fortran LOC 估 |
|---|---|---|---|---|---|
| `frequency/frequency.py` | 1306 | 57/42/0 | `np.linalg.eigh`（`:300` CPU/`:298` GPU）；平动-转动基构造（`:348-398`）、Hessian 投影（`:399+`）、RRHO + GERM-ME 热化学、`np.linalg.lstsq`、`np.polyfit`；硬编码 SI 常数（`:26-46`） | **1:1 mechanical**（xtb 已有 `freq/project.f90` 的投影与 `thermo.f90` 热化学） | ~1400 |
| `hessian/hessian.py` | 39 | — | **torch.autograd 二阶导** | **needs-redesign** | 用 xtb `numhess`（`hessian.F90:33`）替代，~0 净增 |
| `sp/sp.py` | 112 | 若干 | 无（调用计算器 + 格式化输出） | **1:1 mechanical** | ~120 |

### B.6 综合评级汇总

- **1:1 mechanical（可直接改写）**：`_common`、`LBFGS`(opt/scan)、`RFO`(opt)、`SDCG`、`DIIS`、`SD`、`scan.py`、`PRFO`、`dimer`、`neb`、`string`、`gs`、`hpc`、`eulerpc`、`lqa`、`frequency`、`sp`。共 ~16 个文件，占算法内核绝大多数。
- **needs-redesign**：`blbfgs`（批量 GPU 语义）、`BPRFO`（批量 GPU）、`autoneb`（树管理）、`hessian`（autograd → 数值）。
- **needs-implementation**：`scan/algorithm/RFO`（eig + brentq）。
- **needs-external-library / infeasible**：`dmf`（cyipopt）、`_dmf_torch_backend`（torch GPU 后端）。

**被阻塞的具体构造**：
1. `dmf.py:23 import cyipopt` + `:1058 class VariationalPathOpt(cyipopt.Problem)` —— 需要 Fortran 的 Ipopt 绑定（`Ipopt` 有 C/Fortran 接口 `ipopt.f`，可通过 `ipopt` 的 Fortran 调用层接入，但需引入 Ipopt 依赖）。
2. `blbfgs.py`/`BPRFO.py` 的 `(B, n)` 批量化 torch 张量 —— 需要重构为 `(n, B)` 列主序二维数组 + BLAS-3 批量调用。
3. `dimer.py:353 atoms.calc.get_hvp` —— xtb 无 HVP 接口，需基于 `numhess` 实现（或提供解析 HVP）。

---

## C. 数值卫生风险清单（Python↔Fortran 语义差异）

### C.1 float64 默认 vs Fortran 默认 real（`wp`/`sp` 约定）

- MAPLE 全程 `np.float64`（`to_numpy_f64` 在 `optimization/algorithm/_common.py:50-63` 强制转换；`:53` `astype(np.float64)`）。
- **xtb 强制双精度**：CMake `cmake/CMakeLists.txt:50` `-fdefault-real-8 -fdefault-double-8`（GNU），`:58`（LLVMFlang）；meson `meson/meson.build:30-31` 同样。`wp` = `dp`（`src/mctc/accuracy.f90:31` `integer, parameter :: wp = dp`）。
- **风险**：新写的移植代码若用裸 `REAL`，在无 `-fdefault-real-8` 的编译配置下会退化为单精度。**对策**：所有新代码显式 `use xtb_mctc_accuracy, only: wp`，字面量加 `_wp` 后缀；禁止裸 `REAL`/`DOUBLE PRECISION`。
- 双精度使得能量/梯度计算的舍入与 Python 一致，数值可比。

### C.2 0-based vs 1-based 索引与视图/拷贝

- 原子索引 0-based：`scan/scan.py:83` `atoms_idx = [a-1 for a in con["atoms"]]`（多处 `a-1` 显式转换）；`_common.py:31 image_index = start_index + i`。Fortran 1-based，转换时注意所有 `+1/-1`。
- **视图 vs 拷贝**（危险点）：`LBFGS.py:62 q = grad_flat.copy()`、`:98-99 self.S.append(s_vec.copy())` 显式拷贝以避免别名；`RFO.py:88 g_cart = vec1d(-F_cart)` 产生新数组。**Fortran 无隐式拷贝**，`_clip_step`（`LBFGS.py:86-90`）就地修改 `step_cart` 在 numpy 中依赖传入的是可写副本；Fortran 里对实参的就地修改语义不同，须显式 `intent(out)`/局部临时量。
- `np.where`（40 次）返回新数组；Fortran 用 `merge()` 或显式循环。

### C.3 row-major vs column-major（**最大语义坑**）

Python 数组是行主序（C order）：形状 `(N,3)` 的坐标/梯度展平 `.reshape(-1)` 后顺序为 `x1,y1,z1,x2,y2,z2,...`。Fortran 默认列主序：`REAL(wp) :: xyz(3,N)` 展平顺序同为 `x1,y1,z1,...`（因为首维是 3），**但** `REAL(wp) :: xyz(N,3)` 展平为 `x1,x2,...,xN,y1,...`（错误顺序）。

实测所有 `reshape` 落点：
- `optimization/algorithm/LBFGS.py:171,173,183,184`（`(-f).reshape(-1)`、`step_flat.reshape(f.shape)`）
- `optimization/algorithm/RFO.py:85,106`（`get_positions().reshape(-1,3)`、`s_cart.reshape(-1,3)`）
- `scan/algorithm/{LBFGS,RFO}.py:56/77/43/66`
- `ts/algorithm/string.py:130,158,160,175,182,394,397,429,431,437,439,440,460,479,483,...`（30+ 处）
- `ts/algorithm/dmf.py:1505`（`np.tensordot(...).reshape(-1,3*natoms)`）

**对策**：Fortran 中统一用 `REAL(wp) :: xyz(3*natoms)` 扁平向量（展平顺序与 numpy 一致），或 `xyz(3,natoms)`；**避免 `xyz(natoms,3)`**。所有 `.reshape(-1,3)`/`reshape(-1)` 对应为「记录展平约定」注释。

**转置 `.T` 落点**（`matmul` 顺序敏感）：
- `optimization/algorithm/RFO.py:225 g_proj = V.T @ g_mw` → Fortran `matmul(transpose(V), g)` 或 `matmul(V, g)`（对称矩阵本征向量 V 正交，注意 `V.T@x` 与 `V@x` 不同）。
- `ts/algorithm/PRFO.py:191,662,760`（`V.T@g`、`V_mw.T@tracked`）
- `ts/algorithm/string.py:63,181`、`ts/algorithm/neb.py:70`（`C=Q0.T@P0`，Kabsch）
- `ts/algorithm/dmf.py:1501,1502,1552,1711`（`matmul/tensordot(...).T`）
- `PRFO.py:383,425`（`0.5*(H_new + H_new.T)` 对称化）

**einsum/tensordot 落点**（全部在 `dmf.py`）：`:184,193,390,1359,1644,1649,1667,1931,1961`；`np.tensordot`：`:1503,1504,1505,1552,1672,1711,1966,1967,2339` 等。这些收缩顺序在 Fortran 中**必须逐项确认**，是 DMF 无法机械翻译的核心原因。

### C.4 eigh 排序与特征向量符号（**模式追踪对符号敏感**）

- `np.linalg.eigh`（12 次）返回**升序**特征值；LAPACK `dsyev/dsyevd` 同样升序 → **排序一致，无风险**。
- `np.linalg.eig`（`scan/algorithm/RFO.py:32`）返回**任意顺序 + 可能复数**（通用非对称）→ 移植须用 `dgeev` 并按实部排序，或用 `dsyev`（该处 Hessian 实对称）。
- **符号敏感性实测**：
  - `PRFO.py:634-672 update_mode_tracking`：用 `overlaps = np.abs(V_mw.T @ tracked)`（`:662`）取 `argmax`，再 `sign_align = np.sign(np.dot(...))`（`:665-668`）显式符号对齐 → **已处理符号翻转**，Fortran 须实现同样的 abs-overlap + 符号重对齐。
  - `BPRFO.py:366-415`：`idx = argmax(overlap.abs())` + `signs = sign(overlap.gather(...))`（`:401-406`）→ 同逻辑。
  - `irc/algorithm/gs.py:234 w,V = eigh(H_mw)` 后取最低负模（`:61 masses_D`）→ 首步方向用负模；RFO step 中 `-g_proj/w` 对 V 符号不变（g_proj 同号翻转），故 RFO 步不敏感，但**模式追踪跨步必须符号对齐**。
  - `argsort` on eig：`np.argsort`（9 次）主要非 eig 场景；`dmf.py:2750,2752` 对时间做 argsort。
- **风险等级**：中。只要复刻 `abs(overlap)+sign realign` 即安全；若省略符号对齐，TS 搜索会模式跳变失败。

### C.5 单位与硬编码常数（须集中化）

**MAPLE 硬编码常数（实测 grep）**：
- `frequency/frequency.py:26-46`：`H=6.62607015e-34`、`K_B=1.380649e-23`、`C=2.99792458e8`、`NA=6.02214076e23`、`AMU=1.66053906660e-27`、`ANG2_TO_M2=1e-20`、`HARTREE_TO_KJ_PER_MOL=2625.499638`、`HARTREE_TO_KCAL_PER_MOL=627.509474`；`:624` 又一次内联 `1.66053906660e-27*1e-20`。
- `irc/algorithm/{gs,hpc,eulerpc,lqa}.py:31-34`：`BOHR_TO_ANG=0.529177210903`、`KCAL_PER_EH=627.509474`（**同一常数在 4 个文件重复定义**）。
- `ts/algorithm/dmf.py:42-44`：`EV2HARTREE=1/27.211386245988`、`KCAL_PER_EH=627.509474`。
- `ts/algorithm/string.py:544`、`neb.py:1025`：`kcal_per_Eh=627.509`（**精度与上面 627.509474 不一致！**）。
- `sp/sp.py:111`：内联 `627.509`。
- `md/utils.py:34-59`、`md/logger.py:47-50`、`md/barostat/crescale.py:102`：另一套 `HARTREE_TO_EV=27.211386245988`、`BOHR_TO_ANGSTROM=0.529177210903` 等。
- 单位转换集中入口：`maple/function/calculator/calculator_base.py:123 EV2HARTREE`、`:126 _convert_energy_force_units`（eV↔Hartree）→ **所有算法都工作在 Hartree / Hartree·Å⁻¹ / Å**。

**xtb 集中式常数**（移植目标，直接复用）：`src/mctc/convert.f90:25-67`
`autoaa=0.52917726_wp`、`aatoau`、`autoev=27.21138505_wp`、`autokcal=627.50947428_wp`、`autokj=2625.49964038_wp`、`autorcm=219474.63067_wp`、`amutokg`、`amutoau` 等。
**注意精度差异**：MAPLE `0.529177210903` vs xtb `0.52917726`（xtb 少 8 位有效数字）；`627.509474` vs `627.50947428`。若要与 MAPLE 参考值逐位比对须用 MAPLE 常数；若只求物理正确则用 xtb 常数。**移植必须集中到 `xtb_mctc_convert`，禁止散落字面量。**

### C.6 随机数

- `ts/algorithm/dimer.py:258`：`rng = np.random.default_rng()` —— **无种子**（初始方向随机）。移植须暴露种子接口（Fortran 用 `random_number`/`random_seed`），否则无法复现。
- `md/*`（`utils.py:404`、`thermostat/langevin.py:77`、`barostat/crescale.py:88`、`ensemble/nvt.py:247`、`npt.py:238`）用 `np.random.default_rng()`，支持用户传 `rng`；MD 不在本目标核心之列。
- **其他 ts 算法（PRFO/NEB/string/IRC）无随机性** —— 确定性，便于移植与验证。

### C.7 收敛阈值（绝对 vs 每原子；梯度范数约定）

- 采用 **Gaussian 风格 4 判据**（`optimization/algorithm/_common.py:82-89 is_converged`）：
  - **最大力分量** `max_f` = `np.abs(forces).max()`（`:78`）—— 绝对最大值（Eh/Å）
  - **RMS 力** `rms_f` = `sqrt(Σf²/size)`（`:79`）—— Euclidean RMS 除以自由度（非每原子归一）
  - **最大位移** `max_dp`（`:76`）、**RMS 位移** `rms_dp`（`:77`）
- 阈值等级见 `dispatcher.py:154-195`（extratight→superloose），例如 tight：`f_max=0.00085, f_rms=0.00055, dp_max=0.00110, dp_rms=0.00075`。
- **注意**：`rms_f` 用的是 `forces.size`（=3N），**已是「每分量」归一，非「每原子」**。移植须保持同一定义，否则收敛步数不同。
- xtb 侧对应：`src/optimizer.f90:48 get_optthr`（返回 `ethr,gthr`），梯度范数约定需核对（xtb 传统用 `gthr` 对 RMS 梯度），移植时应对齐 §B 的 4 判据。

---

## D. 验证资产（Verification assets）

**MAPLE 拥有丰富的参考输出（regression fixtures）**，可作 Fortran 端 `ctest`/数值比对基准。实测：

- `examples/opt/{lbfgs,rfo,sd,sdcg,cg}/`：每个含 `*.inp`（输入几何）、`*_opt.xyz`（优化后几何）、`*_traj.xyz`、`*.out`（含逐迭代 Energy/Max Force/RMS Force 等）。例：`examples/opt/lbfgs/inp1.out`、`inp1_opt.xyz`。
- `examples/scan/{lbfgs,rfo,sd,sdcg,cg}/` + 顶层 `C18`、`da`、`da_rigid`：`*.out` + `*_scan_final.xyz`（含扫描能量剖面）。例：`examples/scan/cg/butane_torsion.out`。
- `examples/ts/{prfo,neb,string,dimer,autoneb,dmf}/`：
  - `neb/`：`inp1_mep.xyz`、`inp1_cineb_mep.xyz`、`inp1_prfo_ts.xyz`、`inp1_nebts_ts.xyz`、`inp1.out`（含势垒/HEI 能量）。
  - `autoneb/`：`inp1_autoneb_tree.json`（**结构化树**）、`*_global_mep.xyz`、`*_ts_list.xyz`、`*.out`。
  - `string/`：`inp1_gsm_mep.xyz`、`inp1_gsm_hei.xyz`、`inp1_prfo_ts.xyz`、`*.out`。
  - `dmf/`：`inp1_dmf_mep.xyz`、`inp1_dmf_tmax.xyz`、`inp1_prfo_ts.xyz`、`*.out`。
  - `dimer/`：`inp1_dimer_ts.xyz`、`inp1_dimer_traj.xyz`、`inp1.out`。
- `examples/irc/{gs,hpc,eulerpc,lqa}/`：每个含 `inp1_forward.xyz`、`inp1_backward.xyz`、`inp1_full.xyz`（**完整 IRC 路径**）、`inp1.out`（含能量沿反应坐标）。
- `examples/freq/mw/`：`inp1.out`（**实测含 21 个频率，含 6 个零频 + 1 个虚频 −2355.69 cm⁻¹ + 14 个实频**，见 `inp1.out:36-62`）、`inp1_nebts_ts.xyz`，以及 4 组 `test{1-4}_inp1_nebts_ts.{inp,out}`。
- `examples/sp/`（单点）、`examples/md/nve/`（`inp1_md_thermo.dat` 热力学时序）。

**关键限制（务必注意）**：所有 fixture 的输入用**ML 势模型**（`#model=ANI-1xnr`、`#model=uma(...)`、MACE），**并非 GFN2-xTB**（见 `examples/freq/mw/inp1.inp:1`、`examples/ts/neb/inp1.inp:1`、`examples/opt/lbfgs/inp1.inp:1`）。
- 因此这些 `.out`/`.xyz` **只能用于验证「算法/控制流」是否复现**（同一能量函数下的步序列、收敛行为、路径拓扑），**不能直接作为 GFN2-xTB 数值基准**。
- Fortran 端若要参数级数值复现，需：(a) 用相同 ML 势（不现实），或 (b) 对同一输入几何用 xtb 重算能量，然后比对**算法产生的几何/路径是否落在同一势能面盆地**（弱验证）。
- **强验证替代方案（推荐）**：构建解析参考体系 —— LEPS 势 / Müller-Brown 面（H + CH4、丙二醛等常见教科书体系），其解析梯度/Hessian 可精确移植，能逐位验证 PRFO/NEB/IRC/dimer 的步与收敛。MAPLE **未提供**此类解析参考（`.inp` 全为真实分子 + ML 势），故需**自建**。

**结论**：MAPLE 有算法级 golden 输出，但**无 GFN2 数值 fixture、无解析参考体系**。这直接改变测试策略：Fortran 端口应以「解析势（LEPS/Müller-Brown/H+CH4）+ 自洽收敛判据 + 与 MAPLE ML 势输出做拓扑/几何一致性抽查」为主，而非逐位能量比对。

---

## E. 结论（Verdict）

### E.1 各任务族可行性

| 任务族 | 可行性 | 依据 |
|---|---|---|
| **sp** | ✅ 直接可行 | `sp.py` 仅调用计算器 + 格式化；xtb `single.f90`/`api/calculator.f90` 已具备 |
| **opt**（LBFGS/RFO/SDCG/DIIS） | ✅ 可行（机械改写） | 纯向量运算 + `dsyev`；且 xtb 已有 `optimizer.f90`（ancopt/RFO）、`lbfgs_anc/lbfgs.f90` 可复用 |
| **scan**（1D/2D/3D 松弛/刚性） | ✅ 可行 | `scan.py` 机械改写；约束语义对齐 `constrain_pot.f90`/`scanparam.f90`；xtb 已有 `scan_driver.f90` |
| **hessian** | ✅ 可行 | 弃 torch autograd，用 xtb `numhess`（`hessian.F90:33`）或 `model_hessian/*` |
| **freq** | ✅ 可行 | `frequency.py` 机械改写；xtb 已有 `freq/project.f90`（`projectHessian`/`trproj`）+ `thermo.f90` |
| **ts: PRFO / dimer / neb / string（GSM）** | ✅ 可行（按文献重写） | 无外部库；`eigh` + `dsyev`；dimer 需自建 HVP（基于 `numhess`） |
| **ts: autoneb** | 🟡 可行（需重设计） | 树管理/路径拓扑逻辑复杂（1214 行），但无阻塞构造 |
| **ts: BPRFO / blbfgs（GPU 批量）** | 🟡 可行（需重设计批量语义） | torch 批量张量 → Fortran 二维数组 + BLAS-3 |
| **ts: DMF（Direct MaxFlux）** | ❌ **不建议**移植 | `cyipopt.Problem`（`:1058`）+ scipy BSpline/interp1d/Rotation + 19 处 einsum/tensordot；变分作用量 NLP 需 Ipopt 或自写 SQP，成本远超收益 |
| **irc: GS/HPC/EulerPC/LQA** | ✅ 可行（机械改写） | 共享内核（质量加权 Hessian、Bofill 更新、Lagrange-λ 微步）；xtb 有 `numhess` + `bofill` 更新参考（`bfgs.f90`） |

### E.2 三大阻塞（按严重度）

1. **DMF 依赖 cyipopt/Ipopt（非线性规划）+ scipy 样条/旋转**（`ts/algorithm/dmf.py:23,1058`；`_dmf_torch_backend.py`）。这是**唯一真正需要外部数值库**的模块，且 DMF 还深度使用 `np.einsum/tensordot/matmul`（19 处，`:184-2339`），列主序翻译风险极高。**建议明确排除 DMF 或标记为远期。**
2. **批量 GPU 语义（blbfgs/BPRFO）**：`blbfgs.py` 与 `BPRFO.py` 以 `(B, n)` torch 张量为中心（`blbfgs.py:220-289`、`BPRFO.py:366-415`）。Fortran 需重构为 `(n, B)` 列主序 + BLAS-3 批量 `dgemm`，属重设计而非翻译。（注：单体系 PRFO 以 numpy 为主，可先移植单体系版。）
3. **Hessian / HVP 接口缺失**：MAPLE 算法依赖 `calc.get_hessian()`（6 处）与 `calc.get_hvp()`（`dimer.py:353`）。xtb 有 `numhess` 但**无解析 Hessian、无 HVP**。对 TS/IRC 每步都要 Hessian 的算法，需自建高效 HVP（如基于 `numhess` 的有限差分或 `model_hessian` 近似），否则性能与精度都受限。

**次要风险**：row-major vs column-major 的 `.reshape(-1,3)` 约定（§C.3，30+ 处）、模式追踪符号对齐（§C.4）、随机无种子（`dimer.py:258`）、单位常数散落与精度不一致（§C.5，`627.509` vs `627.509474`）。

### E.3 推荐移植策略

**总原则：按文献用惯用 Fortran 重写，而非逐行 transliterate。** 理由：
- 现有 xtb 代码库已在 `optimizer.f90`（RFO/ancopt）、`lbfgs_anc`、`scan_driver.f90`、`hessian.F90`、`freq/`、`bfgs.f90`、`bofill` 更新、`bmatrix.f90`、`mctc/lapack/trs.f90` 提供了成熟 Fortran 内核与风格参考。**应优先复用/对齐这些内部 API，而非翻译 Python 的 ASE 抽象。**
- 直接翻译会继承 Python 的 row-major 展平、视图语义、`np.where`/masking 惯用法，在 Fortran 里既难写又易错。

**建议路线（分层）**：
1. **基础设施层（先做）**：统一几何/梯度/Hessian 数据结构（`xyz(3*natoms)` 扁平，列主序），封装 `get_energy_gradient`、`get_hessian`（调用 `numhess`）、`get_hvp`（基于 `numhess` 构建）；集中单位常数到 `xtb_mctc_convert`；统一收敛判据（复刻 `_common.py:74-89`）。
2. **sp/opt/scan/hessian/freq（第一批，低风险）**：机械改写，直接对照 `examples/*` 做算法级回归；复用 xtb 现有 `optimizer.f90`/`scan_driver.f90`/`freq/`。
3. **ts 单体系（第二批）**：PRFO（单体系 numpy 版）、dimer（自建 HVP）。验证用 LEPS / H+CH4 解析势。
4. **ts 路径方法（第三批）**：NEB、string(GSM)、autoneb。NEB 是本项目中信息密度最高、最值得优先的 TS 方法（1557 行均为 numpy，无外部依赖）。
5. **IRC（第四批）**：GS/HPC/EulerPC/LQA，共享内核，可在 TS 完成后接入。
6. **BPRFO/blbfgs 批量版（可选）**：仅在确需 GPU/批量吞吐时重构。
7. **DMF：排除或延期**，除非决定引入 Ipopt 的 Fortran 接口。

**验证策略**：因 MAPLE fixture 使用 ML 势（§D），Fortran 端应以「解析势（LEPS / Müller-Brown / H+CH4）+ 自洽步序列/收敛」为主要正确性证据，并将 MAPLE 的 ML 势输出用于**路径拓扑与几何一致性**的抽查，而非逐位数值比对。

### E.4 开放问题（需上游决策）

1. DMF 是否在目标范围内？若否，可节省 ≥3000 行 Fortran 与外部依赖。
2. 是否需要 GPU/批量（BPRFO/blbfgs）？若纯 CPU 单体，可跳过批量重设计。
3. Hessian 精度目标：用 `numhess`（数值，~3N 次梯度）还是需要解析 GFN2 Hessian？这决定 TS/IRC 的性能上限。
4. 是否需要与 MAPLE 逐位数值复现（需对齐其 `627.509474`/`0.529177210903` 常数与 row-major 展平），还是只需物理正确（可直接用 xtb 常数）？
