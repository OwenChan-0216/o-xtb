# 12 — M0+M1 第二轮复核遗留项（R2-01…R2-12 + D3 口径补齐）修复报告

> 修复轮 writer：`worker` subagent。
> 输入：`08-independent-review-m0-m1.md`（第一轮）、`10-m0-m1-fix-round-report.md`（第一轮修复）、
> 主控在第二轮复核中实测/核实的事实清单，以及 `docs/xtb-landscape-PLAN.md`。
> **本文所有结论均以 `cmake --build` + `ctest -R landscape` + 定向 CLI 实测为准。**

---

## 1. 交付规模

| 项 | 本轮改动 |
|---|---|
| 生产代码 | `src/landscape/{engine/engine.f90, types/{hessian,settings,coords,log}.f90, optimize/driver.f90, tasks/opt.f90}` |
| 接线 | `src/prog/main.F90`、`src/xhelp.f90` |
| 测试 | `test/unit/test_landscape_{settings,coords,hessian,optimize_math,optimize_xtb,failure}.f90` + `test/unit/CMakeLists.txt` 的 7 个 CLI 级 `add_test` |
| 文档 | `docs/xtb-landscape-PLAN.md`、`docs/_landscape-recon/10-*.md`、本文件 |

结论：`ctest -R landscape` **17/17 通过**；
`ctest -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'` **12/12 通过**。

---

## 2. 逐项处置

### R2-01 · 必修 · `--lopt` 回写收敛结果 —— ✅ 已修复

`src/prog/main.F90:926-935`：landscape 块在 `run_landscape` 之后把
`lres%energy` / `lres%gnorm` 回写到 `res%e_total` / `res%gnorm`（字段名与既有 ANC 路径
`:894-895` 一致）。`write_energy`（TOTAL ENERGY）与 `xtbout.json` 因此报告收敛几何的能量。

实测（`xtb w.xyz --gfn2 --lopt --norestart`）：

```
          | TOTAL ENERGY               -5.070544447778 Eh   |
# xtbopt.xyz line 2
 energy: -5.070544447778 gnorm: 0.000007606232 xtb: ...
```

两者逐位一致（修复前 stdout 为初始几何的 `-5.070383095219`）。

- 新增 CLI 测试 `xtb/landscape-opt-energy`（`landscape_cli_energy.cmake`）：**断言 TOTAL ENERGY 与
  xtbopt.xyz 的 energy 字符串严格相等**。已做反证：注释掉回写后该测试以
  `TOTAL ENERGY (-5.070383095219) differs from xtbopt.xyz (-5.070544447778)` 变红。

### R2-02 · 必修 · CLI 电子结构设置同步 —— ✅ 已修复（仅 `acc`）

- `src/prog/main.F90:926`：`lset%engine%acc = set%acc`（在 `run_landscape` 之前）。
- `src/landscape/engine/engine.f90:284-288`：`engine_set_calculator` 把 `ctrl%acc` 写进
  `calc%accuracy`，使 `landscape_engine_control%acc` 成为唯一真相
  （`xtb_single::singlepoint` 收到 `acc` 形参但**不转发**，见下）。
- `src/landscape/engine/engine.f90:725-728`：`engine_report` 打印生效的 `SCC accuracy`，
  使「同步是否生效」可从 CLI 直接观察。

实测：

```
$ xtb w.xyz --gfn2 --lopt --acc 0.05 --norestart | grep "SCC accuracy"
 landscape engine: SCC accuracy              0.050000
$ xtb w.xyz --gfn2 --lopt --norestart | grep "SCC accuracy"
 landscape engine: SCC accuracy              1.000000
```

- 新增 CLI 测试 `xtb/landscape-opt-acc`：断言默认 run 报告 `1.000000`、`--acc 0.05` 报告
  `0.050000`，且两次 `xtbopt.xyz` 的 energy/gnorm 行不同。已做反证：注释掉同步后该测试以
  `--acc 0.05 did not reach the engine control (reported 1.000000)` 变红。

**实测结论（写进 PLAN §5.1）**：`src/single.f90:37` 的 `singlepoint` **不转发**
`etemp/maxiter/acc`，只转调 `calc%singlepoint`。因此：

- `etemp` 实测**生效**（`--etemp 5000` → `-5.070544450318`，默认 `-5.070544447778`），
  路径是 `newXTBCalculator` 构造时的 `calc%etemp = set%etemp`；**未改代码**；
- `maxiter` **无 CLI flag**，由 xcontrol `$scc maxiterations=`
  （`src/set_module.f90:1758`）在构造时进入 `calc%maxiter`；**未改代码**；
- 只有 `acc` 在本轮接线。

### R2-03 · 必修 · SCF 不收敛在极小化路径升级 —— ✅ 已修复

