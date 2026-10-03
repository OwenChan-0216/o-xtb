## 摘要（≤30 行）

1. **结论：接受（Accept）**。CRITICAL 0 / HIGH 0 / MEDIUM 0 / **LOW 3** / INFO 0。第 3 轮的 1 HIGH + 4 MEDIUM + 7 LOW + 2 INFO 已闭合，U15/U16 已定案。
2. **HIGH-1 真闭合**：我逐行走读 `main.F90`。T1 `:1156`（块内 `:1170 numhess`）、T2 `:1282`（块内 `:1284 main_freq`）换 `landscape_native_hessian_path` 后，套件 `--ohess`（`native_engine=0`）⇒ `.false.` ⇒ 两处都跳过；原生 `--ohess --method ancopt`（`=p_engine_rf`）⇒ `.true.` ⇒ 两处都执行。**两侧都被区分**，不是一刀切。
3. **T3 的偏离是对的**：`anyhess`（`:270`）不改、由 `fres` 桥填容器。我核了 `property.F90:36-57`：`hess=.true.` 打印 `etot+htot`/`etot+gtot`，而 `results.f90:80-89` 的 `enthalpy/gibbs` 是**总数** ⇒ 桥里减掉 `vib%energy` 的算法正确。桥的 `res` 写回位置实测 `:1005`（设计写 `:1003-1005`）、`end if :1008` ✓。
4. **第 4 个触发点：无（计算层）**。我 grep 了全部 `p_run_ohess`/`anyhess`/`anyopt`：做重活只有 `numhess`/`main_freq`；`:271 if(anyhess)` 块只做配置（O1NumHess/PTB），`:465/:821` 仅 `bhess`。**但读点表漏了 `main.F90:4084`**（`analytical hessian` 计时标签，同一 runtyp 三元）⇒ **LOW-1**。
5. **MEDIUM-1 闭合**（§4.7 第 0 段 + §3.11.2 八行表）。`set_runtyp` 锁（`set_module.f90:1034-1038` + `:1105 set1=.false.`）与 `intent(out)` 惯例核对成立。**但表漏了 `%algorithm_source`**（本设计新引入、`grep src/` = 0 命中）⇒ **LOW-3**。
6. **MEDIUM-2 闭合且可核**（我按命令逻辑逐行数过）：11-*.md `grep -c "R4 后补"` = **6**（58/1655/2571/2599/2669/2687），**门槛（未标记）= 0**；13-*.md = **10**（118/119/129/152/158/159/160/174/176/184），门槛 = **0**。数字属实。复核"3"与设计"实测 4"的差异与复核自身 §7 引 `11:2392` 一致，可辩护。
7. **MEDIUM-3 闭合**：`两个逻辑标志` 在 11-*.md 只剩作废/订正/自检句（7 处，门槛 0）；`11:2358`(U1)/`11:2501`(M8)/`13:20` 均已改。
8. **MEDIUM-4、LOW-1..7、INFO-1/2** 逐条处置到位（我核了 7/25 拼写、`defaults.f90:43 n>500`、读点表 #10-15、`set_module.f90:797/1885`、`vib/numhess.f90:111-116`、`relax_scan.f90:532-533/549-551/556`、`CMakeLists.txt:658-669`）。**LOW-2**：两处行号引错（`vib.f90:118`→实为 **124**；`:155`→实为 **152**）。
9. **计数自洽**：§0/§3.6/§10/`13§3`/§16.9 全 = **16**（A3+B0+C7+D1+E1+F3+G1）；§1.2 BC-3 / §5.4 两段 / §10 B=0 三处口径一致。
10. **只改 docs**：`watchdog_diff --stat` 无跟踪文件改动；未跟踪仅 `docs/_simplify-recon/*.md` + `w*.js` ⇒ `git diff --stat -- src test man` 为空 ✓。
11. **阶段判定**：阶段 1 **可实施**；阶段 2 **可实施**；阶段 3 `--opt` **可实施**；阶段 3 `--ohess` **可实施**（HIGH-1 闭合，前置 = R30 一行 + R21 原生分支同次落地）。
12. 需运行验证：§16.4/§13 的 token 计数（4-13 行）我无法复跑（无 shell）；建议实施者在阶段 3 落地那一轮贴原始输出。

