# Worked examples for the o-xtb landscape task suite

Fourteen runnable examples of the potential-energy-surface task suite (`--sp`, `--lopt`, `--lscan`,
`--hess`/`--lvib`, `--lts`, `--lirc`), two per task, plus two multi-task chains.  Every example is a
complete little case: the input geometry, the exact command line, the captured output, the natural
output files, and a README that says what it shows and how to read the result.

Every system is a **30-33 atom GFN2-xTB** job that finishes in seconds to a couple of minutes at
`OMP_NUM_THREADS=1`.  Every number quoted in a case README is a line in that case's captured log -
the logs are the record, and they ship with the case.

The examples were produced with the installed release:

```
OxTB version 0.1.0   (xTB engine 6.7.1)   Compiled on 2026/10/12 from c712f9e
```

## How to run a case

```bash
cd examples/lopt/lopt-01-lbfgs-from-distorted
export XTBPATH=/path/to/o-xtb/source          # or use an installed tree; --gfn 2 needs no file
export OMP_NUM_THREADS=1                       # the examples were measured single-threaded
bash run.sh                                    # the exact command the README documents
```

`run.sh` prints the command it runs and writes the same output file names you find in the folder, so
you can diff your run against the shipped one.  The cases are deterministic: the two saddle and band
cases were re-run from clean directories and every number reproduced byte for byte.

## Layout

```
examples/
  README.md                 this index
  structures/               the shared 30-36 atom systems and their reaction coordinates
  sp/    sp-01-... sp-02-...       single points and the machine-readable document
  lopt/  lopt-01-... lopt-02-...   minimisation, two engines
  lscan/ lscan-01-... lscan-02-... relaxed scans, 1D and 2D
  hess/  hess-01-... hess-02-...   numerical Hessian, and the model Hessian against it
  ts/    ts-01-... ts-02-...       saddle searches: PRFO/B-PRFO/dimer, and the band family
  vib/   vib-01-... vib-02-...     thermochemistry of a minimum, imaginary mode of a saddle
  irc/   irc-01-... irc-02-...     four IRC integrations, and the direction convention
  chains/ chain-01-... chain-02-...  multi-task workflows on one structure
```

Each case folder holds `input.xyz` (plus any extra inputs), `run.sh`, one or more captured logs,
the output files with their natural names (`xtbopt.xyz`, `xtbscan.log`, `hessian`, `vibspectrum`,
`path.xyz`, `irc_forward.xyz`, `landscape_<task>.json`, ...), and `README.md`.

The category `.gitignore` files re-include those output names, which the repository-wide
`.gitignore` excludes elsewhere - that is what makes the examples self-contained.

## The cases

| category | case | system (atoms) | what it shows |
|---|---|---|---|
| `sp` | `sp-01-gfn2-single-point-json` | benzoic acid dimer (30) | one GFN2 single point with `--ljson`: energy, gap, and the unified document |
| `sp` | `sp-02-method-comparison` | benzoic acid dimer (30) | the same geometry at `--gfn 0/1/2/ff` - and why the four numbers are not comparable |
| `lopt` | `lopt-01-lbfgs-from-distorted` | anthracene + maleic anhydride (33) | L-BFGS from a deliberately distorted geometry: 41 steps, -0.956420 Eh |
| `lopt` | `lopt-02-rfo-from-distorted` | anthracene + maleic anhydride (33) | RFO with the model Hessian on the same start: 24 steps, 5 Hessian builds |
| `lscan` | `lscan-01-distance-relaxed` | anthracene + maleic anhydride (33) | bidirectional relaxed scan of the forming C9-C28 bond: 35 frames, hysteresis 1.7e-04 Eh |
| `lscan` | `lscan-02-dihedral-2d` | benzoic acid dimer (30) | relaxed 2D scan of the two proton transfers: concerted (6.05 kcal/mol) versus stepwise (23.9) |
| `hess` | `hess-01-numerical` | benzoic acid dimer (30) | numerical Hessian of a minimum: 84 modes, 6 projected zero modes, ZPE and G(T) |
| `hess` | `hess-02-model-vs-numerical` | benzoic acid dimer (30) | Lindh-D2 model Hessian against the numerical one: 1 versus 181 energy evaluations |
| `ts` | `ts-01-prfo-bprfo-dimer` | benzoic acid dimer (30) | three saddle searches agreeing to 8e-6 Eh, and their shipped-default failures |
| `ts` | `ts-02-band-family` | anthracene + maleic anhydride (33) | NEB and CI-NEB on a working band, and a documented failure of the same family |
| `vib` | `vib-01-minimum-thermochemistry` | benzoic acid dimer (30) | frequencies, ZPE, H(T) and G(T) of a minimum, and the temperature dependence |
| `vib` | `vib-02-imaginary-mode-at-the-ts` | benzoic acid dimer (30) | the single imaginary mode of an optimised saddle and the non-minimum flags |
| `irc` | `irc-01-four-methods` | benzoic acid dimer (30) | one saddle, four integrations: `hpc`, `lqa`, `eulerpc`, `gs` |
| `irc` | `irc-02-direction-and-swap` | benzoic acid dimer (30) | `--lirc-oneway` and `--lirc-swap`: what forward and backward actually mean |

