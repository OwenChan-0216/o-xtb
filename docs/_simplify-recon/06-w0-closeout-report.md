# 06 — W0 收尾报告：核 05 的 1×P1 + 6×P2

> **性质**：修复者（worker）自报。**本文只增量**，不重写 04（04 只做了被点名的
> 数字/引用订正，见 §2.3/§2.4）。
> **本轮基线**：W0 未提交工作树（HEAD = `24c069f`）+ 核 05
> `docs/_simplify-recon/05-w0-independent-review.md`。
> **构建**：`/tmp/xtb-o2/build`，`CMAKE_BUILD_TYPE=Release` +
> `CMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"`（核 05 §1.1 已核对该缓存）。
> 所有 xtb/ctest 调用均带 `OMP_NUM_THREADS=1`。**未提交 git**（`git diff --cached` 为空）。

---

## 0. 结论

| 项 | 结果 |
|---|---|
| 核 05 的 **P1（MEDIUM-1）** | ✅ **已修 + 测试 + 注入**（§1） |
| 任务书 P2-1（`sthr`/`imagthr` 两条守卫无测试） | ✅ 新 ctest `xtb/landscape-vib-thermo-knobs` + 注入（§2.1） |
| 任务书 P2-2（校验只看 `settings%`） | ✅ 校验移到**合并后**的生效状态 + 4 条 `$thermo` 反例 + 注入（§2.2） |
| 任务书 P2-3（报告 98/100 自相矛盾） | ✅ 04 的 4 处订正，口径写清（§2.3） |
| 任务书 P2-4（陈旧行号） | ✅ 04/PLAN/main.F90 改为**子程序名引用**，不留裸行号（§2.4） |
| 任务书 P2-5（`landscape-lts-fix` 把不收敛钉成契约） | ✅ 改为「结果必须被明确报告」契约 + 注入（§2.5） |
| 任务书 P2-6（`-O3` 检测面 + `constraints.f90` 过宽声明） | ✅ CMake 侧两类漏检已修（配置级注入证据）+ 注释软化（§2.6） |
| 回归 | `ctest -R landscape` **101/101**、回归子集 **12/12**、无重名、`LastTestsFailed.log` 不存在（§3） |
| M7 四体系验收 | **逐项复现不变**：dfreq 0.0100 / 0.0600 / 0.0000 / 0.0000 cm⁻¹（§3.2） |
| W0 三条缺陷行为 | **不变**：`$fix` 8/8 位移 0、`--lvib` vs `--hess` dG 1.4e-8、`--lopt`+`$scan` exit 1（§3.3） |
| 新发现（**未修，如实列出**） | `vib%n_imag`/JSON `n_imag`/status 用 `settings%imag_cutoff`，而热化学用合并后的 `set%thermo_ithr`；`$thermo imagthr` 下二者**可合法分歧**（§4.1） |

---

## 1. P1 — `--lvib --ljson` 必须记录**生效**值

### 1.1 缺陷与机制（复核已定位，本轮独立复现）

`write_json`（`src/landscape/tasks/vib.f90`）写的是 `settings%temperature(1)` /
`settings%freq_scal`；而 W0 把 `settings%` 改成**只在 `*_was_set` 时**覆盖 `set%`
（`src/landscape/vib/thermo.f90` 的 `landscape_vib_set_thermo_settings`），
于是没有 CLI flag 时生效值来自 xcontrol `$thermo`。两条路于是可以不同。

★实测复现（本轮，修前 / 注入态，H2O 紧极小）：

```
$ xtb xtbopt.xyz --gfn 2 --lvib --ljson --norestart -I t400.inp     # $thermo temp=400.0
    "gibbs": -5.07555945844026013E+000,        <- 400 K 的值
    "temperature": 2.98149999999999977E+002,   <- 298.15 K，与 gibbs 自相矛盾
```

### 1.2 修复（3 个代码点，均为「记录生效值」的同一原则）

