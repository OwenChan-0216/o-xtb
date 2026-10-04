# 33 — 阶段 2b 独立验证报告（复跑 + 证伪）

> 角色：**独立验证者**（不是实施者）。被验证对象 = **未提交的工作树**（基线 `3f155cc`，7 个改动文件），
> 实施报告 = `docs/_simplify-recon/32-stage2b-impl.md`。
> 本报告**不采信实施报告的任何结论**，全部命令与输出为本轮实测。**未修改仓库的 `src/` 与 `test/`**。
> 构建：`/tmp/xtb-p2b-val/build`（新建，`-O2 -DNDEBUG`、`WITH_TBLITE=OFF`、`WITH_CPCMX=OFF`、`WITH_TESTS=ON`）；
> 参照二进制：`/tmp/xtb-p2b-ref/`（`git archive HEAD` 解包 → 干净 `3f155cc`）；注入副本：`/tmp/xtb-p2b-inj/`（工作树拷贝）。
> 全部 xtb/ctest 调用 `OMP_NUM_THREADS=1`，只跑 `-R landscape` 与回归子集，**未跑全量 ctest**。

---

## 0. 判定

| 项 | 结果 |
|---|---|
| 构建 | **通过**（exit 0；0 error；37 条 warning **全部来自上游遗留文件 `prmat.f90`**） |
| `ctest -R landscape` | **125/125 通过**（38.39 s；`ctest -N` 总数 205，`add_test` 120） |
| 回归子集 | **12/12 通过**（0.28 s） |
| 集合 S（`--help` 双向） | **135 = 135，差集 0，PASS** |
| 10 个新拼写 | **全部实测生效**（A 组 7 + B 组 3 别名），且**6 个独立注入实验**证明读取点可证伪 |
| 别名语义（同值/异值/重复） | 3 对全部三情形**符合设计 §4.3** |
| BC-4（12 次既有调用逐文件 `cmp`） | **全部逐位相同**（唯一差异是构建期嵌入的 git 哈希，已归一） |
| 边界（核心层 0、无算法改动） | 通过（`src/landscape/types/settings.f90` 有一个 8 行类型字段新增，非算法） |
| **结论** | **通过，可以提交**（无阻塞项；有 2 条 LOW 建议 + 1 处报告事实错误待订正，见 §10） |

---

## 1. 构建

```bash
cmake -S /home/owenchan/work_path/coding/fortran/xtb -B /tmp/xtb-p2b-val/build \
  -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"
cmake --build /tmp/xtb-p2b-val/build -j8
```

```
BUILD_EXIT=0
$ grep -ciE '\berror\b' /tmp/p2b-val-build.log
2          # 两条都只是文件名 mctc/env/error.f90 与 src/mctc/error.f90，不是编译错误
$ grep -iE -B6 'Warning' /tmp/p2b-val-build.log | grep -oE '[^ /]+\.(F90|f90|c|cpp):[0-9]+' | sed 's/:.*//' | sort | uniq -c
     28 prmat.f90      # 上游文件（Fortran 2018 deleted feature: 算术 IF / 共享 DO 终止语句 / PURE 属性不匹配）
```

`-O2` 的 warning 与改动**无关**：全部 37 条来自上游 `prmat.f90`，新代码（`main.F90`/`settings.f90`）零 warning。

---

## 2. 测试与注册

```bash
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p2b-val/build -R landscape
# 100% tests passed, 0 tests failed out of 125   (Total Test time 38.39 s)
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p2b-val/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
# 100% tests passed, 0 tests failed out of 12    (0.28 s)
ctest --test-dir /tmp/xtb-p2b-val/build -N | tail -2
# Total Tests: 205
grep -c 'add_test(' test/unit/CMakeLists.txt          # 120   （报告 32 声称 116 -> 120，一致）
grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d   # 空
grep -oE "^test\('[^']+'" test/unit/meson.build       | sort | uniq -d   # 空
```

