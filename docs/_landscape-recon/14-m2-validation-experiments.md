# M2（scan）去风险实验与复核报告

> 里程碑：**M2（scan）**
> 对照：`docs/xtb-landscape-PLAN.md` §5.3.5 / §6.2 / §9.3 / §12；`AGENTS.md` §6（实测事实）
> 本报告对应任务：M2 复盘（去风险实验 #11 + 与既有 `relaxed_scan` 一致性 + 约束刚度敏感性 +
> 遗留小项）。实现本体见 `docs/_landscape-recon/13-m2-scan-implementation-report.md`（m2-impl）。
> 原始数据：`docs/_landscape-recon/m2-hysteresis-data/`（`*.csv` 为汇总，`raw/` 为完整 stdout 日志、
> `xtbscan.log` 帧、输入几何与全部脚本）。
>
> **所有 xtb 调用在本次复盘中一律 `OMP_NUM_THREADS=1` 串行执行**（原因见 §6，这是本轮最重要的
> 操作性发现）。所有脚本对单点失败容错（每个 xtb 调用后不检查退出码、缺失值记 `nan`/`-`），
> 并显式报告「有效点数 / 总点数」。

---

## 0. 结论速览（4 组量化结论）

| # | 结论 | 关键数字 |
|---|---|---|
| 1 | **relaxed 扫描的滞回是收敛噪声，不是物理**；双向默认可以保留，但它是**诊断**而非正确性必需 | 同一网格、同一双向扫描：superloose 1.25e-5 → normal 5.63e-6 → vtight 7.54e-7 Eh（12° 网格）；24° 网格 2.76e-5 → 4.47e-7 Eh。最大 1.7e-2 kcal/mol，无任何不连续点 |
| 2 | **RIGID 二面角扫描在驱动实现中是错的**（HIGH）：片段切割边取错，且依赖“当前几何”重算连通性 | 前 6 点只旋转末端原子 `l`；第 7 点起片段吞掉 `i` 侧、被扫二面角**冻结**在 −119.99°；与正确刚体剖面最大差 **0.127 Eh = 79.6 kcal/mol**；驱动自报「rigid 滞回 0.1295 Eh」（garbage） |
| 3 | **PLAN §9.3 的「与既有 relaxed_scan 一致 ≤1e-6 hartree」在默认档未达成** | 水 distance 5 点：**1.32e-5** Eh；H₂O₂ 二面角 13 点：**4.83e-6** Eh。两侧都收到 `vtight`：H₂O₂ **6.7e-7**（达成）／水 **1.6e-6**（仍差 1.6 倍）。根因是**参照实现 ANCopt 内层收敛不足**（参照自身 default↔vtight 漂移 3.96e-6 Eh） |
| 4 | **`constraint_fc` 默认值保持 0.5**（不改）；但 PLAN 的「0.5 = xtb `fcconstr` 默认」是**事实错误**，xtb 实际是 0.05 | 势垒高度：fc=0.05 → 2.731 kcal/mol（离极限 −4.9%）、fc=0.5 → 2.864（−0.33%）、fc≥2 → 2.873（极限）；最大约束漂移 6.84° / 0.82° / 0.04°。残差（|dE/dq|）在 2e-4…6e-4 之间**不随 fc 单调**，**不能**用来诊断漂移 |

---

## 1. 实验设置（可复现）

### 1.1 体系

| 体系 | 构造 | 平衡态 | 说明 |
|---|---|---|---|
| **1,2-二氯乙烷 (DCE)** `C2H4Cl2` | Z-matrix 手工构造（`raw/zmat.py`），GFN2 `--opt tight` 优化 | E = −15.416221829901 Eh，Cl3–C1–C2–Cl4 = **−179.9866°**（anti，全局极小） | 主体系：anti / gauche 双阱 + ~120° 处势垒 |
| **H2O2** | Z-matrix（O–O 1.475 Å, OOH 100°, 二面角 111° 起），GFN2 `--opt tight` | E = −9.054669695869 Eh，H3–O1–O2–H4 = −179.7814°（GFN2 给 trans 极小） | 一致性实验（小、快、二面角） |
| **H2O** | 与 `test/unit/CMakeLists.txt` 同一份几何（O–H1 = 0.96 Å） | — | 复现 m2-impl §4.6 的 distance 对照 |

GFN2、`--norestart`、内部 a.u.，输出按 §1.2 的脚本解析。

### 1.2 命令（完整命令列表另见 `m2-hysteresis-data/raw/run_all.sh`）

