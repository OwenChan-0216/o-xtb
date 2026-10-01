#!/usr/bin/env python3
"""M2 validation analysis.  Robust: a missing/malformed point is reported as
`nan`/`-`, never an exception."""
import os, re, sys, json, math
import numpy as np

KCAL = 627.50947428
OUT = '/home/owenchan/work_path/coding/fortran/xtb/docs/_landscape-recon/m2-hysteresis-data'
os.makedirs(OUT, exist_ok=True)

def torsion(p1,p2,p3,p4):
    b0=p1-p2; b1=p3-p2; b2=p4-p3
    b1n=b1/np.linalg.norm(b1)
    v=b0-np.dot(b0,b1n)*b1n; w=b2-np.dot(b2,b1n)*b1n
    return math.degrees(math.atan2(np.dot(np.cross(b1n,v),w),np.dot(v,w)))

def read_frames(fn):
    """-> list of (energy, xyz(N,3)) ; a malformed frame becomes (nan, None)"""
    out=[]
    if not os.path.exists(fn): return out
    L=open(fn).read().splitlines(); i=0
    while i < len(L):
        if not L[i].strip(): i+=1; continue
        try: n=int(L[i].split()[0])
        except Exception: i+=1; continue
        try:
            m=re.search(r'energy:\s*(-?[0-9.]+(?:[eE][+-]?[0-9]+)?)', L[i+1])
            e=float(m.group(1)) if m else float('nan')
            xyz=np.array([[float(x) for x in L[i+2+k].split()[1:4]] for k in range(n)])
            if xyz.shape != (n,3): raise ValueError
        except Exception:
            e=float('nan'); xyz=None
        out.append((e,xyz)); i+=n+2
    return out

def read_table(fn):
    """-> list of dicts, one per scanned point (empty list if the table is absent)"""
    pts=[]
    if not os.path.exists(fn): return pts
    for l in open(fn):
        m=re.match(r'\s*(\d+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+([0-9.Eepm+-]+)\s+(\d+)\s+([TF])\s*$', l)
        if m:
            try: e=float(m.group(3))
            except Exception: e=float('nan')
            pts.append(dict(i=int(m.group(1)), value=float(m.group(2)), energy=e,
                            residual=m.group(4), steps=int(m.group(5)), conv=m.group(6)))
    return pts

def reached_deg(frames, atoms=(3,1,2,4)):
    out=[]
    for e,x in frames:
        if x is None: out.append(float('nan')); continue
        i,j,k,l=[a-1 for a in atoms]
        try: out.append(torsion(x[i],x[j],x[k],x[l]))
        except Exception: out.append(float('nan'))
    return out

def vertex(t,y):
    t=np.asarray(t,float); y=np.asarray(y,float)
    if np.any(~np.isfinite(t)) or np.any(~np.isfinite(y)) or len(t)<3: return float('nan'),float('nan')
    d1=(y[1]-y[0])/(t[1]-t[0]); d2=(y[2]-y[1])/(t[2]-t[1]); a=(d2-d1)/(t[2]-t[0])
    if a==0: return float(t[1]), float(y[1])
    return float(t[1]-d1/(2*a)), float(y[1]-d1*d1/(4*a))

def hysteresis(fn):
    pts=read_table(fn)
    if not pts: return dict(n=0, max_delta=float('nan'), at=float('nan'), jump=float('nan'),
                            jump_from=float('nan'), jump_to=float('nan'), valid=0, total=0)
    E=np.array([p['energy'] for p in pts]); V=np.array([p['value'] for p in pts])
    ok=np.isfinite(E)&(E!=0.0)           # a failed point carries a hard 0.0
    n=len(pts); nf=(n+1)//2             # bidirectional layout: forward = 1..nf
    md=float('nan'); at=float('nan'); c=0
    for k in range(nf-1):
        a=k; b=n-1-k
        if ok[a] and ok[b]:
            d=abs(E[a]-E[b]); c+=1
            if not (md>=d): md=d; at=V[a]
    d=np.abs(np.diff(E))
    if len(d):
        j=int(np.argmax(d))
        jump=float(d[j]); jf=float(V[j]); jt=float(V[j+1])
    else:
        jump=jf=jt=float('nan')
    return dict(n=n, compared=c, max_delta=md, at=at, jump=jump, jump_from=jf, jump_to=jt,
                valid=int(np.sum(ok)), total=n)

