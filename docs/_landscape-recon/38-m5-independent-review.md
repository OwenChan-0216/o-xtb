## Review

**结论：有条件接受（Accept with conditions）。无 CRITICAL、无 HIGH；MEDIUM 4、LOW 12、INFO 4。**

M5 的两项验收我都独立复核并**通过**：验收 1（实验 #8）的换算与噪声论证成立，验收 2（LEPS）的解析参考值我用纸笔从 London–Sato 闭式独立重算（r\*=1.505269、E\_TS=−0.140638、H₂ 阱 1.414073/−0.154981、势垒 8.9985/9.0000 kcal/mol，全部吻合），因此**不存在自我循环**；三个交付物在 `m5-path-data/` 中真实存在（path.xyz 帧数、path\_ts\_list.xyz 5 帧均含 `imaginary modes: 1`）。注入记录、47 个单元用例名唯一、ctest 名唯一、OMP 属性、注册三处/两处——全部核对无误。

**M5 的核心功能可以宣称完成；但下列 4 项在进 M6 前应修（前两项是生产代码，各 1 行量级）：**

- **M-1 `gsm.f90:823/860/872` 未初始化 `n_eval`**（UB，字符串运行的 "potential evaluations" 含垃圾值）→ 入口 `n_eval = 0`。
- **M-2 `gsm.f90:323-324 + 494-498` 首个生长节点方向错**：传的是 `budget`（全零帧）而不是产物 → `tau = normalize(0 − R)`，与 gsm.f90:269/446 与报告 36 §3.3 声称的 `unit(P−R)` 相反；单元用例 `string-growth-phase`（gsm.f90 的谐振子）里"指向原点"恰好等于"指向产物"，**看不见**这个错。
- **M-3 `neb.f90:53-60` 模块文档把动态弹簧讲反了**（文档说势垒顶拿到 k\_min、平台拿到 k\_max，代码与 `dynamic-springs` 用例相反），且 3 个"实测"数字陈旧/相互矛盾（28 步 vs 48 步；"k\_min≤5e-3 不收敛" vs 表格 1e-5…1e-3 全收敛；"k≥10 不收敛" vs k=10 收敛）。`cineb.f90:31-35` 同类的"过早点火使能量曲线失真"已被报告 37 §3.1(e) 实测否定。
- **M-4 `landscape_testpot.f90:510-517` 的 root 守卫无效**：`root > tiny()` 为假时 `ds=0` 随后执行 `ds/root = 0/0 → NaN`，而 458-461 的文档声称"never divides by zero"；近等边 H₃ 也会因该处二阶导病态得到噪声梯度。

**必须运行验证（我无法执行）**：`ctest -R landscape`（68）与回归（12）+ 重名检查；`--lts-method string` 用**默认**阈值跑 NH3（预期非零退出，验证 L-4）；`--lts-autoneb-max-depth 1` 的退出码与 xtbts.log 声称（L-2）；用 `-finit-local-zero` 重建并比较"potential evaluations"（**证明 M-1**）；把 `budget` 改成显式产物再跑 `landscape-path` 全套（**预期全绿 → 证明 M-2 无覆盖**）。

以下为完整报告正文。

---

# 38 — M5 独立复核报告（chain-of-states：NEB / CI-NEB / AutoNEB / String(GSM)）

复核对象：报告 35/36/37 + `docs/_landscape-recon/m5-path-data/` + `src/landscape/path/*`（1 834 行）+ `tasks/ts.f90` M5 增量 + `types/settings.f90` M5 增量 + `types/coords.f90::align_geometry` + `test/unit/{test_landscape_path.f90, landscape_testpot.f90}`。
输入边界：本会话只有只读工具，**没有运行任何命令**；"构建成功、测试全绿"未被重跑，但 `m5-path-data/` 的原始输出（ctest 68/68、注入 5 组红/绿、cli-string/cli-autoneb stdout、path\_ts\_list.xyz 帧）与报告 35/36/37 的数字一致，且我用 CMake 断言文本逐条核对了 CLI 测试真正断言了什么。
基线：`HEAD = 902cbe4` + 未提交 M5 工作区（`watchdog_diff` 仅覆盖未提交部分；`src/landscape/path/` 为 untracked）。

## 0. 结论

