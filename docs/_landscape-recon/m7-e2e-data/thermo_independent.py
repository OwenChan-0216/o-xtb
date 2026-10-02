#!/usr/bin/env python3
"""Independent thermochemistry recompute for the M7 validation (report 49).

Reads the stdout of `xtb --lvib` / `xtb --hess` (or any xtb run that prints the
RRHO table) plus the geometry file and:

  1. extracts the frequency table, the SETUP block and the thermochemistry,
  2. recomputes ZPE, H(T), G(T), S(T) from the frequencies and the geometry
     with an independent implementation of the same model (rigid rotor -
     harmonic oscillator with the Head-Gordon free-rotor interpolation at
     `rotor cutoff`, translational Sackur-Tetrode at 1 atm, symmetry number
     from the printed SETUP block),
  3. prints the difference to what xtb printed.

The point of the recompute is not to re-derive xtb's numbers bit for bit but
to make a *hidden parameter* (temperature, pressure, frequency scaling, rotor
cutoff, imaginary cutoff, mode count) visible: any of them wrong breaks the
recompute by far more than the model's own numerical noise.
"""
import json
import math
import re
import sys

# --- constants of src/mctc/convert.f90 and src/mctc/mctc_constants.f90 -----
AUTORCM = 219474.63067
RCMTOAU = 1.0 / AUTORCM
AUTOKCAL = 627.50947428
KCALTOAU = 1.0 / AUTOKCAL
AUTOAA = 0.52917726
AATOAU = 1.0 / AUTOAA
AMUTOKG = 1.660539040e-27
METOKG = 9.10938356e-31
KGTOME = 1.0 / METOKG
ATMPA = 101325.0
CALTOJ = 4.184
R = 8.314462618 / CALTOJ        # molar gas constant, cal/(mol K); xtb uses
                                # molar_gas_constant * jtocal
KB_SI = 1.38064852e-23
H_SI = 6.62607015e-34
NAV = 6.02214076e23
AMU_KG = AMUTOKG                # xtb's `amutokg` is exactly this value

# masses of src/mctc/param/atomic_masses.f90
MASS = {"H": 1.007940754, "C": 12.01073590, "N": 14.00670321,
        "O": 15.99940492}


def parse_xyz(path):
    with open(path) as handle:
        lines = handle.readlines()
    nat = int(lines[0].split()[0])
    syms, xyz = [], []
    for line in lines[2:2 + nat]:
        f = line.split()
        syms.append(f[0])
        xyz.append([float(v) for v in f[1:4]])
    return syms, xyz


def parse_output(text):
    """Everything the validation needs out of one xtb stdout."""
    out = {}
    # frequency table: `eigval :` prints 6 per line; the first contiguous
    # block is the projected Hessian block of the run.
    blocks = re.findall(r"(?:^eigval :.*\n)+", text, re.M)
    freqs = []
    if blocks:
        freqs = [float(v) for v in re.findall(r"-?\d+\.\d+", blocks[0])]
    out["eigval"] = freqs

    # SETUP block
    def setup(name):
        m = re.search(r":\s+" + name + r"\s+(.*?)\s+:", text)
        return m.group(1) if m else None

    out["n_freq"] = setup(r"# frequencies")
    out["n_imag"] = setup(r"# imaginary freq\.")
    out["linear"] = setup(r"linear\?")
    out["symmetry"] = setup("symmetry")
    out["rotational_number"] = setup("rotational number")
    out["scaling_factor"] = setup("scaling factor")
    out["rotor_cutoff"] = setup("rotor cutoff")
    out["imag_cutoff"] = setup("imag\. cutoff")

    # temperature block
    m = re.search(r"^\s*(\d+\.\d+)\s+VIB\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)$", text, re.M)
    if m:
        out["temp"] = float(m.group(1))
        out["s_vib_cal"] = float(m.group(5))
    m = re.search(r"^\s*ROT\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)$", text, re.M)
    if m:
        out["s_rot_cal"] = float(m.group(4))
    m = re.search(r"^\s*TR\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)$", text, re.M)
    if m:
        out["s_tr_cal"] = float(m.group(4))
    m = re.search(r"^\s*TOT\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)$", text, re.M)
    if m:
        out["s_tot_cal"] = float(m.group(3))

    # H(T)/Eh table: T, H(0)-H(T)+PV, H(T)/Eh, T*S/Eh, G(T)/Eh
    m = re.search(r"^\s*(\d+\.\d+)\s+(\S+)E([+-]\d+)\s+(\S+)E([+-]\d+)\s+"
                  r"(\S+)E([+-]\d+)\s+(\S+)E([+-]\d+)\s*$", text, re.M)
    if m:
        out["ht"] = float(m.group(2) + "e" + m.group(3))
        out["et"] = float(m.group(4) + "e" + m.group(5))
        out["ts"] = float(m.group(6) + "e" + m.group(7))
        out["gt"] = float(m.group(8) + "e" + m.group(9))

    # THERMODYNAMIC block
    m = re.search(r"total free energy\s+(-?[\d.]+) Eh", text)
    if m:
        out["g_total"] = float(m.group(1))
    m = re.search(r"total energy\s+(-?[\d.]+) Eh", text)
    if m:
        out["e_total"] = float(m.group(1))
    m = re.search(r"zero point energy\s+(-?[\d.]+) Eh", text)
    if m:
        out["zpe"] = float(m.group(1))
    elif re.search(r"zero point energy:\s+(-?[\d.eE+-]+) Eh", text):
        out["zpe"] = float(re.search(r"zero point energy:\s+(-?[\d.eE+-]+) Eh",
                                     text).group(1))
    m = re.search(r"TOTAL ENTHALPY\s+(-?[\d.]+) Eh", text)
    if m:
        out["h_total"] = float(m.group(1))
    m = re.search(r"total enthalpy H\(T\):\s+(-?[\d.eE+-]+) Eh", text)
    if m:
        out["h_total"] = float(m.group(1))
    m = re.search(r"TOTAL FREE ENERGY\s+(-?[\d.]+) Eh", text)
    if m:
        out["g_total_prop"] = float(m.group(1))
    m = re.search(r"total free energy G\(T\):\s+(-?[\d.eE+-]+) Eh", text)
    if m:
        out["g_total_prop"] = float(m.group(1))
    m = re.search(r"effective electronic temperature:\s+(-?[\d.]+) K", text)
    if m:
        out["etemp"] = float(m.group(1))
    return out


