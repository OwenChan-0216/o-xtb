## Review（摘要，M6 独立复核）

**结论：有条件接受（conditional accept）。0 CRITICAL / 0 HIGH / 5 MEDIUM / 9 LOW / 4 INFO。M6 的物理与算法**未发现会产生错误路径的缺陷**；但 2 个「文档承诺、代码无效」的 CLI 开关 + 3 处文档与代码矛盾必须先处理，再宣称 M6 完成并进 M7。**

- 第 0 项（GS 拆分行为保持）：**可信但非严格**。我独立核对了 `gs_step` 的微循环状态重置、方向 sign 载体、E/g 计数、recalc 传参（`gs.f90:120-190, 262-296`），与报告 44 §2.2 一致；端到端 10/10 逐位一致是强证据，但 `src/landscape/irc/` 未入 git ⇒ 严格 diff 不可能；且 CMake 的 `xtb/landscape-irc-cli` **不钉任何端点数值**（只查两端点互异），所以那次真实回归只能靠单元测试捕获，不能靠 CLI 黄金值。建议补一条端点能量窗口断言。
- 单位（攻击面 2）：质量加权全程 `bohr*amu^1/2`，`autoamu=kgtoamu*metokg` 使 `getAtomicMass*autoamu` 得 amu（`src/mctc/convert.f90:56`、`corrector.f90:217`）——**正确**。但 `s` 在 GS/HPC/EulerPC 是**弦长累加**、只有 LQA 是积分弧长（LOW-4）：GS 4.0512 vs LQA 4.2500 是定义差，不能跨方法比较。
- GS 数学、LQA 谱系、HPC 的 `a_ii(t)` 与 λ→0=−t 分支、EulerPC 预测方向 −g/|g|、mBS 简单 Euler、三终止信号互斥可达 —— 逐条核对**成立**。R-1（2 E/g）已被验证轮**独立实现**并定性证实、定量否定（2.8e-3/4.6e-2 而非 1.4e-2），但被否定的 1.4e-2 仍留在 `hpc.f90:54` 与 PLAN §12.15（LOW-6）。回退路径在真实 GFN2 上确实发生（`m6-irc-data/exp4-hessian/long10`、step0.20/0.40），非死分支。
- 发现「测试全绿但仍然错误」类问题 2 条：`--lirc-level` / `--lirc-rmsd-end` **完全无效**（文档说控制端点弛豫与归属判据，代码从不读）；GS 球内弛豫的**质量**（GS 定义属性）无任何断言，而 R-1 证明它从不满足自身收敛判据。
- 需运行验证 7 项见正文清单（含 4 条把「开关无效」证伪的反向实验 + 正对照）。

完整报告正文（请落盘到 `docs/_landscape-recon/45-m6-independent-review.md`）如下。

---

# 45 — M6 独立复核报告（fresh-context，read-only）

**复核对象**：报告 42/43/44、`m6-irc-data/`、`src/landscape/irc/{corrector,gs,lqa,hpc,eulerpc}.f90`、
`src/landscape/tasks/irc.f90`、`types/{settings,results}.f90` 的 M6 增量、`test/unit/test_landscape_irc.f90`、
`test/unit/CMakeLists.txt`、`main.F90`/`xhelp.f90` 接线、PLAN §5.3.7/§6.5/§12.14/§12.15。
**HEAD**：`2ed7750`（M6 全部未提交）。**未运行任何命令**（read-only 工具）。

## 0. 结论

| 项 | 判定 |
|---|---|
| 物理/算法正确性（四法路径、终止信号、端点归属、单位） | **未发现错误** |
| 「测试全绿但仍然错误」类缺陷 | 2 条（`--lirc-level`/`rmsd_end` 无效；GS 球弛豫质量无覆盖） |
| 文档承诺 vs 代码行为 | 5 条（其中 2 条是**用户可见的 `--help` 虚假陈述**） |
| M6 是否可宣称完成 | **可以，但先关 5 条 MEDIUM**（成本都很低） |
| 进 M7 前必须解决 | ①`--lirc-level`/`rmsd_end` 生效或改文档；②HPC Hessian 与 1.4e-2 两处 `!>` 更正；③`xtb/landscape-irc-pc` 补 OMP 属性；④GS 球弛豫质量补测试；⑤F-1 修或写清（irc/ 无历史） |
| 计数 | CRITICAL 0 / HIGH 0 / MEDIUM 5 / LOW 9 / INFO 4 |

