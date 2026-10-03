# 11 — CLI 全面重设计（保持后向兼容）

> **性质**：**设计，不是实现**。本文件是本次唯一产出。**未改动 `src/` 与 `test/` 任何一行**
> （`git status` 只多出本文件与既有 W0/W1 未跟踪报告，见 §13）。
> **仓库**：`/home/owenchan/work_path/coding/fortran/xtb`，HEAD `bdd8eb8`（含 W0）。
> **本构建**：`/tmp/xtb-w2/build/xtb`（`-O2 -DNDEBUG`，`WITH_TBLITE=OFF WITH_CPCMX=OFF`，
> 独立目录，未触碰 `/tmp/xtb-w0/build`）。
> **参照二进制**：`/home/owenchan/programs/xtb/bin/xtb`（6.7.1 `edcfbbe`，静态，无 landscape）。
> **纪律**：所有 xtb 运行 `OMP_NUM_THREADS=1`；未跑全量 ctest；未修改生产代码/测试。
> **证据类型**：`[实测]` = 真跑了二进制并留原文；`[代码]` = 读代码 + `file:line`；
> `[文档]` = 上游文档/ man page + URL/行号；`[未验证]` = 本机无法判定。
>
> **本轮的上级决策**（已由用户确认，见 §3.0）：`--opt <level>` 采用**方案 C**；
> `--ohess` 也改派到套件 `opt + vib` 链；`--bhess/--metaopt/--path/--modef/--screen` 保持原生。
>
> **R1 修订**（依据 `12-w2-review.md` + 用户四项决策）：第 1 轮就地修订；修订记录 R1..R20，
> 复核 12 逐条处置表见 **§14**，阶段 3 的守卫/测试规格见 **§14.5/§14.6**。
>
> **R2 修复轮（R21..R28，依据 `14-w2-review-round2.md`）**：第 2 轮复核 = **有条件接受**
> （CRITICAL 0 / HIGH 2 / MEDIUM 4 / LOW 6 / INFO 2）。本轮闭合：**H-1**（§4.7 重写为**两段解析尾归一** + 逐行代入证明）、
> **H-2**（§3.11 改为**单一 `landscape_native_engine` 标志**，覆盖 4 个原生出口）、**M-1..M-4**、**L-1..L-6**、**I-1/I-2**；
> 逐条处置见 **§14.7**，新增/复跑的实测见 **§13c**，阶段阻塞状态见 **`13-*.md`**。

---

## 修订记录（R1..R28）

> 本节只说明"改了什么、依据是什么"。每条都在正文里有对应改动点。
> 证据类型沿用全文：`[实测]` / `[代码]` / `[文档]` / `[未验证]`。

| R# | 改动 | 依据 | 正文位置 |
|---|---|---|---|
| R1 | **决策 1**：三类"原生专属"情形（`$scan`、周期体系、xcontrol `$opt` 键）从"改派后静默丢失"改为**响亮报错 + 指向 `--method ancopt`**；给出检测点/错误文本/退出码/测试 | 用户决策 1 | §3.8（新）、§5.5、§10 A/B/H 类 |
| R2 | **订正复核子结论**：复核"`--opt` 改派会打破已注册测试 `xtb/landscape-scan-xcontrol`"**是正确的**；**父会话此前"该测试不会因此失败"的核实被证伪并撤回**（它只读了 `check_scanblock` 的 docstring，未读函数体 492-503 段） | `test/unit/landscape_cli_check.py:447-503`、`:20`、`test/unit/CMakeLists.txt:3082-3088`（file:line） | §14.1、§14.5 |
| R3 | **自指引导清理**：`main.F90:505-508` 与 `xhelp.f90:285-286` 都把 `--opt` 当成"执行 `$scan` 的入口"，改派后自指；列成表并在阶段 3 改写 | `grep` 全仓库 + file:line | §3.8(a)、§14.6 |
| R4 | **决策 2**：套件按上游语义补写 4 个遗留文件（`.xtboptok` / `xtbopt.log` / `xtblast.xyz` / `compliance.dat`）⇒ **B 类破坏清零**；给出逐文件语义、上游对照 `file:line`、`--namespace` 交互、测试 | 用户决策 2 | §3.9（新）、§10 B 类、§14.3 |
| R5 | **决策 3**：`--opt <level>` 的档位同时驱动 **优化阈值 + SCF 精度 + 最大步数**（对齐上游 `get_optthr`）；`--lopt-level` 的 `e_tol`/`acc` 语义随之改变（列为破坏性变更 + 影响清单） | 用户决策 3；`src/optimizer.f90:48-119` | §3.5（改写）、§3.10（新）、§10 E 类 |
| R6 | **决策 4**：C1–C4 四处静默丢弃改为**响亮错误**（`--lopt --lscan`、`--opt --lopt`、`--lts --lopt-engine bfgs`、`--hess --lvib-temp`），逐条给检测点/文本/退出码/测试 | 用户决策 4 | §8.7（新）、§10 C 类、§14.2 |
| R7 | **H3**：`--method` 的解析时序改为**解析后归一**（`parseArguments` 末尾），给出与 `set_runtyp` 锁共存的机制 | 复核 H3；`main.F90:981-982`、`:3878-3889` | §4.6（改写）、§4.7（新） |
| R8 | **H4**：xcontrol `$opt` 键在套件下静默失效 → 进入 R1 的守卫 | 复核 H4；`set_module.f90:797,1777-1902,2845-2860` | §3.8(d) |
| R9 | **H5**：G12（FIRE/inertial、动态 SCC 精度、模型 Hessian 变体、`average_conv`）失去 CLI 可达路径 → 取值域与出口设计 | 复核 H5；`set_module.f90:1888-1892`、`optimizer.f90:832-838` | §4.1（新增出口表）、§4.8（新） |
| R10 | **M1**：档位携带的 `acc`/`maxcycle` 不对齐 —— 并入 R5 | 复核 M1 | §3.5、§3.10 |
| R11 | **M2**：BC-3 与设计正文"满足"表述自相矛盾 → 统一；`[NOTICE]` 的投递改为 **stdout**（`env%warning`/`env%error` 实测就在 stdout） | 复核 M2；`src/type/environment.f90:249-260,266-294` | §1.2、§3.4（改写） |
| R12 | **M4**：`-o`、`--strict --zzzz`、`--opt banana` 三条未入册的行为变更补进清单 | 复核 M4 | §10 F 类、§5.5 |
| R13 | **M5**："原生 runtype + 套件子选项"整类的通用规则 + 消息模板 | 复核 M5 | §8.7(b)、§14.2 |
| R14 | **M6**：§9.2 强制表格补全 §6.3 全部新旗标与 7 个别名 | 复核 M6 | §9.2 |
| R15 | **M7**：§9.4 回归风险补 `xtb/landscape-scan-atom-range`、`-nstep-missing`、`-scan-xcontrol` | 复核 M7；`CMakeLists.txt:658-669,3082-3088` | §9.4 |
| R16 | **M8**："runtyp 机制定义"——`--opt`/`--ohess` 与套件任务的身份关系（不合并 runtyp） | 复核 M8；`setparam.f90:197-218` | §3.11（新） |
| R17 | **行号勘误**：§11 的 12 行可核勘误**全部应用** | 复核 §11 | 正文各点 |
| R18 | **过期事实**：`--lvib` 无条件覆盖 `$thermo` 的陈述已过期（W0 已修为"显式 CLI > xcontrol > 内置默认"） | `src/landscape/vib/thermo.f90:32-35,51-53` | §8.3 D5、§8.6 |
| R19 | **破坏性清单更新**：B 类清零；A/C/D 类补 H1/H2/H4/H5 三条"响亮拒绝"；新增 E/F 类 | 决策 1-4 + 复核 | §10 |
| R20 | 新增 **复核 12 处置表**（H1–H5 / M1–M8 / LOW×7+LOW-units / INFO×4 逐条） | 复核全篇 | §14 |
| **R21** | **H-1 闭合（重写 §4.7）**：`--method` 的解析尾归一改为**先识别 4 个原生出口**（`ancopt\|rf`、`lancopt\|l-ancopt`、`fire\|inertial`、`pbc_lbfgs`）再走套件 setter 分发；`--method` **从不**映射 runtyp。给出**逐行代入现有实现**的证明（`settings.f90:1112-1135`、`set_module.f90:1888-1891`、`geoopt_driver.f90:148-171`），4 个出口均不落 `default`/`env%error` | 复核 14 H-1 | §4.7（重写）、§4.8、§3.11 |
| **R22** | **H-2 闭合**：身份谓词由 `landscape_native_ancopt::logical` 改为**单一** `landscape_native_engine::integer`（取值域 = `setparam.f90:77-80` 的 4 个 `p_engine_*`，0 = 套件），覆盖**全部 4 个原生出口**；§3.8 的三条守卫统一读 `landscape_is_suite_run` | 复核 14 H-2 | §3.11（重写）、§3.8(a)(b)(c) |
| **R23** | **M-2 入册**：§3.8(c) 的 `$opt` 守卫作用域（**全部**套件 run type）登记为**新增破坏性变更 C7**；破坏性计数 **15 → 16**；附爆炸半径实测（`grep -rn '\$opt' test/unit/` = 0 命中；`--lopt --input <$opt optlevel=tight>` 今天 exit 0 且 0 行提示）与"为什么收窄到 `--opt` 不如全量守卫"的论证 | 复核 14 M-2 | §10 C7、§0、§3.6、§3.8(c)、§9.4 |
| **R24** | **M-3 闭合**：抑制既有原生 `if (anyopt)` 分支的具体位置/条件（`main.F90:931` → `if (anyopt .and. landscape_native_engine /= 0)`）、`--ohess` 的 opt→vib 链判据、以及"只跑一次"的 CLI 测试（stdout 判别 token，**本轮实测**）| 复核 14 M-3；`main.F90:317,931,1277,1283` | §3.11、§9.2、§9.4 |
| **R25** | **M-4 闭合**：§8.4 的 `--help` 双向检查拆成**集合 S（套件旗标：阶段 1 门槛，差集必须 = 0）**与**集合 N（原生：已知清单，§8.6 阶段 4 收口）**，并写明抽取规则依赖（本轮实测 30/4 与 34/5 两种口径） | 复核 14 M-4；`2-*.md:294-309` | §8.4、§8.6、§9.1 |
| **R26** | **M-1 真修 + 留痕**：§5.4 按 R4 清零改写（加"R4 后（§3.9）"列 + 重写结论），不再与 §1.2 BC-3/§10 B 矛盾；**并留痕**：`13-*.md §2` 此前声称"§5.4 加 R4 后补齐"是**不可核的过度声称**（这句 R26 里"0 命中"的计数本身已**过期**——R29..R35 的留痕段落把该字样带入正文：**追加前实测 4 处**：`11:58,1495,2392,2420`；追加后该原始计数继续自增，正式判据见 §16.4 的"未标记命中 = 0"） | 复核 14 M-1；`11-*.md:1175-1177` | §5.4、§14.7、`13-*.md §4` |
| **R29** | **HIGH-1 闭合（第 3 轮复核）**：`--ohess`(套件) 会**跑两遍** Hessian/频率。新增**唯一**判据 `landscape_native_hessian_path(runtyp, native_engine)`（纯函数，**不新增状态位**）并逐个覆盖三个触发点：T1 `main.F90:1156`（块内 `:1170 call numhess`）、T2 `:1282-1285`（`call main_freq`）改为读该谓词；T3 `anyhess`（`:270`）**判据不变**，改由套件 vib 链**填满 `fres`**（桥）——因为把 `anyhess` 置假会静默丢掉 `--ohess` stdout 的 `TOTAL ENTHALPY`/`TOTAL FREE ENERGY` 两行（**实测**：原生 `--ohess` 有、套件 `--lvib` 无）。另把同类读者 `:1310-1320`（原生 `xtbopt.xyz` 二次写）与 `:4065-4068`（计时标签）一并纳入。给出**逐行代入自证表**（套件 `--ohess` 三处不触发；`--ohess --method ancopt` 三处仍触发）与 4 条 CLI 测试（判别 token 本轮实测） | 复核 15 HIGH-1；`main.F90:270,1156,1170,1276-1285,1300-1324,4065-4071`、`src/type/data.F90:105-129`、`src/landscape/tasks/vib.f90:155` | §3.11（新增 §3.11.1）、§4.7.1、§9.2、§16.1 |
| **R30** | **MEDIUM-1 闭合**：`landscape_native_engine` 在未给 `--method` 的运行里读到**未定义值**（`intent(out)` 只在 `if (allocated(...))` 内赋值）⇒ 在 `parseArguments` 的 **flag 循环之前**（`main.F90:1574` `call args%nextFlag(flag)` 的前一行）无条件 `landscape_native_engine = 0`，并保留声明初值；新增**新状态位初值表**（变量名 / 声明处 / 初值 / 何时被写）覆盖 `xcontrol_supplied`、`acc_was_set`、`fres`、`lres%vib` | 复核 15 MEDIUM-1；`main.F90:1493-1505,1574` | §4.7（第 2 段）、§3.11.2 |
| **R31** | **MEDIUM-2 闭合**：`13-*.md §6` 的自检是**假的**（写 0，实测非 0）。自检改为"命令 / 期望 / 实际"三列可核形式并留痕"此前的 0 是错的"；**同时订正复核的计数**：该字样的 `grep -c` 在**追加 §16/§17 之前**实测 **4**（复核的 3 漏了 `11:2392`），追加后原始计数自增 ⇒ 正式判据改为"**未标记命中 = 0**"（§16.4 第 3/5/6/7 行） | `grep -c` 本轮实测（§16.4） | `13-*.md §6`、§15、§16.4 |
| **R32** | **MEDIUM-3 闭合**：R22 改写留下的**作废机制残留** 3 处（`11:2183` §12 U1、`11:2322` §14.2 M8 行、`13:18` R16 行）由"两个逻辑标志"改为**单一 `landscape_native_engine`（0 = 套件）**；搜索命令与命中数写进 §16.5 | 复核 15 MEDIUM-3；`grep -n "两个逻辑标志"` | §12 U1、§14.2、`13-*.md §1` |
| **R33** | **LOW-1..LOW-7 逐条处置**（§16.6）：L-1 原生拼写 **8→7**、总数 **26→25**（4 处）；L-2 `:1282/:1287`→`:1279/:1284`；L-3 `n>50 0`→`n > 500`；L-4 读点表补 5 行 + `(b)/(c)` 位置措辞统一 + `:1310-1320`/`:4065-4068` 入抑制集合 + `:1276-1280` **保留**（附实测理由）；L-5 补 level 桥实现点（`set%optset%optlev`，`set_module.f90:1811`）；L-6 措辞改"套件分派路径不触发 `:321/:326` 的 terminate"；L-7 `>500` fixture 改 **GFN-FF 501 原子非周期** | 复核 15 §7；本轮 `grep -n` file:line | §4.1、§3.5、§3.7、§3.11、§4.7.1、§16.6 |
| **R34** | **U15 / U16 定案**：U15 = **(b) 打 `[WARNING]`**（实现点 `set_module.f90:1884-1886` 的 `.not.allocated` 守卫分支；它只在 `set%opt_engine` 已被显式赋值时命中，即只可能在 `--method <native>` 之后 ⇒ 不触碰任何既有原生运行）；U16 = **允许**（原生行为逐字不变、不加警告，4 条理由见 §16.7） | 复核 15 §7 INFO-1/INFO-2 + §10 确认项 3；`set_module.f90:1884-1893` | §12 U15/U16、§3.8、§16.7 |
| **R35** | **新增 §17「阶段 1 工作清单」**（5 组可直接执行的条目，每条含 file:line / 验收方式 / 需要的测试），并把阶段阻塞状态更新为**四态**（阶段 1 / 2 / 3-`--opt` / 3-`--ohess`）；`13-*.md §4` 同步为 4 行 | 复核 15 §11 + 本轮设计 | §17、`13-*.md §4` |
| **R27** | **决策 3 的两个缺口**：(a) `--lopt-level`/`--lscan-level`/`--lts-level`/`--lirc-level` **不**接收上游 8 档名（只 5 个套件名，理由给出），上游名仅经 `--opt`/`--ohess` 桥接；(b) 点出 `--acc` 优先级的实现处 `main.F90:996/1013/1033/1062/1078` 是**无条件** `engine%acc = set%acc`，R5 的"显式 `--acc` > 档位派生"要求改为"仅显式 `--acc` 时同步" | 复核 14 §11、L-4/L-5；`settings.f90:1497-1510`、`main.F90:1665` | §3.5、§3.10b、§6.2 #4 |
| **R28** | **LOW/INFO 逐条处置**（进 §14.7）：L-1（§5.1 #21 措辞→error）、L-2（6 处行号）、L-3（补 `optimizer.f90:801` 的逐帧写点）、L-6（G15 单列）、I-2（编号重建规则）；**另发现并修正** §4.1/§4.8 的两处**文件误归属**（`l_ancopt`/`fire` 实在 `relaxation_engine.f90:400/131`，旧稿写 `optimizer.f90`） | 复核 14 §4/§5；本轮 `grep -n` file:line | §14.7、§4.1、§3.9 |

> **复核编号与计数的不一致（本轮记录）**：复核声明 HIGH 5 / MEDIUM 8 / LOW 7 / INFO 4，但正文只显式编号了
> H1/H2/H3/H5、M1/M2/M4/M5/M6/M7/M8、LOW-1..LOW-7、2 条 INFO。**§14 按内容补足到与计数一致**，
> 并在"复核标签"列注明"正文未编号（本修订按内容补 ID）"，不静默吞掉任何一条。

---

## 0. 摘要（先看这段）

| 主题 | 结论 |
|---|---|
| 上游 CLI 形式 | `--opt [LEVEL]` **接受 level 关键字**（`man/xtb.1.adoc:238-241`）；8 个档位定义见 `optimization.html`（§2.3） |
| 上游方法选择 | **没有** CLI 级 `--method`；方法在 `$opt engine=` 里（`rf|lbfgs|inertial`，`man/xcontrol.7.adoc:364`） |
| 上游命名惯例 | 逗号别名一行（`-o, --opt`）、`--[no]copy`/`--[no]restart` 成对、`--[o]hess`/`--[o]md` 复合 runtype 前缀、`-I/--input` |
| 未知参数 | **warning 不 error**：`-1- ... Unknown option 'X' provided`，**exit 0**（`main.F90:1583`）；`--strict` **也拦不住**（§2.6） |
| 冲突参数 | **首次获胜 + 静默**：`set_runtyp` 的锁消息**从未到达用户**（`set_module.f90:1036`） |
| 套件参数总量 | **122 个拼写**（121 个 case 标签），0 个未文档化（W0 审计已核） |
| 统一选择器 | `--method <name>`，取值域 = 6 最小化 + 8 鞍点 + 4 IRC（逐条 `file:line`，§4.1） |
| `--opt` 语义 | **方案 C**：默认套件优化器（实测依据 → lbfgs，§3.3）；`--method ancopt` 是出口；**明确列入破坏性变更** |
| 破坏性变更 | **C 下逐条核实**：原为 6 类，**R1/R4 修订后 = A 类 3 条 + B 类 0 条（清零）+ C 类 6 条 + D 类 1 条 + E 类 1 条 + F 类 3 条**，另加"阶段 3 测试层后果"1 条（`xtb/landscape-scan-xcontrol`），见 §10。**不是 1 条**。**R23（第 2 轮复核）后 = A 3 + B 0 + C 7 + D 1 + E 1 + F 3 + G 1 = 16 条** |
| 原生引擎出口（R21/R22） | `--method ancopt\|rf\|lancopt\|l-ancopt\|fire\|inertial\|pbc_lbfgs` = 4 个**原生**出口，仅在 `--opt`/`--ohess` 下合法；由**单一** `landscape_native_engine` 标志（取值 = `p_engine_rf/lbfgs/inertial/pbc_lbfgs`）驱动，谓词与三条守卫全读它，见 §3.11/§4.7/§4.8 |
| 原生专属情形（R1） | **三类**（`$scan`、周期体系、xcontrol `$opt` 键）改派后**响亮报错**（`env%error`，exit 1），文本指向 `--method ancopt` / `--lscan`；逐条给检测点，见 §3.8 |
| 遗留文件契约（R4） | 套件**按上游语义补写全部 4 个**：`.xtboptok`（仅收敛时）/ `xtbopt.log`（非隐藏名）/ `xtblast.xyz`（失败时）/ `compliance.dat` ⇒ **B 类清零**，见 §3.9 |
| 档位语义（R5） | `--opt <level>` 与 `--lopt-level` 的档位同时驱动 **阈值 + `e_tol` + SCF 精度 `acc` + `max_steps`**（对齐上游 `get_optthr`）；`--cycles` 映射到 `max_steps`，见 §3.5/§3.10 |
| `--method` 时序（R7） | **解析后归一**（`parseArguments` 末尾，与 `--ljson`/`--lscan-step` 同一位置），与 `set_runtyp` 的"首个 runtyp 锁"无关，见 §4.7 |
| 复核结论订正（R2） | 复核"`--opt` 改派打破 `xtb/landscape-scan-xcontrol`"**正确**；父会话此前"不会失败"的核实**被证伪并撤回**（留痕），见 §14.1 |
| 命名一致性 | 0 个破坏性重命名；全部用别名统一（`--l*-hess-step`、`--method`），§7 |
| 可先落地 | 冲突检测、必填报错点名、危险默认回显、`--help` 双向检查（§8），**不依赖 `--opt` 决策** |

**用户原话（验收标准）**：
> 「全面重设计，派遣子代理 web search 网络 xtb 文档的原有形式，再配合我们的套件。
> 一个例子是 `xtb --opt normal`，会启用 ANCopt；假如换成我们自己的套件，
> 我希望依然是 `xtb --opt normal`（此时应加载默认的 Fortran 套件中的优化器），
> 但是假如要启用方法，就应该是 `--method bfgs` 这样的符合直觉的形式，
> **在不破坏原有 cli 的基础上增加我们的内容**。」

---

## 1. 设计目标与约束

### 1.1 目标

1. **上游形式优先**：凡上游已有惯例（level 关键字、`--[no]x`、逗号别名、`$opt engine=`），
   我们的新增一律**沿用同一形式**，不发明第二套语法。
2. **一个直觉的选择器**：`--method <name>` 让"用哪个算法"成为一等问题，且名字 = 算法名。
3. **维度正交**：**收敛档位**（level）与**算法选择**（method）是两个独立维度，可以组合
   （见 §3.1 的正交性论证）——这正是「`--opt normal --method bfgs` 不别扭」的原因。
4. **绝不静默**（项目既有原则）：未知参数、未知枚举值、冲突组合、危险默认、被忽略的选项，
   全部要有**用户可见**的输出（warning 或 error）。
5. **单位必须标注**：长度/角度/弧长的单位必须出现在 `--help`、运行回显或名字里。
6. **默认值必须有依据**：每个默认值附实测、文献或上游惯例（§3.3、§3.5）。

### 1.2 「不破坏原有 CLI」的可验证定义

用户要求"不破坏原有 cli"，但它必须可测，否则无法验收。本设计把它切成 5 条**可判定的判据**：

| ID | 判据 | 判据的验证手段 |
|---|---|---|
| BC-1 | **语法兼容**：任何既有命令行仍然解析成功（不出现 `Unknown option`） | 用一份"既有调用清单"（§5.1）逐个跑，断言 `Unknown option` 计数 = 0 |
| BC-2 | **旗标不消失**：没有任何既有旗标被移除或改拼写 | `git grep` 旧拼写仍命中 `main.F90` 的 `case`；`--help` 里仍在 |
| BC-3 | **输出文件名不变**：默认（无 `--namespace`）下写出的文件集合**不减少**。**R4 修订**：`--opt`/`--ohess` 改派后套件补写 `.xtboptok`/`xtbopt.log`/`xtblast.xyz`/`compliance.dat`（§3.9），因此 BC-3 对**所有** runtyp 满足（不再需要"`--opt` 例外"）。判据：与 §3.2 的基线文件清单逐文件 diff（**集合不小**；允许新增 `xtb.trj`/`vib_normal_modes`） | 对每个 runtyp 跑同一几何，列表比对 §3.2 基线 |
| BC-4 | **未被改派的任务数值不变**：`--hess`、`--lscan`、`--lts`、`--lirc`、`--lvib`、
   以及未改派的原生 runtyp（`--bhess/--metaopt/--path/--modef/--screen/--md/--sp/...`）
   的输出与 HEAD 逐位一致 | 对每个 runtyp 跑同一几何，`cmp` stdout 与输出文件 |
| BC-5 | **被改派的任务必须显式告知**：`--opt`/`--ohess` 的语义改变必须在**每次运行**打印一行提示。**R11 修订**：提示走 **stdout**（与 `env%warning`/`env%error` 同一 `env%unit`，`[实测]` §3.4），因此判据是"grep **stdout** 里的 `[NOTICE]` 行" —— 与 §9.2 的测试写法一致，不再自相矛盾 | `xtb/landscape-opt-alias` 断言 stdout 含 `[NOTICE]` |

**本设计对 BC-1..BC-5 全部满足**（BC-4 在 `--opt`/`--ohess` 两处**有意违反**，见 §10 A 类；其余 runtyp 满足 BC-4）。
**R11 修订**：旧稿写"本设计对 BC-1..BC-3、BC-5 满足；对 BC-4 有意违反"，与 §10 的 B 类（文件集合减少）矛盾——
B 类经 R4（套件补写遗留文件，§3.9）已清零，BC-3 改为"集合不小"后**无条件成立**，矛盾消失。

### 1.3 项目既有原则的落地

- 「绝不静默」→ §8.1（冲突检测）、§8.2（必填点名）、§8.5（未知枚举）。
- 「每个选项都要有证明生效的测试」→ §9.2 的测试策略，沿用 M3/M4/M6 的"证明生效"表格法。
- 「单位必须标注」→ §7.3。
- 「默认值必须有依据」→ §3.3、§3.5。

---

## 2. 第一步：上游 xtb CLI 形式调研

> 本节区分 **[文档明说]**（含 URL 与原文引用）与 **[代码推断]**（Our repo 源码 + `file:line`）。
> 查不到的写**「未找到」**。

### 2.1 文档来源

| 来源 | URL / 路径 | 用途 |
|---|---|---|
| 官方文档 · Commandline Usage | `https://xtb-docs.readthedocs.io/en/latest/commandline.html` | runtype 全集、选项全集 |
| 官方文档 · Geometry Optimization | `https://xtb-docs.readthedocs.io/en/latest/optimization.html` | `--opt [level]`、**8 个档位表** |
| 官方文档 · Vibrational Frequencies | `https://xtb-docs.readthedocs.io/en/latest/hessian.html` | `--hess`/`--ohess`、热化学、`.xtbhess` 语义 |
| 官方文档 · Detailed Input (xcontrol) | `https://xtb-docs.readthedocs.io/en/latest/xcontrol.html` | `$fix`/`$constrain`/`--input` 说明 |
| 官方文档 · PES scan | `https://xtb-docs.readthedocs.io/en/latest/scan.html` | 扫描无 CLI，只有 `$scan` 块 |
| man page（仓库内，随上游发布） | `man/xtb.1.adoc`、`man/xcontrol.7.adoc` | **最权威**：runtype、选项、`$opt` 键 |
| GitHub README | `https://raw.githubusercontent.com/grimme-lab/xtb/main/README.md` | 构建，无 CLI 内容 |

> 抓取时间：本轮。抓取原文件缓存在 `/tmp/xtbdoc_*.html`（会话临时文件，不随仓库提交）。

### 2.2 `--opt` / `--hess` / `--ohess` / `--md` / `--omd` 的参数形式

**[文档明说]** `man/xtb.1.adoc`：

```
238:*-o, --opt* ['LEVEL']::
239:    call `ancopt(3)` to perform a geometry optimization,
240:    levels from crude, sloppy, loose, normal (default), tight, verytight
241:    to extreme can be chosen
243:*--hess*::
244:    perform a numerical hessian calculation on input geometry
246:*--ohess* ['LEVEL']::
247:    perform a numerical hessian calculation on an `ancopt(3)` optimized
248:    geometry
250:*--bhess* ['LEVEL']::
251:    perform a biased numerical hessian calculation on an `ancopt(3)` optimized ...
```

**[文档明说]** `optimization.html`（`--opt [level]`）：

> "It is activated by the flag `--opt [level]`. The following levels are available:"

**[文档明说]** `commandline.html`：

- `--opt` — "approximate normal coordinate optimization … queue: setup, SP, ANCopt, SP, properties"
- `--[o]hess` — "second derivative calculation … queue: setup, SP, [ANCopt, SP,] SP, Hessian, properties"
- `--[o]md` — "molecular dynamics simulation … queue: setup, SP, [ANCopt, SP,] properties, MD"

**结论（形式）**：**只有 `--opt`/`--ohess`/`--bhess`/`--metaopt` 接受可选的 LEVEL 位置参数**；
`--hess` 不带参数。`--md`/`--omd` **不接受** level（`--omd` 在文档里硬编码 loose：
"a loose optimization level will be chosen"，`md.html`）。

**[实测]（我们的仓库，`/tmp/xtb-w2/build/xtb`）** 接受 level 的 runtype：

```
--opt normal   → :   optimization level            normal          :
--ohess lax    → :   optimization level               lax          :
--bhess normal → :   optimization level            normal          :
--metaopt ...  → 同样走 set_opt(env,'optlevel',sec)              [代码] main.F90:3835
```

### 2.3 收敛档位（LEVEL）的定义、取值与默认值

**[文档明说]** `optimization.html` 的 "Optimization levels" 表（原文）：

| level | Econv/Eh | Gconv/Eh·α⁻¹ | Accuracy |
|---|---|---|---|
| crude | 5 × 10⁻⁴ | 1 × 10⁻² | 3.00 |
| sloppy | 1 × 10⁻⁴ | 6 × 10⁻³ | 3.00 |
| loose | 5 × 10⁻⁵ | 4 × 10⁻³ | 2.00 |
| lax | 2 × 10⁻⁵ | 2 **.5** × 10⁻³ | 2.00 |
| normal | 5 × 10⁻⁶ | 1 × 10⁻³ | 1.00 |
| tight | 1 × 10⁻⁶ | 8 × 10⁻⁴ | 0.20 |
| vtight | 1 × 10⁻⁷ | 2 × 10⁻⁴ | 0.05 |
| extreme | 5 × 10⁻⁸ | 5 × 10⁻⁵ | 0.01 |

**[R17 修订 · LOW-3]** 上表 `lax` 的 Gconv：web 页写 2 × 10⁻³，而本仓库 `src/optimizer.f90:83` 是 **2.5 × 10⁻³**。
**权威来源改成本仓库源码** `src/optimizer.f90:48-118`（`[代码]`，本机可核），web 页降为旁证：
该处 24 个数值中 23 个与 web 页一致（唯 `lax` Gconv 有差，见上表）。该差**不影响任何设计决策**
（`lax` → 套件 `loose` 的映射与这个值无关）。

**[R17 修订 · LOW-12]** `lax` 的阈值（Econv 2 × 10⁻⁵ / Gconv 2.5 × 10⁻³）位于 `loose`（5 × 10⁻⁵ / 4 × 10⁻³）与
`normal`（5 × 10⁻⁶ / 1 × 10⁻³）**之间**（`optimizer.f90:73-86` 注释亦写 "between loose and normal"）
⇒ 把 `lax` 映射到套件 `loose` 会比上游 `lax` **更松**（Econv 5e-5 vs 2e-5），必须在 `[NOTICE]` 里说明。

**[文档明说]** 同页原文：

> "By default, the optimization level 'normal' is used."
> "energy convergence (Econv) is the allowed change in the total energy at convergence and
> the gradient convergence (Gconv) the allowed change in the gradient norm at convergence.
> The accuracy is handed to the singlepoint calculations … and self consistent field convergence
> criteria. It is adjusted to fit the geometry convergence thresholds automatically."
> "The maximal number of optimization cycles can be defined by using the flag `--cycles integer`."

**[文档明说]** `man/xtb.1.adoc:240-241` 与 web 页**不完全一致**：man 页写
"crude, sloppy, loose, normal (default), tight, verytight to extreme"——
**漏了 `lax`**，且用 `verytight`（web 页用 `vtight`）。
`man/xcontrol.7.adoc:374-377` 的 `$opt optlevel=` 则写
`crude=-3, sloppy=-2, loose=-1, normal=0, tight=1, verytight=2, extreme=3`——**同样漏 `lax`**。

**[实测]** 参照二进制 `edcfbbe` 的 `--opt <LEVEL>` 接受情况（`OMP_NUM_THREADS=1`，`/tmp/clitest/h2o.xyz`）：

```
crude     → normal? 否: "optimization level crude"
sloppy    → sloppy
loose     → loose
lax       → lax          ← 文档 man 页漏写，二进制接受
normal    → normal
tight     → tight
verytight → verytight
vtight    → verytight    ← vtight 是 verytight 的别名
extreme   → extreme
-1 → loose ; 0 → normal ; 3 → extreme   ← 数字也接受
（不给）  → normal       ← 默认
```

**[实测]** `--opt banana`（无效档位）→ **静默变 normal，无任何提示**：

```
$ xtb h2o.xyz --gfn2 --opt banana
          :   optimization level            normal          :
```

**[代码推断]** 机制在 `src/set_module.f90:1904-1930` `optlevel2int`：
`case default → ilvl = p_olev_normal`（**无警告**，`[R17]` 实际行号 `:1910`）；显式档位为
crude/sloppy/loose/lax/normal/tight/verytight|vtight/extreme。**确认 `lax` 在代码里存在**
（`set_module.f90:1918`，`[R17]` 旧稿误写 1916——那是 `case('loose','-1')`），只有**文档**漏了它。

**结论**：上游档位集合 = {crude, sloppy, loose, lax, normal, tight, verytight|vtight, extreme}
共 8 档 + 数字别名（-3..3）；**默认 normal**；**无效值静默回退 normal**（这是一个上游缺陷，
与 §8.5 的"绝不静默"原则冲突，我们的重设计不应复制它）。

### 2.4 方法选择在上游怎么表达

**[文档明说 + 未找到]**：在 `commandline.html` 与 `man/xtb.1.adoc` 里 grep
`--method` / `--engine` / `--optimizer`：**未找到**任何通用方法选择旗标。
（`--oniom METHOD LIST` 里的 METHOD 是嵌入分层，不是 PES 算法。）

**[文档明说]** 方法在上游是 **xcontrol `$opt` 块的键**（`man/xcontrol.7.adoc:362-398`）：

```
$opt
*engine*='method'::
    method can be 'rf' for ANCopt (default), 'lbfgs' for L-ANCopt or
    'inertial' for FIRE.
*optlevel*='level'::
    crude = -3, sloppy = -2, loose = -1, normal = 0,
    tight = 1, verytight = 2, extreme = 3
*hessian*=lindh-d2|lindh|swart::
    model hessian for generation of ANC used in optimization
*hlow*, *maxcycle*, *microcycle*, *maxdispl*, *output*, *logfile*, *s6*, *average conv* ...
```

**结论**：
1. **上游确有方法选择器，但它不是 CLI，而是 `$opt engine=<rf|lbfgs|inertial>`**；
   默认 `rf`（= ANCopt）。
2. **`$opt hessian=` 的名字与我们的 `--lX-hessian` 撞车但语义完全不同**：
   上游的 `hessian` 指**模型 Hessian 生成子类型**（Lindh-D2/Lindh/Swart），
   我们的 `--l*-hessian` 指**数值/模型/文件后端**。→ 这是一个**必须记录**的同名不同义项
   （设计上建议我们的 help 文案明确写 "Hessian backend"，不要复用 "model hessian" 措辞）。
3. 上游**没有**把方法选择器提升到 CLI；我们的 `--method` 是**纯新增**，不冲突。

**[代码推断]** 上游 `$opt engine=` 的习惯映射进我们的基座：本仓库 `src/geoopt_driver.f90:148-172`
（`[R17]` 旧稿误写 152-176；`case(p_engine_rf)` = `:149`；`case(p_engine_pbc_lbfgs)` = `:159`；
`case(p_engine_inertial)` = `:169`——**L-2 订正：旧稿写 166-168**）的 `case(p_engine_*)` 就是 `rf/lbfgs/fire/pbc_lbfgs` 的分派点。
`$opt engine=` 的键解析在 `src/set_module.f90:1885-1892`（`[R17]` 核对；**L-2 订正：`inertial|fire` 在 `:1891`，`:1890` 是 `pbc_lbfgs`**）：
`:1888` `rf|ancopt` → `p_engine_rf`；`:1889` `lbfgs|l-ancopt` → `p_engine_lbfgs`；`:1890` `pbc_lbfgs`；
`:1891` `inertial|fire` → `p_engine_inertial`。
我们的套件是**独立的第二套引擎**，不经过 `geoopt_driver`（`src/landscape/landscape_driver.f90:63`）。

### 2.5 上游 CLI 的命名惯例

**[文档明说 + 实测]**（`man/xtb.1.adoc`、`src/xhelp.f90`）：

| 惯例 | 上游实例 | 我们的套件是否遵守 |
|---|---|---|
| **短/长别名同一行** | `-c, --chrg`；`-I, --input`；`-o, --opt` | ✅ 套件无短名，一致 |
| **`--no-` 前缀成对出现** | `--copy/--nocopy`、`--restart/--norestart` | ✅ `--lscan-oneway`、`--lts-no-verify`、`--lvib-no-project` 同构 |
| **复合 runtype 用 `--[o]x` 前缀** | `--hess/--ohess`、`--md/--omd` | ⚠️ 套件**没有** `--lohess` 等复合形式（见 §3.6，这是 `--ohess` 改派的动机之一） |
| **单数名 + 复数名并存** | `--iterations`/`--maxiterations` 别名；`--gfnff`/`--gff` | ⚠️ 套件里 `--lopt-engine` vs `--lscan-method` 是**同概念两名**（§7.1） |
| **单位不进名字，进 help** | `--etemp REAL`（K 在 help 里）；`--cut` | ❌ 套件 `-step` 一词三义两单位（§7.3） |
| **`-I, --input FILE`** | `main.F90:1642` | ✅ 套件不自建输入文件，沿用 `-I` |
| **`$set`/`--set` 之类** | **未找到** `--set`；`$set` 是**已弃用**的 legacy 组，`man/xcontrol.7.adoc:619-625` 为 LEGACY 标题与引言、弃用句实在 **:626**（`[R17]` 旧稿误引 619-621）；CLI 上只有 `--define`（`main.F90:1608`） | ✅ 我们不做 `--set` |
| **空格分隔取值** | `--opt normal`、`--acc 1.0`（不用 `=`） | ✅ 套件同样空格分隔（`--lopt-engine bfgs`） |

