# 19 — 阶段 1（A 组 + B 组）独立验证报告

> 验证对象：`docs/_simplify-recon/17-stage1-impl-a.md`（A 组：§17.1/§17.5）+ `18-stage1-impl-b.md`（B 组：§17.2/§17.3/§17.4）。
> 规格：`11-cli-redesign.md` §8/§17。**HEAD = a845def**（阶段 1 改动**未提交**，`git diff --cached` 为空）。
> 本文是**独立复现**：所有数字/结论都由本轮命令重新产生，**不采信报告里的注入记录**。
> 所有 xtb/ctest 带 `OMP_NUM_THREADS=1`；未跑全量 ctest；**未修改 src/ 生产逻辑**（验证用突变全部还原，§5.5 sha256 校验）。
> 报告用中文。

---

## 0. 结论摘要

| 验收项 | 判定 | 一句话依据 |
|---|---|---|
| §17.6 第 2 条 BC-4 逐位不变 | **通过（比报告更强）** | 版本串对齐后，5 个原生 runtype 的**全部输出文件 raw `cmp` 只有 `xtbtopo.mol` 的创建时间戳行不同**；stdout 差异只有计时/种子/时间戳（同二进制两次运行也不同，已证），**零内容行、零 banner** |
| §17.6 第 1 条 测试全绿 + 无重名 | **通过** | `ctest -R landscape` **115/115**；回归子集 **12/12**；CMake/meson 重名均 0 |
| §17.6 第 3 条 #20/#21/#23/#25 变红 | **通过（自行注入，非采信）** | 去掉冲突分支 → **6/6 冲突测试红**，且因"未失败/不点名旗标"而非退出码；还原后 6/6 绿 |
| §17.6 第 4 条 集合 S 差集 = 0 / N 计数 | **通过** | 两种口径 S=**124/124 差集 0**；N=**30/4** 与 **34/6**，与报告逐字一致 |
| §17.1 正反向 | **通过（含误报排查）** | 6 组正向全部 rc=1 + 点名第二旗标 + 任务未起；`--lopt-engine bfgs`/`--lopt --lopt-hessian model`/... 等**不误报** |
| §17.5 5b 大小写 | **通过** | `BFGS`/`BfGs` 与 `bfgs` 的 `xtbopt.xyz` **raw `cmp` 逐位同**；9 谓词 + 5 存储点 + 3 内联 select 覆盖无遗漏 |
| §17.3 banner | **通过但有覆盖缺口** | 4 个 banner 默认出现/显式不出现两路都对；JSON 未被污染；**但 D3（`--lopt-engine`）banner 无任何测试**（§6.1） |
| §17.2 消息点名旗标 + 旧文本清除 | **通过** | 三条消息点名旗标；旧文本全仓库 0 命中（仅任务书 `p1b-workflow.js`） |
| §17.4 `--help` 门槛可证伪 | **通过** | main 侧 + help 侧各注入一个假旗标 → 脚本 exit 1 |
| BC-2（旗标不消失） | **通过** | `--help` 选项行 **175 → 175**、unique `--` token **190 → 190**、增删 0 |

**独立发现（测试全绿但仍错/缺）：1 个覆盖缺口（D3 banner 无测试）+ 2 条对前提的证伪/订正 + 1 条噪声登记**，见 §6。

---

## 1. 方法与基线（关键：基线怎么选的）

### 1.1 强基线（本轮新建）

阶段 1 的改动**未提交**，所以 `git worktree add /tmp/xtb-p1v/head a845def` 得到的树**正好是阶段 1 之前的源码**。
在该 worktree 用**同一配置**建出 `/tmp/xtb-p1v/head-build/xtb`（强基线：**同 commit、同工具链、只差工作区里未提交的阶段 1 改动**）。

```
$ git worktree add --detach /tmp/xtb-p1v/head HEAD      # Preparing worktree (detached HEAD a845def)
$ cmake -S . -B /tmp/xtb-p1v/head-build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=OFF \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"
$ cmake --build /tmp/xtb-p1v/head-build -j 8            # Built target xtb
$ /tmp/xtb-p1v/head-build/xtb --version → "xtb version 6.7.1 (a845defedfebcea80f94f16e0e22e139dc44d400)"
$ git worktree remove /tmp/xtb-p1v/head                 # 验证完删除（repo 清洁，见 §5.5）
```

### 1.2 弱基线（父会话指定）

