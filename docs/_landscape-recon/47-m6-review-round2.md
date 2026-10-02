I have completed my independent read-only review. Below is the summary (≤30 lines) followed by the full report body.

---

# 47 — M6 修复轮独立复核（第 2 轮，fresh context，read-only）

**结论：接受（accept）— M6 现在可以提交。0 CRITICAL / 0 HIGH / 0 MEDIUM / 4 LOW / 6 INFO。** 45 的 5 条 MEDIUM 在**实质**上全部关闭（M-1 真生效、M-2 的 `rmsd_end` 真生效、HPC Hessian 注释订正、irc-pc OMP 已补、F-1 真修而非只写说明、GS 质量有可证伪断言+PLAN 待办）。我独立重列了全部 27 个 `--lirc-*` 并逐行核对链路，**报告 46 §2.4 的表格完整、无遗漏**，两条「死旋钮」的读取链已完整（`main.F90:3315 → settings.f90 g_* → tasks/irc.f90:568-572 → optimize/driver.f90:500-502`；`main.F90:3532 → tasks/irc.f90:312/315 → endpoint_reached:602-624`）。**未发现任何会改变物理/数值行为的新缺陷**，默认路径逐位中性（`relax_endpoint` 新增的 6 个拷贝在默认档位下等于优化器默认值，故 42 的 10 个 GS 数字保持逐位，§11.1 的「前 100 行 diff 为空」自洽）。

| 45 项 | 判定 | 证据 |
|---|---|---|
| M-1 `--lirc-level` | **已修复（真修）** | `tasks/irc.f90:567-572`；消费者 `optimize/driver.f90:500-502`；CLI `landscape_cli_irc_knobs.cmake` N/E 双断言 |
| M-2 `rmsd_end` | **已修复（真修）** | `tasks/irc.f90:602-624` + 调用 312/315；单元 `endpoint-rmsd-criterion`；CLI F/T |
| M-3 HPC Hessian `!>` | **已修复（文档）** | `hpc.f90:70-77`、`corrector.f90:843-847` 均改为「只用接受点 secant」 |
| M-4 `irc-pc` OMP | **已修复（CMake）；meson 侧未同步** | `CMakeLists.txt:2692`；meson 无 swap、`irc minimum` 仍无 OMP → LOW-1 |
| M-5 GS 球弛豫质量 | **已修复为「可见化」** | 单元 `gs-sphere-relaxation-quality`（独立球面参考）+ `n_pinned` CLI 断言；Lagrange 未做但有 PLAN §6.5 待办行 |
| 45-L6 `1.4e-2` | **部分修复** | 源/PLAN 已清，但替换范围 `1e-3..1e-2` 不覆盖同句引用的 V2=4.56e-2 → LOW-2 |
| 45-L1/L2/L3/L4/L5/L7/L9、I-2 | 已修复 | 见正文 §1 |
| 45-L8(F-1) | 已修复（真修 + 测试） | `corrector.f90:970-995`、`937-951` |
| 45-I-1/I-3/I-4 | 未修（复核已判非缺陷，改动会触碰已验收数字） | `hpc.f90:254`、`eulerpc.f90:242`、`landscape_driver.f90:175` |

进 M7 前**必须**解决：无。建议在 M6 提交前一并收掉 LOW-1（meson 同步）与 LOW-2（范围改 `1e-3..5e-2`）。

---

## 0. 范围、方法与限制

- 复核对象：`46-m6-fix-report.md`、`45-m6-independent-review.md`、`44-m6-validation-experiments.md`、`docs/xtb-landscape-PLAN.md` §5.3.7/§6.5/§12.14/§12.15、`43-*.md`，
  以及当前源码 `src/landscape/irc/{gs,hpc,eulerpc,lqa,corrector}.f90`、`tasks/irc.f90`、`types/{settings,results}.f90`、`landscape_driver.f90`、`prog/main.F90`、`xhelp.f90`、
  `test/unit/{CMakeLists.txt,meson.build,main.f90,landscape_cli_check.py,test_landscape_irc.f90}`。