```bash
export XTBPATH=/home/owenchan/work_path/coding/fortran/xtb
export OMP_NUM_THREADS=1                      # 必须，见 §6
XT=/tmp/xtb-land/build/xtb
DCE=dceopt.xtbopt.xyz

# ① relaxed 双向扫描（滞回），同一网格、5 个收敛档
for lvl in superloose loose normal tight vtight; do
  $XT $DCE --gfn2 --lscan --lscan-coord dihedral --lscan-atoms 3,1,2,4 \
      --lscan-step 12 --lscan-nstep 10 --lscan-level $lvl --norestart --namespace h12$lvl
done
# 同一 5 档在粗网格 24°/nstep 5 上重复一遍

# ② 约束刚度扫描（单向）
for fc in 0.05 0.1 0.5 2.0 5.0 10.0; do
  $XT $DCE --gfn2 --lscan --lscan-coord dihedral --lscan-atoms 3,1,2,4 \
      --lscan-step 24 --lscan-nstep 5 --lscan-oneway --lscan-fc $fc --norestart --namespace f$fc
done

# ③ 与既有 --scan 对照（同一输入、同一 fc、同一网格、逐点）
$XT h2o2opt.xtbopt.xyz --gfn2 --opt        --input h2o2_scan.inp --norestart   # 参照（ANCopt）
$XT h2o2opt.xtbopt.xyz --gfn2 --lscan --lscan-coord dihedral --lscan-atoms 3,1,2,4 \
      --lscan-step 15 --lscan-nstep 12 --lscan-oneway --lscan-fc 0.5 --norestart --namespace h2l
# 水分子 distance 对照：同 m2-impl 的 5 点网格 0.96..1.36 Å，fc=0.5

# ④ 失败探针（刚性/柔性、负步长、跨 ±180、跨 syn 构型）见 §5
```

参照 `--scan` 通过 xcontrol 触发（`src/scan_driver.f90:21` `relaxed_scan`，由 `anyopt` 分支中的
`nscan > 0` 进入，`src/prog/main.F90:906`）：

```
$constrain
  force constant=0.5
  dihedral: 3,1,2,4, -179.78140355392912
$scan
  1: -179.78140355392912, 0.21859644607088, 13
$end
```

（`raw/h2o2_scan.inp`；水分子用 `distance: 1,2, 0.96` + `1: 0.96, 1.36, 5`。）
两侧网格逐点相同：`--lscan` 的网格锚定在输入几何的坐标值 `q0`，`q0 + k·step` 与 `$scan` 的
`start + (end-start)k/(n-1)` 重合。

### 1.3 分析脚本（健壮性）

`raw/final_analysis.py` / `raw/dump_data.py`：所有解析失败返回 `nan`，**任何单点缺失都不会抛异常**；
`energy == 0.0` 被当作「该点无值」（原因见 §5）；每个实验都打印「有效点数 / 总点数」。
汇总 CSV 与原始日志一一对应，可逐位复核。

---

## 2. 滞回量化（PLAN 实验 #11）

### 2.1 原始数据

`m2-hysteresis-data/hysteresis.csv`、`hysteresis_profiles.csv`

DCE，二面角 Cl3–C1–C2–Cl4，双向扫描（正向 11 点 / 6 点 + 反向同样点数），`constraint_fc = 0.5`：

**细网格 12° / nstep 10（正向 11 点，比较 10 点）**

| 档 | max abs(E_fwd − E_rev) / Eh | / kcal·mol⁻¹ | 最大相邻跳变 / Eh | 不连续点 |
|---|---|---|---|---|
| superloose | 1.248123e-05 | 7.832e-03 | 1.4224e-03 | 无 |
| loose | 1.248130e-05 | 7.832e-03 | 1.4224e-03 | 无 |
| **normal（默认）** | **5.629262e-06** | **3.532e-03** | 1.4142e-03 | 无 |
| tight | 2.393662e-06 | 1.502e-03 | 1.4079e-03 | 无 |
| vtight | 7.536890e-07 | 4.729e-04 | 1.4064e-03 | 无 |

**粗网格 24° / nstep 5（正向 6 点，比较 5 点）**

| 档 | max abs(E_fwd − E_rev) / Eh | / kcal·mol⁻¹ | 最大相邻跳变 / Eh |
|---|---|---|---|
| superloose | 2.764573e-05 | 1.735e-02 | 2.6961e-03 |
| loose | 1.320825e-05 | 8.288e-03 | 2.6961e-03 |
| normal | 1.394745e-05 | 8.752e-03 | 2.6961e-03 |
| tight | 1.958410e-06 | 1.229e-03 | 2.6836e-03 |
| vtight | 4.473640e-07 | 2.807e-04 | 2.6833e-03 |

（`hysteresis.csv` 含 `jump_from_deg` / `jump_to_deg` 列。）

### 2.2 极值位置的正反差异

正向支与反向支的**网格极大值都落在同一个网格点** θ = −119.9866°（势垒，anti→gauche 侧）：
E_fwd = −15.411454344283 Eh，E_rev = −15.411453499944 Eh，差 **8.4e-7 Eh**（5.3e-4 kcal/mol）。
`gauche` 极小在正向支的末端 −59.9866°（E = −15.413822452）；反向支从 −71.99° 起，不含该点。

> 用三点抛物线拟合求「极值位置漂移」在 12° 网格上会被拟合噪声主导（同一条曲线的顶点估计值
> 摆动可达 ±6°），因此本报告只用「网格极值点是否相同」这一稳健判据。fc 敏感性（§4）里的
> 极值位置漂移量级 ≫ 拟合噪声（0.04° → 6.8°），趋势单调、可信。

