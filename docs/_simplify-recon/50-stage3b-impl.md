# Stage 3b — 文件契约 + `--ohess` 失败路径 + 自指清理（实施报告）

基线：HEAD `b822c1f`（阶段 1/2/2b/3a 已提交）。本轮**不动任何数值**（R5 档位四轴属 3c）。
构建：`/tmp/xtb-3b/build`，-O2（`-DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"`）。
权威设计：`docs/_simplify-recon/11-cli-redesign.md` §3.9 / §3.10；事实清单 `49-stage3b-recon.md`。

---

## 1. 源改动表

| 文件 | 改动 | 类别 |
|---|---|---|
| `src/landscape/types/log.f90` | 新增 `landscape_file_contract_reset` / `_mark` / `landscape_write_last_geometry`；`landscape_write_files` 增写 `xtbopt.log`（多帧）；抽出 `write_trajectory_file` | 写文件 |
| `src/landscape/tasks/opt.f90` | 任务开场删哨兵；结束时按 `result%converged` 建 `.xtboptok` / `NOT_CONVERGED`，失败再写 `xtblast.<ext>` | 写文件 / 失败分支 |
| `src/landscape/tasks/vib.f90` | Hessian 成功后按上游条件复用 `compliance_driver` | 写文件 |
| `src/prog/main.F90` | `--ohess` 链：`if (lres%converged)` 守卫 vib 半 | 失败分支（T2） |
| `man/xtb.1.adoc` | 5 处陈旧 `ancopt(3)` 自指改为"套件（`--method ancopt` 回原生）" | 文档（T3） |
| `src/xhelp.f90` | 3 处陈旧 `ancopt(3)` 自指（`:785/:814/:818`）同改 | 文档（T3） |
| `test/unit/landscape_cli_check.py` | 新增 5 个 check 函数 + 5 个 `main()` 分派 | 测试 |
| `test/unit/CMakeLists.txt` | 5 条 `add_test` + 并入 `set_tests_properties` 环境块 | 测试注册 |
| `test/unit/meson.build` | 5 条 `test(...)` | 测试注册 |
| `docs/_simplify-recon/11-cli-redesign.md` | §3.9 标为已落地 + 登记 T2 有意偏离 | 设计留痕 |

**未触碰**：`src/type/latticepoint.f90`（上游文件；修法是**不让错误产生**）；核心层
`use xtb_landscape_*` 实测 **0**（`grep -rn` 六个核心目录）；`xtb.trj` **保留**；`set_conv_level`
字段集未动。

---

## 2. T1 文件契约（逐文件，按上游语义）

### 2.1 `.xtboptok` / `NOT_CONVERGED`
- **开场删**：`opt.f90` 在任务开场 `if (settings%write_files) call landscape_file_contract_reset(env)`
  → 删 `NOT_CONVERGED` 与 `.xtboptok`（同 `src/geoopt_driver.f90:112-113`）。
- **结束时建**：`landscape_file_contract_mark(env, result%converged)` → 收敛 `touch('.xtboptok')`，
  未收敛 `touch('NOT_CONVERGED')`（同 `:183-186`），**互斥**。
- **命名空间**：`get_namespace('.xtboptok')` → `.ns.xtboptok`（与上游 `getName` 同一规则）。

### 2.2 `xtbopt.log`
- `landscape_write_files` 在写出轨迹时**同时**写 `xtb.trj` 与 `xtbopt.log`（同名多帧 XMOL，
  经 `write_trajectory_file`），两者都过 `get_namespace`。
- 名字**无前导点**：`get_namespace('xtbopt.log')` → `ns.xtbopt.log`（同上游 `:121`）。
- `xtb.trj` **保留**（BC-3 允许新增）。

### 2.3 `xtblast.xyz`
- 仅失败时：`landscape_write_last_geometry` 用 `generateFileName(tmpname,'xtblast','',mol%ftype)`
  得扩展名（与输入同型），过 `get_namespace`，打印 `last geometry written to: <name>`
  （同 `src/prog/main.F90:1024-1034`；3b 前为 `:1012-1018`）。

