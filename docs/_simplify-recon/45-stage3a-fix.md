# 45 — 阶段 3a 修复轮（T1..T5）

> 角色：实施 worker。对象 = 仓库 `/home/owenchan/work_path/coding/fortran/xtb`
> （HEAD = `2b49ef8` + 未提交的阶段 3a 工作树）。**本轮只修任务书写明的 5 项**，
> 其余已接受项不返工。
> 构建：`/tmp/xtb-3af/build`（-O2，`WITH_TBLITE=OFF WITH_CPCMX=OFF WITH_TESTS=ON`）。
> 全部 xtb/ctest 调用 `OMP_NUM_THREADS=1`；未跑全量 ctest；未 `git commit`。
> 权威设计：`docs/_simplify-recon/11-cli-redesign.md`（§3.5 / §3.8 / §3.10b / §3.11）。
> 上一轮：`42-stage3a-impl.md`（实施）、`43-stage3a-validation.md`（独立验证）。
> **注意：本轮开始时复核报告 `44-stage3a-review.md` 尚未落盘**
> （已通过 `contact_supervisor` 通知父会话）；T5 的第 2 条（`--help` 三处矛盾）
> 因拿不到复核给的 `file:line`，由我按下文 §5.2 自己穷尽定位（找到 **4** 处，全部修）。

---

## 0. 一句话

修掉了 3a 引入/遗留的 3 个静默缺陷与 1 个不实输出声明：
`--opt <LEVEL>`（档位桥）、`--cycles N`（步数预算桥）**实现映射**、
套件 `--ohess` 的 `analytical hessian` 计时标签按**同一判据**抑制、
`--opt banana` 由静默 normal 改为 `env%error`；
并订正报告 F-4..F-8、登记 BC-4 的有意差异穷尽清单。

---

## 1. 源改动表（逐 T）

| T | 内容 | 落点 | 备注 |
|---|---|---|---|
| T1 | 计时标签 slot 5 改读 `landscape_native_hessian_path(set%runtyp, native_engine)`（与 T1/T2 抑制**同一判据**） | `src/prog/main.F90` `finalize_xtb`（`prtiming(5, …)` 前） | 删掉裸 runtyp 三元 `p_run_hess/ohess/bhess` |
| T2 | `--opt`/`--ohess <LEVEL>` → 套件档位桥（写 `lset%set_conv_level`，**与 `--lopt-level` 同一字段**）+ 有效档位 banner + F3 | `main.F90`：捕获在 `case('-o','--opt')`/`case('--ohess')`；应用在**解析尾**（`--method` 归一分派块之后） | 新纯函数 `landscape_opt_level_to_conv_level` |
| T2 | F3：未知档位 `env%error`（点名 `--opt`） | 同上 | 只在套件路径（`runtyp∈{opt,ohess}` 且 `native_engine==0`）校验；**未动**共享的 `optlevel2int` |
| T3 | `--cycles N` → 逐 runtype `*_settings%max_steps` 映射；`--lvib` 报错；与任务专有旗标冲突报错 | `main.F90`：捕获在 `case('--cycles')` 与 4 个 `--l*-max-steps`；应用在同一解析尾 | 新子程序 `landscape_bridge_step_budget` |
| T4 | 报告/设计订正（F-4..F-8）+ BC-4 正确做法 | `42`/`43`/`11` | 见 §4/§7 |
| T5 | `--ohess` 失败后行为（实测原生）、`--help` 4 处矛盾、BC-4 有意差异穷尽清单 | `src/xhelp.f90`；`11` §19 | 见 §5 |

**"没有第二套判据"**：T1 的计时标签与守卫/抑制/分派/`--ljson` 读的是同一组纯函数
（`effective_landscape_task` / `landscape_is_suite_run` / `landscape_ohess_chain` /
`landscape_native_hessian_path`）；T2/T3 的桥只在**解析尾**读 `set%runtyp` +
`landscape_native_engine`（与 `--method` 归一同一处）。

**核心层**：`git diff --name-only | grep -cE '^src/(type|xtb|mctc|param|io|disp|coulomb)/'` = **0**。