`/tmp/xtb-w0/build/xtb`（只读使用）。**限制（实测）**：其内嵌版本串是 `6.7.1 (24c069f1ce…)`，比 HEAD **早一个提交**（`bdd8eb8` 不在里面）——即它不是"阶段 1 之前"，而是"**阶段 1 之前 + 更早**"。任何 w0↔p1 的差异都同时混入 `24c069f→a845def` 的历史改动，**不能单独归因给阶段 1**。因此 w0 只作为**弱旁证**，结论以 §1.1 的强基线为准。

### 1.3 内嵌版本串：为什么必须归一化（可核）

`cmake/CMakeLists.txt:108-124` 用 `git rev-parse HEAD` 生成 `xtb_version.fh`：
- p1 构建目录的源码树是**脏的**，生成的头是 `6.7.1 (unknown-commit)`（`/tmp/xtb-p1/build/include/xtb_version.fh`）；
- 强基线的树是干净的，生成 `6.7.1 (a845defedfebcea80f94f16e0e22e139dc44d400)`。

这是**纯构建元数据**，且阶段 1 改动无法在同一 commit 下建出两个产物（改动未提交）。**为把差异彻底消掉**，本轮在**构建目录内**（非仓库文件）把 p1 的 `xtb_version.fh` 写成强基线的串并重建，使**两个二进制的版本串逐字相同**，从而 BC-4 可以做到**只归一化时间戳**（§2.2）。验证完已还原该头并重建。

---

## 2. §17.6 第 2 条 — BC-4 逐位不变（最重要）

方法：`/tmp/xtb-p1v/bc4.sh <tag> <exe>`。5 个原生 runtype 在**同一目录路径** `/tmp/xtb-p1v/bc4/work` 内运行（`program call`/`coordinate file` 行同源），只替换二进制。收集**所有**非输入文件 + stdout + stderr + 退出码。`--md` 用 `$seed 42` 固定随机数。

5 个运行：`--sp`、`--hess`、`--ohess normal`、`--md`，均 `--gfn 2 --norestart`。

### 2.1 强基线（版本串对齐前）：差异只有版本串 + 时间戳

| runtype | 逐位相同 | 差异文件 | 差异内容 |
|---|---|---|---|
| `--sp` | charges/wbo | `xtbtopo.mol` | 内嵌版本串 |
| `--hess` | charges/compliance.dat/g98.out/**hessian**/vibspectrum/wbo | `xtbtopo.mol` | 内嵌版本串 |
| `--ohess` | charges/compliance.dat/g98.out/**hessian**/vibspectrum/wbo | `xtbtopo.mol`/`xtbopt.xyz`/`xtbopt.log` | 内嵌版本串（能量/gnorm 数值逐字相同，只换 `(...)` 里的 commit） |
| `--md` | charges/mdrestart/scoord.1..49/wbo/xtbmdok | `xtbtopo.mol`/`xtb.trj` | 内嵌版本串 |

`xtbopt.xyz` 唯一差异：`energy: -5.070544427069 gnorm: 0.000152211991 xtb: 6.7.1 (…)` —— **能量与梯度范数逐位相同**，只差 commit 串。

### 2.2 强基线（版本串**对齐后**）：唯一差异是 `xtbtopo.mol` 的时间戳行

| runtype | raw `cmp` 结果 |
|---|---|
| `--sp` | 只有 `xtbtopo.mol` DIFF，其余（charges/wbo）逐位同 |
| `--hess` | 只有 `xtbtopo.mol` DIFF（`hessian`/`vibspectrum`/`g98.out`/`compliance.dat`/charges/wbo 全同） |
| `--ohess` | 只有 `xtbtopo.mol` DIFF（含 `xtbopt.xyz`/`xtbopt.log` 全同） |
| `--md` | 只有 `xtbtopo.mol` DIFF（含 `xtb.trj` + 49 个 `scoord.*` 全同） |

```
$ diff p1v2/sp.files/xtbtopo.mol head/sp.files/xtbtopo.mol
2c2
<           10032620063D
---
>           10032619593D
```

时间戳 = `MMDDYYHHMM`+flag，每次运行不同（`100326 2006` vs `100326 1959`）。**除该时间戳外，5 个原生 runtype 的每个输出文件都 `raw cmp` 逐位相同。**

### 2.3 stdout 逐行判定（版本串对齐后的 raw diff）

