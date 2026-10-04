## 摘要（≤30 行）

- **结论：有条件接受（CRITICAL 0 / HIGH 0 / MEDIUM 2 / LOW 3 / INFO 3）。**
- **能否提交 git：不建议现在提交**——先修 M1（`main.F90:138` 模块级可变变量，设计 §3.11:954 明文禁止，4 行改动）+ M2（`xhelp.f90:319/396/440/626` 仍写 "default 256"，4 条字符串），其余均可提交。
- 四轴数值**逐值核对通过**：`settings.f90:1165-1199` vs 设计 §3.5 表 vs 上游 `get_optthr`（`optimizer.f90:48-119`）；`clamp(n×mult,200,10000)` 与上游 `:113-114` 同规则，`n = mol%n` 与上游调用点 `:332` 一致。
- `acc` 六处写入点**全部**改为条件写（`main.F90:1104/1137/1185/1207/1237/1253`），`grep 'engine%acc = set%acc'` 无条件命中 = **0**；`set%acc` 的唯一来源是 `--acc`（`:1932-1938`）+ parmfit（`set_module.f90:1177`），守卫在实战上完整。
- 优先级**与顺序无关**：`--l*-max-steps`（`:2608/2917/3059/3790`）与 `--cycles` 桥（`:4531-4548`，位于解析尾、先于 `xtbMain` 分派）都写 `max_steps_source`；冲突检测（异值报错）仍在；上游同为「显式覆盖派生」（`relaxation_engine.f90:237-239`）。
- `e_tol` 回显取自设置对象且 5 个 CLI 可达任务齐全（opt/scan/ts/irc/vib）；sp 无 CLI 入口（`test/unit/CMakeLists.txt:3204` 注释），无需回显；唯一行为读点 `settings.f90:1125` + 3 处拷贝（`relax_scan:601`/`irc:730`/`ts:1224`），**无死旋钮**。
- 可证伪性成立：新 `xtb/landscape-level-axes`（`landscape_cli_check.py:4373-4459`）钉三轴+显式优先；既有 `check_acc`（`:181-190`）反向钉住「显式 `--acc` 必须生效」，两条互为反向突变守卫。
- `(not used: ...)` 断言改写的**强度损失评估**：真实 Hessian notice 一律含 "Hessian"（`engine.f90:890-892`、hints 见 `cli_check:3404/3408/3451`），故消费侧断言仍能抓住真失败；这是**必要**改写（3c 新增两条无关 notice），非放水。
- 唯一可能动的验收数字组（M3/M7 `--lopt-level tight` dfreq）由**已注册 ctest** `xtb/landscape-e2e-chain`（`CMakeLists:3305-3311`）覆盖 ⇒ 报告「未动」有测试背书。
- 越界检查：改动 6 个源码文件（`settings.f90`、`main.F90`、5 个任务 banner）+ 文档 + 测试；`src/type|xtb|mctc|param|io|disp|coulomb` 0 触碰；未重做 3a/3b。
- 未重测项已**诚实列出**（§4 未做项 1-5），但设计 §3.10 要求「逐个重测」，M2 滞回 77 文件与 M4 dimer 7.7397e-05 属**披露的偏离**，需父会话显式裁定。
- P2 提醒：报告 §3 用 CH3OH `--lopt` 的 177 次引擎求值推断 **scan 内层弛豫**未触预算，是跨任务类比（本项目已 4 次被实测推翻静态推断）。

---

## 完整正文（供落盘 `docs/_simplify-recon/57-stage3c-review.md`）

# 阶段 3c 独立复核（只读）

对象：`docs/_simplify-recon/55-stage3c-impl.md` + 工作树 delta（相对 `8b85c6d`）。
方法：逐 file:line 读源码（`settings.f90` / `main.F90` / 5 个任务 / `xhelp.f90` / 上游 `optimizer.f90`）、读设计与 `49-stage3b-recon.md`、读测试 delta。**未运行任何命令。**

## 0. 结论

- **CRITICAL 0 / HIGH 0 / MEDIUM 2 / LOW 3 / INFO 3。**
- **阶段 3c 现在不宜直接提交**：先修 M1、M2（合计约 8 行，零风险），其余全部通过。修完即为 **accept**。
- 本轮改动的算法性风险为零：四轴数值与上游逐值一致，落点全在设置层/分派层，未触碰数学本体与核心层。

## 1. Correct（已核对为正确，附证据）

