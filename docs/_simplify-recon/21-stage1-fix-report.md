# 21 — 阶段 1 收尾修复报告（复核 20 的全部 finding + 验证 19 的未验证项）

> 修复对象：`docs/_simplify-recon/20-stage1-review.md`（复核，0 CRITICAL / 2 HIGH / 5 MEDIUM / 7 LOW / 6 INFO）
> 与 `docs/_simplify-recon/19-stage1-validation.md`（独立验证）。
> HEAD = **a845def**；改动**未提交**；构建档位 `-O2`；构建目录 `/tmp/xtb-p1/build`。
> 所有 xtb/ctest 带 `OMP_NUM_THREADS=1`；未跑全量 ctest；未提交 git；未动核心层。
> 报告用中文。**本报告所有数字都由本轮命令重新产生**。

---

## 0. 结论摘要

| 项 | 状态 |
|---|---|
| H1（D3 `--lopt-engine` banner 零覆盖） | **已闭合**（新测试 + 反向突变） |
| H2（4 条新测试未固定 `XTBPATH`） | **前提被实测证伪**；仍按 finding 建议登记进环境名单 |
| M1（`--raman` 绕过 `select_runtyp`） | **已修**（`select_runtyp` 加 `apply` 可选参数 + CLI 冲突测试） |
| M2（校验侧归一、消费侧字面） | **部分修复**：3 处（有可证伪测试）已修；5 处库入口记录为欠账 |
| M3（归一化点/banner 数值零覆盖） | **已闭合**（enum-case 扩到 9 例 + 4 个 banner 断言数值）；1 处记录为不可观测 |
| M4（banner 只断言前缀） | **已闭合**（banner 串带数值/名字，另设 `absent` 前缀做抑制方向） |
| M5（`--strict` 位置无关性无测试） | **已闭合**（`--zzzz --strict` 断言 + 位置相关突变红） |
| L1..L7 / I1..I6 | 逐条处置见 §1.3 / §1.4 |
| 验证 19 §12「未做：3+ 互斥 runtype」 | **已补**（`xtb/landscape-runtype-conflict-triple`） |
| BC-4（原生 runtype 逐位不变） | **通过**：4 个 runtype 的**全部输出文件 raw `cmp` 0 差异**；stdout 仅 5 类非确定性字段 |
| 最终状态 | 构建 0 error；`ctest -R landscape` **118/118**；回归子集 **12/12**；CMake/meson 重名 **0** |

**最终零覆盖清单：不是空的**——剩 4 条**有明确理由**的项（1 条行为上不可观测、5 处库入口合并为 1 条、2 条既有欠账、1 条 CLI 不可达的格式缺陷），见 §3。**没有任何「宣称生效但无测试」的 CLI 行为残留**。

> **R38 更新（父会话四项裁定已落实，见 §9 与 `22-stage1-final-report.md`）**：
> 上面 4 条里的前两条（R1 不可观测、R2 五处库入口）**已关闭**（IRC 启动 banner 新增生效 `Hessian source:` 回显；
> 5 处全部归一化 + 5 条大写/小写等值单测）；D4 裁定**无代码变更**；§17.1 的爆炸半径已入册为 §10 C8。
> 当前剩余只有 2 条**既有欠账**（R3 `--lscan-expo` 生效性、R4 `--lts` band 措辞）与 1 条 CLI 不可达的格式缺陷（R5 banner `f4.2`），
> 而 §17.1/§17.2/§17.3/§17.4/§17.5 的全部实施项均已闭合。

---

## 1. 复核报告（20）逐条处置

### 1.1 HIGH

#### H1 — D3 `--lopt-engine` 默认 banner + `algorithm_was_set` 零覆盖（**已改**）

- **复核事实**：`tasks/opt.f90:121` 的条件改 `.false.` ⇒ 115/115 仍全绿；`grep -rn algorithm_was_set test/` = 0。
- **修复**：
  - `test/unit/landscape_cli_check.py` 的 `ECHO_CASES` 新增 `"lopt"` 组（默认 `--lopt` → banner 出现；`--lopt-engine cg` → 不出现），默认路线还带 `--ljson` 并解析 `landscape_opt.json`（`json_task` 由硬编码 `"scan"` 改为按组给出）。
  - `test/unit/CMakeLists.txt:3397` `add_test("xtb/landscape-lopt-engine-echo" ...)`；meson `test/unit/meson.build:491` `test('landscape lopt engine echo', ...)`。
  - 登记进 `ENVIRONMENT "XTBPATH=...;OMP_NUM_THREADS=1"` 名单（`CMakeLists.txt:3499`）。
- **反向突变（本轮实测）**：
  ```
  $ python3 /tmp/p1f/mut.py src/landscape/tasks/opt.f90 \
      'if (.not. settings%algorithm_was_set) then' 'if (.false.) then'
  $ cmake --build /tmp/xtb-p1/build -j 8
  $ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p1/build -R 'xtb/landscape-lopt-engine-echo' --output-on-failure
  FAIL: lopt (default): the builtin default was not echoed      -> 1/1 Failed
  # 还原后
  $ OMP_NUM_THREADS=1 ctest ... -R 'xtb/landscape-lopt-engine-echo'  -> 1/1 Passed
  ```
  同一次突变把 4 个 echo 测试一起打红（fc/lirc/lts 的失败原因是**数值断言**，见 M4）。
