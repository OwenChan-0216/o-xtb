## Review

**结论：接受（Accept）— CRITICAL 0 / HIGH 0 / MEDIUM 0 / LOW 3 / INFO 4。可以提交 git（P0/P1 为 0；LOW 是文字/行号类，不阻塞）。**

- **T1（HIGH-1）真修好**：`main.F90:999` 已用既有谓词本体 `landscape_is_suite_run(set%runtyp, landscape_native_engine)`（定义 `:4757`→`effective_landscape_task:4732`），非第二套判据；`--omd`/`--screen`/`--metaopt` 三条路径**同一条件**全部恢复原生块（`anyopt:329-331` 含三者，谓词对它们返回 false ⇒ `.not.` 为真 ⇒ 块可达）；`murks` 有初值 `:237`（`logical :: epr, diff, murks = .false.`）；全仓库 `anyopt` 读点仅 `:329/:333/:338/:999`，只有 `:999` 是同类读点，`:333/:338` 保留合理（upstream 对原生 `--opt` 同样 terminate ⇒ 注释"no native workaround either way"成立）。
- **T2（HIGH-2）已改回事实**：`xhelp.f90` 相对 HEAD **0 diff**（stat 表里无该文件）；`man/xtb.1.adoc` 仅余 `--opt`/`--ohess` 两处正确改派文案；`--bhess`(784-785)/`--omd`(813-814)/`--metaopt`(817-818) 与 man 253/282/286 逐字为准确的原生陈述，且**未反向改错** `--opt`/`--ohess`。
- **T3 诚实**：选 (b)，先证明 (a) 技术可行（`freezeset` 在 `xtb_fixparam` 中 public，`types/constraints.f90:64` 已有先例），再按"单一 `$fix` 真源"取舍并登记；条件与代码一致。
- **T4/T5 保留原文+指针** ✅（§1.2 引号订正 + §3.9 表行 + §10 B 类登记；`.xtboptok` **空**、`compliance.dat` **内容含**——上游 `touchFile`(`iohandler.f90:364-392`) 建空文件、`compliance.f90:290-291` 首行 `#` 均实测可核）。
- **可证伪性** ✅：注入打在谓词本体（§1.3）；`--omd` 断言 = `ANC micro-cycles` token + `xtbopt.xyz` 金标能量(1e-9) + O–H∈(0.9,1.05) Å，**不是**只看 exit code。
- **LOW-1**：`vib.f90:178-181` 的机制句"the frequency analysis projects with that mask"把机制归错层——`src/landscape/vib/**` 从不读 `fixset`/`landscape_frozen_mask`（`landscape_vib_analysis(env,mol,hessian,settings,vib,fail)`，无 frozen 形参）；真实机制是计算器层梯度置零（`src/xtb/calculator.f90:301-305`）+ 梯度型 FD（`types/hessian.f90:363-364`）⇒ 冻结分量成零行/列。修法：改一句措辞。
- **LOW-2**：`50-stage3b-impl.md:51-52` 仍写条件"与上游…**同构**"，与 `53 §3`/设计 §3.9"条件不同构"**直接矛盾** ⇒ P2-1 订正不完整（该文件本轮将随提交入库）。
- **LOW-3**：本轮在 `main.F90` 前插 11 行，`log.f90` 与 `landscape_cli_check.py` 的 docstring、报告 49/50 仍引 `main.F90:1012-1018`/`:1014`（murks 路径实际 `1024-1034`）；53 §1.1 的"`anyopt` = 9 处"实测 **11** 处。
- **INFO**：53 §1.2 与 §8.3 对**注入后** `--omd` 退出码自相矛盾（0 vs 1）⇒ 退出码不是稳健判据，红证据应引 token/几何；help 门槛只比集合（`landscape_help_check.py:120-127`）——文案类回归无法自动覆盖（已诚实登记）；`log.f90` 的 `!>` 文档仍只写 `xtbopt.xyz`/`xtb.trj`（代码已加 `xtbopt.log`）。
- **越界检查** ✅：核心层 7 目录 0 改动；未做 R5/再基线；`git add` 未做（`stage3b*.js`、报告文件均 untracked）；无重名 `add_test`。

需运行验证（我无法执行命令）：`ctest -R landscape`=145/145、回归子集 12/12、T1 注入红/还原绿、`--omd|--metaopt|--screen` 退出码 0/0/1 + `ANC micro-cycles`、`--bhess|--omd|--metaopt --method ancopt` → exit 1、以及 `git diff --cached --stat`（staged/unstaged 拆分我的工具看不到）。

