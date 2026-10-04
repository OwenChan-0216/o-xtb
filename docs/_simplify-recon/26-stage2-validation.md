# 26 — 阶段 2 独立验证报告：统一方法选择器 `--method <name>`

> **性质**：**独立验证**。本会话**未修改任何生产逻辑**（`src/` 仅在注入实验中临时改写并逐次还原，
> 见 §8 与末尾的 `sha256sum -c` 证据）。工作区 = `f5b070f` + 阶段 2 未提交改动。
> **独立构建**：`/tmp/xtb-p2v/new`（本会话自建，`-O2 -DNDEBUG`，`WITH_TBLITE=OFF WITH_CPCMX=OFF
> WITH_TESTS=ON`），**强基线** `/tmp/xtb-p2v/base-build`（本会话 `git worktree add --detach
> /tmp/xtb-p2v/base f5b070f` 自建）。未触碰 `/tmp/xtb-w0`、`/tmp/xtb-land`、`/tmp/xtb-p1`、`/tmp/xtb-p2`。
> **纪律**：`OMP_NUM_THREADS=1`；未跑全量 ctest（只 `-R landscape` 与回归子集）；未 `find /`；未提交 git。
> **本报告不复述 25 号报告**：所有数字都是本会话自己跑出来的原文。
>
> **被验证的文件指纹（= 25 号报告所验证的状态，本会话实测一致）**：
> `src/prog/main.F90` `f341fe0a…`、`src/landscape/types/settings.f90` `c63e21e9…`、`src/xhelp.f90` `bff18d6c…`。

---

## 0. 结论

**通过，可提交（在下列 3 条 INFO 与 2 条 LOW 被接受的前提下）。** 阶段 2 的 6 项承诺
（解析 / 归一 / 取值域 / 按 runtyp 过滤 / 别名与 4 个旧旗标 / `auto` / §4.8 的四个原生出口）**全部独立复现**，
**BC-4 比 25 号报告更宽**（本会话扩到 13 个 runtype，全部输出文件逐位相同），
**6 次独立注入全部变红、全部还原**，**集合 S 差集 0**。
未发现 CRITICAL / HIGH / MEDIUM。发现 **3 条 LOW 与 3 条 INFO**（均不阻塞，见 §11）。

| 验收项 | 独立结果 |
|---|---|
| `ctest -R landscape` | **120/120 通过**（本会话自建目录，35.4 s） |
| 回归子集 `Singlepoint\|GFN\|model-hessian\|optimizer\|Argparser\|CAPI` | **12/12 通过** |
| 取值域双向对照 | 25 拼写 + `auto` = **26**，与 `--help` **逐字一致**；每个名字**实跑**通过（§3） |
| 别名三情形 × 4 旗标 | 同值等价 / 异值 error / 只给其一可用 —— **全绿，无误报**（§4） |
| 按 runtyp 过滤 | **76 个不匹配组合全部响亮报错**且点名正确旗标（§5） |
| 四个原生出口 | 4 引擎 / 7 拼写全部实测走到原生（唯一 token 互斥），顺序无关（§6） |
| BC-4 | 13 个 runtype，**全部输出文件 raw `cmp` 相同**（1 处时间戳除外），stdout **行数完全相等**（§7） |
| 可证伪性 | **6/6 独立注入变红**，还原后 `sha256sum -c` 通过（§8） |
| 集合 S | 方言 A/B **差集 = 0**（N = 30/4 与 34/6，与 18 号报告登记一致）（§9） |
| 横向排查 | `--ljson` / `--namespace` / 机器可读输出**无污染**（§10） |

---

## 1. 独立构建与基线

```bash
# 被测（工作区 = 阶段 2）
cmake -S $REPO -B /tmp/xtb-p2v/new -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"
cmake --build /tmp/xtb-p2v/new -j8                                    # EXIT=0
# 强基线（阶段 1 已提交状态）
git worktree add --detach /tmp/xtb-p2v/base f5b070f
cmake -S /tmp/xtb-p2v/base -B /tmp/xtb-p2v/base-build <同上> && cmake --build … --target xtb-exe
```

两个二进制的版本串**实测逐字相同**（`6.7.1 (f5b070f73948f337775824ac8b83fe893b03441e)`），
所以 §7 的 stdout 对比**不需要对版本行做归一化**（25 号报告的该结论本会话复现成立）。

---

## 2. 取值域核实：先从源码枚举，再逐名实跑

**不做文字比对，直接从实现里抽取**（脚本从 `settings.f90` 的 3 个 `*_from_name` 与 `main.F90`
的 `landscape_native_engine_from_name` 里取 `case (...)` 的字面量）：

