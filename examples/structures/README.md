# Shared example structures for the o-xtb landscape suite

These are the validated starting materials for the worked examples of the landscape suite
(`--lopt`, `--lscan`, `--lts`, `--lirc`, `--lvib`).  Every system is a **GFN2-xTB** job of
**30-50 atoms** whose single point finishes in well under 10 s at `OMP_NUM_THREADS=1`
(measured 0.03 s each), and every system has a **well-defined reaction coordinate with a genuine
transition state** that shows **exactly one significant imaginary frequency**.

All commands below were run with `OMP_NUM_THREADS=1` against the **installed static release**
`/home/owenchan/programs/o-xtb/bin/oxtb` (`oxtb --version` -> `OxTB version 0.1.0`,
`xTB version 6.7.1`, `Compiled on 2026/10/12 from c712f9e`; a self-contained copy is kept at
`/tmp/lane-structures/oxtb`).  The numbers were first produced with a build of the same source at
HEAD `4576b9a` and were re-checked bitwise against this release; they are reproduced verbatim in
`docs/_simplify-recon/141-example-structures.md`.

Conventions used in the tables: energies in hartree, frequencies in cm^-1, wall times as measured.

---

## 1. `anthracene_maleic_anhydride/` — Diels-Alder, 33 atoms

**Chemistry.**  Anthracene (C14H10, 24 atoms) + maleic anhydride (C4H2O3, 9 atoms) = **33 atoms**.
The dienophile adds across the meso carbons C9/C10 of the central ring and forms two new C-C
bonds; the two outer rings stay aromatic and the adduct is the 9,10-cycloadduct.

**Reaction coordinate.**  The two forming bonds `C9-C28` and `C10-C29` (atom numbering of
`reactant.xyz`: anthracene 1-24, maleic anhydride 25-33; C9 = 7, C10 = 10, the two vinyl carbons of
maleic anhydride are 28 and 29).  They are symmetry-equivalent, so the reaction is synchronous.

**Files.**

| file | what | E / Eh | notes |
|---|---|---|---|
| `reactant.xyz` | the two separated molecules (GFN2 minimum) | -56.821809 | the fragments are 12.6 A apart |
| `product.xyz`  | the 9,10-cycloadduct (GFN2 minimum) | -56.913775 | new bonds 1.555 A |
| `ts_guess.xyz` | the Diels-Alder saddle | -56.834192 | forming bonds 2.315 A, 1 imaginary mode |

**Validated commands (measured).**

```bash
oxtb reactant.xyz --gfn 2 --sp
#   TOTAL ENERGY -56.821808533251 Eh      wall time 0.036 s
oxtb reactant.xyz --gfn 2 --lopt --lopt-engine lbfgs --lopt-level normal
#   converged: T   final energy -56.821808944025 Eh   (11 steps, 0.07 s)
oxtb ts_guess.xyz --gfn 2 --lvib
#   eigval: -308.68  43.31  79.73 ...      # imaginary freq. 1
#   found 1 significant imaginary frequency
oxtb ts_guess.xyz --gfn 2 --lts --lts-method dimer --lts-level normal --lts-max-steps 60
#   from ts_guess directly, shipped defaults: drifts to a higher-order saddle
#   (3 imaginary modes) at -56.506 Eh - reported honestly
# from ts_guess displaced 0.15 A along the forming direction (see "dimer note" below),
# with --lts-delta 0.1 --lts-ninit force --lts-max-steps 150:
#   converged: T   first order saddle point   final energy -56.834165 Eh
oxtb ts_guess.xyz --gfn 2 --lirc --lirc-method hpc --lirc-max-steps 40 \
     --lirc-step 0.4 --lirc-grad-tol 1e-4
#   forward 40 points -> -56.9126 Eh (the product)
#   backward 13 points -> minimum -56.8391 Eh (a pre-reactive complex)
#   (with the default --lirc-step 0.1 / --lirc-grad-tol 1e-3 the walk stops after 1 point;
#    the -308 cm-1 mode is soft, see "IRC note" below)
oxtb product.xyz --gfn 2 --lscan --lscan-coord distance --lscan-atoms 7,28 \
     --lscan-step 0.1 --lscan-nstep 17 --lscan-level normal --lscan-max-steps 150
#   35 frames, d(C9-C28) 1.555 -> 3.251 A, forward branch monotone rising (-56.9138 -> -56.8239)
```

