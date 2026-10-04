# 上游 `relaxation_engine` 内在派生类型赋值缺陷修复（独立 bug 修复）

- **HEAD**：`0406baf`（阶段 2 已提交；本修复**未提交**）
- **构建档位**：`-O2`（`-DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"`）
- **构建目录**：`/tmp/xtb-up/build`（本修复）；基线二进制 `/tmp/xtb-up/base-build/xtb`
  （`git worktree add --detach /tmp/xtb-up/base HEAD`，**同一 commit、同一配置**）
- **所有命令 `OMP_NUM_THREADS=1`**；未跑全量 ctest（只 `-R landscape` / 回归子集 / 单测名）

---

## 0. 结论摘要

| 项 | 结果 |
|---|---|
| 根因 | `src/relaxation_engine.f90` 的 L-ANCopt 引擎用**内在派生类型赋值**拷贝几何（`:615`、`:779`），gfortran 12.2.0 破坏 `TMolecule%sym(2:)`（AGENTS.md §6 第 5 条的同一编译器缺陷） |
| 修法 | **2 行**：`molopt = mol` → `call molopt%copy(mol)`；`mol = molopt` → `call mol%copy(molopt)`（与 `rf`/FIRE 路径 `:311`/`:379` 完全同写法、同签名） |
| 影响面 | 本机编译器下**原生 `--opt` 的 L-BFGS 路径**（`$opt engine=lbfgs`，或 **n>500 原子的默认引擎** `src/main/defaults.f90:42-46`）；`rf`/FIRE 路径本来就干净 |
| 现象 | `xtbopt.xyz` / `xtbopt.log` / `xtbtopo.mol` 的**符号列**与 stdout 的 `final structure:` / 键表**写垃圾字节**；**数值全对** |
| 修复效果 | 符号列 垃圾 → 正确；**数值逐位不变**（§4） |
| 防回归 | 新增 `xtb/native-opt-lbfgs-symbols`（CMake + meson 双注册），**字节级**断言；注入还原两行 ⇒ **红**，还原 ⇒ **绿**（§3） |
| BC-4 | 10 个用例中 **9 个逐文件 `cmp` 全同**（含 `--sp`/`--hess`/`--ohess`/`--md`/原生 `--opt`/4 个旧旗标）；**唯一有意改变的是 `optlbfgs`**（§2） |
| 计数口径 | **不属于** 18 条 CLI 破坏性变更（§5） |
| 被证伪的前提 | 3 条，见 §6 |

---

## 1. 逐行 diff

```
$ git diff src/relaxation_engine.f90
diff --git a/src/relaxation_engine.f90 b/src/relaxation_engine.f90
index 1ac2111..22f5618 100644
--- a/src/relaxation_engine.f90
+++ b/src/relaxation_engine.f90
@@ -612,7 +612,9 @@ subroutine l_ancopt &
 
    estart = energy
    thiscycle = opt%micro_cycle
-   molopt = mol
+   ! explicit copy: intrinsic assignment of a TMolecule corrupts sym(2:) with
+   ! gfortran (stride bug, see AGENTS.md section 6)
+   call molopt%copy(mol)
 
    if (.not.pr.and.minpr) write(env%unit,'(a6,a14,a16,a16,a15,a6)') &
       &          "cycle", "energy", "change", "gnorm", "step", "conv?"
@@ -775,8 +777,8 @@ subroutine l_ancopt &
       endif
    endif
 
-   ! save optimized geometry
-   mol = molopt
+   ! save optimized geometry (explicit copy, see the note above)
+   call mol%copy(molopt)
 
    if (present(iter_needed)) then
       iter_needed = iter
```

**签名/语义核对（不是推断，逐行读过）**：`src/type/molecule.f90:167`
`procedure :: copy => copyMolecule`；`:199-208`

```fortran
subroutine copyMolecule(self,mol0)
   class(TMolecule), intent(out) :: self
   type(TMolecule), intent(in) :: mol0
   call self%deallocate()
   Call init(self, mol0%at, mol0%sym, mol0%xyz, mol0%chrg, mol0%uhf, &
           & mol0%lattice, mol0%pbc)
   self%ftype = mol0%ftype
end subroutine copyMolecule
```

- `class(TMolecule), intent(out)` ⇒ 对 `type(TMolecule) :: molopt` 与 `type(TMolecule), intent(inout) :: mol`
  都可直接调用，**与 `rf` 路径 `:311`/`:379` 的实参形态完全相同**。
