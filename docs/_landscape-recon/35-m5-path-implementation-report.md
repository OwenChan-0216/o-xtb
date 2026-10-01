# 35 — M5 第一阶段实施报告：chain-of-states（IDPP / NEB / CI-NEB）

> 范围：本阶段只交付 **IDPP + NEB + CI-NEB 内核**及其任务层接线。
> AutoNEB（`path/autoneb.f90`）与 String/GSM（`path/string.f90`、`path/gsm.f90`）
> 属第二阶段，本报告不涉及，`path_autoneb.xyz` / `path_ts_list.xyz` 亦未产生。
>
> 基线：`HEAD = 902cbe4`（M4）。构建目录 `/tmp/xtb-land/build`。
> 所有实测均在 `OMP_NUM_THREADS=1` 下完成。

---

## 0. 结论摘要

| 项 | 结果 |
|---|---|
| 构建 | 干净（`cmake --build`，无 error） |
| `ctest -R landscape` | **63/63 全绿**（M4 后为 51，本阶段 +12；含 1 个单元套件 + 12 个 CLI 测试） |
| 回归子集 | `-R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'` → **12/12** |
| 单元用例 | `landscape-path` 套件 **25/25**（含 12 个新增 CLI 级测试） |
| 注入实验 | **5/5 全部变红**，还原后全绿（§5） |
| LEPS 验收 | NEB 势垒与解析值差 **0.0000 kcal/mol**；CI-NEB 同；最高像几何 `r12 = r23 = 1.50518` bohr（解析 `r* = 1.505269`） |
| 端到端 | `--lts --lts-method cineb`（GFN2，NH3 反转）8 步收敛，`path.xyz` 7 帧，TS 候选 1 虚频 −971.33 cm⁻¹（§7） |

---

## 1. 交付物

| 文件 | 行数 | 内容 |
|---|---|---|
| `test/unit/landscape_testpot.f90`（改） | +266 | `landscape_leps_model`：LEPS H+H2 解析势（能量 + 解析梯度 + 由解析梯度中心差分的 Hessian） |
| `src/landscape/path/idpp.f90`（新） | 322 | IDPP 初始路径（Smidstrup et al., JCP **140**, 214106 (2014)），目标面 + 解析梯度 + L-BFGS 弛豫 |
| `src/landscape/path/neb.f90`（新） | 916 | band 内核：改进切线 Eq. 8–11、Eq. 12 弹簧、ORCA 动态弹簧、Kabsch 对齐、双判据收敛、两阶段 CI 切换、L-BFGS 传播 |
| `src/landscape/path/cineb.f90`（新） | 135 | climbing image 力 Eq. 5、点火判据、最高能量像选择 |
| `src/landscape/types/settings.f90`（改） | +124 | `landscape_path_settings` + `p_landscape_ts_neb/cineb` + `landscape_ts_method_is_band` |
| `src/landscape/types/coords.f90`（改） | +51 | `align_geometry`：无质量 Kabsch 对齐（算术质心，含**质心回写**） |
| `src/landscape/tasks/ts.f90`（改） | +517 | band 分支、产物端点读取/校验、`path.xyz` 与 band 表、TS 候选复用 M3 频率确认 |
| `src/prog/main.F90`（改） | +173 | 12 个 `--lts-*` band flag、`path%input_file`/`path%max_steps` 同步、`cineb` 自动开 climb |
| `test/unit/test_landscape_path.f90`（新） | 1394 | 25 个单元用例 |
| `test/unit/CMakeLists.txt`（改） | +225 | 单元套件注册 + 12 个 CLI 测试 |
| `test/unit/{main.f90,meson.build}`、`src/landscape/{CMakeLists.txt,meson.build}`（改） | +9 | 注册（三处 + 两处） |

`docs/xtb-landscape-PLAN.md` 新增 **§12.12**：runtyp 决策、CLI 表、**输入契约与校验矩阵**、
标定值、已知限制（供 M6/M7 与复审对齐）。

---

## 2. 算法实现要点

