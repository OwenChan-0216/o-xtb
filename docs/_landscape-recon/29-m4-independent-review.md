## Review
- **结论：有条件接受（conditional accept）。M4 的交付物与 PLAN §9.5 验收数字成立，但不可无条件宣称完成。**
- 已验证为正确的（有证据）：P-RFO 双 shift 数学（λ_p 式 4.18a、λ_n 严格单调残差 + 双侧扩张对分、dq 两支与 4.19/4.20 逐项一致、λ_n<0 有断言、失败走 `env%error` 不产生 NaN）；B-PRFO 确实是**不同**算法（alpha 子空间 + `solve_downhill_radius` micro 迭代；`bprfo-radius-split` 以 1e-9 断言两支半径各自生效，纯 P-RFO 换名会红）；刚体投影（在**步向量**上做，6 列/线性 5 列有测试，投影后正交 <1e-12）；模态跟随（argmax|V^Tv| + 符号重对齐，相位只在选择时施加，注入 (ii)/(iv) 会红）；dimer 曲率符号与 2δ 因子（Eq.2 ↔ N^T H N，解析面 0.07%）、Eq.21 两支、Eq.13 取**首个正根**（有 magic-number pin，主值分会红）；`random_seed(put=)` 在 `random_number` 之前，同 seed 两次抽取逐位相同 → **缺 seed 会被测试抓到**（不会因同进程连续抽取而掩盖）；`res` 回写、`p_run_lts=19` 无冲突、无裸 real/直调 LAPACK/module 变量、未改动 M0..M3 默认值（settings.f90 为纯新增）。
- **CRITICAL 0 / HIGH 4 / MEDIUM 8 / LOW 3 / INFO 3**。
- HIGH：**H1** M4 硬约束 2（|λ|≤3 cm⁻¹ 收紧 FD）无实现且 `--lts` **无法**收紧 FD 参数（ts.f90:149-151/246，无 `--lts-step`/`--lts-sccacc`，hess_step=5e-3、hess_acc=0.3 固定在 settings.f90；imag_cutoff=−20 cm⁻¹ 比 3 cm⁻¹ 带更宽，带内模被报成 0 虚频）；**H2** V3 收敛到极小点仍 `converged` + **exit 0**（ts.f90:281-284；fm_from_hnc.exit / fm_stretch2neg.exit 均为 0）；**H3** V1 线性分子虚频被吞（modes.f90:151/179-185）→ 线性 TS 的「虚频确认」交付物失效；**H4** V2 刚体模噪声（~1e-11）使 `lifted` **恒真**、警告每步触发、默认 hlow=1e-2 实际每一步生效（prfo.f90:234-251；ts_hcn_hlow1e-12.txt 仍 `lifted=T`）。
- **进 M5 前必须解决**：H1（实现或把补救路径补上 `--lts-step/--lts-sccacc` + 带内检测/明确警告，并把偏离写入 PLAN）、H2（`n_imag/=1` 时置失败码，至少 `result%converged=.false.`）、H3（线性分支投影或按阈值选零模 + 线性鞍点测试）、H4（在判 `nneg` 前对 Hessian 谱做刚体投影，或噪声感知阈值 + warning 去重）。
- MEDIUM：etemp 死字段（results.f90:150-152 从无赋值，M3 MEDIUM-B 复现）；prfo `reset_result` 不清 `result%conv`（prfo.f90:689-706 vs optimize/driver.f90:535、dimer.f90:1032）；`--lts` 输出文件不过 `get_namespace`（ts.f90:308,320）；驱动级 `remove_rigid` 无测试（MB 面 ndim=2 → n_rigid=0，注入投影 no-op 只有单元测试红）；最终模态向量不重定相也不在收敛点报告（prfo 只印初始模，dimer:866 印最终相固定轴）→ 影响 M6 IRC 方向；`step0` 被 `step_max` 支配且无 CLI（第一平移实测 0.1032 而非 min(step0,step_max)=0.28346）；dimer 表 `trust/bohr` 列填 `step_max`；κ<0 不限幅 + 零步宏迭代（实测 4/39 步 dmax=0）。
- 我方无法跑测试；「需运行验证」清单见报告 §6（含一条关键回归：删掉**驱动里**的 `landscape_project_rigid` 调用后我预测 44/44 仍全绿）。

---

# 29 — M4 独立复核报告（P-RFO / B-PRFO / Dimer）

> 复核者：fresh-context read-only reviewer。复核对象：HEAD `18c08d9` + 未提交的 M4 工作区改动
> （26/27/28 号报告、`m4-saddle-data/`、`src/landscape/saddle/*`、`tasks/ts.f90`、`types/settings.f90` 增量、
> `test/unit/test_landscape_saddle.f90`）。工具只有 read/grep/find/ls/watchdog_diff —— **未运行任何命令**。
> 纪律：所有严重级判定附 `file:line` + 源码/数据证据；无证据的静态猜测不作为 finding。

## 0. 结论

