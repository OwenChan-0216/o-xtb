## 摘要（≤30 行）

**结论：有条件接受。** 报告的**结构性结论成立**（套件≠ANCopt 超集；MAPLE 算法大多与势无关；PBC 是最大缺口），但 **permanent/待补 的划分有 1 处实质错误，Native 能力矩阵不完整**。

- **HIGH-1（最重要）**：报告把 **DMF 判为「永久依赖 MLIP」是错的**。`dmf.py:638` 的 **默认 backend 是 `"numpy"`**，`dmf.py:727-729` 明确 `if backend=="numpy": return None, None`（不加载 torch），numpy 路径只调 `get_forces()`/`get_potential_energy()`（`dmf.py:613,624,840,868,1787`）。torch 只是**可选加速后端**。DMF 的硬依赖只有 `cyipopt`（`dmf.py:23`，通用 NLP 求解器，非 MLIP）。⇒ **DMF = 待补，不是永久**。这直接推翻报告 §3 P1 / §5.7 / §6#2 的「只剩 3 处永久」结论。
- **MEDIUM-1**：`p_run_*` **实际 24 个，不是 21**（`setparam.f90:197-220` 恰 24 行）。表本身完整，但两处「共 21 个」与「穷举」声明不符。
- **MEDIUM-2**：Native 矩阵**缺整层属性/分析能力**：`--esp/--stm/--dipole/--raman/--alpha/--pop/--wbo/--molden/--lmo/--fod/--cma`（`xhelp.f90:158-236`，`main.F90:1872-1930`）、溶剂变体 `--cosmo/--tmcosmo/--gbe/--gb`（`xhelp.f90:205-217`）、`--efield`、以及子模块 `xtb topo/info/ir`（`submodules.f90:36-50`，`primary.f90:55-75`）。套件全无。§1.2 自称「穷举」不成立。
- **MEDIUM-3**：torch 使用分类不完整。`BPRFO.py:17`、`dimer.py:14`、`ts/ts.py:4` 是**模块级硬 import torch**（对比 `PRFO.py:32` 在 `try` 内）。报告称「只有 hessian/_dmf/blbfgs 必需 torch」不准；MAPLE 的 TS 子系统无 torch 连 import 都失败（但不改变「可迁移」结论）。
- **LOW**：dock 实为 `xtb dock` 子模块（`primary.f90:71`），非 `--dock` 旗标；`getkopt` 引用应为 `main.F90:821-824`（报告写 786，那行是 DIPRO）；`$scan` 调用约在 `main.F90:953`（报告写 914-916）；row 29 只说「S 写 xtb.trj」漏了套件**也写 `xtbopt.xyz`**（`types/log.f90:68-82`）；矩阵 row 18/19 把 PBC 标 `N ✅`，但自文 §5.4 实测 **GFN2 PBC 失败**（"Multipoles not available with PBC"），应标 ⚠️(GFN1/FF)。
- **§6 证伪清单完整性**：报告**未把 DMF 记为可迁移**（反而写成永久），漏了自己 §5.4 里发现的 GFN2-PBC 矛盾。
- **§7 诚实性**：基本诚实；但「DMF 永久」是代码层判断却判错。实测只给汇总表、**无原始 stdout**，可复现性打折（LOW）。

---

# W1 独立复核报告（完整正文）

## 复核对象与方法
- 报告：`docs/_simplify-recon/08-four-way-capability-boundary.md`（HEAD `bdd8eb8`）。
- 源码：`/home/owenchan/work_path/coding/fortran/xtb`（含 `src/landscape/**`）与 `/home/owenchan/work_path/coding/python/MAPLE`。
- 手段：**只读**（read/grep/find）。无 shell，故**不重跑任何 xtb/ctest/MAPLE**；报告的 `[实测]` 数字我**无法复现**，仅做自洽性与代码一致性核验。凡我判断为「读代码推断」的一律标注。

## 一、我独立列出的 runtyp 全景（核验报告 §2.1/§4.2）

`src/setparam.f90:197-220` 逐行核对，**`p_run_*` 共 24 个**（报告称 21，错）：
`prescc 1, scc 2, grad 3, opt 4, hess 5, ohess 7, bhess 71, md 6, omd 8, lopt 9, path 10, screen 11, lscan 12, modef 13, mdopt 14, metaopt 15, lts 19, lirc 20, lvib 21, vip 100, vea 101, vipea 102, vfukui 103, vomega 104`。
`set_runtyp` 映射（`set_module.f90:1043-1103`）与报告一致。值域：1–15、19–21 占用，16/17/18 空——**报告此项正确**。**报告的表逐行完整**，仅总数写错。

## 二、差异表：我的缺口/能力清单 vs 报告（本轮核心产出）

图例：✔=报告已列且我认同；✗=报告**遗漏**；≠=报告列出但**判错/标错**。