对每个 runtype，raw stdout diff 的**全部**差异行只属于以下 7 类，且**每一类都实测"同一二进制两次运行也不同"**（`--hess` 两次跑，diff 38 行，种类完全相同）：

| 类别 | 例 | 判定 |
|---|---|---|
| `* started run on …` / `* finished run on …` | `2026/10/03 at 19:59:15.759` | **非确定性时间戳**（同二进制两次不同） |
| `random seed : N` | `570579470` vs `2065596164` | **非确定性 RNG**（`--md` 因 `$seed 42` 无此差异） |
| 计时表 `… min, … sec ( …%)` | 7 行 | **非确定性墙钟** |
| `* wall-time:` / `* cpu-time:` / `* ratio c/w:` | — | **非确定性墙钟** |
| `total power (kW/mol): … (real)` | `-381.4570` vs `-329.6268` | **墙钟派生**：`src/optimizer.f90:584` `(etot-estart)*autokJ/timer%get()`，除数是 wall time；`(step)` 半边 `-0.1058942` 逐位相同（分母是整数 iter，是物理量） |

**新增 banner 行：0 条。** `grep -c NOTICE p1/*.stdout` 全 0（§6.3）。**"只在 p1 出现、不属于上述 7 类"的行：0 条**（`comm -13` 过滤后为空）。

⇒ **对 BC-4 覆盖的 5 个原生 runtype，阶段 1 没有产生任何新 banner，也没有任何意外内容改变。** 这与父会话的预期（"新增 banner 会改变 stdout"）**相反**：B 组的 4 个 `[NOTICE]` 只落在**套件任务**（`--lopt/--lscan/--lts/--lirc`）上。

> 附：版本串**未对齐**时，`--hess` 的对称性 banner（C 代码 `symmetry_i.c` 打印）会相对 Fortran unit-6 移位数行——这是**缓冲边界伪影**。版本串对齐后该伪影消失；且用 `GFORTRAN_UNBUFFERED_ALL=1` 重跑，`--hess` stdout 归一化后 **0 差异**（实测）。两组证据一致：不是内容改变。

### 2.4 弱基线（w0）旁证

w0 vs p1：5 个 runtype 的**文件全部逐位相同**（只有版本串/时间戳不同）；stdout 只有上述类别 + 一个行序伪影。结论与强基线一致，但**归因强度弱**（§1.2）。

---

## 3. §17.6 第 1 条 — 测试全绿 + 无重名

```
$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p1/build -R landscape
100% tests passed, 0 tests failed out of 115          # 阶段 1 前 101 → A 组 109 → B 组 115

$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p1/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
100% tests passed, 0 tests failed out of 12

$ grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d     # 空
$ grep -oE "test\('[^']+'" test/unit/meson.build | sort | uniq -d             # 空
$ ctest -N -R landscape | tail -1  →  Total Tests: 115
```

阶段 1 新增的 14 条测试全部存在且命名唯一：
`landscape-runtype-conflict` / `-suboption-conflict` / `-conflict-reversed` / `-lts-lirc` / `landscape-opt-hess-conflict` / `-vib-temp-conflict` / `landscape-strict-unknown` / `landscape-enum-case` / `landscape-scan-step-zero` / `-coord2-flag` / `landscape-help-coverage` / `landscape-fc-echo` / `-lirc-default-echo` / `-lts-escape-echo`。

---

## 4. §17.6 第 3 条 — #20/#21/#23/#25 可证伪性的独立复核（自己注入）

**不采信报告的注入记录**。所有突变：`cp` 备份 → 改一行（断言模式在文件里唯一出现）→ 重建 → 跑指定 ctest → 还原 → `sha256sum` 校验 → 重建 → 复跑绿。

### 4.1 冲突检测（覆盖 #20/#21/#23/#25）

突变：`src/prog/main.F90` 的 `select_runtyp` 冲突分支条件 `else if (selected_typ /= typ) then` → `else if (.false.) then`（= 阶段 1 之前"首个旗标静默获胜"）。

```
$ ctest -R 'xtb/landscape-runtype-conflict$|…-suboption-conflict$|…-conflict-reversed$|…-lts-lirc$|…-opt-hess-conflict$|…-vib-temp-conflict$'
0% tests passed, 6 tests failed out of 6
  106 xtb/landscape-runtype-conflict
  107 xtb/landscape-runtype-suboption-conflict
  108 xtb/landscape-runtype-conflict-reversed
  109 xtb/landscape-runtype-lts-lirc
  110 xtb/landscape-opt-hess-conflict
  111 xtb/landscape-runtype-vib-temp-conflict
```

