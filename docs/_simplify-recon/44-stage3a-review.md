## Review — 阶段 3a（`--opt`/`--ohess` 改派 + 三条守卫）

**结论：有条件接受（CRITICAL 0 / HIGH 0 / MEDIUM 1 / LOW 4 / INFO 7）。可以提交 git；建议把 MEDIUM-1（2 行）顺手带上，否则必须写成 3b 第一项。**

- **Correct（判据唯一性成立）**：9 个 read point（三守卫 `main.F90:520`、`--ljson` `:1045`、NOTICE `:1055`、5 处分派 `:1069/1141/1157/1187/1206`、原生块抑制 `:987`、T1 `:1291`、T2 `:1421`、`xtbopt.xyz` `:1457`、slot-3 计时 `:5057`）**全部**读四个纯函数；`grep runtyp src/landscape/` = 0；`p_run_l*` 每个残余读点都是"按 runtyp 选择参数文件/`--method` 名字表/属性层"的合法用法。
- **Correct（T3/桥）**：`anyhess`（`:277`）与 HEAD 逐字同；桥的 16 个字段与设计 §3.11.1 **逐字段一致**（含 `etot/gnorm/zp/temp/nimag`），顺序正确（vib 链 + `res` 写回之后、PRINTOUT 之前）；`htot/gtot = 总数 − 电子能` 与 `property.F90:44-48` 的 `etot+htot` 打印语义、以及 `main_freq` 容器的"热贡献"约定一致；`fres%allocate` 的 3n 与 `vib%modes/freq/rmass`（`modes.f90:300`）匹配，`deallocate` 有 `allocated` 守卫；**半修空间被结构性消掉**（套件侧唯一 `anyhess=.true.` 的路径就是桥）。`vib%energy` 的 `intent(out)` 抹除**真修好**（赋值在两次 `intent(out)` 调用之后，`tasks/vib.f90:272`，注释记录实测）。
- **Correct（守卫/状态位/R30·R21/越界）**：7 个套件 run type 全守卫、4 个原生出口全跳过（H-2 正确）；`lruntyp_flag` 的 select 覆盖全部 7 个 ⇒ 文案不会出现空旗标名；`set%xcontrol_supplied` 只在 `rdcontrol` 的 `case('opt')`（受 `do_mark`）与 `set_legacy` 6 个 opt 键置位（rc 通道 save/restore），CLI **不可能**置位（`set_legacy` 只经 `$set` 分支可达），只有 3 处引用、**不在** `write_set_opt`；核心层 0 改动、`--bhess` 未误改、无 3b 内容（无 `--cycles` 映射、无档位四轴、无 §3.9 文件、无 C1-C4）。`:1744` 的 `= 0`（flag 循环前）与 `:4304-4313` 的解析尾赋值仍在。
- **Correct（假绿）**：实施者自报的两处确实修好——守卫断言改钉**守卫自己的句子**（`does not execute the xcontrol $scan block: use --opt --method ancopt` / `runs the landscape suite, which does not support periodic ...`），`--ljson` 改为断言"`--opt` **不得**出现该 warning"**且**"原生出口**必须**出现"，两个方向都在。
- **Finding: MEDIUM（P1）** `main.F90:5072-5077`：`analytical hessian` 计时标签仍按**裸 runtyp 三元**（含 `p_run_ohess`）判定，而 `start_timing(5)` 只在 `:1304`（已被谓词抑制的**原生**块内）；`prtiming` 无条件写 stdout、timer 数组零初始化（`mctc_timings.f90:153-164`）⇒ 套件 `--ohess` 会多打一行 **`analytical hessian time: 0 d, 0 h, 0 min, 0.000 sec`**（`--verbose` 下 `0/0 = NaN`）。这是**遗留的第二个判据 + 输出中的不实声明**，且正是设计复核自己登记的 LOW-1（`16-w2-review-round4.md:132-137`，并在 `:174` 要求"落地后顺带补"）；读点表（15 行）与 `16-w2` 的 #16 建议**都没落**。无测试覆盖（`grep analytical hessian test/` = 0）。**最小修法（2 行）**：`:5072` 改读 `landscape_native_hessian_path(...)`，并在 `check_ohess_suite_once` 的 token 循环加 `("analytical hessian", 0)`（改前必红）。
- **Finding: LOW（P2）×4 / INFO×7**：见正文（静默死旋钮 `--opt <LEVEL>`/`--cycles`；设计点名的 3 条 H-2 反向测试未落地但覆盖等价；`--ohess` 失败后仍跑 vib 链；报告 §1.1 行号整表 +49 漂移；BC-4"唯一有意例外"不止 C7；`--help` 三处文本与行为矛盾等）。
- **明确回答：可以提交。** 条件：MEDIUM-1 落纸（首选本轮修，2 行），且 **3a 不得当作可发布版本**——`.xtboptok`/`xtbopt.log`/`compliance.dat`（+失败时的 `xtblast.xyz`）对 `--opt`/`--ohess` 在 3b 之前消失，而设计 §3.9 的补写是**强制**缓解。

