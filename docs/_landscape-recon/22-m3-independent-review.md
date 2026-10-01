## Review

**结论：有条件接受（Accept with conditions）。M3 尚不能直接宣称完成。**

- **CRITICAL：0**；**HIGH：1**（`vib/modes.f90` 额外近零模分支用未初始化下标索引矩阵，UB + 静默错误频率，且被模块文档"从不丢弃"的承诺反证；测试完全没覆盖这条路径）
- **MEDIUM：2**（`--namespace` 下 `hessian` 文件名被双重加前缀，写→读闭环断裂；PLAN §12.11 / 报告 20 §3.3 / 报告 21 §5.3(d) 把 `--lvib`↔`--hess` 差异归因于投影，机制句与代码矛盾、归因也未被自己的数据支持）
- **LOW：3 + INFO：3**（缺 `--hess` 的"未优化几何"警告；热化学参数无校验（`--lvib-temp 0` → Inf/NaN）；文档/状态簿记错误；MAPLE 常数 0.04% 系统性差异说明）
- 质量加权（`h/√(m_im_j)`，`mol%atmass` 为电子质量）、`autorcm=219474.63067`、3N−6/3N−5 切换（5/6/单原子 3）、虚频负值约定、`main_freq`/`thermodyn` 复用、`res` 回写、runtyp=21 无冲突 —— **逐条核对正确**（有 file:line 证据）
- M2 遗留 M-1/M-2 语义正确、已被 CLI+单元测试覆盖

完整报告见下（父会话落盘到 `docs/_landscape-recon/22-m3-independent-review.md`）。

---

# 22 — M3（vib: Hessian / freq / thermo）独立复核报告

> 角色：fresh-context read-only 复核者。无法运行 shell / 测试；所有结论来自源码、测试、PLAN、报告 20/21 与
> `docs/_landscape-recon/m3-vib-data/` 里的原始 stdout/g98.out 交叉核对。凡涉及"数值行为"的判断，优先以仓库内
> 已记录的实测数据为准（本项目静态分析已被证伪三次）。
> 复核对象：M3 实现（`src/landscape/vib/*`、`tasks/vib.f90`、`types/hessian.f90` 的 `file` provider、
> `test/unit/test_landscape_vib.f90`）+ 验证轮报告 21 + M2 遗留 M-1/M-2。

## 0. 结论

| 问题 | 回答 |
|---|---|
| **M3 是否可宣称完成？** | **尚不可**。修掉 HIGH-1（P1）与 MEDIUM-2 后可以宣称完成功能；PLAN §9.4 / AGENTS.md §2 的状态文本还需改正（报告 21 已把实验 #2/#3/#12 做完，报告 20 §5.1 与 AGENTS.md 仍写"未做"）。 |
| **是否可进入 M4？** | 可以并行开始，但 **M4 复用 `landscape_vib_analysis`（鞍点模式判定）之前必须修掉 HIGH-1**；`engine%etemp` 死字段（报告 21 F1，MEDIUM）必须在 TS/IRC 依赖它之前解决或删除。 |
| **有 CRITICAL 吗？** | 没有。检查面见 §6。 |
| **实现质量** | 频率数学链、投影选择、质量/单位约定、`--hess` 互操作、失败路径与 CLI 接线整体扎实；缺陷集中在"额外近零模"这一条未测分支与命名/文档一致性上。 |

## 1. 逐条回答任务书的攻击面

