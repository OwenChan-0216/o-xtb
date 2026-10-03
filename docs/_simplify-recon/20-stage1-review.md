## 摘要（复核结论）

**判定：有条件接受（conditional accept）。** 实现质量高、无越界、BC-4 可信，但**不应按现状提交**：有一条「新行为零测试」（D3）和一条「4 个新测试未固定环境、CI 会红」的登记缺陷。

**越界检查（全部通过）**：diff 只动 `src/prog/main.F90`、`src/xhelp.f90`、`src/landscape/*`、`test/unit/*`、设计文档；未引入 `--method`（`grep "case ('--method'"` = 0）；case 标签名单未改；`--opt`/`--ohess` 分派体与 `main.F90:630` 的 runtyp 分派未被触碰（115–1557 之间无 hunk）；核心层 0 改动；`man/` 无套件旗标（独立 grep 复核）。

**我独立复现/新发现的实质问题（不在报告 17/18/19 里）**：
1. **`--raman` 绕过 `select_runtyp`**（`set_module.f90:1121` → `set_runtyp('hess')`）：`--raman x y --lopt` **不报冲突**、`--lopt` 被静默丢弃——§17.1 的标的缺陷仍留一个 CLI 可达的洞（不是回归，是漏改）。
2. **4 个新测试跑真实计算却未固定 `XTBPATH`**：`xtb/landscape-fc-echo`/`-lirc-default-echo`/`-lts-escape-echo`/`-strict-unknown` 不在任何 `ENVIRONMENT "XTBPATH=..."` 名单里（同文件 28 条同类测试都在；meson 侧 `xtbenv` 反而设了）。CI（`fortran-build.yml:117-121`）只设 `OMP_NUM_THREADS`。
3. **大小写归一「校验侧通、消费侧不通」**：`relax_scan.f90:494` 现在接受 `'RIGID'`，但 `:500`/`scan1d.f90:170` 仍字面比较 ⇒ 库入口的 `mode='RIGID'` 静默走 relaxed 路径（`hessian.f90:236` 同理 vs `driver.f90:200`/`ts.f90:449`/`vib.f90:144`）。改前是响亮报错。
4. **零覆盖比我预期的多**：除 D3 外，5 个 `hessian_source` 存储点只 2 个被测试覆盖（`lsset/lircset/lvset` 三个归一化删掉仍全绿）；3 个 `--l*-restart` 内联 select 只 1 个覆盖；4 个 banner 只断言前缀，打印的**数值/名字**无一被断言。
5. **`--strict` 的位置无关性（`--zzzz --strict`）只有手工测量**：把判定移回循环内的「位置相关」突变仍全绿。

**回答**：**阶段 1 现在不可提交**（补 D3 echo 测试 ≈10 行 + 确认 4 条测试的 `XTBPATH`，即可提交）；**阶段 2 可以开始**（与本两项无耦合），但建议先补 D3，因为阶段 2 会再碰同一套 banner/echo 机制。

---

# 20 — 阶段 1（A 组 + B 组）独立复核报告

> 复核对象：`docs/_simplify-recon/17-stage1-impl-a.md`（A 组）、`18-stage1-impl-b.md`（B 组）、`19-stage1-validation.md`（验证），
> 规格 `11-cli-redesign.md` §8/§17，实际改动（16 个 `M` + `test/unit/landscape_help_check.py`）。
> HEAD = a845def；改动**未提交**。本轮为 **read-only 复核**（无法运行命令）：所有结论要么是源码事实（file:line），
> 要么显式标注「需运行验证」。工作目录为 `/tmp/xtb-p1/build`。

## 0. 结论

| 项 | 判定 |
|---|---|
| 交付判定 | **有条件接受**（conditional accept） |
| 现在可否提交 git | **不可**：见 H1（D3 零覆盖）与 H2（4 条新测试未固定 `XTBPATH`）。两条都可在 30 分钟内闭合 |
| 阶段 2 可否开始 | **可以**（与 H1/H2 无耦合）；但建议先闭合 H1，因为阶段 2 会复用 banner/echo 机制，否则同族欠账会叠加 |
| CRITICAL / HIGH / MEDIUM / LOW / INFO | 0 / 2 / 5 / 7 / 6 |
| 越界 | 无（§1） |
| BC-4 | 可信度**高**（强基线 + 版本串对齐，独立复算帮助集合佐证）；剩余假设见 §9 |
| M0..M7 数值回归 | 无（改动不触数值路径）；行为面变更见 M5/L3 |

---

## 1. 越界检查（逐条，全部通过）

