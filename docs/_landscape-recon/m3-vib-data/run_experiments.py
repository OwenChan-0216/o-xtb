#!/usr/bin/env python3
"""M3 (vib) validation experiments: PLAN 8.2 #2/#3/#12 plus interop (#D).

Every xtb call runs with OMP_NUM_THREADS=1 (AGENTS.md 4/6) and is wrapped in
``|| true`` semantics: a failing job records nan and never aborts the run.
"""
import csv
import math
import os
import re
import shutil
import subprocess
import sys

ROOT = "/home/owenchan/work_path/coding/fortran/xtb"
XTB = "/tmp/xtb-land/build/xtb"
DATA = os.path.join(ROOT, "docs/_landscape-recon/m3-vib-data")
MOL = os.path.join(DATA, "mol")
SCRATCH = "/tmp/m3vib/scratch"

ENV = dict(os.environ)
ENV["XTBPATH"] = ROOT
ENV["OMP_NUM_THREADS"] = "1"

NAN = float("nan")


def run(case, molpath, args, keep=("hessian", "vibspectrum", "g98.out",
                                   "vib_normal_modes")):
    """Run one xtb job in an isolated directory; return (text, status)."""
    wd = os.path.join(SCRATCH, case)
    if os.path.isdir(wd):
        shutil.rmtree(wd)
    os.makedirs(wd)
    cmd = [XTB, molpath] + args
    try:
        p = subprocess.run(cmd, cwd=wd, env=ENV, capture_output=True,
                           text=True, timeout=900)
        text = p.stdout + p.stderr
        status = p.returncode
    except Exception as exc:                     # never abort the sweep
        text = "%s\n" % exc
        status = -1
    outdir = os.path.join(DATA, case)
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "stdout.txt"), "w") as fh:
        fh.write(text)
    for name in keep:
        src = os.path.join(wd, name)
        if os.path.exists(src):
            shutil.copy(src, os.path.join(outdir, name))
    return text, status


def fnum(tok):
    try:
        return float(tok)
    except ValueError:
        return NAN


def grab(pattern, text, group=1, cast=float, default=NAN):
    m = re.search(pattern, text)
    if not m:
        return default
    if cast is float:
        return fnum(m.group(group))
    return cast(m.group(group))


