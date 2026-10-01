# 37 — M5 验证实验报告（chain-of-states：NEB / CI-NEB / AutoNEB / String(GSM)）

> 输入：`docs/xtb-landscape-PLAN.md` §6.4 / §6.5 / §7 / §8.2（#8）/ §9.6 / §12（R-08/R-11/R-13/R-14/R-15）；
> `AGENTS.md` §4/§5/§6；实现报告 `35-m5-path-implementation-report.md`（IDPP/NEB/CI-NEB）、
> `36-m5-autoneb-string-report.md`（AutoNEB/String/GSM）；M4 实测 `28-m4-validation-experiments.md`
> （σ_g、力阈值可达下限）；M4 复核 `34-m4-coverage-fix-report.md`（注入等价性教训）。
> 角色：**验证者**。本报告只做实验与结论；**未改动任何 `src/` 生产逻辑**（§6.1 用 `git status` 与
> 文件校验和证明），生产代码的缺陷只报告（§4.7）。
> 数据：`docs/_landscape-recon/m5-path-data/`（14 个 CLI 目录 + 5 组注入 + 单元套件/ctest 原始输出 + 脚本，见 §9）。
> 纪律：全部 `xtb`/`ctest` 调用 `OMP_NUM_THREADS=1`；只跑 `-R landscape` 与回归子集，从未跑全量 ctest。

---

## 0. 结论摘要

| 验收项 | 结果 | 判定 |
|---|---|---|
| **验收 1：LEPS 势垒（< 0.5 kcal/mol）** | NEB **+0.0000**、CI-NEB **+0.0000**、AutoNEB **−0.0004**、String/GSM **+0.0003** kcal/mol；解析参考由**独立 Python 实现**复核（r×1e-9、E×1e-10）；**P-RFO（M4）第 4 路**独立定位到 `r12=r23=1.505269`，误差 **+0.0000 kcal/mol** | **通过**（4 路互校） |
| **验收 2：实验 #8 阈值** | `climb_switch_rms = **9.7234e-3** Eh/bohr`（= 0.5 eV/Å，独立换算复核 9.7234532e-3）；PLAN/任务书值 3.472e-2 是**倒数换算**，大 **3.5707** 倍；噪声（σ_g ≤ 1.2e-15、warm 3.9e-7）比阈值小 **13 / 4 个数量级** → **不可能误触发**；点火迭代实测 **31 / 26 / 0**（阈值 9.7234e-3 / 3.472e-2 / 1.0），收敛鞍点与势垒**完全相同** | **通过，[待校准] 结案** |
| **验收 2：k_min/k_max** | 校准对象是**动态调度**：LEPS 上动态校准值 48 步、动态 PLAN 值 30 步都收敛且误差 < 1e-4 kcal/mol，而**静态 1e-2 / 1e-1 都不收敛**（静态 1e-3、1、10 收敛）。NH3 上静态两端都收敛（11 / 10 步）→ 静态失败是**陡峭解析面特有**。PLAN 初值不构成阻塞 | **通过，[待校准] 结案** |
| 可证伪性注入 | **5/5 全部变红**，还原后 68/68 + 12/12 + 47/47 全绿（§5）；每项先论证与旧逻辑**语义不等价** | 通过 |
| 测试 | `ctest -R landscape` **68/68**、回归子集 **12/12**、单元套件 `landscape-path` **47/47**（M5 第二阶段后 36 → 本报告 +11）；`ctest -N -R landscape` = 68；`add_test` 无重名 | 通过 |
| 发现 | **F1（MEDIUM）band 传播鲁棒性**（无线搜索，收敛性对 n_images / max_displ 非单调）、**F2（MEDIUM）**AutoNEB 同源、F3–F7（LOW/INFO） | 见 §4.7，交 M6/M7 |

---

## 1. 环境与方法

| 项 | 值 |
|---|---|
| 基线 | `HEAD = 902cbe4`（M4）+ **未提交的 M5 工作区**（报告 35 第一阶段 + 报告 36 第二阶段） |
| 构建 | `cmake -S . -B /tmp/xtb-land/build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON -DCMAKE_BUILD_TYPE=Release && cmake --build … -j8`，exit 0 |
| 线程 | `OMP_NUM_THREADS=1`（AGENTS.md §4） |
| 单元驱动 | `/tmp/xtb-land/build/test/unit/xtb-tester landscape-path`（test-drive，逐用例打印原始量） |
| CLI 体系 | GFN2-xTB、NH3 反转（`m5-path-data/inputs/nh3_up.xyz` / `nh3_down.xyz`），全部 `--norestart` |
| 解析面 | LEPS（H + H2 三原子）+ Müller-Brown 2 维嵌入（M5 已有） |
| 单位 | 输入 `.xyz` 为 Å；报告内一律 bohr / hartree / Eh·bohr⁻¹ / kcal·mol⁻¹（`autokcal`） |

**新增测试用例（11 个，全部可证伪）**：`leps-prfo-cross-check`、`leps-autoneb-barrier`、
`leps-string-barrier`、`climb-switch-calibration`、`band-dual-criterion-live`、
`band-rotated-endpoint-align`、`band-initial-path-scan`、`band-spring-schedule`、
`string-asymptotic-endpoints`、`band-convergence-curve`、`band-unconnected-endpoints`
（`test/unit/test_landscape_path.f90`，纯追加；另修 1 处陈旧文档注释，见 F6）。

---

## 2. 验收 1（PLAN §9.6）：LEPS 势垒与解析值

### 2.1 独立复核解析参考（不盲信报告 35）

