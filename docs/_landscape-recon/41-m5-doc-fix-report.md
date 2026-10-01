# 41 — M5 文档/测试补丁轮报告（R2-M1 + R2-L1..L4/L6 + M6 接口记录）

> 输入：`40-m5-review-round2.md`（第二轮独立复核，结论＝有条件接受，CRITICAL 0 / HIGH 0 /
> **MEDIUM 1** / LOW 6 / INFO 4）、`39-m5-fix-report.md`、`37-m5-validation-experiments.md`、
> `docs/_landscape-recon/m5-fix-data/`、`m5-path-data/`、`AGENTS.md` §4/§5/§6。
> 角色：**修复者**（本轮**只改文档与测试**，未改任何 `src/landscape` 行为）。
> 纪律：所有 `xtb`/`ctest` 调用 `OMP_NUM_THREADS=1`；只跑 `-R landscape` 与回归子集，从未跑全量 ctest。
> 原始输出：`docs/_landscape-recon/m5-doc-fix-data/`（本轮新目录，见 §10）。

---

## 0. 结论摘要

| 项 | 处置 | 证据 |
|---|---|---|
| **R2-M1**（唯一 MEDIUM）`neb.f90` + PLAN 的 `1e-1` 收敛窗口 7↔13 互换 | **已修**，用**三份互相独立的原始数据**核实 | §1 |
| `neb.f90` 模块文档的其它实测数字（`0.37795` / `1.199e-1` / `5.686e-2` / `512`） | 三个可查，**一个数字写错**（`5.687e-2` 被写成 `5.686e-2`）→ 已改 | §1.4 |
| **R2-L1** `gsm.f90` 模块文档仍写「双前沿」生长 | **已修**（按代码改写；`closed` / `gap` 两处分量文档同步） | §2 |
| **R2-L2** `settings.f90:1066-1068` 称 `gsm` 「额外报告生长历史」 | **已修**，与 `settings.f90:244-248` 一致 | §3 |
| **R2-L3** `--lts-relax-ends` 断言不提 `\|g\|` 必须下降 | **已修** + 注入实测变红 | §4 |
| **R2-L4** 指向报告 39 的交叉引用章节号错 | **已修**（14 处，逐条核对） | §5 |
| **R2-L6** L-1/L-2 两处修复无永久测试 | **已补** 2 条测试，各注入实测变红 | §6 |
| R2-L5（数据文件名实不符）、INFO-1..4 | **记录，不修**（理由见 §7） | §7 |
| 交 M6 的两条接口事实 | 写入 PLAN §6.4 与本文 §8 | §8 |
| 已验收 M5 数字 | **全部不变**（§9） | §9 |

**本轮改动性质：纯文档 + 测试。** `src/landscape/path/neb.f90`、`gsm.f90` 与
`types/settings.f90` 的改动全部落在 `!>` 文档注释 / `!` 注释行内，**没有一行可执行语句变化**；
`src/landscape/tasks/ts.f90` 本轮**零改动**（两次注入后已按 md5 还原，§6）。

---

## 1. R2-M1：`max_displ = 1e-1` 的真实收敛窗口（唯一 MEDIUM）

### 1.1 复核指出的错误

`neb.f90:112-114`（修前）与 `PLAN §6.4:928-929`（修前）写：

> "with `max_displ = 1e-1` bohr 3, 5, 9, 11 and 13 converge while 7 and 15 do not"

### 1.2 回到原始数据（任务要求：不凭记忆）

我读了**三份独立原始文件**（不引用报告表格，直接读逐 n 输出）：

| 来源（文件路径） | 轮次 | 生成代码 |
|---|---|---|
| `docs/_landscape-recon/m5-path-data/unit-suite-landscape-path.txt` | 验证轮（报告 37） | M5 实现（**未经 M-2 修复**，无线搜索内核在 M5 起就是现在这个） |
| `docs/_landscape-recon/m5-fix-data/unit-suite-after.txt` | 修复轮（报告 39） | M-2/M-4 修复后 |
| `docs/_landscape-recon/m5-doc-fix-data/unit-suite-after.txt` | **本轮**（重跑） | 本轮工作区（M5 修复后 + 本轮文档/测试改动） |

