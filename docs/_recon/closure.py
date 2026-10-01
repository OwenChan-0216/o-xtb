#!/usr/bin/env python3
"""
closure.py - static Fortran module-closure analysis for the xtb repository.

Builds:
   provider(module) -> file
   file -> set of modules it provides
   file -> set of modules it uses

Seeds come from:
  * the files listed in ${prog} (src/prog/*)  -- the CLI
  * the files under src/main/
Then the transitive closure over `use <module>` is computed.

Usage:
  python3 closure.py            # full report, seeded from prog + main
  python3 closure.py --only-main  # seeded only from src/prog/main.F90
"""
import os
import re
import sys
from collections import defaultdict, deque

ROOT = os.path.dirname(os.path.abspath(__file__))
while not os.path.exists(os.path.join(ROOT, "src", "prog")) and ROOT != "/":
    ROOT = os.path.dirname(ROOT)

SEARCH_DIRS = ["src", "symmetry"]
FORTRAN_EXT = {".f90", ".f", ".f77", ".f95", ".f03", ".f08", ".fpp"}

# modules we consider "intrinsic" / compiler provided
INTRINSIC = {
    "iso_fortran_env", "iso_c_binding", "ieee_arithmetic", "ieee_exceptions",
    "ieee_features", "omp_lib", "openacc", "ifport", "ifcore", "mkl",
    "iso_varying_string", "ieee_arith", "ieee_support",
}

# ---------------------------------------------------------------------------
# Fortran source discovery
# ---------------------------------------------------------------------------
def fortran_files():
    out = []
    for d in SEARCH_DIRS:
        for dirpath, _dirs, files in os.walk(os.path.join(ROOT, d)):
            for f in files:
                ext = os.path.splitext(f)[1].lower()
                if ext in FORTRAN_EXT:
                    out.append(os.path.relpath(os.path.join(dirpath, f), ROOT))
    return sorted(out)


MOD_RE = re.compile(r"^\s*module\s+([a-zA-Z]\w*)\s*(?:!.*)?$", re.IGNORECASE)
SUBMOD_RE = re.compile(
    r"^\s*submodule\s*\(\s*([a-zA-Z]\w*)\s*\)\s*([a-zA-Z]\w*)?", re.IGNORECASE)
USE_RE = re.compile(
    r"^\s*use\s*(?:,\s*intrinsic\s*)?(?:::)?\s*([a-zA-Z]\w*)", re.IGNORECASE)


def parse(path):
    """Return (provides, uses) as lists of lower-case names."""
    provides, uses = [], []
    try:
        with open(path, "r", errors="replace") as fh:
            for line in fh:
                # strip inline comments (! outside quotes -- good enough here)
                code = line.split("!")[0]
                if not code.strip():
                    continue
                m = SUBMOD_RE.match(code)
                if m:
                    if m.group(2):
                        provides.append(m.group(2).lower())  # submodule name
                    continue
                m = MOD_RE.match(code)
                if m:
                    name = m.group(1).lower()
                    if name not in ("procedure", "subroutine", "function"):
                        provides.append(name)
                    continue
                m = USE_RE.match(code)
                if m:
                    uses.append(m.group(1).lower())
    except OSError:
        pass
    return provides, uses


def prog_files():
    """Parse src/prog/CMakeLists.txt for the ${prog} list."""
    files = []
    cm = os.path.join(ROOT, "src", "prog", "CMakeLists.txt")
    with open(cm) as fh:
        for line in fh:
            m = re.search(r'"\$\{dir\}/([^"]+)"', line)
            if m:
                files.append(os.path.join("src", "prog", m.group(1)))
    return files


def main_files():
    files = []
    cm = os.path.join(ROOT, "src", "main", "CMakeLists.txt")
    with open(cm) as fh:
        for line in fh:
            m = re.search(r'"\$\{dir\}/([^"]+)"', line)
            if m:
                files.append(os.path.join("src", "main", m.group(1)))
    return files


def build():
    all_files = fortran_files()
    provider = {}          # module -> file
    provides = {}          # file -> [modules]
    uses = {}              # file -> [modules]
    for f in all_files:
        p, u = parse(os.path.join(ROOT, f))
        provides[f] = p
        uses[f] = u
        for m in p:
            provider.setdefault(m, f)
    return all_files, provider, provides, uses


