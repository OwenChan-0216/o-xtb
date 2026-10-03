## 摘要（≤30 行）

- **结论：有条件接受（conditional accept）**。CRITICAL 0 / HIGH 0 / MEDIUM 0 / LOW 4 / INFO 2。
- **W0 现在可以提交 git**：核 05 的 P1 与 6 条 P2 的**代码修复全部经走读成立**（见下逐条表），未发现静默错误结果、未越界；条件是**随提交附上运行证据**（我只有只读工具，无法跑：101/101、回归 12/12、`LastTestsFailed.log` 不存在、M7 四体系重测、三条缺陷修后行为）。
- **P1（真修）**：`vib.f90:300-301` 改读 `vib%temperature`/`vib%freq_scal`；`thermo.f90:161-164` 从容器读回 `res%temp`（`set%thermotemp(set%nthermo)`，与 `htot=et(set%nthermo)` 同源，`property.F90:781/1330-1331`），`:131-134` 写 `set%thermo_fscal`（合并后）。**不是改名的 settings%**。注入回滚（`settings%temperature(1)`/`settings%freq_scal`）时 `check_thermo:647` 的 400 K 断言必红。测试同时断言「与 gibbs 自洽」（两 run gibbs 已断言相等 + temperature 相等）。无可漏 consumer（grep 全仓库仅此一处报告该值）。
- **P2-1（真修）**：`--lvib-rotor-cutoff`/`--lvib-imag-cutoff` 生效性由新 `check_thermo_knobs`（`landscape_cli_check.py:698-817`）覆盖，4/4；删除任一守卫会红（sthr `:745`；imagthr `:791`）。
- **P2-2（真修）**：校验移到 `thermo.f90:237-273`，读**合并后** `set%`；任务在首个单点前先 merge 再 check（`vib.f90:116-117`）。追代码确认 `$thermo scale=-1` 现在 `set%thermo_fscal=-1` → `env%error` + 非零退出（不是乘进频率）。
- **P2-3（部分修）**：04 的 98/100 已订正并标注口径，但**残留一处**未标注的 98（04:872）与过期的「三条新 meson 测试」（04 §7.1.3，现为 6）——LOW。
- **P2-4（真修）**：04/PLAN/main.F90 的裸行号已改为子程序名/分支描述（`grep` 0 命中）；但 `constraints.f90:76` 仍留裸行号且**是错的**（`main.F90:473` 实为 476）——LOW。
- **P2-5（真修，选项 b）**：`check_saddlefix:880-907` 断言的是**失败语义**（converged→exit 0；未收敛→exit≠0 且输出含 `transition state search did not converge`），**没有**把「就该不收敛」固化；bprfo/dimer 断言真收敛。理由（120/400/1200 步均不收敛）写在 docstring 与 `ts.f90:323-330` 的对偶处。
- **P2-6（真修）**：CMake 遍历 `CMAKE_BUILD_TYPE`+`CMAKE_CONFIGURATION_TYPES` 并 `string(REPLACE ";" " ")`（`cmake/CMakeLists.txt:66-90`）；`constraints.f90:34-49`、`driver.f90:280-287` 措辞已软化（BFGS 限定解耦初值），并补 `bfgs model`/`rfo model` 断言。
- **LOW（不阻断）**：① `xtb/landscape-vib-thermo-knobs` **漏在** CMake 的 `OMP_NUM_THREADS=1` 名单外（`test/unit/CMakeLists.txt:3104` vs `:2840-2870`/`:3136`；meson 侧有）；② `constraints.f90:120-126` 声称 `path/*`、`irc/*` 是本模块入口——实测二者**不调用**（改为报错）；③ 04:872 残留 `98/98`；④ 06 §1.5 表未记 `freq_scal` 的 GFN-FF 1.03 特例，且 `n_imag`/`status` 的同类分歧仍未修（§4.1 已如实登记、新测试刻意不钉）。
- **越界**：0。diff 仅 `src/landscape/**`、`main.F90`（**纯增行**）、`xhelp.f90`、`cmake/`、`test/unit/**`、`docs/`；核心层 0 文件；无 flag 改名；无 ANCopt/scan 删除（`optimizer.f90`/`scan_driver.f90` 未在变更表）。
- **需运行验证**：见报告 §5（10 项）；meson 侧 6 条测试未执行（本机无 meson，报告已声明）。

