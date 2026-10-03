# 04 — `-O2` 切换与三条静默错误缺陷的修复（实现 + 实测报告）

> **性质**：实现报告。起点 `HEAD = 24c069f`（M0..M7 已提交）。
> **约定**：凡标 **★实测** 的都有真实命令与输出；「推断」= 有证据但未直接验证；「未验证」= 无数据。
> 所有 `xtb` / `ctest` 调用均 `OMP_NUM_THREADS=1`；全量 `ctest` **未跑**（AGENTS §4 禁令）。
> 三个构建目录并存：`/tmp/xtb-land/build`（**$24c069f$ 源码、`-O3`，修复前基线，未删除**）、
> `/tmp/xtb-o2/build`（**本轮源码、`-O2`**，官方档位）、`/tmp/xtb-o3/build`（**本轮源码、`-O3`**，用于隔离优化档变量）。

---

## 0. 结论速览

| # | 事项 | 结果 |
|---|---|---|
| 1 | `-O3` 异常（调查 C §4.4） | **在 `24c069f` 上未复现**（HEAD 的 `-O3` 正确）；**在 edcfbbe 上复现**（★实测，`-O3` 错、`-O0/-O1/-O2` 对、`-O3 -fno-tree-vectorize` 也错）⇒ 机制未定位 ⇒ 官方档位改 `-O2` |
| 2 | `-O2` 切换方式 | (a) 文档：AGENTS §4/§6 + PLAN 附录 A；(b) `cmake/CMakeLists.txt` 检测 `-O3` 时 `message(WARNING ...)`（28 行，逐行理由见 §1.2） |
| 3 | 缺陷① `--lopt-engine rfo` 违反 `$fix` | **机制定位到行**；**已修**（步向量投影到 `$fix` 允许子空间）；修后 6 个引擎位移全为 **0.00000e+00 Å** |
| 4 | 缺陷② `--lvib` 无条件覆盖 `$thermo` | **已修**（优先级：显式 CLI > xcontrol `$thermo` > 内置默认）；`--lvib` vs `--hess` 差从 **7.5e-3 Eh** 降到 **1.4e-8 Eh** |
| 4b | **新发现（同一缺陷类）** | `--lts`(PRFO/B-PRFO/dimer) 与 `--lirc`(HPC) 的核心步也**不**尊重 `$fix`（★实测固定 H 移动 0.12/0.15/0.15 Å 与 0.024 Å） |
| 4c | 第二轮（父会话批准范围 (B)） | **鞍点三方法已修**（修后位移 0.00000e+00 Å，bprfo/dimer 收敛）；**IRC 四方法与 band 五方法改为响亮报错**（契约级阻塞，设计分析见 §5.3） |
| 5 | 缺陷③ `--lopt` 静默忽略 `$scan` | **已修**（`--lopt/--lscan/--lts/--lirc/--lvib` + `$scan` ⇒ `env%error` + exit 1 + 可操作提示）；`--opt` 不受影响 |
| 6 | 测试 | 95 → **100** 个 landscape 测试（+1 单元用例 `fix-projection`、+5 ctest 条目），无重名 |
| 7 | 回归 | `-O2`：`ctest -R landscape` **100/100**，回归子集 **12/12**；`-O3`（同源码）：100/100、12/12 |
| 8 | 可证伪 | 三条原始缺陷 + 鞍点两处 + 两条 guard，共 **7 条注入**：**去掉机制 → 对应测试变红 → 还原 → 变绿**（§2.4/§3.4/§4.4/§5.2/§5.3） |
| 9 | M7 四体系验收 | **逐项复现**（dfreq 0.0100 / 0.0600 / 0.0000 / 0.0000 cm⁻¹）；`-O2` 与 `-O3` 在 h2o/ch3oh/co2 上 `hessian`+`vibspectrum` 逐字节相同，c2h2 只有**打印零的符号**与 9e-14 Å 舍入差（§1.4） |

---

## 1. `-O2` 切换

### 1.1 `-O3` 异常的复现 / 否定（★实测）

探测点 = 调查 C §5 实验 7：`--gfn2 --hess` 于 `water.xyz`，读 `vibspectrum` 的内部频率。

```bash
printf '3\nwater\nO 0.0 0.0 0.0\nH 0.0 0.757 0.586\nH 0.0 -0.757 0.586\n' > water.xyz
OMP_NUM_THREADS=1 XTBPATH=<repo> <bin> water.xyz --gfn2 --hess
```

| 构建 | 源码状态 | 优化档 | 频率（cm⁻¹） | 判定 |
|---|---|---|---|---|
| `/tmp/xtb-base/build` | **edcfbbe** | `-O3` | `-931.59  3329.78  3345.94` | **错**（★实测复现） |
| `/tmp/xtb-base/build-o3nov` | edcfbbe | `-O3 -fno-tree-vectorize` | `-931.59  3329.78  3345.94` | **同样错** ⇒ 排除向量化 |
| `/tmp/xtb-base/build-O2` | edcfbbe | `-O2` | `1557.41  3677.84  3684.01` | 对 |
| `/tmp/xtb-base/build-O1` | edcfbbe | `-O1` | `1557.41  3677.84  3684.01` | 对 |
| `/tmp/xtb-base/build-o0` | edcfbbe | `-O0` | `1557.41  3677.84  3684.01` | 对 |
| **`/tmp/xtb-land/build`** | **`24c069f`** | **`-O3`** | `1557.41  3677.84  3684.01` | **正确 ⇒ 本 HEAD 未复现** |
| `/tmp/xtb-o2/build` | 本轮源码 | `-O2` | `1557.41  3677.84  3684.01` | 正确 |
| `/tmp/xtb-o3/build` | 本轮源码 | `-O3` | `1557.41  3677.84  3684.01` | 正确 |

**结论（如实写）**：

* **本 HEAD 未复现**该 `-O3` 异常（探测范围内，`--hess` of H2O）。
  调查 C 的原文结论（「我们的 HEAD 源码在 `-O3` 下目前是正确的」）**成立**。
* 异常在 **edcfbbe** 上**确实存在且可复现**（`-O3` 错、`-O0/-O1/-O2` 对），
  且 **`-O3 -fno-tree-vectorize` 同样错** ⇒ 调查 C 的「已排除向量化」也成立。
* **仍然建议 `-O2`**，理由不是「我们的代码现在错」，而是：
  1. 机制**未定位**（既非向量化，也不是我们已排除的任何一项）⇒ 无法界定风险边界；
  2. 异常对**源码状态**敏感（156 个提交的差异就能翻转它），而 `src/landscape` 仍在演进；
  3. `-O2` 的代价**实测为零**：四个验收体系的 `hessian` 与 `vibspectrum` 在 `-O2`/`-O3` 下**逐字节相同**（§1.4），
     两档的整套 landscape 测试当时也都是 98/98（§1.3 的对照表跑在新增条目的**中间态**：
     那时只有 3 个新条目；最终计数是 **100/100**，见 §5.4 与 `06-w0-closeout-report.md`）。
* 「异常不在本 HEAD 出现」**不等于**「`-O3` 安全」；本报告不把 `-O3` 标记为已知编译器缺陷（BZ 级别证据不足），
  只标记为**不可依赖**。

### 1.2 切换方式（选 (a)+(b)，并给出逐行理由与 diff）

**为什么不选「只改文档」**：文档不会阻止任何人（包括本会话的下一个 agent）用 CMake 的
默认 `Release`（GNU 下就是 `-O3`）重新配置。一行 `message(WARNING)` 的成本是 0（不影响构建结果），
收益是把「静默用了不安全档位」变成可见事件。

**为什么选 `-DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"` 而不是 `RelWithDebInfo`**：
后者带 `-g`（体积/构建时间），而 `-DNDEBUG` 是与 `Release` 唯一的语义差异；显式写全两个 flag
后，用户拿到的仍然是「Release 语义」。等价的更短写法 `-DCMAKE_Fortran_FLAGS_RELEASE=-O2`
会丢掉 `-DNDEBUG`（xtb 源码里 `assert` 只有一个消费者），本报告统一用前者。

**`cmake/CMakeLists.txt` 的改动（★实测：`git diff` 原文，28 行新增 / 0 行删除）**

理由逐行：

