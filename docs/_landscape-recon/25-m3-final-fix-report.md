# M3（vib）第二轮复核后的最终修复报告（第 25 号）

> 角色：修复者（单写者线程）。输入：复核报告 `24-m3-review-round2.md`（有条件接受；
> CRITICAL 0 / P1 1 / P2 5 / INFO 6，明确要求「进 M4 前必须补 2 项欠账」）、
> `23-m3-fix-report.md`、`AGENTS.md`、`docs/xtb-landscape-PLAN.md`。
> 本轮**只**处理 P1-1、P2-B 与两条措辞（P2-2/P2-3）；其余 P2/INFO 按任务书要求
> 「书面记录并说明为何可接受」。
> 所有 xtb/ctest 调用均为 `OMP_NUM_THREADS=1`；只跑 `-R` 过滤子集，未跑全量 ctest。

---

## 0. 结论摘要

| # | 问题 | 处置 | 状态 |
|---|---|---|---|
| P1-1 | `engine%etemp ← set%etemp` 的 CLI 同步零测试覆盖 | 选方案 (a)：新增 CLI 测试 `xtb/landscape-vib-etemp`（`--etemp 300` vs `--etemp 5000`，断言打印生效值 == 传入值 **且** `eigval` 确实改变） | ✅ 已修，注入实验（删同步行）测试**变红** |
| P2-B | `--lvib` 从不打印生效的 `etemp` | `vib/numhess.f90` 在销毁引擎前按 `printlevel` 调 `engine%report(env%unit)`，从**计算器读回**生效 `etemp` 并打印；CLI 测试断言打印值 == 传入值 | ✅ 已修，实测 `--etemp 300/5000` 打印 `300.000 / 5000.000 K` |
| P2-2 | PLAN §12.11「差异全部来自投影」自相矛盾 | 改为「差异**主要**来自投影（投影项 ≈0.072 cm⁻¹），另有一条 ≤0.004 cm⁻¹ 的**非投影**残余（CO2 实测上界，来源未归因）」；第 23 号 §0、第 21 号 R5 同步 | ✅ 已改 |
| P2-3 | 「∝ ‖g‖」是无数据机制句 | PLAN §12.11、第 20 号 §3.3、第 21 号 §5.3(d) 改为「随偏离驻点程度增大」（附 3 个实测点，注明**未做比例性检验**） | ✅ 已改 |

**验证汇总**：`ctest -R landscape` **36/36 pass**（1.04 s，比修复轮多 1 个新 CLI 测试）；
回归子集 `-R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'` **12/12 pass**；
`ctest -N -R landscape` = **36**；`add_test` 重名检查为空。

**M3 是否可宣称完成**：可以。第 24 号复核的 P1-1 与 P2-B（两条 M4 前置欠账）已实质关闭且可证伪，
P2-2/P2-3 的措辞矛盾已消除；其余 P2/INFO 均为「可见性/健壮性建议」，不改动任何数值结果
（逐条处置见 §5）。

---

## 1. P1-1：为 `--etemp` ↔ landscape 的 CLI 同步补 CLI 测试

### 1.1 选方案与理由

任务书给二选一，复核 §7 P1-1 亦「推荐 (a)」。**选 (a)：补一条 CLI 级测试。**

理由：

1. 该缺陷的本质是「`main.F90` 三个 landscape 入口的同步是唯一真源，却无守卫」。方案 (a)
   直接锁住**真实缺陷**（`src/prog/main.F90:971` 这一行），方案 (b)（哨兵默认值）则把
   「谁负责设 `etemp`」的语义从「引擎控制在每次运行前被同步」改成「未设即报错」，会改变
   既有 API 契约（`landscape_engine_control%etemp` 的默认 300 K 是公共字段语义），
   属于比缺陷本身更大的设计变更。
2. 方案 (a) 零生产代码改动，只加测试，回归面最小；且与 P2-B 的「打印生效值」是同一处
   观测点，一次实现两用（复核 §10 亦点明「与 P2-B 的一行打印一起做最省事」）。

### 1.2 实现

- `test/unit/CMakeLists.txt`：新增资产 `landscape_h2.xyz`（拉伸 H₂，2.4 Å = 4.535 bohr，
  即报告 21 §3.1 的近简并体系；在 build 目录生成，仓库不留测试数据）与 CMake 脚本
  `landscape_cli_vib_etemp.cmake`；新增测试 `xtb/landscape-vib-etemp`，登记进单线程属性表。