- **闸门字段 `algorithm_was_set`（复核 Z2）单独注入**：
  ```
  $ python3 /tmp/p1f/mut.py src/prog/main.F90 \
      '                  lset%algorithm_was_set = .true.' \
      '                  lset%algorithm_was_set = .false.'
  $ cmake --build ... && OMP_NUM_THREADS=1 ctest -R 'xtb/landscape-lopt-engine-echo' --output-on-failure
  FAIL: lopt (explicit): the notice was printed although the flag was given  -> Failed
  # 还原 -> Passed
  ```
  ⇒ **Z1 与 Z2 都有可证伪覆盖**。

#### H2 — 4 条新测试未固定 `XTBPATH`（**前提被证伪 + 仍按建议登记**）

- **复核前提**：「CI（`fortran-build.yml:117-121`）只设 `OMP_NUM_THREADS`，这 4 条测试会红」。
- **实测（本轮，复核 §13.1 指定的命令）**：
  ```
  $ env -u XTBPATH OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p1/build \
      -R 'xtb/landscape-(fc-echo|lirc-default-echo|lts-escape-echo|strict-unknown)'
  100% tests passed, 0 tests failed out of 4        # 期望「失败」= H2 成立，实际 4/4 通过
  ```
  机制证据（同轮）：`env -u XTBPATH ... xtb water.xyz --gfn 2 --lopt --norestart` 正常跑完并写 `xtbopt.xyz`
  （GFN2 参数编译进二进制；`XTBPATH` 只影响 `$HOME/.xtb` 类查找）。
  ⇒ **H2 的「CI 会红」结论不成立**，属「静态推断被实测证伪」（本方向第 13 次，其中父会话 6 次）。
- **处置**：仍按 finding 的**一致性**要求把这 5 条（含新 `lopt-engine-echo`）登记进
  `CMakeLists.txt:3499-3503` 的 `ENVIRONMENT "XTBPATH=${PROJECT_SOURCE_DIR};OMP_NUM_THREADS=1"` 名单，
  并在注释里写明「实测 `XTBPATH` 不必要，登记只为与同族测试一致」。**未放宽任何断言。**

### 1.2 MEDIUM

#### M1 — `--raman` 绕过 `select_runtyp`（**已改**）

- **复核事实**：`main.F90:2157 case ('--raman')` → `set_elprop('raman')` → `set_module.f90:1121 set_runtyp('hess')`；
  `--raman 0.5 1000 --lopt` 不报冲突、`--lopt` 被静默丢弃（§17.1 唯一 CLI 可达的洞）。
- **修复**（`src/prog/main.F90`）：
  - `select_runtyp` 增加可选参数 `apply`（`main.F90:3965-4003`，`logical, intent(in), optional :: apply`）；
    `apply=.false.` **只记录选择、不调用 `set_runtyp`**。
  - `case ('--raman')`（`main.F90:2157-2165`）改为
    `call select_runtyp(env, 'hess', '--raman', selected_runtyp, selected_runtyp_flag, apply=.false.)`，
    随后仍由 `set_elprop('raman')` 完成 `set_runtyp('hess')`。
  - **为什么用 `apply` 而不是直接调 `select_runtyp`**：`set_elprop` 自己会调 `set_runtyp`，
    若包装器先调一次，`set_module.f90:1034` 的 `save :: set1` 锁会再报一次
    "Runtyp already set and locked…"。`apply=.false.` 保证**`--raman` 单独使用时 `set_runtyp` 仍只被调用一次**
    （与改动前逐字相同），因此 tblite 构建里的受支持路径**不可能**因此改变。
- **测试**：`CMakeLists.txt:639` `xtb/landscape-raman-conflict`（复用 `landscape_cli_conflict.cmake`：
  非零退出 + 点名 `--raman` 与 `--lopt` + `run type conflict` + 未启动套件任务）；meson `meson.build:434`。
- **反向突变（本轮实测）**：删掉那句 `select_runtyp(...apply=.false.)` ⇒
  ```
  CMake Error at landscape_cli_conflict.cmake:14 (message):
    '--raman 0.5 1000 --lopt' does not name its first flag
    ...
    -1- prog_main: Raman activities are not implemented with this method
  ```
  （即「失败原因不是冲突」——正是缺陷本身）。还原 ⇒ Passed。
- **可达性实测（重要限制）**：本构建 `WITH_TBLITE=OFF`，`--raman 0.5 1000` 必然以
  `-1- prog_main: Raman activities are not implemented with this method` 结束；加 `--ptb` 则是
  `-1- PTB not available without 'tblite'`。因此本构建里 **`--raman` 无法跑完任何一次真实计算**，
  可验证的只有**解析期的冲突判定**。**未验证**：tblite 构建下 `--raman` 的完整运行路径
  （论证：`set_runtyp` 调用次数与顺序与改动前相同，故不应有行为差异）。

#### M2 — 大小写归一「校验侧通、消费侧不通」（**部分修复：3 处已改，5 处登记**）

- **已改 + 有可证伪测试的 3 处**：
  | 文件:行 | 原 | 现 | 测试 |
  |---|---|---|---|
  | `src/landscape/scan/relax_scan.f90:500` | `trim(settings%mode) == 'relaxed'` | `landscape_lowercase(settings%mode) == 'relaxed'` | 单元 `relaxed-mode-case` |
  | `src/landscape/scan/scan1d.f90:171` | `trim(settings%mode) == 'rigid'` | `landscape_lowercase(...) == 'rigid'` | 单元 `rigid-mode-case` |
  | `src/landscape/optimize/driver.f90:203` | `trim(settings%hessian_source) == 'model'` | `landscape_lowercase(...) == 'model'` | 单元 `model-source-case` |
  新单元用例：`test/unit/test_landscape_scan.f90:180-181`（`rigid-mode-case`、`relaxed-mode-case`）、
  `test/unit/test_landscape_optimize_xtb.f90:70`（`model-source-case`）。