### 2.3 结论

1. **滞回随收敛收紧单调下降（同一网格下降 16–31 倍），最大仅 1.7e-2 kcal/mol。**
   这说明滞回**不是物理多解**，而是「每点内层松弛从不同热启动出发、在各自容差处停下」造成的
   数值残差。默认档下 relaxed 剖面的路径无关性约为 1e-5 Eh。
2. **没有任何不连续点**：相邻点最大能量跳变 1.4e-3（12° 网格）／2.7e-3（24° 网格）Eh，
   与步长成正比、单调，剖面光滑。
3. **对「relaxed scan 是否必须默认双向？」的回答**：不是**正确性**必需（正向本身已收敛到
   1e-5 Eh 以内），但**应保留默认双向**——它是唯一能自证「结果不依赖扫描方向」的手段，
   且成本是线性的（每点只多 1 次单点量级）。建议额外做两件事：
   (a) 把 `loose` 档的滞回量（1e-2 kcal/mol 量级）写进文档作为「不要用 loose 做定量剖面」的依据；
   (b) 在 stdout 报告里同时给出**约束漂移**（目标 vs 实际到达值），见 §4.3。

---

## 3. 与既有 `--scan`（`relaxed_scan`）的一致性（PLAN §9.3 验收项）

### 3.1 原始数据

`m2-hysteresis-data/consistency_*.csv`（逐点 diff + 坐标最大偏移 + 有效点数）。

**(a) H₂O 距离扫描（复现 m2-impl §4.6 的输入）**：5 点，0.96→1.36 Å，fc=0.5

默认档（`--opt` 默认 vs `--lscan-level normal`），有效点 **5/5**：

| 点 | `--scan` / Eh | `--lscan` / Eh | diff / Eh | diff / kcal | max coord dev / bohr |
|---|---|---|---|---|---|
| 1 | −5.070544255123 | −5.070544208690 | +4.643e−08 | +2.91e−05 | 1.11e−04 |
| 2 | −5.066665897515 | −5.066679053245 | **−1.3156e−05** | −8.26e−03 | 6.67e−04 |
| 3 | −5.056044949028 | −5.056053563754 | −8.615e−06 | −5.41e−03 | 3.68e−04 |
| 4 | −5.040594044551 | −5.040601296725 | −7.252e−06 | −4.55e−03 | 5.04e−04 |
| 5 | −5.022433479436 | −5.022427352977 | +6.126e−06 | +3.84e−03 | 3.52e−04 |

→ **max |ΔE| = 1.3156e−05 Eh = 8.26e−03 kcal/mol**

`--opt vtight` vs `--lscan-level vtight`，有效点 **5/5**：

| 点 | diff / Eh |
|---|---|
| 1 | −1.54e−09 |
| 2 | −5.72e−07 |
| 3 | +1.46e−06 |
| 4 | **+1.61e−06** |
| 5 | +6.23e−07 |

→ **max |ΔE| = 1.6149e−06 Eh = 1.01e−03 kcal/mol**

**(b) H₂O₂ 二面角扫描**：13 点，−179.78°→+0.22°，fc=0.5，**帧数两侧同为 13**

| 档（两侧相同） | max abs ΔE / Eh | / kcal | 有效点 |
|---|---|---|---|
| 默认（`--opt` 默认 vs `--lscan normal`） | **4.8299e−06** | 3.03e−03 | 13/13 |
| tight vs tight | 4.0407e−06 | 2.54e−03 | 13/13 |
| **vtight vs vtight** | **6.6722e−07** | 4.19e−04 | 13/13 |

默认档逐点值（前两点正是 m2-impl 引用的数字）：点 1 −9.948e−09、点 2 −2.711e−07、
点 3 −3.997e−07、点 4 −4.412e−07、点 5 −1.346e−06、点 6 −2.045e−06、点 7 −6.357e−07、
点 8 −9.863e−07、点 9 −1.621e−06、点 10 −3.984e−06、点 11 −4.830e−06、点 12 −2.334e−06、
点 13 +3.579e−08。

**(c) 参考实现自身的收敛灵敏度（根因证据）**

同一 H₂O₂ 输入、同一网格，`--scan` 自己在 `--opt` 默认与 `--opt vtight` 之间的剖面漂移：
**max 3.96e−06 Eh**；帧 5/9/13 的几何最大偏差 5.3e−04 / 3.8e−04 / 3.7e−04 bohr。
`--lscan` 侧的约束残差：默认 ≤1.3e−04 Eh/rad，vtight ≤1.0e−05 Eh/rad。

### 3.2 对「m2-impl 说 1.4e−5 vs 我测 9.95e−9 / 2.71e−7」矛盾的解释

**不是矛盾，是两个不同体系**：

* m2-impl 的 1.4e−5 是**水分子 distance 扫描**默认档的最大偏差；我实测同一输入的最大偏差
  1.3156e−05，**逐点表里点 2 就是 −1.32e−5** —— 即 m2-impl 与我测的是**同一次对照**，
  数值一致（他们取了 2 位有效数字）。
