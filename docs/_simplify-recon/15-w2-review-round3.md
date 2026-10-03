## 摘要（≤30 行）

1. **结论：有条件接受（Conditional Accept）**。CRITICAL 0 / **HIGH 1** / MEDIUM 4 / **LOW 7** / INFO 2。
2. **H-1：按字面已可实现**（我逐出口代入复核）：4 个原生出口都走 §4.7 第 2 段的 `if (native_engine /= 0)` 分支，**不调** `landscape_opt_algorithm_from_name`、**不落** `default`；`--method` 与 runtyp 旗标顺序无关成立（第 1 段不读 `set%runtyp`、第 2 段在 flag 循环后）；与 `set_runtyp` 锁无关（`--method` 从不调它）。**扣分项：`landscape_native_engine` 声明为 `intent(out)`（`11:880-889`），而第 2 段只在 `if (allocated(...))` 内赋值 ⇒ 没有 `--method` 的运行读到**未定义值**（新 MEDIUM-1）。
3. **HIGH-1（新，阻断阶段 3 的 `--ohess` 那一半）：M-3 只关了 `--opt` 的半边**。原生 `main.F90:1156→1170 call numhess`、`:1282-1285 main_freq`、`:270 anyhess`（用于 `:1324 write_energy`）都按 `runtyp==ohess` 触发，而 `--ohess`(套件) runtyp 仍是 `p_run_ohess` ⇒ **跑两遍 Hessian/频率**，输出互相覆盖；只抑制 `:931`（`11:938,954`）不够。
4. **H-2：已闭合**。谓词 `landscape_is_suite_run` 覆盖 4 个出口；我代入 `--opt --method fire + $scan`（`:491-510` 守卫跳过 → `:943-945 relaxed_scan` 执行 ✓）、`--lopt --method ancopt + $scan`（解析尾报错，早于守卫 ✓）、`--opt --method pbc_lbfgs + 周期`（原生，守卫不触发 ✓）、`--ohess --method ancopt + 周期`（原生 numhess 的既有 PBC 报错，与今天一致 ✓）。
5. **M-1：真修**（`11:1471` 表加"R4 后（§3.9）"列、`11:1487-1496` 结论两段化、留痕在 `11:1495`/`13:91-92`）。**但 `13-*.md §6` 的自检现在是假的**：`grep -c "R4 后补齐" 11-*.md` = **3**（`11:58,1495,2420`），不是它写的 **0**（新 MEDIUM-2）。
6. **M-2：已闭合**。C7 入册（`11:2094` 起）、计数 15→16，`§0/§3.6/§10/13:64` 四处**算术自洽**（3+0+7+1+1+3+1=16）；爆炸半径 `grep -rn '\$opt' test/unit/` 我复核 = **0 命中** ✓。
7. **M-3：部分闭合**（见 3）——`--opt` 半边给到了具体位置/条件/测试；`--ohess` 半边缺失。
8. **M-4：已闭合**。集合 S（`--l*` + `--method`）实际是**纯套件**集合：30 个原生未文档化旗标（`02-cli-audit.md:306-313`）与 4 个未实现文档项**无一以 `--l` 开头** ⇒ 阶段 1 门槛（差集=0）自洽。
9. **破坏性计数自洽**：清单条目 C1..C7 与 16 条对得上；`§1.2 BC-3`="集合不小"、`§5.4`="HEAD 现状/R4 后"两段、`§10 B`=0 三处口径一致。
10. **回归**：R22 的改写留下 2 处**指向已作废机制**的残留（`11:2183` U1、`11:2322` §14.2-M8 仍写"两个逻辑标志"）与 `§3.11:875-879` 的"作废"声明矛盾（新 MEDIUM-3）。
11. **其余 17 条未被我复核算出回归**；行号勘误我抽查 12 处**全部命中**（`set_module.f90:1891/:797/:1885/:1811/:1649`…、`relaxation_engine.f90:131/400/298/594`、`compliance.f90:287`、`xhelp.f90:170/722/780/270-271/286`、`man/xtb.1.adoc:238-241/246-248`、`optimizer.f90:392/801`、`lbfgs_anc/driver.f90:254`、`tasks/opt.f90:108`、`prog/main.F90:270/476/931/989/1156/1665`）。
12. **阶段判定**：**阶段 1 可实施**；**阶段 2 可实施**；**阶段 3 的 `--opt` 部分可实施，`--ohess` 部分在补 HIGH-1 前不可实施**；实施前必须在 §4.7 第一行补 `landscape_native_engine = 0`（MEDIUM-1）。

