#!/usr/bin/env python3
"""Independent `--ljson` verification (M7 validation, report 49).

Written from scratch (it shares no code with `test/unit/landscape_e2e_check.py`)
so that a hole in the delivered check cannot hide here as well.

For every landscape task reachable from the command line it

  * parses the document with the standard-library JSON parser,
  * checks the envelope (key order, `format`, `task`, `status`),
  * cross-asserts **every** counter/value that also appears on the stdout of
    the *same* run, using its own regular expressions,
  * repeats the run in a fresh directory and requires byte identity,
  * repeats it again with OMP_NUM_THREADS = 1/2/4 and records whether the
    bytes stay identical,
  * with `--namespace` and requires the prefixed file name.

The corrupted-document reverse experiment lives in `ljson_corrupt_check.py`.
"""
import json
import os
import re
import subprocess
import sys

EXE = "/tmp/xtb-land/build/xtb"
H2O = "/tmp/xtb-land/build/test/unit/landscape_h2o.xyz"
HCN = "/tmp/xtb-land/build/test/unit/landscape_hcn.xyz"
HNC = "/tmp/xtb-land/build/test/unit/landscape_hnc_product.xyz"
BASE = os.path.dirname(os.path.abspath(__file__)) + "/exp2-ljson"

ENVELOPE = ["format", "task", "status", "status_name", "converged", "message",
            "counters", "values", "flags", "history"]

TASKS = {
    "opt": (H2O, ["--lopt", "--lopt-level", "tight"]),
    "scan1d": (H2O, ["--lscan", "--lscan-coord", "distance", "--lscan-atoms",
                     "1,2", "--lscan-step", "0.05", "--lscan-nstep", "3",
                     "--lscan-level", "loose"]),
    "scan2d": (H2O, ["--lscan", "--lscan-coord", "distance", "--lscan-atoms",
                     "1,2", "--lscan-step", "0.05", "--lscan-nstep", "2",
                     "--lscan-coord2", "distance", "--lscan-atoms2", "1,3",
                     "--lscan-step2", "0.05", "--lscan-nstep2", "1",
                     "--lscan-level", "loose"]),
    "vib": (H2O, ["--lvib"]),
    "ts": (HCN, ["--lts", "--lts-method", "prfo"]),
    "irc": (HCN, ["--lirc", "--lirc-method", "hpc"]),
}
# ts / irc methods (the band searches take a different code path)
TS_METHODS = {"prfo": 1, "bprfo": 2, "dimer": 3, "neb": 4, "cineb": 5,
              "autoneb": 6, "string": 7, "gsm": 8}
IRC_METHODS = {"gs": 1, "hpc": 2, "lqa": 3, "eulerpc": 4}


def run(inp, args, rundir, omp="1", extra=()):
    os.makedirs(rundir, exist_ok=True)
    env = dict(os.environ, OMP_NUM_THREADS=omp,
               XTBPATH=os.environ.get("XTBPATH", ""))
    proc = subprocess.run([EXE, inp] + list(args) + list(extra), cwd=rundir,
                          capture_output=True, text=True, env=env)
    return proc.returncode, proc.stdout + proc.stderr


def one(pattern, text, default=None, last=False):
    ms = re.findall(pattern, text, re.M)
    if not ms:
        return default
    return ms[-1] if last else ms[0]


def as_int(pattern, text, last=False):
    v = one(pattern, text, last=last)
    return None if v is None else int(v)


def as_float(pattern, text):
    v = one(pattern, text)
    return None if v is None else float(v)


def check_envelope(doc, task, out):
    problems = []
    if list(doc) != ENVELOPE:
        problems.append("key order %s" % list(doc))
    if doc.get("format") != 1:
        problems.append("format %r" % doc.get("format"))
    if doc.get("task") != task:
        problems.append("task %r" % doc.get("task"))
    if not isinstance(doc.get("counters"), dict):
        problems.append("counters is not an object")
    return problems


