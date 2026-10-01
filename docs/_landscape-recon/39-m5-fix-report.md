# 39 — M5 修复轮报告（chain-of-states：NEB / CI-NEB / AutoNEB / String(GSM)）

> 输入：任务书（4 条 MEDIUM + F1/F2 + LOW/INFO）、独立复核
> `38-m5-independent-review.md`、验证轮 `37-m5-validation-experiments.md`、
> 实现轮 `35-*.md` / `36-*.md`、`AGENTS.md` §5/§6（尤其"注入必须先证明语义等价"的教训）、
> `docs/xtb-landscape-PLAN.md` §6.4/§7/§9.6/§12.12/§12.13。
> 角色：**修复者**（实现 + 自证；复核由独立会话进行）。
> 纪律：全部 `xtb`/`ctest` 调用 `OMP_NUM_THREADS=1`；只跑 `-R landscape` 与回归子集；
> 未跑全量 ctest。原始数据在 `docs/_landscape-recon/m5-fix-data/`。
> 输出纪律：最终回答 ≤25 行，细节在本报告。

---

## 0. 结论摘要

| 项 | 结果 |
|---|---|
| **M-1** `gsm.f90` 未初始化 `n_eval`（UB） | **修复**。入口 + 每次迭代 `n_eval = 0`；UB 以 `-finit-integer=-1` **实测证明**（§2） |
| **M-2** 首个生长节点的切线方向错 | **修复**。API 改为传对侧端点**几何**；修复前实测 `tau = unit(0 − R)`（偏差 0.63969 bohr），修复后 `= unit(P − R)`（0.00000）（§3） |
| **M-3** `neb.f90`/`cineb.f90` 文档说反 + 陈旧数字 | **修复**。按代码实际行为重写公式与方向；"实测"数字只保留报告 37 可查者；两处"文档说 A 代码做 B"成表（§4） |
| **M-4** `landscape_testpot.f90` root 守卫无效 | **修复**。守卫改为相对判据 + 提前分支，除零路径**真正消失**；新用例在旧守卫下红（NaN）（§5） |
| **F1/F2** band 无线搜索 → 收敛性对 `n_images` 非单调 | **(a) 被实测否决 → 按 (b) 结案**：(i) `diverged` 显式诊断（提前终止 + 非零退出）；(ii) 失败窗口写入模块文档与 PLAN §6.4；(iii) 回归测试（收敛计数下限 + `band-divergence-guard`）（§6） |
| LOW / INFO | L-1/L-2/L-3/L-4/L-5/L-7/L-8/L-9/L-10/L-11/L-12/INFO-4 修复；L-6/INFO-1/2/3 记录并接受（§7） |
| 测试 | `ctest -R landscape` **69/69**（+1 用例 +1 CLI）；单元套件 `landscape-path` **50/50**（+3）；回归 **12/12**；`ctest -N` = 69；`add_test` 无重名（§9） |
| 已验收 M5 数字 | LEPS 四路互校**不变**（+0.0000 / +0.0000 / −0.0004 / +0.0003）；NH3 NEB/CI-NEB **6.0825**、AutoNEB **6.0823** 不变；NH3 String/GSM **5.9789 → 6.0702**（M-2 的**预期后果**，与 band 的互校差 0.104 → **0.012** kcal/mol），TS RMSD **0.0265 → 0.0103 bohr**（§8） |
| 结论 | 4 条 MEDIUM + F1/F2 全部闭合；构建 0 warning；M0..M4 未受影响（唯一共享文件改动是本轮的文档注释，§10） |

---

## 1. 改动清单

| 文件 | 改动 |
|---|---|
| `src/landscape/path/gsm.f90` | M-2：`grow_frontier` 的第 7 形参 `integer other` → `real(wp) opposite(:, :)`（对侧端点几何）+ 形状守卫 + 文档；调用点改传 `product`；M-1：`landscape_string_climb` 入口与每次迭代 `n_eval = 0`；间距回退（被放大的间距松弛停滞时按请求步长重试一次）；L-9：删掉 `string%message = "unused"` 死代码，改为 `printlevel > 1` 的真诊断；L-4 的收敛说明 |
| `src/landscape/path/neb.f90` | M-3：模块文档（动态弹簧公式与方向 + 只用报告 37 数字）；F1/F2(b)：`band_divergence_factor` + `diverged` 提前终止、末尾重复 `max_displ`/`max_steps`、iter 0 表格行（F3）、模块文档的实测失败窗口；L-1：`band_settings_check`（`max_displ>0`、`k_min/k_max>0`、`k_min<=k_max`、动态 `k_decay>=0`）；`band_force_norm` 辅助函数 |
| `src/landscape/path/cineb.f90` | M-3：两阶段点火协议改为如实表述（本体系未复现失真 + 保留护栏的理由） |
| `src/landscape/path/string.f90` | L-10：重复句删除；`nu2` 明确标注"工程缺省、无文献标定"；样条实测值改为 `1.69e-4 / 4.91e-2`（自然样条 1.6e-1 指向报告 36 §7.5） |
| `src/landscape/path/autoneb.f90` | L-3：采用（restart）路径时校验 `size(initial_images,3) <= max_paths` |
| `src/landscape/tasks/ts.f90` | L-2：`cap_reached` 时把消息并入 `result%message` + `env%warning`；L-7：`--lts-product` 的警告文本列出全部路径方法 |
| `src/landscape/types/settings.f90` | F4：`climb_switch_rms` 的 5 位舍入写明；L-5：`gsm` 目前是 `string` 的别名（文档与行为一致）；L-10：`string_spline` 写 not-a-knot；INFO-4：string 用 `--lts-string-nnodes`（`--lts-images` 对它无影响） |
| `test/unit/landscape_testpot.f90` | M-4：root 守卫 |
| `test/unit/test_landscape_path.f90` | 新用例 `string-growth-start-direction`（M-2）、`leps-degenerate-gradient`（M-4）、`band-divergence-guard`（F1(b)(iii)）；`band-initial-path-scan` 收敛计数下限 = 实测 9 + `diverged` 一致性断言；文档更新 |
| `test/unit/CMakeLists.txt` | 新 CLI 用例 `xtb/landscape-path-autoneb-adopt-limit`（L-3）；`xtb/landscape-path-cli` 增加 `--lts-relax-ends` 断言（L-11）；autoneb restart 增加**文件级**逐帧比较（L-12）；string/CI-NEB 互校窗口收紧到实测值 ±0.05 kcal/mol（L-8）；注释里的 string 实测数字更新 |
| `docs/xtb-landscape-PLAN.md` | §6.4 追加"M5 结案后的实测边界"（band 窗口 + 线搜索否决 + M-2 后果 + string 力判据）；§9.6 追加修复轮结案段 |
| `docs/_landscape-recon/m5-fix-data/**`、本报告 | 原始输出与实验数据 |

