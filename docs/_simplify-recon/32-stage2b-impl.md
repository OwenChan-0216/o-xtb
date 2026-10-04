# 32 — 阶段 2b 实施报告：§6.3 的「统一规范名」缺口旗标

> 基线 `3f155cc`（工作树干净），本报告描述的是**未提交**的工作树变更。
> 权威设计：`docs/_simplify-recon/11-cli-redesign.md`（阶段 1 = `f5b070f`，阶段 2 = `0406baf`）。
> 构建：`/tmp/xtb-p2b/build`（新建，`-O2 -DNDEBUG`、`WITH_TBLITE=OFF`、`WITH_CPCMX=OFF`、`WITH_TESTS=ON`）。
> 全部 xtb/ctest 调用 `OMP_NUM_THREADS=1`。**未提交 git**。

## 0. 摘要

| 项 | 值 |
|---|---|
| 新增拼写 | **10 个**（7 个缺口旗标 + 3 个规范名） |
| `--help` 集合 S | `S(main) = S(help) = 135`，**差集 0**（两个 dialect；阶段 2 后为 125） |
| 新 ctest target | **4 个**（`test/unit/CMakeLists.txt` 的 `add_test` 116 → 120） |
| ctest 总数 | 201 → **205**；`ctest -R landscape` **125/125 passed**（40.58 s） |
| 回归子集 | `-R 'Singlepoint\|GFN\|model-hessian\|optimizer\|Argparser\|CAPI'` **12/12 passed**（0.29 s） |
| 注入实验 | **5 个**（E1..E5），全部在**消费点**，真实输出见 §4 |
| 别名机制 | 复用阶段 2 的 `*_source` 冲突状态 + 共享 setter（`set_landscape_hess_step`），未另造一套 |
| 核心层改动 | `src/type\|xtb\|mctc\|param\|io\|disp\|coulomb` **0 改动**（`git status` 仅 7 个文件，见 §6） |
| 设计文档 | §6.3 / §7.2 / §7.4 / §9.2 五处标注**已落地**，R40 行补「阶段 2b 已落地」 |

**本阶段未做**（属阶段 3，越界即违约）：`--opt`/`--ohess` 改派、§3.8 三条守卫、§3.9 的 4 个遗留文件、
§3.10 的 `--cycles` 映射、§3.10b 档位含 SCF 精度、R42 的测试同步清单。
**未发明** §6.3 之外的旗标（特别地**没有** `--lvib-max-steps`，理由：`--lvib` 无迭代预算语义）。
**未改** `--lscan` 默认双向行为，**未改** `src/landscape/**` 的算法。

---

## 1. 逐旗标表（旗标 / 解析点 / 读取点 / 测试名 / 测试如何变红 / 实测证据）

`解析点` = `src/prog/main.F90` 的 `case` 标签行（**本阶段改动后的行号**）；
`读取点` = 值真正被消费的位置（= 注入实验的位置）。

### A. 完全缺失的 7 个拼写（本节之前 `main.F90` 里 0 命中）