---

以下为完整报告正文（请父会话落盘到 `/home/owenchan/work_path/coding/fortran/xtb/docs/_simplify-recon/07-w0-closeout-review.md`）：

````markdown
# 07 — W0 收尾（核 05 的 1×P1 + 6×P2）独立复核

> **性质**：独立（fresh-context）**只读**复核。不可运行命令、不可改仓库、不可提交。
> **复核对象**：`docs/_simplify-recon/06-w0-closeout-report.md`、`05-w0-independent-review.md`、
> `04-o2-and-silent-defects-fix.md`，以及修复涉及的源码/测试/构建文件。
> **证据类型**：`watchdog_diff`（reviewer-launch HEAD 的未暂存/未跟踪增量）+ 逐行源码走读。
> 凡「需运行」处已显式列入 §5，不冒充已验。
> **审查基准**：是否「测试全绿但仍然错误」。

---

## 0. 结论

**有条件接受（conditional accept）**。

| 级别 | 数量 | 说明 |
|---|---|---|
| CRITICAL (P0) | 0 | 无 |
| HIGH | 0 | 无 |
| MEDIUM | 0 | 核 05 的 P1 与 6 条 P2 **代码修复均成立** |
| LOW (P2) | 4 | 测试注册漏项 1、注释/引用错误 1、报告残留计数 1、JSON 表覆盖不足 1（§4） |
| INFO | 2 | checkpoint 措辞、注入形式（§4） |

**「W0 现在是否可以提交 git？」→ 可以。** 代码层面无阻断项：P1 是**真修**（不是把 `settings%` 换名字），
6 条 P2 逐条落地且各自的注入都能红，无越界，未改动任何数值路径的算式。
提交前（或同一提交内）建议一并落 §4 的 4 条 LOW（全部不改变行为，1 行级改动）。
**我唯一无法确认的是「全绿」本身**：报告 §3 的 101/101、回归 12/12、`LastTestsFailed.log` 缺失、
M7 四体系重测、鞍点三方法实测、CMake 配置级注入实验，都只有 worker 自报；请附 §5 的绿证。

---

## 1. 逐条判定（P1 + P2-1..6）

### P1 — `--lvib --ljson` 必须记录生效值 ⇒ **已修复（真修）**

逐行走读的四段链路：

| 段 | 位置 | 判定 |
|---|---|---|
| xcontrol 解析 | `read_userdata`（`src/prog/main.F90:476`）→ `xtb_setparam::set_thermo` → `set%thermotemp/nthermo`、`thermo_sthr/ithr/fscal` | 生效值来源 1 |
| 优先级决定 | `vib/thermo.f90:207-214`：只有 4 个 `*_was_set` 才写 `set%`；CLI 写点唯一（`main.F90:3763/3779/3796/3812`） | 生效值 = `set%` |
| 结果赋值 | `vib/thermo.f90:161-164` `vib%temperature = res%temp`；`res%temp = set%thermotemp(set%nthermo)`（`src/main/property.F90:781`）；`vib%freq_scal = set%thermo_fscal`（`:131-134`） | **从容器读回**，与被描述的 `gibbs` 同源 |
| JSON 写出 | `tasks/vib.f90:300-301` 读 `vib%`；新字段在 `types/results.f90:90-105` | ✅ |

- **不是改名**：`res%temp` 是 `print_thermo` 真正用来算 `gtot=gt(set%nthermo)` 的同一表达式
  （`property.F90:1330-1331` vs `:781`）；`freq_scal` 取合并后的 `set%thermo_fscal`
  （`print_thermo` 实际乘的那个量，`property.F90:1356`）。
