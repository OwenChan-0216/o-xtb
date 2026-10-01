# M3（Hessian / freq / thermo）实现报告（第 20 号）

> 输入：`docs/xtb-landscape-PLAN.md` §5.3.7/§5.3.8、§6、§9.4、§12；`AGENTS.md` §5/§6/§7
> 目标：实现 M3（`vib`），并清掉 M2 的两个遗留（M-1 `--lscan-max-steps`、M-2 全域未收敛的最小值搜索）
> 纪律：所有 xtb/ctest 调用 `OMP_NUM_THREADS=1`；只跑 `-R landscape` 与
> `-R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'`
> 结果：**构建干净、`ctest -R landscape` 32/32、回归 12/12**；7 次注入实验中 6 次转红
> （第 6 次记录了"断言粒度"这一发现），全部已回滚并复跑确认 13/13 绿

---

## 0. 结论

| 交付物 | 状态 | 证据 |
|---|---|---|
| `src/landscape/vib/numhess.f90`（147 行） | ✅ | `landscape_vib_hessian`：engine + provider + ODLR 显式拒绝；测试 `odlr-unsupported` |
| `src/landscape/vib/modes.f90`（349 行） | ✅ | Eckart 投影 + 质量加权 + `diagHessian` + 3N−6/3N−5 计数；测试 6 条 |
| `src/landscape/vib/thermo.f90`（173 行） | ✅ | 只做「settings → `set` 拷贝 + `freq_results` 填充 + `main_freq`」；不重写 RRHO |
| `types/hessian.f90` 的 `landscape_hessian_file`（+460 行） | ✅ | 严格读写器（缺文件/坏头/截断/维数/非对称/非有限 六类失败）；测试 3 条 |
| `src/landscape/tasks/vib.f90`（277 行） | ✅ | 四个输出文件与 `--hess` 同名同格式；CLI 测试 `xtb/landscape-vib-cli` |
| CLI 接线（`--lvib` + 11 个子 flag，runtyp 21） | ✅ | `setparam/set_module/prog/main.F90/xhelp` 四处同步；`src` 内**唯一**回写 `res` |
| `landscape_driver.f90` 分派 | ✅ | 新增 `case ('vib')` + `landscape_vib_settings` 类型检查（`landscape_api.f90` 只是 `landscape_run` 的转发，无需改动） |
| 测试 `test/unit/test_landscape_vib.f90`（1036 行，13 条） | ✅ | `ctest -R landscape-vib` 13/13 PASSED |
| 三处测试注册（CMake / meson / `main.f90`） | ✅ | `ctest -N -R landscape` = 32 个目标，无重名 |
| M2 遗留 M-1 `--lscan-max-steps` | ✅ | CLI flag + 单元测试 + `xtb/landscape-scan-max-steps` |
| M2 遗留 M-2 全域未收敛的最小值搜索 | ✅ | 新分支 + `scan-task-no-converged-point` + 上面那个 CLI 测试 |

---

## 1. 模块与接口

### 1.1 `xtb_landscape_vib_numhess`（`vib/numhess.f90`）

一次调用返回 `(hess, energy, gradient, final_err, fail)`：

* engine 由 `new_landscape_engine(settings%engine)` 构造，provider 由
  `new_landscape_hessian_provider(..., sccacc=settings%engine%hess_acc,
  filename=settings%hessian_file)` 构造（M1 的抽象层，未改动算法层）；
* 先 `energy_gradient`（参考能量/梯度，同时是差分参考态），再 `hessian(step=engine%hess_step)`；
* **ODLR 在此统一拒绝**：`engine%odlr = .true.` 时在第一次 SCF 前 `env%error` 并返回
  `fail=.true.`。理由：`numerical` provider 自己会拒绝，但 `model`/`file` 的 `compute`
  会**静默忽略**该标志并返回完整稠密矩阵——那正是任务书禁止的"静默忽略"。provider
  内部的拒绝保留为第二道防线（`file_hessian_compute` 也拒绝 `odlr`）。

### 1.2 `xtb_landscape_vib_modes`（`vib/modes.f90`）

`landscape_vib_analysis(env, mol, hessian, settings, vib, fail)`：

