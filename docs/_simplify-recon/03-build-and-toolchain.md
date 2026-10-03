# 03 — 编译方式与工具链调查（调查员 C）

> **性质**：只调查，不改代码。本次会话**未修改仓库内任何源码/构建文件/测试/AGENTS.md**（只在 `/tmp` 下建独立构建目录，
> 唯一写入仓库的文件就是本报告）。
> **约定**：凡标「★实测」的都有真实命令与输出；「推断」= 有证据但未直接验证；「未验证」= 我没有数据。
> 报告里所有 `file:line` 都对应本仓库 HEAD = `24c069f`。

---

## 0. 结论速览（先看这一段）

1. **「不再需要 meson」这个目标现状已经满足，而且从来就不是问题。** 我们的构建链是 **CMake + gfortran**；
   `CMakeLists.txt` / `cmake/**` 里**没有任何 meson 引用**（唯一一处是 `test/unit/CMakeLists.txt:616` 的注释）。
   `meson.build`、`meson_options.txt`、`subprojects/*.wrap` 是上游提供的**另一条**构建路径，本仓库从未用过。
2. **但「只用 gcc/gfortran」还有两个缺口，它们与 meson 无关**：
   - **(i) 构建工具缺口**：CMake 本身就是一台额外工具（它是构建系统，不是编译器）。要真正「只有 gfortran」，
     就得**去掉 CMake**，换成 Makefile 或直接命令行。这是**新工作**，不是现状。
   - **(ii) 依赖缺口**：`mctc-lib` 是**必需**依赖，当前由 CMake 的 `FetchContent` **从 GitHub 克隆**（★实测）。
     不去掉这个下载，就谈不上「只有 gfortran 就能编译」。两条零下载路线我实测通了（§2.3）。
3. **编译器层面现状已满足**：只要 `gfortran`（+ 系统 `libopenblas`），无 Intel 编译器、无 MKL、无 Python。
   CMake 里 GNU 分支只加 `-fdefault-real-8 -fdefault-double-8 -ffree-line-length-none -fbacktrace`（`cmake/CMakeLists.txt:49-51`）。
4. **「混链」这个担忧是环境变量造成的假象，不是构建事实**（★实测）：
   我们的二进制**编译和链接**都只用 `/usr/bin/gfortran`（GCC 12.2.0）；
   `ldd` 里出现的 `gcc15/lib64` 库，是因为当前 shell 的 `LD_LIBRARY_PATH` 里有
   `/home/owenchan/programs/gcc15/lib64:`，运行时把它们**抢先**解析了。`env -u LD_LIBRARY_PATH ldd` 全部回到系统库。
   另外 `gcc15` **根本没有 gfortran**，也**没有 libgfortran**（只有 C/C++），所以它不可能是我们的 Fortran 工具链。
5. **数值等价性（★实测，这是本报告最有价值的结果）**：在**同一份源码**（edcfbbe = 参照二进制的源码状态）上，
   `gfortran 12.2.0 (-O0) + OpenBLAS` 与 `Intel + MKL + meson + 静态` 产出的 `hessian` 文件 **max diff = 0.0（逐位相同）**，
   `charges` / `vibspectrum` **字节相同**，频率 1557.4148 / 3677.8357 / 3684.0117 **完全相同**。
   ⇒ 编译器/BLAS 的差异在本任务的数值上**不可见**；差异几乎全部来自**源码状态**与**构建选项**。
6. **一个真实的风险（★实测，父会话应知悉）**：`gfortran 12.2.0` 在 **`-O3`（= 我们 CMake `Release` 的默认档）** 下
   编译 **edcfbbe 源码** 的 Hessian 路径给出**错误**结果（`-931.59 / 3329.78 / 3345.94 cm^-1`），
   而 `-O0 / -O1 / -O2` 全部给出**与参照二进制一致**的正确答案。**我们的 HEAD 源码在 `-O3` 下目前是正确的**（探测范围内）。
   机制**未定位**；加 `-fno-tree-vectorize` 不能消除。建议保守使用 `-O2`（详见 §4.4、§7）。

---

## 1. 现状：我们到底怎么编译

### 1.1 完整可复跑命令（★实测）

```bash
# 1) 配置（22 s，含从 GitHub 克隆 mctc-lib）
/home/owenchan/programs/cmake/bin/cmake \
  -S /home/owenchan/work_path/coding/fortran/xtb \
  -B /tmp/xtb-static/build \
  -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=OFF \
  -DCMAKE_BUILD_TYPE=Release

# 2) 构建（36 s，-j8）
/home/owenchan/programs/cmake/bin/cmake --build /tmp/xtb-static/build -j8
```

真实输出（节选，`/tmp/xtb-static/configure.log`）：

```
-- The Fortran compiler identification is GNU 12.2.0
fatal: not a git repository (or any of the parent directories): .git
-- Retrieving mctc-lib from https://github.com/grimme-lab/mctc-lib
-- Found OpenMP_C: -fopenmp (found version "4.5")
-- Found OpenMP_Fortran: -fopenmp (found version "4.5")
-- Found OpenMP: TRUE (found version "4.5")
-- Found BLAS: /usr/lib/x86_64-linux-gnu/libopenblas.so
-- Found LAPACK: /usr/lib/x86_64-linux-gnu/libopenblas.so;-lm;-ldl
-- Configuring done (22.0s)
```

构建耗时（★实测）：`real 0m36.173s / user 2m41s / sys 9.97s`（8 核，make 生成器）。

### 1.2 构建产物清单（★实测）

| 产物 | 路径 | 大小 | 说明 |
|---|---|---|---|
| 可执行文件 | `build/xtb` | 8 732 472 B | ELF PIE **动态链接**，`not stripped` |
| 静态库 | `build/libxtb.a` | 12 285 288 B | `lib-xtb-static`（`CMakeLists.txt:138-150`） |
| 共享库 | `build/libxtb.so.6.7.1` | 9 059 096 B | `lib-xtb-shared`（`CMakeLists.txt:186-221`） |
| 模块 | `build/include/*.mod` | **343 个** | Fortran module 文件 |
| 测试 | `build/test/unit/xtb-tester` 等 | — | 仅 `WITH_TESTS=ON` 时构建 |

> CMake 默认**同时**构建静态库 + 共享库 + 可执行文件（`WITH_OBJECT` 模式，`CMakeLists.txt:94-133`）。
> 若只想静态链接，`libxtb.so` 会成为障碍（见 §4.3 实测）。

### 1.3 每个 `-D` 选项的含义

| 选项 | 定义处 | 默认 | 作用 |
|---|---|---|---|
| `WITH_OpenMP` | `cmake/CMakeLists.txt:18` | TRUE | 链 `OpenMP::OpenMP_Fortran`（`CMakeLists.txt:80-82,119`） |
| `WITH_TBLITE` | `cmake/CMakeLists.txt:19` | TRUE | `find_package(tblite)` + `add_compile_definitions(WITH_TBLITE)`（`CMakeLists.txt:46-49`） |
| `WITH_CPCMX` | `cmake/CMakeLists.txt:20` | TRUE | `find_package(cpcmx)` + `add_compile_definitions(WITH_CPCMX)`（`CMakeLists.txt:56-59`） |
| `WITH_TESTS` | `cmake/CMakeLists.txt:21` | TRUE | `add_subdirectory("test")`（`CMakeLists.txt:351-354`）；打开后**必须**有 `test-drive`（`CMakeLists.txt:66-68`） |
| `WITH_OBJECT` | `CMakeLists.txt:18` | TRUE | 用 object library 编译一次给静态/共享库共用 |
| `BUILD_TYPE` | `cmake/CMakeLists.txt:25-35` | **RelWithDebInfo** | 不给就自动设 RelWithDebInfo；我们显式给 `Release` ⇒ `-O3`（`CMakeCache.txt:134`：`CMAKE_Fortran_FLAGS_RELEASE:STRING=-O3`） |

