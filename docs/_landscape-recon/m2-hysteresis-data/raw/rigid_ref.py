import numpy as np, subprocess, os, sys, re

COV = {'H':0.32,'C':0.75,'Cl':1.02,'O':0.63}
BOND = 1.2

def read_xyz(fn):
    L=open(fn).read().splitlines()
    n=int(L[0].split()[0]); sym=[]; xyz=[]
    for l in L[2:2+n]:
        p=l.split(); sym.append(p[0]); xyz.append([float(x) for x in p[1:4]])
    return sym, np.array(xyz)

def torsion(p1,p2,p3,p4):
    b0=p1-p2; b1=p3-p2; b2=p4-p3
    b1n=b1/np.linalg.norm(b1)
    v=b0-np.dot(b0,b1n)*b1n; w=b2-np.dot(b2,b1n)*b1n
    return np.degrees(np.arctan2(np.dot(np.cross(b1n,v),w),np.dot(v,w)))

def fragment(sym, xyz, seed, cut):
    """connected component containing seed, edge `cut` removed (0-based pair)"""
    n=len(sym); seen=np.zeros(n,bool); seen[seed]=True; stack=[seed]
    while stack:
        i=stack.pop()
        for j in range(n):
            if seen[j]: continue
            if {i,j}==set(cut): continue
            if np.linalg.norm(xyz[j]-xyz[i]) <= BOND*(COV[sym[i]]+COV[sym[j]]):
                seen[j]=True; stack.append(j)
    return seen

def rotate(xyz, mask, pivot, axis, ang):
    xyz=xyz.copy()
    ax=axis/np.linalg.norm(axis)
    ca,sa=np.cos(ang),np.sin(ang)
    for i in np.where(mask)[0]:
        r=xyz[i]-pivot
        xyz[i]=pivot+r*ca+np.cross(ax,r)*sa+ax*np.dot(ax,r)*(1-ca)
    return xyz

def dce_real(indices, sym, x0, targets, mode):
    """indices: (i,j,k,l) 1-based atoms; returns list of geometries"""
    i,j,k,l=[a-1 for a in indices]
    q0=torsion(x0[i],x0[j],x0[k],x0[l])
    out=[]
    if mode=='lside':      # fragment containing l after cutting the j-k bond
        mask=fragment(sym,x0,l,(j,k))
    elif mode=='lonly':    # current xtb behaviour: fragment containing l after cutting l-k
        mask=fragment(sym,x0,l,(l,k))
    else: raise ValueError
    x=x0.copy()
    for t in targets:
        q=torsion(x[i],x[j],x[k],x[l])
        alpha=np.radians(t-q)
        x=rotate(x,mask,x[j],x[k]-x[j],alpha)
        qn=torsion(x[i],x[j],x[k],x[l])
        if abs(qn-t)>1e-6:
            raise RuntimeError("rotation did not reach the target: %.6f vs %.6f"%(qn,t))
        out.append(x.copy())
    return out

def energies(sym, geoms, wd):
    os.makedirs(wd, exist_ok=True)
    E=[]
    for k,g in enumerate(geoms):
        fn=os.path.join(wd,'p%03d.xyz'%k)
        with open(fn,'w') as f:
            f.write("%d\nframe %d\n"%(len(sym),k))
            for s,c in zip(sym,g): f.write("%-2s %18.12f %18.12f %18.12f\n"%(s,*c))
        env=dict(os.environ, XTBPATH='/home/owenchan/work_path/coding/fortran/xtb')
        r=subprocess.run(['/tmp/xtb-land/build/xtb',fn,'--gfn2','--sp','--norestart'],
                         capture_output=True,text=True,cwd=wd,env=env)
        m=re.search(r'TOTAL ENERGY\s+(-?[0-9.]+)',r.stdout)
        if not m: raise RuntimeError(r.stdout[-2000:])
        E.append(float(m.group(1)))
    return np.array(E)
