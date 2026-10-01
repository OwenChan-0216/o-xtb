# xtb OpenMP 扩展性审计 — “12 核后效率不再提升”说法核查报告

> 日期:2026-10-01 · 版本:xtb 6.7.1 (be9b701, 本仓库 checkout,含 landscape M0/M1 增补)
> 方法:3 路并行 subagent(线程控制链审计 / OpenMP 区清单 / 实测基准)+ 说法溯源(网络考古)
> 原始 subagent 输出:`~/.pi/agent/sessions/.../subagent-artifacts/{225f6766…,8e8b064d…,dcc72f39…}_*.md`

---

## 0. 结论(三层判定)

| 层面 | 判定 | 一句话 |
|---|---|---|
| **A. 代码中是否有“12 核”硬上限** | **FALSE** | 全树不存在任何线程数钳制:`-P N` 的 N 不经验证直接传给 `omp_set_num_threads`(`src/prog/main.F90:1481`),无 min/max、无任何与常数比较的守卫;穷举数字字面量 12/16/24/32/64 只命中 `schedule(dynamic,32/16)` 等调度块大小(调度粒度,不是核数上限)。 |
| **B. “加核不再有提升”是否有代码层结构性表现** | **TRUE(但拐点不是常数)** | 扩展性饱和/反转由四条结构性原因决定(§3),其拐点取决于**体系规模 × BLAS 后端 × 内存带宽**,而不是一个固定数字。小体系(≈100 原子)拐点甚至是 **1 核**(T2 起负扩展,本报告实测复现);大体系(≥1000 原子,MKL 构建)可扩展到 ~25 核仍有收益(CP2K 邮件列表用户实测)。 |
| **C. “12”这个数字的出处** | **民间杂音,无官方出处** | 官方文档(man page、xtb-docs)、论文均无“12 核上限”表述。最接近的字面"12"是 GitHub Discussion #1156 中用户笔记本 i7-13650HX 的“6 性能核 × 2 = 12 P-threads”;“后无提升”的实底是 #401(OpenBLAS 反扩展)、#613(-P1 快于 -P16)等小体系反扩展案例与大体系平台期的混合记忆。 |

**给用户的直接回答:代码里没有“12 核闸门”。** 流言对应的是真实存在但**可变**的现象:xtb 的 OpenMP 扩展在远低于 12 核的地方就开始失效(小体系从 2 核起就倒退),原因在代码结构里可以逐行指认(§3),但拐点位置随体系大小和构建后端漂移,“12”只是某个观测者在自己体系尺寸上的截图。

---

## 1. 线程控制链路(静态审计,subagent lane-1)

```
CLI  -P/--parallel <N>  (man/xtb.1.adoc:318, 文档写 "number of parallel processes" — 实为线程数)
  └► src/prog/main.F90:1477-1486  args%nextArg(sec) → getValue(env, sec, idum)
       └► src/readin.f90:165-182  getIntValue = 裸格式化 read(val,*) —— 无任何区间验证
            └► omp_set_num_threads(idum)      (main.F90:1481)
            └► mkl_set_num_threads(idum)      (main.F90:1483, #ifdef WITH_MKL)
```

要点:

