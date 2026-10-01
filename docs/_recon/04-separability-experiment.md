# 04 — GFN2‑only 独立二进制“可分离性”实验报告

目标仓库：`grimme-lab/xtb` v6.7.1（Fortran + C），本机路径 `/home/owenchan/work_path/coding/fortran/xtb`。
本报告所有证据均给出 `文件:行号`，均为实测（非推测）。附带产物：
`docs/_recon/closure.py`、`docs/_recon/closure-output.txt`、`docs/_recon/reduced-link-output.txt`、`docs/_recon/environment.txt`。

---

## 0. 结论摘要（TL;DR）

| 问题 | 判定 | 置信度 |
|---|---|---|
| (i) **只改构建系统、不改任何源码**，能否编出“只支持 GFN2‑xTB”的独立二进制？ | **不可行** | 高（≈95%） |
| (ii) **允许改源码/删代码**，能否做到？ | **可行** | 中高（≈85%） |
| 估算工作量 | 中等：新写一个最小 GFN2 driver ≈200–400 行；或裁剪 `src/prog/main.F90`（2231 行）等入口 | — |

主要障碍（均有证据，见下文）：
1. **唯一可执行入口 `src/prog/main.F90` 无条件 `use` 了全套功能模块**（gfnff / iff / ptb / tblite bridge / solv / oniom / dipro / extern 等）。只改构建系统无法移除这些 `use`，编译即失败。缩减链接实测：去掉 gfnff 目标文件 → **46** 处 undefined reference；再去 iff → **61**；去掉全部特性目录 → **251**。
2. **mctc‑lib 是强制外部依赖且本机未安装**（`mctc_env` / `mctc_io` / `mctc_data`），只能联网从 GitHub 拉取（CMake FetchContent 会自动抓 v0.5.1）。离线环境连普通构建都做不了。
3. **模块闭包同时“高估”和“低估”真实链接依赖**：`#if WITH_TBLITE` 保护的 `use tblite_*` 会被词法闭包计入（高估）；而 `integer, external :: lin/ncore` 这类隐式外部过程不会出现在闭包里（低估）。

---

## 1. 环境与依赖实测（方法 B）

工具链（`docs/_recon/environment.txt`）：

```
gfortran : /usr/bin/gfortran  GNU Fortran (Debian 12.2.0-14+deb12u1) 12.2.0
gcc      : /home/owenchan/programs/gcc15/bin/gcc  (GCC 15.2.0)
cmake    : /home/owenchan/programs/cmake/bin/cmake  cmake version 4.3.2
meson    : command not found        ← 缺失
ninja    : command not found        ← 缺失
```

pkg-config（第三方库）：
```
openblas / blas / lapack      (OpenBLAS, /usr/lib/x86_64-linux-gnu/libopenblas.so)
```
`ldconfig -p | grep -iE "mctc|dftd4|tblite|xtb"` → **无任何输出**（本机没有这些库）。

外部依赖打包情况：
- `subprojects/` **只有 `.wrap` 文件**，没有 vendored 源码：
  `cpx.wrap dftd4.wrap mctc-lib.wrap multicharge.wrap tblite.wrap test-drive.wrap`。
- `.gitmodules` 只声明了 `assets/aur/xtb-git`，与计算依赖无关；
  `git submodule status` → `-4c3d... assets/aur/xtb-git`（未初始化）。
- 本机仅在 `/mnt/d/xtb-6.7.1/` 找到一份 **Windows 预编译包**（`xtb.exe`、`libxtb.a`、`libcpx.a`），无 Linux 头/库可用。

网络：**可用**（`git ls-remote https://github.com/grimme-lab/mctc-lib` 成功返回）。这正是后面能真编起来的原因。

CMake 的依赖发现策略见 `cmake/modules/xtb-utils.cmake:31`：`MCTCLIB_FIND_METHOD = cmake → pkgconf → subproject → fetch`；`cmake/modules/Findmctc-lib.cmake:19-20` 指定 `_url=https://github.com/grimme-lab/mctc-lib`、`_rev=v0.5.1`。本机 cmake/pkgconf/subproject 全部落空，最终走 **fetch**。

---

## 2. 静态闭包分析（方法 A）

脚本：`docs/_recon/closure.py`（236 行）。做法：
- 遍历 `src/` 与 `symmetry/` 下所有 Fortran 文件（扩展名 `.f90/.f90/.F90/.f/.F` 等），正则提取
  `module X`、`submodule (X) Y`、`use X` / `use, intrinsic :: X` / `use :: X`；
