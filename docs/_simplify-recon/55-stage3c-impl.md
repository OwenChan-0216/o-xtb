# 阶段 3c 实施报告 — R5 档位四轴（`e_tol`/`acc`/`max_steps`）+ §3.10 再基线

> 基线 `8b85c6d`（工作树干净），构建 `/tmp/xtb-3c/build`（`-O2 -DNDEBUG`），
> 所有 xtb / ctest 调用 `OMP_NUM_THREADS=1`。权威设计 = `11-cli-redesign.md` §3.5/§3.10 + §10 E1。
> **状态：T1–T6 全部落地**；`ctest -R landscape` = **146/146 绿**（145 + 新增 1），回归子集 **12/12 绿**。

---

## 0. 源改动表

| T | 文件 | 行 | 改动 |
|---|---|---|---|
| T1 | `src/landscape/types/settings.f90` | `:373` 附近 | `landscape_settings` 新增 `max_steps_multiplier`（默认 **3** = `normal`）与 `max_steps_source`（可分配字符串，空 = 未显式） |
| T1 | 同上 | `:410` | 新增 type-bound `level_step_budget => landscape_settings_level_step_budget` |
| T1 | 同上 | `:1120-1200` | `set_conv_level` 每档补写 `e_tol` / `engine%acc` / `max_steps_multiplier`（5 档 × 3 = 15 处新赋值，数值照抄上游 `get_optthr`） |
| T1 | 同上 | `:1205` 附近 | 新过程 `landscape_settings_level_step_budget(natoms)`：`max_steps_source` 非空则**不动**，否则 `clamp(natoms*mult,200,10000)` |
| T2 | `src/prog/main.F90` | `:129`（`program xtb` 宿主） | 新增 `logical :: acc_was_set = .false.`（`xtbMain` 与 `parseArguments` 共享） |
| T2 | 同上 | `:1806` | `parseArguments` 开场复位 `acc_was_set = .false.`（C API 重入安全） |
| T2 | 同上 | `case ('-a','--acc')` | `getValue` 成功后置 `acc_was_set = .true.` |
| T2 | 同上 | 6 处（lopt / ohess-vib 半 / lscan / lts / lirc / lvib） | `engine%acc = set%acc` → `if (acc_was_set) engine%acc = set%acc` |
| T3 | `src/landscape/tasks/{opt,scan,ts,irc,vib}.f90` | opt `:116`、scan `:144`、ts `:171`、irc `:164`、vib `:141` 后 | 新增 `energy tolerance:         <es15.6> Eh` 回显（值取自设置对象）；scan 刚性模式与 vib 各附一行 `(not used: ...)` 说明 |
| T4 | `src/prog/main.F90` | 4 个 `case ('--l*-max-steps')` | 置 `max_steps_source = '--l*-max-steps'` |
| T4 | 同上 | `landscape_bridge_step_budget` | 新增可选 `budget_source`：`--cycles` 胜出时记 `'--cycles'`；4 个调用点传入对应 `max_steps_source` |
| T4 | 同上 | 4 个分派点 | 新增 `call <settings>%level_step_budget(mol%n)`（lts 在 `ltset%path%max_steps = ltset%max_steps` **之前**） |

**未改**：`--l*-level` 的已知名集合（仍 5 个套件名，`superloose/loose/normal/tight/vtight`）、
`src/type|xtb|mctc|param|io|disp|coulomb`（0 触碰）、`optimize/`·`saddle/`·`path/`·`irc/`·`scan/` 的数学本体。

**上游逐字对齐（T1 的"先查证"）**：上游 `get_optthr(n, olev, ...)`（`src/optimizer.f90:48-119`）的
`n` 是原子数——调用点 `optimizer.f90:332` `call get_optthr(mol%n, tight, ethr, gthr, maxopt, acc)`；
钳位在 `:113-114` `maxcycle=min(maxcycle,10000); maxcycle=max(maxcycle,200)`。
套件用同一个 `mol%n`（`main.F90` 分派点）与同一条钳位规则，**逐字一致**。

### T1 逐档数值（`set_conv_level` 写入值，与设计 §3.5 / 上游表逐值相同）

| 档位 | `e_tol` | `engine%acc` | `max_steps_multiplier` |
|---|---|---|---|
| superloose | 5.0e-4 | 3.0 | 1 |
| loose | 5.0e-5 | 2.0 | 2 |
| normal | 5.0e-6 | 1.0 | 3 |
| tight | 1.0e-6 | 0.2 | 5 |
| vtight | 1.0e-7 | 0.05 | 20 |

---

## 1. T2/T3/T4 实测（注入真实输出）

命令（水 `landscape_h2o.xyz`，`--gfn2 ... --norestart`，`OMP_NUM_THREADS=1`）：

