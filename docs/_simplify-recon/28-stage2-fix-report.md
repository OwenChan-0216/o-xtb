# 28 — 阶段 2 修复报告（复核 27 的 M1/M2/L1..L5/INFO-1 处置 + T1..T10 任务书）

**范围**：阶段 2（`--method` 统一选择器）的复审修复轮。任务书 = 父会话的本轮 10 条（T1..T10）。
**基座**：`HEAD = f5b070f`（阶段 1 已提交）+ 阶段 2 未提交工作区。**构建**：`/tmp/xtb-p2/build`（`-O2 -DNDEBUG`，
`WITH_TBLITE=OFF WITH_CPCMX=OFF WITH_TESTS=ON`；`include/xtb_version.fh` 实测与 `f5b070f` 的
`head-build` **逐字相同**：`6.7.1 (f5b070f73948f337775824ac8b83fe893b03441e)`）⇒ BC-4 无需归一化。
**纪律**：未提交 git；未动核心层（`src/type|xtb|mctc|param|io|disp|coulomb`）；未引入阶段 3 内容
（`--opt`/`--ohess` 分派未动、无 §3.8 守卫、无 §3.9 文件、无 §3.10 档位）；未改任何现有旗标名；
`OMP_NUM_THREADS=1`；未跑全量 ctest。

---

## 0. 交付摘要

| 项 | 结果 |
|---|---|
| T1 测试框架对非 UTF-8 字节鲁棒 | **已修**：`decode()`（`errors='replace'`），**5 个「跑 xtb」的调用点**全部改（4 个在 `landscape_cli_check.py`、1 个在 `landscape_e2e_check.py`）；断言未改 |
| T2 既有缺陷定位 | **定位到 `file:line`**：`src/relaxation_engine.f90:615` 与 `:779` 的内禀整体赋值；**未修**（非一行 FORM 笔误；修它会改变原生结果） |
| T3 18 个套件方法名逐名覆盖 | **已修**：新增 `xtb/landscape-method-table`（18 名 + 4 个 `auto`）；反向突变一次打红 **38 行**（18 名逐个点名） |
| T4 设计文档登记 + 自相矛盾 | **已修**：R40（§6.3 → 阶段 2b；§6.4 的 `--cycles` → 阶段 3） |
| T5 别名在重复旗标下不等价 | **已修**：climbing 副作用移到解析尾、对**最终值**施加一次；`--lts-method cineb --lts-method neb` ≡ `--method cineb --method neb` |
| T6 引证不准确 | **已修**：`main.F90` 注释 + `25-stage2-impl.md §1` 订正并留痕（旧引证 `set_module.f90:1889` 作废） |
| T7 `landscape_native_engine` 只写不读 | **已登记**（`§9.2`、`§4.7.1`、测试 docstring）：可测/不可测边界写清；**订正复核 INFO-1 的一半**（见 §7） |
| T8 scan 内层方法不可观测 | **已修**：`--lscan`（relaxed）回显 `inner minimiser:`；并断言两个内层器**必须**改变 `xtbscan.log`；rigid 不回显 |
| T9 BC-4 补 4 个旧旗标基线 | **已做**：5 条命令 × 2 二进制，**全部输出文件 raw `cmp` 逐位同**（唯一 stdout 新增行 = T8 的回显） |
| T10 U15 `[WARNING]` | **已实现**：`src/set_module.f90` 的 `.not.allocated` **else 分支**（= R34 指定实现点）；5 个用例（含一致/不给/只给 xcontrol/给两次） |
| `ctest -R landscape` | **121/121**（阶段 2 为 120，+1 个新 target） |
| 回归子集 `Singlepoint\|GFN\|model-hessian\|optimizer\|Argparser\|CAPI` | **12/12** |
| ctest 重名 / meson 重名 | `uniq -d` 均为**空** |
| 集合 S（`--l*` + `--method`）差集 | **0**（`python3 test/unit/landscape_help_check.py …` → `PASS: set S is documented by --help in both dialects`） |
| 反向突变 | **5 组**（T3 一次含 18 名、T5/T8 两项、T10）；全部红 → 还原 → 绿（`sha256sum -c` 通过） |
| `xtb/landscape-method-native` 稳定性 | **p2 上 5/5 连续通过**（2.77/2.67/2.69/2.68/2.71 s）+ 冻结二进制上 3×7 次运行无解码错误 |

改动文件（`git diff --stat -- src test`，**相对 `f5b070f` 的累计值**；括注为本轮新增的部分）：

```
 src/landscape/tasks/scan.f90     |  15 +-   # 全部为本轮（T8 回显）
 src/landscape/types/settings.f90 |  24 ++   # 阶段 2 原始（4 个 *_source 字段），本轮 0 改动
 src/prog/main.F90                | 465 +-   # 阶段 2 原始 + 本轮（T5 副作用位置、T6 注释、T3 表新增的 --method 部分）
 src/set_module.f90               |  23 ++   # 全部为本轮（T10 U15）
 src/xhelp.f90                    |  14 +    # 阶段 2 原始
 test/unit/CMakeLists.txt         |  60 ++   # 阶段 2 原始 + 本轮（新 target 注册）
 test/unit/landscape_cli_check.py | 761 +-   # 阶段 2 原始 + 本轮（T1 decode / T3 表 / T5·T8·T10 用例）
 test/unit/landscape_e2e_check.py |   5 +    # 全部为本轮（T1 同族修复）
 test/unit/meson.build            |  41 ++   # 阶段 2 原始 + 本轮（meson 同步）
```

本轮改动的文档：`docs/_simplify-recon/11-cli-redesign.md`（R40/R41 + §6.3/§6.4/§9.1/§9.2/§4.7.1）、
`docs/_simplify-recon/25-stage2-impl.md`（T6 订正 + 留痕）、本报告。

