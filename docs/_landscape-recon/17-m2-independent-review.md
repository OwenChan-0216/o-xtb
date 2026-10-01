## Review 摘要（≤30 行）

**结论：有条件接受（no CRITICAL / no HIGH）。M2 的 F-1（rigid 二面角片段播种）与 F-2（失败点写伪 0.0）修复经代码+测试+注入证据核实为真，但 M2 尚不能无条件宣称完成**：有 1 条 MEDIUM 语义缺陷（任务级 `result%converged`/退出码与自身 docstring 矛盾，未收敛点对自动化不可见）、1 条 MEDIUM 残留风险（rigid 片段仍按"当前热启动几何"逐步重算，原始 bug 的**机制**未消除且无守卫：`moving(j)` 无检查、rigid 点无 drift 判据），以及 PLAN §9.3 验收项 2/4 按字面**不可达成**（relaxed 固有弹簧偏移 + ±180° 回绕使新 drift 列打印 ±360°）。

进入 M3 前必须解决（都很小，合计 ~25 行）：
1. `tasks/scan.f90:183` `result%converged = n_fail == 0` 与 docstring `:67-70` 二选一改一致（建议 `(.and. n_unconverged == 0)`），并补一条驱动"未收敛点"的测试；
2. rigid：片段切不出两侧时 `if (moving(j)) → env%error`，并在 rigid 点做回绕后的 drift 判据（判无效或告警）；
3. PLAN §9.3 验收项 2/4 改写为"rigid：wrapped(reached−target)=0；relaxed：等于已知弹簧偏移"，drift 列改为回绕差。

需运行验证（我无 shell）：跨切割伪成键是否仍可触发合并、未收敛 relaxed 点的退出码/消息、GFN2 2D 失败路径、跨 ±180 负步长扫描、以及改动后 `ctest -R landscape`（OMP_NUM_THREADS=1）。

篇幅冲突说明：任务要求细节写进 `docs/_landscape-recon/17-m2-independent-review.md`，但我只有只读工具，**完整报告附于下方**（请由运行时/父会话落盘）。

---

# M2（scan）独立复核报告（第 17 号）

> 复核对象：M2 scan 实现 + 修复轮（`13-…-implementation.md`、`14-…-validation-experiments.md`、`16-m2-fix-report.md`）
> 方法：只读静态复核（源码/测试/PLAN/原始数据交叉验证 + 逐点解析推导），**未运行任何命令**
> 立场：优先攻击"测试全绿但仍然错误"的地方
> 复核基线：`src/landscape/scan/{relax_scan,scan1d,scan2d}.f90`、`src/landscape/tasks/scan.f90`、`test/unit/test_landscape_scan.f90`、`test/unit/CMakeLists.txt`、`src/prog/main.F90`

---

## 0. 结论

| 项 | 判定 |
|---|---|
| F-1（relax_scan.f90:879-880 播种 `(l,k)→(k,j)`） | **修复正确**，且替掉的那个测试**可证伪**（见 §2） |
| F-2（失败点 NaN / conv=F / log 省帧） | **修复正确**，三条下游路径（表、log、结果）传播一致（唯 §3.1 的语义项未对齐） |
| M2 能否宣称完成 | **暂不能**。3 条 MEDIUM 需先"修或书面接受"（§3.1 / §3.2 / §3.3），4 条 LOW（§4）可选 |
| 进入 M3 前必须解决 | §3.1（`result%converged` 语义 + 测试）、§3.2（rigid 守卫+drift 判据）、§3.3（PLAN §9.3 验收项改写） |
| CRITICAL / HIGH | 0 条（已检查的攻击面见 §6） |

---

## 1. 判定方法（为什么可信）

对二面角刚体旋转做了独立解析推导而非只读注释：设 j→k 轴单位向量为 `a`，`landscape_scan_rigid_geometry` 取 `pivot = x_j`、`axis = x_k − x_j`，则 `x_k = pivot + axis` 落在旋转轴上、不动；片段只切 `k→j` 一条边，故旋转作用于 `{k 及其全部取代基}`（含 `l`）。以 `xtb_basic_geo::valijkl` 的约定（`ra=x_j−x_i, rb=x_k−x_j, rc=x_l−x_k`，法向夹角 + `test<0` 定号）手算 anti 构型（Cl3–C1–C2–Cl4）与 +β 旋转：连续角满足 `valijkl = φ_rh − 2π`，故 `α = target − value`、绕 +α 旋转使到达值**增加 α** ⇒ 符号与 `landscape_scan_coord_value` 一致。这与 `test_landscape_scan.f90:500-560`（正反两支逐点 reached==target ≤1e−12、近侧逐位不动）及 `16`§4.2 的 21 点 GFN2 实测（drift < 5e−9°）三者独立吻合。

