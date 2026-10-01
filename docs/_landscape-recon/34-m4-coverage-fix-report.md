# 34 — M4 覆盖收口轮报告（任务 A / B / C）

> 轮次性质：复核 33「接受 M4」之后的**只收尾**轮。生产逻辑（`src/landscape/**`）**零改动**，
> 只动测试与文档。纪律：全部 `OMP_NUM_THREADS=1`；只跑 `-R landscape` 与回归子集；未提交 git。
> 数据目录：`docs/_landscape-recon/m4-coverage-data/`（`validation.txt`、`injections/`、`m3/`）。

---

## 0. 摘要

本轮的**主要发现是：任务 A 的前提被实测证伪**。

- 复核 33 / 报告 32 §5.2(e) 声称「把线性分支改回旧逻辑 → 全绿，所以 H3 无可证伪覆盖」。
  **不成立**：真旧逻辑（线性分支无条件取最低 `n_zero` 个**本征值**）会让
  `linear-saddle-imaginary` **变红**（`xtb/landscape-vib` 红，`# imaginary freq. 0` 期望 2）。
  H3 的修复**早就有**可证伪守卫。报告 32 §5.2(e) 实际注入的是「按 `|freq|` 取最低 `n_zero` 个」，
  与旧逻辑**语义不等价**——那个变异在该几何上是行为等价的**正确替代实现**，本就不应红。
- 真正**无覆盖**的是复核 31 LOW-3 / 报告 32 §8.1 点名的**回退分支**
  （刚体基识别不全 → warning + 按最低 `|freq|` 补足）。本轮补了一条**合成畸变线性 Hessian** 单测
  `linear-rigid-fallback` 覆盖它，并给 `linear-saddle-imaginary` 补了「数值 + 符号」断言。
- 两条新/改测试都**自证可证伪**：真旧逻辑、`|freq|` 变异、回退填充规则反转**三种注入**都能判红。
- 报告 32 §6 的「与修复前逐位相同」已按实测订正；复核 33 的 LOW/INFO 逐条记录（§4）。
- 全绿复核：`ctest -R landscape` = **51/51**；`-N` = 51；无重名；回归 **12/12**；
  M3 线性分子输出与已记录数据**逐字节相同**。

---

## 1. 任务 A（订正）：H3 覆盖缺口的前提被实测证伪

### 1.1 真旧逻辑 = 红（缺口不存在）

「旧逻辑」= 线性分支无条件把**最低 `n_zero` 个本征值**当零模（`syev` 升序，等价 HEAD 的
`order(i)=i`，见 `git show HEAD:src/landscape/vib/modes.f90`）。把当前线性分支的选择换成这个规则：

```
$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape
11/51 Test  #62: xtb/landscape-vib ........................***Failed    0.07 sec
98% tests passed, 1 tests failed out of 51

$ xtb-tester landscape-vib
       ... linear-saddle-imaginary [FAILED]
  Message: the two imaginary bends of linear H2O were not reported
       ... linear-rigid-fallback [FAILED]
  Message: the rigid body fallback did not warn
```

原始输出：`m4-coverage-data/injections/inj-1-true-old-logic.txt`。

`linear-saddle-imaginary`（`test/unit/test_landscape_vib.f90`）断言 `vib%n_imag == 2`；
旧逻辑把两条真虚弯曲吞成零模，`# imaginary freq. 0` → **红**。
**⇒ H3 的选模修复自始就有可证伪守卫。**

### 1.2 报告 32 §5.2(e) 的注入与旧逻辑不等价 → 绿

报告 32 §5.2(e) / `injections/inj-e-linear-zero-modes.txt` 记录的注入是
「按 `|freq|` 取最低 `n_zero` 个」，**不是**旧逻辑。复跑：

```
$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape
(then, before this round's new test: 100% tests passed, 0 failed out of 51)
```

原始输出：`m4-coverage-data/injections/inj-2-lowest-absfreq.txt`。

原因：在**物理**线性 H₂O 的真实数值 Hessian 上，被抬升的刚体模的 `|freq|` 仍**低于**两条真虚弯曲，
所以「取最低 `|freq|`」与「按刚体重叠选」给出**同一结果**——它是一个在该几何上正确的替代规则，
不是缺陷。**因此报告 32 §5.2(e) 的结论「H3 没有可证伪覆盖」被撤回**（已在报告 32 原位标注订正，
保留痕迹）。