---

# 44 — 阶段 3a 独立复核（只读，未运行命令）

> 对象：`docs/_simplify-recon/42-stage3a-impl.md`、工作树 delta（相对 `2b49ef8`：`src/prog/main.F90`、`src/set_module.f90`、`src/setparam.f90`、`src/landscape/types/results.f90`、`src/landscape/tasks/vib.f90`、`test/unit/{CMakeLists.txt,landscape_cli_check.py,meson.build}`、`docs/_simplify-recon/11-cli-redesign.md`，+42 号报告与 2 个未跟踪编排脚本）。
> 方法：静态读源码 + 行号核对（我**没有**运行任何命令；下文的"实测"均标注为父会话/实施者证据）。凡我给出的结论都尽量钉到 `file:line`。

## 0. 结论

| 项 | 判定 |
|---|---|
| 改派机制（T1-T7） | **正确且完整**，判据唯一 |
| 三条守卫（含 C7 作用域） | **正确**，H-2 无误报 |
| `--ohess` 链 + `fres` 桥 | **正确**，半修空间已结构性消除 |
| 可证伪性 | **合格**；两处自报假绿真修；发现 1 处未覆盖的真缺陷（MEDIUM-1） |
| 越界 | **零**（核心层 0、无 3b 内容） |
| 报告纪律 | 基本合格；1 条表述不实（BC-4"唯一例外"）、1 张表行号漂移、2 处任务书要求的过时注释未同步 |
| **能否提交 git** | **可以**（MEDIUM-1 建议同轮修；3a 不可发布，需 3b 的 §3.9） |

## 1. 攻击面 1：判据唯一性（本阶段最大设计风险）

我穷尽了 `p_run_l`、`p_run_opt`、`p_run_ohess`、`p_run_hess`、`p_run_bhess`、`anyopt`、`anyhess`、`runtyp`、`landscape_native_engine` 的全部读点，并逐个判断"是否该改读谓词"：

**已改（9 个 read point，全部正确）**
`:520` 三守卫 / `:1045` `--ljson` / `:1055` NOTICE / `:1069·1141·1157·1187·1206` 五处分派 / `:987` 原生 `anyopt` 块 / `:1291` T1 / `:1421` T2 / `:1454-1457` 原生 `xtbopt.xyz` 二次写 / `:5057` slot-3 计时标签。