| 步 | 做法 | 复用的既有代码 |
|---|---|---|
| 1 | 对称化 `0.5*(H+Hᵀ)` | — |
| 2 | 质量加权 `h/√(mᵢmⱼ)`（`mol%atmass` 为 a.u.） | `xtb_freq_utils::massWeightHessian`（与 `src/prog/thermo.f90:132` 同一调用） |
| 3 | 平动/转动投影（**线性分子跳过**，同 `numhess`） | `xtb_freq_project::projectHessian`（Eckart，质量加权空间） |
| 4 | 反加权回非质量加权形式（写出 `hessian` 文件用） | `landscape_vib_mass_unweight`（`massWeightHessian` 的显式逆） |
| 5 | 对角化（`syev`，`uplo='u'` ⇒ 本征值升序） | `xtb_freq_utils::diagHessian` |
| 6 | 频率 `sign(√|ev|,ev)·autorcm`（cm⁻¹，虚频为负） | 与 `numhess` 的换算式逐字一致 |
| 7 | 排序 + 计数 + 约化质量 | 布局与 `freq_results` 一致 |

**排序与符号约定（与既有输出一致）**：`freq(1:n_zero)` = 投影掉的平动/转动，**恰好 0**；
`freq(n_zero+1:3N)` = 内模，按本征值升序，因此虚频（负值）排在最前。
`n_zero`：线性分子 5、非线性 6、单原子 3（`n_vib = 3N − n_zero`，恒等式，永不丢模）。
不变式 `n_vib = 3N−6`（线性 3N−5；单原子 0）。

两处与 xtb 的差异（都写进了代码注释）：

1. 非线性分子若"近零模"少于 6 个，沿用既有实现的硬错误
   （"too few rot/trans modes found, hessian is unusable"，`src/hessian.F90:437`）；
   线性分子按既有实现**无条件**取最低 5 个本征值为零模（不判阈值）——实测
   CO2 的数值 Hessian 零模被噪声抬到 0.01 cm⁻¹ 以上，若判阈值会误杀所有线性分子。
2. 既有实现保留零模的残差（<0.01 cm⁻¹）；本套件把它们写成**精确 0**。差异在
   `f18.2`/`f9.2` 的打印精度下不可见（实测 `vibspectrum` 中显示 `0.00` 而既有实现
   显示 `-0.00`），换来的是一条可证伪的断言（"前 `n_zero` 个恰为 0"）。
3. 额外的近零模（超过 `n_zero` 的那些）**不丢弃**，按升序留在内模里，因此
   `n_vib = 3N − n_zero` 恒成立（既有实现会把它们丢掉并静默少一个模式）。

### 1.3 `xtb_landscape_vib_thermo`（`vib/thermo.f90`）

薄封装，**没有**重写任何热化学：

1. `landscape_vib_set_thermo_settings`：把 `landscape_vib_settings` 拷进既有全局
   `set%thermotemp(50)/nthermo/thermo_sthr/thermo_ithr/thermo_fscal`
   （`src/setparam.f90:284-291`）；
2. 把 `set` 之外的全局依赖补齐：`xtb_splitparam::atmass = mol%atmass*autoamu`
   （单位 amu）。**这是必须的**：`print_thermo → axis2`（`src/axis_trafo.f90:59`）
   从该全局读原子质量，`src/prog/main.F90:461` 与 `src/prog/thermo.f90:103` 都
   同样地填它；不填会读到未分配内存（实测：单元测试进程内 **SIGSEGV**）；
3. `freq_results` 由 `landscape_vib_result` 填充（频率、质量加权模、约化质量、
   参考能量），`dipt/polt = 0`；
4. 调 `xtb_propertyoutput::main_freq`（`--hess` 背后的那个函数）：打印频率/约化质量/
   强度表、写 `vibspectrum` 与 `g98.out`、经 `print_thermo → xtb_thermo::thermodyn`
   得到热化学表；
5. 回读 `res%zp`（→ `vib%zpe`）并与 `vib%n_imag` 交叉核对（不一致只告警：`freq_scal`
   会移动虚频 cutoff）。

