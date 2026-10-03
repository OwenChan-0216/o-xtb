# 24 — 阶段 1 last-mile 报告（MEDIUM-1 计数口径 + R38 指针 + LOW-1 调用点覆盖）

> 输入：复核 `23-stage1-final-review.md`（0 CRITICAL / 0 HIGH / 1 MEDIUM / 2 LOW）。
> 本报告只闭 MEDIUM-1、两处历史记录指针、LOW-1；不扩大范围。
> 构建：`/tmp/xtb-p1/build`（-O2，`WITH_CPCMX=OFF`，`OMP_NUM_THREADS=1`）。
> 基线：HEAD `a845def` + 阶段 1 未提交工作区。

---

## 0. 结论摘要

| 项 | 判定 | 证据 |
|---|---|---|
| MEDIUM-1 计数口径同步到 18 | **已闭合** | `11-*.md` 4 处（:89/:2818-2820/:2423/:2812）逐一改为权威口径；`13-*.md:66/87` 保留原样 + R38 指针 |
| 两处历史记录加 R38 指针 | **已闭合** | `18-*.md:369`、`21-*.md:395` 各一行指针 |
| LOW-1 `--ts` 调用点覆盖 | **已闭合（经父会话裁定走 (A)）** | `src/landscape/tasks/ts.f90` **+1 行可见性**（行为中性）；新单测 `ts-confirm-tighten-case`；**反突变红**「the upper case numerical source did not tighten」，还原后绿 |
| `ctest -R landscape` | **118/118 全绿** | §4.1 |
| 回归子集 | **12/12 全绿** | §4.1 |
| 无重名 | **0** | `grep -oE 'add_test\("xtb/[^"]+"' \| sort \| uniq -d` = 空 |
| BC-4 原生 runtype 逐位不变 | **通过（4 个 runtype 全部输出文件 `cmp` 逐位同）** | §4.3 |

越界检查：**无 `--method`**（未引入）；**核心层 0 改动**；**untyp 语义 / `--opt` / `--ohess` 分派 / 旗标名未动**；`src/landscape/tasks/ts.f90` 唯一改动是 §3.1 的 1 行可见性。

---

## 1. MEDIUM-1 — 破坏性计数口径全部同步到权威值 18

**权威值**：`A 3 + B 0 + C 8 + D 1 + E 1 + F 4 + G 1 = 18`（`11-*.md:2357` 汇总行、`:2237` R38 补丁行）。
**C8 已被 §17.1 的互斥 runtype 旗标占用，U17 不得再称「候选 C8」**（改称 C9）。

### 1.1 改动行号表

| 文件:行（改后） | 改前 | 改后 |
|---|---|---|
| `11-cli-redesign.md:89` | 结尾 `…F 4 + G 1 = 17 条** \|` | 追加 `；**R38（阶段 1 收尾）后 = A 3 + B 0 + C 8 + D 1 + E 1 + F 4 + G 1 = 18 条**（权威口径见 §10 汇总行） \|` |
| `11-cli-redesign.md:2818` | `**破坏性计数：R36 后为 17 条**（A 3 + B 0 + C 7 + D 1 + E 1 + F 4 + G 1），理由见 §10 末的 R29/R35/R36 注` | `**破坏性计数：R38 后为 18 条**（A 3 + B 0 + C 8 + D 1 + E 1 + F 4 + G 1），理由见 §10 末的 R29/R35/R36/R38 注` |
| `11-cli-redesign.md:2819` | `（R36 只在 F 类加了**已实施**的 F4，其余计数不变）。` | `（R36 只在 F 类加了**已实施**的 F4；R38 在 C 类补登 C8，其余计数不变）。` |
| `11-cli-redesign.md:2820` | `**若采纳 U17 → 17**（候选 C8，未定）。` | `**若采纳 U17 → 19**（候选 C9，未定；C8 已被互斥 runtype 旗标占用，见 §10 的 R38 订正）。` |
| `11-cli-redesign.md:2423`（§12 U17 行） | `**未定**：候选 C8（…计数 16→17），或…` | `**未定**：候选 C9（…计数 18→19，若采纳；C8 已被互斥 runtype 旗标占用），或…` |
| `11-cli-redesign.md:2812`（§16.8 U17 行） | `**登记为开放项**（候选 C8，计数 16→17），需用户/下一轮裁定；…` | `**登记为开放项**（候选 C9，计数 18→19，若采纳；C8 已被互斥 runtype 旗标占用），需用户/下一轮裁定；…` |