> **方法学教训（第 4 次静态结论被实测推翻）**：注入实验必须先证明变异与旧逻辑**语义等价**，
> 否则「变红 / 不变红」都无法支撑结论。已写入 AGENTS.md 第 6 节。

---

## 2. 任务 A（b）：强化覆盖

生产逻辑**未动**；只改 `test/unit/test_landscape_vib.f90`（新增/加强的用例都挂在既有 ctest
目标 `xtb/landscape-vib` 上，故**没有**新增 `add_test`，`ctest -N -R landscape` 仍为 51）。

### 2.1 `linear-saddle-imaginary`：补「数值 + 符号」断言

原来只断言 `vib%n_imag == 2`（个数对但数值/符号错时不红）。现在追加（同一线性 H₂O、GFN2 数值 Hessian，
`hess_step = 5e-3`、`scc = 0.3`）：

| 断言 | 值（实测，`m4-coverage-data/`） |
|---|---|
| `vib%freq(6) < -1000 .and. vib%freq(7) < -1000` | `-10566.03, -10566.03` cm⁻¹（符号 + 量级） |
| `abs(vib%freq(6) - vib%freq(7)) < 1e-3` | 简并 |
| `abs(vib%freq(6) + 10566.03) < 5.0` | 数值 |
| `vib%freq(8) > 0 .and. vib%freq(9) > vib%freq(8)` | `20004.35, 21035.64` cm⁻¹（两条正拉伸） |

（数值来自确定性重跑：同一 OMP=1 环境两次逐位相同。）

### 2.2 新单测 `linear-rigid-fallback`：合成畸变/秩亏线性 Hessian → 覆盖回退分支

`landscape_vib_analysis` 的**回退分支**（刚体基识别不全 → `env%warning` + 按最低 `|freq|` 补足，
`modes.f90` 线性分支）此前**不可达**：随机/对角/物理 Hessian 的 9 个本征向量里总有 ≥5 个与
刚体子空间重叠 ≥0.5（实测：对角 = 7 个，随机 2000 次最少 5 个）。

新 fixture 用**规定的本征向量**构造（`build_avoiding_linear_hessian`）：

- 4 个本征向量是**精确**刚体方向（重叠 = 1）；
- 另 5 个张成这些刚体方向的**补空间**，每个只携带 `1/sqrt(5) = 0.447` 的刚体分量（< 0.5 阈值）；
- 9 个本征值互不相同 ⇒ 组装矩阵的本征向量就是规定的 9 个。

线性分子需要 `n_zero = 5`，重叠分类只能找到 4 个 ⇒ 触发回退。
测试钉住：**warning 已发**（`env%nLog` 增加）、`n_zero = 5`、`n_vib = 4`、
**被吞的是哪一个**（剩余里 `|freq|` 最小的本征值 0.15 那个；期望 `freq(6:9) =
autorcm*[-sqrt(0.4), -sqrt(0.25), sqrt(0.3), sqrt(0.6)]`）、`n_imag = 2`、
以及**被吞模式的自身频率**（`autorcm*sqrt(0.15)`）**不再出现**。

fixture 里 `rigid_body_basis` 复刻了生产模块的私有例程（保持模块 public 面不变；测试断言的是
分析的可观测行为，若复刻漂移会**响亮**失败）。

### 2.3 自证（三种注入，红 → 还原 → 绿）

| # | 注入 | 结果 | 证据 |
|---|---|---|---|
| 1 | 线性分支 = 真旧逻辑（最低 `n_zero` 本征值） | **红**：`linear-saddle-imaginary` `n_imag 0≠2`；`linear-rigid-fallback` `no warning` | `injections/inj-1-true-old-logic.txt` |
| 2 | 线性分支 = 最低 `|freq|` n_zero 个（复核 32 的变异） | **红**：`linear-rigid-fallback` `the rigid body fallback did not warn`（新测也判红了这个变异） | `injections/inj-2-lowest-absfreq.txt` |
| 3 | 回退填充规则反转（取**最大** `|freq|`） | **红**：`linear-rigid-fallback` `Message: wrong zero mode filled: expected -138807.94 -109737.32 120211.21 170004.32 got -138807.94 -109737.32 85002.16 120211.21` | `injections/inj-3-wrong-fill.txt` |

