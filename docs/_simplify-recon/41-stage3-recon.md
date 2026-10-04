# 阶段 3（`--opt`/`--ohess` 改派到套件）事实清单

HEAD = `2b49ef8`（工作树干净）。构建 `/tmp/xtb-land/build/xtb`（已含全部已提交内容）。
实测环境：`OMP_NUM_THREADS=1`，临时目录一律 `/tmp/stage3-recon-*`。
**重要行号漂移提醒**：设计文档 §3.11/§14.5 引用的 `main.F90:931/:1156/:1282/:1310-1320/:4065-4071`、`landscape_cli_check.py:492-503`
**均已漂移**，本报告一律给 **HEAD 实测行号**，并在括号内标注设计旧值。

---

## A. `--opt` / `--ohess` 当前分派

### A1. 三个 case 的确切位置与结构
| 旗标 | 行号 | 结构 |
|---|---|---|
| `case ('-o', '--opt')` | `src/prog/main.F90:2202-2208` | `select_runtyp(...,'opt','--opt',...)` → `args%nextArg(sec)` → 有参则 `set_opt(env,'optlevel',sec)` |
| `case ('--ohess')` | `src/prog/main.F90:2215-2221` | 同上，`'ohess'` |
| `case ('--bhess')` | `src/prog/main.F90:2222-2228` | 同上，`'bhess'`（阶段 3 **保持原生**） |
| `case ('--lopt')`（对照） | `src/prog/main.F90:2293-2298` | 只 `select_runtyp(...,'lopt','--lopt',...)`，**无位置参数**；engine/level 由专用旗标设 |

`--opt` / `--ohess` 都只 `set_runtyp`；它们**不**直接进 anyopt。原生执行由独立的 `if (anyopt)` 块完成（见 F18）。level 经 `set_opt('optlevel')` 存进 `set%optset%optlev`（见 A4）。

### A2. `select_runtyp`
- 定义：`src/prog/main.F90:4285-4323`（`subroutine select_runtyp(env,typ,flag,selected_typ,selected_flag,apply)`）。
- 语义：首个请求记录 `selected_typ`/`selected_flag` 并调 `set_runtyp`；若再来一个**不同** typ ⇒ `env%error("run type conflict: ...")`。同 typ 重复为 no-op。
- `selected_runtyp` / `selected_runtyp_flag` 声明：`main.F90:1574`（`character(len=:),allocatable`，解析器状态，非 runtyp）。

### A3. `p_run_*` 常量
定义文件 `src/setparam.f90:197-220`。**实测总数 = 24**（`grep -c "integer, parameter :: p_run_" src/setparam.f90` → `24`；设计 §16.6 L-1 写的 25 与 HEAD 不符，标**未证实**）。

| 常量 | 行 | 值 | 常量 | 行 | 值 |
|---|---|---|---|---|---|
| `p_run_opt` | 200 | 4 | `p_run_lopt` | 206 | 9 |
| `p_run_ohess` | 202 | 7 | `p_run_lscan` | 209 | 12 |
| `p_run_bhess` | 203 | 71 | `p_run_lts` | 213 | 19 |
| `p_run_hess` | 201 | 5 | `p_run_lirc` | 214 | 20 |
| | | | `p_run_lvib` | 215 | 21 |

### A4. `--opt <level>` 解析点 + `get_optthr` 8 档表
- 解析：`main.F90:2206/2219/2226` 的 `set_opt(env,'optlevel',sec)` → `src/set_module.f90:1811` `set%optset%optlev = optlevel2int(val)`。
- `optlevel2int`：`src/set_module.f90:1927-1953`（未知值 → `p_olev_normal`，静默）。
- `get_optthr`：`src/optimizer.f90:48-119`。**完整 8 档（n = 原子数；末尾 `maxcycle=clamp(maxcycle,200,10000)`）**：

| level | key（`optlevel2int`） | ethr | gthr | maxcycle | acc |
|---|---|---|---|---|---|
| crude | `crude`/`-3` | 5e-4 | 1e-2 | n | 3.00 |
| sloppy | `sloppy`/`-2` | 1e-4 | 6e-3 | n | 3.00 |
| loose | `loose`/`-1` | 5e-5 | 4e-3 | n*2 | 2.00 |
| lax | `lax` | 2e-5 | 2.5e-3 | n*2 | 2.00 |
| normal（默认） | `normal`/`0` | 5e-6 | 1e-3 | n*3 | 1.00 |
| tight | `tight`/`1` | 1e-6 | 8e-4 | n*5 | 0.20 |
| vtight | `verytight`/`vtight`/`2` | 1e-7 | 2e-4 | n*20 | 0.05 |
| extreme | `extreme`/`3` | 5e-8 | 5e-5 | n*20 | 0.01 |