- 建 `provider(module)→file`、`file→uses`；
- **种子** = `src/prog/CMakeLists.txt` 里 `${prog}` 列表中的文件 + `src/main/*`；对 `use` 做 BFS 传递闭包；
- 内建模块（`iso_fortran_env`、`omp_lib` 等）白名单排除。

### 2.1 真实输出（种子 = `${prog}` + `src/main/*`）

`python3 closure.py`（完整输出见 `closure-output.txt`）：

```
total fortran files in repo (src/+symmetry/): 362
seed files: 14
files in transitive closure: 286
files excluded by closure: 76
```

排除文件按目录分组（节选）：
```
[src]        (51)  constr.f90 david.f define.f90 drsp.f elem.f90 enso_printout.f90
                   eqrot.f90 expire.f90 filetools.F90 foden.f90 fragment.f90
                   generate_wsc.f90 geosum.f90 getname.f90 getsymnum.f90
                   gfn_prparam.f90 header.f90 htosq.f90 ifind.f90 lin.f90 ...
[src/api]    (7)   calculator.f90 environment.f90 interface.f90 molecule.f90 results.f90 utils.f90 version.f90
[src/dipro]  (1)   version.f90
[src/disp]   (1)   dftd3.f
[src/gfnff]  (5)   getring36.f90 gfnff_qm.f90 gfnff_rab.f math.f shortest_distance.f90
[src/lbfgs_anc](2) filter.f90 optimizer.f90
[src/main]   (1)   run.f90
[src/mctc]   (6)   error.f90 mctc_filetools.f90 mctc_init.F90 mctc_linux.f90 namegen.f90 runtypes.f90
[src/type]   (1)   options.f90
[symmetry]   (1)   symmetry.f90
```

闭包内引用到的**外部（仓库外）模块**共 54 个，其中按文件数计：
```
mctc_env 25, mctc_io 19, tblite_basis_type 19, tblite_blas 9,
tblite_wavefunction 8, tblite_adjlist 5, tblite_context 5, ... cpx 1
（完整列表见 closure-output.txt）
```

### 2.2 仅从 `src/prog/main.F90` 播种（`python3 closure.py --only-main`）

```
total fortran files in repo (src/+symmetry/): 362
seed files: 1
files in transitive closure: 274
files excluded by closure: 88
```
注意：入口从 14 个种子缩到 1 个，闭包只从 286 降到 274——**CLI 本身就已经把整棵依赖树基本拉满（76%–79%）**，进一步“只保留 GFN2”必须动源码，见 §5。

### 2.3 闭包的已知偏差（重要）

- **高估**：`closure.py` 数到的 54 个外部模块中包含大量 `tblite_*`，但这些 `use` 全部位于 `#if WITH_TBLITE` 之内（例：`src/tblite/calculator.F90:29-49`、`src/type/data.F90:26-27`、`src/type/restart.F90:26-27`），预处理后并不存在。实测用 `WITH_TBLITE=OFF` 编译这些外部模块根本不出现。
- **低估**：固定格式/遗留代码里用隐式外部过程（`integer, external :: lin` 等）而非 `use`，这些文件不会进入模块闭包。实测把它们从链接里剔除会出现 undefined reference（见 §4.3）。

---

## 3. 外部依赖与链接期耦合（方法 D）

### 3.1 真正必需的外部库：只有 mctc‑lib

- 顶层 `CMakeLists.txt:43`：`find_package("mctc-lib" REQUIRED)` —— **无条件必需**。
- `CMakeLists.txt:46-48`：tblite 受 `WITH_TBLITE` 控制；`CMakeLists.txt:56-58` cpcmx 受 `WITH_CPCMX` 控制。
- 实测（§4）：`WITH_TBLITE=OFF WITH_CPCMX=OFF` 时**全库 + 可执行文件全部编译链接成功**，唯一外部库就是抓下来的 mctc‑lib v0.5.1。因此 **tblite / dftd4 / multicharge / mstore / cpx 都不是 GFN2 二进制所必需的**。

