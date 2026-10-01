# MAPLE Dispatcher / Calculator 架构与算法清单（供 xtb Fortran 移植评估）

> 仓库：`/home/owenchan/work_path/coding/python/MAPLE`（只读侦察）
> 目的：为「用 Fortran 在 xtb (GFN2-xTB) 上实现 sp/opt/scan/ts/hessian/freq/irc」建立 MAPLE Python 调度器的完整对照基线。
> 所有证据均为 `path:line`。
> 版本：`pyproject.toml` name=maple version=0.1.4，`requires-python>=3.10`，依赖仅 `ase>=3.22, numpy>=1.20, scipy>=1.7`（torch 故意不声明，见 `pyproject.toml:9-14`）。

---

## 0. 总结论（先读这一段）

- MAPLE 是一个 **基于 ASE `Atoms` 的「单进程 + Python 对象状态机」调度器**。能量/力/二阶导全部通过挂载在 `Atoms.calc` 上的 calculator 对象提供。
- 关键抽象面非常小：calculator 只需实现 ASE 的 `calculate(atoms, properties=[...])`（能量/力），外加 **可选** 的 `get_hessian(atoms)` 和 `get_hvp(atoms, n)`（Dimer 用）。批量/torch 是 **少数后端额外提供** 的加速路径（`get_ef_gpu`/`get_efh_gpu`/`calc.coord`），并非所有 job 都强制。
- **算法层几乎全部是纯 numpy**（scipy 仅零星使用）。torch 只在三类地方出现：(a) calculator 后端的解析 Hessian（`hessian_via_double_autograd`，`calculator_base.py:238-260`）；(b) Dimer 的旋转/投影运行时；(c) opt 的 `blbfgs`/ts 的 `BPRFO` 批量 torch 版本（**dispatcher 未引用，属死代码**）；(d) DMF 的可选 torch 后端。
- **对 xtb 移植最关键的两个事实**：
  1. 所有 optimizer/IRC/TS 核心数学（L-BFGS 两循环、RFO/PRFO dual-shift、GDIIS、Gonzalez–Schlegel、HPC/EulerPC/LQA）都是 **可逐行翻译的纯 numpy**，没有隐藏的自动微分依赖。
  2. 但 **PRFO / RFO / Dimer / IRC-* / freq 都要求 `get_hessian`**；IRC 与 PRFO 会周期性完整重算 Hessian。xtb 的 GFN2 解析 Hessian（若有）或数值 Hessian 是移植的硬约束。
- 测试覆盖：**仓库内没有任何 pytest/单元测试，也没有 CI**（`find . -iname '*test*'` 只返回 `examples/freq/mw/test*.inp` 这类示例输入）。数值卫生需在 Fortran 侧从零建立。

---

## 1. 入口链（entry chain）

```
maple/main.py                      # CLI argparse，解析 input_file/output_file 与 --test
  └─ maple.function.engine.engine   # 读输入 → 初始化 calculator → 挂到 atoms.calc → 派发
       ├─ InputReader               # 解析 #task / #model / 坐标 → self.jobtype, self.commandcontrol
       │    └─ CommandControl       # 参数校验 + 默认值（read/command_control.py）
       ├─ SetCalculator             # calculator/set_calculator.py，按 model 名字实例化后端
       └─ Dispatcher                # dispatcher/dispatcher.py，按 jobtype 字符串创建 job 类
            └─ <Job> (JobABC)       # 各 job family 的 run()
```

### 1.1 `maple/main.py`
- CLI 双模式：`maple md nve|nvt|npt`（生成 mdp 模板，`main.py:34-64`）与普通计算模式（`main.py:66-128`）。
- `--test (1..8)` 内建映射：`1=LBFGS opt, 2=NEB, 3=String, 4=Dimer, 5=RFO, 6=IRC GS, 7=Freq MW, 8=Scan`（`main.py:88-102`）。
- 最终 `engine()(input_file, output_file)`（`main.py:130`）。

### 1.2 `maple/function/engine.py`
- `engine.__call__`（`engine.py:60-102`）串联三步：`_input_reader` → `_mlp_initiator` → `_jobtype_dispatcher`。
- `_input_reader`（`engine.py:104-159`）建立 `self.atoms / self.jobtype / self.commandcontrol / self.extra`；`extra={'scan': ...}` 或 `extra={'parmfit': {...}}`（`engine.py:126-131`）。
- `_mlp_initiator`（`engine.py:161-189`）读 `#solv` 的 implicit/explicit，构造 `SetClaculator`，`self.calulator = setcalculator.set_calculator()`。
- 挂载：`Atoms.calc = calulator`；对 `Molecules` 则 `for atom in self.atoms.multiatoms: atom.calc = calulator`（`engine.py:79-88`）。
- `_jobtype_dispatcher`（`engine.py:191-206`）只是 `Dispatcher()(commandcontrol, jobtype, atoms, output, extra)`。

### 1.3 `maple/function/dispatcher/dispatcher.py`（全文 240 行）
`Dispatcher.__call__(commandcontrol, jobtype, atoms, output, extra=None)`，jobtype 是 **字符串**（不是 int，尽管注释写 int）。

派发表（`dispatcher.py:27-143`）：

| jobtype 字符串 | 触发分支 | 实例化 | 附加参数 |
|---|---|---|---|
| `'opt'` | :27 | `optimization.Optimization(output, atoms, params)` | 只允许单个 Atoms |
| `'sp'` | :35 | `sp.SinglePoint(output, atoms, paras)` | 支持 `Molecules`/list（轨迹） |
| `'scan'` | :53 | `scan.Scan(output, atoms, method, constraints=extra['scan'], params)` | 必须 `extra['scan']` |
| `'freq'` | :68 | `frequency.Frequency(output, atoms, paras)` | 单结构 |
| `'ts'` | :75 | `ts.TransitionState(output, atoms, method, params)` | method ∈ neb/string/autoneb/dmf 允许 Molecules |
| `'irc'` | :96 | `irc.IRC(output, atoms, method, params)` | 单结构 |
| `'md'` | :103 | `md.ensemble.{nve,nvt,npt}.{NVE,NVT,NPT}` | 需 `atoms.info` 有 charge/mult |
| `'parmfit'` | :128 | `parmfit.Parmfit(...)` | 单结构 |
| 其他 | :139 | `NotImplementedError` → `log_error` | — |

关键代码（`dispatcher.py:27-52`）：
```python
27  if jobtype == 'opt':
28      from .optimization import Optimization
31          raise NotImplementedError('For optimization job, only one Atoms object is allowed.')
32      opt = Optimization(output=output, atoms=atoms, params=commandcontrol.params)
33      opt.run()
35  elif jobtype == 'sp':
36      from .sp import SinglePoint
38      sp_params = commandcontrol.params if hasattr(commandcontrol, "params") else commandcontrol
41      if isinstance(atoms, Molecules):
42          atoms_input = atoms.multiatoms
43          sp = SinglePoint(output=output, atoms=atoms_input, paras=sp_params)
...
```

`set_throshould`（`dispatcher.py:145-217`）把 Gaussian 风格收敛等级写入 `atoms.{f_max_th,f_rms_th,dp_max_th,dp_rms_th}`：

| level | f_max_th | f_rms_th | dp_max_th | dp_rms_th |
|---|---|---|---|---|
| extratight | 0.00030 | 0.00020 | 0.00030 | 0.00020 |
| tight | 0.00085 | 0.00055 | 0.00110 | 0.00075 |
| medium（默认 fallback） | 0.00285 | 0.00190 | 0.00315 | 0.00210 |
| loose | 0.00380 | 0.00250 | 0.00600 | 0.00400 |
| extraloose | 0.00755 | 0.00500 | 0.01200 | 0.00800 |
| superloose | 0.08500 | 0.05500 | 0.14500 | 0.09500 |

