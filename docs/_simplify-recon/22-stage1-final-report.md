# 22 — 阶段 1 最终微修报告（父会话四项裁定 R38）

> 修复对象：`docs/_simplify-recon/21-stage1-fix-report.md` §8 的四项「需父会话裁定」，父会话已逐条裁定
> （**不入册欠账、不重做已闭合项**）。
> HEAD = **a845def**；改动**未提交**；构建档位 `-O2`；构建目录 `/tmp/xtb-p1/build`；基线二进制
> `/tmp/xtb-p1v/head-build/xtb`（HEAD worktree，版本串已对齐）。
> 所有 xtb/ctest 带 `OMP_NUM_THREADS=1`；未跑全量 ctest；未提交 git；**未动核心层**；未引入 `--method`。
> 报告用中文。**本报告所有数字都由本轮命令重新产生**（修订号 **R38**，见 `11-cli-redesign.md` 的修订记录）。

---

## 0. 结论摘要

| 裁定 | 处置 | 状态 |
|---|---|---|
| **1** §17.1 爆炸半径入册 | `11-*.md` §10 **C 类新增 C8**；C 7 → **8**，总计数 17 → **18**；全部计数口径同步（§10 头部 R38 补丁行、§10 汇总行、§10 末 R29/R35 订正、§17.1 新增一行、修订记录 R38 行） | **已落地** |
| **2** D4 不改代码 | `11-*.md` §8.3 的 D 清单 + §17.3 标题/清单写明 **D4 无代码变更**（双向扫描 = M2 有意的滞回自检；关切由 D1 的 `--lscan-fc` 回显 + M2 滞回文档覆盖）。**`src/` 零改动** | **已落地** |
| **3** 修 M2 剩余 5 处库入口字面比较 | 5 处全部改用 `landscape_lowercase`（小写输入行为不变）；**新增 5 条单元用例**，每处一条；**每处一个反向突变（红 → 还原 → 绿）** | **已落地** |
| **4** 让 IRC 的 `hessian_source` 可观测 | `tasks/irc.f90` 启动 banner 新增生效 `Hessian source:`（与 scan/opt/ts/vib 同格式）；**默认打、显式也给**（生效值，非危险默认）；3 条断言路线 + 反向突变。**额外收获：零覆盖 R1 也由此关闭** | **已落地** |
| 最终状态 | 构建 **0 error**；`ctest -R landscape` **118/118**；回归子集 **12/12**；CMake/meson 重名 **0**；集合 S 差集 **0**；**BC-4 逐位不变** | 全绿 |

**零覆盖清单：从 4 条降到 3 条**（R1、R2 关闭；只剩 2 条既有欠账 + 1 条 CLI 不可达的格式缺陷），见 §3。

---

## 1. 裁定 1（文档）：§17.1 的爆炸半径入册为 C8

**裁定**：`select_runtyp` 把「首选项静默获胜」变成**响亮错误** ⇒ 这是**行为变更**，必须登记。

**落地**（`docs/_simplify-recon/11-cli-redesign.md`）：

- §10 **C 类新增 C8**：`--lopt --lscan` / `--opt --hess` / `--lopt --lscan --lts` / `--sp --lopt-engine bfgs`
  同给 ⇒ `env%error`（exit 1，消息**点名第二个旗标**）；含现象（`--sp --lopt-engine bfgs` 由 **0 → 1**、
  `--lopt --lscan` 由「跑 `--lopt`」→ error）、影响对象、**爆炸半径**（仓库内双 runtype 组合 0 命中、
  `ctest -R landscape` 118/118 与回归 12/12 全绿）、缓解（拆两条命令 / `--ohess`；`--lopt-engine` 等
  子选项只隐含同一 runtyp，重复选择不报错）、可避免（与 C1–C7 同根）。