| 项 | 判定 |
|---|---|
| 交付物（`--lts [prfo|bprfo|dimer]`、`xtbts.xyz`/`xtbts.log`、虚频确认） | **齐备**（数据目录内含四次 etemp × prfo/bprfo、dimer random/force 的 stdout/exit/输出文件） |
| PLAN §9.5 验收（MB 面 prfo vs bprfo RMSD<1e-3；dimer 无 Hessian） | **成立**：`m4-saddle-data/exp5-l1-mb/xtb-tester-saddle.txt:78` = 6.3022E-06（裕度 159×），`:89` dimer 14 步 dist 8.1093E-05、rmsd(prfo) 7.8177E-05，`:92` Hessian requests 0 |
| 硬约束 1（etemp 冻结 + 记录） | **stdout 层面成立**（ts.f90:140 与 engine_report 回读双打印，CLI 测试断言两条）；**result 对象层面不成立**（`result%etemp` 死字段，见 M1） |
| 硬约束 2（近零曲率收紧 FD） | **不成立**（H1）：没有实现，也没有客户端口，且虚频阈值比该带宽 6× |
| 硬约束 3（不用 `--hess` 逐位一致作判据） | **遵守**（未使用） |
| **M4 是否可宣称完成** | **否（不可无条件）**：交付物与验收数字成立，但 H1/H2/H3 直接落在「交付物 + 硬约束」上，H4 使文档化的防护不可诊断 |
| 进 M5 前 | 至少 H1、H2、H3 修复或降级为写入 PLAN 的显式验收附条件 + 一条可见警告；H4 需处置 |

## 1. 攻击面逐条判定（问题 1–11）

**1 数学正确性 —— 通过。**
- `lam_p = 0.5 b_k + 0.5 sqrt(b_k^2+4F_k^2)`（prfo.f90:255）与式 4.18a 一致；`denom=b_k−λ_p<0`，`coeff(k)=−f_k/denom=f_k/(λ_p−b_k)`，符号即沿 V_k 上坡（f_k=g·V_k）。f_k=0 时 λ_p=b_k（b_k>0）→ denom 触发 `evals_eps` 保护。
- `landscape_rfo_downhill_shift`（eigenfollow.f90:311-370）的残差严格递减、`residual(λ→−∞)=+∞`、`λ→b_min⁻` 时 −∞，双侧扩张 + 对分不变量正确；`bmin` 是**排除 k 后**的最小本征值，故 `λ<hi<bmin≤b_i (i≠k)` 时永不出现 `λ=b_i` 除零（唯一除零面被排除）。`λ_n<0` 由 `residual(0)<0` + 单调性保证，并在 prfo.f90:266-273 断言（否则 `env%error`）。空下坡梯度时 `solved=.false.`、`λ_n=0`，走 Newton 形式，不报错。
- 迭代失败路径有界：`max_bracket=200` 后 `fail=.true.` + warning → prfo 转 `env%error`；驱动把该步当 rejected（trust×0.75，连续 8 次 → `"no step could be constructed"` → 非零退出），无 NaN。
- `dq` 合成（prfo.f90:281-287）与 4.19/4.20 逐项对应；`test_prfo_lambda_n` 的残差断言与 `step(3)/step(2)=(1−λ_n)/(4−λ_n)` 比例断言都是对公式的**逐项**检查（不是"能收敛就算过"），注入 (i) 会红。
- 小瑕疵（非 finding）：`b = evals` 是副本，`evals` 未被抬升，故 `landscape_prfo_step_spectrum` 内抬升后的 `b` 只用于 shift/coeff（正确），但 B-PRFO 直接原地改 `evals`，两处命名风格不同（无功能差异）。

**2 B-PRFO 与 P-RFO 是否真的不同 —— 通过（不是换名）。**
bprfo.f90:163-206 是真正的 alpha 子空间划分（`r_p=α·trust`、`r_n=sqrt(1−α²)·trust`）+ 「只在上坡分量超限时解析限幅」+「下坡分量超限时用 `sum(F_i/(b_i−λ))²=r_n²` 的 micro 对分」。`test_bprfo_radius_split`（test_landscape_saddle.f90:610-640）同时断言 `|dq_k|=r_p` 与 `|dq_n|=r_n` 到 1e-9 —— 若 B-PRFO 退化为「P-RFO + 事后 clip」，下坡分量会等于 P-RFO 值，该断言必红。报告 26 §2.2 记录的「始终 `|dq_k|=r_p`」变体不收敛也说明作者实测过两种形式。