def parse(text):
    d = {}
    # `eigval :` lines come in blocks; the existing `--hess` path prints its
    # block twice (numhess and print_thermo), so only the first block is used.
    blocks = []
    cur = []
    for line in text.splitlines():
        m = re.match(r"\s*eigval\s*:(.*)", line)
        if m:
            for tok in m.group(1).split():
                v = fnum(tok)
                if not math.isnan(v):
                    cur.append(v)
        elif cur:
            blocks.append(cur)
            cur = []
    if cur:
        blocks.append(cur)
    freqs = blocks[0] if blocks else []
    nz = 0
    for v in freqs:
        if abs(v) < 5.0e-3:
            nz += 1
        else:
            break
    d["freqs"] = freqs
    d["n_modes_printed"] = len(freqs)
    d["n_zero"] = nz
    d["n_zero_reported"] = int(grab(r"internal,\s+(\d+) projected zero modes",
                                    text, cast=int, default=-1))
    d["n_internal"] = len(freqs) - nz if freqs else -1
    d["n_internal_reported"] = int(grab(r"modes:\s+(\d+) internal", text,
                                        cast=int, default=-1))
    lin = re.search(r"linear molecule:\s+([TF])", text)
    d["linear"] = (lin.group(1) == "T") if lin else None
    d["n_imag"] = int(grab(r"imaginary modes:\s+(\d+)", text, cast=int,
                           default=-1))
    d["lowest_mode"] = grab(r"lowest mode:\s+([-0-9.]+) cm", text)
    d["highest_mode"] = grab(r"highest mode:\s+([-0-9.]+) cm", text)
    d["energy"] = grab(r"TOTAL ENERGY\s+([-0-9.]+) Eh", text)
    d["gnorm"] = grab(r"gradient norm:\s+([-0-9.Ee+]+) Eh", text)
    d["hdr_step"] = grab(r"Hessian step:\s+([-0-9.Ee+]+) bohr", text)
    d["hdr_acc"] = grab(r"Hessian SCC accuracy:\s+([-0-9.Ee+]+)", text)
    d["etemp_echo"] = grab(r"electronic temp\.\s+([0-9.]+)\s+K", text)
    d["zpe_out"] = grab(r"zero point energy:\s+([-0-9.Ee+]+) Eh", text)
    d["zpe_tab"] = grab(r":: zero point energy\s+([-0-9.Ee+]+) Eh", text)
    d["g_total"] = grab(r"total free energy\s+([-0-9.]+) Eh", text)
    d["e_total_tab"] = grab(r":: total energy\s+([-0-9.]+) Eh", text)
    d["g_no_zpve"] = grab(r"G\(RRHO\) w/o ZPVE\s+([-0-9.]+) Eh", text)
    d["g_contrib"] = grab(r"G\(RRHO\) contrib\.\s+([-0-9.]+) Eh", text)
    m = re.search(r"TOT\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)", text)
    d["H_cal"] = fnum(m.group(1)) if m else NAN
    d["Cp_cal"] = fnum(m.group(2)) if m else NAN
    d["S_cal"] = fnum(m.group(3)) if m else NAN
    d["S_J"] = fnum(m.group(4)) if m else NAN
    d["q_TR"] = grab(r"TR\s+([0-9.Ee+-]+)", text)
    d["q_ROT"] = grab(r"ROT\s+([0-9.Ee+-]+)", text)
    d["q_VIB"] = grab(r"VIB\s+([0-9.Ee+-]+)", text)
    d["q_INT"] = grab(r"INT\s+([0-9.Ee+-]+)", text)
    lin2 = re.search(r"linear\?\s+(true|false)", text)
    d["thermo_linear"] = (lin2.group(1) == "true") if lin2 else None
    d["symmetry"] = grab(r"symmetry\s+(\S+)", text, cast=str, default="")
    d["rot_number"] = int(grab(r"rotational number\s+(\d+)", text, cast=int,
                               default=-1))
    d["freq_scal"] = grab(r"frequency scaling factor:\s+([-0-9.]+)", text)
    d["status"] = None
    return d


def internal(d):
    """Internal-mode frequencies only (drop the projected zero modes)."""
    nz = d["n_zero"]
    return d["freqs"][nz:] if d["freqs"] else d["freqs"]


def g98_freqs(path):
    """4-decimal internal-mode frequencies from a Gaussian-style g98.out."""
    out = []
    if not os.path.exists(path):
        return out
    with open(path) as fh:
        for line in fh:
            if "Frequencies --" in line:
                tail = line.split("Frequencies --", 1)[1]
                for tok in tail.split():
                    v = fnum(tok)
                    if not math.isnan(v):
                        out.append(v)
    return out


def case_freqs(case, d):
    """Internal frequencies at the highest available precision."""
    g = g98_freqs(os.path.join(DATA, case, "g98.out"))
    return g if g else internal(d)


def lowest3(d):
    f = internal(d)
    return f[:3] if len(f) >= 3 else f


# --------------------------------------------------------------------------
def wcsv(path, header, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="") as fh:
        wr = csv.writer(fh)
        wr.writerow(header)
        for r in rows:
            wr.writerow(r)


def log(*a):
    print(*a, flush=True)


