# 08 — M0+M1 独立复核意见（reviewer）+ 主控验证附录

> 复核者：`reviewer` subagent（独立上下文、read-only、thinking=high）。
> 复核范围：`src/landscape/` 全部 15 个文件 + `test/unit/test_landscape_*.f90` 5 个文件。
> 复核者的结论与原文见下；**主控附录**见文末，记录了主控对关键声明的独立复核结果，
> 以及复核者因只读工具集无法执行、而由主控补做的构建与测试证据。

---

## 1. 复核结论

**有条件接受（conditional accept）。**

M0+M1 的**算法内核在本次审计的所有攻击面上没有发现 CRITICAL**：

- L-BFGS 两循环**逐行符合** Nocedal & Wright Alg. 7.4
- BFGS + Powell 阻尼的 θ 表达式被测试精确钉死
- 四个 Hessian 更新全部强制对称化且分母守卫完整
- RFO 的 secular 方程 / 二分 / trust 上下界在数学上闭合

**但以下三条必须先处理，否则不能宣称 M0/M1 完成：**

1. **H1** PLAN §5 的引擎契约（restart 策略 / `wfn_ref`）**完全未实现**，而 settings 里留着一个**从不被读取**的 `restart_mode`
2. **H2** M0 的 api/driver/tasks 外壳与 `main.F90` 接线**缺失** —— 套件在 `libxtb` 里是**死代码**
3. **H3** 测试套件**没有任何失败路径覆盖**，且两个最关键算法单元（L-BFGS 递推、GDIIS 线性解）**无法被现有测试证伪**

---

## 2. HIGH 问题

### H1 — 引擎 restart 策略未实现，`restart_mode` 是死设置

**证据**
- `types/settings.f90:129` 声明 `restart_mode = p_landscape_restart_off`；全树 `grep restart_mode` **只命中这一行** → 从未被读取。
- `engine/engine.f90:404-406` 无条件传 `.true.`：
  `call singlepoint(env, mol, chk, self%calc, ..., .true., self%ctrl%lgrad, ...)`
- engine 中**没有** `wfn_ref`、**没有** `engine_pin_state`。

**为什么是问题**
PLAN §5.1 规定 `p_restart_off`（默认）=「每次 E+G 前从 `wfn_ref` 重置波函数」，理由是直接对抗
上游 issue #1378（同几何两次梯度不同）；PLAN R-02 把它列为**最高风险**。现在默认路径实际是
「沿用 `chk` 里的上一个波函数做热启动」，而设置里写着 `off`，**语义相反**。
`test/unit/test_landscape_optimize_xtb.f90:21-23` 的注释自己承认 determinism probe
「deliberately not asserted」，即 R-02 完全未量化。

**最小修复**：在 `new_landscape_engine` 里加 `wfn_ref` + 每步 `wfn%copy(wfn_ref)`（off/pin/warm
三态并打印），**或者**删掉 `restart_mode` 字段并在 PLAN / engine 头注释里改口径
（不能再让文档暗示它生效）。

### H2 — M0 交付不完整：没有对外入口，也没有任何接线，`--lopt` 不存在

**证据（复核者独立 grep）**
- `use xtb_landscape|run_landscape` 在 `src/` 下的命中**全部**在 `src/landscape/**` 内
- `src/prog/main.F90` 无 `p_run_lopt` / `--lopt`（`p_run_*` 分派在 `:568-570`、`:1095-1131` 均无 landscape 分支）
- 工作树 diff 只有 5 个既有文件被改 → `src/setparam.f90`、`src/set_module.f90`、`src/prog/main.F90` **未被触碰**

**PLAN 要求但缺失的文件**

| 缺失文件 | 说明 |
|---|---|
| `landscape_api.f90` | 对外 API |
| `landscape_driver.f90` | 任务驱动 |
| `tasks/sp.f90`、`tasks/opt.f90` | 任务实现 |
| `types/conv.f90`、`types/log.f90` | 收敛报告 / 日志（`writeMolecule` 的正确归属地） |
| `types/hessian.f90` | **model Hessian provider（M1 交付物）** |
| `optimize/cg.f90` | **PLAN §9.2 列为 M1** |
| `optimize/trust.f90` | 可接受（trust 逻辑内联进 `rfo.f90`） |

