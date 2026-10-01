# Research: TS 搜索 / 反应路径 / Hessian-频率 方法学的实现正确性与已知失效模式

> 目标背景：评估能否为 xtb 6.7.1（GFN2-xTB 作为能量/梯度引擎）构建一套 Fortran 的
> `sp / opt / scan / ts / hessian / freq / irc` 套件，并参考 MAPLE（Python，ML 势景观探索器）的
> dispatcher 设计。
>
> 本报告的取证规则：**直接证据** = 源文档原文/公式；**来源解读** = 我基于源文档的整理；
> **研究者推断** = 我个人的判断，源文档未明说。每条给出 confidence。
>
> 访问限制（影响证据强度，必须向下游披露）：
> - `gaussian.com` 在本环境下返回 HTTP 502（`/irc/`、`/opt/`、`/freq/`、`/vib/` 均失败）。
>   Gaussian 的数字主要来自搜索服务返回的原文片段与 G09 keyword 镜像页；**Gaussian 的
>   `Opt=Tight/VeryTight` 数值我未能从可访问的一手页面确认**。
> - 部分 Wiley/AIP/ACS/chemrxiv 正文（Baker 1986 全文、Sella 全文、EulerPC 首个 PDF）无法直取，
>   本报告对无法取到的公式明确标注"missing evidence"，不做杜撰。
> - 本报告是**只读**调研：未修改 `/home/owenchan/work_path/coding/python/MAPLE` 与
>   `/home/owenchan/work_path/coding/fortran/xtb` 的任何文件；本地代码只作引用。

---

## Summary

MEP/IRC、TS 优化、chain-of-states 三类算法的公式、步长与收敛阈值在文献和主流代码里都有
**可实现的明确形式**（质量加权 Cartesian 下的 `dx/ds = -g/|g|`；HPC 用 LQA 预测 + 修正
Bulirsch–Stoer 校正；P-RFO 的双 shift λ_p/λ_n；NEB 的 f⊥ + 弹簧力分解；CI 的平行力翻转）。
真正决定成败的不是公式而是**工程细节**：Hessian 更新公式（Bofill 是共识默认）、trust radius
与位移上限、要跟随的 Hessian 本征矢如何选（重叠判据，否则 modality 会切换）、以及
**能量/梯度的数值噪声量级必须比收敛阈值低一个数量级以上**。

对 xtb 引擎而言最关键的三条硬事实是：(1) xtb **没有 TS 优化器和 IRC**，官方并明确建议改用
外部工具（Sella / molecularGSM / pysisyphus 的 xtb calculator）；(2) xtb 自带的 Hessian 是
**两侧数值微分**，`step_hess = 0.005 bohr`（`src/type/setvar.f90:158`），且 Hessian 运行时的
SCC 精度被人为放宽为 `accu_hess = 0.3`（`src/type/setvar.f90:156`）——这是有限差分 Hessian
噪声的直接来源；(3) xtb 的 opt 收敛判据只有"能量变化 + 梯度范数"，**没有 max/RMS 力与位移的四条判据**，
且 xtb 自己提供 `average_conv` 来平均能量/梯度以"加速数值噪声的 PES 优化"
（`src/type/setvar.f90:95-97`）——即 Grimme 组自己承认 GFN 的 PES 数值上有噪声。

---

## Findings

### 1. MEP / IRC：质量加权坐标、GS / HPC / LQA / EulerPC

#### 1.1 统一的 IRC 定义与质量加权约定

1. **Claim：** IRC 是质量加权 Cartesian 坐标下的最陡下降路径，满足 stiff ODE
   `dx(s)/ds = -g(x)/|g(x)|`（s = 弧长，g = PES 梯度）。
   **Sources：** Hratchian & Schlegel, *J. Chem. Phys.* **120**, 9918 (2004)，Eq. (1)，
   <http://schlegelgroup.wayne.edu/Pub_folder/278.pdf>。
   **Support：** direct evidence（原文 Eq. 1）。
   **Confidence：** high。

2. **Claim：** 质量加权的单位约定：**1 a.u. 沿路径 = 1 bohr·amu^1/2**。Gaussian 的
   `IRC=(StepSize=N)` 单位是 0.01 Bohr，若 `N<0` 则为 0.01 amu^1/2-Bohr，默认 `N=10`；
   `MaxPoints` 默认 10。
   **Sources：** HPC 论文（"1 a.u. along the path corresponds to a step size of
   1 bohr amu^1/2"）；G09 `IRC` 关键字镜像页
   <https://wild.life.nctu.edu.tw/~jsyu/compchem/g09/g09ur/k_irc.htm>；`gaussian.com/irc/`
   的原文片段（StepSize/MaxPoints 默认值）。
   **Support：** direct evidence（数值与单位均为原文）。
   **Confidence：** high（单位约定）；medium（Gaussian 默认 `N=10` → 0.10，因为
   `gaussian.com` 正文此次无法直接抓取，只取到片段）。

3. **Claim（研究者推断）：** 我们的实现必须**同时**支持 MWC 与（可选）非加权 internal
   coordinates，但公式/步长的"官方默认值"都以 MWC 为基准；把别人的 0.10 直接搬到
   internal coordinates 是单位错误。
   **Support：** researcher inference。
   **Confidence：** medium-high。

#### 1.2 Gonzalez–Schlegel (GS) 二阶隐式方法

4. **Claim：** GS 每一步由两阶段组成：
   - **pivot（枢轴）步**：`q*_{k+1} = q_k - (1/2) s N G g_k`（原文 Eq. 8），
     其中 `N = (g_k^T G g_k)^{-1/2}`（Eq. 9），G 为质量加权度规；
   - **球面约束优化**：在圆心 `q*_{k+1}`、半径 `(1/2)s` 的球面上最小化能量（Eq. 10），
     直到切向梯度分量小于预设 cutoff。
   **Sources：** Gonzalez & Schlegel, *J. Phys. Chem.* **94**, 5523 (1990)（质量加权内坐标版本），
   <https://schlegelgroup.wayne.edu/Pub_folder/119.pdf>。
   **Support：** direct evidence（公式为抓取到的原文形式，OCR 略有噪声但 Eq.8/9/10 结构清晰）。
   **Confidence：** high（结构），medium（符号细节，建议以原文 PDF 复核）。

5. **Claim：** GS 论文中使用的步长：**0.05 amu^1/2 bohr**（主要测试），也用了
   **0.2 amu^1/2 bohr**；Hessian 只在 TS 处解析计算一次，路径上使用 **BFGS** 更新
   （原文强调 BFGS 产生的 Hessian 变化是正定的，与 DFP 不同）。
   **Sources：** 同上（119.pdf）。
   **Support：** direct evidence。
   **Confidence：** high（步长）；high（BFGS 更新）。

6. **Claim：** GS 的已知行为（来自 GS 高阶方法论文的对比段）：GS2 "通常每个 IRC 点需要
   3–5 次能量/梯度评价"；因为带约束优化，该法**在步长过大时仍能回到真实路径附近**，
   这是它相对显式方法的鲁棒性来源。
   **Sources：** Hratchian & Schlegel, EulerPC 论文（J. Chem. Phys. 133, 224101, 2010），
   <http://schlegelgroup.wayne.edu/Pub_folder/345.pdf>（对 GS2 的成本陈述）；
   Gonzalez & Schlegel, "Improved algorithms for reaction path following: Higher-order
   implicit algorithms", <https://schlegelgroup.wayne.edu/Pub_folder/135.pdf>
   （"reaction path is an arc of a circle… returns to the vicinity of the true path"）。
   **Support：** direct evidence。
   **Confidence：** high。

7. **Claim（失效模式）：** GS 的代价由"每点 3–5 次 E/g"和 micro-iteration 数决定；
   MAPLE 的实现里 `max_micro_cycles=20`、`micro_step_thresh=1e-3`、
   `hessian_recalc=None`（默认从不重算精确 Hessian）。微迭代不收敛（强弯曲路径、大 step）
   是实践中卡住的主因。MAPLE 还提供一个可选的**抛物线拟合来判断路径是否进入极小点盆地**
   （即"端点在哪儿"的启发式）。
   **Sources：** MAPLE "IRC: Gonzalez-Schlegel (GS)" 文档
   <https://www.maplechem.org/tasks/irc/irc_gs.html>（参数表原文）。
   **Support：** direct evidence（参数与"optional parabolic fit detects when the path has
   descended into a minimum basin"）；依赖 micro-cycle 的失效判断为 source interpretation。
   **Confidence：** high（参数）；medium（失效归因）。

#### 1.3 HPC（Hessian-based Predictor–Corrector）

8. **Claim：** HPC = **LQA 预测步 + 修正 Bulirsch–Stoer (mBS) 校正步**，校正步积分在
   **两点 distance-weighted interpolant (DWI) 拟合曲面**上进行（该曲面用两端点的
   position/energy/gradient/Hessian 拟合）。
   - 预测：`E(x)=E0+g0^T Δx + ½Δx^T H0 Δx`（Eq. 2）→ `g(x)=g0+H0Δx`（Eq. 3）
     → `dx(s)/ds = -(g0+H0Δx)/|g0+H0Δx|`（Eq. 4）；
     令 `ds/dt=|g0+H0Δx|`、`dx/dt=-(g0+H0Δx)`，解析解
     `x(t)=x0+A(t)g0`（Eq. 7），`A(t)=U a(t) U^T`（Eq. 8），
     `a_ii(t)=(e^{-λ_i t}-1)/λ_i`（Eq. 9），λ_i 为 Hessian 本征值；
     预测的 Euler 子步数 **N_Euler = 5000**（Eq. 10），积分在本征矢空间做
     （`ds/dt = [Σ_i (g'_{0i})² e^{-2λ_i t}]^{1/2}`，Eq. 11）。
   - 校正：mBS 使用**简单 Euler**（不是 modified midpoint——原文说 modified midpoint
     会"极大地放大"式(1) 的 stiff 特性而被否决）；误差接受阈值 **< 1×10⁻⁶ a.u.**；
     semi-implicit mBS 被判为不可行，因为 DWI 曲面导数"不可信"。
   **Sources：** Hratchian & Schlegel (2004)，Eqs. 1–12 与结论段，
   <http://schlegelgroup.wayne.edu/Pub_folder/278.pdf>。
   **Support：** direct evidence。
   **Confidence：** high。

9. **Claim：** HPC 的步长经验值：模型势上测 0.05–0.20；化学体系可用到 **0.400 a.u.**，
   而 **LQA 的 0.100 a.u. 是"practical upper limit"**；0.20 步长时 HPC 的 rms 垂直偏差
   0.0038 vs LQA 0.018。校正步**不增加额外的电子结构计算**（HPC 每 IRC 点仅 1 次 E/g）。
   **Sources：** 同上（278.pdf）。
   **Support：** direct evidence。
   **Confidence：** high。

10. **Claim：** HPC 路径上的 Hessian 处理：预测端点得到的 Hessian 被**直接复用**为下一步
    LQA 的 Hessian（"the DWI gradient at the corrected end point and the Hessian from the
    predicted end point are used for the next LQA step"）。
    **Sources：** 同上。
    **Support：** direct evidence。
    **Confidence：** medium-high（原文如此；**未**在该页出现 Bofill/BFGS/SR1 任何更新公式 →
    见 Missing evidence）。

11. **Claim（Gaussian 行为）：** G16 中大多数 IRC 默认用 HPC（G09 起）；`IRC=GradientOnly`
    与 ONIOM(MO:MM) 默认用 EulerPC；可选 LQA / DVV / Euler；Hessian 可用
    `ReCalc=N`（每 N 个 predictor 步，或 N<0 时每 |N| 个 corrector 步重算解析 Hessian）、
    `CalcFC` / `RCFC` 提供初始力常数、`IRC=(CalcFC,RecalcFC=(Predictor=N,Corrector=M))`。
    `ReCalc` 需要解析二阶导数。
    **Sources：** G09 `IRC` 关键字镜像（`wild.life.nctu.edu.tw` 版本，与 `gaussian.com/irc/`
    片段一致）。
    **Support：** direct evidence（选项存在与语义）；Gaussian 的**默认 ReCalc 值未在可访问页面出现**。
    **Confidence：** high（选项）；low（默认值，标为 missing evidence）。

#### 1.4 LQA（Page & McIver）

