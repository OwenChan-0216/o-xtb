# 11 — M0+M1 第二轮独立复核 + 主控实测校验

> 复核者：`reviewer`（独立上下文、read-only、thinking=high），对象为修复轮后的 `src/landscape/`。
> 本文档 = 复核者结论 + **主控对其每条关键声明的实测校验**（含对复核者静态分析的**部分推翻**）。
> 复核者的完整原文见本次会话的 subagent 输出；本文档保留全部可执行结论。

---

## 1. 复核结论：**接受（accept）**

> 无 CRITICAL、无 P1。11 条 P2 建议在进入 M2 前择要处理。

### 1.1 三条 HIGH 全部关闭（复核者判定）

| 编号 | 判定 | 复核者给出的关键证据 |
|---|---|---|
| **H1** restart 策略 | **已修复** | `engine.f90:459`（E+G 前 `call self%apply_restart`）、`:520-528`（off/pin/warm 三态具名分支）、`:522`（off 首次 `pin_state` 建立参考）、`:523`（`chk%copy(wfn_ref)` 无条件执行）、`:262-274`（`engine_pin_state` 深拷贝）；打印在 `tasks/opt.f90:103`、`tasks/sp.f90:88`、`engine.f90:684`；测试 `test_landscape_optimize_xtb.f90:181-235` 对 off 断言 `energy1 == energy2` 且 `maxval(abs(grad1-grad2)) == 0`（**逐位**） |
| **H2** 对外入口 | **已修复** | `main.F90:918-925` 分派块、`:2048-2082` 三个 flag、`set_module.f90:1064-1065`、`setparam.f90:206`；复核者核对了 `p_run_*` 全集 {1..11,13,14,15,71,100..104} 与 `p_ext_*`，确认 **9 之前未被占用**；`main.F90:575-577` 把 `p_run_lopt` 加入 ANC 的 `fnv` 分支；**无文件单元泄漏**（新增 65 行无 `open`） |
| **H3** 测试可证伪性 | **已修复** | `lbfgs-direction` 用**独立稠密 BFGS 逆 Hessian 递推**（`test_landscape_optimize_math.f90:240-289`，N&W eq.7.17）而非调用被测函数；`diis-coefficients` 断言 `sum(c)=1` **且 `c ≠ 1/3`（非平均）且 `x+d == Σc_i x_i`**；`diis-extrapolation` 用 `history_method` 计数；`fallback-counters` 断言 lbfgs/bfgs/rfo 在强凸二次型与 Rosenbrock 上 `n_fallback == 0` |

### 1.2 M1–M7 / L1–L10 全部判定为已修复

复核者逐条给出 file:line。摘要：

- **M1**：`line_search`→`driver.f90:344-352` + `test_line_search_toggle`；`hess_acc`→`engine.f90:245-250` + `test_hess_acc_wiring`（断言 `hp%sccacc == 0.42`）；`odlr=.true.` 显式 `env%error`；`recalc`→`driver.f90:190-197`；`curvature`/`evals_eps`/`mu_margin`/`max_bisect_it`/`diis_store_every`/`diis_min_snapshots` 全部接线
- **M2**：新增 `settings.f90:434-452 landscape_log_failed(env, nlog_before)`，用于 `rfo.f90:110-116`、`bfgs.f90:120-124`、`diis.f90:186-192`、`coords.f90:459-461`；`rfo-after-warning` 用例在 `--strict` 下注入 warning 后断言 RFO 仍 `fail=.false.`
- **M3**：`grep 'use xtb_type_molecule|xtb_type_calculator|xtb_type_restart|xtb_io_writer|xtb_mctc_filetypes' src/landscape/optimize/` → **0 命中**
- **M4**：`coords.f90:349` 加 `xyz_ref`，`:412-465` Horn 四元数 Kabsch；无参考帧时头注释明写局限；测试含**反证控制断言**（无参考帧时 `> 1e-3`）
- **M5**：`diis.f90:35 regularization_floor = 1e-14`，`:159-163` 注释写明旧 `max(dscale,1)` 的退化原因
- **M6**：`find src/landscape -name '*testpot*'` → 空；已移至 `test/unit/landscape_testpot.f90`
- **M7**：`hessian_update.f90:194-216` 双标志 `sr1_added`/`ms_added` + 两道提前 `return`
- **L1–L10** 全部处理（L4 部分，见 R2-08.3；L5 按设计保留并写明）

