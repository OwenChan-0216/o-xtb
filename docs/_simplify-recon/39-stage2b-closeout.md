# 39 — 阶段 2b 收口轮（复核 38 的两条 LOW：T1 提示门槛族、T2 权威文档订正）

> **对象**：仓库 `/home/owenchan/work_path/coding/fortran/xtb`，HEAD `3f155cc`。
> 工作树 = 未提交的阶段 2b + 报告 35（修复轮 1）+ 报告 37（修复轮 2）+ **本轮的 T1/T2**。
> **参照二进制**：`/tmp/xtb-p2bf2/build/xtb`（阶段 2b + 两轮修复 = 本轮之前的**最新**；旧文档/旧码用它复现）。
> **本构建**：`/tmp/xtb-p2bf3/build`（新建，`-O2 -DNDEBUG`、`WITH_TBLITE=OFF`、`WITH_CPCMX=OFF`、`WITH_TESTS=ON`）。
> **纪律**：所有 xtb/ctest 调用 `OMP_NUM_THREADS=1`；只跑 `-R landscape`（127）与回归子集（12）；
> **未跑全量 ctest**；**未 `git add`、未 commit**；核心层 `src/type|xtb|mctc|param|io|disp|coulomb` **0 改动**。
> 全部命令与输出为本轮实测；除特别标注外输入为 GFN2 + `--norestart`。

---

## 0. 判定摘要

| 项 | 结果 |
|---|---|
| 构建 | **exit 0**，`grep -ciE '\berror\b'` = 2（均为文件名 `mctc/env/error.f90`） |
| `ctest -R landscape` | **127/127 通过**（42.76 s；测试 target 数**不变**：122 `add_test` / 207 总数 / 127 landscape） |
| 回归子集 | **12/12 通过**（0.31 s） |
| `--help` 集合 S | **PASS**（未改 `xhelp.f90`，复跑确认） |
| 注入（2 个） | I1（只保留旧 hess-step 条件）、I2（新条件取反 `.and.`→`.or.`）**均红**，还原后全绿（§T1.3） |
| BC（11 组调用） | 输出文件**逐位相同**；stdout 仅 2 组新增 `(not used: …)` 行（§T1.4） |
| T1 | `--lts`/`--lvib` 的提示门槛从「只看步长旗标」扩到「同族任一旗标」，同源计数 `n_hess_fd` 不动 |
| T2 | 权威设计文档 `11-cli-redesign.md` 的证伪行改为实测结论（原文划线保留 + 订正指针）；`R43` 标注 ts 谓词已被取代；补 37/38 号留痕指针 |
| 残留 | meson 未跑（本机无 meson/ninja）；本轮**未改** `meson.build` 的 test 名与参数（只改注释）（§5） |

---

## T1（LOW-1）提示门槛必须覆盖同族的**两个**旋钮

### T1.1 先弄清事实：哪些旗标属于这个「未使用」提示的族？

复核 38 的 LOW-1 断言：`engine/engine.f90` 的提示门槛只看 `ctrl%hess_step_source`
（只有 `--l*-hess-step` 系旗标会设它），而 `--l*-sccacc` 直接写 `ctrl%hess_acc`、**不设任何 source 字段**，
于是「只给 `--l*-sccacc`」时两个旋钮都静默。

**族成员实测（不是读代码猜）**：`grep -nE "hess_acc|hess_step|hvp_step|%odlr" src/prog/main.F90` 的全部命中：

* `hess_step`：只有 `set_landscape_hess_step` 的调用（`--lopt-hess-step`、`--lscan-hess-step`、
  `--lts-step`/`--lts-hess-step`、`--lirc-step-hess`/`--lirc-hess-step`、`--lvib-step`/`--lvib-hess-step`）；
* `hess_acc`：只有 5 处直接赋值（`--lopt-sccacc`、`--lscan-sccacc`、`--lts-sccacc`、`--lirc-sccacc`、`--lvib-sccacc`）；
* `hvp_step`：**没有任何 CLI 旗标**（`main.F90` 零命中）；
* `%odlr`：只有 `--lvib-odlr`，且它**已单独响亮报错**（实测：`exit 1`，
  `-1- landscape_vib_hessian: the ODLR approximation … is not implemented in the landscape suite`），不是静默。