参考由 `scripts/leps_reference.py`（**独立 Python/numpy 实现**，与 Fortran 模型无共享代码；
`scipy` 求根 / 特征分解）计算，参数与模型一致（`d_e=0.1744342274 Eh, β=3.6711 /bohr, r_e=1.4011 bohr, Sato=0.10`）：

| 量 | 独立计算 | 模型（Fortran） | 差 |
|---|---|---|---|
| H2 渐近极小 | `r = 1.4140737807` bohr，`E = −0.154980938826` Eh | 1.4140743 / −0.154980938808（报告 35 §7.4） | `2e-7` bohr / `1.8e-11` Eh |
| 对称共线鞍点 | `r* = 1.5052685936` bohr（`r13 = 3.0105371871`），`E = −0.140638574121` Eh，`|g| = 8.5e-11` | 1.505269 / −0.140638574121，`max|g| = 6.8e-9` | `6e-9` bohr / `< 1e-12` Eh |
| 鞍点谱 | `−1.00494144`，`0.00300403 ×2`，`1.89540979`（+5 刚体 ≈ 1e-11…1e-16） | 单元用例同值 | 一致 |
| 经典势垒 | **8.999970** kcal/mol（相对渐近阱 `r3 = 20 bohr`）= 0.390276 eV | 9.0000 kcal/mol | `3e-5` |
| band 端点势垒 | `r3 = 4 bohr`（`r12` 固定 = `r_h2`）端点 `E = −0.1549786471` ⇒ **8.9985** kcal/mol | `leps_barrier = 8.9985` | 一致 |

> 报告 35 的解析值（`r*`、`E_TS`、谱、势垒）**全部被独立复现**；`tests` 里 8.9985 与
> 「相对渐近阱的 9.0000」差 0.0015 kcal/mol 是**端点定义**差（第三个 H 在 4 bohr 处），不是误差。
> **F6（已修）**：`test/unit/landscape_testpot.f90:154` 的文档把鞍点本征值写成
> `−0.334981 / +1.895409`（陈旧值），实测谱是 `−1.004939 / +0.003004 ×2 / +1.895410`，已更正。

### 2.2 LEPS：四种方法 + P-RFO 的势垒与 TS 几何

原始输出：`unit-suite-landscape-path.txt`（§9）。

| 方法 | 迭代/规模 | 势垒 kcal/mol | 与解析差 kcal/mol | TS 几何（bohr） | 与解析几何差 |
|---|---|---|---|---|---|
| 解析 | — | 8.9985 | — | `r12 = r23 = 1.505269`，`r13 = 3.010537` | — |
| NEB（9 像，IDPP） | 48 | 8.9985 | **+0.0000** | 1.50518 / 1.50518 | 8.9e-5 |
| CI-NEB（9 像，第 31 步点火） | 48 | 8.9985 | **+0.0000** | 1.50518 / 1.50518 | 8.9e-5 |
| AutoNEB（5 stage / 4 插点 / 9 像） | 113（总） | 8.9981 | **−0.0004** | 1.503686 / 1.506537 | 1.6e-3 |
| String/GSM（well-side 端点，32 节点） | 生长 1 + 迭代上限 | 6.7972（**相对其自身端点**） | **+0.0003**（相对同端点解析值 6.7969） | 1.505073 / 1.504439 / 3.009512 | 2.4e-3 / 8.3e-4 / 1.0e-3 |
| **P-RFO（M4，`hlow=1e-6`）** | 5 | —（`E_TS` 直接比较） | **+0.0000** | 1.505269 / 1.505269 | `2e-9` |

**几何互校 RMSD（LEPS）**：AutoNEB vs NEB **0.000407** bohr；AutoNEB vs P-RFO **0.000395**
bohr（Kabsch 对齐后；未对齐 0.390318 bohr，全部是刚体漂移）；NEB vs CI-NEB ≤ 1e-5。
P-RFO 收敛点的 Hessian 谱 = `−1.004938 / +0.003004 ×2 / +1.895411` ⇒ **恰 1 个负本征值**，
与 band 的鞍点候选是同一个一级鞍点。

> **String 的端点选择（必须写明）**：string 生长**不能**用 band 的渐近端点（第三 H 在 4 bohr）。
> 该势的 MEP 从渐近端点走向鞍点时要**缩短 `r13` 2.4 bohr**，而两端点连线的 `r13` 恒定 ⇒
> 生长方向与 MEP 正交。实测（`string-asymptotic-endpoints`）：`ds = 0.5` **生长停滞**、
> `ds = 1.0/1.5` **无进展**、`ds = 2.0` 闭合但最高节点仍在阱区（势垒 0.2599，误差 −8.74 kcal/mol，
> 且如实报 `converged = .false.`）。因此 string 腿改用 **well-side 端点**
> `(r12, r23) = (1.414, 2.0)/(2.0, 1.414)`（`r13 = 3.414` 恒定，距鞍点平面 0.4 bohr），
> 其解析势垒 6.7969 kcal/mol 由**同一个闭式面在同端点**取值得到，与 string 自己的势垒同义可比。
> **String 满足势垒验收（+0.0003）但未满足 band 的力判据**（`f_avg = 3.6e-3`、
> `f_max = 2.2e-2`，3000 步上限；见 F5）。

### 2.3 真实体系互校（GFN2，NH3 反转，`m5-path-data/cli-*`）