`WITH_TBLITE` / `WITH_CPCMX` 的功能影响可以从源码精确定位到两个常量：

```fortran
! src/features.F90:16-21
#ifndef WITH_TBLITE
#define WITH_TBLITE 0
#endif
#ifndef WITH_CPCMX
#define WITH_CPCMX 0
#endif
! src/features.F90:30-31
   logical, parameter :: tblite_support = WITH_TBLITE /= 0
   logical, parameter :: cpcmx_support = WITH_CPCMX /= 0
```

★实测（`WITH_TBLITE=OFF` 的构建）：

```
$ /tmp/xtb-static/build/xtb water.xyz --gfn2 --sp --tblite
ERROR STOP
Error termination. Backtrace: ...（gfortran 运行时栈回溯，符号未导出所以是 ???）
-2- Command line argument parsing failed
-1- prog_main_parseArguments: Compiled without support for tblite library
exit=1
```

⇒ 是**干净报错**（不是崩溃），但**不是** `--help` 里能看出来的（help 文本与编译选项无关，见 §3.3）。
`--gfnff` 是**内置**的、不依赖 tblite：★实测我们与参照二进制的 GFN-FF 单点能量**完全相同**：
`TOTAL ENERGY -0.327262664504 Eh`（两者一致）。

### 1.4 为什么 `WITH_TBLITE=OFF` / `WITH_CPCMX=OFF` 是必需的（原始失败证据）

★实测：`-DWITH_CPCMX=ON`（其余同 §1.1）⇒ **configure 直接失败**：

```
$ cmake -S <repo> -B /tmp/xtb-static/full -DWITH_TBLITE=OFF -DWITH_CPCMX=ON -DWITH_TESTS=OFF -DCMAKE_BUILD_TYPE=Release
rc=1
-- Retrieving toml-f from https://github.com/toml-f/toml-f
CMake Error at /tmp/xtb-static/full/_deps/cpcmx-src/config/modules/cpcm-x-utils.cmake:102 (add_library):
  add_library cannot create imported target "toml-f::toml-f" because another
  target with the same name already exists.
Call Stack (most recent call first):
  /tmp/xtb-static/full/_deps/cpcmx-src/config/modules/Findtoml-f.cmake:84 (cpcmx_find_package)
  /tmp/xtb-static/full/_deps/cpcmx-src/CMakeLists.txt:43 (find_package)

CMake Error at .../cpcm-x-utils.cmake:103 (target_link_libraries):
  target_link_libraries can not be used on an ALIAS target.
-- Configuring incomplete, errors occurred!
```

**根因（我读到的事实 + 推断）**：`toml-f` 被 CMake 以 **subproject** 方式引入（它自己的 `CMakeLists.txt` 会
`add_library(toml-f::toml-f ALIAS toml-f)`），而 cpcmx 自带的 `cpcm-x-utils.cmake` 在
「fetch」分支里**不检查 target 是否已存在**就再建一个同名 IMPORTED target。CMake 4.3.2 视为错误。
**这不是我们的代码问题，也不只是 cpcmx 的问题**——见 §6：在 edcfbbe 上游源码上，**同一个错误模式**（只是 target 换成 `mctc-lib::mctc-lib`）
会让 configure 直接失败，哪怕 `WITH_CPCMX=OFF`。

> 我们基座（HEAD = 1779020）的 `cmake/modules/xtb-utils.cmake:19-24` 增加了 `xtb_promote_target` +
> `if(NOT TARGET ...)` 守卫（`xtb-utils.cmake:95-98,122-125`），所以**上游基座自己不再触发**这个错误；
> 但 cpcmx 是第三方仓库，守卫改不到 ⇒ `WITH_CPCMX=OFF` 仍是唯一的低成本出路。
> （`WITH_TBLITE=ON` 需要额外拉取 tblite + dftd4 + multicharge + mstore + json-fortran + toml-f，
> 属于同类风险面；我**没有**实测 `WITH_TBLITE=ON`——见 §7 未验证项。）

### 1.5 编译器与链接链的真相（复核父会话的「混链」判断）

**结论：不是混链。** 证据链：

| 项 | 证据 |
|---|---|
| 实际编译器 | `CMakeCache.txt:114 CMAKE_Fortran_COMPILER:FILEPATH=/usr/bin/gfortran`；`CMakeCache.txt:64 CMAKE_C_COMPILER=/usr/bin/cc` |
| 实际链接命令 | `/tmp/xtb-land/build/CMakeFiles/xtb-exe.dir/link.txt`（★实测，原文） |
| ld 搜索路径 | 二进制**没有 RPATH/RUNPATH**（`readelf -d` 只有 `NEEDED` 条目） |

```
$ cat /tmp/xtb-land/build/CMakeFiles/xtb-exe.dir/link.txt
/usr/bin/gfortran  -fdefault-real-8 -fdefault-double-8 -ffree-line-length-none -fbacktrace -O3
  ...（9 个 prog/*.o）... -o xtb  libxtb.a /usr/lib/x86_64-linux-gnu/libopenblas.so -lm -ldl
  _deps/mctc-lib-build/libmctc-lib.a /usr/lib/gcc/x86_64-linux-gnu/12/libgomp.so
  /usr/lib/x86_64-linux-gnu/libpthread.a
```

⇒ **链接的是一个 GCC 12 的 `libgomp.so`**（`/usr/lib/gcc/x86_64-linux-gnu/12/`），不是 gcc15 的。

那 `ldd` 为什么显示 gcc15？（★实测）

```
$ echo $LD_LIBRARY_PATH
/usr/local/gromacs/lib:/home/owenchan/programs/gcc15/lib64:

$ ldd /tmp/xtb-land/build/xtb
        libgomp.so.1 => /home/owenchan/programs/gcc15/lib64/libgomp.so.1
        libgcc_s.so.1 => /home/owenchan/programs/gcc15/lib64/libgcc_s.so.1
        libquadmath.so.0 => /home/owenchan/programs/gcc15/lib64/libquadmath.so.0

$ env -u LD_LIBRARY_PATH ldd /tmp/xtb-land/build/xtb
        libopenblas.so.0 => /lib/x86_64-linux-gnu/libopenblas.so.0
        libgfortran.so.5 => /lib/x86_64-linux-gnu/libgfortran.so.5
        libgomp.so.1 => /lib/x86_64-linux-gnu/libgomp.so.1
        libgcc_s.so.1 => /lib/x86_64-linux-gnu/libgcc_s.so.1
        libquadmath.so.0 => /lib/x86_64-linux-gnu/libquadmath.so.0
```

即：**`LD_LIBRARY_PATH` 把 gcc15 的 `libgomp/libgcc_s/libquadmath` 顶到了系统库前面**（`libgfortran` 仍是系统的，
因为 gcc15 目录里**没有** libgfortran，见下）。这是**运行时**现象，与「构建」无关。

补充（★实测）：`/home/owenchan/programs/gcc15/bin/` 里**没有 `gfortran`**（只有 gcc/g++/cpp/gcov 等），
`/home/owenchan/programs/gcc15/lib64/` 里**没有 `libgfortran*`**。⇒ gcc15 是**只有 C/C++** 的安装，
不可能被误当成我们的 Fortran 工具链。

**隐患等级**：低但真实。GCC 12 编译的 Fortran 可执行文件在运行时被换用 GCC 15 的 `libgomp/libgcc_s/libquadmath`，
依赖的是 GOMP/GCC ABI 的向后兼容（`GOMP_4.0/5.0`、`GCC_4.x` 版本化符号）。**我没有实测**它是否有害
（未验证：没有跑 ABI 级别的一致性实验）。要消除，只需在运行环境里去掉那段 `LD_LIBRARY_PATH`
或给二进制加 `-Wl,-rpath,/usr/lib/x86_64-linux-gnu`。

