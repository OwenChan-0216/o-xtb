# Transition states

The `--lts` run type searches a first-order saddle point, or an entire
minimum-energy path when a band method is selected.  The method is chosen with
`--lts-method NAME` (alias `--method NAME`); the name is not case-sensitive.

```bash
oxtb hcn.xyz --gfn 2 --lts --lts-method prfo
```

## Method families

**Saddle searches.** These start from a geometry near the saddle (or from a
minimum with an escape walk) and walk to the stationary point:

| Method | Notes |
|---|---|
| `prfo` | the default; partitioned rational function optimisation |
| `bprfo` | `prfo` with a restricted (trust-region) step |
| `dimer` | first derivatives only, needs no Hessian; works directly from a minimum |

`prfo` and `bprfo` build a Hessian (`--lts-hessian`: `numerical`, `model` or
`file`).  `--lts-target-mode` and `--lts-init-mode` select the mode to follow;
`--lts-escape-step` controls the escape walk that is needed when the start is a
minimum (set it to `0` to disable).

**Chain-of-states methods.** These build and relax a path of images between two
endpoints and need a product endpoint with `--lts-product FILE` (one XYZ frame,
same atoms in the same order):

| Method | Notes |
|---|---|
| `neb` | nudged elastic band |
| `cineb` | climbing-image NEB; ignites the climbing image when the band force falls below `--lts-climb-switch` |
| `autoneb` | incremental path building; bounds with `--lts-autoneb-nstart` and `--lts-autoneb-max-paths` |
| `string`, `gsm` | growing string method |

The band is sized with `--lts-images N`; the spring constants are dynamic
unless `--lts-no-dynamic-k` is given.

## Output

| File | Written by |
|---|---|
| `xtbts.xyz`, `xtbts.log` | every `--lts` run (the saddle found, or the highest image) |
| `path.xyz` | the band methods `neb`, `cineb`, `string`, `gsm` |
| `path_autoneb.xyz`, `path_ts_list.xyz` | `autoneb` |

An NH3 inversion path between two pyramidal geometries, built with `cineb` and
five images, converges and writes a five-frame `path.xyz`.

!!! note "To be written"
    Worked examples (a Müller-Brown saddle, an HCN/HNC saddle) and the
    recommended method for each situation are not written yet.