| 方法 | 收敛 | 势垒 kcal/mol | TS 候选 | 最低虚频 cm⁻¹ | 虚频数 |
|---|---|---|---|---|---|
| NEB（9 像） | 11 步 | 6.0825 | 最高像 5 | −971.3 | 1 |
| CI-NEB（9 像，点火 iter 0） | 11 步 | 6.0825 | climbing 5（`ci_f_rms 1.85e-4`） | −971.3 | 1 |
| AutoNEB（5 stage / 4 插点 / 9 像） | 8+…+1 步 | 6.0823 | climbing 5 | −971.29 | 1 |
| String（8 节点，生长 6 步，15 次重参数化，645 次势能评价） | 8 + 3 climbing | 5.9789 | climbing node 3 | −955.27 | 1 |
| GSM（同内核） | 同 string | 5.9789 | 3 | −955.27 | 1 |

**TS 几何互校（`scripts/xyzrmsd.py`，Kabsch 对齐，bohr/atom）**：

| 对比 | RMSD |
|---|---|
| NEB vs CI-NEB | **0.000019** |
| AutoNEB vs CI-NEB / NEB | **0.000606** |
| String vs NEB / CI-NEB / AutoNEB | **0.026489 / 0.026508 / 0.026491**（= 0.0140 Å） |
| String vs GSM | **0.000000**（逐位相同） |

String 的 TS 比 band 高 **0.104 kcal/mol**（`−4.4166715` vs `−4.4165064` Eh），几何差 0.014 Å，
且 string 收敛残差（`f_rms_max 1.78e-3`，climbing 力 1.79e-3）比 band 大一个数量级 ——
三者互洽，说明差异是 string 的点火节点**未完全落到鞍点**，不是实现分歧。报告 35/36 的
NH3/AutoNEB/String 数字被**独立复现**（势垒、虚频、帧数逐位一致）。

### 2.4 交付物（`path.xyz` / `path_autoneb.xyz` / `path_ts_list.xyz`）

| 方法 | 文件 | 帧数 | 内容 |
|---|---|---|---|
| NEB / CI-NEB | `path.xyz` | 9 | 帧 1 = 反应物、帧 9 = 产物，逐帧 comment 含能量 |
| AutoNEB | `path_autoneb.xyz` | 9 | 末 stage 路径（也是重启文件） |
| AutoNEB | `path_ts_list.xyz` | 5 | **每个 stage 一帧**，逐帧带 `imaginary modes: 1` |
| String / GSM | `path.xyz` | 8 | 最终 string（含端点） |
| String / GSM | `path_ts_list.xyz` | 1 | 最终路径的内部极大（climbing node） |

---

## 3. 验收 2（PLAN §8.2 实验 #8）：climbing 阈值与弹簧常数标定

### 3.1 `climb_switch_rms`：单位、噪声、以及"会不会被误触发"

**(a) 单位换算独立复核**（`scripts/upwind_equivalence.py` 同时输出）：

```
0.5 eV/Å = 0.5 · evtoau / aatoau = 0.5/27.21138505 · 0.52917726⁻¹ = 9.7234532e-3 Eh/bohr
PLAN/任务书 3.472e-2 / 9.7234532e-3 = 3.5707   （= 0.5/14.4 的倒数换算）
```
`settings.f90:170` 存 **9.7234e-3**（5 位有效数字），与精确值差 `5.3e-8`（相对 `5.5e-6`）——
见 F4（INFO，建议存精确表达式或写明舍入）。

**(b) 噪声论证**（复用 M4 报告 28 §3.1 实测，本报告不重测物理噪声，但重测了**确定性**）：

| 噪声源 | 实测 | 与 9.7234e-3 之比 |
|---|---|---|
| 冷启动、`OMP=1` 重复 | **0**（逐位相同） | — |
| 冷启动、`OMP≥2` | ≤ 1.16e-15 Eh/bohr | 小 **8.4e12** 倍 |
| 跨 `OMP_NUM_THREADS` | ≤ 1.11e-15 | 小 **8.8e12** 倍 |
| warm-restart 系统偏置 | 3.916e-7 | 小 **2.5e4** 倍 |

**本报告新增的可证伪半边**：`climb-switch-calibration` 断言同一调用两次**逐位相同**
（`ignition_iteration`、`f_rms_max`、`ts_energy` 全等），即切换时刻完全由 band 状态决定，
没有任何噪声通道；M5 全部路径任务 restart 策略统一为 `off`（硬约束 5），warm 偏置不进入。

**(c) 真实体系上的 `band_f_rms_max` 收敛曲线（原始数据）** —— NH3 反转，CI-NEB，9 像
（`cli-cineb/stdout.txt`，`printlevel=1` 的逐迭代表）：

| iter | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `f_rms_avg` | 1.117e-3 | 1.412e-3 | 2.247e-3 | 2.546e-3 | 3.553e-3 | 1.227e-3 | 8.194e-4 | 5.527e-4 | 4.309e-4 | 5.484e-4 | **2.596e-4** |
| `f_rms_max` | 1.853e-3 | 2.486e-3 | 2.632e-3 | 3.297e-3 | 3.947e-3 | 1.387e-3 | 1.302e-3 | 8.342e-4 | 6.059e-4 | 1.084e-3 | **3.064e-4** |
| `dE(hei)` kcal/mol | 6.0834 | 6.1017 | 6.3211 | 6.0848 | 6.1022 | 6.0824 | 6.0832 | 6.0825 | 6.0845 | 6.0834 | **6.0825** |

点火发生在 **iteration 0**：初始 band 的 `f_rms_max` 已低于 9.7234e-3（NH3 上界 ≈ 1e-2 量级）。
**同一体系的能量曲线不失真**：`dE(hei)` 全程 6.082–6.321 kcal/mol，最终 6.0825。

