## 摘要（30 行内）

**结论：接受（ACCEPT）。CRITICAL 0 / HIGH 0 / MEDIUM 0 / LOW 4 / INFO 5。M7 可提交；整套件可交付。**
全部 4 条 LOW 与 5 条 INFO 都是**文档/指针**级，无一条推翻验收数字、失败语义或 M0..M6 行为；其中 3 条是「本轮声称已改、但仍有残留」，建议随本次提交一并改（一行级编辑）。

- **N-1 = 真修**。`types/log.f90:74,87` 加 `get_namespace`，`opt.f90:156` 是唯一调用者；无第二次加前缀（裸 `open(newunit=…)` 不经过 `open_file`）。默认名 `xtbopt.xyz`/`xtb.trj` **有断言**（`CMakeLists.txt:254-257` + Python `optnamespace` 步骤 1）；「第二次运行覆盖第一次」**有断言**（MD5 before/after `CMakeLists.txt:278,298-300`，内容比对 `landscape_cli_check.py:1117-1119`，且 `c1_text != c2_text` 防止空断言）。
- **N-2 = 部分修复**。我独立走读全部写出点：套件内**没有**任何绕过 `get_namespace`/`open_file` 的写文件（`grep 'file='|file="' src/landscape` = 0）。但表格漏了 `--lvib` 复用 `main_freq` 的**条件输出**：`xtbhess.xyz`（有虚频时，`hessian.F90:714`）、`xtb_enso.json`（`--enso`）、`xtb_localmodes`/`g98_locmode.out`（`set%pr_modef`）。三者都经 `open_file` ⇒ 也带前缀，**产品正确、表格不完整**。
- **N-3 = 已闭环**。50 号的 L-2/L-7/L-8/L-9 + I-1..I-8 **逐条**有处置，无「接受当已修」偷换；L-8 的 6 条 MAPLE fixture 路径我逐个核实存在（`sp/sp.out` 能量 −383.47223856 Eh、`ts/dmf/inp1_prfo_ts.xyz` 7 原子 1 帧均与报告一致）。两处**引用**错：53 §3 的 L-2 引用 `CMakeLists.txt:2967-2969` 实为 HCN product 块（正确位置 `:3018-3020`）。
- **N-4 = 部分修复**。70× 五处全部改对（我 grep 无残留 71×，除 50/52 复核者原文与 repo 根的会话 workflow js）；`json_counter` 真按解析整数比较；`--lvib-hessian file` 的 19→1 在 CMake+Python 双向断言。**但**「PLAN line 1805」残留 4 处：`tasks/scan.f90:245`、`test_landscape_scan.f90:1514,1547`、`landscape_cli_check.py:614`。
- **回归 = 无**。本轮非测试改动只有 `log.f90`（仅 opt 用，已 grep 证明；**任务书「`--lscan` 也用 log.f90」的前提不成立**，scan 自己写 `xtbscan.log`）、`main.F90` 的告警、`xhelp` 文本 ⇒ M2 的 `xtbscan.log` 命名未受影响，验收数字不可能动。
- 已知限制清单在 **`docs/xtb-landscape-M7-validation.md` §8.2**（+ 报告 53 §7）。

---

# 报告 54 — M7 最终独立复核（第三轮，read-only）

> 复核对象：`53-m7-final-fix-report.md`、`52-m7-review-round2.md`、`50-m7-independent-review.md`、`51-m7-fix-report.md`、`49-m7-validation-experiments.md`、
> `src/landscape/{types/log.f90,tasks/*}`、`test/unit/{CMakeLists.txt,meson.build,main.f90,landscape_cli_check.py,landscape_e2e_check.py,test_landscape_e2e.f90,test_landscape_scan.f90}`、
> `docs/xtb-landscape-M7-validation.md`、`docs/xtb-landscape-PLAN.md`、`src/prog/main.F90`、`src/xhelp.f90`。
> 复核者只读、未运行任何命令；工作树基线 = reviewer-launch HEAD（M7 未提交）。所有结论来自源码/测试/文档与已落盘证据文件。

## 0. 判定汇总

