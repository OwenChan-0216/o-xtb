# 35 — 阶段 2b 修复轮报告（T1..T5）

> **对象**：仓库 `/home/owenchan/work_path/coding/fortran/xtb`，HEAD `3f155cc`（阶段 2 + 上游修复已提交），
> 工作树 = **未提交的阶段 2b** + 本轮的 5 项修复。
> **本构建**：`/tmp/xtb-p2bf/build`（新建，`-O2 -DNDEBUG`、`WITH_TBLITE=OFF`、`WITH_CPCMX=OFF`、`WITH_TESTS=ON`）。
> **注入副本**：`/tmp/p2bf-inj/`（工作树拷贝 + `/tmp/p2bf-inj/build`，**仓库未动**）。
> **纪律**：所有 xtb/ctest 调用 `OMP_NUM_THREADS=1`；只跑 `-R landscape` 与回归子集；**未跑全量 ctest**；
> **未 `git add`、未 commit**；核心层 `src/type|xtb|mctc|param|io|disp|coulomb` **0 改动**。
> 全部命令与输出为本轮实测。

---

## 0. 判定摘要

| 项 | 结果 |
|---|---|
| 构建 | **exit 0**，0 error（`grep -ciE '\berror\b'` = 2，均为文件名 `mctc/env/error.f90`） |
| `ctest -R landscape` | **127/127 通过**（38.87 s；此前 125；`add_test` 120 → **122**，`ctest -N` 205 → **207**） |
| 回归子集 | **12/12 通过**（0.27 s） |
| `--help` 集合 S | **135 = 135，差集 0，PASS**（两个 dialect） |
| BC-4（15 组调用，含原生 `--sp/--hess/--opt`） | **全部输出文件逐位相同**；stdout 仅多出新回显行（见 §T1.5） |
| 注入（4 个） | 全部按设计**变红**，还原后全绿（§T1.4、§T2.3） |
| T1..T5 | 全部落地（T1 主工作 = 事实表 + 回显 + 提示 + 可证伪测试） |
| 残留 | meson 未跑（本机无 meson/ninja）；irc 的"非 numerical 源"证据依赖一次中止运行（§6） |

> **后续订正（`37-stage2b-fix2.md`，阶段 2b 修复轮 2）**：本报告 §T1.3 里 `--lts` 的三条
> "not used" 文案中，`dimer`/`neb` 两条（`… builds no Hessian and --lts-no-verify skips the
> confirmation`）**已被删除**：复核证实 `--lts-method autoneb --lts-no-verify` 在**跑到自然结束**时
> 会为 `path_ts_list.xyz` 的候选各建一个数值 Hessian，于是旧提示与同一份 stdout 的
> `landscape engine: Hessians 1` **自相矛盾**。`--lts`/`--lvib` 的提示现改为**与引擎 Hessian
> 计数同源**（`engine%report_unused_hess_step`），文案变为 `no numerical Hessian was built by
> this run`；`--lvib-hessian model|file` 的静默也已补上提示。§T1.2 的 banner 回显行、
> `--lopt`/`--lscan`/`--lirc` 的谓词与 §T1.4 的注入结论均未变。
> 本报告（35）其余部分与 `36` 号复核仍然有效。

---

## T1（用户裁定 2）回显有效值 + 无效时一行提示

### T1.1 事实表（**全部由实验确定**，不是读代码）

判据：对每个（任务, 算法）组合跑「有旗标 vs 无旗标」，看输出是否改变（改变 = 被消费）。
旗标取 `--l*-hess-step 0.2`（默认 0.005 的 **40 倍**）与 `--l*-sccacc 10.0`（默认 0.3 的 33 倍）；
观测量 = 输出文件字节 / 末能量 / 第一步梯度范数 / `landscape engine: Hessians` 计数器。