---

# 16 — W2 CLI 重设计（第 4 轮）独立复核报告

> 对象：`docs/_simplify-recon/11-cli-redesign.md`（2851 行）、`13-cli-redesign-revision.md`（191 行）、依据 `15-w2-review-round3.md`。
> HEAD `bdd8eb8`。**本轮 read-only（无 shell、无编辑）**：所有"实测"未复跑（标未复跑），代码断言逐条读源码核过。
> 计数：CRITICAL 0 / HIGH 0 / MEDIUM 0 / LOW 3 / INFO 0。

## 1. 结论

**接受。** 第 3 轮的 **HIGH-1 真闭合**（三个触发点逐个给判据/位置/测试，且我逐个代入验证生效），**MEDIUM-1..4 闭合**，**7 条 LOW 全部有处置**，**INFO-1/2 已定案**（U15 = 打 `[WARNING]`、U16 = 允许不加警告）。本轮只新增 **3 条 LOW（report-only）**：读点表仍漏 1 个读者（`:4084`）、三处行号引错、状态位表漏 1 个新字段。**均不阻塞任何阶段**。

## 2. HIGH-1 是否真闭合（我自己的走读）

### 2.1 三个触发点代入

| 触发点（HEAD 实测行号） | 现状判据 | 设计判据 | 套件 `--ohess`（`native_engine=0`） | 原生 `--ohess --method ancopt`（`=1`） |
|---|---|---|---|---|
| T1 `main.F90:1156`（`:1170 call numhess`） | `runtyp==hess/ohess/bhess` | `landscape_native_hessian_path` | `.false.` ⇒ **跳过** ✓ | `.true.` ⇒ **执行** ✓ |
| T2 `main.F90:1282`（`:1283 header`、`:1284 main_freq`） | 同上 | 同上 | `.false.` ⇒ **跳过** ✓ | `.true.` ⇒ **执行** ✓ |
| T3 `main.F90:270 anyhess`（读者 `:1304`/`json.F90:102,111`/`:1324`） | 同上 | **不改**，由 `fres` 桥填 | `anyhess` 真 + 桥填 ⇒ 输出同形 ✓ | 真 + 原生 `numhess` 填 ✓ |

- **(a)** 套件 `--ohess` 不再触发原生 Hessian/频率：`numhess` 与 `main_freq` 是唯一的重活承担者（我 grep 了 `numhess`/`main_freq` 的全部调用点，各只有一处，分别在 T1/T2 内）⇒ 只跑一遍。
- **(b)** 原生侧仍触发：判据输入是**同一个** `landscape_native_engine`，原生值 ≠ 0 ⇒ 双向区分成立。
- **(c)** **第 4 个触发点（计算层）不存在**。全部 `p_run_ohess` 使用点（grep `src/`）：`main.F90:270/317/629/1156/1276/1282/1305/1310/4065/4084` + `setparam.f90:202` + `set_module.f90:1055`。其中 `:271 if(anyhess)` 块**只做配置**（O1NumHess 有效性、PTB hessian 切换），`:465/:821` 只对 `p_run_bhess`，`:629` 是参数文件选择，`:317` 是 `anyopt`（由 M-3 的 `:931` 抑制覆盖）。
- **我在 2.1 之外单独查了 `anyopt` 的全部读点**：`:317`（定义）、`:321`（CPCM-X terminate，L-6 有意保留）、`:326`（PTB terminate，同上）、`:481-482`（注释）、`:931`（M-3 抑制）。无遗漏。

### 2.2 `fres` 桥的正确性

`property.F90:36-57`：`hess=.true.` 时打印 `frqres%etot`（TOTAL ENERGY）、`frqres%etot+frqres%htot`（TOTAL ENTHALPY）、`frqres%etot+frqres%gtot`（TOTAL FREE ENERGY）、`frqres%gnorm`。
`results.f90:80-89`：`landscape_vib_result%enthalpy/gibbs` 的文档明写"**电子能 + 热贡献总数**"。
⇒ 桥的 `htot = enthalpy - energy`、`gtot = gibbs - energy`、`etot = vib%energy` **算术正确**。

