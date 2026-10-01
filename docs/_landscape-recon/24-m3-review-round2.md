## 摘要（≤30 行）

**结论：有条件接受（修正轮实质修复成功）；M3 功能可宣称完成，但先补 2 项欠账（P1 一条 + 报告/PLAN 措辞一条）。CRITICAL 0、P1 1、P2 5、INFO 4、无新增 CRITICAL。**

| 第 22 号发现 | 判定 | 关键证据 |
|---|---|---|
| HIGH-1 未初始化下标 | **已修复（真修）** | `modes.f90:209-218` 第二循环改为只跳过前 `n_zero` 个近零模 + `:220` 不变量检查；两条分支（线/非线性、extras=0/>0）都证明 `order(1:n3)` 全赋值；新测试 `extra-zero-modes` 走 extras 路径且断言可证伪（重复/未赋值列必坏正交性） |
| MEDIUM-A 双重前缀 | **已修复** | `tasks/vib.f90:284` 传 `'hessian'`，唯一前缀在 `types/hessian.f90:783`；写/读所有路径（数值 / file provider / `--namespace` / 1D/2D/双向 scan 的 `xtbscan.log`）均单前缀 |
| MEDIUM-B `etemp` 死字段 | **已修复但只修了一半** | `engine.f90:312-319` 推入计算器、`:292` 调用、`:793` 打印生效值 —— 机制正确、测试 `etemp-control` 可证伪（去掉 push 转红）。**但**：`engine_report` 只被 `sp:150/opt:142/scan:205` 调用，`--lvib` 的 engine 在 `numhess.f90:115` 建、`:150` 销毁，**从不打印生效 etemp**（P2-B）；`main.F90:938/955/971` 的 CLI 同步 **零测试覆盖**（P1-1） |
| MEDIUM-C 归因 | **已修复（结论有证据）** | `--hess` 确为 FD（`src/hessian.F90:244` `calc%hessian`→numdiff；`main.F90:2844` 标签是固定串）；`trproj` 签名 `project.f90:151` 无梯度参量，"含梯度项"确为错；同矩阵分解 0.074/5.213/12.91 与 CLI 0.0757/5.2109 量级自洽。**但**：PLAN §12.11 写"差异全部来自投影"与它自己"0.0036 是非投影残余"矛盾（P2-2）；"∝‖g‖"是无数据机制句（P2-3） |
| LOW-1/2/3 | 已修 | 告警 `vib.f90:215-218` 阈值/措辞与 `--hess` 一致（`vec_norm` 确为 L2）；`check_thermo_settings` `:232-263` 在首个 SP 前集中校验；`results.f90:51-53`、`hessian.f90:666-677` 注释已改对 |

**M3 是否可宣称完成**：功能与数值链可以（修复轮 4 项发现均实质关闭且可证伪）。**进 M4 前必须解决**：P1-1（为 `engine%etemp ← set%etemp` 补 CLI 测试，或把 `etemp` 默认值改成"无哨兵"避免 M4 新入口忘同步即静默 300 K）+ P2-B 的措辞（PLAN §9.5 的 M4 gate 正引用它）。其余 P2 可选。

**需运行验证**：R1 `ctest -R landscape`=35/35 + 回归 12/12 + `ctest -N` 与 `uniq -d` 查重（我手工核对 24 个 CLI 名与 11 个单元套件名无重名）；R2 `-fcheck=all` 复跑 `extra-zero-modes`；R3 `--etemp 300|5000 --lvib` 对比 `eigval`；R4 `--lvib-hessian file --lvib-hessian-file hessian` 两次看输入文件是否被改写。

**无 CRITICAL 的攻击面**：HIGH-1 两条排序分支的赋值完备性、近零模分类物理语义（对照 `src/hessian.F90:437-447`）、`n_imag` 与 `imag_cutoff`、`check_thermo_settings` 的 4 参数与温度数组边界、`etemp` 推入的作用域与全局污染、`--namespace` 全部读写路径、`vec_norm`/`norm2` 一致性、`diagHessian` 输出约定与失败路径、`file` provider 回归、测试注册三处一致与重名、M0/M1/M2 回归面。**无法覆盖**：修复轮的精确 delta（`src/landscape/vib/*`、`tasks/vib.f90`、`test_landscape_vib.f90` 仍为 untracked，`watchdog_diff` 只能给 M3 全量 diff）。

---

# 24 — M3（vib）修复轮独立复核（第二轮）