| # | 能力项 | 提供者 | 报告 | 我的判定 | 证据 |
|---|---|---|---|---|---|
| 1 | 属性/分析层：`--esp/--stm` | N | ✗ | **遗漏** | `xhelp.f90:158,161`；`main.F90:1872-1878` |
| 2 | `--pop/--wbo/--dipole/--alpha` | N | ✗ | **遗漏** | `xhelp.f90:219,236,232,228`；`main.F90:1918-1930` |
| 3 | `--molden/--lmo/--fod/--cma` | N | ✗ | **遗漏** | `xhelp.f90:221,238,224,215`；`main.F90:1880,1924` |
| 4 | `--raman`（GFN2+PTB 拉曼） | N | ✗ | **遗漏**（套件 vib 的 IR/Raman 强度恒 0） | `xhelp.f90:234`；AGENTS.md §M3 |
| 5 | 溶剂变体 `--cosmo/--tmcosmo/--gbe/--gb` | N | ✗（仅涵 ALPB/GBSA） | **遗漏** | `xhelp.f90:205-217` |
| 6 | `--efield` | N | ✗ | **遗漏** | `xhelp.f90:151` |
| 7 | 子模块 `xtb topo`（GFN-FF 拓扑） | N | ✗ | **遗漏** | `submodules.f90:36-42,80`；`primary.f90:67` |
| 8 | 子模块 `xtb info` / `xtb ir` | N | ✗ | **遗漏** | `submodules.f90:30,44,77,86`；`primary.f90:59,75` |
| 9 | docking | N | ≠ `--dock` | 实为 **`xtb dock` 子模块** | `submodules.f90:46,82`；`primary.f90:71`；`main.F90` 无 `--dock` |
| 10 | DMF（Direct MaxFlux） | M | ≠ **永久** | **待补**（默认 numpy 后端只吃 E/F） | `dmf.py:638,727-729,613,840,1787` |
| 11 | autograd Hessian | M | ≠（实现层） | 报告**已注明能力可被数值 Hessian 覆盖**，同意 | `hessian.py:6` |
| 12 | batch-GPU L-BFGS/BPRFO | M | ✔ **永久（特征）** | 同意（算法本身在套件里） | `blbfgs.py:11`；`BPRFO.py:17` |
| 13 | `--ohess` | A/N | ✔ G2 | 同意 | `main.F90:1276-1285` |
| 14 | `--bhess`（getkopt） | A | ✔ G3 | 同意；**引用错**（应 `main.F90:821-824`） | `main.F90:820-824`；`getkopt.f90` uses `xtb_geoopt` |
| 15 | `--path/--modef/--screen/--metaopt/--mdopt` | A | ✔ G4-G7 | 同意 | `main.F90:1406-1445` |
| 16 | PBC 单点/优化 | N | ≠ `N ✅` | 应 ⚠️（**GFN1/FF only**，GFN2 失败） | 报告 §5.4 自测；`main.F90:915-918` |
| 17 | `$scan` 块执行 | A | ✔ G13 | 同意（套件响亮报错） | `main.F90:493-503,952-954` |
| 18 | 输出契约 `.xtboptok/.xtbopt.log/.xtblast.xyz/.xtbtmpmode` | A/N | ✔ G11，但 cell 措辞不准 | 同意缺口；**套件也写 `xtbopt.xyz`** | `geoopt_driver.f90:121,186`；`optimizer.f90:374`；`modef.f90:280`；`types/log.f90:68-82` |
| 19 | extern 嵌入（ORCA/TM/MOPAC/driver） | A/N | ✔ E3（泛型） | 同意（未验证） | `engine.f90` 泛型 `class(TCalculator)` |
| 20 | 套件单点无 CLI（`--lsp`） | S | ✔ G1 | 同意存在，但**非能力缺口**（native `--sp` 覆盖） | `main.F90` 无 `landscape_sp_settings`；仅 `test/unit/test_landscape_sp*` |
| 21 | MAPLE torch 依赖面 | M | ≠「仅 3 处必需」 | **至少还含** `BPRFO.py:17/dimer.py:14/ts.py:4` 模块级硬 import | 见 MEDIUM-3 |

**报告「多余」（列了但不算缺口）**：G1、G6、G7 更接近「打包/脚本便利」而非能力缺口（报告自己也标注影响小）。

## 三、正确性逐条

1. **「套件不支持 X」核验（W0 后状态，未引用旧态）**
   - PBC：`landscape_driver.f90:72-76` 真报错 ⇒ ✔。
   - `$scan`：`main.F90:493-503` 真报错 ⇒ ✔。
   - `$fix`：`constraints.f90:106-150` 有投影；`tasks/opt.f90:133-141`、`tasks/ts.f90:210-227`（band 拒绝）、`tasks/irc.f90:172-189`（IRC 拒绝）与报告 §5.2 一致 ⇒ ✔。
   - `sp` API-only：`main.F90` 只 `use landscape_opt/scan/vib/ts_settings`，无 `sp` ⇒ ✔。