- 只读工具；**未运行任何命令**（无法构建/ctest/pytest）。
- `watchdog_diff` 事实：`src/landscape/irc/*.f90`、`tasks/irc.f90` 是**未跟踪新文件** ⇒ 跨版本 diff 不可能；`types/{settings,results}.f90` 的存量 diff 是 **+258/-0** 与 **+222/-0**（纯追加）⇒ 修复轮的编辑与 M6 第一/二阶段折在同一份未提交增量里，无法用 diff 分离。故本轮判断基于「当前文件内容 + 报告 46 的前/后实测输出 + 我自己的语义走读」。
- 结论口径：仅报告有源码/契约证据、且属于本轮复核目标的现存问题。

## 1. 复核 45 逐条判定（M-1..M-5、LOW、INFO）

| 编号 | 内容 | 判定 | 证据（file:line） |
|---|---|---|---|
| M-1 | `--lirc-level` 死旋钮 | **已修复** | 解析 `main.F90:3307-3321`；写 `lircset%set_conv_level` → `settings.f90:1016-1050`（写 g_max/g_rms/d_max/d_rms）；读取 `tasks/irc.f90:567-572`；唯一消费者 `optimize/driver.f90:500-502`。默认档下 6 个拷贝与 `opt` 默认值相同 ⇒ 行为逐位中性（与 §11.1 一致） |
| M-2 | `--lirc-rmsd-end` 死旋钮 | **已修复** | 解析 `main.F90:3528-3544`；`tasks/irc.f90:311-316` 调用 `endpoint_reached(term, endpoint_relax, relaxed, rmsd, rmsd_end)`；判据实现 `tasks/irc.f90:620-623`（`reached = reached .and. relaxed .and. rmsd <= rmsd_end`，且 `relax_requested=.false.` 时跳过） |
| M-3 | HPC Hessian 记账 `!>` 与代码相反 | **已修复** | `hpc.f90:70-77`（「HPC does **not** update the Hessian with the predicted secant」）；`corrector.f90:843-847`（「EulerPC updates it …, HPC does not」） |
| M-4 | `xtb/landscape-irc-pc` 无 OMP 属性 | **CMake 已修复；meson 未同步** | `CMakeLists.txt:2688-2693`（含 irc-pc、irc-minimum、irc-knobs）；`test/unit/meson.build:443` 的 `irc minimum` 仍用 `xtbenv`（无 OMP），且 meson 无 swap 条目 → LOW-1 |
| M-5 | GS 球弛豫质量无断言 | **已修复（断言+可见化+待办）** | 单元 `test_landscape_irc.f90:1590-1691`（独立极角扫描+黄金分割参考、gap<2e-3、奇偶两点循环差>1e-4、`micro_converged=.false.`、`micro_step_thresh` 生效、球面 1e-12）；`n_pinned` `gs.f90:236` → `irc.log`；PLAN §6.5 待办行 `PLAN:960` |
| L-1 | `--help` 说 hpc/eulerpc 未实现 | **已修复** | `xhelp.f90:546-552`（四法均为可用描述，含默认） |
| L-2 | `--lirc-dwi-n` 实为容量 | **已修复（文档+校验）** | `settings.f90:834-841`、`xhelp.f90:597-601`、`main.F90:3456-3458`；校验 `tasks/irc.f90:494-498`；测试 `CMakeLists.txt:1948-1954`；代码侧另有多余保护 `corrector.f90:894` `max(2, dwi_n)` |
| L-3 | `s` 弦长 vs 弧长 | **已修复** | `tasks/irc.f90:914` + `arc_length_definition` `959-973`；PLAN:966；`hpc.f90:269`/`gs.f90:245`/`eulerpc.f90:265` 弦长、`lqa.f90:214-220` 积分长度 |
| L-4 | GS 零梯度守卫缺失 | **已修复**（但无专属测试，报告已承认 §12.5） | `gs.f90:129`（`gs_gradient_guard=1e-14_wp`）、`gs.f90:220-224` |
| L-5 | PLAN 未回填 `max_steps`/`max_pred_steps` | **已修复** | `PLAN:731`（`max_pred_steps` 标为显式偏离）、`PLAN:957`（`max_steps=256` 实测回填） |
| L-6 | 1.4e-2 | **部分修复** | 源内仅剩历史引用 `hpc.f90:60`；但替换范围 `hpc.f90:54`/`PLAN:962,1992,2011`/`43-*.md:399,427` 为 `1e-3..1e-2`，**不覆盖同句的 V2=4.56e-2** → LOW-2 |
| L-7 | 引用不存在的实验 | **已修复** | `gs.f90:88-95`（改为本轮 `noclamp` 实测：25.27 vs 4.05 bohr·amu^1/2） |
| L-8 | F-1 跨 ndim 复用 | **已修复（真修）** | `corrector.f90:937-951`（异维重绑）、`970-978`（reset 释放）、`981-995`（`path_release`）；测试 `test_landscape_irc.f90:1774-1824` 断言 `capacity==0`/未分配/异维重绑 |
| L-9 | CLI 端点无数值锚点 | **已修复**（但见 §4-LOW-3 的作用域澄清） | `CMakeLists.txt:1408-1435`（basin 窗口 + 弧长 + E/g + pinned）、`landscape_cli_check.py:722-741` |
| I-1 | 回退步 E/g 少记 1 | 未修（判为非缺陷） | `hpc.f90:254`、`eulerpc.f90:242`（`neval` 被 `gs_step` 覆写） |
| I-2 | oneway 仍打印 backward error/F | **已修复** | `tasks/irc.f90:906-911`、`results.f90:569-571,588` |
| I-3 | EulerPC 粗阶段重复 secant 更新 | 未修（死工作） | `eulerpc.f90:216-218` 与 `:255-256` |
| I-4 | `result%converged=(n_imag==1)` | 未修（下游无读取点，已核 `main.F90:1006-1019` 不读 `lres%converged`） | `landscape_driver.f90:175` |