⇒ **族恰好是两个旋钮**（步长 `hess_step` + 精度 `hess_acc`），二者由**同一个数值 provider 消费**、被
`model`/`file` **同一并忽略**；**没有第三类**。`--lopt`/`--lscan`/`--lirc` 的 banner 谓词不看旗标、且在被消费时
本来就打提示（报告 35 的既有行为），无静默缺口，**本轮不动**。

### T1.2 复现（旧二进制 `p2bf2`，即本轮之前的交付态）

`--lts --lts-method dimer --lts-no-verify`（HCN），四种旗标组合（只有 sccacc / 只有 hess-step / 都无 / 都给）：

```
--- none       Hessian SCC accuracy: 3.000000E-01   Hessians 0
--- sccacc      Hessian SCC accuracy: 1.000000E+01   Hessians 0     <- 无 "(not used:"（缺口）
--- hessstep    Hessian SCC accuracy: 3.000000E-01   Hessians 0
                (not used: no numerical Hessian was built by this run)
--- both        Hessian SCC accuracy: 1.000000E+01   Hessians 0
                (not used: no numerical Hessian was built by this run)
```

`--lvib --lvib-hessian model` 同样：只给 `--lvib-sccacc 10.0` 时无提示（`Hessians 1`，model provider），
只给 `--lvib-hess-step 0.02` 时才有提示。⇒ 复核 38 的 LOW-1 **完全复现**：该项**确为**本轮收窄引入的新缺口。

### T1.3 修法与可证伪测试

**修法（保持同源原则，不退回方法名枚举）**：

| 文件 | 改动 | 性质 |
|---|---|---|
| `types/settings.f90` | 新增 `character(len=:), allocatable :: hess_acc_source`（`hess_step_source` 的同伴；无别名冲突检测，因每任务精度旗标拼写唯一） | 状态字段 |
| `src/prog/main.F90` | 5 处 `--l*-sccacc` 处理器各加一行 `<set>%engine%hess_acc_source = '--l*-sccacc'` | 解析层 |
| `engine/engine.f90` | 门槛 `if (.not. allocated(hess_step_source)) return` → `if (.not. allocated(hess_step_source) .and. .not. allocated(hess_acc_source)) return`；过程与文件头注释同步 | **谓词/打印层** |

同源计数 `n_hess_fd`（数值 provider 的 build 数）**未改**：提示仍只在 `n_hess_fd == 0` 时出现，
「给了**任一**同族旗标 ∧ 本次运行未读取任何数值 Hessian」是**关于本次运行的直接观测**，与
`landscape engine: Hessians N` 不可能矛盾。

**新测试用例（加进既有 mode `hessused`，不新增 target）**，`test/unit/landscape_cli_check.py`：

* `unused-ts-sccacc-only`：`--lts --lts-method dimer --lts-no-verify --lts-sccacc 10.0`（**无** hess-step）⇒ 必须有提示；
* `used-ts-sccacc-only`：`--lts --lts-method prfo --lts-sccacc 10.0`（**无** hess-step，确实建数值 Hessian）⇒ 必须无提示 ∧ `Hessians ≥ 1`；
* `unused-lvib-sccacc-only`：`--lvib --lvib-hessian model --lvib-sccacc 10.0` ⇒ 提示 = `the Hessian source 'model' has no finite differences`；
* `used-lvib-sccacc-only`：`--lvib --lvib-hessian numerical --lvib-sccacc 10.0` ⇒ 无提示。

（`expect` 助手加了一个可选 `step=` 参数，因为 sccacc-only 的回显步长是内置默认 `5.000000E-03`。）

绿：`ctest --test-dir /tmp/xtb-p2bf3/build -R 'landscape-hess-step-used'` → **Passed 0.64 sec**。

**注入（真实输出）**：

| # | 注入点 | 注入内容 | 真实输出 |
|---|---|---|---|
| I1 | `engine_report_unused_hess_step` 门槛 | **只保留旧的 hess-step 条件**（删掉 `.and. .not. allocated(hess_acc_source)`） | `FAIL: unused-ts-sccacc-only: the run does not report the unused step` → ctest `0% tests passed, 1 tests failed out of 1`（**红**） |
| I2 | 同上 | 新条件**取反**：`.and.` → `.or.`（只在两个旗标都给时才提示） | `FAIL: unused-ts-sccacc-only: the run does not report the unused step`（**红**） |