| 任务 | 算法 / 方法 | 是否消费 | 实测证据（有旗标 vs 无旗标） |
|---|---|---|---|
| `--lopt` | `sd` | 否 | `Hessians 0`，末能量 `-5.070522273869`、`xtb.trj` `c4e4d5ab9c` **两者相同** |
| `--lopt` | `cg` | 否 | 同上（`c4e4d5ab9c`） |
| `--lopt` | `lbfgs`（默认） | 否 | 末能量 `-5.070544447778`、`xtb.trj` `5a92557b3f`、`Hessians 0` 相同 |
| `--lopt` | `bfgs` | 否 | 末能量 `-5.070544444384`、`6e7ddb0556`、`Hessians 0` 相同 |
| `--lopt` | `diis` | 否 | `c4e4d5ab9c`、`Hessians 0` 相同 |
| `--lopt` | `rfo` + `--lopt-hessian numerical` | **是** | `Hessians 1`；末能量 `-5.070544447771` → **`-5.070544445800`**；`xtb.trj` `cc0e13f602` → `6f6902e4ac` |
| `--lopt` | `rfo` + `--lopt-hessian model` | 否 | 末能量 `-5.070544427225`、`xtb.trj` `7e3da86305` **两旗标都相同**（provider 的 `step` 实参文档为 unused，`types/hessian.f90:406`） |
| `--lscan` | 内层 `sd` / `cg` / `lbfgs` / `bfgs` / `diis` | 否 | `Hessians 0`；`xtbscan.log` 各自 `db325aeb44` / `86ce108535` / `64dd2d0da7` / `6a20beb920` / `db325aeb44` 两运行相同 |
| `--lscan` | 内层 `rfo` + `--lscan-hessian numerical` | **是** | `Hessians 3`；`xtbscan.log` `f15bfec110` → `258b6763cc`（sccacc：`2721433bbbf…` 亦变） |
| `--lscan` | 内层 `rfo` + `--lscan-hessian model` | 否 | `xtbscan.log` `d516495e25` 相同 |
| `--lscan` | `--lscan-mode rigid`（无内层最小化） | 否 | `Hessians 0`；`xtbscan.log` `b88ee55694` 相同 |
| `--lts` | `prfo`（确认开启） | **是** | 确认频率 `-1426.12` → **`-1395.15` cm^-1**；`xtbts.log` `8ede8ced0b` → `08582b60f3` |
| `--lts` | `bprfo`（确认开启） | **是** | `-1454.06` → **`-1424.12`**；`a29df5a8e1` → `9bfdba260d` |
| `--lts` | `dimer`（确认开启） | **是** | `-1297.92` → **`-1271.08`**；`Hessians 1` |
| `--lts` | `neb` / `cineb`（确认开启，`--lts-max-steps 80`） | **是** | `-968.98` → **`-915.60`** / `-969.47` → **`-916.08`**；`Hessians 1` |
| `--lts` | `autoneb` / `string` / `gsm`（确认开启） | **是** | `-969.47` → `-916.08` / `-966.23` → `-913.00` / `-966.23` → `-913.00` |
| `--lts` | `prfo` + `--lts-no-verify` | **是**（搜索自建） | `Hessians 3`（无确认）vs `4`（含确认）；`xtbts.log` `0b953d58d5` → `b18ca5e308` |
| `--lts` | `bprfo` + `--lts-no-verify` | **是**（搜索自建） | `Hessians 5`；`0539df4931` → `868c565ff1` |
| `--lts` | `dimer` + `--lts-no-verify` | 否 | `Hessians 0`；`f23f6c036f` 相同 |
| `--lts` | `neb` / `cineb` + `--lts-no-verify` | 否 | `Hessians 0`；`23666aeba2` / `cb7e818259` 相同 |
| `--lts` | `autoneb` / `string` / `gsm` + `--lts-no-verify` | 否 | 输出逐位同（`53a27fcc17` / `b4c96d1fdb` / `711a17c269`）；三者仍报 `Hessians 1`，但该次与步长**无关** |
| `--lts` | `prfo` / `dimer` + `--lts-hessian model` | 否 | `Hessians 7` / `1`（model provider），`d5e1d0a44d` / `8610622902` 两运行相同 |
| `--lirc` | `gs` / `lqa` / `hpc` / `eulerpc` | **是** | `Hessians 1`（初始 Hessian）；`irc.log` `0abb3aef6d`→`19ecfbf0cf`、`a4815b5c38`→`3be5944553`、`c9b8ddc53a`→`a35d5b806f`、`6df8053744`→`9e7ff63c54`（sccacc 四法亦变） |
| `--lirc` | 四法 + `--lirc-hessian model` | 否（且运行中止） | 两运行均 `Hessians 1`、无 `irc.log`：D2 模型 Hessian 在本 fixture 上给 0 个虚频 ⇒ 在 TS 确认处 `ERROR` 中止 |