## 2. 我独立列出的全部 `--lirc-*`（27 项，含 1 别名）× 链路核对

| # | 选项 | 解析 | 字段 | 实际消费点 | 生效证明 / 缺口 |
|---|---|---|---|---|---|
| 1 | `--lirc` | 3253 | runtyp | `main.F90:1006` | `xtb/landscape-irc-cli`（四文件/相位/etemp/pinned/窗口） |
| 2 | `--lirc-method` | 3260 | `method` | `tasks/irc.f90:379` | `-pc`(hpc/eulerpc)、`-cli/-swap/-termination`(gs)、`-knobs`(默认 hpc) |
| 3 | `--lirc-step` | 3276 | `step_length` | 四 walk | `-cli` 打印 `2.000000E-01` + 弧长黄金值 |
| 4 | `--lirc-max-steps` | 3292 | `max_steps` | `gs.f90:212`、`lqa:151`、`hpc:205`、`eulerpc:177`、`irc.f90:567` | `-pc`：`--lirc-max-steps 3` ⇒ `max_steps` + `reached F` |
| 5 | `--lirc-level` | 3307 | g_max/g_rms/d_max/d_rms | `tasks/irc.f90:568-571` | `-knobs`：1 步/7 步 + E_min 单调（注入 (1) 红） |
| 6 | `--lirc-swap` | 3323 | `swap` | `irc.f90:223,229` | `-swap`：两端点能量逐位互换 |
| 7 | `--lirc-oneway` | 3328 | `both_directions` | `irc.f90:242` | `-cli`：只写 forward |
| 8 | `--lirc-target-mode` | 3333 | `target_mode` | `irc.f90:205`→`corrector.f90:317-375` | 单元 `direction-rejects-minimum`（`target=3`⇒告警+index=1, target=3） |
| 9 | `--lirc-micro-cycles` | 3348 | `max_micro_cycles` | `gs.f90:347` | 单元 `gs-sphere-relaxation-quality`（预算 5/20/21/200） |
| 10 | `--lirc-micro-thresh` | 3363 | `micro_step_thresh` | `gs.f90:367` | 同上（阈值=半径⇒一次收敛、`n_eval==1`；注入 (9) 红） |
| 11 | `--lirc-euler-n` | 3378 | `euler_n` | `lqa.f90:177`、`hpc.f90:226` | 仅单元实参覆盖；**CLI 无「改值→结果变」**（读取点明确） |
| 12 | `--lirc-loose-cycles` | 3393 | `loose_cycles` | `eulerpc.f90:215` | 单元 `eulerpc-loose-cycles` + `-pc` 的 0 档 |
| 13 | `--lirc-mbs-tol` | 3409 | `mbs_tol` | `corrector_step` 实参 | 单元 `hpc-corrector-fallback`（`tol=0,k=1`⇒回退） |
| 14 | `--lirc-mbs-max-k` | 3425 | `mbs_max_k` | `corrector_step` 实参 | 同上 |
| 15 | `--lirc-mbs-points` | 3440 | `mbs_points` | `corrector.f90:775` 区（`base_points`） | 仅间接（积分精度参数） |
| 16 | `--lirc-dwi-n` | 3455 | `dwi_n` | `corrector.f90:894`（容量） | 实测 4≡20 逐位 + `1` 被拒（`-dwi-n`） |
| 17 | `--lirc-e-rise` / `--lirc-erise-steps` | 3472 | `e_rise_steps` | `gs:263`、`hpc:295`、`eulerpc:279`、`lqa:220` | 单元 `termination-energy-rise`/`termination-all-methods`；CLI `-termination`（弱：`-pc` 只查 exit 0） |
| 18 | `--lirc-grad-tol` | 3487 | `grad_tol` | 四 walk 信号(b) | 单元 + CLI `-termination` + 报告 46 §10.5 正对照 |
| 19 | `--lirc-recalc` | 3502 | `hessian_recalc` | `gs:231`、`lqa:163`、`hpc:~213`、`eulerpc:189` | 报告 44 §5 实测；无单元断言 |
| 20 | `--lirc-no-endpoint-relax` | 3517 | `endpoint_relax=f` | `irc.f90:262,271` | `-knobs`：无 relaxed 行 + skipped 行（注入 (10) 红） |
| 21 | `--lirc-endpoint-relax` | 3522 | `endpoint_relax=t` | 同上 | `-pc` 显式传该 flag（弱） |
| 22 | `--lirc-rmsd-end` | 3528 | `rmsd_end` | `irc.f90:312,315` | `-knobs` F/T + 单元 `endpoint-rmsd-criterion`（注入 (2) 红） |
| 23 | `--lirc-hessian` | 3545 | `hessian_source` | `irc.f90:169` | M3 测试覆盖 provider；IRC 侧仅透传 |
| 24 | `--lirc-hessian-file` | 3559 | `hessian_file` | `irc.f90:170` | 同上 |
| 25 | `--lirc-step-hess` | 3569 | `engine%hess_step` | `engine/engine.f90:651` | M3 覆盖；IRC 透传 |
| 26 | `--lirc-sccacc` | 3584 | `engine%hess_acc` | `engine/engine.f90:254` + provider | M3 覆盖；IRC 透传 |
| 27 | `--lirc-restart` | 3599 | `engine%restart_mode` | `engine/engine.f90:559,604` | M1/M4 覆盖；IRC 透传 |

