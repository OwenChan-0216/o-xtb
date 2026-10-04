## 摘要（≤30 行）

**结论：接受（OK with notes）。阶段 3a 含修复轮可以提交 git**（无 CRITICAL / HIGH / MEDIUM；4 项 P2 全部为文档与测试覆盖，不需回滚）。

- **T1 正确**：slot 5 标签现读 `landscape_native_hessian_path`（`main.F90:4778-4795`），与 `:1291`/`:1421` 的抑制**同一谓词**；旧裸 runtyp 三元确实会在套件 `--ohess` 上打出不实的 `0.000 sec`。新令牌 `("analytical hessian", 0)`（`landscape_cli_check.py:3686`）可证伪。
- **T2 映射逐档符合设计 §3.5**（`main.F90:4634-4650`）：crude/sloppy→superloose、loose/lax→loose、normal、tight、verytight/vtight/extreme→vtight、superloose，数字 `-3..-2/-1/0/1/2..3` 与名字档一致；写入**同一字段** `set_conv_level`（`:4461`）；回显的是**映射后的有效值**（`:4464`）。`--opt` 不带 LEVEL 时回显 normal 而不调用 setter —— 经核对默认阈值（`settings.f90:376-384`）恰为 normal 行（`:1138-1142`），**不是**不实回显。F3 只在 `landscape_native_engine == 0` 分支（`:4448-4459`），`optlevel2int` 未动。
- **优先级规则不可达属实**：`--lopt-level` 在自己的 case 调 `select_runtyp(env,'lopt',…)`（`:2516`），与 `--opt` 的 `opt` 在桥**之前**冲突并点名两旗标；桥里不写死代码是对的（报告 §4.3 准确）。
- **T3 正确**：`--cycles` 仍先 `set_opt(env,'maxcycle',…)`（`:2171`）⇒ **原生 `set%optset%maxoptcycle` 未改**；桥按 `effective_landscape_task` 分派（`:4472-4492`），5 个目标字段 `lset/lsset/ltset/lircset%max_steps` **全部有消费点**（`optimize/driver.f90:225`、`relax_scan.f90:600`、`tasks/ts.f90:1217`+`saddle/prfo.f90:504`、`tasks/irc.f90:724`+`irc/*.f90`）；`--lvib` 响亮报错；冲突消息点名两个旗标。
- **可证伪性成立**：三处注入都打在**消费点/映射本体**上；预算断言用 `--cycles 4`（水默认 5 步）**真 binding**，不是恒真（任务书的 `--cycles 8` 确实不 binding，实施者 §4.4 的自我纠正正确）。唯一"半恒真"风险见 P2-2。
- **T4/T5 登记合格**：`42` 有 5 处 `[订正 R45-Fx]` 且原文保留，`43 §9` 有总指针；`xhelp.f90` 4 处已修且与三条守卫文案（`main.F90:544/549/556`）一致；`env%check` 确实不在两段 `run_landscape` 之间 ⇒ §5.1 "套件也跑 vib" 成立；核心层 `src/{type,xtb,mctc,param,io,disp,coulomb}` 改动 = **0**；档位四轴/§3.9/自指全文**未越界**（`settings.f90` 不在改动列表）。
- **P2（有条件）**：见正文 P2-1..P2-4，其中 **P2-3 是本轮主题内的不实陈述**（§5.3 第 10 条"文件名集合与原生相同"与设计 §5.4 自相矛盾），建议提交前一句话订正。
- **未做**：未运行任何命令（只读）；ctest 138/138、逐位相同、n_steps 具体值、原生 `--ohess` 未收敛 exit 0 等**均为采信父会话/实施者实测**，我未复算；meson 条目无法本地执行。

---

## 完整报告正文（父会话落盘为 `docs/_simplify-recon/48-stage3a-fix-review.md`）

# 48 — 阶段 3a 修复轮独立复核