**为什么是问题**
套件无法从 xtb 触发，M0 验收 #4（`xtb --help` 不破）与 M1 验收
（`xtb h2o.xyz --lopt --lopt-engine lbfgs`）都无法执行；BFGS/RFO 只能拿单位阵当初始 Hessian
（PLAN D3 要求 `model_hessian` 初猜），真实分子上 RFO 起步会很差；`testpot.f90` 也是
`libxtb` 里的死代码。

**最小修复**：补 `landscape_api.f90` + `tasks/sp.f90` + `tasks/opt.f90` 薄壳，
以及 §12 的 3 处既有文件改动（约 5 行 `setparam`/`set_module` + ~28 行 `main.F90`），
**或者**由所有者把 M0 定义改为「无 API 层」。

### H3 — 测试套件无失败路径，且两个核心算法不可证伪

**失败路径覆盖 = 0**：全 5 个测试文件没有一处构造 `fail=.true.`、无 SCF 不收敛、无奇异常、
无 `max_steps=0`、无 NaN、无 `landscape_rfo_step` 的 `trust<=0` / 无下降步失败、
无 line search 出界失败、无 `stagnated`/`max_iter` 终止、无 `write_files` 打开失败。
`landscape_optimize_model` 的 `if (.not. allocated(xfinal))` 分支（`driver.f90:157-163`）无测试。

**方向类 bug 被驱动的 SD 兜底掩盖**：
- `driver.f90:255/257/260`（ok/fail → `-g`）与 `:310-325`（线搜索失败 → SD 重试）
- 若把 L-BFGS 两循环写反（返回上坡方向），`line_search.f90:95-96` 的 `slope>=0 → fail` 会触发，
  驱动自动退回 SD 并**照常收敛**，测试全绿
- 而 `history_method`（PLAN §5.4）已被删掉，**没有任何计数器/断言**能发现
  「准牛顿方向从未被使用」

**证据**：`test_landscape_optimize_math.f90:174-176`（`lbfgs-vs-bfgs`）只做两条独立的
`converged + E_err<1e-8`，没有互相比较、没有断言 `n_steps`；DIIS 无任何「外推被使用」的断言
（把 `diis_direction` 改成立即 `return`，`test_harmonic` 仍会因 SD 兜底通过）。

**最小修复**
1. L-BFGS 固定历史的方向复现单测（手算 `-H g` 参考值，可同时钉死二循环顺序、`gamma`、覆盖最老）
2. DIIS 系数和为 1 的单测
3. 每个算法加「fallback 未触发」计数断言
4. 一个 `fail=.true.` 的注入路径测试

---

## 3. MEDIUM 问题

### M1 — 死设置 + 行为被硬编码抹掉

| 设置 | 位置 | 状态 |
|---|---|---|
| `line_search` | `settings.f90:159` | 从不读取；Armijo 永远开启（`driver.f90:297/310/318`） |
| `engine%hess_acc` | `settings.f90:133` | 从不读取；provider 自己用 `sccacc=0.3`（`engine.f90:156`） |
| `THessianSettings%odlr` | `engine.f90:142`、`:475` | 硬编码 `.false.`，ODLR 路径永远不可达 |
| `recalc`（PLAN §5.3.4，值 1） | 无 | RFO 只在 `driver.f90:220` 算一次 Hessian，之后纯更新；与 PLAN「每步重算」不符 |
| `curvature`、`evals_eps`、`mu_margin`、`max_bisect_it`、`diis_store_every`、`diis_min_snapshots`、`sd_*`、`cg_*`、`hessian_source`、`level` | 无 | 缺失（值相同的部分被硬编码在 `lbfgs.f90:112`、`rfo.f90:53-55`、`diis.f90` type 默认里） |

**最小修复**：能接线的接线（`line_search`、`hess_acc`、`odlr`、`recalc`），不能接线的删掉。
特别注意 `test_landscape_settings.f90:131/147/152` **正在为这三个死字段背书**，
制造「测试断言存在 = 功能存在」的假象。

### M2 — 用 `env%check` 当「上一次调用是否失败」的探针 → strict 模式下静默降级

