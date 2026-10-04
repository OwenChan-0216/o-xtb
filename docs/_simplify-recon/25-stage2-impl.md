# 25 — 阶段 2 实施报告：统一方法选择器 `--method <name>`

**范围**：CLI 重设计（`11-cli-redesign.md`）阶段 2。规格来源：§4 / §4.7（+§4.7.1）/ §4.8 / §5.1 / §6.3 / §8.4 / §8.5 / §9.1 阶段 2 / §10 C6 / §17.5。
**基座**：HEAD = `f5b070f`（阶段 1 已提交）。**构建**：`/tmp/xtb-p2/build`，`-O2 -DNDEBUG`，`WITH_TBLITE=OFF WITH_CPCMX=OFF WITH_TESTS=ON`。
**边界（任务书）**：不改 `--opt`/`--ohess` 分派；不加 §3.8 三条原生专属守卫；不写 §3.9 四个遗留文件；不做 §3.10 档位 SCF 精度。**本轮不改变任何现有命令的数值结果**。

---

## 0. 交付摘要

| 项 | 结果 |
|---|---|
| `--method` 解析/归一/取值域/过滤/别名/`auto`/4 原生出口 | **已实现** |
| `ctest -R landscape` | **120/120 通过**（阶段 1 为 118；新增 2 条：`xtb/landscape-method`、`xtb/landscape-method-native`） |
| 回归子集（`Singlepoint\|GFN\|model-hessian\|optimizer\|Argparser\|CAPI`） | **12/12 通过** |
| ctest 重名 | `uniq -d` = 0；meson `test('…')` `uniq -d` = 0 |
| 集合 S（`--l*` + `--method`）差集 | **0**（方言 A 与 B 均为 0；集合 N 计数 **30/4**、**34/6**，与 `18-stage1-impl-b.md` 登记值一致） |
| **BC-4 逐位不变** | `--sp`/`--hess`/`--ohess`/`--md` 的**全部输出文件 raw `cmp` 逐位相同**（含 `xtbtopo.mol`）；stdout 只有时间戳/种子/墙钟/行序伪影（§4） |
| 新旗标文档化 | `src/xhelp.f90` 新增 `--method NAME` 条目；`man/` 实测无套件旗标（`grep landscape\|--lopt\|--method man/` = 0 命中）⇒ 无需改 |
| 反向突变 | 10 个突变全部变红、全部还原（§5），`sha256sum -c` 通过 |

改动文件（`git diff --stat -- src test`）：

```
 src/landscape/types/settings.f90 |  24 +++
 src/prog/main.F90                | 442 ++++++++++++++++++++++----
 src/xhelp.f90                    |  14 ++
 test/unit/CMakeLists.txt         |  45 ++++
 test/unit/landscape_cli_check.py | 412 ++++++++++++++++++
 test/unit/meson.build            |  31 +++
 6 files changed, 927 insertions(+), 41 deletions(-)
```

设计文档同步：`docs/_simplify-recon/11-cli-redesign.md` §4.7 新增 **R39**（过渡期限制 + `auto` 的与阶段无关语义），+14 行。

---

## 1. 取值域核实（逐条 `file:line`，全部**实测存在**）

**最小化器（6）** — 解析点实测 `src/landscape/types/settings.f90:1197-1220`（`landscape_opt_algorithm_from_name`）：
`sd` `:1204`、`cg` `:1206`、`lbfgs` `:1208`、`bfgs` `:1210`、`diis` `:1212`、`rfo` `:1214`。
枚举 `settings.f90:80-85`（`p_landscape_opt_{sd=1,lbfgs=2,bfgs=3,diis=4,rfo=5,cg=6}`）。实现文件 `src/landscape/optimize/{sd,cg,lbfgs,bfgs,diis,rfo}.f90`。

**鞍点/TS（8）** — `settings.f90:1382-1409`：
`prfo` `:1389`、`bprfo` `:1391`、`dimer` `:1393`、`neb` `:1395`、`cineb` `:1397`、`autoneb` `:1399`、`string` `:1401`、`gsm` `:1403`。
枚举 `settings.f90:109-120`；实现 `src/landscape/saddle/{prfo,bprfo,dimer}.f90` + `src/landscape/path/{neb,cineb,autoneb,string,gsm}.f90`。