`p_olev_*` 值：`setparam.f90:68-75`（crude=-3, sloppy=-2, loose=-1, **lax=-4**, normal=0, tight=1, vtight=2, extreme=3）。

### A5. 套件 4 档表 vs 上游 8 档并排
`src/landscape/types/settings.f90:1120-1155`（`landscape_settings_set_conv_level`）**只写 4 个阈值字段**；
`e_tol` 固定 `5.0e-6`（`settings.f90:375`），`max_steps` 固定 `256`（`settings.f90:373`），`engine%acc` 来自全局 `set%acc`（无条件覆盖，见 H23）。

| 套件档 | g_max | g_rms | d_max | d_rms | e_tol(现状) | 映射的上游档（§3.5） |
|---|---|---|---|---|---|---|
| superloose | 4.6e-3 | 3.0e-3 | 7.9e-3 | 5.2e-3 | 5.0e-6 | crude/sloppy/superloose |
| loose | 2.0e-3 | 5.0e-4 | 1.0e-2 | 7.0e-3 | 5.0e-6 | loose/lax |
| normal | 3.0e-4 | 1.0e-4 | 4.0e-3 | 2.0e-3 | 5.0e-6 | normal |
| tight | 1.0e-4 | 3.0e-5 | 1.0e-3 | 6.0e-4 | 5.0e-6 | tight |
| vtight | 3.0e-5 | 8.0e-6 | 2.0e-4 | 1.0e-4 | 5.0e-6 | verytight/vtight/extreme（截断） |

⚠️ 套件有 **5** 档（设计 §3.5 正文偶写“4 档”），上游有 8 档；同名档阈值仍不同（套件 4 判据 vs 上游 2 判据）。

---

## B. 三条「原生专属」守卫

### B6. `$scan` xcontrol 块
- **现有守卫实际位置：`src/prog/main.F90:498-518`**（设计 §3.8(a) 写的 `:491-510` 已漂移）。结构：`:498 lruntyp_flag=''` → `select case (set%runtyp)` 仅 `p_run_lopt/lscan/lts/lirc/lvib`（`:500-510`）→ `:511 if (nscan > 0 .and. len_trim(lruntyp_flag)>0)`。
- **报错原文（`:512-515`）**：
  `"<flag> does not execute the xcontrol $scan block: use --opt to run it, or --lscan with --lscan-coord/--lscan-atoms for a scan of the landscape suite"`
  （自指！`--opt` 改派后必须改成 `--opt --method ancopt`，见设计 §14.6。）
- `nscan` 可用点：`call read_userdata(xcontrol, env, mol)` 在 `main.F90:483`（守卫在其后）。
- **`--opt` 现在是否执行它：是。实测**：
  `xtb water.xyz --gfn 2 --opt --input scan.inp --norestart` → `exit=0`，`grep -c "RELAXED SCAN" = 1`，`xtbscan.log` 存在。
  `--lopt` 同输入 → `exit=1` + `does not execute the xcontrol $scan block`。

### B7. 周期体系
- 判定字段：`mol%npbc > 0`（`readMolecule` 在 `main.F90:441` 已定）。
- **套件侧拒绝：`src/landscape/landscape_driver.f90:73-76`**，文案 `"landscape tasks do not support periodic boundary conditions yet"`。**实测**（GFN-FF，`assets/inputs/coord/quartz.3d.coord`）：
  `xtb quartz.coord --gfnff --lopt --norestart` → `exit=1`，末段 `-1- landscape_run: landscape tasks do not support periodic boundary conditions yet`。
- 原生路径（`main.F90:938-943`）对周期 GFN-FF 强制 `pbc_lbfgs`；**实测** `--opt` 周期 → `exit=0`（写 `xtbopt.coord`/`xtboptlog.cif`）。
- 设计 §3.8(b) 要求的**点名 `--method ancopt`** 的守卫当前**不存在**（只有 `landscape_driver` 的通用文案）。

