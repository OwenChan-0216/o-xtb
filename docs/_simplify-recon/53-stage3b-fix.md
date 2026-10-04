# 阶段 3b 修复轮报告（HIGH 2 + MEDIUM 1 + 登记）

基线：HEAD `b822c1f` + 未提交的阶段 3b 工作树。构建 `/tmp/xtb-3bf/build`（-O2，全新目录）。
输入：`52-stage3b-review.md`（HIGH-1 / HIGH-2 / P2-1 / P2-2 / P2-3 / LOW-1）。
本轮**只修**谓词 / 初值 / 文案 / 登记 / 测试。**未**动任何算法、收敛判据、核心层。
**未提交 git**（见 §8）。

| T | 内容 | 状态 |
|---|---|---|
| T1 | `main.F90:987` 谓词 → `landscape_is_suite_run`；`murks` 显式初值 | 修好，含注入证据 |
| T2 | `--bhess`/`--omd`/`--metaopt` 文案改回事实 | 修好，含逐行对照表 |
| T3 | `compliance.dat` 条件：**选 (b)**，措辞改成准确 + 登记差异 | 修好 |
| T4 | `--lvib` 新增输出的登记（设计 §1.2 订正 + §10 B 类登记） | 修好 |
| T5 | 设计 §3.9 `.xtboptok`「非空」行订正（+同表的「首行含」） | 修好 |
| T6 | compliance 反向用例 + `--ohess` vib 半断言 + 门槛缺陷记录 | 修好 |

**测试计数**：`ctest -R landscape` → **145/145 pass**（3b 的 143 + 本轮 2 条新）；回归子集 12/12 pass。
核心层改动 **0**；`git diff --cached` 空。

---

## 1. T1（HIGH-1）`anyopt` 谓词 + `murks` 初值

### 1.1 改动

`src/prog/main.F90`：

```fortran
! 原（3a 引入）:
      if (anyopt .and. landscape_native_engine /= 0) then
! 现（:999）:
      if (anyopt .and. .not. landscape_is_suite_run(set%runtyp, landscape_native_engine)) then
```

`src/prog/main.F90:232`：

```fortran
! 原:  logical :: epr, diff, murks
! 现:  带 `!>` 说明的 `logical :: epr, diff, murks = .false.`
```

**用的是既有谓词**（`landscape_is_suite_run`，`main.F90:4757` → `effective_landscape_task`），
没有第二套判据：同一个谓词就是 §3.8 三条守卫（`:525`）、`--ljson`（`:1057`）、`[NOTICE]`（`:1067-1076`）、
原生 `xtbopt.xyz` 二次写（`:1479-1482`）、计时标签、`--cycles` 桥的判据。

**为什么 `/= 0` 是错的**：`anyopt` 覆盖 `--omd`/`--screen`/`--metaopt`（`:324-326`），
而这三个 runtype **从未改派**且 `--method` 对它们**报错**（实测见 §2.2）⇒
`landscape_native_engine` 对它们恒 0 ⇒ 原生优化块**不可达**。对 `--opt`/`--ohess`
两个分支等价：套件（`native_engine == 0`）→ 抑制；原生出口（`≠ 0`）→ 放行。

**其它 `anyopt` 读点**（`grep -n anyopt` 全仓库 = 9 处）：
`:324`（定义）、`:328`/`:333`（CPCM-X / PTB `env%terminate`，**有意保留**：这两个 workaround
对"改派后的 `--opt`"同样不存在，改判据会让它们从响亮拒绝变成静默；任务书也明写保留）、
`:987`（本轮修）、注释 3 处。**没有第四个受同一缺陷影响的读点。**

### 1.2 实测（扭曲水 O–H = 1.300 Å，`--gfn 2 --omd --norestart`）

