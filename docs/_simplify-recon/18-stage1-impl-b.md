# 18 — 阶段 1（B 组）实施报告：§17.2 flag 点名 + §17.3 危险默认回显 + §17.4 `--help` 双向一致

> 范围：`docs/_simplify-recon/11-cli-redesign.md` §17.2 + §17.3 + §17.4（本文简称 **B 组**）。
> A 组（§17.1 + §17.5）已由父会话验证，见 `17-stage1-impl-a.md`；本文**复用** A 组的
> `select_runtyp` / `landscape_lowercase`，**未重做**其任何内容，**未引入 `--method`**，
> **未改 runtyp 语义**，**未碰 `--opt`/`--ohess` 分派**，**未动核心层**，**未改任何现有旗标名字**。
>
> 构建：`/tmp/xtb-p1/build`（`-O2 -DNDEBUG`、`WITH_TBLITE=OFF`、`WITH_CPCMX=OFF`、`WITH_TESTS=ON`）。
> 所有 xtb/ctest 调用带 `OMP_NUM_THREADS=1`。**未提交 git**（`git diff --cached` 为空）。

---

## 0. 摘要

| 项 | 结果 |
|---|---|
| 改动文件 | `src/landscape/scan/relax_scan.f90`、`src/landscape/tasks/{opt,scan,ts,irc}.f90`、`src/landscape/types/settings.f90`、`src/prog/main.F90` + `test/unit/{CMakeLists.txt,meson.build,landscape_cli_check.py,test_landscape_scan.f90}` + **新文件** `test/unit/landscape_help_check.py` |
| `ctest -R landscape` | **115/115 通过**（阶段 1 前 101；A 组 109；B 组 **+6**） |
| 回归子集 | **12/12 通过** |
| 重名检查 | `grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt \| sort \| uniq -d` = **0 行**；meson 测试名同理 0 行 |
| §17.2 | 3 条必填消息全部点名旗标；**6 条调用点**逐条实测（含 `2` 后缀与长度/角度单位） |
| §17.3 | 4 类危险默认各有 banner；**默认打印 / 显式给值不打印**两路都测；走 **stdout**（`env%unit`）；`--ljson` 文档仍可被 `json.load` 解析（实测） |
| §17.4 | `landscape_help_check.py`：集合 S 差集 = **0**（门槛）；集合 N 两种口径 **30/4** 与 **34/6** 都打印 |
| 反向突变 | **6 组全部「红 → 还原 → 绿」**（含 sha256 校验） |
| §17.6 BC-4 | 5 个原生 runtype 的输出文件**逐位相同** + 归一化 stdout **逐行相同**（§6，**比预期更强**：B 组 banner 只落在套件任务上，原生 runtype 一行都不变） |
| §5.1 #20/#21/#23/#25 | **四条仍全部 exit 1 + 点名旗标 + 任务未启动**（§7） |
| 构建 warning | 改动过的 7 个源文件 **0 warning**；0 error |

**本组最有价值的产出：证伪 3 条前提 + 自己发现 1 条「测试假绿」**（§8）。

---

## 1. 改动清单

### 1.1 §17.2 —— 必填参数点名旗标（`src/landscape/scan/relax_scan.f90`）

`landscape_scan_check` 里三条 `env%error` 由「描述被拒的值」改为「点名要传的旗标」，
并在循环里按坐标序号选旗标后缀、按坐标类型选步长单位：

| 触发 | 旧文本 | 新文本（实测输出） |
|---|---|---|
| 原子下标越界 | `atom index 9 of the distance coordinate is outside 1..3` | `the distance coordinate needs --lscan-atoms 1,2 (atom indices are 1-based, 1..3); index 9 is invalid` |
| 无坐标（`--lscan` 裸调） | `atom index 0 of the distance coordinate is outside 1..3` | `the distance coordinate needs --lscan-atoms 1,2 (atom indices are 1-based, 1..3); index 0 is invalid` |
| `nstep = 0` | `coordinate 1 has nstep = 0, at least one step is required` | `coordinate 1 has nstep = 0; set it with --lscan-nstep <n>` |
| 零步长（distance） | `coordinate 1 has a zero step size` | `coordinate 1 has a zero step size; set it with --lscan-step <value> (angstrom)` |
| 零步长（angle/dihedral） | 同上 | `coordinate 1 has a zero step size; set it with --lscan-step <value> (degree)` |
| 第二坐标 `nstep = 0` | `coordinate 2 has nstep = 0, ...` | `coordinate 2 has nstep = 0; set it with --lscan-nstep2 <n>` |

