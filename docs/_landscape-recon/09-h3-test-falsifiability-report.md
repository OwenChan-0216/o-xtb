# 09 — H3 修复报告：测试可证伪性与失败路径覆盖

> 作者：`worker` subagent（实现线程）。
> 范围：`src/landscape/**`、`test/unit/test_landscape_*.f90`、测试注册文件、`docs/**`。
> 依据：`08-independent-review-m0-m1.md` 的 H3 结论、`xtb-landscape-PLAN.md` §5.4。
> 环境：`/tmp/xtb-land/build`，gfortran，`-DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DCMAKE_BUILD_TYPE=Release`。
> 全部命令与输出均为本机真实执行。

---

## 1. 本次改动文件与规模

| 文件 | 改动 | 净增行 |
|---|---|---|
| `src/landscape/types/results.f90` | `landscape_step%method`/`%fallback`；`landscape_convergence_report%history_method`；`landscape_result%n_fallback`；`append_int` | +51 |
| `src/landscape/optimize/driver.f90` | 方法/兜底追踪；`n_fallback`；NaN/Inf 输入与首次求值守卫（`real_is_finite`）| +63 |
| `src/landscape/optimize/diis.f90` | `diis_direction` 增加可选 `coefficients` 出参（暴露 GDIIS 权重）| +6 |
| `src/landscape/types/log.f90` | 修复轨迹帧元素符号损坏（见 §6）| +5 |
| `test/unit/test_landscape_optimize_math.f90` | 新增 5 个用例 + 独立稠密参考实现 | +380 |
| `test/unit/test_landscape_failure.f90` | **新文件**：失败路径 5 个用例 + 3 个注入模型 | +416 |
| `test/unit/test_landscape_optimize_xtb.f90` | 3 个「假测试」改为真断言 + 3 个辅助过程 | +149 |
| `test/unit/{CMakeLists.txt,meson.build,main.f90}` | 注册 `landscape-failure` | +? |

---

## 2. 新增/修改的用例清单与「捕获什么错误」

### 2.1 `test_landscape_optimize_math.f90`

| 用例 | 断言 | 能捕获的错误 |
|---|---|---|
| `lbfgs-direction` | 手工历史 → `-Hg` 与**独立稠密 BFGS 逆 Hessian 递推**逐分量比 1e-12；内存溢出后检查保留的是**最新** m 对（shift 方向）；空历史返回 `-g` | 二循环顺序写反、`gamma` 取成了最老对、丢弃策略取成丢最新、符号翻转 |
| `diis-coefficients` | GDIIS 权重 `sum(c_i)=1`（1e-10）；非均匀（真外推）；`x+d == Σ c_i x_i`（1e-10） | 增广方程约束行/RHS 写错、直接 `return`（ok=false）、权重退化为平均 |
| `diis-extrapolation` | 驱动级：`history_method` 中 `diis` 计数 > 0 | `diis_direction` 被短路 → 全部退化为 SD，但收敛仍绿 |
| `fallback-counters` | 强凸二次型与 Rosenbrock 上 lbfgs/bfgs/rfo 的 `result%n_fallback == 0`，且各自方向至少用过一次 | **「算法退化成 SD 也能通过」**（如 L-BFGS 返回上坡方向 → 线搜索拒绝 → SD 兜底）|
| `lbfgs-vs-bfgs` | lbfgs/bfgs 坐标级收敛到**同一**解析极小点（1e-3）且两者互差 <1e-3；`n_steps` 关系：12 维二次型 `lbfgs,bfgs < sd`；病态二次型（cond=1000）`n_lbfgs*2 < n_sd`；`n_fallback==0` | 两算法收敛到不同点、准牛顿不优于 SD、退回 SD |
| `rfo-invalid-trust` | `trust<=0`（0 与负）与零梯度都报 `fail`、`step==0`、`predicted==0` | RFO 对非法 trust 或无极小步不报失败、产生虚假位移 |
| `harmonic` / `rosenbrock` / `muller-brown`（原有）| 收敛 + 几何 | 回归 |

### 2.2 `test_landscape_failure.f90`（新）