```
opt    ['bfgs', 'cg', 'diis', 'lbfgs', 'rfo', 'sd']                      6
ts     ['autoneb', 'bprfo', 'cineb', 'dimer', 'gsm', 'neb', 'prfo', 'string']  8
irc    ['eulerpc', 'gs', 'hpc', 'lqa']                                   4
native ['ancopt', 'fire', 'inertial', 'l-ancopt', 'lancopt', 'pbc_lbfgs', 'rf'] 7
total spellings (excl auto): 25      with auto: 26
overlap opt∩ts = []  opt∩irc = []  opt∩native = []  ts∩irc = []  ts∩native = []  irc∩native = []
```

> **关键结构性质（本会话实测）**：四个集合**两两不交**。这正是 `main.F90:4154 landscape_method_task`
> 可以按 `opt → ts → irc` 顺序短路的前提（若相交，`gs`/`gsm` 一类名字会被误判任务）。设计 §4.2
> 担心的"同一名字两种含义"**不是**隐患。

**双向对照 `--help`**：把 `xhelp.f90` 的 `--method NAME` 条目按 `landscape_help_check.py` 的抽取规则
展开后拼接，检查 26 个 token 是否**逐字出现**：

```
names NOT appearing verbatim in the --method help: []
```
并人工核对反向：help 里点到的名字集合 = `sd cg lbfgs bfgs diis rfo | prfo bprfo dimer neb cineb
autoneb string gsm | gs hpc lqa eulerpc | ancopt rf lancopt l-ancopt fire inertial pbc_lbfgs | auto`
—— **没有多列、没有漏列**（既没有"列了不能用"，也没有"能用没列"）。

**逐名实跑**（`/tmp/xtb-p2v/domain.sh`，全部 `OMP_NUM_THREADS=1`）：

```
ok lopt-sd/cg/lbfgs/bfgs/diis/rfo   "landscape: <m> minimisation"
ok scan-<6>                         "landscape: relaxed scan" + xtbscan.log 与 --lscan-method 逐位同
ok ts-prfo/bprfo                    "transition state search (prfo|bprfo)"
ok ts-dimer/neb/cineb/autoneb/string/gsm   "transition state search (<m>)"（收敛性另见 §3.1）
ok irc-gs/hpc/lqa/eulerpc           "intrinsic reaction coordinate (<m>)"
ok auto-lopt/lscan/lts/lirc         四个任务的默认名（lbfgs / prfo / hpc）
ok nat-ancopt/rf                    "ANC micro-cycles"
ok nat-lancopt/l-ancopt             "L-ANC optimizer"
ok nat-fire/inertial                "initial time step"
ok nat-pbc_lbfgs                    "current lattice:"
```

**判别 token 互斥性实测**（防止"断言恒真"）：

```
nat-ancopt    ANC=1 LANC=0 FIRE=0 PBC=0 landscape=0
nat-rf        ANC=1 LANC=0 FIRE=0 PBC=0 landscape=0
nat-lancopt   ANC=0 LANC=1 FIRE=0 PBC=0 landscape=0
nat-l-ancopt  ANC=0 LANC=1 FIRE=0 PBC=0 landscape=0
nat-fire      ANC=0 LANC=0 FIRE=1 PBC=0 landscape=0
nat-inertial  ANC=0 LANC=0 FIRE=1 PBC=0 landscape=0
nat-pbc_lbfgs ANC=0 LANC=0 FIRE=0 PBC=6 landscape=0
```
⇒ 任选一个 token 都能**唯一**确定引擎，且 7 个原生拼写**没有一个**落进套件（`landscape: ` = 0）。

### 3.1 收敛性（"能选" ≠ "能用"）
不匹配的短预算会让任务以"未收敛"退出（`ERROR STOP`），所以本会话用**注册测试的参数**复跑，
证明算法本身可用：

```
neb   (NH3, images 7)   exit 0  converged=1  saddle=1
cineb (alias 对比)      与 --lts-method 逐位同
bprfo (HCN)             exit 0  converged=1
dimer (HCN)             exit 0  converged=1
autoneb (NH3, 400 步)   exit 0  converged=1
string (nnodes 16,600)  exit 0  converged=1  saddle=1
gsm    (同上)           exit 0  converged=1  saddle=1
```
`++ auto` 也在 6 个 runtype 上**逐位等价**（§5.1）。

---

## 4. 别名关系：三情形 × 4 旗标（含误报排查）

`/tmp/xtb-p2v/alias_matrix.sh` + `alias_ts.sh`（每条都贴退出码）。**误报（合法组合被拒）是重点排查对象。**

