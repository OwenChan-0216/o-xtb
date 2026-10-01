# xtb 构建系统、目标图与外部依赖侦察报告

仓库：`grimme-lab/xtb`，版本 `6.7.1`（`CMakeLists.txt:32`、`meson.build:21`）
基线提交：`17790202eb14eeb40effc05008f5508fb0a52157`（2026-09-25），`git describe` = `bleed`
构建系统：**CMake（≥3.17）与 Meson（≥0.62.0）双轨**，两套源文件清单基本等价。

---

## 1. 构建目标总表

### 1.1 CMake 目标

| 目标名 | 类型 | 组成源 | 链接 |
|---|---|---|---|
| `xtb-object` | OBJECT | 全部 `${srcs}` | PUBLIC: `mctc-lib::mctc-lib`、条件 `cpcmx::cpcmx`/`tblite::tblite`/`OpenMP::OpenMP_Fortran`（`CMakeLists.txt:94-133`） |
| `lib-xtb-static` | STATIC | `$<TARGET_OBJECTS:xtb-object>`（`WITH_OBJECT=ON`）或 `${srcs}`（否则） | BLAS、LAPACK、OpenMP、mctc-lib、cpcmx?、tblite?（`CMakeLists.txt:138-183`） |
| `lib-xtb-shared` | SHARED | `$<TARGET_OBJECTS:xtb-object>`，**仅 `WITH_OBJECT=ON` 时生成** | 同上（`CMakeLists.txt:186-225`） |
| `xtb-exe` | EXECUTABLE | `${prog}`（9 个文件） | PRIVATE `lib-xtb-static`，输出名 `xtb`（`CMakeLists.txt:227-257`） |
| `xtb_tests_capi` | EXECUTABLE | `test/api/c_api_example.c` | PUBLIC `lib-xtb-shared`（`test/api/CMakeLists.txt:16-23`） |
| `xtb-tester` | EXECUTABLE | `test/unit/*.f90` | PRIVATE `lib-xtb-static` + `test-drive::test-drive`（`test/unit/CMakeLists.txt:72-90`） |

关键点：`xtb-object` 是**唯一**把全部库源码编进的目标；静态/共享库都只是它的对象集合包装。`lib-xtb-shared` 只有在 `WITH_OBJECT=ON` 时才存在（`CMakeLists.txt:186`）。

### 1.2 Meson 目标

| 目标名 | 类型 | 组成源 | 依赖 |
|---|---|---|---|
| `xtb`（`xtb_lib`，`library()`） | 默认 `both`（静态+共享，`meson.build:17`），`default_library` 可改 | `srcs` | `lib_deps`（OpenMP、threads、BLAS/LAPACK、mctc-lib、tblite、multicharge、dftd4、cpx） |
| `xtb`（`xtb_exe`，`executable()`） | EXECUTABLE | `prog` | `xtb_dep_static`（`meson.build:141-152`） |
| `xtb_c_test` | EXECUTABLE | `test/api/c_api_example.c` | `xtb_dep_static`（`test/api/meson.build:18-28`） |
| `tester` | EXECUTABLE | `test/unit/*.f90` | `xtb_dep_static` + `test-drive`（`test/unit/meson.build:78-87`） |

Meson 定义了 `xtb_dep`（共享）、`xtb_dep_static`（静态）两个 `declare_dependency`（`meson.build:123-137`）；测试统一用静态版。

### 1.3 `srcs` 的组装方式（是否单体）

**结论：`${srcs}` 是单体、无条件的**——没有 `WITH_*` 条件把某个模块目录排除出库源码（除了 `WITH_OBJECT` 只影响"是否包一层 object library"，`srcs` 本身不变）。

