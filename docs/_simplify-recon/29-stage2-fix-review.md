## 29 — 阶段 2 修复轮独立复核（read-only，未执行任何命令）

**结论：接受（accept）。** 无 CRITICAL / HIGH / MEDIUM；**2 条 LOW + 7 条 INFO**，全部落在"报告文本/证据表述"层，**无代码缺陷、无边界越界**。

- **阶段 2 现在可以提交 git 吗？→ 可以。** diff 只有 10 个文件（2 个套件源 + `main.F90` + `xhelp.f90` + `set_module.f90` + 4 个测试/注册 + 1 个设计文档）；核心层（`src/type|xtb|mctc|param|io|disp|coulomb`）**0 改动**；无旗标改名；`--opt`/`--ohess` 分派未动（只保留已登记的 R39 过渡拒绝）；无 §3.8 守卫、无 §3.9 文件、无 §3.10 档位。
- **阶段 2 可以宣称完成吗？→ 可以（在 R40 已把 §6.3 缺口旗标移出阶段 2 之后）。** 27 号的两项阻塞已闭合：M1 → `xtb/landscape-method-table` 逐名可证伪；M2 → R40/R41 登记 + §6.4/§9.1 的 `--cycles` 归属统一 + §9.2 为不存在旗标列的行标"未实现"。
- **阶段 3 可以开始吗？→ 可以。** 起点仍是 R39 过渡拒绝的移除 + `landscape_native_engine` 落读点 + §4.7.1 的阶段 3 运行时断言（T7 已把边界写清）；阶段 3 不得吞掉 §6.3（阶段 2b）。
- T1 已修（4+1 个"跑 xtb"调用点全部 `text=False` + `decode(errors='replace')`，断言未改、无恒真化）；残留 `text=True` 5 处均为**非 xtb 程序**，但报告 §1.3 末句与自己的表矛盾 → **LOW-2**。
- T2 已定位、**未修**：`src/relaxation_engine.f90:615/779`（`molopt = mol` / `mol = molopt`）对 `:311/:379`（`%copy`），我独立核对了这 4 行；该文件不在 diff ⇒ "与本次改动无关"成立。
- T3 18/18 逐名有可证伪证据（opt 里程碑、ts/irc 里程碑 **+** 产物方法行），一次表错位突变 38 行**逐名点名**；不是 18 次独立突变 → INFO-1；**未见恒真断言**。
- T4/T6/T7/T8 的登记与**留痕**到位（R40/R41、§6.3 块/§6.4/§9.1/§9.2、`main.F90:4113-4146` 注释、`25-stage2-impl.md:52-69` 订正块、测试 docstring）。
- T5 真统一（副作用移到解析尾、对**最终值**只施加一次）；测试断言两路里程碑 `(neb)` + 无 climbing + `p2.path.xyz`/`p2.xtbts.xyz` 逐位同。
- T9 实质达标（脚本覆盖全部非 stdout 文件 + stdout diff；我抽查 `xtbscan.log`/`irc.log` 逐字同、version 串一致），但 stdout 分类数字与"唯一新增行"不成立 → **LOW-1**。
- T10 只在"同时给出且不一致"告警（5 用例：一致/只 CLI/只 xcontrol/冲突/重复 xcontrol）；`--strict` 不会把它升级（`env%strict` 在 `rdcontrol` 之后才设，`main.F90:614-615`）；额外覆盖"重复 `$opt engine=`" → INFO-3。
- 我无法执行：121/121、回归 12/12、集合 S、重名、T3 的突变红、`methodtable` 的 0.90 s 耗时（该耗时与 27 次运行不相称 → INFO-2，请补 CTest 计时行）。

---

# 29 — 阶段 2 修复轮复核报告（对象：`28-stage2-fix-report.md` T1..T10）