- **无第二消费者**：全仓库 `settings%temperature|freq_scal|rotor_cutoff|imag_cutoff` 的引用只剩
  merge 与 `ts.f90`/`irc.f90` 的 `imag_cutoff` 传递——没有别处再报告设置值。
- **测试真能捕获回滚**：注入＝把 `vib.f90:300-301` 逐字改回 `settings%temperature(1)`/`settings%freq_scal`
  （核 05 记录的修前原文）。此时 `--lvib --ljson -I temp400.inp` 的 `temperature` = lvset 默认
  `298.15`（`settings.f90:585`），而测试在 `landscape_cli_check.py:644-650` 断言
  `abs(xc_temp-400) > 1e-9 → fail` ⇒ **RED**。`freq_scal` 同理（`:659-668` 断言 0.9）。
- **自洽性断言充分**：同一文档内 `temperature==400` 且 `gibbs` 与 `--lvib-temp 400` 的 run
  **逐位（1e-9）相等**（`:637-643`），后者在 `--lvib`↔`--hess` 段已被钉在 1e-6 内 ⇒ 不是「同温度巧合」。
- **「其它任务同类问题」表（06 §1.5）**：我独立列了一遍所有任务的 JSON 键，判据用「该值是否可能来自
  `settings%` 而生效值另有来源」：

| 任务 | 取自 settings 的键 | 第二来源 | 我的判定 |
|---|---|---|---|
| `sp` | 无 | — | 与表一致 |
| `opt` | 无 | — | 与表一致 |
| `scan` | `bidirectional`（`scan/scan1d.f90:215` = `settings%`，驱动同一 `if`） | 无（`--lscan-bidirectional` 唯一写点） | 与表一致 |
| `ts` | `method`、`verify_ts`（`tasks/ts.f90:368-369`；使用点 `:289/:362` 直接读 settings） | 无 | 与表一致 |
| `irc` | `method`（`tasks/irc.f90:436`） | 无 | 与表一致 |
| `vib` | ~~`temperature`/`freq_scal`~~ → 已修；`project_tr`（`:303`） | `project_tr` 无第二来源 | 与表一致 |
| 全体 | `etemp`（共享块，`json.f90:361`） | 读回计算器 | 与表一致 |
| `vib` | `counters.n_imag`/`status`/`status_name` | **有**：分析用 `settings%imag_cutoff`（`vib/modes.f90:319`），热化学用 `set%thermo_ithr` | 表已登记为未修发现（§4.1），**遗漏的只有 GFN-FF 的 `freq_scal` 特例**（LOW-4） |

⇒ 结论：**P1 已修复**；表基本完整，仅一处覆盖不足（LOW-4）。

### P2-1 — `sthr`/`imagthr` 两条守卫的生效性测试 ⇒ **已修复**

- 新 ctest `xtb/landscape-vib-thermo-knobs`：CMake `test/unit/CMakeLists.txt:3104-3110`、
  meson `test/unit/meson.build:293-297`（**双登记**），python 入口 `landscape_cli_check.py:1781-1784`
  （`thermoknobs` 需要第 5 个实参＝鞍点几何）。
- 每个旋钮两次断言：**生效** + **合并**（`sthr`：`sthr_cli != sthr_default`（`:744-747`）
  且 `sthr_cli == sthr_xc`（`:748-751`）；`imagthr`：`n_imag 1→0`、`status ok`、
  `|ΔG|>1e-6`、`cli_g == xc_g`、打印的 `imag. cutoff` 与 `inverting freq`（`:786-812`））。
- **可红**：删除 `rotor_cutoff_was_set` 行（`thermo.f90:212`）⇒ `--lvib-rotor-cutoff 2000` 后
  `set%thermo_sthr` 仍为 50 ⇒ `sthr_cli == sthr_default` ⇒ `:745` 变红；删除 `imag_cutoff_was_set`
  ⇒ `n_imag` 仍为 1 ⇒ `:791` 变红。**两条守卫可隔离**，比核 05 描述的（一次回滚 4 行）好。
