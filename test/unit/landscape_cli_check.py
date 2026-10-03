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
  optnamespace <exe> <input> <rundir> -> xtb/landscape-opt-namespace
  ljsonnorun <exe> <input> <rundir>   -> xtb/landscape-ljson-no-runtype
  vibetemp <exe> <input> <rundir>     -> xtb/landscape-vib-etemp
  fix    <exe> <input> <rundir>       -> xtb/landscape-fix-rfo
  scanblock <exe> <input> <rundir>    -> xtb/landscape-scan-xcontrol
  saddlefix <exe> <input> <rundir>    -> xtb/landscape-lts-fix
  rejectfix <exe> <input> <rundir>    -> xtb/landscape-lirc-fix
    thermo <exe> <input> <rundir>       -> xtb/landscape-vib-thermo
  thermoknobs <exe> <input> <rundir> <saddle>
                                     -> xtb/landscape-vib-thermo-knobs
  ts     <exe> <input> <rundir>       -> xtb/landscape-ts-prfo
  tsetemp <exe> <input> <rundir>      -> xtb/landscape-ts-etemp
  dimer  <exe> <input> <rundir>       -> xtb/landscape-ts-dimer
  tsminimum <exe> <input> <rundir>    -> xtb/landscape-ts-minimum
  tsnamespace <exe> <input> <rundir>  -> xtb/landscape-ts-namespace
  maxsteps <exe> <input> <rundir>     -> xtb/landscape-scan-max-steps
  scanhess <exe> <input> <rundir>     -> xtb/landscape-scan-hessian
  autonebdepth <exe> <input> <rundir> <product>
                                     -> xtb/landscape-path-autoneb-depth-limit
  irc    <exe> <input> <rundir>       -> xtb/landscape-irc-cli
  ircpc  <exe> <input> <rundir>       -> xtb/landscape-irc-pc
  ircknobs <exe> <input> <rundir>     -> xtb/landscape-irc-knobs
  irctermination <exe> <input> <rundir> -> xtb/landscape-irc-termination
  ircswap <exe> <input> <rundir>     -> xtb/landscape-irc-swap
  error  <exe> <input> <rundir> <pattern> <arg>...  -> the `--lopt`/`--lscan`
                                          error branches of the CMake build

The environment (XTBPATH) is inherited from the meson test environment, exactly
like in the CMake build.
"""

import json
import os
import re
import shutil
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
    # the direct run builds the numerical Hessian from 6N displaced single
    # points plus the gradient of the input geometry: 1 + 6*3 = 19 for water
    match = re.search(r"landscape engine: energy evaluations +(\d+)", output)
    if not match:
        fail("the direct run reports no evaluation counter", output)
    direct_eval = int(match.group(1))
    if direct_eval != 19:
        fail("the direct --lvib run used %d evaluations, expected 1+6N = 19"
             % direct_eval, output)
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
    # the file provider must *save* the displaced single points: reading the
    # file needs the gradient of the input geometry only (19 -> 1 for water),
    # otherwise a provider that silently recomputed the Hessian would be green
    match = re.search(r"landscape engine: energy evaluations +(\d+)", file_output)
    if not match:
        fail("the file run reports no evaluation counter", file_output)
    file_eval = int(match.group(1))
    if file_eval != 1:
        fail("--lvib-hessian file used %d evaluations, expected 1; the "
             "provider did not reuse the file" % file_eval, file_output)
    if direct_eval <= file_eval:
        fail("the Hessian file did not save evaluations (%d vs %d)"
             % (direct_eval, file_eval))
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
    produces as well), not `ns.ns.hessian`, every other output carries the
    prefix too (`ns.vibspectrum`, `ns.vib_normal_modes`, `ns.g98.out`), and the
    re-run with `--lvib-hessian file --lvib-hessian-file hessian --namespace
    ns` finds and reproduces the file.  The rundir is removed at entry, because
    the check asserts the *absence* of the unprefixed output names.
    """
    rundir = os.path.abspath(rundir)
    shutil.rmtree(rundir, ignore_errors=True)
    status, output = run(
        exe, inp, ["--gfn", "2", "--lvib", "--norestart", "--namespace", "ns"], rundir
    )
    if status != 0:
        fail("xtb --lvib --namespace ns terminated with status %d" % status, output)
    if not os.path.exists(os.path.join(rundir, "ns.hessian")):
        fail("the namespaced hessian file was not written", output)
    if os.path.exists(os.path.join(rundir, "ns.ns.hessian")):
        fail("the hessian file name carries the namespace twice")
    # every other output of the task carries the namespace as well
    for name in ("hessian", "vibspectrum", "vib_normal_modes", "g98.out"):
        if not os.path.exists(os.path.join(rundir, "ns." + name)):
            fail("--namespace ns wrote no ns.%s" % name, output)
        if os.path.exists(os.path.join(rundir, name)):
            fail("--namespace ns also wrote the unprefixed %s" % name)
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


def check_fix(exe, inp, rundir):
    """`$fix` must hold the frozen atoms for every minimiser.

    Mirrors `xtb/landscape-fix-rfo`.  A first order direction is built from
    the gradient, and the calculator zeroes the gradient of a fixed atom
    (`src/xtb/calculator.f90:304-306`), so SD/CG/L-BFGS/BFGS/GDIIS keep it in
    place by construction.  The RFO step is expanded in the eigenvectors of the
    Hessian, which mix the frozen and the free components, so it moved the
    frozen oxygen of this fixture by 0.0098/0.0109 angstrom in x/z before the
    direction was projected (docs/_simplify-recon/04-*.md).  `--lopt-hessian
    model` seeds BFGS with the Lindh-D2 matrix as well, so that combination is
    covered here too.  The tolerance is
    the xyz write/read round trip (the writer prints 14 decimals), not a
    measured spread: a projected direction leaves the coordinate unchanged.
    """
    xcontrol = os.path.join(rundir, "landscape_fix.inp")
    os.makedirs(rundir, exist_ok=True)
    rundir = os.path.abspath(rundir)
    xcontrol = os.path.abspath(xcontrol)
    with open(xcontrol, "w") as handle:
        handle.write("$fix\n   atoms: 1\n$end\n")
    geometry = os.path.join(rundir, "xtbopt.xyz")
    # The first order engines are only *provably* decoupled when their seed is
    # decoupled as well: `--lopt-hessian model` seeds BFGS with the Lindh-D2
    # curvature matrix (`optimize/driver.f90` -> `landscape_bfgs%set_hessian`),
    # whose frozen and free blocks are coupled, and the BFGS direction is
    # expanded in the eigenvectors of that matrix exactly like the RFO one
    # (`optimize/bfgs.f90`, `d = -sum_i (V_i.g)/max(w_i, hlow) V_i`).  The
    # projection is therefore not a no-op for `bfgs model`/`rfo model` either,
    # so the two combinations are covered here (finding P2-3 of
    # `05-w0-independent-review.md`).
    cases = [("sd", "sd", []), ("cg", "cg", []), ("lbfgs", "lbfgs", []),
             ("bfgs", "bfgs", []), ("diis", "diis", []), ("rfo", "rfo", []),
             ("bfgs model", "bfgs", ["--lopt-hessian", "model"]),
             ("rfo model", "rfo", ["--lopt-hessian", "model"])]
    for label, engine, extra in cases:
        if os.path.exists(geometry):
            os.remove(geometry)
        status, output = run(
            exe,
            inp,
            ["--gfn", "2", "--lopt", "--lopt-engine", engine,
             "--input", xcontrol, "--norestart"] + extra,
            rundir,
        )
        if status != 0:
            fail("xtb --lopt-engine %s terminated with status %d" % (label, status),
                 output)
        if "landscape: converged" not in output:
            fail("the --lopt-engine %s run did not converge" % label, output)
        if not os.path.exists(geometry):
            fail("the --lopt-engine %s run wrote no xtbopt.xyz" % label, output)
        with open(geometry) as handle:
            lines = handle.read().splitlines()
        fields = lines[2].split()
        if fields[0] != "O":
            fail("the first output atom of %s is not the frozen oxygen" % label,
                 lines[2])
        shift = max(abs(float(value)) for value in fields[1:4])
        if shift > 1.0e-10:
            fail(
                "--lopt-engine %s moved the frozen atom by %.5e angstrom (%s)"
                % (label, shift, " ".join(fields[1:4])),
                output,
            )
        print("fix projection: %-11s frozen atom displacement %.5e angstrom"
              % (label, shift))