---

# 15 — W2 CLI 重设计（第 3 轮）独立复核报告

> 对象：`docs/_simplify-recon/11-cli-redesign.md`（闭合后 2422 行）、`13-cli-redesign-revision.md`、依据 `14-w2-review-round2.md`。
> HEAD `bdd8eb8`。**本轮为 read-only 复核（无 shell、无编辑）**：所有 `[实测]` 数字未复跑（标"未复跑"），凡代码断言给 `file:line`（我逐条读了源码）。
> 计数口径：CRITICAL 0 / HIGH 1 / MEDIUM 4 / LOW 7 / INFO 2。
> 编号规则按 `11:2286-2296` 的 I-2 规则：**先数内容、再对编号**，不改复核给的 ID。

## 0. 方法

核点：`src/prog/main.F90`（解析尾 `:3881-3891`、`anyopt :317/931`、分派 `:989/1012/1028/1058/1077`、`:270/1156/1170/1276-1285/1310-1324/4065-4068`、`--opt/-o :2153-2157`）、`src/set_module.f90`（`set_runtyp :1030-1037`、`$opt engine :1884-1893`、`rdcontrol case('opt') :797`、`optlevel :1809-1813/:2845`）、`src/setparam.f90:77-80,200-202,260`、`src/main/defaults.f90:41-46`、`src/geoopt_driver.f90:148-172`、`src/landscape/types/settings.f90:1112-1135`、`src/landscape/tasks/opt.f90:85-167`、`src/landscape/types/log.f90:55-88`、`test/unit/landscape_cli_check.py:447-503`、`docs/_simplify-recon/02-cli-audit.md`。

## 1. 结论

**有条件接受。** 第 2 轮点名的 4 个阶段 3 阻塞项里 **H-1 / H-2 / M-2 真闭合**，**M-3 只关了 `--opt` 半边**（＝ 本轮 HIGH-1）；本轮**新增 3 条 MEDIUM**（1 条是实现可执行性、2 条是"声称可核"纪律回归），**另有 7 条 LOW** 均为可核的文档/行号/计数问题。

## 2. H-1：逐出口代入（我自己的走读）

**机制复核结论：可实现。** 关键在 `§4.7` 第 2 段是 `if (native_engine /= 0) ... else ...` 的**互斥两分支**，原生名在第 1 分支就被截走，`else` 才进套件 setter（`11:1225-1260`）。

| 出口 | 命令行 | 代入现有实现 | 落 `default`/`env%error`？ |
|---|---|---|---|
| 1 | `--opt --method ancopt`（`rf`） | 尾归一 `set%opt_engine = p_engine_rf`（`setparam.f90:77`）→ `anyopt` 仍真（`main.F90:317`）→ 原生块 `:931` 执行 → `geoopt_driver.f90:149 case(p_engine_rf)` → `:150 call ancopt`（`optimizer.f90:122`） | **否** ✅ |
| 2 | `--opt --method lancopt` | `= p_engine_lbfgs`（`:78`）→ `geoopt_driver.f90:155 case(p_engine_lbfgs)` → `:156 call l_ancopt`（`relaxation_engine.f90:400`） | **否** ✅ |
| 3 | `--opt --method fire`（`inertial`） | `= p_engine_inertial`（`:79`）→ `geoopt_driver.f90:169` → `:170 call fire`（`relaxation_engine.f90:131`） | **否** ✅ |
| 4 | `--opt --method pbc_lbfgs` | `= p_engine_pbc_lbfgs`（`:80`）→ `geoopt_driver.f90:159` → `:163 call relax_pbc`（`lbfgs_anc/driver.f90:39`） | **否** ✅ |
| 5 | `--ohess --method <1..4>` | runtyp `p_run_ohess` 命中同一 case（`11:1298`） | **否** ✅ |
| 6 | `--method ancopt --opt`（反序） | 尾归一位于 flag 循环之后（`main.F90:3881-3891`），`set%runtyp` 已是 `p_run_opt` | **否** ✅ |
| 7 | `--lopt --method ancopt` | `case default` → `env%error`（**设计要求**；规则合理，见下） | 设计如此 |
| 9/10 | `--lopt --method dimer` / 无任务旗标 | 套件 setter 返回 0 → error（`settings.f90:1112-1135` 只认 6 名） | 设计如此 |