| 约束 | 证据 | 结果 |
|---|---|---|
| 不引入 `--method` | `grep "case ('--method'" src/prog/main.F90` = 0；`test/unit/landscape_help_check.py:56 SET_S_EXTRA = "--method"` 只是把该拼写预先放进集合 S（设计 §17.4 明写） | ✅ |
| 不改 runtyp 语义 / `--opt`/`--ohess` 分派 | 首 hunk `@@ -114`，次 hunk `@@ -1558` ⇒ **115–1557 行之间无改动**，即 `xtbMain` 的 runtyp 分派（`main.F90:630`）、`lruntyp_flag` 守卫（`:491-508`）、`--opt`/`--ohess` 的 `set_opt(...)` 全部逐字未变；145 处替换的 `(typ, flag)` 配对逐条核对与旗标族一致（本次 grep 全量复核） | ✅ |
| 不动核心层 | `git diff --stat` 仅 `src/prog/main.F90`、`src/xhelp.f90`、`src/landscape/*`、`test/unit/*`、`docs/*` | ✅ |
| 不改现有旗标名 | case 标签名单未变；`--help` 选项行 175→175、unique `--` token 190→190（验证者实测）；我独立数 `src/xhelp.f90` 里 `--l*` 选项行为 **119 行**、逗号别名展开后 **124 个拼写**，与 `S(help)=124` 完全吻合 | ✅ |
| `man/` | 无需同步：`man/xtb.1.adoc` 只有原生 `--opt/--hess/--ohess`（独立 grep），**0** 条套件旗标 | ✅ |
| 新文件双注册 | `landscape_help_check.py` 在 `test/unit/CMakeLists.txt:3292-3298` 与 `test/unit/meson.build`（新 `test('landscape help coverage', ...)`）双侧登记 | ✅ |

---

## 2. §17.1 冲突检测：145 个站点的组合枚举（任务 2）

### 2.1 站点家族的隐含关系

| typ | 触发旗标（站点数） | 同 typ 合法共存 |
|---|---|---|
| `scc` | `--scc`/`--sp`、`--esp`、`--stm`、`--dipro`（tblite） | ✅ 4 个旗标互不报错（设计正确） |
| `md` | `--md`、`--metadyn`、`--siman` | ✅ |
| `hess` | `--hess`（+`--raman` 间接，见 M1） | ✅（但 `--raman` 绕过） |
| `prescc` | `--ceh`（tblite） | — |
| 单旗标 typ | `vip/vea/vipea/vomega/vfukui/grad/opt/ohess/bhess/omd/path/screen/gmd/modef/mdopt/metaopt` | — |
| 套件 | `lopt`(4 站)、`lscan`(21)、`lts`(56)、`lirc`(27)、`lvib`(11) | ✅ 同族子选项互不报错 |
| 无 runtyp | `--ljson`（设计如此） | ✅ |

**结论**：`(typ, flag)` 配对无一错位；「同 typ 无操作」规则**不产生误报**（验证者 §6.2 的反向清单 + 我的静态枚举一致）。
**但有一个真冲突被漏掉 → M1。**

### 2.2 M1（MEDIUM→建议 P1 修）`--raman` 绕过包装器

```
src/prog/main.F90:2157   case ('--raman')
src/prog/main.F90:2158      call set_elprop('raman')
src/set_module.f90:1119   case('raman')
src/set_module.f90:1121      call set_runtyp('hess')      <-- 第 146 个 set_runtyp 站点，未换
```
`set_runtyp` 的第二调用被 `set_module.f90:1034-1038` 的 `save :: set1` 静默吞掉（`raise('S',...)` → `persistentEnv%warning`）。
`select_runtyp` 只看自己的 `selected_typ`，因此：

* `--raman 0.5 1000 --lopt`：`set_runtyp('hess')` 先占锁 → `--lopt` 的 `set_runtyp('lopt')` 静默失败 → **无 `run type conflict`、`--lopt` 被丢弃**（§17.1 的标的缺陷原样保留）。
* `--lopt --raman ...`：`--raman` 被静默丢弃（与 HEAD 相同，未变差）。

**修法（1 行 + 1 测试）**：把 `main.F90:2157-2158` 改为先 `call select_runtyp(env,'hess','--raman',...)`（`set_elprop` 内部那次随后被锁吞掉，无害）。
**报告 17 §1.1 的「全部 145 处」只是 `main.F90` 口径**：全仓库还有 `set_module.f90:1121` 与 `set_module.f90:2828`（xcontrol `runtyp=`，报告 §8 已登记为范围外）两个站点未覆盖。

### 2.3 行为变更的爆炸半径（M5）

规则本体 = 「不同 runtyp ⇒ exit 1」，其**范围大于 §5.1 登记的 4 条**：任意「原生 runtyp × 另一 runtyp」都从「静默首赢」变成 exit 1，
例如 `--sp --lopt-engine bfgs`（验证者 §6.4 实测 0→1）、`--esp --lopt`、`--grad --lopt`。判定：**属 §8.1 规则的一致后果**（`man/` 未记录任何双 runtyp 组合），但**未入册**，需用户确认。

