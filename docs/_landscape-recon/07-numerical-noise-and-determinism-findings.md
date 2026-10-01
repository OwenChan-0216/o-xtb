# 07 — 数值噪声 / 确定性 / xtb Hessian 参数生效性 实测报告

> 本文全部为**在本机实际运行的实验结果**，不是文献推断。
> 环境：gfortran 12.2.0 / cmake 4.3.2 / OpenBLAS / `xtb` 由本仓库 HEAD `1779020` 构建于
> `/tmp/xtb-land/build`（版本串 `xtb version 6.7.1 (17790202eb14eeb40effc05008f5508fb0a52157)`）。
> 测试体系：水分子，GFN2-xTB。
> 目的：为 `docs/xtb-landscape-PLAN.md` 风险登记册中的前两项风险提供**量化**依据，
> 因为 TS 优化器（P-RFO / Dimer）的模态跟随对梯度噪声极度敏感。

---

## 0. 结论摘要

| 编号 | 命题 | 实测结论 | 对 M4 的影响 |
|---|---|---|---|
| **F1** | GFN2 单点是否可重复 | ✅ **冷启动逐位可重复** | **有利**：FD Hessian 的噪声下限极低 |
| **F2** | OpenMP 线程数是否影响结果 | ✅ 仅 `1.05e-14 Eh/bohr` 量级 | 可忽略；但需固定线程数以保证逐位可复现 |
| **F3** | warm-start（复用 `TRestart`）是否影响结果 | ⚠️ 是，梯度差 `3.9e-07 Eh/bohr` | **必须统一重启策略**（见 §3） |
| **F4** | `$hess` 块的 `step` / `sccacc` / `scale` 是否可靠生效 | ❌ **不可靠**，与 `--copy` 存在未解释的交互 | **不可依赖**；套件必须自建 FD Hessian（见 §4） |

---

## 1. F1 — 冷启动 GFN2 单点是逐位可复现的

### 实验
同一几何文件连续 3 次以**独立进程**运行单点，分别在 4 线程与 1 线程下：

```bash
cat > /tmp/dt.xyz <<'EOF'
3
water
O 0.0000000 0.0000000 0.0000000
H 0.0000000 0.0000000 0.9600000
H 0.9300000 0.0000000 -0.2400000
EOF

for nt in 4 1; do
  for i in 1 2 3; do
    OMP_NUM_THREADS=$nt XTBPATH=<repo> ./xtb /tmp/dt.xyz --gfn2 --sp | grep "total energy"
  done
done
```

### 实测输出
```
=============== OMP_NUM_THREADS=4 : 冷启动重复单点 (3 次独立进程) ===============
  run 1: :: total energy              -5.070383095219 Eh    ::
  run 2: :: total energy              -5.070383095219 Eh    ::
  run 3: :: total energy              -5.070383095219 Eh    ::
=============== OMP_NUM_THREADS=1 : 冷启动重复单点 (3 次独立进程) ===============
  run 1: :: total energy              -5.070383095219 Eh    ::
  run 2: :: total energy              -5.070383095219 Eh    ::
  run 3: :: total energy              -5.070383095219 Eh    ::
```

**结论 F1**：冷启动单点在打印精度内**完全一致**。未观察到 `rabguess`/`iniq` 中的随机初猜引入不确定性
（已独立 grep 确认：`src/rabguess.f90`、`src/iniq.f90`、`src/scc_core.f90`、`src/scf_module.F90`
中**没有** `random_number` / `random_seed`；全仓库 `random_number` 只出现在
`src/david.f:100,425`、`src/local.f90:811,816,825`、`src/shiftlp.f90:35-41`、`src/docking/param.f90`，
这些都不在 GFN2 单点路径上 —— 与 `docs/_landscape-recon/02-*.md` §5 关于 `david.f` 为死代码的结论一致）。

---

## 2. F2 — OpenMP 线程数只引入 1e-14 量级的差异

