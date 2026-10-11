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

## One-command static release

The supported install is the idempotent `install.sh`, which runs the whole
chain (configure, build, test, install, register, self-check):

```bash
./install.sh
```

It installs a fully static binary (no dynamic libraries, `ldd` reports
`not a dynamic executable`) into `~/programs/o-xtb`, with the executable at
`~/programs/o-xtb/bin/oxtb`, and registers `~/.local/bin/oxtb`.

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
