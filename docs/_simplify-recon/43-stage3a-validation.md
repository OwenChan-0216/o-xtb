# 43 — 阶段 3a 独立验证报告（`--opt` / `--ohess` 改派 + 三条守卫）

> 角色：fresh-context 独立验证者。**不读实施报告当结论**，全部结论来自本机实测。
> 被验证对象：仓库 `/home/owenchan/work_path/coding/fortran/xtb`，HEAD = **2b49ef8**，
> 工作树 = 未提交的阶段 3a。
> 验证构建：`/tmp/xtb-3a-val/build`（-O2，`WITH_TBLITE=OFF WITH_CPCMX=OFF WITH_TESTS=ON`）。
> HEAD 对照二进制：`/tmp/xtb-land/build/xtb`（版本串 `unknown-commit`）。
> 注入副本：`/tmp/xtb-3a-val/repo` + `/tmp/xtb-3a-val/repo-build`（**未接触仓库 `src/`、`test/`**）。
> 全部 xtb/ctest 调用 `OMP_NUM_THREADS=1`；未跑全量 ctest。

---

## 0. 结论

**通过，可以提交。**

- 构建 0 error；`ctest -R landscape` = **136/136**；回归子集 `-R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'` = **12/12**；
  CMake/meson 重名检查为空；集合 S（`landscape_help_check.py`）双向差集 **0**；核心层改动 **0**。
- 四个原生出口 token 判别全部正确、均无 `landscape:` 行；`--ohess` 两侧 token 与文件集正确；`fres` 桥与 `--lvib` 末几何 **逐位一致**。
- 三条守卫（`$scan` / 周期 / `$opt`）exit 1 且打印**守卫整句**，三条原生基线 exit 0；**H-2（周期 + `--opt --method ancopt`）exit 0** 成立。
- BC-4：9 个未改派 runtype（含 `--lirc`）的**文件逐位相同**；`--lopt` 数值逐位不变；唯一有意例外（`--lopt --input <$opt>` exit 0→1）确认。
- 独立注入 6 条：5 条按期望红、1 条附加（错误非零能量）也红；还原后 `sha256` 一致、复绿。
- 发现的都是 LOW/INFO（见 §6），**无 CRITICAL / HIGH / MEDIUM 阻断项**。

唯一无法在本机判定的：meson 条目（`meson`/`ninja` 未安装）——与实施报告自报一致。

---

## 1. 构建与测试计数（逐条真实输出）

### 1.1 构建

```
$ cmake -S <repo> -B /tmp/xtb-3a-val/build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF \
        -DWITH_TESTS=ON -DCMAKE_BUILD_TYPE=Release -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"
...
[100%] Linking Fortran executable xtb
[100%] Built target xtb-tester
```

### 1.2 landscape 套件

```
$ ctest -N -R landscape | tail -1
Total Tests: 136
$ ctest -R landscape | tail -3
100% tests passed, 0 tests failed out of 136
Total Test time (real) =  45.48 sec
```

### 1.3 回归子集

```
$ ctest -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
100% tests passed, 0 tests failed out of 12
```

### 1.4 重名 / 核心层 / R39

```
$ grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d      -> 空
$ grep -oE "^test\('[^']+'" test/unit/meson.build | sort | uniq -d            -> 空
$ git diff --name-only | grep -cE '^src/(type|xtb|mctc|param|io|disp|coulomb)/' -> 0
$ grep -c "would have no effect" src/prog/main.F90                            -> 0
```

### 1.5 集合 S（自己跑脚本）

```
$ python3 test/unit/landscape_help_check.py src/prog/main.F90 src/xhelp.f90
dialect A: S(main) = 135, S(help) = 135, difference = 0
dialect B: S(main) = 135, S(help) = 135, difference = 0
PASS: set S is documented by `--help` in both dialects   (exit=0)
```

---

## 2. 四个原生出口（设计 token 判别）

逐条实跑，断言 token 出现、`landscape:` 行计数为 0、不写 json。

| `--method` | 设计 token | token 命中 | `landscape:` 行 | exit |
|---|---|---|---|---|
| `ancopt`   | `ANC micro-cycles` (1) | ✓ | 0 | 0 |
| `lancopt`  | `L-ANC optimizer` (1)  | ✓ | 0 | 0 |
| `fire`     | `initial time step` (1)| ✓ | 0 | 0 |
| `pbc_lbfgs`| `current lattice:`     | ✓ | 0 | 0 |