**关键负向验证（第 2 轮的两条死路都消失）**：出口 1-6 中 `landscape_opt_algorithm_from_name`（`settings.f90:1112`，`case default → 0` 在 `:1130-1131`）**根本不被调用**；`select case (set%runtyp)` 的两个 `default`（原生名+非 opt/ohess、套件名+无任务）都只在设计要求的报错上命中。第 2 轮 HIGH-1 的"两条顺序都死"不再成立 ✅。

**顺序无关性成立**，且有三重证据：(a) 第 1 段只存字符串（`11:1200-1206`），不读 `set%runtyp`；(b) 第 2 段在 `call args%nextFlag(flag)` 循环之后（`main.F90:3881-3891`，与 `--lscan-step` 归一同一位置）；(c) 同惯例先例已在库内：`--ljson` 的检查在 `main.F90:981` 且注释明写"the flag and the run type may be given in either order"（`:975-980`）。

**与 `set_runtyp` 锁共存**：锁在 `set_module.f90:1033-1037`（`logical,save :: set1`，二次调用 `raise('S',...)` 后 `return`）。`--method` 的新 case 不含 `set_runtyp`；库里带 `set_runtyp` 的 case 是 `--lopt-engine` 等（`main.F90:2249/2253/…`），设计明确保留（BC-2）——两者无交集 ✅。

**`--lopt --method ancopt` 规则判定**：**合理**。理由 (a)"显式 `--lopt` + 要原生引擎自相矛盾"与 §4.2 的容忍集合一致；(c) 与 §4.4 的统一规则一致；(d) 报错点名 `--opt` 可操作。反例成本论证（要绕开 `set_runtyp` 锁）成立（`set_module.f90:1034-1036`）。

**扣分（新 MEDIUM-1）**：`11:880-889` 把标志声明为 `"由 parseArguments 的解析尾归一写入（§4.7）并作为 `intent(out)` 参数回传"`，`11:895-916` 给出 `integer :: landscape_native_engine = 0`；而第 2 段伪代码（`11:1225`）只在 `if (allocated(landscape_method_name))` **内部**赋值，**没有** `else landscape_native_engine = 0`。`parseArguments` 的同类 dummy 全部是 `intent(out)`（`main.F90:1493/1496/1499/1502/1505`），因此**没有 `--method` 的每一次运行（含 `--lopt`/`--opt`/`--lscan`/未改派 runtype）都会读未定义值**，`native_engine /= 0` 不可预测 ⇒ 分派随机化。最小修法：第 2 段首行无条件 `landscape_native_engine = 0`（或改 `intent(inout)`），并加一条"`--lopt`（无 `--method`）必须走套件"的断言。

## 3. H-2：谓词覆盖与守卫触发（我构造的 4 个组合）

| 组合 | 新设计走哪条分支（代码层判定） | 与设计声称一致？ |
|---|---|---|
| `--opt --method fire` + `$scan` | 尾归一 `native_engine = p_engine_inertial ≠ 0` → `effective_landscape_task = 0` → `landscape_is_suite_run` 假 ⇒ `main.F90:491-510` 守卫**跳过**；`:931` 原生块执行，`:943-945 if (nscan > 0) call relaxed_scan` ⇒ `RELAXED SCAN` + `xtbscan.log` | ✅ 与 `11:1350` 一致 |
| `--lopt --method ancopt` + `$scan` | 尾归一即 `env%error`（出口 7），早于 `:491-510`（`env%checkpoint` 在 `main.F90:330`） | ✅ |
| `--ohess --method pbc_lbfgs` + 周期 | `native_engine = 4 ≠ 0` → 守卫不触发 → 原生 `:931`；仅 GFN-FF 时 `:933-937` 强制同级引擎；`numhess` 因 `mol%npbc > 0` 报 `Phonon calculations under PBC are not implemented`（**今天同样如此**） | ✅ 无新缺陷 |
| `--ohess --method ancopt` + 周期 | 同上（GFN-FF）：原生 `pbc_lbfgs` + 原生 `main_freq` | ✅ 与 `11:1385-1387` 的自述一致 |