---

# 阶段 3b 修复轮独立复核（`docs/_simplify-recon/54-stage3b-fix-review.md`）

对象：`docs/_simplify-recon/53-stage3b-fix.md` + 工作树 delta（相对 `b822c1f`；9 个已改文件 + 5 个 untracked 报告/脚本）。
方式：只读；以 file:line 静态核对为主，运行结果一律列为"需运行验证"。

## 1. 逐项核对

### T1（HIGH-1）`anyopt` 谓词 + `murks` 初值 — 修好

| 攻击点 | 结论 | 证据 |
|---|---|---|
| 是否用既有谓词本体（非第二套判据） | ✅ | `main.F90:999` = `if (anyopt .and. .not. landscape_is_suite_run(set%runtyp, landscape_native_engine)) then`；`landscape_is_suite_run` 定义 `:4757-4772` → `effective_landscape_task:4732-4749`；同一谓词亦用于 `:525`、`:1057`、`:1067`、`:1481` |
| `--omd`/`--screen`/`--metaopt` 三条都恢复原生块 | ✅ | `anyopt`(`:329-331`) 含三者；`effective_landscape_task` 对三者返回自身 ⇒ 非套件 ⇒ 块可达。三者的 `--method` **真的报错**（`:4381-4392` `case default` + `:4444` `case default`"，实测由 53 §2.2 给出）⇒ `landscape_native_engine` 恒 0 ⇒ 旧判据确使块不可达 |
| `murks` 有初值 | ✅ | `main.F90:233-237`（4 行 `!>` + `= .false.`）；唯一块外读点 `:1536`（metaopt），且该块外读点现在必然已被 `:1013` 赋值 |
| 是否还有别的同类读点 | ✅ 无 | `grep anyopt` 全仓库 11 处：`:200`(声明)、`:329`(定义)、`:333`/`:338`(保留)、`:509/:510/:986/:987/:989/:994`(注释)、`:999`(修) |
| `:333/:338` CPCM-X/PTB 保留是否合理 | ✅ | `if (allocated(set%solvInput%cpxsolvent).and.anyopt)` / `(set%mode_extrun==p_ext_ptb).and.anyopt` 是**响亮拒绝**；native `--opt` 也 terminate ⇒ 注释"no native workaround either way"成立；改判据反而会把响亮拒绝变成静默运行 |
| 注入打在谓词本体 | ✅ | 53 §1.3 即把 `:999` 还原为 `anyopt .and. landscape_native_engine /= 0`（非"等价替代实现"，符合 AGENTS §6 的第 4 条教训） |

### T2（HIGH-2）文案改回事实 — 逐行核对

| 位置 | 现文案 | 该 runtype 是否改派 | 一致 |
|---|---|---|---|
| `xhelp.f90:269-276` `-o, --opt` | "…landscape task suite (stage 3); the legacy ANCopt is reachable as `--opt --method ancopt`" | 是（3a） | ✅ |
| `xhelp.f90:277-295` `--method` | "…With `--opt` and `--ohess` the native engines ancopt(rf)/lancopt/fire/pbc_lbfgs are accepted" | — | ✅ |
| `xhelp.f90:299-306` `--lopt` | "minimize … landscape task suite"; `$scan` 段："use `--opt --method ancopt` for that block" | 套件 | ✅（`--opt --method ancopt` 确是 native 出口，`$scan` 守卫 `:525` 不触发） |
| `xhelp.f90:779-782` `--ohess` | "minimize … landscape task suite and run its harmonic frequency analysis (the legacy ancopt(3) plus numerical Hessian path is `--ohess --method ancopt`)" | 是（3a/3b） | ✅ |
| `xhelp.f90:784-785` **`--bhess`** | "on an ancopt(3) optimized geometry" | **否**（`getkopt.f90:142` 走原生 `geometry_optimization`） | ✅ |
| `xhelp.f90:813-814` **`--omd`** | "molecular dynamics simulation on ancopt(3) optimized geometry, a loose optimization level will be chosen" | **否** | ✅ |
| `xhelp.f90:817-818` **`--metaopt`** | "call ancopt(3) to perform a geometry optimization, then try to find other minimas by meta dynamics" | **否** | ✅ |
| `man/xtb.1.adoc:238-242/247-250` | `--opt`/`--ohess` 改派文案 | 是 | ✅ |
| `man/xtb.1.adoc:253-254/281-283/285-287` | `--bhess`/`--omd`/`--metaopt` 原生文案 | 否 | ✅ |