三个新增局部量（`flag_suffix` / `atom_list` / `step_unit`）都带注释说明**为什么**存在；
第二坐标的后缀（`--lscan-atoms2` / `--lscan-step2` / `--lscan-nstep2` 确实存在，`main.F90:2510/2521/2538`）
不是装饰：不区分会把用户指向一个**校验距离/角度时无效的旗标**（`--lscan-atoms` 只写 `coord(1)`）。

### 1.2 §17.3 —— 危险默认回显

**「显式 vs 默认」的判据靠 settings 上的 4 个 `*_was_set`**（沿用 M3 `--lvib`/`$thermo`
优先级那套命名，`settings.f90:591/598/615/620`；本次新增在 `:436/561/745/868`），由 `main.F90`
在对应 `case` 里置位：

| settings 字段 | 旗标 | `main.F90` 置位点 |
|---|---|---|
| `landscape_opt_settings%algorithm_was_set` | `--lopt-engine` | `:2281` |
| `landscape_scan_settings%constraint_fc_was_set` | `--lscan-fc` | `:2417` |
| `landscape_ts_settings%escape_step_was_set` | `--lts-escape-step` | `:3035` |
| `landscape_irc_settings%method_was_set` | `--lirc-method` | `:3357` |

**为什么不用「值等于默认就打印」**：那样 `--lscan-fc 0.5`（显式）也会打印，违反 §17.3
的规则「显式给值时不打印」；`*_was_set` 让规则**精确**，并且反向突变能证明闸门被测住（§5 M5）。

banner 落在各任务 `settings%printlevel > 0` 的启动块里（范本 `vib.f90:118-136`），前缀统一 `[NOTICE]`
（§8.3 的示例措辞），写到 **`env%unit` = stdout**：

| 任务 | 触发条件（不只是旗标默认） | 实测行 |
|---|---|---|
| `tasks/opt.f90:117-127` | `.not. algorithm_was_set` | `[NOTICE] --lopt-engine default lbfgs (the native --opt runs ANCopt)` / `… pass --lopt-engine <name> to choose another minimiser` |
| `tasks/scan.f90:132-146` | `mode == 'relaxed'` **且** `.not. constraint_fc_was_set` | `[NOTICE] --lscan-fc default 0.50 hartree/bohr^2 differs from the xtb scan force constant 0.05` / `… pass --lscan-fc 0.05 for the legacy xtbscan.log behaviour` |
| `tasks/ts.f90:183-199` | `method ∈ {prfo, bprfo}` **且** `.not. escape_step_was_set` | `[NOTICE] --lts-escape-step default 0.20 bohr moves the input geometry off a minimum` / `… pass --lts-escape-step 0 to disable the escape walk` |
| `tasks/irc.f90:170-178` | `.not. method_was_set` | `[NOTICE] --lirc-method default hpc (the M6 validation round changed it from gs)` / `… pass --lirc-method <name> to choose another integrator` |

三点**刻意的判定**（都写进代码注释）：

1. **rigid scan 不打印 fc banner**：`constraint_fc` 在 rigid 模式里根本不参与计算
   （`relax_scan.f90` 只在 `relaxed` 分支检查 `fc`），打印会误导。实测 `--lscan --lscan-mode rigid`
   base/after stdout **无差异**（§6）。
2. **band/dimer 不打印 escape banner**：`escape_from_minimum` 对 `method /= prfo .and. /= bprfo`
   直接 `return`（`saddle/prfo.f90:780`）。注意既有的 `escape from a minimum:` 行用的是
   更宽的 `method /= dimer` 条件（`ts.f90:176-181`），对 band 也打印——这是**已存在的**
   措辞过宽，属别的范围，本文未改，仅登记（§9）。