| # | 攻击面 | 结论 |
|---|---|---|
| 1 | 质量加权与频率换算 | **正确**。`massWeightHessian`（`src/freq/utils.f90:32-56`）为 `h(i,j)/sqrt(m_i m_j)`；`mol%atmass = atomic_mass(at)` 为**电子质量**（`src/mctc/param/atomic_masses.f90:24` `amutoau*[amu]`），与 `numhess`（`src/hessian.F90:325-326` `amass_au=amass_amu/sqrt(amutoau)`）同一约定；`autorcm=219474.63067`（`src/mctc/convert.f90:40`）作用在**有符号 sqrt** 后的量上（`diagHessian` 已做 `sign(sqrt(abs(ev)),ev)`，`src/freq/utils.f90:77`；`modes.f90:151` 再乘 `autorcm`，与 `src/hessian.F90:431` 逐字一致）。ORCA 的 5140.4867 = 219474.63/√1822.888（amu 质量版）；MAPLE 的 2721.1383 是 **Eh/Å² + amu** 版（`MAPLE/.../frequency/frequency.py:1044-1059`），三者单位约定不同——见 INFO-2。约化质量用 amu（`modes.f90:239-265` 与 `src/hessian.F90:509-525` 同式）。 |
| 2 | 投影（模数/线性切换） | **正确**。`modes.f90:146-152` 仅对**非线性**分子调用 `projectHessian(work, mol, .true., .true.)`，与 `--hess` 的 `if(.not.res%linear)`（`src/hessian.F90:359`）一致；`n_zero` 不是写死 6：线性 5、非线性 6、单原子 3（`modes.f90:132-141`）。线性性判据 `modes.f90:268-317` 与 `xtb_axis::is_linear`（`src/axis_trafo.f90:31` `linthr_bohr2=1e-4`）逐行同构，`linear_tol` 默认 1e-4（偏离 PLAN §5.3.8 的 1e-8，§12.11 已记录，理由正确）。 |
| 3 | 本征值排序与虚频约定 | **正确**。`syev` 升序；虚频为**负值**（不是 `i` 前缀），与 `PREIGF`/`vibspectrum` 一致；`vib%n_imag = count(freq < imag_cutoff)`（`modes.f90:219`），而 `print_thermo` 的 `nimag` 用的是同一个 `set%thermo_ithr` 并在 `freq_scal≠1` 时才可能不同（`thermo.f90:161-170` 有告警交叉核对）✔ 约定自洽。 |
| 4 | `landscape_hessian_file` 读写 | **互操作成立**（实测：`expD/h2o/lvib-read-hess/g98.out:23` 与 `expD/h2o/hess/g98.out:23` 逐位相同）。格式与 `wrhess` 逐字节一致（单测 `hessian-file-roundtrip` 用 `wrhess` 做外部锚点，`types/hessian.f90:687-705`）。读入转置约定与 `rdhess` 一致（`rdhess` 把文件第 i 行读进 `h(j,i)`，`src/freq/io.f90:139-145`；本实现 `types/hessian.f90:600-607` 同）→ 对称文件无影响，非对称可检出（`types/hessian.f90:649-655`）。`$hessian`/`$hessian (projected)` 头、`$end`、CRLF/逗号/tab 分隔、D 指数、维数=3N²、非有限、非对称 六类失败路径齐备且不改动目标矩阵。**注意**：文件里存的是**完整方阵**（不是下三角），writer docstring 表述有误（LOW-3）。 |
| 5 | 测试可证伪性 | 逐条评定见 §4；不存在"自证"或"恒真"的致命断言，但有 1 条未覆盖路径（=HIGH-1）与 1 处薄裕度（`water-vs-trproj`）。 |
| 6 | 与既有 `--hess` 的真实一致性 | **复用而非重写**：`main_freq`（`src/main/property.F90:695`）→ `print_thermo`/`thermodyn`；`vib_normal_modes` 用同一个 `writeNormalModesTurbomole`，质量单位同为 amu（`tasks/vib.f90:251-260` vs `property.F90:772`）。文件名/表头/列结构一致（`expD_structure_diff.txt`）。ZPE、S、Cp 在 H2O/CO2 上逐位相同（`expD_interop.csv`）。**归因叙述有问题**（MEDIUM-2）。 |
| 7 | CLI 与状态 | **正确**。`p_run_lvib=21` 与既有集合 `{1..15,71,100..104}` 无冲突（`src/setparam.f90:197-218`）；`set_module.f90:1070`、`xhelp.f90:359-394`、`main.F90:966-980` 三处同步；`res` 回写存在（`main.F90:976-978`）；`--lvib-imag-cutoff -20` 能被 `TArgParser` 当参数（`src/prog/argparser.f90:117-119` 的第三条件）✔；无新 flag 时既有行为不变（无新 flag 不触碰任何 `set%`/settings）。 |
| 8 | 数值卫生与层边界 | 基本合规：`wp`、无裸 real、无 `stop`、无模块级可变量（`zero_mode_tol` 是 `parameter`）、BLAS/LAPACK 走包装、内部 a.u.、公开过程均有 `!>`。**层边界**：`vib/**` 用了 `xtb_type_*`/`xtb_freq_*`/`xtb_propertyoutput`/`xtb_setparam`，与 PLAN §4.2 规则 1 的字面（只许 `xtb_landscape_*`+`xtb_mctc_*`）冲突，但 §4.3/§5.3.8 明确把 `xtb_freq_*`/`main_freq` 交给 `vib/*`，且 `set%` 写入是 §12.11 记录的唯一例外 → 判定为**计划自身表述不一致，非新增漂移**。除零/开方守卫：`reduced_masses` 有 `sum2>0` 守卫；`mass_unweight`/`reduced_masses` 对未知元素（`atomic_mass→0`）会得到 0/Inf，属既有 xtb 行为，不单列。 |
| 9 | M2 遗留 | M-1 `--lscan-max-steps`（`main.F90:2403-2416` → `lsset%max_steps` → `relax_scan.f90:579` 传入内层优化器）语义清楚：0 = 每点只求一次能量不松弛；M-2 全域未收敛分支（`tasks/scan.f90:224-236`）在最小点搜索之后判定，1D/2D 判据一致（都要求点收敛），能量保持 NaN、几何保持输入几何、消息精确、CLI 测试 `xtb/landscape-scan-max-steps` 断言 `lowest energy: NaN` 且 `xtbscan.log` 仍有 5 帧 ✔。**INFO-3**：该情形退出码仍为 0（`env%warning`），与 `--lopt` 非收敛不同；这是 PLAN R-04 的设计选择且已文档化，不作发现。 |

