I have enough evidence. Writing the review.

**摘要（≤30 行）**

- 复核对象：W0 的 `-O2` 切换 + 三条静默缺陷修复（报告 04 + 相关源码/测试/构建产物）。只读复核，无法运行命令；证据来自源码走读、`watchdog_diff`、以及 `/tmp/xtb-o2`、`/tmp/xtb-o3`、`/tmp/xtb-base`、`/tmp/o2fix` 中**已存在的**构建缓存/测试日志/产物文件。
- **结论：有条件接受（conditional accept）**。CRITICAL 0 / HIGH 0 / MEDIUM(P1) 1 / LOW(P2) 10 / INFO 若干。三条缺陷的**机制定位与代码修复经独立走读成立**，且被我找到的直接产物佐证。
- **代码行为面未发现静默错误结果**：`-O2` 真的生效（`CMakeCache` `Release` + `CMAKE_Fortran_FLAGS_RELEASE=-O2 -DNDEBUG`）、`$fix` 投影真的落在唯一方向消费点、`$thermo` 优先级真的是「CLI > xcontrol > 默认」、`$scan` 真的响亮报错。
- **P1（唯一实质发现，本轮 diff 使其可达）**：`src/landscape/tasks/vib.f90:286-287` 的 JSON 字段 `temperature`/`freq_scal` 取自 `settings%`（lvset），而修复后**有效值可以来自 xcontrol `$thermo`** ⇒ `--lvib --ljson -I "$thermo temp=400"` 会写出 `temperature: 298.15` 配一个 400 K 的 `gibbs`。修复前这是不可能的（lvset 无条件覆盖 `set%`，二者恰好相等），故属**本轮引入的不一致**，且违反本轮/M4/M7 自己的原则（记录**生效值**，如 `result%etemp`）。无任何测试覆盖（e2e `check_ljson` 不校验该键）。
- P2 要点：4 个 `*_was_set` 只有 2 个（temp/scale）被测（`--lvib-rotor-cutoff` 全仓库无 CLI 测试，`--lvib-imag-cutoff` 只测错误分支）；`check_thermo_settings` 只校验 `settings%`，而 `$thermo scale=-1` 未见校验就会乘进频率；`constraints.f90` 模块注释「BFGS/L-BFGS 可证空操作」只在**解耦初值**下成立（`--lopt-hessian model` + BFGS 的种子是 Lindh-D2，`bfgs.f90:97-138`）；报告测试计数 98 与 100 自相矛盾（源码实测为 **100**）；引用的 `main.F90:914-916`（实际 950-952）与 `irc.f90:673`（实际 695）是**加行后的陈旧行号**；`landscape-lts-fix` 把「PRFO 不收敛」钉成契约；`$scan` 检测漏掉分号分隔的 `-DCMAKE_Fortran_FLAGS="-O3;…"` 与多配置生成器。
- **需运行验证**（我无法跑）：① `/tmp/xtb-o2/build` 现存的 `LastTestsFailed.log` 写着 `179:xtb/landscape-lirc-fix`（179 = 该构建的全局测试序号；同一日志里 `36/179 … 94/179` 证明后续干净运行**不会**清空该文件）⇒ 报告「100/100」在产物层面**无法确认**，必须重跑并确认该文件消失；② edcfbbe 的 `-O3/-O2/-O1/-O0` 构建存在（缓存档位对），但未找到探测输出文件，`-931.59` 这一行需给保存的 stdout 或重跑一次；③ `ctest -N -R landscape` = 100 与测试名唯一性；④ meson 侧 5 个新测试从未执行（未装 meson，报告已如实声明）。
- **未越界**：diff 只含 `cmake/CMakeLists.txt`、`docs/`、`src/landscape/**`、`src/prog/main.F90`、`src/xhelp.f90`、`test/unit/**`；无 ANCopt/scan 删除、无 CLI flag 改名、无核心层改动；新模块同时登记 CMake+meson；5 个新 CLI 测试同时登记 CMake+meson（`fix-projection` 是既有 suite 的新用例，`main.f90` 无需改）。
- 未证实/未复现者：报告 §1.1「本 HEAD 未复现 -O3 异常」的理由**成立**（机制未定位 ⇒ 不可依赖），且报告已明确不把它登记为已知编译器缺陷。

