import subprocess, math, os
def E(ang):
    h=0.96; c=math.cos(math.radians(ang)); s=math.sin(math.radians(ang))
    xyz=f"3\nbend\nO 0 0 0\nH {h:.10f} 0 0\nH {h*c:.10f} {h*s:.10f} 0\n"
    open('/tmp/bend.xyz','w').write(xyz)
    out=subprocess.run(['/tmp/xtb-land/build/xtb','/tmp/bend.xyz','--gfn','2','--sp','--norestart'],
        capture_output=True,text=True,env={**os.environ,'OMP_NUM_THREADS':'1'}).stdout
    for l in out.splitlines():
        if 'TOTAL ENERGY' in l: return float(l.split()[3])
for a in [180,179.5,179,178,175,170]:
    print(f"{a}: {E(a):.12f}")
