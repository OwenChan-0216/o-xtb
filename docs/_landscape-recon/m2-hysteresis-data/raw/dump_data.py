#!/usr/bin/env python3
"""Dump every raw data point of the M2 validation into the report data dir.
Robust by construction: a missing file or an unparsable point yields `nan`
instead of an exception, and the run never aborts on a single bad point."""
import os, re, math, shutil, sys
import numpy as np
sys.path.insert(0, '/tmp/m2-exp')
from final_analysis import (read_frames, read_table, reached_deg, hysteresis,
                            torsion, vertex, KCAL, OUT)

SRC = '/tmp/m2-exp'
report = []

def w(fn, text):
    path = os.path.join(OUT, fn)
    with open(path, 'w') as h:
        h.write(text)
    print("wrote", path)

# ---------------------------------------------------------------- hysteresis
rows = ["grid,level,points_compared,max_abs_dE_Eh,max_abs_dE_kcal,largest_jump_Eh,jump_from_deg,jump_to_deg"]
for grid in ('12', '24'):
    for lvl in ('superloose', 'loose', 'normal', 'tight', 'vtight'):
        h = hysteresis('r_hyst%s_%s.log' % (grid, lvl))
        rows.append("%sdeg,%s,%d,%.9e,%.9e,%.9e,%.4f,%.4f" % (
            grid, lvl, h['compared'], h['max_delta'], h['max_delta']*KCAL,
            h['jump'], h['jump_from'], h['jump_to']))
w('hysteresis.csv', "\n".join(rows) + "\n")

# full profiles of the two reference levels (12 deg grid)
lines = ["# forward branch targets, forward/reverse de-biased energies (Eh)",
         "level,target_deg,E_fwd_Eh,E_rev_Eh,dE_Eh"]
for lvl in ('superloose', 'loose', 'normal', 'tight', 'vtight'):
    pts = read_table('r_hyst12_%s.log' % lvl)
    frames = read_frames('h12%s.xtbscan.log' % lvl)
    q = reached_deg(frames)
    n = len(pts); nf = (n + 1)//2
    for k in range(nf - 1):
        a, b = k, n - 1 - k
        lines.append("%s,%.8f,%.12f,%.12f,%.6e" % (
            lvl, pts[a]['value'], pts[a]['energy'], pts[b]['energy'],
            abs(pts[a]['energy'] - pts[b]['energy'])))
    for k in range(n):
        lines.append("%s,reached_%.8f,%.12f,," % (lvl, q[k] if k < len(q) else float('nan'), pts[k]['energy']))
w('hysteresis_profiles.csv', "\n".join(lines) + "\n")

# --------------------------------------------------------------- fc sweep
lines = ["# one-way relaxed scan, 24 deg grid, target -180..-60 deg, level normal",
         "fc_hartree,target_deg,reached_deg,drift_deg,energy_Eh,residual_Eh_per_rad,steps,converged"]
fctab = {}
for fc in ('0.05', '0.1', '0.5', '2.0', '5.0', '10.0'):
    pts = read_table('r_fc_%s.log' % fc)
    frames = read_frames('f%s.xtbscan.log' % fc)
    q = reached_deg(frames)
    fctab[fc] = (pts, q)
    for k, p in enumerate(pts):
        qq = q[k] if k < len(q) else float('nan')
        lines.append("%s,%.8f,%.8f,%.6f,%.12f,%s,%d,%s" % (
            fc, p['value'], qq, qq - p['value'], p['energy'], p['residual'],
            p['steps'], p['conv']))
w('fc_sweep.csv', "\n".join(lines) + "\n")

# fc summary: barrier height from the grid maximum, anti-gauche gap
lines = ["# fc, max|drift|_deg, barriertheta_reached_deg, E_max_Eh, E_anti_Eh, barrier_height_Eh, barrier_kcal,",
         "#     E_gauche_Eh, anti_gauche_Eh, anti_gauche_kcal, max|residual|"]
for fc in ('0.05', '0.1', '0.5', '2.0', '5.0', '10.0'):
    pts, q = fctab[fc]
    q = np.array(q); e = np.array([p['energy'] for p in pts]); v = np.array([p['value'] for p in pts])
    res = np.array([abs(float(p['residual'])) for p in pts])
    j = int(np.argmax(e))
    lines.append("%s,%.4f,%.4f,%.12f,%.12f,%.9f,%.6f,%.12f,%.9f,%.6f,%.3e" % (
        fc, np.max(np.abs(q - v)), q[j], e[j], e[0], e[j] - e[0], (e[j]-e[0])*KCAL,
        e[-1], e[-1] - e[0], (e[-1]-e[0])*KCAL, np.max(res)))
w('fc_summary.csv', "\n".join(lines) + "\n")

# ----------------------------------------------------------- rigid driver
lines = ["# rigid dihedral scan of 1,2-dichloroethane (driver), 12 deg grid",
         "point,target_deg,reached_deg,energy_Eh,residual,steps,converged"]
pts = read_table('r_rigid12.log')
frames = read_frames('rigid12.xtbscan.log')
q = reached_deg(frames)
for k, p in enumerate(pts):
    qq = q[k] if k < len(q) else float('nan')
    lines.append("%d,%.8f,%.8f,%.12f,%s,%d,%s" % (k+1, p['value'], qq, p['energy'],
                                                  p['residual'], p['steps'], p['conv']))