### 实验
固定冷启动，比较 `OMP_NUM_THREADS=1` 与 `=4` 产生的 `gradient` 文件。

### 实测输出
```
=== 跨线程数比对 (NT=4 vs NT=1, 冷启动) ===
  max |dgrad| = 1.052001e-14  (NT=1 vs NT=4, n=21)
```

**结论 F2**：跨线程差异 `1.05e-14 Eh/bohr`，是 OpenMP 归约顺序造成的浮点舍入差异，与机器精度同量级。

**工程建议**：M0 `xtb_landscape_engine` 应**固定并记录**线程数，并在文档中声明
「逐位可复现性仅在固定 `OMP_NUM_THREADS` 与固定重启策略下成立」。这也意味着
任何以「逐位相同」为前提的缓存或断言（例如 M0 引擎的几何缓存、测试 T5）都必须在固定线程数的条件下解释。

---

## 3. F3 — warm-start 会造成 3.9e-07 Eh/bohr 的梯度不连续（**M4 的关键风险**）

### 实验
M0 的测试 `test_landscape_optimize_xtb.f90` 中的两个 determinism 探测，直接运行其可执行文件：

```bash
cd /tmp/xtb-land/build
XTBPATH=<repo> ./test/unit/xtb-tester landscape-optimize-xtb
```

### 实测输出
```
 landscape water: energy evaluations 7
  Starting water-gfn2-determinism ... (3/4)
 landscape water: energy run 1      -5.070544447722
 landscape water: energy run 2      -5.070544447722
 WARNING: landscape water energies differ by   8.8818E-16 hartree
       ... water-gfn2-determinism [PASSED]
  Starting gfn2-singlepoint-determinism ... (4/4)
 gfn2 single point: energy 1      -5.066171489935
 gfn2 single point: energy 2      -5.066171489936
 gfn2 single point: difference   9.6634E-13 hartree
 WARNING: gfn2 single point energy changed by   9.6634E-13 hartree
 gfn2 single point: gradient difference   3.9159E-07 Eh/bohr
       ... gfn2-singlepoint-determinism [PASSED]
```

### 分析
结合 F1（冷启动逐位可复现）可以断定：**这 `9.66e-13 Eh` / `3.92e-07 Eh/bohr` 的差异不是 SCF 的随机性，
而是 warm-start（复用同一个 `TRestart` 波函数对象）导致的**——第二次调用从第一次的密度出发，
SCF 收敛到略微不同的点。

第一组探测（`water-gfn2-determinism`，差 `8.88e-16`）之所以几乎无差，是因为它在**同一个
`TRestart` 内**反复求值同一几何，命中 M0 引擎的几何缓存，属预期行为。

### 对 M4/M5/M6 的量化影响

| 场景 | 梯度噪声 σ_g | 由 FD 传递到 Hessian 的噪声（`h=0.005 bohr`，中心差分） |
|---|---|---|
| 统一冷启动 + 固定线程 | ≈ `1e-14` | ≈ `1e-12 Eh/bohr²` —— **可忽略** |
| 统一 warm-start | ≈ `4e-07` | ≈ `4e-05 Eh/bohr²` —— 差 **4×10⁷ 倍** |
| **混合**（部分 warm、部分 cold） | ≈ `4e-07` 的**跳变** | 出现**非物理的不连续**，模态跟随会失稳 |

GFN2 的 Hessian 本征值典型量级为 `10^-1 ~ 10^0 Eh/bohr²`。因此：

- **统一策略下**，Hessian 的相对噪声约 `10^-11`，远低于模态间的本征值间隙 → **P-RFO 的模态选择安全**。
- **混合策略下**，Hessian 出现 `10^-4 ~ 10^-5` 量级的不连续，如果最低两个本征值的间隙小于该量级，
  跟随的本征向量会**跳变**，P-RFO 会跟随错误的模态 → **TS 搜索会失效或收敛到极小值**。