| 项 | 判定 |
|---|---|
| CRITICAL / HIGH | **0 / 0** |
| MEDIUM | **4**（M-1…M-4） |
| LOW | 12（L-1…L-12） |
| INFO | 4（I-1…I-4） |
| 验收 1（实验 #8：阈值 + 噪声） | **通过**（换算独立复核；PLAN/任务书 3.472e-2 确为倒数换算，大 3.5707×） |
| 验收 2（LEPS 势垒 < 0.5 kcal/mol） | **通过**（解析参考被我用闭式独立复算；4 路互校） |
| 交付物 | **通过**（三个文件均真实产出） |
| 结论 | **有条件接受**；M5 可宣称完成，M-1/M-2 必须在 M6 前修 |

## 1. 我独立验证过的东西（先说"对"的部分）

1. **LEPS 解析参考不是自我循环**（最高价值的一项）。我不看代码，直接用标准伦敦方程 + Sato 修正手算：
   - H₂ 渐近极小：`A=e^{-βx}`，`f/d_e = 0.977273A² − 1.863636A`，`df/dA=0 → A=0.9534884 → r = 1.4011 + 0.047627/3.6711 = 1.414073` bohr（模型 1.4140743；报 37 §2.1 的独立 Python 值 1.4140738）、`E/d_e = −0.8884222 → E = −0.1549801` Eh（模型 −0.154980938808）。
   - 对称共线鞍点 `r* = 1.505269`：`A=0.682175`、`B=e^{−β(2r*−r_e)}=0.0027164`，`E/d_e = 2(0.75A²−0.5A) + (0.75B²−0.5B) + (0.25A²−1.5A)/1.1 − (0.25B²−1.5B)/1.1 = −0.806256 → E = −0.140638` Eh（模型 −0.140638574121）。
   - 势垒：`(−0.140638+0.1549809)×627.5095 = 9.0000` kcal/mol；带端点（第三 H 在 4 bohr）`(−0.1406385741+0.1549786471)×627.5095 = 8.99851` → 与 `leps_barrier = 8.9985` 一致。
   ⇒ `landscape_testpot.f90` 的能量式、Sato 因子、参数与 `test_landscape_path.f90:107-114` 的常量**全部正确**，且与 M4 P-RFO 独立找到的 `r12=r23=1.505269` 互洽。R-08 守门测试 `leps-gradient`（逐分量中心差分 + O(h²) 比值 9947.8，注入 v 变红 15 项）**非空洞**。