12. **Claim：** LQA 的规范引用是 Page & McIver, *J. Chem. Phys.* **88**, 922 (1988)
    （Gaussian/Q-Chem 写作 `Page88`/`Page90`）；HPC 论文把它描述为"用二次 Taylor 展开
    解析求解式(1)"的积分器（即上面 Eq. 2–9），它的解析解与 Sun–Ruedenberg 的
    quadratic steepest descent 属同一家族但**不是同一个导出**。
    **Sources：** 278.pdf（把 LQA 归给 Page–McIver）；G09 `IRC` 页（`LQA` → Page88/Page90）；
    Eckert & Werner, *Theor. Chem. Acc.* **100**, 21 (1998)，
    <https://www.math.u-szeged.hu/~stacho/eck-w98.pdf>（该文用的是 Sun–Ruedenberg QSD：
    `x(u) = x^(k) - H^{-1}(I - uH)g`，式(6)，并明确把 Page–McIver 只列为"prior LQA
    implementations"）。
    **Support：** direct evidence（归属与 QSD 公式）；**Page–McIver 的原始更新式未抓到**
    （标 missing evidence）。
    **Confidence：** medium-high。

13. **Claim（LQA 的失效模式，可直接用于设计）：** "straightforward LQA step" 在**强弯曲**
    路径上会产生**振荡（oscillative behaviour）并大幅偏离真实 MEP**；要达到 VTST 精度，
    简单 LQA 需要步长"around 0.1 a0 or rad"。Sun–Ruedenberg 的改进是区分三个点
    （展开中心 x^(k)、连接点 p^(k)、真实 MEP 点 r^(k)），从而用步长 h 达到 h/2 的精度。
    QSD 步长自适应函数 `h(κ)=h_max·f(κ/κ̃)`，`f = (a+1-κ/κ̃)/(1+(κ/κ̃)^m)`，
    `a=1/4, m=5/6, κ̃=2.0 a0`；测试 h_max = 0.15/0.3/0.5/0.7。
    **Sources：** Eckert & Werner (1998)（引 [16,39] 支持 0.1 的说法），同上 URL。
    **Support：** direct evidence（LQA 振荡特性与 0.1 步长）；注意该文不是 Page–McIver 原文。
    **Confidence：** medium-high。

14. **Claim：** MAPLE 的 LQA 实现只把 LQA 当作**二阶局部二次近似**的积分器，其定位是
    "surface 光滑时最快"。
    **Sources：** <https://www.maplechem.org/tasks/irc/irc_lqa.html>。
    **Support：** source interpretation（MAPLE 文档对这一族算法的定位描述）。
    **Confidence：** medium。

#### 1.5 EulerPC（Meisner & Kästner）

15. **Claim：** EulerPC 的预测步是一阶 Euler：
    `x̃_{i+1} = x_i - (g_i/|g_i|) s`（原文 Eq. 2）；校正步是与 HPC 相同的
    **DWI 曲面 + 修正 Bulirsch–Stoer**；DWI 曲面 `E_DWI = Σ_i w_i T_i`，
    `T_i(x) = E_i + g_i^T x + ½ x^T H_i x`（Eq. 3–4）。
    **Sources：** Meisner & Kästner, *J. Chem. Phys.* **133**, 224101 (2010)，
    <http://schlegelgroup.wayne.edu/Pub_folder/345.pdf>。
    **Support：** direct evidence。
    **Confidence：** high。

16. **Claim：** EulerPC **本质上是一阶方法**（log-log 斜率 2.016，即误差 ∝ step¹），
    因此需要更小步长/更密路径点才能达到 GS/HPC 的精度；
    每一步只花 **1 次 E/g**（对比 GS2 的 3–5 次）；
    预测器/校正器开销 O(N_atoms)，DWI 曲面拟合需要 O(N_atoms²) 存储与计算
    （HPC 若做完整 Hessian 则是 O(N_atoms³)）。
    **Sources：** 345.pdf。
    **Support：** direct evidence。
    **Confidence：** high。

17. **Claim：** EulerPC 论文的步长：**0.10 与 0.40 amu^1/2 bohr** 测试，
    "0.10 amu^1/2 bohr is an accepted step size upper limit in most reaction path
    following applications"；Hessian 更新测试统一用 0.10 amu^1/2 bohr；
    mBS 截断阈值 **1×10⁻⁶ amu^1/2 bohr**；
    Hessian 更新使用 **Bofill 方案**，并测试了每 2/5/10 个预测步用解析 Hessian 更新一次
    以及"全部用更新 Hessian"。
    **Sources：** 345.pdf。
    **Support：** direct evidence（这是"路径上用哪个 Hessian 更新"的最强一手证据）。
    **Confidence：** high。

18. **Claim（对失效模式的对比数据）：** Euler 积分在 0.20 步长下"无法跟随路径"，会产生
    绕 IRC 的大振荡；LQA 在 0.20 下"经历轻微困难但能自行回到参考路径"；GS2 更稳。
    最大误差出现在 SiH2+H2→SiH4，0.40 步长时 RMS/max 误差 0.0059 / 0.0111
    amu^1/2 bohr。
    **Sources：** 345.pdf。
    **Support：** direct evidence。
    **Confidence：** high。

#### 1.6 两端点（forward/backward）如何判定结束

19. **Claim：** **没有任何一手来源给出统一的"端点检测"判据**。
    - Gaussian：靠 `MaxPoints` 硬截断（默认每方向 10 点），不判断"到极小点了"。
    - MAPLE-GS：可选抛物线拟合判断是否已落入极小点盆地（启发式）。
    - MAPLE-HPC/EulerPC：只有 `max_steps`（默认 50）。
    - ORCA：`%irc MaxIter`（默认 20）＋梯度收敛检查。
    - xtb 的 RMSD push/pull pathfinder：打印 `terminated because max. # cycles reached`
      并输出 `xtbpath_ts.xyz`，也是硬截断。
    **Sources：** G09 IRC 页；MAPLE GS/HPC/EulerPC 页；ORCA 6.1 手册 4.4
    <https://www.faccts.de/docs/orca/6.1/manual/contents/structurereactivity/irc.html>；
    xtb 文档 <https://xtb-docs.readthedocs.io/en/latest/path.html>。
    **Support：** direct evidence（各代码的行为）；"没有统一判据"是 source interpretation。
    **Confidence：** high。

20. **Claim（研究者推断）：** 我们的 IRC 必须自带三种终止信号：
    (a) `max_steps`；(b) 每步 |g| 低于阈值（进入盆地）；(c) 能量沿 s 回升超过 N 步
    （说明越过了极小点）。三者需可配置，并把"落在哪个极小点"作为输出（配合 RMSD 比较）。
    **Support：** researcher inference（基于上面各代码的实践）。
    **Confidence：** high（工程建议）。

---

### 2. TS 优化器：P-RFO / B-PRFO / Dimer / eigenvector-following

#### 2.1 P-RFO 的公式（取自 ORCA 6.1 手册，最完整的公开实现描述）

21. **Claim：** P-RFO 把优化分成两个问题：沿 **1 个** Hessian 本征模**极大化**（shift
    `λ_p`），沿其余 **3N-7(6)** 个本征模**极小化**（shift `λ_n`）：
    ```
    E = E0 + g_q^T Δq + ½ Δq^T H_q Δq                       (4.16)
    Δq = -H_q^{-1} g_q = Σ_i (-V_i^T g_q V_i / b_i)          (4.17)
    λ_p = ½ b_k + ½ sqrt(b_k² + 4 F_k²)                      (4.18a)
    Σ_{i≠k} F_i² / (λ_n - b_i) = λ_n                         (4.18b)  （迭代求解）
    Δq_k = -(F_k V_k)/(b_k - λ_p),
    Δq_i = -(F_i V_i)/(b_i - λ_n),  i≠k                      (4.19)
    Δq = Σ_j Δq_j                                            (4.20)
    ```
    其中 `F_i = V_i^T g`。`λ_n` 必须为负且小于 `b_2`（若跟随的不是最低模则小于 `b_1`）；
    若 Hessian 有不止一个负本征值，需要**修改 Hessian**：ORCA 的实现是"把 Hessian 的对角元
    平移或反号（shifted or reversed）"。
    **Sources：** ORCA 6.1 Manual §4.3.1
    <https://www.faccts.de/docs/orca/6.1/manual/contents/structurereactivity/optimizations_TS.html>；
    算法归属 Baker, *J. Comput. Chem.* **7**, 385 (1986)。
    **Support：** direct evidence（公式逐条来自手册原文）。
    **Confidence：** high。

22. **Claim：** 为什么"朴素 TS 优化器会滑到极小点"——Newton–Raphson 步
    `Δq = -H_q^{-1} g_q` **走向最近的驻点**，"根据该点 PES 的曲率，这个驻点可能是极小点
    也可能是鞍点"；只有引入 shift 才能强制目标是"恰有一个负本征值"的驻点。
    **Sources：** ORCA 6.1 §4.3.1 原文（"This step leads to the nearest stationary point…
    can be a minimum or a saddle point"）。
    **Support：** direct evidence。
    **Confidence：** high。

23. **Claim：** 补充机制层面的原因：**BFGS 更新被构造成正定 Hessian，因此在原理上不适合
    鞍点定位**；这也是为什么路径/TS 优化需要 Bofill、TS-BFGS、SR1 这类不保正定的更新。
    **Sources：** arXiv:2603.21323（"Machine-Learned Leftmost Hessian Eigenvectors…"）
    <https://arxiv.org/html/2603.21323>；Bofill 1994/1995 的更新族论文（摘要级）。
    **Support：** direct evidence（BFGS 正定性 → 不适合鞍点）。
    **Confidence：** high。

24. **Claim：** "minimization 用的 shift 必须 λ < 最小本征值"才能在有理函数框架下保证下降步：
    `p̃_i = -g̃_i/(H̃_ii - λ)`；这正是 RFO 的思路。
    **Sources：** pysisyphus 文档 §7
    <https://pysisyphus.readthedocs.io/en/latest/min_optimization.html>（含推导）。
    **Support：** direct evidence。
    **Confidence：** high。

25. **Claim：** "B-PRFO"：**未在任何一手来源中找到这个写法**。两种可能解读：
    (a) **Baker 的 P-RFO**（ORCA 与 MAPLE 均以 Baker 1986 为 P-RFO 的出处）；
    (b) **Banerjee 的 RFO 变体**——第三方工作流文档把 `RS-P-RFO` 标注为
    "(Banerjee, default)"（pdb2reaction tsopt 文档）。
    **Sources：** ORCA 6.1 §4.3.1（Baker 1986）；MAPLE P-RFO 页（"Baker"式 P-RFO）；
    <https://t-0hmura.github.io/pdb2reaction/reference/commands/tsopt.html>（"RS-P-RFO (Banerjee)"）。
    **Support：** direct evidence（两处归属）；"B-PRFO 就是其中之一"是 researcher inference。
    **Confidence：** low（术语本身）→ 建议向任务发起方确认 B 指 Baker 还是 Banerjee/Boﬁll。

#### 2.2 P-RFO 的 trust radius / step 控制的公开默认值（可直接抄）

26. **Claim：** MAPLE 的 P-RFO 默认参数：
    `trust_radius=0.2` Å，`trust_min=1e-3`，`trust_max=1.0`，`eta_shrink=0.75`，
    `eta_expand=1.75`，`evals_eps=1e-10`，`mu_margin=1e-8`，`max_bisect_it=60`，
    `recalc=1`（每步重算精确 Hessian），`hessian_update=bofill`，
    收敛阈值 `f_max_th=9.5e-3`、`f_rms_th=5e-3`（Hartree/Å）、
    `dp_max_th=1.8e-3`、`dp_rms_th=1.2e-3`（Å）。
    **Sources：** <https://www.maplechem.org/tasks/ts/ts_prfo.html>。
    **Support：** direct evidence（参数表原文）。注意：这四个收敛阈值与 Gaussian 的
    "Loose" 级别数量级一致（pysisyphus 亦把 Baker 阈值描述为"comparable to the Gaussian
    defaults"）→ source interpretation。
    **Confidence：** high（参数）；medium（与 Gaussian Loose 的对应关系）。

27. **Claim：** pysisyphus 的 TS 优化默认：`trust_radius=0.3`，`trust_min=0.1`，
    `trust_max=1.0`，`max_micro_cycles=50`，`hessian_update: bofill`
    （文档明说"Should not be modified for TS optimizations"），
    `hessian_recalc: 1..5`（"a small number like 5 may be a good idea"）。
    **Sources：** pysisyphus TS optimization 文档
    <https://pysisyphus.readthedocs.io/en/latest/tsoptimization.html>。
    **Support：** direct evidence。
    **Confidence：** high。

28. **Claim：** ORCA 的 step 控制：`MaxStep` 默认 **0.3 au**（内坐标最大步长），
    `Trust` 默认 **-0.3**（负号表示固定 trust radius 0.3 au）。
    **Sources：** ORCA 6.1 Manual §4.1 Table 4.3（`%geom` 关键字表原文）。
    **Support：** direct evidence。
    **Confidence：** high。

