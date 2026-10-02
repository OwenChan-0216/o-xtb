# 42 — M6 IRC 第一阶段（GS + LQA + 共享 corrector + 任务 driver）实现报告

> 里程碑：M6（第一阶段）。范围：**GS + LQA + 共享 corrector + 任务 driver**。
> HPC / EulerPC 属于第二阶段，本轮**只**留成 `env%error("<method> is not
> implemented yet")`（非零退出码），不实现。
>
> HEAD：`2ed7750`（M5 提交之后的工作树，未提交；父会话统一提交）。
> 所有 `xtb` / `ctest` 调用均带 `OMP_NUM_THREADS=1`。

---

## 0. 摘要

| 项 | 结果 |
|---|---|
| 新增源文件 | `src/landscape/irc/{corrector,gs,lqa}.f90`、`src/landscape/tasks/irc.f90` |
| 新增测试 | `test/unit/test_landscape_irc.f90`（18 个单元用例）+ 6 个 CLI 级 ctest |
| LOC | corrector 902 / gs 421 / lqa 231 / tasks/irc 840 / 测试 1038 |
| 构建 | 0 warning（`touch` 全部 IRC 文件后重建） |
| `ctest -R landscape` | **77/77 通过**（M5 结束时 70；本轮 +1 单元套件 +6 CLI） |
| 回归子集 | `-R 'Singlepoint\|GFN\|model-hessian\|optimizer\|Argparser\|CAPI'` → **12/12** |
| 重名检查 | `grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt \| sort \| uniq -d` → **空** |
| 端到端 | `xtb xtbts.xyz --gfn2 --lirc --lirc-method gs` → exit 0，四个文件，端点 = HNC / HCN |
| 可证伪注入 | 5/5 全部按预期变红并已还原（§8） |
| 已知偏离 | GS 每点平均 E/g = 16.9/20.3（PLAN 预期 3–5，见 §10 R-1）；相位注入下「逐位确定性」不变红（§8.4 覆盖缺口） |

---

## 1. 交付物与文件

| 文件 | 内容 |
|---|---|
| `src/landscape/irc/corrector.f90`（902 行） | 四法共享内核：质量加权坐标/梯度/Hessian 变换、初始方向选择（复用 M4 相位约定）、LQA 解析传播（Page–McIver 支）、DWI 面拟合、modified Bulirsch–Stoer（简单 Euler 基本步）、路径容器 |
| `src/landscape/irc/gs.f90`（421 行） | Gonzalez–Schlegel：pivot + 半径 `s/2` 球约束 + 微循环（切空间曲率平移 Newton + 球面投影） |
| `src/landscape/irc/lqa.f90`（231 行） | LQA 单步传播（每宏步 1 次 E/g） |
| `src/landscape/tasks/irc.f90`（840 行） | `--lirc` 任务 driver：虚频确认、双向积分、端点归属、四个输出文件 |
| `test/unit/test_landscape_irc.f90`（1038 行） | 18 个 L1 解析势单元用例 |
| `src/landscape/types/settings.f90` | `landscape_irc_settings` + `p_landscape_irc_*` + 名字/查询函数 |
| `src/landscape/types/results.f90` | `landscape_irc_result` + 三终止信号常量 + `landscape_irc_result_write` |
| `src/landscape/landscape_driver.f90` | `case ('irc')` 分派（经 `run_irc_task` 把 TS 能量回写 `landscape_result`） |
| `src/setparam.f90` / `src/set_module.f90` / `src/prog/main.F90` / `src/xhelp.f90` | 接线（§5） |
| `src/landscape/CMakeLists.txt` / `meson.build`、`test/unit/{CMakeLists.txt,main.f90,meson.build,landscape_cli_check.py}` | 构建/测试注册 |

**构建注册**（`src/landscape/CMakeLists.txt:45-48`、`src/landscape/meson.build:45-48`）：
`irc/corrector.f90`、`irc/gs.f90`、`irc/lqa.f90`、`tasks/irc.f90`（两处手工同步）。
**测试注册**（三处一致）：`test/unit/CMakeLists.txt:52`（`"landscape-irc"`）、
`test/unit/main.f90:50/107`、`test/unit/meson.build:63`。

---

## 2. 接口契约（父会话裁定，已在 PLAN §12.14 记录）

1. **输入几何 = TS 本身**：`xtb xtbts.xyz --gfn2 --lirc --lirc-method gs` 是自然
   工作流。**虚频确认**：复用 M3 `landscape_vib_analysis`，恰好 1 个虚频才算 TS；
   0 个 → 「minimum」、≥2 → 「higher order saddle」，均 `env%error` + **非零退出码**
   （不是 warning；M4 的 H2 教训）。实测（§7.1、§7.5）exit=1。