### 1.4 jobtype 来源与合法集合
- `InputReader` 从 `params.get("task")` 取 `self.jobtype`（`read/input_reader.py:375`）。
- 合法 task 集合由 `CommandControl.SUPPORTED_TASKS = {"sp","opt","ts","scan","freq","irc","md","parmfit"}`（`read/command_control.py:34`）决定。
- **没有 `hessian` 这个 task**；`SUPPORTED_HESSIAN_MODES={"analytic","numerical"}`（`command_control.py:40`）只是模型选项。
- method 合法集合 `IMPLEMENTATION_MAP`（`command_control.py:95-104`）：
  - opt: `{lbfgs, rfo, sd, cg, sdcg, ""}`
  - scan: `{lbfgs, rfo, sd, cg, sdcg}`
  - ts: `{prfo, string, neb, dimer, autoneb, dmf}`
  - freq: `{mw, nonmw, both}`
  - irc: `{gs, hpc, eulerpc, lqa}`
  - md: `{nve, nvt, npt}`
  - parmfit: `{abinitio, correction}`

### 1.5 `JobABC`（`dispatcher/jobABC.py`，81 行）
所有 job 的基类（`sp` 除外：`SinglePoint` 继承 `JobABC`，是；`optimization` 也是）。
- `run()` 抽象方法（`jobABC.py:12-14`）。
- 参数注入工具：`_lower_keys` / `_select_subdict` / `_update_dataclass_from_dict` / `_init_params(params_class, paras, aliases)`（`jobABC.py:20-57`）—— **把 dict 按大小写不敏感键映射到 dataclass**，是 Fortran settings 类型要复刻的语义。
- `log_error` / `log_info` 追加写 output 文件（`jobABC.py:63-82`）。

---

## 2. 各 job family 一览（模块 | 文件 | LOC | 入口 | 算法 | 引文 | 外部依赖 | 可调参数默认值）

### 2.1 sp
| 项 | 值 |
|---|---|
| module | `dispatcher/sp/sp.py` |
| LOC | 112 |
| 入口 | `SinglePoint(JobABC).run()`；`SPParams(verbose=0)` |
| 算法 | 单点能量；trajectory 逐帧 `get_potential_energy()`；verbose≥1 打印 `-forces` 梯度 |
| 引文 | 无 |
| 依赖 | ase, timer |
| 参数 | `verbose: int = 0` |
| 要点 | 单位 Hartree；`_run_trajectory` 统计能量范围/span kcal/mol（`sp.py:107-111`） |

### 2.2 optimization
| 项 | 值 |
|---|---|
| module | `dispatcher/optimization/optimization.py` |
| LOC | 37 |
| 入口 | `Optimization.run()` → method 分派到 `LBFGS / RFO / SDCG` |
| 算法 | method 映射见 `optimization.py:17-33`：`lbfgs→LBFGS`, `rfo→RFO`, `{sd,sdcg,cg}→SDCG` |
| 依赖 | ase |
| 参数 | 见各 algorithm 的 dataclass |

### 2.3 scan
| 项 | 值 |
|---|---|
| module | `dispatcher/scan/scan.py` |
| LOC | 491 |
| 入口 | `Scan(JobABC).run()` → `run_scan()` |
| 算法 | N 维（1D/2D/3D）分层连续扫描。`mode=relaxed` 每点调用 `Optimization`（内层 optimizer）；`mode=rigid` 用刚体移动 `set_distance/set_angle/set_dihedral`。约束用 ASE `FixInternals`。 |
| 引文 | 无正式引文；注释说明分层策略（`scan.py:14-17`） |
| 依赖 | ase (`FixInternals`, `NeighborList`, `natural_cutoffs`), numpy 间接 |
| 参数 | `method`（默认 "lbfgs"）、`mode`（默认 "relaxed"，可选 "rigid"）；约束定义 `[a1,a2,step,steps]`/`[a1,a2,a3,...]`/`[a1..a4,...]`（`scan.py:45-75`） |
| 要点 | 输出流式写 `<base>_scan_final.xyz`（或 `.pdb`）；内层 opt 关闭日志 `verbose=0, log_final_paths=False`（`scan.py:191-195`） |
| legacy | `scan/algorithm/{LBFGS,RFO,logger}.py` 未被 `scan.py` 引用（scan 实际调用 optimization），属旧代码（见 §3.2） |

### 2.4 ts
| 项 | 值 |
|---|---|
| module | `dispatcher/ts/ts.py` |
| LOC | 140 |
| 入口 | `TransitionState.run()`，method 分派（`ts.py:20-140`） |
| 依赖 | torch (`from torch import Tensor`, 仅类型导入，`ts.py:4`), ase |
| 参数 | method ∈ prfo/neb/string/dimer/autoneb/dmf；`dmf` 需 `cyipopt`（`ts.py:114-120`，ImportError 提示 conda 安装） |

### 2.5 frequency
| 项 | 值 |
|---|---|
| module | `dispatcher/frequency/frequency.py` |
| LOC | 1306 |
| 入口 | `Frequency(...).run()`（driver，`frequency.py:1234-1305`）→ `MWFrequency / NonMWFrequency / BothFrequency`（均继承 `FrequencyBase`） |
| 算法 | Hessian 对角化 → 频率；投影平动/转动；RRHO + 低频校正热化学 |
| 引文 | Truhlar 低频熵、Grimme 熵、Head-Gordon 自由转子（内联于 `_truhlar_entropy`/`_grimme_entropy`/`_headgordon_weight`/`_free_rotor_entropy`，`frequency.py:516-630`） |
| 依赖 | numpy；**可选 torch**（`_eigh` CUDA 加速，`frequency.py:20-26, 292-303`）；ase |
| 参数 | `FrequencyParams(method="mw", temperature=298.15, ilowfreq=2, verbose=1, treat_imag_as_real=False, pressure_kpa=101.325, device="cpu")`；`PrintParams(n_freqs_to_print=10, sort_ascending=True, imag_tol_cm1=10.0)`；基底默认 `omega0_cm1=100.0, nu_floor_cm1=1.0, symmetry_number=1`（`frequency.py:101-120, 183-195`） |
| 常量 | `ilowfreq`: 0=harmonic, 1=Truhlar, 2=Grimme, 3=Head-Gordon free-rotor（`frequency.py:469-480`） |
| 单位 | Hessian 期望 **Hartree/Å²**；MW 转换因子 `2721.1383`（`frequency.py:1019`），非 MW 同样 `2721.1383`（`frequency.py:1206`） |
| 要点 | `get_hessian` 要求 `calc.get_hessian`，接受 `(1,3N,3N)` 并 squeeze；否则 RuntimeError（`frequency.py:305-343`） |

### 2.6 hessian
| 项 | 值 |
|---|---|
| module | `dispatcher/hessian/hessian.py`，`__init__.py` 空 |
| LOC | 39 |
| 入口 | **无类、无 job**。只有一个函数 `hessian(coordinates, energies=None, forces=None)`（`hessian.py:11`） |
| 算法 | 通过 torch autograd 由能量图或力图对坐标做二阶导，返回 `(molecules,3A,3A)` |
| 依赖 | **torch**（`hessian.py:1-2`） |
| 要点 | `grep` 全仓库 **无任何模块 import 它**（孤立工具函数）。MAPLE 里「Hessian job」实际由 calculator 的 `get_hessian` 提供，由 freq/PRFO/IRC 调用。 |

