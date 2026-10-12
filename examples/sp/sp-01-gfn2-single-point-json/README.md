# sp-01 — GFN2 single point with the unified JSON result

**System.** `benzoic_acid_dimer/reactant.xyz` from `examples/structures` — the planar C2h
hydrogen-bonded benzoic acid dimer, **30 atoms** (molecule A = atoms 1-15, molecule B = 16-30).
It is a GFN2-xTB minimum.

**What it shows.** A plain GFN2-xTB single point and the machine-readable result document that
`--ljson` writes for *every* run type (`landscape_sp.json`). The energy and the HOMO-LUMO gap are
printed on stdout; the JSON document carries the same energy plus the geometry, the provenance
block and the gradient norm.

**Command** (`run.sh`):

```bash
export OMP_NUM_THREADS=1
export XTBPATH=<repository root>
oxtb input.xyz --gfn 2 --sp --ljson --norestart
```

`--norestart` keeps the run independent of a stale `xtbrestart` from an earlier run (see
"Reproduce" below). The binary is the installed OxTB 0.1.0 / xTB 6.7.1 release, commit `c712f9e`.

**Observed result** (`oxtb.log`):

| quantity | value |
|---|---|
| total energy | **-52.373771244067 Eh** |
| HOMO-LUMO gap | **0.1351135 Eh = 3.676625649790 eV** |
| gradient norm | 8.231235387188e-04 Eh/bohr |
| SCC iterations | 11 |
| wall time | **0.03 s** |

**Reading `landscape_sp.json` (format 2).** Every document starts with the same core block:

| key | this run |
|---|---|
| `format` | `2` |
| `task` | `"sp"` |
| `status` / `status_name` | `0` / `"ok"` |
| `converged` | `true` |
| `n_atoms` | `30` |
| `energy` | `-5.23737712440669227E+001` (hartree, same number as the log) |
| `geometry` | `unit: "bohr"`, `symbols`, `coordinates` |
| `provenance` | `oxtb_version 0.1.0`, `engine_version 6.7.1`, `commit c712f9e...`, `command_line`, `method "GFN2-xTB"`, `charge 0`, `spin 0`, `input_file` |
| `counters` / `values` / `flags` / `history` | task-specific; here `values.gnorm = 8.23123538718708572E-004` |

The block order is fixed, so one parser reads every task's document (sp, opt, scan, ts, irc, vib).

**Reading the other files.** `oxtb.log` is the full stdout+stderr of the command (setup, SCF
table, orbital energies, the `SUMMARY` block with the total energy, charges and bond orders).
`xtbtopo.mol`, `charges`, `wbo` and `xtbrestart` are the usual byproducts and are not committed
here. The structures README quotes the same energy (`-52.373771244067 Eh`), so this folder agrees
with the shared fixtures.

**Reproduce.**

```bash
cd examples/sp/sp-01-gfn2-single-point-json
rm -f oxtb.log landscape_sp.json xtbtopo.mol charges wbo xtbrestart
./run.sh
grep 'TOTAL ENERGY' oxtb.log
```

Deleting the outputs and re-running reproduces `landscape_sp.json` **byte for byte**
(sha256 `af01c3e8…`); the log differs only in timestamps and the random seed.