**对 AGENTS.md §6「gfortran 12.2.0 派生类型赋值 stride 缺陷」归因的影响：无影响。**
那是**编译期代码生成**缺陷（与运行库无关）。★实测复现（20 行、无 xtb、当前工具链）：

```fortran
program stride
  implicit none
  type :: mol
    character(len=:), allocatable :: sym(:)
  end type mol
  type(mol) :: a, b
  integer :: k
  allocate(character(len=80) :: a%sym(3))
  a%sym(1)='O'; a%sym(2)='H'; a%sym(3)='H'
  b = a
  do k = 1, 3
     write(*,'(a,i0,a,i0,a,i0)') 'b(',k,') byte1=',iachar(b%sym(k)(1:1)),' byte2=',iachar(b%sym(k)(2:2))
  end do
end program stride
```

```
$ gfortran -O3 stride4.f90 -o stride4 && ./stride4
len(a%sym(1)) = 80
len(b%sym(1)) = 80
b(1) byte1=79 byte2=32      ← 'O' 正常
b(2) byte1=0  byte2=0       ← NUL（损坏）
b(3) byte1=0  byte2=0       ← NUL（损坏）

$ gfortran -O0 stride4.f90 -o stride4o && ./stride4o
b(1) byte1=79 byte2=32
b(2) byte1=0  byte2=0       ← -O0 也损坏 ⇒ 前端/代码生成缺陷，与优化档无关
```

用哪个编译器复现的：`gfortran --version` = `GNU Fortran (Debian 12.2.0-14+deb12u1) 12.2.0`（即 `/usr/bin/gfortran`，
与构建用的完全同一个）。带/不带 gcc15 的 `LD_LIBRARY_PATH` 结果一样（与运行库无关，符合「编译期缺陷」判断）。
⇒ **AGENTS.md 的归因成立**，且与「混链」无关。

---

## 2. 依赖闭包

### 2.1 依赖总表

| 依赖 | 必需? | header-only? | 提供者 | 我们当前 | 获取方式 |
|---|---|---|---|---|---|
| **mctc-lib v0.5.1** | **必需** | 否（编译出 `libmctc-lib.a`） | GitHub `grimme-lab/mctc-lib` | ✔ 启用 | `find_package("mctc-lib" REQUIRED)`（`CMakeLists.txt:42-44`）→ `Findmctc-lib.cmake:19-23` → **FetchContent**（`xtb-utils.cmake:109-131`），`GIT_TAG v0.5.1` |
| **test-drive v0.5.0** | 仅测试必需 | 否 | GitHub `fortran-lang/test-drive` | ✔（`WITH_TESTS=ON`） | 同机制（`CMakeLists.txt:66-68`，`Findtest-drive.cmake:68-71`） |
| **tblite v0.6.0** | 可选 | 否 | GitHub `tblite/tblite` | ✘（`WITH_TBLITE=OFF`） | `CMakeLists.txt:46-49` + `Findtblite.cmake:17-20` |
| **cpcmx v1.1.0** | 可选 | 否 | GitHub `grimme-lab/CPCM-X` | ✘（`WITH_CPCMX=OFF`） | `CMakeLists.txt:56-59` + `Findcpcmx.cmake:68-71` |
| **toml-f** | 仅 cpcmx / mctc-lib(WITH_JSON) 需要 | 否 | GitHub `toml-f/toml-f` | ✘ | 由 cpcmx 的 `Findtoml-f.cmake` 拉取；`mctc-lib` 侧由 `WITH_JSON` 门控 |
| **jonquil**（JSON Fortran 库） | 仅 `mctc-lib WITH_JSON=ON` | 否 | — | ✘ | `mctc-lib/CMakeLists.txt:32-33` |
| **LAPACK / BLAS** | **必需** | 否 | 系统 `libopenblas.so` | ✔ | `CMakeLists.txt:83-84`，实测解析为 `/usr/lib/x86_64-linux-gnu/libopenblas.so`（`CMakeCache.txt:42`） |
| **OpenMP** | 可选（默认开） | 否 | GCC 的 `libgomp` | ✔ | `CMakeLists.txt:80-82` |
| **git** | 构建期（版本串） | — | 系统 | ✔（但**取不到值**，见 §3.2） | `cmake/CMakeLists.txt:68` |
| **CMake ≥ 3.17** | **必需** | — | `/home/owenchan/programs/cmake/bin/cmake` (4.3.2) | ✔ | — |
| **Python** | **不需要** | — | — | — | CMake 路径不调用 Python；meson 路径才需要 |
| **Intel / MKL** | 不需要 | — | — | — | 只有参照二进制用了 |

> `mctc-lib` 对 toml-f/jonquil 的依赖是**可选**的：`mctc-lib/CMakeLists.txt:32-34`
> `if(NOT TARGET "jonquild::jonquil" AND WITH_JSON) find_package(...)`，而我们的构建里
> `CMakeCache.txt` 有 `WITH_JSON:BOOL=OFF` ⇒ **不需要 toml-f/jonquil**。这也解释了为什么我们关掉 cpcmx 后
> 整条链只剩一个下载。

### 2.2 「mctc-lib 是 FetchContent 拉 v0.5.1」——★实测确认（并补充细节）

```
$ git -C /tmp/xtb-land/build/_deps/mctc-lib-src remote -v
origin  https://github.com/grimme-lab/mctc-lib (fetch)
$ git -C /tmp/xtb-land/build/_deps/mctc-lib-src describe --tags
v0.5.1
$ git -C /tmp/xtb-land/build/_deps/mctc-lib-src log --oneline -1
aa89d4b Bump version to 0.5.1 (#104)
```

调用点：`CMakeLists.txt:42-44` → `Findmctc-lib.cmake:28` → `xtb-utils.cmake:109-131`：

```cmake
# cmake/modules/xtb-utils.cmake:78-82（subproject 分支）
elseif("${method}" STREQUAL "subproject")
   if(NOT DEFINED "${_pkg_uc}_SUBPROJECT")
      set("${_pkg_uc}_SUBPROJECT" "subprojects/${package}")
   ...
# cmake/modules/xtb-utils.cmake:109-120（fetch 分支）
elseif("${method}" STREQUAL "fetch")
   message(STATUS "Retrieving ${package} from ${url}")
   FetchContent_Declare("${_pkg_lc}" GIT_REPOSITORY "${url}" GIT_TAG "${rev}")
   FetchContent_MakeAvailable("${_pkg_lc}")
```

查找顺序（`Findmctc-lib.cmake:22-24`）是 `cmake → pkgconf → subproject → fetch`。
本机既没有系统 mctc-lib（`mctc-lib_DIR-NOTFOUND`，`CMakeCache.txt:436`）也没有 pkg-config 模块，
`subprojects/mctc-lib/` 不存在，⇒ 落到 **fetch**。**父会话的结论正确。**

### 2.3 能不能构建一个「不下载任何东西」的版本？——★实测两条路线都通

**路线 A：`FETCHCONTENT_SOURCE_DIR_<NAME>`（CMake 官方离线开关）**

```bash
cmake -S <repo> -B /tmp/xtb-base/build \
  -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DCMAKE_BUILD_TYPE=Release \
  -DFETCHCONTENT_SOURCE_DIR_MCTC-LIB=/tmp/xtb-land/build/_deps/mctc-lib-src \
  -DFETCHCONTENT_SOURCE_DIR_TEST-DRIVE=/tmp/xtb-land/build/_deps/test-drive-src
# ⇒ rc=0；构建目录里只有 _deps/*-build，没有 _deps/*-src ⇒ 没有发生克隆
$ ls /tmp/xtb-base/build/_deps
mctc-lib-build  test-drive-build
```

**路线 B：本地 vendoring（把 mctc-lib 放进 `subprojects/`）**