4 个新 target 独立列出并各自通过：

```
Test #190: xtb/landscape-opt-knobs
Test #191: xtb/landscape-scan-knobs
Test #192: xtb/landscape-hess-step-alias
Test #193: xtb/landscape-restart-knobs
```

---

## 3. 集合 S（`--help` ↔ 解析器，两个 dialect）

```bash
python3 test/unit/landscape_help_check.py src/prog/main.F90 src/xhelp.f90
# dialect A: S(main) = 135, S(help) = 135, difference = 0
# dialect B: S(main) = 135, S(help) = 135, difference = 0
# PASS: set S is documented by `--help` in both dialects
```

我自己做了一次**集合差分**（不依赖 `--help` 文本，直接 diff `case` 标签）：

```
新增 case 标签（10 个）       删除（0 个）         total 198 -> 208
--lirc-hess-step  --lopt-hess-step  --lopt-max-steps  --lopt-restart  --lopt-sccacc
--lscan-hess-step --lscan-sccacc    --lts-hess-step   --lvib-hess-step --lvib-restart
xhelp.f90 新增 `--` 行：10 条（与上表一一对应）
grep -c -- '--lvib-max-steps' src/prog/main.F90   # 0   （报告 32「未发明表外旗标」属实）
grep -c -- '--lts-project-tr' / '--lts-imag-cutoff' src/prog/main.F90   # 0 / 0（§7.4 第 5 行仍未落地，属实）
```

⇒ **恰好 10 个拼写，既不多也不少，无删除**。

---

## 4. 逐旗标实跑（A 组 7 个）

统一 `--gfn 2 --norestart`，每个组合一个干净目录，`XTBPATH` 指向仓库。

### A1 `--lopt-max-steps`

```
默认 256 : exit=0  maximum number of steps: 256  converged: T  steps: 5  final energy: -5.070544447778 Eh
--lopt-max-steps 1: exit=1  maximum number of steps: 1  converged: F  steps: 1  final energy: -5.070432957755 Eh
                    landscape: maximum number of steps reached
-1- landscape_optimize: landscape minimisation did not converge: maximum number of steps reached
```
**生效**：回显 + 步数 + 收敛位 + 退出码 + 末能量全部改变。

### A2/A4 `--lopt-hess-step` / `--lopt-sccacc`（必须配 `--lopt-engine rfo --lopt-hessian numerical --lopt-max-steps 2`）

```
默认     exit=0  -5.070544447771 Eh
--lopt-hess-step 0.2   exit=0  -5.070544445800 Eh
--lopt-sccacc 10.0     exit=0  -5.070544447751 Eh
```
**月牙注（我自己的加固证据）**：`--lopt-sccacc` 对末能量的影响只有 **2.0e-11 Eh**（≈ 打印位数最后一位），但第一步的梯度范数差
**16 %**：`1.773788E-04 -> 2.069108E-04`，且 `xtb.trj` 在第 8 行第 381 字节起不同。⇒ 见 §10 F4。

**默认引擎下是静默空转（实测）**：
```
--lopt（默认 lbfgs）        landscape engine: Hessians 0   final energy -5.070544447778
--lopt --lopt-hess-step 0.2 landscape engine: Hessians 0   final energy -5.070544447778   （逐位同）
--lopt --lopt-sccacc 10.0   landscape engine: Hessians 0   final energy -5.070544447778   （逐位同）
```
报告 32 §5 前提 1 与 R2 已如实登记该点（help 文本亦写明），但**运行期无任何提示**（残留风险 R2）。

### A3/A5 `--lscan-hess-step` / `--lscan-sccacc`（`--lscan-method rfo --lscan-hessian numerical`）

