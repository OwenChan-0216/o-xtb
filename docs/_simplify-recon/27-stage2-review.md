# 阶段 2 独立复核（read-only）

## 摘要（≤30 行）

- **结论：有条件接受。阶段 2 的代码可以提交 git；但不能报告为「阶段 2 已完成」（§9.1/§9.2 的两项验收未满足）。阶段 3 可以开始**（先把下面 M1/M2 登记进设计文档，R39 的移除本就是阶段 3 第一项动作）。
- **边界（任务 1）：零越界。** diff 只动 `src/landscape/types/settings.f90`(4 个 `*_source`)、`src/prog/main.F90`、`src/xhelp.f90`、3 个测试文件、设计文档；`--opt/--ohess` 分派未动（`landscape_native_engine` 在 `xtbMain` **无任何读点**，`if (anyopt)` 原生块原样）；无 §3.8 守卫、无 §3.9 文件、无 §3.10 档位、核心层 0 改动、无旗标改名。
- **机制（任务 2）：成立。** 第 1 段只存字符串（`main.F90:2300-2315`），第 2 段在 flag 循环 `end do`（`:3957`）之后（`:3960-4045`），`set%runtyp` 在 `parseArguments` 之后无人再赋值（全仓 grep）⇒ 顺序无关**结构性成立**。四个原生出口走 `:3968-3982` 的第一分支，`case (p_run_opt,p_run_ohess)`，**不落** `default`。
- **但「别名表与 `set_module.f90:1888-1891` 逐字一致」不成立（L5）**：`lbfgs` 被有意去掉（设计 §4.7/R21），而 `lancopt` 是**新增**拼写，**不是** xcontrol 键（`:1889` 只有 `lbfgs|l-ancopt`）。后果：`--method lancopt` 可用、`$opt engine=lancopt` 打 `not implemented` 警告。`main.F90:4114-4123` 的注释与 25 号报告 §1 的引证（`:1889`）不准确。
- **状态初值（任务 3）：全部确定。** 新增状态位仅 5 个：4 个 allocatable `*_source`（默认未分配）+ `landscape_native_engine`（`:1606`，在 `:1608` 循环前、任何 `env%error` 之前）。注意：本轮该值**只写不读**（`xtbMain:246` 的 `= 0` 被 `intent(out)` 抹掉且无人读）⇒ R30/MEDIUM-1 的运行时测试现在**恒真**（INFO-1）。
- **别名关系（任务 4）：无误拒、无静默接受。** 冲突仅在「异 owner 且异值」触发（`:4234/4272/4313/4352`）；枚举 5×4 组合全部符合设计。**唯一不对称（L3）**：`--lts-method cineb --lts-method neb` 留 `climb=.true.`（副作用逐次施加 `:4324`），而 `--method cineb --method neb` 只处理最后一个 ⇒ `climb=.false.`，两别名在重复旗标下**不等价**。
- **过滤（任务 5）：以 `set%runtyp` 为准、顺序无关**（`--method bfgs --lopt` 与反序都正确；`--lscan --method dimer` 报错点名 `--lts`）。三个名字集合两两不交（`settings.f90:1197/1315/1382`），`landscape_method_task` 的 opt→ts→irc 短路安全。
- **`auto`（任务 6）：语义正确**（no-op = 所选任务默认，banner 语义自洽），ctest 只钉住 lopt/lts（lscan/lirc 仅 26 号会话实测）。
- **M1（MEDIUM）：18 个套件方法名里 13 个无 ctest 证明生效**（含最常见的 `--lopt --method lbfgs`）——违反铁律 1 与 §9.2 的逐名表。
- **M2（MEDIUM）：§9.1 把 §6.3 缺口旗标列为阶段 2，本轮未实现且设计文档无登记**（R39 只登记了 `--opt` 过渡限制）；且 §6.4 与 §9.1 对 `--cycles` 的归属自相矛盾。
- **L1：BC-4 证据不含被改写的 4 个旧旗标**（唯一真正改动的代码路径）⇒ 「现有命令逐位不变」缺 4 条基线对比。
- **L2：scan 内层方法「存了但没生效」无法被任何测试发现**（rigid 模式忽略它，relaxed 模式两条别名路由共用 setter、里程碑行与方法无关、`xtbscan.log` 不含方法名）。
- **L4：`--method <native>` 静默覆盖 xcontrol `$opt engine=`**（U15 的 `[WARNING]` 未实现，26 号已登记）；需上级决定是否动 `set_module.f90`。
- **未见「断言恒真」的新测试**：conflict-opt/scan/ts/irc 四条分别钉住 4 个 setter 的存储+分派；`irc.log` 头含方法名（`irc.f90:996`）⇒ irc 别名比较本身就是分派断言；501 原子 fixture 被 26 号注入 E 证明非恒真。
- **需运行验证**（我无法执行）：见正文 §6 的 7 条命令，其中第 5 条是我新提的（4 个旧旗标的基线对比）。

