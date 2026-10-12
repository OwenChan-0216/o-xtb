#!/usr/bin/env python3
"""Displace the two transferring protons of the benzoic-acid dimer TS guess.

The dimer method needs a start that is *not* an exact stationary point, so this
moves H10 0.15 A toward O23 and H25 0.15 A toward O8 (1-based atom indices of
the 30-atom benzoic-acid dimer).  Usage:

    displace.py <in.xyz> <out.xyz>
"""
import math
import sys


def main(inp, out):
    lines = open(inp).read().splitlines()
    natoms = int(lines[0])
    atoms = []
    for line in lines[2:2 + natoms]:
        parts = line.split()
        atoms.append([parts[0], float(parts[1]), float(parts[2]), float(parts[3])])

    def move(donor, acceptor, dist):
        a = atoms[donor - 1]
        b = atoms[acceptor - 1]
        vec = [b[1] - a[1], b[2] - a[2], b[3] - a[3]]
        norm = math.sqrt(sum(v * v for v in vec))
        for k in range(3):
            a[1 + k] += dist * vec[k] / norm

    move(10, 23, 0.15)   # H10 toward O23
    move(25, 8, 0.15)    # H25 toward O8

    body = ["%d" % natoms,
            "TS guess displaced 0.15 A along each transfer coordinate (H10->O23, H25->O8)"]
    for atom in atoms:
        body.append("%-4s%14.8f%14.8f%14.8f" % (atom[0], atom[1], atom[2], atom[3]))
    open(out, "w").write("\n".join(body) + "\n")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
