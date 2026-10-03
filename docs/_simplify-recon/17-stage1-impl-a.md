# 17 — 阶段 1（A 组）实施报告：§17.1 冲突组合检测 + §17.5 `--strict` 时序 / 套件枚举转小写

> 范围：`docs/_simplify-recon/11-cli-redesign.md` §17.1 + §17.5（本文简称 **A 组**）。
> §17.2/§17.3/§17.4 属 p1b，本文**未触碰**（`src/landscape/scan/relax_scan.f90` 未改，
> `test/unit/CMakeLists.txt` 里 `landscape-scan-nstep-missing`/`-atom-range` 两条旧断言未改）。
>
> 构建：`/tmp/xtb-p1/build`（`-O2 -DNDEBUG`、`WITH_TBLITE=OFF`、`WITH_CPCMX=OFF`、`WITH_TESTS=ON`）。
> 另有 `/tmp/xtb-p1/build-clean`（全新配置 + 全量编译，用于 warning 计数与测试名唯一性复核）。
> 所有 xtb / ctest 调用带 `OMP_NUM_THREADS=1`。**未提交 git。**

---

## 0. 摘要

| 项 | 结果 |
|---|---|
| 改动文件 | `src/prog/main.F90`、`src/landscape/types/settings.f90`、`src/landscape/types/hessian.f90`、`src/xhelp.f90` + 5 个测试文件（见 §1） |
| `ctest -R landscape` | **109/109 通过**（阶段 1 前 101；新增 8 条） |
| 回归子集 | **12/12 通过** |
| 重名检查 | `grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt \| sort \| uniq -d` = **0 行** |
| 构建 warning | 总 37 条：`src/prmat.f90` 28 + `src/drsp.f` 5（Fortran 2018 deleted feature）+ `src/onetri.f90` 2 / `src/type/anc.f90` 1 / `src/mctc/linalg.f90` 1（PURE 属性不匹配）。**`src/landscape` = 0 条**；0 error |
| §5.1 #20/#21/#23/#25 | **四条逐条由"静默"变为命名旗标的非零退出**（§5；#23 阶段 1 前也非零，但原因是 TS 搜索失败，不是旗标冲突——见 §7.1） |
| §17.6 BC-4 逐位不变 | `--sp`/`--hess`/`--opt`/`--ohess`/`--md` **全部输出文件逐位相同 + 归一化 stdout 逐行相同 + 退出码相同**（§6） |
| 反向突变 | **6 组全部"红 → 还原 → 绿"**（§4） |

**两个失败测试的判定（父会话点名要求）**

| 测试 | 判定 | 处置 |
|---|---|---|
| `#53 xtb/landscape-settings` → 子用例 `algorithm-lookup`：`expected 0 but got 2` | **过期测试**（§17.5 5b 的**有意**行为变更：`LBFGS` 现在解析为 `bfgs`=`p_landscape_opt_lbfgs`=2） | 改期望值（`test_landscape_settings.f90:354-356`）+ 新增 `enum-case` 子用例覆盖 8 个入口；登记为 **§10 F4**（计数 16 → 17） |
| `#173 xtb/landscape-e2e-layers` 17 项里失败 1 项 | **同一个根因**：`layers.json` 实测唯一失败项是 `L1 landscape-settings`（见 §2），L2/L3 全绿 | 无需单独处置；修好上一条后该测试自动变绿（已实测） |
| `test_landscape_hessian.f90:151`（未在父会话清单里，我自己找到） | **同类过期测试**：`check(error, .not. landscape_hessian_source_known("Numerical"))` 断言"大写必须被拒" | 改为 `landscape_hessian_source_known("Numerical")` 为真（有意变更） |

**没有为了变绿而放宽/删除任何断言**：两条被改的断言都是"期望值方向反转"，且**都有新测试接管**（`enum-case` 单元 + CLI）。

---

## 1. 改动清单

### 1.1 §17.1 —— `select_runtyp`

`src/prog/main.F90`：

