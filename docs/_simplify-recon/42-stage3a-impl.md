# 42 — CLI 重设计阶段 3a 实施报告：`--opt`/`--ohess` 改派 + 三条守卫

> 状态：**骨架 + 第 1 步（测试注册与运行）已完成**；第 2 步（注入实验）、第 3 步（BC-4）、
> 设计文档订正见下文各节（本节写作时后续步骤正在进行，完成后逐节补齐）。
> 权威设计：`docs/_simplify-recon/11-cli-redesign.md` §3.8 / §3.11 / §3.11.1 / §4.7 / §4.8 / §10(C7)。
> 构建：`/tmp/xtb-3a/build`（-O2，`WITH_TBLITE=OFF WITH_CPCMX=OFF WITH_TESTS=ON`），HEAD = `2b49ef8`。

---

## 0. 本轮做了什么（一句话）

`--opt`/`--ohess` 的 run type **不变**（仍是 `p_run_opt`/`p_run_ohess`），但**由 landscape 套件执行**；
原生 ANCopt 家族改由 `--method ancopt|lancopt|fire|pbc_lbfgs` 到达。
判据只有一套：4 个纯函数（`effective_landscape_task` / `landscape_is_suite_run` /
`landscape_ohess_chain` / `landscape_native_hessian_path`），
守卫、抑制、分派、`--ljson`、计时标签**全部**读它们（不存在第二套 `native_engine == p_engine_rf` 判据）。

---

## 1. 源改动表（逐 T）

| T | 内容 | 落点（HEAD 后行号） | 备注 |
|---|---|---|---|
| T1 | 4 个纯函数 | `src/prog/main.F90:4521/4546/4570/4591` | `effective_landscape_task`(4521)、`landscape_is_suite_run`(4546)、`landscape_ohess_chain`(4570)、`landscape_native_hessian_path`(4591)；每个 `select case` 都有 `case default` 赋值 |
| T1 | 分派/守卫读点改读谓词 | `main.F90:520`（三守卫）、`:1045`（`--ljson`）、`:1069`（lopt 分派）、`:1291`（T1 原生 Hessian）、`:1421`（T2 原生频率）、`:1457`（原生 `xtbopt.xyz` 二次写）、`:5054`（计时标签） | `grep -n "p_run_l" main.F90` 穷尽核对见 §1.1 |
| T2 | `--opt`/`--ohess` 改派 + `[NOTICE]` | `main.F90:1055-1066` | `[NOTICE]` 写 `env%unit`（stdout，R11），每次运行一次；文案**不点名算法**（`--opt --method bfgs` 合法 ⇒ 写死 "lbfgs" 会错） |
| T2 | `--ohess` = opt 链 + vib 链 | `main.F90:1069-1130`（`landscape_ohess_chain` 分支，`run_landscape(lvset)` 第二次调用） | 与原生 `main_geometry`+`main_freq` 两调用同构 |
| T3 | R24 抑制原生 `anyopt` 块 | `main.F90:987` `if (anyopt .and. landscape_native_engine /= 0)` | `:328`/`:333`（CPCM-X/PTB terminate）**未动** |
| T4 | R29/T1+T2 抑制 | `main.F90:1291`（`numhess`）、`:1421`（`main_freq`） | 均改读 `landscape_native_hessian_path` |
| T4 | R29/T3 `fres` 桥（`anyhess` **不动**） | `main.F90:1106-1130`；`fres%etot`=:1121、`fres%htot`=:1126、`fres%gtot`=:1127 | 桥在 vib 链之后、`res` 写回之后 |
| T4 | 抑制集合：原生 `xtbopt.xyz` 二次写、计时标签 | `main.F90:1457`、`:5050-5057` | 计时标签需把 `native_engine` 传进 `finalize_xtb`（`:5022` 签名 + `:783`/`:1612` 两个调用点） |
| T5 | 三条守卫（一个落点） | `main.F90:498-557` | 触发条件统一 `landscape_is_suite_run(set%runtyp, landscape_native_engine)`；三条文本均含 `--method ancopt`；`env%checkpoint` 标签改为 `the run type does not execute this xcontrol block` |
| T5 | `set%xcontrol_supplied`（**裁定 (B)**） | 声明 `src/setparam.f90:533`（`TSet` 内，**未碰 `src/type`**）；置位 `src/set_module.f90:824`（`case('opt')`，受 `do_mark` 约束）+ `:2907/2923-2931`（legacy `$set` 六个 opt 键） | 不进 `write_set_opt`（`TSet` 标量本就不在其中，先例 `set%randseed_set`） |
| T5 | C7 判据 = **来源**（`.xtbrc` 那次不置位） | `src/set_module.f90:731/743/772`（`rdcontrol` 新可选参 `from_input`）+ `:855-863`（`$set` 分支 save/restore）；调用点 `src/prog/main.F90:411` `from_input=.false.` | 不按文件名豁免（`--input .xtbrc` 仍守卫） |
| T6 | 移除 R39 | `main.F90:4325`（`case (p_run_lopt, p_run_opt, p_run_ohess)`）、`:4360-4370`（原拒绝分支删除，`case default` 文案加 `--opt`） | `grep -c "would have no effect"` = 0 |
| T7 | `--ljson` 按有效任务触发 | `main.F90:1045` | `--opt --ljson` 真写 `landscape_opt.json`（与 `--lopt --ljson` 的 `counters.n_steps` 相同，见 §2） |
| — | 套件结果新增 `vib` 组件 + `energy` | `src/landscape/types/results.f90`（`landscape_vib_result%energy`、`landscape_result%vib`）；`src/landscape/tasks/vib.f90:272-273` | `vib%energy` 必须在两次 `intent(out)` 调用**之后**赋值（`landscape_vib_analysis` 的 `intent(out)` 会重置整个派生类型 —— 实测踩到，见 §4） |