---

## T1（必修）测试框架对字节噪声鲁棒

### 1.1 修复前后的真实输出

**修复前**（`cd $REPO && OMP_NUM_THREADS=1 XTBPATH=$PWD ctest --test-dir /tmp/xtb-land/build -R xtb/landscape-method-native`）：

```
    File ".../test/unit/landscape_cli_check.py", line 2245, in invoke
      proc = subprocess.run(
          [exe, input_file] + args, cwd=workdir, capture_output=True, text=True
      )
    File ".../subprocess.py", line 2194, in _communicate
      stdout = self._translate_newlines(stdout, self.stdout.encoding, self.stdout.errors)
  UnicodeDecodeError: 'utf-8' codec can't decode byte 0xa4 in position 15840: invalid start byte
0% tests passed, 1 tests failed out of 1
```

同族独立复现（把 `check_method_native` 的 7 个原生名按测试的调用序列**严格解码**跑一遍）：

```
ok ancopt        ok rf
UnicodeDecodeError: 'utf-8' codec can't decode byte 0xdb in position 15785: invalid continuation byte
（第三次调用 `--method lancopt` 崩在解码上，**断言一个都没跑到**）
```

**修复后**（同一命令，`p2` 构建，连续 5 次）：

```
1/1 Test #188: xtb/landscape-method-native ......   Passed    2.77 sec
1/1 Test #188: xtb/landscape-method-native ......   Passed    2.67 sec
1/1 Test #188: xtb/landscape-method-native ......   Passed    2.69 sec
1/1 Test #188: xtb/landscape-method-native ......   Passed    2.68 sec
1/1 Test #188: xtb/landscape-method-native ......   Passed    2.71 sec
100% tests passed, 0 tests failed out of 1     (× 5)
```

**冻结二进制（`/tmp/xtb-land/build`，未重建）上的稳定性证据**：用修好的解码逻辑把 7 个原生名各跑一遍，
重复 3 轮，每轮 7/7 断言通过（`exit 0` + 唯一 token + 无 `landscape: `）：

```
repeat 1: 7/7 native names asserted OK (no UnicodeDecodeError)
repeat 2: 7/7 native names asserted OK (no UnicodeDecodeError)
repeat 3: 7/7 native names asserted OK (no UnicodeDecodeError)
```

> 注：`/tmp/xtb-land/build` 的**二进制**是修复轮之前的源码状态，而测试脚本是共享的（`-DSCRIPT=源码路径`），
> 所以它现在只因**新加的 U15 断言**而红（`FAIL: u15-conflict: expected a warning for the ignored $opt engine`），
> 与解码无关 —— 这本身就是 T1 修好的证据（测试已能走到语义断言）。该目录按纪律未重建。

### 1.2 修复内容（断言不变）

**反向突变（T1 自己的红→绿）**：把 `decode` 改回严格解码（= 修复前的行为），**不重建**（只改 Python）：

```
$ python3 - <<'PY'   # decode(): errors="replace" → 无 errors（严格）
$ ctest --test-dir /tmp/xtb-p2/build -R xtb/landscape-method-native --output-on-failure
1/1 Test #188: xtb/landscape-method-native ......***Failed    2.67 sec
  UnicodeDecodeError: 'utf-8' codec can't decode byte 0x98 in position 16046:
0% tests passed, 1 tests failed out of 1
$ 还原（cp 备份）→ 连续 3 次：Passed 2.77 / 2.76 / 2.65 sec
```

（非法字节的位置/内容每次都不同：15840 → 15785 → 16046，与 T2 的未初始化内存结论一致。）

```python
def decode(raw):
    """Decode captured output without ever raising. … errors='replace'"""
    if isinstance(raw, str):
        return raw
    return raw.decode("utf-8", errors="replace")
```

* `run()`（全脚本共用的 xtb 调用）与两个任务级 `invoke()` 改为 `text=False` + `decode()`；
* 断言全部保持原样（都是可打印 token 匹配，`errors='replace'` 只在**非** token 区域插入 U+FFFD）；
* `fail()` 打印 `output` 会把替换字符打出来 —— 不影响判定（16 进制层证据见 T2）。

### 1.3 全文件排查（`text=True` / `capture_output` 调用点）

| 文件:行 | 调用的程序 | 已改？ | 理由 |
|---|---|---|---|
| `test/unit/landscape_cli_check.py:91`（`run()`，被 22 处复用） | **xtb** | **是** | 就是崩溃点所在路径 |
| `test/unit/landscape_cli_check.py:1996`（`check_method.invoke`） | **xtb** | **是** | 同族 |
| `test/unit/landscape_cli_check.py:2313`（`check_method_native.invoke`） | **xtb** | **是** | 崩溃点的直接调用点 |
| `test/unit/landscape_cli_check.py:2495`（`check_method_table.invoke`，本轮新增） | **xtb** | 新增即 `text=False` | — |
| `test/unit/landscape_e2e_check.py:151`（`run_xtb`） | **xtb** | **是**（`text=True, errors="replace"`） | 同一个被测程序，同族风险 |
| `test/unit/landscape_e2e_check.py:735/741` | `landscape_tester`（单元测试二进制） | 否 | 输出全部由 Python/Fortran 单元测试**自己**打印，不是 xtb 的格式化 dump；实测 4 个 suite 无非法字节 |
| `test/unit/landscape_e2e_check.py:1020/1022/1026` | `python3 -c` | 否 | 纯 Python 解释器输出 |
| `test/unit/landscape_help_check.py` | 无 subprocess 调用 | — | 只读源码 |