### 2.7 irc
| 项 | 值 |
|---|---|
| module | `dispatcher/irc/irc.py` |
| LOC | 34 |
| 入口 | `IRC.run()` 分派 gs/hpc/eulerpc/lqa（`irc.py:15-34`） |
| 依赖 | ase；算法内部仅 numpy（torch 仅 `to_f64` 兼容读取，非必需） |
| 参数 | 见 §4 |

### 2.8 md
| 项 | 值 |
|---|---|
| module | `dispatcher/md/`（`__init__.py` 67 行 + ensemble/thermostat/barostat/integrator/logger/mdp_reader/rst_io/dcd_writer） |
| LOC | 合计 ~6000（含 logger 1117、utils 851） |
| 入口 | `NVE/NVT/NPT(JobABC).run()` |
| 算法 | Velocity-Verlet（a.u.）；thermostat: Langevin (BAOAB/OU) / V-rescale (Bussi 2007)；barostat: Berendsen / C-rescale (Bernetti-Bussi 2020) |
| 引文 | 大量内联引文（`nve.py:45-54` 等） |
| 依赖 | numpy；ase（PBC cell）；**无 torch** |
| 参数 | 见 §4.5；默认 timestep=0.1 fs, steps=100000, temperature=300 K, NPT pressure=1 bar, `tau_t=100`(NVT)/`200`(NPT), `tau_p=2000`, `compressibility=4.5e-5` |

### 2.9 parmfit
| 项 | 值 |
|---|---|
| module | `dispatcher/parmfit/`（~40 文件，最大子模块） |
| LOC | 数千 |
| 入口 | `Parmfit.run()` → method `abinitio` → `Abinitio.run()`；method `correction` → `Correction.run()`（`parmfit.py:28-46`） |
| 算法 | MM 力场参数拟合：MetalAA / NCAA / TorsionFit / RESP / Seminario / chargefit / mechanics 等 |
| 依赖 | numpy, scipy, ASE；调用 Gaussian/ORCA 外部 QM（`utils/QMInterface/{gaussian,orca}.py`）；内部 Scan 引擎（`utils/Scan/`） |
| 参数 | `CorrectionConfig`（`correction/config.py`）、`utils/Scan/models.py`、`utils/TorsionFit/config.py` 等 |
| 要点 | 与 xtb 移植 **基本无关**，仅需在矩阵中标注「存在但非移植目标」 |

---

## 3. 算法文件深度分析（移植最重要）

### 3.1 optimization/algorithm

#### `_common.py`（89 行）— 共享工具
- `write_xyz`（`.info["pdb_template"]` 时走 PDB）、`to_numpy_f64`（兼容 torch detach）、`vec1d`。
- `compute_metrics(atoms, step_cart, forces)`：设置 `atoms.max_dp/rms_dp/max_f/rms_f`（`_common.py:74-79`）。
- `is_converged(atoms)`：**四判据与**（`_common.py:82-89`）：
  `max_f≤f_max_th AND rms_f≤f_rms_th AND max_dp≤dp_max_th AND rms_dp≤dp_rms_th`。

#### `LBFGS.py`（`optimization/algorithm/LBFGS.py`，219 行）
- 坐标系：**笛卡尔**。
- 算法：经典 **L-BFGS 两循环递归**（`_two_loop`，:61-84），动态 H0 `gamma = y·s / y·y`，否则 `1/curvature`。
- Hessian 更新：隐式（L-BFGS 历史 S/Y/rho），更新时若 `curvature = y·s ≤ 1e-12` 丢弃（:92-102）。**不需要显式 Hessian**。
- 步控：`_clip_step`，`max_step=0.2`（:86-90）。
- 收敛：`is_converged`（沿用 atoms 阈值）。
- 默认参数：`memory=5, curvature=70.0, max_step=0.2, max_iter=256, verbose=1, log_final_paths=True`（:16-23）。
- torch：不依赖（torch 仅在 `_common.to_numpy_f64` 里兼容分支）。

#### `RFO.py`（`optimization/algorithm/RFO.py`，389 行）— 最小化用 RFO
- 坐标系：**mass-weighted**（`D = 1/sqrt(m)`，`_mass_weight` :203-211），步在 MW 空间，再转回 Cart。
- Hessian：**需要完整 Cartesian Hessian**，每步 `atoms.calc.get_hessian`（`_calculate_hessian` :193-201）。**无 Hessian 更新**（每步重算）。
- 步控：**single-shift RFO + trust region**（`_rfo_step_mw` :213-293）：eigendecomp，无约束步在半径内直接用；否则 bisection 求 shift μ<min(w)，步 clamp 到 trust_radius。
- trust-radius 逻辑（`_accept_or_reject` :295-304）：`rho<eta_shrink` 且未到最小半径 → reject + 半径×0.5；accept 且 `rho>eta_expand` 且在边界 → 半径×2。
- 收敛：`is_converged`（atoms 阈值）。
- 默认参数：`max_iter=256, trust_radius_init=0.2, trust_radius_min=1e-3, trust_radius_max=1.0, eta_shrink=0.75, eta_expand=1.75, evals_eps=1e-10, mu_margin=1e-8, max_bisect_it=60, verbose=1, log_final_paths=True`（:22-41）。
- torch：不依赖。

#### `DIIS.py`（`optimization/algorithm/DIIS.py`，218 行）— GDIIS 加速器
- `DIISParams(memory=6, min_vectors=3, regularization=1e-10)`（:20-25）。
- `DIISAccelerator`：误差向量=forces；corrected coord `x_i + step_scale*f_i`；B 矩阵 + Tikhonov 正则，增广 `[B,-1;-1,0]`，`np.linalg.lstsq`（:70-127）。引文：Csaszar & Pulay 1984；Farkas & Schlegel PCCP 2002（:40-42）。
- `DIIS()` 旧函数已 deprecated（:160-218），用 `SD`/`SDCG` 的 `diis_enabled`。
- torch：不依赖。

#### `SDCG.py`（`optimization/algorithm/SDCG.py`，557 行）— SD+CG 融合
- 坐标系：笛卡尔。
- 算法：Phase1 **Steepest Descent**（`step = max_step*forces`）；Phase2 **PRP+ 共轭梯度**（`beta=max(f_k·(f_k-f_{k-1})/||f_{k-1}||²,0)`，Powell restart），带 **GDIIS**。引文：Polak-Ribiere 1969；Powell 1977；Csaszar-Pulay 1984；Farkas-Schlegel 2002（:16-20）。
- 相切换：`max_f < cg_switch_fmax` 或 `sd_iter≥sd_max_iter`（:459-468）。GDIIS 每 `diis_store_every` 步存快照（:288-341），用 Barzilai-Borwein 估 step_scale（:269-286）。
- Hessian：**不需要**（只用 forces）。
- 默认参数：`max_step=0.2, max_iter=256, verbose=1, sd_enabled=True, cg_enabled=True, sd_max_iter=50, cg_switch_fmax=0.0(auto=0.5·初始max_f), cg_restart_threshold=0.2, cg_beta_method="prp+", diis_enabled=True, diis_store_every=5, diis_min_snapshots=3, diis_memory=6, log_final_paths=True`（:34-57）。
- `SD.py`（11 行）是 `SDCG` 的向后兼容别名（`SD=SDCG`，:1-11）。
- torch：不依赖。

#### `blbfgs.py`（`optimization/algorithm/blbfgs.py`，535 行）— **批量 GPU L-BFGS（死代码）**
- `BatchLBFGS`：torch 张量批量优化，动态收缩 batch，padded `nmax`，逐 batch L-BFGS 历史。**需要 calculator 提供 `get_ef_gpu()` 与 `calc.coord/coord32`，并实现 `prepare/step_cart_/backup_coords`**（:37-42, 97-216）。
- **dispatcher/optimization 未引用它**（全仓库无 import）。仅 `aimnet/_aimnet2_batch_calculator.py` 注释提到。
- torch：**强依赖**（`DTYPE=torch.float64`）。