## 2. 发现（按级别）

### HIGH-1（P1，阻断"M3 完成"）：额外近零模分支用未初始化下标索引矩阵

* **位置**：`src/landscape/vib/modes.f90:174-182`（第一轮只记前 `n_zero` 个近零模，多出的仅置 `extra_zero=.true.`，**不记下标**）
  → `src/landscape/vib/modes.f90:192-198`（第二轮 `if (abs(freq_cm(i)) < zero_mode_tol .and. .not. linear) cycle` 把**所有**近零模都跳过，包括那些 extras）
  → `src/landscape/vib/modes.f90:208-212`（`vib%modes(:, i) = work(:, order(i))`、`vib%freq(i) = freq_cm(order(i))` 对 `i = n_zero+1 .. n3` 逐个使用 `order(i)`）。
* **现象**：设 `n_extra = ` 超出 `n_zero` 的近零模个数（`extra_zero = .true.` 时 `n_extra ≥ 1`），则第二轮结束时 `k = n3 - n_extra`，`order(n3-n_extra+1 : n3)` **从未被赋值**（`allocate(freq_cm(n3), order(n3))` 无 `source`）。随后 `work(:, order(i))` / `freq_cm(order(i))` 用未初始化整数下标**越界读取**（`order(i)` 可能 <1 或 >n3）：
  * 越界读 → 未定义行为（Release 无 bounds check，可能读到垃圾甚至非法地址）；
  * 即使恰好落在数组内，也会把某个内模的频率/模向量**复制**到另一列 → 频率表、`vib_normal_modes`、`res%freq`/`res%hess`（进而 ZPE 与全部热化学，因为 `print_thermo` 只过滤 `|f|>1 cm⁻¹`，复制出的大频率不会被过滤）**静默错误**。
* **为什么是问题**：这是新代码，且与模块自己的契约相反——`modes.f90:38-51` 与告警文本 `modes.f90:221-230` 明确写"额外的近零模**从不丢弃**、按升序留在内模列里"，而实现把它们从 `order` 里漏掉并留下未初始化槽位。触发条件（≥7 个 `|f| < 0.01 cm⁻¹` 的模式，即本征值 < ~2e-15 a.u.）在真实输入中可达：
  1. **`file` 源**：任何秩亏 >6 的合法 TURBOMOLE Hessian —— 例如用冻结原子（`$constrain`）跑出的 `--hess` 文件（冻结行列恒 0），或子系统/部分 Hessian。这是套件自己主推的互操作路径（§12.11、报告 21 §5.4）；
  2. **数值源**：两个碎片相距很远（相互作用曲率 ∝ r⁻⁶…r⁻⁸；报告 21 实验 B 实测 H2 在 6 Å 时 3.30 cm⁻¹，外推 ~30 Å 量级即跌破 0.01 cm⁻¹）→ 6 个相对运动近零模成为 extras；
  3. **M4 直接受影响**：鞍点/键断裂几何的模式判定会复用本函数，而该函数在"多出来的近零模"上返回垃圾。