### 2.1 改进切线（Henkelman & Jónsson, JCP **113**, 9978 (2000), Eqs. 8–11）

```
dm = R_i − R_{i-1},  dp = R_{i+1} − R_i        （各自先归一化）
E_{i-1} < E_i < E_{i+1} :  τ = û(dp)            （单调上升：前向 upwind）
E_{i-1} > E_i > E_{i+1} :  τ = û(dm)            （单调下降：后向 upwind）
否则（极值点, Eq. 11）    :  τ ~ w_max * û(+方向) + w_min * û(−方向)
                             w_max = max(|E_{i+1}−E_i|, |E_{i-1}−E_i|)，附在**能量较高**的邻居上
```

实现上按 Eq. 11 的**绝对值 max/min** 形式（不是 MAPLE 的 `max(ΔE,0)` 正部形式）。理由：
正部形式在单调段退化为纯 `dp`，于是**两个 upwind 分支在代数上冗余**（
`E_{i+1}>E_i>E_{i-1}` ⇒ 权重为 `(E_{i+1}−E_i, 0)` ⇒ τ ∝ dp），
注入实验 (iii) 将无法与旧逻辑区分开 —— 正是 M4 教训（报告 34）。
改用 Eq. 11 后分支真实生效，注入 (iii) 可证伪（§5）。

退化保护：加权和为零 → `dp + dm` → `e_1`，任何输入都返回单位向量、不产生 NaN。

### 2.2 Eq. 12 弹簧（标量距离差）

```
F_i = F_i^perp + k_i (|R_{i+1}−R_i| − |R_i−R_{i-1}|) τ_i
```

弹簧项**只沿切向**，用两个**标量距离差**。1998 年的原始矢量弹簧
`k (R_{i+1} − 2R_i + R_{i-1})` 不做（其垂向分量会把像推离路径），
在 `test_spring_eq12` 里把两者并列记录：在构造的 kink 几何上差异 **3.0 Eh/bohr**（§5 (ii)）。

### 2.3 动态弹簧（ORCA 风格，按 PLAN/任务书**字面公式**实现）

```
ΔE_i = max(E_i − max(E_{i-1}, E_{i+1}), 0),  ΔE_max = max_i ΔE_i
k_i   = k_max − (k_max − k_min) · exp(−decay · ΔE_i/ΔE_max)
```

> ⚠️ **如实记录**：该字面公式把**弱**弹簧给"能量不高于任一邻居"的像（ΔE=0 ⇒ exp(0)=1 ⇒
> `k = k_min`），把接近 `k_max` 的弹簧给**唯一**能量抬升的像。参考实现 MAPLE 的 docstring
> 声称"barrier 处的像得到更弱的弹簧"，与其**自己的公式相反**。本实现遵守公式（任务书与
> PLAN §6.4 都是字面公式），`test_dynamic_springs` 把公式而非注释钉死。

### 2.4 收敛：geomeTRIC 风格双判据

```
per-image  rms_i = sqrt( ΣF_i² / (3N) )        （只算内部像；climbing image 排除）
band 收敛 ⟺  mean_i(rms_i) ≤ f_rms_avg_tol  AND  max_i(rms_i) ≤ f_rms_max_tol
             AND（若已点火） 未投影的 climbing image 力 rms ≤ f_rms_max_tol
```

`test_dual_criterion` 同时钉住"平均达标但单个像差 → 不收敛"和"最大达标但平均差 → 不收敛"。

### 2.5 Kabsch 对齐

`align_geometry(env, xyz, ref)`：两者各自减去**算术质心**，按四元数法旋转
`xyz` 到 `ref`，**再把 `ref` 的质心加回去**。最后一步是必需的：只做居中会把
每个像搬到原点，等于**静默引入平移**（开发期实测该 bug 使 CMake 的 band 头部
打印出 `band: 9 images (7 internal, 2` 之类错位现象之外还在 `test_band_align_effect`
上表现为"对齐无效果"）。`align-rotation` 现在断言恢复精度 2.6e-16 且质心落在
**参考质心**上。