```
$ xtb landscape_h2o.xyz --gfn2 --lopt --lopt-level loose | grep -E "maximum number of steps|SCC accuracy|energy tolerance"
 maximum number of steps:  200
 energy tolerance:            5.000000E-05 Eh
 landscape engine: SCC accuracy              2.000000
```

| 用例 | `maximum number of steps` | `energy tolerance` | `engine: SCC accuracy` | 说明 |
|---|---|---|---|---|
| `--lopt`（默认档 = normal） | **200** | 5.000000E-06 | 1.000000 | 旧默认预算是 **256** ⇒ 256→200 = clamp(3n,200,10000)（n=3，下界绑定） |
| `--lopt --lopt-level loose` | 200 | 5.000000E-05 | **2.000000** | T2：改前这里恒为 1.0（死旋钮） |
| `--lopt --lopt-level loose --acc 1.0` | 200 | 5.000000E-05 | **1.000000** | 显式 `--acc` 优先 |
| `--lopt --lopt-level tight` | 200 | **1.000000E-06** | **0.200000** | T3 回显 |
| `--lopt --lopt-level tight --lopt-max-steps 8` | **8** | 1.000000E-06 | 0.200000 | T4：显式覆盖派生 |
| `--lopt --cycles 4` | **4** | 5.000000E-06 | 1.000000 | T4：`--cycles` 覆盖派生（该运行按预期 exit 1：预算不足未收敛） |
| `--lopt --lopt-level superloose` | 200 | **5.000000E-04** | **3.000000** | |
| `--lopt --lopt-level vtight` | 200 | **1.000000E-07** | **0.050000** | |

其余任务的回显实测：

```
$ xtb landscape_h2o.xyz --gfn2 --lscan --lscan-mode rigid ...   （exit 1，点失败属既有行为）
 number of coordinates:    1
 energy tolerance:            5.000000E-06 Eh
 (not used: a rigid scan runs no inner relaxation)
 (not used: a rigid scan builds no Hessian)
$ xtb landscape_h2o.xyz --gfn2 --lscan --lscan-mode relaxed ...  （exit 0）
 energy tolerance:            5.000000E-06 Eh        ← 无 rigid 提示
$ xtb landscape_h2o.xyz --gfn2 --lvib
 energy tolerance:            5.000000E-06 Eh
 (not used: the frequency task has no convergence loop)
```

**可证伪性（注入实测，两次独立构建）**

1. 把 lopt 分支的 `if (acc_was_set) lset%engine%acc = set%acc` 改回无条件写入 ⇒
   `ctest -R landscape-level-axes` **红**，消息
   `FAIL: --lopt-level loose does not report acc 2.0 (dead knob, T2)`；还原 ⇒ 绿。
2. 删掉分派点的 `call lset%level_step_budget(mol%n)` ⇒ 同测试 **红**，消息
   `FAIL: the default level does not report clamp(3n, 200, 10000) = 200`；还原 ⇒ 绿。

**新增可证伪测试**：`xtb/landscape-level-axes`（登记在 `test/unit/CMakeLists.txt` + `test/unit/meson.build`，
检查实现 = `test/unit/landscape_cli_check.py` 的 `levelaxes` 模式，函数 `check_level_axes`）；
单元侧 `test/unit/test_landscape_settings.f90` 新增用例 `level-step-budget`（`clamp` 两端 + 500 原子缩放 +
显式优先），并把 `convergence-levels` 扩到三轴、`enum-case` 扩到 `e_tol`/`acc`/multiplier。

---

## 2. §3.10 再基线清单表（逐个实测，非静态推断）