`max_displ = 1e-1` 行逐 n 结果（字段：`converged` / `diverged` / `iter` / 势垒误差 kcal/mol）：

| n_images | `m5-path-data`（报告中） | `m5-fix-data`（报告 39） | **本轮重跑** |
|---|---|---|---|
| 3 | T / — / 11 / +0.0001 | T / F / 11 / +0.0001 | T / F / 11 / +0.0001 |
| 5 | T / — / 20 / +0.0002 | T / F / 20 / +0.0002 | T / F / 20 / +0.0002 |
| **7** | **T / — / 24 / +0.0000** | **T / F / 24 / +0.0000** | **T / F / 24 / +0.0000** |
| 9 | T / — / 37 / +0.0002 | T / F / 37 / +0.0002 | T / F / 37 / +0.0002 |
| 11 | T / — / 35 / +0.0000 | T / F / 35 / +0.0000 | T / F / 35 / +0.0000 |
| **13** | **F / — / 512 / +7.5e5** | **F / T / 397 / +8.4e4** | **F / T / 397 / +8.4e4** |
| 15 | F / — / 512 / +1.7e6 | F / T / 93 / +6.0e4 | F / T / 93 / +6.0e4 |

⇒ **真实集合＝ `1e-1` 时 3、5、7、9、11 像收敛；13、15 像发散**（三份数据完全一致；
`diverged` 列只是 M5 修复轮新增的提前终止诊断，不改变收敛判定）。
同一三份数据的 `0.37795`（默认）行是 3/5/9/11 收敛、7/13/15 发散，**没有变**。

### 1.3 这些数字确实来自本轮的实现（不是被否决的 (a) 变体）

复核担心错误值取自报告 39 §6.1 里**被实测否决的「有界增长」线搜索变体**（该变体那一行正是
"`1e-1` 界 3/5/9/11/13 收敛、7/15 发散"）。判定如下：

1. **被否决的 (a) 变体已被回退**，其数字只能来自报告 §6.1 的自述表格（无独立 artifact，复核
   R2-I4 已指出）；
2. 而 3/5/**7**/9/11 收敛、13/15 发散这组数字出现在**两份与 (a) 无关的 artifact** 里：
   `m5-path-data/unit-suite-landscape-path.txt` 是**M5 实现轮（未做线搜索实验）**的原始输出，
   与本轮**重跑**（当前工作区二进制）逐位一致；
3. 本轮重跑用的是 `band-initial-path-scan`（`test_landscape_path.f90:3123`，`set%max_steps = 512`
   的**同一份夹具**），其原始打印见 §10 的 `unit-suite-after.txt` 第 69-75 行。
   ⇒ **数字来自本实现，不是 (a)。**

**处置**：把 `neb.f90` 与 PLAN 两处都改成核实后的集合（两处逐字一致）：

```
... and with `max_displ = 1e-1` bohr 3, 5, 7, 9 and 11 converge while 13 and 15 do not ...
```

PLAN（§6.4）：「`max_displ=1e-1` 时 3/5/7/9/11 像收敛、13/15 像发散」。

### 1.4 `neb.f90` 模块文档的其它实测数字逐条核查（任务要求）