---

## 3. §17.5 5a `--strict`（任务 3）

* 实现（`main.F90:3902-3918`）：未知旗标只在循环里计数（`:1594-1601`），循环后统一判 `strict` ⇒ **位置无关**，`--zzzz --strict` 也 exit 1（代码上成立；验证者手工实测 rc=1）。
* **M5（MEDIUM，覆盖缺口）**：`xtb/landscape-strict-unknown`（`landscape_cli_py`/`landscape_cli_strict.cmake`）只跑 `--strict --zzzz` 与 `--zzzz`，
  **没有 `--zzzz --strict` 这条顺序**。因此「把判定移回循环内（用当时的 `strict` 值）」这类**位置相关**突变**仍然全绿**——而「位置无关」正是选用解析尾方案的唯一理由。补一条顺序断言即可（1 行 ARGS）。
* **L3（LOW，行为变更）**：解析尾方案下，`terminate(0)` 出口（`--help`/`--version`/`--license`/`--citation`）**会跳过**未知旗标报告（旧代码在循环内已 warn）。`xtb --zzzz --help` 现在只打帮助。

---

## 4. §17.5 5b 大小写归一（任务 4）

### 4.1 覆盖清单核对（我自己 grep 全部入口）

`grep "function .*_known|function .*from_name" src/landscape` ⇒ 11 个；`grep "case ('[a-z]" src/landscape` ⇒ 全部字符串分支。
逐条对照：

| 入口 | file:line | 归一 | 上游消费者是否大小写一致 |
|---|---|---|---|
| `landscape_settings_set_conv_level` | settings.f90:1085 | ✅ | 自身即存储点 ✅ |
| `landscape_opt_algorithm_from_name` | :1173 | ✅ | 只产整数 ✅ |
| `landscape_irc_method_from_name` | :1291 | ✅ | 只产整数 ✅ |
| `landscape_ts_method_from_name` | :1358 | ✅ | 只产整数 ✅ |
| `landscape_ts_init_mode_known` | :1434 | ✅ | **否**：`prfo.f90:955` 字面比较（见 M2） |
| `landscape_ts_ninit_known` | :1451 | ✅ | **否**：`dimer.f90:425` 字面比较（但 default 分支报错 ⇒ 失败响亮） |
| `landscape_scan_coord_from_name`（pure） | :1491 | ✅ | 只产整数 ✅ |
| `landscape_scan_mode_known` | :1547 | ✅ | **否**：`relax_scan.f90:500`/`scan1d.f90:170`/`tasks/scan.f90:137`（见 M2） |
| `landscape_conv_level_known` | :1564 | ✅ | ✅ |
| `landscape_hessian_source_known` | hessian.f90:197 | ✅ | **否**：`driver.f90:200`/`ts.f90:449`/`vib.f90:144`（见 M2） |
| `new_landscape_hessian_provider`（工厂） | hessian.f90:236 | ✅ | ✅（工厂自己解析） |
| CLI 5 个存储点 | main.F90:2309/2579/2960/3640/3719 | ✅ 全部 `landscape_lowercase` | ✅ |
| `lsset%mode`/`ltset%init_mode`/`ltset%n_init` | main.F90:2329/2766/2857 | ✅ | ✅（CLI 侧） |
| 3 处内联 `select case`（`--l*-restart`） | main.F90:2370/2940/3693 | ✅ | ✅ |

**CLI 侧无遗漏**（与报告 §1.3 一致）。**库入口侧有 M2。**

### 4.2 M2（MEDIUM）校验侧归一、消费侧未归一 ⇒ 旧的响亮拒绝变成新的静默错路

```
scan/relax_scan.f90:494   if (.not. landscape_scan_mode_known(settings%mode)) ... env%error(...)   ! 现在接受 'RIGID'
scan/relax_scan.f90:500   if (trim(settings%mode) == 'relaxed') then   ! 'RIGID' ⇒ 假 ⇒ 跳过 relaxed 前置校验
scan/scan1d.f90:170       if (trim(settings%mode) == 'rigid') then     ! 'RIGID' ⇒ 假 ⇒ 走 relaxed 分支
tasks/scan.f90:137        if (trim(settings%mode) == 'relaxed' ...)    ! 'RIGID' ⇒ 假 ⇒ 不打 fc banner
```
`hessian.f90:236`（工厂已归一）与 `optimize/driver.f90:200`（字面 `'model'`，跳过 BFGS 的 model 种子）、`tasks/ts.f90:449`（字面 `'numerical'`，跳过近零曲率收紧决策）、`tasks/vib.f90:144`（字面 `'file'`）同理。
改前：`landscape_scan_check` 与工厂都会**报错**；改后：**接受**并走另一条路——正是设计 §17.5 5b 明令要避免的「大写被接受但走另一条路径」，只是从 CLI 逃到了库入口（`landscape_scan_mode_known` 的文档注释自己写着 "for the library entry point"）。
**修法**：4 处字面比较改用 `landscape_lowercase(...)`（或让 `landscape_scan_check` 用局部小写副本）。**CLI 不可达，故 MEDIUM 而非 HIGH。**

