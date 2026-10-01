# M3（Hessian / freq / thermo）复核后修复报告（第 23 号）

> 角色：修复者（单写者线程）。输入：复核报告 `22-m3-independent-review.md`（有条件接受，
> CRITICAL 0 / HIGH 1 / MEDIUM 2 / LOW 3 / INFO 3）、验证报告
> `21-m3-validation-experiments.md`（79 个作业 + `m3-vib-data/`）、实现报告
> `20-m3-vib-implementation-report.md`、工程约束 `AGENTS.md`。
> 所有 xtb/ctest 调用均为 `OMP_NUM_THREADS=1`；只跑 `-R` 过滤子集，未跑全量 ctest。

---

## 0. 结论摘要

| # | 问题 | 处置 | 状态 |
|---|---|---|---|
| HIGH-1 | `vib/modes.f90` 额外近零模分支用未初始化下标 | 第二个排序循环改为只跳过前 `n_zero` 个近零模 + 不变量检查 + 新单元测试 | ✅ 已修，注入实验旧码 **SIGSEGV** |
| MEDIUM-A | `--namespace` 下 `hessian` 双重加前缀 | 删掉任务层的 `get_namespace`，命名空间只由 writer 加一次 + CLI 写→读测试 | ✅ 已修 |
| MEDIUM-B | `landscape_engine_control%etemp` 死字段 | 选择方案 (a)：引擎把它**真正接进** xTB 计算器（与既有 `acc` 同机制）+ 记录/打印生效值 + 新单元测试 | ✅ 已修，注入实验（去掉 push）测试变红 |
| MEDIUM-C | `--lvib`↔`--hess` 差异归因错误 | **实测重做归因**：差异**主要**来自投影约定（投影项 ≈0.072–5.21 cm⁻¹），另有一条 ≤0.004 cm⁻¹ 的**非投影**残余（CO2 实测上界，来源未归因，§8.1）；删除“`trproj` 含梯度项”这一错误机制句；**并纠正任务书里的前提“`--hess` 用解析 Hessian”**（见 §4） | ✅ 已改（含一处与任务书不同的结论，已在 §4 明确说明） |
| LOW-1 | 缺 `--hess` 的“未优化几何”告警 | 加同阈值同措辞的 `env%warning` | ✅ 已修 |
| LOW-2 | 热化学参数无校验 | 任务入口集中校验 4 个参数 + 2 条 CLI 错误测试 | ✅ 已修 |
| LOW-3 | 文档/状态簿记 | PLAN §9.4/§12.11/§9.5、AGENTS §2/§6、报告 20 §3.3/§5.1/§5.3、报告 21 §5.3(d)/§5.5/F1/R5 全部更新；`results.f90`、`types/hessian.f90` 注释更正 | ✅ 已改 |
| INFO-1/2/3 | `vib_normal_modes` 索引约定；MAPLE 常数约定；全域未收敛扫描退出码 | 写入 PLAN §12.11 | ✅ 已记录 |

**验证汇总**：`ctest -R landscape` **35/35 pass**（0.95 s）；回归子集
`-R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'` **12/12 pass**；
`ctest -N -R landscape` = 35；`add_test` 重名检查为空。
发现并修复了一个**恒真的单元测试**（`water-vs-trproj`，见 §4.3）——它把已投影矩阵
再投影，因此“通过”不说明任何事。

---

## 1. HIGH-1：额外近零模分支用未初始化下标索引矩阵

### 1.1 修复

`src/landscape/vib/modes.f90`（排序内核）：

- 第二个循环原来对非线性分子 `cycle` 掉**所有** `|f| < zero_mode_tol` 的模式，
  于是 `order(n_zero+1:n3)` 只被部分赋值，随后 `work(:, order(i))` 用未初始化下标
  越界读取。现在**只跳过前 `n_zero` 个**近零模（计数器 `n_zero_seen`），多出来的
  近零模按升序落在内模列表里（模块文档承诺“从不丢弃一个模式”，实现现在与之一致）。