**IRC（4）** — `settings.f90:1315-1334`：
`gs` `:1322`、`hpc` `:1324`、`lqa` `:1326`、`eulerpc` `:1328`。
枚举 `settings.f90:131-134`；实现 `src/landscape/irc/{gs,hpc,lqa,eulerpc}.f90`。

**原生引擎（4 引擎 / 7 拼写）** — 别名逐字取自 xcontrol 的 `$opt engine=` 取值表 `src/set_module.f90:1898-1901`（**R41/T6 订正**：旧稿写“逐字取自 `set_module.f90:1888-1891`”**不准确**，本轮行号已因 U15 的注释右移；更重要的是下表里 `lancopt` **不是** xcontrol 键，详见下方订正）；实现映射
`src/prog/main.F90:4124-4143`（`landscape_native_engine_from_name`）：

| `--method` 拼写 | 引擎 ID | 依据 |
|---|---|---|
| `ancopt`、`rf` | `p_engine_rf` = 1（`src/setparam.f90:77`） | `set_module.f90:1898`；出口 `src/geoopt_driver.f90:148-153` |
| `lancopt`、`l-ancopt` | `p_engine_lbfgs` = 2（`setparam.f90:78`） | `set_module.f90:1899` **只认 `lbfgs`/`l-ancopt`**；`lancopt` 是**新增**的 CLI 拼写（**R41/T6 订正**，详见下表后的注）；出口 `geoopt_driver.f90:155-158` |
| `fire`、`inertial` | `p_engine_inertial` = 3（`setparam.f90:79`） | `set_module.f90:1901`；出口 `geoopt_driver.f90:169-171` |
| `pbc_lbfgs` | `p_engine_pbc_lbfgs` = 4（`setparam.f90:80`） | `set_module.f90:1900`；出口 `geoopt_driver.f90:159-166` |

> **【R41/T6 引证订正·留痕】** 上表原写“别名逐字取自 `set_module.f90:1888-1891`”、并把 `lancopt` 的依据列为 `set_module.f90:1889`。
> 这两点**都不准确**：
> 1. `:1889` 是 `case('lbfgs','l-ancopt')` —— **没有** `lancopt`；`lancopt` 不在 xcontrol 的任何拼写里
>    （`$opt engine=lancopt` 实测报 `engine 'lancopt' is not implemented` 且**不设引擎**）。所以“逐字一致”只在**数量**上
>    巧合成立（7 个拼写），集合并不相同：**去掉** `lbfgs`（设计 R21 有意；裸 `lbfgs` 归套件）、**新增** `lancopt`（设计 R9 的 CLI 专名）。
> 2. 行号已随本轮 U15 注释右移，当前为 `set_module.f90:1898-1901`。
> 订正后的说法见 `src/prog/main.F90:4116-4132` 的模块注释（同时写明了**两条差异**）。
> 暴露的评审项：复核 27 的 **L5**；本轮处置见 `28-stage2-fix-report.md` T6。

**任务默认（1）** — `auto`（=所选任务的默认）：opt `settings.f90:428`（`lbfgs`）、scan `settings.f90:546`（`'lbfgs'`）、ts `settings.f90:681`（`prfo`）、irc `settings.f90:879`（`hpc`）。

### 1.1 与设计的差异（订正）

1. **设计 §4.1 的解析点行号（`settings.f90:1119…` 等）已过期**：本轮在 `settings.f90` 前部插入了 4 个字段，全部右移。**实测行号见上**（opt `1204-1214`、irc `1322-1328`、ts `1389-1403`）。
2. **裸 `lbfgs` 不在原生表**（与设计 §4.7 一致，与上级 Q1 附注的字面表述**不一致**，见 §6 证伪前提 F1）。`--lopt --method lbfgs` 必须是**套件** lbfgs。
3. 设计 §4.1 说"25 个拼写（不含 `auto`）"= 18 套件名 + 7 原生拼写。**实测一致**（6+8+4=18；4 引擎 7 拼写）。设计**没有列不存在的名字，也没有漏**。

---

## 2. §4.7 逐行代入证明表（4 个原生出口都不落 `default`/`env%error`）