| # | 项 | 旧值（已验收） | 新值（本轮实测） | 是否有意 | 依据 / 证据 |
|---|---|---|---|---|---|
| 1 | 默认档 `max_steps`（H2O，CLI） | 256 | **200** | ✅ 有意 | E1 的核心；`clamp(3·3,200,10000)`。旧 golden 在 `xtb/landscape-opt-knobs`，已按新语义改写（断言 `200` + 理由注释） |
| 2 | M3/M7 链 dfreq（H2O，`--lopt --lopt-level tight`） | 0.0100 cm⁻¹ | **0.0100 cm⁻¹** | ❌ 未动 | `landscape_e2e_check.py chain`：`max dfreq 0.0100 cm^-1 (tol 0.20), dZPE 1.429e-08, dH 1.427e-08, dG 1.430e-08 hartree` |
| 3 | M3 频率绝对值 | 1539.58 / 3643.01 / 3651.17 | **同** | ❌ 未动 | 同一条链输出 |
| 4 | M4 prfo-vs-bprfo RMSD | 6.3022e-06 bohr | **6.3022E-06 bohr** | ❌ 未动 | `xtb/landscape-saddle` 打印行 |
| 5 | M4 dimer-vs-prfo RMSD | 7.7397e-05 bohr | **未重测** | — | 该数字在当前 HEAD 的测试里**没有打印点**（`grep RMSD test/unit/test_landscape_saddle.f90` ⇒ 仅 `:968` 一处）；模型势无 SCF ⇒ 不受档位影响（**未做项**，见 §4） |
| 6 | M5 LEPS 解析势垒 | 8.9985 kcal/mol | **8.998500** | ❌ 未动 | `xtb/landscape-path` 打印 + 断言 `test_landscape_path.f90:462` |
| 7 | M5 NEB/CI-NEB 势垒 | 8.9985 | **8.9985 / +0.0000** | ❌ 未动 | 同上 |
| 8 | M5 MB band / AutoNEB | 105.7730 / 105.7230 | **105.7730 / 105.7230** | ❌ 未动 | 同上 |
| 9 | M6 四法 MEP 偏离（fwd） | 0.03995 / 0.00657 / 0.00215 / 0.02574 | **同** | ❌ 未动 | `xtb/landscape-irc` 打印行 |
| 10 | M6 四法 MEP 偏离（bwd） | 0.04132 / 0.01913 / 0.01395 / 0.02806 | **同** | ❌ 未动 | 同上 |
| 11 | 22 处 `set_conv_level` 调用点 | 断言"收敛/步数" | **全部仍成立** | — | `ctest -R landscape` 146/146；`test_landscape_failure.f90` 钉的 `n_steps`（129/167/178/210/290）与 `test_landscape_scan.f90` 的 7 处均未失效 ⇒ **只改了一处 golden（第 1 行）** |
| 12 | `landscape_cli_check.py` 的 `(not used: ...)` 约定 | 单个 notice 的 `re.search` | 改为 `findall` + 只拒"含 Hessian/finite"的 notice | ✅ 有意 | 3c 新增了两条与 Hessian 无关的 `(not used: ...)` 提示（刚性扫描 / `--lvib`），旧断言会误红；理由写在检查函数注释里（**不是**放宽断言：`unused-*` 侧仍要求 hint 出现在某条 notice 中） |
| 13 | 原生 runtype 不受影响 | — | **仍不受影响** | ❌ 未动 | `xtb/landscape-native-runtypes-unaffected` 绿 |
| 14 | M2 滞回数据（77 文件） | 见 `m2-hysteresis-data/` | **未重跑** | — | 判定见 §3 |

**回归子集**：`ctest -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'` = **12/12 通过**。

---

## 3. M2 滞回数据的判定（未全量重跑，给理由）

- **默认档 `normal`**：`e_tol`（5e-6）与 `acc`（1.0）**逐字不变**，只有 `max_steps` 256→200；
  滞回是**收敛残差**而非物理量（AGENTS §6 第 8 条），预算从 256 降到 200 只改变"内层弛豫是否被预算截断"，
  而实测内层弛豫在 `normal` 档只需 177 次引擎求值（设计 §3.5 [实测] 表），远未触到 200 个宏观步。
  ⇒ **判定：默认档不受实质影响**。
- **非默认档**：`m2-hysteresis-data/` 的记录是用 `--lscan-level loose|vtight` 之类跑出来的，而这些档位在本轮
  之后**还会**带 `acc`=2.0/0.05 与 `e_tol`=5e-5/1e-7 ⇒ 重跑那批点得到的是**另一组设置**，
  不能当作"同一实验的新值"比对。数据集因此成为 **3c 之前的档位语义**的历史记录，不是需要刷新的 golden。
- **未做项**：给出的不是实测滞回数值，而是"默认档是否受影响"的判定（任务 T5.4 允许的口径）。

---

## 4. 测试计数与未做项

| 项 | 值 |
|---|---|
| `ctest -R landscape` | **146 / 146 通过**（基线 145 + 新增 `xtb/landscape-level-axes`），耗时 ≈ 47 s |
| 回归子集（`-R 'Singlepoint\|GFN\|model-hessian\|optimizer\|Argparser\|CAPI'`） | **12 / 12 通过** |
| 单元新增用例 | `landscape-settings` 用例表新增 `level-step-budget`；`convergence-levels` / `enum-case` 扩充（三轴） |
| CLI 新增测试 | `xtb/landscape-level-axes`（CMake + meson 双登记；`ctest -N -R landscape` 无重名） |
| 构建 | `/tmp/xtb-3c/build`，`-O2 -DNDEBUG`，零警告新增 |

**未做项（显式列出）**

