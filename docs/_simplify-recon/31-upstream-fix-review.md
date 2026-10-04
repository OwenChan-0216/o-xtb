## 审查摘要（≤30 行）

**结论：接受（有 1 条 MEDIUM，可用 1 行改动/1 行登记关闭）；这个修复现在可以提交 git。**

1. 修复本体正确且最小：`src/relaxation_engine.f90` 只改 2 行代码（`:617 call molopt%copy(mol)`、`:781 call mol%copy(molopt)`）+ 3 行注释，diff stat 5+/3-，无任何连带改动；同文件 rf/FIRE 路径（`:311`/`:379`）本来就是 `%copy`，写法/签名一致。
2. 可证伪性主张**成立**：NUL 是合法 UTF-8（U+0000），严格解码确实会漏；新测试是**三重**断言——严格解码 + 控制字节扫描 + **符号列与输入 fixture 逐原子比对**（`landscape_cli_check.py:2513-2544`）。我未能构造出能同时通过三条的真垃圾（所有输出都源自同一个被破坏的 `mol%sym`）。
3. 注入红/还原绿**可核**：命令 + 期望 + 实际齐备（`ctest -R native-opt-lbfgs-symbols` → `***Failed` / `Passed`），另有独立第二份"改前红"（未打补丁的基线二进制连跑两次红）。仅部分命令转录被节略。
4. R42 计数口径**自洽**：`11-cli-redesign.md:73`(R42)、`:93`(§0)、`:2409-2418`(§10 注) 三处都写"不属于 18 条、A3+B0+C8+D1+E1+F4+G1=18 不变"，`:2386` 汇总行未变、`:2861` 不矛盾。本修复确实未被混进 18 条。
5. 残留项登记**完整**：`src/screening.f90:107 mol = mol0` 已记入 `AGENTS.md:349-351`；我全量扫描（RHS `= mol*`、LHS `mol* =`、全部 `type(TMolecule)` 局部名）后确认它是 `src/` 里**唯一**剩余的真 `TMolecule = TMolecule` 内在赋值。
6. 边界干净：未动 §5 的 7 个核心目录，`src/landscape/**` 0 改动，`relaxation_engine.f90` 无 `use xtb_landscape_*`（grep = 0），未引入阶段 3 内容。
7. 注册完整：`CMakeLists.txt:3549` + `:3594`(ENV) 与 `meson.build:649-652` 双注册，测试名唯一（add_test 一次、meson test 一次）。

**MEDIUM-1（唯一需要动的地方）**：新测试用 `--opt --input <$opt engine=lbfgs>`（`landscape_cli_check.py:2489-2494`），而 C7/§3.8c 在阶段 3 会把"套件 runtype + `$opt` 块"变成**响亮错误**（`11-cli-redesign.md:779-784`、`2316-2327`）⇒ 阶段 3 这条测试必红且**无人登记**；最小改法：改成 `--opt normal --method l-ancopt --norestart`（`main.F90:4159-4160` → `p_engine_lbfgs` → `geoopt_driver.f90:155-158`，`landscape_cli_check.py:2322-2323` 已证该拼写打到同一个引擎），这样 R42 的"不改计数"也继续保持成立。

LOW×3 / INFO×6 见正文；**别把 `errors='replace'` 当成新测试变红时的"修法"**（那会静默解除断言）。

---

# docs/_simplify-recon/31-upstream-fix-review.md（正文，请父会话落盘）

# 复核：上游 `relaxation_engine` 内在赋值缺陷修复（R42）

- 复核对象：`docs/_simplify-recon/30-upstream-relaxation-fix.md`、`11-cli-redesign.md`（R42 行 + §0/§10 计数注）、
  `src/relaxation_engine.f90`、`test/unit/landscape_cli_check.py`（mode `nativeoptsym`）、
  `test/unit/{CMakeLists.txt,meson.build}`、`AGENTS.md`（gitignored）
- 复核 HEAD：`0406baf`；工作树未提交 delta（watchdog，stat）：5 个已改文件 + 1 个未跟踪报告
  （`11-cli-redesign.md` 17+/4-、`src/relaxation_engine.f90` 8+/4- 即 5+/3-、`CMakeLists.txt` 20+、
  `landscape_cli_check.py` 89+、`meson.build` 11+；未跟踪 `docs/_simplify-recon/30-upstream-relaxation-fix.md`）
- 本复核**只读**，未运行任何命令；所有"实测"引用均来自报告/AGENTS.md，凡需执行的命令集中在 §4。

## 0. 结论