**明确的能力边界**：IR/Raman 强度为 0（`vibspectrum` 打 `NO`）。强度是偶极/极化率
**导数**，xtb 从解析 Hessian（`numhess` 的 `dipd`）得到，而本套件的 Hessian 来自抽象
provider，不带导数。频率与全部热化学量不受影响。这一点写在模块 docstring 与报告里。

### 1.4 `landscape_hessian_file`（`types/hessian.f90`）

* 格式：与 `wrhess`/`rdhess`（`src/freq/io.f90`）**逐位一致**——`$hessian` 头 + 完整
  方阵按行、每记录 5 列、`(5x,5f15.10)`；`$end` 可选。
* 读入时按 `rdhess` 的约定 `h(j,i) ← 第 i 行第 j 个数`，因此文件里真出现不对称时
  可以被检出（packed 三角形写法的文件反而检不出）。
* 失败路径（全部 `env%error` + `ok=.false.`，且**不改动**目标矩阵）：打不开/缺失、
  首记录无 `$hessian`、记录里有非数字 token、值的个数 ≠ (3N)²（维数不符，含截断与
  超大两种方向的清晰计数消息）、`|h(i,j)−h(j,i)| > 1e−8·max(1,|h|)`（非对称）、
  非有限元素。
* 不复用 `rdhess` 的理由：`rdhess` 的读取没有 `iostat`，损坏文件会**终止进程**，
  无 `$hessian` 头时静默返回零矩阵——与"明确报错不崩溃"的要求冲突。写侧同理没有
  直接调 `wrhess`（它无法报告打开失败），而是复刻同一格式；**测试 `hessian-file-roundtrip`
  用 `wrhess` 的输出做逐字节比对**，格式一致性因此仍是可证伪的。
* 分隔符：空格/逗号/tab **以及 CR**（CRLF 行尾的文件来自其它平台时不会被当成损坏；
  `hessian-file-roundtrip` 里有一条 CRLF 往返断言）。
* 命名空间：读写都走 `get_namespace`（写用带前缀名，读先试前缀名再回退原名，
  与 `persistentEnv%io%readFile` 同构），所以 `--namespace foo --lvib` 写
  `foo.hessian`，而 `--lvib-hessian-file hessian` 仍能找到默认名。

### 1.5 `xtb_landscape_tasks_vib`（`tasks/vib.f90`）

驱动：建 Hessian → 分析 → 写 `hessian` → 调 thermo 包装（写 `vibspectrum`/`g98.out`/
热化学表）→ 写 `vib_normal_modes`（复用 `writeNormalModesTurbomole`，质量单位 amu
=`mol%atmass*autoamu`）→ 填 `landscape_result`。`result%energy` 是**被分析几何**的
能量，供 `main.F90` 回写 `res`（硬要求，见 §3 证据）。

`write_files=.false.` 只关掉本套件自己写的两个文件；`vibspectrum`/`g98.out`/热化学表
由复用的 `main_freq` 无条件产生（该函数没有输出开关），已写入 PLAN §12.11。

---

## 2. 可证伪性：7 次注入实验（真实输出）

流程：改源码 → `cmake --build` → `./xtb-tester landscape-vib`（Release，`OMP_NUM_THREADS=1`）
→ 记录转红用例 → 回滚 → 复跑确认 13/13 绿。全部源码改动已用 `diff` 逐字节回滚验证。

