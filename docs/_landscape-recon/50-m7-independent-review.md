## Review 摘要（报告 50 正文见下）

**结论：有条件接受。CRITICAL 0 / HIGH 0 / MEDIUM 3 / LOW 9 / INFO 8。**
M7 的代码可宣称完成（3 条 MEDIUM 有明确最小修复，无一推翻验收数字）；**整套件可宣称完成**，但 PLAN 回填与 4 条文档口径必须先落地（见 §7）。

- `--ljson` **不是死旋钮**：解析（`main.F90:2179-2190` 设 5 个 settings）→ 字段（`settings.f90:378-384`）→ 6 个写出点（`sp:157 / opt:159 / scan:271 / vib:245 / ts:235,283 / irc:359`）逐条核对通过；注入 i/ii/iii/vii 证明 JSON 测试可红（`m7-e2e-data/injections/injections.json` 内 `compiled:true`、`red:true`、`restored:true`）。
- 端到端链**真衔接**：`check_chain` 消费 `xtbopt.xyz`（绝对路径 + `cwd=rundir`），非原始输入；G/H/ZPE 参数与 xtb 默认逐项相等（`setparam.f90:287-294` vs `settings.f90:575-596`），**未发现「调参使两者一致」的痕迹**。
- 容差**来源论证不成立**（L1）：CLI 链实测 0.0100 cm⁻¹ / 1.4e-8 Eh，却按「0.097 的 2 倍」「1.8e-8 的 5 倍」论证 0.20 / 1.0e-6（实为 20× / 71×）。容差本身安全（注入 iv 可红），是文档口径错。
- MEDIUM：ts 的 `n_cache_miss`/`n_eval` 在确认 Hessian **之前**采样（`tasks/ts.f90:255,908`），同一 stdout 里 `cache misses: 77` 与 `energy evaluations 95` 并存，JSON 与 CLI 断言同源于前者 → 回归比对语义错；`maple_importable: true` 是假绿（`landscape_e2e_check.py:526-528`）；**PLAN.md 本轮完全未改**（1511 仍写 `--ljson` 未实现，1805 仍描述旧退出语义，无 §12.16）。
- 2D 扫描 JSON（`tasks/scan.f90:333`）、scan 的 `n_valid/n_fail/n_unconverged`、`layers` 的 8/14 套件与 `ts→irc` 腿均**无测试覆盖**（L3/L4/L5/L6）。
- 未见 M0..M6 数值回归：`driver.f90` 修复只改失败路径轨迹；`--ljson` 不写数值输出；M7 仅新增 stdout 行（`etemp:`）。

---

# 报告 50 — M7 独立复核（read-only）

> 复核对象：`48-m7-e2e-closeout-report.md`、`49-m7-validation-experiments.md`、`m7-e2e-data/`、
> `--ljson` 实现与接线、`test/unit/test_landscape_e2e.f90`、`tasks/*` 的 M7 增量、
> `landscape_e2e_check.py`、`docs/xtb-landscape-M7-validation.md`、PLAN §9.8/§12。
> 复核者只读，未运行任何命令；所有结论来自源码、diff、测试与已落盘证据文件。
> 工作树基线：reviewer-launch HEAD（M7 未提交）；`docs/**` 除 48/49/m7-e2e-data 外**无改动**。

## 0. 独立核对结论（先给判定）