CMake 侧（`src/CMakeLists.txt:17-42`）：
```cmake
add_subdirectory("api")   # 及 coulomb/dipro/disp/docking/extern/freq/gfnff/
                          # internals/io/iff/main/mctc/param/prog/ptb/solv/
                          # tblite/type/xtb/lbfgs_anc
...
set(dir "${CMAKE_CURRENT_SOURCE_DIR}")
list(APPEND srcs "${dir}/aespot.F90" ... "${dir}/zmatpr.f90")   # src 根目录 ~130 个文件
set(srcs ${srcs} PARENT_SCOPE)
set(prog ${prog} PARENT_SCOPE)
```
- 每个子目录的 `CMakeLists.txt` 用 `list(APPEND srcs ...)` + `set(... PARENT_SCOPE)` 追加自己的文件；嵌套目录（`io/reader`、`io/writer`、`mctc/blas`、`mctc/lapack`、`solv/ddcosmo`）先在父 CMakeLists 里 `add_subdirectory`，再追加父目录文件。
- 例外：`src/model_hessian/` **没有 CMakeLists.txt**，它的 7 个文件被直接写在 `src/CMakeLists.txt:80-87`。
- `symmetry/CMakeLists.txt:24-27` 把 `symmetry.f90` + `symmetry_i.c` 追加进 `srcs`（顶层在 `CMakeLists.txt:73` `add_subdirectory("symmetry")`）。
- 顶层 `CMakeLists.txt:74-75` 初始化 `set(prog)` / `set(srcs)`，`xtb-object` 在 `CMakeLists.txt:96-101` 用全部 `${srcs}` 构造。

规模：`src/` 下 `.f90/.F90/.f/.c` 共 362 个，其中 `src/prog/` 9 个（属 `prog`），`src/nvtx.f90` 1 个（CMake 未收录），故 CMake `srcs` ≈ 353 + symmetry 2 = **355 个源文件**；`prog` = 9 个。

Meson 侧（`src/meson.build:1-22` + 各子目录 `srcs += files(...)`）：
- 与 CMake 同构，但 `src/model_hessian/meson.build` 存在并被 `subdir('model_hessian')` 引入。
- `srcs += 'symmetry/symmetry.f90'`、`'symmetry/symmetry_i.c'`（`meson.build:104-105`）。
- **差异**：`meson.build:107-109` 在 `-Dnvtx=true` 时追加 `src/nvtx.f90`；CMake 完全不编译 `src/nvtx.f90`，也无 GPU/nvtx 选项。
- Meson 每个库/可执行都传 `-DWITH_TBLITE=0/1`、`-DWITH_CPCMX=0/1`（`meson.build:120-123, 148-150`）；CMake 用 `add_compile_definitions`（`CMakeLists.txt:48,58`）。

两套清单经脚本计数均为 ~356 条，可视为一一对应。

---

## 2. 是否存在多个可执行文件？

**运行时只有一个 xtb 可执行文件**，但包含 6 个"子模块"入口，由 `primary.f90` 内部分派，**不是多个二进制**：

- `src/prog/primary.f90:18-77` 定义 `program xtb_prog_primary`，用 `getRunmode` 解析首参数，`select case` 分派到：
  - `xtbMain`（`src/prog/main.F90:111`）
  - `xtbInfo`（`src/prog/info.f90:42`）
  - `xtbThermo`（`src/prog/thermo.f90:45`）
  - `xtbTopology`（`src/prog/topology.f90:43`）
  - `xtbDock`（`src/prog/dock.f90:66`）
  - `xtbIR`（`src/prog/irmod.f90:45`）
- `main.F90`、`dock.f90`、`info.f90`、`irmod.f90`、`topology.f90`、`thermo.f90` 都是**模块 + 子程序**，只有 `primary.f90` 是 `program`。因此 `dock`/`irmod` 等不是独立可执行目标。

**构建产物中的可执行目标共 3 个**（两套系统一致）：
1. `xtb`（主程序；源 `src/prog/primary.f90`）
2. `xtb_tests_capi` / `xtb_c_test`（C API 测试，`test/api/c_api_example.c`）
3. `xtb-tester` / `tester`（单元测试框架 `test-drive` runner，`test/unit/main.f90`）

没有独立的 `tblite` 辅助可执行文件——tblite 仅作为被链接的库（`src/tblite/`、`WITH_TBLITE`）。

---

## 3. 外部依赖矩阵

xtb 自身直接 `find_package` 的依赖（`CMakeLists.txt:40-84`）：

