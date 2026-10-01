I have completed the read-only review. Below is the ≤30-line summary followed by the full report body.

**摘要（≤30 行）**

- 结论：**有条件接受**。CRITICAL 0 / HIGH 0 / **MEDIUM 1** / **LOW 6** / INFO 4。M-1..M-4 的**代码修复本身全部为真修**（我用源码逐路径走通验证），F1/F2 按 (b) 结案合理。
- 唯一 MEDIUM：M-3 的"文档订正"写错了 `max_displ=1e-1` 的收敛窗口——**7↔13 互换**，且用的是报告中**被否决的 (a) 变体**的数字。出现在 `neb.f90:112-114` 与 `PLAN §6.4:928-929`，与本轮自己的原始数据矛盾。
- M-1 真修：`n_eval` 入口+每迭代清零；UB 证明可独立核算（11246−11212 = 34 = 报告给出的 climb 迭代数，量化自洽）。
- M-2 真修且无歧义：唯一调用点传 `product`，形参语义唯一；新夹具方向夹角 **41.7°**（>30°），节点差 0.6397 bohr ⇒「指向原点」与「指向产物」不可互换，测试不空洞；旧逻辑零覆盖已由注入等价性证明。
- M-4 真修：相对守卫 + 提前分支，`root≥0`、`root<=1e-12·max|J|`（含 0/NaN/max|J|=0）全部走无除法分支，除零路径关闭。
- 新发现（测试全绿但文档错）：`gsm.f90` 模块文档仍描述**双前沿**生长（代码是单前沿）；`settings.f90:1066-1068` 仍称 `gsm` "额外报告生长历史"（L-5 只改了一处）；`--lts-relax-ends` 的 CLI 断言不提"|g| 必须下降"；L-1/L-2 两处修复**无任何永久测试**；全部 11 处 "report 39 section N" 交叉引用指向错误章节。
- 可提交性：**代码可以提交**（无代码级阻塞）；建议同批把 `neb.f90:112-114` + PLAN 那一行数字改掉（一行级）。
- 进 M6 前：无代码阻塞；需知 string 默认力判据在分子面不可达（勿用 `string%converged` 当起点判据）、`neb/cineb` 不写 `path_ts_list.xyz`。
- M0..M4 无回归风险：`coords.f90` 为纯追加（+51 行，0 删除），`settings.f90` 改动仅注释，`ts.f90` 两处改动都在 band/告警分支。

---

# 40 — M5 修复轮独立复核（第 2 轮）

复核对象：`39-m5-fix-report.md`、`38-m5-independent-review.md`、`37-m5-validation-experiments.md`、`src/landscape/path/*`、`types/{settings,coords}.f90`、`tasks/ts.f90`、`landscape_driver.f90`、`test/unit/{test_landscape_path.f90,landscape_testpot.f90,CMakeLists.txt}`、`docs/xtb-landscape-PLAN.md`、`docs/_landscape-recon/m5-fix-data/**`。
输入边界：本会话**只有只读工具，未运行任何命令**；"构建干净/测试全绿"未重跑，但我用 `m5-fix-data` 的原始输出逐条核对了报告引用的每一个数字，并用 `watchdog_diff` 核对了工作区改动形状。基线 `HEAD = 902cbe4`；`src/landscape/path/` 为 untracked，故**无法机械地分离"本轮"与"M5 前两阶段"的 diff**，逐条判定依赖报告 39 §1 的改动清单 + 直接读当前文件。

## 0. 结论

| 项 | 判定 |
|---|---|
| CRITICAL / HIGH | **0 / 0** |
| MEDIUM | **1**（R2-M1：`neb.f90` + PLAN 的 1e-1 窗口数字错误，M-3 订正不完整） |
| LOW | 6（R2-L1..L6） |
| INFO | 4（R2-I1..I4） |
| M-1 / M-2 / M-4 | **已修复（真修，可证伪）** |
| M-3 | **部分修复**（公式与方向已改对；另一处窗口数字写错） |
| F1 / F2 | **未消除根因，按 (b) 结案**（诊断/文档/回归齐备，窗口文档含 R2-M1 的错误） |
| F3 / F4 / F6 | 已修复（F4 仅文档） |
| F5 / F7 | 部分处置（记录 + 推迟 M6）/ 接受（如实记录） |
| 结论 | **有条件接受：代码可提交；提交前顺手改 1 处数字** |

## 1. 逐条判定（M-1..M-4、F1..F7）

### M-1 `gsm.f90` 未初始化 `n_eval`（UB）— **已修复（真修）**

