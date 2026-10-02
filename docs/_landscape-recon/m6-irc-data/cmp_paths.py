#!/usr/bin/env python3
import sys, math, re

def frames(path):
    lines=open(path).read().split("\n"); out=[]; i=0
    while i < len(lines):
        s=lines[i].strip()
        if not s: i+=1; continue
        try: n=int(s)
        except ValueError: i+=1; continue
        atoms=[]
        for k in range(n):
            p=lines[i+2+k].split(); atoms.append([float(x) for x in p[1:4]])
        out.append(atoms); i+=2+n
    return out

def rmsd(a,b): return math.sqrt(sum((x-y)**2 for pa,pb in zip(a,b) for x,y in zip(pa,pb))/len(a))
def dist(a,b): return math.sqrt(sum((x-y)**2 for pa,pb in zip(a,b) for x,y in zip(pa,pb)))

def maxdev(p1,p2):
    f1=frames(p1); f2=frames(p2); m=0.0
    for a in f1:
        d=min(dist(a,b) for b in f2); m=max(m,d)
    return m

p1=sys.argv[1]
for p2 in sys.argv[2:]:
    f1=frames(p1); f2=frames(p2)
    print(f"{p1} vs {p2}: frames {len(f1)}/{len(f2)} max deviation {maxdev(p1,p2):.6e} bohr endpoint dist {dist(f1[-1],f2[-1]):.6e}")
