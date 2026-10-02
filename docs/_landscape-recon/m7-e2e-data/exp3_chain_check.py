#!/usr/bin/env python3
"""Experiment 3: independent re-run of the `sp -> opt -> hess -> freq -> thermo`
chain (M7 validation, report 49).

The chain is a sequence of separate xtb invocations; nothing in the product
drives it, so the questions are:

  1. is the input of every step really the output of the previous one,
  2. does any step silently rebuild the geometry or the Hessian,
  3. does a failed step stop the chain (non-zero exit + no artefacts).

Every run is a fresh process in a fresh directory, `set -e` semantics are
emulated by checking each exit status, and the geometry/energy of every hand
over is compared against the file the previous step wrote.
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

EXE = "/tmp/xtb-land/build/xtb"
BASE = os.path.dirname(os.path.abspath(__file__)) + "/exp3-chain"
H2O = "/tmp/xtb-land/build/test/unit/landscape_h2o.xyz"


def run(args, rundir, omp="1"):
    os.makedirs(rundir, exist_ok=True)
    env = dict(os.environ, OMP_NUM_THREADS=omp, XTBPATH=os.environ["XTBPATH"])
    proc = subprocess.run([EXE] + list(args), cwd=rundir, capture_output=True,
                          text=True, env=env)
    return proc.returncode, proc.stdout + proc.stderr


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()[:16]


def xyz_energy(path):
    line = open(path).read().splitlines()[1]
    return float(re.search(r"energy:\s+(-?[\d.]+)", line).group(1))


def total_energy(out):
    return float(re.search(r"TOTAL ENERGY\s+(-?[\d.]+) Eh", out).group(1))


def main():
    report = {"steps": []}
    d = BASE

    # ---- step 1: sp (the plain run type; the suite's sp task is API only) ---
    st, out = run([H2O, "--gfn", "2", "--norestart"], d + "/1-sp")
    e_sp = total_energy(out)
    report["steps"].append({"step": "sp", "exit": st, "energy": e_sp})

    # ---- step 2: opt ------------------------------------------------------
    st, out = run([H2O, "--gfn", "2", "--lopt", "--lopt-level", "tight",
                   "--norestart"], d + "/2-opt")
    opt_xyz = d + "/2-opt/xtbopt.xyz"
    e_opt_stdout = float(re.search(r"final energy:\s+(-?[\d.]+)",
                                   out).group(1))
    e_opt_file = xyz_energy(opt_xyz)
    report["steps"].append({
        "step": "opt", "exit": st,
        "energy_stdout": e_opt_stdout, "energy_xtbopt": e_opt_file,
        "stdout_eq_file": e_opt_stdout == e_opt_file,
        "converged_line": "landscape: converged" in out,
        "files": sorted(os.listdir(d + "/2-opt")),
        "xtbopt_sha": sha(opt_xyz)})

    # ---- step 3: hess on the optimised geometry ---------------------------
    st, out = run([opt_xyz, "--gfn", "2", "--hess", "--norestart"], d + "/3-hess")
    report["steps"].append({
        "step": "hess", "exit": st, "energy": total_energy(out),
        "energy_eq_xtbopt": total_energy(out) == e_opt_file,
        "hessian_written": os.path.exists(d + "/3-hess/hessian"),
        "hessian_sha": sha(d + "/3-hess/hessian") if os.path.exists(
            d + "/3-hess/hessian") else None})

    # ---- step 4/5: freq + thermo on the same geometry ---------------------
    st, out = run([opt_xyz, "--gfn", "2", "--lvib", "--norestart"], d + "/4-vib")
    report["steps"].append({
        "step": "vib", "exit": st, "energy": total_energy(out),
        "energy_eq_xtbopt": total_energy(out) == e_opt_file,
        "gradient_norm": float(re.search(r"gradient norm\s+([\d.eE+-]+)",
                                         out).group(1)),
        "zpe": float(re.search(r"zero point energy\s+(-?[\d.]+) Eh",
                               out).group(1)),
        "enthalpy": float(re.search(
            r"total enthalpy H\(T\):\s+(-?[\d.eE+-]+) Eh", out).group(1)),
        "gibbs": float(re.search(
            r"total free energy G\(T\):\s+(-?[\d.eE+-]+) Eh", out).group(1)),
        "files": sorted(os.listdir(d + "/4-vib")),
        "hessian_sha": sha(d + "/4-vib/hessian") if os.path.exists(
            d + "/4-vib/hessian") else None})

    # ---- the geometry is really read from the file ------------------------
    # Move one hydrogen by 0.05 bohr and rerun the same command: the printed
    # energy has to follow the file, which rules out a cached geometry.
    perturbed = d + "/5-perturbed.xyz"
    lines = open(opt_xyz).read().splitlines()
    f = lines[2].split()
    lines[2] = "%s %.10f %s %s" % (f[0], float(f[1]) + 0.05, f[2], f[3])
    open(perturbed, "w").write("\n".join(lines) + "\n")
    st, out2 = run([perturbed, "--gfn", "2", "--lvib", "--norestart"],
                   d + "/5-vib-perturbed")
    report["perturbation"] = {
        "energy_original": total_energy(out),
        "energy_perturbed": total_energy(out2),
        "follows_file": total_energy(out2) != total_energy(out)}

    # ---- silent recomputation of the Hessian ------------------------------
    # `--lvib-hessian file` must read the Hessian of step 3 instead of
    # recomputing it: the energy evaluation count collapses and the written
    # `hessian` is byte identical to the file it was given.
    st, out3 = run([opt_xyz, "--gfn", "2", "--lvib", "--lvib-hessian", "file",
                    "--lvib-hessian-file", d + "/3-hess/hessian",
                    "--norestart"], d + "/6-vib-filehess")
    n_eval_file = int(re.search(r"energy evaluations\s+(\d+)", out3).group(1))
    n_eval_fd = int(re.search(r"energy evaluations\s+(\d+)", out).group(1))
    same_hess = (os.path.exists(d + "/6-vib-filehess/hessian") and
                 sha(d + "/6-vib-filehess/hessian") == sha(d + "/3-hess/hessian"))
    report["hessian_reuse"] = {
        "exit": st, "n_eval_from_file": n_eval_file, "n_eval_fd": n_eval_fd,
        "zpe_from_file": float(re.search(r"zero point energy\s+(-?[\d.]+) Eh",
                                         out3).group(1)),
        "zpe_fd": report["steps"][3]["zpe"],
        "reused": n_eval_file < n_eval_fd, "written_hessian_identical": same_hess}

    # ---- failure injection ------------------------------------------------
    # The frequency step is pointed at a Hessian file that does not exist; the
    # exit status must be non-zero and no result artefact may appear, so a
    # `set -e` chain stops and a runner that ignores the status cannot find a
    # usable result.
    fail_dir = d + "/7-fail"
    st, out4 = run([opt_xyz, "--gfn", "2", "--lvib", "--lvib-hessian", "file",
                    "--lvib-hessian-file", "missing_file", "--norestart"],
                   fail_dir)
    artefacts = [n for n in ("hessian", "vibspectrum", "g98.out",
                             "vib_normal_modes") if os.path.exists(
                                 os.path.join(fail_dir, n))]
    report["failure"] = {"exit": st, "artefacts": artefacts,
                         "message": [l for l in out4.splitlines()
                                     if "rror" in l][:3]}
    # a second command chained with `&&` must not run
    st2, out5 = run([opt_xyz, "--gfn", "2", "--lopt", "--norestart"], fail_dir)
    report["failure"]["next_step_would_run"] = st2 == 0

    json.dump(report, open(BASE + "/chain.json", "w"), indent=1, default=str)
    for step in report["steps"]:
        print(step)
    print("perturbation", report["perturbation"])
    print("hessian_reuse", report["hessian_reuse"])
    print("failure", report["failure"])


if __name__ == "__main__":
    main()
