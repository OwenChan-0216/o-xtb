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
  ts     <exe> <input> <rundir>       -> xtb/landscape-ts-prfo
  tsetemp <exe> <input> <rundir>      -> xtb/landscape-ts-etemp
  dimer  <exe> <input> <rundir>       -> xtb/landscape-ts-dimer
  tsminimum <exe> <input> <rundir>    -> xtb/landscape-ts-minimum
  tsnamespace <exe> <input> <rundir>  -> xtb/landscape-ts-namespace
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


def check_ts(exe, inp, rundir):
    """`--lts` locates a first order saddle point and writes its two files.

    Mirrors the CMake script of `xtb/landscape-ts-prfo`.  The input is a bent
    HCN, a guess for the HCN/HNC transition state; P-RFO converges in a few
    steps to a stationary point with exactly one imaginary mode, which is the
    definition of the requested saddle point.  The frozen electronic
    temperature is part of the output (M4 hard constraint 1).
    """
    for name in ("xtbts.xyz", "xtbts.log"):
        path = os.path.join(rundir, name)
        if os.path.exists(path):
            os.remove(path)
    status, output = run(
        exe, inp, ["--gfn", "2", "--lts", "--lts-method", "prfo", "--norestart"], rundir
    )
    if status != 0:
        fail("xtb --lts terminated with status %d" % status, output)
    if "landscape: converged" not in output:
        fail("the transition state search did not converge", output)
    if "saddle confirmation - imaginary modes: 1" not in output:
        fail("the located point is not a first order saddle point", output)
    if not re.search(r"landscape engine: etemp +300[.]000 K", output):
        fail("the frozen electronic temperature was not reported", output)
    for name in ("xtbts.xyz", "xtbts.log"):
        path = os.path.join(rundir, name)
        if not os.path.exists(path):
            fail("%s was not written" % name)
        if os.path.getsize(path) == 0:
            fail("%s is empty" % name)
    with open(os.path.join(rundir, "xtbts.log")) as handle:
        log = handle.read()
    if "confirmation imaginary modes: 1" not in log:
        fail("the log does not report the imaginary mode count", log)
    # the restricted step branch has to reach the same kind of stationary point
    status, output = run(
        exe, inp, ["--gfn", "2", "--lts", "--lts-method", "bprfo", "--norestart"], rundir
    )
    if status != 0:
        fail("xtb --lts --lts-method bprfo terminated with status %d" % status, output)
    if "landscape: converged" not in output:
        fail("the B-PRFO search did not converge", output)
    if "saddle confirmation - imaginary modes: 1" not in output:
        fail("the B-PRFO point is not a first order saddle point", output)


def check_dimer(exe, inp, rundir):
    """`--lts --lts-method dimer` locates a saddle point without a Hessian.

    Mirrors the CMake script of `xtb/landscape-ts-dimer`.  The search starts
    from the deterministic `force` initial axis (the largest Cartesian
    gradient component direction, PLAN section 6.3), converges to a first
    order saddle point of the bent HCN, writes `xtbts.xyz`/`xtbts.log` and
    prints its rotation/torque and curvature diagnostics together with the
    frozen electronic temperature.
    """
    for name in ("xtbts.xyz", "xtbts.log"):
        path = os.path.join(rundir, name)
        if os.path.exists(path):
            os.remove(path)
    status, output = run(
        exe, inp,
        ["--gfn", "2", "--lts", "--lts-method", "dimer", "--lts-ninit", "force",
         "--norestart"],
        rundir,
    )
    if status != 0:
        fail("xtb --lts --lts-method dimer terminated with status %d" % status, output)
    if "dimer initial axis: force" not in output:
        fail("the deterministic initial axis was not used", output)
    if "landscape: converged" not in output:
        fail("the dimer search did not converge", output)
    if "saddle confirmation - imaginary modes: 1" not in output:
        fail("the dimer point is not a first order saddle point", output)
    if not re.search(r"landscape engine: etemp +300[.]000 K", output):
        fail("the frozen electronic temperature was not reported", output)
    if not re.search(r"dimer rotation: iterations [0-9]+, torque rms", output):
        fail("the rotation/torque diagnostic is missing", output)
    if "dimer curvature:" not in output:
        fail("the curvature diagnostic is missing", output)
    for name in ("xtbts.xyz", "xtbts.log"):
        path = os.path.join(rundir, name)
        if not os.path.exists(path):
            fail("%s was not written" % name)
        if os.path.getsize(path) == 0:
            fail("%s is empty" % name)
    with open(os.path.join(rundir, "xtbts.log")) as handle:
        log = handle.read()
    if "confirmation imaginary modes: 1" not in log:
        fail("the log does not report the imaginary mode count", log)
    if "dimer" not in log:
        fail("the log does not identify the dimer method", log)