- `test/unit/landscape_cli_check.py`：新增 `vibetemp` 模式（meson 对等物）。
- `test/unit/meson.build`：生成同一 H₂ 资产并注册 `landscape vib etemp`（与 CMake 脚本一一对应）。

测试断言（两条，均可证伪）：

1. `--etemp 300` 的 stdout 含 `landscape engine: etemp   300.000 K`，`--etemp 5000` 的 stdout
   含 `landscape engine: etemp  5000.000 K`——**打印值 == 实际传入值**（这条同时是 P2-B 的测试）；
2. 两次运行的 `eigval :` 行**不相等**——电子温度真的改变了频率。

### 1.3 实测（真实数字）

拉伸 H₂（2.4 Å）唯一的内部模（`eigval :` 第 6 列）：

```
$ OMP_NUM_THREADS=1 xtb landscape_h2.xyz --gfn 2 --lvib --norestart --etemp 300
 landscape engine: etemp                   300.000 K
eigval :        0.00     0.00     0.00     0.00     0.00    16.44
$ OMP_NUM_THREADS=1 xtb landscape_h2.xyz --gfn 2 --lvib --norestart --etemp 5000
 landscape engine: etemp                  5000.000 K
eigval :        0.00     0.00     0.00     0.00     0.00     9.88
```

真实数字差：**16.44 cm⁻¹（300 K）→ 9.88 cm⁻¹（5000 K）**，变化 **−39.9 %**（6.56 cm⁻¹），
远大于 FD 噪声（≤0.1 cm⁻¹），第 2 条断言因此稳健。该量级与报告 21 §3.1「−31.4 %」
同向同阶（本几何绝对值更软，比值相近）。

### 1.4 注入实验（可证伪，真实输出）

临时删除 `src/prog/main.F90:971` 的 `lvset%engine%etemp = set%etemp` 后重建：

```
$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape-vib-etemp --output-on-failure
...
0% tests passed, 1 tests failed out of 1

The following tests FAILED:
        107 - xtb/landscape-vib-etemp (Failed)
```

直接跑脚本得到的失败信息（同时暴露了「5000 K 被静默改成 300 K」这一现象）：

```
CMake Error at .../landscape_cli_vib_etemp.cmake:26 (message):
  --etemp 5000 did not reach the engine control (missing CLI sync)
            program call               : ... --gfn 2 --lvib --norestart --etemp 5000
   landscape engine: etemp                   300.000 K
  eigval : 0.00 0.00 0.00 0.00 0.00 16.44
```

即：删同步后 5000 K 的 run 报 `300.000 K`、`eigval` 回落到 300 K 的 16.44 → 两条断言
（打印值、频率不等）同时失败。还原同步行后 `xtb/landscape-vib-etemp [PASSED]`。

---

## 2. P2-B：`--lvib` 打印实际生效的 `etemp`

### 2.1 机制与实现

复核 §7 P2-B 的第二个最小方案（在 `vib/numhess.f90` 销毁引擎前调一次 `engine%report(env%unit)`）
被采纳，理由：它从**计算器读回**（`engine_report` 内 `select type`，`engine.f90:792-796`），
因此不仅验证 `main.F90` 的同步，也验证 `push_calculator_etemp`（「设置没进去」两种失效都会显形）；
而直接打印 `settings%engine%etemp` 只能覆盖前者。

`src/landscape/vib/numhess.f90`：在 `engine%destroy()` 之前插入

```fortran
if (settings%printlevel > 0) call engine%report(env%unit)
```

（与 `sp.f90:150`/`opt.f90:142`/`scan.f90:205` 的调用点同构）。`--lvib` 的引擎在
`landscape_vib_hessian` 内建内销毁，这是它第一次被报告。

### 2.2 实测（真实输出）

```
$ OMP_NUM_THREADS=1 xtb landscape_h2o.xyz --gfn 2 --lvib --norestart
 landscape engine: energy evaluations 19
 landscape engine: cache hits         0
 landscape engine: Hessians           1
 landscape engine: Hessian-vector     0
 landscape engine: unconverged SCC    0
 landscape engine: restart policy     off
 landscape engine: SCC accuracy              1.000000
 landscape engine: etemp                   300.000 K
 landscape engine: hessian source     numerical
```