**没有任何 `src/` 之外的核心层改动**；M5 的 M0..M4 共享文件（`types/coords.f90`、`types/settings.f90`
的 M5 部分）未被修改，`settings.f90` 的改动只是注释文本。

---

## 2. M-1：`gsm.f90` 未初始化 `n_eval`（UB，必修）

**代码**：`landscape_string_climb` 里 `integer :: k, nat, ndim, it, n_eval, ls`（`:823`）在
`:860` 被 `n_eval = n_eval + 1` 首次读取，`:872` 累加进 `string%n_eval`（用户可见的
`string: potential evaluations`）。修复：入口 `n_eval = 0`，并在每次 `it` 迭代开头重置
（旧代码把**累计**值每个迭代都加一遍 = 重复计数）。

**同类 `intent(out)` 路径核查**（任务要求）：`grow_frontier%fail`、`landscape_string_relax%fail`、
`frontier_step%n_eval/fail`、`evaluate_node%fail`、`landscape_string_refine%fail`、
`landscape_string_optimize` 的 `string%converged/message` 均在入口显式赋值；
`landscape_string_grow` 新增的对侧端点形状守卫也在入口置 `fail = .true.`。
`landscape_string_climb` 是唯一遗漏，已修。

**UB 实测**（命令与全部原始输出见 `m5-fix-data/m1-n_eval-experiment.txt`）：

```
code     | build                              | potential evaluations
---------+------------------------------------+----------------------
pre-fix  | (default Release)                  | 11246
pre-fix  | -finit-local-zero                  | 11246
pre-fix  | -finit-local-zero -finit-integer=-1| 11212   <-- UB：随构建改变
fixed    | (default Release)                  | 10685
fixed    | -finit-local-zero                  | 10685
fixed    | -finit-local-zero -finit-integer=-1| 10685
```

读法：
1. **修复前**同一个输入在两种构建下给出**不同**的 "potential evaluations"（11246 / 11212）⇒
   该值来自未初始化读取（UB），复核 M-1 的判定**被实测确认**。
2. **修复后**三种构建完全一致（10685）⇒ 计数器已确定。
3. 修复后的值比修复前低 **561（5.2 %）**，因为旧代码把迭代内的累计值反复相加
   （重复计数），所以报告 36 §7.3 引用的 645 并不是"645 次势能评价"。
   本报告**更正**该引用：本轮的 string 运行为 **559**（复用 CLI 设置）。
4. 如实记录：`-finit-local-zero` 单独使用时**没有**改变数值（该栈槽恰好为 0），
   所以 UB 在本机上是"潜在"的；用 `-finit-integer=-1` 才暴露。另外
   `-finit-integer=<非零非 -1>` 会让**核心** xtb（`xtb h2o.xyz --gfn 2`）段错误，
   与 landscape 无关（既有问题），故只采用 `-1`。

---

## 3. M-2：首个生长节点的切线方向错（最高优先，必修）

### 3.1 修复前的证据（本轮核心产物）

**（a）旧逻辑的语义**：`grow_frontier(..., other, ...)` 文档写"对侧前沿的索引"，调用点传的是
`budget`（= `settings%string_nnodes`，一个计数）；`grown(3,nat,budget)` 以 `source=0.0_wp`
分配且首个生长步之前只写过第 1 帧，故 `nodes(:,:,budget)` 是**全零帧** ⇒ 首个生长节点的
`tau = normalize(0 − R)` 指向**坐标原点**。类型 integer→integer、索引在界内，完全静默。

**（b）先固定证据再修**：新增判别性单元用例 `string-growth-start-direction`（在**未修改**的
生产代码上运行）→ **红**，实测输出（`m5-fix-data/injection-zero-opposite-frame-unit.txt` 同一夹具）：

```
 Starting string-growth-start-direction ... (32/48)
  growth closed T  steps 1  unit(P - R)  -0.74741  0.66436  0.00000
  unit(0 - R)   -1.00000 -0.00000 -0.00000
  node direction  -1.00000  0.00000  0.00000  node - expected   0.63969
      ... string-growth-start-direction [FAILED]
  Message: the first growth node is not one spacing along unit(P - R)
```