* **证据**：79 个验收作业的 stdout 里 **0 次**出现该告警（`grep -r "more than the expected number of near-zero" docs/_landscape-recon/m3-vib-data` 无命中），`test_landscape_vib.f90` 13 条用例中**没有**覆盖 `extra_zero` 的用例 → 正是"全绿但错误"的典型：绿色套件从未走过这条分支。
* **最小修复**（改动 3 行 + 1 个新整数）：把第二轮改成"只跳过被算作零模的那 `n_zero` 个近零模"，从而填满 `order`：
  ```fortran
  k = n_zero
  n_zero_seen = 0
  do i = 1, n3
     if (.not. linear .and. abs(freq_cm(i)) < zero_mode_tol) then
        n_zero_seen = n_zero_seen + 1
        if (n_zero_seen <= n_zero) cycle      ! 前 n_zero 个已在 order(1:n_zero)
     end if
     if (linear .and. i <= n_zero) cycle
     k = k + 1
     order(k) = i
  end do
  ```
  （extras 因此按升序落在内模列之后，与文档一致；`vib%freq(n_zero+1:n_zero+n_extra)` 保持其 <0.01 cm⁻¹ 的噪声值，不参与热化学。）
* **必须同时补测试**（否则修复不可证伪）：在 `test_landscape_vib.f90` 中构造一个非线性的秩亏 Hessian（例：H–H 伸缩块放在原子 1-2，第三个 H 放在 5 bohr 外且**行列为全零** → n3=9、非线性、rank 1、投影后 6 个零模 + 2 个 extra），断言 `count(abs(vib%freq) > 1.0e-6) == 1`、`maxval(abs(vib%freq))` 等于解析伸缩频率（`autorcm*sqrt(k/mu)`）、`vib%n_vib == 3`、且 `vib%modes` 中不含重复的伸缩列。修复前该断言必然失败（未初始化下标），修好后通过 → 真·可证伪。

### MEDIUM-2（P2）：`--namespace` 下 `hessian` 文件被双重加前缀，写→读闭环断裂

* **位置**：`src/landscape/tasks/vib.f90:220` `call landscape_write_hessian_file(env, get_namespace('hessian'), hess, ok)` → `src/landscape/types/hessian.f90:781-783` 内部**再次** `name = get_namespace(filename)`。
* **现象**：`get_namespace` 非幂等（`src/setparam.f90:587-605`：`name = namespace//'.'//string`）。`--namespace foo --lvib` 写出的是 **`foo.foo.hessian`**；读路径只加一次前缀（`types/hessian.f90:755`，先试 `foo.hessian` 再回退 `hessian`），所以文档承诺的
  `--lvib-hessian file --lvib-hessian-file hessian`（报告 20 §1.4、§3.2）在带 namespace 时**找不到刚写的文件** → `env%error: cannot open Hessian file`。
* **为什么是问题**：(a) 与既有 `--hess` 的文件名不一致（`wrhess`→`open_file` 只加一次前缀，得 `foo.hessian`）；(b) 与套件自己的其它 writer 不一致（`tasks/scan.f90:272,321`、`tasks/vib.f90:251` 都只加一次）；(c) 直接违背报告 20 §1.4 的文字承诺；(d) CLI 测试 `xtb/landscape-vib-cli` 不传 `--namespace`，所以绿。
* **最小修复**：二选一，推荐删除任务层的 `get_namespace`——
  `src/landscape/tasks/vib.f90:220` → `call landscape_write_hessian_file(env, 'hessian', hess, ok)`（命名空间由 `open_hessian_for_write` 单点负责，与读路径对称）。修复后加一条断言即可证伪：CLI 加 `--namespace foo` 后检查 `foo.hessian` 存在且 `foo.foo.hessian` **不**存在。

### MEDIUM-3（P2）：`--lvib`↔`--hess` 差异的归因与机制叙述与证据不符