| 攻击面 | 判定 |
|---|---|
| 1 `--ljson` 真生效 / 任务×测试表完整性 / counters 同源 | 生效（无第 4 次死旋钮）；表**基本完整但 scan/vib 计数器无交叉断言**（L3）；ts 的 counters **不同源**（M1） |
| 2 确定性（键序/格式/数组序/namespace/逐位） | 通过；键序与字节比较均在 `landscape_e2e_check.py:290-300,367-374`；namespace 5/5 任务；OMP 敏感性已记录（I2） |
| 3 链的「真」衔接 / 静默重算 | 通过（消费 `xtbopt.xyz`；`--lvib` 按设计重算 FD Hessian；`--lvib-hessian file` 实测 19→1 次评估，见 49 §3.2） |
| 4 G/H/ZPE 独立性 / 参数 / 容差来源 / 假通过 | 独立复算真实（`m7-e2e-data/thermo_independent.py` 自述只读打印频率+几何）；参数 9 项逐项等于 xtb 默认；**容差来源论证算错**（L1）；无调参痕迹 |
| 5 「不可用 ⇒ 非零退出」统一 | scan 分支已改（`tasks/scan.f90:243-255`）；逐任务表（`M7-validation.md:196-210`）与代码一致；未破坏 M4/M6 语义（非鞍点仍 error，极大点未误判） |
| 6 MAPLE 诚实性 | **未运行**且写明（`maple_executed:false` + 依赖缺失理由）；但 `maple_importable:true` 是假绿（M2），且 §9.8 的「各任务」只落了 IRC 一个（L8） |
| 7 交叉验证脚本 L1/L2/L3 | 可证伪（各 mode 失败即 `fail()`/`SystemExit`）；但覆盖 6/14 套件、L3 只 1 条腿（L6） |
| 8 两条 PLAN 收尾项 | 行 1259 **已核实完成**（`results.f90:479` + `dimer.f90:961`，独立确认）；行 1805 scan 分支已改 |
| 9 测试可证伪性 | JSON 测试非「只测存在」；容差非空（注入 iv 可红）；**scan 2D JSON 零覆盖**（L5） |
| 10 回归 | 无 M0..M6 数值回归；仅新增 stdout 行（`etemp:`，`results.f90:510`） |
| 11 数值卫生 N1..N17 | `json.f90` 全合规（`wp`、无裸 real、无 module 可变量、无 BLAS、`env%error`、`!>` 带单位） |
| 12 文档承诺 vs 代码 | 7 条不一致（L1/L2/L4/L8/I1/I6） |
| 13 收尾完整性 | §9.8 两行交付物齐；**PLAN 未回填**（M3）；MAPLE「各任务」不全（L8） |

## 1. MEDIUM

### M1 — `ts` 的 JSON 计数器在确认 Hessian 之前采样，同一 stdout 出现两个「cache misses」
* `src/landscape/tasks/ts.f90:255`（鞍点路径）与 `:908`（band 路径）：`result%n_cache_miss = engine%n_eval` 在 `confirm_saddle`（`:273` / `:921`）**之前**执行；`:283` 的 `write_json` 用的是这个旧值。
* 证据（49 §2.3 + `m7-e2e-data/exp2-ljson/ts/stdout.txt`）：同一 stdout 同时打印
  `cache misses: 77`（result 表）与 `landscape engine: energy evaluations 95`（引擎报告），差 18 = 6N(HCN)。
* 为什么是问题：PLAN §5.5 把 `counters` 定义为**回归比对**的锚点，而 `--ljson` 的 CLI 断言（`landscape_e2e_check.py:305-310` 用 `cache misses:` 行）与 JSON 同源，因此**测试永远看不到这处不一致**；回归基线里 `n_cache_miss` 随「在哪里采样」而变。
* 最小修复：把两处 `result%n_cache_miss = engine%n_eval` 移到 `confirm_saddle` 之后（并同步 `result%n_eval` 语义），或把两个数分别命名（`n_cache_miss_search` / `n_cache_miss_total`），并在 `xtb/landscape-ljson-ts` 增一条对引擎报告行的断言。