| 文件 / 位置 | 改动 |
|---|---|
| `src/landscape/types/results.f90`（`landscape_vib_result`） | 新增 `temperature`、`freq_scal` 两个**生效值**字段（带单位与来源注释） |
| `src/landscape/vib/thermo.f90`（`landscape_vib_thermo_output`） | 合并后写 `vib%freq_scal = set%thermo_fscal`；`main_freq` 之后写 `vib%temperature = res%temp`——**从容器读回**（`main_freq` 里就是 `set%thermotemp(set%nthermo)`，与 `htot = et(set%nthermo)` 同源，`src/main/property.F90`） |
| `src/landscape/tasks/vib.f90`（`write_json`） | `temperature`/`freq_scal` 改读 `vib%`，不再读 `settings%` |

**未做**（不越界）：不新增 JSON 键（10 键 schema 不变）；不改 `gibbs`/`enthalpy` 的
计算路径；`freq_scal` 的语义在结果字段注释里写清——它是**合并后参数状态**的因子，
`print_thermo` 对 GFN-FF 在因子为内置 1.0 时会替换成 1.03（`--hess` 同样如此），
该替换不复制进 JSON（复制就是把上游规则再写一遍）。

### 1.3 前后 JSON 对照（★实测，同一几何、同一命令）

| 输入 | 字段 | 修前（注入态） | 修后 |
|---|---|---|---|
| `$thermo temp=400.0` | `temperature` | `2.98149999999999977E+002` | **`4.00000000000000000E+002`** |
| `$thermo temp=400.0` | `gibbs` | `-5.07555945844026013E+000` | `-5.07555945844026013E+000`（不变） |
| `$thermo scale=0.9` | `freq_scal` | `1.00000000000000000E+000` | **`9.00000000000000022E-001`** |
| `$thermo scale=0.9` | `gibbs` | `-5.07005830726468343E+000` | `-5.07005830726468343E+000`（不变） |

「修前」一列由 §1.4 的注入构建实测（把赋值逐字改回 `settings%…`，语义等价于修前源码）。

### 1.4 测试与注入

**测试**：`test/unit/landscape_cli_check.py::check_thermo`（mode `thermo`，
ctest `xtb/landscape-vib-thermo`）新增两段，均断言**两条独立性质**：
① `temperature` 必须等于 400（即 block 要求的温度）；② 它与 `gibbs` 自洽——
`$thermo temp=400` 的 `--ljson` 文档与 `--lvib-temp 400` 的文档必须报告**同一个**
`temperature`，而两个 run 的 `gibbs` 已经在前一段被断言相等（同一温度才可能同 G）。
`freq_scal` 同理（0.9 与 CLI 0.9 一致）。

```
thermo json: `$thermo temp=400` and `--lvib-temp 400` both report temperature 400.000 K for gibbs -5.075559458440 Eh
thermo json: `$thermo scale=0.9` == `--lvib-freq-scal 0.9` -> freq_scal 0.900
```

**注入（可证伪）**：`write_json` 的两行赋值**逐字回滚**为修前的
`settings%temperature(1)` / `settings%freq_scal`（无其它改动）。

| 测试 | 注入后 | 还原后 |
|---|---|---|
| `xtb/landscape-vib-thermo` | **RED**：`FAIL: landscape_vib.json reports temperature 298.150000 K for a run whose gibbs is the 400 K value` | GREEN（0.40 s） |

### 1.5 其它任务的 JSON 是否有同类问题（任务书要求 4）

判据：JSON 值是否可能来自 `settings%`，而生效值还有**第二个来源**（xcontrol/读回）。

| 任务 | JSON 里取自 `settings%` 的键 | 该设置的来源 | 判定 |
|---|---|---|---|
| `sp` | 无（只有 `energy`/`kcal_per_mol`/counters） | — | 无风险 |
| `opt` | 无（`n_fallback`/`energy`/`kcal_per_mol`） | — | 无风险 |
| `scan` | `bidirectional` | **只有** `--lscan-bidirectional`（`main.F90` 是唯一写点；`lsset%bidirectional` 无 xcontrol 键） | settings == 生效，无风险 |
| `ts` | `method`、`verify_ts` | **只有** `--lts-method` / `--lts-verify-ts`（`grep verify_ts src/` → 唯一写点是 CLI 解析） | settings == 生效，无风险 |
| `irc` | `method` | **只有** `--lirc-method` | settings == 生效，无风险 |
| `vib` | ~~`temperature`/`freq_scal`~~ | `--lvib-temp`/`--lvib-freq-scal` **或** `$thermo temp/scale`（W0 之后） | **本轮 P1，已修** |
| `vib` | `project_tr` | 只有 `--lvib-no-project` | settings == 生效，无风险 |
| 所有任务 | `etemp` | **读回**计算器（`result%etemp`，M3/M4 的既有原则） | 已是生效值 |
| `vib` | `counters.n_imag`、`status`、`status_name` | 由 `landscape_vib_analysis` 用 `settings%imag_cutoff` 计算，而热化学用合并后的 `set%thermo_ithr` | **同类但不同键**：`$thermo imagthr` 下二者可分歧 ⇒ §4.1 记录为未修发现（修它会改分析层语义，属父会话决策） |