**有意不改（逐个核对，理由成立）**
| 读点 | 内容 | 判定 |
|---|---|---|
| `:277` `anyhess` | 设计 T3 明写不动；容器"会不会被打印"的判据，与谁填无关 | ✔ |
| `:324` `anyopt` | `:328`/`:333` CPCM-X/PTB terminate（设计 R24 明写保持） | ✔ |
| `:477`/`:871`/`:1292`/`:1294`/`hessian.F90:151..446` | 全部只判 `p_run_bhess`（未改派） | ✔ |
| `:679` 参数文件选择 / `:1411` `main_geometry`（设计读点 #15） / `:1444` 属性文件 `write_energy` 的 hess 形参（= `anyhess` 同义） | 与"谁执行"无关 | ✔ |
| `:4325→4330` `case (p_run_lopt, p_run_opt, p_run_ohess)`、`:4312` `case (p_run_opt, p_run_ohess)` | `--method` 名字表按 **runtyp** 分派是设计 §4.7 的规矩（`--method` 不改 runtyp） | ✔ |
| `gfnff/calculator.f90:239` | 只决定 `gfnff_eg` 的 `minpr`（一笔内部 timer 打印） | ✔（但读点表若声称"穷尽"，应把它列为"有意不改"，见 INFO-5） |

**遗漏（MEDIUM-1）**：`:5072` 的 `analytical hessian` 计时标签（详见 §6）。它**是** `runtyp` 三元读者，且套件 `--ohess` 走它 ⇒ 读点表"按这张表搜一遍即可保证无遗漏"第二次被否证（第一次就是设计复核的 LOW-1）。

其余全仓核对：`grep runtyp src/landscape/` = **0 命中**（套件层完全没有第二套判据）；`src/setparam.f90:197-220` 的 `p_run_*` 只在 `set_module.f90` 赋值、`gfnff/calculator.f90:239`、`hessian.F90`（bhess）与 `main.F90` 出现。

## 2. 攻击面 2：`--ohess` 的 T1/T2/T3 与 `fres` 桥

1. **T1/T2**：`:1291`、`:1421` 都已换成 `landscape_native_hessian_path`；该函数对 `hess`/`bhess` 恒 `true`、对 `ohess` 取 `native_engine /= 0`、其余 `false`（`case default` 赋值）⇒ 与 HEAD 上 `--hess`/`--bhess` 的行为逐位同，套件 `--ohess` 两侧都抑制。✔
2. **T3 `anyhess` 真的没动**：`main.F90:277` 与 HEAD 逐字同（diff 未触及）✔。
3. **桥字段不遗漏**：核对设计给的 16 项，全部按设计写入（`n3true/linear/freq/rmass/hess/dipt/polt/etot/gnorm/htot/gtot/zp/temp/nimag`，`:1109-1131`）。`fres%grad` 未填但**无读者**（三个读者 = 属性文件 `write_energy`、`json.F90:102/111`、stdout `write_energy`，都不读 `grad`）。`fres%allocate` 给的长度 3n 与 `vib%freq/modes/rmass`（`modes.f90:300` 分配 3n）一致；`json.F90:295-336` 按 `n3true`（= 3n）索引 ⇒ 无越界。✔
4. **"减电子能"约定**：`property.F90:44-48` 打 `frqres%etot + frqres%htot`，而 `landscape_vib_result%enthalpy/gibbs` 是**总数**（`thermo.f90:173-174` 用 `energy + res%htot`）⇒ 桥 `enthalpy − energy` 得到**热贡献**，与原生容器（`main_freq` 填的热贡献）同义。`json.F90:102` 的 `gtot > 0` 门与原生同形（水：G 热校正 +0.002499 Eh > 0，父会话的 `-5.068045136132 − (−5.070544447744)` 可核）。✔
5. **半修空间**：枚举所有 `anyhess=.true.` 的路径——`hess`/`bhess`（原生块，`numhess` 填 fres）、`ohess`+原生出口（原生块填）、`ohess`+套件（桥填）——**没有第四条**。`--ohess --method <套件名>` 也走桥（`native_engine == 0`）。桥在 PRINTOUT 段之前、`res` 写回之后。✔
6. **`vib%energy` 的 `intent(out)` 抹除**：`landscape_vib_analysis` 的 `vib` 是 `intent(out)`（`modes.f90:127`）；赋值点 `tasks/vib.f90:262-272` 在 `landscape_vib_analysis` 与 `landscape_vib_thermo_output`（后者 `vib` 是 `inout`，`thermo.f90:109`）之后、`write_json` 之前 ⇒ 真修好；`result%vib = vib` 的类型无 `character` 组件，AGENTS §6.5 的 gfortran 缺陷不适用。✔
7. **新发现（LOW-2）**：两次 `run_landscape`（`:1081` opt 链、`:1102` vib 链）之间**没有** `env%checkpoint`；只有 `:1103`（vib 之后）与 `:1136` 两处。`env%error` 不中止 ⇒ opt 链失败（不收敛 / SCC 失败）时，**vib 链照样跑**：在未收敛几何上做 FD Hessian、写 `hessian`/`vibspectrum`、打频率表，然后靠 `:1136` 的 checkpoint exit 1。原生 `--ohess` 在同一情形下 `env%terminate`（`main.F90:1022-1026`；`environment.f90:266-292` 立即 `terminate(1)`）**先退出**、不跑 `main_freq`。⇒ 不是静默错数（退出码仍 1），代价是一次多余 Hessian + 一份未收敛几何的频率输出。最小修法 = 在 `:1096` 之前插一行 `call env%checkpoint("Landscape task terminated")`。