- `self%deallocate()` 内部逐个 `if (allocated(...)) deallocate(...)`（`:485-508`），对
  **未初始化的局部 `molopt`** 安全 —— 这正是 `fire`（`rf`/FIRE 路径）**今天已经在做**的事，
  所以不是新引入的假设。
- `type(TMolecule)` 的 `interface assignment(=)` **只**定义了 `structure_to_molecule` /
  `molecule_to_structure`（`:184-187`、`:409`/`:431`，签名里另一个实参是 `type(structure_type)`），
  **没有** `TMolecule = TMolecule` 的定义赋值 ⇒ `:615`/`:779` 确实是**内在赋值**，会命中该编译器缺陷。

**未改动该文件其它任何一行**（`git diff` 只有上面两处 + 两处注释）。

---

## 2. BC-4：逐文件 `cmp`

脚本 `/tmp/xtb-up/bc4/bc4.sh`（BASE=`/tmp/xtb-up/base-build/xtb`，NEW=`/tmp/xtb-up/build/xtb`，
同一工作目录路径、同一 fixture、stdout 归一化方式沿用 `/tmp/p1-bc4/bc4b.sh`）。
原始输出 `/tmp/xtb-up/bc4/bc4-final.out`。

| # | 用例 | 命令 | 输出文件数 | raw `cmp` 差异 | 归一化 stdout |
|---|---|---|---|---|---|
| 1 | `sp` | `--gfn 2 --sp --norestart` | 3 | **0** | 逐位同 |
| 2 | `hess` | `--gfn 2 --hess --norestart` | 7 | **0** | 逐位同 |
| 3 | `ohess` | `--gfn 2 --ohess --norestart` | 9 | **0** | 逐位同 |
| 4 | `md` | `--gfn 2 --md --norestart --input seed42.in` | 55 | **0** | 逐位同 |
| 5 | `optnative` | `--gfn 2 --opt normal --norestart`（默认引擎 = `rf`） | 5 | **0** | 逐位同 |
| **6** | **`optlbfgs`** | **`--gfn 2 --opt normal --norestart --input lbfgs.inp`（`$opt engine=lbfgs`）** | 5 | **3（有意）** | **14 行（有意）** |
| 7 | `loptengine` | `--gfn 2 --lopt --lopt-engine bfgs --norestart` | 5 | **0** | 逐位同 |
| 8 | `lscanmethod` | `--gfn 2 --lscan --lscan-method cg <scan>` | 5 | **0** | 逐位同 |
| 9 | `ltsmethod` | `--gfn 2 --lts --lts-method dimer --lts-ninit force --norestart`（HCN） | 5 | **0** | 逐位同 |
| 10 | `lircmethod` | `--gfn 2 --lirc --lirc-method gs --lirc-max-steps 2 --norestart`（TS） | 7 | **0** | 逐位同 |

### 「因本修复而变化的文件」= 只有 `optlbfgs` 的三个符号载体

```
### optlbfgs   exit base=0 new=0
   DIFFERS: xtbopt.log
   DIFFERS: xtbopt.xyz
   DIFFERS: xtbtopo.mol
   output files=5 raw-cmp-differing/missing/extra=3
   normalised stdout: DIFFERS (32 bytes, 14 lines)
```

差异**逐行**如下（`cat -v`，反引号 + `^@` = 被破坏的字节）：

```
$ diff <(cat -v optlbfgs-base/xtbopt.xyz) <(cat -v optlbfgs-new/xtbopt.xyz) | cat -v
4,5c4,5
< `^@^@^@        -0.01312453219926        0.00000000000000        0.96657611955003
< 4443         0.93289476125787       -0.00000000670885       -0.25429493238043
---
> H           -0.01312453219926        0.00000000000000        0.96657611955003
> H            0.93289476125787       -0.00000000670885       -0.25429493238043

$ diff <(cat -v optlbfgs-base/xtbtopo.mol) <(cat -v optlbfgs-new/xtbtopo.mol)
6,7c6,7
<    -0.0131    0.0000    0.9666 `^@^@ 0  0  0  0  0  0  0  0  0  0  0  0
<     0.9329   -0.0000   -0.2543 444 0  0  0  0  0  0  0  0  0  0  0  0
---
>    -0.0131    0.0000    0.9666 H   0  0  0  0  0  0  0  0  0  0  0  0
>     0.9329   -0.0000   -0.2543 H   0  0  0  0  0  0  0  0  0  0  0  0
```

`xtbopt.log`（全部轨迹帧）同理，只有符号列。