| 攻击面 | 判定 |
|---|---|
| 1 N-1（namespace 真的到 `--lopt` 了吗） | **真修**，默认名与「覆盖」后果**都有断言**；无双重前缀；对 `--lscan` 的同类检查早已存在（`xtbscan.log`），且 `--lscan` 不写几何/轨迹 ⇒ 无 N-1 类比物 |
| 2 N-2（输出 × namespace 表完整性） | **部分修复**：套件内所有写出点都过前缀（结构性证明），但 `--lvib` 的 3 个条件输出未入表；`landscape_sp.json` 无 namespace 断言（已声明为接受） |
| 3 N-3（50 号证据缺口） | **闭环**：12/12 逐条处置，正确；2 处引用/计数错 |
| 4 N-4（6 条 LOW） | **部分修复**：4.1/4.2/4.3/4.5/4.6 真修；4.4 残留 4 处旧指针 |
| 5 回归（M0..M6） | **无**；任务书关于 `log.f90` 共用性的前提有误，已更正 |
| 6 测试可证伪性 | 逐个判过；3 条依赖「两个收敛档几何必须不同」「vtight 必须收敛」的**软前提**（清单见 §8） |
| 7 文档承诺 vs 代码 | 残留 2 条实质矛盾：`xtbscan_2d.xyz`（PLAN:817 + `scan.f90:332`）、PLAN §5.5 的 `xtbopt.log`；1 条缺线程口径（`json.f90:34-36`） |
| 8 交付就绪性 | **M7 可提交、整套件可交付**；限制清单 = guide §8.2 + 报告 53 §7 |

**Merge verdict：OK with notes**（4 LOW 建议随提交改完；无阻塞项）。

## 1. N-1 逐条判定：真修

### 1.1 调用链逐行走读（写出路径是否都过前缀）

```
main.F90:943-949            (仅 --ljson 告警，与文件名无关)
  └─ p_run_lopt 分支 → tasks/opt.f90:156 landscape_optimize
       └─ landscape_write_files  (types/log.f90:57)
            log.f90:74  fname = get_namespace(trim(prefix)//'opt.xyz')   ← 修复点
            log.f90:75  open(newunit=unit, file=fname, …)                ← 裸 open，不再加前缀
            log.f90:87  fname = get_namespace(trim(prefix)//'.trj')      ← 修复点
            log.f90:88  open(newunit=unit, file=fname, …)
```
- `get_namespace`（`src/setparam.f90:589-607`）**非幂等**，只在 `persistentEnv%io%namespace` 已分配时前置一次；这里传的是**未加前缀**的 `'xtbopt.xyz'`（`settings%output_prefix` 默认 `'xtb'`，`types/settings.f90:482`）⇒ 恰好一次，M3 的 `ns.ns.hessian` 缺陷不会回来。我在 log.f90 中确认写文件用的是 Fortran 裸 `open`，**不经过** `open_file`/`iohandler::getName`，因此不可能二次加前缀。
- **唯一性**：`grep landscape_write_files src/` = `opt.f90:156` 一个调用点（其余是文档引用）。**任务书「`--lopt` 与 `--lscan` 共用 log.f90」不成立** —— scan 的几何帧由 `tasks/scan.f90:405-458`（`write_scan_profile`）/`:462-506`（`write_scan_grid`）自写 `xtbscan.log`，从不调用 `landscape_write_files`。
- **没有遗漏的第二个写出点**：`main.F90:1274-1283` 的 `xtbopt.xyz` 写入被 `runtyp ∈ {opt,ohess,omd,screen,metaopt,bhess}` 守卫，**不含**任何 `p_run_l*` ⇒ `--lopt` 的几何只可能由 log.f90 写（这也是 N-1 的根因，且修复位置正确）。
- 结构面：`grep "file='|file=\"" src/landscape` = **0 命中** ⇒ 套件里不存在绕过 `get_namespace`/`open_file` 的写文件；`open_file` → `filetools.F90:78` → `iohandler::writeFile` → `getName`（`iohandler.f90:112-131`）同样加前缀。

### 1.2 「默认名仍是 xtbopt.xyz / xtb.trj」有断言吗 —— 有

- CMake `xtb/landscape-opt-namespace` 第 1 段（`CMakeLists.txt:254-266`）：无 `--namespace` 时 `xtbopt.xyz`、`xtb.trj` 必须存在且非空；Python 镜像 `landscape_cli_check.py:1074-1088` 同断言（meson `landscape opt namespace`）。
- 另外 4 个既有目标（`landscape-opt-energy`、`-acc`、`-hessian`、`-scan-*`）本来就读未加前缀名 ⇒ 默认名是隐式回归护栏。