1. **四轴数值逐值一致**（设计 §3.5 表 = 上游 = 代码）
   `settings.f90:1165-1167`（superloose `e_tol` 5e-4 / acc 3.0 / mult 1）、`:1173-1175`（5e-5 / 2.0 / 2）、`:1181-1183`（5e-6 / 1.0 / 3）、`:1189-1191`（1e-6 / 0.2 / 5）、`:1197-1199`（1e-7 / 0.05 / 20）；
   对照 `src/optimizer.f90:59-105`（crude 5e-4/3.0/n、loose 5e-5/2.0/n*2、default 5e-6/1.0/n*3、tight 1e-6/0.20/n*5、vtight 1e-7/0.05/n*20）。**5 档 × 3 轴全部一致**。
2. **`clamp` 与原子数**
   `settings.f90:1225` `max_steps = min(max(natoms*mult,200),10000)`；上游 `optimizer.f90:113-114` 同式；`n` 的语义 = `mol%n`（上游调用点 `:332`、`relaxation_engine.f90:237`/`:523`），套件分派点同用 `mol%n`（`main.F90:1108/1187/1208/1238`）。**逐字同规则**。
3. **`acc` 六处写入点全部条件化**
   `main.F90:1104`（lopt）、`:1137`（`--ohess` vib 半）、`:1185`（lscan）、`:1207`（lts）、`:1237`（lirc）、`:1253`（lvib）均为 `if (acc_was_set) ... = set%acc`；`grep '%acc\s*='` 在 `src/` 内**无**无条件 `engine%acc = set%acc` 残留。默认档派生值仍为 1.0（`settings.f90:1182`）⇒ **默认行为不变**。
4. **`set%acc` 的来源是封闭的**（守卫完整性）
   `set%acc` 全仓库仅 3 个写点：`setparam.f90:227` 初值 1.0、`main.F90:1932/1936/1938`（`--acc`，`:1943` 置 `acc_was_set`）、`set_module.f90:1177`（`set_fit` = parmfit 路径，与套件 runtype 不可共存）。**无 xcontrol 键写 `set%acc`**（`grep -i accuracy` 只命中 `xtb_mctc_accuracy`/打印串/`set%accu_hess`/`accu_md`）。
5. **优先级与定序**
   `max_steps_source`（`settings.f90:397`，`:1221-1223` 非空即跳过派生）由 4 个旗标（`:2608/2917/3059/3790`）与 `--cycles` 桥（`:4531-4548` 的 `budget_source`，`:4737-4741`）写入；桥位于 `parseArguments`（`:1668-4572`）**末尾**，先于 `xtbMain` 的四处分派 ⇒ 与命令行顺序无关。冲突检测（异值 `env%error`、同值幂等）未被改动。上游同规则：`relaxation_engine.f90:238-239` `if (maxstep > 0) maxcycle = maxstep`。
6. **`e_tol` 回显同源、无死旋钮**
   回显值取自设置对象（`tasks/opt.f90:122`、`scan.f90:149`、`ts.f90:176`、`irc.f90:168`、`vib.f90:146-147`）；消费点 `settings.f90:1125`（唯一行为读）+ `relax_scan.f90:601` / `irc.f90:730` / `ts.f90:1224`（同一对象拷贝）。刚性扫描与 `--lvib` 的 `(not used: ...)` 两处提示与其真实消费关系一致（`scan.f90:151-153` 条件于 mode、`vib.f90:148-149` 无收敛循环）。sp 任务为 API-only（`test/unit/CMakeLists.txt:3204` 注释 + `landscape_driver.f90:80-86`），无 CLI 入口 ⇒ 不构成缺口。
7. **可证伪性双向闭合**
   `xtb/landscape-level-axes`（`landscape_cli_check.py:4373-4459`）断言默认档三轴 + loose/tight/superloose 的 `e_tol` + loose 的 acc 2.0 + 显式 `--acc` 优先 + `--l*-max-steps 8`/`--cycles 4` 优先；既有 `check_acc`（`:181-190`）断言默认 1.000000 与 `--acc 0.05` 必须改变结果 ⇒ 守卫的两个方向都有突变守卫。单测 `level-step-budget`（`test_landscape_settings.f90:364-405`）覆盖 clamp 两端 + 500 原子缩放 + 显式优先；`convergence-levels`/`enum-case` 扩到三轴。登记齐（CMake `test/unit/CMakeLists.txt:3777-3788` + 属性块 `:3912` 带 `OMP_NUM_THREADS=1`；meson `test/unit/meson.build:899-905`）。
8. **notice 断言改写未放水（逐条判据）**
   真实 Hessian notice 全部含 "Hessian"/"finite"（`:890-892` reason 串、hints `cli_check:3404/3408/3451/3457/3500`）⇒ `hint is None` 分支仍能抓住「消费了却报未用」；`hint` 分支由「首条必须匹配」放宽为「任一条匹配」，对当前唯一 notice 生产者语义等价，且更稳健（多条共存时不再误红）。
