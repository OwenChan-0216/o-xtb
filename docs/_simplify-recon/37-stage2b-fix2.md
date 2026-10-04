# 37 — 阶段 2b 修复轮 2：提示与计数同源（T1..T3）

> **对象**：仓库 `/home/owenchan/work_path/coding/fortran/xtb`，HEAD `3f155cc`。
> 工作树 = **未提交的阶段 2b + 修复轮（报告 35）+ 本轮的 T1..T3**。
> **本构建**：`/tmp/xtb-p2bf2/build`（新建，`-O2 -DNDEBUG`、`WITH_TBLITE=OFF`、`WITH_CPCMX=OFF`、`WITH_TESTS=ON`）。
> **注入副本**：`/tmp/p2bf2-inj/`（工作树 tar 拷贝 + `/tmp/p2bf2-inj/build`，**仓库未动**）。
> **纪律**：所有 xtb/ctest 调用 `OMP_NUM_THREADS=1`；只跑 `-R landscape`（127）与回归子集（12）；
> **未跑全量 ctest**；**未 `git add`、未 commit**；核心层 `src/type|xtb|mctc|param|io|disp|coulomb` **0 改动**。
> 全部命令与输出为本轮实测；除特别标注外输入为 GFN2 + `--norestart`。

---

## 0. 判定摘要

| 项 | 结果 |
|---|---|
| 构建 | **exit 0**，`grep -ciE '\berror\b'` = 0 |
| `ctest -R landscape` | **127/127 通过**（15.34 s；测试 target 数不变，仍是报告 35 的 122 `add_test` / 207 总数） |
| 回归子集 | **12/12 通过**（0.31 s） |
| `--help` 集合 S | **135 = 135，差集 0，PASS**（未改 `xhelp.f90`，复跑确认） |
| 输出文件（BC） | 6 组调用新旧二进制**逐文件相同**（§3） |
| 注入（4 个） | I1..I4 全部按设计**变红**，还原后全绿（§2.4、§T2.3） |
| T1 | `--lts` 的"自相矛盾提示"**消灭**：提示改为与 `Hessians N` **同源**（选方案 (a)，理由见 §T1.1） |
| T2 | `--lvib-hessian model|file` 的静默**补上**同源提示 |
| T3 | `32-stage2b-impl.md` §7 R2 加**订正指针**（原文保留） |
| 残留 | meson 未跑（本机无 meson/ninja）；预算耗尽时提示为"运行级"真话而非"方法级"真话（§5 R2） |

---

## T1（MEDIUM-1）消灭 `--lts` 的"自相矛盾提示"

### T1.1 选 (a) 还是 (b)：选 **(a) 同源化**

任务书给了两条路：(a) 把提示搬到"计数已知的位置"，条件 = `用户显式给了 hess-step 旗标` ∧ `本次运行实际建的数值 Hessian 数 == 0`；
(b) 在运行前原理上不可判定时干脆不打提示。

我选 **(a)**，理由如下（逐条对应任务书的判据）：

1. **(b) 的"不可判定"只对一部分 `--lts` 组合成立**，整任务放弃提示会丢掉**本来为真且有用**的信息。
   实测（§T1.2）：`--lts-method dimer --lts-no-verify` 整条运行 `Hessians 0`，`--lts-method neb|cineb --lts-no-verify`
   到自然结束也是 `Hessians 0`——这些"步长确实没进任何 provider"是事实，删掉提示等于把可证的真话一起删掉。
2. **(a) 的构造性保证正是任务书要的"不可能矛盾"**：提示与 `landscape engine: Hessians N` **由同一个事实导出**——
   两者都来自 `engine_hessian` 的成功返回。引擎新增一个只数**数值 provider** 的计数器 `n_hess_fd`
   （`n_hess` 把 `model`/`file` provider 的 build 也数进去，所以不是同一个数）。提示的条件是 `n_hess_fd == 0`：
   - `n_hess_fd > 0` ⇒ 至少一次 build 真的把 `hess_step` 交给了 FD provider ⇒ 静默；
   - `n_hess_fd == 0` 且提示出现 ⇒ 该次运行没有任何 FD build，于是"这次运行没有消费该步长"是**关于本次运行的直接观测**，
     与"数了几个 Hessian"不冲突（可以是 `Hessians 0`，也可以是 `Hessians N>0` 的 model/file build，后者由提示的
     文案"the Hessian source '<name>' has no finite differences"解释清楚）。