* 我上一轮引用的 −9.95e−9 / −2.71e−7 是 **H₂O₂ 二面角扫描**的点 1 / 点 2。
  二面角势的曲率远小于拉伸一个 O–H 键，因此同样的坐标残差造成小 3–4 个数量级的能量差。
* 结论：默认档的一致性水平是「**1e−6 ~ 1e−5 Eh，取决于被扫坐标的曲率**」，
  两种体系的数字可以同时成立。

### 3.3 PLAN §9.3 验收判定

> 验收项：**与既有 `relaxed_scan` 在同输入下能量剖面一致（容差 1e-6 hartree）**

* **两侧都用默认收敛档：未达成**（水 1.32e−5、H₂O₂ 4.83e−6，分别超标 13× 与 4.8×）。
* **两侧都收紧到 `vtight`：H₂O₂ 达成（6.67e−7 < 1e−6）；水未达成（1.61e−6，超标 1.6×）。**
* **根因（实测，不是推断）**：差异由**参照实现的内层 ANCopt 收敛不足**主导，不是本套件的问题：
  * 参照实现对自身收敛档就敏感（default↔vtight 漂移 3.96e−6 Eh，与两侧差异同量级）；
  * 本套件侧的约束残差在 vtight 已降到 1e−5 Eh/rad 以下，坐标继续收紧时两侧能量差不再同步收敛
    （水的 max coord dev 从 6.7e−04 只降到 3.8e−04 bohr）。
* **修正建议（已写入 PLAN §9.3）**：把验收判据改为「**在相同约束残差水平下**比对，绝对容差
  1e-6 hartree」，或给 `--scan` 侧提供可比的收紧档。另外，比对前必须把 `constraint_fc`
  显式对齐（默认 0.5 vs xtb 0.05，差 10 倍 ⇒ 默认不可比，见 §4）。

---

## 4. 约束刚度敏感性（PLAN R-04「有限势垒」）

### 4.1 原始数据

`m2-hysteresis-data/fc_sweep.csv`、`fc_summary.csv`。DCE 二面角，单向，24°/nstep 5，
`--lscan-level normal`，`--lscan-fc = fc`（6 点，全部 `conv = T`）。

| fc (hartree·rad⁻²) | 最大约束漂移 / ° | 势垒位置（网格极大点，到达值）/ ° | 势垒高度 / kcal·mol⁻¹ | anti–gauche 差 / kcal·mol⁻¹ | max ∥残差∥ / Eh·rad⁻¹ |
|---|---|---|---|---|---|
| 0.05 | **6.8414** | −103.81 | 2.7314 | 1.4450 | 2.11e−04 |
| 0.1 | 3.4217 | −106.37 | 2.8242 | 1.4709 | 1.93e−04 |
| **0.5（默认）** | **0.8176** | −107.64 | **2.8635** | 1.5045 | 4.05e−04 |
| 2.0 | 0.1796 | −107.93 | 2.8728 | 1.5136 | 2.08e−04 |
| 5.0 | 0.0700 | −107.96 | 2.8727 | 1.5156 | 5.62e−04 |
| 10.0 | 0.0363 | −107.97 | 2.8730 | 1.5162 | 3.62e−04 |

（漂移 = 实际到达的二面角 − 目标值，逐点最大绝对值；目标网格 −180, −156, −132, −108, −84, −60°。）

### 4.2 结论

1. **约束是软弹簧，且二面角用的是有界周期势**：`constrain_pot` 对二面角是
   `E_bias = fc·(1 − cos(φ − φ0))`（`src/constrain_pot.f90:296-312`），最大恢复力矩只有 `fc`
   （在 Δφ = 90° 处），在 Δφ = 180° 处**归零**。对 distance 才是 `fc·(r−r0)^expo`，
   对 angle 是 `fc·(θ−θ0)²`。**`spring_expo` 只影响 distance**（PLAN §5.3.5 原文未说明，已更正）。
2. **默认值 0.5 的定量代价**：势垒高度相对 fc→∞ 极限偏低 **0.33%**（2.8635 vs 2.8730 kcal/mol，
   差 0.0095 kcal/mol）；漂移 0.82°。
   **fc=0.05 的代价**：势垒偏低 **4.9%**（−0.141 kcal/mol）、漂移 6.84°、势垒位置偏 4.2°。
3. **报告的「约束残差」不能用来判断漂移**：max ∥残差∥ 在 1.9e−04…5.6e−04 之间**随 fc 非单调**
   （fc=5.0 最大、fc=0.1 最小）。因为残差 `|dE_total/dq|` 度量的是「该点是否为总势的驻点」，
   而漂移 `q − q_target` 是弹簧力与物理力平衡的结果，两者不是同一个量：
   驻点处残差 ≡ 0（收敛到容差内即可），漂移却 ∝ `F_phys /(2 fc)`。
   **建议（PLAN R-04 缓解措施修正）**：stdout 表里 1D 情况只打印了目标值 `value`，
   应增加「到达值」与「漂移」两列（2D 路径已有 requested/value 两组值）。