- 新增模块过程 `select_runtyp(env, typ, flag, selected_typ, selected_flag)`（`main.F90:3948-3978`），
  文档注释写明为什么它不是 `set_runtyp` 的简单包装。
- `parseArguments` 里的**全部 145 处** `call set_runtyp('<typ>')` 改为 `call select_runtyp(...)`
  （`grep -c "call select_runtyp" src/prog/main.F90` = **145**；改动前 `grep -n "call set_runtyp"` 的
  145 个站点逐条核对过，包括设计清单没列出的 `--ceh`/`--dipro`/`--esp`/`--stm`/`--siman`/`--gmd`/
  `--screen`/`--modef`/`--mdopt`/`--metadyn`/`--metaopt`/`--ohess`/`--bhess`/`--omd`/`--vfukui` 等）。
- 子选项站点原先的 `if (set%runtyp /= p_run_lopt) call set_runtyp('lopt')` 守卫**被删除**：
  同一个语义现在由 `select_runtyp` 的"同一 typ 重复选择 = 无操作"承担（一个规则一种拼写）。
- 状态用 `parseArguments` 的局部 `intent(inout)` 变量传递，**不用 `save` 变量**。
  理由：`set_module.f90:1031-1038` 的 `logical, save :: set1` 锁正是本次要绕开的隐藏状态
  （它的消息进 `persistentEnv`，用户永远看不到），再加一个 `save` 会把同类缺陷变成两处；
  且 `save` 状态在同进程第二次调用解析器时会误报。

冲突文本（`env%error`，退出码 1，`env%checkpoint("Command line argument parsing failed")`, `main.F90:329`）：

```
run type conflict: --lopt already selected the 'lopt' run type, --lscan would select 'lscan';
only one run type can run (use --ohess, or run two jobs)
```

（措辞取自 §8.1；`--method ancopt` 的建议**故意省略**——`--method` 属阶段 2，不能在阶段 1 的错误文本里指向一个不存在的旗标。）

### 1.2 §17.5 5a —— `--strict` 时序

选用了 §17.5 的**第二个方案（解析尾统一报）**，理由是实测的：

- 未知旗标的 `env%warning`（原 `main.F90:1583`）改为在解析循环里**只记录**，循环结束后统一报
  （`main.F90:3898-3909`）：`strict` 为真 ⇒ `env%error`，否则 `env%warning`。
- **为什么不用第一个方案**（`case('--strict')` 处立即 `env%strict = .true.`）：实测它把**解析期间的一切**
  warning 变成致命错误，直接打红 5 条既有回归测试（`xtb/Singlepoint`、`GFN0-xTB`、`GFN1-xTB`、
  `GFN2-xTB/GBSA`、`GFN2-FF`）。原因：这 5 条用 `--coffee --strict` 跑"无几何输入"的冒烟运行，
  而 `--coffee` 找不到名为 `coffee` 的文件只是一条 warning（`main.F90:296-300` → `set_module.f90:1593`），
  它在 `:608` 的 `env%strict = strict` **之前**发生。⇒ 第一个方案的爆炸半径**超出 F2 登记的
  "只有未知旗标从 exit 0 变非零"**，属于未入册的行为变更；第二个方案与 F2 完全对齐。
- 附带好处（**比设计更好的地方**）：解析尾方案的判定**与 `--strict` 的位置无关**——
  `--zzzz --strict` 也 exit 1（第一个方案做不到，实测见 §5）。
- 单旗标消息文本逐字保留上游措辞 `Unknown option '<flag>' provided`；多个未知旗标时为
  `Unknown options '<f1> <f2>' provided`（避免逐条重复同一段落）。

### 1.3 §17.5 5b —— 套件枚举大小写（**清单被实测证明不完整**）