2. **「Y 依赖 MLIP」核验**
   - MAPLE 计算器层确为纯 MLIP，无 xTB：`set_calculator.py:31-52`；`calculator/` 仅 `__init__/base/set_calculator` ⇒ ✔。
   - 算法取量确经 ASE 接口（`calc.get_hessian`/`get_forces`）：`neb.py:38`、`irc/hpc.py:422`、`PRFO.py:367` ⇒ ✔。
   - **但 DMF 判错**（见 HIGH-1）。
3. **引用错误**：`getkopt` 在 `main.F90:821-824`（报告写 786）；`$scan` 的 `relaxed_scan` 调用在 `main.F90:952-954`（报告写 914-916，那是 DIPRO 区附近）。⇒ LOW。

## 四、实测证据可信度

- 报告**只给汇总表，无原始 stdout 片段**（§5 无任何逐字输出）。数字内部自洽（如 §5.1 水 `--lopt` lbfgs E 与 §5.0 `water_min.xyz` E 同为 −5.070544446522；§5.3 taxol 147.09/110.19=1.335）。但**不可审计**，建议父会话要求补原始输出。
- §5.1/§5.3 **多次自述「二进制对照污染」**（参照 edcfbbe vs 基座 bdd8eb8 差 8.6e-7 Eh / 1.19 cm⁻¹），这是负责任的处理 ⇒ 认同。
- §5.2 的「参照 `--opt` 在 `$fix` 下把 O 移到 −0.308 Å」是**强主张**且是 §6#1 的基石，但无原始输出，我无法复现。就代码面：native `optimizer.f90:366-371` 确按 `$fix` 缩减 `nvar`，与本基座「不动」自洽；参照二进制行为未证实 ⇒ 标 **未验证（我）**。
- §5.4 的 GFN2-PBC 失败与 §5.7 的 MAPLE 不可运行均为合理自测/环境事实，我无环境复跑 ⇒ **未验证（我）**。

## 五、永久 vs 待补（报告最重要的判断）

| 报告 | 我的改判 |
|---|---|
| P1 DMF 永久 | **待补**（`dmf.py:638` 默认 numpy 后端；torch 可选；硬依赖仅 cyipopt） |
| P2 autograd Hessian 永久（实现层） | 保留，但**能力不缺**（数值 Hessian 已覆盖），非真正缺口 |
| P3 batch-GPU 永久（特征层） | **保留**（xtb CPU-only，batch/GPU 特征确实不可得；算法可迁移） |

⇒ 真正的「永久」只有 **batch-GPU 特征** 1 条（+ autograd 实现层一条，能力不缺）。报告「13 待补 + 3 永久」应改为 **约 14 待补 + 1-2 永久**。

## 六、被证伪的前提（完整性与报告对照）

报告 §6 列 6 条；我复核后**补一条**：

> **报告自身隐含前提「DMF 永久依赖 MLIP」——假**（`dmf.py:638,727-729`）。报告在 §6#2 说「MAPLE 算法依赖 MLIP⇒无法迁移，大部分假」，却**把 DMF 排除在外**；实际 DMF 也属「大部分」之列。

另有 §5.4 已发现、但 §6 未登记的矛盾：**「Native 支持 PBC 优化」对 GFN2 为假**（矩阵 row 18/19 仍标 `N ✅`）。

## 七、未验证清单（我的证据等级）

- **我核验的**：runtyp 数量与映射；`$fix`/`$scan`/PBC 在套件的报错点；`sp` API-only；dock 为子模块；native 属性/溶剂/子模块能力存在性；MAPLE 计算器无 xTB、DMF 默认 numpy 后端、torch 硬 import 集合。
- **我读代码推断的**：extern 对套件的适用性；MAPLE 算法与势无关（除 DMF 外）。
- **我无法确认的**：报告全部 `[实测]` 数字（无 shell、无原始输出）；参照二进制 `$fix` 移原子；GFN2-PBC 失败的具体报错文本；MAPLE 实时运行。

## 八、给父会话的处置建议

1. **必须修**：把 DMF 从「永久」移入「待补」并给代价（M/L：需为套件/ASE 提供 xTB 计算器 + cyipopt 或 Fortran 重写 NLP）。
2. **必须补**：Native 矩阵加「属性/分析层」与 3 个子模块行；runtyp 总数改 24。
3. **建议**：矩阵 PBC 改 ⚠️（GFN1/FF）；dock 改 `xtb dock`；订正 getkopt/`$scan` 行号；row 29 补 `xtbopt.xyz`。
4. **建议**：把 §5 的原始 stdout 落盘/附上，否则 `[实测]` 无法审计。

## 验收报告