### 2.6 上游对冲突参数与未知参数的处理（并在本仓库验证）

**(a) 未知参数 → warning，不是 error；exit 0**

**[代码推断]** `src/prog/main.F90:1582-1583`：

```fortran
case default
   call env%warning("Unknown option '"//flag//"' provided", source)
```

**[实测]**（`/tmp/xtb-w2/build/xtb`，`OMP_NUM_THREADS=1`）：

```
$ xtb h2o.xyz --gfn2 --zzzz          # exit=0
-1- prog_main_parseArguments: Unknown option '--zzzz' provided

$ xtb h2o.xyz --gfn2 --strict --zzzz # exit=0，仍然只是那一条 -1-
-1- prog_main_parseArguments: Unknown option '--zzzz' provided
```

**[实测]** 参照二进制同行为（`--zzzz-not-a-flag` 也只 warning，exit 0）。
`--strict` **也拦不住**解析期的未知参数：`env%strict = strict` 写在**解析循环之后**
（`main.F90:607-608`），解析期的 warning 已经发完。**这是一个可修的非破坏性缺陷**（§8.5）。

**(b) 冲突参数 → 首次获胜 + 完全静默**

**[文档明说]** `man/xtb.1.adoc:205-207`：

```
NOTE: You can only select *one* runtyp, only the first runtyp will be used
      from the program, use implemented composite runtyps to perform several
      operations at once.
```

**[代码推断]** 机制在 `src/set_module.f90:1031-1040`：

```fortran
subroutine set_runtyp(typ)
   logical,save :: set1 = .true.
   if (.not.set1) then
      call raise('S','Runtyp already set and locked, please use a composite runtyp instead.')
      return
   endif
```

`raise('S', …)`（`src/mctc/error.f90:25-31`）写入 **`persistentEnv`**（mctc-lib 的全局对象）。

**[实测]** 冲突组合**不产生任何用户可见输出**：

```
$ xtb h2o.xyz --gfn2 --norestart --opt normal --lopt       # exit=0
   *** GEOMETRY OPTIMIZATION CONVERGED AFTER 4 ITERATIONS ***    ← 只有 ANCopt，无任何提示

$ xtb h2o.xyz --gfn2 --norestart --lopt --lscan            # exit=0
 landscape: lbfgs minimisation                                   ← 只有 --lopt，无任何提示

$ xtb h2o.xyz --gfn2 --norestart --opt normal --lopt-engine bfgs  # exit=0
   *** GEOMETRY OPTIMIZATION CONVERGED AFTER 4 ITERATIONS ***    ← --lopt-engine bfgs 静默丢弃！
```

**最后一条是审计 §4.4 未覆盖的新发现**：不只是两个 runtype flag 会静默丢，
**一个原生 runtype + 一个套件子选项**也会静默丢（`--lopt-engine` 先 `set_runtyp('lopt')`
被锁 → runtyp 保持 opt；`lset%algorithm=bfgs` 被写入但**没人读**）。

**[未验证]** 机制归属：`persistentEnv` 与 `src/prog/primary.f90:36` 的 `env`、
`src/prog/main.F90:1487` 的**解析局部** `env` 是不是同一个对象——`TEnvironment` 在外部依赖
mctc-lib 里，本轮**未读其源码**。可观察事实（无输出、exit 0）是**实测的**。

### 2.7 「文档明说」vs「代码推断」清单

| 结论 | 类型 |
|---|---|
| `--opt [LEVEL]` 接受 8 档关键字，默认 normal | **文档明说**（web + man） |
| `lax` 存在但 web/man 的档位表漏写 | **文档明说（矛盾）** + **实测**（`set_module.f90:1918`，`[R17]`） |
| 上游无 CLI 方法选择器 | **文档明说（未找到）** |
| 方法在上游 = `$opt engine=` | **文档明说**（`man/xcontrol.7.adoc:364`） |
| 上游未知参数 = warning + exit 0 | **代码推断** + **实测** |
| `--strict` 管不到解析期未知参数 | **代码推断**（`main.F90:607`）+ **实测** |
| 上游冲突 = 首选项获胜 + 静默 | **文档明说**（man 的 NOTE）+ **实测** |
| `$opt hessian=` 与我们的 `--lX-hessian` 同名不同义 | **文档明说** |

### 2.8 未找到 / 未验证

- **未找到**：上游任何 `--method` / `--engine` / `--optimizer` CLI 旗标。
- **未找到**：上游对"未知 **枚举值**"（而非未知旗标）的统一策略；
  已知的实例是 `--opt banana` → **静默 normal**（§2.3），**没有** warning。
- **未验证**：`TEnvironment` 的 warning 落盘位置（stdout vs stderr）在源码层的归属；
  **实测**是写 **stdout**（§3.4）。
- **未验证**：`--o1nh`、`--imagmin/--imagmax` 的 ODLR Hessian 实现细节（与本次设计无关）。

---

## 3. `--opt <level>` 与 `--ohess` 的语义（方案 C，已决策）

### 3.0 决策记录

| # | 决策 | 来源 |
|---|---|---|
| D-C | `--opt <level>` → **套件默认优化器**，**必须**每次运行打印一行提示，`--method ancopt` 是出口；列入破坏性变更 | **用户已确认**（本轮上级转达） |
| D-O | `--ohess <level>` → **套件 `opt + vib` 链** | **用户已确认** |
| D-N | `--bhess` / `--metaopt` / `--path` / `--modef` / `--screen` **保持原生** | **用户已确认**；依据 = W1 确认套件无等价实现（`08-four-way-capability-boundary.md` §3 G3/G4/G5/G6/G7） |

### 3.1 维度正交性论证（`level` 与 `method` 是两个轴）

**无论 A/B/C/D 都成立**，这是 `--opt normal --method bfgs` 读起来不别扭的原因：

| 维度 | 回答的问题 | 上游对应物 | 我们的对应物 |
|---|---|---|---|
| **level / 收敛档位** | "收敛到什么程度？" | `--opt <level>` 的位置参数；`$opt optlevel=` | `--lopt-level` / `set_conv_level`（`settings.f90:1046`） |
| **method / 算法** | "用哪个算法走这条路？" | `$opt engine=`（`rf/lbfgs/inertial`） | `--lopt-engine`（`main.F90:2251`）、`--lts-method`（`:2581`）、`--lirc-method`（`:3325`） |

两者**无耦合**：任何 method 都能配任何 level。上游自己就是两个键
（`$opt engine=` + `$opt optlevel=`，`man/xcontrol.7.adoc:364,374`）。
**因此 `--opt normal --method bfgs` = "用 bfgs，收敛到 normal 档"，与 `--opt tight --method lbfgs`
是同一语法的两个不同组合。** 设计上：**level 不因 method 改变而改变；method 不因 level 改变而改变**；
两者都缺省时各自取默认（level=normal，method=任务默认）。

### 3.2 文件契约基线（本设计的第二类破坏来源）

**[实测]**（`/tmp/xtb-w2/build/xtb`，`h2o.xyz`，`--gfn2 --norestart`，干净目录，
`ls -a` 全列，2026-10-03）：

| 调用 | 写出的文件（含隐藏文件） |
|---|---|
| `--opt normal` | `charges` `wbo` **`xtbopt.log`** **`.xtboptok`** `xtbopt.xyz` `xtbtopo.mol` |
| `--lopt` | `charges` `wbo` `xtbopt.xyz` `xtbtopo.mol` **`xtb.trj`** |
| `--hess` | `charges` **`compliance.dat`** `g98.out` `hessian` `vibspectrum` `wbo` `xtbtopo.mol` |
| `--lvib` | `charges` `g98.out` `hessian` **`vib_normal_modes`** `vibspectrum` `wbo` `xtbtopo.mol` |
| `--ohess normal` | `charges` **`compliance.dat`** `g98.out` `hessian` `vibspectrum` `wbo` **`xtbopt.log`** **`.xtboptok`** `xtbopt.xyz` `xtbtopo.mol` |
| `--hess` on a saddle（1 虚频） | 上述 + **`xtbhess.xyz`**（条件输出） |
| `--lvib` on a saddle（1 虚频） | 上述 + **`xtbhess.xyz`**（条件输出） |
| `--lts --lts-method prfo`（失败） | `xtbts.log` `xtbts.xyz` |

**结论（三类）**：

1. **opt 侧**：原生写 `xtbopt.log`（轨迹，xyz）与 `.xtboptok`（收敛哨兵）；
   套件写 `xtb.trj`（轨迹）。⇒ **套件缺 `xtbopt.log` 与 `.xtboptok`，多 `xtb.trj`**。
2. **hess 侧**：原生多写 `compliance.dat`（顺从性分析）；套件多写 `vib_normal_modes`。
   `xtbhess.xyz` **两边都写**（条件 = 有虚频）。
3. **`xtblast.xyz`**：仅原生失败路径写（`main.F90:956-958`）；套件**不写**。

**证据（代码）**：

```
$ grep -rn "xtboptok\|NOT_CONVERGED\|xtblast\|xtbopt.log" src/landscape/
(空)                      ← 套件对这四个名字零引用
```

- `.xtboptok` 的写点在 `src/geoopt_driver.f90:112-113`（开场删除）、`:183`（失败写 `NOT_CONVERGED`）、
  `:186`（成功 `touch .xtboptok`）。
- `xtbopt.log` 的写点在 `src/geoopt_driver.f90` 的 `set%opt_logfile` 分支（`main.F90:1197` 附近）。
- 套件的写点在 `src/landscape/types/log.f90:74`（`...opt.xyz`）与 `:87`（`....trj`）。
- `compliance.dat` 在原生 `--hess` 路径（`src/hessian.F90` 或 `main_freq`）；
  套件 `--lvib` 不调用它（`src/landscape/tasks/vib.f90:25-40` 的文件表里没有）。
- `xtbhess.xyz` 由 `distort` 写（`src/hessian.F90:714-717`），
  `src/landscape/tasks/vib.f90:34` 明说它也走这条路。

**W1 报告订正**：`08-four-way-capability-boundary.md` §2 row 29 写套件缺
"`.xtboptok`/`.xtbopt.log`/`xtblast.xyz`"。**逐字核实：`.xtbopt.log` 这个名字不存在**
（`.xtboptok` 有前导点，轨迹文件是 **`xtbopt.log`** 无前导点）。**其余成立**：
`.xtboptok` 与 `xtblast.xyz` 套件确实不写。⇒ W1 的**结论成立，文件名有一处笔误**（本轮实测为准）。

### 3.3 套件默认优化器是哪个：实测依据

**[实测]** 6 个套件引擎在同一 3 个未优化几何上的真实能量评估数
（`--lopt --lopt-engine <m> --lopt-level normal`，`n_cache_miss` = 真实能量评估数，
注意 RFO 的 `n_eval` 会被缓存掩盖，必须看 `n_cache_miss`）：

| engine | H2O | CH3OH | butane | 备注 |
|---|---|---|---|---|
| sd | 21 | 177 | 42 | |
| cg | 21 | 177 | 42 | |
| **lbfgs** | **6** | **20** | **9** | 现有默认（`settings.f90:427`） |
| bfgs | 4 | 20 | 12 | H2O 最省，butane 略差 |
| diis | 13 | 38 | 20 | 大量 fallback（11/31/17） |
| rfo | 21 | 80 | 87 | 需 Hessian，最贵 |

末能量一致性（所有引擎到同一极小点）：lbfgs/bfgs/rfo/sd 在 H2O 上
−5.070544447815 / −5.070544434858 / −5.070544447754 / −5.070544166351 Eh（差 ≤ 3e-7）。

**依据链**：
1. **实测**（上表）：lbfgs 与 bfgs 是仅有的两个"廉价且鲁棒"的通用极小化器；
   lbfgs 在 3/3 上都 ≤ 12 次评估，bfgs 在但丁烷上多 3 次。
2. **文献**：L-BFGS 是 quasi-Newton 的标准低记忆实现（Nocedal & Wright, *Numerical Optimization*,
   2nd ed., Ch. 7），配 Bofill Hessian 更新（`settings.f90:421-424` 记 Bofill 1994）。
3. **既有实现**：`settings.f90:427` 的默认值就是 `p_landscape_opt_lbfgs`，
   `--help` 文案也写 "default lbfgs"（`xhelp.f90:289-291`）。

⇒ **`--opt <level>` 沿用套件既有默认 `lbfgs`**。**不是新决策，是把既有默认接到新入口。**

> **未确定**：更大的分子（>60 原子）上 lbfgs vs bfgs 的排序未测。若将来要改默认，
> 需要 taxol 级或 CH3OH 以外的基准；**本轮不做该决策**。

### 3.4 提示的投递方式（放 stdout 还是 stderr？）

**[实测]** `env%warning` 的输出去向：

```
$ xtb h2o.xyz --gfn2 --norestart --hess --ljson > so.txt 2> se.txt
so.txt:388  [WARNING] Runtime exception occurred
so.txt:390  -1- prog_main: --ljson writes nothing without a landscape run type: ...
se.txt: （空）
```

⇒ **warning 走 stdout，stderr 是空的。**

**设计决策（R11 修订）**：
- `--opt`/`--ohess` 改派的提示走 **stdout**（`env%unit`）。**R11 理由**：① `env%warning`/`env%error` 实测就在 stdout（上），
  同一 `env%unit` 内不一致会更糟；② BC-5 与 §9.2 的测试写法就是 grep stdout，走 stdout 使两者**可执行且不矛盾**；
  ③ 旧稿担心"污染 `grep TOTAL ENERGY` 这类调用"——但 `env%warning` **已经**在 stdout，这个风险**已存在**，
  新增一行 `[NOTICE]` 与它同类，不引入新的不一致。
- **每次运行打印一次**（不是每个 flag 一次），且**`-s`/`--silent` 不抑制**——
  因为它是一条"语义变更"通知，不是 debug 噪声。
- `-s`/`--silent` 目前在**上游就是未实现**的（审计 §2.3；实测 `-1- ... Unknown option '--silent' provided`）。
  若设计想用它抑制，必须先实现它（§8.6）；本轮**不依赖**它。
- **stdout 是否被既有测试断言**：`[实测]` 本机核实为 **0 命中 `2>&1`**，但 **`test/unit/CMakeLists.txt:513-514` 等把
  `OUTPUT_VARIABLE output` 与 `ERROR_VARIABLE output` 取**同名合并**（即 stderr 也进了断言流），`landscape_cli_check.py:55-61`
  的 `run()` 返回 "combined output" ⇒ **stderr 已被合并入断言流**；但断言全是子串式（`MATCHES`/`in`），
  **多一行 `[NOTICE]` 不会变红**。
  （`--opt --input <$scan>` 那一组断言除外，见 §14.1/R2：它断言的是**行为**不是输出文本。）

提示文案（建议）：

```
[NOTICE] --opt now runs the landscape suite optimiser (lbfgs); ANCopt is not used.
         pass --method ancopt for the legacy ANCopt optimiser.
```

（一行到两行，**前缀 `[NOTICE]`**，与 `[WARNING]` 区分；写到 `env%unit` = stdout。）

### 3.5 level 关键字与套件收敛档位的对齐（**R5 修订：档位 = 阈值 + `e_tol` + SCF 精度 + 步数预算**）

**现状（HEAD `bdd8eb8`，`[代码]`）**：

- 套件 5 档的 `set_conv_level`（`src/landscape/types/settings.f90:1046-1081`）**只写 4 个阈值字段**：

| 套件档位 | g_max | g_rms | d_max | d_rms | e_tol（现状） |
|---|---|---|---|---|---|
| superloose | 4.6e-3 | 3.0e-3 | 7.9e-3 | 5.2e-3 | **5.0e-6（固定）** |
| loose | 2.0e-3 | 5.0e-4 | 1.0e-2 | 7.0e-3 | **5.0e-6** |
| normal | 3.0e-4 | 1.0e-4 | 4.0e-3 | 2.0e-3 | **5.0e-6** |
| tight | 1.0e-4 | 3.0e-5 | 1.0e-3 | 6.0e-4 | **5.0e-6** |
| vtight | 3.0e-5 | 8.0e-6 | 2.0e-4 | 1.0e-4 | **5.0e-6** |

- `e_tol` **不随档位变化**（`settings.f90:357` 固定字段；`set_conv_level` 逐行确认只写 4 个字段）。
- `engine%acc` = `1.0`（`settings.f90:325`），由 `main.F90:991`（`--lopt` 路径）从全局 `set%acc` 同步
  （`--acc`，默认 1.0，`setparam.f90:227`），**与档位无关**。
- `lset%max_steps` = `256` 固定（`settings.f90:355`），**没有 CLI**（§6.3 补 `--lopt-max-steps`）。
- 上游每个档位还携带 **Econv**、**SCF 精度 acc** 与 **maxcycle 倍数**（`src/optimizer.f90:59-113`）：
  `maxcycle = clamp(n × mult, 200, 10000)`，`n = 原子数`（`get_optthr(mol%n,...)`，`optimizer.f90:332`）；
  `--cycles N` 覆盖（`optimizer.f90:335-337`；读点 `set_module.f90:1823` `--cycles` → `set_opt(env,'maxcycle',sec)`，
  `main.F90:1955`）。

**R5 新语义（用户决策 3）**：**档位一次性驱动 4 个轴**：收敛阈值、`e_tol`、SCF 精度 `acc`、步数预算 `max_steps`。
`set_conv_level` 扩展为写 5 个字段（+ `e_tol`），并在同一张表里定义 `acc` 与 `max_steps` 倍数（由任务驱动读）。
**数值全部照搬上游对应档位**（`optimizer.f90:59-105`）：

| 套件档位 | g_max | g_rms | d_max | d_rms | **e_tol（新）** | **acc（新）** | **步数倍数（新）** |
|---|---|---|---|---|---|---|---|
| superloose | 4.6e-3 | 3.0e-3 | 7.9e-3 | 5.2e-3 | 5.0e-4 | 3.0 | 1 |
| loose | 2.0e-3 | 5.0e-4 | 1.0e-2 | 7.0e-3 | 5.0e-5 | 2.0 | 2 |
| normal | 3.0e-4 | 1.0e-4 | 4.0e-3 | 2.0e-3 | 5.0e-6 | 1.0 | 3 |
| tight | 1.0e-4 | 3.0e-5 | 1.0e-3 | 6.0e-4 | 1.0e-6 | 0.2 | 5 |
| vtight | 3.0e-5 | 8.0e-6 | 2.0e-4 | 1.0e-4 | 1.0e-7 | 0.05 | 20 |

（`max_steps = clamp(原子数 × 倍数, 200, 10000)`，与上游同规则；`--cycles N` / `--lopt-max-steps N` 显式覆盖。）

**[实测]** 档位确实改变行为（CH3OH，`--lopt --lopt-engine sd`，`n_cache_miss`）：

```
superloose → 28 evals   E=-8.225969151202
loose      → 28 evals   E=-8.225969151202
normal     → 177 evals  E=-8.226108114255
tight      → 257 evals
vtight     → 257 evals
```

**对齐/映射表**（**R27 口径固定：只属于 `--opt`/`--ohess` 桥接**；`--lopt-level` 等**不**收上游名，见下）：
`--opt <LEVEL>` 接受**上游 8 档 + 我们的 5 档**的并集，
上游名 → 套件名是多对一的，映射发生（或发生截断）时打印一行 `[NOTICE]`（不静默）：

| `--opt` 关键字 | 套件档位 | 偏差（写进 `[NOTICE]`） |
|---|---|---|
| `crude` | `superloose` | e_tol 5e-4（同上游 crude）；acc 3.0 |
| `sloppy` | `superloose` | 比上游 sloppy（e_tol 1e-4）**更松** |
| `loose` | `loose` | 同名，e_tol 5e-5 一致 |
| `lax` | `loose` | 比上游 lax（e_tol 2e-5）**更松**（`lax` 阈值介于 loose 与 normal，见 §2.3） |
| `normal` | `normal` | 默认；阈值判据数目不同（4 vs 上游 2） |
| `tight` | `tight` | 同名 |
| `verytight` / `vtight` | `vtight` | 两拼写映射到一套件名 |
| `extreme` | `vtight` | **上限截断**（上游 e_tol 5e-8 / acc 0.01，套件无更紧档） |
| `superloose` | `superloose` | 套件独有 |
| 数字 `-3..3` | 同上映射 | 上游数字别名 |
| `banana` 等未知 | **error**（不复制上游的静默 normal，§8.5） | — |

**R27 决定（L-4）：`--l*-level` 是否也接收上游 8 档名？—— 不接收。**
现况：`landscape_conv_level_known`（`settings.f90:1497-1510`）只认 5 个套件名
（`superloose/loose/normal/tight/vtight`）；`--lopt-level lax` 今天就是 `env%error`
（`main.F90:2271-2275`）⇒ "不接收"是**保持现状**，不构成新破坏。

- **理由 1（单一命名轴）**：上游名与套件档不是一一对应（`verytight`→`vtight`、`extreme`→`vtight`
  **截断**，`sloppy`/`lax` 无对应档）。若在 `--l*-level` 上也收，同一旗标就有两个命名轴，
  `--lopt-level lax` 的含义只能靠文档解释。
- **理由 2（可达性不受损）**：要用上游名的用户走桥接即可：`--opt lax --method bfgs`
  （`--opt` 先设 runtyp `p_run_opt`，`--method bfgs` 在解析尾归一到 lset）⇒ "套件算法 + 上游档名"完全可达。
- **理由 3（不破坏）**：不收新名 ⇒ BC-1/BC-2 原样成立；若收则需额外的 `[NOTICE]` 语义与再基线（§3.10）。

⇒ 记录为**已决定项**（不再列为开放问题）；§6.2 第 4 行同步改写。

**上游档名 → 套件档的实现点（R33/L-5 补）**：`--opt <LEVEL>` / `-o <LEVEL>` 把关键字存进
`set%optset%optlev`（`main.F90:2153-2157` 的 `case ('-o','--opt')` → `call set_opt(env,'optlevel',sec)`
→ `set_module.f90:1811` 的 `set%optset%optlev = optlevel2int(val)`，`optlevel2int` 在 `:1910-1928`，
未知值 → `p_olev_normal`）。所以套件分派处（`effective_landscape_task == p_run_lopt`，§3.11 读点 #5）
要**读这个整数**、映射到 `l*set` 的档位派生子（`set_conv_level`）并打 `[NOTICE]`；`--ohess` 同构
（`main.F90:2166` 的 `case('--ohess')`）。⇒ `xtb/landscape-method-level-bridge`（`--opt lax --method bfgs`）
的断言依赖这条映射；实现时**不得**再从 `--opt` 的原始字符串推断（它到那里已丢失）。

**必须告知的偏差**（写进 §10 E 类）：

1. **`--lopt-level` 的 `e_tol`/`acc` 随档位改变**（旧稿"`e_tol` 固定"作废）：
   `--lopt-level loose` 从 `e_tol=5e-6, acc=1.0` 变为 `e_tol=5e-5, acc=2.0`（更松、更快）。
2. **默认 `normal` 也变**：`max_steps` 从固定 `256` 变为 `clamp(3n, 200, 10000)`（H2O → 200）；`acc` 不变（1.0）。
3. **优先级（兼容逃生舱）**：显式 `--acc <x>` **优先于**档位派生的 `acc`；显式 `--cycles`/`--lopt-max-steps`
   优先于档位派生的 `max_steps`。即：`--lopt-level loose --acc 1.0` 仍得到 `acc = 1.0`，
   而 `--lopt-level loose --cycles 256` 仍得到 256 步预算。
   **实现处（R27/L-5）**：`main.F90:996`（`--lopt`）、`:1013`（`--lscan`）、`:1033`（`--lts`）、
   `:1062`（`--lirc`）、`:1078`（`--lvib`）现在是**无条件** `engine%acc = set%acc` ⇒ 会把档位派生的 `acc`
   **覆盖回全局默认** `set%acc`（`setparam.f90:227` = 1.0）。R5 的优先级要求把它改为**仅当用户显式给了
   `--acc` 时同步**（`case ('-a','--acc')` 在 `main.F90:1665` 置 `acc_was_set = .true.`，五处同步加 `if (acc_was_set)`）。
   不改则 `--lopt-level loose` 的 `acc = 2.0` 静默失效——这正是本项目已抓到 4 次的"死旋钮"同类缺陷。
4. **档位是 g_max/g_rms/d_max/d_rms 四判据**，上游是"ΔE + 梯度范数"两判据；即使同名 `normal`，
   数值阈值也不同（套件 g_rms=1e-4 vs 上游 Gconv=1e-3）。

**影响、既有测试与已验收数字的再基线清单 → §3.10。**

### 3.6 A / B / C / D 后果对照表（**供用户一眼选**）

| | **A** | **B** | **C（已选）** | **D** |
|---|---|---|---|---|
| `--opt <lvl>` 的行为 | 仍是 ANCopt | 套件默认（lbfgs） | **套件默认（lbfgs）** | 阶段一 ANCopt，阶段二套件 |
| 调用样例（套件） | `--opt normal --method auto` | `--opt normal` | `--opt normal` | 同 B（阶段二起） |
| 调用样例（原生） | `--opt normal` | `--method ancopt` | `--method ancopt` | 同 B |
| 数值是否变 | **否** | **是，静默** | **是，但告知** | 阶段一不变，阶段二变 |
| 用户是否被告知 | — | ❌ **不告知** | ✅ 每次一行 `[NOTICE]`（**stdout**） | ✅ 阶段一预告 + 阶段二告知 |
| 破坏性条数（§10） | **0** | 未计（静默本身是缺陷） | **16**（A3+B0+C7+D1+E1+F3+G1，R23 后） | 同 C（阶段二起） |
| 是否消灭"静默"缺陷 | — | ❌ 制造一个新的静默缺陷 | ✅ | ✅ |
| 用户"依然是 `--opt normal`" | ❌ 要加 `--method` | ✅ | ✅ | ✅（阶段二起） |

**B 的核心问题**：它满足了字面要求，但**对既有脚本完全静默**——这正是本项目
（W0 的 `$scan`、M3 的 `$thermo`、M4/M6 的死旋钮）一直在消灭的**同一类缺陷**。
**C = B + 显式告知 + 出口**，是本设计的推荐也是用户已选。**D 是最保守的工程路径**，
代价是要等两个发布周期。

### 3.7 若选 C/B/D：原生 runtype 的影响面分析（`--bhess/--metaopt/--path/--modef/--screen`）

**规则**：**只有 `--opt` 与 `--ohess` 改派**；其余保持原生（用户已决定，§3.0 D-N）。

| runtype | 套件有无等价实现 | 若改派的后果 | 结论 |
|---|---|---|---|
| `--bhess`（偏置 Hessian，`getkopt`） | ❌（`08-...md` §3 G3；`src/getkopt.f90:142`） | **功能消失**（套件无偏置 Hessian 语义） | **保持原生** |
| `--metaopt`（构象搜索） | ❌（G6；`main.F90` 的 ANCopt 偏置链） | **功能消失** | **保持原生** |
| `--path`（RMSD 偏置路径） | ❌（G4；`src/bias_path.f90`） | **功能消失**（套件 NEB 是笛卡尔空间，不是 RMSD） | **保持原生** |
| `--modef`（模式跟随） | ❌（G5；`src/modef.f90`） | **功能消失**（套件 `saddle/eigenfollow.f90` 只服务 TS） | **保持原生** |
| `--screen`（批量筛选） | ❌（G7；`src/screening.f90`） | **功能消失** | **保持原生** |
| `--vip`/`--vea`/`--vipea`/`--vfukui`/`--vomega`（属性层，G8） | ❌ **无 property 层**（套件只有 sp/opt/scan/ts/irc/vib 六个任务） | 套件**无法经 CLI 暴露**这类属性（INFO-3 明说） | **保持原生**；`--method` 在其上报错（§4.6） |
| DMF（G14） | ❌（D2 明确排除：需 cyipopt/Ipopt） | 不在本次范围 | **不复述实现**（INFO-2：仅复述 D2 的排除决定） |
| `--ohess`（opt+Hess 一次） | ⚠️ **可用 `--lopt` + `--lvib` 两步链等价替代** | 输出契约变化（§3.2 / §10 B4） | **改派（用户已定）** |

**`--ohess` 输出契约核查**（这是它能改派、而其余不能的关键）：

- 原生 `--ohess <level>` **本身就是 `main_geometry` + `main_freq` 两次调用**
  （`src/prog/main.F90:1279` 与 `:1284`；**L-2 订正**：旧稿这里写 `:1282`/`:1287` —— `1279` 才是 `main_geometry`，`1284` 才是 `main_freq`）——**不是单一算法**，所以用套件的两步链替代在
  **语义上是同构的**。
- 但**文件契约有差**（§5.4 与 §10 B4）：缺 `.xtboptok` / `xtbopt.log` / `compliance.dat`，
  多 `xtb.trj` / `vib_normal_modes`。
- **外部消费点**：`.xtboptok` 是"收敛哨兵"，常被流水线 `test -f .xtboptok` 判定；
  `xtbopt.log` 是 xyz 轨迹，常被可视化脚本读取。⇒ **这两条是真破坏**，
  且**不能**用"数值变了"一句带过。
- **缓解（R4 修订：决策 2 已定为强制）**：套件 `opt`/`vib` 任务**按上游语义写全 4 个遗留文件**
  （`.xtboptok` / `xtbopt.log` / `xtblast.xyz` / `compliance.dat`），⇒ **B 类破坏清零**。
  完整语义、上游对照 `file:line`、`--namespace` 交互与测试见 **§3.9**（新增）；实施归阶段 3。

---

### 3.8 【R1 新增】三类"原生专属"情形：响亮报错 + 指向 `--method ancopt`

> **来源**：用户决策 1（父会话已逐条核实三类都成立）。
> **统一原则**：改派后这三类不能再"静默丢失"；一律 `env%error`，**exit 码 = 1**
> （`src/type/environment.f90:266-294` `terminateRun` 无 `code` ⇒ `terminate(1)`；
> 错误文本由 `env%show(...,.true.)` 写到 `env%unit` = **stdout**，可 grep）。
> **前置**（与 §3.11 一致）：`--opt`/`--ohess` 保留为**独立 runtyp**（不合并到 `p_run_lopt`）；
> 当且仅当 `landscape_native_engine == 0` 时，它们被"改派到套件"。下文把后者简写为
> "`--opt`(套件) "。
>
> **R22 修订（H-2，关键）**：旧稿的判据是 `landscape_native_ancopt`（一个**只认 `ancopt`** 的布尔），
> 而 §4.8/§5.5 明写 `--opt --method lancopt|fire` 也走**原生** ⇒ 三条守卫会对原生 L-ANCopt/FIRE
> **误报 exit 1**。现在三条守卫统一读 **`landscape_native_engine == 0`**（单一整数标志，取值域 = 4 个
> `$opt engine=` 值，§3.11），所以：
>
> - `--opt` / `--ohess`（无 `--method`）→ `native_engine == 0` → **套件任务** → 三条守卫**生效**；
> - `--opt --method ancopt|lancopt|fire|pbc_lbfgs` → `native_engine ≠ 0` → **原生** → 三条守卫**均不触发**；
> - `--lopt`/`--lscan`/`--lts`/`--lirc`/`--lvib` → `native_engine == 0` 且 runtyp 就是套件任务 → **生效**。
>
> 判据的唯一来源是 `landscape_is_suite_run(runtyp, landscape_native_engine)`（§3.11 的纯函数），
> **不允许**在守卫里写 `native_engine == p_engine_rf`（那正是 H-2 的错法）。
> **R29 补充**：同一个位（`landscape_native_engine` = 0 / ≠ 0）也是**原生 Hessian/频率路径**的唯一判据
> （经 §3.11.1 的 `landscape_native_hessian_path`）：§3.8 的三条守卫与 `--ohess` 的两处抑制读**同一个来源**，
> 所以不存在"守卫说套件、抑制说原生"的第二套判据。

#### (a) `$scan` xcontrol 块（H1）

| 项 | 设计 |
|---|---|
| 触发条件 | `nscan > 0` **且** `landscape_is_suite_run(set%runtyp, landscape_native_engine)` 为真（R22：含 `--opt`/`--ohess`(套件)，**不含** `--opt --method ancopt|lancopt|fire|pbc_lbfgs`） |
| 检测点（file:line） | `src/prog/main.F90:491-510` 现有守卫的 `select case (set%runtyp)` 上**加 `p_run_opt`/`p_run_ohess` 两个分支**，分支体内受 `landscape_native_engine == 0` 控制（§3.11）；`nscan` 已在 `:476` `read_userdata` 后可用 |
| 错误文本 | `"--opt now runs the landscape suite optimiser, which does not execute the xcontrol $scan block: use --method ancopt to run the native ANCopt that performs it, or --lscan with --lscan-coord/--lscan-atoms for a scan of the landscape suite"`（`--ohess` 同构，首词换成 `--ohess`） |
| 退出码 | 1（`env%error` + `env%checkpoint`） |
| 测试 | 更新 `xtb/landscape-scan-xcontrol`（`check_scanblock` 的 **492-503 段**，见 §14.5）；另加 `xtb/landscape-opt-scanblock` 断言文本含 `--method ancopt` |

> **R2 留痕**：复核"`--opt` 改派会打破 `xtb/landscape-scan-xcontrol`"**正确**；
> 父会话此前"该测试不会因此失败"的核实**被证伪并撤回**（证据 `landscape_cli_check.py:492-503`，见 §14.1）。

#### (b) 周期体系（H2）

| 项 | 设计 |
|---|---|
| 触发条件 | `mol%npbc > 0` **且** `landscape_is_suite_run(set%runtyp, landscape_native_engine)` 为真（R22：`--opt --method ancopt` 于周期体系**不**触发，走原生 `pbc_lbfgs`） |
| 检测点（file:line） | **与 (a) 同一块**：`src/prog/main.F90:491-510` 的现有 `select case (set%runtyp)` 守卫里加 `p_run_opt`/`p_run_ohess` 两个分支（L-4 措辞统一：三处守卫都在这里；它在 `:434 readMolecule`（`mol%npbc` 已定）、`:333 rdcontrol`（`set%optset%xcontrol_supplied` 已定）与 `:476 read_userdata`（`nscan` 已定）**之后**、原生优化块 `:931` **之前**，所以三个条件都就绪，与分派点位置**功能等价**） |
套件自身已在 `src/landscape/landscape_driver.f90:73-77` 拒绝 PBC，但那里的文本不点名 `--method ancopt`，所以守卫放在这里（双保险） |
| 错误文本 | `"--opt runs the landscape suite, which does not support periodic boundary conditions: use --method ancopt for the native ANCopt (pbc_lbfgs / GFN-FF periodic) optimisation"` |
| 退出码 | 1 |
| 测试 | `xtb/landscape-opt-pbc`：一个 GFN-FF 周期 fixture + `--opt` → 非零退出 + 文本含 `--method ancopt`；
**基线**：同 fixture `--opt --method ancopt` → exit 0（原生化），`--lopt` → 报 `landscape tasks do not support periodic boundary conditions yet`（`landscape_driver.f90:74`） |

> **注**：`--lopt`/`--lscan`/... 的 PBC 拒绝**保留**：它们无"ancopt 出口"（§4.2 的容忍集合不含 `ancopt`），
> 所以不给错误导。

#### (c) xcontrol `$opt` 键（H4）

| 项 | 设计 |
|---|---|
| 触发条件 | xcontrol（或 legacy `$set`）**出现过 `$opt` 组**（哪怕只一个键）**且** `landscape_is_suite_run(set%runtyp, landscape_native_engine)` 为真（`--lopt/--lscan/--lts/--lirc/--lvib` 与 `--opt`/`--ohess`(套件)） |
| 检测点（file:line） | **写点（R28 定）**：`src/set_module.f90:797`（`case('opt'); call rdblock(env,set_opt,line,id,copy,err,ncount)`）——在其**前一行**置位 `set%optset%xcontrol_supplied = .true.`（新增逻辑字段，默认 `.false.`，**不进 `write_set_opt`**，因为它不是用户键）；legacy `$set` 侧同理置位在 `src/set_module.f90:2845,2856-2860`（`optlev`/`hlowopt`/`s6opt`/`microopt`/`maxopt`/`maxdispl` 六个键所在的
`subroutine set_legacy`，`:2811-2928`）；
CLI 的 `--opt/--ohess/--cycles` 也调 `set_opt`，**它们不置位**——因为置位在 `rdcontrol` 的 `case('opt')` 分派处，而不是在 `set_opt` 内部，所以不需要给 `set_opt` 加参数（`rdblock` 的 `handlerInterface` 是固定的三参接口，`set_module.f90:106-112,914-919`）；
读点：**与 (a)(b) 同一块**（`main.F90:491-510`；`rdcontrol` 更早，`main.F90:333`；L-4 措辞统一） |
| 错误文本 | `"the xcontrol $opt block is ignored by the landscape suite: remove it, or use --method ancopt to run the native ANCopt (rf) that honours engine=/optlevel=/hessian=/maxcycle=/..."` |
| 退出码 | 1 |
| 测试 | `xtb/landscape-opt-xcontrol`：`--opt --input <$opt optlevel=tight>` → 非零退出 + 文本含 `--method ancopt`；
**基线**：`--opt --method ancopt --input <同文件>` → exit 0 且结果随 `optlevel` 改变（V4）；`--lopt --input <同文件>` → 同类报错 |