---

## 5. §17.2 消息点名（任务 5）

* 三条消息已点名（`relax_scan.f90:539-541/569-571/573-577`，含 `2` 后缀与长度/角度单位）✅
* 旧文本全仓库 grep：`at least one step is required`、`outside 1..3` ⇒ 命中仅剩 `docs/_simplify-recon/02-cli-audit.md`（历史证据）、`11/12/14-*.md`（设计/复核记录）、`p1rev-workflow.js`（任务书）。`src/`、`test/`、`man/`、脚本 **0 命中** ✅
* 我复核了 B 组 §8.1 的「假绿」判断：`landscape_cli_error.cmake` 用 `MATCHES`；旧 PATTERN 若只含旗标名，会被 stdout 的命令行回显命中——**该结论正确**（新 PATTERN 跨消息措辞）✅

---

## 6. §17.3 banner（任务 6）

| banner | 触发条件 | file:line | 默认打印测试 | 显式抑制测试 | 值/名字断言 |
|---|---|---|---|---|---|
| D1 `--lscan-fc` | `mode=='relaxed'` ∧ ¬was_set | `tasks/scan.f90:137-146` | ✅ `landscape-fc-echo` route1 | ✅ route2/route3 | ❌ 只断言前缀 |
| D2 `--lirc-method` | ¬was_set | `tasks/irc.f90:174-178` | ✅ `-lirc-default-echo` | ✅ | ❌ 只断言前缀（`hpc` 未断言） |
| D3 `--lopt-engine` | ¬was_set | `tasks/opt.f90:121-127` | **❌ 零** | **❌ 零** | ❌ |
| D7 `--lts-escape-step` | prfo/bprfo ∧ ¬was_set | `tasks/ts.f90:189-199` | ✅ `-lts-escape-echo` | ✅ | ❌ 只断言前缀 |

* **H1（HIGH，必须闭合）**：D3 及其闸门字段 `algorithm_was_set`（`settings.f90:436` / set `main.F90:2281` / read `tasks/opt.f90:121`）**全仓库 `test/` 0 引用**——我独立 grep 确认（`grep -rn algorithm_was_set` 只有 src 3 处 + 报告/任务书）。与验证者 §6.1、父会话结论一致。**它违反本项目铁律 1**，而且设计 §17.3 的「测试」行只列了 3 条测试、正文却列了 4 类 banner ⇒ 这是**设计自身的清单不一致**导致的漏项（报告 18 未主动登记，只在 §0/§9 之外没提）。
* **M4（MEDIUM）**：4 个 banner 的断言都是**前缀子串**（`landscape_cli_check.py:1871/1905/1924`），所以「打印的数值/名字来自 settings」这一**代码注释里明写的声称不可证伪**：把 `tasks/scan.f90:139` 的 `settings%constraint_fc` 换成硬编码 `0.50_wp`（或把 `landscape_irc_method_name` 打成错的），4 条 echo 测试**仍全绿**。建议把 banner 字符串扩到含数值（如 `"[NOTICE] --lscan-fc default 0.50"`）。
* **污染机器可读输出**：banner 走 `env%unit`（= stdout），与套件既有全部 `landscape:` 打印、`env%error` 的 `-N-` 行同流（`xtb_mctc_global` 无 stderr 通道），**理由充分**；机器可读结果是**文件**（`landscape_*.json`），`read_json` 在 fc 的 3 条路线里都跑过 ✅。四类 banner 只落在套件任务上，BC-4 覆盖的 5 个原生 runtype **0 条 new NOTICE**（验证者 §2.3 独立实测）✅。
* **L2（LOW）**：banner 用 `'(a,f4.2,a)'` 打印 `constraint_fc`/`escape_step`，而这两者只有 `> 0` 的下界校验 ⇒ 库入口给 ≥10 的值会打印 `****`（CLI 不可达，因为显式给值即抑制）。

---

## 7. §17.4 `--help` 双向一致（任务 7）

### 7.1 抽取规则：我独立写了一遍（伪代码）并对照