### B8. `$opt` xcontrol 键
- `$opt` 组读取点：`src/set_module.f90:797`（`case('opt'); call rdblock(env,set_opt, line,id,copy,err,ncount)`）。
- `$opt engine=` 处理：`src/set_module.f90:1884-1913`。未选中时 `1888-1893` 建 `set%opt_engine`；已选中时进 else 分支。
- **U15/T10 `[WARNING]`：`src/set_module.f90:1912`** `"engine '<val>' is ignored: an optimizer engine was already selected"`；未实现名警告 `:1897` `"engine '<val>' is not implemented"`。
- **套件当前对 `$opt`：静默忽略（C7 未实现）**。实测：`--lopt --input <$opt optlevel=tight>` → `exit=0`，`grep -ci "opt block|ignored|warning" = 0`；原生 `--opt --input <同>` → `exit=0` 且 `energy convergence 0.1000000E-05 Eh`（tight 生效）。

### B9. 三条守卫的候选放置区
必须位于 **`readMolecule`（`:441`，`mol%npbc`）、`rdcontrol`（`:340`，`$opt` 已读）/`read_userdata`（`:483`，`nscan`）之后，原生 `if (anyopt)`（`:938`）之前**。
⇒ 现成落点 = **`main.F90:498-518`**（与 `$scan` 守卫同块，设计 §3.11 读点表 #1/#2/#3 的“同一块”）。

---

## C. 四个遗留文件（§3.9）

### C10. 套件当前写点
**零**。`grep -rn "xtboptok|xtbopt.log|xtblast|compliance" src/landscape/` → **无命中**。
套件 `--lopt` 只写 `xtbopt.xyz` + `xtb.trj`（经 `src/landscape/types/log.f90`）。

### C11. 原生写点与语义差异
| 文件 | 原生写点（file:line） | 语义 |
|---|---|---|
| `.xtboptok` | `src/geoopt_driver.f90:112-113`（开场删 `.xtboptok`+`NOT_CONVERGED`，仅 `pr=.true.`）；`:186` 成功 `touch_file('.xtboptok')`；`:183` 失败 `touch_file('NOT_CONVERGED')` | **仅收敛时创建**；失败不建 |
| `xtbopt.log` | `src/geoopt_driver.f90:120-121` `open_file(ilog,'xtbopt.log','w')`（**无前导点**）；逐帧写点 `src/optimizer.f90:801`（XMOL 多帧） | 轨迹日志 |
| `xtblast.xyz` | `src/prog/main.F90:963-968`（仅 `murks` 失败路径） | 失败时写最后几何 + `"last geometry written to:"`；成功不写 |
| `compliance.dat` | 写函数 `src/compliance.f90:287`（裸 `open(...,file="compliance.dat")`）；**调用点** `src/hessian.F90:331-332`，条件 `mol%n>1 .and. freezeset%n==0 .and. .not.set%periodic` | 仅 Hessian 路径（`--hess`/`--ohess`）；`--opt` 单独无 |

### C12. 实测文件清单对比
`--lopt`（套件，`/tmp/stage3-recon-lopt`）：`xtbopt.xyz`、`xtb.trj`、`xtbtopo.mol`、`charges`、`wbo` — **无** `.xtboptok`/`xtbopt.log`/`xtblast.xyz`/`compliance.dat`。
原生 `--opt`（`/tmp/stage3-recon-opt`）：`xtbopt.xyz`、`xtbopt.log`、**.xtboptok**、`xtbtopo.mol`、`charges`、`wbo` — **无** `xtb.trj`（ANCopt 默认不写轨迹）。
原生 `--ohess`（`/tmp/stage3-recon-ohess`）：多加 `compliance.dat`、`hessian`、`vibspectrum`、`g98.out`。
套件 `--lvib`（`/tmp/stage3-recon-lvib`）：`compliance.dat` **缺失**（正是 §3.9 的缺口），有 `vib_normal_modes`。
→ 结论：`.xtboptok`、`xtbopt.log`、`compliance.dat` 是**真缺口**；`xtb.trj` 是新增（BC-3“集合不小”满足）。

---

## D. `--cycles`（§3.10）