### 1.3 「第二次运行覆盖第一次」的后果真的被断言吗 —— 是，且不是空断言

CMake（`CMakeLists.txt:275-305`）：
1. `--namespace c1 --lopt-level loose` ⇒ 必须存在 `c1.xtbopt.xyz`（`:275-277`）；
2. `file(MD5 … c1_before)`（`:278`）；
3. `--namespace c2 --lopt-level vtight` 在**同一目录**跑；
4. `c1/c2` 的 `.xyz`+`.trj` 四个文件都必须存在（`:290-294`）；
5. `xtbopt.xyz` **必须不存在**（`:295-297`）；
6. `MD5 c1_after == c1_before`（`:298-300`）⇒ 覆盖即红；
7. `c1_text != c2_text`（`:302-305`）⇒ 防止「两次运行本来就是同一文件」把断言变成空测试。

Python 镜像逐条对应（`landscape_cli_check.py:1098-1120`），第 6 条改为读前/读后内容比对（`:1117-1119`）。**注入 xiii**（删掉两处 `get_namespace`，即修复前字节）⇒ `xtb/landscape-opt` 与 `xtb/landscape-opt-namespace` 双红（53 §1.5 记录），且 `xtb/landscape-opt` 的**清场**（`CMakeLists.txt:173-175`）是修复的一部分（否则复用 rundir 的残留会让注入假绿 —— 作者自己记录了这个发现，方法论合规）。

### 1.4 对 `--lscan` 的同类检查

已有且足够：`xtb/landscape-scan-cli`（`landscape2.xtbscan.log`）、`-scan-failed-point`（`landscape3`）、`-scan-max-steps`（`landscape4`）、`xtb/landscape-ljson-scan{2d}`（JSON 前缀 `e2ens.`，`landscape_e2e_check.py:505-512`）。双前缀会表现为 `landscape2.landscape2.xtbscan.log`，存在性断言即红。**scan 不写几何/轨迹 ⇒ 没有 N-1 的类比缺陷**。

### 1.5 无 M0..M6 回归

- `log.f90` 仅 opt 使用（上）；默认名不变 ⇒ `--lopt` 既有工具链（guide §2 手工命令、`landscape_e2e_check.py` 的 chain 消费 `xtbopt.xyz`，`:249-251`）不受影响。
- 单元 `test_landscape_optimize_xtb.f90:149-160` 用 `output_prefix='landscape_unittest'` 且**无 namespace**（`grep io%namespace test/unit` = 0）⇒ 名字不变。
- 核心层无 `xtbopt.xyz` 读取方（只有 `--mdopt` 读裸 `xtb.trj`，那是 MD 轨迹，与本套件无关）。

## 2. N-2：我独立列出的「输出 × namespace」完整表（与报告 53 对照）

判定规则：写出点若经 `get_namespace` 或 `open_file`，则带前缀（已由 `iohandler::getName` 证明）。**套件内 0 个裸字面名 open**。