### 3.2 scan/algorithm（legacy，未被 scan.py 调用）
| 文件 | 内容 | 说明 |
|---|---|---|
| `LBFGS.py` (176) | 独立函数式 L-BFGS，默认 `memory=5, curvature=70.0, maxstep=0.2, maxiteration=128`（:27-35） | 与 optimization LBFGS 逻辑近似但独立版本 |
| `RFO.py` (185) | 函数式 RFO，用 `scipy.optimize.brentq` 求 shift；`max_step_size=0.1, max_iter=256`（:15-19）；内部使用 `torch.eye`（:46） | 旧/混合 torch-numpy，且 `scan.py` 实际走 `Optimization` |
| `logger.py` (21) | `log_info/log_error` | — |

> 结论：**scan 的真正的每点优化来自 `optimization` 家族**；`scan/algorithm/*` 可视为可忽略的历史残留。

### 3.3 ts/algorithm

#### `PRFO.py`（`ts/algorithm/PRFO.py`，892 行）— **RS-PRFO（核心）**
- 坐标系：步计算在 **mass-weighted**，几何更新在 **Cartesian**（:466-471）。
- Hessian：**需要完整 Cartesian Hessian**，按 `recalc` 间隔重算（默认每 1 步）；其余步用 **Bofill（默认）/ BFGS** 更新（`_bofill_update` :385-429，`_bfgs_update` :370-383）。
- 步控：**dual-shift RS-PRFO**（`prfo_step` :140-351）：把 Hessian 特征空间分成 uphill（目标模，σ=-1）与 downhill（σ=+1），trust 半径按 `alpha∈[0.05,0.95]` 在两子空间分配，各自 bisection 求 μ；uphill 模 = 最负特征值（或 |gp| 最大者）。
- trust 逻辑：`rho<eta_shrink` 且半径>min → reject + ×0.5（最多 `max_attempts=8` 重试）；`rho>eta_expand` 且在边界 → ×2（:820-834）。
- 收敛：4 判据（`check_convergence` :505-521）。
- 默认参数（`PRFOParams` :431-459）：`max_iter=256, trust_radius=0.2, trust_min=1e-3, trust_max=1.0, eta_shrink=0.75, eta_expand=1.75, evals_eps=1e-10, mu_margin=1e-8, max_bisect_it=60, recalc=1, hessian_update="bofill", f_max_th=9.5e-3, f_rms_th=5e-3, dp_max_th=1.8e-3, dp_rms_th=1.2e-3`。
- torch：不依赖（`to_numpy_f64` 兼容 torch，但无 torch 调用）。

#### `BPRFO.py`（`ts/algorithm/BPRFO.py`，944 行）— **批量 torch RS-PRFO（死代码）**
- `BatchPRFO`，torch 批量，padded `nmax`，参数走 `__init__` 而非 dataclass：`trust_init=0.20, trust_min=1e-3, trust_max=1.00, hessian_update="bofill"`（:57-80）。
- 需 calculator 的 `get_efh_gpu`/`prepare`/`coord`。
- **未被 `ts/algorithm/__init__.py` 导出**（只导出 PRFO/NEB/GSM/Dimer/AutoNEB），无引用。torch 强依赖。

#### `dimer.py`（`ts/algorithm/dimer.py`，537 行）
- 坐标系：Cartesian；可选 mass metric（`use_mass_weight=False` 默认），可选移除刚体分量（`remove_rigid=True`）。
- Hessian：**不重算完整 Hessian**；用 **Hessian-vector product** `H·n`，两种来源：`use_hvp=True` 调 `calc.get_hvp`（默认 False）或有限差分（`delta=0.005`）（`_finite_diff_Hn_and_F` :268-289 / `_hvp_Hn_and_F` :291-302）。
- 算法：Dimer 旋转最小化最大曲率 + 沿 n 平移，`kappa_to_flip` 翻转平行分量。
- 默认参数（`DimerParams` :105-139）：`use_hvp=False, delta=0.005, rot_max_iter=5, rot_alpha=0.5, rot_f_max_th=1.0e-3, rot_f_rms_th=5.0e-4, step0=0.2, step_max=0.15, trust_radius=0.15, f_max_th=5.0e-3, f_rms_th=1.0e-3, kappa_to_flip=0.0, max_iter=200, use_mass_weight=False, remove_rigid=True, n_init="random", save_traj=True, save_metrics=True`。
- torch：**运行时使用 torch**（`:14, 358, 403-456` 用 torch tensor 做旋转/投影/HVP），即使有限差分路径也会构造 tensor。**移植需剥离或保留等价的纯 numpy 实现**。

#### `neb.py`（`ts/algorithm/neb.py`，1540 行）
- 坐标系：Cartesian（含 Kabsch 对齐、IDPP 插值）。
- 算法：NEB with improved tangent + 弹簧；**ORCA 风格动态弹簧常数** `k_i=k_max-(k_max-k_min)·exp(-decay·ΔE_i/ΔE_max)`（`compute_dynamic_k` :214-281）。L-BFGS 在投影 NEB 力上优化（`LBFGSDriver` :478-560）。
- CI-NEB：`cineb_tangent`（Henkelman-Jonsson 风格 upwinding，:318-370），`cineb_forces`（:789-855），climbing image 索引可冻结，dual convergence `ci_should_stop`（:520）。
- Hessian：**不需要**（只用能量+力）。
- 参数（`NEBParams` :191-211）：`n_images=10, k_min=0.03, k_max=0.3, use_dynamic_k=True, k_decay=0.5, max_iter=500, lbfgs_m=20, step0=2e-2, ifidpp=1, neb_f_max_th=9.5e-3, neb_f_rms_th=5e-3, initial_opt=False, refine=None('cineb'|'nebts'), cineb_f_max_th=1e-2, cineb_f_rms_th=1e-2, cilbfgs_m=20, cistep0=5e-3`；`IDPPParams(max_steps=300, step_size=0.01, r_cut=12.0, eps=1e-8, w_power=2.0)`（:147-153）。
- torch：**不需要**（`to_numpy_f64` 兼容读取）。scipy 未用（仅 numpy）。
- 出口 `restart_run` 可接 PRFO（`refine='nebts'`）。

#### `autoneb.py`（`ts/algorithm/autoneb.py`，1214 行）
- 在 NEB 之上做 **自动化多步路径探索**：自适应插点、局部极小检测与路径分裂、端点优化、二叉树管理。
- 复用 `neb` 的 `NEB/NEBParams/LBFGSDriver/neb_forces/compute_dynamic_k`（:22-27）。
- 参数（`AutoNEBParams` :36-50）：`n_images=20, k_min=0.03, k_max=0.3, use_dynamic_k=True, k_decay=0.5, max_iter=256, lbfgs_m=10, step0=2e-2, ifidpp=1, ang_max=0.3, ang_iter=20, path_iter=50, min_e_drop=0.001, ep_iter=30, ep_e_drop=0.0005, autoneb_f_max_th=9.5e-3, autoneb_f_rms_th=5e-3, max_depth=5, max_paths=10, do_final_refine=True, final_refine_factor=2.0, final_refine_max_iter=200, final_refine_ep_iter=20, verbose=1`；`PathNode` 存 L-BFGS 历史。
- Hessian：不需要。torch：不需要。