全仓 `grep -rn "text=True" test/` 现在只剩 `landscape_e2e_check.py:155`（已带 `errors="replace"` 的那一处）。

---

## T2（必修）定位并记录既有缺陷（**未修**）

### 2.1 根因（file:line，已用注入实验收口，不是静态推断）

**位置**：`src/relaxation_engine.f90` 的 `l_ancopt`（L-ANCopt，即 `--method lancopt` / 旧 `$opt engine=lbfgs`）：

```
:615    molopt = mol          ! 内禀整体赋值（TMolecule = TMolecule）
:779    mol = molopt          ! 回写：坏掉的 sym(2:) 因此进入调用者的 mol
```

`TMolecule` 的分量 `sym` 是**延迟长度**字符数组（`src/type/molecule.f90:77`），
`allocate_molecule` 把它分到 **len=80**（`:474`）。gfortran 12.2.0 对这种类型做**内禀整体赋值**时，
**第 1 个元素正确、第 2 个起内容被破坏，长度保持 80** —— 这正是本项目已经在
`docs/_landscape-recon/10-m0-m1-fix-round-report.md §4.1` 记录过的**编译器缺陷**（`.trj` 里的 NUL 前缀现象）。

**为什么偏偏 L-ANCopt 中招**：同族的 `ancopt`（rf）用的是 `call molopt%copy(mol)`（`:311`）/
`call mol%copy(molopt)`（`:379`），而 `copyMolecule`（`molecule.f90:199-208`）走 `init(...)` 的
**逐元素**构造 —— 也就是 §4.1 记录的规避手段。所以：

| 命令 | 打印符号 | 非法 UTF-8 |
|---|---|---|
| `--method ancopt` / `rf` | 正确 | 0 |
| `--method lancopt` / `l-ancopt` | **垃圾字节** | 有 |
| 旧写法 `$opt engine=lbfgs`（等价于 lancopt） | **垃圾字节** | 有 |
| `$opt engine=rf`（等价于 ancopt） | 正确 | 0 |

**症状面**（同一份坏掉的 `mol%sym` 被多处打印）：`final structure:`（`geoopt_driver.f90:200` → `writeMolecule`）、
`Multipole` 表（`property.F90:1117` 的 `a4` 字段）、`Wiberg/Mayer` 表（`property.F90:918/921/929`）、
以及写进 `xtbopt.xyz` 的符号列 —— 坐标列**始终正确**。

### 2.2 判别实验：把 `molopt = mol` 换成 `copy`（红 → 绿 → 红）

临时把两行替换成同族已用的规避写法，构建到 `/tmp/xtb-t2build`（**p2 构建目录的副本**，未碰禁改目录）：

```
$ sed -i …           # :615 molopt = mol → call molopt%copy(mol) ; :779 mol = molopt → call mol%copy(molopt)
$ xtb h2o.xyz --gfn 2 --opt --method lancopt --norestart
final structure:
O            0.01022976220748 …            ← O 正确
H           -0.01312453219926 …            ← H 正确（原来是 \x00\x00\x00\x00 / \x14\x1e@\xe7）
H            0.93289476125787 …            ← H 正确
$ xtbopt.xyz 同样干净
```

还原后（`sha256sum` 与注入前逐字节相同）重建，同一命令再跑：

```
$ xtb … --method lancopt
final structure:
O            0.01022976220748 …
\x00\x00\x00\x00        -0.01312453219926 …     ← 垃圾字节回来了（且恰好是合法 UTF-8 ⇒ 静默损坏）
```

⇒ **两行即根因**；“换 copy 就好”证明是**编译器代码生成**问题，不是数据流问题。

### 2.3 最小复现（**不依赖 xtb**，`/tmp/t2probe/repro.f90`）

```fortran
program repro
   implicit none
   type :: moltype
      character(len=:), allocatable :: sym(:)
      integer, allocatable :: at(:)
      real :: xyz(3,3)
   end type moltype
   type(moltype) :: a, b
   integer :: i
   allocate(character(len=80) :: a%sym(3))
   allocate(a%at(3))
   a%sym(1) = 'O'; a%sym(2) = 'H'; a%sym(3) = 'H'
   a%at = [8,1,1]; a%xyz = 0.0
   b = a
   do i = 1, 3
      print '(i2,1x,a4,1x,i0)', i, b%sym(i), len(b%sym(i))
   end do
end program repro
```

```
$ gfortran --version | head -1
GNU Fortran (Debian 12.2.0-14+deb12u1) 12.2.0
$ for opt in -O0 -O1 -O2 -O3; do gfortran $opt -o repro_$opt repro.f90; ./repro_$opt; done
=== -O0 ===            === -O1 ===            === -O2 ===            === -O3 ===
 1 O    80              1 O    80              1 O    80              1 O    80
 2      80              2      80              2      80              2      80
 3 ��_� 80              3 ��b� 80              3 ��^_ 80              3 �:�1 80
```

**在 -O0/-O1/-O2/-O3 全部复现** ⇒ 与优化级别无关（不是本项目 §6 记录的 `-O3` 那个问题），
且 `len` 全程 80（= §4.1 的“步长错误”特征）。这也把 §4.1 里**一直欠着的最小复现**补上了。

### 2.4 为什么**不修**

* 它**不是**一行的 FORM/格式笔误（`property.F90:1113`/`917` 的 `a4` 与 `write` 数据项一一对应，已逐字核对）；
  坏的是**数据**（`mol%sym`），不是格式。
* 修法（`molopt = mol` → `call molopt%copy(mol)`）会**改变原生 L-ANCopt 的 stdout 与 `xtbopt.xyz` 字节**
  ——那正是 BC-4 要守的东西，且属于“为了让它消失而改上游行为”。本轮纪律要求不修。