---

## 2. 正确项（含证据）

| # | 项 | 证据 |
|---|---|---|
| C1 | 二面角播种 `(k,j)` 语义正确；`l` 的取代基一起转（真刚体） | `relax_scan.f90:876-880`；`test_landscape_scan.f90:441-479` 断言"近侧逐位不动 + 远侧等于独立 Rodrigues 旋转 + 片段内所有内距守恒" |
| C2 | 被替掉的"编码 bug 的测试"确实换成了可证伪形式 | 旧 fixture（H–O–O–H）在 `{l}` 语义下恰好正确；新 DCE fixture 的掩码断言 `:425`（`count(moving)==4`）在旧播种 `(l,k)` 下**必然立刻失败**（旧掩码 = `{Cl4}`，大小 1≠4），无需运行即可判定；`16`§1.4 的注入实验亦显示两条用例转红 |
| C3 | distance / angle 分支**无同类错误** | `:838-839` 两侧片段各平移 ∓½α（沿 i→j 单位矢量）⇒ 距离恰增 α，且两侧各自刚性；`:848-857` 切 `i–j`、`j` 为枢轴、轴 = `(x_i−x_j)×(x_k−x_j)`、`α=value−target`，绕该轴 +α 使 θ 减 α ⇒ 到达 target。与验证轮结论（§8 末"distance 与 angle 不受此 bug 影响"）一致 |
| C4 | 去偏项扣对了 | `:621-632`：`point%energy` = base（电子能量）在 `xout` 处新算；`point%bias` 用**同一个 `model%fix`** 在同一几何上由 `constrain_pot` 算 ⇒ `total = E_phys + E_bias`，即 `scan_driver.f90:98` 的 `etot−efix`。两侧剖面实测吻合 1.3e−5…6.7e−7 Eh（`14`§3）从数值上排除了"扣错项" |
| C5 | 残差定义与度量正确（角度/二面角用**弧度**） | `coordinate_residual` = `\|g·g_q\|/\|g_q\|²`（`dE/dq` 的最小位移投影），`g = g_phys + g_bias`（**含偏置**，`:633`）；`landscape_scan_coord_gradient` 通过对 `constrain_pot` 的定点构造使 `dE/dq ≡ 1`：距离 `expo=1,target=0`（`constrain_pot.f90:196-203`）、角 `expo=2,target=θ−0.5`（`:244-258`，单位 rad）、二面角周期式取 `φ0=φ−π/2` ⇒ `sin(dphi1)=1`（`:296-312`）。逐条手算无误，单位与偏置一致（Eh/bohr 或 Eh/rad），无度/弧度混用 |
| C6 | "180° 附近残差是否假性为 0"：**否** | `dphidr` 的 1/sinφ 放大同时出现在分子与分母（`|g·g_q|/\|g_q\|²`），比值不受影响；`dphidr` 只在 `\|n_a\|\|n_b\|sinφ < 1e−14` 时回零（`basic_geo.f90:127-135`），即仅在距 0/π 1e−14 rad 内——实际不可达。真正的病理是 R9-b 的 `valijkl` acos 病态（值误差 4e−13 rad），不是残差归零 |
| C7 | 失败（NaN）在三条下游路径传播一致 | 引擎先探 `landscape_log_failed` 再读 `cache_results%converged`（`engine.f90:499-510`），并有非有限兜底（`:520-526`）；`profile/grid` 的 `energy_valid` 门（`scan1d.f90:318-325`、`scan2d.f90:266-274`）绝不写 0.0；`xtbscan.log` 只写有值帧 + `status='replace'`（`tasks/scan.f90:246-250,255-275,291-295`）；"无任何有效点时 `result%energy=NaN` 且不覆盖输入几何"（`:127-131,144-146,180`）。Hessian 路径（`scan_bias_model_hessian`）只对 base 的 Hessian 加偏置的解析 FD，与"丢弃评估"无关，未被污染 |
| C8 | `warm_start` 只热启动几何，波函数策略归 `restart_mode` | `scan1d.f90:258,271`、`scan2d.f90:258` 只搬 `xout`；策略在 `engine.f90:573-586` 单点统一施加（默认 `off`，`settings.f90:108`），一次任务内不混 warm/cold，符合 AGENTS §6.2 |
| C9 | 从"失败点"热启动是安全的 | `landscape_optimize_model` 的所有返回路径都经 `finish()`（`optimize/driver.f90:503 x_final = x`）；早退路径（`:132-141`）时 `x` 仍是**该点的起点几何**，不是未初始化缓冲区；F-2 场景下 `xout` 是构造好/松弛好的几何。故不会把全零帧当起点（旧 bug 的全零帧来自 `store_point` 不写 xyz，已被 `energy_valid` 门覆盖） |
| C10 | CLI/状态：`12` 不冲突、回写 `res`、无 flag 时行为不变 | `setparam.f90:209 p_run_lscan=12` 与 1–15/71/100–104 无重复，`set_module.f90:1067` 映射；`main.F90:950-960` 回写 `res%e_total`/`res%gnorm` 并 `env%checkpoint`；`--lscan*` 全部走新 `case`，`scan_step_given` 在 `main.F90:1432-1433` 显式初始化，单位换算在全 flag 解析后做（`:2432-2439`，Å→bohr / 度→rad），故不带 `--lscan` 时既有路径零改动 |
| C11 | 数值卫生未回退 | `scan/**` 无裸 `real`、无 `stop/error stop`、无 module 级可变量（只有 `parameter` 与类型分量默认值），`implicit none(type, external)` 齐备；除零守卫 `geom_guard`（`:94,830,850,865`、`coordinate_residual:766-771`）。scan 层私有类型只出现在 `tasks/scan.f90`（`TMolecule/TRestart/TCalculator`） |