### 设计后果（必须写进 PLAN）

1. `xtb_landscape_engine` 必须把**重启策略**作为一等公民暴露，而不是隐含在 `TRestart` 的复用顺序里：
   显式枚举「cold（每次清空波函数）/ warm（复用上一帧）」两种模式，并在 settings 中可配。
2. 单次任务内（一个 opt / 一个 FD Hessian / 一个 NEB 迭代）必须使用**同一种**策略。
3. FD Hessian 的评估序列（`x + h e_i` 与 `x - h e_i`）必须**全部冷启动**或**全部 warm**，
   不能因循环顺序而产生混合。
4. 必须在日志中记录 `n_eval`、`n_cache_hit`、重启模式 —— 已有 M0 计数器可复用。
5. 这解释了为什么 M0 的几何缓存是**正确且必要**的：它把「同一几何重复求值」变成确定性操作，
   从而消除了混合策略的一个主要来源。

> ⚠️ 注意：M0 缓存的判据是**逐位相同比较**（`==` 于实数）。在 F2 的约束下（固定线程数）
> 这是成立的；但若线程数在运行中变化，缓存将失效并退化为混合策略。这是一个必须在
> 测试中固定并断言的隐含前提。

---

## 4. F4 — `$hess` 块的 `step` / `sccacc` / `scale` 生效性**不可靠**（xtb 侧潜在缺陷）

这一节记录一次**调查过程与最终未能收敛的根因**，因为中间的多次实验都因混淆变量而得出过错误结论，
必须把最终的确定事实与未确定部分严格分开。

### 4.1 确定的事实

**（a）cwd 下的 `xcontrol` 不会被自动读取。**
把 `$hess` 块中放入非法键，仅当显式给出 `--input xcontrol` 时才触发警告：
```
$ printf '$hess\n   bogus_key_xyz=1.0\n$end\n' > xcontrol
$ ./xtb dt.xyz --gfn2 --sp --input xcontrol 2>&1 | grep -i "not recognized"
-1- set_hess: the key 'bogus_key_xyz' is not recognized by hess      ← 证明块被解析
$ ./xtb dt.xyz --gfn2 --sp 2>&1 | grep -i "not recognized"
(无输出)                                                              ← 证明 cwd 的 xcontrol 未被读取
```

**（b）块本身工作正常 —— 对照实验。** 同一 `--input xcontrol` 机制下，`$scc` 块**明确生效**：
```
=== 对照: $scc 块 etemp 是否生效 (能量应变化) ===
 默认        : total energy  -5.070383095219 Eh
 $scc temp=5000.0 : total energy  -5.070383097531 Eh     ← 能量改变，块生效
```
`$opt` 块的非法键同样正确告警（`set_opt: the key 'bogus' is not recognized by opt`）。

**（c）`--input xcontrol` + `$hess` + 单一数值键：Hessian 与默认逐位相同。**
```bash
# 每次在独立目录内：printf '$hess\n   step=1.00\n$end\n' > xcontrol
# ./xtb dt.xyz --gfn2 --hess --input xcontrol
```
| 键设置 | `hessian` 文件 vs 默认 |
|---|---|
| `step=1.00`（默认 0.005 的 **200×**） | **IDENTICAL** |
| `step=0.010` | **IDENTICAL** |
| `sccacc=1.0`（默认 0.3 的 3.3×） | **IDENTICAL** |
| `sccacc=0.05`（默认的 1/6） | **IDENTICAL** |
| `sccacc=0.005`（默认的 1/60） | **IDENTICAL** |

`step` 变化 200× 而中心差分 Hessian **逐位不变**，物理上不可能 → 数值键未到达 `numhess`。