```
# --lopt / --lopt-engine
ok o-f  exit 0        --method bfgs
ok o-g  exit 0        --lopt-engine bfgs
ok o-fg exit 0        --method bfgs --lopt-engine bfgs
ok o-gf exit 0        --lopt-engine bfgs --method bfgs
ok o-d1 exit 1        --method bfgs --lopt-engine cg   → conflicting landscape methods: --method bfgs and --lopt-engine cg
ok o-d2 exit 1        --lopt-engine cg --method bfgs   → 同上（顺序无关）
ok o-case1/case2 exit 0  --method BFGS + --lopt-engine bfgs（大小写混合）→ 同值幂等
ok o-f == o-g == o-fg == o-gf == o-case1 == o-case2    xtbopt.xyz 逐位同
# --lscan / --lscan-method（xtbscan.log 逐位同）；--lts / --lts-method；--lirc / --lirc-method
… 同样的 7 行全部 ok（取值 cg / dimer / gs；xtbts.xyz、i1.irc.log 逐位同）
```

**"只给其一"**：只给旧旗标 4/4 可用；只给 `--method`（带任务旗标）4/4 可用。

**默认值的边角（最容易误报的地方）**：`--method` 的值恰好等于任务默认值 —— 4/4 exit 0。

```
z1 --lirc --lirc-method hpc  --method hpc   exit 0
z2 --lscan --lscan-method lbfgs --method lbfgs exit 0
z3 --lts --lts-method prfo  --method prfo   exit 0
z4 --lopt --lopt-engine lbfgs --method lbfgs exit 0
```

**其他误报排查**（全部 exit 0，无拒绝）：
`--method auto` + 显式旧旗标（`--lopt-engine bfgs --method auto` 保持 bfgs，**不报冲突**）、
`--method dimer --lts-method dimer` 反序、`--lts --lts-method DIMER --method dimer`。

缺失值的响亮报错：`--method`（无值）→ `The --method flag requires a method name`。

> **优先级规则实测定案**：`--method` 与旧旗标**互为别名**；**异 owner + 异值 ⇒ error**（点名两个旗标），
> **同 owner 重复 ⇒ last-wins**（`--lopt-engine bfgs --lopt-engine cg` 仍是 `cg`，**没有**被新检查变成
> 破坏性变更 —— 本会话复跑确认：`repeat-engine-last` 与 `--method cg` 逐位同）。
> 这是设计 §4.3 规则的**有意收窄**（25 号报告 F6），且**不与 §10 的破坏性清单冲突**。

---

## 5. 按 runtyp 过滤：76 个不匹配组合

`/tmp/xtb-p2v/filter.sh`：对每个 (runtype, name) 组合断言 **退出码 ≠ 0** 且 **消息点名正确旗标**。

```
checked 76 pairs, failures 0
```

组合数 = `{--lopt,--lscan}×{8 ts + 4 irc + 7 native}` = 19×2 = **38**
+ `{--lts}×{6 opt + 4 irc + 7 native}` = **17**
+ `{--lirc}×{6 opt + 8 ts + 7 native}` = **21** ⇒ **76**。逐条实跑，逐条断言。

**消息原文（实测，逐条点名正确旗标）**：

```
lopt-dimer        : dimer is a transition-state method; use it with --lts (or --lts-method dimer)
lscan-dimer       : （同上）
lts-bfgs          : bfgs is a minimisation method; use it with --lopt or --lscan
lirc-gsm          : gsm is a transition-state method; use it with --lts (or --lts-method gsm)
lopt-hpc          : hpc is an intrinsic reaction coordinate method; use it with --lirc
lts-eulerpc       : eulerpc is an intrinsic reaction coordinate method; use it with --lirc
lirc-prfo         : prfo is a transition-state method; use it with --lts (or --lts-method prfo)
lopt-ancopt       : --method ancopt selects a native optimizer engine, which is only available with --opt or --ohess
lscan-rf          : --method rf selects a native optimizer engine, which is only available with --opt or --ohess
lts-pbc_lbfgs     : --method pbc_lbfgs selects a native optimizer engine, which is only available with --opt or --ohess
```

**大小写**：`--method DIMER` / `Dimer` 也走同一条过滤（`landscape_lowercase` 归一），消息回显用户拼写。

**未知名 / 无任务 / `--lvib`**（实测）：
```
--lopt --method bogus  → exit 1: unknown landscape method 'bogus': ask for --method auto for the task
                         default, or name a minimiser (sd, cg, lbfgs, bfgs, diis, rfo), a saddle search
                         (prfo, bprfo, dimer, neb, cineb, autoneb, string, gsm) or an IRC integrator
                         (gs, hpc, lqa, eulerpc)
--method ''            → exit 1: unknown landscape method '': …
--method bfgs（无任务）→ exit 1: --method needs a landscape run type: add --lopt, --lscan, --lts or --lirc …
--sp --method bfgs     → exit 1: 同上（`--sp` 是真旗标：`main.F90:2155 case ('--scc','--sp')`）
--lvib --method bfgs   → exit 1: … cannot be used with --lvib … (use --lvib-hessian …)
--hess --method bfgs   → exit 1: --method needs a landscape run type: …
```