---

以下是完整报告正文（请父会话落盘到 `/home/owenchan/work_path/coding/fortran/xtb/docs/_simplify-recon/05-w0-independent-review.md`）：

````markdown
# 05 — W0 独立复核：（-O2 切换 + 三条静默缺陷）

> **性质**：独立（fresh-context）**只读**复核。不可运行命令、不可改仓库。
> **证据类型**：`watchdog_diff`（reviewer-launch HEAD 的未暂存/未跟踪增量）+ 源码走读 +
> **已存在的**构建/测试产物（`/tmp/xtb-o2/build`、`/tmp/xtb-o3/build`、`/tmp/xtb-base/*`、
> `/tmp/o2fix/*`）。凡「未验证」处已显式标注。
> **审查基准**：是否「测试全绿但仍然错误」。

---

## 0. 结论

**有条件接受（conditional accept）**。

| 级别 | 数量 | 说明 |
|---|---|---|
| CRITICAL (P0) | 0 | 无 |
| HIGH | 0 | 无 |
| MEDIUM (P1) | **1** | `landscape_vib.json` 的 `temperature`/`freq_scal` 报的是设置值而非 `$thermo` 生效值（本轮使其可达） |
| LOW (P2) | 10 | 见 §3：测试可证伪性缺口 3 条、文档/引用不一致 4 条、检测面 3 条 |
| INFO | 4 | 见 §3 |

三条缺陷的**修复本身**（代码行为）未发现错误：机制定位逐行成立（下文 §1 逐条给证据），
且被现成产物佐证（`/tmp/xtb-o2/build/test/unit/landscape-cli-fix/xtbopt.xyz` 的固定 O 逐位为
`0.00000000000000 0.00000000000000 0.00000000000000`、能量 `-5.070544411705`，与报告 §2.3 的
rfo 行**逐字相同**；`landscape-cli-lts-fix/xtbts.xyz` 的固定 H 逐位为
`0.00000000000000 1.05000000000000 0.00000000000000`）。

---

## 1. 逐条判定表

### 1.1 `-O2` 切换