| 行 | 为什么值得改上游构建文件 |
|---|---|
| `# This checkout supports -O2, not -O3, for GNU Fortran.` 起的 11 行注释 | 记录**实测**证据（频率、正确值、`-fno-tree-vectorize` 反证、未复现说明）与外部报告位置。没有这段，后来的维护者只会看到一条「无缘无故的 warning」，会把它删掉。 |
| `if(CMAKE_Fortran_COMPILER_ID MATCHES "GNU")` | 只对 GNU 生效：Intel/Flang 没有这份证据（调查 C §7 未验证项）。 |
| `set(xtb_opt_flags "${CMAKE_Fortran_FLAGS}")` + `string(APPEND ... " ${CMAKE_Fortran_FLAGS_${xtb_build_type}}")` | 覆盖两种真实用法：单配置生成器把优化档放在构建类型变量里（CI/我们的命令），而用户直接写 `-DCMAKE_Fortran_FLAGS=-O3` 也检测得到。 |
| `if(CMAKE_BUILD_TYPE)` 守卫 | `CMAKE_CONFIGURATION_TYPES` 多配置生成器下 `CMAKE_BUILD_TYPE` 为空、`CMAKE_Fortran_FLAGS_<BT>` 未定义，`string(APPEND ... " ")` 会成为空串；守卫避免这种拼法。 |
| `if(xtb_opt_flags MATCHES "(^| )-O3( |$)")` | 词边界匹配，避免 `-O3x`/`-march` 之类误报；这是**唯一**的判定逻辑。 |
| `message(WARNING ...)` | 措辞刻意保守：说「不支持」而不是「生成错误代码」，因为缺陷**在本 HEAD 未复现**；信息里给出可直接复制的修复命令。 |
| 放在 dialects 块之后 | 该位置已保证 `CMAKE_Fortran_COMPILER_ID` 已由 `project()` 解析；同时 `PARENT_SCOPE` 的 flags 设置尚未执行，不影响变量语义。 |

★实测三种配置的行为：

| 配置 | 结果 |
|---|---|
| `-DCMAKE_BUILD_TYPE=Release`（默认 `-O3`） | `CMake Warning at cmake/CMakeLists.txt:79`，configure rc=0 |
| `-DCMAKE_BUILD_TYPE=Release -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"` | **0 warning** |
| `-DCMAKE_BUILD_TYPE=RelWithDebInfo`（= `-O2 -g -DNDEBUG`） | **0 warning** |

警告原文（★实测）：

```
CMake Warning at cmake/CMakeLists.txt:79 (message):
  Fortran optimisation level -O3 is not supported for this checkout: gfortran
  12.2.0 gave wrong Hessian results at -O3 for a numerically related source
  state (mechanism unknown, docs/_simplify-recon/03-build-and-toolchain.md
  section 4.4).  Use -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG" with
  -DCMAKE_BUILD_TYPE=Release.
```

**官方构建命令（已写入 `AGENTS.md` §4 与 `docs/xtb-landscape-PLAN.md` 附录 A）**：

```bash
cmake -S . -B /tmp/xtb-o2/build \
      -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"
cmake --build /tmp/xtb-o2/build -j
```

### 1.3 `-O2` 与 `-O3` 的全套对照（★实测，同一份源码）

```bash
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-o2/build -R landscape
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-o3/build -R landscape
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-o2/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
```

| 构建 | `-R landscape` | 回归子集 | 耗时 |
|---|---|---|---|
| `/tmp/xtb-o2/build`（本轮源码，`-O2`） | **98/98 passed**（中间态，见 §5.4） | **12/12 passed** | 30.32 s |
| `/tmp/xtb-o3/build`（本轮源码，`-O3`） | **98/98 passed**（中间态，见 §5.4） | **12/12 passed** | 28.81 s |
| `/tmp/xtb-land/build`（`24c069f` 源码，`-O3`，修复前） | 95/95 passed（修复前基线） | 12/12 passed | — |

测试名唯一性（AGENTS §4 硬要求，★实测）：

```
$ grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d
(no output)
$ ctest --test-dir /tmp/xtb-o2/build -N -R landscape | tail -2
Total Tests: 98        # 当时的中间态；补齐 lts/lirc 两条后为 100（见 §5.4）
```

### 1.4 M7 四体系验收表复现（★实测，含 `-O2`/`-O3` 对照）

夹具直接取 M7 验证轮留下的原始输入
`docs/_landscape-recon/m7-e2e-data/exp1-thermo/<mol>/<mol>.xyz`，流程与
`landscape_e2e_check.py chain` 一致（`--lopt --lopt-level tight` → 用 `xtbopt.xyz` 跑
`--lvib` 与 `--hess` → 比较内部频率与 ZPE/H/G）。

```bash
OMP_NUM_THREADS=1 XTBPATH=$PWD python3 test/unit/landscape_e2e_check.py chain \
    <bin> docs/_landscape-recon/m7-e2e-data/exp1-thermo/<mol>/<mol>.xyz <rundir> 1.0
```

| 体系 | 构建 | max dfreq (cm⁻¹) | dZPE (Eh) | dH (Eh) | dG (Eh) |
|---|---|---|---|---|---|
| H2O | `-O2` 本轮 | **0.0100** | 1.429e-08 | 1.426e-08 | 1.429e-08 |
| H2O | `-O3` 本轮 | **0.0100** | 1.429e-08 | 1.426e-08 | 1.429e-08 |
| H2O | `-O3` 修复前 | **0.0100** | 1.429e-08 | 1.426e-08 | 1.429e-08 |
| CH3OH | `-O2` 本轮 | **0.0600** | 2.975e-07 | 3.070e-07 | 2.530e-07 |
| CH3OH | `-O3` 本轮 | **0.0600** | 2.975e-07 | 3.070e-07 | 2.530e-07 |
| CH3OH | `-O3` 修复前 | **0.0600** | 2.975e-07 | 3.070e-07 | 2.530e-07 |
| CO2（线性） | `-O2` 本轮 | **0.0000** | 1.709e-08 | 1.296e-08 | 1.908e-08 |
| C2H2（线性） | `-O2` 本轮 | **0.0000** | −3.400e-11 | −2.100e-11 | −4.200e-11 |

频率本身也逐项复现（★实测）：H2O `1539.58 3643.01 3651.17`；
CH3OH `232.10 505.67 705.93 750.27 1129.85 1184.24 1397.63 1469.30 2750.31 2841.28 3340.70 3474.13`；
CO2 `600.32 600.32 1424.78 2593.06`；C2H2 `492.17 492.17 849.00 849.00 2155.46 3351.71 3427.76`
——与 `m7-e2e-data/exp1-thermo/summary.json` 中的记录完全一致。

**数字没有变化** ⇒ 无需逐项解释原因。补一条更强的证据（★实测）：

```
$ diff -q /tmp/o2fix/acc/o2-h2o/vibspectrum /tmp/o2fix/acc/o3-h2o/vibspectrum   # identical
$ diff -q /tmp/o2fix/acc/o2-h2o/hessian    /tmp/o2fix/acc/o3-h2o/hessian        # identical
$ diff -q .../o2-ch3oh/vibspectrum .../o3-ch3oh/vibspectrum                     # identical
$ diff -q .../o2-ch3oh/hessian    .../o3-ch3oh/hessian                          # identical
```

⇒ 在本项目的数值域内 **`-O2` 与 `-O3` 不可区分**，因此「切到 `-O2`」是**行为中性**的保守化。

**一处必须如实修正（★实测）**：h2o / ch3oh / co2 的 `hessian` 与 `vibspectrum` **逐字节相同**，
但 **c2h2（线性分子）的 `hessian` 文本不同**。逐值比较后确认这不是数值差异：

```
n=144/144 tokens  max|delta| = 0.000e+00  n_absdiff_nonzero = 0
几何（含 energy/gnorm 记号）max|delta| = 8.993e-14
```

差异只有两类：(i) **打印出的零的符号**（`-0.0000000000` vs `0.0000000000`）；
(ii) 线性分子轴对称化在**第 13 位小数**上的舍入（9e-14 Å）。
`vibspectrum` 与 7 个频率在两者下逐位一致。⇒ 结论「-O2 与 -O3 在本项目数值域内不可区分」成立，
但「逐字节相同」只对非线性体系成立，**不得**写成普遍命题。

---

## 2. 缺陷①：`--lopt-engine rfo` 违反 `$fix`（固定原子会移动）

### 2.1 机制定位（逐行证据，不是推测）

**`$fix` 在哪一层生效**：**计算器层**，方式是把固定原子的梯度分量置零。

```
src/xtb/calculator.f90:300-307
   energy = energy + efix
   results%e_total = energy
   results%gnorm = norm2(gradient)
   if (fixset%n.gt.0) then
      do i=1, fixset%n
         gradient(1:3,fixset%atoms(i))=0      <-- 全部机制只有这一处
      enddo
   endif
```

* 同一处理在 `src/tblite/calculator.F90`、`src/gfnff/calculator.f90`、四个 `src/extern/*` 计算器里各有一份。
* `$fix` **不**属于 ANCopt：ANCopt 额外做的是「自由度收缩 + 投影」
  （`src/optimizer.f90:367-371` 的 `nvar = nat3-3*fixset%n-3` 与 `:501` 的 `trproj(...,-1,...)`），
  那是**第二**道保险，套件没有继承。
* landscape 套件的引擎**经过** `xtb_single::singlepoint` 调计算器
  （`src/landscape/engine/engine.f90:531`），所以套件拿到的梯度**已经是置零后的**。

**为什么一阶方法对、RFO 错**：