def check_scanblock(exe, inp, rundir):
    """A landscape run type must reject the xcontrol `$scan` block.

    Mirrors `xtb/landscape-scan-xcontrol`.  `$scan` belongs to the ANCopt
    family - `relaxed_scan` runs it only on the `anyopt` path
    (`src/prog/main.F90:914-916`) - and no landscape run type executes it.
    Before the guard, `--lopt --input <file with $scan>` returned status 0 after
    a plain minimisation and wrote no `xtbscan.log`: the caller asked for a scan
    and silently got a different task.  The check pins the non-zero status, the
    actionable message and the absence of the scan log for all five run types,
    and that `--opt` still runs the block.
    """
    os.makedirs(rundir, exist_ok=True)
    rundir = os.path.abspath(rundir)
    xcontrol = os.path.join(rundir, "landscape_scan.inp")
    with open(xcontrol, "w") as handle:
        handle.write("$constrain\n  distance: 1, 2, auto\n"
                     "$scan\n  1: 0.9, 1.1, 3\n$end\n")
    scanlog = os.path.join(rundir, "xtbscan.log")
    for task in ("lopt", "lscan", "lts", "lirc", "lvib"):
        if task == "lscan":
            # a *valid* `--lscan` command line: the `$scan` block is rejected
            # even though the run type itself is fine
            extra = ["--lscan-coord", "distance", "--lscan-atoms", "1,2",
                     "--lscan-step", "0.05", "--lscan-nstep", "2"]
        else:
            extra = []
        if os.path.exists(scanlog):
            os.remove(scanlog)
        status, output = run(
            exe,
            inp,
            ["--gfn", "2", "--" + task] + extra
            + ["--input", xcontrol, "--norestart"],
            rundir,
        )
        if status == 0:
            fail("xtb --%s accepted the xcontrol $scan block" % task, output)
        if "does not execute the xcontrol $scan block" not in output:
            fail("xtb --%s did not explain the rejected $scan block" % task, output)
        if os.path.exists(scanlog):
            fail("xtb --%s wrote xtbscan.log although it refused the $scan block"
                 % task, output)
        print("scan block: --%s rejected the $scan block with status %d"
              % (task, status))
    # the ANCopt path still executes the block
    optdir = os.path.join(rundir, "opt")
    status, output = run(
        exe, inp, ["--gfn", "2", "--opt", "--input", xcontrol, "--norestart"],
        optdir,
    )
    if status != 0:
        fail("xtb --opt with a $scan block terminated with status %d" % status, output)
    if "RELAXED SCAN" not in output:
        fail("--opt did not run the $scan block", output)
    if not os.path.exists(os.path.join(optdir, "xtbscan.log")):
        fail("--opt did not write xtbscan.log", output)


def read_thermo(text):
    """Enthalpy and free energy (hartree) of a thermochemistry printout."""
    match = re.search(r"total free energy\s+(-?[\d.]+) Eh", text)
    if not match:
        fail("no total free energy in the output", text)
    gibbs = float(match.group(1))
    match = re.search(r"TOTAL ENTHALPY\s+(-?[\d.]+) Eh", text)
    if match:
        enthalpy = float(match.group(1))
    else:
        match = re.search(r"total enthalpy H\(T\):\s+(-?[\d.]+) Eh", text)
        if not match:
            fail("no total enthalpy in the output", text)
        enthalpy = float(match.group(1))
    return enthalpy, gibbs


def read_json(rundir, name):
    """Load a `--ljson` document of `rundir`."""
    path = os.path.join(rundir, name)
    if not os.path.exists(path):
        fail("no %s in %s" % (name, rundir))
    with open(path) as handle:
        return json.load(handle)