| 依赖 | 必需/可选 | 控制开关 | 获取方式（CMake） | 版本 |
|---|---|---|---|---|
| **mctc-lib** | **必需** | 无（总是） | `find_package("mctc-lib" REQUIRED)`；Find 脚本方法顺序 `cmake→pkgconf→subproject→fetch` | v0.5.1 |
| **tblite** | 可选（默认 ON） | `WITH_TBLITE`（`cmake/CMakeLists.txt:22`） | `find_package("tblite" REQUIRED)`（`CMakeLists.txt:47`）+ `add_compile_definitions(WITH_TBLITE)` | v0.6.0 |
| **cpcmx** | 可选（默认 ON） | `WITH_CPCMX`（`cmake/CMakeLists.txt:23`） | `find_package("cpcmx" REQUIRED)`（`CMakeLists.txt:57`）+ `WITH_CPCMX` | v1.1.0 |
| **test-drive** | 仅测试时必需 | `WITH_TESTS`（默认 TRUE） | `find_package("test-drive" REQUIRED)`（`CMakeLists.txt:66`） | v0.5.0 |
| OpenMP | 可选（默认 ON） | `WITH_OpenMP`（`cmake/CMakeLists.txt:20`） | `find_package("OpenMP" REQUIRED)` | 系统 |
| BLAS/LAPACK | **必需** | 无 | `find_package("LAPACK"/"BLAS" REQUIRED)`（`CMakeLists.txt:83-84`） | 系统 |

**传递/提升（promote）依赖**（`CMakeLists.txt:51-52, 61-62`）：`toml-f`、`test-drive`、`mstore`、`multicharge`、`dftd4`、`s-dftd3`、`tblite`、`cpcmx`、`numsa`、`mctc-lib`。这些由 tblite/cpcmx 的 CMake config 或子项目创建目标，xtb 通过 `xtb_promote_target()`（`cmake/modules/xtb-utils.cmake:20-26`）把它们重命名为 `pkg::pkg` 命名空间目标。

- `toml-f`、`mstore`、`numsa`、`s-dftd3` **没有** xtb 自带 Find 脚本，完全靠上游 config/子项目提供。
- xtb 自带 Find 脚本（`cmake/modules/`）：`Findmulticharge.cmake`、`Findmctc-lib.cmake`、`Finddftd4.cmake`、`Findtblite.cmake`、`Findcpcmx.cmake`、`Findtest-drive.cmake`。其中 `Findmulticharge`/`Finddftd4` 在 xtb 顶层并未直接调用，而是供子项目（tblite/dftd4）复用（xtb 把 `cmake/modules` 加入 `CMAKE_MODULE_PATH`，`cmake/CMakeLists.txt:40-41`）。
- `xtb-utils.cmake:33-113` 的 `xtb_find_package` 实现四级查找：`cmake`（config）→ `pkgconf` → `subproject`（`subprojects/<pkg>`，需自带 CMakeLists）→ `fetch`（`FetchContent_Declare` + `FetchContent_MakeAvailable`）。

**Meson 侧**（`meson/meson.build:215-266`）：

| 依赖 | 必需/可选 | 控制 | fallback |
|---|---|---|---|
| mctc-lib | **必需** | 无 | `['mctc-lib','mctc_dep']`，static |
| tblite | 可选 | `-Dtblite`（feature auto） | `['tblite','tblite_dep']`，static、`api=false`，`version>=0.4.0` |
| multicharge | 可选（跟随 tblite） | `required: get_option('tblite')` | `['multicharge','multicharge_dep']` |
| dftd4 | 可选（跟随 tblite） | `required: get_option('tblite')` | `['dftd4','dftd4_dep']` |
| cpx(=cpcmx) | 可选 | `-Dcpcmx` | `['cpx','cpx_dep']`，static |
| test-drive | 仅测试 | `required: not meson.is_subproject()` | `['test-drive','testdrive_dep']`（`test/unit/meson.build:20-25`） |