| # | 文件 | 任务 | 写出点（file:line） | 前缀 | 报告 53 表 | 测试证明 |
|---|---|---|---|---|---|---|
| 1 | `landscape_<task>.json` | opt/scan/scan2d/vib/ts/irc | `types/json.f90:400` | ✅ | #3 ✅ | `xtb/landscape-ljson-{opt,scan,scan2d,vib,ts,irc}`（步骤 4，`landscape_e2e_check.py:505-512`） |
| 2 | `landscape_sp.json` | sp（API） | 同上同一行 | ✅（结构） | #4 ✅（已声明无测试） | 单元 `sp-ljson`（无 namespace） |
| 3 | `xtbopt.xyz` | opt | `types/log.f90:74` | ✅**（本轮修）** | #1 ✅ | 见 §1.2/§1.3（3 个目标） |
| 4 | `xtb.trj` | opt | `types/log.f90:87` | ✅**（本轮修）** | #2 ✅ | 同上 |
| 5 | `xtbscan.log` | scan 1D+2D | `tasks/scan.f90:419`/`:468` | ✅ | #5 ✅ | scan-cli / -failed-point / -max-steps / ljson-scan{2d} |
| 6 | `hessian`（写+回读） | vib | `types/hessian.f90:783`（写）/`:756`（读，带回退） | ✅一次 | #6 ✅ | vib-cli、vib-namespace（`ns.ns.hessian` 必须不存在） |
| 7 | `vibspectrum` | vib | `main/property.F90:754` → `open_file` | ✅ | #7 ✅ | vib-namespace（本轮加断言） |
| 8 | `vib_normal_modes` | vib | `tasks/vib.f90:390`（另有 `main_freq` 的 `set%pr_nmtm` 分支，默认 F） | ✅ | #8 ✅ | vib-namespace（本轮加） |
| 9 | `g98.out` | vib | `freq/io.f90` `g98fake2` → `open_file` | ✅ | #9 ✅ | vib-namespace（本轮加） |
| **10** | **`xtbhess.xyz`** | **vib，仅当存在虚频** | `hessian.F90:714`（`generateFileName`+`open_file`），由 `main/property.F90:791` 的 `distort` 调用（`imag==0` 提前返回） | ✅ | **缺失** | **无** |
| **11** | **`xtb_enso.json`** | **vib，仅 `--enso`** | `main/property.F90:771-777` → `open_file` | ✅ | **缺失** | **无** |
| **12** | **`xtb_localmodes` / `g98_locmode.out`** | **vib，仅 `set%pr_modef`** | `wrmodef.f90:172-173` → `open_file` | ✅ | **缺失** | **无** |
| 13 | `xtbts.xyz`/`xtbts.log` | ts 单几何 | `tasks/ts.f90:600`/`:612` | ✅ | #10 ✅ | ts-prfo / ts-namespace |
| 14 | `path.xyz` | ts neb/cineb/string/gsm | `ts.f90:772/800/824` → `write_path_frames` `:1239` | ✅ | #11 ✅ | path-cli / path-string |
| 15 | `path_autoneb.xyz`（=restart 文件） | ts autoneb | `ts.f90:772` → `:1239` | ✅ | #12 ✅ | path-autoneb（重启由 `--lts-autoneb-restart <file>` 显式给出） |
| 16 | `path_ts_list.xyz` | ts autoneb/string/gsm | `ts.f90:1298` | ✅ | #13 ✅ | path-autoneb / path-string |
| 17 | `irc_forward/backward/path.xyz` | irc | `irc.f90:779-785` → `:819`/`:861` | ✅ | #14 ✅ | irc-cli / -pc / -swap / -minimum |
| 18 | `irc.log` | irc | `irc.f90:948` | ✅ | #15 ✅ | irc-cli / -knobs |
| 19 | `charges`/`wbo`/`xtbtopo.mol`/`xtbrestart`/`xtbout.json`/`gfnff_*` | 全部 | 既有核心 `open_file` | ✅ | #16 ✅（无本套件测试，已给理由） | 核心侧 CLI 只断退出码（已声明） |

**差异结论**：报告 53 的表对「本套件自己的写出点」是**完整且正确**的（我逐点核对一致），但把 **`--lvib` 复用的 `main_freq` 路径的条件输出**漏了 3 项（#10-#12）。其中 **#10 `xtbhess.xyz` 是普通 CLI 可达**（`xtb <ts>.xyz --gfn2 --lvib [--namespace ns]` 必然有虚频）；#11/#12 需要 `--enso` / `set%pr_modef`（后者只能经参数文件，`--modef` 是 runtyp 不是开关）。三者都经 `open_file` ⇒ **产品行为正确（带前缀）**，问题只在表格的「完整」自述与测试覆盖。理由栏的另两项（#2 无 CLI、#16 核心自有）成立。

## 3. N-3：50 号 12 条逐条处置核验