```
xtbscan.log md5:
  默认                    f15bfec1109423a6e0840c2b13ac70ca
  --lscan-hess-step 0.2   258b6763cc7645f87412764adeb2dbe5
  --lscan-sccacc 10.0     2721433bbbf64751ba43e2d6461c44bc
三点能量（iter:1/2/3）：默认 -5.070420739768 / -5.070543485805 / -5.070420835439
                        hess    -5.070420743892 / -5.070543479522 / -5.070420858803  (1e-8 Eh)
                        sccacc  -5.070420739861 / -5.070543485516 / -5.070420835501  (1e-10 Eh)
```
md5 与报告 32 §1 的三个值**逐位一致**（我独立复算）。

### A6 `--lopt-restart`

```
off   exit=0 xtb.trj 5a92557b3f2e13fcf7a711276ecd3d6f  engine echo: off
pin   exit=0 xtb.trj 37e91fc009427d0fec038f0189b3a88c  engine echo: pin
warm  exit=0 xtb.trj d13309f46af0b1222cc12150dfcc65e2  engine echo: warm
重复 pin（第二次运行）         xtb.trj 37e91fc009427d0fec038f0189b3a88c   ← 逐位可复现
final energy 三种模式：-5.070544447778 Eh（12 位小数完全相同）
坐标差：max|off-pin| = 1.2670e-11 bohr，max|pin-warm| = 1.2164e-06 bohr
```
⇒ `off/pin/warm` 三者产物两两不同；报告 32 §5 前提 2（"观测量不是末能量而是 `xtb.trj`/`hessian`"）实测成立。
（报告写的"pin/warm 的全帧最大坐标差 1.267e-11"只对 **off-vs-pin** 成立，见 §10 F2。）

### A7 `--lvib-restart`

```
hessian md5: off d86ba4621b10f832096132e40fd0d390   pin 54ad20a792492a113206e6ca49c80c3c   warm 54ad20a792492a113206e6ca49c80c3c
vibspectrum: 三者相同 9758bed2863f4e196110b1d3cd80f637
engine echo: off / pin / warm 均正确回读
```
**pin 与 warm 的 `hessian` 逐位相同** —— 报告仅记录了该现象，未解释；我给出机制（§10 F3）。

### 参数缺失 / 非法值（10 个新旗标全测，exit 均为 1）

```
--lopt --lopt-max-steps      -> The --lopt-max-steps flag requires an integer
--lopt --lopt-hess-step      -> The --lopt-hess-step flag requires a number
--lopt --lopt-sccacc         -> The --lopt-sccacc flag requires a number
--lopt --lopt-restart        -> The --lopt-restart flag requires off, pin or warm
--lscan --lscan-hess-step    -> The --lscan-hess-step flag requires a number
--lscan --lscan-sccacc       -> The --lscan-sccacc flag requires a number
--lvib --lvib-restart        -> The --lvib-restart flag requires off, pin or warm
--lts --lts-hess-step        -> The --lts-hess-step flag requires a number
--lirc --lirc-hess-step      -> The --lirc-hess-step flag requires a number
--lvib --lvib-hess-step      -> The --lvib-hess-step flag requires a number
--lopt --lopt-max-steps abc  -> The --lopt-max-steps flag requires an integer
--lopt --lopt-max-steps 1.5  -> The --lopt-max-steps flag requires an integer
--lopt --lopt-restart bogus  -> Unknown landscape restart policy 'bogus'
--lvib --lvib-restart bogus  -> Unknown landscape restart policy 'bogus'
--lopt --lopt-restart PIN    -> exit 0（大小写不敏感，符合阶段 1 的枚举归一）
```
`--lopt-max-steps 0` / `-5` **不校验**（分别得到 `converged: F` + "no step performed"、`landscape minimisation did not converge: no step performed`），
但与既有 `--lscan-max-steps 0` 的行为一致（设计未要求校验）⇒ 不作为缺陷。

---

## 5. 别名语义（B 组 3 对 × 3 情形，我全跑）