⇒ **H-2 闭合**：谓词单一（`landscape_native_engine`，取值域 = `set_module.f90:1888-1891` 的 7 个键字面 / 4 个 `p_engine_*`），守卫统一读 `landscape_is_suite_run`（`11:911-917`），且**守卫不会对任何原生出口误报**。测试也已按"谓词退化为 `== p_engine_rf` 必红"给了反例（`11:1350/1351/1352`）。

## 4. M-1 / M-2 / M-3 / M-4 判定

- **M-1 = 真修（但留痕段落使自检失效）**：`11:1471` 表头含"**R4 后（§3.9）**"列、`11:1487-1491` 结论拆成"HEAD 现状 / R4 后"两段并明写"3 个缺失只描述 HEAD 现状"、`11:1493-1496` 留痕；与 `11:121`（BC-3"集合不小"）、`11:2090`（B 类清零）现在**一致** ✅。`13:88-92` 也留痕 ✅。**但**见 §7 的 MEDIUM-2。
- **M-2 = 真闭合**：C7 在 `11:2094-2105`（现象/影响/缓解/爆炸半径/可避免），计数在 `11:81 / 662 / 2152 / 13:64` 四处一致（16）；"为何不收窄"给出 3 条论证 + `grep` 实测。我复核 `grep -rn '\$opt' test/unit/` = **0 命中**（把 `$opt` 当字面量搜 `test/unit/` 无匹配）✅。
- **M-3 = 部分闭合（HIGH-1）**：`--opt` 半边给了 `main.F90:931 → if (anyopt .and. landscape_native_engine /= 0)`、`anyopt` 另两读点 `:321/:326` 有意保留、以及"只跑一次"的两个 CLI 断言（`11:1360-1362`）✅；**`--ohess` 半边缺失**（见 §7 HIGH-1）。
- **M-4 = 真闭合**：`11:1857-1870` 拆 S/N 两集合；S = "`--l` 开头或 `--method`" 的门槛差集必须 = 0，N 只打印。**我独立核实 S 是纯套件集合**：`02-cli-audit.md:306-313` 的 30 个原生未文档化旗标与 `:322-326` 的 4 个（`--ithr`/`--xparam`/`-s|--silent`）**没有一个以 `--l` 开头**（清单里只有 `--ljson`/`--lopt*`/`--lscan*`/`--lts*`/`--lirc*`/`--lvib*` 是 `--l*`，而它们在 `xhelp.f90` 里也有：`02:302` "套件部分双向差集 0"）⇒ 阶段 1 门槛可达 ✅。

## 5. 破坏性计数自洽性

| 位置 | 计数 | 与清单对得上？ |
|---|---|---|
| `11:81`（§0 摘要） | A3+B0+C7+D1+E1+F3+G1 = 16 | ✅ 算术正确 |
| `11:662`（§3.6 表） | **16**（R23 后） | ✅ |
| `11:2056-2058`（§10 头） | R19 六类 + R23 补丁 C 6→7、15→16 | ✅（R19 的行是历史行，紧随其后被 R23 行纠正，可接受） |
| `11:2094-2105` + `11:2147-2152` | C1..C7 具名 7 条，汇总 16 | ✅ |
| `13:60-64` | 同样 16，逐类拆分 | ✅ |
| `§1.2 BC-3` / `§5.4` / `§10 B` | "集合不小" / "HEAD 现状 vs R4 后" / B=0 | ✅ 三处一致 |

⇒ **计数自洽**（这是我本轮唯一确认"无异议"的一项计数）。附：`--method` 取值域计数**不自洽**，见 LOW-1。

## 6. 其余 17 条已闭合项的回归检查

我抽核了第 2 轮已判"已改"的位置，**除下列 2 处均为真**：