即：**期望** `unit(P − R) = (−0.74741, 0.66436, 0)`，**实际** `(−1, 0, 0) = unit(0 − R)`，
节点位置偏差 **0.63969 bohr**，而旧代码**照常闭合**（`closed T`）——完全静默。

**（c）旧套件没有覆盖**：修复前 `xtb-tester landscape-path` = **47/47 全绿**（基线，见
报告 37 §6.2 与本轮开始时的运行）；把**全零帧**（与旧 `other = budget` 语义**逐位等价**：
同一个 `(3,nat)` 全零数组、同一调用点）注入**修复后**的代码 → 旧 47 个用例**全绿**，只有新
用例变红：

```
$ xtb-tester landscape-path   → 47 PASSED + 1 FAILED (string-growth-start-direction)
```

⇒ 复核 M-2 的"测试全绿但仍然错误"判定被实测确认，且**旧套件零覆盖**。

### 3.2 修复

* `grow_frontier` 第 7 形参改为 `real(wp), intent(in) :: opposite(:, :)`，文档写明
  "对侧**端点**的几何（bohr，`(3, nat)`）；单前沿生长时它**不在** `nodes` 里"，并在入口加
  形状守卫（`size(opposite,1)==3 .and. size(opposite,2)==size(nodes,2)`，否则 `fail`）。
  调用点改传 `product`（不是索引）。
* 语义：首个生长节点的切线 = `unit(P − R)`（模块文档与 `landscape_string_optimize` 的注释原本
  就是这么写的，现在代码一致）。

### 3.3 自证

| 状态 | 新用例 | 旧 47+ 用例 | 证据文件 |
|---|---|---|---|
| 修复前 | **红**（node − expected 0.63969 bohr） | 全绿 | §3.1(b)(c) |
| 注入"全零帧"（旧语义）到修复后代码 | **红**（同值） | 旧 47 个全绿 | `injection-zero-opposite-frame-unit.txt` |
| 修复后 | **绿**（`node direction = unit(P − R)`，`node − expected = 0.00000`） | 全绿 | `unit-suite-after.txt` |

**ctest 级注入**（`injection-A-ctest.txt`，69 项）：2 红 —— 单元套件
`xtb/landscape-path`（新用例）与 `xtb/landscape-path-string`（CLI 端到端；因为 M-2 改变了
NH3 string 的实测势垒，而 L-8 已把互校窗口收紧到实测值：旧值 5.9789 落在 `[6.02, 6.12]` 之外）：

```
cineb barrier 6.0825, string barrier 5.9789
  the string barrier 5.9789 is outside the expected window
```

**关键教训（注入等价性）**：本轮的注入是把 `opposite` 形参换成**显式的全零帧**（`allocate(..., source=0.0_wp)`），
它与旧代码 `other = budget` 选中的 `grown(:,:,budget)` **逐位等价**（同一形状、同一零值、
同一调用点、首步之前从未写过），并且两次运行的实测数字**完全相同**（node direction `(-1,0,0)`、
偏差 `0.63969`）——即先证明等价再解读"变红"（`AGENTS.md` §6 第 4 条教训）。

### 3.4 修复暴露的第二个缺陷：间距放大后的生长停滞（已修）

M-2 修正后 NH3 的 CLI string 运行**停滞**：`node 7` 处曲率条件把间距放大到上限
`2 ds = 1.0` bohr，`node 8` 在半径 1.0 bohr 的球面上**无下降方向**（`frontier_step` 的能量
线搜索全部失败）⇒ `landscape_string_grow` 报错（报告 38 预期"修完需重测 string 数字"）。
实测（`--lts-string-nu2 1e6`，即关掉放大条件）：间距保持 0.5 bohr 时节点 2…13 全部正常放置，
说明**停滞来自被放大的半径**而不是新方向本身。

修复：`grow_frontier` 在间距被放大时，若在该半径上松弛停滞，则**按请求步长重试一次**
（`tau0` 保存初始切线；两次尝试都失败才报"growth stalled"）。文档写明单位与语义。
实测（`string.out`）：生长 8 步、10 节点、势垒 6.0702、`converged T`、exit 0。

### 3.5 gsm.f90 里其它"计数 vs 索引/帧"混用（任务要求逐条列出）

| 位置 | 用法 | 判定 |
|---|---|---|
| `gsm.f90:528` `left_prev >= 1 .and. left_prev <= size(nodes,3)` | 上界是 `grown` 的**容量**（budget）而不是已放置节点数 | **同类模式但良性**：调用方只传 `0` 或已放置索引；该比较只是越界守卫，分支由 `left_prev >= 1` 决定。新形参已消除它的后果；不额外改动（避免扩大 diff） |
| `landscape_string_grow` 的 `budget = settings%string_nnodes` | 容量（budget），与 `n_placed` 分开 | 正确；`while (n_placed < budget)`、`new_index = n_placed + 1`、`allocated(nodes, n_placed+1)` 都按计数用 ✓ |
| `interpolate_tail` 的 `n = size(nodes,3)` | 容量；`n_gap = n - n_placed` 填到**预算末尾** | 正确（紧邻前沿之后的帧本来就是零填充，模块文档已写明） |
| `landscape_string_refine(nodes, string_nnodes, ...)` | `budget` 是容量；`n_want = min(budget, 2n-1)` | 正确 ✓ |
| `landscape_string_optimize:248` `size(nodes,3) >= string_nnodes` | 计数 vs 容量 | 正确（"预算是上界"的语义）✓ |
| `highest_energy_node` / `string_finalise` / `landscape_string_climb` | 返回**内部**节点索引，且有 `k<1/k>n`、`k<2/k>size-1` 守卫 | 正确 ✓ |
| `landscape_band_measures(forces, skip, ...)` | `skip` 是索引（0 = 无） | 与 `neb.f90` 同一约定 ✓ |
| `string%spacing` | 长度而非计数 | 正确 ✓ |