| 情形 | `--lts-step`/`--lts-hess-step` | `--lirc-step-hess`/`--lirc-hess-step` | `--lvib-step`/`--lvib-hess-step` |
|---|---|---|---|
| 同值 0.02（两拼写各给一次） | exit 0，`xtbts.log` f13ebd55 / `xtbts.xyz` effe9f67（两者逐位同） | exit 0，`irc.log` ec9eef28 / `irc_path.xyz` f9f2f4dc | exit 0，`hessian` ff083f9d |
| 异值 0.02 vs 0.03 | exit 1 | exit 1 | exit 1 |
| 重复同旗标 0.03 后 0.02 | exit 0，产物 = 0.02 运行（last-wins） | exit 0，同上 | exit 0，`hessian` ff083f9d + 回显 `2.000000E-02` |
| **与默认不同**（证明"不是两个都无效"） | 默认 `52733ac4` ≠ `f13ebd55` | 默认 `e48ad457` ≠ `ec9eef28` | 默认 `d86ba462` ≠ `ff083f9d` |
| 数值等价（`0.01` vs `1.0e-2`） | — | — | exit 0，回显 `1.000000E-02`（数值比较而非字符串） |

冲突消息（点名两个旗标，第二个旗标在句首）：

```
-1- prog_main_parseArguments: conflicting Hessian finite difference steps: --lts-hess-step 3.000000E-02 bohr and --lts-step 2.000000E-02 bohr
-1- prog_main_parseArguments: conflicting Hessian finite difference steps: --lirc-hess-step 3.000000E-02 bohr and --lirc-step-hess 2.000000E-02 bohr
-1- prog_main_parseArguments: conflicting Hessian finite difference steps: --lvib-hess-step 3.000000E-02 bohr and --lvib-step 2.000000E-02 bohr
```

**别名规则在我这里独立通过**；`--lts-step`/`--lirc-step-hess`/`--lvib-step` 三个旧拼写**未改名**（diff 只改函数体，`case` 标签原样保留）。

---

## 6. 独立注入实验（在**我自己的副本** `/tmp/xtb-p2b-inj/` 里做，仓库未动）

| # | 注入点 | 注入内容 | 结果 |
|---|---|---|---|
| I1 | `src/landscape/engine/engine.f90:651` | `step_used = self%ctrl%hess_step` → `5.0e-3_wp` | `opt-knobs` / `scan-knobs` / `hess-step-alias` **3 个红**（`--lopt-hess-step did not change the minimisation`、`--lscan-…did not change the scan`、`alias-ts: --lts-hess-step did not change xtbts.log`） |
| I2 | `src/prog/main.F90:4608`（**共享 setter 的冲突判定**） | `if (ctrl%hess_step_source /= owner .and. ctrl%hess_step /= step)` → `if (.false.)` | `hess-step-alias` 红：`FAIL: the conflict was not reported for --lts`（**实施报告没有做这个注入**，我补上：证伪别名冲突逻辑本身） |
| I3 | `src/landscape/optimize/driver.f90:225` | `do istep = 1, settings%max_steps` → `1, 256` | `opt-knobs` 红：`FAIL: a minimisation that exhausts its budget exited 0` |
| I4 | `src/landscape/tasks/opt.f90:134` + `tasks/scan.f90:176`（**任务层 sccacc 参数**） | `sccacc=settings%engine%hess_acc` → `0.3_wp` | **保持全绿**（`2/2 passed`）⇒ 独立证实"任务层参数是死参"，真实消费点只有 `engine.f90:254` |
| I5 | `src/landscape/engine/engine.f90:254`（真实消费点） | `hp%sccacc = self%ctrl%hess_acc` → `0.3_wp` | `opt-knobs` + `scan-knobs` **2 个红** |
| I6 | `src/landscape/engine/engine.f90:604`（restart 读取点） | `select case (self%ctrl%restart_mode)` → `select case (p_landscape_restart_off)` | `restart-knobs` 红（`--lopt-restart pin did not change xtb.trj`）；**我另做了 lvib 半边的手工核对**：注入后 `--lvib-restart off/pin/warm` 的 `hessian` **都是 d86ba462**（与 off 相同），而 engine 回显仍是 `off/pin/warm` ⇒ `--lvib-restart` 的读取点同样可证伪（实施报告的 E3 只对 `--lopt` 那一半给了测试级证据） |