```
S(main)  = { quoted token t of every `case (...)` label on one line : t startswith '-'
             and (t startswith '--l' or t == '--method') }
S(help)  = { tokens of every double-quoted help string that itself startswith '-',
             split on [,\s]+, keep only ^-+[A-Za-z0-9_\[] , with --[no]x → {--x,--nox} }
gate     = S(main) == S(help)
```
**“过窄假空差集”排查（我独立做的一遍）**：
1. `grep "'--l|\"--l" src/prog/main.F90` ⇒ 所有套件拼写**都在 case 标签里**（其余命中是消息文本 495-508/986 与注释 3940+）⇒ 主规则不窄 ✅
2. 多行 case 标签：`grep "case *(.*&\s*$" src/prog/main.F90` ⇒ **唯一一条是 `:630`**（`case (p_run_...)`，无引号）⇒ 逐行抽取不丢标签 ✅
3. help 侧：`grep '^\s*"--l' src/xhelp.f90` ⇒ **119 行**；其中 `:324`（4 个）、`:482`、`:513` 各含逗号别名 ⇒ 展开后 **124**，与 `S(help)=124` 逐字吻合（`--license`+`--lmo` 由 `--l` 前缀规则吸入）✅
4. 反向超集（自写更宽规则）在报告 19 §5.1，`--ljson writes nothing…` 等 4 条是**句子**不是拼写 ⇒ 脚本排除正确 ✅
5. `--method` 不在 `xhelp.f90`（独立 grep）⇒ 两侧都无，门槛不受影响 ✅
**结论**：门槛真实、不窄、可双向证伪（M6 突变 ⇒ 差集 1 ⇒ exit 1）。

### 7.2 「§8.4 的 34/5 不可复现、dialect B 给 34/6」——**成立**

我不跑脚本，但从规则可静态复算口径 B：不展开 `[no]` ⇒ help-only 侧多出字面量 `--[no]copy`/`--[no]restart` 两条（`xhelp.f90` 里确有此二拼写），而 implemented 侧多为 `--copy/--nocopy/--restart/--norestart` 四条 ⇒ **34/6**。集合 S 与口径无关 ⇒ 124/124、差集 0。报告 §8.2 与设计 R37 的订正**正确**。

---

## 8. 测试可证伪性逐条（任务 8）

| 测试 | 反向突变是否红 | 备注 |
|---|---|---|
| 6 条 conflict | ✅（验证者自注 6/6 红；A 组 M1/M2） | 断言「非零 + 点名两个旗标 + `run type conflict` + 无 `energy evaluations`」，非退出码依赖（`--lts --lopt-engine` 突变下仍非零但**不点名**）——设计得当 |
| `landscape-strict-unknown` | ✅（tail if→.false.） | 但**不覆盖位置无关性**（M5） |
| `landscape-enum-case` | ✅（A 组 M4/M5 证明 hessian/lscan 两组） | lts 组：`dimer.f90:437` default 会报错 ⇒ 必红，**结构上可证伪**；prfo 组只有 `re.search("prfo")` 这个弱 pattern，真正的判据是 `xtbts.xyz` 逐位比 ⇒ **未注入验证**（报告 M5 只覆盖 hessian_source） |
| `landscape-help-coverage` | ✅（M6 + 验证者双向注入） | 读源码，无环境依赖——**唯一环境自足的 CLI 级新测试** |
| 3 条 echo | ✅（M2/M3/M4/M5） | 有 milestone 行断言（防止 print 块前崩掉造成「无 banner 假绿」）——设计好；缺口见 M4 |
| 4 条 scan error（CLI）+ 3 条单元 message | ✅（M1：5 条红） | 断言跨措辞，不会被命令行回显命中 |
| **无测试可证伪的** | — | H1（D3）、M5（顺序）、M3（3+2 个归一化点）、M1（`--raman`） |

---

## 9. BC-4 诚实性（任务 9）

1. **覆盖是否完整**：报告 19 §2 用强基线（`git worktree` a845def + 同配置 + `xtb_version.fh` 对齐）逐 runtype 列出差异文件。**唯一未被文字证明的是「文件清单相等」**——若脚本只遍历一侧目录，另一侧多/少一个文件会被漏掉。5 个 runtype 的清单看起来是全目录枚举（含 `scoord.1..49`、`xtbmdok`、`mdrestart`、`compliance.dat`、`g98.out`），**建议在报告里补一句「两目录文件名集合相等」**（我无法读 `/tmp/xtb-p1v/bc4.sh`）。
2. **时间戳非确定性已被证明**：`xtbtopo.mol` 第二行是 `MMDDYYHHMM`+flag，两次观察值 `1003262006`/`1003261959` 直接对应运行时刻（19:59 vs 20:06）⇒ 时间派生，非确定性成立。
3. **有没有别的字段被「已知类别」放过**：被剔除的 5 类（`started/finished run on`、`random seed`、计时表、`wall-time/cpu-time/ratio`、`total power (kW/mol) (real)`）都有机制定位（`src/optimizer.f90:584` 的分母是 wall time），且**同二进制两次运行也不同**已实测；`(step)` 半边逐位相同是**物理量未被放过**的证据。**判为充分**。
4. 残余：BC-4 全部证据（`bc4.sh`）在 `/tmp`，**无法从仓库复现**；本报告只能审阅其结论与自洽性，不能重放（见 INFO-1）。