---

## 4. M-3：算法文档与代码/实测相反（必修）

### 4.1 改了什么

* `neb.f90` 动态弹簧段：写清字面公式与**实际方向**：`dE_i = 0` ⇒ `k_i = k_min`；
  唯一抬升（`dE_i = dE_max`）⇒ `k_i = k_max − (k_max−k_min) e^{−decay}`
  （校准档 `k_min=1e-2, k_max=1e-1, decay=0.5` ⇒ `4.5e-2`），并说明这与直觉相反、
  与参考实现注释矛盾（报告 35 §2.3），**公式**才是契约（`dynamic-springs` 用例逐值钉住）。
* "实测"数字全部替换为**报告 37 可查**者：动态校准 48 步、动态 PLAN 初值 30 步、势垒误差
  < 1e-4 kcal/mol；静态 `1e-2` / `1e-1` 不收敛（误差 1.1e6 / 2.3e4 kcal/mol）、`1e2` 不收敛
  （5.8e5）、静态 `1e-5…1e-3`/`1`/`10` 收敛（31/30/31/37/43 步）；NH3 上静态两端也收敛（11/10 步）。
  删掉陈旧的 "28 步"、"`k_min <= 5e-3` 不收敛"、"`k >= 10` 不收敛"三个自相矛盾的数字。
* `cineb.f90` 点火段：改为"两阶段**护栏**保留，但**本体系未复现**过早点火导致的能量曲线失真
  （报告 37 §3.1(e)：LEPS 阈值 1.0 → iter 0 点火，势垒/几何/迭代数逐位相同；NH3 阈值 10.0
  同样）"，并给出保留护栏的**代码依据**而不是文献口号：CI 力把 **band 切线**当反应坐标，
  当初始路径是直线/IDPP 插值（HCN→HNC）时该切向不是路径方向，反号的平行分量可能把像推离鞍点；
  且点火后索引**冻结**，过早选择不可撤销。成本只是本来就要跑的 plain NEB 迭代。

### 4.2 "文档说 A、代码做 B"清单（任务要求成表）

| # | 位置 | 文档承诺 | 代码实际 | 处置 |
|---|---|---|---|---|
| 1 | `neb.f90:53-60`（修前） | 势垒顶拿 `k_min`、平台拿 `k_max` | 恰好相反（`dE=0` → `k_min`） | **已改文档**（§4.1） |
| 2 | `neb.f90:57-59`（修前） | 28 步收敛；`k_min≤5e-3` / `k≥10` 不收敛 | 48 步；`1e-5…1e-3` 全收敛；`k=10` 43 步收敛 | **已删改写**（§4.1） |
| 3 | `cineb.f90:31-35`（修前） | 过早点火使能量曲线失真 | 实测**未复现**（报告 37 §3.1(e)） | **已改文档**（§4.1） |
| 4 | `landscape_testpot.f90:458-461`（修前） | "never divides by zero" | 被守卫的分支执行 `ds/root = 0/0` → NaN | **已修代码**（§5） |
| 5 | `gsm.f90:269/446` vs `:323`（修前） | 首节点用 `unit(P−R)` | 实际朝坐标原点（0.63969 bohr 偏差） | **已修代码**（§3） |
| 6 | `settings.f90:266-270`（修前） | "`gsm` 任务名隐含生长历史报告" | `gsm` 只是别名（`string_history` 由 `--lts-string-history` 控制） | **已改文档**（L-5） |
| 7 | `settings.f90:262`（修前） | `string_spline` 用 **natural** 三次样条 | 实现与 `string.f90` 都是 **not-a-knot** | **已改文档**（L-10） |
| 8 | `string.f90:67-68`（修前） | 句子重复；样条误差写 2.4e-4 | 实测 `1.69e-4`（`string-spline-tangent`） | **已改文档**（L-10） |

---

## 5. M-4：`landscape_testpot.f90` 的 root 守卫（必修）

`leps_evaluate` 旧代码：`if (root > tiny()) then … else ds = 0` 之后**无条件**执行
`dedr = dq - ds/root` ⇒ `root == 0` 时 `0/0 = NaN`，与 `:458-461` 的"never divides by zero"
相反；且 `root` 只是**远小于** `|J|` 时（近等边 H₃）会放大抵消噪声。

修复：

```
   if (root > 1.0e-12_wp*maxval(abs(j))) then
      ds(...) = ...              ! 真实导数贡献
      dedr = dq - ds/root
   else
      ! 退化的交换积分：root 是它们与均值的偏差范数，此处不可导
      dedr = dq
   end if
```

守卫是**相对**的（相对 `max|J|`），并且在被守卫的分支里**根本不做除法** ⇒ 除零路径消失。
`else` 分支取 `dedr = dq`，它在**对称方向**（等边三角形的呼吸模）上是精确导数，文档已写明。