### M2 — `maple` 模式报 `maple_importable: true`（假绿）
* `test/unit/landscape_e2e_check.py:526-528`：探针是 `python3 -c "import maple"`，成功只证明 `maple/__init__.py` 浅层可导入。
* 证据（49 §4.1 实测）：`from maple.function.dispatcher import Dispatcher` → `ModuleNotFoundError: No module named 'ase'`；`ase/torch/fairchem` 全缺。落盘 `m7-e2e-data/exp4-maple/maple.json` 里 `maple_importable: true` 与 `maple_import_error: ""` 并存。
* 为什么是问题：紧邻 `maple_executed:false` 的一个 `true` + 空错误串读作「本机可用 MAPLE」，正是本项目禁止的假通过信号。
* 最小修复：探针改为 `from maple.function.dispatcher import Dispatcher`（失败即记录 `ModuleNotFoundError` 文本），或把键改名为 `maple_toplevel_importable` 并在 `conclusion` 里写明缺失依赖。

### M3 — PLAN 本轮完全未更新，三处与已发布行为矛盾
* `docs/xtb-landscape-PLAN.md:1511` 仍写 `❌ --ljson 未实现（M7）`（`--ljson` 已实现并有 5 个 CLI 测试）。
* `:1805` INFO-3 仍把「退出码 0 + NaN TOTAL ENERGY」写成当前语义（M7 已改为 `env%error` → 非零退出）。
* `§9.8`（`:1350-1357`）没有结果/状态回填；§12 无 M7 小节（对比 M3 有 §12.11、M5 §12.12/12.13、M6 §12.14/12.15 的「实际接线」范式）。
* 证据：`watchdog_diff(path=docs)` 无 PLAN 修改；49 §9 只给「backfill suggestions」。
* 最小修复：新增 `§12.16 M7（--ljson / 端到端链 / 验证脚本）实际接线`，改 1511 为 ✅，把 1805 标注「M7 已统一（scan 分支）」，并在 §9.8 表后追加实测验收行（0.0100 cm⁻¹ 等）。

## 2. LOW

**L1 — 容差来源论证算错（CLI 侧）**。`test/unit/landscape_e2e_check.py:71-73`「twice the measured 0.097 cm⁻¹」、`:80`「five times the measured 2.0e-7」；`48` §2.2「0.20/1.00 (2× measurement)」；`docs/xtb-landscape-M7-validation.md:113`「2× the larger measurement」。实测（`m7-e2e-data/exp5-script/chain-abs.log`）CLI 链 `max dfreq 0.0100 (tol 0.20)`、`dZPE 1.429e-08`：0.20 = 20×0.0100，1.0e-6 = 71×1.4e-8。0.0971/2.0e-7 是**单元测试自己几何**（`test_landscape_e2e.f90:98,105`，注入日志里 `3651.33 vs 3651.23`）的实测值，被误搬到 CLI 侧。容差安全（注入 iv 可红），但「来源」这句不成立。最小修复：CLI 侧改写为「实测 0.0100 cm⁻¹ / 1.4e-8 Eh，容差取 20×/70× 的保守界」，并说明与单元测试 0.0971 的几何差异。

**L2 — `chain-failure` 的文档与实现相反**。`landscape_e2e_check.py:31-35`「the first step (`--lopt`) is forced to fail (`--lopt-max-steps 1`)」，实现（`:232-263`）是**第 1 步成功、第 2 步（`--lvib-hessian file` 指向缺失文件）失败**；`test/unit/CMakeLists.txt:2805` 同句「a failed first step must abort」。最小修复：改写这两处为「step 2 is misconfigured and must abort the runner」。

**L3 — scan/vib 的计数器无交叉断言**（49 F4，我已从注入证据独立确认：`injections.json` 中 `json-counter` 注入下 `xtb/landscape-ljson-scan` 为 `red:false`）。`landscape_e2e_check.py:302-311` 的 `expected` 只含 `opt/ts/irc`；scan 仅断 `n_points`/`energy`，vib 仅断 `zpe`/`n_imag`。最小修复：给 scan 加 `energy evaluations` 断言、给 vib 加 `energy evaluations`/`# frequencies` 断言。

**L4 — 「counters 就是 stdout 打印的数」不成立**。`src/landscape/types/json.f90:40-43` 与 `src/landscape/tasks/scan.f90:284-286` 都这样断言，但 `n_valid`/`n_fail`/`n_unconverged`（1D）与 `n1`/`n2`（2D）**没有任何打印点**（`scan.f90:230-266` 只打印 message + `lowest energy`）。最小修复：把该句限定为「可由 CLI 交叉验证的计数器」，或在扫描摘要里打印这四个数。