| 二进制 | exit | `ANC micro-cycles` 出现次数 | `xtbopt.xyz` 的 energy |
|---|---|---|---|
| pre-3a `/tmp/xtb-land/build/xtb` | 0 | 1 | −5.070544363296 |
| 3a `/tmp/xtb-3af/build/xtb` | 0 | **0** | −4.962807380731（= 输入几何） |
| 3b `/tmp/xtb-3b/build/xtb`（修前） | 0 | **0** | −4.962807380731 |
| **本轮 `/tmp/xtb-3bf/build/xtb`** | 0 | **1** | **−5.070544363296** |

末 O–H 0.96 Å（pre-3a 与修后逐位同）vs 1.30 Å（3a/3b）。**HIGH-1 复现并被修复。**

### 1.3 注入（可证伪）

把 `main.F90:999` 还原为 `if (anyopt .and. landscape_native_engine /= 0) then`，增量重建：

```
$ ctest --test-dir /tmp/xtb-3bf/build -R 'landscape-(native-runtypes-unaffected|vib-compliance-skip|file-contract)'
6/6 Test #225: xtb/landscape-native-runtypes-unaffected ...***Failed    0.16 sec
83% tests passed, 1 tests failed out of 6
  (LastTest.log) FAIL: --omd exited 1 instead of the native 0
  FAIL: --omd did not run the native ANCopt (no 'ANC micro-cycles')
```

还原该行、重建 → **6/6 pass**（`xtb/landscape-native-runtypes-unaffected` Passed 1.85 s）。
**改前红 / 改后绿，逐字如上。**

### 1.4 BC-4：与 pre-3a 比较（`norm` 只去版本串/时间/路径/随机种子/计时）

| runtype | 退出码 pre-3a → 3bf | stdout（归一） | `xtbopt.xyz` | `xtbopt.log` |
|---|---|---|---|---|
| `--omd` | 0 → 0 | 同（余计时/seed） | **逐位同** | **逐位同** |
| `--screen` | 1 → 1 | 同（余 backtrace 地址） | 逐位同 | 同 |
| `--metaopt` | 0 → 0 | 同（余 `ratio c/w`） | 逐位同 | 同 |

- `--screen` 的 exit 1 是**上游既有行为**：`screen` 例程要工作目录里的 `screen` 文件，
  没有就报 `read error in screen`（`main.F90:1588` 的 `call screen(...)` 之后）。pre-3a 与修后一致。
- `--omd` 的 **MD 产物**（`xtb.trj`/`mdrestart`/`scoord.*`）**不可逐位比**：MD 的
  `random seed` 是**每进程随机**的（同一 pre-3a 二进制连跑两次：seed 335113443 / 824422036，
  `mdrestart` 不同）。可逐位比的确定性部分是**优化侧**（`xtbopt.xyz`/`xtbopt.log`/stdout）。

---

## 2. T2（HIGH-2）三个 runtype 的文案改回事实

### 2.1 逐行对照表（"这行描述哪个 runtype + 该 runtype 是否改派 + 文案是否一致"）

| 位置 | 描述的对象 | 是否改派 | 现文案 | 一致？ |
|---|---|---|---|---|
| `xhelp.f90:270-276` | `-o, --opt [LEVEL]` | **是**（阶段 3a） | "optimize the geometry with the landscape task suite (stage 3); the legacy ANCopt is reachable as `--opt --method ancopt`" | ✅ |
| `xhelp.f90:277-295` | `--lopt` 及方法表 | 套件 runtype | "…the native engines ancopt(rf)/lancopt/fire/pbc_lbfgs are accepted [with `--opt`/`--ohess`]" | ✅ |
| `xhelp.f90:299-303` | `--lopt` | 套件 runtype | "minimize the geometry with the landscape task suite (src/landscape)" | ✅ |
| `xhelp.f90:779-782` | `--ohess [LEVEL]` | **是**（opt 链 + vib 链） | "minimize … landscape task suite and run its harmonic frequency analysis (the legacy ancopt(3) plus numerical Hessian path is `--ohess --method ancopt`)" | ✅ |
| `xhelp.f90:784-785` | `--bhess [LEVEL]` | **否** | "perform a biased numerical hessian calculation on an **ancopt(3) optimized** geometry" | ✅（本轮改回） |
| `xhelp.f90:813-814` | `--omd` | **否** | "molecular dynamics simulation on **ancopt(3) optimized** geometry, a loose optimization level will be chosen" | ✅（本轮改回） |
| `xhelp.f90:817-818` | `--metaopt [LEVEL]` | **否** | "**call ancopt(3)** to perform a geometry optimization, then try to find other minimas by meta dynamics" | ✅（本轮改回） |
| `man/xtb.1.adoc:238-242` | `-o, --opt` | 是 | "run the landscape suite geometry optimization (pass `--method ancopt` …)" | ✅ |
| `man/xtb.1.adoc:247-250` | `--ohess` | 是 | 同上句式 | ✅ |
| `man/xtb.1.adoc:252-254` | `--bhess` | **否** | "on an `ancopt(3)` optimized geometry" | ✅（改回） |
| `man/xtb.1.adoc:281-283` | `--omd` | **否** | "on `ancopt(3)` optimized geometry" | ✅（改回） |
| `man/xtb.1.adoc:285-287` | `--metaopt` | **否** | "call `ancopt(3)` to perform a geometry optimization" | ✅（改回） |