9. **再基线中唯一可动人数字组由 ctest 背书**
   M3/M7 链 `--lopt --lopt-level tight` 的 dfreq 由已注册的 `xtb/landscape-e2e-chain`（`CMakeLists:3305-3311` → `landscape_e2e_check.py:277-292`，容差 0.20）覆盖，报告 §2 行 2 的「0.0100 未动」不是静态断言。
10. **越界检查**：delta 仅 `settings.f90`、`main.F90`、`tasks/{opt,scan,ts,irc,vib}.f90` + 设计文档 + 测试；核心层 `src/type|xtb|mctc|param|io|disp|coulomb` 0 触碰；未重做 3a/3b（`landscape_bridge_step_budget` 仅加一个 optional 参数）。

## 2. Finding

### M1（P1）模块级可变变量 —— 与 AGENTS §5 硬约束、设计 §3.11 明文条款冲突
- 位置：`src/prog/main.F90:138` `logical :: acc_was_set = .false.`（位于 `module xtb_prog_main` 的 `private` 区，`contains` 之前）。
- 证据：
  - 该模块此前**没有任何**模块级变量（`:100-114` 全是 `use ... only:`，`:124-127` 是 `implicit none`/`private`/`public :: xtbMain`）⇒ 3c 引入了第一个。
  - 设计对其**同类**状态位的规定（`11-cli-redesign.md:953-954`）：「`program xtb` 的局部变量，与 `lruntyp_flag` 并列；由 `parseArguments` … 作为 `intent(out)` 参数回传——**不进 `set%`、不新增 runtyp、不引入模块级可变变量**」。实际 `landscape_native_engine` 是 `xtbMain` 局部（`:258-262`），并经 `intent(out)` 传入 `parseArguments`（调用点 `:275-277`）。
  - AGENTS §5「Hard constraints — do not regress these」第 3 条：**No module-level mutable variables. Settings are passed as explicit objects.**
  - 报告 §0 T2 行写「（`program xtb` 局部）」——文件里**不存在** `program xtb`（唯一 program 是 `src/prog/primary.f90:19` `program xtb_prog_primary`），且该变量是模块状态；这属本项目主题（不实陈述）范畴，措辞与设计 `:953` 的同款措辞同源，但结论仍不成立。
- 影响：**无功能缺陷**（`:1823` 每次 `parseArguments` 开场复位，C API 重入安全；设置对象本身是 `xtbMain` 局部，每次新建）。属架构/约束违反 + 表述不实。
- 最小修法：在 `xtbMain` 局部（紧邻 `:262`）声明 `logical :: acc_was_set`，给 `parseArguments` 增加尾随 `intent(out) logical :: acc_was_set`，调用点 `:275-277` 补一个实参（与该子程序既有的 `landscape_native_engine` 完全同构）。或改用本项目更惯用的 `*_source` 字段（见 `max_steps_source`/`hess_acc_source`）。

### M2（P1）`--help` 仍记载旧默认值 256（用户可见的不实陈述，由本 diff 造成）
- 位置：`src/xhelp.f90:319`（`--lopt-max-steps` "default 256"）、`:396`（`--lscan-max-steps`）、`:440`（`--lts-max-steps`）、`:626`（`--lirc-max-steps`）。
- 证据：3c 之后未给旗标时的有效默认是 `clamp(n×mult,200,10000)`（水 → 200），新 CLI 测试自己就钉了 `200`（`landscape_cli_check.py:3093-3102`、`:4420-4422`）；`xhelp.f90` 未在本轮改动（delta 不含它）。阶段 1 建立的 `--help` 一致性门槛只查**旗标集合**，不查取值文本 ⇒ 不会被自动拦下。
- 同类（同一 diff 造成的语义过时）：档位旗标的帮助文本仍只写「阈值」——`:309-310`（`--lopt-level`）、`:372-373`（`--lscan-level`）、`:442-443`（`--lts-level`）、`:628-630`（`--lirc-level`），而 3c 之后档位同时驱动 `e_tol`/`acc`/步数预算。
- 最小修法：四处改 `(default: clamp(3 × atom count, 200, 10000), derived from the convergence level)`，四处档位文本补「+ energy tolerance, SCC accuracy, step budget」。

### L1（P2）报告 §3 的机制推断为跨任务类比
- 位置：`55-stage3c-impl.md` §3 第一段：「实测内层弛豫在 normal 档只需 177 次引擎求值（设计 §3.5 [实测] 表），远未触到 200 个宏观步」。
- 证据：177 evals 是 `--lopt --lopt-engine sd`（CH3OH，设计 §3.5 `[实测]` 表）的**最小化**计数，不是 scan 的 `relax_scan` 内层计数；且「引擎求值」≠「宏观步」。
- 处置建议：把该句降级为「判定（未实测）」或补一次默认档 scan 的滞回点重跑。**不影响提交**，但属本项目已 4 次被实测推翻的静态推断类型。