设计 §17.5 5b 列了 5 个入口。实测（`grep -rn "function .*from_name\|function .*_known" src/landscape/`）
后确认**必须**还包括 4 个谓词**与 5 个存储点**，否则会出现"大写被接受、但走另一条路径"的**新静默缺陷**：
`lsset%mode`、`ltset%init_mode`、`ltset%n_init`、`l*-hessian_source` 的**值**会被下游用
`trim(...) == 'model'`（`src/landscape/optimize/driver.f90:200`）、`== 'numerical'`（`tasks/ts.f90:433`）、
`== 'rigid'`（`scan/scan1d.f90:170`）、`== 'relaxed'`（`scan/relax_scan.f90:499`）、
`== 'force'`（`saddle/prfo.f90:955`）、`select case (trim(n_init))`（`saddle/dimer.f90:425`）
**按字面**比较。只归一化谓词不够。

落实的归一化点（共 9 个解析入口 + 3 个内联 `select case`）：

| # | 入口 | file:line（改动后） | 归一化方式 |
|---|---|---|---|
| 1 | `landscape_opt_algorithm_from_name`（`--lopt-engine` / `--lscan-method`） | `settings.f90:1149`（谓词） | `select case (landscape_lowercase(name))` |
| 2 | `landscape_irc_method_from_name`（`--lirc-method`） | `settings.f90:1267` | 同上 |
| 3 | `landscape_ts_method_from_name`（`--lts-method`） | `settings.f90:1334` | 同上 |
| 4 | `landscape_scan_coord_from_name`（`--lscan-coord[2]`） | `settings.f90:1467` | 同上（`pure`，故用本地 pure 助手） |
| 5 | `landscape_conv_level_known`（`--l*-level`） | `settings.f90:1541` | 同上 |
| 6 | `landscape_settings_set_conv_level`（**存储点**：档位阈值） | `settings.f90:1055` | 同上（否则 `known` 通过但阈值不动 = 新死旋钮） |
| 7 | `landscape_scan_mode_known` + `lsset%mode`（**存储点**） | `settings.f90:1523` / `main.F90:2328` | 谓词 + `= landscape_lowercase(sec)` |
| 8 | `landscape_ts_init_mode_known` + `ltset%init_mode`（**存储点**） | `settings.f90:1410` / `main.F90:2764` | 同上 |
| 9 | `landscape_ts_ninit_known` + `ltset%n_init`（**存储点**） | `settings.f90:1427` / `main.F90:2855` | 同上 |
| 10 | `landscape_hessian_source_known` + `new_landscape_hessian_provider` + 5 个 `l*%hessian_source`（**存储点**） | `hessian.f90:195,236` / `main.F90:2308,2577,2958,3636,3715` | 同上 |
| 11 | `--lscan-restart` / `--lts-restart` / `--lirc-restart` 的**内联 `select case (sec)`** | `main.F90:2369,2938,3689` | `select case (landscape_lowercase(sec))` |

`landscape_lowercase`（`settings.f90:1121-1136`，新公开的 pure 助手）：
不用 `xtb_mctc_strings:lowercase` 是因为后者**不是** `pure`，而 `landscape_scan_coord_from_name`
是 `pure`（函数属性不能为了归一化而降级）。文档注释里写明了这个约束。

`xhelp.f90`：`--lopt-engine`/`--lopt-level`/`--lscan-coord`/`--lscan-mode`/`--lscan-method`/`--lts-method`/`--lirc-method`
**七处**补 "not case-sensitive" 说明（`xhelp.f90:290,294,311,329,333,378,564`）。
**可核**：`--help` 输出前后 diff **只多出这 7 处文字**，`^--` 旗标行数 **175 → 175**（BC-2 不破）：

```
$ diff <(xtb-base --help) <(xtb-new --help)
186c186  <     bfgs, diis or rfo (default lbfgs)   > …  (default lbfgs).  The name is not case-sensitive
190c190  <     normal (default), tight or vtight   > …  vtight.  The level name is not case-sensitive
206a207  >     (the type name is not case-sensitive)
224c225  <     scan mode, relaxed (default) or rigid   > …  or rigid (not case-sensitive)
228c229  <     diis or rfo   >     diis or rfo.  The name is not case-sensitive
272c273,274  <     autoneb … or string / gsm (growing string)   > … (growing string). / The method name is not case-sensitive
457c459,460  <     reference; 16.9-20.3 E/g …   > … deviation). / The method name is not case-sensitive
（另有一处 "normal termination of xtb" 的行序伪影，原因同 §6.1 的缓冲边界）
```

