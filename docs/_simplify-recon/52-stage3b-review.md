## Review 摘要（≤30 行）

- **结论：有条件接受（CONDITIONAL ACCEPT）**；CRITICAL 0（本 diff） / **HIGH 2** / MEDIUM 1 / LOW 2 / INFO 2。
- **阶段 3b 现在可以提交 git 吗？→ 不可以（先修 1 处 3 行文案）。** T1/T2/T4 的机制与测试经我逐条核到源码，可提交；**T3 把 `--bhess`/`--omd`/`--metaopt` 三条 help/man 文案改成了不成立的陈述**（详见 P1-1），这是本 diff 引入的、必须修掉的用户可见假话。
- **P1-1（本 diff 引入，阻塞提交）**：`src/xhelp.f90:785-786/814-815/817-818`、`man/xtb.1.adoc:252-255/282-285/287-290` 现在说这三个 runtype "由套件优化几何 / pass `--method ancopt` 回原生"。实测依据：`effective_landscape_task` 只映射 `p_run_opt/p_run_ohess`（`main.F90:4728`），套件集合只有 5 个 `p_run_l*`（`:4753-4758`），`--bhess` 走原生 `getkopt.f90:142 → geometry_optimization`；且 `--bhess|--omd|--metaopt --method ancopt` 在 `main.F90:4377-4379` **直接报错**（"only available with --opt or --ohess"）。旧文案本来是对的。
- **P0-1（继承自 HEAD `b822c1f`，非 3b 引入，但由 P1-1 的核查暴露）**：`main.F90:987` 的 `anyopt .and. landscape_native_engine /= 0` 让 `--omd/--screen/--metaopt` 的**原生优化块不可达**（`landscape_native_engine` 只由 `--method` 写，而这三个 runtype 传 `--method` 即报错）⇒ `--omd` 从输入几何直接跑 MD；`--metaopt` 在 `:1524` 读**未初始化**的 `murks`（`:232` 无初值，只被跳过块里的 `intent(out)` 赋值）。与设计 §3.7"保持原生"、§1.2 BC-4 冲突。最小修：谓词改 `anyopt .and. .not. landscape_is_suite_run(...)` + `murks = .false.` 初值。
- **P2-1（本 diff 引入，登记/措辞）**：`compliance.dat` 条件不是上游条件。上游 `freezeset%n == 0` 是 `$fix` 组的 `freeze:` 名单（`xcontrol.7.adoc:212-216`），代码用的是 `$fix` 组的 `atoms:` 名单（`landscape_frozen_mask` ← `fixset`，`constrain_param.f90:341-357`）。两个方向都可达（`$fix atoms:` 上游写/套件不写；`$fix freeze:` 反之），且 `vib.f90:166-173`、报告 §2.4、设计 §3.9 表都声称"同构/逐字相同"——措辞不实。
- **P2-2（本 diff 引入）**：`--lvib`（**非**改派 runtype）stdout 新增 compliance 块 + 新文件，设计 §1.2 仍写"BC-4 只在 `--opt`/`--ohess` 两处有意违反"，§10 A 类也没登记；实施报告只在 §10 记为"残留风险"。
- **P2-3（文档）**：设计 §3.9 测试表仍写 `.xtboptok` **非空**，与上游 `touchFile`（`iohandler.f90:364-392` 建空文件）矛盾；实施报告写"空"是对的，设计行未订正。
- **LOW-1**：新测试只覆盖 compliance 的**正向**（文件存在+含自名），没有 `$fix`/单原子的反向用例；`--ohess` 链没有 compliance 断言；`landscape-help-coverage` 只比旗标**集合**不比语义，正是 P1-1 逃过验证的原因。
- **LOW-2**：未跟踪的 `stage3b-workflow.js`（仓库根）不在 `.gitignore` 内——提交时勿误加。
- 逐条攻击面回答见正文 §3–§9；**需运行验证**见正文末节（4 条，含 `--omd/--metaopt` 前后对比与 `$fix` compliance 矩阵）。

---

# 阶段 3b 独立复核报告（完整正文）