**Recommended use.**  The chain system: `--lopt` -> `--lscan` -> `--lts` -> `--lirc`.  It is also
the best `--lts --lts-method prfo` example (the delivered `ts_guess.xyz` is the P-RFO-converged
saddle, so it is a hard test for the search: the search starts at the answer).

---

## 2. `benzoic_acid_dimer/` — concerted double proton transfer, 30 atoms

**Chemistry.**  Two benzoic acid molecules (2 x C7H6O2) = **30 atoms** in the planar C2h
hydrogen-bonded dimer.  Both O-H...O=C hydrogen bonds exchange their protons **concertedly**; the
reaction is its own reverse (the two monomers swap protons and the species is unchanged), so this
is a **degenerate** reaction and `product.xyz` is geometrically identical to `reactant.xyz`.

**Reaction coordinate.**  The two hydroxyl protons `H10` and `H25` (donors `O9`/`O24`, acceptors
`O23`/`O8`; atom numbering of `reactant.xyz`: molecule A 1-15, molecule B 16-30).  `O...O = 2.65 A`
in the dimer.

**Files.**

| file | what | E / Eh | notes |
|---|---|---|---|
| `reactant.xyz` | the C2h dimer (GFN2 minimum) | -52.373771 | O-H 1.01 A, H...O 1.65 A |
| `product.xyz`  | the proton-transferred dimer (**same species**) | -52.373771 | degenerate by symmetry |
| `ts_guess.xyz` | the concerted transfer TS guess | -52.360890 | O-H 1.17 A, H...O 1.48 A, 1 imaginary mode |

**Validated commands (measured).**

```bash
oxtb reactant.xyz --gfn 2 --sp
#   TOTAL ENERGY -52.373771244067 Eh      wall time 0.026 s
oxtb reactant.xyz --gfn 2 --lopt --lopt-engine lbfgs --lopt-level normal
#   converged: T   final energy -52.373771818978 Eh
oxtb ts_guess.xyz --gfn 2 --lvib
#   eigval: -715.91  20.07  22.87 ...      # imaginary freq. 1
#   found 1 significant imaginary frequency
oxtb ts_guess.xyz --gfn 2 --lts --lts-method dimer --lts-level normal --lts-max-steps 120 \
     --lts-delta 0.1 --lts-ninit force --lts-rot-max-iter 30
#   from a start displaced 0.15 A along the transfer coordinate:
#   converged: T   first order saddle point   final energy -52.363968 Eh  (1 imaginary mode)
oxtb ts_guess.xyz --gfn 2 --lirc --lirc-method hpc --lirc-max-steps 40
#   forward 6 points -> minimum -52.373772 Eh
#   backward 5 points -> minimum -52.373774 Eh      (both directions walk; the two minima
#                                                     are the degenerate reactant/product)
oxtb reactant.xyz --gfn 2 --lscan --lscan-coord distance --lscan-atoms 9,10 \
     --lscan-step 0.05 --lscan-nstep 25 --lscan-level normal --lscan-max-steps 150
#   51 frames of d(O9-H10) 1.008 -> 2.254 A; the profile has a maximum of -52.3639 Eh at
#   d(O9-H10) = 1.25 A (barrier 6.2 kcal/mol) and returns to -52.3737 Eh when the proton has
#   hopped to O23 -- a genuine transfer barrier, not a monotone ramp
```

**Recommended use.**  The cleanest `--lts --lts-method dimer` example: the dimer converges to a
first-order saddle in ~10 s.  It is also a good `--lirc` example (both endpoints are reached with
the default settings) and the `--lscan` example that shows a real barrier.

---

## 3. `ptoluic_acid_dimer/` — double proton transfer with methyl rotors, 36 atoms