* **位置**：`docs/xtb-landscape-PLAN.md` §12.11（"差异完全来自前端的投影选择"）、`docs/_landscape-recon/20-...md` §3.3/§5.3（"差异来自前端投影，不是频率链"；"若要与 `--hess` 逐位一致，替代方案是改用 `trproj`"）、`docs/_landscape-recon/21-...md` §5.3(d) 根因 2 与 R5。
* **证据（均为仓库内既有数据/代码）**：
  1. 机制句"`trproj` 的投影算符含梯度项，在驻点退化"**与代码矛盾**：`src/freq/project.f90:252-290`（`gtrprojm`）的投影基只有常量平动向量的和 `r×axis` 转动向量，`trproj`（:151-215）只做质心平移，全流程没有梯度项。
  2. 驻点（GFN2 极小点）处实测 0.0757 cm⁻¹ 可**完全**由"FD Hessian vs 解析 Hessian"解释：`expD_interop.csv` 记 `hessian` 矩阵最大相对差 3.325e-5 → 频率相对 1.7e-5 → 3652×1.7e-5 ≈ **0.06 cm⁻¹**；线性对照 CO2（两条路径**都跳过投影**，δ 只能来自 Hessian 源）实测 0.0036 cm⁻¹，量级一致 → 说明 FD-vs-解析 就是一条真实的独立误差源。
  3. 报告 21 §5.4 自己的数据 `expD/h2o/lvib-read-hess/g98.out`（对 `--hess` 写出的 trproj 投影矩阵再走本套件 Eckart 路径）与 `expD/h2o/hess/g98.out` 第 23 行**逐位相同** → 在极小点上"再投影"≈ 恒等，投影约定在该点的贡献 ≲1e-4 cm⁻¹（远小于 0.0757）。
  4. 由此，(a) "改用 `trproj` 就能与 `--hess` 逐位一致"**不成立**（Hessian 源是 FD 而非解析，CO2 的 0.0036 cm⁻¹ 即证明残余不可消除）；(b) 驻点处的归因应写成"FD-vs-解析为主（~0.06–0.08 cm⁻¹），投影约定 ≲1e-4"；(c) 非驻点处（`h2o_raw`：两路径差 5.21 cm⁻¹，而单测 `water-vs-trproj` 报同一矩阵 Eckart-vs-trproj 为 5.71 cm⁻¹）投影确实贡献显著，但报告 21 §5.3(d) 用"几何依赖"论证投影是主因时，没有排除同量级的 FD-vs-解析 项（该点 `hessian` 相对差 2.358e-3 → ≈4.3 cm⁻¹，同量级）。
* **为什么是问题**：这条归因决定了 M4 的容差选择（报告 21 R2/R5）以及是否值得为"逐位一致"去换投影，现在的叙述会让 M4 走错方向；而机制句是可直接被判为错误的代码事实。
* **最小修复**：做一次**三点分解**（见 §5 R3）后改写三处文字为实测分解；删除或改正"`trproj` 含梯度项"这句；把"改用 `trproj` 可逐位一致"改成"可消除投影项，残余为 FD-vs-解析（极小点 ~0.0036–0.08 cm⁻¹）"。

### LOW-1（P2）：缺少 `--hess` 的"几何未完全优化"告警

* **位置**：`src/landscape/tasks/vib.f90:139-160`（只打印 `gradient norm`）；对照 `src/hessian.F90:161-170`（`norm2(grad) > 0.002` → `!! INCOMPLETELY OPTIMIZED GEOMETRY !!` + `env%warning`）。
* **现象/证据**：`expD/h2o_raw/hess/stdout.txt:388` 有该 WARNING，同几何的 `--lvib` stdout 没有 → 用户在非驻点上跑 `--lvib` 得不到与 `--hess` 同等的提醒。
* **最小修复**：在 `tasks/vib.f90` 的能量/梯度打印处加同阈值（`result%gnorm > 2.0e-3_wp`）的 `env%warning`，措辞与 `--hess` 对齐。

### LOW-2（P2）：热化学参数无校验，非法值静默产出 Inf/NaN

* **位置**：`src/prog/main.F90:2517-2578`（`--lvib-temp/-rotor-cutoff/-imag-cutoff/-freq-scal` 只做 `read`，不校验符号/范围）；`src/landscape/vib/thermo.f90:141-160`（只裁剪 `ntemp` 的数组上界）。
* **现象**：`--lvib-temp 0`（或负值）→ `print_thermo` 中 `beta=1/(kB·T)=Inf` → `log(sqrt(π/beta·2μ))=-Inf` → 热化学表 Inf/NaN 且无任何报错；`--lvib-freq-scal 0` → 全部频率被当负/零处理（`src/main/property.F90:1381-1390` 的 `if (tmp(i) > 0)` 判据）→ `nimag` 与"内模数"变成无意义值、ZPE=0；正的 `--lvib-imag-cutoff` 会让 `n_imag`/`ithr` 语义静默翻转。
* **为什么是问题**：PLAN §7 N12 要求除零/对数前有守卫；这些都是本里程碑新增的 CLI 旋钮。
* **最小修复**：在 `main.F90` 的四个 flag 分支里加显式范围检查（`temp > 0`、`freq_scal > 0`、`imag_cutoff < 0`、`rotor_cutoff ≥ 0`），非法值 `env%error`；或在 `landscape_vib_set_thermo_settings` 里集中校验一次（更省地方）。
* **需运行验证**：`--lvib-temp 0` 是否确实打印非有限值（见 §5 R4）。

### LOW-3（P2）：文档/状态簿记矛盾（逐条可改写）