---

## 2. P2 逐条

### 2.1 P2-1 — `sthr` / `imagthr` 两条 `*_was_set` 守卫的生效性测试

复核事实：`--lvib-rotor-cutoff` 在整个 `test/unit` 零引用；`--lvib-imag-cutoff`
只有「正数报错」分支。⇒ 删掉 `landscape_vib_set_thermo_settings` 里那两行守卫，
全套 100 个测试**全绿**（复核 §4.2 的第 6 条，本轮用注入复验，见下）。

**新测试** `xtb/landscape-vib-thermo-knobs`（mode `thermoknobs`；同时登记
`test/unit/CMakeLists.txt` 与 `test/unit/meson.build`）。每个旋钮断言两次：
**生效**（结果改变）与**合并**（xcontrol 键与 CLI flag 同值）。

| 旋钮 | 生效断言 | 合并断言 | ★实测 |
|---|---|---|---|
| `sthr` / `--lvib-rotor-cutoff` | G 与默认不同 | `--lvib-rotor-cutoff 2000` 与 `$thermo sthr=2000` 的 G 相等（≤1e-12） | dG **1.498e-05** Eh（H2O 紧极小） |
| `imagthr` / `--lvib-imag-cutoff` | `n_imag` 1 → 0、status `incomplete` → `ok`、G 改变 | 两路的 G 相等 + 打印的 `imag. cutoff` = -10000 + 出现 `inverting freq` | dG **2.448e-03** Eh（bent HCN 鞍点，默认 `n_imag 1`/`incomplete`） |

```
thermo knobs: rotor cutoff  --lvib-rotor-cutoff 2000 == $thermo sthr=2000 = -5.068030235327 Eh (default -5.068045210878, dG 1.498e-05)
thermo knobs: imag cutoff   --lvib-imag-cutoff -10000 == $thermo imagthr=-10000 -> analytic n_imag 0, dG 2.448e-03 Eh (default n_imag 1, status incomplete)
```

**注入**：删掉 `landscape_vib_set_thermo_settings` 里 `rotor_cutoff_was_set` /
`imag_cutoff_was_set` 两行（纯删除，语义等价于「这两条守卫不存在」）。

| 测试 | 注入后 | 还原后 |
|---|---|---|
| `xtb/landscape-vib-thermo-knobs` | **RED**：`FAIL: --lvib-rotor-cutoff 2000 did not change the free energy` | GREEN（0.15 s） |

> 该测试**不**断言 `$thermo imagthr` 与 CLI 的 `n_imag` 相等：分析层的计数用
> `settings%imag_cutoff`，两路在此键上**合法分歧**（§4.1）。钉住分歧就等于把
> 一个待决策行为编码成期望值（M2 的教训）。

### 2.2 P2-2 — 校验必须针对**生效值**

**修法**：删掉 `tasks/vib.f90` 里私有的 `check_thermo_settings`（只读 `settings%`），
新增 `landscape_vib_check_thermo_settings`（`vib/thermo.f90`），读**合并后**的
`set%`（`thermotemp(1:nthermo)`、`thermo_fscal`、`thermo_ithr`、`thermo_sthr`）。
任务在**第一个单点之前**先 `landscape_vib_set_thermo_settings` 再 check，
因此 `$thermo` 的值与 `--lvib-*` 的值走**同一段**校验代码。

**测试**（`check_thermo` 内新增 4 条反例，均断言 exit≠0 + 文档化消息）：

