# irc-02 — the direction convention: `--lirc-oneway` and `--lirc-swap`

**System.** The **30-atom** benzoic-acid dimer saddle (`input.xyz` = the delivered TS guess,
-52.360890 Eh, one imaginary mode).  Both IRC endpoints are the *same* species (the two protons swap,
so the dimer is unchanged by symmetry), which makes it easy to see that a flag moves the integration
and not the answer.

**What it shows.**  Exactly what the two direction flags do, and that the two endpoints really are
the two minima - not a re-labelling of one.

* **default** - both directions are integrated: `forward` (6 points) and `backward` (5 points).
* **`--lirc-oneway`** - only the forward direction is integrated; the backward direction is reported
  as `not requested (--lirc-oneway)`, `backward points: 0`, and **no `irc_backward.xyz` is written**.
* **`--lirc-swap`** - the two directions are exchanged: the *forward* run of the swapped job
  reproduces the *backward* run of the default job point for point (and vice versa), and the summary
  line `directions swapped: T` records it.

**Command** (`run.sh`):

```bash
export OMP_NUM_THREADS=1
export XTBPATH=<repository root>
oxtb input.xyz --gfn 2 --lirc --lirc-method hpc --lirc-max-steps 40                                    # -> oxtb.log
oxtb input.xyz --gfn 2 --lirc --lirc-method hpc --lirc-oneway --lirc-max-steps 40 --namespace oneway
oxtb input.xyz --gfn 2 --lirc --lirc-method hpc --lirc-swap   --lirc-max-steps 40 --namespace swap
```

The direction convention is printed at the top of every run:

```
forward is defined by the largest absolute component of the mass weighted transition vector
phase component:              0.612997 (cartesian 1 of atom 10)
```

so "forward" is fixed by the phase of the transition vector, and `--lirc-swap` reverses that phase.

**Observed result:**

| run | termination forward | forward points | forward endpoint / Eh | termination backward | backward points | backward endpoint / Eh | `directions swapped` | wall time |
|---|---|---|---|---|---|---|---|---|
| default | gradient | 6 | **-52.373672216996** | gradient | 5 | **-52.373672970653** | F | 2.4 s |
| `--lirc-oneway` | gradient | 6 | **-52.373672216996** | *not requested* | 0 | - | F | 1.9 s |
| `--lirc-swap` | gradient | 5 | **-52.373672970653** | gradient | 6 | **-52.373672216996** | T | 2.4 s |

Read the first and third rows together: the swapped job's forward endpoint (-52.373672970653) is
exactly the default job's backward endpoint, and its backward endpoint is exactly the default job's
forward endpoint.  The flag moves the work, it does not change the physics.

The two protons are symmetry-equivalent, so the dominant component of the transition vector that
fixes the phase - and therefore which half is called *forward* - is decided by round-off.  This
release names atom **10** (the pre-refresh release named atom **25**), which is why the *forward*
and *backward* labels here are the opposite way round to the earlier edition; the two endpoints are
the same pair as before.

**How to read the output files.**

* `irc_forward.xyz` / `irc_backward.xyz` / `irc_path.xyz` / `irc.log` - the default run.  Compare
  `swap.irc_forward.xyz` with `irc_backward.xyz`: they hold the same frames.
* `oneway.irc_forward.xyz` / `oneway.irc_path.xyz` - the one-way run; there is deliberately **no**
  `oneway.irc_backward.xyz`.  `oneway.irc_path.xyz` then holds only the forward half (6 frames).
* `*.irc.log` - the one-line-per-quantity summary; grep `forward points`, `directions swapped`,
  `termination backward`.