## 3. 攻击面 3：三条守卫的作用域与 `xcontrol_supplied`

- **作用域**：`landscape_is_suite_run` 覆盖 `{lopt,lscan,lts,lirc,lvib}` + `{opt,ohess}`(套件)；`:522-536` 的 `select case` 也覆盖这 7 个 ⇒ `lruntyp_flag` 永不为空。✔
- **H-2**：4 个原生出口 `native_engine ∈ {p_engine_rf,lbfgs,inertial,pbc_lbfgs} ≠ 0` ⇒ `effective_landscape_task` 原样返回 ⇒ 守卫全跳过；测试三条基线（scanblock/pbc/xcontrol 各一条 `--method ancopt`）逐条覆盖。✔
- **置位点**：`set_module.f90:813-825`（`case('opt')`，`do_mark` 守卫）+ `:2907/2923-2931`（6 个 legacy 键）。CLI 的 `--opt`/`--ohess`/`--cycles` 只调 `set_opt`（`main.F90:2136-2142` 等），**不经过**这两处 ⇒ 不置位。✔
- **rc 通道 save/restore**：`:852-863` 的 `$set` 分支用 `lsupplied` 保存/恢复；`case('opt')` 侧靠 `do_mark` 直接不置位（rc 只读一份，不需要恢复）。`set_legacy` 只被 `rdcontrol` 的 `$set` 分支当作 handler 传入（`grep "call set_legacy"` = 0）⇒ 不存在第三方调用置位。✔
- **不进 `write_set_opt`**：`grep xcontrol_supplied` = 声明 1（`setparam.f90:533`，在 `TSet` 内、紧邻先例 `randseed_set`）+ 写 6 + 读 1（`main.F90:552`）⇒ 无序列化点。✔
- **`.xtbrc` 判据**：`:411` 传 `from_input=.false.`，用户输入 `:340` 缺省 `.true.`；仓库根 `.xtbrc`（被跟踪）确实含 `$opt` 块（第 12 行）⇒ 不按文件名豁免、按来源豁免，与设计 §18.3 一致；`--input .xtbrc` 仍被守卫。✔

## 4. 攻击面 4：R30/R21

- `landscape_native_engine = 0` 在 flag 循环之前（`:1744`，紧跟一段赋值，其间无 `env%error`/`return`）✔；解析尾写它与 `set%opt_engine`（`:4304-4313`）✔；声明初值 `= 0`（`:246`）仍在（虽被 `intent(out)` 抹掉，但循环前那行才是保证）✔。
- `:1617`/`:788` 两个 `finalize_xtb(env, landscape_native_engine)` 调用点与 `:5032` 的新签名一致（`:788` 在早期失败路径上，`landscape_native_engine` 此时**已**被定义）✔。

