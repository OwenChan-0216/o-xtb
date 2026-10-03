## Review — 阶段 1 最终微修（`a845def` + 未提交工作树）

**结论：有条件接受（0 CRITICAL / 0 HIGH / 1 MEDIUM / 2 LOW / 5 INFO）。代码可提交；文档计数口径需先补 4 处。**

| 裁定 | 判定 | 关键证据 |
|---|---|---|
| 1 §17.1 入册 C8 | **部分落地 → MEDIUM** | §10 C8 条、§10 汇总行 `A 3+B 0+C 8+D 1+E 1+F 4+G 1 = 18`、§10 末 R38 订正、§17.1 R38 行、修订记录 `R1..R38` 均存在；**但 §2 概述行、§16.9、§12/§16.8 的 U17 行仍写 17 / “候选 C8”** |
| 2 D4 无代码变更 | **已落地** | `11:2006` D 清单含 R38 注、`11:2012-2019` 理由段、`11:2862/2867` §17.3 标题+正文；`18-*.md:367` 与 `21 §7.5` 仍留“未实施/待裁定”旧措辞（历史记录，未加 R38 指针） |
| 3 5 处归一 + 单测 + 突变 | **已落地（1 处形式偏差）** | 5 处全部改用 `landscape_lowercase`（`scan.f90:143`、`ts.f90:638`、`vib.f90:147`、`prfo.f90:958`、`dimer.f90:428`）；全仓 `src/landscape` 无残留字面比较；5 条用例均在册；**ts 只测新建谓词，调用点回退不会变红** |
| 4 IRC 生效 source 打印 | **已落地** | `irc.f90:174-175` 与 opt/sp/scan/ts/vib **逐字同格式**（`'(1x,a,a)'` + `"Hessian source:           "`），位置在 `restart policy:` 后；默认打+显式也给；`require` 3 条路线 + `lirchessian` 组；**不污染 `--ljson`** |

**越界检查：全清。** 无 `--method`（`grep` main.F90 = 0）；核心层（`src/type|xtb|mctc|param|io|disp|coulomb`）0 改动；`select_runtyp` 只在首次选择调 `set_runtyp`、冲突只 `env%error`（runtyp 语义与 `--opt`/`--ohess` 分派未动）；630/931-965/1156/1282 四处仍是原生代码（未落 hunk）；旗标名未改。

**零覆盖清单最终判定：R1、R2 确已关闭（可核）；剩 R3/R4/R5 理由成立（`spring_expo` 在 `test/` 0 命中；`ts.f90:180` 对 band 方法确实多打一行而 `prfo.f90:780-781` 直接 return；`f4.2` 溢出仅库入口可达）。**
唯一未真正闭合的是 **ts 的“接线”**（见 LOW-1）。

**阶段 1 可否提交：可以（代码无阻塞项）。** 建议提交前先改 §2/§16.9/U17 三处计数（纯文档 5 分钟），否则提交里留下“18 vs 17 / 候选 C8 已被占用”的自相矛盾。
**阶段 2 可否开始：可以。** 裁定 3 消除的正是“归一约定两套”的潜在陷阱，`--method` 新入口不会再撞上它；无遗留依赖。

### 需运行验证（我无法执行）
1. `OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p1/build -R landscape` → 期望 **118/118**；本轮无新 `add_test`（新覆盖都在既有目标内）⇒ **父会话的“从 118 增加”门槛按字面未满足**，请确认可接受。
2. 5 条新用例：`cd /tmp/xtb-p1/build/test/unit && OMP_NUM_THREADS=1 XTBPATH=<repo> ./xtb-tester landscape-{scan,saddle,vib}` 后 `grep -E "scan-task-mode-case|can-tighten|init-mode-case|axis-case|vib-hessian-case"`。
3. `python3 test/unit/landscape_cli_check.py echo <exe> <landscape_hcn.xyz> <dir> lirc`（须含 `Hessian source:           numerical` ×2 与 `model` ×1）与 `... enumcase <exe> <h2o> <dir> <hcn>`（10 组）。
4. BC-4 重跑 + `version.fh` 还原；6 个反向突变若需**仓库内可复现**，报告应补 `file: old → new` 逐条（22 §3.3 只给了消息，未给替换串）。

### 完整报告正文（父会话落盘 `docs/_simplify-recon/23-stage1-final-review.md`）

**CRITICAL / HIGH：无。**

**MEDIUM-1（文档，裁定 1 未“全部口径”同步）**
位置：`docs/_simplify-recon/11-cli-redesign.md:89`（§2 概述行结尾 `R36…= 17 条`）、`:2818`（§16.9 `破坏性计数：R36 后为 17 条（A 3+B 0+C 7+…）`）、`:2820`（`若采纳 U17 → 17`）、`:2423`（§12 U17 行 `候选 C8（计数 16→17）`）、`:2812`（§16.8 U17 行同）、`13-cli-redesign-revision.md:65/85`（历史文档，优先级更低）。
证据：`11:2357` 权威汇总已是 18、`:2237` R38 补丁行、`:2851` §17.1 R38 行、`:69` 修订记录 R38 行、`:26` 标题 `R1..R38`、`:2006/2012/2862/2867` D4 均已改；唯独上述 4 处仍是 17，且 U17 行仍称“候选 C8”（`:2368` 只订正了 §10 那一处）。
影响：`22-stage1-final-report.md:16` 与 `21 §9` 的“**计数口径全部更新**”不成立（其括号里只列了 §10 三处 + §17.1 + 修订记录）。
最小修法：按 R38 口径改这 4 行为 `18`，并把两处 U17 行改成“U17 若采纳只能是 C9（当前 18）”。

