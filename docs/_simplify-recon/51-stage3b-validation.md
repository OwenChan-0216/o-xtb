# Stage 3b — 独立验证报告（validator）

**结论：通过（PASS），可以提交。** 无 CRITICAL / HIGH / MEDIUM。3 条 LOW/INFO 观察（§7），
均不阻塞，建议 3c 处理或登记。

- 被验对象：工作树（HEAD `b822c1f` + 未提交的 3b 改动，10 文件，+491/−18）。
- 验证者**独立**复跑：自建 `/tmp/xtb-3b/build`（-O2）、自建 scratch `/tmp/xtb-3b-val/`，
  不使用实施者的 scratch；**未改 `src/`、`test/`**。
- 权威：`docs/_simplify-recon/11-cli-redesign.md` §3.9；事实清单 `49-stage3b-recon.md`。
- 所有 xtb/ctest 均 `OMP_NUM_THREADS=1`、`timeout 600`；未跑全量 ctest。

---

## 0. 判定摘要

| 条目 | 结论 | 证据 |
|---|---|---|
| T1 文件契约（4 文件 + namespace） | **PASS** | §2，逐条实跑 |
| T2 `--ohess` 失败路径 | **PASS**（注入重现级联） | §3 |
| T4 数值不变（5 任务） | **PASS** | §4，除版本串/计时/新增文件外逐字节相同 |
| T3 自指清理 + 集合 S | **PASS** | §5 |
| 测试注册（CMake + meson 镜像 + 重名） | **PASS** | §1 |
| 新增测试可证伪 | **PASS**（对 HEAD 二进制 5/5 红） | §6 |
| 有意偏离（T2 exit 1） | **接受**，已在设计 §3.9 登记 | §8 |

---

## 1. 构建与测试计数（真实输出）

```
$ cmake -S . -B /tmp/xtb-3b/build ... -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"
$ cmake --build /tmp/xtb-3b/build -j16            → exit 0，0 处 error
$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-3b/build -R landscape
100% tests passed, 0 tests failed out of 143        Total Test time (real) = 42.49 sec
  #219 landscape-file-contract-opt        Passed
  #220 landscape-file-contract-opt-fail   Passed
  #221 landscape-file-contract-vib        Passed
  #222 landscape-file-contract-namespace  Passed
  #223 landscape-ohess-fail               Passed
$ OMP_NUM_THREADS=1 ctest ... -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
100% tests passed, 0 tests failed out of 12
$ grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d   →  (空)
$ ctest --test-dir /tmp/xtb-3b/build -N -R landscape → Total Tests: 143
$ ctest --test-dir /tmp/xtb-3af/build -N -R landscape → Total Tests: 138
```

⇒ **138 → 143（+5）**，与实施报告一致；无重名吞测试。三条注册（`CMakeLists.txt` /
`meson.build` / `landscape_cli_check.py` 的 `main()` 分派）**逐条核对存在**（meson 无法本地执行，
与实施报告同局限）。

---

## 2. T1 文件契约逐条实测

搭好 scratch 后**每条在独立目录**运行（`cd <dir> && <abs xtb> <abs input>`）。

```
$ xtb water.xyz --gfn2 --lopt --lopt-level normal        exit=0
  文件: .xtboptok(0 B) xtbopt.log xtbopt.xyz xtb.trj xtbrestart xtbtopo.mol charges wbo
  .xtboptok 字节数 = 0（空哨兵，符合上游 touch_file）
  stdout: "steps: 5"；xtbopt.log 帧数 = 6 = 步数+1（输入几何是第 1 帧）
  cmp xtbopt.log xtb.trj → 相同；grep -c 'iter:' = 6

$ xtb water.xyz --gfn2 --lopt --cycles 1                 exit=1
  文件: NOT_CONVERGED(0 B) xtblast.xyz xtbopt.log(=2 帧) xtbopt.xyz xtb.trj
  **无 .xtboptok**
  打印: "last geometry written to: xtblast.xyz"
  核: xtblast.xyz 坐标 == xtbopt.log 第 2 帧 == xtbopt.xyz（"最后几何"语义正确）

$ xtb water.xyz --gfn2 --lvib                            exit=0
  文件: compliance.dat hessian vibspectrum vib_normal_modes g98.out charges wbo ...
  compliance.dat 首行 "#"，第 2 行 "# compliance.dat"（实施报告 §7 的证伪成立）

$ xtb water.xyz --gfn2 --lopt --namespace c1             exit=0
  文件: .c1.xtboptok c1.xtbopt.log c1.xtbopt.xyz c1.xtb.trj ...
  **无** 裸 .xtboptok / xtbopt.log / xtbopt.xyz

$ xtb water.xyz --gfn2 --lvib --namespace c1             exit=0
  文件: compliance.dat（**裸名**，无 c1.compliance.dat）+ c1.hessian c1.vibspectrum ...
```

