## Review

- **Correct**: `11-cli-redesign.md` 的**代码引用纪律异常扎实**——§6.2 的 121 行 `main.F90` 行号经我逐条机器核对**全部精确**；`man/xtb.1.adoc`、`man/xcontrol.7.adoc` 的引用逐条命中；上游 8 档收敛表与仓库内 `src/optimizer.f90:48-118` 的**24 个数值中 23 个完全一致**（唯一 `lax` 的 Gconv 有差），⇒ **未发现编造**；`git status` 自检与 `watchdog_diff` 实测一致（未动 src/test）。
- **Finding**: **P0(CRITICAL) 0 / P1(HIGH) 5 / P2(MEDIUM) 8 / LOW 7 / INFO 4**。核心缺陷全部集中在 §3/§10 的**影响面分析**：C 方案改派 `--opt` 会连带丢掉 **`$scan`（且打破已注册测试 `xtb/landscape-scan-xcontrol`）**、**周期体系 `--opt`**、**xcontrol `$opt` 键与 L-ANCopt/FIRE**，这些在破坏性清单里**一条都没有**；另有 1 条「现状事实」已过期（`$thermo` 早已修好）、1 条 `--method` 解析时序无法按字面实现、以及 BC 判据与本设计正文自相矛盾。
- **Fixed**: 本次为 review-only，未改任何文件（含未写 `progress.md`）；产出报告正文交父会话落盘。
- **Merge verdict**: **BLOCK（阶段 3 `--opt`/`--ohess` 改派）+ OK with notes（阶段 1/2 的 §8.1/8.2/8.4/8.5 与 §4/§6.2/§7 设计）** —— 见 §14，需闭合 H3/M2/M4/M5/M6/M7 后可用于阶段 1/2；H1/H2/H5/M1/M8 必须闭合后才能动阶段 3。

---

# 12 — W2 CLI 重设计文档独立复核（评审员）

> 对象：`docs/_simplify-recon/11-cli-redesign.md`（设计）；`08-four-way-capability-boundary.md`（订正后）+ `10-w1-report-corrections.md`（订正记录）；`02-cli-audit.md`（现状事实）
> 基线：HEAD `bdd8eb8`，我的工作树经 `watchdog_diff` 实测与 `11-*.md` §13 自检**逐字一致**（只有 6 个未跟踪文件，`src/`、`test/` 零改动）
> 证据分级沿用文档自身的 `[实测]`/`[代码]`/`[文档]`/`[未验证]`；**本次复核无 shell**，一切 `[实测]` 我无法重跑，凡我未复算的实测数字一律标 `未验证`（见 §12）
> 结论口径：CRITICAL=0 / **HIGH=5** / MEDIUM=8 / LOW=7 / INFO=4

## 0. 摘要（先看这段）

| # | 主题 | 结论 |
|---|---|---|
| 1 | web 调研可信度 | **未发现编造**。可核部分（man 页、level 数值、默认档、`--omd` 硬编码 loose、上游无 `--method`）**全部通过**；纯 URL 内容本机不可核（`未验证`）。唯一数值出入：`lax` 的 Gconv 文档写 2e-3、`src/optimizer.f90:83` 是 **2.5e-3**（LOW-3） |
| 2 | `--method` 取值域 | **6+8+4+1+1 = 20 个名字全部在源码中存在**，无虚构、无遗漏；TS/IRC 两表 `file:line` **逐条精确**；最小化器表解析行 5/6 偏移 +2（LOW-2） |
| 3 | 后向兼容矩阵 | 语法层覆盖良好，但**漏 6 类调用**：`-o`、`--opt` 的全部 8 档+数字档、`--opt`×`$scan`（H1）、`--opt`×周期（H2）、`--opt`×xcontrol `$opt`（H5）、"原生 runtype + 套件子选项"整类（M5） |
| 4 | `--opt normal` 语义依据 | **有依据**（既有默认 `settings.f90:427` 可核 + 实测代价表 + 文献），非拍脑袋。但**静默陷阱确实存在且被低估**：档位还带走 SCF 精度/maxcycle（M1），`$opt`/`FIRE` 出口未设计（H5） |
| 5 | 冲突与错误处理 | 方向正确（error + 可操作消息），**无残留"首选项获胜"**；但 §8.5 自己又引入 2 条未入册的行为变更（M4），且"原生 runtype+套件子选项"大类未覆盖（M5） |
| 6 | 单位与命名 | `--lirc-step` vs `--lirc-step-hess` 的分离是**真解**；`--lscan-step`（Å/度）仍是"文档+回显"路线，**单位未进名字**，设计已给出可测判据（§7.3 硬性要求），可接受；但引用行号错（L1） |
| 7 | 实施计划与测试 | 阶段划分大体可独立验收；**§9.2「强制表格」漏掉 §6.3 的全部新旗标与 7 个别名**（M6）；§9.4 漏 2 条断言消息文本的既有测试（M7）；弃用策略明确（永久别名+不告警） |
| 8 | 破坏性清单诚实性 | 6 类划分**方向诚实**（明确否定旧稿"1 条"），但**不完整**：`$scan`（H1）、周期（H2）、xcontrol `$opt`（H5）、per-level SCC 精度（M1）、`-o`（M4）均属破坏性却未入册；BC-3/BC-5 的"满足"表述与 §10 矛盾（M2） |
| 9 | 遗漏能力 | W1 的 G1/G2/G3-G7/G8 基本覆盖；**G9/G10（PBC）、G12（FIRE/model Hessian 变体）、G13（`$scan`）、G15（属性层）无任何说明**；G15/G8 未明说"无法经 CLI 暴露"（H1/H2/H5/M7-L6） |
| 10 | 能否作为实施依据 | **有条件接受**：阶段 1/2 的 §8.1/8.2/8.4/8.5 + §4/§6.2/§7 **可在闭合 M2/M4/M5/M6/M7 后直接实施**；**阶段 3 必须先闭合 H1/H2/H3/H5/M1/M8**，否则会产生 3 处能力回退 + 1 个测试红 + 1 条自指错误消息 |