> 角色：独立复核（只读，未运行任何命令）。对象 = `docs/_simplify-recon/45-stage3a-fix.md` + 工作树 delta（相对 `2b49ef8`）。
> 纪律：所有结论来自**静态核对**；实施者/父会话的实测数字（138/138、逐位相同、n_steps 值、原生退出码）我**未复算**，仅在文末"未能验证"中登记。
> 上一轮：`44-stage3a-review.md` **本轮开始时不存在**（实施者在 `45` §0 已声明），因此我对 T5 的 `--help` 三处矛盾做了独立穷尽（复核到 **4** 处，与实施者一致）。

## 1. 判据唯一性（本阶段主题）

| 读点 | 位置 | 判据 |
|---|---|---|
| 三条护栏 | `main.F90:520` | `landscape_is_suite_run` |
| 原生 opt 块抑制 | `:987` | `anyopt .and. landscape_native_engine /= 0` |
| `--ljson` 告警 | `:1045` | `landscape_is_suite_run` |
| `[NOTICE]` | `:1055` | `landscape_is_suite_run` |
| lopt/vib 分派 | `:1069`/`:1206` | `effective_landscape_task` |
| 原生 Hessian 块 | `:1291` | `landscape_native_hessian_path` |
| 原生 freq 块 | `:1421` | `landscape_native_hessian_path` |
| 原生几何写出 | `:1457` | `landscape_is_suite_run` |
| **slot 3 标签** | `:5241`/`:5244` | `landscape_is_suite_run` / `effective_landscape_task` |
| **slot 5 标签（T1）** | `:5265` | **`landscape_native_hessian_path`** ✅ |
| `--cycles` 桥（T3） | `:4473` | `effective_landscape_task` ✅ |
| **`--opt <LEVEL>` 桥（T2）** | **`:4448`** | **`set%runtyp == p_run_opt .or. p_run_ohess .and. landscape_native_engine == 0`（内联重写）** ⚠ |

`grep -n "p_run_ohess|p_run_opt|anyopt|anyhess|set%runtyp =="` 的全部读点已穷尽：`set%runtyp == p_run_opt` 的裸比较只出现在 `main.F90:4448`（T2 桥）、`:5239`（finalize slot 3，与 `landscape_is_suite_run` 合取，正确）、`:1056`（NOTICE，与 `landscape_is_suite_run` 合取，正确）、`:4716`（`effective_landscape_task` 本体，正确）。

**判定**：**不构成"第二套判据"**（`:4448` 的表达式与 `effective_landscape_task(...) == p_run_lopt` **语义等价**，不存在两条逻辑能分叉的情形），但它是**同一判据的第二次书写**，见 P2-1。

T1 附带的"slot 5 是唯一按裸 runtyp 判定且套件路径必然为 0"（`45` §6 全表）与代码一致：slot 3 已被谓词覆盖，其余 slot 的 `start_timing` 与本标签不同路径，或该 runtype 根本不改派。

## 2. T2 映射正确性（逐档核对设计 §3.5）

设计 §3.5 表 vs `main.F90:4634-4650`：

| `--opt` 关键字 | 设计 | 实现 | |
|---|---|---|---|
| crude | superloose | superloose | ✅ |
| sloppy | superloose | superloose | ✅ |
| loose | loose | loose | ✅ |
| lax | loose | loose | ✅ |
| normal | normal | normal | ✅ |
| tight | tight | tight | ✅ |
| verytight / vtight | vtight | vtight | ✅ |
| extreme | vtight（上限截断） | vtight | ✅ |
| superloose | superloose | superloose | ✅ |
| 数字 `-3..3` | 同上映射 | `-3,-2`→superloose，`-1`→loose，`0`→normal，`1`→tight，`2,3`→vtight | ✅（与 `setparam.f90:256-257` 的 crude=-3…extreme=3 一一对应） |
| 未知 | error | `env%error("Unknown --opt level '<x>'…")`（`:4455`） | ✅ |

