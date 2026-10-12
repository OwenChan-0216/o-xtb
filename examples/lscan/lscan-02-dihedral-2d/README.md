# lscan-02 — relaxed 2D scan of a double proton transfer

**System.** `benzoic_acid_dimer/reactant.xyz` from `examples/structures` — the C2h benzoic acid
dimer, **30 atoms** (molecule A = atoms 1-15, molecule B = 16-30). The two hydroxyl protons are
**H10** (donor O9 = atom 9) and **H25** (donor O24 = atom 24); `examples/structures/README.md`
§2 names both protons and their donors, and `benzoic_acid_dimer/scan_coordinate.md` validates the
proton-transfer coordinate `d(O9-H10)` = atoms **9,10**.

**What it shows.** A relaxed **2D** scan over the two proton-transfer distances — coordinate 1 is
the validated `d(O9-H10)`, coordinate 2 is its symmetry partner `d(O24-H25)` (atoms **24,25**,
the second proton that `examples/structures/README.md` §2 documents). The grid answers a question a
1D scan cannot: is the double proton transfer **concerted** (both protons move together) or
**stepwise**?

**Why 2D rather than a dihedral.** The benzoic acid dimer is planar and rigid, so a dihedral scan
would only show a nearly free OH rotor. The 2D proton-transfer surface instead separates two
mechanisms with a large energy difference — the instructive picture.

**Command** (`run.sh`):

```bash
export OMP_NUM_THREADS=1
export XTBPATH=<repository root>
oxtb input.xyz --gfn 2 --lscan --lscan-ndim 2 \
    --lscan-coord  distance --lscan-atoms  9,10  --lscan-step  0.125 --lscan-nstep  8 \
    --lscan-coord2 distance --lscan-atoms2 24,25 --lscan-step2 0.125 --lscan-nstep2 8 \
    --lscan-level normal --lscan-max-steps 150 --norestart
```

**Observed result** (`oxtb.log`). Grid 9 x 9 = 81 points, 0 failed. Diagonal (both protons at the
same distance) versus the stepwise edge (one proton far, the other still bonded):

| d(O9-H10) = d(O24-H25) / A | E(diagonal) / Eh | E(one proton far) / Eh |
|---|---|---|
| 1.0077 | -52.373771819 | -52.373771819 |
| 1.1327 | -52.367938434 | -52.370165436 |
| 1.2577 | **-52.364134813** | -52.363217237 |
| 1.3827 | -52.368440969 | -52.357041127 |
| 1.5077 | -52.372399474 | -52.352406309 |
| 1.6327 | -52.373765319 | -52.348125945 |
| 1.7577 | -52.373067460 | -52.343826139 |
| 1.8827 | -52.371153540 | -52.339600775 |
| 2.0077 | -52.368702311 | **-52.335630072** |

| quantity | value |
|---|---|
| corner minimum (1.0077, 1.0077) | -52.373771819 Eh |
| **concerted barrier** (diagonal, at 1.2577 A) | **0.009637 Eh = 6.05 kcal/mol** |
| **stepwise corner** (2.0077, 1.0077) | **0.038143 Eh = 23.9 kcal/mol** above the minimum |
| concerted advantage | **17.9 kcal/mol** |
| lowest grid energy | -52.373771819 Eh at (1.0077, 1.0077) |
| largest jump between consecutive points | 1.202e-02 Eh |
| wall time | **69.4 s** |

The diagonal has a genuine 6.0 kcal/mol barrier at `d = 1.26 A` — the same value the validated 1D
scan reports — and the off-diagonal path that transfers the protons *one at a time* is ~18 kcal/mol
higher everywhere. On this surface the double transfer is **concerted**. (The serpentine warm start
is visible in the `residual` column; the diagonal barrier agrees with the 1D result to ~1e-4 Eh.)

**Reading the output files.** `oxtb.log` prints the header (`coordinate 1`/`coordinate 2`), the
`2D scan grid` table (`coord2 / coord1 / energy / residual`), the lowest grid energy and the largest
jump. `xtbscan.log` holds the 81 frames in evaluation order (serpentine), each with its
`energy: … xtb: … iter: …` comment line.

**Reproduce.**

```bash
cd examples/lscan/lscan-02-dihedral-2d
rm -f oxtb.log xtbscan.log xtbtopo.mol charges wbo xtbrestart
./run.sh
grep -E '2D scan grid|lowest grid' oxtb.log
```

A clean re-run reproduces `xtbscan.log` byte for byte (sha256 `9e77a748…`).