### 2.3 自证表的行号核对（我逐条核过）

| 设计引用 | 实际 | 判定 |
|---|---|---|
| T1 `:1156`（三元 `if`） | `:1156` ✓ | 命中 |
| T1 块内 `:1170 call numhess` | `:1170` ✓（`start_timing(5)` 在 `:1169`） | 命中 |
| T2 `:1282-1285` | `:1282 if` / `:1283 generic_header` / `:1284 main_freq` ✓ | 命中 |
| `:1305` 属性文件 `write_energy` | `:1304 call write_energy(...)`、`:1305` 是该调用的第三实参行 ✓ | 命中 |
| `:1310-1320` `xtbopt.xyz` 二次写 | `:1310 if` … `:1315 generateFileName` ✓ | 命中 |
| `:4065-4071` 计时标签 | `:4065 if` … `:4067 prtiming(3,'ANC optimizer')`、`:4069 landscape optimizer` ✓ | 命中 |
| T3 `:270` | `:270` ✓ | 命中 |
| 桥位置 `:989-1008`、`res` 写回 `:1003-1005`、`end if :1008` | `:989` 块 / `:1005 res%e_total=lres%energy` / `:1007 checkpoint` / `:1008 end if` | **`res` 写回偏 2 行**（LOW-2） |
| 桥字段 `results.f90:279-322`（`landscape_result`）、`:60-106`（`landscape_vib_result`） | `landscape_result` 起于 `:279` ✓；`landscape_vib_result` 起于 `:62`（`end type` 在 `:106`）✓ | 命中 |
| `tasks/vib.f90:155 landscape_vib_hessian` | 实为 **`:152`** | **错**（LOW-2） |
| `data.F90:105-129` 默认初值、`json.F90:111 n3true` 守卫 | 与 M7 记录一致 | 接受（未复跑） |
| `mctc_timings.f90:161-163`（`init_timing` 用 `source=0.0_wp`） | ✓ 我读过 ⇒ 未启动的 slot 是 0，不是未定义 | 支撑 LOW-1 |

## 3. MEDIUM-1（标志初值）

- **闭合**：§4.7 新增**第 0 段**——`parseArguments` 的 flag 循环（`main.F90:1574 call args%nextFlag`）**之前**无条件 `landscape_native_engine = 0`；§3.11.2 给出八行"变量名/声明处/初值/何时被写/读到未定义值的可能性"表；并诚实标注"`intent(out)` 的未定义值在 `-O2` 下常表现为 0，运行时测不准 ⇒ 只能静态可核（`grep`）"。
- 我核了 `intent(out)` 惯例（`main.F90:1493-1505` 同型）与 `set_runtyp` 锁（`set_module.f90:1034-1035` `if (.not.set1) … return`；`:1105 set1=.false.`）⇒ 设计的两条断言都成立。
- **缺口（LOW-3）**：§3.11.2 自称覆盖"**全部**新增状态位"，但 §4.7 第 3 段的共享 setter **新引入** `lset%algorithm_source`（及 lscan/lts/lirc 同型），而 `grep src/ algorithm_source` = **0 命中** ⇒ 它确实是新增字段，且**不在表内**。它 `character(:),allocatable`、只在 `allocated(...)` 下读 ⇒ 无未定义读风险，但该表（正是 MEDIUM-1 的交付物）不完整。

## 4. MEDIUM-2（假自检）

- **可核且属实。** 我按命令逻辑逐行判定（read/grep 工具，非 shell）：
  - 11-*.md 含 `R4 后补` 的行 = `58,1655,2571,2599,2669,2687` = **6**（与 §16.4 第 2 行、`13§6` 第 2 行的"6"一致）。
  - 该 6 行是否都含 `留痕|订正|错称|grep|复核|纪律|自检`：58 ✓、1655（含 `grep "R4 后补齐"`）✓、2571 ✓、2599 ✓、2669 ✓、2687 ✓ ⇒ **门槛 = 0** ✓。
  - 13-*.md 含该字样 10 行（118/119/129/152/158/159/160/174/176/184），逐行含标记 ⇒ **门槛 = 0** ✓。
  - `两个逻辑标志` 在 11-*.md 命中 **7** 处（62/893/2358/2501/2688/2727/2737），门槛 = 0 ✓（与 §16.4 第 3 行"原始命中 7"一致）。