#### 2.3 Dimer（Henkelman & Jónsson）

29. **Claim：** 旋转步与曲率（原文 Eq. 2 与 Eq. 5/6/13）：
    ```
    F' = F1' - F2',   Fi' ≡ Fi - (Fi·N̂)N̂
    C = [(F2 - F1)·N̂]/(2ΔR) = (E2 - E0)/(ΔR)²              (Eq. 2)
    E0 = Ez + (ΔR/4)(F1 - F2)·N̂                             (Eq. 3)
    F' ≈ [F*·Q̂* - F·Q̂]/δθ |_{θ=δθ/2}                      (Eq. 5)
    Δθ ≈ (F·Q̂ + F*·Q̂*)/(-2F')                              (Eq. 6, 改进前)
    Δθ = θ0 = -½ arctan(2 F0 / F0')                         (Eq. 13, 推荐)
    ```
    平移步的有效力与 quick-min 传播：
    ```
    F† = F_R - 2F∥                                            (Eq. 18)
    ΔV_i = F_i† Δt/m ;  V_i = ΔV_i(1 + ΔV_i·V_{i-1}/ΔV_i²) if V_i·F_i† > 0, else ΔV_i
    F† = -F∥        if C > 0
    F† = F_R - 2F∥  if C < 0                                  (Eq. 21)
    ```
    原文明确指出 Eq. 13 比 Eq. 6 在 `F→0`、`F'→0` 极限下行为更好。
    **Sources：** Henkelman & Jónsson, *J. Chem. Phys.* **111**, 7010 (1999)，
    <https://theory.cm.utexas.edu/henkelman/pubs/henkelman99_7010.pdf>（经 answer 模式逐式抽取）。
    **Support：** direct evidence（公式形式；OCR 已按原文符号校正）。
    **Confidence：** high。

30. **Claim：** Dimer 的推荐参数（原文）：dimer 分离 **ΔR = 1×10⁻² Å**（Al/Al(100) 算例），
    平移的有限差分步 `dR = 1×10⁻³ Å`，旋转有限差分角**δθ = 1×10⁻⁴ rad**，
    最大平移距离 0.1 Å，旋转/平移收敛时 |F| < 1×10⁻⁴；典型 ~400 次力评价；
    初始随机位移 ~0.1 Å/坐标（Gaussian）。共轭梯度旋转+平移优于 quick-min。
    **Sources：** 同上。
    **Support：** direct evidence。
    **Confidence：** medium-high（这些是算例取值，原文未宣称它们是"通用默认值"）。

31. **Claim：** **各代码的"dimer separation"定义不一致（真实陷阱）**：
    - VASP：`DdR = 5E-3`（Å）是"**twice** the distance between images"；
      `DRotMax=1`，`DFNMin=0.01`，`DFNMax=1.0`。
    - pysisyphus：`length = 0.0189` 是"separation of dimer images from **common midpoint**"，
      `rotation_max_cycles=15`，`rotation_method=fourier`，`rotation_thresh=1e-4`（rms 旋转力），
      `rotation_tol=1`（度），`rotation_max_element=0.001`（direct 法的最大步元），
      `rotation_remove_trans=True`，`seed` 用于可复现。
    **Sources：** VASP dimer 页 <https://theory.cm.utexas.edu/vtsttools/dimer.html>；
    pysisyphus TS 文档 §12.2。
    **Support：** direct evidence（两处定义原文）。
    **Confidence：** high。

32. **Claim（Dimer 的实战诊断规则，VASP 文档）：** 收敛判断需要
    "max force < -EDIFFG **且** curvature < 0"；若 Torque（旋转力）不随迭代下降，
    说明**受力精度不够**，应把 EDIFF 降到 1e-7~1e-8，或**增大 DdR**；
    Angle 若长期停在 ~1 说明有问题。
    **Sources：** VASP dimer 页（同上）。
    **Support：** direct evidence。
    **Confidence：** high。**这一条对 GFN2-xTB 直接适用**（见 §8）。

#### 2.4 eigenvector-following vs RFO

33. **Claim：** EF 与 RFO 共用"有理函数"框架（Q-Chem 附录给出本征方程形式 A.7–A.10，
    归给 Baker(1986) 与 Banerjee(1985)）；差别在于**对位移分母的 shift 形式与求解方式**
    （RFO 用 λ 修正分母并迭代求 λ；P-RFO 则对"要极大化的模"和"要极小化的模"用**两个不同**
    shift λ_p/λ_n）。Q-Chem 另有 TRIM 等替代。
    **Sources：** Q-Chem 6.0 §9.1.3 EF 算法
    <https://manual.q-chem.com/6.0/sect_ef.html>（附录 A.7–A.10）；
    ORCA 6.1 §4.3.1（P-RFO 双 shift）；pysisyphus overview（RS-P-RFO / RS-I-RFO / TRIM 并列，
    TRIM → TRIM-Paper）。
    **Support：** direct evidence（各自形式）；"差别是双 shift vs 单 shift"是 source interpretation。
    **Confidence：** high（各自形式）；medium（统一对比表述，因为原文没有横向对比页）。

#### 2.5 TS 优化的已知陷阱与标准防护

34. **Claim（如何选要跟随的模——这是最重要的一条）：** 主流实现都不"只取最低本征值"，而是用
    **重叠（overlap）判据**：
    - pysisyphus：`prim_coord: [BOND, i, j]` = "Select the mode to follow uphill by **overlap**
      with this primitive internal coordinate. Expects exactly one typed primitive."；
      `rx_modes` = 与"构造出的模"做重叠（含相位因子），是 `prim_coord` 的推广；
      `root: n` = "Follow the n-th imaginary mode uphill"；
      `hessian_ref: [path]` = 用参考 Hessian 的虚模做**最高重叠**选择。
    - ORCA：`TS_Mode` 关键字；Hybrid Hessian 情况下要求"前 3–5 个循环检查是否跟随了正确的模"。
    **Sources：** pysisyphus TS 文档（原文注释）；ORCA 6.1 §4.3.2 Tips。
    **Support：** direct evidence。
    **Confidence：** high。

35. **Claim（符号/相位问题）：** transion vector 的"相位（phase）"必须被固定，否则 forward/reverse
    方向歧义。Gaussian 的定义："forward 方向 = transition vector 最大分量为正时其指向的方向"，
    并可用 `Phase=(N1,N2[,N3[,N4]])` 显式指定（键/角/二面角）。
    **Sources：** G09 `IRC` 页（原文）。
    **Support：** direct evidence。
    **Confidence：** high。

36. **Claim（近平简最低本征值）：** 公开手册没有正式规则，但存在一个有具体描述的实现行为：
    当 Hessian 出现**幅度很小的本征值**（低频模）时，ORCA 会把该本征值**替换为同号的较大数值**，
    因为 P-RFO 会沿小本征值方向走出巨大的一步。
    **Sources：** Matter Modeling SE 问题 "Geometry optimisation with low frequency modes"
    <https://mattermodeling.stackexchange.com/questions/12962/geometry-optimisation-with-low-frequency-modes>
    （**社区 lore**，非 ORCA 官方文档；回答描述的是用户观察/推断）。
    **Support：** community lore —— 明确标注。
    **Confidence：** low-medium。

37. **Claim（近平简的替代处理）：** 用 **image function / RS-I-RFO**（把"沿一个模上升"改写为
    image function，对近平简更稳）与 **TRIM** 是常见替代；pysisyphus 把 `RS-P-RFO` 作为默认，
    但也实现 `RS-I-RFO`（RS 变体需要 `max_micro_cycles`，TRIM 不需要）。
    **Sources：** pysisyphus TS 文档（原文：RS 变体有 micro cycles，TRIM 不适用；
    `#max_micro_cycles: 50`）。
    **Support：** direct evidence（实现存在）；"对近平简更稳"是 source interpretation。
    **Confidence：** medium。

38. **Claim（trust radius 失效与推荐削减）：** pysisyphus 的"TS 优化通用建议"明确列出：
    多用精确 Hessian（`hessian_recalc: n`）、**用紧的 SCF 收敛**（"In contrast to codes like
    ORCA pysisyphus does not enforce this automatically"）、网格类方法要更细网格以**降低数值噪声**、
    先用便宜方法（xtb）预优化 TS、**减小 trust radius 到 0.1 / trust_max 0.3–0.5**、
    检查内坐标设置是否正确。
    **Sources：** pysisyphus TS 文档 §12.3。**Support：** direct evidence。**Confidence：** high。

39. **Claim（平移/转动的投影）：**
    - ORCA：`ProjectTR` 默认 **false**（"Disable translation and rotation projection
      (must be false for internals)"）→ 即用内坐标时不做 TR 投影，用 Cartesian 时才做。
    - geomeTRIC：TRIC 坐标系统显式包含平移/转动（JCP 144, 214108 (2016)）。
    - ASE NEB：`remove_rotation_and_translation` 选项，非周期体系默认开启。
    - NWChem VIB：用 **Eckart 投影**去掉平动/转动后再对角化。
    **Sources：** ORCA 6.1 Table 4.3；geomeTRIC 文档
    <https://geometric.readthedocs.io/en/latest/>；ASE NEB 文档
    <https://docs.ase-lib.org/ase/neb.html>；NWChem Hessians 页
    <https://nwchemgit.github.io/Hessians-and-Vibrational-Frequencies.html>。
    **Support：** direct evidence。
    **Confidence：** high。

40. **Claim（Baker 的位移缩放）：** 我能确认的是"step 必须被限制"这一事实（ORCA `MaxStep 0.3 au`；
    MAPLE/pysisyphus 的 trust_max；P-RFO 的 restricted-step 文献），
    但**未能取到 Baker 1986 原文中具体的位移缩放公式/数字**（Wiley 全文不可达）。
    **Sources：** 见 Missing evidence。**Support：** —。**Confidence：** n/a。

---

### 3. Chain-of-states：NEB / CI-NEB / AutoNEB / GSM(FSM) / DMF

#### 3.1 NEB 与改进切线、弹簧常数

41. **Claim：** NEB 的力分解（geomeTRIC Eq. 1）：
    ```
    F_i = F_PES^⊥(r_i) + F_spring^∥(Δr_{i+1,i}, Δr_{i-1,i})
    F_PES^⊥(r_i) = F_PES(r_i) - (F_PES(r_i)·τ̂_i) τ̂_i
    F_spring^∥   = k(|r_{i+1}-r_i| - |r_i-r_{i-1}|) τ̂_i
    ```
    tangent 定义（Henkelman & Jónsson 2000, Eqs. 8–11）：用**能量单调性**决定上风/下风：
    ```
    τ_i = τ_i^+ = R_{i+1}-R_i   if  V_{i+1} > V_i > V_{i-1}
    τ_i = τ_i^- = R_i-R_{i-1}   if  V_{i+1} < V_i < V_{i-1}
    ```
    在极值点用加权平均（Eqs. 10–11）：
    ```
    τ_i = τ_i^+ ΔV_i^max + τ_i^- ΔV_i^min   if V_{i+1} > V_{i-1}
    ΔV_i^max = max(|V_{i+1}-V_i|, |V_{i-1}-V_i|)
    ΔV_i^min = min(...)
    ```
    原始弹簧力（Eq. 5，用 displacement 差）vs 改进弹簧力（Eq. 12，用**标量距离差**）：
    ```
    F_i^s|∥ = k[(R_{i+1}-R_i) - (R_i-R_{i-1})]·τ̂_i τ̂_i     (原)
    F_i^s|∥ = k(|R_{i+1}-R_i| - |R_i-R_{i-1}|) τ̂_i          (改进)
    ```
    **Sources：** Henkelman & Jónsson, *J. Chem. Phys.* **113**, 9978 (2000)，
    <https://theory.cm.utexas.edu/henkelman/pubs/henkelman00_9978.pdf>；
    geomeTRIC NEB 文档（同一组公式的实现描述）
    <https://geometric.readthedocs.io/en/latest/neb.html>。
    **Support：** direct evidence。
    **Confidence：** high。