**这张表就是谓词**（写进 `tasks/{opt,scan,ts,irc}.f90` 的 `*_unused_hessian_step`）：

```
opt : used  ⇔  algorithm == rfo            ∧ hessian_source == numerical
scan: used  ⇔  mode == relaxed             ∧ inner algorithm == rfo ∧ source == numerical
ts  : used  ⇔  source == numerical         ∧ ( verify_ts ∨ method ∈ {prfo, bprfo} )
irc : used  ⇔  source == numerical
```

**比任务书要求的 (任务, 算法) 二维表多一维 `hessian_source`**：这是**有意**的，因为
`model`/`file` provider 的 `step` 实参文档即 unused（`types/hessian.f90:406/461`），
这一维只会把"used"收窄成"unused"，**不可能把真正被消费的组合误标为 unused**（用户最担心的方向）。
实测两侧都做了（`rfo + model`、`prfo + model`、`lirc + model`）。

### T1.2 banner 回显（4 个任务各两行，值从**设置对象**读）

```fortran
      write(env%unit, '(1x,a,es15.6,a)') "Hessian step:             ", &
         & settings%engine%hess_step, " bohr"
      write(env%unit, '(1x,a,es15.6)') "Hessian SCC accuracy:     ", &
         & settings%engine%hess_acc
```

沿用 `tasks/vib.f90:133-136` 的**既有行式与对齐**（同一个概念只留一种拼写），
所以现在 5 个任务的这一对行完全一致。实测（`--lopt --lopt-hess-step 0.02 --lopt-sccacc 10.0`）：

```
 Hessian step:                2.000000E-02 bohr
 Hessian SCC accuracy:        1.000000E+01
 (not used: lbfgs builds no numerical Hessian)
```

### T1.3 无效时的一行提示

紧跟回显行，格式 `(not used: <reason>)`，reason 由同一个谓词函数给出：

| 任务 | 情形 | 提示文本（实测原文） |
|---|---|---|
| opt | 非 rfo | `(not used: lbfgs builds no numerical Hessian)` |
| opt/scan/ts/irc | 非 numerical 源 | `(not used: the Hessian source 'model' has no finite differences)` |
| scan | rigid | `(not used: a rigid scan builds no Hessian)` |
| ts | 无确认且非 prfo/bprfo | `(not used: dimer builds no Hessian and --lts-no-verify skips the confirmation)`（`neb` 同式） |

**ts 的谓词是本轮最容易写错的一处**：`--lts-no-verify` **并不**等于"不消费"——
P-RFO/B-PRFO 的搜索自己建数值 Hessian（实测 `Hessians 3`，`xtbts.log` 随步长变）。
写成"no-verify ⇒ unused"就是新的谎言，故专门加了 `used-ts-prfo-no-verify` 用例与 I3 注入（§T1.4）。

### T1.4 可证伪测试与注入（真实输出）

新测试 `xtb/landscape-hess-step-used`（mode `hessused`，`test/unit/landscape_cli_check.py`）：
每任务 **一个 used + 一个 unused** 组合；used 侧还断言 `landscape engine: Hessians ≥ 1`
（回显本身不构成证据），unused 侧断言提示文本。