---

## 3. 需在"宣称 M2 完成"前处置的发现

### 3.1 MEDIUM — `result%converged` / 退出码与 docstring 矛盾：未收敛的 scan 点对自动化不可见

* 位置：`src/landscape/tasks/scan.f90:183`（`result%converged = n_fail == 0`）对 `:67-70`（"`result%converged` whether every scan point converged. A failed point (**unconverged inner relaxation** or a failed single point) is reported as an error, exactly like an unconverged minimisation in `xtb_landscape_tasks_opt`"）与 `:215-223`（只 `env%warning` + message "scan completed with unconverged points"）互相矛盾；同一文件里两段注释给出相反承诺。
* 现象（可从代码确定，不需运行）：`n_fail` 只统计"无能量"的硬失败（`store_point`/`solve_grid_point` 的 `point_fail`）；某点内层松弛撞 `max_steps`/stagnate 时（`optimize/driver.f90:376-381`）`result%converged=.false.` → 经 `relax_scan.f90:640` 落到 `point%converged`，只进 `n_unconverged`。于是该点的能量**有效**、进入 profile 与 `xtbscan.log`，而任务级 `result%converged=.true.`、退出码 0、消息 "scan completed"。
* 为什么是问题：与 `tasks/opt.f90:165-172`（`if (.not. result%converged) call env%error(...)` ⇒ 非零退出）的"对标"承诺不成立；任何只看退出码/`lres%converged` 的自动化（含 ctest 与后续 M3..M7 的任务结果复用）无法区分"全收敛"与"部分未收敛"，而 PLAN §6.2 的 R-04 缓解 (c) 要求非收敛可见。
* 测试盲区（"全绿但没测到"）：
  - `test_landscape_scan.f90:1304` 的 `check(error, result%converged)` 在当前定义下**不可能失败**（`n_fail==0` 已被上面 `frames==2*3+1` 的断言蕴含）；
  - `test/unit/CMakeLists.txt:456` 用 `MATCHES "landscape task terminated: scan completed"`，而该串是 "…scan completed **with unconverged points**" 的子串 ⇒ CLI 测试对未收敛路径同样全绿；
  - 无任何测试驱动 `n_unconverged>0` 分支。