---

# 27 — 阶段 2 独立复核报告：统一方法选择器 `--method <name>`

**复核者**：独立 read-only 复核（fresh context，**不能运行命令**，未修改任何文件）。
**复核对象**：`docs/_simplify-recon/25-stage2-impl.md`、`26-stage2-validation.md`，以及 `src/`、`test/`、`man/` 的实际改动（HEAD = `f5b070f` + 未提交工作区）。
**方法**：逐文件走读 diff + 逐行核对规格（`11-cli-redesign.md` §4/§4.7/§4.7.1/§4.8/§5/§6.3/§9.1/§9.2/§10）+ 逐个测试判断可证伪性 + 枚举别名组合。
**证据限制**：本会话**没有执行任何命令**；凡「实测」字样均引自 25/26 号报告并标注是否被我静态复核。26 号报告本身是一次**独立**会话（自建 `/tmp/xtb-p2v/new` + `f5b070f` worktree 基线），其数字我无法复现，只能核对其方法学与自证。

---

## 0. 结论

**有条件接受。**

- **无 CRITICAL、无 HIGH、无边界越界、未发现回归证据**。2 条 MEDIUM 都是「验收/登记」缺口而非代码缺陷；LOW/INFO 均不阻塞。
- **阶段 2 的代码可以提交 git**，条件是：① 上级跑 §6 的验证命令；② M1/M2 必须**登记**（R40 或下一轮工作清单），否则阶段 3 会忘记；③ **不要 `git add p2-workflow.js`**（见 INFO-6）。
- **阶段 3 可以开始**：其第一项动作（移除 R39 的 `--opt` 过渡拒绝 + 落地 `landscape_native_engine` 的读点）不受本报告任何发现阻塞；但阶段 3 不得吞掉 §6.3 缺口旗标（M2）。

---

## 1. 边界核对（任务 1，逐文件；任何越界应为 HIGH）

| 文件 | 改动 | 边界判定 |
|---|---|---|
| `src/landscape/types/settings.f90` | +4 个 `character(len=:), allocatable :: *_source`（`:445`、`:551`、`:686`、`:892`） | 在套件内；无枚举/阈值/SCF 精度改动 ⇒ 不触 §3.10 ✔ |
| `src/prog/main.F90` | 新增 `--method` case、4 个旧 case 改调共享 setter、尾归一、5 个新过程 | 唯一允许 `use xtb_landscape_*` 的文件 ✔ |
| `src/xhelp.f90` | +14 行 `--method NAME` 帮助 | **任务书要求**新旗标进 help（否则集合 S 门槛红）✔ |
| `test/unit/{CMakeLists.txt,meson.build,landscape_cli_check.py}` | +2 个 ctest / +2 个 meson test / +415 行检查器 | 两侧同时注册 ✔ |
| `docs/_simplify-recon/11-cli-redesign.md` | +14 行 R39 | 设计登记，正确 ✔ |
| `src/set_module.f90`、`src/main/defaults.f90`、`src/type`、`src/xtb`、`src/mctc`、`src/param`、`src/io`、`src/disp`、`src/coulomb` | **0 改动**（`git diff --stat` 无） | 核心层未动 ✔ |

逐条边界：