---

## 1. 复核方法（哪些是机器核对，哪些不是）

| 手段 | 覆盖 |
|---|---|
| **逐条机器核对** | `grep -n "^ {9}case \('--l" src/prog/main.F90` 全表 ↔ §6.2 的 121 行行号（**全部命中**）；`man/xtb.1.adoc`/`man/xcontrol.7.adoc` 被引行；`src/optimizer.f90:48-118`、`src/set_module.f90:1904-1930`、`src/setparam.f90:68-75,197-218`、`src/landscape/types/settings.f90`、`src/geoopt_driver.f90:148-190`、`src/landscape/types/log.f90:74,87`、`test/unit/CMakeLists.txt`、`test/unit/landscape_cli_check.py` |
| **静态能力核对** | 套件对 `compliance_driver`/`xtboptok`/`xtblast`/`optset`/`maxcycle`/`n_cache_miss`/PBC 的引用（全目录 grep） |
| **`watchdog_diff`** | 工作树 delta：与 §13 自检一致，`src/`、`test/` 未被触碰 |
| **未做（无 shell）** | 一切 xtb 运行、`ctest`。文档的 90% `[实测]` 我**没有复算** ⇒ 见 §12「需运行验证」 |

**证伪前提（我若发现即以此报告为准）**：
1. 「W2 未改 src/test」→ **成立**（`watchdog_diff`）。
2. 「§6.2 的 121 个行号是 HEAD `bdd8eb8` 实测」→ **成立**（逐条命中，非 +37 套用）。
3. 「套件没有任何测试会因 stderr 多一行而变红（U5）」→ **部分不成立**：CMake 侧 `OUTPUT_VARIABLE output` 与 `ERROR_VARIABLE output` **同名合并**（`test/unit/CMakeLists.txt:513-514` 等），Python 侧 `run()` 明确返回 `"combined output"`（`landscape_cli_check.py:55-61`）⇒ **stderr 被合并进断言流**；但断言全是 `MATCHES`/`in` 子串式，**多一行 NOTICE 不会变红**。→ U5 可结案：**风险为零，但不是"stderr 不被断言"这个理由**。
4. 「上游 8 档表来自 web 页、无可核来源」→ **不成立**：`src/optimizer.f90:48-118` 就是同一张表（23/24 一致）。

---

## 2. 攻击面 1：web 调研的可信度（**逐条判断**）

我把被引内容分成"可本机核"和"纯 URL"两类。

### 2.1 可本机核的上游声明 —— **全部通过**

| 文档声明（§） | 引用 | 我的核对 | 判定 |
|---|---|---|---|
| `-o, --opt [LEVEL]`，levels crude..verytight..extreme | `man/xtb.1.adoc:238-241` | `man/xtb.1.adoc:238-241` 逐字相同 | ✅ |
| `--hess` 无数值参数 / `--ohess [LEVEL]` / `--bhess [LEVEL]` | `:243-248`、`:250-251` | 逐字相同；`--metaopt [LEVEL]` 亦在 `:283` | ✅ |
| `--omd` 硬编码 loose | `md.html` | **仓库内 man 也有**：`man/xtb.1.adoc:279-281` "a loose optimization level will be chosen"；且 `main.F90:2199-2201` 硬写 `'-1'` | ✅（且被代码二次佐证） |
| "只选一个 runtyp，首个获胜" NOTE | `man/xtb.1.adoc:205-207` | `:205-206` 逐字相同 | ✅ |
| `$opt engine=rf/lbfgs/inertial`，默认 rf | `man/xcontrol.7.adoc:364` | `:364-366` 逐字相同 | ✅ |
| `$opt optlevel=` 的数字映射且漏 `lax` | `man/xcontrol.7.adoc:374-377` | `:374-377` 逐字相同，**确实漏 lax** | ✅ |
| `$opt hessian=lindh-d2\|lindh\|swart` | `:398` | `:398-399` 相同 | ✅ |
| 默认档 = normal | `optimization.html` | `src/setparam.f90:263-264` `optlev = p_olev_normal`；`optimizer.f90:88` `case default` = normal | ✅ |
| **8 档数值表（Econv/Gconv/Accuracy）** | `optimization.html`（§2.3 表） | 与 `src/optimizer.f90:48-118` **23/24 一致** | ✅（1 处见下） |
| 上游**没有** CLI 级 `--method`/`--engine`/`--optimizer` | "未找到" | `grep -n "--method\|--engine"' src/prog/main.F90` → **0 命中**；全仓库无 `case ('--method')` | ✅ |
| `$set` 是已弃用 legacy 组；CLI 只有 `--define` | `xcontrol.7.adoc:619-621`、`main.F90:1608` | `main.F90:1608` = `case ('--define')` **精确**；弃用句实在 `:626`（`:619-621` 是 LEGACY 标题+引言） | ⚠️ 引用区间偏（LOW-5 同族） |

