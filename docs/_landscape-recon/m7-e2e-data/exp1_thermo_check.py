#!/usr/bin/env python3
"""Experiment 1 driver: the `--lvib` vs `--hess` thermochemistry comparison.

For every system: optimise with `--lopt --lopt-level tight`, then run `--lvib`
and `--hess` on the optimised `xtbopt.xyz` (the same geometry, so the only
difference left is the projection convention and the FD discretisation), then
compare the frequencies, ZPE, H, G and S and cross-check the thermochemical
parameter block of the two runs.
"""
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import thermo_independent as ti

EXE = sys.argv[1] if len(sys.argv) > 1 else "/tmp/xtb-land/build/xtb"
BASE = os.path.dirname(os.path.abspath(__file__))
ENV = dict(os.environ, OMP_NUM_THREADS="1",
           XTBPATH=os.environ["XTBPATH"])
AUTORCM = ti.AUTORCM

SYSTEMS = [("h2o", "h2o.xyz"), ("ch3oh", "ch3oh.xyz"),
           ("co2", "co2.xyz"), ("c2h2", "c2h2.xyz")]


def run(args, cwd, outfile):
    with open(outfile, "w") as handle:
        proc = subprocess.run([EXE] + args, cwd=cwd, stdout=handle,
                              stderr=subprocess.STDOUT, env=ENV)
    return proc.returncode


def analyse(path, geom):
    text = open(path).read()
    got = ti.parse_output(text)
    syms, xyz = ti.parse_xyz(geom)
    freqs = [v for v in got["eigval"] if abs(v) > 1.0]
    ref = ti.recompute(freqs, syms, xyz, got["temp"],
                       float(got["rotor_cutoff"].split()[0]),
                       float(got["rotational_number"]),
                       got["linear"] == "true", int(got["n_freq"]))
    return got, freqs, ref


def main():
    result = {}
    for name, xyz in SYSTEMS:
        run_dir = os.path.join(BASE, "exp1-thermo", name)
        geom_in = os.path.join(run_dir, xyz)
        entry = {"input": xyz}
        entry["opt_status"] = run([geom_in, "--gfn", "2", "--lopt",
                                   "--lopt-level", "tight", "--norestart"],
                                  run_dir, os.path.join(run_dir, "opt.out"))
        geom = os.path.join(run_dir, "xtbopt.xyz")
        entry["lvib_status"] = run([geom, "--gfn", "2", "--lvib", "--norestart"],
                                   run_dir, os.path.join(run_dir, "lvib.out"))
        entry["hess_status"] = run([geom, "--gfn", "2", "--hess", "--norestart"],
                                   run_dir, os.path.join(run_dir, "hess.out"))
        if max(entry["opt_status"], entry["lvib_status"], entry["hess_status"]):
            entry["error"] = "non zero exit"
        vib, vib_freq, vib_ref = analyse(os.path.join(run_dir, "lvib.out"), geom)
        hss, hess_freq, hess_ref = analyse(os.path.join(run_dir, "hess.out"), geom)

        # the optimised geometry and its energy
        with open(geom) as handle:
            head = handle.readlines()[1]
        entry["opt_energy"] = float(re.search(r"energy:\s+(-?[\d.]+)", head).group(1))
        entry["opt_gnorm"] = float(re.search(r"gnorm:\s+(-?[\d.eE+-]+)", head).group(1))

        # parameter block: everything thermochemical that could differ
        keys = ["n_freq", "n_imag", "linear", "symmetry", "rotational_number",
                "scaling_factor", "rotor_cutoff", "imag_cutoff", "temp"]
        entry["params"] = {k: {"lvib": vib.get(k), "hess": hss.get(k),
                               "equal": vib.get(k) == hss.get(k)} for k in keys}

        entry["frequencies"] = {"lvib": vib_freq, "hess": hess_freq,
                                "n_internal": len(vib_freq)}
        entry["max_dfreq"] = max(abs(a - b) for a, b in zip(vib_freq, hess_freq))
        for q in ("zpe", "h_total", "g_total"):
            entry[q] = {"lvib": vib.get(q, vib.get("g_total_prop")),
                        "hess": hss.get(q, hss.get("g_total_prop")),
                        "delta": vib.get(q, vib.get("g_total_prop"))
                                 - hss.get(q, hss.get("g_total_prop"))}
        entry["h_total"]["lvib"] = vib["h_total"]
        entry["s_tot_cal"] = {"lvib": vib["s_tot_cal"], "hess": hss["s_tot_cal"],
                              "delta": vib["s_tot_cal"] - hss["s_tot_cal"]}
        entry["ts_eh"] = {"lvib": vib["ts"], "hess": hss["ts"],
                          "delta": vib["ts"] - hss["ts"]}

        # independent recompute of both routes
        entry["independent_vs_xtb_lvib"] = {
            "d_zpe": vib["zpe"] - vib_ref["zpe"],
            "d_s_tot": vib["s_tot_cal"] - vib_ref["s_tot"],
            "d_ht": vib["ht"] - vib_ref["ht"],
            "d_gt": vib["gt"] - vib_ref["gt"]}
        entry["independent_vs_xtb_hess"] = {
            "d_zpe": hss["zpe"] - hess_ref["zpe"],
            "d_s_tot": hss["s_tot_cal"] - hess_ref["s_tot"],
            "d_ht": hss["ht"] - hess_ref["ht"],
            "d_gt": hss["gt"] - hess_ref["gt"]}
        # identity ZPE = 1/2 sum nu from the printed table
        entry["zpe_identity_lvib"] = vib["zpe"] - 0.5 * sum(vib_freq) / AUTORCM
        entry["zpe_identity_hess"] = hss["zpe"] - 0.5 * sum(hess_freq) / AUTORCM
        result[name] = entry
        print("%-6s dfreq %.4f cm^-1  dZPE %.3e  dH %.3e  dG %.3e Eh  "
              "param-equal %s" % (name, entry["max_dfreq"],
                                  entry["zpe"]["delta"], entry["h_total"]["delta"],
                                  entry["g_total"]["delta"],
                                  all(v["equal"] for v in entry["params"].values())))
    with open(os.path.join(BASE, "exp1-thermo", "summary.json"), "w") as handle:
        json.dump(result, handle, indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