`src/xhelp.f90` 的 3 处改回后**整个文件与 HEAD 逐字节相同**（`git diff --stat src/xhelp.f90` = **空**；
`--ohess` 的改派文案是 3a 的已提交内容），`man` 侧只余 `--opt`/`--ohess` 两处（3a 的正确改派文案）。

### 2.2 为什么"pass `--method ancopt`"是**不实陈述**（实测，修后二进制）

```
$ xtb w.xyz --gfn 2 --metaopt --method ancopt --norestart     → exit 1
-1- prog_main_parseArguments: --method ancopt selects a native optimizer engine,
    which is only available with --opt or --ohess
$ xtb w.xyz --gfn 2 --metaopt --norestart                     → exit 0
```
`--bhess`/`--omd` 同（三条同一消息；判定点 `main.F90:4388-4391`）。⇒ 这三个 runtype
**只能**走原生 ANCopt，文案说"pass `--method ancopt`"是错的。

### 2.3 `landscape_help_check.py` 集合 S

`ctest -R help` → 2/2 pass（`xtb/landscape-help-coverage` Passed）。文案改动未破坏旗标集合双向一致。

---

## 3. T3（P2-1）`compliance.dat`：**选 (b)**——保持套件条件，改准确措辞 + 登记

**查证结论（先按任务书要求查证 (a) 是否可行）**：套件**能**访问上游 `freezeset`
（`src/fixparam.f90:30` 的模块变量 `xtb_fixparam::freezeset`；先例 `types/constraints.f90:64`
已经 `use xtb_fixparam, only : fixset`）⇒ **(a) 技术上可行**。仍选 **(b)**，理由：

1. **两个名单确实是两个键**：`src/constrain_param.f90:338` 的 `case('atoms')` 写 `fixset`，
   `src/constrain_param.f90:348` 的 `case('freeze')` 写 `freezeset`；上游 `src/hessian.F90:331` 读 `freezeset%n == 0`，
   套件 `landscape_frozen_mask` 读 `fixset`。两个方向都可达
   （`$fix atoms:` → 上游写、套件不写；`$fix freeze:` → 反过来）。
2. **套件的 `$fix` 单一真源就是 `fixset`**（`types/constraints.f90:67-99` 明写"`$freeze` 有意不考虑"，
   因为它是 Hessian-only 的投影）。频率分析的 Hessian 就是在这套掩码下做的，
   让 compliance 条件去读**另一个**名单，等于让"文件写不写"与"频率是在哪个子空间算的"两套判据分叉。
3. **本轮范围**：改读 `freezeset` 会**改变**哪些运行写 `compliance.dat`（`$fix atoms:` 的运行从
   不写变成写），这是行为变更，超出"谓词/初值/文案/登记/测试"。