**证据**：`rfo.f90:92`、`bfgs.f90:117`、`diis.f90:159` 均为
`call mctc_*; call env%check(failed); if (failed) …`。
而 `type/environment.f90:162-172` 的 `check` 是**累积**语义：
`terminate = any(self%log(:self%nLog)%error)`；`warning` 在 strict 下以 `error` 位写入
（`environment.f90:341-344`）。

**后果**：`--strict` 下任何一次早先的 warning（例如 `driver.f90:226` 的
"initial Hessian unavailable"）会让之后**每一次** `mctc_syev` 都被判为失败 →
`rfo_step` 永远 `fail` → 每步退回 `-g`（**RFO 实际变 SD**），BFGS 退回最速下降
（`bfgs.f90:118-121`）。这属于「静默换算法」。

**最小修复**：调用前记录 `env%nLog`，只看新增条目；或把 `mctc_syev` 的 `info` 暴露出来判断。

### M3 — 层次边界违规（PLAN §4.2 规则 1）

**证据**：`optimize/driver.f90:40-45` `use xtb_mctc_filetypes / xtb_io_writer / xtb_type_molecule /
xtb_type_restart / xtb_type_calculator`。PLAN 规定 `optimize/**` **不得** `use xtb_type_molecule`，
且 `writeMolecule` 只能出现在 `types/log.f90`、xtb 私有类型只能出现在 `types/engine.f90`；
任务 driver 应在 `tasks/opt.f90`。现在「引擎 backed model」也被复制到 optimize 层（`driver.f90:70-88`）。

**后果**：M2–M7 每加一个任务都会继续污染该层；`types/conv.f90`/`types/log.f90` 的复用点不存在。

**最小修复**：把 `landscape_optimize` / `landscape_engine_model` / `write_landscape_files`
移到 `tasks/opt.f90`（+ `types/log.f90`），`optimize/driver.f90` 只保留纯数学内核。

### M4 — `remove_rotation` 没有帧间对齐，特征向量符号/排序会镜像或交换坐标

**证据**：`coords.f90:347-362`。做了两件事：每列取最大分量变正（`:350-355`）、`det<0` 时翻第三列
（`:356-359`）；**没有**与前一帧/参考帧做任何对齐。头注释 `coords.f90:45-49` 断言
「degenerate moments of inertia therefore yield a reproducible rotation」——**只在「同一输入」
意义下成立，跨帧不成立**。

**后果**：`mctc_syev` 在**简并主惯量**（线性分子、对称陀螺、原子团簇）时返回的是简并子空间的
某个正交基，符号修正无法消除该子空间内的任意旋转/轴序交换；两个只差一点点的构型可能落到
互成镜像/置换的两个主轴系 → 坐标不连续、Hessian 与模式无法跨帧比较。

**现状与紧迫性**：M1 代码里**没有任何调用**（只有测试调用），所以现在不阻断；
但 PLAN §4.2 把 `coords/cartesian.f90` 定位为 NEB/IRC 的对齐工具，**M5/M6 之前必须修**。

**最小修复**：签名加 `xyz_ref`，用 Kabsch（或按特征值排序 + 逐轴与参考帧符号比较）对齐；
测试加「旋转后的同一分子 → 同一坐标系」与「线性/对称陀螺」两个用例。

### M5 — GDIIS 正则化被写成绝对量而非相对量

**证据**：`diis.f90:146` `reg = self%regularization*max(dscale, 1.0_wp)`，
`dscale = max|g_i|²`。梯度模永远 < 1 Ha/bohr（更别说平方），所以 `max(...)=1` 生效 →
`reg ≡ 1e-10` 绝对量；收敛末期 |g|~1e-4 时 `dscale~1e-8`，`reg/B ~ 1e-2`（1% 相对正则）。

**后果**：与头注释「Relative Tikhonov regularisation」及 PLAN §5.3.4 的「1e-10 相对」不符；
近似收敛时系数被压平（趋近平均几何），外推效果变差（有 Armijo 兜底所以不致命）。

**最小修复**：`reg = self%regularization*max(dscale, tiny(1.0_wp))`（必要时再加极小绝对下限）。

### M6 — `testpot.f90`（351 行）被编进 `libxtb`

**证据**：`src/landscape/CMakeLists.txt:24` 与 `meson.build:22` 都列出 `engine/testpot.f90`；
PLAN §8.1 明确写「用 `test/unit/landscape_*.f90`（测试内定义的 extends 引擎 + 内置解析势）」，
§11 也强调不加死代码。