```
thermo: `$thermo scale=-1.0  ` rejected with status 1
thermo: `$thermo temp=-5.0   ` rejected with status 1
thermo: `$thermo imagthr=20.0` rejected with status 1
thermo: `$thermo sthr=-1.0   ` rejected with status 1
```

修前实测（同一 input）：`$thermo scale=-1` **exit 0**，打印
`scaling factor -1.0000000`，G 由 -5.068045 变 **-5.088169**（负因子乘进每个频率）。

**注入**：把任务里的 merge+check 换成**修前源码逐字**的
`check_thermo_settings_legacy(env, settings, ok)`（只校验 settings 对象）。

| 测试 | 注入后 | 还原后 |
|---|---|---|
| `xtb/landscape-vib-thermo` | **RED**：`FAIL: the $thermo scale=-1.0 block was accepted` | GREEN（0.40 s） |

### 2.3 P2-3 — 报告 04 的测试计数 98/100

源码实测 **101**（本轮新增 1 条之后；本轮之前为 100）：
`add_test("xtb/landscape-…` **80** 条 + `foreach(task IN ITEMS opt scan scan2d vib ts irc)` 展开 **6** 条
+ `tests` 列表里 **15** 个 `landscape-*` test-drive suite = **101**（`ctest -N -R landscape`
的 101 个名字去重后也是 101）。04 里的 98 是**中间态**（当时只有 3 个新条目登记），
与 §5.4 的 100 并存但不加标注 ⇒ 本轮订正 4 处（§1.1 正文、§1.3 表两行、
§1.3 的 `ctest -N` 片段、§5 的 `ctest` 片段与「新增的 3 个测试（95 → 98）」→
**「新增的 5 个测试（95 → 100）」**，并把 `landscape-lts-fix`/`landscape-lirc-fix`
两行补进表里）。04 的行号引用与「98」都加了指向本报告的注。

### 2.4 P2-4 — 陈旧行号 → 可持久引用

| 位置 | 修前 | 修后 |
|---|---|---|
| 04 §2.2 四个调用点 | `opt.f90:140`、`relax_scan.f90:648`、`ts.f90:1189`、`irc.f90:673` | 子程序名：`landscape_optimize`、`landscape_scan_relax_point`、`relax_one_endpoint`、`relax_endpoint`（+ 关键实参） |
| 04 §4.1 / §4.3 表 | `src/prog/main.F90:914-916` | `main.F90` 的 `anyopt` 分支、`if (nscan > 0)` 守卫（**不写行号**） |
| PLAN §6.9 表 | `relax_scan.f90:648`、`ts.f90:1211`、`irc.f90:673` | 同上子程序名（`ts.f90:1211` 同样已过期） |
| `src/prog/main.F90` 注释 | `src/prog/main.F90:914-916` | 「下面的 `if (anyopt)` 分支里的 `if (nscan > 0)` 守卫」，并注明行号因该守卫本身而失效 |

**可验证性**：`grep -n "main.F90:914\|irc.f90:673\|relax_scan.f90:648\|ts.f90:1189\|ts.f90:1211\|opt.f90:140" docs/_simplify-recon/04-*.md docs/xtb-landscape-PLAN.md src/prog/main.F90` → **0 命中**；`grep -n 914` 的**唯一**命中是 04 里解释「初版行号已过期」的那一句注释本身。

### 2.5 P2-5 — `landscape-lts-fix` 的 prfo 契约

复核关切：把「PRFO 不收敛」钉成期望行为，将来改进 trust radius 会因**好事**变红。

**先试选项 (a)**（找能收敛的 fixture）：在 `$fix atoms: 1` 的 bent HCN 上把步数
预算从 120 提到 400、1200，**仍然**是 `maximum number of steps reached`（exit 1），
说明该夹具的约束 P-RFO 在本轮不收敛，且与投影无关（修前同样不收敛）。
⇒ 采用**选项 (b)**：断言改成「结果必须被明确报告」——

```
converged  -> 必须 exit 0
未收敛     -> 必须 exit≠0 且输出含 "transition state search did not converge"（landscape_ts 的通用报错）
两种情况下：冻结原子位移必须 = 0
```

不再断言具体原因串（`maximum number of steps reached`）。理由写进
`check_saddlefix` 的 docstring 与代码注释。