def moments(syms, xyz):
    """Principal moments of inertia (amu Å²) and the molecular mass (amu)."""
    import itertools
    m = [MASS[s] for s in syms]
    mtot = sum(m)
    com = [sum(m[i] * xyz[i][k] for i in range(len(m))) / mtot
           for k in range(3)]
    inertia = [[0.0] * 3 for _ in range(3)]
    for i in range(len(m)):
        r = [xyz[i][k] - com[k] for k in range(3)]
        for a in range(3):
            for b in range(3):
                inertia[a][b] += m[i] * ((sum(v * v for v in r) if a == b else 0.0)
                                         - r[a] * r[b])
    # 3x3 Jacobi eigenvalues (symmetric)
    a = [row[:] for row in inertia]
    for _ in range(100):
        p, q, mx = 0, 1, 0.0
        for i, j in itertools.combinations(range(3), 2):
            if abs(a[i][j]) > mx:
                mx, p, q = abs(a[i][j]), i, j
        if mx < 1.0e-14:
            break
        theta = 0.5 * math.atan2(2 * a[p][q], a[q][q] - a[p][p])
        c, s = math.cos(theta), math.sin(theta)
        for k in range(3):
            if k not in (p, q):
                apk, aqk = a[p][k], a[q][k]
                a[p][k] = a[k][p] = c * apk - s * aqk
                a[q][k] = a[k][q] = s * apk + c * aqk
        app, aqq, apq = a[p][p], a[q][q], a[p][q]
        a[p][p] = c * c * app - 2 * s * c * apq + s * s * aqq
        a[q][q] = s * s * app + 2 * s * c * apq + c * c * aqq
        a[p][q] = a[q][p] = 0.0
    return sorted([a[i][i] for i in range(3)]), mtot