### 1.2 历史修订文档的指针（保留原样）

| 文件:行（新增） | 文本 |
|---|---|
| `13-cli-redesign-revision.md:66` | `\| **（R38 指针）** \| 本行为历史修订记录，保留原样；见 R38 后的权威计数 **18**（`11-*.md` §10 汇总行），且 U17 若采纳只能是 **C9**（C8 已被互斥 runtype 旗标占用，`11-*.md` §10 的 R38 订正） \| … \|` |
| `13-cli-redesign-revision.md:87` | `> **（R38 指针）** 保留原样（历史修订记录）。见 R38 后的权威计数 **18**（`11-*.md` §10 汇总行）；U17 若采纳只能是 **C9**（计数 18→19），C8 已被互斥 runtype 旗标占用（`11-*.md` §10 的 R38 订正）。` |

> `:65` 与 `:86` 两行（原「候选 C8（计数 16→17）」）**逐字保留**，仅在紧邻处加指针——遵循项目「订正留痕，不静默改写历史」。

**残留检查**：`grep -n "= 17 条\|候选 C8（套件\|计数 16→17" 11-*.md` 现在只剩 `:89` 里**同一行内**、标为历史修订链的 `R36 后…= 17 条`（紧接其后的就是 `R38 后…= 18 条`，与权威口径一致，非歧义）。

---

## 2. 两处历史记录加 R38 指针

| 文件:行（新增） | 文本 | 原状 |
|---|---|---|
| `18-stage1-impl-b.md:369` | `（R38 已裁定：D4 无代码变更，理由见 11-*.md §8.3/§17.3）` | `:367-368` 保留「D4 … 登记为**未实施**」 |
| `21-stage1-fix-report.md:395` | `（R38 已裁定：D4 无代码变更，理由见 11-*.md §8.3/§17.3）` | `§7` 第 5 条保留「…与 **D4**（设计自相矛盾）未处理，属范围外/待裁定」 |

> 只加指针行，未改写任何历史措辞。

---

## 3. LOW-1 — `--ts` 曲率带门的**调用点**覆盖

### 3.1 为什么原来的机制做不到（复核对，父会话裁定 (A) 的依据）

1. **CLI 在存储点就归一**：`src/prog/main.F90:2966` `ltset%hessian_source = landscape_lowercase(sec)`。
   ⇒ `--lts-hessian NUMERICAL` 到 `tasks/ts.f90:450` 时**已经是小写**；现有 `enumcase::ltshess`
   正是断言大写/小写都打印小写 `Hessian source: model` 且 118/118 绿。
   ⇒ 大写与小写在 CLI 下是**逐字节相同输入**，enumcase/CLI 级路线**原理上无法**区分
   「归一化谓词」与「字面比较」。
2. `can_tighten` 的唯一消费者在 `if (band_hit)` 内（`tasks/ts.f90:459` / `:486`），而真实体系
   `0±3 cm^-1` 带命中**不可构造**（`docs/_landscape-recon/30-m4-fix-report.md:48,184`）。
   实测 `--lts --lts-method dimer --lts-step {0.05,0.5,1.0,2.0}`（HCN 夹具）**均无** `near-zero curvature:`；
   step 5/10 直接 SCC 崩。
   ⇒ 任何「用生产路径 + 大写 settings」的行为测试，若不带带命中，也无法区分。

**唯一可行路线（父会话授权 (A)）**：把 `confirm_saddle` 做**可见性暴露**，用**合成 Hessian**
把一个真实内模放进带内，再以大写拼写驱动**生产子程序**。

### 3.2 src 改动（逐行，行为中性）

```
$ diff -u /tmp/ts_nomine.f90 src/landscape/tasks/ts.f90
--- /tmp/ts_nomine.f90
+++ src/landscape/tasks/ts.f90
@@ -113,6 +113,7 @@
    public :: landscape_ts_curvature_band_hit
    public :: landscape_ts_curvature_band_cm1
    public :: landscape_ts_can_tighten
+   public :: confirm_saddle   ! exposed for the curvature-band wiring test
    public :: landscape_ts_count_frames
    public :: landscape_ts_read_path
```