- **不改 `--opt`/`--ohess` 分派**：`landscape_native_engine` 在 `xtbMain`（`:131-1481`）**只有声明（`:246`）与传参（`:261`），无读点**（`grep -n landscape_native_engine` 全部命中在 `:246/261/1486/1581/1601/1606/3968/3970/3977/4124/4143`）；`main.F90:996/1019/1035/1065/1084` 的套件分派块与 `if (anyopt)` 原生块均未改 ✔
- **不加 §3.8 三条守卫**：全 diff 无 `$scan`/周期/`$opt engine` 守卫逻辑 ✔（`--opt --method <suite name>` 的过渡拒绝**不是** §3.8 守卫，且已登记 R39）
- **不写 §3.9 四个遗留文件**：`src/landscape/` 无新文件 ✔
- **不做 §3.10 档位 SCF 精度**：`landscape_conv_level_known` 与档位映射 0 改动 ✔
- **不改现有旗标名**：`--lopt-engine/--lscan-method/--lts-method/--lirc-method` 名字、参数形式、错误文本（"Unknown landscape …"）逐字保留（`main.F90:2318/2380/2643/3378` → `:4215/4253/4294/4333`）✔
- **`--method` 与上游无冲突**：`grep -n "'--method'" src/prog/main.F90` 只有新增的 `:2300`；`man/`、`xhelp.f90` 此前无该拼写 ⇒ 非「改名」，是新增 ✔

---

## 2. §4.7 机制的可实现性（任务 2）

### 2.1 别名表 vs `set_module.f90:1888-1891`（**不逐字一致，见 L5**）

| 来源 | 值域 |
|---|---|
| xcontrol `$opt engine=`（`set_module.f90:1884-1893`） | `rf|ancopt`、`lbfgs|l-ancopt`、`pbc_lbfgs`、`inertial|fire`（**7 拼写**） |
| `landscape_native_engine_from_name`（`main.F90:4124-4143`） | `ancopt|rf`、`lancopt|l-ancopt`、`fire|inertial`、`pbc_lbfgs`（**7 拼写**） |
| 差集 | **去掉** `lbfgs`（设计 §4.7/R21 有意，裸 `lbfgs` 归套件）；**新增** `lancopt`（**不是** xcontrol 键） |

⇒ 数量对得上（7=7），但集合不同。`lancopt` 是设计 R9 有意引入的 CLI 名（避免与套件 `lbfgs` 撞名），**行为后果**：`--method lancopt` 可用，`$opt engine=lancopt` 走 `case default` → `[WARNING] engine 'lancopt' is not implemented`（`set_module.f90:1887`）且**不设引擎**。这不是缺陷，但 `main.F90:4114-4123` 的注释「The alias spellings are the keys of the xcontrol `$opt` block … except that the bare `lbfgs` is not listed here」**漏了「新增了 `lancopt`」这一半**，25 号报告 §1 表把 `lancopt` 的依据写成 `set_module.f90:1889` 也**引错行**（1889 = `lbfgs|l-ancopt`）。

### 2.2 四个原生出口不落 `default`/`env%error`

走读 `main.F90:3967-3988`：`if (native /= 0)` → `select case (set%runtyp)` → `case (p_run_opt, p_run_ohess)` → `set%opt_engine = …`；`else if (auto)`；`else`（套件名）才进 setter。四个引擎名在第一个分支被分流 ⇒ **不会**调 `landscape_opt_algorithm_from_name`。7 个拼写 × `--opt` 的判别 token（`ANC micro-cycles`/`L-ANC optimizer`/`initial time step`/`current lattice:`）由 `check_method_native` 断言，并断言 `landscape: ` 不出现。✔（26 号注入 A 从反面证明两条路分离。）

### 2.3 顺序无关

- 第 1 段（`:2300-2315`）**只** `args%nextArg` + 赋值，不读 `set%runtyp`、不调 `set_runtyp`、不写 settings ✔
- 第 2 段在 flag 循环（`end do` `:3957`）**之后**、`end subroutine parseArguments`（`:4047`）之前 ✔
- `set%runtyp` 在 `parseArguments` 之后**无人再赋值**（全仓 `grep "call set_runtyp"` = `prog/dock.f90:489`（另一入口）、`main.F90:4101`（`select_runtyp`）、`set_module.f90:1121`（`--raman`→hess）、`set_module.f90:2828`（`$set runtyp=`））；`rdcontrol` 在 `parseArguments` 之后，且此时 `set_runtyp` 已被 CLI 锁定 ⇒ 不改变结论 ✔
- **未验证的边角（INFO）**：无任何 CLI 任务旗标、只靠 xcontrol `$set runtyp=lopt` 选任务时，`--method bfgs` 在第 2 段看到的是 `sp` ⇒ 报「needs a landscape run type」。与 §4.5「必须显式任务旗标」一致，但**未在报告中登记**、也无测试。

---

## 3. 状态初值清单（任务 3）