**(d) LEPS 上的完整收敛曲线（原始数据）** —— 重建法（每个 budget 都是同一初始 band 的
确定性重跑，`band-convergence-curve`，节选；全表在 `unit-suite-landscape-path.txt`）：

| iter | 0 | 1 | 4 | 10 | 14 | 22 | 26 | 31 | 33 | 35 | 43 | **48** |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `f_rms_avg` | 8.173e-2 | 1.635 | 1.030 | 3.318e-1 | 2.451e-2 | 5.060e-1 | 1.125e-2 | 1.530e-3 | 4.165e-3 | 7.441e-2 | 1.299e-3 | **2.521e-4** |
| `f_rms_max` | 1.199e-1 | 5.339 | 2.484 | 9.082e-1 | 3.739e-2 | 1.428 | 2.942e-2 | 2.797e-3 | 9.925e-3 | 1.732e-1 | 1.591e-3 | **5.613e-4** |
| `dE(hei)` | 81.13 | 706.1 | 331.6 | 84.97 | 66.97 | 154.1 | 10.74 | 9.000 | 9.012 | 11.28 | 8.999 | **8.9985** |

曲线**非单调**，尖峰最大到 `f_rms_max = 5.34`（iter 1）、`1.43`（iter 22）：这正是阈值必须
由 band 状态（而非固定迭代数或噪声）决定的原因；`band-convergence-curve` 把
「最小通过 budget = 无约束运行的迭代数（48）」钉为断言。

**(e) 阈值改变点火时刻，但不改结果**（`climb-switch-calibration`，LEPS，9 像）：

| `climb_switch_rms` | 点火迭代 | 收敛迭代 | `E_TS` / Eh | 势垒 kcal/mol | 与解析差 | `r12/r23` |
|---|---|---|---|---|---|---|
| 9.7234e-3（校准 = 0.5 eV/Å） | **31** | 48 | −0.1406385595 | 8.9985 | **+0.0000** | 1.50518 / 1.50518 |
| 3.472e-2（PLAN/任务书值） | **26** | 48 | −0.1406385595 | 8.9985 | **+0.0000** | 1.50518 / 1.50518 |
| 1.0（荒谬地早） | **0** | 48 | −0.1406385595 | 8.9985 | **+0.0000** | 1.50518 / 1.50518 |
| 1e-12（低于收敛力，永不点火） | 无 | 48（plain NEB） | — | 8.9985 | +0.0000 | — |

CLI 侧同样：NH3 上 `--lts-climb-switch 3.472e-2 / 1.0 / 10.0` 三个值**都**在 iter 0 点火、
**都**给出 6.0825 kcal/mol 与同一 TS（`cli-cineb-t34 / -t1 / -t10`）。

> **如实记录**：「过早点火导致能量曲线失真」这一 PLAN 预期失效模式，在 LEPS 与 NH3 上**都未复现**：
> climbing image 无论何时点火都收敛到同一鞍点（这是因为 CI 力 `F − 2(F·τ)τ` 本身把该像推向鞍点，
> 与起始位置无关）。因此阈值的作用是**省算力/稳健性**（在 band 尚未成形时不冒险），
> 而不是精度。这不削弱定值本身（单位错误必须纠正），但必须写清："0.5 eV/Å 是保守的**工程**阈值，
> 本套件未测到它带来精度收益"。

### 3.2 `k_min` / `k_max` 标定

**(a) 静态扫描（LEPS，9 像，400 步预算，`neb-spring-calibration` 原始输出）**：

| k / Eh·bohr⁻² | 1e-5 | 1e-4 | 1e-3 | **1e-2** | **1e-1** | 1 | 10 | 1e2 |
|---|---|---|---|---|---|---|---|---|
| 迭代 | 31 | 30 | 31 | **不收敛** | **不收敛** | 37 | 43 | **不收敛** |
| 势垒误差 kcal/mol | 0.0000 | 0.0000 | 0.0001 | 1.1e6 | 2.3e4 | 0.0004 | 0.0001 | 5.8e5 |
| 最小像间距 /bohr | 0.065 | 0.066 | 0.071 | 1.02 | 3.58 | 0.500 | 0.501 | 1.52 |

细扫（临时探针，1e-4…1e4，见 §9 说明）：静态 **1e3、1e4 也不收敛**。
**静态窗口非单调**（收敛：`1e-4…1e-3` 与 `1…10`；不收敛：`1e-2`、`1e-1`、`1e2…1e4`）。

**(b) 动态调度 vs 静态（`band-spring-schedule`）**：

| 设定 | 收敛 | 迭代 | 势垒误差 kcal/mol |
|---|---|---|---|
| 动态校准 `k_min=1e-2, k_max=1e-1`（`settings.f90` 默认） | **T** | **48** | 0.0000 |
| 动态 PLAN 初值 `2.083e-3 / 2.083e-2` | **T** | **30** | 0.0000 |
| 静态 `1e-2` | F | 400（上限） | 1.13e6 |
| 静态 `1e-1` | F | 400（上限） | 2.32e4 |
| 静态 `2.083e-3`（PLAN 下界） | T | 31 | 0.0000 |
| 静态 `2.083e-2`（PLAN 上界） | T | 56 | 0.0000 |

**(c) NH3（真实体系，CLI）**：动态校准值 **11 步**、动态 PLAN 初值 **20 步**、
静态 `1e-2` **11 步收敛**、静态 `1e-1` **10 步收敛**（`cli-neb-plan-k / -statk / -statk2`）。