### 1.1 `p_run_l*` 读点穷尽核对（T1 的"没有第二套判据"证据）

```
$ grep -n "p_run_l" src/prog/main.F90
520   if (landscape_is_suite_run(set%runtyp, landscape_native_engine)) then   <- 三守卫（改）
526/528/530/532/534  lruntyp_flag = '--opt'/... <- 仅用于错误文本点名旗标（select case 内）
672   case (... p_run_lopt, p_run_lscan, p_run_lts, p_run_lvib, p_run_lirc)  <- 参数文件选择，与改派无关（未动）
1045  if (lset%ljson .and. .not. landscape_is_suite_run(...))                 <- 改
1069  if (effective_landscape_task(...) == p_run_lopt) then                   <- 改
1092  if (effective_landscape_task(...) == p_run_lscan) then                  <- 改
1108  if (effective_landscape_task(...) == p_run_lts) then                    <- 改
1138  if (effective_landscape_task(...) == p_run_lirc) then                   <- 改
1157  if (effective_landscape_task(...) == p_run_lvib) then                   <- 改
4325  case (p_run_lopt, p_run_opt, p_run_ohess)                               <- `--method` 套件名分派（设计 §4.7 明写按 runtyp）
5054  if (effective_landscape_task(set%runtyp, native_engine) == p_run_lopt)  <- 改
```

---

## 2. 测试注册表（第 1 步产物）

### 2.1 新增 9 条（三处注册：`main()` 分派 + `test/unit/CMakeLists.txt` + `test/unit/meson.build`）

| CMake 测试名 | python mode | 断言要点 |
|---|---|---|
| `xtb/landscape-opt-alias-once` | `optalias` | `--opt` 跑套件一次（`landscape: lbfgs minimisation`=1、`ANC micro-cycles`=0、`[NOTICE]`、写 `landscape_opt.json`），且 `counters.n_steps` == `--lopt` |
| `xtb/landscape-opt-native-exit` | `optnative` | 4 个原生出口（ancopt/lancopt/fire/pbc_lbfgs）各自走原生、无 `landscape: `、无 `[NOTICE]`、**不写** json |
| `xtb/landscape-opt-scanblock` | `optguard scanblock` | `--opt --input <$scan>` → exit≠0 + 文本含 `--method ancopt` + 无 `xtbscan.log`；基线 `--opt --method ancopt` 同输入 → exit 0 + `RELAXED SCAN` + 写 `xtbscan.log` |
| `xtb/landscape-opt-pbc` | `optguard pbc` | 周期 fixture（`assets/inputs/coord/quartz.3d.coord`）+ `--gfnff --opt` → exit≠0 + `--method ancopt`；基线 `--opt --method ancopt` → exit 0 + `current lattice:` |
| `xtb/landscape-opt-xcontrol` | `optguard xcontrol` | `--opt --input <$opt optlevel=tight>` → exit≠0 + `--method ancopt`；基线原生 exit 0；**C7 全量作用域**：`--lopt` 同输入也 exit≠0 |
| `xtb/landscape-opt-xtbopt-once` | `optxtbopt` | `optimized geometry written to:`=0、`wrote xtbopt.xyz`=1、计时块含 `landscape optimizer` 不含 `ANC optimizer`；`--namespace c1` → 只写 `c1.xtbopt.xyz` |
| `xtb/landscape-ohess-suite-once` | `ohesssuite` | `Numerical Hessian`=0、`Frequency Printout`=0、`ANC micro-cycles`=0、`landscape: lbfgs minimisation`=1、`landscape: harmonic frequencies`=1、`landscape engine: Hessians           1`=1；`hessian`/`vibspectrum`/`g98.out`/`xtbopt.xyz` 存在 |
| `xtb/landscape-ohess-native-hess` | `ohessnative` | 反向：`--ohess --method ancopt` → `Numerical Hessian`=1、`Frequency Printout`=1、`landscape: harmonic frequencies`=0 |
| `xtb/landscape-ohess-fres-bridge` | `ohessbridge` | `--ohess` 的 `TOTAL ENERGY`≠0、`TOTAL ENTHALPY`/`TOTAL FREE ENERGY` 与同末几何 `--lvib` 的 `total enthalpy H(T)`/`G(T)` 差 ≤1e-6 Eh |