- **反向突变（本轮实测）**：把 3 处改回 `trim(...)` ⇒
  ```
  Starting rigid-mode-case ...  ... rigid-mode-case [FAILED]
  Starting relaxed-mode-case ... ... relaxed-mode-case [FAILED]        # xtb/landscape-scan
  landscape model source: bfgs model seed 13 steps / 16
  landscape model source: bfgs MODEL seed 16 steps / 18
  ... model-source-case [FAILED]                                       # xtb/landscape-optimize-xtb
  ```
  还原后 `xtb/landscape-scan`、`xtb/landscape-optimize-xtb` 均 Passed。
- **一条实测订正**：`driver.f90:203` 的分支在**模块原夹具上不可观测**——
  `bfgs` 的 model 种子与 identity 种子都是 **6 步 / 7 个单点**（`minimize_water` 打印），
  所以测试改用**拉伸水**（`setup`/`minimize_water` 新增可选 `start`）：
  model 13 步/16 点 vs identity 16 步/18 点。**没有放宽断言**（新增的是更强的等值断言）。
- **未改、登记为欠账的 5 处**（同一族「校验侧归一、消费侧字面」）：
  | 文件:行 | 内容 | 为何不改 |
  |---|---|---|
  | `src/landscape/tasks/scan.f90:137` | `trim(settings%mode) == 'relaxed'`（banner 门） | CLI 在所有存储点归一（`main.F90:2335`），库入口路径不可观测；无红得起来的测试 |
  | `src/landscape/tasks/ts.f90:449` | `trim(settings%hessian_source) == 'numerical'` | 同上（`main.F90:2966` 归一） |
  | `src/landscape/tasks/vib.f90:144` | `trim(settings%hessian_source) == 'file'` | 同上；且大写时工厂会**响亮报错**，不是静默 |
  | `src/landscape/saddle/prfo.f90:955` | `trim(settings_%init_mode) == 'force'` | 同上（`main.F90:2772` 归一） |
  | `src/landscape/saddle/dimer.f90:425` | `select case (trim(n_init))` | 同上；且 `case default` **响亮报错**，不是静默错路 |
  理由：**铁律 1「每个改动都要有测试，且反向突变必须变红」**——这 5 处没有 CLI 可达的可证伪观测，
  改一行而没有能变红的测试，等于制造第 4 次「死旋钮/无覆盖」。已按 `file:line` 逐条登记（§3），
  建议阶段 2 在给库入口补测试时一并归一。

#### M3 — 归一化点零覆盖（**已闭合**）

- `test/unit/CMakeLists.txt:801` 的 `xtb/landscape-enum-case` 从 4 组扩到 **9 组**：
  `lopt`（既有）、`lscan`（既有）、`lts`（既有）、`prfo`（既有）、**`lscanhess`、`lvibhess`、`ltshess`、
  `ltsrestart`、`lircrestart`**（python 镜像在 `landscape_cli_check.py` 的 `check_enum_case`）。
- 函数签名加了**每例输入**（`compare_enum_case(label input result pattern upper lower)`）：
  `--lirc` 需要过渡态输入（水是极小点，任务在写 `irc.log` 前就中止），故 `lircrestart` 用 HCN 夹具
  （`-DINPUT2=${LANDSCAPE-HCN}`；`LANDSCAPE-HCN` 的创建已上移到 `LANDSCAPE-H2O` 之后、enum-case 之前）。
- **反向突变（本轮实测）**：一次性把 7 个归一化点改回未归一形式
  （`lset/lsset/ltset/lircset/lvset%hessian_source = sec`；`--lts-restart`/`--lirc-restart` 的 `select case (sec)`），
  用**每例单独**的 cmake 脚本（`mut_<label>.cmake`，从生成的脚本按 label 切出）逐例跑：
  ```
  lopt:        RED -> lopt: the value did not reach the task
  lscanhess:   RED -> lscanhess: the value did not reach the task
  lvibhess:    RED -> lvibhess: the value did not reach the task
  ltshess:     RED -> ltshess: the value did not reach the task
  ltsrestart:  RED -> ltsrestart: the value did not reach the task
  lircrestart: RED -> lircrestart: the upper case run exits 1, the lower case run 0
  ```
  还原后 `xtb/landscape-enum-case` Passed。
- **唯一无法证伪的归一化点**：`lircset%hessian_source`（`main.F90:3646`）。
  `--lirc-hessian MODEL` 的存储值只被 `tasks/irc.f90:208` 传给工厂，而工厂自己 lower-case
  （`types/hessian.f90:237`），IRC 任务**不打印 `Hessian source:`** ⇒ 大写/小写的状态码、输出文件、
  stdout 全同，**任何断言都不可能变红**。登记（§3 第 1 条），不写假测试。

#### M4 — banner 只断言前缀 ⇒ 打印的数值/名字不可证伪（**已闭合**）

- `ECHO_CASES` 的 `banner` 串现在**带数值/名字**：
  `"[NOTICE] --lscan-fc default 0.50 hartree/bohr^2"`、`"[NOTICE] --lirc-method default hpc ("`、
  `"[NOTICE] --lts-escape-step default 0.20 bohr"`、`"[NOTICE] --lopt-engine default lbfgs ("`。
