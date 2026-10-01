import numpy as np
from scipy.optimize import minimize_scalar, brentq
np.set_printoptions(precision=10)

DE  = 0.1744342274
BETA= 3.6711
RE  = 1.4011
SATO= 0.10

def pair(r):
    x = r - RE
    e1 = DE*(np.exp(-2*BETA*x) - 2*np.exp(-BETA*x))
    e3 = 0.5*DE*(np.exp(-2*BETA*x) + 2*np.exp(-BETA*x))
    d1 = DE*(-2*BETA*np.exp(-2*BETA*x) + 2*BETA*np.exp(-BETA*x))
    d3 = 0.5*DE*(-2*BETA*np.exp(-2*BETA*x) - 2*BETA*np.exp(-BETA*x))
    q = 0.5*(e1+e3); j = 0.5*(e1-e3)/(1.0+SATO)
    dq= 0.5*(d1+d3); dj= 0.5*(d1-d3)/(1.0+SATO)
    return q, j, dq, dj

PAIRS = ((0,1),(1,2),(0,2))

def energy_grad(xin):
    x = np.asarray(xin, dtype=float)
    xyz = x.reshape(3,3).T
    r=np.zeros(3); Q=np.zeros(3); J=np.zeros(3); dQ=np.zeros(3); dJ=np.zeros(3)
    for kk in range(3):
        i,jn = PAIRS[kk]
        rr = float(np.linalg.norm(xyz[:,i]-xyz[:,jn])); r[kk]=rr
        Q[kk],J[kk],dQ[kk],dJ[kk] = pair(rr)
    root=np.sqrt(0.5*((J[0]-J[1])**2+(J[1]-J[2])**2+(J[2]-J[0])**2))
    E=float(np.sum(Q)-root)
    ds=np.array([(J[0]-0.5*(J[1]+J[2]))*dJ[0],
                 (J[1]-0.5*(J[0]+J[2]))*dJ[1],
                 (J[2]-0.5*(J[0]+J[1]))*dJ[2]])
    dedr = dQ - ds/root
    g=np.zeros(9)
    for kk in range(3):
        i,jn = PAIRS[kk]
        u=1.0/r[kk]; dv=xyz[:,i]-xyz[:,jn]
        g[3*i:3*i+3]   += dedr[kk]*u*dv
        g[3*jn:3*jn+3] -= dedr[kk]*u*dv
    return E, g

def hess_fd(xin, h=1e-5):
    x=np.asarray(xin,dtype=float); n=x.size; H=np.zeros((n,n))
    for i in range(n):
        xp=x.copy(); xm=x.copy(); xp[i]+=h; xm[i]-=h
        H[:,i]=(energy_grad(xp)[1]-energy_grad(xm)[1])/(2*h)
    return 0.5*(H+H.T)

def collinear(d12, d23):
    x=np.array([0.0,0,0, d12,0,0, d12+d23,0,0])
    return x

def asym(r3):
    f=lambda d: energy_grad(collinear(d, r3-d))[0]
    res=minimize_scalar(f, bracket=(1.30,1.414,1.60), method='brent', options={'xtol':1e-15})
    return float(res.x), float(res.fun)

print("=== H + H2 asymptote (collinear, the H2 bond relaxed) ===")
ref={}
for r3 in (4.0,10.0,20.0,40.0):
    rr,ee=asym(r3); ref[r3]=(rr,ee)
    print(f"  r3 = {r3:5.1f} bohr : rH2 = {rr:.10f} bohr, E = {ee:.12f} Eh")
r_h2,E_h2 = ref[20.0]

print("=== stationary points on the symmetric line r12 = r23 = d ===")
F=lambda d: (energy_grad(collinear(d,d))[0])
dF=lambda d,h=1e-7: (F(d+h)-F(d-h))/(2*h)
grid=np.linspace(1.36,1.70,681)
vals=np.array([dF(float(g)) for g in grid])
cross=np.where(np.diff(np.sign(vals))!=0)[0]
saddles=[]
for i in cross:
    d=brentq(dF, float(grid[i]), float(grid[i+1]), xtol=1e-15)
    saddles.append(d)
    xs=collinear(d,d)
    E,g=energy_grad(xs); H=hess_fd(xs)
    w=np.sort(np.linalg.eigvalsh(H))
    print(f"  dE/dd = 0 at d = {d:.10f} bohr   (r12=r23={d:.10f}, r13={2*d:.10f})")
    print(f"    E = {E:.12f} Eh    |g| = {np.linalg.norm(g):.3e} Eh/bohr")
    print(f"    Hessian eigenvalues: {np.array2string(w,precision=8)}")
    print(f"    barrier vs H2 asymptote = {(E-E_h2)*627.509474:.6f} kcal/mol = {(E-E_h2)*27.211386245:.6f} eV")
    for r3 in (4.0,10.0):
        print(f"    barrier vs endpoint(r3={r3}) = {(E-ref[r3][1])*627.509474:.6f} kcal/mol")

print("=== collinear endpoint energies (r12, r23) ===")
def E_of(d12,d23):
    x=collinear(d12,d23); return energy_grad(x)[0]
import itertools
cands=[(1.4140743,4.0),(1.4140743,2.5),(1.4140743,2.0),(1.4140743,3.0),(1.5052685936,2.0),
       (1.6,1.6),(2.0,1.0),(1.0,2.0),(1.7,1.3105365),(1.3105365,1.7),
       (1.9,1.5),(1.5,1.9),(2.0,1.5052685936),(1.5052685936,1.9)]
for (a,b) in cands:
    e=E_of(a,b)
    print(f"  r12={a:9.6f} r23={b:9.6f} r13={a+b:9.6f}  E={e:.10f}  dE_vs_TS={(e+0.140638574121)*627.509474:9.4f} kcal")