**正向组合**（§3/§4 已证）：`--lts --method prfo|bprfo|dimer|neb|cineb|autoneb|string|gsm` 8/8 工作，
`--lirc --method gs|hpc|lqa|eulerpc` 4/4 工作，`--lopt/--lscan --method <6>` 全工作。

### 5.1 `auto` 的语义被真正钉住（不只是"不崩溃"）
`auto` 的实现是 **no-op**（`main.f90:3983-3988` 的 `continue`），所以本会话用**逐位等价**证明它
等于"所选任务的默认"（而不是"某一个固定方法"）：

```
lscan auto: xtbscan.log 与无 --method 逐位同
lts   auto: tsx.xtbts.xyz 逐位同
lirc  auto: irc0.irc.log 逐位同
opt   auto: xtbopt.xyz 逐位同（且 ANC token = 1，仍走原生）
ohess auto: hessian 逐位同
```
另外**默认 banner 的语义也一致**（实测）：`--lopt` → 打 `[NOTICE] --lopt-engine default`；
`--lopt --method auto` → **仍打**（auto 不掩盖"没显式选"，测试有断言）；
`--lopt --method bfgs` → **不打**（与 `--lopt-engine bfgs` 一致，实测 NOTICE=0）。
⇒ `auto` 的定义"所选任务的默认"被 6 个 runtype 独立钉住。

---

## 6. §4.7 机制走读 + 四个原生出口

**代码走读（自己读的，file:line 为实测行号）**：

| 位置 | 作用 | 本会话核对 |
|---|---|---|
| `main.F90:246` | `integer :: landscape_native_engine = 0` | 声明带初值 |
| `main.F90:1606` | 在 `args%nextFlag` 循环**之前**无条件置 0 | ✅ 在 `:1608` 循环前，**早于**任何 `env%error` |
| `main.F90:2300-2315` | `case ('--method')` **只调 `args%nextArg`**，不调 `set_runtyp`、不写 settings | ✅ 与旗标顺序无关的结构性保证 |
| `main.F90:3967-3988` | 解析尾第 2 段：**原生分支在前**（`if (native /= 0)`），`else if` 才是 `auto` | ✅ 原生名**不可能**进入套件 setter |
| `main.F90:3989-4050` | 套件分支：按 `set%runtyp` 分派到 4 个纯 setter | ✅ 分支内**没有** `set_runtyp` |
| `main.F90:4215/4253/4294/4333` | 4 个共享 setter（opt/scan/ts/irc），ts 的那个携带 climbing 副作用 | ✅ 旧旗标 4 个 case 全部改为调用它们 |

**"原生名不进套件 setter"的实测证据（不只静态）**：注入 A 把原生映射全部打掉后，
`--opt --method ancopt` 的失败文本是 `--opt --method ancopt exited 1` +
`filter-lopt-native: missing 'only available with --opt or --ohess'` —— 即该名字**确实进了套件分派**
并因此报错，说明两条路是分离的（§8 INJ-A）。

**顺序无关**：`--opt --method ancopt` 与 `--method ancopt --opt` 的 `xtbopt.xyz` **逐位同**（测试断言）；
本会话另外证明 `--opt --method ancopt` 与**裸 `--opt`** 的全部 5 个输出文件逐位同：

```
== --opt --method ancopt == plain --opt (all files)?
  differing=0 (files: 5)
```
反向顺序也验证过：`--method bfgs --lopt …` 与 `--lopt … --method bfgs` 都 exit 0 且
`landscape: bfgs minimisation`。

**无 `--method` 时与阶段 1 完全一致**：见 §7（BC-4，13 个 runtype）。

---

## 7. BC-4：13 个 runtype 对 `f5b070f` 强基线

方法：两个二进制在**同一目录**里先后运行**同一条命令行**（输入文件绝对路径相同），
逐文件 `cmp`，并把 stdout 的 diff 逐行分类。`--md` 用 `$seed 42`（xcontrol）钉住随机性。