**新用例 `leps-degenerate-gradient`**：等边 H₃（边 1.9 bohr）的梯度必须有限并与呼吸模的中心差分一致：

```
   equilateral energy -3.18401E-02  max |gradient|  4.61442E-02
   dE/d(breathing) analytic   1.518558057249E-01  central difference   1.518558055063E-01
```

**自证**：把守卫改回旧形式 → 只有该用例变红，其余 **48/49 绿**（`injection-testpot-old-root-guard.txt`）：

```
  Starting leps-degenerate-gradient ... (2/49)
       ... leps-degenerate-gradient [FAILED]
  Message: the equilateral LEPS gradient is not finite
```

⇒ 该分支在旧套件里**零覆盖**，复核 M-4 成立。旧形式的注入是**逐行还原**（不是等价改写），
因此"变红"直接说明新旧逻辑可区分。

---

## 6. F1/F2：band 传播的收敛性对 `n_images` 非单调（MEDIUM）

### 6.1 先试 (a)：三种线搜索/接受判据的实测

任务要求"请优先尝试 (a)"，因此先实现并**测量**了三种方案（本轮的实测数据）：

| 方案 | 实现 | LEPS n=3..15 窗口 | NH3（真实体系） | 判定 |
|---|---|---|---|---|
| 单调回溯（band 力范数必须下降） | 2 段接受（严格下降 → 有界增长），最多 10 次减半 | — | **停滞**：第 3 次迭代在**任一**缩放因子下都抬高力范数（α=1.95e-3 时 +7.9e-5 相对），**连最陡下降方向也抬高**，而 band 仍高于判据 2.8 倍（`f_avg 8.46e-4` vs `3e-4`）；13/49 单元用例变红 | ❌ |
| 能量 Armijo（图像能量和下降） | 同一回溯结构，merit = `Σ E_i` | — | **停滞**：同一迭代实测 `Δmerit/Δα = +6.1e-5` 而 `g·d = −1.85e-3`（弹簧项不是能量梯度） | ❌ |
| 有界增长（每步 ≤ 4× 力范数，无单调要求） | 两段接受，第二段只要求 ≤ 4× | **仍非单调**：默认界 3/5/9/11 收敛、7/13/15 发散（11 从收敛变发散）；`1e-1` 界 3/5/9/11/13 收敛、7/15 发散 | 收敛（6.0825 ✓，11 步） | ❌（未达 (a) 的判据） |

**根因（实测）**：band 力场非保守（Eq.12 切向弹簧不是任何势的梯度），切向弹簧**必须**暂时抬高
力范数与能量才能重分布图像；因此"单调接受"会杀死 band 需要的那些步（NH3 停滞），
而"每步有界"会累积（4^n）而挡不住发散。⇒ **(a) 在本轮可实现的形态下无法使收敛性对
`n_images` 单调**；(b) 被选中。

**诚实记录**：有界增长版本确有两项改善（NH3 完全不变、LEPS 迭代 48→29、静态弹簧窗口从
"1e-2/1e-1/1e2 失败"变成"只有 1e2 失败"），但它不满足 (a) 的验收判据，且把
"对齐路径 == 参考路径"的逐像 RMSD 从 `9.5e-7` 推到 `3.7e-3` bohr（线搜索的边界分支使
两次运行的收敛分布分岔），会削弱一条已验证的 M5 不变量，故**回退**。

### 6.2 (b) 的三件交付

**(i) 显式非收敛诊断**（不静默返回最后一次迭代）：

* `landscape_band_type%diverged`：力范数超过 `band_divergence_factor = 1e3` 倍初值时**提前终止**
  （阈值比校准运行的最大瞬态 44 倍高两个数量级，实测 LEPS climbing 运行 `f_max` 峰值 5.34）；
* 提前终止的迭代数（实测，默认界）：n=7 → **322**（原 512）、n=13 → **390**、n=15 → **147**；
* 末尾报告重复 `n_images / max_displ / max_steps / diverged`（用户不必回滚日志头部）；
* 任何非收敛仍经 `env%error` ⇒ **非零退出**（原有行为，本轮确认：`--lts-method string` 默认阈值
  实测 exit 1）。

**(ii) 失败窗口写入文档与 PLAN**：`neb.f90` 模块文档新增"Propagation and its measured failure
window"段（含两张窗口数字、`diverged` 与迭代上限两种失败的区别、"循环未收敛的 band 从不返回
`converged = .true.`"的契约）；PLAN §6.4 追加"M5 结案后的实测边界"。

**(iii) 回归测试钉住窗口**：

* `band-initial-path-scan`：收敛计数下限从 `>= 5` 提到**实测 9**（两张界各 4/5 个），
  并断言 `diverged ⇒ not converged` 且 `diverged ⇒ n_iter < max_steps`；
* 新用例 `band-divergence-guard`：n=13 + 默认界，断言"要么收敛到解析势垒、要么被判为 diverged
  且在预算前停止"（**不**把"该配置必然发散"写成期望值，改进版传播仍能保持绿）；
* 注入实验（`injection-B-ctest.txt`，删掉提前终止）：**只有** `band-divergence-guard` 变红
  （"the band neither converged nor was diagnosed as diverged"）⇒ 诊断本身可证伪。

**实测收敛表（n=3..15，IDPP，512 步预算；修复后）**：