### 1.1 关于 T2/T3 落在"解析尾"而非 `xtbMain` 分派块

设计 §3.5 写的落点是"套件分派处（`effective_landscape_task == p_run_lopt`）"，
`xtbMain` 的分派块确实有该判据。选择解析尾（紧随 `--method` 归一的
`select case (set%runtyp)` 之后）的理由是**把解析态留在解析器内**：

- 桥需要的三个信息 —— `--opt <LEVEL>` 的**原始字符串**（`set%optset%optlev`
  是整数，无法区分 `banana` 与 `normal`，也无法表达套件独有的 `superloose`）、
  `--cycles` 的值与"是否给出"、4 个 `--l*-max-steps` 的"是否给出" —— 全是
  `parseArguments` 的局部量；放到 `xtbMain` 就要新增 ~7 个 `intent(out)` 传参。
- 解析尾的 runtype 分派与 `xtbMain` 的分派读**同一个** `set%runtyp` +
  `landscape_native_engine`（后者在紧邻上方刚解析完），语义完全相同。
- 生效时机在 `xtbMain` 读取 settings **之前**，所以护栏、抑制、`--ljson`、
  计时标签都不受影响。

若父会话要求严格落在 `xtbMain` 分派块，可平移（行为不变，仅传参形态变化）。

---

## 2. 逐 T 真实输出 + 注入（改前红 / 改后绿）

工具：`/tmp/xtb-3af/main.F90.bak` 备份 + `sha256sum -c` 断言还原；每次注入只做一次
文本替换 + 增量构建 + 直接调用对应 python mode。

### T1（事实 A）

改前（`/tmp/xtb-3a/build/xtb`，HEAD+3a）—— 套件 `--ohess` 末尾：

```
453: analytical hessian:
454- * wall-time:     0 d,  0 h,  0 min,  0.000 sec
455- *  cpu-time:     0 d,  0 h,  0 min,  0.000 sec
456- * ratio c/w:       NaN speedup
```

改后（`/tmp/xtb-3af/build/xtb`）：

```
$ xtb landscape_h2o.xyz --gfn 2 --ohess --norestart        # exit=0
$ grep -c 'analytical hessian' out.txt        -> 0
$ grep -c 'landscape optimizer' out.txt       -> 1
$ xtb landscape_h2o.xyz --gfn 2 --ohess --method ancopt --norestart
$ grep -c 'analytical hessian' out.txt        -> 1     # 反向断言：原生仍有该标签
```

**注入**（把 `if (landscape_native_hessian_path(...))` 还原成裸 runtyp 三元）：

```
$ python3 landscape_cli_check.py ohesssuite <exe> <h2o> <dir>
FAIL: --ohess printed 'analytical hessian' 1 times instead of 0      <- 改前红（新令牌）
```

还原后 `ohesssuite` 复绿（§2 末尾）。**改后绿** = 当前 138/138 套件（§3）。

### T2（事实 B）

```
$ --opt tight            -> banner: [NOTICE] landscape convergence level: tight
$ --lopt --lopt-level tight
    cmp xtbopt.xyz  -> IDENTICAL
    cmp xtb.trj     -> IDENTICAL
$ --opt crude --ljson    -> n_steps=3   (banner: superloose)
$ --opt tight --ljson    -> n_steps=5   (banner: tight)
$ --opt banana           -> exit=1, "-1- prog_main_parseArguments: Unknown --opt level 'banana': use crude, sloppy, loose, lax, normal, tight, verytight, extreme, superloose or vtight"
$ --opt tight --lopt-level loose -> exit=1, "run type conflict: --opt already selected the 'opt' run type, --lopt-level would select 'lopt'"
```

**注入**（把 `crude/sloppy/superloose` 分支写死成 `normal`）：

```
FAIL: --opt crude and --opt tight produced the same run (5 steps)
```