| 数字 | 原始出处 | 结论 |
|---|---|---|
| 默认界 `0.37795` bohr | `settings.f90:195,405` `max_displ = 3.7795e-1_wp`；扫描打印 `bound 0.378` | **可查，保留** |
| 初始 band 力 IDPP `f_rms_max = 1.199e-1` | `unit-suite-after.txt:60` `initial band idpp T f_avg 8.17302E-02 f_max 1.19936E-01` | **可查（1.19936e-1 → 1.199e-1），保留** |
| 线性插值 `f_rms_max = 5.686e-2` | `unit-suite-after.txt:61` `initial band idpp F f_avg 2.52372E-02 f_max 5.68717E-02` | **数字写错**（末位：实测 `5.687e-2`）→ **已改为 `5.687e-2`** |
| `512 iteration budget` | 扫描夹具 `set%max_steps = 512`（`test_landscape_path.f90:3123`）；发散运行 `iter 512`（`unit-suite-after.txt:59,255`） | **可查，保留** |

> 说明：`5.686e-2` 不是量级错误，是**末位舍入被截断**（5.68717 → 5.686）。报告 37 §4.2 与
> 测试注释都写 `5.7e-2`（两位有效数字），没有冲突。这里按任务要求「查不到的删除或重测」处理为
> 「查到实测值后改成实测值」。

---

## 2. R2-L1：`gsm.f90` 模块文档的「双前沿」生长 → 按代码改写

复核指出：`gsm.f90` 模块文档说生长是**两前沿**交替推进、两前沿相遇才停，而代码
（`landscape_string_grow:333-346`）是**单前沿**从反应物出发、距产物 ≤ 一个 spacing 即闭合；
同文件 `:298-306`（`landscape_string_grow` 的文档）自己已经写着「two-sided variant 已弃用，
`string_nnodes` 是 upper bound」⇒ 同文件自相矛盾。

**改法**（只动文档，零代码）：
* 抬头句改为「Three phases; the optimisation and the climbing node follow the publication,
  while the growth uses a **single frontier** from the reactant」；
* phase 1 重写为单前沿语义 + `string_nnodes` 是上界 + 双前沿被弃用的**实测**理由
  （NH3 上两条链松弛到不同方向、前沿间距恒为 1.4 bohr —— 与 `:298-306` 的既有文字一致）；
* 失效模式条目「a string that does not close」由「两前沿相距超过一个 spacing」改成
  「frontier 距产物超过一个 spacing」；
* `landscape_string_type%closed`（`:113`）由「True if the two frontiers met within one spacing」
  改成「True if the single frontier reached the product within one spacing」；
* `landscape_string_type%gap`（`:147`）由「Distance between the two frontiers」改成
  「Distance from the frontier to the product」。
* 代码事实核对：`string_frontier_distance(nodes, frontier, product)`（`:451-462`）就是
  `|frontier_node − product|`；`closed` 在 `:410` 置位；`gap` 在 `:381` 赋值 ⇒ 新文档与代码逐点一致。

---

## 3. R2-L2：`settings.f90:1066-1068` 的 `gsm` 说明

修前（`landscape_ts_method_is_string` 的文档）：

> "the `gsm` name selects the variant that **also reports the growth history**"

与 `main.F90:3223-3226`（`string_history` 的唯一写入者是 `--lts-string-history`）、
`main.F90:2506`（`--lts-method gsm` 只设 `climb`）以及**本轮 L-5 已改过的**
`settings.f90:244-248`（「`gsm` 目前只是别名」）矛盾。

**已改为**：`gsm` 目前是 `string` 的**别名**，只差打印的标题；生长历史由 `--lts-string-history`
对两个名字统一控制（report 38 L-5）。⇒ 两处文档现在一致。

---

## 4. R2-L3：`--lts-relax-ends` 的 CLI 断言补上「`|g|` 必须下降」

修前 `test/unit/CMakeLists.txt`（`xtb/landscape-path-cli` 段）：注释写「the printed gradient norm
has to drop」，但代码只断言「before / after 两行存在」⇒ 松弛变成 no-op 也会绿。

**已改**：分别捕获 reactant / product 的 before 与 after 两行 `|g|`，并断言