| 新增状态位 | 位置 | 初值 | 判定 |
|---|---|---|---|
| `landscape_opt_settings%algorithm_source` | `settings.f90:445` | allocatable ⇒ 未分配 | ✔ |
| `landscape_scan_settings%method_source` | `settings.f90:551` | 同上 | ✔ |
| `landscape_ts_settings%method_source` | `settings.f90:686` | 同上 | ✔ |
| `landscape_irc_settings%method_source` | `settings.f90:892` | 同上 | ✔ |
| `landscape_native_engine` | `main.F90:246`（`= 0`）、`:1581`（`intent(out)`）、**`:1606`（循环前）** | 每条路径已定义 | ✔ |

- `:1606` 在 `nFlags = args%countFlags()`（`:1607`）与 `call args%nextFlag`（`:1608`）**之前**，也早于循环内任何 `env%error` ⇒ R30/MEDIUM-1 要求满足 ✔
- **但（INFO-1）**：该值本轮**无读点**（`:3970/3977` 与赋值同块）。⇒ §4.7.1 的 `xtb/landscape-lopt-no-method` 在本轮是**恒真测试**（设计自己也承认运行时不可证伪）；真正意义在阶段 3。`xtbMain:246` 的 `= 0` 对 `intent(out)` 无效（不构成缺陷，但注释可更准确）。
- 结构体新增字段安全性：全仓 4 个类型的构造**全部是默认构造 `()`**（`grep` 65 处），无位置参数构造 ⇒ 不破坏任何调用点 ✔

---

## 4. 别名关系：4×组合枚举（任务 4）

owner 只有两个：`--method` 与各任务的旧旗标。判定式：`allocated(source) .and. source /= owner .and. stored /= new`（`:4234-4235/4272-4274/4313-4314/4352-4353`）。

| # | 组合（任一任务，任取 X≠Y） | 期望 | 判定式给出 | 误拒/静默风险 |
|---|---|---|---|---|
| 1 | 只 `--method X` | 生效 | `source` 未分配 → 设值 | 无 |
| 2 | 只 `--old X` | 生效 | 同上 | 无 |
| 3 | `--method X --old X` / `--old X --method X` | 幂等 | `stored == new` → 不报错 | 无 |
| 4 | `--method X --old Y`（两序） | error | `source /= owner` 且 `stored /= new` → error | 无静默 |
| 5 | `--old X --old Y` / `--method X --method Y` | last-wins | 同 owner（前者）/ 只处理最后一个（后者） | 无 |
| 6 | `--method auto` + 显式旧旗标 | 保留旧值 | `auto` 在 `:3983` 提前 `continue`，不进 setter | 无 |

- **不误拒**：`--lopt-engine bfgs --method lbfgs`（`lbfgs` 是套件默认名）→ `stored==new` → 通过；`--lirc-method hpc --method hpc` → 通过（26 号 §4 z1-z4 实测同结论）。设计 §4.3「第二次设定不同值即报错」被**有意收窄**为「异 owner」，25 号 F6 已登记（理由：否则 `--lopt-engine bfgs --lopt-engine cg` 从 last-wins 变 error = 未登记的破坏性变更）——**这个收窄是对的**。
- **不静默**：异值异 owner 必报错（26 号注入 B 反向证明）。
- **L3（真不对称，未登记、未测试）**：`--lts-method cineb --lts-method neb` 与 `--method cineb --method neb` 不等价（climb 副作用逐次施加 `:4324` vs 只处理最后一个 `:3967-3969`）。属病态输入，LOW。
- **INFO-2**：`auto` 只能经 `--method` 给出（`--lopt-engine auto` → `Unknown … algorithm 'auto'`）。设计 R39 只登记了「`auto` 语义与阶段无关」，没登记这条可达性差异。

---

## 5. 按 runtyp 过滤 / `auto` / 可证伪性（任务 5-7）

### 5.1 过滤

- 依据 = `set%runtyp`（第 2 段时刻已终值，§2.3）✔
- 分派依据 = `landscape_method_task`（`:4154-4170`，opt→ts→irc 短路）。**集合两两不交**（`settings.f90:1197-1220` 6 个 / `:1382-1409` 8 个 / `:1315-1334` 4 个），且与原生 7 拼写也不交（`:4130-4141`）⇒ 短路安全 ✔
- `--method bfgs --lopt`（反序）正确 ✔；`--lscan --method dimer` → error 点名 `--lts` ✔
- 未知名 / 无任务 / `--lvib` 三种错误分别有专门文本（`:4023/4040/3990`）✔

### 5.2 `auto`