2. **单位换算**：`0.5·evtoau/aatoau = 0.5×0.0367493/1.8897261 = 9.7234e-3` Eh/bohr = 0.5 eV/Å ✓；任务书/PLAN 的 `3.472e-2 = 0.5/14.3996` 是**力换算因子的倒数**，判别正确。`settings.f90:170` 的 5 位舍入（差 5.3e-8）由 `climb-switch-calibration` 断言（`|default − e_ratio| < 1e-7`）钉住 ✓。
3. **切线数学 = 原文**：`landscape_neb_tangent`（neb.f90:225-275）严格实现 Eq. 8（单调段取 upwind，`ep>e>em → up`，`ep<e<em → um`；都用**归一化**的 τ±）与 Eq. 11（`ep>=em` 时前向邻居拿 `max(|ΔE|)`，`|ΔE|` 取**绝对值**而非正部）。我按 Henkelman 2000 的 Eq. (8)-(11) 逐条对照，一致；退化保护（加权和→dp+dm→e₁）不产生 NaN ✓。
4. **Eq. 12 弹簧**（neb.f90:283-315）：`F = F_perp + k(|dp|−|dm|)τ`，**标量距离差**、纯切向，非 Eq. 5 的矢量弹簧 ✓。
5. **Eq. 5 CI 力**（cineb.f90:60-72）：`F_ci = F − 2(F·τ)τ`，F = −∇E，符号与因子 2 正确；`landscape_band_forces` 在 CI 分支 `cycle`，**确实不含弹簧力** ✓。
6. **IDPP 不需要能量**（idpp.f90 只 use accuracy/environment/lbfgs，无 model）✓；目标面为**逆距离线性插值** ✓；解析梯度 `−2(1/d−t)/d³·(x_a−x_b)` 与中心差分一致（`idpp-gradient`）✓。
7. **双判据**：`landscape_band_converged` 是 `avg ≤ tol AND max ≤ tol AND (CI: ci_rms ≤ max_tol)`；`dual-criterion`（谓词）+ `band-dual-criterion-live`（实带，`max_steps=0` 卡在 avg=8.17e-2/max=1.20e-1，三种容差组合）双向可证伪 ✓。"avg 达标 max 未达标"**不会假收敛**。
8. **Kabsch**：`align_geometry`（coords.f90:353-400）用**算术质心** + 四元数 + **质心回写**（`xyz = target + comref`），端点被显式跳过（`landscape_band_align` 只动 2..n−1；`build_path` 先插值再覆写端点），对角/线形分子：S 秩 1 ⇒ K 的最大特征空间 = 绕分子轴/绕质心的旋转，**不产生除零也不交换端点**；对 2 原子 + 共线 H₃ 都安全（MB 嵌入因**退化旋转**另用 `align=.false.` 并写明）。`band-align-effect`/`band-rotated-endpoint-align` 把"开启时逐像重合参考路径 < 1e-5 bohr"钉死（注入 iv 变红）✓。
9. **两阶段切换按 band 状态、非步数**：`landscape_cineb_ignition_ready(band%f_rms_max, climb_switch_rms)`，严格 `<`；点火后**恰好一个** CI（索引冻结），最高点迁移时 `n_climb_switch` 计数并 `env%warning`（不静默）✓。
10. **端点/产物/etemp**：`read_band_product` 覆盖 6 条拒绝路径（不存在/原子数/原子序/多帧/非 xyz/输入多帧歧义）且各有 CLI 测试；命名空间统一走 `get_namespace`（CLI 用 `--namespace p1/p2/p3`，断言 `p1.path.xyz` 等）✓；`result%etemp = engine%effective_etemp()` + `engine%report` 打印**生效** etemp（M4 硬约束 1）✓；band 分支复用 M3 频率确认，`n_imag ≠ 1` ⇒ `result%converged=.false.` ⇒ `env%error` ⇒ 非零退出 ✓。
11. **数值卫生（N1..N17）**：`src/landscape/path/*` 无裸 `real`/`real*8`、无直接 LAPACK、无 module 级可变量（全 `parameter`）、无 `stop`、字面量全 `_wp`、每个 module/type/公开过程有 `!>` 文档；新增文件已注册 `CMakeLists.txt` + `meson.build`，测试注册三处 ✓。
12. **回归**：`settings.f90` 增量**纯添加**（`watchdog_diff` 无删除行）；`coords.f90` 只追加 `align_geometry` + public；`ts.f90` 的 M4 单端路径（`x0`/`select case`）保持原样，只在 band 方法下提前 return；`main.F90` 唯一删除是一个空行。**M0..M4 未受影响**。

## 2. Findings

### MEDIUM

**M-1（UB）`src/landscape/path/gsm.f90:823`（声明）、`:860`（首次读）、`:872`（累加）**
`integer :: k, nat, ndim, it, n_eval, ls` 未初始化；`n_eval = n_eval + 1` 首次出现在 860，872 行 `string%n_eval = string%n_eval + n_eval`。为什么是问题：未初始化读取是 UB（M3 HIGH-1 同类），并直接污染用户可见的 `string: potential evaluations N` 诊断（报告 36 §7.3 把 645 当作"645 次势能评价"这一实测事实引用，实际该值含垃圾增量）。最小修复：`subroutine landscape_string_climb` 入口 `n_eval = 0`（或把 `n_eval` 改成 `frontier_step` 那样的 `intent(out)` 累加器）。

**M-2（文档/实现矛盾，测试看不见）`gsm.f90:323-324` 与 `gsm.f90:494-498`**
`call grow_frontier(..., n_placed, n_placed - 1, budget, ...)` 把 `other` 传成 `budget`（`grown(3,nat,budget)` 在 312 行以 `source=0.0_wp` 分配，除第 1 帧外全零），于是 `left_prev=0` 走 else 分支 `tau = pack(nodes(:,:,other)) − x_left = normalize(0 − R)`：**首个生长节点朝坐标原点而非产物**。而 `gsm.f90:269`（与 `:446`）和报告 36 §3.3 都声称首节点用 `unit(P−R)`。为什么是问题：这是"测试全绿但仍然错误"的典型——`string-growth-phase` 用谐振子（产物 = −x，原点方向恰好 = 产物方向）**天然看不见**；LEPS well-side 与 NH3 上球面约束松弛把错误起点"吸收"了（球面极小化重新找到路径），所以端到端仍然对，但这条**语义偏离没有任何覆盖**，也解释了为什么 `string-asymptotic-endpoints` 的四组 `ds` 行为如此脆弱。最小修复：把产物显式传进 `grow_frontier`（例如提前把产物写进 `grown(:,:,budget)` 或新增 `target` 参数），或者把文档/报告改成"朝向坐标原点"——前者才是原意。（修完需重测报告 36/37 里 string 的"生长 6 步 / 8 节点"等实测数字。）