| 50 号条目 | 53 号处置 | 我的核验 |
|---|---|---|
| L-2 chain-failure 文档与实现相反 | fixed（doc） | **真修**：`landscape_e2e_check.py:32-36`（step1 成功/step2 配错）与 `CMakeLists.txt:3018-3020` 已改；旧句「a failed first step must abort」grep 无命中。**53 的引用 `:2967-2969` 指错**（那是 HCN product 块）→ LOW-4 |
| L-7 负断言不清场 | fixed | **真修**：`chain-failure` `shutil.rmtree`（`landscape_e2e_check.py:305-306`）；`sp-ljson` 入口 `call delete_text`（`test_landscape_e2e.f90:509-512`）；两个新 namespace 检查入口清场（`CMakeLists.txt:173-175/243-244/859-861`、`landscape_cli_check.py:1060-1061/295-296`） |
| L-8 §9.8「各任务」只有 IRC | fixed | **真修**：`MAPLE_FIXTURES`（`landscape_e2e_check.py:804-811`）6 条；我**逐个核实文件存在**（`sp/sp.out`、`opt/lbfgs/inp1_traj.xyz`、`scan/C18_scan_final.xyz`、`ts/dmf/inp1_prfo_ts.xyz`、`freq/mw/inp1.xyz`、`irc/hpc/inp1_full.xyz`）；抽样核对数值：`sp.out` = `Energy: -383.4722385600 Hartree`（22 原子）、`ts/dmf/inp1_prfo_ts.xyz` 7 原子 1 帧 —— 与 53 表格一致；缺 fixture ⇒ `fail(...)`；conclusion 由实际读到的任务生成（`:988-1002`） |
| L-9 `--ljson` 静默 no-op | fixed（product） | **真修**：`main.F90:943-949` 告警 + `xhelp.f90:274-279` 文本 + 目标 `xtb/landscape-ljson-no-runtype`（`CMakeLists.txt:2938-2964`，断退出 0、断消息、断无文档）；注入 xii 红 |
| I-1 报告 48 的键序归属 | fixed | **真修**：`48-…md:79-83,183-187` |
| I-2 跨 OMP 非逐位 | accepted | 正确（PLAN §12.16:2162-2175、guide §4.2；全部 M7 目标钉 `OMP_NUM_THREADS=1`） |
| I-3 `n_imag=-1` / `n_eval` 语义 | accepted（51 已做） | 正确（PLAN §12.11 INFO-4 + §12.16 计数表） |
| I-4 hessian 文件二次投影 | accepted + 断言 | 正确（guide §7.7 + 19→1 断言） |
| I-5 单元 determinism 看不到 builder 非确定 | accepted, no action | 正确（CLI `ljson` 双进程字节比较） |
| I-6 CMake NaN 注释不精确 | fixed（comment） | **真修**（`CMakeLists.txt:969-976` 改为 §12.11 INFO-3 并说明 NaN 只出现在扫描表） |
| I-7 sp 无 runtyp | accepted | 正确（`48` §8.3、guide §4.1/§8.1 行 1、xhelp） |
| I-8 无注入钉频率容差 | fixed（evidence） | **真修**：注入 xi（`vib/modes.f90` ×1.0001 ⇒ chain 差 0.3700 > 0.20 红），并诚实声明 0.2 cm⁻¹ 以下按设计通过 |

**无「接受当已修」的偷换**（I-2/3/5/7 明确写 accepted，并给出载体）。唯一簿记小瑕：§0 汇总写「8 fixed / 3 accepted / 1 already fixed in round 51」，而表内 I-7 行写「accepted (documented)」—— 数字与行标签不完全一致（INFO）。

## 4. N-4 逐条

| 项 | 判定 | 证据 |
|---|---|---|
| 4.1 70× | **真修（5/5 处 + 报告 51 两行）** | `guide:178`、`landscape_e2e_check.py:30,102`、`PLAN:1380`、`51:30,278,340` 全为 70×；我 grep `71(×|x|X)` 在交付物内**无残留**（仅 50/52 复核者原文 + repo 根未跟踪会话 js，见 INFO-4） |
| 4.2 子串→整数 | **真修** | `test_landscape_e2e.f90:686-719` `json_counter`：`pattern = '"'//key//'": '` + 逐位取数字 ⇒ `"n_eval": 12` 不再满足 `1`；三处调用（`:472,477,535`）；注入 xiv 红 |
| 4.3 19→1 断言 | **真修且可红** | CMake `CMakeLists.txt:710-716`（direct=19）、`:759-765`（file=1）；Python `landscape_cli_check.py:243-250`（19）、`:265-274`（1 且 direct>file）⇒ 静默重算即红 |
| 4.4 旧行号指针 | **部分修复** | 已改：guide §6 标题、`48` §6、`CMakeLists.txt:969`。**残留 4 处 `PLAN line 1805`**：`tasks/scan.f90:245`、`test_landscape_scan.f90:1514`、`:1547`、`landscape_cli_check.py:614`（内容正确、仅指针旧） |
| 4.5 `n_cache_miss` 恒等口径 | **真修** | guide §4.2:295-311（限定 completed + 两个例外 + 「读码非实测」标注）；PLAN §12.11 INFO-5（diff `:1859-1874`）与 §12.16:2160-2166 同口径 |
| 4.6 `n_valid`/status/§8.2 | **真修** | guide §8.1 行 3（1D = converged∧evaluated `scan.f90:176-183`；2D = evaluated `:164`，指向 §4.2）；§4 的 status 段（`:250-258`）；§8.2 新增 7 行（PBC guard `landscape_driver.f90:73-77` 已核实存在；`grep set_landscape src/` = 0；`grep bias_path src/landscape` = 0） |