| 新旗标 | 解析点 | 读取点 | 测试名 | 测试如何变红 | 实测证据 |
|---|---|---|---|---|---|
| `--lopt-max-steps N` | `main.F90:2361` → `lset%max_steps`（`settings.f90` 的 `landscape_settings%max_steps`，默认 256） | `src/landscape/optimize/driver.f90:225` `do istep = 1, settings%max_steps` | `xtb/landscape-opt-knobs` | 读取点改回常量（`do istep = 1, 256`）⇒ `a minimisation that exhausts its budget exited 0`（**E4 实测**） | `--lopt-max-steps 1`：回显 `maximum number of steps:  1`、`landscape: maximum number of steps reached`、`converged: F`、`steps: 1`、末能量 `-5.070432957755 Eh`、exit 1；默认 256 步：`converged: T`、`steps: 5`、`-5.070544447778 Eh` |
| `--lopt-hess-step V` | `main.F90:2379` → 共享 setter → `lset%engine%hess_step` | `src/landscape/engine/engine.f90:651` `step_used = self%ctrl%hess_step`（`tasks/opt.f90:277` 不传 `step=`） | `xtb/landscape-opt-knobs` | 读取点改回常量（`step_used = 5.0e-3_wp`）⇒ `--lopt-hess-step did not change the minimisation`（**E1 实测**） | `--lopt-engine rfo --lopt-hessian numerical --lopt-max-steps 2`：默认 `-5.070544447771`，`--lopt-hess-step 0.2` → `-5.070544445800`（默认 0.005） |
| `--lscan-hess-step V` | `main.F90:2685` → 共享 setter → `lsset%engine%hess_step` | 同 `engine.f90:651`（scan 的 rfo 内层器）+ `tasks/scan.f90` 的 provider | `xtb/landscape-scan-knobs` | 同 E1 ⇒ `--lscan-hess-step did not change the scan`（**E1 实测**） | `--lscan-method rfo --lscan-hessian numerical`：`xtbscan.log` md5 默认 `f15bfec1109423a6e0840c2b13ac70ca` → `--lscan-hess-step 0.2` `258b6763cc7645f87412764adeb2dbe5` |
| `--lopt-sccacc V` | `main.F90:2397` → `lset%engine%hess_acc` | **`src/landscape/engine/engine.f90:254` `hp%sccacc = self%ctrl%hess_acc`**（不是任务层参数，见 §5 前提 3） | `xtb/landscape-opt-knobs` | 读取点改回常量（`hp%sccacc = 0.3_wp`）⇒ `--lopt-sccacc did not change the minimisation`（**E5 实测**） | 同一 rfo 配置：默认 `-5.070544447771`，`--lopt-sccacc 10.0` → `-5.070544447751` |
| `--lscan-sccacc V` | `main.F90:2703` → `lsset%engine%hess_acc` | 同 `engine.f90:254` | `xtb/landscape-scan-knobs` | 同 E5 ⇒ `--lscan-sccacc did not change the scan`（**E5 实测**） | `xtbscan.log` md5 `f15bfec1…` → `--lscan-sccacc 10.0` `2721433bbbf64751ba43e2d6461c44bc` |
| `--lopt-restart MODE` | `main.F90:2414` → `lset%engine%restart_mode`（`off`/`pin`/`warm`，大小写不敏感） | `src/landscape/engine/engine.f90:604` `engine_apply_restart` 的 `select case (self%ctrl%restart_mode)` | `xtb/landscape-restart-knobs` | 读取点改回旧行为（`select case (p_landscape_restart_off)`）⇒ `--lopt-restart pin did not change xtb.trj`（**E3 实测**） | engine 读回行 `landscape engine: restart policy     warm`；`pin`/`warm` 的 `xtb.trj` 字节 ≠ `off`（全帧最大坐标差 **1.267e-11 bohr**） |
| `--lvib-restart MODE` | `main.F90:3968` → `lvset%engine%restart_mode` | 同 `engine.f90:604`（数值 Hessian 的位移序列起点，`engine.f90:670`） | `xtb/landscape-restart-knobs` | 同 E3 ⇒ `--lvib-restart pin` 的 `hessian` 与 `off` **逐位同**（E3 实测：`d86ba462…` == `d86ba462…`） | `hessian` md5：`off` `d86ba4621b10f832096132e40fd0d390`，`pin`/`warm` `54ad20a792492a113206e6ca49c80c3c`（重复 `pin` 逐位可复现）；`vibspectrum` 三者相同 |

### B. 3 对规范名 vs 现有拼写（现有拼写保留为别名）

三对共用**同一个共享 setter** `set_landscape_hess_step`（`main.F90:4594-4622`），
状态位是 `landscape_engine_control%hess_step_source`（`settings.f90:342`）——
与阶段 2 的 `algorithm_source`/`method_source` 同一机制，未另造一套。