def check_thermo(exe, inp, rundir):
    """`--lvib` thermochemistry follows the `$thermo` priority rule.

    Mirrors `xtb/landscape-vib-thermo`.  Priority: explicit command line >
    xcontrol `$thermo` > builtin default.  Before the fix `--lvib` overwrote
    all four keys of the block unconditionally, so `$thermo temp=298.15,300,400`
    collapsed to the single 298.15 K the settings carried and `scale=0.9` was
    ignored, while `--hess` honoured both: the two routes disagreed by 7.5e-3
    hartree on one geometry whose validated agreement is 1e-6 (the projector
    spread, docs/_landscape-recon/49-*.md).  The comparisons below are made at
    a *tight* minimum, which is where that tolerance is calibrated.
    """
    os.makedirs(rundir, exist_ok=True)
    rundir = os.path.abspath(rundir)
    inputs = {
        "list": "$thermo\n   temp=298.15,300.0,400.0\n$end\n",
        "scale": "$thermo\n   scale=0.9000\n   temp=298.15\n$end\n",
        "temp298": "$thermo\n   temp=298.15\n$end\n",
        "temp400": "$thermo\n   temp=400.0\n$end\n",
    }
    for name, block in inputs.items():
        with open(os.path.join(rundir, name + ".inp"), "w") as handle:
            handle.write(block)

    # the thermochemistry table of `--hess` and `--lvib` has to agree, so the
    # geometry must be a (tight) minimum
    status, output = run(exe, inp, ["--gfn", "2", "--lopt", "--lopt-level", "tight",
                                    "--norestart"], rundir)
    if status != 0:
        fail("the thermochemistry optimisation terminated with status %d" % status,
             output)
    geometry = os.path.join(rundir, "xtbopt.xyz")
    if not os.path.exists(geometry):
        fail("the thermochemistry optimisation wrote no xtbopt.xyz", output)

    def thermo(task, args):
        status, output = run(exe, geometry, ["--gfn", "2", "--" + task,
                                             "--norestart"] + args, rundir)
        if status != 0:
            fail("xtb --%s %s terminated with status %d"
                 % (task, " ".join(args), status), output)
        return read_thermo(output), output

    for name in ("list", "scale"):
        (vh, vg), vib_out = thermo("lvib", ["-I", name + ".inp"])
        (hh, hg), hess_out = thermo("hess", ["-I", name + ".inp"])
        if abs(vg - hg) > 1.0e-6 or abs(vh - hh) > 1.0e-6:
            fail("the --lvib and --hess thermochemistry disagree on %s by "
                 "%.3e/%.3e hartree (H/G, tolerance 1e-6)\n--lvib:\n%s\n--hess:\n%s"
                 % (name, vh - hh, vg - hg, vib_out, hess_out))
        print("thermo: %-5s --lvib vs --hess  dH %.3e, dG %.3e hartree"
              % (name, vh - hh, vg - hg))

    # `temp=298.15,300.0,400.0` must produce one table row per temperature; the
    # summary reports the *last* one, here 400 K (the same value `--hess`
    # prints)
    (_, list_g), list_out = thermo("lvib", ["-I", "list.inp"])
    for temperature in ("298.15", "300.00", "400.00"):
        if not re.search(r"^ *%s +VIB" % re.escape(temperature), list_out, re.M):
            fail("the `$thermo temp` list lost the %s K row" % temperature, list_out)
    (_, temp400_g), _ = thermo("lvib", ["-I", "temp400.inp"])
    if abs(list_g - temp400_g) > 1.0e-9:
        fail("`temp=298.15,300.0,400.0` does not report the 400 K value "
             "(%.12f vs %.12f)" % (list_g, temp400_g))

    (_, default_g), _ = thermo("lvib", [])
    if abs(default_g - temp400_g) < 1.0e-9:
        fail("the xcontrol `temp=400` did not override the builtin 298.15 K")
    # explicit command line beats the xcontrol block
    (_, cli_g), _ = thermo("lvib", ["-I", "temp298.inp", "--lvib-temp", "400"])
    if abs(cli_g - temp400_g) > 1.0e-9:
        fail("--lvib-temp 400 did not override `$thermo temp=298.15` "
             "(%.12f vs %.12f)" % (cli_g, temp400_g))
    # ... and the xcontrol block beats the builtin default (same value here)
    (_, xc_g), _ = thermo("lvib", ["-I", "temp400.inp"])
    if abs(xc_g - cli_g) > 1.0e-9:
        fail("`$thermo temp=400` differs from `--lvib-temp 400` "
             "(%.12f vs %.12f)" % (xc_g, cli_g))
    print("thermo: CLI `--lvib-temp 400` == xcontrol `temp=400` == %.12f Eh" % cli_g)

    # the same for `scale`: the CLI value and the xcontrol value are the same
    # 0.9 on the same (builtin) temperature
    (scaled_h, scaled_g), scaled_out = thermo("lvib", ["-I", "scale.inp"])
    (cli_h, cli_g2), cli_out = thermo("lvib", ["--lvib-freq-scal", "0.9"])
    if abs(scaled_g - cli_g2) > 1.0e-9 or abs(scaled_h - cli_h) > 1.0e-9:
        fail("`$thermo scale=0.9` and `--lvib-freq-scal 0.9` differ "
             "(%.12f vs %.12f)\n%s\n%s" % (scaled_g, cli_g2, scaled_out, cli_out))
    if abs(scaled_g - default_g) < 1.0e-9:
        fail("the xcontrol `scale=0.9` did not change the thermochemistry")
    print("thermo: xcontrol `scale=0.9` == CLI `--lvib-freq-scal 0.9` == %.12f Eh"
          % scaled_g)

    # --- `--ljson` records the *effective* temperature, not the settings -----
    # default (finding MEDIUM-1 of `05-w0-independent-review.md`): before this
    # round `--lvib --ljson -I temp400.inp` wrote `temperature: 298.15` next to
    # the 400 K `gibbs` of the same document, because the JSON read the
    # `settings%` fields while the thermochemistry read the merged `$thermo`
    # values.  Two runs with the same `gibbs` were computed at the same
    # temperature, hence they must report the same `temperature` - and that
    # number has to be the 400 K the block asked for.
    def thermo_json(args):
        status, output = run(exe, geometry, ["--gfn", "2", "--lvib", "--ljson",
                                            "--norestart"] + args, rundir)
        if status != 0:
            fail("xtb --lvib --ljson %s terminated with status %d"
                 % (" ".join(args), status), output)
        return read_json(rundir, "landscape_vib.json"), read_thermo(output)[1], output

    xc_doc, xc_json_g, xc_json_out = thermo_json(["-I", "temp400.inp"])
    cli_doc, cli_json_g, cli_json_out = thermo_json(["--lvib-temp", "400"])
    if abs(xc_json_g - cli_json_g) > 1.0e-9:
        fail("the JSON runs of `$thermo temp=400` and `--lvib-temp 400` differ "
             "(%.12f vs %.12f)" % (xc_json_g, cli_json_g), xc_json_out)
    xc_temp = xc_doc["values"]["temperature"]
    if abs(xc_temp - 400.0) > 1.0e-9:
        fail("landscape_vib.json reports temperature %.6f K for a run whose "
             "gibbs is the 400 K value" % xc_temp, xc_json_out)
    if abs(xc_temp - cli_doc["values"]["temperature"]) > 1.0e-9:
        fail("the JSON temperature of the `$thermo temp=400` run (%.6f) and of "
             "the `--lvib-temp 400` run (%.6f) disagree"
             % (xc_temp, cli_doc["values"]["temperature"]), cli_json_out)
    print("thermo json: `$thermo temp=400` and `--lvib-temp 400` both report "
          "temperature %.3f K for gibbs %.12f Eh" % (xc_temp, xc_json_g))

    sc_doc, _, sc_json_out = thermo_json(["-I", "scale.inp"])
    cli_sc_doc, _, cli_sc_json_out = thermo_json(["--lvib-freq-scal", "0.9"])
    if abs(sc_doc["values"]["freq_scal"] - 0.9) > 1.0e-12:
        fail("landscape_vib.json reports freq_scal %.9f for a `$thermo "
             "scale=0.9` run" % sc_doc["values"]["freq_scal"], sc_json_out)
    if abs(sc_doc["values"]["freq_scal"]
           - cli_sc_doc["values"]["freq_scal"]) > 1.0e-12:
        fail("the JSON scaling factors of the `$thermo scale=0.9` and the "
             "`--lvib-freq-scal 0.9` run disagree (%r vs %r)"
             % (sc_doc["values"]["freq_scal"], cli_sc_doc["values"]["freq_scal"]),
             cli_sc_json_out)
    print("thermo json: `$thermo scale=0.9` == `--lvib-freq-scal 0.9` -> "
          "freq_scal %.3f" % sc_doc["values"]["freq_scal"])

    # --- unusable values of the `$thermo` block are rejected -----------------
    # The validation runs on the *merged* state, so a bad block value is caught
    # exactly like a bad `--lvib-*` flag and before the first single point
    # (finding P2-2 of `05-w0-independent-review.md`).  `set_thermo` checks
    # nothing, so `$thermo scale=-1` used to be multiplied into every
    # frequency (measured: it changed G by 1.9e-2 hartree instead of aborting).
    invalid = {
        "badscale": ("scale=-1.0", "the frequency scaling factor must be positive"),
        "badtemp": ("temp=-5.0", "the thermochemical temperature must be positive"),
        "badimagthr": ("imagthr=20.0",
                       "the imaginary frequency cutoff must not be positive"),
        "badsthr": ("sthr=-1.0",
                    "the rotor cutoff of the quasi-RRHO treatment must not be negative"),
    }
    for name, (key, pattern) in invalid.items():
        with open(os.path.join(rundir, name + ".inp"), "w") as handle:
            handle.write("$thermo\n   %s\n$end\n" % key)
        status, output = run(exe, geometry,
                             ["--gfn", "2", "--lvib", "--norestart",
                              "-I", name + ".inp"], rundir)
        if status == 0:
            fail("the `$thermo %s` block was accepted" % key, output)
        if pattern not in output:
            fail("the `$thermo %s` block was rejected without the documented "
                 "message" % key, output)
        print("thermo: `$thermo %-12s` rejected with status %d" % (key, status))