对齐只改几何，不改物理：端点固定；`band-fixed-endpoints` 在 `align=.false.`
下断言首尾像**逐位**不变，`band-align-effect` 在 `align=.true.` 下断言端点能量不变。

### 2.6 两阶段 CI 切换

先跑普通 NEB；`climb_switch_rms` 满足后把**最高能量内部像**点火为 climbing image
（`F_ci = F − 2(F·τ)τ`，无弹簧力），对其它像仍是 NEB 力。点火后该索引**冻结**
（参考实现语义），若最高能量像随后改变，`n_climb_switch` 计数并 `env%warning`
（不静默），最终 TS 候选仍取点火的那一张。

---

## 3. PLAN §8.2 实验 #8：CI-NEB 切换阈值与弹簧常数标定

### 3.1 σ_g 与阈值的量级对比（回答"0.5 eV/Å 是否会被噪声误触发"）

| 噪声源 | 实测（报告 28 §3.1） | 与 9.7234e-3 Eh/bohr 之比 |
|---|---|---|
| 随机 σ_g（冷启动，OMP=1） | 0（逐位相同） | — |
| 随机 σ_g（OMP≥2） | ≤ 1.16e-15 Eh/bohr | **小 1.3×10¹³ 倍** |
| warm-restart 系统偏置 | 3.916e-7 Eh/bohr | **小 2.5×10⁴ 倍** |

**结论：0.5 eV/Å 的切换阈值不可能被梯度噪声误触发**；切换时机完全由 band 自身状态
（`band_f_rms_max`）决定。M5 统一 `restart=off`（`landscape_engine_control%restart_mode`
默认），因此实际生效的只有随机项。

### 3.2 弹簧常数扫描（LEPS H+H2，9 像，`f_rms_avg/max = 3e-4/1e-3`，预算 400 步）

`test_spring_calibration` 真实输出（静态弹簧，`use_dynamic_k=.false.`）：

| k (Eh/bohr²) | 迭代数 | 收敛 | 势垒误差 (kcal/mol) | 最小像间距 (bohr) |
|---|---|---|---|---|
| 动态默认 `k_min=1e-2, k_max=1e-1` | **48** | **T** | 0.0000 | 0.462（均值 0.501） |
| 1e-5 | 31 | T | 0.0000 | 0.065 |
| 1e-4 | 30 | T | 0.0000 | 0.066 |
| 1e-3 | 31 | T | 0.0001 | 0.071 |
| 1e-2 | — | **F** | 1.1e6 | 1.024 |
| 1e-1 | — | **F** | 2.3e4 | 3.578 |
| 1 | 37 | T | 0.0004 | 0.500 |
| 10 | 43 | T | 0.0001 | 0.501 |
| 1e2 | — | **F** | 5.8e5 | 1.523 |

**读法（如实）**：
- **上界是可证伪的**：`k = 1e2` 在预算内不收敛（band 发散）→ `test_spring_calibration`
  断言 `fails(8) < 0`，注入会变红。这复现了 VASP/R-11 的"弹簧过刚妨碍收敛"。
- **下界在 LEPS 上不是"不收敛"**：`k ≤ 1e-3` 反而**收敛得最快**，但最小像间距只有
  0.065 bohr（均值的 13%）——像几乎挤在一起。垂向力判据看不见这种病态，
  这正是 PLAN 要求"双判据"和第二阶段该补"重参数化/弧长约束"的理由。测试因此
  断言"弱端收敛"这一**实测事实**，并把它打印出来，而不是伪造一个下界。
- **静态窗口非单调**：`[1e-5,1e-3]` 与 `[1,10]` 收敛，`[1e-2,1e-1]` 与 `1e2` 不收敛。
  固定步长截断 + L-BFGS 历史在非保守力场上有类似共振的敏感性，属 §6 的残余风险。