- **同时新增 `absent` 字段**（不带数值的前缀）用于**抑制方向**：只用带数值的串会让
  「显式路线却打了 banner（打的是显式值）」漏检——本轮实测确实漏过一次
  （`main.F90` 的 `algorithm_was_set` 注入最初未变红），修正后才红。这是本次修复的**第 2 个自捕缺陷**。
- **反向突变（本轮实测）**：
  ```
  tasks/scan.f90:140  settings%constraint_fc -> 0.99_wp
  tasks/irc.f90:176   trim(landscape_irc_method_name(settings%method)) -> "gs"
  tasks/ts.f90:193    settings%escape_step -> 0.99_wp
  $ ctest -R 'xtb/landscape-(fc-echo|lirc-default-echo|lts-escape-echo)'
  FAIL: fc (default): the builtin default was not echoed
  FAIL: lirc (default): the builtin default was not echoed
  FAIL: lts (default): the builtin default was not echoed        -> 3/3 Failed
  # 还原 -> 3/3 Passed
  ```

#### M5 — `--strict` 位置无关性无测试（**已闭合**）

- `landscape_cli_strict.cmake`（`CMakeLists.txt` 内嵌）与 python `check_strict_unknown` 都加了第三条路线
  `--zzzz --strict --gfn 2 --sp`：必须非零退出 + 出现 `Unknown option '--zzzz' provided`。
- **反向突变（本轮实测，模拟「判定移回循环内」）**：在 `case default` 里加
  `if (strict) call env$error(...)`，并把解析尾的 `if (strict) then`（`main.F90:3920`）改成 `if (.false.) then`
  （循环内已经处理过致命判定，尾部只保留非严格时的 warning）⇒
  ```
  $ ctest -R 'xtb/landscape-strict-unknown' --output-on-failure
  FAIL: --zzzz --strict was accepted            -> Failed
  ```
  即**只有新增的反序断言**能区分位置相关与位置无关（`--strict --zzzz` 在突变下仍非零）。还原 ⇒ Passed。

### 1.3 LOW（逐条处置）

| 编号 | 内容 | 处置 |
|---|---|---|
| L1 | `xhelp.f90` 只给 7/17 个已不区分大小写的旗标加了说明 | **接受并说明**：纯文档一致性；`--help` 的选项行数与 token 数不变（BC-2），补全属设计 §8.6 的帮助清单工作（阶段 4） |
| L2 | banner 用 `f4.2`，库入口给 ≥10 会打印 `****` | **接受并说明**：CLI 不可达（显式给值即抑制 banner）；库入口的校验只要求 `> 0`。已登记 |
| L3 | `--help/--version/--license/--citation` 之前的未知旗标不再报告 | **接受并说明**：解析尾方案（位置无关）的**必然代价**——`terminate(0)` 在循环内出口；要恢复旧行为就必须在循环内判 `strict`，即回到位置相关（与 5a 目标冲突）。登记为已入册的行为变更 |
| L4 | 冲突消息报规范名而非别名（`--sp` 报 `--scc`） | **接受并说明**：报的是 `select_runtyp` 调用点的**文档名**；两处调用（`main.F90:2133/2174`）分别用 `--scc`/`--opt`，而 `--sp`/`-o` 是别名。测试只断言「点名旗标族」，不依赖别名拼写 |
| L5 | `--gmd` 在 `set_runtyp` 失败后仍被记入 `selected_typ`，可能多报一条误导冲突 | **接受并说明**：`--gmd` 紧跟 `env%error("This feature has been deprecated")`（`main.F90:2243`），进程必然失败；多出的冲突行不改变结论。登记 |
| L6 | 报告 17 §1.1「全部 145 处」若指全仓库不成立（另 2 处未换） | **已订正**：145 处是 `main.F90` 口径。另 2 处是 `set_module.f90:1121`（**本轮已由 M1 的 `select_runtyp` 覆盖**）与 `set_module.f90:2828`（xcontrol `runtyp=`，设计 §8 已登记为范围外） |
| L7 | 设计 §17.3 标题写 D1/D2/D3/D4，正文只列 D1/D2/D3/D7 | **接受并说明（需父会话裁定）**：设计自相矛盾，实施按 4 类做（报告 18 §9 已登记 D4 未实施）。属**设计文档**问题，不在本轮改 `src/` 的范围 |

### 1.4 INFO（逐条处置）

| 编号 | 内容 | 处置 |
|---|---|---|
| I1 | BC-4 证据在 `/tmp`，仓库无法重放 | **接受并登记**：BC-4 的强基线（worktree + 版本串对齐）依赖 `/tmp/xtb-p1v`。本轮 §5 给出可核命令；若要把脚本入库，属交付整理（未做） |
| I2 | BC-4 未声明「两目录文件清单相等」 | **已闭合**：本轮显式 `diff <(ls head) <(ls p1fix)`，4 个 runtype 的清单逐字相同（3/7/9/55） |
| I3 | 仓库根有未跟踪 `p1rev-workflow.js` | **接受**：未提交 git（本轮全程无 `git add`/`git commit`）；`git status` 里仍为 `??` |
| I4 | `enum-case` 的 prfo 组 pattern `"prfo"` 是弱断言 | **部分闭合**：新增 `ltshess` 组断言 `Hessian source: +model`（正是 prfo 组用到的 `--lts-hessian MODEL`）；prfo 组的真正判据仍是 `xtbts.xyz` 逐位比较。登记 |
| I5 | 一个逻辑冲突报 N 条（每个冲突子选项一条） | **接受**：设计判断（信息不丢，每个被拒旗标都点名），报告 §7.6 已登记 |
| I6 | `--ceh`/`--dipro` 的 runtyp 选择被 `get_xtb_feature('tblite')` 包住 | **不适用**：本构建 `WITH_TBLITE=OFF`，`--ceh`/`--dipro` 本就不选 runtyp、也无效果。tblite 构建下需复核（登记） |