外部模块家族与引用文件数（`closure.py` 的 `module_report`）：
```
mctc_env: 25 files (dipro, io/reader, io/writer, main/json, ptb/*, solv/cpx, tblite/calculator)
mctc_io : 23 files (含 mctc_io_constants/_convert/_filetype/_structure/_structure_info)
dftd4   : 1 file   (src/ptb/coulomb.F90 的 dftd4_data_hardness)
cpx     : 1 file   (src/solv/cpx.F90)
mctc_data: 1 file  (src/ptb/ncoord.F90)
tblite_*: 全部位于 #if WITH_TBLITE 之内
```
可见 mctc‑lib 被 **IO（分子读写）、structure、param 数据**这条主链使用，是硬耦合：
`src/io/reader.f90`、`src/io/writer.f90`、`src/main/json.F90`、`src/main/property.F90`、`src/mctc/filetypes.f90`。
GFN2 核心 SCC 链（`src/scc_core.f90`、`src/grad_core.f90`、`src/eeq_model.f90`、`src/aespot.F90`）**没有任何外部 use**（grep 为空）——GFN2 引擎本身的数学部分是自包含的。

### 3.2 链接期隐式耦合（模块闭包捕捉不到）

遗留代码通过隐式外部接口调用 standalone 过程（无 module），例如：
- `src/scc_core.f90:179,394`：`integer, external :: lin`
- `src/optimizer.f90:259`：`integer, external :: lin`；`src/optimizer.f90:1139`：`real(wp), external :: ddot`
- `src/prog/main.F90:170`：`integer, external :: ncore`
- `src/main/geometry.f90:477`、`src/scanparam.f90:157,406`、`src/constrain_param.f90:413`：`real(wp), external :: valijkl`
- 提供者文件本身不在模块闭包里：`src/lin.f90:22`（`lin`/`lina`）、`src/pqn.f90:37,62`（`pqn`/`ncore`）、`src/ifind.f90`、`src/neighbor.f90`、`src/rmsd.f90`、`src/readl.f90`、`src/constr.f90` 等。§4.3 用链接实验证实。

固定格式（fixed‑form）遗留文件（task 特别点名）：
```
src/david.f  src/drsp.f  src/esp.f  src/stm.f  src/surfac.f
src/disp/dftd3.f  src/gfnff/gfnff_rab.f  src/gfnff/math.f
```
- `src/esp.f`（`module esp`）与 `src/stm.f`（`module stm`）被 `src/main/property.F90:586-587` 显式 `use`，进入闭包；`esp.f:66` 又 `call surfac`，把 `src/surfac.f` 链接进来。
- `src/david.f`、`src/drsp.f`、`src/surfac.f` 不提供 module，**被模块闭包排除**，但 `surfac`/`david` 仍通过外部调用在链接期被需要。
- `COMMON` 块：`src/esp.f`、`src/intpack.f90`（`grep -lE "^\s*common\s*/"` 仅这两处）。
- 多个文件中重复定义同名 standalone 符号（如 `valijkl` 在 `src/basic_geo.f90:245` 与 `src/constr.f90:816`；`lin` 在 `src/lin.f90:22` 与 `src/lin_mod.f90:29` 的模块内）——静态库链接“先到先得”，一旦减少源文件列表极易触发重复/未定义符号。

---

## 4. 真实构建与缩减链接实验（方法 C）

所有构建在 `/tmp` 下进行，**未改动仓库工作树**（`git status` 仍为空）。

### 4.1 默认选项配置：失败（构建环境障碍）

```
cmake -S <repo> -B /tmp/xtb-red/build -DWITH_TBLITE=OFF
...
CMake Error at .../cpcmx-src/config/modules/cpcm-x-utils.cmake:102 (add_library):
  add_library cannot create imported target "toml-f::toml-f" because another
  target with the same name already exists.
```
即：在 cmake 4.3.2 下，默认 `WITH_CPCMX=ON` 会与 xtb 自己 fetch 的 toml‑f 抢同名 imported target，配置直接失败。**这是环境层面的坑，不是可分离性问题**，但说明“拿默认选项一把梭”在本机行不通。

### 4.2 关闭可选特性后：**构建成功**

```
cmake -S <repo> -B /tmp/xtb-red2/build \
      -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=OFF
-- Retrieving mctc-lib from https://github.com/grimme-lab/mctc-lib
...
-- Configuring done (20.7s)      EXIT=0

cmake --build /tmp/xtb-red2/build -j
[100%] Linking Fortran executable xtb
[100%] Built target xtb-exe     EXIT=0
```
产物：`/tmp/xtb-red2/build/xtb` (13.9 MB)、`libxtb.a` (21.6 MB)。
抓到的 mctc‑lib：`v0.5.1`（`aa89d4bf5c0076fbf169b59eeb9e30185db0e5a5`）。