### 1.3 「假测试清单」逐条复查：全部转为真断言

复核者确认 `water-gfn2-minimization` 已改为按 `mol%at` 定位 O/H 后比较 r(OH) 与 H–O–H 角
（参照值来自**另一实现** xtb ANC `--opt`）；determinism 探针已改为逐位相等；
`lbfgs-vs-bfgs` 已改为对照解析极小点 + 彼此比较 + `n_steps` 关系 + `n_fallback==0`。

---

## 2. 复核者列出的 11 条 P2（新引入 / 新发现）

| 编号 | 严重度 | 问题 | 主控校验结果 |
|---|---|---|---|
| **R2-01** | P2（用户可见应升 P1） | `--lopt` 结束后 `res` 未回写 → stdout / `xtbout.json` 报的是**初始几何**的能量；`xtbopt.xyz` 是收敛几何 → **同一份输出自相矛盾** | ✅ **实测确认**（见 §3.1） |
| **R2-02** | P2 | CLI 电子结构设置未传入 `landscape_engine_control` | ⚠️ **部分确认、部分推翻**（见 §3.2） |
| **R2-03** | P2（对 M2 最危险） | SCF 不收敛信号被完全丢弃：`engine.f90:476` 只 `n_scf_fail+1`；唯一消费者是 `tasks/sp.f90:106`；`tasks/opt.f90` **完全不看** | ✅ **代码确认**（见 §3.3） |
| **R2-04** | P2 | `engine.f90:520-528` 的 `select case` **无 `case default`** → 非法 `restart_mode` 静默退化为 warm | ✅ **代码确认** |
| **R2-05** | P2 | 上一轮关于 `.trj` NUL 前缀的根因归因（`copyMolecule`）**与代码矛盾**，不应据此上报上游 | ✅ **确认，且推翻我上轮的报告**（见 §3.4） |
| **R2-06** | P2（M4 前置） | RFO 步不做平动/转动投影；6 个刚体模被 `hlow` 抬升后仍参与步长分配 → trust 半径浪费、`dmax` 判据失真 | ✅ **代码确认**（`remove_rotation` 在 src/landscape 内无生产调用点） |
| **R2-07** | P2（对 M2 重要） | `recalc=1` × 数值 Hessian ⇒ RFO 每步 6N+1 次单点；且 provider 绕过 engine 计数 → 打印代价严重低估 | ✅ **代码确认** |
| **R2-08** | P2 | 覆盖缺口 6 项（`write_files` 打开失败、`x_final` 未分配、中途失败、CLI error 分支、`mass_weight_vector` 的 mass≤0、无 `--lopt` vs `--opt` 回归对照） | ✅ 代码确认 |
| **R2-09** | LOW | `bfgs%set_hessian`（**model Hessian 注入钩子**）全树无调用者；`hessian_source='model'` 直接 `env%error` | ✅ **确认 → 构成 D3 口径缺口**（见 §4） |
| **R2-10** | LOW | `xtb --help` 未列出 `--lopt*`（`src/xhelp.f90` 未改） | ✅ 代码确认 |
| **R2-11** | LOW | `engine_set_calculator/set_model/set_xyz` 只 `invalidate()`，不清 `ref_valid`/`wfn_ref`；`engine_hvp` 结束后 `current_xyz` 停留在位移几何 | ✅ 代码确认（当前公共 API 不可达） |
| **R2-12** | LOW | 数值 Hessian provider 不还原 `chk`（`hessian.f90:265-292` 还原了 `mol%xyz` 与 `calc%accuracy`） | ✅ 代码确认 |

---

## 3. 主控对复核者关键声明的实测校验

### 3.1 R2-01 ✅ 确认 —— 真实且严重的用户可见 bug

```bash
$ xtb dt.xyz --gfn2 --sp        | grep "total energy"
         :: total energy              -5.070383095219 Eh    ::     ← 初始几何

$ xtb dt.xyz --gfn2 --lopt --lopt-engine lbfgs --lopt-level normal | grep "total energy"
         :: total energy              -5.070383095219 Eh    ::     ← 仍是初始几何（BUG）

$ head -2 xtbopt.xyz
3
 energy: -5.070544447778 gnorm: 0.000007606257 xtb: 6.7.1       ← 收敛几何（正确）
```

**差异 `1.6e-4 Eh ≈ 0.10 kcal/mol`。** 读取 stdout 或 JSON 的用户会拿到错误能量；
而 `xtbopt.xyz` 是对的 —— **同一份输出自相矛盾**。