### 1.5 复核 §14「需向用户确认」（转父会话裁定，本轮不动）

1. **D4（`--lscan` 默认双向回显）是否属阶段 1**：设计 §17.3 标题/正文自相矛盾（L7），实施按 4 类做并登记未实施。**需裁定**。
2. **§17.1 爆炸半径**：任意「原生 runtyp × 另一 runtyp」现在 exit 1（`--sp --lopt-engine bfgs` 由 0→1）。本轮未改规则，**需裁定是否入册 §5.1**。
3. **D3 处置**：本轮**已补测试**（H1），该确认项关闭。

---

## 2. 验证报告（19）「未验证 / 代偿 / 未做」项处置

| 19 的项 | 处置 |
|---|---|
| §12 meson 未在本机执行（无 meson/ninja） | **仍未验证**（环境限制）。替代证据：CMake/meson 测试名 `uniq -d` 均空；新增测试在两侧同步登记（`CMakeLists.txt:3397` ↔ `meson.build:491`；`:639` ↔ `:434`） |
| §12 BC-4 强结论依赖版本串对齐 | **接受**：本轮沿用同一方法并**重跑**（§5）；差异只有非确定性字段 |
| §12 w0 弱基线归因强度弱 | **接受**：本轮只用强基线（HEAD worktree `a845def`） |
| §12「未做：3+ 互斥 runtype 无专门测试」 | **已补**：`CMakeLists.txt:647` `xtb/landscape-runtype-conflict-triple`（`--lopt --lscan --lts`）。反向突变（冲突分支 → `.false.`）⇒ **8/8 冲突测试红**（含 triple：`the run type conflict '--lopt --lscan --lts' did not fail`）；还原 ⇒ 8/8 绿 |
| §12「未做：`--lts` band 下 `[NOTICE] --lts-escape-step` 与 `escape from a minimum:` 措辞不一致」 | **接受（范围外）**：报告 B §8.4 已登记；band 方法（neb/cineb/autoneb/string/gsm）的 banner 语义属 M5/后续 |
| §6.2 证伪「`--lscan-method cg` 单独调用 rc=0」 | **接受订正**：rc=1 来自坐标缺失（§17.2 错误），非冲突。测试没有依赖该前提 |
| §6.3 证伪「BC-4 stdout 因 banner 改变」 | **接受订正**：本轮 BC-4 独立复现（§5），原生 runtype **0 条新 NOTICE** |
| §6.4 `--sp --lopt-engine bfgs` 由 0→1 未入册 | **登记**，与复核 §14.2 合并，需父会话裁定 |

---

## 3. 最终零覆盖清单

「零覆盖」= **宣称生效但没有任何测试能证明**。下表是本轮修复后的**全部剩余项**（4 条，均有理由），
以及**已闭合**项（供对照）。

### 3.1 剩余（有理由）

> **R38 订正（本节的 R1/R2 已在本轮关闭，表格保留为历史记录）：**
> 父会话四项裁定的第 3/4 条要求**不再登记为欠账**，而是改代码 + 补测试：
> **R1** 由 `tasks/irc.f90` 的启动 banner 新增生效 `Hessian source:` 回显 + `xtb/landscape-enum-case` 的
> `lirchessian` 组（＋ `xtb/landscape-lirc-default-echo` 的 `hessian` 路线）关闭；
> **R2** 的 5 处库入口字面比较全部改用 `landscape_lowercase`，每处一条大写/小写等值单测。
> 完整处置、反向突变与**更新后的零覆盖清单**见 `22-stage1-final-report.md` §2/§3。

| # | 开关 / 字段 / 行为 | 读取处 file:line | 测试 | 理由 |
|---|---|---|---|---|
| R1 | `lircset%hessian_source` 存储点归一 | `src/prog/main.F90:3646` | **无** | **行为上不可观测**：值只被 `tasks/irc.f90:208` 传给工厂，工厂自行 lower-case（`types/hessian.f90:237`），IRC 不打印 `Hessian source:` ⇒ 大写/小写的退出码/输出文件/stdout 全同，**不存在能变红的断言** |
| R2 | 5 处库入口字面比较（M2 剩余） | `tasks/scan.f90:137`、`tasks/ts.f90:449`、`tasks/vib.f90:144`、`saddle/prfo.f90:955`、`saddle/dimer.f90:425` | **无** | CLI 在所有存储点归一（`main.F90:2335/2966/3725/2772/2863`）⇒ CLI 不可达；库入口无红得起来的测试。按铁律 1 不做无测试改动，逐条登记（§1.2 M2） |
| R3 | `--lscan-expo`（`spring_expo`）生效性 | `main.F90:2438` → `relax_scan.f90:665`（R38 订正行号：旧写 `2427`，实测 `case ('--lscan-expo')` 在 `2431`、存储点在 `2438`） | **无** | **既有欠账**（复核 Z11，非阶段 1 引入） |
| R4 | `--lts` band 方法下 `escape from a minimum:` 措辞过宽 | `tasks/ts.f90:176-181` vs `saddle/prfo.f90:780` | **无** | **既有欠账**（复核 Z12 / 报告 B §8.4，范围外） |
| （附）R5 | banner `f4.2` 对 ≥10 的值溢出 `****` | `tasks/scan.f90:139`、`tasks/ts.f90:192` | **无** | L2：CLI 不可达（显式给值即抑制 banner） |