> **作用域（设计取舍，已声明；R23：已入册为破坏性变更 C7）**：守卫**对所有走套件的 run type 生效**（不只 `--opt`），
> 因为 `--lopt` 等今天也**静默**忽略 `set%optset`（复核 H4：套件对 `set%optset` **零引用**，仅 `settings.f90:422` 一句注释；
> 本轮复测：`grep -rn optset src/landscape/` = **1 命中且是注释**）。“绝不静默”是项目首要原则，覆盖不完全就等于留着静默路径。
>
> **R23：为何不收窄到只守卫 `--opt`**（复核 M-2 要求二选一）：
> 收窄的定义就是"让 `--lopt`/`--lscan`/… + `--input <含 $opt>` 继续 exit 0 且 0 行提示"——**实测**：
> `--lopt --input <$opt optlevel=tight>` → exit 0、`grep -ci 'warning\|ignore\|opt block'` = 0。
> 保留这条静默路径与 §1.1 目标 4（绝不静默）直接冲突，而登记的代价是：
> **爆炸半径实测 = 0**：`grep -rn '\$opt' test/unit/` = **0 命中**（所有 CLI fixture 用的是 `$scan`/`$scc`/`$fix`，不是 `$opt`）。
> ⇒ **选择：全量守卫 + 登记为 C7 + 计数 15→16**（§10 C7）。

### 3.9 【R4 新增】套件写全 4 个遗留文件（B 类清零）

> **来源**：用户决策 2。要求按**上游语义**写；本节给逐文件语义 + **上游对照 `file:line`**。
> **上游对照不是猜名字**：下表的"上游写点/条件"均在仓库内可核。

| 文件 | 上游写点 / 条件（file:line） | 套件新语义（设计） |
|---|---|---|
| **`.xtboptok`** | `src/geoopt_driver.f90:112-113` 开场 **删** `.xtboptok`（仅 `pr=.true.`）；`:186` 成功时 `touch_file('.xtboptok')`；`:183` 失败时 `touch_file('NOT_CONVERGED')` | **仅收敛成功时创建**（外部流水线的收敛判据）；任务开场先删旧哨兵；失败时**不**创建 `.xtboptok`，改创 `NOT_CONVERGED`（与上游同构）。
| **`xtbopt.log`** | 开场 `src/geoopt_driver.f90:120-121` `open_file(ilog,'xtbopt.log','w')`（**名字无前导点**）；可被 `$opt logfile=` 重定向到 `-`（stdout）或自定义文件（`:123-128`）。**逐帧写点（L-3 补）**：`src/optimizer.f90:801` `call writeMolecule(mol, ilog, format=fileType%xyz, ..., number=iter)`，在 `ancopt` 的 `relax` 内（打印控制 `:800`），因此文件是 XMOL 多帧 | 逐步轨迹日志（XMOL 多帧），**名字 `xtbopt.log`**（W1 旧稿写的 `.xtbopt.log` **有误**，本轮核实并改对）。若未给 `--namespace` 则为裸名。
| **`xtblast.xyz`** | `src/prog/main.F90:956-962`（仅 `murks`/失败路径）：`generateFileName(tmpname,'xtblast',extension,mol%ftype)` → `open_file` → `writeMolecule`，并打印 `"last geometry written to: <name>"` | 套件 `opt` 任务**失败时**写最后一步几何（xyz），并打印同名提示。成功时**不**写。
| **`compliance.dat`** | **不是 `main_freq` 写的**：`compliance_driver` 仅被 `src/hessian.F90:331-332` 的 `numhess` 调用，条件是 `mol%n > 1 .and. freezeset%n == 0 .and. .not. set%periodic`（`:331`）；写函数 `src/compliance.f90:253-358` `write_compliance_dat` 用**裸名** `open(newunit,file="compliance.dat",status="replace")`（**行号在 `:287`，L-2 订正：旧稿写 `:248-300`/`:283`**） | 套件 `vib` 任务在**与上游同条件**（`n>1`、无 `$fix`、非周期）下调用同一个 `compliance_driver`（复用，不重写）。⇒ 上游 `--hess`/`--ohess` 有它，套件 `--lvib`（及 `--ohess` 链）也应有。 |

**`--namespace` 交互（上游行为，本轮核到源码）**：

- `.xtboptok` / `xtbopt.log` / `xtblast.xyz` 都经 `open_file`/`touch_file` → `persistentEnv%io%{writeFile,touchFile}` →
  `src/type/iohandler.f90:111-130` 的 `getName` **自动加命名空间**：
  `.xtboptok` → `.ns.xtboptok`（以点开头：`'.'//ns//file`）；`xtbopt.log` → `ns.xtbopt.log`；
  `xtblast.xyz` → `ns.xtblast.xyz`（`generateFileName` 本身不加前缀，但接下来的 `open_file` 加）。
  ⇒ **上游对这三个文件是带前缀的**；套件必须用 `xtb_setparam::get_namespace`（`setparam.f90:589-607`）
  得到同构名字（它实现的是同一条规则：点开头 → `'.'//ns//file`）。
- `compliance.dat` 用**裸** Fortran `open`（`compliance.f90:287`；L-2 订正），**不带**命名空间。
  ⇒ 套件**不得**给它加前缀（否则与上游不一致）。

**测试（各自一行，进 §9.2）**：

| 测试 | 断言 | 反例（突变下应变红） |
|---|---|---|
| `xtb/landscape-file-contract-opt` | 收敛任务后 `.xtboptok` 与 `xtbopt.log` 存在；`.xtboptok` **非空**且无 `NOT_CONVERGED` | 删任一写点 |
| `xtb/landscape-file-contract-opt-fail` | 受限步数（`--cycles 1`，不可收敛）+ `--opt` → **不得**创建 `.xtboptok`；`NOT_CONVERGED` 存在；`xtblast.xyz` 存在且可解析为 xyz | 把 `.xtboptok` 改成无条件 `touch` |
| `xtb/landscape-file-contract-vib` | `--lvib`（水）→ `compliance.dat` 存在且首行含 `compliance.dat`；`--lopt`（→`--opt` 链）亦同 | 去掉 `compliance_driver` 调用 |
| `xtb/landscape-file-contract-namespace` | `--namespace c1 --opt` → 存在 `c1.xtbopt.log`/`.c1.xtboptok`；**不**存在裸 `xtbopt.log`/`.xtboptok`；`compliance.dat` **不**带前缀 | 改用 `get_namespace` 以外的裸名（旧 N-1 缺陷同类） |

### 3.10 【R5 新增】新档位语义的影响面：既有测试与已验收数字的**再基线清单**

> `e_tol`/`acc`/`max_steps` 随档位变化后，**所有**跑在某个档位（含默认 `normal`）上的数值都可能移位。
> 实施阶段 3 必须：**先列清单 → 逐个重测 → **只**在有意处更新 golden 值，并在报告里贴前后对比**。

**受影响的既有测试**（本机 `grep` 全命中，file:line）：

- **单元测试**（直接调 `set_conv_level`）：`test_landscape_settings.f90:285-318`（`test_convergence_levels`，需**补 `e_tol` 断言**）、
  `test_landscape_optimize_math.f90:384/503/550/892/978`、`test_landscape_cg.f90:208`、
  `test_landscape_e2e.f90:182/315/573`、`test_landscape_scan.f90:1190/1478/1536/1600/1703`。
  这些用例多数断言"是否收敛/步数"，因此 `e_tol` 变松（loose/superloose）会**减少步数**，可能导致断言失效。
- **CLI 测试**：`landscape_cli_check.py:558`（`check_thermo`，`--lopt-level tight`）、`:721`（`check_thermo_knobs`）、
  `:1218/:1265`（`--lscan-level loose`）、`:1663/:1680/:1694`（`check_opt_namespace`，loose/vtight，断言"两命名空间结果不同"，应仍成立）；
  `landscape_e2e_check.py:117/119/125`（各任务默认档）、`:243/:311`、`:552`（`--lts-level superloose`）。
- **CMake 脚本测试**：`test/unit/CMakeLists.txt:177,245,265,280,539,545,560,999,1031,1696`；
  `1782-1810`（`--lirc-level` 端点弛豫：断言 vtight 比 superloose **弛豫更多**——`acc` 变紧后应仍成立，但步数会变）。

**已验收数字的再基线**（来自 AGENTS §2 与各里程碑报告）：

| 里程碑 | 依赖的档位 | 需重测的项 |
|---|---|---|
| M2 scan | `loose`/`vtight` hysteresis 数据（`m2-hysteresis-data/` 77 文件） | 滞回最大值、约束残差、默认档对比 |
| M3 vib | `normal`（默认） | 频率（`--lvib` vs `--hess` 差异）、`e_tol` 不影响 vib？（Hessian 路径不读 `e_tol`，但 `--lopt` 前置优化会） |
| M4 saddle | 默认档 | MB RMSD 6.3022e-06、dimer vs prfo 7.7397e-05、虚频数值 |
| M6 IRC | `hpc` 默认 + `--lirc-level` | 四方法端点、`--lirc-level` 端点弛豫步数 |
| M7 验收 | 默认档 | `--hess` 对比 dfreq（0.0100/0.0600 cm⁻¹）、dZPE/dH/dG |

**降低爆炸半径的机制（设计已含）**：

1. `--acc <x>` 显式时**优先**（§3.5 优先级规则）——可在重测时钉住 `acc` 以隔离 `e_tol` 的影响。
2. `--cycles N`/`--lopt-max-steps N` 显式时**优先**——可钉住步数预算。
3. 建议实施时**分两步**：**3a** 先只把 `e_tol` 纳入 `set_conv_level`（最小、可单独重基线）；
   **3b** 再接 `acc`/`max_steps`（依赖 3a 的基线）。两步各自可独立验收。

### 3.10b 【R5 新增】`--cycles` 映射表

**上游读点**：`main.F90:1955` `case('--cycles')` → `set_opt(env,'maxcycle',sec)` → `set%optset%maxoptcycle`
（`set_module.f90:1822-1830`），被 `optimizer.f90:335-337` 读取并**覆盖** `get_optthr` 的 maxcycle。
套件**不读** `set%optset%maxoptcycle` ⇒ C 之后 `--opt --cycles N` 会静默失效 ⇒ 必须映射或报错。

| run type | `--cycles N` 映射目标 | 备注 |
|---|---|---|
| `--lopt` / `--opt`(套件) | `lopt_settings%max_steps = N` | 直接覆盖档位派生的预算 |
| `--lscan` | `lscan_settings%max_steps = N` | 内层弛豫预算（§6.2 #25 `--lscan-max-steps` 同字段） |
| `--lts` | `ts_settings%max_steps = N` | 同 `--lts-max-steps` |
| `--lirc` | `lirc_settings%max_steps = N` | 同 `--lirc-max-steps`（路径预算） |
| `--lvib` | **响亮报错**：`--cycles has no meaning for --lvib (the frequency task has no step budget)` | 无对应概念 ⇒ `env%error`（exit 1） |
| 未改派原生 runtyp，**以及 `--opt`/`--ohess --method <native>`**（R24） | 保持原生语义（`set%optset%maxoptcycle`） | 同现状；判据 = `landscape_native_engine /= 0`（§3.11 读点表 #8） |

**优先级**：显式 `--cycles N` **优先于**档位派生的 `max_steps`，但**低于**任务专有旗标
（`--lopt-max-steps`/`--lscan-max-steps`/`--lts-max-steps`/`--lirc-max-steps`）：若二者都给且**异值** → `env%error`
（同值幂等），消息点名两个旗标（§4.3 规则 2 的同构）。

**测试**：`xtb/landscape-cycles-map`：同一分子 `--lopt --cycles 8` 与 `--lopt --lopt-max-steps 8` 的
`landscape_opt.json` `counters.n_steps` 相同、并小于默认；`xtb/landscape-cycles-lvib` 断言 `--lvib --cycles 8` 非零退出；
`xtb/landscape-cycles-conflict` 断言 `--lopt --cycles 8 --lopt-max-steps 9` 非零退出。

### 3.11 【R16 新增；R22/R24 重写】runtyp 机制定义（M8）：`--opt`/`--ohess` 与套件任务的**身份关系**

**问题**（复核 M8）：C 方案要"改派 `--opt` 到套件"，但套件的所有守卫/分派都按 `set%runtyp == p_run_lopt/...` 判定；
若把 `--opt` 直接 `set_runtyp('lopt')`，则 `--opt` 与 `--lopt` 变成**同一** runtyp ⇒
(a) 无法实现 C2（`--opt --lopt` 双 runtyp 冲突）；(b) `set_runtyp` 的 `save` 锁会对"第二个旗标"静默 raise（`set_module.f90:1034-1038`）。

**决策 1（设计）：不合并 runtyp**。保留 `p_run_opt=4` / `p_run_ohess=7`（`setparam.f90:200,202`）；
改派只改变"它们被**谁**执行"，不改变它们**是**什么。

**决策 2（R22 重写 H-2）：原生分派是单一整数标志，取值域就是 4 个原生引擎。**
旧稿的两个逻辑标志（`landscape_native_ancopt` / `landscape_opt_alias`）**作废**：

1. `landscape_native_ancopt` **只认 `ancopt`**，把 `--opt --method lancopt|fire` 判成"套件任务" ⇒ §3.8 的三条守卫
   对**原生** L-ANCopt/FIRE **误报**（复核 H-2）。
2. `landscape_opt_alias` 是第二个状态位，与谓词不同源 ⇒ 两条判据可以不一致（同一类缺陷）。

取而代之（`program xtb` 的局部变量，与 `lruntyp_flag` 并列；由 `parseArguments` 的解析尾归一写入
（§4.7）并作为 `intent(out)` 参数回传——**不进 `set%`、不新增 runtyp、不引入模块级可变变量**）：

```
!> Native ANCopt-family dispatch of the redeployed `--opt`/`--ohess`.
!> 0 = the run goes to the landscape suite.  Otherwise the identifier of the
!> native engine, i.e. one of `p_engine_rf` / `p_engine_lbfgs` /
!> `p_engine_inertial` / `p_engine_pbc_lbfgs` (`src/setparam.f90:77-80`).  The
!> value set is exactly the `$opt engine=` keyword set of
!> `set_module.f90:1888-1891`, so there is one authoritative mapping.
integer :: landscape_native_engine = 0
```

**为何"单一标志 + 4 个取值"就足够（H-2 的修法）**：

- 所有判定只问一句 "**是原生还是套件**"：`landscape_native_engine /= 0`；
- **禁止**把它写成 `== p_engine_rf`（那就是把取值域退化成 1 个值的 H-2 错法）；§14.7 为该错误写法指定了反例测试；
- 三条守卫（§3.8 a/b/c）、`[NOTICE]`（BC-5）、`--cycles` 映射（§3.10b）、`--ljson` 判定（§5.3）、
  原生 `if (anyopt)` 抑制（M-3）**全部**读它，没有第二个状态位。

**派生谓词（`main.F90` 的纯函数，便于单测）**：

```
!> Landscape task executed by this run; 0 = native run type / no suite task.
integer function effective_landscape_task(runtyp, native_engine)
   if (runtyp == p_run_opt .or. runtyp == p_run_ohess) then
      if (native_engine /= 0) then
         effective_landscape_task = 0             ! native ANCopt family
      else
         effective_landscape_task = p_run_lopt   ! redeployed to the suite
      end if
   else if (runtyp == p_run_lopt .or. runtyp == p_run_lscan .or. runtyp == p_run_lts .or. &
            runtyp == p_run_lirc .or. runtyp == p_run_lvib) then
      effective_landscape_task = runtyp
   else
      effective_landscape_task = 0                ! un-redeployed native run type
   end if
end function

!> TRUE iff this run is a suite task (the single criterion of the §3.8 guards).
logical function landscape_is_suite_run(runtyp, native_engine)
   landscape_is_suite_run = effective_landscape_task(runtyp, native_engine) /= 0
end function

!> TRUE for the redeployed `--ohess`, which is the opt chain *followed by* the vib chain.
logical function landscape_ohess_chain(runtyp, native_engine)
   landscape_ohess_chain = runtyp == p_run_ohess .and. native_engine == 0
end function

!> TRUE iff the **native** numerical Hessian / frequency path of this run
!> executes: `--hess` and `--bhess` unchanged, and `--ohess` only in its
!> native half (`--ohess --method ancopt|...`).  This is the single criterion
!> of the three readers `main.F90:1156`, `:1282` and `:4065`; the redeployed
!> `--ohess` gets its Hessian from the suite vib chain instead (`R29`,
!> HIGH-1).
logical function landscape_native_hessian_path(runtyp, native_engine)
   integer, intent(in) :: runtyp       !> `set%runtyp`
   integer, intent(in) :: native_engine !> `landscape_native_engine` (0 = suite)
   select case (runtyp)
   case (p_run_hess, p_run_bhess)
      landscape_native_hessian_path = .true.
   case (p_run_ohess)
      landscape_native_hessian_path = native_engine /= 0
   case default
      landscape_native_hessian_path = .false.
   end select
end function
```

**读点全表（改派标志的每一处读者；实施时按这张表搜一遍即可保证无遗漏）**：

| # | 读点 | 位置（file:line） | 用哪个谓词 |
|---|---|---|---|
| 1 | `$scan` 守卫 | `main.F90:491-510`（`select case (set%runtyp)` 加 `p_run_opt`/`p_run_ohess` 分支） | `landscape_is_suite_run` |
| 2 | 周期守卫 | `main.F90:491-510`（与 #1 同一块；L-4 措辞统一） | `landscape_is_suite_run` + `mol%npbc > 0` |
| 3 | xcontrol `$opt` 守卫 | 同上（#1/#2 同一块） | `landscape_is_suite_run` + `set%optset%xcontrol_supplied`（§3.8c） |
| 4 | **原生优化块抑制（M-3）** | `main.F90:931`：`if (anyopt)` → `if (anyopt .and. landscape_native_engine /= 0)` | `native_engine` |
| 5 | 套件任务分派（ 5 处） | `main.F90:989`（lopt）、`:1012`（lscan）、`:1028`（lts）、`:1058`（lirc）、`:1077`（lvib） | `effective_landscape_task` |
| 6 | `--ohess` 的 vib 链 + `fres` 桥 | `main.F90:989-1008` 的 `p_run_lopt` 分派块内、`res%e_total = lres%energy`（`:1003-1005`）写回**之后**、`end if`（`:1008`）**之前**（该块的进入条件改为 `effective_landscape_task(...) == p_run_lopt`） | `landscape_ohess_chain` |
| 7 | `--ljson` 判定（§5.3） | `main.F90:982-987` | `landscape_is_suite_run` |
| 8 | `--cycles` 映射（§3.10b） | `--cycles` 处理处 | 套件 → 映射；原生（含 `--opt --method <native>`）→ 保留 `set%optset%maxoptcycle` |
| 9 | `[NOTICE]`（BC-5） | 套件分派前 | `set%runtyp ∈ {opt,ohess} .and. native_engine == 0` |
| 10 | **原生数值 Hessian（R29/T1）** | `main.F90:1156` 的 `if (runtyp == hess .or. ohess .or. bhess)`（块内 `:1170 call numhess`） | `landscape_native_hessian_path` |
| 11 | **原生频率打印（R29/T2）** | `main.F90:1282-1285`（`call generic_header` + `:1284 call main_freq`） | `landscape_native_hessian_path` |
| 12 | **`fres` 的三个读者（R29/T3）** | `main.F90:1300-1306`（`set%property_file` 的 `write_energy`）、`:1287-1298`（`xtbout.json`）、`:1324`（stdout 的 `write_energy`） | **判据不改**（仍 `anyhess`）：由套件 vib 链的 **`fres` 桥**保证容器被填（§3.11.1） |
| 13 | 原生 `xtbopt.xyz` 二次写（L-4） | `main.F90:1310-1320` | `landscape_is_suite_run`（套件运行不再二次写 + 不再打第二行提示） |
| 14 | 计时标签（L-4） | `main.F90:4065-4071` | `landscape_is_suite_run`（套件 ⇒ `landscape optimizer`；原生 ⇒ 保持 `ANC optimizer`） |
| 15 | 原生 `main_geometry`（L-4） | `main.F90:1276-1280` | **保留、不读任何判据**（与今天原生 `--opt`/`--ohess` 的输出同形；实测见 §16.6 L-4） |

**`--ohess` 的双阶段**：不是新 runtyp。`effective_landscape_task -> p_run_lopt` 跑 opt 链，
再由 `landscape_ohess_chain` 为真时接 vib 链（与上游 `main.F90:1279,1284` 的 `main_geometry` + `main_freq`
两调用**同构**）。`--ohess --ljson` 写 `landscape_opt.json`（opt 阶段）。

#### 3.11.1 【R29 新增】HIGH-1 闭合：`--ohess`(套件) 的**三个原生触发点**逐个处置

复核 15 HIGH-1 的论断**逐字复核成立**（我读了 `main.F90:270,1156,1170,1276-1285,1300-1324,4065-4071`）：
原生 Hessian/频率路径**按 `set%runtyp` 触发**，而 `--ohess`(套件) 的 runtyp **仍是 `p_run_ohess`**（决策 1）⇒
只抑制 `:931`（M-3）会让同一个 `--ohess` 跑**两遍** Hessian/频率，`hessian`/`vibspectrum`/`g98.out` 各写两次（后写覆盖前写）。

**唯一新增判据（不新增状态位）**：§3.11 的纯函数 `landscape_native_hessian_path(runtyp, native_engine)`
（取值表：`hess`/`bhess` ⇒ `.true.`；`ohess` ⇒ `native_engine /= 0`；其余 ⇒ `.false.`）。

| # | 触发点（现状行） | 现状判据 | 判据 | 改动位置（file:line） | 对套件 `--ohess` 的效果 |
|---|---|---|---|---|---|
| **T1** | `main.F90:1156`：`if ((runtyp == p_run_hess) .or. (runtyp == p_run_ohess) .or. (runtyp == p_run_bhess)) then`（块内 `:1161` PBC 报错、`:1170 call numhess`） | runtyp 三元 | `landscape_native_hessian_path` | 替换 `:1156` 的整个条件 | 不再调 `numhess` ⇒ 不再产生第二份 `fres`/`hessian`/`xtbhess.xyz`/`compliance.dat`，台账不再写两遍 |
| **T2** | `main.F90:1282-1285`：同一 runtyp 三元 + `:1283 generic_header(iprop,'Frequency Printout',...)` + `:1284 call main_freq(iprop, mol, chk%wfn, fres)` | runtyp 三元 | `landscape_native_hessian_path` | 替换 `:1282` 的条件 | 不再调第二个 `main_freq` ⇒ `vibspectrum`/`g98.out`/热力学表**只由套件 vib 链写一次** |
| **T3** | `main.F90:270` `anyhess = (runtyp == hess) .or. (runtyp == ohess) .or. (runtyp == bhess)` → 读点 `:1304`（属性文件 `write_energy`）、`json.F90:102/111`（`xtbout.json`）、`:1324`（stdout `write_energy`） | runtyp 三元 | **判据不改**（仍 `anyhess`）；改为**保证被读的容器 `fres` 在套件 `--ohess` 下被填满**（`fres` 桥，见下） | `:270` **不动**；新增桥（在套件 vib 链之后，同一分派区内） | 三处读者拿到套件的 H(T)/G(T)/`freq`，输出与原生 `--ohess` **同形**；不存在"半修"风险 |

**为何 T3 不能把 `anyhess` 置假（本节对复核建议的偏离，给实测理由）**：

1. `anyhess` 的语义不是"原生路径跑了"，而是"**频率结果容器会被打印**"——它的另外三个读者（`:1304`、`json.F90:102/111`、`:1324`）都不看哪个路径填的。
2. 置假会静默改变 `--ohess` 的**控制台契约**（不属于已入册的 16 条）：**实测**（本轮，`/tmp/w2-h1-probe`）原生 `--ohess normal` 的 stdout 含
   `| TOTAL ENTHALPY  -5.046634777445 Eh |` / `| TOTAL FREE ENERGY -5.068040873597 Eh |`，而套件 `--lvib`（同一水分子）的 `write_energy` 块**只有** `TOTAL ENERGY` + `GRADIENT NORM`（`hess=.false.`，`property.F90:36-57`）。⇒ 置假就是让 `--ohess` 少两行。
3. 置假还会让 `--ohess --json`（`set%pr_json`，`main.F90:1287-1298`）与 `set%property_file` 静默丢掉热化学键。
⇒ **选择：`anyhess` 保持不动 + 套件填 `fres`**（与 M7 已建立的"套件→原生容器"链同一手法：`vib/thermo.f90:115-175` 把总数写进 `freq_results`）。

**`fres` 桥（要在阶段 3 实施的最小代码；此处给字段与写点）**：

1. `src/landscape/types/results.f90:279-322` 的 `landscape_result` 加一个组件 `type(landscape_vib_result) :: vib`（该类型所有组件都有默认初值，`:60-106`；**无** `character(len=:),allocatable` 组件，所以普通派生类型赋值安全，AGENTS §6.5 的 gfortran 缺陷不适用于它）；
2. `src/landscape/tasks/vib.f90` 在拿到 `energy`（`:155 landscape_vib_hessian` 之后）把它写进结果：`landscape_vib_result` 加 `real(wp) :: energy = 0.0_wp`（**有效初值**，否则 `htot/gtot` 会差一个 SCF 重启级别的小量，AGENTS §6.2：warm 重启 3.9e-07 Eh/bohr），并在任务末尾 `result%vib = vib`；
3. `src/prog/main.F90` **在 `:989-1008` 的 `p_run_lopt` 分派块内**（进入条件改为 `effective_landscape_task(set%runtyp, landscape_native_engine) == p_run_lopt`）、**vib 链之后且 `res` 写回（`:1003-1005`）之后**，条件是 `landscape_ohess_chain(set%runtyp, landscape_native_engine)`：

```
call fres%deallocate();  call fres%allocate(mol%n)   ! 不用 `fres = ...` 整对象赋值
fres%n3true = 3*mol%n ; fres%linear = lres%vib%linear
fres%freq  = lres%vib%freq ; fres%rmass = lres%vib%rmass ; fres%hess = lres%vib%modes
fres%dipt  = 0.0_wp ; fres%polt = 0.0_wp             ! 无偶极/极化率导数（与 --lvib 同）
fres%etot  = lres%vib%energy ; fres%gnorm = lres%gnorm
fres%htot  = lres%vib%enthalpy - lres%vib%energy      ! write_energy 打印 etot+htot
fres%gtot  = lres%vib%gibbs    - lres%vib%energy
fres%zp    = lres%vib%zpe ; fres%temp = lres%vib%temperature ; fres%nimag = lres%vib%n_imag
```

（`property.F90:44-49` 打印 `frqres%etot + frqres%htot` = 总 H(T)、`+ frqres%gtot` = 总 G(T)；`landscape_vib_result%enthalpy/gibbs` 是**总数**，所以这里减掉电子能得热贡献 —— 与 M7 的约定一致。`vib%freq`/`vib%modes`/`vib%rmass` 的长度实测 = 3n：`vib/modes.f90:300`。）

**自证（逐行代入现有实现，两边必须同时成立）**：

| # | 命令行 | `set%runtyp` | `landscape_native_engine` | `landscape_native_hessian_path` | T1 `numhess` | T2 `main_freq` | `landscape_ohess_chain` | T3 `anyhess` + `fres` | 结果 |
|---|---|---|---|---|---|---|---|---|---|
| A | `--ohess`（套件） | `p_run_ohess`（`main.F90:2166`） | **0**（无 `--method`；§4.7 第 2 段第一行赋 0） | `.false.`（`case(p_run_ohess)` → `0 /= 0` 假） | **跳过** ✓ | **跳过** ✓ | `.true.` ⇒ 套件 opt+vib 各一次 ✓ | `anyhess` 真，`fres` 由桥填 ✓ | **恰好一次** Hessian/频率；stdout 与原生同形 |
| B | `--ohess --method ancopt`（原生） | `p_run_ohess` | `p_engine_rf` = 1 | `.true.`（`1 /= 0`） | **执行** ✓ | **执行** ✓ | `.false.` ⇒ 套件 vib 链**不**跑 ✓ | `anyhess` 真，`fres` 由原生 `numhess` 填 ✓ | 与今天逐位同 |
| C | `--hess` / `--bhess` | `p_run_hess`/`p_run_bhess` | 0 | `.true.`（第一个 case，与 `native_engine` 无关） | 执行 ✓ | 执行 ✓ | `.false.` | 同今天 | **不变** |
| D | `--opt`（套件） | `p_run_opt` | 0 | `.false.`（`default`） | 跳过（本来也跳） | 跳过（本来也跳） | `.false.`（runtyp ≠ ohess） | `anyhess` **假**（与今天同） | **不变** |
| E | `--lvib` / `--lopt` 等 | `p_run_lvib`/… | 0 | `.false.` | 跳过 | 跳过 | `.false.` | `anyhess` 假 | **不变**（`--lvib` 自带 H(T)/G(T) 行，见 `tasks/vib.f90`；**有意不**用桥） |
| F | `--ohess --method fire` + 周期 GFN-FF | `p_run_ohess` | `p_engine_inertial` ≠ 0 | `.true.` ⇒ 原生 `numhess` 跑到 `:1161` 的 PBC 报错 | — | — | `.false.` | 同 B | 与今天**同样**报错（无新缺陷） |

⇒ **抑制条件同时区分了两边**：同一 `landscape_native_engine`（0 与非 0）决定了 T1/T2 的取舍，
而 T3 的对侧由 `landscape_ohess_chain` 保证（套件链跑的时候原生链一定不跑，反之亦然）。

**测试（4 条；判别 token 全部本轮实测，环境 `/tmp/xtb-w2/build/xtb` + `OMP_NUM_THREADS=1` + 非周期水）**：

| 测试 | 命令 | 断言 | 可注入的突变（变红） |
|---|---|---|---|
| `xtb/landscape-ohess-suite-once` | `--ohess normal` | exit 0；`Numerical Hessian` = **0**（实测原生为 1）、`Frequency Printout` = **0**（原生 1）、`ANC micro-cycles` = **0**（原生 1）、`landscape: harmonic frequencies` = **1**、`landscape engine: Hessians` 行 = **1**；`hessian`/`vibspectrum`/`g98.out` 存在 | 去掉 `:1156` 的谓词 ⇒ `Numerical Hessian`=1 ⇒ 红；去掉 `:1282` 的 ⇒ `Frequency Printout`=1 ⇒ 红；去掉 `:931` 的（M-3）⇒ `ANC micro-cycles`=1 ⇒ 红 |
| `xtb/landscape-ohess-native-hess` | `--ohess --method ancopt` | exit 0；`Numerical Hessian` = 1、`Frequency Printout` = 1、`landscape: harmonic frequencies` = 0（**反向**：抑制必须放过原生） | 把谓词写成恒 `.false.`（例如只看套件）⇒ 原生侧不跑 `numhess` ⇒ `hessian` 不写/无 `Numerical Hessian` ⇒ 红 |
| `xtb/landscape-ohess-fres-bridge` | `--ohess normal`，再对同一末几何跑 `--lvib` | 前者的 `TOTAL ENTHALPY`/`TOTAL FREE ENERGY` 行存在，且与后者的 `total enthalpy H(T)` 一致（≤1e-6 Eh）；`TOTAL ENERGY` ≠ 0 | 删掉桥（或把 `anyhess` 置假）⇒ 前者只剩 `TOTAL ENERGY` + `GRADIENT NORM` ⇒ 红；**半修**（`anyhess` 真但不填 `fres`）⇒ 打印 `TOTAL ENERGY 0.000000000000` ⇒ 红 |
| `xtb/landscape-opt-xtbopt-once`（L-4） | `--opt`（套件） | exit 0；`optimized geometry written to:` = **0**、`wrote xtbopt.xyz` = 1；`xtbopt.xyz` 只被一个写点写 | 去掉 `:1310-1320` 的抑制 ⇒ 两行提示都出现（实测原生 `--ohess` 今天打 `optimized geometry written to:` **1** 次，套件 `--lopt` 打 `wrote xtbopt.xyz` **1** 次）⇒ 红；`--opt --namespace c1` 时 `c1.xtbopt.xyz` 仍只写一次 |

> **对复核的一处机制订正（附证据）**：复核写"只抑制 `:1156` 而忘了 `:270 anyhess` ⇒ `:1324` 会用未分配的 `fres` 打印频率块（**半修即崩**）"。
> **不崩**：`fres` 是 `type(freq_results)`（`src/type/data.F90:105-129`），**每个标量都有默认初值 `= 0.0_wp`/`= 0`**，所以 `write_energy`（`property.F90:36-57`）读到的是 `0.0`；
> `xtbout.json` 的数组分支由 `freqres%n3true > 0` 挡住（默认 `0`，`json.F90:111`），所以不会碰到未分配的 `freq`。
> 本轮用一个 10 行 gfortran 程序（镜像同样的默认初值，`/tmp/w2-h1-probe/frag.f90`）**实测**：`allocated(freq)=F`、`n3true=0`、`etot=htot=gtot=0.000000000`。
> ⇒ 半修的真实后果是**静默错数**（`TOTAL ENERGY 0.000000000000`），比"崩"更难发现 —— 所以本设计用 `fres` 桥把这个半修空间**结构性地**消掉（`xtb/landscape-ohess-fres-bridge` 就是它的守卫）。

#### 3.11.2 【R30 新增】全部新增状态位的确定初值（MEDIUM-1）

复核 15 MEDIUM-1 要求："检查**所有**新增状态位是否都有确定初值"。逐项作答（这就是实施前的清单）：

| 变量 | 声明处（设计后） | 初值 | 何时被写 | 读到未定义值的可能性 |
|---|---|---|---|---|
| `landscape_native_engine::integer` | `main.F90` `program xtb` 局部（与 `lruntyp_flag` 并列）+ `parseArguments` 的 `intent(out)` dummy | 声明 `= 0`；**且** `parseArguments` 的 **flag 循环之前**（`main.F90:1574` 前一行）无条件 `landscape_native_engine = 0` | 解析尾段（`:3882-3889` 之后）；第 2 段的**两个分支都写**（原生名写 `p_engine_*`，套件名写 `0`；未给 `--method` 时靠循环前那行） | **无**（`intent(out)` 进入即未定义，所以循环前的那行是必需的，声明初值**不**足以保护——这就是 MEDIUM-1） |
| `landscape_method_name::character(:),allocatable` | `main.F90` 局部 | 未分配（默认） | 只在 `case('--method')` | 无（所有读点都在 `allocated()` 保护内，`main.F90:3882` 的前置 `if`） |
| `landscape_native_hessian_path` / `effective_landscape_task` / `landscape_is_suite_run` / `landscape_ohess_chain` / `landscape_native_engine_from_name` | `main.F90` 纯函数 | 不适用（每次调用都走 `select case`，**每个分支都赋值**，`case default` 也赋） | — | 无 |
| `fres::freq_results`（既有） | `main.F90:142` | 全部标量默认初值（`data.F90:105-129`），数组未分配 | 原生 `numhess` **或**套件 `fres` 桥 | 无"读未分配数组"路径（只有标量读点，`json.F90:111` 有 `n3true > 0` 守卫）；**值可能静默为 0** ⇒ 由桥测试守住 |
| `lres%vib::landscape_vib_result`（新增组件） | `results.f90:279-322` | 全部组件默认初值（`:60-106`），数组未分配 | `tasks/vib.f90` 末尾 | 无（非 vib 任务从不读它） |
| `landscape_vib_result%energy::real(wp)`（新增字段） | `results.f90:60-106` | `= 0.0_wp` | `tasks/vib.f90` 拿到 `energy`（`:155`）之后 | 无（但**必须**写，否则 `htot/gtot` 差一个 SCF 重启量级） |
| `set%optset%xcontrol_supplied::logical`（U13/R28） | `setparam.f90:262-270` | `= .false.` | `set_module.f90:797` 的 `case('opt')` 分派前一行 + `set_legacy`（`:2811-2928` 的 opt 键） | 无（默认 `.false.` 是脚本的模块级初值，`save` 语义下每进程只初始化一次） |
| `acc_was_set::logical`（R27/L-5） | `main.F90` `program xtb` 局部 | `= .false.` | `case('-a','--acc')`（`main.F90:1665`） | 无（声明初值即可，它不经 `intent(out)` dummy） |

> **实施前的静态核（可 `grep`）**：`grep -n "landscape_native_engine" src/prog/main.F90` 必须命中
> ①声明行（带 `= 0`）②flag 循环前那行 ③第 2 段的两处赋值；实现报告里贴这段输出（本轮 M-2 的教训：声称必须可核）。

**M-3（R24）：既有原生分支必须显式抑制，否则同一个 `--opt` 会跑两次**

- 事实：`--opt`(套件) 的 runtyp 仍是 `p_run_opt`，所以 `anyopt`（`main.F90:317`：
  `runtyp == opt/ohess/omd/screen/metaopt`）**仍为真**；不改 `:931`，原生 `geometry_optimization`
  （`:943`）与套件 `run_landscape`（`:989` 分支）会**各跑一次**。
- 抑制只加在 `:931`：`if (anyopt .and. landscape_native_engine /= 0) then`。
- `anyopt` 的另外两个读点 —— `:321`（CPCM-X）与 `:326`（PTB）的 `env%terminate` 守卫 —— **保持原样**：
  它们的语义是"原生优化器不支持 X"，对改派后的 `--opt` 保守报错才是正确的（套件分派路径本身没有 CPCM-X/PTB 链）——
  **L-6 措辞订正**：不是"套件无 CPCM-X/PTB 路径"（CPCM-X 的 post-SCF 块 `:1197-1216` 不受 runtyp 守卫，
  `--lopt --cpx <solvent>` 今天确实会算），而是"改派不改变这两个 terminate 读点的行为"。