**3 刚体投影 —— 通过，但驱动级无测试（M4）。**
- M1 债务处理正确且**在步向量上**：`landscape_rigid_modes` 建 3 平动 + 3 转动（几何中心，质量无关）并 Gram-Schmidt；`landscape_project_rigid` 去分量（eigenfollow.f90:433-500）。线性分子 5 列（`rigid-linear-basis` 断言），单体返回空（nat≤1 早退）——与 M3 的 3N−5 处理**不矛盾**（M4 用的是自身基，未复用 modes.f90 的 linear 分支）。
- 报告 26 §6 记录的形状截断 bug（`vec=raw(:,k)` 9→3 静默截断）已被 `rigid-basis-orthonormal`（6 列）与 `rigid-linear-basis`（5 列）固定；`internal_distance_change` 比较是有意义的（任何 6 正交列都能过 Gram，但不一定能过内坐标比较）。
- **缺口（M4）**：驱动里 `if (n_rigid > 0) call landscape_project_rigid(step, rigid, n_rigid)`（prfo.f90:497-500）在 MB 测试里 **n_rigid=0**（ndim=2 不是 3 的倍数 → `landscape_rigid_modes` 早退），因此**所有** MB 测试都没走这条路径；`remove_rigid=.false.`（`--lts-no-rigid`）在整个 M4 测试集中从未被设置。报告 26 §5 注入 (iii) 只杀死了 `rigid-projection` 与 `prfo-rigid-projection` 两个**单元**测试（它们直接调投影例程，不经驱动），所以「M1 债务已在驱动里关闭」这一断言在测试层面**未被证伪**。

**4 模态跟随 —— 基本通过；两处需注意（M5、I1）。**
- `landscape_follow_transition_mode` 每步（`recalc=1` 默认 → 每步）做 `argmax` + 符号重对齐（eigenfollow.f90:246-260）；相位只在选择时施加（:255-258 有注释解释为何不再施加），与 `mode-follow-sign` 的「连续性」断言一致（该测试前先把 vector 翻成 −e1，专门排除「相位顺带修好」的假绿，正是本项目历史模式的对策）。
- 低 overlap 触发后是**重新选模**（`target` 语义：默认重选最负模式），置 `followed=.false.` + warning，并写进步表（`followed=F`）；**模态跳变本身不被判为失败**，搜索继续（与 pysisyphus 一致）。验证报告 28 §5 实测触发（overlap .9831 < .99）并仍收敛到同一鞍点。
- **未覆盖点**：没有任何测试断言「重新选模后驱动仍继续、且 `followed=F` 出现在输出里」；`mode%followed` 只在 `printlevel>=1` 的 `record_step` 里被打印。属可接受的覆盖缺口（INFO 级），但如果 M5 依赖模态连续性，建议补一条驱动级断言。

**5 Dimer 正确性 —— 通过，附两条 LOW/MEDIUM。**
- 曲率：`C=(f_minus−f_plus)·N/(2δ)`（dimer.f90:180-196），与 H&J Eq.2（R1=R+δN、R2=R−δN ⇒ F2−F1=2δHN ⇒ C=N^T H N）逐项一致，δ 同时决定位移 ±δN 与分母 2δ；`dimer-curvature` 用解析 Hessian 校验到 0.07/0.09%（容差 0.2%），并单独钉住 δ 的因子（若分母写成 δ 会 2× 红）。
- 报告 27 §2 的能量形式推导 `(E2−E0)/δ² = C/2 − g·N/δ` 复核**正确**（对 x+(−δN) 展开即得），即「1/2 因子 + 梯度项」的说明无误。
- Eq.21 两支与 VASP/H&J 一致（平行分量恒反、C>0 时丢垂直分量）；`dimer-translation-force` 四个断言分别钉住两支，注入 (iii) 会红。
- Eq.13：从两项 Fourier 模型 `A sin2θ+B cos2θ`，`F0=B`、`F0'=2A` ⇒ `θ=½atan2(−2F0,F0')`，再取首个正根（+π/2）。测试既对照精确 Fourier 根（1e-3 容差 1e-7、0.3 容差 1e-3），也对照 Eq.6 的差别，并用一把 magic number（θ(0.0136,0.0148)=1.0352）钉住「首个正根」而非主值支 —— 后者是真正的分支回归 pin。`f0'=0` 的 π/4 极限由 atan2 自然给出（无需分支）。
- δ 定义（centre→image=1.8897e-2 bohr）与 VASP `DdR` 的关系是**外部代码断言**而非本仓证据（[待校准] 已标注），且报告 28 §6.4 实测 δ×8 只改 0.0013%（报告 27 §6.4 同结论），故不构成 finding，但「VASP 的 DdR 是两倍」这句无人复核的外部事实建议改为「本实现采用 pysisyphus 约定」。
- 随机轴：`random_seed(size/put)` → `random_number` → −0.5 → 归一（dimer.f90:483-492）。**关于「同进程连抽会掩盖缺 seed」的担忧不成立**：`dimer-initial-axis` 用**同一 seed 连抽两次**并比逐位相等 —— 若去掉 `random_seed(put=)`，生成器序列继续推进，两次抽取必然不同 → 该测试**会红**；seed 42 vs 7 的差异 >1e-3 再补一层。注意 `dimer-reproducible` 里 `difference < 1e-4` 这条断言对「seed 被忽略」是**恒真**的（两个 seed 都走同一条路），但它不是唯一防线，`dimer-initial-axis` 覆盖了 seed 依赖（I2 类观察，非缺陷）。
- VASP 诊断阈值可达性：`rot_f_rms_th=2.65e-4` 与实测 torque rms 3.7e-4…9.4e-4（前几步不收敛 → 5 次 warning，与报告 27 §3(4) 一致：stdout.txt:237/241/249/253/261 正好 5 处 `converged=F`，warning 汇总在 :525-530）——阈值**临界可达**，前几步恒超阈；这不是错误（warning 是设计行为），但意味着默认配置下 dimer 每步都打 warning，建议评估把阈值放宽到 5e-4 或把 warning 去重（H4 同源）。