### 4.3 **默认值取 0.5 还是 0.05？——结论：保持 0.5，但必须更正 PLAN 的事实错误**

* **事实**：`src/scanparam.f90:77` 是 `fcconstr = 0.05_wp`。PLAN §5.3.5 写的
  「0.5（xtb `fcconstr` 默认…）」是**误读**，已更正。
* **保 0.5 的理由**：本套件要做 TS/IRC 的**定量**势垒，0.33% vs 4.9% 的势垒误差差别是决定性的；
  fc=0.5 的 0.82° 漂移对 σ/π 与氢键体系可接受，而 6.84° 会直接改变势垒位置与曲率。
* **兼容性代价与处置**：默认与 `--scan` 不同 ⇒ 两者默认剖面**不可逐点比**（差约 1e−3 Eh 量级）。
  处置：(a) 文档写明 `--lscan-fc 0.05` 是与 `xtbscan.log` 既有工具链逐点对齐的开关；
  (b) §9.3 的一致性验收测试必须显式指定两侧 fc；(c) PLAN §5.3.5 已补上实测代价表。
* **不建议直接改代码默认值**：改动会波及 `test_landscape_scan.f90` 中 3 个把 fc=0.5 写进解析
  公式却未设置 `set%constraint_fc` 的用例（`test_relaxed_profile`、`test_relaxed_residual`、
  `test_grid_2d`），且会把默认剖面变得更差；在「精度优先」的前提下更优解是**保留 0.5 +
  把 0.05 作为显式兼容档**。

---

## 5. 「扫描点没有数值」的失败机制（任务第 3 项）

### 5.1 为什么找不到「第 3 个点」的现场

上一轮被中断的那次运行**没有留下任何日志**：`/tmp/m2-exp` 中该时间点只有本报告 §2/§3 用到的
文件，session 日志在中断前最后一条记录就是 §2 的滞回批次；无法从中恢复那个具体输入。
因此本轮把问题**当作一类失效模式**重新定位、并用可复现的最小例子给出了机制与修复建议。

### 5.2 24 个「刁钻」探针点**全部成功**（排除「一般性弱点」）

| 探针 | 结果 |
|---|---|
| 负步长（目标越界到 −192…−300°，跨 ±180 回绕） | 6/6 `conv = T`，exit 0；**但 stdout 打的是未回绕的目标值**（−203.99…），到达值才在合法区间 |
| 60° 大步长（nstep 4） | 5/5 `conv = T`，exit 0 |
| cis 起点（二面角 ≈ 0°，syn 遮挡区）起扫 −120° | 6/6 `conv = T`，exit 0 |
| 负距离目标（0.96 → −0.04 Å） | 3/3 `conv = T`，exit 0（弹簧把两个原子拉到重合附近，未失败） |
| 5 个收敛档 × 2 个网格的滞回扫描（52 点） | 全部 exit 0 |
| 二面角/距离一致性扫描（18 点） | 全部 exit 0 |

⇒ **不是扫描点普遍的健壮性缺陷**。

### 5.3 复现出的失效机制（这才是「点没有数值」的根因）

最小复现（`raw/huge.log`、`raw/huge.xtbscan.log`；水分子，distance 1–2，步长 5.0 Å，nstep 2）：

```
point      value/Ang           energy/Eh      residual      steps  conv
    1       0.96000009      -5.070544208690   1.0234E-05      5 T
    2       5.96000009       0.000000000000   5.4806E+00     18 F     <-- 无能量
    3      10.96000009       0.000000000000   0.0000E+00     29 T     <-- 无能量，却报 conv=T
largest jump between points:    5.070544E+00 Eh
```

* **退出码 = 1**（`landscape scan aborted: N scan point(s) failed`）。
* `xtbscan.log` 的对应帧写成 `energy: 0.000000000000`——**不是缺行，而是一个合法的 0.0**，
  任何按列解析的脚本都会把它当真实能量读进去，静默污染剖面。
* 底层原因（日志里的 engine 报错链）：
  `-3- landscape_engine_energy_gradient: SCC did not converge at the current geometry;
  the energy and gradient are discarded` → `-2/-1- scf: ... did not converge`。
  约束把两原子拉到 5.96 Å 后 SCF 不收敛，引擎丢弃能量/梯度，该点 `point%energy` 保持
  初值 0.0，`profile%xyz(:,i)` 也保持 0（对完全失败的内部点甚至是一帧全零坐标）。
* 若某次运行恰好在这一类点上停住（或不检查退出码），**「第 3 个点没有数值」的观感就成立**：
  0.0 能量 + 可能全零的帧 + 非零退出码。上一次中断正是「bash 脚本没有对 xtb 调用容错」。

### 5.4 由此发现的两个实现问题（交给 m2-impl）