| 项 | 判定 |
|---|---|
| 修复正确性 | **通过**（2 行、语义等价路径、与 rf/FIRE 同写法） |
| 可证伪性主张 | **成立**（NUL 合法 UTF-8 ⇒ 严格解码不足；三重断言互相兜底） |
| 报告纪律 | **基本可核**（3 处可核口径 + 1 处数字错 + 2 处论据偏弱） |
| 计数口径 | **自洽**（R42 未混进 18 条） |
| 边界 | **干净**（无核心层、无阶段 3 内容） |
| **是否可以提交 git** | **可以**。CRITICAL 0 / HIGH 0 / MEDIUM 1 / LOW 3 / INFO 6；MEDIUM-1 建议随同一 commit 用 1 行测试改动关闭 |

## 1. 逐条回答主任务

### Q1 可证伪性主张是否成立 —— 成立

**新测试的断言到底是什么**（`test/unit/landscape_cli_check.py:2462-2545`）：

| 断言 | 位置 | 内容 |
|---|---|---|
| 真的走到了 L-BFGS 引擎 | `:2502` | `"L-ANC optimizer" not in output` ⇒ fail。该 banner 只有 `l_ancopt` 打印（`src/relaxation_engine.f90:591-594`），FIRE 打的是 `Fast Inertial Relaxation Engine`（`:286`），`rf` 引擎**不打 banner**（该文件 162-390 段无 banner 写入）⇒ 若 `$opt engine=lbfgs` 被忽略而落到 rf，测试**会红**，不可能"没跑到就绿" |
| 严格 UTF-8 | `:2516-2520` | 对 `proc.stdout+proc.stderr` 与 `xtbopt.xyz` 原始字节做 `raw.decode("utf-8")` |
| 控制字节扫描 | `:2521-2523` | 任何 `b < 0x20` 且非 `\t`/`\n`/`\r` ⇒ 失败并打印偏移 |
| **符号列语义比对（文件）** | `:2525-2533` | 从输入 fixture 取原子数与符号序列，与 `xtbopt.xyz` 的 `xyz[2:2+natoms]` 符号列**逐原子相等** |
| **符号列语义比对（stdout）** | `:2535-2544` | `final structure:` 块（正则锚定 `====\n<count>\n<comment>\n<atoms>`）的符号列同样必须等于输入序列 |

**论证成立性**：(a) `b"\x00".decode("utf-8")` 成功（U+0000 是合法码点），所以"严格解码"作为**唯一**断言会漏——这一条是纯 Python 事实，不需要跑；(b) 报告 §3.1 给了首次复现的 32 个坏字节**全是 NUL**、严格解码成功的证据；(c) 报告 §3.2 又给了一次"严格解码通过但符号列是垃圾（含 `\x00`/`\x17`）"的注入证据。⇒ "严格解码不足"这个结论**成立**，而且它同时解释了为什么"容错解码 `errors='replace'`（`landscape_cli_check.py:69-81` 的 `decode`）"不是掩盖原因：换成严格解码也一样会漏。

**会不会误报**：在当前 fixture 下不会。理论上的误报源只有三个，全部属于 fail-loud 且与本缺陷无关：
1. 与本轮无关的上游 Fortran record-marker 泄漏（`28-stage2-fix-report.md` T2，501 原子 fixture 实测 1/8/192 个非法字节）若出现在这个小 fixture 上 ⇒ 严格解码会红（→ INFO-2）；
2. 未来 banner 引入控制字符（如 ANSI ESC 0x1b、退格 0x08）⇒ 控制字节扫描会红（今天的输出里没有，grep 过 `src/` 无此类写入）；
3. upstream 改 `final structure:` 布局（`src/geoopt_driver.f90:199-202`：`="=="` / `final structure:` / `="=="` / `writeMolecule`）⇒ 正则失配，报"block is missing"（也是红）。