**6 虚频确认 —— 有实现（复用 M3），但近零/线性两处不成立（H1、H3）。**
`confirm_saddle`（ts.f90:246-284）确实调用 `engine%hessian` + `landscape_vib_analysis`（M3 实现，含 3N−6/3N−5），把 `n_imag`/`imag_freq` 写进 result 并打印，CLI 测试断言 `saddle confirmation - imaginary modes: 1`（注入 (iv) 会红，报告 28 §6）。但：
- **不是**「报告虚频数而不断言」：`n_imag/=1` 有 warning（ts.f90:281-284），只是不升级为失败（H2）。
- **硬约束 2 无代码**：`confirm_saddle` 用 `settings%engine%hess_step`(5e-3)/`hess_acc`(0.3)，**没有**任何 |freq|<3 cm⁻¹ 的检测与重算；`imag_cutoff=-20 cm⁻¹` 比该带宽 6.7×，所以带内模（−3…−20 cm⁻¹）会被报成「0 虚频」而不是触发收紧（H1）。`--lts` 也没有对应 `--lvib-step/--lvib-sccacc` 的 CLI（main.F90:2886/2901 只有 lvib 版本）——**用户连手动收紧都做不到**。

**7 etemp —— 打印正确，result 字段死（H1 之外的 M1）。**
`ctrl%etemp = settings%etemp`（ts.f90:147）+ `set_calculator` 内 `push_calculator_etemp`（engine.f90:292,318），`engine_report` 从 `calc%etemp` 回读打印（engine.f90:793）；`set_numerical_accuracy` 只拷 `hess_acc`，不动 etemp（engine.f90:246-255），`new_landscape_engine` 之外**没有**任何路径改 etemp → 一次运行内恒定 ✓。CLI 测试断言设置值与回读值（landscape_cli_check.py:435-438）。

**8 测试可证伪性 —— 逐个判定（34 条）。**
可证伪且强：`rigid-basis-orthonormal`（6 列 + 内坐标比较，抓形状截断）、`rigid-linear-basis`（5 列）、`rigid-projection`/`prfo-rigid-projection`（3 条断言，含 raw 步的幅值 >1e-3 前置条件 —— 避免「恒真」）、`prfo-lambda-n`（残差 + 步长比双断言）、`prfo-hlow-lift`/`prfo-negative-downhill`（去掉抬升会变 error → 红）、`bprfo-radius-split`（1e-9）、`dimer-curvature`（符号 + 2δ 因子 + 解析对照）、`dimer-translation-force`（两支四断言）、`dimer-rotation-angle`（含 magic-number 分支 pin）、`dimer-rotation-alignment`（torque 降 >5×）、`dimer-velocity-update`（4 例）、`dimer-mobility`、`dimer-initial-axis`（seed 依赖 + 未知名报错）、`dimer-invalid`（两条非法参数）、`dimer-no-hessian`（n_hess==0 + 收敛）、`dimer-reproducible`。
弱/需注意：
- `dimer-reproducible` 的 `difference < 1e-4`（test:1445）对 seed 失效恒真 —— 由 `dimer-initial-axis` 兜住（可接受）。
- `mb-prfo-saddle`/`mb-bprfo-saddle`/`mb-methods-agree` 属**结果级**验收断言：注入 (i)（λ_n 不做迭代）它们**仍会通过**（报告 协议级正确性只由 `prfo-shifts`/`prfo-lambda-n` 兜住，报告 28 §6.1 已自曝）。这是「全绿≠协议正确」的又一实例，已被披露，记 INFO。
- `dimer-invalid` 第二条只查 `result%converged==.false.`（不查消息）—— 弱但非恒真。
- 没有发现「比较自己刚赋值的量」这类空测试；也没有发现被放宽到无意义的容差（最宽的是 MB 曲率的 0.2% 相对容差，对应 0.07/0.09% 实测，合理）。

