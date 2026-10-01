# M3 (`--lvib`) validation data — layout

Raw data of the M3 acceptance experiments (PLAN §8.2 #2/#3/#12 plus the
`--hess` interoperability check).  Report: `../21-m3-validation-experiments.md`.

Every case directory holds `stdout.txt` (the complete stdout+stderr of the
job) plus the files the job wrote (`hessian`, `vibspectrum`, `g98.out`,
`vib_normal_modes`).  Everything was produced with
`OMP_NUM_THREADS=1` and `XTBPATH=<repo root>`, binary
`/tmp/xtb-land/build/xtb` (HEAD `b1f4dad` plus the uncommitted M3 working-tree
changes; the validation itself modified no source file).

| Path | Content |
|---|---|
| `run_experiments.py` | the driver that produced the whole tree (rerunnable) |
| `mol/` | input geometries; `*_opt.xyz` are GFN2 minima from `xtb --opt`, `h2o.xyz`/`h2o_raw.xyz` is the non-stationary CMake test geometry |
| `expA/`, `expA_step_sccacc.csv` | PLAN #2: `step_hess` × `sccacc` grid, 2 molecules × 4 × 3 |
| `expB/`, `expB_etemp.csv`, `expB_etemp_hessian.csv`, `expB_h2_grid.csv` | PLAN #3: `etemp` sweep + the stretched-H2 distance scan |
| `expC/`, `expC_linear.csv` | PLAN #12: linear molecules (CO2, HCN) vs non-linear controls |
| `expD/`, `expD_interop.csv`, `expD_structure_diff.txt` | `--lvib` vs `--hess` file/number interoperability |
| `expB/h2grid/` | stretched H2 (2.4 … 6.0 Å) × `etemp` {300, 5000} K |

`expB_h2_grid.csv` was produced by a short inline script (the same recipe is
in §8 of the report); the row format is `d_Ang,etemp_K,energy_Eh,n_imag,freq_cm1`.

All 79 jobs exited 0 (69 `--lvib` runs, 10 `--hess` control runs); no case had to
be recorded as `nan` and no stdout carries an `ERROR` / `abnormal termination`
marker.

Note on the frequency precision: the `--lvib` stdout prints 2 decimals, the
`g98.out` block 4 decimals.  Every drift/comparison number in the report is
taken from the `g98.out` values, which is why the tables can resolve
differences far below 0.01 cm⁻¹.
