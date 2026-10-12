# ts-02 — the chain-of-states band family, and where it does not work

**System.** The **33-atom** Diels-Alder system
(`examples/structures/anthracene_maleic_anhydride`): anthracene (24 atoms) + maleic anhydride
(9 atoms) forming the 9,10-cycloadduct.  The two forming bonds are `C9-C28` and `C10-C29`.

**Files.**  `product.xyz` is the cycloadduct minimum (-56.913775 Eh).  `ts_guess.xyz` is the
delivered Diels-Alder saddle (-56.834192 Eh, one imaginary mode).  `reactant.xyz` is the delivered
separated-reactant minimum (-56.821809 Eh).  `precomplex.xyz` is a constructed **pre-reactive
complex**: the same 33 atoms with the maleic anhydride placed 3.5 A above the anthracene ring, in
the product orientation (built from `product.xyz`, not relaxed - see below).

**What it shows.**  Three things, in order of usefulness.

1. **A working band.**  `product.xyz -> ts_guess.xyz` is the compact leg of the reaction (the two
   forming bonds shorten from 1.555 A to 2.315 A).  NEB and CI-NEB both converge on it and confirm a
   first-order saddle.
2. **The physics.**  The GFN2 saddle (-56.834192) lies **below** the separated reactant
   (-56.821809), so the association leg `reactant.xyz -> product.xyz` is essentially barrierless and
   is *not* the band to run; the band that matters on the product side is the one that climbs to the
   saddle.
3. **An honest failure.**  The full `reactant.xyz -> product.xyz` band does **not** converge for any
   method with the shipped defaults - the record is kept in `neb-full.log`.

## 1. The band that works: `product.xyz -> ts_guess.xyz`

**Command** (`run.sh`, runs 1 and 2):

```bash
export OMP_NUM_THREADS=1
export XTBPATH=<repository root>
oxtb product.xyz --gfn 2 --lts --lts-method neb   --lts-product ts_guess.xyz --lts-images 9 --lts-level normal --lts-max-steps 200
oxtb product.xyz --gfn 2 --lts --lts-method cineb --lts-product ts_guess.xyz --lts-images 9 --lts-level normal --lts-max-steps 200
```

| run | method | images | converged | barrier / kcal/mol | saddle confirmation | wall time |
|---|---|---|---|---|---|---|
| 1 | NEB | 9 | **T** | **31.92** (highest internal image 8, -56.862908) | 1 imaginary, **-345.38 cm^-1** | 8.6 s |
| 2 | CI-NEB | 9 | **T** | **49.87** (climbing image 8, -56.834307) | 1 imaginary, **-360.45 cm^-1** | 10.0 s |

The reference barrier is **TS - product = -56.834192 - (-56.913775) = +49.94 kcal/mol**, and it is
also the energy of the `ts_guess.xyz` endpoint (image 9, 49.94 kcal/mol above the product).  Plain
NEB places its **internal** highest image a little short of the saddle (31.92 kcal/mol) because the
saddle sits on the fixed endpoint; CI-NEB's climbing image reaches it (49.87).  Use CI-NEB when the
saddle is near an endpoint.

`local-neb.path.xyz` / `local-cineb.path.xyz` hold the 9 frames (frame 1 the product, frame 9 the
TS), one `energy:` per frame; `local-*.xtbts.xyz` is the confirmed saddle candidate.

(Wall times: runs 1-2 print a wall-time line in their logs; runs 3-5 end through an error path
before that line, so their times were measured with `time` around the same command.)

**Other methods on the same leg (honest record).**  `--lts-method string` (run 3) converges to the
path but its highest node relaxes to a **minimum** (0 imaginary modes) - it does not confirm a
saddle here; `local-string.path.xyz` and `local-string.path_ts_list.xyz` are written anyway.

## 2. Why the pinned `reactant.xyz -> product.xyz` band fails

**Command** (`run.sh`, run 4):

```bash
oxtb reactant.xyz --gfn 2 --lts --lts-method neb --lts-product product.xyz --lts-images 9 \
     --lts-level normal --lts-max-steps 100
```

**Root cause, in one paragraph a reader can act on.**  `reactant.xyz` has the two fragments
**12.6 A apart and coplanar** (both in the `z = 0` plane), while `product.xyz` needs the anhydride
**lifted out of plane and rotated** above the ring (maleic-anhydride centroid `z = +2.75`).  The
Cartesian/IDPP interpolation between those two endpoints has no way of representing the
out-of-plane rotation, so it walks the images straight **through** the anthracene; the SCC then
fails on the overlapping frames.  The symptom is a nonsense "highest image" that is far above both
endpoints: **260.04 kcal/mol** (image 3, -56.407402) for the 9-image NEB in `neb-full.log`;
**484.59 kcal/mol** for the 15-image NEB and CI-NEB in `neb-full15.log` / `cineb-full15.log`; and
**833.54 kcal/mol** for the 15-image NEB with `--lts-no-align` in `neb-full15-noalign.log`.  The
string variant (run 3) confirms a minimum rather than a saddle; `gsm` aborts immediately
("no progress", `gsm-full.log`, 0.7 s); AutoNEB aborts (a band image cannot be evaluated,
`autoneb-full.log`, 2.8 s).  This is a limitation of the interpolation for a large-amplitude
association, not a budget issue: more images, more steps, `--lts-no-idpp` and `--lts-no-align` were
all tried.

**Why the separated pair is the wrong endpoint anyway.**  The GFN2 saddle is *below* the separated
reactant, so there is no barrier to find on that leg; a band run there is looking for something that
does not exist.

## 3. The chemically correct endpoint: `precomplex.xyz -> product.xyz`

**Command** (`run.sh`, run 5):

```bash
oxtb precomplex.xyz --gfn 2 --lts --lts-method neb --lts-product product.xyz --lts-images 11 \
     --lts-level normal --lts-max-steps 300
```

This band **converges** (`f_rms_avg 2.9e-04`) to a **monotone downhill** path from the pre-complex
(-56.634058) to the product (-56.913775); the per-image energies are in `neb-precomplex.log`.  There
is **no barrier** on this leg, so the `TS candidate` (the band's highest image, -56.806547) is not a
real transition state and the confirmation reports a higher-order saddle (3 imaginary modes).  In
other words: the association and the bond formation are barrierless in GFN2; only the product-side
retro barrier (49.94 kcal/mol to `ts_guess.xyz`) is real.

**Is `precomplex.xyz` a minimum?**  No - it is only a starting point.  A plain minimisation (run 6,
`precomplex-opt.log`) drops it to **-56.823545 Eh** in 1.2 s, i.e. back into the separated-reactant
well (compare `reactant.xyz` at -56.821809).  It is a hand-built geometry, shipped as the endpoint
that removes the 12.6 A gap and the out-of-plane rotation.

**How to read the output files.**

* `*.log` - full stdout+stderr of each run (`oxtb.log` is the `product -> ts_guess` NEB transcript).
* `local-neb.path.xyz`, `local-cineb.path.xyz`, `precomplex-neb.path.xyz` - the bands (one xyz frame
  per image, frame 1 / frame n the two endpoints; every frame's comment carries `energy:`).
* `local-*.xtbts.xyz` / `*.xtbts.log` - the saddle candidate and its confirmation summary.
* `precomplex-opt.log` - the minimisation that shows `precomplex.xyz` is not a minimum.
* `neb-full.log` - the honest record of the pinned, non-converging full-reaction band (9 images);
  `neb-full15.log`, `cineb-full15.log`, `neb-full15-noalign.log` - the same band with 15 images;
  `gsm-full.log`, `autoneb-full.log` - the two methods that abort outright.
