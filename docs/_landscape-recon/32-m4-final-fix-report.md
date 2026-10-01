# 32 — M4 最终修复报告（复核 31 的 3 条 MEDIUM + 几何依赖性 + §5 运行清单）

> 修复者：worker 子会话。对象：`31-m4-review-round2.md`（结论「接受」，但列出 3 条 MEDIUM
> 与「M5 前处理」的要求）、以及父会话实测发现的**功能缺口**：
> 用线性 HCN 极小点跑 `--lts` 时 prfo/bprfo **exit 1、0 虚频**，而 dimer 能成功。
> 纪律：所有 xtb/ctest 调用均 `OMP_NUM_THREADS=1`；只跑 `-R landscape` 与回归子集；
> 不提交 git；绝不跑全量 ctest。
> 数据：`docs/_landscape-recon/m4-final-fix-data/`（acceptance / escape / debug / m3 / med2 /
> injections / injections 共 6 个子目录，见 §9）。

---

## 0. 结论

| 项 | 状态 | 一句话 |
|---|---|---|
| **任务 1** MEDIUM-1（极小点起步选到刚体零模） | **修复（选项 a）** | 选模改为「最低**内模**」+ 新增**逃逸行走**；GFN2 HCN 从线性极小点 prfo 5 步 / bprfo 7 步到达与弯曲猜测**同一个**鞍点，exit 0、1 虚频 |
| **任务 2** MEDIUM-3（`result%etemp` 无断言） | **修复** | `xtb/landscape-ts-etemp` 增加 stdout `etemp:` 与 `xtbts.log` 冻结温度两条断言；删掉赋值即红（实测） |
| **任务 3** MEDIUM-2（`λ_n` 对分不验证残差） | **测量 + 加固** | 真实运行中**从不发生**（19 次求解 `residual(hi) = −5e-4 … −2e-2`，根的残差 ≤5e-16）；补上端残差校验 + 退化回退 + 合成谱单测 |
| **任务 4** 几何依赖性写进文档 | **完成** | PLAN §9.5 + 报告 26/27/28/30 各补一节，含两起点实测对照表 |
| **任务 5** 复核 31 §5 运行清单 | **逐条执行** | 8 项全部跑完；**两条复核预测被实测证伪**（§5.2(b)、§5.2(e)），已在 §5 记录 |
| **M4 已验收数字** | **逐位不变** | Müller-Brown prfo vs bprfo RMSD **6.3022e-06**（原 6.3022e-06）、dimer vs prfo **7.7397e-05**（原 7.74e-05）、`dimer Hessian requests 0`、弯曲起点三方法 1 虚频 exit 0 且能量逐位相同 |
| **M3 线性分子回归** | **不变** | CO₂/HCN 均 3N−5 = 4 内模 + 5 零模；`--lvib` vs `--hess` max|Δf| = **0.0036 / 0.0023 cm⁻¹**（≤0.004）；`TR` 行两条路径逐位相同 |
| 构建与测试 | **干净** | `ctest -R landscape` **51/51**（原 49 + 新增 2 个 CLI 测试）、`ctest -N -R landscape` = 51、`add_test` 无重名、回归子集 **12/12** |
| 可证伪注入 | **9 项全部变红并还原** | §5.2 五条 + 本轮新增四条（逃逸关掉、选模回退、残差校验删掉、`result%etemp` 删掉） |

计数：本**轮**新发现 0 CRITICAL / 0 HIGH / 0 MEDIUM；复核 31 的 3 条 MEDIUM 全部闭合。
两条复核预测（`project_hessian_rigid` 注入、线性零模分支注入）被实测证伪，见 §5.2。

---

## 1. 任务 1：从极小点起步的 P-RFO / B-P-RFO（MEDIUM-1）

### 1.1 复现与量化（修复前）

固定二进制 = 本轮改动前的 M4 工作树；输入 = 线性 HCN 极小点
`H(−1.0,0,0) Å, C(0,0,0), N(1.156,0,0)`（父会话给的对照）。

| 方法 | 退出码 | 选中模式（打印） | 收敛步数 | 终点能量 /Eh | 虚频数 |
|---|---|---|---|---|---|
| prfo | **1** | `index 1, eigenvalue −0.00000000`（刚体零模） | 3 | −5.504066223602（= 极小点） | **0** |
| bprfo | **1** | `index 1` → `index 3`，两者 `eigenvalue ±0.00000000` | 3 | −5.504066223602（= 极小点） | **0** |
| dimer | **0** | `index 0, eigenvalue −0.19706487`（沿轴曲率） | 29（`energy calls: 337`） | −5.387373461989（= 鞍点） | **1** |