实现 = no-op（`:3983-3988` 的 `continue`）⇒ 结果 = 任务内置默认（opt/scan `lbfgs`、ts `prfo`、irc `hpc`），与 §4 一致；且 banner 语义自洽（`algorithm_was_set`/`method_was_set` 未被污染 ⇒ `--lopt --method auto` 仍打 D3 notice，`--lopt-engine bfgs --method auto` 不打）。**ctest 只钉住 lopt + lts**（lscan/lirc 的逐位等价只在 26 号会话的 `/tmp` 脚本里）——覆盖不足但不错误。

### 5.3 逐条可证伪性（「把对应逻辑写错，这条测试会不会仍绿」）

| 断言 | 若对应逻辑写错 | 会红吗 |
|---|---|---|
| `alias-opt` 里程碑 `landscape: bfgs minimisation` + `xtbopt.xyz` 逐位同 | 尾归一只写不生效/写错对象 | **红**（里程碑由 `lset%algorithm` 打印） |
| `conflict-{opt,scan,ts,irc}` 非零退出 | 尾归一只写不生效 / 写错对象 / 无冲突检查 | **红**（这是 4 个 setter 的存储+分派锚点） |
| `alias-cineb` 的 `climbing image N ignited` + `p1.path.xyz` 逐位同 | climbing 副作用搬出共享 setter | **红**（26 号注入 F 已实测） |
| `alias-irc` 的 `irc1.irc.log` 逐位同 | 分派写错对象 / 不生效 | **红**（`irc.f90:996-997` 把方法名写进 log 头 ⇒ 该比较**本身就是**分派断言） |
| `check_method_native` 7 拼写的唯一 token + 无 `landscape: ` | 映射删掉/改到别的引擎 | **红**（26 号注入 A/E 实测） |
| 501 原子 + `--method ancopt` 的 `ANC micro-cycles` 且无 `L-ANC optimizer` | 删 `set%opt_engine = landscape_native_engine` | **红**（26 号注入 E 实测：token 反转） |
| `native-ohess` 的 5 文件与裸 `--ohess` 逐位同 + token | `p_run_ohess` 从 case 里去掉 | **红**（exit 1） |
| `filter-*` 系列 | 过滤谓词/报告删掉 | **红**（26 号注入 C/F 实测） |
| `repeat-last`/`repeat-engine` | `--method` 变 first-wins | **红**（25 号注入 M8 实测） |
| `alias-scan` 的 `xtbscan.log` 逐位同 | 尾归一只写不生效 | **弱**（见 L2：两条路由共用 setter，且 `xtbscan.log` 不含方法名、里程碑与方法无关） |
| `auto-*` | 删 no-op 分支 | **红**（25 号 M6 实测） |

**未发现「断言恒真」**：`identical()` 比字节且文件缺失即抛异常（26 号 F-2 真实发生过）；`expect_error` 要求非零退出 + 正则；`expect_milestone` 同时断言「含」与「不含」。唯一恒真的是 §4.7.1 的 `-lopt-no-method`（设计自认，INFO-1）。

### 5.4 覆盖缺口（M1 的原始数据）

ctest 经 `--method` 实际跑到的名字：**opt 2/6**（`bfgs`、`cg`）、**ts 2/8**（`dimer`、`cineb`）、**irc 1/4**（`gs`）、**native 7/7**、**auto 2/4**（lopt、lts）。
⇒ **13 个套件名零 ctest 覆盖**：`sd`、`lbfgs`、`diis`、`rfo`、`prfo`、`bprfo`、`neb`、`autoneb`、`string`、`gsm`、`hpc`、`lqa`、`eulerpc`（**含最常用的 `--lopt --method lbfgs`**）。
静态核对：这些名字今天**都能工作**（`from_name` 表齐全），所以这是**回归保护**缺口，不是现存缺陷——但违反铁律 1 与设计 §9.2 的逐名表，且 26 号已用 26 名手工跑过（今天全绿）。

---

## 6. BC-4 与回归（任务 8-9）+ 需运行验证

### 6.1 BC-4 方法学评价

26 号 §7 的方法（同目录、同命令行、两二进制、逐文件 `cmp`、stdout 逐行分类、行数比对、抹数字后多重集比较）**比我预期的更严**，并且给出了具体差异（`md` 的 `xtbtopo.mol` 第 2 行 `MMDDYYHHMM`）。方法学可接受。