```
if(NOT REACTANT-G-AFTER LESS REACTANT-G-BEFORE) ... FATAL_ERROR
if(NOT PRODUCT-G-AFTER LESS PRODUCT-G-BEFORE)   ... FATAL_ERROR
```

（CMake `if(<a> LESS <b>)` 对 `es12.5` 形式数值做**数值**比较，已单独验证。）

**实测（`m5-doc-fix-data/relax-ends-cli.txt`）**：

```
 band: endpoint relaxation (reactant) before: E      -4.426199541332 Eh, |g|  3.82012E-03
 band: endpoint relaxation (reactant) after:  E      -4.426244036780 Eh, |g|  1.13954E-05
 band: endpoint relaxation (product) before: E      -4.426199541332 Eh, |g|  3.82013E-03
 band: endpoint relaxation (product) after:  E      -4.426244036780 Eh, |g|  1.14059E-05
```

与报告 39 L-11 声称的 `3.82e-3 → 1.14e-5` 一致（**现在有了永久断言**）。

**注入（`inject-C-relax-ends-ctest.txt`）**：把 `relax_one_endpoint` 里的
`call geometry_unpack(xfinal, geometry)` 改成 `geometry_unpack(x0, …)`（＝丢弃 M1 结果，
松弛成了 no-op）→ **只有** `xtb/landscape-path-cli` 变红：

```
CMake Error at landscape_cli_path.cmake:115 (message):
  the reactant relaxation did not lower the gradient norm: 3.82012E-03 ->
  3.82012E-03
 band: endpoint relaxation (reactant) before: ... |g|  3.82012E-03
 band: endpoint relaxation (reactant) after:  ... |g|  3.82012E-03
0% tests passed, 1 tests failed out of 1
```

还原后 md5 与注入前一致（`ts.f90 = fbcf8f3b3c40e3d87e5ca894d7adeea7`）。

---

## 5. R2-L4：指向报告 39 的交叉引用逐条核对

报告 39 的真实章节：§2 M-1、§3 M-2、**§3.4 间距放大后的生长停滞**、§4 M-3、**§5 M-4
（testpot root 守卫）**、**§6 F1/F2**（§6.1 试 (a)、§6.2 (b) 的三件交付）、§7 LOW/INFO、
§8 已验收数字（§8.2 NH3）、§9 运行验证、§10 改动风险与残余（编号 1..6）、§11 数据清单。
**没有 §6.3。** 原文引用的「section 5 / 5.1 / 5.2 / 6 / 6.3」全部落在 §5（M-4）或 §6（F1/F2）
上，与所述内容不符。