**机制确认（刚体子空间重叠）**：本轮给驱动加了诊断行
`selected mode, rigid body overlap:`（`prfo.f90:report_initial_mode_diagnostics`，打印
`‖R v‖`，`R = Σ_a b_a b_a^T` 为刚体投影算子；1 = 纯刚体、0 = 纯内模）。用**注入 B**
（把选模回退成旧的 `index = 1`）复现旧行为，输出为：

```
   transition mode: index 1, eigenvalue      -0.00000000 Eh/bohr^2
   selected mode, rigid body overlap:     1.000000        <-- 选中的就是刚体零模
   escape from a minimum: 15 push(es), total displacement   3.000000 bohr, lowest mode  -7.753069E-17 Eh/bohr^2
   selected mode, rigid body overlap:     1.000000
   steps:          2
   final energy:        -5.504066223545 Eh
   saddle confirmation - imaginary modes: 0
   confirmation: minimum (0 imaginary modes) - not a transition state
```

即：升序谱的前 5 个模是投影后 `P H P` 的刚体零模（~1e-17，符号由舍入决定），
旧的 `index = 1` 恰好选中它们，而步的刚体分量又被 `project_rigid` 抹掉 → 搜索退化为极小化。
（证据文件：`injections/expB-selection-defect-cli.txt`；16 行 `index 1 … -0.00000000`。）

### 1.2 修复（选项 a）：最低**内模** + 逃逸行走

**（i）选模**（`saddle/eigenfollow.f90`）：`nneg` 只用 `evals < −landscape_curvature_noise_tol`
的**显著**负本征值计数；`target > nneg` 时不再恒定 `index = 1`，而是调用新的纯函数
`landscape_lowest_internal_mode`（第一个 `evals(i) > tol` 的模；谱全在带宽内时退回最大 |λ|）。
修复后同一极小点：

```
   transition mode: index 6, eigenvalue       0.08238897 Eh/bohr^2   (线性 HCN 最低内模 = 弯曲)
   selected mode, rigid body overlap:     0.000000                 <-- 内模
```

**（ii）仅修选模不够（实测）**：关闭逃逸后 prfo 从同一起点 **3 步回到极小点**（0 虚频、exit 1）：
在（近）驻点极小点上，跟随模的上坡分量 `−F_k/(b_k − λ_p)` 随梯度一同消失，初始模型步是
**下降步**（实测首步 `dmax 0.0486 bohr`、`ΔE −2.03 kcal/mol`）。因此新增**逃逸行走**
（`prfo.f90:escape_from_minimum`）：

- **触发条件**（两条都必须满足）：① 谱中**没有**显著负曲率（否则是鞍点猜测，不动它）；
  ② 初始模型步**不是上升步**——由新的内部探针 `initial_step_ascends()` 判定，它用**驱动同一条**
  P-RFO / B-P-RFO 步例程算一次首步，取 `predicted < −escape_ascent_tol (1e-12 Eh)` 为「上升」。
  这条判据把「极小点（模型步下降）」与「弯曲猜测/远点起步（模型步上升）」分开：
  实测 Müller-Brown 起点 `(-0.6,0.4)` 的 `predicted = −4.83e-2 Eh`（上升 → **不逃逸**，
  搜索照旧 6 步到鞍点），HCN 极小点则 `predicted > 0`（下降 → 逃逸）。
- **行走**：沿**最低内模**推 `--lts-escape-step`（默认 **0.2 bohr**），每次推走都重算
  Hessian + 重新选模（跟模），**直到该模曲率变负**为止；上限 `escape_max_walk = 3.0 bohr`
  （`ceiling(3.0/0.2) = 15` 次推走上限），失败（评估/Hessian 失败、位移为零）只 warning 并保留
  最后一个有效几何。
- **位移量论证**：`escape_step` 是**笛卡尔**长度（本模块的模向量是质量无关的笛卡尔单位向量），
  与「0.1–0.3 bohr·amu^0.5」的关系是 `d_Cart = d_mw / ‖M^{1/2} v‖`；HCN 弯曲的
  `‖M^{1/2} v‖ ≈ 1.07`，故默认 0.2 bohr ↔ 0.21 amu^0.5·bohr，落在建议区间内。
  **单次 0.2 bohr 不够**（实测）：推 0.2 bohr 后最低模仍是 `+0.0960 Eh/bohr²`，
  推到 **1.4 bohr** 才变负（`−0.0053 Eh/bohr²`）——所以行走是**循环**的，这一点由实测决定，
  不是设计偏好。
