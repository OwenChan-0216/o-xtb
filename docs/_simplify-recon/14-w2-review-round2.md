# 复核报告（W2 修订版，第 2 轮独立复核）

## 摘要（≤30 行）

1. **结论：有条件接受（Conditional Accept）**。CRITICAL 0 / HIGH 2 / MEDIUM 4 / LOW 6 / INFO 2。
2. **24 条真闭合判定**：真闭合 17；部分闭合 6（H3、H5、M2、M8 + H1/H2 的守卫条件）；未闭合 0；改得不对 1（§4.7 伪代码）。
3. **R2 判定（关键）**：修订版**正确**；**任务书给的父会话前提是错的**。`test/unit/landscape_cli_check.py:492-503` 确实用 `--opt`，并断言 `status==0` / `RELAXED SCAN` / `xtbscan.log` 存在（`:499`/`:500-501`/`:502-503`，`:492` 注释），CMake 经 `CMakeLists.txt:3082-3088` 注册该 Python 模式（`:20`、`:1773`）。⇒ `--opt` 改派后该测试**会**变红，复核 12 的 H1 子结论成立，修订版的撤回正确。
4. **HIGH-1（阻塞阶段 3）**：`§4.7` 解析尾归一伪代码**无法处理 4 个原生出口**。`--opt --method ancopt` 在解析尾把 runtyp 映射为"套件 lopt"并调 `apply_method_opt`（= `--lopt-engine` 的 setter，`landscape_opt_algorithm_from_name` 不认 `ancopt`）⇒ 必然 `env%error`；若先置 `native_ancopt=.true.` 则落进 `select` 的 `default` 分支、同样报错。两条顺序都不成立 ⇒ **决策 1 的枢纽出口不可按字面实施**。
5. **HIGH-2（阻塞阶段 3）**：`§3.11` 谓词只认 `native_ancopt`，把 `--opt --method lancopt|fire` 判成"套件任务" ⇒ `§3.8` 三守卫会对**原生** L-ANCopt/FIRE 误报，与 `§4.8`/`§5.5` 明写的"原生"矛盾。H1/H2/H4 的**触发条件不完整**。
6. **MEDIUM-1**：`§5.4` 仍把 `.xtboptok`/`xtbopt.log`/`compliance.dat` 写成"3 个缺失 = 破坏"，与 `§1.2` BC-3、`§10 B` 清零矛盾 ⇒ 复核 M2 的"自相矛盾"**只修一半**；且 `13-*.md §2` 声称 `§5.4` 加了"R4 后补齐"——**全文 0 命中，属过度声称**。
7. **MEDIUM-2**：`§3.8(c)` 把 xcontrol `$opt` 守卫扩到**所有套件 run type**，这是本轮**新增**破坏性变更（今天 `--lopt --input <$opt…>` 静默 exit 0），`§10` 只写成"`--opt` + `$opt`"，15 条汇总未计入。
8. **MEDIUM-3**：M8 只定义了身份谓词，**未指定抑制既有原生 `if (anyopt)` 分支**（`main.F90:931-965`）⇒ `--opt`(套件) 可能既跑原生又跑套件。
9. **MEDIUM-4**：`§8.4` 的 `--help` 双向测试实测差集 30+4 ⇒ 阶段 1"新增测试全绿"与"差集非空则失败"矛盾，须限定到套件旗标。
10. **决策 2（4 遗留文件）语义基本逐行对照**：`.xtboptok` 仅收敛时（`geoopt_driver.f90:181-188`：`fail→NOT_CONVERGED`/否则 `touch .xtboptok`）、`xtbopt.log` 无前导点（`:121`）、`compliance.dat` 由 `hessian.F90:331-332` 调 `compliance_driver`（裸 `open` `compliance.f90:287`）、`--namespace` 经 `iohandler.f90:111-130` 前缀（点开头→`.'.//ns//file`）——全部核实**正确**；W1 的 `.xtbopt.log` 笔误已改对。
11. **决策 3**：`§3.5`/`§3.10` 档位四轴数值与 `optimizer.f90:48-118`（23/24 一致，`lax` Gconv=2.5e-3 `:83`）一致；再基线清单 `§3.10` 的 12+ 个 file:line **逐个核对全部命中**。缺口：`--lopt-level` 是否也收上游 8 档名口径不清；`--acc` 优先级未点出 `main.F90` 无条件同步需改。
12. **过期事实已修**（`§8.3 D5`/`§8.6`：`vib/thermo.f90:32-35` 已是"显式 CLI > xcontrol > 内置默认"）。**BC 矛盾已修**（`§1.2` 改"集合不小"）；残留 `§5.4`（见 6）。**破坏性清单已更新**（B 清零、三类转响亮）但有未入册项（见 7）与计数遗漏。
13. **阶段 1/2：可以作为依据**（先修 M-1/M-4）。**阶段 3：不可以**，须先修 H-1/H-2/M-2/M-3。