**会不会漏报**：我构造不出。要同时逃过三条，必须满足"合法 UTF-8 + 无 `<0x20` 控制字节 + `xtbopt.xyz` 与 stdout 的 `final structure:` 符号列都恰好等于 `O,H,H`"。而缺陷是 `mol%sym` 数组被写坏，`xtbopt.xyz` / `xtbopt.log` / `xtbtopo.mol` / stdout 的 `final structure:` / 键表**同源**（都来自 `l_ancopt` 返回的 `mol`），所以只要符号坏了，符号列比对至少命中一处；若字节是 NUL/控制字符，控制扫描命中；若是非 UTF-8，解码命中；若是可打印垃圾（报告实测出现过 `4443`、`` ` ``），符号列比对命中。**唯一"通过"的情形是数据其实没坏**（例如相邻内存恰好给出正确符号），那就不叫漏报。一个可想到的窄口子：垃圾只出现在本测试**不看**的字段/文件（如 `xtbopt.log`、`xtbtopo.mol` 或 stdout 的键表以外区域）——但这也只可能发生在"符号列恰好正确而其它地方坏了"的假设情形，与已知机制不符（BC-4 显示三者同时坏）。

**注入红/还原绿是否可核 —— 可核（命令 + 期望 + 实际三者齐备）**：
- 注入方式明写（文本替换回内在赋值，且证明 `git diff --stat` 空、`cmp` 与 HEAD 逐字节相同）⇒ 替代了上一次"注入不等价"的教训（AGENTS.md §6 M4 条）；
- 期望（红）与**实际**（`***Failed 0.06 sec`、`FAIL: stdout is not valid UTF-8: ... byte 0xcd in position 15988`）都有；
- 还原（`cp` 回补丁版 + 重建）后 `Passed 0.06 sec` 的实际输出也有；
- 另有**独立**的第二份"改前红"：同一条检查对未打补丁的基线二进制连跑两次都红（`0xac`/`0xfc`）⇒ 不依赖注入也能证明"坏代码会红"。
- 不足：注入用的替换脚本、以及"另一注入运行里严格解码通过/符号列红"的完整转录被节略（只有 4 行片段），复跑需重建命令（→ INFO-3）。不影响核心主张。

### Q2 R42 的计数表述 —— 自洽，本修复未被混进 18 条

| 位置 | 文本 | 判定 |
|---|---|---|
| `11-cli-redesign.md:73`（R42 行） | "**计数口径：不属于 18 条 CLI 破坏性变更**（§10 汇总行 A3+B0+C8+D1+E1+F4+G1=**18** 不动），它是**独立的上游 bug 修复**" | 自洽 |
| `:93`（§0「破坏性变更」行尾注） | "**R42 不改变这个计数**：那是……独立 bug 修复……不是 CLI 破坏性变更" | 自洽 |
| `:2409-2418`（§10 汇总行后的 R42 注） | "本节汇总仍为 **A 3 + B 0 + C 8 + D 1 + E 1 + F 4 + G 1 = 18**"；并另有一句"它确实**改变原生输出字节**……已在 BC-4 里单列为'有意改变'的一行" | 自洽 |
| `:2386`（§10 权威汇总行） | `= 18 条`（未改） | 自洽 |
| `:2861` | "破坏性计数：R38 后为 18 条" | 不矛盾（历史口径，未声称含 R42） |

算术核对：3+0+8+1+1+4+1 = 18 ✔。R42 的定位（独立 bug 修复 + 单列"有意行为变更"）没有污染 CLI 计数。
**唯一需要补的一层**见 MEDIUM-1：本轮的**新增测试**是第二个"阶段 3 测试层后果"（§10 G 类），加上现有 `u15-xcontrol-only`，两个都没有登记。

### Q3 修复是否最小 —— 是

- diff stat：`src/relaxation_engine.f90 | 8 +++++---`，逐行核对 = 2 行代码（`molopt = mol`→`call molopt%copy(mol)`；`mol = molopt`→`call mol%copy(molopt)`）+ 3 行注释（2 行新增说明 + 1 行注释改写），**该文件其它行未动**；
- 同文件 rf（`:311`/`:379`）、FIRE（`:311`/`:379` 同段）与 `src/hessian.F90:631/638` 的 `tmol%copy(mol)` 未被改动；`src/optimizer.f90:198`、`src/landscape/**` 的同类局部（`buffer`/`prodmol`）本来就是 `%copy`/`init`；
- 无签名/接口改动：`copyMolecule(self,mol0)`（`src/type/molecule.f90:199-208`，`class(TMolecule), intent(out)`）与 rf 路径实参形态完全相同；`TMolecule` 的 `assignment(=)` 只定义了 `structure_to_molecule`/`molecule_to_structure`（`molecule.f90:189-192`、`:409-429`、`:431-451`），所以原两行**确实是**内在赋值，会命中该编译器缺陷 —— 报告 §1 的这段推理我逐条读过，成立。

### Q4 "数值不变"的论证是否足够 —— 方向对，但主论据应是 §2 的逐行 diff，不是 token 计数（→ LOW-2）

- §4 的 token 正则 `[-+]?\d+\.\d+(e±\d+)?` **漏整数**：stdout 的 WBO/键表里的原子序号（`1 8 3 2`）、`iter:`、原子数、`--` 占位符都不计入。报告 §2 的 stdout diff 里就有 `     1   8 O    1.840 --     3 4443 0.920     2 ...` 这类整数字段；
- §4 的 12/60/10/389 计数来自 `/tmp/xtb-up/bc4/bc4.sh`（不在仓库）⇒ 不可独立复核；
- 但 §2 提供了**更强**的证据：10 个用例里 96 个输出文件 raw `cmp` 全同 + `optlbfgs` 的 3 个文件差异"只在符号列" + 归一化 stdout 的 14 行差异**全是符号 token**（并给了逐行 `diff`），再加 `TOTAL ENERGY -5.070544430927 Eh`、`xtbopt.xyz` 第 2 行 `energy: -5.070544430927 gnorm: 0.000135264098` 字符级锚点，以及坐标列字符级相同。**这已经足以支撑"数值不变"**（而且 `xtbopt.xyz` 第 3 行 O 未变、只 4/5 行 H 变，与 AGENTS.md §6.5"element 1 stays correct"的机制描述吻合，是很好的自洽交叉验证）。
- 建议：§4 改标为"辅助证据"，主论据指向 §2；若要保留 token 法，应把 `[-+]?\d+(\.\d+)?([eEdD][-+]?\d+)?` 与整数一起统计，并说明版本串 `6.7.1` 也在 token 流里（⇒ token 计数依赖构建元数据对齐）。

### Q5 BC-4 分类是否诚实 + 第一轮 9 个假红的解释 —— 分类诚实；解释可核但机制属假设

- **分类诚实**。5 个"未变"用例在代码层面就不可能变：`optnative`（`--opt` 默认引擎，n=3 ⇒ rf，`src/main/defaults.f90:42-46`）、`ohess`（同为 rf）、`sp`/`hess`/`md`（不经过 `relaxation_engine`）、以及 4 个套件用例（`src/landscape/**` 对 `relaxation_engine`/`geoopt_driver`/`l_ancopt` 的引用 **grep = 0 命中**）；`loptengine`/`lscanmethod`/`ltsmethod`/`lircmethod` 走 `--l*`，不经过原生引擎。⇒ 唯一"有意改变"= `optlbfgs`，且只有符号载体（`xtbopt.xyz`/`xtbopt.log`/`xtbtopo.mol` + stdout 符号 token）。没有把"应该不变"包装成"有意改变"。文件数算术也自洽：3+7+9+55+5+5+5+7 = 96；`optlbfgs` 5 个文件里 3 个差异、`charges`/`wbo` 相同。
- **第一轮 9 个假红**：报告 §6.2 的**观测**可核（`/tmp/xtb-up/build` 的 `include/xtb_version.fh` 当时是 `6.7.1 (unknown-commit)`、基线是 `6.7.1 (0406baf...)`；重新 `cmake -S . -B` 生成正确 header 后 9/10 用例**立刻**逐位全同）；**机制**（版本串长度改变 Fortran 单元 6 与 glibc `printf` 两块缓冲的刷新边界 ⇒ 两处打印层交换顺序）是**假设**，没有直接测量（→ INFO-6）。可核的做法就是"对齐构建元数据"，这也与 AGENTS.md/`25-stage2-impl.md` 记录过的同类动作一致；但更稳的是把版本串归一化掉（现在只归一化了 `xtbtopo.mol` 的 MDL 日期行）。

### Q6 遗留项是否如实登记 + 别处是否还有同模式 —— 登记属实，且 `screening.f90:107` 是唯一剩余

- `AGENTS.md:349-351`：明确登记 `src/screening.f90:107`（`mol = mol0`，`--screen` 路径）**未修**，并给出"新代码永不内在赋值，一律 `call a%copy(b)`"的规则（`:348-349`）；我也核对了 `src/screening.f90:46 type(TMolecule), intent(inout) :: mol0`、`:53 type(TMolecule) :: mol` ⇒ 该行确实是 `TMolecule = TMolecule` 内在赋值。
- **我自己的全量扫描**（`src/**`）：
  - RHS `=\s*mol[0-9A-Za-z_]*\s*$` 与 LHS `^\s*mol\w*\s*=`、以及 30 个 `type(TMolecule) ::` 局部名（`tmol`/`molopt`/`buffer`/`copy`/`comb`/`inner_mol`/`outer_mol`/`mol_model`/`local_mol`/`prodmol`/`ptr`/`molA`/`molB`/`mol_shifted` …）的赋值扫描 ⇒ **只有** `screening.f90:107` 是真 `TMolecule = TMolecule`；
  - `struc = mol`（`tblite/calculator.F90:176/429/508`、`dipro.F90:123`、`main/property.F90:319/441`）与 `mol = struc`（`ptb/calculator.F90:133`、`io/reader.f90:94`）走**定义赋值** `molecule_to_structure`/`structure_to_molecule`（`molecule.f90:189-192`）⇒ 不受该编译器缺陷影响；
  - `ptb/calculator.F90:271 mctcmol = mol`：`mctcmol` 是 `type(structure_type)`（`:236`）⇒ 定义赋值；
  - `intmodes.f90:218 molv=molvec`：整数数组（`:198-220` 段）；`hessian.F90:631/638` 已用 `%copy`。
- ⇒ 登记**完整**，没有"该登记而未登记"的第二处。

### Q7 边界 —— 干净

- 未触碰 §5 的 7 个核心目录（`src/type|xtb|mctc|param|io|disp|coulomb`）；唯一源码改动在 `src/relaxation_engine.f90`（仓库根目录下的既有上游文件），且 `grep -n 'landscape' src/relaxation_engine.f90` = **0 命中**（不违反"只有 `main.F90` 可 `use xtb_landscape_*`"）；
- 未含阶段 3 内容：没有改 `--opt` 改派、没有 C7 守卫、没有 `--method` 语义变化、没有 §6.3 旗标；改动性质是"修一个上游输出字节缺陷"，不是 CLI 行为变更。

### Q8 测试注册 —— 双注册且名字唯一

| 位置 | 内容 |
|---|---|
| `test/unit/CMakeLists.txt:3549`（+ `:3550-3555` 驱动调用） | `add_test("xtb/native-opt-lbfgs-symbols" … "-DARGS=nativeoptsym;${LANDSCAPE-E2E-XTB};${LANDSCAPE-H2O};…"` |
| `test/unit/CMakeLists.txt:3594` | 加入 `set_tests_properties(… ENVIRONMENT "XTBPATH=…;OMP_NUM_THREADS=1")`（AGENTS.md §6.1 的线程钉住要求） |
| `test/unit/meson.build:649-652` | `native_opt_dir = landscape_cli_dir / 'native-opt-lbfgs-symbols'` + `test('native opt lbfgs symbols', python, env: landscape_env, args: [landscape_cli_check, 'nativeoptsym', xtb_exe, h2o_xyz, native_opt_dir])` |
| `test/unit/landscape_cli_check.py:56`（mode 表）、`:2462`（实现）、`:3045`（分派） | 与报告 §3.3 一致 |
| 名字唯一性（我核对） | `add_test("xtb/native-opt-lbfgs-symbols"` 全文出现 **1 次**（`:3549`），`test('native opt lbfgs symbols'` **1 次**（`:650`）；参数形态与同族 mode（`:3369` method、`:3396` methodnative、`:3410` methodtable）一致，CMake 变量 `LANDSCAPE-E2E-XTB`(`:3184`)、`LANDSCAPE-CLI-PY`(`:3355`) 定义在该 add_test 之前；驱动 `landscape_cli_py.cmake`（`CMakeLists.txt:3342-3354` 生成）把 stdout/stderr 合并、按 status 报错 ⇒ mode 名/参数个数正确即可（`main()` 要求 `sys.argv[1:5]`，本 mode 用 3 个位置参数 ✔） |

### Q9 报告纪律 —— 逐条核对结论

| 报告主张 | 核对 |
|---|---|
| "2 行修复" / "该文件其它行未动" | ✔（watchdog stat 5+/3-，逐行读过） |
| `:615`/`:779` 是旧行号、`:311`/`:379` 是 rf 路径 | ✔ |
| "CMake + meson 双注册" | ✔（`CMakeLists.txt:3549/3594`、`meson.build:650`） |
| "测试名唯一" | ✔（新名各 1 次） |
| "AGENTS.md §6 第 5 条已扩写 + 已登记 `screening.f90:107`" | ✔（`AGENTS.md:335-351`） |
| "R42 不改变 18 的计数" | ✔（§0/§10/R42 三处一致） |
| "注入红 / 还原绿 / 基线红" | ✔ 命令+期望+实际齐备（部分转录节略，见 INFO-3） |
| "121/121 landscape、12/12 回归、BC-4 9/10 逐位同" | ⚠ 我无法运行 ⇒ 见 §4 需运行验证 |
| §8「`git status` 显示 **4 个**已改文件」 | ✘ **实际 5 个**（`11-cli-redesign.md`、`relaxation_engine.f90`、`CMakeLists.txt`、`landscape_cli_check.py`、`meson.build`）→ LOW-1 |
| §4 "数值不变"论证方式 | ⚠ 主论据选错（见 Q4）→ LOW-2 |

## 2. Findings

### CRITICAL
无。

### HIGH
无。

### MEDIUM

**MEDIUM-1（建议随本 commit 关闭）新测试用的 `--opt --input <$opt …>` 组合是阶段 3 的响亮错误，未登记**
- 位置：`test/unit/landscape_cli_check.py:2489-2494`（写 `$opt\n engine=lbfgs\n$end\n` 并 `--opt normal --input engine.ctl`）。
- 证据：`11-cli-redesign.md:779-784`（§3.8c 触发条件 = 出现过 `$opt` 组 **且** `landscape_is_suite_run(set%runtyp, landscape_native_engine)`）与 `:2316-2327`（**C7**，计数 +1，改后 `env%error` exit 1）⇒ 阶段 3 落地后本测试在 `proc.returncode != 0` 处必红。
- 为什么是本轮的问题：`11-cli-redesign.md:2249/2324/2548` 三处把这个 C7 的"爆炸半径"记为"`grep -rn '\$opt' test/unit/` = **0 命中** ⇒ **0 条既有测试会变红**"，而本轮新增的 `:2491` 正是新的 `$opt` 用法；同时 §10 的 **G 类**（"阶段 3 的测试层后果（已知且必须同步修复）"，`:2377-2384`）只有 G1 一条，本轮没有登记第二条。（附：该 0 命中口径在本轮之前就已被 R41/T10 的 u15 段破坏——`landscape_cli_check.py:2418/2424/2427/2430/2441/2451/2458`，其中 `u15-xcontrol-only`（`:2454-2455`，`--opt --norestart --input rf_control` 且无 `--method`）在阶段 3 同样会红；这属于上一轮的遗留，但同一次登记应当一并覆盖。）
- 最小修法（二选一，都不改语义、都不影响缺陷覆盖）：
  1. **推荐**：把该 mode 的 xtb 调用改成 `[exe, inp, "--gfn", "2", "--opt", "normal", "--method", "l-ancopt", "--norestart"]`，删掉 `engine.ctl` 与 `--input`。同一段 `l_ancopt` 被走到（`main.F90:4159-4160` → `p_engine_lbfgs` → `geoopt_driver.f90:155-158`），且 `landscape_cli_check.py:2322-2323` 已断言 `--opt --method lancopt/l-ancopt` 打印 `L-ANC optimizer` ⇒ 存活条件不变；同时让 R42"不改计数"继续成立。
  2. 保留 `$opt` 路线，但在 §10 G 类 / §14.5 增记一条（并在 §9.4、§10 C7 的爆炸半径处把 `grep` 计数改为实际值），说明阶段 3 需把本测试迁移到 `--method l-ancopt`（或断言新的错误文本）。

### LOW

**LOW-1 报告 §8 的文件计数错**：`30-upstream-relaxation-fix.md` §8 写"`git status` 因此显示 **4 个**已改文件"，实际为 **5 个**（watchdog stat 的 5 个文件；§3.3 自己也列了 CMake+meson+py+doc = 4 个注册/文档位置 + 源码 = 5）。建议顺手改为 5，并保留"新报告本身未跟踪、提交时需 `git add docs/_simplify-recon/30-upstream-relaxation-fix.md`"的提醒（现在只写了"未提交"）。

**LOW-2 "数值不变"的主论据选错**：见 Q4。`docs/_simplify-recon/30-upstream-relaxation-fix.md` §4 的 token 正则漏整数（原子序号/`iter:`/原子数/`--`），且计数脚本只在 `/tmp`。建议把 §2 的"96 文件 raw `cmp` 全同 + `optlbfgs` 14 行差异全是符号"提为主论据，§4 降为辅助。

**LOW-3 "影响面"被低估（方向是低估，不是夸大）**：报告 §0 / R42 / `AGENTS.md:339` 都写"原生 `--opt` 走 L-BFGS（`$opt engine=lbfgs`，或 >500 原子的默认引擎）"。实际 `geometry_optimization` 还有 12 处调用点：`prog/main.F90:950`、`:1392`、`getkopt.f90:142`、`screening.f90:147`、`mdoptim.f90:89`、`docking/search_nci.f90:551/918`、`modef.f90:157/298/341/455/491`、`scan_driver.f90:88/119`、`gfnff/struc_converter.f90:132`（这些文件均 `use xtb_geoopt`）⇒ `--screen` / `--mdopt` / `--modef` / `--dock` / 原生 `--scan($scan)` / GFN-FF 在 `$opt engine=lbfgs` 或 n>500 时同样受影响（修复同样受益）。建议把这句改成"任何走到 `xtb_geoopt` 的原生路径"，否则将来有人按这句去判断爆炸半径会漏。

### INFO

**INFO-1 局部拷贝的元数据损失（不改代码，但值得一句话记录）**：`copyMolecule`（`molecule.f90:199-208`）只搬 `at/sym/xyz/chrg/uhf/lattice/pbc`(+`ftype`)，而 `TMolecule` 还有 `name/bonds/frag/pdb/sdf/info/cn/dist/linear/cellpar/rec_lat/volume/wsc`（`:100-137`）。`init` 会调 `update`（`:243-244`）重建 `dist/linear` 与周期量 `cellpar/rec_lat/volume`（`:510-527`），但 `name/bonds/frag/pdb/sdf/info` **不会**重建。因此修复后 L-BFGS 结束时返回的 `mol` 比"内在赋值时代"少了这些输入元数据——**这与 rf/FIRE 引擎（`:311`/`:379`）行为完全一致**，也与 BC-4 结果一致（xyz 输入下 `bonds` 本就为空；`xtbtopo.mol` 的键表在 `topology.f90:56-76` 由 WBO 重算，故只有符号列变化）。未测的输入类别：SDF/PDB/molfile（残基、输入键块）与周期 `optcell`（lattice/pbc 有拷贝、派生量会重算，风险低）。最小验证：`$opt engine=lbfgs` 跑一个带键块的 SDF（或带残基的 PDB），与 rf 路线（或 HEAD）逐文件 `cmp`。

**INFO-2 新断言可能被无关上游缺陷打红**：严格 UTF-8 + 控制字节扫描对本 fixture 今天为绿；但若上游 record-marker 泄漏（`28-stage2-fix-report.md` T2）在小体系上出现，本测试会红而缺陷不在本代码。**不要**用 `errors='replace'` 去"修"（`landscape_cli_check.py:69-81` 的容错解码在这里是**故意绕过**的）——那会静默解除断言，正是本项目的四类反复缺陷模式之一。

**INFO-3 证据可复现性**：BC-4 的脚本与原始输出（`/tmp/xtb-up/bc4/bc4.sh`、`bc4-final.out`）只在 `/tmp`；注入 transcript 有 `...` 占位符；`python3 -c '...; raw.decode("utf-8")'` 成功后不打印，而报告转录里出现了 "strict decode ... OK" 一行（隐含 `print`）。M2/M3 的惯例是把原始数据落到 `docs/_landscape-recon/*-data/`，建议本轮也把 `bc4.sh` + `bc4-final.out`（或至少完整命令清单）落盘。

**INFO-4 措辞**："上游 `relaxation_engine` 内在赋值缺陷修复"（R42 标题）与 `AGENTS.md:328-329` 的"**reportable to GCC Bugzilla, not to xtb upstream**"并列时容易误读：代码位置在上游、根因在编译器（内在赋值是合法 Fortran）。建议加一句限定（"上游代码里的写法触发本机编译器缺陷"），并明确"是否/是否已向 upstream 报告"。

**INFO-5 陈旧计数（先于本 diff，顺手记）**：`11-cli-redesign.md:1016` 仍写"不属于已入册的 **16 条**"（R23 时代口径），与 §10 的 18 条不一致；本轮未触碰该行，不计入本轮问题。

**INFO-6 §6.2 的机制句**：`/tmp/xtb-up/build` 的 `xtb_version.fh` 为 `unknown-commit` 而基线为 hash 的**观测**可核（重新 configure 后 9/10 立刻逐位全同）；"版本串长度改变两块缓冲刷新边界 ⇒ 打印层交错翻转"是**假设**。建议 (a) 把 BC-4 的归一化扩展到版本串（现在只掩码了 `xtbtopo.mol` 的 MDL 日期行），(b) 机制句标注为待验证假设（本项目已有"机制句必须有数据"的先例）。

## 3. 逐项核对表（file:line 证据）

| # | 项目 | 证据 | 判定 |
|---|---|---|---|
| 1 | 两行修复 | `src/relaxation_engine.f90:617`、`:781`（diff stat 5+/3-，仅此两处） | ✔ 最小 |
| 2 | 语义等价路径 | `:311`/`:379`（rf/FIRE 同写法）；`src/type/molecule.f90:167`（`procedure :: copy => copyMolecule`）、`:199-208` | ✔ |
| 3 | 内在赋值判定 | `molecule.f90:189-192`（只定义 `structure_to_molecule`/`molecule_to_structure`）、`:409-429`、`:431-451` | ✔ 报告推理正确 |
| 4 | 测试三重断言 | `landscape_cli_check.py:2502`（引擎守卫）、`:2513-2523`（解码+控制字节）、`:2525-2533`（xyz 符号列）、`:2535-2544`（stdout 符号列） | ✔ |
| 5 | 无 vacuous pass | `relaxation_engine.f90:591-594`（只有 l_ancopt 打 `L-ANC optimizer`；rf 无 banner、FIRE 是另一串） | ✔ |
| 6 | 注册 | `CMakeLists.txt:3549`、`:3594`；`meson.build:649-652`；`landscape_cli_check.py:56/2462/3045` | ✔ |
| 7 | 名字唯一 | add_test 新名 1 次；meson 新名 1 次 | ✔ |
| 8 | 计数口径 | `11-cli-redesign.md:73`、`:93`、`:2386`、`:2409-2418`、`:2861` | ✔ 自洽 |
| 9 | 阶段 3 兼容 | `11-cli-redesign.md:779-784`、`:2316-2327`、`:2377-2384` vs `landscape_cli_check.py:2489-2494` | ✘ **MEDIUM-1** |
| 10 | AGENTS.md 登记 | `AGENTS.md:335-347`（本缺陷+修法）、`:348-349`（规则）、`:349-351`（`screening.f90:107` 未修） | ✔ |
| 11 | 别处同模式 | `src/screening.f90:46/53/107`（唯一真 TMolecule=TMolecule）；其余均为定义赋值或非 TMolecule（`tblite/calculator.F90:176/429/508`、`dipro.F90:123`、`main/property.F90:319/441`、`io/reader.f90:94`、`ptb/calculator.F90:133/271`、`intmodes.f90:218`） | ✔ 登记完整 |
| 12 | 边界 | 未动 §5 核心目录；`grep landscape src/relaxation_engine.f90` = 0；无 `--opt` 改派/守卫改动 | ✔ |
| 13 | 数值不变（机制） | `molecule.f90:205-207` vs 内在赋值；BC-4（报告 §2）96 文件 raw `cmp` 同 + 14 行差异全符号 | ✔（论据表述 → LOW-2） |
| 14 | BC-4 分类诚实 | 5 个未变用例的代码依据：`src/main/defaults.f90:42-46`（rf 默认）、`src/landscape/**` 对原生引擎 0 引用 | ✔ |
| 15 | 报告文件计数 | 报告 §8 "4 个已改文件" vs watchdog 5 个 | ✘ LOW-1 |

## 4. 需运行验证（我无命令权限；请父会话/监管跑）

1. `OMP_NUM_THREADS=1 ctest --test-dir <O2 build> -R native-opt-lbfgs-symbols --output-on-failure` → 期望 `1/1 Passed`（这是本轮唯一新增门禁）。
2. `OMP_NUM_THREADS=1 ctest --test-dir <O2 build> -R landscape` → 期望 121/121（**注意别跑全量 ctest**，AGENTS.md §4）。
3. `OMP_NUM_THREADS=1 ctest --test-dir <O2 build> -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'` → 期望 12/12。
4. 名字唯一性（防 CMake 静默丢测）：`ctest -N -R landscape | tail -1` 与 `grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d`（期望空）。
5. 反向注入（可证伪性二次确认，至少一条）：把 `:617`/`:781` 改回内在赋值 → 重建 → 该测试必须 **红**；还原 → **绿**。
6. 基线对照：用未打补丁的 HEAD 二进制跑 `python3 test/unit/landscape_cli_check.py nativeoptsym <base-xtb> <landscape_h2o.xyz> <tmpdir>` → 期望 exit 1。
7. BC-4 复核（若要自己重跑）：两个构建目录的 `include/xtb_version.fh` 必须一致（版本串须含同一 hash），再逐文件 `cmp`；建议同时掩码版本串与 `xtbtopo.mol` 的 MDL 日期行。
8. 若采纳 MEDIUM-1 的方案 1：另跑 `xtb landscape_h2o.xyz --gfn 2 --opt normal --method l-ancopt --norestart` 目视 `xtbopt.xyz` 符号列为 `O/H/H`（等价于现有 u15 断言）。

## 5. 被确认 / 被证伪的细节

- **确认**：NUL 是合法 UTF-8（严格解码不足以证伪该缺陷）——Python 规范事实，且报告给了两条独立证据；报告对该前提的"证伪 + 据此加固断言"是正确的方法论动作。
- **确认**：报告 §0 的"element 1 正确、`sym(2:)` 坏"与 BC-4 的 `xtbopt.xyz` 行号（第 3 行 O 不变、第 4/5 行 H 变）自洽；测试的 `xyz[2:2+natoms]` 索引假设因此被交叉验证为正确。
- **确认**：`screening.f90:107` 之后无第二处同类内在赋值（我的 grep 覆盖面：RHS/LHS 双侧名字、全部 `type(TMolecule)` 局部与 `allocatable/pointer` 变体）。
- **需修正的口径**：`11-cli-redesign.md:2249/2324/2548` 的 C7 爆炸半径"0 命中"已被 R41/T10 的 u15 段与本轮新测试证伪（见 MEDIUM-1）。
- **未证伪任何修复相关主张**：报告中我没有找到与源码矛盾的"已改/已测"陈述（除 §8 的文件计数）。

## 6. 提交判定

**可以提交 git。** 修复本体（2 行 + 注释）、新测试（三重断言、可证伪）、注册（CMake+meson、名字唯一、ENV 钉线程）、文档登记（R42/§0/§10 计数、AGENTS.md §6.5）均无阻塞项；MEDIUM-1 的最短关闭方式是一行测试调用改写（`--opt --method l-ancopt`，去掉 `$opt`/`--input`），建议并入同一 commit；若选择保留 `$opt` 路线，则必须在 §10 G 类/§14.5 补登记并更新 C7 的爆炸半径实测值。LOW/INFO 均为报告文字与论据表述层面，不阻塞提交。