- 新增不变量检查：循环后 `k /= n3` 立即 `env%error` 并返回（“无法发生，但不假设”）。
- 物理论证（写在代码注释里）：一个 `|f| < 0.01 cm^-1` 且不是投影零模的模式，要么是
  秩亏矩阵的残余刚体模，要么是真正的软坐标；保留它**带符号的噪声值**可以区分这两者
  （正的噪声不能变成虚频，反之亦然）。既有实现（`src/hessian.F90:437`）把**所有**
  近零模都算作零模，然后把它没走到的列留成“零频率 + 零向量”，即丢掉该模式；本套件
  保留 `n_vib = 3N − n_zero` 的契约并如实报告额外模式。

### 1.2 新测试（可证伪）

`test/unit/test_landscape_vib.f90` 新增 `extra-zero-modes`：合成一个 3 原子（H,H,H，
第三个原子在 5 bohr 外且行列全零）的秩 1 Hessian → 投影后 8 个近零模（6 投影 +
2 extras）。断言：分析不失败、`n_zero = 6`、`n_vib = 3`、`count(|f|>1e-6) = 1`、
第 9 列是拉伸模（>1000 cm⁻¹）、两个额外模是最低内模、9 列**两两正交归一**
（重复列或未赋值列必然破坏正交性）、三个内模的约化质量均 > 0。

### 1.3 注入实验（真实输出）

把第二循环临时改回旧逻辑（去掉计数与不变量检查）后重建：

```
$ OMP_NUM_THREADS=1 XTBPATH=$PWD ./xtb-tester landscape-vib
  Starting extra-zero-modes ... (9/14)
Program received signal SIGSEGV: Segmentation fault - invalid memory reference.
Backtrace for this error: ...
$ echo $?          # 139（进程崩溃 ⇒ ctest 该 target 红）
```

还原修复后：`... extra-zero-modes [PASSED]`，`landscape-vib` 15/15。

---

## 2. MEDIUM-A：`--namespace` 下 `hessian` 双重加前缀

### 2.1 修复

`src/landscape/tasks/vib.f90` 的 `write_hessian_file`：
`call landscape_write_hessian_file(env, get_namespace('hessian'), hess, ok)`
→ `call landscape_write_hessian_file(env, 'hessian', hess, ok)`。
`get_namespace` 非幂等；命名空间现在只由 writer 加一次（`open_hessian_for_write`），
与读路径（`open_hessian_for_read`）和既有 `wrhess`/`open_file` 对称。`vib_normal_modes`
的名字仍由任务层一次性加前缀（那条路径本来只加一次，未改）。

### 2.2 新测试 + 实测

- CMake：`xtb/landscape-vib-namespace`（`test/unit/CMakeLists.txt` + 一个
  `landscape_cli_vib_namespace.cmake` 脚本）；meson 对等物：
  `test/unit/landscape_cli_check.py` 的 `check_vib_namespace` + `meson.build` 的
  `landscape vib namespace`。
- 手工复现（`--namespace ns`，水极小点几何）：

```
$ xtb h2o_opt.xyz --gfn2 --lvib --norestart --namespace ns      # exit 0
$ ls ns*      # ns.charges ns.g98.out ns.hessian ns.vib_normal_modes ns.vibspectrum ...
$ ls ns.ns.hessian      # No such file or directory   ← 双重前缀已消除
$ xtb h2o_opt.xyz --gfn2 --lvib --lvib-hessian file \
      --lvib-hessian-file hessian --norestart --namespace ns    # exit 0
 Hessian file:             hessian
eigval :     1539.15  3644.04  3652.39      # 直接路径（第一次运行）
eigval :     1539.15  3644.04  3652.39      # 从文件读回（第二次运行）
```

---

## 3. MEDIUM-B：`landscape_engine_control%etemp` 是死字段

### 3.1 机制确认（读码）

- `xtb_single::singlepoint(env, mol, chk, calc, egap, et, ...)` 收下 `et` 后
  **不转发**（`src/single.f90:52` 只调 `calc%singlepoint(env, mol, chk, prlevel, restart,
  etot, g, sigma, egap, res)`；抽象接口里根本没有 etemp 参数）。