#### `string.py`（`ts/algorithm/string.py`，954 行）— GSM（Growing String Method）
- 坐标系：Cartesian；能量加权切线；两端自适应生长 + τ-正交子空间受限 mini-relax（LBFGS）+ 投影 L-BFGS 全路径弛豫。
- 参数（`GSMParams` :292-337）：`grow_step=0.12, grow_step_min=0.02, grow_backtrack=0.5, grow_relax_iters=10, grow_relax_tol=2.5e-3, grow_energy_tol=1.0e-3, pause_imbalance=2, refine_end_every=3, merge_threshold=0.5, n_images=9, max_iter_relax=300, string_f_max_th=5.0e-3, string_f_rms_th=1.0e-3, lbfgs_memory=7, lbfgs_curvature=70.0, lbfgs_max_step=0.2, reparam_every=3, refine=None('cistring'|'stringts'), cistring_f_max_th=4.0e-3, cistring_f_rms_th=2.0e-3, max_iter_grow=100, log_every=1, guide_conn_min=0.3, guide_d_switch=4.0, guide_inc_trigger=2`。
- Hessian：不需要。torch：不需要。`restart_run` 可接 PRFO（:527）。

#### `dmf.py`（`ts/algorithm/dmf.py`，2767 行）— Direct MaxFlux
- 坐标系：Cartesian；B-spline 路径参数化；**cyipopt** 求解变分目标 `Itilde=(1/beta)ln∫|xdot|exp(beta·E)dt`（:1-14）。
- 后端：`backend="numpy"`（默认）或 `"torch"`（`_dmf_torch_backend.py`，需要 vendored torch 包）。
- 参数（`DMFParams` :636-659）：`backend="numpy", beta=10.0, nmove=10, nsegs=6, dspl=3, update_teval=False, init_path="fbenm", fbenm_correlated=True, ipopt_out=False, mass_weighted=False, remove_rotation_and_translation=True, tol="tight", max_iter=200, refine=None('prfo'|'dimer')`。
- 依赖：`cyipopt`（必需，`dmf.py:23`），scipy（BSpline/interp1d/Rotation），ase。
- Hessian：不需要（目标只含能量）。可 `refine` 接 PRFO/Dimer。

#### `logger.py`（`ts/algorithm/logger.py`，21 行）
- `log_info/log_error` 追加写文件。

### 3.4 irc/algorithm

四个 IRC 积分器共享骨架：**mass-weighted coordinates + Hessian**，从 TS 几何沿最负模（`target_mode`）正/反向积分，路径合并（低能端 set dE=0，能量最高点标为 TS）。单位：`BOHR_TO_ANG=0.529177210903`，`KCAL_PER_EH=627.509474`（各文件 :33-34）。

| 文件 | LOC | 算法 | Hessian 需求 | 默认参数 |
|---|---|---|---|---|
| `gs.py` | 768 | **Gonzalez–Schlegel**：pivot step + 球约束优化，micro-cycle 用 Lagrange 乘子 λ 强制 `|p|²=(step/2)²` | 需完整 Hessian；可周期重算（`hessian_recalc`），否则 BFGS/Bofill 更新 | `target_mode=1, step_length_bohr=0.10, max_steps=50, max_micro_cycles=20, micro_step_thresh=1e-3, hessian_recalc=None, hessian_update="bofill", f_max_th=2e-3, f_rms_th=5e-4`（`gs.py:112-139`） |
| `hpc.py` | 919 | **Hessian-based Predictor-Corrector**：LQA 预测 + **DWI 面拟合 + mBS (modified Bulirsch–Stoer) 校正** | 同上 | `target_mode=1, step_length_bohr=0.10, max_steps=50, euler_n=5000, hessian_recalc=None, hessian_update="bofill", dwi_n=4, mbs_max_k=15, mbs_points=20, mbs_tol=1e-5, f_max_th=2e-3, f_rms_th=5e-4`（`hpc.py:195-227`） |
| `eulerpc.py` | 964 | **Euler-based Predictor-Corrector**：Euler 预测（Hessian 梯度模型）+ DWI/mBS 校正 | 同上 | `target_mode=1, step_length_bohr=0.10, max_steps=50, max_pred_steps=500, loose_cycles=3, hessian_recalc=None, hessian_update="bofill", dwi_n=4, mbs_max_k=15, mbs_points=20, mbs_tol=1e-5, f_max_th=2e-3, f_rms_th=5e-4`（`eulerpc.py:195-228`） |
| `lqa.py` | 722 | **Local Quadratic Approximation**：单步 LQA 传播 | 同上 | `target_mode=1, step_length_bohr=0.10, max_steps=50, euler_n=5000, hessian_recalc=None, hessian_update="bofill", f_max_th=2e-3, f_rms_th=5e-4`（`lqa.py:110-136`） |

- 共同点：`_get_hessian_cart()` 调 `atoms.calc.get_hessian(atoms)`（如 `gs.py:304-311, 450, 541`）。
- 收敛：Cartesian 力阈值 `f_max_th=2e-3, f_rms_th=5e-4`。
- torch：`to_f64` 仅兼容读取 torch tensor（`gs.py:40-43`），核心为 numpy。**移植无 torch 阻塞**。
- `logger.py`（21 行）：`log_info/log_error`。

---

## 4. 参数 dataclass 全清单（Fortran settings-type 规格）

`grep @dataclass`（排除 parmfit）命中：

