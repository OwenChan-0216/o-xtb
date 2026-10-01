# 28 — M4 验证实验报告（P-RFO / B-PRFO / Dimer）

> 输入：`docs/xtb-landscape-PLAN.md` §6.3 / §6.7 / §7 / §8.2（#3/#4/#5）/ §9.5 / §12.11；
> `AGENTS.md` §4/§5/§6；实现报告 `26-m4-saddle-implementation-report.md`、
> `27-m4-dimer-implementation-report.md`；M3 实测 `21-m3-validation-experiments.md`、
> 复核 `22/24/25`。
> 角色：**验证者**（不改动 `src/` 生产逻辑；本报告只做实验与结论，发现的 bug 交由后续修复轮）。
> 数据：`docs/_landscape-recon/m4-saddle-data/`（195 个文件，见 §9）。
> 纪律：全部 xtb/ctest 调用 `OMP_NUM_THREADS=1`；只跑 `-R landscape` 与回归子集。

---

## 0. 结论摘要

| 实验 | 结果 | 判定 |
|---|---|---|
| **#3 `etemp`**（真实 TS，弯曲 HCN） | 起点最低 3 本征值：0 K / 300 K **逐位相同**；1000 K 差 3e-4 cm⁻¹；**5000 K 差 80.7 cm⁻¹（−7.5 %）**。收敛路径 4→5 步；TS 几何 RMSD（300 vs 5000 K）**6.97e-3 bohr**；虚频 **−1426.11 → −1455.41 cm⁻¹**。 | **硬约束 1 成立且必要**（冻结 + 记录）。 |
| **#4 梯度噪声 σ_g** | 冷启动同位相等（0）；同进程多线程重复 **≤1.16e-15 Eh/bohr**；跨 `OMP_NUM_THREADS` **≤1.11e-15**；warm-restart **3.916e-7**（系统偏置）。可达力下限：M4 搜索实测最终 `gmax` **1.0e-6 … 2.1e-6**（P-RFO/B-PRFO），dimer `1.08e-4`。 | **`normal`（g_rms=1e-4）可达，不回退**；`[待校准]` 力阈值关闭。 |
| **#5 L1 解析面** | 解析鞍点 (−0.82200156, 0.62431280)，E=−0.0648035531 Eh，本征值 −1.196576/+0.781248。prfo vs bprfo **RMSD 6.30e-6**；dimer vs prfo **7.82e-5**；到解析鞍点距离 9.96e-6 / 1.06e-6 / 1.12e-4 bohr。 | **验收（<1e-3 bohr）以 >10× 裕度通过**。 |
| **#5 L2 真实 GFN2** | HCN→HNC：prfo 4 步 / bprfo 6 步 / dimer 39 步（random）与 38 步（force），全部 **恰好 1 个虚频**；prfo vs bprfo 对齐 RMSD **7.7e-6**，dimer vs prfo **1.17e-4 / 2.03e-4**。 | **两方法落到同一鞍点**。 |
| 失效模式 | 模态切换守卫**实测触发**（overlap .9831 < .99）；>1 负本征值几何（拉伸 H₂O）找到并实测 hlow；trust 过大未复现（被 trust_max 自限）；**发现 2 条新缺陷**（§7）。 | 见 §7。 |
| 可证伪性注入 | 4 项注入全部令断言变红并已还原（§6）。 | 通过。 |

**发现（详见 §7）**：**V1（MEDIUM，M3 范围，影响 M4 确认）** 线性分子的频率分析把
“低于阈值的最负本征值”当作零模吞掉 —— 线性水（2 重简并虚弯曲）被报成 **0 虚频**；
**V2（MEDIUM）** P-RFO 的 `lifted` 诊断/警告被数值刚体模噪声（~1e-11）**每步触发**，使
文档中「>1 负本征值」的防护无法被区分，且默认 `hlow=1e-2` 实际改变收敛路径（4→6 步）；
**V3（MEDIUM）** `--lts` 收敛到**极小点**（0 虚频）时仍以退出码 0 + “converged” 报告成功。

---

## 1. 环境与方法