- **CLI 定义：`src/prog/main.F90:1998-2004`**（`case ('--cycles')` → `set_opt(env,'maxcycle',sec)`）。
- **消费点：`set_module.f90:1822-1830`** → `set%optset%maxoptcycle`；被 `src/optimizer.f90:335-337` 读入并覆盖 `get_optthr` 的 `maxcycle`（仅原生）。
- 套件“迭代预算”字段：`max_steps`，默认 `256`（`src/landscape/types/settings.f90:373`）。
- **实测：`--lopt --cycles N` 被静默忽略（死旋钮）**：
  `--lopt --cycles 1 --ljson` → `exit=0`，`landscape_opt.json` `n_steps=5`、`converged=true`；默认 `--lopt` 同分子也 `n_steps=5`。`--cycles 5` 同样 exit 0 无提示。

---

## E. R39 过渡拒绝（阶段 3 移除）

- **位置：`src/prog/main.F90:4225-4237`**（设计 §4.7 引用的 `:4235` 附近）。`case (p_run_opt, p_run_ohess)` 在 **`:4225`**，注释“Stage 3 removes this”在 `:4230`。
- **报错原文（`:4232-4236`）**：
  `"--method <name> is a landscape method, but --opt and --ohess still run the native ANCopt in this build, so the name would have no effect: use --lopt (or the native engines --method ancopt|lancopt|fire|pbc_lbfgs with --opt)"`
- 相关测试：`landscape_cli_check.py` 的 `native-reject-opt`/`native-reject-ohess`（`:2420-2436`，断言含 `would have no effect` 且点名 `--lopt`）。

---

## F. §3.11 谓词与原生块抑制

### F16. 谓词现状
| 谓词 | 状态 |
|---|---|
| `landscape_native_engine_from_name` | **已存在**：`src/prog/main.F90:4348-4367`（纯函数，原生名 → `p_engine_*`） |
| `effective_landscape_task` / `landscape_is_suite_run` / `landscape_ohess_chain` / `landscape_native_hessian_path` | **不存在**（`grep -rn` 全仓库 0 命中）→ 阶段 3 新增 |

`landscape_native_engine` 的**全部读取/写入点**（`grep -n`）：
`main.F90:246`（声明 `= 0`）、`:261`/`:1486`（`parseArguments` 调用实参）、`:1581`（`intent(out)` dummy）、`:1601`（注释）、`:1606`（flag 循环前无条件 `= 0`）、`:4166`（解析尾赋值）、`:4168`（`/= 0` 判定）、`:4175`（写 `set%opt_engine`）。
⚠️ **除解析尾之外当前尚无任何分派/守卫消费者**（阶段 3 要补 §3.11 读点表 #1..#15）。

### F18. 原生块抑制点（HEAD 实测行号）
| 项 | HEAD 行号 | 判据 | 现状 |
|---|---|---|---|
| `if (anyopt)` 原生优化块 | `main.F90:938` | `anyopt`（`=324-326`：opt/ohess/omd/screen/metaopt） | **无抑制**（设计 §3.11 #4 建议改 `if (anyopt .and. landscape_native_engine /= 0)`） |
| `anyhess` 定义 | `main.F90:277` | runtyp 三元 | 不变 |
| 原生数值 Hessian 块 | `main.F90:1163` | runtyp 三元 | 无抑制 |
| 原生 `main_geometry`（opt 写 xtbopt.xyz） | `main.F90:1284-1287`（call `:1286`） | runtyp 三元 | 设计 #15 说**保留** |
| 原生频率打印 `main_freq` | `main.F90:1289-1291`（call `:1291`） | runtyp 三元 | 无抑制 |
| 原生 `xtbopt.xyz` 二次写 | `main.F90:1317-1329`（文案 `:1323`） | runtyp 三元 | 无抑制（设计 #13） |
| 计时标签 | `main.F90:4800-4814`（`ANC optimizer` `:4802`，`landscape optimizer` `:4805`） | runtyp | 无抑制（设计 #14，旧值 `:4065-4071` 漂移） |
| `anyopt` 另两个读点 | `main.F90:328`（CPCM-X terminate）、`:333`（PTB terminate） | 保持原样 | — |

设计 §3.11 行的旧行号已整体漂移（`:931→938`、`:1156→1163`、`:1282→1289`、`:1310-1320→1317-1329`、`:4065-4071→4800-4814`）。

---

## G. 测试同步清单（R42）