* 最小修复（择一，建议 a）：(a) `result%converged = (n_fail == 0) .and. (n_unconverged == 0)`，并把 `:215` 分支改为 error（或保留 warning 但把 docstring `:67-70` 改成"是否每个点都产出了能量"）；(b) 保留现行为，则必须改 docstring 并补一条用 `set%max_steps=1` 驱动的单元用例断言 message/warning，同时把 CMake 的 MATCHES 串改成不可被子串命中的形式。

### 3.2 MEDIUM — rigid 片段掩码仍按"当前（热启动）几何"逐点重算：原始 bug 的机制残留且无守卫、无判据

* 位置/机制：`relax_scan.f90:896-928` 的 BFS 邻接表是**距离截断图**（`bond_factor*(covalent_radius_2009(i)+covalent_radius_2009(j))`，`bond_factor=1.2`，`:87`），在**传入的几何**上现算；调用点 `:838,839,856,879` 传的是工作几何，而 `scan1d.f90:258,271` / `scan2d.f90:258` 把上一点几何回灌为下一点起点 ⇒ 掩码逐点随扫描演化。
* 判断（回答问题 1）：
  - 对**正常成键二面角**，新播种是正确的（C1/C2）；掩码 = 含 `k` 的远侧片段，`l` 及其同侧取代基为刚体。
  - 但"连通性桥接"这一**机制**没有消除，只是把触发条件从"人为的 `{l}` 片段"改回"真实的跨切割近键"：BFS 只封锁 `k→j` 一条边，若远侧任一原子与近侧任一原子距离落到阈值内，BFS 会经该桥吞掉近侧（进而 `moving(j)=.true.`），两侧同转 ⇒ **被扫坐标再次冻结**，且 rigid 点无条件 `point%converged=.true.`（`:739`）、`n_fail=0` ⇒ 退出码 0，唯一线索是新加的 drift 列。
  - 阈值（`src/mctc/param/covalent_radii.f90:27-30`，r_cov：H 0.32、C 0.75、Cl 1.02）意味着需要 C···H < 1.284 Å、Cl···H < 1.608 Å、Cl···Cl < 2.448 Å——远在 vdW 壁**以内**，所以正常分子上很难触发（DCE 实测最紧跨对为阈值的 0.526×，且修正后远侧整体刚性旋转使其内距守恒）。**残留风险确实低，但它是静默的**：`16`§6 的 R9-a 已把它列为"低/留待 M4"，而验证轮 `14`§8 的建议 2/3（掩码只在参考几何上算一次；rigid 点由"参考几何 + 累计旋转角"构造）**未实现**。
  - 环体系与"非成键的二面角（`l` 不在 k 侧 / `i` 落在移动侧）"同属该类：`relax_scan.f90:806-809` 的注释说"环上刚性扫描 only meaningful for the scanned coordinate itself"过于宽容——整分子绕 j–k 轴旋转时 `i` 与 `l` 同角转动，二面角**一点都不变**（等于冻结），并非"仅对被扫坐标有意义"。
* 最小修复（约 10 行，可显著降级该风险而不改语义）：
  1. 掩码算出后立刻拒绝"未切开"：`if (moving(j))`（二面角；distance/angle 用 `if (moving(blocked))`）⇒ `env%error("the cut j-k does not separate the two sides")`。它能同时捕获环、非成键切割与伪桥接三种情形（伪桥接必然经近侧连通图到达 `j`）。
  2. rigid 点收尾处做**回绕后**的到达值判据：`if (abs(wrapped(reached − target)) > tol) → 该点判无效（或至少 env%warning + 计数）`，把 §9.3 验收项 4 从"设计承诺"变成"运行期检查"。结构化修法（掩码固定于参考几何）可随 R9-a 推迟到 M4，但注释应改为"掩码逐点重算"的**事实**描述。

### 3.3 MEDIUM（文档/可达成性）— PLAN §9.3 验收项 2/4 按字面不可达成；±180° 回绕使 drift 列打印 ±360