归一化 stdout 的 14 行差异**全部**是符号 token（`final structure:` 块 2 行、H 原子键表 2 行、
WBO 表 3 行），**没有任何数字变化**：

```
$ diff ob.norm on.norm | grep -a '^[<>]' | cat -v
< `^@^@^@        -0.01312453219926        0.00000000000000        0.96657611955003
< 4443         0.93289476125787       -0.00000000670885       -0.25429493238043
> H           -0.01312453219926        0.00000000000000        0.96657611955003
> H            0.93289476125787       -0.00000000670885       -0.25429493238043
<      2   1 `^@^@^@     0.805     0.282     0.776     1.384
<      3   1 4443     0.805     0.282     0.776     1.384
>      2   1 H        0.805     0.282     0.776     1.384
>      3   1 H        0.805     0.282     0.776     1.384
<      1   8 O    1.840 --     3 4443 0.920     2 `^@^@^@ 0.920
...
>      1   8 O    1.840 --     3 H    0.920     2 H    0.920
```

### 「应当逐位不变」= 其它 9 个用例 + 第 10 个用例的其余文件

- 9 个用例的**全部**输出文件（共 3+7+9+55+5+5+5+7 = 除 `optlbfgs` 的 96 个文件，含 `md` 的 55 个
  `xtb.trj`/`xtbrestart` 等）raw `cmp` **0 差异**；
- `optlbfgs` 的其余 2 个文件（`charges`、`wbo`）raw `cmp` **也相同**；
- 全部 10 个用例的归一化 stdout 除 `optlbfgs` 外逐位同；
- `xtbtopo.mol` 的时间戳行（MDL 日期行，分钟分辨率 `:2` 行）**额外**掩码后重比：
  **只有 `optlbfgs` 仍不同**，其余 9 个 SHA 相同（防"跨分钟导致假差异"的保底）。

---

## 3. 新测试：严格字节断言 + 注入红/还原绿

### 3.1 断言内容（`test/unit/landscape_cli_check.py:2462` `check_native_opt_symbols`，mode `nativeoptsym`）

在临时目录跑
`xtb <h2o.xyz> --gfn 2 --opt normal --input engine.ctl --norestart`（`engine.ctl` 内容 `$opt engine=lbfgs`），
然后：

1. 断言 stdout 命中 `L-ANC optimizer`（确实走到了 L-BFGS 引擎，不是"没跑到"就绿）；
2. 对 **stdout(`stdout+stderr` 原始字节)** 与 **`xtbopt.xyz` 原始字节** 各做：
   - `raw.decode("utf-8")`（**严格**模式）必须成功；
   - **显式扫描控制字节**：任何 `b < 0x20` 且不是 `\t`/`\n`/`\r` 的字节 ⇒ 失败并打印偏移；
3. **符号列比对**：从输入 fixture 读出原子数与符号序列（`O,H,H`），与
   `xtbopt.xyz` 的符号列**逐原子**相等 ⇒ 否则失败并打印 `written/expected`；
4. stdout 的 `final structure:` 块里 n 行原子行的符号列同样必须等于输入序列。

**为什么不能只用 `decode("utf-8")`**：`b"\x00".decode("utf-8")` **成功**（NUL 是合法码点 U+0000）——
本任务最初建议的"严格解码"断言在这个缺陷上**会漏**。实测证据：
第一次复现的 `--opt --input lbfgs.inp` 输出里 stdout 的 32 个坏字节**全是 NUL**，
`raw.decode("utf-8")` **严格模式成功**：

```
$ python3 -c 'raw=open("stdout.txt","rb").read(); print(raw.count(b"\x00")); raw.decode("utf-8")'
32
strict decode of the BUGGY stdout: OK (a NUL byte is valid UTF-8)
```

同理，一次注入运行里 `xtbopt.xyz` 严格解码也成功而符号列已坏：

```
$ python3 ...（注入后的 xtbopt.xyz）
nul count: 2
strict decode: OK
symbol column: ['O', '3\x00\x00', '\x17hڤ']    expected ['O','H','H']
symbol guard red: True
```

⇒ 所以「控制字节扫描」+「符号列比对」这两条**才是**能真正证伪的断言，二者都保留。

**并且断言不依赖垃圾字节的具体取值**：实测同一二进制多次运行的坏字节**不同**
（NUL、`0xcd`、`0xec`、`0xac`、甚至数字 `"4443"`）——它来自相邻内存。
测试因此只与**期望符号**比较，不断言字面垃圾，也不会因此变脆。

### 3.2 注入证据（真实输出）

**注入**：把两行改回内在赋值（`python` 文本替换，`git diff --stat` 此时为空 =
**与 `HEAD` 逐字节相同**）：

```
$ git diff --stat
(none)
$ cmp src/relaxation_engine.f90 <(git show HEAD:src/relaxation_engine.f90) && echo "IDENTICAL TO HEAD"
IDENTICAL TO HEAD
$ cmake --build /tmp/xtb-up/build -j --target xtb-exe   # build=0
$ OMP_NUM_THREADS=1 ctest -R 'native-opt-lbfgs-symbols' --output-on-failure
Test project /tmp/xtb-up/build
    Start 201: xtb/native-opt-lbfgs-symbols