## 1. 攻击面逐条判定

| # | 攻击面 | 判定 | 依据 |
|---|---|---|---|
| 1 | GS 拆分行为保持 | 可信（非严格） | `gs.f90:262-296` 无跨调用状态；10 个数字逐位同报告 42；新 `gs-path-geometry-consistency` 精确复现旧回归；但无历史可 diff、CLI 无黄金端点值 |
| 2 | 单位 | **正确** | `corrector.f90:217`+`src/mctc/convert.f90:56`；全部标注 bohr\*amu^1/2；`mass-weighting-roundtrip` 钉 amu |
| 3 | GS 数学 | 公式正确；R-1 根因解释**不完整** | pivot/R=s/2/`N=1/|g^q|` 正确；收敛判据比较的是**被信任域限幅后**的 d，与 `micro_step_thresh`(1e-3) 差 50×，故必然跑满；但均匀 shift `denom=max(eval,shift)` 本身也让迭代线性收敛——报告只归因 trust-region |
| 4 | LQA 谱系 | **符合契约** | `corrector.f90:80-100` 明写 Page–McIver vs QSD；`a_ii`、`g(t)` 与 Hratchian–Schlegel Eqs.7-9 一致 |
| 5 | HPC | 公式正确；R-1 已独立核实 | `corrector.f90:580-586`（`a=-t`）、`615-632`（`speed` 同 tol）；R-1 由 44 §6.1 自行实现 V1/V2；回退真实发生 |
| 6 | EulerPC | **符合契约** | `eulerpc.f90:206` `q_cur - step*g/gn`；收敛阶只钉渐近区间(0.10→0.20, ∈(0.5,2))，诚实打印三点拟合 3.22 |
| 7 | mBS | **符合契约** | 简单 Euler（`corrector.f90:733-755`）；`mbs_tol` 1e-5 vs 论文 1e-6 三处（settings/xhelp/模块头）显式记录；不收敛 → `converged=.false.` + 警告 + GS 回退 |
| 8 | 终止信号 | **符合契约，但 (b)/(c) 语义不同源** | 三信号 12/12 可独立触发；EulerPC forward 由 (c) 先触发 ⇒ 「(c) 触发」不代表「已到极小点」（见 M-2） |
| 9 | 端点归属 | 对齐语义正确；判据与文档不符 | `align_geometry(env, xyz_end, xyz_min)` = 质心 + mass-free 正旋转（`coords.f90:353-401`）；但归属判据只用终止信号（M-2） |
| 10 | 相位与确定性 | 缺口**已实质关闭** | `test_phase_sign_invariance` 用显式取反喂 `set_phase`，去掉规范化即红；跨库符号仍不可测（如实记录） |
| 11 | 自我循环 | 大体可独立复核；MB 参考自偏 | 参考 = 0.01 步 LQA 细路径（44 已自认）；LEPS 用闭式 `leps_r_h2`、MB 用解析极小点常量 |
| 12 | 回归 M0..M5 | **未发现影响** | `watchdog_diff --stat`：仅 `types/{settings,results}.f90`（纯追加）、`landscape_driver.f90`、`main.F90`/`set_module`/`setparam`/`xhelp`；核心层 0 改动；`p_run_lirc=20` 与 `p_run_*`/`p_ext_*` 无冲突 |
| 13 | N1..N18 | 基本合规 | `implicit none(type,external)`、`_wp`、BLAS 经 `mctc_syev`、无模块级可变量、`env%error`+`fail`（`main.F90:1021` 的 `env%checkpoint` 落实非零退出）；唯一例外见 L-4 |
| 14 | 文档承诺 vs 代码 | **5 条矛盾**（M-1、M-3、L-1、L-2、L-6） | 见下 |