**9 CLI / 接线 —— 基本正确，三处不一致。**
- `p_run_lts = 19` 独占（setparam.f90:213；其余为 1–15、21、71、100–104）✓；`set_runtyp('lts')`（set_module.f90:1070）✓；`main.F90:590` 把 lts 加进参数文件选择分支（否则会 `env%terminate('internal error')`）✓；`main.F90:986-987` 做了 `res` 回写 ✓（AGENTS §6-7）。
- 每个 `--lts-*` 都写进 `ltset` 且被内核消费（逐条比对：method/trust/trust_max/hlow/max_steps/level/mode_overlap_min/alpha/micro_cycles/target_mode/init_mode/delta/dR/rot_*/ninit/seed/step_max/translate_max_iter/recalc/no_verify/no_rigid/restart/hessian/hessian_file）。**没有 `--lts-step0`、`--lts-hess-step`、`--lts-sccacc`**（M6/H1）。
- `--namespace`：`--lts` 的 `xtbts.xyz`/`xtbts.log` 走裸 `open(file=name)`（ts.f90:308,320），**不过 `get_namespace`**，而 scan（scan.f90:272/321）与 vib（vib.f90:315）都过 → `--namespace ns --lts` 仍写 `xtbts.xyz`，同目录两个命名空间运行互相覆盖（M3 的 MEDIUM-A 是「双前缀」，这里是「零前缀」，同一族问题，M3）。

**10 数值卫生（N1..N17 相关项）—— 通过。**
`implicit none(type,external)` 四个新文件齐备；`use xtb_mctc_accuracy, only:wp` 齐备；无 `real*8`/`d0`/直调 `dgemm/dsyev`（grep 空）；模块级只有 `parameter`（`rigid_dependent_tol`、`dimer_kappa_floor/dimer_tiny/dimer_pi`）与类型定义，无可变量；除零/开方/对数守卫齐（`2δ`、`1/κ`、`sqrt(1−α²)`、归一化、`f_norm≤tiny`、`nrm>trust`）；Hessian 进入 `landscape_spectrum` 前对称化，`engine_hessian` 出口再对称化；步向量在投影后不放大（trust 是上界）；`!>` 文档覆盖模块/类型/公开过程，单位与文献齐；特征值升序约定在 eigenfollow 头注与 `mctc_syev` 说明中显式声明；模态追踪 argmax+sign realign 显式；随机数唯一使用点 + 显式 seed ✓。

**11 回归 —— 未见风险。**
`settings.f90` 增量为纯新增（新类型 + 新常量 + 新查询函数，未改动任何 M0..M3 默认值）；`results.f90` 只加字段；`landscape_driver.f90` 只加 `case ('ts')`；`main.F90` 只加 `--lts*` 分支与 lts 块；`CMakeLists/meson.build/main.f90` 三处注册齐（`landscape-saddle` 在 test/unit/CMakeLists.txt:50、meson.build:61、main.f90:48/103），`xtb/landscape-ts-*` 4 个 CLI 测试均在 CMake 与 meson 双注册，且 ts 三个正例测试在 OMP_NUM_THREADS=1 属性列表内（CMakeLists.txt:1152-1154）。未发现重名 `add_test`（报告 28 §6.5 的空 uniq -d 已核）。

## 2. HIGH（P1）—— 逐条 file:line、理由、最小修复

**H1（硬约束 2）`--lts` 无法收紧 FD 参数，代码里也没有「近零曲率 → 收紧」路径。**
`src/landscape/tasks/ts.f90:149-151`（provider 用 `settings%engine%hess_acc`=0.3）、`ts.f90:246`（`engine%hessian` 不传 step → `ctrl%hess_step`=5e-3，engine.f90:647-649）、`src/prog/main.F90:2886,2901`（只有 `--lvib-step`/`--lvib-sccacc`，无 lts 版）、`src/landscape/types/settings.f90:465`（`imag_cutoff=-20 cm⁻¹`）。
现象：带内（0±3 cm⁻¹）曲率的符号仍按默认 FD 判定并输出，且 3 cm⁻¹ 的模落在 `-20` 阈值以上 → 被算作「非虚频」；用户无法用 `--lts` 施加规定的补救（step 0.002 / sccacc 0.1）。
为什么是问题：硬约束 2 是 M4 的验收前提之一（任务书 + PLAN §9.5），报告 28 §3.3/§10 把它**重新表述**为「噪声远低于带宽，故无需收紧」——这只解决了随机噪声分辨率，没有覆盖「近零曲率需要重算并明确标注」的字面要求；当前实现下 flat TS 的「虚频确认」可能给出错误且不可收紧的结论。
最小修复（任一即需落地并记录）：(a) `confirm_saddle` 增加一个命名常量（如 `ts_curvature_band_cm1=3.0`）：当 `minval(vib%freq(n_zero+1:n3)) > -band` 时用 `step=2e-3`、`sccacc=0.1` 重算一次 Hessian/分析，并把两次结果与所用参数一起打印；(b) 至少加 `--lts-step`/`--lts-sccacc` 两个 flag（照抄 `--lvib-step`/`--lvib-sccacc` 的 15 行模板）+ 一条显式 warning「near-zero curvature: the sign is resolution-limited」；(c) 若决定不实现，必须在 PLAN §9.5 写入显式附条件并把 `imag_cutoff` 的带宽关系说明补进 ts.f90 模块头（当前模块头只声称「由惩罚条款负责」，没有指向代码）。