- **记录**：`--lts` 头部打印 `escape from a minimum: 0.200000 bohr along the lowest internal mode`
  （设置回显），每次推走在 `--lts-printlevel 2` 打印，收尾打印
  `escape from a minimum: 7 push(es), total displacement 1.400000 bohr, lowest mode -5.299187E-03 Eh/bohr^2`。
- **CLI**：`--lts-escape-step VALUE`（新增，`main.F90` + `xhelp.f90`；`0` 关闭逃逸）。

**修复后实测（`acceptance/`）**：

| 起点 | prfo | bprfo | dimer |
|---|---|---|---|
| 线性极小点 H(−1.0,0,0) | 逃逸 7 push/1.4 bohr + **5 步**，1 虚频 −1426.19 cm⁻¹，exit 0，E = −5.387373532908 | 逃逸 7 push + **7 步**，1 虚频 −1426.13 cm⁻¹，exit 0，E = −5.387373532839 | **29 步**，1 虚频 −1426.73 cm⁻¹，exit 0，E = −5.387373461989（`Hessian requests: 0`） |
| 弯曲 TS 猜测 H(0,1.05,0) | 4 步，1 虚频 −1426.12 cm⁻¹，exit 0，E = −5.387373532156 | 5 步，1 虚频 −1426.12 cm⁻¹，exit 0，E = −5.387373532550 | 15 步，1 虚频 −1425.24 cm⁻¹，exit 0，E = −5.387373500230 |
| 线性 HNC 极小点（ctest 输入） | 逃逸 8 push/1.6 bohr + 4 步，1 虚频，exit 0，E = −5.387373532837 | — | — |
| 线性极小点 + `--lts-escape-step 0` | 3 步，0 虚频，exit 1 + 诊断 | — | — |

三种方法从极小点与从弯曲猜测到达的是**同一个**鞍点（能量一致到 1e-7 Eh）。
**dimer 不需要 Hessian / 不选模**，因此它从极小点起步**直接可用**——这正是父会话看到的
「dimer 成功、prfo/bprfo 失败」的结构性原因；现在三者都能成功。

### 1.3 考虑过但**否决**的另一条路：修 trust 半径的 rho

诊断过程中发现：逃逸后的爬坡会被 trust 半径拖死——`rho` 只在 `predicted > 0` 时计算，
而**上坡步**的 `predicted` 是负的，于是每一步都被判 `rho = 0` → 半径每步 ×0.75，
15 步后落到 `trust_min = 1.8897e-3 bohr`，再用 240 步以 1.2e-3 bohr 的步长爬（实测：
prfo 256 步未收敛，`gmax` 从 2e-2 只降到 6.3e-4，虽然已到鞍点附近且确认 1 虚频）。
把 rho 改成**带符号的**标准比值（`rho = (E_old − E_new)/(E_model_old − E_model_new)`，
数学上正确）确实让逃逸后的 HCN **11 步**收敛——但它**弄坏了已验收的 Müller-Brown**：

| 版本 | mb-prfo-saddle | prfo vs bprfo RMSD |
|---|---|---|
| 原规则（`predicted > 0` 才比值） | 6 步收敛到鞍点 | **6.3022e-06**（验收值） |
| 带符号比值的标准 trust 更新 | **23 步不收敛**（`gmax 1.1e+178`，跑到 basin 外） | 7.68e-01（失败） |

原因经实测确定：MB 起点 `(-0.6,0.4)` 的 RFO 步**本身**就有 0.5–1.5（比它到鞍点的距离还大），
原规则在这个无单位的解析面上「每步收缩」恰好把半径压到合适尺度，而标准比值在第 4–5 步
判「预测良好」→ 放大到 0.868 → 第 6 步过冲（`predicted −3.47` vs `actual −0.91`）→ 出界。
**结论：不动 trust 规则**（它属于「已验收 M4 数字」的一部分），改由逃逸行走把起点送到
曲率已变负的位置，让**原有**搜索逻辑自然收敛（5/7 步）。这条弯路连同其数据记在此处，
以免后人重复踩。

### 1.4 测试与可证伪注入（任务 1）

- **CLI 级（新增）`xtb/landscape-ts-escape`**：输入 = 线性 HNC 极小点（与
  `xtb/landscape-ts-minimum` **同一**输入）。断言：exit 0；输出含
  `escape from a minimum: <n> push`；含 `escape from a minimum:  0.200000 bohr`；
  含 `selected mode, rigid body overlap:  0.000000`（选中的不是刚体模）；
  `saddle confirmation - imaginary modes: 1` + `confirmation: first order saddle point`；
  `xtbts.xyz`/`xtbts.log` 写出且非空、日志含 `confirmation imaginary modes: 1`；
  **并且 bprfo 同样满足**逃逸 + 1 虚频 + exit 0。
