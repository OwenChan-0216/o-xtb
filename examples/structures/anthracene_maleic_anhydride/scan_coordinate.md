# Scan coordinate

**1D relaxed scan of the forming C-C bond.**

* input geometry: `product.xyz` (the 9,10-cycloadduct, C9-C28 = 1.555 A)
* `--lscan-coord distance`
* `--lscan-atoms 7,28` (1-based: atom 7 = anthracene C9, atom 28 = the maleic anhydride
  carbon it bonds to; see the numbering in `reactant.xyz`)
* `--lscan-step 0.1`, `--lscan-nstep 17` -> d(C9-C28) sweeps 1.555 -> 3.251 A
* `--lscan-level normal --lscan-max-steps 150`

Measured profile (35 frames, forward branch, `xtbscan.log`): monotone rising from
-56.9138 Eh (bond formed) to -56.8239 Eh (bond broken), i.e. the reverse of the bond-formation
step of the Diels-Alder reaction.

Beyond d(C9-C28) ~ 3.35 A the single-bond scan is no longer monotone: the *other* forming bond
(C10-C29) then breaks and the profile jumps down by 0.014 Eh.  Keep the range at or below 3.25 A.

Full command:

```bash
oxtb product.xyz --gfn 2 --lscan --lscan-coord distance --lscan-atoms 7,28 \
     --lscan-step 0.1 --lscan-nstep 17 --lscan-level normal --lscan-max-steps 150
```