> 关于 `--opt tight --lopt-level loose`：**假设被实测证伪**（见 §4.3）——
> `--lopt-level` 自己调 `select_runtyp(env,'lopt',…)`，与 `--opt` 的 `opt` runtype
> 冲突，**在桥之前**就已经非零退出，且消息本就**点名两个旗标**。因此"显式
> `--lopt-level` 高于 `--opt <LEVEL>`"在本 CLI 里**不可达**，桥里不需要（也没有）
> 第二套冲突判定。

### T3（事实 C）

```
$ --lopt --ljson               -> n_steps=5   (默认)
$ --lopt --cycles 4 --ljson    -> n_steps=4
$ --lopt --lopt-max-steps 4    -> n_steps=4
$ --opt  --cycles 4 --ljson    -> n_steps=4   (改派 runtype 同样映射)
$ --lopt --cycles 4 --lopt-max-steps 4 -> n_steps=4 (同值幂等)
$ --lopt --cycles 4 --lopt-max-steps 5 -> exit=1 "--cycles 4 conflicts with --lopt-max-steps 5: give only one step budget"
$ --lvib --cycles 4            -> exit=1 "--cycles has no meaning for --lvib: the frequency task has no step budget"
$ --lscan --cycles 4           -> 映射到 lscan_settings%max_steps（xtbscan.log 仍产出）
$ --opt --method ancopt --cycles 4 -> exit=0，无 "convergence level" 行，无 "landscape:" 行（保持原生语义）
```

**注入**（`if (cycles_given) then` → `if (.false. .and. cycles_given) then`）：

```
FAIL: --lopt --cycles 4 reports 5 steps, --lopt --lopt-max-steps 4 4
```

> **任务书的 `--cycles 8` 与本 fixture 不匹配**：水 fixture 默认 5 步，
> 8 **不 binding**（n_steps 仍 = 默认 5，"小于默认"断言会失败）。改用
> `--cycles 4`（binding：n_steps=4 < 5）。见 §4.4。

### 改后复绿（三条注入均还原 + 复绿）

```
$ sha256sum -c /tmp/xtb-3af/main.sha   -> src/prog/main.F90: OK
$ python3 landscape_cli_check.py ohesssuite …  -> "ohess suite: one minimisation + one frequency analysis, no native Hessian/frequency block"
$ python3 landscape_cli_check.py optlevel …    -> "opt level bridge: --opt tight == --lopt --lopt-level tight, crude 3 != tight 5 steps"
$ python3 landscape_cli_check.py cycles …      -> "cycles map: --cycles 4 == --lopt-max-steps 4 (4 steps, default 5), lvib and conflict refused"
```

---

## 3. 测试注册与计数

### 3.1 新增 2 条 CLI 测试（CMake + meson 两处注册）

| CMake 测试名 | python mode | fixture | 断言要点 |
|---|---|---|---|
| `xtb/landscape-opt-level-bridge` | `optlevel` | `landscape_h2o.xyz` | `--opt tight` 与 `--lopt --lopt-level tight` 的 `xtbopt.xyz`/`xtb.trj` **逐位相同**；banner 含 `tight`；`--opt crude`(3 步) != `--opt tight`(5 步)；`--opt banana` 非零 + 点名；`--opt tight --lopt-level loose` 非零 |
| `xtb/landscape-cycles-map` | `cycles` | `landscape_h2o.xyz` | `--lopt --cycles 4` == `--lopt --lopt-max-steps 4` == `--opt --cycles 4`（n_steps=4）且 < 默认 5；同值幂等；异值冲突非零且点名 `--lopt-max-steps`；`--lvib --cycles 4` 非零且含 `--cycles has no meaning for --lvib` |

### 3.2 既有测试的**加强**（T1）

| 位置 | 改动 |
|---|---|
| `landscape_cli_check.py::check_ohess_suite_once` | token 循环加 `("analytical hessian", 0)`（**新令牌**，改前必红） |
| `landscape_cli_check.py::check_ohess_native_hess` | token 循环加 `("analytical hessian", 1)`（反向） |
| `main()` | 新增 `optlevel`/`cycles` 两个 mode 分派 |
| `CMakeLists.txt` | 2 个 `add_test` + 加进 `set_tests_properties(... OMP_NUM_THREADS=1)` 名单 |
| `meson.build` | 2 个 `test(...)` 条目（镜像 CMake） |