**wrap 文件 / 子模块**：
- `.gitmodules` 只有 `assets/aur/xtb-git`（无关构建）。
- `subprojects/*.wrap`（`wrap-git`）：`cpx.wrap`(v1.1.0)、`dftd4.wrap`(v4.2.0)、`mctc-lib.wrap`(v0.5.1)、`multicharge.wrap`(v0.5.0)、`tblite.wrap`(v0.6.0)、`test-drive.wrap`(v0.5.0)。**没有** toml-f/mstore/numsa/s-dftd3 的 wrap——它们由父依赖（tblite 等）的 wrap 传递解析。
- `subprojects/` 内除 wrap 外没有已检出的源码目录（`subprojects/` 仅 6 个 `.wrap` + `.gitignore`）。

> 注意：CMake 的 `xtb_find_package` 默认方法含 `subproject` 与 `fetch`，因此即使系统无 mctc-lib/tblite，联网时也能通过 FetchContent 自动拉取。Meson 默认也会用 wrap fallback（除非 `--wrap-mode=nofallback`）。

---

## 4. 构建选项（含默认值）

### 4.1 CMake

| 选项 | 默认 | 位置 | 作用 |
|---|---|---|---|
| `WITH_OBJECT` | `TRUE` | `CMakeLists.txt:18` | 是否用 object library 组合；`FALSE` 时无共享库，直接源码建静态库。CMake 3.27.x 有 bug 时被强制设为 FALSE（`CMakeLists.txt:21-24`） |
| `INSTALL_MODULES` | `FALSE` | `CMakeLists.txt:19` | 是否把 `.mod` 装到 include |
| `WITH_OpenMP` | `TRUE` | `cmake/CMakeLists.txt:20` | OpenMP 并行 |
| `WITH_TBLITE` | `TRUE` | `cmake/CMakeLists.txt:22` | tblite 后端；关掉即去掉 tblite 路径 |
| `WITH_CPCMX` | `TRUE` | `cmake/CMakeLists.txt:23` | CPCM-X 溶剂化 |
| `WITH_TESTS` | `TRUE` | `cmake/CMakeLists.txt:21` | 编译单元测试（触发 test-drive 查找与 `add_subdirectory(test)`） |
| `CMAKE_BUILD_TYPE` | `RelWithDebInfo` | `cmake/CMakeLists.txt:26-35` | 未指定时默认 |

**CMake 完全没有 GPU/nvtx 选项，也不编译 `src/nvtx.f90`。** 没有 `WITH_GFNFF`——GFN-FF 源码（`src/gfnff/`）无条件编译，无法在构建期裁剪。

### 4.2 Meson（`meson_options.txt`）

| 选项 | 类型 | 默认 | 作用 |
|---|---|---|---|
| `lapack` | combo | `auto` | 后端：`auto/mkl/mkl-rt/openblas/netlib/custom` |
| `custom_libraries` | array | `[]` | custom 后端的库 |
| `tblite` | feature | `auto` | tblite 后端 |
| `cpcmx` | feature | `auto` | CPCM-X 溶剂化 |
| `openmp` | boolean | `true` | OpenMP |
| `install_modules` | boolean | `false` | 安装 `.mod` |
| `build_name` | string | `unknown` | 版本串（git 自动覆盖） |
| `gpu` | boolean | `false` | GPU 加速（仅 NVHPC/PGI，`meson/meson.build:68-83`） |
| `gpu_arch` | string | `70` | GPU arch（`-ta=tesla:cc<arch>`） |
| `cusolver` | boolean | `false` | cuSOLVER/cuBLAS eigensolver |
| `nvtx` | boolean | `false` | NVTX markers，并追加 `src/nvtx.f90` |

可裁剪特性：
- **tblite 后端**：关闭 → `-Dtblite=disabled`（meson）/ `-DWITH_TBLITE=false`（CMake）。
- **cpcmx 溶剂化**：`-Dcpcmx=disabled` / `-DWITH_CPCMX=false`。
- **OpenMP**：`-Dopenmp=false` / `-DWITH_OpenMP=false`。
- **GPU**：仅 meson（`-Dgpu=true`），且只在 NVHPC 编译器分支生效；CMake 无。
- **gfnff 无法裁剪**（两套构建都无条件编译 `src/gfnff/`）。