| n_images | 3 | 5 | 7 | 9 | 11 | 13 | 15 |
|---|---|---|---|---|---|---|---|
| `max_displ=0.378`（默认） | T 14 | T 19 | **F 322 (div)** | T 48 | T 60 | **F 390 (div)** | **F 147 (div)** |
| `max_displ=1e-1` | T 11 | T 20 | T 24 | T 37 | T 35 | **F 397 (div)** | **F 93 (div)** |

（T = 收敛且势垒 = 解析值 8.9985 ± 0.0002；F = 非收敛，`div` = 由 `diverged` 提前终止。
与报告 37 §4.2 的窗口**一致**，差别只在于失败运行不再跑满 512 步。）

---

## 7. LOW / INFO 逐条处置

| # | 位置 | 处置 | 证据 / 理由 |
|---|---|---|---|
| L-1 | `neb.f90` 弹簧/步长无校验 | **已修** | 新增 `band_settings_check`：`max_displ>0`、`k_min/k_max>0`、`k_min<=k_max`、动态时 `k_decay>=0`；在 kernel 层做（单元测试与 AutoNEB 直接调用它），错误经 `env%error` |
| L-2 | `autoneb` 截断时仍写 `converged` | **已修 + 实测** | `--lts-autoneb-max-depth 1`：exit 0（末 stage 的 band 确实收敛）、stdout 出现 `budget limit reached…`、`xtbts.log` 的 `termination:` 现在写 `stopped at the insertion depth limit max_depth = 1 with 6 of 9 images`（修前写 `converged`），并额外 `env%warning`（`autoneb_depth1.out`） |
| L-3 | adopt 路径不受 `max_paths` 约束 | **已修 + 新 CLI 用例** | 13 帧 restart 文件 + `--lts-autoneb-max-paths 10` → exit 1、消息 `the adopted AutoNEB path has 13 images, more than the hard limit 10`；新用例 `xtb/landscape-path-autoneb-adopt-limit`（脚本自建 18 帧文件，不依赖别的用例） |
| L-4 | string 默认阈值在分子面上不可达 | **已测 + 已写入文档与 PLAN** | 默认阈值（`3e-4`/`1e-3`）实测残差 `3.79e-4 / 1.05e-3` ⇒ `converged F`、**exit 1**（`string_default.out`）；CLI 用例显式放宽到 `1e-3/2e-3`；`gsm.f90` 模块文档与 PLAN §6.4 写明"IRC 不应把 `string%converged` 当作起点可用性判据" |
| L-5 | `gsm` 只是别名 | **已改文档** | `settings.f90` 明确"目前与 `string` 只差打印的标题"，行为与文档一致（不改行为，避免引入未评审的产品差异） |
| L-6 | `neb`/`cineb` 不写 `path_ts_list.xyz` | **接受，记录** | CI-NEB 的 climbing image 是最自然的候选，但 M5 的交付物清单（报告 37 §2.4）已按方法区分；M6 消费 `path_ts_list.xyz` 时须容忍这一点（PLAN §6.4 与报告 38 §5 已提示） |
| L-7 | `--lts-product` 警告文本不完整 | **已修** | 文本改为列出 `neb|cineb|autoneb|string|gsm`；CLI 用例只断言 `only used by`，实测仍绿 |
| L-8 | GSM/CI-NEB 互校无断言 | **已修** | CLI 的互校窗口收紧为 CI-NEB `[6.03, 6.13]`、string `[6.02, 6.12]`（实测 6.0825 / 6.0702 ±0.05）⇒ 0.1 kcal/mol 量级的回归会被抓住（注入 A 实测：旧 string 值 5.9789 → 变红） |
| L-9 | `string%message = "unused"` 死代码 | **已修** | 删除；改为 `printlevel > 1` 打印爬升节点移动后的重测力范数（真诊断，且不再覆盖 `climbing node did not reach…` 消息） |
| L-10 | `string.f90` 文案（重复句、natural vs not-a-knot、`nu2` 依据、2.4e-4） | **已修** | 见 §4.2 表第 7/8 行；`nu2` 标注为"工程缺省、无文献标定"，并说明 `string_spacing_cap` 才是可用性护栏 |
| L-11 | `--lts-relax-ends` 零覆盖 | **已修（新增 CLI 断言）** | `xtb/landscape-path-cli` 增加一次 `--lts-relax-ends` 运行，断言端点松弛前后两行（端点 |g| 3.82e-3 → 1.14e-5）与 band 收敛（6.1105 kcal/mol，相对**已松弛**端点；15 步） |
| L-12 | 重启"等价"只有内存级证据 | **已修（文件级）** | `xtb/landscape-path-autoneb` 现在把 `path_autoneb.xyz` 在重启前后做逐帧比较（归一化：阶段计数 `iter:` 与 4 位小数）。实测差异上界 **2e-5 Å**（Kabsch 对采用路径的重复对齐 + 文本往返），势垒差 1e-12 Eh ⇒ 逐位比较**不成立**，故按 1e-4 Å 分辨率断言，并在注释里写明测量。顺带记录：CMake 的正则引擎**不支持** `{n}` 量词（`[0-9]{4}` 静默不匹配），必须写 `[0-9][0-9][0-9][0-9]` |
| INFO-1 | `hessian_recalc` 语义改名 | **接受** | 已在类型文档与报告 35 §8 说明；本轮在 PLAN §12.12 的 M5 段一并留档（未上 CLI） |
| INFO-2 | CI 索引点火后冻结 | **接受** | 有一次性 warning + `n_climb_switch` 计数 + M3 频率确认兜底，非静默；`cineb.f90` 文档已写 |
| INFO-3 | `landscape_ts_count_frames` 迷你解析器 | **接受** | 只用于**拒绝**多帧输入，最坏是错误拒绝而非错误接受 |
| INFO-4 | 报告 36 §8 把 string 的节点数写成 `--lts-images` | **已改文档** | `settings.f90` 的 `string_nnodes` 文档写明 string **不用** `n_images`；`--lts-images` 配置 band/AutoNEB |
| F3 | 迭代表缺 iter 0 行 | **已修** | band 头部在表题后补打 iter 0 行（点火比较的就是该状态） |
| F4 | `climb_switch_rms` 5 位舍入 | **已改文档**（未改数值） | `settings.f90` 写明"存 5 位有效数字，精确值 `0.5 evtoau/aatoau = 9.7234532e-3`，相对差 5.5e-6"；不改数值以免使已验证的标定与 PLAN 引用失效 |
| F5 | string 力判据不是鞍点定位的代理 | **部分处置 / 其余推迟 M6** | 已在 `gsm.f90` 与 PLAN 写明"判据是节点力残差、不是候选质量"；逐节点残差输出（复核建议的完整方案）推迟到 M6 |
| F7 | `naive-tangent-kink` 是弱守卫 | **接受** | 真正的切线守卫是 `improved-tangent`（断言单调段 upwind 精确值）；报告 37 §5 已如实记录 |