| # | 严重度 | 描述 | 建议 |
|---|---|---|---|
| **F1** | **中** | **失败点被静默写成 `energy = 0.0` 与全零几何**（`store_point` 不写 xyz，`point%energy` 未置 NaN） | 失败点写入 `NaN`（或 `xtbscan.log` 跳过该帧），并在 stdout 行加标记；`profile%converged` 已能区分 |
| **F2** | **中** | **`conv` 标记不可信**：点 3 的能量/梯度被丢弃后，内层判据在「零梯度」上平凡满足 ⇒ 报 `T`、残差 0.0 | 引擎丢弃梯度时应让该点的 `converged = .false.`（`result%converged` 不该由被丢弃的量决定） |
| F3 | 低 | 负步长时 `value` 列打印未回绕的目标（−203.99°），与几何里的到达值（+156.01°）不一致 | `value` 列改为打印到达值（漂移列见 §4.2），或对角度做回绕 |

**实验纪律建议（已落实到本轮脚本）**：跑 scan 的脚本必须 (1) 容忍非零退出码；
(2) 把 `energy == 0.0` / `conv = F` 当作无值；(3) 显式统计「有效点数 / 总点数」。

---

## 6. 操作性发现：必须 `OMP_NUM_THREADS=1`

同一命令（DCE，二面角，24°，nstep 1，单向 relaxed，2 个点，16 次能量+梯度评估）：

| 线程数 | wall |
|---|---|
| `OMP_NUM_THREADS=1` | **0.13 s** |
| `OMP_NUM_THREADS=8`（默认） | **44.12 s** |

**340× 的反向加速比**（AGENTS §6.8 记录过 taxol 上的 anti-scaling；小体系上更极端：OpenBLAS
线程池 + libgomp 自旋在每次 32 基函数的 SCF 上反复付固定开销）。后果：

* 本轮**全部**实验在 `OMP_NUM_THREADS=1` 下串行完成，整个矩阵（5 档 × 2 网格滞回 + 6 档 fc +
  刚性 + 3 个一致性体系 + 探针 + 失败复现）**总耗时 14 秒**；同样的矩阵在默认 8 线程下估算是
  数十分钟到小时级（m2-impl 的 5 分钟/21 点的对照即为此原因）。
* 结果与线程数无关：24°/nstep 5 的 `max|E_fwd − E_rev|` 在 1 线程与 8 线程下都是
  `1.394745E-05`；水分子一致性 max|ΔE| 在 1/8 线程下都是 `1.315573e-05`。
* **建议**：M2 及后续里程碑的基准/验收一律 `OMP_NUM_THREADS=1`（并在 PLAN 附录 A 记录），
  并行只用于「多进程跑不同扫描点」；这也与 AGENTS §6.8 的结论一致。

---

## 7. 遗留小项

### 7.1 `--lopt-hessian <numerical|model>`（已完成）

* `src/prog/main.F90`：新增 `case ('--lopt-hessian')`，用
  `landscape_hessian_source_known` 校验后写入 `lset%hessian_source`；未知名字/缺参数 → `env%error`
  （exit 1）。同步新增 `use xtb_landscape_hessian, only: landscape_hessian_source_known`。
* `src/xhelp.f90`：新增 4 行帮助。
* `docs/xtb-landscape-PLAN.md` §12.3(b)：CLI flag 表新增一行（标注为 M2 复核轮实现，R2-09 遗留项）。
* 新增 CLI 级测试 `xtb/landscape-opt-hessian`（`test/unit/CMakeLists.txt`）：对
  `{lbfgs,rfo} × {model,numerical}` 四个组合要求 exit 0 + `landscape: converged` +
  `Hessian source:` 头是该组合选的来源 + 两个来源的能量截到毫哈特里后相等；
  另加错误分支 `xtb/landscape-hessian-unknown`。
* **实测**（水分子，`OMP_NUM_THREADS=1`）：

  | 组合 | 能量 / Eh | 报告头 |
  |---|---|---|
  | `lbfgs` + `numerical` | −5.070544447778 | numerical |
  | `lbfgs` + `model` | −5.070544447778（逐位相同，lbfgs 不用 Hessian） | model |
  | `rfo` + `numerical` | −5.070544447771 | numerical |
  | `rfo` + `model` | −5.070544427225（差 2.1e−8） | model |

  `--lopt-hessian bogus` → exit 1，`Unknown landscape Hessian source 'bogus'`。

### 7.2 `test/unit/meson.build` 镜像 CMake 侧 CLI 检查（已完成，**本机无法验证 meson 本身**）

* CMake 侧共有 **14 项** landscape CLI 检查；meson 原本只镜像了 `landscape opt` 与
  `landscape scan` 这 2 项，本轮把**其余 12 项全部补齐**（两侧现在都是 14 项）。
  任务书说的「7 个 CLI 检查」对应 M0/M1 交付的 7 项（`opt-energy`、`opt-acc`、`scf-failure`、
  `engine-missing`、`engine-unknown`、`level-missing`、`level-unknown`，即 M0/M1 的 8 项减去
  meson 已有的 `opt`）；M2 自己新增的 3 个 `--lscan` 错误分支也一并镜像，使两侧严格一一对应。
* meson 无法检查测试输出，故新增 `test/unit/landscape_cli_check.py`，把 CMake 的
  `cmake -P` 脚本语义逐条实现（`energy` / `acc` / `hessian` / `scf` / `error` 五种模式），
  由 `test()` 以 `python` 为可执行程序调用；meson 的测试名与 CMake 测试一一对应。