**M-3（模块算法文档与代码/实测相反）`neb.f90:53-60`、`cineb.f90:31-35`**
- `neb.f90:54-56`："Images at the top of a barrier get the weak spring `k_min` … images on a flat stretch the stiff `k_max`"。代码（`landscape_neb_springs`）与 `dynamic-springs` 用例断言**恰好相反**：`rise=0` 的单调像得 `k_min`，唯一能量抬升的像得 `k_max−(k_max−k_min)e^{−decay}`（decay=0.5 时 ≈0.045）。报告 35 §2.3 已承认该倒置，但**代码文档没改**。
- `neb.f90:57-59` 三个数字全部与 `m5-path-data`/报告 37 §3.2 表格矛盾：48 步（写 28）；`k_min ≤ 5e-3 不收敛`（1e-5/1e-4/1e-3 分别 31/30/31 步收敛）；`k ≥ 10 不收敛`（k=10 43 步收敛，只有 1e2 才发散）。
- `cineb.f90:32-35`："igniting the climbing image before the band has relaxed distorts the energy profile"——报告 37 §3.1(e) 实测**未复现**（LEPS 阈值 1.0 → iter 0 点火，势垒/几何/迭代数逐位相同；NH3 阈值 10.0 同样）。
为什么是问题：本项目的算法文档是下一个维护者（与 M6 的 IRC 实现）读的第一手材料；三条陈述全部与代码/实测相反，正是 M3 MEDIUM-C 那一类"归因错误"。最小修复：把这三处改成对公式的字面陈述 + 指向报告 37 §3 + 说明"阈值只省算力、本套件未测到精度收益"。同类（LOW 级）请见 L-10、L-13。

**M-4（守卫不起作用）`test/unit/landscape_testpot.f90:510-517`（对照文档 458-461）**
```fortran
if (root > tiny(1.0_wp)) then
   ds(...) = ...
else
   ds = 0.0_wp
end if
dedr = dq - ds/root      ! root = 0 → 0/0 = NaN
```
文档声称"the routine never divides by zero"，但"被守卫"的那一支恰恰执行 `ds/root = 0/0`：等边 H₃（三 `J` 相等）会得到 NaN 梯度而 `fail` 仍是 `.false.`，随后 `landscape_value_present` 才在带内核里报错。更普遍地，`root` 只要**远小于** `|J|`（近等边）就落入 `root > 1e-38` 的真分支，给出 `(J_k−(J_m+J_n)/2)·dJ/root` 的**噪声放大**梯度（该点 √ 不可导）。为什么是问题：这是 M2/M3 两次"文档声明的守卫其实没守住"的同一模式，且该势是整个 R-08 守门测试与被测代码的公共基础。最小修复：`if (root > 1.0e-12_wp*maxval(abs(j))) then ... else dedr = dq`（或直接 `fail = .true.`），并补一个等边 H₃ 的用例断言"有限梯度/明确失败"。

### LOW