`WITH_TBLITE`/`WITH_CPCMX` 通过 `#ifdef` 宏进入源码：`src/features.F90`、`src/solv/cpx.F90`、`src/tblite/*`、`src/dipro/*`、`src/type/*`、`src/main/*`、`src/disp/dftd4.F90`、`src/scf_module.F90` 等（grep `WITH_TBLITE|WITH_CPCMX` 命中 30+ 文件）。

---

## 5. 运行时数据文件与查找机制

### 5.1 参数/数据文件

| 文件 | 说明 | 查找/安装 |
|---|---|---|
| `param_gfn0-xtb.txt` | GFN0 参数 | 源码根；运行时 `rdpath(env%xtbpath,...)`（`src/xtb/calculator.f90:122`） |
| `param_gfn1-xtb.txt` / `param_gfn1-si-xtb.txt` | GFN1 参数 | 同上（`src/xtb/calculator.f90:125`） |
| `param_gfn2-xtb.txt` | GFN2 参数 | 同上（`src/xtb/calculator.f90:128`） |
| `param_ipea-xtb.txt` | IP/EA 参数 | 同上 |
| `.param_gfnff.xtb` | GFN-FF 参数 | `rdpath(env%xtbpath,'.param_gfnff.xtb',...)`（`src/prog/topology.f90:110`） |
| `param_ptb.txt` | PTB 参数 | `rdpath(env%xtbpath,'param_ptb.txt',...)`（`src/ptb/calculator.F90:135`） |
| `.xtbrc` / `.xtbrc` in `$XTBPATH` | 全局配置 | `rdpath(env%xtbpath,p_fname_rc,xrc,...)`（`src/prog/main.F90:370`） |
| `.param.xtbiff` | docking 参数 | `$XTBHOME/.param.xtbiff`（`src/docking/param.f90:178`） |
| `include/*.fh` | 编译期 `#include` 的参数（GBNSA/alpb/cosmo 网格） | 编译时 include，非运行时 |
| `symmetry/symmetry.f90`,`symmetry_i.c` | 源码，非数据 | 编入库 |

### 5.2 路径解析逻辑

- 环境初始化 `src/type/environment.f90:140-149`：
  - `XTBHOME`：若未设置/为空 → 回退到 `$HOME`。
  - `XTBPATH`：若未设置/为空 → 回退到 `XTBHOME`。
- `rdpath`（`src/mctc/systools.F90:66-101`）把 `path` 按 `pathdel`（`:`）拆开，逐个目录 `inquire` 目标文件，返回第一个存在的完整路径。
- `xenv%home`/`xenv%path` 在 `src/prog/main.F90:221-222` 被设为 `env%xtbhome`/`env%xtbpath`；`src/printout.f90:93` 打印 `xtbhome directory`。
- `src/readin.f90:62` 同样用 `rdpath(xenv%path,name,...)` 查找 xcontrol 等。
- 注意：没有编译期硬编码的数据目录宏；运行时完全依赖 `XTBPATH` 环境变量（测试正是通过设 `XTBPATH=${PROJECT_SOURCE_DIR}` 找到源码根参数文件）。

### 5.3 安装目的地

**CMake（`CMakeLists.txt`）：**
- `include/xtb.h` → `${CMAKE_INSTALL_INCLUDEDIR}`（`:242-249`）
- 模块 `.mod`（当 `INSTALL_MODULES`）→ `${CMAKE_INSTALL_INCLUDEDIR}`（`:251-258`）
- 6 个参数文件 → `${CMAKE_INSTALL_DATADIR}/xtb`（`:260-273`）：`param_gfn0/1/1-si/2/ipea-xtb.txt`、`.param_gfnff.xtb`
- 库/可执行 → `lib`/`bin`（`:285-333`）
- CMake 包文件 + Find 模块 → `${CMAKE_INSTALL_LIBDIR}/cmake/xtb`（`:335-350` 与 `cmake/CMakeLists.txt:31-35`）
- 版本头 `xtb_version.fh` 生成到 build 的 `include/`（`cmake/CMakeLists.txt:84-92`）