2. **forward 方向确定性**：复用 M4 相位约定
   （`xtb_landscape_saddle_eigenfollow::landscape_transition_mode_set_phase`，
   最大绝对分量取正），在输出中打印该分量值与原子编号；`--lirc-swap` 显式取反并在
   `irc.log` 记录。实测同一输入两次运行 `irc_forward.xyz` **逐位相同**（§7.1）。
3. **单位契约**：IRC 步长单位 = `bohr*amu^1/2`（质量加权弧长）。`corrector.f90` 头注释、
   `landscape_irc_settings` 每个字段、`irc.log`、`--help` 全部标注该单位。质量加权用
   **amu**（`getAtomicMass*autoamu`），不是振动分析的电子质量 a.u. 度量。
4. **LQA 谱系**：实现 **Page & McIver 支**（Page & McIver, JCP **88**, 922 (1988)），
   即 HPC/EulerPC 论文与 Gaussian 所引的二次 Taylor 解析传播；在 `corrector.f90`
   头注释中明确记录与 Sun–Ruedenberg/Eckert–Werner QSD 形式
   （`x(u) = x^(k) - H^{-1}(I - uH) g`，三点区分）的差异，且 QSD **不实现**。
5. **mBS 用简单 Euler**（不是 modified midpoint），`mbs_max_k=15`、`mbs_points=20`、
   `mbs_tol` 默认 MAPLE 的 1e-5，HPC 论文的 1e-6 经 `--lirc-mbs-tol 1e-6` 可选暴露；
   收敛失败返回 `converged=.false.`（供调用者回退 GS 一步并告警）。
6. **Hessian 沿路径**：默认 Bofill（复用 `optimize/hessian_update.f90`，更新后强制
   对称化），`hessian_recalc=N` 每 N 步用 provider 重建；初始 Hessian 走 M3 provider。

---

## 3. 算法与实现要点

### 3.1 共享内核 `irc/corrector.f90`

* **质量加权**：`q_i = sqrt(m_i/amu) r_i`、`g^q_i = g_i/sqrt(m_i/amu)`、
  `H^q_ij = H_ij/sqrt(m_i m_j)`。度量在质量加权坐标下为单位矩阵（等价于 PLAN §6.5
  的 `G = M^{-1}` 写法，推导见头注释）。
* **初始方向**：`mctc_syev`（升序）→ 第 `target` 个最负模；无负本征值 → `env%error`。
* **LQA 解析传播**（`landscape_irc_lqa_step`）：`dx(t)=U a(t) U^T g0`，
  `a_ii(t)=(e^{-λ_i t}-1)/λ_i`；弧长 `S(t)=∫|g(t)|dt` 单调，用 **Simpson 积分 +
  二分**求 `S(t*)=s`（`euler_n` 个面板，即论文 Eq.10 的 `N_Euler=5000`）。
  `|λ_i| ≤ 1e-10·max(1,|λ|max)` 的零模（刚体/数值）从传播与弧长中剔除。
* **DWI 面**：`E_DWI = Σ w_i T_i / Σ w_i`，`T_i` 为各样本点的二次展开，
  `w_i = 1/(|x-x_i|²+ε²)`（Shepard 逆平方距离；原文权重函数未能逐字取得，报告 04
  标为 missing evidence，此处如实记录为偏离）。解析梯度含 `∇w` 项。
* **mBS**：层 `k` 用 `mbs_points·2^k` 个简单 Euler 子步、步长 `s/(mbs_points·2^k)`；
  Richardson 外推（因子 `2^j`）；RMS 差 < `tol` 收敛，否则返回 `converged=.false.`；
  `max_points` 限制一次校正的 ODE 评估数。

### 3.2 GS `irc/gs.f90`

* pivot `q* = q - (1/2) s (g^q/|g^q|)`（质量加权坐标下 `N = (g^T G g)^{-1/2} = 1/|g^q|`），
  球半径 `s/2` 且过当前点。
* 首步（TS 处梯度≈0）沿过渡向量 `±v` 走半步。
* 微循环：切空间投影 Hessian `P H P`（`P = I - e_r e_r^T`）`mctc_syev` 对角化，剔除
  径向零方向；负/近零曲率按正平移下限；切向 Newton 步**限幅到球半径**后
  `project_sphere` 投影回球面。收敛判据 = 步长 < `micro_step_thresh`（或耗尽
  `max_micro_cycles=20`）。
* 宏步后 Bofill 更新 Hessian（`hessian_recalc>0` 时每 N 步重建）。

### 3.3 三终止信号

`(a) max_steps`、`(b) RMS 每分量梯度 ≤ grad_tol`（默认 1e-3 Eh/bohr，MAPLE GS 端点
判据）、`(c) 能量连续 `e_rise_steps` 步未刷新运行最小值`（实现形式；严格
`E_k > E_{k-1}` 在极小点附近的 2-循环上永不触发，见报告 §8.5 与本文件 §10 R-3）。