- 证据：声明 `gsm.f90:881`；入口清零 `:888`；每次 climb 迭代清零 `:902`；累加 `:935`。我逐条走通 `landscape_string_climb` 的每个 return（`:892`、`:927`、`:968`）：唯一在 `n_eval` 被读之前返回的分支是 `:892`（`env%error`）与 `:927`（line search 评估失败，此时本迭代的部分计数被丢弃＝少计数，不是 UB）。⇒ **该例程内不再存在未赋值读取**。
- UB 证明**可独立核算**：`m5-fix-data/m1-n_eval-experiment.txt` 给出 pre-fix `11246`（默认/`-finit-local-zero`）vs `11212`（`-finit-integer=-1`），差 **34**；同文件注明该实验用紧判据让 climb 循环迭代 **34** 次。旧代码 `string%n_eval += n_eval` 置于循环内而 `n_eval` 是累计值 ⇒ 初值 `g0` 的贡献恰为 `I·g0`，`g0=-1` 与 `g0=0` 之差 = 迭代数 = 34。**观测差与迭代数逐位吻合**，UB 判定被量化确认，不是"数值碰巧变了"。
- 修复后三构建一致（10685）⇒ 唯一相关未初始化读就是它。报告同时更正了报告 36 §7.3 引用的 645（诚实）。**判定：已修复。**

### M-2 首个生长节点方向错 — **已修复（真修，语义唯一、测试不空洞）**

- 代码：唯一调用点 `gsm.f90:345-346` 传 **`product`**（不是索引/计数）；形参 `gsm.f90:498-499`（`real(wp), intent(in) :: opposite(:, :)`，文档写明"对侧**端点**的几何，单前沿生长时它**不在** `nodes` 里"）；形状守卫 `:521`（`size(opposite,1)/=3 .or. size(opposite,2)/=size(nodes,2)` → `fail`）；切线 `:531` `tau = geometry_pack(opposite) - x_left` ⇒ `unit(P−R)`。`grep` 确认 `grow_frontier` 只有这一个调用点，**没有别处再传错**（复核 38 提到的 `gsm.f90:269/446` 是**文档位置**，随本轮插行已移位；其内容现由 `:291`、`:445-448`、`:469` 承接，与代码一致）。
- 语义唯一性：`opposite` 是"对侧端点几何"，与 `left`/`left_prev`（链上索引）语义正交，不再可能把"容量/计数"当索引传入；形状不匹配被显式拒绝而不是越界读。**无歧义。**
- 新夹具的**敏感性验算**（我手算，与数据一致）：`reactant=(1,0,0)`、`product=(0.1,0.8,0)`（`test_landscape_path.f90:1887-1891`）。
 `unit(P−R) = (−0.9,0.8,0)/1.204159 = (−0.74741,0.66436,0)`；`unit(0−R) = (−1,0,0)`。
 夹角 `arccos(0.74741) = **41.68°**`（文档写"42 degrees"，吻合）；两者相距 `ds·|...|=0.63969` bohr（原始输出 `node − expected 0.63969`，一致）。
 ⇒ **> 30°，fixture 真的打破了"指向原点 == 指向产物"的巧合**（谐振子井心在原点、产物不在原点上），节点位置断言（`test_landscape_path.f90:1926-1928`，容差 1e-13）足以区分两种方向。测试**不敏感性问题不存在**。
- 旧逻辑零覆盖 + 注入等价性（M4 教训）：`m5-fix-data/injection-zero-opposite-frame-unit.txt` 是 **48 用例**（47 旧 + 1 新）的套件输出，其中 `string-growth-start-direction [FAILED]`（`:183-187`），且 `node direction (-1,0,0)`、偏差 `0.63969`；文件顶部同时保存 `growth closed T steps 1 unit(P-R) -0.74741 ...` 与 `unit(0-R) -1.00000...`。注入物是"显式全零帧"，与旧 `other=budget` 选中的 `grown(:,:,budget)`（`source=0.0_wp` 分配、首步前只写过第 1 帧）**形状/取值/调用点逐一相同**，且两次运行数字完全相同 ⇒ **先证明等价再解读变红**（符合 AGENTS §6 第 4 条）。ctest 级注入（`injection-A-ctest.txt`）2 红（单元套件 + `xtb/landscape-path-string`），与报告一致。
- 与报告 38 的预测一致：报告 38 第 3 条"期望仍全绿（证明该语义无覆盖）"——报告 39 实测**旧 47 个全绿、只有新用例变红**。**是未修复前状态的证据，不是事后构造**：新用例调用的是 **签名未变** 的公开 `landscape_string_grow`（只有私有 `grow_frontier` 改形参），所以同一测试文件可直接跑在"未修复的生产代码"上，这一点成立；唯一的证据瑕疵是"pre-fix 运行"本身没有独立 artifact（报告 §3.1(b) 用"同一夹具"的注入文件代表），但两者被论证为逐位等价，可接受。

### M-3 `neb.f90`/`cineb.f90` 文档与代码/实测 — **部分修复**