⇒ 4 个文件的上游语义、命名空间规则（点开头 `.ns.xtboptok`、其余 `ns.<name>`、
`compliance.dat` 裸名）**全部与事实清单一致**。

**额外交叉核（实施报告未给）**：同一几何（未优化的 water.xyz）上，
套件 `--lvib` 与**原生 `--hess`** 写出的 `compliance.dat` 数值一致到
`2.121552372105` vs `2.121552372175`（相对 ≈3e-11），全部条目同量级。
⇒ compliance 复用是**同源正确**的，不只是"文件存在"。

---

## 3. T2 `--ohess` 失败路径 + 注入

```
$ xtb water.xyz --gfn2 --ohess --cycles 2 --norestart    exit=1
  -2- Landscape task terminated
  -1- landscape_optimize: landscape minimisation did not converge: maximum number of steps reached
  误导弹数词 "lattice point" / "Setup of Coulomb evaluator failed"：0
  文件: NOT_CONVERGED xtblast.xyz xtbopt.log xtbopt.xyz xtb.trj
        **无 hessian / vibspectrum / .xtboptok**
  out.log 中 "Coulomb:" 出现 1 次 = 计时标签 `* Coulomb:`（非级联）——证伪成立

$ xtb water.xyz --gfn2 --lopt --cycles 2 --norestart     exit=1  同一条单因消息，无级联
$ xtb water.xyz --gfn2 --ohess --norestart               exit=0  .xtboptok + hessian + vibspectrum + compliance.dat
$ xtb water.xyz --gfn2 --ohess --method ancopt --cycles 1 exit=0 打印 "*** FAILED TO CONVERGE ... ***"，
        仍写 hessian/vibspectrum/.xtboptok（= 被登记的原生对照行为）
```

**注入（不改仓库源码）**：把 `src/prog/main.F90:1105` 的 `if (lres%converged) then`
改为 `if (.true.) then`，在 `/tmp` 副本上用**同 flags 手工重编译单文件 + 重链接**（构建目录
`/tmp/xtb-3b/build`，仓库 `src/` 未被触碰）：

```
$ <注入二进制> water.xyz --gfn2 --ohess --cycles 2 --norestart   exit=1
  -7- Landscape task terminated
  -6- landscape_vib_hessian: landscape frequency analysis: the single point of the reference geometry failed
  -5- landscape_engine_energy_gradient: SCC did not converge at the current geometry ...
  -4- xtb_calculator_singlepoint: Electronic structure method terminated
  -3- scf: Setup of Coulomb evaluator failed
  -2- type_latticepoint_update: Could not generate lattice points
  -1- landscape_optimize: landscape minimisation did not converge: maximum number of steps reached
```
⇒ 级联**完整重现**（含 `latticepoint` 误导消息）。还原对象文件重链接后
`cmp xtb <备份>` rc=0（**逐字节复原**），再跑 `--ohess --cycles 2` → 单因消息、级联 0。

---

## 4. T4 数值不变（5 任务 × 新旧二进制逐字节）

对新二进制与 HEAD 二进制 `/tmp/xtb-3af/build/xtb` 同命令同输入对跑，把版本串归一后
对**全部输出文件**逐字节比较：

| 任务 | 命令 | 结果 |
|---|---|---|
| `--lopt` | `--lopt --lopt-level normal` | xtbopt.xyz / xtb.trj 归一后**相同**；新增 xtbopt.log |
| `--lscan` | `--lscan-coord distance --lscan-atoms 1,2 --lscan-step 0.05 --lscan-nstep 2` | xtbscan.log 归一后**相同**（能量逐位相同） |
| `--lts` | `--lts-method prfo --lts-init-mode force --lts-max-steps 3` | xtbts.xyz / xtbts.log 相同（两侧同 exit=1 同错误消息） |
| `--lirc` | `--lirc-method hpc --lirc-max-steps 3` | irc_path.xyz / irc.log **逐字节相同**；fwd/bwd 仅版本串行 |
| `--lvib` | `--lvib` | hessian / vibspectrum / vib_normal_modes / g98.out **逐字节相同** |

未归一化时的差异**只有三类**：(a) `xtb: 6.7.1 (<hash>)` vs `(unknown-commit)`；
(b) 计时/random-seed/日期行；(c) 新增文件与新增的 compliance 输出块。
**能量、梯度、坐标、频率、IRC 路径数值零变化。**

---

## 5. T3 自指清理 + 集合 S

`git diff src/xhelp.f90 man/xtb.1.adoc` 核对：
- **已改（陈旧）**：`man/xtb.1.adoc` `--opt`/`--ohess`/`--bhess`/`--omd`/`--metaopt` 5 处；
  `xhelp.f90` `--ohess`(:783)/`--bhess`(:785)/`--omd`(:814)/`--metaopt`(:818) —— 均改为
  "landscape suite（`--method ancopt` 回原生）"。