**但（L1）**：13 个 runtype 里**没有一个使用被本轮改写的 4 个旧旗标**（`--lopt-engine`/`--lscan-method`/`--lts-method`/`--lirc-method`）。而这 4 个 case 的**实现被整段替换**（`main.F90:2318-2325/2380-2386/2643-2651/3378-3386`），是本轮**唯一**可能改变既有命令的代码路径。⇒ 「本轮不改变任何现有命令的数值结果」目前只对**不含这些旗标**的命令有实测支撑。
我能静态确认的风险点只有一个：`set_landscape_scan_algorithm` 把存储值**转小写**（`:4281`，旧代码存 `sec` 原文）。我已核对 `lsset%method` 的**全部读点**（`relax_scan.f90:501/502/597`，全部经 `from_name` 内部再转小写）与**全部打印点**（无：`xtbscan.log` 与 json 都不含方法名）⇒ **不可观测**。但这属于「静态结论」，本项目已 4 次被实测推翻 ⇒ 见 §6.2 第 5 条。

### 6.2 需运行验证（我无法执行；按优先级）

```bash
REPO=/home/owenchan/work_path/coding/fortran/xtb
# 1. 门槛：全绿 + 无重名（重名会被 CMake 静默丢弃，AGENTS §4）
OMP_NUM_THREADS=1 XTBPATH=$REPO ctest --test-dir /tmp/xtb-p2/build -R landscape        # 期望 120/120
OMP_NUM_THREADS=1 XTBPATH=$REPO ctest --test-dir /tmp/xtb-p2/build \
  -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'                          # 期望 12/12
ctest --test-dir /tmp/xtb-p2/build -N -R landscape
grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d                 # 期望空
grep -oE "test\('[^']+'"     test/unit/meson.build  | sort | uniq -d                    # 期望空
# 2. 集合 S 门槛（脚本读源码，不需重建）
python3 test/unit/landscape_help_check.py src/prog/main.F90 src/xhelp.f90              # 期望 S 差集 0（A/B）
# 3. 未验证的 meson 端到端（本机无 meson ⇒ 只能记录为未验证）
# 4. M1 的廉价闭合（可选，~30 s）：表驱动跑 18 个套件名 + auto，断言里程碑/退出码
# 5. ★本轮新增的必跑项（闭合 L1）：f5b070f 基线 vs 阶段 2 二进制，4 个旧旗标
#    （含大写存储点 --lscan-method CG）
#    --lopt --lopt-engine bfgs / --lscan --lscan-method cg / --lscan --lscan-method CG
#    --lts --lts-method dimer / --lirc --lirc-method gs
#    期望：全部输出文件 raw cmp 逐位同（同 26 号 §7 的方法）
# 6. 提交前确认工作区
git status --porcelain                                                                 # 期望不含 p2-workflow.js
```

### 6.3 回归（任务 9）

- **M0..M7 数字**：本轮未触碰任何数值代码（`src/landscape/` 只加 4 个 allocatable 字符字段，无算法/阈值/单位改动）⇒ 不可能影响 M0..M7 的已验收数字 ✔
- **W0 三条缺陷行为**：`$fix` 投影、`$thermo` 优先级、`$scan` 拒绝均未被触碰；`--lvib --method` 现在**响亮报错**（`:4023`），不改变 `$thermo` 语义 ✔
- **阶段 1 的 118 个测试**：25/26 号都报 120/120（118+2）。唯一与阶段 1 行为相关的是「枚举转小写」的 5 个存储点——本轮给 `lsset%method` 补了转小写（第 6 个存储点），方向与 §8.5 一致 ✔
- **未见回归证据，但见 §6.2 第 5 条的证据缺口**（L1）。

---

## 7. 报告纪律（任务 10）

可核性总体良好：25 号 §2 的「静态核」给了 `grep`，§5 的 10 次突变给了真实 FAIL 文本，26 号 §14 给了「命令/期望/实际」三列表。抽查引证**全部对得上**：`case ('--method')` = `:2300`、`--lopt-engine` = `:2318`、`--lscan-method` = `:2380`、`--lts-method` = `:2643`、`--lirc-method` = `:3378`、`landscape_native_engine = 0` = `:1606`（循环前）、setter = `:4215/4253/4294/4333`。