| 算法 | 方向来源 | 固定分量为何为 0 |
|---|---|---|
| SD | `d = -g`（`src/landscape/optimize/sd.f90:43`） | `g` 在该分量为 0 |
| CG | `d = -g + β d_old`（`src/landscape/optimize/cg.f90`） | 两项在该分量都为 0 |
| L-BFGS / BFGS | `d = -H g`，`H` 由修正对 `(s, y)` 更新（`src/landscape/optimize/{lbfgs,bfgs}.f90`）。`s`、`y` 在固定分量上恒为 0，可证 **H 的固定块与自由块保持解耦**：初始 `H` 对角 ⇒ `H e_i = h_ii e_i`（`i` 固定）⇒ 秩 1/秩 2 更新（BFGS/SR1/Bofill/Powell 同构）只作用于非固定块 | `g` 为 0 且 `H` 解耦 |
| GDIIS | `d = Σ c_i x_i − x`，`Σ c_i = 1`（`src/landscape/optimize/diis.f90:202`），所有快照在固定分量上与当前几何**完全相同** | 求和恒等消去 |
| **RFO** | `step = −Σ_i (V_i·g)/(w_i−λ) V_i`（`src/landscape/optimize/rfo.f90:197-199`） | **不成立**：`V_i` 是**完整** Hessian 的本征矢，其固定分量一般非零；`g` 在固定分量为 0 只保证标量因子 `(V_i·g)≠0` 来自自由分量，**不影响** `V_i` 在固定分量上的展开系数 |

⇒ **「梯度为零」不蕴含「步长为零」**：父会话的怀疑机制**确认**（不是推翻）。

**修前实测（★实测，`/tmp/xtb-land/build/xtb`，`24c069f` 源码）**

夹具：`landscape_h2o.xyz`（O 在原点）+ `$fix atoms: 1`。

| 引擎 | 固定 O 的收敛坐标 (Å) | 位移 (Å) |
|---|---|---|
| sd | `0.00000000000000  0.00000000000000  0.00000000000000` | 0.00000e+00 |
| cg | 同上 | 0.00000e+00 |
| lbfgs | 同上 | 0.00000e+00 |
| bfgs | 同上 | 0.00000e+00 |
| diis | 同上 | 0.00000e+00 |
| **rfo** | `-0.00977962683586  -0.00000000000000  -0.01091766805310` | **1.09177e-02** |

（另一个夹具水、O 初始 z = −0.735 Å：`rfo` 漂移 9.23452e-03 Å；
调查 A 在第三个体系测到 0.183 Å —— 量级随体系变化，但**方向一致**。）

### 2.2 修复

* **新增模块** `src/landscape/types/constraints.f90`（104 行，`xtb_landscape_constraints`）：
  * `landscape_frozen_mask(nat)` → `logical(3N)`，从 `xtb_fixparam::fixset` 读出 `$fix` 原子
    （`fixset%n == 0` 或 `atoms` 未分配时返回全 `.false.`；越界索引跳过，不越界写内存）。
    **只读 `fixset`**，不读 `freezeset`（后者只影响 Hessian 投影）。
  * `landscape_project_frozen(vector, frozen)` → 把 `vector` 的固定分量置零（正交投影）。
  * 模块头把上面的「一阶 vs 二阶」逐行论证写成文档注释；新增文件已登记
    `src/landscape/CMakeLists.txt` 与 `src/landscape/meson.build`。
* **`src/landscape/optimize/driver.f90`**：`landscape_optimize_model` 增加可选实参
  `frozen(:)`；在每次算出方向之后、**应用步之前**做一次投影：
  ```fortran
  if (constrained) call landscape_project_frozen(d, fix_mask)
  ```
  这是**唯一的**不变式点（对 SD/CG/L-BFGS/GDIIS 是可证的空操作，对 RFO 是全部修复；
  BFGS 只在**解耦初值**下可证——`--lopt-hessian model` 用 Lindh-D2 曲率矩阵做种子，
  此时投影不是空操作，见 `src/landscape/types/constraints.f90` 模块头与 06 报告 §2.3）。
  投影后方向仍是下降方向（梯度在固定分量为 0 ⇒ `g·P d = g·d < 0`），
  且 `predicted` 仍是被取步长的模型下降的**上界**，`rho` 语义不变。
  缺省（无 `frozen` 或全 `.false.`）逐位复现旧行为。
* **四个调用点**各传自己的 `$fix` 掩码（因此 `--lopt`、`--lscan` 的松弛内层、`--lts` 端点松弛、
  `--lirc` 端点松弛都覆盖到）——**按子程序名引用，不写行号**（行号会随编辑漂移，
  本报告初版的四个行号就已因新增守卫行全部过期，见 06 报告 §2.4）：
  `tasks/opt.f90` 的 `landscape_optimize`（`frozen=fix_mask`）、
  `scan/relax_scan.f90` 的 `landscape_scan_relax_point`（`frozen=landscape_frozen_mask(...)`）、
  `tasks/ts.f90` 的 `relax_one_endpoint`、`tasks/irc.f90` 的 `relax_endpoint`。
  `--lopt` 额外在 stdout 打印一行 `fixed atoms ($fix): N (three components each)`。

### 2.3 逐引擎固定原子位移表（修前 / 修后，★实测）

| 引擎 | 修前位移 (Å) | 修后位移 (Å) | 修后收敛步数 | 修后总能量 (Eh) |
|---|---|---|---|---|
| sd | 0.00000e+00 | **0.00000e+00** | — | — |
| cg | 0.00000e+00 | **0.00000e+00** | — | — |
| lbfgs | 0.00000e+00 | **0.00000e+00** | — | — |
| bfgs | 0.00000e+00 | **0.00000e+00** | — | — |
| diis | 0.00000e+00 | **0.00000e+00** | — | — |
| **rfo** | **1.09177e-02** | **0.00000e+00** | 18 | −5.070544411705 |

修复还顺带修掉了一个**隐性错误结果**：修前 RFO+`$fix` 收敛到的是
**约束被破坏**的几何（final energy −5.070544309697，且 22 步里前两步被拒、trust 反复收缩），
修后收敛到真正的约束极小（−5.070544411705，**更低**）。

**无 `$fix` 路径逐位不变**（★实测，`-O3` 修复前 vs `-O2` 修后）：

| 命令 | `-O3` 修复前 | `-O2` 修后 |
|---|---|---|
| `--lopt-engine rfo`（无 xcontrol） | `−0.00000000000000  0.00000000000012  −0.23370288082372` | 同左（逐位） |
| `--lopt`（默认 lbfgs） | `0.00000000000000  0.00000000000000  −0.23361526524912` | 同左（逐位） |

### 2.4 测试与注入

**测试 1（单元，解析势，决定性）**：`test/unit/test_landscape_optimize_math.f90`
新增用例 `fix-projection`（+ 潜势模块 `test/unit/landscape_testpot.f90` 新增
`landscape_quadratic_fix_model`：Hessian `[[4,3],[3,4]]`，梯度在固定分量置零，模拟计算器）。
起点 `(1,1)`、冻结分量 1 ⇒ 梯度 `(0,7)`、无投影的 RFO 步为 `(−3,4)`（固定分量移动 **3 bohr**）；
约束极小是 `(1,−0.75)`。断言：`result%converged`、
`|x(1)−1| < 1e-12`、`|x(2)+0.75| < 1e-8`，对**全部 6 个引擎**循环。

**测试 2（CLI）**：`test/unit/landscape_cli_check.py:check_fix`（新 mode `fix`）+
CMake 测试 `xtb/landscape-fix-rfo` + meson 测试 `landscape fix rfo`。
6 个引擎各跑一次真实 GFN2 极小化，断言固定 O 的 3 个分量 `<= 1e-10 Å`
（容差来源：xyz 写出/读回的 14 位十进制往返，**不是**实测离散度 —— 投影之后该坐标逐位不变）。

```
fix projection: sd    frozen atom displacement 0.00000e+00 angstrom
fix projection: cg    frozen atom displacement 0.00000e+00 angstrom
fix projection: lbfgs frozen atom displacement 0.00000e+00 angstrom
fix projection: bfgs  frozen atom displacement 0.00000e+00 angstrom
fix projection: diis  frozen atom displacement 0.00000e+00 angstrom
fix projection: rfo   frozen atom displacement 0.00000e+00 angstrom
```

**注入（可证伪，★实测）**：把 `driver.f90` 的唯一投影语句注释掉
（`if (constrained) call landscape_project_frozen(d, fix_mask)` →
`! INJECTED (defect 1): ...`）。这是**纯删除**，与修前逻辑语义等价（修前根本没有这一步，
不存在「等价替代实现」的陷阱，M4 教训）。

| 测试 | 注入后 | 还原后 |
|---|---|---|
| `xtb/landscape-optimize-math` | **RED**：`Message: rfo moved the frozen component` | GREEN |
| `xtb/landscape-fix-rfo` | **RED**：`FAIL: --lopt-engine rfo moved the frozen atom by 1.09177e-02 angstrom (-0.00977962683586 -0.00000000000000 -0.01091766805310)` | GREEN |

---

## 3. 缺陷②：`--lvib` 无条件覆盖 xcontrol `$thermo`

### 3.1 机制定位（file:line）

`src/landscape/vib/thermo.f90:167-180`（修前原文）：