| 项 | 判定 | 证据 |
|---|---|---|
| 官方命令是否真的是 -O2 | ✅ **成立** | `/tmp/xtb-o2/build/CMakeCache.txt:58` `CMAKE_BUILD_TYPE:STRING=Release`，`:134` `CMAKE_Fortran_FLAGS_RELEASE:STRING=-O2 -DNDEBUG`。对照 `/tmp/xtb-o3/build/CMakeCache.txt:134` = `-O3`（同源码，仅档位不同） |
| 有无遗漏的 `-O3` 路径 | ✅ 无 | 全仓库 grep：只有 `cmake/CMakeLists.txt:61-87` 的新注释/检测出现 `-O3`；`meson/README.adoc:155-157` 只是上游文字；`meson.build:26,28` 已是 `buildtype=debugoptimized` + `optimization=2`。`libxtb.a/.so` 与测试目标与 `lib-xtb-static`/`lib-xtb-shared` 共用同一 flags，无独立 `-O3` |
| 警告是否真的触发且不失败构建 | ✅ 成立 | `/tmp/o2fix/warn.log` 原文：`CMake Warning at cmake/CMakeLists.txt:79 (message): Fortran optimisation level -O3 is not supported …`，并继续 `-- Configuring done (17.3s) / -- Generating done`（是 warning 不是 error） |
| 检测逻辑能否看到变量 | ✅ 成立 | `CMakeLists.txt:38 add_subdirectory("cmake")`（在 `project()` 之后），子目录作用域**继承**父作用域的 `CMAKE_BUILD_TYPE` / `CMAKE_Fortran_FLAGS*`，故 `CMAKE_Fortran_FLAGS_RELEASE=-O3` 可被读到 |
| 「未复现」结论是否诚实的 | ✅ 诚实 | 报告 §1.1 明确写「本 HEAD 未复现」，且**不**登记为已知编译器缺陷，只标「不可依赖」；理由（机制未定位、对源码状态 156 提交敏感、-O2 代价实测为零）成立。**没有**用「没复现」推「-O3 安全」 |
| 验收数字是否逐项对照 | ✅ 已对照 | 报告 §1.4 给出四体系 dfreq/dZPE/dH/dG 三档对照；我用仓库内 `docs/_landscape-recon/m7-e2e-data/exp1-thermo/summary.json:354-364,393` 核对 H2O：`hess[1539.58,3643.01,3651.16]`、`lvib[…,3651.17]`、`max_dfreq = 0.010000000000218279` —— 与报告「0.0100」及 `/tmp/o2fix/acc/o2-h2o/vibspectrum` 逐值一致 |
| 优化档是否影响数值 | ✅ 如实 | 报告主动加了 c2h2（线性）例外：`hessian` 文本有「打印零的符号」与 9e-14 Å 舍入差，**不**写成普遍命题。这是本轮最诚实的一处 |
| `-O3` 探测行是否有真实输出 | ⚠️ 部分 | `/tmp/o2fix/o3probe/o3.log:261,319` 有 `eigval: 1557.41 3677.84 3684.01`（本项目源码 `-O3`，正确）；edcfbbe 的五个构建目录（`/tmp/xtb-base/build{,-O2,-O1,-o0,-o3nov}`）存在、缓存档位正确，但**未找到保存的探测 stdout**，`-931.59` 一行只能由报告 03 与本轮重跑共同支撑（见 §4.2） |

### 1.2 缺陷①：`--lopt-engine rfo` 违反 `$fix`

| 项 | 判定 | 证据 |
|---|---|---|
| 机制定位（`$fix` 在计算器层置零梯度） | ✅ 成立 | `src/xtb/calculator.f90:300-307`（`if (fixset%n.gt.0) … gradient(1:3,fixset%atoms(i))=0`）；套件经 `xtb_single::singlepoint` 取梯度，故该置零**已经**生效；`$freeze`（只影响 Hessian 投影）刻意不读，`constraints.f90:59-71` 注释一致 |
| 「一阶对、RFO 错」解释与代码一致 | ✅ 成立 | SD `d=-g`（唯一非零项来自 `g`）；CG `d=-g+βd_old`；GDIIS `d=Σcᵢxᵢ−x`（`diis.f90:202`，`Σcᵢ=1` 且快照共享固定分量）；**BFGS 需要限定条件**（见 P2-3）；RFO `d=−Σ(Vᵢ·g)/(wᵢ−λ)Vᵢ`（`rfo.f90:197-199`），`Vᵢ` 是**完整** Hessian 本征矢 ⇒ 固定分量一般非零。⇒ 父会话怀疑**确认** |
| 投影是否真的落在「全部方向」上 | ✅ 成立 | 唯一方向消费点在 `optimize/driver.f90:277-286`（`select case` 之后、`use_trust`/`clip_step` 之前）。我逐条核对了三条取步分支：trust 分支 `step = d`（:288-292）、非 trust 分支 `take_descent_step(..., d, ...)`（:317-319，line search 只缩放 `d`）、SD 回退 `steepest_fallback` 自建 `dir=-g`（:462-479，固定分量天然为 0）⇒ 无旁路 |
| 投影算子是否与 `$constrain`/`$fix` 的冻结坐标一致 | ✅ 成立 | `landscape_frozen_mask` 只读 `xtb_fixparam::fixset`（`src/fixparam.f90:33,124`），与计算器置零用的是同一个对象；索引 1-based、越界 `cycle`、未分配时返回全 `.false.`，长度 `3N` |
| 是否有别的二阶路径被遗漏 | ✅ 基本覆盖，🔎 一处**声明过宽** | 见 P2-3（`--lopt-hessian model` + bfgs）。`--lts` prfo/bprfo（`saddle/prfo.f90:589-591`）+ escape（`:792`）+ dimer（`saddle/dimer.f90:830-834`，在零范数判据**之前**）都在 `x_trial = x + step` 之前；band/IRC 改为报错（`tasks/ts.f90:207-227`、`tasks/irc.f90:172-190`）。`--lirc` 端点松弛的 `frozen=` 实参（`irc.f90:695`）在 `$fix` 下不可达（入口已报错）——**死代码但无害**（INFO-2） |
| 逐引擎位移表可信度 | ✅ 产物佐证 | `/tmp/xtb-o2/build/test/unit/landscape-cli-fix/xtbopt.xyz`（循环最后一个引擎 = rfo）固定 O 逐位 0，能量 `-5.070544411705` = 报告 §2.3 的 rfo 行；`landscape-cli-lts-fix/xtbts.xyz`（最后一个方法 = dimer）固定 H 逐位 `0 1.05 0` |
| 注入是否真能变红 | ✅ 结构上可信 | `/tmp/o2fix/inject.py` 的 8 个变异：`1/3/s1/s2/s3/r1/r2` 是**纯删除/`.false.` 禁用**（与修前语义等价），`2` 是**逐字回滚**修前原文（符合 M4「先证明语义等价」教训）；`CTestCostData.txt:108-112` 显示 5 个新测试各跑 6-10 次，与 A/B 注入轮次吻合 |