**因正确原因红**（`--output-on-failure`）：
```
the run type conflict '--lopt --lscan' did not fail                         # #20 → exit 0
'--lts --lopt-engine bfgs' does not name its first flag                     # #23 → 非零但不是冲突
```
第二行尤其关键：`--lts --lopt-engine bfgs` 在突变下**仍非零**（water 上 TS 搜索失败），测试**因此不靠退出码**，而是要求点名 `--lts`/`--lopt-engine` + `run type conflict` + 无任务启动 ⇒ 报的 §7.1 订正成立，且测试非空洞。

还原后：`6/6 Passed`。`sha256(main.F90)=d889cbee…`（与突变前一致）。

### 4.2 §17.2 消息可证伪

突变：`src/landscape/scan/relax_scan.f90` 三条消息去掉旗标名（`needs --lscan-atoms`→`is missing an atom list for` 等）。
```
$ ctest -R 'xtb/landscape-scan$|…-nstep-missing$|…-atom-range$|…-step-zero$|…-coord2-flag$'
5 tests failed out of 5      # 1 单元 + 4 CLI
```
还原后 5/5 绿；`sha256(relax_scan.f90)=e2dcaf35…` 一致。

### 4.3 §17.5 5a `--strict` 可证伪

突变：`main.F90` 解析尾 `if (strict) then call env%error(...)` → `if (.false.) then`（未知旗标永不致命）。
```
$ ctest -R xtb/landscape-strict-unknown
***Failed
CMake Error at landscape_cli_strict.cmake:11 (message): --strict --zzzz was accepted
```
还原后绿。另测**顺序无关**（解析尾方案的附带收益）：
```
--strict --zzzz --sp  rc=1   --zzzz --strict --sp  rc=1   --zzzz --sp  rc=0   # 三者 Unknown option 各 1 条
```

### 4.4 §17.4 `--help` 门槛可证伪（**非侵入**：脚本读文件路径）

`landscape_help_check.py <main> <help>` 可直接喂改过的副本，无需改仓库：
```
main 侧注入 --lzzzz case   → S(main)=125 S(help)=124 difference=1 → script exit 1
help 侧给副本加 --lnonexistent → S(main)=124 S(help)=125 difference=1 → script exit 1
原文件                     → difference=0 → script exit 0
```

### 4.5 §17.3 banner 的可证伪性

- D1（`--lscan-fc`）：突变 `tasks/scan.f90` 的 banner 条件为 `.false.` → `xtb/landscape-fc-echo` **红**。还原后绿。
- D3（`--lopt-engine`）：突变 `tasks/opt.f90` 的 `if (.not. algorithm_was_set)` → `.false.` → **`ctest -R landscape` 仍然 115/115 全绿** ⇒ **D3 无测试**（§6.1）。

### 5.5 还原校验（全部通过）

| 文件 | 突变前 sha256 | 还原后 |
|---|---|---|
| `src/prog/main.F90` | `d889cbee7734fb32c4e01bd3bd8ae05edebefb8c9385f911a228bbe0c99631a2` | 一致 |
| `src/landscape/tasks/opt.f90` | `c52e19c1c1a756b0b8192ce56c0bc5cd42a4afd6319a8ab8cd87f1ef361a8db0` | 一致 |
| `src/landscape/tasks/scan.f90` | `7a8df7383e63e4c8e402ae415b8aa57e7c66bafa0b684b98dddf78b5fb60970e` | 一致 |
| `src/landscape/scan/relax_scan.f90` | `e2dcaf353561cba094a48d4f4c17fd5070f0efea6bee42c426f6b4491178ef09` | 一致 |

`git status --porcelain` = 阶段 1 的 16 个 `M` + 3 个 `??`（`17/18-*.md`、`landscape_help_check.py`、任务书 `p1b-workflow.js`），**无多改**。`git diff --cached` 空。最终态复跑：`ctest -R landscape` 115/115、回归子集 12/12。

---

## 5. §17.6 第 4 条 — 集合 S / N