```
# 绿（本构建）
$ ctest --test-dir /tmp/xtb-p2bf/build -R 'landscape-hess-step-used|landscape-lvib-restart-warm'
1/2 Test #194: xtb/landscape-hess-step-used ......   Passed    0.36 sec
2/2 Test #195: xtb/landscape-lvib-restart-warm ...   Passed    0.09 sec
```

注入（在 `/tmp/p2bf-inj/` 副本里做，仓库未动）：

| # | 注入点 | 注入内容 | 真实输出 |
|---|---|---|---|
| I1 | `tasks/opt.f90` 回显行 | `settings%engine%hess_step` → `5.0e-3_wp` | `FAIL: used-opt-rfo: the run does not echo the effective step 2.000000E-02` → **红** |
| I2 | `opt_unused_hessian_step` 谓词 | `algorithm /= rfo` → `algorithm == rfo`（取反） | `FAIL: used-opt-rfo: the step is consumed but the run reports it as unused ('rfo builds no numerical Hessian')` → **红** |
| I3 | `ts_unused_hessian_step` 谓词 | 去掉 `prfo/bprfo` 例外，写成 `.not. verify_ts` ⇒ unused（**诱人错向**） | `FAIL: used-ts-prfo-no-verify: the step is consumed but the run reports it as unused ('prfo builds no Hessian and --lts-no-verify skips the confirmation')` → **红** |
| I4 | `engine/engine.f90:604` restart 分支 | `warm` 行为改成 `off` | `FAIL: --lvib-restart warm differs from pin: the documented equivalence of --help no longer holds` → **红**（T2 的测试） |

I1/I2/I3 三次注入之间互不干扰（I1 注入的那次 `ctest -R 'landscape-hess-step-used|landscape-lvib-restart-warm'`
里，`hess-step-used` 红而 `lvib-restart-warm` 仍 `Passed`）。
注入全部只发生在 `/tmp/p2bf-inj/` 副本（每次先还原上一个注入再注入下一个），**仓库工作树全程未改**。

### T1.5 BC-4：新回显行是**唯一**的行为变化，且不触任何输出文件

15 组调用（`--lopt`、`--lopt --lopt-engine rfo`、`--lscan`、`--lscan` 2D、`--lts prfo/dimer/neb`、
`--lirc gs/hpc`、`--lvib`、`--sp`、`--hess`、`--opt`、`--lvib-step`、`--lts-step`）
在**修复前的阶段 2b 二进制**（`/tmp/xtb-p2b-val/build/xtb`）与本构建之间逐文件 `cmp`：

```
lopt       files=charges,wbo,xtb.trj,xtbopt.xyz,xtbrestart,xtbtopo.mol
lts-neb    files=path.xyz,xtbrestart,xtbts.log,xtbts.xyz
lirc-gs    files=charges,irc.log,irc_backward.xyz,irc_forward.xyz,irc_path.xyz,wbo,xtbrestart,xtbtopo.mol
lvib       files=charges,g98.out,hessian,vib_normal_modes,vibspectrum,wbo,xtbrestart,xtbtopo.mol
opt        files=.xtboptok,charges,wbo,xtbopt.log,xtbopt.xyz,xtbrestart,xtbtopo.mol
DIFFS: none
```

stdout 的差异（剔除时间戳/种子/`program call` 等既有噪声后）：

```
=== lopt:     3 significant stdout line(s) differ
    + Hessian step:                5.000000E-03 bohr
    + Hessian SCC accuracy:        3.000000E-01
    + (not used: lbfgs builds no numerical Hessian)
=== lts-prfo: 2 significant stdout line(s) differ   (+ Hessian step / + Hessian SCC accuracy)
=== lirc-gs:  2 significant stdout line(s) differ   (+ Hessian step / + Hessian SCC accuracy)
=== lvib:     0 significant stdout line(s) differ   ← 它本来就有这两行
```

⇒ 这是**有意的 stdout 变化**（阶段 2b 的 T1 要求），**零输出文件变化**。

---

## T2（用户裁定 1）文档化 `--lvib-restart warm` ≡ `pin`

### T2.1 `--help`（`src/xhelp.f90`）