> 落盘目标：`docs/_simplify-recon/52-stage3b-review.md`
> 复核对象：`docs/_simplify-recon/50-stage3b-impl.md` + 工作树 delta（相对 `b822c1f`，10 文件 +491/−18）
> 权威设计：`docs/_simplify-recon/11-cli-redesign.md` §3.9/§1.2/§10；事实清单 `49-stage3b-recon.md`、`41-stage3-recon.md`
> 复核方式：**只读**。未运行命令、未改仓库。所有结论给 `file:line` 级证据；需要实测才能判定的项单列"需运行验证"。
> 同级材料：`51-stage3b-validation.md`（validator，结论 PASS）。本报告与其不冲突：它 §4 实测的"数值零变化"我采信为已证事实，本报告的 P1-1/P0-1/P2-1 是它未覆盖的**语义层**。

---

## 0. 结论与提交判定

| 项 | 判定 |
|---|---|
| 本阶段结论 | **有条件接受**（CONDITIONAL ACCEPT） |
| CRITICAL | 0（本 diff） |
| HIGH | **2**（P1-1 本 diff 引入且阻塞提交；P0-1 继承自 HEAD） |
| MEDIUM | 1（P2-1 compliance 条件与措辞） |
| LOW | 2（P2-2 未登记的 `--lvib` 契约变化；P2-3 设计表陈旧行） |
| INFO | 2 |
| **阶段 3b 现在是否可以提交 git？** | **不可以。** 先修 P1-1（3 条文案 × 2 文件 = 6 处，纯文档改动，零数值影响）。修完即可提交 3b。 |

**为什么不是"直接可提交"**：3b 的机制面（T1 文件契约、T2 失败即停、T4 测试）经我逐条核到源码，成立且可证伪（与 validator 实测一致）。唯一阻塞项是 T3：这一轮把 **3 个未改派 runtype** 的 help/man 文案改成了两句**都不成立**的话，而 3b 这一阶段的名字就叫"自指引导清理"。它不会让任何测试变红（`landscape-help-coverage` 只比旗标集合，不比语义），所以必须靠人工复核拦住——正是本报告的作用。

**P0-1 是否阻塞 3b 提交**：它**不是** 3b 引入的（HEAD 上已存在），所以**不构成 3b 提交的阻塞理由**；但它 (a) 使设计 §3.7"bhess/metaopt/screen 保持原生 ⇒ 无问题"与 §1.2 BC-4 成为假陈述，(b) 正是 P1-1 那三条文案所断言的行为。建议**在同一轮提交里一起修**（1 行谓词 + 1 行初值），或至少显式登记。

---

## 1. 核过的"正确"（Correct，带证据）