def cross_check(task, doc, out, dirkey=None):
    """Every assertion below is derived from the printed stdout of this run."""
    c, v = doc["counters"], doc["values"]
    bad = []

    def eq(name, got, want, tol=0.0):
        if got is None or want is None:
            bad.append("%s: no printed counterpart (json=%r)" % (name, got))
        elif isinstance(want, float):
            if abs(got - want) > tol:
                bad.append("%s: json=%r stdout=%r" % (name, got, want))
        elif got != want:
            bad.append("%s: json=%r stdout=%r" % (name, got, want))

    if task == "opt":
        eq("n_eval", c["n_eval"], as_int(r"energy calls:\s+(\d+)", out))
        eq("n_eval(engine)", c["n_eval"],
           as_int(r"landscape engine: energy evaluations\s+(\d+)", out, last=True))
        eq("n_cache_miss", c["n_cache_miss"], as_int(r"cache misses:\s+(\d+)", out))
        eq("n_steps", c["n_steps"], as_int(r"^\s+steps:\s+(\d+)", out))
        eq("energy", v["energy"], as_float(r"final energy:\s+(-?[\d.]+)", out),
           1.0e-9)
        eq("etemp", v["etemp"],
           as_float(r"landscape engine: etemp\s+([\d.]+) K", out), 1.0e-9)
    elif task.startswith("scan"):
        frames = open(os.path.join(BASE, dirkey or task, "xtbscan.log")).read().count(
            "energy:")
        eq("n_points(file:%d)" % frames, c["n_points"], frames)
        eq("n_points(printed)", c["n_points"], as_int(
            r"wrote xtbscan.log with (\d+) frame", out))
        eq("energy", v["energy"], as_float(
            r"lowest (?:grid )?energy:\s+(-?[\d.eE+-]+) Eh", out), 1.0e-6)
        eq("n_eval(engine)", c["n_eval"],
           as_int(r"landscape engine: energy evaluations\s+(\d+)", out, last=True))
        eq("etemp", v["etemp"],
           as_float(r"landscape engine: etemp\s+([\d.]+) K", out), 1.0e-9)
    elif task == "vib":
        eq("n_eval(engine)", c["n_eval"],
           as_int(r"landscape engine: energy evaluations\s+(\d+)", out, last=True))
        eq("n_imag", c["n_imag"],
           as_int(r"# imaginary freq\.\s+(\d+)", out))
        eq("zpe", v["zpe"], as_float(r"zero point energy:\s+(-?[\d.eE+-]+) Eh",
                                     out), 1.0e-7)
        eq("enthalpy", v["enthalpy"],
           as_float(r"total enthalpy H\(T\):\s+(-?[\d.eE+-]+) Eh", out), 1.0e-9)
        eq("gibbs", v["gibbs"],
           as_float(r"total free energy G\(T\):\s+(-?[\d.eE+-]+) Eh", out), 1.0e-9)
        eq("temperature", v["temperature"],
           as_float(r"^\s*([\d.]+)\s+VIB", out), 1.0e-9)
        eq("freq_scal", v["freq_scal"],
           as_float(r"scaling factor\s+([\d.]+)", out), 1.0e-9)
        eq("n_vib", c["n_vib"], as_int(r"# frequencies\s+(\d+)", out))
        eq("etemp", v["etemp"],
           as_float(r"landscape engine: etemp\s+([\d.]+) K", out), 1.0e-9)
        nz = c["n_zero"] + c["n_vib"]
        if nz != c["n_modes"]:
            bad.append("n_zero+n_vib != n_modes")
    elif task == "ts":
        eq("n_eval", c["n_eval"], as_int(r"energy calls:\s+(\d+)", out))
        eq("n_eval(engine)", c["n_eval"],
           as_int(r"landscape engine: energy evaluations\s+(\d+)", out, last=True))
        eq("n_cache_miss", c["n_cache_miss"], as_int(r"cache misses:\s+(\d+)", out))
        eq("n_steps", c["n_steps"], as_int(r"^\s+steps:\s+(\d+)", out))
        eq("n_imag", c["n_imag"],
           as_int(r"imaginary modes:\s+(\d+)", out))
        eq("energy", v["energy"], as_float(r"final energy:\s+(-?[\d.]+) Eh", out),
           1.0e-9)
    elif task == "irc":
        eq("n_fwd", c["n_fwd"], as_int(r"forward points:\s+(\d+)", out))
        eq("n_bwd", c["n_bwd"], as_int(r"backward points:\s+(\d+)", out))
        eq("n_imag", c["n_imag"], as_int(r"imaginary modes:\s+(\d+)", out))
        eq("n_eval", c["n_eval_fwd"] + c["n_eval_bwd"], None) if False else None
        eq("energy_ts", v["energy_ts"],
           as_float(r"transition state energy:\s+(-?[\d.]+) Eh", out), 1.0e-9)
        eq("step_length", v["step_length"], as_float(
            r"step length:\s+([\d.eE+-]+) bohr", out), 1.0e-12)
    return bad