> 角色：fresh-context read-only 复核者。输入：`23-m3-fix-report.md`（修复轮报告）、`22-m3-independent-review.md`（第一轮）、
> `21-m3-validation-experiments.md` + `m3-vib-data/`、`20-m3-vib-implementation-report.md`、`AGENTS.md`。
> **本轮只读、无 shell**：所有"已修复"判定以源码逐行为准；数值行为以仓库内已记录数据 + 代码可证性为准。
> 任务：找出"测试全绿但仍然错误"的地方；逐条判定第 22 号发现是否真修；给 file:line 证据。

## 0. 元信息与限制

* 工作区 = HEAD + 未提交改动。`watchdog_diff --stat` 显示 `src/landscape/vib/{modes,numhess,thermo}.f90`、
  `src/landscape/tasks/vib.f90`、`test/unit/test_landscape_vib.f90` **仍是 untracked**，因此**无法**用 diff 隔离
  "修复轮相对实现轮的 delta"；本复核只以当前文件内容为准（这也意味着第 22 号 LOW-3.4「交付物未 `git add`」**仍未关闭**）。
* 未运行任何命令/测试；所有需要在机器上确认的事项集中在 §8「需运行验证」。
* 未修改任何文件。

## 1. 结论摘要

| 项 | 判定 | 一句话依据 |
|---|---|---|
| HIGH-1（UB + 未初始化下标） | **已修复（真修，非表面修）** | 排序内核重写 + 不变量 + 可证伪新测试；两条分支均证明 `order` 全赋值 |
| MEDIUM-A（`--namespace` 双重前缀） | **已修复** | 命名空间只剩单点（`open_hessian_for_write`），写→读在全路径闭环 |
| MEDIUM-B（`engine%etemp` 死字段） | **机制已修复；验证只做了一半** | 推入计算器的机制正确且单测可证伪；但 CLI 同步无测试（**P1-1**）、`--lvib` 不打印生效值（**P2-B**） |
| MEDIUM-C（归因错误） | **已修复（结论有实测支持）** | `--hess` 亦为 FD 已被代码证明；投影归因与三点分解自洽；但措辞有 2 处过头（**P2-2/P2-3**） |
| LOW-1/2/3 | 已修（LOW-1 无测试覆盖，见 **P2-4**） | 代码与注释均已改对 |
| 新增回归风险 | 有 1 条 | 修复轮引入了 `engine%etemp ← set%etemp` 的耦合，改一行即静默回退且测试全绿（**P1-1**） |

**总判定：有条件接受。** M3 的数值链与功能面可以宣称完成；下面 P1/P2 属"可验证性 / 文书一致性 / 用户可见性"欠账，
不改动任何数值结果。

## 2. HIGH-1 逐项核验（任务书重点 1）

### 2.1 `order(1:n3)` 是否每条路径都被完全赋值 —— **是**

`src/landscape/vib/modes.f90`：

* 线性分支 `:182-184`：`do i = 1, n_zero; order(i) = i`（`n_zero = 5`，单原子时 `n_zero = n3 = 3`）。
* 非线性分支 `:186-194`：按升序取**前 `n_zero` 个** `|f| < zero_mode_tol` 的模式写入 `order(1..n_zero)`，
  多出的置 `extra_zero = .true.`（不写下标，符合设计）。
* `:196-203`：若不足 `n_zero` 个近零模 → `env%error` + `return`（与 `src/hessian.F90:437` 同语义）。
* 第二循环 `:209-218`：
  ```fortran
  k = n_zero; n_zero_seen = 0
  do i = 1, n3
     if (.not. linear .and. abs(freq_cm(i)) < zero_mode_tol) then
        n_zero_seen = n_zero_seen + 1
        if (n_zero_seen <= n_zero) cycle
     end if
     if (linear .and. i <= n_zero) cycle
     k = k + 1; order(k) = i
  end do
  ```
  赋值个数 = `n3 − (#跳过的近零模)`。第一循环与第二循环的判据是**严格互补**（`:187` 用 `>= tol → cycle`，
  `:212` 用 `< tol`），所以两者认定的"近零集合"逐元素相同；跳过的必然是 `order(1:n_zero)` 那 `n_zero` 个 ⇒
  `k` 恰为 `n3`。加 `:220` 的 `k /= n3 → env%error` 兜底 ⇒ **不存在未赋值槽位**，UB 消除。
* 使用点 `:229-239` 全部落在 `1..n3` 已赋值区间。

**结论**：HIGH-1 是"处理正确"而非"掩盖"。新测试构造的路径（rank-1、8 个近零模）确实走到 extras 分支。

### 2.2 不变量检查能否被绕过 —— **不能被绕过，但它不是安全网**