- 原生 ANCopt/FIRE/L-ANCopt/pbc_lbfgs（`native_engine /= 0`）⇒ `:931` 仍为真 ⇒ 原生路径不变。
- **断言"只跑一次"的判据（本轮实测）**：套件路径在 stdout 打 `landscape: lbfgs minimisation`
  （`tasks/opt.f90:108`）且写 `landscape_opt.json`；原生 ANCopt 在 stdout 打 `ANC micro-cycles`
  （`optimizer.f90:392`）且 **不**写 json（见 §9.2 的 `xtb/landscape-opt-alias-once`）。
- **R29 补充（HIGH-1）**：同一个 `--opt`/`--ohess` 改派在 `--ohess` 侧还有**三个**原生 Hessian/频率触发点
  （`main.F90:270`/`:1156`/`:1282`），必须按 §3.11.1 的 T1/T2/T3 一并处理；
  此外 `main.F90:1310-1320`（原生 `xtbopt.xyz` 二次写）与 `:4065-4071`（计时标签）也进入抑制集合（读点表 #13/#14）。

**影响面清单**：所有用 `set%runtyp == p_run_l*` 的既有守卫（`--ljson` 消息、`$scan` 守卫、PBC、`landscape_driver.f90:73`）
改为调用上表谓词（或保留 `p_run_l*` 分支并**额外**处理 `opt/ohess`）。这一条就是复核要求的 M8 "runtyp 机制定义"。

**四问四答（本轮任务书点名）**：

| 问题 | 答案 |
|---|---|
| `--opt --method ancopt` 怎么办？ | `native_engine = p_engine_rf` ⇒ 原生（§4.7 出口 1）；守卫均不触发 |
| `--ohess --method ancopt` 呢？ | `p_run_ohess` 命中同一 case ⇒ 原生 opt + 原生 `main_freq`（§4.7 出口 5） |
| `--lopt --method ancopt` 允许吗？ | **不允许**，`env%error` 点名 `--opt`（§4.7 出口 7 的理由） |
| 与 `set_runtyp` 的"首个 runtyp 锁"如何共存？ | `--method` **从不**调 `set_runtyp`（§4.7），所以锁只由 runtype 旗标消耗；`--method` 在解析尾读 `set%runtyp`，与旗标顺序无关 |

---

## 4. 统一方法选择器 `--method <name>`

> **本节不依赖 §3 的 A/B/C/D 决策**：`--method` 的取值域、作用域、优先级规则在任何方案下一致。

### 4.1 取值域（只列**套件真实实现**的方法，逐条 `file:line`）

**最小化器**（6 个）— `src/landscape/types/settings.f90:79-84`（枚举）与 `:1112-1135`（`from_name`）：

| 名字 | 枚举 | 解析点（`[R17]` 修正 +2 偏移） | 实现文件 |
|---|---|---|---|
| `sd` | `p_landscape_opt_sd`=1 | `settings.f90:1119` | `src/landscape/optimize/sd.f90` |
| `cg` | `p_landscape_opt_cg`=6 | `settings.f90:1121` | `src/landscape/optimize/cg.f90` |
| `lbfgs` | `p_landscape_opt_lbfgs`=2 | `settings.f90:1123` | `src/landscape/optimize/lbfgs.f90` |
| `bfgs` | `p_landscape_opt_bfgs`=3 | `settings.f90:1125` | `src/landscape/optimize/bfgs.f90` |
| `diis` | `p_landscape_opt_diis`=4 | `settings.f90:1127` | `src/landscape/optimize/diis.f90` |
| `rfo` | `p_landscape_opt_rfo`=5 | `settings.f90:1129` | `src/landscape/optimize/rfo.f90` |

**鞍点 / TS 方法**（8 个）— `settings.f90:1295-1322`：

| 名字 | 枚举 | 解析点 | 实现文件 |
|---|---|---|---|
| `prfo` | `p_landscape_ts_prfo` | `settings.f90:1302` | `src/landscape/saddle/prfo.f90` |
| `bprfo` | `p_landscape_ts_bprfo` | `settings.f90:1304` | `src/landscape/saddle/bprfo.f90` |
| `dimer` | `p_landscape_ts_dimer` | `settings.f90:1306` | `src/landscape/saddle/dimer.f90` |
| `neb` | `p_landscape_ts_neb` | `settings.f90:1308` | `src/landscape/path/neb.f90` |
| `cineb` | `p_landscape_ts_cineb` | `settings.f90:1310` | `src/landscape/path/cineb.f90` |
| `autoneb` | `p_landscape_ts_autoneb` | `settings.f90:1312` | `src/landscape/path/autoneb.f90` |
| `string` | `p_landscape_ts_string` | `settings.f90:1314` | `src/landscape/path/string.f90` |
| `gsm` | `p_landscape_ts_gsm` | `settings.f90:1316` | `src/landscape/path/gsm.f90` |

**IRC 积分方法**（4 个）— `settings.f90:1229-1248`：

| 名字 | 枚举 | 解析点 | 实现文件 |
|---|---|---|---|
| `gs` | `p_landscape_irc_gs` | `settings.f90:1236` | `src/landscape/irc/gs.f90` |
| `hpc` | `p_landscape_irc_hpc` | `settings.f90:1238` | `src/landscape/irc/hpc.f90` |
| `lqa` | `p_landscape_irc_lqa` | `settings.f90:1240` | `src/landscape/irc/lqa.f90` |
| `eulerpc` | `p_landscape_irc_eulerpc` | `settings.f90:1242` | `src/landscape/irc/eulerpc.f90` |

**原生直通**（**R21 扩到 4 个引擎 / 7 个拼写**（L-1 订正：旧稿写 8；`lbfgs` 被有意排除，见 §4.7），**仅 §3 的 C/B/D 方案下有意义**）：

| 名字 | 语义 | 依据（`file:line`；**R28 校订**） |
|---|---|---|
| `ancopt`（+ 上游拼写 `rf`，R21 补） | 上游 ANCopt（`set%opt_engine = p_engine_rf`，`setparam.f90:77`） | `src/optimizer.f90:122`（`subroutine ancopt`；`[R17]` 旧稿写 121 = 注释行）；出口 `src/geoopt_driver.f90:148-153`（`case(p_engine_rf)` → `call ancopt`） |
| `lancopt`（R9 新增，别名 `l-ancopt`） | L-ANCopt（`set%opt_engine = p_engine_lbfgs`，`setparam.f90:78`） | **`src/relaxation_engine.f90:400`**（`subroutine l_ancopt`；**R28 订正：旧稿写 `optimizer.f90`，那里没有这个子程序**）；出口 `geoopt_driver.f90:155-158`；`set_module.f90:1889` `lbfgs\|l-ancopt`（**原生只取 `l-ancopt`**，裸 `lbfgs` 留给套件，§4.7） |
| `fire`（R9 新增，别名 `inertial`） | FIRE（`set%opt_engine = p_engine_inertial`，`setparam.f90:79`） | **`src/relaxation_engine.f90:131`**（`subroutine fire`；**R28 订正**）；出口 `geoopt_driver.f90:169-171`（**L-2 订正：旧稿写 166-168**）；`set_module.f90:1891` `inertial\|fire`（**L-2 订正：旧稿写 1890，1890 是 `pbc_lbfgs`**） |
| `pbc_lbfgs`（R9 新增；**R21 改语义：它是真正的原生出口，不再“仅报错”**） | 周期 L-BFGS（`set%opt_engine = p_engine_pbc_lbfgs`，`setparam.f90:80`）。`--opt --method pbc_lbfgs` 走**原生**，实测在**非周期**水上 exit 0（§13b）；它**同时**是套件侧周期守卫给用户的提示名（§3.8b） | `set_module.f90:1890`；出口 `geoopt_driver.f90:159-166`（`case(p_engine_pbc_lbfgs)` → `call relax_pbc`，实现在 `src/lbfgs_anc/driver.f90:39`） |

> **R9（H5）说明**：`--method` 的出口集合从 1 个（`ancopt`）扩到 **`ancopt`/`lancopt`/`fire`（+别名 `inertial`）/`pbc_lbfgs`**，
> 对齐上游 `$opt engine=` 的 4 个值（`set_module.f90:1888-1891`），使 G12（FIRE/L-ANCopt）**不丢 CLI 可达路径**。
> 这 4 个名字**仅**在 `--opt`/`--ohess` 下合法（§4.8）。
> **R21 订正**：这 4 个都是**真正的原生出口**（`pbc_lbfgs` 不再是"仅报错"）；"报错"的只是**套件**侧的周期守卫
> （§3.8b：`--opt`(套件) + 周期 ⇒ 提示 `--method ancopt`）。这条正是 H-1 要求的"四个出口都不落
> `default`/`env%error`"。

**任务默认**（1 个）：`auto` → 按当前 runtyp 取该任务的默认方法
（opt/scan：`lbfgs` `settings.f90:427,528`；ts：`prfo` `settings.f90:651`；irc：`hpc` `settings.f90:837`）。

**总数 = 6 + 8 + 4 = 18 个套件方法名**（不含 `auto`）。
**R9 扩展**：+ 4 个原生引擎（**R21 后共 7 个拼写**：`ancopt|rf`、`lancopt|l-ancopt`、`fire|inertial`、`pbc_lbfgs`；
**L-1 订正**：旧稿写"8 个拼写"，而 `11:1035` 自己枚举的就是 7 个 —— `set_module.f90:1888-1891` 的 7 个键里裸
`lbfgs` 被有意留给套件（§4.7），所以原生侧只有 7 个拼写）
⇒ 取值域共 **18 套件名 + 7 原生拼写 = 25 个拼写**（不含 `auto`）；
`--method` 对每个套件名在每个任务下的容忍性见 §4.2，原生拼写只在 `--opt`/`--ohess` 下合法（§4.7/§4.8）。

### 4.2 作用域语义（跨任务）与消歧规则

`--method` 是**跨任务的单一选择器**，名字的**含义由当前 runtyp 决定**。
消歧规则（**明确规则，不是猜**）：

```
resolve(--method NAME, runtyp R):
  0. 若 NAME 是原生引擎名（§4.7 的 landscape_native_engine_from_name ≠ 0）
     -> 仅 R ∈ {p_run_opt, p_run_ohess} 合法；结果由解析尾归一设置（§4.7），不经过本函数
  1. 若 NAME == 'auto'            -> R 的默认方法
  2. 若 NAME 属于 R 的容忍集合     -> 设置 R 的方法
  3. 若 NAME 属于别的任务的集合    -> env%error，消息里点名那个任务
  4. 否则                        -> env%error "unknown landscape method"
```

> **R21**：第 0 步的优先级高于一切——原生名**不参与**"名字→任务集合"的消歧（这就是 H-1 的修法），
> 所以 `bfgs`（套件）与 `lancopt`（原生）不会相撞，裸 `lbfgs` 也不会被误认为 L-ANCopt。

**容忍集合**：

| runtyp | 接受的名字集合 |
|---|---|
| `--lopt` | 6 最小化器 + `auto` |
| `--lscan`（`mode=relaxed`） | 6 最小化器 + `auto` |
| `--lts` | 8 鞍点方法 + `auto` |
| `--lirc` | 4 IRC 方法 + `auto` |
| `--opt`（C/B/D） | 6 最小化器 + **4 原生引擎（R21）** + `auto` |
| `--ohess`（C/B/D） | 同上 |
| 任何**未改派**的 runtyp | **不**接受（见 §4.6） |

**同名跨任务的一致性**：`bfgs`/`lbfgs`/`sd`/`cg`/`diis`/`rfo` 在 `--lopt` 与 `--lscan` 下含义
**完全一致**（都指向 `p_landscape_opt_*` 的同一枚举，`settings.f90:79-84`）。
`dimer` 只在 `--lts` 下有定义——它在 `--lopt` 下**不存在**，所以是**错误**不是"另一种含义"。
⇒ **不存在"同一名字在跨任务下含义不同"的情况**，无需额外的命名空间。

### 4.3 与现有 `--lopt-engine` / `--lscan-method` / `--lts-method` / `--lirc-method` 的关系

**关系 = 别名（alias），不是覆盖。** 全部保留，`--method` 是新的**规范名（canonical）**。

| 现有旗标 | 解析点 | 规范名 | 关系 |
|---|---|---|---|
| `--lopt-engine` | `main.F90:2251` | `--method` | **别名**（保留，不弃用警告） |
| `--lscan-method` | `main.F90:2316` | `--method` | **别名** |
| `--lts-method` | `main.F90:2581` | `--method` | **别名**（保留专名，因为它还带 climbing-image 副作用） |
| `--lirc-method` | `main.F90:3325` | `--method` | **别名** |
| `--method` | **新增** | — | 规范名；按 §4.2 解析 |

**统一检测点（关键）**：让四个旧旗标与 `--method` **共享同一个 setter**：
`--method` 只是"不限定 runtyp 的通用入口"，最终都调 `landscape_opt_algorithm_from_name`
/ `landscape_ts_method_from_name` / `landscape_irc_method_from_name`。

**优先级规则与冲突报错**：

1. **同值 = 幂等**（OK，不报错）：`--lopt --method bfgs --lopt-engine bfgs`。
2. **异值 = error**（**绝不静默首选项获胜**）：
   `--lopt --method bfgs --lopt-engine cg` →
   `env%error("conflicting landscape methods: --method bfgs and --lopt-engine cg")`。
   实现方式：setter 记住"方法是否已被显式设定"，第二次设定不同值即报错。
3. **与 `--lts-method` 的 climbing 副作用**：`--lts --method cineb` 必须与
   `--lts --lts-method cineb` 完全同构（都置 `path%climb = .true.`，
   `main.F90:2589-2593`）。**实现要求**：把副作用搬进共享 setter。
4. **`--lscan` 的语义特例**：`--lscan-method` 只收 6 最小化器（`main.F90:2316-2327`），
   与 `--method` 在 `--lscan` 下的容忍集合一致 → 无冲突。

### 4.4 当方法名对应多个任务时怎么办（`bfgs` 是 minimiser，`dimer` 是 saddle）

**明确规则：按当前 runtyp 过滤；不在当前任务集合里的名字 = 响亮错误。**
（用户任务书 §2 明确要求给出这条规则。）

| 调用 | 结果 | 错误消息（设计） |
|---|---|---|
| `--lopt --method dimer` | **error** | `dimer is a transition-state method; use it with --lts (or --lts-method dimer)` |
| `--lts --method bfgs` | **error** | `bfgs is a minimisation method; use it with --lopt or --lscan` |
| `--lirc --method bfgs` | **error** | `bfgs is a minimisation method; use it with --lopt, --lscan or --opt` |
| `--lts --method dimer` | OK | — |
| `--lopt --method bfgs` | OK | — |

**不采用"自动按名字推断任务"**（例如 `--method dimer` 自动变成 `--lts`）：理由
—— 那会让 `--method` 隐式设定 runtyp，与"只选一个 runtyp、首选项获胜"的上游规则
（`man/xtb.1.adoc:205`）打架，且掩盖用户笔误。**除非用户显式给了任务旗标**（§4.5）。

### 4.5 `--method` 与 runtyp 的推导规则

**两条路**：

1. **有任务旗标**（`--lopt/--lscan/--lts/--lirc/--opt/--ohess/--lvib`）→ 按 §4.2 的容忍集合解析。
2. **无任务旗标**：
   - `--method <m>` 若只属于**一个**任务 → **抛出 error**，要求显式任务旗标
     （比"隐式选任务"安全）。消息：`--method dimer needs a run type; add --lts`。
   - 旧稿的例外（`--method ancopt` 且无 runtyp ⇒ 等价 `--opt`）—— **R21 已定：省掉**。
     理由：它是一条隐式规则（同一个旗标在有/无另一旗标时语义不同），且与 §4.4 "不隐式选 runtyp"矛盾。
     ⇒ `--method ancopt` 单独出现 = `env%error`，消息点名 `--opt`/`--ohess`（§4.7 出口 10）。
   - 原生引擎名（§4.7）与套件名同规则：无 `--opt`/`--ohess` 就报错，**不**自动变成 `--opt`。

### 4.6 `--method` 与**未改派** runtyp 的交互（上级点名第 5 条）

**规则：未走套件的 runtyp 上出现 `--method` = 响亮错误，错误信息点名替代方案。**

| 调用 | 结果 |
|---|---|
| `--metaopt --method bfgs` | **error**：`--metaopt runs the native ANCopt conformer search and has no landscape method; use --lopt for a landscape minimisation` |
| `--bhess --method bfgs` | **error**：`--bhess has no landscape equivalent; the Hessian backend is not selectable here` |
| `--path --method neb` | **error**：`--path is the native RMSD-biased path; for a landscape band search use --lts --method neb` |
| `--modef --method bfgs` | **error**：`--modef is the native mode-following search; use --lts for a landscape saddle search` |
| `--screen --method bfgs` | **error**：`--screen has no landscape equivalent; use --lopt per geometry` |
| `--hess --method numerical` | **error**：`--hess always builds a numerical Hessian; use --lvib for the landscape frequency task` |
| `--md --method bfgs` | **error**：同 metaopt（MD 不走套件） |
| `--siman --method bfgs` | **error**（R13 补全，正文未编号 INFO）：`--siman is the native basin-hopping/simulated-annealing run; use --lopt for a landscape minimisation` |
| `--mdopt --method bfgs` | **error**：`--mdopt is the native metadynamics run; use --lts --method neb / --lopt for landscape tasks` |
| `--metadyn --method bfgs` | **error**：`--metadyn is the native metadynamics run; there is no landscape method for it` |
| `--nat --method bfgs` | **error**：`--nat only sets the atom count; add a landscape run type such as --lopt` |
| `--bias-input --method bfgs` | **error**：`--bias-input is the native RMSD bias; for a landscape band search use --lts --method neb` |

> **R13（M5）通用规则 + 消息模板**：不只是 `--method`，**任何套件子选项**出现在"当前 run type 不是它绑定的任务"上，
> 都报 `env%error`（而不是静默丢弃）。消息模板统一为：
> `<flag> belongs to the <task> task; add --<task> (or use --method ancopt / the native equivalent)`。
> 爆炸半径：122 个套件拼写 × 任一先行 runtype 旗标（今天全部静默，`set_module.f90:1031-1038` 的锁消息从未到达用户）
> → 全部变成 exit 1。**实施前必须先 grep 既有测试里的"原生 runtype + 套件子选项"组合**（复核已代跑：`--opt ` 仅 1 命中；双 runtype 0 命中）。

**实现点（R7 修订 —— H3）**：**不能**在 `--method` 的 parser case 里判 `set%runtyp`。
`set_runtyp` 是在**各 case 内部**调用的（`main.F90:2249/2306/2583/3328/...`），解析循环里"先出现的旗标先设 runtyp"，
所以 `xtb m.xyz --method bfgs --lopt` 在 `--method` 处 runtyp 仍是默认（sp）⇒ **必然误报**。
正确做法（同一文件里已有先例）见 **§4.7**：
`--ljson` 的检查放在解析之后（`main.F90:981-982` “The check is here and not in the parser, because the flag and the run type may be given in either order”）；
`--lscan-step` 的 Å→bohr 也是解析后归一（`main.F90:3878-3889`）。

### 4.7 【R7 新增；R21 **重写**】`--method` 的**可实现机制**：解析尾**两段**归一（H3 + H-1）

**目标（三条，缺一不可）**：

1. `--method` 与任务旗标的**任意顺序**都正确（`--method bfgs --lopt` 与 `--lopt --method bfgs` 等价）；
2. 不碰 `set_runtyp` 的"首个 runtyp 锁"（`set_module.f90:1034-1038`）；
3. ** 4 个原生出口（`ancopt`/`lancopt`/`fire`/`pbc_lbfgs`）都走原生分支，不落任何 `default`/`env%error`**（复核 H-1）。

**为什么必须分两段（H-1 的根因，复核已论证，本轮逐行复核成立）**：

- 旧稿（R7）只有一段："把 `--opt` 在解析尾映射为套件任务，再调 `apply_method_opt`"。
- 而 `apply_method_opt` 就是 `--lopt-engine` 的 setter，它内部调 `landscape_opt_algorithm_from_name`
  （`settings.f90:1112-1135`），该函数**只认 6 个最小化器名**（`sd/cg/lbfgs/bfgs/diis/rfo`，`settings.f90:1119-1129`），
  对 `'ancopt'` 返回 **0** ⇒ setter 立刻 `env%error("Unknown landscape minimisation algorithm 'ancopt'")`。
- 若改用"先把 `native_ancopt` 置位再走 `select case (task)`"，则 task = 0 ⇒ 落 `default` ⇒ 同样 `env%error`。
- ⇒ **两条顺序都走不通**；根因不是措辞，是"原生名不该进套件 setter 的取值域"。

**机制（三段；第 1/2 段在 `parseArguments` 内，第 3 段是共享 setter）**

**第 1 段：解析期只存字符串**（`case('--method')`，新增，放在 `--lopt` 附近）

```
case ('--method')
   call args%nextArg(landscape_method_name)   ! character(len=:), allocatable, `program xtb` 局部
   if (.not. allocated(landscape_method_name)) &
      call env%error("The --method flag requires a method name", source)
```

**不**调 `set_runtyp`、**不**写任何 settings（⇒ 与旗标顺序无关）。

**第 0 段【R30 新增，MEDIUM-1】：flag 循环之前把标志置零**。`landscape_native_engine` 是
`parseArguments` 的 `intent(out)` dummy（与 `inputFile`/`paramFile`/`gsolvstate`/`restart`/`strict`/`coffee`
同一惯例，`main.F90:1493-1505`），**进入子程序时它的值是未定义的** —— `program xtb` 侧的声明初值
**救不了它**（`intent(out)` 在入口即把实际参数变回未定义），而第 2 段只在 `if (allocated(landscape_method_name))`
**内部**赋值 ⇒ 没有 `--method` 的任何运行（`--lopt`/`--lscan`/`--lts`/`--lirc`/`--lvib`/`--opt`/`--ohess`/`--hess`/
未改派 runtype）都会拿这个未定义值去判 `native_engine /= 0`（复核 15 MEDIUM-1）。修法：

```
   ! parseArguments 的 flag 循环之前（main.F90:1574 `call args%nextFlag(flag)` 的前一行）
   landscape_native_engine = 0   ! 未给 --method 时必须确定地表示"套件"
```

这样第 2 段的**两个分支都无需再写 0**（套件名分支保持这行写的 0，原生名分支覆盖成 `p_engine_*`）。
全部新增状态位的初值清单见 **§3.11.2**。**为何放在循环前而不是复核建议的"第 2 段首行"**：解析循环里的 `env%error` 会让流程提前离开子程序，放在循环前才能保证**每条返回路径**上这个值都已定义（第 2 段的 `if` 之外再无赋值）。

**第 2 段：解析尾归一（两分支，原生先判）**。位置 = `main.F90:3882-3889` 的 `--lscan-step` 归一循环**之后**、
`end subroutine parseArguments`（`:3891`）**之前**（与 `--ljson` 的"解析后检查"`:981-982` 同惯例）：

```
if (allocated(landscape_method_name)) then
   landscape_native_engine = landscape_native_engine_from_name(landscape_method_name)
   if (landscape_native_engine /= 0) then
      ! ---------- 原生出口：只在这里判，且只对 --opt/--ohess 合法 ----------
      select case (set%runtyp)
      case (p_run_opt, p_run_ohess)
         ! 显式钉住引擎：src/main/defaults.f90:42-46 会在 initDefaults（main.F90:677）
         ! 里按原子数给默认（n > 500 → lbfgs；L-3 订正：旧稿写"n>50 0"），不显式赋值会让
         ! `--opt --method ancopt` 在大体系上**静默**变成 L-ANCopt。
         set%opt_engine = landscape_native_engine
      case default
         call env%error("--method "//landscape_method_name//" selects the native ANCopt "//&
            & "family and is only available with --opt or --ohess", source)
      end select
   else
      ! ---------- 套件方法名：按 runtyp 分发到 4 个纯 setter ----------
      select case (set%runtyp)
      case (p_run_lopt, p_run_opt, p_run_ohess)
         call set_landscape_opt_algorithm (env, lset,   landscape_method_name, '--method', source)
      case (p_run_lscan)
         call set_landscape_scan_algorithm(env, lsset,  landscape_method_name, '--method', source)
      case (p_run_lts)
         call set_landscape_ts_algorithm  (env, ltset,  landscape_method_name, '--method', source)
      case (p_run_lirc)
         call set_landscape_irc_algorithm (env, lircset,landscape_method_name, '--method', source)
      case default
         call env%error("--method needs a landscape run type: add --lopt, --lscan, --lts, "//&
            & "--lirc, --lvib or --opt (or use --method ancopt with --opt)", source)
      end select
   end if
end if
```

> **关键**：`case (p_run_lopt, p_run_opt, p_run_ohess)` **不调 `set_runtyp`**（不像 `--lopt-engine` 的 case）。
> `--opt` 必须保持 `p_run_opt`，否则 §3.11 的身份关系与 C2（`--opt --lopt` 冲突）都被破坏。
> 这正是"共享 setter"必须是**纯 setter**（无 runtyp 副作用）的原因。

**原生名 → 引擎的映射（`main.F90` 局部纯函数；别名集合逐字取自 `set_module.f90:1888-1891`）**

```
!> Native engine selected by a `--method` name; 0 for a landscape method name.
integer function landscape_native_engine_from_name(name)
   select case (trim(name))
   case ('ancopt', 'rf')        ; landscape_native_engine_from_name = p_engine_rf
   case ('lancopt', 'l-ancopt') ; landscape_native_engine_from_name = p_engine_lbfgs
   case ('fire', 'inertial')    ; landscape_native_engine_from_name = p_engine_inertial
   case ('pbc_lbfgs')           ; landscape_native_engine_from_name = p_engine_pbc_lbfgs
   case default                 ; landscape_native_engine_from_name = 0
   end select
end function
```

**裸 `lbfgs` 故意不在此表内**：它已是套件最小化器名（§4.1）。上游 `set_module.f90:1889` 的 `lbfgs|l-ancopt`
在本设计里只取 `l-ancopt` 作原生别名，避开"同一名字两种含义"。

**第 3 段：共享 setter**（§4.3）——从现有 4 个 case 里**抽取**，只做"名字 → 枚举 + 冲突检查"，
**不含 runtyp 副作用**（副作用留在 case 里，BC-2 不受影响）：

```
case ('--lopt-engine')
   if (set%runtyp /= p_run_lopt) call set_runtyp('lopt')   ! 保留：单独给 --lopt-engine 仍选 lopt
   call args%nextArg(sec)
   if (allocated(sec)) then
      call set_landscape_opt_algorithm(env, lset, sec, '--lopt-engine', source)
   else
      call env%error("The --lopt-engine flag requires an algorithm name", source)
   end if
```

`set_landscape_opt_algorithm` 的内部 = 现有 4 行 + §4.3 的冲突检查：

```
landscape_algorithm = landscape_opt_algorithm_from_name(name)
if (landscape_algorithm == 0) call env%error("Unknown landscape minimisation algorithm '"//name//"'", source)
if (allocated(lset%algorithm_source) .and. lset%algorithm_source /= owner) &
   call env%error("conflicting landscape methods: --method "//name//" and "//owner//" <value>", source)
lset%algorithm = landscape_algorithm
lset%algorithm_source = owner          ! 记首设旗标以生成可操作消息（§4.3 规则 2）
```

（`--lscan-method`/`--lts-method`/`--lirc-method` 同构；ts 的那个把 climbing 副作用
`path%climb = .true.`（`main.F90:2589-2593`）搬入共享 setter，使 `--lts --method cineb` 与
`--lts --lts-method cineb` 完全同构。）

**与 `set_runtyp` 锁的共存**：`--method` **从不**调 `set_runtyp`，也**从不**隐式选任务（§4.4 明确拒绝）
⇒ 与"只选一个 runtyp、首选项获胜"（`man/xtb.1.adoc:205`）完全无交。只有当用户**已经**给了任务旗标
（或 `--opt`/`--ohess`）时 `--method` 才有作用域；否则报错（第 2 段的 `default` 分支）。
**解析顺序无关性**：由第 1 段（不读 `set%runtyp`）与第 2 段（在 flag 循环之后）共同保证：
`--method ancopt --opt` 与 `--opt --method ancopt` 在尾归一时 `set%runtyp` 都是 `p_run_opt` ⇒ 逐位等价。

**逐行代入证明： 4 个原生出口都不落 `default`/`env%error`**（复核 H-1 自证要求；
`set%runtyp` 由 `--opt` 的 `main.F90:2154` / `--ohess` 的 `:2166` 置为 `p_run_opt`/`p_run_ohess`）

| # | 命令行 | 第 2 段取到的 `landscape_native_engine` | `select case (set%runtyp)` 命中 | `landscape_opt_algorithm_from_name` 被调？ | 结果 |
|---|---|---|---|---|---|
| 1 | `--opt --method ancopt`（或 `rf`） | `p_engine_rf` = 1 ≠ 0 | `case (p_run_opt, p_run_ohess)` → `set%opt_engine = 1` | **否**（`else` 分支未进入） | 原生 ANCopt（`geoopt_driver.f90:149 case(p_engine_rf)` → `:150 call ancopt`）✅ |
| 2 | `--opt --method lancopt`（或 `l-ancopt`） | `p_engine_lbfgs` = 2 ≠ 0 | 同上 → `set%opt_engine = 2` | 否 | 原生 L-ANCopt（`geoopt_driver.f90:155` → `:156 call l_ancopt`）✅ |
| 3 | `--opt --method fire`（或 `inertial`） | `p_engine_inertial` = 3 ≠ 0 | 同上 → `set%opt_engine = 3` | 否 | 原生 FIRE（`geoopt_driver.f90:169` → `:170 call fire`）✅ |
| 4 | `--opt --method pbc_lbfgs` | `p_engine_pbc_lbfgs` = 4 ≠ 0 | 同上 → `set%opt_engine = 4` | 否 | 原生 pbc L-BFGS（`geoopt_driver.f90:159` → `:163 call relax_pbc`）✅ |
| 5 | `--ohess --method <1..4>` | 同上 | `set%runtyp == p_run_ohess` 命中同一 case | 否 | 原生 opt（引擎同上）+ 原生 `main_freq`（`main.F90:1284`）✅ |
| 6 | `--method ancopt --opt`（反序） | 同 1 | 同 1（尾归一在两者之后） | 否 | 同 1 ✅ |
| 7 | `--lopt --method ancopt` | 1 ≠ 0 | `case default` → `env%error`（**设计如此**，见下） | 否 | 响亮报错："… only available with --opt or --ohess" |
| 8 | `--lopt --method bfgs` | 0 | `case (p_run_lopt, …)` → 套件 setter | 是，收 `'bfgs'` → `p_landscape_opt_bfgs` | 套件 bfgs ✅ |
| 9 | `--lopt --method dimer` | 0 | 同上 | 是，但返回 0 → `env%error`（§4.4 设计如此） | 响亮报错（点名 `--lts`） |
| 10 | `--method bfgs`（无任务旗标） | 0 | runtyp = 默认（非 opt/ohess/l*） → `case default` | 否 | 响亮报错（§4.5） |

**关键点（为何出口 1-6 不会报错）**：原生名在第 2 段的**第一个分支**就被分流（`if/else` 结构，`else` 才碰 setter），
所以 `landscape_opt_algorithm_from_name` 在出口 1-6 上**根本不被调用**；`default` 只在"原生名 + 非 opt/ohess"（出口 7）
与"套件名 + 无任务"（出口 10）两种**设计要求的报错**上命中。⇒ 复核 H-1 的两条死路都被消除，
且**不靠**改 `landscape_opt_algorithm_from_name` 的取值域（那会把 6 个最小化器与 4 个原生引擎混在一个函数里，
违反 §4.2 的"名字含义由 runtyp 决定"）。

**显式钉住 `set%opt_engine` 的必要性（H-1 的隐式陷阱）**：`src/main/defaults.f90:42-46` 在 `initDefaults`
（`main.F90:677`，在 `parseArguments:252` **之后**）里按原子数给默认引擎（n > 500 → `p_engine_lbfgs`，
否则 `p_engine_rf`）。若不显式赋值，`--opt --method ancopt` 在 1000 原子上会静默变成 L-ANCopt。
赋值后 `defaults.f90:42` 的 `.not.allocated` 守卫使默认不再覆盖（与 `set_module.f90:1885` 的
xcontrol `$opt engine=` 同样的 first-wins 规则）⇒ **优先级：显式 CLI（`--method <native>`）> xcontrol `$opt engine=` > 内置默认**；
与 `--lvib`/`$thermo` 已确立的"显式 CLI > xcontrol > 内置默认"一致（AGENTS §6）。

**规则：`--lopt --method ancopt` 允许吗？—— 不允许（出口 7）**。理由：
(a) `--lopt` 是套件任务的**显式**旗标，在它上要原生引擎是自相矛盾；(b) §4.2 的 `--lopt` 容忍集合就是
"6 最小化器 + `auto`"；(c) §4.4 的统一规则"名字不在当前任务的集合里 = 响亮错误"因此适用；
(d) 报错信息**点名** `--opt`，用户一步可改。(反例检查：若允许，就要在套件分派点把 `--lopt` 改派回原生，
`--lopt --lopt-engine X` 的既有语义会被同时改写 —— 破坏面更大。)

**为何不用两趟解析**：本仓库的 `TArgParser`（`src/prog/argparser.f90`）不提供回放已消费参数的能力，
二趟解析需重建 parser 与全部 case，**改动面远大于**尾归一；而尾归一是同一文件里**已被验证过的模式**
（`--ljson`、`--lscan-step`）。

#### 4.7.1 测试规格（H-1/H-2/M-3 的"真的走到原生路径"断言）

判别 token **全部本轮实测**（`/tmp/xtb-w2/build/xtb`，`OMP_NUM_THREADS=1`，非周期水，原生路径今天经
`$opt engine=<名字>` 可达 —— 见 §13c）：

| 引擎 | stdout 唯一 token | 出处 `file:line` |
|---|---|---|
| `rf` | `ANC micro-cycles` | `src/optimizer.f90:392` |
| `lbfgs` | `L-ANC optimizer` | `src/relaxation_engine.f90:594` |
| `inertial` | `initial time step` | `src/relaxation_engine.f90:298` |
| `pbc_lbfgs` | `current lattice:` | `src/lbfgs_anc/driver.f90:254` |
| （套件） | `landscape: ` + 算法名 + ` minimisation` | `src/landscape/tasks/opt.f90:108` |

| 测试（新增） | 命令 | 断言 | 突变下变红 |
|---|---|---|---|
| `xtb/landscape-method-native-ancopt` | `--opt --method ancopt`；以及 `--method ancopt --opt` | exit 0；stdout 含 `ANC micro-cycles` 且**不含** `landscape:`；两顺序输出逐位同 | 把 `ancopt\|rf` 映射删掉（→ 0）⇒ 落套件分支 ⇒ 打印 `landscape:` ⇒ 红 |
| `xtb/landscape-method-native-lancopt` | `--opt --method lancopt`（`l-ancopt` 反例） | 含 `L-ANC optimizer`，不含其他三个 token | 同上（映射→ 0） |
| `xtb/landscape-method-native-fire` | `--opt --method fire`（`inertial` 反例） | 含 `initial time step` | 同上 |
| `xtb/landscape-method-native-pbc` | `--opt --method pbc_lbfgs` | 含 `current lattice:`（实测非周期水 exit 0） | 同上；或把它映射成别的引擎 ⇒ 其他 token 出现 ⇒ 红 |
| `xtb/landscape-method-native-ohess` | `--ohess --method ancopt` | exit 0；含 `ANC micro-cycles`；写 `hessian`/`vibspectrum`（`main_freq`） | 把 `p_run_ohess` 从 case 里去掉 ⇒ 落 `default` ⇒ 非零退出 ⇒ 红 |
| `xtb/landscape-method-native-level` | **GFN-FF 501 原子非周期** fixture + `--opt --method ancopt` | stdout 含 `ANC micro-cycles` 且**不含** `L-ANC optimizer`（引擎 = `rf`） | 删掉 `set%opt_engine = landscape_native_engine` ⇒ `defaults.f90:44` 的默认给 lbfgs ⇒ 出现 `L-ANC optimizer` ⇒ 红 |
| `xtb/landscape-method-on-lopt-rejected` | `--lopt --method ancopt` | 非零退出 + 文本含 `--opt`/`--ohess` | 去掉原生分支的 `case default` |
| `xtb/landscape-opt-alias-once`（**M-3**） | `--opt --ljson` | 含 `landscape: lbfgs minimisation`；**不含** `ANC micro-cycles`；写 `landscape_opt.json` 且 `counters.n_steps` == 同几何 `--lopt --ljson` | 去掉 `main.F90:931` 的 `landscape_native_engine /= 0` ⇒ 原生块也跑 ⇒ 出现 `ANC micro-cycles` ⇒ 红 |
| `xtb/landscape-opt-native-nojson`（M-3 反向） | `--opt --method ancopt --ljson` | exit 0；含 `ANC micro-cycles`；**不写** `landscape_opt.json` | 把 §5.3 的 `--ljson` 列表写成"runtyp ∈ {opt,ohess}"而不看 `native_engine` ⇒ 写了 json ⇒ 红 |
| `xtb/landscape-guard-fire-no-scan`（**H-2**） | `--opt --method fire --input <含 $scan>` | exit 0 + `$scan` 被原生执行（含 `RELAXED SCAN`，写 `xtbscan.log`） | 谓词退化为 `native_engine == p_engine_rf` ⇒ 命中 `$scan` 守卫 ⇒ 非零 ⇒ 红 |
| `xtb/landscape-guard-fire-no-opt`（H-2/c） | `--opt --method fire --input <含 $opt optlevel=tight>` | exit 0 + 含 `initial time step`（无守卫报错） | 同上 |
| `xtb/landscape-guard-pbc-native`（H-2/b） | GFN-FF 周期 fixture + `--opt --method ancopt` | exit 0（原生周期路径） | 谓词退化 ⇒ 周期守卫误报 ⇒ 红 |
| `xtb/landscape-opt-xcontrol-scope`（**M-2**） | `--lopt --input <含 $opt optlevel=tight>` | 非零退出 + 文本含 `--method ancopt` | 去掉守卫（今天 exit 0 且 0 行提示 [实测]） |
| `xtb/landscape-method-level-bridge`（L-4） | `--lopt-level lax` vs `--opt lax --method bfgs` | 前者非零退出（5 个套件名之外）；后者 exit 0 + `[NOTICE]` | 把上游名加进 `landscape_conv_level_known` ⇒ 前者变绿 ⇒ 红 |
| **`xtb/landscape-ohess-suite-once`（R29/HIGH-1/T1+T2）** | `--ohess normal`（套件） | exit 0；`Numerical Hessian` = 0、`Frequency Printout` = 0、`ANC micro-cycles` = 0、`landscape: harmonic frequencies` = 1、`landscape engine: Hessians` 行 = 1 | 去掉 `:1156`/`:1282` 的谓词或 `:931` 的抑制 ⇒ 对应 token 变 1 ⇒ 红（见 §3.11.1） |
| **`xtb/landscape-ohess-native-hess`（R29/T1+T2 反向）** | `--ohess --method ancopt` | exit 0；`Numerical Hessian` = 1、`Frequency Printout` = 1、`landscape: harmonic frequencies` = 0 | 谓词写成恒假 ⇒ 原生侧不跑 `numhess` ⇒ `hessian` 不写 ⇒ 红 |
| **`xtb/landscape-ohess-fres-bridge`（R29/T3）** | `--ohess normal`（套件）与同一末几何的 `--lvib` | `TOTAL ENTHALPY`/`TOTAL FREE ENERGY` 行存在且与 `--lvib` 的 `total enthalpy H(T)`/`G(T)` 一致（≤1e-6 Eh）；`TOTAL ENERGY` ≠ 0 | 删桥 ⇒ 两行消失；`anyhess` 真而不填 `fres` ⇒ 打印 `TOTAL ENERGY 0.000000000000` ⇒ 红 |
| **`xtb/landscape-opt-xtbopt-once`（R29/L-4）** | `--opt`（套件）；以及 `--opt --namespace c1` | `optimized geometry written to:` = 0、`wrote xtbopt.xyz` = 1；`c1.xtbopt.xyz` 只写一次；计时块含 `landscape optimizer` 且不含 `ANC optimizer` | 去掉 `:1310-1320` 的抑制 ⇒ 两行提示都出现 ⇒ 红；恢复 `:4065` 的 runtyp-only 条件 ⇒ 计时标签回到 `ANC optimizer` ⇒ 红 |
| **`xtb/landscape-lopt-no-method`（R30/MEDIUM-1）** | `--lopt`（无 `--method`） | exit 0；含 `landscape: lbfgs minimisation`、不含 `ANC micro-cycles`；写 `landscape_opt.json` | 删掉 flag 循环前的 `landscape_native_engine = 0` ⇒ 读到未定义值。**诚实标注**：`intent(out)` 的未定义值在 `-O2` 下经常"恰好为 0"，所以**运行时测试不能可靠地证伪这一条**；真正的验收是**静态且可核的**：`grep -n "landscape_native_engine" src/prog/main.F90` 必须同时给出声明行（带 `= 0`）与 flag 循环前那行（实现报告贴输出） |
| **`xtb/landscape-method-native-vs-xcontrol`（R34/U15）** | `--opt --method fire --input <$opt engine=rf>` | exit 0；含 `[WARNING]`（提示 `$opt engine=rf` 被丢弃）、含 `initial time step`（fire 生效）、不含 `ANC micro-cycles` | 去掉 `set_module.f90:1885` 分支的 warning ⇒ `[WARNING]` 消失 ⇒ 红（行为不变，仍 fire —— 本项只加诊断） |