1. **M2 滞回 77 文件未重跑**（理由见 §3；任务 T5.4 允许）。
2. **M4 dimer-vs-prfo 7.7397e-05 未重测**：当前 HEAD 的测试里没有该打印点（不是本轮删的，
   可用 `git log -p` 核对）；模型势 + 显式预算 ⇒ 静态判断不受档位影响，但**未实测**。
3. **M3 CH3OH dfreq 0.0600 未重跑**（人工实验，`m7-e2e-data/exp1-thermo/`；不在 ctest 里）。
4. **`max_steps_multiplier` 的 CLI 侧只有下界可证伪**：水（n=3）在 5 档上都是 200，倍数差异要
   `3n≥200`（n≥67）才可观测，而在 CLI 上跑一个 ≥67 原子的优化代价高。⇒ 该轴的缩放由**单测**
   `level-step-budget`（500 原子 → 1500；2000 原子 + vtight → 10000）证伪，CLI 侧只证"派生发生了 + 显式优先"。
5. **meson 侧未构建**（本机无 meson/ninja）；`meson.build` 的登记是手工同步的。

---

## 5. 被证伪的前提（实测推翻的静态结论）

1. **"22 处 `set_conv_level` 调用点会看到新的步数断言值并大量失效"**（`49-stage3b-recon.md` B6/B7 的预判）
   —— **证伪**。因为派生放在 **CLI 分派点**（`xtbMain`，那里才有 `mol%n`），库层（单测直接构造的设置对象）
   的 `max_steps` 语义**逐字未变**；只有 `e_tol`/`acc` 随档位变，而 22 处用例没有一处依赖旧的固定 `e_tol`。
   结论：22 个用例全部仍绿，**只更新了 1 处 golden**（`landscape-opt-knobs` 的 256→200）。
2. **"`e_tol` 只能通过数值轨迹间接证伪"**（`49-stage3b-recon.md` A5）—— 本轮把它变成**直接可观测**
   （stdout 回显），并把该回显本身纳入新 CLI 测试；缺回显时 T3 的注入即红。
3. **"`--l*-max-steps` 与档位派生可以按解析顺序自然定序"** —— **证伪**：档位在解析期写字段、预算也在解析期
   写字段，只按顺序会互相覆盖；必须引入**来源**字段（`max_steps_source`）才能让"显式优先"与顺序无关
   （`--lopt-max-steps 8 --lopt-level tight` 与反序同为空话）。这也是 `--cycles` 桥必须同时记来源的原因
   （否则分派点的派生会把 `--cycles 4` 覆盖回 200）。
4. **"加一行 `(not used: ...)` 不影响既有测试"** —— **证伪**：`xtb/landscape-hess-step-used` 用
   `^\s*\(not used: (.*)\)\s*$` 的**首条**匹配断言"未使用的原因"，3c 新增的提示插在它之前 ⇒ 误红。
   处理：`findall` + 只拒含 `Hessian`/`finite` 的 notice（既保留原断言强度，又允许无关 notice 共存）。

---

## 6. 复现命令（全部 `OMP_NUM_THREADS=1`）

```bash
XTB=/tmp/xtb-3c/build/xtb; W=/tmp/xtb-3c/build/test/unit/landscape_h2o.xyz
$XTB $W --gfn2 --lopt --lopt-level loose --norestart | \
  grep -E "maximum number of steps|SCC accuracy|energy tolerance"
ctest --test-dir /tmp/xtb-3c/build -R landscape
ctest --test-dir /tmp/xtb-3c/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
python3 test/unit/landscape_e2e_check.py chain $XTB $W /tmp/s3c/chain
```

---

## 7. 留给复核的判定项（未自作决定）

1. **`--ohess` 的 vib 半是否应继承档位派生 `acc`**：本轮按批准方向把 6 个写入点**统一**改为
   `if (acc_was_set)`（含 `main.F90` 的 `--ohess` vib 半），所以在 `--ohess tight` 下：minimisation 半用
   `acc`=0.2（档位派生），频率半仍是 `lvset` 自己的默认 1.0（未显式 `--acc` 时不被覆盖）。
   设计 §3.5 只写了"档位驱动**该运行**的 SCF 精度"，未明确两半是否应同精度；此处**按现状落地**，
   若复核认为频率半也应取档位 `acc`，改动很小（把档位值同步给 `lvset%engine%acc`，并加一条断言）。
2. **`e_tol` 不属于 `landscape_<task>.json` 的 10 键 schema**（本轮只加 stdout 回显）。
   若希望机器可读的回归也能钉 `e_tol`，需改 schema（本轮不动）。
3. **M2 滞回数据集**的处置：建议在数据集 README 里标明"记录于 3c 之前的档位语义"（本轮未改数据目录）。