启动验证 + 真实 GFN2 单点（水分子）：
```
$ ./xtb --version
... xtb version 6.7.1 (unknown-commit) ...
$ ./xtb /tmp/w.xyz --gfn2 --sp
:  Hamiltonian                  GFN2-xTB          :
:: total energy              -5.070383095219 Eh    ::
| HOMO-LUMO GAP              14.518987926825 eV   |
normal termination of xtb     EXIT=0
```
**结论：一个能跑 GFN2 的完整二进制，其外部依赖下限就是 mctc‑lib（联网 fetch）**。

### 4.3 缩减链接实验：暴露 CLI 的硬耦合

用 `xtb-object` 的全部 `.o` 做手工链接，逐个剔除特性目录（链接命令模板与完整输出见 `reduced-link-output.txt`）：

```
gfortran -fdefault-real-8 -fdefault-double-8 <prog objs> -o OUT \
         <xtb-object objs minus EXCLUDE> _deps/mctc-lib-build/libmctc-lib.a \
         -lopenblas -lm -ldl -fopenmp
```

| EXCLUDE | 退出码 | undefined reference 行数 | 典型未定义符号 |
|---|---|---|---|
| `/gfnff/` | 1 | **46** | `__xtb_gfnff_calculator_MOD_newgffcalculator`, `..._Tgffcalculator`(23×), `__xtb_gfnff_param_MOD_gff_print`, `__xtb_gfnff_shake_MOD_init_shake` … |
| `/gfnff/\|/iff/` | 1 | **61** | 上面 + `__xtb_iff_iffenergy_MOD_iff_e`(5×), `__xtb_iff_iffprepare_MOD_precomp` … |
| `/gfnff/\|/iff/\|/ptb/\|/solv/` | 1 | **102** | 上面 + `__xtb_ptb_calculator_MOD___vtab_...`, `__xtb_solv_gbsa_MOD___vtab_..._Tborn` … |
| 全部特性目录 | 1 | **251** | `__xtb_docking_param_MOD_optlvl`(43×), `__xtb_docking_set_module_MOD_set_logicals`, `__xtb_tblite_calculator_MOD_...`, `__xtb_ptb_...` … |

链接期隐式耦合验证（证明模块闭包低估）：
| EXCLUDE | undefined reference |
|---|---|
| `/src/lin\.f90\.o` | **`lin_`**（来自 `src/scc_core.f90:218`） |
| `/src/pqn\.f90\.o` | **`ncore_`** |
| `/src/lin_mod\.f90\.o` | **`__xtb_lin_MOD_lin`**（来自 `src/xtb/hamiltonian.F90:282`） |

错误分类：
- **compile-time 缺失模块**：`WITH_TBLITE` 关闭后 `use tblite_*` 被预处理器移除 → 无错误；若强行保留会报 “Cannot open module file 'tblite_*.mod'”。（`WITH_TBLITE` 已由 `src/features.F90:16-17` / `src/tblite/*.F90:17-18` 等处的 `#ifndef … #define 0` 兜底。）
- **link-time 未定义符号**：`lin_ / ncore_ / __xtb_lin_MOD_lin` 及上表全部 `__xtb_<feature>_MOD_*` → 说明“删除源文件”会断链。
- **需要外部库**：只有 `libmctc-lib.a`（+ OpenBLAS/OpenMP/threads）。tblite/dftd4/cpx 在关闭开关后完全不需要。

---

## 5. 判定（方法 E）

### (i) 只改构建系统（不改源码）→ **不可行**（置信度高）

理由（逐条证据）：
1. 本仓库唯一的可执行入口是 `src/prog/primary.f90`（`program`）→ `src/prog/main.F90`（`module xtb_prog_main`）。`main.F90` **无条件** `use` 了全部非 GFN2 模块：
   `src/prog/main.F90:72 xtb_gfnff_calculator`、`:73 xtb_iff_calculator`、`:87-89 xtb_gfnff_param/topology/convert`、`:92-93 xtb_iff_*`、`:94 xtb_oniom`、`:96 xtb_tblite_calculator`、`:98 xtb_ptb_calculator`、`:99 xtb_solv_cpx`、`:100 xtb_dipro`。
   计算器工厂 `src/main/setup.f90:21-38` 同样无条件 import 了 solv/extern/tblite/ptb/gfnff/iff/oniom。
2. 构建系统只能决定“编不编译某个 .c/.f90”，**无法移除源码里的 `use`**。只要 `main.F90` 仍被编译，就一定需要那些 `.mod`；一旦按“只留 GFN2 源文件”缩减，实测出现 46/61/102/251 处 undefined reference（§4.3）。
3. 仓库里**不存在任何现成的 GFN2‑only 可执行目标**可供构建系统切换（`src/prog/` 只有全套 CLI；`test/` 是测试）。
   → 除非允许“新增一个 driver 源文件”（那已属源码改动），否则无解。