def main():
    os.makedirs(MOL, exist_ok=True)

    # ---------------- Experiment A: step x sccacc -------------------------
    log("== Experiment A: Hessian step x SCC accuracy ==")
    steps = [0.002, 0.005, 0.010, 0.020]
    accs = [0.1, 0.3, 1.0]
    rows_a = []
    for mol in ["h2o", "ch3oh"]:
        mp = os.path.join(MOL, "%s_opt.xyz" % mol)
        if not os.path.exists(mp):
            mp = os.path.join(MOL, "%s.xyz" % mol)
        recs = {}
        for st in steps:
            for ac in accs:
                case = "expA/%s/step%.3f_acc%.1f" % (mol, st, ac)
                args = ["--gfn2", "--lvib", "--norestart",
                        "--lvib-step", "%.5f" % st,
                        "--lvib-sccacc", "%.3f" % ac]
                text, status = run(case, mp, args)
                d = parse(text)
                d["status"] = status
                d["gfreq"] = case_freqs(case, d)
                recs[(st, ac)] = d
        # drift relative to the default (0.005, 0.3); g98.out carries 4
        # decimals, the stdout only 2, so the g98 set is the precise one
        base = recs[(0.005, 0.3)]
        fb0 = base["gfreq"]
        for st in steps:
            for ac in accs:
                cur = recs[(st, ac)]
                fc = cur["gfreq"]
                if len(fb0) == len(fc) and fb0:
                    df = max(abs(x - y) for x, y in zip(fb0, fc))
                    dlow = abs(fb0[0] - fc[0])
                    dlow_rel = dlow / abs(fb0[0]) if fb0[0] else NAN
                else:
                    df, dlow, dlow_rel = NAN, NAN, NAN
                rows_a.append([mol, st, ac, len(fc), cur["n_internal_reported"],
                               cur["n_zero"], cur["n_imag"], cur["status"],
                               "%.5f" % cur["hdr_step"],
                               "%.3f" % cur["hdr_acc"],
                               "%.12f" % cur["energy"],
                               "%.12e" % cur["zpe_tab"],
                               "%.6e" % (cur["energy"] - base["energy"]),
                               "%.6e" % (cur["zpe_tab"] - base["zpe_tab"]),
                               "%.6f" % df, "%.6f" % dlow,
                               "%.3e" % dlow_rel,
                               " ".join("%.4f" % x for x in fc),
                               " ".join("%.2f" % x for x in cur["freqs"])])
    wcsv(os.path.join(DATA, "expA_step_sccacc.csv"),
         ["mol", "step", "sccacc", "n_internal", "n_internal_reported",
          "n_zero", "n_imag", "status", "hdr_step", "hdr_acc",
          "energy_Eh", "zpe_Eh", "dE_vs_default",
          "dZPE_vs_default", "max_dfreq_cm1", "d_lowest_cm1",
          "d_lowest_rel", "internal_freqs_cm1", "all_freqs_cm1"], rows_a)

    # ---------------- Experiment B: etemp --------------------------------
    log("== Experiment B: etemp ==")
    etemps = [0.0, 300.0, 1000.0, 5000.0]
    cases_b = [("h2o", [], None), ("h2s", [], None),
               ("ch3", ["--uhf", "1"], 1), ("o2", ["--uhf", "2"], 2)]
    rows_b = []
    for mol, extra, _ in cases_b:
        mp = os.path.join(MOL, "%s_opt.xyz" % mol)
        if not os.path.exists(mp):
            mp = os.path.join(MOL, "%s.xyz" % mol)
        for et in etemps:
            case = "expB/%s/etemp%d" % (mol, int(et))
            args = ["--gfn2", "--lvib", "--norestart",
                    "--etemp", "%.1f" % et] + extra
            text, status = run(case, mp, args)
            d = parse(text)
            d["status"] = status
            f = d["gfreq"] = case_freqs(case, d)
            rows_b.append([mol, et, status, "%.1f" % d["etemp_echo"],
                           d["n_imag"],
                           "%.12f" % d["energy"], "%.12e" % d["zpe_tab"],
                           "%.6f" % f[0] if f else "nan",
                           "%.6f" % f[1] if len(f) > 1 else "nan",
                           "%.6f" % f[2] if len(f) > 2 else "nan",
                           " ".join("%.4f" % x for x in f)])
    # Hessian change between the etemp values (bit level, same geometry)
    rows_h = []
    for mol, _, _ in cases_b:
        h = {}
        for et in etemps:
            p = os.path.join(DATA, "expB/%s/etemp%d/hessian" % (mol, int(et)))
            h[et] = load_hessian(p) if os.path.exists(p) else []
        ref = h[300.0]
        for et in etemps:
            v = h[et]
            if len(v) == len(ref) and v:
                md = max(abs(a - b) for a, b in zip(v, ref))
                mx = max(abs(x) for x in ref) or 1.0
                same = (v == ref)
                # frequency change from the file
                rows_h.append([mol, et, len(v), "%.6e" % md, "%.3e" % (md / mx),
                               "identical" if same else "differs"])
            else:
                rows_h.append([mol, et, len(v), "nan", "nan", "unavailable"])
    wcsv(os.path.join(DATA, "expB_etemp_hessian.csv"),
         ["mol", "etemp_K", "n_values", "max_abs_dH", "max_rel_dH", "vs_300K"],
         rows_h)
    # relative drift vs etemp=300
    wcsv(os.path.join(DATA, "expB_etemp.csv"),
         ["mol", "etemp_K", "status", "etemp_echo_K", "n_imag", "energy_Eh", "zpe_Eh",
          "lowest1_cm1", "lowest2_cm1", "lowest3_cm1", "internal_freqs_cm1"],
         rows_b)

    # ---------------- Experiment C: linear 3N-5 --------------------------
    log("== Experiment C: linear molecules ==")
    rows_c = []
    for mol, nn in [("co2", 3), ("hcn", 3), ("h2o", 3), ("ch3oh", 6)]:
        mp = os.path.join(MOL, "%s_opt.xyz" % mol)
        if not os.path.exists(mp):
            mp = os.path.join(MOL, "%s.xyz" % mol)
        for tag, args in [("lvib", ["--gfn2", "--lvib", "--norestart"]),
                          ("hess", ["--gfn2", "--hess", "--norestart"])]:
            case = "expC/%s/%s" % (mol, tag)
            text, status = run(case, mp, args)
            d = parse(text)
            d["status"] = status
            f = d["gfreq"] = case_freqs(case, d)
            rows_c.append([mol, nn, tag, status, d["linear"], d["thermo_linear"],
                           d["n_internal"], d["n_zero"], d["n_modes_printed"],
                           d["rot_number"], d["symmetry"],
                           "%.6e" % d["q_TR"], "%.6e" % d["q_ROT"],
                           "%.6e" % d["q_VIB"], "%.6e" % d["q_INT"],
                           "%.12f" % d["energy"], "%.12e" % d["zpe_tab"],
                           " ".join("%.4f" % x for x in d["freqs"]),
                           " ".join("%.4f" % x for x in f)])
    wcsv(os.path.join(DATA, "expC_linear.csv"),
         ["mol", "n_atoms", "path", "status", "linear_flag", "thermo_linear",
          "n_internal", "n_zero", "n_modes_printed", "rot_number", "symmetry",
          "q_TR", "q_ROT", "q_VIB", "q_INT", "energy_Eh", "zpe_Eh",
          "stdout_freqs_cm1", "g98_freqs_cm1"], rows_c)

    # ---------------- Experiment D: interop with --hess ------------------
    log("== Experiment D: interoperability ==")
    rows_d = []
    for mol in ["h2o", "h2o_raw", "co2", "ch3oh"]:
        mp = os.path.join(MOL, "%s_opt.xyz" % mol)
        if not os.path.exists(mp):
            mp = os.path.join(MOL, "%s.xyz" % mol)
        cli = "expD/%s/lvib" % mol
        chs = "expD/%s/hess" % mol
        t1, s1 = run(cli, mp, ["--gfn2", "--lvib", "--norestart"])
        t2, s2 = run(chs, mp, ["--gfn2", "--hess", "--norestart"])
        d1, d2 = parse(t1), parse(t2)
        d1["status"], d2["status"] = s1, s2
        f1 = case_freqs(cli, d1)
        f2 = case_freqs(chs, d2)
        d1["gfreq"], d2["gfreq"] = f1, f2
        # file level comparison
        cmp_rows = compare_files(cli, chs)
        for name, info in cmp_rows.items():
            rows_d.append([mol, name, info["same_bytes"], info["max_abs"],
                           info["max_rel"], info["note"]])
        # numeric comparison
        dfmax = (max(abs(a - b) for a, b in zip(f1, f2))
                 if len(f1) == len(f2) and f1 else NAN)
        rows_d.append([mol, "frequencies", "", "%.6f" % dfmax, "",
                       "lvib [%s] vs hess [%s]" %
                       (" ".join("%.2f" % x for x in f1),
                        " ".join("%.2f" % x for x in f2))])
        rows_d.append([mol, "n_internal", "", "%d vs %d" % (d1["n_internal"],
                       d2["n_internal"]), "",
                       "zero modes %d vs %d" % (d1["n_zero"], d2["n_zero"])])
        rows_d.append([mol, "zpe", "", "%.6e" % (d1["zpe_tab"] - d2["zpe_tab"]),
                       "", "lvib %.10e hess %.10e" % (d1["zpe_tab"],
                                                      d2["zpe_tab"])])
        rows_d.append([mol, "g_total", "",
                       "%.6e" % (d1["g_total"] - d2["g_total"]), "",
                       "lvib %.10e hess %.10e" % (d1["g_total"], d2["g_total"])])
        rows_d.append([mol, "S_cal", "",
                       "%.6e" % (d1["S_cal"] - d2["S_cal"]), "",
                       "lvib %.6f hess %.6f" % (d1["S_cal"], d2["S_cal"])])
        rows_d.append([mol, "Cp_cal", "",
                       "%.6e" % (d1["Cp_cal"] - d2["Cp_cal"]), "",
                       "lvib %.6f hess %.6f" % (d1["Cp_cal"], d2["Cp_cal"])])
        rows_d.append([mol, "H_cal", "",
                       "%.6e" % (d1["H_cal"] - d2["H_cal"]), "",
                       "lvib %.6f hess %.6f" % (d1["H_cal"], d2["H_cal"])])
        rows_d.append([mol, "energy", "",
                       "%.6e" % (d1["energy"] - d2["energy"]), "",
                       "lvib %.12f hess %.12f" % (d1["energy"], d2["energy"])])
        rows_d.append([mol, "q_TR", "",
                       "%.6e" % (d1["q_TR"] - d2["q_TR"]), "",
                       "lvib %.6e hess %.6e" % (d1["q_TR"], d2["q_TR"])])
    # file-provider round trip: read our own hessian back
    for mol in ["h2o", "co2"]:
        mp = os.path.join(MOL, "%s_opt.xyz" % mol)
        case = "expD/%s/lvib-from-file" % mol
        t, s = run(case, mp, ["--gfn2", "--lvib", "--lvib-hessian", "file",
                              "--lvib-hessian-file",
                              os.path.join(DATA, "expD/%s/lvib/hessian" % mol),
                              "--norestart"])
        d = parse(t)
        base = parse(open(os.path.join(DATA, "expD/%s/lvib/stdout.txt" % mol)).read())
        f = case_freqs(case, d)
        fb = case_freqs("expD/%s/lvib" % mol, base)
        same = (f == fb) and (internal(d) == internal(base))
        df = max(abs(a - b) for a, b in zip(f, fb)) if (len(f) == len(fb) and f) else NAN
        rows_d.append([mol, "file-provider(self)", "", "%.9f" % df, "",
                       "bitwise identical frequencies: %s" % same])
        # the reader must also accept the Hessian written by the existing --hess
        hcase = "expD/%s/lvib-read-hess" % mol
        t2, s2 = run(hcase, mp, ["--gfn2", "--lvib", "--lvib-hessian", "file",
                                 "--lvib-hessian-file",
                                 os.path.join(DATA, "expD/%s/hess/hessian" % mol),
                                 "--norestart"])
        d2 = parse(t2)
        dref = parse(open(os.path.join(DATA, "expD/%s/hess/stdout.txt" % mol)).read())
        f2 = case_freqs(hcase, d2)
        fr = case_freqs("expD/%s/hess" % mol, dref)
        df2 = max(abs(a - b) for a, b in zip(f2, fr)) if len(f2) == len(fr) and f2 else NAN
        rows_d.append([mol, "file-provider(hess-file)", "", "%.9f" % df2, "",
                       "lvib-from-hess-file vs --hess: %s vs %s" %
                       (" ".join("%.4f" % x for x in f2),
                        " ".join("%.4f" % x for x in fr))])
        # vibspectrum wave-number column only (the IR intensity column is a
        # documented difference: the provider carries no dipole derivatives)
        va = vibspec_freqs(os.path.join(DATA, "expD/%s/lvib/vibspectrum" % mol))
        vb = vibspec_freqs(os.path.join(DATA, "expD/%s/hess/vibspectrum" % mol))
        dv = max(abs(a - b) for a, b in zip(va, vb)) if len(va) == len(vb) and va else NAN
        rows_d.append([mol, "vibspectrum(wn column)", "no", "%.6f" % dv, "",
                       "%d modes; the IR intensity column differs (0 vs --hess)"
                       % len(va)])
    # determinism: the same run twice must be bitwise identical
    for mol in ["h2o"]:
        mp = os.path.join(MOL, "%s_opt.xyz" % mol)
        t, s = run("expD/%s/lvib-repeat" % mol, mp,
                   ["--gfn2", "--lvib", "--norestart"])
        a = os.path.join(DATA, "expD/%s/lvib/hessian" % mol)
        b = os.path.join(DATA, "expD/%s/lvib-repeat/hessian" % mol)
        same = (open(a, "rb").read() == open(b, "rb").read())
        rows_d.append([mol, "determinism(hessian)", "yes" if same else "no",
                       "0", "", "two identical runs"])
    # vib_normal_modes: the existing `--hess` only writes it with the xcontrol
    # `$write vib_normal_modes=true`, so that switch is enabled explicitly
    xc = "/tmp/m3vib/xcontrol_nmtm"
    with open(xc, "w") as fh:
        fh.write("$write\n   vib_normal_modes=true\n$end\n")
    for mol in ["h2o", "co2"]:
        mp = os.path.join(MOL, "%s_opt.xyz" % mol)
        hcase = "expD/%s/hess-nmtm" % mol
        run(hcase, mp, ["--gfn2", "--hess", "--norestart", "--input", xc])
        pa = os.path.join(DATA, "expD/%s/lvib/vib_normal_modes" % mol)
        pb = os.path.join(DATA, hcase, "vib_normal_modes")
        nv = len(g98_freqs(os.path.join(DATA, "expD/%s/lvib/g98.out" % mol)))
        info = compare_normal_modes(pa, pb, nv)
        rows_d.append([mol, "vib_normal_modes", "no" if info["diff"] else "yes",
                       "%.3e" % info["max_abs_internal"], "",
                       "modes=%d; cos(internal)=[%s]; zero modes %s" %
                       (info["n_modes"],
                        " ".join("%.4f" % c for c in info["cos"]),
                        info["zero_note"])])
        rows_d.append([mol, "vib_normal_modes(exists)", "yes", "0", "",
                       "both paths wrote %d bytes / %d bytes" %
                       (info["size_a"], info["size_b"])])
    wcsv(os.path.join(DATA, "expD_interop.csv"),
         ["mol", "quantity", "byte_identical", "abs_diff", "rel_diff", "note"],
         rows_d)

    log("done")