- **留痕**到位：`13§5.5` 明写"此前的自检数字 0 是错的"；`13§6` 改成"命令/期望/实际"三列 + 原始输出块；`wc -l` 不再写死。
- **复核"3"与设计"实测 4"**：复核在其 §7 自己引用了 `11:2392`（§14.7 的 M-1 行），却把它排除在计数外 ⇒ 设计的"漏了 `11:2392`"可辩护。当前状态无法回放"追加前"，但**正式判据（门槛 = 0）我已独立验证为真**。

## 5. MEDIUM-3（作废机制残留）

- 我 grep 了两个文件：`两个逻辑标志` 仅出现在 **作废/订正/自检** 句（`11:893` 作废声明、`11:2358` U1、`11:2501` M8、`11:62` R32 记录、`11:2688/2727/2737` 自检）；`13:20`（R16 行）已改并注明订正。
- `landscape_native_ancopt`/`landscape_opt_alias` 仅出现在"旧写法 → 新写法"的历史/作废记录（5+1 处）⇒ **保留合理**。
- **无"现行"措辞残留** ⇒ **闭合**。

## 6. MEDIUM-4 + LOW 7 + INFO 2

| ID | 处置判定（我的核实） |
|---|---|
| **MEDIUM-4** | 设计按 I-2 规则把它映射为"复核对第 2 轮 M-4 的**重新确认**"（§16.0）⇒ **不适用，接受**。属编号口径判断，不与复核矛盾。 |
| **L-1** | **已改**：全篇已统一为 **7 个拼写 / 25 个拼写**（`11:1152/1172-1175/1523/2153-2154`，无残留"8 个"/"26"）✓ |
| **L-2** | **已改**：`§3.7` 现写 `main.F90:1279`（`main_geometry`）/`:1284`（`main_freq`）✓ |
| **L-3** | **已改**：`§4.7` 注释 `n > 500`，与 `defaults.f90:43` 一致 ✓ |
| **L-4** | **部分改**：读点表补了 **#10-15**（我逐行核过，均存在）；`(a)(b)(c)` 位置统一为 `:491-510`；`:1310-1320`/`:4065-4071` 入抑制集合；`:1276-1280` 保留并给理由。**但 `:4084` 仍漏**（LOW-1）。 |
| **L-5** | **已改**：`§3.5` 补 `set%optset%optlev` 写点（`main.F90:2153-2157` → `set_module.f90:1811`/`:1910-1928`）✓ |
| **L-6** | **已改**：措辞改为"改派不改变 `:321`/`:326` 两读点行为"✓ |
| **L-7** | **已改**：`§4.7.1` 的 `>500` fixture 改 **GFN-FF 501 原子非周期** ✓ |
| **INFO-1（U15）** | **已定 (b) 打 `[WARNING]`**：实现点 `set_module.f90:1884-1886`（我核过 `case('engine')` 在 `:1884`、`.not.allocated` 守卫在 `:1885`）✓ |
| **INFO-2（编号）** | **接受**：本轮沿用"先数内容、再对编号"✓ |
| **U16** | **已定：允许、不加警告**，4 条理由（含"同一语义两拼写不同行为"的反例）⇒ 合理 ✓ |
| **U17（新发现）** | 套件 + `--o1nh` 死旋钮：我核了 `main.F90:2181 set%o1numhess = .true.` 与 `vib/numhess.f90:111-116`（只读 `settings%engine%odlr`）⇒ **确实不同源**；登记为候选 C8（16→17，未定），**不阻塞** ✓ |

## 7. 阶段 1 工作清单（§17）可直接执行性