**`man/` 无需同步**（**证伪父会话前提**）：`man/xtb.1.adoc` 里 `landscape`、`--lopt`、`--lscan`、`--lirc`、
`--lvib` 的 `grep -c` 全部为 **0** —— man 页根本不记录套件旗标。

---

## 2. 两个失败的定位（`layers.json` 实证）

```
$ python3 -c "import json;d=json.load(open('/tmp/xtb-p1/build/test/unit/landscape-e2e-layers/layers.json'));[print(e['layer'],e['suite'],e['status'],e['passed']) for e in d['layers']]"
L1 landscape-api 0 True
L1 landscape-settings 1 False      <-- 唯一失败项
L1 landscape-coords 0 True
...（L1 其余 8 项全 True）
L2 landscape-optimize-xtb/vib/failure/e2e 全 True
L3 chain / ts-irc 全 True
```

⇒ `xtb/landscape-e2e-layers` 与 `xtb/landscape-settings` 是**同一个根因**
（`test/unit/test_landscape_settings.f90:354` 的过期期望值），**不是真回归**。
判定依据（不是"它红了所以改它"）：
- `algorithm-lookup` 断言 `landscape_opt_algorithm_from_name("LBFGS") == 0`，而 §7.5/§17.5 5b
  的**明文目标**就是让 `BFGS` 等价于 `bfgs`；改后期望 `p_landscape_opt_lbfgs`（=2），与报错
  "expected 0 but got 2" 完全一致。
- 该值的变化**只**可能来自 lowercase 归一化（`git diff` 里没有别的路径能影响这个返回值）。
- 反向突变 M4（去掉 `landscape_opt_algorithm_from_name` 的归一化）**重新打红**这两条测试（§4），
  说明覆盖面没被"改期望值"掏空。

---

## 3. 新增/修改的测试与注册

### 3.1 新增 CLI 测试（CMake，8 条）

| 测试名 | 断言 |
|---|---|
| `xtb/landscape-runtype-conflict` | #20 `--lopt --lscan`：非零 + 两个旗标名 + **无** `landscape engine: energy evaluations`（证明没起任务） |
| `xtb/landscape-runtype-suboption-conflict` | #23 `--lts --lopt-engine bfgs`：同上 |
| `xtb/landscape-runtype-conflict-reversed` | `--lscan --lopt`：顺序不影响，仍点名第一个/第二个旗标 |
| `xtb/landscape-runtype-lts-lirc` | §17.1 验收里的 `--lts --lirc` |
| `xtb/landscape-opt-hess-conflict` | #21 `--opt --hess` |
| `xtb/landscape-runtype-vib-temp-conflict` | #25 `--hess --lvib-temp 400` |
| `xtb/landscape-strict-unknown` | `--strict --zzzz` 非零 + 消息；**且** `--zzzz`（无 strict）exit 0 + 同消息（BC-1 双向） |
| `xtb/landscape-enum-case` | 4 组"大写 vs 小写"跑同一任务：退出码相同、**结果文件逐位相同**、且值确实到达任务（`Hessian source: +model` / `landscape: rigid scan` / `dimer initial axis: +force`），并断言输出无 `Unknown landscape` |

`xtb/landscape-enum-case` 注册了 `ENVIRONMENT "XTBPATH=…;OMP_NUM_THREADS=1"`：逐位比较要求固定线程数
（AGENTS §6.1）。

### 3.2 单元测试