| # | 注入 | 转红的用例（真实消息） |
|---|---|---|
| 1 | `landscape_vib_analysis` 里 `projectHessian` 调用被关掉 | `water-modes-gfn2 [FAILED] Message: the water analysis failed`；`water-vs-trproj [FAILED]`；`hessian-file-provider [FAILED] Message: the direct analysis failed`；`vib-task-water [FAILED] Message: the vib task did not converge`（共 5 条红） |
| 2 | `landscape_vib_mass_unweight` 的指数写反（`1/√m` 代替 `√m`） | `mass-weight-roundtrip [FAILED] Message: the mass weighting is not invertible`；`water-vs-trproj [FAILED] Message: the Eckart frequency deviates from the trproj reference`；`hessian-file-provider [FAILED] Message: the file Hessian does not reproduce the frequencies` |
| 2b | 在分析链里把加权与反加权连着调（指数差 2 次幂） | `diatomic-analytic-frequency [FAILED] Message: the analytic diatomic frequency was not reproduced`；`hessian-file-provider [FAILED]` |
| 3 | 零模不再置零（保留残差） | `water-modes-gfn2 [FAILED] Message: the projected zero modes are not exactly zero`；`hessian-file-provider [FAILED]` |
| 4 | 线性分子也要求 6 个零模 | `diatomic-analytic-frequency [FAILED] Message: a linear molecule must have 5 zero modes`；`co2-linear-modes [FAILED] Message: a linear molecule has 5 zero modes` |
| 5 | `landscape_write_hessian_file` 每个元素 ×0.5 | `hessian-file-roundtrip [FAILED] Code: 1 Message: the Hessian round trip is not bitwise` |
| 7 | 删掉读入器的维数检查 | `hessian-file-failures [FAILED] Message: a truncated Hessian file was accepted` |

第 6 次注入（删掉 `$hessian` 头检查）**没有**转红：坏头文件随后仍会因值个数不符被
维数检查拒绝，断言"必须报错"依旧成立。记录在此，因为它说明失败路径测试的断言粒度
（"被拒绝"）比实现细节更稳；维数检查的证伪由第 7 次注入承担。

回滚后：
```
$ OMP_NUM_THREADS=1 ./xtb-tester landscape-vib | grep -c PASSED
13
```

---

## 3. 验收证据（真实执行）

### 3.1 构建与测试

```
$ cmake --build /tmp/xtb-land/build -j
[100%] Built target xtb-tester          # 无 error / warning

$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape
100% tests passed, 0 tests failed out of 32
Total Test time (real) =   0.96 sec

$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
100% tests passed, 0 tests failed out of 12
Total Test time (real) =   0.24 sec

$ ctest -N -R landscape | tail -1
Total Tests: 32
$ grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d
（无输出：无重名）
```

`xtb/landscape-vib`（13 条单元用例）：
```
mass-weight-roundtrip, linear-detection, diatomic-analytic-frequency,
rosenbrock-analytic-hessian, projection-required, water-modes-gfn2,
water-vs-trproj, co2-linear-modes, hessian-file-roundtrip,
hessian-file-provider, hessian-file-failures, odlr-unsupported, vib-task-water
```

### 3.2 CLI（水分子）

```
$ XTBPATH=$PWD OMP_NUM_THREADS=1 /tmp/xtb-land/build/xtb h2o.xyz --gfn2 --lvib --norestart
landscape: harmonic frequencies
Hessian source:           numerical
Hessian step:                5.000000E-03 bohr
Hessian SCC accuracy:        3.000000E-01
project translations/rotations: T
...
eigval :        0.00     0.00     0.00     0.00     0.00     0.00
eigval :     1564.32  3634.77  3646.27
...
modes: 3 internal, 6 projected zero modes
linear molecule:          F
imaginary modes:          0
lowest mode:      1564.32 cm^-1, highest mode:      3646.27 cm^-1
energy:                        -5.070383735497 Eh
zero point energy:           2.015122E-02 Eh
Hessian residual:            0.000000E+00
landscape task terminated: frequency analysis completed
...
| TOTAL ENERGY               -5.070383735497 Eh   |     # = 任务能量 ⇒ res 回写生效
```
写出的文件（`--namespace` 未设时就是这四个名字）：
```
-rw-r--r--  1981 g98.out
-rw-r--r--  1332 hessian
-rw-r--r--  1354 vib_normal_modes
-rw-r--r--   722 vibspectrum
```
`hessian` 可被 `--lvib-hessian file` 读回并复现同一频率表（`xtb/landscape-vib-cli`
与 python 版 `landscape_cli_check.py vib` 都断言了这一点，两处均 PASS）。

### 3.3 与既有 `--hess` 的一致性（同分子两路径）

同一个 `h2o.xyz`（0.96 Å / 0.929 Å、104.5°）：