1. **`.xtboptok` 语义与上游一致**：开场删旧哨兵（`log.f90:151-158`，对应 `geoopt_driver.f90:112-113`）、仅收敛时 `touch`（`log.f90:167-178` ↔ `:186`）、失败建 `NOT_CONVERGED`（↔ `:183`）、**互斥**。空文件这一点也与上游一致——`touchFile` 用 `status='new'` 建空文件后立刻 `close`（`iohandler.f90:364-392`），所以实施报告 §5 写"存在且**空**"是**对的**，而设计 §3.9 表里的"**非空**"是错的（见 P2-3）。
2. **命名空间规则逐字同构**：`get_namespace`（`setparam.f90:596-614`）与上游 `iohandler%getName`（`iohandler.f90:117-129`）的点开头规则相同（`.xtboptok → .ns.xtboptok`，`xtbopt.log → ns.xtbopt.log`）。套件用的是 `get_namespace`，**不是自己拼前缀**；`compliance.dat` **没有**被加前缀（`vib.f90:174-177` 只调 `compliance_driver`，名字在 `compliance.f90:287` 裸 `open`）。⇒ 攻击面 2 通过：**不存在两套前缀约定**。
3. **`xtbopt.log` 是 XMOL 多帧、无前导点**：`log.f90:97-99` 写 `xtb.trj` 与 `xtbopt.log`，帧由 `write_trajectory_file`（`log.f90:104-142`）用 `writeMolecule(..., number=iframe)` 逐帧写；与上游 `optimizer.f90:801` 的写点语义相同。`xtb.trj` **保留**（BC-3 允许新增，`11-cli-redesign.md:143`）。
4. **`xtblast.<ext>` 仅失败时写 + 打印上游消息**：`opt.f90:238-243` 只在 `result%converged == .false.` 时调用 `landscape_write_last_geometry`；名字经 `generateFileName(tmpname,'xtblast','',mol%ftype)`（`log.f90:186`）→ `get_namespace`，消息 `last geometry written to:` 与上游 `main.F90:1013-1018` 同形。（唯一差异：上游打印的是**未加前缀**的 `tmpname`，套件打印带前缀的实际文件名——更准确，INFO 级。）
5. **T2 修法正确、结构上封死级联**：`main.F90:1105` 用 `if (lres%converged)` 守卫**整个 vib 半**（`:1106-1145`），不是"清 env 错误掩盖"。失败的 opt 半已由 `landscape_optimize` 记单因错误（`opt.f90:216-227`），链尾 `env%checkpoint("Landscape task terminated")`（`main.F90:1147`）→ `environment.f90:176-195` 的 `terminate` ⇒ exit 1。**级联在结构上不可达**：vib 半是唯一复用同一 `calc` 的消费者，它现在只有一个入口且在守卫内。
   - 我另外检查了"`converged == .true.` 且 `n_scf_fail > 0`"能否成立（那会让守卫放行一个带错误的半程）：驱动循环里拒绝步不改变 `x`/`g`，`driver.f90:404-405` 的收敛判定在下一轮会得到同样结果并已在前一轮退出，故该状态实际不可达 ⇒ **不作为发现**。
6. **测试可证伪、且不是恒真断言**：`landscape_cli_check.py:3938-4102` 的 5 个 mode 断言**内容与条件**（`.xtboptok` 存在+空+无 `NOT_CONVERGED`；失败侧断言"无 `.xtboptok`"+"有 `NOT_CONVERGED`"+"xtblast 单帧"+"消息存在"；`xtbopt.log` 帧数 ≥2 用 `count_xyz_frames` 真解析；namespace 双向：既有带前缀也断言**不存在**裸名）。`.xtboptok` 的"仅收敛时"是**双向**测的。validator §6 已实测 5 条对新旧二进制分别红/绿。
7. **注入打在判定本体**：报告 §6 的注入是 `main.F90:1105` 的 `if (lres%converged)` → `if (.true.)`，即判定本体；validator §3 复现了完整级联并 `cmp` 复原。
8. **越界检查通过**：diff 未碰 `settings.f90`、未碰 `set_conv_level`、无 `acc_was_set`、无再基线；核心层 `use xtb_landscape_*` = 0（validator §7 复核）；`xtb.trj` 未被删；未碰 `src/type/latticepoint.f90`（改法是"不让错误产生"，正确）。
9. **测试注册三处齐全、无重名**：`CMakeLists.txt:3783/3791/3799/3807/3815`（5 条）+ 环境块 `:3878-3882`；`meson.build:891-910`（5 条，命名与 CMake 镜像）；`landscape_cli_check.py` `main()` 5 个分派。`grep -oE 'add_test\("[^"]+"' | sort | uniq -d` 的报告为空，我抽查新名与既有 `xtb/landscape-ohess-{suite-once,native-hess,fres-bridge}` 不冲突。

---

## 2. 发现（Findings）

### Finding P1-1 — T3 把 3 个**未改派** runtype 的 help/man 文案改成了不成立的陈述（本 diff 引入，**阻塞提交**）

- **位置**：
  - `src/xhelp.f90:785-786`（`--bhess`）、`:814-815`（`--omd`）、`:817-818`（`--metaopt`）
  - `man/xtb.1.adoc:252-255`（`--bhess`）、`:282-285`（`--omd`）、`:287-290`（`--metaopt`）