| 规范名（新增） | 现有拼写（保留） | 解析点 | 读取点 | 测试名 / 断言 | 测试如何变红 |
|---|---|---|---|---|---|
| `--lts-hess-step V` | `--lts-step` | `main.F90:3116` / `main.F90:3135` | `engine.f90:651`（`tasks/ts.f90:563` 的 `call engine%hessian(...)` 不传 `step=`） | `xtb/landscape-hess-step-alias`：`--lts --lts-method prfo`（**收敛运行**），两拼写给 `0.02` ⇒ `xtbts.log` + `xtbts.xyz` **逐位同**，且都与默认不同 | 消费点改回常量（E1）⇒ `alias-ts: --lts-hess-step did not change xtbts.log`（**E1 实测**）；裸 `case` 绕过 setter ⇒ 冲突断言失去触发点 |
| `--lirc-hess-step V` | `--lirc-step-hess` | `main.F90:3814` / `main.F90:3835` | `engine.f90:651`（`tasks/irc.f90:233` 的 `call engine%hessian(...)` 不传 `step=`；另各任务 provider 的 `sccacc=`） | 同上：`--lirc --lirc-method gs --lirc-max-steps 1`，两拼写给 `0.02` ⇒ `irc.log` + `irc_path.xyz` 逐位同且都 ≠ 默认（md5：默认 `e48ad457…`，两拼写 `ec9eef2856e9b941e936c55053e3539a`） | 同上（同一共享 setter/消费点，E1 机制） |
| `--lvib-hess-step V` | `--lvib-step` | `main.F90:3917` / `main.F90:3936` | `vib/numhess.f90:144` 的 `step=settings%engine%hess_step`（**唯一显式传入 `step=` 的调用点**，因此 E1 不影响本对，需 E2） | 同上：`--lvib`，两拼写给 `0.01` ⇒ `hessian` **逐位同**（md5 `c12267a1…`）且 ≠ 默认（`d86ba462…`） | 消费点改回常量（`step=5.0e-3_wp`）⇒ `alias-lvib: --lvib-hess-step did not change hessian`（**E2 实测**；此时「等价」断言仍为绿，见 §5 前提 2） |

**别名语义（三对 + 全部新旗标）实测**：

* **同值等价**：`--lvib-step 0.01 --lvib-hess-step 1.0e-2` → exit 0，回显 `Hessian step:  1.000000E-02 bohr`
  （数值比较，**不是**字符串比较）。
* **异值响亮错误**（点名第二个旗标 + 第一个旗标）：
  ```
  -2- Command line argument parsing failed
  -1- prog_main_parseArguments: conflicting Hessian finite difference steps: --lts-hess-step 1.000000E-02 bohr and --lts-step 2.000000E-02 bohr
  -1- prog_main_parseArguments: conflicting Hessian finite difference steps: --lirc-hess-step 3.000000E-02 bohr and --lirc-step-hess 2.000000E-02 bohr
  -1- prog_main_parseArguments: conflicting Hessian finite difference steps: --lvib-hess-step 2.000000E-02 bohr and --lvib-step 1.000000E-02 bohr
  ```
  三次运行 exit = 1。
* **同一旗标重复 = last-wins**：`--lvib-step 0.01 --lvib-step 0.03` → exit 0，回显 `Hessian step:  3.000000E-02 bohr`。

### C. 缺失参数 / 未知值的错误分支（实测 exit = 1）

```
--lopt --lopt-max-steps      → The --lopt-max-steps flag requires an integer
--lopt --lopt-hess-step      → The --lopt-hess-step flag requires a number
--lopt --lopt-sccacc         → The --lopt-sccacc flag requires a number
--lopt --lopt-restart        → The --lopt-restart flag requires off, pin or warm
--lscan --lscan-hess-step    → The --lscan-hess-step flag requires a number
--lscan --lscan-sccacc       → The --lscan-sccacc flag requires a number
--lvib --lvib-restart        → The --lvib-restart flag requires off, pin or warm
--lvib --lvib-restart bogus  → Unknown landscape restart policy 'bogus'
--lopt --lopt-max-steps abc  → The --lopt-max-steps flag requires an integer
```

---

## 2. 实现（改动清单）