- **计数口径全部更新**：C 类 **7 → 8**，总计数 **17 → 18**。
  - §10 头部：「**R38 补丁**：新增 C8 … 总计数 17 → **18**（本节的汇总行是唯一权威口径）」；
  - §10 汇总行：`A 3 + B 0 + C 8 + D 1 + E 1 + F 4 + G 1 = 18 条`；
  - §10 末的 R29/R35 注：**R38 订正**——原「候选 C8」已被占用（U17 若采纳只能是 C9），当前总数已是 18；
  - §17.1 表格新增一行「**R38：爆炸半径已入册**」；
  - 修订记录：新增 **R38** 行，标题 `修订记录（R1..R28）` → `（R1..R38）`。

**证据**（`grep`，本轮实测）：

```
$ grep -n "C8（R38" docs/_simplify-recon/11-cli-redesign.md          # 1 命中（§10 C 类）
$ grep -n "C 8 + D 1" docs/_simplify-recon/11-cli-redesign.md        # 1 命中（汇总行）
$ grep -n "R38" docs/_simplify-recon/11-cli-redesign.md              # 头部补丁行 / C8 / 汇总 / R29 注 / §17.1 / §17.3 / §17.7 / 修订记录
```

> **说明（父会话状态描述的一处订正）**：裁定 1 是**纯文档**动作——`select_runtyp` 的行为在阶段 1 A 组
> 就已是现在的样子，本轮没有碰 `main.F90` 的任何一行（本轮唯一一次 `main.F90` 编辑是 §2 的反向突变，
> 已还原并 `grep` 确认）。

---

## 2. 裁定 2（文档）：D4 不改代码

**裁定**：`--lscan` **默认双向**是 **M2 有意确立**的默认（双向扫描 = **滞回自检**），不是缺陷。

**落地**（两处文档都写明）：

- `11-*.md` §8.3 的 D 清单条目：`**D4 `--lscan` 默认双向（R38 裁定：无代码变更，见下面的注）**`，
  并在清单下方加一段 **R38 裁定**：双向扫描就是滞回自检（两份剖面在同一约束残差水平上一致才说明
  点数/内层收敛足以支撑结论；`docs/_landscape-recon/14-m2-validation-experiments.md`、`AGENTS.md` §6.8
  「滞回是收敛产物而非物理」），改成默认单向等于删掉自检；用户需要知道的「默认与上游不同」那一面
  由 **D1 的 `--lscan-fc` 回显**覆盖（需要单向时用 `--lscan-oneway`）；
  §17.3 的 D 列表自相矛盾（L7）由此正式关闭。
- `11-*.md` **§17.3 标题**：`（§8.3，清单 D1/D2/D3/D4/D7）` → `（§8.3，清单 D1/D2/D3/D7；**D4 无代码变更**）`，
  并在「内容」行写明 D4 不在本节及其理由。
- `21-stage1-fix-report.md` 新增 **§9「父会话裁定（四项）与落实」**（含本条与裁定 1），并在 §0/§3.1 加 R38 指向。

**代码影响：0**（`git diff --stat -- src` 里 D4 相关文件为 0；本轮 `--lscan` 只改了 banner 门的**大小写归一**，
不是双向语义）。

---

## 3. 裁定 3（代码 + 测试）：5 处库入口字面比较

**父会话驳回**「CLI 不可达 ⇒ 不做改动」：这些是**库级入口**，单元测试可直接以大写构造 settings 触达。

### 3.1 改动（全部为「归一化」，不改变小写输入的既有行为）

| # | 位置 | 原 | 现 | 单测 |
|---|---|---|---|---|
| 1 | `tasks/scan.f90:143`（relaxed 的 `--lscan-fc` banner 门） | `trim(settings%mode) == 'relaxed'` | `landscape_lowercase(settings%mode) == 'relaxed'` | `scan-task-mode-case` |
| 2 | `tasks/ts.f90`（曲率带重算门） | `can_tighten = trim(settings%hessian_source) == 'numerical'` | `can_tighten = landscape_ts_can_tighten(settings%hessian_source)`（新公开纯谓词，内部 `landscape_lowercase`） | `ts-can-tighten-case` |
| 3 | `tasks/vib.f90:147`（`file` 缺文件名的点名门） | `trim(settings%hessian_source) == 'file'` | `landscape_lowercase(settings%hessian_source) == 'file'` | `vib-hessian-case` |
| 4 | `saddle/prfo.f90:958`（`init_mode = force` 的初始过渡向量门） | `trim(settings_%init_mode) == 'force'` | `landscape_lowercase(settings_%init_mode) == 'force'` | `prfo-init-mode-case` |
| 5 | `saddle/dimer.f90:425`（`n_init` 选择） | `select case (trim(n_init))` | `select case (landscape_lowercase(n_init))`（`case default` 的错误文本仍回显用户给的拼写） | `dimer-axis-case` |