> **结论（回填依据）**：
> 1. **PLAN 初值可用**（LEPS 30 步、NH3 20 步，势垒误差 ≤ 2e-4 kcal/mol）——R-13 担心的
>    "1.9–3.6 倍单位不确定度"在这两个面上都**不改变收敛性也不改变势垒**，因此它不是阻塞项。
> 2. **真正需要标定的是"调度"**：在 LEPS 的陡峭面上，窗口内**静态** k 反而失败，动态调度才收敛。
>    所以 `[待校准]` 必须同时标明 `k_min`、`k_max` 与 `use_dynamic_k`，不能只给一个数（R-11）。
> 3. 保留校准默认 `1e-2 / 1e-1`（LEPS 与 NH3 都收敛；与 PLAN 值同量级，且 `k_max` 更靠"不硬"一侧）。
> 4. 上界（`k=1e2` 不收敛）是**可证伪**的：`neb-spring-calibration` 断言 `fails(1e2) < 0`（注入会变红）。

### 3.3 string 的端点契约（顺带验收）

见 §2.2 的注：`string-asymptotic-endpoints` 用表把四种 `ds` 的实测行为钉住，并断言
**不允许"静默收敛到错误鞍点"**（返回路径时要么命名它没满足的力判据、要么势垒远离解析值）。
这是对报告 36 §5.1 的独立复现 + 升级为可证伪契约。

---

## 4. 失效模式实测

### 4.1 过早点火 CI
见 §3.1(e)：LEPS 阈值 1.0 → iter 0 点火，势垒/几何/迭代数**逐位相同**；NH3 阈值 10.0 同样。
**结论：未复现失真**（如实记录，并说明机制：CI 力自会把像推向鞍点）。

### 4.2 图像数过少 / 过多 + 初始路径（`band-initial-path-scan`）

初始 band 的力与图像数**无关**：IDPP 路径 `f_rms_max = 1.199e-1`（3–15 像基本恒定），
线性插值 `5.7e-2`。但传播的收敛性**非单调**：

| n_images | 3 | 5 | 7 | 9 | 11 | 13 | 15 |
|---|---|---|---|---|---|---|---|
| `max_displ=0.378`（默认） | 14 ✓ | 19 ✓ | **发散** | 48 ✓ | 60 ✓ | **发散** (bar 4.9e3) | **发散** (1.1e6) |
| `max_displ=0.1` | 11 ✓ | 20 ✓ | 24 ✓ | 37 ✓ | 35 ✓ | **发散** (7.5e5) | **发散** (1.7e6) |
| 线性插值 + `max_displ=0.378` | 55 ✓ | 30 ✓ | 发散 | 发散 | 发散 | 发散 | — |

（✓ = 收敛且势垒误差 < 0.5 kcal/mol；`n=7 / max_displ=0.378` 的势垒误差 +88 kcal/mol。）
另有 `max_displ=0.03` / `0.01` 的交叉表（探针，§9）：`n9+idpp` 在 0.03 发散、在 0.1 收敛；
`n7+idpp` 在 0.01 发散、在 0.1 收敛 —— 见 **F1**。

### 4.3 k 过大
静态 `k = 1e2`（LEPS）：400 步不收敛，势垒误差 5.8e5 kcal/mol，最小像间距 1.52 bohr；
`1e3 / 1e4`（探针）同样不收敛，误差 9.7e4 / 9.2e4。`neb-spring-calibration` 把 `1e2` 钉成断言。
**注意**：LEPS 上静态 `1e-2`、`1e-1` 也失败（§3.2），所以"k 过大"不是一个干净的单调上界。

### 4.4 Kabsch 对齐关闭 → 路径漂移（`band-rotated-endpoint-align`）

产物端点绕 z 轴旋转 **30°**（几何上同一个反应）：

| 对齐 | 收敛 | 迭代 | 势垒 kcal/mol | 与参考路径的逐像 RMSD /bohr | `f_rms_max` |
|---|---|---|---|---|---|
| `align = .true.`（默认） | **T** | 37 | 8.9987（误差 +0.0002） | **9.47e-7** | 3.7e-4 |
| `align = .false.` | **F** | 512 | 164.78 | **8.26** | 1.58 |

关闭对齐后图像在两个不同坐标系之间线性插值，切线不再是路径切线，band 直接跑飞
（`min spacing 2.2` bohr）。**结论：Kabsch 对齐是承重件**，且断言是"开启时路径逐像等于参考路径
（< 1e-5 bohr）"，注入（§5 iv：关闭调用点）会把它变红。

### 4.5 NEB 双判据：平均达标但最大未达标（`band-dual-criterion-live`）

初始 band（LEPS，9 像，`max_steps = 0`）的 `f_rms_avg = 8.173e-2`、`f_rms_max = 1.199e-1`：

| 容差组合 | 判定 | 断言 |
|---|---|---|
| `avg_tol = 0.2`（松，avg 达标），`max_tol = 1e-3`（紧，max 不达标） | **不收敛** | 真（不得假收敛） |
| `avg_tol = 1e-6`（紧），`max_tol = 0.2`（松） | **不收敛** | 真 |
| 两者都 0.2（都达标） | **收敛** | 真 |

两个方向 + 正例，共 3 条断言 ⇒ 双判据是**合取**，不存在"平均掩盖最差像"的假收敛。

### 4.6 端点不连通（`band-unconnected-endpoints`）

把产物写成**同一批原子在另一侧**的共线排布（观察原子必须穿过成键对）：band 跑满 512 步，
 `f_rms_max = 6.4e3`、势垒 1.26e6 kcal/mol，**如实报 `converged = .false.`，能量全程有限**，