**Chemistry.**  Two p-toluic acid molecules (2 x C8H8O2) = **36 atoms**, the same C2h dimer and the
same concerted (degenerate) double proton transfer as system 2, but with two para methyl groups
whose rotations add soft modes.

**Files.**

| file | what | E / Eh | notes |
|---|---|---|---|
| `reactant.xyz` | the C2h dimer (GFN2 minimum) | -58.717330 | O...O 2.65 A |
| `product.xyz`  | the proton-transferred dimer (**same species**) | -58.717330 | degenerate by symmetry |
| `ts_guess.xyz` | the concerted transfer TS guess | -58.704720 | 1 imaginary mode |

**Validated commands (measured).**

```bash
oxtb reactant.xyz --gfn 2 --sp
#   TOTAL ENERGY -58.717329795725 Eh      wall time 0.032 s
oxtb reactant.xyz --gfn 2 --lopt --lopt-engine lbfgs --lopt-level normal
#   converged: T   final energy -58.717330162090 Eh
oxtb ts_guess.xyz --gfn 2 --lvib
#   eigval: -710.74  15.29  17.03 ...      # imaginary freq. 1
#   found 1 significant imaginary frequency
oxtb ts_guess.xyz --gfn 2 --lirc --lirc-method hpc --lirc-max-steps 40
#   forward 6 points -> minimum -58.717326 Eh
#   backward 5 points -> minimum -58.717328 Eh
```

**Recommended use.**  A larger variant of system 2 for timing/scaling examples.  **The dimer
method does not converge on it** (it drifts to higher-order saddles; the methyl rotations add
several soft modes) — use system 2 or 1 when the example needs `--lts --lts-method dimer`.

---

## Notes for the example lanes

**Atom counts.**  33 / 30 / 36; all within the requested 30-50 range and all GFN2 single points
run in ~0.03 s at `OMP_NUM_THREADS=1`.

**Dimer note.**  The `--lts --lts-method dimer` search converges reliably only when it is **not**
started exactly at a stationary point.  Starting from `ts_guess.xyz` (gradient ~0) the finite
difference curvature is ill-defined and the search drifts to a higher-order saddle.  The working
recipe used above is to displace the reaction coordinate by ~0.15 A first and to raise the dimer
separation to its default-sized value:

```bash
oxtb <ts_guess displaced along the reaction coordinate> --gfn 2 \
     --lts --lts-method dimer --lts-level normal --lts-max-steps 150 \
     --lts-delta 0.1 --lts-ninit force --lts-rot-max-iter 30
```

The displaced start is *not* part of the delivered files; the example lane can build it by moving
the two forming bonds (system 1) or the two transferring protons (system 2) by 0.15 A.

**IRC note.**  For a **soft** imaginary mode (system 1, -309 cm^-1) the default
`--lirc-grad-tol 1e-3` fires at the first point because the gradient is still below the threshold
0.05 bohr*amu^1/2 away from the saddle.  Use `--lirc-step 0.4 --lirc-grad-tol 1e-4` for system 1;
systems 2 and 3 (stiff modes, -711/-716 cm^-1) work with the defaults.

**Degeneracy.**  Systems 2 and 3 are symmetric double proton transfers, so the reactant and the
product are the same species; the IRC walks to two symmetry-equivalent minima.  `product.xyz` is
provided as the identical geometry so that every lane can use the same three-file convention.

**Scan coordinates (written down).**

| system | file | coordinate | range | profile |
|---|---|---|---|---|
| 1 | `product.xyz` | `distance` atoms `7,28` = C9...C28 | 1.555 -> 3.251 A | monotone rising |
| 2 | `reactant.xyz` | `distance` atoms `9,10` = O9-H10 | 1.008 -> 2.254 A | barrier at 1.25 A |
| 3 | `reactant.xyz` | `distance` atoms `9,10` = O9-H10 | (same construction) | barrier |

The per-system notes `anthracene_maleic_anhydride/scan_coordinate.md` and
`benzoic_acid_dimer/scan_coordinate.md` spell the coordinate definition, the atom indices and the
measured profile out in full.