代码位置：`main.F90:920-925`（landscape 块）在 `call run_landscape` 之后**没有**回写 `res`。
对照 `main.F90:895-897` 的 ANC 分支有 `res%e_total = etot`。

### 3.2 R2-02 ⚠️ 部分确认、部分推翻 —— 复核者的静态分析在本项上不完全成立

复核者静态推断：`--etemp/--acc/--maxscciter/--verbose` 全部被忽略。
主控实测：

| 命令 | 收敛能量 | 结论 |
|---|---|---|
| `--lopt`（第 1 次） | `-5.070544447778` | — |
| `--lopt`（第 2 次） | `-5.070544447778` | 可复现 |
| `--lopt --etemp 5000` | `-5.070544450318` | **etemp 生效**（Δ=2.5e-9） |
| `--lopt --etemp 100` | `-5.070544447778` | 与默认一致 |
| `--lopt --acc 0.05` | `-5.070544447778` | **acc 未生效**（与默认逐位相同） |
| `--opt` | `-5.070544427069` | — |
| `--opt --acc 0.05` | `-5.070544427082` | acc 在 `--opt` 路径生效（Δ=1.3e-11） |

**结论**：
- **`--acc` 确实被忽略** → 复核者的核心结论成立，须修。
- **`--etemp` 实际生效** → 复核者的 etemp 部分**被实验推翻**（很可能因为 `set%etemp` 被 SCF 内部
  通过全局 `xtb_setparam` 直接读取，而 `acc` 只能经 `singlepoint` 的实参传入）。**不应据此改代码。**
- **`--maxscciter` 不是合法 CLI flag** —— `grep "case ('--maxscciter')"` 无命中；
  主控实测该 flag 会触发 `[WARNING] Please study the warnings concerning your input carefully`
  （即未知选项）。SCF 最大迭代是通过 xcontrol `$scc` 块的 `maxiterations=` 键
  （`set_module.f90:1758 set%maxscciter = idum`）。复核者与被复核的测试探针在这一点上都用错了 flag。

> 这条校验说明：**静态代码分析的结论必须用实验收口**。修复轮据此只改动经实测确认被忽略的 `acc`，
> 并禁止引入不存在的 flag。

### 3.3 R2-03 ✅ 代码确认

```
$ grep -rn "n_scf_fail" src/landscape/
  tasks/sp.f90:106:   result%converged = engine%n_scf_fail == 0
  engine/engine.f90:193:      integer :: n_scf_fail = 0
  engine/engine.f90:476:      self%n_scf_fail = self%n_scf_fail + 1
  engine/engine.f90:683:   write(unit, '(1x,a,i0)') "landscape engine: unconverged SCC    ", self%n_scf_fail
```

`tasks/opt.f90` **完全不消费** `n_scf_fail` → 一次不收敛的 SCC 会返回不可信的 E/g 且 `fail=.false.`，
优化器照常前进一步，退出码仍为 0。**这是对 M2（扫描会在成百上千个几何上重复此行为）最危险的缺口。**

> 注：复核者原先的探针（`--maxscciter 1`）因 flag 不存在而无效，但**代码层面的结论成立**，
> 已由 `grep` 独立确认。

### 3.4 R2-05 ✅ 确认 —— **推翻我上一轮报告中的归因**

```fortran
! src/type/molecule.f90:189-192
interface assignment(=)
   module procedure :: structure_to_molecule
   module procedure :: molecule_to_structure
end interface assignment(=)
```

`assignment(=)` 泛型**只覆盖 `TMolecule ←→ structure_type`**。而 `buffer = mol` 两侧**都是 `TMolecule`**
→ 走**内禀赋值** → `copyMolecule`（`:199-208`，绑定为类型绑定过程 `%copy`）**在该路径上从未被调用**。

补充：`buffer%sym` 无论经内禀赋值还是经 `init(buffer, mol%at, mol%xyz, ...)`，都来自
`TMolecule%allocate` 的 `character(len=80)`，**长度一致** → 「改用 `init` 就消除 NUL」这条因果链
在代码上**无法成立**。真实机制很可能在 `mctc-lib` 的 structure/xyz writer（**本仓库之外**）。

**主控处置**：已把 `10-m0-m1-fix-round-report.md §4.1` **改写为撤回声明**，明确标注「原始归因是错的，
不应据此上报上游」，并把该项转为待最小复现的开放项。**不按原归因上报上游。**