`:220` 的 `k /= n3` 在本逻辑下**不可达**（这正是它作为"不假设"断言的意义）。唯一能造成"重复下标而非计数错误"的
输入是 `freq_cm` 含 `NaN`：`abs(NaN) >= tol` 与 `abs(NaN) < tol` 同时为假，两个循环分类不一致 → `order` 出现重复项、
`k` 仍等于 `n3`，不变量检查**不会**报警，随后 `vib%modes` 出现重复列（正交性被破坏）。
**但这不可达**：`freq_cm = autorcm*sign(sqrt|ev|, ev)`，`ev` 来自 `syev`；`file` provider 明确拒绝非有限输入
（`types/hessian.f90:500-506`），数值 provider 在 SCC 失败时 `env%error` 返回。→ 记为 **INFO-1**（可读性建议：
把判据改成 `mergesort` 式一致谓词或直接检查 `order` 的置换性），不是缺陷。

### 2.3 extras 归入"最低内模"是否物理正确、是否与 `src/hessian.F90:437-447` 语义一致 —— **是，且更有契约一致性**

* 既有实现的语义（`src/hessian.F90:435-447` + `:471-490`）：`izero` 收集**全部** `|f|<0.01`，`h(1:n3,1:kend)` 只用前 `kend`
  个；内模循环只收 `|f|>0.01`，**够不到**的列保持 `h=0` 的零向量 + `isqm=0`（即"丢模式但保持 3N 列"）。
* 套件的语义（模块文档 `modes.f90:53-64`）：前 `n_zero` 个是投影零模，其余近零模**按升序保留为最低内模**，带自己
  （带符号的噪声）频率；`n_vib == 3N − n_zero` 无条件成立。
* 判据：两者都保持 `3N` 列；套件给出**正交归一的真实本征向量**，既有实现给零向量（非正交、非本征向量）；
  且套件不再"丢失一条模式"。对一个 `|f| < 0.01 cm^-1` 的模式，"是秩亏残留刚体模还是软坐标"无法从频率区分，
  保留带符号的噪声值至少不把符号抹掉（正的噪声不会被写成虚频）。**因此该策略至少与既有语义等价、且更贴合本模块
  "从不丢弃模式"的承诺。** 唯一副作用：`vib%n_imag = count(freq(n_zero+1:n3) < imag_cutoff)`（`:248`）在
  `imag_cutoff` 被用户设成极小负值（如 `-1e-6`）时会把噪声负模计成虚频——这是既有 `--lvib-imag-cutoff` 的语义，
  非新增缺陷（INFO-2）。

### 2.4 新测试是否"真走到"该路径、断言是否恒真

`test/unit/test_landscape_vib.f90:505-581`：合成 3 原子（第 3 个原子在 `(2,0,4)` bohr，行列全零）的 rank-1 Hessian：

* **确实走 extras 分支**：rank 1 → 投影后 1 个非零本征值 + 8 个近零 → `n_zero=6`、2 个 extras。
  几何还有一条**精确对称性**（原子 1/2 的 x 相同 ⇒ 6 条刚体向量的 z 分量对原子 1/2 逐位相等 ⇒
  `P A P` 在 `{x,y,z}×{3,6}` 之外**精确为 0**）——这解释了为什么 `:550` `count(|f|>1e-6)==1` 与
  `:556` `maxval(|f(7:8)|)<1e-6`（等价 |λ|<2.1e-23 a.u.）这样紧的阈值得以满足：2×2 块 [[a,b],[b,d]] 的
  小本征值 ~`(a−d)²/8c` ≈ 1e-38，而不是一般的 `ε‖A‖`≈5e-20。报告 23 记录的"通过"与这一论证互相印证（INFO-3）。
* **可证伪**：`:563-575` 的逐列归一 + 两两正交检查是关键——旧代码（第二循环 `cycle` 掉所有近零模）会留下
  未赋值 `order` 槽位，取到重复/越界列 ⇒ 归一/正交必然失败或崩溃（报告 23 §1.3 的 SIGSEGV 注入与之相符）。
* **恒真断言 1 条**（无害）：`:547` `maxval(abs(vib%freq(1:6))) == 0.0` —— 实现 `:235` 无条件把前 `n_zero` 个频率
  写成 0.0，所以这条**任何实现都通过**；真正的约束由 `:550/:556/:563-575` 承担。（INFO-4）
* 未覆盖：extras 与 `--lvib-no-project` 的组合、extras 存在时 `n_imag` 的行为（不必要）。

## 3. MEDIUM-A 核验（重点 2）