**复核者**：独立 read-only 复核（fresh context，**未执行任何命令**，未修改任何文件）。
**对象**：`docs/_simplify-recon/28-stage2-fix-report.md`、`27-stage2-review.md`、`25-stage2-impl.md`、`11-cli-redesign.md` 的实际改动，以及 `src/`、`test/` 的工作区 delta（HEAD = `f5b070f` + 未提交阶段 2 + 本轮修复）。
**方法**：逐文件走读 `watchdog_diff`（10 个文件，+1406/−58）、逐条核对 T1..T10 的断言与实现点、逐个判断新/改测试的可证伪性、并直接读取**外部证据产物**（`/tmp/t9/bc4-flags.sh` 与 `/tmp/t9/run/*`）。
**证据限制**：不能构建、不能跑 ctest/xtb；凡"实测"数字我标注为引用 28/26/25 号或来自 `/tmp/t9/run/` 的产物；产物可读的部分我**自己核对**。

## 0. 结论

**接受。** 本轮把 27 号的两项 MEDIUM、5 条 LOW 与 INFO-1 全部闭合，且闭合方式**可证伪**（新 target + 反向突变 + 可读产物）。没有发现代码级缺陷、没有边界越界、没有恒真断言、没有把断言放宽来"消除红"。剩下的 2 条 LOW 是**报告证据表述**错误（T9 的 stdout 分类、T1 的 `text=True` 残留句），修文档即可，不阻塞提交。

## 1. 逐条判定表

| 项 | 判定 | 依据（file:line / 证据） |
|---|---|---|
| **T1** 测试框架容错解码 | **已修复** | `test/unit/landscape_cli_check.py:72-96`（`decode` + `run`，`capture_output=True, text=False`）、`:1996-1999`、`:2313-2316`、`:2495-2498`；`test/unit/landscape_e2e_check.py:151-162`（`text=True, errors="replace"`）。断言全部保持 token/退出码语义，无一处改为"对替换后文本放宽" |
| **T2** 既有缺陷定位（不修） | **已定位、未修、判别证据成立** | `src/relaxation_engine.f90:615`（`molopt = mol`）与 `:779`（`mol = molopt`）—— 我独立核对了这两行与同族 `:311/:379` 的 `call molopt%copy(mol)` / `call mol%copy(molopt)`；入口 `src/geoopt_driver.f90:155-158`（`p_engine_lbfgs → l_ancopt`）。**该文件不在 diff** ⇒ "非本次引入"结构成立 |
| **T3** 18 名逐名生效证据 | **已修复** | `test/unit/landscape_cli_check.py:2460-2685`（`check_method_table`，27 次运行）；里程碑来源 `tasks/opt.f90:108-109`、`tasks/ts.f90:163-164`、`tasks/irc.f90:159-160`；产物方法行 `ts.f90:685-686`、`irc.f90:996-997`；注册 `test/unit/CMakeLists.txt:3406-3412` + `test/unit/meson.build`（`test('landscape method table' …)`）。断言基于**解析后的枚举** ⇒ 名字表错位即红（突变证据见 28 §3.2） |
| **T4** 设计登记 + 自相矛盾 | **已修复** | `11-cli-redesign.md:71-72`（R40/R41）、`:1848-1853`（§6.3 落地阶段块，逐条 `grep -c`）、`:1871`（§6.4 `--cycles` → **§9.1 阶段 3**）、`:2137-2144`（§9.1 阶段 2 改写）、`:2203-2208`（§9.2 为不存在旗标列的行标"未实现"） |
| **T5** 重复旗标别名等价 | **已修复** | 副作用搬到 `src/prog/main.F90:4047-4060`（flag 循环之后、对**最终值**一次）；setter 只存值并留注释 `:4315-4320`；测试 `landscape_cli_check.py:2252-2279`（`repeat-band-flag`/`-method` 里程碑 `(neb)` + 无 climbing + 产物逐位同；`repeat-band-explicit-climb` 反向） |
| **T6** 引证订正 + 留痕 | **已修复（留痕在位）** | `src/prog/main.F90:4113-4146` 注释写明**两条差异**并留痕"此前的引证不准确"；`25-stage2-impl.md:52-69` 表头 + `lancopt` 行订正为 `set_module.f90:1898-1901` + 【引证订正·留痕】块。核对 `set_module.f90:1898`=`rf|ancopt`、`:1899`=`lbfgs|l-ancopt`、`:1900`=`pbc_lbfgs`、`:1901`=`inertial|fire` ⇒ 订正后行号**正确** |
| **T7** `landscape_native_engine` 边界登记 | **已登记** | 测试 docstring `landscape_cli_check.py:2294-2311`；`11-cli-redesign.md:1534` 与 `:2196`（拆成 (a) 今天可证伪的 pin 行 / (b) 阶段 3 才可测的读点） |
| **T8** scan 内层方法可观测 | **已修复** | `src/landscape/tasks/scan.f90:124-135`（仅 `relaxed` 回显生效内层器；rigid 静默）；`xtbscan.log` 格式**未改**；测试 `landscape_cli_check.py:2639-2679`（回显名 + rigid 不回显 + `cg`/`sd` 的 `xtbscan.log` 必须与 `lbfgs` 不同） |
| **T9** 4 个旧旗标 BC-4 基线 | **实质已做，报告表述有误** | 脚本 `/tmp/t9/bc4-flags.sh`（5 命令 × 2 二进制、收集**全部非 stdout 文件** + 退出码 + stdout diff）；产物 `/tmp/t9/run/{optbfgs,scancg,scanCG,tsdimer,ircgs}-{base,new}/`。我抽查 `scancg/xtbscan.log` 与 `ircgs/irc.log` base↔new **逐字相同**，两边 version 串同为 `6.7.1 (f5b070f…)`。**但** stdout 分类数字对不上 → **LOW-1** |
| **T10** U15 `[WARNING]` | **已实现，最小且（除警告外）行为中性** | `src/set_module.f90:1786-1787`（+1 声明）、`:1886-1916`（注释 + `.not.allocated` 的 **else 分支**，值保留、仅告警）；测试 `landscape_cli_check.py:2415-2455`（5 用例）。可达性核对：`rdcontrol`(`main.F90:340`) 早于 `initDefaults`(`:684`) 与 `:942` 的 `deallocate` ⇒ else 分支只在 `--method <native>` 或重复 `$opt engine=` 时命中；`--strict` 不升级（`env%strict` 在 `:615` 才设） |

