# Getting started

## Requirements

* a Fortran compiler (the supported configuration is GNU `gfortran` 12),
* CMake >= 3.17 (`cmake_minimum_required` in `CMakeLists.txt`),
* a BLAS/LAPACK provider (OpenBLAS or MKL).

`XDG`-style relocatable installs are supported: since the option is built in,
an install tree finds its own parameter files, so `--gfn 0/1/2/ff` work from any
directory without exporting `XTBPATH`.

## Build the site-independent program

From the repository root:

```bash
cmake -S . -B build \
      -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"
cmake --build build -j
```

!!! warning "Use `-O2`, not the default Release `-O3`"
    CMake's `Release` build type is `-O3` for GNU, and gfortran 12.2.0 at `-O3`
    produced wrong numerical Hessian results for one source state of this tree.
    `-O2` is the supported optimisation level and the configure step warns when
    `-O3` is detected.  `-DWITH_CPCMX=OFF` is required with some CMake
    versions to avoid a toml-f target clash.

The executable is `build/oxtb`.

### Windows (MSYS2)

`install.sh` is a Unix shell script, so a Windows build is configured directly.
The supported environment is **MSYS2 UCRT64** (MSYS2 documents MINGW64 as
deprecated), and its shell provides the whole toolchain as packages:

```bash
pacman -S mingw-w64-ucrt-x86_64-gcc-fortran mingw-w64-ucrt-x86_64-openblas \
          mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja \
          mingw-w64-ucrt-x86_64-git mingw-w64-ucrt-x86_64-python
```

OpenBLAS is LAPACK complete, so the separate `lapack` package is not needed and
the math library lookup does not depend on search order.  `python` is part of
the line because `WITH_TESTS` defaults to `ON` and the test target needs a
Python 3 interpreter; `git` is what fetches `mctc-lib` and `test-drive`, which
MSYS2 does not package.

From the repository root, in the same shell:

```bash
cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG" \
      -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_OBJECT=OFF
cmake --build build -j
```

The executable is `build/oxtb.exe`.

!!! note "The Windows flags are in the build system, not on the command line"
    Do not pass the Windows specifics by hand.  The `if(WIN32)` blocks of
    `CMakeLists.txt` already supply `_WIN32` (gfortran's preprocessor defines no
    target macro at all), the static OpenMP archives, `-static` and the larger
    stack.  The `windows-latest` CI job runs exactly this flow; it additionally
    passes `-DBLA_VENDOR=OpenBLAS` and `-DWITH_TESTS=ON
    -DTEST_DRIVE_BUILD_TESTING=OFF` to build and run a bounded test subset.

What a Windows build does differently:

- `WITH_OBJECT=OFF` is required: a `-static` executable cannot host the shared
  library, so the build has no C API and no `liboxtb.dll`; upstream's Windows
  build has the same limitation.
- No parameter files are needed: GFN1-xTB, GFN2-xTB, GFN-FF and, since 0.3.0,
  GFN0-xTB are compiled into the binary.
- The program sets its own console output code page to UTF-8 at startup, so a
  Chinese-locale console shows `·`, `²`, `Δ` and `⁻¹` correctly without `chcp`.
  Redirected output is not translated and keeps the raw UTF-8 bytes, and the
  console window stays on UTF-8 after the run.
- `--blas-threads` is inert in a static build and says so; use
  `OPENBLAS_NUM_THREADS` instead.
- The man pages and the shell completions are Unix install steps and do not
  apply.
- Status: this is the path CI builds on `windows-latest` with MSYS2/UCRT64, and
  a cross-built `oxtb.exe` was smoke-tested on a real Windows machine (the four
  `--gfn` methods, `--hess` and `--lopt`).  Nothing beyond that is claimed.

## One-command static release

The supported install is the idempotent `install.sh`, which runs the whole
chain (configure, build, test, install, register, self-check):

```bash
./install.sh
```

It installs a fully static binary (no dynamic libraries, `ldd` reports
`not a dynamic executable`) into `~/programs/o-xtb`, with the executable at
`~/programs/o-xtb/bin/oxtb`, and registers `~/.local/bin/oxtb`.

## Reproducible builds