**新增行数 = 1**（`diff … | grep -c '^>'` = 1）。只改可见性：不改行为、不改签名、不改注释语义。
（`have to` 说明：这是把「原理上不可测」变成「可测」的最小改动。）

### 3.3 新单测 `ts-confirm-tighten-case`（`test/unit/test_landscape_saddle.f90`）

**位置**：模型 `band_hessian_model` 在 `:132-140`；夹具 `sym_water` 在 `:145`；用例注册在 `:196`；
子程序 `test_ts_confirm_tighten_case` 在 `:1063-1126`；模型过程 `band_evaluate`/`band_hessian` 在 `:1129-1166`。

**合成 Hessian**：`H = curvature * I`（各向同性，`curvature = 1e-10` hartree/bohr²，与水几何
`xyz_water`/`sym_water = O,H,H` 配合）。它不依赖 FD 步长，所以默认分辨率与收紧分辨率返回同一矩阵。

**本征值证据**（生产 `landscape_vib_analysis` 的实测全谱，临时诊断运行，已移除）：

```
DIAG-SPECTRUM n_zero=6 freq(cm^-1):
  mode 1..6    0.000000          <- 6 个投影刚体零模（恰为 0，正确分类）
  mode 7       0.048443          \
  mode 8       0.049068           > 3 个内模，全部落在 0 +/- 3 cm^-1 带内
  mode 9       0.051202          /
```

**断言的可观测输出**（不是「不崩溃」）：

| # | 断言 | 含义 |
|---|---|---|
| 1 | `lower` 含 `near-zero curvature:` | 合成 Hessian 真的进带（≥1 内模在 ±3 cm^-1） |
| 2 | `lower` 含 `tightened re-decision:` | 小写 `numerical` 真的走收紧分支 |
| 3 | `upper` 含 `tightened re-decision:` | 大写 `NUMERICAL` 走**同一**分支 |
| 4 | `upper == lower`（逐字节） | 两种拼写同一可观测（除拼写外无其它差异） |
| 5 | `nlog_upper == nlog_lower` | 大写不比小写多记一条 `cannot be re-decided` 警告（`env%warning` 只入 log、不直接打 unit，故用计数观测） |

**生产确认输出**（小写、绿，临时诊断运行）：

```
 near-zero curvature: a mode lies inside 0 +/-    3.000 cm^-1
   recomputing the Hessian with step  2.000E-03 bohr and sccacc  1.000E-01
   tightened re-decision: lowest internal mode             0.05 cm^-1 (was  4.844E-02
 )
 saddle confirmation - imaginary modes: 0
 confirmation: minimum (0 imaginary modes) - not a transition state
```

两条拼写的该输出**逐字节相同**（`upper == lower` 断言通过）。

### 3.4 反突变（核心）：调用点改回字面比较 ⇒ **红**

突变（`src/landscape/tasks/ts.f90:451`）：

```
-   can_tighten = landscape_ts_can_tighten(settings%hessian_source)
+   can_tighten = trim(settings%hessian_source) == 'numerical'
```

真实输出：

```
$ OMP_NUM_THREADS=1 ./xtb-tester landscape-saddle
  Starting ts-confirm-tighten-case ... (29/43)
       ... ts-confirm-tighten-case [FAILED]
  Message: the upper case numerical source did not tighten
  Starting driver-rigid-projection ... (30/43)
```

（suite 退出码 = 1。`ts-can-tighten-case` 仍绿——正是复核 LOW-1 描述的「谓词有单测、调用点无」情形，新用例补上了这一环。）

突变下大写路线的确认输出（临时诊断）证明走的是**另一条分支**：

```
DIAG-UPPER>>>
 near-zero curvature: a mode lies inside 0 +/-    3.000 cm^-1
 saddle confirmation - imaginary modes: 0
 confirmation: minimum (0 imaginary modes) - not a transition state
<<<DIAG-UPPER
```

即：进带成立、但**没有** `recomputing the Hessian` / `tightened re-decision` 两行
（`can_tighten = false` 落进 `else if (.not. can_tighten)`，该警告只入 `env%log`，由断言 5 的
计数不等捕获）。

**还原后**：

```
  Starting ts-confirm-tighten-case ... (29/43)
       ... ts-confirm-tighten-case [PASSED]
```

### 3.5 更新后的零覆盖清单（本项）