- **落点**：写入 `lset%set_conv_level(landscape_opt_conv_level)`（`:4461`），与 `--lopt-level` **同一字段** —— 与 `45` §3.1 的"逐位相同"断言一致。
- **回显有效值**：`:4464` 打的是 `landscape_opt_conv_level`（映射结果），不是旗标原文。✅
- **不带 LEVEL**：回显 `normal` 且**不调用** setter。核对 `settings.f90:376-384`（`g_max=3.0e-4, g_rms=1.0e-4, d_max=4.0e-3, d_rms=2.0e-3`）== `set_conv_level` 的 `normal` 分支（`:1138-1142`）⇒ **回显诚实**，不是"回显了没生效的档位"。✅（这也覆盖了 3a 的默认路径。）
- **F3 的作用域**：错误只在 `(runtyp∈{opt,ohess}) .and. landscape_native_engine == 0` 内（`:4448`/`:4455`）；`set_module.f90` 的 `optlevel2int` 未被改动（`git diff` 中 `set_module.f90` 的 67 行全部是 `xcontrol_supplied` 相关）⇒ 原生 `--opt --method ancopt banana` 保持静默 normal。✅
- **优先级规则**：`--opt tight --lopt-level loose` 在桥之前由 `select_runtyp` 报 `run type conflict: --opt already selected the 'opt' run type, --lopt-level would select 'lopt'` ⇒ 结构上不可达，"不实现死代码"正确；设计 §19.1 已登记该订正。✅

## 3. T3 映射正确性

- **目标字段**（`:4474-4485`）：`p_run_lopt→lset%max_steps`、`p_run_lscan→lsset%max_steps`、`p_run_lts→ltset%max_steps`、`p_run_lirc→lircset%max_steps`，与设计 §3.10b 表逐行一致。四个字段都有真实消费点（§1 摘要已列）—— `ltset%max_steps` 同时驱动 prfo/dimer 的宏步与端点弛豫，`lircset%max_steps` 是路径预算，`lsset%max_steps` 是内层弛豫预算，均与 §3.10b 的备注相符。
- **`--lvib`**：`case (p_run_lvib)` → `env%error("--cycles has no meaning for --lvib: the frequency task has no step budget")`（`:4487`）。✅
- **冲突检测点名两个旗标**：`landscape_bridge_step_budget`（`:4660-4690`）写 `"--cycles N conflicts with <flag> M: give only one step budget"`；异值报错、同值幂等。✅
- **原生路径保持 `set%optset%maxoptcycle`**：`case('--cycles')`（`:2171`）**仍**调 `set_opt(env,'maxcycle',sec)`；桥的 `case default → continue` 不触碰任何字段。`--opt/--ohess --method <native>` 的 effective task 是 `p_run_opt/p_run_ohess` ⇒ 落 default。✅
- T3 落点用纯函数 `effective_landscape_task`（与 T2 内联写法不同，见 P2-1）。

## 4. 可证伪性

| 项 | 注入点 | 是否在消费点 | 断言是否恒真 |
|---|---|---|---|
| T1 | slot 5 谓词退回裸 runtyp 三元 | ✅（打出标签的判据本体） | 否（`("analytical hessian",0)` 是新令牌，改前打印 1 次） |
| T2 | `crude/sloppy/superloose` 分支写死 `normal` | ✅（映射本体） | 否（`crude != tight`；若桥"只回显不写字段"也变红） |
| T3 | `if (cycles_given)` → `if (.false. .and. cycles_given)` | ✅（映射入口） | 否（`--cycles 4` == `--lopt-max-steps 4` **且** `< default`，水 fixture 默认 5 步 ⇒ binding） |
| T1 反向 | — | `("analytical hessian",1)`（原生 `--ohess --method ancopt`） | 否（反向钉住，恒假谓词会红） |

`45` §4.4 对任务书 `--cycles 8` 的证伪（不 binding）**正确**，最终测试确实改成了会咬人的值；报告 §230 的自纠已核对。**未发现恒真断言**（唯一弱点是覆盖不足，见 P2-2）。

## 5. T4 / T5 登记质量