3. **fc 的数值从 settings 读**（`f0.2`）而不是硬编码 `0.5`，所以 banner 不会随默认值改动而过期。

### 1.3 §17.4 —— `--help` 双向一致性

新文件 `test/unit/landscape_help_check.py`（规则**写死在代码里并打印**）：

```
  main  every quoted string of a `case (...)` label of main.F90
        that starts with `-` (both quote characters, comma
        separated aliases are separate spellings)
  help  every help text line of xhelp.f90 whose string starts
        with `-`, split at commas and whitespace
        dialect A: `--[no]x` expands to `--x` and `--nox`
        dialect B: `--[no]x` stays literal
```

- **集合 S**（`--l` 开头或 `== --method`）：**门槛**，两种口径都断言差集为空。
- **集合 N**：只打印 + 打印完整清单（§8.6 的已知清单）。
- 注册：`add_test("xtb/landscape-help-coverage" …)`（`test/unit/CMakeLists.txt:3292`，走既有的
  `landscape_cli_py.cmake` 助手）+ meson `test('landscape help coverage', …)`（`meson.build:469`附近）。
- 读的是**源码**（`${PROJECT_SOURCE_DIR}/src/prog/main.F90`、`xhelp.f90`），不需要二进制/环境。

实测输出见 §4。

---

## 2. 新增/修改的测试与注册

### 2.1 新增 CLI 测试（6 条）

| 测试名 | file:line | 断言 |
|---|---|---|
| `xtb/landscape-scan-step-zero` | `CMakeLists.txt:870` | `--lscan-step 0`（angle）的消息含 `--lscan-step <value> (degree)` |
| `xtb/landscape-scan-coord2-flag` | `:876` | 第二坐标 `--lscan-nstep2 0` 的消息含 `set it with --lscan-nstep2` |
| `xtb/landscape-help-coverage` | `:3292` | 集合 S 差集 = 0（两种口径）；N 打印 |
| `xtb/landscape-fc-echo` | `:3307` | 3 条路线：relaxed 默认→有 banner、`--lscan-fc 0.05`→无、rigid 默认→无；前两条另跑 `--ljson` 并 `json.load` |
| `xtb/landscape-lirc-default-echo` | `:3314` | 默认 `hpc`→有 banner；`--lirc-method gs`→无 |
| `xtb/landscape-lts-escape-echo` | `:3321` | 默认 0.2→有 banner；`--lts-escape-step 0.3`→无 |

`landscape_cli_check.py` 新增 mode `echo`（`ECHO_CASES` 表 + `check_echo`，`:1869/:1946`）。
每条路线**先断言「任务到达了自己的 print 块」**（milestone 行），再断 banner 的有/无——
否则一个在 print 块之前就崩掉的任务会让「无 banner」假绿。

**两条既有断言已同步改**（§17.2 要求；行号是改后）：

| 测试 | 旧 PATTERN | 新 PATTERN |
|---|---|---|
| `xtb/landscape-scan-nstep-missing`（`:858`） | `at least one step is required` | `set it with --lscan-nstep` |
| `xtb/landscape-scan-atom-range`（`:864`） | `outside 1..3` | `needs --lscan-atoms` |

> **为什么不是 `--lscan-nstep` 这种「只含旗标名」的 pattern**：xtb 的 stdout 第 109 行会
> 回显**整条命令行**（`program call : … --lscan-nstep 0`），所以任何只出现在命令行里的旗标名
> 都会被输出**无条件命中**——这样的断言在旧消息下也会绿。这是本轮**自己发现并修掉的假绿**（§8.1）。
> 新 pattern 都跨了消息的措辞（`set it with …` / `needs …`），命令行里不可能出现。

### 2.2 单元测试（`test/unit/test_landscape_scan.f90`）

`test_atom_out_of_range` / `test_zero_nstep` 增加**消息文本**断言（读
`env%log(env%nLog)%message`，沿用 `test_landscape_saddle.f90:1506` 的既有做法）：
`index(…, '--lscan-atoms') > 0`、`'--lscan-nstep'`、`'--lscan-step'`。
这两条是「改消息」这一改动最便宜、最直接的证伪面。