1. `src/landscape/types/results.f90:50-51` 写 `n_zero` "6, or 5 for a linear molecule (0 for a single atom)"，而实现是单原子 `n_zero = 3`（`modes.f90:132-141`，报告 20 §5.6 也写 3）→ 改注释为 3。
2. `src/landscape/types/hessian.f90:666-676` writer docstring 说"Only the lower triangle is stored"——实际写的是**完整方阵**（`packed(lin(i,j))` 在 j>i 时镜像，与 `wrhess` 相同）；同一 docstring 引用的测试名 `hessian-file-writer-format` 在仓库里不存在（实际是 `hessian-file-roundtrip` 中的字节比对）→ 两处都要改。
3. **状态簿记**：报告 20 §5.1 与 `AGENTS.md` §2 "Not completed — M4..M7" 仍写 PLAN §8.2 实验 #2/#3"未做"，但报告 21 已做完并给出 79 个作业的数据 → 按报告 21 R1 更新 PLAN §9.4 与 AGENTS.md（否则下一轮又会基于过期状态决策）。
4. 新增文件全是 **untracked**（`vib/*.f90`、`tasks/vib.f90`、`test_landscape_vib.f90` 不在 `git diff` 的 stat 里）→ 提交前必须 `git add`，否则 M3 交付物不进版本库。

### INFO-1：`vib_normal_modes` 的索引约定

报告 21 §5.3(c) F5 已记录：该文件**行 = 笛卡尔分量、列（列组）= 模式**（因为 `writeNormalModesTurbomole` 用第一下标做质量反加权却用它打印模式号，`src/io/writer/turbomole.f90:164-188`）。下游读该文件的工具极易按"行=模式"误解 → 建议按 R4 写入 PLAN §12.11。

### INFO-2：与 MAPLE 的常数差异（不要用作紧容差参照）

MAPLE 的 `2721.1383` 是 **Hartree/Å² + amu** 约定（`MAPLE/.../frequency/frequency.py:1044-1059`，其注释给出的推导与常数本身有 ~0.04% 的不自洽），xtb 的 `219474.63067` 是 **Hartree/bohr² + 电子质量** 约定；两者对同一物理频率会系统性差 ~0.04%（3644 cm⁻¹ 处 ~1.5 cm⁻¹）。M4 若与 MAPLE 对拍，只能对拓扑/量级，不能对 0.01 cm⁻¹（PLAN N9 已定此原则，这里补充"常数约定"这一条新来源）。

### INFO-3：全域未收敛扫描的退出码

`tasks/scan.f90:224-236` 只 `env%warning`，`xtb --lscan-max-steps 0` 以**退出码 0** 结束，同时 `TOTAL ENERGY` 打印 NaN。这是 M2 已接受的语义（PLAN R-04：点未收敛是告警不是失败）且已被测试固定，仅记录：若 M7 收口时要统一"结果不可用 ⇒ 非零退出"，这里需要一起改。

## 3. 继承未决项（不是本轮新发现，但必须进 M4 的 gate 清单）

| # | 项 | 状态 |
|---|---|---|
| F1 | `landscape_engine_control%etemp` 是**死字段**：`data` 里读 `mol%at/prop`… 实测复核确认：`engine.f90:503-505` 把 `ctrl%etemp` 传给 `singlepoint`，而 `src/single.f90:37-62` 只把它作为形参收下、**不转发**给 `calc%singlepoint`，真正生效的是 `calc%etemp ← set%etemp`（构造时从全局拷一次）。CLI `--etemp` 有效（报告 21 实验 B 实测），但任何直接设置 `settings%engine%etemp` 的调用者（M4 的 TS/IRC 若照此写）会**静默无效**，同时该字段还参与缓存键（`engine.f90:474`）造成伪缓存失效。 | 报告 21 F1 已记 MEDIUM；**M4 前须修或删**（报告 21 R3） |
| M3-D | PLAN §9.4 验收项 #2/#3/#12：验证轮（报告 21 §2–§4）已完成并给出材料（频率漂移表、etemp-Hessian 差分、q_ROT 逐位一致、CO2/HCN 3N−5）。 | 需按报告 21 R1 更新 PLAN/AGENTS 文本；**建议**采纳报告 21 R2 的 FD 不确定度（默认 0.005/0.3 相对最严格 ≤0.10–0.35 cm⁻¹；`|λ| ≲ 3 cm⁻¹` 时须收紧）到 M4 的鞍点判据里 |

## 4. 测试可证伪性逐条评定（13 条）