> **Falsifiability**：每行最后一列都是**可注入的具体突变**（沿用 M4 报告 34 §1 的教训：先证明突变与被回退的
> 逻辑**语义等价**，否则"绿"说明不了任何事）。

### 4.8 【R9 新增；R21 改写】原生引擎出口（H5）：`ancopt` / `lancopt` / `fire` / `pbc_lbfgs`

**作用域**：这 4 个引擎（**7 个拼写**（L-1 订正），§4.1）**仅**在 `--opt`/`--ohess` 下合法（其他任务集合里出现 →
`env%error`，§4.4/§4.7 出口 7）。

| `--method` 名字 | 效果 | 实现点 |
|---|---|---|
| `ancopt`（+`rf`） | `landscape_native_engine = p_engine_rf`；`set%opt_engine = p_engine_rf` ⇒ `--opt`/`--ohess` 走**原生** ANCopt（= 今天的行为） | §4.7 第 2 段；引擎 ID `setparam.f90:77` |
| `lancopt`（别名 `l-ancopt`） | `set%opt_engine = p_engine_lbfgs` ⇒ 原生 L-ANCopt | §4.7；`set_module.f90:1889` |
| `fire`（别名 `inertial`） | `set%opt_engine = p_engine_inertial` ⇒ 原生 FIRE | §4.7；`set_module.f90:1891` |
| `pbc_lbfgs`（**R21：真正的出口**） | `set%opt_engine = p_engine_pbc_lbfgs` ⇒ 原生周期 L-BFGS（`relax_pbc`）。**今天**用户不需手写它：GFN-FF + 周期时 `main.F90:933-937` 会**自动**选它；但非周期体系上它只能经 `--method`（或 `$opt engine=`）选中，所以它必须是一个**不报错**的出口 | §4.7；`set_module.f90:1890` |

**为何需要**：否则 G12（FIRE / L-ANCopt）在 C 之后**没有 CLI 可达路径**（复核 H5）——
用户无法再用 `$opt engine=`（§3.8c 让它在套件下报错），也没有别的 CLI 旋钮。这些出口把这条路径补回。
**取值域交叉检查**："`bfgs` 既是套件 minimiser 又可能被误认为 L-ANCopt"——不冲突：原生别名是 `lancopt`/`l-ancopt`，
**不是**裸 `lbfgs`（§4.7 的映射表）；`lancopt` 在 `--lopt` 下属于"原生名 + 非 opt/ohess" ⇒ `env%error`（§4.7 出口 7）。

**与 `$opt engine=` 的关系（R21 定优先级）**：两者同一取值域；解析尾归一在 `rdcontrol`（`main.F90:333`）**之前**
执行，所以显式 `--method` 先占住 `set%opt_engine`，`$opt engine=` 被 `set_module.f90:1885` 的 `.not.allocated` 守卫忽略。
其余 `$opt` 键（如 `optlevel=`）仍被原生全部尊重（原生 `--opt --method ancopt` 下 §3.8c 守卫**不**触发）。

> **既有的"周期 GFN-FF 强制 pbc_lbfgs"优先于本标志（已知行为，不在本设计改动范围）**：`main.F90:933-937`
> 在 `mol%npbc > 0` 且 GFN-FF 时会 `deallocate(set%opt_engine)` 并强制 `pbc_lbfgs`——它对**现有的** `$opt engine=fire`
> 也一样。⇒ 在周期 GFN-FF 体系上 `--opt --method fire` 实际跑 `pbc_lbfgs`；
> 这也是 §4.7.1 的 `xtb/landscape-guard-pbc-native` 只断言"exit 0 + 不误报守卫"、不断言 `initial time step` 的原因（避免把既有行为当成新缺陷）。

---

## 5. 后向兼容矩阵

### 5.1 现有调用形式清单（逐条标注）

> **`--opt` 那一行按上级要求留占位**，见 §5.5。
> 判据：`仍然工作` / `语义改变` / `不再工作`。

| # | 调用 | 现状（HEAD 实测） | 新设计 | 判定 |
|---|---|---|---|---|
| 1 | `--lopt` | 套件 lbfgs | 不变 | 仍然工作 |
| 2 | `--lopt-engine bfgs` | 套件 bfgs | 别名 `--method bfgs` | 仍然工作 |
| 3 | `--lopt-level tight` | 套件 tight | 不变（新增上游别名见 §3.5） | 仍然工作 |
| 4 | `--lopt-hessian model` | 套件 model 提供器 | 不变 | 仍然工作 |
| 5 | `--lopt-hessian file --lopt-hessian-file f` | 读文件 | 不变 | 仍然工作 |
| 6 | `--lscan ...`（全套 21 个） | 套件扫描 | 不变 | 仍然工作 |
| 7 | `--lscan-method cg` | 套件 cg | 别名 `--method cg` | 仍然工作 |
| 8 | `--lts`（全套 56 个） | 套件 TS | 不变 | 仍然工作 |
| 9 | `--lts-method dimer` | 套件 dimer | 别名 | 仍然工作 |
| 10 | `--lirc`（全套 28 个） | 套件 IRC | 不变 | 仍然工作 |
| 11 | `--lirc-method lqa` | 套件 lqa | 别名 | 仍然工作 |
| 12 | `--lvib`（全套 11 个） | 套件频率 | 不变 | 仍然工作 |
| 13 | `--ljson` + 套件 runtyp | 写 `landscape_<task>.json` | 不变 | 仍然工作 |
| 14 | `--hess` | 原生数值 Hessian | **不变**（BC-4） | 仍然工作 |
| 15 | `--hess --ljson` | 原生 hess + warning | 不变 | 仍然工作 |
| 16 | `--bhess`/`--metaopt`/`--path`/`--modef`/`--screen` | 原生 | **保持原生**（D-N） | 仍然工作 |
| 17 | `--sp`/`--grad`/`--md`/`--omd`/`--vip`/... | 原生 | 不变 | 仍然工作 |
| 18 | `--opt normal` | **原生 ANCopt** | **套件 lbfgs** | **语义改变**（§5.5） |
| 19 | `--ohess normal` | **原生 ANCopt+Hess** | **套件 opt+vib 链** | **语义改变**（§5.5） |
| 20 | `--lopt --lscan` | 静默首选项获胜 | **error**（§8.1） | **语义改变（变响亮）** |
| 21 | `--opt --hess` | 静默首选项获胜（`--opt`） | **error**（§8.7 C2 族：两个不同 runtype）。**R28 订正：旧稿写"`--opt` 走套件 + error/warning（§8.1）"，与 §8.7 "旧稿措辞作废、改 error"矛盾，现统一为 error** | **语义改变（变响亮）** |
| 22 | `--metaopt --method bfgs` | 无 `--method`，N/A | **error**（§4.6） | 新增行为 |
| 23 | `--lts --lopt-engine bfgs` | **静默丢弃** `--lopt-engine`（§2.6b 实测） | **error**（§4.3 冲突/§4.6 集合过滤） | **语义改变（变响亮）** |
| 24 | `--lvib --lvib-temp 400` | 套件温度 | 不变 | 仍然工作 |
| 25 | `--hess --lvib-temp 400` | **静默丢弃** `--lvib-temp` | **error**（§8.1 扩展） | **语义改变（变响亮）** |

### 5.2 组合矩阵（`--opt` / `--lopt` / `--lscan` / `--lts` / `--lirc` / `--lvib`）

**[实测]** 现状（`/tmp/xtb-w2/build/xtb`，`--norestart`，无任何用户提示）：

| 组合 | 现状实际执行 | 现状是否提示 |
|---|---|---|
| `--opt normal --lopt` | ANCopt | ❌ |
| `--lopt --opt normal` | 套件 lbfgs | ❌ |
| `--opt normal --lopt-engine bfgs` | ANCopt（`--lopt-engine` **丢弃**） | ❌ |
| `--lopt --lscan` | 套件 lbfgs | ❌ |
| `--lts --lirc` | 套件 TS | ❌（有另一条 TS 自身警告） |
| `--hess --ljson` | 原生 hess | ✅ `[WARNING] --ljson writes nothing...` |
| `--lopt --ljson` | 套件 opt + json | 无警告 |

**新设计的目标矩阵**（`--opt` 行按 C）：

| 组合 | 新行为 |
|---|---|
| `--opt normal --lopt` | **error**（两个 runtype 冲突，§8.1）——**除非** `--opt` 在某方案下本身就是套件（C 下仍是两个不同 runtyp，故 error） |
| `--opt normal --method bfgs` | 套件 opt + bfgs（§3） |
| `--opt normal --method ancopt` | 原生 ANCopt |
| `--lopt --lscan` | **error**：`--lopt and --lscan are different run types; only one can run` |
| `--lts --lirc` | **error**（同上） |
| `--hess --ljson` | 保留 warning（已实现） |

### 5.3 `--ljson` 组合（点名要求）

**[实测]** 现状：

| 组合 | 现象 |
|---|---|
| `--ljson --lopt/--lscan/--lvib/--lts/--lirc` | 写 `landscape_<task>.json` ✅ |
| `--ljson --opt` / `--ljson --hess` | `[WARNING] --ljson writes nothing without a landscape run type: add --lopt, --lscan, --lvib, --lts or --lirc`（`main.F90:984-987`，`[R17]` 旧稿误写 952-957——那是 `$scan`/`relaxed_scan` 块）✅ |
| `--ljson` 单独 | 同 warning ✅ |

**新设计**：`--ljson` 在原生 runtyp 上的行为**不变**。但在 C 之后，`--opt`/`--ohess` 是套件任务，
**`--ljson` 的消息文本与判定必须更新**（`main.F90:984-987`）：把 `--opt`/`--ohess` 加进"有效 runtype"列表，
并且 `--opt --ljson` / `--ohess --ljson` 应**真的写出** `landscape_opt.json`（否则又是一条静默不一致）。
⇒ §9.1 阶段 3 的一项（与阶段 2 分开：它依赖 `--opt` 改派）。

**【R2/R13 注】** `--ljson --opt` 这条消息正是复核所说"BC-5 与 §9.2 要求 grep stdout"的一个实例：
该 warning 实测就在 stdout（§3.4），所以本设计统一将 `[NOTICE]`/`[WARNING]`/`[ERROR]` 全部走 stdout。

### 5.4 `--ohess` 文件契约对照（独立于"数值变了"的第二类破坏）

**[实测]** 基线（§3.2）：

| 文件 | 原生 `--ohess` | 套件链（`--lopt` + `--lvib`） | 差异（HEAD） | **R4 后（§3.9）** |
|---|---|---|---|---|
| `xtbopt.xyz` | ✅ | ✅ | 同名（套件经 `log.f90:74`） | 不变 |
| `.xtboptok` | ✅ | ❌ **缺** | **破坏**（收敛哨兵） | **套件补写**（仅收敛时）⇒ **不再破坏** |
| `xtbopt.log` | ✅ | ❌（套件写 `xtb.trj`） | **破坏**（xyz 轨迹文件名不同） | **套件补写 `xtbopt.log`**（逐帧，写点 `optimizer.f90:801`，L-3）⇒ **不再破坏**；`xtb.trj` 作为**新增**保留 |
| `xtb.trj` | ❌ | ✅ | 新增 | 新增（BC-3 允许新增） |
| `xtbhess.xyz` | ✅（有虚频时） | ✅（有虚频时，实测） | 一致 | 不变 |
| `hessian` | ✅ | ✅ | 一致 | 不变 |
| `vibspectrum` | ✅ | ✅ | 一致 | 不变 |
| `g98.out` | ✅ | ✅ | 一致 | 不变 |
| `compliance.dat` | ✅ | ❌ **缺** | **破坏**（顺从性分析） | **套件在同条件下复用 `compliance_driver`**（`hessian.F90:331-332`）⇒ **不再破坏** |
| `vib_normal_modes` | ❌ | ✅ | 新增 | 新增（BC-3 允许新增） |
| `charges`/`wbo`/`xtbtopo.mol` | ✅ | ✅ | 一致 | 不变 |

**结论（R26 重写，M-1）**：

- **HEAD 现状**：`--ohess` 改派到套件会**少掉 3 个文件**（`.xtboptok`/`xtbopt.log`/`compliance.dat`）+ **多出 2 个**（`xtb.trj`/`vib_normal_modes`）。
  外脚本靠文件名判断收敛/取轨迹 ⇒ 这确实是"独立于数值变了的第二类破坏"（**现状**语境）。
- **R4（决策 2）后**：套件按**上游语义**写全 `.xtboptok`/`xtbopt.log`/`compliance.dat`（§3.9 逐文件给上游对照 `file:line`）
  ⇒ **缺失项清零**；新增两项是**纯增量**（BC-3 已改为"集合不减小"，§1.2）。
  ⇒ **B 类破坏 = 0 条**（§10 B），**本节的"3 个缺失 = 破坏"只描述 HEAD 现状，不作为交付后的破坏项**。
- **R26 留痕（报告纪律）**：本节旧稿（R4 之前）在结论里直接写"会改变 **3 个缺失** + **2 个新增**…是独立的第二类破坏"，
  而未同时给出 R4 的消解结果 ⇒ 与 `§1.2 BC-3`、`§10 B 类（清零）`**自相矛盾**（复核 14 M-1 只修了一半）。
  本次已按上表加"R4 后"列并把结论改写为**两段（HEAD 现状 / R4 后）**；
  同理 `13-*.md §2` 此前声称"§5.4 加 R4 后补齐"，而 `grep "R4 后补齐"` = **0 命中** ⇒ **该声称是过度声称**，
  已在 `13-*.md §4` 订正并留痕。

### 5.5 `--opt` / `--ohess` 行（方案 C 已决策，坑位填上；**R12/R5 补全 `-o` 与全部档位**）

| 调用 | 现状 | C 下（含 R1/R5） | 判定 |
|---|---|---|---|
| `xtb m.xyz --opt` | ANCopt，normal | 套件 lbfgs，normal + `[NOTICE]` | **语义改变** |
| `xtb m.xyz -o` / `-o normal` | `case('-o','--opt')`（`main.F90:2153`）⇒ 与 `--opt` 同 | 同 `--opt` | **语义改变（R12：旧稿未列 `-o`）** |
| `--opt <normal|crude|tight|...>` | 全接受（`set_module.f90:1910-1928`） | 按 §3.5 映射；偏差打 `[NOTICE]` | **语义改变** |
| `--opt lax / sloppy` | 接受 | 套件 `loose`/`superloose`（比上游**更松**）+ `[NOTICE]` | **语义改变（R12/LOW-6：旧稿 §5.5 未列）** |
| `--opt extreme` | ANCopt extreme | 套件 `vtight`（**截断**）+ `[NOTICE]` | **语义改变** |
| `--opt -3 / 0 / 3`（数字档） | 接受（`case('crude','-3')` 等） | 同关键字映射 | **语义改变（LOW-6）** |
| `--opt banana` | **静默→normal** | **error**（§8.5） | **行为变更（R12：旧稿 §8.5 建议但未入册）** |
| `--opt --cycles 50` | 影响原生 ANCopt 的 maxcycle | 映射到套件 `max_steps`（§3.10b） | **语义改变（变响亮/映射）** |
| `--opt --input <含 $scan 的 xcontrol>` | **执行 relaxed_scan**（写出 `xtbscan.log`） | **响亮报错 + 指向 `--method ancopt`**（§3.8a） | **语义改变（功能损失 → 响亮拒绝，R1）** |
| `--opt` + 周期体系 | 走 `geoopt_driver`/`pbc_lbfgs`（`main.F90:933-937`） | **响亮报错 + 指向 `--method ancopt`**（§3.8b） | **语义改变（R1）** |
| `--opt --input <含 $opt 块>` | 原生读 `set%optset%*`/`get_optthr` | **响亮报错**（§3.8c，除非 `--method ancopt`） | **语义改变（R1）** |
| `--opt normal --method ancopt`（或 `lancopt`/`fire`） | ANCopt normal | **原生 ANCopt（不变）**；`lancopt`/`fire` 选 L-ANCopt/FIRE（§4.8） | 仍然工作 |
| `--ohess` | 原生 ANCopt+hess | 套件 opt+vib + `[NOTICE]` | **语义改变** |
| `--ohess normal --method ancopt` | 原生 | **原生（不变）** | 仍然工作 |

> **坑位状态**：**已由用户决策 C 填充**（§3.0）。若用户后续改选 A/B/D，本表按 §3.6 重写。
> **旧稿的"1 条破坏性变更"不成立**——见 §10 的逐类清单（**R4 后 B 类清零**，**R1 后三类从静默变响亮**）。
> **实测基线（复核代跑）**：`grep -rn -- '--opt ' test/unit/` = **1 命中** = `landscape_cli_check.py:495`（即 R2 的 `--opt + $scan` 断言）；
> `grep -rn "2>&1" test/unit/` = **0 命中**（但 CMake 同名 `ERROR_VARIABLE` 会合并，§3.4）；双 runtype 组合 = **0 命中**。

---

## 6. 完整映射表：旧形式 → 新形式

### 6.1 说明与图例

- **保持** = 拼写与语义均不变。
- **别名** = 新增规范名，旧名**永久保留**（不破坏）。**本设计不含任何"重命名（破坏性）"**。
- **新增** = 全新旗标（非破坏）。
- **移除** = **本设计为 0 条**。
- 行号以 **HEAD `bdd8eb8`** 的 `src/prog/main.F90` 为准（W0 后行号比审计 B 的 `24c069f` 大约 +37）。
- 统计：套件 case 标签 **121** / 拼写 **122**（`--lirc-e-rise, --lirc-erise-steps` 是一行两拼写）。
  逐前缀：`--ljson` 1、`--lopt*` 5、`--lscan*` 21、`--lts*` 56、`--lirc*` 28、`--lvib*` 11。

### 6.2 套件参数逐行映射（122 拼写）

| # | 旧形式（HEAD 行） | 目标字段 | 动作 | 新形式 / 备注 |
|---|---|---|---|---|
| 1 | `--ljson` (`:2231`) | `l*set%ljson` | **保持** | 消息列表加 `--opt`/`--ohess`（§5.3） |
| 2 | `--lopt` (`:2244`) | runtyp | **保持** | — |
| 3 | `--lopt-engine` (`:2251`) | `lset%algorithm` | **别名** | → `--method`；`--lopt-engine` 保留 |
| 4 | `--lopt-level` (`:2266`) | 5 阈值 | **保持** | **R27/L-4：不收上游 8 档名**（只 5 个套件名，`settings.f90:1497-1510`）；上游名走 `--opt`/`--ohess` 桥接（§3.5） |
| 5 | `--lopt-hessian` (`:2280`) | `lset%hessian_source` | **保持** | help 补 `file`（审计 c1） |
| 6 | `--lopt-hessian-file` (`:3823`) | `lset%hessian_file` | **保持** | — |
| 7 | `--lscan` (`:2296`) | runtyp | **保持** | — |
| 8 | `--lscan-mode` (`:2302`) | `lsset%mode` | **保持** | — |
| 9 | `--lscan-method` (`:2316`) | `lsset%method` | **别名** | → `--method` |
| 10 | `--lscan-level` (`:2330`) | 5 阈值 | **保持** | — |
| 11 | `--lscan-restart` (`:2344`) | `engine%restart_mode` | **保持** | — |
| 12 | `--lscan-ndim` (`:2363`) | `lsset%ndim` | **保持** | — |
| 13 | `--lscan-oneway` (`:2378`) | `bidirectional` | **保持** | — |
| 14 | `--lscan-cold-start` (`:2383`) | `warm_start` | **保持** | — |
| 15 | `--lscan-fc` (`:2388`) | `constraint_fc` | **保持** | 危险默认回显（§8.3） |
| 16 | `--lscan-expo` (`:2403`) | `spring_expo` | **保持** | — |
| 17 | `--lscan-coord` (`:2418`) | `coord(1)%ctype` | **保持** | 必填报错点名（§8.2） |
| 18 | `--lscan-atoms` (`:2433`) | runtyp/coord | **保持** | 同上 |
| 19 | `--lscan-step` (`:2443`) | `coord(1|2)%step` | **保持** | **单位 Å/度**，必须标注（§7.3） |
| 20 | `--lscan-nstep` (`:2459`) | `coord(1)%nstep` | **保持** | 同上 |
| 21 | `--lscan-coord2` (`:2474`) | `coord(2)%ctype` | **保持** | — |
| 22 | `--lscan-atoms2` (`:2490`) | `ndim` | **保持** | — |
| 23 | `--lscan-step2` (`:2501`) | `coord(2)%step` | **保持** | 单位 Å/度 |
| 24 | `--lscan-nstep2` (`:2518`) | `coord(2)%nstep` | **保持** | — |
| 25 | `--lscan-max-steps` (`:2534`) | `lsset%max_steps` | **保持** | — |
| 26 | `--lscan-hessian` (`:2549`) | `lsset%hessian_source` | **保持** | — |
| 27 | `--lscan-hessian-file` (`:2565`) | `lsset%hessian_file` | **保持** | — |
| 28 | `--lts` (`:2575`) | runtyp | **保持** | — |
| 29 | `--lts-method` (`:2581`) | `ltset%method` | **别名** | → `--method`；climbing 副作用搬进共享 setter |
| 30 | `--lts-trust` (`:2604`) | `trust` | **保持** | 单位 bohr |
| 31 | `--lts-trust-max` (`:2619`) | `trust_max` | **保持** | bohr |
| 32 | `--lts-hlow` (`:2634`) | `hlow` | **保持** | — |
| 33 | `--lts-max-steps` (`:2649`) | `max_steps` | **保持** | 也是 band 预算（审计 c4） |
| 34 | `--lts-level` (`:2664`) | 5 阈值 | **保持** | — |
| 35 | `--lts-mode-overlap-min` (`:2678`) | `mode_overlap_min` | **保持** | — |
| 36 | `--lts-alpha` (`:2693`) | `alpha` | **保持** | — |
| 37 | `--lts-micro-cycles` (`:2708`) | `max_micro_cycles` | **保持** | — |
| 38 | `--lts-target-mode` (`:2723`) | `target_mode` | **保持** | — |
| 39 | `--lts-init-mode` (`:2738`) | `init_mode` | **保持** | — |
| 40 | `--lts-delta` (`:2752`) | `delta` | **保持** | bohr（dimer） |
| 41 | `--lts-dr` (`:2768`) | `dR` | **保持** | bohr |
| 42 | `--lts-rot-max-iter` (`:2783`) | `rot_max_iter` | **保持** | — |
| 43 | `--lts-rot-alpha` (`:2798`) | `rot_alpha` | **保持** | — |
| 44 | `--lts-rot-frms` (`:2813`) | `rot_f_rms_th` | **保持** | — |
| 45 | `--lts-ninit` (`:2829`) | `n_init` | **保持** | — |
| 46 | `--lts-seed` (`:2843`) | `seed` | **保持** | — |
| 47 | `--lts-step-max` (`:2858`) | `step_max` | **保持** | bohr |
| 48 | `--lts-translate-max-iter` (`:2873`) | `translate_max_iter` | **保持** | — |
| 49 | `--lts-recalc` (`:2889`) | `recalc` | **保持** | — |
| 50 | `--lts-no-verify` (`:2904`) | `verify_ts` | **保持** | — |
| 51 | `--lts-no-rigid` (`:2908`) | `remove_rigid` | **保持** | — |
| 52 | `--lts-restart` (`:2913`) | `engine%restart_mode` | **保持** | — |
| 53 | `--lts-hessian` (`:2932`) | `ltset%hessian_source` | **保持** | — |
| 54 | `--lts-hessian-file` (`:2946`) | `ltset%hessian_file` | **保持** | — |
| 55 | `--lts-step` (`:2956`) | `engine%hess_step` | **别名** | → `--lts-hess-step`（bohr） |
| 56 | `--lts-sccacc` (`:2972`) | `engine%hess_acc` | **保持** | — |
| 57 | `--lts-step0` (`:2988`) | `step0` | **保持** | bohr（dimer） |
| 58 | `--lts-escape-step` (`:3003`) | `escape_step` | **保持** | bohr |
| 59 | `--lts-product` (`:3020`) | `path%product_file` | **保持** | — |
| 60 | `--lts-images` (`:3031`) | `path%n_images` | **保持** | — |
| 61 | `--lts-kmin` (`:3046`) | `path%k_min` | **保持** | — |
| 62 | `--lts-kmax` (`:3061`) | `path%k_max` | **保持** | — |
| 63 | `--lts-kdecay` (`:3076`) | `path%k_decay` | **保持** | — |
| 64 | `--lts-no-dynamic-k` (`:3091`) | `path%use_dynamic_k` | **保持** | — |
| 65 | `--lts-climb` (`:3096`) | `path%climb` | **保持** | — |
| 66 | `--lts-climb-switch` (`:3101`) | `path%climb_switch_rms` | **保持** | — |
| 67 | `--lts-no-idpp` (`:3117`) | `path%ifidpp` | **保持** | — |
| 68 | `--lts-no-align` (`:3122`) | `path%align` | **保持** | — |
| 69 | `--lts-relax-ends` (`:3127`) | `path%relax_ends` | **保持** | — |
| 70 | `--lts-max-displ` (`:3132`) | `path%max_displ` | **保持** | bohr |
| 71 | `--lts-frms-avg` (`:3147`) | `path%f_rms_avg_tol` | **保持** | — |
| 72 | `--lts-frms-max` (`:3162`) | `path%f_rms_max_tol` | **保持** | — |
| 73 | `--lts-autoneb-nstart` (`:3177`) | `path%autoneb_nstart` | **保持** | — |
| 74 | `--lts-autoneb-max-paths` (`:3192`) | `path%max_paths` | **保持** | — |
| 75 | `--lts-autoneb-max-depth` (`:3207`) | `path%max_depth` | **保持** | — |
| 76 | `--lts-autoneb-restart` (`:3222`) | `path%autoneb_restart_file` | **保持** | — |
| 77 | `--lts-string-nnodes` (`:3233`) | `path%string_nnodes` | **保持** | — |
| 78 | `--lts-string-grow-tol` (`:3248`) | `path%string_grow_tol` | **保持** | — |
| 79 | `--lts-string-ds` (`:3263`) | `path%string_ds` | **保持** | bohr |
| 80 | `--lts-string-nu2` (`:3278`) | `path%string_nu2` | **保持** | — |
| 81 | `--lts-string-grow-steps` (`:3293`) | `path%string_grow_steps` | **保持** | — |
| 82 | `--lts-no-string-spline` (`:3308`) | `path%string_spline` | **保持** | — |
| 83 | `--lts-string-history` (`:3313`) | `path%string_history` | **保持** | — |
| 84 | `--lirc` (`:3318`) | runtyp | **保持** | — |
| 85 | `--lirc-method` (`:3325`) | `lircset%method` | **别名** | → `--method` |
| 86 | `--lirc-step` (`:3341`) | `step_length` | **保持** | **单位 bohr·amu^½**，必须标注（§7.3） |
| 87 | `--lirc-max-steps` (`:3357`) | `lircset%max_steps` | **保持** | — |
| 88 | `--lirc-level` (`:3372`) | 5 阈值 | **保持** | help 补默认（审计 c2） |
| 89 | `--lirc-swap` (`:3388`) | `swap` | **保持** | — |
| 90 | `--lirc-oneway` (`:3393`) | `both_directions` | **保持** | — |
| 91 | `--lirc-target-mode` (`:3398`) | `target_mode` | **保持** | — |
| 92 | `--lirc-micro-cycles` (`:3413`) | `max_micro_cycles` | **保持** | — |
| 93 | `--lirc-micro-thresh` (`:3428`) | `micro_step_thresh` | **保持** | — |
| 94 | `--lirc-euler-n` (`:3443`) | `euler_n` | **保持** | — |
| 95 | `--lirc-loose-cycles` (`:3458`) | `loose_cycles` | **保持** | — |
| 96 | `--lirc-mbs-tol` (`:3474`) | `mbs_tol` | **保持** | — |
| 97 | `--lirc-mbs-max-k` (`:3490`) | `mbs_max_k` | **保持** | — |
| 98 | `--lirc-mbs-points` (`:3505`) | `mbs_points` | **保持** | — |
| 99 | `--lirc-dwi-n` (`:3520`) | `dwi_n` | **保持** | — |
| 100 | `--lirc-e-rise` / `--lirc-erise-steps` (`:3537`) | `e_rise_steps` | **保持** | 一行两拼写，均保留 |
| 101 | `--lirc-grad-tol` (`:3552`) | `grad_tol` | **保持** | — |
| 102 | `--lirc-recalc` (`:3567`) | `hessian_recalc` | **保持** | — |
| 103 | `--lirc-no-endpoint-relax` (`:3582`) | `endpoint_relax` | **保持** | — |
| 104 | `--lirc-endpoint-relax` (`:3587`) | `endpoint_relax` | **保持** | — |
| 105 | `--lirc-rmsd-end` (`:3593`) | `rmsd_end` | **保持** | bohr |
| 106 | `--lirc-hessian` (`:3610`) | `lircset%hessian_source` | **保持** | — |
| 107 | `--lirc-hessian-file` (`:3624`) | `lircset%hessian_file` | **保持** | — |
| 108 | `--lirc-step-hess` (`:3634`) | `engine%hess_step` | **别名** | → `--lirc-hess-step`（bohr） |
| 109 | `--lirc-sccacc` (`:3649`) | `engine%hess_acc` | **保持** | — |
| 110 | `--lirc-restart` (`:3664`) | `engine%restart_mode` | **保持** | — |
| 111 | `--lvib` (`:3683`) | runtyp | **保持** | — |
| 112 | `--lvib-hessian` (`:3689`) | `lvset%hessian_source` | **保持** | — |
| 113 | `--lvib-hessian-file` (`:3703`) | `lvset%hessian_file` | **保持** | — |
| 114 | `--lvib-step` (`:3714`) | `engine%hess_step` | **别名** | → `--lvib-hess-step`（bohr） |
| 115 | `--lvib-sccacc` (`:3729`) | `engine%hess_acc` | **保持** | — |
| 116 | `--lvib-odlr` (`:3744`) | `engine%odlr` | **保持** | — |
| 117 | `--lvib-no-project` (`:3751`) | `project_tr` | **保持** | — |
| 118 | `--lvib-temp` (`:3756`) | `temperature(1)` | **保持** | 单位 K；与 `--etemp` 同名相近需在 help 区分 |
| 119 | `--lvib-rotor-cutoff` (`:3774`) | `rotor_cutoff` | **保持** | cm⁻¹ |
| 120 | `--lvib-imag-cutoff` (`:3790`) | `imag_cutoff` | **保持** | cm⁻¹ |
| 121 | `--lvib-freq-scal` (`:3807`) | `freq_scal` | **保持** | 无量纲 |
> **本表共 121 行、122 个拼写**（第 100 行 `--lirc-e-rise / --lirc-erise-steps` 是一行两拼写）。
> 汇总：**保持 115 / 别名 7 / 重命名 0 / 移除 0**。

**别名 7 条汇总**：`--lopt-engine`、`--lscan-method`、`--lts-method`、`--lirc-method`（→ `--method`）；
`--lts-step`、`--lvib-step`、`--lirc-step-hess`（→ `--l*-hess-step`）。

### 6.3 新增旗标（非破坏）

| 新旗标 | 作用 | 依据 |
|---|---|---|
| `--method NAME` | 统一方法选择器 | §4 |
| `--lopt-max-steps N` | 补缺口（`--lopt` 迭代预算现在固定 256，`settings.f90:355`） | 审计 §3.2「最值得注意」第 1 条 |
| `--lopt-hess-step V` / `--lscan-hess-step V` | 补缺口（`--lopt`/`--lscan` 现在没有 hess 步长旋钮） | 审计 §4.5 |
| `--lts-hess-step V` / `--lirc-hess-step V` / `--lvib-hess-step V` | 规范名（旧名别名） | §7.2 |
| `--lopt-sccacc V` / `--lscan-sccacc V` | 补缺口 | 审计 §4.5 |
| `--lopt-restart MODE` / `--lvib-restart MODE` | 补缺口（现在只有全局 `--restart/--norestart`） | 审计 §4.5 |
| `--method ancopt`（值，非旗标） | 方案 C 的 ANCopt 出口 | §3.0 |

### 6.4 受影响的原生参数

| 原生旗标 | 影响 | 动作 |
|---|---|---|
| `--opt [LEVEL]`（`main.F90:2153`） | runtyp 改派到套件（方案 C） | **语义改变**（§3、§10 A1） |
| `--ohess [LEVEL]`（`main.F90:2166`） | runtyp 改派（方案 C） | **语义改变**（§10 B1..B5） |
| `--cycles INT`（`main.F90:1955`） | 现存 CLI 旋钮（只影响原生 ANCopt，`get_optthr` 的 `maxcycle`）；套件 `--lopt` **不读它** | **新增映射**：`--cycles` 在套件 runtyp 下映射到 `--lopt/lscan/lts/lirc-max-steps`，或**响亮报错**（§9.1 阶段 2；否则 C 之后 `--cycles` 对 `--opt` **静默失效** = 新缺陷） |
| `--hess`（`main.F90:2160`） | 无 | 保持 |
| `--bhess`/`--metaopt`/`--path`/`--modef`/`--screen` | 无（保持原生） | 保持；但 `--method` 在其上报错（§4.6） |
| `-s`/`--silent`（`xhelp.f90:780`，**未实现**；`[R17]` 旧稿误写 775） | 设计想用它抑制提示 | **必须实现**，否则提示无条件打印（§3.4）；也可在做 §8 时顺手实现 |
| `--ithr`/`--xparam`（`xhelp.f90:722,170`，**未实现**；`[R17]`） | 与本次设计无关 | 列为 §8.6 的收口项 |

---

## 7. 命名一致性方案

### 7.1 同概念两名：`--lopt-engine` vs `--lscan-method`

**现状**（`file:line`）：`main.F90:2251`（`--lopt-engine` → `lset%algorithm`）与
`main.F90:2316`（`--lscan-method` → `lsset%method`）**指向同一个枚举集合**
（都用 `landscape_opt_algorithm_from_name`，`settings.f90:1112`）。

**方案**：引入规范名 `--method`；两者都成为别名（§4.3）。**不重命名、不弃用**——
因为存在大量既有脚本，且两个名字都无歧义。`--help` 里把 `--method` 放最前，旧名放其后
（`--lopt-engine NAME (alias of --method)`）。

**取舍原则**：**同概念两名 → 用别名统一到第三个规范名，而不是删掉其中一个。**
（理由：删除是破坏性的，而冗余别名不产生歧义成本。）