```
$ python3 test/unit/landscape_help_check.py src/prog/main.F90 src/xhelp.f90      # exit 0
dialect A: S(main) = 124, S(help) = 124, difference = 0
dialect A: N(implemented, undocumented) = 30
dialect A: N(documented, unimplemented) = 4
dialect B: S(main) = 124, S(help) = 124, difference = 0
dialect B: N(implemented, undocumented) = 34
dialect B: N(documented, unimplemented) = 6
PASS: set S is documented by `--help` in both dialects
```

S 的 124 = **122 纯套件** + `--license` + `--lmo`（前缀 `--l` 规则吸进来）。N 与审计 §2.2/§2.3 逐字一致（A 口径）。**§8.4 的"34/5"不可复现**，可复现的是 A 口径 30/4 与 B 口径 34/6——与报告 §8.2 一致。

### 5.1 独立实现一个粗版抽取器比对（"S 规则是否过窄造出假空差集"）

自写（不依赖脚本）：主程序用**括号配平、case-insensitive 的 `case` 标签扫描**取全部拼写；再用一个**更宽**的规则（正文/消息里所有 `-` 开头的引号串）交叉验证。
```
case-labels 总 230, suite 124            # 与脚本一致
"任意 - 引号串" 里 suite 多出 4 个：
  --ljson writes nothing without a landscape run
  --lopt --lscan
  --lscan-coord/--lscan-atoms for a scan of the landscape suite
  --lts --lopt-engine bfgs
```
这 4 个都是**消息文本里的句子**（含空格），**不是独立拼写**；脚本只读 `case` 标签，正确地排除它们。`if (... == '--l*')` 形式：**0 个**。⇒ **没有任何套件旗标实现于 `case` 标签之外**，脚本的主规则**不窄**，差集为空是真实的。

### 5.2 抽取规则语义核对（合成 fixture）

构造精简 main/help：main 有 `case ('--lalpha','--lbeta')`、`case ("--lgamma")`、`case ('--lzno','--lnzno')`；help 有 `--lalpha, --lbeta`、`--lgamma`、`--lzno`、以及一行**不以 `-` 开头的正文**提到 `--lbeta`。
```
结果：S(main)=5, S(help)=4, difference=1, implemented-undocumented=--lnzno  → exit 1
```
⇒ 逗号别名会拆开、双引号会认、**正文行被忽略**（`--lbeta` 未被误当文档）——与脚本打印的规则一致。
`[no]` 展开用第二个 fixture（main `--lzz/--nolzz`，help `--[no]lzz`）验证：**A 口径差集 0；B 口径差集 1**（字面 `--[no]lzz`）——与文档语义完全一致。

---

## 6. §17.1 正反向 + 误报排查（误报是最危险的回归）

`run` 打印：退出码 / `run type conflict` 行数 / `landscape engine: energy evaluations` 行数（0 ⇒ 未起任务）。

### 6.1 正向（应报错）

| 调用 | rc | conflict | started |
|---|---|---|---|
| `--lopt --lscan` | 1 | 1 | 0 |
| `--opt --hess` | 1 | 1 | 0 |
| `--lts --lirc` | 1 | 1 | 0 |
| `--lts --lopt-engine bfgs` | 1 | 1 | 0 |
| `--hess --lvib-temp 400` | 1 | 1 | 0 |
| `--lscan --lopt`（倒序） | 1 | 1 | 0 |
| `--lopt-engine bfgs --lscan`（隐含+显式） | 1 | 1 | 0 |
| `--lopt --lscan --lscan-coord … --lscan-atoms … --lscan-nstep …` | 1 | 4 | 0 |
| `--md --lopt` | 1 | 1 | 0 |

### 6.2 反向（**不得误报**）

| 调用 | rc | conflict |
|---|---|---|
| `--lopt` | 0 | 0 |
| `--lopt-engine bfgs`（无 `--lopt`，隐含 runtyp） | 0 | 0 |
| `--lopt --lopt-hessian model` | 0 | 0 |
| `--lopt --lopt-level tight` | 0 | 0 |
| `--lscan --lscan-method cg --lscan-coord … --lscan-atoms …` | 0 | 0 |
| `--lopt-engine bfgs --lopt`（倒序，同 typ） | 0 | 0 |
| `--lopt --lopt-engine bfgs --lopt-level tight` | 0 | 0 |
| `--lvib --lvib-temp 400 --lvib-step 0.01` | 0 | 0 |
| `--hess --ljson` / `--sp --ljson` / `--ljson` | 0 | 0 |