- 真正生效的是 `TxTBCalculator%etemp`（`scf(..., self%etemp, ...)`，
  `src/xtb/calculator.f90:258`），它在构造时从全局 `set%etemp` 拷一次
  （`src/xtb/calculator.f90:144`）。
- 因此 `engine.f90` 把 `ctrl%etemp` 传进 `singlepoint` 是无效的，而缓存键
  （`engine.f90:472`）却用它，既能误导调用者又会产生伪缓存失效。

### 3.2 选择与理由（任务书给了二选一）

**选 (a)：让字段真正生效。** 理由：

1. 复核 F1 的首选项就是“把 `ctrl%etemp` 真正接到计算器”；本仓已有**同类先例**：
   `engine_set_calculator` 里 `self%calc%accuracy = self%ctrl%acc`，其注释明确写着
   “singlepoint 收到 `acc` 却丢弃，所以必须写进计算器”。这里照抄同一模式，概念只保留
   一种拼写。
2. 方案 (b)（删字段、只记录 `set%etemp`）会让 M4 的 `ts`/`irc` 无法在一次运行内
   显式冻结 `etemp`（报告 21 R3 的硬约束），而 `etemp` 是这套方法里最大的单一误差源
   （拉伸 H₂ 最低模 0→5000 K 漂移 −31.4 %）。
3. 任务书给的示例做法（“围绕调用同步全局 `set%etemp`”）**实测无效**：`calc%etemp`
   是构造时的一次拷贝，改全局不会改变它。因此实现走的是“写进计算器”，不是“改全局”。

实现（`src/landscape/engine/engine.f90`）：

- 新增私有 `push_calculator_etemp`：`select type (calc => self%calc); type is
  (TxTBCalculator); calc%etemp = self%ctrl%etemp`。只有 `TxTBCalculator` 携带电子温度，
  其他计算器（GFN-FF、外码）没有该字段，保持不动（注释写明）。
- `engine_set_calculator` 调用它（与 `accuracy` 同处）。
- `engine_report` 从**计算器读回**并打印 `landscape engine: etemp  <值> K`，
  让“设置没进去”从外部可见（与既有的 `SCC accuracy` 打印同思路）。
- `src/prog/main.F90`：三个 landscape 入口（`--lopt`/`--lscan`/`--lvib`）各加一行
  `…%engine%etemp = set%etemp`，保证 CLI `--etemp` 继续生效（否则引擎会用 300 K
  覆盖 CLI 值，属于回归）。
- `src/landscape/types/settings.f90`：字段与方法文档改写，说明“该值由引擎写进计算器”。
- **层次耦合说明**：引擎模块因此新增 `use xtb_xtb_calculator, only : TxTBCalculator`
  （首个具体计算器依赖）。这是 PLAN §4.3 “复用 xtb 私有模块” 的既定路线，且 `select type`
  对非 xTB 计算器是**无操作**（那些类型没有该字段），已实测 `--gfnff --lvib` /
  `--gfnff --lopt` 仍 exit 0（无回归）。

### 3.3 新测试 + 注入实验

`test/unit/test_landscape_vib.f90` 新增 `etemp-control`：拉伸 H₂（2.4 Å = 4.535 bohr，
即报告 21 §3.1 的近简并体系）在 `settings%engine%etemp = 300 K` 与 `5000 K` 下各做一次
FD Hessian + 频率分析，断言只有 1 个内模、且 `|Δf|/f > 10 %`。

注入实验（临时删掉 `call push_calculator_etemp(self)`）真实输出：

```
  Starting etemp-control ... (10/15)
       ... etemp-control [FAILED]
  Message: the electronic temperature did not change the Hessian
```

还原后 [PASSED]。（实测方向与量级：报告 21 的 579.90 → 397.56 cm⁻¹，−31 %。）

---

## 4. MEDIUM-C：`--lvib` ↔ `--hess` 差异的归因（实测重做）

> **本节的结论与任务书给的表述有一处不同**：任务书说“既有 `--hess` 用解析 Hessian，
> 套件用 FD”。**该前提被代码与实测否定**（§4.1）。归因“改用实测”这一要求本身照做，
> 但实测的结论是“差异来自**投影约定**”，而不是“解析 vs FD”。证据如下，全部可复现。

