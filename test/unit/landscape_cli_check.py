#!/usr/bin/env python3
"""CLI level checks of the landscape suite for the meson build.

The CMake build drives these checks with small `cmake -P` scripts
(`test/unit/CMakeLists.txt`); meson cannot inspect the output of a test, so the
same checks are implemented here and invoked as meson test programs.  Every
mode mirrors one CMake test one-to-one:

  energy <exe> <input> <rundir>       -> xtb/landscape-opt-energy
  acc    <exe> <input> <rundir>       -> xtb/landscape-opt-acc
  hessian <exe> <input> <rundir>      -> xtb/landscape-opt-hessian
  scf    <exe> <input> <rundir>       -> xtb/landscape-scf-failure
  scanfail <exe> <input> <rundir>     -> xtb/landscape-scan-failed-point
  error  <exe> <input> <rundir> <pattern> <arg>...  -> the `--lopt`/`--lscan`
                                          error branches of the CMake build

The environment (XTBPATH) is inherited from the meson test environment, exactly
like in the CMake build.
"""

import os
import re
import subprocess
import sys


def run(exe, inp, args, rundir):
    """Run xtb and return (status, combined output)."""
    os.makedirs(rundir, exist_ok=True)
    proc = subprocess.run(
        [exe, inp] + args,
        cwd=rundir,
        capture_output=True,
        text=True,
    )
    return proc.returncode, proc.stdout + proc.stderr


def fail(message, output=""):
    print("FAIL: " + message)
    if output:
        print(output)
    sys.exit(1)


def check_energy(exe, inp, rundir):
    """The TOTAL ENERGY line must be the energy written to xtbopt.xyz."""
    status, output = run(exe, inp, ["--gfn", "2", "--lopt", "--norestart"], rundir)
    if status != 0:
        fail("xtb --lopt terminated with status %d" % status, output)
    match = re.search(r"TOTAL ENERGY +(-?[0-9]+\.[0-9]+)", output)
    if not match:
        fail("no TOTAL ENERGY in the output", output)
    stdout_energy = match.group(1)
    with open(os.path.join(rundir, "xtbopt.xyz")) as handle:
        xyz = handle.read()
    match = re.search(r"energy: +(-?[0-9]+\.[0-9]+)", xyz)
    if not match:
        fail("no energy in xtbopt.xyz", xyz)
    if stdout_energy != match.group(1):
        fail(
            "TOTAL ENERGY (%s) differs from xtbopt.xyz (%s)"
            % (stdout_energy, match.group(1))
        )


def opt_result(exe, inp, args, rundir):
    """Run one minimisation and return (reported accuracy, xtbopt energy line)."""
    xyzfile = os.path.join(rundir, "xtbopt.xyz")
    if os.path.exists(xyzfile):
        os.remove(xyzfile)
    status, output = run(
        exe, inp, ["--gfn", "2", "--lopt", "--norestart"] + args, rundir
    )
    if status != 0:
        fail("xtb --lopt %s failed with status %d" % (" ".join(args), status), output)
    with open(xyzfile) as handle:
        match = re.search(r"energy: [^\n]*", handle.read())
    result = match.group(0) if match else ""
    match = re.search(r"landscape engine: SCC accuracy +([0-9.]+)", output)
    return (match.group(1) if match else "", result, output)


def check_acc(exe, inp, rundir):
    """`--acc` must reach the engine control and change the result."""
    default_acc, default_result, output = opt_result(exe, inp, [], rundir)
    acc_acc, acc_result, _ = opt_result(exe, inp, ["--acc", "0.05"], rundir)
    if default_acc != "1.000000":
        fail("the default run reported accuracy %r" % default_acc, output)
    if acc_acc != "0.050000":
        fail("--acc 0.05 did not reach the engine control (%r)" % acc_acc)
    if default_result == acc_result:
        fail("--acc 0.05 had no effect on the --lopt result (%s)" % default_result)