注入全部还原后：`4/4 passed`；5 个源文件与仓库 `diff -q` **完全相同**。

⇒ **7 个 A 组旗标的消费点全部有可证伪证据**（`--lopt/lscan-hess-step`←I1，`--lopt/lscan-sccacc`←I5，
`--lopt-max-steps`←I3，`--lopt/lvib-restart`←I6，3 个别名←I1/I2）。**没有一个死旋钮**。

---

## 7. BC-4：新增旗标不得改变既有行为（改动前 vs 改动后）

参照 = `git archive HEAD` 的干净 `3f155cc` 构建（`/tmp/xtb-p2b-ref/build/xtb`）。
12 组调用各跑两次（ref / val），**逐文件 `cmp`** + stdout 比对：

```
--lopt 默认 / --lscan angle / --lscan relaxed / --lts prfo / --lirc gs / --lvib / --sp / --hess / --opt
--lts --lts-step 0.02 / --lirc --lirc-step-hess 0.02 / --lvib --lvib-step 0.02   ← 三个被改写的旧拼写
```

结果：**全部输出文件逐位相同**，stdout 逐行多重集相同。

必须**先排除的非确定性**（否则会得到 9 个假红，本项目的既有教训）：

1. **构建期嵌入的 git 哈希**（`xtb: 6.7.1 (3f155cc0…)` vs `(unknown-commit)`）—— 参照树来自 `git archive`，这个差异出现在
   `xtbopt.xyz` / `xtbtopo.mol` / `xtbscan.log` / `xtb.trj` / `irc_*.xyz` 的每一行。归一化 `\(([0-9a-f]{40}|unknown-commit)\)` 之后，**所有文件逐位相同**。
2. 墙钟时间戳（`* started/finished run on …`）、计时块（`x min, y sec (z%)`）、`ratio c/w`、`total power ... (real)`（按时间算的 W）。
3. **stderr/stdout 交错**（`2>&1` 合流 + 缓冲）：`normal termination of xtb`、`Molecule has the following symmetry elements:`、
   `ANC optimizer:`、某一行 normal mode 的行序在两棵树间会移动；**行多重集完全相同**（`sort` 后 `diff` 为空），不是输出内容差异。
4. `random seed`（每次运行的打印值不同，实测不影响任何数值）。

排除上述四类后：**12/12 组「文件逐位 + stdout 多重集」全同 ⇒ BC-4 通过**。

---

## 8. 边界

```
$ git diff --name-only
docs/_simplify-recon/11-cli-redesign.md
src/landscape/types/settings.f90
src/prog/main.F90
src/xhelp.f90
test/unit/CMakeLists.txt
test/unit/landscape_cli_check.py
test/unit/meson.build
```
* 核心层 `src/type|xtb|mctc|param|io|disp|coulomb`：**0 改动** ✓
* `src/landscape/**`：只有 `types/settings.f90` 新增 8 行（`character(len=:), allocatable :: hess_step_source` + 文档注释），
  **算法文件（engine / optimize / saddle / irc / vib / scan / tasks）零改动** ✓（我逐个 `diff -q` 核对过注入副本用到的 5 个文件，与仓库一致）
* 无 `git add`、无 commit、无 staged 文件；工作树状态 = 验证开始时一致 ✓

---

## 9. 与实施报告数字的交叉核对