def check_thermo_knobs(exe, inp, rundir, saddle):
    """The rotor and imaginary cutoffs of `$thermo` take effect (`--lvib`).

    Mirrors `xtb/landscape-vib-thermo-knobs`.  The `$thermo` block has exactly
    four keys and the frequency settings carry one `*_was_set` guard per key
    (`landscape_vib_settings`); `xtb/landscape-vib-thermo` covers `temp` and
    `scale`, so this check closes `sthr` (`--lvib-rotor-cutoff`) and `imagthr`
    (`--lvib-imag-cutoff`).  Both are asserted twice: an *effect* (the number
    changes) and the *merge* (the xcontrol key and the CLI flag give the same
    result).  Deleting the two guards of `sthr`/`imagthr`
    (`landscape_vib_set_thermo_settings`) used to leave the whole suite green
    - the CLI flag had no test at all (`sthr`) or only its error branch
    (`imagthr`) - which is finding P2-1 of `05-w0-independent-review.md`.
    """
    os.makedirs(rundir, exist_ok=True)
    rundir = os.path.abspath(rundir)
    saddle_dir = os.path.join(rundir, "saddle")
    os.makedirs(saddle_dir, exist_ok=True)

    # --- sthr / --lvib-rotor-cutoff, on a tight water minimum ---------------
    # The quasi-RRHO treatment replaces the harmonic entropy of the modes below
    # the cutoff by the Grimme free-rotor interpolation, so the cutoff changes
    # G (measured 1.5e-5 hartree here, H is untouched).
    status, output = run(exe, inp, ["--gfn", "2", "--lopt", "--lopt-level",
                                    "tight", "--norestart"], rundir)
    if status != 0:
        fail("the rotor cutoff optimisation terminated with status %d" % status,
             output)
    geometry = os.path.join(rundir, "xtbopt.xyz")
    if not os.path.exists(geometry):
        fail("the rotor cutoff optimisation wrote no xtbopt.xyz", output)
    with open(os.path.join(rundir, "sthr.inp"), "w") as handle:
        handle.write("$thermo\n   sthr=2000.0\n$end\n")

    def water_thermo(args):
        status, output = run(exe, geometry,
                             ["--gfn", "2", "--lvib", "--norestart"] + args,
                             rundir)
        if status != 0:
            fail("xtb --lvib %s terminated with status %d"
                 % (" ".join(args), status), output)
        return read_thermo(output)[1]

    sthr_default = water_thermo([])
    sthr_cli = water_thermo(["--lvib-rotor-cutoff", "2000"])
    sthr_xc = water_thermo(["-I", "sthr.inp"])
    if abs(sthr_cli - sthr_default) < 1.0e-9:
        fail("--lvib-rotor-cutoff 2000 did not change the free energy "
             "(%.12f vs %.12f)" % (sthr_cli, sthr_default))
    if abs(sthr_cli - sthr_xc) > 1.0e-12:
        fail("`--lvib-rotor-cutoff 2000` and `$thermo sthr=2000` differ "
             "(%.12f vs %.12f)" % (sthr_cli, sthr_xc))
    print("thermo knobs: rotor cutoff  --lvib-rotor-cutoff 2000 == "
          "$thermo sthr=2000 = %.12f Eh (default %.12f, dG %.3e)"
          % (sthr_cli, sthr_default, sthr_cli - sthr_default))

    # --- imagthr / --lvib-imag-cutoff, on the bent HCN saddle --------------
    # A mode whose magnitude is below the cutoff is treated as an artifact of
    # the projected Hessian and `print_thermo` inverts its sign
    # (`if (vibs(i) < 0 .and. vibs(i) > ithr)`, `src/main/property.F90`).  The
    # fixture has one imaginary mode of -1077 cm^-1, so a cutoff of -10000 cm^-1
    # has to turn it into a real mode: the analysis counts `n_imag` 0 instead
    # of 1 (status `incomplete` -> `ok`) and the mode enters the partition
    # function (measured dG 2.4e-3 hartree).
    #
    # The two routes are compared on the *thermochemistry*, not on `n_imag`:
    # the suite's own mode analysis (`landscape_vib_analysis`) classifies with
    # `settings%imag_cutoff`, so an xcontrol `imagthr` reaches the reused model
    # (`set%thermo_ithr`) but not the analysis counter - the divergence is
    # visible in the warning of `landscape_vib_thermo_output` ("the
    # thermochemistry counted a different number of imaginary modes ...") and
    # is recorded as an open finding in `docs/_simplify-recon/06-*.md`.  What
    # this check pins is the *effect* of the CLI flag and that the block
    # reaches the same effective cutoff (same G, same printed cutoff).
    with open(os.path.join(saddle_dir, "imagthr.inp"), "w") as handle:
        handle.write("$thermo\n   imagthr=-10000.0\n$end\n")

    def saddle_json(args):
        status, output = run(exe, saddle,
                             ["--gfn", "2", "--lvib", "--ljson",
                              "--norestart"] + args, saddle_dir)
        if status != 0:
            fail("xtb --lvib --ljson %s terminated with status %d"
                 % (" ".join(args), status), output)
        return read_json(saddle_dir, "landscape_vib.json"), output

    default_doc, default_out = saddle_json([])
    cli_doc, cli_out = saddle_json(["--lvib-imag-cutoff", "-10000"])
    xc_doc, xc_out = saddle_json(["-I", "imagthr.inp"])
    if default_doc["counters"]["n_imag"] != 1:
        fail("the HCN fixture does not have one imaginary mode (%d)"
             % default_doc["counters"]["n_imag"], default_out)
    if cli_doc["counters"]["n_imag"] != 0:
        fail("--lvib-imag-cutoff -10000 did not invert the imaginary mode "
             "(n_imag %d)" % cli_doc["counters"]["n_imag"], cli_out)
    if cli_doc["status"] != 0 or cli_doc["status_name"] != "ok":
        fail("the run without an imaginary mode is not `ok` (%d/%s)"
             % (cli_doc["status"], cli_doc["status_name"]), cli_out)
    if abs(cli_doc["values"]["gibbs"]
           - default_doc["values"]["gibbs"]) < 1.0e-6:
        fail("the imaginary cutoff did not change the free energy "
             "(%.12f vs %.12f)"
             % (cli_doc["values"]["gibbs"], default_doc["values"]["gibbs"]),
             default_out)
    if abs(cli_doc["values"]["gibbs"] - xc_doc["values"]["gibbs"]) > 1.0e-12:
        fail("`--lvib-imag-cutoff -10000` and `$thermo imagthr=-10000` differ "
             "in G (%.12f vs %.12f)"
             % (cli_doc["values"]["gibbs"], xc_doc["values"]["gibbs"]), xc_out)
    match = re.search(r"imag[.] cutoff\s+(-?[\d.]+) cm", xc_out)
    if not match or abs(float(match.group(1)) + 10000.0) > 1.0e-9:
        fail("`$thermo imagthr=-10000` did not reach the thermochemistry",
             xc_out)
    if "inverting freq" not in xc_out:
        fail("`$thermo imagthr=-10000` did not invert the imaginary mode",
             xc_out)
    print("thermo knobs: imag cutoff   --lvib-imag-cutoff -10000 == "
          "$thermo imagthr=-10000 -> analytic n_imag 0, dG %.3e Eh (default "
          "n_imag %d, status %s)"
          % (cli_doc["values"]["gibbs"] - default_doc["values"]["gibbs"],
             default_doc["counters"]["n_imag"], default_doc["status_name"]))