```
--lvib-restart MODE
    wavefunction restart policy of the engine, off (default), pin or warm.
    The finite difference sequence resets the wavefunction to the state it
    entered the Hessian with before every displacement, so warm and pin
    hand the provider the same start and produce a byte identical
    `hessian` file; only off is distinguishable (it records the cold start
    wavefunction).  The two spellings are kept, the equivalence is
    asserted by the xtb/landscape-lvib-restart-warm check
```

### T2.2 断言该等价本身的测试

新测试 `xtb/landscape-lvib-restart-warm`（mode `lvibrestart`）：跑 `--lvib --lvib-restart off|pin|warm`，
断言 engine 回读的策略正确、`off ≠ pin`（证明旗标不是死的）、**`pin` 与 `warm` 的 `hessian` 逐位同**
（失败消息直接点名"文档化的等价不再成立"）。本构建实测 `Passed 0.09 sec`。

### T2.3 注入（证明该测试可红）

`engine/engine.f90` 的 `case (p_landscape_restart_warm)` 改成先 `pin_state` 再 `copy(wfn_ref)`
（即行为等于 `off`）：

```
FAIL: --lvib-restart warm differs from pin: the documented equivalence of `--help` no longer holds
```

### T2.4 设计文档登记

`11-cli-redesign.md` §6.3 的表下新增「**已知等价（T2）**」段（含机制与 `md5` 证据），
并在修订记录新增 **R43** 行。

---

## T3（LOW-1）修正不实的帮助文本

**先自证判据**（不只读 `driver.f90:183`）：

* `--lopt`：6 个引擎里只有 `rfo` 走 `use_trust` ⇒ 建数值 Hessian（实测 `Hessians 1`）；
  `bfgs` 只在 `hessian_source == 'model'` 时取初始 Hessian（`driver.f90:203-213`），**不建数值 Hessian**（实测 `Hessians 0`）。
* `--lscan`：内层最小化器走同一个 `landscape_optimize_model` ⇒ 只有内层 `rfo` 建（实测 `Hessians 3`）；rigid 无内层器。
* `--lts`：prfo/bprfo 搜索建、dimer 不建，但**确认**对 8 个方法都建（实测）。
* `--lirc`：四法都建初始 Hessian（实测 `Hessians 1`）。

`--help` 是**按任务写的**，所以按任务改，不一律写成 `rfo`：

| 位置 | 原文（不实） | 现文（与代码一致） |
|---|---|---|
| `--lopt-hess-step`（原 `:320`） | `used by an algorithm that builds one (rfo, bfgs) - the default lbfgs never does` | `only --lopt-engine rfo builds a numerical Hessian; the other five engines (including the default lbfgs) never do, and the value is ignored for --lopt-hessian model or file. The run echoes the effective value and marks it as unused in that case.` |
| `--lscan-hess-step`（原 `:394-395`） | `used by an inner minimiser that builds one (rfo, bfgs)` | `only an inner minimiser of --lscan-method rfo builds a numerical Hessian (the default lbfgs never does), a rigid scan has no inner minimisation at all, and the value is ignored for --lscan-hessian model or file. The run echoes the effective value and marks it as unused in those cases` |
| `--lopt-sccacc` / `--lscan-sccacc` | `used by an algorithm that builds one` | `consumed by the same engine/inner minimiser and Hessian source as --lopt/--lscan-hess-step` |

`--lts-hess-step`/`--lirc-hess-step`/`--lvib-hess-step` 的 help 行**未做**算法归属断言（只写单位与别名关系），
核对后**无同类不实陈述**，故未改。`--help` 集合 S 复跑：**135 = 135，差集 0，PASS**（两个 dialect）。

---

## T4 订正实施报告的事实错误（`32-stage2b-impl.md`）

按留痕纪律**原文不删**，在 §5 之后新增 **§5b 订正块**（以 `33-stage2b-validation.md` 为权威）：