### 2.4 `compliance.dat`
- `vib.f90` 在 `landscape_vib_hessian` 成功后调用**同一个** `compliance_driver`，条件是
  `mol%n > 1 .and. .not. any(landscape_frozen_mask(mol%n)) .and. mol%npbc == 0`。
  **订正（父会话，依据 54 号复核的 LOW-2）**：原文写“条件与上游 `src/hessian.F90:331` **同构**”
  是**不实陈述** —— 上游用的是 `$fix` 的 **`freeze:`** 名单（`freezeset`），套件用的是 **`atoms:`** 名单（`fixset`），
  且两个方向都可达（`$fix atoms:` 上游写/套件不写；`$fix freeze:` 反之）。
  以 `53-stage3b-fix.md` §3 与设计 §3.9 的**差异登记**为准；本条原文不再作为结论依据。
- `compliance_driver` 内用**裸名** `open(file="compliance.dat")`（`src/compliance.f90:287`），
  **不带前缀** —— 套件不干预。

### 2.5 实测文件集合（`/tmp/xtb-3b/scratch`）
```
--lopt 成功     : .xtboptok xtbopt.log xtbopt.xyz xtb.trj ...
--lopt --cycles 2: NOT_CONVERGED xtblast.xyz xtbopt.log xtbopt.xyz xtb.trj （无 .xtboptok）
--lvib          : compliance.dat hessian vibspectrum ...
--lopt --namespace c1: .c1.xtboptok c1.xtbopt.log c1.xtb.trj（无裸名）
--lvib --namespace c1: compliance.dat（无前缀）
```

---

## 3. T2 `--ohess` 失败路径：失败即停

`src/prog/main.F90` 的 `--ohess` 链，在 `run_landscape(lset)` 之后以 `lres%converged` 守卫整个
vib 半。未收敛 ⇒ 跳过 vib；opt 半已由 `landscape_optimize` 记入单因错误，链尾 `env%checkpoint`
将其转为 exit 1。

**实测（修复后）**：
```
$ xtb water.xyz --gfn2 --ohess --cycles 2 --norestart
exit=1
-2- Landscape task terminated
-1- landscape_optimize: landscape minimisation did not converge: maximum number of steps reached
文件: NOT_CONVERGED xtblast.xyz xtbopt.log xtbopt.xyz xtb.trj   （无 hessian/vibspectrum/.xtboptok）
误导级联字样 "Could not generate lattice points" / "Setup of Coulomb evaluator failed"：0
```
**对照成功**：`--ohess`（默认）→ exit 0，有 `.xtboptok` + `hessian` + `vibspectrum`。

---

## 4. T3 自指引导清理

改 `man/xtb.1.adoc:239/247/251/280/284`、`src/xhelp.f90:785/814/818` 为"套件（`--method ancopt`
回原生）"。**未动** `xhelp.f90:272/283-284/303/781-782`（3a 已改对，准确）。
`xtb/landscape-help-coverage`（集合 S 双向一致脚本）**PASS**。

---

## 5. T4 测试与登记

新增 5 条（设计 §3.9 的 4 条 + T2 的 1 条）：

| 测试 | 断言 |
|---|---|
| `xtb/landscape-file-contract-opt` | 收敛 `--opt` → `.xtboptok` 存在且**空**、无 `NOT_CONVERGED`、`xtbopt.log` 多帧（实测 6 帧） |
| `xtb/landscape-file-contract-opt-fail` | `--opt --cycles 2` → 无 `.xtboptok`、有 `NOT_CONVERGED`、`xtblast.xyz` 单帧、打印 `last geometry written to:` |
| `xtb/landscape-file-contract-vib` | `--lvib` → `compliance.dat` 存在且内容含 `compliance.dat` |
| `xtb/landscape-file-contract-namespace` | `--opt --namespace c1` → `.c1.xtboptok`/`c1.xtbopt.log`，无裸名；`--lvib --namespace c1` → 裸 `compliance.dat`，无 `c1.compliance.dat` |
| `xtb/landscape-ohess-fail` | `--ohess --cycles 2` → 非零退出、无级联字样、无 `hessian`/`vibspectrum`、有 `NOT_CONVERGED` 无 `.xtboptok`；对照成功 `--ohess` 有 `.xtboptok`+`hessian` |