- `test/unit/test_landscape_settings.f90`：
  - `algorithm-lookup`：`LBFGS` → `p_landscape_opt_lbfgs`（有意变更）；
  - **新增子用例 `enum-case`**：8 个入口（算法 / IRC 方法 / TS 方法 / 扫描坐标 / 档位 known / 扫描模式 /
    init-mode / ninit）的大写拼写 + `set_conv_level("TIGHT")` 与 `"tight"` 的**四个阈值逐一相等**
    （专治"谓词归一化、setter 没归一化"的新死旋钮）。
- `test/unit/test_landscape_hessian.f90`：`Numerical` 由"false"改为"true"。

### 3.3 meson 镜像

`test/unit/meson.build`：6 条 conflict 用现有 `error` 模式（pattern = 被拒旗标，如 `--lscan would select`），
`enumcase`/`strictunknown` 走 `landscape_cli_check.py` 新增的 `check_enum_case` / `check_strict_unknown`
（逐位比较 + 双向 strict 检查，逻辑与 CMake 脚本逐条对应）。
**未验证**：本机没有 meson/ninja（AGENTS §4），所以 meson 侧只做了语法审阅 —— 但两条新 python 模式
**已直接执行通过**：

```
$ cd test/unit && OMP_NUM_THREADS=1 python3 landscape_cli_check.py enumcase /tmp/xtb-p1/build/xtb /tmp/h2o.xyz /tmp/pymirror-enumcase ; echo $?   → 0
$ ... strictunknown ...                                                                                                        → 0
$ ... error "--lscan would select" --gfn 2 --lopt --lscan                                                                      → 0
$ ... error "--lopt-engine would select" --gfn 2 --lts --lopt-engine bfgs                                                      → 0
```

---

## 4. 反向突变（红 → 还原 → 绿）

方法：`/tmp/mut/run_mutation.sh`（先把三个源文件恢复到"已实施"快照 → 应用突变 → 重建 → 跑指定测试）。
"还原"由 sha256 校验（`src/prog/main.F90` 5b9af12e…、`settings.f90` 63d57ba2…、`hessian.f90` 71dc30ff…）。

| # | 突变 | 命中的测试（红） | 关键输出 |
|---|---|---|---|
| **M1** | `select_runtyp` 删掉冲突分支（= HEAD 行为） | 6/6 conflict 测试全红 | `0% tests passed, 6 tests failed out of 6` |
| **M2** | 冲突条件去掉 `selected_typ /= typ`（任何第二次选择都算冲突） | `xtb/landscape-opt` 红 | `CMake Error … xtb --lopt terminated with status 1`（证明"同一 runtyp 重复=无操作"被测住） |
| **M3** | 5a 退回 HEAD（循环内 warning、无解析尾） | `xtb/landscape-strict-unknown` 红 | `0% tests passed, 1 tests failed out of 1` |
| **M4** | `landscape_opt_algorithm_from_name` 去掉归一化 | `xtb/landscape-settings` + `xtb/landscape-enum-case` 红 | `2 tests failed out of 2` |
| **M5** | 去掉**存储点**归一化 `lset%hessian_source = sec` | `xtb/landscape-enum-case` 红 | `CMake Error at landscape_cli_enum_case.cmake:26: lopt: the value did not reach the task`，输出里实测 `Hessian source:           MODEL`（**把"大写被接受但走另一条路径"这个新静默缺陷抓出来**） |
| **M6** | `landscape_settings_set_conv_level` 去掉归一化 | `xtb/landscape-settings` 红 | `0% tests passed, 1 tests failed out of 1`（该子用例专测四个阈值相等） |
| 还原 | 三个文件 sha256 校验 → 重建 | 见 §0：109/109、12/12 全绿 | `100% tests passed, 0 tests failed out of 109` |

---

## 5. §5.1 #20/#21/#23/#25 逐条前后（真实输出，`/tmp/p1-bc4/targets.sh`）

`before` = `/tmp/xtb-p1/xtb-base`（HEAD 源码 + 只回退本次改动、同一构建目录），`after` = `/tmp/xtb-p1/build/xtb`。
均以 `xtb water.xyz --gfn 2 <flags> --norestart` 运行，`task-started-lines` = 输出里
`landscape engine: energy evaluations` 的行数（0 ⇒ 任务从未启动）。