- 4/4 达成（temp/scale 由 `check_thermo`，sthr/imagthr 由 `check_thermo_knobs`）。
- 遗留：该测试**漏在** CMake 的 `OMP_NUM_THREADS=1` 属性名单外（LOW-1）。

### P2-2 — 校验必须针对生效值 ⇒ **已修复（真修）**

- 私有 `check_thermo_settings`（只读 settings）**已删除**（`vib.f90:308-351` 的 −44 行）；新
  `landscape_vib_check_thermo_settings(env, ok)`（`vib/thermo.f90:237-273`）读 `set%thermotemp(1:nthermo)`、
  `thermo_fscal`、`thermo_ithr`、`thermo_sthr`。
- 调用顺序：`vib.f90:116-117` 在**第一个单点之前**（`landscape_vib_hessian` 才建 engine）先 merge 再 check；
  失败 → `result%message="frequency analysis failed"` + return，`env%error` 由
  `main.F90:1089` 的 `env%checkpoint` 转成非零退出。
- **`$thermo scale=-1` 现在被拒绝**（追代码）：`set_thermo` 把 `-1` 写进 `set%thermo_fscal`
  （无正性检查，`set_module.f90`），merge 不改它（`freq_scal_was_set=.false.`），
  新 check 的 `set%thermo_fscal <= 0` 分支报 "the frequency scaling factor must be positive" ⇒
  在 `print_thermo` 乘进频率**之前**终止。四个反例（scale/temp/imagthr/sthr）在
  `landscape_cli_check.py:672-694`，断言 exit≠0 + 文档化消息（消息前缀与既有 CMake
  测试 `:942-953` 的 `MATCHES` 子串仍兼容）。
- 默认值不误伤：`setparam.f90:287-294` 的 `298.15 / 50.0 / -20.0 / 1.0` 全部通过。
- 可红：把 merge+check 换成修前 settings-only 版本 ⇒ 四个 `$thermo` 反例全部 exit 0 ⇒ `:691` 变红。

### P2-3 — 报告数字 98/100 ⇒ **部分修复**（残留 1 处，LOW-3）

- 已订正：04 §0 表（`95 → 100`）、§1.1 结论第 3 点（98/98 → 中间态注）、§1.3 表两行（加「中间态」注）、
  §1.3 `ctest -N` 片段、§5 标题下注与 §5.4 计入方式（`95 → 100`，06 再 +1 ⇒ 101），
  并把 `landscape-lts-fix`/`landscape-lirc-fix` 补进新增测试表（04:594-601）。
- 源码实测口径自洽：`add_test("xtb/landscape-…` 静态 **81** 行 − 1（foreach 模板）+ 6 = **86**，
  加 `tests` 列表 15 个 `landscape-*` = **101**，与 06 §2.3 的 `80 + 6 + 15 = 101` 一致。
- **残留**：04:872 仍写「整套 landscape 测试在 `-O3` 下 98/98 绿」而无注；04 §7.1.3 仍写
  「三条新 meson 测试」（实际已登记 6 条）⇒ 同类不一致未清完（LOW-3）。

### P2-4 — 陈旧行号 ⇒ **已修复，但源码注释里留了一处错行号**（LOW-2）

- 04 §2.2 四个调用点 → 子程序名（04:269-274）；04 §4.1/§4.3 → 「`anyopt` 分支里的 `if (nscan > 0)` 守卫」；
  PLAN §6.9 同；`main.F90:480-484` 的注释自述「行号因该守卫本身而失效，故不重复」。
  `grep "main.F90:914|irc.f90:673|relax_scan.f90:648|ts.f90:1189|ts.f90:1211|opt.f90:140"` → **0 命中** ✓。
- 核 05 未点、但属同类的两处：
  ① `src/landscape/types/constraints.f90:76` 引 `src/prog/main.F90:473`，实测 `call read_userdata` 在 **476**；
  ② 04:353 引同一行号（`src/prog/main.F90:473`）——`grep` 命中（06 §2.4 的可验证性命令没覆盖这个模式）。
  ⇒ 「不留裸行号」的目标**没有完全达到**（LOW-2）。

