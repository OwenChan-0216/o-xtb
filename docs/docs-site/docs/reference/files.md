# Output files

Every file below was produced by a run of a build of this repository.  The
"flag" column is the option that makes the file appear.

## Task results

| File | Flag | Content |
|---|---|---|
| `xtbopt.xyz` | `--lopt`, `--opt` | the optimised geometry |
| `xtbopt.log` | `--lopt`, `--opt` | the optimisation log |
| `xtb.trj` | `--lopt`, `--md` | the trajectory (optimisation frames, or the MD trajectory) |
| `xtbscan.log` | `--lscan` | one XYZ frame per scan point with the de-biased energy in the comment line |
| `xtbts.xyz`, `xtbts.log` | `--lts` | the transition state (saddle search) or the highest image (band search) |
| `path.xyz` | `--lts --lts-method neb\|cineb\|string\|gsm` | the relaxed band |
| `path_autoneb.xyz`, `path_ts_list.xyz` | `--lts --lts-method autoneb` | the AutoNEB path and the list of intermediate transition states |
| `irc_forward.xyz`, `irc_backward.xyz` | `--lirc` | the two IRC branches |
| `irc_path.xyz` | `--lirc` | both IRC branches as one path |
| `irc.log` | `--lirc` | the IRC integration log |
| `hessian` | `--hess`, `--lvib`, `--ohess` | the Hessian in the native layout |
| `vibspectrum` | `--hess`, `--lvib`, `--ohess` | the harmonic spectrum |
| `vib_normal_modes` | `--lvib`, `--ohess` | the normal-mode displacements |
| `g98.out` | `--hess`, `--lvib`, `--ohess` | Gaussian-style output with the thermochemistry |
| `compliance.dat` | `--hess`, `--lvib`, `--ohess` | compliance constants and relaxed force constants (multi-atom runs without frozen atoms or periodicity) |

## Machine-readable output

| File | Flag | Content |
|---|---|---|
| `landscape_<task>.json` | `--ljson` | the structured result document, format 2 (see [JSON output](ljson.md)); `<task>` is `sp`, `opt`, `scan`, `ts`, `vib`, `irc`, ... |
| `xtbout.json` | `--json` | the older property dump; a separate format, unchanged by `--ljson` |

## Files nearly every run writes

| File | Content |
|---|---|
| `xtbtopo.mol` | the molecular topology |
| `charges` | the partial charges |
| `wbo` | the Wiberg bond orders |
| `xtbrestart` | the wavefunction restart file (controlled by `--lopt-restart` for the suite) |

`--md` additionally writes `mdrestart`, `xtbmdok` and the `scoord.*` step files.

!!! note "File names are not renamed"
    The output names keep the historical xTB spellings (`xtbopt.xyz`,
    `xtbscan.log`, `irc_*.xyz`, ...), so existing tool chains keep working.
    A run can be redirected to prefixed names with `--namespace`.