实现位置：`case ('--method')` `main.F90:2300-2315`（**只存字符串**，不调 `set_runtyp`、不写 settings）；第 0 段 `main.F90:1606`（`landscape_native_engine = 0`，在 flag 循环 `:1608` 之前）；第 2 段尾归一 `main.F90:3967-4045`；共享 setter `main.F90:4215/4253/4294/4333`。

`select case (set%runtyp)` 的两个分支结构：**原生名在第一个 `if` 被分流**（`main.F90:3968-3982`），`else` 才进套件分派（`:3983-4043`）。

| # | 命令行 | `landscape_native_engine` | 命中分支 | 调 `landscape_opt_algorithm_from_name`？ | 实测结果 |
|---|---|---|---|---|---|
| 1 | `--opt --method ancopt` | `p_engine_rf`=1≠0 | `case (p_run_opt,p_run_ohess)` → `set%opt_engine=1` | **否** | exit 0，stdout 含 `ANC micro-cycles`，无 `landscape: ` ✅ |
| 2 | `--opt --method rf` | 同 1 | 同 1 | 否 | 同上 ✅ |
| 3 | `--opt --method lancopt` | `p_engine_lbfgs`=2≠0 | 同 1 | 否 | exit 0，含 `L-ANC optimizer` ✅ |
| 4 | `--opt --method l-ancopt` | 同 3 | 同 1 | 否 | 含 `L-ANC optimizer` ✅ |
| 5 | `--opt --method fire` | `p_engine_inertial`=3≠0 | 同 1 | 否 | 含 `initial time step` ✅ |
| 6 | `--opt --method inertial` | 同 5 | 同 1 | 否 | 含 `initial time step` ✅ |
| 7 | `--opt --method pbc_lbfgs` | `p_engine_pbc_lbfgs`=4≠0 | 同 1 | 否 | 含 `current lattice:`（非周期水 exit 0）✅ |
| 8 | `--ohess --method ancopt` | 1≠0 | `set%runtyp == p_run_ohess` 命中同一 case | 否 | exit 0，含 `ANC micro-cycles`，写 `hessian`/`vibspectrum`/`compliance.dat`/… ✅ |
| 9 | `--method ancopt --opt`（反序） | 同 1 | 同 1（尾归一在两者之后） | 否 | 含 `ANC micro-cycles`；`xtbopt.xyz` 与 #1 **逐位同** ✅ |
| 10 | 501 原子 GFN-FF + `--opt --method ancopt` | 1≠0 | 同 1 | 否 | 含 `ANC micro-cycles`，**不含** `L-ANC optimizer`（`defaults.f90:42-46` 未覆盖）✅ |
| 11 | `--lopt --method ancopt` | 1≠0 | `case default` → `env%error`（**设计如此**） | 否 | exit 1，文本含 `only available with --opt or --ohess` ✅ |
| 12 | `--method ancopt`（无任务旗标） | 1≠0 | `case default` → `env%error` | 否 | exit 1，同上 ✅ |
| 13 | `--lopt --method bfgs` | 0 | `case (p_run_lopt)` → 套件 setter | 是，收 `'bfgs'` → `p_landscape_opt_bfgs` | exit 0，`landscape: bfgs minimisation` ✅ |
| 14 | `--lopt --method dimer` | 0 | 同上，但 `landscape_method_task='ts'` → mismatch | 否 | exit 1，文本含 `--lts` ✅ |
| 15 | `--opt --method bfgs` | 0 | `case (p_run_opt,p_run_ohess)` → **过渡期响亮错误** | 否 | exit 1，文本含 `--lopt` + `would have no effect` ✅ |
| 16 | `--method bfgs`（无任务旗标） | 0 | `case default` → `env%error` | 否 | exit 1，`needs a landscape run type` ✅ |

**静态核（可 `grep`）**：`grep -n "landscape_native_engine" src/prog/main.F90` 同时给出
声明行（`:246`，带 `= 0`）、`intent(out)` dummy（`:1581`）、**flag 循环前那行**（`:1606`，循环起点 `:1608`）、
第 2 段赋值（`:3968`）与使用（`:3970/3977`）。⇒ §3.11.2 的 MEDIUM-1 要求满足。