**H2（V3）非一阶鞍点仍以成功退出。**
`src/landscape/tasks/ts.f90:281-284`（`n_imag/=1` 仅 warning）+ `ts.f90:213-215`（失败才 `env%error`）。
证据：`m4-saddle-data/failure-modes/fm_from_hnc.exit` 与 `fm_stretch2neg.exit` 均为 `0`，对应 stdout 为 `saddle confirmation - imaginary modes: 0` + `landscape task terminated: converged`。
为什么是问题：任务目标是**一阶鞍点**（PLAN §9.5 交付物），退出码 0 会让 CI/验收脚本把它当成成功；也是「测试全绿（CLI 测试只跑 HCN 正例）但语义错误」的典型。
最小修复：在 `confirm_saddle` 里把 `n_imag/=1` 升为任务失败（`result%converged=.false.` + `result%message="not a first order saddle point"`，或直接 `env%error`），仍照常写 `xtbts.xyz`/`xtbts.log`（把确认结果留在文件里）；配一条 CLI 负例测试（从线性 HNC 出发，断言非零退出码）。

**H3（V1，M3 范围但直接打在 M4 交付物上）线性分子的虚频确认错误。**
`src/landscape/vib/modes.f90:151`（`if (project_tr .and. .not. linear)` 跳过投影）、`:179-185`（linear 分支无条件取最低 `n_zero=5` 个本征值为零模）、`:216`（`if (linear .and. i <= n_zero) cycle`）。
证据：`m4-saddle-data/failure-modes/w180_lvib.txt`（线性 H₂O 报 0 虚频）对 `w180_hess.txt`/`hessian`（未投影本征值 −0.3618 ×2）。
为什么是问题：`--lts` 的确认就是 `landscape_vib_analysis`，线性 TS（线性 HXH 型）会得到「0 虚频」→ 交付物「虚频确认」在该类体系上失效；M3 只覆盖了线性**极小点**，M4 未补线性鞍点测试。报告 28 §7/§10 自己也写「应在 M4 收口前修复」。
最小修复：linear 分支同样做刚体投影（M3 已有 3N−5 投影路径）或「按 `zero_mode_tol` + 投影零模」选零模而非无条件取最低 5 个；补一个线性二阶鞍点的单元测试（现有 w180 几何即可）。

**H4（V2）刚体模噪声令 `lifted` 恒真、hlow 每步实际生效、警告刷屏。**
`src/landscape/saddle/prfo.f90:234-251`（`nneg` 用 `evals(i)<0`，抬升用 `b(i)<hlow`；B-PRFO 同逻辑 bprfo.f90:155-170）。
证据：`failure-modes/ts_hcn_hlow1e-12.txt:233…247` 每一步都 `lifted=T` + `the downhill subspace has a negative curvature` 警告；`fm_from_hnc.txt:329-330` 同一警告在汇总里出现多次；报告 28 §5.1 实测 λ_n 在 hlow=1e-2 vs 1e-6 下为 −1.466e-2 vs −1.865e-2、步数 4 vs 6。
为什么是问题：(1) 文档化的「>1 个负本征值」防护在真实体系上恒触发（数值 Hessian 的刚体模 ±1e-11），`lifted`/该 warning 因此**不能**作为防护生效的证据（审阅若据此宣称验证过会得出错误结论）；(2) 未标定的 hlow=1e-2 事实上是对整个下坡子空间的曲率地板，软内模会被抬到 1e-2（抑制其下坡弛豫）→ 影响收敛路径（已实测）而文档仍称它只在「多负本征值」时生效（settings.f90:430-433）；(3) 每步一条 warning 淹没真实诊断。根因是**步向量做了刚体投影，但建步用的 Hessian 谱没有**。
最小修复：在 `landscape_prfo_step_spectrum`/`landscape_bprfo_step` 判 `nneg` 与抬升之前，对 `evals/evecs` 做刚体投影（用 `landscape_rigid_modes` 的 P H P 投影或把 |λ|<噪声阈的刚体方向剔除，其中噪声阈可复用报告 28 §3.1 的 σ_g 量级），使 `lifted` 只在真实第二负曲率时真；并把 hlow 的默认值/生效条件写准（或按体系尺度归一）。至少：把该 warning 改成一次性（首次）并修正 settings.f90 文档。

## 3. MEDIUM（P2）