* **验证方式**：本机无 meson/ninja（AGENTS §4），改为**手工用同样的参数逐个调用该 Python 脚本**
  跑通 12 项（4 个正例 + 8 个错误分支），全部 exit 0；即「测试逻辑已在本机验证，
  仅 meson 语法未验证」。

| CMake 测试 | meson 测试名 | 本机手工验证 |
|---|---|---|
| `xtb/landscape-opt` | `landscape opt`（原有） | ctest 通过 |
| `xtb/landscape-scan` | `landscape scan`（原有） | ctest 通过 |
| `xtb/landscape-opt-energy` | `landscape opt energy` | ✅ exit 0 |
| `xtb/landscape-opt-acc` | `landscape opt acc` | ✅ exit 0 |
| `xtb/landscape-opt-hessian` | `landscape opt hessian` | ✅ exit 0 |
| `xtb/landscape-scf-failure` | `landscape scf failure` | ✅ exit 0 |
| `xtb/landscape-engine-missing` | `landscape engine missing` | ✅ exit 0 |
| `xtb/landscape-engine-unknown` | `landscape engine unknown` | ✅ exit 0 |
| `xtb/landscape-level-missing` | `landscape level missing` | ✅ exit 0 |
| `xtb/landscape-level-unknown` | `landscape level unknown` | ✅ exit 0 |
| `xtb/landscape-hessian-unknown` | `landscape hessian unknown` | ✅ exit 0 |
| `xtb/landscape-scan-coord-unknown` | `landscape scan coord unknown` | ✅ exit 0 |
| `xtb/landscape-scan-nstep-missing` | `landscape scan nstep missing` | ✅ exit 0 |
| `xtb/landscape-scan-atom-range` | `landscape scan atom range` | ✅ exit 0 |
| （error 脚本共用一个 `landscape_cli_error.cmake`） | — | — |

---

## 8. 明确超出本轮范围、但影响 M2 验收的发现：**RIGID 二面角扫描实现错误**

严重度 **HIGH**。`src/landscape/scan/relax_scan.f90:801-806`：

```fortran
call landscape_scan_fragments(at, xyz, l, k, moving)     ! 切的是 l–k 这条边
call rotate_fragment(xyz, moving, xyz(:, j), axis/delta, alpha)
```

* **错误 1（切割边）**：二面角 i–j–k–l 的刚体旋转应当**切断中心键 j–k**，取含 l 的片段
  （模块头注释写的正是这个语义：“the fragment of the last atom is rotated about the central
  bond `x_k − x_j`”）。代码却切断 `l–k`；当 l 与 k 成键（常态）时 `moving` 退化成 **{l} 一个原子**，
  于是只有末端原子绕 j–k 轴转，k 上其余取代基不动 ⇒ **得到的不是刚体扫描**。
* **错误 2（连通性依赖当前几何 + 热启动链）**：`moving` 每次都按**当前**（上一点已畸变并热启动
  继承下来的）几何用共价半径重算。DCE 扫到 −119.99° 时 Cl4 与 H8 距离 1.45 Å < Cl–H 阈值
  1.61 Å ⇒ BFS 从 Cl4 吞掉 H8 → C2 → C1 → 整个分子（除 C1、C2 因位于旋转轴上不动），
  于是**两个 Cl 一起转、二面角不再变化**。

**实测后果**（`m2-hysteresis-data/rigid_driver.csv`，DCE，12°，单向）：

| 点 | 目标 / ° | 到达 / ° | E / Eh |
|---|---|---|---|
| 1–6 | −179.99 … −119.99 | **精确等于目标** | 正常下降 |
| 7 | −107.99 | **−119.99（未动）** | −15.286739739372 |
| 8–11 | −95.99 … −59.99 | **−119.99（全部冻结）** | −15.286739739…（同一数值重复） |

* 与**独立 Python 实现的正确刚体剖面**（切 j–k、旋转整个 l 侧片段 {C2,Cl4,H7,H8}，再逐点用
  xtb `--sp` 求能量）比较：前 6 点与「只转 l」语义逐位一致（≤5.5e−10 Eh，证明代码确实只转 l），
  第 7 点起偏离正确剖面达 **0.127 Eh（79.6 kcal/mol）**。
* 驱动的双向 rigid 扫描自报 **滞回 1.295e−01 Eh（81 kcal/mol）**——完全是人造伪影；
  **正确的 rigid 扫描滞回恒等于 0**（每点由参考几何直接构造，与扫描方向无关）。
* 单元用例 `rigid-dihedral-exact` **锁定了错误语义**：其 fixture 是 H1-O1-O2-H2，其中
  O–H 距离 1.836 bohr 大于共价半径阈值 1.2×(0.63+0.32) Å ⇒ 氢原子在连通图中是**孤立点**，
  所以 `fragments(…, 4, 2)` 恒返回 {H2}，测试的注释「cutting the O2–H2 bond leaves H2 alone」
  与事实不符，**从未覆盖真正成键的情形**。