| 路径 | 频率（cm⁻¹） |
|---|---|
| `--lvib`（Eckart/`projectHessian`） | 1564.32 / 3634.77 / 3646.27 |
| `--hess`（遗留 `trproj`） | 1564.32 / 3640.48 / 3646.32 |

最大差出现在反对称 O–H 伸缩。**归因（第 23 号修复轮重测修正）**：差异来自前端投影
（Eckart vs 遗留 `trproj`），**不是**「解析 vs 数值 Hessian」——两条路径
**都是**中心差分 Hessian（步长 0.005 bohr、SCC 精度 0.3），`--hess` 自己的 stdout 写的就是
`| Numerical Hessian |` / `step length 0.00500` / `SCC accuracy 0.30000`。
把**同一个**原始 Hessian 分别过两条投影可得（见单元测试 `water-vs-trproj` 与
第 23 号报告）：极小点 0.074 cm⁻¹、非驻点 5.213 cm⁻¹、强扭曲水 12.91 cm⁻¹。
CLI 同几何对比的可复现数字是 **0.0757（H2O 极小点）/ 0.9972（CH3OH 极小点）/
0.0036（CO2）/ 5.2109（非驻点 H2O）cm⁻¹**；本文上一轮写的「5.71 cm⁻¹」来自一个
未入库的 `h2o.xyz`，建议用上面四个分档数字代替。**差异的来源**是两个投影
在**不同度量**里定义同一套刚体运动（`trproj`：单位质量向量 + 非质量加权 Hessian；
Eckart：质量加权向量 + 质量加权 Hessian），而 **`trproj` 不含任何梯度项**
（`src/freq/project.f90:151-215`）。把各自写出的 `hessian` 喂给共享下游

```
$ xtb thermo h2o.xyz hessian       # 我们写的（Eckart 投影后）
eigval :       -0.02    -0.01    -0.00    -0.00     0.00     0.02
eigval :     1564.32  3634.77  3646.27        # = 我们的 --lvib，逐位相同
$ xtb thermo h2o.xyz xtbhess.dat   # xtb --hess 写的
eigval :       -0.02    -0.00    -0.00     0.00     0.00     0.00
eigval :     1564.32  3640.48  3646.32        # = --hess，逐位相同
```
即两条路径各自的 `hessian` 文件在既有工具链里都自洽（0.01 cm⁻¹ 打印精度内），
`xtb --thermo` 能直接读我们的文件。

**线性分子（CO2，1.1439 Å）**：`--lvib` 601.33/601.33/1423.40/2590.54，
`--hess` 601.36/601.36/1423.40/2590.54，最大差 **0.03 cm⁻¹**——因为线性分子按既有
做法跳过投影，两条路径走完全相同的后处理。

**容差依据**：单元测试 `water-vs-trproj` 断言同一原始矩阵两条投影的频率差
`≤ 0.005·|f_ref| + 0.5 cm⁻¹`（实测该几何 12.91 cm⁻¹ / 0.31 %，裕度 ~1.5 倍），并额外
断言两者**不**逐位相等（防止参照矩阵被分析例程就地覆盖后把测试变成恒真；
第 23 号修复轮发现并修正了这个缺陷）。PLAN §6.6 允许 `projectHessian`/`trproj`
二者之一；本套件选 Eckart（§5.3.8、R04 §71 指定），并且 Eckart 正是 xtb 自己
`--thermo` 路径的投影（`src/prog/thermo.f90:136`）。

### 3.4 输出格式与既有 `--hess` 对齐（逐行结构比对）

```
$ diff <(sed 's/-\?[0-9]\+\.[0-9]\+//g' ours/vibspectrum) \
       <(sed 's/-\?[0-9]\+\.[0-9]\+//g' theirs/vibspectrum)
# 只有数值列不同；表头、列名、`$end` 逐行相同
$ diff <(sed 's/-\?[0-9]\+\.[0-9]\+//g' ours/g98.out) \
       <(sed 's/-\?[0-9]\+\.[0-9]\+//g' theirs/g98.out)
# 结构相同（"Standard orientation"、频率块、坐标块逐行一致）
```
仅两处内容差异，均为已知且已文档化：
1. 零模频率列：我们 `0.00`，既有 `-0.00`（我们把零模写成精确 0）；
2. IR 强度列：我们 `0.00000 NO`，既有 `131.95795 YES`（无偶极导数，§1.3）。
`vib_normal_modes`：既有 `--hess` 只在 xcontrol 打开 `set%pr_nmtm` 时写，而任务书
要求总是写；内容由同一个 `writeNormalModesTurbomole` 产生。