### P2-5 — `landscape-lts-fix` 的 prfo 契约 ⇒ **已修复（选项 b，理由成立）**

`test/unit/landscape_cli_check.py:820-919` 现在的契约：

```
converged            -> 必须 status == 0
未收敛               -> 必须 status != 0 且输出含 "transition state search did not converge"
两种情况            -> 冻结 H 位移 == 0；且两种情况都必须写了 xtbts.xyz
bprfo / dimer        -> 断言 status == 0 且 converged（真收敛夹具）
```

- **不是**「就该不收敛」：`if converged` 分支通过；将来 rho/trust 规则改进后 prfo 收敛也**不会**变红
  （核 05 的 P2-4 关切被消除）。失败语义由 `tasks/ts.f90:323-330` 提供
  （`transition state search did not converge: <reason>`），测试只钉这个通用串、**不再**钉
  `maximum number of steps reached`。
- 选项 (a) 的排除有实测记录（120/400/1200 步均不收敛）——属 §5 需复跑项。
- 可红：删掉 `ts.f90:323-330` 的 `env%error` ⇒ 未收敛却 exit 0 ⇒ `:901-903` 变红。
- 判定：**符合「二选一并说明理由」**，且同时满足两侧（收敛夹具只用于 bprfo/dimer，prfo 用失败语义）。

### P2-6 — `-O3` 检测面 + 过宽注释 ⇒ **已修复**

- CMake（`cmake/CMakeLists.txt:63-90`）：`xtb_opt_flags = CMAKE_Fortran_FLAGS` + 每个
  `CMAKE_BUILD_TYPE`/`CMAKE_CONFIGURATION_TYPES` 的 `CMAKE_Fortran_FLAGS_<CONFIG>`，
  再 `string(REPLACE ";" " ")` 后 `MATCHES "(^| )-O3( |$)"` ⇒ 分号列表与多配置生成器都覆盖；
  官方 `-O2 -DNDEBUG` 不误报（`CMAKE_Fortran_FLAGS_RELEASE` 内无 `-O3`）。
- 注释（`constraints.f90:34-49`、`driver.f90:280-287`）：BFGS 已限定「只在初值解耦时可证」，
  并给出 Lindh-D2 种子路径与 `bfgs` 的方向展开式；`check_fix` 补 `bfgs model`/`rfo model`
  两例（`landscape_cli_check.py:409-412`，共 8 例）。注入（删投影）时
  `bfgs model` 位移 x 0.28359 / z 0.19312 ⇒ 断言可红。

---

## 2. 专项攻击面逐问回答

1. **P1 是否真生效值**：是（§1 P1 的四段表 + `res%temp` 同源证据 + 全仓库无第二消费者）。
   测试对「写回 settings 值」**真能红**（`settings.f90:585` 默认 298.15 vs 断言 400）。
   表**基本完整**，唯一漏项是 `freq_scal` 的 GFN-FF 1.03 特例（LOW-4）。
2. **P2-1 是否 4/4 且可红**：是（§1 P2-1）。
3. **P2-2 校验位置**：在生效值之后；`$thermo scale=-1` **被拒绝**（不是乘进频率）。
4. **P2-5 断言语义**：失败语义（+ bprfo/dimer 的收敛断言），未固化缺陷；理由与代码位置见 §1 P2-5。
5. **P2-6**：分号分隔与多配置生成器**已补齐**（静态走读成立）；`constraints.f90` 注释**已按实际行为修正**
   （但见 LOW-2 的两处遗留）。
6. **P2-3/P2-4**：数字口径已自洽（101，静态点数一致），但 04 残留两处（LOW-3）；裸行号改为可持久引用
   已完成要点，残留 2 处（LOW-2）。