- **CLI 级（改造）`xtb/landscape-ts-minimum`**：加 `--lts-escape-step 0`，继续锁住 H2 的
  「极小点不是鞍点 → 非零退出码 + 三条诊断 + 文件仍写出」路径（默认开启逃逸后，同一起点
  不再产生极小点，所以旧测试必须显式关闭逃逸才仍有意义）。
- **单元级（新增）`mode-select-lowest-internal`**：合成谱
  `evals = [−1e-16, −1e-17, +0.3, +0.5]`（前两个是噪声带内的刚体零模）→ 断言
  `mode%index == 3`、`eigenvalue == 0.3`、`vector = e3`、且发出 warning。
  **注入 B**（`index = 1` 回退）→ 该测试红 + `xtb/landscape-ts-escape` 红（实测）。
- **注入 A**（`escape_from_minimum` 立刻 return）→ `xtb/landscape-ts-escape` 红
  （`the escaped search terminated with status 1`，实测）。

---

## 2. 任务 2：MEDIUM-3，`result%etemp` 断言

`xtb/landscape-ts-etemp` 新增两条断言（CMake 与 `landscape_cli_check.py` 两侧）：

1. `output MATCHES "etemp: +5000[.]000 K"` —— 这是 `landscape_result%write_log` 打印的
   **结果字段**（`results.f90:380-386`），与已有的两条（settings 回显
   `electronic temperature:  5000.000 K`、引擎回读 `landscape engine: etemp  5000.000 K`）
   是**不同的行**；
2. `xtbts.log` 含 `electronic temperature (frozen):  5000.000 K`
   （`ts.f90:write_ts_files` 写的是 `result%etemp`）。

**注入 D**（删掉 `ts.f90` 的 `result%etemp = engine%effective_etemp()`）→ 测试红，
`CMake Error … the result object does not carry the effective etemp`（实测，`injections/expD-…`）。

**诚实说明断言的能力边界**：在当前设计下 `settings%etemp` 与 `engine%effective_etemp()`
**必然相等**（`ts.f90` 把 `settings%etemp` 拷进 `ctrl%etemp`，引擎再把它推进计算器，
回读的就是同一个值），所以「把赋值改成 `settings%etemp`」这一种替换在本 CLI 上**无法**被区分；
能捕获的是复核真正担心的两类错误：**字段根本没赋值**（注入 D 红）与**值从未到达计算器**
（引擎回读断言 + M3 的 `etemp-control`/`--lvib` 端口）。这一点写进报告而不是假装覆盖了。

---

## 3. 任务 3：MEDIUM-2，`λ_n` 对分不验证残差

### 3.1 测量：该情形是否真实发生

复核的担忧：`hi = bmin − mu_margin` 的上端残差从不校验，噪声门又把 `(−tol, 0)` 的本征值
留在方程里，于是（当所有下坡梯度都 ≲1e-8 时）方程在 `(−∞, bmin)` 上**没有根**，
对分会把 `λ_n` 收敛到区间端点 `hi` 并照旧通过 `λ_n < 0` 断言。

**测量方法**：临时在 `landscape_rfo_downhill_shift` 出口打印
`residual(hi)`、`residual(λ_n)`、`bmin` 与 `Σ_{i≠k}F_i²`，跑三个真实 M4 用例
（弯曲 HCN prfo/bprfo、逃逸后的 HCN prfo），共 **19 次**求解。原始日志：
`m4-final-fix-data/med2/*-shift-residuals.log`（`DBGSHIFT` 行）。

**结果**：`residual(hi)` **全部为负**（−5e-4 … −2e-2，最接近 0 的一条是 −2.1e-7），
返回根的残差 `|residual(λ_n)| ≤ 5e-16`；`bmin ≈ −2e-16`（投影噪声，复核点出的正是它）
**无害**；`Σ F_i²` 为 1e-10 … 2.7e-2（远大于触发阈值）。