| # | 位置 | 引用内容 | 原引用 | 改为 | 依据 |
|---|---|---|---|---|---|
| 1 | `neb.f90:101` | 第 3 次迭代任何缩放都抬高力范数（NH3） | section 5 | **6.1** | §6.1 = 线搜索实测 |
| 2 | `test_landscape_path.f90:3027` | 无线搜索（band-divergence-guard 文档） | section 5 | **6.1** | 同上 |
| 3 | `test_landscape_path.f90:3091` | 单调线搜索使 band 停滞 | section 5 | **6.1** | 同上 |
| 4 | `test_landscape_path.f90:3032` | 13 像失败窗口夹具 | section 5.2 | **6.2** | §6.2 = (b) 交付含窗口 |
| 5 | `test_landscape_path.f90:3093` | LEPS 初始 band 力重测 | 39 section 5.2 | **39 section 6.2** | 同上 |
| 6 | `test_landscape_path.f90:3177` | 收敛配置下限 9 = 4+5 | section 5.2 | **6.2** | 同上 |
| 7 | `test_landscape_path.f90:2568` | AutoNEB 的 `max_displ` 实测 1e-2 | 报告 37 section 4.5 | **报告 37 section 4.7 (F2)** | §4.7 F2 就是 AutoNEB 继承 F1 的条目 |
| 8 | `gsm.f90:71` | 间距放大→停滞、回退重试 | section 6 | **3.4** | §3.4 = 「间距放大后的生长停滞（已修）」 |
| 9 | `gsm.f90:568` | 同上（`grow_frontier` 内注释） | section 6 | **3.4** | 同上 |
| 10 | `gsm.f90:79` | string 势垒与 band 差 0.012 kcal/mol | section 6 | **8.2** | §8.2 = NH3 已验收数字（string 6.0702） |
| 11 | `CMakeLists.txt:1651` | 重启文件级比较 2e-5 Å | report 39 section **6.3** | **report 39 section 10 item 4** | §6.3 不存在；L-12 的分辨率记在 §10 第 4 条 |
| 12 | `CMakeLists.txt:1715` | string 生长 8 步 / 10 节点 / 6.0702 | section 6 | **8.2** | 同 #10 |
| 13 | `CMakeLists.txt:1830` | 互校窗口 6.0825 / 6.0702 | section 6 | **8.2** | 同 #10 |
| 14 | `PLAN:924` | 第 3 次迭代抬高力范数 | 报告 39 §5.1 | **§6.1** | 同 #1 |
| 15 | `PLAN:927` | 两版线搜索都试过、窗口仍非单调 | 报告 39 §5.2 | **§6.2** | 同 #4（窗口表在 §6.2） |
| 16 | `PLAN:940` | 间距回退重试 | 报告 39 §6 | **§3.4** | 同 #8 |

（任务书说「11 处」；实际逐条扫出 **16 处引用、14 个不同位置**（`PLAN:924/927/940` 与
`gsm.f90` 三处的原文措辞各不相同）。上表按位置列出，全部已改。报告 37 §4.5 用于
`test_landscape_path.f90:3093` 的初始 band 力被复核判为「可接受」，保留。）

---

## 6. R2-L6：L-1 与 L-2 两处修复的永久测试（各注入实测变红）

### 6.1 L-1 → 新单元用例 `band-invalid-settings`

**测试**（`test_landscape_path.f90`，新子程序 + `collect_landscape_path` 注册）：对 4 个校验
分支各跑一次 `landscape_band_optimize`（每次先恢复一套合法基线，只注入该分支的缺陷）：

| case | 缺陷 | 期望 |
|---|---|---|
| 1 | `max_displ = 0` | `converged = .false.`、`images` 未分配、`message == "invalid band settings"` |
| 2 | `k_min = 0` | 同上 |
| 3 | `k_min=1e-1 > k_max=1e-2` | 同上 |
| 4 | `use_dynamic_k=.true.`, `k_decay = -1` | 同上 |

**修后实测**（`m5-doc-fix-data/unit-suite-after.txt`）：

```
  Starting band-invalid-settings ... (47/51)
   invalid-settings case  1  converged F  message: invalid band settings
   invalid-settings case  2  converged F  message: invalid band settings
   invalid-settings case  3  converged F  message: invalid band settings
   invalid-settings case  4  converged F  message: invalid band settings
       ... band-invalid-settings [PASSED]
```

**注入 A**（`inject-A-invalid-settings-unit.txt`）：把 `call band_settings_check(env, settings, fail)`
替换为 `fail = .false.`（四个分支同时失效）→ **50 PASSED / 1 FAILED**，唯一红的是新用例：

```
  Starting band-invalid-settings ... (47/51)
   invalid-settings case  1  converged F  message: band reached the iteration limit without converging
       ... band-invalid-settings [FAILED]
  Message: a band with invalid settings evaluated its images
```

⇒ 该分支此前**零覆盖**（复核 R2-L6 成立），新用例真的抓得到。还原后 `neb.f90` md5
`e2a1cec37af524da2fa4e9c33f8c4373` 与注入前一致。

### 6.2 L-2 → 新 CLI 用例 `xtb/landscape-path-autoneb-depth-limit`