7. **回归风险**：**低**。数值路径零算式改动——`landscape_vib_set_thermo_settings`（提前调用＋守卫）
   写的是 `print_thermo/thermodyn` 专用参数，FD Hessian/单点/分析都不读它们；
   默认值 `298.15/50.0/-20.0/1.0` 与 lvset 默认逐值相同 ⇒ 无 `$thermo` 无 CLI 时逐位不变。
   `$fix` 投影与 `--lvib`↔`--hess` 一致性所在的代码本轮只改了注释。
   M7 四体系（0.0100/0.0600/0.0000/0.0000）在已提交的 M7 数据里可核到（`docs/_landscape-recon/m7-e2e-data/exp1-thermo/summary.json:393/175/285/49`）⇒ 目标值未被改。
8. **测试可证伪性逐个**：`check_thermo`（JSON 值与 4 个反例）红；`check_thermo_knobs` 红；
   `check_fix` 的 2 个新组合红；`check_saddlefix` 红；`fix-projection` 单测红（删投影）；
   CMake `-O3` 检测无 ctest ⇒ 以配置级注入为证（属构建守卫，可接受）。
9. **越界**：0（见摘要）。

---

## 3. 报告与实现的对照（06 自报 vs 我的走读）

| 06 的声明 | 我的判定 | 证据 |
|---|---|---|
| 新增 `landscape_vib_result%temperature/%freq_scal` | ✅ | `results.f90:90-105` |
| `write_json` 改读 `vib%` | ✅ | `vib.f90:300-301` |
| 校验搬进 `vib/thermo.f90`（合并后） | ✅ | `thermo.f90:237-273`；`vib.f90:116-117` |
| 新 ctest `landscape-vib-thermo-knobs` CMake+meson 双登记 | ✅ 但 CMake **缺 OMP 属性** | `CMakeLists.txt:3104/3136`；`meson.build:293`（LOW-1） |
| `check_thermo` 新增 JSON + 4 反例 | ✅ | `landscape_cli_check.py:630-694` |
| `check_fix` +2 组合（8 例） | ✅ | `:409-412` |
| `check_saddlefix` 改为失败契约 | ✅ | `:880-907` |
| CMake 遍历配置 + 归一化分号 | ✅ | `cmake/CMakeLists.txt:64-90` |
| 注释软化（constraints/driver/04 §2.1） | ✅（另见 LOW-2） | `constraints.f90:34-49`、`driver.f90:280-287`、04:263-265 |
| 04 计数订正、行号 → 子程序名 | ✅ 主要、残留 2 处 | §1 P2-3/P2-4（LOW-2/LOW-3） |
| 101/101、12/12、无重名、无 `LastTestsFailed.log` | **未验证**（我无法跑） | §5 |
| M7 四体系「逐项复现不变」 | **未验证**（目标值可核，复现需跑） | §5 |
| prfo status 1 / bprfo,dimer status 0、位移 0 | **未验证** | §5 |
| 每条注入「红→还原→绿」 | **未验证**（读代码后我认为**成立**） | §1 |

---

## 4. Findings

### LOW-1 — 新测试漏在 CMake 的 `OMP_NUM_THREADS=1` 名单外

- 位置：`test/unit/CMakeLists.txt:3104`（`xtb/landscape-vib-thermo-knobs`）vs
  `:2840-2870`（跑 engine 的 CLI 检查名单）与 `:3136-3158`（M7 + 本轮 5 条）。
- 证据：它的四个兄弟（`vib-cli`、`vib-etemp`、`vib-namespace`、`vib-thermo`）**都**在名单里；
  meson 侧同名测试用 `landscape_env`（`:142` = `xtbenv + ['OMP_NUM_THREADS=1']`，`:293`）。
- 影响：不在 `OMP_NUM_THREADS=1` 的 CI/本地调用下，该测试的 8 次 FD Hessian 会落入
  AGENTS §6.8 的 340× 反缩放（`xtb/landscape-vib-thermo` 单线程 0.40 s）；正确性上两 run
  同线程数仍逐位可比，故**不是**必然失败，但违反项目「所有 xtb/ctest 调用加 `OMP_NUM_THREADS=1`」的硬约束。