**LOW-1（测试强度，裁定 3 的 ts 一处形式偏差）**
位置：`test/unit/test_landscape_saddle.f90:995-1016`（`ts-can-tighten-case`）对 `src/landscape/tasks/ts.f90:638` 的新公开谓词；生产接线在 `ts.f90:450`。
证据：其余 4 处都经**生产入口**（`landscape_scan` 任务、`landscape_vib` 任务、`landscape_saddle_optimize`、`landscape_dimer_initial_axis`）用大写 settings 触达；ts 这条只调用谓词。把 `ts.f90:450` 回退成内联 `trim(settings%hessian_source) == 'numerical'`（谓词留在模块里）⇒ 该用例仍绿，而陷阱复活。父会话要求的形式（“以大写构造 settings 调用，断言与全小写结果相同”）在 ts 处未逐字满足。
最小修法：在零覆盖清单里把“曲率带门的接线”登记为新的可证伪缺口，或给 `--lts-hessian NUMERICAL` + 真band命中加一条 CLI 断言（成本高）。判为 report-only。

**LOW-2（报告可复现性）**
位置：`22-*.md` §3.3（5 处突变）。
证据：只给 `ctest` 输出与 `mutrun.sh` 用法，未给每处的 `old → new` 串；§4.3 给了（好），§3.3 没给。落盘脚本在 `/tmp/p1f/`，同 BC-4 一样不可从仓库重放。最小修法：在 §3.3 表里补 `file: old → new`。

**INFO（逐条）**
1. `22 §3.1` 与 `§5.1` 对同一 5 点给两套行号（scan 143 vs 137、ts 638/450 vs 640、vib 147 vs 144、prfo 958 vs 955、dimer 428 vs 425）——前者是语句行（已核），后者是注释/边界行；建议统一。
2. `test_scan_task_mode_case` / `test_prfo_init_mode_case` 把 `env%unit` 指向 scratch 并在 `rewind` 后重写：变异方向的红**依赖运行时“重写后截断”**（被覆盖掉的恰好是上一条输出的末尾两行 = NOTICE/选择行）。报告已观测到红 ⇒ 本构建确实截断；建议在 `read_unit_text` 的注释里点明这一平台假设。
3. `ctest -R landscape` 停在 118（无新 `add_test`），与“从 118 增加”的门槛措辞有落差；请在提交说明里写清“新增覆盖在既有目标内”。
4. BC-4：4 个原生 runtype 的**全部**输出文件（3/7/9/55）raw `cmp` 0 差异 + 文件清单相等 ⇒ 非“只比一个文件”；stdout 是**按 5 类已知非确定性行过滤**后比较，过滤行内部的真实差异不可见；raw 行数（28/30/66/28）与基线二进制在 `/tmp`（21 §7 I1 已登记）。
5. 裁定 4 的“生效值”措辞：打印的是 `settings%hessian_source`，与 provider `name` 一一对应（工厂对未知值 `env%error`、缺文件名 `env%error`，无静默回退），故“生效值”成立；`--ljson` 是独立文件、stdout 只被正则解析，无污染。`--lirc` banner 新增一行属套件侧输出变更（§17.7 已登记），不影响 BC-4 的 4 个原生 runtype。
6. 未跟踪 `p1fix2-workflow.js`（仓库根，本轮新增的 /tmp 工作脚本同类物）：与 21 §7 I3 的处置一致，**不得提交**；建议 `.gitignore`（可选）。

**小写行为不变的逐处判定（裁定 3 禁止项）**：5 处对纯小写输入的布尔结果与原代码逐字等价——`trim(x)=='lit'` 与 `lowercase(x)=='lit'` 在小写输入下同真同假；`select case (trim(n_init))` 与 `select case (landscape_lowercase(n_init))` 对 `'force'/'random'` 命中同分支、其它小写值同走 `case default`（错误文本仍回显原拼写，用例已断言）。**未改变小写输入既有行为。**

**遗漏扫描（裁定 3 的“全量”）**：`src/landscape` 内 `== '…'` 命中 7 处，全部为 `landscape_lowercase(...)`；`select case` 的字符选择子只剩 `landscape_lowercase(...)`（其余全是整型枚举或 `settings%task()` 这类编译期常量）；`trim(...) ==`、`.eq.`、双引号比较、`select case (trim(`、`/= '` 在 `src/landscape` **0 命中**；main.F90 无针对 landscape 设置串的字面比较，也无 `--method`。⇒ **无遗漏、无新增库入口字面比较。**

**回归风险**：本轮只做“大小写不敏感化”+ 一行 stdout，数值路径未动；M0..M7 已验收数字与 W0 三条缺陷（`-O2`、`$fix`+rfo、`$thermo` 优先级）均不受影响——每个被改分支的**数值语义**只在曾经“错误/报错”的大写输入上改变，而现有用例/验收数字全部用小写或经 `*_from_name` 归一（`grep test/unit` 未见任何断言旧大写行为的用例）。