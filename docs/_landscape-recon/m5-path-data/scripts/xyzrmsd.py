#!/usr/bin/env python3
"""Kabsch aligned RMSD (bohr) between two single frame xyz files (angstrom)."""
import sys, numpy as np

def read(fn):
    lines = open(fn).read().splitlines()
    n = int(lines[0].split()[0])
    xyz = np.array([[float(x) for x in l.split()[1:4]] for l in lines[2:2+n]])
    return xyz*1.8897261246257702  # angstrom -> bohr

def kabsch_rmsd(a, b):
    a = a - a.mean(0)
    b = b - b.mean(0)
    u, s, vt = np.linalg.svd(a.T @ b)
    d = np.sign(np.linalg.det(u @ vt))
    rot = u @ np.diag([1, 1, d]) @ vt
    a = a @ rot
    return np.sqrt(((a-b)**2).sum()/a.shape[0]), np.sqrt(((a-b)**2).sum()/a.size)

if __name__ == "__main__":
    a = read(sys.argv[1]); b = read(sys.argv[2])
    r, rall = kabsch_rmsd(a, b)
    print(f"{sys.argv[1]} vs {sys.argv[2]}: aligned RMSD {r:.6f} bohr/atom ({r/1.8897261246257702:.6f} A), "
          f"per component {rall:.6f} bohr")