`--gfnff --lvib` 仍 exit 0（非 `TxTBCalculator` 无该字段，`report` 只打印计数器、不打印
`etemp` 行），无回归。

### 2.3 测试

P2-B 的「打印值 == 实际传入值」由 §1.2 的 CLI 测试断言 1 承担（`--etemp 300` → `300.000`，
`--etemp 5000` → `5000.000`）；删同步行即变红（§1.4），因此它同时是 P2-B 的可证伪测试。
PLAN §12.11 与 §9.5 的措辞已同步为「`sp`/`opt`/`scan`/`vib` 四任务均调用 `engine_report`」。

---

## 3. P2-2 / P2-3：两处措辞改正

### 3.1 P2-2「差异全部来自投影」→「主要来自投影」

- `docs/xtb-landscape-PLAN.md` §12.11：「差异全部来自投影」→「差异**主要**来自投影」，
  并把 CLI 段落的「非投影残余…（FD 实现差异）」改为「（为 `--hess` 与套件两条数值 Hessian
  实现之间的差异，来源未进一步归因，报告 23 §8.1）」。
- `docs/_landscape-recon/23-m3-fix-report.md` §0 处置表：原「差异确实来自投影约定
  （分档 0.0036–5.2109 cm⁻¹）」→「差异**主要**来自投影约定（投影项 ≈0.072–5.21 cm⁻¹），
  另有一条 ≤0.004 cm⁻¹ 的**非投影**残余（CO2 实测上界，来源未归因，§8.1）」。
- `docs/_landscape-recon/21-m3-validation-experiments.md` §7 R5 行同步（见 §3.3）。

现在三份文档对 0.0036 cm⁻¹ 的归属一致：**非投影残余**，不属于投影差异。

### 3.2 P2-3「∝ ‖g‖」删除/降级

- `docs/xtb-landscape-PLAN.md` §12.11：「离驻点越远差异越大（∝ ‖g‖）」→「随偏离驻点程度
  增大而增大（实测三点：极小点 0.074、非驻点 5.213、强扭曲水 12.91 cm⁻¹；**未做比例性检验，
  不写成 ∝ ‖g‖**）」。
- `docs/_landscape-recon/20-m3-vib-implementation-report.md` §3.3：「差异随 ‖g‖ 放大」→
  「差异**的来源**是两个投影在不同度量里定义同一套刚体运动」。
- `docs/_landscape-recon/21-m3-validation-experiments.md` §5.3(d)：同样把 ∝‖g‖ 换成实测三点。

保留的机制陈述只有一条，且每条都有代码或实测支撑：两投影去掉**同一个** 6 维刚体运动的空间，
但在**不同度量**里定义它（`trproj` 单位质量向量 + 非质量加权 Hessian；Eckart 质量加权向量 +
质量加权 Hessian），`trproj` **不含梯度项**（`src/freq/project.f90:151`）。

### 3.3 附带一致性修正

`docs/_landscape-recon/21-m3-validation-experiments.md` §7 R5 行原写「差异确实来自投影」，
与 §3.1 的「非投影残余」矛盾，同步改为「差异**主要**来自投影（投影项 ≈0.072 cm⁻¹），
另有一条 ≤0.004 cm⁻¹ 的非投影残余」并指向本报告。

---

## 4. 变更文件清单（本轮）

**实现**

- `src/landscape/vib/numhess.f90`：销毁引擎前 `if (settings%printlevel > 0) call engine%report(env%unit)`（P2-B）。

**测试**

- `test/unit/CMakeLists.txt`：`landscape_h2.xyz` 资产 + `landscape_cli_vib_etemp.cmake` 脚本 +
  `xtb/landscape-vib-etemp` 测试（并登记单线程属性，P1-1）。
- `test/unit/landscape_cli_check.py`：`vibetemp` 模式。
- `test/unit/meson.build`：H₂ 资产 + `landscape vib etemp`（与 CMake 一一对应）。

**文档**

- `docs/xtb-landscape-PLAN.md`（§9.5、§12.11）、第 20/21/23 号报告（措辞），本报告。

---

## 5. 其余 P2/INFO 的书面处置（为何可接受）