### 2.2 纯 URL、本机不可核 —— 标 `未验证`，但**无编造迹象**

`commandline.html` 的三条 queue 串（`queue: setup, SP, ANCopt, SP, properties` 等）、`hessian.html`、`scan.html`、`xcontrol.html`、README 无 CLI 内容的断言，我**无法核**（无网络工具）。判断：
- 这些串**格式正确、位置合理**（queue 出现在上游 commandline 页是真实风格），且**没有一条被用来支撑关键设计决策**（关键决策的支撑都落在 man 页与代码上）。
- `optimization.html` 的档位表若真是编造，不可能与 `optimizer.f90` 的 24 个数值对上 23 个（含 `crude=maxcycle=n, acc=3.00` 这类非显然项）。
⇒ **结论：调研可信，未发现编造；`未验证` ≠ 假**。

### 2.3 唯一数值出入（LOW-3）

| 档 | 文档 Gconv | `src/optimizer.f90` |
|---|---|---|
| `lax` | **2 × 10⁻³** | **2.5 × 10⁻³**（`:83`） |

其余 23 项（含 `lax` 的 Econv 2e-5、acc 2.00）**全部一致**。⇒ 要么 web 页与 6.7.1 代码有 1 项出入，要么转写笔误；不影响任何设计决策（`lax`→`loose` 映射与该值无关），但**建议把 §2.3 的权威来源改成 `src/optimizer.f90:48-118`**（`[代码]`，本机可核），把 web 页降为旁证。

### 2.4 我**怀疑**是转写/记忆错误的引用（全部可核，非编造）

见 §11 勘误表：`set_module.f90:1916`（lax 实际 `:1918`）、`:1912`（`case default` 实际 `:1910`）、`main.F90:952-957`（`--ljson` 警告实际 `:983-987`）、`main.F90:3836-3844`（step 换算实际 `:3878-3889`）、`xhelp.f90:717/775`（实际 `:722/:780`）、`geoopt_driver.f90:152-176`（实际 `:148-172`）、§4.1 最小化器解析行。**这些都是 ≥5 行的偏移，属"旧稿行号未随 HEAD 更新"**，不是虚构内容。

---

## 3. 攻击面 2：`--method` 取值域 vs 实现

逐条核对（全部 `file:line`）：

| 文档声明 | 实现 | 判定 |
|---|---|---|
| 6 最小化器 `sd/lbfgs/bfgs/diis/rfo/cg` | `settings.f90:79-84`（枚举，值 1..6）；`case` 在 `:1119/1121/1123/1125/1127/1129`，赋值在 `:1120/1122/1124/1126/1128/1130` | ✅ 存在；**解析行号 5/6 偏移 +2**（LOW-2） |
| 8 鞍点法 `prfo/bprfo/dimer/neb/cineb/autoneb/string/gsm` | `settings.f90:108-119`、`case` 在 `:1302/1304/1306/1308/1310/1312/1314/1316` | ✅ **逐条精确** |
| 4 IRC 法 `gs/hpc/lqa/eulerpc` | `settings.f90:130-133`、`case` 在 `:1236/1238/1240/1242` | ✅ **逐条精确** |
| `ancopt` 原生直通 | `optimizer.f90:122` `subroutine ancopt`（doc 写 `:121` = 注释行）；分派 `geoopt_driver.f90:148-172` | ✅ |
| `auto` = 任务默认 | opt `settings.f90:427` lbfgs；scan `:528` lbfgs；ts `:651` prfo；irc `:837` hpc | ✅ **四条默认值全部精确** |
| 总数 20（不含 auto 19） | 6+8+4+1+1 | ✅ 算术正确 |
| "不存在同名跨任务不同义" | 三个 `*_from_name` 的 `case` 标签集**互不相交** | ✅ 成立（`bfgs`/`dimer`/`gs` 无歧义） |

**没有发现"列了不存在的方法"或"漏了存在的方法"。** 唯一实质问题是**分辨率时序**（H3）与**出口不全**（H5：`$opt engine=lbfgs|inertial` 对应的 L-ANCopt/FIRE 不在取值域里）。