- **LOW-1「曲率带门的接线」（`tasks/ts.f90:450`）** → **已闭合**：`ts-confirm-tighten-case`
  （生产子程序 + 合成带内 Hessian + 大小写两端 + 逐字节/计数双断言 + 反突变红）。
- `21-*.md §3.1 R2` 的表 ts 行（`tasks/ts.f90:449`）此前记「CLI 不可达、无红得起来的测试」：
  该判断对**存储点归一**仍成立（`main.F90:2966` 归一 ⇒ CLI 不可达），但**调用点的接线**现已可测并已覆盖；
  表格其余条目（R3 `--lscan-expo`、R4 `--lts` band 措辞、R5 banner 溢出）与 `R1`（lirc 存储点）
  **保持原状**（理由见 `21-*.md §3.1` / `22-*.md §2`），本项不涉及。
- 附带：`confirm_saddle` 现为 public（可见性），无新增零覆盖项（其行为由既有 `xtb/landscape-ts-*`
  CLI 测试 + 本新单测覆盖）。

---

## 4. 验收

### 4.1 测试

```
$ OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-p1/build -R landscape
100% tests passed, 0 tests failed out of 118
$ OMP_NUM_THREADS=1 ctest -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'
100% tests passed, 0 tests failed out of 12
$ grep -oE 'add_test\("xtb/[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d
(空)
```

新用例在**既有 target** `xtb/landscape-saddle`（CMake `:50` / meson `:61` 的单一注册）内，
**无新增 `add_test`** ⇒ 118 不增；用例名 `ts-confirm-tighten-case` 与全仓无重名。
（`test/unit/meson.build` 无需改：套件名不变，例收集在 `test_landscape_saddle.f90` 的 `collect_*` 内。）

### 4.2 逐位构建证据

```
$ cmake --build /tmp/xtb-p1/build -j    # 0 error
```

### 4.3 BC-4（原生 runtype 输出逐位不变）— 方法同报告 19 强基线

- 强基线：`/tmp/xtb-p1v/head-build/xtb`（HEAD `a845def` 干净 worktree、同配置）。
- **只在构建目录内**把 p1 的 `include/xtb_version.fh` 写成基线串（`6.7.1 (a845defedfebcea80f94f16e0e22e139dc44d400)`）后重建，
  验证完**已还原**为 `6.7.1 (unknown-commit)` 并重建。
- harness `bc4.sh`：4 个原生 runtype（`--sp` / `--hess` / `--ohess normal` / `--md`，`$seed 42`），
  同目录同路径、只换二进制。

| runtype | 输出文件数 | `cmp` 逐位相同 |
|---|---|---|
| `--sp` | 3 (`charges`/`wbo`/`xtbtopo.mol`) | **3/3** |
| `--hess` | 7 | **7/7** |
| `--ohess normal` | 9 | **9/9** |
| `--md` | 55 | **55/55** |

⇒ 4 个原生 runtype 的**全部输出文件 raw `cmp` 逐位相同**（含 `xtbtopo.mol`）。

---

## 5. 纪律 / 未越界

- 只改 `docs/` + `test/`；`src/` 仅**父会话授权的 1 行可见性**（§3.2）。
- **未**引入 `--method`；**未**改 runtyp 语义、`--opt`/`--ohess` 分派、核心层、旗标名。
- `OMP_NUM_THREADS=1`；未跑全量 ctest；未 `find /`；未碰 `/tmp/xtb-w0/build`、`/tmp/xtb-land/build`；未提交 git。
- 临时诊断代码（DIAG 打印、临时 `landscape_vib_analysis` 调用、临时 import）**已全部移除**，最终测试文件不含。

## 6. 未验证 / 限制

- 单测用**合成各向同性 Hessian**（非真实 GFN2 面）；它证明的是**接线**（拼接与分支），
  不证明真实体系带命中的数值——真实带命中仍按 `30-*.md` 记为不可构造。
- BC-4 的 `/tmp/xtb-p1v` 证据与报告 19 一样属构建目录工件，仓库内不可重放（命令见 §4.3）。
- `upper == lower` 的逐字节相等依赖两次运行除拼写外无差异（`printlevel=1`、固定合成矩阵）；
  若将来 `confirm_saddle` 打印了 `hessian_source` 本身，该断言需相应放宽为「非拼写行相等」。