### 2.2 被改派改变的既有测试（同步）

| 位置 | 改动 |
|---|---|
| `landscape_cli_check.py::check_scanblock` | `--opt` 段**反转**：由"断言执行 `$scan`"改为"断言拒绝 + 点名 `--method ancopt` + 不写 `xtbscan.log`"，并新增基线 `--opt --method ancopt` 执行之 |
| `landscape_cli_check.py::check_method_native` | 裸 `--ohess` 段改为断言**套件路径**（`landscape: harmonic frequencies`、无 `ANC micro-cycles`、写 `hessian`/`vibspectrum`）；原生侧由 `--ohess --method ancopt` 承担（新增 `Numerical Hessian` 断言） |
| `landscape_cli_check.py::check_method_native` | 删除 R39 的 `native-reject-opt`/`native-reject-ohess` 段，替换为**正向**断言 `--opt/--ohess --method bfgs` → `landscape: bfgs minimisation`（T6 的可证伪断言） |
| `landscape_cli_check.py::check_method_native`（U15） | `u15-xcontrol-only`/`u15-xcontrol-twice` 改走 `--opt --method ancopt`（裸 `--opt` + `$opt` 现在正是 C7 拒绝的对象）；循环改为带显式期望 token |
| `landscape_cli_check.py::check_native_opt_symbols` | 由 `--opt --input <$opt engine=lbfgs>` 改为 `--opt --method lancopt`（同一引擎 `p_engine_lbfgs`，三重断言不变：严格解码 + 控制字节扫描 + 符号列比对） |
| 注释/文案 | `landscape_cli_check.py` 顶部 mode 表、`check_scanblock`/`check_opt_namespace`/`check_method_native` 文档串、`CMakeLists.txt`（`--opt` 归入套件的说明、`native-opt-lbfgs-symbols` 注释） |

### 2.3 第 1 步的真实输出（9/9 通过）

```
$ ctest -R "landscape-opt-alias-once|...|landscape-ohess-fres-bridge" -V
1/9 Test #208: xtb/landscape-opt-alias-once ......   Passed    0.09 sec
2/9 Test #209: xtb/landscape-opt-native-exit .....   Passed    0.10 sec
3/9 Test #210: xtb/landscape-opt-scanblock .......   Passed    0.07 sec
4/9 Test #211: xtb/landscape-opt-pbc .............   Passed    1.13 sec
5/9 Test #212: xtb/landscape-opt-xcontrol ........   Passed    0.08 sec
6/9 Test #213: xtb/landscape-opt-xtbopt-once .....   Passed    0.08 sec
7/9 Test #214: xtb/landscape-ohess-suite-once ....   Passed    0.07 sec
8/9 Test #215: xtb/landscape-ohess-native-hess ...   Passed    0.06 sec
9/9 Test #216: xtb/landscape-ohess-fres-bridge ...   Passed    0.09 sec
100% tests passed, 0 tests failed out of 9
```

（CMake 包装脚本只在失败时回显 stdout，所以上表不显示各 check 自己的 `print`；下表是直接调用
同一 mode、同一参数的**逐条真实输出**，命令见 §2.4。）

```
landscape-opt-alias-once      opt alias: --opt ran the suite (5 steps, same as --lopt)
landscape-opt-native-exit     opt native exit: --method ancopt     -> ANC micro-cycles
                              opt native exit: --method lancopt    -> L-ANC optimizer
                              opt native exit: --method fire       -> initial time step
                              opt native exit: --method pbc_lbfgs  -> current lattice:
landscape-opt-scanblock       opt guard scanblock: refused with '--method ancopt', native exit runs it
landscape-opt-pbc             opt guard pbc: refused with '--method ancopt', native exit runs pbc_lbfgs
landscape-opt-xcontrol        opt guard xcontrol: refused for --opt and --lopt, native exit honours it
landscape-opt-xtbopt-once     opt xtbopt: one writer, landscape timer, namespace honoured
landscape-ohess-suite-once    ohess suite: one minimisation + one frequency analysis, no native Hessian/frequency block
landscape-ohess-native-hess   ohess native: native Hessian and frequency path kept
landscape-ohess-fres-bridge   ohess bridge: TOTAL ENERGY -5.070544447778, H(T) -5.046638762610 (--lvib -5.046638762610)
```

