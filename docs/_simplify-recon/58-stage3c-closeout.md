# 58 — 阶段 3c 收口轮（MEDIUM 2 + 父会话发现 1 + 登记）

> 范围 = 复核 MEDIUM-1/MEDIUM-2 + 父会话实测的 `--ohess <LEVEL>` 两半不一致 + 三条已接受偏离的登记。
> **不改四轴数值、不重做 3c、不碰核心层、不为变绿放宽断言。** 构建目录 `/tmp/xtb-3cf/build`（新建，`-O2 -DNDEBUG`，
> `WITH_CPCMX=OFF`，configure exit 0）。基线 `HEAD = 8b85c6d`，工作树 = 未提交的阶段 3c。所有 xtb/ctest 调用 `OMP_NUM_THREADS=1`。

## 0. 摘要

| 项 | 结论 | 证据 |
|---|---|---|
| T1 `acc_was_set` 宿主变量 | **已删**，改为 `parseArguments` 的尾随 `intent(out)` 哑元（与 `landscape_native_engine` 同构） | `main.F90:264` 局部 + `:1750` 哑元；无宿主声明 |
| T1 附加核对 | 全仓库**无**其它模块级/宿主级可变状态（landscape 树 + `main.F90` + `xhelp.f90` 全扫） | §1.4 |
| T2 `xhelp.f90` 四处 `(default 256)` | **已改**为档位派生表述（4 处），与 `settings.f90` 的默认值/公式逐字对齐 | §2，`--help` 实测渲染 |
| T3 `--ohess <LEVEL>` 两半不一致 | **已修**：桥接处对 `p_run_ohess` 同时给 `lvset` 上档位 | 改前 `0.2`/`1.0` → 改后 `0.2`/`0.2`；新测试红→绿 |
| T3 新测试 | `xtb/landscape-ohess-level-axes`（3 次 `--ohess` 运行，断言两半的 acc 与 e_tol） | §3.3 |
| T3 `--lvib` 核对 | `--lvib` **没有** `--lvib-level` 旗标（全仓库 0 命中）⇒ 无同类不一致，**不改**其语义 | §3.4 |
| T4 三条再基线偏离 | 已登记：设计 §3.10 新增「三条未重跑的偏离——父会话裁定接受」表 + 本报告 §4 | §4 |
| 测试计数 | landscape **147/147**（3c 的 146 + 新增 1）；回归子集 **12/12**；`--help` 一致性 PASS；`add_test` 无重名 | §5 |
| 被证伪的前提 | 复核 INFO-1 的「保持现状」建议被父会话实测推翻；另有 1 条订正 + 1 条复现陷阱 | §6 |

## 1. T1 — `acc_was_set` 改为参数传递（复核 MEDIUM-1）

### 1.1 缺陷

`src/prog/main.F90`（改前 `:138`）

```fortran
   !> `--acc` was named on the command line. ...
   logical :: acc_was_set = .false.      ! 位于 module xtb_prog_main 的 `contains` 之前
```

即 **`program` 单元（宿主）级可变状态**，写点 2 处（`:1823` 开场复位、`:1943` `case ('-a','--acc')`），
读点 6 处（`:1104` lopt / `:1137` ohess-vib / `:1185` lscan / `:1207` lts / `:1237` lirc / `:1253` lvib）。
违反 `AGENTS.md` §5「No module-level mutable variables」与设计 §3.11。

### 1.2 改法（`src/prog/main.F90`，与 `landscape_native_engine` 完全同构）

| 位置 | 改动 |
|---|---|
| 模块级 | 删除 `logical :: acc_was_set = .false.`，连同其宿主变量注释移入 `xtbMain` 的局部声明（`:264`，带 `!>` 文档注释说明职责与「不是宿主变量」的理由） |
| `parseArguments` 形参表（`:1671-1672`） | 追加尾随哑元 `acc_was_set` |
| `parseArguments` 哑元区（`:1750`） | `logical, intent(out) :: acc_was_set` + `!>` 文档注释 |
| `xtbMain` 调用点（`:277-279`） | 追加实参 `acc_was_set` |
| `:1840` | `acc_was_set = .false.` **保留**（`intent(out)` 哑元在入口同样未定义，且 flag 循环有 6 个 `return` 路径先于 `--acc`）；注释扩写为「哑元定义」而非「局部复位」 |
| `:1960` | `acc_was_set = .true.` 不变（写点语义未动） |
| 6 个读点 | 不动（仍是 `if (acc_was_set) ...`） |

### 1.3 验收