## 5. 测试可证伪性（逐条）

| 测试 | 故意写错对应逻辑会红吗 | 依据 |
|---|---|---|
| `xtb/landscape-opt-namespace` | **会**（注入 xiii 实测红）；双前缀/单文件覆盖/未加前缀三态各有一条断言 | §1.3 |
| `xtb/landscape-opt`（扩展） | **会**（xiii 红） | `CMakeLists.txt:189-203` |
| `xtb/landscape-ljson-no-runtype` | **会**（xii 红）；若「有告警但仍写文档」也被文档断言拦 | `:2951-2957` |
| `landscape-e2e sp-ljson`（整数计数） | **会**（xiv 红，且旧子串形式对同一错误文档绿 ⇒ 证明强化必要） | `test_landscape_e2e.f90:533-539` |
| `ljson-determinism` | 字节比较只能抓非确定量；计数已数值化；键序由 CLI 抓（`landscape_e2e_check.py:365-367`） | 与 52 §9 一致 |
| `vib-cli` / Python `vib` 19→1 | **会**（静默重算 ⇒ 19≠1 红） | §4.3 |
| `vib-namespace`（4 文件） | **会**：任一写出点丢前缀 ⇒ 未加前缀名出现 ⇒ 断言红 | `CMakeLists.txt:878-890` |
| `optnamespace`（Python 镜像） | **会**（同 CMake 条件） | `:1098-1120` |
| `maple`（per-task fixtures） | **会**：fixture 消失即 `fail`；`maple_importable` 真则 `fail`；error 空则 `fail` | `:922-983` |
| `chain-failure`（清场后） | **会**（x 红） | `:305-306` |
| `scan-counters` | **会**：`n_fail != omitted`、`n_valid ∉ [..]`、`n1*n2 != n_points` 均红 | `:425-462`、`:670-706` |

**软前提（非缺陷，需在运行清单里盯）**：① `xtb/landscape-opt-namespace` 依赖 `loose` 与 `vtight` **都收敛且几何不同**（`:302-305` 的 `c1_text != c2_text` 反向断言）；② 依赖 `vtight` 在默认步数预算内收敛（否则 `status != 0` 直接红）；③ 19 = 1+6N 依赖水分子 FD Hessian 的中心差分实现不变（合理 pin）。

## 6. 回归分析（M0..M6）

- 本轮**非测试**改动仅 3 个文件：`types/log.f90`（两个文件名）、`src/prog/main.F90`（一段 `env%warning`）、`src/xhelp.f90`（帮助文本）。**没有数值、没有收敛准则、没有失败语义改动**。
- `log.f90` 的调用者唯一（§1.1）⇒ **M2 的 `--lscan` 输出名（`xtbscan.log`）不可能受影响**；任务书「`log.f90` 是 `--lopt`/`--lscan` 共用路径」的前提应更正。
- 告警只在 runtyp ∉ 5 个 `p_run_l*` 时触发 ⇒ 任何 landscape 任务的行为/计数器/`env%nLog` 不受影响（`landscape_log_failed` 只比较调用前后的增量）。
- 验收数字（H2O 0.0100 / CH3OH 0.0600 / CO2 0.0000 / C2H2 0.0000 cm⁻¹）在本轮改动下**在数学上不可能变**，53 §4.7 的重测（逐位同 49/51）与该论证一致。

## 7. 文档承诺 vs 代码（残余）