---

## 4. 攻击面 3：后向兼容矩阵完整性（我独立列出的既有调用形式）

### 4.1 我从 `main.F90` 解析分支独立列出的 runtyp 选择入口

`set_runtyp` 的 24 个 runtyp（`setparam.f90:197-218`：prescc/scc/grad/opt/hess/ohess/bhess/md/omd/lopt/path/screen/lscan/modef/mdopt/metaopt/lts/lirc/lvib/vip/vea/vipea/vfukui/vomega）+ 122 个套件拼写 + 92 个原生 case。

### 4.2 对照结果（矩阵 §5.1/§5.2/§5.5 **遗漏**的部分）

| 既有调用形式 | 现状（代码） | 矩阵是否覆盖 | 判定 |
|---|---|---|---|
| `-o <level>`（`--opt` 的短别名） | `main.F90:2153` `case ('-o','--opt')` | **完全没有** | **破坏性变更未入册**（M4） |
| `--opt lax / sloppy / loose / tight / verytight / vtight` | 全接受（`set_module.f90:1912-1927`） | §5.5 只列 normal/crude/extreme | 漏（LOW-6） |
| `--opt -3 / 0 / 3`（数字档） | 接受（`case('crude','-3')` 等） | §3.5 表格提了一句，§5.5 未列 | 漏（LOW-6） |
| `--opt banana` | **静默→normal**（`set_module.f90:1910-1911`） | §8.5 建议改 error，但**未进 §10** | **行为变更未入册**（M4） |
| **`--opt --input <含 $scan 的 xcontrol>`** | **执行 relaxed_scan**（`main.F90:317-318` anyopt → `:952-953`），已注册测试 `xtb/landscape-scan-xcontrol` 断言之 | **完全没有** | **H1** |
| **`--opt` + 周期体系** | 走 `geoopt_driver`，周期 GFN-FF 自动切 `pbc_lbfgs`（`main.F90:933-937`；`geoopt_driver.f90:159-168`） | **完全没有** | **H2** |
| **`--opt` + `$opt optlevel=/engine=/hessian=`** | 原生读 `set%optset%*`（`set_module.f90:1806-1901` → `get_optthr`） | **完全没有** | **H5** |
| `--ohess <level>` + `$scan` | 同上（anyopt 含 ohess） | 未列（同 H1 族） | H1 子项 |
| `--bhess/--omd/--metaopt/--screen` + `$scan` | anyopt 含三者 ⇒ 仍执行 `$scan` | 保持原生 ⇒ ✅ 无问题 | ✅（设计正确） |
| `<任一原生 runtype> + <套件子选项>`（如 `--opt --lscan-fc 0.05`、`--sp --lvib-temp 400`） | **静默丢弃**（`if (set%runtyp /= p_run_lXXX) call set_runtyp(...)` 被锁，`set_module.f90:1031-1038`） | §10 C3/C4 只举了 `--lopt-engine`/`--lvib-temp` 两个例子 | **整类未入册**（M5） |
| `--method bfgs --lopt`（顺序在前） | N/A（新旗标） | §4.6 的 setter 设计**按字面必然出错** | **H3** |
| `--siman/--mdopt/--metadyn/--nat/--bias-input --method X` | N/A | §4.6 表只列 7 个 runtype；规则虽一般化但**消息模板缺失** | INFO |
| `--opt --cycles 50` | 只影响原生 | ✅ 已列（D1） | ✅ |

**矩阵的优点**：`--lopt/--lscan/--lts/--lirc/--lvib` 全套 122 个拼写的现状与动作分类**准确**（我核了 §6.2 全表），"别名而非重命名"的策略与"0 移除"的统计**成立**。

---

## 5. 攻击面 4：`--opt normal` 的语义依据

**判定：有依据，但静默陷阱被低估。**

1. **依据链成立**：`settings.f90:427` 的既有默认就是 `p_landscape_opt_lbfgs`，`xhelp.f90:288-290` 写 "(default lbfgs)" ⇒ 文档"不是新决策"的说法**可核**。实测代价表（§3.3）我**未复算**（`未验证`），但其口径正确（RFO 的缓存掩盖问题被点出，`n_cache_miss` 在 `types/json.f90:356` 真实存在，§13 的复现配方可执行）。
2. **与上游 `normal` 的对齐不成立，且不止文档说的两条**（M1）：
   - 上游每个档位还携带 **SCF 精度 acc**（crude 3.00 → extreme 0.01）与 **maxcycle** 倍数（n, n, 2n, 2n, 3n, 5n, 20n, 20n）（`optimizer.f90:59-113`）；
   - 套件的 `acc` 来自**全局 `set%acc`**（默认 1.0，`setparam.f90:227`；同步点 `main.F90:989` `lset%engine%acc = set%acc`），**与档位无关**（`landscape_engine_control%acc = 1.0`，`settings.f90:325`）；
   - ⇒ `--opt crude` 在新实现下 **SCF 精度从 3.00 变成 1.0（更紧）**、Econv 从 5e-4 变成 5e-6（更紧，文档已说）、maxcycle 从"n"变成 256（`settings.f90:355`，且**没有 CLI**，见 D1）。§10 A2 只写了"判据数目与定义不同"，**漏了这两条数值轴**。