### 7.2 `hess_step` 的三个名字（`--lts-step` / `--lvib-step` / `--lirc-step-hess`）

**现状**：三者写**同一字段** `engine%hess_step`（`settings.f90:333`），
解析点 `main.F90:2956 / 3714 / 3634`。`--lopt`/`--lscan` **完全没有**。

**方案**：

| 任务 | 规范名（新） | 旧名（别名，保留） |
|---|---|---|
| opt | `--lopt-hess-step` | （原无） |
| scan | `--lscan-hess-step` | （原无） |
| ts | `--lts-hess-step` | `--lts-step` |
| irc | `--lirc-hess-step` | `--lirc-step-hess` |
| vib | `--lvib-hess-step` | `--lvib-step` |

**单位**: bohr（FD 位移）。**规范名的后缀 `-hess-step` 明确表示"数值 Hessian 的差分步长"**，
消除了与 `--lirc-step`（弧长）的混淆。

**取舍原则**：**当一个字段有多个不一致的名字、且其中一个名字与别的物理量撞车时 → 引入规范名 + 保留别名。**
（`--lirc-step-hess` 与 `--lirc-step` 只差后缀，是本次最危险的一对，必须修。）

### 7.3 `-step` 一词三义两单位（单位必须体现在名字或文档里）

| 旗标 | 真实含义 | 单位 | 处理 |
|---|---|---|---|
| `--lscan-step` / `--lscan-step2` | 扫描坐标的**增量** | **Å（距离）/ 度（角度）** | **保持名字**；`--help` 与运行回显写单位；`main.F90:3878-3889` 已有换算（bohr 内部，`[R17]` 旧稿误写 3836-3844） |
| `--lirc-step` | IRC **弧长**（宏步长） | **bohr·amu^½** | **保持名字**；help 写单位；运行时回显 |
| `--lts-step`/`--lvib-step`/`--lirc-step-hess` | FD Hessian **差分位移** | **bohr** | 按 §7.2 → `--l*-hess-step`；help 写单位 |
| `--lts-step0` / `--lts-step-max` / `--lts-escape-step` | dimer 平移/上限/逃逸 | bohr | 保持；help 写单位 |

**取舍原则**：**只有在"名字歧义会导致误用"时才改名字**。`--lscan-step` 的单位是 Å 而套件内部
通篇 bohr（`settings.f90:20-22`），确有误用风险；但改名字（`--lscan-step-ang`）是破坏性的，
**收益不足以抵消** ⇒ **用文档 + 回显解决**。相反 `--lirc-step` vs `--lirc-step-hess`
是**同前缀不同物理量**，误用代价高 ⇒ **改名（别名）**。

**硬性要求（设计判据）**：**每一个带单位的旗标，其 `--help` 行必须含单位字符串，
且运行时必须回显有效值与单位。** 这是可测的（§9.2 的 `help-unit-annotation` 检查）。

### 7.4 缺口补齐

| 缺口 | 补齐 | 依据 |
|---|---|---|
| `--lopt-max-steps` 不存在 | 新增 | 审计 §3.2 |
| `--lopt`/`--lscan` 无 hess 步长 | 新增 `--l*-hess-step` | 审计 §4.5 |
| `--lopt`/`--lscan` 无 sccacc | 新增 `--l*-sccacc` | 审计 §4.5 |
| `--lopt`/`--lvib` 无 restart | 新增 `--lopt-restart`/`--lvib-restart` | 审计 §4.5 |
| `--lts` 无频率确认旋钮（`--lvib` 有 `--lvib-no-project`/`--lvib-imag-cutoff`） | 建议新增 `--lts-project-tr`/`--lts-imag-cutoff` | 审计 §3.2 第 2 条 |
| `--lsp`（套件单点 API-only） | **不做**（原生 `--sp` 已覆盖；见 §11 不建议项） | W1 §3 G1 |

### 7.5 大小写与别名

**[实测]** 套件的枚举值是**大小写敏感**的：

```
--lopt-engine BFGS   → -1- ... Unknown landscape minimisation algorithm 'BFGS'
--lopt-level Normal  → -1- ... Unknown landscape convergence level 'Normal'
--lts-method PRFO    → -1- ... Unknown landscape transition state method 'PRFO'
```

而上游 `--alpb`/`--gbsa` 的溶剂名是**大小写不敏感**的
（`commandline.html`: "The solvent input is not case-sensitive."）。

**方案（非破坏）**：所有套件的**枚举名匹配前先转小写**（`trim` + lowercase）。
这只把"报错"变成"接受"，不影响任何既有可解析的调用。
（`[未验证]`：`--lopt-engine` 的 6 个名字与 `--lts-method` 的 8 个名字是否有大小写冲突的实例
——本机测试里没有；转小写对既有行为的唯一影响是把 `BFGS` 从错误变成 `bfgs`。）

### 7.6 取舍原则（总结）

| 情形 | 动作 | 理由 |
|---|---|---|
| 同概念两名，都无歧义 | **别名**到新的规范名 | 删除是破坏性的，别名零成本 |
| 名字歧义会导致高代价误用（`--lirc-step` vs `--lirc-step-hess`） | **新增规范名 + 旧名别名** | 不静默、不破坏 |
| 单位不同但名字可辨 | **保持 + 文档 + 回显** | 改名收益 < 破坏成本 |
| 缺旋钮 | **新增** | 纯增量 |
| 与上游同名不同义（`--lX-hessian` vs `$opt hessian=`） | **保持，但在 help 里明确措辞** | 上游的 `hessian` 不是 CLI 旗标，冲突面小 |

---

## 8. 非破坏性改进（可先落地，不依赖 `--opt` 决策）

> 这些改动**全部满足 BC-1..BC-4**（唯一例外是 §8.1 会把若干"静默首选项获胜"的调用变成 error，
> 见 §5.1 #20/#21/#23/#25 —— 它们属于**语义改变（变响亮）**，需逐条确认）。

### 8.1 冲突组合检测

**[实测] 现状**：`--lopt --lscan` 静默跑 `--lopt`（§2.6b）。
**机制**：`set_runtyp` 的锁在 `set_module.f90:1034-1038`，消息进 `persistentEnv`，**从未打印**。

**方案（推荐，最小）**：在 `parseArguments` 里维护一个"已选 runtyp 的**用户可见**记录"，
第二次要求不同 runtyp 时 `env%error(...)`：

```
landscape/native run type conflict: --opt already selected the 'opt' run type,
--lscan would select 'lscan'. Only one run type can run; use --ohess or run two jobs.
```

**实现要点**：**不要**依赖 `set_runtyp`（它是 `save` 状态，且上游也可能被别的路径调用）。
在 `main.F90` 的每个 runtype case 里调用一个新的 `select_runtyp(env, typ, flag)` 包装，
它同时记录 `flag` 字符串以生成可操作消息。

**会转变的最常见调用**（必须逐条确认）：`--lopt --lscan`、`--opt --hess`、`--lts --lirc`、
`--opt --lopt`、`--hess --opt`、`--lvib --hess`（若同时给）。**列进 §10 的"变响亮"清单。**

### 8.2 必填参数报错点名 flag

**[实测] 现状**（审计 §4.2，本轮复核）：
`--lscan`（什么坐标都没给）→ `landscape_scan_check: atom index 0 of the distance coordinate is outside 1..3`
——**不点 `--lscan-atoms`**。

**方案**：沿用 M4 已建立的约定（`--lts-product` 那条：`pass it with --lts-product <file>`），
把 `scan` 的 4 条必填检查改成点名 flag：

| 现状消息 | 新消息（设计） |
|---|---|
| `atom index 0 ... outside 1..3` | `the distance coordinate needs --lscan-atoms 1,2 (atom indices are 1-based)` |
| `coordinate 1 has a zero step size` | `coordinate 1 has a zero step size; set it with --lscan-step <value> (angstrom)` |
| `coordinate 1 has nstep = 0 ...` | `coordinate 1 has nstep = 0; set it with --lscan-nstep <n>` |
| `--lvib --lvib-hessian file` 缺 file | 已点名 ✅ |

**实现点**：`src/landscape/scan/*.f90` 的检查子程序（`landscape_scan_check`）。

### 8.3 危险默认的回显

**[实测] 现状**：`--lscan-fc` 默认 0.5 hartree/bohr²（`settings.f90:545`），**是 xtb 自身
`fcconstr=0.05` 的 10 倍**（`src/scanparam.f90`），且**没有回显**。

**方案**：任何**与上游默认不同**的套件默认值，在任务开始时打印一行 `[NOTICE]`：

```
[NOTICE] --lscan-fc default 0.5 hartree/bohr^2 differs from the xtb scan force constant 0.05;
         pass --lscan-fc 0.05 for the legacy xtbscan.log behaviour.
```

**清单**（审计 §3.3）：D1 `--lscan-fc`、D2 `--lirc-method=hpc`（M6 已改默认）、
D3 `--lopt-engine=lbfgs`（在 C 之后与 `--opt` 的旧默认不同）、
D4 `--lscan` 默认双向、D5 `$thermo`（**R18 修订：此条已不是缺陷** ——
W0 已把 `--lvib` 改为"**显式 CLI > xcontrol `$thermo` > 内置默认**"，`src/landscape/vib/thermo.f90:32-35,51-53` 与
`landscape_vib_set_thermo_settings`/`landscape_vib_check_thermo_settings` 两个入口可核；旧稿"无条件覆盖"
与 `vib/thermo.f90:167-180` 的行号均**已过期**，不再是"危险默认"，只是一个正常默认）、
D7 `--lts-escape-step` 移动输入几何。

### 8.4 `--help` 与实现的**双向一致性检查**机制

**现状**：`main.F90` 的 230 拼写 vs `xhelp.f90` 的 204，差集 30（已实现未文档化）+ 4（已文档化未实现），
**套件部分双向差集为 0**（审计 §2）。

**方案（可自动化，非破坏；R25 改写，M-4）**：新增测试 `xtb/landscape-help-coverage`，**分两个集合、两个门槛**：

- **集合 S（套件旗标）** = `main.F90` / `xhelp.f90` 里以 `--l` 开头或等于 `--method` 的拼写。
  **断言 S_A == S_B（差集必须为空）** —— 这是**阶段 1 的验收门槛**
  （今天 [实测/复核已核] 双向差集均为 0；套件侧 122/122，见 `2-*.md §2.1`）。
- **集合 N（原生旗标）** = 其余拼写。审计口径下 **N_A − N_B = 30**（已实现未文档化）、
  **N_B − N_A = 4**（已文档化未实现：`--ithr`/`--xparam`/`-s|--silent`；`2-*.md §2.2/§2.3` 逐条列表）。
  **这一侧不断言为空**：测试把两侧差集**打印**并把 N 侧作为**已知清单**登记在 §8.6，由**阶段 4** 收口。
  ⇒ 阶段 1 的"新增测试全绿"与"差集非空则失败"不再矛盾（M-4）。
- 第 4 步"单位 token"同前（只对集合 S 断言）。

> **可复现性说明（R25 新增，重要）**：差集的具体数字**依赖抽取规则**。
> 用审计的规则（`2-*.md §2.1`："以 `-` 开头的行首选项串，逗号别名拆开，`[no]` 展开"）得到 **30 / 4**；
> 用"正则抓引号内以 `-` 开头的 token"得到 **34 / 5**（本轮实测，差异来自 `--gfn0/1/2` 的合并写法 `--gfn[0|1|2]` 与
> `--nocopy` 的 `[no]` 展开）。⇒ **测试脚本必须把抽取规则写死、并把规则与两个计数打印到输出**；
> 报告里贴出这两个数字。"差集为空"只对集合 S 断言（集合 S 不受这几种写法影响）。

> **注意**：`--help` 的双向一致是 BC-2 的**可执行判据**（旗标不消失）。

### 8.5 未知参数 / 未知枚举值：绝不静默

| 缺陷 | 现状证据 | 方案 |
|---|---|---|
| 未知旗标只 warning，`--strict` 管不到 | [实测] `main.F90:1583`；`env%strict` 在 `:608` 才设 | 把 `strict` 的读取提前到解析循环内（`case('--strict')` 时同步 `env%strict`），使 `--strict --zzzz` 真正失败 |
| 未知枚举值（`--opt banana`）静默回退 | [实测] `set_module.f90:1910` `case default → p_olev_normal`（`[R17]` 旧稿误写 1912） | 套件侧已 error（§2.3 实测）；**原生侧建议同样 error**（属上游缺陷，可单独修） |
| 套件 `--method`/`--l*-level` 未知值 | 已 `env%error` ✅（`main.F90:2274` 等） | 保持 |
| 套件枚举大小写敏感 | [实测] `BFGS` → 错误 | 转小写（§7.5） |

### 8.6 已实现未文档化 / 已文档化未实现：收口

> **R25 修订**：本节的两份清单就是 §8.4 "集合 N" 的**已知清单**。§8.4 的测试把它们的差集**打印**，
> 但**不**作为任何阶段的门槛（阶段 1 只看集合 S）；本节的具体条数随抽取规则而定（30/4 与 34/5 两种口径，见 §8.4）。
> 收口属**阶段 4**。

**方案**：§8.4 的脚本同时给出这 34 条的**当前差集**；收口动作：
- 30 个"已实现未文档化"（**全部是原生旗标**，审计 §2.2 逐个列出）→ 补 `xhelp.f90` 条目。
  其中 `--version`/`-V`/`--very-verbose` 是最该补的。
- 4 个"已文档化未实现"（`--ithr`（`xhelp.f90:722`）、`--xparam`（`:170`）、`-s|--silent`（`:780`））→ **实现或从 `--help` 移除**。
  （`[R17]` 旧稿误写 `:775`/`:717`。）
  `-s/--silent` 因为 §3.4 想用它，**建议实现**（一个全局 quiet 标志，抑制非 `[NOTICE]`/`[WARNING]` 输出）。
- **R18**：`--lvib` 对 `$thermo` 已由 W0 改为"显式 CLI > xcontrol `$thermo` > 内置默认"
  （`src/landscape/vib/thermo.f90:32-35,51-53`），**本节旧稿的"改为…"动作已完成，不再列入**。

### 8.7 【R6 新增】决策 4：C1–C4 四处静默丢弃改为**响亮错误**

> **现状实测（父会话，`/tmp/xtb-w2/build/xtb`）**：四条全部 exit 0、无任何提示；
> 机制是 `set_module.f90:1031-1038` 的 `set_runtyp` 锁消息进了 `persistentEnv` 而**从未到达用户**，
> 或者套件子选项被写入一个**没人读**的字段。
> **共同实现基座**（§8.1）：新增一个 `select_runtyp(env, typ, flag)` 包装，在 `parseArguments` 里
> 代替直接 `set_runtyp`；它记录"用户可见的首选 runtyp + 旗标名"，第二个**不同** runtyp 即 `env%error`。
> 退出码一律 **1**（`env%error` + `env%checkpoint`，`environment.f90:266-294`）。

| # | 调用 | 触发条件（检测点 file:line） | 错误文本（设计） | 测试（断言） |
|---|---|---|---|---|
| **C1** | `--lopt --lscan` | 两次 `select_runtyp` 且 typ 不同：`main.F90:2244`（lopt）与 `:2296`（lscan） | `"landscape run type conflict: --lopt already selected the 'lopt' run type, --lscan would select 'lscan'; only one run type can run (use --ohess, or run two jobs)"` | `xtb/landscape-runtype-conflict`（现无，新增）：断言非零退出 + 文本含 `--lscan` |
| **C2** | `--opt --lopt` | 两次 `select_runtyp` 且 typ 不同：`main.F90:2153`（opt）与 `:2244`（lopt） | `"run type conflict: --opt (now the landscape suite optimiser) and --lopt are different run types; keep one of them, or pass --method ancopt to run the native ANCopt"` | `xtb/landscape-opt-lopt-conflict`（新增） |
| **C3** | `--lts --lopt-engine bfgs` | 共享 setter 检测旗标归属 ≠ 当前有效任务：`--lopt-engine` 的 case `main.F90:2251` + `effective_landscape_task`（§3.11） | `"--lopt-engine belongs to the lopt task; use --lts-method bfgs (or --method bfgs) for a transition state search"` | `xtb/landscape-subflag-mismatch`（新增）：`--lts --lopt-engine bfgs` 非零退出 + 文本含 `--lts-method` |
| **C4** | `--hess --lvib-temp 400` | 同 C3：`--lvib-temp` 的 case `main.F90:3756`；当前 runtyp 为 `p_run_hess`（非 lvib） | `"--lvib-temp belongs to the lvib task; add --lvib, or use --etemp 400 for the native --hess chain"` | `xtb/landscape-vib-temp-mismatch`（新增） |

**爆炸半径（§9.4 的强制 grep 结果）**：复核已代跑 ——
`--opt ` **1 命中**（即 R2）、双 runtype 组合 **0 命中**；⇒ **C1/C2 不会撞既有测试**。
C3/C4 需在实现前 grep 一遍套件子选项与原生 runtype 的混用。

**注意（与 §2.6b 的区别）**：这里报 **error 而不是静默丢弃** —— 正是"绝不静默"的落地。
但 **§8.1 的旧稿措辞 "`--opt --hess` 走 `--opt` + error/warning" 作废**：
`--opt --hess` 属 C2 族（双 runtype），**报 error**；同时 `--opt` 本身还会先把任务送到套件（若 `--opt` 是首个）
—— 两个检测点**同一次运行都要跑**，因此实施时需保证 `select_runtyp` 的检查**早于**套件分派（同在 `parseArguments` / 主流程入口）。

---

## 9. 实施计划

### 9.1 阶段划分（每阶段可独立验收）

> 阶段 1 与 2 **不依赖** `--opt` 决策（除阶段 1 的 §8.1 冲突检测会动 `--opt` 的既有行为）。

**阶段 1 — 非破坏性改进（可立即落地）**
- §8.1 冲突检测（runtype 冲突 → error）
- §8.2 必填参数点名
- §8.3 危险默认回显
- §8.4 `--help` 双向检查测试
- §8.5 `--strict` 提前 + 套件枚举转小写
- 验收：新增测试全绿（**含 `xtb/landscape-help-coverage` 的**集合 S（套件旗标）**差集为空；集合 N（原生）**差集只打印、**不作为门槛**，R25）；§5.1 的 #20/#21/#23/#25 变红（**逐条确认**）；其余 BC-4 逐位不变。

> **阶段 1 的阻塞已解除（第 2 轮复核后）**：只需先修 M-4（本节，已改）、M-1（§5.4，已改），
> 并落 H3 的**套件部分**解析尾机制（§4.7 的第 1/2/3 段；原生分支属阶段 3）。

**阶段 2 — `--method` 统一选择器（非破坏）**
- 新增 `--method`；四个旧旗标变别名；冲突 error；`--method` 在未改派 runtyp 上报错（§4.6）
- 新增缺口旗标（§6.3）：`--lopt-max-steps`、`--l*-hess-step`、`--l*-sccacc`、`--lopt/lvib-restart`
- 验收：`--method <name>` 对**每个**任务的每个取值都有"证明生效"的 CLI 测试（§9.2）；
  旧旗标逐条仍工作（BC-2）。

**阶段 3 — `--opt` / `--ohess` 改派（方案 C，破坏性）**
- `--opt [LEVEL]` / `-o` → 套件默认优化器 + `[NOTICE]`（**R11：stdout**）
- `--ohess [LEVEL]` → 套件 `opt+vib` 链 + `[NOTICE]`
- `--method ancopt` / `lancopt` / `fire`（+ 别名 `inertial`）/ `pbc_lbfgs`（**R21：四个都是真正的原生出口**，不再是"仅报错"）出口（§4.8）
- **R21/R22：解析尾归一的原生分支 + 单一 `landscape_native_engine` 标志**（§3.11/§4.7）——阶段 3 的**第一项**，
  否则 `--method ancopt` 会 `env%error`（H-1）、三条守卫会对原生 L-ANCopt/FIRE 误报（H-2）
- **R24：抑制原生 `if (anyopt)` 分支**（`main.F90:931` 加 `landscape_native_engine /= 0`）+ `--ohess` 的 opt→vib 链判据（§3.11）
- **R29（HIGH-1，第 3 轮复核）：`--ohess` 的**原生 Hessian/频率路径抑制**（§3.11.1）——T1 `main.F90:1156`、
  T2 `:1282` 改读 `landscape_native_hessian_path`；T3 `anyhess` 不改而用 **`fres` 桥**；
  另 `:1310-1320`（`xtbopt.xyz` 二次写）与 `:4065-4068`（计时标签）入抑制集合。**前置**：§4.7 第 0 段的
  `landscape_native_engine = 0`（R30/MEDIUM-1）—— 它必须与 R21 的原生分支**同一次改动**落地
- **R23：xcontrol `$opt` 守卫作用域全覆盖**（含 `--lopt` 等，破坏性 C7）+ `set%optset%xcontrol_supplied` 标志（§3.8c）
- 上游 level → 套件 level 映射（§3.5）+ 偏差告知；**R5：档位同时驱动阈值/`e_tol`/`acc`/`max_steps`**（建议分 3a/3b，§3.10）
- **R1 三类守卫**（§3.8）：`$scan`、周期体系、xcontrol `$opt` 块 → 响亮报错 + 指向 `--method ancopt`
- **R6 C1–C4 响亮错误**（§8.7）+ **R13 通用规则**（原生 runtype + 套件子选项）
- `--cycles` 映射（§3.10b）/ `--lvib` 下报错
- `--ljson` 消息列表更新 + `--opt --ljson` 真的写 `landscape_opt.json`（§5.3）
- **R4 文件契约**（§3.9）：套件 `opt`/`vib` 写全 `.xtboptok`/`xtbopt.log`/`xtblast.xyz`/`compliance.dat`
- **R2/R3 测试更新（必须）**：把 `test/unit/landscape_cli_check.py` 的 `check_scanblock` **492-503 段**
  从"断言 `--opt` 执行 `$scan`"改为"断言 `--opt` + `$scan` **响亮报错** + 错误信息指向 `--method ancopt`/`--lscan`"，
  **保留前半段**（466-491 的 5 个套件 runtyp 拒绝断言）；报告里贴出**改动前后**的测试输出
- **R3 自指引导清理**（§14.6）：`main.F90:505-508` 与 `xhelp.f90:285-286` 不再把 `--opt` 当作 `$scan` 入口；
  `xhelp.f90:270-271` 与 `man/xtb.1.adoc:238-241` 的 "`--opt` call ancopt(3)" 描述改为套件
- 验收：§10 逐类有测试（**含 C7**）；BC-5（提示存在）有测试；BC-4 对**未改派** runtyp 仍成立；
  **§3.10 的再基线清单逐个重测**（含单元测试、CLI 测试、M2/M3/M4/M6/M7 的已验收数字）；
  **H-1/H-2/M-3/R29 的 CLI 级断言全绿**（§4.7.1 的 **20 条**，特别是四个原生出口、"只跑一次"与 `--ohess` 的 4 条；`R29` 把该表由 14 行扩到 20 行）

> **阶段阻塞状态（R35 更新为四态，取代第 2 轮的两态结论）**：
> 阶段 1 = **可实施**（第 3 轮复核确认，工作清单见 §17）；阶段 2 = **可实施**；
> 阶段 3 的 **`--opt` 半边 = 可实施**（H-1/H-2/M-2 已闭合、M-3 的 `:931` 抑制已指定；前置 = R30 的一行）；
> 阶段 3 的 **`--ohess` 半边 = 本轮 R29 闭合后可实施**（三个触发点逐个给了判据/位置/测试 + 自证表）。
> 两个半边都必须把 R30 的 `landscape_native_engine = 0` 作为**第一项**落地。

**阶段 4 — 文档与收口**
- `xhelp.f90` 补 30 条原生 + 更新套件 help 的单位/默认
- `man/` 与 `docs/` 同步
- 弃用策略（§9.3）

### 9.2 测试策略（沿用本项目"每个选项都要有证明其生效的测试"）

**强制表格**（沿用 M6 报告 46 §2.4 的模式）：为**每一个**新增/改派的选项建一行。
**R14（M6）**：下表补全了 §6.3 的**全部**新旗标与 §6.2 的**7 个别名**——旧稿只有 8 行，阶段 2 的"每个新增选项都有证明生效的测试"因此不可判。

| 选项（含别名） | 读取点 | 证明生效的测试 | 测试如何变红 |
|---|---|---|---|
| `--method bfgs`（每任务每取值，**23 个名字**——R9；**口径澄清（L-1）**：23 = 6 最小化器 + 8 ts + 4 irc + 4 原生引擎 + `auto`，**按引擎名字计**，不含 3 个原生别名拼写；若按拼写计则为 **25 个套件+原生拼写 + `auto`**，两者不可混用） | `settings.f90:*_from_name`；尾归一 §4.7 | `xtb/landscape-method-<task>-<name>`（断言 stdout 的算法名） | 删掉赋值 |
| `--method ancopt` / `rf` / `lancopt` / `l-ancopt` / `fire` / `inertial` / `pbc_lbfgs`（**R21：7 个拼写 / 4 个原生出口**（L-1 订正）） | §4.7 解析尾归一 + §4.8 | **§4.7.1 的 20 条 CLI 测试**（R29 后；断言原生分支：stdout 不含 `landscape:`，含实测唯一 token `ANC micro-cycles`/`L-ANC optimizer`/`initial time step`/`current lattice:`；`--ohess` 的 4 条见 §3.11.1） | 把该名字的映射删掉（→ 0）或改到别的引擎（token 变） |
| 套件/原生身份谓词（H-2） | §3.11 `effective_landscape_task`/`landscape_is_suite_run` | `xtb/landscape-guard-fire-no-scan`（`--opt --method fire` + `$scan` **不**报错）、`-guard-fire-no-opt`（+ `$opt` 块不报错）、`-guard-pbc-native`（原生周期 exit 0） | 谓词退化为 `native_engine == p_engine_rf`（三个测试均红，R22 的反例） |
| 原生块抑制（M-3） | §3.11 读点表 #4；`main.F90:931` | `xtb/landscape-opt-alias-once`（`--opt --ljson`：含 `landscape: lbfgs minimisation`、**不含** `ANC micro-cycles`、`n_steps` == `--lopt`）；`-opt-native-nojson`（`--opt --method ancopt --ljson` 不写 json） | 去掉 `landscape_native_engine /= 0` ⇒ 两个测试各自反向红 |
| **原生 Hessian/频率抑制（R29/HIGH-1）** | §3.11.1；`main.F90:1156`（`numhess`）、`:1282`（`main_freq`）、`:1310-1320`、`:4065-4071` | `xtb/landscape-ohess-suite-once`（`--ohess`：`Numerical Hessian`=0、`Frequency Printout`=0、`landscape: harmonic frequencies`=1、`landscape engine: Hessians` 行=1）；`-ohess-native-hess`（`--ohess --method ancopt` 反向）；`-ohess-fres-bridge`（`TOTAL ENTHALPY`/`TOTAL FREE ENERGY` 与 `--lvib` 一致）；`-opt-xtbopt-once`（`wrote xtbopt.xyz`=1） | 见 §3.11.1 的逐行突变列（每个 token 都有对应的单行突变） |
| **标志初值（R30/MEDIUM-1）** | §3.11.2；`main.F90:1574` 前一行 | **静态核**：`grep -n "landscape_native_engine" src/prog/main.F90`（得声明行、flag 循环前行、第 2 段两处）；运行时烟难：`xtb/landscape-lopt-no-method` | —— |
| xcontrol `$opt` 守卫作用域（M-2/C7） | §3.8(c) | `xtb/landscape-opt-xcontrol-scope`（`--lopt --input <含 $opt>` 非零退出 + 点名 `--method ancopt`）+ §3.8c 原有 3 条 | 去掉守卫（今天 exit 0 静默 [实测]） |
| `--lopt-level` 不收上游名（L-4） | §3.5 | `xtb/landscape-method-level-bridge`（`--lopt-level lax` 非零；`--opt lax --method bfgs` exit 0 + `[NOTICE]`） | 把上游名加进 `landscape_conv_level_known` ⇒ 红 |
| `--lopt-engine`（别名） | `main.F90:2251` | 断言与 `--method <同名>` **输出逐位同**（别名等价性） | 改别名转发 |
| `--lscan-method`（别名） | `main.F90:2316` | 同上（`--lscan` 下） | 同上 | 
| `--lts-method`（别名，**带 climbing 副作用**） | `main.F90:2581` | 断言 `--lts --method cineb` 与 `--lts --lts-method cineb` 的 `climb` 行为同（`main.F90:2589-2593`） | 把副作用搬出共享 setter |
| `--lirc-method`（别名） | `main.F90:3325` | 同上（`--lirc` 下） | 同上 |
| `--lts-step` / `--lvib-step` / `--lirc-step-hess`（3 别名） | `main.F90:2956/3714/3634` | `xtb/landscape-hess-step-alias-<task>`：断言与 `--l*-hess-step` **同一字段**（JSON/回显） | 把别名指向另一字段 |
| `--lopt-max-steps N`（新） | `settings.f90:355` | `xtb/landscape-opt-max-steps`（N=8 vs 256 断言 `n_steps` 不同） | 删赋值 |
| `--lopt-hess-step` / `--lscan-hess-step`（新） | `settings.f90:333` | `xtb/landscape-hess-step-<task>`（断言 `engine%hess_step` 回显改变） | 删赋值 |
| `--lopt-sccacc` / `--lscan-sccacc`（新） | `settings.f90:335` | 同构 | 删赋值 |
| `--lopt-restart` / `--lvib-restart`（新） | `settings.f90` restart_mode | 同构 | 删赋值 |
| `--method` 冲突（异值） | §4.3 | `xtb/landscape-method-conflict`（`--method bfgs --lopt-engine cg` 非零退出） | 去掉冲突检测 |
| `--opt normal` → 套件（含 `-o`） | `main.F90:2153` | `xtb/landscape-opt-alias`（断言 stdout 含 `[NOTICE]` 与 `landscape: lbfgs`，且 `xtbopt.xyz` 与 `--lopt` 逐位同） | 还原原生分支 |
| `--opt` + `$scan` / 周期 / `$opt` 块 | §3.8 | `xtb/landscape-opt-scanblock`、`-opt-pbc`、`-opt-xcontrol`（非零退出 + 文本点名） | 去掉守卫 |
| level 映射 + 档位四轴 | §3.5 | `xtb/landscape-opt-level-map`（每个档位断言 `e_tol`/`acc`/`max_steps`/阈值回显） | 改一个映射 |
| `--cycles` 映射 | §3.10b | `xtb/landscape-cycles-map`、`-cycles-lvib`、`-cycles-conflict` | 去掉映射 |
| 冲突检测 C1/C2 | §8.7 | `xtb/landscape-runtype-conflict`、`-opt-lopt-conflict` | 去掉检测 |
| 子选项错配 C3/C4 + R13 通用规则 | §8.7 | `xtb/landscape-subflag-mismatch`、`-vib-temp-mismatch` | 去掉检测 |
| 必填点名 | §8.2 | `xtb/landscape-scan-required-flag`（断言消息里含 `--lscan-step`/`--lscan-atoms`/`--lscan-nstep`） | 还原旧消息 |
| 文件契约（4 文件） | §3.9 | `xtb/landscape-file-contract-opt` / `-opt-fail` / `-vib` / `-namespace` | 删一个写点 |
| `--help` 一致 + 单位 token 白名单 | §8.4 | Python 脚本断言 A==B；`help-unit-annotation` 正则白名单 **写死**为 `bohr|angstrom|Å|degree|K|cm\^-1|amu|Eh|hartree`（LOW-4，复核 §7 建议） | 在 `main.F90` 加一个不写 help 的 case |

**Falsifiability 要求**：每个新测试**必须证明它在旧代码下是红的**——
沿用 M4 报告 34 的教训：「先证明突变与被回退的逻辑**语义等价**，否则绿说明不了任何事」。

### 9.3 弃用策略

| 对象 | 策略 |
|---|---|
| `--lopt-engine` / `--lscan-method` / `--lts-method` / `--lirc-method` | **不弃用**（永久别名）。理由：它们无歧义、被大量脚本使用。`--help` 里标注为 alias。 |
| `--lts-step` / `--lvib-step` / `--lirc-step-hess` | **不弃用**（永久别名 → `--l*-hess-step`）。 |
| 别名是否打印警告 | **否**（用旧名不产生 warning）。理由：§2.5 的上游惯例是别名静默接受（`--gfnff/--gff` 无提示）；警告会淹没真正重要的 `[NOTICE]`。 |
| 将来若真要移除 | 需 ≥2 个发布周期 + `[DEPRECATED]` 警告 + 本文件与 AGENTS 同步。 |

### 9.4 回归风险（哪些既有测试会受影响）

| 风险 | 受影响的测试（file:line） | 影响 |
|---|---|---|
| `--opt` 改派 | 所有用 `--opt` 的原生 CLI 测试 | 数值变化；需逐个核对 |
| **R2：`$scan` 守卫** | **`xtb/landscape-scan-xcontrol`**（`CMakeLists.txt:3082-3088`；`landscape_cli_check.py:447-503`，尤其 **492-503**） | **会变红（必需）：492-503 段必须同步改写，见 §14.5** |
| **R15/M7：`§8.2` 要替换的两条消息** | `xtb/landscape-scan-atom-range`（断言 `outside 1..3`，`CMakeLists.txt:664-669`）与 `xtb/landscape-scan-nstep-missing`（断言 `at least one step is required`，`:658-663`） | 旧稿 §9.4 **漏列**；实施 §8.2 时必须**同步更新这两条测试断言**（否则变红） |
| 冲突检测变 error | 若有测试用 `--lopt --lscan` 之类组合 | 复核代跑：**0 命中**；不会变红 |
| `[NOTICE]` 写到 **stdout** | 若 CLI 测试用 `2>&1` 合并并断言整段输出 | 复核代跑：`2>&1` **0 命中**；但 CMake 同名 `ERROR_VARIABLE` 会合并 stderr（§3.4）；断言均子串式 ⇒ **多一行不会变红** |
| **R5：档位四轴** | 见 §3.10 的**完整再基线清单**（单元测试 6 文件 + CLI 2 文件 + CMake 14 处 + M2/M3/M4/M6/M7 验收数字） | 会移位；必须逐个重测 |
| `--help` 双向检查 | 新增测试自身 | 若 `xhelp.f90` 的解析规则写错，假阳性 |
| 枚举转小写 | 若有测试断言 `--lopt-engine BFGS` **报错** | 会变红（但这是有意的行为改变） |
| `--ljson` 消息文本改变 | `xtb/landscape-ljson-*` | 文本断言会变红（`main.F90:984-987`） |
| **R13 通用规则**（原生 runtype + 套件子选项 → error） | 需 grep 全部 `--opt ` / `--sp ` / `--hess ` 后面跟套件子旗标的组合 | 复核代跑 `--opt ` **1 命中**（R2）；其余待实施前 grep |
| **R21：四个原生出口**（`--method ancopt|lancopt|fire|pbc_lbfgs`） | 无（`--method` 是新旗标；今天它是 `Unknown option`，**实测** `--opt --method ancopt` → `-1- ... Unknown option '--method' provided`、exit 0） | 不会撞既有测试；新测试见 §4.7.1 |
| **R24（M-3）：`--opt` 只跑一次** | `xtb/landscape-opt-alias`（新增） | 新增断言；今天无测试覆盖改派后的 `--opt`（`--opt ` 仅 R2 那 1 命中） |
| **R23（M-2）：`$opt` 守卫扩到全部套件 run type** | 无 | 实测：`grep -rn '\$opt' test/unit/` = **0 命中**（CLI fixture 用的是 `$scan`/`$scc`/`$fix`）⇒ 0 条既有测试会变红 |
| **R22（H-2）：谓词改为单一标志** | 无（纯设计内部） | §14.7 的反例测试（`native_engine == p_engine_rf` 退化）覆盖 |

**实施前的强制动作**（复核已代跑 + **本轮复测**，结果写入本节）：
`grep -rn "2>&1" test/unit/` = **0 命中**；`grep -rn '\-\-opt ' test/unit/` = **1 命中** = `landscape_cli_check.py:495`（即 R2）；
`grep -rnE '\-\-l(opt|scan|ts|lirc).*--l(opt|scan|ts|lirc)' test/unit/` = **0 命中**。
**R15 新增一条**：`grep -rn 'landscape-scan-atom-range\|landscape-scan-nstep-missing\|landscape-scan-xcontrol' test/unit/CMakeLists.txt`（已知，见上）。
**R23 新增一条**：`grep -rn '\$opt' test/unit/` = **0 命中**（M-2/C7 的爆炸半径）。
**R21 新增一条**：`grep -rn "'--method'" src/` = 0 命中（该旗标确实尚未存在，H-1 的机制是新代码）。

---

## 10. 破坏性变更清单（方案 C，逐条；**R19 修订，R23 补 C7**）

> **形式**：条目 / 现象 / 影响谁 / 缓解措施 / 是否可避免。
> **R19 汇总**：**A 类 3 条 + B 类 0 条（清零）+ C 类 6 条 + D 类 1 条（已定：映射）+ E 类 1 条 + F 类 3 条 + G 类 1 条**。
> **R23 补丁**：新增 **C7**（套件 run type + xcontrol `$opt` 块），C 类 6 → **7**，总计数 15 → **16**。
> 用户四项决策已闭合 H1/H2/H4/H5/M1：**三类原生专属情形从"静默丢失"变为"响亮拒绝"**（H 类），B 类因 R4 清零。

### A 类 — `--opt` 改派的直接后果

**A1. 引擎与数值结果改变**
- 现象：`--opt` 由 `src/optimizer.f90` 的 ANCopt（`p_run_opt`=4）改为套件（`p_run_lopt`=9）。
  轨迹、步数、末几何、能量都变。[实测] H2O：原生 ANCopt 4 次迭代收敛；套件 lbfgs 5–6 次能量评估。