### 1.3 缺陷②：`--lvib` 覆盖 `$thermo`

| 项 | 判定 | 证据 |
|---|---|---|
| 优先级语义是否真的实现 | ✅ 成立 | `vib/thermo.f90:185-192`：4 个 `if (…_was_set)` 才写 `set%`；4 个标志只在 `main.F90:3764/3780/3797/3813` 的 4 个 `--lvib-*` case 里被置真（`grep lvset%` 确认**没有**其他写 `lvset%temperature/freq_scal/…` 的地方，也没有 `set% → lvset%` 的反向同步） |
| 哨兵值是否与合法输入冲突 | ✅ 无哨兵值 | 用独立 `logical` 标志而非特殊数值；`--lvib-temp` 把 `temperature` 整体清零后写 `(1)` 并置 `n_temperature=1`，与 `$thermo` 列表不冲突 |
| `$thermo` 全部键是否处理 | ✅ 4/4 | `src/set_module.f90:1960-2014` 的 `select case(key)` 只有 `temp`/`sthr`/`imagthr`/`scale`（default 分支只 warning）；4 个键 → 4 个标志 → `set%nthermo/thermotemp`、`thermo_sthr`、`thermo_ithr`、`thermo_fscal` 一一对应。`set_module.f90:2912-2913` 的 legacy 路径映射到同一对键，无第 5 个键 |
| 与 `--hess` 的对照是否用同一 input | ✅ 成立 | `test/unit/landscape_cli_check.py:552-560`：`thermo("lvib", ["-I", name+".inp"])` 与 `thermo("hess", ["-I", name+".inp"])` **同一个文件同一几何**；几何先经 `--lopt --lopt-level tight` 取极小（容差 1e-6 Eh 的校准点） |
| 参照语义是否讲清 | ✅ | 报告 §3.3 明确 `--hess` 是参照、余差 1.4e-8 是 M3 记录的投影约定残差；任务书「不是逐位相等」被遵守 |
| **JSON 是否记录生效值** | ❌ **P1** | 见 §3 MEDIUM-1 |

### 1.4 缺陷③：`--lopt` 静默忽略 `$scan`