**核对结果**：报告 46 §2.4 的 26 行表覆盖了全部 27 项（`--lirc-erise-steps` 与 `--lirc-hessian-file` 各并入相邻行，两行都点名了两个选项）⇒ **表完整，无遗漏**。8 个 ⚠️（#11/#15/#19/#23/#24/#25/#26/#27）我逐个验证过读取点均真实存在，**不是死旋钮**。

## 3. 专项攻击面结论

1. **M-1 链路**：完整、无短路（§2 第 5 行；`set_conv_level` 只写 4 个 g/d 判据，`e_tol` 与档位无关且被 `irc.f90:568` 拷贝）。新测试**不是恒真断言**：`landscape_cli_irc_knobs.cmake:1620-1650` 比较两次运行的 `relaxation steps` 与 `E_min`，去掉 4 个拷贝后两次运行同值 ⇒ `N_superloose GREATER_EQUAL N_vtight` 必触发 FATAL_ERROR（注入 (1) 已红）。表格完整性见 §2。
2. **`rmsd_end` 语义**：文档已如实改写（`settings.f90:899-908`、`xhelp.f90:624-628`、`PLAN:963`），明确「需弛豫端点；无弛豫时判据不可用且日志写明已跳过」；不再有虚假承诺。**残余语义**：默认阈值 0.18897 bohr 仍宽于 45 举的反例（eulerpc 0.40，rmsd 0.0733 bohr，端点高于真极小 5.8e-3 Eh）⇒ 该情形仍打印 `T`；但文档现在只承诺「RMSD 判据」，不再暗示「到达真极小」，故不构成新的虚假承诺（INFO-1）。
3. **M-2 全局清除**：`src/` 与 PLAN 已无未更正的 1.4e-2；残留只在带更正标记的历史记录（`43-*.md:159/399/427`、`44`/`45`/`46` 的讨论段落）。**表述不忠实**：`1e-3..1e-2` 不覆盖 V2=4.56e-2（LOW-2）。
4. **M-4**：Lagrange **未实现**（Q2 决定），降级说明到位：`gs.f90:96-108`（四项实测代价 + open item）、`PLAN:960`（待办 + 验收方式）、`settings.f90:822-831`（微循环判据不可达）、默认方法已改 `hpc`（`settings.f90:807`）。断言确实覆盖「未达判据」：单元断言 `micro_converged=.false.`（预算 5/20/21/200）+ CLI 断言 GS 上 pinned>0。
5. **M-5 / F-1**：**真修**（`path_release` + 异维重绑），不只是说明；论证逐行可核（§1 L-8）。
6. **默认值决策**：`hessian_recalc` **未改**（-1），依据来自实测 `44 §5.2`（长积分 6.0e-4 Eh / |g|=4.1e-2，recalc=10 恢复）；写入 `settings.f90:876-892` + PLAN:733/964。唯一改动的默认是 `method: gs→hpc`，依据实测（MB 0.0022 vs 0.040 bohr、1.98 vs 16.9/20.3 E/g），对已验收数字**无影响**：全部 IRC CLI 脚本显式传 `--lirc-method`（`-cli/-swap/-termination`=gs，`-pc`=hpc/eulerpc，`-knobs` 显式 gs 作对照），单元测试用 `default_settings(..., method)` 传参。
7. **GS 降级 / 弧长定义**：`PLAN:957`（GS 行含 16.9/20.3、8.5×、0.040 bohr、非单调）、`PLAN:960`、`PLAN:966`（弧长定义不可跨方法）、`gs.f90:60-108`、`settings.f90:776-783`、`xhelp.f90:546-552`、`irc.log` 每次打印 `arc length s is …`。44 §3.1/§4.1 的表都是**同方法**的端点位/E-g/点数，43 §9.3 无弧长列 ⇒ **未发现仍在暗示可跨方法比较的地方**。
8. **CLI 黄金值**：容差合理（±1e-4 Eh = 4 法同盆地离散度 5.0e-5 的 2 倍、比必须排除的 eulerpc 8.0e-4 窄 8 倍，脚本注释写明依据），且真正钉死路径的是 6 位小数弧长 `4.051234`/`3.695670` 与 E/g `16.9/20.2`。**但它不能捕获「GS 拆分冻结几何」那类回归**（LOW-3）：注入 (i) 只写错 `path%xyz`，而弧长取 `ds=|q_new-q_cur|`（`gs.f90:244-245`）、E/g 取 `n_eval`、端点位取 `path%e`、pinned 取 `micro_converged`，四者全不变 ⇒ CLI 仍绿；唯一护栏是单元 `gs-path-geometry-consistency`（与 44 §2.3 的结论一致）。脚本注释若被读成「CLI 覆盖了那次回归」，是误导。
9. **回归**：默认路径逐位中性（§0、M-1 第 1 行）；`setparam.f90` `p_run_lirc=20` 与 19/21 无冲突；`set_module.f90` 仅新增 case；核心层 0 改动；M0..M5 无 IRC 依赖。风险仅剩 `hessian_recalc` 决策依赖（未改默认）。
10. **测试可证伪性**：逐个新/改测试的「写错该逻辑是否仍绿」判定见 §4 表；10 条注入对「回退到修复前实现」的 6 条（1,2,3,5,7,8）**等价性由构造保证**；4 条（4,6,9,10）是人工变异、不涉及等价性。**过程缺口**：报告 46 §9 的表丢了 44 §9 的「等价性」列（M4 铁律 1 的载体）⇒ INFO-2。
11. **文档 vs 代码剩余问题**：45 的 5 条已全部关闭（M-1、M-3、L-1、L-2、L-6 前者两条与 L-1/L-2 已改，L-6 见 LOW-2）。新增/残留 4 条：LOW-2、LOW-3、LOW-4（`settings.f90:793` 「the endpoint relaxation keeps the minimiser budget」与 `main.F90:3309`/`PLAN §12.14` 「budget 取 --lirc-max-steps」矛盾——代码是后者）、INFO-3（`--lirc-step` 的 `--help` 未带 0.40 失效实测；`--lirc-method` 建议 eulerpc「0.20 or less」而 PLAN:964 记载 0.20 即论文所述的失效档）。
12. **数值卫生 N1..N17**（本轮新代码）：N1 ✓（`implicit none(type,external)`+`wp`，四 irc 模块与 tasks 均齐）；N2 ✓（无裸字面量，参数均 `_wp`：`gs.f90:125,129`、`corrector.f90:127-142`、测试 `2.0e-3_wp` 等）；N6 ✓（仅 `mctc_syev`）；N12 ✓（`sphere_newton` 限幅、`irc_gradient_guard`）；N13 ✓（`env%error`+`fail`，无 `stop`）；N14 ✓（只有 parameter）；N15 ✓（新增 `path_release` 补齐释放）；N16 ✓；N17 **一处例外**：`results.f90:623` `if (e_min == 0.0_wp)` 用能量浮点等值当「是否做过弛豫」的哨兵（LOW-4b）。N3/N4/N5/N7..N11 属 M6 一/二阶段，本轮未触碰。