### 4.1 前提核对：`--hess` 也是数值（中心差分）Hessian

- `--hess` 自己的 stdout（本次重跑）：

```
          |                Numerical Hessian                |
step length          :   0.00500
SCC accuracy         :   0.30000
```

- 代码路径：`numhess`（`src/hessian.F90:232`）→ `calc%hessian` →
  `TCalculator::hessian_numdiff`（`src/type/calculator.f90:106-242`），双面中心差分，
  与套件 `landscape_numerical_hessian_provider` 同一公式、同步长、同精度。
  计时表里的 `analytical hessian`（`src/prog/main.F90:2840`）只是一个**固定标签**。
- 既有单元测试 `numerical-vs-calculator` 已断言：套件 provider 复现
  `TCalculator%hessian`（即 `--hess` 调用的那个例程）到 **< 1e-8** 绝对误差。

### 4.2 三点分解（同一矩阵，实测）

`test/unit/test_landscape_vib.f90` 的 `water-vs-trproj` 现在对**同一个原始** FD 矩阵分
别做 Eckart 与 `trproj`（修复了 §4.3 的恒真缺陷后打印）：

| 几何 | Eckart（套件） / cm⁻¹ | trproj（`--hess`） / cm⁻¹ | max‖Δf‖ |
|---|---|---|---|
| GFN2 极小点（`h2o_opt`） | 1539.1480 3644.0560 3652.3753 | 1539.1469 3644.0557 3652.3013 | **0.074** |
| 非驻点（`h2o_raw`） | 1565.0991 3629.7342 3642.9892 | 1565.0984 3634.9475 3643.6359 | **5.213** |
| 强扭曲水（测试几何） | 1318.0122 3716.0701 4141.5458 | 1318.5519 3706.8595 4128.6366 | **12.91** |

三列分别与 CLI 对应：trproj 列复现 `--hess`（1565.0969/3634.9513/3643.6221）、
Eckart 列复现 `--lvib`（1565.0984/3629.7404/3642.9747），误差 ~0.01 cm⁻¹（几何十进制截断）。

**独立交叉验证（numpy 重实现 + 外部 FD）**：

1. 用 18 次 `xtb --gfn2 --grad` 单点在 ±0.005 bohr 处做中心差分，得到一个与套件完全
   独立的原始 Hessian `H_ext`；把它写成 `hessian` 文件喂给套件（Eckart）：
   `1565.0998 / 3629.7239 / 3642.9889` ——复现**套件**的值，而 `--hess` 的
   `3634.9513` 差 5.2 cm⁻¹。
2. 在 numpy 里独立实现两条投影：`trproj(H_ext)` 与 `--hess` 写出的矩阵差 **3.6e-6**；
   `Eckart(H_ext)` 与 `--lvib` 写出的矩阵差 **4.0e-6**；两者的差矩阵是**秩 1**，
   主本征值 **3.39e-3**，与两份 CLI 文件之差（3.389e-3）一致。

CLI 层同几何重测（与第 21 号报告一致）：`--lvib` vs `--hess`
**0.0757（H2O 极小点）/ 0.9972（CH3OH 极小点）/ 0.0036（CO2）/ 5.2109（非驻点 H2O）** cm⁻¹。
CO2 是线性分子、两条路径**都跳过投影**，所以 0.0036 cm⁻¹ 是“非投影残余”（FD 实现差异）
的上界。

### 4.3 顺手发现：`water-vs-trproj` 原来是恒真测试

原测试先 `call landscape_vib_analysis(env, mol, hess, …)`（该例程 `intent(inout)`，
**会把参数就地换成投影后矩阵**），然后把 `hess`（已是 Eckart 投影矩阵）打包给 `trproj`。
于是它比较的是“同一矩阵的两次（近似幂等）投影”，永远通过——复核 §4 里“这个用例非循环”
的判断因此需要修正。修复：保留一份原始矩阵（`raw`），参照路径用它；容差按实测
（0.005·|f|+0.5 cm⁻¹），并增加一条**反向断言**“两者不得逐位相等”，防止有人再把参照
换成投影矩阵（注入实验：把 `raw` 换回 `hess` → `[FAILED] the two projections agree
trivially`）。