- **现文案（摘）**：`--bhess` = "on a landscape suite optimized geometry (pass --method ancopt for the native ancopt(3) optimizer)"；`--omd` = "on a landscape suite optimized geometry (pass --method ancopt ...)"；`--metaopt` = "run the landscape suite geometry optimization (pass --method ancopt ...)"。
- **证据（三条独立证明）**：
  1. **套件从不执行这三个 runtype**：`effective_landscape_task` 只在 `(runtyp == p_run_opt .or. p_run_ohess) .and. native_engine == 0` 时改派（`main.F90:4728-4735`）；`landscape_is_suite_run` 的真值集合只有 `p_run_lopt/lscan/lts/lirc/lvib`（`:4753-4758`）。`p_run_bhess` 在 `landscape_native_hessian_path` 里被显式判为**原生**（`:4798-4800`）。
  2. **`--method ancopt` 对这三个 runtype 直接报错**：`main.F90:4368-4379` `select case (set%runtyp); case (p_run_opt, p_run_ohess) ...; case default → env%error("--method ancopt selects a native optimizer engine, which is only available with --opt or --ohess")`。⇒ 新文案推荐的是一个**会被程序拒绝**的组合。
  3. **`--bhess` 的几何本来就是原生 ANCopt 优化的**：`main.F90:871` → `get_kopt` → `get_rmsd` → `geometry_optimization`（`getkopt.f90:142`，即 `geoopt_driver.f90` 的 ANCopt 家族）。⇒ 旧文案 "on an `ancopt(3)` optimized geometry" **本来就是准确的**，本轮把它改错了。
- **为什么验证没拦住**：`xtb/landscape-help-coverage` 是"旗标**集合**双向一致"脚本（`11-cli-redesign.md:143` 附近 R25），只比集合不比语义 ⇒ 语义错误必然逃过。validator §5 也只核了"哪些行被改了/未改"，未核"改后是否成立"。
- **最小修**：把 `--bhess`/`--omd`/`--metaopt` 三处（xhelp + man 各 3）**还原为原文案**（`--bhess`: "on an `ancopt(3)` optimized geometry"；`--omd`: "molecular dynamics simulation on `ancopt(3)` optimized geometry"；`--metaopt`: "call `ancopt(3)` to perform a geometry optimization"）。T3 的合法范围只有 `--opt`/`--ohess` 两条（它们确实改派了，文案成立）。
- **建议附带**：给 help-coverage 加一条**语义**断言（例：`--bhess|--omd|--metaopt|--screen|--path|--modef` 的 help 文本**不得**出现 "landscape suite"），否则同类错误会再次逃过。

### Finding P0-1 — `anyopt` 抑制谓词让 `--omd/--screen/--metaopt` 的原生优化块**不可达**（继承自 HEAD，非本 diff 引入）

- **位置**：`src/prog/main.F90:987` `if (anyopt .and. landscape_native_engine /= 0) then`；后果点 `:1491-1514`（omd 的 MD）、`:1518-1526`（metaopt，尤其 `:1524 if (murks)`）；标签点 `:5251-5254`。
- **证据链**：
  1. `anyopt` 含 `p_run_omd`、`p_run_screen`、`p_run_metaopt`（`main.F90:324-326`）。
  2. `landscape_native_engine` 只由 `--method` 写（`:1777` 无条件置 0；`:4366` 唯一另写点），而 `--method` 对这三个 runtype 会报错（`:4377-4379`）⇒ **对这三个 runtype 该谓词恒为假**，原生优化块成为死代码（`grep` 全文只有 `:987` 一处 `call geometry_optimization` 属于 anyopt 家族）。
  3. 后果：`--omd` 现在**不做**前置几何优化就从输入几何跑 MD（MD 调用在块外，`:1491`）；`--metaopt` 在 `:1524` 读 `murks`——而 `murks` 在 `:232` 声明时**无初值**，唯一赋值来自被跳过块里的 `intent(out)` 形参（`:1001`/`:1545`）⇒ **未初始化 logical 读取**，可能随机触发 `Optimization did not converge, aborting`。
  4. 与权威文本冲突：设计 §3.7 表（`12-w2-review.md:215` 复述）"bhess/metaopt/path/modef/screen 保持原生 ⇒ ✅ 无问题"；§1.2 BC-4"未被改派的任务输出与 HEAD 逐位一致"（`11-cli-redesign.md:144-146`）。两者现在都不成立。
