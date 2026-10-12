# vib-01 — frequencies and thermochemistry of a relaxed minimum

**System.** The **30-atom** benzoic-acid dimer minimum
(`examples/structures/benzoic_acid_dimer/reactant.xyz`, = `input.xyz`).  GFN2 single point
-52.373771244067 Eh.

**What it shows.**  `--lvib` on a genuine minimum: the full frequency list, the zero-mode count, the
zero-point energy, and H(T) / G(T) at two temperatures.  It is also the reference the TS case
(`examples/vib/vib-02-imaginary-mode-at-the-ts`) is compared against.

**Command** (`run.sh`):

```bash
export OMP_NUM_THREADS=1
export XTBPATH=<repository root>
oxtb input.xyz --gfn 2 --lvib --lvib-temp 298.15            # -> oxtb.log, vibspectrum, vib_normal_modes
oxtb input.xyz --gfn 2 --lvib --lvib-temp 1000 --namespace t1000   # -> vib1000.log, t1000.*
```

`--lvib-temp` sets the temperature of the thermochemical table; the Hessian is the suite's own
numerical (central-difference, 5e-3 bohr) Hessian, projected on the 3N-6 internal modes.

**Observed result** (from `oxtb.log` and `vib1000.log`):

| quantity | 298.15 K | 1000 K |
|---|---|---|
| symmetry / modes | C2h, 84 internal, 6 projected zero modes | same |
| imaginary modes | **0** | **0** |
| lowest / highest mode | **14.20** / 3109.48 cm^-1 | same |
| zero point energy | **0.222898 Eh** | 0.222898 Eh |
| total enthalpy H(T) | **-52.133632 Eh** | **-52.012432 Eh** |
| total free energy G(T) | **-52.194895 Eh** | **-52.405684 Eh** |
| total entropy S(T) | 539.48 J/K/mol | 1032.48 J/K/mol |
| wall time | 2.3 s | 2.1 s |

3N-6 = 84 internal modes and 6 projected zero modes (the 3 translations + 3 rotations) sum to the
3N = 90 rows of `vibspectrum`.  The first six rows are the projected rigid motions (0.00 cm^-1); the
first real mode is `14.20 cm^-1`, an intermolecular libration of the hydrogen-bonded dimer.

**Temperature effect.**  ZPE is temperature-independent (0.222898 Eh); only the populated
vibrational/rotational/translational partition functions change.  Going 298.15 -> 1000 K raises
`H(T)` by **+0.121200 Eh = +76.1 kcal/mol** and `G(T)` falls by **-0.210790 Eh** because the
entropy term `T*S` (539.48 -> 1032.48 J/K/mol) grows faster than the enthalpy.

**How to read the output files.**

* `vibspectrum` - the frequency list: one row per mode (`mode`, `symmetry`, `wavenumber cm^-1`,
  `IR intensity`, `selection rule`); rows 1-6 are the projected zero modes.  Read it with any
  thermochemistry program (`thermo`).
* `vib_normal_modes` - the Cartesian displacement of every mode (`$vibrational normal modes`).
* `oxtb.log` - full stdout+stderr: the `eigval :` blocks, the `Thermodynamic Functions` table
  (`temp. partition function enthalpy heat capacity entropy`), then the one-line summary
  (`modes: ... zero point energy: ... total enthalpy H(T): ... total free energy G(T): ...`).
* `g98.out`, `hessian`, `t1000.*` - the Gaussian-style archive, the raw Hessian, and the 1000 K
  outputs (namespaced).