### 2.3 meson 镜像

`test/unit/meson.build`：4 条 scan error 用既有 `error` 模式（`landscape scan nstep missing` /
`atom range` / `step zero` / `coord2 flag`，`:374..395`）；3 条 echo 用新增 `echo` 模式（`:449`附近）；
help coverage 用新脚本（`:469`附近）。测试名唯一（`:grep uniq -d` = 0）。
**未验证**：本机无 meson/ninja（AGENTS §4），meson 侧只做语法审阅 + 括号平衡检查
（`paren balance: 0 bracket: 0`）——但三条 echo 与两条新 error 的 **python 检查器本体已直接执行通过**。

---

## 3. §17.2 改动前（红）/ 改动后（绿）

### 改动后（当前二进制，真实 `-1-` 行）

```
$ xtb h2o.xyz --gfn 2 --lscan --lscan-coord distance --lscan-atoms 1,2 --lscan-step 0.1 --lscan-nstep 0
-1- landscape_scan_check: coordinate 1 has nstep = 0; set it with --lscan-nstep <n>
$ xtb h2o.xyz --gfn 2 --lscan --lscan-coord distance --lscan-atoms 1,9 --lscan-step 0.1 --lscan-nstep 2
-1- landscape_scan_check: the distance coordinate needs --lscan-atoms 1,2 (atom indices are 1-based, 1..3); index 9 is invalid
$ xtb h2o.xyz --gfn 2 --lscan --lscan-coord angle --lscan-atoms 1,2,3 --lscan-step 0 --lscan-nstep 2
-1- landscape_scan_check: coordinate 1 has a zero step size; set it with --lscan-step <value> (degree)
$ xtb h2o.xyz --gfn 2 --lscan --lscan-ndim 2 … --lscan-nstep2 0
-1- landscape_scan_check: coordinate 2 has nstep = 0; set it with --lscan-nstep2 <n>
$ xtb h2o.xyz --gfn 2 --lscan                                     # 完全没有坐标
-1- landscape_scan_check: the distance coordinate needs --lscan-atoms 1,2 (atom indices are 1-based, 1..3); index 0 is invalid
$ xtb h2o.xyz --gfn 2 --lscan --lscan-coord distance --lscan-atoms 1,2 --lscan-step 0 --lscan-nstep 2
-1- landscape_scan_check: coordinate 1 has a zero step size; set it with --lscan-step <value> (angstrom)
```

### 改动前（反向突变 M1：把三条消息换回旧文本，真实 ctest 输出）

```
1/5 Test  #61: xtb/landscape-scan .................***Failed    0.18 sec
2/5 Test #117: xtb/landscape-scan-nstep-missing ...***Failed    0.02 sec
3/5 Test #118: xtb/landscape-scan-atom-range ......***Failed    0.02 sec
4/5 Test #119: xtb/landscape-scan-step-zero .......***Failed    0.02 sec
5/5 Test #120: xtb/landscape-scan-coord2-flag .....***Failed    0.02 sec
0% tests passed, 5 tests failed out of 5
```

`--output-on-failure` 的逐条原因（同一突变）：

```
  missing 'set it with --lscan-nstep' in the output of '--gfn 2 --lscan
  missing 'needs --lscan-atoms' in the output of '--gfn 2 --lscan
  missing '--lscan-step <value> [(]degree[)]' in the output of '--gfn 2
  missing 'set it with --lscan-nstep2' in the output of '--gfn 2 --lscan
```

还原 → **5/5 绿**（§5 M1 记录）。

---

## 4. §17.4 集合 S/N 计数（真实输出）

```
$ python3 test/unit/landscape_help_check.py src/prog/main.F90 src/xhelp.f90
…
dialect A: S(main) = 124, S(help) = 124, difference = 0
dialect A: S: 0 differences
dialect A: N(implemented, undocumented) = 30
dialect A: N(documented, unimplemented) = 4
dialect B: S(main) = 124, S(help) = 124, difference = 0
dialect B: S: 0 differences
dialect B: N(implemented, undocumented) = 34
dialect B: N(documented, unimplemented) = 6
PASS: set S is documented by `--help` in both dialects
exit=0
```