**为何第 0 段放在循环前而不是"第 2 段首行"**：解析循环内的 `env%error` 会让流程提前离开子程序，放在循环前才能保证**每条返回路径**上该值已定义（设计 §4.7 第 0 段的理由，本轮照做）。

**与 `set_runtyp` 锁的共存**：`--method` **从不**调 `set_runtyp`（`:2300-2315` 无该调用），所以锁只由 runtype 旗标消耗。实测 `--method bfgs --lopt` 与 `--lopt --method bfgs` 都 exit 0、且 `xtbopt.xyz` 逐位同；`--method ancopt --opt` 与 `--opt --method ancopt` 同上。

---

## 3. 共享 setter 与别名关系（逐对实测）

四个纯 setter（无 runtyp 副作用）`main.F90:4215/4253/4294/4333`，四个旧旗标改为调用它们（`--lopt-engine` `:2318`、`--lscan-method` `:2380`、`--lts-method` `:2643`、`--lirc-method` `:3378`）。

| 任务 | `--method` vs 旧旗标 | 断言 | 实测 |
|---|---|---|---|
| opt | `--method bfgs` vs `--lopt-engine bfgs` | 同 milestone + `xtbopt.xyz` 逐位同 | 通过（`alias-opt`） |
| scan | `--method cg` vs `--lscan-method cg` | 同 milestone + `xtbscan.log` 逐位同 | 通过（`alias-scan`） |
| ts（单端） | `--method dimer` vs `--lts-method dimer` | 同 milestone + `xtbts.xyz` 逐位同 | 通过（`alias-ts`） |
| ts（band） | `--method cineb` vs `--lts-method cineb` | 两路都 ignite + `p1.path.xyz`/`p1.xtbts.xyz` 逐位同 | 通过（`alias-cineb`） |
| irc | `--method gs` vs `--lirc-method gs` | 两路 exit 0 + `irc1.irc.log` 逐位同 | 通过（`alias-irc`） |
| 大小写 | `--method BFGS` vs `--method bfgs` | `xtbopt.xyz` 逐位同 | 通过（`alias-opt-upper`） |
| 冲突（异值） | `--method bfgs` + `--lopt-engine cg`（两个顺序） | exit 1 + 文本含 `conflicting landscape methods` 与 `--method` | 通过（`conflict-opt`、`conflict-opt-reverse`） |
| 冲突（scan/ts/irc） | `--method cg`+`--lscan-method bfgs`；`--method dimer`+`--lts-method prfo`；`--method gs`+`--lirc-method lqa` | 同上 | 通过 |
| 同值幂等 | `--method bfgs --lopt-engine bfgs` | exit 0 + 到任务 | 通过（`conflict-same`） |
| 重复旧旗标 | `--lopt-engine bfgs --lopt-engine cg` | last-wins = `cg`；与 `--method cg` 逐位同 | 通过（`repeat-engine`） |
| 重复 `--method` | `--method bfgs --method cg` | last-wins = `cg`（打印 `landscape: cg minimisation`） | 通过（`repeat-last`） |

**优先级规则（本轮实现并登记）**：`--method` 与旧旗标是**别名**，二者最后写入者参与冲突判定；**异 owner + 异值 ⇒ error**；**同 owner 重复 ⇒ last-wins**。理由见 §6 F6（同 owner 报错会使 `--lopt-engine bfgs --lopt-engine cg` 从 last-wins 变 error = 破坏性变更，不在 §10 清单）。

**按 runtyp 过滤（实测全部响亮）**：

```
--lopt   --method dimer  → exit 1 "dimer is a transition-state method; use it with --lts (or --lts-method dimer)"
--lopt   --method hpc    → exit 1 "…intrinsic reaction coordinate method; use it with --lirc"
--lscan  --method dimer  → exit 1 同上（点名 --lts）
--lts    --method bfgs   → exit 1 "bfgs is a minimisation method; use it with --lopt or --lscan"
--lirc   --method bfgs   → exit 1 同上
--lopt   --method bogus  → exit 1 "unknown landscape method 'bogus': …"
--lvib   --method bfgs   → exit 1 "cannot be used with --lvib … (use --lvib-hessian …)"
--sp     --method bfgs   → exit 1 "--method needs a landscape run type: add --lopt, --lscan, --lts or --lirc …"
--method bfgs（无任务）  → exit 1 同上
--lopt   --method ancopt → exit 1 "…only available with --opt or --ohess"
--method ancopt（无任务）→ exit 1 同上
```