`src/landscape/engine/engine.f90:493-499`：计算器分支在
`self%cache_results%converged == .false.` 时 `n_scf_fail++`、`env%warning`、`fail=.true.`，
并且**在该点直接返回，不写缓存**（避免后续 cache hit 复活一个不可用结果）。

**选择 warning 而非 error 的理由（已写入代码注释）**：engine 是库边界，单个位移几何的 SCF
失败未必意味着整条极小化不可用（也避免在 Hessian 序列中硬中止）；是否让整条 run 失败交给任务层。
`src/landscape/tasks/opt.f90:156-161` 在结束时若 `n_scf_fail > 0` 一律 `env%error`，
`src/prog/main.F90` 的 `env%checkpoint` 把它变成非零退出码。

- 新增单元测试 `landscape-optimize-xtb :: scf-non-convergence`：把 `calc%maxiter` 置 1，
  断言 ① `engine%energy_gradient` 返回 `fail=.true.` 且 `n_scf_fail==1`、日志有错误；
  ② `landscape_optimize` 不报告 `converged` 且日志有错误。
- 新增 CLI 测试 `xtb/landscape-scf-failure`：`$scc maxiterations=1` 下退出码非 0 且
  输出**不含** `landscape: converged`。实测 `exit=1`。

> 说明：`maxiter=1` 时 `scf_module` 自身会 `env%error`，因此 CLI 层无法把「landscape 的升级」
> 与「scf 自身的报错」完全分离；engine 侧的升级由上面的单元测试独立覆盖。

### R2-04 · 必修 · `apply_restart` 补 `case default` —— ✅ 已修复

`src/landscape/engine/engine.f90:518-558`：`engine_apply_restart` 增加 `env` 形参
（`energy_gradient` / `hessian` 两处调用点同步更新），未知 `restart_mode` 报
`env%error("unknown landscape restart mode: …")`，不再静默退化为 `warm`。

- 新增单元测试 `landscape-failure :: invalid-restart-mode`：`restart_mode=99` 必须产生 error 记录。

### R2-05 · 必修（文档）· NUL 前缀根因描述 —— ✅ 已修复（并**完成了最小复现**）

- `src/landscape/types/log.f90:85-93`：注释改为只陈述现象与规避手段，不断言根因。
- **最小复现（本仓库内，已实测）**：把 `log.f90` 的 `init(...)` 临时换回 `buffer = mol`，
  两条路径的 `.trj` **字节不同**：

  ```
  # buffer = mol 路径
  O            0.00000000000000 ...
  ^@^@^@^@         0.00000000000000 ...   # atom 2: H -> NUL 前缀
  M-YM-LM->^^         0.93000000000000 ...   # atom 3: H -> 垃圾字节

  # init(...) 路径（当前代码）
  O            0.00000000000000 ...
  H            0.00000000000000 ...
  H            0.93000000000000 ...

  $ cmp trj_copy.trj trj_init.trj
  trj_copy.trj trj_init.trj differ: byte 144, line 4
  ```

  在 `buffer = mol` 之后立即打印，可见 `buffer%sym(1)='O'` 正常，`buffer%sym(2)/%sym(3)`
  已是 NUL/垃圾；`mol%sym` 三个元素全部正常。
- **结论修正**：第二轮「改用 `init` 就消除 NUL 在代码上不成立」的说法与实测**相反**——
  规避手段**有实验依据**，保留。根因仍未定位到具体模块（表象出现在内禀赋值之后；既不是
  `copyMolecule`，也无法仅凭本仓库区分「编译器运行时对 deferred-length character 数组的整体赋值」
  与 mctc-lib 侧字符处理）。已把复现结果补进 `10-*.md §4.1`。

### R2-07 · 必修 · `recalc` 默认值与代价计数 —— ✅ 已修复

- `src/landscape/types/settings.f90:210-215`：`recalc` 默认 1 → 5，注释写明「数值 Hessian
  每次 6N 次单点，`recalc=1` 时 RFO 每步 6N+1 次」。
- `src/landscape/types/hessian.f90:88`：provider 抽象类型新增 `integer :: n_eval = 0`；
  数值 provider 每做一次位移单点 `n_eval++`（`:281,:291`）；模型 provider 恒为 0。
- `src/landscape/engine/engine.f90:621-627`：`engine_hessian` 把 `hp%n_eval` 累加进
  `self%n_eval`，因此 `landscape engine: energy evaluations` 与 `result%n_cache_miss`
  反映真实代价。
- 新增单元测试 `landscape-optimize-xtb :: hessian-cost-accounting`：断言一次
  `engine%hessian` 后 `n_eval` 精确增加 `6N`，随后逐步单调增长；并断言一次 RFO run 的
  `n_cache_miss >= 6N`。实测 GFN2 水（N=3）：`43 single points for 7 steps (18 = 6N)`。

### R2-08 · 择要补测 —— ✅ 已修复

1. `landscape_write_files` 打开失败：`landscape-failure :: write-files-open-failure`
   （prefix 指向不存在目录，断言 error 记录）。