补充：`--opt --method pbc_lbfgs` 在**非周期**水分子上同样 exit 0 并打印 `current lattice:`；
该 token 对其余三个出口为 **0 次**（实测），因此是可判别的。

```
$ python3 landscape_cli_check.py optnative <exe> landscape_h2o.xyz <dir>
opt native exit: --method ancopt     -> ANC micro-cycles
opt native exit: --method lancopt    -> L-ANC optimizer
opt native exit: --method fire       -> initial time step
opt native exit: --method pbc_lbfgs  -> current lattice:      (exit=0)
```

---

## 3. `--ohess` 两侧 + `fres` 桥

### 3.1 套件侧

```
$ xtb landscape_h2o.xyz --gfn 2 --ohess --norestart
Numerical Hessian                   0     (行计数)
Frequency Printout                  0
ANC micro-cycles                    0
landscape: lbfgs minimisation       1
landscape: harmonic frequencies     1
landscape engine: Hessians           0   (opt 链)
landscape engine: Hessians           1   (vib 链)
TOTAL ENERGY               -5.070544447778 Eh
TOTAL ENTHALPY             -5.046638762610 Eh
TOTAL FREE ENERGY          -5.068045210878 Eh
写 hessian / vibspectrum / g98.out / xtbopt.xyz / vib_normal_modes   exit=0
```

### 3.2 原生侧

```
$ xtb landscape_h2o.xyz --gfn 2 --ohess --method ancopt --norestart
Numerical Hessian   1
Frequency Printout  1
ANC micro-cycles    1
landscape: lbfgs    0
landscape: harmonic 0        exit=0   写 hessian/vibspectrum/g98.out
```

### 3.3 `fres` 桥（同末几何 `--lvib`）

对 `--ohess` 写出的 `xtbopt.xyz` 再跑 `--lvib`：

```
 total enthalpy H(T):           -5.046638762610 Eh
 total free energy G(T):        -5.068045210878 Eh
```

与 §3.1 的 `TOTAL ENTHALPY` / `TOTAL FREE ENERGY` **逐位相同**（差 = 0，远优于 1e-6 阈值）。
`check_ohess_fres_bridge` 通过。

> 注：stale 数字核对。父会话给出的 `-5.070544447744 / -5.046638712638 / -5.068045136132`
> **本机不可复现**；实现报告 §2.3 与本机、以及实施者自己的 `/tmp/xtb-3a/build/xtb` 三方一致给出
> `-5.070544447778 / -5.046638762610 / -5.068045210878`（同一 fixture，`cmp` 逐位相同）。
> 见 §6 证伪项 F-4。

---

## 4. 三条守卫 + 原生基线（完整守卫句）

每条分别在**原始命令**下复核 exit 码与**守卫整句**（不是裸子串）。

| 用例 | 守卫运行 | 完整守卫句（实测，节选前缀） | 原生基线 | 基线 token |
|---|---|---|---|---|
| `$scan`  | exit **1** | `-2- the run type does not execute this xcontrol block` / `-1- prog_main: --opt does not execute the xcontrol $scan block: use --opt --method ancopt ...` | `--opt --method ancopt` exit **0**，`RELAXED SCAN`=1，写 `xtbscan.log` | `RELAXED SCAN` |
| 周期 | exit **1** | `-1- prog_main: --opt runs the landscape suite, which does not support periodic boundary conditions: use --opt --method ancopt for the native ANCopt (pbc_lbfgs / GFN-FF periodic) optimisation` | `--gfnff --opt --method ancopt` exit **0** | `current lattice:` (125×)  |
| `$opt` | exit **1** | `-1- prog_main: the xcontrol $opt block does nothing for --opt: the landscape suite does not read the ANCopt parameters; ...` | `--opt --method ancopt --input $opt` exit **0** | — |
| `$opt`（C7 全量） | `--lopt --input $opt` exit **1** | 同上，旗标为 `--lopt` | — | — |

**H-2 专项**：周期体系 `--opt --method ancopt`（quartz.3d.coord, `--gfnff`）**exit 0**，
`current lattice:` 出现 125 次 —— 守卫不会误伤原生出口。✓

补充：守卫块在 `[NOTICE]` **之前**触发（守卫运行的 `[NOTICE]` 计数 = 0），
且 `--input <显式 .xtbrc>` 仍被守卫（exit 1），而 `.xtbrc` 被自动读取时不守卫（exit 0）——
两者都符合"按来源判据"的裁定 (A)。

---

## 5. BC-4：未改派 runtype 的输出文件逐位不变