**注入**：删掉 `tasks/ts.f90` 里 `if (.not. result%converged) … env%error(… "did not converge" …)`
这一段（= 不收敛时静默 exit 0）。

| 测试 | 注入后 | 还原后 |
|---|---|---|
| `xtb/landscape-lts-fix` | **RED**：`FAIL: the constrained prfo run exited 0 although it did not converge` | GREEN（1.3 s） |

★还原后实测：

```
saddle fix: prfo  status 1 converged False  frozen atom displacement 0.00000e+00 angstrom
saddle fix: bprfo status 0 converged True   frozen atom displacement 0.00000e+00 angstrom
saddle fix: dimer status 0 converged True   frozen atom displacement 0.00000e+00 angstrom
```

### 2.6 P2-6 — `-O3` 检测面 + 过宽注释

**(a) CMake 检测**（`cmake/CMakeLists.txt`）：现在遍历
`CMAKE_BUILD_TYPE` **与** `CMAKE_CONFIGURATION_TYPES` 的每个配置，
并在匹配前 `string(REPLACE ";" " ")` 归一化列表分隔符。

**(b) 注释**：`src/landscape/types/constraints.f90` 模块头把
「L-BFGS / BFGS」拆开：L-BFGS 仍可证；**BFGS 只在初值解耦时可证**——
`--lopt-hessian model` 用 Lindh-D2 曲率矩阵做种子
（`optimize/driver.f90` → `landscape_bfgs%set_hessian`），方向在该矩阵本征矢上展开
（`d = -sum_i (V_i.g)/max(w_i, hlow) V_i`，`optimize/bfgs.f90`）。同一句话在
`optimize/driver.f90` 的投影注释里也软化了。04 §2.1 的「BFGS 可证空操作」同步加注。

**测试**：`check_fix` 新增 `bfgs model` / `rfo model` 两个组合（`--lopt-hessian model`），
共 8 例，全部断言冻结 O 位移 = 0：

```
fix projection: sd / cg / lbfgs / bfgs / diis / rfo / bfgs model / rfo model
                frozen atom displacement 0.00000e+00 angstrom   (8/8)
```

**注入**（`optimize/driver.f90` 删除 `if (constrained) call landscape_project_frozen(d, fix_mask)`，
即回到修前逻辑）：

| 对象 | 注入后位移（Å） | 还原后 |
|---|---|---|
| `rfo` | **1.09177e-02**（复核 04 的旧值，逐位复现） | 0.00000e+00 |
| `bfgs model`（P2-3 的新断言） | **x 0.28359 / z 0.19312** | 0.00000e+00 |
| `rfo model`（P2-3 的新断言） | **x 0.26674 / z 0.18334** | 0.00000e+00 |

⇒ 「BFGS 投影是空操作」在 model 种子下**被测量否证**；新断言可证伪。

**CMake 检测的注入/对照**（配置级，`/tmp/w0cfg.sh`，每次全新 configure，
`FETCHCONTENT_SOURCE_DIR_*` 指向本地依赖源，无网络）：

| 配置 | 修前逻辑 | 修后逻辑 |
|---|---|---|
| 活动 build type = Release 且 `CMAKE_Fortran_FLAGS_RELEASE="-O3 -DNDEBUG"`（对照） | warn=1 | warn=1 |
| `-DCMAKE_Fortran_FLAGS="-O3;-funroll-loops"`（分号列表） | **warn=0** | **warn=1** |
| `-DCMAKE_BUILD_TYPE=` + `-DCMAKE_CONFIGURATION_TYPES=Debug;Release` + `CMAKE_Fortran_FLAGS_RELEASE="-O3"`（多配置生成器的等价状态） | **warn=0** | **warn=1** |
| 对照 `-DCMAKE_Fortran_FLAGS="-O2;-funroll-loops"` | — | warn=0 |

（每条都是 `Generating done` + `CMake Error` 计数 0；注入态 = 把该 if 块逐字还原为
修前的 `if(CMAKE_BUILD_TYPE) … endif()` 版本。）

---

## 3. 测试与回归（★实测，全部 `OMP_NUM_THREADS=1`）

### 3.1 计数与唯一性