| 文件 | 改动 |
|---|---|
| `src/landscape/types/settings.f90` | `landscape_engine_control` 新增 `character(len=:), allocatable :: hess_step_source`（`:342`，8 行含文档注释）。每个任务持有自己的 engine control，所以同一任务的两个拼写共享它、任务之间不干扰 |
| `src/prog/main.F90` | 10 个新 `case`（行号见 §1）；`use xtb_landscape_settings` 增加 `landscape_engine_control`；新共享 setter `set_landscape_hess_step`（`:4594`）；`--lscan-restart`/`--lts-restart`/`--lirc-restart` 三个既有分支**未动**（无别名 ⇒ 无冲突可查，保持原样以缩小改动面）。新 `--lopt-restart`/`--lvib-restart` 照抄 `--lscan-restart` 的 `select case (landscape_lowercase(sec))` 三分支写法 |
| `src/xhelp.f90` | 10 个新 `--` 行 + 3 个旧拼写的 `alias of …` 说明（`:315/318/325/329`、`:392/397`、`:508/512`、`:695/700`、`:726/730/737`） |
| `test/unit/landscape_cli_check.py` | 4 个新 mode（`optknobs`/`scanknobs`/`hessstepalias`/`restartknobs`）+ 4 个辅助函数（`knobs_run`/`knobs_file`/`knobs_final_energy`）+ 顶部 mode 清单 |
| `test/unit/CMakeLists.txt` | 4 个 `add_test`（`:3415-3477` 一整块，含注释）+ 4 个测试名加进 `OMP_NUM_THREADS=1` 的 `set_tests_properties` 组 |
| `test/unit/meson.build` | 4 个 `test(...)` 条目（同样的 mode 与 fixture） |
| `docs/_simplify-recon/11-cli-redesign.md` | §6.3（已落地）、§7.2（已落地）、§7.4（已落地）、§9.2 五行 + R40 行 |

**为什么这 4 个测试只有一份实现**：每个测试要跑 3~10 个run并**逐字节比较两个运行的输出文件**，
这正是 `landscape_cli_check.py` 已经承担的角色；CMake 侧用**既有的** `landscape_cli_py.cmake` +
`LANDSCAPE-CLI-PY` 包装器驱动同一个脚本（阶段 2 的 `--method` 系列已经这样做了，
`landscape_e2e_check.py` 是更早的先例），因此两侧不存在"两份逻辑漂移"的风险。

---

## 3. 测试与注册

* **新 target（4）**：`xtb/landscape-opt-knobs`、`xtb/landscape-scan-knobs`、
  `xtb/landscape-hess-step-alias`、`xtb/landscape-restart-knobs`；
  运行时间 0.23 / 0.13 / 0.41 / 0.17 s（合计 0.94 s）。
* **注册三处**：`test/unit/CMakeLists.txt`（`add_test` + 环境组）、`test/unit/meson.build`、
  `landscape_cli_check.py` 的 mode 分派（+ 顶部 usage 清单）。
* **测试名唯一性**：
  `grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d` → **空**；
  `grep -oE "^test\('[^']+'" test/unit/meson.build | sort | uniq -d` → **空**。
* **计数**：`ctest -R landscape` **125/125**（`add_test` 116 → 120；ctest 总数 201 → 205）；
  回归子集 12/12。**未跑全量 ctest**。
* 本机**无 meson/ninja**，`meson.build` 的两处新条目**未被执行验证**（仅按既有条目逐字同构书写）。

---

## 4. 注入实验（消费点，真实输出）

注入方式：`cp` 原文件 → `sed` 单行突变 → `cmake --build /tmp/xtb-p2b/build -j8` → 跑测试 → `cp` 还原 →
重新构建 → 复跑变绿。**所有突变已还原**（`git diff --stat` 见 §6）。

### E1 — `src/landscape/engine/engine.f90:651`：`step_used = self%ctrl%hess_step` → `step_used = 5.0e-3_wp`