**测试**（`test/unit/CMakeLists.txt`，`cmake -P` 脚本，沿用 M5 的 `--lts` CLI 测试写法）：
`--lts-method autoneb --lts-autoneb-max-depth 1 --lts-images 9`（末 stage 的 band 确实收敛 ⇒
exit 0），断言：

1. stdout 含 `autoneb: budget limit reached`（cap 真的触发）；
2. `landscape task terminated: stopped at the insertion depth limit max_depth = 1`（cap 进了
   `result%message`）；
3. `xtbts.log` 含 `termination: stopped at the insertion depth limit max_depth = 1`；
4. `xtbts.log` **不含** `termination: converged`。

**注入 B**（`inject-B-cap-message-ctest.txt`）：删掉 `landscape_ts_band` 里 cap 分支的
`result%message = auto%message`（`ts.f90:707-709`）→ 该测试变红：

```
CMake Error at landscape_cli_autoneb_cap.cmake:19 (message):
  the cap did not reach the result message
   landscape task terminated: converged
0% tests passed, 1 tests failed out of 1
```

⇒ 「修了但没守卫」的 L-2 现在可证伪。还原后 `ts.f90` md5 `fbcf8f3b…` 一致。

### 6.3 注册

* 单元用例：`test_landscape_path.f90` 的驱动清单 `collect_landscape_path`（`landscape-path`
  套件本身在 `test/unit/CMakeLists.txt:51`、`test/unit/meson.build:62`、`test/unit/main.f90:105`
  三处注册，未新增套件）；单元套件由 50 → **51** 用例。
* CLI 用例：`test/unit/CMakeLists.txt` 新增 `add_test("xtb/landscape-path-autoneb-depth-limit")`
  并加入 `OMP_NUM_THREADS=1` 属性列表（`set_tests_properties`，排在
  `xtb/landscape-path-autoneb` 之后）；**同时镜像到** `test/unit/meson.build`
  （新增 NH3 up/down 输入生成 + `test('landscape path autoneb depth limit', …)`）与
  `test/unit/landscape_cli_check.py`（新 mode `autonebdepth` + 校验函数）。
  镜像的写法沿用 `landscape_cli_check.py` 头部既有的「每个 mode 对一条 CMake 测试」约定；
  M5 的另外四条 `--lts` CLI 测试目前仍只在 CMake 侧（既有缺口，未在本轮扩大处理）。
  累计 CLI 测试数 69 → **70**。

---

## 7. 记录（不修）

| # | 内容 | 处置 | 理由 |
|---|---|---|---|
| R2-L5 | `m5-fix-data/unit-suite-49cases-before-new-tests.txt` 名实不符（内部是 **50** 用例、含 3 个新用例） | **接受，记录** | 纯归档文件的命名；真正的「49 用例（加入新用例前）」artifact 是 `injection-testpot-old-root-guard.txt`（见报告 39 §5 与 §11）。改名会牵动报告 39 §11 的引用，收益低于扰动 |
| R2-I1 | `landscape_testpot.f90:468-469` 的 "always returns a gradient in the level set of the energies" 过强（`dedr=dq` 只在对称方向精确） | **接受，记录** | 同一句的前半子句已正确限定 "exact along the symmetric directions"；纯措辞，无行为影响 |
| R2-I2 | `neb.f90:872` 注释 "two orders of magnitude above the largest transient" 实为 `1e3/4.4e1 = 22.7×`（≈1.35 个数量级） | **接受，记录** | 阈值本身（`band_divergence_factor = 1e3`）经复核正确，且它是文档与回归都引用的事实；仅注释的量级措辞偏乐观。**注意：此处与 R2-M1 无关**（同一文件、不同段）——本轮按任务书「只改数据与交叉引用」的范围未动 |
| R2-I3 | `test/unit/CMakeLists.txt:1776` 注释 "the measured difference is 0.10 kcal/mol" 已陈旧（现为 0.012） | **接受，记录** | 同文件 `:1809-1818` 的窗口与相邻注释已按 6.0825/6.0702 收紧；该行是历史对照说明，与实测值并存不产生误导 |
| R2-I4 | 报告 39 §6.1 对被否决变体的 `3.7e-3` 与报告 37 §4.4 的记法疑似量混用 | **接受，记录** | 该变体（有界增长线搜索）已整体回退，无 artifact 可复核；M6 若重做线搜索必须重测，见 §8 |