### 3.3 计数（改动后，`/tmp/xtb-3af/build`）

```
$ ctest -N -R landscape | tail -1          -> Total Tests: 138        (136 + 2)
$ ctest -R landscape | tail -1             -> 100% tests passed, 0 tests failed out of 138
$ ctest -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
                                           -> 100% tests passed, 0 tests failed out of 12
$ grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d   -> 空
$ grep -oE "^test\('[^']+'"  test/unit/meson.build | sort | uniq -d        -> 空
$ python3 test/unit/landscape_help_check.py src/prog/main.F90 src/xhelp.f90
  -> dialect A/B: difference = 0 ; PASS: set S is documented by `--help` in both dialects
$ git diff --name-only | grep -cE '^src/(type|xtb|mctc|param|io|disp|coulomb)/' -> 0
```

> **测试隔离观测（非本轮引入，登记）**：`xtb/GFN2-FF` 会读取工作目录里裸名的
> `charges`（`src/gfnff/gfnff_ini.f90:534`）。我早前**并行**跑了两次 ctest，
> 期间工作目录里留下了一个与 caffeine 拓扑不匹配的 `charges`，使该测试
> `ERROR STOP`。实测判定：**与本轮改动无关**（3a 旧二进制放在被污染目录里同样失败，
> 本轮二进制放在干净目录里通过）；清掉残留后回归子集 **12/12**。
> 复现：`rm -f <build>/test/unit/charges` 后重跑即绿。这属于既有测试隔离缺陷，
> 不在本轮范围。

---

## 4. 被证伪的前提 / 订正（事实 D：F-4..F-8 + 本轮新发现）

### 4.1 F-4（父会话的 `--ohess` 三能量不可复现）—— **成立，机理已定位**

验证报告 §9 F-4 已给出真值；本轮用 `--ohess` 直接复测，真值是
`-5.070544447778`（TOTAL ENERGY）。父会话的 `-5.070544447444` 系 `head -3`
抓到**初始几何**的 `TOTAL ENERGY` 行所致的**测量方法**错误，不是数值问题。
**订正指针已加进 `42` §2.3 与 `43` §9（原文保留）。**

### 4.2 F-5（`42` §3 inj1 行号陈旧）—— 成立

`injections.log` 表里 inj1 的"去掉 `:938` 的原生块抑制"应为 `:987`（`42` §1 表本身
写对了）。**订正指针已加进 `42` §3。**

### 4.3 F-6（F1 的"10 处 `$opt`"被自身改动刷新为 20）—— 成立

**订正指针已加进 `42` §4.1 F1。**

> 本轮的独立证伪（新）：设计/任务书的
> "显式 `--lopt-level` **高于** `--opt <LEVEL>`，异值 ⇒ error" **不可达**。
> `--lopt-level` 在自己的 `case` 里调 `select_runtyp(env,'lopt',…)`
> （`main.F90`），与 `--opt` 的 `opt` runtype 冲突 =>
> `--opt tight --lopt-level loose` 在桥之前就 exit 1，且消息是
> `run type conflict: --opt already selected the 'opt' run type, --lopt-level would
> select 'lopt'`（**本就点名两旗标**）。因此桥里**不实现**该优先级（避免死代码），
> 测试 `xtb/landscape-opt-level-bridge` 用 exit≠0 钉住可观测行为。

### 4.4 本轮新证伪（任务书 figment）：`--cycles 8` 不 binding

任务书 T3 的测试写 `--lopt --cycles 8` "小于默认"。实测水 fixture 默认 **5 步**，
budget 8 不 binding ⇒ n_steps 仍 = 5，"小于默认"必失败。改用 `--cycles 4`
（n_steps=4 < 5），并在测试文档串里写明。

### 4.5 F-7（BC-4 的"stdout 逐行相同"不稳健）—— 成立，**正确做法已写入**