脚本 `/tmp/xtb-3a-val/bc4.sh`，原始输出 `/tmp/xtb-3a-val/bc4-out.txt`。
参考 = `/tmp/xtb-land/build/xtb`（HEAD `2b49ef8`，版本串 `unknown-commit`），
新 = `/tmp/xtb-3a-val/build/xtb`。比较前剥离 `(<40hex>|unknown-commit)`（已知非确定性）。
stdout 在 `GFORTRAN_UNBUFFERED_ALL=1` 下比较并归一化版本/日期/种子/计时/`program call`/回溯地址。

```
BC4 sp:            ref=0 new=0 files=3  -> BYTE IDENTICAL (hash stripped) (stdout identical)
BC4 hess:          ref=0 new=0 files=7  -> BYTE IDENTICAL (hash stripped) (stdout identical)
BC4 bhess:         ref=0 new=0 files=10 -> BYTE IDENTICAL (hash stripped) (stdout identical)
BC4 lopt:          ref=0 new=0 files=5  -> BYTE IDENTICAL (hash stripped) (stdout identical)
BC4 lscan:         ref=0 new=0 files=4  -> BYTE IDENTICAL (hash stripped) (stdout identical)
BC4 lts:           ref=1 new=1 files=2  -> BYTE IDENTICAL (hash stripped) (stdout identical)
BC4 lvib:          ref=0 new=0 files=7  -> BYTE IDENTICAL (hash stripped) (stdout identical)
BC4 lirc:          ref=0 new=0 files=7  -> BYTE IDENTICAL (hash stripped) (stdout identical)
BC4 lts_hcn:       ref=0 new=0 files=5  -> BYTE IDENTICAL (hash stripped) (stdout identical)
BC4 md:            ref=0 new=0 files=54 -> BYTE IDENTICAL (hash stripped) (stdout identical)
BC4 opt_native:    ref=0 new=0 files=5  -> BYTE IDENTICAL (hash stripped) (STDOUT DIFFERS: 计时行)
BC4 ohess_native:  ref=0 new=0 files=9  -> BYTE IDENTICAL (hash stripped) (stdout identical)
```

- `--lirc` 的输入是先用 `--lts --lts-method prfo` 收敛出的 `irc0.xtbts.xyz`（同一份喂给两侧）。
- `--md` 用 `--input <$set seed 12345>` 固定种子（`--seed` 非合法旗标）。
- `opt_native` 的 stdout 差异**仅是计时行**（`SCC iter. ... 0 min, 0.001 sec` vs `0.000 sec`）：
  同一二进制连跑两次会得到不同的秒数**与百分比**（实测），bash 归一化器漏掉了无百分号的计时行
  → 见 §6 假绿 F-1。**文件层面 5 个全部逐位相同**。

### 5.1 `--lopt` 数值逐位不变

```
$ cmp ref/xtbopt.xyz new/xtbopt.xyz   -> 仅版本串不同
$ sed -E 's/\(([0-9a-f]{7,40}|unknown-commit)\)/(HASH)/' | diff  -> IDENTICAL
 energy: -5.070544447778 gnorm: 0.000007606232
 O  0.01012001145297  0.00000000000000  0.00763622827478
 H -0.01302766304505 -0.00000000000000  0.96656991970604
 H  0.93290765159208  0.00000000000000 -0.25420614798082
```

### 5.2 唯一有意例外（C7）

```
--lopt --input <含 $opt> :
  HEAD /tmp/xtb-land/build/xtb  -> exit 0，无 "does nothing for" 行（静默）
  new  /tmp/xtb-3a-val/build/xtb -> exit 1，守卫句 "the xcontrol $opt block does nothing for --lopt ..."
```

---

## 6. 独立注入（自建副本 `/tmp/xtb-3a-val/repo`）

流程：`python` 精确替换 → 增量构建（**3.1 s**）→ 直接调用对应 python mode → 还原 →
`sha256sum -c` 断言逐字节还原 → 复绿。基准 `sha256 = 8c174c96…`。