**`auto`（no-op，实测）**：`--lopt --method auto` 与 `--lopt` 的 `xtbopt.xyz` **逐位同**，且 D3 `[NOTICE] --lopt-engine default` **照打**；`--lopt-engine bfgs --method auto` **不报冲突**、与 `--lopt-engine bfgs` 逐位同、**不打印**该 notice；`--lts --method auto` 与 `--lts` 的 `xtbts.xyz` 逐位同。

---

## 4. BC-4 逐位不变（vs `f5b070f` 强基线）

方法：`git worktree add --detach /tmp/xtb-p2v/head f5b070f`，同配置（`-O2`，`WITH_TBLITE=OFF WITH_CPCMX=OFF`）建 `xtb-exe`；两个二进制的 `include/xtb_version.fh` **实测已逐字相同**（均为 `6.7.1 (f5b070f73948f337775824ac8b83fe893b03441e)`，`cmake/CMakeLists.txt` 用 `HEAD`），故**无需对齐**。脚本 `/tmp/xtb-p2v/bc4/bc4.sh <tag> <exe>` 在同一工作目录路径内以两个二进制各跑 4 个原生 runtype（`--gfn 2 --norestart`；`--md` 用 `$seed 42`），收集**全部**非输入文件 + stdout + 退出码。

| runtype | 退出码 base/new | 输出文件数 | **raw `cmp` 不同文件数** | stdout 差异行 | 差异内容 |
|---|---|---|---|---|---|
| `--sp` | 0 / 0 | 3（charges, wbo, xtbtopo.mol） | **0** | 24 | 时间戳/种子/墙钟 |
| `--hess` | 0 / 0 | 7（+hessian, vibspectrum, g98.out, compliance.dat） | **0** | 28 | 时间戳/种子/墙钟 |
| `--ohess` | 0 / 0 | 9（+xtbopt.xyz, xtbopt.log） | **0** | 60 | 时间戳/种子/墙钟 + `total power (real)`（墙钟派生，`(step)` 半边逐字同） |
| `--md` | 0 / 0 | 55（49 个 scoord + mdrestart + xtb.trj + …） | **0** | 32 | 时间戳/墙钟 + ` MD:` 与最后一条 `ratio c/w` 的**行序伪影**（两个文件都在第 385 行） |

**非确定性过滤后**：`sp`/`hess` 的 stdout 差异**全部**属于时间戳/种子/计时表/`ratio c/w`；`ohess` 只剩 2 行墙钟派生的 `total power … (real)`；`md` 只剩 2 行行序伪影。**新增 banner 行 = 0**（`grep -c NOTICE` base=0 new=0，四个 runtype 全 0），`grep -c landscape` = 0。

⇒ **BC-4 通过，且比"归一化后逐位同"更强：无需归一化，全部输出文件 raw `cmp` 逐位相同。**

---

## 5. 反向突变证据（红 → 还原 → 绿）

每次：备份 `src/prog/main.F90` → 唯一替换 → `cmake --build --target xtb-exe` → `ctest -R 'landscape-method…'` → 记录红 → 还原 → 重建 → 绿。全部还原后 `sha256sum -c /tmp/p2-sha-before.txt` **通过**（main.F90 = `f341fe0a…`，settings.f90 = `c63e21e9…`，xhelp.f90 = `bff18d6c…`）。