**最小修复**：移到 `test/unit/` 并加入 tester 的源文件列表。

### M7 — `update_bofill` 可能「未做任何更新却报 `ok=.true.`」

**证据**：`hessian_update.f90:196-215`：当 `|s·u|<=guard_su` **且** `s·B s<=0` 时 SR1 项被跳过、
MS 项也被跳过（`:211` 的条件），但 `:216` 仍无条件 `ok = .true.`；调用方
（`bfgs.f90:150-152`、`driver.f90:336`）据此认为历史已更新。

---

## 4. LOW（报备，不阻断）

| 编号 | 问题 |
|---|---|
| L1 | `max_displ` 对 RFO 不生效（`driver.f90:270` 的 `.not. use_trust`），默认 `trust_max=1.8897` > `max_displ=0.37795`，RFO 单步可达文档值的 5 倍（`settings.f90:148` 注释失真） |
| L2 | `results.f90:200-207` 把 `delta_e*autokcal` 打进表格，**无表头也无单位标注**，其余列全是 a.u. |
| L3 | `result%n_eval` 语义两端不一致：`driver.f90:143` 覆盖为 engine 的 **cache miss** 计数，而 `finish()` 存的是**全部**评价次数（含 cache hit） |
| L4 | `coords.f90:226/250` 的 `smass` 无 `source=` 初值；`sqrt(mass(iat))` 对非法原子序（mass=0）会 Inf，无守卫 |
| L5 | 线搜索无曲率（Wolfe）条件（`line_search.f90:99-121`，设计如此），等价于把曲率质量完全押在 `lbfgs.f90:106-110` 的 push 过滤上 |
| L6 | 缓存键只有 `xyz`+`n`（`engine.f90:376-383`）：`mol%at/chrg/uhf` 或 `ctrl%etemp/acc` 改变而坐标逐位相同时会返回过期值 |
| L7 | `engine_get_xyz` 返回的是**缓存**而非当前几何（`engine.f90:331-340`），首次评价前返回 `(3,0)`，与 PLAN §5.1 语义不同 |
| L8 | 容差：`test_landscape_settings.f90:236-244` 对 ~3e-5 的量用绝对 `thr=1e-18`；`test_landscape_optimize_math.f90:113` 在 `loose` 档下要求几何误差 <2e-3 bohr —— 该断言不由收敛判据蕴含，偏脆 |
| L9 | 被拒绝的步把 `step=0,de=0` 送进 `is_converged`（`driver.f90:341-347` → `settings.f90:250-259`），使两个位移判据**恒真**：收敛只能由梯度判据决定 |
| L10 | 新增 `medium/extraloose/extratight` 别名（`settings.f90:270-300`），与 PLAN §5.3.1 差异表里**明确反对**「medium≈loose 一一对应会造成误导」的理由相矛盾 |

---

## 5. 复核者独立验证过的正面结论（原文摘录）

1. **L-BFGS 两循环逐行正确**（`lbfgs.f90:156-176`）：存储索引随 `nstore` 递增 = 越新越大
   （`push` 在 `:115-121` 追加、满时把 `2..m` 左移），第一循环 `i=nstore..1`（新→旧）、
   第二循环 `i=1..nstore`（旧→新）、`gamma=s·y/y·y` 用**最新**对（`:162-164`）、`d=-q`（`:176`）、
   `ρ=1/(s·y)`（`:123`）—— 与 Nocedal & Wright Alg. 7.4 **完全一致**。
2. **四个更新的公式与守卫**（`hessian_update.f90`）：BFGS `ybar=θy+(1-θ)Bs`、
   `θ=0.8 s·Bs/(s·Bs-s·y)`、`B+=ybar ybarᵀ/(ybar·s) - Bs(Bs)ᵀ/(s·Bs)`（`:142-155`）；
   SR1 跳过 `|s·u|<=1e-8|s||u|`（`:170-174`）；Bofill `φ=(s·u)²/((s·u)²+(s·y)²)`（`:195-216`）；
   Powell-PSB（`:250-256`）。**四个更新后都调用 `symmetrize_hessian`**
   （`:154/:178/:217/:257`）。无除零、无未定义行为。