- 影响谁：任何靠 `--opt` 做生产几何优化、且对末几何/步数/轨迹有期望的脚本。
- 缓解：`--method ancopt`/`lancopt`/`fire` 出口（§4.8）；`[NOTICE]` 提示。
- 可避免：❌（这是 C 的核心）。
- **R5 更新**：旧稿的"未做逐位对比"（U4）**现在可测**：`--opt` 与 `--lopt` 同在一个二进制，5 分钟可完成
  （复核对 LOW-7 的要求）。本修订把 U4 从"未确定"降级为"实施前 5 分钟小任务"（§12）。

**A2. 收敛档位的数值阈值改变（**R5 改写**）**
- 现象：`--opt normal` 的判据变了。原生 normal：ΔE ≤ 5e-6 **且** 梯度范数 ≤ 1e-3。
  套件 normal：`e_tol`=5e-6 **且** `g_max`≤3e-4、`g_rms`≤1e-4、`d_max`≤4e-3、`d_rms`≤2e-3 ——
  套件是**四判据**，梯径更紧。
- **旧稿的"`e_tol` 恒定（5e-6）"作废**：R5 把 `e_tol` 变为档位相关（superloose 5e-4 … vtight 1e-7）。
- 影响谁：用 `--opt <level>` 控制成本的脚本。
- 缓解：`--opt <上上游档位>` 映射表 + 偏差 `[NOTICE]`；`--acc`/`--cycles` 可显式钉住（§3.5 优先级）。
- 可避免：⚠️ 可部分缓解（映射表 + 提示），**不能完全避免**（判据数目与定义不同）。
- **补充**：`--opt extreme` → 套件 `vtight` **上限截断**（套件无更紧档）。

**A3. 旗标面：`-o` 与全部档位一并改派（**R12**）**
- 现象：`case('-o','--opt')`（`main.F90:2153`）使 `-o` 与 `--opt` **同义** ⇒ 短别名一并改派；
  `lax`/`sloppy`/`loose`/`tight`/`verytight`/`vtight`/数字档 `-3..3` 全部接受并重新映射。
- 影响谁：用 `xtb -o ...` 的脚本（旧稿 §5.1/§10 **完全未列**）。
- 缓解：`[NOTICE]` + `--method ancopt`；`--help` 明确 `-o` 改派。
- 可避免：❌（与 `--opt` 同根）。

### B 类 — 文件契约改变（**R4：清零，0 条**）

> **旧稿 B1–B5 作废**：用户决策 2 定为**套件按上游语义写全 4 个遗留文件**（§3.9），
> 因此"缺 `.xtboptok` / `xtbopt.log` / `xtblast.xyz` / `compliance.dat`"不再成立。
> **唯一残留**：新增的 `xtb.trj`/`vib_normal_modes` 是**新增而非删除** ⇒ 不构成破坏（BC-3 已改为"集合不小"）。
> **B 类清零，BC-3 无条件成立。**

### C 类 — 新增的**响亮错误**（本来静默，现在会失败；R6 决策 4）

> **全部四条（C1–C4）已由用户决策 4 接受**；逐条的检测点/文本/退出码/测试见 §8.7。

**C1. `--lopt --lscan`** —— 静默首选项获胜 → error（消息点名 `--lscan`）。
**C2. `--opt --lopt` / `--opt --hess`** —— 跨原生/套件双 runtyp → error（影响面最大，`--opt` 最常用）。
**C3. `--lts --lopt-engine bfgs`** —— 子选项与任务不匹配 → error（点名 `--lts-method bfgs`）。
**C4. `--hess --lvib-temp 400`** —— 同 C3 → error（点名 `--lvib` 或 `--etemp`）。
**C5（R13）. “任一原生 runtype + 套件子选项”整类** —— 122 个套件拼写 × 任一先行 runtype 旗标，全部从静默丢弃→ error。
**C6（R13）. 未改派 runtype + `--method`** —— `--metaopt/--bhess/--path/--modef/--screen/--md/--hess/--siman/--mdopt/--metadyn/--nat/--bias-input` → error（§4.6）。

**C7（R23，第 2 轮复核 M-2）. 套件 run type + xcontrol `$opt` 块** ——
`--lopt`/`--lscan`/`--lts`/`--lirc`/`--lvib` 与 `--opt`/`--ohess`(套件) + `--input <含 `$opt` 的 xcontrol>`：
今天**静默 ignore、exit 0**（§3.8c 的实测：`--lopt --input <$opt optlevel=tight>` → exit 0，`warning|ignore|opt block` 计数 = 0），
改后 `env%error`（exit 1）。

- 现象：用户以为 `$opt` 键在给套件调参，实际套件对 `set%optset` **零引用**（`grep -rn optset src/landscape/` = 1 命中且是注释）⇒ 今天就是"死旋钮 + 静默"。
- 影响谁：用 xcontrol 配 `--lopt` 等套件运行的脚本。**它们的设置今天本就未生效**，所以这是"把静默变响亮"，不是数值改变。
- 缓解：错误文本指向 `--method ancopt`（原生 ANCopt 真的尊重 `$opt`；实测 `optlevel=tight` → `energy convergence 0.1e-05`，且与 `crude` 的末能量不同）。
- 爆炸半径（实测）：`grep -rn '\$opt' test/unit/` = **0 命中** ⇒ **0 条既有测试会变红**。
- 可避免：⚠️ 技术可以（"只守卫 `--opt`"），但**工程上不接受**：那会**故意保留**一条已被确认的静默路径，与 §1.1 目标 4（"绝不静默"）
  以及本项目已抓到的 4 次"同一类缺陷"（`--lirc-level` 死旋钮、`$thermo` 覆盖、两次输出命名）直接冲突。
  ⇒ **选择：全量作用域 + 入册 C7 + 计数 +1**。

**可避免**：⚠️ 这是"绝不静默"与百分百兼容的直接冲突；用户决策 4 已选择"响亮"。

### D 类 — `--cycles`（**R5 已定：映射，不再是无解静默**）

**D1. `--cycles INT` 映射到套件 `max_steps`**（§3.10b）
- 现象：旧稿担心 `--opt --cycles 50` 在套件下静默失效。**R5 改为映射**：`--lopt/--lscan/--lts/--lirc` 与
  `--opt`(套件) 均映射；`--lvib` 无对应概念 ⇒ **响亮报错**（exit 1）。
- 影响谁：`--opt --cycles N` 的脚本（行为变：预算= N 而非原生 maxcycle）。
- 可避免：✅（映射已消除静默）。

### E 类 — **R5：档位同时驱动 `e_tol`/`acc`/`max_steps`（新）**

**E1. `--lopt-level <level>` 的语义扩大**
- 现象：`--lopt-level loose` 从（`e_tol`=5e-6, `acc`=1.0, `max_steps`=256）变为（5e-5, 2.0, clamp(2n,200,10000)）；
  **默认 `normal`** 的 `max_steps` 也从 256 变为 clamp(3n,200,10000)（H2O → 200）。
- 影响谁：所有用 `--lopt-level`/`--lscan-level`/`--lts-level`/`--lirc-level` 或默认档的脚本与测试。
- 缓解：`--acc` 与 `--cycles`/`--l*-max-steps` 显式时**优先**（可逐字钉住旧行为）；
  建议 3a/3b 分两步实施（§3.10）。
- 可避免：❌（用户决策 3 的核心）；但影响面**已列表化**（§3.10）。
- **再基线要求**：§3.10 的全部既有测试与 M2/M3/M4/M6/M7 已验收数字需重测并**逐条更新 golden 值**（报告贴前后对比）。

### F 类 — **R12：未入册的行为变更（旧稿 §10 计数偏低）**

| # | 调用 | 现状 | 新 | 影响 |
|---|---|---|---|---|
| F1 | `-o <level>` | 原生 ANCopt | 套件 | 同 A3 |
| F2 | `--strict --zzzz` | exit 0 | **非零** | 所有依赖"容错 exit 0"的脚本（§8.5） |
| F3 | `--opt banana` | 静默→normal | **error** | 依赖容错的脚本（§8.5） |

### G 类 — 阶段 3 的**测试层后果**（R2 新增；已知且必须同步修复）

**G1. `xtb/landscape-scan-xcontrol` 会变红**
- 现象：`test/unit/landscape_cli_check.py::check_scanblock` 的 **492-503 段**断言原生 `--opt` **执行** `$scan`
  （`:498-499` status==0；`:500-501` 输出含 `RELAXED SCAN`；`:502-503` `xtbscan.log` 存在；`:492` 注释 `# the ANCopt path still executes the block`）。
  R1 让 `--opt` + `$scan` 响亮报错 ⇒ 这三条断言失败。
- 缓解/处置（必须）：阶段 3 把该段改为"断言响亮报错 + 文本含 `--method ancopt`/`--lscan`"，**保留 466-491 段**。
- 可避免：❌（改派的必然后果，但**必须入册**，不能静默改测试）。

**汇总：A 3 + B 0 + C 7 + D 1 + E 1 + F 3 + G 1 = 16 条**（R23 后；其中 B 类已清零；A/C/D/E/F/G 需用户逐条确认）。

> **R29/R35：计数不变（仍 16）**。第 3 轮复核 HIGH-1（`--ohess` 跑两遍）与本轮的两个新增读者
> （`xtbopt.xyz` 二次写、计时标签）都是**改派内部的重复工作/错标**，修掉后对**用户可见的契约**而言：
> 文件集合不变、stdout 行不变（`fres` 桥正是为了**不**少两行，见 §3.11.1 的实测）；
> 唯一新增行为是套件 `--ohess --json` 与 `set%property_file` 里出现了热化学键（与原生 `--ohess` **同形**，属 BC-3 的"新增"）。
> 若用户采纳 §16.8 的 **U17**（套件运行 + `--o1nh` 从死旋钮改响亮报错），计数才变 **17**（候选 C8，**未定**）。

---

## 11. 不建议做的改动（及理由）

| # | 不建议 | 理由 |
|---|---|---|
| 1 | **删除** `--lopt-engine`/`--lscan-method`/`--lts-method`/`--lirc-method` | 无歧义、广泛使用；删除是纯破坏，收益为 0（别名零成本） |
| 2 | **重命名** `--lscan-step` 以标注单位（如 `--lscan-step-ang`） | 破坏面大（21 个 `--lscan*` 里最常用之一），收益（单位提示）可用 help + 回显达到 |
| 3 | 把 `--opt` 的**所有** level 都强行映射成套件 5 档而**不告知截断** | `crude`/`sloppy`/`lax`/`extreme` 会静默改变含义 → 违反"绝不静默" |
| 4 | 复刻上游的"未知枚举值静默回退"（`--opt banana` → normal） | 与项目原则冲突；我们应 error |
| 5 | 让 `--method` **隐式设定 runtyp** | 与上游"只选一个 runtyp"规则打架，掩盖笔误（§4.4） |
| 6 | 新增 `--lsp`（套件单点 CLI） | 原生 `--sp` 已覆盖；W1 §3 G1 明确"只在 API 用"。增加 CLI 面而无新能力 |
| 7 | 把 `--bhess`/`--metaopt`/`--path`/`--modef`/`--screen` 也改派 | 套件**无等价实现** → 功能消失（用户已决定保持原生） |
| 8 | 引入 `--set`/`$set` 风格的自定义键值输入 | 上游 `$set` 已弃用（`man/xcontrol.7.adoc:619`），我们不做 |
| 9 | 把 `--lX-hessian` 改名以避开上游 `$opt hessian=` | 上游那个是 xcontrol 键不是 CLI 旗标，冲突面小；改名是破坏 |
| 10 | 现在再讨论 `e_tol` 是否随档位变化 | **已由用户决策 3 定案（R5）**：随档位变化（§3.5）；本项由"不建议"改为"已实施" |
| 11 | 在阶段 3 之前就给 `--opt` 加 `[DEPRECATED]` 警告 | C 是立即切换，不是两阶段；`--method ancopt` 已足够 |
| 12 | 用环境变量（如 `XTB_ENGINE=native`）做逃生舱 | **建议不引入新机制**：`--method ancopt` 已足够显眼且可测试；环境变量会引入"不可见状态"（§12 列为待确认） |

---

## 12. 未确定 / 未验证清单

| # | 项 | 状态 / 依据 |
|---|---|---|
| U1 | `--opt` 与 `--lopt` 是否合并 runtyp | **已定（R16/M8，§3.11）：不合并** —— 保留 `p_run_opt`/`p_run_ohess`，套件/原生的区分由**单一** `landscape_native_engine`（0 = 套件）承担；**R32 订正**：旧稿在这里写"两个逻辑标志"，那是 §3.11 已声明的**作废**写法（`landscape_native_ancopt`/`landscape_opt_alias`） |
| U2 | `e_tol` 是否随档位变化 | **已定（R5/决策 3）：是**（§3.5） |
| U3 | 逃生舱 | **已定**：`--method ancopt`/`lancopt`/`fire`（§4.8）；**不**引入环境变量（§11 #12） |
| U4 | ANCopt vs 套件 lbfgs 末几何 RMSD / 能量差 | **降级为"实施前 5 分钟小任务"**（复核对 LOW-7 的要求）：`--opt --method ancopt` 与 `--lopt` 同在一个二进制；列为阶段 3 的前置测量 |
| U5 | `[NOTICE]` 会不会打破既有 CLI 测试 | **已定（R11）**：走 **stdout**；`2>&1` = 0 命中；CMake 同名 `ERROR_VARIABLE` 合并但断言是子串式（§3.4） |
| U6 | `--cycles` 映射还是报错 | **已定（R5/决策 3）**：映射（`--lvib` 例外报错），§3.10b |
| U7 | 套件是否补写 4 个遗留文件 | **已定（R4/决策 2）：全写**（§3.9），B 类清零 |
| U8 | 未知旗标只 warning → error | **部分已定（R12/F 类）**：`--strict --zzzz`（F2）、`--opt banana`（F3）改为 error，已**入册待用户逐条确认**；其余原生未知旗标保持 warning |
| U9 | `persistentEnv`/解析局部 `env`/`env` 是否同一对象 | **仍未验证**（外部依赖 mctc-lib 未读源码）；但与 R1/R6 的守卫无关（守卫只用 `env%error`，不依赖三者同一性） |
| U10 | `lax` 是否保留为独立档 | **已定（R5）**：不新增套件档；映射到 `loose` 并在 `[NOTICE]` 里说明"比上游 lax 更松"（§3.5） |
| U11 | 大分子（>60 原子）lbfgs vs bfgs 排序 | 未测；**不影响本修订**（不改默认引擎） |
| **U12（新）** | `e_tol`/`acc`/`max_steps` 三个轴的具体取值是否与上游**逐位**一致 | `[代码]` 已照搬 `optimizer.f90:59-113`；但套件阈值（g_max 等）与上游不同尺度 ⇒ **同名档位数值不同是设计选择**，已列 §3.10 |
| **U13（新）** | xcontrol `$opt` 块的"是否出现"检测标志具体放哪 | **已定（R28）**：`set%optset%xcontrol_supplied`（类型 `ancopt_setvar`，`setparam.f90:262-270` 加一字段，默认 `.false.`）；**置位在 `rdcontrol` 的 `case('opt')` 分派处（`set_module.f90:797` 前一行）与 `subroutine set_legacy` 的五个 opt 键（`:2845,2856-2860`）**，不在 `set_opt` 内部（否则 CLI 的 `--opt/--ohess/--cycles` 也会置位）；**不进 `write_set_opt`** |
| **U14** | `check_scanblock` 改写后的具体断言文本 | 阶段 3 与 R1 的 `$scan` 守卫**同一次改动**；具体文案见 §14.5 |
| **U15（R28 新）** | `--method <native>` 与 xcontrol `$opt engine=` **同时出现**时是否要打一行 `[WARNING]`（旧设计：显式 CLI 静默优先，与 `defaults.f90:42` 同类的 first-wins） | **已定（R34，采纳复核 INFO-1 的建议）⇒ (b) 打 `[WARNING]`**。实现点：`set_module.f90:1884-1886` 的 `if (.not.allocated(set%opt_engine))` 守卫的**反例分支**（`allocated` 已为真时）报一行 `[WARNING] engine '<val>' ignored, --method already selected the engine`。**为何安全**：`set%opt_engine` 在 `rdcontrol`（`main.F90:333`）之前只可能被解析尾段（`--method <native>`）置位，而 `defaults.f90:42-46` 的默认在 `initDefaults`（`main.F90:677`，**之后**），所以该 warning **只对"显式 CLI + `$opt` 冲突"这一新组合**触发，任何既有运行都不会多一行输出（BC-4 不变）。测试：`xtb/landscape-method-native-vs-xcontrol`（`--opt --method fire --input <$opt engine=rf>` ⇒ exit 0 + `[WARNING]` + `initial time step`） |
| **U16（R28 新）** | `pbc_lbfgs` 在**非周期**体系上的 `relax_pbc` 物理意义（未评估 `set%optcell` 交互；只测了 "exit 0 + `current lattice:`"，§13c #8） | **已定（R34）：允许，不加警告、行为与原生逐字相同**。理由 4 条：(1) §4.8 的契约就是"四个名字 = 今天的原生行为"，加一行 warning 就破了它；(2) 同一个键今天经 `$opt engine=pbc_lbfgs` 可达且**无**任何提示，
若 `--method` 有提示而 `$opt` 没有，就出现"同一语义两拼写不同行为"（§4.3 明令禁止）；(3) `npbc==0` 时格子自由度为零，`relax_pbc` 退化为普通 L-BFGS——行为**不多余也不算错**（实测 exit 0、6× `current lattice:`）；
(4) 警告必须入册为**原生路径上的新输出**（BC-4），成本大于收益。⇒ 只把"非周期上冗余"写进 `--help`/`man`（文档级缓减），不改代码、不改计数。若用户后续要求提示，实现点 = §3.8(b) 守卫族同一块（`main.F90:491-510`），条件 `mol%npbc == 0 .and. set%opt_engine == p_engine_pbc_lbfgs` |
| **U17（R29 新，待用户裁定）** | 套件运行 + 原生 Hessian 子选项 `--o1nh`（`set%o1numhess`，`main.F90:2181`）：套件 `vib` 任务只拒绝**套件侧**的 `settings%engine%odlr`（`vib/numhess.f90:111-116`），而 `--o1nh` 只写 `set%o1numhess`，**两者今天不同源** ⇒ `--ohess`(套件) 下 `--o1nh` 是**死旋钮 + 静默**（HEAD 上 `--lopt --o1nh` 已经是这种状态，非本设计引入） | **未定**：候选 C8（套件 run + `--o1nh` ⇒ `env%error` 指向 `--method ancopt`，计数 16→17），或把 `set%o1numhess` 转发到 `l*set%engine%odlr` 让套件自己的拒绝文本生效（改动更小、与已有错误文本一致）。两者都属 R13 的"原生子选项 + 非原生路径"规则族，**不阻塞**阶段 1-3（留待与本轮四分项一起裁定） |
| **U18（R29 新，已定）** | `--lvib`/`--lopt` 是否也用 `fres` 桥（让它们的最后能量块也打 `TOTAL ENTHALPY`/`TOTAL FREE ENERGY`） | **已定：不用**。它们**今天就**在**自己的**汇总里打 H(T)/G(T)（M7 的 `--lvib` 输出实测含 `landscape task terminated: frequency analysis completed` 与 `total enthalpy H(T)` 行），加桥会变成两处重复且改动已验收的 M3/M7 输出契约 |

---

## 13. 本轮证据与自检

**本文件是本次唯一改动**。验证：

```
$ git status --short          # 只有未跟踪的新报告与 w1/w2-workflow.js；src/ test/ 无改动
?? docs/_simplify-recon/08-four-way-capability-boundary.md
?? docs/_simplify-recon/09-w1-review.md
?? docs/_simplify-recon/10-w1-report-corrections.md
?? docs/_simplify-recon/11-cli-redesign.md
?? w1-workflow.js
?? w2-workflow.js
```

**复现命令（全部 `OMP_NUM_THREADS=1`）**：

```bash
# 文件契约基线（§3.2/§5.4）
/tmp/xtb-w2/build/xtb h2o.xyz --gfn2 --norestart --opt normal   # xtbopt.log .xtboptok xtbopt.xyz
/tmp/xtb-w2/build/xtb h2o.xyz --gfn2 --norestart --lopt         # xtbopt.xyz xtb.trj
/tmp/xtb-w2/build/xtb h2o.xyz --gfn2 --norestart --hess         # compliance.dat hessian vibspectrum g98.out
/tmp/xtb-w2/build/xtb h2o.xyz --gfn2 --norestart --lvib         # hessian vibspectrum vib_normal_modes g98.out
/tmp/xtb-w2/build/xtb h2o.xyz --gfn2 --norestart --ohess normal # 二者之和

# 冲突静默（§2.6b）
/tmp/xtb-w2/build/xtb h2o.xyz --gfn2 --norestart --opt normal --lopt-engine bfgs   # ANCopt，无提示

# 引擎代价（§3.3）
for m in sd cg lbfgs bfgs diis rfo; do
  /tmp/xtb-w2/build/xtb ch3oh.xyz --gfn2 --norestart --lopt --lopt-engine $m --ljson
  python3 -c "import json;print(json.load(open('landscape_opt.json'))['counters'])"
done

# 上游文档（§2）
curl -sSL https://xtb-docs.readthedocs.io/en/latest/optimization.html | ...
```

**证伪的前提（本轮如果发现任何一条，以本报告为准）**：
1. 「套件缺 `.xtboptok`/`xtbopt.log`」→ **成立**（但 W1 写的 `.xtbopt.log` 应更正为 `xtbopt.log`）。
2. 「套件 `--lvib` 也写 `xtbhess.xyz`」→ **成立**（[实测] 有虚频时），**不是差异**。
3. 「`--strict` 会把未知参数变成错误」→ **不成立**（[实测] exit 0）。
4. 「未知旗标只 warning」→ **成立**（`main.F90:1583`）。
5. 「套件的枚举名大小写不敏感」→ **不成立**（`BFGS` 报错）。

### 13b 本轮（R1）的证伪与留痕

6. 「复核说 `--opt` 改派会打破 `xtb/landscape-scan-xcontrol`」→ **成立**（复核正确）。
   **父会话此前"该测试不会因此失败"的核实被证伪并撤回** —— 它只读了 `check_scanblock` 的 docstring（描述前半段），
   未读函数体 **492-503** 段（`[读代码]`）：`:493-497` 跑 `--opt --input <xcontrol>`、`:498-499` 要求 status==0、
   `:500-501` 要求输出含 `RELAXED SCAN`、`:502-503` 要求 `xtbscan.log` 存在；`:492` 注释原文
   `# the ANCopt path still executes the block`。该函数经 `landscape_cli_check.py:20` 的 `scanblock` 分派
   注册为 `test/unit/CMakeLists.txt:3082-3088` 的 `xtb/landscape-scan-xcontrol`。⇒ 本修订**保留**这条撤回记录（R2）。
7. W1 写的 `.xtbopt.log` → **不成立**（该名字不存在）；轨迹文件是 **`xtbopt.log`**（无前导点，`geoopt_driver.f90:120-121`），
   `.xtboptok` 才有前导点（`:186`）。本修订已在 §3.2/§3.9 写对。

### 13c 本轮（R21..R28）的实测与对复核结论的核实

> 环境：`/tmp/xtb-w2/build/xtb`（HEAD 语系的 `-O2` 构建），`OMP_NUM_THREADS=1`，非周期水 fixture
> （与 `test/unit/CMakeLists.txt:162-164` 同一几何），工作目录 `/tmp/cli-verify-11`。**未碰 `/tmp/xtb-w0/build`，未跑全量 ctest。**

8. **四个原生引擎今天都可达，且各有唯一 stdout token**（经 `$opt engine=`，即 `--method <name>` 将替换的机制）：

   | 命令（`--opt --input <$opt engine=X>`） | exit | `ANC micro-cycles` | `L-ANC optimizer` | `initial time step` | `current lattice:` | `landscape:` |
   |---|---|---|---|---|---|---|
   | `engine=rf` | 0 | **1** | 0 | 0 | 0 | 0 |
   | `engine=lbfgs` | 0 | 0 | **1** | 0 | 0 | 0 |
   | `engine=fire` | 0 | 0 | 0 | **1** | 0 | 0 |
   | `engine=pbc_lbfgs` | 0 | 0 | 0 | 0 | **6** | 0 |

   ⇒ (a) H-1 的"四个出口可实现"**有实测基础**；(b) 四个 token 互斥，可直接做 §4.7.1 的断言；
   (c) `pbc_lbfgs` **在非周期水上也 exit 0** ⇒ §4.8 把它当"真正的出口"而非"仅报错"是站得住的。
9. **"只跑一次"的判别 token（M-3）**：`--opt --ljson` → exit 0，`ANC micro-cycles` = 1、`landscape:` = 0，
   **无 `landscape_opt.json`**；`--lopt --ljson` → `landscape: lbfgs minimisation` = 1、`ANC micro-cycles` = 0，
   写 `landscape_opt.json` + `xtb.trj`。⇒ §4.7.1 的 `xtb/landscape-opt-alias-once` 的断言可直接用这两个 token 与 json 的存在性。
10. **`--method` 今天不存在**：`--opt --method ancopt` 与 `--lopt --method ancopt` 均 exit 0 + `-1- prog_main_parseArguments: Unknown option '--method' provided`；
   `grep -rn "'--method'" src/` = **0 命中** ⇒ H-1 的机制是新代码，不会撞既有测试。
11. **M-2/C7 的爆炸半径**：`--lopt --input <$opt optlevel=tight>` 今天 → exit 0，
   `grep -ci 'warning\|ignore\|opt block'` = **0**（完全静默）；`grep -rn '\$opt' test/unit/` = **0 命中**。
12. **H4 基线（守卫的必要性）**：`--opt --input <$opt optlevel=tight>` → exit 0 + `ANC micro-cycles` = 1 +
   `energy convergence 0.1000000E-05`；改为 `optlevel=crude` ⇒ 末能量 `-5.070383095219 Eh`（vs tight 的 `-5.070544427069 Eh`）⇒
   **`$opt` 键今天真的生效**，所以"套件下静默忽略"是真实功能损失。

---

## 14. 【R20 新增】复核 12 处置表

> **编号口径**：复核 12 声明 HIGH 5 / MEDIUM 8 / LOW 7 / INFO 4，但正文只显式编号了
> H1/H2/H3/H5、M1/M2/M4/M5/M6/M7/M8、LOW-1..LOW-7、2 条 INFO。
> **本表按内容补足到与计数一致**，"复核标签"列标明哪些是"正文未编号（本修订按内容补 ID）"。
> 每一项的处置 ∈ {**已改**（给章节/file:line） / **接受**（说明理由） / **不适用**（说明理由）}。
>
> **编号重建规则（I-2，R28）**：当复核声明的计数与它正文里显式编号的条数不一致时，
> 本表按**内容**补 ID（标"正文未编号"），**不新增/不丢弃任何一条**，也不改复核给的编号；
> 下一轮复核请用**同一条规则**对账（先数内容，再对编号），否则计数会再次不可对。
> 第 2 轮复核的结果逐条处置见 **§14.7**。

### 14.1 HIGH（5）

| ID | 复核标签 | 内容（复核原文要点） | 处置 | 依据 / 改动位置 |
|---|---|---|---|---|
| H1 | H1 | `$scan`/G13：`--opt` 改派丢掉 xcontrol `$scan` 执行能力；`main.F90:505-508` 错误消息自指；**已注册测试变红** | **已改**：响亮报错 + 测试同步改写 | §3.8(a)、§5.5、§9.1 阶段 3、§10 G1、§14.5 |
| H2 | H2 | 周期体系 `--opt`（G9/G10）从"能跑"变"中止" | **已改**：响亮报错 + 指向 `--method ancopt` | §3.8(b)、§5.5 |
| H3 | H3 | `--method` 解析时序按字面**无法实现**（`--method bfgs --lopt` 必然误报） | **已改**：解析后归一（三步机制） | §4.6（改写）、§4.7（新增） |
| H4 | **正文未编号（本修订按内容补 ID）** | xcontrol `$opt` 键（engine/optlevel/hessian/maxcycle/microcycle/hlow/maxdispl…）在套件下**静默失效**（套件对 `set%optset` 零引用） | **已改**：响亮报错（作用域=所有走套件的 run type）；**R23：已入册为破坏性变更 C7** | §3.8(c)、§10 C7、§14.7 |
| H5 | H5 | G12：FIRE/inertial（L-ANCopt/FIRE）、动态 SCC 精度、模型 Hessian 变体（Swart/GFNFF）、`average_conv` 失去 CLI 可达路径 | **部分已改 / 部分接受**：
FIRE/L-ANCopt → `--method fire`/`lancopt`（已改，§4.1/§4.8）；
`$opt hessian=swart/gfnff` 与 `average_conv` 属 `$opt` 键 ⇒ 由 §3.8(c) 响亮报错（已改）；
"动态 SCC 精度"（`optimizer.f90:832-838`）是原生 ANCopt 的**内部**算法行为，不是 CLI 面 ⇒ **不适用**（无 CLI 旋钮可丢） | §4.1、§4.8、§3.8(c) |

### 14.2 MEDIUM（8）

| ID | 复核标签 | 内容 | 处置 | 改动位置 |
|---|---|---|---|---|
| M1 | M1 | 档位携带 SCF 精度 `acc` / `maxcycle`，套件不对齐 | **已改**（决策 3） | §3.5（改写）、§3.10 |
| M2 | M2 | BC-3 的"满足"表述与 §10 矛盾；`[NOTICE]` 走 stderr 而 BC-5/§9.2 要求 grep stdout | **已改**：BC-3 改为"集合不小"且 B 类清零；`[NOTICE]` 改走 stdout | §1.2、§3.4（改写） |
| M3 | **正文未编号（按内容补 ID）** | 1 条"现状事实"已过期：`$thermo` 早已修好 | **已改** | §8.3 D5、§8.6（R18） |
| M4 | M4 | 未入册的行为变更：`-o` 随 `--opt` 改派；`--strict --zzzz` 与 `--opt banana` 变严格 | **已改**（登记为 F 类 + A3 + §5.5） | §10 A3/F 类、§5.5 |
| M5 | M5 | "原生 runtype + 套件子选项"整类未覆盖 | **已改**：通用规则 + 消息模板 | §8.7 C5、§4.6（R13） |
| M6 | M6 | §9.2 强制表格漏 §6.3 全部新旗标与 7 个别名 | **已改**：表格补全到 22 行 | §9.2 |
| M7 | M7 | §9.4 漏 `scan-atom-range`、`scan-nstep-missing`、`scan-xcontrol` | **已改** | §9.4（R15） |
| M8 | M8 | "runtyp 机制定义"：`--opt`/`--ohess` 与套件任务的身份关系未定义 | **已改**：不合并 runtyp + **单一 `landscape_native_engine`（0 = 套件）** + 谓词（**R32 订正**：旧稿这里写"两个逻辑标志"，那是 §3.11 已声明的作废写法） | §3.11（新增） |

### 14.3 LOW（7）+ 复核 §11 勘误表（12 行）

| ID | 内容 | 处置 | 改动位置 |
|---|---|---|---|
| LOW-1 | §7.3 换算行号误写 `main.F90:3836-3844` | **已改** → `:3878-3889` | §7.3 |
| LOW-2 | §4.1 最小化器解析行 5/6 偏移 +2 | **已改** → sd 1119 / cg 1121 / lbfgs 1123 / bfgs 1125 / diis 1127 / rfo 1129 | §4.1 |
| LOW-3 | `lax` Gconv 文档 2e-3 vs 源码 2.5e-3（`optimizer.f90:83`） | **已改**：表格改 2.5e-3 + 权威来源改为源码 | §2.3 |
| LOW-4 | help 单位 token 白名单未写死（`help-unit-annotation` 会长期假阳性） | **已改**：白名单写死（`bohr\|angstrom\|Å\|degree\|K\|cm^-1\|amu\|Eh\|hartree`） | §9.2 |
| LOW-5 | `xcontrol.7.adoc:619-621` 误导，弃用句在 `:626` | **已改** | §2.5 |
| LOW-6 | §5.5 未列 `--opt` 的其余 6 档 + 数字档 | **已改** | §5.5 |
| LOW-7 | U4（ANCopt vs lbfgs 末几何）现在 5 分钟可测，不该与 U1/U2/U3 并列 | **已改**：U4 降级为阶段 3 前置测量 | §12 U4、§10 A1 |
| errata | 复核 §11 的 12 行（含 `set_module.f90:1916→1918`、`:1912→1910`、`main.F90:952-957→984-987`、`:3836-3844→3878-3889`、`xhelp.f90:775→780`、`:717→722`、`geoopt_driver.f90:152-176→148-172`、§4.1 解析行、§10 B4 `compliance_driver` 调用者、§10 B2 引文非逐字、§2.5 `:626`、`lax` 映射更松） | **全部应用** | 正文对应各点（均带 `[R17]`/`[R18]` 标记） |

> **注**：复核把"LOW"计为 7，但正文里除 LOW-1..LOW-7 外还有一条未编号的"LOW（单位可见性）"；
> 本修订把它编为 **LOW-4**（上表）。`--lax` 映射更松（复核 §11 row 12）作为 errata 处理。

### 14.4 INFO（4）

| ID | 复核标签 | 内容 | 处置 | 改动位置 |
|---|---|---|---|---|
| INFO-1 | INFO（row 131） | `--siman/--mdopt/--metadyn/--nat/--bias-input --method X` 的消息模板缺失 | **已改**：§4.6 补 5 行消息模板 | §4.6 |
| INFO-2 | INFO（row 221） | G14 DMF 零提及（D2 已排除，但未复述） | **已改**：§3.7 补一行复述 D2 排除 | §3.7 |
| INFO-3 | **正文未编号（按内容补 ID）** | G8（vip/vea/vipea/vfukui/vomega）未明说"套件无 property 层 ⇒ 无法经 CLI 暴露" | **已改**：§3.7/§5.1 明说 | §3.7 |
| INFO-4 | **正文未编号（按内容补 ID）** | §2.8 未验证项（ODLR Hessian 细节、`TEnvironment` warning 落盘归属） | **接受（不适用）**：与本次 CLI 设计无关，保留在 §2.8，不阻塞任何阶段 | §2.8 |

### 14.5 阶段 3 的测试更新规格（R2，强制）

**对象**：`test/unit/landscape_cli_check.py::check_scanblock`（`447-503`），注册为 `xtb/landscape-scan-xcontrol`
（`test/unit/CMakeLists.txt:3082-3088`；分派 `landscape_cli_check.py:20`）。

| 段 | 现状（HEAD） | 阶段 3 改成 |
|---|---|---|
| `466-491` | 5 个套件 runtyp（lopt/lscan/lts/lirc/lvib）断言拒绝 `$scan`（含 `does not execute the xcontrol $scan block`、无 `xtbscan.log`） | **保留不动** |
| `492`（注释） | `# the ANCopt path still executes the block` | 改为 `# the redeployed --opt must refuse the block as loudly as the suite run types` |
| `493-497` | `run(exe, inp, ["--gfn","2","--opt","--input",xcontrol,"--norestart"], optdir)` | 保留命令，但期望改为**非零退出** |
| `498-499` | `if status != 0: fail("xtb --opt with a $scan block terminated with status %d")` | 反转为 `if status == 0: fail("...")` |
| `500-501` | `if "RELAXED SCAN" not in output: fail("--opt did not run the $scan block")` | 改为 `if "--method ancopt" not in output: fail("--opt did not point at --method ancopt")` |
| `502-503` | `if not os.path.exists(xtbscan.log): fail("--opt did not write xtbscan.log")` | 改为 `if os.path.exists(xtbscan.log): fail("--opt wrote xtbscan.log although it refused the $scan block")` |
| `451`（docstring；**L-2 订正：旧稿写 452**） | 引 `src/prog/main.F90:914-916`、"`relaxed_scan` runs it only on the `anyopt` path" | 改写为"原生 ANCopt（`--method ancopt`）仍执行；`--opt` 改派后与套件 runtyp 一样拒绝" |

**报告要求**：在阶段 3 交付里贴出**改动前（红）与改动后（绿）**的该测试输出（证明突变语义等价 —— 本项目 M4 报告 34 §1 的教训）。

### 14.6 自指引导清单（R3，阶段 3 必改）

| 位置 | 现文本 | 改派后的问题 | 阶段 3 改写为 |
|---|---|---|---|
| `src/prog/main.F90:505-508` | `"$scan block: use --opt to run it, or --lscan with --lscan-coord/--lscan-atoms ..."` | `--opt` 不再执行 `$scan` ⇒ **自指** | `"use --opt --method ancopt to run it, or --lscan with --lscan-coord/--lscan-atoms for a scan of the landscape suite"` |
| `src/xhelp.f90:285-286`（`--lopt` help） | `"(use --opt for that block, or --lscan with --lscan-coord)"` | 同上 | `"(use --opt --method ancopt for that block, or --lscan with --lscan-coord)"` |
| `src/xhelp.f90:270-271`（`--opt` help） | `"-o, --opt [LEVEL]  call ancopt(3) to perform a geometry optimization..."` | 描述已过时（现在跑套件） | `"-o, --opt [LEVEL]  minimise with the landscape suite (default lbfgs); pass --method ancopt for the legacy ANCopt"` |
| `src/prog/main.F90:481-488`（注释） | "`relaxed_scan` executes it only on the `anyopt` path ... reached by `--opt` and friends" | 注释过时 | 改为"原生 ANCopt 路径（`--method ancopt`）执行；`--opt` 改派后由 §3.8(a) 守卫拒绝" |
| `man/xtb.1.adoc:238-241`（`--opt`） | `"call ancopt(3) to perform a geometry optimization..."` | 同 | 同步为套件默认 + `--method ancopt` 出口 |
| `man/xtb.1.adoc:246-248`（`--ohess`） | `"... on an ancopt(3) optimized geometry"` | 同 | 同步 |
| `test/unit/landscape_cli_check.py:451`（docstring；**L-2 订正：旧稿写 452**） | 引 `main.F90:914-916` 说 `--opt` 执行块 | 会误导实现者 | 见 §14.5 |