不崩溃、不伪造结果。

### 4.7 发现（`file:line`，交 M6/M7 处置）

| # | 严重度 | 位置 | 内容 | 证据 |
|---|---|---|---|---|
| **F1** | **MEDIUM** | `src/landscape/path/neb.f90:759`（`clip_band_step` + 无线搜索的 L-BFGS 步） | **band 传播鲁棒性**：同一解析面、同一初始路径，收敛性对 `n_images` 与 `max_displ` **非单调**（§4.2：n=7 默认档发散、n=7 在 0.1 收敛；n=13/15 两档都发散；n=9 在 0.01 发散、0.1/0.378 收敛）。初始 band 力与 n 无关，故根因是**步长/历史**而非初始路径。建议 M7 加线搜索或按体系尺度自动标定 `max_displ`，并在未收敛时把 `max_displ` 提示进日志 | §4.2 表；`band-initial-path-scan` |
| **F2** | **MEDIUM** | `src/landscape/path/autoneb.f90`（各 stage 调 band） | AutoNEB 继承 F1：LEPS 上用**默认** `max_displ = 0.37795` 时各 stage 发散，`1e-2` 才收敛（势垒 8.9981）。NH3 不受影响 | `leps-autoneb-barrier` 的注 |
| **F3** | LOW | `src/landscape/path/neb.f90:719, 809` | band 逐迭代表从 **iter 1** 开始打印，而点火在 **iter 0** 报告 ⇒ 触发点火的 `f_rms_max`（初始 band 力）**不可见**。建议 printlevel ≥ 1 时补打 iter 0 行 | `cli-cineb/stdout.txt`（"ignited at iteration 0"+ 表从 1 开始） |
| **F4** | INFO | `src/landscape/types/settings.f90:170` | `climb_switch_rms` 存 5 位有效数字 `9.7234e-3`，与 `0.5·evtoau/aatoau = 9.7234532e-3` 差 `5.3e-8`（相对 5.5e-6）。建议直接写表达式或注明舍入；PLAN §6.4 已注明 | `climb-switch-calibration` 打印 |
| **F5** | LOW | `src/landscape/path/gsm.f90`（string 收敛判据） | string 在 LEPS 上找到**精确**鞍点（势垒 +0.0003 kcal/mol、几何 ≤ 2.4e-3 bohr）却在 3000 步内达不到 band 的力判据（`f_avg 3.6e-3 / f_max 2.2e-2`）。判据不是鞍点定位的代理（报告 36 §5.3 同现象）。建议 M7 输出**逐节点残差**，区分"端点邻域残差"与"鞍点节点残差" | `leps-string-barrier` 打印 |
| **F6** | INFO | `test/unit/landscape_testpot.f90:154` | 文档把鞍点本征值写成 `−0.334981 / +1.895409`（陈旧），实测 `−1.004939 / +0.003004 ×2 / +1.895410`。**本报告已修**（注释） | §2.1 |
| **F7** | INFO | `test/unit/test_landscape_path.f90`（`naive-tangent-kink`） | 该用例对切线规则是**弱守卫**：注入 (i)/(iii)（朴素切线 / 去掉 upwind）下它**不变红**（它只断言"归一化 + 极值点加权非退化 + 朴素切线有垂向分量"）。切线的可证伪守卫是 `improved-tangent`（断言单调段的前向/后向 upwind 精确值）。见 §5 | §5 注入表 |

---

## 5. 可证伪性（注入实验）

方法：`scripts/inject_m5.py <name>`（改源码 → 全量重建 → 跑 `xtb-tester landscape-path` 与
`ctest -R landscape` → **还原并校验 md5**）。每个注入的"旧逻辑"都是**另一种合法实现**，
所以"变红"直接说明测试能区分两者（报告 34 的教训）。

| # | 注入 | 变异 vs 旧逻辑 | 变红的用例 | 还原后 |
|---|---|---|---|---|
| (i) | 改进切线 → 朴素切线 | 单调/极值分支一律 `τ = normalize(up+um)`（1998 弹性带） | `improved-tangent`、`band-spring-schedule` | 绿 |
| (ii) | Eq.12 弹簧 → 矢量弹簧 | `F = F_perp + k(dp − dm)`（1998 原式） | `spring-eq12`、`neb-spring-calibration`、`mb-neb-saddle`、`autoneb-mb-saddle`、`band-rotated-endpoint-align`、`band-initial-path-scan`、`band-spring-schedule`、`band-convergence-curve` | 绿 |
| (iii) | 关闭 upwind 判据 | 两个单调性分支条件 → `.false.`（一律 Eq.11 加权） | `improved-tangent`、`band-spring-schedule` | 绿 |
| (iv) | 关闭 Kabsch 对齐（**调用点**） | 4 处 `if (settings%align)` → `if (.false.)`（例程保留） | `band-align-effect`、`leps-autoneb-barrier`、`band-rotated-endpoint-align`、`band-spring-schedule`，**+ CLI `xtb/landscape-path-string`** | 绿 |
| (v) | LEPS 梯度按列主序展平（R-08） | `leps_evaluate` 出口 `gradient = reshape(transpose(reshape(g,[3,3])),[9])` | `leps-gradient`、`leps-hessian`、`leps-neb-barrier`、`leps-cineb-barrier`、`cineb-switch-threshold`、`neb-spring-calibration`、`leps-prfo-cross-check`、`leps-autoneb-barrier`、`leps-string-barrier`、`climb-switch-calibration`、`band-rotated-endpoint-align`、`band-initial-path-scan`、`band-spring-schedule`、`string-asymptotic-endpoints`、`band-convergence-curve` | 绿 |