| 条目 | file:line 可核 | 验收/测试/反向突变 | 判定 |
|---|---|---|---|
| §17.1 冲突检测 | `main.F90:2154/2160/2166/2244/2296/2575/3318/3683` | 有 | **可执行**（附"同 typ 重复 = 无操作"的坑位说明） |
| §17.2 必填点名 | `relax_scan.f90:532-533/549-551/556` ✓；`CMakeLists.txt:658-663`、`:664-669` ✓ | 有 | **可执行** |
| §17.3 危险默认回显 | `vib.f90` 的 printlevel 块（**设计写 :118-136，实为 :123-135**，LOW-2） | 有 | **可执行**（行号需修） |
| §17.4 `--help` 双向 | 新建脚本 + CMake/meson 注册 | 有 | **可执行** |
| §17.5a `--strict` | `main.F90:1583`/`:608` ✓ | 有，**但方案二选一留给实施**（"移入解析循环"或"解析尾统一报"） | **半可执行**：一个显式待决点 |
| §17.5b 枚举转小写 | `settings.f90:1112/1229/1295/1497/1425` ✓ | 有 | **可执行** |
| §17.6 共同验收 | — | 有（含"贴前后输出"） | **可执行** |

> **"实施时才发现要先决定 X"的坑**：只有 §17.5a 一处（已明写"两者选一，实施时记入报告"）。其余条目已钉到行号+断言+反向突变。§17.1 另有一个必须记住的语义（同 typ 重复不得误报），已写在"注意"行。

## 8. 计数与口径自洽

| 位置 | 计数 | 我对账 |
|---|---|---|
| §0 摘要 | A3+B0+C7+D1+E1+F3+G1 = **16** | 算术正确 ✓ |
| §3.6 表 | **16**（R23 后） | ✓ |
| §10 汇总 | **16**（R29/R35 注：HIGH-1 不改契约 ⇒ 不加条） | ✓ |
| `13§3` | **16**（逐类拆分一致） | ✓ |
| §16.9 | **16**（候选 C8 ⇒ 17，未定） | ✓ |
| §1.2 BC-3 / §5.4 / §10 B | "集合不小" / "HEAD 现状 vs R4 后"两段 / B=0 | **三处一致** ✓ |

## 9. 本轮新发现（逐条：位置 / 证据 / 最小修法）

### LOW-1：读点表仍漏一个 `runtyp` 读者 —— `main.F90:4084`（计时标签）
- 证据：`main.F90:4084`：`if ((runtyp==hess) .or. (runtyp==ohess) .or. (runtyp==bhess)) then … prtiming(5,'analytical hessian')`（`:4086`）。
- 设计读点表 #14 只给 `:4065-4071`（`ANC optimizer`），§16.6 L-4 也只写 `:4065-4071` 入抑制集合。
- 后果（**非**重复计算，仅错标）：套件 `--ohess` 抑制 T1 后 `start_timing(5)`（`:1169`）不再执行，而 `:4084` 仍调 `prtiming(5,…)`；`init_timing` 用 `source=0.0_wp`（`mctc_timings.f90:161-163`）⇒ 打印一行 `analytical hessian time: … 0.000 sec`（若 `verbose`，`timing_cpu/timing_wall = 0/0 = NaN`）。它**否证**读点表的"按这张表搜一遍即可保证无遗漏"。
- 最小修法：读点表加一行 #16 = `main.F90:4084`，判据 `landscape_is_suite_run`（套件 ⇒ `landscape frequencies`，原生 ⇒ 保持原样）；或把 #14 的范围扩到 `:4065-4088`。

### LOW-2：三处 file:line 引错（可核但不实）
- `§16.4` 第 12 行与 `§17.3` 引 `tasks/vib.f90:118` / `:118-136`；实测 `if (settings%printlevel > 0)` 在 `:123`、`write "landscape: harmonic frequencies"` 在 **`:124`**、块尾 `:135`。
- `§3.11.1` 引 `tasks/vib.f90:155 landscape_vib_hessian`；实测 `call landscape_vib_hessian(...)` 在 **`:152`**。
- `§3.11.1` 引"`res` 写回 `:1003-1005`"；实测 `res%e_total = lres%energy` 在 **`:1005`**、`res%gnorm` 在 `:1006`（写回段是 `:1005-1006`；`end if :1008` 正确）。
- 最小修法：改为 `:123-135` / `:124` / `:152` / `:1005-1006`。（危害：低；但在一个以"可核"为主题的回合里出现，属同类纪律问题。）