```
$ grep -n "acc_was_set" src/prog/main.F90
264:      logical :: acc_was_set
279:         & lsset, lvset, ltset, lircset, landscape_native_engine, acc_was_set)
1106/1139/1187/1209/1239/1255:  if (acc_was_set) ... = set%acc        ← 6 个读点
1672/1750: parseArguments 的哑元
1840/1960: 哑元清零 / 置位
```

**宿主变量声明已消失**（模块作用域 `1..129` 行现在只剩 `implicit none` / `private` / `public :: xtbMain` / `contains`）。
语义验收（`/tmp/xtb-3cf/build/xtb`，水）：

```
--lopt --lopt-level loose              → landscape engine: SCC accuracy 2.000000   ✅ 档位仍生效
--lopt --lopt-level loose --acc 1.0    → 1.000000                                  ✅ 显式优先
--lopt --acc 0.5                       → 0.500000                                  ✅ 显式单独生效
--lopt（默认）                          → 1.000000 / e_tol 5.000000E-06             ✅ 默认不变
```
`ctest -R landscape-level-axes` 全绿（该测试正是 3c 为这三条优先级写的）。

### 1.4 附加核对：还有别的模块级/宿主级可变状态吗？

- `src/prog/main.F90`：`grep -nE "^ *logical ::|^ *integer ::|^ *real|^ *character.*::"` → 命中全是 `xtbMain`/`parseArguments`
  **内部**声明（6 空格缩进 = 子程序局部），模块作用域内 `::` 只剩 `public :: xtbMain`。
- `src/landscape/**/*.f90` + `src/xhelp.f90`：脚本逐文件取「第一个顶格 `contains` 之前、且不在 `type ... end type`
  内、且非 `parameter`」的声明 → **仅** `xhelp.f90:19/103` 两个子程序哑元（`integer, intent(in) :: iunit`），
  **不是** 模块状态。`grep ", save\|: *save" src/landscape/` 只命中 `tasks/ts.f90:1444` 的局部 `saved(:, :)`（名字巧合）。
- 结论：**无其它模块级/宿主级可变状态**，本条无需再登记缺陷。

## 2. T2 — `xhelp.f90` 四处陈旧默认值（复核 MEDIUM-2）

3c 后默认步预算 = `clamp(n_atoms × multiplier, 200, 10000)`，`multiplier = 3`（默认档 `normal`）：

- `src/landscape/types/settings.f90:392` `integer :: max_steps_multiplier = 3`（`set_conv_level` 的 `normal` 分支 `:1183` 同值）；
- `src/landscape/types/settings.f90:1225` `self%max_steps = min(max(natoms*self%max_steps_multiplier, 200), 10000)`。

（`:384` 的库默认 `integer :: max_steps = 256` **未变**，是库调用者的默认，不是 CLI 默认——见复核 INFO-2，
本轮不改，仅在此记录。）四处 help 文本改前/改后：

| 行 | 改前 | 改后 |
|---|---|---|
| `:319` `--lopt-max-steps N` | `step budget of the minimisation (default 256)` | `step budget of the minimisation; the default is derived from the convergence level (3 steps per atom at level normal, clamped to 200..10000), --cycles and the level change it` |
| `:396` `--lscan-max-steps N` | `... every scan point (default 256)` | 同句式（主语换成 scan point） |
| `:440` `--lts-max-steps N` | `maximum number of macro iterations (default 256)` | 同句式（主语换成 macro iterations） |
| `:626` `--lirc-max-steps N` | `maximum number of macro steps of one direction (default 256)` | 同句式（主语换成 macro steps of one direction） |

**验收**：`xtb --help` 渲染四段均无误（实测贴出，见 §5 命令 4）；`xtb/landscape-help-coverage`（集合 S 差集为 0）PASS。
数值与代码一致（3 per atom / 200..10000 / 默认档 normal），**从 `settings.f90` 读出而非凭记忆**。

## 3. T3 — `--ohess <LEVEL>` 的 vib 半拿不到档位派生设置（父会话实测）

### 3.1 改前实测（`/tmp/xtb-3c-val/build/xtb`，同一次运行内）

```
$ xtb landscape_h2o.xyz --gfn 2 --ohess tight --norestart
 maximum number of steps:  200
 energy tolerance:            1.000000E-06 Eh        ← opt 半
 landscape engine: SCC accuracy              0.200000 ← opt 半
 Hessian SCC accuracy:        3.000000E-01
 energy tolerance:            5.000000E-06 Eh        ← vib 半（默认档！）
 landscape engine: SCC accuracy              1.000000 ← vib 半 ❌
```
根因：`parseArguments` 的 `--opt/--ohess` 桥只 `call lset%set_conv_level(...)`（3c 代码 `main.F90:4518`），
`lvset` 未被触碰；vib 半只保留自己的默认（`engine%acc = 1.0`、`e_tol = 5e-6`）。