42. **Claim：** spring constant 惯例：
    - 所有弹簧用**同一个 k** 才能得到等间距（Henkelman 2000 原文）；
    - "k 可以变化几个数量级而不影响 band 的平衡位置"（Henkelman 2000 原文）；
    - ASE `NEB(images, k=0.1)` → **默认 k = 0.1 eV/Å**；
    - VASP：`SPRING` 默认 **-5**（负值表示启用 NEB），并警告"不要用过大值，否则妨碍收敛"；
    - CI-NEB 论文给出的可变 k：`k_i' = k_max - Δk[(E_max-E_i)/(E_max-E_ref)]`（E_i>E_ref），
      否则 `k_max - Δk`。
    **Sources：** 上述三处 + Henkelman/Uberuaga/Jónsson, *J. Chem. Phys.* **113**, 9901 (2000)
    <https://theory.cm.utexas.edu/henkelman/pubs/henkelman00_9901.pdf>（Eq. 6）。
    **Support：** direct evidence。
    **Confidence：** high。

43. **Claim（**矛盾点**，见 Contradictions）：** "k 变几个数量级无影响" 与 "k 过大会妨碍收敛"
    指的是**不同性质**（平衡位置 vs 收敛速率），但在设计参数默认值时必须明确区分。
    **Support：** source interpretation。**Confidence：** high。

#### 3.2 CI-NEB 的细节

44. **Claim：** climbing image 的力（Eq. 5）：
    ```
    F_i_max = -∇E(R_i_max) + 2∇E(R_i_max)|∥
            = -∇E(R_i_max) + 2 (∇E(R_i_max)·τ̂_i_max) τ̂_i_max
    ```
    即"取完整势能力，并把沿 band 的平行分量反号"；**最高点图像完全不受弹簧力影响**。
    切换时机：先用常规 NEB 跑若干迭代，再选出能量最高的图像 `i_max`；
    若有两个以上接近的高能垒，可指定多个 climbing image。
    **Sources：** henelman00_9901.pdf（原文 Eq. 5 与正文）。
    **Support：** direct evidence。
    **Confidence：** high。

45. **Claim（CI-NEB 的量化收益与收敛）：** CH4/Ir(111) 上 CI-NEB 比常规 NEB 的活化能估计高
    ~0.4 eV（常规 NEB 低估）；计算量相当（差异 <10%）；达到 0.03 eV/Å 力收敛所需力评价次数
    179（常规 NEB）/190（CI，等弹簧）/178（CI，可变弹簧）。
    **Sources：** henelman00_9901.pdf。**Support：** direct evidence。**Confidence：** high。

46. **Claim（geomeTRIC 的 NEB 收敛数字，可直接抄）：** 收敛判据是**所有图像的 g_RMS 的
    平均值和最大值**都低于阈值；`g_RMS = sqrt((1/N_atoms) Σ_i (g_xi²+g_yi²+g_zi²))`；
    默认收敛阈值 **0.025（平均）与 0.05（最大）eV/Å**；climbing image 的切换阈值
    `--climb [0.5]` 表示"最大 RMS 梯度 < 0.5 eV/Å 时把 HEI 切到 climbing 模式"。
    **Sources：** geomeTRIC NEB 文档（原文）。**Support：** direct evidence。**Confidence：** high。

#### 3.3 初始路径生成（线性插值 vs IDPP）

47. **Claim：** IDPP（image dependent pair potential）：构造一个只依赖**原子对距离插值**的
    目标函数面，在该面上做 NEB 得到初始路径，**不需要任何能量评价**；
    论文明说线性插值（LI）与 LST 路径会产生间断/大量迭代。
    **Sources：** Smidstrup, Pedersen, Stokbro, Jónsson, *J. Chem. Phys.* **140**, 214106 (2014)；
    arXiv 版 <https://arxiv.org/html/1406.1512>；ASE 示例
    <https://docs.ase-lib.org/examples_generated/03-tutorials/neb_idpp.html>。
    **Support：** direct evidence。**Confidence：** high。

#### 3.4 Growing String / GSM (FSM)

48. **Claim：** GSM 的核心机制（Peters–Heyden–Bell–Chakraborty 2004）：
    - 垂直梯度（法向力）：`f⊥(w(s)) = -∇V(w(s)) + (τ̂(s)^T ∇V(w(s))) τ̂(s)`（Eq. 1），
      MEP 满足 `f⊥(w^MEP)=0`；
    - 生长指示函数：`i(f⊥) = 1 if |f⊥| ≤ tolerance else 0`（Eq. 7），
      tolerance 可固定或像 trust radius 一样自适应；
    - 生长规则（Eq. 9）：`a1(k+1)=a1(k)+Δs_k·i(f⊥(w_lf))`，
      `a2(k+1)=a2(k)-Δs_k·i(f⊥(w_rf))`，`n_{k+1}=n_k+i(·)+i(·)`；
      `a2-a1 → 0` 时两段合并，之后节点数固定、参数化均匀。
    - 切线：可用中心差分，但**推荐三次样条（free ends 给出端点自然切线）**；
      NEB 用 upwind 切线，SM/GS 用样条切线；
    - 节点间距条件 `R > |∇V·τ̂|/(2ν₂)`（ν₂ = 垂直路径平面内的最小 Hessian 本征值）以防 kink。
    **Sources：** Peters et al., *J. Chem. Phys.* **120**, 114101 (2004)（PDF 版）
    <https://sites.chemengr.ucsb.edu/~baronp/CODES/SADDLE-SEARCH/04_Peters_GrowingString.pdf>。
    **Support：** direct evidence（公式与参数为原文抽取）。
    **Confidence：** high。

49. **Claim（GSM vs NEB 的量化结论，注意原文的保留态度）：**
    Müller–Brown 势 18 节点：GS 收敛到鞍点的梯度数约为 NEB 的 1/3（GS 185，NEB(k=10) 210）；
    但同一篇原文结论说"我们的二维 Müller–Brown 结果**并未明确支持** GSM 优于 NEB/SM"；
    丙氨酸二肽体系上 **GS 一致优于 SM 与 NEB**，且在质量加权坐标下只有 GS 收敛到正确路径
    （NEB 有节点高出反应物 380 kcal/mol）。
    **Sources：** 同上。**Support：** direct evidence。**Confidence：** high。

50. **Claim（GSM 的实现默认值，pysisyphus）：** `max_nodes=9`（总 11 图）、`climb=False`
    （但"usually a good idea"）、`climb_rms=0.005`（启用 CI 的 rms(force) 阈值）、
    `reparam_check: rms`、`perp_thresh=0.05`（生长新 frontier 节点的阈值）、
    `reparam_every=2` / `reparam_every_full=3`、`climb_lanczos`、`stop_in_when_full=-1`；
    另有 `precontr`（平动/转动预条件）与 string 优化器。
    **Sources：** pysisyphus COS 文档
    <https://pysisyphus.readthedocs.io/en/latest/chainofstates.html>。
    **Support：** direct evidence。**Confidence：** high。

#### 3.5 AutoNEB

51. **Claim：** AutoNEB = 逐步建立路径的策略：先粗收敛少量图像，再**在几何或能量分辨率最需要的
    间隙插入新图像**，从而比一次性 NEB 用更少资源；论文 Kolsbjerg, Groves, Hammer,
    *J. Chem. Phys.* **145**, 094107 (2016)，勘误 *JCP* **148**, 029903 (2018)；
    已在 **ASE `ase/autoneb.py`** 中实现。
    **Sources：** <https://pubmed.ncbi.nlm.nih.gov/27608989/>；
    ASE AutoNEB 的 merge request 描述
    <https://gitlab.com/ase/ase/-/merge_requests/144>（"stepwise build up the path while
    evaluating only a few images at the same time… a new image is added in the gap that either
    improves the geometrical or energy resolution"）；ASE NEB 文档把 AutoNEB 列为 Paper III。
    **Support：** direct evidence（原理与出处）；具体 ASEN EB 参数未取到。
    **Confidence：** medium-high。

#### 3.6 DMF（MAPLE `ts/algorithm/dmf.py` + `_dmf_torch_backend.py`）到底是什么

52. **Claim：** **DMF = Direct MaxFlux**，一个**双端（double-ended）变分路径优化**方法：
    目标是"最小化 `exp(βE)` 的有限温度线积分"（大型 β 极限下逼近 minimax，
    即路径最高点趋近 TS），基于 Koda & Saito 的 variational MaxFlux 形式。
    MAPLE 用 **B-spline 曲线**表示路径（控制点由 IPOPT 优化，端点约束固定），
    另外有一组独立的能量评价点；默认用 **FB-ENM（flat-bottom elastic network model）**
    生成初始路径。
    **Sources：** MAPLE "Direct MaxFlux (DMF)" 文档
    <https://www.maplechem.org/tasks/ts/ts_dmf.html>；MAPLE PR #57
    <https://github.com/ClickFF/MAPLE/pull/57>（新增 DMF）；PyDMF（Koda 的参考实现）
    <https://github.com/shin1koda/dmf> 与文档 <https://shin1koda.github.io/dmf/>；
    FB-ENM 原始论文 <https://chemrxiv.org/doi/10.26434/chemrxiv-2024-h15dh>；
    ColabReaction（DMF+UMA）<https://pubs.acs.org/doi/abs/10.1021/acs.jcim.5c02398>。
    **Support：** direct evidence。**Confidence：** high。

53. **Claim（**关键结论**）：DMF **不需要神经网络势**。** MAPLE 文档明确写：
    "The objective contains energies only; its analytic gradient uses forces, not Hessians"，
    并且 "DMF itself does not use Hessians"；能量/力来自"the selected MAPLE calculator"。
    因此**任何能给出能量+力的引擎（含 GFN2-xTB）都可驱动 DMF**。
    MAPLE 的 `_dmf_torch_backend.py` 对应的是 `backend=numpy|torch` 这个**张量后端**选项
    （"Tensor backend for DMF path algebra: numpy or torch. The torch backend inherits the
    calculator device when available"），**不是**对 ML 势的依赖。
    但 DMF 依赖 **cyipopt** 做非线性约束优化（必须显式安装）。
    **Sources：** MAPLE DMF 页（原文引用如上）。
    **Support：** direct evidence（文档原文）；"torch backend ≠ MLIP 依赖"是明确指出文档措辞
    的 source interpretation。
    **Confidence：** high。

54. **Claim：** DMF 的 MAPLE 默认参数（可作为我们复刻时的对照）：
    `beta=10.0`（1/eV，即 kT≈0.1 eV 量级的有效温度）、`nmove=10`、`nsegs=6`、`dspl=3`（B 样条阶数）、
    `update_teval=False`、`init_path=fbenm`（或 `linear`）、`fbenm_correlated=True`、
    `mass_weighted=False`、`remove_rotation_and_translation=True`、
    `tol=tight|middle|loose`、`max_iter=200`、`refine=None|prfo|dimer`。
    **Sources：** MAPLE DMF 页。**Support：** direct evidence。**Confidence：** high。

55. **Claim（研究者推断）：** 对"GFN2-xTB 套件要不要做 DMF"的判断：
    代价是 **IPOPT 依赖（C 库）＋ B-spline 路径优化器**，收益是"无需 Hessian 就能拿到
    rough MEP + TS guess"；而如果已实现 CI-NEB/GSM，DMF 的边际价值主要是
    "端点约束下的连续路径表述"和对**端点几何质量不敏感**。建议列为**第二阶段可选项**，
    不进 MVP。
    **Support：** researcher inference。**Confidence：** medium。

---

### 4. Scan：rigid vs relaxed、约束施加方式与失效模式

56. **Claim：** **relaxed scan 就是"约束优化"**：在扫描点 n 上求解
    `min_{q'} E(q_n, q')`，s.t. `q = q_n`；其驻点条件由 Lagrange 乘子 λ 给出
    （文献把 Gaussian 的 scan 明确表述为"constrained optimization with a Lagrange
    multiplier"）。
    **Sources：** <https://theochem.cc/software/gaussian/scan/mathematics/constrained-optimization/>。
    **Support：** direct evidence（该文是对 Gaussian 机制的整理；**非 Gaussian 官方文档**，
    需注意其二手性质）。**Confidence：** medium。

57. **Claim（rigid scan 的官方定义）：** Gaussian 的 `Scan` = **rigid** PES scan，
    在选定内坐标的矩形网格上做**单点能**评价，且**分子结构必须用 Z-matrix 定义**；
    步数与步长写在变量定义行上。
    **Sources：** `gaussian.com/scan/`（搜索片段原文）。
    **Support：** direct evidence。**Confidence：** medium-high
    （正文页此次抓取失败，仅取到片段）。