* 触发条件与本次 `--method` 改动**无关**：`f5b070f` 的二进制（`/tmp/xtb-p2v/head-build/xtb`）在
  `$opt engine=lbfgs` 下同样损坏（`xtbopt.xyz` 第 4/5 行 `\x00\x00\x00\x00`），且那一次**没有** `--method`。

### 2.5 可复现记录（建议后续单独处理）

```bash
# 复现（水，GFN2，L-ANCopt 路径）
cd /tmp && mkdir t2 && cd t2
printf '3\nwater\nO 0 0 0\nH 0 0 0.96\nH 0.93 0 -0.24\n' > w.xyz
OMP_NUM_THREADS=1 XTBPATH=$REPO /tmp/xtb-p2/build/xtb w.xyz --gfn 2 --opt --method lancopt --norestart > out.txt
python3 -c 'raw=open("out.txt","rb").read(); raw.decode("utf-8")'   # UnicodeDecodeError（非确定性字节）
head -5 xtbopt.xyz                                                  # 符号列垃圾/`\x00\x00\x00\x00`（坐标正确）
```

* **字节数在多次运行间变化**（父会话 501 原子 GFN-FF：192 / 1 / 8；本轮水：首次非法字节落在 15785/15840/21672，
  内容 `\x00\x00\x00\x00` / `\xcd\x1c\xef\xbb` / `' 3\x00\x00'` / `\x14\x1e@\xe7` 各不相同）⇒ 未初始化内存/
  错误步长的典型特征；**有时全是 NUL（合法 UTF-8）⇒ 静默损坏，连严格解码都抓不到**。
* **上报对象是 gfortran/GCC Bugzilla**（环境 `GNU Fortran (Debian 12.2.0-14+deb12u1) 12.2.0`），
  最小复现已给（§2.3）；**不要**把它记成 xtb 上游缺陷，也**不要**再归因 `copyMolecule`。
* 建议后续动作：作为**独立**改动处理（`molopt = mol` → `%copy`），并与 BC-4 基线一起重新验收；
  它会让 L-ANCopt 的 `xtbopt.xyz` 与 stdout **变干净**（字节会变，这是有意的修复）。
* 本轮对它的**唯一**动作：T1 的解码容错 + 本节记录。

---

## T3（必修）18 个套件方法名的逐名“生效”证据

### 3.1 新测试

`xtb/landscape-method-table`（新 target，`test/unit/CMakeLists.txt` + `meson test('landscape method table')`），
模式 `methodtable`。逐名断言（**产物 + stdout 双侧**）：

| 任务 | 名字 | stdout 里程碑 | 产物断言 |
|---|---|---|---|
| opt（6） | `sd` `cg` `lbfgs` `bfgs` `diis` `rfo` | `landscape: <name> minimisation` | `xtbopt.xyz` 写出 + **不给 `--method` 时才有的** `[NOTICE] --lopt-engine default` 必须**消失**（证明该名被当成显式选择） |
| ts 单端（3） | `prfo` `bprfo` `dimer` | `landscape: transition state search (<name>)` | `nm.xtbts.log` 首行 `transition state search: <name>`（`ts.f90:685`，由**解析后的枚举**打印） |
| ts 链（3） | `neb` `cineb` `autoneb` | 同上 | 同上 + climbing 阶段：`cineb`/`autoneb` 必须 `climbing image N ignited at iteration`，`neb` **必须没有** |
| ts 弦（2） | `string` `gsm` | 同上 | 同上 + `climbing image (TS candidate): N`（弦方法的 climbing 阶段措辞不同，实测） |
| irc（4） | `gs` `lqa` `hpc` `eulerpc` | `landscape: intrinsic reaction coordinate (<name>)` | `nm.irc.log` 首行 `intrinsic reaction coordinate: <name>`（`irc.f90:996`） |
| `auto`（4） | `--lopt`/`--lts`（既有）+ `--lscan`/`--lirc`（**本轮补**） | 任务默认里程碑 | `xtbscan.log` / `irc.log` 与不给 `--method` **逐位同** |

失败**收集后一起报**（不是遇错即停）：一次突变能把所有受害名字列出来。
耗时实测 **0.90 s**（**27 次运行**：6 opt + 3 ts 单端 + 3 band + 2 弦 + 1 irc 准备 + 4 irc + 2 scan-auto + 2 irc-auto + 3 scan 内层 + 1 rigid）。

### 3.2 反向突变（T3 的逐名证据）

一次突变把 `landscape_opt_algorithm_from_name`、`landscape_ts_method_from_name`、
`landscape_irc_method_from_name` 三张表**各自整体循环轮换**（错位：`sd→cg→lbfgs→…→sd` 等，均为**derangement**），
重建后跑 `methodtable`：

```
FAIL: 38 of the method names did not reach their task:
  table-opt-sd: the run did not report 'landscape: sd minimisation'
  table-opt-cg: the run did not report 'landscape: cg minimisation'
  table-opt-lbfgs: the run did not report 'landscape: lbfgs minimisation'
  table-opt-bfgs: the run did not report 'landscape: bfgs minimisation'
  table-opt-diis: the run did not report 'landscape: diis minimisation'
  table-opt-rfo: the run did not report 'landscape: rfo minimisation'
  table-ts-prfo: the run did not report 'landscape: transition state search (prfo)'
  table-ts-prfo: nm.xtbts.log does not report 'transition state search: prfo'
  …（bprfo / dimer / neb / cineb / autoneb / string / gsm 各 2~3 行）…
  table-irc-gs: the run did not report 'landscape: intrinsic reaction coordinate (gs)'
  table-irc-gs: nm.irc.log does not report 'intrinsic reaction coordinate: gs'
  …（lqa / hpc / eulerpc）…
  table-scan-inner-lbfgs/-cg/-sd: the task did not echo the effective inner minimiser
```