```
FAIL: --lopt-hess-step did not change the minimisation          (optknobs exit=120)
FAIL: --lscan-hess-step did not change the scan                 (scanknobs exit=1)
FAIL: alias-ts: --lts-hess-step did not change xtbts.log        (hessstepalias exit=1)
```

⇒ 一次突变同时打红 **3 个 target**（`--lopt-hess-step`、`--lscan-hess-step`、`--lts-hess-step`
的生效断言），且证明 `tasks/opt.f90:277` 与 `tasks/ts.f90` 的确认 Hessian 确实走
`engine%hessian`（不传 `step=`）。

### E2 — `src/landscape/vib/numhess.f90:144`：`step=settings%engine%hess_step` → `step=5.0e-3_wp`

```
FAIL: alias-lvib: --lvib-hess-step did not change hessian       (hessstepalias exit=1)
```

⇒ `--lvib-hess-step`/`--lvib-step` 的生效断言变红；**注意此时「两拼写等价」断言仍是绿的**
（两个拼写都无效 ⇒ 输出仍然相同）。这是"只有等价断言不够、必须同时断言生效"的实测依据。

### E3 — `src/landscape/engine/engine.f90:604`：`select case (self%ctrl%restart_mode)` → `select case (p_landscape_restart_off)`

```
FAIL: --lopt-restart pin did not change xtb.trj                (restartknobs exit=1)
# 直接核对剩下的一半：
$ cmp injv_off/hessian injv_pin/hessian   → 相同（md5 d86ba462… == d86ba462…）
```

⇒ 消费点失效时，**回显断言仍然绿**（settings 字段照样被写入），只有字节比较发现它 ——
这就是该测试同时断言"engine 读回行 + 结果改变"两半的原因。

### E4 — `src/landscape/optimize/driver.f90:225`：`do istep = 1, settings%max_steps` → `do istep = 1, 256`

```
FAIL: a minimisation that exhausts its budget exited 0         (optknobs exit=1)
# 注入后的运行：回显 "maximum number of steps:  1"，但仍然
#   "landscape: converged" / "steps:          5" / "final energy: -5.070544447778 Eh" / exit 0
```

⇒ 旗标"看似生效"（回显 1）而预算没有生效时，测试响亮失败。

### E5 — `src/landscape/engine/engine.f90:254`：`hp%sccacc = self%ctrl%hess_acc` → `hp%sccacc = 0.3_wp`

```
# 先注入任务层参数（tasks/opt.f90:134 与 tasks/scan.f90:176 的 sccacc=settings%engine%hess_acc → 0.3_wp）：
optknobs exit=0 ; scanknobs exit=0      ← 不变红（原因见 §5 前提 3）
# 再注入真正的消费点 engine.f90:254：
FAIL: --lopt-sccacc did not change the minimisation            (optknobs exit=120)
FAIL: --lscan-sccacc did not change the scan                   (scanknobs exit=1)
```

⇒ `--lopt/--lscan-sccacc` 的生效断言可证伪，且**消费点是 engine 层而不是任务层参数**。

---

## 5. 被本阶段证伪的前提（重要：这些都是任务书/设计/AGENTS 里的静态想法）

1. **任务书建议的 `--lopt-sccacc 10.0` vs 默认 0.3 ⇒ 能量改变，在默认引擎下不成立。**
   实测 `--lopt --lopt-sccacc 10.0` 与默认**末能量逐位相同**（`-5.070544447778 Eh`）：
   默认 `lbfgs` **不建 Hessian**（`landscape engine: Hessians 0`），`hess_acc` 无人消费。
   同理 `--lopt-hess-step`。⇒ 两个测试都必须配 `--l-*-engine rfo --l-*-hessian numerical`。
2. **「restart 改变可观测结果」的观测量不是末能量。** 实测 `--lopt-restart off|pin|warm`
   的 `final energy` **12 位小数完全相同**；真正可观测的差异在 `xtb.trj`（全帧最大坐标差
   **1.267e-11 bohr**，重复运行的同一模式逐位可复现）与 `--lvib` 的 `hessian` 文件字节。
   AGENTS.md §6.2 的"warm 重启引入 3.9e-07 Eh/bohr 梯度跳变"在这个 fixture 上**不能**用作断言。