| 项 | 处置 | 理由 |
|---|---|---|
| **P2-1** `--lvib-hessian-file hessian` 原地改写读入文件 | **延后到 M4** | 修法需要先定语义（静默跳过写盘 / `env%warning` / 新增 `--lvib-no-write` 开关），属产品选择而非本轮范围；当前行为确定性、无随机性，且不改动任何频率结果（写入的是重投影后的矩阵，读回仍复现自身），M3 无验收判据依赖它。M4 建议在 `hessian_source == 'file'` 且读写同名时跳写并发 `env%warning` |
| **P2-4** LOW-1 告警无测试；`freq_scal`/`rotor_cutoff` 无 CLI 用例 | **记录，延后** | 告警阈值/措辞已与 `--hess` 对齐且手工复现（`h2o_raw` 上打印）；它不影响结果正确性，且新加 CLI 用例需再增资产与脚本。矩阵可见性（4 个参数中 2 个已有错误用例）已满足 M4 需求 |
| **P2-5** namespace CLI 测试 `eigval` 相等断言在正则不匹配时恒真 | **记录，延后** | 主断言（`ns.hessian` 存在、`ns.ns.hessian` 不存在、第二次 exit 0）已强到能捕捉双重前缀/找不到文件的真实回归；空匹配只是弱化了「频率一致」这一附加断言。本轮新增的 `vibetemp` 模式已显式 guard 空匹配（`if not cold_freqs / hot_freqs`），未扩大改动范围 |
| **INFO-1** `modes.f90` NaN 时判据不一致 | 记录 | 当前不可达（`file` 拒绝非有限、数值 provider 失败即返回），复核亦判非缺陷 |
| **INFO-2** extras 带符号噪声在极小负 `imag_cutoff` 下计入 `n_imag` | 记录 | 既有 `--lvib-imag-cutoff` 语义；M4 判虚频不得只看 `n_imag`（已写入 §12.11） |
| **INFO-3/4** `extra-zero-modes` 的紧阈值依赖几何对称性；一条恒真断言 | 记录 | 不影响可证伪性（真约束由正交性断言承担），复核已判无害 |
| **INFO-5** API 调用者不设 `engine%etemp` 会被改回 300 K | 记录 | 与既有 `acc` 同一设计（引擎控制是唯一真源）；CLI 已同步且新增测试守卫 |
| **INFO-6** `src/landscape/vib/*`、`tasks/vib.f90`、`test_landscape_vib.f90` 仍未 `git add` | **交给父会话** | 交付/提交是父会话动作；本线程遵守 `noStagedFiles`（工作区无 staged 文件） |

---

## 6. 本轮验证命令与输出（真实执行）

```
$ cmake -S . -B /tmp/xtb-land/build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF \
        -DWITH_TESTS=ON -DCMAKE_BUILD_TYPE=Release && cmake --build /tmp/xtb-land/build -j
[100%] Built target xtb-tester

$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape
100% tests passed, 0 tests failed out of 36      # 1.04 s（修复轮为 35）
   其中 ... Test #107: xtb/landscape-vib-etemp ........ Passed

$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build \
    -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
100% tests passed, 0 tests failed out of 12      # 0.27 s

$ ctest --test-dir /tmp/xtb-land/build -N -R landscape | tail -1
Total Tests: 36
$ grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d
                                     # 空 ⇒ 无重名

$ OMP_NUM_THREADS=1 python3 test/unit/landscape_cli_check.py vibetemp \
      /tmp/xtb-land/build/xtb landscape_h2.xyz /tmp/.../pycheck
PYCHECK PASS exit=0                  # meson 对等物亦通过
```

注入实验（§1.4）：删 `main.F90` 同步行 → `xtb/landscape-vib-etemp` **变红**（1 tests failed，
消息 `--etemp 5000 did not reach the engine control`）；还原后 36/36 全绿。

---

## 7. 残留风险

1. `xtb/landscape-vib-etemp` 依赖「拉伸 H₂ 在该 FD 设置下 300 K 与 5000 K 频率显著不同」
   （实测 6.56 cm⁻¹）。若将来把 `etemp` 的物理作用改掉（例如换成固定 broadening），
   该测试会以「频率未变」失败——这正是它应有的行为，不是脆弱性。
2. P2-1（Hessian 文件原地改写）未修，见 §5；M4 若继续主推 `--lvib-hessian file` 的用法，
   应优先处理，否则用户保留的输入文件会被覆盖。
3. `meson.build`/`landscape_cli_check.py` 的对等物已写（`vibetemp` 模式已直接跑通），
   但本机无 `meson`/`ninja`，meson 目标本身仍未在构建系统中验证（与既有 R-16 一致）。