3. **运行未完成（预算耗尽）时是否仍然为真？**是。提示的措辞是**运行级**的
   （`no numerical Hessian was built by this run`），不是方法级的。一个因为预算提前停下的 run 确实"没有建数值 Hessian"，
   这句话为真；它**不**声称"该方法永远不会用这个步长"。旧提示的反面（`autoneb builds no Hessian …`）才是方法级断言，
   而它被实测证伪（§T1.2）。这正是"宁可说关于观测运行的真话，不说关于方法名的猜测"。
   代价：预算耗尽的 `dimer --lts-no-verify` 也会打这句提示，读者需要理解它是"本次运行"的陈述——已记入 §5 R2。

实现位置与同源证明（代码）：

| 位置 | 改动 |
|---|---|
| `src/landscape/engine/engine.f90` 类型 `landscape_engine` | 新字段 `integer :: n_hess_fd = 0`（只数数值 provider 的 build） |
| 同上 `engine_hessian` provider 分支 | 成功 return 前：`if (self%hp%name == 'numerical') self%n_hess_fd = self%n_hess_fd + 1` |
| 同上 新过程 `report_unused_hess_step` | `n_hess_fd > 0` ⇒ 返回；`hess_step_source` 未分配 ⇒ 返回；否则按 `hp%name` 给文案 |
| `src/landscape/tasks/ts.f90` | 删掉 `ts_unused_hessian_step`（按方法名枚举路径的前置谓词）与 banner 提示；在**两处** `engine%report` 之后调用 `engine%report_unused_hess_step` |
| `src/landscape/vib/numhess.f90` | 在 `engine%report` 之后调用同一个过程（T2） |

`n_hess_fd` 与 `n_hess` 都在 `engine_hessian` 的**同一个 return 路径**上递增，因此
`n_hess_fd <= n_hess` 恒成立；提示读的是前者，计数打印的是后者，两者不可能对同一份 stdout 说反话。

> **为什么不把提示塞进 `engine_report` 本身？** 因为 `--lopt`/`--lscan`/`--lirc` 仍用报告 35 的 banner 前置谓词
> （那三个任务的谓词是可证的，且已通过复核，本轮**不改**）。若 `engine_report` 无条件打提示，那三个任务会出现
> **两条**提示。用一个独立过程、由需要它的两个任务显式调用，可把改动面精确限制在 `--lts`/`--lvib`。

### T1.2 事实表（本轮实测，**跑到自然结束**，回应任务书的混杂因子）

父会话事实 A 的混杂因子是：`--lts-max-steps 3` 使全部 run `exit=1`，于是 `Hessians 0` 可能只是"提前中止"。
**本轮把每种组合都放到自然结束**（不传 `--lts-max-steps`），并且**记录 exit 与终止原因**：

NH3 上翻/下翻（`nh3up.xyz` + `--lts-product nh3down.xyz --lts-images 5 --lts-no-verify --lts-hess-step 0.02 --lts-sccacc 10.0`）：

| 方法 | exit | 终止 | `Hessians N` | 旧提示 | 新提示 |
|---|---|---|---|---|---|
| `autoneb` | **0** | `autoneb: termination autoneb completed`，`converged T` | **1** | **(错) `autoneb builds no Hessian …`** | **无** |
| `string` | 1 | `string reached the iteration limit`（自然结束，非提前 return） | **1** | (错) | **无** |
| `gsm` | 1 | `gsm reached the iteration limit` | **1** | (错) | **无** |
| `neb` | 0 | converged | 0 | 有 | `no numerical Hessian was built by this run` |
| `cineb` | 0 | converged | 0 | 有 | 同上 |
| `dimer`（HCN 输入） | 0 | converged | 0 | 有 | 同上 |
| `prfo`（HCN，`--lts-max-steps 2`） | 1 | 预算 | 2 / 3 | 无 | 无 |
| `prfo --lts-no-verify` | 1 | 预算 | 2 | 无 | 无 |

父会话事实 A 的**原样复现**（HCN + `--lts-product hnc_prod.xyz --lts-images 5 --lts-no-verify --lts-max-steps 3`）：
本构建输出 `landscape engine: Hessians 3` 且 **0 条 `(not used:`**——矛盾消失。

⇒ 结论：**父会话的混杂因子不影响结论**。矛盾在"跑到自然结束（exit 0）"的 ammonia autoneb 上同样成立
（`Hessians 1` 对 `autoneb builds no Hessian`），所以事实 A 不是中止伪像；而 `string`/`gsm` 的
`Hessians 1` 也证明"band 搜索不建 Hessian"的前置断言只对 `neb|cineb` 成立、对
`autoneb|string|gsm`（它们为 `path_ts_list.xyz` 的候选几何建 Hessian）**不**成立。