- **T4**：`42-stage3a-impl.md` 有 5 处 `[订正 R45-F4/F5/F6/F7/F8]`，均**原文保留 + 指针**（§2.3 `:119`、§3 inj1 `:159`、§4.1 F1 `:202`、§4.2 `:185`、§5.2 `:277`）；`43-stage3a-validation.md:290` 有总指针。✅
- **T5-1（`--ohess` 失败后行为）**：`main.F90:1094-1133` 中两段 `run_landscape` 之间**没有** `env%check`（只有第二段之后的 `env%checkpoint`），而 `tasks/opt.f90:214-222` 未收敛时是 `env%error`（只置位、不即时中止）⇒ "套件也照样跑 vib" **结构上成立**；与原生的一致性结论合理，exit code 差异登记为有意。✅
- **T5-2（`--help`）**：`src/xhelp.f90` 4 处已改（`--opt`、`--method`、`--lopt`、`--ohess`），且 `--lopt` 的新指引 `--opt --method ancopt` 与三条守卫文案（`main.F90:544/549/556`）**一致**。✅
- **T5-3（BC-4 穷尽清单）**：`11-cli-redesign.md:3126-3178` 的 §19.4 覆盖了复核点名的全部项（`analytical hessian` 标签消失=第 3 条、档位回显行=第 2 条、json 数量=第 8/9 条、NOTICE=第 1/2 条、C7=第 11 条）⇒ **对这 5 项是真穷尽**；但对**文件集合**一项**不穷尽且不实**，见 P2-3。

## Findings

### P2-1（判据重复书写，非分叉）`main.F90:4448`
T2 桥用内联 `(set%runtyp == p_run_opt .or. set%runtyp == p_run_ohess) .and. landscape_native_engine == 0`，而 T3 桥（`:4473`）与全部其它读点用 `effective_landscape_task(...)`/`landscape_is_suite_run(...)`。两者**语义等价**（已核对 `:4716`），所以本轮无行为缺陷；但 `:4701` 的文档注释声称这组纯函数是"the **only** criterion of the guards, the suppression of the native blocks, the dispatch and `--cycles`/`--ljson`"，与该行不符（既有漂移风险，也有注释不精确）。
**最小修法**：`:4448` 改成 `if (effective_landscape_task(set%runtyp, landscape_native_engine) == p_run_lopt) then`（行为不变，注释随之成立）。

### P2-2（新映射表覆盖不足）`landscape_cli_check.py:3920-3986`
新增的 10 项映射表只被 `crude`、`tight`、`banana` 三个取值触达：`lax`、`sloppy`、`superloose`、`verytight`、`vtight`、`extreme`、数字 `-3..3` **全无断言**。把 `lax` 分支错写成 `normal`（设计 §5.5 明确要求 `lax`→套件 `loose`）在现有 138 个测试下**仍全绿**。另外设计 §9.2 的 `xtb/landscape-method-level-bridge` 所要求的 `--lopt-level lax` **非零**（L-4 "不收上游名"）在 `test/unit` 中 `grep` **0 命中**，无覆盖。
**最小修法**：在 `check_opt_level_bridge` 里加一个逐档表（关键字 → 期望回显名），用 `--opt <kw> --ljson` 的 `n_steps` 或 banner 文本断言；补一条 `--lopt-level lax` 非零断言。

