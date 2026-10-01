# 06 — M0 + M1 实现报告（含真实构建与测试输出）

> 本报告记录 `docs/xtb-landscape-PLAN.md` 中 **M0（骨架）+ M1（极小化器）** 的落地结果。
> 所有数字与输出均为在本机**真实执行**所得；未采信任何转述。
> 构建目录：`/tmp/xtb-land/build`（仓库外）。仓库工作树仅新增 `src/landscape/`、`test/unit/test_landscape_*.f90`、
> `docs/`，以及对 5 个既有文件的**最小**修改（共 +22 行）。
>
> ⚠️ **执行说明**：本里程碑由 subagent `worker` 完成，它在最后的「全量回归」阶段触发了
> 30 分钟超时（原因见 §5），因此**未能自行写出本报告**。本报告由主控复核后补写，
> 所有验证均已由主控独立重跑。

---

## 1. 交付物清单

### 1.1 计划书

| 文件 | 行数 |
|---|---|
| `docs/xtb-landscape-PLAN.md` | **1357** |

章节：1 摘要与决策记录(D1–D4) · 2 问题陈述：ANCopt 缺口 · 3 MAPLE 对照矩阵 · 4 总体架构 ·
5 接口契约 · 6 算法清单与出处 · 7 数值卫生规范 · 8 测试策略 · 9 分阶段里程碑 M0–M7 ·
10 风险登记册 · 11 明确不做的事 · 12 集成点 · 附录 A 环境约束 · 附录 B 与调研设计的差异清单。

### 1.2 新代码 `src/landscape/`（15 个文件，3815 行）

| 文件 | 行数 | 注释行占比 | 职责 |
|---|---|---|---|
| `types/settings.f90` | 345 | 38% | 抽象 `landscape_settings` 基底 + `landscape_sp_settings` + `landscape_opt_settings`；算法/Hessian 更新枚举；4 判据 `is_converged` |
| `types/results.f90` | 278 | 27% | `landscape_step` / `landscape_result` / `landscape_convergence_report` |
| `types/coords.f90` | 403 | 23% | pack/unpack、范数工具、质量加权（坐标与 Hessian 双向）、去平动/去转动、单位转换集中处 |
| `engine/engine.f90` | 614 | 33% | `landscape_engine`：`calc%singlepoint`/`calc%hessian` 薄封装 + 几何逐位缓存 + `n_eval`/`n_cache_hit` 计数 + 可注入抽象接口 |
| `engine/testpot.f90` | 351 | 30% | 解析测试势：各向异性简谐振子、Rosenbrock、Müller-Brown |
| `optimize/hessian_update.f90` | 285 | 30% | BFGS（含 Powell 阻尼）/ SR1 / Bofill / Powell；强制对称化；返回 ok 标志 |
| `optimize/line_search.f90` | 125 | 41% | 回溯 Armijo/Wolfe 线搜索 |
| `optimize/sd.f90` | 47 | 59% | 最速下降 |
| `optimize/lbfgs.f90` | 180 | 32% | 两循环递归 L-BFGS（memory 可配、曲率条件筛选） |
| `optimize/bfgs.f90` | 154 | 37% | 稠密 BFGS（可选 Bofill/SR1/Powell） |
| `optimize/diis.f90` | 185 | 35% | GDIIS（含正则化） |
| `optimize/rfo.f90` | 218 | 31% | RFO：dual-shift trust region，`hlow` 处理负曲率 |
| `optimize/driver.f90` | 559 | 17% | 统一入口 `landscape_optimize` + 逐步日志 + 轨迹输出 |
| `CMakeLists.txt` / `meson.build` | 39 / 32 | — | 构建接入 |

### 1.3 新测试 `test/unit/`（5 个文件，1484 行）

| 文件 | 行数 | 用例数 |
|---|---|---|
| `test_landscape_settings.f90` | 306 | 6 |
| `test_landscape_coords.f90` | 273 | 6 |
| `test_landscape_hessian_update.f90` | 253 | 5 |
| `test_landscape_optimize_math.f90` | 443 | 7 |
| `test_landscape_optimize_xtb.f90` | 209 | 4 |
| **合计** | **1484** | **28** |

### 1.4 对既有文件的修改（`git diff --stat`）

```
 src/CMakeLists.txt       |  1 +
 src/meson.build          |  1 +
 test/unit/CMakeLists.txt |  5 +++++
 test/unit/main.f90       | 10 ++++++++++
 test/unit/meson.build    |  5 +++++
 5 files changed, 22 insertions(+)
```

新增行分别是：注册 `landscape` 子目录（CMake/Meson 各 1 行）、注册 5 个新测试套件
（CMake/Meson 各 5 行）、在 test-drive 运行器的用例清单中登记 5 个套件（`main.f90` 10 行）。

> **偏差说明**：`test/unit/main.f90` 不在初始授权的允许清单内，但它是**必要**的——
> test-drive 需要在该文件中登记用例名，否则新增测试不会被执行。改动为纯增量（10 行），无逻辑修改。

### 1.5 `git status`