**不准确之处（均不阻塞）**：
1. 25 号 §1「别名逐字取自 `set_module.f90:1888-1891`」+ `lancopt` 的依据行 = `:1889`（L5）。
2. 25 号 §0 的「范围」引用了 §6.3，但 §6.3 的缺口旗标**一个都没实现、也没说明未实现**（M2）。
3. 25 号 §0 声称「**BC-4 逐位不变**」的证据只覆盖 4 个**原生** runtype，未覆盖被改写的 4 个旧旗标（L1）。
4. 25 号 §4.7.1 的「20 条测试」在本轮只落地 2 个 ctest 入口；26 号 §12.2 已诚实标注「没有一一映射」，但 25 号 §0 未标注（M1）。

---

## 8. 逐条表（CRITICAL / HIGH / MEDIUM / LOW / INFO）

| # | 级别 | 位置 | 问题 | 证据 | 最小修法 |
|---|---|---|---|---|---|
| M1 | MEDIUM | `test/unit/landscape_cli_check.py:1947-2225`、`test/unit/CMakeLists.txt:3365-3398` | 18 个套件方法名中 **13 个无 ctest 覆盖**（含 `--lopt --method lbfgs`）；违反铁律 1 与设计 §9.2 的逐名表「`xtb/landscape-method-<task>-<name>`」 | `check_method` 只跑 `bfgs/cg/dimer/cineb/gs/auto`；`check_method_native` 只跑 7 个原生拼写 | 加一个表驱动 ctest（18 名 × 里程碑/退出码），约 30 s；或**明确登记**为阶段 2 收尾项 |
| M2 | MEDIUM | `docs/_simplify-recon/11-cli-redesign.md:2135-2139`（§9.1 阶段 2）vs `src/prog/main.F90` | §9.1 把 §6.3 缺口旗标（`--lopt-max-steps`、`--l*-hess-step`、`--l*-sccacc`、`--lopt/lvib-restart`）列为**阶段 2**，本轮未实现、设计文档无登记（R39 只登记 `--opt` 过渡限制）；§6.4 与 §9.1 对 `--cycles` 归属**互相矛盾** | `grep -n "--lopt-max-steps\|--lopt-sccacc\|--lopt-restart" src/prog/main.F90` = 0 命中；设计 §6.4 写「§9.1 阶段 2」，§9.1 把 `--cycles` 写在阶段 3 | 加 R40：登记「§6.3 缺口旗标 → 阶段 2b/3」并订正 §6.4 的归属 |
| L1 | LOW | `docs/_simplify-recon/26-stage2-validation.md:271-282` | BC-4 证据不含**被改写的 4 个旧旗标**，而它们是本轮唯一改动的代码路径 | 13 个 runtype 列表无 `--lopt-engine/--lscan-method/--lts-method/--lirc-method`；`git diff` 显示 4 个 case 被整段替换 | 跑 §6.2 第 5 条（4-5 条命令 + `cmp`） |
| L2 | LOW | `test/unit/landscape_cli_check.py:2033-2042`；`src/landscape/scan/relax_scan.f90:501/597`；`src/landscape/scan/scan1d.f90:407-458` | scan 的「内层方法存了但被忽略」无法被任何测试发现：两条别名路由共用 setter、里程碑 `landscape: relaxed scan` 与方法无关、`xtbscan.log` 不含方法名、rigid 模式根本不用它 | 26 号 §11 LOW-3 独立发现 rigid 通道；我补上 relaxed 通道 | 断言 `--lscan --method cg` 与 `--lscan --method lbfgs` 的 `xtbscan.log` **不同**（或与默认路由不同） |
| L3 | LOW | `src/prog/main.F90:3967-3969` vs `:4320-4325` | 重复旗标下两别名**不等价**：`--lts-method cineb --lts-method neb` 留 `climb=.true.`，`--method cineb --method neb` 留 `climb=.false.`（`--method` 只保留最后一个字符串） | 代码走读；无测试 | 在 `--method` 文档/报告里注明「重复 `--method` 为 last-wins，副作用不累积」；或让 ts 的副作用随最终值重算 |
| L4 | LOW | `src/set_module.f90:1885-1893`（未改） | `--method <native>` 会**静默**使 xcontrol `$opt engine=<别的>` 失效（`.not.allocated` 守卫），无任何 warning；设计 §4.7.1 的 `R34/U15` 要求补 `[WARNING]` | 26 号 §11 LOW-2 实测 `warn=0`；`git diff --name-only` 无 `set_module.f90` | 需上级决定是否动非核心但非 landscape 的 `set_module.f90`（加一条 warning，不影响无 `--method` 的现有命令） |
| L5 | LOW | `src/prog/main.F90:4114-4123`；`docs/_simplify-recon/25-stage2-impl.md:52-62` | 「别名 = xcontrol `$opt` 键」的说法不准确：`lancopt` 是**新增**拼写（`$opt engine=lancopt` → `not implemented` 警告），`lbfgs` 被有意去掉 | `set_module.f90:1888-1891` 逐字对照；`main.F90:4130-4141` | 改注释：说明「取 xcontrol 键去掉 `lbfgs`、加上 CLI 专名 `lancopt`」；订正 25 号 §1 的引证行 |
| INFO-1 | INFO | `src/prog/main.F90:246/1606/3968-3977` | `landscape_native_engine` 本轮**只写不读**（阶段 3 的钩子）⇒ §4.7.1 的 `-lopt-no-method` 测试现在**恒真**；`xtbMain:246` 的 `= 0` 被 `intent(out)` 抹掉 | `grep -n landscape_native_engine` 无 `xtbMain` 读点 | 报告/设计注明「该测试在阶段 3 才具备可证伪性」 |
| INFO-2 | INFO | `src/prog/main.F90:3983-3988` | `auto` 只能经 `--method` 给出（旧旗标不收 `auto`）；R39 只登记了语义与阶段无关 | `--lopt-engine auto` → `Unknown … algorithm 'auto'` | 在 R39 里补一句可达性说明 |
| INFO-3 | INFO | `test/unit/landscape_cli_check.py:1947-2225`；`src/landscape/tasks/irc.f90:182` | `--lirc --method gs` 对 D2 banner（`method_was_set`）的抑制**无断言**（代码正确，setter `:4361` 设了） | 新测试只断言 lopt 的 notice | 可顺手加一条（非必须） |
| INFO-4 | INFO | `man/xtb.1.adoc` | 无 `--method` 条目（所有套件旗标都不在 man 里） | `grep method man/` 只命中无关行 | §9.1 阶段 4 的文档收口 |
| INFO-5 | INFO | `src/prog/main.F90:4040-4041` | 无任务时的消息只点名 `--opt`，未点 `--ohess`（而 `--ohess --method ancopt` 合法） | 26 号 §11 INFO-1 | 消息补 `--ohess` |
| INFO-6 | INFO | `p2-workflow.js`（仓库根，untracked） | 会话脚本未进 `.gitignore` | `watchdog_diff` untracked 清单 | 提交时**不要** `git add` 它；或加进 `.gitignore` |