> `[订正 R45-F4]`（`45-stage3a-fix.md` §4.1）父会话当时给出的 `--ohess` 三能量
> `-5.070544447744 / -5.046638712638 / -5.068045136132` **不可复现**；真值是上表的
> `-5.070544447778`（与 `43-stage3a-validation.md`、实施者二进制、独立构建三方一致）。
> 原因是 `head -3` 抓到了**初始几何**的 `TOTAL ENERGY` 行——是**测量方法**错误，
> 不是数值差异。原文保留。

### 2.4 复现命令

```bash
export OMP_NUM_THREADS=1 XTBPATH=$PWD      # 仓库根
cd /tmp/xtb-3a/build/test/unit
python3 $REPO/test/unit/landscape_cli_check.py optalias  /tmp/xtb-3a/build/xtb $PWD/landscape_h2o.xyz /tmp/xtb-3a/newout/a
python3 $REPO/test/unit/landscape_cli_check.py optnative /tmp/xtb-3a/build/xtb $PWD/landscape_h2o.xyz /tmp/xtb-3a/newout/b
python3 $REPO/test/unit/landscape_cli_check.py optguard /tmp/xtb-3a/build/xtb $PWD/landscape_h2o.xyz /tmp/xtb-3a/newout/c scanblock
python3 $REPO/test/unit/landscape_cli_check.py optguard /tmp/xtb-3a/build/xtb $REPO/assets/inputs/coord/quartz.3d.coord /tmp/xtb-3a/newout/d pbc
python3 $REPO/test/unit/landscape_cli_check.py optguard /tmp/xtb-3a/build/xtb $PWD/landscape_h2o.xyz /tmp/xtb-3a/newout/e xcontrol
python3 $REPO/test/unit/landscape_cli_check.py optxtbopt /tmp/xtb-3a/build/xtb $PWD/landscape_h2o.xyz /tmp/xtb-3a/newout/f
python3 $REPO/test/unit/landscape_cli_check.py ohesssuite /tmp/xtb-3a/build/xtb $PWD/landscape_h2o.xyz /tmp/xtb-3a/newout/g
python3 $REPO/test/unit/landscape_cli_check.py ohessnative /tmp/xtb-3a/build/xtb $PWD/landscape_h2o.xyz /tmp/xtb-3a/newout/h
python3 $REPO/test/unit/landscape_cli_check.py ohessbridge /tmp/xtb-3a/build/xtb $PWD/landscape_h2o.xyz /tmp/xtb-3a/newout/i
```

### 2.5 计数与重名

- `ctest -N -R landscape`（注册后）见 §5；重名检查：
  `grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d` → **空**；
  `grep -oE "^test\('[^']+'" test/unit/meson.build | sort | uniq -d` → **空**。
- `grep -c "would have no effect" src/prog/main.F90` → **0**（R39 清零）。

---

## 3. 注入实验（14 条，每条"改什么 → 哪个测试红 → 真实输出 → 还原复绿"）

工具：`/tmp/xtb-3a/inject.py`（对 `src/prog/main.F90` 做单点文本替换 → 增量构建 3.5 s → 直接调用对应 python mode →
还原 → **`sha256` 断言还原逐字节相同** → 再构建 → 复绿）。原始日志：`/tmp/xtb-3a/injections.log`。

| # | 注入（改什么） | 期望红的测试 | 真实红输出（FAIL 行） |
|---|---|---|---|
| 1 | 去掉 `:938` 的原生块抑制（`if (anyopt .and. landscape_native_engine /= 0)` → `if (anyopt)`） | `optalias` | `FAIL: --opt ran the native ANCopt as well` |

> `[订正 R45-F5]`（`45-stage3a-fix.md` §4.2）本表 inj1 的行号 `:938` 是 3a 前的陈旧值，
> HEAD 后真实落点是 **`:987`**（§1 表已写对）。原文保留。
| 2 | T1 `:1291` 谓词退回 runtyp 三元 ⇒ 套件 `--ohess` 也调 `numhess` | `ohesssuite` | `FAIL: --ohess printed 'Numerical Hessian' 1 times instead of 0` |
| 3 | T2 `:1421` 谓词退回 runtyp 三元 ⇒ 第二个 `main_freq` | `ohesssuite` | `FAIL: --ohess printed 'Frequency Printout' 1 times instead of 0` |
| 4 | **半修**：桥保留但 `fres%etot = 0.0_wp` | `ohessbridge` | `FAIL: --ohess reports TOTAL ENERGY 0: the frequency container was printed but not filled` |
| 4b | 桥填错字段：`fres%htot = 0.0_wp` | `ohessbridge` | `FAIL: --ohess TOTAL ENTHALPY -5.070544447778 differs from --lvib -5.046638762610` |
| 5 | `anyhess` 对套件置假（**注意加括号**，见 §4.1） | `ohessbridge` | `FAIL: expected exactly one TOTAL ENTHALPY line, found 0` |
| 6 | 关掉守卫 (a) `$scan` | `optguard scanblock` | `FAIL: --opt accepted the xcontrol $scan block` |
| 7 | 关掉守卫 (b) 周期 | `optguard pbc` | `FAIL: the refusal is not the periodic guard of the redeployed --opt` |
| 8 | 关掉守卫 (c) `$opt` | `optguard xcontrol` | `FAIL: --opt accepted the xcontrol $opt block` |
| 9 | `landscape_is_suite_run` 恒真 | `optnative` + `optguard scanblock` | `FAIL: --opt --method ancopt announced a redeployment` / `FAIL: the native exit refused the $scan block (exit 1)` |
| 10 | 恢复 R39 拒绝（`case (p_run_lopt, p_run_opt, p_run_ohess)` → `case (p_run_lopt)`） | `methodnative` | `FAIL: stage3-opt-suite-method: exit status 1` |
| 11 | `--ljson` 判定退回旧 runtyp 列表 | `optalias` | `FAIL: --ljson reported the redeployed --opt as a run type that knows nothing about the switch` |
| 12 | 去掉原生 `xtbopt.xyz` 二次写的抑制 | `optxtbopt` | `FAIL: --opt printed the native geometry message as well` |
| 13 | 计时标签退回 runtyp-only | `optxtbopt` | `FAIL: the timing block does not name the landscape optimiser` |