### P2-3（本轮主题：**不实陈述**）`45-stage3a-fix.md` §5.3 第 10 条 + `11-cli-redesign.md` §19.4
第 10 条写 "`--ohess` 套件链写 `hessian`/`vibspectrum`/`g98.out`/`vib_normal_modes`/`xtbopt.xyz`（**文件名集合与原生相同**，内容来自套件）"。这与同仓库设计 §5.4/§3.9 的对照表**自相矛盾**：套件缺少 `xtbopt.log`、`.xtboptok`、`compliance.dat`（设计 §5.4 明确标为"破坏"，待 R4/§3.9=3b 补写；实证：`grep -rn "xtboptok\|xtbopt\.log\|compliance" src/landscape/` = 0 命中，而原生侧 `geoopt_driver.f90:121/186`、`hessian.F90:331-332` 写出），且**多出** `vib_normal_modes`、`xtb.trj`（§5.4 亦如此标注）。因此"文件名集合与原生相同"不成立。
同一条清单的收尾句"（穷尽；**未列出者 = 逐位不变**）"对**改派 run 的 stdout**也不成立：`main.F90:987` 抑制掉整段原生 ANCopt 输出块后，`--opt`/`--ohess` 的**逐迭代输出体**由套件 banner/表取代，清单只列了 slot 3 计时标签与 NOTICE 两行。
**最小修法**：（a）把第 10 条改为"少了 `xtbopt.log`/`.xtboptok`/`compliance.dat`（3b 补），多了 `vib_normal_modes`/`xtb.trj`"；（b）清单补一行"改派 run 的逐迭代输出块（原生 `micro-cycle` 表 → 套件 banner/表）整体替换"；（c）把"未列出者 = 逐位不变"限定为"未改派 runtype 的文件"。

### P2-4（INFO 级，随 P2-3 一起处理）
BC-4 的"正确判据"（§19.5）本身写得准确（文件逐位相同 + stdout 差异仅限已登记非确定性），本轮无需再改。

### INFO
1. `xhelp.f90` 未记录数字别名 `-3..3`（实现接受）。集合覆盖检查只查旗标，不会红；是否补文档由设计决定。
2. `--opt banana` 报错后仍打 `[NOTICE] landscape convergence level: normal`（`:4459` 先把变量置 normal 再 `write`）。进程退出 1，无功能影响，但两行并排略显矛盾，可在报错分支跳过 banner。

## 越界核对（优先级 7）

- 档位四轴（`e_tol`/`acc`/`max_steps` 随档位）：**未做** —— `src/landscape/types/settings.f90` 不在改动列表，`set_conv_level` 仍只写 4 个阈值。✅（与 `45` §8.5 声明一致）
- §3.9 的 4 个遗留文件、C1-C4、自指引导全文：**未做**。✅
- 核心层 `src/{type,xtb,mctc,param,io,disp,coulomb}`：改动 **0**（改动文件为 `docs/*`、`src/landscape/tasks/vib.f90`、`src/landscape/types/results.f90`、`src/prog/main.F90`、`src/set_module.f90`、`src/setparam.f90`、`src/xhelp.f90`、`test/unit/*`）。✅
- 测试注册：CMake + meson 两处都有（`CMakeLists.txt:3759/3769/3830/3831`、`meson.build:881/885`），新测试进入 `OMP_NUM_THREADS=1` 名单（`:3820-3833`），测试名无重复。✅

## 未能验证 / 残留风险

1. **未运行任何命令**（只读）。`ctest -R landscape` 138/138、`--opt tight` 与 `--lopt --lopt-level tight` 逐位相同、`n_steps` = 3/4/5、`--opt banana` exit 1、原生 `--ohess` 未收敛 exit 0 等，全部**采信**父会话/实施者实测；建议提交前由有执行权者再跑一次 `ctest -R landscape`（`OMP_NUM_THREADS=1`，`timeout 600`）与 `-R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'`。
2. `45` §3.3 的计数公式"136 + 2"未与 `ctest -N` 总数列对照（我只核到 3a 新增 11 条 + 本轮 2 条的注册文本）；总数以父会话实测 138 为准。
3. meson 条目（`meson.build:881-888`）本机无法执行。
4. `xtb/GFN2-FF` 与工作目录裸名 `charges` 的耦合（`45` §3.3）是既有测试隔离缺陷，本轮未引入、未修。

## 结论

**接受（OK with notes）；阶段 3a（含修复轮）可以提交 git。** 无 P0/P1；P2-1 是一行等价改写，P2-2 是补测试，P2-3/P2-4 是文档订正（其中 P2-3 建议在本次提交前顺手改掉，因为它正是本轮主题"消除不实陈述"的同类残留）。