| 报告 32 的数字 | 我的复算 | 一致? |
|---|---|---|
| `add_test` 116→120；ctest 201→205 | 120；205 | ✓ |
| `S = 135/135`，差集 0 | 135/135，差集 0 | ✓ |
| `--lopt-hess-step 0.2` 末能量 -5.070544445800 | -5.070544445800 | ✓ |
| `--lopt-sccacc 10.0` 末能量 -5.070544447751 | -5.070544447751 | ✓ |
| `xtbscan.log` md5 `f15bfec1…` / `258b6763…` / `2721433b…` | 逐位相同 | ✓ |
| `hessian` md5 `d86ba462…` / `54ad20a7…`；`irc.log` 默认 `e48ad457…`、0.02 `ec9eef28…` | 逐位相同 | ✓ |
| `--lopt-max-steps 1`：`converged: F`、`steps: 1`、exit 1、-5.070432957755 | 同 | ✓ |
| restart：pin 可复现、`pin/warm ≠ off`、末能量 12 位小数相同 | 同 | ✓ |
| E1..E5 的注入机制（消费点） | 我复现 I1/I3/I5 + 新增 I2/I4/I6 | ✓（且更严） |

---

## 10. 证伪清单（我的主要产出：报告 32 说错 / 说漏的地方）

| # | 严重度 | 内容 |
|---|---|---|
| **F1** | **报告事实错误** | 报告 32 §5 前提 4 称「`--lts-restart` 与 `--lscan/--lirc-restart` 的未知值消息本来就不同 …… 而 lscan/lirc 报 `Unknown landscape restart policy`」。**实测 `--lirc-restart bogus` 报的是 `The --lirc-restart flag requires off, pin or warm`**（我用了完整参数集 `--lirc --lirc-method gs --lirc-max-steps 1 --lirc-restart bogus` 复核）。正确分布是：`--lscan-restart` 用新措辞（1/3），`--lts-restart`、`--lirc-restart` 用旧措辞（2/3）。因此新旗标**采纳的是少数派措辞**，报告里"3 个既有 restart 里 2 个是后者"的论证**是反的**。结论（有意不统一既有措辞）仍可接受，但依据必须订正。 |
| **F2** | LOW（数字不精确） | 报告 §1 A6 行把 `1.267e-11 bohr` 同时挂在 `pin` 和 `warm` 上。实测 `max|off-pin| = 1.2670e-11`，而 `max|off-warm| = max|pin-warm| = 1.2164e-06`（**大 5 个数量级**）。两个比较不是同一个量级，不应合并叙述。 |
| **F3** | LOW（说漏：一个模式不可独立观测） | **`--lvib-restart warm` 与 `pin` 的 `hessian` 逐位相同**（md5 `54ad20a7…`）。报告只记录了 md5 相同，没有解释，也没有声明「该模式下 warm 不可区分于 pin」。机制（我读了代码）：`types/hessian.f90:328` `call wfn_ref%copy(chk)` 会在**每个位移点前**把 `chk` 重置为**进入算 Hessian 时的**波函数快照，而 `engine.f90:607`（off）记录的是**冷启动**波函数、`engine.f90:559`（pin）记录的是**未位移收敛**波函数、warm 保留的正是同一个**未位移收敛**波函数 ⇒ warm 与 pin 交给 FD provider 的起点**逐位相同**。所以 `xtb/landscape-restart-knobs` 的 "结果必须改变" 断言对 `--lvib` 只覆盖了 **vs off** 这一半。不是阶段 2b 的缺陷（旗标忠实传递 engine 策略，该行为本来就存在），但报告不应把它当成"每个模式都有独立效果"。 |
| **F4** | LOW（证据脆弱） | `--lopt-sccacc` 的证据强度只有 **2.0e-11 Eh**、`--lopt-hess-step` 为 **1.97e-9 Eh**，都是**打印末位数字级**的差异（`final energy` 12 位小数）。本机能复现，但换 BLAS/编译器时存在"两个运行打出同一串"的风险。同类更强的观测量已存在且我已实测：第一步梯度范数 `1.773788E-04 → 2.069108E-04`（16 %）、`xtb.trj` 字节。建议把这两条断言换成/补上更强的观测量（一句 `knobs_final_energy` 改成读 `xtb.trj` 或第一步 gnorm）。`scanknobs` 因为比较**整文件字节**所以更稳（能量差 1e-8/1e-10 也够），不必改。 |
| **F5** | INFO（说漏：运行期无提示） | 默认引擎（lbfgs）下 `--lopt-hess-step`/`--lopt-sccacc` 是**完全静默**的空转（`Hessians 0`，末能量逐位同）。报告 §5 前提 1 与 R2 已如实登记，`--help` 也写了，但**运行期不告诉用户"这个旋钮在你选的引擎上没被消费"**。与项目在阶段 1 建立的"D 类危险/无效组合要响亮"的取向相比偏弱。非阻塞（可选：加一行 `[NOTICE]` 或在 `engine_report` 里标注 hess_step/hess_acc 未消费）。 |
| **F6** | INFO（阶段 2 消息的连带不精确） | `--method lvib` 与任一 lvib 任务旗标同用时（例如 `--method lvib --lvib-restart warm`，**没有** `--lvib`），得到 `--method lvib cannot be used with --lvib: …`（`main.F90:4217` 按**已选 runtype** `p_run_lvib` 分支），点名的旗标用户根本没写。组合本身非法（结论不变），措辞不精确；阶段 2b 的新旗标让这条路径更容易被触发到。 |
| **F7** | INFO（说漏：边界里有一个 `src/landscape/**` 文件） | 报告 §6 写「`src/landscape/**` 的算法文件不应被改」并注明只改了 `settings.f90`；严格说 `src/landscape/types/settings.f90` **是** `src/landscape/**` 下的改动（8 行类型字段）。它只是别名冲突状态的载体、无算法语义，可接受，但"`src/landscape/**` 零改动"的表述在本文档体系里容易被后继读者误读。 |