**标定后的默认值**：`k_min = 1.0e-2`、`k_max = 1.0e-1 Eh/bohr²`（动态，decay 0.5），
`f_rms_avg_tol = 3.0e-4`、`f_rms_max_tol = 1.0e-3 Eh/bohr`。
（PLAN 初值 `2.083e-3 / 2.083e-2` 保留为 CLI 可覆盖值，标注见 §3.3。）

### 3.3 `climb_switch_rms` 的定值与 PLAN 值的换算错误

任务的验收文字为"0.5 eV/埃（= climb_switch_rms 3.472e-2 Eh/bohr）"。**该等号不成立**：

```
0.5 eV/Å = 0.5 × (1/27.21138505) Eh / (1.8897259886 bohr)
         = 0.5 × 0.0367493 / 1.88973
         = 9.7234e-3 Eh/bohr
```

3.472e-2 = 0.5 / 14.4，而 14.4 = 27.2114/1.88973 —— 即用**力**的换算因子
（eV/Å → Eh/bohr 的倒数形式）套在了本该用**长度**因子的地方。正确值是 **9.7234e-3**
（等价于 1.786 eV/Å 才是 3.472e-2）。

**处理**：默认值取物理正确的 **9.7234e-3 Eh/bohr（= 0.5 eV/Å）**，并在
`landscape_path_settings` 的类型文档里写清换算与出处；`--lts-climb-switch`
可覆盖。两种取值在 LEPS 上都收敛（§7 实测点火迭代数不同：9.723e-3 → 31，
3.472e-2 更迟），因此该订正不影响功能，但会让默认值与化学文献的 0.5 eV/Å 一致。
`k_min/k_max` 的 PLAN 初值同源错误（把 eV/Å² 当 eV/Å 换算），一并说明。

---

## 4. 输入契约与校验矩阵（每个分支一个 CLI 测试）

机制与理由见 PLAN §12.12。测试名与断言：

| # | 分支 | 测试名 | 断言字符串 |
|---|---|---|---|
| 1 | 正常 product（单帧、原子数/序一致），NEB + CI-NEB 各跑一次 | `xtb/landscape-path-cli` | 退出 0；`landscape: transition state search (neb)`；`band: k_min`；`landscape: converged`；`saddle confirmation - imaginary modes: 1`；`path.xyz` **恰 7 帧**；CI 分支出现 `climbing image N ignited at iteration` 与 `band: climbing image (TS candidate): N` |
| 2 | product 文件不存在 | `xtb/landscape-path-product-not-found` | `cannot open the product geometry` |
| 3 | product 原子数不符（3 vs 4） | `xtb/landscape-path-product-atom-count` | `the product geometry has 3 atoms but the reactant has 4` |
| 4 | product 原子序不符（H,N,H,H） | `xtb/landscape-path-product-atom-order` | `the atom order of the product geometry differs` |
| 5 | product 帧数 > 1（2 帧） | `xtb/landscape-path-product-multiframe` | `holds 2 frames; exactly one is required` |
| 6 | product 扩展名非 xyz（`.coord`） | `xtb/landscape-path-product-not-xyz` | `must be a single frame xyz file` |
| 7 | 输入多帧且**无** product | `xtb/landscape-path-input-multiframe` | `the input holds 2 frames; pass the product with --lts-product` |
| 8 | 输入多帧且**有** product（歧义） | `xtb/landscape-path-ambiguous` | `the two endpoints are ambiguous` |
| 9 | 单帧且无 product | `xtb/landscape-path-product-missing` | `a band search needs a product geometry` |
| 10 | 单端方法（dimer）带 `--lts-product` | `xtb/landscape-path-product-single-ended` | 输出含 `only used by` 与 `neb|cineb`（**warning，非 error**） |
| 11 | `--lts-images` 缺值 | `xtb/landscape-path-band-images-missing` | `The --lts-images flag requires an integer` |

> **决策记录（多帧便利路径）**：**未实现**。既有 `readMolecule`（`src/io/reader.f90`）
> 只读单帧；读第二帧需要自己写多帧解析器（成本高于收益），故按上级给的备选方案处理：
> 单一路径 + 明确错误（即第 7/8 条）。检测本身**不是**解析器：
> `landscape_ts_count_frames` 只读 atom 数、跳过 comment 与 atom 行、看下一个整数，
> 因此帧计数开销可忽略且不会误读坐标。