58. **Claim（各代码的约束语法/实现）：**
    - Gaussian：`Opt=ModRedundant` + `ModRedundant` 段，动作码 `B/K/R/D/H/S`
      （`S nsteps stepsize` 为扫描），原子编号 + 类型码 + 参数。
    - ORCA：`%geom scan B 1 0 = 2.0, 1.0, 15 end`；`ScanTS` 会在**越过最高点后中止扫描**、
      取最高能量结构、算扫描坐标的二阶导、再做 TS 优化（`%geom fullScan true` 可关闭中止）。
    - ORCA 的**约束施加方式**：在冗余内坐标的 projector `P'` 上**再乘一个约束 projector C**
      （手册 Eq. 4.13："Constraints on the redundant internal coordinates can be imposed by
      modifying the above projector P' with a projector for the constraints C"）。
    - pysisyphus：`scan: type: BOND, indices: [i,j], start/end/steps/step_size`，
      支持 `symmetric` 双向扫描；实现为 1D relaxed scan。
    - Sella：支持 constrained optimization（其论文摘要明确提及，并用于 relaxed scans 与
      dummy atoms 的约束补偿）。
    **Sources：** `gaussian.com/modred/`（片段）；ORCA 6.1 §4.3.2 + §4.1.3.3；
    pysisyphus scans 文档 <https://pysisyphus.readthedocs.io/en/latest/scans.html>；
    Sella 论文摘要（chemrxiv 2022-44r17）。
    **Support：** direct evidence。**Confidence：** high（ORCA projector 与 pysisyphus）；
    medium（Gaussian 语法，来自片段）。

59. **Claim（Lagrange 乘子 vs 力投影）：** ORCA 走"**投影子**"路线（在笛卡尔/内坐标步上
    投影掉被约束方向），这等价于在约束流形上做拟牛顿步；"λ 乘子"表述则出现在把 relaxed scan
    当约束优化的教学文献里。**两者在实现上可互推**（投影子是约束 Jacobian 的零空间投影，
    multiplier 是用于消去约束力的对偶变量）。
    **Sources：** ORCA Eq. 4.13（投影子）；theochem.cc（Lagrange 表述）。
    **Support：** source interpretation（"可互推"是研究者推断）。
    **Confidence：** medium。

60. **Claim（scan 的真实失效模式，有一手来源的三条）：**
    1. **滞回（hysteresis）与灾变点（catastrophe points）**：内旋转的 torsional potential
       若用 rigid rotation 会"anomaly free 但精度不足"；relaxed 路径在"其他自由度可低成本
       释放扭转张力"的体系里会出现灾变点与**滞回环**——即正向/反向扫描得到不同曲线。
    2. **自洽 PES 的间断**：SCF 解的不连续会产生 **fake saddle points**（在更大的约束子空间
       里不再是鞍点）与 **missing saddle points**（轨迹上消失）。
    3. **坐标定义漂移/不连续**（研究者推断，配合 (1)(2)）：当"扫描坐标"在某个区间与其他内坐标
       发生强耦合（键断裂/形成、二面角穿越 0/180°），约束方向本身会跳变 → 曲线出现不连续。
    **Sources：** (1) "Catastrophes, bifurcations and hysteretic loops in torsional potentials
    of internal rotations in molecules"（来源摘要，检索条目）；
    (2) arXiv:1112.4196 "Numerical search of discontinuities in self-consistent potential
    energy surfaces" <https://ar5iv.labs.arxiv.org/html/1112.4196>。
    **Support：** direct evidence（(1)(2)）；researcher inference（(3)）。
    **Confidence：** high（(2)）；medium（(1)，只有摘要级证据）；medium（(3)）。

61. **Claim（研究者推断，工程建议）：** 我们的 scan 必须提供
    (a) **双向（forward+backward）扫描**并显式报告滞回；
    (b) 每个扫描点从**前一个点的优化结果**热启动几何（避免跨 basin 跳变）；
    (c) 用**约束力残差**（`|∂E/∂q - λ|`，即约束坐标上的残余梯度）作为每个点的收敛证据；
    (d) 对 xtb 而言，扫描过程中**关闭/固定 restart**（见 §8）以保证同一点的可复现性。
    **Support：** researcher inference。**Confidence：** medium-high。

---

### 5. 收敛判据的"真实代码数值"对照表

62. **Claim（xtb，8 档，只有 2 个判据）：**
    | level | Econv / Eh | Gconv / Eh·α⁻¹ | Accuracy |
    |---|---|---|---|
    | crude | 5e-4 | 1e-2 | 3.00 |
    | sloppy | 1e-4 | 6e-3 | 3.00 |
    | loose | 5e-5 | 4e-3 | 2.00 |
    | lax | 2e-5 | 2e-3 | 2.00 |
    | **normal（默认）** | 5e-6 | 1e-3 | 1.00 |
    | tight | 1e-6 | 8e-4 | 0.20 |
    | vtight | 1e-7 | 2e-4 | 0.05 |
    | extreme | 5e-8 | 5e-5 | 0.01 |

    ANCopt setup 里还打印：`max. RF displ. = 1.0`、`Hlow = 0.02`、`Hmax = 5.0`、
    `S6 in model hess. = 20.0`、`ANC micro-cycles = 20`、`max. optcycles` 自动为 200..10000
    （`--cycles` 可覆盖）。**xtb 没有 max force / RMS force / max-RMS displacement 判据**，
    只有"能量变化 + 梯度范数"。`--opt engine=rf|lbfgs`（6.1.4 起）。
    **Sources：** xtb 文档 <https://xtb-docs.readthedocs.io/en/latest/optimization.html>；
    本地代码 `src/type/setvar.f90:74-99`（`optlev` / `micro_opt` / `maxoptcycle` /
    `maxdispl_opt` / `hlow_opt` / `exact_rf` / `average_conv`）。
    **Support：** direct evidence。**Confidence：** high。
    **对本项目的含义（研究者推断）：** 若我们的 `opt/ts/irc` 采用 Gaussian 式四判据，
    必须**自己从 xtb 的梯度算 max/RMS**，不能依赖 xtb 的 ANCopt 收敛逻辑。

63. **Claim（Gaussian 默认 opt 判据，数值）：**
    Max Force 0.000450、RMS Force 0.000300、Max Displacement 0.001800、RMS Displacement 0.001200
    （Ha/Bohr、Bohr）。`Opt=Tight` 收紧这些 cutoff，且文档建议 DFT 配 `Int=UltraFine`；
    对低频模体系，tight 是"确保后续频率可靠"的手段。
    **Sources：** `gaussian.com/faq3/` 的实际输出示例（搜索服务返回的原文，含
    "Maximum Force 0.000038 0.000450 YES" 等四行）；`gaussian.com/opt/` 片段
    （"This option tightens the cutoffs on forces and step size"）。
    **Support：** direct evidence（默认四阈值）；**Tight/VeryTight 的具体数字未取到**
    （见 Missing evidence）。
    **Confidence：** medium-high（默认值）；low（tight 数值）。

64. **Claim（ORCA 6.1 Table 4.1，四档完整数值）：**

    | 变量 | Loose | **Normal(默认)** | Tight | VeryTight |
    |---|---|---|---|---|
    | TolE / a.u. | 3e-5 | 5e-6 | 1e-6 | 2e-7 |
    | TolMaxG / a.u. | 2e-3 | 3e-4 | 1e-4 | 3e-5 |
    | TolRMSG / a.u. | 5e-4 | 1e-4 | 3e-5 | 8e-6 |
    | TolMaxD / a.u. | 1e-2 | 4e-3 | 1e-3 | 2e-4 |
    | TolRMSD / a.u. | 7e-3 | 2e-3 | 6e-4 | 1e-4 |

    另：`MaxStep=0.3` au（内坐标最大步长）、`Trust=-0.3`（固定 trust radius 0.3 au）、
    `Step=qn|rfo|prfo`（`rfo` 是 `!Opt` 默认，`prfo` 是 `!OptTS` 默认）。
    **Sources：** ORCA 6.1 Manual §4.1（Table 4.1、Table 4.3 原文）。
    **Support：** direct evidence。**Confidence：** high。

65. **Claim（Q-Chem）：** `GEOM_OPT_TOL_GRADIENT` 默认 **300**（即最大梯度分量阈值
    300×10⁻⁶ = 3e-4）；`$geom_opt GRADIENT_CONVERGENCE` 默认 **3e-4**；
    `CONVERGENCE_CHECK` 默认 DEFAULT = "检查最大梯度分量 与（最大位移 或 能量变化）"，
    也可选 Energy / Gradient(norm)。必须"TOL_GRADIENT 与 (TOL_DISPLACEMENT 或 TOL_ENERGY)
    之一同时满足"。
    **Sources：** Q-Chem 6.4/7.0 手册 §9.2.2 / §9.2.5
    <https://manual.q-chem.com/6.4/topic_ts_Job-Control-Optimize.html>、
    <https://manual.q-chem.com/latest/topic_ts_Job-Control-Libopt3.html>。
    **Support：** direct evidence（梯度值）；**TOL_DISPLACEMENT/TOL_ENERGY 的默认数字未取到**。
    **Confidence：** high（梯度）；low（其余两项默认值）。

66. **Claim（ORCA 的 IRC 默认值——注意 ORCA 用的是 Morokuma 式方法，不是 GS/HPC/LQA）：**
    `%irc MaxIter 20`（默认）、`Direction both`（默认）、`hessMode 0`（用于初始位移的 Hessian 模）、
    `Scale_Init_Displ 0.1`（a.u.，默认初始位移步长）、`DE_Init_Displ 2.0`（默认预期 2 mEh 能量变化）、
    `Follow_CoordType cartesian`（默认且唯一选项）、`Scale_Displ_SD 0.15`、
    `Adapt_Scale_Displ true`、`SD_ParabolicFit true`、`Interpolate_only true`、
    `Do_SD_Corr true`、`Scale_Displ_SD_Corr 0.333`、`SD_Corr_ParabolicFit true`；
    自适应规则：整体步长 < 0.5×Scale_Displ_SD 则 ×0.5；> 2× 则 ×2；
    Scale_Displ_SD 不得小于初值的 1/16、不得大于 4 倍。
    **Sources：** ORCA 6.1 §4.4（原文）。
    **Support：** direct evidence。**Confidence：** high。

67. **Claim（IRC "tight vs default" 的推荐值——**没有统一标准**，只能给经验合成）：**
    - 步长：Gaussian 默认 0.10 amu^1/2 bohr（= `StepSize=10`）；HPC 论文 0.10 是 LQA 的
      "practical upper limit"、HPC 可到 0.40；EulerPC 用 0.10 为"accepted upper limit"；
      MAPLE 默认 `step_length_bohr=0.10`；ORCA 的 `Scale_Displ_SD` 体系等价量是 0.15 au。
      → **推荐默认 0.10 a.u.(=bohr·amu^1/2)，tight 用 0.05**。
    - 力收敛：MAPLE GS/HPC/EulerPC 用 `f_rms_th=5e-4`、`f_max_th=2e-3` **Hartree/Bohr**
      （对 ML 势的单位体系）；换成 xtb 的 `Eh/α` 同样适用（1 α = 1 bohr）。
      → **推荐 tight 用 RMS 5e-4 Eh/a0（约 0.05 eV/Å 量级）。**
    - **质量加权约定：MWC Cartesian，1 a.u. = 1 bohr·amu^1/2**（HPC 论文原文），
      Gaussian 的 negative `StepSize` 也用 amu^1/2-Bohr。
    **Sources：** 见上引各条。**Support：** direct evidence（各代码数值）+ source interpretation
    （"推荐值"的合成）。**Confidence：** medium-high（数值属于证据；"推荐"是推断）。

68. **Claim（NEB 收敛：跨代码惯例）**：geomeTRIC 0.025(avg)/0.05(max) eV/Å；
    CI 切换 0.5 eV/Å（RMS）；VASP 用 `EDIFFG`（典型 -0.03 eV/Å）；ASE 示例用 `fmax=0.04`。
    **Sources：** 见 §3。**Support：** direct evidence（geomeTRIC/VASP 文档；ASE 是示例值）。
    **Confidence：** high（geomeTRIC）；medium（VASP/ASE 属惯例）。

---

### 6. Hessian 与频率：数值微分、投影、计数、缩放、热化学