| 文件:行 | dataclass | 字段与默认值 |
|---|---|---|
| `sp/sp.py:9` | `SPParams` | `verbose=0` |
| `optimization/algorithm/LBFGS.py:16` | `LBFGSParams` | `memory=5, curvature=70.0, max_step=0.2, max_iter=256, verbose=1, log_final_paths=True` |
| `optimization/algorithm/RFO.py:22` | `RFOParams` | `max_iter=256, trust_radius_init=0.2, trust_radius_min=1e-3, trust_radius_max=1.0, eta_shrink=0.75, eta_expand=1.75, evals_eps=1e-10, mu_margin=1e-8, max_bisect_it=60, verbose=1, log_final_paths=True` |
| `optimization/algorithm/DIIS.py:20` | `DIISParams` | `memory=6, min_vectors=3, regularization=1e-10` |
| `optimization/algorithm/SDCG.py:34` | `SDCGParams` | `max_step=0.2, max_iter=256, verbose=1, sd_enabled=True, cg_enabled=True, sd_max_iter=50, cg_switch_fmax=0.0, cg_restart_threshold=0.2, cg_beta_method="prp+", diis_enabled=True, diis_store_every=5, diis_min_snapshots=3, diis_memory=6, log_final_paths=True` |
| `scan/algorithm/*` | 无 dataclass | 函数默认参数（见 §3.2） |
| `ts/algorithm/PRFO.py:431` | `PRFOParams` | `max_iter=256, trust_radius=0.2, trust_min=1e-3, trust_max=1.0, eta_shrink=0.75, eta_expand=1.75, evals_eps=1e-10, mu_margin=1e-8, max_bisect_it=60, recalc=1, hessian_update="bofill", f_max_th=9.5e-3, f_rms_th=5e-3, dp_max_th=1.8e-3, dp_rms_th=1.2e-3` |
| `ts/algorithm/dimer.py:105` | `DimerParams` | `use_hvp=False, delta=0.005, rot_max_iter=5, rot_alpha=0.5, rot_f_max_th=1.0e-3, rot_f_rms_th=5.0e-4, step0=0.2, step_max=0.15, trust_radius=0.15, f_max_th=5.0e-3, f_rms_th=1.0e-3, kappa_to_flip=0.0, max_iter=200, use_mass_weight=False, remove_rigid=True, n_init="random", n_given=None, save_traj=True, save_metrics=True` |
| `ts/algorithm/neb.py:147` | `IDPPParams` | `max_steps=300, step_size=0.01, r_cut=12.0, eps=1e-8, w_power=2.0` |
| `ts/algorithm/neb.py:190` | `NEBParams` | `n_images=10, k_min=0.03, k_max=0.3, use_dynamic_k=True, k_decay=0.5, max_iter=500, lbfgs_m=20, step0=2e-2, ifidpp=1, neb_f_max_th=9.5e-3, neb_f_rms_th=5e-3, initial_opt=False, refine=None, cineb_f_max_th=1e-2, cineb_f_rms_th=1e-2, cilbfgs_m=20, cistep0=5e-3` |
| `ts/algorithm/autoneb.py:36` | `AutoNEBParams` | `n_images=20, k_min=0.03, k_max=0.3, use_dynamic_k=True, k_decay=0.5, max_iter=256, lbfgs_m=10, step0=2e-2, ifidpp=1, ang_max=0.3, ang_iter=20, path_iter=50, min_e_drop=0.001, ep_iter=30, ep_e_drop=0.0005, autoneb_f_max_th=9.5e-3, autoneb_f_rms_th=5e-3, max_depth=5, max_paths=10, do_final_refine=True, final_refine_factor=2.0, final_refine_max_iter=200, final_refine_ep_iter=20, verbose=1` |
| `ts/algorithm/autoneb.py:84` | `PathNode` | 路径树节点（path_id/images/energies/parent/children/status/depth/.../lbfgs_S/Y/rhos） |
| `ts/algorithm/string.py:292` | `GSMParams` | 见 §3.3 string |
| `ts/algorithm/dmf.py:636` | `DMFParams` | `backend="numpy", beta=10.0, nmove=10, nsegs=6, dspl=3, update_teval=False, coefs=None, t_eval=None, w_eval=None, init_path="fbenm", fbenm_correlated=True, ipopt_out=False, mass_weighted=False, remove_rotation_and_translation=True, tol="tight", max_iter=200, refine=None` |
| `irc/algorithm/gs.py:112` | `GSParams` | 见 §3.4 |
| `irc/algorithm/hpc.py:195` | `HPCParams` | 见 §3.4 |
| `irc/algorithm/eulerpc.py:195` | `EulerPCParams` | 见 §3.4 |
| `irc/algorithm/lqa.py:110` | `LQAParams` | 见 §3.4 |
| `frequency/frequency.py:101` | `FrequencyParams` | `method="mw", temperature=298.15, ilowfreq=2, verbose=1, treat_imag_as_real=False, pressure_kpa=101.325, device="cpu"` |
| `frequency/frequency.py:112` | `PrintParams` | `n_freqs_to_print=10, sort_ascending=True, imag_tol_cm1=10.0` |
| `frequency/frequency.py:125` | `ThermoResults` | `zpe_kjmol, h_trans_kjmol, h_rot_kjmol, h_vib_thermal_kjmol, s_trans_jmolK=0, s_rot_jmolK=0, s_vib_jmolK=0, g_correction_kjmol=0`（结果容器，非用户参数） |
| `md/ensemble/nve.py:38` | `NVEParams` | `timestep=0.1, steps=100000, temperature=300.0, traj_every=100, log_every=100, traj_format="xyz", verbose=1, debug=False, init_velocities=True, restart=False, load_state=False, rst_file="", rst_every=1000, remove_com=True, remove_rotation=False, remove_angular=True, remove_com_every=0, remove_angular_every=0, random_seed=None` |
| `md/ensemble/nvt.py:71` | `NVTParams` | `timestep=0.1, steps=100000, temperature=300.0, thermostat="langevin", friction=0.001, tau_t=100.0, traj_every=100, log_every=100, traj_format="xyz", verbose=1, debug=False, init_velocities=True, restart=False, load_state=False, rst_file="", rst_every=1000, remove_com=True, remove_rotation=False, remove_angular=False, remove_com_every=100, remove_angular_every=0, random_seed=None` |
| `md/ensemble/npt.py:65` | `NPTParams` | `timestep=0.1, steps=100000, temperature=300.0, pressure=1.0, thermostat="v-rescale", barostat="c-rescale", friction=0.001, tau_t=200.0, tau_p=2000.0, compressibility=4.5e-5, traj_every=100, log_every=100, traj_format="xyz", verbose=1, debug=False, init_velocities=True, restart=False, load_state=False, rst_file="", rst_every=1000, remove_com=True, remove_rotation=False, remove_angular=False, remove_com_every=100, remove_angular_every=0, random_seed=None` |

### 4.1–4.5 MD 子组件构造默认（非 dataclass，走 `__init__`）
- `LangevinThermostat(atoms, temperature, friction, timestep, rng=None)`，`friction` 单位 1/fs，OU 系数 `c1=exp(-γdt), c2=sqrt((1-c1²)kT/m)`（`md/thermostat/langevin.py:46-85`）。
- `VRescaleThermostat(atoms, temperature, tau_t, timestep, rng=None, n_dof=None)`（`md/thermostat/vrescale.py:46-92`）。
- `BerendsenBarostat(atoms, pressure, tau_p, timestep, compressibility=DEFAULT_COMPRESSIBILITY)`（`md/barostat/berendsen.py:56-88`）。
- `CRescaleBarostat(atoms, pressure, temperature, tau_p, timestep, compressibility=DEFAULT_COMPRESSIBILITY, rng=None)`（`md/barostat/crescale.py:53-95`）。
- `VelocityVerlet(atoms, timestep)`，内部 fs→a.u.（`md/integrator/velocity_verlet.py:43-59`）。
- 单位常量：`KELVIN_TO_HARTREE, AMU_TO_AU, FS_TO_AU`（`md/__init__.py:46-53`）。
- `CommandControl.DEFAULTS["md"]` 又给出另一套默认（timestep=0.25, steps=400000, ...，`read/command_control.py:64-92`），与 dataclass 默认 **不一致**（注意：输入解析时 DEFAULTS 会先注入 params 覆盖 dataclass 默认）。

### 4.6 CommandControl 参数白名单（用于 Fortran 解析器对照）
- `LBFGS_PARAMS` / `RFO_PARAMS` / `SDCG_PARAMS` / `OPT_METHOD_PARAMS`（`command_control.py:115-158`）
- `SCAN_PARAMS={"method","mode"}`、`TS_REFINE_MAP`（`command_control.py:159, 197-200`）
- `SOLV_PARAMS`（隐式/显式溶剂，`command_control.py:160-185`）
- `GLOBAL_PARAMS={model, model_options, device, gpuid, d4, pbc, solv, level}`（`command_control.py:105-114`）

---

## 5. Calculator 抽象