```bash
# 在仓库副本里（不动真仓库）：
mkdir -p subprojects && ln -s <mctc-lib-v0.5.1-src> subprojects/mctc-lib
cmake -S . -B build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=OFF \
      -DCMAKE_BUILD_TYPE=Release -DMCTCLIB_FIND_METHOD=subproject
```

★实测输出：

```
-- Include mctc-lib from subprojects/mctc-lib
-- Configuring done (14.3s)
```

并且完整构建成功：`real 0m33.996s`，产出 `xtb`（8 671 032 B）。

**结论**：
- **最小必需下载集**（现状）= **只有 `mctc-lib`**（`WITH_TESTS=OFF` 时连 test-drive 都不用；
  对比 `CMakeCache.txt:454 test-drive_SOURCE_DIR:.../_deps/test-drive-src` 只在 `WITH_TESTS=ON` 时出现）。
- **可以做到零下载**，代价是二选一：(A) 配置时多给两个 `-D` 指向已解包的依赖；(B) 把 mctc-lib 源码
  **vendor 进仓库**（约 1 个 `git clone` 体量，`subprojects/mctc-lib/`，约 2–3 MB 源码），
  配置时给 `-DMCTCLIB_FIND_METHOD=subproject`。两条路线都**不需要网络**，都不需要改一行源码。
- vendoring 的成本：仓库体积增加；上游升级要手动同步；`subprojects/.gitignore` 目前会忽略该目录
  （`subprojects/.gitignore`，需改成不忽略或换目录名）。

---

## 3. 与参照二进制的对比

### 3.1 参照二进制是怎么编出来的（★实测证据 + 推断）

基础事实（复核，★实测）：

```
$ file /home/owenchan/programs/xtb/bin/xtb
ELF 64-bit LSB executable, x86-64, statically linked, BuildID=..., not stripped
$ ls -la → 63 253 248 B
$ ldd → not a dynamic executable
$ --version → xtb version 6.7.1 (edcfbbe) compiled by 'albert@albert-system' on 2024-07-22
```

**(a) 它用 meson 构建 —— 两条独立的格式指纹（★实测）**

| 指纹 | 参照二进制 | 我们的 CMake 构建 | 出处 |
|---|---|---|---|
| `compiled by '...'` | `'albert@albert-system'`（**user@hostname**） | `'@Linux'`（**`$USERNAME` 为空 + `CMAKE_HOST_SYSTEM_NAME`**） | `assets/templates/version.f90:3`；CMake 侧 `cmake/CMakeLists.txt:77-78`；meson 侧 `meson.build:68-69`（`getpass.getuser()` + `socket.gethostname()`） |
| `on YYYY-MM-DD` | `2024-07-22`（**短横线**） | `2026/10/03`（**斜杠**） | CMake：`cmake/CMakeLists.txt:76` `"%Y/%m/%d"`；meson：`meson.build:67` `"%Y-%m-%d"` |

两条指纹同时成立，基本排除 CMake。⇒ **参照二进制 = meson 构建**。

**(b) 它用 Intel 编译器 + MKL + Intel OpenMP（★实测 strings）**

```
$ strings -a ref | grep -c 'GNU Fortran'      → 0
$ strings -a ref | grep -ci openblas          → 0
$ strings -a ref | grep -oE 'libiomp5|libmkl_[a-z_]+\.so|kmp_version' | sort -u | head
libiomp5
kmp_version
libmkl_avx.so
libmkl_def.so
...
$ strings -a ref | grep -oE 'Intel\(R\) (C|C\+\+|Fortran)[^:]{0,60}' | sort -u | head -1
Intel(R) C++ Intel(R) 64 Compiler ... Version 19.1.3.304 Build 20200925_000000
$ strings -a ref | grep -i 'Intel MKL FATAL ERROR' → 有
```

⇒ 静态链入了 `libiomp5.a`（Intel OpenMP）+ MKL。**没有** GNU Fortran 字样、**没有** OpenBLAS 字样。

**(c) 它是静态链接的（★实测）**：`file` 报 statically linked、`ldd` 报 not a dynamic executable。

**(d) 上游的静态构建配方（★实测，就是 CI 里那一条）**

`.github/workflows/fortran-build.yml:267-286`：

```yaml
- name: Configure meson build
  run: >
    meson setup ${{ env.BUILD_DIR }} --prefix=/ --libdir=lib
    -Dfortran_link_args="-lifcoremt -static"
    -Ddefault_library=static
    -Dlapack=mkl
...
- name: Install package / Upload binary  → xtb-bleed-linux-x86_64.tar.xz
```

`README.md:25` 亦写：「**Statically linked binaries (Intel Compiler)** can be found at the latest release page」。

**(e) 源码状态：edcfbbe ≠ 我们的基座（★实测，这条很重要）**

```
$ git cat-file -t edcfbbe → commit
$ git show -s --format='%ci %h %s' edcfbbe
2024-07-02 14:57:19 +0200 edcfbbe Fixes #1054 by ensuring thread savety of hessian calculations with GFN-FF (#1061)
$ git merge-base --is-ancestor edcfbbe HEAD → YES
$ git rev-list --count edcfbbe..HEAD → 156
$ git describe --tags edcfbbe → v6.7.0-18-gedcfbbe
$ git describe --tags HEAD     → bleed-7-g24c069f   （tag `bleed` == 1779020，即 landscape 7 个提交的父节点）
```

⇒ 参照二进制来自 **edcfbbe**；我们的基座是 **1779020 (=tag `bleed`)**，比它**新 156 个提交**，再加 7 个 landscape 提交。
**版本号两边都显示 6.7.1**，但 `meson.build`/`CMakeLists.txt` 在 edcfbbe 上写的是 `6.7.0`
（`/tmp/xtb-base/meson.build:22`、`/tmp/xtb-base/CMakeLists.txt:29`），而 `v6.7.1` tag 是 edcfbbe 之后的
提交 `26b2801 "push to v6.7.1"`（★实测）。二进制日期 2024-07-22 恰在 tag 前一天
⇒ **推断**：维护者在 edcfbbe 的工作树上先把版本号改成 6.7.1（未提交）、构建发布二进制，次日才提交 tag。
（这条是**推断**，我无法从二进制证明工作树是否有其它未提交改动——见 §3.4 的一个反例线索。）

### 3.2 构建差异

| 维度 | 参照二进制 | 我们的构建 |
|---|---|---|
| 构建系统 | **meson**（见 §3.1a） | **CMake**（`CMakeLists.txt`）；meson 未安装、未使用 |
| 编译器 | Intel（ifort/icx 系）+ Intel OpenMP | **gfortran 12.2.0** + GCC libgomp |
| 线性代数 | **MKL**（静态） | 系统 **OpenBLAS**（动态；`CMakeCache.txt:42`） |
| 链接 | **全静态**（63.2 MB） | 动态（8.7 MB）；我们的全静态版本 37.0 MB（§4.3） |
| 优化档 | 未知（Intel；README 的 meson 配方是 `--buildtype release --optimization 2`，**未验证**） | `-O3`（`CMAKE_Fortran_FLAGS_RELEASE:-O3`） |
| 方言 flags | Intel：`-axAVX2 -r8 -traceback`（`cmake/CMakeLists.txt:52-54`）/ meson 侧未知 | `-fdefault-real-8 -fdefault-double-8 -ffree-line-length-none -fbacktrace` |
| `WITH_TBLITE` | **ON**（`--tblite` 可用：★实测 `--tblite` 给出 `TOTAL ENERGY -5.070369821863 Eh`） | **OFF**（★实测干净报错） |
| `WITH_CPCMX` | 未知（推断 ON，因为 release 一般全开；**未验证**） | **OFF** |
| 版本串 | `6.7.1 (edcfbbe) albert@albert-system 2024-07-22` | `6.7.1 (unknown-commit) '@Linux' 2026/10/03` |

**`unknown-commit` 的根因（★实测，一个小缺陷）**：`cmake/CMakeLists.txt:68`：