- 复用既有归一化入口 `landscape_lowercase`（`types/settings.f90:1151`，其文档注释正是「存储与比较必须同拼写」）。
- **唯一的 API 变化**：`tasks/ts.f90` 新增公开纯谓词 `landscape_ts_can_tighten(hessian_source)`。
  理由与既有 `landscape_ts_curvature_band_hit` 完全相同（那个谓词也是从 `confirm_saddle` 内部抽出来
  以便单测），本条的门原本内联在 1200 行的宏驱动里，不抽出就**没有可证伪的观测点**。它无副作用、无状态、
  只有一个 `character` 入参。

### 3.2 新单元用例（5 条，全在既有 suite 内，故测试条数不变）

| suite | 用例 | 断言（要点） |
|---|---|---|
| `landscape-scan` | `scan-task-mode-case` | 以 `relaxed` 与 `RELAXED` 各跑一次任务（原子索引越界使其在 banner 后立即停），`env%unit` 重定向到 scratch；两次都必须打印 `[NOTICE] --lscan-fc default` |
| `landscape-saddle` | `ts-can-tighten-case` | `numerical/NUMERICAL/NuMeRiCaL` → `.true.`；`model/MODEL/file/nonsense` → `.false.` |
| `landscape-saddle` | `prfo-init-mode-case` | `force` 与 `FORCE` 各跑一次 Mueller-Brown P-RFO（`printlevel=1`，max_steps 6）；两次输出都必须含 `transition vector from the largest gradient component:`，且步数相同 |
| `landscape-saddle` | `dimer-axis-case` | `FORCE` 与 `force` 的轴**逐位相同**、`RANDOM` 与 `random`（同 seed）的轴**逐位相同**；`BOGUS` 仍被拒且消息回显原拼写 |
| `landscape-vib` | `vib-hessian-case` | `file` 与 `FILE` 在缺文件名时都报**点名 `--lvib-hessian-file`** 的错误（大写拼写不再落到工厂的通用消息） |

新增的测试辅助：`test/unit/test_landscape_{scan,saddle}.f90` 各有一个私有 `read_unit_text(unit)`
（把 scratch unit 写的内容读回字符串；`rewind` 在前，故也可在读到底后再写一次）。

### 3.3 反向突变证据（5/5 红 → 还原 → 绿）

统一用 `/tmp/p1f/mut.py`（要求替换目标**唯一命中**，否则拒绝）施加，还原后再构建；
**还原用 `os.utime` 显式 touch**——实测 `shutil.move` 保留旧 mtime，会让 make 认为对象已最新而**跑在旧对象上**
（本轮第 2 次自捕缺陷：一次 `ts-can-tighten-case` 的「意外红」就是这么来的，已修正流程后重测）。

```
--- MUTATED (landscape-scan) ---
       ... scan-task-mode-case [FAILED]
  Message: the upper case mode did not reach the force constant notice
--- RESTORED (landscape-scan) ---
       ... scan-task-mode-case [PASSED]

--- MUTATED (landscape-saddle) ---
       ... ts-can-tighten-case [FAILED]
  Message: the upper case numerical source cannot tighten
--- RESTORED (landscape-saddle) ---
       ... ts-can-tighten-case [PASSED]

--- MUTATED (landscape-vib) ---
       ... vib-hessian-case [FAILED]
  Message: the upper case source does not reach the flag naming guard
--- RESTORED (landscape-vib) ---
       ... vib-hessian-case [PASSED]

--- MUTATED (landscape-saddle) ---
       ... prfo-init-mode-case [FAILED]
  Message: the upper case init_mode did not force the transition vector
--- RESTORED (landscape-saddle) ---
       ... prfo-init-mode-case [PASSED]

--- MUTATED (landscape-saddle) ---
       ... dimer-axis-case [FAILED]
  Message: the upper case force axis was rejected
--- RESTORED (landscape-saddle) ---
       ... dimer-axis-case [PASSED]
```