- **公式与方向已改对**：`neb.f90:76-108` 现在给出字面式并写明"`dE_i=0 ⇒ k_i=k_min`；唯一抬升的像 `k_i = k_max−(k_max−k_min)e^{−decay}`（校准档 4.5e-2）"、以及"**该顺序与直觉相反**（势垒顶拿弱弹簧 / 平台拿硬弹簧）"——与 `test_landscape_path.f90:791-842`（`dynamic-springs`：`springs(3)=k_max−(k_max−k_min)e^{−decay}`、`springs(2)=springs(4)=k_min`、端点 `k_max`）**逐值一致**。复核 38 的三处矛盾数字（"28 步"、"k_min≤5e-3 不收敛"、"k≥10 不收敛"）**确实被删除**：我对 `neb.f90` 的 `grep '28|5e-3|>= 10'` 返回 **0 命中**，替换后的数字（动态 48/30 步；静态 1e-2/1e-1/1e2 不收敛；静态 1e-5…1e-3/1/10 收敛 = 31/30/31/37/43；NH3 两端 11/10 步）与 `unit-suite-after.txt:24-32` 和报告 37 §3.2 **逐位一致**。
- **cineb**：`cineb.f90:28-50` 已改为"两阶段是**护栏**、本体系**未复现**过早点火失真（报告 37 §3.1(e)）"，并给出保留护栏的**代码依据**（CI 力把 band 切线当反应坐标；点火后索引冻结不可撤销）。方向正确。
- **但引入/残留一处错误数字**（见 R2-M1）：`neb.f90:112-114` 与 `PLAN §6.4:928-929` 把 `max_displ=1e-1` 行写成 "3/5/9/11/13 收敛、7/15 发散"，实际（本轮自己的原始数据 `unit-suite-after.txt:69-75`、报告 39 §6.2 表、报告 37 §4.2、测试注释 `test_landscape_path.f90:3096-3099`）是 "3/5/7/9/11 收敛、13/15 发散"——**7 与 13 互换**，而错误版本恰是报告 39 §6.1 里**被否决的「有界增长」变体**那一行。⇒ 报告 39 **没有**"只留正确数字"：它删了三条旧矛盾，却把一条错误数字写进了两个权威位置。**判定：部分修复。**

### M-4 `landscape_testpot.f90` root 守卫 — **已修复（真修，除零关闭）**

- 代码 `:518-527`：`if (root > 1.0e-12_wp*maxval(abs(j))) then ds(...); dedr = dq - ds/root; else dedr = dq; end if`。
- 逐值走查所有可能 `root`：
 - `root=0`（等边/`J≡0`）：阈值 `1e-12·max|J|`；若 `max|J|=0` 则阈值 0，`0>0` 假 → else，**无除法**。若 `max|J|>0` 也假 → else。
 - `root<0`：不可能（`sqrt`）。
 - subnormal：`root=1e-320 > 1e-12·max|J|` 只有当 `max|J| ≲ 1e-308`，此时 `ds/root` 的量级 O(|J|/root)=O(1e12)·…仍有限；不存在 `x/0`。
 - NaN（`j` 溢出）：`root=NaN` ⇒ 任何比较为假 ⇒ else 分支（无除法）；能量本身仍会是 NaN，但**不是除零**。
 - ⇒ **不存在 `x/0`**；文档 `:454-469` 的 "never divides by zero" 现在成立。`else` 分支取 `dedr=dq`，正如文档所述"是**对称方向**上过退化点的精确值"；测试的 breathing 断言（`:408-411`，解析 1.518558057249e-01 vs 中心差分 1.518558055063e-01）把这个分支的数值钉死（把它改成 0 会红）。
- 新用例真覆盖该分支：`injection-testpot-old-root-guard.txt:5` 显示旧守卫下 `max |gradient| NaN`，`:127-129` 只有 `leps-degenerate-gradient [FAILED]`（49 用例中 48 绿）。旧形式是**逐行还原**而非等价改写，"变红"直接说明新旧可区分。**判定：已修复。**

### F1 / F2 band 传播收敛性对 `n_images` 非单调 — **(a) 被实测否决 → (b) 结案；实现正确，窗口文档有错**

- (a) 的三版实测（报告 39 §6.1 表）给出了"NH3 停滞 + LEPS 窗口仍非单调"的证据，并**记录了被拒版本的对照窗口**；因此"选 (b)"是有实测支撑的工程决定，不是回避。
- (b) 三件交付**都在**且可核：
 (i) 显式诊断：`neb.f90:151`（`band_divergence_factor=1e3`）、`:875-884`（超阈 → `diverged=.true.` + `aborted` + `band%message` + `env%error` + `exit`）、`:928-930`（末尾重复 `n_images/max_displ/max_steps/diverged`）；`ts.f90:763` 把 `band%message` 送入 result（`band_message` 只在 `converged` 时改写），`ts.f90:883-890` 把非收敛升级为非零退出 ⇒ **诊断显式、非静默**。
 (ii) 失败窗口入文档：`neb.f90:96-124`（含 `diverged` vs 迭代上限两种失败的区分、"循环未收敛的 band 从不返回 `converged=.true.`"）。
 (iii) 回归：`band-initial-path-scan` 的 `n_conv >= 9`（= 实测 4+5，`test_landscape_path.f90:3174-3180`）+ `diverged ⇒ not converged ⇒ n_iter < max_steps` 双向断言；`band-divergence-guard`（`:3038-3081`）**故意不把"该配置必然发散"写成期望**。注入 B（删掉提前终止）只有该用例变红（`injection-B-ctest.txt:27,146`）⇒ 诊断可证伪。