### 4.4 文档改写

- **PLAN §12.11**：整段重写（机制 + 分档数字 + “`--hess` 也是 FD”+“`trproj` 不含梯度项”）。
- **报告 20 §3.3/§5.1/§5.3**：归因、容差依据、状态簿记（实验 #2/#3/#12 已完成）。
- **报告 21 §5.3(d) 根因 2 / §5.5 / §6 F1 / §7 R5**：机制句删除并改为“不同度量里的
  同一套刚体运动”；5.71 单一数字作废，改分档；F1 标注已修；R5 标注已改。
- **PLAN §9.5（M4 硬约束）**：新增 3 条（冻结并记录 `etemp`；虚频附近必须收紧 FD 参数；
  **不得用“与 `--hess` 逐位一致”做判据**）。

---

## 5. LOW 项

| 项 | 修改 | 证据 |
|---|---|---|
| LOW-1 “未优化几何”告警 | `tasks/vib.f90` 在 `result%gnorm > 2.0e-3` 时打印 `!! INCOMPLETELY OPTIMIZED GEOMETRY !!` 并发 `env%warning`（阈值/措辞与 `src/hessian.F90:161-170` 一致；位置在任务末尾，不影响已有的 `landscape_log_failed` 判定） | `--lvib` 在 `h2o_raw` 上现在打印该行（`grep` 见 §7） |
| LOW-2 热化学参数校验 | `tasks/vib.f90` 新增 `check_thermo_settings`（在任何单点之前）：温度 > 0、`freq_scal` > 0、`imag_cutoff ≤ 0`、`rotor_cutoff ≥ 0`，违反即 `env%error` + 任务失败 | 新 CLI 测试 `xtb/landscape-vib-temperature-invalid`（`--lvib-temp 0`）与 `xtb/landscape-vib-imag-cutoff-invalid`（`--lvib-imag-cutoff 20`） |
| LOW-3.1 `results.f90` 注释 | `n_zero` 文档 “0 for a single atom” → “3 for a single atom” | 与 `modes.f90:132-141` 一致 |
| LOW-3.2 `types/hessian.f90` writer 文档 | “Only the lower triangle is stored” → 说明文件存的是**完整方阵**（下三角镜像写入）；测试名 `hessian-file-writer-format` → 实际存在的 `hessian-file-roundtrip` | 与 `wrhess` 逐字节比较的既有测试 |
| LOW-3.3 状态簿记 | PLAN §9.4、AGENTS §2、报告 20 §5.1 统一改为“实验 #2/#3/#12 已完成”并给出结论与位置 | 报告 21 |
| INFO-1/2/3 | 写入 PLAN §12.11（`vib_normal_modes` 行/列约定；MAPLE `2721.1383` = Eh/Å²+amu vs `autorcm` = Eh/bohr²+电子质量，~0.04 % 系统差；全域未收敛扫描退出码 0） | 复核报告 §2/§6 |

---

## 6. 变更文件清单（本轮）

**实现**

- `src/landscape/vib/modes.f90`：HIGH-1 修复 + 不变量 + 文档。
- `src/landscape/tasks/vib.f90`：MEDIUM-A（命名空间一次）+ LOW-1 告警 + LOW-2 校验。
- `src/landscape/engine/engine.f90`：MEDIUM-B（`push_calculator_etemp` + `engine_report`）。
- `src/landscape/types/settings.f90`：`landscape_engine_control` 文档（etemp/acc 语义）。
- `src/landscape/types/results.f90`：`n_zero` 注释。
- `src/landscape/types/hessian.f90`：writer 文档。
- `src/prog/main.F90`：三个 landscape 入口同步 `set%etemp`。

**测试**

- `test/unit/test_landscape_vib.f90`：新增 `extra-zero-modes`、`etemp-control`；
  修复 `water-vs-trproj`（原始矩阵 + 反向断言 + 实测容差）。