> **核实方法（本轮已跑）**：`grep -rn 'use --opt\|--opt to run' src/ man/ docs/`
> 命中**仅** `src/prog/main.F90:506` 与 `src/xhelp.f90:286` 两处（`docs/` 与 `man/` 均为 0 命中，除本设计文件自身）；
> `man/xcontrol.7.adoc:442` 的 `$scan` 段**不**推荐 `--opt`（只文档块语法）。
> ⇒ 自指引导的**全部**位置就是本表这 6 行 + 1 行测试注释。

### 14.7 【R28 新增】第 2 轮复核（`14-w2-review-round2.md`）逐条处置表

> **对象**：复核第 2 轮：CRITICAL 0 / **HIGH 2** / MEDIUM 4 / LOW 6 / INFO 2。
> 本表逐条给处置；凡"已改"均带章节；凡结论与复核不同处均给证据。

| ID | 复核的论证（要点） | 处置 | 改动位置 / 证据 |
|---|---|---|---|
| **H-1** | §4.7 的解析尾归一无法处理 4 个原生出口：`--opt --method ancopt` 要么让 `landscape_opt_algorithm_from_name` 收到 `'ancopt'`（返回 0 ⇒ `env%error`），要么落 `select` 的 `default` ⇒ 两条顺序都死 | **已改（重写 §4.7）**：解析尾**两段**归一——原生名在第 2 段的**第一个分支**就被分流（`landscape_native_engine_from_name`），**不进入**套件 setter；给出**逐行代入证明**表（出口 1-6 不调 `from_name`、不落 `default`；出口 7/10 是设计要求的报错）；表头即 `settings.f90:1112-1135` 的实际取值域 | §4.7（重写）、§4.7.1、§4.8、§3.11；实测支撑 §13c #8 |
| **H-2** | §3.11 谓词只认 `native_ancopt` ⇒ `--opt --method lancopt\|fire` 被判成套件 ⇒ §3.8 三守卫对原生 L-ANCopt/FIRE 误报 | **已改**：单一 `landscape_native_engine`（取值域 = `p_engine_rf/lbfgs/inertial/pbc_lbfgs`，0 = 套件）；三条守卫改成 `landscape_is_suite_run(...)`；**明确禁止**写成 `== p_engine_rf`（H-2 的错法）；三个反例测试进 §4.7.1 | §3.11（重写）、§3.8 前置 + (a)(b)(c)、§4.7.1 |
| **M-1** | §5.4 仍写"3 个缺失 = 破坏"，与 §1.2 BC-3/§10 B 矛盾（只修一半）；且 `13-*.md §2` 声称 §5.4 加"R4 后补齐"——全文 0 命中，属过度声称 | **已改（真改）**：§5.4 表格加"R4 后（§3.9）"列，结论拆成"HEAD 现状 / R4 后"两段，明写"3 个缺失"只描述 HEAD 现状；**并留痕**：在 §5.4 与 `13-*.md §4` 记录"此前的修订记录错称已改，实为未改"及 `grep "R4 后补齐"`= 0 命中 | §5.4、`13-*.md §2/§4` |
| **M-2** | §3.8(c) 把 `$opt` 守卫扩到所有套件 run type（今天 `--lopt --input <$opt>` 静默 exit 0）⇒ 新增破坏性变更而未入册/未计数 | **已改**：登记 **C7**，计数 **15 → 16**；给出"为何不收窄到只守卫 `--opt`"的论证 + 爆炸半径实测（`grep '\$opt' test/unit/` = 0） | §10 C7、§3.6、§0、§3.8(c)、§9.4；实测 §13c #11 |
| **M-3** | M8 只给了身份谓词，未指定抑制既有 `if (anyopt)`（`main.F90:931`）⇒ `--opt` 可能既跑原生又跑套件 | **已改**：`main.F90:931` → `if (anyopt .and. landscape_native_engine /= 0)`；`anyopt` 另两个读点（`:321`/`:326`）**故意保留**（保守报错正确）；`--ohess` 的 opt→vib 链用 `landscape_ohess_chain`；新增两个"只跑一次"测试（判别 token 实测） | §3.11（读点表 #4）+ M-3 段、§4.7.1、§9.2、§9.4；实测 §13c #9 |
| **M-4** | §8.4 的 `--help` 双向测试实测差集 30+4 ⇒ 与阶段 1"新增测试全绿"矛盾 | **已改**：拆成集合 S（套件旗标，阶段 1 门槛，差集必须 = 0）与集合 N（原生，已知清单，阶段 4 收口）；写明抽取规则依赖（30/4 与 34/5 两种口径） | §8.4（重写）、§8.6、§9.1 |
| **L-1** | §5.1 #21 写"`--opt` 走套件 + error/warning"，与 §8.7 "改 error"不一致 | **已改** → 统一为 **error**（C2 族） | §5.1 #21 |
| **L-2** | 6 处行号偏差 | **已改**：`set_module.f90:1890→1891`（`inertial\|fire`；`1890` = `pbc_lbfgs`）、`compliance.f90:283→287`（裸 `open`）与 `:248-300→253-358`（函数范围）、`geoopt_driver.f90:166-168→169-171`、`main.F90:929→931`、`main.F90:477/990→476/989`、`§14.5` 的 `:452→451` | §2.4、§3.8(b)、§3.9、§3.11、§4.1、§14.5；**另**修 `§4.1` 的**文件误归属**（`l_ancopt` = `relaxation_engine.f90:400`、`fire` = `:131`，旧稿写 `optimizer.f90`） |
| **L-3** | §3.9 对 `xtbopt.log`（"XMOL 多帧"）结论正确但缺上游逐帧写点 | **已改** → 补 `optimizer.f90:801`（`writeMolecule(..., number=iter)`） | §3.9 |
| **L-4** | `--lopt-level` 是否也收上游 8 档名口径不清 | **已定**：**不收**（只 5 个套件名，`landscape_conv_level_known` `settings.f90:1497-1510`）；上游名只经 `--opt` 桥接；3 条理由 + 测试 | §3.5（R27 决定）、§6.2 #4、§4.7.1 |
| **L-5** | §3.5 优先级未点出实现处（`main.F90` 无条件同步 `set%acc`） | **已改**：点出 `main.F90:996/1013/1033/1062/1078` 的**无条件** `engine%acc = set%acc`，R5 要求改为"仅显式 `--acc` 时同步"（`acc_was_set`，读点 `main.F90:1665`） | §3.5 第 3 条 |
| **L-6** | §14 未单列复核标为 MEDIUM 的 G15（属性/分析层） | **已改（单列）**：G15 的内容（`vip/vea/vipea/vfukui/vomega` 无套件 property 层 ⇒ 不经 CLI 暴露）已在 §3.7 + §14.4（INFO-3）覆盖；本处单列 ID，避免计数再争 | §14.7（本行）、§3.7、§14.4 |
| **I-1** | §14.6 自指清单完整性 | **接受（已核）**：`grep -rn 'use --opt\|--opt to run' src/ man/` = 2 命中（`main.F90:506`、`xhelp.f90:286`）⇒ 清单完整 | §14.6 |
| **I-2** | 编号重建规则 | **已改**：§14 顶加规则行（先数内容、再对编号；本表新增条不得改复核给的 ID） | §14（顶部） |

> **G15 单列（L-6）**：复核 12 在 `§10` 末行把 G15（vip/vea/vipea/vfukui/vomega 属性层）标为 MEDIUM；
> 设计侧结论不变：**套件没有 property 层**（`src/landscape/` 下 0 个 property/vip 入口），
> 所以这些原生 runtyp 不进入 `--method` 取值域（§4.6 已把它们逐个列为 error），也不产生 CLI 缺口。

---

## 15. 本修订的纪律声明

- **仍未改动 `src/` 与 `test/`**（第 1 轮只改 `11-cli-redesign.md` + 新增 `13-cli-redesign-revision.md`；
  第 2 轮（R21..R28）只就地改这两个文件）。验证：`git diff --stat -- src test` → **空**。
- **所有新增断言均有 `file:line` 或 `[实测]` 依据**；对复核结论的**推翻只发生在 R2 一处**，且**是推翻父会话的订正而非复核结论**
  （复核 H1 的子结论经核实**成立**）。第 2 轮新增的全部"实测"写在 **§13c**（调用方式、工作目录、原始 stdout token 计数均可复现）。
- **本轮不推翻第 2 轮复核的任何一条**（H-1/H-2/M-1..M-4/L-1..L-6/I-1/I-2 均按复核要求处置）；
  只把复核的"修法建议"落成**可实施的伪代码 + 逐行证明**（H-1）与**单一状态位**（H-2）。
- **可核性（针对 M-1 的教训）**：本轮所有"已改"都给了章节 + `file:line`；
  `13-*.md` 里不再保留任何**不可核的声称**（旧稿的"§5.4 加 R4 后补齐"已删并留痕）。
  行号勘误一律用“旧稿写 X → 实际 Y”的形式写出，可直接 `grep` 对账。
- **未新增任何推测性机制**：R21/R22/R24 是复核 H-1/H-2/M-3 的**最小可实现修法**；R23/R26 是复核 M-2/M-1 的登记；
  R25/R27/R28 是复核 M-4/L-4/L-5/L-1/L-2/L-3/L-6/I-2 的处置；R21 的 `rf` 别名取自 `set_module.f90:1888`。

**第 3 轮（R29..R35，针对 `15-w2-review-round3.md`）追加的纪律**：

- 只就地改本文件与 `13-cli-redesign-revision.md`；`git diff --stat -- src test man` 仍**为空**（见 §13、§16.4）。
- **实测口径**：本轮的 token 计数与文件清单均在 `/tmp/w2-h1-probe`（`OMP_NUM_THREADS=1`、
  `XTBPATH=<repo>`、`/tmp/xtb-w2/build/xtb`）上复现，命令与原始输出写在 **§16.4**；
  **未跑全量 ctest、未碰 `/tmp/xtb-w0/build`**。
- **对复核的两处订正都给了证据**（不是反驳结论，而是反驳机制陈述/计数）：
  (1) "半修即**崩**" → 实为**静默 0**（`data.F90:105-129` 的默认初值 + `json.F90:111` 的 `n3true` 守卫；`/tmp/w2-h1-probe/frag.f90` 实测）；
  (2) MEDIUM-2 的 `grep` 计数：复核说 3，**实测 4**（它漏了 `11:2392`）。两条都写进 §16.4/§16.3。
- **本轮不推翻第 3 轮复核的任何一条结论**（H-1 成立、M-3 确实只关了一半、M-2 的自检确实为假）；
  HIGH-1 的\"三触发点逐个给判据\"按字面完成（§3.11.1），M-1/M-3/M-4/LOW/INFO 逐条进 §16。
- **HIGH-1 的唯一设计偏离已声明**：把 `anyhess`（T3）**置假**改为**填 `fres`**（§3.11.1 给了三条实测理由），
  因为前者会静默少两行 stdout（未入册的契约变化）。这是本轮唯一一处"不复刻复核建议"的地方。

---

## 16. 【R29..R35 新增】第 3 轮复核（`15-w2-review-round3.md`）逐条处置

> **复核结论**：**有条件接受**：CRITICAL 0 / HIGH 1 / MEDIUM 4 / LOW 7 / INFO 2。
> 其中 H-1（`--method` 节点与 4 个原生出口）与 H-2 经复核**逐出口代入后判定可实施**；
> 本轮任务的是那个 **HIGH-1** + 4 MEDIUM + 7 LOW + 2 INFO。
> **本节是本轮的权威处置表**；正文对应章节均已就地修订（R29..R35）。

### 16.0 逐条判定

| 复核 ID | 复核结论 | 本轮处置 | 位置 |
|---|---|---|---|
| **HIGH-1** | `--ohess`(套件) 会跑**两遍** Hessian/频率（`numhess`/`main_freq`/`anyhess` 三个触发点按 runtyp 触发）；只抑制 `:931` 不够 | **闭合**：三个触发点 T1/T2/T3 逐个给了**判据 / 改动位置 / 测试**与**逐行代入自证表**；另有 2 处同类读者入抑制集合 | §3.11.1、§3.11 读点表 #10-15、§4.7.1、§9.2 |
| **MEDIUM-1** | `landscape_native_engine` 在无 `--method` 时读到未定义值 | **闭合**：flag 循环前一行无条件 `= 0`（§4.7 第 0 段）+ **全部新状态位初值表**（§3.11.2） | §4.7、§3.11.2 |
| **MEDIUM-2** | `13-*.md §6` 自检是假的（写 0，实测非 0） | **闭合**：自检改为"命令/期望/实际"三列可核形式 + 留痕"此前的 0 是错的"；**并订正复核的 3→4** | §16.4、`13-*.md §6` |
| **MEDIUM-3** | R22 改写留下 2 处指向已作废机制的残留 | **闭合**：3 处（`11:2183`、`11:2322`、`13:18`）改为单一 `landscape_native_engine`；搜索命令与命中数见 §16.5 | §12 U1、§14.2、`13-*.md §1` |
| **MEDIUM-4** | **计数不一致（按 I-2 规则登记）**：复核声明 MEDIUM 4，但 §7 只显式编号了 MEDIUM-1/2/3 三条；按内容补的第 4 条 = 其 §8 表里的「M-4 = 真闭合」（即第 2 轮的 §8.4 拆门槛项） | **不适用（无需动作）**：那是**已闭合**项的复核确认，不是新发现；本轮借 L-4 顺手把读点表补全（#10-15） | §16.6（L-4）、§3.11 读点表 |
| **L-1..L-7** | 7 条可核的文档/行号/计数问题 | 逐条处置见 §16.6 | §4.1/§3.5/§3.7/§3.11/§4.7.1 |
| **INFO-1** | U15（`--method <native>` + `$opt engine=` 是否 warning）接受为诚实开放项 | **(b) 打 `[WARNING]`**，实现点/证据/测试给全 | §12 U15、§16.7 |
| **INFO-2** | 编号重建规则已生效，建议下一轮沿用 | **接受**：本轮沿用（先数内容、再对编号；不改复核的 ID） | §14 顶部 |
| 阶段判定 | 阶段 1/2 可实施；阶段 3 的 `--opt` 可实施、`--ohess` 不可 | 更新为**四态**；`--ohess` 半边**本轮闭合**（前置仅 R30 一行） | §9.1、`13-*.md §4` |
| 需用户确认 3 项 | C7 作用域、`--lopt-level` 不收上游名、**`--ohess` 语义二选一** | 前两项维持设计已选并留待点头；**第 3 项已在本设计中是 (i)**（§3.9/§5.5/§9.1 早已定：套件 opt+vib）⇒ (ii) 不作备选，理由见 §3.11.1 开头 | §3.11.1、§5.5 |

### 16.1 HIGH-1（设计全文 → §3.11.1）

见 §3.11.1。三个触发点的**一句话总结**：

- **T1** `main.F90:1156`（`numhess` 块）：判据换成 `landscape_native_hessian_path`；
- **T2** `main.F90:1282`（`main_freq` 块）：同上；
- **T3** `main.F90:270` 的 `anyhess`：**不动**，改为由套件 vib 链写满 `fres`（桥）。

**自证（复核要求的"两侧同时区分"）**：`landscape_native_engine` 是唯一输入 ——
`--ohess`（无 `--method` ⇒ 0）⇒ T1/T2 均跳、`landscape_ohess_chain` 为真 ⇒ 套件链跑**一次**；
`--ohess --method ancopt`（⇒ 1）⇒ T1/T2 均执行、`landscape_ohess_chain` 为假 ⇒ 与今天逐位同。
完整 6 行（A-F）代入表在 §3.11.1。

### 16.2 MEDIUM-1（设计 → §4.7 第 0 段 / §3.11.2）

- **修复**：`parseArguments` 的 flag 循环（`main.F90:1574`）**之前**无条件 `landscape_native_engine = 0`。
- **为何声明初值不够**：`intent(out)` dummy 在入口即未定义（本文件 §4.7 第 0 段已写明）。
- **"所有新状态位"清单**：8 行，见 §3.11.2（含 `fres`、`lres%vib`、`landscape_vib_result%energy`、
  `set%optset%xcontrol_supplied`、`acc_was_set`）。
- **诚实的测试局限**：未定义值在 `-O2` 下经常恰为 0，所以这条只能**静态可核**（`grep`），运行时烟难作补充。

### 16.3 MEDIUM-2（自检作可核化）

复核：“`13-*.md §6` 的自检是**假的**”。**成立**，且比复核说的更差一点：

| 处 | 旧文本 | 问题 | 现在 |
|---|---|---|---|
| `13:109` | `grep -c "R4 后补齐" …  # 0` | 那个 `#0` 是**写上去的期望**，不是实跑输出 | 改为"命令 / 期望 / 实际"三行，见 `13-*.md §6` |
| `13:110` | `wc -l 11-*.md  # 2423` | 写死行数 | 改为"实跑 wc -l"并注明行数会随修订变 |
| `11:2392` | `grep = 0 命中` 的表述 | 复核说 3 命中，**实测 4**（它漏了这一行） | 已在 R26 行加订正括注；计数见 §16.4 |

> **教训（与 M1 同类）**：一个 0/1 数字如果不在同一轮里跑出来就是声称，不是证据。
> 所以本轮的自检全部写成"命令 + 期望 + 实际"三列（§16.4），并且**在每个数字后面注明它是在哪一轮测的**。

### 16.4 本轮可核自检（命令 / 期望 / 实际）

> 环境：仓库根 `/home/owenchan/work_path/coding/fortran/xtb`（HEAD `bdd8eb8`）；
> 探针目录 `/tmp/w2-h1-probe`（`OMP_NUM_THREADS=1`、`XTBPATH=<repo>`、二进制 `/tmp/xtb-w2/build/xtb`）。
> **实际值**列是 R29..R35 改完之后跑出来的（= 本轮交付状态）；期望值列写的是**判据**。
> **计数类自检都改成"未标记命中 = 0"**：模式只写字符串**前缀**，并要求每一行提及处都在
> 留痕/订正/复核/纪律/自检句里（自检行自己属于最后一类）—— 否则每次修订都会把计数自己抬高（这正是旧版 `# 0` 失效的原因）。

| # | 命令 | 期望（判据） | 实际（本轮末） |
|---|---|---|---|
| 1 | `git diff --stat -- src test man` | 空 | 空（只改 `docs/_simplify-recon/`） |
| 2 | `grep -n "R4 后补" docs/_simplify-recon/11-cli-redesign.md \| grep -cv -e 留痕 -e 订正 -e 错称 -e grep -e 复核 -e 纪律 -e 自检`（模式只写**前缀**，避免自检行自己污染计数；门槛是"未标记命中"） | **= 0** | **0**（同一命令在 `13-*.md` 上也 = 0，见 `13-*.md §6`） |
| 3 | `grep -n "两个逻辑标志" docs/_simplify-recon/11-cli-redesign.md \| grep -cv -e 作废 -e 订正 -e 复核 -e 留痕 -e 自检`（同 `13-*.md §6` 第 6/7 行；原始命中 **7** 处，全部是作废/订正/自检句） | **= 0**（不允许再有一行把它当成**现行**机制） | **0**（唯一"现行"描述已改为单一 `landscape_native_engine`） |
| 4 | `grep -c "Numerical Hessian" ohess.out`（原生 `--ohess normal`） | 1（基线） | 1 |
| 5 | `grep -c "Frequency Printout" ohess.out` | 1（基线） | 1 |
| 6 | `grep -c "ANC micro-cycles" ohess.out` | 1（基线） | 1 |
| 7 | `grep -c "Geometry Summary" ohess.out` | 1（`:1279` 原生写点） | 1 |
| 8 | `grep -c "TOTAL ENTHALPY" ohess.out` | 1（不得因 T3 处置而消失） | 1 |
| 9 | `ls ohess` 目录 | `hessian`/`vibspectrum`/`g98.out`/`compliance.dat`/`.xtboptok`/`xtbopt.log` | 全部存在 |
| 10 | `grep -c "Frequency Printout" lvib.out`（套件 `--lvib`） | 0（套件不经过 `:1283` 的 header） | 0 |
| 11 | `grep -c "TOTAL ENTHALPY" lvib.out` | 0（`hess=.false.` ⇒ **T3 置假就会少这两行**） | 0 |
| 12 | `grep -c "landscape: harmonic frequencies" lvib.out` | 1（套件 vib 链入口，`tasks/vib.f90:118`） | 1 |
| 13 | `grep "landscape engine: Hessians" lvib.out` | 值 = **1**（Hessian 计数，HIGH-1 的"只跑一次"直接判据） | `landscape engine: Hessians           1` |
| 14 | `./frag`（`frag.f90` 镜像 `data.F90:105-129` 的默认初值） | `allocated(freq)=F`、`n3true=0`、`etot=htot=gtot=0` ⇒ 半修 = **静默 0** | 全命中 |
| 15 | `grep -c "landscape optimizer:" lopt.out`（套件 `--lopt`） | 1（计时标签） | 1 |
| 16 | `grep -c "ANC optimizer:" ohess.out` | 1（原生标签；改派后必须换名，见 §3.11 读点表 #14） | 1 |
| 17 | `wc -l docs/_simplify-recon/11-cli-redesign.md docs/_simplify-recon/13-cli-redesign-revision.md`（自检） | 都 ≥ R2 末的行数（2423 / 116） | **2851 / 191**（本轮末实跑） |

**复现片段（原始命令）**：

```bash
# 原生 ─ohess 基线（本轮实测）
printf '3\nwater\nO  0.0000000  0.0000000  0.0000000\nH  0.0000000  0.0000000  0.9600000\nH  0.9300000  0.0000000 -0.2400000\n' > h2o.xyz
OMP_NUM_THREADS=1 XTBPATH=/home/owenchan/work_path/coding/fortran/xtb \
  /tmp/xtb-w2/build/xtb h2o.xyz --gfn2 --norestart --ohess normal > ohess.out 2>&1
OMP_NUM_THREADS=1 XTBPATH=/home/owenchan/work_path/coding/fortran/xtb \
  /tmp/xtb-w2/build/xtb h2o.xyz --gfn2 --norestart --lvib        > lvib.out 2>&1
OMP_NUM_THREADS=1 XTBPATH=/home/owenchan/work_path/coding/fortran/xtb \
  /tmp/xtb-w2/build/xtb h2o.xyz --gfn2 --norestart --lopt        > lopt.out 2>&1
# 半修后果的语言级验证（非 xtb 代码路径，只看默认初值语义）
gfortran -o frag frag.f90 && ./frag
```

> **本轮的"未跑"項（诚实登记）**：`--method` 今天不存在（§13c #10），所以
> 阶段 3 的 `--ohess` 套件路径**无法在本轮实跑**；§3.11.1 里的都是**判据 + 今天原生侧的基线 token**，
> 而不是已通过的验收数字。它们的验收在阶段 3 落地的那一轮。

### 16.5 MEDIUM-3（作废机制残留的全局搜索）

```bash
grep -rn "landscape_native_ancopt\|landscape_opt_alias" docs/_simplify-recon/1*.md
grep -rn "两个逻辑标志" docs/_simplify-recon/11-cli-redesign.md docs/_simplify-recon/13-cli-redesign-revision.md  # 自检
```

> **行号口径**：行号随每次修订漂移（本轮追加 §16/§17 后整体下移），所以**判据是命中数与命中性质，不是行号**；
> 下表给"R29 前 → R29 后（本轮末）"两个行号，均可用上面的 `grep -n` 直接核出。

| 命中（本轮末实跑） | 位置 | 判定 |
|---|---|---|
| `landscape_native_ancopt` | `11:54`（R22 修订记录）、`11:726`（§3.8 的 R22 修订说明，R29 前 `:711`）、`11:893/895`（**作废声明本身**，R29 前 `:875/877`）、`11:2358`（§12 U1 的作废名单） | **保留**：全部是"旧写法 → 新写法"的**历史/作废记录**（5 处），删掉反而丢失可追溯性；`§3.8` 前置段另加了一句"同一位也是原生 Hessian 路径的唯一判据"（R29） |
| `landscape_opt_alias` | `11:897`（作废理由第 2 条，R29 前 `:879`） | **保留**（同上） |
| "两个逻辑标志" | `11:893`（作废声明）、**`11:2358`（U1，已改）**、**`11:2501`（§14.2 M8，已改）** | 改 2 处 + 保留 1 处作废声明（自检句另计，见 §16.4 第 3 行） |
| "逻辑标志" | **`13:20`（R16 行，已改、已订正）** | 改为单一 `landscape_native_engine`（订正说明见 `13-*.md §1`） |

⇒ 本轮改动 **3 处**（`11:2183`→现 `11:2358`、`11:2322`→现 `11:2501`、`13:18`→现 `13:20`），
保留 **6 处历史/作废**记录；"未把它当现行机制"的判据 = §16.4 第 3 行与 `13-*.md §6` 第 6/7 行的 **0**。

### 16.6 LOW 逐条处置（7 + 2 INFO 相关）

| # | 复核位置/证据 | 处置 | 改动位置 / 理由 |
|---|---|---|---|
| **L-1** | 声称"4 个引擎 / 8 个拼写"、"18+8=26"，而自己枚举的是 7 个 | **已改**：`8→7`、`26→25`（4 处）+ `§9.2` 的"23 个名字"口径澄清 | `§4.1`（`11:1015/1035/1036`）、`§4.8`、`§9.2` |
| **L-2** | `§3.7` 写 `main_geometry`+`main_freq` 在 `:1282`/`:1287`（实际 `:1279`/`:1284`） | **已改** + 注明 `:1282`/`:1287` 实际是什么 | `§3.7` |
| **L-3** | `§4.7` 伪代码注释写"n>50 0" | **已改** → `n > 500`（`defaults.f90:43`） | `§4.7` 第 2 段 |
| **L-4** | 读点表漏 4 个原生读者；`(b)/(c)` 位置措辞不一致 | **已改**：读点表补 5 行（#10-15）；`(a)(b)(c)` 三处统一为 `main.F90:491-510`（附"为何与分派点等价"）；`:1310-1320` 与 `:4065-4071` **入抑制集合**；`:1276-1280` **保留**（实测：原生 `--ohess` 打 `Geometry Summary` 1 次、套件 `--lopt`打 0 次 ⇒ 保留才是与今天同形） | `§3.11` 读点表、`§3.11.1`、`§3.8(b)(c)` |
| **L-5** | `--opt <LEVEL>` → 套件档的映射实现点未给 | **已改**：补 `set%optset%optlev` 写点（`main.F90:2153-2157` → `set_module.f90:1811`/`:1910-1928`）与套件分派处的读法 | `§3.5` |
| **L-6** | 写"套件无 CPCM-X/PTB 路径"，而 `:1197-1216` 不受 runtyp 守卫 | **已改**：措辞改为"改派不改变 `:321`/`:326` 这两个 terminate 读点的行为"（行为不改） | `§3.11` M-3 段 |
| **L-7** | `>500 原子 fixture` 在 GFN2 上不可行 | **已改**：改用 **GFN-FF 501 原子非周期** fixture（避开 `:933-937` 的周期强制） | `§4.7.1` |

### 16.7 INFO 与 U15/U16

- **INFO-1（U15）**：定 **(b) 打 `[WARNING]`**（详 §12 U15）。属 §3.8 守卫族的**诊断扩展**，不改行为、不改计数。
- **INFO-2（编号规则）**：沿用（先数内容、再对编号；本轮新增的 U17 不占用复核 ID）。
- **U16**：定 **允许、不加警告**（详 §12 U16）。

### 16.8 新发现（本轮自己找到的，不在复核清单里）

| # | 现象 | 证据 | 处置 |
|---|---|---|---|
| **U17** | 套件 `--ohess` 下 `--o1nh`（ODLR）成为死旋钮：套件只拒绝 `settings%engine%odlr`（`vib/numhess.f90:111-116`），而 `--o1nh` 只写 `set%o1numhess`（`main.F90:2181`），两者不同源 | 本轮读源码；HEAD 上 `--lopt --o1nh` 已经是静默（非本设计引入） | **登记为开放项**（候选 C8，计数 16→17），需用户/下一轮裁定；不阻塞阶段 1-3（详 §12 U17） |
| — | `:1300-1306` 的 `set%property_file` 写点也是 `fres` 读者（复核只列了 `:1324`） | 本轮读源码 | 已纳入 T3 的覆盖（§3.11 读点表 #12） |
| — | `main_xtb_json`（`:1287-1298`）也是 `fres` 读者，但其数组分支有 `n3true > 0` 守卫 | `json.F90:102/111` | 同上；并推翻了复核的"半修即崩"（§3.11.1 的订正段） |

### 16.9 更新后的计数与阶段状态

**破坏性计数：仍为 16 条**（A 3 + B 0 + C 7 + D 1 + E 1 + F 3 + G 1），理由见 §10 末的 R29/R35 注。
**若采纳 U17 → 17**（候选 C8，未定）。

| 阶段 | 状态（本轮末） | 依据 |
|---|---|---|
| **阶段 1** | **可实施** | 第 3 轮复核 §11 确认（M-4/M-1 已修，集合 S 为纯套件集合）；工作清单见 §17 |
| **阶段 2** | **可实施** | 复核确认；`--method` 的**套件侧**机制已逐行核过 |
| **阶段 3（`--opt` 半边）** | **可实施** | H-1/H-2/M-2 已闭合 + M-3 的 `:931` 抑制已指定 + R29 补了 `:1310-1320`/`:4065-4071`；前置 = R30 一行 |
| **阶段 3（`--ohess` 半边）** | **本轮解除阻塞** | R29（§3.11.1）给了 T1/T2/T3 的判据、位置、自证表与 4 条测试；前置 = R30 一行 |

> **实施顺序（R35 建议）**：1) R30 的 `landscape_native_engine = 0` + R22 的单一标志；2) R21 的解析尾两段归一；
> 3) R24 的 `:931` 抑制与 R29 的 T1/T2 抑制 + `fres` 桥；4) R23 的 C7 与 R1 的三类守卫；
> 5) R29 的 `:1310-1320`/计时标签；6) R34 的 U15 warning。前两步是所有后续步骤的判据来源。

---

## 17. 【R35 新增】阶段 1 工作清单（下轮可直接执行）

> **准入前提**：本节只列**不依赖 `--opt` 改派**的东西（复核已确认阶段 1 可实施）。
> **禁止事项**：不引入 `--method`、不改 runtyp 语义、不碰 `--opt`/`--ohess` 的分派、不动 `src/type`/`src/xtb`/`src/mctc`/`src/param`/`src/io`/`src/disp`/`src/coulomb`。
> 每条给：**改动点（file:line）/ 验收方式 / 需要的测试 / 反向突变（必红）**。

### 17.1 冲突组合检测（§8.1 + §8.7 的 C1 族）

| 项 | 内容 |
|---|---|
| 改动点 | `src/prog/main.F90` 新增 `select_runtyp(env, typ, flag)`（与 `set_runtyp` 同构，额外记 `flag` 字符串）；把 `parseArguments` 里**所有** runtype 旗标的 `call set_runtyp('...')` 换成它（`--opt` `:2154`、`--hess` `:2160`、`--ohess` `:2166`、`--lopt` `:2244`、`--lscan` `:2296`、`--lts` `:2575`、`--lirc` `:3318`、`--lvib` `:3683` 等；`grep -n "call set_runtyp" src/prog/main.F90` 逐条核） |
| 语义 | 第二次要求**不同** runtyp ⇒ `env%error`（文本见 §8.1）；同一 runtyp 重复（如 `--lopt --lopt-engine bfgs` 隐含的 lopt）**不报错** |
| 验收 | `--lopt --lscan` / `--opt --hess` / `--lts --lirc` 非零退出且点名第二个旗标；`--lopt-engine bfgs`、`--lscan-method cg` 等**仍 exit 0**（§5.1 #2/#7/#23） |
| 测试 | 新增 `xtb/landscape-runtype-conflict`（`--lopt --lscan`）；`xtb/landscape-opt-hess-conflict`（`--opt --hess`）；旧测试回归子集重跑（`-R landscape`） |
| 反向突变 | 去掉第二次冲突判定 ⇒ 两个新测试红 |
| 注意（阶段 1 的 BC-4） | `--lopt-engine` 等**子选项**会隐含 `set_runtyp('lopt')`（`:2249` 等）；`select_runtyp` 必须把"同一 typ 的重复选择"当无操作，否则会误报 |

### 17.2 必填参数报错点名 flag（§8.2）

| 项 | 内容 |
|---|---|
| 改动点 | `src/landscape/scan/relax_scan.f90` 的 `landscape_scan_check`：`:533`（越界）、`:545-551`（`nstep`）、`:556`（零步长）三条 `env%error` 文本改为点名旗标（目标文本见 §8.2 的表） |
| 验收 | `--lscan`（无坐标）的消息含 `--lscan-atoms`；`--lscan-nstep 0` 的消息含 `--lscan-nstep`；`--lscan-step 0` 的消息含 `--lscan-step` |
| 测试 | **必须同步改**两条既有断言（它们断的是旧文本）：`test/unit/CMakeLists.txt:658-663`（`xtb/landscape-scan-nstep-missing`，`PATTERN=at least one step is required`）与 `:664-669`（`xtb/landscape-scan-atom-range`，`PATTERN=outside 1..3`） |
| 反向突变 | 把新文本换回旧文本 ⇒ 两条既有测试绿、新断言红 |

### 17.3 危险默认回显（§8.3，清单 D1/D2/D3/D4/D7）

| 项 | 内容 |
|---|---|
| 改动点 | 套件任务的启动打印处（`tasks/opt.f90`、`tasks/scan.f90`、`tasks/vib.f90` 的 `printlevel > 0` 块，例如 `vib.f90:118-136` 已是范本；`--lts-escape-step` 与 `--lirc-method=hpc` 各自的 banner 处） |
| 内容 | 四类：`--lscan-fc` 默认 0.5 vs 上游 0.05（`settings.f90:545`）；`--lirc-method` 默认 `hpc`；`--lopt-engine` 默认 `lbfgs`（在 C 之后与 `--opt` 旧默认不同）；`--lts-escape-step` 会移动输入几何 |
| 验收 | 每个默认的 banner 行可 `grep`（统一前缀 `[NOTICE]` 或 `landscape:`）；显式给值时**不再**打（或用 `differ from` 变体） |
| 测试 | `xtb/landscape-fc-echo`、`-lirc-default-echo`、`-lts-escape-echo`；反向突变：删掉打印 |

### 17.4 `--help` 与实现的**双向一致性**（§8.4/§8.6，集合 S 门槛）

| 项 | 内容 |
|---|---|
| 改动点 | 新增 `test/unit/landscape_help_check.py`（抽取规则写死：从 `src/prog/main.F90` 的 `case ('...')` 标签与 `src/xhelp.f90` 的 help 文本里抓以 `-` 开头的 token，逗号别名拆开、`[no]` 展开）；注册为 `test/unit/CMakeLists.txt` 的新 `add_test("xtb/landscape-help-coverage" ...)` + `test/unit/meson.build` 同步 |
| 断言 | **集合 S = 以 `--l` 开头或等于 `--method` 的拼写**，要求 `S(实现) == S(help)`（差集为空）；**集合 N 只打印**（30/4 或 34/5，两种口径都打出来）；脚本必须把抽取规则与两个计数打印到输出 |
| 验收 | 输出含 `S: 0 differences`、`N(implemented, undocumented) = 30`、`N(documented, unimplemented) = 4`（或 34/5，取决于规则） |
| 反向突变 | 在 `main.F90` 加一个不写 help 的 `--lzzzz` case ⇒ 集合 S 差集非空 ⇒ 红 |
| 注意 | `test/unit/CMakeLists.txt` 的 **测试名必须唯一**（AGENTS §4：同名 `add_test` 会被静默丢掉） |

### 17.5 `--strict` 提前 + 套件枚举转小写（§8.5）

| 项 | 内容 |
|---|---|
| 5a 改动点 | `src/prog/main.F90:1583`（`case default` 的 `env%warning("Unknown option '"//flag//"' provided")`）依赖 `env%strict`，而 `env%strict = strict` 在 `:608` 之后才生效 |
| 5a 方案 | 把 `env%strict` 的同步移进解析循环（`case('--strict')` 处立即 `env%strict = .true.`），或把未知旗标改在解析尾统一报（两者选一，实施时记入报告） |
| 5a 验收/测试 | `--strict --zzzz` 非零退出（§10 F2）；新增 `xtb/landscape-strict-unknown`；反向突变：还原 `:608` 的位置 |
| 5b 改动点 | 四个套件名字解析函数：`settings.f90:1112`（最小化器）、`:1229`（IRC）、`:1295`（TS）、`:1497`（档位）；以及 `scan_coord_from_name`（`:1425`） |
| 5b 方案 | 入口统一 `name = lowercase(trim(name))`（已有 `xtb_mctc_strings` 的 `lowercase` 可用；`set_module.f90` 的 CLI 侧已用同名子程序） |
| 5b 验收/测试 | `--lopt-engine BFGS` 与 `bfgs` **输出逐位同**；新增 `xtb/landscape-enum-case`；反向突变：去掉 `lowercase` ⇒ 大写变 error ⇒ 红（这是**有意**的行为变更，入册为 §10 F 类同族） |
| 5b 风险 | `xhelp.f90` 与 `man/` 需同步说明大小写不敏感（§7.5） |

### 17.6 阶段 1 的共同验收

1. `ctest -R landscape` 全绿（**新增测试**与既有测试都在内；不跑全量 ctest）；
2. **BC-4 逐位不变**：`--hess`、`--sp`、`--md` 等的输出与阶段 1 前逐位相同（用同一 fixture 前后 diff）；
3. §5.1 的 **#20/#21/#23/#25 逐条变红并确认**（它们就是本条设计的标的）；
4. §8.4 的集合 S 差集 = 0（**门槛**），集合 N 的计数打印但不作门槛；
5. 报告里贴出：`git diff --stat -- src test man`、四条测试的**改动前（红）/改动后（绿）**输出、集合 S/N 的计数。