| 项 | 判定 | 证据 |
|---|---|---|
| 现在是否报错 | ✅ 成立 | `main.F90:478-508`：`select case (set%runtyp)` → 5 个 landscape runtyp → `env%error(… "does not execute the xcontrol $scan block" …)` + `env%checkpoint`。`env%error` 记录错误、`checkpoint` 打印 `Program stopped due to fatal error` 并终止 ⇒ 非零退出（报告 §4.2 有实测 `exit = 1`） |
| 错误信息是否可操作 | ✅ 给出两个替代 | 「use `--opt` to run it, or `--lscan` with `--lscan-coord/--lscan-atoms`」 |
| 位置是否在任务运行之前 | ✅ 成立 | 紧接 `read_userdata`（`:476`）之后；`set%runtyp` 由 `parseArguments`（`:252`）在更早已设定，故判断可靠 |
| `nscan` 判据是否可靠 | ✅ 成立 | `nscan` 是 `src/scanparam.f90:37` 的全局量，`$scan` 的每一条都由 `constrain_param.f90:868` 自增；`$scan` 块必然使 `nscan > 0` |
| 「只被 ANCopt 消费」是否成立 | ✅ 成立 | `main.F90:949-952` 的 `if (nscan > 0) call relaxed_scan(...)` 位于 `if (anyopt)`（`:938`）内部；`anyopt`（`:314-316`）不含任何 landscape runtyp |
| 表格是否完整（任务 × 块） | ✅ 基本完整 | 报告 §4.3 用「消费者分类」逐块给出：CALC 层块（`$constrain/$fix/$wall/$metadyn/$gbsa/$embedding/$external/$scc/$gfn/$cma/$symmetry`）= 消费；MAIN/ANC 独占块中只有 `$scan` 属「同一用户意图被降级」⇒ 硬错误；`$hess/$opt/$md/$siman/…` = 忽略且文档化。我独立复核了「任务清单」（runtyp = lopt/lscan/lts/lirc/lvib，`setparam.f90:206-215`；`sp` 无 runtyp，`CMakeLists.txt:2915-2923` 注释一致）与「xcontrol 块清单」的对照，**未发现被漏归类**的块 |
| 是否引入新的静默忽略 | ✅ 未发现 | `--ljson` 无 runtyp 由既有 warning 覆盖（`main.F90:980-985`）；`--lvib` 的 4 个 `--lvib-*` 现在只在显式给出时生效，且帮助补了三行（`xhelp.f90:659-662`）。`$wall`/`$metadyn` 只有静态证据（报告已标「静态」） |

---

## 2. 范围与越界判定

`watchdog_diff --stat`：20 文件、+910/−21。文件清单判定：

| 允许范围 | 实际 | 判定 |
|---|---|---|
| `src/landscape/**` | `types/constraints.f90`（新，未跟踪）、`optimize/driver.f90`、`saddle/{prfo,dimer}.f90`、`scan/relax_scan.f90`、`tasks/{opt,ts,irc,vib?}`、`vib/thermo.f90`、`types/settings.f90`、两个 `CMakeLists.txt`/`meson.build` | ✅ |
| `src/prog/main.F90`、`src/xhelp.f90` | 只加 `$scan` 守卫 + 4 个 `*_was_set` + 帮助文字，**无 flag 改名** | ✅ |
| `test/unit/**` | 5 个新 ctest 条目（CMake+meson 双登记）+ 1 个既有 suite 新用例 + `landscape_testpot.f90` 新模型 | ✅（`main.f90` 无需改：CLI 测试由 python 驱动，新用例在原 suite 内） |
| `docs/**`、`cmake/CMakeLists.txt` | PLAN 更新 + 报告；cmake 仅 +28 行**警告**（§1.2 已证明是 warning 且值有据） | ✅ |
| **不得删除 ANCopt/scan 代码** | `−21` 行全部是签名/被替换语句（driver 形参、thermo 的 4 行无条件覆盖等），`src/optimizer.f90`、`src/scan_driver.f90`、`src/prog/main.F90` 的 `relaxed_scan` 路径**零删除** | ✅ |
| **不得改核心层** | `type/xtb/mctc/param/io/disp/coulomb` 修改文件数 = 0 | ✅ |

---

## 3. Findings

### MEDIUM-1 (P1) — `landscape_vib.json` 报的是设置值，不再是 `$thermo` 的生效值