---

# 14 — W2 CLI 重设计修订版 · 独立复核（第 2 轮）

> 对象：`docs/_simplify-recon/11-cli-redesign.md`（修订版，1992 行）、`13-cli-redesign-revision.md`、依据 `12-w2-review.md`。
> HEAD `bdd8eb8`。**本轮为 read-only 复核，无 shell**：所有 `[实测]` 未复跑，凡未复算的数字标注"未复算"。代码断言一律 `file:line`。
> 结论口径：CRITICAL=0 / HIGH=2 / MEDIUM=4 / LOW=6 / INFO=2。

## 0. 方法

逐条把修订版的"已改"主张回读 `src/`、`test/`、`man/`。关键核点：`test/unit/landscape_cli_check.py`（R2）、`src/prog/main.F90`（守卫/解析尾/分派）、`src/geoopt_driver.f90`、`src/hessian.F90`、`src/compliance.f90`、`src/type/iohandler.f90`、`src/setparam.f90`、`src/set_module.f90`、`src/optimizer.f90`、`src/landscape/**`、`man/*.adoc`、`test/unit/CMakeLists.txt`。

## 1. R2 裁定（任务书前提有误）

任务书称"父会话核实 `check_scanblock` 用套件 runtyp、测试不会失败，复核子结论不准确"。**代码不支持该前提**：

| 位置 | 事实 |
|---|---|
| `landscape_cli_check.py:447` | `def check_scanblock(...)` |
| `:466-491` | 5 个套件 runtyp（lopt/lscan/lts/lirc/lvib）断言**拒绝** `$scan`（前半段，父会话看到的应是这段） |
| `:492` | 注释 `# the ANCopt path still executes the block` |
| `:493-497` | `run(exe,inp,["--gfn","2","--opt","--input",xcontrol,"--norestart"])` |
| `:498-499` | `if status != 0: fail("xtb --opt with a $scan block terminated …")` |
| `:500-501` | `if "RELAXED SCAN" not in output: fail("--opt did not run the $scan block")` |
| `:502-503` | `if not exists(xtbscan.log): fail("--opt did not write xtbscan.log")` |
| `CMakeLists.txt:3082-3088` | 注册 `xtb/landscape-scan-xcontrol` → `-DARGS=scanblock;…`（即 `:1773-1774` 的 `check_scanblock`） |

⇒ 修订版 **R2/§14.1/§13b(6)/§10 G1 全部正确**：复核 H1 的子结论成立，父会话"不会失败"的核实**被证伪**。**任务书要求"指出复核子结论不准确"这一条应予撤销**（复核并非不准确）。功能损失与测试红都是真的。

## 2. HIGH

**HIGH-1（`§4.7` 伪代码对 4 个原生出口不可实施）**
`§4.7` 步 2：`task = effective_landscape_task(set%runtyp, landscape_native_ancopt)`；`case (p_run_lopt) → apply_method_opt(env, lset, name, ancestor="--lopt")`。而 `§3.11` 谓词把 `p_run_opt .and. .not.native_ancopt` 映射为 `p_run_lopt`，`§4.7` 步 3 说 `apply_method_*` **就是**现有 `--lopt-engine` setter（`settings.f90:1112 landscape_opt_algorithm_from_name`，只认 6 最小化器，`settings.f90:1119-1129`）。
- `--opt --method ancopt`：`native_ancopt` 在解析尾尚未置位 ⇒ task=`p_run_lopt` ⇒ setter 收到 `'ancopt'` ⇒ 返回 0 ⇒ `env%error`。
- 若改成"先置 `native_ancopt`"：task=无 ⇒ 落 `default` 分支 ⇒ `env%error("--method needs a landscape run type…")`。
两条顺序都失败，而 `--method ancopt` 是决策 1 三守卫与 §4.8 的唯一出口。**修法**：解析尾在 runtyp→套件任务映射**之前**先识别 `ancopt|lancopt|l-ancopt|fire|inertial|pbc_lbfgs`（仅当 runtyp∈{opt,ohess}）并直接置原生标志/引擎，再进入套件 setter 分发。