3. **ANCopt 可达性的静默陷阱**：`--method ancopt` 存在（设计正确），但
   - 提示走 **stderr**（§3.4），而 **BC-5 与 §9.2 都要求 grep `stdout`**（M2）——一套自查标准会直接判设计不合格；
   - `-o` 短别名同样改派（M4）——`xtb -o` 的用户连"我用了 `--opt`"都未必意识到；
   - `$opt engine=` 出口丢失（H5）⇒ 用户想回 L-ANCopt/FIRE **没有 CLI 路径**。

---

## 6. 攻击面 5：冲突与错误处理

**没有残留"首选项获胜"设计**（§4.3 规则 2 明确异值报错、§4.6 未改派 runtype 报错、§8.1 双 runtype 报错），且消息**普遍可操作**（点名替代方案）。但有三处结构性问题：

- **H3（时序）**：§4.6 写"实现点：`--method` 的 setter 在 `set%runtyp` 不是套件任务时报 `env%error`"。而 `set%runtyp` 是在**各 case 内部**调用的（`main.F90:2249/2306/2583/3328/...`），解析循环里"先出现的旗标先设 runtyp"。因此 `xtb m.xyz --method bfgs --lopt` 在 `--method` 处 runtyp 仍是默认（sp）→ **必然误报**；`--lopt --method dimer` 才正确。**同一个文件里已经写明了正确做法**：`main.F90:981-982` "The check is here and not in the parser, because the flag and the run type may be given in either order"（`--ljson` 的检查就放在解析之后）；`main.F90:3878-3889` 的 `--lscan-step` Å→bohr 也是**解析后归一**。⇒ 设计必须把 `--method` 的解析推迟到 `parseArguments` 末尾（`main.F90:3891` 之前）或主流程的 runtyp 归一化点。
- **M5（覆盖面）**：`--opt --lscan-fc 0.05` 这类"原生 runtype + 套件子选项"是**最大的一类静默丢弃**（122 个套件子旗标 × 任一先行 runtype 旗标），设计只把 `--lopt-engine`、`--lvib-temp` 两条写进 §10 C3/C4。要么给出通用规则（`set_*` 选项在"该任务不是当前 runtyp"时报错）并声明其爆炸半径，要么明确它不在本次范围。
- **M4（未入册的行为变更）**：`--strict --zzzz` 从 exit 0 变非零（§8.5）、`--opt banana` 从静默 normal 变 error（§8.5）、`-o` 随 `--opt` 改派（§10 A 类未提）。§10 的计数"6 类"**偏低**。

---

## 7. 攻击面 6：单位与命名

| 项 | 判定 |
|---|---|
| `--lirc-step`(bohr·amu^½) vs `--lirc-step-hess`(bohr) | **真解**：新增规范名 `--l*-hess-step` + 旧名别名，同一字段 `engine%hess_step`（`settings.f90:333`）三个写点 `main.F90:2956/3714/3634` 全部核到 | ✅ |
| `--lscan-step`(Å/度) | **未改名**（有意），设计给的可测判据是"help 含单位串 + 运行时回显"（§7.3 硬性要求 + §9.2 `help-unit-annotation`）⇒ **单位"可见"但不在名字里**；§7.3 明确写了"Å（距离）/ 度（角度）"两义，判据可测 | ⚠️ 可接受（属设计取舍，非缺陷） |
| 单位可见性缺口 | 设计**没有**规定 help 里单位串的**统一写法**（`bohr`? `a.u.`? `Å`?），也未规定"回显有效值"的格式；建议在 §9.2 里把 `help-unit-annotation` 的正则白名单写死（`bohr|angstrom|Å|degree|K|cm^-1|amu`），否则该测试会长期假阳性 | LOW |
| 引用行号 | §7.3 说换算在 `main.F90:3836-3844`，**实际 `:3878-3889`**（那个区间是 `--metadyn/--metaopt/--nat`） | LOW-1 |

---

## 8. 攻击面 7：实施计划与测试策略