### G19. `check_scanblock` 与 `check_native_opt_symbols`
- `def check_scanblock(...)`：**`test/unit/landscape_cli_check.py:498`**（设计 §14.5 写的 447-503 段已漂移）。docstring `498-509`。
  - 5 套件 runtyp 拒绝循环：约 `521-543`；
  - **`--opt` 段（G1 对象，必须反转）：`544-555`**，原文：
    ```python
    # the ANCopt path still executes the block
    optdir = os.path.join(rundir, "opt")
    status, output = run(exe, inp, ["--gfn","2","--opt","--input",xcontrol,"--norestart"], optdir)
    if status != 0: fail("xtb --opt with a $scan block terminated with status %d" % status, output)
    if "RELAXED SCAN" not in output: fail("--opt did not run the $scan block", output)
    if not os.path.exists(os.path.join(optdir,"xtbscan.log")): fail("--opt did not write xtbscan.log", output)
    ```
  - 注册：`test/unit/CMakeLists.txt:3587` `add_test("xtb/landscape-scan-xcontrol" ...)`（ARGS `scanblock;...`）+ `test/unit/meson.build`。
- `def check_native_opt_symbols(...)`：**`test/unit/landscape_cli_check.py:2478`**；调用形态 `main()` 分派 模式 `"nativeoptsym"` → `:3578 check_native_opt_symbols(...)`；注册 `CMakeLists.txt:3649` `add_test("xtb/native-opt-lbfgs-symbols" ...)`（ARGS `nativeoptsym;...`）+ `meson.build:~702`。该用例**依赖原生 `--opt` 语义**（`$opt engine=lbfgs` 走原生 L-BFGS）→ 阶段 3 改派后 `--opt` 不再走原生 L-BFGS，**该用例必须改走 `--opt --method lancopt`**。

### G20/G21. `--opt` / `--ohess` 穷尽扫描（`grep -rn -- '--opt' test/unit/ | grep -v -- '--lopt'` = 33 命中）
| 文件:行 | 用例/上下文 | 为何受影响 | 阶段 3 怎么改 |
|---|---|---|---|
| `landscape_cli_check.py:544-555` | `check_scanblock`（`xtb/landscape-scan-xcontrol`） | 断言 `--opt` **执行** `$scan` | 反转为断言 exit≠0 且文本含 `--method ancopt`/`--lscan`（G1，§14.5） |
| `landscape_cli_check.py:2420-2436` | `check_method_native` 的 `native-reject-opt`/`native-reject-ohess` | R39 拒绝 | **删除**该段（阶段 3 允许套件名） |
| `landscape_cli_check.py:2345-2361,2379` | `check_method_native` 原生出口断言（`--opt --method ancopt|...`） | 仍原生，**应保持** | 保留（但注意 `--ohess` 侧，见下） |
| `landscape_cli_check.py:2388-2414` | `check_method_native` 的 `--ohess` 三文件逐位相同 | `--ohess --method ancopt` 仍原生 | 保留 |
| `landscape_cli_check.py:2403-2406` | `check_method_native` 的**裸 `--ohess`** | 断言原生路径 | ⚠️ 阶段 3 裸 `--ohess` 改派到套件 ⇒ 断言失效，需改 |
| `landscape_cli_check.py:2449-2465` | `check_method_native` U15（`$opt engine=` 冲突） | `--opt --method lancopt` 原生 | 保留（原生分支仍有效） |
| `landscape_cli_check.py:2478-2545` | `check_native_opt_symbols` | 依赖原生 L-BFGS `--opt` | 改用 `--opt --method lancopt`（或 `$opt engine=lbfgs` 仍走原生） |
| `landscape_cli_check.py:508,1881` | docstring/注释 | 文案过时 | 改写文案 |
| `CMakeLists.txt:624` | `xtb/landscape-opt-hess-conflict`（`--opt --hess`→冲突） | 冲突测试，语义不变 | 保留 |
| `CMakeLists.txt:228,3645` | 注释 | 说明过时 | 更新注释 |
| `meson.build:424` | 同上冲突 test | 保留 | — |
| `test_landscape_optimize_xtb.f90:110` | 注释（参考 `--opt` 数值） | 仅注释 | 更新注释 |
| `landscape_e2e_check.py` | **0 命中** | — | — |

### 其它 `--ohess` 命中（`grep -rn -- '--ohess' test/unit/`）
全部在 `landscape_cli_check.py`（`2155/2173/2319/2388-2459`，其余同表）。`--bhess` 在 `test/unit/` **0 命中**（`--bhess` 保持原生，无测试改动）。

---

## H. 破坏性变更与再基线（§10）