- **最小修**：`:987` 改为 `if (anyopt .and. .not. landscape_is_suite_run(set%runtyp, landscape_native_engine))`（对 omd/screen/metaopt 为真、对套件 `--opt/--ohess` 为假，语义正是"改派的才抑制"）；并在 `:232` 给 `murks` 加 `= .false.` 初值（防御未初始化读取）。
- **口径说明**：这是 HEAD 的既有缺陷，**不是 3b 引入**，故不阻塞 3b 的提交；但它必须在阶段 3 收口前修掉或显式登记，否则 P1-1 的文案还原后仍会与"未改派 = 数值不变"的承诺矛盾。

### Finding P2-1 — `compliance.dat` 的调用条件与上游**不同**，且注释/报告/设计称"同构/逐字相同"（MEDIUM）

- **位置**：`src/landscape/tasks/vib.f90:164-177`；报告 `50-stage3b-impl.md` §2.4；设计 §3.9 表 `compliance.dat` 行（"与上游同条件（`n>1`、无 `$fix`、非周期）"）。
- **上游事实**：`src/hessian.F90:331` 的条件是 `mol%n > 1 .and. freezeset%n == 0 .and. .not. set%periodic`。`freezeset` 是 `$fix` 组里 **`freeze:`** 键的名单（"freezes all atoms in 'list' for hessian calculation"，`man/xcontrol.7.adoc:212-216`；填充点 `src/constrain_param.f90:348-357`，legacy 键 `hessf` 见 `:1595`），与 **`atoms:`** 键的 `fixset`（`:341-347`，"fixes all atoms in 'list' by setting the gradient to zero"）是**两个不同的集合**。
- **套件实际用的**：`.not. any(landscape_frozen_mask(mol%n))`，而 `landscape_frozen_mask` 读的是 `fixset`（`types/constraints.f90:80-99`，且模块注释明确"`$freeze` **不**被考虑"）⇒ 判据是 `atoms:` 名单，**不是** `freezeset`。
- **两个方向的偏离都可达**（普通 xcontrol 输入即可）：
  - `$fix atoms: 1`：上游 `--hess` **写** compliance.dat（`freezeset%n == 0` 为真）；套件 `--lvib` **不写**（mask 非空）⇒ 该场景下文件集合**变小**，BC-3 的"集合不小"被破坏。
  - `$fix freeze: 1`：上游 `--hess` **不写**（`freezeset%n == 1`）；套件 `--lvib` **写**（mask 全假）。
- **为什么算发现**：本阶段的目标就是"按上游语义写文件契约"（设计 §3.9 表 + 任务书攻击面 1"逐字相同"），而代码、注释（"`freezeset%n == 0` is read through `landscape_frozen_mask`"）、报告 §2.4（"条件与上游 `src/hessian.F90:331` **同构**"）与设计表都把 `freezeset` 与 `fixset` 当同一个东西。这是本项目主题（不实陈述）的一个新实例，且偏离**未登记**。
- **最小修（二选一，需父会话裁定）**：
  - (a) **严格对齐上游**：条件改 `freezeset%n == 0`（`use xtb_fixparam, only : freezeset`，套件已在 `constraints.f90` 用过该模块），注释改述为"上游用 `freezeset`（`$fix freeze:`），本条件是**逐字**同一判据"；
  - (b) **保留现判据但登记为有意偏离**：注释/报告/设计表改成"上游是 `freezeset`（`$fix freeze:`），套件改用 `$fix atoms:` 掩码（理由：套件不消费 `$fix freeze:`，且 `$fix atoms:` 下不写 compliance 更自洽）"，并加一条可证伪测试（见 LOW-1）。
  - 无论选哪条，**"同构/逐字相同"的措辞都必须改**。