---

## 4. Settings / Result

`landscape_irc_settings`（PLAN §5.3.7 表 + 任务书）：`method`、`target_mode`、
`step_length`(0.10)、`max_steps`（继承，256）、`max_micro_cycles`(20)、
`micro_step_thresh`(1e-3)、`euler_n`(5000)、`loose_cycles`(3)、`dwi_n`(4)、
`mbs_max_k`(15)、`mbs_points`(20)、`mbs_tol`(1e-5)、`e_rise_steps`(3)、
`grad_tol`(1e-3)、`hessian_update`(bofill)、`hessian_recalc`(-1)、`swap`、
`both_directions`、`endpoint_relax`、`rmsd_end`(0.18897)、`etemp`、`write_files`、
`output_prefix`。每个字段带单位注释；凡 PLAN 标 `[待校准]` 的保留标注（§11）。

`landscape_irc_result`：`n_fwd/n_bwd`、`xyz_fwd/xyz_bwd(3,n,n)`、`e_fwd/e_bwd`、
`s_fwd/s_bwd`、`gnorm_fwd/bwd`、`n_eval_fwd/bwd`（每点 E/g 次数）、
`term_fwd/bwd`（三信号）、`reached_min_fwd/bwd`、`rmsd_to_min_fwd/bwd`、
`energy_ts/gnorm_ts`、`etemp`、`step_length`、`n_imag`、`is_saddle`、
`phase_index/phase_value`、`swapped`、`message`。

---

## 5. CLI 接线（grep 证据）

```
$ grep -n "p_run_.* = " src/setparam.f90        # 使用 {1..8,10..15,19,20,21,71,100..104}
   integer, parameter :: p_run_lts    =  19
   integer, parameter :: p_run_lirc   =  20     # ← 新增，p_run_* 命名空间内空闲
   integer, parameter :: p_run_lvib   =  21
$ grep -n "p_ext_.* = " src/setparam.f90        # 使用 {-1,0,1,3,4,5,12..18}
$ grep -n "lirc" src/set_module.f90
   1073:   case('lirc')
   1074:      set%runtyp = p_run_lirc
$ grep -n "p_run_lirc\|lircset" src/prog/main.F90 | head
   154:      type(landscape_irc_settings) :: lircset
   594:  ... p_run_lvib, p_run_lirc)          # 参数文件选择块
   1006:      if (set%runtyp == p_run_lirc) then   # 分派块
   1010:         lircset%engine%acc = set%acc
   1011:         lircset%etemp = set%etemp
   1013:         call run_landscape(env, mol, chk, calc, lircset, lres)
```

`p_run_lirc = 20` 与 `p_ext_*`（最大 18）不冲突；`--lirc*` 全部为精确匹配的新前缀，
不改既有分支。`--help` 已列出全部 `--lirc*`（`src/xhelp.f90`）。

**CLI 选项**：`--lirc`、`--lirc-method`、`--lirc-step`、`--lirc-max-steps`、
`--lirc-level`、`--lirc-swap`、`--lirc-oneway`、`--lirc-target-mode`、
`--lirc-micro-cycles`、`--lirc-micro-thresh`、`--lirc-euler-n`、`--lirc-mbs-tol`、
`--lirc-mbs-max-k`、`--lirc-mbs-points`、`--lirc-dwi-n`、`--lirc-e-rise`、
`--lirc-grad-tol`、`--lirc-recalc`、`--lirc-no-endpoint-relax`、`--lirc-rmsd-end`、
`--lirc-hessian`、`--lirc-hessian-file`、`--lirc-step-hess`、`--lirc-sccacc`、
`--lirc-restart`。

**`res` 回写**（AGENTS.md §6 第 7 条）：`main.F90` 的 `p_run_lirc` 块把
`lres%energy`（= TS 能量，IRC 的参考点）与 `lres%gnorm` 写回 `res`，
`TOTAL ENERGY` 行实测 `-5.387373532405 Eh` = `xtbts.xyz` 的 `energy:`（§7.1）。
**namespace**：四个输出文件名全部经 `get_namespace`（`tasks/irc.f90:627,669,756`）。
**生效 etemp**：任务开头打印 `settings%etemp`，`engine%report` 打印 calculator 回读值，
`result%etemp = engine%effective_etemp()`，`irc.log` 记录（实测 300.000 K）。

---

## 6. 测试覆盖

### 6.1 L1 单元（`landscape-irc`，18 用例，全部通过）