## 2. 边界核对（任务 8，逐文件）

| 文件 | 改动 | 判定 |
|---|---|---|
| `src/landscape/types/settings.f90` | +24（阶段 2 的 4 个 allocatable `*_source`，本轮 0 改动） | 套件内、无阈值/枚举/SCF 改动 ✔ |
| `src/prog/main.F90` | +465/−…（`--method` case、4 个旧 case 改调共享 setter、解析尾归一、climbing 副作用、5 个新过程） | 唯一允许 `use xtb_landscape_*` 的文件 ✔；**无 §3.8 守卫、无 §3.10 档位、无旗标改名**（旧错误文本逐字保留：`Unknown landscape minimisation algorithm '…'`、`… scan minimiser`、`… transition state method`、`… IRC method`、`The --l*-… flag requires …`）✔ |
| `src/landscape/tasks/scan.f90` | +15（T8 回显） | 套件内 ✔ |
| `src/set_module.f90` | +23（T10，父会话已裁定允许） | 非核心层 ✔；**除告警外无行为变更**（值保留、未知拼写仍静默不设） |
| `src/xhelp.f90` | +14（阶段 2 的 `--method NAME` 帮助） | 集合 S 门槛所需 ✔ |
| `test/unit/{CMakeLists.txt,meson.build,landscape_cli_check.py,landscape_e2e_check.py}` | 两侧同步注册 + 检查器 | ✔（新 target 名 `xtb/landscape-method-table` 与既有 `…-method`/`…-method-native` 三名字互不相同，无重名） |
| `docs/_simplify-recon/11-cli-redesign.md` | +56（R40/R41/§6.3/§6.4/§9.1/§9.2/§4.7.1） | 文档 ✔ |
| `src/type|xtb|mctc|param|io|disp|coulomb`、`src/landscape/CMakeLists.txt|meson.build` | **0** | 无越界、无新源文件需注册 ✔ |

**阶段 3 内容核对**：`--opt`/`--ohess` 仍走 `if (anyopt)` 原生块；唯一相关新增是 `main.F90:4029-4037` 的**过渡期响亮拒绝**（R39 已登记、阶段 3 移除）；`landscape_native_engine` 在 `xtbMain` 仍**无读点**（只 `:3977` 写进 `set%opt_engine`）。⇒ **零阶段 3 越界。**

## 3. 新/改测试的逐条可证伪性（任务 9）