- **未动（准确）**：`xhelp.f90:272/283-284/303/781-782`（3a 已改对，逐行读确认仍然准确）。

集合 S：
```
$ ctest --test-dir /tmp/xtb-3b/build -R landscape-help-coverage
1/1 Test #196: xtb/landscape-help-coverage ......   Passed   0.02 sec
```
（该测试即 `main.F90` ↔ `xhelp.f90` 双向 help 集合一致性脚本，S 差集为 0。）

---

## 6. 新增测试的**可证伪性**（对 HEAD 二进制全红）

用**新测试脚本**驱动 **HEAD 二进制** `/tmp/xtb-3af/build/xtb`（无 3b 特性）：

| mode | 旧二进制 | 新二进制 |
|---|---|---|
| `filecontractopt` | rc=1 `FAIL: a converged --opt wrote no .xtboptok` | rc=0 |
| `filecontractoptfail` | rc=1 | rc=0 |
| `filecontractvib` | rc=1 `FAIL: --lvib wrote no compliance.dat` | rc=0 |
| `filecontractns` | rc=1 `FAIL: --opt --namespace c1 wrote no .c1.xtboptok` | rc=0 |
| `ohessfail` | rc=1 | rc=0 |

⇒ 5 条新测试**全部可证伪**（不是恒真断言），且对 3b 实现为绿。

---

## 7. 证伪清单（实施报告说错 / 说漏）

| # | 级别 | 内容 | 证据 |
|---|---|---|---|
| L1 | LOW | **说漏**：只有 `--lopt`（含 `--ohess` 的 opt 半）会在开场删/建 `.xtboptok`、`NOT_CONVERGED`、`xtbopt.log`、`xtblast.xyz`。`--lscan/--lts/--lirc/--lvib` **不 reset** 哨兵 ⇒ 上一轮 `--lopt` 留下的陈旧 `.xtboptok` 会残留，可能误导只看哨兵的外部流水线。设计 §3.9 未把 reset 定义为"所有任务"；建议 3c 决定是否统一开场 reset。 | `grep -rn landscape_file_contract src/landscape/tasks/*.f90` 仅 `opt.f90:153/239` |
| L2 | INFO | **表述需登记**：`xtbopt.log` 帧数 = **步数 + 1**（输入几何是第 1 帧）。实测成功 5 步 → 6 帧；失败 1 步 → 2 帧。验收脚本不要写成"帧数 == 步数"。实施报告只写"6 帧"，未明确该 +1。 | §2 实测 |
| L3 | INFO | **说漏**：实施报告未给出套件 `--lvib` 的 `compliance.dat` 与**原生 `--hess`** 的数值对照。本次补测相对差 ≈3e-11（同源正确）。建议把该对照写进测试或报告，否则"复用了 driver"只是代码事实而非数值事实。 | §2 末 |

其余报告主张**均经实测复现**：scc 计数 143、重名空、`mol%pbc` 是 `logical :: pbc(3)`
（`src/type/molecule.f90:68`，`npbc` 在 `:71`）、`compliance.dat` 首行为 `#`、
`* Coulomb:` 计时标签、注入重现级联、`--ohess --method ancopt` 原生对照、
核心层 `use xtb_landscape_*` = **0**（`grep -rn` 六个目录）、未触碰 `src/type/latticepoint.f90`
（10 个改动文件中无该文件）。

---

## 8. 有意偏离的认定

**T2：套件 `--ohess` 未收敛 ⇒ exit 1 + `NOT_CONVERGED` + 不写频率文件。**
原生 `--ohess` 未收敛时 exit 0 且仍写频率（§3 实测复现）。两者都**实测确认**，
偏离已在设计 §3.9 明确登记并给出理由（诚实失败契约 / 非驻点频率意义 / `NOT_CONVERGED`
是上游既有信号）。验证者**接受**该偏离：它把"静默地在坏几何上出频率"变成"响亮失败"，
且与套件 `--lopt` 既有行为一致。

---

## 9. 残留风险

1. **meson 注册未验证**（本机无 meson/ninja）——与实施报告同局限；逐条镜像已人工核对存在。
2. **`--lvib` stdout 新增 compliance 块 + 新文件 `compliance.dat`**：任何逐行比对 `--lvib`
   stdout 的外部脚本需知悉；与原生 `--hess` 行为一致，属预期。
3. **L1 的哨兵 reset 范围**（非 opt 任务不 reset）——若外部流水线对非 opt 任务也检查
   `.xtboptok`，会读到陈旧值。当前设计未要求，登记为 3c 候选。

---

## 10. 结论

**通过，可以提交。** T1/T2/T3/T4 逐条实跑成立；新增 5 条测试可证伪且对旧二进制全红；
5 个任务的数值输出与 HEAD 二进制逐字节相同（除版本串/计时/新增文件）；级联注入重现、
还原后二进制逐字节复原。无 CRITICAL/HIGH/MEDIUM；L1 建议 3c 决策，L2/L3 为登记项。