| runtype | 退出码 base/new | 输出文件数 | **raw `cmp` 不同的文件** | stdout 差异行 | base/new 行数 |
|---|---|---|---|---|---|
| `--sp` | 0/0 | 3 | **0** | 28 | 14/14 |
| `--hess` | 0/0 | 7 | **0** | 32 | 16/16 |
| `--ohess` | 0/0 | 9 | **0** | 68 | 34/34 |
| `--md`（seed 42） | 0/0 | 55 | **1**（`xtbtopo.mol`，见下） | 30 | 15/15 |
| `--gfnff --sp` | 0/0 | 2 | **0** | 32 | 16/16 |
| `--opt`（原生） | 0/0 | 5 | **0** | 62 | 31/31 |
| `--ohess`（原生） | 0/0 | 9 | **0** | 60 | 30/30 |
| `--hess --ljson` | 0/0 | 7 | **0** | 28 | 14/14 |
| `--lopt` | 0/0 | 5 | **0** | 32 | 16/16 |
| `--lscan` | 0/0 | 5 | **0** | 30 | 15/15 |
| `--lts` | 1/1 | 2 | **0** | 38 | 19/19 |
| `--lvib` | 0/0 | 7 | **0** | 22 | 11/11 |
| `--lopt --ljson` | 0/0 | 6 | **0** | 32 | 16/16 |

- **`md` 的那 1 个差异是时间戳**：`xtbtopo.mol` 第 2 行 `10042600393D` → `10042600403D`
  （`MMDDYYHHMM`，两次运行的分钟不同），与代码无关。
- **行数完全相等**（base 行数 = new 行数，13/13）⇒ 没有新增/删除任何一行输出。
- **把数字全部抹掉后做多重集比较**：13 个 runtype 里唯一残留的差异是 `program call` 行
  （二进制路径不同：`base-build/xtb` vs `new/xtb`）；`--lts` 另有 C 回溯帧地址（两条路都在**同一条既有失败路径**上退出 1，帧数相同）。
- **没有新增/删除的输出行**：base 与 new 的行数在 13 个 runtype 上**逐一相等**（上表最后一列），
  且抹掉数字后的多重集差异只剩 `program call`（二进制路径不同）；这条比 25 号报告的“归一化后逐位同”
  更强：**不需要归一化，输出文件本身就逐位同**。

⇒ **BC-4 通过，且比 25 号报告更宽**（25 号只跑 4 个原生 runtype；本会话加了 `--gfnff`、`--hess --ljson`
与 5 个套件 runtype）。

---

## 8. 可证伪性：6 次独立注入（自己制造缺陷，不采信报告）

方法：`cp` 备份 → `python3` 唯一字符串替换 → `cmake --build --target xtb-exe` → `ctest -R …`
→ 记录真实 FAIL 文本 → 还原 → 重建 → `sha256sum -c`。

| # | 注入（语义） | 位置 | 变红 | **真实 FAIL 文本** |
|---|---|---|---|---|
| A | 原生映射全删（`--method` 永远走套件） | `main.F90:4124-4143` 函数体 → `engine = 0` | `landscape-method` + `-native` | `FAIL: filter-lopt-native: missing 'only available with --opt or --ohess'` / `FAIL: --opt --method ancopt exited 1` |
| B | 冲突判定恒假（静默首选项获胜） | `main.F90:4236` 前的 `if` 加 `.false.` | `landscape-method` | `FAIL: conflict-opt: expected a non-zero exit` |
| C | `--lopt` 分支的 runtyp 过滤摘掉 | `main.F90:3995` 的谓词 → `.false.` | `landscape-method` | `FAIL: filter-lopt-dimer: missing 'dimer is a transition-state method'` |
| F | 四个分支的 mismatch **报告**删掉（静默接受） | `main.F90:3996/4003/4010/4017` → `continue` | `landscape-method` | `FAIL: filter-lopt-dimer: expected a non-zero exit` |
| D | `auto` 的 no-op 分支删掉 | `main.F90:3983` → `.false.` | `landscape-method` | `FAIL: auto-method: exit status 1` |
| E | 原生引擎钉住行删掉 | `main.F90:3977` → `continue` | `landscape-method-native` | `FAIL: --opt --method lancopt did not reach the native engine` |

**每次还原后**：`sha256sum -c /tmp/xtb-p2v/sha-before.txt` → `main.F90: OK` / `settings.f90: OK` /
`xhelp.f90: OK`；随后 `ctest -R landscape` → **120/120**（最终态复跑，35.4 s）。

**额外定点实验（E 的延伸，25 号报告 F7 的核心断言）**：E 施加后单独跑 501 原子 GFN-FF：

```
# 未注入（正确态）：  --gfnff --opt --method ancopt --norestart
  exit=0  ANC micro-cycles: 1  L-ANC optimizer: 0
# 注入 E 后：
  exit=0  ANC micro-cycles: 0  L-ANC optimizer: 1      ← 显式 ancopt 被 >500 原子默认静默改成 L-ANCopt
```
⇒ **501 原子 fixture 确实是唯一能看见 `set%opt_engine = landscape_native_engine` 这行的探针**
（小体系默认就是 `rf`，注入 E 在 `ancopt` 上仍绿；`lancopt`/`fire` 才是小体系上的探针）。
这也说明**该断言不是恒真**（设计 §4.7.1 的 `-native-level` 项成立）。