### 3.2 本轮已闭合（原复核 Z1–Z10）

| 原编号 | 开关 / 字段 / 行为 | 读取处 file:line | 测试名 | 反向突变 |
|---|---|---|---|---|
| Z1 | `[NOTICE] --lopt-engine default` banner | `tasks/opt.f90:121-127` | `xtb/landscape-lopt-engine-echo` | 条件→`.false.` ⇒ 红 |
| Z2 | `landscape_opt_settings%algorithm_was_set` | `settings.f90:436`；set `main.F90:2287`；read `opt.f90:121` | 同上 | 置 `.false.` ⇒ 红（explicit 路线） |
| Z3 | `--strict` 位置无关性 | `main.F90:3911-3926` | `xtb/landscape-strict-unknown` | 位置相关突变 ⇒ 红（`--zzzz --strict was accepted`） |
| Z4 | `--lscan-hessian` 存储点归一 | `main.F90:2585` | `xtb/landscape-enum-case`（lscanhess） | →`sec` ⇒ 红 |
| Z5 | `--lirc-hessian` 存储点归一 | `main.F90:3646` | — | **不可观测**（R1） |
| Z6 | `--lvib-hessian` 存储点归一 | `main.F90:3725` | `xtb/landscape-enum-case`（lvibhess） | →`sec` ⇒ 红 |
| Z7 | `--lts-restart` 内联 select 归一 | `main.F90:2946` | `xtb/landscape-enum-case`（ltsrestart） | →`sec` ⇒ 红 |
| Z8 | `--lirc-restart` 内联 select 归一 | `main.F90:3699` | `xtb/landscape-enum-case`（lircrestart） | →`sec` ⇒ 红 |
| Z9 | 4 个 banner 的数值/名字（`0.50`/`0.20`/`hpc`/`lbfgs`） | `tasks/{scan,ts,irc,opt}.f90` | 4 个 `*-echo` | 打印错值/错名 ⇒ 红 |
| Z10 | `--raman` 的 runtyp 选择 | `main.F90:2157-2165` | `xtb/landscape-raman-conflict` | 去掉 `select_runtyp` ⇒ 红 |
| （新增） | `ltset%hessian_source` 存储点归一（复核误判为已覆盖） | `main.F90:2966` | `xtb/landscape-enum-case`（ltshess） | →`sec` ⇒ 红 |
| （新增） | 3+ 互斥 runtype | `main.F90:4000` | `xtb/landscape-runtype-conflict-triple` | 冲突分支→`.false.` ⇒ 红 |
| （新增） | `scan1d` 模式选择 / `relax_scan` 校验门 / driver 的 model 种子 | `scan1d.f90:171`、`relax_scan.f90:500`、`driver.f90:203` | 单元 `rigid-mode-case`/`relaxed-mode-case`/`model-source-case` | 改回 `trim` ⇒ 3 个都红 |

> 复核 §10 的「5 个 `hessian_source` 存储点只 2 个被覆盖」**已全部逐个覆盖**（除 R1 的 lirc 一处，理由如上）；
> 复核 §10 的「3 个 `--l*-restart` 只 1 个覆盖」**已全部覆盖**。

---

## 4. 本轮新增/加强的测试与反向突变证据

| 测试 | 类型 | 反向突变 | 结果 |
|---|---|---|---|
| `xtb/landscape-lopt-engine-echo`（`CMakeLists.txt:3397`） | CLI echo | `opt.f90:121` 条件→`.false.` | 红（`the builtin default was not echoed`）→ 还原绿 |
| 同上（闸门字段） | CLI echo | `main.F90:2287` 置 `.false.` | 红（`the notice was printed although the flag was given`）→ 还原绿 |
| `xtb/landscape-raman-conflict`（`:639`） | CLI 冲突 | 删 `select_runtyp(...apply=.false.)` | 红（`does not name its first flag`）→ 还原绿 |
| `xtb/landscape-runtype-conflict-triple`（`:647`） | CLI 冲突 | 冲突分支→`.false.` | 红（`did not fail`）→ 还原绿（8/8 冲突族一起红/绿） |
| `xtb/landscape-strict-unknown`（`:661`，加第三条路线） | CLI | 位置相关突变 | 红（`--zzzz --strict was accepted`）→ 还原绿 |
| `xtb/landscape-enum-case`（`:801`，4→9 例） | CLI 大小写 | 7 个归一化点→`sec` | 6 例逐例红（见 §1.2 M3）→ 还原绿 |
| 4 个 `*-echo`（banner 数值） | CLI echo | 硬编码值/名字 | 3 例红 + lopt 红 → 还原绿 |
| 单元 `rigid-mode-case` / `relaxed-mode-case`（`test_landscape_scan.f90:180-181`） | 单元 | `scan1d.f90:171`/`relax_scan.f90:500`→`trim` | 2/2 红 → 还原绿 |
| 单元 `model-source-case`（`test_landscape_optimize_xtb.f90:70`） | 单元 | `driver.f90:203`→`trim` | 红（13/16 vs 16/18）→ 还原绿 |