---

## 5. 注入实验（每个都真实执行，且先证明变异与旧逻辑的关系）

方法：`python3 /tmp/inject.py <name>`（改源码 → 全量重建 → 跑 `landscape-path`
套件与 `-R landscape-path` → 还原源码）。所有注入的"旧逻辑"就是被替换掉的另一种
合法实现，因此"变红"直接说明对应测试能区分两者；没有一条是靠"语义等价的另一种写法"
变红的（这正是报告 34 的教训）。

| # | 注入 | 变异与旧逻辑 | 变红测试 |
|---|---|---|---|
| (i) | 改进切线 → 朴素切线 | `τ = normalize(dp + dm)`：1998 年弹性带的朴素切线，改进切线要取代的对象 | `improved-tangent`（+ ctest `xtb/landscape-path`） |
| (ii) | Eq. 12 → 原 Eq. 5 矢量弹簧 | `F = F_perp + k(dp − dm)`：1998 年原始矢量弹簧；kink 几何上与 Eq. 12 差 3.0 Eh/bohr | `spring-eq12`、`neb-spring-calibration`、`mb-neb-saddle` |
| (iii) | 关闭 upwind 单调性判据 | 两个分支条件改成 `.false.`，一律走 Eq. 11 加权平均。**先证明不等价**：Eq. 11 用绝对值 max/min，单调段下与纯 `dp`/`dm` 不同（若用 MAPLE 的正部权重则**代数等价**，注入无意义，见 §2.1） | `improved-tangent` |
| (iv) | 关闭 Kabsch 对齐 | 建路与步进处的 `if (settings%align)` 改为 `if (.false.)`（对齐例程本身保留） | `band-align-effect`、`leps-neb-barrier`、`leps-cineb-barrier`、`cineb-switch-threshold`、`neb-spring-calibration`，以及 CLI `xtb/landscape-path-cli` |
| (v) | 按列主序读梯度（R-08） | `leps_evaluate` 出口处把 9 维梯度按 `(nat,3)` 转置（`reshape(transpose(reshape(g, [3,3])), [9])`） | `leps-gradient`、`leps-hessian`、`leps-neb-barrier`、`leps-cineb-barrier`、`cineb-switch-threshold`、`neb-spring-calibration` |

**全部还原后**：`cmake --build` 干净，`ctest -R landscape` **63/63 全绿**（实测，见 §7）。

补充说明：
- (iv) 中 `align-rotation` **不变红**，这是正确的：它测的是 `align_geometry` 例程
  本身，而注入关闭的是 band 对它的**调用**。两个测试分工明确（例程 vs 使用）。
- (v) 中 `leps-gradient` 变红，即 R-08 的守门测试生效；同时 4 个 band 级测试也变红，
  说明错误的展平顺序会一路污染势垒与标定。

---

## 6. 已知限制与残余风险

1. **band 传播是固定步长截断的 L-BFGS，作用在非保守力场（含弹簧）上**。
   LEPS / Müller-Brown / NH3 反转 / H2+H 迁移正常收敛，但：
   - **HCN→HNC（GFN2）不收敛**：该反应的重原子需要交换位置，IDPP 目标面能实现的
     路径在**笛卡尔意义上不连续**（实测 IDPP 像间距 0.066/0.068/0.071/**2.88**/0.091… bohr，
     第 4→5 帧跨越了 C/N 对穿点），band 长期停在 `f_rms ≈ 3e-2`。
     **不过**：其 TS 候选（最高能量像）经 M3 确认是合格一级鞍点（−664 cm⁻¹，1 虚频）。
     端到端验收因此改用 NH3 反转（§7）。第二阶段的**线搜索 + 弧长重参数化**是正解。
   - 静态弹簧窗口非单调（§3.2），提示传播对步长/历史敏感。