1. **`xtbscan_2d.xyz`**：`PLAN:817`（§5.5 输出表「新增」）与 `src/landscape/tasks/scan.f90:332`（`!>` 说 2D 帧与之对齐）仍主张该名存在；实际 2D 写的是同一个 `xtbscan.log`（`scan.f90:468`），53 §2 自己也已声明「该名不存在」。⇒ **LOW-1**。
2. **`PLAN:812`（`xtbopt.log`，opt「沿用现有命名」）**：交付的 `--lopt` **不写** `xtbopt.log`（`log.f90` 只写两文件；53 §1.4 的实测列表也无此项），而 PLAN §9.2/§12.9 的 M1 验收只要求 `xtbopt.xyz`+`xtb.trj` ⇒ §5.5 表与 §9.2/代码三方不一致。⇒ 与 LOW-1 合并。
3. **`json.f90:33-36`**：模块 `!>` 写「two runs of the same input produce byte identical files」，未带线程数口径（实测跨 OMP ≤2.4e-10 不逐位；guide/PLAN 有该口径）—— 52 §10 的 INFO 未被 53 处置。⇒ **INFO-2**。
4. 其余 `!>`/xhelp 承诺抽查无假：`log.f90:25-30/51-56`（默认名 + 一次前缀）**与代码一致**；`vib.f90:26-40` 的 5 个文件名（含 `xtbhess.xyz`）与代码一致；`ts.f90:44-50`、`irc.f90:39-42` 与代码一致；`xhelp` 的 `--ljson` 文本已带「需要 `--l*`」的限定。

## 8. 需运行验证清单（复核者只读，无法执行）

```bash
export OMP_NUM_THREADS=1
cmake --build /tmp/xtb-land/build -j                                   # 期望 0 warning
ctest --test-dir /tmp/xtb-land/build -R landscape                      # 期望 95/95
ctest -N -R landscape | tail -1                                        # 期望 95
grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d # 期望空
ctest --test-dir /tmp/xtb-land/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'   # 12/12
```
1. **父会话原始复现**：`xtb w.xyz --gfn2 --lopt --ljson --namespace c1` ⇒ 目录内必须是 `c1.xtbopt.xyz`+`c1.xtb.trj`，**不得**出现裸 `xtbopt.xyz`/`xtb.trj`。
2. **默认名**：无 `--namespace` 的 `--lopt` ⇒ 仍是 `xtbopt.xyz`/`xtb.trj`。
3. **注入 xiii 复跑**（删两处 `get_namespace`）⇒ `xtb/landscape-opt` 与 `-opt-namespace` 双红；恢复后绿（并确认 `xtb/landscape-opt` 的清场仍在）。
4. **我新发现的条件输出（INFO-1 的验证）**：`xtb <bent-ts>.xyz --gfn2 --lvib --namespace ns` ⇒ 应出现 `ns.xtbhess.xyz`（虚频）且**无**裸 `xtbhess.xyz`；同目录 `--lvib --enso` ⇒ `ns.xtb_enso.json`。
5. **两个新 Python 模式手工跑**（meson 无法验证注册）：`landscape_cli_check.py optnamespace|ljsonnorun <xtb> <h2o.xyz> <tmp>` 期望 exit 0。
6. **验收四体系重测**：dfreq 0.0100/0.0600/0.0000/0.0000 cm⁻¹，dZPE ≤3.07e-7 Eh。
7. **软前提盯防**：连跑 `ctest -R landscape-opt-namespace` 3 次，确认 `loose`/`vtight` 都收敛且几何文本不同（若 vtight 偶发不收敛，该目标会红 —— 不是产品缺陷，但需知晓）。
8. **提交前**：`git status --porcelain` 确认无已暂存项；**必须加入** `docs/xtb-landscape-M7-validation.md`（未跟踪、且是已知限制清单的正本）；**不要加入** repo 根的 `m7-workflow.js`/`m7fix-workflow.js`/`m7final-workflow.js`（未跟踪会话文件）。

## 9. Findings

**CRITICAL 0 / HIGH 0 / MEDIUM 0 / LOW 4 / INFO 5。**