| 问题 | 判定 |
|---|---|
| 分阶段可独立验收？ | 基本成立（§9.1）；阶段 1 含有意变更（#20/#21/#23/#25 变红）已声明 | ✅ |
| **§9.2 的"强制表格"完整吗？** | **不完整**（M6）：表里只有 `--method`、`--opt→套件`、`--method ancopt`、level 映射、冲突、必填点名、文件契约、`--help` 八行；**§6.3 新旗标**（`--lopt-max-steps`、`--lopt/lscan-hess-step`、`--lopt/lscan-sccacc`、`--lopt/lvib-restart`）**与 7 个别名（旧名=新名等价性）没有任何"证明生效"的测试行**，而阶段 2 的验收正是"每个新增选项都有证明生效的测试" ⇒ **验收标准不可判** | MEDIUM |
| **§9.4 回归风险完整吗？** | **不完整**（M7）：漏了 `xtb/landscape-scan-atom-range`（断言 `outside 1..3`，`CMakeLists.txt:664-669`）与 `xtb/landscape-scan-nstep-missing`（断言 `at least one step is required`，`:658-663`）——而 §8.2 正是要**替换这两条消息**；也漏了 `xtb/landscape-scan-xcontrol`（H1）。文档自己给了三条"实施前强制 grep"（`2>&1`、`--opt `、双 runtype），我已代跑：`2>&1` **0 命中**（但见 §1 证伪点 3：CMake 用同名 ERROR_VARIABLE 合并）；`--opt ` **1 命中 = `landscape_cli_check.py:495`**（即 H1）；双 runtype 组合 **0 命中** | MEDIUM |
| 弃用策略 | ✅ 明确：别名永久、不告警（理由引上游客名惯例）、若将来移除需 ≥2 发布周期 + `[DEPRECATED]` | ✅ |
| 测试可 falsify？ | ✅ 明确要求"先证明突变与被回退逻辑语义等价"（引报告 34 §1 的教训），这是本项目最强的自我约束 | ✅ |
| 未定项 | §12 U4（ANCopt vs lbfgs 末几何差）**现在两条实现都在手上**（`--opt` 与 `--lopt` 同一二进制），属"5 分钟可测"，不该与 U1/U2/U3 并列 | LOW-7 |

---

## 9. 攻击面 8：破坏性变更清单的诚实性与完整性

**诚实**：明确否定旧稿"1 条"，改为 A/B/C/D 四类 6+1 条，并声明 B1–B4 是**独立于"数值变了"的第二类破坏**——这是本文档质量最高的部分。

**不完整（逐条缺口）**：

| 缺口 | 类型 | 证据 | 严重度 |
|---|---|---|---|
| `$scan` 执行能力丢失 + 自指错误消息 + 已注册测试变红 | 能力/测试 | `main.F90:478-510`（注释明写 `$scan` 由 `--opt` 执行）、`:317-318`、`:952-953`；`test/unit/CMakeLists.txt:3082-3088`、`landscape_cli_check.py:447-503` | **HIGH** |
| 周期体系 `--opt` 从"能跑"变"中止" | 能力 | `landscape_driver.f90:73-77`（套件硬报错）；`main.F90:933-937`、`geoopt_driver.f90:159-168`（原生 pbc_lbfgs） | **HIGH** |
| xcontrol `$opt` 键（engine/optlevel/hessian/maxcycle/microcycle/hlow/maxdispl…）静默失效 | 静默 | 套件对 `set%optset` **零引用**（只有 `settings.f90:422` 一句注释）；写点 `set_module.f90:1806-1901`；读点 `optimizer.f90:48-118` | **HIGH** |
| 每档 SCF 精度 acc / maxcycle 不对齐 | 数值 | `optimizer.f90:59-113` vs `settings.f90:325` + `main.F90:989` + `settings.f90:355` | MEDIUM |
| `-o` 随 `--opt` 改派 | 语法/语义 | `main.F90:2153` | MEDIUM |
| `--strict`/`--opt banana` 变严格 | 语法 | `main.F90:1639`+`:607`；`set_module.f90:1910-1911` | MEDIUM |
| `.xtboptok/.xtbopt.log` 已由 B1/B2 覆盖 ✓、`compliance.dat` ✓ | — | — | ✅ |
| **BC-3 的"满足"表述** | 自相矛盾 | §1.2 行 71 说"对 BC-1..BC-3、BC-5 满足"，而 §10 B1–B4 恰恰让 `--opt` 的文件集合**减少 3 个** | MEDIUM |

---

## 10. 攻击面 9：遗漏的能力（对照 W1 订正后的 G 表）

W1 订正后：**N=15（G1–G15）+ 永久 2（P2,P3）+ 环境 4（E1–E4）**。文档覆盖情况：