- 行号勘误 12+ 处**全部命中**（证据见摘要 11；特别是我核到 `set_module.f90:797` 正是 `case('opt'); call rdblock(env,set_opt,…)`，`§3.8(c)` 的检测点正确；`:1890` 确为 `pbc_lbfgs`、`:1891` 确为 `inertial|fire`，L-2 订正正确；`compliance.f90:287` 确为裸 `open(..., "compliance.dat", status="replace")`）。
- `§3.9` 的 L-3 补点 `optimizer.f90:801` 正确（`call writeMolecule(mol, ilog, format=fileType%xyz, energy=…, gnorm=…, number=iter)`）。
- `§4.1` 的文件误归属订正正确（`fire`=`relaxation_engine.f90:131`、`l_ancopt`=`:400`）。
- `§3.5` 的 L-5 实现点正确（`engine%acc = set%acc` 无条件同步在 `main.F90:996`；`case('-a','--acc')` 在 `:1665`）。
- `§8.4`/`§8.6`/`§9.1` 已按 R25 改写；`§4.7.1` 的 5 个判别 token **全部命中源码**（`optimizer.f90:392`、`relaxation_engine.f90:298/594`、`lbfgs_anc/driver.f90:254`、`tasks/opt.f90:108`）。
- **回归（真）**：`11:2183`（§12 U1）与 `11:2322`（§14.2 M8 行）仍写"**两个逻辑标志**"，与 `11:875-879` 的"旧稿的两个逻辑标志（`landscape_native_ancopt`/`landscape_opt_alias`）**作废**"+ R22 的单一 `landscape_native_engine` 直接矛盾 ⇒ **MEDIUM-3**。
- **回归（真）**：`13:18` 的 R1 行仍写"不合并 runtyp + 逻辑标志 + 谓词"（单数，勉强）；同一文件 `§5.3` 的口径已改对，故只算 LOW/不单列（并入 MEDIUM-3 的修法：三处一并改成单一标志）。

## 7. 本轮新发现（逐条：位置 / 证据 / 最小修法）

### HIGH

**HIGH-1（阻断阶段 3 的 `--ohess` 半边）：`--ohess`(套件) 会跑两遍 Hessian/频率**
- 证据：`--ohess`(套件) 的 runtyp **仍是 `p_run_ohess`**（`11:872-875` 决策 1），而
  `main.F90:1156` 的 `if (runtyp == hess .or. ohess .or. bhess)` → `:1170 call numhess(...)`（原生 FD Hessian）、
  `main.F90:1282-1285` → `call main_freq(iprop, mol, chk%wfn, fres)`、
  `main.F90:270 anyhess = …`（`--ohess` ⇒ 真）被 `:1324 call write_energy(env%unit, res, fres, anyhess)` 使用。
  设计只抑制 `:931`（`11:938` 读点 #4、`11:954` "抑制只加在 `:931`"），读点表 #6（`11:940`）只说"接 vib 链"，**没有**抑制 `:1156/:1282-1285`。
  ⇒ 按字面实施：套件 opt + 套件 vib **加上** 原生 numhess + 原生 main_freq，`hessian`/`vibspectrum`/`g98.out`/`xtbhess.xyz`/`compliance.dat` 各写两遍（后写者覆盖），成本翻倍。
- 附加陷阱：若实施者**只**抑制 `:1156` 而忘了 `:270 anyhess`，`:1324` 会用未分配的 `fres` 打印频率块（半修即崩）。
- 最小修法：把 `:1156` 与 `:1282-1285` 也纳入 `landscape_ohess_chain` 的抑制集合（`if (… .and. .not. landscape_ohess_chain(...))`），并让 `anyhess`（`:270`）对套件 `--ohess` 为假（或由套件 vib 链填充 `fres`）；补一条"`--ohess` 只跑一次"的 CLI 断言（判别 token：原生 `ANC micro-cycles` 出现 1 次 + 套件 `landscape: …` 出现 1 次 + `vibspectrum` 只由套件写）。

### MEDIUM

**MEDIUM-1：`landscape_native_engine` 在无 `--method` 时未定义**（见 §2 末）。位置 `11:880-889`（`intent(out)` 声明）与 `11:1225-1247`（第 2 段只在 `if (allocated(landscape_method_name))` 内赋值）；对照 `main.F90:1493-1505` 的 `intent(out)` 惯例。修法：第 2 段首行 `landscape_native_engine = 0`（1 行），并加"`--lopt`（无 `--method`）走套件"的断言。