**每个新测试都有「红 → 还原 → 绿」证据**（§1 各条给出命令与消息）。全部突变用
`/tmp/p1f/mut.py`（唯一出现断言）施加，还原用改动前的备份副本，并逐项 `grep` 确认无残留
（`grep -n "if (.false.) then" tasks/opt.f90`、`grep -n "0.99_wp" tasks/{scan,ts}.f90`、
`grep -n "hessian_source = sec\|select case (sec)" src/prog/main.F90` 等，均 0 命中；
`main.F90:1819` 的 `select case (sec)` 是既有 `--color` 分支）。

---

## 5. BC-4 复核（原生 runtype 输出文件逐位不变）

**方法**（同 19 §1.1 的强基线）：
```
# 基线：HEAD worktree（阶段 1 之前）同配置构建
$ git worktree add --detach /tmp/xtb-p1v/head HEAD
$ cmake -S . -B /tmp/xtb-p1v/head-build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=OFF \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"
$ cmake --build /tmp/xtb-p1v/head-build -j 8          # -> /tmp/xtb-p1v/head-build/xtb
# 版本串对齐（纯构建元数据）：把 p1 的 include/xtb_version.fh 写成基线串后重建
$ cp /tmp/xtb-p1v/head-build/include/xtb_version.fh /tmp/xtb-p1/build/include/xtb_version.fh
$ cmake --build /tmp/xtb-p1/build -j 8
$ /tmp/xtb-p1/build/xtb --version   # 6.7.1 (a845defedfebcea80f94f16e0e22e139dc44d400)
# 同一目录路径、只换二进制
$ bash /tmp/xtb-p1v/bc4.sh head  /tmp/xtb-p1v/head-build/xtb
$ bash /tmp/xtb-p1v/bc4.sh p1fix /tmp/xtb-p1/build/xtb
# 验证完已还原 version.fh 并重建
```
**结果（本轮实测）**：

| runtype | 文件清单 | raw `cmp` 差异文件 | stdout 非确定性行 | 新 `NOTICE` | stderr | 退出码 |
|---|---|---|---|---|---|---|
| `--sp` | 3 = 3（逐字相同） | **0** | 全部属 5 类已知字段 | 0 | 0 差异 | 0 = 0 |
| `--hess` | 7 = 7 | **0**（含 `hessian`/`vibspectrum`/`g98.out`/`compliance.dat`） | 同上 | 0 | 0 差异 | 0 = 0 |
| `--ohess normal` | 9 = 9 | **0**（含 `xtbopt.xyz`/`xtbopt.log`） | 同上 | 0 | 0 差异 | 0 = 0 |
| `--md`（`$seed 42`） | 55 = 55 | **0**（含 `xtb.trj` + `scoord.1..49`） | 同上 | 0 | 0 差异 | 0 = 0 |

- **`xtbtopo.mol` 本轮也逐位相同**（两次运行落在同一分钟，`MMDDYYHHMM` 时间戳一致；19 的差异行是时间戳）。
- 5 类非确定性字段 = `started/finished run on` 时间戳、`random seed`、计时表 `…sec(%)`、
  `wall-time/cpu-time/ratio c/w`、`total power (kW/mol)`。逐 runtype 用
  `sed -E '/(started|finished) run on/d; /random seed/d; /min,.*sec/d; /wall-time|cpu-time|ratio c\/w/d; /total power/d'`
  过滤后 `diff` ⇒ **剩余差异行 0**（4/4 runtype）。
- 本轮改动碰了 `driver.f90`（landscape 优化器）与 `scan1d.f90`/`relax_scan.f90`（套件扫描），
  以及 `main.F90` 的 `--raman` 分支；三者都不在 4 个原生 runtype 的代码路径上，BC-4 实测确认。

---

## 6. 最终状态与可核命令

```
$ cmake --build /tmp/xtb-p1/build -j 8                              # 0 error
$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p1/build -R landscape
100% tests passed, 0 tests failed out of 118                        # 基线 115 -> 118
$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p1/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
100% tests passed, 0 tests failed out of 12
$ grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d    # 空
$ grep -oE "test\('[^']+'" test/unit/meson.build | sort | uniq -d           # 空
$ python3 test/unit/landscape_help_check.py src/prog/main.F90 src/xhelp.f90  # exit 0（集合 S 差集 0）
```
新增的 3 条测试：`xtb/landscape-lopt-engine-echo`、`xtb/landscape-raman-conflict`、
`xtb/landscape-runtype-conflict-triple`（115 → 118）；另有 2 个单元用例、`enum-case` 扩到 9 例、
4 个 echo 断言加数值、`strict-unknown` 加一条顺序路线（这些不改变测试条数）。

**改动文件**（19 个 `M`；本轮在阶段 1 的 16 个之上新增/修改 4 个）：
`src/prog/main.F90`、`src/landscape/types/{settings,hessian}.f90`、`src/landscape/tasks/{opt,scan,ts,irc}.f90`、
`src/landscape/scan/{relax_scan,scan1d}.f90`、**`src/landscape/optimize/driver.f90`**、`src/xhelp.f90`、
`test/unit/{CMakeLists.txt,meson.build,landscape_cli_check.py}`、`test/unit/test_landscape_{settings,hessian,scan}.f90`、
**`test/unit/test_landscape_optimize_xtb.f90`**、`docs/_simplify-recon/11-cli-redesign.md`。
未跟踪：`test/unit/landscape_help_check.py`、`docs/_simplify-recon/{17,18,19,20,21}-*.md`、`p1rev-workflow.js`。
**未提交 git**；`git diff --cached` 空。

---

## 7. 未验证 / 限制（凡无法核的都写明）