---

## 4. ★ 复核者提出的口径缺口：D3 的 model Hessian 初猜

复核者指出：

> M1 已含 **CG**（167 行，PR+ 与两条重启路径）与**可用的 Hessian provider**（自建 FD，
> 与 `TCalculator%hessian` 逐点一致 <1e-8）；但 **model Hessian 初猜只是 stub**：
> `hessian_source='model'` 会 `env%error`（`hessian.f90:305-322`），`bfgs%set_hessian` 这个注入点
> **全树无调用**（R2-09），RFO/BFGS 起步仍用数值 Hessian（6N 次单点）或单位阵。
> 这与**当前 PLAN §9.2/D4 的口径一致**（已把 model Hessian 本体推迟到 M3），
> 但**与原始 D3「M1 含 model Hessian 初猜」不一致**。请主控认领该口径。

**主控判定：这是真实缺口，必须补齐，不能靠改 PLAN 口径绕过。**

理由：上游（仓库所有者）在决策时选择的 D3 选项预览文本明确写有
`初猜: model_hessian (Lindh/Swart/EEQ)` —— 即 model Hessian 作为**初始 Hessian** 是
其选择的一部分，而非可推迟项。同时这也恰好是 `07-*.md §4.3` 所指出的
「xtb 的 `$hess` 旋钮不可靠 ⇒ 套件必须自建 Hessian 路径」的正面解法：
有了 model Hessian 初猜，RFO 就不必每步依赖 6N 次单点的数值 Hessian，R2-07 的代价问题也随之缓解。

**处置**：已把「实现 `landscape_model_hessian_provider`（复用 `src/model_hessian/*` 的
Lindh/Swart/EEQ），并作为极小化的初始 Hessian 注入 RFO/BFGS」列入本轮修复，
并要求同步更新 PLAN 使 D3 完整落地。

---

## 5. 复核者「需运行验证」清单 → 主控执行状态

| # | 复核者要求 | 主控状态 |
|---|---|---|
| 1 | `ctest -R landscape` | ✅ 已跑：**10/10 目标、63/63 用例全通过**（修复轮后） |
| 2 | `ctest -R 'Singlepoint\|IP\|GFN\|Argparser'` 验证「不带新 flag 无回归」 | ✅ 已跑（定向子集 13/13，见 `10-*.md`；全量因超时限制未跑） |
| 3 | 复现 R2-05 的最小实验 | ⏳ 已列入本轮修复（要求写出 `buffer = mol` vs `init(...)` 的字节比对结果） |
| 4 | meson 侧验证 | ❌ 本机无 meson/ninja，无法验证（PLAN R-16 已自认） |
| 5 | `--lopt --etemp 1000 --acc 0.05` 前后对比 | ✅ **已执行**，结果见 §3.1/§3.2，并据实测修正了复核者的静态结论 |

---

## 6. 处置决定（主控）

复核结论为 **accept**，11 条 P2。主控按「是否阻塞 M2」排序后决定：

| 项 | 处置 | 理由 |
|---|---|---|
| **R2-01** | **修复** | 用户可见的错误能量输出，自相矛盾 |
| **R2-03** | **修复**（M2 前置，最高优先） | 扫描会放大成「看起来收敛的垃圾剖面」 |
| **R2-02** | **修复**（仅 `acc`；**不动 `etemp`**） | 经实测修正后的正确范围 |
| **R2-04** | **修复** | 与套件自身「未识别取值不得静默回退」的设计原则相矛盾 |
| **R2-05** | **修复（更正文档）** | 我自己的报告有误，必须更正；不做未证实的上游指控 |
| **R2-07** | **修复**（`recalc` 默认 1→5 + 代价计数） | M2 内层约束松弛若用 RFO 会不可接受 |
| **R2-08** | **择要修复**（1/2/3/4 项） | 覆盖缺口 |
| **R2-09** | **修复 → 转为 D3 缺口补齐**（见 §4） | 上游 D3 选择的组成部分 |
| **R2-10** | 修复 | 便宜，且影响「M0 已有可用入口」的用户侧结论 |
| **R2-11 / R2-12** | 修复 | 便宜，消除状态残留 |
| **R2-06** | **留给 M4** | 复核者明确判定「不需要先做」；RFO 的平/转投影属 M4（P-RFO）的正确性问题 |

本轮修复完成后需再做一次定向验证；若通过，则 M0+M1 关闭，可以进入 M2（扫描）。