| 用例 | 断言 |
|---|---|
| `mass-weighting-roundtrip` | 加权往返逐位；刚性平移的加权长度 = `d·sqrt(Σm)`（≠ 笛卡尔长度）；梯度加权往返 |
| `arc-length-unit` | LQA 实现的弧长 = 请求步长 |
| `lqa-1d-exact` | 1D 二次势上 LQA `dx = -s`（闭式） |
| `lqa-2d-consistency` | 2D 上与独立闭式（对角化 + 独立 Euler 弧长积分）一致 |
| `mbs-1d-exact` | 常场下 mBS 精确 = `-s` |
| `mbs-vs-lqa` | 单步 Euler 误差 4.8e-2，外推后 5.5e-12（外推有效） |
| `dwi-interpolation` | 样本点处 E/g 复现；样本间能量合理 |
| `phase-determinism` | 两次调用向量逐位相同；最大分量取正且被记录 |
| `direction-rejects-minimum` | 无负本征值 → 失败 |
| `mb-gs-minima` | Müller-Brown 鞍点 → 两个解析极小点（GS） |
| `mb-lqa-minima` | 同上（LQA） |
| `mb-sphere-chord` | 首点 = `s/2`；**每段弧长 ≤ 步长**（球约束）、≥ `s/2`（N 归一化） |
| `mass-metric-effect` | 非单位质量下首点/弧长改变（度量确实起作用） |
| `leps-irc-descent` | LEPS 双向单调下降、H2 键长趋近解析 `r_e` |
| `lqa-step-scan` | 步长 {0.05,0.10,0.20,0.40} 的 MEP 偏离单调增大（§7.3） |
| `termination-max-steps` | 信号 (a) |
| `termination-grad-tol` | 信号 (b) |
| `termination-energy-rise` | 信号 (c)；关掉 (c) → 回退 (a)（成对可证伪） |

### 6.2 CLI 级（6 个 ctest）

| ctest | 断言 |
|---|---|
| `xtb/landscape-irc` | 上述 18 个单元用例 |
| `xtb/landscape-irc-cli` | 先 `--lts` 收敛 TS，再 `--lirc`：exit 0、虚频 1、相位分量、生效 etemp、双向 `reached minimum: T`、四文件、`irc_path.xyz` 有 `TS` 标记、两端点能量不同、`--lirc-step 0.2` 到达 settings、`--lirc-oneway` 只写 forward、**同一输入两次 `irc_forward.xyz` 逐位相同** |
| `xtb/landscape-irc-swap` | `--lirc-swap` 交换两端点能量（且先证明两端点不同，避免空洞） |
| `xtb/landscape-irc-termination` | `--lirc-grad-tol 0` 下双向 `termination: energy_rise` 且 `reached minimum: T`（信号 (c) 的 CLI 客户端） |
| `xtb/landscape-irc-minimum` | 水（0 虚频）→ 非零退出 + `not a transition state` |
| `xtb/landscape-irc-hpc-unimplemented` | `--lirc-method hpc` → 非零 + `hpc is not implemented yet` |
| `xtb/landscape-irc-method-unknown` | `--lirc-method bogus` → 非零 + `Unknown landscape IRC method` |

meson 侧同构镜像：`test/unit/landscape_cli_check.py` 新增 `irc` / `irctermination`
模式（本地用真实二进制手工执行通过），`test/unit/meson.build` 追加 4 个 `test()`
（meson 本机未安装，无法执行——沿用项目既有 R-16 限制）。

---

## 7. 验证实验

### 7.1 端到端 `--lirc --lirc-method gs`（GFN2，HCN/HNC TS）

输入 = `--lts --lts-method prfo` 收敛的 TS（`xtbts.xyz`，E=-5.387373532156 Eh）。

```
$ OMP_NUM_THREADS=1 xtb xtbts.xyz --gfn 2 --lirc --lirc-method gs --norestart --namespace e2e
 landscape: intrinsic reaction coordinate (gs)
 step length:               1.000000E-01 bohr*amu^1/2
 Hessian update:           bofill
 restart policy:           off
 electronic temperature:        300.000 K (frozen for the whole run)
 transition state imaginary modes: 1
 confirmation: first order saddle point
 transition mode index:     1 (eigenvalue -7.695905E-02
 phase component:              0.928068 (cartesian 1 of atom 1)
 wrote e2e.irc_forward.xyz with 43 frames
 wrote e2e.irc_backward.xyz with 41 frames
 wrote e2e.irc_path.xyz with 83 frames
 wrote e2e.irc.log
 termination forward:      gradient
 termination backward:     gradient
 forward points:           42
 backward points:          40
 forward arc length:               4.051234 bohr*amu^1/2
 forward endpoint energy:       -5.472135505135 Eh
 backward arc length:              3.695670 bohr*amu^1/2
 backward endpoint energy:      -5.504066222136 Eh
 forward reached minimum:  T (rmsd     0.009860 bohr)
 backward reached minimum: T (rmsd     0.000016 bohr)
 landscape engine: etemp                   300.000 K
 landscape task terminated: IRC integration completed
          | TOTAL ENERGY               -5.387373532405 Eh   |
normal termination of xtb            # exit 0
```