* **18/18 个套件名逐个点名变红**（+3 行 scan 回显顺带变红 ⇒ 回显读的确实是同一张表）。
* 还原（`cp` 备份 + `sha256sum -c` 通过）→ 重建 → 绿。

### 3.3 覆盖清单（更新后，§9.2 的逐名表）

| 名字 | 阶段 2 覆盖 | 本轮后 | 覆盖方式 |
|---|---|---|---|
| `sd` `cg` `lbfgs` `bfgs` `diis` `rfo` | 2/6（`bfgs` `cg`） | **6/6** | `methodtable` 里程碑 + 产物；`bfgs`/`cg` 另有别名逐位比对 |
| `prfo` `bprfo` `dimer` `neb` `cineb` `autoneb` `string` `gsm` | 2/8（`dimer` `cineb`） | **8/8** | 里程碑 + `nm.xtbts.log` + climbing 阶段 |
| `gs` `hpc` `lqa` `eulerpc` | 1/4（`gs`） | **4/4** | 里程碑 + `nm.irc.log` |
| 原生 7 拼写 | 7/7 | 7/7 | `landscape-method-native`（token 判别） |
| `auto` | 2/4 | **4/4** | `methodtable` 的 `xtbscan.log`/`irc.log` 逐位同 |
| **合计** | 14/29 | **29/29** | 13 个“零覆盖”名全部闭合 |

**如实登记的残余能力边界**：6 个 opt 名的断言里，**里程碑**是分派断言，`xtbopt.xyz` 只证明任务跑了
（该任务没有任何产物携带方法名；`landscape_opt.json` 也不含 `method` 计数器）。
本轮**考虑并否决**了“用轨迹/首步几何做两两可区分”的强化：实测 GFN2 水与拉伸水上
`sd` 与 `cg` 的 3 步轨迹 `xtb.trj` **逐字节相同**（`cg.f90` 的模块注释就写明“无历史时方向 = 最速下降”，
且在 `--lopt-max-steps 1/2/3` 下都相同），所以“6 名两两互异”在该 fixture 上**结构上不成立**；
部分互异（4 类）断言脆弱且不覆盖全部名字 ⇒ 不采用，改为如实登记。

---

## T4（必修）设计文档登记 + 自相矛盾

`docs/_simplify-recon/11-cli-redesign.md`：

1. **新增 R40**（修订记录）：§6.3 的缺口旗标本轮**一个都没落地**；本轮逐条 `grep -c`
   （`grep -c -- "--<flag>'" src/prog/main.F90`）：

   | §6.3 声称的新旗标 | 实测 |
   |---|---|
   | `--lopt-max-steps` | **0**（存在的是 M2 遗留的另一拼写 `--lscan-max-steps`，`main.F90:2596`） |
   | `--lopt-hess-step` / `--lscan-hess-step` / `--lts-hess-step` / `--lirc-hess-step` / `--lvib-hess-step` | **全 0**（只有 `--lirc-step-hess` = 2） |
   | `--lopt-sccacc` / `--lscan-sccacc` | **0**（存在 `--lts/--lirc/--lvib-sccacc`） |
   | `--lopt-restart` / `--lvib-restart` | **0**（存在 `--lscan/--lts/--lirc-restart`） |

   ⇒ **整个 §6.3 新旗标块移到阶段 2b（非破坏收尾，先于阶段 3）**，阶段 2 不再声称包含本项。
   **更深一层的问题也一并登记**：§6.3/§7.2 宣称的“统一规范名”（`--l*-hess-step` / `--l*-sccacc`）
   从未实现 — 部分**能力**早已以**任务限定名**存在（`--lscan/--lts/--lirc-max-steps`、
   `--lts/--lirc/--lvib-sccacc`、`--lscan/--lts/--lirc-restart`、`--lirc-step-hess`），
   而 §9.2 的**强制表**为不存在的旗标列了 4 行、并点名了不存在的测试
   （实测只有 `xtb/landscape-scan-max-steps`）⇒ 这 4 行已标“**未实现（R40）**”。
2. **§6.3 加落地阶段提示块**（逐条列出实测 `grep -c` 值 + 已存在的任务限定名）。
3. **§6.4 的 `--cycles` 行**由“§9.1 阶段 2”改为 **“§9.1 阶段 3”** ⇒ 与 §9.1 的阶段 3 列表
   （`--cycles` 映射 / `--lvib` 下报错）与 §3.10b **一致**（`--cycles` 的桥接只有在 `--opt` 改派后才需要，
   §3.10b 的论证本身就依赖“C 之后”）⇒ **自相矛盾消除**。
4. **§9.1 阶段 2 的验收行**更新为已落地事实（`xtb/landscape-method-table` + R41 的 BC-4 补全），
   并把缺口旗标一条改写为指向 R40。
5. **新增 R41**（本修复轮登记表，覆盖 M1/L1..L5/INFO-1 处置）。

> **发现（供上级评估）**：§9.2 是项目沿用 M6 报告 46 §2.4 的“强制表格”，本应是逐选项的验收契约；
> 实测它有 **4 行 + 3 行别名行指向不存在的旗标**。这超出了 T4 的字面要求
> （只要求登记或移出阶段 2），但登记为上述 R40 的一部分，以免阶段 2b/3 继续“对着不存在的旋钮验收”。

---

## T5（必修）重复旗标下别名不等价

**问题**（复核 27 L3）：climbing 副作用原先写在共享 setter 里（**逐旗标**施加），
而 `--method` 的重复只处理最后一个 ⇒
`--lts-method cineb --lts-method neb` 留 `climb=.true.`，`--method cineb --method neb` 留 `climb=.false.`。