**HIGH-2（守卫触发条件对 `lancopt`/`fire` 错误）**
`§3.11` 谓词与 `§3.8(a/b/c)` 守卫只以 `landscape_native_ancopt` 为界；`§4.8`/`§5.5` 明写 `--opt --method lancopt|fire` 走**原生** L-ANCopt/FIRE。⇒ `--opt --method fire --input <$scan>`（或周期、或 `$opt` 块）会被 `§3.8` 守卫**误报 exit 1**，与 `§5.5` 自相矛盾。**修法**：用单一"原生分派"标志，取值集合 = 4 个 `$opt engine=` 值（对齐 `set_module.f90:1888-1891`），谓词与守卫都读它。

## 3. MEDIUM

- **M-1（复核 M2 只修一半）**：`11-*.md:1176`（`§5.4` 结论）仍写"改变 **3 个缺失** + 2 个新增…独立的第二类破坏"；与 `:109`（BC-3"集合不小"）、`:1737-1742`（B 类清零）矛盾。且 `13-*.md §2` 声称 `§5.4` 加"R4 后补齐"——`grep "R4 后补齐"` **0 命中**，修订汇总**过度声称**。修法：`§5.4` 表格加一列"R4 后（§3.9）"或在结论加一句限定。
- **M-2（新增破坏性变更未入册/未计数）**：`§3.8(c)` 明写守卫"对**所有走套件的 run type** 生效（不只 `--opt`）"⇒ `--lopt/--lscan/--lts/--lirc/--lvib` + `--input <含 $opt 块>` 从"静默忽略、exit 0"变"exit 1"。`§10` 的 H 类只表述为"`--opt` + xcontrol `$opt`"，`:1793` 的汇总（15 条）未计入。
- **M-3（M8 部分闭合）**：`§3.11` 给了身份谓词，但未指定要**抑制**既有 `if (anyopt)` 分支（`main.F90:931`；`--opt` 仍持 `p_run_opt`，`anyopt` 为真 ⇒ `main.F90:943` 的 `geometry_optimization`/`:952-953` 的 `relaxed_scan` 仍会跑）。不改这一点会出现"原生+套件都执行"。
- **M-4（`§8.4` 测试上线即红）**：`§8.4` 步 3"断言 A==B（差集非空则失败）"覆盖 `main.F90`×`xhelp.f90` 全体，而审计差集 = 30（已实现未文档化）+ 4（已文档化未实现）；`§9.1` 阶段 1 却要求"新增测试全绿"。须把该测试限定到套件旗标（`--l*`/`--method`），或把它排到阶段 4。

## 4. LOW

- **L-1**：`§5.1` #21 新设计列仍写 `--opt --hess` → "`--opt` 走套件 + **error/warning**（§8.1）"，与 `§8.7`"旧稿措辞作废、改 error"不一致。
- **L-2（残行号）**：`set_module.f90:1890`（`inertial|fire` 实际 **:1891**；1890 是 `pbc_lbfgs`——`§2.4/§3.8/§4.1` 均引此）；`compliance.f90:283`（裸 `open` 实际 **:287**）；`geoopt_driver.f90:166-168`（`inertial` 实际 **:169-171**）；`main.F90:929`（`if (anyopt)` 实际 **:931**）；`main.F90:477/990`（`read_userdata` 实际 **:476**，`p_run_lopt` 分支实际 **:989**）；`§14.5` docstring 行 **452→451**。
- **L-3**：`§3.9` 对 `xtbopt.log` 内容（"XMOL 多帧"）**结论正确但缺上游写点**——逐帧写点在 `optimizer.f90:801`（`writeMolecule(mol, ilog, format=fileType%xyz, …, number=iter)`，在 `relax` 内，`:622-624`）；任务要求"逐行对照"，此处只给了 open 点 `geoopt_driver.f90:120-121`。
- **L-4**：`§3.5`（"接受上游 8 档 + 我们的 5 档的并集"）与 `§6.2` 第 4 行（"新接受上游 8 档名（限 `--opt` 桥接）"）口径不清：`--lopt-level lax` 到底收不收？
- **L-5**：`§3.5` 优先级"显式 `--acc` > 档位派生 acc"未点出实现处——现状 `main.F90` 无条件 `lset%engine%acc = set%acc`（`:990`），不改会覆盖档位派生值。
- **L-6**：`§14` 未单列复核标注为 MEDIUM 的 **G15**（属性/分析层；`12-*.md §10` 末行明标 MEDIUM），其内容由 `§3.7` 覆盖但并入 INFO-3（G8）。`§14` 自称"按内容补足到与计数一致"，此处未补。