| # | 位置 | 现象 / 为什么是问题 / 最小修复 |
|---|---|---|
| L-1 | `main.F90:2956-2990`（`--lts-kmin/--lts-kmax/--lts-kdecay`）+ `neb.f90:277-305` | 没有任何 `env%error` 校验 `k_min ≤ k_max`、`k_decay ≥ 0`。`decay<0` 时 `exp(−decay·rise/rise_max) = e^{+|decay|}` 可把弹簧放大到 `k_max+(k_max−k_min)e^{10}`，**破坏文档承诺的 `k_min ≤ k_i ≤ k_max`**（rise 归一化本身有 `rise_max<1e-12` 守卫 ✓）。修：在 task/settings 层做一次参数校验（M3 LOW-2 的同类做法）。 |
| L-2 | `autoneb.f90:390-410` + `ts.f90:700` | `max_depth` 截断时 `auto%cap_reached=.true.` 与 `auto%message`（"stopped at the insertion depth limit max_depth = 5 with 6 of 9 images"）**只经 `write_autoneb_table`（printlevel>0）打印**；`result%converged` 仍是末 stage 的 band 收敛，`band_message` 把它变成 `result%message = "converged"`，于是 `xtbts.log` 的 `termination:` 写"converged"，退出 0——请求 9 像只得到 6 像却"声称成功"（`cap_reached` 无任何调用者读取）。修：`cap_reached` 时把消息并入 `result%message`。 |
| L-3 | `autoneb.f90:317-336`（首 stage 采用 `initial_images`） | `max_paths` 的"硬上界"只对新建路径生效：`--lts-autoneb-restart` 给一个 20 帧文件（> `max_paths=10`）会**被原样采用并返回**，`size(images,3)` 超过文档宣称的硬上限。修：adopt 分支加 `if (n_images > settings%max_paths) env%error`。 |
| L-4 | `test/unit/CMakeLists.txt:1698`（`--lts-frms-avg 1e-3 --lts-frms-max 2e-3`）+ 报告 36 §5.3 | string 在参考体系 NH3 上的实测残差 `f_rms_max = 1.78e-3` **高于类默认 1e-3**：用**默认阈值**跑 `--lts-method string` 会 `converged F` → 非零退出（path.xyz 仍写出）。端到端"通过"依赖 CLI 显式放宽阈值；报告如实披露（F5）但残差来源未定位。修：先定位（逐节点残差），或在类型文档里写明"string 在分子面上需放宽 `--lts-frms-*`"。 |
| L-5 | `settings.f90:266-270` 与 `:259`、`main.F90:3223-3226` | 文档称"`gsm` name … only adds the growth history of the report"、"the `gsm` task name implies this report"，但 `string_history` **只**由 `--lts-string-history` 设置 ⇒ `gsm` 目前是 `string` 的纯别名（唯一差别是打印的头部名字，CLI 也只断言头部与退出码）。修：`--lts-method gsm` 时置 `string_history=.true.`，或删掉这两句文档。 |
| L-6 | `ts.f90:712-762`、报告 36 §4 表 | `path_ts_list.xyz` 只由 autoneb/string/gsm 写；`neb`/`cineb` 不写（M5 交付物清单未作区分）。CI-NEB 的 climbing image 恰恰是最自然的候选，一致性上应写一帧。修：band 分支写一帧候选（或明确在 PLAN/§12.12 的契约里排除）。 |
| L-7 | `ts.f90:196-201` | 警告文本 "`--lts-product` is only used by `--lts-method neb\|cineb`" 已不完整（autoneb/string/gsm 也用），且 CLI 用例把该不完整文本断言下来。修：改成 "neb/cineb/autoneb/string/gsm"（并同步测试正则）。 |
| L-8 | `test/unit/CMakeLists.txt:1740-1747` | 报告 36 §0/§7.4 的"GSM/CI-NEB 互校：势垒差 0.104 kcal/mol、几何 RMSD 0.014 Å"**没有任何测试钉住**：CLI 只断言 `5.0 < barrier < 7.0`（1.2 kcal/mol 的窗口，0.1 kcal/mol 级回归会漏过）。修：把 0.104 kcal/mol / 阈值改成断言。 |
| L-9 | `gsm.f90:256-257` | `call build_forces(...f_avg, f_max)` 之后 `if (f_avg < 0 .or. f_max < 0) string%message = "unused"`：为消 unused 警告而写的死代码，逻辑上会把诊断消息覆盖成字面量 `"unused"`（`landscape_string_climb` 刚设的 "the climbing node did not reach the force criterion" 就在这里被覆盖的风险）。修：删除该行，或改成 `if (settings%printlevel > 2) ...` 的真诊断。 |
| L-10 | `string.f90:67-68`；`settings.f90:262-266`；`string.f90:70-74` | ①`string.f90:67/68` 整句重复（复制粘贴）；②`settings.f90` 说 `string_spline` 用的是"**natural** cubic spline"，实现与 `string.f90` 文档都是 **not-a-knot**（并明确说 natural 端部误差 O(h)）；③`nu2 = 5e-2` 的"实测依据"混用了 **Cartesian Hessian 本征值**（−1.0049）与"MB 面上 0.1–1"，而单元测试为了关掉该条件取 `nu2 = 1e6`，即并无同量纲的实测支撑（`string-spline` 实测把 spline 误差记作 1.69e-4，也与 `string.f90:340` 文档里的 2.4e-4 不一致）。修：改文字，`nu2` 明确标注"工程缺省、无文献标定"。 |
| L-11 | `ts.f90:1043-1074`、报告 35 §6.4 | `--lts-relax-ends`（M5 唯一的"端点松弛"路径，用 M1 minimiser）**零测试覆盖**，只有代码路径 + 打印。修：加一个 CLI 用例断言端点 |g| 下降与 band 仍收敛（或加单元用例）。 |
| L-12 | `test/unit/test_landscape_path.f90:2192-2262` vs `CMakeLists.txt:1590-1607` | "重启与一次性跑等价"的逐位证据来自**内存内**替换（`max\|dR\| = 0.0`），而 CLI 会经过 `path_autoneb.xyz` 的文本往返（Å，f24.14）+ `angstrom_to_bohr`；CLI 只比较 4 位小数的势垒字符串。修：CLI 里比较重启前后的 `path_autoneb.xyz`（或断言两轮路径文件逐帧一致），把"等价"变成文件级证据。 |