| # | 注入 | 期望 | 实测 |
|---|---|---|---|
| inj1 | `if (anyopt .and. landscape_native_engine /= 0)` → `if (anyopt)` | `optalias` 红 | **红** `FAIL: --opt ran the native ANCopt as well`（exit 1） |
| inj2 | T1 `landscape_native_hessian_path` 的 `p_run_ohess` 分支 → 恒真 | `ohesssuite` 红 | **红** `FAIL: --ohess printed 'Numerical Hessian' 1 times instead of 0` |
| inj3 | `landscape_is_suite_run` 恒真 | `optnative` 红 | **红** `FAIL: --opt --method ancopt announced a redeployment` |
| inj4 | 半修：保持 `anyhess` 真但不填 → `fres%etot = 0.0_wp` | `ohessbridge` 红 | **红** `FAIL: --ohess reports TOTAL ENERGY 0 ...`；裸跑打印 **`TOTAL ENERGY 0.000000000000 Eh` 且 exit 0**（静默错数，证实） |
| inj5 | 守卫条件 → 恒真（守卫过宽，反向） | 三条 `optguard` 基线红 | **红** 三条均 `FAIL: the native exit refused ...`（scan/pbc/xcontrol） |
| inj6 | 错误非零：`fres%etot = 1.0_wp` | `ohessbridge` 红 | **红** `FAIL: --ohess TOTAL ENTHALPY 1.023905685167 differs from --lvib -5.046638762610` |

- inj4 的**静默错数**（exit 0、`normal termination`、`TOTAL ENERGY 0.000000000000`）比崩溃更难发现，
  测试确实把它抓成红 —— 这是本阶段最有价值的守护之一。
- 还原验证：`sha256sum -c` = `src/prog/main.F90: OK`；复跑 `optalias` / `optnative` 均 exit 0 复绿。
- 仓库工作树在整个验证期间 `git status` 与开始时一致（**我未改仓库任何 `src/`、`test/` 文件**）。

---

## 7. 假绿复核（`check_opt_guard` / `check_opt_alias_once` / `check_ohess_fres_bridge`）

### 7.1 实施者自报的两处 —— 核对结论：**确实已修好**

- **守卫裸子串**：`check_opt_guard` 的 pbc 段改为断言
  `runs the landscape suite, which does not support periodic boundary conditions: use --opt --method ancopt`
  （inj5 证实：基线被拒时测试红），scanblock 段断言 `does not execute the xcontrol $scan block: use --opt --method ancopt`，
  xcontrol 段断言 `the xcontrol $opt block does nothing for --opt`。三者均非裸 `--method ancopt`。
  补充事实修正：守卫运行时 `[NOTICE]` **不打印**（守卫在 `[NOTICE]` 之前触发）；子串污染只发生在"守卫被关掉后放行到 `[NOTICE]`"的路径上——结论不变，机理需说清。
- **`--ljson` 文档由任务旗标写**：`check_opt_alias_once` 增补
  `if "writes nothing without a landscape run type" in output: fail`；
  `check_opt_native_exit` 反向断言原生出口**必须**出现该 warning。双向钉住。

### 7.2 我另外找到的（实施报告未列）

- **F-1（LOW，测试基建）**：BC-4 stdout 归一化器只覆盖**带百分号**的计时行
  （`[-0-9.]+ min, *[-0-9.]+ sec \( *[-0-9.]+%\)`），漏掉无百分号的 `SCC setup/iterations/... 0 min, X sec`。
  实测同一二进制连跑两次该行即可不同（秒数与百分比都变），因此 BC-4 的 "stdout identical"
  会**偶发假红**（本次 `opt_native` 即命中一次纯计时差异）。
  **不影响文件级 BC-4 结论**，但该断言不是可复现的硬门槛。
- **F-2（LOW，覆盖深度）**：`check_opt_alias_once` 名为 "once"，但只对
  `landscape: lbfgs minimisation` 用 `in`（子串）而非计数，"恰好一次"实际只靠
  `ANC micro-cycles` 缺失间接保证。可达路径下无缺陷，但若将来默认原生引擎换成不打该行的引擎，
  该测试会失去判别力。已由 `check_ohess_suite_once` 的**计数**断言（其余测试）补足。
- **F-3（INFO，鲁棒性已验证）**：我怀疑 `check_ohess_fres_bridge` 只查 `abs(energy)<1e-8`、
  错误**非零** `fres%etot` 会漏过 —— **实测证伪**：因 `fres%htot` 用独立的
  `lres%vib%enthalpy - lres%vib%energy` 计算，打印的 `TOTAL ENTHALPY = etot + htot`，
  `etot` 一旦偏离真值，H 比较即失败（inj6：`1.0239…` vs `-5.0466…`）。断言链是闭合的。

### 7.3 假绿陷阱的最终判定

`[NOTICE]` 行含 `--method ancopt`、`program call` 行含整个命令行 —— 两处弱断言陷阱**确实已修**；
`--ljson` 文档判定改为双向。另有 F-1 的 BC-4 基建噪声（与本题断言正确性无关）。

---

## 8. 残留风险严重度（独立判断）