| 项 | 值 |
|---|---|
| 二进制 | `/tmp/xtb-land/build/xtb`（Release，`WITH_TBLITE=OFF WITH_CPCMX=OFF WITH_TESTS=ON`；HEAD `18c08d9` + 未提交的 M4 工作区改动） |
| 线程 | `OMP_NUM_THREADS=1`（AGENTS.md §4） |
| 方法 | GFN2-xTB，全部 `--norestart` |
| 体系 | HCN（弯曲 TS 起点，`/tmp/hcn.xyz`：H(0,1.05,0) C(0,0,0) N(1.156,0,0)，单位 Å）；HNC 线性产物；拉伸 H₂O；线性 H₂O；解析 Müller-Brown 二维面 |
| 单位 | 输入 `.xyz` 为 Å；报告内坐标一律 bohr（1 Å = 1.8897 bohr）；能量 hartree；曲率 Eh/bohr²；频率 cm⁻¹ |

本轮**未修改任何 `src/` 生产逻辑**（§6 的 4 次注入全部还原，`diff` 校验一致，见 §6.5）。
为测量 σ_g 的跨线程噪声与打印解析面收敛点，对**测试文件**做了两处纯打印扩展（§8）。

---

## 2. 实验 #3（M4 gate）：`etemp` 对曲率 / 鞍点的影响

### 2.1 TS 起点的最低 3 个本征值（`--lvib`，g98.out 4 位小数，cm⁻¹）

数据：`m4-saddle-data/exp3-etemp/vib_etemp{0,300,1000,5000}/`。

| `etemp` / K | 最低 3 个内模 / cm⁻¹ | 相对 300 K 的最大偏差 | 虚频数 |
|---|---|---|---|
| 0 | −1076.9672  2305.6011  3296.8411 | 0（逐位相同） | 1 |
| **300（默认）** | **−1076.9672  2305.6011  3296.8411** | — | 1 |
| 1000 | −1076.9671  2305.6009  3296.8408 | 3e-4 | 1 |
| **5000** | **−996.2635  2291.8547  3276.5269** | **80.70（7.5 %）** | 1 |

结论：弯曲 HCN 是**闭壳层**体系，但 5 000 K 时 Fermi 展宽（0.43 eV）已足以让最低
曲率漂移 **80.7 cm⁻¹**；0/300 K 完全无响应（逐位相同），1000 K 起才可见（3e-4 cm⁻¹）。
这与 M3 报告 21 §B（拉伸 H₂ −31.4 %）方向一致，量级更温和但**同样不可忽略**。

### 2.2 `--lts` 端到端（prfo / bprfo × 4 个 `etemp`）

数据：`exp3-etemp/ts_{prfo,bprfo}_etemp{0,300,1000,5000}/`（含 stdout、exit、xtbts.xyz/log）。

| `etemp` / K | prfo 步数 | bprfo 步数 | prfo 虚频 / cm⁻¹ | bprfo 虚频 / cm⁻¹ | 全部收敛 |
|---|---|---|---|---|---|
| 0 | 4 | 6 | −1426.11 | −1426.12 | T T T T |
| 300 | 4 | 6 | −1426.11 | −1426.12 | T T T T |
| 1000 | 4 | 6 | −1426.11 | −1426.12 | T T T T |
| 5000 | **5** | 6 | **−1455.41** | **−1455.41** | T T T T |

几何差（原始 / Kabsch 对齐，bohr）：

| 对比 | 原始 RMSD | 对齐 RMSD | 能量差 / Eh |
|---|---|---|---|
| prfo etemp 300 vs 1000 | 1.38e-9 | 1.38e-9 | +4.2e-11 |
| prfo etemp 300 vs 5000 | **6.97e-3** | 6.97e-3 | **−1.276e-3** |
| prfo vs bprfo etemp 300 | 6.05e-4 | **7.7e-6** | — |
| prfo vs bprfo etemp 5000 | 6.55e-4 | **2.5e-6** | — |

注：prfo/bprfo 的**原始** RMSD（~6e-4）几乎全部来自坐标系整体旋转，对齐后跌到 1e-5 量级；
300 vs 5000 K 的差异是真实 PES 形变（不可用对齐消除）。

### 2.3 硬约束 1（冻结 + 记录）验证

`ts_prfo_etemp5000/stdout.txt` 同时打印：

```
 electronic temperature:       5000.000 K (frozen for the whole run)
 landscape engine: etemp                  5000.000 K
```

四条 `--lts`/CLI 测试 `xtb/landscape-ts-etemp` 断言该两条一致（注入式锁，见 §6 与报告 26）。
**结论**：`etemp` 在一次运行内恒定且实际生效值被记录 —— **硬约束 1 满足**；同时实验 3
表明 5 000 K 时**必须**冻结（否则几何/虚频不可复现）。