3. **`sccacc=` 的任务层参数是死参。** `tasks/opt.f90:134` 等把 `sccacc=settings%engine%hess_acc`
   传进 provider 工厂，但 `engine%set_hessian_provider` → `set_numerical_accuracy`
   （`engine.f90:254`）在挂接时用 `self%ctrl%hess_acc` **覆盖**它；在任务层注入常量 `0.3`
   两个测试都**不变红**（E5 前半步，实测）。真正的消费点只有 `engine.f90:254`。
   （**未修**：属 `src/landscape/**`，本阶段只做 CLI 暴露；此处登记为观察。）
4. **`--lts-restart` 与 `--lscan/--lirc-restart` 的未知值消息本来就不同**：
   `--lts-restart bogus` 报 `The --lts-restart flag requires off, pin or warm`（旧写法），
   而 lscan/lirc 报 `Unknown landscape restart policy 'bogus'`。两个新 flag 沿用后者
   （3 个既有 restart 里 2 个是后者）；**没有统一既有措辞**（会改既有输出文本，属另一个改动）。
5. **设计 §9.2 为这些旗标点名的测试名（`xtb/landscape-opt-max-steps` 等）本轮不存在，
   也没有按名字落地**：实际用 4 个分组 target（一个 target 覆盖同一任务的多个旋钮，
   因为每个旋钮的断言都只需要同一族运行的差分）。设计表已改为**实际测试名**。
6. **设计 §9.2 为 `--lts-step`/`--lvib-step`/`--lirc-step-hess` 引用的行号已过时**
   （`main.F90:2956/3714/3634` → 现为 `3135/3936/3835`），本阶段一并订正。

---

## 5b. 订正块（阶段 2b 修复轮 T4；**以 `33-stage2b-validation.md` 的实测为准**）

> **留痕纪律**：下面三处原文**不删**，以本节为权威订正。依据均为独立验证报告 `33-stage2b-validation.md`
> 的 F1/F2/F4（本轮未重跑，直接引用其原文命令与输出），并已在 `11-cli-redesign.md` 的 R43 行登记。

1. **F1 — 上节前提 4 的论证方向是反的（事实错误）。**
   原文称「`--lts-restart` 与 `--lscan/--lirc-restart` 的未知值消息本来就不同 …… 而 lscan/lirc 报
   `Unknown landscape restart policy`」。**实测**（报告 33 §10 F1，完整参数集
   `--lirc --lirc-method gs --lirc-max-steps 1 --lirc-restart bogus`）`--lirc-restart` 报的是
   **`The --lirc-restart flag requires off, pin or warm`**（旧措辞）。正确分布是：
   `--lscan-restart` 用**新**措辞（1/3），`--lts-restart` 与 `--lirc-restart` 用**旧**措辞（2/3）。
   ⇒ 新旗标（`--lopt/--lvib-restart`）采纳的是**少数派**措辞，原文「3 个既有 restart 里 2 个是后者」的
   依据**作废**。结论（有意不统一既有措辞）仍成立，但依据改为本节。
2. **F2 — 数字只对一半成立（不精确）。**
   原文 A6 行把 `1.267e-11 bohr` 同时挂在 `pin` 和 `warm` 上。**实测**：
   `max|off-pin| = 1.2670e-11`，而 `max|off-warm| = max|pin-warm| = 1.2164e-06`（**大 5 个数量级**）。
   两者不是同一个量级，不得合并叙述；上节前提 2 的结论（restart 的可观测量不是末能量）不受影响。