**措辞（已与代码一致）**：`src/landscape/tasks/vib.f90:166-182` 的注释不再说"同条件/同构"，
改为逐字说明：上游读 `freezeset%n`（`freeze:` 名单，`man/xcontrol.7.adoc:212-216`）、
套件读 `fixset`/`landscape_frozen_mask`（`atoms:` 名单，`src/constrain_param.f90:338-357`）、
两方向可达、以及"为什么套件用 `fixset`"。设计 §3.9 的 `compliance.dat` 行同步改为
"**条件不同构（订正 T3）**"+ 差异登记（`11-cli-redesign.md` §3.9）。

---

## 4. T4（P2-2）`--lvib` 新增输出的登记

- 设计 §1.2 的 BC-4 句订正：`--lvib` **不是**改派 runtype，但 §3.9 给它加了
  **stdout 的 compliance 块 + 新文件 `compliance.dat`** ⇒ BC-4 的有意差异**至少三处**
  （`--opt`/`--ohess`/`--lvib`），不是"两处"。
- §10 的 **B 类**新增一段 "登记 T4"：stdout 变化（逐行比对 `--lvib` 的外部脚本须知悉）、
  文件新增属 BC-3 的"集合不小"、验收测试两条（正向 + 反向）。
- 不变的文件契约语义：`compliance.dat` **裸名**、无命名空间（`src/compliance.f90:287`），
  已由 `xtb/landscape-file-contract-namespace` 守着。

---

## 5. T5（P2-3）设计 §3.9 的 `.xtboptok` 描述

`11-cli-redesign.md` 的 §3.9 测试表原写 `.xtboptok`「**非空**」，与上游
`src/type/iohandler.f90:364-392` 的 `touchFile`（**建空文件**）以及实施报告 §2.1「实测空文件」矛盾。
已订正为「`.xtboptok` **为空**（`iohandler.f90:364-392` 的 `touchFile` 建空文件；订正 T5）」。
**同表顺手订正**（同一类"设计行与实测矛盾"）：`compliance.dat` 的断言从「**首行**含
`compliance.dat`」改为「**内容含**该字符串」——实测首行是 `#`，该串在第 2 行
（`50-stage3b-impl.md` §7 已记录被证伪的前提）。代码侧的断言本来就是"内容含"。

---

## 6. T6（LOW-1）反向用例 + `--ohess` vib 半断言 + 门槛缺陷

### 6.1 新测试 `xtb/landscape-vib-compliance-skip`（mode `vibcomplianceskip`）

反向断言（**不得**写 `compliance.dat`）：

| 用例 | 实测 | 断言 |
|---|---|---|
| 单原子（`He`，`n == 1`） | exit 0，无 `compliance.dat` | `mol%n > 1` 假 |
| `--input <$fix atoms: 1>`（`$fix` 掩码非空） | exit 0，无 `compliance.dat`，`hessian` 存在 | `landscape_frozen_mask` 非空 |

**注入/删条件反例**：删掉条件里的任一子句（`mol%n > 1` 或 `not any(...)`）会让对应用例写文件 ⇒ 红。
（本轮未做该注入的完整复测：新增用例在**未注入**时逐条断言文件**不存在**，
即"条件整块被删/被绕过"必然红；`50-stage3b-impl.md` 已有正向删除 `compliance_driver` 的注入证据。）

### 6.2 `--ohess` 的 vib 半 compliance 断言

`check_file_contract_vib` 现在**同时**跑 `--lvib` 与 `--ohess`：断言 `--ohess` 收敛运行
既有 `hessian` **也有** `compliance.dat`（实测 `/tmp/xtb-3bf/build/xtb`：`--ohess` exit 0，
`compliance.dat` + `hessian` + `vibspectrum` 齐）。⇒ `xtb/landscape-file-contract-vib` 覆盖两条写点。

### 6.3 门槛缺陷记录（**只登记，不修门槛**）