### Finding P2-2 — `--lvib` 的 stdout 与文件集合变了，但设计仍称"BC-4 只在 `--opt`/`--ohess` 两处违反"（LOW，登记项）

- **位置**：`vib.f90:174-177`（新增 `compliance_driver` → `compliance.f90:100-107` 往 `env%unit` 打印 "Compliance Constants" 块）+ 新增 `compliance.dat`。
- **冲突文本**：`11-cli-redesign.md:149` "本设计对 BC-1..BC-5 全部满足（BC-4 在 `--opt`/`--ohess` 两处**有意违反**）"；`:144-146` BC-4 的未改派清单**明确包含 `--lvib`**；§10 A 类只有 A1/A2/A3（都关于 `--opt`）。validator §4 也实测到 `--lvib` 的差异只有"新增文件与新增的 compliance 输出块"。
- **最小修**：在 §1.2 BC-4 句与 §10 A 类里补一条（`--lvib` 的 stdout/文件集随 §3.9 改变，属 R4 决策 2 的必然结果），或把 BC-4 的"两处"改成"三处（`--opt`/`--ohess`/`--lvib` 的 §3.9 附带项）"。实施报告 §10 已如实记为残留风险，但**设计正文没有登记**，这正是本项目要求"每个行为变更入册"的口径。

### Finding P2-3 — 设计 §3.9 测试表里的 `.xtboptok` "**非空**"是错的（LOW，文档）

- **证据**：上游 `touch_file` → `iohandler%touchFile` 用 `open(status='new')` 建文件后立即 `close`（`iohandler.f90:364-392`）⇒ 空文件。实施报告 §5 断言"存在且**空**"，`landscape_cli_check.py:3956-3957` 也是"非空即失败"——**实现是对的**，设计表行（`11-cli-redesign.md` §3.9 测试表 `landscape-file-contract-opt` 行）未同步订正。
- **最小修**：把设计表该行改成"存在且为**空**文件（上游 `touchFile` 建空文件）"。

### Finding LOW-1 — compliance 条件**没有反向用例**，`--ohess` 链也没有 compliance 断言（测试缺口）

- `check_file_contract_vib`（`landscape_cli_check.py:4002-4026`）只跑 `--lvib`（水）并断言"文件存在 + 内容含 `compliance.dat`"。缺：`$fix atoms:` 应为不写、`$fix freeze:` 的行为、单原子 `n == 1` 不写；设计 §3.9 表还要求"`--lopt`（→ `--ohess` 链）亦同"，实现里 `check_ohess_fail` 的成功对照只断言 `.xtboptok` + `hessian`，**没有**断言 `compliance.dat`。
- 若 P2-1 选 (a)：加 `$fix freeze:`/`$fix atoms:` 两条断言；若选 (b)：加"`$fix atoms:` ⇒ 无 `compliance.dat`"一条（这是判据本体的可证伪测试，目前判据本体零覆盖）。

### Finding INFO-1 — `landscape_file_contract_reset/mark` 的 `env` 形参未使用；写失败静默

- `log.f90:151-178`：`env` 声明了 `intent(inout)` 但函数体未用；`touch_namespaced`/`delete_namespaced`（`:198-232`）吞掉 `iostat`。上游 `touch_file`/`delete_file` 同样不报错（`filetools.F90:44-54`）⇒ **与上游同构**，仅记录（若日后想"绝不静默"，这里是唯一入口）。

### Finding INFO-2 — 提交卫生

- 仓库根有未跟踪的 `stage3b-workflow.js`（不在 `.gitignore` 内；`*.mod`/`*.out`/`xtbopt.log` 已被忽略，新增的 `xtbopt.log` 不会脏树）。提交时请只加 `src/`、`man/`、`test/`、`docs/_simplify-recon/` 的**有意**文件，勿误加该脚本（`docs/_simplify-recon/41,49,50,51-*.md` 是有意交付物，按项目惯例随阶段提交）。

---

## 3. 攻击面 1：文件契约语义是否与上游逐字一致