### H22. 18 条逐条（A3 + B0 + C8 + D1 + E1 + F4 + G1；§10 汇总行）
- **A1** `--opt` 引擎/数值改变（原生 ANCopt → 套件 lbfgs）。落地：阶段 3。
- **A2** 收敛档位数值阈值改变（4 判据 vs 2 判据）。落地：阶段 3。
- **A3** 旗标面：`-o` 与全部档位一并改派。落地：阶段 3。
- **B0** 文件契约改变——**已清零**（R4 决策②：套件补写 4 文件）。落地：阶段 3。
- **C1** `--lopt --lscan` → error。**已落地（阶段 1）。**
- **C2** `--opt --lopt`/`--opt --hess` → error。**已落地（阶段 1）。**
- **C3** `--lts --lopt-engine bfgs` → error。**已落地（阶段 1）。**
- **C4** `--hess --lvib-temp 400` → error。**已落地（阶段 1）。**
- **C5** 任一原生 runtype + 套件子选项整类 → error。**已落地（阶段 1）。**
- **C6** 未改派 runtype + `--method` → error。**已落地（阶段 2）。**
- **C7** 套件 run type + xcontrol `$opt` 块 → error（**未落地，阶段 3**）。
- **C8** 两个及以上互斥 runtype 旗标 → error。**已落地（阶段 1/§17.1）。**
- **D1** `--cycles INT` 映射到 `max_steps`（`--lvib` 报错）。**未落地，阶段 3。**
- **E1** `--lopt-level` 语义扩大（`e_tol`/`acc`/`max_steps` 随档位）。**未落地，阶段 3。**
- **F1** `-o <level>` 原生→套件。**未落地，阶段 3。**
- **F2** `--strict --zzzz` exit 0 → 非零。**已落地（阶段 1）。**
- **F3** `--opt banana` 静默→normal → error。**未落地，阶段 3。**
- **F4** 套件枚举值大小写不敏感。**已落地（阶段 1）。**
- **G1** `xtb/landscape-scan-xcontrol` 会变红，必须同步改测试。**未落地，阶段 3。**

### H23. 需重测的既有已验收数字（来源报告 + 具体数字）
| 里程碑 | 数字 | 来源报告 |
|---|---|---|
| M3 dfreq | H2O **0.0100** cm⁻¹、CH3OH **0.0600** cm⁻¹ | `docs/xtb-landscape-M7-validation.md:127`；`docs/_landscape-recon/49-m7-validation-experiments.md:60-61` |
| M4 RMSD | MB prfo-vs-bprfo **6.3022e-06** bohr；dimer-vs-prfo **7.7397e-05** | `docs/_landscape-recon/30-m4-fix-report.md:13,155`；`32-m4-final-fix-report.md:22,270-271` |
| M5 barrier | LEPS autoneb **6.0823** kcal/mol；LEPS 端点势垒 **8.9985** | `docs/_landscape-recon/35-m5-path-implementation-report.md:308`；`37-m5-validation-experiments.md:60`；`36-m5-autoneb-string-report.md:238` |
| M6 MEP 偏离 | fwd gs/lqa/hpc/eulerpc = **0.03995 / 0.00657 / 0.00215 / 0.02574** bohr（bwd 0.04132/0.01913/0.01395/0.02806） | `docs/_landscape-recon/44-m6-validation-experiments.md:169-170`；`46-m6-fix-report.md:241` |

> 依赖链：E1 让 `e_tol`/`acc`/`max_steps` 随档位变 ⇒ 上述默认档下的数字全部可能移位（§3.10 建议 3a/3b 分两步）。

---

## 未查（诚实标注）
- `p_run_*` 设计声称的 25 个（§16.6 L-1）与实测 24 不符——差异来源**未查**。
- §3.11 读点表 #6（`fres` 桥）/#12（`fres` 三读者）/`json.F90` 行号**未逐行核实**。
- `--method` 套件名在阶段 3 的**新**分派（`case (p_run_opt, p_run_ohess)` 分支改写后）设计行号**未查**。
- `man/xtb.1.adoc` 的 `--opt`/`--ohess` 文案（`238-241`/`246-248`）与 `src/xhelp.f90:270-272,300` 自指已定位，但**未**逐条比对最终改法。
- `--ohess`(套件) 的 T1/T2/T3 抑制（§3.11.1）**未实测**（本轮未跑 `--ohess` 套件路径，因为它尚不存在）。