```cmake
execute_process(COMMAND git rev-parse HEAD
  RESULT_VARIABLE git_return
  OUTPUT_VARIABLE commit)
```

没有 `WORKING_DIRECTORY`，于是它在**二进制目录**（`/tmp/xtb-land/build`，不是 git 仓库）里执行：

```
$ grep -n 'fatal' /tmp/xtb-static/configure.log
11:fatal: not a git repository (or any of the parent directories): .git
```

⇒ `git_return != 0` ⇒ `commit = "unknown-commit"`。meson 侧没这个问题（`meson.build:46` 的
`run_command(git, ...)` 默认在源码目录跑），所以参照二进制能带上 `edcfbbe`。
**建议**：加 `WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"` 即可（一处 1 行改动，本次未改）。

### 3.3 功能差异 —— 必须把「源码差异」和「构建选项差异」分开

★实测：`--help` 行数 **参照 241 行 / 我们 698 行**。把 `--help` 的选项名做集合差
（`diff <(grep -oE '"--?[a-zA-Z0-9-]+' src/xhelp.f90) ...`，对照组用 `git archive edcfbbe` 解出的源码树）：

**(A) 纯粹因为我们更新了 156 个上传提交而多出来的选项**（与构建选项无关）：

```
--cycles  --efield  --gb  --gbe  --imagmax  --imagmin  --ithr  --o1nh
--ceh 的签名也变了：edcfbbe 是 `--ceh`，HEAD 是 `--ceh <grad> [REAL]`
```

**(B) landscape 套件带来的选项**（我们自己的新增，★实测 `--help` 集合差共 **117** 个）：

```
--lopt*  (5)   --lscan* (18)  --lvib* (11)  --lts* (54)  --lirc* (28)  --ljson (1)
```

**(C) 构建选项差异（tblite/CPCM-X）**：**看不出**。因为 `xhelp.f90` 是**静态文本**，
`--help` 不随 `WITH_TBLITE`/`WITH_CPCMX` 变化。实测两者 `--help` 都列出 `--tblite`、`--gbe`、`--gb`……，
但我们的二进制在 `--tblite` 上直接报错（§1.3）。**这是一个真实的可用性陷坑**：帮助文本误导用户。

**(D) 我们**没有**丢掉参照二进制有的任何选项**（除 (A)(B) 之外，`diff` 无其它差异）。

### 3.4 数值等价性 —— ★实测（本报告最重要的实验）

**实验 A（同一源码，不同编译器/BLAS；最干净的对照）**
把 edcfbbe 的源码树解到 `/tmp/xtb-base`（`git archive`，只读地取，不动仓库），
用**我们的工具链**（gfortran 12.2.0 + OpenBLAS + CMake）构建，与参照二进制跑同一输入：

```bash
printf '3\nwater\nO 0.0 0.0 0.0\nH 0.0 0.757 0.586\nH 0.0 -0.757 0.586\n' > water.xyz
OMP_NUM_THREADS=1 XTBPATH=<repo> <bin> water.xyz --gfn2 --hess
```

> ⚠️ edcfbbe 源码用 gfortran **12.2.0 直接编不过**：`src/gfnff/gfnff_eg.f90:4049`
> `real(wp), intent(in) :: rTrans( 3, product(2*ewaldCutD+1))` —— gfortran 报
> `Error: 'array' argument of 'product' intrinsic at (1) must be an array`。
> 我 20 行最小复现确认这是 gfortran 前端对 `2*array+1` 数组性推导的缺陷（与优化档无关）。
> 上游用 commit `42d6c80`（"change product to hardcoded number fixes #1012 fixes #998 fixes #997 (#1051)"，
> 2024-08-09，即 edcfbbe 之后）改成 `rTrans(:, :)` 修掉了。为了做对照，我把**上游那条修复原样**打在
> `/tmp/xtb-base` 副本上（**只改这一处，且与上游 diff 一致**）。这本身就是一条对用户问题有用的结论：
> **v6.7.1 发布源码在 gfortran 12.2.0 下编译不通过；我们现在的基座能过。**

| 文件 | 参照二进制（Intel/MKL/meson/静态） vs 我们的 edcfbbe 构建（gfortran/OpenBLAS/CMake/-O0） |
|---|---|
| `hessian` | **max diff = 0.0 ⇒ 逐位完全相同**（矩阵最大元素 0.5981241368） |
| `charges` | 字节相同（`diff` 无输出） |
| `vibspectrum` | 字节相同 |
| `g98.out` | 只有两类差异：(i) 第 17 行行尾空格；(ii) 打印的**法向模式向量整体取反**（±号是特征向量的固有自由度） |
| `g98.out` 频率 | `1557.4148  3677.8357  3684.0117` —— **完全相同** |
| `g98.out` Red. masses | `2.1190 2.1028 1.5744` —— **完全相同** |
| `wbo` | 末位差 ~1e-15 量级（浮点归约顺序） |

**实验 B（我们 HEAD 的构建 vs 参照二进制）**

| 量 | 参照 | 我们（HEAD，-O3，动态） | 差 |
|---|---|---|---|
| GFN2 单点总能 | `-5.070369819160 Eh` | `-5.070369819160 Eh` | **打印精度内相同** |
| HOMO–LUMO gap | `14.648806958949 eV` | `14.648813364946 eV` | `6.4e-6 eV` |
| Fermi | `-0.1783382 Eh` | `-0.1783384 Eh` | `2e-7 Eh` |
| 频率（Hz 域，g98.out） | `1557.4148 3677.8357 3684.0117` | 同左 | 0 |
| Hessian 矩阵 | — | — | `max|Δ| = 3.13e-6`（相对 ~5e-6，矩阵 max 0.598） |
| `charges` | — | 同左 | 字节相同 |
| `wbo` | `0.920186989431188` | `0.92018698964884216` | ~2e-10 |
| `g98.out` Red. masses | `2.1190 2.1028 1.5744` | `1.0832 1.0820 1.0449` | **约 2 倍差异** |

**Red. masses 那 2 倍差异的来源已定位（★实测）**：它是**上游源码修复**，不是编译器问题。
edcfbbe..HEAD 之间 `src/hessian.F90` 有提交 `a91c8ac "Fix reduced mass calculation (#1237)"`
（同批还有 `02289da Remove molecular rotation before numerical Hessian (#1426)`、
`bad1639 Fix monoatomic hessian initialization (#1421)`、`ca631a3 Fix hessian with fixed atoms (#1175)`）。
实验 A 证明：**同一份 edcfbbe 源码**下，我们的 gfortran 构建和参照二进制给出**完全一样**的
`2.1190 2.1028 1.5744`（即参照二进制带着这个「旧算法」）。我们 HEAD 给出的是修好的值。
⇒ **这一处差异是我们的源码更新所致，方向是「我们更正确」。**

**等价性结论**：
- **相同源码 + 相同构建选项**下，`gfortran 12.2.0 + OpenBLAS` 与 `Intel + MKL + meson + 静态`
  在本任务（GFN2 单点 / Hessian / 频率 / 电荷 / WBO）上**数值等价**（Hessian 逐位相同）。
- 二者在**打印层面**的差异 < 1e-5 相对量级；容差来源是浮点归约顺序 + 特征向量符号约定，
  由 `OMP_NUM_THREADS=1` 与相同 BLAS 可以压到 0（实验 A 就是 0）。
- 现状下二者**不完全等价**的原因**不是编译器，而是 (1) 源码状态差 156 个提交、(2) `WITH_TBLITE` 开关**、
  (3) `unknown-commit` 版本串。数值上在共有功能域内**等价**。

### 3.5 关于「除了硬编码的 params」

参数文件（`param_gfn2-xtb.txt` 等）是**运行时**从 `XTBPATH` 读的纯文本（`CMakeLists.txt:274-284` 安装规则），
**不是硬编码**。两者用同一份参数文件即可，不构成差异。真正「硬编码」的是
`src/**` 里的常量与 `assets/templates/version.f90` 的版本串。