## 4. 本轮新发现问题

**LOW-1（P2）CMake/meson 测试注册不同步（AGENTS §7）。**
`test/unit/CMakeLists.txt:2688-2693` 把 `irc-pc`、`irc-minimum`、`irc-knobs` 加入 OMP=1 列表，但 meson 镜像未跟：`test/unit/meson.build:443-447` 的 `landscape irc minimum` 仍用 `xtbenv`（无 `OMP_NUM_THREADS=1`），而该负例确实会跑数值 Hessian（`tasks/irc.f90:185` 先算 Hessian，`442` 才报 "not a transition state"）⇒ meson 注释「the error branches … never reach a calculation」对该分支不成立。另外 meson **完全没有** `xtb/landscape-irc-swap` 的对应条目（`landscape_cli_check.py` 也无 `swap` 模式）。
**最小修复**：meson 侧把 `irc minimum` 改用 `landscape_env` 并补 swap 条目（或把 CMake 的 irc-minimum 退回原状以保持双侧一致）。

**LOW-2（P2）M-2 的替换范围不覆盖被引用的实测值。**
`src/landscape/irc/hpc.f90:54` 写「the endpoint lands **1e-3..1e-2 hartree** above the true HNC minimum」，而同一段 `hpc.f90:56-58` 给出 V1=**2.80e-3**、V2=**4.56e-2**；4.56e-2 ∉ [1e-3,1e-2]。同一范围也出现在 `PLAN:962`、`PLAN:1992`、`PLAN:2011`、`43-*.md:399,427`、`46 §3.1`。
**最小修复**：范围改 `1e-3..5e-2`（或写「V1 2.8e-3、V2 4.6e-2」而不给区间），上层 `!>`「50 to 800 times closer」（`hpc.f90:63-64`）的算术本身正确（2.80e-3/5.5e-5=51、4.56e-2/5.5e-5=829）。