| 用例 | 评定 | 依据 |
|---|---|---|
| `mass-weight-roundtrip` | ✅ 可证伪（含显式元素值检查，反指数虽过往返仍会红） | 报告 20 注入 #2/#2b 实测转红 |
| `linear-detection` | ✅（CO2 线性 / 水非线性 / 单原子 / 明显弯曲 CO2 四点） | 判据与 `xtb_axis::is_linear` 同构 |
| `diatomic-analytic-frequency` | ✅ **最高价值**：解析锚点 `f=autorcm·√(k/μ)` 同时钉住质量加权方向、指数与换算因子的**用法**（唯一不依赖内部实现的数值断言） | 注入 #4（线性也要求 6 零模）与 #2b 均转红 |
| `rosenbrock-analytic-hessian` | ✅ 独立解析矩阵 + 特征值闭式 | — |
| `projection-required` | ✅ 真的走了"未投影 ⇒ 必须拒绝"分支 | 注入 #1 转红 |
| `water-modes-gfn2` | ⚠️ 部分自证：`n_zero==6` 来自硬编码 6，`n_vib==3` 是 `n3-n_zero` 恒等式；**真正有内容**的是"分析未失败（投影必须产出 6 个近零模）+ `freq(7)>100` + 单调排序"这三条 | 注入 #1/#3 转红 |
| `water-vs-trproj` | ⚠️ 非循环（参照走既有 `trproj`），但**与实现共享 `massWeightHessian`/`diagHessian`/`autorcm`**，无法发现共同约定的错误（那由双原子解析用例承担）；容差 `0.002·|f|+0.1`≈7.4 cm⁻¹ 仅为实测 5.71 cm⁻¹ 的 ~1.3 倍，裕度偏薄，且该 5.71 的归因见 MEDIUM-3 | 注入 #1/#2 转红 |
| `co2-linear-modes` | ✅ 3N−5 与简并对（`|f(7)−f(6)|<5`）；`n_zero==5` 同属硬编码，但"线性切换 ⇒ 多一个内模"是真的被区分了 | 注入 #4 转红 |
| `hessian-file-roundtrip` | ✅ **外部锚定**：与 `xtb_freq_io::wrhess` 输出**逐字节**比对（`test_landscape_vib.f90:521-534`），不是自证；另有 CRLF 往返 | 注入 #5 转红 |
| `hessian-file-provider` | ✅ 真·文件写→读（跨两次分析）；注意它把已投影矩阵再投影一次（两次 Eckart 幂等，实测 `expD/h2o/lvib-read-hess` 与 `hess` 逐位相同），因此**不能**发现"少投一次/多投一次"之外更细的投影问题 | 注入 #2 转红 |
| `hessian-file-failures` | ✅ 7 类失败路径 + "失败不改动目标矩阵" + 缺文件名的工厂分支，断言粒度稳 | 注入 #7 转红；注入 #6（删头检查）不转红已如实记录 |
| `odlr-unsupported` | ✅ 断言 `fail`、有日志、Hessian 与梯度都保持 0 | — |
| `vib-task-water` | ⚠️ 只查文件存在/非空 + 能量 + 几何不动，**不查内容**，也**不覆盖有虚频的分支**（`distort`/`xtbhess.xyz`、`n_imag>0` 消息）——后者只有报告 20 §3.5 的手工实验覆盖。建议补一条带虚频的用例（拉伸 O–H 即可，成本 1 次 6N+1 FD） | — |
| **缺失** | ❌ **`extra_zero` 分支零覆盖**（HIGH-1 所在），见 §2 | `grep` 79 个作业无该告警 |

## 5. 需运行验证（复核者无 shell）