**为何不发生（可检验的论据，不只「应该不会」）**：残差在 `(−∞, bmin)` 上严格递减，
`residual(hi) < 0` ⟺ `Σ_{i≠k} F_i²/(b_i − hi) > −hi`；由 `b_i − hi ≥ mu_margin` 得
`Σ F_i² / mu_margin ≥ Σ F_i²/(b_i − hi)`，故 **充分条件**是
`Σ_{i≠k} F_i² > mu_margin·(mu_margin − bmin)`——默认 `mu_margin = 1e-8`、
`|bmin| ≪ mu_margin` 时即 `|F_i| ≳ 1e-8`。而搜索的收敛判据是 `g_max ≤ 3e-4`
（`g_rms ≤ 1e-4`），即只要还在走步，梯度就比触发阈值大 **4 个数量级**；
实测的最小 `Σ F_i² = 1.6e-5`（= `|F| ~ 4e-3`）也是如此。（当梯度真的掉到 1e-8 以下时，
搜索已经收敛、步已无意义。）

### 3.2 加固（仍按复核建议做，成本 ~10 行）

`eigenfollow.f90:landscape_rfo_downhill_shift` 在开区间前增加**上端残差校验**：
`residual(hi) > 0` 时**不再返回区间端点**，而是 `λ_n = 0`、`solved = .false.` 并发 warning
（`the lambda_n secular equation has no root below the smallest downhill eigenvalue;
the downhill step uses lambda_n = 0`）。语义：方程没有下坡分支时，退化的「纯牛顿下坡步」
（`λ_n = 0`，本来就是文档里「下坡子空间为空」的既定行为）比一个**不是根**的 shift 更诚实。
选择「回退到 λ_n = 0」而不是复核建议的「把抬升作为回退恢复」的理由：在该失效模式下
无约束方程的根其实落在 `λ* ≳ bmin ≈ 0`（正侧），**任何负的 `λ_n` 都不被方程支持**；
而抬升（`b_i → hlow`）会顺带改变正常软模的行为，代价更大。

**单元测试（新增）`prfo-lambda-n-no-root`**：合成谱 `diag(−0.5, −1e-16, 0.5)`、
`F = [0, 1e-11, 1e-11]`、`k = 1`。先**独立算出**上端残差 `residual(hi) > 0`（断言这个前提），
再断言 `λ_n == 0`、`env%nLog` 增加（有 warning）、`lifted = F`、`|step| ≤ trust`。
注意：跟随模的 `F_k` 必须为 0——否则 `0.01 + 1e-22` 在双精度下回到 `0.01`，
`ΣF² − F_k² ≤ tiny` 会先走「全零下坡梯度」的既有分支（这一点也写进了测试注释）。
**注入 C**（删掉该校验）→ 该测试红，`Message: a shift that does not solve the secular
equation was returned`（实测）。

---

## 4. 任务 4：把几何依赖性写进文档

| 文件 | 补充内容 |
|---|---|
| `docs/xtb-landscape-PLAN.md` §9.5 | 新增「[M4 最终修复轮]」块：MEDIUM-1/2/3 的处置 + **两起点实测对照表** + 「prfo/bprfo 需要鞍点猜测或过渡向量」「dimer 不需要 Hessian，从极小点起步直接可用」 |
| `26-m4-saddle-implementation-report.md` §10（新） | 明确本报告 HCN 验收起点是**弯曲 TS 猜测**；prfo/bprfo 对起点的要求；从极小点的实测行为 |
| `27-m4-dimer-implementation-report.md` §12（新） | dimer 与 P-RFO 的**结构性**差别（无 Hessian、无选模）+ 两起点对照表 |
| `28-m4-validation-experiments.md` §12（新） | 两起点 × 三方法 × 逃逸开关的实测表（本报告 §1.2 的表） |
| `30-m4-fix-report.md` | 追加「[最终修复轮] MEDIUM-1/2/3 的处置」小节（指向本报告） |

---

## 5. 任务 5：复核 31 §5「需运行验证」清单逐条结果