**还原校验**：`md5sum src/landscape/path/neb.f90 = d6921f4f…`（注入前后一致）；
`ctest -R landscape` 68/68、回归 12/12、单元 47/47 全绿。

**每个注入的"语义不等价"论证**（不是靠"另一种写法"变红）：

| 注入 | 非等价性证据 | 数值 |
|---|---|---|
| (i)/(iii) | 单调三元组 `E_{i-1}<E_i<E_{i+1}` 上：upwind 给 `up`，Eq.11 给 `0.707(up+um)` | **相差 45.0°**（`scripts/upwind_equivalence.py`）；`improved-tangent` 直接断言单调段的精确 upwind 值，故两者不可能同时通过 |
| (ii) | 构造 kink 几何上 Eq.12 与矢量弹簧的力差 | **3.0 Eh/bohr**（`spring-eq12` 打印 3.0000 / 3.0000） |
| (iv) | 对齐例程 vs **调用点** 分工不同：`align-rotation` 测例程（不变红，**正确**），band 级用例测使用 | §4.4：路径 RMSD 9.5e-7 → 8.26 bohr |
| (v) | 转置展平与正确展平在列主序约定下**逐分量不同**（`leps-gradient` 断言逐分量一致） | 梯度 O(h²) 检验（`4.26e-5 / 4.26e-7 / 4.28e-9`，比值 9947.8）立刻变红 |

**如实记录的覆盖缺口**：
1. `naive-tangent-kink` 对切线规则**不敏感**（见 F7）。切线真正的守卫是 `improved-tangent`；
   band 级测试（LEPS/MB）在朴素切线下**仍收敛且势垒正确** ⇒ 切线选择的影响只在**弯曲/极值路径**上
   才被观测到，本套件的 LEPS 面太"温和"。
2. 注入 (i)/(iii)/(iv) 都会让 `band-spring-schedule` 变红（它断言"静态 1e-2/1e-1 不收敛"这一
   **标定实测值**）。这不是该用例的缺陷，而是**标定陈旧告警**：传播内核一变，静态窗口必须重测。
   报告中已如实标注，使读者不会把这条红误读成对某个注入的独立证据。
3. 没有做外部实现（pysisyphus/geomeTRIC/MAPLE）的交叉验证：本机无 Python 环境保证，
   且 PLAN R-15 禁止搬运其代码。交叉验证以**解析面 + P-RFO 独立方法**完成（§2.2）。

---

## 6. 改动与纪律

### 6.1 改动清单（**无 `src/` 生产逻辑改动**）

| 文件 | 改动 |
|---|---|
| `test/unit/test_landscape_path.f90` | **+11 个单元用例**（§1 列表）+ 若干局部辅助（`leps_well_reactant/product`、`leps_energy`、`leps_prfo_saddle`、`path_rmsd`、`rotate_geometry_z`）+ 顶部 `use` 两行（`landscape_result`、`landscape_saddle_optimize`、`evtoau/aatoau`）。**无既有用例被放宽或删除** |
| `test/unit/landscape_testpot.f90` | 1 处陈旧文档注释更正（F6，注释 only） |
| `docs/xtb-landscape-PLAN.md` | §3 回填（见 §7）：`[待校准]` 结案 6 处 + 2 张标定表更新 |
| `docs/_landscape-recon/37-*.md`、`m5-path-data/**` | 本报告与原始数据 |

**证明**（本报告交付时）：

```
$ git status --short src/
 M src/landscape/CMakeLists.txt      # 以下 7 项均为 M5 第一/二阶段的既有改动（报告 35/36）
 M src/landscape/meson.build
 M src/landscape/tasks/ts.f90
 M src/landscape/types/coords.f90
 M src/landscape/types/settings.f90
 M src/prog/main.F90
 M src/xhelp.f90
?? src/landscape/path/
$ md5sum src/landscape/path/neb.f90
d6921f4f12bf78f6e5f53078d4b67903   # 注入前 = 注入后（每轮注入脚本自动还原并打印）
```
即：本报告**没有**新增任何 `src/` 变更；`settings.f90` 的标定默认值在第一阶段已写入
（`k_min=1e-2`、`k_max=1e-1`、`climb_switch_rms=9.7234e-3`），本报告只**独立复核并结案**，
未改数值（唯一建议见 F4）。

### 6.2 测试与回归

```
$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape
100% tests passed, 0 tests failed out of 68        Total Test time = 3.43 sec
$ OMP_NUM_THREADS=1 ctest -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
100% tests passed, 0 tests failed out of 12
$ xtb-tester landscape-path        → 47/47 PASSED（原始输出 unit-suite-landscape-path.txt）
$ ctest -N -R landscape | tail -1  → Total Tests: 68
$ grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d   → 空
```

### 6.3 构建物清理

`ctest` 生成的 `Testing/` 位于 **`/tmp/xtb-land/build/`**（构建目录，非仓库）；仓库内
`git status` 仅显示上述 M5 既有改动 + 本报告新增的 `docs/` 文件（无 `Testing/`、无二进制）。

---

## 7. 回填 PLAN（已完成）与对 settings 的建议

**已回填 `docs/xtb-landscape-PLAN.md`**（去掉 `[待校准]`，每条指向本报告与实测数字）：