全部 14 条：**红 → 还原 → 绿**（`inject.py` 的 `[red-run]/[green-run]` 逐条 exit 码见日志；注入跑完后
`md5sum src/prog/main.F90` == 注入前的 `f780a69b…`）。

**三条最初"红不了"的注入（已修测试，见 §4.2）**：

| 注入 | 最初现象 | 原因 | 修法 |
|---|---|---|---|
| inj5 `anyhess` 置假 | 绿 | 我的突变写成 `A .or. B .or. C .and. D`（Fortran 优先级 ⇒ `A .or. B .or. (C .and. D)`）⇒ 对 `--ohess` **没有**置假 —— **突变语义不等价**（M4 报告 34 §1 的教训） | 加括号后红 |
| inj7 关掉周期守卫 | 绿 | 断言只查 `"--method ancopt" in output`，而同一运行的 `[NOTICE]` 行**也含**该子串 ⇒ 断言被 `[NOTICE]` 满足 | 改为断言**守卫自己的句子**（`runs the landscape suite, which does not support periodic boundary conditions: use --opt --method ancopt`） |

> `[订正 R45-F8]`（`45-stage3a-fix.md` §4.6）上表 inj7 的**机理句**不准确：实测
> **守卫运行时 `[NOTICE]` 并不打印**（守卫先于 `[NOTICE]` 触发，守卫运行的 `[NOTICE]`
> 计数 = 0）。子串污染只发生在"守卫被禁用、运行放行到 `[NOTICE]`"的路径上。
> **修法正确，机理已订正。** 原文保留。
| inj11 `--ljson` 旧列表 | 绿 | 旧列表只让 `--ljson` 多打一条 warning，**文档照样写**（写文档的是任务的 `lset%ljson`）⇒ 只断言"写了 json"无法证伪 | 增补断言：`--opt --ljson` **不得**出现 `writes nothing without a landscape run type`（并在 `optnative` 里反向断言原生出口**必须**出现该 warning） |

> 第 2/3/7/11 条同时说明：**"通过"的断言必须钉在能区分两条路径的 token 上**；本项目的 `[NOTICE]` 行会把
> `--method ancopt` 带进任何 `--opt` 运行的 stdout，任何只用该子串的守卫断言都是假绿。

---

## 4. 被证伪的前提 / 已知限制

### 4.1 被实测证伪的前提（逐条）