**"同 typ 无操作"规则无误报**（全部反向项 rc=0）。

### 6.3 两条对前提的订正（file:line 可核）

1. **`--lscan-method cg` 单独调用不是 exit 0**（任务书 §5 把它列进"仍 exit 0"）：它隐含 `lscan` runtyp，而 `lscan` 无坐标 → §17.2 的坐标错误，rc=1。**不是冲突误报**：
   ```
   $ xtb water.xyz --gfn 2 --lscan-method cg
   -1- landscape_scan_check: the distance coordinate needs --lscan-atoms 1,2 …; index 0 is invalid   (无 conflict)
   ```
   与报告 §7.1 对 #23 的订正同类：**"隐含 runtyp"任务的失败可能来自任务本身，而不是旗标处理**。`--lscan-method cg` **配全套坐标**才是 rc=0（已实测）。

2. **`--sp --lopt-engine bfgs` 现在 exit 1 + 冲突**（`--sp` = `scc` runtyp，`src/prog/main.F90:2132 case ('--scc','--sp')` → `select_runtyp(env,'scc','--sp',…)`）。这**不在 §8.1 的"最常见调用"清单**里，但**是 §17.1 规则的直接后果**（两个不同 runtyp）——判为"规则一致、清单不全"，登记而非阻断。

### 6.4 噪声登记

一个逻辑冲突会为**每个**冲突任务子选项各报一次（`--lopt --lscan` + 2 个子选项 = 4 条），报告 §7.6 已登记为行为细节。实测确认：信息不丢（每个被拒旗标都点名），根因（`-1-`）在最后一行。

---

## 7. §17.5 5b 大小写 + `from_name` 覆盖

### 7.1 逐位同（独立复现，修正了本轮第一版自身的引号 bug 后才有效）

| 组 | 与 `bfgs`/`tight`/`model` 比 | 结果 |
|---|---|---|
| `--lopt --lopt-engine BFGS` | `xtbopt.xyz` | **IDENTICAL** |
| `--lopt --lopt-engine BfGs`（混合） | | **IDENTICAL** |
| `--lopt --lopt-level TIGHT` | | **IDENTICAL** |
| `--lopt --lopt-hessian MODEL` | | **IDENTICAL** |

值与任务核对（`--lopt-hessian MODEL` → 任务打印 `Hessian source: model` 小写；`--lscan-mode RIGID` → `landscape: rigid scan`；`--lts-ninit FORCE` → `dimer initial axis: force direction`）。

### 7.2 `from_name` / `_known` 入口全量 grep（覆盖无遗漏）

`grep -rn "function .*from_name\|function .*_known" src/` 在**核心层**只有 `src/mctc/mctc_strings.f90:lowercase`（工具，不是套件枚举）。套件枚举入口共 **9 个谓词**：`landscape_opt_algorithm_from_name`(settings.f90:1173)、`landscape_irc_method_from_name`(:1291)、`landscape_ts_method_from_name`(:1358)、`landscape_scan_coord_from_name`(:1491)、`landscape_conv_level_known`(:1564)、`landscape_scan_mode_known`(:1547)、`landscape_ts_init_mode_known`(:1434)、`landscape_ts_ninit_known`(:1451)、`landscape_hessian_source_known`(hessian.f90:197)。
- `landscape_irc_method_known`(:1313) / `landscape_ts_method_known`(:1388) **委托**给已归一的 `from_name`（`known = from_name(name) /= 0`）⇒ 覆盖。
- **5 个存储点**（`l*%hessian_source`）：`grep "hessian_source *=" main.F90` 全部包 `landscape_lowercase`（2309/2579/2960/3640/3719），**无一处裸赋值**。
- `lsset%mode`(2329)、`ltset%init_mode`(2766)、`ltset%n_init`(2857) 亦归一。
- 3 处内联 `select case`（`--l*-restart`，2369/2938/3689… 实为 2370/2940/3693）用 `landscape_lowercase(sec)`。
⇒ **覆盖完整**，与报告 §1.3 一致。

---

## 8. §17.3 banner + JSON

| 触发 | 默认 → banner | 显式 → banner |
|---|---|---|
| `--lopt`（无 `--lopt-engine`） | **1** | `--lopt-engine cg` → **0** |
| `--lscan` relaxed（无 `--lscan-fc`） | **1** | `--lscan-fc 0.05` → **0**；`--lscan-mode rigid` → **0** |
| `--lts --lts-method prfo`（无 `--lts-escape-step`） | **1** | `--lts-escape-step 0.3` → **0** |
| `--lirc`（无 `--lirc-method`） | **1** | `--lirc-method GS` → **0** |