### INFO

- **I-1** `settings.f90:194-200`：`hessian_recalc` 被重定义为"每 N 步清空 L-BFGS 历史"（band 无显式 Hessian），与 PLAN 的同名字段语义不同；已在类型文档与报告 35 §8 说明，且未上 CLI，可接受，但建议在 PLAN §12.12 的契约表里显式登记改名。
- **I-2** `neb.f90:700-716`：CI 索引点火后**冻结**（与 VTST/ASE 每步重选不同）。若最高像迁移，`band%ts_energy` 可能低于真实最高像能量；有一条一次性 warning + `n_climb_switch` 计数，且 M3 频率确认会挡住非鞍点，故非静默。建议在类型文档里写明与参考实现的这一差异。
- **I-3** `ts.f90:1005-1030`：`landscape_ts_count_frames` 是"迷你解析器"（列表读原子数 + 跳行）。它只用于**拒绝**多帧输入，误计数最坏是给出错误拒绝而不是错误接受；可接受（报告 35 §4 已声明）。
- **I-4** 报告 36 §8 的 "`string_nnodes`（= `--lts-images`）" 是措辞错误：string 用 `--lts-string-nnodes`（`settings.f90:244-246`），`--lts-images` 对 string **完全无影响**（AutoNEB 用的是 `n_images`）。

## 3. 攻击面逐条判定（1–13）

1. 改进切线 Eqs.8-12：**对**（neb.f90:225-275；upwind 与绝对值 max/min 均按原文；Eq.11 退化保护齐全）。
2. 动态弹簧：公式对；`dE_max=0` 守卫 `rise_max<1e-12 → k_max` 存在 ✓；`k_min≤k_i≤k_max` 在文档域内成立，但**无参数校验**（L-1）。
3. CI-NEB Eq.5：符号/因子 2 对；最高像确实无弹簧力；切换按 `band_f_rms_max`（严格 `<`）；点火后不重选而是冻结 + 告警（I-2，非静默、无"两个/零个 CI"）。
4. IDPP：无任何能量评价 ✓；逆距离线性插值 ✓（与 ASE `IDPP` 约定一致，报告已说明）。
5. 双判据：avg 与 max 皆查，CI 另加未投影力；"avg 达标 max 未达标"有两级用例，**不会假收敛** ✓。
6. Kabsch：只改内部像，端点逐位不动（`band-fixed-endpoints`）；线性/单原子/双原子不除零、不换端点；端点比对用刚体不变的两两距离 ✓。
7. AutoNEB：能量分辨率插点 + 勘误（区间**几何中点**）✓；`max_paths` 超限 `env%error` ✓，`max_depth` 只是诊断（L-2）、重启文件尺寸未校验（L-3）；"一次性 vs 重启"内存内逐位等价（L-12 的边界）。
8. String/GSM：`f_perp`（Eq.1）符号对；Eq.7 用**模**（非分量 RMS）且有独立用例；Eq.9 通过"球面半径 = spacing"精确实现（工程决定，已实测论证）；`nu2` 是用户下界，来源交代存在但依据偏薄（L-10）；三次样条（not-a-knot）与解析切线对照（圆 1.69e-4 / 直线 1e-12）✓。
9. LEPS：解析梯度与中心差分逐分量为 O(h²) ✓；解析参考值被我用闭式**独立复算** ✓（非自我循环）；唯一缺陷是 `root` 守卫（M-4）。R-08 守门有效（转置注入 → 15 项红）。
10. 虚频/失败语义：band 收敛后在候选点做 M3 频率确认，`n_imag≠1` → `env%error`（非零退出）✓；三个 `path*.xyz` 全走 `get_namespace` ✓；生效 etemp 由 `engine%report` 打印 ✓。
11. 测试可证伪性：47 用例全部语义可辨；注入 5 组的"红"列表与原始输出一致，且每组都论证了与当前逻辑**不等价**（报告 37 §5 表）；已点明 `naive-tangent-kink` 对切线不敏感（F7 诚实）。仍有两处"绿而无覆盖"：`string-growth-phase` 对 M-2 不敏感、GSM/CI-NEB 互校无断言（L-8）。
12. 数值卫生：N1..N17 全部满足（见 §1.11），唯一 UB 是 M-1。
13. 回归：M0..M4 未被触碰（§1.12）。