---

## 3. 实验 #4（M4 gate）：梯度噪声 σ_g vs 力阈值可达性

数据：`m4-saddle-data/exp4-noise/omp{1,2,4,8}.txt`（`xtb-tester landscape-optimize-xtb`，
仅打印的跨线程探针用不同 `OMP_NUM_THREADS` 运行同一二进制）。

### 3.1 实测 σ_g

| 噪声源 | 实测（水，GFN2） | 备注 |
|---|---|---|
| 冷启动、同进程重复（`OMP=1`） | **0**（逐位相同） | AGENTS.md §6.1 的复现 |
| 冷启动、同进程重复（`OMP≥2`） | **≤1.16e-15 Eh/bohr** | **M0/M1 的“位相等”仅在 `OMP_NUM_THREADS=1` 成立** |
| 跨 `OMP_NUM_THREADS`{1,2,4,8} | **1.11e-15**（OMP2）/ 3.96e-16（OMP4）/ 2.52e-16（OMP8） | 最大值分量；`OMP2` 最大 |
| warm-restart（冷启动 vs 复用波函数） | **3.916e-7 Eh/bohr**（能量 9.68e-13 Eh） | 系统偏置，非随机 |

**重要**：`OMP≥2` 时 `gfn2-singlepoint-determinism` / `water-gfn2-determinism` **失败**
（冷启动重复差 1e-15）；这是 ctest 注册 `OMP_NUM_THREADS=1` 的原因（`test/unit/CMakeLists.txt:122`）。
即：M0/M1 的位相等结论是**条件性**的，报告 07 的措辞应加此限定。

### 3.2 力阈值可达下限

- 随机部分 σ_g ≤ **1.2e-15 Eh/bohr** → 相对 `g_rms=1e-4` 小 **8×10¹⁰ 倍**。
- 系统部分（warm）**3.916e-7** → `g_rms/255`、`g_max/766`。M4 搜索统一 `restart=off`（冷启动），
  实际不引入该项。
- **实测可达**：M4 搜索收敛时
  - Müller-Brown 解析面：prfo `gmax=9.65e-6`、bprfo `1.04e-6`、dimer `1.08e-4`；
  - GFN2 HCN：prfo `gnorm=7.69e-6`、bprfo `2.82e-7`、dimer `1.34e-4` / `2.60e-4`（全部满足四判据）。
- **trust 半径下确界**：噪声诱导位移 ~ σ_g/|H| ≈ 3.9e-7/1 ≈ **4e-7 bohr**，比 `trust_min=1.8897e-3`
  小 **4700 倍**；`trust_min` 不受噪声限制。

### 3.3 回填建议（PLAN §8.2 #4）

| 项 | 现值 | 建议 | 依据 |
|---|---|---|---|
| `TConvSettings%normal`（g_max/g_rms=3e-4/1e-4） | 保留 | **保留，不回退到 `loose`** | 搜索实测 gmax 1e-6…1e-4，可达且有余量 >3× |
| `TTsSettings` 力阈值 `[待校准]` | — | **关闭该 [待校准] 标记** | 同上；σ_g 远低于阈值 |
| `TTsSettings%delta` `[待校准]`（`settings.f90:477`，单位/定义歧义） | midpoint→image=1.8897e-2 | **确认该约定合法** | 报告 27 §6.4：δ×8 曲率变 1.5e-6（0.0013 %）；--acc×30 变 7e-7 |
| `TTsSettings%hlow`（GFN2 取向 1e-2） | — | **改用刚体投影后谱 / 加噪声感知阈值再校准**（见 V2） | 见 §7 V2 |

---

## 4. 实验 #5（M4 验收）：P-RFO 模态跟随 vs 参考交叉验证

> **限制声明**：本机无法安装 Sella/pysisyphus/MAPLE（无外部 Python 环境保证）。
> 因此**没有**做外部代码交叉验证（不假装做过）；交叉验证以**解析势（定量、精确参考）**
> + **内部方法互校（prfo/bprfo/dimer）** 为主。这是 PLAN §8.2 #5 在本环境下的可达形式。

### 4.1 L1（定量，优先）：Müller-Brown 解析面