| 调用 | before | after |
|---|---|---|
| **#20** `--lopt --lscan` | `exit=0`，task-started=1（跑了 lopt） | `exit=1`，task-started=**0**，`-1- … run type conflict: --lopt already selected the 'lopt' run type, --lscan would select 'lscan'` |
| **#21** `--opt --hess` | `exit=0` | `exit=1`，`-1- … --opt already selected the 'opt' run type, --hess would select 'hess'` |
| **#23** `--lts --lopt-engine bfgs` | `exit=1`（**不是 exit 0！**），task-started=1（跑了 TS 搜索才失败） | `exit=1`，task-started=**0**，`-1- … --lts already selected the 'lts' run type, --lopt-engine would select 'lopt'` |
| **#25** `--hess --lvib-temp 400` | `exit=0`（`--lvib-temp` 静默丢弃） | `exit=1`，`-1- … --hess already selected the 'hess' run type, --lvib-temp would select 'lvib'` |
| 对照 `--lopt-engine bfgs`（无 `--lopt`，隐含 runtyp） | `exit=0` | `exit=0`（不误报） |
| 对照 `--lopt --lopt-engine bfgs`（同 typ 两次） | `exit=0` | `exit=0`（不误报） |
| 对照 `--strict --zzzz --sp` | `exit=0` | `exit=1`（F2） |
| 对照 `--zzzz --sp`（无 strict） | `exit=0` | `exit=0`（BC-1） |

---

## 6. §17.6 BC-4：原生输出逐位不变

**方法**（`/tmp/p1-bc4/bc4b.sh`）：5 个原生运行在**同一目录路径** `/tmp/p1-bc4/run` 内执行（这样
stdout 的 `program call`/`coordinate file` 行也同源），两次捕获之间只替换二进制；
- 归一化两处**构建元数据**：文件里内嵌的版本串 `6.7.1 (<commit>)` → `6.7.1 (VERSION)`、
  `xtbtopo.mol` 第 2 行的创建时间戳 → `TIMESTAMP`；
- stdout 截断在计时块（` total:`）之前，并剔除 `random seed`/`started|finished run on`/百分比行；
- `--md` 用 `$seed 42` 固定随机数（**实测**：同二进制两次运行 `xtb.trj` 逐位相同）。

| 运行 | 输出文件（含 `xtbopt.xyz`/`hessian`/`vibspectrum`/`compliance.dat`/`g98.out`/`xtb.trj`/`scoord.*`/`charges`/`wbo`） | 归一化 stdout | 退出码 |
|---|---|---|---|
| `--sp` | 逐位相同 | 逐行相同 | 相同 |
| `--hess` | 逐位相同 | 逐行相同 | 相同 |
| `--opt normal` | 逐位相同 | 逐行相同 | 相同 |
| `--ohess normal` | 逐位相同 | 逐行相同 | 相同 |
| `--md`（`$seed 42`） | 逐位相同 | 逐行相同 | 相同 |

**过程中的两个坑（都可核、都不是本次改动引入）**：
1. 第一次比较时 `--sp`/`--hess` 的 stdout **行序**不同（对称性 banner 的位置移动了 ~80 行），
   内容集合完全相同。定位：该 banner 由 C 代码 `symmetry/symmetry_i.c` 打印，
   与 Fortran unit 6 走**不同缓冲**；`GFORTRAN_UNBUFFERED_ALL=1` 下两个二进制 **逐行相同**，
   证明是缓冲边界伪影。为把伪影彻底消掉，我在 `/tmp/xtb-p1/build/include/xtb_version.fh`
   （**构建目录内生成的头文件，不是仓库文件**）里把版本串写回 HEAD 的完整哈希——因为我的工作树是脏的，
   cmake 生成的是 `unknown-commit`（14 字符 vs 40 字符），恰好足以移动 libgfortran 的冲刷边界。
   换上同一版本串后 stdout 逐行相同（上表）。