**证伪前提（本会话自己踩到的 3 条，避免把"绿"当成证明）**：

- **F-1**：短预算的 `--lts-max-steps 3/5` 会让 band 搜索以"未收敛"退出 1 ——
  第一轮域扫描里 6 个 ts 名因此"看起来失败"，实际是**我自己的参数问题**
  （`src/landscape/tasks/ts.f90` 的迭代上限路径 `landscape_ts_band: … did not converge: maximum number of steps reached`）。
  按注册测试的参数复跑后 7/8 收敛（§3.1）。**结论：判"名字可用"必须用注册参数，不能自造预算。**
- **F-2**：`autoneb` 写的是 `p1.path_autoneb.xyz`（不是 `p1.path.xyz`，见
  `test/unit/CMakeLists.txt:2471-2479` 的对比对象）。我的第一个 alias 脚本比错了文件名，
  把"两个文件都不存在"报成"内容不同"。修正后 autoneb 的 4 个输出文件**全部逐位同**。
- **F-3**：AutoNEB 的 `random seed` 每次不同（实测 `1357357417` vs `1267235523`），
  所以任何"auto/alias 逐位同"的断言**必须**落在**确定性输出文件**上，或落在没触发随机插入的短预算上。
  25 号报告 F3 的同类前提（stdout 含程序调用、种子、墙钟，同二进制两次也不逐位同）本会话**复现成立**。

---

## 9. 集合 S（`--method` 已在 `xhelp`）

```bash
python3 test/unit/landscape_help_check.py src/prog/main.F90 src/xhelp.f90
dialect A: S(main) = 125, S(help) = 125, difference = 0     S: 0 differences
dialect A: N(implemented, undocumented) = 30   N(documented, unimplemented) = 4
dialect B: S(main) = 125, S(help) = 125, difference = 0     S: 0 differences
dialect B: N(implemented, undocumented) = 34   N(documented, unimplemented) = 6
PASS: set S is documented by `--help` in both dialects
```
N 的 30/4 与 34/6 **与 18 号报告登记值逐字一致**。**注入 M9 型（删 `xhelp` 条目）本会话未重跑**，
但**自然变红的证据另有**：`ctest -R landscape` 的 120 项里包含 `xtb/landscape-help-coverage`，
它的门槛就是 S 差集；25 号报告 §5 M9 的"首轮 119/120"与本会话的机制一致（门槛在拦未文档化旗标）。

**重名检查**（两套注册）：
```
grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d     → 空
grep -oE "test\('[^']+'"     test/unit/meson.build  | sort | uniq -d     → 空
grep -rl -- '--lopt|--method|landscape' man/                            → 空（man/ 无套件旗标，无需改）
grep -n '"--method' src/xhelp.f90                                       → 274
```

**meson 侧（本机无 meson，不能端到端）**：meson 内联的 python 生成脚本产出的 `big.xyz`
与 CMake `file(APPEND)` 产物 **`diff` 逐位同**（15277 B）；两个 `test(...)` 的参数顺序与 CMake
`-DARGS=` **逐项对齐**（`method` / `methodnative`）。**未验证 meson 端到端执行**（无 meson/ninja）。

---

## 10. 横向排查：`--method` 会不会污染机器可读输出 / 与旧旗标静默分歧

| 探针 | 命令 | 结果 |
|---|---|---|
| JSON 逐位 | `--lopt --method bfgs --ljson` vs `--lopt --lopt-engine bfgs --ljson` | `landscape_opt.json` **逐位同**；schema 仍 10 键 |
| JSON 内容 | 同上 | 不含 `--method` 字面量；`grep -rl -- '--method' <rundir>` 只命中 stdout 的 `program call` 行 |
| `--namespace` | `--lopt --method bfgs --namespace c1 --ljson` vs 旧旗标 | 文件集相同（`c1.charges` / `c1.landscape_opt.json` / `c1.wbo` / `c1.xtbopt.xyz` / `c1.xtbtopo.mol` / `c1.xtb.trj`），内容逐位同 |
| 原生 runtype + `--ljson` | `--opt --method ancopt --ljson` | 与裸 `--opt --ljson` **同行为**：exit 0、**不写** json、同一条 warning |
| 与旧旗标异值 | `--opt --method ancopt --lopt-engine bfgs` | exit 1：`run type conflict: --opt already selected the 'opt' run type, --lopt-engine would select 'lopt'` |
| 套件子选项混用 | `--opt --method ancopt --lopt-hessian model` | exit 1：同上（**没有**静默丢弃） |
| 输出文件全量 | `--method X` vs `--<task>-method-flag X`（lopt/scan/ts/irc 各取 6 组） | 每个 runtype 的**全部**输出文件逐位同（5/5、5/5、2/2、3/3、7/7） |