### LOW-3：§3.11.2 状态位表漏 `lset%algorithm_source`
- 证据：§4.7 第 3 段的共享 setter 写 `lset%algorithm_source = owner`（`11:1427/1430`）；`grep algorithm_source src/` = **0 命中** ⇒ 新字段；§3.11.2 的八行表未列。
- 危害：无未定义读（`character(:),allocatable` + `allocated(...)` 守卫），但 MEDIUM-1 要求的"所有新增状态位"清单不完整。
- 最小修法：加一行（变量名 `lset/lsset/ltset/lircset%algorithm_source` / 声明处：对应 settings 类型 / 初值：未分配 / 何时写：共享 setter 的 `owner` 参数）。

## 10. 需运行验证（`OMP_NUM_THREADS=1`；**只 `-R landscape`，绝不跑全量**）

1. `git diff --stat -- src test man`（应空；我已用 `watchdog_diff` 侧证）。
2. `grep -c "R4 后补" docs/_simplify-recon/11-cli-redesign.md` → **6**；`13-cli-redesign-revision.md` → **10**；两条门槛命令 → **0**（我已按逻辑核对一致）。
3. `wc -l` 两文件（设计写 2851 / 191；我读至末尾约 2850±1，无法精确）。
4. `two逻辑标志` / `landscape_native_ancopt` 的 `grep -n` 命中清单（设计 §16.5 的表）。
5. §16.4 第 10/11 行的 token 复现：`--ohess normal`（`Numerical Hessian`=1、`Frequency Printout`=1、`ANC micro-cycles`=1、`TOTAL ENTHALPY`=1）与 `--lvib`（`landscape: harmonic frequencies`=1、`landscape engine: Hessians`=1、`Frequency Printout`=0、`TOTAL ENTHALPY`=0）——**本轮我无法复跑**，但每个 token 的源码出处我都核到（`header.f90:270`、`main.F90:1283`、`optimizer.f90:392`、`engine/engine.f90:804`、`tasks/vib.f90:124/228`）。
6. `grep -c "landscape engine: Hessians"`（`engine/engine.f90:804`，`%n_hess`）。
7. 阶段 3 落地那一轮：§3.11.1 的 4 条 CLI 测试的**改动前（红）/改动后（绿）**输出。

## 11. 需向用户确认

1. **C7 的作用域**（全量套件 run type vs 只 `--opt`）——设计已选全量、计入 16；需点头（不点头则回 15）。
2. **`--lopt-level` 不收上游 8 档名**——确认即非破坏。
3. **U17（候选 C8：套件 + `--o1nh` 是否改响亮报错）**——设计保留为开放项；决定后计数 16→17。

## 12. 阶段判定（本轮末）

| 阶段 | 判定 | 依据 |
|---|---|---|
| **阶段 1** | **可实施** | 第 3 轮已确认 + §17 工作清单（§17.5a 有一个显式待决点，不阻塞其余条目） |
| **阶段 2** | **可实施** | 复核确认；`--method` 套件侧机制逐行核过 |
| **阶段 3（`--opt` 半边）** | **可实施** | H-1/H-2/M-2 闭合 + `:931` 抑制指定 + `:1310-1320`/`:4065-4071` 入集合 |
| **阶段 3（`--ohess` 半边）** | **可实施（本轮解除）** | HIGH-1 三触发点逐个给判据/位置/测试 + 我代入验证生效；**前置 = R30 一行，与 R21 原生分支同次落地** |

> **实施建议（与设计一致）**：R30 的 `=0` 与 R22 的单一标志必须**首先**落地，否则后续每一步的判据都读未定义值。落地后建议顺带补 LOW-1（`:4084`）与 LOW-2/LOW-3，因为它们的成本是"几行文档"。

---