**LOW-3（P2）CLI 黄金值的作用域被高估。**
`test/unit/CMakeLists.txt:1423-1425` 的注释说这是「the CLI anchor the earlier version of the check lacked … without it a regression of the reported numbers is invisible」。但 M6 第二阶段的真实回归（冻结记录几何）**不改变任何被断言的 CLI 量**：`gs.f90:244-247` 的 `ds/s_cur/path_add` 都基于 `q_new/q_cur`（`gs.f90:263` 正常前进），只有写进 `path%xyz` 的几何是错的 ⇒ 端点位、弧长、E/g、pinned 四者全不变（44 §2.3 的注入也只让单元用例变红）。
**最小修复**：注释里点明「本断言覆盖数值回归；冻结几何类回归由单元 `gs-path-geometry-consistency` 负责」，或补一条几何派生断言（端点 xyz 与 `--lirc-endpoint-relax` 的极小点对齐 RMSD 窗口）。

**LOW-4（P2）两处文档/代码口径不一致 + 一处浮点哨兵。**
(a) `settings.f90:792-793`「`max_steps` is the **path** budget only; the endpoint relaxation keeps the minimiser budget」与 `main.F90:3309-3310`／`PLAN §12.14` 第 6 条「relaxation step budget = `--lirc-max-steps`」相反；代码是后者（`tasks/irc.f90:567 opt%max_steps = settings%max_steps`），且驱动 §12.4 自认该耦合。
(b) `results.f90:623` 用 `e_min == 0.0_wp` 判断「未做弛豫」（N17 浮点判等），而任务侧本来就有布尔 `relaxed_fwd/bwd`（`tasks/irc.f90:257-259`）。
**最小修复**：(a) 改为「the endpoint relaxation reuses the same `max_steps` field」；(b) 把 `relaxed_*`（或 `n_relax_*`）写进 `landscape_irc_result` 并在 `write_attribution` 用它。