**修法**（最小）：setter 只**存值**；副作用移到 `parseArguments` 末尾（flag 循环之后、`--method` 尾归一之后），
对**最终值**施加一次：

```fortran
      select case (ltset%method)
      case (p_landscape_ts_cineb, p_landscape_ts_autoneb, &
            & p_landscape_ts_string, p_landscape_ts_gsm)
         ltset%path%climb = .true.
      end select
```

* 只**开**不关（与 `--lts-climb` 同语义）⇒ 显式 `--lts-climb` 行为不变；
* `--lts-method cineb` 单独给仍会 ignite（新增的 `table-ts-cineb/-autoneb/-string/-gsm` 断言钉住）；
* **行为变更（有意，已在 R41/§9.2 登记）**：`--lts-method cineb --lts-method neb` 从“cineb+climb”
  变为“neb（无 climb）”，与 `--method cineb --method neb` 一致 —— 这正是任务书要求的“同一 owner 的重复确定性收敛”。

**测试**：`check_method` 新增
`repeat-band-flag` / `repeat-band-method`（断言里程碑 = `(neb)`、**无** climbing、`p2.path.xyz`/`p2.xtbts.xyz` 逐位同）
与 `repeat-band-explicit-climb`（`--lts-climb` 仍然 ignite）。

**反向突变**：把副作用搬回 setter ⇒

```
FAIL: repeat-band-flag: the discarded `cineb` still ignited the climbing image
```

还原 → 绿。

---

## T6（必修）引证订正（留痕）

**不准确之处**：25 号报告 §1 写“别名逐字取自 `set_module.f90:1888-1891`”，并把 `lancopt` 的依据列为 `:1889`。
实测：`:1889` 是 `case('lbfgs','l-ancopt')` —— **没有 `lancopt`**；`$opt engine=lancopt` 实测报
`engine 'lancopt' is not implemented` 且**不设引擎**。数量巧合（7=7），**集合不同**：
去掉 `lbfgs`（R21 有意）、**新增** `lancopt`（R9 的 CLI 专名）。

**订正**：

* `src/prog/main.F90` 的 `landscape_native_engine_from_name` 模块注释重写：写明**两条差异**
  （`lbfgs` 不在表内、`lancopt` 不在 xcontrol 键内），并**留痕**“此前的引证不准确 + 指向本报告 T6”；
* `docs/_simplify-recon/25-stage2-impl.md §1`：表头与 `lancopt` 行订正为 `set_module.f90:1898-1901`，
  并在表后加**引证订正·留痕**块（旧说法、错在哪、订正后的位置）。

---

## T7（必修）`landscape_native_engine` 的作用域登记

**复核 INFO-1 的一半需要订正**（本轮实测）：

* **可测且已证伪**：`main.F90:3977` 的 `set%opt_engine = landscape_native_engine` **确实被读**（被下游 `geoopt_driver` 读）。
  删掉该赋值 ⇒ 501 原子 GFN-FF 上 `--method ancopt` 落回 `defaults.f90:44` 的 `p_engine_lbfgs` ⇒
  stdout 出现 `L-ANC optimizer` 而不是 `ANC micro-cycles` ⇒ `xtb/landscape-method-native` 的 `native-big` 变红
  （25 号报告的注入 M2 已实测；本轮 T3 的突变再次覆盖同一条路径）。
* **确实不可测（阶段 3）**：**阶段 3 的读取点不存在**（`--opt`/`--ohess` 仍走 `if (anyopt)` 原生块）
  ⇒ 任何声称“`--opt` 下引擎被尊重”的运行时测试都是恒真的。§4.7.1 的 `xtb/landscape-lopt-no-method`
  属于这一类（**该 test 在本构建中不存在**：`grep -rn "lopt-no-method" test/unit/` = 0 命中，
  它写在设计里就是预期的“恒真/只能静态核”项；其**声明初值**只能静态核：
  `intent(out)` + 未初始化在 `-O2` 下常“恰好为 0”）。

**登记动作**：`§9.2` 的“标志初值”行改写为两半（a）可测 + 突变 (b) 阶段 3 不可测；
`§4.7.1` 的 `lopt-no-method` 行保留静态核要求；`test/unit/landscape_cli_check.py` 的
`check_method_native` docstring 新增 **“Scope note for `landscape_native_engine`”** 段，
明说“本构建没有阶段 3 的读取点，本文件的测试不声称覆盖它”。

---

## T8（必修）scan 内层方法“存了但没生效”不可发现

**为何原先无法发现**（复核 27 L2 的四条 + 本轮复核）：

1. `rigid` 模式根本不建约束、不用内层最小化器（`relax_scan.f90:501/597` 只在 relaxed 路径）；
2. `--lscan --method X` 与 `--lscan --lscan-method X` 共用同一个 setter ⇒ 别名比对两条路一起错；
3. 里程碑 `landscape: relaxed scan` 与 mode 绑定、**不含方法名**；
4. `xtbscan.log` 的列定义是 M2 的兼容契约，**不含方法名**；
5. 25/26 号的“别名等价”断言（`xtbscan.log` 逐位同）对**两条都错**的情况天然免疫。

**可观测化（已实现，改 stdout 不动文件格式）**：`src/landscape/tasks/scan.f90` 的 banner 在
**relaxed** 模式下多打一行（rigid 不打）：

```
$ xtb w.xyz --gfn 2 --lscan --method cg … 
 landscape: relaxed scan
   inner minimiser:         cg
$ xtb w.xyz --gfn 2 --lscan --lscan-mode rigid …
 landscape: rigid scan                       ← 没有 inner minimiser 行
```