| # | 清单项 | 结果 | 证据 |
|---|---|---|---|
| 1 | 构建 + `ctest -R landscape` = 49/49；`-N` = 49；无重名；回归 12/12 | **51/51**（49 + 新增 `xtb/landscape-ts-escape`、`xtb/landscape-ts-escape-step-missing`）；`-N` = 51；`grep … uniq -d` 空；回归 **12/12**。顺带发现并修掉一条 **M4 遗留在测试里的编译警告**（`test_landscape_saddle.f90:1292` 用实数做 DO 循环变量，gfortran 报 deleted feature）→ 现在 `cmake --build` **0 warning / 0 error** | §7 |
| 2(a) | 删 `project_rigid`（步投影）→ `driver-rigid-projection` 红 | **红**（`driver-rigid-projection [FAILED]`） | `injections/inj-a-step-projection.txt` |
| 2(b) | 删 `project_hessian_rigid` → 复核预测「仍绿」 | **复核部分证伪**：**单元**测试全绿（0 红），但 **CLI** `xtb/landscape-ts-prfo` **红**——输出出现 **4 行 `lifted=T`**（该测试断言 `lifted=T` 不得出现）。即 H4 的「谱投影」这一半**有**可证伪覆盖，只是不在单元级 | `injections/inj-b-hessian-projection-unit.txt`、`inj-b-hessian-projection-cli.txt` |
| 2(c) | `landscape_ts_curvature_band_hit` 恒 `.false.` → `ts-curvature-band` 红 | **红**（`Message: a mode inside the band was not detected`）。注意：必须改**谓词函数体**；只改调用点（`band_hit = .false.`）**不会**变红，因为该测试测的是纯谓词 | `injections/inj-c-curvature-band.txt` |
| 2(d) | 删 `result%converged = .false.` → `xtb/landscape-ts-minimum` 红 | **红**（`CMake Error at landscape_cli_ts_minimum.cmake:16`：exit 0 被接受） | `injections/inj-d-saddle-failure.txt` |
| 2(e) | 线性分支回退到「最低 n_zero」→ `linear-saddle-imaginary` 红 | **复核预测证伪**：**绿**。把线性分支的选择换成按 `|freq|` 取最低 `n_zero` 个后，`landscape-vib` **16 个用例输出逐字节相同**（`diff` 空）、0 红。原因：该用例（线性 H₂O 的真实数值 Hessian）里被抬升的刚体模的 `|freq|` 仍**低于**两条真虚弯曲模，两种选择规则给出同一结果 → **H3 的选模改动目前没有可证伪覆盖**（复核 §2 LOW-3 的边界比原判更宽；本轮未新增该覆盖，见 §8） | `injections/inj-e-linear-zero-modes.txt` **[订正 34：此结论已证伪并撤回，见下]** |
| 3 | MEDIUM-1 判定实验（选中的是不是刚体模） | **成立**：注入 B 下 `selected mode, rigid body overlap: 1.000000` + `index 1 eigenvalue −0.00000000` | `injections/expB-selection-defect-cli.txt` |
| 4 | MEDIUM-2 判定实验（`λ_n` 是否真是根） | **不是根的情形未发生**：19 次求解 `residual(hi)` 全负、`|residual(λ_n)| ≤ 5e-16` | `med2/*.log` |
| 5 | `--lts-hlow 1e-12` vs 默认，统计 `lifted=T` | 两者均 **0 行 `lifted=T`**（各 4 行 `lifted=F`），exit 0 | `acceptance/bent-prfo/stdout.txt` + 现场对比 |
| 6 | M3 回归：CO₂/HCN `--lvib` vs `--hess` + `q_ROT` | CO₂ max\|Δf\| = **0.0036 cm⁻¹**，HCN = **0.0023 cm⁻¹**（验收上限 0.004）；两者均 `4 internal, 5 projected zero modes`（3N−5）；`TR` 行两条路径**逐位相同**（0.893E+25 / 0.430E+25） | `m3/co2-*`、`m3/hcn-*` |
| 7 | M4 验收数字（从输出读，不抄报告） | MB prfo vs bprfo RMSD = **6.3022E-06**（断言 <1e-3）；dimer vs prfo = **7.7397E-05**；`dimer Hessian requests 0`；GFN2 HCN 弯曲起点 prfo/bprfo/dimer = 4/5/15 步 + `imaginary modes: 1` + exit 0 | §5.7、`acceptance/` |
| 8 | Debug 构建（`-fbounds-check -ffpe-trap=invalid,zero,overflow -fbacktrace`）跑三方法 E2E | **6/6 干净**（弯曲+极小点 × prfo/bprfo/dimer）：exit 0、步数与 Release 相同（4/5/15、5/7/29）、各 1 虚频，且虚频值与 Release **完全相同**（−1426.12/−1426.13/−1426.19/−1426.73/−1425.24 cm⁻¹）；无 `ERROR`/`trap`/`backtrace` 标记 | `debug/*.log` |

***[订正 34]*** **第 2(e) 行的结论已被实测证伪并撤回**（保留原行作为订正痕迹）。
该行实际注入的是「按 `|freq|` 取最低 `n_zero` 个」，与它声称的「回退到「最低 n_zero」」**语义不等价**。
用**真旧逻辑**（线性分支无条件取最低 `n_zero` 个**本征值**，等价 HEAD 的 `order(i)=i`）复跑：
`11/51 Test #62: xtb/landscape-vib ***Failed`，`linear-saddle-imaginary [FAILED]`，
`Message: the two imaginary bends of linear H2O were not reported`，`# imaginary freq. 0`（期望 2）。
即 **H3 的选模改动早有可证伪守卫**；`inj-e` 之所以绿，是因为它的变异在**该几何**上是行为等价的**正确替代实现**，本就不应红。
证据：`m4-coverage-data/injections/inj-1-true-old-logic.txt`、`inj-2-lowest-absfreq.txt`；详见 `34-m4-coverage-fix-report.md` §1。