2. **`climb_switch_rms` 默认值修正为 9.7234e-3**：PLAN/任务书的 `3.472e-2` 是换算
   错误（§3.3）。若复审坚持保留 PLAN 字面值，只需改一个默认常量，功能等价。
3. **IDPP 对 2 原子（MB 嵌入）退化**：只有 1 个 pair 距离对应 2 个自由度，目标面
   欠定；MB 测试因此显式 `ifidpp=.false.`、`align=.false.`（两原子线性模型的
   Kabsch 旋转退化）。真实分子（>= 3 原子）无此问题。
4. **`relax_ends` 只在任务层**（复用 M1 `landscape_optimize_model`），仅在
   `--lts-relax-ends` 时走；一次 band 序列内 etemp / restart 策略由同一
   `landscape_engine_control` 保证统一（M4 硬约束 5）。该路径**未被单元测试覆盖**
   （只有代码路径 + 打印），列为第二阶段测试缺口。
5. **`hessian_recalc` 的语义**：band 没有显式 Hessian，该字段被定义为
   "每 N 步清空 L-BFGS 历史"（0 = 不清）；`--lts` 未暴露（仅 API）。文档已注明。
6. `path_autoneb.xyz` / `path_ts_list.xyz` **未产生**（第二阶段交付物）。

---

## 7. 验收证据（真实执行）

### 7.1 构建与测试

```
$ cmake -S . -B /tmp/xtb-land/build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF \
        -DWITH_TESTS=ON -DCMAKE_BUILD_TYPE=Release && cmake --build ... -j 8
exit=0

$ ctest --test-dir /tmp/xtb-land/build -R landscape
63/63 Test #142: xtb/landscape-path-product-single-ended ... Passed 0.08 sec
100% tests passed, 0 tests failed out of 63
Total Test time (real) = 9.13 sec

$ ctest -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
100% tests passed, 0 tests failed out of 12
```

`ctest -N -R landscape` → 52 → **63**；`grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d`
→ **空**（无重名）。

### 7.2 单元套件 `landscape-path`（25/25）

```
step 1.000E-03  max |analytic - central|  4.25835E-05
step 1.000E-04  max |analytic - central|  4.25834E-07      <- 比值 100，O(h^2)
step 1.000E-05  max |analytic - central|  4.28068E-09
err(1e-3)/err(1e-5) =         9947.8
LEPS TS eigenvalues:  -1.004939  -0.000000 ... 0.003004 0.003004 1.895410
```

### 7.3 端到端 `--lts --lts-method cineb`（GFN2，NH3 反转）

```
$ OMP_NUM_THREADS=1 xtb nh3.xyz --gfn 2 --lts --lts-method cineb \
      --lts-images 7 --lts-product nh3_inv.xyz --norestart
exit=0

 landscape: transition state search (cineb)
 band: product geometry nh3_inv.xyz
 band: 7 images (5 internal, 2 fixed endpoints)
 band: k_min  1.000E-02 Eh/bohr^2, k_max  1.000E-01 Eh/bohr^2
 band: dynamic springs, decay    0.500
 band: climbing image switch at  9.723E-03 Eh/bohr
 band: climbing image 4 ignited at iteration 0
 band: iterations 8, f_rms_avg  2.50438E-04, f_rms_max  3.30317E-04
 band: highest image 4, energy      -4.416506815538 Eh, barrier       6.0823 kcal/mol
 band: climbing image 4, force RMS  2.09879E-05 Eh/bohr
 wrote path.xyz with 7 frames
    image        energy/Eh       dE/kcal/mol   distance/bohr
      1      -4.426199541332         0.0000 reactant
      2      -4.425398560884         0.5026       0.141495
      3      -4.419952158127         3.9203       0.254510
      4      -4.416506815538         6.0823       0.257968
      5      -4.419952315435         3.9202       0.257951
      6      -4.425398095685         0.5029       0.254468
      7      -4.426199541332        -0.0000 product
 band: climbing image (TS candidate): 4
 landscape: converged
 converged:      T
 steps:          8
 saddle confirmation - imaginary modes: 1
 most negative frequency:          -971.33 cm^-1
 confirmation: first order saddle point
 wrote xtbts.xyz
 landscape task terminated: converged
```