w('rigid_driver.csv', "\n".join(lines) + "\n")

# ------------------------------------------------------------- consistency
def read_scan(path):
    """(energies, geometries) of an xtbscan.log; a bad frame becomes nan/None."""
    frames = read_frames(path)
    e = np.array([x[0] for x in frames])
    g = [x[1] for x in frames]
    return e, g


def consistency(ref, lscan, out, comment):
    e_ref, g_ref = read_scan(ref)
    e_ls, g_ls = read_scan(lscan)
    n = min(len(e_ref), len(e_ls))
    lines = ["# " + comment,
             "# legacy frames %d, landscape frames %d" % (len(e_ref), len(e_ls)),
             "point,E_legacy_scan_Eh,E_landscape_scan_Eh,diff_Eh,diff_kcal,max_coord_dev_bohr"]
    mx = 0.0
    nvalid = 0
    for k in range(n):
        if any([not np.isfinite(x) or x == 0.0 for x in (e_ref[k], e_ls[k])]):
            lines.append("%d,nan,nan,nan,nan,nan" % (k + 1))
            continue
        d = e_ls[k] - e_ref[k]
        nvalid += 1
        mx = max(mx, abs(d))
        dev = float('nan')
        if g_ref[k] is not None and g_ls[k] is not None and g_ref[k].shape == g_ls[k].shape:
            dev = float(np.max(np.abs(g_ref[k] - g_ls[k])))
        lines.append("%d,%.12f,%.12f,%.10e,%.6e,%.6e" % (
            k + 1, e_ref[k], e_ls[k], d, d * KCAL, dev))
    lines.append("# valid points %d / %d ; max |diff| = %.6e Eh (%.6e kcal/mol)" % (
        nvalid, n, mx, mx * KCAL))
    w(out, "\n".join(lines) + "\n")
    return nvalid, n, mx


print()
print("== consistency ==")
for tag, ref, ls, note in (
    ("water_normal", 'water/ref_n_omp1.xtbscan.log', 'water/lw1.xtbscan.log',
     "H2O distance 1-2, 5 points 0.96..1.36 Ang, fc=0.5, both default levels"),
    ("water_vtight", 'water/ref_v.xtbscan.log', 'water/lwv.xtbscan.log',
     "H2O distance 1-2, 5 points 0.96..1.36 Ang, fc=0.5, both vtight"),
    ("water_normal_8thread", 'water/ref_n.xtbscan.log', 'water/lw.xtbscan.log',
     "H2O distance 1-2, 5 points, fc=0.5, both default, OMP_NUM_THREADS=8"),
    ("h2o2_normal", 'scanref/ref_scan_normal.xtbscan.log', 'scanref/lscan_ref.xtbscan.log',
     "H2O2 dihedral 3-1-2-4, 13 points -179.78..0.22 deg, fc=0.5, both default levels, OMP_NUM_THREADS=8"),
    ("h2o2_vtight", 'scanref/ref_scan_vtight.xtbscan.log', 'h2lvtight.xtbscan.log',
     "H2O2 dihedral 3-1-2-4, 13 points, fc=0.5, both vtight, OMP_NUM_THREADS=8"),
    ("h2o2_default_omp1", 'scanref/ref_scan_normal.xtbscan.log', 'h2lnormal.xtbscan.log',
     "H2O2 dihedral 3-1-2-4, 13 points, fc=0.5, legacy default vs landscape default, landscape OMP_NUM_THREADS=1"),
    ("h2o2_vtight_omp1", 'scanref/ref_scan_vtight.xtbscan.log', 'h2lvtight.xtbscan.log',
     "H2O2 dihedral 3-1-2-4, 13 points, fc=0.5, legacy vs landscape at vtight, landscape OMP_NUM_THREADS=1"),
    ("h2o2_tight_omp1", 'scanref/ref_scan_normal.xtbscan.log', 'h2ltight.xtbscan.log',
     "H2O2 dihedral, 13 points, legacy default vs landscape tight, landscape OMP_NUM_THREADS=1")):
    r = consistency(os.path.join(SRC, ref), os.path.join(SRC, ls),
                    "consistency_%s.csv" % tag, note)
    print("  %-26s valid %d/%d  max|dE| = %.6e Eh = %.6e kcal/mol" % ((tag,) + r + (r[2] * KCAL,)))

# ------------------------------------------------------- failure probe
lines = ["# deliberately failing scan points (mechanism of a point with no value)",
         "case,target_or_point,energy_Eh,residual,steps,converged,run_exit"]
for tag, fn, exitcode in (("huge_distance_step5A", 'failtest/huge.log', 1),
                          ("scf_maxiter1", 'failtest/fail3.log', 1),
                          ("negative_distance_target", 'failtest/neg.log', 0)):
    for p in read_table(os.path.join(SRC, fn)):
        lines.append("%s,%d,%.12f,%s,%d,%s,%d" % (tag, p['i'], p['energy'], p['residual'],
                                                  p['steps'], p['conv'], exitcode))
w('failure_probe.csv', "\n".join(lines) + "\n")

print("done")