| # | 前提（出处） | 实测 | 处置 |
|---|---|---|---|
| F1 | 设计 §3.8(c) R23 / §14.7 M-2："C7 爆炸半径**实测** = 0（`grep -rn '\$opt' test/unit/` = 0 命中）" | 真实命中 **10 处**（`[订正 R45-F6]`：该数字已被 3a 自身的测试改动刷新为 **20 处**，见 `45-stage3a-fix.md` §4.3；"设计原主张 = 0 为假"这一结论不变）；且真正的通道是**环境**：`XTBPATH=${PROJECT_SOURCE_DIR}` → 仓库根**被 git 跟踪的 `.xtbrc`**（`ef197a9`，`$opt` 在第 12 行）→ `$opt`。实测 **143/216** 个注册测试带 `XTBPATH`（`ctest --show-only=json-v1` 的 `ENVIRONMENT` 属性统计）。按原设计实现 ⇒ 这 143 个测试**全部硬失败**（已实测：`--lopt` + `XTBPATH=<repo>` exit 1） | 裁定 (A)（按来源，`.xtbrc` 那次不置位）⇒ 0 个测试受影响；订正写入设计 §18.2 + R44 行 |
| F2 | 设计 §3.11.2："`set%optset%xcontrol_supplied`，`setparam.f90:262-270` 加一字段" | `setparam.f90:262-270` 是 `TSet` 里 `optset` **组件**的声明，**加不了字段**；字段属于 `ancopt_setvar`（`src/type/setvar.f90`）＝**核心层**，本阶段硬约束禁止改动 | 裁定 (B)：字段放 `TSet`（`setparam.f90:533`）⇒ **`set%xcontrol_supplied`**；先例 `set%randseed_set`；订正写入设计 §18.1 |
| F3 | 设计 §3.8(b) 的基线句："`--lopt` + 周期 → 报 `landscape_driver.f90:74` 的通用文案" | 与同表**触发条件**矛盾：守卫在套件分派之前，`--lopt` 也命中 `landscape_is_suite_run` ⇒ 拿到**守卫**文案；driver 拒绝对 `--lopt` **不可达** | 按任务书（三守卫统一 `landscape_is_suite_run`）实施；driver 拒绝保留作双保险（保护直接调 `run_landscape` 的单元测试/API 层）；订正写入 §18.5 |
| F4 | 设计 §3.4 建议的 `[NOTICE]` 文案 `(lbfgs)` | R39 已移除 ⇒ `--opt --method bfgs` 合法，写死 "(lbfgs)" 会**错** | 文案不点名算法（§18.4）；`xtb/landscape-opt-alias-once` 与 `check_method_native` 的 `stage3-opt-suite-method` 断言分别钉住 `landscape: lbfgs` 与 `landscape: bfgs` |
| F5 | 设计 §3.11："`--ohess --ljson` 写 `landscape_opt.json`（opt 阶段）" | 实测**还**写 `landscape_vib.json`（两条链都拿到 `--ljson`） | 有意行为，登记为新增文件（BC-3 只要求集合不缩小）；§18.6 |
| F6 | 设计 §3.11.1 对复核的机制订正："半修（`anyhess` 真但不填 `fres`）⇒ 打印 `TOTAL ENERGY 0.000000000000`" | **成立**（inj4 实测该行；但要注意 `anyhess` **置假**是另一种症状：`TOTAL ENTHALPY` 行**消失**，inj5 实测） | 两种症状都进测试（inj4/inj5） |
| F7 | 任务书/设计未提：`landscape_vib_analysis` 的 `vib` 是 `intent(out)` | `intent(out)` 会把**整个派生类型**重置为默认初值 ⇒ 我在 `landscape_vib_hessian` 之后写 `vib%energy = energy` **被抹掉**，`fres%etot` 变 0（实测 `TOTAL ENERGY 0.000000000000`） | `vib%energy` 改到两次 `intent(out)` 调用**之后**（`tasks/vib.f90:272`）；见 §4.3 |

### 4.2 测试侧的两个假绿（由注入发现，已修）

见 §3 末表：`[NOTICE]` 子串污染守卫断言（inj7）、`--ljson` 文档由任务标志而非守卫判定（inj11）。
另外 `check_scanblock` 的 `--opt` 段同样只用 `--method ancopt` 子串 → 一并改为守卫句。

### 4.3 已知限制（登记，不在本阶段修）

| # | 限制 | 证据/说明 |
|---|---|---|
| L1 | **rc 通道里套件不消费的块是一整类**：`$opt`/`$md`/`$siman`/`$hess`/`$modef`/`$cube`/`$symmetry`。当前取"静默 + 登记"（裁定 (A)），**待重新评估** | 实测：`$scc temp=5000` → `landscape engine: etemp 5000.000 K`；`$thermo temp=500.0` → H(T) 变化 ⇒ 这两类**被消费**；`$fix` 在 rc 里**原生路径也不消费**（`read_userdata` 读被选中的输入文件），而输入文件里的 `$fix` 套件正确尊重（O 停在 (0,0,0)）；`grep` 上述 `set%*set` 在 `src/landscape/` = 1（注释）。完整表见设计 §18.3 |
| L2 | `--ohess --ljson` 多写一个 `landscape_vib.json` | §4.1 F5 |
| L3 | 原生 `xtbopt.xyz` 二次写、计时标签的抑制**只覆盖套件 run type**；`--opt --method ancopt` 保持原生两行提示与 `ANC optimizer` 标签（**有意**，与 HEAD 同形） | BC-4 `opt_native`/`ohess_native` 逐位相同 |
| L4 | stdout 里 **C 对称性库（`printf`）与 Fortran unit 6 的缓冲**会造成 `-----` 分隔线与对称性行的**相对顺序**在两个构建间不同（内容相同、顺序不同；每构建内部稳定） | 实测：`GFORTRAN_UNBUFFERED_ALL=1` 后两构建 stdout 完全一致 ⇒ 纯缓冲假象，不是行为变更。BC-4 的 stdout 对比因此在**无缓冲**下进行 |
| L5 | `--md` 的随机种子**无法用 CLI 固定**（`--seed` 不是合法旗标，实测 `Unknown option '--seed' provided`）⇒ 只能经 legacy `$set seed <n>` | BC-4 的 md 用例改用 `--input <$set seed 12345>`，此后 `mdrestart` 与 `xtb.trj` 逐位相同 |
| L6 | 本阶段**不做**（属 3b）：4 个遗留文件（`.xtboptok`/`xtbopt.log`/`xtblast.xyz`/`compliance.dat`）、`--cycles` 映射、档位四轴（`e_tol`/`acc`/`max_steps` 仍固定 5e-6/1.0/256）、`--opt banana` 静默、`--ljson` 文案打磨、`man/xtb.1.adoc` 与 `xhelp.f90` 的自指引导全文 | 任务书"本阶段不做"清单 |