1. **tblite 构建下 `--raman` 的完整运行路径未验证**（本机 `WITH_TBLITE=OFF`）。论证：`apply=.false.`
   使 `set_runtyp` 的调用次数/顺序与改动前**逐字相同**，故行为不应改变；可验证的冲突判定已实测。
2. **meson 端到端未执行**（本机无 meson/ninja，AGENTS §4）。替代：测试名唯一、两侧同步登记、python 检查器本体直接执行通过。
3. **BC-4 的证据在 `/tmp`，仓库内不可重放**（I1）；§5 给出完整命令。
4. **R1（`lircset%hessian_source`）与 R2（5 处库入口字面比较）没有可证伪观测**，按铁律 1 只登记不改（§3.1）。
5. **`--lts` band 方法的 banner 语义**（既有欠账 R4）与 **D4**（设计自相矛盾）未处理，属范围外/待裁定。
   （R38 已裁定：D4 无代码变更，理由见 11-*.md §8.3/§17.3）
6. **父会话状态描述中的两处不准确**（本轮订正）：
   - 「M2 已关闭」不完整——复核点名的 **7 处**里只关了 **3 处**（有测试的），另 5 处登记为欠账（§1.2 M2）；
   - 「`landscape_cli_check.py:24 与 :135-138` 是 D3 的断言」不准确——`:130-138` 是**既有**的
     `check_hessian`（`--lopt-hessian` 的 model/numerical × lbfgs/rfo 能量比较），D3 的断言在
     `ECHO_CASES["lopt"]`（`landscape_cli_check.py:1982-2003`）与 `CMakeLists.txt:3397`。

---

## 8. 需父会话裁定

1. **§17.1 爆炸半径**（`--sp --lopt-engine bfgs` 0→1）是否入册 §5.1（复核 §14.2 / 验证 §6.4）。
2. **D4**（`--lscan` 默认双向回显）是否属阶段 1（设计 §17.3 自相矛盾，L7）。
3. **M2 剩余 5 处库入口字面比较**：接受「登记为欠账」还是要求阶段 2 前补齐（补齐需先建库入口测试）。
4. **R1（`--lirc-hessian` 归一化不可观测）**：接受登记，还是要求给 IRC 任务加 `Hessian source:` 打印
   （会改 stdout，属行为变更，本轮未做）。

---

## 9. 父会话裁定（四项）与落实

> 父会话对上面 §8 的四项给出裁定；**实现与证据全部在 `22-stage1-final-report.md`**（本报告只记裁定本身
> 与它在本报告里触发的文字订正）。R38 = 本轮的修订号（`11-*.md` 的修订记录）。

| # | 裁定 | 落实 |
|---|---|---|
| **1** | **§17.1 的爆炸半径入册**（`--sp --lopt-engine bfgs` 0 → 1 是行为变更，不是缺陷） | `11-cli-redesign.md` §10 **C 类新增 C8**（含现象/影响/爆炸半径/缓解/可避免），计数口径全部更新：C 7 → **8**，总计数 17 → **18**（top 头部的 R38 补丁行、§10 汇总行、§10 末的 R29/R35 订正、§17.1 新增一行）；另加修订记录 **R38** 行 |
| **2** | **D4 不改代码**（`--lscan` 默认双向是 M2 有意确立的默认，不是缺陷） | `11-*.md` §8.3 的 D 清单条目加 R38 注（双向扫描 = 滞回自检，改默认单向等于删自检；关切由 D1 的 `--lscan-fc` 回显 + M2 滞回文档覆盖），并修正 §17.3 标题/清单（D1/D2/D3/**D4**/D7 → D1/D2/D3/D7 + 一行说明）。**`src/` 零改动** |
| **3** | **M2 剩余 5 处库入口字面比较：不再接受“登记为欠账”**（库级入口可被单测以大写 settings 直接触达） | 5 处全部改用 `landscape_lowercase`（`tasks/scan.f90`、`tasks/ts.f90`、`tasks/vib.f90`、`saddle/prfo.f90`、`saddle/dimer.f90`），**小写输入行为不变**；为每处新增一条单元用例（`scan-task-mode-case`、`ts-can-tighten-case`、`vib-hessian-case`、`prfo-init-mode-case`、`dimer-axis-case`），每一条都有“去掉归一 ⇒ 红”的突变证据（报告 22 §2） |
| **4** | **R1：让 IRC 的 `hessian_source` 可观测**（不限于登记） | `tasks/irc.f90` 启动 banner 新增生效 `Hessian source:`（与 scan/opt/ts/vib 同格式，位置在 `restart policy:` 之后）；按 §17.3 的 banner 规则判定它是**生效值**而非危险默认 ⇒ **默认打、显式也给**。测试：`xtb/landscape-lirc-default-echo` 的 `lirc` 路线新增 `default`/`explicit` 的 `Hessian source: numerical` 断言与新的 `hessian` 路线（`--lirc-hessian model` ⇒ `Hessian source: model`）；`landscape_cli_check.py` 的 `check_echo` 为此新增 `require` 机制（CMake 与 meson 同一实现）。**额外收获**：打印存储值使面向前一行的“不可观测”结论**失效**——`xtb/landscape-enum-case` 新增 `lirchessian` 组（`--lirc-hessian NUMERICAL` vs `numerical`）现在能变红，即零覆盖清单的 **R1 已关闭** |

> **注（与 §1.3 L7 的关系）**：L7 报的“设计自相矛盾”现由裁定 2 正式关闭：**D4 本就不在实施范围**，
> §17.3 的标题已改正，不再是“实施与设计不一致”。