* 修复点：`src/landscape/tasks/vib.f90:284` `call landscape_write_hessian_file(env, 'hessian', hess, ok)`；
  命名空间唯一施加点 `types/hessian.f90:783`（`open_hessian_for_write`）。
* 读路径 `types/hessian.f90:743-768`：先试 `<ns>.<name>`，失败再回退 `<name>` ⇒ 单前缀闭环。
* 全仓库 `get_namespace` 调用点只有 4 处（`tasks/vib.f90:315`、`tasks/scan.f90:272,321`、`types/hessian.f90:756,783`），
  **每处只加一次**，无第二处二次加前缀。
* scan 的 1D/2D/双向写盘（`tasks/scan.f90:272,321`）与 `vib_normal_modes`（`vib.f90:315`）都不受影响；
  `--lscan-hessian-file` 走同一 `file` provider ⇒ 1D/2D/双向/file 四条路径均闭环。
* 新 CLI 测试 `xtb/landscape-vib-namespace`（`CMakeLists.txt:684-689` + 生成脚本 `:640-683`）断言：`ns.hessian` 存在、
  `ns.ns.hessian` 不存在、第二次运行（`--lvib-hessian file --lvib-hessian-file hessian --namespace ns`）exit 0
  且 `eigval` 行相同。**exit-0 部分强（找不到文件必然非零退）**；`eigval` 字符串比较部分偏弱（见 P2-5）。

## 4. MEDIUM-B 核验（重点 3）

**机制**（读码确认，与报告 23 §3.1/§3.2 一致）：

* `engine.f90:277-296` `set_calculator` 深拷贝后 `:291` 写 `acc`、`:292` `call push_calculator_etemp(self)`；
  `:312-319` `select type (calc => self%calc); type is (TxTBCalculator); calc%etemp = self%ctrl%etemp`。
* 计算器实际用自己字段（`src/xtb/calculator.f90:259/268` → `self%etemp`），构造时从 `set%etemp` 拷一次（`:144`）；
  `xtb_single::singlepoint` 丢弃 `et` 参数 ⇒ 推入是唯一有效途径。**死字段确实已复活。**
* **无全局污染**：全程只写引擎私有副本（`calc` 是 `allocate(source=calc)` 的深拷贝），不写 `set%etemp`；
  因此不存在"提前 `return` 未恢复"的问题（这正是选方案 (a) 的额外好处）。`--gfnff`/其它计算器走 `select type`
  无操作分支。

**测试强度**：`test_landscape_vib.f90:596-661`：`settings%engine%etemp = 300 / 5000`，同一 `chk`、`restart_mode`
默认 `off`（`settings.f90:117`）⇒ 不存在 warm-start 漂移伪造差异；断言 `cold > 100` 与 `|Δf|/f > 10 %`
（实测 −31 %）。去掉 `push_calculator_etemp` ⇒ 两次都 300 K ⇒ 偏差 0 ⇒ 转红（报告 23 §3.3 有真实输出）。
**该测试确实证明了"改变该旋钮会改变频率"**（对库路径而言）。

**两处未闭合**：

* **P1-1（新）**：`main.F90:938/955/971` 的 `lset/lsset/lvset%engine%etemp = set%etemp` 是**修复轮新增的耦合**：
  `push_calculator_etemp` 无条件覆盖，`landscape_engine_control%etemp` 默认硬编码 300 K（`settings.f90:107`），
  而 `set%etemp` 默认也是 300 K（`type/options.f90:176`）。因此**删掉那三行 ⇒ `--etemp 5000` 对所有 landscape 任务
  静默退回 300 K，而全部测试仍然绿**（`grep -r etemp test/` 无任何 CLI/单元测试使用 `--etemp`）。修复轮把一个
  原本"构造器自动带 `set%etemp`"的行为改成了"必须由 main.F90 同步"，却没有为这条不变量留下守卫。
* **P2-B（新）**：报告 23 §3.2 与 PLAN §12.11/§9.5 声称"`engine_report` 从计算器读回并打印生效值，使设置没进去
  从外部可见"。实际 `engine_report`（`engine.f90:770-802`，etemp 打印在 `:790-796`）的调用点只有
  `tasks/sp.f90:150`、`tasks/opt.f90:142`、`tasks/scan.f90:205`；**`--lvib` 的 engine 实例在
  `vib/numhess.f90:115` 创建、`:150` 销毁，从不调 `report`**，且 `tasks/vib.f90` 的 printlevel 块只打印
  restart/source/step/sccacc/project（`:110-125`）。⇒ 对本里程碑交付的 `--lvib`，"实际生效值"既不打印也不落盘；
  PLAN §9.5 的第 1 条 gate 引用了一个对 vib 不成立的机制。