### 4.4 过程教训（本项目第 N 次：静态结论必须实测）

1. **注入的语义等价性**：inj5 的突变因运算符优先级**没有实现它声称的语义**，测试因此保持绿 —— 与 M4 报告 34 §1 同一类错误。
   教训：突变后先问"它真的改了我以为的那个值吗"，再解释红/绿。
2. **apply/restore 循环必须配一次源一致性核对**：本轮的 14 条注入循环跑完后，我发现
   `main.F90:1045` 的 `--ljson` 判定**被还原成了旧式 runtyp 列表**（其余改动都在）。
   触发方式是"逐条 `grep` 期望模式 + 计数"，不是构建（构建照样成功）。
   现在的流程：注入前存 `md5` 基准，注入后 `diff` 基准并断言一致（`inject.py` 内置 `sha256` 断言 + 跑完后的外部 `md5sum` 比对）。
3. **`[NOTICE]` 会污染任何 `--opt` 运行的 stdout 子串断言**（§4.2）。

---

## 5. 验收数字

### 5.1 测试计数（注册前后）

| 项 | 值 |
|---|---|
| `ctest -R landscape`（注册前，父会话独立复核） | **127 / 127** |
| `ctest -R landscape`（本阶段注册后） | **136 / 136**（+9） |
| 回归子集 `-R 'Singlepoint\|GFN\|model-hessian\|optimizer\|Argparser\|CAPI'` | **12 / 12** |
| `--help` 双向一致性（集合 S 差集） | **0**（dialect A: S=0 差；dialect B: `S(main)=135, S(help)=135, difference=0`；`PASS: set S is documented by \`--help\` in both dialects`） |
| 重名（CMake / meson） | `grep -oE 'add_test\("[^"]+"' ... \| sort \| uniq -d` = **空**；meson 同法 = **空** |
| `grep -c "would have no effect" src/prog/main.F90`（R39 清零） | **0** |
| 核心层改动 | `git diff --name-only \| grep -cE '^src/(type\|xtb\|mctc\|param\|io\|disp\|coulomb)/'` = **0** |

### 5.2 BC-4：未改派 run type 的输出文件逐位不变

参考构建 = **HEAD `2b49ef8` 的独立构建** `/tmp/xtb-head/build/xtb`（`git archive 2b49ef8 | tar -x` 后 -O2 构建；
因为该树无 `.git`，其版本串是 `unknown-commit` ⇒ 对比前先剥掉 `(<hash>|unknown-commit)`，这正是任务书点名的已知非确定性）。
脚本 `/tmp/xtb-3a/bc4b.sh`，原始输出 `/tmp/xtb-3a/bc4-final.txt`。

```
BC4 sp:            ref=0 new=0 files=3  -> BYTE IDENTICAL (after stripping the commit hash) (stdout identical)
BC4 hess:          ref=0 new=0 files=7  -> BYTE IDENTICAL (after stripping the commit hash) (stdout identical)
BC4 bhess:         ref=0 new=0 files=10 -> BYTE IDENTICAL (after stripping the commit hash) (stdout identical)
BC4 lopt:          ref=0 new=0 files=5  -> BYTE IDENTICAL (after stripping the commit hash) (stdout identical)
BC4 lscan:         ref=0 new=0 files=4  -> BYTE IDENTICAL (after stripping the commit hash) (stdout identical)
BC4 lts:           ref=1 new=1 files=2  -> BYTE IDENTICAL (after stripping the commit hash) (stdout identical)
BC4 lvib:          ref=0 new=0 files=7  -> BYTE IDENTICAL (after stripping the commit hash) (stdout identical)
BC4 lts_hcn:       ref=0 new=0 files=5  -> BYTE IDENTICAL (after stripping the commit hash) (stdout identical)
BC4 md:            ref=0 new=0 files=54 -> BYTE IDENTICAL (after stripping the commit hash) (stdout identical)
BC4 opt_native:    ref=0 new=0 files=5  -> BYTE IDENTICAL (after stripping the commit hash) (stdout identical)
BC4 ohess_native:  ref=0 new=0 files=9  -> BYTE IDENTICAL (after stripping the commit hash) (stdout identical)
```

