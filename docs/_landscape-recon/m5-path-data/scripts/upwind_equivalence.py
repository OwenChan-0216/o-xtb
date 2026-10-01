#!/usr/bin/env python3
"""Non equivalence witness of the improved (upwind) tangent and the Eq. 11 weights.

Injection (iii) replaces the two monotonicity branches by the Eq. 11 weighted
average.  The mutation is only meaningful if the two rules differ on a
monotonic triple, which is checked here with the numbers of the unit case
`improved-tangent` (xm=(0,0,0), x=(1,0,0), xp=(1,2,0), Em=-1, E=0, Ep=+1).
"""
import numpy as np

xm = np.array([0.0, 0.0, 0.0]); x = np.array([1.0, 0.0, 0.0]); xp = np.array([1.0, 2.0, 0.0])
em, e, ep = -1.0, 0.0, 1.0
dm = x - xm; dp = xp - x
um = dm/np.linalg.norm(dm); up = dp/np.linalg.norm(dp)

# Eq. 11 weights (absolute max/min, higher energy neighbour first)
rise_up = abs(ep - e); rise_down = abs(em - e)
w_up, w_dn = (max(rise_up, rise_down), min(rise_up, rise_down)) if ep >= em else \
             (min(rise_up, rise_down), max(rise_up, rise_down))
tau_eq11 = w_up*up + w_dn*um
tau_eq11 /= np.linalg.norm(tau_eq11)
tau_upwind = up  # monotonic rising -> forward difference
print("monotonic triple (Em<E<Ep):")
print("  upwind tau      =", tau_upwind)
print("  Eq.11   tau     =", tau_eq11)
print(f"  max |difference| = {np.max(np.abs(tau_upwind - tau_eq11)):.6f}"
      f"   angle = {np.degrees(np.arccos(np.clip(tau_upwind @ tau_eq11, -1, 1))):.3f} deg")

# unit conversion of the climbing switch (PLAN experiment 8)
autoev = 27.21138505; autoaa = 0.52917726
print("\n0.5 eV/angstrom:")
print(f"  0.5 * evtoau / aatoau = {0.5/autoev/(1/autoaa):.10e} Eh/bohr")
print(f"  PLAN 3.472e-2 vs that ratio = {3.472e-2/(0.5/autoev/(1/autoaa)):.4f}")
print(f"  0.5/14.4 = {0.5/14.4:.6f}  (14.4 = {autoev/autoaa:.4f} = evtoau**-1/aatoau**-1 reciprocal abuse)")