### (ii) 允许改源码 → **可行**（置信度中高）

可行路径（推荐 A）：
- **A. 新写最小 driver**：复用现有引擎 API（`xtb_type_environment` / `xtb_type_molecule` / `xtb_xtb_calculator:newXTBcalculator` + `xtb_xtb_gfn2` / `xtb_single` / `xtb_geoopt_driver` / `xtb_io_reader` / `xtb_printout`），写 ~200–400 行 `program`，只 `use` GFN2 所需模块，然后在 CMake 里加一个显式源列表的可执行目标。经验证 GFN2 引擎链自包含（§3.1），且整库在仅 mctc‑lib 下可编（§4.2），所以这条路技术风险低。
- **B. 裁剪 `src/prog/main.F90` + `src/main/setup.f90` / `defaults.f90` / `argparser` / `submodules` / `topology.f90` / `dock.f90` / `property.F90` / `json.F90` 中的非 GFN2 分支**：把 `case` 派发里 gfnff/iff/ptb/tblite/oniom/solv/extern/dipro 的分支删掉，并删除对应 `use`。工作量更大，因为 `main.F90` 有 2231 行且特性逻辑交织。

需要注意的“不能删”的耦合：
- `src/xtb/gfn2.f90:25` 反向依赖 `xtb_xtb_gfn1`（`setGFN1ShellHardness`）→ **GFN1 代码不能整块删除**。
- 遗留 standalone 符号 `lin/ncore/pqn/valijkl/ifind/...` 必须在源列表里（或同步改调用点），否则断链（§3.2、§4.3）。
- 分子读写链路依赖 mctc‑lib（§3.1），无法回避；除非重写 `src/io/reader.f90/writer.f90`（成本高）。
- `symmetry/symmetry.f90` + `symmetry/symmetry_i.c` 参与几何处理，需保留。

### (iii) 工作量 / 主要障碍总结

| 障碍 | 性质 | 影响 |
|---|---|---|
| `main.F90` 无条件 use 全部特性模块 | 源码结构 | 这是 (i) 不可行的根因；裁剪需动 2000+ 行 |
| 模块闭包低估链接依赖（隐式 external） | 遗留代码 | 按闭包裁源文件会 undefined reference（lin/ncore） |
| 模块闭包高估依赖（`#if` 保护） | 预处理 | 静态统计会误报 tblite 依赖；以实测开关为准 |
| mctc‑lib 本地缺失、只能联网 fetch | 环境 | 离线环境根本无法构建 |
| cmake 4.3.2 与默认 cpcmx/toml‑f 目标冲突 | 环境 | 必须显式 `-DWITH_CPCMX=OFF` |
| gfortran 需 `-fdefault-real-8 -fdefault-double-8` | 构建 | 重写 driver 时必须沿用（见 `cmake/CMakeLists.txt:50`） |

估算：新写最小 GFN2 driver 约 **0.5–1 人日**（含构建系统目标）；彻底裁剪 CLI 约 **3–5 人日**。

---

## 6. 附：产物与命令清单

产物（均在 `docs/_recon/`，未改动任何被 git 跟踪的文件）：
- `closure.py` — 静态闭包脚本（236 行），支持 `--only-main`
- `closure-output.txt` — `closure.py` 的两份真实输出（455 行）
- `reduced-link-output.txt` — 缩减链接实验真实输出（71 行）
- `environment.txt` — 工具链/依赖实测输出
- `04-separability-experiment.md` — 本报告

关键命令：
```bash
# 静态闭包
python3 docs/_recon/closure.py > docs/_recon/closure-output.txt
python3 docs/_recon/closure.py --only-main >> docs/_recon/closure-output.txt

# 真实构建（仅 mctc-lib）
cmake -S . -B /tmp/xtb-red2/build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=OFF
cmake --build /tmp/xtb-red2/build -j
/tmp/xtb-red2/build/xtb /tmp/w.xyz --gfn2 --sp

# 缩减链接（模板）
gfortran -fdefault-real-8 -fdefault-double-8 <prog objs> -o OUT \
  <xtb-object objs minus EXCLUDE> _deps/mctc-lib-build/libmctc-lib.a \
  -lopenblas -lm -ldl -fopenmp
```

> 说明：所有“真实构建/链接”都在 `/tmp` 下进行；仓库工作树 `git status --short` 始终为空。