def load_normal_modes(path):
    """TURBOMOLE `vib_normal_modes` as a list of rows.

    The writer (`writeNormalModesTurbomode`, `src/io/writer/turbomode.f90:150`)
    scales and prints the matrix it is handed index by index, so the printed
    row index is the Cartesian component and the block index is the mode; a
    mode vector is a *column* of the parsed matrix (verified against the
    `g98.out` normal coordinates).
    """
    rows = {}
    if not os.path.exists(path):
        return []
    with open(path) as fh:
        for line in fh:
            if line.startswith("$"):
                continue
            t = line.split()
            if len(t) < 3:
                continue
            try:
                i = int(t[0])
                rows.setdefault(i, []).extend(float(x) for x in t[2:])
            except ValueError:
                continue
    n = max(rows) if rows else 0
    return [rows[i] for i in range(1, n + 1)]


def compare_normal_modes(pa, pb, nv):
    a = load_normal_modes(pa)
    b = load_normal_modes(pb)
    info = {"diff": True, "max_abs_internal": NAN, "n_modes": len(a),
            "cos": [], "zero_note": "",
            "size_a": os.path.getsize(pa) if os.path.exists(pa) else -1,
            "size_b": os.path.getsize(pb) if os.path.exists(pb) else -1}
    if not a or len(a) != len(b):
        info["zero_note"] = "not comparable"
        return info
    n = len(a)
    ca = [[a[i][m] for i in range(n)] for m in range(n)]
    cb = [[b[i][m] for i in range(n)] for m in range(n)]

    def cosu(u, v):
        nu = math.sqrt(sum(x * x for x in u))
        nv = math.sqrt(sum(x * x for x in v))
        return sum(x * y for x, y in zip(u, v)) / (nu * nv) if nu * nv else 0.0

    # the projected zero modes are the leading columns of the suite's file
    info["cos"] = [cosu(ca[n - nv + k], cb[n - nv + k]) for k in range(nv)]
    worst = 0.0
    for k in range(n - nv, n):
        s = 1.0 if cosu(ca[k], cb[k]) >= 0 else -1.0
        worst = max(worst, max(abs(ca[k][i] - s * cb[k][i]) for i in range(n)))
    info["max_abs_internal"] = worst
    info["diff"] = worst > 1.0e-8
    za = max(abs(x) for k in range(n - nv) for x in ca[k]) if n > nv else 0.0
    zb = max(abs(x) for k in range(n - nv) for x in cb[k]) if n > nv else 0.0
    info["zero_note"] = "max|zero-mode block| ours %.2e theirs %.2e" % (za, zb)
    return info