## 5. 攻击面 5：可证伪性与假绿

- 注入落在**谓词/抑制本体**（14 条里 12 条是谓词或守卫本体；inj5 是 `anyhess` 本体、inj4/4b 是桥本体）✔。
- 自报的两处假绿**确实修好**：守卫断言不再用被 `[NOTICE]` 污染的裸子串（`:570-572`、`:3830-3834`）；`--ljson` 改为双向断言（`optalias` 断"不得出现 warning"、`optnative` 断"必须出现"）✔。
- **我未发现的第 3 处假绿**：`check_opt_alias_once` 的 `counters.n_steps` 比较在"两份文档都缺该键"时 `None == None` 通过（`read_json` 只保证文件存在）。建议改为断言键存在（INFO-4）。
- **反向用例真的会红**（推理，未运行）：`check_opt_native_exit` 对 4 个出口断言 `[NOTICE]` **不存在**、`writes nothing...` **存在**、无 `landscape_` json ⇒ H-2 式退化（把 `lancopt`/`fire` 判成套件）会同时打红 `optnative`；`u15-agree/u15-conflict`（`--opt --method lancopt` + `$opt` 块，期望 exit 0）会打红"守卫误报"型退化。
- **设计点名但未落地的反向测试（LOW-3）**：`landscape-guard-fire-no-scan`、`-guard-fire-no-opt`（设计 §4.7.1 表）、`-opt-native-nojson` 三个名字在 `test/unit/CMakeLists.txt` 中**不存在**；其等价覆盖由 `optnative` 的 NOTICE/warning 双向断言 + `check_opt_guard` 的 `ancopt`/`lancopt` 基线提供（`-guard-pbc-native`、`-opt-xcontrol-scope` 实际**已**落在新 mode 内）。报告只列 9 条新测试，**没有交代这个替换**——按验收口径（"§4.7.1 的 20 条全绿"）应当写明。

## 6. 攻击面 6：越界

- `watchdog_diff --stat` 的 8 个改文件 + 1 新报告：`src/type|xtb|mctc|param|io|disp|coulomb` **0 命中**（`setparam.f90`/`set_module.f90` 位于 `src/` 根，属允许范围）✔。
- 无 §3.9 的四个遗留文件、无 `--cycles` 映射（`:2136-2142` 原样）、无档位四轴（`:1070-1077` 只同步 `acc`/`etemp`，未动 `e_tol`/`max_steps`）、无 C1-C4、无 `man/`+`xhelp` 全文清理 ✔。
- `--bhess` 未误改：`hessian.F90` 的 bhess 分支原样，谓词对 bhess 恒 `true` ✔。

## 7. 攻击面 7：报告纪律