---

## 10. 零覆盖清单（宣称生效但没有任何测试能证明）

| # | 开关 / 字段 / 行为 | file:line | 现状证据 | 反向突变结果 |
|---|---|---|---|---|
| Z1 | `[NOTICE] --lopt-engine default lbfgs` banner | `tasks/opt.f90:117-127` | `test/` 0 引用 | 改 `.false.` ⇒ **115/115 仍全绿**（验证者 + 父会话实测） |
| Z2 | `landscape_opt_settings%algorithm_was_set` | `settings.f90:436`，set `main.F90:2281` | `grep -rn algorithm_was_set test/` = 0 | 同上（同一处） |
| Z3 | `--strict` 的**位置无关性**（`--zzzz --strict`） | `main.F90:3908-3918` | 只有验证者 §4.3 手工测量，无测试 | 「判定移回循环内」突变 ⇒ 仍全绿 |
| Z4 | `--lscan-hessian` 存储点归一 | `main.F90:2579` | 无 `--lscan-hessian <大写>` 测试 | 改回 `= sec` ⇒ 预计全绿（未实测） |
| Z5 | `--lirc-hessian` 存储点归一 | `main.F90:3640` | 同上 | 同上 |
| Z6 | `--lvib-hessian` 存储点归一 | `main.F90:3719` | 同上 | 同上 |
| Z7 | `--lts-restart` 内联 select 归一 | `main.F90:2940` | 无大写测试 | 预计全绿 |
| Z8 | `--lirc-restart` 内联 select 归一 | `main.F90:3693` | 同上 | 预计全绿 |
| Z9 | 4 个 banner 的**数值/名字**（`0.50`/`0.20`/`hpc`） | `tasks/{scan,ts,irc}.f90` | `ECHO_CASES` 只断言前缀 | 打印错误数值 ⇒ 仍全绿 |
| Z10 | `--raman` 的 runtyp 选择 | `set_module.f90:1121` | 无测试 | 冲突检测删除也不影响任何测试（本来就漏） |
| Z11（**既有**，非阶段 1） | `--lscan-expo` 生效性 | `main.F90:2427` → `relax_scan.f90:665` | `test/` 无 `spring_expo` 用例 | — |
| Z12（**既有**） | `--lts` band 下 `escape from a minimum:` 措辞过宽 | `tasks/ts.f90:176-181` vs `saddle/prfo.f90:780` | 报告 B §8.4 已登记、范围外 | — |

Z4–Z8 是**同一族的「存储点归一」有 10 处、只有 5 处被测试覆盖**（覆盖的：`lset%hessian_source`（M5 实证）、`lsset%mode`、`ltset%init_mode`、`ltset%n_init`、`--lscan-restart`）。报告 17 §1.3 的「覆盖完整」是**代码口径**，不是**测试口径**——两者需分开陈述。

---

## 11. 回归评估（任务 11）

* **M0..M7 已验收数字**：改动不含数值路径（无算式、无阈值、无步长）；唯一可能影响验收命令的是**冲突检测**，而所有验收命令都是单一 runtyp（同族子选项不报错）。**无回归。**
* **W0 三条缺陷**：其测试（`landscape-fix-rfo`/`-scan-xcontrol`/`-vib-thermo`）都在 115/115 内且均为单 runtyp ✅。
* **既有 101/115 测试**：两条过期断言被**方向反转**（`LBFGS`→`p_landscape_opt_lbfgs`、`Numerical`→true），有 `enum-case` 单元接管 ⇒ 不是「为绿放宽」（我核对了新期望值与 §17.5 5b 的目标一致）。
* **新风险（L3）**：`--help/--version/--license/--citation` 前的未知旗标不再报告（解析尾被 `terminate(0)` 跳过）。
* **CI（H2）**：见下。

---

## 12. H1/H2 的闭合工作量

* **H1（D3）**：`landscape_cli_check.py` 的 `ECHO_CASES` 加一组 `"lopt"`（route1 `--lopt` → banner True；route2 `--lopt-engine cg` → False），
  `test/unit/CMakeLists.txt` + `meson.build` 各加一条 `xtb/landscape-lopt-engine-echo`（约 12 行），
  并记录一次「条件改 `.false.` ⇒ 红」的反向突变。**≈20 分钟。**