| # | 突变（file 内容） | 变红的测试 | 实测 FAIL 文本 |
|---|---|---|---|
| M1 | `landscape_native_engine_from_name` 的 `case ('ancopt','rf')` → `engine = 0` | `xtb/landscape-method` + `-native` | `FAIL: filter-lopt-native: missing 'only available with --opt or --ohess'`；`FAIL: --opt --method ancopt exited 1` |
| M2 | 删掉 `set%opt_engine = landscape_native_engine`（改 `continue`） | `xtb/landscape-method-native` | `FAIL: --opt --method lancopt did not reach the native engine` |
| M3 | 把 climbing 副作用从共享 setter **移回** `--lts-method` 的 case | `xtb/landscape-method` | `FAIL: alias-cineb-method: the climbing image was never ignited`（**`--lts-method` 那一路仍绿** ⇒ 证明副作用必须在共享 setter 里） |
| M4 | 删掉 opt setter 的冲突检查块 | `xtb/landscape-method` | `FAIL: conflict-opt: expected a non-zero exit` |
| M5 | `landscape_method_task` 恒返回 `'opt'` | `xtb/landscape-method` | `FAIL: alias-ts-method: exit status 1`（dimer 被送进 minimiser 表） |
| M6 | 删掉 `auto` 的 no-op 分支 | `xtb/landscape-method` | `FAIL: auto-method: exit status 1` |
| M7 | 删掉 `case (p_run_opt,p_run_ohess)` 的过渡期拒绝分支 | `xtb/landscape-method-native` | `FAIL: native-reject-opt: missing 'would have no effect'` |
| M8 | `--method` 只保留**第一个**字符串（first-wins） | `xtb/landscape-method` | `FAIL: repeat-last: the task did not report 'landscape: cg minimisation'` |
| M9 | 删掉 `xhelp.f90` 的 `--method NAME` 条目（脚本读源码，无需重建） | `xtb/landscape-help-coverage` | `FAIL: dialect A/B documents no help for: --method`（S 差集 1） |
| M10 | 把 `--method` 的缺值报错改成 `continue`（`main.F90:2314-2315`） | `xtb/landscape-method` | `FAIL: filter-method-missing: expected a non-zero exit` |

**M9 是自然变红的一次真实验**：本报告首轮 `ctest -R landscape` 就是 119/120，唯一红项即 `xtb/landscape-help-coverage`，补 `xhelp.f90` 后 120/120。⇒ 集合 S 门槛确实在拦"新旗标未文档化"。

---

## 6. 我证伪的前提（本方向累计第 14 次起）

**F1（上级 Q1 附注）"原生别名以 `set_module.f90:1888-1891` 为准 ⇒ 裸 `lbfgs` 也是原生名"** —— **证伪**。
理由：`--lopt --method lbfgs` 是套件最常用调用（套件默认就是 `lbfgs`），若 `lbfgs` 进原生表，它会命中尾归一的原生分支再落 `case default` ⇒ 被拒绝。设计 §4.7 明确"裸 `lbfgs` 故意不在此表内"。⇒ 实现只取 `lancopt`/`l-ancopt`、`ancopt`/`rf`、`fire`/`inertial`、`pbc_lbfgs`（7 拼写）。原生 L-ANCopt 仍经 `lancopt`/`l-ancopt` 可达。

**F2（设计 §4.1）"解析点行号 `settings.f90:1119…`"** —— 本轮实测已过期为 `1204…`（本轮在 settings.f90 前部插入字段导致右移）。**不是设计错误，是行号随实现漂移**；报告一律用实测行号。

**F3（设计 §4.7.1）"`--opt --method ancopt` 两顺序**输出逐位同**"** —— **作为写法的前提不成立**：stdout 含 `* started run on …`、`random seed`、`program call`（含参数）与墙钟计时，**同一二进制两次运行也不逐位同**（实测 `auto` 对比时 diff 出 24 行全为此类）。⇒ 断言改为**结果文件 `xtbopt.xyz` 逐位同** + 两序都含实测 token（`ANC micro-cycles`）。这是"逐位同"的适用范围问题，不是代码缺陷。

**F4（设计 §4.7 尾归一代码）"`case (p_run_lopt, p_run_opt, p_run_ohess)` 都进套件 setter"** —— **会造出死旋钮**：阶段 2 的 `--opt`/`--ohess` 仍走原生（`main.F90:938 if (anyopt)`），而 `lset` 在 `--opt` 下**无任何读点**（`run_landscape` 仅在 `p_run_lopt` 分派块被调，`:1006`）。⇒ 经上级决策（Q1 选 (a)）改为**过渡期响亮错误**，并在 `11-cli-redesign.md` §4.7 加 **R39** 登记 + 指明阶段 3 移除。**这是有意的设计偏离，已登记。**