| 文件 | 判定 | 证据 |
|---|---|---|
| `.xtboptok` | ✅ 仅收敛时创建；开场删旧哨兵；失败不建 | `log.f90:151-178` ↔ `geoopt_driver.f90:112-113/183-186`；`opt.f90:153/238-243` |
| `NOT_CONVERGED` | ✅ 失败时建、与 `.xtboptok` 互斥 | 同上；测试 `:3988-3991` |
| `xtbopt.log` | ✅ 多帧 XMOL、无前导点、逐帧 `number=` | `log.f90:97-99/104-142` ↔ `geoopt_driver.f90:121` + `optimizer.f90:801` |
| `xtblast.xyz` | ✅ 仅失败写 + 打印消息 + 单帧 | `opt.f90:238-243`、`log.f90:181-196` ↔ `main.F90:1013-1018` |
| `compliance.dat` | ⚠️ **条件不同**（P2-1）；裸名 ✅ | `vib.f90:164-177` ↔ `hessian.F90:331`；`compliance.f90:287` 裸 `open` |

两点说明：(a) reset/mark 用 `settings%write_files` 门控，上游用 `pr`；今天 `write_files` 对可达路径恒为 `.true.`（`settings.f90:515` 默认真，`main.F90` 无写点），且子步骤（`relax_scan.f90:599`、`ts.f90:1224`、`irc.f90:717`）设假——但那些子步骤**不经**任务层（唯一调用点是 `landscape_driver.f90:91`）⇒ 无行为差异，不构成发现。(b) 上游对 `xtblast` 打印的是**未加前缀**名，套件打印带前缀名（更准确）。

## 4. 攻击面 2：`--namespace` 正确性

✅ 三个几何名全部走 `get_namespace`（`log.f90:76/97/99/186`），**没有**自己拼前缀；`compliance.dat` **没有**加前缀（`vib.f90` 不给名字）。`get_namespace` 与上游 `getName` 规则逐字相同（点开头 → `'.'//ns//file`）。测试 `check_file_contract_namespace`（`:4028-4062`）**双向**断言（既要有 `.c1.xtboptok`/`c1.xtbopt.log`，又要**不存在**裸名；`--lvib --namespace c1` 要有裸 `compliance.dat` 且**无** `c1.compliance.dat`）⇒ 本项目已犯过 4 次的"两套前缀约定"缺陷在此处不成立。

## 5. 攻击面 3：T2 的修法

✅ 判定 `lres%converged`（`main.F90:1105`）并跳过 vib 半，不是"清 env 错误掩盖"；`lres%converged` 有确定的默认值（`results.f90:289` `logical :: converged = .false.`），早期返回路径不会带出未定义值。跨半状态（同一 `calc` 对象）仍在，但**唯一**消费者被守卫封死 ⇒ 误导级联**结构上不可达**（不是"这次没出现"）。与原生**有意偏离**已登记（设计 §3.9 T2 段 + 报告 §8），我复核文本准确（原生 exit 0 + 仍写频率；套件 exit 1 + `NOT_CONVERGED` + 不写频率）。

## 6. 攻击面 4：可证伪性

✅ 注入打在判定/写点本体（报告 §6 `main.F90:1105`；validator §3 复现完整级联 + `cmp` 复原）。✅ 无恒真断言：`count_xyz_frames` 真解析帧、`.xtboptok` 查 `getsize`、xtblast 查单帧与消息、namespace 查"不存在"。✅ `.xtboptok` 的"仅收敛时"**双向**测（成功有 / 失败无）。⚠️ 唯一缺口见 LOW-1（compliance 判据本体零覆盖）。

## 7. 攻击面 5：数值不变

✅ 未动算法/收敛判据：diff 只改文件写入与失败分支（`log.f90` 重构为 `write_trajectory_file` 是同逻辑抽取；`opt.f90`/`vib.f90` 只加写点/调用；`main.F90` 只加守卫）；`settings.f90` 零改动。validator §4 实测 5 个任务（lopt/lscan/lts/lirc/lvib）输出**除版本串/计时/新增文件外逐字节相同**，能量/梯度/坐标/频率/IRC 路径零变化；`--lvib` 与原生 `--hess` 的 `compliance.dat` 数值相对差 ≈3e-11（同源正确）。唯一"输出变了"的是 `--lvib` 的 stdout 多一个块（P2-2，已登记为残留风险）。