| 测试 | 把对应逻辑故意写错，会红吗 | 依据 |
|---|---|---|
| `methodtable` 的 `table-opt-<name>` | **红** | 里程碑由 `landscape_opt_algorithm_name(lset%algorithm)` 打印；名字表错位 ⇒ 打印别的名字（28 §3.2 实测 38 行） |
| `table-ts-<name>`（里程碑 + `nm.xtbts.log`） | **红** | 两处都由解析后的枚举打印（`ts.f90:163/685`）；band 名另有 climbing 阶段断言（`neb` 必须**没有**） |
| `table-irc-<name>`（里程碑 + `nm.irc.log`） | **红** | `irc.f90:159/996` |
| `table-scan-auto` / `table-irc-auto` | **红** | 与不给 `--method` 的产物逐位比对；删 `auto` no-op 分支 ⇒ 走名字查找 ⇒ exit≠0 |
| `table-scan-inner-{lbfgs,cg,sd}`（回显） | **红** | 回显写死 ⇒ 断言名不符（28 §T8 实测） |
| `table-scan-inner-{cg,sd}`（产物必须不同） | **红** | 让 `relax_scan` 恒用某器 ⇒ 三者同 ⇒ 两条断言同时红（28 §T8 实测）。**这是"生效"而非"读取"的断言**，写法正确 |
| `table-scan-rigid`（不回显） | **红** | 去掉 mode 判断 ⇒ 回显出现 ⇒ 红 |
| `repeat-band-flag` / `-method` | **红** | 副作用搬回 setter ⇒ 被丢弃的 `cineb` 仍 ignite（28 §T5 实测）；两路产物逐位同是**分派**断言 |
| `u15-*`（5 例） | **红** | 把 else 分支改 `continue` ⇒ `u15-conflict` 红（28 §T10 实测）；`u15-agree`/`-cli-only`/`-xcontrol-only` 反向钉住"不该告警" |
| `native-*`（7 拼写 + 顺序 + 501 原子） | **红** | token 反转（25 号 M1/M2 实测）；`native-big` 对 `set%opt_engine = landscape_native_engine` 可证伪 |
| T1 的 `decode` | **红** | 改回严格解码 ⇒ `UnicodeDecodeError`（28 §1.2 实测，位置 15840→15785→16046 变化） |

**未见恒真断言**：`inspect`/`expect_milestone` 同时要求退出码、里程碑与产物 token；`identical` 读字节且文件缺失即抛异常；T7 明确声明"本构建不声称覆盖阶段 3 读点"，没有拿恒真断言充数。

## 4. 发现清单

**CRITICAL**：无。
**HIGH**：无。
**MEDIUM**：无。

### LOW-1（报告证据表述）：T9 的 stdout 分类与"唯一新增行"不成立
- **位置**：`28-stage2-fix-report.md` §T9 的两张表；产物 `/tmp/t9/run/scancg.stdout.diff`、`/tmp/t9/run/scanCG.stdout.diff`。
- **证据**：`scancg.stdout.diff` 共 39 条变更行（与报告一致），但除 `215a216  inner minimiser: cg` 外**还有** `247d247` / `248a249` —— `normal termination of xtb` 与轨道能量表首行的**相对位置**变了（两个输出流的缓冲区交错）。报告写"唯一 stdout 新增行 = T8 的回显"、分类为"28 噪声 + 1 其他"，而 39 ≠ 29；`scanCG` 同样（31 ≠ 25）。逐类可复算：时间戳/路径/种子/计时/墙钟 = 36，其他 = 3（1 回显 + 2 交错）。
- **最小修法**：重跑分类脚本，把"其他"列改成**逐行列出**；并用**同一二进制跑两次**（base↔base）证明该交错与 T8 无关（不能排除"新增一行改变了缓冲区边界"的可能，这一点必须实测，本项目已 4 次被"静态结论"打脸）。
- **影响**：不影响 BC-4 结论（文件级 `cmp` 与我的抽查都支持"全部输出文件逐位同"）。

