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
  vib    <exe> <input> <rundir>       -> xtb/landscape-vib-cli
  vibnamespace <exe> <input> <rundir> -> xtb/landscape-vib-namespace
  vibetemp <exe> <input> <rundir>     -> xtb/landscape-vib-etemp
  maxsteps <exe> <input> <rundir>     -> xtb/landscape-scan-max-steps
  scanhess <exe> <input> <rundir>     -> xtb/landscape-scan-hessian
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



def check_vib(exe, inp, rundir):
    """`--lvib` must write the `--hess` files and reproduce them from disk.

    Mirrors the CMake script of `xtb/landscape-vib-cli`: the four output files
    have to exist, the task energy has to be the reported TOTAL ENERGY (the
    `res` write-back), and a re-run with `--lvib-hessian file` must reproduce
    the frequencies of the direct numerical Hessian.
    """
    status, output = run(exe, inp, ["--gfn", "2", "--lvib", "--norestart"], rundir)
    if status != 0:
        fail("xtb --lvib terminated with status %d" % status, output)
    if "landscape: harmonic frequencies" not in output:
        fail("the frequency header was not printed", output)
    if not re.search(r"Hessian source: +numerical", output):
        fail("the Hessian source was not reported", output)
    if "landscape task terminated: frequency analysis completed" not in output:
        fail("the frequency task did not complete", output)
    if "modes: 3 internal, 6 projected zero modes" not in output:
        fail("the mode count of water is wrong", output)
    if not re.search(r"linear molecule: +F", output):
        fail("water was classified as linear", output)
    for name in ("hessian", "vibspectrum", "vib_normal_modes", "g98.out"):
        path = os.path.join(rundir, name)
        if not os.path.exists(path):
            fail("%s was not written" % name)
        if os.path.getsize(path) == 0:
            fail("%s is empty" % name)
    match = re.search(r"energy: +(-?[0-9]+[.][0-9]+)", output)
    task_energy = match.group(1) if match else ""
    match = re.search(r"TOTAL ENERGY +(-?[0-9]+[.][0-9]+)", output)
    total_energy = match.group(1) if match else ""
    if not task_energy:
        fail("the frequency task reported no energy", output)
    if task_energy != total_energy:
        fail(
            "the task energy (%s) is not the reported TOTAL ENERGY (%s)"
            % (task_energy, total_energy)
        )
    match = re.search(r"eigval : +([-0-9. ]+)", output)
    vib_freqs = " ".join(match.group(1).split()) if match else ""
    status, file_output = run(
        exe,
        inp,
        ["--gfn", "2", "--lvib", "--lvib-hessian", "file",
         "--lvib-hessian-file", "hessian", "--norestart"],
        rundir,
    )
    if status != 0:
        fail("reading the Hessian file failed with status %d" % status, file_output)
    if not re.search(r"Hessian file: +hessian", file_output):
        fail("the file provider did not report its file", file_output)
    match = re.search(r"eigval : +([-0-9. ]+)", file_output)
    file_freqs = " ".join(match.group(1).split()) if match else ""
    if file_freqs != vib_freqs:
        fail(
            "the Hessian file reproduces different frequencies (%s vs %s)"
            % (file_freqs, vib_freqs)
        )


def check_vib_namespace(exe, inp, rundir):
    """The `hessian` file of `--lvib` carries the namespace exactly once.

    Mirrors the CMake script of `xtb/landscape-vib-namespace`: with
    `--namespace ns` the task writes `ns.hessian` (the name the `--hess` path
    produces as well), not `ns.ns.hessian`, and the re-run with
    `--lvib-hessian file --lvib-hessian-file hessian --namespace ns` finds and
    reproduces it.
    """
    status, output = run(
        exe, inp, ["--gfn", "2", "--lvib", "--norestart", "--namespace", "ns"], rundir
    )
    if status != 0:
        fail("xtb --lvib --namespace ns terminated with status %d" % status, output)
    if not os.path.exists(os.path.join(rundir, "ns.hessian")):
        fail("the namespaced hessian file was not written", output)
    if os.path.exists(os.path.join(rundir, "ns.ns.hessian")):
        fail("the hessian file name carries the namespace twice")
    match = re.search(r"eigval : +([-0-9. ]+)", output)
    vib_freqs = " ".join(match.group(1).split()) if match else ""
    status, file_output = run(
        exe,
        inp,
        ["--gfn", "2", "--lvib", "--lvib-hessian", "file",
         "--lvib-hessian-file", "hessian", "--norestart", "--namespace", "ns"],
        rundir,
    )
    if status != 0:
        fail("reading the namespaced Hessian file failed with status %d" % status, file_output)
    match = re.search(r"eigval : +([-0-9. ]+)", file_output)
    file_freqs = " ".join(match.group(1).split()) if match else ""
    if file_freqs != vib_freqs:
        fail(
            "the namespaced Hessian file reproduces different frequencies (%s vs %s)"
            % (file_freqs, vib_freqs)
        )