**没有发现**：死旋钮、拼写不落地、`--help` 缺行、重名测试、核心层改动、BC-4 行为漂移、注入后仍绿的有效旗标。

---

## 11. 残留风险（不阻塞提交）

| # | 风险 | 说明 |
|---|---|---|
| R1 | meson 侧**未执行验证** | 本机无 meson/ninja（`which meson ninja` 为空）。4 个 `test(...)` 条目与 `add_test` 逐字同构、测试名 `uniq -d` 为空，但**没有运行证据**。与报告 32 R1 一致。 |
| R2 | `--lopt-hess-step`/`--lopt-sccacc` 在默认引擎下静默无效 | 见 F5；help 有说明，运行期无提示。 |
| R3 | `--lvib-restart warm` 不可独立观测 | 见 F3；是 engine/provider 的既有性质，非本阶段引入。 |
| R4 | `--lopt-sccacc`/`--lopt-hess-step` 断言处在打印精度末位 | 见 F4；建议换观测量。 |
| R5 | 别名冲突只在**同一任务内**成立 | `--lopt-hess-step` 与 `--lts-hess-step` 是两个不同的 `landscape_engine_control` 对象，不互查；但两个 runtype 旗标同现时 `select_runtyp` 已先报 runtype 冲突，无漏洞（我实测 `--lopt --lts-hess-step 0.02` 走 runtype 冲突分支）。 |
| R6 | `--lopt-max-steps 0`/负数不校验 | 与既有 `--lscan-max-steps` 行为一致（设计未要求），非新缺陷。 |

---

## 12. 判定与建议

**阶段 2b 通过独立验证，可以提交。** 建议：

1. **提交前订正报告 32 §5 前提 4 的事实错误**（F1，一行），否则该错误进入历史；本报告 §10 已给正确实测。
2. 可选（不阻塞）：把 F4 的两条断言加一个更强的观测量；给 F3 在 §9.2 表内补一句"`--lvib` 下 warm ≡ pin（机制见报告 33 F3）"；F5 加一行 NOTICE。
3. `--lvib-max-steps` 等表外旗标**未发明**（实测 `grep -c` = 0），阶段边界干净；`--opt`/`--ohess` 改派、§3.8 守卫、`--cycles` 映射属阶段 3，本轮**未越界**。