### 5.1 `calculator_base.py`（~420 行）
- 注册表：`_REGISTRY` + `register_calculator`（按 `cls.MODEL_NAMES` 注册，`calculator_base.py:13-31`）、`get_registered_calculator`、插件（`module=` 或 `MAPLE_CALCULATOR_PLUGINS` env）。
- 核心类 `CalcABC(ase.calculators.calculator.Calculator)`（:266-...）：
  - 协议属性：`MODEL_NAMES=()`, `MODEL_ENERGY_UNIT='eV'`, `SUPPORTED_HESSIAN_MODES=('numerical',)`, `SUPPORTS_CHARGE_MULT=False`, `SUPPORTS_PBC=False`, `CHECKPOINT_FILENAME`, `REQUIRES_LOCAL_MODEL_FILE`, `OPTION_KEYS`, `MODEL_PATH_OPTION`（:268-280）。
  - `calculate(atoms, properties, system_changes)`：PBC 拒绝 + 隐式溶剂导数拒绝 + 调父类（:306-316）。
  - `_finalize_results(atoms, energy, forces, hessian, unit)`：唯一写 `self.results` 的入口；eV→Hartree 转换（`EV2HARTREE`，:123, 126-140, 323-354）。
  - `get_hessian(atoms, delta=0.002)`：按 `self.hessian` 分派 `analytic`（调 `_analytic_hessian`）或 `numerical`（`numerical_hessian_from_atoms` 中心差分，:355-368）。
  - `_analytic_hessian(atoms)`：后端 autograd，基类 NotImplemented（:370-375）。
  - `get_hvp(atoms, n)`：Hessian-vector product，基类 NotImplemented（Dimer 用，:399-412）。
  - 内部工具：`numerical_hessian_from_atoms`（:173-234，含 FixAtoms 处理与 PHVA 嵌入）、`hessian_via_double_autograd`（:238-260，torch 双重 autograd，逐列）。
  - 隐式溶剂守卫：`reject_implicit_solvent_derivatives`（:70-78）——GBSA/QEq 只支持能量，请求 forces/hessian 直接 `NotImplementedError`。
- **最小接口**：任何方法必须提供 ASE `calculate`（至少 energy，通常 forces）。Hessian 可选但 freq/RFO/PRFO/IRC 需要。批量/PBC 可选。Dimer 可选 `get_hvp`。

### 5.2 `set_calculator.py`（~530+ 行）
- `SetCalculator.__init__(device, model, output, atoms, d4, implicit, solvent, model_options, solvation_options)`（:106-127）。
- `_BUILTIN_NAME_TO_MODULE`（:32-51）现有后端：ani(ani2x/ani1x/ani1ccx/ani1xnr)、aimnet(aimnet2/aimnet2nse)、mace(maceoff23s/m/l, egret)、maceomol、macepol(s/m/l)、fennol/fennix-bio1s/m、uma。
- `_validate_against_class`（:221-...）：PBC、hessian mode、coulomb_method、charge/mult、d4 校验。

### 5.3 现有 calculator 与能力矩阵
| 后端 | MODEL_NAMES | 能量单位 | Hessian 模式 | charge/mult | PBC | torch |
|---|---|---|---|---|---|---|
| MACE | maceoff23s/m/l, egret | eV | analytic, numerical | no | no | 是 |
| MACE-general | maceomol | eV | analytic, numerical | no | no | 是 |
| MACE-pol | macepols/m/l | eV | analytic, numerical | yes | no | 是 |
| ANI | ani2x/1x/1ccx/1xnr | **hartree** | analytic, numerical | no | no | 是 |
| AIMNet2 | aimnet2/aimnet2nse | eV | analytic, numerical | yes | no | 是（含 batch `get_ef_gpu`/`get_efh_gpu`/`prepare`） |
| UMA | uma | eV | **numerical only** | yes | **yes** | 是 |
| Fennol | fennol, fennix-bio1s/m | eV | analytic, numerical | yes | no | 是（含 `get_hvp`） |
| extra_correction | GBSA（溶剂）、QEqTorch（电荷） | — | 仅能量 | — | — | 是 |

- **所有后端都是 torch**（`find ... | xargs grep -l 'import torch'` 命中全部 calculator 实现与 `calculator_base.py`）。
- 提供 `get_hvp` 的后端：ANI（`ani/_ani_calculator.py:153`）、Fennol（`fennol/_fennol_calculator.py:118`）。
- 提供批量 GPU 接口的：AIMNet2 batch（`aimnet/_aimnet2_batch_calculator.py`，供死代码 BatchLBFGS 用）。

> **移植含义**：xtb calculator（Fortran 侧）只需在 Python/C 绑定层提供「能量 / 力 / 可选 Hessian」即可覆盖 sp/opt/scan/NEB/freq/IRC；Dimer(use_hvp=True) 与解析 Hessian 是额外可选项。

---

## 6. Utility 层

### 6.1 `maple/function/utility/`
- `__init__.py:1` 仅导出 `Molecules`。
- `molecules.py`（15 行）：`Molecules(atoms_list)` 容器，`multiatoms`、`calc`，方法 `get_efh()`→`calc.get_efh_gpu()`、`get_energies_forces()`→`calc.get_ef_gpu()`（`molecules.py:5-14`）。**这就是多结构（NEB/scan/MD/Freq 轨迹）传递的载体**。
- **没有独立的 coordinate-transform / mass-weighting / internal-coordinate 工具模块**。坐标变换与质量加权分散在各算法中就地实现：
  - 质量加权：`D = 1/sqrt(重复3次的m)`，如 RFO `_mass_weight`（`RFO.py:203-211`）、PRFO（`PRFO.py:817-822`）、IRC `masses_D`（`gs.py:61-77`）。
  - 刚体移除：`_remove_rigid_body_components`（`dimer.py:176-...`）、`project_out_rigidbody_forces`（`string.py:137`）。
  - 内坐标：仅由 ASE `FixInternals` 提供（scan 用），MAPLE 自身不实现 Wilson B 矩阵 / DL 坐标。

### 6.2 `maple/function/units/`
- `__init__.py` 与 `units.py` 均为 **0 字节（空文件）**。单位换算在各模块内联（见各算法常量）。
- MD 单位常量实际在 `md/__init__.py`/`md/utils.py`（`KELVIN_TO_HARTREE, AMU_TO_AU, FS_TO_AU`）。
- freq 单位常量内联在 `frequency/frequency.py:31-46`。

### 6.3 dispatcher 依赖的通用数学/几何 helper
- 线性代数：`np.linalg.eigh/eig/lstsq/solve/norm`（各算法）。
- Kabsch 对齐：`kabsch_align`（`neb.py:55`，`string.py:53`）。
- IDPP 插值：`_pair_indices`/`_idpp_targets`（`neb.py:155-181`）。
- 能量加权切线、动态弹簧：`compute_dynamic_k`（`neb.py:214`）、`improved_tangent`（:284）、`cineb_tangent`（:318）。
- 优化核心：`LBFGSDriver`（`neb.py:478-560`，也被 string 家族用法参考）。
- 输出：`write_xyz`/`write_all_images_xyz`（`neb.py:83-146`）、`write_pdb_model`/`write_pdb_trajectory`（`read/filereader/pdb_reader.py`）、频次日志 `logger.py`。

---

## 7. 测试覆盖

- **无 pytest，无 tests/ 目录，无 CI**。`pyproject.toml` 无 `[tool.pytest]`，仓库根无 `.github/` workflow。
- `find . -iname '*test*'` 仅命中 `examples/freq/mw/test{1..4}_inp1_nebts_ts.{inp,out}` —— 这些只是示例输入/输出，不是断言测试。
- `main.py --test 1..8`（`main.py:88-102`）只是跑 `examples/<subdir>/inp1.inp` 的 smoke 运行，不校验数值。
- `examples/` 下各 job 有 `.inp` + `.out`（golden 输出样本可作回归基线），覆盖：
  - `examples/opt/{lbfgs,rfo,sd,sdcg,cg,macepol,exp-solv}`
  - `examples/scan/{C18,da,da_rigid,...}`（含 relaxed/rigid 与多 optimizer）
  - `examples/ts/{prfo,neb,string,autoneb,dimer,dmf}`
  - `examples/irc/{gs,hpc,eulerpc,lqa}`
  - `examples/freq/mw`
  - `examples/sp`
  - `examples/md/nve`
  - `examples/parmfit`
  - `examples/calculator_plugin`