```
$ grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d
(no output)
$ ctest --test-dir /tmp/xtb-o2/build -N -R landscape | tail -1
Total Tests: 101          # 100 -> 101：新增 xtb/landscape-vib-thermo-knobs
$ ctest --test-dir /tmp/xtb-o2/build -R landscape
100% tests passed, 0 tests failed out of 101      (31.45 s)
$ ctest --test-dir /tmp/xtb-o2/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
100% tests passed, 0 tests failed out of 12       (0.25 s)
$ ls /tmp/xtb-o2/build/Testing/Temporary/LastTestsFailed.log
(No such file or directory)                       # 运行前已删除，且本次运行未重建
```

### 3.2 M7 四体系验收（复核 04 §1.4 的同一驱动，夹具拷到 /tmp 跑，不动原始数据）

```
$ OMP_NUM_THREADS=1 XTBPATH=$PWD python3 /tmp/w0m7/exp1_thermo_check.py /tmp/xtb-o2/build/xtb
h2o    dfreq 0.0100 cm^-1  dZPE 1.429e-08  dH 1.426e-08  dG 1.429e-08 Eh  param-equal True
ch3oh  dfreq 0.0600 cm^-1  dZPE 2.975e-07  dH 3.070e-07  dG 2.530e-07 Eh  param-equal True
co2    dfreq 0.0000 cm^-1  dZPE 1.709e-08  dH 1.296e-08  dG 1.908e-08 Eh  param-equal True
c2h2   dfreq 0.0000 cm^-1  dZPE -3.400e-11 dH -2.100e-11 dG -4.200e-11 Eh param-equal True
```

与 04 §1.4 表**逐值相同**（含 c2h2 的负号）。

### 3.3 W0 三条缺陷行为不变

| 缺陷 | 本轮实测 | 断言位置 |
|---|---|---|
| ① `$fix` 六引擎 | 8/8（含 2 个 model 种子组合）位移 **0.00000e+00** | `xtb/landscape-fix-rfo` |
| ② `--lvib` 遵守 `$thermo` | `--lvib` vs `--hess` dH/dG **1.417e-08 / 1.431e-08**（list）、**1.282e-08 / 1.287e-08**（scale） | `xtb/landscape-vib-thermo` |
| ③ `--lopt` + `$scan` | exit **1** + 可操作信息（`--opt` / `--lscan --lscan-coord`） | `xtb/landscape-scan-xcontrol` |

---

## 4. 剩余处置（未修 / 未验证，如实记录）

### 4.1 新发现（同类问题，但**未修**）：`n_imag`/status 的阈值来源

- 事实：`landscape_vib_analysis` 用 `settings%imag_cutoff` 计 `vib%n_imag`
  （`src/landscape/vib/modes.f90`，`count(freq < settings%imag_cutoff)`），
  而 `print_thermo` 用**合并后**的 `set%thermo_ithr`；`n_imag` 又进入 JSON
  `counters.n_imag`、`status`/`status_name` 与 stdout 的 `imaginary modes:` 行。
- 后果：`$thermo imagthr=-10000` 时，热化学把 -1077 cm⁻¹ 的模**反号当成实模**
  （打印 `inverting freq`、G 改变 2.4e-3 Eh），但套件仍报 `n_imag = 1` / `incomplete`，
  并触发 `landscape_vib_thermo_output` 的既有警告「the thermochemistry counted a
  different number of imaginary modes …」。CLI `--lvib-imag-cutoff` 两路一致。
- **为什么没修**：修法只有两种，都改变**分析层语义**——(i) 分析改用合并后的阈值
  （需给 `landscape_vib_analysis` 加参数或回写 settings，触及 M3 的公开 API 与
  单测），(ii) 保留但明确文档化。这属于产品/架构决策，交父会话；本轮按任务书
  要求「成表列出」（§1.5）并在新测试里**刻意不钉住**该分歧。
- 无 `$thermo` block 时二者相同，**不影响**任何已验收数字（§3.2 的 4 个体系）。

### 4.2 复核里本轮未修、需记录的项