---

## 4. 「只用 gcc/gfortran」的三条路线

### (a) 保持 CMake，把依赖闭包降到最小 —— **推荐**

命令（★实测可用）：

```bash
cmake -S <repo> -B build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF [-DWITH_TESTS=OFF] -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

| 项 | 评估 |
|---|---|
| 工作量 | **0**（现状就是这条） |
| 可维护性 | 最高：上游两条链都在维护 CMake；我们的 `src/landscape/CMakeLists.txt` 已就位 |
| 风险 | 低。`WITH_CPCMX=ON` 目前 configure 必失败（§1.4） |
| 功能代价 | 无 tblite 后端（`--tblite`、tblite 侧的 `--efield`、`--gbe`/`--gb`、`--spinpol` 走 tblite 的部分、DIPRO/PTB 的 tblite 分支）；无 CPCM-X 溶剂模型。**GFN0/1/2、GFN-FF、优化、扫描、Hessian/频率、TS、IRC、thermo 全部不受影响**（★实测 `--gfnff` 与参照二进制同值） |
| 还能更小？ | `WITH_TESTS=OFF` 去掉 test-drive 拉取；再用 §2.3 的离线开关就**零下载**。已经到极限——`mctc-lib` 无法移除（`src/mctc/*` 与 `xtb_mctc_*` 是内建层，但 `mctc-lib` 提供 `mctc_io/环境变量/BLAS-LAPACK 包装`，见 `CMakeLists.txt:115-116`） |

### (b) 纯 Makefile / 一条 gfortran 命令 —— 可行但成本高

**需要什么（★实测的全部硬数据）**：

- 源文件清单：**392 个**编译单元进 `libxtb`（`make` 侧：`src/CMakeLists.txt` + 22 个子目录 `add_subdirectory`），
  扩展名分布 ★实测：`333 .f90 / 49 .F90 / 8 .f / 2 .c`；程序侧另 **9 个**（全在 `src/prog/`）。
  清单可以**自动生成**（我验证过的方法，可直接复跑）：

  ```bash
  # 从 CMake 已有产物里抽（最稳）
  grep -oE '/abs/repo/[^ ]+\.(f90|F90|f|c)' build/CMakeFiles/xtb-object.dir/build.make | sort -u
  # ⇒ 392 行；程序侧同样从 CMakeFiles/xtb-exe.dir/build.make 抽 ⇒ 9 行
  ```

- **模块顺序依赖**（真问题）：构建目录里产出 **343 个 `.mod`**。★实测：**gfortran 自己能生成依赖**，
  不需要 `makedepf90`：

  ```bash
  $ gfortran -cpp -MM -I build/include -I include src/landscape/optimize/lbfgs.f90
  xtb_landscape_lbfgs.mod lbfgs.o: src/landscape/optimize/lbfgs.f90 \
   /usr/include/finclude/x86_64-linux-gnu/math-vector-fortran.h \
   xtb_mctc_accuracy.mod
  ```

  我对着 392 个源文件跑了一轮：**385/390 个 Fortran 源成功生成依赖**（先只给 `build/include` 时 375/390；
  再加上 mctc-lib 的 `include` 后剩 5 个，属于 Fortran 依赖收集器典型的「第二轮才收敛」情形），
  **共抽取 2882 条 `.mod` 依赖边**。⇒ 手写 Makefile 的**依赖图可以全自动生成**，
  但**必须**写一个生成器（递归 make + `-MM` 两轮），因为坦率地说 343 个 module 没人能手排。

- 编译 flags：`-fdefault-real-8 -fdefault-double-8 -ffree-line-length-none -fbacktrace -O2/-O3`
  （`cmake/CMakeLists.txt:50`）。
- 链接：`gfortran ... -o xtb libxtb.a -lopenblas -lm -ldl -fopenmp`（来自 `link.txt`，★实测原文见 §1.5）。
- **上游历史上有没有 Makefile？** ★实测：**没有**。

  ```
  $ git log --all --oneline -- Makefile Makefile.am config.mk   → （空）
  $ git ls-files | grep -iE '^Makefile|Makefile$|\.mk$'          → man/Makefile（仅文档）
  ```

  ⇒ 手写 Makefile 是**从零开始**，没有历史可抄。

| 项 | 评估 |
|---|---|
| 工作量 | **高**：源清单生成器（392+9）+ 模块依赖生成器（343 module / 2882 边）+ flags/链接 + 增量构建 + 每次新增源文件都要重新生成 |
| 可维护性 | **低**：`src/landscape` 还在演进（AGENTS §7 要求新文件同时登记 `CMakeLists.txt` **和** `meson.build`，说明已经是双构建系统维护负担；再加第三个会翻倍） |
| 风险 | 中高：增量构建正确性、`WITH_TBLITE`/`WITH_CPCMX` 条件编译、模块目录同步，全部要自己保证 |
| 是否真能「只有 gfortran」 | **能**：生成器只用 `gfortran -cpp -MM` + `make`。但产出的是一个**自制构建系统**，长期看比 CMake 更贵 |

### (c) 全静态链接（对齐参照二进制的形态） —— ★实测成功

第一步（原样 `-static`）会**失败**，但失败点很有信息量（★实测原文）：

```
$ cmake ... -DBLA_STATIC=ON -DCMAKE_EXE_LINKER_FLAGS="-static"
[ 49%] Linking Fortran executable mctc-convert
/usr/bin/ld: attempted static link of dynamic object `/usr/lib/gcc/x86_64-linux-gnu/12/libgomp.so'
collect2: error: ld returned 1 exit status
```

原因：`OpenMP_gomp_LIBRARY` 被 CMake 解析成 `.so`，显式 `.so` 路径使 `-static` 失效。
把该 cache 变量指向静态库即可：

```bash
cmake -S <repo> -B /tmp/xtb-static/static2 \
  -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=OFF -DCMAKE_BUILD_TYPE=Release \
  -DBLA_STATIC=ON -DCMAKE_EXE_LINKER_FLAGS="-static" \
  -DOpenMP_gomp_LIBRARY=/usr/lib/gcc/x86_64-linux-gnu/12/libgomp.a
cmake --build /tmp/xtb-static/static2 -j8            # 整体 all 会失败（见下）
cmake --build /tmp/xtb-static/static2 --target xtb-exe -j8   # ✔ 成功
```

第二次失败（预期之内，且可绕过）：

```
/usr/bin/ld: /usr/lib/gcc/x86_64-linux-gnu/12/libgomp.a(team.o): relocation R_X86_64_TPOFF32 against
hidden symbol `gomp_tls_data' can not be used when making a shared object
gmake[2]: *** [CMakeFiles/lib-xtb-shared.dir/build.make:874: libxtb.so.6.7.1] Error 1
```

⇒ **不能把静态 libgomp 链进 `.so`**。CMake 里没有「只出可执行文件、不出共享库」的开关
（`CMakeLists.txt:186-221` 无条件建共享库），所以只能 `--target xtb-exe`。

结果（★实测）：

```
$ file /tmp/xtb-static/static2/xtb
ELF 64-bit LSB executable, x86-64, statically linked, ... not stripped
$ ls -la → 37 015 096 B
$ ldd   → not a dynamic executable
$ --version → * xtb version 6.7.1 (unknown-commit) compiled by '@Linux' on 2026/10/03
$ --help | wc -l → 698          # 功能与动态版一致
```

唯一的链接期告警（来自 glibc，属预期）：

```
/usr/bin/ld: /usr/lib/gcc/x86_64-linux-gnu/12/libgomp.a(target.o): in function `gomp_target_init.part.0':
(.text+0x3bd): warning: Using 'dlopen' in statically linked applications requires at runtime
the shared libraries from the glibc version used for linking
```

**正确性验证（★实测）**：静态构建与动态构建跑同一 `--hess`：

- `diff ours/vibspectrum stat/vibspectrum` → **无差异**（rc=0）
- `hessian` max diff = **0.0**

**与参照二进制对比**：都是「statically linked」，但参照 63.2 MB（含 MKL + libiomp5）vs 我们 37.0 MB（含 OpenBLAS + libgomp）。
体积差就是 MKL 的体量。**形态一致，内容不同**——这是可接受的：数值上已经证明等价（§3.4 实验 A 在动态下就是 0，
静态与动态之间也是 0）。

| 项 | 评估 |
|---|---|
| 工作量 | 低（3 个 `-D` + `--target xtb-exe`），★实测 32 s 构建 |
| 可维护性 | 中：`OpenMP_gomp_LIBRARY` 是**平台相关**的绝对路径（Debian 12 特有），换机器要改；`libxtb.so` 的静态冲突永远存在，必须用 `--target` |
| 风险 | 低-中：glibc 静态告警（`dlopen`/NSS）意味着**跨机器移植性其实并不会因静态化而变好**（这正是 glibc 官方不建议全静态的原因）。真正的「单文件分发」诉求，用**动态 + 打包**更稳 |
| 额外收益 | 去掉对 `LD_LIBRARY_PATH` 的敏感性（§1.5 的 gcc15 假象会一并消失） |

### 4.4 三条路线之外的第 4 条：**优化档**

★实测（见 §0.6 / §5 实验 6）：`gfortran 12.2.0` + `-O3` 在 **edcfbbe 源码**上给出**错误** Hessian，
`-O0/-O1/-O2` 全部正确（且与 Intel 参照逐位一致）。我们的 HEAD 在 `-O3` 下**目前**正确。
鉴于：
- CMake 默认 `Release = -O3`（`CMakeCache.txt:134`），而我们的常规构建显式用了 `Release`；
- `RelWithDebInfo = -O2 -g`（`CMakeCache.txt:137`），是上游 CMake 的**默认档**（`cmake/CMakeLists.txt:25-35`）；
- `-O3` 的收益在 xtb 这种以 BLAS 为主的热点上通常很小；

建议把构建档位保守化为 **`-O2`**（即 `RelWithDebInfo` 或显式 `-DCMAKE_Fortran_FLAGS_RELEASE=-O2`）。
**这是我在本次调查里唯一建议动的「构建配置」项**，而且它不改变任何产品行为。

---

## 5. 实测清单（每一条都可复跑）

| # | 实验 | 命令（要点） | 结果 | 产物/日志 |
|---|---|---|---|---|
| 1 | 最小依赖配置+构建 | `cmake -S <repo> -B /tmp/xtb-static/build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=OFF -DCMAKE_BUILD_TYPE=Release` + `--build -j8` | ✔ rc=0；configure 22 s、build 36 s；产出 xtb + libxtb.a + libxtb.so | `/tmp/xtb-static/{configure.log,build.log}` |
| 2 | 全静态尝试（原样） | 同 1 + `-DBLA_STATIC=ON -DCMAKE_EXE_LINKER_FLAGS=-static` | ✘ `attempted static link of dynamic object .../12/libgomp.so` | `/tmp/xtb-static/static-build.log:82` |
| 3 | 全静态尝试（修正后） | 见 §4(c) | ✔ `--target xtb-exe` 成功；`file` = **statically linked**，37.0 MB；`.so` 目标仍失败（libgomp.a + shared 冲突） | `/tmp/xtb-static/static2/xtb` |
| 4 | 源清单/依赖抽取 | `grep -oE '\.(f90\|F90\|f\|c)' build.make`；`gfortran -cpp -MM` 循环 | ✔ 392+9 文件；343 `.mod`；385/390 生成成功；2882 依赖边 | `/tmp/xtb-static/lib_sources.txt`、`/tmp/xtb-static/deps.mk` |
| 5 | 数值比对（同源码） | edcfbbe 树 + gfortran(-O0) vs 参照二进制，`--gfn2 --hess` | ✔ `hessian` **逐位相同**；`charges`/`vibspectrum` 字节相同；频率相同 | `/tmp/xtb-cmp/{ref,base_o0}/` |
| 6 | 数值比对（我们 HEAD） | 三个二进制 × `--sp` / `--hess` | ✔ 总能打印精度内相同；Hessian max diff 3.13e-6 | `/tmp/xtb-cmp/{ref,ours,stat}/` |
| 7 | **`-O3` 异常** | edcfbbe 树分别用 `-O0/-O1/-O2/-O3/-O3 -fno-tree-vectorize` 构建，跑 `--hess` | `-O3` → `-931.5938 3329.7753 3345.9421`（**错**）；其余 → `1557.4148 3677.8357 3684.0117`（= 参照） | `/tmp/xtb-cmp/{base_o0,hO1,hO2,base,hn}/` |
| 8 | stride 缺陷最小复现 | 20 行 `character(len=:),allocatable::sym(:)` 派生类型整体赋值 | ✔ `b%sym(2:3)` 首字节 = 0（NUL），`len` 仍为 80，`-O0`/`-O3` 都相同 | `/tmp/xtb-static/stride/stride4.f90` |
| 9 | 离线构建（A：FETCHCONTENT_SOURCE_DIR） | 见 §2.3 | ✔ 无 `_deps/*-src` ⇒ 未下载 | `/tmp/xtb-base/configure2.log` |
| 10 | 离线构建（B：vendoring `subprojects/mctc-lib`） | 见 §2.3 | ✔ `Include mctc-lib from subprojects/mctc-lib`；构建 34 s | `/tmp/xtb-vendor/` |
| 11 | `WITH_CPCMX=ON` 失败复现 | 见 §1.4 | ✘ configure rc=1，`toml-f::toml-f` target 重名 | `/tmp/xtb-static/full-configure.log` |
| 12 | 混链复核 | `ldd`（有/无 `LD_LIBRARY_PATH`）、`link.txt`、`CMakeCache.txt` | ✔ 构建只用 gcc12；gcc15 仅由 `LD_LIBRARY_PATH` 在运行时介入 | §1.5 原文 |
| 13 | 参照二进制来源 | `file` / `ldd` / `strings` / `--version` / `git describe` | ✔ meson + Intel + MKL + 静态 + edcfbbe | §3.1 |

**未实测（明确列出）**：
- `WITH_TBLITE=ON` 的 configure/build（需拉 tblite + dft4 + multicharge + mstore + jonquil，耗时与风险未评估）；
  推断它会因为同一类 target 重名问题或依赖链而失败或很慢——**这只是推断**。
- 参照二进制的 Intel 优化档（无法从二进制读出）。
- 参照二进制是否 `WITH_CPCMX=ON`（未验证）。
- 大小/内存/性能对比（未测；上游与本项目的既有基准不覆盖）。
- gcc15 运行库替换是否有害（未做 ABI 级别实验）。
- edcfbbe `-O3` 异常的**机制**（未定位；已排除 `-fno-tree-vectorize`）。

---

## 6. 反证：用户/父会话的前提哪些是错的

### 6.1 ✘ 「meson 在阻碍我们 / 目标是『不再需要 meson』」——**前提错误**

- 我们的构建一直是 **CMake**：`CMakeLists.txt` / `cmake/**` 里 **0 处 meson 引用**（唯一一处是
  `test/unit/CMakeLists.txt:616` 的注释，讲的是「meson 构建下的测试名」）。
- `meson`/`ninja` **本机没装**（`which meson ninja` → 空），历史上也没用过。
- `meson.build` / `meson_options.txt` / `subprojects/*.wrap` 是**上游并行提供的第二条构建路径**
  （`README.md:31` 「This projects supports two build systems, meson and CMake」）。
- ⇒ **「不再需要 meson」现状已满足**。**唯一真实成本**是：我们的 `src/landscape/` 必须同时登记
  `CMakeLists.txt` **和** `meson.build`（AGENTS §7 的手工同步要求）。如果目标是「少一个构建系统」，
  正确的动作是**删掉 landscape 的 meson 登记 / 或上游的 meson.build**，而不是「去掉 meson 依赖」。

### 6.2 △ 「只需要使用 gcc/gfortran」——**编译器层面已满足；真正缺的是另外两样**

| 层面 | 现状 | 缺什么 |
|---|---|---|
| 编译器 | ✔ 只用 `gfortran 12.2.0`（`CMakeCache.txt:114`） | 什么都不缺 |
| 构建工具 | ✘ 用 `CMake 4.3.2`（独立于编译器） | 若要「只有 gfortran」⇒ 必须换成 Makefile/脚本（§4b，工作量高、上游从无先例） |
| 依赖获取 | ✘ `mctc-lib` 从 GitHub **克隆** | 离线开关（`FETCHCONTENT_SOURCE_DIR_*`）或 vendoring（§2.3，★实测两条都通） |
| 可选依赖 | ✘ 默认 `WITH_TBLITE=ON`/`WITH_CPCMX=ON` 会拉 4–6 个仓库，其中 cpcmx 目前必失败 | 必须显式 `-DWITH_TBLITE=OFF -DWITH_CPCMX=OFF`（★实测证据见 §1.4） |

⇒ 「只缺 gcc/gfortran」这个说法**不准确**：编译器早就够了，真正要处理的是**构建工具**与**依赖获取**两件事。

### 6.3 ✘ 「编译器与运行库疑似来自两套工具链」——**是 `LD_LIBRARY_PATH` 造成的运行时假象**（★实测，§1.5）

- 链接命令里是 `/usr/bin/gfortran` + `/usr/lib/gcc/x86_64-linux-gnu/12/libgomp.so`。
- gcc15 目录**没有 gfortran、没有 libgfortran**。
- `env -u LD_LIBRARY_PATH ldd` 全部解析到系统库。
- 它**不影响** AGENTS §6 的 stride 缺陷归因（那是编译期缺陷，★实测已复现）。

### 6.4 △ 「编译出的结果是否类似于参照二进制（除了硬编码 params）」

需要拆成三问，答案不同：

1. **数值上是否等价？** ✔ **是**（同一源码 + 同选项下 Hessian **逐位相同**，§3.4 实验 A）。
2. **功能上是否等价？** △ **现状不等价**，但不是「硬编码 params」的问题，而是
   (i) **源码差 156 个提交**（`--efield/--gb/--gbe/--imagmax/--imagmin/--ithr/--o1nh/--cycles/--ceh <grad>` 等是上游新增）；
   (ii) **`WITH_TBLITE=OFF`**（`--tblite` 直接报错；`--help` 看不出来）；
   (iii) 我们**多**了整套 landscape 选项（117 个）。
   参数文件是**运行时**从 `XTBPATH` 读的文本（`CMakeLists.txt:274-284`），**不是硬编码**，不构成差异。
3. **构建形态上是否等价？** ✘ 不等价且**不必要**：参照是 Intel/MKL/meson/**静态**；我们是 gfortran/OpenBLAS/CMake/动态。
   想要「形态也一致」就做 §4(c)，★实测**做得到**（37.0 MB 全静态，数值与动态版逐位相同）。

### 6.5 ✔ 「`WITH_CPCMX=OFF` 是必需的」——**成立**（★实测原文见 §1.4）

但要补一句：根因在 **cpcmx 自带的 CMake 工具模块**（第三方仓库），不在 xtb 也不在我们的代码；
而且**同一类错误在 edcfbbe 上游源码上连 mctc-lib 都会触发**（`xtb-utils.cmake` 无条件
`add_library(mctc-lib::mctc-lib INTERFACE IMPORTED)`，★实测 configure rc=1：
`add_library cannot create imported target "mctc-lib::mctc-lib" because another target with the same name already exists`）。
我们的基座已经用 `if(NOT TARGET ...)` 修掉了这一处。

### 6.6 补充：一条「v6.7.1 源码 gfortran 编不过」的事实

edcfbbe 的 `src/gfnff/gfnff_eg.f90:4049` 用 `product(2*ewaldCutD+1)`（`ewaldCutD(3)` 是参数数组）做
假元维度声明，**gfortran 12.2.0 报错**（与优化档无关），上游 2024-08-09 用
`42d6c80 "change product to hardcoded number fixes #1012 fixes #998 fixes #997 (#1051)"` 修成 `rTrans(:, :)`。
⇒ 「用 gfortran 编译上游老源码」**本身就会踩坑**；我们现在能编过是因为基座足够新。

### 6.7 补充：一个可能的真实工具链风险（父会话需要决定怎么处理）

**gfortran 12.2.0 + `-O3` 在 edcfbbe 源码上的 Hessian 是错的**（★实测，见 §4.4 / §5#7）。
我们的 HEAD 在 `-O3` 下**这一探测点**是对的，但这说明 **`-O3` 不是安全档位**。
我们常规构建用的就是 `Release`（`-O3`）。这不是「必须改」的 bug（我们的代码目前正确），
而是「值不值得把档位降到 `-O2` 以换取确定性」的决策——**应由父会话/用户拍板**。

---

## 7. 建议 & 未验证项

**建议（按优先级）**

1. **不做大改**：现状（CMake + gfortran + `-DWITH_TBLITE=OFF -DWITH_CPCMX=OFF`）就是用户想要的形态；
   把这一点写进文档比改构建更重要（用户对「meson 是阻碍」的理解需要纠正）。
2. **若确实要求零下载**：采用 §2.3(B) 的 vendoring（`subprojects/mctc-lib` + `-DMCTCLIB_FIND_METHOD=subproject`），
   或至少把 §2.3(A) 的两个 `-D` 写进构建说明。**改动很小，已验证。**
3. **修 `unknown-commit`**（`cmake/CMakeLists.txt:68` 加 `WORKING_DIRECTORY`）：1 行，让版本串可追溯。
4. **考虑把默认构建档位从 `-O3` 降到 `-O2`**（或直接不指定 `CMAKE_BUILD_TYPE` 用上游默认 `RelWithDebInfo`）。
   证据见 §4.4；这是一个**行为中性**的保守化。
5. **不要**为了「只有 gfortran」而手写 Makefile（§4b 评估：高成本、低可维护性、上游无先例）。
   真要单文件分发，用 §4(c) 的静态构建（★实测可行）。

**未验证项（我没有数据，不要当结论用）**
- 参照二进制的优化档、`WITH_CPCMX` 开关；
- `WITH_TBLITE=ON` 在本机能否配置/构建（推断会遭遇同类 target 重名或长依赖链）；
- gcc15 运行库替换对性能/正确性有无实际影响；
- `-O3` 异常的确切机制（已排除向量化）；
- 那个 `-O3` 异常是否会在**我们 HEAD 的其它输入**上出现（我只探了 H2O `--hess`；我们的 landscape 测试套件在 `-O3` 下是绿的，
  但那是「当前证据」，不是证明）。

---

### 附：本次调查在 `/tmp` 下的产物位置（便于复查）

```
/tmp/xtb-static/build/{configure.log,build.log}        最小依赖动态构建
/tmp/xtb-static/static{,2}/*                           静态构建尝试（static2/xtb = 成功的静态二进制）
/tmp/xtb-static/full-configure.log                     WITH_CPCMX=ON 的失败原文
/tmp/xtb-static/{lib_sources.txt,deps.mk}              源清单与依赖边
/tmp/xtb-static/stride/stride4.f90                     gfortran 12.2.0 stride 缺陷最小复现
/tmp/xtb-base/                                         edcfbbe 源码树（git archive）+ 其构建
/tmp/xtb-vendor/                                       vendoring 路线的零下载构建
/tmp/xtb-cmp/{ref,ours,stat,base,base_o0,hO1,hO2,hn}/  数值比对全部输出
```