| W1 项 | 文档覆盖 | 判定 |
|---|---|---|
| G1 `--lsp` | §11 #6 明确"不做"并给理由 | ✅ 明说"不暴露" |
| G2 `--ohess` | §3.6/§3.7 改派 + §5.4 契约 | ✅ |
| G3–G7 bhess/metaopt/path/modef/screen | §3.7 表逐条"套件无等价实现 ⇒ 保持原生" + §4.6 报错 | ✅ |
| G8 vip/vea/vipea/vfukui/vomega | §5.1 #17 只列"不变"；§4.6 的 MD 消息覆盖不到这 5 个 | ⚠️ 未明说"套件无 property 层 ⇒ 无法经 CLI 暴露" |
| **G9/G10 PBC** | **全文档零提及** | **HIGH（H2）** |
| G11 输出契约 | §3.2/§10 B1–B4 覆盖 `xtboptok/xtbopt.log/xtblast.xyz/compliance.dat`；漏 `.xtbtmpmode`（但 modef 保持原生 ⇒ 无实际影响） | ⚠️ LOW |
| **G12 FIRE/inertial、动态 SCC 精度、模型 Hessian 变体（Swart/GFNFF）、average_conv** | **零提及**；且 §4.1 取值域没有 `lancopt`/`fire`，§3.7 只保一个 `ancopt` 出口 ⇒ **FIRE/L-ANCopt 失去 CLI 可达路径** | **HIGH（H5 子项）** |
| **G13 `$scan` 块执行** | **零提及**（只在 §3.6 作为"缺陷类别"举例）；而 C 方案把 `--opt` 这条 W1 明确记录的**唯一执行路径也拿掉**了 | **HIGH（H1）** |
| G14 DMF | 零提及（D2 排除，可接受，但未复述） | INFO |
| **G15 属性/分析层** | **零提及**；未明说"套件无 property 层 ⇒ 这些能力不能经 `--method`/套件 CLI 暴露" | MEDIUM |
| P2/P3/E1–E4 | 不适用（非 CLI 面） | ✅ |

---

## 11. 勘误表（可核，全部低风险）

| # | 文档处 | 文档值 | 实测值 | 级别 |
|---|---|---|---|---|
| 1 | §2.3、§8.5 | `set_module.f90:1916`（lax） | **1918**（`case('lax')`；1916 是 `case('loose','-1')`） | LOW |
| 2 | §8.5 | `set_module.f90:1912`（case default） | **1910** | LOW |
| 3 | §5.3 | `main.F90:952-957`（`--ljson` 警告） | **983-987**（952-955 是 `$scan`/`relaxed_scan` 块） | LOW |
| 4 | §7.3 | `main.F90:3836-3844`（step 换算） | **3878-3889** | LOW |
| 5 | §6.4、§8.6 | `xhelp.f90:775`（`-s/--silent`）、`:717`（`--ithr`） | **780**、**722**（`--xparam` 的 170 ✓） | LOW |
| 6 | §2.4 | `geoopt_driver.f90:152-176` | **148-172**（`case(p_engine_rf)`=149） | LOW |
| 7 | §4.1 | 最小化器"解析点" 1119/1125/1127/1129/1131/1123 | **1119/1123/1125/1127/1129/1121**（偏移 +2） | LOW |
| 8 | §10 B4 | "原生 `--ohess` 跑 `main_freq` → 写 `compliance.dat`" | `compliance_driver` 只被 **`src/hessian.F90:331-332`（`numhess`）** 调用；`main_freq` 不写它（结论"套件不写"仍成立） | LOW |
| 9 | §10 B2 | 引号内 "a trajectory … is written to the file xtbopt.log" | `man/xtb.1.adoc:434-437` 原文是 "contains all structures obtained in the geometry optimization … in a XMOL formatted trajectory"（**文件名与语义正确，引文非逐字**）；man 还列 `xtbopt.coord`/`xtbhess.coord`，契约表未收 | LOW |
| 10 | §2.5 | `xcontrol.7.adoc:619-621` 写 "This feature will be deprecated" | 该句在 **:626**（619-621 是 LEGACY 标题与引言） | LOW |
| 11 | §3.5 | `lax` Gconv 2e-3 | `optimizer.f90:83` = **2.5e-3** | LOW-3 |
| 12 | §3.5 备注 | `lax → loose`"上游独有之档" | lax 的阈值（2e-5 / 2.5e-3）位于 loose（5e-5 / 4e-3）与 normal（5e-6 / 1e-3）**之间**（`optimizer.f90:73-86` 注释亦写 "between loose and normal"）⇒ 映射到 `loose` 会**比上游更松**，应写明 | LOW |

---

## 12. 需运行验证清单（所有命令必须 `OMP_NUM_THREADS=1`，用 `/tmp/xtb-w2/build/xtb`；**本评审无 shell，全部未执行**）

| # | 命令 | 要证伪/证实的结论 |
|---|---|---|
| V1 | `xtb h2o.xyz --gfn2 --opt --input <含 $scan 的 inp>` | **H1 的核心事实**：现状是否 RELAXED SCAN + `xtbscan.log`（应然：是）。同时跑 `--gfn2 --lopt --input <同文件>` 应得非零退出 |
| V2 | `ctest --test-dir ... -R 'landscape-scan-xcontrol|landscape-scan-atom-range|landscape-scan-nstep-missing'` | V1 的实现基线；也为 M7 的两条消息断言取基线 |
| V3 | 周期体系（GFN-FF、`--opt`、e.g. 一个 3 维周期 fixture） | **H2**：现状是否收敛并走 `pbc_lbfgs`；同体系 `--lopt` 应报 `landscape tasks do not support periodic boundary conditions yet` |
| V4 | `--opt --input '<$opt optlevel=tight / engine=lbfgs / hessian=swart>'` | **H5**：`$opt` 键确实改变原生结果（`get_optthr`）；反向证明 C 之后它们成为死键 |
| V5 | 参照二进制 `edcfbbe`：`--opt` × {crude,sloppy,loose,lax,normal,tight,verytight,vtight,3,-3,banana} | §2.3 的 `[实测]` 表（含 `banana` 静默 normal） |
| V6 | §3.3 的 6 引擎 × 3 分子 `n_cache_miss`（配方见 §13，`landscape_opt.json` 的 `counters`） | 决定 `--opt` 默认引擎（建议另加 ≥60 原子的用例，闭合 §12 U11） |
| V7 | `--opt --lopt-engine bfgs`、`--lscan-method cg --lts`、`--sp --lvib-temp 400` | 静默丢弃三类（M5 的爆炸半径） |
| V8 | `grep -rn -- '--opt ' test/ unit/`（我已代跑：**1 命中**）、`grep -rn "2>&1" test/unit/`（**0 命中**，但 CMake 用同名 `ERROR_VARIABLE` 合并） | §9.4 的三条强制 grep（U5 可直接结案） |
| V9 | 实现阶段 1/2 后：`ctest -R landscape` 与 `ctest -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'` | BC-1..BC-4 的回归判据（**绝不跑全量**） |