2. `xtbtopo.mol` 含创建时间戳（`10032618113D`），必须归一化；否则永远"不同"。

**父会话给的 `/tmp/xtb-w0/build/xtb` 只能作弱基线**：它内嵌的版本串是 `24c069f`（比 HEAD 早一个提交，
`bdd8eb8` 那 21 个源文件改动不在里面？——实测它**含** `$scan` 守卫，说明它至少是 `bdd8eb8` 之后的树，
版本串是 configure 时刻的陈旧产物）。用它做比较时，"差异"只有内嵌版本串 + 时间戳；
归一化后 `w0` vs `pre1` 也是**全部相同**。本文以**同构建目录、同配置、只回退本次改动**的
`xtb-base` 为主基线（受控对比）。

---

## 7. 被实测证伪/订正的前提（本方向最有价值的产出）

1. **§5.1 #23 的"现状 `静默丢弃`"只对了一半**：旗标确实被静默丢弃，但该调用**今天就不是 exit 0**
   ——`--lts --lopt-engine bfgs` 在 water 上会**真的跑一遍 TS 搜索**（4883 次能量评估）后才因
   "no negative eigenvalue / did not converge" 失败（exit 1）。所以"现状 exit 0"的说法不可核；
   准确的说法是"旗标被丢弃 + 任务白跑，最终因无关原因失败"。**我的测试因此不靠退出码**，
   而是断言"点名 `--lopt-engine`"**且**"输出里没有 `landscape engine: energy evaluations`"（任务没起）。
2. **§17.5 5a 的第一个方案（`case('--strict')` 立即置位）会打红 5 条既有回归测试**
   （实测见 §1.2），爆炸半径超出 F2 登记范围 ⇒ 必须走第二个方案。**设计给的两个方案并非等价。**
3. **§17.5 5b 的清单不完整**（缺 4 个谓词 + 5 个存储点 + 3 个内联 select，见 §1.3），
   照原清单实施会造出**新的静默缺陷**：`--lopt-hessian MODEL` 会被接受、然后跑数值 Hessian。
   反向突变 M5 给出了实证（`Hessian source:           MODEL`）。
4. **`man/` 无需同步**：`man/xtb.1.adoc` 对套件旗标 0 命中（§1.3）。
5. **干净构建的 warning 来源与 AGENTS/父会话的说法不符**：实测 37 条 = `src/prmat.f90` 28 +
   `src/drsp.f` 5（deleted feature，**都在仓库内**，不是 mctc-lib）+ 4 条 PURE 属性不匹配
   （`src/onetri.f90`×2、`src/type/anc.f90`、`src/mctc/linalg.f90`）。**`src/landscape` = 0 条**。
   （AGENTS 写的"39 条来自 mctc-lib"在本次实测下不成立；数字与来源都可核。）
6. **一个冲突会为每个冲突任务子选项各报一次**（非缺陷，但是行为细节）：`--lopt --lscan
   --lscan-coord … --lscan-atoms … --lscan-step … --lscan-nstep …` 会打 5 条同族错误，
   最后一条（`-1-`）是根因 `--lscan`（xtb 的日志从 `-N-` 到 `-1-` 倒序打印）。
   设计 §8.7 只描述了一条消息。**未去重是刻意的选择**：不丢信息（每个冲突旗标都被点名）、
   少一个状态位；`--lopt --lscan` 这种最常见写法只有 1 条。若 review 认为必须去重，
   加一个 `logical` 状态位即可（约 6 行 + 145 个调用点改签名）。
7. **`--hess --lvib-temp 400` 的 before 输出里有一条 `-1- hessian_numhess: Hessian on
   incompletely optimized geometry!`**（未被 strict 放大），说明这条路径本身有 warning——
   与本次改动无关，但值得阶段 2/3 注意。

---

## 8. 未验证 / 残余风险