def recompute(freqs, syms, xyz, temp, rotcut, symnum, linear, nvib):
    """The RRHO + free-rotor (Head-Gordon switching) model of xtb `thermodyn`."""
    beta = 1.0 / (KB_SI * temp) * 4.3597447222071e-18   # 1/Eh
    sthr = rotcut * RCMTOAU                              # Eh
    inertia, mtot = moments(syms, xyz)
    # `axis2`: const1 = 1.66053 converts amu Å² into 1e-40 g cm², the leading
    # 1e-47 turns those into kg m²; the average runs over all three moments
    # (the vanishing one included).
    avmom_si = 1.0e-47 * 1.66053 * sum(inertia) / 3.0
    avmom = avmom_si * KGTOME * AATOAU ** 2 * 1.0e20     # xtb's conversion

    q_vib, h_vib, cp_vib, s_vib = 1.0, 0.0, 0.0, 0.0
    cp_rr = 0.5 / beta ** 2
    zpe = 0.0
    for nu in freqs:
        omega = nu * RCMTOAU
        zpe += 0.5 * omega
        ewj = math.exp(-omega * beta)
        q_vib /= (1.0 - ewj)
        h_vib += omega * ewj / (1.0 - ewj)
        cp_ho = omega ** 2 * ewj / (1.0 - ewj) ** 2
        mu = 0.5 / (omega + 1.0e-14)
        mu = mu * avmom / (mu + avmom)
        if omega > 0.0:
            sv_ho = omega * beta * ewj / (1.0 - ewj) - math.log(1.0 - ewj)
            sv_rr = 0.5 + math.log(math.sqrt(math.pi / beta * 2.0 * mu))
        else:
            sv_ho = sv_rr = 0.0
        wofrot = 1.0 - 1.0 / (1.0 + (sthr / omega) ** 4) if sthr >= 0 else 0.0
        cp_vib += (1.0 - wofrot) * cp_ho + wofrot * cp_rr
        s_vib += R * ((1.0 - wofrot) * sv_ho + wofrot * sv_rr)
    h_vib = h_vib * R * beta * temp

    # rotational
    if linear:
        # `axis2`: aa = const2/eig(3), the constant of the two degenerate
        # perpendicular axes; `thermodyn` uses it alone for a linear rotor.
        A = 16.8576522 / inertia[2] * RCMTOAU
        B = C = A
        q_rot = 1.0 / (beta * A * symnum)
        h_rot = R * temp
        s_rot = R * (math.log(1.0 / (beta * A * symnum)) + 1.0)
    else:
        A, B, C = [16.8576522 / I * RCMTOAU for I in inertia]   # Eh
        q_rot = math.sqrt(math.pi / (A * B * C * beta ** 3)) / symnum
        h_rot = 1.5 * R * temp
        s_rot = 0.5 * R * (-2.0 * math.log(symnum)
                           + math.log(math.pi / (A * B * C * beta ** 3)) + 3.0)

    # translational, standard pressure 1 atm (Sackur-Tetrode)
    m_kg = mtot * AMU_KG
    s_tr = R * (math.log((2.0 * math.pi * m_kg * KB_SI * temp / H_SI ** 2) ** 1.5
                         * KB_SI * temp / ATMPA) + 2.5)
    h_tr = 2.5 * R * temp

    h_tot = h_tr + h_rot + h_vib
    s_tot = s_tr + s_rot + s_vib
    ht = h_tot / 1000.0 * KCALTOAU
    et = ht + zpe
    ts = s_tot * temp / 1000.0 * KCALTOAU
    g = et - ts
    return dict(zpe=zpe, ht=ht, et=et, ts=ts, gt=g, s_tot=s_tot,
                s_vib=s_vib, s_rot=s_rot, s_tr=s_tr, q_vib=q_vib,
                q_rot=q_rot, avmom=avmom, inertia=inertia, A=A, B=B, C=C)


def main():
    path, xyzfile = sys.argv[1], sys.argv[2]
    text = open(path).read()
    syms, xyz = parse_xyz(xyzfile)
    got = parse_output(text)
    temp = got.get("temp", 298.15)
    rotcut = float(got["rotor_cutoff"].split()[0])
    symnum = float(got["rotational_number"])
    linear = got["linear"] == "true"
    freqs = [v for v in got["eigval"] if abs(v) > 1.0]
    scale = float(got["scaling_factor"])
    freqs = [v * scale for v in freqs]
    nvib = int(got["n_freq"])
    ref = recompute(freqs, syms, xyz, temp, rotcut, symnum, linear, nvib)
    report = {"file": path, "geometry": xyzfile, "xtb": got,
              "independent": {k: v for k, v in ref.items()
                              if k not in ("inertia",)},
              "delta": {k: got.get(k, float("nan")) - ref[k] for k in
                        ("zpe", "ht", "et", "ts", "gt")},
              "delta_s": {"s_tot": got.get("s_tot_cal", float("nan")) - ref["s_tot"],
                          "s_vib": got.get("s_vib_cal", float("nan")) - ref["s_vib"],
                          "s_rot": got.get("s_rot_cal", float("nan")) - ref["s_rot"],
                          "s_tr": got.get("s_tr_cal", float("nan")) - ref["s_tr"]},
              "n_internal_freq": len(freqs), "nvib_printed": nvib}
    print(json.dumps(report, indent=1, default=str))


if __name__ == "__main__":
    main()