---

## 9. 零覆盖 / 未验证清单（单列）

**零 ctest 覆盖（M1）**：`--method` 的 13 个套件取值 `sd lbfgs diis rfo prfo bprfo neb autoneb string gsm hpc lqa eulerpc`；`--lscan --method auto`、`--lirc --method auto`。

**未验证项（诚实标注）**：
1. meson 端到端**未执行**（本机无 meson/ninja）——25/26 号均已标注，我无法补做。
2. 26 号的全部「实测」数字我**无法复现**（不能运行命令）⇒ 其中 BC-4、120/120、集合 S 差集 0、6 次注入的红/绿，均**依赖 26 号会话的自证**；我做了方法学核对与静态复核，未发现自相矛盾。
3. §6.2 第 5 条（4 个旧旗标的基线对比）**未做**。
4. `--method` + xcontrol `$set runtyp=`（无 CLI 任务旗标）的边角行为**未验证**。
5. `--method <native>` + xcontrol `$opt engine=` 的**静默覆盖**未实现 U15 警告（L4，需决策）。
6. L3 的重复旗标不对称**无测试**。

---

## 10. 明确回答

- **阶段 2 现在可以提交 git 吗？** —— **可以**（无 CRITICAL/HIGH/越界；代码路径经我静态走读与两次独立注入一致）。前提：跑 §6.2 第 1/2/5/6 条；把 M1/M2 登记为后续项；不要 `git add p2-workflow.js`。**但不要对外宣称「阶段 2 完成」**：§9.1/§9.2 的两项验收（逐名测试、§6.3 缺口旗标）未满足。
- **阶段 3 可以开始吗？** —— **可以**。阶段 3 的第一项（移除 R39 的过渡拒绝、给 `landscape_native_engine` 落地读点与 §4.7.1 的阶段 3 断言）不受本报告任何发现阻塞。开工前请先把 M1/M2 写进设计文档（R40），否则阶段 3 会像 R39 警告的那样「忘记放开/忘记补回」。

---