- `test/unit/CMakeLists.txt`：新增 `xtb/landscape-vib-namespace`、
  `xtb/landscape-vib-temperature-invalid`、`xtb/landscape-vib-imag-cutoff-invalid`
  （并登记到单线程与 XTBPATH 测试属性列表）。
- `test/unit/meson.build` + `test/unit/landscape_cli_check.py`：meson 对等物
  （`vibnamespace` 模式 + 两条 `error` 用例）。

**文档**

- `docs/xtb-landscape-PLAN.md`（§9.4、§9.5、§12.11）、
  `docs/_landscape-recon/20-*.md`（§3.3、§5.1、§5.3）、
  `docs/_landscape-recon/21-*.md`（§5.3(d)、§5.5、§6、§7）、
  `AGENTS.md`（§2 状态 + §6 新增实测事实）、本报告。

---

## 7. 本轮验证命令与输出（真实执行）

```
$ cmake --build /tmp/xtb-land/build -j
[100%] Built target xtb-tester

$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape
100% tests passed, 0 tests failed out of 35          # 0.95 s

$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build \
    -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
100% tests passed, 0 tests failed out of 12          # 0.25 s

$ ctest --test-dir /tmp/xtb-land/build -N -R landscape | tail -1
Total Tests: 35
$ grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d
                                    # 空 ⇒ 无重名

$ OMP_NUM_THREADS=1 XTBPATH=$PWD ./xtb-tester landscape-vib
  ... extra-zero-modes [PASSED] ... etemp-control [PASSED] ...   # 15/15
```

`--lvib` vs `--hess`（同几何，`m3-vib-data/mol/`，g98.out 频率）：

```
h2o_opt   lvib 1539.1468 3644.0390 3652.3852 | hess 1539.1454 3644.0390 3652.3095 | 0.0757
h2o_raw   lvib 1565.0984 3629.7404 3642.9747 | hess 1565.0969 3634.9513 3643.6221 | 5.2109
co2_opt   lvib  601.2640  601.2640 1423.5372 | hess  601.2604  601.2604 1423.5372 | 0.0036
ch3oh_opt lvib  363.4604 1029.7807 1090.5893 | hess  362.4753 1029.5240 1090.5823 | 0.9972
```

`--namespace` 往返（§2.2）与 `h2o_raw` 上的新告警：

```
$ grep -m1 "INCOMPLETELY" lvib/stdout.txt
 !! INCOMPLETELY OPTIMIZED GEOMETRY !!
```

回归检查（MEDIUM-B 的 `select type` 对其他计算器无操作）：

```
$ xtb h2o_opt.xyz --gfnff --lvib --norestart        # exit 0, modes: 3 internal, 6 projected zero modes
$ xtb h2o_opt.xyz --gfnff --lopt --norestart        # exit 0, landscape: converged
```

---

## 8. 残留风险 / 未决项

1. **`--hess` 与套件的“非投影”残余 ≤0.004 cm⁻¹**（CO2 实测）未能进一步归因到具体一行
   代码；它与两个 FD 驱动的 SCF 起始猜测/实现细节有关，量级远小于投影项（0.076–5.21），
   不影响 M4 的任何判据。
2. **`water-vs-trproj` 的容差是“测量出来的”**（0.5 % + 0.5 cm⁻¹）：它只能捕捉“投影被
   整体跳过/替换”这类错误，不能捕捉两条投影内部的细节回归——那由双原子解析用例与
   `water-modes-gfn2` 承担。
3. `--lvib-imag-cutoff` 仍要求用户显式带负号（`-20`）；`--lvib-freq-scal 0` 与
   `--lvib-rotor-cutoff <0` 走的是同一校验路径，但没有各自的 CLI 用例（矩阵可见性优先）。
4. `src/type/calculator.f90:695` 把**未初始化**的 `egap` 传给 `singlepoint`
   （`hlgap` 在计算器里是 `intent(out)` 且先被置 0，因此实测无影响）——属既有代码瑕疵，
   不在本次可改动范围，记录于此。
5. 临时诊断（Eckart/trproj 分解、外部 FD 对照）只在 `/tmp` 与临时单元测试中进行，
   **已全部移除**；仓库内保留的分解证据是 `water-vs-trproj` 本身。