**Meson（`meson.build` + `assets/meson.build`）：**
- `install_headers(xtb_header)` → includedir（`meson.build:181`）
- `install_data(xtb_parameter_files)` → meson 默认 `datadir`（`meson.build:203-214`，未指定 `install_dir`）。**代码层面目的地是 `${prefix}/share`；`meson/README.adoc` 与 `assets` 中示意为 `${prefix}/share/xtb`，此处存在文档与实现的疑点。**
- `.mod`（当 `install_modules`）→ `include`（`meson.build:216-225`）
- `config_env.bash`/`config_env.csh`（含 `@datadir@` 占位符，`assets/templates/config_env.bash`）与 `xtb.pc` → `libdir/pkgconfig`、env module tcl → `datadir/modules/modulefiles/xtb/<version>`
- man pages（发现 `asciidoctor` 才生成）→ man1/man7（`meson.build:186-201`）

`config_env.bash` 设置 `XTBPATH=${XTBHOME}/@datadir@:${HOME}`——这解释了 `XTBPATH` 应包含安装数据目录。

---

## 6. 最小可复制构建命令（Linux + gfortran）

### 6.1 CMake
```bash
cd /path/to/xtb
export FC=gfortran CC=gcc
# 完整（需要 mctc-lib；可联网自动 FetchContent，或已安装）
cmake -B _build -S. -GNinja -DCMAKE_BUILD_TYPE=Release
cmake --build _build
# 精简（去掉 tblite 与 cpcmx，仍需要 mctc-lib + LAPACK/BLAS）
cmake -B _build -S. -GNinja -DCMAKE_BUILD_TYPE=Release -DWITH_TBLITE=false -DWITH_CPCMX=false
cmake --build _build
# 运行测试
ctest --test-dir _build --output-on-failure -R 'xtb/*'
```

### 6.2 Meson
```bash
cd /path/to/xtb
export FC=gfortran CC=gcc
# 需系统 liblapack-dev / libblas-dev（netlib 后端）
meson setup _build --buildtype release --optimization 2 -Dlapack=netlib
meson compile -C _build
# 精简
meson setup _build --buildtype release -Dlapack=netlib -Dtblite=disabled -Dcpcmx=disabled
meson compile -C _build
# 运行测试
meson test -C _build --print-errorlogs --suite xtb
```

依赖缺失时：CMake 通过 `FetchContent`（默认方法含 `fetch`）拉取 mctc-lib/tblite/cpcmx；Meson 通过 `subprojects/*.wrap` fallback 拉取。两者都需联网。若离线，需预装 `mctc-lib`（及可选 `tblite`/`cpcmx`），或把依赖源码放到 `subprojects/<pkg>`。

---

## 7. 测试与 CI

### 7.1 test/
- `test/CMakeLists.txt:16-21`：`WITH_OBJECT` 为真才加 `api` 子目录；`unit` 总是加。
- `test/api`：C API 示例（`c_api_example.c`），链接共享库；CMake 测试名 `xtb/CAPI`，env `XTBPATH=${PROJECT_SOURCE_DIR}`（`test/api/CMakeLists.txt:25-35`）。Meson 测试名 `C API`，链接静态库（`test/api/meson.build`）。
- `test/unit`：31 个测试名（`atomlist,bmatrix,coordinationnumber,coulomb,dftd3,dftd4,detrotra,docking,eeq,gfn0,gfn1,gfn2,gfnff,hessian,iff,latticepoint,molecule,model-hessian,oniom,optimizer,dipro,pbc-tools,peeq,random,repulsion,symmetry,tblite,thermo,vertical,wsc,cpx`）+ 单独的 `ptb`（`test/unit/CMakeLists.txt:26-56`、`test/unit/meson.build:34-58`）。依赖 `test-drive`。
- 单元测试还带 5 个 CLI 冒烟测试（`--version/--help/--license`、Info、Singlepoint、GFN0/1/2、GBSA、GNF-FF、xcontrol），env `XTBPATH`（`test/unit/CMakeLists.txt:113-190`）。
- `src/tblite`/`cpx` 测试通过编译宏 `WITH_TBLITE`/`WITH_CPCMX` 条件生效。