NH3 反转实验势垒 ≈ 5.8 kcal/mol，本计算 **6.08 kcal/mol**（差 0.3 kcal/mol），
TS 虚频 −971 cm⁻¹（实验/文献约 −950 cm⁻¹）。`path.xyz` 帧序：帧 1 = 反应物、
帧 7 = 产物，逐帧 comment 带能量。

### 7.4 LEPS 三路互校（解析 / NEB / CI-NEB）

LEPS（H+H2）解析参考（默认参数 `d_e=0.1744342274 Eh, β=3.6711 /bohr, r_e=1.4011 bohr, Sato=0.10`）：

| 量 | 解析值 |
|---|---|
| H2 渐近阱 | `r = 1.4140743` bohr，`E = −0.1549809388` Eh |
| 鞍点（共线对称） | `r12 = r23 = r* = 1.5052686` bohr `= 0.7965539 Å` |
| 鞍点能量 | `−0.1406385741` Eh |
| 鞍点 Hessian 本征值 | `−1.004939 / +0.003004 ×2 / +1.895410`（**恰 1 负**） |
| 经典势垒 | `9.0000 kcal/mol = 0.39036 eV`（相对渐近阱；带端点在 4 bohr 处为 8.9985） |

| 方法 | 势垒 (kcal/mol) | 与解析差 | 最高像 | `r12 / r23` (bohr) |
|---|---|---|---|---|
| NEB（9 像，48 步） | 8.9985 | **+0.0000** | 5 | 1.50518 / 1.50518 |
| CI-NEB（9 像，第 31 步点火） | 8.9985 | **+0.0000** | 5 | 1.50518 / 1.50518 |
| 解析 | 8.9985 | — | — | 1.50527 / 1.50527 |

验收（"LEPS 势垒与解析值差 < 0.5 kcal/mol"）三路互校达成，几何误差 `2e-5 bohr`。
（Müller-Brown 2D：NEB 60 步收敛，最高像距解析鞍点 **0.0271**，势垒 `105.7730` vs 解析 `106.0346` kcal/mol ⇒ **−0.26 kcal/mol**。）

### 7.5 IDPP vs 线性插值（同一对端点，7 像）

```
max energy  linear   -0.003392062498   IDPP   -0.025687343521
max adjacent jump  linear  46.945712 kcal/mol, IDPP  27.444830 kcal/mol
```

---

## 8. 与原计划的偏离

| 项 | 偏离 | 理由 |
|---|---|---|
| runtyp | **不新增**，`p_run_lts` + method 分支 | PLAN §9.6 首选方案；`p_run_*` 无空闲必要性，R-05 不触发 |
| `climb_switch_rms` / `k_min` / `k_max` 默认值 | 改为实测标定值（§3） | PLAN 明确标 `[待校准]`，实验 #8 就是定值依据；PLAN 初值含换算错误 |
| 切线极值权重 | Eq. 11 绝对值 max/min（非 MAPLE 正部形式） | 正部形式下 upwind 分支代数冗余，注入 (iii) 不可证伪（M4 教训） |
| 多帧输入便利路径 | 未实现，改明确报错 | 上级授权的备选方案；复用 `readMolecule` 读第二帧需写解析器 |
| `path_autoneb.xyz` / `path_ts_list.xyz` | 未产出 | AutoNEB 属第二阶段 |
| `--lts-max-displ` | 新增（任务书建议列表外） | 标定中它是唯一能救回 GFN2 发散的旋钮，必须可从 CLI 复现 |
| `hessian_recalc` 语义 | L-BFGS 历史清空间隔 | band 无显式 Hessian；避免出现无人使用的字段 |
| `landscape_types/coords.f90` 增加 `align_geometry` | 公开新过程 | 对齐应只有一处实现；该文件属 landscape 自有代码，不违反"核心层不动" |