1. **`-P` 无钳制**:main.F90:1480-1481 把 `idum` 原样传入,`-P 0`、`-P -1`、`-P 999999` 都直接到达 OpenMP 运行时(行为由 libgomp 决定:非法值告警并沿用旧值——这本身可能就是某些“设了没反应”报告的来源)。
2. **`mkl_set_num_threads` 是死代码**:`WITH_MKL` 预处理器宏在全树**只出现在 main.F90:1482 这一处引用处**,CMake/meson 均不定义它(meson.build:171-173 只定义 `WITH_TBLITE`/`WITH_CPCMX`;CMakeLists.txt 无任何 MKL find 模块)。⇒ 即便官方构建用 MKL,MKL 线程数也只能靠 `MKL_NUM_THREADS` 环境变量或 MKL 对 `OMP_NUM_THREADS` 的默认尊重,`-P` 无法直接拨动 BLAS 线程。
3. **代码自身不读任何线程类环境变量**:`src/type/environment.f90:137-145` 只读 HOSTNAME/HOME/PATH/XTBHOME/XTBPATH。`OMP_NUM_THREADS`/`MKL_NUM_THREADS`/`OPENBLAS_NUM_THREADS`/`OMP_DYNAMIC`/`OMP_SCHEDULE` 全部由链接的运行时隐式生效。`src/xhelp.f90:441-442` 的 help 文本(`export MKL_NUM_THREADS=<NCORE>`、`export OMP_NUM_THREADS=<NCORE>,1`)印证了这一分工。
4. **从未调用** `omp_set_nested`/`omp_set_dynamic`/`omp_set_max_active_levels`(全树零命中)⇒ 嵌套行为完全交给环境。
5. 数字字面量扫描(12/16/24/32/64 × omp/thread/nproc/parallel 关键词)全部命中为**调度块大小**:`schedule(dynamic,32)`(aespot.F90:323,621;scc_core.f90:1226,1275;xtb/hamiltonian.F90:220,445,660;generate_wsc.f90:72;coulomb/klopmanohno.F90:525;disp/dftd4.F90:692,1109,1882,2063,2125)、`schedule(dynamic,16)`(gfnff/gfnff_ini2.F90:816,884,1371)、`$acc vector_length(32)`(intgrad.f90:1335;xtb/hamiltonian_gpu.f90:277)。**没有任何一处把线程数封顶。**
6. 反向证据(pseudodiag.f90:101-103):`nproc = omp_get_max_threads(); blocksize = 6 * nproc` —— 工作块尺寸**随线程数增长**,这是“随核扩展”方向的设计,与“封顶”相反。
7. 红鲱鱼排查:main.F90:184 的 `ncore` 是核电荷函数,与核数无关;各处 `nproc` 局部变量均为工作分区计数。

---

## 2. 实测(本机,subagent lane-2)

**环境**:Intel Ultra 7 155H,cgroup 限制为 **8 逻辑 CPU**(4 物理核 × SMT2),16GB RAM。
**二进制**:`/tmp/xtb-land/build/xtb`(gfortran + **libgomp**,BLAS = **系统 OpenBLAS**,ldd 确认无 MKL)—— 正是 GitHub #401 中表现病态的后端组合。
**工作负载**:taxol,113 原子(C₄₇H₅₁NO₁₄),GFN2 冷启动单点,12 次 SCF 迭代,`OMP_DYNAMIC=FALSE`,每点 3 次取中位数。

| 线程 | wall (s) | user (s) | sys (s) | 加速比 | 并行效率 |
|---|---|---|---|---|---|
| 1 | 0.358 | 0.30 | 0.02 | 1.000 | 100% |
| 2 | 0.565 | 0.75 | 0.35 | **0.63×** | 32% |
| 3 | 0.926 | 1.63 | 0.86 | 0.39× | 13% |
| 4 | 2.245 | 5.00 | 2.53 | **0.16×** | 4% |
| 6 | 4.610 | 11.18 | 7.03 | 0.08× | 1.3% |
| 8 | 2.483 | 13.54 | 5.66 | 0.14× | 1.8% |
| 8(`-P 8` 路径) | 5.601 | 17.04 | 10.84 | 0.06× | 0.8% |

判别性诊断(区分“自然饱和”与“线程空转”):

| 配置 | T1 wall | T8 wall | T8 sys | 解读 |
|---|---|---|---|---|
| 基准(OMP=8,OpenBLAS 默认池) | 0.358 | 2.483 | 5.66 | sys 爆炸 |
| `OPENBLAS_NUM_THREADS=1` | 0.340 | 2.284 | **0.02** | sys 爆炸全部来自 **OpenBLAS 自有线程池空转**(OMP 8 × OpenBLAS 8 = 64 pthread 挤 8 CPU 的过订阅) |
| 再加 `OMP_WAIT_POLICY=PASSIVE` | 0.292 | 0.423 | 0.04 | 空转彻底消除,但 wall 仍无加速 → **113 原子尺度下有效并行占比≈0**,不是 Amdahl 串行占比问题,是**开销支配区** |

**SCF 确定性**:全部 36 个测量运行 SCF 迭代数恒为 12,总能量恒为 −186.500449124213 Eh —— 与本仓库 07 号报告“同线程数内逐位可复现”一致(跨线程数仅有 ~1e-14 归约序差异)。

**结论(实测部分)**:113 原子 + OpenBLAS 构建下,**拐点在 1 核**——“加核反而变慢”。这正是社区流言的原始观测形态;其机制(空转/屏障/过订阅)已在代码里指认(§3),与“12”无关。注:GFN-FF 探针(19 ms 工作量)低于可靠计时分辨率,本机无法测其扩展性,引用 #1195 的社区数据(800 原子 GFN-FF,16 线程,user/real/16 = 0.84)补位。

---