- 位置：`src/landscape/tasks/vib.f90:286`（`call landscape_json_add_value(doc, 'temperature', settings%temperature(1))`）与 `:287`（`… 'freq_scal', settings%freq_scal`）。
- 证据链：本轮把 `settings%` 从「无条件写进 `set%`」改成「仅在 `*_was_set` 时写」（`vib/thermo.f90:185-192`），因此**未给 CLI flag 时**生效值来自 xcontrol `$thermo`（`set_module.f90:1960-2014` → `set%thermotemp/nthermo`、`set%thermo_fscal`），而 `settings%temperature(1)` 保持 lvset 默认 `298.15`、`settings%freq_scal` 保持 `1.0`（`settings.f90:585-587,606`）。`write_json` 拿的是 `intent(in)` 的 `settings`（`vib.f90:262`），`landscape_vib_set_thermo_settings` 也是 `intent(in)`（`thermo.f90:179-181`），**无回写**。
- 后果：`xtb m.xyz --gfn2 --lvib --ljson -I "$thermo：temp=400"` 的文档里 `temperature: 298.15` 与 `values.gibbs`（400 K 的结果）自相矛盾；`:287` 对 `$thermo scale=0.9` 同理（`freq_scal: 1.0`，实际 0.9）。这正是 M7 明文要求「JSON 是机器可读回归产物、必须同源于生效值」的反例，也与同一代码库 `result%etemp` 的「记录读回值」原则（`tasks/vib.f90:191-194`、`engine.f90:771-779`）不一致。
- **是本轮 diff 使其可达**：修复前 `--lvib` 无条件用 lvset 覆盖 `set%`，两者恰好相等；现在可以不相等。
- 无测试覆盖：`test/unit/landscape_e2e_check.py` 的 `check_ljson` 只交叉断言 counters 与部分 energy，`grep temperature` 在 e2e 检查中 0 命中 ⇒ 该歧义**永久绿**。
- 最小修法：把生效值写进结果对象（与 `etemp` 同一套路）——在 `vib/thermo.f90` 里 merge 之后记录 `vib%temperature = set%thermotemp(set%nthermo)`、`vib%freq_scal = set%thermo_fscal`，`write_json` 改用它们；或在 `check_thermo` 里加一条断言（同一 input 下 `--lvib --ljson` 的 `temperature` 必须等于 `$thermo` 的 400）。

### LOW (P2) — 测试可证伪性缺口

- **P2-1（可证伪性 2/4）**：4 个 `*_was_set` 守卫只有 `temperature_was_set` 与 `freq_scal_was_set` 被 `check_thermo` 覆盖（`landscape_cli_check.py:552-595`）。`--lvib-rotor-cutoff`（`sthr`）在**整个 test/unit 零引用**（与报告 02 §5.2 的「58 个套件参数无 CLI 测试引用」一致），`--lvib-imag-cutoff` 只有「正数报错」分支（`CMakeLists.txt:948-952`）。⇒ 只回滚 `rotor_cutoff_was_set`/`imag_cutoff_was_set` 两行会**保持全绿**；注入 2 一次回滚 4 行，无法隔离。修法：`check_thermo` 增 `sthr`/`imagthr` 各一例（`$thermo sthr=500` vs `--lvib-rotor-cutoff 500`）。
- **P2-2（校验对象过窄）**：`src/landscape/tasks/vib.f90:318-327` 的 `check_thermo_settings` 只校验 `settings%`，但生效值现在可来自 `$thermo`，而上游 `set_thermo` 对 `scale` **没有正性检查**（`set_module.f90:2011`）。⇒ `--lvib -I "$thermo：scale=-1"` 会带着负 scaling 跑，`print_thermo` 把它乘进频率（`src/main/property.F90:1318-1319,1356`）——正是 LOW-2 那条校验想防的失效模式。修法：merge 之后校验生效值（或 `set%thermo_fscal`）。
- **P2-3（声明过宽）**：`constraints.f90:36-49`（及报告 §2.1 表）称 SD/CG/L-BFGS/BFGS/GDIIS 的投影「可证空操作」。对 **BFGS** 只在初值解耦时成立：`driver.f90:195-205` 在 `hessian_source == 'model'` 时把 **Lindh-D2 曲率矩阵**当种子塞进 `bfgs%set_hessian`，而方向是 `d = −Σ(Vᵢ·g)/max(wᵢ,hlow) Vᵢ`（`bfgs.f90:95-140`），固定分量不再为零。代码是对的（投影对每条方向都生效），但该组合（`--lopt --lopt-hessian model --lopt-engine bfgs` + `$fix`）**无测试**，且注释的普适性主张不成立。修法：软化措辞 + 加一条该组合的 CLI 断言。
- **P2-4（测试把「不收敛」钉成契约）**：`landscape_cli_check.py:665-676` 要求约束 P-RFO **必须** `status != 0` 且信息为 `maximum number of steps reached`。报告已声明这是「诚实契约」，但将来若 P-RFO 的 rho/trust 规则被合理改进（M4 已知项）该测试会因**好事**变红，容易诱发「弱化 `$fix` 断言」。建议只钉位移 + 「converged 或 预算耗尽」。
- **P2-5**：`--lscan` + `$fix` 若固定原子属于被扫描坐标，松弛内层被投影（原子不动）后目标坐标不可达，但点的 `converged` 仍可为真（值/残差列有记录，故不算静默）。PLAN §6.9 只把 **rigid** 模式列为待办，relaxed 行标 ✅ 却既无测试也无这条说明。