### LOW-2（报告自相矛盾）：`text=True` 残留句
- **位置**：`28-stage2-fix-report.md` §1.3 末句"全仓 `grep -rn "text=True" test/` 现在只剩 `landscape_e2e_check.py:155`"。
- **证据**：`grep` 实测残留 5 处：`landscape_e2e_check.py:736`、`:742`（`landscape_tester` 单元测试二进制）、`:1021`、`:1023`、`:1028`（`python3 -c`）。同表上一行已把它们列为"否/不改"，**表与末句互相矛盾**。
- **判定**：这 5 处都不是被测程序 xtb（不打印 xtb 的格式化 dump），风险低；但末句是错的。最小修法：订正末句；顺手把 `:736/:742` 也改成 `errors="replace"`（同族一致性，1 行 ×2）。

### INFO-1（T3 的突变粒度）
要求是"逐个反向突变"，实际是**一次表整体错位**（三张表各自 derangement）。因每个名字的映射都被改错、且 FAIL 文本**逐名点名**（38 行），证据强度满足"每个名字有能证伪它的突变"，但不是 18 次独立突变。建议在 §3.2 明说这一点（避免后人误读为 18 次实验）。

### INFO-2（耗时数字不可核）
28 §3.1 称 `methodtable` "耗时实测 **0.90 s**（**27 次运行**：6 opt + 3 ts 单端 + 3 band + 2 弦 + 1 irc 准备 + 4 irc + 2 scan-auto + 2 irc-auto + 3 scan 内层 + 1 rigid）"。我按代码复算运行数 = **27 ✔**，但 27 次含 3 次 5-image band 与 2 次 growing-string、4 次 IRC 的 GFN2 任务不可能 0.90 s。请补 `ctest -R landscape-method-table` 的 `Passed x.xx sec` 行（这是"命令+期望+实际"纪律的应有形态）。

### INFO-3（T10 的范围外延，已登记，可接受）
else 分支**也**对"同一 `$opt` 块重复给不同 `engine=`"告警（原先是静默丢弃）。这是**既有输入路径**的 stdout 变更（此前 exit 0 且无警告），28 已登记 + 单独用例；仓库内没有该形状的既有 fixture（`grep "engine=" test/` 只命中新加的 3 个控制文件），`--strict` 不会升级（`main.F90:614-615` 在 `rdcontrol` 之后）。若上级坚持严格照 T10 字面（只 `--method` 与 xcontrol 冲突），可在 else 分支加"仅当 `--method` 给出过"的条件；**我倾向保留现状**（"绝不静默覆盖"是项目原则）。

### INFO-4（操作注意）：`/tmp/xtb-land/build` 现在是"过期二进制"
父会话最初看到的 `xtb/landscape-method-native` 红是**修复前脚本**的解码错误；现在该目录红是因为其二进制**早于** `set_module.f90` 的 U15 告警（共享脚本来自源码）。⇒ 该目录不能再用作证据（也不许重建，按纪律）；不要把它记成代码缺陷。T1 的稳定性证据应以 `p2` 的 5/5 + 冻结二进制上 3×7 无解码错误为准（28 §1.1 已如此呈现）。

### INFO-5（残留的语义抖动面，建议登记）
`errors='replace'` 只消除**解码**失败，不消除"垃圾字节恰好落在被断言 token 上"的可能。今天风险有界：非法字节出现在 L-ANCopt 的**符号列**（`final structure:`/Multipole/Wiberg/`xtbopt.xyz`），而 `landscape-method-native` 的 L-ANCopt 用例跑**水**（0 非法字节），501 原子用例用 `ancopt`/RF（干净）。建议在 28 §T2/§13 加一句"若将来把 L-ANCopt 与大体系配对，token 断言可能被垃圾字节命中"。

### INFO-6（T2 的独立性证据依赖执行）
"`f5b070f` 的二进制在 `$opt engine=lbfgs` 下同样损坏"是**执行依赖**的证据，我只能静态确认该代码路径（`relaxation_engine.f90` 的 `l_ancopt`、`set_module.f90` 的 `engine=lbfgs`）**不在本轮 diff 内**。建议保留那次实验的原始 stdout/`xtbopt.xyz` 十六进制片段作为附录（当前报告只有描述）。

### INFO-7（文档措辞）：`25-stage2-impl.md:52`
该行仍以"**别名逐字取自** xcontrol 的 `$opt engine=` 取值表 `set_module.f90:1898-1901`"开头，随后括注"旧稿写'逐字取自…'**不准确**"——留痕已在（下方订正块完整），但句子本身仍自相矛盾。建议改为"取值域参照…（**两条差异见下**）"。