改前 BC-4 声称"文件逐位相同 **且 stdout 逐行相同**"。实测（验证报告 §5/§7.2 F-1）：
归一化器只覆盖**带百分号**的计时行，漏掉无百分号的
`SCC setup/iterations ... 0 min, X sec`；同一二进制重跑该行即变（秒数与百分比都动）。
**正确做法（已登记进 `42`/`43`/设计 §19）**：

> BC-4 = **输出文件逐位相同** + stdout 的差异**只有**已登记的非确定性
> （版本串 `(<hash>|unknown-commit)`、日期、随机种子、`program call`、回溯地址、
> **以及计时行的秒数/无百分号行**），不再声称"逐行相同"。
> 漏掉的计时行形态记入报告（见下）。

### 4.6 F-8（守卫运行时 `[NOTICE]` 不打印）—— 成立

`42` §4.2 的机理句"同一运行的 `[NOTICE]` 行也含该子串"应订正为：
**守卫先于 `[NOTICE]` 触发**（守卫运行时 `[NOTICE]` 计数 = 0），子串污染只发生在
"守卫被关掉、运行放行到 `[NOTICE]`"的路径。修法正确，机理句已订正（**订正指针进 `42` §4.2**）。

---

## 5. T5 处置（逐条判定）

### 5.1 `--ohess` 失败后仍跑 vib 链 —— **对齐原生，No change**

**实测原生**（水，失真几何，`OMP_NUM_THREADS=1`）：

```
$ xtb dist.xyz --gfn 2 --ohess --method ancopt --cycles 1 --norestart    -> exit=0
  *** FAILED TO CONVERGE GEOMETRY OPTIMIZATION IN 1 ITERATIONS ***
  Numerical Hessian        1
  Frequency Printout       1
  写出 hessian / vibspectrum / g98.out / xtbopt.xyz
```

即**原生 `--ohess` 在优化未收敛时照样跑 `main_freq`**（exit 0）。
套件侧代码路径同样没有在第一段 `run_landscape` 与 vib 链之间插 `env%check`
（`main.F90` ohess 链），所以套件**也**跑 vib —— **与原生一致**。
唯一差别是 **exit code**：套件的优化未收敛是 `env%error`（`src/landscape/tasks/opt.f90:216`，
exit 1；这是套件已验收的契约），原生是 exit 0（上游怪癖）。
判定：**行为已对齐（都产出频率），无需改码**；exit code 差异**有意**，登记。

### 5.2 `--help` 文本与行为矛盾 —— **改前 4 处，逐条修**

复核报告 44 未落盘，我按"3a 已改派但 help 仍写原生"的判据自行穷尽，找到 **4** 处
（比复核说的"三处"多一处 `--ohess`）：

| # | 位置 | 原文（矛盾处） | 处置 |
|---|---|---|---|
| 1 | `src/xhelp.f90` `-o, --opt [LEVEL]` | "call ancopt(3) to perform a geometry optimization, levels from crude, sloppy, loose, normal (default), tight, verytight to extreme can be chosen" | **修**：改为套件执行 + `--method ancopt` 为原生出口 + 列出接受的上游名与 `superloose` |
| 2 | `src/xhelp.f90` `--method NAME` | "a landscape name is refused until --opt is dispatched to the suite" | **修**：改为"a landscape name selects the suite that the redeployed --opt runs" |
| 3 | `src/xhelp.f90` `--lopt` | "(use --opt for that block, or --lscan …)" | **修**：`--opt` 自身也拒绝 `$scan` ⇒ 改为 `--opt --method ancopt` |
| 4 | `src/xhelp.f90` `--ohess [LEVEL]` | "perform a numerical hessian calculation on an ancopt(3) optimized geometry" | **修**：改为套件最小化 + 套件频率；原生路径 = `--ohess --method ancopt` |

`--help` 集合覆盖检查（`landscape_help_check.py`）改动后仍 PASS（集合 S 差集 0，
§3.3），`xtb/Argparser_print_help` 仍绿。**自指引导全文清理仍属 3b（不做）。**