- 最小修法：把 `"xtb/landscape-vib-thermo-knobs"` 加进 `:3136` 的 `set_tests_properties` 列表（1 行）。

### LOW-2 — 两处错误的裸行号 + 一处错误的调用者清单（新文件）

- `src/landscape/types/constraints.f90:76`: 引 `src/prog/main.F90:473`；实测 `call read_userdata` 在 **476**
  （`:475` 是注释行）。04:353 引同一行号，也在 06 §2.4 的 grep 模式之外。
- `src/landscape/types/constraints.f90:120-126`: 注释写 `landscape_project_fixed_atoms` 是
  「不需要 mask 实参的方法的入口：鞍点搜索（prfo/dimer）、**band 搜索（`path/*`）**、**反应路径正确器（`irc/*`）**」。
  实测 `grep -rn landscape_project_fixed_atoms src/` 只有 `prfo.f90:599/795`、`dimer.f90:835`
  与定义/`public`；`tasks/ts.f90:207-227`、`tasks/irc.f90:172-190` 反而**拒绝** `$fix`。
  ⇒ 注释描述的调用者不存在，容易让读者以为 band/IRC 已有 `$fix` 语义。
- 最小修法：`:76` 去掉行号（「`read_userdata`，`--lopt` 之前」）；`:120-126` 删掉 `path/*`、`irc/*`
  （或改为「band/IRC 目前**拒绝** `$fix`，见 tasks/ts.f90 / tasks/irc.f90」）。

### LOW-3 — 04 的计数残留（P2-3 未清完）

- `04-o2-and-silent-defects-fix.md:872`: 「整套 landscape 测试在 `-O3` 下 **98/98** 绿」——无「中间态」注，
  与同报告 §5.4 的 100/101 口径不一致。
- 04 §7.1 第 3 条（`:869` 段）：「**三条**新 meson 测试」——现在 meson 已登记 6 条
  （`fix rfo`、`scan xcontrol`、`vib thermo`、`vib thermo knobs`、`lts fix`、`lirc fix`）。
- 最小修法：两处改成「中间态 98；最终 100（本轮 06 再 +1 ⇒ 101）」与「六条」。

### LOW-4 — JSON 生效值表的覆盖不足（报告级）

- 06 §1.5 把 `vib` 的 `temperature`/`freq_scal` 标为「已修」，但 `freq_scal` 有第三来源：
  `print_thermo` 在因子为内置 1.0 且 `mode_extrun==p_ext_gfnff` 时替换成 **1.03**
  （`src/main/property.F90` 的 `scale_factor` 分支），JSON 仍报 1.0。
  代码注释已如实说明（`results.f90:99-105`），但**表里没有这一行**，且本轮 GFN-FF 未做实验（06 §4.3.3）。
- 同一类里更重的一条（06 已登记为未修）：`counters.n_imag`/`status`/`status_name` 用
  `settings%imag_cutoff`（`vib/modes.f90:319`），热化学用 `set%thermo_ithr`；`$thermo imagthr=-10000`
  下 JSON 报 `n_imag:1`/`incomplete` 而 thermo 数到 0（有 `env%warning`，非静默；新测试**刻意不钉**该分歧，
  这是正确处置）。
- 最小修法（报告级，不改代码）：在 §1.5 表加该行，并注明「GFN-FF 特例 + imagthr 分歧」为同一「生效值」
  家族的两个未修成员。

### INFO-1 — 新 `env%checkpoint` 的措辞

`src/prog/main.F90:510` 紧跟在 `read_userdata` 之后，因此 `read_userdata`（`constrain_param`）抛出的
**任何其它** `env%error`（例如 "not enough arguments to constrain a distance"）现在都会由这条
checkpoint 终止，顶层消息打印成 "the run type does not execute the xcontrol `$scan` block"
（真正的错误仍在日志列表里逐条打印，退出码不变）。行为无回归，措辞会误导。
最小修法：把该 checkpoint 移进 `if (nscan > 0 .and. len_trim(lruntyp_flag) > 0)` 之内（1 行缩进）。