* 位置：`docs/xtb-landscape-PLAN.md:1115-1118`。项 2"每个点的 `reached` 必须等于目标值"、项 4"rigid … 逐点 `reached == value`"。
* 反例（两条都在项目自己的文档里）：(a) relaxed 点按设计停在有限弹簧的偏移处——PLAN §5.3.5 自己写"fc=0.5 时 0.82°、fc=0.05 时 6.84°"；`16`§3 声称该项"改写为可达到的形式"，实际只加了 `value/reached/drift` 三列，判据本身没改。(b) `valijkl` 值域 (−π, π]，`scan1d.f90:431` 打印 `reached − value` 未回绕 ⇒ 目标越过 ±π 时 drift ≈ ±360°（`14`§5.4 的 F3-low：目标 −203.99° 对应到达 +156.01°）；几何本身是对的（旋转角不取模不影响刚体构造），但表与验收都会误读。
* 为什么是问题：验收判据是"宣称 M2 完成"的依据；改写后的项 2 与 §5.3.5 自相矛盾，项 4 会被普通扫描（跨 ±180）无故判失败。修 F3-low 只改"打印哪一列"，没改"判据是否可达"。
* 最小修复：项 2 改为"rigid：`wrapped(reached−target)=0`；relaxed：`|reached−target|` = 已知弹簧偏移（并在表中作为一列报告）"；drift 列改打印回绕差（或把 `alpha` 归约到 (−π,π] 并让 `value` 同步回绕）。

---

## 4. LOW（报告项，不阻塞）

| # | 位置 | 现象 / 为什么是问题 | 最小修复 |
|---|---|---|---|
| L1 | `scan1d.f90:357`（`n_compared` 无条件自增） | 全 NaN 剖面时表打印 "points compared 10 / max \|E_fwd−E_rev\| 0.0 Eh"，而**没有任何点被比较**（`max_delta` 因 NaN 比较恒假而保持 0）——与 `:78-84` 类型注释"NaN 点不参与比较"不符，也违背 F-1/F-2 轮确立的"表不撒谎"。退出码 1 使其非静默 | 自增前 `if (.not. energy_valid(ifwd) .or. .not. energy_valid(irev)) cycle`；无合格配对时打印 NaN/"not available" |
| L2 | `relax_scan.f90:730-736` | rigid 失败分支在"base 返回非有限能量且 `fail=.false.`"时**未设 `fail=.true.`**（对照 relaxed 分支 `:648` 设了）⇒ `point_fail=false`、`profile%n_fail` 不计、无诊断、退出码 0（NaN 表行仍在，log 省帧）。生产路径下引擎的有限性检查（`engine.f90:520-526`）会先置 `fail`，故当前不可达；但 `landscape_energy_model` 是文档化的可替换抽象（M4/M5 会插新模型），属"埋雷" | 在 `:734` 后加 `fail = .true.`（一行） |
| L3 | `main.F90:959` + `src/main/property.F90:51` | `res%gnorm = lres%gnorm` 把**坐标残差**（距离 Eh/bohr、角/二面角 **Eh/rad**）写进固定标签为 "GRADIENT NORM … Eh/α" 的行；`--lscan` 时该行必然把 Eh/rad 当 Eh/bohr 展示（AGENTS 硬约束要求单位标注正确）。表头 `scan1d.f90:424-427` 的 "residual" 列同样无单位 | scan 时不写 `res%gnorm`（或写 0 并在表内说明），至少在表头标出 Eh/bohr vs Eh/rad |
| L4 | `scan/relax_scan.f90:57-60` vs PLAN §4.2 规则 1 / §4.3 表 | `scan/**` 直接 `use xtb_type_environment`（§4.3 以"全层"消解）、`xtb_type_setvar::constr_setvar`、`xtb_basic_geo::bangl/valijkl`（**两者都不在 §4.3 边界表**）。`13`§5 却称"由 PLAN §4.3 明确列为 scan/* 的边界模块"——文档与 PLAN 不一致。复用 `valijkl/bangl` 本身是**正确**选择（自行实现坐标约定会与 `constrain_pot` 脱钩） | 在 §4.3 表补两行（`xtb_type_setvar::constr_setvar` → `scan/*`；`xtb_basic_geo::bangl/valijkl` → `scan/*`），或改写规则 1；顺带修 `13`:365 的表述 |
| L5 | `relax_scan.f90:127-129`、`scan1d.f90:320`、`scan2d.f90:279` | `point%total`/`bias` 与 `profile%total`/`grid%total` 对无能量点仍是 0.0（当前任务层未读取，属"写而不读"的死数据），重新引入了 F-2 明确禁止的"0.0 代表缺失"模式；无效点的 `n_steps` 也保持 0 | 无效点写 NaN / 或删除该字段 |
| L6 | `settings.f90:143`（继承默认 `hessian_source='numerical'`） | `--lscan-method rfo` 无对应 CLI 开关，每个扫描点会付 6N 次单点建数值 Hessian（`--lopt-hessian` 只作用于 `lset`）；非正确性缺陷，但是 M3 前值得定的策略（PLAN §5.3.5 未列该字段） | 在 PLAN/文档写明，或 M3 一并加 `--lscan-hessian` |