- 缺口（不是掩盖，但应记）：
 - **窗口只覆盖奇数 n**（3,5,7,9,11,13,15）× 2 个 `max_displ`，共 14 个配置；偶数 n 与其它 `max_displ`（报告 37 的 0.03/0.01 交叉表）只在临时探针里测过、**没有永久断言**，`n_conv>=9` 只能对那 14 个配置的退化报警。`band-initial-path-scan` 与模块文档都只声称这 14 个配置，**不构成虚假声明**，但 M6 若依赖"失败窗口"应在更密采样上重测。
 - 文档里那一行错误数字见 R2-M1。
- F2：AutoNEB 继承同一窗口；LEPS 的 AutoNEB 单元用例用实测可行的 `max_displ=1e-2`（`test_landscape_path.f90:2566-2569`，注释写明默认值在各 stage 发散），NH3 CLI 用默认值收敛（`m5-fix-data/autoneb.out`）⇒ 与文档一致。
- **判定：F1/F2 = 未修根因 + 按 (b) 结案（可接受）**；缺陷在窗口文档（R2-M1）。

### F3 迭代表缺 iter 0 行 — **已修复**

`neb.f90:783-793` 在表题后打印 `0, f_rms_avg, f_rms_max, dE(hei)`，注释点明"点火比较的就是该状态"。原始输出可见 iter 0 行（`unit-suite-after.txt:87`）。

### F4 `climb_switch_rms` 5 位舍入 — **已修复（仅文档，值未改）**

`settings.f90:167-177` 写明"标准值 `9.7234e-3`、精确 `0.5 evtoau/aatoau = 9.7234532e-3`、相对差 5.5e-6"。我独立复核量纲：`aatoau = 1.8897261 bohr/Å`（mctc 约定），`0.5·evtoau/aatoau = 0.5·0.0367493/1.8897261 = 9.72345e-3` ✓；值未改，避免使已验证标定失效（`climb-switch-calibration` 用 `< 1e-7` 钉住 default vs 精确值的差）。PLAN `:1864` 同步。

### F5 string 力判据不是鞍点定位代理 — **部分处置（记录 + 推迟 M6，已披露）**

`gsm.f90:70-77` 明确"`string%converged` 是节点力残差的陈述，不是候选质量的陈述"；PLAN §6.4 第 3 条（`:941-944`）写明"IRC 不应把 `string%converged` 当作起点可用性判据"。逐节点残差输出（复核建议的完整方案）推迟 M6——**已在报告 §7 "F5" 行如实标注"部分处置/其余推迟"**。判定：符合"显式 disposition + 未来里程碑"，无隐瞒。

### F6 `landscape_testpot.f90:154` 陈旧本征值 — **已修复**

现文档为 `-1.004939 / +0.003004 (x2) / +1.895410`（`landscape_testpot.f90:150-155`），与 `unit-suite-after.txt:10` 的实测谱一致。

### F7 `naive-tangent-kink` 是弱守卫 — **接受（如实记录）**

真正的切线守卫是 `improved-tangent`（断言单调段 upwind 精确值）；报告 37 §5 与报告 39 §7 都如实写着"该用例对切线规则不敏感"，不是掩盖。判定：接受。

## 2. 专项攻击面逐条回答（1–10）