- **未被测试/示例覆盖**：`blbfgs.BatchLBFGS`、`BPRFO.BatchPRFO`（死代码）；`hessian.py`（孤立函数）；`freq` 的 CUDA 路径；`md` 的 nvt/npt（只有 nve 示例）；`radial/内部坐标` 相关（不存在）。
- **结论**：Fortran 移植必须 **自行补齐** 数值卫生测试（每算法收敛性、Hessian 正确性、单位一致性、IRC 路径对称性等），MAPLE 无现成可移植的测试套件。

---

## 8. TASK COMPLETENESS MATRIX

列：实现? / 坐标系 / 需初始 Hessian? / 需 torch? / 备注

| Task | 实现? | 坐标系 | 需初始 Hessian? | 需 torch? | 备注 |
|---|---|---|---|---|---|
| sp | 是 (`sp/sp.py:14`) | 笛卡尔 | 否 | 否（取决于 calculator 后端） | 单点能量 + 可选梯度 |
| opt (min) | 是 | 笛卡尔 | 否 | 否 | LBFGS/SDCG/SD/CG 仅需力；**RFO 需完整 Hessian**（每步重算） |
| scan (relaxed) | 是 (`scan/scan.py:13`) | 内坐标约束（ASE FixInternals） | 否 | 否 | 每点调用 `Optimization`；1D/2D/3D 分层 |
| scan (rigid) | 是 (`scan.py:159`) | 笛卡尔刚体移动 | 否 | 否 | `mode="rigid"`，自动识别移动碎片 |
| TS (P-RFO) | 是 (`ts/algorithm/PRFO.py:464`) | MW（步）/Cart（几何） | **是**（完整 Hessian） | 否 | RS dual-shift，Bofill/BFGS 更新，recalc=1 |
| TS (B-PRFO) | 是（`BPRFO.py:52`）但**死代码** | MW/torch padded | 是 | **是** | 批量 torch，未被 `ts.py` 引用 |
| TS (Dimer) | 是 (`dimer.py:212`) | Cart（可选 mass metric） | 否（用 HVP 或有限差分） | **是**（运行时 torch） | `use_hvp` 可调 `get_hvp` |
| TS (NEB) | 是 (`neb.py:562`) | Cart | 否 | 否 | IDPP 初始化 + 动态弹簧 + L-BFGS |
| TS (CI-NEB/AutoNEB) | 是 (`neb.py:789` CINEB; `autoneb.py:79`) | Cart | 否 | 否 | AutoNEB 自动插点/分裂 |
| TS (GSM/String) | 是 (`string.py:339`) | Cart | 否 | 否 | 两端生长 + 投影 L-BFGS；可 refine 接 PRFO |
| TS (DMF) | 是 (`dmf.py:661`) | Cart（B-spline 路径） | 否 | 可选（backend=torch） | **需 cyipopt**；纯能量目标 |
| hessian (analytic/num) | 由 calculator 提供 (`calculator_base.py:355`) | — | — | 后端决定 | 无独立 job；数值差分 delta=0.002 |
| freq (harmonic) | 是 (`frequency.py:1234`) | MW 或非 MW | **是**（calc.get_hessian） | 可选（CUDA eigh） | 转换因子 2721.1383（Ha/Å²+amu→cm⁻¹） |
| freq (thermo) | 是（RRHO + 低频校正） | — | 是（同上 Hessian） | 否 | ilowfreq 0/1/2/3；T=298.15K, P=101.325kPa |
| IRC (GS) | 是 (`gs.py:143`) | MW | **是**（并用最负模） | 否 | Gonzalez–Schlegel |
| IRC (HPC) | 是 (`hpc.py:231`) | MW | **是** | 否 | LQA 预测 + DWI/mBS 校正 |
| IRC (LQA) | 是 (`lqa.py:140`) | MW | **是** | 否 | 单步 LQA |
| IRC (EulerPC) | 是 (`eulerpc.py:...`) | MW | **是** | 否 | Euler 预测 + DWI/mBS 校正 |
| MD | 是 (`md/ensemble/*.py`) | Cart（a.u.） | 否 | 否 | NVE/NVT/NPT；Velocity-Verlet；周期体系需 cell/stress |

---

## 9. 给 xtb 移植的直接约束清单（scout 结论）

1. **接口最小面**：xtb 只需提供一个「能返回 energy / forces / (可选 hessian)」的 calculator 适配层，即可支撑 sp/opt(min)/scan/NEB/TS(GSM,Dimer)/IR C/MD 的绝大多数路径。
2. **Hessian 是主要缺口**：RFO（opt）、PRFO、Dimer(可选)、freq、全部 IRC 变体都要求 Hessian；IRC/RFO/PRFO 会周期性重算或更新（BFGS/Bofill）。xtb 侧须明确：解析 Hessian 是否可用；否则用 `calculator_base.numerical_hessian_from_atoms` 的中心差分（delta=0.002，O(6N) 次力调用）。
3. **坐标约定必须对齐**：MAPLE 的 Hessian 单位是 **Hartree/Å²**、质量 amu、MW 转换因子 2721.1383（注意与 ORCA 的 5140.4867 不同，factor 在 `frequency.py:1049-1052` 解释）。
4. **收敛判据统一**：所有 opt/scan/PRFO/Dimer 用 4 判据（max_f/rms_f/max_dp/rms_dp 对 `atoms.*_th`），阈值由 `level` 映射（§1.3）。Fortran settings 应保留该结构。
5. **torch 阻塞点可规避**：真正的 torch-only 是 `blbfgs`/`BPRFO`（死代码，可忽略）与 Dimer 的运行时 torch（需重写为 numpy）；其余全部 numpy。DMF 的 torch 后端是可选分支。
6. **需要外部依赖的算法**：DMF 需 cyipopt；parmfit 需 Gaussian/ORCA。二者不属于核心 xtb 移植范围。
7. **参数语义**：`JobABC._init_params` 的大小写不敏感键映射与 `CommandControl.DEFAULTS` 的「输入默认 vs dataclass 默认」双轨是 Fortran settings-type 必须精确复刻的语义（尤其 MD，两套默认不一致）。
8. **测试**：MAPLE 无测试，`examples/*.out` 可作为数值基线参考；Fortran 侧需自建回归测试。

---

### 附：主要文件清单（含 LOC）
- `dispatcher/dispatcher.py` 240；`dispatcher/jobABC.py` 81
- `dispatcher/sp/sp.py` 112；`dispatcher/optimization/optimization.py` 37
- `dispatcher/scan/scan.py` 491；`dispatcher/frequency/frequency.py` 1306；`dispatcher/hessian/hessian.py` 39（孤立）
- `dispatcher/ts/ts.py` 140；`ts/algorithm/{PRFO 892, BPRFO 944, dimer 537, neb 1540, autoneb 1214, string 954, dmf 2767, _dmf_torch_backend 121, logger 21}`
- `dispatcher/irc/irc.py` 34；`irc/algorithm/{gs 768, hpc 919, eulerpc 964, lqa 722, logger 21}`
- `optimization/algorithm/{blbfgs 535, _common 89, DIIS 218, LBFGS 219, RFO 389, SDCG 557, SD 11}`
- `scan/algorithm/{LBFGS 176, RFO 185, logger 21}`（legacy）
- `md/`：`__init__ 67, logger 1117, utils 851, rst_io 331, mdp_reader 83, md_templates 169, dcd_writer 402`；ensemble `{nve 580, nvt 629, npt 637}`；thermostat `{langevin 111, vrescale 170}`；barostat `{berendsen 143, crescale 173}`；integrator `{velocity_verlet 303}`
- `calculator/calculator_base.py` ~420；`calculator/set_calculator.py` ~530+
- `read/command_control.py`（参数校验/默认）；`read/input_reader.py`（jobtype 来源）
- `utility/molecules.py` 15；`units/`（空）