1. **F1（事实错误）**：`--lirc-restart bogus` 实测报 `The --lirc-restart flag requires off, pin or warm`（**旧**措辞），
   不是 `Unknown landscape restart policy`。正确分布：`--lscan-restart` 用新措辞（1/3），`--lts/--lirc-restart` 用旧措辞（2/3）
   ⇒ 新旗标采纳的是**少数派**措辞，原文"3 个既有 restart 里 2 个是后者"的论证**方向是反的**（结论不变，依据作废）。
2. **F2（不精确）**：`1.267e-11 bohr` 只对 **off-vs-pin** 成立；`off-vs-warm = pin-vs-warm = 1.2164e-06`（**大 5 个数量级**），不得合并叙述。
3. **F4（证据脆弱）**：`--lopt-sccacc` 的末能量差只有 **2.0e-11 Eh**（打印末位），应改用已实测的第一步梯度范数
   `1.773788E-04 → 2.069108E-04`（**16 %**）与 `xtb.trj` 字节；测试本身未改（能量比较仍成立），只订正论据强度叙述。

---

## T5 登记 INFO 项（不修代码）

`11-cli-redesign.md` 的 R43 行下方新增「**R43 登记的已知项（INFO）**」：

1. **死参 `sccacc=`**：`engine/engine.f90:254` 的 `hp%sccacc = self%ctrl%hess_acc` **覆盖**任务层传入 provider 工厂的 `sccacc=` 实参
   （`tasks/{opt,scan,sp,irc,ts}.f90` 同源）⇒ 内部冗余，非用户可见缺陷（报告 33 的 I4 注入实测：任务层注入常量仍全绿）。
2. **`--lts-restart` 未知值消息措辞与 `--lscan/--lirc-restart` 不统一**：`--lts-restart bogus` 报旧措辞，
   `--lscan/--lirc-restart bogus` 报新措辞（分布见 F1）；统一会改既有输出文本，属另一个改动 ⇒ **有意不修**。

---

## 1. 改动清单

| 文件 | 改动 | 性质 |
|---|---|---|
| `src/landscape/tasks/opt.f90` | banner 两行回显 + `opt_unused_hessian_step` 谓词 + 提示行 | **仅打印层**（无算法/数值改动） |
| `src/landscape/tasks/scan.f90` | 同上 + `scan_unused_hessian_step`；内层算法解析提到一次（值不变） | 仅打印层 |
| `src/landscape/tasks/ts.f90` | 同上 + `ts_unused_hessian_step` | 仅打印层 |
| `src/landscape/tasks/irc.f90` | 同上 + `irc_unused_hessian_step` | 仅打印层 |
| `src/xhelp.f90` | T3 两处不实文案订正；`--lvib-restart` 的 T2 等价说明；`--lopt/--lscan-sccacc` 的消费点说明 | 文案 |
| `test/unit/landscape_cli_check.py` | 新增 mode `hessused`、`lvibrestart`（+ 文档串） | 测试 |
| `test/unit/CMakeLists.txt` | 新增 `xtb/landscape-hess-step-used`、`xtb/landscape-lvib-restart-warm`（含 ENVIRONMENT 列表） | 测试注册 |
| `test/unit/meson.build` | 同两条 `test(...)`（与 CMake 逐字同构；**未执行**） | 测试注册 |
| `docs/_simplify-recon/11-cli-redesign.md` | §6.3 事实表 + T2 等价登记 + R43 行 + T5 两条 INFO | 文档 |
| `docs/_simplify-recon/32-stage2b-impl.md` | §5b 订正块（F1/F2/F4） | 文档 |
| `docs/_simplify-recon/35-stage2b-fix.md` | 本报告 | 文档 |

**未改**：`src/landscape/engine/**`、`optimize/**`、`saddle/**`、`irc/**`、`vib/**`、`scan/**`、
`types/**`（阶段 2b 的 `hess_step_source` 字段保持原样）、核心层 7 个目录。

测试计数：`add_test` **122**（120 + 2），`ctest -N` **207**（205 + 2），
`grep -oE 'add_test\("[^"]+"' | sort | uniq -d` **空**，meson `test('...'` 重复 **空**。