⇒ **没有静默分歧，也没有机器可读输出的污染。**

---

## 11. 独立发现（测试全绿但仍需记录）

> 全部**不阻塞**。前 3 条是我自己在测试覆盖之外发现的行为/覆盖缺口。

- **LOW-1：注册测试没有枚举完取值域。** `xtb/landscape-method` 只实跑
  `bfgs / cg / dimer / cineb / gs / auto` + 4 个错误分支；`xtb/landscape-method-native` 覆盖 7 个原生拼写。
  ⇒ 若将来 `sd`、`diis`、`rfo`、`bprfo`、`neb`、`autoneb`、`string`、`gsm`、`lqa`、`eulerpc`
  中的某一个从取值域里掉出去，**ctest 不会变红**（本会话用 26 个名字手工跑过，今天全部可用，见 §3）。
  建议：把 §3 的域扫描做成一个由表驱动的 ctest 用例（成本约 30 s）。
- **LOW-2：`--method <native>` 与 xcontrol `$opt engine=<别的>` 的优先级是"静默 CLI 获胜"。**
  实测 `--opt --method fire --input <$opt engine=rf>` → `initial time step`（fire 生效）、
  **无任何 warning**（`warn=0`）。这与项目已确立的"显式 CLI > xcontrol > 内置默认"（AGENTS §6）一致，
  且设计 §4.8 也这么规定；但设计 §4.7.1 的 `R34/U15` 曾要求补一条 `[WARNING]` 诊断
  （`set_module.f90:1885` 的 `.not.allocated` 守卫分支），**本轮未实现**（`git diff --name-only`
  里没有 `set_module.f90`）。25 号报告 §0 未声称实现它，故属"设计表里有、阶段 2 边界外"的**登记缺口**。
- **LOW-3：`--lscan --lscan-mode rigid --method X` 静默无用。** 实测 `--method bfgs` 与
  `--lscan-method bfgs` 在 rigid 模式下**输出逐位同且零提示**（rigid 点走
  `scan1d.f90:171 landscape_scan_rigid_point`，不读 `settings%method`）。这是**既有**行为
  （旧旗标同样如此，非阶段 2 引入），但按铁律 1 的"每个新旗标要证明生效"，这条通道值得登记。
- **INFO-1：无任务时的错误消息只点名 `--opt`，没点 `--ohess`**（`main.F90:4040-4041`）：
  `… add --lopt, --lscan, --lts or --lirc (or use --method ancopt with --opt)`。
  实测 `--ohess --method ancopt` 是合法的（原生路径），所以消息**不完整但不错误**。
- **INFO-2：`--method dimer --method bfgs --lopt` 静默丢弃前面的跨任务名**（last-wins），
  只对**最后一个**值做 runtyp 过滤。与设计 §4.3 的 last-wins 一致；若用户笔误写在前面则无提示。
- **INFO-3：`--lopt --method auto` 保留 `[NOTICE] --lopt-engine default`，
  `--lopt --method bfgs` 抑制它** —— 行为自洽（`algorithm_was_set`），但 `--method` 本身**没有**专属 echo
  banner。阶段 2 的边界未要求，登记备查。

**没有发现"测试断言恒真"的情况**：本会话逐条读了两套新测试的断言（`identical()` 比字节、
`expect_error()` 要求非零退出 + 正则、`expect_milestone()` 要求 token 存在且另一个 token 不存在），
并用 6 次注入证明它们真的会红（§8）。`identical()` 在文件缺失时抛异常 ⇒ 测试非零退出（在 F-2 里真实发生）。

---

## 12. 未验证项（诚实标注）

1. **meson 端到端未执行**（本机无 meson/ninja）。只做了替代核对：内联生成脚本产物与 CMake 产物逐位同、
   参数顺序对齐、两侧测试名无重名。
2. **`ctest -N -R landscape` 的计数与 `landscape_cli_check.py` 的 20+ 场景清单没有一一映射**：
   25 号报告 §4.7.1 的表是设计清单（20 行），交付的是 2 个 ctest 入口覆盖其中一部分；
   表里属于阶段 3 的项（`-opt-alias-once` / `-opt-native-nojson` / `-ohess-suite-once` /
   `-guard-fire-no-scan` / `-opt-xcontrol-scope` / `-method-level-bridge` …）**本轮未实现，也未声称实现**。