**MEDIUM-2：`13-*.md §6` 自检是**假的**（与 M-1 同类纪律问题）**
- `13:109`：``$ grep -c "R4 后补齐" docs/_simplify-recon/11-cli-redesign.md   # 0（且不再声称已加）``
- 实测（我用 grep 核过）：该字符串在 `11-*.md` 出现 **3 次**——`11:58`（R26 行引述旧声称）、`11:1495`（§5.4 留痕）、`11:2420`（§15 纪律声明）。**正是本轮的留痕写法自己制造了这 3 处**，于是"0 命中"不再成立。`11:58/:2392` 里"`grep "R4 后补齐"` = **0 命中**"的表述同样已失真（0 是"R1 版 §2 那句声称"的计数，不是现在全文的计数）。
- 最小修法：把自检改成可核形式，例如 `# 该字样现仅出现在 3 处留痕段落（11:58/1495/2420）；R1 版 §2 的原声称已删除`，或 grep 一个只属于原声称的字串（如 `13-*.md R1 版 §2 的"§5.4/§5.5（R4/R12/R5）…"`）。**建议同时删掉无法在只读下核实的 `wc -l` 数字**（我按行号推算 11-*.md 末行 ≈ 2422，与它写的 2423 差 1；13-*.md 亦无法用只读工具核实）。

**MEDIUM-3：R22 的改写留下两处指向已作废机制的残留（本轮引入的回归）**
- `11:2183`（§12 U1）：`保留 p_run_opt/p_run_ohess + 两个逻辑标志`；
- `11:2322`（§14.2 M8 行）：`已改：不合并 runtyp + 两个逻辑标志 + 谓词`；
- 对照 `11:875-879`：`旧稿的两个逻辑标志（landscape_native_ancopt / landscape_opt_alias）**作废**`。
- 影响：不阻塞实现（§3.11 正文是权威），但**这是"17 条已闭合项被本轮改动破坏"的实例**，且 §14 是下一轮对账的入口。修法：两处改成"单一 `landscape_native_engine`（0 = 套件）"。

### LOW

| # | 位置 | 证据 | 最小修法 |
|---|---|---|---|
| L-1 | `11:1015 / 1035-1036 / 1363 / 1987` | 声称"4 个引擎 / **8 个拼写**"、"18 套件名 + 8 原生拼写 = **26**"，但 `11:1035` 自己枚举的是 `ancopt\|rf`、`lancopt\|l-ancopt`、`fire\|inertial`、`pbc_lbfgs` = **7** 个（`set_module.f90:1888-1891` 的 7 个键里 `lbfgs` 被有意排除，见 `11:1247-1248`） | 全处改 **7 拼写 / 25**（或删掉总数句） |
| L-2 | `11:688`（§3.7） | 写"原生 `--ohess` 本身就是 `main_geometry` + `main_freq` 两次调用（`main.F90:1282` 与 `:1287`）"，实际是 `:1279 call main_geometry` 与 `:1284 call main_freq`（`11:946` 引对了） | 改 `:1279`/`:1284` |
| L-3 | `11:1206` vs `11:1312` | 同一节内 "（n>50 0 → lbfgs）" vs "n > 500 → `p_engine_lbfgs`"；`defaults.f90:43` 是 `mol%n > 500` | 统一为 `n > 500` |
| L-4 | `11:938`（读点表）+"按这张表搜一遍即可保证无遗漏" | 漏列 4 个原生读者：`main.F90:1324`（`anyhess` 写能量）、`:1310-1320`（原生 `xtbopt.xyz` 二次写，内容因 `tasks/opt.f90:148 geometry_unpack(xfinal, mol%xyz)` 而相同，属重复写+重复提示）、`:1276-1280 main_geometry`、`:4065-4068`（`prtiming(3,'ANC optimizer')` 计时标签在改派后成为误标）。另：`§3.8(c)` 说守卫"与 (a) 同一位置"（`:491-510`）而读点表 #2/#3 说"与 (a)(b) 同一位置"（`:931` 之前） | 读点表补 4 行；统一 (b)/(c) 的位置措辞（两处都在分派前，功能等价） |
| L-5 | `11:617-645`（§3.5 映射表） | `--opt <LEVEL>` → 套件档的**映射实现点未给**（`--opt` 的 level 落在 `set%optset%optlev`，`set_module.f90:1811`，CLI 写点 `main.F90:2153-2157`）；而 `11:1355` 的 `xtb/landscape-method-level-bridge` 依赖该映射可核 | 补一句实现点（套件分派处读 `set%optset%optlev` → `set_conv_level` + `[NOTICE]`） |
| L-6 | `11:956`（§3.11 M-3 段） | 写"套件无 CPCM-X/PTB 路径"，但 `main.F90` 的 CPCM-X post-SCF 块（`:1197-1216`：`cpx%setup` / `cpx%calc_solv`）**不受 runtyp 守卫**，`--lopt --cpx <solvent>` 今天确实会算（`--opt` 因 `:321 anyopt` 而 terminate） | 措辞改为"套件分派路径不触发 `:321/:326` 的 terminate，行为与今天一致"；行为本身无需改 |
| L-7 | `11:1348` | `xtb/landscape-method-native-level` 要求 ">500 原子 fixture"（`defaults.f90:43`）；GFN2 上 500+ 原子在本项目的 CLI 测试预算内不可行（AGENTS §6.8 的 taxol 113 原子已反扩展） | 明确用 **GFN-FF** 501 原子非周期 fixture（不触发 `:933-937` 的强制），断言 `ANC micro-cycles` 且不含 `L-ANC optimizer` |