1/1 Test #201: xtb/native-opt-lbfgs-symbols .....***Failed    0.06 sec
CMake Error at landscape_cli_py.cmake:10 (message):
  landscape_cli_check.py failed with status 1

  FAIL: stdout is not valid UTF-8: 'utf-8' codec can't decode byte 0xcd in
  position 15988: invalid continuation byte
...
0% tests passed, 1 tests failed out of 1
```

（第 2 次注入运行时同一个断言报的是 `0xec`、`0xac` —— 字节值不确定，见 §3.1，
所以"红"是确定的、"红的字节值"不是。另一次注入运行里 stdout 严格解码成功而
`xtbopt.xyz` 的**符号列**断言单独打红，见上。）

**还原**（`cp /tmp/xtb-up/relaxation_engine.f90.fixed src/relaxation_engine.f90` + 重建）：

```
$ OMP_NUM_THREADS=1 ctest -R 'native-opt-lbfgs-symbols' --output-on-failure
    Start 201: xtb/native-opt-lbfgs-symbols
1/1 Test #201: xtb/native-opt-lbfgs-symbols .....   Passed    0.06 sec
100% tests passed, 0 tests failed out of 1
```

**独立于注入的第二份"改前红"**：同一条检查对 **`/tmp/xtb-up/base-build/xtb`（未打补丁的基线二进制）**
同样红（连续两次运行都红）：

```
$ python3 test/unit/landscape_cli_check.py nativeoptsym /tmp/xtb-up/base-build/xtb ... 
FAIL: stdout is not valid UTF-8: 'utf-8' codec can't decode byte 0xac in position 16019: invalid start byte
run1 exit=1
FAIL: stdout is not valid UTF-8: 'utf-8' codec can't decode byte 0xfc in position 16019: invalid start byte
run2 exit=1
```

### 3.3 注册

| 位置 | 内容 |
|---|---|
| `test/unit/CMakeLists.txt:3549` | `add_test("xtb/native-opt-lbfgs-symbols" ... -DARGS=nativeoptsym;...)` |
| `test/unit/CMakeLists.txt:3594` | 加入 `set_tests_properties(... ENVIRONMENT "XTBPATH=...;OMP_NUM_THREADS=1")` |
| `test/unit/meson.build:650` | `test('native opt lbfgs symbols', python, env: landscape_env, args: [... 'nativeoptsym', ...])` |
| `test/unit/landscape_cli_check.py:56,2462,3045` | 头注 mode 表、`check_native_opt_symbols`、`elif mode == "nativeoptsym"` |

**测试名唯一性**（CMake 同名会**静默丢测试**）：

```
$ grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sort | uniq -d
(空)
$ grep -oE "^test\('[^']+'" test/unit/meson.build | sort | uniq -d
(空)
```

---

## 4. 「数值不变」的证据

对 `optlbfgs` 这一对运行（唯一的"有意改变"用例），把**所有数值 token**（`[-+]?\d+\.\d+(e±\d+)?`）
按出现顺序抽出并比较：

| 文件 | 数值 token 数（base / new） | 序列相同 |
|---|---|---|
| `xtbopt.xyz` | 12 / 12 | **是** |
| `xtbopt.log` | 60 / 60 | **是** |
| `xtbtopo.mol` | 10 / 10 | **是** |
| 归一化 stdout | 389 / 389 | **是** |

补充锚点：

- `TOTAL ENERGY` 行两侧都是 `-5.070544430927 Eh`；
- `xtbopt.xyz` 第 2 行能量/梯度元数据逐字符相同：
  `energy: -5.070544430927 gnorm: 0.000135264098`；
- 坐标列逐字符相同（§2 的 `diff` 只命中第 1 个 token）。

**容差来源：无容差**。所有比较都是逐字符 / 逐位，不存在"到容差一致"的措辞：
末几何与末能量**逐位相同**，因为修复只改**拷贝方式**，不触碰任何浮点运算
（`copyMolecule` 与内在赋值搬的是同一批 `mol0%xyz`/`mol0%at`，见 §1）。
`xtbtopo.mol` 的 MDL 日期行（分钟分辨率）是唯一的非数值差别，已单独掩码重比（§2 末）。

---

## 5. 登记为「有意行为变更」且与 18 条 CLI 破坏性变更**分开计数**

- `docs/_simplify-recon/11-cli-redesign.md`：
  - §修订表新增 **R42** 行；
  - §0「破坏性变更」行加尾注：**R42 不改变 18 这个计数**，它是**独立的上游 bug 修复**；
  - §10 汇总行后新增 R42 注（同口径：`A 3 + B 0 + C 8 + D 1 + E 1 + F 4 + G 1 = 18` 不变，
    但**原生输出字节确实变了**，已在 BC-4 里单列为"有意改变"的一行）。
- `AGENTS.md` §6 第 5 条：由"我们在自己的 `log.f90` 绕过"扩写为"**上游
  `src/relaxation_engine.f90:615/:779` 也有同一缺陷**，本机编译器的 L-BFGS 路径会写垃圾字节，
  已修；并加规则「新写派生类型赋值时**永不**用内在赋值，一律 `call a%copy(b)`」，
  同时登记**仍未修**的 `src/screening.f90:107`。

---

## 6. 被证伪的前提（本轮实测推翻的判断）

1. **「严格 `raw.decode('utf-8')` 足以捕获该缺陷」——错。**
   坏字节大量是 NUL，而 NUL 是**合法** UTF-8 码点 U+0000；实测第一次复现的 buggy stdout
   严格解码**成功**。因此测试**必须**另有控制字节扫描 + 符号列比对（§3.1）。这也意味着
   阶段 2 引入的容错解码（`errors='replace'`）**不是**（也不是）能掩盖该断言的原因——
   即使换成严格解码也会漏，必须看字节/看符号。
2. **「两个构建目录的 stdout 可直接逐位比较」——错（BC-4 第一轮的假差异）。**
   第一轮 BC-4 里 **9 个"应当不变"的用例也红了**（`sp`/`hess`/`md` 等的归一化 stdout 差 2-6 行、
   位置在 `normal termination of xtb` 与 C 层 `Topologies differ...` 之间**互相换位**）。
   根因不是修复，而是 `/tmp/xtb-up/build` 的 `include/xtb_version.fh` 当时被生成为
   `6.7.1 (unknown-commit)`，而基线是 `6.7.1 (0406baf...)`：**版本串长度不同改变了
   Fortran 单元 6 与 glibc `printf` 两块缓冲的刷新边界**，于是交错顺序翻转。
   重跑 `cmake -S . -B /tmp/xtb-up/build` 让 header 正确后再建，**9/10 用例立刻逐位全同**（§2）。
   ⇒ BC-4 的前提是**两个二进制的构建元数据必须相同**（阶段 2 `25-stage2-impl.md` 已记录过一次
   同样的对齐动作）。
3. **「坏字节是固定的 NUL」——错。** 实测同一二进制不同运行的坏字节为 NUL / `0xcd` / `0xec` /
   `0xac` / 数字串 `"4443"`；断言不能写死字节值（§3.1）。派生事实：**"只跑一次看看输出"
   不足以刻画该缺陷**，必须按语义（符号列）断言。

---

## 7. 复现与验证命令（全部 `OMP_NUM_THREADS=1`）

```bash
# 构建（本修复）
cmake -S . -B /tmp/xtb-up/build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"
cmake --build /tmp/xtb-up/build -j