69. **Claim（xtb 的数值 Hessian 约定——本地一手证据）：**
    - xtb 的频率"只能通过解析梯度的**两侧数值微分**得到"（文档原文：
      "Vibrational frequency calculations are available only through two-sided numerical
      differentiation of analytical gradients."）。
    - 位移步长默认 **`step_hess = 0.005_wp`（bohr，Cartesian increment）**
      → `src/type/setvar.f90:158`（同一 type 内 `accu_hess = 0.3_wp` 在 `:156`）。
    - **Hessian 运行时 SCC 精度被放宽为 0.3**（而不是 1.0 的收敛 SCF）；
      `numhess` 结束后才把 `calc%accuracy = set%acc` 复位（`src/hessian.F90:271` 附近）。
    - 数值 Hessian 由 `call calc%hessian(env, mol, chk0, indx, step, h, dipd)` 完成
      （`src/hessian.F90:223`、`:232`），并做对称化 `h(jj,ii)=0.5*(h(ii,jj)+h(jj,ii))`
      （`src/hessian.F90:291` 附近）。
    - 可配置项（xcontrol）：`$hess` 的 `step`（位移增量）、`scale`（Hessian 元素缩放，默认 1.0）、
      `sccacc`（Hessian 运行时的 SCC 精度）、元素质量覆盖 `element mass` / `scale mass`。
    **Sources：** 本地 `src/type/setvar.f90:154-159`（hessian_setvar）、`:165-169`（thermo_setvar）；
    `src/hessian.F90:223,232,271` 附近；xtb 文档
    <https://xtb-docs.readthedocs.io/en/latest/hessian.html>；
    `man/xcontrol.7.adoc`（`$hess` 参数）。
    **Support：** direct evidence。**Confidence：** high（本地行号已核对）。

70. **Claim（其他代码的数值频率步长，用于对照）：** ORCA `%freq` 支持 `CentralDiff true/false`
    （单侧 vs 两侧），并有 `NumFreq`；ASH 的 NumFreq 默认 `displacement=0.005`、`npoint=2`；
    Molpro `FREQUENCIES` 用"3N Cartesian 有限差分"（`STEP` 选项存在，具体默认值未取到）。
    **Sources：** ORCA 6.1 §4.6 <https://orca-manual.mpi-muelheim.mpg.de/contents/structurereactivity/frequencies.html>；
    ASH 文档 <https://ash.readthedocs.io/en/latest/module_freq.html>；
    Molpro 手册 <https://www.molpro.net/manual/doku.php?id=harmonic_vibrational_frequencies_frequencies>。
    **Support：** direct evidence。
    **Confidence：** high（0.005 这个量级在 xtb/ASH 都出现）；medium（Molpro 细节）。

71. **Claim（投影平动/转动）：** 主流做法是用 **Eckart 投影**把平动/转动分量从 Hessian 中投掉，
    然后再对角化；分子振动的 3N-6（非线性）/ 3N-5（线性）个内自由度来自
    `R^{3N} = R_ext ⊕ R_int` 的正交直和分解。
    xtb 打印的例子对 CH3OH 类 7 原子体系给出 21 个频率，其中 **6 个恒为 0**，
    文档明说这些零值"已从 Hessian 中投影掉，零值本身不代表 Hessian 质量"。
    **Sources：** NWChem Hessians 页（"VIB module projects out the translations and rotations
    of the nuclear hessian using the standard Eckart projection algorithm"）；
    Eckart conditions（Wikipedia）；
    xtb hessian 文档（"They have been projected out of the Hessian before the calculation of
    the frequencies"）。
    **Support：** direct evidence。**Confidence：** high。

72. **Claim（质量加权与输出）：** xtb 频率来自质量加权 Hessian 的对角化，
    打印 `reduced masses (amu)`、`IR intensities`、`Raman intensities`，
    写 `g98.out`（Molden 可读）和 **Turbomole 格式的 `hessian` 文件（已投影、已质量加权）**；
    `xtb thermo` 子模块可以读**非质量加权的、已投影的 Turbomole Hessian**（默认格式），
    也可用 `--orca` / `--turbomole` 指定来源。
    **Sources：** xtb hessian 文档；xtb thermo 文档
    <https://xtb-docs.readthedocs.io/en/latest/xtb_thermo.html>。
    **Support：** direct evidence。**Confidence：** high。

73. **Claim（GFN2-xTB 的频率缩放因子）：** xtb 自己在频率输出末尾打印
    "**recommended (thermochemical) frequency scaling factor: 1.0**"，
    且 thermo SETUP 里 `scaling factor 1.0000000` → **xtb 官方推荐不做全局缩放**。
    文献层面：GFN 族 IR 谱评测论文（Bursch 等）讨论了 GFN1/GFN2-xTB 的谱相似度与
    "用**原子质量缩放**替代全局频率缩放"这一替代方案，并指出 FF 方法因已经验拟合而
    "全局缩放几乎无影响"，但**我未能从可访问页面取到 GFN2-xTB 的数值缩放因子**。
    **Sources：** xtb hessian 文档（1.0 的原文打印）；
    <https://pmc.ncbi.nlm.nih.gov/articles/PMC8378236/>（Abstract/§4.1 片段）。
    **Support：** direct evidence（1.0）；**数值 scale factor → missing evidence**。
    **Confidence：** high（"xtb 推荐 1.0"）；low（"文献给出的 GFN2 缩放因子"，未取到）。

74. **Claim（热化学 RRHO / quasi-harmonic）：**
    - **xtb**：用"coupled rigid-rotor-harmonic-oscillator"；默认 **rotor cutoff = 50 cm⁻¹**
      （`thermo_sthr = 50.0_wp`，注释注明"When was 100 cm-1 previously" →
      `src/type/setvar.f90:167-168`）；imag cutoff = **-20 cm⁻¹**；
      自动检测对称性并给出 rotational number（可被 `$symmetry` 覆盖）；
      温度默认 **298.15 K**（`therm_temp(50)`，`src/type/setvar.f90:166`），
      可用 `$thermo temp=150,200,...`；`xtb thermo` 子模块用 **mRRHO**，
      `--sthr REAL` 可调 rotor cutoff。
    - **ORCA**：默认用 **quasi-RRHO（Grimme）** 处理低频熵贡献，可用关键字关闭。
    **Sources：** xtb hessian 文档（SETUP 打印与温度）；xtb thermo 文档（mRRHO, --sthr）；
    本地 `src/type/setvar.f90:165-169`；ORCA 6.1 §4.7
    <https://www.faccts.de/docs/orca/6.1/manual/contents/structurereactivity/thermochemistry.html>。
    **Support：** direct evidence。**Confidence：** high。

75. **Claim（研究者推断）：** 对我们套件的直接含义：
    - 频率的**数值噪声下限由 Hessian 步长与 SCF 精度共同决定**：xtb 用 0.005 bohr 与
      accu_hess=0.3 是"为了速度牺牲精度"的组合；若我们的 `freq` 要与解析 Hessian 代码对齐，
      应至少提供 `step`、`sccacc` 两个可调旋钮，并**默认比 0.3 更紧**（例如 1.0/0.5），
      否则虚频个数与数值会不稳。
    - 必须自建 **Eckart 投影 + 3N-6/3N-5 计数 + 线性分子检测**；不能依赖 xtb 的输出
      （xtb 只给已投影的 Hessian 与频率列表）。
    **Support：** researcher inference。**Confidence：** medium-high。

---

### 7. 现有实现调研（可学到什么 / 能否复用代码）

| 项目 | 语言 | 许可 | 实现了什么 | 坐标系 | 能否复用代码 |
|---|---|---|---|---|---|
| **DL-FIND / libdlfind** | **Fortran** | **LGPL-3.0**（源码头明写） | P-RFO（Powell 或 **Bofill** 更新）、Dimer、NEB、TS/反应路径、圆锥交叉、全局优化；"optimizer is fully restartable" | 内坐标+Cartesian（库自带） | **最值得考虑复用**：唯一"Fortran + LGPL-3.0 + 与 xtb 同许可"的组合，已有 `libdlfind`（可嵌入的 API 版）；能量/梯度通过外部回调 |
| **pysisyphus** | Python | **GPL-3.0** | RS-P-RFO（默认）/RS-I-RFO/TRIM、Dimer（PLBFGS 预条件）、NEB(+CI/adaptive/free-end)、GSM(含内坐标)、SZTS、IRC；提供 **xtb calculator** | redund/DLC 内坐标、Cartesian | 算法参考价值最高（文档写实现细节）；**GPL-3.0 与 LGPL 混用需谨慎**（不能把 GPL 代码抄进 LGPL 程序） |
| **geomeTRIC** | Python | "Other"（GitHub 标注，非标准 GPL/MIT） | TRIC 内坐标、min/TS/constrained/NEB(+CI)/MECI | **TRIC**（显式含平动转动） | 许可不清 → 不建议抄代码；**TRIC 思路**可参考 |
| **Sella** | Python（含 C 扩展） | **LGPL-3.0** | 用冗余内坐标的 TS 优化、dummy atom 处理线性角、**受约束优化**、迭代 eigensolver + 有限差分 Hessian-向量积；"multi-secant TS-BFGS" 更新；trust radius 形式对不定 Hessian 也有效 | 冗余内坐标 | 许可与 xtb 兼容（LGPL-3.0）；但**Python**，只能学算法；其"每步只做 Hessian-vector product"的思路对 GFN2 很省 |
| **ASE** | Python | LGPL-2.1+ | NEB/CI-NEB/**AutoNEB**/Dimer（MinModeAtoms/DimerControl）、各类 optimizer、`ase.vibrations`（数值 Hessian） | Cartesian | 只能学算法；但**默认值/接口约定**可直接对齐（k=0.1 eV/Å、fmax 惯例、`remove_rotation_and_translation`） |
| **ORCA** | 闭源 | 商业/学术许可 | P-RFO（Baker）、IRC（Morokuma 式）、ScanTS、NEB-TS、AnFreq/NumFreq、quasi-RRHO | redund 内坐标（LC/DC） | 只能学（**手册是公开的最佳公式来源**） |
| **Gaussian 16** | 闭源 | 商业 | Berny/EF、IRC(HPC/EulerPC/LQA/DVV/Euler)、SCAN/ModRedundant、Freq | redund 内坐标、Z-matrix（scan） | 只能学 |
| **CFOUR** | Fortran | 学术许可（非自由） | 自带 TS/IRC/频率 | — | **不能复用**（许可） |

**Sources：** DL-FIND 页 <https://www.chemshell.org/dl-find/> 与
<https://www.itheoc.uni-stuttgart.de/research/kaestner/research/dlfind/>；
libdlfind 源码头（LGPL-3.0）<https://github.com/digital-chemistry-laboratory/libdlfind/blob/main/src/dlf_global_module.f90>、
<https://github.com/digital-chemistry-laboratory/libdlfind/blob/main/src/api.f90>；
pysisyphus <https://github.com/eljost/pysisyphus>（GPL-3.0）与文档 overview/TS/COS；
geomeTRIC <https://github.com/leeping/geometric>；
Sella <https://github.com/zadorlab/sella> 与 PyPI（LGPL-3.0）；
ASE NEB 文档；xtb issue #494（官方推荐 sella/molecularGSM）。
**Support：** direct evidence（语言/许可/功能）。
**Confidence：** high（许可与功能）；medium（"能否复用"的结论，见下面 76）。

76. **Claim（研究者推断，许可证层面的关键结论）：**
    xtb 是 **LGPL-3.0-or-later**（`src/iniq.f90:1-18` 等文件头），
    DL-FIND 与 libdlfind 是 **LGPL-3.0**，Sella 是 **LGPL-3.0** →
    这三者在 LGPL 体系内互相链接是**许可兼容**的路线；
    pysisyphus(GPL-3.0)、geomeTRIC(非标准) 的**代码**不宜并入；ASE(LGPL-2.1+) 作为
    **测试/交叉验证工具**（而不是被链接）最合适。
    建议的验证路径：**先用 ASE+pysisyphus 的既有实现（它们都有 xtb calculator）
    生成 GFN2-xTB 的金标准轨迹，再拿我们的 Fortran 实现去逐点比对**，
    而不是直接搬运 Python 代码。
    **Support：** researcher inference（基于各仓库 README/源码头）。**Confidence：** medium-high
    （许可事实 high；"是否要在法律上走 LGPL 混合"需项目方决策）。

---

### 8. 半经验（GFN2-xTB）引擎驱动这些算法的陷阱——哪些是真的

77. **Claim（真实 #1：Hessian 的有限差分噪声源于故意放宽的 SCF 精度）：**
    xtb 的 Hessian 运行用 `accu_hess = 0.3`（`src/type/setvar.f90:156`），
    即**在 Hessian 的每个位移点上 SCF 并没有被收敛到生产精度**；
    文档也承认频率**只能靠两侧数值微分**。
    **Sources：** 本地 `src/type/setvar.f90:154-159`；xtb hessian 文档；
    `man/xcontrol.7.adoc`（`$hess sccacc`）。
    **Support：** direct evidence。**Confidence：** high。
    **含义（研究者推断）：** 一步 `--hess` 就有 6N 次"半收敛"SCF，
    因此 **Hessian 本征值（尤其低频/虚频）会随 `sccacc`、`step`、乃至 restart 状态漂移**；
    TS 优化若每步重算 Hessian，会把这些噪声注入 λ_p/λ_n 与模态选择。