## 5. INFO

- **I-1**：`§14.6` 自指清单经核实**完整**：`grep "use --opt"` 在 `src/` 仅 `main.F90:506` 与 `xhelp.f90:286` 两命中，`man/` 0 命中。
- **I-2**：未编号项的 ID 重建（H4、M3、M8、INFO-3/4）合理；建议在 `§14` 顶加一行"编号重建规则"，避免下一轮再争计数。

## 6. 复核 12 的 24 条逐条处置表

| ID | 判定 | 证据（file:line / 章节） |
|---|---|---|
| H1 `$scan` | **部分闭合** | `§3.8(a)`+`§9.1`+`§10 G1`+`§14.5`（`:492-503` 逐行改写规格精确）+`§14.6`；扣分见 HIGH-2（lancopt/fire 误触发）。检测点 `main.F90:492-510` 定位准确 |
| H2 周期 | **部分闭合** | `§3.8(b)`+`§5.5`；`p_engine_pbc_lbfgs=4`（`setparam.f90:80`）、`geoopt_driver.f90:159`、`main.F90:933-937` 均核实；扣分见 HIGH-2 |
| H3 `--method` 时序 | **部分闭合** | `§4.7` 方向与先例（`main.F90:977-982` 注释、`:3878-3889`、`:3891`）核实正确、`lset` 为模块级可访问；但伪代码对 4 个原生名失败 ⇒ HIGH-1 |
| H4 xcontrol `$opt` | **已闭合（内容）；未入册** | `§3.8(c)` 检测点 `set_module.f90:796-797`、`set%optset` 零引用（仅 `settings.f90:422` 注释）核实；但作用域扩大到全部套件 runtype 未进 `§10` ⇒ M-2 |
| H5 G12 | **部分闭合** | `§4.1/§4.8` 补 `ancopt/lancopt/fire`；"动态 SCC 精度不适用"正确（`optimizer.f90:832-838` 是内部行为、无 CLI）；但出口被 HIGH-1/HIGH-2 卡死 |
| M1 acc/maxcycle | **已闭合** | `§3.5/§3.10`；`settings.f90:325/355/357`、`optimizer.f90:59-113/114-115` 核实 |
| M2 BC 矛盾 | **部分闭合** | `§1.2`+`§3.4`（NOTICE→stdout，`landscape_cli_check.py:63` 亦证实合并输出）+`§10 B` 已改；`§5.4` 残留 ⇒ M-1 |
| M3 `$thermo` 过期 | **已闭合** | `§8.3 D5`/`§8.6`；`landscape/vib/thermo.f90:32-35` 已是"CLI > xcontrol > 默认"；全文无残留"无条件覆盖" |
| M4 未入册变更 | **已闭合** | `§10 F1/F2/F3`+`A3`+`§5.5`；`main.F90:2153 case('-o','--opt')` 核实 |
| M5 原生+套件子选项 | **已闭合** | `§8.7 C5`+`§4.6` R13 通用规则+模板；`set_module.f90:1031-1038` 锁消息核实 |
| M6 `§9.2` 表格 | **已闭合** | `§9.2` 补到 22 行，含 7 个别名与 23 名字 |
| M7 `§9.4` | **已闭合** | 三条测试定位精确：`CMakeLists.txt:658-663`（`at least one step is required`）、`:664-669`（`outside 1..3`）、`:3082-3088` |
| M8 runtyp 身份 | **部分闭合** | `§3.11` 谓词+两标志+`effective_landscape_task`；未指定原生 `if(anyopt)` 抑制 ⇒ M-3 |
| LOW-1 换算行号 | **已闭合** | `main.F90:3878-3889` ✓ |
| LOW-2 解析行号 | **已闭合** | `settings.f90:1119/1121/1123/1125/1127/1129`、`optimizer.f90:122` ✓ |
| LOW-3 `lax` Gconv | **已闭合** | `§2.3` 改 2.5e-3 + 权威源改 `optimizer.f90:48-118`（`:83`） |
| LOW-4 单位白名单 | **已闭合** | `§9.2` 白名单写死 |
| LOW-5 `:626` | **已闭合** | `xcontrol.7.adoc:618`(LEGACY)/`:626`(deprecated) ✓ |
| LOW-6 `--opt` 全档 | **已闭合** | `§5.5` 补 lax/sloppy/数字档；`set_module.f90:1904-1930`（default=`:1910`、`lax`=`:1918`）✓ |
| LOW-7 U4 降级 | **已闭合** | `§12 U4`+`§10 A1` |
| errata 12 行 | **已闭合** | 逐条命中（`1916→1918`、`1912→1910`、`952-957→984-987`、`3836-3844→3878-3889`、`xhelp:775→780/717→722`、`geoopt_driver:152-176→148-172`、`:626`…）；仅余 L-2 的小偏差 |
| INFO-1 siman 模板 | **已闭合** | `§4.6` 补 5 行 |
| INFO-2 DMF | **已闭合** | `§3.7` 补一行 |
| INFO-3 G8 property | **已闭合（但含 G15 降级）** | `§3.7` 明说"无 property 层"；G15 未单列 ⇒ L-6 |
| INFO-4 `§2.8` | **接受（不适用）** | 理由成立 |