（命令：`/tmp/p1f/mutrun.sh <file> <old> <new> <suite> <pattern>`；每步都重新 `cmake --build` 并只跑该 suite。）

---

## 4. 裁定 4（代码 + 测试）：IRC 的 `hessian_source` 可观测

### 4.1 打印（`src/landscape/tasks/irc.f90`）

在 `--lirc` 的启动 banner（`printlevel > 0` 块、`restart policy:` 之后）新增：

```fortran
write(env%unit, '(1x,a,a)') "Hessian source:           ", &
   & trim(settings%hessian_source)
```

**与同类打印一致**：`tasks/{opt,sp,scan,vib,ts}.f90` 都是同一行式 `Hessian source:           ` + 设置值；
IRC 之前只打 `Hessian update:` / `restart policy:` / `electronic temperature:`。

**按 §17.3 的 banner 规则判定「默认打、显式也给」**：这条是**生效值**（`--lirc-hessian` 的存储值，
决定初始 Hessian 与重算用的是位移单点还是 Lindh-D2 模型），不是 §17.3 里那种「与上游默认不同的危险默认」。
§17.3 的抑制规则只针对「未显式给值时回显内建默认」，所以这里**不打 `[NOTICE]` 前缀、不做抑制**，
默认值 `numerical` 与显式值都打。这一点写进了代码注释与 §17.7 的设计记录。

### 4.2 测试（3 条路线 + 1 个新 enum 组）

`test/unit/landscape_cli_check.py::check_echo` 新增 `require` 机制（路线级「必须出现在输出里的字符串」），
CMake 与 meson **同一实现**（CMake 侧经 `landscape_cli_py.cmake` 调用同一脚本）：

| 路线 | 参数 | 断言 |
|---|---|---|
| `lirc` / `default` | `--lirc --lirc-max-steps 1` | 里程碑 + `[NOTICE] --lirc-method default` + **`Hessian source:           numerical`** |
| `lirc` / `explicit` | `… --lirc-method gs` | 里程碑 + 无 `[NOTICE] --lirc-method` + **`Hessian source:           numerical`** |
| `lirc` / `hessian`（新） | `… --lirc-hessian model` | 里程碑 + **`Hessian source:           model`**（反映显式值） |
| `enumcase` / `lirchessian`（新） | `--lirc-hessian NUMERICAL --lirc-restart WARM` vs `… numerical … warm` | 退出码相同、结果文件 `irc.log` 逐位相同、输出含 `Hessian source: +numerical` |

> **为什么 `lirchessian` 用 `numerical` 而不是 `model`（实测事实，必须记下）**：
> 这条 fixture（弯曲 HCN 猜测）在 `--lirc-hessian model` 下 TS 确认得到 **0 个虚频**、任务在写 `irc.log`
> 之前就以 `the input geometry is a minimum` 退出（exit 1，**不写任何文件**），`compare_enum_case` 的
> 「结果文件必须存在且逐位相同」因此无对象；`--lirc-restart WARM` 是同一 fixture 上既有 `lircrestart`
> 组用的同一个手段（warm restart 让确认 Hessian 出现 1 个虚频，任务跑完并写文件）。用 `numerical`
> （= 默认值）仍然完整地测到「存储点归一」：去掉 `main.F90:3646` 的 `landscape_lowercase` 后，
> 大写路线会在 banner 里打印 `NUMERICAL`，正则不再命中（见 §4.3）。

### 4.3 反向突变证据（2/2 红 → 还原 → 绿）

**(a) 把打印的值改成硬编码常量**（`trim(settings%hessian_source)` → `'numerical'`）：

```
--- MUTATED (echo) ---
FAIL: lirc (hessian): 'Hessian source:           model' is missing from the output
--- RESTORED (echo) ---
（无输出，exit 0）
```