---

## 5. 测试可证伪性逐条审查（攻击面 5）

| 用例 | 判定 |
|---|---|
| `rigid-dihedral-fragment`（新） | **可证伪**：改回 `(l,k)` ⇒ `:425` 掩码大小断言立刻失败（1≠4）；改错旋转方向/枢轴 ⇒ `:449` reached≠target 或 `:458-471` 偏离独立 Rodrigues 旋转。**注意**它与被测模块共享"约定"（`reference_dihedral` 是 `valijkl` 的重写，`:1472-1505`），只能证明内部自洽——但 `:421` 显式断言两者在 fixture 上一致，故约定错位也会被抓 |
| `rigid-dihedral-scan`（新） | **可证伪**：逐点 `reached==target`:534、近侧逐位不动:562、反向分支几何一致:590、滞回 ≤1e−14:583、以及"剖面非常数"的自检 span>1e−3:576（防止退化表面骗过）。注入实验（`16`§1.4）已实测转红 |
| `scan-missing-energy`（新） | **可证伪**：`scan_fragile_model` 故意在失败时留下 `energy=0.0`（`:1604-1617`），断言"有效点 ≠0.0 / 无效点必为 NaN / n_fail==n_missing / 2D 极小点来自有值点" ⇒ 恢复旧行为（照抄 0.0、conv=T）必红 |
| `scan-task-missing-energy/-no-energy`（新） | **可证伪**：真实 GFN2 SCF 失败 + 日志无 `energy: 0.000000000000` + 帧数 < 请求点数 + 全失败时 `result%energy` 为 NaN 且几何保留 |
| `scan-task-gfn2`（旧，:1304） | **弱**：`check(result%converged)` 在当前定义下恒真（见 §3.1）；`result%converged`/`n_unconverged` 语义**无任何测试覆盖** |
| CLI `xtb/landscape-scan-cli`（改名后，CMake:456） | **弱**：MATCHES 子串命中"…scan completed with unconverged points" ⇒ 无法区分收敛/未收敛（同 §3.1） |
| `scan-2d-bookkeeping` / `scan-hysteresis-report` / `relaxed-scan-residual` | 独立重算（profile 数组 vs 报告字段、闭式约束极小、残差重投影）——可证伪 |
| 覆盖缺口 | ① rigid 掩码"跨切割合并/环/非成键"无用例（→§3.2 的守卫应带一条）；② rigid 点的 drift 判据无用例；③ `result%converged` 的未收敛分支无用例；④ `moving(j)` 之类的退化态无用例 |

---

## 6. 特殊问题的直接回答（攻击面清单）

1. **rigid 二面角修复正确性**：正确（C1/C2，解析 + 测试 + 实测三重）。分支点原子（k 上有第三个取代基）→ 新播种把整个 k 侧作为刚体，正确且正是旧播种失效之处；环 → 切不开两侧，整分子旋转、二面角**冻结**（`:806-809` 的措辞过宽）；`l` 与 `i` 同侧（几何上 syn）→ 无影响（掩码按连通性而非几何），但若 `l` 与 `k` 实际不成键、或 `i` 被吞入移动侧，则冻结（§3.2）。**BFS 是距离截断图（共价半径×1.2）不是成键图**，且逐点重算 ⇒ 原理上仍可能合并，但需要真实跨切割近键（阈值远在 vdW 内），实测 DCE 余量 0.526×；风险低但**静默**（§3.2 建议加守卫）。
2. **其他坐标类型**：distance 用 `(i,j)`+`(j,i)`、angle 用 `(i,j)`（切 i–j、转 i 侧），**均正确**；angle 不需要"第三个原子在移动侧"的条件（旋转 i 侧即等价）。
3. **去偏与残差**：扣项正确（C4）；度量正确用**弧度**且与偏置一致（C5）；180° 附近残差**不**假性为 0（C6），但存在 R9-b 的值病态。
4. **失败点处理**：表/log/几何/结果四处传播一致（C7）；`converged` 在 1D/2D 内部一致（逐点 `point%converged`），但**任务级**与 docstring 不一致（§3.1），且 rigid 的非有限分支漏设 `fail`（L2）。
5. **测试可证伪性**：见 §5，被替换的测试确实换成了能检出的形式；两处旧的/新的弱断言已指出。
6. **warm_start vs restart**：只热启动几何，波函数策略唯一由 `restart_mode` 控制（C8）；默认 `off` 比 PLAN §6.2(a) 建议的 `pin` 更严格（同为确定性的），PLAN 文本应更新。
7. **CLI 与状态**：`p_run_lscan=12` 无冲突、`--lscan` 回写 `res`、无 flag 时零行为变化（C10）；2D 蛇形热启动**会**把失败点的几何当地起点，但该几何是"上次内层接受的几何或本点起点"而非垃圾（C9），故不是缺陷，只是策略（如需严格可 `if (point_fail) cycle` 跳过回灌）。唯一确定问题是 gnorm 单位标签（L3）。
8. **数值卫生与层边界**：卫生未回退（C11）；边界问题为文档级（L4）。