### LOW (P2) — 文档/引用一致性

- **P2-6（自相矛盾的数字）**：报告 §0 行 6 与 §5.4 说 100，§1.1 结论第 3 点、§1.3 表、§5 标题说 98（且 §5 写「新增的 3 个测试（95 → 98）」却列了 4 个名字）。我按源码实测：`add_test("xtb/landscape-…` 共 80 条 + `foreach(task IN ITEMS opt scan scan2d vib ts irc)` 展开 6 条 = 86 条，加 `tests` 列表里 15 个 `landscape-*` test-drive suite ⇒ **100**，与 95 + 5 相符。⇒ §1.3 的 `-O2`/`-O3` 对照表是**中间态**（98）而非最终态，应标注或重测。
- **P2-7（陈旧行号）**：`main.F90:480-482` 的注释与报告 §4.1 引用 `relaxed_scan` 在 `src/prog/main.F90:914-916`，实际（加行后）是 `:949-952`；报告 §2.2/PLAN §6.9 引 `tasks/irc.f90:673`，实际是 `:695`。（`tasks/opt.f90:140`、`tasks/ts.f90:1211`、`relax_scan.f90:648` 三个引用是对的。）
- **P2-8（绝对化措辞）**：报告 §1.2 表写 `-DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"` → 「**0 warning**」，但 `/tmp/o2fix/config-o2.log:16-20` 有一条来自 FetchContent `test-drive` 的 CMake **Deprecation** Warning（与 -O3 无关）。应写「无 -O3 警告」。
- **P2-9**：`--lscan` + `$scan` 被纳入硬错误是**范围判断**（报告 §7.2-5 已显式请拍板，诚实）；但通用消息对 `--lscan` 情形自指（"`--lscan` … use … or `--lscan` with `--lscan-coord`"），读起来像在建议用户已经给过的东西。

### LOW (P2) — 检测面

- **P2-10**：`-O3` 检测的正则 `(^| )-O3( |$)` 对**分号分隔**的 CMake 列表（`-DCMAKE_Fortran_FLAGS="-O3;-funroll-loops"` ⇒ `;-O3;`）不匹配；多配置生成器（`CMAKE_BUILD_TYPE` 为空）整段被 `if(CMAKE_BUILD_TYPE)` 跳过。两点报告均在 §1.2 表里**如实记录**，不是隐性缺陷，但检测覆盖率不是 100%。

### INFO