### 3.5 边界与失败路径（实测）

| 场景 | 行为 |
|---|---|
| 单原子（Ar） | `modes: 0 internal, 3 projected zero modes`，正常结束（不误报 3N−6） |
| `--lvib-hessian model` | 正常：2333.99/4146.77/4195.97 cm⁻¹（Lindh-D2 模型 Hessian 的平动/转动块为零，零模干净） |
| `--lvib --lvib-no-project` | 非零退出：`too few rot/trans modes found, the Hessian is unusable`（PLAN §6.6 的"未投影 ⇒ 6 个伪零频"被实测坐实） |
| `--lvib-step 0` | 非零退出：`the finite difference step of the numerical Hessian must be positive` |
| `--lvib --lvib-odlr` | 非零退出：`the ODLR approximation of the numerical Hessian (src/o1numhess.f90) is not implemented in the landscape suite` |
| `--lvib-hessian file` 无文件 | 非零退出：`cannot open Hessian file 'no_such_file.dat'` |
| 拉长 O–H（2.6 Å） | `-801.31 cm⁻¹`，`imaginary modes: 1`，`terminated: frequency analysis completed with imaginary modes`，并写出 `xtbhess.xyz`（与 `--hess` 的 `distort` 行为一致） |

---

## 4. M2 遗留

### 4.1 M-1：`--lscan-max-steps`

新增 CLI flag（`src/prog/main.F90`，帮助文本在 `src/xhelp.f90`），语义是把内层松弛的
步数预算写进 `landscape_scan_settings%max_steps`（0 合法，见下）。

### 4.2 M-2：全域未收敛的最小值搜索

`src/landscape/tasks/scan.f90` 增加显式分支：当**没有任何**扫描点收敛时
（`n_unconverged == n_steps` 且无硬失败点）

* `result%message = "scan completed without a converged point"`；
* `env%warning(...)`：说明能量**未定义（保持 NaN）**且参考几何是输入几何，并提示
  提高 `max_steps`；
* `result%converged = .false.`（原本已如此），`result%energy` 保持
  `landscape_missing_value()`（NaN），`mol%xyz` 保持输入几何。

不把它升级为 `env%error`：既有设计里"点未达收敛判据"是告警不是失败（PLAN R-04），
只有"点根本没有能量"才是硬失败。该分支把两者的区别显式化。

**1D 与 2D 语义一致（代码复核）**：`landscape_scan1d` 与 `landscape_scan2d` 的最小
值搜索都要求点**已收敛**（`scan2d.f90:201` 的 `if (.not. grid%converged(i,j)) cycle`
与 1D 循环里的同一判据），所以两条路径在"全域未收敛"时都得到 NaN；这一点写进了
`tasks/scan.f90` 的注释，并由测试同时覆盖 1D 与 2D。

单元测试 `scan-task-no-converged-point`（`max_steps = 0`）断言：无硬错误、
`n_steps = 3`、`converged = .false.`、能量非有限、消息精确匹配、几何未被移动、
`xtbscan.log` 仍有 3 帧（点被求值过），并在同一测试后半段用 `max_steps = 256`
复跑同一设置确认会收敛出真实最低能量；最后用同一 `max_steps = 0` 跑一个 2D 网格，
断言它同样 `converged = .false.`、消息相同、能量同样非有限（不把"最好但未收敛的点"
当成最小值）。CLI 层测试 `xtb/landscape-scan-max-steps`（CMake + python 版
`maxsteps`）用 `--lscan-max-steps 0` 复现 1D 的断言。

---

## 5. 未完成 / 残留风险

1. **实验 #2（Hessian 步长 × sccacc 敏感度）、#3（`etemp` 对最低本征值）与
   #12（线性分子 3N−5）已在验证轮完成**，数据与结论见
   `docs/_landscape-recon/21-m3-validation-experiments.md`（79 个作业，
   `m3-vib-data/`）。本文这一条是当时的状态，已由 PLAN §9.4 与 §12.11 更新。