| ID | Sev | Finding | 位置 / 证据 | 最小修复 |
|---|---|---|---|---|
| L-1 | LOW（doc） | `xtbscan_2d.xyz` 仍被 PLAN §5.5 与 `scan.f90` 的 `!>` 声称为 2D 扫描输出，代码写的是同一个 `xtbscan.log`；PLAN §5.5 的 `xtbopt.log` 行同样不存在于交付的 `--lopt`。53 §2 已自认该名不存在却未回改这两处 | `PLAN:812,817`；`tasks/scan.f90:332`；反证 `tasks/scan.f90:468`、`53 §1.4` 实测列表 | 改 PLAN 两行为 `xtbscan.log`（2D 同文件）/ 删除或标注 `xtbopt.log`；`scan.f90:332` 改 `xtbscan.log` |
| L-2 | LOW（doc） | 53 的 N-4.4 声称旧行号指针已修，仍有 4 处 `PLAN line 1805` 存活（内容正确，仅指针旧） | `tasks/scan.f90:245`；`test/unit/test_landscape_scan.f90:1514,1547`；`test/unit/landscape_cli_check.py:614` | 统一改成 `PLAN §12.11 INFO-3` |
| L-3 | LOW（doc） | 交付 guide 仍写 93 个目标 / 93/93（本轮 +2 ⇒ 95） | `docs/xtb-landscape-M7-validation.md:39`（`# all landscape checks (93 targets, ~28 s)`）与 §8.3 表 | 改 95；顺手把 `optnamespace`/`ljsonnorun` 加进 §8.3 手工入口表 |
| L-4 | LOW（report） | 53 §3 的 L-2 行引用 `CMakeLists.txt:2967-2969`，该处是 HCN product 块；chain-failure 注释在 `:3018-3020` | `53 §3` vs `CMakeLists.txt:3018-3020` | 改引用 |
| I-1 | INFO | N-2 表缺 `--lvib` 复用 `main_freq` 的 3 个条件输出（`xtbhess.xyz` 普通 CLI 可达；`xtb_enso.json` 需 `--enso`；`xtb_localmodes`/`g98_locmode.out` 需 `set%pr_modef`）。三者经 `open_file` ⇒ 产品行为正确，仅表格「完整」自述与覆盖不足 | `hessian.F90:714`；`main/property.F90:754,771-777,791`；`wrmodef.f90:172-173` | 表里补 3 行（写「条件输出、经核心 `open_file`、带前缀」），或在表头声明「只列套件自身写出点」 |
| I-2 | INFO | `json.f90` 模块 `!>` 的字节同一性承诺缺线程口径（52 §10 的 INFO 未处置） | `types/json.f90:33-36` vs PLAN §12.16:2162-2175 | 加「同一 `OMP_NUM_THREADS`」半句 |
| I-3 | INFO | 53 §0 汇总「8 fixed / 3 accepted / 1 already fixed in round 51」与表内 I-7 行标签（accepted/documented）不完全一致 | `53 §0` vs `53 §3` | 统一标签 |
| I-4 | INFO | repo 根 3 个未跟踪会话文件仍含旧 71× 文本与内部提示词，且**未被 .gitignore 覆盖** | `m7-workflow.js`、`m7fix-workflow.js`、`m7final-workflow.js`（`watchdog_diff` 列为 untracked） | 提交时排除（或加入 .gitignore 的 session 段） |
| I-5 | INFO | 已知限制清单正本 `docs/xtb-landscape-M7-validation.md` 目前**未跟踪**，必须在本次提交中加入 | `watchdog_diff(path=docs/xtb-landscape-M7-validation.md)` = untracked | `git add` 该文件 |

## 10. 交付就绪性（明确回答）

- **M7 是否可提交：是。** 唯一功能性缺陷 N-1 已真修且有可红测试与注入证据；无 CRITICAL/HIGH/MEDIUM；4 条 LOW 全为文档/引用一行级编辑，建议随本次提交一并改完（L-1 与 L-3 是与交付文档正本直接冲突的两条）。提交时注意 INFO-4/INFO-5 的增删范围。
- **整套件是否可交付：是。** 16/16 入口点实现/测试/可达（guide §8.1，我核对行数为 16），无 stub；`--ljson` 生效且有可证伪测试；L3 链与 `ts→irc` 腿在真实 GFN2 上通过；G/H/ZPE 与 `--hess` 在**有来源的容差**内一致；MAPLE 诚实记录「未运行 + 深探失败 + 缺失依赖」，fixture 逐任务可核；D2 排除项与 PLAN §11 行已入 guide §8.2。
- **已知限制清单在**：`docs/xtb-landscape-M7-validation.md` **§8.2**（另有 §8.1 每入口限制列、§7 不可比项），补充于报告 53 §7（残留风险 6 条）与本报告 §9。