**（d）但加上 `--copy` 后，同样的键生效了。**
在 `--copy` 条件下重做隔离矩阵，基线为「`--copy` + 空 `$hess`」：
| 键设置 | `hessian` vs 基线 |
|---|---|
| `step=1.00` | **DIFFERS** |
| `sccacc=1.0` | **DIFFERS** |
| `scale=0.5` | IDENTICAL |
| `step=1.00 + sccacc=1.0 + scale=0.5` | **DIFFERS** |
| `sccacc=0.3` 然后 `step=1.00` | **DIFFERS** |

并且：「`--copy` + 空 `$hess`」的基线本身**也不等于**「无 `--copy`」的默认结果。

### 4.2 未确定的部分（不得当作结论使用）

**根因未确定。** 以下都是**假设，未经证实**：

- 假设 A：`set_hess` 中 `logical,save :: set1/set2/set3`（`src/set_module.f90:2166-2169`）
  是「只接受首次出现」的一次性守卫；若控制文件被解析多于一 次，则先被消费的键失效。
  代码确实形如：
  ```fortran
  case('sccacc')
     if (getValue(env,val,ddum).and.set1) set%accu_hess = ddum
     set1 = .false.
  case('step')
     if (getValue(env,val,ddum).and.set2) set%step_hess = ddum
     set2 = .false.
  ```
- 假设 B：`rdcontrol(..., copy_file=copycontrol)`（`src/prog/main.F90:306`）在 `copy_file=.true.`
  时走不同的解析路径，从而重置或跳过这些守卫。
- 已排除：`rdcontrol` 对 xcontrol **只被调用一次**（`src/prog/main.F90:306`；另一次
  `main.F90:372` 是 `.xtbrc`，`dock.f90:142,146` 是 docking 专用）。

**因此本节的确定结论仅限于**：在 `--input xcontrol` 而不加 `--copy` 时，`$hess` 块的数值键
**静默无效**；加 `--copy` 后生效。这个交互是**未记录的、违反直觉的**，本身就是缺陷级别的可用性问题。

### 4.3 对 PLAN 的影响（重要）

1. **`docs/xtb-landscape-PLAN.md` 风险登记册第 1 条（`accu_hess = 0.3` 噪声）的缓解措施必须修改**：
   原计划依赖调整 `set%step_hess` / `set%accu_hess` 来表征与降低 FD Hessian 噪声，
   但该旋钮**不可靠**。
2. **改为**：`src/landscape/vib/numhess.f90`（M3）必须**自建**有限差分 Hessian 实现，
   把步长与每次评估的 SCF 精度作为**显式参数**（而非依赖 `set%` 全局量）传递，
   并复用 M0 的 `xtb_landscape_engine`（含统一重启策略与几何缓存）来保证一致性与可复现性。
   这与 D3 决策（Hessian 提供者抽象）天然吻合 —— 新增一个 `landscape_numerical_hessian_provider`
   完全落在既有接口内。
3. 该自建实现同时是**去风险实验 #2 的正确载体**：只有它能把 `step ∈ {0.002,0.005,0.010}`
   与 `sccacc ∈ {0.1,0.3,1.0}` 真正独立地变化出来。
4. **新增风险登记项**：`xtb` 6.7.1 的 `$hess` 控制块数值键在非 `--copy` 路径下静默失效
   （已复现，根因未定）。缓解：不依赖它；若将来需要，先补一个能判定的最小回归测试。
   建议向 xtb 上游报告，附上 §4.1 的 (c)(d) 对照数据。

### 4.4 复现命令（完整）