- **meson 侧未在 meson 下执行**（本机无 meson/ninja）；python 检查器本体与 CMake 脚本已通过真实运行
  （§3.3）。meson 测试名（`landscape runtype conflict` 等）与 CMake 名不同名是既有约定（空格 vs `/`），
  不构成 ctest 重名。
- **BC-4 的 stdout 比较是"归一化后"的**：墙钟、CPU 时间、随机种子、`total power` 行被剔除；
  这些字段本身每次都不同（同二进制两次运行也不同，实测），不能作为不变量。
- **`--md` 只能用 `$seed 42` 才能逐位比**；不加 seed 时 MD 轨迹是随机的（这是既有设计，不是本改动引入）。
- **`select_runtyp` 的冲突检测只在 `parseArguments` 内生效**：xcontrol 的 `runtyp=` 键
  （`set_module.f90:2828`）仍走 `set_runtyp` 的老路径。设计与本次范围都只要求 CLI 侧。
- **未覆盖的组合**：3 个以上互斥 runtype（如 `--lopt --lscan --lts`）会报 2 条冲突（每个都点名），
  已按 §7.6 记为行为细节；没有专门的测试（现有 6 条测试覆盖 2 元冲突与顺序）。
- 仓库根目录有一个**未跟踪**的 `p1-workflow.js`（本会话开始时就在，非本次改动产生）；本次改动的 9 个文件
  全部是 `M`（已改未暂存），`git diff --cached` 为空（**未提交任何东西**）。
- `test/unit/meson.build` 的 6 条 conflict 测试用 pattern = 被拒旗标（不含第一个旗标名与
  "未起任务"断言），CMake 侧断言更严；这是刻意的（`error` 模式的接口限制），已在报告与注释里写明。

---

## 9. 可核证据索引

```
# 构建（0 error；landscape 0 warning）
cmake -S . -B /tmp/xtb-p1/build-clean -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"
cmake --build /tmp/xtb-p1/build-clean -j 8            # → /tmp/p1-clean-build.log（37 warning，明细见 §7.5）

# 测试（增量构建目录与全新配置目录都跑过）
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p1/build -R landscape            # 109/109
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p1/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'   # 12/12
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p1/build-clean -R landscape      # 109/109（全新 configure）
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p1/build-clean -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'  # 12/12
grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d       # 空（0 行）

# 阶段 1 前的二进制（受控基线）：HEAD + 只回退本次改动，同构建目录
git checkout -- src/prog/main.F90 src/landscape/types/settings.f90 src/landscape/types/hessian.f90
cmake --build /tmp/xtb-p1/build -j 8 && cp xtb /tmp/xtb-p1/xtb-base        # 之后恢复改动并重建

# 证据脚本（保留在 /tmp，可按需重跑）
/tmp/p1-bc4/bc4b.sh <outdir> <exe>        # BC-4：文件哈希 + 归一化 stdout
/tmp/p1-bc4/targets.sh                    # §5.1 #20/#21/#23/#25 前后对照
/tmp/mut/run_mutation.sh <name> <mutation.py> <ctest regex>   # 反向突变
```

`git diff --stat -- src test`：

```
 src/landscape/types/hessian.f90       |  11 +-
 src/landscape/types/settings.f90      |  73 ++++--
 src/prog/main.F90                     | 403 +++++++++++++++++++++-------------
 src/xhelp.f90                         |  15 +-
 test/unit/CMakeLists.txt              | 193 ++++++++++++++++
 test/unit/landscape_cli_check.py      | 115 ++++++++++
 test/unit/meson.build                 |  50 +++++
 test/unit/test_landscape_hessian.f90  |   4 +-
 test/unit/test_landscape_settings.f90 |  48 +++-
 9 files changed, 724 insertions(+), 188 deletions(-)
```

设计文档同步：`docs/_simplify-recon/11-cli-redesign.md` 新增 **§10 F4**（套件枚举大小写：error → 接受，
有意变更）、计数 16 → **17**、§10 末 **R36 注**、§17.5 的 5b 风险行补"清单不完整 + man/ 无对象"。