## 8. 攻击面 6：越界

✅ 未做 R5 四轴（`set_conv_level` 字段集未动）、未做再基线、未做 `acc_was_set`；核心层未碰（validator `grep` 复核 = 0）；`xtb.trj` 未删；`src/type/latticepoint.f90` 未碰（改法是"不让错误产生"）。⚠️ 唯一越界是 T3 的 3 条文案（P1-1），以及 P0-1 所暴露的 `anyopt` 谓词问题（继承项）。

## 9. 攻击面 7：新引入的不实陈述（本项目的主题）

共 3 类、8 处：
1. `xhelp.f90:785-786/814-815/817-818` + `man/xtb.1.adoc:252-255/282-285/287-290` —— 6 处（P1-1）。
2. `vib.f90:166-173` 注释 + 报告 §2.4 + 设计 §3.9 表 —— "与上游同条件/同构"（P2-1）。
3. 设计 §1.2 "BC-4 只在两处违反" —— 已不再成立（P2-2）；设计 §3.9 表 `.xtboptok` "非空" —— 与实测矛盾（P2-3）。
（另：报告 §5 的"`xtbopt.log` 实测 6 帧"未说明 6 = 步数 5 + 1，validator L2 已提醒；属措辞，不单列。）

---

## 需运行验证（父会话执行；我无法运行命令）

1. **P1-1 的直接反证**：`xtb water.xyz --gfn2 --bhess --method ancopt` → 期望 exit 1 且消息含 `only available with --opt or --ohess`（证明新文案推荐的组合不可用）；`--bhess` 裸跑 stdout 应出现原生 `geometry_optimization` 头（证明不是套件）。
2. **P0-1 的前后对比**：`xtb <distorted>.xyz --gfn2 --omd --mdtime 0.5 --norestart` 与 `--metaopt`（或 `--screen`）在 HEAD 二进制 vs **stage-3a 之前的提交**二进制上对跑，期望 HEAD 缺前置优化块（症状：计时块打印 `ANC optimizer 0.000 sec`（`:5251-5254`）但无优化表头）；并观察 `--metaopt` 是否偶发 `Optimization did not converge, aborting`（未初始化 `murks`）。修谓词后复跑应恢复。
3. **P2-1 的 `$fix` 矩阵（4 组）**：`$fix` 含 `atoms: 1` 与含 `freeze: 1` 两种输入 × {套件 `--lvib`，原生 `--hess`}，记录 `compliance.dat` 是否出现；期望 `atoms:` 组 = 上游有/套件无，`freeze:` 组 = 上游无/套件有。
4. **修 P1-1/P0-1 后**：`ctest --test-dir <build> -R landscape`（期望 143/143）+ `-R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'`（12/12）；若动 `main.F90:987`，另加一条 `--omd/--metaopt/--screen` 的回归断言（现在零覆盖）。

---

## 10. 与 `51-stage3b-validation.md` 的关系（为何仍判"有条件接受"）

validator 的 PASS 建立在"实跑 T1/T2/T4 + 5 条新测试对新旧二进制红/绿"之上，我采信其实测数据。它的三个漏点是**语义层**：(a) §5 只核了"哪些行被改/未改"，未核"改后是否成立"⇒ 漏 P1-1；(b) §2/§3 未涉及 `$fix` ⇒ 漏 P2-1；(c) 未复查 `anyopt` 谓词对非改派 runtype 的可达性（只把 `:987` 当作"判据"记录）⇒ 漏 P0-1。它自己的 §7 L1（只有 opt 任务 reset 哨兵）我复核成立，但按设计 §3.9 的定义范围（只要求 opt 系写全 4 文件）属 **LOW/设计范围**，建议 3c 决策，不作为本轮发现。

---