**外加一条真正的“生效”断言**（回显只证明读取，不证明使用）：在拉伸水 fixture 上
`--lscan --method lbfgs` / `cg` / `sd` 的 `xtbscan.log` **必须互不相同**（实测 md5
`469501df…` / `a553742d…` / `76d502b6…`）—— 内层方法若被忽略，三者逐位同 ⇒ 红。

**反向突变（两项）**：

```
FAIL: table-scan-inner-cg: the task did not echo the effective inner minimiser   ← banner 回显写死 'lbfgs'
FAIL: table-scan-inner-sd: the task did not echo the effective inner minimiser
FAIL: table-scan-inner-cg: the inner minimiser did not change xtbscan.log        ← relax_scan 恒用 sd
FAIL: table-scan-inner-sd: the inner minimiser did not change xtbscan.log
```

还原 → 绿。**未改 `xtbscan.log` 的格式**（M2 的兼容契约保持不变），因此不需要“登记为待办”。

---

## T9（必修）BC-4 补 4 个被改写的旧旗标基线

**方法**：`/tmp/t9/bc4-flags.sh`。基线二进制 = `/tmp/xtb-p2v/head-build/xtb`（`f5b070f` worktree，同配置 `-O2`），
新版 = `/tmp/xtb-p2/build/xtb`。两者的 `include/xtb_version.fh` 实测**逐字相同**
（`6.7.1 (f5b070f73948f337775824ac8b83fe893b03441e)`）⇒ 无需对齐。`OMP_NUM_THREADS=1`，
同一工作目录、同一命令行、两个二进制各跑一遍，收集**全部**非输入文件 + stdout + 退出码后 `cmp`。

| 命令 | exit base/new | 输出文件数 | **raw `cmp` 不同/缺失/多余** | stdout 差异行 |
|---|---|---|---|---|
| `--gfn 2 --lopt --lopt-engine bfgs --norestart` | 0 / 0 | 5 | **0** | 30 |
| `--gfn 2 --lscan --lscan-method cg --lscan-coord distance --lscan-atoms 1,2 --lscan-step 0.05 --lscan-nstep 2 --lscan-oneway` | 0 / 0 | 5 | **0** | 39 |
| 同上但 `--lscan-method CG`（**大写**：新 setter 的存储点转小写） | 0 / 0 | 5 | **0** | 31 |
| `--gfn 2 --lts --lts-method dimer --lts-ninit force --norestart` | 0 / 0 | 5 | **0** | 28 |
| `--gfn 2 --lirc --lirc-method gs --lirc-max-steps 2 --norestart` | 0 / 0 | 7 | **0** | 34 |

stdout 逐行判定（脚本 + 分类过滤）：

| 命令 | 差异行 | 时间戳/路径/种子/墙钟 | **其他** |
|---|---|---|---|
| `--lopt-engine bfgs` | 30 | 24（含 `ratio c/w`、`finished run on`） | 0 |
| `--lscan-method cg` | 39 | 28 | **1**：`>    inner minimiser:         cg`（= T8 的**有意**新增行） |
| `--lscan-method CG` | 31 | 24 | **1**：同上 |
| `--lts-method dimer` | 28 | 24 | 0 |
| `--lirc-method gs` | 34 | 28 | 0 |

`* started run on` / `program call`（二进制路径）/ `random seed` / 计时表 / `ratio c/w` / `finished run on`
是同一二进制两次运行也存在的固有噪声（25 号报告 F3 已实测）。

⇒ **本轮唯一真正改动的代码路径（4 个旧旗标）现在有了逐位基线**：
**全部输出文件 raw `cmp` 逐位相同**（含 `xtbopt.xyz`、`xtbscan.log`、`p1.*`/`xtbts.*`、`irc*.log`、`xtb.trj`），
唯一 stdout 新增行是 T8 的回显（已在 R41/§9.2 登记）。`25-stage2-impl.md §4` 的“BC-4 逐位不变”现由本表补全。

---

## T10（父会话裁定）U15 的 `[WARNING]`

**实现点**（= 设计 R34 指定的 `.not.allocated` 守卫 **else 分支**），`src/set_module.f90`：

```fortran
   case('engine')
      …（注释：U15 的意图 + 为什么值必须保留）
      if (.not.allocated(set%opt_engine)) then
         …（原样：未实现警告 + 4 个引擎赋值）
      else
         select case(lowercase(val))
         case('rf','ancopt');      iengine = p_engine_rf
         case('lbfgs','l-ancopt'); iengine = p_engine_lbfgs
         case('pbc_lbfgs');        iengine = p_engine_pbc_lbfgs
         case('inertial','fire');  iengine = p_engine_inertial
         case default;             iengine = 0
         end select
         if (iengine /= 0 .and. iengine /= set%opt_engine) then
            call env%warning("engine '"//trim(val)//"' is ignored: an "//&
               & "optimizer engine was already selected (--method or an "//&
               & "earlier $opt engine=)",source)
         end if
      end if
```

* 除该警告外**行为不变**：`set%opt_engine` 仍保留先到的值（CLI 优先，U15 的语义），未知拼写仍是**静默不设**
  （与原先一致，避免把 `$opt engine=lancopt` 的既有 `not implemented` 变成两条警告）；
* **实测输出形态**（xtb 的 `env%warning` 该有的样子）：

```
########################################################################
[WARNING] Please study the warnings concerning your input carefully
-1- set_opt: engine 'rf' is ignored: an optimizer engine was already selected (--method or an earlier $opt engine=)
########################################################################
```

