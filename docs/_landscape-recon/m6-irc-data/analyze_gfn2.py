#!/usr/bin/env python3
"""Parse the GFN2 four-method IRC data of experiment 6 and print the
cross-method endpoint RMSD matrix, energy gaps (kcal/mol) and arc lengths."""
import os, re, sys, itertools, math

BASE = "exp6-crosscheck/gfn2"
STEPS = ["0.05", "0.10", "0.20", "0.40"]
METHODS = ["gs", "lqa", "hpc", "eulerpc"]
HARTREE2KCAL = 627.50947428

def read_xyz_last(path):
    """Return (symbols, coords) of the last frame of a multi-frame xyz."""
    with open(path) as f:
        lines = f.read().split("\n")
    # find frame boundaries: a count line followed by comment
    frames = []
    i = 0
    while i < len(lines):
        s = lines[i].strip()
        if not s:
            i += 1; continue
        try:
            n = int(s)
        except ValueError:
            i += 1; continue
        comment = lines[i+1]
        atoms = []
        for k in range(n):
            parts = lines[i+2+k].split()
            atoms.append((parts[0], [float(x) for x in parts[1:4]]))
        frames.append((comment, atoms))
        i += 2 + n
    return frames[-1]

def read_direction(path):
    """Last frame coords and energy from a direction xyz."""
    comment, atoms = read_xyz_last(path)
    m = re.search(r"energy:\s*(-?[0-9.]+)", comment)
    e = float(m.group(1)) if m else float("nan")
    coords = [c for _, c in atoms]
    return coords, e

def parse_log(path):
    txt = open(path).read()
    d = {}
    m = re.search(r"mean energy/gradient evaluations per point:\s*([0-9.]+)\s*\n"
                  r"\s*\n\s*backward direction", txt)
    # forward mean is the first occurrence
    means = re.findall(r"mean energy/gradient evaluations per point:\s*([0-9.]+)", txt)
    d["mean_eval"] = [float(x) for x in means[:2]]
    for key, pat in [("e_fwd", r"forward endpoint energy:\s*(-?[0-9.]+)"),
                     ("e_bwd", r"backward endpoint energy:\s*(-?[0-9.]+)"),
                     ("s_fwd", r"forward arc length:\s*([0-9.]+)"),
                     ("s_bwd", r"backward arc length:\s*([0-9.]+)"),
                     ("term_fwd", r"termination forward:\s*(\S+)"),
                     ("term_bwd", r"termination backward:\s*(\S+)"),
                     ("rmsd_fwd", r"forward reached minimum:\s*\S+\s*\(rmsd\s*([0-9.]+)"),
                     ("rmsd_bwd", r"backward reached minimum:\s*\S+\s*\(rmsd\s*([0-9.]+)")]:
        mm = re.search(pat, txt)
        d[key] = mm.group(1) if mm else None
    return d

def rmsd(a, b):
    return math.sqrt(sum((x-y)**2 for pa, pb in zip(a, b) for x, y in zip(pa, pb)) / len(a))

def main():
    data = {}
    for step in STEPS:
        for meth in METHODS:
            d = os.path.join(BASE, f"step{step}", meth)
            log = os.path.join(d, "m.irc.log")
            fxyz = os.path.join(d, "m.irc_forward.xyz")
            bxyz = os.path.join(d, "m.irc_backward.xyz")
            if not os.path.exists(log):
                print(f"missing {log}"); continue
            cf, ef = read_direction(fxyz)
            cb, eb = read_direction(bxyz)
            data[(step, meth)] = dict(log=parse_log(log), cf=cf, cb=cb, ef=ef, eb=eb)

    for step in STEPS:
        print(f"\n===== step {step} bohr*amu^1/2 =====")
        print("method   term(f/b)   E_fwd            E_bwd            rmsd_f/b        s_fwd   s_bwd  E/g(f/b)")
        for meth in METHODS:
            if (step, meth) not in data: continue
            b = data[(step, meth)]
            print(f"{meth:8s} {b['log']['term_fwd'][:6]:>6s}/{b['log']['term_bwd'][:6]:<6s} "
                  f"{b['ef']:.12f} {b['eb']:.12f} {b['log']['rmsd_fwd']}/{b['log']['rmsd_bwd']:<10} "
                  f"{b['log']['s_fwd']} {b['log']['s_bwd']} {b['log']['mean_eval']}")
        print("endpoint RMSD matrix (bohr), forward:")
        print("        " + "".join(f"{m:>10s}" for m in METHODS))
        for m1 in METHODS:
            row = "".join(f"{rmsd(data[(step,m1)]['cf'], data[(step,m2)]['cf']):10.2e}" for m2 in METHODS)
            print(f"{m1:8s}{row}")
        print("endpoint RMSD matrix (bohr), backward:")
        print("        " + "".join(f"{m:>10s}" for m in METHODS))
        for m1 in METHODS:
            row = "".join(f"{rmsd(data[(step,m1)]['cb'], data[(step,m2)]['cb']):10.2e}" for m2 in METHODS)
            print(f"{m1:8s}{row}")
        # energy gaps kcal/mol
        print("forward  dE (kcal/mol) vs gs:", {m: round((data[(step,m)]['ef']-data[(step,'gs')]['ef'])*HARTREE2KCAL,4) for m in METHODS})
        print("backward dE (kcal/mol) vs gs:", {m: round((data[(step,m)]['eb']-data[(step,'gs')]['eb'])*HARTREE2KCAL,4) for m in METHODS})

if __name__ == "__main__":
    main()