解析参考（`/tmp/mb.py`，Newton 求根，|∇E|=4.9e-17）：鞍点 **(−0.82200156, 0.62431280)**，
E=−0.0648035531 Eh，Hessian 本征值 **−1.196576 / +0.781248**（恰 1 个负）。
（另一驻点 (0.212487, 0.292988) 也是鞍点，本征值 −1.17169/+0.81415 —— 见 §5 的 dimer 陷阱。）

实测收敛点（`exp5-l1-mb/xtb-tester-saddle.txt`）：

| 方法 | 起点 | 步数 | 收敛点 | 到解析鞍点/bohr | \|g\| | ΔE/Eh | Hessian 本征值 |
|---|---|---|---|---|---|---|---|
| prfo | (−0.6, 0.4) | 5 | (−0.82201148440244, 0.62431195862073) | 9.96e-6 | 1.00e-5 | −9.8e-12 | −1.196579/0.781236 |
| bprfo | (−0.7, 0.45) | 4 | (−0.82200261954216, 0.62431287984356) | 1.06e-6 | 1.14e-6 | −2.9e-13 | −1.196578/0.781246 |
| prfo | (−0.75, 0.5) | 6 | (−0.82200127898338, 0.62431070709809) | 2.11e-6 | 2.18e-6 | −7.0e-13 | −1.196557/0.781257 |
| dimer(seed 2, random) | (−0.75, 0.5) | 14 | (−0.82192393365278, 0.62423170673900) | 1.12e-4 | 1.34e-4 | −7.4e-9 | −1.195780/0.781704 |

**几何互校 RMSD**：

- **prfo vs bprfo = 6.302e-6 bohr** → 验收 1e-3 **通过，裕度 159×**；
- **dimer vs prfo = 7.818e-5 bohr** → 1e-3 **通过，裕度 13×**；
- 三者均落在**同一**（唯一负本征值的）解析鞍点上（本征值一致性见上表）。

`dimer Hessian requests = 0`（14 步全程不需要 Hessian），PLAN §9.5 的 dimer 定位成立。

### 4.2 L2（真实 GFN2）：HCN → HNC

数据：`exp5-l2-gfn2/{prfo,bprfo,dimer_random,dimer_force}/`。

| 方法 | 步数 | 能量/Eh | 最负频率/cm⁻¹ | 虚频数 | gnorm | 原始 RMSD vs prfo | 对齐 RMSD vs prfo |
|---|---|---|---|---|---|---|---|
| prfo | 4 | −5.387373532487 | −1426.11 | **1** | 7.69e-6 | — | — |
| bprfo | 6 | −5.387373532550 | −1426.12 | **1** | 2.82e-7 | 6.05e-4 | **7.7e-6** |
| dimer(random) | 39 | −5.387373510767 | −1425.83 | **1** | 1.34e-4 | 6.05e-4 | **1.17e-4** |
| dimer(force) | 38 | −5.387373451279 | −1426.50 | **1** | 2.60e-4 | 5.02e-3 | **2.03e-4** |

- 全部 `criteria (gmax,grms,dmax,drms): T T T T`，全部 **恰好 1 个虚频**（PLAN §9.5 交付物）；
  能量一致到 2e-7 Eh，虚频一致到 0.7 cm⁻¹。
- 原始 RMSD ~6e-4 由坐标系整体旋转主导（对齐后 1e-5…2e-4），与报告 27 §6.3 一致。

---

## 5. 失效模式实测

数据：`failure-modes/`。