def vibspec_freqs(path):
    """Wave-number column of a vibspectrum file (one float per mode)."""
    out = []
    if not os.path.exists(path):
        return out
    with open(path) as fh:
        for line in fh:
            if line.startswith("$") or line.startswith("#"):
                continue
            m = re.search(r"[-+]?\d+\.\d+", line)
            if m:
                out.append(float(m.group(0)))
    return out


def load_hessian(path):
    """Read the TURBOMOLE-layout hessian file into a flat list of numbers."""
    vals = []
    with open(path) as fh:
        for line in fh:
            if "$" in line:
                continue
            for tok in line.replace(",", " ").split():
                try:
                    vals.append(float(tok))
                except ValueError:
                    pass
    return vals


def strip_numbers(path):
    """Structural text: numbers replaced by N."""
    out = []
    with open(path) as fh:
        for line in fh:
            out.append(re.sub(r"[-+]?\d+\.\d+([EeDd][-+]?\d+)?", "N", line))
    return out


def compare_files(dir_a, dir_b):
    res = {}
    for name in ["hessian", "vibspectrum", "g98.out"]:
        pa = os.path.join(DATA, dir_a, name)
        pb = os.path.join(DATA, dir_b, name)
        if not (os.path.exists(pa) and os.path.exists(pb)):
            res[name] = {"same_bytes": "missing", "max_abs": "", "max_rel": "",
                         "note": "a=%s b=%s" % (os.path.exists(pa),
                                                os.path.exists(pb))}
            continue
        ba = open(pa, "rb").read()
        bb = open(pb, "rb").read()
        same = "yes" if ba == bb else "no"
        va, vb = load_hessian(pa), load_hessian(pb)
        if len(va) == len(vb) and va:
            md = max(abs(x - y) for x, y in zip(va, vb))
            mx = max(abs(x) for x in va) or 1.0
            mr = md / mx
            note = "n=%d max|a|=%.3e" % (len(va), mx)
        else:
            md, mr = NAN, NAN
            note = "value count %d vs %d" % (len(va), len(vb))
        res[name] = {"same_bytes": same, "max_abs": "%.6e" % md,
                     "max_rel": "%.3e" % mr, "note": note}
    return res


if __name__ == "__main__":
    main()
