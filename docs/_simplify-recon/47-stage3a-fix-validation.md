# 47 — 阶段 3a 修复轮：独立验证

> 角色：**独立验证 worker**（不信任 45 报告；自己跑）。
> 对象：仓库 `/home/owenchan/work_path/coding/fortran/xtb`，HEAD = `2b49ef8` + 未提交 3a + 修复轮工作树。
> 构建：`/tmp/xtb-3af-val/build`（-O2，`WITH_TBLITE=OFF WITH_CPCMX=OFF WITH_TESTS=ON`，全新配置）。
> 对照：`/tmp/xtb-3af/build`（实施者修复轮）、`/tmp/xtb-3a/build`（修复轮前）。
> 全部 `OMP_NUM_THREADS=1`；未跑全量 ctest；未 `git commit`；每命令 `timeout`。

## 0. 结论

**通过，可以提交。** 5 项范围（T1..T5）全部经独立复现为真；
3 条独立注入证明新测试**可被证伪**；构建 0 error、`ctest -R landscape` **138/138**、
回归子集 **12/12**、重名检查空、集合 S PASS、核心层 0 改动、工作树已还原。

**但**：T5.1（`--ohess` 失败后仍跑 vib）的**结论依据被实测证伪**——套件侧并非"与原生一致、
只差 exit code"，而是 vib 链**带着未清除的 env 错误启动、当场中止、不写任何频率文件**并抛出一条
误导性的级联错误（详见 §6 F-1）。这条**不在本轮 5 项修复内**（T5.1 判定为 No change），
但 T3 的 `--cycles <5` 让该路径**变成一行命令可达**，属新暴露的既有缺陷，建议 3b 处理。

---

## 1. 构建 / 计数 / 注册

| 项 | 命令 | 结果 |
|---|---|---|
| 构建 | `cmake -S . -B /tmp/xtb-3af-val/build …` + `cmake --build -j` | **0 error**（日志里 2 处 "error" 是 `error.f90` 文件名） |
| 计数 | `ctest -N -R landscape` | **Total Tests: 138**（符合预期） |
| 套件测试 | `ctest -R landscape` | **100% tests passed, 0 failed out of 138**（42.7 s） |
| 回归子集 | `ctest -R 'Singlepoint\|GFN\|model-hessian\|optimizer\|Argparser\|CAPI'` | **12/12** |
| 重名 | `grep -oE 'add_test\("[^"]+"' \| sort \| uniq -d` | **空** |
| 重名（meson） | `grep -oE "^test\('[^']+'" \| sort \| uniq -d` | **空** |
| 集合 S | `landscape_help_check.py src/prog/main.F90 src/xhelp.f90` | **PASS**（dialect A/B 差集 0） |
| 核心层 | `git diff --name-only \| grep -cE '^src/(type\|xtb\|mctc\|param\|io\|disp\|coulomb)/'` | **0** |

新增 2 条测试（`xtb/landscape-opt-level-bridge`、`xtb/landscape-cycles-map`）已注册并在 138 内，
修复轮构建与全新构建两侧均绿。

---

## 2. T1 计时标签（事实 A）— 复现成立

```
套件:  xtb landscape_h2o.xyz --gfn 2 --ohess --norestart        exit=0
  'analytical hessian' count = 0 ; 'numerical hessian' count = 0
  'landscape optimizer' count = 1 ; 'ANC optimizer' count = 0
  计时表标签（穷举）= { total, SCF, landscape optimizer }   ← slot 5 消失
原生:  xtb landscape_h2o.xyz --gfn 2 --ohess --method ancopt     exit=0
  'analytical hessian' count = 1 ; 'ANC optimizer' count = 1      ← 反向仍保留
```

**穷尽核对（自跑，未照抄）**：`grep -n "prtiming\|start_timing" src/prog/main.F90` 全表逐个判据
过了一遍。slot 5 是唯一"判据为裸 runtyp、`start_timing` 却落在被谓词抑制的原生块内"的标签；
其余 slot 3/4/6/8/9/10/11 的 timer 与本标签在同一路径启动，或该 runtype 根本不改派。
**报告 §6 的穷尽结论成立**（无第二处必然为 0）。

---

## 3. T2 `--opt <LEVEL>` 档位桥（事实 B）— 逐档复现成立

**逐档做**（不只 tight），`--opt <up>` vs `--lopt --lopt-level <mapped>` 的 `xtbopt.xyz`
**逐位相同**（8 档 + 7 个数字别名）：