### 5.3 BC-4 的"唯一有意例外"穷尽清单 —— 登记进设计 §19

3a + 本轮**有意**改变的 stdout/文件/退出码差异（穷尽；未列出者 = 逐位不变）：

**stdout**
1. `[NOTICE] --opt now runs the landscape suite …` / `[NOTICE] --ohess now runs …`
   （改派 run 每次一行）—— 42 §1。
2. `[NOTICE] landscape convergence level: <level>`（本轮 T2，改派 run）—— 新增。
3. 计时表 slot 3：改派 run 打 `landscape optimizer`，不再打 `ANC optimizer`；
   套件 `--ohess` **不再**打 `analytical hessian`/`numerical hessian`（本轮 T1）。
4. `--ljson` 对改派 `--opt` **不再**打 `writes nothing without a landscape run type`。
5. F3 新错误文本 `Unknown --opt level '<x>'`（本轮 T2）。
6. T3 新错误文本 `--cycles has no meaning for --lvib …` 与
   `--cycles N conflicts with --lopt-max-steps M …`（本轮 T3）。
7. 三条护栏文案（`$scan`/周期/`$opt`）在 `--opt`（及 C7 的 `--lopt`）出现（42 §1）。

**写入的文件（集合）**
8. `--opt --ljson` 写 `landscape_opt.json`（旧为告警不写）。
9. `--ohess --ljson` 写 `landscape_opt.json` **加** `landscape_vib.json`（42 §4.1 F5/§18.6）。
10. `--ohess` 套件链写 `hessian`/`vibspectrum`/`g98.out`/`vib_normal_modes`/`xtbopt.xyz`
    （内容来自套件）。
    **订正（父会话，依据 48 号复核的 P2-3）**：原文写「**文件名集合与原生相同**」是**不实陈述**，与设计 §5.4 的实测表自相矛盾。
    准确事实：套件链**缺** `.xtboptok` 与 `xtbopt.log`（原生有），**多** `xtb.trj`（原生无）；
    设计 §5.4 已把这三项登记为 **B 类破坏**，由 **3b 的 R4（§3.9）**补写清零
    （`.xtboptok` 仅收敛时创建、`xtbopt.log` 逐帧写、`xtb.trj` 作为**新增**保留）。
    ⇒ **阶段 3a 单独不可发布**：在 3b 落地之前，`--opt`/`--ohess` 的**收敛哨兵与轨迹日志消失**。
    以设计 §5.4 的表为准；本条原文不再作为结论依据。

**退出码**
11. C7：`--lopt --input <含 $opt>` exit 0 → 1（42 §5.2 已登记）。
12. 三条护栏：`--opt --input <$scan/周期/`$opt`>` exit ≠ 0（新）。
13. F3 `--opt banana` exit → 1（新）。
14. T3 `--lvib --cycles`、`--cycles/--lopt-max-steps` 异值 exit → 1（新）。

**数值（几何/能量）**
15. 改派 `--opt` 现在**真的**响应 `--opt <LEVEL>`/`--cycles N`，
    所以其结果可不同于（坏掉的）3a 值；但**等于** `--lopt --lopt-level <mapped>`。

**明确"不变"（BC-4 断言，§3.3）**：`--sp/--hess/--bhess/--md/--lscan/--lts/--lirc/--lvib`
（未给新旗标时）、原生 `--opt --method ancopt`、`--ohess --method ancopt`、
以及**未给 `--cycles` 的 `--lopt`**，输出文件逐位不变。

---

## 6. T1 附带核对：计时表穷尽审计

`grep -n "prtiming\|start_timing" src/prog/main.F90` 全看一遍（slot / 打印条件 /
启动落点 / 是否可能在套件路径上为 0）：