---

## 8. 已验收 M5 数字的复测（任务要求"不得弄坏"）

### 8.1 LEPS（解析面，单元套件原始输出 `unit-suite-after.txt`）——**全部不变**

| 方法 | 修复后 | 报告 37 验收值 | 判定 |
|---|---|---|---|
| NEB（9 像） | 势垒 8.9985，误差 **+0.0000** | +0.0000 | 不变 |
| CI-NEB（9 像，点火 iter 31） | 8.9985，**+0.0000** | +0.0000 | 不变 |
| AutoNEB（5 stage / 9 像） | 8.9981，**−0.0004**，RMSD vs NEB 0.000407 bohr | −0.0004 / 0.000407 | 不变 |
| String/GSM（well-side 端点，32 节点） | 6.7972，**+0.0003** | +0.0003 | 不变 |
| P-RFO（M4） | `err/kcal +0.0000`，`r12/r23 = 1.505269` | +0.0000 | 不变 |
| `climb_switch` 点火迭代（1.0 / 3.472e-2 / 9.7234e-3） | **0 / 26 / 31** | 0 / 26 / 31 | 不变 |
| 静态弹簧标定表（1e-5…1e2） | 31/30/31/F/F/37/43/F | 同 | 不变（F1(b) 未改传播内核） |
| Müller-Brown band / AutoNEB | 60 步、105.7730、−0.2616 / 105.9350、−0.0996 | 同 | 不变 |
| `--lts-relax-ends`（NH3） | 15 步、6.1105 kcal/mol、exactly 1 虚频 | （新增覆盖） | — |

### 8.2 NH3（GFN2 反转，CLI，`m5-fix-data/*.out`）

| 方法 | 修复后 | 报告 37 验收值 | 判定 |
|---|---|---|---|
| NEB（9 像） | **6.0825** kcal/mol，11 步 | 6.0825 / 11 | **不变** |
| CI-NEB（9 像） | **6.0825**，11 步，climbing 5 | 6.0825 / 11 | **不变** |
| AutoNEB（5 stage / 9 像） | **6.0823** | 6.0823 | **不变** |
| String / GSM | **6.0702**（10 节点，生长 8 步，559 次评价） | 5.9789（8 节点，生长 6 步，645 次评价） | **变**（见下） |
| TS 几何：String/GSM vs CI-NEB | **0.010271 bohr/atom = 0.005435 Å** | 0.026489 / 0.026508（0.0140 Å） | **变（更好）** |
| TS 几何：AutoNEB vs CI-NEB | 0.000606 | 0.000606 | 不变 |
| TS 几何：String vs GSM | 0.000000 | 0.000000 | 不变 |

**为什么 String 的数字必须变**：M-2 修正了首个生长节点的切线方向（`unit(P−R)` vs `unit(0−R)`），
生长轨迹因此不同；NH3 上曲率条件把节点 7 的间距放大到上限 1.0 bohr，新轨迹需要再放一个节点
（即 §3.4 的停滞点），修复后为 10 节点 / 8 步。结果是：
1. 势垒 5.9789 → **6.0702**，与 band 的差从 **0.104 kcal/mol 降到 0.012 kcal/mol**；
2. TS 候选与 band 的几何 RMSD 从 **0.0140 Å 降到 0.0054 Å**；
3. 计数器修复（M-1）使 "potential evaluations" 从 645（含垃圾/重复计数）变为 559。

⇒ 这是**修正方向后的预期后果**，且两条独立路径（string/GSM 与 band）的一致性**更强**，
故不构成对 M5 验收的破坏：LEPS 四路互校、NH3 NEB/CI-NEB/AutoNEB、GSM vs CI-NEB 的
"同内核逐位一致"全部保持不变。CMake 的互校窗口已按新实测值收紧（L-8），并在测试注释里
写明改动原因与旧值。

---

## 9. 需运行验证清单（复核 38 末节）——逐条真实输出

### 9.1 ctest / 回归 / 重名