**(b) 去掉 `main.F90:3646` 的存储点归一**（`lircset%hessian_source = landscape_lowercase(sec)` → `= sec`）：

```
$ ctest --test-dir /tmp/xtb-p1/build -R landscape-enum-case
CMake Error at landscape_cli_enum_case.cmake:26 (message):
  lirchessian: the value did not reach the task
0% tests passed, 1 tests failed out of 1
# 还原后
1/1 Test #115: xtb/landscape-enum-case ..........   Passed
```

⇒ **零覆盖清单的 R1（`lircset%hessian_source` 归一化「行为上不可观测」）已关闭**：
21 号报告 §1.2 M3 的结论（「大写/小写的退出码/输出文件/stdout 全同，不存在能变红的断言」）在
**加上生效值打印之后不再成立**——这正是裁定 4 的目的。

---

## 5. 更新后的零覆盖清单

「零覆盖」= **宣称生效但没有任何测试能证明**。下表是本轮之后的**全部剩余项**（3 条，均有理由）。

### 5.1 剩余（有理由）

| # | 开关 / 字段 / 行为 | 读取处 file:line | 测试 | 理由 |
|---|---|---|---|---|
| R3 | `--lscan-expo`（`spring_expo`）生效性 | `main.F90:2438` → `relax_scan.f90:665` | **无** | **既有欠账**（复核 Z11，非阶段 1 引入；`spring_expo` 只影响距离约束，且 `relax_scan.f90:512` 的校验要求它 `> 0`） |
| R4 | `--lts` band 方法下 `escape from a minimum:` 措辞过宽 | `tasks/ts.f90:176-181` vs `saddle/prfo.f90:780` | **无** | **既有欠账**（复核 Z12 / 报告 B §8.4，band 方法 = 阶段后段） |
| R5 | banner `f4.2` 对 ≥10 的值溢出 `****` | `tasks/scan.f90:139`、`tasks/ts.f90:192` | **无** | **CLI 不可达**（显式给值即抑制 banner）；L2，已登记 |

### 5.2 本轮关闭（21 号报告 §3.1 的 R1/R2）

| # | 开关 / 字段 / 行为 | 读取处 file:line | 测试 | 反向突变 |
|---|---|---|---|---|
| ~~R1~~ → 关闭 | `lircset%hessian_source` 存储点归一 | `main.F90:3646` | `xtb/landscape-enum-case`（`lirchessian`）+ `xtb/landscape-lirc-default-echo`（`hessian` 路线，经新增的 banner） | `= sec` ⇒ 红；打印改硬编码 ⇒ 红 |
| ~~R2~~ → 关闭 | 5 处库入口字面比较 | `tasks/scan.f90:143`、`tasks/ts.f90:640`、`tasks/vib.f90:147`、`saddle/prfo.f90:958`、`saddle/dimer.f90:425` | 5 条新单元用例（§3.2） | 逐条回退 `trim(...)` ⇒ 5/5 红 |

> 「关闭」的判据与项目铁律一致：**每个改动都有一个能变红的测试**（§3.3、§4.3 的原始输出）。

### 5.3 已闭合项（21 号报告 §3.2 的 Z1–Z10 与本轮全部条目）

- Z1–Z10（banner 数值、`algorithm_was_set`、`--strict` 位置无关、4 个存储点归一、4 个 banner、`--raman`）、
  `ltset%hessian_source`、3+ 互斥 runtype、`scan1d` 模式 / `relax_scan` 校验门 / driver 的 model 种子：
  **保持关闭**（本轮完整重跑 `ctest -R landscape` = 118/118）。
- 本轮新增：5 条库入口单测（§3.2）、IRC `Hessian source:` 的 3 条路线断言 + 1 个 enum 组（§4.2）、
  `main.F90:3646` 的存储点归一（§4.3b）。

---

## 6. BC-4 结论（原生 runtype 输出文件逐位不变）