3. **F4 — `--lopt-sccacc` 的能量证据弱到打印末位（证据脆弱）。**
   原文以末能量差作为生效证据：`--lopt-sccacc 10.0` 只差 **2.0e-11 Eh**（`final energy` 12 位小数的末位），
   `--lopt-hess-step 0.2` 为 1.97e-9 Eh。**更强的观测量已实测**：第一步梯度范数
   `1.773788E-04 → 2.069108E-04`（**16 %**），且 `xtb.trj` 第 8 行第 381 字节起不同。
   ⇒ 证据强度应以梯度范数/轨迹字节为准；能量差仅作辅助。（测试本身在
   `xtb/landscape-opt-knobs` 中仍用末能量比较，**未改**；本订正只影响报告的论据强度叙述。）

---

## 6. 集合 S 检查、工作树状态

```
$ python3 test/unit/landscape_help_check.py src/prog/main.F90 src/xhelp.f90
dialect A: S(main) = 135, S(help) = 135, difference = 0
dialect A: S: 0 differences
dialect B: S(main) = 135, S(help) = 135, difference = 0
dialect B: S: 0 differences
PASS: set S is documented by `--help` in both dialects
```
（阶段 2 后为 125/125 ⇒ 本阶段新增 10 个拼写全部有 help 行；`N` 集合计数 30/4 与 34/6 未变。）

```
$ git status --short
 M docs/_simplify-recon/11-cli-redesign.md
 M src/landscape/types/settings.f90
 M src/prog/main.F90
 M src/xhelp.f90
 M test/unit/CMakeLists.txt
 M test/unit/landscape_cli_check.py
 M test/unit/meson.build
?? p2b-workflow.js        ← 与本阶段无关的既有未跟踪文件（未动）
```
核心层（`src/type|xtb|mctc|param|io|disp|coulomb`）**0 改动**。
**未 `git add`、未 commit**。

---

## 7. 残留风险 / 未完成

| # | 项 | 说明 |
|---|---|---|
| R1 | meson 侧未执行 | 本机无 meson/ninja；`meson.build` 的 4 个条目按既有条目逐字同构，但**没有运行验证** |
| R2 | `--lopt-hess-step`/`--lscan-hess-step` 仅在所有权重引擎下有意义 | 已在 `--help` 写明"used by an algorithm that builds one (rfo, bfgs) - the default lbfgs never does"；`--lvib-*`/`--lts-*`/`--lirc-*` 的同族 help 未加同类限定（避免无谓改动既有文案） |
| R3 | restart 消息措辞不完全统一 | 见 §5 前提 4，**有意未修** |
| R4 | 任务层 `sccacc=` 死参 | 见 §5 前提 3，**有意未修**（属 `src/landscape/**`，超出本阶段范围） |
| R5 | 别名冲突只覆盖 `hess_step` | `--lopt-max-steps`/`--l*-sccacc`/`--l*-restart` 在各自任务内只有**一个**拼写，因此按设计不存在别名对；跨任务同名不存在 |
| R6 | 新增旗标未做"单元级"覆盖 | 4 个 target 全部是 CLI 级（跑真实 GFN2）；`src/landscape` 单元测试未新增（本阶段不改算法，故无新单元语义可测） |

> **订正指针（T3 of `37-stage2b-fix2.md`）**：上表 R2 的原文**保留**（留痕），但其中引述的
> `--help` 原文 —— `used by an algorithm that builds one (rfo, bfgs) - the default lbfgs never does`
> —— **已被删除**：阶段 2b 修复轮的 T3（`35-stage2b-fix.md` 的 §T3 表）实测 `bfgs` **不建**数值 Hessian
> （它只在 `hessian_source == 'model'` 时取初始 Hessian，`Hessians 0`），该文案属**不实陈述**。
> 现行 `--help` 文案见 `src/xhelp.f90` 的 `--lopt-hess-step` / `--lscan-hess-step` 条目：
> `only --lopt-engine rfo builds a numerical Hessian; the other five engines (including the default
> lbfgs) never do, and the value is ignored for --lopt-hessian model or file.`
> 复核见阶段 2b 修复轮的复核报告（**36 号**），本轮的 T1/T2 进一步把"unused"提示改为
> **与引擎 Hessian 计数同源**（`37-stage2b-fix2.md`）—— 所以 R2 里"按任务写死谓词"的做法
> 也不再是结论。