### L2（P2）设计 §3.10 的「逐个重测」有两项以判定替代
- `55-stage3c-impl.md` §2 行 5（M4 dimer-vs-prfo 7.7397e-05「未重测」）与行 14（M2 滞回 77 文件「未重跑」）。
- 证据：设计 `11-cli-redesign.md:873-895` 明确列出这两项为「需重测」，且 §3.10 正文要求「逐个重测 → 只在意处更新 golden」。报告在 §4 未做项 1/2 中**主动披露**并给出理由 ⇒ 诚实，但与设计要求不一致。
- 处置建议：父会话显式裁定「接受判定」或补测。若要把 7.7397e-05 冻结为 golden，需先给 `test_landscape_saddle.f90` 加打印点（报告 §2 行 5 自己指出当前只有 `:968` 一处 RMSD 打印）。

### L3（P2）「dfreq 未动」的精度口径
- 报告 §2 行 2 报 `max dfreq 0.0100 cm^-1`（`landscape_e2e_check.py:289` 四位小数打印）。所谓「同」只能覆盖 [0.00995, 0.01005)，与 M7 的 0.0100 不构成逐位同一。建议措辞改为「在打印精度与容差 0.20 内未变」。

### INFO-1 `--ohess <level>` 两半精度不对称（报告 §7.1 的待裁定项）
- 现状：min 半取档位派生 `acc`（`main.F90:1104` 路径 + `:1108` 预算），频率半保留 `lvset` 默认 1.0（`:1137`，仅 `--acc` 显式时被覆盖）。
- 支持现状的证据：上游原生路径同样两半不同精度（`src/hessian.F90:174` 把 `calc%accuracy` 设为 `set%accu_hess`，`:259` 复位）；且套件 FD Hessian 用 `engine%hess_acc`（`settings.f90:348`，0.3）而非 `engine%acc`。⇒ 建议**保持现状并在设计里记一句**，不要为「对称」而改数值。

### INFO-2 库默认 256 与 CLI 默认 clamp(3n,…) 并存
- `settings.f90:384` `integer :: max_steps = 256` 未变（`test_landscape_settings.f90:57/184` 仍钉 256），派生只在 `xtbMain` 分派点发生 ⇒ 库调用者（含 API-only 的 sp 任务、e2e 单测）仍是 256。字段注释（`:385-391`）与报告 §5.1 都写明这一点，属**有意设计**；建议在 `docs/xtb-landscape-M7-validation.md` 或设置模块头再加一行「library default ≠ CLI default」以免后续误判。

### INFO-3 提交卫生
- untracked：`docs/_simplify-recon/55-stage3c-impl.md`（应随本次提交 `git add`）、`stage3c-workflow.js`（仓库根的编排脚本，**不应**入库；建议移出或加 `.gitignore`）。
- `AGENTS.md`（gitignored 会话状态）现写「阶段 2 / 2b / 3a / 3b / **3c** 均已实施并提交」，而 3c 尚在工作树 ⇒ 提交后该句才成立（或改为「3c = 未提交的工作树」）。

## 3. 需运行验证（复核者无法执行）

1. **全量 landscape**：`ctest --test-dir <build> -R landscape` → 期望 **146/146**（报告 §4；同时确认第 146 个 `xtb/landscape-level-axes` 真的跑了，不只是登记）。
2. **回归子集**：`ctest -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'` → 期望 12/12。
3. **唯一可能动的验收数字组（最高价值）**：`python3 test/unit/landscape_e2e_check.py chain <xtb> test/unit/landscape_h2o.xyz <dir>` → 确认打印的 `max dfreq`（报告 0.0100，容差 0.20）与 dZPE/dH/dG（1.429e-08 量级）。报告的行 2/3 依赖它。
4. **报告 §1 的两次注入复现**：(a) 把 lopt 分支的 `if (acc_was_set)` 改回无条件 ⇒ `ctest -R landscape-level-axes` 必红；(b) 删 `call lset%level_step_budget(mol%n)` ⇒ 同测试必红。还原后绿。
5. **ctest 重名检查**（AGENTS §4 的静默丢弃陷阱）：`ctest -N -R landscape` 计数 + `grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d` 应为空。
6. **M1/M2 修完后**：重跑 (1)(2) 与阶段 1 的 `--help` 双向一致性脚本（只改文本，不应影响旗标集合）。
7. 可选但建议：默认档 scan 的一个滞回点重跑（替换 L1 的类比推断）。

## 4. 复核者声明

- 本复核为只读：未运行命令、未修改任何文件、未写 `progress.md`（任务要求最终回答即完整报告正文，由父会话落盘）。
- 结论基于 delta（`watchdog_diff`，相对 launch HEAD）与源码/设计/计划文本的直接读取；`ctest` 结果与 §3 各项均**未**由我复现。