# 基线（同一 commit，未打补丁）—— 本轮已建、跑完即清理（基线二进制保留）
git worktree add --detach /tmp/xtb-up/base HEAD
cmake -S /tmp/xtb-up/base -B /tmp/xtb-up/base-build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF \
      -DWITH_TESTS=ON -DCMAKE_BUILD_TYPE=Release -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"
cmake --build /tmp/xtb-up/base-build -j --target xtb-exe
git worktree remove /tmp/xtb-up/base      # 仅删工作树，/tmp/xtb-up/base-build/xtb 保留

# 新测试（绿）
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-up/build -R native-opt-lbfgs-symbols --output-on-failure

# 套件 + 回归子集
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-up/build -R landscape
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-up/build -R 'Singlepoint|GFN|model-hessian|optimizer|Argparser|CAPI'

# BC-4（逐文件 cmp）
bash /tmp/xtb-up/bc4/bc4.sh        # 输出 /tmp/xtb-up/bc4/bc4-final.out

# 手工复现缺陷 / 验证修复（本机）
cd /tmp/xtb-up/repro
printf '$opt\n engine=lbfgs\n$end\n' > lbfgs.inp
OMP_NUM_THREADS=1 /tmp/xtb-up/base-build/xtb h2o.xyz --gfn 2 --opt normal --input lbfgs.inp --norestart
xxd xtbopt.xyz | head -8     # 符号列是 NUL/垃圾（基线）
OMP_NUM_THREADS=1 /tmp/xtb-up/build/xtb h2o.xyz --gfn 2 --opt normal --input lbfgs.inp --norestart
sed -n '3,5p' xtbopt.xyz      # O / H / H（修复后）
```

**最终验证结果（本轮）**

| 检查 | 结果 |
|---|---|
| `ctest -R landscape` | **121/121 通过**（37.6 s） |
| `ctest -R 'Singlepoint\|GFN\|model-hessian\|optimizer\|Argparser\|CAPI'` | **12/12 通过** |
| `ctest -R native-opt-lbfgs-symbols` | **1/1 通过** |
| BC-4 10 用例 | 9 个逐文件 + stdout 逐位同；1 个（`optlbfgs`）**有意改变**，数值 token 序列相同 |

---

## 8. 残留风险 / 未做

- **`src/screening.f90:107` `mol = mol0` 是同一类内在赋值**（`type(TMolecule)` → `type(TMolecule)`），
  走 `--screen` 结构筛选路径。**本任务范围内我未改它**（任务限定只改 `relaxation_engine` 的 2 行），
  但它有同样的潜在符号破坏。已记入 `AGENTS.md` §6 第 5 条。
- **n>500 原子的默认 L-BFGS 路径**（`src/main/defaults.f90:42-46`）在修复范围内，但我**没有**
  用 501 原子体系跑数值验证（按纪律避免重复大体系实验）。它是**同一段代码**（`l_ancopt`），
  已由小体系覆盖。
- **`xtbtopo.mol` 的 MDL 日期行是分钟分辨率**：BC-4 的 raw `cmp` 有两分钟边界处的假差异风险
  （本轮 10 个用例恰在同一分钟内）。已用"时间戳掩码后重比"兜底（§2 末），但 CI 侧若复刻
  BC-4 建议沿用 `25-stage2-impl.md` 的 `sed 's/^ *[0-9]+[A-Z]$/TIMESTAMP/'` 归一化。
- **meson 无法本地验证**（本机无 meson/ninja，AGENTS.md §4）：meson 侧的注册
  （`test/unit/meson.build:650`）只做了静态核对（名字唯一、mode 与 CMake 一致）。
- **未提交 git**（按要求）；`git status` 因此显示 4 个已改文件 + 本报告 + 未跟踪的
  `AGENTS.md`（该文件本就被 gitignore）。

---

## 复核处置（依据 31-upstream-fix-review.md）

31 号复核结论 = **接受**（唯一 1 条 MEDIUM，已按下表关闭）。它确认：修复最小（仅 2 行代码 + 3 行注释）、
可证伪性主张成立（三重断言：严格解码 + 控制字节扫描 + 符号列逐原子比对）、R42 计数自洽、
`screening.f90:107` 是 `src/` 里唯一剩余同型处且已登记、边界干净、注册完整。

**MEDIUM-1（跨阶段交互，已登记为阶段 3 工作项）**：本轮的回归测试用 `--opt --input <$opt engine=lbfgs>`，
而**阶段 3 的 C7 / §3.8(c)** 会把「套件 runtype + `$opt` 块」变成**响亮错误** ⇒ 该测试在阶段 3 会失效。
**阶段 3 落地时必须同步**：把该测试的调用改为阶段 3 下的合法路径（原生 L-BFGS = `--opt --method lancopt`），
**断言保持三重不变**（严格解码 + 控制字节扫描 + 符号列比对）。
（与 `check_scanblock` 492-503 的改写同类，已一并登记。）

**复核的一条纪律提醒（记录在案）**：新测试变红时，**不得**用 `errors='replace'` 之类放宽解码的方式"修绿" ——
那会**静默解除断言**，正是本项目一直在消灭的缺陷类型。