| 用例 | 断言 | 能捕获的错误 |
|---|---|---|
| `objective-failure` | `fail=.true.` 假模型 → `converged=.false.`、`message="initial energy evaluation failed"`、`n_steps=0`、几何原样返回、不崩溃 | 目标函数失败被当成成功/崩溃 |
| `step-budget` | `max_steps=0` → `"no step performed"`；`max_steps=1` → `"maximum number of steps reached"`；两者均不收敛且 `n_steps` 正确 | 预算为 0/1 时误判收敛或报错信息错误 |
| `uphill-stagnation` | 能量恒增假模型 → `message="stagnated: no acceptable step found"`、`n_steps==10`（patience）、`any(steps%fallback)`、几何不动、不死循环 | 线搜索必然失败时无兜底/死循环/错误收敛 |
| `non-finite-input` | `x0` 含 NaN 或 Inf → `message="initial coordinates are not finite"`、`x_final` 未分配 | NaN/Inf 起点头部污染整条流水线 |
| `non-finite-output` | 目标函数首次返回 NaN → `message="initial energy or gradient is not finite"`、`n_steps=0` | 目标函数输出 NaN 被静默传播 |

### 2.3 `test_landscape_optimize_xtb.f90`（消除假测试）

| 用例 | 原状 | 现状 |
|---|---|---|
| `water-gfn2-minimization` | 只查 `mol%xyz(3,1) < 0.5`（近乎恒真）| 按 `mol%at` 定位 O 与两个 H，算两个 O–H 距离与 H–O–H 角，与独立 GFN2 参考（`xtb --gfn2 --opt`：r=0.9593 Å、∠=107.2°）比 0.01 Å / 1.0°。实测 0.95922/0.95921 Å、107.2245° |
| `water-gfn2-output-files` | 纯冒烟（只 `inquire`）| 解析 `.trj`：帧数 `== result%n_steps+1`；首帧 == 起始几何、末帧 == 优化几何；轨迹确实移动；结束后删除文件（不再往 CWD 留垃圾）|
| `water-gfn2-determinism` | 只断言 `diff < 1e-8`（报告式）| `off` 重启策略下断言**逐位相等** `energy1 == energy2` |
| `gfn2-singlepoint-determinism` | （上一轮已是逐位断言）| 保持 |
| `coords::remove-rotation-*` | （M4 修复轮已补跨帧 + 简并惯量）| 保持 |

---

## 3. 故意注入 bug 的验证（可证伪性证据）

对每个关键断言，实际改坏被测算法 → 构建 → 运行 → 观察变红 → 撤销。全部为真实执行。

| 注入 | 命令/改动 | 结果 |
|---|---|---|
| **L-BFGS 符号翻转**（返回上坡方向，即复核报告描述的「两循环写反」）| `direction = -q` → `direction = q` | `lbfgs-direction` **FAILED**（逐分量不匹配）；`fallback-counters` **FAILED**（`lbfgs ... fallbacks 14`，消息 `"lbfgs degraded to steepest descent on a convex quadratic"`）；`lbfgs-vs-bfgs` **FAILED**（`"L-BFGS is not faster than steepest descent"`，31 vs 31）|
| **L-BFGS 两循环顺序交换** | 第一循环升序、第二循环降序 | `lbfgs-direction` **FAILED** |
| **L-BFGS gamma 取最老对** | `sy/yy` 改用索引 1 | `lbfgs-direction` **FAILED**（差 0.173）|
| **DIIS 直接返回** | `diis_direction` 开头 `return` | `diis-coefficients` **FAILED**（`"GDIIS did not produce an extrapolated step"`）；`diis-extrapolation` **FAILED**（`extrapolated 0, steepest 16`）|
| **DIIS 约束 RHS 符号** | `rhs(n+1) = -1` → `+1` | `diis-coefficients` **FAILED**（`sum(c)= -1` 而非 `+1`）|
| **轨迹丢帧** | `.trj` 从第 2 帧开始写 | `water-gfn2-output-files` **FAILED**（`expected 7 but got 6`）|

> 注意：复核报告断言「把 L-BFGS 返回上坡方向会让线搜索拒绝并退回 SD，测试全绿」。实测确认：**仅靠 `converged` 的旧断言确实全绿**；现在 `n_fallback` 计数与方向复现单测都能独立发现它（上表第 1 行）。这就是 H3 要堵的漏洞。

---

## 4. 真实构建与测试输出