- `src/xhelp.f90` 的 `git diff --stat` **为空**（`watchdog_diff --stat` 的 9 文件清单里没有它）⇒ 3 处回退彻底；`man/xtb.1.adoc` 仅两处改派文案。
- 未发现"反向改错"：`--opt`/`--ohess` 的现文案与 3a/3b 的实际行为一致（`--ohess` 链见 `main.F90:1106-1162`）。
- 全仓库扫描（`src/`、`man/`）未发现残留的不实陈述：`landscape suite` 只出现在 `--opt`/`--ohess`/`--method`/`--lopt*` 段。

### T3 `compliance.dat` 条件 — 选 (b)，诚实

- (a) 可行性查证成立：`src/fixparam.f90:30` `type(fix_setvar) :: freezeset`（module 无 `private` 默认限制，`private :: wp` 仅此项）⇒ 套件可读；先例 `types/constraints.f90:64`。
- 两个名单确是两个键：`src/constrain_param.f90:338` `case('atoms')`→`fixset`、`:348` `case('freeze')`→`freezeset`（我逐段读了两个分支）；上游读 `freezeset`：`src/hessian.F90:331`。
- `mol%npbc == 0` ≡ `.not. set%periodic`（`main.F90:569` 无条件 `set%periodic = mol%npbc > 0`，在 Hessian 之前）✅；周期系统在 `landscape_driver.f90:73-77` 就被拒 ✅。
- 措辞与代码一致（条件就是 `mol%n > 1 .and. .not. any(landscape_frozen_mask(mol%n)) .and. mol%npbc == 0`）；差异登记在 `11-cli-redesign.md` §3.9 表行 + 新测试 + `vib.f90` 注释。**唯一保留意见见 LOW-1/LOW-2。**

### T4/T5 订正 — 保留原文 + 指针 ✅

- §1.2：原文句保留，其后插 `> **[订正 T4，阶段 3b 修复轮]**` 引号订正（"两处"→"至少三处"），R11 段仍独立可读。
- §3.9 表：`.xtboptok` 行由"**非空**"改为"**为空**（`iohandler.f90:364-392` 的 `touchFile` 建空文件；订正 T5）"；`compliance.dat` 行"**首行**含"→"**内容含**（订正 T5：首行是 `#`…）"。两条订正都**引用了被推翻的旧措辞**，指针齐全。
- 二级核对：`touchFile`(`iohandler.f90:379-387`) 确为 `status='new'` + 立即 `close` ⇒ 空文件；`compliance.f90:290/291` = `"#"` / `"# compliance.dat"` ⇒ "首行 `#`、串在第 2 行"成立。
- §10 B 类新增 `[登记 T4]`：`--lvib` stdout 的 compliance 块 + 新文件 `compliance.dat` + 两条验收测试；与 BC-3"集合不小"一致。

### T6 反向用例 — 判据可证伪（未实跑）

- 新 `check_vib_compliance_skip`：单原子（`mol%n > 1` 假）与 `--input <$fix atoms: 1>`（掩码非空）**都断言 `compliance.dat` 不存在**，且断言 exit 0（单原子）与 `hessian` 存在（固定原子）；删任一子句 → 对应用例写文件 → `os.path.exists` 必红。逻辑成立（53 §6.1 诚实说明"未做完整注入复测"）。
- `check_file_contract_vib` 新增 `--ohess` 半断言（`hessian` + `compliance.dat`）✅ 与 `main.F90:1106-1162` 的链一致。

## 2. 越界 / 硬约束

- 改动文件 9 个：`docs/_simplify-recon/11-cli-redesign.md`、`man/xtb.1.adoc`、`src/landscape/tasks/{opt,vib}.f90`、`src/landscape/types/log.f90`、`src/prog/main.F90`、`test/unit/{CMakeLists.txt,landscape_cli_check.py,meson.build}`。**核心层（type/xtb/mctc/param/io/disp/coulomb）0 命中** ✅；`src/prog/main.F90` 是既定集成点。
- 未做 R5 / §3.10 再基线 ✅；未改算法与收敛判据 ✅。
- 未 `git add`：`stage3b-workflow.js`、`stage3bfix-workflow.js`、5 个报告均为 **untracked** ✅。（提醒：`docs/_simplify-recon/*.md` 是**入库目录**，提交时需把 41/49/50/51/53/54 一并 `git add`，workshop 脚本才保持 untracked。）
- `add_test` 无重名：7 条新/改测试名各出现 1 次；CMake 与 meson 两条注册路径齐全（meson 未在本机验证，已在 53 §7 登记）。