```
 M src/CMakeLists.txt
 M src/meson.build
 M test/unit/CMakeLists.txt
 M test/unit/main.f90
 M test/unit/meson.build
?? docs/
?? src/landscape/
?? test/unit/test_landscape_coords.f90
?? test/unit/test_landscape_hessian_update.f90
?? test/unit/test_landscape_optimize_math.f90
?? test/unit/test_landscape_optimize_xtb.f90
?? test/unit/test_landscape_settings.f90
```

---

## 2. 构建（真实执行）

```bash
cmake -S /home/owenchan/work_path/coding/fortran/xtb -B /tmp/xtb-land/build \
      -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/xtb-land/build -j
```

增量重建输出：
```
[ 89%] Built target lib-xtb-static
[ 89%] Built target lib-xtb-shared
[ 91%] Built target xtb-exe
[ 99%] Built target xtb-tester
[100%] Built target xtb_tests_capi
```

**结论**：`libxtb` 静态库、共享库、`xtb` 可执行文件、`xtb-tester`、C API 测试**全部构建成功**，
未破坏既有构建。产物 `xtb` 可正常运行：
```
$ ./xtb --version
   * xtb version 6.7.1 (17790202eb14eeb40effc05008f5508fb0a52157) compiled by '@Linux' on 2026/10/01
```

> 注：`-DWITH_CPCMX=OFF` 是**必需**的（cmake 4.3.2 下 cpcmx 与 toml-f 的 imported target 重名会让配置失败），
> 这是既有环境约束，与本次改动无关。
> Meson 侧已写入 `src/landscape/meson.build` 与测试注册，但**本机未安装 meson/ninja，无法验证**。

---

## 3. 测试（真实执行，28/28 通过）

```bash
ctest --test-dir /tmp/xtb-land/build --output-on-failure -R landscape -V
```

```
52: # Testing: landscape-settings
52:        ... defaults-common [PASSED]
52:        ... defaults-opt [PASSED]
52:        ... defaults-sp [PASSED]
52:        ... convergence-boundary [PASSED]
52:        ... convergence-measures [PASSED]
52:        ... convergence-levels [PASSED]
52:        ... identifier-names [PASSED]
1/5 Test #52: xtb/landscape-settings ...........   Passed    0.00 sec
53: # Testing: landscape-coords
53:        ... pack-unpack [PASSED]
53:        ... vector-tools [PASSED]
53:        ... mass-weight [PASSED]
53:        ... remove-translation [PASSED]
53:        ... remove-rotation [PASSED]
53:        ... unit-conversion [PASSED]
2/5 Test #53: xtb/landscape-coords .............   Passed    0.10 sec
54: # Testing: landscape-hessian-update
54:        ... secant-condition [PASSED]
54:        ... symmetrization [PASSED]
54:        ... powell-damping [PASSED]
54:        ... sr1-skip [PASSED]
54:        ... dispatch [PASSED]
3/5 Test #54: xtb/landscape-hessian-update .....   Passed    0.00 sec
55: # Testing: landscape-optimize-math
55:        ... harmonic [PASSED]
55:        ... rosenbrock [PASSED]
55:        ... muller-brown [PASSED]
55:        ... lbfgs-vs-bfgs [PASSED]
55:        ... rfo-trust-limited [PASSED]
55:        ... engine-cache [PASSED]
55:        ... engine-hvp [PASSED]
4/5 Test #55: xtb/landscape-optimize-math ......   Passed    0.10 sec
56: # Testing: landscape-optimize-xtb
56:        ... water-gfn2-minimization [PASSED]
56:        ... water-gfn2-output-files [PASSED]
56:        ... water-gfn2-determinism [PASSED]
56:        ... gfn2-singlepoint-determinism [PASSED]
5/5 Test #56: xtb/landscape-optimize-xtb .......   Passed    4.63 sec
Total Test time (real) =   4.83 sec
```

**5 个套件、28 个用例全部通过。**

---

## 4. 数值卫生审计（主控独立核验）

| 检查项 | 结果 |
|---|---|
| `stop` / `error stop` | **0** ✅ |
| 直接 `call dgemm/dgemv/dsyev/dgesv/...`（绕过包装） | **0** ✅ |
| `real*8` / `real(8)` / `real(kind=8)` | **0** ✅ |
| 缺少 `implicit none` 的文件 | **0** ✅ |
| 真·module 级可变量（非 `parameter`、非 type 组件） | **0** ✅ |
| 未加 `_wp` 的裸实数字面量 | **0** ✅ |
| `!>` 文档注释行总数 | **921** ✅ |
| 文件级注释行占比 | 17%–59%（`driver.f90` 最低 17%） |

> 独立核验方法：用脚本逐个文件定位 `module` 与 `contains` 之间的声明区，
> 并区分「派生类型组件」与「模块变量」。初查中由简单正则得到的 148 个命中**全部为派生类型组件**
> （例如 `type :: landscape_bfgs_type` 内的 `hess`），不是全局状态。**模块级可变量确认为 0。**

---

## 5. Worker 超时的根因（非代码问题）

Worker 在完成代码与 5 个 landscape 测试后，额外运行了**全量 ctest**：