`--lvib`（T2，H2O，`--lvib-sccacc 10.0`）：

| `--lvib-hessian` | `--lvib-hess-step` | `hessian` md5 | 新提示 |
|---|---|---|---|
| `numerical` | 0.005 | `5d56e4c9fb…` | 无 |
| `numerical` | 0.02 | `80eaa11e41…`（**变**） | 无 |
| `model` | 0.005 | `f334c99ecb…` | `the Hessian source 'model' has no finite differences` |
| `model` | 0.02 | `f334c99ecb…`（**不变**） | 同上 |

⇒ `model` 下 `--lvib-hess-step` 确实不改变任何输出（这就是"静默"的实测证据），提示是诚实的；
`numerical` 下旗标确实是活的，提示不出现。

### T1.3 提示文案与位置（实测 stdout）

`--lts --lts-method dimer --lts-no-verify --lts-hess-step 0.02 --lts-sccacc 10.0`：

```
 Hessian step:                2.000000E-02 bohr          <- banner 回显（保留）
 Hessian SCC accuracy:        1.000000E+01
 ...
 landscape engine: Hessians           0                  <- 计数（引擎 report，未改）
 landscape engine: Hessian-vector     0
 (not used: no numerical Hessian was built by this run)  <- 同源提示（新增位置）
```

`--lts --lts-method prfo --lts-hessian model --lts-hess-step 0.02`：

```
 landscape engine: Hessians           257
 (not used: the Hessian source 'model' has no finite differences)
```

### T1.4 可证伪测试与注入（真实输出）

测试仍是 `xtb/landscape-hess-step-used`（`landscape_cli_check.py` mode `hessused`），本轮改/加了
`--lts` 与 `--lvib` 的用例：

* `used-ts-autoneb-no-verify`：**跑到自然结束**（断言 `autoneb: termination autoneb completed`）、
  断言无提示、断言 `Hessians >= 1`——这就是任务书要的"实际建了 Hessian 而提示不出现"；
* `unused-ts-dimer-no-verify` / `unused-ts-neb-no-verify`：断言提示 = `no numerical Hessian was built by this run`；
* `unused-ts-model`：断言提示 = `the Hessian source 'model' has no finite differences`；
* `used-ts-prfo` / `used-ts-prfo-no-verify`：断言无提示（诱人错向的反例）；
* `unused-lvib-model` / `used-lvib-numerical`：T2 的一对；
* `--lvib` 的 md5 对：`numerical` 下 0.005 vs 0.02 必须**不同**，`model` 下必须**相同**。

注入（在 `/tmp/p2bf2-inj/` 副本里做，逐次还原；**仓库工作树全程未改**）：

| # | 注入点 | 注入内容 | 真实输出 |
|---|---|---|---|
| I1 | `engine_report_unused_hess_step` 首个守卫 | `if (self%n_hess_fd > 0)` → `if (self%n_hess_fd >= 0)`（**条件恒假**，永不打提示） | `FAIL: unused-ts-dimer-no-verify: the run does not report the unused step` → **红**（exit 120） |
| I2 | 同上 | 加 `.and. .false.`（**条件恒真**，永远打提示） | `FAIL: used-ts-prfo: the step is consumed but the run reports it as unused ('no numerical Hessian was built by this run')` → **红** |
| I3 | `tasks/vib.f90` 回显行 | `settings%engine%hess_step` → 常量 `5.0e-3_wp` | `FAIL: unused-lvib-model: the run does not echo the effective step 2.000000E-02` → **红** |
| I4 | `engine_hessian` 计数守卫 | 去掉 `hp%name == 'numerical'`（改成**凡 provider build 都计数**） | `FAIL: unused-ts-model: the run does not report the unused step` → **红** |

I4 是关键的"同源"注入：它把"数值 Hessian 数"偷换成"所有 Hessian 数"，于是 `--lts-hessian model` 的提示被误消。
I1/I2 是任务书要的"条件恒真/恒假"。还原后 `hessused` 全绿（exit 0）。

---

## T2（LOW-1）`--lvib` 的同类静默

事实 B（`--lvib-hessian model|file` 下 `--lvib-hess-step` 无效且无提示）由 §T1.2 的 md5 表**复现**。

**实现**：不新写谓词，直接复用 T1 的同源提示——`src/landscape/vib/numhess.f90` 在
`if (settings%printlevel > 0) call engine%report(env%unit)` 之后加同一行调用。
`--lvib` 恰好只建**一个** Hessian（`landscape_vib_hessian` 的无条件 `engine%hessian` 调用），
所以 `n_hess_fd` 的语义在这里最干净：`numerical` ⇒ 1，`model`/`file` ⇒ 0。
谓词**不是**读旗标字符串，而是读引擎实际使用的 provider 名（`hp%name`），满足"与'实际用了哪个 provider'同源"。