## 3. Findings

### LOW-1（P2）`vib.f90` 新机制句把机制归错层
- 位置：`src/landscape/tasks/vib.f90:178-181`。
- 证据：`grep -n landscape_frozen_mask src/landscape` 命中 `tasks/opt.f90:171`、`tasks/ts.f90:254/1271`、`tasks/irc.f90:220/731`、`scan/relax_scan.f90:669`、`optimize/driver.f90:95`、`types/constraints.f90`；**`src/landscape/vib/**` 无命中**。`landscape_vib_analysis(env, mol, hessian, settings, vib, fail)`（`vib/modes.f90:116`）没有 frozen 形参，投影是 Eckart（平移/转动）。真实的"冻结分量无 Hessian 信息"来自：`src/xtb/calculator.f90:301-305` 每次单点把 `$fix` 原子的梯度置零 + 数值 Hessian 由**梯度**中心差分构成（`types/hessian.f90:363-364`）⇒ 冻结分量为精确零行/列。另 `vib/thermo.f90:138-139` 明确写"the landscape suite never [freezes]"，与"the frequency analysis projects with that mask"直接冲突。
- 为何报告：本方向已有两次"机制句写错"的教训（M3 `trproj` 梯度项）。
- 最小修法：把这半句换成按上面链条的措辞（"the frozen components carry no Hessian information: the calculator zeroes their gradient, which the gradient-based finite differences propagate into zero rows and columns (`src/xtb/calculator.f90:301-305`, `types/hessian.f90:363`)"）。**判定 (b) 的结论本身不受影响**（前提实质成立）。

### LOW-2（P2）P2-1 的订正漏掉实施报告，`50-stage3b-impl.md:51-52` 仍称"同构"
- 位置：`docs/_simplify-recon/50-stage3b-impl.md:50-52`（"条件与上游 `src/hessian.F90:331` **同构**：…"）。
- 证据：`53 §3` 与 `11-cli-redesign.md` §3.9 表行已改为"**条件不同构（订正 T3）**"；`vib.f90:171` 也改成"deliberately not upstream's"。50 未同步 ⇒ **同一提交内**两份报告互相矛盾，而 50 将被 `git add`。
- 最小修法：50 §2.4 加一句指向 §3.9 的"条件不同构"登记（或改写该半句）。

### LOW-3（P2）行号漂移 + 一处计数错
- 本轮在 `main.F90` 谓词处净插 11 行，但下列引用仍是**修前**编号，指向 `geometry_optimization` 调用而非 murks/xtblast 路径（实际 `main.F90:1024-1034`）：
  - `src/landscape/types/log.f90`（`landscape_write_last_geometry` 的 `!>`："mirrors the `murks` path … `src/prog/main.F90:1012-1018`"）；
  - `test/unit/landscape_cli_check.py`（`check_file_contract_opt_fail` docstring 同串）；
  - `docs/_simplify-recon/49-stage3b-recon.md:226-227`（`:1014`/`:1012`）、`50-stage3b-impl.md:48`（`:1012-1018`）。
- 计数：`53 §1.1` 写"`grep -n anyopt` 全仓库 = **9 处**"，实测 **11 处**（`:200,329,333,338,509,510,986,987,989,994,999`）。
- 最小修法：把这 5 处行号改为 `1024-1034`（或统一"按过程名引用"），并把 9 改为 11。属本方向已多次出现的 LOW 行号类。

### INFO-1 `53 §1.2` 与 `§8.3` 对**注入后** `--omd` 退出码自相矛盾
- §1.2 表："3a/3b（修前）exit **0**，micro-cycles 0"；§8.3 第 3 条："注入后的 `--omd` **不是** exit 0…而是 exit **1**"。两者都是同一缺陷状态，差异只能来自 MD 的每进程随机 seed（§1.4 也承认 seed 随机）。
- 影响：T1 的**红**证据若只被退出码断言捕获，会随 seed 摇晃。测试里真正稳健的判据是 `ANC micro-cycles` token、`xtbopt.xyz` 金标能量、O–H 窗口——建议 53 在 §1.3/§8.3 明确写这三者，并把退出码降级为"附加"。