**L5 — 2D 扫描 JSON 零覆盖**。`src/landscape/tasks/scan.f90:333` `write_json_grid`（含 visit-order 重排循环 `:362-368`）在交付测试里不可达：`TASK_ARGS["scan"]`（`landscape_e2e_check.py:88-90`）是 1D，`ljson-methods` 只跑 ts/irc；全仓 `grep lscan-coord2` 在 `test/unit/CMakeLists.txt` 无命中。这是 M3「零覆盖分支」模式的复现。最小修复：`ljson` 模式加 `scan2d` 变体（`--lscan-coord2/--lscan-atoms2/--lscan-step2/--lscan-nstep2`），断言 `n1*n2 == n_points` 且 `energy` 长度等于 `xtbscan_2d.xyz` 帧数。

**L6 — `layers` 的覆盖与文档不符**（49 F7）。`landscape_e2e_check.py:458-490` 只跑 4 个 L1 + 2 个 L2 套件（共 14 个 landscape 单元套件中的 6 个）+ chain 一条 L3 腿；`docs/xtb-landscape-M7-validation.md:71` 的 L3 行却把 `xtb-tester landscape-e2e` 也列进去（`layers` 从不运行它），且 `ts → irc` 腿不在报告内。最小修复：把两个套件列表补全（都已是 ctest target）并加 `ts→irc` 腿，或把 §3 的行文改成「layers 覆盖 6/14 + chain」。

**L7 — 测试卫生：断言「文件不存在」前不清场**。`xtb/landscape-e2e-chain-failure`（`landscape_e2e_check.py:257-261`）在**复用**的 rundir 里断言 `hessian/vibspectrum/g98.out` 不存在；49 F1 实测注入运行后残留即假红（exit 8，`rm -rf` 后恢复）。同类：`test/unit/test_landscape_e2e.f90:511` `test_sp_ljson` 只在**结尾**删除 `landscape_sp.json`，一次中途 abort 就会让「是否写出」的断言变成空测试。最小修复：两个测试在开头删除目标文件/清空 rundir。

**L8 — §9.8「MAPLE 各任务」只落了 IRC**。`docs/xtb-landscape-PLAN.md:1357` 要求对 MAPLE **各任务**做拓扑/几何一致性记录；`landscape_e2e_check.py:492-596` 只读 `examples/irc/hpc/inp1_full.xyz` 一个 fixture。MAPLE checkout 里 `examples/{sp,opt,scan,ts,freq,irc}`（含 `ts/{autoneb,dimer,neb,prfo,string}`、`opt/{cg,lbfgs,rfo,sd,...}`）都有落盘 fixture，逐任务记录**无需运行 MAPLE**。另：`MAPLE_DIR` 默认值是开发机绝对路径（`:516-517`），在别处会静默变成「checkout not found」+ 无 fixture 字段，而 `conclusion`（`:571-577`）仍断言该 fixture 的拓扑。最小修复：至少为 `sp/opt/ts/freq` 各读一个已提交 fixture 记录端点/极值计数，并把 conclusion 改为条件生成。

**L9 — `--ljson` 在无 landscape run type 时静默无效**。`src/prog/main.F90:2179-2190` 只置 flag；`xtb x.xyz --ljson`（默认 sp/单点 runtyp）不写任何文件、退出 0，无提示。最小修复：解析时若 `set%runtyp` 不是 5 个 `p_run_l*` 之一则 `env%warning`，或在 xhelp 里写明「需与 `--l*` 同用」。

## 3. INFO