78. **Claim（真实 #2：Grimme 组自己承认 GFN PES 数值有噪声）：**
    xtb 的 ANCopt 提供 `average_conv`（"average the energy and gradient before checking for
    convergence to accelerate numerically noisy potential energy surfaces"，默认 **false**），
    并在 `src/type/setvar.f90:95-97` 有同义注释。
    **Sources：** 本地 `src/type/setvar.f90:95-97`；`man/xcontrol.7.adoc`（`average conv`）。
    **Support：** direct evidence。**Confidence：** high。
    **含义：** "GFN2 的梯度噪声会干扰步长控制/收敛判定"是**被上游代码结构证实的**，
    不是社区传说。

79. **Claim（真实 #3：重复调用之间并非天然 bitwise 可复现——restart 会隐式继承波函数）：**
    xtb 的 `TRestart` 机制会把上一次的波函数/占据数带入下一次计算；官方 issue #1378
    "Restart information always implicitly used" 报告：**连续两次 `singlepoint` 会用上
    restart 信息，导致梯度与首次调用不同**，且用户无法直观知道 restart 来自哪里；
    `src/restart.f90` 提供 `readRestart/writeRestart`，`src/xtb/calculator.f90` 的
    `singlepoint(..., restart, ...)` 带 restart 开关。
    **Sources：** <https://github.com/grimme-lab/xtb/issues/1378>（issue 原文）；
    <https://github.com/grimme-lab/xtb/blob/293469d4/src/restart.f90>；
    <https://github.com/grimme-lab/xtb/blob/293469d4/src/xtb/calculator.f90>。
    **Support：** direct evidence（issue 与源码）。
    **Confidence：** high。
    **含义（研究者推断）：** 我们的 IRC/NEB/Hessian 驱动器若复用同一个 `TxTBCalculator`
    实例，**必须显式控制 restart**：要么每次传"零 restart"（`--norestart` 语义），
    要么把 restart 作为几何的函数缓存。否则"同一个几何两次给不同梯度"（差异量级取决于 SCF
    收敛阈值），会直接破坏有限差分 Hessian 的对称性和信赖域判据。

80. **Claim（初始猜测链：几何决定论但 restart 破坏决定论）：**
    初始电荷来自 `iniq.f90` 的 Grimme–Gasteiger 变体（vTB / GFN1 / GFN2 三种，
    按 `version` 选择，见 `src/iniq.f90:60-80` 的 `iniqcn`），SAD/EEQ 猜测在
    `src/setparam.f90`（`p_guess_sad/gasteiger/goedecker/multieq`）与 `src/prog/main.F90` 中初始化。
    即：**给定几何 → 猜测是确定的**；不确定性来自 restart 继承与 SCF 迭代路径。
    **Sources：** 本地 `src/iniq.f90:27-90`；
    <https://github.com/grimme-lab/xtb/blob/293469d4/src/setparam.f90>；
    <https://github.com/grimme-lab/xtb/blob/293469d4/src/prog/main.F90>；
    `man/xcontrol.7.adoc`（`$scc` / `$scf`、`guess` 选项）。
    **Support：** direct evidence（猜测类型与机制）+ researcher inference（"几何决定论"的推论）。
    **Confidence：** medium-high。

81. **Claim（真实 #4：默认设置里就有影响曲率的"物理参数"）：**
    `scc_setvar` 的默认电子温度 `etemp = 300.0 K`（Fermi smearing）与
    Broyden 阻尼 `broydamp = 0.40`；文档另注 `sccmd < 5`、`broydamp` 在关键体系应取 0.05，
    且 `etemp` 会改变占据数与能量。
    **Sources：** 本地 `src/type/setvar.f90`（scc_setvar，约 `:61-70`）；
    `man/xcontrol.7.adoc`（`$scc temp/etemp`、`broydamp`、`$scc sccacc`）。
    **Support：** direct evidence（默认值存在）。
    **研究者推断：** 因为 **Fermi smearing 直接改变电子能量关于核坐标的二阶导**，
    所以"etemp 影响 Hessian 曲率/虚频位置"在理论上是必然的；
    但**没有找到 xtb 文档明确说这句话** → 标为 inference，需要用小分子实验证（见 §9）。
    **Confidence：** medium-high（推断）；high（参数默认值存在）。

82. **Claim（level shifting / damping 与曲率）：** xtb 的 SCC 里有 level-shift 通道
    （`scc_core.f90` 的 `shellShift`/`externShift` 形参），外部包装（Qcore）暴露
    `level_shift` / `remove_level_shift`（默认 0 / true）；xtb 官方 xcontrol 文档里
    与之对应的是 `$scc` 的 Broyden 阻尼与 `$scf` 相关项。
    **Sources：** <https://github.com/grimme-lab/xtb/blob/293469d4/src/scc_core.f90>；
    `man/xcontrol.7.adoc`；Qcore xtb 文档
    <https://software.entos.ai/qcore/documentation/commands/xtb/>。
    **Support：** direct evidence（参数存在）。
    **研究者推断：** "level shifting/damping 改变曲率"= 因为任何改变 SCF 解/能量的设置都会
    改变 E(x) 的二阶导；但**没有直接文献量化 xtb 的效应**。→ 必须做数值实验。
    **Confidence：** medium（推断）。

83. **Claim（xtb 的能力边界——必须先确认，否则整个 ts/irc 设计要重排）：**
    - **xtb 没有 TS 优化器**：维护者在 issue #494 中明确回答
      "**xtb does not implement a transition state optimizer**"，并给出替代方案
      （molecularGSM + xtb standalone；Sella + xtb-python/ASE 接口）。
    - **xtb 没有 IRC 关键字**（`xtb.1.adoc` 中没有 `--irc`）。
    - xtb 的"反应路径"是 **RMSD push/pull metadynamics pathfinder**（`--path`，
      `$path` 的 `nrun/npoint(或 nopt)/anopt/kpush/kpull/ppull/alp`；
      默认见 `src/type/setvar.f90` 的 `path_setvar`: `nrun=3, nopt=50, anopt=3,
      kpush=0.05, kpull=-0.04, alp=0.70, ppull=0.05`），
      并与 **Grimme 2019 JCTC 15, 2847** 的 metadynamics 工作相关；文档自己说它
      "usually faster than NEB/GSM but might not be as reliable"。
    - xtb 的 `--modef`（normal mode following）是**最接近 TS 搜索**的自带功能
      （`modef_setvar`: `nscan=31, step=1.0, updat=0.2, local=0, vthr=0.0, prj=0,
      follow=7`），用于模式跟随/构象搜索，**但它不是 P-RFO**。
    **Sources：** <https://github.com/grimme-lab/xtb/issues/494>（**一手官方回答**）；
    <https://github.com/grimme-lab/xtb/blob/master/man/xtb.1.adoc>；
    xtb 文档 <https://xtb-docs.readthedocs.io/en/latest/path.html>；
    本地 `src/type/setvar.f90`（path_setvar / modef_setvar）。
    **Support：** direct evidence。**Confidence：** high。
    **含义（研究者推断）：** 因此 `ts / irc` 必须是**我们新写**的，而不是"给 xtb 加个开关"；
    好处是 xtb 提供干净的"能量+梯度"回调（`calc%singlepoint`），
    坏处是**任何依赖 xtb 内部 ANC 坐标/模型 Hessian 的捷径都要自己重建**。

84. **Claim（`--norestart` / `xtbrestart` 与我们的驱动器的交互）：**
    xtb 命令行有 restart 相关开关与 `xtbrestart` 文件；在库/API 层，
    restart 是**显式形参**（`singlepoint(..., restart, ...)`）而 issue #1378 表明
    "高层包装（`TxTBCalculator`）会隐式使用 restart"。
    **Sources：** = 第 79 条的来源；另见 <https://github.com/grimme-lab/xtb/issues/348>
    （mdrestart 语义不清的讨论）。
    **Support：** direct evidence（issue 与源码）。**Confidence：** high。
    **研究者推断：** 设计中应提供三种模式并强制显式：
    `restart=off`（每点独立，用于 Hessian/IRC 的确定性）、
    `restart=warm`（沿用上一点波函数，用于 opt/NEB 的加速）、
    `restart=pinned`（固定某个参考几何的波函数，用于 scan 的一致性）。
    默认值建议 `off` 或 `pinned`，并把该选择写进输出以便复现。

85. **Claim（成本量级，用于容量规划）：** xtb 的一次能量+梯度是主要成本；
    - IRC：GS 每点 3–5 次 E/g（原文），HPC/EulerPC 每点 ~1 次（原文）；
    - CI-NEB：每轮 (N_images)×1 次 E/g；
    - Dimer：每轮 1 次 E/g × (1 旋转 + 1 平移)，典型 ~400 次力评价（原文）；
    - Hessian：6N 次 E/g（两侧数值微分，xtb 文档与实现）。
    **Sources：** 278.pdf / 345.pdf / henkelman99_7010.pdf / xtb hessian 文档。
    **Support：** direct evidence。**Confidence：** high。

---

### 9. Open questions / 必须先"去风险"的测试清单

按优先级排列（每条给出最小验证实验）：

1. **xtb 反复调用的确定性（最高优先）。**
   同一几何、同一波函数初猜下，连续 N 次 `singlepoint` 的能量与梯度是否 **bitwise 相同**？
   分别在 `restart=off` / 复用同一 `TRestart` 两种模式下测。
   → 若不同，量化差异（Eh/bohr），并与我们的力收敛阈值比较。
   （依据：issue #1378。）
2. **Hessian 步长与 sccacc 的敏感性。**
   对 H2O / CH3OH / 一个 TS（如 HCN→HNC），扫 `step_hess ∈ {0.002, 0.005, 0.010}`
   与 `sccacc ∈ {0.3, 0.1, 1.0}`，报告频率、最小本征值、虚频个数的漂移。
   → 决定我们 `freq` 的默认值是否要偏离 xtb 的 0.005/0.3。
3. **etemp（Fermi smearing）对曲率的影响。**
   `etemp ∈ {0, 300, 1000, 5000} K`（xtb 默认 300）下对同一分子做 Hessian，
   比较最低 3 个本征值。
   → 若影响显著，`ts/irc` 必须把 etemp 冻结并在输出中记录。
4. **梯度噪声 vs trust radius 的下确界。**
   测 xtb 梯度的"重复性噪声" σ_g，然后要求 trust radius 的力判据 ≥ 10σ_g；
   → 给出我们 TS/IRC/NEB 力收敛阈值的**可达到下限**。
5. **P-RFO 在 GFN2 上的模态跟随。**
   对 3–5 个已知 TS（SN2、HCN→HNC、Diels–Alder），用我们实现 vs
   Sella/pysisyphus(+xtb calculator) 对比：收敛代数、最终 TS 几何 RMSD、
   虚频个数与数值。→ 校验 prim_coord/overlap 选模与 λ 求解。
6. **IRC 四算法在 GFN2 上的互校。**
   同一 TS 用 GS / HPC / LQA / EulerPC 跑 forward+backward，
   比较端点几何、端点能量、以及"落在哪个极小点"（RMSD 到优化后的 R/P）。
   → 若某算法在 GFN2 上系统性偏差，需要在文档里降级它。
7. **IRC 端点判据的标定。**
   以 Gaussian/ORCA 的默认点数（MaxPoints=10, MaxIter=20）为参照，
   测我们的自动终止判据是否会在相同 s 处停下来。
8. **CI-NEB 的 climbing 切换阈值。**
   geomeTRIC 用 0.5 eV/Å（RMS）切 CI；在 xtb 的噪声水平下，
   0.5 eV/Å 是否会被噪声误触发？→ 测切换点前后的能量曲线。
9. **DMF 的可行性（若纳入范围）。**
   评估 IPOPT 作为 Fortran/C 依赖的引入成本；用 PyDMF 对同一体系跑一遍，
   再用我们的能量回调替换，比较路径 t_max 位置与几何。
   核心问题：**DMF 相对 CI-NEB 是否有实质增量收益**。
10. **DL-FIND 复用性（法律 + 技术）。**
    确认 libdlfind 的 API 能否接受"外部能量/梯度回调"、能否在 LGPL-3 下与 xtb 同进程链接；
    以及在 GFN2 噪声下其 P-RFO/Dimer 是否需要关掉内部 Hessian 更新。
11. **Rigid vs relaxed scan 的滞回量化。**
    对一个二面角做双向扫描，报告正向/反向 E(q) 的最大差异与不连续点位置；
    → 决定 scan 是否必须默认双向。
12. **线性分子 / 3N-5 情形。**
    用 CO2 / 乙炔验证我们的频率计数、Eckart 投影与转动配分函数是否正确
    （xtb 自己输出 `linear?` 标志）。