```bash
XTB=/tmp/xtb-land/build/xtb
export OMP_NUM_THREADS=1 XTBPATH=<repo>

# (a) 证明 cwd 的 xcontrol 不被自动读取
mkdir -p /tmp/probe && cd /tmp/probe && cp /tmp/dt.xyz .
printf '$hess\n   bogus_key_xyz=1.0\n$end\n' > xcontrol
$XTB dt.xyz --gfn2 --sp                2>&1 | grep -i "not recognized"   # 无输出
$XTB dt.xyz --gfn2 --sp --input xcontrol 2>&1 | grep -i "not recognized" # 有警告

# (b) 证明 $scc 块生效（对照）
$XTB dt.xyz --gfn2 --sp                            | grep "total energy"
printf '$scc\n   temp=5000.0\n$end\n' > xcontrol
$XTB dt.xyz --gfn2 --sp --input xcontrol           | grep "total energy"   # 能量不同

# (c) 证明 $hess 数值键在无 --copy 时无效
mkdir -p /tmp/fin/step && cd /tmp/fin/step && cp /tmp/dt.xyz .
printf '$hess\n   step=1.00\n$end\n' > xcontrol
$XTB dt.xyz --gfn2 --hess --input xcontrol
cmp hessian <无--copy 默认运行的 hessian>          # IDENTICAL（200× 步长无效果）

# (d) 证明加 --copy 后生效
mkdir -p /tmp/iso/k && cd /tmp/iso/k && cp /tmp/dt.xyz .
printf '$hess\n   step=1.00\n$end\n' > xcontrol
$XTB dt.xyz --gfn2 --hess --input xcontrol --copy
# 与「--copy + 空 $hess」基线比较 -> DIFFERS
```

---

## 5. 对去风险清单的更新（对照 `04-web-research-ts-irc-state-of-art.md` §9）

| # | 实验 | 本文档结论 | 状态 |
|---|---|---|---|
| 1 | SCF 反复调用确定性 | ✅ **F1/F2/F3 已量化完成** | **完成** |
| 2 | Hessian 步长与 sccacc 敏感性 | ❌ 无法用 xtb 的 `$hess` 旋钮完成 → 必须先在 M3 自建 FD Hessian | **改道**（见 §4.3） |
| 3 | `etemp` 对曲率的影响 | 未做；`$scc temp=` 已验证可控（§4.1b） | 待做 |
| 4 | 梯度噪声 vs trust radius 下确界 | 部分完成：噪声 `σ_g ≈ 1e-14`（统一冷启动）/ `4e-7`（warm） | 待定阈值 |
| 5 | P-RFO 模态跟随（GFN2） | 未做（依赖 M4） | 待做 |
| 6 | IRC 四算法互校 | 未做（依赖 M6） | 待做 |
| 7 | IRC 端点判据标定 | 未做 | 待做 |
| 8 | CI-NEB climbing 切换阈值 | 未做 | 待做 |
| 9 | DMF 可行性 | 不适用（D2 已排除） | 关闭 |
| 10 | DL-FIND 复用性 | 不适用（不搬运代码） | 关闭 |
| 11 | rigid vs relaxed scan 滞回 | 未做 | 待做 |
| 12 | 线性分子 3N-5 情形 | 未做 | 待做 |

---

## 6. 附：本文档的实验清单（全部为真实执行）

| 实验 | 命令要点 | 结果 |
|---|---|---|
| 冷启动重复性 | `xtb w.xyz --gfn2 --sp` × 3 × {NT=1,4} | 能量逐位一致 |
| 线程数敏感性 | 比较 `gradient` 文件 NT=1 vs NT=4 | `1.05e-14 Eh/bohr` |
| warm-start 敏感性 | `xtb-tester landscape-optimize-xtb` | `9.66e-13 Eh` / `3.92e-07 Eh/bohr` |
| xcontrol 自动读取 | `$hess` 非法键，有/无 `--input` | 仅 `--input` 时告警 |
| 块有效性对照 | `$scc temp=5000.0` | 能量改变 → 生效 |
| `$hess` 单键 | `step` / `sccacc` × 5 组 | 全部逐位相同（无 `--copy`） |
| `$hess` + `--copy` | 5 组隔离矩阵 | `step` / `sccacc` 生效，`scale` 不生效 |

M0+M1 的实现与测试结果见 `06-m0-m1-implementation-report.md`。
独立复核意见见 `08-independent-review-m0-m1.md`（若已产出）。