```fortran
subroutine landscape_vib_set_thermo_settings(settings)
   ...
   ntemp = max(1, min(settings%n_temperature, size(set%thermotemp)))
   set%nthermo = ntemp
   set%thermotemp(1:ntemp) = settings%temperature(1:ntemp)   ! 无条件
   set%thermo_sthr = settings%rotor_cutoff                   ! 无条件
   set%thermo_ithr = settings%imag_cutoff                    ! 无条件
   set%thermo_fscal = settings%freq_scal                     ! 无条件
```

而 `lvset` 的默认是 `n_temperature = 1`、`temperature(1) = 298.15`、`rotor_cutoff = 50.0`、
`imag_cutoff = -20.0`、`freq_scal = 1.0`（`src/landscape/types/settings.f90`）。
`set%thermo_*` 在 `read_userdata`（`src/prog/main.F90:473`）时**已经**是 `$thermo` 的值，
所以这四行是「用默认值把用户设置覆盖回去」。

**`$thermo` 的全部键（穷举，不是抽样）**：`src/set_module.f90:1960-2014` 的 `set_thermo`
只有一个 `select case(key)`，共 **4** 个键：

| `$thermo` 键 | 写入的全局 | 对应 landscape 字段 | 对应 CLI flag |
|---|---|---|---|
| `temp`（逗号列表） | `set%thermotemp(1:nthermo)`、`set%nthermo` | `temperature(1:50)`、`n_temperature` | `--lvib-temp` |
| `sthr` | `set%thermo_sthr` | `rotor_cutoff` | `--lvib-rotor-cutoff` |
| `imagthr` | `set%thermo_ithr` | `imag_cutoff` | `--lvib-imag-cutoff` |
| `scale` | `set%thermo_fscal` | `freq_scal` | `--lvib-freq-scal` |

（`set_module.f90:2912-2913` 的 `set` legacy 路径把 `thermo`/`thermo_sthr` 映射到同一对键，无新增。）

**修前实测（★实测，h2o 夹具、同一 input 文件、同一几何）**

| input | `--hess` total free energy (Eh) | `--lvib` total free energy (Eh) | 差 (Eh) |
|---|---|---|---|
| `$thermo temp=298.15,300.0,400.0` | −5.074961878677 | −5.067463972102 | **7.50e-03** |
| `$thermo scale=0.9000 temp=298.15` | −5.069471144738 | −5.067463972102（**完全忽略 scale**） | 2.01e-03 |

父会话测到 7.5e-3 Eh（≈4.7 kcal/mol）；本报告复现同量级（7.50e-3），
而 M3/M7 已验收的「相同热化学设置下 1e-7」差 5 个数量级 ⇒ **只能是热化学设置不同**。

### 3.2 修复

* `src/landscape/types/settings.f90`：新增 4 个显式标志
  `temperature_was_set`、`rotor_cutoff_was_set`、`imag_cutoff_was_set`、`freq_scal_was_set`
  （缺省全 `.false.`，并写明「为什么需要标志」：单看数值无法区分「用户显式给 298.15」
  与「用了默认 298.15」）。
* `src/prog/main.F90:3764/3780/3797/3813`：四个 `--lvib-*` case 在赋值后置对应标志。
* `src/landscape/vib/thermo.f90`：`landscape_vib_set_thermo_settings` 改为优先级语义，
  并把 4 个键的穷举与优先级规则写进过程文档注释：
  ```fortran
  if (settings%temperature_was_set) then
     ntemp = max(1, min(settings%n_temperature, size(set%thermotemp)))
     set%nthermo = ntemp
     set%thermotemp(1:ntemp) = settings%temperature(1:ntemp)
  end if
  if (settings%rotor_cutoff_was_set) set%thermo_sthr = settings%rotor_cutoff
  if (settings%imag_cutoff_was_set) set%thermo_ithr = settings%imag_cutoff
  if (settings%freq_scal_was_set)   set%thermo_fscal = settings%freq_scal
  ```
  没有标志时**完全不碰** `set`，于是 `$thermo`（或内置默认）原样生效。
* `src/xhelp.f90`：`--lvib` 帮助补三行说明该优先级（「静默」变「明示」）。
* **API 语义变化（显式记录）**：直接构造 `landscape_vib_settings` 的调用者若要覆盖
  `$thermo`，必须同时置 `*_was_set`。本仓库内**没有**这样的调用者
  （★实测：`grep -rn 'freq_scal|n_temperature|%temperature|rotor_cutoff|imag_cutoff' test/unit/*.f90 test/unit/*.py`
  在 landscape 设置上零命中）。

### 3.3 修后实测（★实测）

题面要求「`--hess` 的数值是参照，不是逐位相等」——本报告的比较在**tight 极小**上做，
即 M7 校准那个容差的地方。

| 输入 | 量 | `--lvib` − `--hess` (Eh) | M7 容差 |
|---|---|---|---|
| `$thermo temp=298.15,300.0,400.0` | dH | **1.417e-08** | 1.4e-6 |
| 同上 | dG | **1.431e-08** | 1.4e-6 |
| `$thermo scale=0.9000 temp=298.15` | dH | **1.282e-08** | 1.4e-6 |
| 同上 | dG | **1.287e-08** | 1.4e-6 |

（修前同两个输入分别是 7.50e-03 / 2.01e-03 —— 下降 **5 个数量级**。
剩余 ~1.4e-8 就是 AGENTS §6 记录的「Eckart vs `trproj` 投影约定」残差。）

三条**独立**的优先级路径（★实测，同一 tight 极小）：

| 断言 | 实测 |
|---|---|
| `temp=298.15,300.0,400.0` 产生 3 行温度表 | 3 行全在（298.15 / 300.00 / 400.00） |
| 列表的汇总值 = 最后一个温度（400 K）的值 | `list` G = `temp400` G = −5.075559458440 Eh（差 < 1e-9） |
| xcontrol 覆盖内置默认 | `-I temp400.inp` G = −5.07556 vs 无 input G = −5.06805（差 7.5e-3） |
| 显式 CLI 覆盖 xcontrol | `--lvib-temp 400 -I temp298.inp` G == `--lvib-temp 400` G（逐位 −5.075559458440） |
| `scale`：xcontrol == CLI | `-I scale.inp` G == `--lvib-freq-scal 0.9` G == −5.070058307265 Eh |
| `scale`：确实生效 | 与无 input（−5.068045050015）差 2.0e-3 |

### 3.4 测试与注入

**测试**：`test/unit/landscape_cli_check.py:check_thermo`（新 mode `thermo`）
+ CMake 测试 `xtb/landscape-vib-thermo` + meson 测试 `landscape vib thermo`。
流程：先 `--lopt --lopt-level tight` 取极小几何，再把上面 6 条断言全部跑一遍。
容差 1e-6 Eh 有出处（M7 `THERMO_TOL`，70× 实测残差），且 1e-9 用于「两条路径必须逐位一致」
的判等（它们走的是同一整型路径）。

**注入（可证伪，★实测）**：把 `landscape_vib_set_thermo_settings` 的 4 个 `if (..._was_set)`
守卫**还原成修前的无条件 4 行**（纯语义回滚，逐字采用调查 B 记录的原文）。

| 测试 | 注入后 | 还原后 |
|---|---|---|
| `xtb/landscape-vib-thermo` | **RED**：`FAIL: the --lvib and --hess thermochemistry disagree on list by ...` | GREEN |

---

## 4. 缺陷③：`--lopt` 静默忽略 `$scan`

### 4.1 机制定位（file:line）

* `$scan` 只被 **ANCopt 家族**消费：`src/prog/main.F90` 的 `anyopt` 分支
  （子程序内相对位置：`geometry_optimization` 调用之后、`if (nscan > 0)` 守卫内；
  **不写行号**，本报告初版的 `:914-916` 已因新增守卫行过期，见 06 报告 §2.4）
  ```fortran
  if (anyopt) then
     ... call geometry_optimization(...)
     if (nscan > 0) then
        call relaxed_scan(env, mol, chk, calc)   ! 只有这条路径
     end if
  ```
  `anyopt` 在 `src/prog/main.F90:314-316` 定义为 `p_run_opt/ohess/omd/screen/metaopt`，
  **不含任何 landscape 运行类型**。
* 五个 landscape 运行类型（`p_run_lopt/p_run_lscan/p_run_lts/p_run_lirc/p_run_lvib`）
  的代码块里对 `nscan`/`scan_list` **零引用**（★实测 `grep -rn 'nscan\|scan_list' src/landscape/` → 0 命中，
  且 `main.F90` 的 landscape 块里也没有）。

**修前实测（★实测，同一 input 含 `$constrain` + `$scan`）**

| 命令 | exit | `xtbscan.log` | stdout |
|---|---|---|---|
| `--opt` | 0 | **有** | `RELAXED SCAN / output written to xtbscan.log` |
| `--lopt` | **0** | **无** | **零诊断** |
| `--lvib` | **0** | 无 | 零诊断 |

⇒ 用户把脚本里的 `--opt` 换成 `--lopt`，得到的是**一次优化 + 退出码 0 + 没有扫描**。

### 4.2 修复