- **集合 S 差集 = 0（门槛满足）**，两种口径都是 124/124。S 的 124 = 套件 122（审计 §1.2 的 122 个拼写）
  + 2 个被前缀规则吸进来的**原生**拼写 `--license`、`--lmo`（S 按 `--l` 前缀定义，设计明确如此；
  实测 `non-suite in S = ['--license', '--lmo']`）。
- N 的清单与 §8.6 逐条一致（口径 A 的 30 条与审计 §2.2 列表**逐字相同**；4 条 = `--ithr`/
  `--silent`/`--xparam`/`-s`，与审计 §2.3 相同）。
- **§8.4 的「34/5」不可复现**（§8.2 证伪）：口径 B（`[no]` 不展开）给出的 help-only 是 **6**，
  多出的两条是字面量 `--[no]copy`/`--[no]restart`。已在设计文档 §17.4 加 **R37** 实测行。
  这不影响门槛——**S 与口径无关**。

### 反向突变 M6（`main.F90` 加一个不写 help 的 `--lzzzz` case）——真实输出

```
dialect A: S(main) = 125, S(help) = 124, difference = 1
dialect A: S: 1 differences
dialect A: N(implemented, undocumented) = 31
dialect B: S(main) = 125, S(help) = 124, difference = 1
dialect B: N(implemented, undocumented) = 35
FAIL: dialect A documents no help for: --lzzzz
FAIL: dialect B documents no help for: --lzzzz
exit=1
```

还原后 `md5sum -c` 校验 `main.F90` 与 `relax_scan.f90` 均为 `OK`（§5 M6）。

---

## 5. 反向突变（红 → 还原 → 绿）

方法：`/tmp/p1b/run_mutation.sh`（快照 → 突变 → 重建 → 跑指定 ctest → **整体还原** → 重建 → 再跑，
最后 `md5sum -c` 校验 `src/prog/main.F90` 与 `src/landscape/scan/relax_scan.f90`）。
突变体 `m1..m6.py` 里的每个替换都断言「模式在文件里恰好出现 1 次」，防止静默改错地方。

| # | 突变（语义） | 命中的测试（红） | 真实输出 | 还原 |
|---|---|---|---|---|
| **M1** | `relax_scan.f90` 三条消息换回旧文本 | `xtb/landscape-scan`（单元）+ 4 条 CLI | `0% tests passed, 5 tests failed out of 5` | 5/5 绿，md5 OK |
| **M2** | 删掉 scan 的 fc notice `if` 块 | `xtb/landscape-fc-echo` | `1 tests failed out of 1` | 1/1 绿 |
| **M3** | 删掉 irc 的 method notice `if` 块 | `xtb/landscape-lirc-default-echo` | `1 tests failed out of 1` | 1/1 绿 |
| **M4** | 删掉 ts 的 escape notice `if` 块 | `xtb/landscape-lts-escape-echo` | `1 tests failed out of 1` | 1/1 绿 |
| **M5** | `constraint_fc_was_set` 闸门换成 `.true.`（显式给值也打印） | `xtb/landscape-fc-echo` | `1 tests failed out of 1` | 1/1 绿 |
| **M6** | `case ('--lzzzz', '--lscan-max-steps')`（实现但无 help） | `xtb/landscape-help-coverage` | `S: 1 differences` + `FAIL … --lzzzz`，exit 1 | exit 0，md5 OK |

M2/M3/M4 的突变是**整块删除 print 语句**（`drop_if_block`：定位条件行 → 删除到配对的 6 空格
`end if`），不是改字符串——所以「绿」不可能是措辞差异造成的假象。
M5 专门证明「显式给值不再打印」这条规则**被测住**：只保留「默认打印」的半边是过不了 M5 的。

---

## 6. §17.6 BC-4：原生输出逐位不变