1. **M-2 修复是否真的消除方向错？** 是。唯一调用点传几何、形参语义唯一、形状守卫存在（`gsm.f90:345-346/498-499/521/531`）；无其它传错点；新夹具夹角 **41.7°**（>30°）、节点差 **0.6397 bohr** ⇒ 不可互换，测试**不**不敏感。
2. **M-2 的证据固定是否真实输出？** 与报告 38 预测一致（旧套件仍全绿、只有新用例红）；`injection-zero-opposite-frame-unit.txt` 是 48 用例原始套件输出、含 FAILED 与两条方向打印，与报告 39 §3.1(c) 的数字一致。它证明的是"注入（= 旧语义）变红"，而"新用例在未修改生产代码上变红"只有散文级记录（公开 API 未变使其可信）。**判定：真实但只有一半独立 artifact**，属可接受范围，不是事后构造。
3. **M-1 的 UB 证明是否落盘、可解释？** 落盘于 `m1-n_eval-experiment.txt`，且**可解释**：差值 34 = 报告自身的 climb 迭代数（旧累加式对初值的敏感度恰为迭代数），量化自洽；`-finit-local-zero` 单独使用时不变（该栈槽恰为 0），用 `-finit-integer=-1` 暴露——报告如实写明这一点。修复覆盖 `landscape_string_climb` 的所有路径。
4. **M-3 的订正方向是否正确？是否与 `dynamic-springs` 一致？三处矛盾数字是否只剩一处？** 公式方向正确、与用例断言逐值一致；三处旧数字已删除（grep 0 命中）；**但新增/残留一处 1e-1 窗口错误**（R2-M1：7↔13 互换，取自被否决变体），且 `settings.f90:1066-1068` 的 `gsm` 说明仍是旧说法（R2-L2）。**没有"两边都留着"旧数字，但有一处新错。**
5. **M-4 除零路径是否关闭？** 关闭（见 §1 M-4 的 root 值走查）：0/负数/subnormal/NaN/`max|J|=0` 全部不进入除法分支；文档承诺与代码一致（除 `:468-469` 后半句轻微过强，R2-I1）；新用例真覆盖该分支（旧守卫 → NaN 红）。
6. **F1/F2：** 选 (b)（(a) 有实测否决记录）；失败窗口**只覆盖奇 n × 2 界**（见 §1 F1 缺口），文档也没有声称更多；回归能捕获退化（`n_conv>=9` + 双向一致性 + 注入 B 变红）；(a) 变体因被回退而**无 pre-fix 对照 artifact**，只能引用报告 39 §6.1 的自述表格（因此该表行的"13 收敛"无法复核，见 R2-I4）。
7. **回归风险：** `types/coords.f90` 对 HEAD 的 delta 是**纯追加**（+51 行、0 删除：`public :: align_geometry` + 子程序；`watchdog_diff` 全文已读）⇒ M0..M4 不调用它，无回归通道。`tasks/ts.f90` 本轮两处改动都在 band/AutoNEB 或"单端方法忽略 `--lts-product`"的告警文本（`:195-202`、`:707-711`），M4 单端路径行为不变；CLI 断言只匹配 `only used by` + `neb|cineb`（`CMakeLists:1537-1542`）仍成立。`settings.f90` 本轮改动仅注释文本（报告 §1/§10 自称，与我读到的内容一致）。LEPS/NH3 已验收数字在 `unit-suite-after.txt` 中**逐条不变**（NEB/CI-NEB +0.0000、AutoNEB −0.0004、String/GSM 6.7972 +0.0003、P-RFO +0.0000、MB 60 步 105.7730、NH3 NEB/CI-NEB 在 `neb.out/cineb.out`）。
8. **测试可证伪性（逐条）：** `string-growth-start-direction` ✅（注入红）；`leps-degenerate-gradient` ✅（旧守卫 NaN 红；else 分支改 0 也红）；`band-divergence-guard` ✅（删提前终止红；把阈值放大到失效也红）；`landscape-path-autoneb-adopt-limit` ✅（自建 18 帧文件，不依赖别的用例；删掉尺寸校验会红）；L-8 窗口 ✅（注入 A 实测抓到旧值 5.9789）；L-12 文件级比较 ⚠（1e-4 Å 分辨率，报告披露实测 2e-5 Å）；`band-initial-path-scan` 的 `n_conv>=9` ✅（等于实测值，退化即红）；**`--lts-relax-ends` 断言 ⚠ 弱**（只断言两行存在，不比较 |g| 下降，R2-L3）；**L-1 的 `band_settings_check` ❌ 零覆盖**；**L-2 的 `cap_reached` → message 传播 ❌ 零永久覆盖**（只有手工运行）。报告里"注入不变红"的记录只有 F7 一条，且是**诚实的缺口记录**（并说明真守卫是 `improved-tangent`），不是掩盖。
9. **"文档说 A、代码做 B"清单**：见 §3（这是本轮最有价值的系统性产出）。
10. **数值卫生（N1..N17）：** 新/改代码全部满足——`path/*` 无裸 `real`/`real*8`、无 `stop/error stop`、无直接 LAPACK/BLAS、无 module 级可变量（全部 `parameter` 或类型分量）、字面量带 `_wp`、`env%error`+返回、`!>` 文档齐全；新代码（`gsm.f90` 重试、`neb.f90` 守卫与 `band_force_norm`、`testpot.f90` 守卫）无例外。`grow_frontier` 重试分支的 `n_try/itry/tau0/radius` 都已声明/分配，L-BFGS 在每个 `itry` 重新构造。

## 3. 「文档 vs 代码」系统性清单（本轮的净产出）