| # | 实施报告登记项 | 我的独立判定 | 严重度 |
|---|---|---|---|
| R-1 | `--ohess --ljson` 多写 `landscape_vib.json` | 实测两个文档都语义正确（`task=opt` n_steps=5；`task=vib` n_vib=3），是"两个任务两个文档"，BC-3 只要求集合不缩小 ⇒ **不是问题**，登记即可 | **LOW/无** |
| R-2 | rc 通道对套件不消费的块静默忽略（一整类） | 实测成立：仓库 `.xtbrc`（第 12 行 `$opt`）+ `--lopt` exit 0 无守卫；`--input <显式 .xtbrc>` 仍守卫。裁定 (A) 有意、不阻断；属"一整类"而非单挑 `$opt` | **MEDIUM（设计层面，已登记，留待重新评估）** |
| R-3 | meson 本机不可执行 | 本机同样无 `meson`/`ninja`，条目的正确性**无法独立验证** | **LOW（不可验证）** |
| R-4 | F-1 BC-4 stdout 计时噪声 | 见 §7.2 | **LOW** |

---

## 9. 证伪清单（实施报告 / 任务书说错、说漏之处）

> `[订正 R45]`（`45-stage3a-fix.md`）本节 F-4..F-8 **全部已在修复轮落盘处理**：
> F-4/F-5/F-6/F-8 已在 `42-stage3a-impl.md` 原文旁加 `[订正 R45-Fx]` 指针，F-7 的
> **正确做法**（BC-4 = 文件逐位相同 + stdout 差异只有已登记的非确定性）已写进
> 设计 §19 与 `42` §5.2。本节原文保留。

- **F-4（任务书数字）**：父会话给的 `--ohess` 三能量 `-5.070544447744 / -5.046638712638 / -5.068045136132`
  **不可复现**。实现报告 §2.3、实施者二进制、我的构建三方一致为
  `-5.070544447778 / -5.046638762610 / -5.068045210878`（同 fixture，`cmp` 逐位相同）。属转录/环境差异，不影响验收。
- **F-5（报告行号）**：报告 §3 inj1 写"去掉 `:938` 的原生块抑制"；HEAD 后真实落点是 **`:987`**（报告 §1 表自身也写 `:987`）。§3 的行号是 3a 前的陈旧值。
- **F-6（报告 F1 证据已过时）**：报告 §4.1 F1 用"`grep -rn '\$opt' test/unit/` 真实命中 **10** 处"作证据；
  当前（3a 改完测试后）实测 **20** 处。设计文档"= 0"的原始主张确实为假，但报告引用的数字已被其自身改动刷新。
- **F-7（报告 §5.2 的"stdout 也逐行相同"不稳健）**：`opt_native` 的 stdout 对比在本次实测出现纯计时差异；
  该结论依赖计时，不是可复现硬门槛（见 F-1）。文件级结论不受影响。
- **F-8（报告 §4.2 机理表述）**：报告称"同一运行的 `[NOTICE]` 行也含该子串"；实测**守卫运行时 `[NOTICE]` 不打印**
  （守卫先于 `[NOTICE]`）。子串污染只在"守卫被禁用、运行放行到 `[NOTICE]`"时出现。修法正确，机理描述需修正。
- 未发现实施报告 §1/§3/§4/§18 的其它错误：`xcontrol_supplied` 落点（`setparam.f90:533`，核心层 0 改动）、
  四条纯函数位置、R39 归零、四个原生 token、三条守卫统一读 `landscape_is_suite_run` 均已独立复核为真。

---

## 10. 复现命令（关键条目）

```bash
export OMP_NUM_THREADS=1 XTBPATH=/home/owenchan/work_path/coding/fortran/xtb
REPO=/home/owenchan/work_path/coding/fortran/xtb
BUILD=/tmp/xtb-3a-val/build
cmake -S $REPO -B $BUILD -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"
cmake --build $BUILD -j8
ctest --test-dir $BUILD -R landscape
ctest --test-dir $BUILD -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
python3 $REPO/test/unit/landscape_help_check.py $REPO/src/prog/main.F90 $REPO/src/xhelp.f90
/tmp/xtb-3a-val/bc4.sh                                   # BC-4 13 例
# 注入：/tmp/xtb-3a-val/repo(-build)，基准 sha256 = 8c174c9684b03a76ad28668a10e33f86b938ebbc403c437a54e8ae3f371cb080
```

原始产物：`/tmp/xtb-3a-val/bc4-out.txt`、`/tmp/xtb-3a-val/work/{native,raw3,ohess,json,rc,rc2,tsgen,inj}/`。