### 3.2 改法（1 处，4 行 + 注释）

`src/prog/main.F90:4551-4553`（桥接处 `else` 分支内，`lset` 之后）：

```fortran
               if (set%runtyp == p_run_ohess) then
                  call lvset%set_conv_level(landscape_opt_conv_level)
               end if
```

优先级规则未动：显式 `--acc` 仍对两半都优先（`xtbMain:1139` 的 `if (acc_was_set)` 排在 vib 半分派内）。
同一桥的 `landscape_native_engine == 0` 守卫仍在 ⇒ `--ohess --method ancopt` 不进桥，两半都不改。

**有意不做**：`lvset%level_step_budget(mol%n)`。频率任务没有收敛循环、没有步预算（`--cycles` 对它**报错**，
设计 §3.10b），给 `lvset%max_steps` 派生一个没人读的值只会制造「vib 有预算」的错觉。
档位对 vib 半可观测的轴就是 `engine%acc` 与 `e_tol`（两者都进 stdout banner），两个都同源了。

### 3.3 测试与注入（`test/unit/landscape_cli_check.py::check_ohess_level_axes`）

新 CLI 测试 **`xtb/landscape-ohess-level-axes`**（mode `ohesslevelaxes`），3 次 `--ohess` 运行：

| 运行 | 断言（`re.findall`，出现次数 = 2，即两半各一次） |
|---|---|
| `--ohess tight` | `SCC accuracy` == `['0.200000','0.200000']` **且** `energy tolerance:` == `['1.000000E-06','1.000000E-06']` |
| `--ohess tight --acc 0.5` | `['0.500000','0.500000']`（显式 `--acc` 对两半都赢过档位） |
| `--ohess`（默认） | `['1.000000','1.000000']` 且 `['5.000000E-06','5.000000E-06']`（防「无条件覆盖 vib 默认」的假修） |

**注入（改前红 / 改后绿）** —— 用改前的**同一源码状态的二进制**作为「去掉 vib 半档位应用」的等价突变
（比重新手改更忠实：它就是 3c 的真实前身）：

```
$ python3 landscape_cli_check.py ohesslevelaxes /tmp/xtb-3c-val/build/xtb  ...   # 改前
FAIL: --ohess tight reported the SCC accuracies ['0.200000', '1.000000'] instead of two times 0.200000: the level does not reach both stages
exit=1
$ python3 landscape_cli_check.py ohesslevelaxes /tmp/xtb-3cf/build/xtb  ...      # 改后
ohess level: both stages of the chain report the same SCC accuracy and energy tolerance (level and explicit --acc)
exit=0
```

注册：`test/unit/CMakeLists.txt`（`add_test` + `set_tests_properties` 的 `XTBPATH`/`OMP_NUM_THREADS=1` 列表）、
`test/unit/meson.build`（`landscape ohess level axes`）。`ctest -N -R landscape` = **147**（3c 的 146 + 1），
`grep -oE 'add_test\("[^"]+"' … | sort | uniq -d` **为空**（重名静默丢弃陷阱）。

### 3.4 `--lvib` 核对（父会话要求）

`grep -n "lvib-level\|lvib_level" src/prog/main.F90 src/xhelp.f90 src/landscape/types/settings.f90` → **0 命中**。
`--lvib` 没有档位旗标（只有 `--lopt-level`/`--lscan-level`/`--lts-level`/`--lirc-level`），
其档位就是库默认（`normal`：`acc = 1.0`、`e_tol = 5e-6`），`engine%acc` 只由显式 `--acc` 决定。
⇒ **不存在同类不一致**，本轮**不改**它的语义（登记于此）。

## 4. T4 — 三条已接受的再基线偏离（登记；父会话裁定）

已写入 **设计 §3.10**（「再基线清单」表之后新增一段「三条未重跑的偏离——父会话裁定接受」表，
每行含裁定、理由、证据等级）：

| 里程碑 | 项 | 裁定与理由 | 证据等级（报告用词约束） |
|---|---|---|---|
| M2 | 滞回 77 文件（`m2-hysteresis-data/`）未重跑 | **接受**：那批数据是在**旧档位语义**下测的；重跑得到的是**另一个实验**而不是刷新的 golden，它作为「3c 之前的档位语义」的历史记录保留是正确的 | 历史记录，**不作为**当前 golden 引用 |
| M4 | dimer-vs-prfo `7.7397e-05` 未重测 | **接受**：该打印点在当前 HEAD 已不存在（非本轮删除）；模型势 + 显式预算 ⇒ 与档位无关（静态论证）；M4 其余数字实测未动 | **未实测，静态判定**（不得写成「已实测未动」） |
| M3 | CH3OH `dfreq 0.0600 cm⁻¹` 未重跑 | **接受**：人工实验、不在 ctest 内；同一链的 H2O `dfreq 0.0100` 已由注册测试 `xtb/landscape-e2e-chain` 覆盖并实测未动 | 同链的 H2O 有注册测试覆盖 |