`src/prog/main.F90` 在 `read_userdata` 之后、任何任务运行之前加一段守卫（+39 行，
含 15 行注释与一个 `character(len=16) :: lruntyp_flag` 局部变量）：

```fortran
call read_userdata(xcontrol, env, mol)

! ------------------------------------------------------------------------
! the xcontrol `$scan` block belongs to the ANCopt family
! ...（注释解释：relaxed_scan 只在 anyopt 路径，landscape 运行类型都不执行它）
lruntyp_flag = ''
select case (set%runtyp)
case (p_run_lopt);  lruntyp_flag = '--lopt'
case (p_run_lscan); lruntyp_flag = '--lscan'
case (p_run_lts);   lruntyp_flag = '--lts'
case (p_run_lirc);  lruntyp_flag = '--lirc'
case (p_run_lvib);  lruntyp_flag = '--lvib'
end select
if (nscan > 0 .and. len_trim(lruntyp_flag) > 0) then
   call env%error(trim(lruntyp_flag)//" does not execute the xcontrol "//&
      & "$scan block: use --opt to run it, or --lscan with "//&
      & "--lscan-coord/--lscan-atoms for a scan of the landscape suite", source)
end if
call env%checkpoint("the run type does not execute the xcontrol $scan block")
```

* 用既有的 `env%error` + `env%checkpoint`（AGENTS 硬约束：不许 `stop`/`error stop`）。
* 错误信息**给可操作替代**：`--opt`（跑 `$scan` 块）或 `--lscan --lscan-coord`（套件自己的扫描）。
* `--opt`/`--scan` 家族不受影响（不在 `select` 内，`lruntyp_flag` 为空）。
* `src/xhelp.f90` 的 `--lopt` 帮助补两行说明这一点。

**修后实测（★实测）**

```
$ xtb water.xyz --gfn2 --lopt -I xscan      # xscan 含 $constrain + $scan
########################################################################
[ERROR] Program stopped due to fatal error
-2- the run type does not execute the xcontrol $scan block
-1- prog_main: --lopt does not execute the xcontrol $scan block: use --opt to run it,
    or --lscan with --lscan-coord/--lscan-atoms for a scan of the landscape suite
########################################################################
exit = 1
```

| 命令 | exit | `xtbscan.log` |
|---|---|---|
| `--lopt` + `$scan` | **1** | 无 |
| `--lscan`（带合法的 `--lscan-*`）+ `$scan` | **1** | 无 |
| `--lts` + `$scan` | **1** | 无 |
| `--lirc` + `$scan` | **1** | 无 |
| `--lvib` + `$scan` | **1** | 无 |
| **`--opt` + `$scan`** | **0** | **有**（RELAXED SCAN，3 点） |

### 4.3 「套件任务 × xcontrol 块」处理方式表（横向排查）

方法：先按**消费者**分类（静态证据，`file:line`），再对每条给出「执行 / 消费 / 忽略」的判定与处置。
`消费者`一列：**CALC** = 计算器层（所有走 `singlepoint` 的任务都吃到，含全部 landscape 任务）；
**MAIN/ANC** = 只在上游对应运行类型的路径上生效。

| xcontrol 块 | 消费者（证据） | `--lopt` | `--lscan` | `--lts` | `--lirc` | `--lvib` | 处置 |
|---|---|---|---|---|---|---|---|
| `$constrain` | CALC：`src/xtb/calculator.f90:293` `constrain_pot(potset,...)`；`src/landscape/scan/relax_scan.f90:59` 另用 `xtb_constrainpot` | 消费 | 消费 | 消费 | 消费 | 消费 | 无（正确）★实测：`--lopt` 打印 `constraining bond 1 2 to 0.9600001 Å`，E 由 −5.070544447778 变 −5.070544355564 |
| `$fix` | CALC：`src/xtb/calculator.f90:304-306` 梯度置零 | 消费 | 消费 | 消费 | 消费 | 消费 | **本轮修复**：二阶步额外投影（§2） |
| `$wall` | CALC：`src/xtb/calculator.f90:295` `cavity_egrad(...)`（静态证据） | 消费 | 消费 | 消费 | 消费 | 消费 | 无（未做运行实验，标「静态」） |
| `$metadyn` | CALC：`src/xtb/calculator.f90:296-297` `metadynamic(metaset/rmsdset,...)`（静态） | 消费 | 消费 | 消费 | 消费 | 消费 | 无（未做运行实验，标「静态」） |
| `$gbsa`/`$solvation`、`$embedding`、`$external` | CALC（GBA/PC 势在计算器内） | 消费 | 消费 | 消费 | 消费 | 消费 | 无 |
| `$scc`、`$gfn`、`$cma`、`$symmetry` | CALC / 主程序（与任务无关的电子结构设置） | 消费 | 消费 | 消费 | 消费 | 消费 | 无 |
| **`$scan`** | MAIN/ANC：`src/prog/main.F90` 的 `anyopt` 分支（`if (nscan > 0)` 守卫，**不写行号**） | **报错** | **报错** | **报错** | **报错** | **报错** | **本轮修复**（§4.2） |
| `$hess`（`step`/`sccacc`） | MAIN/ANC：`set%step_hess`/`set%accu_hess` | 忽略 | 忽略 | 忽略 | 忽略 | 忽略 | **明确文档化**：套件自带 FD Hessian 参数（`--l*-step`/`--l*-sccacc`），源码注释写明「**deliberately 不读** `set%step_hess`/`set%accu_hess`」（`src/landscape/vib/numhess.f90:33`、`src/landscape/types/settings.f90:561`）。另外上游本就有同一处异常：不带 `--copy` 时 `$hess` 的数值键对 `--hess` 也**无效**（AGENTS §6.3） |
| `$opt`（ANCopt 参数：`optlevel`/`micro_opt`/`average_conv`…） | MAIN/ANC：`set%optset` | 忽略 | 忽略 | 忽略 | 忽略 | 忽略 | **明确文档化**：`set%optset` 在 `src/landscape/` 里只出现在一处注释中（★实测 `grep` → 1 命中，是注释）。套件的对应旋钮是 `--lopt-level`/`--l*-level`；两者是**不同优化器**，忽略是设计选择 |
| `$md`、`$siman`、`$modef`、`$path`、`$reactor`、`$stm`、`$split` | MAIN/ANC（各自运行类型） | 忽略 | 忽略 | 忽略 | 忽略 | 忽略 | **明确文档化**（本表）：★实测 `grep 'set%md\|set%siman' src/landscape/` → 0；这些块属于**别的任务**，上游 `--sp` 对它们同样静默。不属于「同一任务的静默降级」类，因此不报错（否则会误伤 `--lopt` + `$write` 这类合法组合） |
| `$write`、`$cube`、`$fit`、`$derived`、`$ffnb`、`$oniom`、`$legacy set` | 输出/其它 | 按语义 | 按语义 | 按语义 | 按语义 | 按语义 | 不涉及 |

**判定规则（写下来便于复核）**：只有「同一用户意图在 `--opt` 下被满足、在套件下被静默丢弃」的块
才升级为**硬错误**（只有 `$scan` 属于这一类）。属于**另一个任务**的块保持静默
（上游行为一致），但本表逐条记录为「忽略 + 文档化」，不留未归类项。

### 4.4 测试与注入

**测试**：`test/unit/landscape_cli_check.py:check_scanblock`（新 mode `scanblock`）
+ CMake 测试 `xtb/landscape-scan-xcontrol` + meson 测试 `landscape scan xcontrol`。
断言：5 个运行类型都非零退出、消息含 `does not execute the xcontrol $scan block`、
**不写** `xtbscan.log`；并且 `--opt` 仍然执行 `$scan`（stdout 含 `RELAXED SCAN` 且写出 `xtbscan.log`）。

```
scan block: --lopt rejected the $scan block with status 1
scan block: --lscan rejected the $scan block with status 1
scan block: --lts rejected the $scan block with status 1
scan block: --lirc rejected the $scan block with status 1
scan block: --lvib rejected the $scan block with status 1
```

**注入（可证伪，★实测）**：把守卫条件改成 `if (.false.) then`（纯语义回滚到修前：不报错）。

| 测试 | 注入后 | 还原后 |
|---|---|---|
| `xtb/landscape-scan-xcontrol` | **RED**：`FAIL: xtb --lopt accepted the xcontrol $scan block` | GREEN |

---

## 5. 全套回归结果（★实测，全部 `OMP_NUM_THREADS=1`）

```bash
ctest --test-dir /tmp/xtb-o2/build -R landscape                                        # 100/100
ctest --test-dir /tmp/xtb-o3/build -R landscape                                        # 100/100
ctest --test-dir /tmp/xtb-o2/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'   # 12/12
ctest --test-dir /tmp/xtb-o3/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'   # 12/12
```

> 计数口径：本节标题下的 `ctest -N` 输出当时是 98（只有 3 个新条目已登记）；
> 补齐 `landscape-lts-fix`/`landscape-lirc-fix` 两条后为 **100**（95 + 5，
> 见 §5.4 的计入方式）；06 报告再新增 `landscape-vib-thermo-knobs` ⇒ **101**。
> 下表列出新增的 **5** 个 ctest 条目（第一行是**既有** ctest 条目内的新用例，不计入条目数）。