## 5. MEDIUM-C 核验（重点 4）

**代码一致性（已逐条核对）**：

* `--hess` 是数值 Hessian：`src/hessian.F90:241-244` 走 `calc%hessian(...)`（`TxTBCalculator` → `hessian_numdiff`），
  `main.F90:2844` 的 `'analytical hessian'` 是 `mode_extrun /= turbomole` 分支的固定标签 —— 报告的纠正是对的。
* `trproj` 不含梯度项：其签名 `src/freq/project.f90:151` `subroutine trproj(natoms,nat3,xyz,hess,ldebug,nmode,mode,ndim)`
  **根本没有梯度参量** ⇒ 旧机制句不可能成立。✔
* 投影调用条件一致：`src/hessian.F90:355-369` `if (.not. res%linear)` 与套件 `modes.f90:146-148`
  `if (settings%project_tr .and. .not. linear)` 同构；`--hess` 写盘的也是**非质量加权、已投影**矩阵
  （`hss` → `wrhess`，`hessian.F90:352-382`）⇒ 文件语义与套件一致。✔
* 数据自洽：同矩阵分解 0.074（极小点）/5.213（非驻点）/12.91（强扭曲）与 CLI 0.0757/5.2109 同量级；
  CO2（两路径都跳投影）残余 0.0036 ⇒ 投影项 ≈ 0.072（极小点），量级闭合。✔

**两处措辞过头（P2-2/P2-3）**：见 §7 发现清单。

## 6. 新/改测试可证伪性逐条

| 测试 | 判定 | 依据 |
|---|---|---|
| `extra-zero-modes`（新） | ✅ 可证伪（1 条恒真断言）：归一/正交 + `count(|f|>1e-6)==1` + `freq(9)>1000` 会在"重复/未赋值列"或"丢模式"时转红；`:547` 的 `freq(1:6)==0` 恒真 | §2.4 |
| `etemp-control`（新） | ✅ 可证伪（库路径）：去掉 push → 偏差 0 → 转红；`restart_mode=off` 排除 warm-start 伪差异 | §4 |
| `water-vs-trproj`（修） | ✅ 修好了恒真缺陷：`:403-405` 保存 `raw`、`:418-427` 参照走 `trproj`、`:447` 反向断言 `maxval|Δ|>1.0` 阻止把参照换回投影矩阵；容差 `0.005|f|+0.5` 为实测 12.91 的 25 倍裕度 | 代码 + 报告 23 §4.3 |
| `xtb/landscape-vib-namespace`（新） | ⚠️ 主断言强（文件存在性 + 第二次 exit 0），但 `eigval` 相等断言在正则**不匹配**时两侧都为空而恒真（P2-5） | `CMakeLists.txt:663-683` |
| `xtb/landscape-vib-temperature-invalid` / `-imag-cutoff-invalid`（新） | ✅ 可证伪：脚本要求 `status != 0` **且**匹配消息（`:399-404`）；`check_thermo_settings` 在首个 SP 之前（`vib.f90:103`）| `CMakeLists.txt:715-726` |
| LOW-1 新告警 | ❌ 无任何测试断言 `INCOMPLETELY`（`grep -r INCOMPLETELY test/` 为空） | P2-4 |

## 7. 发现清单

### P1-1（可验证性/回归守卫，改一行即静默回退）：`--etemp` 与 landscape 的 CLI 同步零覆盖

* **位置**：`src/prog/main.F90:938,955,971`（新增同步） ← `src/landscape/engine/engine.f90:292,312-319`（无条件覆盖）
  ← `src/landscape/types/settings.f90:107`（默认 300 K） ← `src/type/options.f90:176`（`set%etemp` 默认 300 K）。
* **现象**：删除任一同步行（或 M4 新入口漏写），`--etemp <T≠300>` 会被引擎默认值覆盖；`--lvib` 的频率/热化学
  与 `--lopt/--lscan` 的轨迹都静默变成 300 K，而 `ctest -R landscape`(35/35) 与回归子集(12/12) **全绿**
  （`grep -r etemp test/` 显示无任何 CLI 测试传 `--etemp`）。
* **为什么是问题**：修复轮把"构造器自动继承 `set%etemp`"换成了"引擎控制唯一真源"，于是**多了一条不变量却没有守卫**；
  而 PLAN §9.5 明确把 `etemp` 列为最大单一误差源（拉伸 H₂ −31 %），M4 的 `ts`/`irc` 还要再加入口。