def check_vib_etemp(exe, inp, rundir):
    """The CLI `--etemp` must reach the landscape engine.

    Mirrors the CMake script of `xtb/landscape-vib-etemp`: the engine control
    is the single source of truth for the electronic temperature, so a missing
    `main.F90` sync would silently run every landscape task at 300 K.  The
    stretched H2 input shifts its only mode by >30 % between 300 K and 5000 K
    (report 21 section 3.1), so the two runs have to report different effective
    temperatures and different frequencies.
    """
    status, cold = run(
        exe, inp, ["--gfn", "2", "--lvib", "--norestart", "--etemp", "300"], rundir
    )
    if status != 0:
        fail("xtb --lvib --etemp 300 terminated with status %d" % status, cold)
    if not re.search(r"landscape engine: etemp +300[.]000 K", cold):
        fail("the effective electronic temperature 300 K was not reported", cold)
    status, hot = run(
        exe, inp, ["--gfn", "2", "--lvib", "--norestart", "--etemp", "5000"], rundir
    )
    if status != 0:
        fail("xtb --lvib --etemp 5000 terminated with status %d" % status, hot)
    if not re.search(r"landscape engine: etemp +5000[.]000 K", hot):
        fail("--etemp 5000 did not reach the engine control (missing CLI sync)", hot)
    match = re.search(r"eigval : +([-0-9. ]+)", cold)
    cold_freqs = " ".join(match.group(1).split()) if match else ""
    match = re.search(r"eigval : +([-0-9. ]+)", hot)
    hot_freqs = " ".join(match.group(1).split()) if match else ""
    if not cold_freqs:
        fail("the 300 K run reported no frequencies", cold)
    if not hot_freqs:
        fail("the 5000 K run reported no frequencies", hot)
    if cold_freqs == hot_freqs:
        fail(
            "the electronic temperature did not change the frequencies (%s)" % cold_freqs
        )


def check_maxsteps(exe, inp, rundir):
    """`--lscan-max-steps` reaches the inner relaxation (M2 leftovers M-1/M-2).

    Mirrors the CMake script of `xtb/landscape-scan-max-steps`: with a zero
    step budget no point converges, the run stays successful but reports a
    missing minimum (NaN) and a readable diagnostic, and every evaluated point
    still reaches the scan log.  With a real budget the same scan converges.
    """
    args = [
        "--gfn", "2", "--lscan", "--lscan-coord", "angle",
        "--lscan-atoms", "2,1,3", "--lscan-step", "3", "--lscan-nstep", "2",
        "--lscan-max-steps", "0", "--norestart", "--namespace", "landscape4",
    ]
    status, output = run(exe, inp, args, rundir)
    if status != 0:
        fail("--lscan-max-steps 0 failed with status %d" % status, output)
    if "scan completed without a converged point" not in output:
        fail("the missing convergence was not reported", output)
    if not re.search(r"lowest energy: +NaN", output):
        fail("the unconverged scan reported a minimum", output)
    with open(os.path.join(rundir, "landscape4.xtbscan.log")) as handle:
        frames = len(re.findall(r"energy:", handle.read()))
    if frames != 5:
        fail("xtbscan.log holds %d frames, expected 5" % frames)
    args = [
        "--gfn", "2", "--lscan", "--lscan-coord", "angle",
        "--lscan-atoms", "2,1,3", "--lscan-step", "3", "--lscan-nstep", "2",
        "--lscan-max-steps", "256", "--lscan-level", "loose", "--norestart",
        "--namespace", "landscape4",
    ]
    status, output = run(exe, inp, args, rundir)
    if status != 0:
        fail("the reference scan failed with status %d" % status, output)
    if "landscape task terminated: scan completed" not in output:
        fail("the reference scan did not complete", output)
    if "without a converged point" in output:
        fail("the reference scan reported a missing minimum", output)


def check_scanhess(exe, inp, rundir):
    """`--lscan-hessian` reaches the engine of the scan points."""
    args = [
        "--gfn", "2", "--lscan", "--lscan-method", "rfo",
        "--lscan-hessian", "model", "--lscan-coord", "angle",
        "--lscan-atoms", "2,1,3", "--lscan-step", "3", "--lscan-nstep", "1",
        "--lscan-level", "loose", "--norestart",
    ]
    status, output = run(exe, inp, args, rundir)
    if status != 0:
        fail("--lscan-hessian model failed with status %d" % status, output)
    if not re.search(r"Hessian source: +model", output):
        fail("the scan Hessian source was not reported", output)


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
    elif mode == "vib":
        check_vib(exe, inp, rundir)
    elif mode == "vibnamespace":
        check_vib_namespace(exe, inp, rundir)
    elif mode == "vibetemp":
        check_vib_etemp(exe, inp, rundir)
    elif mode == "maxsteps":
        check_maxsteps(exe, inp, rundir)
    elif mode == "scanhess":
        check_scanhess(exe, inp, rundir)
    elif mode == "error":
        if len(rest) < 2:
            fail("the error mode needs a pattern and the xtb arguments")
        check_error(exe, inp, rundir, rest[0], rest[1:])
    else:
        fail("unknown mode %r" % mode)


if __name__ == "__main__":
    main()