| 失效模式 | 结果 | 证据 |
|---|---|---|
| **模态切换** | **实测触发**：`--lts-mode-overlap-min 0.99` 时第 2 步 overlap **0.9831 < 0.99** → `WARNING: mode following lost the transition vector (overlap .9831 below the threshold .9900); reselecting the mode`，最终仍收敛到正确鞍点（−1426.11 cm⁻¹，E 与默认逐位相同） | `fm_overlap0.99.txt:338` |
| **trust 半径过大 → 错误 basin** | **未复现**：`--lts-trust 1.0` 与 `2.0` 均 4 步收敛到同一鞍点（能量 −5.387373532548，与默认差 6e-11）。原因：RFO 步本身自限 + `trust_max=1.8897` 截断，HCN 面上 trust 不是限制因素。等效的大步长失效在**无量纲** MB 面上可达（报告 27 §6.1：默认 step0/step_max 使 dimer 300+ 步不收敛），属尺度标定问题 | `fm_trust1.0.txt`、`fm_trust2.0.txt` |
| **trust 过小** | `--lts-trust 0.05` → 40 步**不收敛**（exit 1） | `fm_trust0.05.txt` |
| **>1 负本征值 / hlow** | 构造出拉伸 H₂O（O–H=1.5 Å, HOH=104°）：`--lvib` → **2 个虚频**（−854.69 / −825.36 cm⁻¹）；未投影 Hessian 本征值 **−5.79e-2, −3.49e-2**（+ 刚体模 ~1e-11）。`--lts` 从该点出发 5 步“收敛”到**水极小点**（0 虚频），emit `hlow` 警告 | `hess_stretch/`、`fm_stretch2neg.txt`、`ts_h2o_stretch_hlow1e-6.txt` |
| **起始点在错误盆** | 从线性 HNC（产物，极小点）出发 `--lts`：2 步“收敛”到极小点（E=−5.4721599，**0 虚频**） | `fm_from_hnc.txt` |
| **`--lts-init-mode force`** | 20 步不收敛（exit 1，无 NaN/crash），与报告 26 §8.1 一致 | `fm_initforce.txt` |

### 5.1 关于 `lifted` 与「>1 负本征值」的实测（重要，支撑 V2）

HCN TS 起点（真实只有 1 个负本征值）在 `hlow=1e-2 / 1e-6 / 1e-12` **三种**取值下都报
`lifted=T` 并 emit `the downhill subspace has a negative curvature` 警告。原因：数值 Hessian
的 6 个刚体模本征值为 **−3.9e-11 / −1.7e-17 / −3e-27 / …**（未投影，见
`failure-modes/hess_hcn/hessian` 的对角化），其中若干 <0 → `nneg>0` → lift 分支进入。
**这不是文档描述的“>1 个真实负本征值”路径**。

实测 hlow 对**收敛路径**的影响（HCN，其余默认）：

| `hlow` / Eh/bohr² | 步数 | 第 1 步 λ_n |
|---|---|---|
| 1e-2（默认） | **4** | −1.466039e-2 |
| 1e-6 | **6** | −1.864664e-2 |
| 1e-12 | >6 | −1.864710e-2 |

→ 默认 `hlow` 对真实单负本征值体系**实际生效**（步数 4 vs 6，λ_n 差 21 %），而非仅在
“>1 负本征值”时才起作用的“保护”。

---

## 6. 可证伪性注入（全部还原，实测输出见 `injections/`）

每次注入后重建 `xtb-tester` 并运行，最后 `diff` 校验与备份逐字节一致（§6.5）。

| # | 注入 | 位置 | 变红的测试 | 首条真实消息 |
|---|---|---|---|---|
| (i) | `landscape_rfo_downhill_shift` 直接 `return`（λ_n 不迭代） | `saddle/eigenfollow.f90` | `prfo-shifts`, `prfo-lambda-n`, `prfo-negative-downhill`, `bprfo-radius-split`（4） | `lambda_n must be negative` / `lambda_n does not solve the RFO secular equation` |
| (ii) | 去掉模态跟随的符号重对齐 `v_new=sign(Vᵀv)V_idx` | `saddle/eigenfollow.f90` | `mode-follow-sign`（1） | `the sign realignment lost the direction of the tracked vector` |
| (iii) | dimer Eq.21 分支 `curvature < 0` → `> 0` | `saddle/dimer.f90` | `dimer-translation-force`, `dimer-mb-saddle`, `dimer-no-hessian`, `dimer-reproducible`（4） | `the perpendicular force is not kept for C < 0` |
| (iv) | 虚频计数 `result%n_imag = vib%n_imag` → `0` | `tasks/ts.f90` | `xtb/landscape-ts-prfo`, `xtb/landscape-ts-dimer`（2 CLI） | `saddle confirmation - imaginary modes: 0` → `not a first order saddle point` |

### 6.1 一条“测试覆盖缺口”的观察（重要）

注入 (i) 后 **`mb-prfo-saddle` 与 `mb-methods-agree` 仍然通过**（报告 26 §5 曾声称它们会变红）。
即：**验收级的 MB 端到端测试对这种“下坡 shift 被破坏”不敏感**（λ_n=0 的纯 Newton 下坡步
在 MB 上仍收敛到同一鞍点）；只有 `prfo-shifts` / `prfo-lambda-n` 这类**单元级**断言能抓住它。
这是本项目的「测试全绿但不代表协议正确」模式的一个新实例。