3. **RFO**（`rfo.f90`）：`{w_i}` 抬升后（`:105-107`）在 `(-∞, min w)` 上 `|d(λ)|` 严格单调递减
   （`rfo_step_norm:204-216`），bracketing（`:126-143`，上限 200）+ 60 次二分（`:145-154`）
   **必收敛**；trust 有 `[trust_min, trust_max]` 双端钳位（`:186-192`），
   **不存在收缩到 0 或爆炸的路径**。
4. **线搜索**：`c1=1e-4`（`:84`，在合理区间），回溯 1/2、上限 `max_backtrack=10`，
   `alpha_min = sqrt(eps)*max(alpha,1)`（`:86-87`）。**不会「无进展却声称成功」**。
5. **缓存**（`engine.f90:376-383`）：命中判据是 `cache_valid` + `allocated` + shape 匹配 +
   `all(mol%xyz == cache_xyz)`（**全部元素、逐位**）；命中时 `n_eval` 不增（`:417` 只在 miss 时 +1）、
   `n_cache_hit` 单独计数（`:388`）→ 语义自洽。缓存是 `source=` 深拷贝（`:421-424`），**无指针别名**。
6. **编译级符号/接口**：`singlepoint` 15 实参与 `src/single.f90:41-58` 形参逐个对应；
   `calc%hessian` 的位置实参到 `7th=dipgrad`、`polgrad` 是有名可选（`src/type/calculator.f90:103-152`）；
   `mctc_syev`/`mctc_getrf`/`mctc_getrs` 可解析；`fileType%xyz` + `writeMolecule` 关键字与
   `src/io/writer.f90:36-50` 一致。
7. **module 级可变量 = 0**（独立确认了主控的初查）。
8. **并行/生命周期**：树内 `!$omp`/`omp_`/`random_number`/`stop`/`error stop` **零命中**；
   `landscape_engine_model` 是模块私有类型，三个 pointer 分量只指向本地 `target`，**无悬垂**。
9. **单位**：内部全 a.u.，唯一混入的是打印层的 `autokcal`（L2）与 testpot 里 Müller–Brown 的
   `kcaltoau`（已注明）；无 eV、无 Å。
10. **D2 无越界 / D3 无反向依赖**（复核者独立 grep 验证）。
11. **构建与测试注册正确**：CMake 的 `string(MAKE_C_IDENTIFIER)` → `test_landscape_hessian_update.f90`
    与 meson 的 `t.underscorify()` 映射规则一致。

---

## 6. 复核者列出的「不确定项」（需实验，只读工具集无法判定）

1. **能否编译**：复核者工具集只读且无 shell → 已在 §7 由主控补做。
2. **测试收敛步数与墙钟**：`test_muller_brown`（20000 步 × 5 算法 × 2 basin）、
   `test_rosenbrock`（5000 步 × 4 算法）、`test_gfn2` 的实际耗时。
3. **`env%check` 累积语义在具体调用序列下是否真的会误判**（M2）。
4. **`remove_rotation` 的镜像是否在真实分子上出现**（M4）—— M1 无调用点，当前不可达。
5. **GFN2 侧 `restart=.true.` 与 `p_restart_off` 的差异量级**（H1）—— 已由主控在
   `07-*.md` 中量化为 `3.92e-07 Eh/bohr`。
6. **测试是否会在 CWD 留下 `landscape_unittest*.xyz/.trj` 影响后续 ctest**。

---

# 主控验证附录

## A. 主控补做的构建与测试（复核者无法执行的部分）

复核者在「不确定项 1」中要求：
> 请在 supervisor 侧运行：`cmake -S . -B /tmp/xtb-build-ls -DWITH_CPCMX=OFF -DCMAKE_BUILD_TYPE=Release && cmake --build ... && ctest --test-dir ... -R landscape`

**主控执行结果：**

```
$ cmake --build /tmp/xtb-land/build -j
[ 89%] Built target lib-xtb-static
[ 89%] Built target lib-xtb-shared
[ 91%] Built target xtb-exe
[ 99%] Built target xtb-tester
[100%] Built target xtb_tests_capi

$ ctest --test-dir /tmp/xtb-land/build -R landscape
1/5 Test #52: xtb/landscape-settings ...........   Passed    0.00 sec
2/5 Test #53: xtb/landscape-coords .............   Passed    0.10 sec
3/5 Test #54: xtb/landscape-hessian-update .....   Passed    0.00 sec
4/5 Test #55: xtb/landscape-optimize-math ......   Passed    0.10 sec
5/5 Test #56: xtb/landscape-optimize-xtb .......   Passed    4.63 sec
100% tests passed, 0 tests failed out of 5
Total Test time (real) =   4.83 sec
```

