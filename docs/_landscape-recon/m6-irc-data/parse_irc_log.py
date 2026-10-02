#!/usr/bin/env python3
"""Parse the per-point tables of m6 IRC logs."""
import re, sys, glob, os

def parse(path):
    txt = open(path).read()
    fwd, bwd = [], []
    section = None
    for line in txt.splitlines():
        if line.strip() == "forward direction":
            section = fwd; continue
        if line.strip() == "backward direction":
            section = bwd; continue
        m = re.match(r"\s*(\d+)\s+([0-9.]+)\s+(-?[0-9.]+)\s+([0-9.E+-]+)\s+(\d+)\s*$", line)
        if m and section is not None:
            section.append((int(m.group(1)), float(m.group(2)), float(m.group(3)),
                            float(m.group(4)), int(m.group(5))))
    return fwd, bwd

def summary(path):
    txt = open(path).read()
    g = lambda p: (re.search(p, txt).group(1) if re.search(p, txt) else None)
    return dict(
      term_fwd=g(r"termination forward:\s*(\S+)"),
      term_bwd=g(r"termination backward:\s*(\S+)"),
      e_fwd=float(g(r"forward endpoint energy:\s*(-?[0-9.]+)")),
      e_bwd=float(g(r"backward endpoint energy:\s*(-?[0-9.]+)")),
      s_fwd=float(g(r"forward arc length:\s*([0-9.]+)")),
      s_bwd=float(g(r"backward arc length:\s*([0-9.]+)")),
      rmsd_fwd=g(r"forward reached minimum:\s*\S+\s*\(rmsd\s*([0-9.]+)"),
      rmsd_bwd=g(r"backward reached minimum:\s*\S+\s*\(rmsd\s*([0-9.]+)"),
    )

if __name__ == "__main__":
    for p in sys.argv[1:]:
        f, b = parse(p)
        s = summary(p)
        print(f"== {p}")
        if f:
            print(f"  fwd n={len(f)} last|g|={f[-1][3]:.6E} mean E/g={sum(x[4] for x in f)/len(f):.3f} term={s['term_fwd']} E={s['e_fwd']:.12f} s={s['s_fwd']}")
        if b:
            print(f"  bwd n={len(b)} last|g|={b[-1][3]:.6E} mean E/g={sum(x[4] for x in b)/len(b):.3f} term={s['term_bwd']} E={s['e_bwd']:.12f} s={s['s_bwd']}")