### INFO-2 文案类回归无自动门槛（已登记，接受）
- `test/unit/landscape_help_check.py:120-127` 只做集合 `s_main ^ s_help` 差集；P1-1 正是"集合不变、语义变错"绕过验证的实例。53 §6.3 已把它登记为门槛缺陷并给出 3c 建议（如"`--method ancopt` 只允许出现在 `--opt`/`--ohess`/`--lopt` 段"）。本轮**不修门槛**是合理的范围控制，但意味着 **HIGH-2 类问题只能靠人读**，记入残留风险。

### INFO-3 `log.f90` 文档与 stdout 契约
- `log.f90:53-60` 的 `!>` 与 `:19-30` 的模块文档仍只描述 `xtbopt.xyz`/`xtb.trj`，未提本轮新增的 `xtbopt.log` 第二写点（代码 `:88-96` + 内联注释有）。AGENTS 要求"每个 module/type/公开过程都有 `!>` 文档" ⇒ 补一句即可。
- `landscape_write_last_geometry` 打印 `fname`（**已加命名空间**），而上游 `main.F90:1027-1028` 打印的是裸 `tmpname`（文件实际带前缀）。这是 `--namespace` 下与上游 stdout 的一处既存差异，未在 §3.9/§10 登记（影响极小，测试断言的是子串）。

### INFO-4 `main.F90:1110-1162` 的 `if (lres%converged)` 体未重排缩进（3b 代码，纯风格）
- 守卫插入后体内 30 余行仍与 `if` 同级；同段还保留了 HEAD 既有的两处同字符串 `call env%checkpoint("Landscape task terminated")`（`:1116` 与 `:1162`，非本轮引入）。属可读性，非行为。

## 4. 需运行验证（复核者不能执行命令）

1. `cmake --build /tmp/xtb-3bf/build -j && ctest --test-dir /tmp/xtb-3bf/build -R landscape` → 期望 **145/145**；`ctest -N -R landscape` 与 `grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d`（期望空）。
2. `ctest --test-dir /tmp/xtb-3bf/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'` → 期望 12/12。
3. **T1 注入复测**：`main.F90:999` 还原为 `anyopt .and. landscape_native_engine /= 0` → `ctest -R 'landscape-(native-runtypes-unaffected|vib-compliance-skip|file-contract)'` 必须红（记录的失败行）；还原 → 6/6 绿。
4. `--gfn 2 --omd|--metaopt|--screen --norestart`（扭曲水 fixture）：退出码 **0/0/1**、stdout 含 `ANC micro-cycles` 与 `optimized geometry written to:`、`xtbopt.xyz` 能量 = `-5.070544363296`（1e-9）、最长 O–H ∈ (0.9,1.05) Å ——即"先优化"确实发生（这是区分 pre/post 的关键，不是退出码）。
5. `--bhess|--omd|--metaopt <xyz> --gfn 2 --method ancopt` → 期望 **exit 1** + `only available with --opt or --ohess`（HIGH-2 的实测依据）。
6. `--lvib --input <$fix atoms: 1>`（无 `compliance.dat`、有 `hessian`）与单原子 He（`--lvib` exit 0、无 `compliance.dat`）；`--ohess --norestart` 有 `hessian`+`compliance.dat`+`vibspectrum`。
7. `git status --short && git diff --cached --stat`：确认本轮的 untracked 报告/脚本**未** staged（我的工具只给合并 delta，无法拆分 staged/unstaged）。
8. meson 注册（无 meson/ninja 时可跳过，但需在残留清单保持登记）。

## 5. 接受度与残留风险

- **接受，可以提交 git**：两项 HIGH 均已按证据闭合；无 P0/P1；LOW-1..3 为文字/行号类，可随提交顺手修（不修也应登记，因为其中 LOW-2 是"同一提交内两份报告自相矛盾"）。
- 残留：meson 未验证；文案类回归无自动门槛（INFO-2）；`--lvib`/`--ohess` 的 stdout 新增 compliance 块对外部逐行比对脚本的提示属文档级（已在 §10 B 类登记）；`--namespace` 下 `last geometry written to:` 的裸名/前缀差异（INFO-3）；`--lscan/--lts/--lirc/--lvib` 不 reset 哨兵（`51 §L1`，交 3c）。