（注：`--lirc --lirc-method hpc` 显式给值也是 0——`method_was_set` 判据是"给过旗标"，不是"值≠默认"，符合 §17.3 规则。）
banner 是 2 行（第 2 行缩进续行，不带二次 `[NOTICE]`），落在 `printlevel > 0` 块内。

**JSON 未被污染**：`--lopt --ljson` / `--lscan --ljson` 均 rc=0，生成 `landscape_opt.json`/`landscape_scan.json`，`json.load` 成功（10 键），且**文件内 `NOTICE` 命中 0**；`NOTICE` 只在 stdout（各 1 条）。

---

## 9. §17.2 消息 + 旧文本清除

三条 `-1-` 实测：
```
needs --lscan-atoms 1,2 (atom indices are 1-based, 1..3); index 0 is invalid
coordinate 1 has nstep = 0; set it with --lscan-nstep <n>
coordinate 1 has a zero step size; set it with --lscan-step <value> (degree)
```
旧文本全仓库 grep（排除 `.git` 与两份 recon 文档）：`outside 1..3` / `at least one step is required` → **0 命中**（只命中任务书 `p1b-workflow.js`）。测试 pattern 已同步：`test/unit/CMakeLists.txt:861/867/873/879` 与 `meson.build:376/381/387/392`。

---

## 10. 横向排查（别处引用旧文本/旧默认）

| 位置 | 命中 | 处置 |
|---|---|---|
| `man/xtb.1.adoc` 的 `landscape|lopt|lscan|lirc|lvib|--method` | **0**（`grep -c`=0） | 不需同步（与 A 组 R36 一致） |
| `src/`、`test/` 里的旧 scan 文本 | 0 | 已清 |
| `.github/workflows/fortran-build.yml` 的 `lts` 命中 | 2 处均为 YAML `defaults:` 子串（假命中） | 无 CI 引用 |
| `xhelp.f90` `not case-sensitive` | 9 条（2 条既有 solvent + **7 条新增**：290/294/311/329/333/378/564） | 与报告一致 |
| BC-2：`--help` 选项行 / unique `--` token | **175→175 / 190→190，增删 0** | `--help` diff 只有 7 处文字 + 1 处 `normal termination` 行序伪影 |
| `p1b-workflow.js`（未跟踪任务书） | 引用旧文本 | 非交付物，不改 |

---

## 11. 独立发现（测试全绿但仍缺/仍错）

### 6.1 【覆盖缺口 · 中等】D3 banner（`--lopt-engine` 默认）无任何测试

- 现象：突变 `src/landscape/tasks/opt.f90:121` 的 `if (.not. settings%algorithm_was_set)` 为 `.false.`（banner 永不打印），`ctest -R landscape` **仍 115/115 全绿**。
- `grep -rn 'lopt-engine default|NOTICE.*lopt' test/` → **0 命中**。`ECHO_CASES`（`landscape_cli_check.py:1868`）只有 `fc`/`lirc`/`lts` 三组。
- 连带：`algorithm_was_set` 字段（`settings.f90:436`）**只**被这个 banner 读取（`grep` 全仓库仅 3 处引用），所以该字段 + 其两个 set 点（`main.F90:2281`）也**无测试**。
- 影响：§17.3 的 D3 需求（"与 `--opt` 旧默认不同"要回显）**实现正确但不可证伪**——review 若按"每项改动都有反向突变测试"的门槛，这是一条 **blocker 级覆盖债务**（与 M3/M4/M6 反复出现的"死旋钮/无测试默认"同族）。
- 修复成本：给 `ECHO_CASES` 加一组 `lopt`（默认 `--lopt` 有 banner / `--lopt-engine cg` 无），并给一条反向突变记录。**未由本轮修复**（验证者不改 `src/` 生产逻辑；改动测试也超出"独立验证"范围）。

### 6.2 【证伪前提】`--lscan-method cg` 单独调用 **不是** exit 0

见 §6.3(1)。任务书 §5 与 A 报告 §5 的对照表把 `--lscan-method cg` 归入"仍 exit 0"；实测 rc=1（坐标缺失的 §17.2 错误，非冲突）。**A 报告 §5 表里其实只测了 `--lopt-engine bfgs`，没测 `--lscan-method cg`**——该对照项在报告与任务书里都是推断，未实测。