| # | 命令/实验 | 期望结果（用于证实/证伪本报告） |
|---|---|---|
| R1 | Debug 构建（`-DCMAKE_BUILD_TYPE=Debug` 或 `-DCMAKE_Fortran_FLAGS="-fcheck=all"`）后运行 §2 HIGH-1 的新增用例 | 修复前：未初始化/越界诊断或断言失败；修复后：通过。**这是 HIGH-1 的最终证据** |
| R2 | `OMP_NUM_THREADS=1 XTBPATH=$PWD <build>/xtb h2o.xyz --gfn2 --lvib --namespace foo --norestart && ls foo*.hessian`；再 `... --lvib --lvib-hessian file --lvib-hessian-file hessian --namespace foo` | 期望现在看到 `foo.foo.hessian`、随后报 `cannot open Hessian file`；修复后应为 `foo.hessian` 且读回成功 |
| R3 | **三点分解**（同几何 h2o_opt 与 h2o_raw）：(a) Eckart(FD)（= `--lvib`）、(b) `trproj(FD)`（单测内那条参照路径）、(c) `trproj(解析)`（= `--hess`）；三者两两给 `g98.out` 4 位小数差 | 判定 MEDIUM-3：若 \|a−b\|≪\|a−c\| 则投影归因错，"FD 源为主"成立；若两点上 \|a−b\| 都 ~5.7 而 \|a−c\| 在极小点仅 0.08，则投影项确实几何依赖，且必须找出机制（不可再写"含梯度项"） |
| R4 | `--lvib --lvib-temp 0`、`--lvib --lvib-freq-scal 0`、`--lvib --lvib-imag-cutoff 20` | 观察热化学表是否 Inf/NaN、`imaginary modes`/内模数是否荒谬 → 决定 LOW-2 的修复形态 |
| R5 | 修复后：`OMP_NUM_THREADS=1 ctest --test-dir <build> -R landscape`（应 32/32）、`-R 'Singlepoint\|GFN\|model-hessian\|optimizer\|Argparser\|CAPI'`（12/12）、`ctest -N -R landscape`（=32）、`grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt \| sort \| uniq -d`（空） | 复核注册唯一性；新用例必须进 CMake+meson+`main.f90` 三处 |
| R6 | 可选：H2O···(远距离水) 30 Å（或任何 `file` 源秩亏 Hessian）跑 `--lvib` | 确认 HIGH-1 触发路径在真实输入下可达（跑出该告警即证实） |

## 6. 没有 CRITICAL：检查过的攻击面清单

1. 质量加权方向/指数与质量来源（`src/freq/utils.f90`、`src/mctc/param/atomic_masses.f90`、`src/hessian.F90`）；
2. 频率换算因子数值、单位与 `numhess` 逐字一致性（`autorcm`、`diagHessian` 的 sign-sqrt）；
3. 投影调用参数与线性切换（`projectHessian(…,.true.,.true.)`、`if(.not.linear)`、模数 5/6/3）；
4. 本征值升序、虚频符号、`n_imag` 与 `print_thermo` 的交叉核对（含 `freq_scal≠1` 的差异路径）；
5. `landscape_hessian_file` 格式/转置/对称/维数/单位/命名空间/失败路径（与 `wrhess`/`rdhess` 逐行核对）；
6. 与既有 `--hess` 的复用关系与文件互操作（`main_freq`、`writeNormalModesTurbomole`、`distort` 几何还原）；
7. runtyp 取值唯一性、四处接线、`res` 回写、无新 flag 时行为不变；
8. 数值卫生（`wp`/裸 real/`stop`/模块级变量/BLAS 包装/a.u.）与层边界（§4.2 vs §4.3 的自我矛盾）；
9. 除零/开方/对数守卫；10. 测试注册三处一致与重名风险（32 = 11 单元套件 + 21 CLI，未见重名）；11. M2 遗留 M-1/M-2 语义与覆盖；12. 单原子、线性分子、`file`/`model`/`numerical` 三源的边界分支。

**未发现 CRITICAL 的原因**：上述 12 个面里，只有"额外近零模"这一条未测分支存在真实缺陷（已在 HIGH-1 报告），其余均为正确或已在 MEDIUM/LOW 中如实列出。

## 7. 建议的处置顺序（给父会话）

1. **修 HIGH-1 + 补可证伪用例**（修改 3 行 + 1 测试），跑 R1/R5。
2. **修 MEDIUM-2**（删 `tasks/vib.f90:220` 的多余 `get_namespace`），跑 R2/R5。
3. **跑 R3 三点分解**，据此改写 PLAN §12.11 / 报告 20 §3.3·§5.3 / 报告 21 §5.3(d)·R5 的归因与机制句（含删除"改用 trproj 可逐位一致"）。
4. 收 LOW-1/LOW-2（各 3–8 行）+ LOW-3 的文档与状态簿记（含 PLAN §9.4、AGENTS.md §2、`git add` 新文件）。
5. 把报告 21 F1（`engine%etemp` 死字段）与 R2（FD 不确定度）写进 M4 的 gate 清单。
6. 建议把复核结论写回 `docs/_landscape-recon/22-m3-independent-review.md` 并在 AGENTS.md §2 记录"M3 有条件接受"。

## 8. 复核元数据

* 复核对象工作区：HEAD `b1f4dad` + 未提交改动（`watchdog_diff --stat`：20 文件 +1430/−17，另含本报告/报告 20/21 与 `m3-vib-data/` 的 untracked 文件；`src/landscape/vib/*`、`tasks/vib.f90`、`test/unit/test_landscape_vib.f90` 为新增未跟踪文件）。
* 本复核**未修改任何文件**（只读工具）。