**四个产出文件**（`ls -la`）：

```
-rw-r--r-- 13275 e2e.irc_backward.xyz
-rw-r--r-- 13923 e2e.irc_forward.xyz
-rw-r--r--  7122 e2e.irc.log
-rw-r--r-- 20163 e2e.irc_path.xyz
```

`e2e.irc_forward.xyz` 首帧（= TS）与末帧：

```
3
 energy: -5.387373532405 xtb: 6.7.1 (2ed7750...) iter: 1
H 0.14152984509873 1.03301636977124 0.00000000000000
C -0.08294717735390 -0.10720801292802 -0.00000000000000
N 1.09741733225517 0.12419164315677 -0.00000000000000
...
 energy: -5.472135505135 xtb: 6.7.1 (2ed7750...) iter: 43
H 1.85609079788511 0.71478155929752 -0.04813480307011
C -0.07879314755279 -0.23515484759879 0.02103796224722
N 0.96915430777396 0.25779268809875 -0.01496887257030
```

端点几何归属：**forward → HNC（H–N–C 线性，E=-5.47214 Eh）**、
**backward → HCN（H–C–N 线性，E=-5.50407 Eh）**（用端点坐标计算 H–C–N 夹角 ≈180°，
H 位于不同侧）。`irc_path.xyz` 83 帧（42+40+1），第 41 帧带 `TS` 标记：

```
frame 41 energy:      -5.387373532405 s:         0.000000 TS
```

`irc.log`（表头 + 尾部）：

```
 landscape intrinsic reaction coordinate: gs
 electronic temperature (frozen):      300.000 K
 step length:  1.000000E-01 bohr*amu^1/2
 imaginary modes of the transition state: 1
 phase component (forward):     0.92806755 (cartesian 1 of atom 1)
 directions exchanged: F

 forward direction
    point          s/(bohr*amu^1/2)        energy/Eh      |g|/(Eh/bohr)   E/g
        1         0.0500000000      -5.387467523539    6.012994E-03      1
        2         0.1494591366      -5.388160932861    1.631161E-02     21
 ...
 forward endpoint energy:       -5.472135505135 Eh
 forward arc length:               4.051234 bohr*amu^1/2
 backward endpoint energy:      -5.504066222136 Eh
 backward arc length:              3.695670 bohr*amu^1/2
 termination forward:  gradient
 termination backward: gradient
 forward reached minimum:  T (rmsd     0.009860 bohr)
 backward reached minimum: T (rmsd     0.000016 bohr)
```

**确定性**：同一输入连续两次运行，`irc_forward.xyz` 逐位相同
（`cmp d1.irc_forward.xyz d2.irc_forward.xyz` 无差异）。

### 7.2 实验 #6（四算法互校）——本轮可实现的两法：GS vs LQA

同一 TS，同一步长 0.10，双向：

| 量 | GS | LQA | 差 |
|---|---|---|---|
| forward 端点能量（HNC） | -5.472135505135 Eh | -5.472154867647 Eh | 1.94e-05 Eh |
| backward 端点能量（HCN） | -5.504066222136 Eh | -5.504065967313 Eh | 2.55e-07 Eh |
| forward 端点几何 RMSD | — | — | **1.93e-02 bohr** |
| backward 端点几何 RMSD | — | — | **1.42e-02 bohr** |

两法端点落在同一极小点、几何一致到 ~2e-2 bohr、能量一致到 ~2e-5 Eh。
**HPC / EulerPC 的互校留待第二阶段**（本轮 `env%error` 明确拒绝）。

### 7.3 LQA 步长扫描（失效模式，实验 #6 的步长侧）

Müller-Brown 面上以 0.02 步长的细路径为参考，测每点对参考路径的最大偏离：

| step (bohr·amu^1/2) | 最大偏离 | 端点距解析极小点 |
|---|---|---|
| 0.05 | 7.9063e-03 | 1.0995 |
| 0.10 | 1.5970e-02 | 1.0995 |
| 0.20 | 1.0446e-01 | 1.0995 |
| 0.40 | 1.0983e-01 | 1.0995 |

偏离随步长单调增大（0.05→0.40 增大约 14 倍），0.40 偏离 > 0.05 的量级；
与报告 04 §1.3「0.10 是 practical upper limit、0.20 轻微困难、0.40 失控」一致。
「端点距极小点」在四种步长下相同（≈1.10）是因为该解析面第三个极小点
（`(-0.050, 0.467)`）并非 `mb_min1`；端点本身是**同一个**极小点（见 §10 R-4）。
测试断言：偏离单调 + 0.40 偏离 > 0.05；四步长均 < 0.15 的极小点判定由
`mb-lqa-minima` 单独断言（实测 < 0.15）。

