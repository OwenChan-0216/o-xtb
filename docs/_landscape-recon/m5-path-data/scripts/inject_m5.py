#!/usr/bin/env python3
"""M5 injection experiments: mutate, build, test, restore."""
import subprocess, sys, shutil, os, re

ROOT = "/home/owenchan/work_path/coding/fortran/xtb"
NEB = os.path.join(ROOT, "src/landscape/path/neb.f90")
POT = os.path.join(ROOT, "test/unit/landscape_testpot.f90")
BUILD = "/tmp/xtb-land/build"

def build():
    r = subprocess.run(["cmake", "--build", BUILD, "-j8"], capture_output=True, text=True)
    if r.returncode != 0:
        print("BUILD FAILED")
        print(r.stdout[-3000:], r.stderr[-3000:])
        return False
    return True

def run_tests(dest):
    env = dict(os.environ, OMP_NUM_THREADS="1")
    r = subprocess.run(["./xtb-tester", "landscape-path"], cwd=os.path.join(BUILD, "test/unit"),
                       capture_output=True, text=True, env=env)
    out = r.stdout + r.stderr
    open(dest, "w").write(out)
    failed = re.findall(r"Starting (\S+) .*?\.\.\. \[FAILED\]", out)
    withmsg = re.findall(r"Message: (.*)", out)
    print("tester rc", r.returncode, "failed:", failed)
    for m in withmsg[:6]:
        print("   msg:", m)
    c = subprocess.run(["ctest", "-R", "landscape"], cwd=BUILD, capture_output=True, text=True, env=env)
    open(dest.replace(".txt", "-ctest.txt"), "w").write(c.stdout + c.stderr)
    tail = [l for l in (c.stdout+c.stderr).splitlines() if "tests passed" in l or "Failed" in l]
    print("ctest:", tail[:6])
    return failed

def mutate(name):
    if name == "naive-tangent":
        s = open(NEB).read()
        old = """   if (ep > e .and. e > em) then
      ! monotonically rising: upwind is the forward difference
      tau = up
   else if (ep < e .and. e < em) then
      ! monotonically falling: upwind is the backward difference
      tau = um
   else"""
        new = """   if (.false.) then
      tau = up
   else if (.false.) then
      tau = um
   else if (.true.) then
      tau = up + um
   else"""
        assert old in s
        s = s.replace(old, new)
        open(NEB, "w").write(s)
    elif name == "vector-spring":
        s = open(NEB).read()
        old = "   force = force_perp + k*(d_next - d_prev)*tau"
        new = "   force = force_perp + k*(dp - dm)"
        assert old in s
        open(NEB, "w").write(s.replace(old, new))
    elif name == "no-upwind":
        s = open(NEB).read()
        s = s.replace("   if (ep > e .and. e > em) then", "   if (.false.) then")
        s = s.replace("   else if (ep < e .and. e < em) then", "   else if (.false.) then")
        assert "if (.false.) then" in s
        open(NEB, "w").write(s)
    elif name == "no-align":
        s = open(NEB).read()
        n = s.count("if (settings%align)")
        s = s.replace("if (settings%align)", "if (.false.)")
        assert n >= 3, n
        open(NEB, "w").write(s)
    elif name == "leps-transposed":
        s = open(POT).read()
        old = """      gradient(3*(jat - 1) + 1:3*jat) = gradient(3*(jat - 1) + 1:3*jat) &
         & - dedr(k)*u(k)*(xyz(:, i) - xyz(:, jat))
   end do

end subroutine leps_evaluate"""
        new = """      gradient(3*(jat - 1) + 1:3*jat) = gradient(3*(jat - 1) + 1:3*jat) &
         & - dedr(k)*u(k)*(xyz(:, i) - xyz(:, jat))
   end do
   ! INJECTION: column major flattening (R-08)
   gradient = reshape(transpose(reshape(gradient, [3, 3])), [9])

end subroutine leps_evaluate"""
        assert old in s
        open(POT, "w").write(s.replace(old, new))
    else:
        raise SystemExit("unknown injection " + name)

if __name__ == "__main__":
    name = sys.argv[1]
    dest = sys.argv[2]
    backup = {NEB: open(NEB).read(), POT: open(POT).read()}
    try:
        mutate(name)
        if build():
            run_tests(dest)
    finally:
        for f, content in backup.items():
            open(f, "w").write(content)
        print("restored")