---

## 8. 交 M6 的两条接口事实（复核交代）

两条都已写进 **PLAN §6.4「M5 结案后的实测边界」**（第 3、4 条）：

1. **string 的默认力判据在分子面上不可达** ⇒ `string%converged` **不得**被 M6 用作「起点是否
   可用」的判据。PLAN §6.4 第 3 条现已显式写出（原来只说「IRC 不应把 `string%converged`
   当作起点可用性的判据」；本轮补上「默认力判据（`3e-4`/`1e-3`）在分子面上不可达」这一事实）。
   实测依据：报告 39 §9.2（默认阈值下 string 非收敛、exit 1）与本轮 CLI 测试显式放宽到
   `1e-3`/`2e-3`。
2. **`neb` / `cineb` 不写 `path_ts_list.xyz`** ⇒ 只有 **AutoNEB**（每 stage 一帧）与
   **string/GSM**（最终路径的内部局部极大）写该文件；plain NEB / CI-NEB 只写 `path.xyz`。
   PLAN §6.4 第 4 条新增该条并写明「M6/M7 任何消费 `path_ts_list.xyz` 的流程都必须容忍
   NEB/CI-NEB 运行后该文件不存在」。代码依据：`tasks/ts.f90:1233`（写入点）只在
   AutoNEB 与 string 分支被调用；交付物清单 PLAN `:819`/`:1312` 已按方法区分。

---

## 9. 验证（全部 `OMP_NUM_THREADS=1`）

### 9.1 ctest / 回归 / 重名 / 单元

```
$ ctest --test-dir /tmp/xtb-land/build -R landscape
100% tests passed, 0 tests failed out of 70          Total Test time = 3.13 sec

$ ctest -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
100% tests passed, 0 tests failed out of 12

$ xtb-tester landscape-path        → 51 PASSED / 0 FAILED（原 50 + band-invalid-settings）
$ ctest -N -R landscape | tail -1  → Total Tests: 70（原 69 + autoneb-depth-limit）
$ grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d   → 空
```

原始输出：`m5-doc-fix-data/{ctest-landscape-after.txt,ctest-regression-after.txt,unit-suite-after.txt}`。

### 9.2 「不得弄坏」的已验收 M5 数字——**全部不变**

LEPS（解析面，`unit-suite-after.txt`）：

| 方法 | 本轮 | 验收值 |
|---|---|---|
| NEB（9 像） | 8.9985，**+0.0000** | +0.0000 |
| CI-NEB（9 像，点火 iter 31） | 8.9985，**+0.0000** | +0.0000 |
| AutoNEB（5 stage / 9 像） | 8.9981，**−0.0004** | −0.0004 |
| String/GSM（well-side 端点） | 6.7972，**+0.0003** | +0.0003 |
| P-RFO（M4） | **+0.0000**，`r12/r23 = 1.505269` | +0.0000 |

NH3（GFN2 反转，CLI，`nh3-cli-barriers.txt`）：

| 方法 | 本轮 | 验收值 |
|---|---|---|
| NEB（9 像） | **6.0825** kcal/mol | 6.0825 |
| CI-NEB（9 像） | **6.0825** | 6.0825 |
| AutoNEB（9 像） | **6.0823** | 6.0823 |
| String/GSM（10 节点，生长 8 步，559 次评价） | **6.0702** | 6.0702 |

### 9.3 可证伪性注入（3 次，全部还原并核对 md5）