### 6.3 【证伪前提】BC-4 的 stdout 不因 B 组 banner 改变

见 §2.3。父会话预期"新增 banner 行会改变 stdout"；实测原生 runtype **0 条 new banner**（报告 §8.3 已纠正，本轮从独立基线复现）。

### 6.4 【未入册的行为变更】`--sp --lopt-engine bfgs` 由 exit 0 变 exit 1

见 §6.3(2)。属 §17.1 规则一致后果，但不在 §8.1 的登记清单。

### 6.5 【行为细节】一个逻辑冲突报 N 条

见 §6.4。非缺陷，登记。

---

## 12. 未验证 / 限制（凡无法核的都写明）

- **meson 侧未在 meson/ninja 下执行**（本机无 meson/ninja，AGENTS §4）。已做替代：meson 与 CMake 测试名均唯一（`uniq -d`=0）、`landscape_help_check.py` 与 `check_echo` 的 python 检查器**本体已直接执行通过**。**未验证** meson 测试的端到端行为。
- **BC-4 的强结论依赖"版本串对齐"**：未对齐时必须归一化内嵌 commit（§1.3），且 `xtbtopo.mol` 时间戳永远不同；这两个都是构建/时间元数据，**机制已定位到 `cmake/CMakeLists.txt:108-124` / `xtbtopo` 写盘点**，不是阶段 1 代码路径。
- **w0 弱基线**：内嵌版本串是 `24c069f`（早一个提交），差异混入历史改动 ⇒ 只作旁证。
- **未做**：3 个以上互斥 runtype（`--lopt --lscan --lts` → 2 条冲突）无专门测试（报告 §8 已登记）。
- **未做**：`--lts` band 方法（neb/cineb/autoneb/string/gsm）下 `[NOTICE] --lts-escape-step` 与既有 `escape from a minimum:` 行不一致（报告 §8.4 登记，属范围外）。
- 本轮对 `src/` 的临时突变**全部还原**并 sha256 校验（§5.5）；`git worktree` 已删除，repo 无残留。

---

## 13. 可核证据索引

```
# 强基线
git worktree add --detach /tmp/xtb-p1v/head HEAD ; cmake -S . -B /tmp/xtb-p1v/head-build … ; cmake --build …
# BC-4（同目录路径、换二进制、$seed 42 固定 MD）
/tmp/xtb-p1v/bc4.sh <tag> <exe>            # → /tmp/xtb-p1v/bc4/res/<tag>/<rt>.{files,stdout,exit}
# 测试
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p1/build -R landscape                       # 115/115
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p1/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'   # 12/12
# 集合 S/N
python3 test/unit/landscape_help_check.py src/prog/main.F90 src/xhelp.f90               # exit 0
# 突变（每次：备份→唯一替换→重建→ctest→还原→sha256→重建）
#   main.F90 select_runtyp 冲突分支→.false.   → 6 冲突测试红
#   relax_scan.f90 三条消息去旗标             → 5 测试红
#   main.F90 解析尾 if(strict)→if(.false.)    → strict-unknown 红
#   tasks/opt.f90  D3 banner 条件→.false.     → 115/115 仍全绿（F-V1）
#   tasks/scan.f90 D1 banner 条件→.false.     → fc-echo 红
# 反向超集 grep（S 不窄）
python3 - <<'PY'  (见 §5.1)  PY
```

`git diff --stat -- src test man`（未变，见 §5.5）：16 个 `M`；`man/` 无改动；未跟踪：`17/18-*.md`、`test/unit/landscape_help_check.py`、`p1b-workflow.js`。`git diff --cached` 空。

---

### 验证者总判

阶段 1（A 组 + B 组）的**功能实现与本报告声明的数值结论全部可独立复现**：BC-4 逐位不变（比报告的"归一化后"更强，达到"只差时间戳"）、测试全绿无重名、四条标的可证伪、集合 S 门槛可双向证伪、大小写归一覆盖完整、banner 默认/显式两路正确、旧文本清除干净。
**唯一需要在交付前处理的欠账是 §11.1（D3 `--lopt-engine` 默认 banner 无测试——去掉它整个 landscape 套件仍然全绿）**，其余为已登记的噪声/范围外项与本报告订正的两条推断前提。
