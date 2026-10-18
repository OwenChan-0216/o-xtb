#!/usr/bin/env python3
"""Generate the "command each case runs" index in ``examples/README.md``.

Every ``examples/**/run.sh`` is the command of record and every case README
quotes a captured log, but there is no single place that shows all the command
lines at once.  This script writes that place and is the gate that keeps it
faithful: it rewrites **only** the region between

    <!-- BEGIN GENERATED: command index -->
    <!-- END GENERATED: command index -->

in ``examples/README.md`` and copies everything outside the two markers
unchanged.  ``--check`` writes nothing and exits non-zero when the file is
stale, so a read-only checkout can run it.

The command lines are read from the ``run.sh`` files, never from the README
command blocks (those are sometimes abbreviated).  A shell redirect is part of
what the script runs, so it is kept; the ``export`` preamble is reproduced
exactly as the case READMEs present it.  The system of a case is derived from
the case READMEs - a shared ``examples/structures/<name>`` reference in the
case README, or, for a step of a chain, in the chain README; the two cases that
name their system only in prose fall back to the atom count of their
``input.xyz``.

Stdlib only.  The repository root is the grandparent of this file, or
``--root``.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

BEGIN = "<!-- BEGIN GENERATED: command index -->"
END = "<!-- END GENERATED: command index -->"

# The order the examples README presents its categories in.
CATEGORY_ORDER = ["sp", "lopt", "lscan", "hess", "ts", "vib", "irc"]

OMP_LINE = "export OMP_NUM_THREADS=1"
XTBPATH_LINE = "export XTBPATH=<repository root>"


def fail(message: str) -> None:
    sys.stderr.write("gen_command_index.py: error: %s\n" % message)
    raise SystemExit(2)


def atom_count(path: Path) -> int:
    """Number of atoms of an xmol ``.xyz`` file (first non-blank line)."""
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            return int(line.split()[0])
    fail("%s: empty xyz file" % path)


def resolve_system(case_dir: Path, readme_text: str, structures: dict) -> str:
    """The shared ``examples/structures`` system a case uses."""
    hits = sorted(name for name in structures if name in readme_text)
    if len(hits) == 1:
        return hits[0]
    if len(hits) > 1:
        fail("%s: the READMEs reference several structures (%s)" % (case_dir, ", ".join(hits)))
    input_xyz = case_dir / "input.xyz"
    if not input_xyz.is_file():
        fail(
            "%s: no structure named in the READMEs and no input.xyz for the "
            "atom-count fallback" % case_dir
        )
    count = atom_count(input_xyz)
    matches = sorted(name for name, atoms in structures.items() if atoms == count)
    if len(matches) != 1:
        fail(
            "%s: input.xyz has %d atoms, matching %d structures (%s)"
            % (case_dir, count, len(matches), ", ".join(matches) or "none")
        )
    return matches[0]


def oxtb_commands(script: Path) -> list:
    """The exact ``oxtb`` invocation(s) a ``run.sh`` runs, continuations joined."""
    text = script.read_text(encoding="utf-8")
    if "export OMP_NUM_THREADS=1" not in text or "export XTBPATH=" not in text:
        fail("%s: no OMP_NUM_THREADS / XTBPATH preamble" % script)
    joined = re.sub(r"\\\s*\n[ \t]*", " ", text)
    commands = []
    for line in joined.splitlines():
        stripped = line.strip()
        if stripped == "oxtb" or stripped.startswith("oxtb "):
            commands.append(stripped)
    if not commands:
        fail("%s: no `oxtb` invocation" % script)
    return commands


def collect(root: Path) -> tuple:
    """(standalone cases, chains), each case a dict, deterministically ordered."""
    examples = root / "examples"
    readme = examples / "README.md"
    if not readme.is_file():
        fail("%s: not found" % readme)
    structures_dir = examples / "structures"
    if not structures_dir.is_dir():
        fail("%s: not found" % structures_dir)
    structures = {
        d.name: atom_count(d / "reactant.xyz")
        for d in sorted(p for p in structures_dir.iterdir() if p.is_dir())
    }

    standalone = []
    chains = {}
    for script in sorted(examples.rglob("run.sh")):
        case_dir = script.parent
        rel = case_dir.relative_to(examples)
        parts = rel.parts
        case_readme = case_dir / "README.md"
        if not case_readme.is_file():
            fail("%s: no README.md" % case_dir)
        text = case_readme.read_text(encoding="utf-8")
        if parts[0] == "chains":
            chain_name = parts[1]
            chain_readme = examples / "chains" / chain_name / "README.md"
            if not chain_readme.is_file():
                fail("%s: no %s" % (case_dir, chain_readme))
            text += "\n" + chain_readme.read_text(encoding="utf-8")
            entry = {
                "name": parts[2],
                "rel": str(rel),
                "category": "chains",
                "chain": chain_name,
                "system": resolve_system(case_dir, text, structures),
                "commands": oxtb_commands(script),
            }
            chains.setdefault(chain_name, []).append(entry)
        else:
            entry = {
                "name": parts[1],
                "rel": str(rel),
                "category": parts[0],
                "system": resolve_system(case_dir, text, structures),
                "commands": oxtb_commands(script),
            }
            standalone.append(entry)

    standalone.sort(key=lambda e: (CATEGORY_ORDER.index(e["category"]), e["name"]))
    for steps in chains.values():
        steps.sort(key=lambda e: e["name"])
    return standalone, chains


def fence(commands: list) -> list:
    lines = ["```bash", OMP_LINE, XTBPATH_LINE]
    lines.extend(commands)
    lines.append("```")
    return lines


def build_body(root: Path) -> str:
    standalone, chains = collect(root)
    chain_dirs = sorted(chains)
    n_steps = sum(len(steps) for steps in chains.values())

    lines = [
        "<!-- Generated by `examples/tools/gen_command_index.py` from every `run.sh`; do not edit by hand. -->",
        "",
        "Every block below reproduces the `export` preamble the case READMEs show and the exact",
        "`oxtb` invocation(s) its `run.sh` runs, continuation lines joined and shell redirects kept.",
        "The index lists **%d cases** (%d standalone cases plus %d chain steps) in **%d chains**."
        % (len(standalone) + n_steps, len(standalone), n_steps, len(chain_dirs)),
        "",
    ]
    for entry in standalone:
        lines.append("### `%s`" % entry["name"])
        lines.append("")
        lines.append("category `%s` \u00b7 system `structures/%s`" % (entry["category"], entry["system"]))
        lines.append("")
        lines.extend(fence(entry["commands"]))
        lines.append("")

    lines.append("### Chains")
    lines.append("")
    lines.append(
        "The two `chains/` directories carry one structure through several tasks; every numbered"
    )
    lines.append(
        "step is a separate case folder with its own `run.sh`, listed here in the order the chain"
    )
    lines.append("runs them.")
    lines.append("")
    for chain_name in chain_dirs:
        steps = chains[chain_name]
        order = " \u2192 ".join("`%s`" % s["name"] for s in steps)
        lines.append("#### `%s`" % chain_name)
        lines.append("")
        lines.append(
            "system `structures/%s` \u00b7 step order %s" % (steps[0]["system"], order)
        )
        lines.append("")
        for step in steps:
            lines.append("**`%s`** (category `chains`)" % step["name"])
            lines.append("")
            lines.extend(fence(step["commands"]))
            lines.append("")

    while lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines)


def rewrite(readme_text: str, body: str) -> str:
    if readme_text.count(BEGIN) != 1:
        fail("%s: expected exactly one BEGIN marker, found %d" % ("examples/README.md", readme_text.count(BEGIN)))
    if readme_text.count(END) != 1:
        fail("%s: expected exactly one END marker, found %d" % ("examples/README.md", readme_text.count(END)))
    pre, rest = readme_text.split(BEGIN, 1)
    _, post = rest.split(END, 1)
    return pre + BEGIN + "\n" + body + "\n" + END + post


def main(argv) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=None, help="repository root (default: derived from this file)")
    parser.add_argument("--check", action="store_true", help="write nothing; exit 1 if the index is stale")
    args = parser.parse_args(argv)

    root = (args.root or Path(__file__).resolve().parents[2]).resolve()
    readme = root / "examples" / "README.md"
    body = build_body(root)
    old = readme.read_text(encoding="utf-8")
    new = rewrite(old, body)

    if new == old:
        if args.check:
            sys.stderr.write("gen_command_index.py: examples/README.md is up to date\n")
            return 0
        sys.stderr.write("gen_command_index.py: examples/README.md is already up to date\n")
        return 0
    if args.check:
        sys.stderr.write(
            "gen_command_index.py: examples/README.md is stale; run "
            "`python3 examples/tools/gen_command_index.py`\n"
        )
        return 1
    readme.write_text(new, encoding="utf-8")
    sys.stderr.write("gen_command_index.py: wrote examples/README.md\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