- 覆盖：`--sp` / `--hess` / `--bhess` / `--lopt` / `--lscan` / `--lts`（水与 HCN→HNC）/ `--lvib` / `--md` /
  原生出口 `--opt --method ancopt` 与 `--ohess --method ancopt`。
- stdout 对比在 `GFORTRAN_UNBUFFERED_ALL=1` 下进行（§4.3 L4），并归一化：版本串、日期、随机种子、计时行、
  `program call`、`(step)/(real)` 功率、回溯地址。归一化后 **stdout 也逐行相同**。

> `[订正 R45-F7]`（`45-stage3a-fix.md` §4.5）上面"stdout 也逐行相同"**不是可复现的硬门槛**：
> 归一化器只覆盖**带百分号**的计时行，漏掉了无百分号的
> `SCC setup/iterations ... 0 min, X sec`；同一二进制连跑两次该行的秒数与百分比都会变。
> **正确表述（已登记进设计 §19）**：BC-4 = **输出文件逐位相同** + stdout 的差异**只有**
> 已登记的非确定性（版本串 `(<hash>|unknown-commit)`、日期、随机种子、`program call`、
> 回溯地址、**无百分号的计时行**）。文件级结论不受影响。原文保留。
- `--md` 用 `--input <$set seed 12345>` 固定种子（§4.3 L5）。

### 5.3 `--lopt` 数值不变（显式证明）

```
$ cmp /tmp/xtb-3a/bc4b/lopt/{ref,new}/xtbopt.xyz   -> 逐位相同
  ref == new:  3 / energy: -5.070544447778 gnorm: 0.000007606232
               O  0.01012001145297  0.00000000000000  0.00763622827478
               H -0.01302766304505 -0.00000000000000  0.96656991970604
               H  0.93290765159208  0.00000000000000 -0.25420614798082
$ grep -h "TOTAL ENERGY" .../lopt/{ref,new}/stdout.txt
  | TOTAL ENERGY               -5.070544447778 Eh   |   (两构建相同)
```

即本阶段**没有**动 `e_tol`/`max_steps`/`acc`（§4.3 L6），`--lopt` 的末能量、末几何与末梯度逐位不变。

### 5.4 新增 9 条测试的真实输出

见 §2.3（`ctest` 的通过列表 + 逐条 check 自己的 `print` 输出）。

---

## 6. 设计文档订正（已落）

`docs/_simplify-recon/11-cli-redesign.md`：

1. **修订记录新增 `R44` 行**（阶段 3a 实施订正：字段路径 / C7 爆炸半径 / rc 通道裁定 (A) + 待重新评估 / `[NOTICE]` 文案 / PBC 基线矛盾）。
2. **§3.8(c) 的"爆炸半径实测 = 0"行加 `[订正 R44]` 指针**（原文保留），给出真实命中 10 处与 143/216 的环境通道。
3. **§3.11 读点表 #3 加 `[订正 R44]` 指针**：字段实际是 `set%xcontrol_supplied`。
4. **新增 `## 18. 【R44 新增】阶段 3a 实施订正`**：§18.1 字段路径（含设计自相矛盾的两条依据 + 核心层 0 改动可核项）、
   §18.2 爆炸半径（含测量方法 `ctest --show-only=json-v1`）、§18.3 rc 通道裁定 (A)（判据按来源 + 4 条理由 + 待重新评估 +
   "套件消费哪些 rc 块"实测表）、§18.4 `[NOTICE]` 文案、§18.5 PBC 基线矛盾、§18.6 `--ohess --ljson` 两文档。

---

## 7. 建议的下一步

1. **独立复核**（fresh-context reviewer）：本报告 §3/§4/§5 的证据链、§4.2 的两个假绿修法、§18 的设计订正。
2. **阶段 3b**（任务书已列）：4 个遗留文件 + `--namespace` 交互、`--cycles` 映射、档位四轴（`e_tol`/`acc`/`max_steps`）
   与再基线清单（M2/M3/M4/M6/M7 的已验收数字）、C1-C4、`--ljson` 文案、`man/xtb.1.adoc` 与 `xhelp.f90` 的自指引导全文。
3. **rc 通道的重新评估**（§4.3 L1）：等有真实用户后决定是否把"套件不消费的 rc 块"整类改为响亮报错；
   若做，建议**整类一起做**（否则"单挑 `$opt`"的武断会重演）。
4. `xtb/landscape-ohess-suite-once` 目前只断言 `landscape engine: Hessians           1` 这一行（§2.1）；
   若后续要让"恰好一次 Hessian"更强，可在 `--ohess --ljson` 上比对 `landscape_vib.json` 的 `counters`。