## 5. 测试计数与命令（全部 `OMP_NUM_THREADS=1`，`timeout` 包裹）

| # | 命令 | 结果 |
|---|---|---|
| 1 | `cmake --build /tmp/xtb-3cf/build -j 8` | **clean**（无 warning/error；`xtb` + `xtb-tester` 均链出） |
| 2 | `ctest --test-dir /tmp/xtb-3cf/build -R landscape` | **147/147 passed**（45.8 s） |
| 3 | `ctest -R 'Singlepoint\|GFN\|model-hessian\|optimizer\|Argparser\|CAPI'` | **12/12 passed**（0.27 s） |
| 4 | `xtb --help \| grep -A3 -E "^--l(opt\|scan\|ts\|irc)-max-steps"` | 四处新文本全部正确渲染（见 §2） |
| 5 | `ctest -R landscape-help-coverage` | PASS（集合 S 差集 0） |
| 6 | `ctest -N -R landscape` + 重名检查 | 147；重名列表**空** |
| 7 | 注入对比（§3.3） | 改前 exit 1（`['0.200000','1.000000']`）/ 改后 exit 0 |
| 8 | `grep -rln "use xtb_landscape" src/ \| grep -v main.F90 \| grep -v landscape/` | **空**（核心层仍是 0） |

**改动的文件**：`src/prog/main.F90`（T1+T3）、`src/xhelp.f90`（T2）、
`test/unit/landscape_cli_check.py`（新检查 + mode + docstring）、`test/unit/CMakeLists.txt`（注册 + 环境列表）、
`test/unit/meson.build`（注册）、`docs/_simplify-recon/11-cli-redesign.md`（§3.5 状态订正、§3.10 登记、§9.2 测试行）。
`src/landscape/**` 的 6 个文件与 `test/unit/test_landscape_settings.f90` 是**未提交的 3c 改动**，本轮**未触碰**。
**未 `git add` / 未提交**；会话脚本 `stage3c-workflow.js`、`stage3cclose-workflow.js` 留在工作树未入库。

## 6. 被证伪的前提 / 复现陷阱

1. **复核 INFO-1 的「保持现状、不要为对称而改数值」建议被实测推翻**（父会话的证据）。复核的论据是
   「上游原生路径的两半精度本来就不同（`hessian.F90:174` 用 `set%accu_hess`）」+「套件 FD Hessian 读的是
   `engine%hess_acc`（0.3），不是 `engine%acc`」。两者都成立，但都**不解释** `--ohess tight` 在同一次运行里
   把 `landscape engine: SCC accuracy` 打成 `0.2` 和 `1.0` 这个**用户可见的自相矛盾**：`engine%acc` 是
   频率半每一点/每步的 SCF 精度（进 banner、进 `--ljson`），与 `hess_acc` 是两个概念。
   **复核结论「不是缺陷」是错的**，正确处置是修（本轮 T3），并且修的**方向**与复核给的第一条论据相反：
   上游原生 `--ohess` 两半不同精度是因为它两半本来就是**两次独立调用**；套件把 `--ohess` 定义成**一次运行的链**
   （设计 §3.11.1），一次运行的档位就该一次驱动。
   教训与 AGENTS §6 一致：**先测再改/再判**；本项是这条方向里第 14 次「静态结论被实测修正」。
2. **设计 §3.5 原文写「五处同步加 `if (acc_was_set)`」，实际是六处**（复核已按 6 处计）。本轮订正 §3.5 的
   状态段为 6 个读点并写明哑元传递。
3. **复现陷阱（本轮实际踩到）**：`--ohess` 的手工复现**不能**用 `test/unit/landscape_h2o.xyz`
   —— 该路径在源码树里**不存在**（fixture 由 `test/unit/CMakeLists.txt:162-163` 的 `file(WRITE ...)` 生成）。
   用错路径时 xtb 报 `No input file given, so there is nothing to do`（exit 1，先打 backtrace），
   极易误判成「改动把 `--ohess` 弄坏了」。正确 fixture：`<build>/test/unit/landscape_h2o.xyz`。

## 7. 未做的事（有意）

- 未改四轴数值、未重做 3c 的 T1-T4、未改算法本体、未碰核心层（0）。
- 未改 `settings.f90:384` 的库默认 `max_steps = 256`（复核 INFO-2，属有意设计；仅登记）。
- 未为 `lvset` 派生步预算（理由见 §3.2）。
- 未 `git add` 会话脚本；未提交。