2. **IR/Raman 强度为 0**（§1.3）。若后续要补，需要 provider 接口额外暴露偶极导数，
   属于 ≥M3 的解析钩子工作。
3. **投影约定与 `--hess` 的差异**（§3.3）已在 PLAN §12.11 与本文记录（分档：
   0.0036–0.0757 cm⁻¹ @ 极小点，最高 5.21 cm⁻¹ @ 非驻点）。若要求与 `--hess`
   **逐位**一致，替代方案是改用 `trproj`（实测可复现 `--hess` 到 ~0.006 cm⁻¹，
   残余来自两个 FD 驱动的实现差异）；当前选择是 PLAN §5.3.8/R04 §71 指定的 Eckart。
4. `landscape_vib_result%zpe` 由热化学包装填充（`print_thermo` 的定义），
   `modes.f90` 不自己算 ZPE——避免同一概念两种拼写；因此**不**调用 thermo 包装的
   路径上 `zpe` 保持 0（当前 CLI 总是调用，任务层不受影响）。
5. meson/ninja 本机未安装：`meson.build`（源码与测试）按约定同步了，但**无法验证**；
   python 版 CLI 检查器已在本机直接调用验证过三个新 mode（`vib`/`maxsteps`/`scanhess`）。
6. 单原子分子的 `n_zero = 3`（而不是 5/6）是一个小扩展：xtb 的 `print_thermo` 把单
   原子当 rotor-only 处理，本套件用"3 个平动 + 0 内模"表达同一件事。

---

## 6. 变更文件清单

实现（新增）：`src/landscape/vib/numhess.f90`、`src/landscape/vib/modes.f90`、
`src/landscape/vib/thermo.f90`、`src/landscape/tasks/vib.f90`、
`test/unit/test_landscape_vib.f90`。

实现（修改）：`src/landscape/types/settings.f90`（`landscape_vib_settings` + 基类
`hessian_file`）、`src/landscape/types/results.f90`（`landscape_vib_result`）、
`src/landscape/types/hessian.f90`（`file` provider + 严格读写器）、
`src/landscape/landscape_driver.f90`、`src/landscape/tasks/{sp,opt,scan}.f90`
（provider 工厂传入文件名）、`src/landscape/tasks/scan.f90`（M-2 分支）、
`src/landscape/{CMakeLists.txt,meson.build}`。

集成：`src/setparam.f90`（`p_run_lvib = 21`）、`src/set_module.f90`、
`src/prog/main.F90`（runtyp 列表、分派 + `res` 回写、`--lvib*`/`--lscan-*`/
`--lopt-hessian-file` flag、`finalize_xtb` 计时）、`src/xhelp.f90`。

测试注册与 CLI 检查：`test/unit/CMakeLists.txt`、`test/unit/meson.build`、
`test/unit/main.f90`、`test/unit/landscape_cli_check.py`、
`test/unit/test_landscape_hessian.f90`（`file` 现在是已知源）、
`test/unit/test_landscape_scan.f90`（M-2 用例）。

文档：`docs/xtb-landscape-PLAN.md`（§9.4 状态、§12.11 新增）。

---

## 7. 复现命令（本轮最终一次运行）

```
$ cmake -S . -B /tmp/xtb-land/build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON -DCMAKE_BUILD_TYPE=Release
-- Generating done
$ cmake --build /tmp/xtb-land/build -j
[100%] Built target xtb-tester
$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape
100% tests passed, 0 tests failed out of 32          # 1.07 s
$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
100% tests passed, 0 tests failed out of 12          # 0.25 s
$ XTBPATH=$PWD OMP_NUM_THREADS=1 /tmp/xtb-land/build/xtb h2o.xyz --gfn2 --lvib --norestart
exit=0
hessian            1332 bytes
vibspectrum         722 bytes
vib_normal_modes   1354 bytes
g98.out            1981 bytes
| TOTAL ENERGY               -5.070383735497 Eh   |   # = 任务能量 ⇒ res 回写生效
```