| 位置 | 回填内容 |
|---|---|
| §4 映射表（CI-NEB 行） | `climbing 切换阈值 9.7234e-3 Eh/bohr（= 0.5 eV/Å，报告 37 §3.1；点火迭代实测 0/26/31）` |
| §6.4 设置表 `k_min/k_max` | **[M5 处置] `[待校准]` 结案**：校准对象是动态调度；LEPS 动态两套值 48/30 步，静态 `1e-2/1e-1` 不收敛；NH3 11 步 vs PLAN 初值 20 步 |
| §6.4 设置表 `climb_switch_rms` | 值改为 **9.7234e-3**，注明 PLAN 3.472e-2 是倒数换算（大 3.5707 倍），并记录 `settings.f90` 5 位舍入（差 5.3e-8） |
| §6.4 算法表（动态弹簧） | `k_min=1.0e-2`、`k_max=1.0e-1`，注明"该窗口内静态值反而失败，调度是承重件" |
| §6.4 算法表（CI-NEB） | 阈值定值 + "LEPS 上阈值放大到 1.0 也只提前点火、不改变收敛鞍点与势垒" |
| §8.2 实验 #8 行 | **结案**（阈值 + 噪声 + 动态调度） |
| §12 风险 R-11 / R-13 | **[M5 结案]**（R-11：调度是承重件；R-13：1.9–3.6 倍不确定度不改变收敛性与势垒，不阻塞） |
| §12.12 标定表两行 | 值后加 `→ 结案` 与 M5 复核依据 |

**对 `settings.f90` 的建议**（**本报告未改**，因属 `src/`）：

1. （INFO，可选）`climb_switch_rms` 改为 `0.5_wp*evtoau/aatoau` 的精确表达式，或在类型文档
   里写明"存 5 位有效数字"。当前 5.5e-6 的相对差在物理上无影响（见 F4）。
2. （可选）`k_min/k_max` 的类型文档可以补一句"校准对象是动态调度；窗口内静态值在陡峭面上不收敛"，
   以免后人把这两个数当静态值直接使用。

---

## 8. 残余风险与下一步建议（M6/M7 之前）

1. **F1/F2（band 传播）是 M5 之后最大的数值鲁棒性缺口**。建议 M7 优先：
   (a) 给 band 步加 Armijo/回溯**线搜索**（力场非保守，故用能量或力范数做接受判据）；
   (b) `max_displ` 按体系尺度自动标定（或在未收敛时提示降低）；
   (c) 退出前打印 `max_displ / max_steps` 的当前值（现在只在头部打印一次）。
2. **F5（string 力判据 vs 鞍点定位）**：建议逐节点输出残差；若确认残差集中在端点邻域
   （本报告的两个面都指向这个解释），可把端点邻域节点从收敛判据中剔除或用 `--lts-relax-ends`
   把端点松到极小（该路径目前无单元覆盖）。
3. **M6（IRC）接口注意**：`path.xyz` 的帧序（1 = 反应物）与 `path_ts_list.xyz` 的候选语义
   已经固定（§2.4），IRC 应消费**同一组候选**并沿用 `restart=off` 的统一策略（硬约束 5）。
4. **测试维护**：`band-spring-schedule` 含"标定陈旧告警"型断言（静态 k 不收敛）。若 M7 改传播内核，
   必须重测这两行，而不是直接放宽（否则会重演 M2 的"把 bug 写进期望值"教训）。

---

## 9. 数据清单（`docs/_landscape-recon/m5-path-data/`）

| 路径 | 内容 |
|---|---|
| `inputs/{nh3_up,nh3_down}.xyz` | CLI 实验输入（与 `test/unit/CMakeLists.txt` 相同的 NH3 反转） |
| `cli-neb/` `cli-cineb/` `cli-cineb-t34/` `cli-cineb-t1/` `cli-cineb-t10/` | NH3 NEB / CI-NEB 与 3 个阈值（stdout 含逐迭代 `f_rms` 表 + `path.xyz` + `xtbts.xyz`） |
| `cli-neb-n13/` | 13 像（真实体系上的图像数鲁棒性） |
| `cli-neb-plan-k/` `cli-neb-statk/` `cli-neb-statk2/` | 动态 PLAN 弹簧 / 静态 1e-2 / 静态 1e-1 |
| `cli-autoneb/` `cli-string/` `cli-gsm/` | AutoNEB（`path_autoneb.xyz` 9 帧、`path_ts_list.xyz` 5 帧）、String、GSM |
| `injections/*.txt` (+ `-ctest.txt`) | 5 项注入的完整单元套件输出与 ctest 结果（红→还原→绿） |
| `unit-suite-landscape-path.txt` | `xtb-tester landscape-path` 全量原始输出（所有量化打印） |
| `ctest-landscape.txt` `ctest-regression.txt` | 68/68 与 12/12 的原始输出 |
| `scripts/leps_reference.py` / `.out` | **独立** Python LEPS 实现 + 参考值输出（§2.1） |
| `scripts/upwind_equivalence.py` / `.out` | upwind vs Eq.11 的非等价性见证 + 单位换算复核（§5、§3.1） |
| `scripts/xyzrmsd.py` | Kabsch 对齐的逐原子 RMSD（§2.3） |
| `scripts/inject_m5.py` | 注入脚本（变异 → 构建 → 测试 → 还原 + md5 校验） |

> 说明：§3.2 的"细扫（1e-4…1e4）"与 §4.2 的 `max_displ=0.03/0.01` 交叉表出自
> **临时探针程序**（同一 `xtb-tester` 套件内的临时用例，交付前已删除）；其结论已由
> `neb-spring-calibration`（1e-5…1e2）与 `band-initial-path-scan`（0.378/0.1）两个**永久用例**
> 覆盖，探针只用于加密采样，未产生任何断言。