**INFO-1**：默认 `rmsd_end`=0.18897 bohr 宽于 45 的反例（0.0733）⇒ 该情形仍打印 `reached_min=T`。文档已只承诺「RMSD 判据」，非虚假承诺；若要收紧，须改默认值并重验收。
**INFO-2**：报告 46 §9 注入表缺「变异与旧逻辑语义等价」列（44 §9 有）。
**INFO-3**：`xhelp.f90:553-556`（`--lirc-step`）未带 0.40 失效实测；`xhelp.f90:548-551` 说 eulerpc「use a step of 0.20 or less」，而 `PLAN:964`／44 §4.4 记录 0.20 对 eulerpc 已 ⚠️。
**INFO-4**：`tasks/irc.f90:919-928` 在 `endpoint_relax=.false.` 时只打印 forward 的归属行，`irc.log` 缺 backward 的 `reached minimum`（result summary 会打，`results.f90:585`）——单向不对称。
**INFO-5**：`--lirc-target-mode` 经 CLI 实际不可用（`--lirc` 强制恰好 1 个虚频 ⇒ N>1 只告警）；报告 46 §2.4 已披露，但 `xhelp.f90:571-573` 未向用户说明。
**INFO-6**：`settings.f90:787-788` 把 `g_max, g_rms, d_max, d_rms, e_tol` 五个字段称作「the four convergence thresholds」（措辞滑落，`e_tol` 不随档位变）。

**对「新测试写错该逻辑是否仍绿」的判定**：`endpoint-rmsd-criterion`（否，注入 (2) 红）／`path-cross-dimension-reuse`（否，(3) 红）／`gs-sphere-relaxation-quality`（否，(8)(9) 红；注意 `micro_converged=.false.` 的硬断言使 Lagrange 修复后必然要显式更新——设计如此）／`-knobs` 的 level 与 rmsd-end 断言（否，(1)(2) 红）／default-hpc 与 pinned 断言（否，(5)(6) 红）／`gs-path-geometry-consistency`（否，(7) 红）。

## 5. 需运行验证清单（我无法运行）

1. **收掉 LOW-1 后**：`grep -n "landscape irc" test/unit/meson.build`；确认 swap/OMP 与 CMake 对齐（meson 本机不可执行）。
2. **收掉 LOW-2 后**：`grep -rn "1e-3\.\.1e-2" src/ docs/xtb-landscape-PLAN.md` 应无残留（或已含 4.56e-2 的口径）。
3. **LOW-3 的实验化（可选，10 分钟）**：在 `gs.f90:246` 注入 `x_new = path%xyz(:,1)`，重跑 `ctest -R 'landscape-irc$|landscape-irc-cli'`，预期 **单元红、CLI 绿**——这直接验证 LOW-3 的论断（也顺带重验 44 §2.3 的护栏活性）。
4. **基线复核**：`OMP_NUM_THREADS=1 cmake --build /tmp/xtb-land/build -j`（0 warning）；`ctest -N -R landscape | tail -1` = 79；`grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d` 空；`ctest -R landscape` 79/79；回归子集 12/12；`xtb-tester landscape-irc` 35/35。
5. **`--lirc-level bogus`**（当前无测试）：应 `Unknown landscape convergence level` + 非零退出（解析路径与 `--lopt-level` 共用）。
6. （可选）`--lirc-method eulerpc --lirc-step 0.20` 复跑一次，决定 `--help` 的「0.20 or less」是否要改成 0.10（44 §4.4 已测 ⚠️ 3.6e-4，无需新数据，只需决定文案）。

## 6. 结论

- **M6 现在可以提交**：45 的 5 条 MEDIUM 实质关闭，未发现 CRITICAL/HIGH/MEDIUM 级别问题，默认路径逐位中性，无已验收数字受影响。
- **进 M7 前必须解决**：无硬性项。建议随 M6 提交一并收掉 LOW-1（meson 同步）与 LOW-2（范围改 `1e-3..5e-2`）；LOW-3/LOW-4 可留作 M7 首个小修。
- 计数：**CRITICAL 0 / HIGH 0 / MEDIUM 0 / LOW 4 / INFO 6**。