可选路线（(a) 同源 vs banner 里读 `settings%hessian_source`）选同源的额外好处：
`hessian_source` 的解释与 `new_landscape_hessian_provider` 的**工厂解析结果**永远一致，
且 `--lvib` 的回显行（既有 `tasks/vib.f90:133-136`）保持不动（本任务书要求不改已复核部分）。

I3 注入（把回显改成常量）给出 T2 的可证伪性；I4 注入证明"数错 provider"会红。

---

## T3（LOW-2）报告指针

`docs/_simplify-recon/32-stage2b-impl.md` §7 R2 引用的 `--help` 原文
（`used by an algorithm that builds one (rfo, bfgs) - the default lbfgs never does`）已在报告 35 的 T3 被改写，
本轮**在 R6 行之后新增一个订正指针块**（原文 R2 行**不删**）：

* 点名被删的原文与它不实的原因（`bfgs` 不建数值 Hessian，实测 `Hessians 0`）；
* 指向现行 `src/xhelp.f90` 的 `--lopt-hess-step` / `--lscan-hess-step` 文案；
* 指向 **36 号复核**（阶段 2b 修复轮的复核）；
* 说明 R2 里"按任务写死谓词"的做法已被本轮的 T1/T2 **同源化**取代。

另在 `docs/_simplify-recon/35-stage2b-fix.md` §0 摘要表下加了同类**后续订正块**（原文不删），
说明 §T1.3 里 `--lts` 的 `dimer`/`neb` 两条文案已被删除、`--lts`/`--lvib` 改为同源提示——
否则读者会从 35 读到已经失效的文案。这两处都是**留痕指针**，不改任何已复核的实现结论。

---

## 1. 改动清单（本轮）

| 文件 | 改动 | 性质 |
|---|---|---|
| `src/landscape/engine/engine.f90` | `n_hess_fd` 字段 + `engine_hessian` 计数 + `report_unused_hess_step` + 绑定 | **计数/打印层**（不改任何数值路径） |
| `src/landscape/tasks/ts.f90` | 删 `ts_unused_hessian_step` + banner 提示；两处 `engine%report` 后加同源提示 | **仅打印/谓词层** |
| `src/landscape/vib/numhess.f90` | `engine%report` 后加同源提示 | 仅打印层 |
| `test/unit/landscape_cli_check.py` | `check_hessian_step_used` 的 `--lts` 用例改写 + 新增 `--lts`/`--lvib` 用例 + md5 对 + 文档串 | 测试 |
| `test/unit/CMakeLists.txt` | `xtb/landscape-hess-step-used` 的注释更新（**未加/删 target**） | 注释 |
| `docs/_simplify-recon/32-stage2b-impl.md` | §7 R2 订正指针块 | 文档 |
| `docs/_simplify-recon/35-stage2b-fix.md` | §0 后续订正块 | 文档 |
| `docs/_simplify-recon/37-stage2b-fix2.md` | 本报告 | 文档 |

**未改**：`src/prog/main.F90`、`src/xhelp.f90`、`types/**`、`saddle/**`、`irc/**`、`optimize/**`、`scan/**`、
`tasks/{opt,scan,irc}.f90`（报告 35 的 T1 谓词保持原样）、`test/unit/meson.build`（test 名与参数不变）、核心层 7 个目录。
**未**动任何旗标拼写、**未**动 `--method`/`--opt`/`--ohess`（阶段 3）。

---

## 2. 验证命令汇总（可复跑）

```bash
cmake -S /home/owenchan/work_path/coding/fortran/xtb -B /tmp/xtb-p2bf2/build \
  -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"
cmake --build /tmp/xtb-p2bf2/build -j8
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p2bf2/build -R landscape
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p2bf2/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
python3 test/unit/landscape_help_check.py src/prog/main.F90 src/xhelp.f90
```

---

## 3. BC：只有 stdout 变化，输出文件逐位不变

对新旧二进制（`/tmp/xtb-p2bf/build/xtb` = 报告 35 的产物，`/tmp/xtb-p2bf2/build/xtb` = 本构建）
在同一目录下跑同样的调用并逐文件 `cmp`：

```
ts-dimer-noverify : files identical
ts-autoneb        : files identical
ts-prfo           : files identical
lvib-model        : files identical
lvib-num          : files identical
lopt              : files identical
```