### 7.4 mBS 收敛（共享 corrector）

同一二次面、同一弧长 0.4：

* 单步 Euler（`base_points=1, max_k=1`）：误差 **4.8006e-02**；
* Richardson 外推（`base_points=1, max_k=10, tol=1e-8`）：误差 **5.4766e-12**，`converged=.true.`。

外推把一阶 Euler 的误差降低约 10 个数量级，符合「简单 Euler 基本步 + Richardson
外推」的设计。

### 7.5 端点判据标定（实验 #7）与三信号实测

| 信号 | 触发条件 | 实测 |
|---|---|---|
| (b) 梯度 | RMS 每分量 ≤ `grad_tol`(1e-3 Eh/bohr) | HCN GS 双向 `termination: gradient`；力阈值可达（M4 实验 #4 已证 σ_g ≪ 阈值） |
| (c) 能量回升 | 连续 `e_rise_steps`(3) 步未刷新运行最小值 | `--lirc-grad-tol 0` 下双向 `termination: energy_rise`，`reached minimum: T` |
| (a) 步预算 | `max_steps` | 单元 `termination-max-steps`；`xtb/landscape-irc-termination` 关掉 (c) 后回退 (a) |

对照 Gaussian `MaxPoints=10` / ORCA `MaxIter=20`：本实现的默认步长 0.10 与 Gaussian
默认一致；终止不依赖硬截断（物理信号优先），`max_steps` 仅作上界（默认继承 256）。
标定结论写入 §11。

### 7.6 失败路径实测

```
$ xtb water.xyz --gfn2 --lirc            → exit 1
  confirmation: minimum (0 imaginary modes) - not a transition state
  landscape task terminated: the input geometry is a minimum ... not a transition state
$ xtb xtbts.xyz --gfn2 --lirc --lirc-method hpc   → exit 1
  -1- landscape_irc: hpc is not implemented yet
$ xtb xtbts.xyz --gfn2 --lirc --lirc-method bogus → exit 1
  -1- prog_main_parseArguments: Unknown landscape IRC method 'bogus'
```

---

## 8. 可证伪注入实验（5/5，全部真实输出 + 等价性论证）

> 铁律：注入前先证明**变异与旧逻辑语义等价**；不等价的变异若变红才支撑结论。
> 下面每条都给出「旧逻辑 / 变异 / 等价性」与真实红/绿输出。全部已还原并确认变绿
> （每次还原后 `landscape-irc` 单元套件 18/18）。

### 8.1 (i) 去掉 GS 球约束投影

* 旧逻辑：`gs.f90:213` 微步后 `q_new = project_sphere(q_new + d, pivot, 0.5*step)`，
  把试探点投回半径 `s/2` 的球面——这是球约束的**唯一执行点**。
* 变异：`q_new = q_new + d`（删去该投影）。
* 等价性：变异**恰好删除约束执行**，不是等价改写（`project_sphere` 在 |q-pivot|≠R
  时改变几何）。因此变红即证明测试测的是球约束本身。
* 真实输出：

```
=== INJECTION (i) : unit suite ===
       ... mb-sphere-chord [FAILED]
  Message: a Gonzalez-Schlegel chord exceeded the sphere constraint
   chord min   0.1000000000 max   0.1664598246 step   0.1000000000
=== CLI === 1 tests failed out of 7 (xtb/landscape-irc)
=== restored: unit passed=18 ===
```

（真实弦长 0.16646 > 步长 0.10；未注入时 min/max = 0.09639/0.10000。）

### 8.2 (ii) `N = (g^T G g)^{-1/2}` 指数 −1/2 → +1/2

* 旧逻辑：`gs.f90:174-175` pivot/首猜用 `g^q/|g^q|`（即 `N = |g^q|^{-1}`，GS Eq.9）。
* 变异：改为 `|g^q|·g^q`（指数取 `+1/2`）。
* 等价性：pivot 步长由 `s/2` 变为 `(s/2)|g^q|²`，**不是**等价改写；对 HCN
  `|g^q|~1e-2`，pivot 塌缩到当前点。
* 真实输出：

```
=== INJECTION (ii) : unit suite ===
       ... mb-sphere-chord [FAILED]
  Message: a Gonzalez-Schlegel step is much shorter than the pivot step
   chord min   0.0002593048 max   0.0003638376 step   0.1000000000
       ... mb-gs-minima [FAILED]           (附带：路径不再到达极小点)
       ... termination-energy-rise [FAILED]
=== CLI === 3 tests failed out of 7
=== restored: unit passed=18 ===
```

「步长测试」（`mb-sphere-chord` 的 `smin ≥ s/2` 断言）按预期变红。

### 8.3 (iii) 质量加权度量换成单位矩阵

* 旧逻辑：`corrector.f90:215` `sqrt_mass = sqrt(mass)`——`landscape_irc_sqrt_mass`
  是施加 amu 度量的**唯一位置**。