## 2. MEDIUM（建议 M6 提交前关闭）

**M-1 `--lirc-level` 完全无效；端点弛豫静默使用 `normal`。**
* `tasks/irc.f90:508-518`（`relax_endpoint`）只复制 `opt%write_files/printlevel/engine/engine%etemp`，
  **没有**复制 `e_tol/g_max/g_rms/d_max/d_rms/max_steps`（兄弟代码 `tasks/ts.f90:1069-1075`、
  `scan/relax_scan.f90:577-585` 都复制）。全仓库 `settings%g_max|g_rms|d_max` 的唯一消费点是
  `optimize/driver.f90:501-502`（读的是 `opt`），IRC 侧无任何读取点。
* 现象：`--lirc-level vtight` 会设置 `lircset%g_*` 然后**无人读取**；用户以为端点弛豫被收紧，
  实际仍是默认 `normal`，且 `opt%max_steps` 是 256（不看 `--lirc-max-steps`）。
* 文档同时撒谎：`main.F90:3308`「Convergence thresholds of the inner endpoint relaxation」、
  `xhelp.f90:558-560` 同义。
* 最小修复：在 `relax_endpoint` 里补 `opt%max_steps = settings%max_steps; opt%e_tol = settings%e_tol;
  opt%g_max = settings%g_max; …`（4 行，与 ts/scan 一致）。

**M-2 `rmsd_end` / `--lirc-rmsd-end` 无效，`reached_min` 因此不断言「路径到过极小点」。**
* `settings.f90:854-856` 注释「RMSD below which an endpoint counts as reached a minimum」，
  `xhelp.f90:617-618` 同义；全仓库 `rmsd_end` 仅出现在 `main.F90:3532`（解析）与 PLAN 表——**从不被读**。
* `tasks/irc.f90:558-566`（`endpoint_reached`）只看终止信号 + 弛豫是否收敛。弛豫从任何起点都会
  收敛到**最近**极小点，故 `reached_min` 实为「(b)/(c) 触发」的同义语。
* 实测反例：`m6-irc-data/exp6-crosscheck/gfn2/step0.40/eulerpc/out:252` =
  `forward reached minimum: T (rmsd 0.0733 bohr)`，而该端点比真实极小高 **5.8e-3 Eh**（44 §6.2）。
* 最小修复：把 `rmsd_end` 接进 `endpoint_reached`（`reached = reached .and. rmsd <= settings%rmsd_end`），
  或在 settings/xhelp 明写「仅用于报告，不构成判据」。

**M-3 HPC 的 Hessian 记账注释与代码相反（44 的 F-3 只改了报告，未改源码 `!>`）。**
* `hpc.f90:69`「The predicted secant updates the mass weighted Hessian」与
  `corrector.f90:833`「the current mass weighted Hessian (updated with the predicted secant by the caller)」
  —— 对 HPC 都是**假的**：`hpc.f90:262-264` 只用**接受点**的 secant 更新，预测 secant 只在
  `eulerpc.f90:216-218` 使用。读者会据此误判 DWI 所用的 Hessian。
* 最小修复：改这两处措辞（或让 HPC 也做预测更新，但那会改变已验收数值）。

**M-4 `xtb/landscape-irc-pc` 未固定 `OMP_NUM_THREADS=1`（CMake/meson 两侧不一致）。**
* `test/unit/CMakeLists.txt:2475-2482` 的单线程属性列表含 `irc-cli/-swap/-termination`，
  **不含** `irc-pc`；而 meson 镜像 `test/unit/meson.build:442-445` 用 `env: landscape_env`（含 OMP=1）。
* 违反 AGENTS.md「所有 xtb/ctest 调用带 OMP_NUM_THREADS=1」与「CMake/meson 手工同步」，
  且这正是 M2 的 340× 反向加速/位数不确定场景（该测试跑 2 次完整 GFN2 IRC + `--lts`）。
* 最小修复：把 `"xtb/landscape-irc-pc"` 加入 `:2475` 块的列表。