- **INFO-1**：`src/landscape/tasks/opt.f90:130-137` 新增 stdout 行 `fixed atoms ($fix): N (three components each)` 无任何测试断言（项目「新行为必须有测试」纪律）。
- **INFO-2**：`tasks/irc.f90:695` 的 `frozen=landscape_frozen_mask(...)` 实参在 `$fix` 下不可达（入口 `:172-190` 已报错）——死代码，无害；但它同时是「`--lirc` 端点松弛被修」这一说法在 AGENTS §6 的落点，容易误读为「`--lirc` + `$fix` 可用」。
- **INFO-3**：`$scan` 守卫与上游「冲突组合首选项静默获胜」的交互（报告 02 §4.4）：`--lopt --opt -I $scan` 的 runtyp 是 lopt（第二个 `set_runtyp` 的 `raise('S',…)` 从不显示），新守卫会报错而**用户确实传了 `--opt`**。行为上比「静默只优化」好，但消息未提冲突。
- **INFO-4**：报告 §5 的小节标题编号重复（两个「## 5」，第二处是第二轮的「### 5. 修复的第二轮」），§6 随之错位——纯排版。

---

## 4. 需运行验证清单（只读复核无法执行）

1. **最终 `ctest -R landscape`**：`/tmp/xtb-o2/build/Testing/Temporary/LastTestsFailed.log` 现存 `179:xtb/landscape-lirc-fix`。该文件是**上一次有失败的运行**留下的（`LastTest.log` 的 `36/179 … 94/179` 证明过滤运行仍用全局序号，且最后那次干净运行（12 个回归测试）**没有**清空它，`/tmp/xtb-o3/build` 无此文件也印证「只在失败时写」）。因此 100/100 这一条**在产物层面无法确认**，请重跑 `ctest --test-dir /tmp/xtb-o2/build -R landscape` 并附 `LastTestsFailed.log` 缺失/为空的证据。
2. **edcfbbe 的 `-O3` 探测输出**：`/tmp/xtb-base/build{,-O2,-O1,-o0,-o3nov}` 存在、缓存档位正确，但未找到保存的 stdout；请附 `-931.59 3329.78 3345.94` 那一行所在的原始日志（否则该行应标为「引自报告 03」而非本轮实测）。
3. `grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d` → 空；`ctest --test-dir /tmp/xtb-o2/build -N -R landscape | tail -1` → 100（我按源码点数为 86 + 15 = 100，未见重名，但需机器确认）。
4. meson 侧 5 个新测试从未执行（未装 meson）——报告已如实声明；若 CI 有 meson，需要跑一次。
5. **P1 的最小复现**（也验证我的判定）：`xtb h2o.xyz --gfn2 --lvib --ljson -I <含 $thermo temp=400 的文件>`，检查 `landscape_vib.json` 的 `values.temperature` 是否等于 400。
6. **P2-1 的复现**：只注释 `vib/thermo.f90:190-191` 两行，`ctest -R landscape` 是否仍 100% 通过（预期：通过 ⇒ 证明那两条守卫不可证伪）。

---

## 5. 无法验证 / 未复现的如实声明

1. 我**没有**运行任何命令（只读），故报告 04 的绝大多数「★实测」是**佐证**（与产物/源码/缓存一致）而非我自己的重测。
2. 我**未**独立验证 `-O3` 在 edcfbbe 上给错频率（无保存输出，无法执行）。
3. 我**未**验证 mesa/meson 路径（未安装 meson）。
4. 我**未**逐值核对 c2h2 的 `hessian` 文本差异（报告已给出 `max|delta|=0`、`8.993e-14` 的说明，我只看其结论**不自相矛盾**）。
5. 我**未**核对 47 份 M0..M7 历史文档的一致性——超出本轮范围。

---

## 6. 一句话处置建议

`-O2` 与三条缺陷的**代码修复可以合入**（机制、落点、报错与产物全部核对通过）；
合入前建议处理 **MEDIUM-1**（JSON 报生效值）与 **P2-1**（`sthr`/`imagthr` 两条守卫的测试），
并重跑一次 landscape 全绿以消除 `LastTestsFailed.log` 的疑点；其余为报告级修正。
````