### INFO-2 — P2-1 的注入形式

06 §2.1 的注入是「删掉两行守卫」，它等价于「这两条守卫不存在」（作者原话），
但**不**等价于修前的无条件写（修前在 `$thermo sthr=2000` 下会把 50 写回去）。
两种变异都会让同一测试变红（删除⇒`sthr_cli==default`；回滚⇒同），故可证伪结论不受影响，
与项目 M4 的「先证语义等价」教训不冲突（原文只主张后者）。

---

## 5. 需运行验证清单（只读复核无法执行）

1. `OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-o2/build -R landscape` ⇒ **101/101**，
   并附 `Testing/Temporary/LastTestsFailed.log` **不存在**的证据（核 05 §4.1 曾在该目录看到
   `179:xtb/landscape-lirc-fix`）。
2. `grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d` ⇒ 空
   （我静态点数 81 条 `add_test`，无重名；foreach 展开 6 条）。
3. `ctest --test-dir /tmp/xtb-o2/build -N -R landscape | tail -1` ⇒ `Total Tests: 101`。
4. 回归子集 `-R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'` ⇒ 12/12。
5. M7 四体系重测（`exp1_thermo_check.py`）：dfreq 0.0100 / 0.0600 / 0.0000 / 0.0000；
   dZPE/dH/dG 与 04 §1.4 逐值；`param-equal True`。
6. W0 三条缺陷：`$fix` 8/8 位移 `0.00000e+00`；`--lvib` vs `--hess` dH/dG ~1e-8；`--lopt`+`$scan` exit 1。
7. `xtb/landscape-vib-thermo`：`$thermo temp=400` 的 JSON `temperature == 400.000`；
   `--lvib-temp 400` 与 `$thermo temp=400` 同 G；4 个 `$thermo` 反例 exit 1 + 消息。
8. `xtb/landscape-vib-thermo-knobs`：sthr dG 1.498e-05、imagthr dG 2.448e-03、
   默认 `n_imag 1`/`incomplete` ⇒ CLI `ok`（**这条同时验证「弯曲 HCN 猜测恰有 1 个虚模」的夹具前提**）。
9. `xtb/landscape-lts-fix`：prfo status 1/converged False/位移 0；bprfo、dimer status 0/converged True/位移 0。
10. CMake 配置级对照（4 组，`/tmp/w0cfg.sh` 类）：官方 `-O2` 无 warn；`-DCMAKE_Fortran_FLAGS="-O3;-funroll-loops"`
   修前 warn=0/修后 warn=1；多配置等价状态修前 0/修后 1；`-O2;-funroll-loops` warn=0。
11. **meson 侧 6 条新测试从未执行**（本机无 meson）——报告已声明；若 CI 有 meson 需跑一次。
12. 本轮全部注入的「红→还原→绿」逐条留证（我的走读判定它们都会红，但未实测）。

---

## 6. 无法验证 / 未复现的如实声明

1. 我**没有**运行任何命令（只读），故 06 的「★实测」数字是**走读佐证**而非重测。
2. 我**未**独立验证 M7 四体系复现、101/101、注入红绿、CMake 配置实验——均列 §5。
3. 我**未**验证 meson 路径（未安装 meson）。
4. 我**未**核对核 05 §4 与 W0 无关的历史项（`/tmp/xtb-o3` 的 `-O3` 探测 stdout 存档等）。
5. 我**未**核对 04 与 47 份历史文档的全量一致性（超出本轮范围）。

---

## 7. 一句话处置

**W0 可以提交**：P1（JSON 生效值）是真修且有能红的测试，6 条 P2 逐条落地、无越界、无数值路径改动；
提交时请一并落 §4 的 LOW-1（1 行注册）与 LOW-2/LOW-3（纯文档/注释），
并把 §5 的绿证（尤其 101/101 与 `LastTestsFailed.log` 缺失）附在提交说明里。
````