**M-5 GS 球内弛豫的**质量**无任何断言——正是 R-1 表明从不满足自身判据的那一环。**
* 唯一约束测试 `mb-sphere-chord`（`test_landscape_irc.f90:584-628`）只断言「弦 ≤ 步长」与「≥ s/2」，
  这是**任何**球面点都满足的必要条件；`gs-step` 若返回偏离球面约束极小点较远的点，仍然全绿
  （只能被端点盆地/细路径间接约束）。
* R-1 已证微循环几乎每步跑满 20 次（`gs.f90:296-325`：判据比较的是信任域限幅后的 d），
  所以「返回的是球面约束极小点」这一 GS 定义属性**没有被测**。
* 最小修复（新单元用例）：在解析面上对某一 pivot 用独立方法在球面上求 E 最小（密集采样 + 局部
  Newton，或直接用 `sphere_newton` 的独立实现），要求 `landscape_irc_gs_step` 返回点的 E 与之
  相差 < 1e-8 Eh（`gs_step` 已是 public）。

## 3. LOW

**L-1 `--lirc-method` 的 `--help` 说 hpc/eulerpc「not implemented yet」（用户可见的假话）。**
`xhelp.f90:547-549`、`main.F90:3261-3263`。M6 第二阶段已实现。最小修复：改文案。

**L-2 `--lirc-dwi-n` 无效（DWI 恒为两点）。** `corrector.f90:890-892` 只 `add` 了 `q_a/q_b` 两点，
`dwi_n` 仅作容量 ⇒ `--lirc-dwi-n 20` 与 `4` 逐位同结果。但 `settings.f90:811-813` 写「Number of sample
points of the DWI surface fit」、`corrector.f90:149` 写「up to `dwi_n` sample points」、`xhelp.f90:594-595`
同义。修复：改文档，或实现多点 DWI。

**L-3 `s` 的定义在四法间不一致（弦长 vs 弧长）。** `gs.f90:187`、`hpc.f90:269`、`eulerpc.f90:265`
用 `vec_norm(q_new-q_cur)`；只有 `lqa.f90:214-220` 用积分 `s_reached`。实测同一条路径 GS 4.0512 vs
LQA 4.2500（= 0.05+42×0.1 精确），差的 4.7% 主要是定义差。44 §3/§4 的跨方法弧长表因此不可直接比较。
修复：注明、或四法统一（HPC/GS 记半弧长修正）。

**L-4 `s_fwd/s_bwd` 与 GS 的零梯度守卫缺失。** `gs.f90:275-276` 用 `gnorm_weighted` 的 `tiny` 兜底，
在恰好驻点（需 `--lirc-grad-tol 0`）会记录重复点直到 (c) 触发；LQA/HPC/EulerPC 都有 `1e-14` 守卫并转成
信号 (b)。修复：加同一 `irc_gradient_guard`。

**L-5 `max_pred_steps`（PLAN §5.3.7，MAPLE 500）未实现、未记录为偏离**；PLAN §5.3.7 仍写
`max_steps=50` 而代码 256（44 §11 的回填建议未落到 PLAN）。

**L-6 被否定的 1.4e-2 Eh 仍在源码注释与 PLAN 里。** `hpc.f90:54`、PLAN §12.15 第 3 条；
44 §6.1 实测 2.80e-3（V1）/4.56e-2（V2）。修复：改成「量级 1e-3…1e-2，依 Hessian 记账变体」。

**L-7 `gs_step`/`sphere_newton` 的信任域注释引用了不存在的实验。** `gs.f90:317-320`「measured on the
GFN2 HCN/HNC path, report 42」——报告 42/44 只有 `--lirc-micro-cycles/--lirc-micro-thresh` 扫描
（44 §7.1），**没有**去掉限幅的实验。修复：删引用或补实验。

**L-8 F-1（path 容器跨 `ndim`）在未提交代码里仍是潜伏 bug。** `corrector.f90:807-816`（reset 不重置
`capacity`/不释放）+ `818-826`（`ndim==0` 提前 return）。测试已用两个 path 对象绕开
（`test_landscape_irc.f90:1474-1482` 有明确注释）。生产不触发，但 `src/landscape/irc/` 首次入库，
若不在入库前修/写清，缺陷会随第一个 revision 固化。