## 3. 结构性原因(为什么拐点漂移,代码证据)

subagent lane-2 清单:全树 `!$omp` 指令行 **750 行 / ~50 文件**;`parallel do` 96 处;`critical` 35 处;`atomic` 13 处(全在 ptb);`collapse(2)` ~10 处;`barrier/sections/workshare` 0 处。GFN2 单点管线的并行结构:

```
GFN2 SP 一次 SCF 迭代:
  ├─ H0/积分构建   src/xtb/hamiltonian.F90:211-221   并行,shell-pair 粒度 collapse(2) dynamic(32)
  ├─ H1/Fock 装配  src/scc_core.f90:134-137         并行,逐矩阵元素 static
  ├─ dpint/qpint   src/scc_core.f90:185-249         并行,3 个 omp do static
  ├─ 偶极/四极 J   src/aespot.F90:323,621            并行,但导数累计在 critical(dipm_crt/qp_crt) (l.405-411)
  ├─ shell Coulomb src/coulomb/klopmanohno.F90:284   并行,原子对粒度 dynamic(32),但导数累计有 3 个 critical (l.559-567)
  ├─ D4 色散       src/disp/dftd4.F90:692,1109,...   并行,原子对粒度 dynamic(32) collapse(2)
  └─ ★对角化      src/mctc/lapack/eigensolve.F90:122-246   **零 OpenMP** — 全部委托 lapack_sygvd/syevd
```

**四条结构性原因:**