`xtb/landscape-help-coverage`（`test/unit/landscape_help_check.py`）只比对 `--help` 与
`main.F90` 的旗标**集合**（集合 S 差集 = 0），**不比对旗标描述的语义**。
这正是 P1-1（HIGH-2：把三个未改派 runtype 的文案改成不实陈述）能**通过验证**的原因：
三条被改错的文案描述的是**已注册的旗标**，集合不变、脚本全绿。
⇒ **"文案类"变更必须由人/复核读文本**，门槛脚本按设计无法覆盖。
建议（属 3c 或以后）：给 `xhelp.f90` 的每段加"该段描述的 runtype 是否改派"的可核标记，
或加一条"文档中出现的 `--method ancopt` 只允许出现在 `--opt`/`--ohess`/`--lopt` 段落"的检查。

---

## 7. 测试计数与真实输出

```
$ ctest --test-dir /tmp/xtb-3bf/build -R landscape
145/145 Test #225: xtb/landscape-native-runtypes-unaffected ...   Passed    1.85 sec
100% tests passed, 0 tests failed out of 145      Total Test time (real) =  55.95 sec

$ ctest --test-dir /tmp/xtb-3bf/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
100% tests passed, 0 tests failed out of 12

$ ctest --test-dir /tmp/xtb-3bf/build -R help
2/2 pass（Argparser_print_help, xtb/landscape-help-coverage）

$ grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d
（空 —— 无重名）
```

新测试注册三处齐全：`test/unit/landscape_cli_check.py`（2 个 check 函数 + 2 个 `main()` 分派）、
`test/unit/CMakeLists.txt`（2 条 `add_test` + 并入 `set_tests_properties` 环境块）、
`test/unit/meson.build`（2 条 `test` + 新增 `h2o_stretch_xyz` fixture，与 CMake 的
`LANDSCAPE-H2O-STRETCH` 同几何）。meson 本机**未验证**（无 meson/ninja）。

---

## 8. 被证伪的前提（本轮）

1. **"BC-4 对未改派 runtype = 输出逐位相同"在 `--omd` 上不成立**（不是本轮改动造成的）：
   MD 的 `random seed` 每进程随机（同一 pre-3a 二进制连跑两次 seed 335113443 vs 824422036，
   `mdrestart` 不同）⇒ `xtb.trj`/`mdrestart`/`scoord.*` 不可作逐位基线。可用基线是**优化侧**
   （`xtbopt.xyz`/`xtbopt.log`/归一 stdout），实测与 pre-3a 逐位同。任务书 §"BC-4"的措辞需按此收窄。
2. **`--screen` 在无 `screen` 文件时 exit 1 是上游既有行为**（pre-3a 与修后一致，仅 backtrace 地址不同）
   ⇒ 测试把期望退出码钉在 1，而不是"必须 exit 0"。
3. **注入后的 `--omd` 不是"exit 0 且未优化"，而是 exit 1**：从 1.30 Å 输入几何直接跑 MD 会在
   SCC/几何上失败。两者都让测试红（消息为"exited 1 instead of the native 0"+ "no ANC micro-cycles"）。
4. 任务书 T6 的"`$fix atoms:` 反向用例"与 T3 的选项 (a) 互斥（(a) 下 `$fix atoms:` **会**写文件）。
   本轮按 T6 的期望选 (b)，并在 §3 说明理由 —— **该冲突已在报告留痕**。

## 9. 不做 / 未做

- **未**做 R5 档位四轴 / `acc_was_set` / §3.10 再基线（属 3c）。
- **未**改任何算法与收敛判据；**未**碰核心层（`git diff --name-only | grep -cE '^src/(type|xtb|mctc|param|io|disp|coulomb)/'` = **0**；
  `use xtb_landscape` 在七个核心目录 = **0**）。
- **未**重做已通过的部分（T1/T2 的文件契约机制、5 条新测试）。
- **未** `git add` 任何文件（含仓库根的 `stage3b-workflow.js`/`stage3bfix-workflow.js`；`git diff --cached` 空）。
- 残留：meson 注册未验证；`--lvib`/`--ohess` stdout 新增 compliance 块对**外部逐行比对脚本**的提示属文档级。