```
$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape
100% tests passed, 0 tests failed out of 69          Total Test time = 3.37 sec

$ OMP_NUM_THREADS=1 ctest -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
100% tests passed, 0 tests failed out of 12

$ xtb-tester landscape-path            → 50/50 PASSED
$ ctest -N -R landscape | tail -1      → Total Tests: 69
$ grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d   → 空
```

新增/变动的 ctest 项：`xtb/landscape-path-autoneb-adopt-limit`（新）、
`xtb/landscape-path-cli`（+relax-ends 断言）、`xtb/landscape-path-autoneb`（+文件级重启比较）、
`xtb/landscape-path-string`（窗口收紧）。单元用例：50 = 原 47 + `string-growth-start-direction`
+ `leps-degenerate-gradient` + `band-divergence-guard`。

### 9.2 `--lts-method string` 默认阈值（L-4）

```
$ xtb nh3_up.xyz --gfn 2 --lts --lts-method string --lts-product nh3_down.xyz \
      --lts-string-nnodes 16 --lts-max-steps 600 --norestart
exit 1
 string: relaxed in 1200 iterations, f_rms_avg  3.79346E-04, f_rms_max  1.04815E-03
 string: converged F
 landscape task terminated: the string reached the iteration limit without converging
```

⇒ 复核预期成立：默认阈值在该体系上**非零退出**（`path.xyz` 仍写出）。

### 9.3 `--lts-autoneb-max-depth 1`（L-2）

```
exit 0
 autoneb: termination stopped at the insertion depth limit max_depth = 1 with 6 of 9 images
 autoneb: budget limit reached: stopped at the insertion depth limit max_depth = 1 with 6 of 9 images
[WARNING] Runtime exception occurred
 termination: stopped at the insertion depth limit max_depth = 1 with 6 of 9 images   (xtbts.log)
```

⇒ 退出码 0（末 stage 的 band 收敛，保持不变），但 `xtbts.log` 的 `termination:` 不再谎称
`converged`，与 stdout 一致。

### 9.4 `-finit-local-zero` / `-finit-integer=-1` 对比（M-1）

见 §2 表（修复前 11246 vs 11212 = UB；修复后三构建均为 10685）。

### 9.5 全零帧（= 旧 M-2 语义）注入

见 §3.1(b)(c) 与 `injection-zero-opposite-frame-unit.txt`、`injection-A-ctest.txt`。

### 9.6 L-3

```
$ xtb … --lts-autoneb-restart <13 帧> --lts-autoneb-max-paths 10
exit 1
 the adopted AutoNEB path has 13 images, more than the hard limit 10 (--lts-autoneb-max-paths)
```

---

## 10. 改动风险与残余

1. **NH3 string 的势垒与几何**已变（§8.2）：这是 M-2 的直接后果，且与 band 的一致性更强。
   若复核认为"5.9789"本身是验收对象，请以本报告的测量为准重新冻结验收表。
2. **F1/F2 的根本修复（单调收敛）需要另一种传播内核**（例如 FIRE/damped MD 或弧长重参数化），
   本轮以 (b) 结案并在 PLAN §6.4 写明理由与实测证据；M6/M7 若实现需重测
   `neb-spring-calibration`、`band-spring-schedule`、`band-initial-path-scan` 三处标定。
3. **`-finit-integer=<非零>` 会让核心 xtb 段错误**（与 landscape 无关）：这限制了 UB 类实验的
   手段，本轮只用了 `-1`。
4. **`L-12` 的分辨率**：文件级重启比较只能到 1e-4 Å（实测差异 2e-5 Å，来自 Kabsch 对采用路径
   的重复对齐）。若要求逐位，需要让 `adopt_initial_images` 跳过重新对齐（行为改动，未做）。
5. **未测试路径**：string 生长停滞时的"两次尝试都失败"分支没有专门用例（NH3 的停滞现已被
   回退覆盖，但"回退也失败"没有夹具）。
6. L-6（`neb`/`cineb` 不写 `path_ts_list.xyz`）与 F5（逐节点残差）留给 M6。

---

## 11. 数据清单（`docs/_landscape-recon/m5-fix-data/`）

| 文件 | 内容 |
|---|---|
| `injection-zero-opposite-frame-unit.txt` | 全零帧（旧 M-2 语义）注入修复后代码的单元套件原始输出（47 绿 / 1 红 + 实测方向与偏差） |
| `injection-A-ctest.txt`、`injection-B-ctest.txt`、`injection-A-B-ctest.txt` | ctest 级注入（A = 零帧；B = 删掉发散诊断） |
| `injection-testpot-old-root-guard.txt` | 旧 M-4 守卫注入（48 绿 / `leps-degenerate-gradient` 红，NaN） |
| `m1-n_eval-experiment.txt` | M-1 的三构建 × 两版本 "potential evaluations" 表 |
| `unit-suite-after.txt` / `unit-suite-49cases-before-new-tests.txt` | 修复后 50/50 全量单元输出 / 加入新用例前的 49 用例输出 |
| `ctest-landscape-after.txt` / `ctest-regression-after.txt` | 69/69 与 12/12 原始输出 |
| `neb.out` / `cineb.out` / `autoneb.out` / `string.out` / `gsm.out` | NH3 上五种方法的 CLI 原始输出（势垒、虚频、迭代数） |
| `string_default.out` | L-4：string + 默认阈值 → 非收敛 + exit 1 |
| `autoneb_depth1.out`、`autoneb_adopt2.out` | L-2 / L-3 的实测输出 |
| `autoneb_one_shot_path.xyz` | L-12 的 one-shot 路径文件 |