**28 个用例全部通过**（用例级明细见 `06-m0-m1-implementation-report.md` §3）。
→ **复核者「不确定项 1」已消解：代码可编译、测试可运行且全绿。**
→ 复核者的编译级静态核对（§5.6）与实跑结果**一致**，增强了其 §5 各项正面结论的可信度。

## B. 主控对复核者关键声明的独立复核

| 声明 | 主控验证命令 | 结果 | 判定 |
|---|---|---|---|
| H1 `restart_mode` 死设置 | `grep -rn "restart_mode" src/` | **全仓库仅 1 处命中**（`settings.f90:129` 声明） | ✅ 确认 |
| H1 engine 无条件传 restart | `grep -n "singlepoint(" src/landscape/engine/engine.f90` | 仅 `:404`，实参含 `.true.` | ✅ 确认 |
| H2 套件是死代码 | `grep -rn "use xtb_landscape" src/ \| grep -v "^src/landscape/" \| wc -l` | **0** | ✅ 确认 |
| H2 无 `p_run_lopt` | `grep -c p_run_lopt src/setparam.f90` | **0** | ✅ 确认 |
| H2 缺失文件 | 逐个 `[ -f ]` 检查 9 个 PLAN 要求文件 | **9/9 全部缺失** | ✅ 确认 |
| M2 `env%check` 累积 | `sed -n '160,175p' src/type/environment.f90` | `terminate = any(self%log(:self%nLog)%error)` | ✅ 确认 |
| H3 `lbfgs-vs-bfgs` 非对比 | 读 `test_landscape_optimize_math.f90:149` 起 | 存在该用例，结构如复核者所述 | ✅ 确认 |
| 主控自测的数值卫生 | 见 `06-*.md` §4 | 真·module 级可变量 **0** | ✅ 与复核者 §5.11 一致 |

## C. 主控与复核者的发现汇合（相互独立、互为印证）

复核者从**代码静态分析**发现 H1：`restart_mode` 是死设置、engine 无条件 warm-start。
主控从**实测实验**发现 F3（`07-*.md` §3）：warm-start 引入 `3.92e-07 Eh/bohr` 的梯度跳变，
足以让 P-RFO 模态跟随失效。

**两条独立路径在同一处汇合** → H1 不仅是文档/契约问题，而是**已被量化证实的 M4 阻断性缺陷**。
其优先级应从 HIGH 提升为**M4 的前置阻塞项**。

---

## 7. 处置决定（主控）

复核结论为「有条件接受」，三条 HIGH 必须先处理。主控决定：

| 项 | 处置 |
|---|---|
| **H1** | **修复**（实现 `wfn_ref` + 三态 restart 策略 + 打印模式）。同时是 M4 的前置阻塞项，且修复方案与 `07-*.md` §3 的设计后果一致 |
| **H2** | **修复**（补 `api/driver/tasks` 外壳 + 3 处既有文件接线），并一并补 `types/hessian.f90`（model Hessian provider）与 `optimize/cg.f90` |
| **H3** | **修复**（方向复现单测 + fallback 计数断言 + 失败路径注入） |
| M1 | 修复（接线 `line_search`/`hess_acc`/`odlr`/`recalc`，删除不可接线字段，并清除测试中为死字段背书的断言） |
| M2 | **必须修复**（正确性缺陷：静默换算法） |
| M3 | 修复（把任务级驱动移出 `optimize/`） |
| M4 | 修复（`remove_rotation` 加 `xyz_ref` + Kabsch 对齐 + 简并惯量测试）—— M5/M6 前置 |
| M5、M7 | 修复（各 1–2 行） |
| M6 | 修复（把 `testpot.f90` 移到 `test/unit/`） |
| L1–L10 | 按成本择要修复；L2/L3/L7/L9 建议一并处理（语义正确性） |
| 复核者不确定项 2–6 | 由修复轮的测试与实验逐条关闭 |