| 注入 | 目标测试 | 结果 | artifact |
|---|---|---|---|
| A：禁用 `band_settings_check`（`fail = .false.`） | `landscape-path / band-invalid-settings` | 50 绿 / 1 红 | `inject-A-invalid-settings-unit.txt` |
| B：删掉 cap → `result%message` 传播 | `xtb/landscape-path-autoneb-depth-limit` | 1 红 | `inject-B-cap-message-ctest.txt` |
| C：`relax_one_endpoint` 丢弃 M1 结果 | `xtb/landscape-path-cli`（relax-ends 断言） | 1 红 | `inject-C-relax-ends-ctest.txt` |

还原后：`neb.f90 = e2a1cec37af524da2fa4e9c33f8c4373`、`ts.f90 = fbcf8f3b3c40e3d87e5ca894d7adeea7`
（与注入前逐位一致），70/70 + 12/12 + 51/51 重新全绿。

---

## 10. 数据清单（`docs/_landscape-recon/m5-doc-fix-data/`）

| 文件 | 内容 |
|---|---|
| `unit-suite-after.txt` | 本轮 `xtb-tester landscape-path` 51/51 全量原始输出（含 §1 的逐 n 窗口行） |
| `ctest-landscape-after.txt` / `ctest-regression-after.txt` | 70/70 与 12/12 原始输出 |
| `nh3-cli-barriers.txt` | NH3 上 NEB / CI-NEB / AutoNEB / String 的势垒行 |
| `relax-ends-cli.txt` | `--lts-relax-ends` 的 before/after `\|g\|`（§4） |
| `inject-A-invalid-settings-unit.txt` | 注入 A：单元套件（50 绿 / 1 红） |
| `inject-B-cap-message-ctest.txt` | 注入 B：cap 消息传播（§6.2） |
| `inject-C-relax-ends-ctest.txt` | 注入 C：no-op 松弛（§4） |

---

## 11. 改动清单（本轮）

| 文件 | 改动 | 性质 |
|---|---|---|
| `src/landscape/path/neb.f90` | R2-M1 窗口数字改正；`5.686e-2` → `5.687e-2`；交叉引用 → §6.1 | **文档注释** |
| `src/landscape/path/gsm.f90` | R2-L1 双前沿 → 单前沿（phase 1、失效模式、`closed`、`gap`）；交叉引用 → §3.4 / §8.2 | **文档注释** |
| `src/landscape/types/settings.f90` | R2-L2 `gsm` 别名说明 | **文档注释** |
| `docs/xtb-landscape-PLAN.md` | §6.4 窗口数字、§5.1/§5.2/§6 → §6.1/§6.2/§3.4、新增第 4 条（`path_ts_list.xyz` 接口差异）、第 3 条补「默认判据不可达」 | 文档 |
| `test/unit/test_landscape_path.f90` | 新用例 `band-invalid-settings`（+注册）；6 处交叉引用 | 测试 |
| `test/unit/CMakeLists.txt` | relax-ends 前后 `\|g\|` 比较（R2-L3）；新 CLI 测试 `xtb/landscape-path-autoneb-depth-limit`（L-2）+ OMP 属性；3 处交叉引用 | 测试 |
| `test/unit/landscape_cli_check.py` | 新 mode `autonebdepth`（meson 镜像） | 测试 |
| `test/unit/meson.build` | NH3 输入生成 + `landscape path autoneb depth limit`（meson 镜像） | 测试 |
| `docs/_landscape-recon/m5-doc-fix-data/**`、本报告 | 原始输出与记录 | 数据 |

**未改动**：`src/landscape/tasks/ts.f90`（注入后已按 md5 还原）、`path/{cineb,string,autoneb,idpp}.f90`、
`tasks/ts.f90` 之外的全部生产代码、M0..M4 共享文件。`git status` 无 staged 文件；
**未执行任何 git 提交**。