---

## 2. 被本轮**证伪的前提**（任务书/既有文档里的静态想法）

1. **「`--lts --lts-method dimer` 不需要 Hessian ⇒ 步长必然 unused」——只对搜索成立，对整条运行不成立。**
   实测 dimer 的**确认**会建数值 Hessian：`-1297.92` → `-1271.08 cm^-1`（`--lts-hess-step 0.2`），`Hessians 1`。
   ⇒ 谓词必须按"整条运行"写（`verify_ts`），不能按搜索写。
2. **「`--lts-no-verify` ⇒ 步长 unused」是错的**：P-RFO/B-PRFO 的搜索自建数值 Hessian（实测 `Hessians 3`，`xtbts.log` 随步长变）。
   这正是 §T1.3 的"诱人错向"，已由 `used-ts-prfo-no-verify` 用例 + I3 注入钉住。
3. **「`--lopt` 的 `(rfo, bfgs)` 都建数值 Hessian」不实**（本轮新写的 help 文案）：`bfgs` 只在 model 源取初始 Hessian
   （`driver.f90:203-213`），数值 Hessian 实测 `Hessians 0`。T3 已改。
4. **「restart 的可观测量是末能量」不成立**（报告 32 已记，本轮 T2 再次确认）：`off/pin/warm` 末能量 12 位小数相同，
   可观测量是 `xtb.trj` / `hessian` 字节。
5. **「`--lopt-sccacc` 的生效证据是末能量差」太弱**（报告 33 F4）：只有 2.0e-11 Eh（打印末位）；
   第一步梯度范数差 16 %（`1.773788E-04 → 2.069108E-04`）才是可靠观测量。T4 已订正报告论据。
6. **「谓词按 (任务, 算法) 二维表就够」不足**：`hessian_source` 是第三个维度（`rfo + model` 实测两旗标都无效）。
   本轮把该维纳入谓词（只可能收窄"used"方向）。

---

## 3. 复核者 F6 的处置

复核者的 **F6**（`--method lvib` 的报错文本点名了用户没写的旗标）**本轮未按 F6 改任何东西**：
按用户裁定，该文本准确且 `--lvib` 存在，不属本轮 5 项。

---

## 4. 验证命令汇总（可复跑）

```bash
cmake -S /home/owenchan/work_path/coding/fortran/xtb -B /tmp/xtb-p2bf/build \
  -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"
cmake --build /tmp/xtb-p2bf/build -j8
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p2bf/build -R landscape
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p2bf/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
python3 test/unit/landscape_help_check.py src/prog/main.F90 src/xhelp.f90
```

---

## 5. 残留风险

| # | 项 | 说明 |
|---|---|---|
| R1 | meson 侧未执行 | 本机无 meson/ninja；两条 `test(...)` 与 CMake 条目逐字同构，`uniq -d` 为空，但**无运行证据** |
| R2 | irc 的"非 `numerical` 源 ⇒ unused"证据依赖一次**中止**运行 | `--lirc-hessian model` 在本项目两个 TS fixture 上 D2 模型 Hessian 都给 0 个虚频 ⇒ 在确认处 `ERROR` 中止（两运行相同）。谓词在该情形的正确性由"provider 的 `step` 实参文档为 unused" + 中止前 `Hessians 1` 支撑，**不是**由路径积分差分支撑 |
| R3 | 新增 2~3 行 stdout 是**有意的**行为变化 | 输出文件零变化（§T1.5），但任何以 stdout 全文做黄金比的**外部**工具链会看到新行 |
| R4 | 谓词含 `hessian_source` 维 | 比任务书的二维表更严；只收窄"used"方向（见 §T1.1），但后继读者需知道这条维度的存在 |
| R5 | `--sp`/`--lvib` 未加提示行 | `--lvib` 本来就有回显（且恒消费）；`--sp` 不用 Hessian，不在 T1 的 4 任务范围 |
| R6 | 未提交 | 工作树含阶段 2b + 本轮；`git status` 无 staged 文件 |