* 变异：`sqrt_mass = mass/mass`（形状保持的恒等 1）。
* 等价性：所有加权变换都经它；返回 1 即度量 = 单位矩阵，正是「换成单位矩阵」。
* 真实输出：

```
=== INJECTION (iii) : unit suite ===
       ... mass-weighting-roundtrip [FAILED]
  Message: the mass weighted length of a rigid translation is wrong
       ... mass-metric-effect [FAILED]
  Message: the mass metric did not change the first IRC point (identity metric?)
=== CLI === 1 tests failed out of 7
=== restored: unit passed=18 ===
```

单位往返测试与**路径**测试（`mass-metric-effect`，用非单位质量）同时变红。
（注意：纯单位质量的解析路径无法察觉度量变化——已用非单位质量用例补上。）

### 8.4 (iv) 去掉相位约定

* 旧逻辑：`corrector.f90:351` `call landscape_transition_mode_set_phase(mode)`——
  选择过渡向量后定向为最大绝对分量取正，并记录 `phase_index/phase_value`。
* 变异：删去该调用。
* 等价性：删除定向与记录，不是等价改写。
* 真实输出：

```
=== INJECTION (iv) : unit suite ===
       ... phase-determinism [FAILED]
  Message: the phase convention did not make the largest component positive
=== CLI === 2 tests failed out of 7 (xtb/landscape-irc, xtb/landscape-irc-cli)
=== restored: unit passed=18 ===
```

**覆盖缺口（如实记录）**：任务书要求「确定性测试必须变红」。实测在同一构建内，
去掉相位约定后**同一输入两次运行仍逐位相同**：

```
$ xtb xtbts.xyz --gfn 2 --lirc --lirc-method gs ... --namespace i4a
$ xtb xtbts.xyz --gfn 2 --lirc --lirc-method gs ... --namespace i4b
DETERMINISM: bitwise IDENTICAL even without the phase convention (expected gap)
```

原因：LAPACK 对同一输入给出**同一个**特征向量符号，逐位可复现性不依赖相位约定；
相位约定保证的是「方向与线性代数库的符号约定无关」的**规范化**（跨构建/跨库可复现）。
因此：
* **被覆盖**：相位规范化本身（`phase-determinism` 的 `phase_value>0`、
  `phase_index==maxloc`、CLI 的相位分量断言）→ 注入 (iv) 变红。
* **未被覆盖**：逐位确定性对该注入不敏感 → 记为缺口，不假装变红。
  若要覆盖「跨库符号无关」，需要第二个线性代数后端或人为翻转 `mctc_syev` 的符号，
  本轮未做。

### 8.5 (v) 关掉终止信号 (c)

* 旧逻辑：`gs.f90:252` / `lqa.f90:219` `if (nrise >= max(1, settings%e_rise_steps))`
  触发 `p_landscape_irc_term_energy_rise`。
* 变异：`if (.false.) then`（分支整体删除）。
* 等价性：删除终止分支，不是等价改写。
* 真实输出：

```
=== INJECTION (v) : unit suite ===
       ... termination-energy-rise [FAILED]
  Message: the energy rise did not report signal (c)
   energy-rise term 1 n 200 last e  -1.283834E-01   (term=1 = max_steps)
=== CLI === 2 tests failed out of 7
   135 - xtb/landscape-irc-termination (Failed)
=== restored: unit passed=18 ===
```

`xtb/landscape-irc-termination`（端点归属 + 信号 (c) 的 CLI 客户端）变红。
`xtb/landscape-irc-cli` 保持绿，原因是默认 `grad_tol=1e-3` 下 HCN 路径先由信号 (b)
终止——这正是新增 `--lirc-grad-tol 0` 用例的原因（已在 §6.2 说明）。

---

## 9. 构建 / 测试数字

```
$ cmake --build /tmp/xtb-land/build -j          # touch 全部 IRC 文件后
（无 warning / error）

$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape
100% tests passed, 0 tests failed out of 77      # M5 结束 70 → +7

$ ... -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
100% tests passed, 0 tests failed out of 12

$ grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d
（空）

$ ctest -N -R landscape | tail -1
Total Tests: 77
```

---

## 10. 偏离、缺口与残余风险

