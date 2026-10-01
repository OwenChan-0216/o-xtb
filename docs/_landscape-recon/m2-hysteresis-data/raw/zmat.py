import numpy as np

def nerf(a, b, c, r, theta_deg, chi_deg):
    """new atom D: |D-C|=r, angle(b,C,D)=theta, dihedral(a,b,C,D)=chi"""
    theta = np.radians(theta_deg); chi = np.radians(chi_deg)
    bc = c - b; bc = bc/np.linalg.norm(bc)
    ab = b - a; ab = ab/np.linalg.norm(ab)
    n = np.cross(ab, bc); n = n/np.linalg.norm(n)
    m = np.cross(n, bc)
    d2 = np.array([-r*np.cos(theta), r*np.sin(theta)*np.cos(chi), r*np.sin(theta)*np.sin(chi)])
    return c + bc*d2[0] + m*d2[1] + n*d2[2]

def torsion(p1,p2,p3,p4):
    b0 = p1-p2; b1 = p3-p2; b2 = p4-p3
    b1n = b1/np.linalg.norm(b1)
    v = b0 - np.dot(b0,b1n)*b1n
    w = b2 - np.dot(b2,b1n)*b1n
    return np.degrees(np.arctan2(np.dot(np.cross(b1n,v),w), np.dot(v,w)))

sym = ['C','C','Cl','Cl','H','H','H','H']
xyz = np.zeros((3,8))
xyz[:,0] = [0.0, 0.0, 0.0]                 # C1
xyz[:,1] = [1.53, 0.0, 0.0]                # C2
# Cl3: bond to C1(1), angle Cl3-C1-C2 = 109.5, phantom reference below
phantom = np.array([0.0, 1.0, 0.0])
xyz[:,2] = nerf(phantom, xyz[:,1], xyz[:,0], 1.79, 109.5, 0.0)   # a=phantom,b=C2,c=C1
# Cl4: bond to C2(2), angle Cl4-C2-C1 = 109.5, dihedral Cl4-C2-C1-Cl3 = 180
xyz[:,3] = nerf(xyz[:,2], xyz[:,0], xyz[:,1], 1.79, 109.5, 180.0)  # a=Cl3,b=C1,c=C2
# H5,H6 on C1: bond to C1, angle H-C1-C2 = 109.5, dihedral H-C1-C2-Cl3 = +-120
xyz[:,4] = nerf(xyz[:,2], xyz[:,1], xyz[:,0], 1.09, 109.5, 120.0)
xyz[:,5] = nerf(xyz[:,2], xyz[:,1], xyz[:,0], 1.09, 109.5, -120.0)
# H7,H8 on C2: bond to C2, angle H-C2-C1 = 109.5, dihedral H-C2-C1-Cl3 = +-120
xyz[:,6] = nerf(xyz[:,2], xyz[:,0], xyz[:,1], 1.09, 109.5, 120.0)
xyz[:,7] = nerf(xyz[:,2], xyz[:,0], xyz[:,1], 1.09, 109.5, -120.0)

print("check d(C1,C2)=", np.linalg.norm(xyz[:,1]-xyz[:,0]))
print("check d(C1,Cl3)=", np.linalg.norm(xyz[:,2]-xyz[:,0]))
print("check d(C2,Cl4)=", np.linalg.norm(xyz[:,3]-xyz[:,1]))
print("check d(C1,H5)=", np.linalg.norm(xyz[:,4]-xyz[:,0]))
print("check ang Cl3-C1-C2=", np.degrees(np.arccos(np.dot(xyz[:,0]-xyz[:,2], xyz[:,1]-xyz[:,0])/np.linalg.norm(xyz[:,0]-xyz[:,2])/np.linalg.norm(xyz[:,1]-xyz[:,0]))))
print("dihedral Cl3-C1-C2-Cl4 =", torsion(xyz[:,2],xyz[:,0],xyz[:,1],xyz[:,3]))
print("dihedral H5-C1-C2-Cl3 =", torsion(xyz[:,4],xyz[:,0],xyz[:,1],xyz[:,2]))
with open('/tmp/m2-exp/dce.xyz','w') as f:
    f.write("%d\n1,2-dichloroethane anti start\n"%len(sym))
    for s,c in zip(sym, xyz.T):
        f.write("%-2s %14.8f %14.8f %14.8f\n"%(s,c[0],c[1],c[2]))
print(open('/tmp/m2-exp/dce.xyz').read())