| `--opt` | 桥到套件档 | xtbopt.xyz | 回显 banner |
|---|---|---|---|
| crude / sloppy / -3 / -2 | superloose | IDENTICAL | `landscape convergence level: superloose` |
| loose / lax / -1 | loose | IDENTICAL | `…: loose` |
| normal / 0 | normal | IDENTICAL | `…: normal` |
| tight / 1 | tight | IDENTICAL | `…: tight` |
| verytight / extreme / 2 / 3 | vtight | IDENTICAL | `…: vtight` |

```
--opt banana                                     exit=1
  Unknown --opt level 'banana': use crude, sloppy, loose, lax, normal,
  tight, verytight, extreme, superloose or vtight
--opt banana --method ancopt (原生)               exit=0   ← 全局 optlevel2int 未被改
   0 行 "landscape convergence level"、0 行 "… now runs the landscape suite"
--opt tight --lopt-level loose                   exit=1
  run type conflict: --opt already selected the 'opt' run type,
  --lopt-level would select 'lopt'; …
```

**自设计用例**：数字别名 `-3..3` 全部走通（父会话未测）；原生 `--opt 0 --method ancopt --cycles 1`
无 banner、无 redeploy 通告，`--cycles` 不进入套件桥（见 §4）。

---

## 4. T3 `--cycles` 步数预算桥（事实 C）— 用"会咬人的预算"复现成立

**lopt**（水默认 5 步，用 `--cycles 2` 才 binding）：

```
默认                 n_steps=5  converged=true
--lopt --cycles 2    n_steps=2  converged=false  "maximum number of steps reached"
--lopt --lopt-max-steps 2  n_steps=2        landscape_opt.json 与上一行【逐位同】
--opt  --cycles 2    n_steps=2  （3a 新派发路径同样生效）
```

**5 个 runtype 各一次**（自跑，逐条比较文件）：

| runtype | `--cycles 1/2` | 任务专有旗标 | 比较 |
|---|---|---|---|
| lopt | n_steps=2 | `--lopt-max-steps 2` | `landscape_opt.json` **逐位同** |
| lscan | xtbscan.log 同 | `--lscan-max-steps 1` | `xtbscan.log` **逐位同** |
| lts | `landscape_ts.json` n_steps=1（默认 4，**binding**） | `--lts-max-steps 1` | `landscape_ts.json` **逐位同** |
| lirc | exit=0 | `--lirc-max-steps 1` | `irc_path.xyz` **逐位同** |
| lvib | **error** | — | `--cycles has no meaning for --lvib: the frequency task has no step budget` |

```
--lopt --cycles 1 --lscan-max-steps 2        exit=1  "… --cycles 1 conflicts with --lscan-max-steps 2: give only one step budget"
--lopt --cycles 2 --lopt-max-steps 3         exit=1  "… --cycles 2 conflicts with --lopt-max-steps 3: …"
--lts  --cycles 1 --lts-max-steps 2          exit=1  "… conflicts with --lts-max-steps …"
原生 --opt 0 --method ancopt --cycles 1       exit=0，无 visibility 变化（仍走 maxoptcycle）
```

> **任务簿/报告 §4.4 的"`--cycles 8` 不 binding"结论成立**：水默认 5 步，8>5 无变化。
> 本验证统一改用 2/1（< 默认），逐项均可观测。

---

## 5. 独立注入（3 条，均在我自己的备份副本上，改后已 `sha256sum -c` 还原）

| # | 注入 | 期望 | 实测（真输出） |
|---|---|---|---|
| ① T1 | `landscape_native_hessian_path(...)` → 裸 `runtyp ∈ {hess,ohess,bhess}` | 套件 `--ohess` 标签**重现**且测试红 | `FAIL: --ohess printed 'analytical hessian' 1 times instead of 0`，输出里确实出现 `analytical hessian: … 0.000 sec / ratio c/w: NaN` |
| ② T2 | 映射表 `case('crude','sloppy',…) level='superloose'` → `'normal'` | `optlevel` 测试红 | `FAIL: --opt crude and --opt tight produced the same run (5 steps)` |
| ③ T3 | `if (cycles_given) then` → `if (.false. .and. cycles_given) then` | `cycles` 测试红 | `FAIL: --lopt --cycles 4 reports 5 steps, --lopt --lopt-max-steps 4 4` |

三条注入改回后增量重建、三条 python mode **全部复绿**（`ohesssuite`/`optlevel`/`cycles` 返回 0，
2 条新 ctest 复绿）。→ **新测试确实可被证伪**。

---

## 6. 证伪清单（45 报告说错 / 说漏）

### F-1（重要，实测证伪）报告 §5.1 的 T5.1 判定依据不成立