* **最小修复**（二选一，推荐 (a)）：
  (a) 加 1 条 CLI 测试：`--gfn 2 --lvib --etemp 300` vs `--etemp 5000`（对近简并体系，例如拉伸 H₂ 的 xyz 资产），
  断言两次 `eigval :` 行不同（可与 P2-B 的打印一起做，成本最低）；
  (b) 把 `landscape_engine_control%etemp` 默认改成哨兵（如 `-1.0_wp` = "不推入，沿用计算器值"），
  `push_calculator_etemp` 仅在 `> 0` 时赋值 —— 这样忘同步也不会静默改温度。

### P2-B（文书/可见性，非结果错误）：`--lvib` 从不记录/打印实际生效的 `etemp`

* **位置**：报告 `23-m3-fix-report.md` §3.2（"`engine_report` 从计算器读回并打印"）、PLAN §12.11 电子温度段与
  §9.5 第 1 条（"必须在输出/重启文件里记录实际生效值（`engine_report` 已打印）"）；代码：
  `src/landscape/engine/engine.f90:770-802`（有实现）vs 调用点 `tasks/sp.f90:150`、`tasks/opt.f90:142`、
  `tasks/scan.f90:205`（**无 vib**），`src/landscape/vib/numhess.f90:115/150`（engine 局部创建并销毁）。
* **现象**：`xtb h2o.xyz --gfn 2 --lvib --etemp 5000` 的 stdout 里不存在任何生效温度；用户无法从外部确认
  "设置没进去"（这正是 MEDIUM-B 的初衷）。`main_freq`/`print_thermo` 路径也不打印电子温度（`grep etemp src/thermo.f90` 空）。
* **最小修复**：`tasks/vib.f90:110-125` 的 printlevel 块加一行生效值（`settings%engine%etemp`），或在
  `vib/numhess.f90:150` 之前按 printlevel 调一次 `engine%report(env%unit)`；并把报告/PLAN 的措辞限定为
  "sp/opt/scan 由 `engine_report` 打印；vib 打印同值"。

### P2-1（数据完整性/惊喜）：`--lvib-hessian-file hessian` 会把读入的 Hessian 文件原地改写

* **位置**：`src/landscape/tasks/vib.f90:151-160`（`write_files` 为真时写盘）+ `:284`（写名硬编码 `'hessian'`）+
  `types/hessian.f90:771-788`（命名空间一次）+ `types/settings.f90:376-377`（`write_files` 默认 `.true.`，**无 CLI 开关**）。
* **现象**：文档主推的用法（报告 20 §1.4、`xtb/landscape-vib-cli` 的第二次运行）恰好让写目标 == 读来源：
  用户 `--hess` 留下、或手工保留的 `hessian`（或 `<ns>.hessian`）会被套件用**重投影后**的矩阵覆盖
  （`--hess` 的 trproj 矩阵再走 Eckart，差矩阵秩 1、量级见 §5）。非驻点几何上这是 cm^-1 级别的改写。
* **最小修复**：`hessian_source == 'file'` 且写名解析后与读名同一文件时跳过写盘（或至少 `env%warning`），
  或加 `--lvib-no-write` 开关。

### P2-2（文书自相矛盾）："差异全部来自投影" vs "0.0036 是非投影残余"

* **位置**：`docs/xtb-landscape-PLAN.md` §12.11（"两者**都**是数值…**差异全部来自投影**：把同一个原始 Hessian
  分别过两条投影…"）对同段后文"CO2 是线性分子、两条路径都跳过投影，所以 0.0036 cm⁻¹ 是「非投影」残余的上界"。
* **为什么是问题**：CO2 两条路径都**不投影**，其 0.0036 cm⁻¹ 按定义不可能来自投影；报告 23 §0 的处置表又把
  "分档 0.0036–5.2109" 整段归给"投影约定"，与它自己的 §4.1 一致但与 §0 的标题不一致 —— 正是本类复核要找的
  "结论比证据强一格"。
* **最小修复**：把 PLAN 的"差异全部来自投影"改成"差异主要来自投影（极小点 ≈0.072 cm⁻¹），另有一条 ≤0.004 cm⁻¹
  的非投影残余（CO2 实测上界，来源未归因，报告 23 §8.1）"；报告 23 §0 同改。

### P2-3（无数据机制句）：`∝ ‖g‖`

* **位置**：PLAN §12.11（"离驻点越远差异越大（∝ ‖g‖）"）、报告 20 §3.3（"差异随 ‖g‖ 放大"）。
* **证据状态**：报告只给 3 个几何（0.074 / 5.213 / 12.91 cm⁻¹），**没有给对应 ‖g‖**，也没有做比例性检验；
  而"两个投影在不同度量里定义同一刚体运动"本身并不蕴含线性比例（驻点处矩阵不退化，实测 0.074 ≠ 0 即为证）。