| # | 位置 | 文档承诺 | 代码/实测 | 处置建议 |
|---|---|---|---|---|
| 1 | `neb.f90:112-114` | `max_displ=1e-1` 时 "3,5,9,11,13 收敛，7,15 不收敛" | 实测（`unit-suite-after.txt:69-75`、报告 39 §6.2、报告 37 §4.2）是 "3,5,7,9,11 收敛，13,15 发散"；错值来自被否决的 (a) 变体 | **必须改**（R2-M1） |
| 2 | `PLAN §6.4:928-929` | 同上 | 同上 | **必须改**（同批，一行） |
| 3 | `gsm.f90:25-32, 55` | 生长是**两前沿**交替推进、"两前沿相遇才停"、"节点数达到 `string_nnodes` 才停" | 单前沿（从 reactant）生长，`gsm.f90:333-346`；停止条件是"前沿距产物 ≤ 一个 spacing"（`:343`、`:410`）；`string_nnodes` 是**上界**（`gsm.f90:298-306` 自己写着"two-sided variant"已被弃用、"`string_nnodes` 是 upper bound, not a target"）⇒ **同文件自相矛盾** | 改文字（R2-L1） |
| 4 | `gsm.f90:113` `string%closed` | "True if the **two frontiers** met within one spacing" | `closed` 在 `:410` 由"单前沿到产物的距离 ≤ spacing"置位 | 同上（R2-L1） |
| 5 | `gsm.f90:147` `string%gap` | "Distance between the **two frontiers** when the growth stopped" | `gap = string_frontier_distance(grown, n_placed, product)`（`:387`） | 同上（R2-L1） |
| 6 | `settings.f90:1066-1068` | "the `gsm` name selects the variant that **also reports the growth history**" | `string_history` 的唯一写入者是 `main.F90:3223-3226`（`--lts-string-history`）；`--lts-method gsm` 分支只设 `climb`（`main.F90:2506`）⇒ `gsm` 是纯别名（正是 L-5 的结论，但**只改了 `settings.f90:244-248` 一处**） | 改文字（R2-L2） |
| 7 | `test/unit/CMakeLists.txt:1428-1430` | 注释："the printed gradient norm **has to drop**" | `:1443-1453` 只断言"before/after 两行存在"，不比较数值 ⇒ 松弛变成 no-op 仍绿 | 加 before/after 数值比较（R2-L3） |
| 8 | `test/unit/CMakeLists.txt:1776` | 注释："the measured difference is **0.10 kcal/mol**" | 修复后实测 **0.012 kcal/mol**（同文件 `:1809-1818` 的窗口已按 6.0825/6.0702 收紧） | 改注释（R2-I3） |
| 9 | `neb.f90:872` | 注释："threshold is **two orders of magnitude** above the largest transient" | `1e3 / 4.4e1 = 22.7×` ≈ 1.35 个数量级 | 改措辞（R2-I2） |
| 10 | `landscape_testpot.f90:468-469` | "**never divides by zero** and **always returns a gradient in the level set of the energies**" | 前半句已成立；后半句在退化点的非对称方向上**不成立**（该处本不可导，`dedr=dq` 只是工程选择；同句前一子句已正确限定"exact along the symmetric directions"） | 删掉后半句（R2-I1） |
| 11 | 11 处 `report 39 section N` 引用 | 见 §4 清单 | 全部指向错误章节（报告 39 的 §5 是 M-4、§6 是 F1/F2，且无 §6.3） | 批量改（R2-L4） |
| 12 | `m5-fix-data/unit-suite-49cases-before-new-tests.txt` | 报告 §11 描述为"加入新用例前的 **49** 用例输出" | 文件内部编号是 `(k/**50**)`，且含 3 个新用例（`leps-degenerate-gradient` 2/50、`string-growth-start-direction` 33/50、`band-divergence-guard` 46/50）⇒ 名称与内容不符（真正的 49 用例 artifact 是 `injection-testpot-old-root-guard.txt`） | 改名或补注（R2-L5） |

（我按要求扫了本轮涉及的全部文件：`path/{gsm,neb,cineb,string,autoneb,idpp}.f90`、`types/{settings,coords}.f90`、`tasks/ts.f90`、`landscape_driver.f90`、`test/unit/{test_landscape_path.f90,landscape_testpot.f90,CMakeLists.txt}`、`docs/xtb-landscape-PLAN.md`。除上表外没有发现新的"文档 A / 代码 B"。）

## 4. 本轮新发现（我的编号 + 最小修复）

**R2-M1 — MEDIUM，`neb.f90:112-114` + `PLAN §6.4:928-929`：1e-1 行的收敛窗口 7↔13 互换（且取自已否决的 (a) 变体）**
证据：本轮自己的原始数据 `m5-fix-data/unit-suite-after.txt:69-75`（`n 7 bound 0.100 converged T iter 24`；`n 13 bound 0.100 converged F diverged T iter 397`）；报告 39 §6.2 表；报告 37 §4.2 表；测试注释 `test_landscape_path.f90:3096-3099`。四处一致，只有 `neb.f90` 与 PLAN 两处相反。最小修复：把两处改成"`max_displ=1e-1` 时 3、5、7、9、11 像收敛，13、15 像发散"。**这是 M-3 的订正被自己写错的一处**，也是本轮唯一应在提交前修的项。

**R2-L1 — LOW，`gsm.f90` 模块文档的"双前沿"生长（`:25-32`、`:55`、`:113`、`:147`）**：与同文件 `:298-306` 及实现（`:333-346`、`:410`）矛盾。最小修复：把 phase 1 描述改为"单前沿从反应物出发、每次推进一个 spacing、距离产物 ≤ 一个 spacing 即闭合并附加产物；`string_nnodes` 是上界"。