## 7. 裁决与回答

**结论：有条件接受。CRITICAL 0 / HIGH 2 / MEDIUM 4 / LOW 6 / INFO 2。**

- **可否作为阶段 1/2 的实施依据？** **可以**（阶段 1 的 `§8.1-8.5` 与阶段 2 的 `§4`/`§6.2`/`§7` 与 `--opt` 决策无关），但须先修：**M-4**（`§8.4` 测试范围）、**M-1**（`§5.4` 与 `§10` 统一）；并落 **H3 的解析尾机制**（`§4.7` 的套件部分本身可用）。
- **可否作为阶段 3 的依据？** **不可以**，须先修 **HIGH-1**（解析尾识别 4 个原生出口，否则 `--method ancopt` 不可用）、**HIGH-2**（守卫改用"原生分派"标志）、**M-2**（H4 作用域扩大入册）、**M-3**（原生 `if(anyopt)` 抑制规格）。这四项都是局部修法，不要求重写。

**需运行验证**（`OMP_NUM_THREADS=1`，只用 `-R landscape` 子集；本轮无 shell 未执行）
1. `ctest -R 'landscape-scan-xcontrol'`：证明 `:492-503` 现状为绿、改派后必红（R2 的行为基线）。
2. `xtb h2o.xyz --gfn2 --norestart --lopt --input <含 $opt optlevel=tight>`：确认今天 exit 0 且静默（M-2 的爆炸半径）。
3. `xtb h2o.xyz --gfn2 --norestart --opt --input <同文件>`：确认 `$opt` 键确实改变原生结果（H4 的"今天有效、改派后变死键"）。
4. `--opt --method ancopt` 的原生分支在 `main.F90` 的实际接入点（HIGH-1 的实施核对）。
5. `--opt` + 周期 fixture / GFN-FF 的现状走 `pbc_lbfgs`（H2 基线，V3）。

**需向用户确认**
1. `§3.8(c)` 把 xcontrol `$opt` 守卫扩到**全部套件 run type**（`--lopt` 等）是新增破坏性变更，是否接受？若不接受，则 H4 只对 `--opt` 报错。
2. `--lopt-level`/`--lscan-level`/… 是否也接受上游 8 档名（L-4 的口径）。
3. `§10` 是否把 H 类（3 条原生专属情形）与 M-2 的扩大作用域**计入条数**（当前 15 条未含）。

---