* **最小修复**：写成观测（"随偏离驻点程度增大"，附 3 个数据点），或补一条把 ‖g‖ 与 max‖Δf‖ 列出的实测表后再写比例。

### P2-4：LOW-1 修复无测试；LOW-2 的 2 个参数无 CLI 用例

* **位置**：`src/landscape/tasks/vib.f90:215-218`（新告警）—— `grep -r INCOMPLETELY test/` 为空；
  LOW-2 的 `freq_scal`/`rotor_cutoff` 分支（`vib.f90:250-262`）只有 `xhelp/main.F90` 侧注入，无 CLI 用例
  （报告 23 §8.3 已自认）。
* **附带观察**：告警位置在任务**末尾**（文件已写盘之后），而 `--hess` 的同名告警在 FD **之前**
  并配 `env%check(exitRun)`（`src/hessian.F90:161-170`）。退出码语义一致（`--strict` 下都会失败），
  但"先失败再算"与"算完再失败"不同；如需完全对齐可把告警移到 `landscape_vib` 的早期检查处。
* **最小修复**：给 `extra-zero-modes` 之外再加一条用 `h2o_raw`（梯度 > 2e-3）的 CLI 用例断言该行；
  或至少把该告警写进 `xtb/landscape-vib-cli` 的匹配项。

### P2-5（测试偏弱）：namespace CLI 测试的 `eigval` 相等断言可为空匹配

* **位置**：`test/unit/CMakeLists.txt:663-683`（同名 python 版 `test/unit/landscape_cli_check.py:264-281`）。
* **现象**：`string(REGEX MATCH ...)` 匹配失败时 `CMAKE_MATCH_1` 为空 ⇒ `vib_freqs`/`file_freqs` 都是 `""`
  ⇒ `STREQUAL` 通过。主断言（`ns.hessian` 存在、`ns.ns.hessian` 不存在、第二次 exit 0）仍然有效，所以风险有限。
* **最小修复**：匹配后加 `if(NOT vib_freqs) message(FATAL_ERROR ...)`（python 版已有 `if not match` 的等价缺口）。

### INFO

* **INFO-1**：`modes.f90:187/212` 的互补判据在 `freq_cm` 含 NaN 时会不一致（不变量检查抓不到重复下标）。
  当前不可达（`file` 拒绝非有限、数值 provider 失败即返回），建议注释或改成显式检查 `order` 为置换。
* **INFO-2**：extras 保留带符号噪声 ⇒ 用户把 `--lvib-imag-cutoff` 设成极小负值时噪声负模会计入 `n_imag`
  （`modes.f90:248`）。既有语义，仅记录；M4 判定虚频**不要**只看 `n_imag`（默认 cutoff −20 cm⁻¹ 会漏掉
  |λ|<20 cm⁻¹ 的鞍点）。
* **INFO-3**：`extra-zero-modes` 的紧阈值（1e-6 cm⁻¹ ⇒ |λ|<2.1e-23 a.u.）只有靠该合成几何的精确对称性
  （原子 1/2 的 z 分量逐位相等 ⇒ 投影后矩阵精确解耦）才满足；报告记录的"通过"与该论证一致。
  建议在测试注释里写明这条依赖，避免将来改几何后出现"神秘的 red"。
* **INFO-4**：`extra-zero-modes:547` 的 `maxval(abs(vib%freq(1:6))) == 0.0` 由 `modes.f90:235` 构造保证，恒真。
* **INFO-5**：`landscape_engine_control%etemp` 默认 300 K 会让"用 `set%etemp=5000` 造出计算器、再走 landscape API
  且不设 engine 字段"的调用者被改回 300 K。与既有 `acc` 同一设计（引擎控制是唯一真源），CLI 已同步；
  如接受 P1-1 的方案 (b) 则此隐患一并消除。
* **INFO-6**：第 22 号 LOW-3.4（`git add`）**仍未关闭**：`src/landscape/vib/{modes,numhess,thermo}.f90`、
  `src/landscape/tasks/vib.f90`、`test/unit/test_landscape_vib.f90` 仍 untracked（`watchdog_diff` 确认）。

## 8. 需运行验证（复核者无 shell）