### 6.5 源完整性

```
$ for f in eigenfollow.f90 dimer.f90; do diff -q /tmp/m4inject/$f src/landscape/saddle/$f; done
$ diff -q /tmp/m4inject/ts.f90 src/landscape/tasks/ts.f90
（三处命令均无输出：逐字节一致）
$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape
100% tests passed, 0 tests failed out of 44
$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
100% tests passed, 0 tests failed out of 12
$ grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d
（空：无重名）    $ ctest -N -R landscape | tail -1 → Total Tests: 44
```

---

## 7. 新发现（bug 只报告，不在本轮修复）

### V1（MEDIUM，`src/landscape/vib/modes.f90`，继承自 xtb 旧行为）—— 线性分子吞掉负本征值

**现象**：线性 H₂O（O(0,0,0) H(±0.96,0,0)，即 GFN2 下的**二阶鞍点**，两个简并弯曲应虚）
被 `--lvib` 与 `--hess` 报成 **0 个虚频**，最低内模 **+707.64 cm⁻¹ ×2**。

**证据**（`failure-modes/w180_lvib.txt`、`w180_hess.txt`、`/tmp/wlin/hessian`）：

- `--lvib` 写出的 `hessian` 文件（非质量加权、未投影）本征值：
  **−0.361813724 ×2**、1.1e-10 ×3、+0.0191 ×2、+0.4461、+1.3237 —— **确有两个负本征值**。
- 但 `--lvib` 报告 `imaginary modes: 0`，内模 = **+707.64  +707.64  +3419.67  +3609.10**。
- 能量面自证：E(180°)=−5.018205857 < … 单调下降至平衡角；二阶差分 d²E/dθ² ≈ −0.229 Eh/rad²<0。
- **阈值不连续**：HOH 从 179.5°（判为 linear）到 179.0°（判为非 linear），最低内模由 **+707.6 跳到 −1884.0 cm⁻¹**。

**根因（定位到行）**：`modes.f90` 的 linear 分支**跳过投影**（`modes.f90:151`，
`if (project_tr .and. .not. linear)`），并无条件取**最低的 `n_zero=5` 个本征值**为零模
（`modes.f90:142` 设 `n_zero=5`；`modes.f90:181` `n_zero_found = n_zero` 及随后 `order(i)=i`；
`modes.f90:216` `if (linear .and. i <= n_zero) cycle`）。当 Hessian 有**低于刚体模噪声的负本征值**时
（线性鞍点），这 5 个最低值就是两个真实虚弯曲 + 3 个平动，于是**两个虚弯曲被当作零模删除**，
剩下 2 个转动（0.0191）被当成振动打印（707.64）。

**影响 M4**：`--lts` 的鞍点确认调用同一个 `landscape_vib_analysis`，因此**线性过渡态**
的虚频确认会给出错误的「0 虚频」。M4 当前的 HCN 例子是弯曲的，未触发；但线性 TS
（如线性 HXH 类）会踩中。**M3 的线性测试只覆盖了线性极小点（CO₂/HCN）**，未覆盖线性鞍点。

**建议**：linear 分支也做刚体投影（有线性专用的 3N−5 投影），或按「低于 `zero_mode_tol`
且严格为投影零模」选择零模，而非无条件取最低 5 个；并补一个线性鞍点测试。

### V2（MEDIUM，`src/landscape/saddle/prfo.f90:237-251`）—— `lifted` 诊断被刚体模噪声淹没

`nneg` 统计下坡子空间中 `evals<0` 的个数。数值 Hessian 的刚体模本征值为 ~±1e-11（未投影），
其中若干 <0 ⇒ `nneg>0` 恒成立 ⇒ `was_lifted`/`lifted` 与警告 `the downhill subspace has a
negative curvature` 在**真实单负本征值体系上也每步触发**（HCN 实测 `lifted=T`，即使
`--lts-hlow 1e-12`）。且默认 `hlow=1e-2` 把刚体模抬到 1e-2，改变 λ_n（−1.466e-2 vs −1.865e-2）
与收敛路径（4→6 步）。

**影响**：CLI 上 `lifted=T` **不能**作为「>1 负本征值保护已生效」的证据；文档/审阅若据此
声称保护被验证会得出错误结论。功能上因步被刚体投影，最终几何不被破坏。