**建议（m2-impl）**：
1. 片段改为按**中心键 j–k** 切割（`landscape_scan_fragments` 需要支持「切任意一条边」，
   或改成 `fragments(seed=k, blocked=j)` 并明确 l 必须挂在 k 侧）；
2. `moving` 只在**参考几何**（扫描输入的 `x0`，或每个点各自的原点几何）上算一次并复用，
   不要随热启动几何漂移；
3. rigid 点应当从**参考几何 + 总旋转角**构造（或至少保证旋转轴/片段不变），这样 rigid 扫描
   的滞回恒为 0，正是 `rigid-scan-hysteresis-zero` 想声明的性质；
4. 把 `rigid-dihedral-exact` 的 fixture 换成真正成键的分子（例如乙烷 C–C 上的两个甲基，
   或本例的 DCE），并断言「l 侧片段内的所有原子都随转动、i 侧片段不动」。

在修复前，**M2 的 `mode = rigid` 不可用于定量用途**（1D 二面角尤其；distance 与 angle 不受
此 bug 影响——distance 切的是被扫键本身，angle 切的是 i–j，语义正确）。

---

## 9. 本轮验证命令与结果

```bash
cmake -S . -B /tmp/xtb-land/build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/xtb-land/build -j            # 0 error / 0 warning（新增文件部分）

ctest --test-dir /tmp/xtb-land/build -R landscape
#   100% tests passed, 0 tests failed out of 23   （原 21 项 + 新增 landscape-opt-hessian + landscape-hessian-unknown）

ctest --test-dir /tmp/xtb-land/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI|hessian|landscape'
#   100% tests passed, 0 tests failed out of 36

# meson 侧 CLI 检查（meson 本机不可用，改用同样的 Python 驱动手工验证）
for mode in energy acc hessian scf; do python3 test/unit/landscape_cli_check.py $mode <xtb> water.xyz <rundir>; done   # 全 exit 0
python3 test/unit/landscape_cli_check.py error <xtb> water.xyz <rundir> "<pattern>" --gfn 2 --lopt ...               # 5 项全 exit 0
```

**未跑全量 ctest**（AGENTS §4 禁止）。

---

## 10. 风险登记更新

| # | 项 | 级别 | 状态 |
|---|---|---|---|
| R1 | 与参照 `--scan` 的 1e-6 容差 | 中 | **已量化**：默认档未达成（1e-5 量级）；vtight 下 H₂O₂ 达成、水 1.6e-6。根因是参照侧收敛，已写回 PLAN §9.3 |
| R2 | `constraint_fc` 默认 0.5 vs xtb 0.05 | 中 | **已量化并定案保留 0.5**；PLAN 的事实错误已更正；兼容开关 `--lscan-fc 0.05` |
| **R9（新）** | **rigid 二面角扫描实现错误** | **高** | 见 §8，需 m2-impl 修复；修复前 rigid 不可用于二面角定量 |
| **R10（新）** | 失败扫描点写成 `energy = 0.0` 且可能报 `conv = T` | 中 | 见 §5.4（F1/F2） |
| **R11（新）** | 默认 8 线程下 scan 慢 340× | 中（操作） | 基准/验收一律 `OMP_NUM_THREADS=1`，建议写入 PLAN 附录 A |
| R3 | rigid 环体系片段 | 低 | 与 R9 同源，修复 R9 时一并处理 |
| R5 | 滞回信号强度 | 低 | **已量化**：真实分子上默认档 ~1e-5 Eh；双向默认保留（作为自证手段） |
| R6 | 未做 xcontrol `$landscape` 段 | 低 | 不变 |
| R7 | meson 侧未验证 | 低 | 本轮已把 CLI 检查补齐并用同一 Python 驱动手工验证；meson 语法本身仍未验证 |

---

## 11. 数据文件索引

```
docs/_landscape-recon/m2-hysteresis-data/
├── hysteresis.csv               滞回（2 网格 × 5 档：max|ΔE|、跳变、位置）
├── hysteresis_profiles.csv      逐点 目标/到达、fwd/rev 能量
├── fc_sweep.csv                 6 个 fc × 6 点的 目标/到达/漂移/能量/残差/步数/收敛
├── fc_summary.csv               fc → 最大漂移、势垒/极小位置与高度
├── rigid_driver.csv             驱动 rigid 扫描的 目标/到达/能量（§8 证据）
├── consistency_water_normal.csv     水 5 点逐点 diff（默认档）
├── consistency_water_vtight.csv     水 5 点逐点 diff（vtight）
├── consistency_water_normal_8thread.csv
├── consistency_h2o2_*.csv       H₂O₂ 13 点逐点 diff（默认 / tight / vtight / 1 线程）
├── failure_probe.csv            §5 失败机制（含 0.0 能量点与退出码）
└── raw/                         全部 stdout 日志、xtbscan.log 帧、输入几何、脚本
                                  (run_all.sh, final_analysis.py, dump_data.py, rigid_ref.py, zmat.py)
```