注入 3 的失败消息**内含期望值 vs 实际值**（`check` 的消息里带数字），满足任务书要求。
三种注入还原后 `linear-rigid-fallback` / `linear-saddle-imaginary` 均 **PASSED**（§5）。

---

## 3. 任务 B：报告 32 §6 措辞与数字订正

复核 33 LOW-1：报告 32 §6 写「弯曲 HCN 的 prfo 结果与修复前**逐位相同**」，与仓库唯一记录的
修复前值矛盾。已订正：

- 报告 32 §6 表格行改为带**虚频实测值**的一行，并在表下加 ***[订正 34]***：
  修复前（`26-m4-saddle-implementation-report.md:159-183`、`28-m4-validation-experiments.md:177`）
  弯曲 HCN prfo = **−1426.11 cm⁻¹**、`E = −5.387373532487`；本轮 = **−1426.12 cm⁻¹**、
  `E = −5.387373532156` ⇒ **ΔE = 3.31e-7 Eh、Δf = 0.01 cm⁻¹**，归因 round 30 的 H4 谱投影。
  准确表述：**收敛到同一鞍点、虚频数值在 0.01 cm⁻¹ 量级内一致**（不是逐位相同）。
- 写入父会话独立实测的两组数字：
  - 弯曲起点：prfo **−1426.12**、bprfo **−1426.12**、dimer **−1425.32** cm⁻¹，均 exit 0；
  - 线性极小点起步（本轮新修路径）：prfo **−1426.21**、bprfo **−1426.12**、dimer **−1426.89** cm⁻¹，
    均 exit 0。
- 报告 30 §4 也补记了同样三个弯曲起点能量（复核 33 LOW-1 的建议）。

---

## 4. 任务 C：复核 33 剩余 LOW / INFO 记录

| 项 | 位置（复核 33 的 `file:line`） | 处置 |
|---|---|---|
| **LOW-1** 报告 32 §6「逐位相同」自相矛盾 | `32-m4-final-fix-report.md` §6 | **已修**（本轮，§3） |
| **LOW-2** `--lts-escape-step` 无下界 → 推走次数无界（每次推走 1 次数值 Hessian） | `saddle/prfo.f90:773`（`ntries = ceiling(3.0/escape_step)`，`escape_max_walk` 在 `:104`）；CLI 无校验 `prog/main.F90:2895-2910`；`tasks/ts.f90` 未校验 | **推迟到 M5**（不影响默认路径；建议 M5 加 `0 < step`，或硬上限 ~100） |
| **LOW-3** 逃逸「不触发」一侧与 `initial_step_ascends` 无断言 | `saddle/prfo.f90:492`（调用）、`:702-727`（探针）；`test/unit/CMakeLists.txt:897-968`（ts-prfo 脚本） | **推迟到 M5**（建议在 ts-prfo 加「弯曲起点不得出现 `escape … push`」3 行断言） |
| **LOW-4** `result%etemp` 无法区分「生效值 vs 设置值」 | 复核 33 任务 2；`tasks/ts.f90:172/207`，`engine/engine.f90:779-793` | **接受**（设计必然：CLI 上二者恒等；已由「字段未赋值」+「值未到计算器」两类断言覆盖，报告 32 §2 末段已披露） |
| **LOW-5** 报告 32 §3.1「充分条件」方向不严格 | `32-m4-final-fix-report.md` §3.1 | **接受**（**仅措辞**：代码/PLAN §9.5/单测写的是反方向「`Σf² ≤ margin(margin−bmin)` ⟹ 无根」，正确；报告那句方向不严格） |
| **LOW-6** 逃逸未进 `xtbts.log`，无法仅凭日志复现 | `tasks/ts.f90:476`（自称「the file alone documents the run」）、`:477-536`（`write_ts_files`） | **推迟到 M5**（建议加一行 `escape step: <f12.6> bohr`） |
| **INFO-1** `m4-final-fix-data/escape/` 为空目录 | 报告 32 §9 | **已修**（本轮删除该空目录；`m4-final-fix-data/` 现为 acceptance/debug/injections/m3/med2） |
| **INFO-2** 两处清单证据未落盘 ((a) hlow 对比；(b) Δf 6 位小数) | 报告 32 §5 第 5/6 项 | **接受**（本轮 M3 回归用**逐字节 diff** 替代：`m3/*` vs 已记录 `m4-final-fix-data/m3/*` 的 `eigval/TR/internal` 行 = **0 diff**，见 `validation.txt`；落盘谱只有 2 位小数，6 位小数仍不可独立复现） |
| **INFO-3** `eigenfollow.f90:173-176` docstring 旧句式 | `saddle/eigenfollow.f90:173-176` | **推迟到 M5**（措辞，无功能影响；同 docstring 下文 `:178-188` 已纠正） |
| **INFO-4** PLAN §6.3 与 `tasks/ts.f90` module doc 未提起点要求 | `docs/xtb-landscape-PLAN.md:861-905`（§6.3，失效模式表 `:874-876`）；`tasks/ts.f90:20-61` | **推迟到 M5**（文档；PLAN §9.5 / 报告 26/27/28/30 已写） |