* **H2（环境）**：把 4 条测试加入既有的 `ENVIRONMENT "XTBPATH=${PROJECT_SOURCE_DIR};OMP_NUM_THREADS=1"` 名单（`CMakeLists.txt:3396-3419` 追加 4 个名字，或新建一段），或说明为何不需要。**≈5 分钟。**

---

## 13. 需运行验证（我无法执行，交给上级）

1. **H2 判定（最高优先）**：
   `env -u XTBPATH OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p1/build -R 'xtb/landscape-(fc-echo|lirc-default-echo|lts-escape-echo|strict-unknown)'`
   期望：**失败**（H2 成立，CI 会红）／通过则需给出「无 XTBPATH 也能找到 param」的机制证据。
2. **H1 闭合后的反向突变**：`tasks/opt.f90:121` 的 `.not. settings%algorithm_was_set` → `.false.` ⇒ 新 `lopt` echo 测试必须**红**。
3. **M1 复现**：`OMP_NUM_THREADS=1 XTBPATH=$PWD /tmp/xtb-p1/build/xtb <h2o.xyz> --gfn 2 --raman 0.5 1000 --lopt --norestart`
   期望（当前=缺陷）：无 `run type conflict`；修后：点名 `--raman`/`--lopt`。
4. **M2 复现**：在 `test/unit/test_landscape_scan.f90` 临时加一条 `set%mode = 'RIGID'` 后调 `landscape_scan_check`，
   期望（当前=缺陷）：返回 `.true.`（校验通过）而 `scan1d` 走 relaxed 分支；`hessian_source='MODEL'` + `--lopt-engine bfgs` 同理。
5. **Z4–Z8 零覆盖确认**：分别把 `main.F90:2579/3640/3719` 与 `2940/3693` 的归一化去掉，期望 `ctest -R landscape` **仍全绿**。
6. **M4 零覆盖确认**：把 `tasks/scan.f90:139` 的 `settings%constraint_fc` 换成 `0.99_wp`，期望 `landscape-fc-echo` **仍绿**。
7. **BC-4 文件清单**：在 `/tmp/xtb-p1v/bc4/res/{p1v2,head}/<rt>.files/` 上 `ls | sort` 两侧比集合，确认无多/少文件。

## 14. 需向用户确认

1. **D4（`--lscan` 默认双向回显）是否属阶段 1**：设计 `11-cli-redesign.md:2825` 标题写「清单 D1/D2/D3/D4/D7」，`:2830` 正文只列 4 类（D1/D2/D3/D7）——**设计自相矛盾**，实施者按 4 类做并在报告 B §9 登记未实施。请裁定。
2. **§17.1 的爆炸半径**：任意「原生 runtyp × 另一 runtyp」现在都 exit 1（如 `--sp --lopt-engine bfgs`），是否接受并写入 §5.1 入册清单？
3. **D3 的处置**：补测试（建议）还是作为已知欠账提交？

## 15. 逐条表（CRITICAL / HIGH / MEDIUM / LOW / INFO）