### INFO

- **INFO-1**：`11:2207` 的 U15（`--method <native>` 与 `$opt engine=` 同时给出时是否打 `[WARNING]`）是诚实的开放项，**接受**；建议取 (b)（在 `set_opt` 的 `engine` 分支里当 `allocated(set%opt_engine)` 已真时打 warning，一次改动、不改行为），并把它并入 `§3.8(c)` 的守卫族。
- **INFO-2**：I-2 的编号重建规则（`11:2286-2296`）已生效：我用"先数内容、再对编号"对账第 2 轮的 24 条，**没有出现计数争用**；建议下一轮沿用。本轮对第 2 轮 L-1..L-6/I-1/I-2 的处置逐条核过，**均为真改或不适用**（L-1→`11:1413` 已改 error；L-2→6 处全部命中；L-3→`11:784`；L-4→`11:645`+`11:1546`；L-5→`11:617-622`;L-6→`11:2407-2409`；I-1→`11:2378` 的 2 命中我复核为 `main.F90:506`/`xhelp.f90:286` ✓；I-2→`11:2293-2296`）。

## 8. 逐条处置表（第 2 轮 24 条 + 本轮新增）

| 第 2 轮 ID | 本轮（第 3 轮）判定 | 证据 |
|---|---|---|
| H-1 | **闭合**（附 MEDIUM-1 一行必须补） | `11:1165-1300`；对照 `settings.f90:1112-1135`、`set_module.f90:1888-1891`、`geoopt_driver.f90:148-172`、`defaults.f90:41-46` |
| H-2 | **闭合** | `11:865-917`、`11:711-720`、`11:1350-1352`；4 组合代入见本报告 §3 |
| M-1 | **闭合**；但产生新不可核声称 | `11:1471/1487-1496`、`13:88-92`；**反例** `13:109`（grep = 3 非 0） |
| M-2 | **闭合** | `11:2094-2105`、计数 16（`11:81/662/2152`、`13:64`） |
| M-3 | **部分闭合** ⇒ **HIGH-1** | `11:938/949-958`（只 `:931`）；`main.F90:1156/1170/1282-1285/270/1324` 未覆盖 |
| M-4 | **闭合** | `11:1857-1870`；`02-cli-audit.md:306-326`（30+4 无 `--l` 前缀） |
| L-1…L-6、I-1、I-2 | **闭合 / 已核** | 见 §7 INFO-2 |
| round-2「需运行验证」5 条 | 仍**未执行**（我只读） | 见 §9 |
| round-2「需用户确认」3 条 | C7 作用域、`--lopt-level` 口径：设计**自行决定并登记**（`11:2100-2105`、`11:645`）；第 3 项已决定计入 16 | 需用户点头（非阻塞） |

## 9. 需运行验证（`OMP_NUM_THREADS=1`，**只用 `-R landscape`/`--strict` 无关子集，绝不跑全量**）