新增的 5 个测试（95 → 100；06 报告 §2.1 再 +1 ⇒ 101）：

| 测试名 | 文件 | 作用 |
|---|---|---|
| `xtb/landscape-optimize-math` 的 `fix-projection`（既有条目内的新用例） | `test/unit/test_landscape_optimize_math.f90` | 解析势上验证 `$fix` 投影（不含 SCF，0.01 s） |
| `xtb/landscape-fix-rfo` | `test/unit/CMakeLists.txt` + `test/unit/landscape_cli_check.py::check_fix` + `test/unit/meson.build` | 8 例（6 引擎 + 2 个 `--lopt-hessian model` 种子组合）的真实 GFN2 固定原子位移 |
| `xtb/landscape-scan-xcontrol` | 同上（`check_scanblock`） | `$scan` 被拒绝 + `--opt` 仍执行 |
| `xtb/landscape-vib-thermo` | 同上（`check_thermo`） | `$thermo` 优先级 + 与 `--hess` 一致 |
| `xtb/landscape-lts-fix` | 同上（`check_saddlefix`） | 三个鞍点方法的 `$fix` 位移（prfo 不收敛的契约见 06 报告 §2.5） |
| `xtb/landscape-lirc-fix` | 同上（`check_rejectfix`） | `--lirc`/band 路径拒绝 `$fix`（env%error） |

M7 的分层验收也重跑（包含在 100 里）：`xtb/landscape-e2e-layers`（17 checks）、
`landscape-e2e-chain`、`landscape-e2e-chain-failure`、`landscape-e2e-ljson-methods`、
`landscape-e2e-{ts,scan}-counters`、`xtb/landscape-e2e-maple` —— 全部 green。

---

## 6. 变更文件清单

新文件 1 个、修改 18 个；`git diff --stat` = 638 insertions(+), 21 deletions(-)。

| 文件 | 改了什么 |
|---|---|
| `cmake/CMakeLists.txt` | +28：`-O3` 检测 + `message(WARNING ...)`（§1.2 逐行理由） |
| `src/landscape/types/constraints.f90` | **新增 104 行**：`$fix` 掩码 + 投影 + 机制文档 |
| `src/landscape/CMakeLists.txt` / `meson.build` | +1/+1：登记新模块 |
| `src/landscape/optimize/driver.f90` | +39：可选 `frozen(:)` 实参 + 投影不变式 |
| `src/landscape/types/constraints.f90` | 第二轮 +48：`landscape_project_fixed_atoms`（自持 `fixset` 的入口点） |
| `src/landscape/saddle/prfo.f90` | +18：主步与 escape 的 `$fix` 投影 |
| `src/landscape/saddle/dimer.f90` | +7：平移步的 `$fix` 投影 |
| `src/landscape/tasks/ts.f90` | +18：band 方法的 `$fix` 拒绝 |
| `src/landscape/tasks/irc.f90` | +20：`--lirc` 的 `$fix` 拒绝 |
| `src/landscape/tasks/opt.f90` | +12：读 `$fix` 掩码、打印、传参 |
| `src/landscape/scan/relax_scan.f90`、`tasks/ts.f90`、`tasks/irc.f90` | 各 +4：传 `$fix` 掩码 |
| `src/landscape/types/settings.f90` | +14：4 个 `*_was_set` 标志 + 文档 |
| `src/landscape/vib/thermo.f90` | +34/−16：`$thermo` 优先级语义 |
| `src/prog/main.F90` | +39：4 个 `*_was_set` 赋值 + `$scan` 守卫 |
| `src/xhelp.f90` | +5：`--lopt` 的 `$scan` 说明、`--lvib` 的 `$thermo` 优先级说明 |
| `test/unit/CMakeLists.txt` | +54：3 个新测试 + python 包装 + `set_tests_properties` |
| `test/unit/landscape_cli_check.py` | +233：`fix` / `scanblock` / `thermo` 三个 mode |
| `test/unit/landscape_testpot.f90` | +94：`landscape_quadratic_fix_model` |
| `test/unit/test_landscape_optimize_math.f90` | +67：`fix-projection` 用例 |
| `test/unit/meson.build` | +21：三个新 meson 测试 |
| `AGENTS.md`（gitignored） | §4 官方构建命令改 `-O2`；§6 新增「-O2 轮实测事实」段 |
| `docs/xtb-landscape-PLAN.md` | 附录 A 新增优化档一行；两处构建命令加 `-DCMAKE_Fortran_FLAGS_RELEASE` |

**git 状态**：全部为工作区改动，**未 `git add`、未提交**（`git diff --cached` 为空）。

---

## 5. 修复的第二轮（父会话批准的范围扩展 (B)）：鞍点侧 + IRC 侧

> 本节是**增量**：§1..§4 的内容未改动。触发条件是 §7.1-6 的实测发现
> （`--lts`/`--lirc` 的核心步同样不尊重 `$fix`）。父会话的决定：鞍点一侧**做**，
> IRC 一侧**先分析、不确信就响亮报错**，边界是「宁可响亮失败，不可静默错误」。

### 5.1 单一事实来源（父会话要求 1）

三条路径的「哪些原子被固定」都来自**同一处**：

```
src/fixparam.f90:33   type(fix_setvar) :: fixset        <-- xtb 的参数状态，唯一来源
src/fixparam.f90:124  integer :: n = 0 / integer, allocatable :: atoms(:)
```

* `src/xtb/calculator.f90:304-306` 用它把梯度置零（上游行为，未改一行）；
* `src/landscape/types/constraints.f90` 的 `landscape_frozen_mask(nat)` 把它变成
  `logical(3N)` 掩码，供 `optimize/driver.f90`（显式实参）与
  `saddle/*`（`landscape_project_fixed_atoms(step)`，内部读同一 `fixset`）使用。
* 鞍点/IRC 里**没有**任何第二份「固定原子判定」。

新增的第二个入口点（`landscape_project_fixed_atoms`）是为了避免把
`frozen` 实参穿过 12 个签名（4 个 IRC 方法 + 5 个 band 方法 + prfo + dimer + escape）；
它只是 `landscape_frozen_mask(size(step)/3)` + `landscape_project_frozen` 的三行包装，
算法只有一个（§5.1 的模块注释写明了这一点）。

### 5.2 鞍点侧（prfo / bprfo / dimer）：做，已修

**投影位置 = 步向量**（不是 Hessian），理由是**与刚体投影的既有处理对齐 + 避免伪造零本征值**：

| 对象 | 是否投影 | 理由 |
|---|---|---|
| 接受的步向量 `step` | **是** | `x_trial = x + step` 是唯一改变几何的地方；投影后固定原子**逐位不变**（可断言） |
| escape walk 的位移 `dvec` | **是** | 它也是几何位移（`x_esc = x + dvec`）；若被跟随的模式整体落在固定坐标上，`|dvec|` 变 0 ⇒ 走 escape 的既有分支停走并告警（不静默） |
| Hessian `hmat` | **否** | 刚体方向是 Hessian 的**数值零方向**，所以必须从**谱**里去掉（`landscape_project_hessian_rigid`）。`$fix` 方向**不是**零方向：把它的行/列清零会凭空造出 `3·N_fix` 个零本征值，被 `hlow` 抬起后进入模态选择/跟随，反而污染 `lambda_p/lambda_n` 与 trust radius 的判据。B-PRFO 走的是同一个 `step`，无需单独改（`saddle/bprfo.f90` 只提供步） |
| 探针几何（dimer 的旋转、数值 Hessian 的差分位移） | **否** | 它们不是「结果几何」。规则明确写为：**被接受的几何（轨迹/最终几何）不得移动固定原子**；内部求值几何可以（数值 Hessian 本来就要位移所有原子）。这条规则同时解释了为什么不对 `hessian` provider 做任何改动 |

**调用点（3 处）**：`saddle/prfo.f90:591`（主步，紧跟 `landscape_project_rigid`）、
`saddle/prfo.f90:786`（escape）、`saddle/dimer.f90:833`（平移步，紧跟刚体投影、在零范数判据之前）。
`--lts --lts-method neb|cineb|autoneb|string|gsm` 与 `--lirc` **拒绝**（见 §5.3）。

**逐引擎固定原子位移表（★实测）**
夹具 = `landscape_hcn.xyz`（弯曲 HCN TS 猜测，原子 1 = H，初始 `(0, 1.05, 0)` Å），
`$fix atoms: 1`，`--lts-max-steps 120`。断言量是**最大分量位移**（`xtb/landscape-lts-fix` 的判据），
`|Δ|` 是欧氏距离。

| 方法 | 修前 max\|Δx\| (Å) | 修前 \|Δ\| (Å) | 修前收敛 | 修后 max\|Δx\| (Å) | 修后收敛 |
|---|---|---|---|---|---|
| prfo | 1.14051e-01 | 1.20574e-01 | 否（步数用尽，exit 1） | **0.00000e+00** | 否（步数用尽，exit 1；**修前也否**） |
| bprfo | 1.45892e-01 | 1.46715e-01 | **是** | **0.00000e+00** | **是**（57 步） |
| dimer | 1.46394e-01 | 1.47202e-01 | **是** | **0.00000e+00** | **是**（21 步） |