---

## 5. 验证（原始输出：`m4-coverage-data/validation.txt`）

```
$ cmake --build /tmp/xtb-land/build -j            -> 0 error / 0 warning
$ OMP_NUM_THREADS=1 ctest -R landscape            -> 100% tests passed, 0 failed out of 51
$ OMP_NUM_THREADS=1 ctest -N -R landscape         -> Total Tests: 51
$ grep -oE 'add_test\("[^"]+"' ... | sort | uniq -d   -> (empty, no duplicates)
$ OMP_NUM_THREADS=1 ctest -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
                                                  -> 100% tests passed, 0 failed out of 12
$ xtb-tester landscape-vib                        -> 17/17 PASSED
   (was 16; +1 = linear-rigid-fallback)
```

**M3 已验收行为未回归**（生产逻辑零改动 + 实测）：

| 项 | 本轮重跑 | 判定 |
|---|---|---|
| CO₂/HCN `4 internal, 5 projected zero modes`（3N−5） | 是（`--lvib` 与 `--hess` 各一份） | 不变 |
| `linear molecule: T` | 是 | 不变 |
| 5 个精确零模（`eigval` 前 5 项 = `0.00`） | 是 | 不变 |
| `TR` 行（CO₂ `0.893E+25`、HCN `0.430E+25`） | `--lvib` 与 `--hess` **逐位相同** | 不变 |
| `eigval`/`TR`/`internal` 行 vs 已记录 M3 数据 | **0 diff lines**（4/4 文件） | 不变 |
| `--lvib` vs `--hess` 频率差 ≤0.004 cm⁻¹ | 落盘谱 2 位小数相同（记录值 0.0036/0.0023，见 INFO-2） | 不变 |

---

## 6. 改动文件

```
 M test/unit/test_landscape_vib.f90    +linear-rigid-fallback 用例（合成畸变线性 Hessian）
                                       +linear-saddle-imaginary 的数值/符号断言
                                       +rigid_body_basis / build_avoiding_linear_hessian 两个 fixture
 M docs/_landscape-recon/32-m4-final-fix-report.md   §5.2(e) 与 §8.1 订正（撤回 + 保留痕迹）
                                                     §6 弯曲 HCN 一行按实测订正
 M docs/_landscape-recon/30-m4-fix-report.md         §4 补记弯曲起点三个能量
 R docs/_landscape-recon/m4-final-fix-data/escape/   删除空目录（INFO-1）
?? docs/_landscape-recon/34-m4-coverage-fix-report.md（本文件）
?? docs/_landscape-recon/m4-coverage-data/           validation.txt / injections/ / m3/
```

生产源码 `src/landscape/**` **零改动**（`git diff` 中 `vib/modes.f90` 与轮次开始时逐位相同，
md5 `ef294656f05b53b88acbd50d218a50b5`）。

---

## 7. 残余风险

1. `linear-saddle-imaginary` 的 `-10566.03` 是**回归基线**（确定性重跑稳定）；换编译器/优化级别
   可能位移，容差 5 cm⁻¹ 是为稳健性留的。（数值来自 GFN2 数值 Hessian 的压缩 O–H 几何。）
2. `linear-rigid-fallback` 的 fixture 复刻了生产的私有刚体基例程；若生产实现改动而语义不变，
   复刻仍会**响亮**失败（这是期望行为，但需要维护者同步）。
3. 复核 33 的 LOW-2/3/6、INFO-3/4 按上表**推迟**，未在本轮处理。
4. 本轮**未**提交 git（按任务书，父会话统一提交）。