**R-1（性能，MEDIUM）GS 每点 E/g 远高于 PLAN 的 3–5。**
实测 GFN2 HCN/HNC 路径：forward 平均 **16.93**、backward **20.25**（`irc.log` 的
`E/g` 列与 `mean energy/gradient evaluations per point`）；LQA 恒为 **1.00**。
根因（已实测定位）：切空间 Newton 步（`|d|~1.8–2.4 bohr·amu^1/2`）远大于球半径
`s/2=0.05`，微步被 trust-region 限幅钉在球面半径上，`|d|≤micro_step_thresh(1e-3)`
的收敛判据在极小点附近的 2-循环上永不满足，于是每个宏步耗尽 20 次微循环。
路径本身**正确**（端点/几何/能量与 LQA 一致，§7.2）。已尝试且**未**采纳的修法
（会改变已复核行为，留给第二阶段）：切空间 Lagrange 精确步、微循环内不更新
Hessian、以切向梯度为收敛判据。建议第二阶段在实现 HPC/EulerPC 时一并把 GS 微循环
改为**等式约束 Lagrange 步**（MAPLE 的形式），可望回到 3–5。

**R-2（覆盖缺口，LOW）相位注入下逐位确定性不变红**（§8.4），如实记录，不假装。

**R-3（语义偏离，LOW）终止信号 (c) 的严格定义。**
PLAN §6.5 写「能量连续回升 `e_rise_steps` 步」；实现为「连续 `e_rise_steps` 步未刷新
**运行最小值**」。严格 `E_k > E_{k-1}` 在 GS 球约束与 LQA 固定弧长于极小点附近的
2-循环上交替、永不触发（已在 Müller-Brown 上实测）。已在模块注释与 settings 注释
写明该实现形式。

**R-4（测试语义，INFO）`lqa-step-scan` 的「端点距极小点」列不区分步长。**
该 Müller-Brown 参数集的 `(-0.822,0.624)` 鞍点连接的是 `mb_min1(-0.558,1.442)` 与
**第三个**极小点 `(-0.050,0.467)`，不是第二井 `(0.623,0.028)`（标准 MB 面实有 5 个
驻点，实测）。端点判定用例已改用正确的极小点；`lqa-step-scan` 的「距 `mb_min1`」
列仅作诊断打印，真正的判定是「对参考路径的最大偏离」单调增大。

**R-5（未实现，按范围）HPC / EulerPC**：`--lirc-method hpc|eulerpc` →
`env%error("<method> is not implemented yet")`，exit 1。共享 corrector 的 DWI/mBS
已实现并单元测试（§7.4），供第二阶段直接使用。

**R-6（资源，INFO）`max_steps` 默认继承基类 256**（PLAN §5.3.7 写 50）。
正常运行由物理信号 (b)/(c) 提前终止（HCN 实测 42/40 点）；`--lirc-max-steps` 可改。
已在 settings 注释写明该偏离。

**R-7（构建，既有）meson 本机不可执行**（R-16），镜像按既有约定手工同步并通过
`landscape_cli_check.py` 手工执行验证。

---

## 11. `[待校准]` 标注处置

| 字段 | PLAN 标注 | 处置 |
|---|---|---|
| `micro_step_thresh`(1e-3) | `[待校准]` | **保留**（MAPLE 同值；本轮未做独立标定） |
| `max_micro_cycles`(20) | `[待校准]` | **保留**（同上；且 R-1 表明该值与收敛判据需一并重定） |
| `e_rise_steps`(3) | `[待校准]` | **保留**（实测可用，但与严格 PLAN 语义有偏离，见 R-3） |
| `grad_tol`(1e-3) | `[待校准]` | **保留**（= MAPLE GS `f_rms_th` 5e-4 Eh/Å 的换算值 9.45e-4 取整；信号 (b) 可达性由 M4 实验 #4 支撑） |
| `step_length`(0.10) | — | 已由 §7.3 步长扫描与 Gaussian/ORCA 对照确认 |
| `mbs_tol`(1e-5) / HPC 的 1e-6 | — | 两者均可调；默认 1e-5（MAPLE），`--lirc-mbs-tol` 暴露 1e-6 |
| `rmsd_end`(0.18897) | — | MAPLE `rmsd_end`=0.1 Å，保留 |

---

## 12. 本轮改动的既有文件

```
 src/landscape/CMakeLists.txt       |   4 +
 src/landscape/landscape_driver.f90 |  52 +-
 src/landscape/meson.build          |   4 +
 src/landscape/types/results.f90    | 164 +
 src/landscape/types/settings.f90   | 206 +
 src/prog/main.F90                  | 372 +-
 src/set_module.f90                 |   3 +
 src/setparam.f90                   |   1 +
 src/xhelp.f90                      |  83 +
 test/unit/CMakeLists.txt           | 324 +
 test/unit/landscape_cli_check.py   | 102 +
 test/unit/main.f90                 |   2 +
 test/unit/meson.build              |  28 +
 13 files changed, 1340 insertions(+), 5 deletions(-)
新增（未跟踪）：src/landscape/irc/、src/landscape/tasks/irc.f90、test/unit/test_landscape_irc.f90
```

`src/type`、`src/xtb`、`src/mctc`、`src/param`、`src/io`、`src/disp`、`src/coulomb`
核心层未改动。未提交 git（父会话统一提交）。