修前 `xtbts.xyz` 原文（供复核）：

```
prfo  H    0.11405123731836  1.01087958252317  -0.00000000000000
bprfo H    0.14589166826049  1.03447606077976   0.00000000000000
dimer H    0.14639445212370  1.03459847905975   0.00000000000000
```

修后三者都逐位等于输入 `H  0.00000000000000  1.05000000000000  0.00000000000000`。

**关于 `prfo` 不收敛（父会话要求 4，不伪造收敛）**：约束后的 P-RFO 在这个夹具上**用尽步数**
（120 步与 400 步都一样，`maximum number of steps reached`，exit 1）。
**修前它也（在漂移的几何上）不收敛**（同样 `maximum number of steps reached`），
所以这不是投影引入的退化，而是 P-RFO 在该夹具上的 trust-radius 行为
（与 M4 已知项「uphill 时 rho 规则过于保守」同源，`31-m4-review-round2.md` 的处置是保留）。
因此测试断言的是**诚实的契约**：非零退出 + 消息指名步数预算 + 固定原子位移为 0；
**没有**为了让它通过而放宽收敛判据、加步数或换夹具。
`bprfo`/`dimer` 提供了**收敛的** `$fix` 夹具（化学上合理：固定末端 H，研究 C–N 方向的约束驻点），
所以 `$fix` 的鞍点用例不是「只有失败路径」。

**测试与注入（★实测）**

| 测试 | 内容 |
|---|---|
| `xtb/landscape-lts-fix`（CMake + meson，python mode `saddlefix`） | prfo/bprfo/dimer × `$fix`：位移 ≤1e-10 Å + 收敛契约（bprfo/dimer 必须收敛；prfo 必须非零退出且理由正确） |
| 注入 `s1`+`s3`（删掉 prfo 的两处投影调用） | **RED**：`FAIL: --lts-method prfo moved the frozen atom by 1.14051e-01 angstrom` |
| 注入 `s2`（只删 dimer 的投影调用） | **RED**：`FAIL: --lts-method dimer moved the frozen atom by 1.46394e-01 angstrom`（prfo/bprfo 仍绿 ⇒ 注入可**逐方法**隔离） |
| 三处还原 | **GREEN** |

```
saddle fix: prfo  status 1 converged False  frozen atom displacement 0.00000e+00 angstrom
saddle fix: bprfo status 0 converged True   frozen atom displacement 0.00000e+00 angstrom
saddle fix: dimer status 0 converged True   frozen atom displacement 0.00000e+00 angstrom
```

### 5.3 IRC 侧（gs / lqa / hpc / eulerpc）：**分析后决定不做，改为响亮报错**

父会话要求「先分析并写清，不确信就报错」。分析结论如下（三条，逐条给依据）。

**(1) 质量加权投影本身是良定义的（这一条**不**是障碍）。**
IRC 在质量加权坐标里推进（`q_i = sqrt(m_i) x_i`，`irc/corrector.f90:245-255`）。
`$fix` 冻结的是 **Cartesian** 分量；因为 `dq_i = sqrt(m_i) dx_i` 且 `sqrt(m_i) > 0`，
「把 `Δq` 的固定分量置零」**等价于**「把 `Δx` 的固定分量置零」——投影算子在两种度量下是**同一个**
（对角、同零模式）。所以「投影破坏质量加权」不成立，这一步可以照搬鞍点侧。

**(2) 真正的障碍是 `s` 的契约。**
M6 的契约是「`s` 列是**质量加权弧长**」（PLAN §6.5 弧长定义行；`s` 在 gs/hpc/eulerpc 是弦长累加、
在 lqa 是积分弧长）。现在四个方法都把 `s` 从**请求的**步长累加：

```
irc/hpc.f90:281      s_cur = s_cur + ds
irc/eulerpc.f90:265  s_cur = s_cur + ds
irc/lqa.f90:201      s_cur = s_cur + shift
irc/gs.f90:244       s_cur = s_cur + ds
irc/*.f90:186/158/133/191   q_cur = q_ts + sign*0.5_wp*step*v  ;  s_cur = 0.5_wp*step
```

投影会**缩短实际走出的位移**，于是「请求的步长」与「实际弧长」不再相等，必须二选一：
(A) `s` 继续记「请求值」⇒ 语句「s 是弧长」变成假命题（静默的数据错误）；
(B) `s` 改为累加**允许子空间内的实际弧长** `|Δq_projected|` ⇒ 自洽，但同一条路径在
有/无 `$fix` 下的 `s` 不同口径，**是契约变更**，需要先拍板并写进 PLAN。
我倾向于 (B)（它是唯一自洽的），但也不允许沉默地选一个。

**(3) LQA 的正确器在投影下不动点不确定（这一条决定了「不确信」）。**
`landscape_irc_lqa_step` 用 **Newton 迭代把预测点打到请求弧长 `s_target`**
（`irc/corrector.f90:399-493`，`Sigma_n` 步）。投影后的步**无法**达到 `s_target`
（可达集是 `s_target` 的一个子集），所以「迭代收敛到的点」不再是「投影后的修正点」——
它的极限集合依赖于迭代路径，不是良定义的修正方程的解。这是「不确信正确」的判据；
HPC/EulerPC 的 DWI+mBS 校正同理（mBS 的接受阈值是对**请求的**弧长定义的）。
另外 GS 的球面弛豫还有 §6.5 未关闭的 Lagrange open item，叠加 `$fix` 会让行为基线的区分成本翻倍。

**决定（父会话语：报错也是合格交付）**：`--lirc` + `$fix` ⇒ **显式错误、非零退出**。
（`--lts` 的 5 个 band 方法同理，理由见 (2) 的姊妹问题：band 图像由**端点插值 / IDPP / 重分布**
构造（`path/idpp.f90`、`path/string.f90`、`path/gsm.f90`），两端点对「固定坐标」不一致时
「图像 1 的原子 i 该在哪」无定义。）

**错误信息原文（★实测，`xtb/landscape-lirc-fix` 断言其存在）**：

```
[ERROR] Program stopped due to fatal error
-2- Landscape task terminated
-1- landscape_irc: the reaction path (--lirc) does not support $fix: its path advance is
    defined in the mass weighted arc length, which a fixed coordinate would have to
    redefine.  Use --lopt or --lts (their searches project the step), or remove the
    $fix block
```

以及 band 侧：

```
-1- landscape_ts: the band searches (--lts-method neb|cineb|autoneb|string|gsm) do not
    support $fix: their interior images are interpolated between the two endpoints.
    Use --lts-method prfo, bprfo or dimer, or remove the $fix block
```

**触发条件**：`--lirc`（任意方法）或 `--lts`（band 方法）且 `any(landscape_frozen_mask(mol%n))`
（即 `$fix` 至少列了一个原子）。`--lopt`/`--lscan`/prfo/bprfo/dimer/端点松弛**不受影响**。
两条 guard 在引擎创建**之前**（`tasks/ts.f90` 的 band 分支之前、`tasks/irc.f90` 的入口），
因此不浪费 SCF，且 `--lts-method neb` 在缺 product 时也先报 `$fix` 这条更根本的问题。

**测试与注入（★实测）**

| 测试 | 内容 |
|---|---|
| `xtb/landscape-lirc-fix`（CMake + meson，python mode `rejectfix`） | `--lirc` 与 `--lts-method neb` + `$fix`：非零退出 + 消息 + **不写** `xtbts.xyz`/`irc_forward.xyz`/`irc_path.xyz` |
| 注入 `r1`+`r2`（把两条 guard 的条件改成 `.false.`） | **RED**：`FAIL: --lirc accepted $fix although the method does not support it` |
| 还原 | **GREEN** |

```
reject fix: --lirc    rejected $fix with status 1
reject fix: --lts neb rejected $fix with status 1
```

**测试实现里的一个真实缺陷（自查发现并已修）**：两个新检查最初只在 rundir 里 `makedirs`，
而它们断言的是**产物不存在**。注入实验把 guard 关掉后，`--lirc` 会**真的写出** `irc_forward.xyz`，
这些残留文件让「还原后」的检查仍然失败（假红）。修法是在检查开头
`shutil.rmtree(rundir)`——这正是 M7 finding F1 记录的同一个陷阱
（`docs/_landscape-recon/50-m7-independent-review.md`），在本轮的新检查里**又犯了一次**，
已在代码注释里点名 F1。

### 5.4 「无 `$fix` 时行为不变」的证据（父会话要求 3）

**证据 1（结构性，★实测）**：HEAD 上 `test/` 里**没有任何** `$fix` 出现：

```bash
$ git grep -c '$fix' HEAD -- test/      # 0 个文件命中
$ git grep -l '$fix' HEAD               # 只有 man/xcontrol.7.adoc 与 src/constrain_param.f90
```