def check_ts_minimum(exe, inp, rundir):
    """A search that converges to a minimum is not a transition state.

    Mirrors the CMake script of `xtb/landscape-ts-minimum` (H2 of
    `29-m4-independent-review.md`): from a linear HNC the P-RFO search lands on
    the molecule's own minimum (0 imaginary modes) when the escape out of a
    minimum is disabled (`--lts-escape-step 0`); the run must abort with a
    non-zero status, print the diagnosis, and still write `xtbts.xyz`/
    `xtbts.log` for debugging.  With the default escape the same input finds
    the saddle point (`check_ts_escape`).
    """
    for name in ("xtbts.xyz", "xtbts.log"):
        path = os.path.join(rundir, name)
        if os.path.exists(path):
            os.remove(path)
    status, output = run(
        exe, inp,
        ["--gfn", "2", "--lts", "--lts-method", "prfo", "--norestart",
         "--lts-escape-step", "0"],
        rundir,
    )
    if status == 0:
        fail("a minimum was accepted as a transition state", output)
    if "saddle confirmation - imaginary modes: 0" not in output:
        fail("the imaginary mode count is not reported", output)
    if "confirmation: minimum" not in output:
        fail("the minimum was not named as such", output)
    if "not a first order saddle point" not in output:
        fail("the failure was not reported", output)
    for name in ("xtbts.xyz", "xtbts.log"):
        if not os.path.exists(os.path.join(rundir, name)):
            fail("%s was not written despite the failure" % name)


def check_ts_escape(exe, inp, rundir):
    """The escape walk turns a minimum start into a successful search.

    Mirrors the CMake script of `xtb/landscape-ts-escape` (MEDIUM-1 of
    `31-m4-review-round2.md`): from the same linear minimum as
    `check_ts_minimum`, the driver walks the geometry along the lowest
    internal mode until its curvature turns negative and the search then
    reaches the HCN/HNC saddle point with exactly one imaginary mode.
    """
    for name in ("xtbts.xyz", "xtbts.log"):
        path = os.path.join(rundir, name)
        if os.path.exists(path):
            os.remove(path)
    status, output = run(
        exe, inp, ["--gfn", "2", "--lts", "--lts-method", "prfo", "--norestart"], rundir
    )
    if status != 0:
        fail("the escaped search terminated with status %d" % status, output)
    if not re.search(r"escape from a minimum: +[0-9]+ push", output):
        fail("the escape walk out of the minimum was not reported", output)
    if not re.search(r"escape from a minimum: +0[.]200000 bohr", output):
        fail("the configured escape displacement was not reported", output)
    if not re.search(r"selected mode, rigid body overlap: +0[.]000000", output):
        fail("a rigid body direction was followed", output)
    if "saddle confirmation - imaginary modes: 1" not in output:
        fail("the escaped search did not reach a first order saddle", output)
    if "confirmation: first order saddle point" not in output:
        fail("the saddle confirmation is missing", output)
    for name in ("xtbts.xyz", "xtbts.log"):
        if not os.path.exists(os.path.join(rundir, name)):
            fail("%s was not written" % name)
    with open(os.path.join(rundir, "xtbts.log")) as handle:
        log = handle.read()
    if "confirmation imaginary modes: 1" not in log:
        fail("the log does not report the imaginary mode count", log)
    status, output = run(
        exe, inp, ["--gfn", "2", "--lts", "--lts-method", "bprfo", "--norestart"], rundir
    )
    if status != 0:
        fail("the escaped B-PRFO search terminated with status %d" % status, output)
    if not re.search(r"escape from a minimum: +[0-9]+ push", output):
        fail("the B-PRFO escape walk was not reported", output)
    if "saddle confirmation - imaginary modes: 1" not in output:
        fail("the escaped B-PRFO search did not reach a saddle", output)