---

## Contradictions

1. **"dimer separation" 的定义互相矛盾（同名不同义）。**
   VASP：`DdR = 5E-3` 是"**twice** the distance between images"（即两像间距）；
   pysisyphus：`length = 0.0189` 是"separation of dimer images from the **common midpoint**"；
   原文 Henkelman 1999 用 `ΔR = 10⁻² Å` 且 `C=(E2-E0)/(ΔR)²`。
   → 三个数值看起来差 2 倍以上，**实际是定义差异**。
   [VASP](https://theory.cm.utexas.edu/vtsttools/dimer.html)、
   [pysisyphus](https://pysisyphus.readthedocs.io/en/latest/tsoptimization.html)、
   [Henkelman 1999](https://theory.cm.utexas.edu/henkelman/pubs/henkelman99_7010.pdf)。

2. **NEB spring constant：** "k 可以变化几个数量级而不影响 band 平衡位置"（Henkelman 2000）
   vs VASP 的"不要用过大 SPRING，否则妨碍收敛"。
   两者指的是 equilibrium spacing vs convergence rate，但**在默认值选择上会给出相反直觉**。
   [Henkelman 2000](https://theory.cm.utexas.edu/henkelman/pubs/henkelman00_9978.pdf)、
   [VASP Wiki](https://vasp.at/wiki/Nudged_elastic_bands)。

3. **"LQA" 的谱系归属：** HPC/Gaussian 把 LQA 归给 **Page & McIver**；
   而 Eckert & Werner 的同一名字段落描述的其实是 **Sun–Ruedenberg 的 QSD**
   （三个点 p/x/r 的区分），并只把 Page–McIver 列为"prior LQA implementations"。
   → 引用 "LQA" 时必须写明是哪一个公式，否则会实现成另一种算法。
   [278.pdf](http://schlegelgroup.wayne.edu/Pub_folder/278.pdf)、
   [eck-w98.pdf](https://www.math.u-szeged.hu/~stacho/eck-w98.pdf)。

4. **IRC 步长"标准值"：** 0.05（GS 原文测试）/ 0.10（Gaussian 默认、MAPLE 默认、
   EulerPC "accepted upper limit"、"LQA practical upper limit"）/ 0.20（GS 论文也用过、LQA 勉强）/
   0.40（HPC 论文认为可行）。
   → 不存在单一"标准步长"，它是**算法相关**的。

5. **xtb 是否具备 TS/路径能力：** 官方 issue 回答 "xtb does not implement a transition state
   optimizer"（2021 语境）↔ xtb 文档与代码里存在 `--path`（RMSD push/pull metadynamics）与
   `--modef`（模式跟随）。二者不矛盾（是不同功能），但**容易被误读为 xtb 有 TS 搜索**。
   [issue #494](https://github.com/grimme-lab/xtb/issues/494)。

6. **"P-RFO 的默认 Hessian 更新"：** pysisyphus 明说 `hessian_update: bofill`
   "Should not be modified for TS optimizations"；MAPLE 也说默认 `bofill`；
   但 EulerPC 论文同时测过"每 2/5/10 步用解析 Hessian 替换更新 Hessian"，
   说明**定期重算优于纯更新**。→ "bofill 是好的更新" 与 "应该定期重算" 并存，
   不冲突但优先级需要项目方定。

---

## Missing evidence

- **Page & McIver (1988) LQA 的原始更新公式**：只取到它的"地位"（被 HPC/Gaussian 引用）
  与 Sun–Ruedenberg 的 QSD 导出，**没有取到 Page–McIver 原文的方程**。
- **Baker 1986 P-RFO 原文的位移缩放/trust radius 具体公式**：Wiley 全文不可达；
  ORCA 的 `MaxStep=0.3 au`、`Trust=-0.3` 是"另一个实现"的默认值，不等于 Baker 原文数值。
- **Gaussian `Opt=Tight` / `Opt=VeryTight` 的四个数值**：`gaussian.com` 502，
  未能从可访问的一手页面确认（社区常引 1.5e-5/1.0e-5/6e-5/4e-5 与 1e-6/1e-6/4e-6/4e-6，
  但**未经我验证**，故不写入 Findings 的"证据"栏）。
- **Gaussian IRC 的默认 `ReCalc` 值 与 默认 Hessian 更新公式**：文档只说明选项存在；
  某社区输出显示 `Recalc = 5` 与 "DWI will use Hessian update vectors"，但属于用户输入/非官方源。
- **GFN2-xTB 的数值频率缩放因子**：xtb 输出推荐 1.0；文献（PMC8378236）讨论质量缩放替代，
  但我未能取到 GFN2 的具体 scale factor 数字。
- **Sella 的模态重叠/退化处理 与 其收敛判据**：chemrxiv/ACS 正文不可达，
  只取到 OSTI 讲稿中的 TS-BFGS 多 secant 更新与 trust radius 形式。
- **"HMF" Hessian 更新**：未能在任何来源中找到该缩写对应的 Hessian 更新公式
  （猜测可能是某个代码内部命名，或与 **H**essian **M**odified **F**letcher /
  Murtagh–Sargent–Powell 一类更新有关，**未证实**）。需要任务发起方给出定义。
- **pysisyphus NEB 的默认 spring constant**：文档未给出数值。
- **Molpro / Q-Chem 的数值频率步长默认值**：只确认了 xtb(0.005 bohr)、ASH(0.005)、
  ORCA 的 `CentralDiff` 开关。
- **xtb `--modef` 与 TS 的定量关系**（能否作为 TS 初猜生成器）：只有参数与用途描述。

---

## Sources

**Kept（按重要性）：**

- Hratchian & Schlegel, *J. Chem. Phys.* **120**, 9918 (2004)，
  <http://schlegelgroup.wayne.edu/Pub_folder/278.pdf> — HPC 的完整公式（Eqs.1–12）与步长/LQA 上限。
- Meisner & Kästner（EulerPC），<http://schlegelgroup.wayne.edu/Pub_folder/345.pdf> —
  EulerPC 公式、Bofill 更新、一阶性、成本对比、各积分器失效对比。
- Gonzalez & Schlegel, *J. Phys. Chem.* **94**, 5523 (1990)，
  <https://schlegelgroup.wayne.edu/Pub_folder/119.pdf> — GS 的 pivot/球面约束/BFGS 更新/步长。
- ORCA 6.1 Manual §4.3（TS，含 P-RFO 全部公式 4.16–4.20）、§4.1（Table 4.1/4.3 收敛阈值与
  MaxStep/Trust）、§4.4（IRC 全部默认值）、§4.7（quasi-RRHO） —
  <https://www.faccts.de/docs/orca/6.1/manual/contents/structurereactivity/optimizations_TS.html> …
  这是公开可得、公式最完整的闭源实现文档。
- Henkelman & Jónsson, *J. Chem. Phys.* **111**, 7010 (1999)，
  <https://theory.cm.utexas.edu/henkelman/pubs/henkelman99_7010.pdf> — Dimer 全部公式与参数。
- Henkelman & Jónsson, *J. Chem. Phys.* **113**, 9978 (2000) —
  改进切线 Eqs.8–12；
  Henkelman/Uberuaga/Jónsson, *J. Chem. Phys.* **113**, 9901 (2000) — CI-NEB Eq.5-6。
- Peters, Heyden, Bell, Chakraborty (GSM)，
  <https://sites.chemengr.ucsb.edu/~baronp/CODES/SADDLE-SEARCH/04_Peters_GrowingString.pdf> —
  GSM 生长规则/切线/性能对比。
- geomeTRIC 文档（NEB 收敛 0.025/0.05 eV/Å、CI 切换 0.5 eV/Å、g_RMS 定义、TRIC），
  <https://geometric.readthedocs.io/en/latest/neb.html> / `/transition.html`。
- pysisyphus 文档（TS 优化 §12、COS §11、min §7），
  <https://pysisyphus.readthedocs.io/en/latest/tsoptimization.html> 等 —
  含 trust radius / hessian_update / 模态重叠 / dimer 参数 / GSM 参数的**实现级默认值**。
- xtb 官方文档（optimization/hessian/thermo/path），
  <https://xtb-docs.readthedocs.io/en/latest/optimization.html> 等 —
  xtb 的 8 档阈值、`average conv`、Hessian=两侧数值微分、rotor cutoff 50 cm⁻¹、scale 1.0。
- grimme-lab/xtb 源码与 issue：#494（无 TS 优化器）、#1378（restart 隐式使用）、
  `src/restart.f90`、`src/type/setvar.f90`、`src/hessian.F90`、`src/iniq.f90`、
  `src/scc_core.f90`、`man/xcontrol.7.adoc`、`man/xtb.1.adoc`。
- MAPLE 文档：`irc_gs / irc_hpc / irc_lqa / irc_eulerpc / ts_prfo / ts_dmf`，
  <https://www.maplechem.org/> — MAPLE 的具体默认参数（本项目要对齐的对象）。
- VASP Wiki / TST Tools 页（NEB SPRING 语义、dimer DdR/DFNMin/DFNMax 与收敛诊断）。
- Q-Chem 手册（EF 附录 A.7–A.10；libopt3/optimize job control 默认值）。
- G09 `IRC` 关键字镜像页（Gaussian IRC 选项与默认 MaxPoints/StepSize）。
- ASE 文档（NEB k=0.1 eV/Å、remove_rotation_and_translation、AutoNEB、Dimer 类）。
- Smidstrup et al. IDPP（arXiv 版），<https://arxiv.org/html/1406.1512>。
- DL-FIND / libdlfind（Fortran + LGPL-3.0，可嵌入 API）。
- Sella（OSTI 讲稿：TS-BFGS 多 secant 更新与 trust radius 形式；PyPI/GitHub：LGPL-3.0、
  冗余内坐标、受约束优化）。
- Bursch et al., GFN IR 谱评测，<https://pmc.ncbi.nlm.nih.gov/articles/PMC8378236/>。

**Rejected / deprioritized：**

- 各种 SEO 农场与"AI 生成"的解释页（多个来源在检索结果里给出与原文冲突的公式片段，未采用）。
- Matter Modeling SE 关于"ORCA 处理小本征值"的答案 —— 只作为 **community lore** 引用，
  不作为实现依据。
- `theochem.cc`（Gaussian scan/IRC 机制整理）—— 有价值的二手整理，但非 Gaussian 官方，
  仅用于"Lagrange 乘子/约束优化"的表述，已在正文标注其二手性质。
- 与主题无关的 PRFO 检索噪声（雷达 polarimetric radar forward operator、股票波动率网站、
  俄语音乐站、日文 PDF）—— 明显是关键词碰撞，全部丢弃。
- `docs.rs` / vibe-qc 之类的第三方 GFN2 复刻页面 —— 只用其"数值 Hessian 步长 0.005 Å/bohr
  的工程惯例"作为旁证，不用于任何 GFN2 物理声明的证据。

---

## Next steps

1. **补三个硬缺口**（会影响可实现的数值默认值）：
   (a) Gaussian `Opt=Tight/VeryTight` 与 `IRC` 默认 `ReCalc` 的一手页面
   （建议用离线手册/PDF 版 Gaussian 16 用户手册，或校内镜像）；
   (b) Page & McIver 1988 的 LQA 原始方程；
   (c) Baker 1986 的位移缩放/trust radius 原始数值。
2. **向任务发起方询问 "HMF" 与 "B-PRFO" 的定义**（两个术语在公开文献中无法定位，
   若来自某个具体代码/教材，需要指出处，否则我们只能按最接近的实现猜测）。
3. **做 §9 的第 1–4 号数值实验**（xtb 确定性 / Hessian 敏感度 / etemp / 梯度噪声），
   这四个的结果会直接决定 `opt/ts/irc/freq` 的默认阈值与非功能需求（restart 策略）。
4. **确认 libdlfind 的可嵌入性与许可路径**（唯一"Fortran + LGPL-3.0 + 可用于 TS/路径"的现成资产），
   同时用 pysisyphus+xtb calculator 建立**交叉验证金标准**（代码不复制，只做结果比对）。
5. **确认 DMF 是否进范围**：它不需要 Hessian、也不需要神经网络势（只需能量+力），
   但引入 cyipopt 依赖；需要以"相对 CI-NEB 的边际收益"作为取舍依据。

---

## Supervisor coordination

无阻塞项，未发起 `contact_supervisor`。需要任务发起方决策的两点已写入
"Missing evidence" 与 "Next steps"（`B-PRFO` / `HMF` 术语定义；Gaussian 一手数值的补证方式），
可在下一轮澄清，不阻塞本报告交付。