1. `git diff --stat -- src test`（应空）与 `git status --porcelain docs/_simplify-recon/`。
2. `grep -c "R4 后补齐" docs/_simplify-recon/11-cli-redesign.md` → 期望 **3**（证伪 `13:109` 的 0）；`wc -l` 两文件（核 `13:108-110`）。
3. §13c #8 的四个 token 复现：`--opt --input <$opt engine=rf|lbfgs|fire|pbc_lbfgs>`（H-1/H-2 全部 CLI 断言的基线；我只读无法复跑）。
4. §13c #9/#11/#12 的"只跑一次"与 C7 爆炸半径（`--opt --ljson`、`--lopt --input <$opt>`）。
5. `grep -rn '\$opt' test/unit/`（我复核 = 0）+ `grep -rn 'use --opt\|--opt to run' src/ man/`（我复核 = `main.F90:506`/`xhelp.f90:286`）。

## 10. 需向用户确认

1. **C7 的作用域**（全量套件 run type vs 只 `--opt`）——设计已选全量并计 16 条，须用户确认（第 2 轮复核亦列为确认项；不接受则 H4 只对 `--opt` 报错，计数回到 15）。
2. **`--lopt-level` 不收上游 8 档名**（`11:645`，保持现状、非破坏）——确认即可。
3. **`--ohess` 的语义二选一**（HIGH-1 的修法方向）：(i) 套件 vib 链 + 抑制原生 `numhess/main_freq/anyhess`（与 §3.9 的 R4/B=0 叙述一致），还是 (ii) 保留原生 Hessian、取消套件 vib 链（则 §3.9/§5.4 的"套件补写 `compliance.dat`"叙述要重写）。**这是阶段 3 的前置决策**。

## 11. 阶段判定

| 阶段 | 判定 | 依据 |
|---|---|---|
| **阶段 1** | **可实施** | M-4（`11:1857-1870`）与 M-1（`11:1471/1487-1496`）已修；集合 S 经我独立核实为纯套件集合 ⇒ "新增测试全绿"与"差集=0"自洽；LOW-4 建议随手补读点表，不阻塞 |
| **阶段 2** | **可实施** | 与 `--opt` 决策无关（`11:976-978`）；`--method` 的套件侧机制（第 1/3 段 + 尾归一 else 分支）我已逐行核对可用 |
| **阶段 3** | **`--opt` 部分可实施；`--ohess` 部分不可** | 前置：(a) 在 `11:1225` 首行补 `landscape_native_engine = 0`（MEDIUM-1）；(b) 把 `main.F90:1156/1282-1285/270` 纳入抑制规格并补"只跑一次"测试（HIGH-1）；(c) 修 MEDIUM-2/MEDIUM-3 的文档矛盾。其余（H-1/H-2/M-2 已闭合）不构成阻塞 |

---

### 附：`13-*.md` 声称逐句核对（本轮重点，因它上轮因过度声称被点名）

| `13-*.md` 行 | 声称 | 我的核实 |
|---|---|---|
| `13:33` | 登记 C7；计数 15→16；爆炸半径实测 0 | ✅ 真（`11:2094-2105`、`11:81`、`grep '\$opt' test/unit/` = 0） |
| `13:37` | 6 处行号订正 + `relaxation_engine.f90:400/131` | ✅ 真（逐个核过） |
| `13:39-45` | H-1 用两段归一 + 逐行证明 | ⚠️ **部分**：证明正确，但漏了 `intent(out)` 初始化（MEDIUM-1） |
| `13:40` | M-3 已修（`main.F90:931`） | ⚠️ **不完整**：只覆盖 `--opt`；`--ohess` 的原生 numhess/main_freq/anyhess 未指定（HIGH-1） |
| `13:42` | M-1 真改 §5.4 并留痕 | ✅ 真（`11:1471/1487-1496`） |
| `13:47-50` | 阶段 1 解除、阶段 2 解除、阶段 3"设计层解除、待裁定" | ✅ 措辞**恰当**（没有再声称"已通过复核"）——这是上轮过度声称的**正确矫正** |
| `13:91-92` | 旧记录错称已改、实为未改，并留痕 | ✅ 真（这正是本轮 §7 发现的措辞） |
| `13:109` | `grep -c "R4 后补齐" 11-*.md # 0` | ❌ **假**（实为 3；MEDIUM-2） |
| `13:110` | `wc -l 11-*.md = 2423` | ⚠️ 无法在只读下核实，按行号推算 ≈2422（差 1）；建议粘贴真实输出 |