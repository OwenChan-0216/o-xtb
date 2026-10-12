# Scan coordinate

**1D relaxed scan of the transferring proton.**

* input geometry: `reactant.xyz` (the C2h dimer, O9-H10 = 1.008 A)
* `--lscan-coord distance`
* `--lscan-atoms 9,10` (1-based: atom 9 = hydroxyl O of molecule A, atom 10 = its proton;
  the acceptor is atom 23 = the carbonyl O of molecule B)
* `--lscan-step 0.05`, `--lscan-nstep 25` -> d(O9-H10) sweeps 1.008 -> 2.254 A
* `--lscan-level normal --lscan-max-steps 150`

Measured profile (51 frames): the energy rises from -52.3738 Eh to a maximum of **-52.3639 Eh at
d(O9-H10) = 1.25 A** (barrier **6.2 kcal/mol**), then falls back to -52.3737 Eh once the proton
has hopped to the acceptor oxygen.  This is the proton-transfer barrier of the concerted double
transfer; it is the *asymmetric* single-proton path (only H10 is constrained, H25 is free).

Full command:

```bash
oxtb reactant.xyz --gfn 2 --lscan --lscan-coord distance --lscan-atoms 9,10 \
     --lscan-step 0.05 --lscan-nstep 25 --lscan-level normal --lscan-max-steps 150
```

The same construction applies to `ptoluic_acid_dimer/` (36 atoms), whose numbering is identical
for molecule A (atoms 1-18) and shifts molecule B to atoms 19-36 (acceptor O = 26).