2. `tasks/opt.f90` 的 `x_final` 未分配分支：`landscape-optimize-xtb :: missing-geometry`
   （NaN 起始几何 → 核心不返回几何 → 任务报错）。
3. `coords.f90` 的 `mass_weight_vector` / `mass_unweight_vector` 对 `mass<=0` 加 `env` 守卫
   （与 Hessian 版一致，`:194-235`），并新增单元测试 `landscape-coords :: mass-weight-invalid`
   （覆盖 vector 与 Hessian 四个例程；`getAtomicMass(0) = -1`）。
4. `main.F90` 的缺参数 / 未知算法名 / 未知档位 error 分支：CLI 测试
   `xtb/landscape-engine-missing`、`xtb/landscape-engine-unknown`、`xtb/landscape-level-missing`、
   `xtb/landscape-level-unknown`（均断言非零退出 + 对应 error 文本）。

### R2-10 · 便宜 · help 文本 —— ✅ 已修复

`src/xhelp.f90:274-286`：新增 `--lopt`、`--lopt-engine NAME`、`--lopt-level LEVEL` 三条。

### R2-11 / R2-12 · 状态残留 —— ✅ 已修复

- `engine_set_calculator`（`engine.f90:288-289`）与 `engine_set_model`（`:303`）置
  `ref_valid = .false.`。
- `engine_hvp` 结束（及两条失败早退路径）把 `current_xyz` 还原为调用前的几何
  （`engine.f90:684/697/705`）。
- 数值 Hessian provider 的 `cleanup` 增加 `call chk%copy(wfn_ref)`（`hessian.f90:315`），
  恢复调用前的波函数。

### ★ D3 缺口补齐 · model Hessian 真正接上 —— ✅ 已修复

- `src/landscape/types/hessian.f90:320-372`：`landscape_model_hessian_provider%compute`
  实现为 Lindh-D2 模型 Hessian：复用 `newLindhD2ModelHessian`（`src/model_hessian/lindh.f90:41`）
  与 `set%mhset` 默认力常数（`src/setparam.f90:267-278`），经 `TModelHessian%compute`
  得稠密 Hessian；纯几何、`n_eval=0`、返回前强制对称化。
- `hessian_source='model'` 由 `new_landscape_hessian_provider` 正常构造；
  未识别取值仍报错（不变）。
- 注入：`src/landscape/optimize/driver.f90:162-176`——BFGS 在
  `hessian_source=='model'` 时用 `objective%hessian` → `bfgs%set_hessian` 播种初猜；
  RFO 本就走 `objective%hessian`（初猜即 provider 结果）。

测试（`landscape-optimize-xtb :: model-initial-hessian` 与 `landscape-hessian :: model-hessian`）：

```
① model provider → 有限、零 `n_eval`、严格对称的 Hessian（单元）
② 真实 GFN2 水（stretched/over-bent）步数对比：
   bfgs model seed      6 steps, converged T
   bfgs identity seed   6 steps, converged T
   rfo  model seed      6 steps, converged T
   rfo  numerical seed  7 steps, converged T
③ hessian_source='bogus' 仍报错（`source-selection` 用例）
```

即在所测体系上 **model 初猜不劣于单位阵（BFGS）/数值（RFO）**。

---

## 3. 仍未解决 / 未做（含理由）

| # | 项 | 理由 |
|---|---|---|
| 1 | `hessian_source` **无 CLI flag**，`model` 只能由 API/单元测试选择 | 本轮任务明确只要求把 `--lopt / --lopt-engine / --lopt-level` 加进 help，未授权新增第 4 个 flag；「成功运行」用单元测试 + GFN2 实测数据给出。建议 M2 增加 `--lopt-hessian` |
| 2 | 全量 `ctest` | 任务明令禁止（84 项、单项 mctc-lib/ncoord 156 s），只跑定向子集 |
| 3 | meson 侧新增的 7 个 CLI 测试 | meson 既有 landscape CLI 测试是单个 smoke test；为不在被禁范围内扩大改动，新 CLI 检查只加在 CMake（Fortran 单元用例在两个构建系统下都会跑） |
| 4 | NUL 前缀根因 | 表象可复现且规避有效；根因跨到编译器运行时/mctc-lib，超出允许改动范围，只记录不修 |
| 5 | `etemp` / `maxiter` 的显式接线 | 实测已生效（`calc%etemp` / `calc%maxiter` 在构造期取自 `set%*`），按任务要求**不动** |

---

## 4. 验证命令

```bash
cmake -S /home/owenchan/work_path/coding/fortran/xtb -B /tmp/xtb-land/build \
  -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/xtb-land/build -j
ctest --test-dir /tmp/xtb-land/build --output-on-failure -R landscape
ctest --test-dir /tmp/xtb-land/build --output-on-failure \
  -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
```

结果：`landscape` 17/17 通过；定向子集 12/12 通过。