* **订正 R34 的一句**：R34 说该分支“只可能在 `--method <native>` 之后命中”。实测**还有一种**：
  **同一个 `$opt` 块里重复给 `engine=` 两个不同值**（首个生效、第二个原先静默消失）。
  本轮让它**也**告警 —— 与“绝不静默覆盖”是同一条规则；已在 R41/§4.7.1 登记，并单独用例钉住。

**测试**（`check_method_native` 的 5 个 `u15-*` 用例）：

| 用例 | 命令 | 期望 |
|---|---|---|
| `u15-conflict` | `--opt --method lancopt` + `$opt engine=rf` | 有 `[WARNING]` + `is ignored`；仍 `L-ANC optimizer`（CLI 胜） |
| `u15-agree` | `--opt --method lancopt` + `$opt engine=lbfgs` | **无**警告 |
| `u15-cli-only` | `--opt --method lancopt` | 无警告 |
| `u15-xcontrol-only` | `--opt` + `$opt engine=rf` | 无警告（既有行为逐字不变） |
| `u15-xcontrol-twice` | `--opt` + `$opt engine=rf` 后再 `$opt engine=lbfgs` | 有警告（上述订正的行为） |

**反向突变**：把 else 分支改成 `continue` ⇒ `FAIL: u15-conflict: expected a warning for the ignored $opt engine`。
还原 → 绿。

---

## 11. 验收（本轮全量）

```bash
cd $REPO
cmake --build /tmp/xtb-p2/build --target xtb-exe -j 8        # 0 error
OMP_NUM_THREADS=1 XTBPATH=$PWD ctest --test-dir /tmp/xtb-p2/build -R landscape   # 121/121（38.08 s）
OMP_NUM_THREADS=1 XTBPATH=$PWD ctest --test-dir /tmp/xtb-p2/build \
  -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'                   # 12/12
ctest --test-dir /tmp/xtb-p2/build -N -R landscape | grep "Total Tests"          # 121
grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d           # 空
grep -oE "test\('[^']+'"     test/unit/meson.build   | sort | uniq -d            # 空
python3 test/unit/landscape_help_check.py src/prog/main.F90 src/xhelp.f90        # PASS（S 差集 0）
/tmp/t9/bc4-flags.sh                                                             # 5 命令 × 全部输出文件 raw cmp 0 差异
```

* **新增覆盖体现在 target 数**：120 → **121**（`xtb/landscape-method-table`）；用例数：`methodtable` 27 次运行、
  `landscape-method` +3（重复旗标）、`landscape-method-native` +5（U15）。
* **未执行**：meson 端到端（本机无 meson/ninja，AGENTS §4）—— 已同步注册 `test('landscape method table')`，
  沿用 25/26 号的替代核验（两侧测试名 `uniq -d` = 0、Python 检查器本体直接跑通）。

---

## 12. 覆盖清单（更新后 · 汇总）

| 类别 | 阶段 2 | 本轮后 | 证据 |
|---|---|---|---|
| 18 个套件方法名“生效” | 5/18（另 1 个 `bfgs` 别名） | **18/18** | `xtb/landscape-method-table` + 一次错位突变 38 行逐名变红 |
| `auto`（4 个任务） | 2/4 | **4/4** | 同上（`xtbscan.log`/`irc.log` 逐位同） |
| 原生 7 拼写 | 7/7 | 7/7 | `landscape-method-native` |
| `landscape_native_engine` 写点 | 1（501 原子 fixture） | 1（同）+ **边界登记** | `native-big` + `§9.2`/`§4.7.1` |
| scan 内层方法可观测 | 0 | **3 断言**（回显 / rigid 不回显 / 产物必须不同） | `methodtable` + 2 项突变 |
| 重复旗标等价性（climb） | 0 | **4 断言** | `repeat-band-*` + 1 项突变 |
| U15 冲突告警 | 0 | **5 用例** | `u15-*` + 1 项突变 |
| 4 个旧旗标 BC-4 | 0 | **5 命令 × 全部输出文件逐位** | `/tmp/t9/bc4-flags.sh` |

---

## 13. 残留风险 / 未做

1. **T2 的编译器缺陷仍未修**（有意）：L-ANCopt 的 `xtbopt.xyz`/stdout 符号列在 gfortran 12.2.0 下**会**损坏
   （有时是合法 UTF-8 的 NUL ⇒ 静默）。建议作为独立改动（2 行）+ 重做 BC-4 基线。
2. 6 个 opt 名只有“里程碑 + 产物存在”两级断言（原因见 §3.3：GFN2 水/拉伸水上 `sd`≡`cg`，两两互异不成立）。
3. §6.3 剩余缺口旗标（`--l*-hess-step`/`--l*-sccacc`/`--lopt/lvib-restart`）**仍未实现**，已按 R40 移到阶段 2b。
4. 阶段 3 的 `landscape_native_engine` 读取点尚不存在（T7）；阶段 3 开工时需按 §4.7.1 补运行时断言。
5. meson 端到端仍未执行（环境无 meson/ninja）。
6. `p2-workflow.js` / `p2fix-workflow.js`（仓库根、untracked）**不要** `git add`（复核 27 INFO-6）。

---

## 订正（父会话，依据 29 号复核的 LOW-1/LOW-2）

复核 29 指出本报告两处**表述**与证据不符（无代码缺陷）：

- **LOW-1**：T9 的 stdout 分类数字与「唯一新增行」的说法不成立（实际分类口径与计数见 29 号报告 §T9）。
  以 29 号的核对为准；本报告相应句子**不再作为结论依据**。
- **LOW-2**：§1.3 末句与同节的表格自相矛盾（表格列了 5 处 `text=True`，末句的概括与表不符）。
  以**表格**为准。

两条均为报告文本层，**不影响 T1/T2 的代码结论与 121/121 的验收**。