3. **`--method` 在未改派原生 runtype（`--hess`/`--md`/`--bhess`/`--path`/`--modef`/`--screen`/
   `--metaopt`/`--siman`/`--mdopt`/`--metadyn`/`--nat`/`--bias-input`）上的逐条专属措辞**
   （设计 §4.6 的 12 条）**没有**逐条实现，只由通用 `case default` 覆盖。本会话实测四条：
   ```
   --hess  --method bfgs → exit 1: --method needs a landscape run type: add --lopt, --lscan, --lts or --lirc (or use --method ancopt with --opt)
   --md    --method bfgs → exit 1: （同一条文本）
   --bhess --method bfgs → exit 1: （同一条文本）
   --path  --method neb  → exit 1: （同一条文本）
   ```
   响亮、不误导，但**不是** §4.6 的逐条措辞（例如 `--path` 的消息没有指向 `--lts --method neb`）。
   （25 号报告 §6 F8 已自认，本会话独立复核成立。）
4. **`--lopt --method <name> --ljson` 的 json 里没有方法名字段**：schema 未变（"method" 子串来自
   既有的 `conv%history_method` 序列，两条路相同）。若评审希望 json 记录生效方法名，那是 **M7 schema**
   的扩展请求，**不是**阶段 2 的缺陷。

---

## 13. 复现命令（本报告的全部数字）

```bash
REPO=/home/owenchan/work_path/coding/fortran/xtb
cmake -S $REPO -B /tmp/xtb-p2v/new -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"
cmake --build /tmp/xtb-p2v/new -j8
git -C $REPO worktree add --detach /tmp/xtb-p2v/base f5b070f
cmake -S /tmp/xtb-p2v/base -B /tmp/xtb-p2v/base-build <同上>
cmake --build /tmp/xtb-p2v/base-build -j8 --target xtb-exe

OMP_NUM_THREADS=1 XTBPATH=$REPO ctest --test-dir /tmp/xtb-p2v/new -R landscape          # 120/120
OMP_NUM_THREADS=1 XTBPATH=$REPO ctest --test-dir /tmp/xtb-p2v/new \
  -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'                            # 12/12

bash /tmp/xtb-p2v/domain.sh      # §3 取值域逐名实跑            -> FAILFLAG=0
bash /tmp/xtb-p2v/alias_matrix.sh; bash /tmp/xtb-p2v/alias_ts.sh   # §4 -> FAILURES=0
bash /tmp/xtb-p2v/filter.sh      # §5 -> checked 76 pairs, failures 0
bash /tmp/xtb-p2v/auto.sh        # §5.1 auto 逐位等价
bash /tmp/xtb-p2v/bc4.sh         # §7 BC-4（13 runtype）
bash /tmp/xtb-p2v/lateral.sh     # §10
bash /tmp/xtb-p2v/inj.sh <A|B|C|D|E|F> '<test regex>'   # §8（自带还原 + sha256 校验）
python3 test/unit/landscape_help_check.py src/prog/main.F90 src/xhelp.f90               # §9
```

原始日志：`/tmp/xtb-p2v/logs/`（build、bc4.log、string-gsm*.log），运行目录 `/tmp/xtb-p2v/run/`。
基线二进制留在 `/tmp/xtb-p2v/base-build/xtb`（`bc4.sh` 只需要它）；基线 **worktree 已清理**
（`git worktree remove --force /tmp/xtb-p2v/base`，仓库不留额外 worktree 登记），
重建它只需上面那一条 `git worktree add` 加一次 `cmake --build`。

---

## 14. 判据对照（命令 / 期望 / 实际）

| 判据 | 命令 | 期望 | 实际 |
|---|---|---|---|
| 取值域无多列/漏列 | §2 脚本 + 逐名实跑 | 26 名全部可用且 help 逐字一致 | ✅ 26/26 |
| 别名同值等价 | `o-f/o-g/o-fg/o-gf` + `cmp` | 逐位同 | ✅ |
| 别名异值 error | `o-d1/o-d2` 等 5 对 | exit 1 + 点名两旗标 | ✅ |
| 只给其一可用 | 8 条 | exit 0 | ✅ |
| 过滤响亮 | `filter.sh` | 76/76 exit≠0 且点名 | ✅ 76/76 |
| 原生出口真到原生 | 7 拼写 token | 唯一 token 且无 `landscape:` | ✅ |
| 无 `--method` 行为不变 | `bc4.sh` | 全部输出文件逐位同 | ✅ 13 runtype |
| 可证伪 | 6 注入 | 红 + 还原绿 | ✅ 6/6 |
| 集合 S | `landscape_help_check.py` | 差集 0 | ✅ 0（A/B） |
| 机器可读无污染 | §10 表 | json/文件集逐位同 | ✅ |