**受控基线**（同构建目录、同配置、只差 B 组的 4 个 notice 块）：
`/tmp/p1b/xtb-base` = 从工作树里删掉 4 个 notice 块后重建；`/tmp/p1b/xtb-after` = 本组最终二进制
（`cmp` 确认还原后重建的二进制与 `xtb-after` 逐位相同）。BC-4 脚本沿用 A 组的
`/tmp/p1-bc4/bc4b.sh`（同目录路径、`$seed 42` 固定 MD、归一化内嵌版本串与 `xtbtopo.mol` 时间戳、
截断计时块）。

| 运行 | 输出文件（`xtbopt.xyz`/`hessian`/`vibspectrum`/`compliance.dat`/`g98.out`/`xtb.trj`/`scoord.*`/`charges`/`wbo`） | 归一化 stdout | 退出码 |
|---|---|---|---|
| `--sp` | **逐位相同** | **逐行相同（0 差异）** | 相同 |
| `--hess` | **逐位相同** | **逐行相同（0 差异）** | 相同 |
| `--opt normal` | **逐位相同** | **逐行相同（0 差异）** | 相同 |
| `--ohess normal` | **逐位相同** | **逐行相同（0 差异）** | 相同 |
| `--md`（`$seed 42`） | **逐位相同** | **逐行相同（0 差异）** | 相同 |

> **对父会话预期的订正**：父会话预计「新增 banner 行会改变 stdout」。**实测不是**——B 组的 4 个
> banner 只落在**套件任务**（`--lopt` / `--lscan` / `--lts` / `--lirc`）上，BC-4 覆盖的
> `--sp/--hess/--opt/--ohess/--md` 一行都不变（§8.3）。因此 BC-4 的结论比预期**更强**：
> 「文件逐位相同」与「stdout 逐行相同」**同时**成立，不需要单独报告 banner 差异。

### 套件任务 stdout：差异**恰好只有 banner**（base vs after，同一目录路径）

| 调用 | 新增行（去掉计时/随机种子/时间戳/`program call` 后的全部差异） |
|---|---|
| `--lopt` | `[NOTICE] --lopt-engine default lbfgs (the native --opt runs ANCopt)` / `… pass --lopt-engine <name> …` |
| `--lopt --lopt-engine cg` | **无**（显式） |
| `--lscan …`（relaxed 默认） | `[NOTICE] --lscan-fc default 0.50 hartree/bohr^2 differs from the xtb scan force constant 0.05` / `… pass --lscan-fc 0.05 …` |
| `--lscan --lscan-mode rigid` | **无**（rigid 不用 bias） |
| `--lts --lts-method prfo` | `[NOTICE] --lts-escape-step default 0.20 bohr moves the input geometry off a minimum` / `… pass --lts-escape-step 0 …` |
| `--lirc` | `[NOTICE] --lirc-method default hpc (the M6 validation round changed it from gs)` / `… pass --lirc-method <name> …` |

（`--lts --lts-max-steps 1` 的 base/after 都带 Fortran 运行时回栈 `#0 0x…`——地址每次不同，
是**既有的**「max-steps 用尽 + `env%error`」路径，与本次改动无关。）

### 弱基线 `/tmp/xtb-w0/build/xtb`

5 个原生运行**文件全部逐位相同**；归一化 stdout 只有两类**行序伪影**（A 组已定位的 C/Fortran
缓冲边界，AGENTS 记录）：`sp`/`hess` 的对称性 banner 与 `normal termination of xtb` 相对位置不同，
`F2C` 内容集合完全相同。**w0 不能作强基线**的理由（内嵌版本串陈旧）与 A 组一致。

---

## 7. §5.1 #20/#21/#23/#25 重跑（改动后仍是红）

```
$ xtb water.xyz --gfn 2 --lopt --lscan --norestart
exit=1  -1- … run type conflict: --lopt already selected the 'lopt' run type, --lscan would select 'lscan'; …
        task-started-lines=0
$ xtb water.xyz --gfn 2 --opt --hess --norestart
exit=1  -1- … run type conflict: --opt already selected the 'opt' run type, --hess would select 'hess'; …
        task-started-lines=0
$ xtb water.xyz --gfn 2 --lts --lopt-engine bfgs --norestart
exit=1  -1- … run type conflict: --lts already selected the 'lts' run type, --lopt-engine would select 'lopt'; …
        task-started-lines=0
$ xtb water.xyz --gfn 2 --hess --lvib-temp 400 --norestart
exit=1  -1- … run type conflict: --hess already selected the 'hess' run type, --lvib-temp would select 'lvib'; …
        task-started-lines=0
```