stdout 的差异（只列 `(not used` / `Hessians` 行）：

```
=== ts-dimer-noverify
- (not used: dimer builds no Hessian and --lts-no-verify skips the confirmation)
+ (not used: no numerical Hessian was built by this run)     <- 位置也搬到计数之后
=== ts-autoneb
- (not used: autoneb builds no Hessian and --lts-no-verify skips the confirmation)   <- 删除（假话）
=== ts-prfo
（无差异）
=== lvib-model
+ (not used: the Hessian source 'model' has no finite differences)   <- 新增（T2）
=== lvib-num
（无差异）
```

---

## 4. 被本轮**证伪的前提**

1. **「`--lts` 的"是否消费步长"可以在运行前由方法名判定」——错。**
   `autoneb`/`string`/`gsm` 会为 `path_ts_list.xyz` 的候选几何建数值 Hessian（实测 `Hessians 1`，
   ammonia autoneb 跑到自然结束、`converged T`、exit 0）。旧前置谓词把它们标成 unused，与同一份 stdout 的
   `Hessians 1` 直接矛盾。任务书给的"禁止按方法名枚举"是对的。
2. **「父会话事实 A 的矛盾可能只是 `--lts-max-steps 3` 的中止伪像」——不成立（混杂因子被排除）。**
   自然结束的 ammonia autoneb（exit 0，无 max-steps）同样给出 `Hessians 1` 对旧提示。
   顺带实测：HCN + `--lts-max-steps 3` 现在报 `Hessians 3`（不是 0），所以父会话表里 `Hessians 0`
   的行确实混入了中止效应——这不影响本轮结论（提示已不再按方法名判定），但**不要**再用那张表的
   `Hessians 0` 反推方法是否建 Hessian。
3. **「`--lvib` 的 `--lvib-hess-step` 静默只是缺一行提示」——只是缺提示，但"可证"依赖 provider 名而不是旗标字符串。**
   实测 `model` 下 0.005/0.02 的 `hessian` md5 相同（`f334c99ecb…`），`numerical` 下不同
   （`5d56e4c9fb…` → `80eaa11e41…`）。谓词若只读 `settings%hessian_source` 字符串仍会对
   "工厂解析后实际挂的是哪个 provider"失去检验（I4 注入即演示了把 provider 维度删掉会红）。
4. **「`--lvib` 的 banner 回显行需要改」——不需要。** 既有 `tasks/vib.f90:133-136` 的两行本来就在，
   本轮只是补同源提示；BC 显示 `--lvib` 的输出文件零变化。
5. **「`Error termination. Backtrace:` 是本轮引入的」——不是**：`string`/`gsm` 在旧二进制上同样打印该行
   （`grep -c` = 1），且程序继续跑完。属既有基线现象，与本轮无关（未深究）。

---

## 5. 残留风险

| # | 项 | 说明 |
|---|---|---|
| R1 | meson 侧未执行 | 本机无 meson/ninja；本轮**未改** `meson.build`（test 名与参数不变），无新增条目要核 |
| R2 | 提示是"运行级"真话 | `--lts-method dimer --lts-no-verify` 若因预算提前停下，仍打 `no numerical Hessian was built by this run`；这是真的，但读者需理解它不是"该方法不吃这个旗标"的方法级断言（措辞已写成 run 级） |
| R3 | 仅用户显式给旗标时提示 | 与 (a) 的条件一致。`--lopt`/`--lscan`/`--lirc` 的 banner 提示**不**看旗标（报告 35 的既有行为）——两组任务在"是否要求给旗标"上不一致，属**有意**：前者是"你给的 knob 没用上"，后者是"你的算法不建 Hessian" |
| R4 | 新增 stdout 行 | `--lts` 的提示换位/改写、`--lvib model` 新增一行；输出文件零变化（§3），但以 stdout 全文做黄金比的外部工具链会看到新行 |
| R5 | `n_hess_fd` 只按 provider 名判定 | provider 名由工厂写入固定字面量（`numerical`/`model`/`file`），不是用户输入；若将来新增一个"用步长但不是 numerical"的 provider，需同时维护这里的判断 |
| R6 | 未提交 | 工作树含阶段 2b + 报告 35 + 本轮；`git status` 无 staged 文件 |

---

## 6. 测试计数

* `add_test` 条目：**未增删**（122）；`ctest -N` 总数 **207**，`-N -R landscape` **127**。
* `grep -oE 'add_test\("[^"]+"' | sort | uniq -d` → 空；meson `test('…'` 重复 → 空。
* 本轮把新断言加进既有 mode `hessused`（只改/加用例，不加 target）。