def check_saddlefix(exe, inp, rundir):
    """`$fix` holds the frozen atom for the single ended saddle searches.

    Mirrors `xtb/landscape-lts-fix`; the input is the bent HCN transition state
    guess whose atom 1 is the terminal H at `(0, 1.05, 0)` angstrom, and
    `$fix atoms: 1` freezes it.  Before the projection the accepted step of
    every method moved it (measured: prfo 0.1171, bprfo 0.1475, dimer 0.1482
    angstrom - docs/_simplify-recon/04-*.md section 5.2).  After the fix the
    coordinate is bitwise the input value, so the tolerance is the xyz
    write/read round trip, not a measured spread.

    `prfo` does **not** converge on this constrained fixture (it exhausts the
    step budget, measured with 120/400/1200 steps - the same happens before the
    projection, so the fixture is the reason, not the projection).  The check
    therefore asserts the honest contract of either outcome: a converged run
    exits 0, a non-converged run exits non-zero and says so.  No convergence is
    faked and the step budget is not tuned to make the fixture pass.
    """
    # rebuilt: the check below asserts the *absence* of `xtbts.xyz` for the
    # method that does not converge, and a leftover file of an earlier run (a
    # manual run, or the injected run of the falsifiability experiment) would
    # satisfy that existence check (the same trap as finding F1 of
    # `50-m7-independent-review.md`)
    rundir = os.path.abspath(rundir)
    shutil.rmtree(rundir, ignore_errors=True)
    os.makedirs(rundir, exist_ok=True)
    xcontrol = os.path.join(rundir, "landscape_fix.inp")
    with open(xcontrol, "w") as handle:
        handle.write("$fix\n   atoms: 1\n$end\n")
    reference = None
    with open(inp) as handle:
        for line in handle.read().splitlines()[2:4]:
            fields = line.split()
            if fields and fields[0] == "H":
                reference = [float(value) for value in fields[1:4]]
    if reference is None:
        fail("the saddle fixture has no hydrogen at atom 1", inp)
    for method in ("prfo", "bprfo", "dimer"):
        geometry = os.path.join(rundir, "xtbts.xyz")
        if os.path.exists(geometry):
            os.remove(geometry)
        status, output = run(
            exe,
            inp,
            ["--gfn", "2", "--lts", "--lts-method", method,
             "--lts-max-steps", "120", "--input", xcontrol, "--norestart"],
            rundir,
        )
        converged = "landscape: converged" in output
        if not os.path.exists(geometry):
            fail("the --lts-method %s run wrote no xtbts.xyz" % method, output)
        with open(geometry) as handle:
            lines = handle.read().splitlines()
        fields = lines[2].split()
        if fields[0] != "H":
            fail("the first output atom of %s is not the frozen hydrogen" % method,
                 lines[2])
        shift = max(abs(float(value) - ref)
                    for value, ref in zip(fields[1:4], reference))
        if shift > 1.0e-10:
            fail(
                "--lts-method %s moved the frozen atom by %.5e angstrom (%s)"
                % (method, shift, " ".join(fields[1:4])),
                output,
            )
        if method == "prfo":
            # `prfo` does not converge on this constrained fixture (it exhausts
            # the step budget, measured with 120/400/1200 steps - the same
            # happens before the projection, so the fixture is the reason, not
            # the projection).  What the check pins is therefore **not**
            # "prfo must not converge": it is that the outcome is reported
            # honestly - a converged run exits 0, a non-converged one exits
            # non-zero with the message of `landscape_ts` ("transition state
            # search did not converge: <reason>").  Asserting the surfaced
            # reason instead ("maximum number of steps reached") would turn a
            # future improvement of the trust radius into a red test for the
            # wrong reason (finding P2-4 of `05-w0-independent-review.md`).
            if converged:
                if status != 0:
                    fail("the constrained prfo run reported convergence with "
                         "status %d" % status, output)
            else:
                if status == 0:
                    fail("the constrained prfo run exited 0 although it did "
                         "not converge", output)
                if "transition state search did not converge" not in output:
                    fail("the constrained prfo run failed without reporting "
                         "the missing convergence", output)
        else:
            if status != 0 or not converged:
                fail("--lts-method %s did not converge (status %d)"
                     % (method, status), output)
        print("saddle fix: %-5s status %d converged %s  frozen atom displacement "
              "%.5e angstrom" % (method, status, converged, shift))