| 级别 | 编号 | 问题 | file:line | 证据 |
|---|---|---|---|---|
| HIGH | H1 | D3 banner + `algorithm_was_set` 零覆盖（违反「每个改动都有测试」） | `tasks/opt.f90:121`、`settings.f90:436`、`main.F90:2281` | 突变 `.false.` ⇒ 115/115 全绿；`test/` 0 引用 |
| HIGH | H2 | 4 条新测试跑真实计算却不固定 `XTBPATH`（CI 只设 OMP） | `CMakeLists.txt:3307-3327`、`landscape_cli_strict.cmake`(3264-3300) vs 名单 `:3053-3082`/`:3396-3419`；CI `.github/workflows/fortran-build.yml:117-121`；meson `xtbenv`(`meson.build:213-216`) | 需运行验证 §13.1 |
| MEDIUM | M1 | `--raman` 绕过 `select_runtyp` ⇒ 静默首赢仍在 | `main.F90:2157-2158`、`set_module.f90:1119-1121` | 代码路径 + 锁语义 |
| MEDIUM | M2 | 大小写：校验侧归一、消费侧字面 ⇒ 库入口静默错路 | `relax_scan.f90:494` vs `:500`/`scan1d.f90:170`；`hessian.f90:236` vs `driver.f90:200`/`ts.f90:449`/`vib.f90:144` | 代码对照 |
| MEDIUM | M3 | 10 个归一化点只 5 个被测试（Z4–Z8） | `main.F90:2579/3640/3719/2940/3693` | 测试清单逆向 |
| MEDIUM | M4 | banner 只断言前缀 ⇒ 数值/名字声称不可证伪 | `landscape_cli_check.py:1871/1905/1924`、`tasks/scan.f90:139` | 突变推演 |
| MEDIUM | M5 | `--strict` 位置无关性无测试 | `landscape_cli_py`/`landscape_cli_strict.cmake`（ARGS 只有一种顺序） | 突变推演 |
| LOW | L1 | `xhelp.f90` 只给 7 处补「不区分大小写」，另有 ~10 个旗标已同样不区分 | `xhelp.f90:290/294/311/329/333/378/564` vs `--l*hessian`/`--l*-restart`/`--lts-init-mode`/`--lts-ninit` | 代码 + help |
| LOW | L2 | banner `f4.2` 对 ≥10 的值溢出成 `****`（库入口可达） | `tasks/scan.f90:139`、`tasks/ts.f90:192` | 格式宽度 |
| LOW | L3 | 未知旗标在 `--help/--version/--license/--citation` 前不再报告 | `main.F90:1594-1601` vs `:3902-3918`（`terminate(0)` 出口） | 控制流 |
| LOW | L4 | 冲突消息报**规范名**而非用户输入的别名 | `main.F90:2133`（报 `--scc` 当用户写 `--sp`）、`:2174`（报 `--opt` 当写 `-o`） | 调用点字面量 |
| LOW | L5 | `--gmd` 在 `set_runtyp` 失败后仍被记入 `selected_typ`（多打一条误导冲突） | `main.F90:2238-2239`、`main.F90:3972-3975`、`mctc/error.f90:41-43` | 代码 |
| LOW | L6 | 报告 17 §1.1「全部 145 处」是全**仓库**口径的话不成立（另 2 处未换） | `set_module.f90:1121`（CLI 可达）、`:2828` | grep |
| LOW | L7 | 设计 §17.3 标题 vs 正文对 D4 自相矛盾，实施按 4 类 | `11-cli-redesign.md:2825` vs `:2830` | 文档 |
| INFO | I1 | BC-4 全部证据在 `/tmp`，仓库无法复现（无脚本入库） | 报告 17 §9 / 19 §13 | — |
| INFO | I2 | BC-4 未显式声明「两目录文件清单相等」 | 报告 19 §2.2 | — |
| INFO | I3 | 仓库根有未跟踪的 `p1rev-workflow.js`（及任务书）；**不要**纳入提交 | repo root | `ls` |
| INFO | I4 | `enum-case` 的 prfo 组 pattern `"prfo"` 是弱断言（真正的判据是逐位文件比较） | `landscape_cli_check.py`/`landscape_cli_enum_case.cmake` | — |
| INFO | I5 | 冲突报错按「每个冲突子选项各一条」（`--lopt --lscan --lscan-*` ⇒ 4 条），报告 §7.6 已登记、刻意不去重 | `main.F90:3976-3980` | 设计判断 |
| INFO | I6 | `--ceh`/`--dipro` 的 runtyp 选择被 `get_xtb_feature('tblite')` 包住；本构建（tblite=OFF）下 `--ceh` 不选 runtyp ⇒ `--ceh --lopt` 不报冲突（但 `--ceh` 本身也无效果） | `main.F90:1716-1717/1842-1844` | 代码 |

## 16. 报告纪律（任务 10）

17/18 的绝大多数声称带命令 + 期望 + 实测输出，**可核性高**；缺口：
* 17 §6 与 18 §6 的 BC-4 引用 `/tmp/p1-bc4/bc4b.sh`、`/tmp/mut/run_mutation.sh`、`/tmp/p1b/*`（`*.py` 突变体）——**全部不可从仓库重放**（INFO-1）；19 §1.1 的强基线做法（worktree + 版本串对齐）是更可信的替代，但也依赖 `/tmp/xtb-p1v/bc4.sh`。
* 17 §4 的「sha256 校验」只给摘要，未贴 `sha256sum` 原始输出（19 §5.5 补了 4 个文件的原始值 ✅）。
* 「BC-4 逐位相同」在 17 里是**归一化后**，19 已升级为「只差时间戳」——两报告口径不同，19 更严，采纳 19。
* 19 §6.1 的覆盖缺口结论**完全成立**（我独立复核）。

## 17. 总判

阶段 1 的 A/B 两组实现**在 CLI 面上正确、可证伪、无越界、无数值回归**，验证者的独立复核（19）质量高且其两条「证伪前提」订正我都能复现其推理（`--lscan-method cg` 不是 exit 0；BC-4 不因 banner 改变）。**但「tester 全绿≠正确」的清单还没清完**：新增 4 个 `*_was_set` 闸门中 **1 个（D3）连同其字段完全无测试**，新增 10 个归一化点中 **5 个无测试**，1 个 CLI 可达的 runtyp 通道（`--raman`）**没接进新规则**，4 条跑真实计算的新测试**没进环境名单**。
⇒ **有条件接受：先闭 H1（20 分钟）+ 确认 H2（5 分钟），再提交 git；阶段 2 可并行开始（但建议 H1 先做，避免同族欠账叠加）。**