1. **本征求解器完全外包给 BLAS/LAPACK**。eigensolve.F90 无一行 OMP;并行性 = 链接库的属性:netlib 参考实现 → 恒串行;OpenBLAS → 自有 pthread 池(与 xtb 的 OMP 互不知晓,可过订阅,见实测 sys 爆炸);MKL(mkl_gnu_thread/intel_thread) → 尊重 OMP_NUM_THREADS/MKL_NUM_THREADS。**同一个 xtb 源码,仅 BLAS 后端不同,扩展曲线可以从“反扩展”(#401 OpenBLAS)变成“平台期”(#401 MKL,16 核 2 倍)**——这就是“别人的 12 核拐点”在你机器上不复现的第一原因。
2. **热循环以原子/原子对为迭代空间,粒度粗**。 hamiltonian.F90 的 shell-pair 循环是 GFN2 最重段,但迭代次数 ~O(N_shell²),113 原子只有几千个迭代,`dynamic,32` 块把并行度进一步除以块大小;8 线程分到的块在 0.3 s 总量里不足道,而 fork-join 屏障(SCF 每迭代 12 个并行区进出)与 libgomp 自旋等待全数变成了开销(实测 user+sys ≈ 7.7×wall)。
3. **critical 段卡在导数累积热路径上**。 klopmanohno.F90:559-567 三个 critical、aespot.F90:405-411 两个 critical —— 梯度计算阶段这变成真串行锁,核数越高争锁越重。
4. **35 处 `schedule(runtime)` 依赖用户设置 `OMP_SCHEDULE`**,而构建系统从不设它(全树 grep 为空)。官方文档自己说 “for many threads the dynamic schedule has proven to give a good load-balance” —— 也就是说**不设 `OMP_SCHEDULE` 的用户拿到的是默认 static 块分配**,多线程下负载不均。xtb 生态的 CENSO 文档直接把策略写成“并行效率指数衰减 ⇒ 尽量开尽量多的单线程作业”。

外加一条非代码但官方文档背书的硬墙:**内存**。xtb-docs setup.html:“3000 原子体系每线程 ~16GB(密集矩阵代数)” ⇒ 大体系的“核数上限”其实是内存上限,而这是架构性(密集本征求解)而非可调参数。

---

## 4. 说法溯源(网络考古)

| 来源 | 事实内容 | 与“12核”的关系 |
|---|---|---|
| [Issue #401](https://github.com/grimme-lab/xtb/issues/401) (2020) | conda-forge(OpenBLAS):1→5.44 s,**16 核→16.03 s(反扩展)**;换 MKL:16 核 2.66 s(平台期 ~2×) | “加核无提升/变慢”的实底;后端决定性证据 |
| [Issue #613](https://github.com/grimme-lab/xtb/issues/613) (2022) | 102 原子 GFN2:`-P 1` 远快于 `-P 16`;另一用户集群同象限;维护者指回 #401(换 MKL) | 同上;且解释了“设 -P 1 却看到 16 核在动”(BLAS 池不受 -P 管) |
| xtb-python [Issue #115](https://github.com/grimme-lab/xtb-python/issues/115) | tblite 库,50 原子:默认多线程比 OMP_NUM_THREADS=1 慢 10× | 小体系反扩展的极端案例 |
| Discussion #1156 (2024) | 20 核笔记本 GFN-FF MD;**i7-13650HX = 12 P-threads + 8 E-threads**;官方推荐式 `OMP_NUM_THREADS=${N},1` | **“12”最可能在这里混入**——它是某台笔记本的 P-线程数,不是 xtb 的核数上限 |
| Issue #1195 (2024) | 800 原子 GFN-FF MD,16 线程:user/real/线程数 = **0.839** | 反例:足够大的体系 + FF 代码路径,16 核仍有 84% 效率 |
| CP2K 邮件列表 2021-02 | “除非远超 1000 原子,我不会给 xtb 超过 25 核” | 大体系平台期位置的一个数据点 |
| susilehtola README(fork) | “小分子单核更快;不要超过物理核数” | 常识性建议,无 12 |
| xtb-docs setup.html | 3000 原子 16GB/线程;`OMP_NUM_THREADS=<ncores>,1`;OMP_SCHEDULE 动态调度的建议 | 官方承认内存随核×规模线性涨,拐点非固定 |

**判定**:“12 核后无提升”**不是代码常数,而是把‘小体系反扩展 + 大体系平台期 + 某台 12 线程笔记本’压缩成的一个民间口诀**。它在小体系场景下甚至保守了(拐点可以是 1 核);在大体系 + MKL 场景下又悲观了(25 核仍有收益)。

---

## 5. 对 landscape(PES 任务套件)工作的启示

1. **批量并行优先于单点内并行**:NEB 链像、扫描网格点、批 SP 这类工作应走**进程级并行**(每进程 `OMP_NUM_THREADS=1~2`),这是 CENSO/CREST 生态的既定做法;在引擎内对单个 SP 堆线程在我们的 OpenBLAS 构建上是负收益(§2)。
2. **引擎计时精度红线**:113 原子 GFN2 SP 仅 0.36 s(T1),任何 landscape 基准(如 P-RFO 步计时)若混入线程数变化,将同时混入 ~1e-14 归约序扰动与 7.7× 的空转噪声 —— 与 AGENTS.md §6.1/6.2 的既有警告同源。**landscape 的 FD-Hessian 与 NEB 序列必须保持线程数与重启策略双固定。**
3. **测试注册已规避**:`test/unit/{CMakeLists.txt:120,meson.build:105}` 把 `OMP_NUM_THREADS=1` 钉死,保持。
4. **无代码动作需求**:不存在要“修复的 12 核上限”;若未来 M7 要做扩展性对比,需在 **MKL 构建**(meson `lapack=mkl`,我们的 cmake 配置无此钩子,见 §1.2)或 ≥1000 原子体系上做,本机 8 逻辑 CPU 无法覆盖 12 核区间。

---

## 6. 复现命令(附录)

```bash
# 单点计时(任一线程数 T ∈ {1,2,3,4,6,8})
mkdir -p /tmp/xtb-bench && cd /tmp/xtb-bench && cp <repo>/assets/inputs/xyz/taxol.xyz .
for t in 1 2 4 8; do
  OMP_NUM_THREADS=$t OMP_DYNAMIC=FALSE XTBPATH=<repo> /usr/bin/time -v \
    /tmp/xtb-land/build/xtb taxol.xyz --gfn2 --sp 2> t$t.log
done
grep -E 'Elapsed|User time|System time' t*.log   # /usr/bin/time 缺失时用 getrusage 包装(见 subagent 工件)
# 判别诊断:OpenBLAS 空转 vs OpenMP 空转
OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=8 xtb taxol.xyz --gfn2 --sp   # sys 爆炸应消失
OPENBLAS_NUM_THREADS=1 OMP_WAIT_POLICY=PASSIVE OMP_NUM_THREADS=8 xtb ...  # 空转彻底消除
```

关键 grep(复现 §1/§3 证据):

```bash
rg -n 'omp_set_num_threads|WITH_MKL' src/prog/main.F90 src/readin.f90
rg -n '!\\$omp' src/mctc/lapack/eigensolve.F90        # 应为空:本征求解器零 OpenMP
rg -n 'schedule ?\\(' src -g '*.f90' | head           # dynamic,32/16 = 块大小,非核数上限
rg -n 'critical' src/coulomb/klopmanohno.F90 src/aespot.F90 | head
```