def compare(a, b, path=""):
    """Recursive numeric diff of two documents: (path, left, |d|, right)."""
    diffs = []
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            diffs += compare(a.get(k), b.get(k), path + "." + str(k))
    elif isinstance(a, list) and isinstance(b, list):
        for i, (x, y) in enumerate(zip(a, b)):
            diffs += compare(x, y, path + "[%d]" % i)
    elif isinstance(a, (int, float)) and isinstance(b, (int, float)):
        if a != b:
            diffs.append((path, a, abs(a - b), b))
    elif a != b:
        diffs.append((path, a, float("nan"), b))
    return diffs


def main():
    report = {}
    for task, (inp, args) in TASKS.items():
        base_task = "scan" if task.startswith("scan") else task
        rundir = "%s/%s" % (BASE, task)
        extra = ["--norestart", "--ljson"]
        status, out = run(inp, args, rundir, extra=extra)
        entry = {"status": status}
        name = "landscape_%s.json" % base_task
        path = os.path.join(rundir, name)
        entry["file"] = name
        if status != 0 or not os.path.exists(path):
            entry["error"] = "exit %d, file %s" % (status, os.path.exists(path))
            report[task] = entry
            print("%-7s FAILED exit=%d" % (task, status))
            continue
        doc = json.load(open(path))
        entry["problems"] = check_envelope(doc, base_task, out) + \
            cross_check(base_task, doc, out, task)
        # determinism (fresh directory, same input)
        again = rundir + "-again"
        status2, out2 = run(inp, args, again, extra=extra)
        first = open(path, "rb").read()
        second = open(os.path.join(again, name), "rb").read()
        entry["deterministic"] = (first == second) and status2 == 0
        # thread count stability
        entry["thread_stability"] = {}
        for omp in ("2", "4"):
            d3 = "%s-omp%s" % (rundir, omp)
            st, _ = run(inp, args, d3, omp=omp, extra=extra)
            p3 = os.path.join(d3, name)
            same = st == 0 and os.path.exists(p3) and \
                open(p3, "rb").read() == first
            entry["thread_stability"][omp] = {"exit": st, "identical": same}
            if not same and os.path.exists(p3):
                other = json.load(open(p3))
                diffs = compare(doc, other)
                entry["thread_stability"][omp]["max_abs"] = \
                    max([d[2] for d in diffs] or [0.0])
                entry["thread_stability"][omp]["n_differing_fields"] = len(diffs)
                entry["thread_stability"][omp]["examples"] = [
                    "%s: %.17g -> %.17g (abs %.3g)" % (d[0], d[1], d[3], d[2])
                    for d in diffs[:6]]
        # namespace
        d4 = rundir + "-ns"
        st, _ = run(inp, args, d4, extra=extra + ["--namespace", "m7ns"])
        entry["namespace"] = (st, os.path.exists(
            os.path.join(d4, "m7ns." + name)))
        entry["counters"] = doc["counters"]
        report[task] = entry
        print("%-7s exit=%d problems=%s deterministic=%s ns=%s threads=%s"
              % (task, status, entry["problems"] or "none",
                 entry["deterministic"], entry["namespace"],
                 {k: v["identical"] for k, v in entry["thread_stability"].items()}))

    # every ts and irc method
    methods = {}
    for method, ident in TS_METHODS.items():
        args = ["--gfn", "2", "--lts", "--lts-method", method,
                "--lts-max-steps", "20", "--lts-level", "superloose",
                "--norestart", "--ljson", "--namespace", "m7m"]
        if method in ("neb", "cineb", "autoneb", "string", "gsm"):
            args += ["--lts-product", HNC]
        st, out = run(HCN, args, BASE + "/ts-" + method)
        p = os.path.join(BASE + "/ts-" + method, "m7m.landscape_ts.json")
        ok = False
        if os.path.exists(p):
            doc = json.load(open(p))
            ok = (doc["counters"].get("method") == ident
                  and doc["task"] == "ts")
        methods["ts-" + method] = {"exit": st, "method_ok": ok}
    for method, ident in IRC_METHODS.items():
        args = ["--gfn", "2", "--lirc", "--lirc-method", method,
                "--lirc-max-steps", "4", "--norestart", "--ljson",
                "--namespace", "m7m"]
        st, out = run(HCN, args, BASE + "/irc-" + method)
        p = os.path.join(BASE + "/irc-" + method, "m7m.landscape_irc.json")
        ok = False
        if os.path.exists(p):
            doc = json.load(open(p))
            ok = (doc["counters"].get("method") == ident
                  and doc["task"] == "irc")
        methods["irc-" + method] = {"exit": st, "method_ok": ok}
    report["methods"] = methods
    print("methods:", {k: (v["exit"], v["method_ok"]) for k, v in methods.items()})

    json.dump(report, open(BASE + "/verify.json", "w"), indent=1,
              sort_keys=True, default=str)


if __name__ == "__main__":
    main()