| # | 位置 | 现象 / 为什么是问题 | 最小修复 |
|---|---|---|---|
| M1 | `types/results.f90:150-152`（字段）| `landscape_result%etemp` 文档写「read back from the calculator」，但**全仓无任何赋值**（grep 无 `result%etemp =`），恒为 0；报告 26 §1 把「`etemp` in `landscape_result`」列为交付物。这是 M3 MEDIUM-B「死字段」教训的复现：硬约束 1 的「记录」只落在 stdout/log（log 里写的还是 `settings%etemp`，不是回读值）| 在 `landscape_ts` 的 `engine%report` 前后把回读值写入 `result%etemp`（可给 engine 加 `effective_etemp()` 查询），或删掉字段并改报告措辞 |
| M2 | `saddle/prfo.f90:689-706` | prfo 的 `reset_result` **不清** `result%conv`（历史数组/n_iter/converged），而 `optimize/driver.f90:535-558` 与 `dimer.f90:1032-1058` 都清 → 复用同一 result 对象跑两次 P-RFO 会拼接过期收敛历史（`landscape_result_trim` 依赖 n_iter）。M4 生产路径每进程只跑一次，故不可见 | 把 dimer 版 reset 复制到 prfo |
| M3 | `tasks/ts.f90:308,320` | `xtbts.xyz`/`xtbts.log` 不过 `get_namespace`（scan.f90:272/321、vib.f90:315 都过）→ `--namespace ns --lts` 仍写非命名空间文件，同目录并发运行互相覆盖 | 用 `get_namespace('xtbts.xyz')` 恰好施加一次（注意 M3 双前缀教训：不要再叠加 prefix） |
| M4 | `saddle/prfo.f90:497-500` + 报告 26 §5(iii) | 驱动级刚体投影与 `remove_rigid=.false.` 无任何可证伪测试（MB 面 ndim=2 ⇒ n_rigid=0；单元测试只测例程本身）→ 「M1 债务已在驱动关闭」在测试层面未验证；删掉驱动那行我预测 44/44 仍全绿 | 加一条 3N 维（如 3 自由度合成面或 6 原子模型）驱动测试：`remove_rigid=T` 时步向量与刚体基正交、`=F` 时不正交，或断言两者轨迹不同 |
| M5 | `saddle/prfo.f90:678-682`（选择时 report，printlevel≥2 才每步）+ `dimer.f90:866,868-872` | P-RFO 路径**全程只打印初始模**（printlevel=1），收敛点的转换向量/曲率都不报，且最终向量不重定相（相位只在选择时施加）；dimer 则对最终轴 `set_phase` 并报「final curvature + transition mode/vector」。同一 TS 用不同 method 打印的方向可能相反 → 影响 M6 IRC 的初始方向选择，也与 eigenfollow 头注「同一几何总印同一方向」的说法不符 | 在 `landscape_saddle_optimize` 结束（`finish` 前）对 final `mode` 调 `landscape_transition_mode_set_phase` + `landscape_transition_mode_report`，与 dimer 对齐 |
| M6 | `saddle/dimer.f90:786`；`settings.f90` step0=3.7795e-1、step_max=2.8346e-1 | `mobility=min(step0,step_max)/|F|` ⇒ 默认下 `step0` **永远不生效**（step_max 更小），且无 `--lts-step0` flag；模块头「第一次平移长度 = min(step0,step_max)」被实测反驳：GFN2 HCN 首步 step=1.0322E-01、mobility 8.93E-01（κ 限幅 1/1.1198 绑住）| 文档改成「min(step0,step_max) 是上限，κ 限幅可再缩短」；`step0` 要么加 CLI 要么删掉 |
| M7 | `saddle/dimer.f90:943` + `types/results.f90:331` | dimer 把 `step_max` 写进 `record%trust_radius`，于是 stdout/日志的 `trust/bohr` 列恒为 2.8346E-01（另一含义），消费者会把「上限」误读成「当前 trust」；步表是唯一面向用户的逐步轨迹 | 给 `landscape_step` 加 `bound_kind`/或 dimer 专用表头；至少在该行加注释列名 |
| M8 | `saddle/dimer.f90:375`（κ<0 不限幅）、`:343-348`（v·F≤0 时 step=0） | (a) κ<0 时不限幅 ⇒ `h=mobility·|F†|` 在刚方向可无限增大（报告 27 §4 实测 1D 情形会「ping-pong/能量 +1e2 Eh」，且用了 step_max 救场；已验证体系未出现）；(b) 速度被丢弃时**整步为 0** 且 `exit`，产生「空转」宏迭代（dimer_random/stdout.txt 第 4、9、13、23 步 dmax=0，39 步里 4 次）→ 白耗 eval 与步预算。两者都不产生错答案，但都是报告 27 §4 已知偏离的未收口部分 | (a) 在 κ≤κ_floor 时保守取 `tau=min(mobility, 1/|κ|→大)` 即维持现状但补一条「κ<0 分支已实测」的说明；(b) 速度置零后仍取一步力方向位移（quick-min 标准做法），可消掉空转迭代 |

## 4. LOW / INFO