---

## 7. 需运行验证（我无 shell；请父会话执行并回填）

1. **跨切割伪成键是否仍可触发合并**（§3.2 的核心不确定性）：建议先加调试输出或直接做单元实验——构造一个 k 侧原子与 i 侧原子距离 = 1.1× 阈值的几何（例如把 DCE 的 Cl4 沿轴向压近 H5），断言 `moving(j) == .false.`；若守卫缺失则该断言应失败（说明风险真实）。运行侧等价探针：`OMP_NUM_THREADS=1 xtb <syn-clash 构型> --gfn2 --lscan --lscan-mode rigid --lscan-coord dihedral --lscan-atoms <i,j,k,l> --lscan-step 15 --lscan-nstep 24`，检查 drift 列是否出现台阶。
2. **未收敛 relaxed 点的对外行为**（把 §3.1 从"读代码"变成"实测"）：`OMP_NUM_THREADS=1 xtb water.xyz --gfn2 --lscan --lscan-coord angle --lscan-atoms 2,1,3 --lscan-step 3 --lscan-nstep 2 --lscan-method sd --lscan-level vtight --namespace unconv`，核对退出码、`landscape task terminated: …` 消息、以及该点是否进 `xtbscan.log`。
3. **GFN2 的 2D 失败路径**（`16`R10-d 自认只有解析模型覆盖）：构造一个第二坐标越界的 2D 网格，核对表内 NaN / 极小点来源 / log 帧数。
4. **跨 ±180 的负步长扫描**（§3.3 的 UX 项）：`--lscan-coord dihedral --lscan-step -12 --lscan-nstep 20`，确认打印 drift ≈ ±360 而几何仍正确（用到达值与几何反算对照）。
5. **回归**：改动后 `OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape`（`16`§4 记录 25/25）与 `-R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'`（12/12）；`ctest -N -R landscape` 核对测试名无撞名（撞名静默丢测是本轮已发现的坑）。

---

## 8. 结论

M2 的**两处实质修复都是真的**：F-1 的播种修正有解析推导 + 独立参考几何 + 注入实验三重支撑，F-2 的"缺失值"不变式在表、log、结果三条路径上一致，且失败/未收敛语义在 1D/2D/双向内部是统一的。没有 CRITICAL：所有几何/数值核心（三个坐标分支的刚体语义、去偏项、残差度量、单位、除零守卫）经手算与实测一致。

但"测试全绿"尚未覆盖三处：(1) 任务级 `result%converged`/退出码与自身 docstring 相反（未收敛点只进 warning，无测试、CLI 断言还被子串命中）；(2) rigid 片段仍逐点重算在演化几何上——原始 bug 的机制残留、退化态无守卫、无 drift 判据，只有 drift 列作为唯一线索；(3) PLAN §9.3 验收项 2/4 按字面不可达成（弹簧偏移 + ±180 回绕）。三者都可在 ~25 行内解决，建议**"有条件接受：完成上述 3 条后即可宣称 M2 完成并进入 M3"**；若仓库主愿意把"未收敛点不算失败"作为**有意设计**，则至少必须改 docstring、补该分支的测试，并修 §3.3 的验收文本——否则 M2 的验收结论本身没有可执行判据。