**R2-L2 — LOW，`settings.f90:1066-1068` 仍称 `gsm` "额外报告生长历史"**：与 `main.F90:3223-3226/2506` 矛盾，也与本轮刚改过的 `settings.f90:244-248` 矛盾。最小修复：改为"`string` 与 `gsm` 共用同一内核与同一行为（目前只差打印的标题）"。

**R2-L3 — LOW，`--lts-relax-ends` 的 CLI 断言弱于其注释**：`CMakeLists:1443-1453` 只捕获"after"行的 E/|g| 存在性；注释（`:1428-1430`）与报告 §7 L-11 的说法（|g| 3.82e-3 → 1.14e-5）**没有被断言**。最小修复：同时捕获 before/after 两行的 `|g|` 并断言 `g_after < g_before`（松弛版本：`g_after < 0.1·g_before`），或断言与实测值的 ±10 % 窗口。

**R2-L4 — LOW，全部 11 处 `report 39 section N` 交叉引用错误**（应重编号）：
- `neb.f90:101` "section 5" → §6.1；`test_landscape_path.f90:3026`、`:3090` 同；
- `test_landscape_path.f90:3031`、`:3176` "section 5.2" → §6.2；
- `gsm.f90:65`、`:561` "section 6" → §3.4；`gsm.f90:73` "section 6" → §8.2；
- `test/unit/CMakeLists.txt:1631` "section 6.3" → §10.4（§6.3 不存在）；`:1695` → §3.4/§8.2；`:1809` → §8.2；
- `PLAN:924` "§5.1" → §6.1；`PLAN:927` "§5.2" → §6.2；`PLAN:940` "§6" → §3.4/§8.2。
（另有 `test_landscape_path.f90:2568` 把 AutoNEB 的 `max_displ` 实测记为 "report 37 section 4.5"，该内容在 §4.2/§4.7 F2；`test_landscape_path.f90:3092` 用 §4.5 引初始 band 力则可接受。）
最小修复：批量重编号；若曾改过报告章节，说明一句即可。

**R2-L5 — LOW，`m5-fix-data/unit-suite-49cases-before-new-tests.txt` 名实不符**：文件内为 50 用例（含 3 个新用例）。最小修复：改名（如 `unit-suite-50cases-final.txt`）或删除（与 `unit-suite-after.txt` 重复），并在报告 §11 指明"49 用例状态"的真实 artifact 是 `injection-testpot-old-root-guard.txt`。

**R2-L6 — LOW，L-1 与 L-2 两处修复没有永久测试**：
- `neb.f90:952-985` 的 `band_settings_check`（`max_displ<=0`、`k_min/k_max<=0`、`k_min>k_max`、动态 `k_decay<0`）**没有任何用例**（我对 `test_landscape_path.f90` 与 `test/unit/CMakeLists.txt` 的 `grep 'inverted|max-displ|k-min|must be positive'` 无命中）⇒ 把四个分支全部删掉，套件仍全绿。
- `ts.f90:707-711` 的 `cap_reached → result%message` 传播只有手工运行 `autoneb_depth1.out`；`autoneb-limits` 只断言了"预算内不发生 cap"（`:2250-2251`），**没有 `cap_reached=.true.` 的用例**。
最小修复：各加一条（单元：`set%k_min=1e-1; set%k_max=1e-2` ⇒ `band%converged==.false.` 且 message 命中 `invalid band settings`；CLI：`--lts-autoneb-max-depth 1` 断言 `xtbts.log` 的 `termination:` 含 `max_depth` 且不含 `converged`）。

**INFO**
- **R2-I1** `landscape_testpot.f90:468-469` 的"always returns a gradient in the level set of the energies"过强（`dedr=dq` 只在对称方向上精确）。
- **R2-I2** `neb.f90:872` 的"two orders of magnitude"实为 22.7×（≈1.35 个数量级）。
- **R2-I3** `test/unit/CMakeLists.txt:1776` 的"0.10 kcal/mol"注释陈旧（现为 0.012）。
- **R2-I4** 报告 39 §6.1 对被否决(有界增长)变体写"路径 RMSD 9.5e-7 → **3.7e-3** bohr"，与报告 37 §4.4 的记法（RMSD 9.47e-7、f_rms_max 3.7e-4）疑似量混用；该变体已回退，无法复核（同时也意味着该表行"13 像收敛"没有 artifact 支撑）。

## 5. 我确认"对"的部分（先说好的）