**L-9 端点归属的 CLI 端缺少数值锚点。** `landscape_cli_irc.cmake:1400-1409` 只断言两方向端点能量
**互异**，不钉数值/弧长/点数，故第二阶段那次真实回归对 CLI 层不可见（建议加「端点能量 ∈ HNC/HCN
±1e-4 Eh」窗口；pc 脚本已有盆地窗口可照抄）。

## 4. INFO

- **I-1** 回退时 `neval` 被 `gs_step` 覆写（`hpc.f90:239-249`、`eulerpc.f90:237-247`），
  丢弃预测点的 1 次求值 ⇒ 有回退的步骤 `E/g` 少记 1（0.40 EulerPC：报告 3.43 应约 3.6）。
- **I-2** `--lirc-oneway` 时 `irc.log` 仍打印 `termination backward: error` / `backward reached minimum: F`
  （`tasks/irc.f90:840-847`，`term_bwd` 保持 `p_landscape_irc_term_error`）。
- **I-3** EulerPC 粗阶段把预测 secant 更新做两次（`eulerpc.f90:217` 与 `:260`）。Bofill/SR1 均在
  第二次成为精确 no-op（我按 `hessian_update.f90:158-223` 的 φ 与两个 rank-1 项推过），属死工作。
- **I-4** `run_irc_task:177` `result%converged = (irc%n_imag == 1)`：即使两方向都被 `max_steps` 截断也报
  `converged=T`（当前下游未使用，`lres%converged` 全仓库无读取点）。
- 另：`speed()` 对负本征值大 t 有 `exp` 溢出/NaN 理论风险，但我**未能构造可达路径**
  （需同时 `|g|` 极小 + 负曲率；`grad_tol>0` 时先由 (b) 终止），故只记录不断言。

## 5. 需运行验证清单（我无法运行，父会话执行）

1. **基线**：`cmake -S . -B /tmp/xtb-land/build …` → `cmake --build -j`（0 warning）；
   `OMP_NUM_THREADS=1 ctest -R landscape`（77/77）；回归子集 12/12；
   `ctest -N -R landscape | tail -1` = 77；`grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d` 空。
2. **证伪 M-1**（关键）：`--lirc --lirc-level vtight` vs `normal`，对比四文件与 `mean E/g`、点数——
   **预期逐位相同**（证明开关无效）。若不同 ⇒ 我的 M-1 判定错误，请退回。
3. **证伪 M-2**：`--lirc-rmsd-end 1e-3` vs 默认，对比 `irc.log` —— **预期逐位相同**。
4. **证伪 L-2**：`--lirc-dwi-n 4` vs `20` —— **预期逐位相同**。
5. **正对照**（证明实验能看见开关效果）：`--lirc-grad-tol 0.01` vs `1e-3`，点数/终止信号**必须改变**。
6. **M-4**：`ctest -R 'xtb/landscape-irc-pc' -V`（或 `--show-only=json-v1`）确认其 env 无
   `OMP_NUM_THREADS=1`；再分别以 OMP=1 与 8 跑一次，记录墙钟差。
7. **护栏活性**：重放 44 §2.3 的 `x_new = path%xyz(:,1)` 注入 ⇒ 期望 `gs-path-geometry-consistency`
   + `mb-gs-minima` 变红；再重放 42 §8.1 的 `project_sphere` 删除 ⇒ `mb-sphere-chord` 变红
   （这两条是行为保持与球约束的唯一护栏）。
8. **L-7 的替代**：在 `sphere_newton` 去掉 `if (nd > radius)` 限幅跑一次 GFN2 GS，看是否真出现
   43 § 注释所称的「两球面点间振荡」；若无 ⇒ 删除该句引用。
9. （可选）实现 M-5 的球面极小点对照测试，确认 `gs_step` 返回点距今次球面极小点 < 1e-8 Eh。