---

## 6. 已验收数字是否被弄坏

| 数字 | 原值（M4 验收） | 本轮重跑 | 判定 |
|---|---|---|---|
| MB prfo vs bprfo RMSD /bohr | 6.3022e-06 | **6.3022e-06** | 不变 |
| MB dimer vs prfo /bohr | 7.74e-05 | **7.7397e-05** | 不变（同一数值的四舍五入） |
| MB dimer Hessian requests | 0 | **0** | 不变 |
| 弯曲 HCN prfo / bprfo / dimer | 1 虚频、exit 0 | 4/5/15 步、1 虚频、exit 0、E = −5.387373532156 / −5.387373532550 / −5.387373500230；虚频 −1426.12 / −1426.12 / −1425.32 cm⁻¹ | 不变 |
| M3 线性分子（CO₂/HCN） | 3N−5、5 零模、q_ROT 逐位、Δf ≤ 0.004 cm⁻¹ | 4 内模 + 5 零模；Δf = 0.0036/0.0023；`TR` 逐位相同 | 不变 |

***[订正 34]*** 上表「弯曲 HCN prfo / bprfo / dimer」一行的原注「（与修复前逐位相同）」**不成立**，撤回。
仓库里唯一的修复前记录是 `26-m4-saddle-implementation-report.md:159-183` 与 `28-m4-validation-experiments.md:177`：
弯曲 HCN prfo 4 步、1 虚频 **−1426.11 cm⁻¹**、`TOTAL ENERGY −5.387373532487`。
本轮实测为 E = −5.387373532156、虚频 −1426.12 cm⁻¹，即 **ΔE = 3.31e-7 Eh、Δf = 0.01 cm⁻¹**，
差异归因于 round 30 的 **H4 谱投影**（`lifted=T → F`），**不是**最终修复轮。
准确表述应为：**收敛到同一鞍点、虚频数值在 0.01 cm⁻¹ 量级内一致**。
两组实测数字（父会话 2026-10 独立重跑）：

- 修复前（m4-validate 记录）：弯曲 HCN prfo 虚频 **−1426.11 cm⁻¹**、E = −5.387373532487。
- 现在（弯曲起点）：prfo **−1426.12**、bprfo **−1426.12**、dimer **−1425.32 cm⁻¹**，均 exit 0。
- 线性极小点起步（本轮新修路径）：prfo **−1426.21**、bprfo **−1426.12**、dimer **−1426.89 cm⁻¹**，均 exit 0。

（dimer 的 `energy calls: 337` 与修复前也逐位相同 → 本轮改动确实没有触碰 dimer 路径。）

---

## 7. 改动文件与测试

```
 M src/landscape/saddle/eigenfollow.f90     选模（最低内模）+ λ_n 上端残差校验 + landscape_lowest_internal_mode
 M src/landscape/saddle/prfo.f90            逃逸行走 + 首步上升探针 + 选模诊断（刚体重叠）
 M src/landscape/types/settings.f90         新增 escape_step（+ 文档：单位与量级论证）
 M src/landscape/tasks/ts.f90               --lts 头部回显逃逸位移
 M src/prog/main.F90                        --lts-escape-step
 M src/xhelp.f90                            帮助文本
 M test/unit/CMakeLists.txt                 新 CLI 测试 xtb/landscape-ts-escape；ts-minimum 加 --lts-escape-step 0；
                                            ts-etemp 加 result%etemp 断言
 M test/unit/landscape_cli_check.py         meson 镜像：check_ts_escape（新）+ check_ts_minimum/check_ts_etemp 同步
 M test/unit/meson.build                    新测试注册
 M test/unit/test_landscape_saddle.f90      新单元测试 mode-select-lowest-internal、prfo-lambda-n-no-root；
                                            另修掉一条 M4 遗留的实数 DO 循环变量警告（dimer-curvature）
 M docs/xtb-landscape-PLAN.md                §9.5 [M4 最终修复轮] 块 + 几何依赖表
 M docs/_landscape-recon/{26,27,28,30}-*.md  几何依赖性补充节
?? docs/_landscape-recon/32-m4-final-fix-report.md（本文件）
?? docs/_landscape-recon/m4-final-fix-data/（acceptance/escape/debug/m3/med2/injections）
```