两次注入都在仓库工作树内做（`cp` 备份 + `edit` + 增量重编），**每次都从备份逐字节还原**，
最终 `diff -q src/landscape/engine/engine.f90 <备份>` = 相同，再全绿（§2）。

### T1.4 BC：只有 stdout 的 2 行新增，输出文件零变化

对**旧**（`p2bf2`）与**新**（`p2bf3`）二进制，11 组调用在同一调用下逐文件 `cmp`
（`bc-<label>-old` vs `bc-<label>-new`）：

```
lopt-sccacc   lscan   lts-dimer-sccacc   lts-prfo   lirc   lvib-model
lvib-num      sp      hess               opt        lopt-plain
files-differ=[]   （11/11 输出文件逐位相同）
```

stdout 的提示行差异（`grep -E '\(not used:|Hessian SCC accuracy'`）：

```
--- lts-dimer-sccacc
+ (not used: no numerical Hessian was built by this run)          <- 新增（T1 的目标）
--- lvib-model
+ (not used: the Hessian source 'model' has no finite differences) <- 新增（T1 的目标）
--- lopt-sccacc / lts-prfo / lvib-num / lopt-plain / …             （无差异）
```

⇒ 本轮是**纯提示层**改动：数值路径、输出文件、既有提示（`--lopt` 的 banner 提示）全部不动。

---

## T2（LOW-2）清理权威设计文档里已被证伪的断言

`docs/_simplify-recon/11-cli-redesign.md` 是**阶段 3 的输入文档**。本轮改三处，**原文一律保留**（划线/引用块）：

1. **§6.3 事实表**（原第 1893 行）：原一行把六方法写成同一结论
   「`dimer`/`neb`/`cineb`/`autoneb`/`string`/`gsm` + `--lts-no-verify` | 否」。
   改为**两行**：`dimer`/`neb`/`cineb` → 否（`Hessians 0`）；`autoneb`/`string`/`gsm` → **是**
   （实测：ammonia autoneb 跑到自然结束、`autoneb: termination autoneb completed`、`converged T`、exit 0，
   建 **1 个数值 Hessian**（`path_ts_list.xyz` 的候选模式），`landscape engine: Hessians 1`）。
   表下新增**引用块**：把原行以 `~~…~~` 保留，说明 `autoneb`/`string`/`gsm` 已被实测证伪、
   `--lts`/`--lvib` 的提示已改为**运行级同源陈述**；指针 = `37-stage2b-fix2.md` §T1 与
   `38-stage2b-fix2-review.md` LOW-2。
2. **§6.3 旋钮族补记**：说明该提示的**触发旗标族**是「步长 + 精度」两旋钮（无第三类），
   原门槛只看步长旗标 ⇒「只给 `--l*-sccacc`」静默，本轮已修（指针 `39-stage2b-closeout.md` §T1）。
3. **`R43`（`:74`）**：在其 ts 谓词描述后加**订正**——`--lts`/`--lvib` 的「按方法名枚举」谓词**已被取代**，
   改为 `engine%report_unused_hess_step` 同源陈述（指针 `37-stage2b-fix2.md`、`38-stage2b-fix2-review.md`）；
   `--lopt`/`--lscan`/`--lirc` 的前置谓词不变。

**留痕核验**（`grep -c`，修复前 → 修复后）：

```
37-stage2b   0 -> 2
38-stage2b   0 -> 3
39-stage2b   0 -> 3
```

---

## 1. 改动清单（本轮）

| 文件 | 改动 | 性质 |
|---|---|---|
| `src/landscape/types/settings.f90` | 新增 `landscape_engine_control%hess_acc_source` | 状态字段 |
| `src/prog/main.F90` | 5 处 `--l*-sccacc` 处理器各设 `hess_acc_source` | 解析层 |
| `src/landscape/engine/engine.f90` | 门槛接受同族**任一**旗标；过程/文件头注释同步 | 谓词/打印层 |
| `test/unit/landscape_cli_check.py` | `check_hessian_step_used`：`expect` 加 `step=` 参数 + 4 个 `*-sccacc-only` 用例 + 文档串 | 测试 |
| `test/unit/CMakeLists.txt` | `xtb/landscape-hess-step-used` 的注释更新（**未加/删 target**） | 注释 |
| `test/unit/meson.build` | 同名测试的注释更新（**未改 test 名与参数**） | 注释 |
| `docs/_simplify-recon/11-cli-redesign.md` | T2 的三处订正/留痕 | 文档 |
| `docs/_simplify-recon/39-stage2b-closeout.md` | 本报告 | 文档 |