**建议**：对角化前先对 Hessian 做刚体投影（或把 `nneg` 阈值设为噪声感知值），并让
`lifted` 只在真实负曲率被抬起时为真。

### V3（MEDIUM，`src/landscape/tasks/ts.f90:282`）—— 非一阶鞍点仍以“成功”退出

`--lts` 收敛到**极小点**（0 虚频）时：`landscape task terminated: converged` + **exit 0**，
只 emit 一条 warning `the located stationary point has 0 imaginary mode(s), not 1`。
实测两例：从线性 HNC 出发（`fm_from_hnc`）、从拉伸 H₂O 出发（`fm_stretch2neg`）。
对于 CI/验收脚本这是**假阳性**（任务目标是一阶鞍点）。

**建议**：把「非一阶鞍点」升为任务失败（非零退出码），或至少 `result%converged=.false.`。

### V4（LOW，文档）—— M0/M1「冷启动位相等」是条件性结论

`OMP≥2` 时同位重复差 ≤1.16e-15 Eh/bohr（`gfn2-singlepoint-determinism` 在 `OMP≥2` 直接失败）。
AGENTS.md §6.1 / 报告 07 应写明「仅 `OMP_NUM_THREADS=1`」。ctest 已按此注册，故套件稳定。

---

## 8. 本轮测试文件的改动（仅打印，不改断言/算法）

1. `test/unit/test_landscape_optimize_xtb.f90`（`gfn2-singlepoint-determinism`）：新增
   3N 分量梯度的 `es24.16` 打印与 `f20.14` 能量打印 —— 支撑 §3.1 的跨 OMP 噪声测量。
   不新增测试名、不改断言。
2. `test/unit/test_landscape_saddle.f90`（`run_one` / `run_dimer`）：新增收敛点的
   `f20.14` 打印 —— 支撑 §4.1 的 $\Delta E$、本征值对比。不新增测试名、不改断言。

两处均不产生新 `add_test`，无需改注册文件；`ctest -N -R landscape` 仍为 **44**，无重名。

---

## 9. 数据清单（`docs/_landscape-recon/m4-saddle-data/`，195 文件）

| 目录 | 内容 |
|---|---|
| `exp3-etemp/vib_etemp{0,300,1000,5000}/` | `--lvib` stdout + `g98.out` + `hessian` + `vibspectrum` + `vib_normal_modes` |
| `exp3-etemp/ts_{prfo,bprfo}_etemp{0,300,1000,5000}/` | `--lts` stdout + exit + `xtbts.xyz` + `xtbts.log` |
| `exp4-noise/omp{1,2,4,8}.txt` | 跨线程梯度探针（含全精度梯度）；`optimize-xtb-omp1.txt` 基线 |
| `exp5-l1-mb/xtb-tester-saddle.txt` | 解析面全部测试打印（收敛点、RMSD、本征值需外部脚本） |
| `exp5-l2-gfn2/{prfo,bprfo,dimer_random,dimer_force}/` | `--lts` stdout + exit + 输出文件 |
| `failure-modes/` | `fm_*.txt` + exit（trust/overlap/init/错误盆）；`hess_{hcn,stretch}/`（未投影 Hessian 文件）；`ts_*_hlow*.txt`；`w180_{lvib,hess}.txt`；`_scratch/` |
| `injections/` | `inj_{i,ii,iii}_saddle.txt`、`inj_iv_cli.txt` |

复现脚本片段（全部 `OMP_NUM_THREADS=1`，`XTBPATH=$PWD`）：

```bash
XTB=/tmp/xtb-land/build/xtb
# #3
$XTB /tmp/hcn.xyz --gfn 2 --lvib  --norestart --etemp 5000
$XTB /tmp/hcn.xyz --gfn 2 --lts --lts-method prfo --norestart --etemp 5000
# #4
for T in 1 2 4 8; do OMP_NUM_THREADS=$T /tmp/xtb-land/build/test/unit/xtb-tester landscape-optimize-xtb; done
# #5 L1
OMP_NUM_THREADS=1 /tmp/xtb-land/build/test/unit/xtb-tester landscape-saddle
# #5 L2 / failure modes
$XTB /tmp/hcn.xyz --gfn 2 --lts --lts-method {prfo,bprfo,dimer} --norestart
$XTB /tmp/hcn.xyz --gfn 2 --lts --lts-method prfo --lts-mode-overlap-min 0.99
```