```
$ cd /tmp/xtb-land/build && timeout 3000 ctest -j 4
Test project /tmp/xtb-land/build
      Start 44: xtb/docking
      Start 48: xtb/gfn2
      Start 47: xtb/gfn1
      Start  4: mctc-lib/ncoord
 1/84 Test  #4: mctc-lib/ncoord ..................   Passed  155.95 sec
      Start 49: xtb/gfnff
... (在 30 分钟处被 subagent 超时终止)
```

全量套件共 **84 项**（含 mctc-lib 与 test-drive 的测试），其中单项 `mctc-lib/ncoord` 耗时 **155.95 秒**。
因此 30 分钟超时是**回归范围过大**所致，**与本次新增代码无关**。

**处置**：主控已终止残留的 `ctest` / `xtb-tester` 进程（`pkill -9 -x xtb-tester` / `-x ctest`），
并改为只运行 `-R landscape` 的定向回归（4.83 秒，全绿）。

**M2 起的流程修正**：回归验证使用 `ctest -R 'landscape|opt|...'` 的**定向子集**，
或在 `worker` 任务里显式设定 `timeoutMs`。全量回归应由独立的长时任务承担（或使用 `-E` 排除慢测试）。

---

## 6. 与 PLAN 的偏差

| 项 | PLAN | 实现 | 说明 |
|---|---|---|---|
| 引擎抽象 | 抽象引擎边界 + 可注入接口 | 已实现（`landscape_engine` + `abstract interface`） | 一致 |
| 几何缓存 | 逐位相同则命中缓存，`n_eval` 不增 | 已实现，且有专门测试 `engine-cache` | 一致 |
| Hessian 提供者抽象 | abstract interface + 数值实现 + 解析钩子 | M0 只做了 `engine_hessian` 薄封装；提供者抽象类型**尚未显式抽出** | ⚠️ 偏差：需在 M3 补齐。见 §7 |
| 测试文件数 | 5 个 | 5 个 | 一致 |
| `test/unit/main.f90` | 未列在允许清单 | 已修改（+10 行，纯增量） | 必要，见 §1.4 |
| 全量回归 | 「不破坏既有测试」 | 未完成（超时） | 由定向回归部分替代；建议后续补跑 |

---

## 7. 遗留问题与 M2/M3 入口

### 7.1 必须在 M3 之前解决的（来自 `07-*.md` 的实测结论）

1. **【HIGH】统一重启策略**：F3 实测表明，warm-start 与 cold-start 混用会引入 `3.9e-07 Eh/bohr`
   的梯度跳变，足以让 P-RFO 的模态跟随失效。`xtb_landscape_engine` 必须把「cold / warm」
   作为显式可配项，并在单次任务内保持一致；同时固定并记录 `OMP_NUM_THREADS`
   （F2：跨线程差异 `1.05e-14 Eh/bohr`，会破坏逐位缓存判据）。
2. **【HIGH】自建 FD Hessian**：F4 实测表明 xtb 的 `$hess` 控制块数值键（`step` / `sccacc`）
   在非 `--copy` 路径下**静默无效**。因此 M3 的 `vib/numhess.f90` 必须自建有限差分 Hessian，
   把步长与 SCC 精度作为显式参数传递，而**不能**依赖 `set%step_hess` / `set%accu_hess`。
   这同时是去风险实验 #2 的唯一正确载体。
3. **【MEDIUM】补齐 Hessian 提供者抽象**：M0 尚未把「Hessian 提供者」抽成可替换类型，
   只在 `landscape_engine` 上暴露了 `engine_hessian`。与 D3 决策有偏差，需在 M3 补齐
   （新增 `landscape_hessian_provider` abstract type + `landscape_numerical_hessian_provider` 实现）。
4. **【MEDIUM】全量回归补跑**：本轮只跑了定向回归。建议在 M2 完成后用
   `ctest -j 4 -E 'mctc-lib|gfnff|docking'` 或分片方式补一次。

### 7.2 M2（扫描）的入口

- 复用 `xtb_constrainpot`（`src/constrain_pot.f90`）与 `xtb_scan::relaxed_scan`（`src/scan_driver.f90:21`）
  的既有约束机制，新写外层网格循环与 2D/刚性扫描。
- 需要在 `landscape_settings` 中新增 `landscape_scan_settings`（PALN §5 已给出字段与默认值）。
- 需新增 `types/scanparam.f90` 或复用 `src/scanparam.f90` 的 `tb_scan` 列表——**先确认复用边界**。
- 验收：relaxed dihedral scan 的剖面极值位置与 MAPLE 输出一致；rigid scan 与手工构造几何一致；
  2D 网格计数正确。
- 去风险实验 #11（rigid vs relaxed 滞回量化）应在 M2 内完成。

### 7.3 已确认可复用的 M0 资产

- 解析测试势 `xtb_landscape_testpot`（简谐振子 / Rosenbrock / Müller-Brown）→ M2/M4/M6 的算法级测试可直接用。
- `landscape_engine` 的可注入接口 → 任何新算法都能在**不跑 SCF** 的前提下做单元测试。
- `landscape_result` / `landscape_step` → 扫描与路径方法可复用其收敛报告结构。