* **I1** `48` §1.3 称单元测试 `ljson-determinism`「additionally pins the key order」——键序断言只存在于 `landscape_e2e_check.py:290-296`；`test_landscape_e2e.f90:462-476` 只断字节相等与两个计数器。
* **I2**（49 F8）JSON 在**不同线程数**下非逐位相同（≤2.4e-10 abs，计数器稳定）；任何 JSON 基线必须钉 `OMP_NUM_THREADS`（ctest 已钉）。
* **I3**（49 F9）`n_imag = -1` 哨兵（opt/scan）与 `n_eval` 的每任务含义差异需写入 §12.11 同款 INFO 表。
* **I4**（49 F10）`hessian` 文件路径会**二次投影**（Eckart 幂等到 1e-10），所以 `--lvib --lvib-hessian file` 复现的是**文件自身的投影**（读 `--hess` 文件即得 `--hess` 数）。用户指南 §7 未提这一句。
* **I5**（49 F11）单元 `ljson-determinism` 结构上无法发现 builder 级非确定性（两次写同一对象）；只有 CLI 检查能（注入 2 vs 注入 3 的互补性成立）。
* **I6** M7 的 scan 改动除退出码外还**移除了尾部 `TOTAL ENERGY` 块**：`env%error` → `main.F90:971` `env%checkpoint` → 进程终止，故 NaN 只出现在扫描表（`lowest energy: +NaN`）。`CMakeLists.txt:811-816` 的注释「non-zero exit next to the NaN total energy」已不精确（测试断言本身正确）。
* **I7** `sp` 无 run type，`landscape_sp.json` 只能经 API 得到（`48` §8.3 已声明）；「全部任务可选输出」在 CLI 层天然不完整。
* **I8** 无注入钉住**频率**容差（只钉了能量容差）；0.15 cm⁻¹ 级别的频率回归会通过 0.20 容差（最小值处已记录的最大投影差为 0.0757 cm⁻¹）。

## 4. 已核实为「做对了」（不产生 finding 的核对项）

* 行 1259 dimer 列名：`types/results.f90:478-481`（`bound_label` 按 `bound_kind` 切换）+ `saddle/dimer.f90:959-961` 设置 `p_landscape_bound_step_max` — **已完成**，`48` §6 的说法成立。
* `--lts-step0` 上限语义：`xhelp.f90:436-438` + `settings.f90:725-731`（含实测 0.1032 bohr）— 已完成。
* `driver.f90:119-131` 提前分配轨迹：与旧路径首帧同内容（`x` 在分配点之前不被修改）；`finish()`（`:499-515`）现为 (ndim,1) 安全拷贝；「非有限起点」路径仍不调 `finish()`（无影响）。
* 热化学参数**无调参**：`setparam.f90:287-294`（298.15 / 50.0 / −20.0 / 1.0 / nthermo=1）与 `settings.f90:575-596` 完全一致；49 §1.4 的 9 项参数逐项相等且被 4 个 knob 实验证明「真的进到模型」。
* 注入方法论合规：`injections.json` 记录 `compiled:true`（含一次语法错误注入被识别为「未编译」的教训）、`sha_before==sha_after`、`restored:true`；注入 2 与 3 互补。
* `add_test` 唯一性：`test/unit/CMakeLists.txt` 共 90 个 landscape 名（含新 10 个），逐名比对**无重复**（M2 教训已防住）。

## 5. 需运行验证（复核者无法执行）