报告称：套件侧"没有在第一段与 vib 链之间插 `env%check`，所以套件**也**跑 vib —— 与原生一致；
**唯一差别是 exit code**"。**实测证伪**（`--ohess --cycles 4`，1->4 全部复现）：

```
套件 --ohess --cycles 4   exit=1  写 hessian? no  写 vibspectrum? no
  landscape: harmonic frequencies                     ← 进了 vib 链
  landscape task terminated: frequency analysis failed
  -6- landscape_vib_hessian: … the single point of the reference geometry failed
  -5- landscape_engine_energy_gradient: SCC did not converge at the current geometry
  -3- scf: Setup of Coulomb evaluator failed
  -2- type_latticepoint_update: Could not generate lattice points
  -1- landscape_optimize: landscape minimisation did not converge: maximum number of steps reached
原生 --ohess --method ancopt --cycles 1   exit=0  写 hessian/vibspectrum: yes
```

即：**差别不止 exit code**——套件在优化失败后进入 vib 链却**立刻中止、不产任何频率文件**。
机理（已定位到 `src/type/latticepoint.f90:196` 的 `call env%check(exitRun)`）：优化失败留下的
**未清除 env 错误**在 vib 的第一次 `env%check` 处被判为致命，抛出 "Could not generate lattice
points" 这条**误导性级联错误**。对照实验：把该未收敛几何单独喂给 `--sp` → exit 0、`TOTAL ENERGY`
正常 → 失败**与几何无关，是残留错误标志**。

**影响**：T5.1 判定为 "No change" 只成立在"本来只想对齐 exit 语义"的口径；若目标是"与原生一样
产出频率"，则该判定错误。**新暴露点**：T3 的 `--cycles <5` 使这条路径一行命令可达
（此前需要挑难收敛几何或极严档位），建议 3b 在 vib 链前 `env%clear`/`checkpoint`（与原生对齐）。

### F-2（低）报告 §4.3 的"冲突在**桥之前** exit 1"机理不准

实测 `--opt tight --lopt-level loose`：`select_runtyp` 只**登记**冲突错误并不中止执行，
解析尾的 T2 桥随后仍执行并打印 `[NOTICE] landscape convergence level: tight`，最终才由
`env%check` 使 exit=1。**结果（exit≠0、点名两旗标）正确**，但"exit before the bridge"的措辞不实；
桥在冲突运行上确实跑过一遍（对 abort 的运行无观测影响）。

### F-3（低）报告 §3.3 "测试隔离观测"的 `charges` 污染：本次**未复现**

本次全新构建 / 固定 cwd 串行跑，`ctest -R landscape` 138/138、回归 12/12 均未出现
`xtb/GFN2-FF` 因工作目录 `charges` 变红。该观测**依赖运行方式**，不是稳定回归，建议不要写进
"已知缺陷"当作常驻结论（登记为偶发即可）。

### F-4（信息）报告 §2 T1 的"改前 453 行"引用的是 `/tmp/xtb-3a` 的行号，不是源码行号
与源码 `main.F90:5267` 对不上，读者无法据此定位；不影响结论。

### F-5（信息）`--cycles 1` 与 `--lopt-max-steps 1` 在 `--ohess` 上**不可比**
`--ohess --lopt-max-steps N` 被 `select_runtyp` 当作 runtype 冲突直接拒绝（`--lopt-max-steps`
选择 `lopt`），所以 `--ohess` 只能靠 `--cycles` 设预算。报告 §3 表格里把两者并排写，易误导。

---

## 7. 未做项 / 残留风险

- **未做**：T4 的 F-4..F-8 逐条原文核对（只确认了 `42`/`43` 存在 `订正 R45` 指针、设计 §19 四小节
  落盘）；`--help` 只抽验了 `--opt`/`--ohess` 两条（其余关于 `--method`/`--lopt` 的两条未逐字读）。
- **未做**：meson/ninja 本机未装，meson 两条新条目无法执行（与报告一致，不可本地验证）。
- **残留 R-1**：F-1 的 vib 链残留错误（既有缺陷，被 T3 放大可达性）。
- **残留 R-2**：T2/T3 桥落在解析尾而非 `xtbMain` 分派块（行为不变，报告已自陈）。
- **残留 R-3**：`xtb/GFN2-FF` 与 cwd 裸名 `charges` 的耦合（本次未复现，见 F-3）。

---

## 8. 提交建议

**可以提交。** 5 项修复均真实、可证伪、已复现；构建/测试/注册/核心层约束全部满足。
唯一需带进 3b 的是 **F-1**（`--ohess` 失败路径 vib 链的残留错误标志 + 误导性级联错误），
它不在本轮范围、但被本轮 T3 显著可达化，应在提交信息或 3b 计划中显式登记。