## The chains

A chain carries one structure through several tasks, so you can see which file each step consumes
from the previous one.

| chain | steps |
|---|---|
| `chain-01-lopt-scan-dimer-ts-irc` | `00-structure` -> `01-lopt` -> `02-lscan` -> `03-dimer` -> `04-ts` -> `05-irc` |
| `chain-02-band-to-irc` | `00-endpoints` -> `01-band` -> `02-refine` -> `03-irc` |

Every step is itself a complete case folder with its own `run.sh`, log and README; the chain README
ties them together and gives the energy at each step.  `chain-01` shows the dimer and PRFO routes to
the same saddle; `chain-02` shows how to take the saddle out of a band (`path_ts_list.xyz`) and feed
it to the IRC.

## The shared structures

`structures/README.md` documents each system: atom count, chemistry, the reaction coordinate with
its atom indices, the validated command lines, and which tasks it suits.  Read it before writing a
new case - the atom numbering there is the numbering every case README uses.

| system | atoms | reaction |
|---|---|---|
| `anthracene_maleic_anhydride` | 33 | Diels-Alder across the meso carbons; **distinct** endpoints, the only band-capable system |
| `benzoic_acid_dimer` | 30 | concerted double proton transfer; **degenerate** (product is the same species) |
| `ptoluic_acid_dimer` | 36 | the same reaction on a larger monomer; also degenerate |

## Caveats worth knowing before you copy a recipe

* **A band needs endpoints that differ by a smooth motion.**  `ts-02` documents what happens when
  they do not: the separated fragments sit 12.6 A apart and coplanar while the product needs an
  out-of-plane rotation, so the Cartesian/IDPP interpolation walks the images through the ring and
  the SCC blows up (the pathological "highest image" barriers are 260 / 484 / 834 kcal/mol in the
  shipped logs).  The same case shows the fix: start from a pre-reactive complex.
* **Some saddle searches need tuning on these systems.**  `ts-01` reports, with logs, that B-PRFO
  and the dimer method reach a higher-order saddle from the shipped `ts_guess.xyz` with the shipped
  defaults, and what it took to reach the first-order saddle instead.
* **The model Hessian is a cheap approximation, not a replacement** - `hess-02` quantifies both the
  cost (1 versus 181 energy evaluations) and the damage (an O-H frequency off by ~1000 cm-1).
* **The acid dimers are degenerate reactions.**  That is ideal for a saddle search and for showing
  that the IRC directions are what the flags say, and useless for a band: a band between identical
  endpoints has nothing to interpolate.
* **The logs ship with the cases on purpose.**  If a README claims a number, that number is a line
  in the log next to it; if you edit a case, re-run it and update both.