⇒ 所有新增行为都由 `fixset%n > 0` / `any(frozen)` 门控，**不可能**影响任何既有测试。

**证据 2（实测，三条都不得变化）**：

| 项 | 结果 |
|---|---|
| `ctest -R landscape`（`-O2`） | **100/100 passed**（31.44 s；修复前基线 95 ⇒ 本轮新增 5 个 ctest 条目，见下注） |
| `ctest -R landscape`（`-O3`，同源码） | **100/100 passed**（29.81 s） |
| 回归子集（`-O2` / `-O3`） | **12/12 / 12/12 passed** |
| M7 四体系验收（§1.4） | **逐项不变**（H2O 0.0100 / CH3OH 0.0600 / CO2 0.0000 / C2H2 0.0000；dZPE/dH/dG 与 §1.4 表逐位相同） |

> 计入方式（95 → 100）：新增的 ctest 条目是 5 个（`landscape-fix-rfo`、`landscape-scan-xcontrol`、
> `landscape-vib-thermo`、`landscape-lts-fix`、`landscape-lirc-fix`）；`fix-projection` 是**既有**套件
> `xtb/landscape-optimize-math` 内的**第 15 个用例**，
> 不新增 ctest 条目 ⇒ 95 + 5 = **100**。
> 测试名唯一性复核：`grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d` → 空。

**证据 3（逐位，★实测）**：`--lts-method prfo|bprfo|dimer` **不带 `$fix`** 时，
`-O2` 本轮构建与 `-O3` 修复前构建的 `final energy` 逐位相同
（`-5.387373532156` / `-5.387373532550` / `-5.387373500230`）。

### 5.5 「所有二阶步」这个说法的边界（父会话要求 4：证伪任务书前提）

任务书写「**所有**二阶步都必须尊重 `$fix`」。按本轮实测，这句话需要**拆分**才成立：

| 二阶步 | 尊重 `$fix`？ | 依据 |
|---|---|---|
| `--lopt-engine rfo` | ✅ 已修 | §2 |
| `--lts` 端点松弛 / `--lirc` 端点松弛的 RFO | ✅ 已修（走同一个 driver） | §2.2 |
| `--lts` prfo / bprfo / dimer | ✅ 本轮已修 | §5.2 |
| `--lts` band（neb/cineb/autoneb/string/gsm） | ⛔ **拒绝运行**（不是「尊重」，是「不假装支持」） | §5.3 |
| `--lirc` 四方法 | ⛔ **拒绝运行** | §5.3 |
| `--lscan --lscan-mode rigid` | ⚠️ **未覆盖、未实验**（纯几何构造，不是步） | §7.1 |

⇒ 证伪的**不是**「二阶步有风险」这个判断（它成立），而是「本轮能把**所有**二阶步都修好」这个隐含前提：
其中 IRC/band 一侧存在**契约级**的阻塞（弧长语义、LQA 不动点、图像插值），
只能以「响亮拒绝」落地。**没有静默错误留下**是本轮的实际交付标准。

## 7. 未验证 / 未完成 / 与任务书或父会话前提不一致之处

### 7.1 明确「未验证」

1. **`-O3` 异常的机制**：未定位（已排除 `-fno-tree-vectorize`，与调查 C 一致）。
   本报告**不**声称掌握根因，也**不**把它登记为「已知编译器缺陷」（证据不足以报 GCC）。
2. **`WITH_TBLITE=ON` / `WITH_CPCMX=ON` 下的行为**：未测（沿用 AGENTS §4 的 `OFF`）。
3. **`meson` 侧的新测试**：meson 未安装 ⇒ 六条新 meson 测试「已写、**未执行**」
   （与项目其余 meson 登记一致）。CMake 侧六条均已实跑。
4. **`$wall` / `$metadyn` 的运行级实验**：未做（表中按 `file:line` 静态证据标为「消费」）。
5. **`-O3` 在**本 HEAD**的其它输入上是否有问题**：只探了 H2O `--hess` 一个点；
   整套 landscape 测试在 `-O3` 下 98/98 绿（当轮的测试数；现为 101），但那是「当前证据」，不是证明。
6. **`--lts` / `--lirc` **核心算法**（PRFO/B-PRFO/dimer/IRC corrector）对 `$fix`：★实测违反；鞍点一侧已在第二轮修好，IRC/band 一侧改为响亮报错（见 §5）。**
   （下面这段是**第一轮**结束时的记录，保留以便对照；第二轮的结论与数字在 §5。）
   它们与 RFO 同属二阶步，但走**自己的**迭代循环，并且**只**做质权坐标下的刚体投影
   （`src/landscape/saddle/prfo.f90:585` `landscape_project_rigid`，`irc/*.f90`），
   本项目**没有**任何地方把 `$fix` 掩码接进去。实测（`landscape_hcn.xyz` = 弯曲 HCN TS 猜测，
   `$fix atoms: 1` 固定 H，初始 `(0, 1.05, 0)` Å）：

   | 命令 | 结果 | 固定 H 的位移 |
   |---|---|---|
   | `--lts --lts-method prfo --lts-max-steps 40` | 未收敛（exit 1），`xtbts.xyz` = `(0.11028, 1.01009, 0)` | **0.11728 Å** |
   | `--lirc --lirc-method hpc --lirc-max-steps 8` | exit 0，`irc_forward.xyz` 共 9 帧 | 末帧 **0.023690 Å**，路径最大 **0.023718 Å** |

   ⇒ **同一缺陷类的确认实例**（不是推断）。**不在本轮范围**（任务书点名 `--lopt-engine rfo`；
   `--lts`/`--lirc` 的**端点松弛**已修，因为它们走 `landscape_optimize_model`）。
   修法与 §2 相同（把 `landscape_frozen_mask` 接进 `saddle/prfo.f90` 的步投影点与
   `irc/corrector.f90` 的步），但会改动 M4/M6 已验收的数值路径，**属于新工作**，需先拍板。
7. **`--lscan` 的 `rigid` 模式**：纯几何构造（按坐标值搬原子），固定原子若落在被扫描坐标里仍会被移动；
   未做实验，未修。

### 7.2 与任务书 / 父会话前提的不一致（如实记录）

1. **「`-O3` 异常」在本 HEAD 未复现** —— 与调查 C 一致，与「我们官方构建一直是 Release(= -O3)
   而不安全」的推论不同：不安全的是**档位本身不可依赖**，不是「当前二进制是错的」。
2. **缺陷① 的怀疑机制被确认**（不是推翻）：梯度为零不蕴含步长为零，RFO 的本征矢把固定分量
   混进步长。父会话说「需你确认或推翻」——**确认**。
3. **缺陷① 的修法**：任务书建议「至少 rfo，并检查 diis/bfgs」。实测 + 逐行证明：
   diis/bfgs（以及 sd/cg/lbfgs）**不需要**修（位移本来就精确为 0），
   修复点是 **RFO**，而实现上落成一个对所有算法统一的投影不变式。
4. **缺陷② 的容差**：任务书说「把 `--hess` 当参照」。在**非极小**几何上，两条路径的
   dG 天然有 ~2e-5 Eh（投影约定随 ‖g‖ 放大），**不是**热化学设置问题；
   因此测试把比较放在 **tight 极小** 上（那里残差 1.4e-8，M7 已校准）。这一点容易误读，故写明。
5. **缺陷③ 的范围**：任务书列的「不执行 `$scan` 的套件任务」中不含 `--lscan`。
   本报告**把 `--lscan` 也纳入硬错误**：它虽然「是扫描」，但**用的是自己的
   `--lscan-coord` 网格**，xcontrol `$scan` 块同样被静默丢弃 ⇒ 同一缺陷类。
   若父会话认为 `--lscan` + `$scan` 应允许（例如容忍 `$scan` 作为惰性文档），
   这是一处需要拍板的范围判断（默认行为：报错）。
6. **`$scan` 之外的块**：见 §4.3 表。除了 `$scan`，**没有**发现「同一用户意图被静默降级」的第二个块；
   `$hess`/`$opt`/`$md`/… 属于「别的任务」或「上游本来也无效」，按任务书「报错**或**明确文档化」的后半条处理。

### 7.3 建议的后续动作

1. **IRC/band 的 `$fix`（已分析，已登记为 PLAN §6.9 待办）**：
   先把 `s` 的语义二选一写进 M6 契约（自洽的解是「`s` = 允许子空间内的实际弧长」），
   再处理 LQA `Sigma_n` 在投影下不动点不确定的问题（要么改判据、要么接受其迭代只在
   全空间有定义），最后把每个**接受点**的质量加权位移投影并逐方法重跑 M6 验收。
   本轮按父会话语以「响亮报错」落地。
2. 把 `-O3` 异常的最小复现（edcfbbe + `-O3`）整理成可提给 GCC Bugzilla 的工单，
   需要先缩小到单个文件/单个 kernel。
3. `--lscan --lscan-mode rigid` 的 `$fix`（纯几何构造，未实验）与 `prfo` 在约束夹具上的
   收敛性（本轮记录为不收敛，未调参）——两项都登记，不在本轮伪造通过。