def closure(seeds, all_files, provider, uses):
    needed = set()
    queue = deque()
    # A seed file needs itself plus every module it uses.
    for s in seeds:
        if s not in uses:
            continue
        needed.add(s)
        queue.append(s)
    external = defaultdict(set)   # module -> set(files that use it)
    while queue:
        f = queue.popleft()
        for m in uses.get(f, []):
            if m in INTRINSIC:
                continue
            if m in provider:
                pf = provider[m]
                if pf not in needed:
                    needed.add(pf)
                    queue.append(pf)
            else:
                external[m].add(f)
    return needed, external


def report(title, seeds, all_files, provider, provides, uses):
    needed, external = closure(seeds, all_files, provider, uses)
    lines = []
    lines.append("=" * 72)
    lines.append(title)
    lines.append("=" * 72)
    lines.append(f"total fortran files in repo (src/+symmetry/): {len(all_files)}")
    lines.append(f"seed files: {len(seeds)}")
    lines.append(f"files in transitive closure: {len(needed)}")
    lines.append(f"files excluded by closure: {len(all_files) - len(needed)}")
    lines.append("")

    # excluded grouped by top-level directory (relative to src/)
    excl = [f for f in all_files if f not in needed]
    groups = defaultdict(list)
    for f in excl:
        parts = f.split(os.sep)
        key = os.sep.join(parts[:2]) if len(parts) > 2 else parts[0]
        groups[key].append(f)
    lines.append("EXCLUDED FILES grouped by directory:")
    for k in sorted(groups):
        lines.append(f"  [{k}]  ({len(groups[k])} files)")
        for f in sorted(groups[k]):
            lines.append(f"      {f}")
    lines.append("")

    # external modules referenced by the closure, with referencing-file counts
    ext_count = {}
    for m, fs in external.items():
        ext_count[m] = fs
    lines.append(f"EXTERNAL (non-in-tree) modules referenced by closure: {len(ext_count)}")
    for m in sorted(ext_count):
        lines.append(f"  {m}  <- {len(ext_count[m])} file(s) in closure")
    lines.append("")

    # in-tree modules provided by excluded files (what we lose)
    gaps = defaultdict(list)
    for f in excl:
        for m in provides.get(f, []):
            gaps[m].append(f)
    lines.append(f"MODULES PROVIDED ONLY BY EXCLUDED FILES: {len(gaps)}")
    for m in sorted(gaps):
        lines.append(f"  {m}  ({os.path.basename(gaps[m][0])})")
    lines.append("")
    return "\n".join(lines), needed, external


def module_report(all_files, provider, uses):
    """Group files by external module family and count in-tree referrers."""
    extfam = defaultdict(set)
    for f in all_files:
        for m in uses.get(f, []):
            if m in INTRINSIC or m in provider:
                continue
            for fam in ("mctc_env", "mctc_io", "mctc_data", "tblite", "dftd4",
                        "mstore", "multicharge", "cpx"):
                if m == fam or m.startswith(fam + "_"):
                    extfam[fam].add((f, m))
    lines = ["=" * 72, "EXTERNAL MODULE FAMILIES AND IN-TREE REFERRERS", "=" * 72]
    for fam in sorted(extfam):
        mods = sorted({m for _f, m in extfam[fam]})
        files = sorted({f for f, _m in extfam[fam]})
        lines.append(f"{fam}: {len(files)} files, modules: {', '.join(mods)}")
        for f in files:
            lines.append(f"    {f}")
    lines.append("")
    return "\n".join(lines)


if __name__ == "__main__":
    all_files, provider, provides, uses = build()
    prog = [f for f in prog_files() if f in uses]
    mainf = [f for f in main_files() if f in uses]

    out = []
    if "--only-main" in sys.argv:
        seeds = ["src/prog/main.F90"]
        txt, _n, _e = report("CLOSURE SEEDED ONLY FROM src/prog/main.F90",
                             seeds, all_files, provider, provides, uses)
        out.append(txt)
    else:
        seeds = sorted(set(prog) | set(mainf))
        txt, _n, _e = report("CLOSURE SEEDED FROM src/prog/* + src/main/*",
                             seeds, all_files, provider, provides, uses)
        out.append(txt)
        out.append(module_report(all_files, provider, uses))
    print("\n".join(out))