def table_out(name, fn):
    print("### %s (%s)"%(name, fn))
    h=hysteresis(fn)
    print("  valid points %d / %d ; hysteresis points compared %d"%(h['valid'],h['total'],h['compared']))
    if h['compared']:
        print("  max |E_fwd-E_rev| = %.6e Eh = %.6e kcal/mol at %.4f deg"%(h['max_delta'],h['max_delta']*KCAL,h['at']))
    else:
        print("  max |E_fwd-E_rev| = - (no comparable point)")
    print("  largest adjacent jump = %.6e Eh at %.4f -> %.4f deg"%(h['jump'],h['jump_from'],h['jump_to']))
    return h

if __name__=='__main__':
    # ---------------- 1. hysteresis ----------------
    summary={}
    print("================ 1. HYSTERESIS (relaxed, bidirectional) ================")
    print("%-12s %-6s %-22s %-22s %-12s"%("grid","level","max|dE| / Eh","max|dE| / kcal/mol","jump / Eh"))
    for grid,files in (("12deg",('superloose','loose','normal','tight','vtight')),
                       ("24deg",('superloose','loose','normal','tight','vtight'))):
        for lvl in files:
            fn='r_hyst%s_%s.log'%(grid.replace('deg',''),lvl)
            h=hysteresis(fn)
            summary['hyst_%s_%s'%(grid,lvl)]=h
            print("%-12s %-6s %22.9e %22.9e %12.4e"%(grid,lvl,h['max_delta'],h['max_delta']*KCAL,h['jump']))
    # ---------------- 2. fc sweep ----------------
    print()
    print("================ 2. CONSTRAINT FORCE CONSTANT SWEEP (one way, 24 deg) ================")
    print("%-6s %8s %12s %14s %12s %14s %14s %14s %10s"%("fc","#pts","max|drift|","max|drift|","residual","barrier th","barrier E","gauche th","gauche E"))
    fcdata={}
    for fc in ('0.05','0.1','0.5','2.0','5.0','10.0'):
        log='r_fc_%s.log'%fc
        pts=read_table(log)
        frames=read_frames('f%s.xtbscan.log'%fc)
        q=np.array(reached_deg(frames)); v=np.array([p['value'] for p in pts]); e=np.array([p['energy'] for p in pts])
        res=np.array([float(p['residual'].replace('E','e').replace('+','')) if p['residual'] not in ('-',) else float('nan') for p in pts]) if pts else np.array([])
        ok=np.isfinite(q)&np.isfinite(e)&(e!=0.0)
        drift=(q-v)[ok] if len(q)==len(v) else np.array([float('nan')])
        maxdrift=float(np.max(np.abs(drift))) if len(drift) and np.all(np.isfinite(drift)) else float('nan')
        # barrier = interior maximum, gauche = interior minimum, both on the
        # reached-coordinate axis; a non-interior extremum is reported as nan
        bt=be=gt=ge=float('nan')
        if np.sum(ok)>=3:
            qo=q[ok]; eo=e[ok]
            k=int(np.argmax(eo))
            if 0<k<len(eo)-1:
                bt,be=vertex(qo[k-1:k+2],eo[k-1:k+2])
            j=int(np.argmin(eo))
            if 0<j<len(eo)-1:
                gt,ge=vertex(qo[j-1:j+2],eo[j-1:j+2])
        fcdata[fc]=dict(max_drift=maxdrift, barrier_th=bt, barrier_e=be, gauche_th=gt, gauche_e=ge,
                        q=list(q), v=list(v), e=list(e), res=list(res))
        print("%-6s %8d %12.4f %14s %12s %14.4f %14.9f %14.4f %14.9f"%(fc,np.sum(ok),maxdrift,'deg',
              ('%.2e'%np.nanmax(np.abs([float(r) for r in res]))) if len(res) else '-', bt,be,gt,ge))
    # ---------------- 3. rigid vs relaxed ----------------
    print()
    print("================ 3. RIGID vs RELAXED (driver, one way) ================")
    for tag,grid in (("rigid12",'r_rigid12.log'),):
        pts=read_table(grid); frames=read_frames('rigid12.xtbscan.log')
        q=reached_deg(frames)
        print("  %s: %d points, valid %d"%(tag,len(pts),sum(1 for p in pts if p['energy']!=0.0)))
        for k,p in enumerate(pts):
            print("    target %10.4f  reached %12.6f  E %18.12f  (%s)"%(p['value'],q[k] if k<len(q) else float('nan'),p['energy'],p['conv']))
    np.save(os.path.join(OUT,'analysis.npy'), {'summary':summary,'fc':fcdata}, allow_pickle=True)
    print()
    print("raw data written to", OUT)