def check_hessian(exe, inp, rundir):
    """`--lopt-hessian` must reach the engine and stay comparable."""
    cases = [
        ("model_lbfgs", ["--lopt-engine", "lbfgs", "--lopt-hessian", "model"], "model"),
        ("num_lbfgs", ["--lopt-engine", "lbfgs", "--lopt-hessian", "numerical"], "numerical"),
        ("model_rfo", ["--lopt-engine", "rfo", "--lopt-hessian", "model"], "model"),
        ("num_rfo", ["--lopt-engine", "rfo", "--lopt-hessian", "numerical"], "numerical"),
    ]
    energies = {}
    for name, args, expected_source in cases:
        status, output = run(
            exe, inp, ["--gfn", "2", "--lopt", "--norestart"] + args, rundir
        )
        if status != 0:
            fail("xtb --lopt %s failed with status %d" % (" ".join(args), status), output)
        if "landscape: converged" not in output:
            fail("xtb --lopt %s did not converge" % " ".join(args), output)
        match = re.search(r"Hessian source: +([a-z]+)", output)
        found = match.group(1) if match else ""
        if found != expected_source:
            fail(
                "%s reported Hessian source %r, expected %r"
                % (name, found, expected_source)
            )
        with open(os.path.join(rundir, "xtbopt.xyz")) as handle:
            xyz = handle.read()
        match = re.search(r"energy: +(-?[0-9]+\.[0-9]{3})", xyz)
        if not match:
            fail("the %s run reported no energy" % name, xyz)
        energies[name] = match.group(1)
    for first, second in (("model_lbfgs", "num_lbfgs"), ("model_rfo", "num_rfo")):
        if energies[first] != energies[second]:
            fail(
                "%s and %s converge to different energies (%s vs %s)"
                % (first, second, energies[first], energies[second])
            )


def check_scf(exe, inp, rundir):
    """An unconverged SCC must abort the run with a non-zero status."""
    os.makedirs(rundir, exist_ok=True)
    xcontrol = os.path.join(rundir, "scf_fail.inp")
    with open(xcontrol, "w") as handle:
        handle.write("$scc\n maxiterations=1\n$end\n")
    status, output = run(
        exe,
        inp,
        ["--gfn", "2", "--lopt", "--input", xcontrol, "--norestart"],
        rundir,
    )
    if status == 0:
        fail("the unconverged SCC did not fail the run", output)
    if "landscape: converged" in output:
        fail("a converged landscape run was reported", output)


def check_scanfail(exe, inp, rundir):
    """A scan point without an energy must be reported and not written.

    A rigid distance scan with a 5 angstrom step puts the second point at
    5.96 angstrom, where the SCC of the single point fails.  The run has to
    end with a non-zero status and a readable diagnostic, and the scan log
    must not contain a frame with a fabricated zero energy (nor a frame per
    requested point, since a point without an energy has none).
    """
    args = [
        "--gfn", "2", "--lscan", "--lscan-mode", "rigid",
        "--lscan-coord", "distance", "--lscan-atoms", "1,2",
        "--lscan-step", "5.0", "--lscan-nstep", "2",
        "--namespace", "landscape3",
    ]
    status, output = run(exe, inp, args, rundir)
    if status == 0:
        fail("the failed scan points did not fail the run", output)
    if "scan points failed" not in output:
        fail("the failed scan points were not reported", output)
    with open(os.path.join(rundir, "landscape3.xtbscan.log")) as handle:
        scanlog = handle.read()
    if "energy: 0.000000000000" in scanlog:
        fail("a failed scan point was written with a zero energy", scanlog)
    frames = len(re.findall(r"energy:", scanlog))
    if frames >= 5:
        fail("the scan log holds %d frames, expected fewer than 5" % frames)


def check_error(exe, inp, rundir, pattern, args):
    """An invalid request must abort with a non-zero status and a message."""
    status, output = run(exe, inp, args, rundir)
    if status == 0:
        fail("expected a non-zero exit for '%s'" % " ".join(args), output)
    if not re.search(pattern, output):
        fail("missing %r in the output of '%s'" % (pattern, " ".join(args)), output)


def main():
    if len(sys.argv) < 5:
        fail("usage: landscape_cli_check.py MODE EXE INPUT RUNDIR [ARGS]")
    mode, exe, inp, rundir = sys.argv[1:5]
    rest = sys.argv[5:]
    if mode == "energy":
        check_energy(exe, inp, rundir)
    elif mode == "acc":
        check_acc(exe, inp, rundir)
    elif mode == "hessian":
        check_hessian(exe, inp, rundir)
    elif mode == "scf":
        check_scf(exe, inp, rundir)
    elif mode == "scanfail":
        check_scanfail(exe, inp, rundir)
    elif mode == "error":
        if len(rest) < 2:
            fail("the error mode needs a pattern and the xtb arguments")
        check_error(exe, inp, rundir, rest[0], rest[1:])
    else:
        fail("unknown mode %r" % mode)


if __name__ == "__main__":
    main()