```
$ cmake --build /tmp/xtb-land/build -j            # exit 0，无 landscape 相关警告
$ ctest --test-dir /tmp/xtb-land/build --output-on-failure -R landscape
1/10 ... landscape-settings        Passed
2/10 ... landscape-coords          Passed
3/10 ... landscape-hessian-update  Passed
4/10 ... landscape-optimize-math   Passed
5/10 ... landscape-cg              Passed
6/10 ... landscape-hessian         Passed
7/10 ... landscape-optimize-xtb    Passed
8/10 ... landscape-failure         Passed
9/10 ... #89 xtb/landscape-opt     Passed
10/10 ... landscape-api            Passed
100% tests passed, 0 tests failed out of 10
```

用例级计数（`[PASSED]` 计数）：

| suite | 用例数 |
|---|---|
| landscape-settings | 10 |
| landscape-coords | 8 |
| landscape-hessian-update | 6 |
| landscape-optimize-math | 15（H3 新增 5）|
| landscape-cg | 5 |
| landscape-hessian | 6 |
| landscape-optimize-xtb | 4（H3 重写 3）|
| landscape-failure | 5（H3 新增）|
| landscape-api | 4 |
| **合计** | **63**（复核时为 28）|

关键实测数值（供复核）：
- `lbfgs-direction`：与独立稠密递推差 < 1e-12。
- `diis-extrapolation`：`extrapolated 32, steepest 5, total 37`。
- `fallback-counters`：convex quadratic `lbfgs/bfgs/rfo` 均 `fallbacks 0`；Rosenbrock 亦然。
- `lbfgs-vs-bfgs`：12 维 `lbfgs 13, bfgs 18, sd 31`；病态二次型 `lbfgs 32, sd 3439`。

---

## 5. 仍未覆盖 / 已知边界

1. **NaN/Inf 中途发散守卫不可达**：一致的目标函数若在试探点返回 NaN，Armijo 判据必然拒绝该点，因此「已接受步的 NaN」无法通过正常流程触发；已实现的守卫是「起点非有限」与「首次求值非有限」两条可达路径（均已测试）。未加入不可达的防御分支（避免无测试的死代码）。
2. **`landscape_result%n_fallback` 只计「被接受的兜底步」**：RFO 在到达解析极小点但能量判据（`e_tol`）尚未满足时会做一步零位移（梯度已为 0），该步的兜底被拒绝，故不计入，避免把「无事可做」误报为算法退化。
3. **CLI 层失败路径**（`landscape_optimize` 在 `x_final` 未分配或 `converged=.false.` 时 `env%error`）未新增加注入测试，依赖既有 `xtb/landscape-opt` 冒烟。
4. **`hessian_update` 的 `ok` 分支（M7）**、**M2 `env%check`** 等其它 HIGH/MEDIUM 项不在 H3 范围。
5. **水分子参照容差 0.01 Å / 1.0°**：由 landscape L-BFGS（normal 档）与 xtb ANC 两套优化器的独立结果之差决定（实测 0.0001 Å / 0.03°），留有 ~10× 余量；若未来 GFN2 参数变化需重新标定。

---

## 6. 附带发现（测试轮内修复）

**轨迹帧元素符号损坏**：`landscape_write_files` 原以 `buffer = mol`（`TMolecule` 派生赋值）构造轨迹缓冲，而 `copyMolecule` 把延迟长度字符数组 `sym(:)` 传入 `character(len=*)` 形参，导致 `.trj` 第 2 帧起的元素符号变成含 NUL 的乱码（坐标正确）。

- 证据：修复前 `cat -A landscape_unittest.trj` 显示 `` `^@^@^@ ``、`U#^[\` 等；`landscape_unittestopt.xyz`（由 `mol` 直接写出）符号正确。
- 修复：`call init(buffer, mol%at, mol%xyz, ...)` 从原子序数重建符号；修复后符号全部正确。该修复在 `test_output_files` 的解析断言下被覆盖。
- 根因在 `src/type/molecule.f90` 的 `copyMolecule`（本任务文件集之外），未改动。

**两套 bohr→Å 常数不一致**：`xtb_mctc_convert::autoaa = 0.52917726`（写死），而 mctc-lib 的 xyz writer 用 CODATA 导出的 `0.529177210903`，相对差 ~9e-8。`test_output_files` 用 1e-6 Å 容差并在注释中说明原因（不掩盖真实几何误差）。属既有不一致，未改动（`src/mctc/convert.f90` 不在允许文件集内）。