**未改**：`src/xhelp.f90`、`types/{hessian,log,coords,constraints,results,json}.f90`、`saddle/**`、`irc/**`、
`optimize/**`、`scan/**`、`vib/**`、`tasks/{opt,scan,ts,irc}.f90`、`tasks/vib.f90`（报告 35/37 的谓词与同源提示保持原样）、
核心层 7 个目录、任何旗标拼写、任何算法/数值路径；**未**动阶段 3 的内容（`--opt`/`--ohess`、`--cycles`、档位 SCF）。

---

## 2. 验证命令汇总（可复跑）

```bash
cmake -S /home/owenchan/work_path/coding/fortran/xtb -B /tmp/xtb-p2bf3/build \
  -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"
cmake --build /tmp/xtb-p2bf3/build -j8
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p2bf3/build -R landscape
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p2bf3/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
python3 test/unit/landscape_help_check.py src/prog/main.F90 src/xhelp.f90
```

---

## 3. 被本轮**证伪/订正的前提**

1. **「提示门槛只需看 `hess_step_source`」——错（复核 38 LOW-1 成立）。**
   实测：只给 `--lts-sccacc 10.0` / `--lvib-sccacc 10.0` 时两个旋钮（步长 0.005、精度 10.0）都没被任何 build 读取
   （`Hessians 0` / model provider），却没有 `(not used:` 行；而只给步长旗标时**有**。属于「验证侧收窄、消费侧未覆盖」的同类缺陷。
2. **「同族的第三类旗标」——不存在。**
   `hvp_step` 无 CLI；`--lvib-odlr` 已单独响亮报错（exit 1）。族 = {步长, 精度}。
   `--lopt`/`--lscan`/`--lirc` 的 banner 谓词在被消费时本就打提示、无静默缺口，故本轮不把它们并入。
3. **`11-cli-redesign.md:1893` 的「`autoneb`/`string`/`gsm` + `--lts-no-verify` 步长未消费」——错。**
   实测 ammonia autoneb + `--lts-no-verify` 跑到自然结束（`converged T`、exit 0）后建 **1 个数值 Hessian**，
   与同一份 stdout 的 `Hessians 1` 矛盾；文档已改为实测结论并保留原文。
   （注：`dimer`/`neb`/`cineb` 的 `Hessians 0` 仍然成立，故该行只对三个方法证伪。）
4. **「改写权威设计文档会破坏已复核结论」——不成立。** 三处都是**留痕型**改动：原文保留（划线/引用块），
   新增的是订正指针与被证伪事实的实测替换，不删任何已复核的实现结论；`--lopt`/`--lscan`/`--lirc` 的谓词声明明确写「不变」。

---

## 4. 残留风险

| # | 项 | 说明 |
|---|---|---|
| R1 | meson 侧未执行 | 本机无 meson/ninja；本轮只改 `meson.build` 的**注释**，test 名与参数未变，无新增条目要核 |
| R2 | 提示仍是「运行级」真话 | 预算提前中止时也打 `no numerical Hessian was built by this run`；这是关于本次运行的真话（报告 37 R2 的延续） |
| R3 | 新增 stdout 行 | 只有「只给 `--l*-sccacc` 且未消费」的组合多一行；输出文件零变化（§T1.4），但以 stdout 全文做黄金比的外部工具链会看到新行 |
| R4 | `hess_acc_source` 只记录「是否给过」 | 不参与别名冲突检测（每任务精度旗标拼写唯一）；若将来给精度旗标加别名，需要同 `hess_step_source` 一样补冲突谓词 |
| R5 | 未提交 | 工作树含阶段 2b + 报告 35 + 报告 37 + 本轮；`git status` 无 staged 文件 |

---

## 5. 测试计数

* `add_test` 条目：**未增删**（**122**）；`ctest -N` 总数 **207**，`-N -R landscape` **127**。
* `grep -oE 'add_test\("[^"]+"' | sort | uniq -d` → 空。
* 本轮把新断言加进既有 mode `hessused`（只改/加用例，**不加 target**）。
* `ctest -R landscape` = **127/127**；回归子集 = **12/12**；`landscape_help_check.py` = **PASS**。