**三处注册**：`test/unit/landscape_cli_check.py`（`main()` 分派 5 个新 mode）、
`test/unit/CMakeLists.txt`（5 条 `add_test` + 环境块）、`test/unit/meson.build`（5 条 `test`）。
**重名检查**：`grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d` → **空**。

**真实 ctest 输出**：
```
$ ctest --test-dir /tmp/xtb-3b/build -R landscape
100% tests passed, 0 tests failed out of 143   (Total 40.96 s)
```
新增 5 条（`#219..#223`）全部 Passed。`xtb/landscape-help-coverage` Passed。

---

## 6. 注入真实输出（T2 可证伪）

把 `src/prog/main.F90:1105` 的 `if (lres%converged) then` 注入为 `if (.true.) then`（即总是跑
vib 半），增量重建后：
```
$ xtb water.xyz --gfn2 --ohess --cycles 2 --norestart
exit=1
-3- scf: Setup of Coulomb evaluator failed
-2- type_latticepoint_update: Could not generate lattice points
```
⇒ 误导级联**重现**。还原该行、重建后 `xtb/landscape-ohess-fail` **Passed**。

---

## 7. 被证伪的前提

- **`mol%pbc` 不是标量**：`TMolecule%pbc` 是 `logical :: pbc(3)`（`src/type/molecule.f90:68`），
  首次编译在 `vib.f90` 报 `IF clause ... requires a scalar LOGICAL`。改用 `mol%npbc == 0`
  （periodic 的既有判据）。
- **`compliance.dat` 首行不是 `compliance.dat`**：文件首行是 `#`，`# compliance.dat` 在第 2 行
  （`src/compliance.f90` 表头）。测试改为断言**内容含** `compliance.dat`，不锁首行。
- **`ohessf` 目录里 `grep -c "Coulomb"` = 1 是**正常的计时标签 `* Coulomb:`，不是级联。
  测试因此只匹配完整串 `Setup of Coulomb evaluator failed`。

---

## 8. 有意偏离登记

**T2：套件 `--ohess` 未收敛 → exit 1 + `NOT_CONVERGED` + 不写频率文件。**
原生 `--ohess` 未收敛时 **exit 0** 且**仍写** `hessian`/`vibspectrum`/`.xtboptok`（实测
`--ohess --method ancopt --cycles 1`）。理由：(a) 保持套件既有诚实失败契约（`--lopt` 已 exit 1 +
单因消息）；(b) 非驻点几何上的频率分析意义可疑；(c) `NOT_CONVERGED` 是上游对"未收敛"的既有信号。
已登记于 `docs/_simplify-recon/11-cli-redesign.md` §3.9。

---

## 9. 本阶段不做（确认）

- **未**做 R5 档位四轴（`e_tol`/`acc`/`max_steps`）—— 属 3c；`set_conv_level` 字段集未动。
- **未**做 `acc_was_set` 优先级修复、**未**做 §3.10 再基线。
- **未**改任何数值路径；**未**碰核心层（0 命中）；**未**删 `xtb.trj`。
- **未**提交 git。

## 10. 残留风险

- `--lvib` 现在多打印一段 compliance 块并多写 `compliance.dat`：已由 143 条 landscape 测试确认
  无回归；但任何**外部**逐行比对 `--lvib` stdout 的脚本需知悉（与上游 `--hess` 一致的行为）。
- meson 注册**未验证**（本机无 meson/ninja），照 CMake 逐条镜像书写。