`task-started-lines` = 输出里 `landscape engine: energy evaluations` 的行数（0 ⇒ 任务没起）。
A 组的 6 条 conflict 测试也仍在 115/115 里全绿。

---

## 8. 证伪的前提与自查发现的缺陷

### 8.1 【自己发现】「只断旗标名」的 pattern 被 stdout 里的命令行回显无条件命中（假绿）

第一版 `landscape-scan-nstep-missing` 的 pattern 是 `--lscan-nstep`。反向突变 M1 下它**仍然绿**——
因为 xtb 启动时回显整条命令行，而 ARGS 里就有 `--lscan-nstep 0`。同一问题的还有
`--lscan-atoms` 与 `--lscan-nstep2`。**已修**：所有 §17.2 的 pattern 都改成跨消息措辞的字符串
（`set it with …` / `needs …`），M1 下 4 条 CLI + 1 条单元全部变红（§3）。这是本项目第 12 次
「静态结论被实测推翻」（其一是**我自己刚写的断言**）。

### 8.2 §8.4 的「34/5」不可复现

见 §4。可复现的是 **30/4**（审计规则）与 **34/6**（`[no]` 不展开）；两种口径下集合 S 都是 124/124、差集 0。
已写入设计文档 §17.4（R37）。

### 8.3 BC-4 与 banner 的关系与父会话预期不同

见 §6：banner 只落套件任务，`--sp/--hess/--opt/--ohess/--md` 的 stdout **一字不变**。

### 8.4 既有 banner 的措辞对 band 方法过宽（本组范围外，仅登记）

`tasks/ts.f90:176-181` 的 `escape from a minimum:` 行对 `neb/cineb/autoneb/string/gsm` 也打印，
但 `escape_from_minimum` 对它们直接 `return`（`saddle/prfo.f90:780`）。本组的
`[NOTICE] --lts-escape-step` **没有**沿用这个过宽条件（只对 prfo/bprfo），因此二者在 band 运行里
会**不一致**（有 `escape from a minimum: 0.200000` 但没有 `[NOTICE]`）。我选择「新代码正确、不改旧行」
（改旧行是 stdout 行为变更，超出 §17.2/17.3/17.4 的范围）。

---

## 9. 未验证 / 残余风险

- **meson 侧未在 meson 下执行**（本机无 meson/ninja）。已做的替代检查：测试名唯一
  （`grep uniq -d` = 0）、括号平衡 = 0、`echo`/`error` 两种 mode 的 python 检查器**直接执行通过**。
- **`--lscan-expo` 没有 banner**：§17.3 的清单只有 D1（fc），`spring_expo` 未被要求；
  它与 `constraint_fc` 一样是「有意不同于上游」的参数，但本轮**不做**（不扩范围）。
- **§8.3 清单里的 D4（`--lscan` 默认双向）未实现回显**：§17.3 的表头写了 D1/D2/D3/D4/D7，
  但正文的四条只列 D1/D2/D3/D7，父会话的指令也只列这四条 ⇒ 我按四条做，D4 登记为**未实施**。
  （R38 已裁定：D4 无代码变更，理由见 11-*.md §8.3/§17.3）
- **集合 S 的 2 个非套件成员**（`--license`/`--lmo`）：S 按 `--l` 前缀定义（设计如此），差集为 0 不受影响。
- **banner 在 `printlevel > 0` 内**：`--lopt-printlevel 0` 会抑制它。§17.3 的范本（`vib.f90:118-136`）
  就在同一块里，且「用户显式要求静音」属正当；但若复核认为 `[NOTICE]` 必须无条件，需要把 4 段
  移出 `if` 块（约 4 处 6 行）。
- **`--ljson` 的机器可读性只覆盖 scan（fc case）**：JSON 是文件、banner 在 stdout，
  机制上互不干扰；实测 `--lopt --ljson` 与 `--lscan --ljson` 的文档都能 `json.load`。