| 复核编号 | 内容 | 处置 |
|---|---|---|
| P2-5（复核编号，`--lscan` + `$fix` 的 relaxed 行） | 固定原子属于被扫坐标时目标不可达，点的 `converged` 仍可为真 | **未修**：值/残差列有记录（非静默）；PLAN §6.9 只把 rigid 模式列为待办 ⇒ 建议下一轮把 relaxed 行也标为待办（本轮不动 PLAN 该行以避免与父会话的 PLAN 编辑冲突） |
| P2-8 | 04 §1.2 写「0 warning」，实际有一条来自 FetchContent `test-drive` 的 **CMake Deprecation** 警告 | **未改 04 正文**：本轮 configure 复现该警告（`CMake Deprecation Warning at …/test-drive-src/CMakeLists.txt:14`），结论是措辞应为「无 `-O3` 警告」；记录在此 |
| P2-9 | 通用报错信息对 `--lscan` 情形自指 | **未修**（消息对 `--lopt/--lts/--lirc/--lvib` 正确；`--lscan` 的替代建议确实只能是 `--lscan-coord/--lscan-atoms`）。属措辞，未越界改 |
| INFO-1 | `--lopt` 新增 stdout 行 `fixed atoms ($fix): N …` 无断言 | **未修**：它是诊断行，生效性由 `xtb/landscape-fix-rfo` 的位移断言覆盖 |
| INFO-2 | `tasks/irc.f90` 的 `frozen=` 实参在 `$fix` 下不可达（入口已报错） | **未改**（死代码无害）；`irc.f90` 的引用已在本轮 §2.4 改为子程序名 |
| INFO-3 | `--lopt --opt -I $scan` 冲突时新守卫报错而用户确实传了 `--opt` | **未改**（行为优于静默；消息未提冲突） |
| INFO-4 | 04 §5 标题编号重复 | **未改**（纯排版，且不重写 04） |

### 4.3 未验证声明（不得当成已验证）

1. **meson 路径未执行**（本机无 meson）：新测试已登记 `test/unit/meson.build`，
   但**从未运行**。CMake 侧 101/101 是本轮唯一执行过的构建系统。
2. `-O3` 在 edcfbbe 上给错频率**本轮未复现**（无该源码状态的构建；04/03 的历史
   结论未变，本轮只核对「本 HEAD 的 `-O3` 探测正确」这一既存事实）。
3. `landscape_vib_result%temperature` 的 GFN-FF 特例（`print_thermo` 把内置 1.0
   替换成 1.03）**未做实验**，只按源码写入注释；本轮全部验收都是 GFN2。
4. 复核 05 §4 的「需运行验证清单」里与 W0 无关的项（`/tmp/xtb-o3` 的 `-O3` 探测
   stdout 存档）未处理——超出本轮范围。

---

## 5. 本轮变更文件（相对 W0 工作树；`git diff --cached` 为空，未提交）

| 文件 | 改动 |
|---|---|
| `src/landscape/types/results.f90` | `landscape_vib_result` 新增 `temperature`/`freq_scal`（生效值） |
| `src/landscape/vib/thermo.f90` | 新增 `landscape_vib_check_thermo_settings`（校验合并状态）；`landscape_vib_thermo_output` 回写生效值；模块文档更新 |
| `src/landscape/tasks/vib.f90` | merge+check 提前到首个单点之前；删除私有的 settings-only 校验；`write_json` 改读 `vib%` |
| `src/landscape/types/constraints.f90` | 模块头：BFGS 只在解耦初值下可证（P2-3） |
| `src/landscape/optimize/driver.f90` | 同一句话软化（注释） |
| `src/prog/main.F90` | `$scan` 守卫注释改为可持久引用 |
| `cmake/CMakeLists.txt` | `-O3` 检测：遍历所有配置 + 归一化分号列表 |
| `test/unit/landscape_cli_check.py` | `check_thermo`（JSON 生效值 + 4 条 `$thermo` 反例）、新 `check_thermo_knobs`、`check_fix`（+2 组合）、`check_saddlefix`（契约） |
| `test/unit/CMakeLists.txt` | 新 ctest `xtb/landscape-vib-thermo-knobs` |
| `test/unit/meson.build` | 同上（meson 侧，未执行） |
| `docs/_simplify-recon/04-*.md` | 98→100 口径、行号→子程序名、BFGS 加注（增量订正） |
| `docs/xtb-landscape-PLAN.md` | §6.9 表的行号 → 子程序名 |
| `docs/_simplify-recon/06-w0-closeout-report.md` | 本文 |