def check_rejectfix(exe, inp, rundir):
    """The methods without `$fix` support must refuse the run, not move atoms.

    Mirrors `xtb/landscape-lirc-fix`.  The band searches of `--lts` and the
    reaction path `--lirc` have no defined meaning for a frozen coordinate yet
    (interpolated images / the mass weighted arc length contract), so they
    abort with an actionable message instead of running in a geometry that
    violates the constraint (docs/_simplify-recon/04-*.md sections 5.2/5.3).
    """
    # rebuilt: the check asserts the *absence* of the artefacts the refused run
    # would have written when the guard is injected (finding F1 of
    # `50-m7-independent-review.md`)
    rundir = os.path.abspath(rundir)
    shutil.rmtree(rundir, ignore_errors=True)
    os.makedirs(rundir, exist_ok=True)
    xcontrol = os.path.join(rundir, "landscape_fix.inp")
    with open(xcontrol, "w") as handle:
        handle.write("$fix\n   atoms: 1\n$end\n")
    cases = [
        ("--lirc", ["--lirc", "--lirc-method", "hpc", "--lirc-max-steps", "4"],
         "the reaction path (--lirc) does not support $fix"),
        ("--lts neb", ["--lts", "--lts-method", "neb", "--lts-max-steps", "4"],
         "the band searches (--lts-method neb|cineb|autoneb|string|gsm) do not "
         "support $fix"),
    ]
    for label, args, pattern in cases:
        status, output = run(
            exe, inp, ["--gfn", "2"] + args + ["--input", xcontrol, "--norestart"],
            rundir,
        )
        if status == 0:
            fail("%s accepted $fix although the method does not support it" % label,
                 output)
        if pattern not in output:
            fail("%s did not explain the rejected $fix block" % label, output)
        for artifact in ("xtbts.xyz", "irc_forward.xyz", "irc_path.xyz"):
            if os.path.exists(os.path.join(rundir, artifact)):
                fail("%s wrote %s although it refused the $fix block"
                     % (label, artifact), output)
        print("reject fix: %-9s rejected $fix with status %d" % (label, status))


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
    step budget no point converges, the run reports a missing minimum (NaN)
    and a readable diagnostic with a non-zero exit status, and every evaluated
    point still reaches the scan log.  With a real budget the same scan
    converges and exits 0.
    """
    args = [
        "--gfn", "2", "--lscan", "--lscan-coord", "angle",
        "--lscan-atoms", "2,1,3", "--lscan-step", "3", "--lscan-nstep", "2",
        "--lscan-max-steps", "0", "--norestart", "--namespace", "landscape4",
    ]
    status, output = run(exe, inp, args, rundir)
    # M7 (PLAN §12.11 INFO-3): a scan without a single converged point has no
    # usable result, so the run exits non-zero next to the NaN total energy
    # (before this round the branch only warned and the run exited 0).
    if status == 0:
        fail("a scan without a converged point exited 0", output)
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


def check_autoneb_depth_limit(exe, inp, rundir, product):
    """An AutoNEB run that stops at the insertion cap must name the cap.

    Mirrors the CMake script of `xtb/landscape-path-autoneb-depth-limit`: the
    band of the last stage converges, but the requested path was not built, so
    the result message - and therefore `xtbts.log` - has to report the cap
    instead of a bare "converged" (report 38 L-2).
    """
    args = [
        "--gfn", "2", "--lts", "--lts-method", "autoneb",
        "--lts-product", product, "--lts-autoneb-max-depth", "1",
        "--lts-max-steps", "400", "--norestart", "--namespace", "mesonP",
    ]
    status, output = run(exe, inp, args, rundir)
    if status != 0:
        fail("the capped AutoNEB run terminated with status %d" % status, output)
    if "autoneb: budget limit reached" not in output:
        fail("the AutoNEB insertion cap was not reached", output)
    cap = "landscape task terminated: stopped at the insertion depth limit max_depth = 1"
    if cap not in output:
        fail("the cap did not reach the result message", output)
    with open(os.path.join(rundir, "mesonP.xtbts.log")) as handle:
        log = handle.read()
    if "termination: stopped at the insertion depth limit max_depth = 1" not in log:
        fail("the cap did not reach xtbts.log", log)
    if "termination: converged" in log:
        fail("xtbts.log claims convergence for a capped run", log)


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


def check_basin(label, energy, lower, upper):
    """Require an endpoint energy to lie inside the measured basin window."""
    value = float(energy)
    if value > upper or value < lower:
        fail("the %s endpoint %s is outside the basin window (%s .. %s)"
             % (label, energy, lower, upper))


def read_log(rundir, name):
    """Read one IRC log file of the run directory."""
    with open(os.path.join(rundir, name)) as handle:
        return handle.read()


def endpoint_energy(log, direction):
    """Endpoint energy of one direction of an IRC log."""
    match = re.search(r"%s endpoint energy: +(-?[0-9.]+)" % direction, log)
    if not match:
        fail("the IRC log reports no %s endpoint energy" % direction, log)
    return match.group(1)


def check_irc(exe, inp, rundir):
    """`--lirc` from a converged transition state (xtb/landscape-irc-cli).

    The input is the bent HCN transition state **guess**: the check first runs
    `--lts` to converge it, because an IRC started from a non-stationary
    geometry funnels both directions into the same basin (report 42).
    """
    status, output = run(
        exe, inp,
        ["--gfn", "2", "--lts", "--lts-method", "prfo", "--norestart",
         "--namespace", "irc0"],
        rundir,
    )
    if status != 0:
        fail("the preparation --lts run failed with status %d" % status, output)
    ts = os.path.join(rundir, "irc0.xtbts.xyz")
    if not os.path.exists(ts):
        fail("the preparation --lts run wrote no xtbts.xyz", output)
    irc_args = ["--gfn", "2", "--lirc", "--lirc-method", "gs", "--norestart",
                "--namespace", "irc1"]
    status, output = run(exe, ts, irc_args, rundir)
    if status != 0:
        fail("xtb --lirc terminated with status %d" % status, output)
    for pattern in [
        r"landscape: intrinsic reaction coordinate [(]gs[)]",
        r"transition state imaginary modes: +1",
        r"phase component: +[0-9.]+",
        r"landscape engine: etemp +300[.]000 K",
        r"forward reached minimum: +T",
        r"backward reached minimum: +T",
    ]:
        if not re.search(pattern, output):
            fail("missing %r in the --lirc output" % pattern, output)
    for name in ["irc1.irc_forward.xyz", "irc1.irc_backward.xyz",
                 "irc1.irc_path.xyz", "irc1.irc.log"]:
        path = os.path.join(rundir, name)
        if not os.path.exists(path) or os.path.getsize(path) == 0:
            fail("%s was not written" % name, output)
    with open(os.path.join(rundir, "irc1.irc_path.xyz")) as handle:
        pathfile = handle.read()
    if " TS" not in pathfile:
        fail("the transition state is not marked in irc_path.xyz", pathfile)
    with open(os.path.join(rundir, "irc1.irc.log")) as handle:
        log = handle.read()
    match = re.search(r"forward endpoint energy: +(-?[0-9.]+)", log)
    if not match:
        fail("the IRC log reports no forward endpoint energy", log)
    fwd = match.group(1)
    match = re.search(r"backward endpoint energy: +(-?[0-9.]+)", log)
    if not match:
        fail("the IRC log reports no backward endpoint energy", log)
    if fwd == match.group(1):
        fail("both IRC directions reached the same energy (%s)" % fwd)
    bwd = match.group(1)
    # golden values of the Gonzalez-Schlegel baseline (report 44 section 3):
    # the measured minima +/- 1e-4 Eh, 2x the measured same-basin spread of
    # the four methods (5.0e-5 Eh) and 8x narrower than the distance of the
    # one method outside the basin (eulerpc, 8.0e-4 Eh)
    check_basin("forward", fwd, -5.47225988, -5.47205988)
    check_basin("backward", bwd, -5.50416622, -5.50396622)
    for pattern in [r"forward arc length: +4[.]051234",
                    r"backward arc length: +3[.]695670",
                    r"mean energy/gradient evaluations per point: +16[.]9",
                    r"mean energy/gradient evaluations per point: +20[.]2",
                    r"endpoint rmsd criterion: rmsd <= rmsd_end = 0[.]18897000"]:
        if not re.search(pattern, log):
            fail("missing %r in irc.log" % pattern, log)
    # the GS defect is demonstrated, not only described
    match = re.search(r"pinned at the micro cycle budget: forward ([0-9]+) of", log)
    if not match or int(match.group(1)) < 1:
        fail("the GS sphere relaxation is no longer pinned on the forward path", log)
    match = re.search(r"backward ([0-9]+) of [0-9]+ points", log)
    if not match or int(match.group(1)) < 1:
        fail("the GS sphere relaxation is no longer pinned on the backward path", log)
    with open(os.path.join(rundir, "irc1.irc_forward.xyz")) as handle:
        first = handle.read()
    status, output = run(exe, ts, irc_args, rundir)
    if status != 0:
        fail("the repeated --lirc run failed with status %d" % status, output)
    with open(os.path.join(rundir, "irc1.irc_forward.xyz")) as handle:
        second = handle.read()
    if first != second:
        fail("irc_forward.xyz is not bitwise reproducible")


def check_irc_knobs(exe, inp, rundir):
    """`--lirc-level`, `--lirc-rmsd-end` and the default method (M-1).

    Each of the three has to make the reported numbers move: the two flags were
    parsed and then never read before the M6 fix round, and the default method
    was `gs` although `hpc` is both more accurate and 8.5x cheaper.
    """
    status, output = run(
        exe, inp,
        ["--gfn", "2", "--lts", "--lts-method", "prfo", "--norestart",
         "--namespace", "ircknob0"],
        rundir,
    )
    if status != 0:
        fail("the preparation --lts run failed with status %d" % status, output)
    ts = os.path.join(rundir, "ircknob0.xtbts.xyz")
    if not os.path.exists(ts):
        fail("the preparation --lts run wrote no xtbts.xyz", output)
    # the default method is hpc (M6 behaviour change, PLAN section 12.15)
    status, output = run(
        exe, ts, ["--gfn", "2", "--lirc", "--norestart", "--namespace", "irc4"],
        rundir,
    )
    if status != 0:
        fail("xtb --lirc without --lirc-method failed with status %d" % status, output)
    log = read_log(rundir, "irc4.irc.log")
    if not re.search(r"intrinsic reaction coordinate: hpc", log):
        fail("the default IRC method is no longer hpc", log)
    check_basin("default forward", endpoint_energy(log, "forward"),
                -5.47225988, -5.47205988)
    check_basin("default backward", endpoint_energy(log, "backward"),
                -5.50416622, -5.50396622)
    if not re.search(r"pinned at the micro cycle budget: forward 0 of", log):
        fail("the default (hpc) run reports pinned micro cycles", log)
    # `--lirc-rmsd-end` attributes the endpoint (the forward endpoint is
    # 0.0099 bohr from its relaxed minimum, the backward one 1.6e-5)
    status, output = run(
        exe, ts,
        ["--gfn", "2", "--lirc", "--lirc-method", "gs", "--lirc-rmsd-end", "1e-3",
         "--norestart", "--namespace", "irc5"],
        rundir,
    )
    if status != 0:
        fail("xtb --lirc --lirc-rmsd-end 1e-3 failed with status %d" % status, output)
    log = read_log(rundir, "irc5.irc.log")
    if not re.search(r"endpoint rmsd criterion: rmsd <= rmsd_end = 0[.]00100000", log):
        fail("--lirc-rmsd-end 1e-3 did not reach the settings", log)
    if not re.search(r"forward reached minimum: +F", log):
        fail("--lirc-rmsd-end 1e-3 did not reject the forward endpoint", log)
    if not re.search(r"backward reached minimum: +T", log):
        fail("--lirc-rmsd-end 1e-3 rejected the backward endpoint", log)
    # `--lirc-level` drives the endpoint relaxation (measured: 1 step at
    # superloose to -5.47213843 Eh, 7 steps at vtight to -5.47215989 Eh)
    minima = {}
    for level in ["superloose", "vtight"]:
        status, output = run(
            exe, ts,
            ["--gfn", "2", "--lirc", "--lirc-method", "gs", "--lirc-level", level,
             "--norestart", "--namespace", "irc-" + level],
            rundir,
        )
        if status != 0:
            fail("xtb --lirc-level %s failed with status %d" % (level, status), output)
        log = read_log(rundir, "irc-%s.irc.log" % level)
        match = re.search(
            r"forward relaxed minimum: +(-?[0-9.]+) Eh [(]([0-9]+) relaxation steps[)]",
            log,
        )
        if not match:
            fail("the %s log reports no relaxed minimum" % level, log)
        minima[level] = (float(match.group(1)), int(match.group(2)))
    if minima["vtight"][1] <= minima["superloose"][1]:
        fail("--lirc-level vtight did not need more relaxation steps than superloose "
             "(%d vs %d)" % (minima["vtight"][1], minima["superloose"][1]))
    if minima["vtight"][0] >= minima["superloose"][0]:
        fail("--lirc-level vtight did not relax further than superloose (%g vs %g)"
             % (minima["vtight"][0], minima["superloose"][0]))
    # without a relaxation there is no relaxed minimum: the attribution falls
    # back to the termination signal and the log has to say so
    status, output = run(
        exe, ts,
        ["--gfn", "2", "--lirc", "--lirc-method", "gs", "--lirc-no-endpoint-relax",
         "--norestart", "--namespace", "irc6"],
        rundir,
    )
    if status != 0:
        fail("xtb --lirc --lirc-no-endpoint-relax failed with status %d" % status, output)
    log = read_log(rundir, "irc6.irc.log")
    if not re.search(r"forward reached minimum: +T", log):
        fail("--lirc-no-endpoint-relax lost the termination based attribution", log)
    if re.search(r"forward relaxed minimum:", log):
        fail("--lirc-no-endpoint-relax still reports a relaxed minimum", log)
    if not re.search(r"the rmsd_end criterion was skipped", log):
        fail("--lirc-no-endpoint-relax does not report the skipped rmsd criterion", log)


def check_irc_pc(exe, inp, rundir):
    """`--lirc-method hpc` and `eulerpc` (xtb/landscape-irc-pc).

    Both predictor-corrector integrators have to reach a minimum in both
    directions, write the four output files and keep the mean E/g per point at
    the predictor-corrector level (see the module header of `irc/hpc.f90`).
    """
    status, output = run(
        exe, inp,
        ["--gfn", "2", "--lts", "--lts-method", "prfo", "--norestart",
         "--namespace", "ircpc0"],
        rundir,
    )
    if status != 0:
        fail("the preparation --lts run failed with status %d" % status, output)
    ts = os.path.join(rundir, "ircpc0.xtbts.xyz")
    if not os.path.exists(ts):
        fail("the preparation --lts run wrote no xtbts.xyz", output)
    for method in ["hpc", "eulerpc"]:
        status, output = run(
            exe, ts,
            ["--gfn", "2", "--lirc", "--lirc-method", method, "--norestart",
             "--namespace", method],
            rundir,
        )
        if status != 0:
            fail("xtb --lirc --lirc-method %s failed with status %d" % (method, status), output)
        for pattern in [
            r"landscape: intrinsic reaction coordinate [(]%s[)]" % method,
            r"transition state imaginary modes: +1",
            r"termination forward: +(gradient|energy_rise)",
            r"termination backward: +(gradient|energy_rise)",
            r"forward reached minimum: +T",
            r"backward reached minimum: +T",
        ]:
            if not re.search(pattern, output):
                fail("missing %r in the %s output" % (pattern, method), output)
        for name in ["%s.irc_forward.xyz" % method, "%s.irc_backward.xyz" % method,
                     "%s.irc_path.xyz" % method, "%s.irc.log" % method]:
            path = os.path.join(rundir, name)
            if not os.path.exists(path) or os.path.getsize(path) == 0:
                fail("%s was not written" % name, output)
        with open(os.path.join(rundir, "%s.irc.log" % method)) as handle:
            log = handle.read()
        match = re.search(r"mean energy/gradient evaluations per point: +([0-9.]+)", log)
        if not match:
            fail("%s: the log reports no mean E/g" % method, log)
        mean_ev = float(match.group(1))
        if not 1.0 <= mean_ev <= 6.0:
            fail("%s: the mean E/g per point is %s, far above the predictor-corrector level" % (method, mean_ev), log)
        if not re.search(r"forward endpoint energy: +-5[.]47", log):
            fail("%s: the forward endpoint did not reach the HNC basin" % method, log)
        if not re.search(r"backward endpoint energy: +-5[.]50", log):
            fail("%s: the backward endpoint did not reach the HCN basin" % method, log)
    # the new flags reach the settings
    status, output = run(
        exe, ts,
        ["--gfn", "2", "--lirc", "--lirc-method", "eulerpc",
         "--lirc-loose-cycles", "0", "--lirc-erise-steps", "5",
         "--lirc-endpoint-relax", "--norestart", "--namespace", "ircpc1"],
        rundir,
    )
    if status != 0:
        fail("the new --lirc flags failed with status %d" % status, output)
    # a path cut off by the step budget is not assigned to a minimum
    status, output = run(
        exe, ts,
        ["--gfn", "2", "--lirc", "--lirc-method", "hpc", "--lirc-max-steps", "3",
         "--norestart", "--namespace", "ircpc2"],
        rundir,
    )
    if status != 0:
        fail("the --lirc-max-steps 3 run failed with status %d" % status, output)
    if not re.search(r"termination forward: +max_steps", output):
        fail("the step budget did not report signal (a)", output)
    if not re.search(r"forward reached minimum: +F", output):
        fail("a path cut off by the step budget was assigned to a minimum", output)


def check_irc_termination(exe, inp, rundir):
    """Termination signal (c) at the command line (xtb/landscape-irc-termination)."""
    status, output = run(
        exe, inp,
        ["--gfn", "2", "--lts", "--lts-method", "prfo", "--norestart",
         "--namespace", "ircterm0"],
        rundir,
    )
    if status != 0:
        fail("the preparation --lts run failed with status %d" % status, output)
    ts = os.path.join(rundir, "ircterm0.xtbts.xyz")
    if not os.path.exists(ts):
        fail("the preparation --lts run wrote no xtbts.xyz", output)
    status, output = run(
        exe, ts,
        ["--gfn", "2", "--lirc", "--lirc-method", "gs", "--lirc-grad-tol", "0",
         "--norestart", "--namespace", "ircterm1"],
        rundir,
    )
    if status != 0:
        fail("xtb --lirc --lirc-grad-tol 0 failed with status %d" % status, output)
    for pattern in [
        r"termination forward: +energy_rise",
        r"termination backward: +energy_rise",
        r"forward reached minimum: +T",
        r"backward reached minimum: +T",
        r"landscape engine: etemp +300[.]000 K",
    ]:
        if not re.search(pattern, output):
            fail("missing %r in the --lirc output" % pattern, output)


def check_irc_swap(exe, inp, rundir):
    """`--lirc-swap` exchanges the two directions (xtb/landscape-irc-swap).

    Mirrors the inline CMake script of the CMake build.  The input is the bent
    HCN transition state guess, converged with `--lts` first (see
    `check_irc`).  The swap check would be vacuous if both directions reached
    the same energy, so that is asserted as well.
    """
    status, output = run(
        exe, inp,
        ["--gfn", "2", "--lts", "--lts-method", "prfo", "--norestart",
         "--namespace", "ircswap0"],
        rundir,
    )
    if status != 0:
        fail("the preparation --lts run failed with status %d" % status, output)
    ts = os.path.join(rundir, "ircswap0.xtbts.xyz")
    if not os.path.exists(ts):
        fail("the preparation --lts run wrote no xtbts.xyz", output)

    def case(suffix, swap):
        args = ["--gfn", "2", "--lirc", "--lirc-method", "gs", "--norestart",
                "--namespace", suffix]
        if swap:
            args.append("--lirc-swap")
        status, output = run(exe, ts, args, rundir)
        if status != 0:
            fail("xtb --lirc %s failed with status %d" % (suffix, status), output)
        log = read_log(rundir, "%s.irc.log" % suffix)
        return endpoint_energy(log, "forward"), endpoint_energy(log, "backward")

    plain_fwd, plain_bwd = case("ircswap1", False)
    swapped_fwd, swapped_bwd = case("ircswap2", True)
    if plain_fwd == plain_bwd:
        fail("both directions reached the same energy (%s); the swap check "
             "would be vacuous" % plain_fwd)
    if plain_fwd != swapped_bwd:
        fail("--lirc-swap did not exchange the forward endpoint: %s vs %s"
             % (plain_fwd, swapped_bwd))
    if plain_bwd != swapped_fwd:
        fail("--lirc-swap did not exchange the backward endpoint: %s vs %s"
             % (plain_bwd, swapped_fwd))


def check_opt_namespace(exe, inp, rundir):
    """`--lopt` geometry and trajectory honour `--namespace`.

    Mirrors the CMake script of `xtb/landscape-opt-namespace` (defect N-1 of
    the final fix round): `xtb_landscape_log::landscape_write_files` used the
    bare names `xtbopt.xyz`/`xtb.trj` although every other landscape writer and
    the pre-existing `--opt` pass their names through `get_namespace`, so two
    minimisations with different namespaces in one directory overwrote each
    other.  Without `--namespace` the names must stay `xtbopt.xyz`/`xtb.trj`.

    `inp` is ignored: the check writes its own *stretched* water, because two
    runs of a geometry that is already at the minimum could produce identical
    files, and an identical pair cannot tell an overwrite from a correct pair.
    The rundir is removed at entry, because the check asserts the *absence* of
    the unprefixed `xtbopt.xyz`.
    """
    rundir = os.path.abspath(rundir)
    shutil.rmtree(rundir, ignore_errors=True)
    os.makedirs(os.path.join(rundir, "plain"))
    os.makedirs(os.path.join(rundir, "two"))
    stretched = os.path.join(rundir, "stretched_h2o.xyz")
    with open(stretched, "w") as handle:
        handle.write("3\nstretched water\n"
                     "O  0.0000000  0.0000000  0.0000000\n"
                     "H  0.0000000  0.0000000  1.3000000\n"
                     "H  1.3000000  0.0000000 -0.4000000\n")

    # 1. the default names (tool-chain compatibility)
    plain = os.path.join(rundir, "plain")
    status, output = run(
        exe, stretched,
        ["--gfn", "2", "--lopt", "--lopt-level", "loose", "--norestart"],
        plain,
    )
    if status != 0:
        fail("the default --lopt run failed with status %d" % status, output)
    for name in ("xtbopt.xyz", "xtb.trj"):
        path = os.path.join(plain, name)
        if not os.path.exists(path):
            fail("without --namespace the output is still %s, but it was not "
                 "written" % name, output)
        if os.path.getsize(path) == 0:
            fail("%s is empty" % name)

    # 2. two namespaces in one directory
    two = os.path.join(rundir, "two")
    status, output = run(
        exe, stretched,
        ["--gfn", "2", "--lopt", "--lopt-level", "loose", "--norestart",
         "--namespace", "c1"],
        two,
    )
    if status != 0:
        fail("the --namespace c1 run failed with status %d" % status, output)
    first = os.path.join(two, "c1.xtbopt.xyz")
    if not os.path.exists(first):
        fail("--namespace c1 wrote no c1.xtbopt.xyz", output)
    with open(first) as handle:
        first_text = handle.read()

    status, output = run(
        exe, stretched,
        ["--gfn", "2", "--lopt", "--lopt-level", "vtight", "--norestart",
         "--namespace", "c2"],
        two,
    )
    if status != 0:
        fail("the --namespace c2 run failed with status %d" % status, output)
    for name in ("c1.xtbopt.xyz", "c2.xtbopt.xyz", "c1.xtb.trj", "c2.xtb.trj"):
        if not os.path.exists(os.path.join(two, name)):
            fail("%s was not written" % name, output)
    if os.path.exists(os.path.join(two, "xtbopt.xyz")):
        fail("a namespaced run also wrote the unprefixed xtbopt.xyz")
    with open(first) as handle:
        if handle.read() != first_text:
            fail("the --namespace c2 run overwrote c1.xtbopt.xyz")
    with open(os.path.join(two, "c2.xtbopt.xyz")) as handle:
        second_text = handle.read()
    if first_text == second_text:
        fail("the two namespaces hold the same geometry; the check cannot "
             "tell an overwrite from a correct pair")


def check_ljson_no_runtype(exe, inp, rundir):
    """`--ljson` without a landscape run type is reported, not silently ignored.

    Mirrors the CMake script of `xtb/landscape-ljson-no-runtype` (finding L-9 of
    `50-m7-independent-review.md`): the switch is an output switch, so a run
    type that does not know it writes nothing.  That used to happen without a
    message; now the no-op is reported on stderr, no document is written, and
    the process still exits 0 because the request itself is not an error.
    """
    rundir = os.path.abspath(rundir)
    shutil.rmtree(rundir, ignore_errors=True)
    os.makedirs(rundir)
    status, output = run(
        exe, os.path.abspath(inp), ["--gfn", "2", "--ljson"], rundir
    )
    if status != 0:
        fail("xtb --ljson terminated with status %d" % status, output)
    if "writes nothing without a landscape run type" not in output:
        fail("the --ljson no-op was not reported", output)
    documents = [name for name in os.listdir(rundir)
                 if name.startswith("landscape_") and name.endswith(".json")]
    if documents:
        fail("--ljson wrote a document without a landscape run type: %s"
             % documents)


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
    elif mode == "fix":
        check_fix(exe, inp, rundir)
    elif mode == "scanblock":
        check_scanblock(exe, inp, rundir)
    elif mode == "saddlefix":
        check_saddlefix(exe, inp, rundir)
    elif mode == "rejectfix":
        check_rejectfix(exe, inp, rundir)
    elif mode == "thermo":
        check_thermo(exe, inp, rundir)
    elif mode == "thermoknobs":
        if len(rest) < 1:
            fail("the thermoknobs mode needs the saddle geometry")
        check_thermo_knobs(exe, inp, rundir, rest[0])
    elif mode == "optnamespace":
        check_opt_namespace(exe, inp, rundir)
    elif mode == "ljsonnorun":
        check_ljson_no_runtype(exe, inp, rundir)
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
    elif mode == "irc":
        check_irc(exe, inp, rundir)
    elif mode == "ircknobs":
        check_irc_knobs(exe, inp, rundir)
    elif mode == "ircpc":
        check_irc_pc(exe, inp, rundir)
    elif mode == "ircswap":
        check_irc_swap(exe, inp, rundir)
    elif mode == "irctermination":
        check_irc_termination(exe, inp, rundir)
    elif mode == "autonebdepth":
        if len(rest) < 1:
            fail("the autonebdepth mode needs the product geometry")
        check_autoneb_depth_limit(exe, inp, rundir, rest[0])
    elif mode == "error":
        if len(rest) < 2:
            fail("the error mode needs a pattern and the xtb arguments")
        check_error(exe, inp, rundir, rest[0], rest[1:])
    else:
        fail("unknown mode %r" % mode)


if __name__ == "__main__":
    main()