Two builds of the same tree, at the same absolute path, with the same toolchain
and the inputs pinned below, produce a **byte-identical** `oxtb`.  The tree's
route to that path does not matter either: a `cp -a` copy and a fresh `tar`
re-extract of the same tree give the same bytes, and so does a different
build-directory name.  What the hash depends on is this:

* the **absolute source path** - it is compiled into the executable,
* the **absolute dependency paths**: `-DFETCHCONTENT_SOURCE_DIR_MCTC-LIB` (and
  `-DFETCHCONTENT_SOURCE_DIR_TEST-DRIVE` when `WITH_TESTS=ON`) together with
  `-DFETCHCONTENT_FULLY_DISCONNECTED=ON`, so that no dependency is fetched into
  the build directory, whose own path would then be compiled in as well,
* the **toolchain versions**: the pair measured here is gfortran 12.2.0 with
  CMake 4.3.2,
* `SOURCE_DATE_EPOCH`, pinned to the commit's own timestamp, which dates the
  version header; it is honoured in UTC.

```bash
export SRC=/path/to/source BUILD=/path/to/build
export MCTC=/path/to/mctc-lib-src TEST_DRIVE=/path/to/test-drive-src
cd "$SRC"
export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct) OMP_NUM_THREADS=1
cmake -S "$SRC" -B "$BUILD" \
  -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=OFF -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG" \
  -DFETCHCONTENT_SOURCE_DIR_MCTC-LIB="$MCTC" \
  -DFETCHCONTENT_SOURCE_DIR_TEST-DRIVE="$TEST_DRIVE" \
  -DFETCHCONTENT_FULLY_DISCONNECTED=ON
cmake --build "$BUILD" -j8
sha256sum "$BUILD/oxtb"
```

!!! warning "What this does not claim"
    A different **compiler** changes the bytes: gfortran 14.4.0 at the same
    path with the same flags gives a different executable, and gfortran 14.4.0
    reproduces itself byte for byte on a repeat build, so that is the compiler
    and not build noise.  A different CMake version is in the same class (not
    narrowed further).  A different **absolute path** changes the bytes too,
    and the path cannot be mapped away: the embedded copies are gfortran's
    per-I/O-statement source-location descriptors (`At line N of file <path>`),
    emitted for I/O statements written without `IOSTAT=`.  All 2,317 own-source
    and 126 `mctc-lib` occurrences sit in `.rodata`, and `-ffile-prefix-map`,
    `-fdebug-prefix-map` and `-fmacro-prefix-map` were each measured to change
    not one byte.  Cross-machine and cross-platform reproducibility is not
    claimed: only the Linux executable was compared, on one machine.

A rebuild and a download are different guarantees.  A released archive is
identified by its `SHA256SUMS` asset, while a rebuild reproduces the bytes only
under the conditions above.

## A first run: water

Create a water geometry in XYZ format:

```text
3
water
O  0.0000000  0.0000000  0.0000000
H  0.0000000  0.0000000  0.9600000
H  0.9300000  0.0000000 -0.2400000
```

A GFN2-xTB single point:

```bash
oxtb water.xyz --gfn 2 --sp
```

The result block is:

```text
           -------------------------------------------------
          | TOTAL ENERGY               -5.070383095219 Eh   |
          | GRADIENT NORM               0.007659658070 Eh/α |
          | HOMO-LUMO GAP              14.518987926825 eV   |
           -------------------------------------------------
```

The run writes `xtbtopo.mol`, `charges` and `wbo` next to the input, and a
restart file `xtbrestart`; nothing needs to be requested for those.

## A geometry optimisation

```bash
oxtb water.xyz --gfn 2 --lopt --lopt-engine lbfgs --lopt-level normal
```

The suite relaxes the geometry and writes `xtbopt.xyz` (the optimised geometry),
`xtbopt.log` (the optimisation log) and `xtb.trj` (the trajectory).  The
converged energy is printed at the end of the run.

The same calculation can be requested with the native spelling `--opt`, which
the suite now serves as well; `--lopt` is the explicit suite task.

## Where to go next

* the [user guide](user-guide/index.md) describes each task family and the flags
  that select its method;
* the [command-line reference](reference/cli.md) lists every option;
* the [output files](reference/files.md) chapter maps each file to the flag
  that produces it.