| # | 命令 | 期望/用途 |
|---|---|---|
| R1 | `OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-land/build -R landscape`；`-R 'Singlepoint\|GFN\|model-hessian\|optimizer\|Argparser\|CAPI'`；`ctest -N -R landscape`；`grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt \| sort \| uniq -d` | 35/35、12/12、35、空。**重名已由我手工核对**（24 个 `xtb/landscape-*` CLI 名与 11 个单元套件名无交集），grep 仅作机器确认 |
| R2 | Debug/`-fcheck=all` 构建后跑 `xtb-tester landscape-vib`（尤其 `extra-zero-modes`） | 确认 HIGH-1 修复后无未初始化/越界诊断（旧码 SIGSEGV，报告 23 §1.3） |
| R3 | `xtb <近简并体系> --gfn 2 --lvib --etemp 300` vs `--etemp 5000`，比较 `eigval :` 行 | 关闭 **P1-1**（同时暴露 **P2-B**：目前无任何生效值输出可比对） |
| R4 | `xtb h2o.xyz --gfn 2 --lvib --lvib-hessian file --lvib-hessian-file hessian` 两次，比较两次前后 `hessian` 的校验和/时间戳 | 证实 **P2-1**（输入文件被改写） |
| R5 | `xtb <h2o_raw> --gfn 2 --lvib`（梯度 > 2e-3）| 确认 LOW-1 告警行存在（报告 23 §7 的手工 grep），并作为 P2-4 的测试素材 |

## 9. 无 CRITICAL：本轮检查过的攻击面

1. HIGH-1 两条排序分支的赋值完备性 + 不变量可达性 + NaN 情形（§2.1/§2.2）；
2. 近零模分类的物理语义与 `src/hessian.F90:437-447` 的对照（§2.3）；
3. `vib%n_imag`/`imag_cutoff`/`n_vib` 计数契约（`modes.f90:242-248`）；
4. `check_thermo_settings` 的 4 个参数、`temperature(50)` 数组边界（`ntemp = max(1,min(...))` 不会越界）、
   与 `landscape_vib_set_thermo_settings`（`thermo.f90:164-169`）的钳制一致；
5. `push_calculator_etemp` 的作用域（深拷贝副本，无全局污染）、非 TxTB 计算器的 no-op、
   `cache_etemp` 缓存键（`engine.f90:501,575`）语义（现在真正有效，不再伪失效）；
6. `--namespace` 的所有写/读路径（§3）；
7. `vec_norm`（L2，`coords.f90:112-118`）与 `--hess` 的 `norm2(res%grad)` 一致性 ⇒ LOW-1 阈值等价；
8. `diagHessian`（`src/freq/utils.f90:59-88`）的 `syev('v','u')` 输出约定、升序、sign-sqrt、失败路径；
9. `file` provider 与 M2 `--lscan-hessian-file` 的共享面（修复轮只改 `types/hessian.f90` 注释）；
10. 测试注册三处（`test/unit/CMakeLists.txt`、`meson.build`、`test/unit/main.f90`）与重名；
11. M0/M1/M2 回归面：`engine_set_calculator` 新增 push 对 CLI 路径是 no-op（`newXTBCalculator` 已从
    `set%etemp` 拷贝，`src/xtb/calculator.f90:144`），scan/opt 的 `xtbscan.log`/`xtbopt.xyz` 写路径未动；
12. `--lvib` 的 `res` 回写与 `write_files` 语义、`--lvib-hessian-file hessian` 的读写同名问题（P2-1）。

**未发现 CRITICAL 的原因**：修复轮触及的四条代码路径（排序内核、命名空间、etemp 推入、文档）逐一核到"契约 ⇔ 实现"
一致，且新测试对三条都具备可证伪性；剩余问题全部是**可验证性/可见性/文书**层面，不改动任何数值结果。

## 10. 给父会话的处置顺序

1. **P1-1**：加一条 `--etemp` + `--lvib` 的 CLI 断言（与 P2-B 的一行打印一起做最省事），或把 `etemp` 默认值换成哨兵。
2. **P2-B**：在 `tasks/vib.f90` 的 printlevel 块打印生效 etemp；修正报告 23 §3.2 与 PLAN §12.11/§9.5 的措辞。
3. **P2-2/P2-3**：改 PLAN §12.11 与报告 20 §3.3 / 报告 23 §0 的两处过头措辞。
4. **P2-1 / P2-4 / P2-5**：各自为 1–8 行的小修（跳写同名文件 / 补告警与校验测试 / 加空匹配守卫）。
5. **INFO-6**：提交前 `git add` 5 个 untracked 交付文件（LOW-3.4 仍未关闭）。
6. 把 R1–R5 的期望值写进 `24-m3-review-round2.md` 并更新 AGENTS §2 的"修复轮复核"状态。

---