**方法**（与 `19-*.md` 的强基线一致）：基线二进制 = `/tmp/xtb-p1v/head-build/xtb`（HEAD worktree `a845def`
同配置构建，`--version` 实测 `6.7.1 (a845defedfebcea80f94f16e0e22e139dc44d400)`）；
把它的 `include/xtb_version.fh` 复制进本轮构建 → 重建（实测 `6.7.1 (a845def…)`）→ 用 `/tmp/xtb-p1v/bc4.sh`
在**同一目录路径**下只换二进制跑 4 个原生 runtype → 事后**把 `version.fh` 还原并重建**。

**结果（本轮实测）**：

| runtype | 文件清单 | raw `cmp` 差异 | 退出码 | stderr | stdout 过滤后差异 | 新 `NOTICE` |
|---|---|---|---|---|---|---|
| `--sp --norestart` | 3 = 3（逐字相同） | **0** | 0 = 0 | 相同 | **0 行** | **0** |
| `--hess --norestart` | 7 = 7 | **0**（含 `hessian`/`vibspectrum`/`g98.out`/`compliance.dat`） | 0 = 0 | 相同 | **0 行** | **0** |
| `--ohess normal --norestart` | 9 = 9（含 `xtbopt.xyz`/`xtbopt.log`） | **0** | 0 = 0 | 相同 | **0 行** | **0** |
| `--md --input md.inp`（`$seed 42`） | 55 = 55（含 `xtb.trj` + `scoord.1..49`） | **0** | 0 = 0 | 相同 | **0 行** | **0** |

- stdout 的 raw 差异行（28/30/66/28）全部落在 5 类已知非确定性字段上（`started/finished run on` 时间戳、
  `random seed`、计时表 `…sec`、`wall-time/cpu-time/ratio c/w`、`total power`）；按这 5 类过滤后 **4/4 runtype 差异 0 行**。
- **BC-4 成立**：本轮改动只落在套件路径（`src/landscape/*`、`src/xhelp.f90`）与 `main.F90` 的
  `--raman`/冲突判定（阶段 1 A 组，已闭合），4 个原生 runtype 的代码路径未被触碰。

---

## 7. 最终状态与可核命令

```
# 构建（档位 -O2）
$ cmake -S . -B /tmp/xtb-p1/build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"   # 已配置
$ cmake --build /tmp/xtb-p1/build -j 8                       # 0 error

# 套件测试（不跑全量）
$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p1/build -R landscape
100% tests passed, 0 tests failed out of 118                  # 与 21 号报告相同（新增覆盖在既有测试内部）
$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p1/build \
    -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
100% tests passed, 0 tests failed out of 12

# 重名（AGENTS §4：同名 add_test 会被静默丢掉）
$ grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d   # 空
$ grep -oE "test\('[^']+'" test/unit/meson.build | sort | uniq -d          # 空

# --help 双向一致（集合 S 门槛）
$ python3 test/unit/landscape_help_check.py src/prog/main.F90 src/xhelp.f90
dialect A: S(main) = 124, S(help) = 124, difference = 0
dialect A: N(implemented, undocumented) = 30 / N(documented, unimplemented) = 4
dialect B: S difference = 0, N = 34 / 6
PASS: set S is documented by `--help` in both dialects

# 本轮新增用例（suite 内，单跑可核）
$ cd /tmp/xtb-p1/build/test/unit
$ OMP_NUM_THREADS=1 XTBPATH=$PWD/../../../.. ./xtb-tester landscape-scan    | grep -E "scan-task-mode-case"
$ OMP_NUM_THREADS=1 XTBPATH=$PWD/../../../.. ./xtb-tester landscape-saddle  | grep -E "can-tighten|init-mode-case|axis-case"
$ OMP_NUM_THREADS=1 XTBPATH=$PWD/../../../.. ./xtb-tester landscape-vib     | grep -E "vib-hessian-case"

# CLI 路线（CMake 与 meson 同一 python 实现）
$ OMP_NUM_THREADS=1 python3 test/unit/landscape_cli_check.py echo \
    /tmp/xtb-p1/build/xtb <abs>/landscape_hcn.xyz /tmp/chk lirc
$ OMP_NUM_THREADS=1 python3 test/unit/landscape_cli_check.py enumcase \
    /tmp/xtb-p1/build/xtb <abs>/landscape_h2o.xyz /tmp/chk2 <abs>/landscape_hcn.xyz

# BC-4（强基线；版本串对齐后必须还原）
$ cp /tmp/xtb-p1v/head-build/include/xtb_version.fh /tmp/xtb-p1/build/include/xtb_version.fh
$ cmake --build /tmp/xtb-p1/build -j 8 && /tmp/xtb-p1/build/xtb --version | grep -a "xtb version"
$ bash /tmp/xtb-p1v/bc4.sh p1final /tmp/xtb-p1/build/xtb        # head 的 result 目录已在 /tmp/xtb-p1v/bc4/res/head
# 再截图对比（文件清单 / raw cmp / exit / stderr / 过滤 stdout），最后还原 version.fh 并重建
```