1. M-1/M-2/M-4 的**代码修复是真修**，且各有可证伪守卫；M-2 的注入**先证等价再解读变红**，完全符合 AGENTS §6 第 4 条（M4 教训）。
2. `neb.f90:225-315` 的切线（Eq.8-11，含绝对值 `max(|ΔE|)` 与 upwind）、Eq.12 标量弹簧、`cineb.f90:60-72` 的 Eq.5（符号/因子 2）我逐条对照过 Henkelman 2000，正确。
3. `band_force_norm`/`band_divergence_factor` 的实现与文档一致（只对内部像求和，端点不参与）。`band_settings_check` 的四个条件与文档一一对应（仅缺测试，见 R2-L6）。
4. `--lts-autoneb-adopt-limit` 的测试**自建** 18 帧文件（`CMakeLists:1854-1862`），不依赖别的用例的产物，是这份 CMake 里少见的稳健写法。
5. L-3（adopt 超限）、L-9（删 `string%message="unused"` 死代码，改为 `printlevel>1` 真诊断）、L-10（`nu2` 标为"工程缺省无文献标定"、样条 not-a-knot 与 1.69e-4/4.91e-2/1.6e-1 三值）均与代码/原始数据一致。
6. 69 个 landscape `add_test` 名**无重名**（我列出全部 56 个 `xtb/landscape-*` 名 + 13 个单元套件名，逐项对照无重复）；新 CLI 测试的 OMP 属性由 `CMakeLists:1943-1966` 的既有列表覆盖（`landscape-path-{cli,autoneb,string}` 在列；adopt-limit 等错误分支按注释保持 plain env，符合设计）。
7. 交付物与验收数字：`m5-path-data/` 的三个 `path*.xyz` 帧数与报告一致；`unit-suite-after.txt` 中 LEPS 四路互校与 NH3 数字与报告 39 §8 **逐条吻合**。

## 6. 需运行验证清单（父会话执行；我只读无法运行）

1. **强制**：`OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape`（期望 **69/69**）、`-R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'`（**12/12**）、`ctest -N -R landscape`（69）、`grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d`（应为空）。以及 `xtb-tester landscape-path`（**50/50**）。
2. **R2-L3 的验证**：跑 `OMP_NUM_THREADS=1 xtb nh3_up.xyz --gfn 2 --lts --lts-method cineb --lts-images 7 --lts-product nh3_down.xyz --lts-relax-ends --norestart --namespace p1`，读出 `endpoint relaxation (reactant|product) before/after` 两行的 `|g|`，确认 `after < before`（报告 §7 L-11 声称 3.82e-3 → 1.14e-5，但没有任何测试断言过）。
3. **R2-L6 的两个缺口**（若接受补测）：单元层面 `set%k_min=1e-1; set%k_max=1e-2` → `landscape_band_optimize` 应立即以 `invalid band settings` 失败（也可 `max_displ=0`、`k_decay=-1` 各一条）；CLI 层面 `--lts-method autoneb --lts-autoneb-max-depth 1 --lts-images 9`（exit 0、stdout `budget limit reached`、`xtbts.log` 的 `termination:` 含 `max_depth` 而不含 `converged`）——这是报告 §7 L-2 唯一依赖手工运行的地方。
4. **R2-M1 的复核**（无需重跑）：只需拿本报告的映射去改 `neb.f90:112-114` 与 PLAN `:928-929`，改动后再与 `m5-fix-data/unit-suite-after.txt:69-75` 对照一次。
5. 可选（M-1 的独立复现）：以 `-finit-integer=-1` 重建并比较 `string: potential evaluations`（期望与默认构建一致 = 10685），以及把 34 与本报告的量化解释核对一次。
6. 可选（若 M6 要依赖 F1 的失败窗口）：在**偶数** n（4/6/8/10/12/14）与 `max_displ ∈ {3e-2, 1e-2}` 上补一次采样，确认 `n_conv>=9` 的窗口没有未知黑洞。

## 7. 判定与移交

- **M5 现在是否可以提交：可以。** 4 条 MEDIUM 的代码修复全部为真修且有可证伪守卫；0 CRITICAL / 0 HIGH；新增发现只有 1 条 MEDIUM，且是**纯文档数字**（`neb.f90:112-114` + PLAN 一行），不改变任何代码行为与验收数字。建议在**同一次提交**里顺手把它改掉（连同 R2-L1/L2 的两处文档矛盾），因为它们正是 M6 会读的算法文档。
- **进 M6 前必须解决**：无**代码级**阻塞。建议（低成本、直接影响 M6）：
 1. 修 R2-M1 的数字（`neb.f90:112-114`、PLAN §6.4）；
 2. 修 R2-L1（`gsm.f90` 双前沿）与 R2-L2（`gsm` 生长历史）——M6 的 IRC 会读这两处；
 3. 补 R2-L6 的两条断言（L-1 参数校验、L-2 cap 消息），把"修了但没守卫"的两项补成可证伪；
 4. M6 接口注意（沿用复核 38 §5 + 本轮新增）：string 的默认力判据在分子面上不可达（勿把 `string%converged` 当起点判据）；`neb`/`cineb` 不写 `path_ts_list.xyz`；band 传播**没有线搜索**，收敛性对 `n_images` 非单调（失败窗口只覆盖 14 个配置），IRC 初始化不应依赖 band 的默认步长/界。
- **不构成阻塞但应记录**：R2-L3/L4/L5、R2-I1..I4。

---