| 项 | 判定 | 证据 |
|---|---|---|
| 设计订正"保留原文 + 指针" | ✔ | `11-cli-redesign.md` 的 diff **只有插入**（+108/-0）：`[订正 R44]` 指针 3 处 + 新增 §18（6 小节），被证伪的行原文保留 |
| 残留风险如实登记 | ✔（但两处表述需收紧） | L1（rc 类）、L2（双 json）、L3（原生抑制范围）、L4（缓冲）、L5（md 种子）、L6（3b 清单）都在 |
| BC-4 的"唯一有意例外 = C7" | ✘ 不准确（INFO-1） | 至少还有 3 处**有意** stdout 文本偏离：`main.F90:540-543`（`$scan` 文案，任务书自己要求改）、`:546-550`（周期体系下 suite run type 由 `landscape_driver.f90:73-76` 改成守卫文案，设计 F3）、`:1046-1049`（`--ljson` warning 列表加 `or --opt`，影响 `--sp --ljson` 等原生运行）。报告 §5.2 的 11 个 fixture 不含这三种输入 ⇒ "这 11 个逐位不变"成立，但**措辞应限定**为"退出码/语义层面"。 |
| §1.1 行号可核 | ✘（LOW-4） | 交付文件实测：分派 `1069/1141/1157/1187/1206`（报告 §1.1 写 `1069/1092/1108/1138/1157` = 整表 +49）；参数文件 `679`（报告 672）；`case (p_run_lopt,p_run_opt,p_run_ohess)` `4330`（报告 §1/T6 写 4325）；slot-3 `5057`（报告 `5054`）；守卫块 `493-559`（`if` 在 520；报告 §1/T5 写 498-557）；桥 `1109-1131`（报告 §1/T4 写 1106-1130）。四个纯函数的 `4521/4546/4570/4591` **正确**。⇒ 属"快照过期"，不影响代码，但与"逐条可核"的纪律冲突，且 §1.1 与 §1 互相矛盾。 |
| 任务书要求的注释同步 | ✘ 部分（INFO-3） | `test/unit/CMakeLists.txt:227-229`（"the pre-existing `--opt`, whose geometry goes through `open_file`"）与 `test/unit/test_landscape_optimize_xtb.f90:110-113`（"obtained independently with `xtb water.xyz --gfn2 --opt`"）未更新；py 侧同型 docstring 已更新（`landscape_cli_check.py:1915-1919`）✔ |

## 8. 其余发现（逐条：位置 / 证据 / 最小修法）

**LOW（P2）**
- **LOW-1 静默死旋钮**：`--opt <LEVEL>`（`set%optset%optlev`）与 `--opt --cycles N`（`set%optset%maxoptcycle`，`main.F90:2136-2142`）在改派后**无任何读者**（`grep "optlev|maxoptcycle|optset" src/landscape/` = **1 命中且是注释**，`types/settings.f90:440`；分派只同步 `acc`/`etemp`）。⇒ `--opt tight` 等价于套件默认档、`--opt --cycles 50` 被静默丢弃（改派前两者由原生 ANCopt 消费）。任务书把映射划给 3b（报告 L6），但 L6 只写"四轴仍固定 5e-6/1.0/256"，**没有指出这是"用户给的键静默无效"**；设计 §3.5/§4.7.1 还点名了 `xtb/landscape-method-level-bridge`（该测试若在 3a 写出来会是**恒真**的）。最小修法：3a 不改代码，但在报告/设计登记这一条**静默**后果，并把 level 桥列为 3b 第一项。
- **LOW-3** 见 §5（设计点名的 3 条 H-2 反向测试未落地、替代覆盖未交代）。
- **LOW-4** 见 §7（§1.1 行号漂移）。
- **LOW-2** 见 §2.7（`--ohess` 缺 opt→vib 之间的 checkpoint）。