- 仓库根目录仍有**未跟踪**的 `p1b-workflow.js`（本会话开始时就在）；本次改动 15 个文件全部是 `M`
  （已改未暂存）+ 1 个未跟踪新文件 `test/unit/landscape_help_check.py`，`git diff --cached` 为空。

---

## 10. 可核证据索引

```
# 构建（0 error；改动过的 7 个源文件 0 warning）
cmake -S . -B /tmp/xtb-p1/build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"
cmake --build /tmp/xtb-p1/build -j 8

# 测试
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p1/build -R landscape                 # 115/115
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p1/build \
   -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'                    # 12/12
grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d            # 空

# §17.4（可独立重跑，不需要二进制）
python3 test/unit/landscape_help_check.py src/prog/main.F90 src/xhelp.f90

# §17.3 的 python 检查器（可独立重跑）
cd test/unit && OMP_NUM_THREADS=1 XTBPATH=$REPO python3 landscape_cli_check.py \
   echo /tmp/xtb-p1/build/xtb /tmp/h2o.xyz /tmp/rundir fc        # exit 0

# BC-4
/tmp/p1-bc4/bc4b.sh /tmp/p1b/bc-after /tmp/p1b/xtb-after
/tmp/p1-bc4/bc4b.sh /tmp/p1b/bc-base  /tmp/p1b/xtb-base     # 同构建目录、只差 4 个 notice 块
/tmp/p1-bc4/bc4b.sh /tmp/p1b/bc-w0    /tmp/xtb-w0/build/xtb # 弱基线

# 反向突变
/tmp/p1b/run_mutation.sh <name> /tmp/p1b/m<N>.py '<ctest regex>'
```

`git diff --stat -- src test man`（`man/` 无改动；`landscape_help_check.py` 是未跟踪新文件）：

```
 src/landscape/scan/relax_scan.f90     |  32 ++-
 src/landscape/tasks/irc.f90           |  11 +
 src/landscape/tasks/opt.f90           |  11 +
 src/landscape/tasks/scan.f90          |  14 ++
 src/landscape/tasks/ts.f90            |  18 +-
 src/landscape/types/hessian.f90       |  11 +-     <- A 组
 src/landscape/types/settings.f90      | 103 +++++++--
 src/prog/main.F90                     | 407 +++++++++++++++++++++-------------
 src/xhelp.f90                         |  15 +-      <- A 组
 test/unit/CMakeLists.txt              | 264 +++++++++++++++++++++-
 test/unit/landscape_cli_check.py      | 240 ++++++++++++++++++++
 test/unit/meson.build                 |  98 +++++++-
 test/unit/test_landscape_hessian.f90  |   4 +-       <- A 组
 test/unit/test_landscape_scan.f90     |  12 +
 test/unit/test_landscape_settings.f90 |  48 +++-     <- A 组
 15 files changed, 1089 insertions(+), 199 deletions(-)
（+ 未跟踪新文件 test/unit/landscape_help_check.py，6869 B）
```

### 旧消息文本的全仓库引用（§17.2 要求的 grep 成表）

| 位置 | 是否需同步 | 处置 |
|---|---|---|
| `src/landscape/scan/relax_scan.f90` | 是 | **已改**（唯一的实现处） |
| `test/unit/CMakeLists.txt:854/860`（旧行号） | 是 | **已改**为 `set it with --lscan-nstep` / `needs --lscan-atoms` |
| `test/unit/meson.build:371/376`（旧行号） | 是 | **已改**（同上，两条 + 新增两条） |
| `man/` | — | **0 命中**（`man/xtb.1.adoc` 不记录套件旗标，与 A 组 R36 一致） |
| `docs/_simplify-recon/02-cli-audit.md:573-575` | 否 | 现状审计的**历史证据**，不改 |
| `docs/_simplify-recon/11/12/14-*.md` | 否 | 设计/复核的**历史记录**，不改（§17.4 另加 R37 实测行） |
| `p1b-workflow.js`（未跟踪） | 否 | 任务书本身 |
| 其他 Python 脚本（`landscape_cli_check.py` 等） | — | **0 命中**（不复制消息文本） |