新增测试（3 个，均同时注册到 `CMakeLists.txt` / `meson.build` / `main.f90` 三处所需的清单）：

| 测试 | 类型 | 锁住的行为 |
|---|---|---|
| `mode-select-lowest-internal` | 单元 | 噪声带内的刚体零模不得被当作过渡向量 |
| `prfo-lambda-n-no-root` | 单元 | 方程无根时 `λ_n = 0` + warning，而不是返回区间端点 |
| `xtb/landscape-ts-escape` | CLI（GFN2 真实体系） | 从极小点起步：逃逸行走 + prfo/bprfo 各 1 虚频 + exit 0 + 日志记录 |
| `xtb/landscape-ts-escape-step-missing` | CLI 错误分支 | `--lts-escape-step` 缺值报错（与 `--lts-step/--lts-sccacc/--lts-step0` 同款） |
| （改造）`xtb/landscape-ts-minimum` | CLI | 关闭逃逸时极小点仍按 H2 失败（exit≠0 + 诊断 + 文件） |
| （改造）`xtb/landscape-ts-etemp` | CLI | `result%etemp` 与 `xtbts.log` 的冻结温度 |

**最终验证**：`ctest -R landscape` = **51/51**；`ctest -N -R landscape` = 51；
`grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d` 空；
回归 `-R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'` = **12/12**；构建无 warning/error。

---

## 8. 残余风险与未竟事项

1. ~~**H3 的选模改动仍无可证伪覆盖**（本轮用 §5.2(e) 的注入实测发现）。~~
   ***[订正 34]*** **此结论已被实测证伪并撤回**（见 §5 表后订正与 `34-m4-coverage-fix-report.md` §1）：
   真旧逻辑（最低 `n_zero` 个本征值）**早已**被 `linear-saddle-imaginary` 判红；§5.2(e) 绿是因为
   其变异（最低 `|freq|` 个）与旧逻辑不等价。复核 31 LOW-3 / 本报告点名的**回退分支**
   （刚体基识别不全 → warning + 按最低 `|freq|` 补足）此前确实无覆盖，现由合成畸变线性 Hessian
   单测 `linear-rigid-fallback` 覆盖（`34-m4-coverage-fix-report.md` §2）。
2. **逃逸行走是启发式**：步长默认 0.2 bohr、总预算 3.0 bohr、只在「无显著负曲率 + 首步非上升」
   时触发。对极端软模（曲率永不变负）或会解离的位移，行走会走满预算后仍交给搜索
   （结果由 H2 的确认路径判定并给出非零退出码 + 诊断），不会静默给出错误鞍点。
   不同体系的合适步长可能不同（可 `--lts-escape-step` 调整）；本轮只在一个真实体系
   （GFN2 HCN/HNC，两种极小点几何）上标定。
3. **trust 半径的 rho 规则在上坡时过保守**（§1.3，实测：256 步爬坡 vs 5 步），
   但改动它会让 Müller-Brown 不收敛，因此**本轮不动**；作为已知特性记录在 PLAN §9.5
   与本报告，留给后续（若将来要给 MB 测试换起点或引入半径的自适应上限，可一并处理）。
4. **`result%etemp` 断言的边界**见 §2 末段（`settings%etemp` 与生效值在设计上必然相等）。
5. 复核 31 §2 的 LOW/INFO 中，本轮只处理了与三条 MEDIUM 直接相关的部分；其余
   （LOW-2 H1 重算分支、LOW-4 M8b 零步回退、LOW-5 meson 镜像弱于 CMake、LOW-6 `imag_freq`
   语义、INFO-1/3/4 措辞等）**保持原状**，未在报告中声称已处理。

---

## 9. 数据目录布局

| 路径 | 内容 |
|---|---|
| `m4-final-fix-data/acceptance/` | 9 个 GE 端到端运行（弯曲/极小点 × prfo/bprfo/dimer + HNC 极小点 + 两个「关逃逸」对照），各含 `stdout.txt` 与 `exit.txt` |
| `m4-final-fix-data/debug/` | Debug 构建（`-fcheck=bounds -ffpe-trap=…`）的 6 个 E2E 日志与退出码 |
| `m4-final-fix-data/m3/` | CO₂/HCN 的 `--lvib` 与 `--hess` 原始输出（3N−5、零模数、频率、热力学） |
| `m4-final-fix-data/med2/` | `λ_n` 逐次求解的 `residual(hi)`/`residual(λ_n)`/`bmin`/`ΣF²` 原始打印（19 次） |
| `m4-final-fix-data/injections/` | 9 项注入的真实输出（expA–D + inj-a…e） |