**本轮改动的文件**（在 21 号报告的清单之上）：

- `src/landscape/tasks/{scan,ts,vib,irc}.f90`、`src/landscape/saddle/{prfo,dimer}.f90`（裁定 3/4）
- `test/unit/test_landscape_{scan,saddle,vib}.f90`（5 条新用例 + 2 个 `read_unit_text` 辅助）
- `test/unit/landscape_cli_check.py`（`check_echo` 的 `require` 机制 + `lirc` 第 3 条路线 + `lirchessian` 组）
- `test/unit/CMakeLists.txt`（内联 enum 脚本新增 `lirchessian`）
- `docs/_simplify-recon/11-cli-redesign.md`（裁定 1/2 + §17.7 + R38）
- `docs/_simplify-recon/21-stage1-fix-report.md`（§9 父会话裁定 + §0/§3.1 的 R38 指向）
- `docs/_simplify-recon/22-stage1-final-report.md`（本报告，新）
- **`main.F90` 净改动 0 行**（仅一次突变 + 还原，`grep` 与 `ctest` 已确认）
- **核心层（`src/type`、`src/xtb`、`src/mctc`、`src/param`、`src/io`、`src/disp`、`src/coulomb`）0 改动**；
  未引入 `--method`；未改 runtyp 语义与 `--opt`/`--ohess` 分派。

---

## 8. 未验证 / 限制（凡无法核的都写明）

1. **meson 端到端未执行**（本机无 meson/ninja，AGENTS §4）。替代证据：两侧同步登记（`landscape_cli_check.py`
   是 CMake 与 meson 共用实现；`lirchessian` 在 CMake 内联脚本与 python 镜像里各一份，逐字对应）、
   python 检查器本体**直接执行通过**（`echo` 与 `enumcase` 均 exit 0）、测试名唯一。
2. **`enumcase` 的逐位比较对线程数敏感**（本轮实测：8 线程下 `upper-lopt/xtbopt.xyz` 与 lower 不同，
   `OMP_NUM_THREADS=1` 下相同）。这是**既有**性质（AGENTS §6.1），不是本轮引入；CMake 侧由
   `ENVIRONMENT "…;OMP_NUM_THREADS=1"` 固定，meson 侧由 `landscape_env` 固定。
3. **BC-4 的证据在 `/tmp`，仓库内不可重放**（I1）；§6/§7 给出完整命令与基线二进制路径。
4. **`lirchessian` 只能覆盖到「存储值」而不是「模型 Hessian 的实际执行」**：该 fixture 在
   `--lirc-hessian model` 下确认不到虚频（实测 0 个虚频、exit 1、不写文件），所以这条路线无法既跑完
   又使用非默认源。归因：`--lirc-hessian <非默认值>` 的**数值**行为不是本条的目标（目标是「存储拼写归一」
   与「生效值可观测」），两者都已可证伪。
5. **D4 的「危险默认」面仍未回显**（按裁定 2 是**有意**的）：`--lscan` 的双向性、`--lscan-oneway` 的
   存在只能从 `--help` 与文档得知。若日后要求回显，须作为新的设计项入册（会改 stdout ⇒ 行为变更）。
6. **裁定 1 是文档动作**：C8 登记的是阶段 1 A 组早已落地的行为，本轮未重新实测「所有 122 个套件拼写 ×
   任一 runtype」的全矩阵（§10 C5 的范围），只复跑既有冲突族 8 条测试与仓库 grep。