### INFO-8（27 号 INFO-2..INFO-5 无处置记录）
28 §13 只登记了 INFO-6。27 的 INFO-2（`auto` 只能经 `--method` 给出）、INFO-3（`--lirc --method gs` 对 D2 banner 抑制无断言）、INFO-4（`man/` 无 `--method`）、INFO-5（无任务时的消息未点名 `--ohess`，`main.F90:4040-4041` 现在仍只点名 `--opt`）**没有 disposition 行**。父会话本轮只要求 INFO-1，故不算未完成；建议在 28 §13 补一张"其余 INFO → 接受/推迟"表，避免下一阶段"忘记"。

## 5. 零覆盖 / 未验证清单（单列）

1. **6 个 opt 名只有"里程碑 + 产物存在"两级证据**（无任何产物携带方法名；`sd`/`cg` 在 GFN2 水上轨迹逐字节相同）——28 §3.3 已**如实登记**，非隐瞒。
2. **`landscape_native_engine` 的阶段 3 读点**：本构建不存在 ⇒ 不可测（已登记 T7）。
3. **meson 端到端未执行**（环境无 meson/ninja）；只做了两侧名字 `uniq -d` 与脚本本体直跑。
4. **T9 的文件级 `cmp` 结论**：产物在盘上，我抽查了 2 个文件 + version 串；**全量重跑**（`/tmp/t9/bc4-flags.sh`）是残余验证项。
5. **121/121、回归 12/12、集合 S 差集 0、重名空、5 组突变红→绿**：全部依赖父会话自证，我无法执行（方法学与断言设计已逐条核对，未发现自相矛盾）。
6. **`--method` + xcontrol `$set runtyp=`（无 CLI 任务旗标）** 的边角仍未验证（27 INFO 遗留）。
7. **T10 的 else 分支在 `--pbc`/GFN-FF 周期路径**：静态上 `main.F90:942` 先 `deallocate` ⇒ 走 if 分支不告警；未实测（若 BC-4 的 `--pbc` 命令复跑即可顺带覆盖）。

## 6. 请上级运行/补齐的命令（我无法执行）

```bash
REPO=/home/owenchan/work_path/coding/fortran/xtb
# 1) 门槛（期望 121/121、12/12、空、0）
OMP_NUM_THREADS=1 XTBPATH=$REPO ctest --test-dir /tmp/xtb-p2/build -R landscape
OMP_NUM_THREADS=1 XTBPATH=$REPO ctest --test-dir /tmp/xtb-p2/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
ctest --test-dir /tmp/xtb-p2/build -N -R landscape | grep "Total Tests"
grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d
grep -oE "test\('[^']+'"     test/unit/meson.build   | sort | uniq -d
python3 test/unit/landscape_help_check.py src/prog/main.F90 src/xhelp.f90
# 2) INFO-2：贴出计时行（不是 0.90 s）
ctest --test-dir /tmp/xtb-p2/build -R landscape-method-table -V | tail -5
# 3) LOW-1：证明 stdout 的 `normal termination of xtb` 交错与 T8 无关（base 跑两次）
#    + 重跑分类，逐行列出"其他"类
# 4) T1 稳定性：连续 3 次
OMP_NUM_THREADS=1 XTBPATH=$REPO ctest --test-dir /tmp/xtb-p2/build -R xtb/landscape-method-native
# 5) T9 全量重跑（残余验证）
/tmp/t9/bc4-flags.sh
```

## 7. 报告纪律评价（任务 10）

总体**可核性好**：28 号每条处置都带命令、期望、实测输出片段与 `file:line`；抽查引证**全部对得上**（`relaxation_engine.f90:615/779`、`main.F90:4047-4060`、`4315-4320`、`set_module.f90:1898-1901`、`ts.f90:685`、`irc.f90:996`、`landscape_cli_check.py:72/1966/2282/2460/2415-2455`）。不足即 LOW-1（T9 分类数字与"唯一"表述）、LOW-2（`text=True` 末句）、INFO-2（耗时数字），都是"证据表述"而非"事实虚构"。

---