### 7.2 `.github/workflows/fortran-build.yml`
一条 CI 多矩阵：
- `source-dist`：meson `-Dlapack=netlib --wrap-mode=forcefallback`，`meson dist --include-subprojects`。
- `gcc-meson-build`：gfortran 10–15、ubuntu/macos、`-Db_coverage=true`、`-Dlapack=netlib|openblas`，跑 `--suite xtb`。
- `gcc-cmake-build`：gfortran-14/gcc-14、Release+Debug、Ninja，`ctest -R 'xtb/*' -E 'tblite/gfn1-xtb'`。
- `xtb-lightweight-meson-build`：`-Dtblite=disabled -Dcpcmx=disabled`。
- `xtb-lightweight-cmake-build`：`-DWITH_CPCMX=false -DWITH_TBLITE=false`。
- `mingw-meson-build` / `mingw-meson-static-build`：MSYS2 MINGW64 + OpenBLAS/LAPACK，静态打包。
- `intel-meson-build`（ifort + MKL，静态 `-lifcoremt`）、`intel-ifx-cmake-build`/`intel-ifx-meson-build`（ifx + MKL，`-DBLA_VENDOR=Intel10_64lp`、`WITH_TBLITE/CPCMX=ON`）。
- `continuous-delivery`：仅在 push 时构建 Linux/Windows 发行包。

CI 明确验证了"关闭 tblite/cpcmx 的轻量构建"路径可用。

---

## 8. 风险、坑与开放问题

1. **`xtb-config-dir` 是未定义变量**：`CMakeLists.txt:126` 在 include 目录里引用 `${xtb-config-dir}`，但全仓库没有 `set(xtb-config-dir ...)`——展开为空，属无害死引用。
2. **CMake 不编译 `src/nvtx.f90`**，也无 GPU 选项；GPU 路径仅 meson（NVHPC）。`src/xtb/hamiltonian_gpu.f90` 两套都无条件编入，但内部多由宏控制。
3. **参数文件 meson 安装目的地疑点**：代码 `install_data(xtb_parameter_files)` 未指定 `install_dir`，按 meson 语义落在 `${prefix}/share`，而 README/惯例期望 `${prefix}/share/xtb`。运行期依赖 `XTBPATH` 指向该目录，若安装位置与预期不符，xtb 找不到参数文件。需实测 `meson install` 产物确认。
4. **GFN-FF 不可裁剪**：没有 `WITH_GFNFF` 开关，`src/gfnff/` 始终编入。
5. **单体外壳**：`xtb-object` 无条件编译全部 `${srcs}`，因此"关闭 tblite/cpcmx"只是去掉链接依赖与 `#ifdef` 分支，编译量几乎不变。
6. **多构建系统需同步**：新增源文件必须同时更新 `CMakeLists.txt` 与 `meson.build`，否则两套构建产物不一致（`src/model_hessian` 在 CMake 无独立 CMakeLists 即为易错点）。
7. **`WITH_OBJECT` 是共享库前提**：`WITH_OBJECT=FALSE`（如 CMake 3.27.x）会静默不产出 `libxtb.so`，仅静态库+可执行。
8. **mctc-lib 强依赖**：即使轻量构建也必须有 mctc-lib；离线环境需预装或提供 `subprojects/mctc-lib`。
9. **`src/model_hessian/CMakeLists.txt` 缺失**：CMake 侧靠父文件手写 7 个源文件，新增/删除文件时容易遗漏；meson 侧有独立 `meson.build`。

---

## 9. 建议先打开的文件

1. `CMakeLists.txt`（顶层）—— 全部 CMake 目标、依赖、安装规则、选项入口。
2. `meson.build` + `meson/meson.build` —— meson 目标、LAPACK 后端与依赖解析。
3. `src/CMakeLists.txt` 与 `src/meson.build` —— `${srcs}`/`prog` 单体清单组装。
4. `src/prog/primary.f90` —— 单可执行多子模块分派的入口。
5. `cmake/modules/xtb-utils.cmake` —— 外部依赖四级查找（cmake/pkgconf/subproject/fetch）。
6. `src/type/environment.f90` + `src/mctc/systools.F90` —— 运行时数据路径（XTBPATH/XTBHOME）。