## 4. 需运行验证清单（父会话执行）

1. `OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape` → 期望 68/68；`-R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'` → 12/12；`ctest -N -R landscape` 与 `grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d`（应空）。**注意**：若按 M-1/M-2 修复，报告 36/37 的 string 实测数字（生长步数、势垒、帧数）需重测。
2. **M-1 判定**：加 `-finit-local-zero`（或 `-finit-integer=-1`）重建，比较 cli-string 的 `string: potential evaluations N`；数值改变即证明未初始化读取（再加 `-fcheck=all` 看是否报错）。
3. **M-2 判定**：临时把 `gsm.f90:324` 的 `budget` 换成 `n_placed + 1`（或显式产物），跑 `xtb-tester landscape-path`；**预期仍全绿**（证明该语义无覆盖），并观察 `string-growth-phase`/`leps-string-barrier` 的输出是否变化。
4. **M-4 判定**：临时用例调用 `leps_evaluate` 于等边 H₃（三边 `sqrt(3)` 的等边三角形）与近等边构型，检查梯度是否 NaN/噪声；断言 `fail` 是否为假。
5. **L-4 判定**：`OMP_NUM_THREADS=1 xtb nh3_up.xyz --gfn 2 --lts --lts-method string --lts-product nh3_down.xyz --norestart`（默认阈值）→ 期望 `string: converged F` / 非零退出。
6. **L-2 判定**：`--lts-method autoneb --lts-autoneb-max-depth 1 --lts-images 9` → 检查退出码 0、stdout 的 `budget limit reached`、以及 `xtbts.log` 的 `termination:` 是否写 `converged` 而未达 9 像。
7. **L-3 判定**：`--lts-method autoneb --lts-autoneb-restart <9 帧文件> --lts-autoneb-max-paths 5` → 检查是否被接受（现应被接受，需变成报错）。
8. 可选：`--lts-relax-ends`（L-11）手工跑一次，确认端点能量/|g| 打印与 band 收敛。

## 5. 判定与移交

- **M5 可否宣称完成：可以**，条件是 M-1、M-2（生产代码，各 1–3 行）修掉；M-3、M-4 属"文档守卫/测试势守卫"，修或显式 disposition 后结案。这两项都不改变已实测的验收数字（LEPS 势垒 4 路互校、阈值标定、三交付物）。
- **进 M6 前必须解决**：M-1、M-2；建议同时处理 M-3/M-4 与 L-1/L-2/L-4（都便宜且直接关系到 M6 会消费的 string 路径与退出码语义）。
- **M6（IRC）接口注意**：`path.xyz` 帧序与 `path_ts_list.xyz` 语义已在报告 37 §2.4 固定；但请注意 L-6（neb/cineb 不写 ts_list）与 L-2（AutoNEB 截断时"converged"）——IRC 若按 `path_ts_list.xyz` 取起点，需容忍这两点；同时 L-4 表示 string 路径的默认用力判据偏严，IRC 初始化不应依赖 `string%converged`。