---

## 13. 需向用户确认清单

| # | 问题 | 为什么必须由用户定 |
|---|---|---|
| Q1 | `--opt` 改派（C）是否知情接受**三项能力回退**：周期体系、xcontrol `$scan` 块、xcontrol `$opt engine=lbfgs\|inertial`（L-ANCopt/FIRE）？ | 用户的原始要求是"依然是 `xtb --opt normal`"，但未被告知这三项；若不可接受 ⇒ 需要 D 方案（两阶段）或给 `--opt` 加"周期/含 `$scan` 时自动回落原生 + NOTICE" |
| Q2 | `--method` 的出口集合是否要扩到 `ancopt`（rf）+ `lancopt`（lbfgs）+ `fire`（inertial）三个原生引擎（对齐 `$opt engine=`）？ | 决定 G12 是否成为能力回退（H5） |
| Q3 | `e_tol` 是否随档位变化（§3.5 未定 ii / U2） | 会把 `--lopt-level` 的语义改动变成第 7 条破坏性变更 |
| Q4 | `--cycles` 在套件 runtyp 下映射还是报错（D1/U6） | 二者都是行为变更，必须选一 |
| Q5 | `--strict`、原生未知枚举（`--opt banana`）是否真的改成 error（U8） | 会影响所有依赖"容错+exit 0"的既有脚本 |
| Q6 | BC-3 的缓解（套件补写 `.xtboptok`/`xtbopt.log`/`compliance.dat`）是否**强制**（U7） | 强制 ⇒ BC-3 成立；不强制 ⇒ BC-3 必须以"--opt/--ohess 例外"重写（M2） |
| Q7 | `[NOTICE]` 走 stderr 还是 stdout（BC-5 的判据要求 stdout） | 二者只能选一，改动测试写法 |
| Q8 | 阶段 3 之前是否需要"过渡期"（保留原生 `--opt` 一个周期 + `[DEPRECATED]`），还是立即切换（§11 #11） | 直接决定 H1/H2 的爆炸半径 |

---

## 14. 裁决与回答

**结论：有条件接受（Conditional Accept）。CRITICAL 0 / HIGH 5 / MEDIUM 8 / LOW 7 / INFO 4。**

**「这份设计能否作为实施依据？」**
- **阶段 1（§8.1/8.2/8.4/8.5）+ 阶段 2（§4 取值域与别名、§6.2 全表、§7 命名/单位）**：**可以**——但必须先闭合 **M2**（BC 判据重写）、**M4**（把 §8.5 的两条行为变更与 `-o` 补进破坏/变更册）、**M5**（"原生 runtype + 套件子选项"通用规则与消息模板）、**M6**（§9.2 表格补全 §6.3 新旗标与 7 个别名）、**M7**（§9.4 补三条消息断言测试）；并落 **H3**（`--method` 改为解析后归一，参照 `main.F90:981-982`/`:3878-3889`）。
- **阶段 3（`--opt`/`--ohess` 改派）**：**不可以**，直到 **H1（`$scan`/G13）、H2（周期/G9,G10）、H5（xcontrol `$opt` 键 + L-ANCopt/FIRE/G12）、M1（acc/maxcycle 对齐）、M8（runtyp 机制定义）** 全部闭合，并回答 Q1–Q8。H1 尤其硬：它不只是一个未入册的破坏项，而是**会让已注册的 `xtb/landscape-scan-xcontrol` 变红**，并让 `main.F90:505-507` 的错误消息（"use --opt to run it"）变成自指。
- **文档本身的质量**：引用可信（**未发现编造**）、§6.2 全表精确、"绝不静默"原则的落地思路（错误可操作、变响亮清单、falsifiable 测试）在本项目中属上乘；缺陷集中在**影响面分析的完备性**，不是方向错误。**修订成本远低于重写**：预计 §3/§9/§10 增补 5 个小节 + §1.2 判据重写即可。