```bash
export OMP_NUM_THREADS=1
cmake --build /tmp/xtb-land/build -j
ctest --test-dir /tmp/xtb-land/build -R landscape            # 期望 90/90
ctest --test-dir /tmp/xtb-land/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'  # 12/12
grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d   # 期望空
```
1. **F1 类残留**：`rm -rf /tmp/xtb-land/build/test/unit/landscape-e2e-chain-failure && ctest ... -R chain-failure`，连跑两次；再手工 `touch` 一个 `hessian` 后重跑，确认 L7。
2. **L1**：`python3 test/unit/landscape_e2e_check.py chain /tmp/xtb-land/build/xtb <h2o.xyz> /tmp/e2e-abs`，确认打印 `max dfreq 0.0100`（而非 0.097）。
3. **L5（2D JSON）**：`xtb h2o.xyz --gfn 2 --lscan --lscan-coord distance --lscan-atoms 1,2 --lscan-step 3 --lscan-nstep 1 --lscan-coord2 angle --lscan-atoms2 2,1,3 --lscan-step2 3 --lscan-nstep2 1 --ljson --norestart` → 检查 `landscape_scan.json` 可解析、`n_points == n1*n2`、`history.energy` 长度 == `xtbscan_2d.xyz` 帧数。
4. **M1**：`xtb hcn.xyz --gfn 2 --lts --lts-method prfo --ljson` → 比较 result 表 `cache misses:` 与 `landscape engine: energy evaluations`（期望两者不同，差值 = 6N）。
5. **M2**：`python3 -c "from maple.function.dispatcher import Dispatcher"`（期望 ModuleNotFoundError: ase）。
6. **L9**：`xtb h2o.xyz --gfn 2 --ljson`（无 `--l*`）→ 期望无 `landscape_*.json`、退出 0。
7. **I6**：`xtb ... --lscan --lscan-max-steps 0 --ljson` → 确认 JSON 写出（status −1）但 stdout **无** `TOTAL ENERGY` 行。

## 6. 若「整套件可宣称完成」，未完成 / 已知限制清单（供最终交付文档）

1. **PLAN §6.5 GS Lagrange 修复**：本轮明确不做（`PLAN:960`），球面约束偏差 3.4e-4/1.3e-3 Eh、GS 每点 16.9/20.3 E/g。
2. **meson/ninja 未安装**：`src/landscape/meson.build`、`test/unit/meson.build` 的注册（含 M7 的 10 个测试）**未验证**。
3. **`sp` 无 run type**：`--ljson` 的 sp 文档仅 API 可达（`test_landscape_e2e.f90:494`）。
4. **MAPLE 未运行**：ML 势 + 缺 ase/torch/fairchem；只做拓扑记录，且只覆盖 IRC fixture（L8）。
5. **2D 扫描 JSON 无测试**（L5）；scan 的 `n_valid/n_fail/n_unconverged` 无法与 stdout 对拍（L4）。
6. **ts 计数器语义**：`n_cache_miss` 是搜索计数而非整轮计数（M1）。
7. **JSON 非跨线程逐位稳定**：基线须钉 `OMP_NUM_THREADS`（I2）。
8. **`--ljson` 不写早期错误返回**（未知 Hessian source、非法热化学参数等，`48` §8.2 已声明为范围决定）。
9. **IR/Raman 强度为 0**（Hessian provider 无偶极导数）；`hessian` 文件路径二次投影（I4）。
10. **IRC 的 `s` 列跨方法不可比**（gs/hpc/eulerpc 弦长 vs lqa 积分弧长）。
11. **D2 排除清单**：DMF、batch-GPU blbfgs/BPRFO、ML 势 calculator、parmfit、MD 系综、PBC、全局优化。
12. **`--lvib` vs `--hess` 永不逐位相等**（Eckart vs trproj，最小 0.0036 / 最大 0.0757 cm⁻¹，离极小可达 5.21 cm⁻¹）。

## 7. 合并判定

* **M7 可宣称完成**：先处置 M1（ts 计数器采样点）、M2（`maple_importable` 假绿）、M3（PLAN §12.16 回填 + 1511/1805 改口），并顺手修 L1/L2 的文档口径；L3–L9 可作为已登记债务（建议至少补 L3 的 scan 断言与 L7 的清场，成本极低）。
* **整套件可宣称完成**：`--ljson` 生效且有可证伪测试、L3 链与 `ts→irc` 端点在真实 GFN2 上通过、G/H/ZPE 与 `--hess` 在**有来源的容差**内一致、MAPLE 诚实记录「未运行」、两条 PLAN 收尾项已核实/已改。**无 CRITICAL/HIGH，无验收数字被推翻。** 残留风险即 §6 清单。