def check_ts_namespace(exe, inp, rundir):
    """`--namespace ns --lts` writes `ns.xtbts.xyz`/`ns.xtbts.log`.

    Mirrors the CMake script of `xtb/landscape-ts-namespace` (M3 of
    `29-m4-independent-review.md`): the file names pass through
    `get_namespace` exactly like `--lscan` and `--lvib`, so a namespaced run
    does not collide with a plain one.
    """
    for name in ("landscape6.xtbts.xyz", "landscape6.xtbts.log"):
        path = os.path.join(rundir, name)
        if os.path.exists(path):
            os.remove(path)
    status, output = run(
        exe, inp,
        ["--gfn", "2", "--lts", "--lts-method", "prfo", "--norestart",
         "--namespace", "landscape6"],
        rundir,
    )
    if status != 0:
        fail("xtb --lts --namespace terminated with status %d" % status, output)
    for name in ("landscape6.xtbts.xyz", "landscape6.xtbts.log"):
        if not os.path.exists(os.path.join(rundir, name)):
            fail("%s was not written (namespace not applied)" % name)


def check_ts_etemp(exe, inp, rundir):
    """The CLI `--etemp` must reach the transition state engine.

    Mirrors the CMake script of `xtb/landscape-ts-etemp`: the settings carry the
    frozen temperature and `main.F90` has to synchronise them from `set%etemp`,
    so a missing sync would leave the task at 300 K.  Both the frozen value and
    the value read back from the calculator are checked against 5000 K.
    """
    status, output = run(
        exe, inp,
        ["--gfn", "2", "--lts", "--lts-method", "prfo", "--etemp", "5000",
         "--norestart"],
        rundir,
    )
    if status != 0:
        fail("xtb --lts --etemp 5000 terminated with status %d" % status, output)
    if not re.search(r"electronic temperature: +5000[.]000 K", output):
        fail("the frozen electronic temperature is not 5000 K", output)
    if not re.search(r"landscape engine: etemp +5000[.]000 K", output):
        fail("--etemp 5000 did not reach the engine control (missing CLI sync)", output)
    # MEDIUM-3: the result field itself (`etemp:` of `landscape_result%write_log`
    # and the frozen value of `xtbts.log`) must carry the effective temperature
    if not re.search(r"etemp: +5000[.]000 K", output):
        fail("the result object does not carry the effective etemp", output)
    with open(os.path.join(rundir, "xtbts.log")) as handle:
        log = handle.read()
    if not re.search(r"electronic temperature \(frozen\): +5000[.]000 K", log):
        fail("xtbts.log does not carry the effective etemp", log)


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
    elif mode == "ts":
        check_ts(exe, inp, rundir)
    elif mode == "tsetemp":
        check_ts_etemp(exe, inp, rundir)
    elif mode == "tsminimum":
        check_ts_minimum(exe, inp, rundir)
    elif mode == "tsescape":
        check_ts_escape(exe, inp, rundir)
    elif mode == "tsnamespace":
        check_ts_namespace(exe, inp, rundir)
    elif mode == "dimer":
        check_dimer(exe, inp, rundir)
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
