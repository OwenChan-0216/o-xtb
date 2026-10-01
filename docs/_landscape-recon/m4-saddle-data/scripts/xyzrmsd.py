import sys, numpy as np
def read(f):
    L=open(f).read().splitlines()
    n=int(L[0].split()[0]); at=[]; xyz=[]
    for l in L[2:2+n]:
        p=l.split(); at.append(p[0]); xyz.append([float(v) for v in p[1:4]])
    return at, np.array(xyz)
def kabsch(a,b):
    a=a-a.mean(0); b=b-b.mean(0)
    H=a.T@b; U,S,Vt=np.linalg.svd(H); d=np.sign(np.linalg.det(Vt.T@U.T))
    D=np.diag([1,1,d]); R=Vt.T@D@U.T; return a@R.T
f1,f2=sys.argv[1],sys.argv[2]
a1,x1=read(f1); a2,x2=read(f2)
raw=np.sqrt(((x1-x2)**2).sum()/len(x1))
al =np.sqrt(((kabsch(x1,x2)- (x2-x2.mean(0)))**2).sum()/len(x1))
print(f"{f1}\n{f2}\n  raw RMSD   = {raw:.6e} bohr\n  aligned    = {al:.6e} bohr\n  max comp   = {np.abs(x1-x2).max():.6e} bohr")