**F5（设计 §4.7 的 default 消息）"`--method needs a landscape run type: add --lopt, --lscan, --lts, --lirc, --lvib or --opt`"** —— `--lvib` **没有**方法选择器（`landscape_vib_settings` 无 method 字段），把它列进"合法 run type"会误导。⇒ `--lvib` 单独一条错误并点名 `--lvib-hessian`。

**F6（设计 §4.3 规则 2 字面）"setter 第二次设定不同值即报错"若套到同一旧旗标** —— 会使 `--lopt-engine bfgs --lopt-engine cg` 从 last-wins 变 error，属**破坏性变更且不在 §10 清单**。⇒ 冲突只在**不同 owner** 时触发；`--method` 自身重复保持 last-wins（上级 Q2 确认）。

**F7（设计 §4.7.1 `-native-level`）"必须 501 原子 fixture 才能证伪 pin"** —— 部分成立：`--opt --method lancopt` 在小体系上就能证伪 pin 行（默认引擎是 `rf`，pin 行删掉就出现 `ANC micro-cycles`，M2 已证）。501 原子 fixture **额外**证明"显式 CLI 覆盖 >500 默认"（`defaults.f90:42-46`），两者都保留（该 fixture 运行 2.2 s）。

**F8（设计 §4.6 的逐 runtype 专属消息）本轮未实现**：`--hess --method bfgs`、`--md --method bfgs` 等 12 条**专属**消息只由通用 `case default`（"needs a landscape run type: add --lopt…"）覆盖 —— **响亮且点名正确旗标**，但不是 §4.6 的逐条措辞。**诚实标注：未按 §4.6 逐条实现**（本轮任务书的边界只要求"不匹配时响亮报错并点名正确的旗标"）。阶段 3/4 可补。

**F9（设计 §4.2 step 0 与 `auto` 的优先级）**：`auto` **不是**原生名（不在 `landscape_native_engine_from_name` 中，返回 0），所以"原生先判"对 `auto` 无影响；`auto` 分支在 `if/else` 的第二个分支（`main.F90:3983`），实测在 4 个套件 runtype 上均可接受。设计未写 `--opt --method auto` 的行为 ⇒ 本轮实现为 no-op（`--opt --method auto` ≡ `--opt`），并在 R39 登记"`auto` 的语义与阶段无关"。

---

## 7. 复现命令

```bash
cd /home/owenchan/work_path/coding/fortran/xtb
cmake -S . -B /tmp/xtb-p2/build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"
cmake --build /tmp/xtb-p2/build -j

# 全绿 + 无重名
OMP_NUM_THREADS=1 XTBPATH=$PWD ctest --test-dir /tmp/xtb-p2/build -R landscape          # 120/120
OMP_NUM_THREADS=1 XTBPATH=$PWD ctest --test-dir /tmp/xtb-p2/build \
  -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'                            # 12/12
grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d                    # 空
grep -oE "test\('[^']+'" test/unit/meson.build | sort | uniq -d                           # 空

# 集合 S
python3 test/unit/landscape_help_check.py src/prog/main.F90 src/xhelp.f90                 # S: 0 differences（A/B）；N 30/4、34/6

# BC-4
git worktree add --detach /tmp/xtb-p2v/head f5b070f
cmake -S /tmp/xtb-p2v/head -B /tmp/xtb-p2v/head-build … && cmake --build /tmp/xtb-p2v/head-build -j --target xtb-exe
/tmp/xtb-p2v/bc4/bc4.sh base /tmp/xtb-p2v/head-build/xtb
/tmp/xtb-p2v/bc4/bc4.sh new  /tmp/xtb-p2/build/xtb
diff -r /tmp/xtb-p2v/bc4/res/base/*.files /tmp/xtb-p2v/bc4/res/new/*.files            # 0 差异
```

**未执行**：meson/ninja 本机未安装（AGENTS §4）⇒ meson 侧注册**本体未执行**，已做替代（python 检查器本体直接跑通、CMake fixture 与 meson 生成脚本产物 `diff` 逐位同、两侧测试名 `uniq -d`=0）。**未验证 meson 端到端。**