- **L1** 报告 28 §4.1/§4.2 把 MB 本征值 `−1.196576/+0.781248` 标为 Eh/bohr²，实为**无量纲**面值；乘 `kcaltoau` 后应为 ≈−1.9e-3/+1.2e-3（自证：同一文件 `dimer curvature (force/analytic): 2.4345E-02 / 2.4363E-02`，报告 26 §3.4 亦写「曲率量级 kcaltoau≈1.6e-3 Eh/bohr²」）→ 单位标签与内部一致性错误。
- **L2** 计数不一致：报告 27 §1/§6.1 称「14 new dimer unit tests」，实际新增 12（22+12=34，与报告 27 的 34 及 `xtb-tester-saddle.txt` 的 (23/34) 一致）；报告 26 §1 写 21、§4.3 写 22（22 才对）。
- **L3** `ts.f90:338-341`：`result%n_imag=0` 时仍打印 `most negative frequency: +707.64 cm^-1`（标签误导，应只在 `n_imag>0` 时打印该行，或改称 "lowest internal mode"）。
- **I1** `mb-prfo-saddle`/`mb-methods-agree` 对 λ_n 注入不敏感（报告 28 §6.1 已披露）：验收断言验的是**结果**而非协议，协议正确性依赖 `prfo-shifts`/`prfo-lambda-n`。建议把「PLAN §9.5 验收 = P-RFO 正确」这句话弱化，或给验收测试加一条 λ_n 残差断言。
- **I2** dimer 旋转的 `F0` 取的是 `|f_rot|`（恒 ≥0，符号由 q 承载），故 `if (f0<=0) return`（dimer.f90:341）除恰零转矩外不可达；单测的 Fourier 模型也只覆盖正 F0，负值/符号分支无覆盖（无证据表明有害）。
- **I3** `prfo.f90:366` 在 `recalc=0` 时仍分配 `hnew(ndim,ndim)`；`xtb/landscape-ts-dimer` 单测约 39 步 × ~22 次 SCF 梯度 ≈ 900 次评估（加数值 Hessian 确认），是 landscape 里最贵的测试，必要时可把测试的 `--lts-rot-max-iter` 调小。

## 5. 无 CRITICAL 的说明：我主动检查过的攻击面

- 逐行核对了 4.16/4.18a/4.18b/4.19/4.20 与实现的对应，含残差单调性/根存在性/边界（除零面 `λ<bmin≤b_i`）；B-PRFO 的 α 划分、micro 对分与半径方程残差；dimer Eq.2/5/13/21 与 2δ 因子、1/2+梯度项推导。
- `eigenfollow` 的选择/跟随/相位/低 overlap 重选、`rigid_modes` 的 Gram-Schmidt 与线性退化、驱动中投影的使用位置（步向量，非 Hessian）。
- 所有除零/开方/对数/归一化/trust 裁剪/`huge`/NaN 守卫；失败路径是否产生 NaN 或未捕获错误（结论：有界且经 `env%error`）。Debug (`-ffpe-trap`) 结论我没有运行（见 §6）。
- 测试集 34 条逐条做「故意写错是否仍通过」推演 + 与 `m4-saddle-data/` 的实测数字对表（MB RMSD、dimer 步数/距离/seed 差、5 处 rotation warning、`n_hess=0`、lifted=T）。
- CLI：runtyp 19 唯一性、`set_module`/`main.F90` 接线、`res` 回写、18+9 个 flag 的消费链、namespace、OMP 环境属性、三处注册与重名。
- 数值卫生：`implicit none`、`wp`、`_wp` 字面量、BLAS/LAPACK 包装、模块级可变量、`!>` 文档、扁平化 `xyz(3,n)`/`(dim,n)`、升序本征值声明、seed。
- 回归面：`settings.f90` 纯新增、`results.f90` 纯加字段、M0..M3 默认值未动。

## 6. 需运行验证（我无法执行，交父会话/验证者）

1. `OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape` → 期望 44/44；`ctest -N -R landscape | tail -1` = 44；`grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d` 空。
2. 回归子集 `-R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'` → 12/12。
3. **M4 的关键回归**：删掉 `prfo.f90:497-500` 驱动里的 `if (n_rigid > 0) call landscape_project_rigid(...)`（保留例程本身），重编后跑 `-R landscape`；我预测 **44/44 仍全绿** → 证实 M4「驱动级投影未被测试覆盖」。
4. H2/V3：`xtb hnc.xyz --gfn2 --lts --lts-method prfo --norestart; echo $?` 从线性 HNC 出发 → 期望 `imaginary modes: 0` 且 `$?=0`（复现报告 28 §7 V3）。
5. H4/V2：`xtb hcn.xyz --gfn2 --lts --lts-hlow 1e-12 --norestart` → 期望每步 `lifted=T` + 同一 warning 多次出现。
6. H1：`xtb ... --lts --lts-sccacc 0.1` → 期望「未知参数」报错（证明补救路径不存在）；对照 `--lvib --lvib-sccacc 0.1` 正常。
7. H3/V1：取 `failure-modes/v1-linear-water/` 的线性几何做 `--lts`（或直接对线性二阶鞍点几何跑确认）→ 期望报 0 虚频。
8. M3：`xtb hcn.xyz --gfn2 --lts --namespace ns --norestart` → 检查是否写出 `ns.xtbts.xyz`（应无）与 `xtbts.xyz`（有）。
9. 成本：`ctest -R landscape-saddle`、`ctest -R landscape-ts-dimer` 各计时，确认 CI 预算（dimer 测试约 900 次 SCF 评估）。
10. （可选）Debug 构建 `-fbounds-check -ffpe-trap=invalid,zero,overflow` 下跑 `xtb --lts` 三方法的 E2E，复核报告 27 §6.2 的声明。