| slot | 标签 | 打印判据 | `start_timing` 落点 | 套件路径上会为 0？ |
|---|---|---|---|---|
| 1 | `total` | 无条件 | 程序开头 | 否 |
| 2 | `SCF` | `runtyp ≠ prescc` | 单点前（846 等） | 否（套件也做 SCF） |
| 3 | `ANC optimizer` | native opt/ohess/omd/metaopt **且非套件** | 996 | 否（仅原生） |
| 3 | `landscape optimizer` | `effective==p_run_lopt` | 1078（opt/ohess）、lopt 块 | 否 |
| 3 | `landscape scan` | `runtyp==lscan` | 1144 | 否（lscan 恒为套件） |
| 3 | `landscape frequencies` | `runtyp==lvib` | 1209 | 否 |
| 3 | `landscape IRC` | `runtyp==lirc` | 1193 | 否 |
| 4 | `path finder` | `runtyp==path` | 1556 | 否 |
| 5 | `analytical/numerical hessian` | **裸 runtyp**（旧） | 1304（原生 Hessian 块内） | **是 ⇒ T1 修复** |
| 6 | `MD` | md/omd/metaopt | 1489/1519 | 否 |
| 8 | `screen` | `runtyp==screen` | 1564 | 否 |
| 9 | `mode following` | `runtyp==modef` | 1575 | 否 |
| 10 | `MD opt.` | `runtyp==mdopt` | 1583 | 否 |
| 11 | `dipro` | `dipro%diprocalc` | 832（同块内） | 否（自带 timer 后 `terminate(0)`） |

**结论：slot 5 是本文件里唯一"按裸 runtyp 判定、在套件路径下必然为 0"的标签**
（只有它的 `start_timing` 落在被谓词抑制的原生块内）。其余标签的 timer 与本标签
在同一路径上启动，或该 runtype 根本不改派。

---

## 7. 报告/设计文档订正（留痕：原文保留 + 加订正指针）

| 文件 | 位置 | 订正 |
|---|---|---|
| `42-stage3a-impl.md` | §2.3 | `[订正 R45-F4]` 父会话三能量不可复现，真值见 §4.1；测量法错误 |
| `42-stage3a-impl.md` | §3 注入表 inj1 | `[订正 R45-F5]` 落点是 `:987`（非 `:938`） |
| `42-stage3a-impl.md` | §4.1 F1 | `[订正 R45-F6]` 数字已被自身改动刷新为 **20** 处 |
| `42-stage3a-impl.md` | §4.2 | `[订正 R45-F8]` 守卫运行时 `[NOTICE]` 不打印；污染只在守卫被禁路径 |
| `42-stage3a-impl.md` | §5.2 | `[订正 R45-F7]` 不再声称 stdout"逐行相同"，改为"文件逐位相同 + 仅计时等已登记非确定性"；补归一化器漏掉的行形态 |
| `43-stage3a-validation.md` | §9 F-4/F-5/F-6/F-7/F-8 | `[订正 R45]` 各加"已由 45 落盘并订正 42/设计"指针 |
| `11-cli-redesign.md` | 新增 §19 | 阶段 3a 修复轮登记：T1-T3 桥与不实标签 + **BC-4 有意差异穷尽清单** + `--help` 4 处 |

---

## 8. 残留风险 / 建议

1. **R-1（低）**：T2/T3 桥落在解析尾而非 `xtbMain` 分派块（§1.1），如父会话坚持设计
   字面落点，可平移，行为不变。
2. **R-2（低）**：`--opt <LEVEL>` 与 `--cycles` 的优先级规则里，与 `--lopt-level` 的
   冲突**结构上不可达**（§4.3），故只测"非零退出"，未实现死代码。
3. **R-3（低，既有）**：`xtb/GFN2-FF` 与工作目录里裸名 `charges` 耦合（§3.3），
   并行跑 ctest 时会偶发红；与本轮无关，建议后续加 `--namespace` 或用 RUNDIR 隔离。
4. **R-4（不可验证）**：`meson`/`ninja` 本机未安装，meson 的两条新条目无法本地执行，
   与实现/验证报告自报一致。
5. **下一步**：3b（档位四轴 `e_tol`/`acc`/`max_steps` 随档位、4 个遗留文件、§3.9、
   自指引导全文）—— 本轮**未做**，以免动已验收数字。