**INFO**
1. BC-4"唯一有意例外"应限定（§7）；建议在 42 号 §5.2 补一行枚举。
2. `--help` 文本与行为矛盾（3b 已登记，但清单需补全）：`xhelp.f90:270-272`（`--opt` = "call ancopt(3)"）、**`:776-777`**（`--ohess` = "on an ancopt(3) optimized geometry"）、`:299-300`（`--lopt` + `$scan` 指向 `--opt`，而 `--opt` 现在**拒收**该块）、**`:292-293`**（`--ljson` 的 run type 列表**不含 `--opt`**，与刚更新的 `main.F90:1048` 警告矛盾）。任务书的 DONT 只点名 `270-272,300`，请把 `292-293`、`776-777` 一并加进 3b。
3. `test/unit/CMakeLists.txt:227-229` 与 `test/unit/test_landscape_optimize_xtb.f90:110-113` 的过时注释（任务书要求同步）未更新。
4. `check_opt_alias_once` 的 `None == None` 弱断言（建议断言键存在）。
5. `gfnff/calculator.f90:239` 按裸 runtyp 决定 `optpr`：只影响 `gfnff_eg` 的内部 timer 打印，不是 suite/native 判据 ⇒ 可接受，但读点表要把它列为"有意不改"，否则"穷尽 grep"的表述不成立。
6. **3b 前不可发布**：`.xtboptok`/`xtbopt.log` 的写点在 `geoopt_driver.f90:112-113/183-186`（只经原生 `geometry_optimization` 到达），`xtblast.xyz` 在 `main.F90:1018-1026`（已被抑制）⇒ `--opt`/`--ohess` 在 3b 之前**丢这 3 个文件**（`compliance.dat` 同理）。设计 §3.9 的补写是**强制**缓解（决策 2），BC-3 只有在 3b 之后才无条件成立。3a 提交可以，发布不行。
7. 工作树根有 2 个未跟踪编排脚本（`stage3a-workflow.js`、`stage3a-val-workflow.js`）——父会话 scratch，提交时不要 `git add`。

## 9. 需运行验证（我做不了；建议父会话逐条跑，`OMP_NUM_THREADS=1`，只 `-R landscape`）

1. **MEDIUM-1 实测**：`xtb water.xyz --gfn2 --ohess --norestart` 的 stdout 应含 `analytical hessian time:` **恰好一次**且为 `0.000 sec`；`--ohess --method ancopt` 同行应为**非零**。再跑一次 `--verbose`，确认是否出现 `ratio c/w:` 的 `NaN`。修法验证：把 `:5072` 换成谓词后该行**消失**，并在 `check_ohess_suite_once` 加 `("analytical hessian", 0)`（加 token 后未修 ⇒ 红）。
2. **LOW-2 实测**：`--ohess --lopt-max-steps 1`（或任何使 opt 链不收敛的输入）⇒ 预期 exit 1，但 `hessian`/`vibspectrum` **仍被写出**且 stdout 有频率表（原生 `--ohess` 同情形不写）。
3. **LOW-1 实测**：`--opt --ljson --lopt-max-steps …` 无关；用 `--opt normal` vs `--opt tight`（同水、`--ljson`）比对 `counters.n_steps` 与末能量**逐位同**；`--opt --cycles 4` 与不给我者逐位同。
4. 复跑 9 条新测试 + `ctest -N -R landscape`（应 136）+ 重名检查 + 集合 S；复跑 14 条注入（含 `sha256` 还原断言）与 BC-4 的 11 个 fixture `cmp`。
5. `xtb --help`（`xhelp.f90`）实际输出，确认 §8-INFO-2 的四处文本。
6. `--ohess --ljson` 目录列表（确认两个 json，L2 登记属实）。

## 10. 最终裁定

- **CRITICAL 0 / HIGH 0 / MEDIUM 1 / LOW 4 / INFO 7。**
- **接受（有条件）**：改派机制、三条守卫、`fres` 桥与抑制集合实现正确、判据唯一（1 处遗漏见 MEDIUM-1）、零越界、注入与两处假绿修法经得起核对。
- **能否提交 git：可以。** 条件：
  1) MEDIUM-1 落纸——**首选本轮修**（`:5072` 换谓词 + 1 条 token 断言，2 行），若不带则必须在 42 号/3b 清单里写明"`--ohess` 会打印一行 0.000 秒的 `analytical hessian`"；
  2) 42 号补两处订正（§5.2 的"唯一有意例外"限定为退出码/语义；§1.1 行号整表刷新）与 INFO-3 的两处注释；
  3) 提交信息/报告注明"**3a 不可发布**：等 3b 落 §3.9 的文件契约（`.xtboptok`/`xtbopt.log`/`compliance.dat`/`xtblast.xyz`）与 §3.5 的档位桥（`--opt <LEVEL>`/`--cycles` 现在对套件静默无效）"。