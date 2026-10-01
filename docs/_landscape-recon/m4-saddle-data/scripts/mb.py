import numpy as np
A=np.array([-200.,-100.,-170.,15.]); a=np.array([-1.,-1.,-6.5,0.7])
b=np.array([0.,0.,11.,0.6]); c=np.array([-10.,-10.,-6.5,0.7])
x0=np.array([1.,0.,-0.5,-1.]); y0=np.array([0.,0.5,1.5,1.0])
kc=1.0/627.50947428
def V(x,y):
    u=x-x0; v=y-y0; q=a*u*u+b*u*v+c*v*v
    return kc*np.sum(A*np.exp(q))
def grad(x,y):
    u=x-x0; v=y-y0; q=a*u*u+b*u*v+c*v*v; g=A*np.exp(q)
    du=2*a*u+b*v; dv=b*u+2*c*v
    return kc*np.array([np.sum(g*du),np.sum(g*dv)])
def hess(x,y):
    u=x-x0; v=y-y0; q=a*u*u+b*u*v+c*v*v; g=A*np.exp(q)
    du=2*a*u+b*v; dv=b*u+2*c*v
    return kc*np.array([[np.sum(g*(du*du+2*a)),np.sum(g*(du*dv+b))],
                        [np.sum(g*(du*dv+b)),np.sum(g*(dv*dv+2*c))]])
# Newton from reference
p=np.array([-0.82200156,0.62431280])
for i in range(60):
    g=grad(*p); H=hess(*p); p=p-np.linalg.solve(H,g)
    if np.linalg.norm(g)<1e-14: break
print("exact saddle  =",repr(p), " |grad|=%.3e"%np.linalg.norm(grad(*p)))
print("mb_saddle ref = [-0.82200156, 0.6243128]  dist = %.3e bohr"%np.linalg.norm(p-np.array([-0.82200156,0.62431280])))
w=np.linalg.eigvalsh(hess(*p))
print("Hessian eigenvalues at saddle (Eh/bohr^2): %.8f  %.8f"%tuple(w))
print("saddle energy = %.10f Eh = %.6f kcal/mol"%(V(*p), V(*p)/kc))
# minima (Newton from a few starts)
for st in [(-0.5,0.5),(0.5,0.0),(-0.6,-0.2),(1.0,0.0),(0.6,0.6)]:
    q=np.array(st,dtype=float)
    for i in range(200):
        g=grad(*q); H=hess(*q)
        try: d=np.linalg.solve(H,g)
        except: break
        q=q-d
        if np.linalg.norm(g)<1e-14: break
    w2=np.linalg.eigvalsh(hess(*q))
    kind="MIN" if (w2>0).all() else ("SADDLE" if (w2<0).sum()==1 else "MAX/other")
    print("  stat pt", np.round(q,6), "E=%.6f"%V(*q), "eig=%s"%np.round(w2,5), kind)