---

## 10. 对 PLAN 的回填建议汇总

| PLAN 位置 | 建议 |
|---|---|
| §5.3.1 `[待校准]`：`normal` 四阈值（TS/IRC 前复核） | **关闭**：σ_g ≤ 1.2e-15（随机）/ 3.9e-7（warm），`normal` 可达；保留默认 |
| §5.3.6 `TTsSettings` 力阈值 `[待校准]` | **关闭**（同上）；`delta` `[待校准]` 由报告 27 §6.4 关闭 |
| §9.5 硬约束 1（`etemp` 冻结 + 记录） | **满足**（§2.3）；并补一句「5 000 K 时曲率漂 7.5 %、几何 7e-3 bohr」作为定量依据 |
| §9.5 硬约束 2（近零曲率收紧 FD） | **满足**（报告 27 §6.4 + §2.1：>1000 K 才显著） |
| §9.5 硬约束 3（不用 `--hess` 逐位一致） | 保持；本报告未使用逐位判据 |
| §8.2 #3/#4/#5 | #3/#4 关闭；#5 在本环境**只能**用解析面 + 内部互校（已声明限制） |
| §9.5 交付物「虚频确认」 | 交付，但对**线性**鞍点失效（V1），应在 M4 收口前修复 |

---

## 11. 残余风险 / 未竟事项

1. **V1/V2/V3 未修复**（超出验证者权限），已给 `file:line` 与最小复现，交后续修复轮。
2. **无外部代码交叉验证**（Sella/pysisyphus 不可得）—— 已显式声明，未假装完成。
3. `--lts` 的 `hlow`/`trust`/`alpha` 等旋钮只有单元级覆盖；本报告补了 `hlow`/`trust`/`overlap`
   的端到端实测，其余保持报告 26/27 的结论。
4. MB 上 dimer 的起始轴敏感性（31/40 seed 到鞍点）沿用报告 27，未重跑。

---

## 12. [最终修复轮补充] 两个起点的实测对照（本轮的「几何依赖性」条目）

本文档（以及 26/27/30）的 HCN 验收起点是**弯曲的 TS 猜测**几何
`H(0,1.05,0) Å, C(0,0,0), N(1.156,0,0)`，而不是极小点；原稿没有写明这一点。
最终修复轮补上了两种起点的实测对照（GFN2，全部 `OMP_NUM_THREADS=1`，`--norestart`）：

| 方法 | 起点 = 线性极小点 H(−1.0,0,0) Å | 起点 = 弯曲 TS 猜测 | 起点 = 极小点且 `--lts-escape-step 0` |
|---|---|---|---|
| prfo | 逃逸 7 push/1.4 bohr + 5 步，1 虚频 −1426.19 cm⁻¹，exit 0，E = −5.387373532908 | 4 步，1 虚频 −1426.12 cm⁻¹，exit 0，E = −5.387373532156 | 3 步，0 虚频，exit 1（`confirmation: minimum … not a transition state`） |
| bprfo | 逃逸 7 push + 7 步，1 虚频 −1426.13 cm⁻¹，exit 0，E = −5.387373532839 | 5 步，1 虚频 −1426.12 cm⁻¹，exit 0，E = −5.387373532550 | — |
| dimer | 29 步，1 虚频 −1426.73 cm⁻¹，exit 0，E = −5.387373461989 | 15 步，1 虚频 −1425.24 cm⁻¹，exit 0，E = −5.387373500230 | — |
| 线性 HNC 极小点（ctest 输入） | 逃逸 8 push/1.6 bohr + 4 步，1 虚频，exit 0，E = −5.387373532837 | — | 2 步，0 虚频，exit 1 |

要点：**prfo/bprfo 需要鞍点猜测**（最终修复轮加了从（近）驻点极小点起步的逃逸行走，
见 PLAN §9.5）；**dimer 不需要 Hessian/选模，因此从极小点起步直接可用**（同一极小点 29 步）。
M4 的验收数字（Müller-Brown prfo vs bprfo RMSD 6.3022e-06、dimer vs prfo 7.7397e-05、
弯曲起点三方法 1 虚频 + exit 0）在修复后**逐位不变**（重跑证据：
`docs/_landscape-recon/m4-final-fix-data/`）。
