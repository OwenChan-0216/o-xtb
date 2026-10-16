# chain-02 — band -> saddle -> IRC on the Diels-Alder system

**System.** The **33-atom** Diels-Alder system (`examples/structures/anthracene_maleic_anhydride`):
anthracene + maleic anhydride -> 9,10-cycloadduct.  A short chain that takes a transition state out
of a chain-of-states band and feeds it to the IRC.

**What it shows.**  The band -> saddle -> IRC hand-off: `--lts --lts-method cineb` writes the
confirmed saddle candidate to `xtbts.xyz`, a P-RFO step refines it onto the true saddle, and
`--lirc --lirc-method hpc` integrates from there to the two endpoints of the reaction.  It also
shows, honestly, that the **raw** band candidate is not good enough to start an IRC.

## Step table

| step | folder | consumes | command | produces | headline number | wall time |
|---|---|---|---|---|---|---|
| 00 | `00-endpoints/` | - | - | `product.xyz`, `ts_guess.xyz`, `reactant.xyz` | product -56.913775 Eh | - |
| 01 | `01-band/` | `../00-endpoints/product.xyz` + `--lts-product ../00-endpoints/ts_guess.xyz` | `--lts --lts-method cineb --lts-images 9 --lts-level normal` | `xtbts.xyz`, `path.xyz` | **barrier 49.87 kcal/mol** (image 8, -56.834307) | 5.8 s |
| 02 | `02-refine/` | `../01-band/xtbts.xyz` | `--lts --lts-method prfo --lts-level normal` | `xtbts.xyz` | **-56.834192216439 Eh**, 1 imaginary (-308.92 cm^-1) | 8.5 s |
| 03 | `03-irc/` | `../02-refine/xtbts.xyz` | `--lirc --lirc-method hpc --lirc-step 0.4 --lirc-grad-tol 1e-4` | `irc_forward/backward/path.xyz`, `irc.log` | 13 / 51 points, endpoints -56.8391 / -56.9138 | 9.4 s |

Total wall time ~24 s at `OMP_NUM_THREADS=1`.

## What flows into what

```
00-endpoints/product.xyz  --(--lts-product)-->  00-endpoints/ts_guess.xyz
        |
        v   (01-band, CI-NEB)
01-band/xtbts.xyz    -56.834307439160 Eh  (the band's confirmed saddle candidate)
01-band/path.xyz     9 band frames
        |
        v   (02-refine, P-RFO)
02-refine/xtbts.xyz  -56.834192216439 Eh  (the true first-order saddle)
        |
        v   (03-irc, hpc)
03-irc/irc_forward.xyz  -> pre-reactive complex -56.839109784760 Eh
03-irc/irc_backward.xyz -> product             -56.913763098223 Eh
```

**Which file holds the transition state?**  For plain NEB / CI-NEB the confirmed candidate is
`xtbts.xyz` (the band itself is `path.xyz`).  `path_ts_list.xyz` - "every saddle candidate found,
with its energy and imaginary mode count" - is written by **AutoNEB and the string method**, not by
plain NEB/CI-NEB; the naming convention is the same (`--namespace` prefixes it).

## The honesty note this chain exists to make

**The raw band candidate is not a usable transition state.**  `01-band/xtbts.xyz` (-56.834307,
imaginary mode -360.45 cm^-1) looks like a saddle and passes the band's own confirmation, but an IRC
started from it returns to the **product in both directions** (measured: both halves end near
-56.9138 Eh).  Only after the 3-step P-RFO refinement in `02-refine/` - which moves it 1.15e-4 Eh and
turns the imaginary mode into the reaction coordinate, -308.92 cm^-1 - does the IRC split into the
pre-reactive complex and the product.  A band gives you a starting point, not a finished saddle;
always refine before an IRC.

Two more bounds, stated plainly:

* The full `reactant -> product` band does **not** converge at all (the fragments start 12.6 A apart
  and coplanar); this chain uses the compact `product -> ts_guess` leg, which does.  The full record
  is in `examples/ts/ts-02-band-family`.
* `03-irc` needs `--lirc-step 0.4 --lirc-grad-tol 1e-4`: the -309 cm^-1 mode is soft, so the default
  `--lirc-step 0.1 --lirc-grad-tol 1e-3` stops after one point.
