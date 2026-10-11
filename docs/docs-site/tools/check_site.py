#!/usr/bin/env python3
#
# This file is part of xtb.
#
# Copyright (C) 2026 xtb contributors
#
# xtb is free software: you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# xtb is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with xtb.  If not, see <https://www.gnu.org/licenses/>.
"""Local gate for the o-xtb documentation site.

This is the **dependency-free** equivalent of ``mkdocs build --strict``: it
needs neither MkDocs nor a network, so a CTest target can run it.  It is the
local half of the site's two gates; ``mkdocs build --strict`` (with
``validation.anchors: warn``) is the other, run in CI.

Checks:

  a. every navigation entry of ``mkdocs.yml`` maps to a file that exists (the
     generated command-line chapters included), and every generated chapter
     page is reachable through the navigation;
  b. ``tools/gen_cli_reference.py --check`` is clean - the generated pages
     match ``src/xhelp.f90``;
  c. every internal Markdown link between the site's own pages resolves;
  d. the key lists on ``reference/ljson.md`` equal the enforced oracle of
     ``test/unit/landscape_e2e_check.py``;
  e. no report number appears as a link anywhere, and a report-number
     reference appears only on the ``method-notes`` pages (plain text).

Usage::

    check_site.py [--no-generate]

By default the CLI reference is regenerated first (exactly the step CI runs
before the build), so the target is self-contained.  ``--no-generate`` skips
that step and requires the generated files to be present and current, which is
the stricter form the CI job uses after its own generator step.

The exit status is non-zero when any check fails; every failure names the file
and, where it applies, the line.
"""

import argparse
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
REPO_ROOT = HERE.parents[3]
SITE_DIR = REPO_ROOT / "docs" / "docs-site"
MKDOCS = SITE_DIR / "mkdocs.yml"
DOCS_DIR = SITE_DIR / "docs"
CLI_DIR = DOCS_DIR / "cli"

sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(REPO_ROOT / "test" / "unit"))
import gen_cli_reference  # noqa: E402
import landscape_e2e_check  # noqa: E402

#: `[text](target)` and `[text](<target>)`: the inline Markdown link forms used
#: on the site.  Reference-style links are not used, so they are not parsed.
LINK = re.compile(r"\[([^\]]*)\]\(<?([^)>\s]+)>?\)")
#: A markdown link target that reaches into the internal records, or that names
#: a report file directly.  Neither may appear on the site.
REPORT_TARGET = re.compile(r"(?:^|/)docs/_[a-z-]*recon/|(?:^|/)\d{2,3}-[a-z]")
#: A report-number citation, e.g. `report 44`.
REPORT_CITATION = re.compile(r"(?i)\breport\s+\d+")
#: A `.md` navigation value.
MD_REF = re.compile(r"([A-Za-z0-9_./-]+\.md)\b")

#: The gate-marker comments in `reference/ljson.md` and the oracle each one is
#: checked against.
KEY_MARKERS = {
    "core-keys": "CORE_KEYS",
    "geometry-keys": "GEOMETRY_KEYS",
    "provenance-keys": "PROVENANCE_KEYS",
}


def fail(problems, where, message):
    problems.append("%s: %s" % (where, message))


def parse_nav(text):
    """The nav block of `mkdocs.yml` as `{line number: path}` pairs.

    Hand-parsed on purpose: the gate must not depend on PyYAML.  The nav block
    starts at the top-level key `nav:` and ends at the next top-level key (a
    non-empty line with no indentation).
    """
    entries = {}
    in_nav = False
    for lineno, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not in_nav:
            if stripped == "nav:":
                in_nav = True
            continue
        if line and not line[0].isspace():
            break  # next top-level key
        if stripped.startswith("#"):
            continue
        for match in MD_REF.finditer(line):
            entries[lineno] = match.group(1)
    return entries


def check_nav(problems):
    text = MKDOCS.read_text()
    nav = parse_nav(text)
    if not nav:
        fail(problems, "mkdocs.yml", "no navigation entries found")
        return
    nav_paths = set()
    for lineno, target in sorted(nav.items()):
        nav_paths.add(target)
        if not (DOCS_DIR / target).is_file():
            fail(problems, "mkdocs.yml:%d" % lineno,
                 "navigation entry '%s' has no file" % target)

    # every generated chapter page must be reachable from the navigation
    nav_cli = CLI_DIR / "nav-cli.yml"
    generated = []
    if nav_cli.is_file():
        generated = MD_REF.findall(nav_cli.read_text())
        for target in generated:
            path = "cli/" + target
            if path not in nav_paths:
                fail(problems, "mkdocs.yml",
                     "generated page '%s' is not in the navigation" % path)
    print("nav: %d entries, %d generated chapters checked" % (len(nav), len(generated)))


def check_generator(problems):
    status = gen_cli_reference.main(["--check"])
    if status != 0:
        fail(problems, "docs/docs-site/docs/cli",
             "gen_cli_reference.py --check reported drift")


def check_links(problems):
    checked = 0
    for page in sorted(DOCS_DIR.rglob("*.md")):
        text = page.read_text()
        for lineno, line in enumerate(text.splitlines(), start=1):
            for _label, target in LINK.findall(line):
                if target.startswith(("http://", "https://", "mailto:")):
                    continue
                if target.startswith("#"):
                    continue
                path_part = target.split("#", 1)[0]
                if not path_part:
                    continue
                resolved = (page.parent / path_part).resolve()
                checked += 1
                if not resolved.is_file():
                    rel = page.relative_to(DOCS_DIR)
                    fail(problems, "%s:%d" % (rel, lineno),
                         "link '%s' does not resolve" % target)
    print("links: %d internal links checked" % checked)


def check_key_lists(problems):
    page = DOCS_DIR / "reference" / "ljson.md"
    text = page.read_text()
    lines = text.splitlines()
    for marker, constant in KEY_MARKERS.items():
        expected = list(getattr(landscape_e2e_check, constant))
        found = extract_fenced_block(lines, marker)
        if found != expected:
            fail(problems, "reference/ljson.md",
                 "the '%s' list %r does not equal %s %r"
                 % (marker, found, constant, expected))
    print("json: %d key lists checked against landscape_e2e_check.py"
          % len(KEY_MARKERS))


def extract_fenced_block(lines, marker):
    """The lines of the first fenced block after `<!-- gate:marker -->`."""
    want = "<!-- gate:%s -->" % marker
    start = None
    for index, line in enumerate(lines):
        if line.strip() == want:
            start = index
            break
    if start is None:
        return None
    fence = None
    body = []
    for line in lines[start + 1:]:
        if fence is None:
            if line.startswith("```"):
                fence = line
            continue
        if line.startswith("```"):
            return body
        body.append(line)
    return None


def check_report_policy(problems):
    pages = sorted(DOCS_DIR.rglob("*.md"))
    for page in pages:
        rel = page.relative_to(DOCS_DIR)
        in_notes = rel.parts and rel.parts[0] == "method-notes"
        for lineno, line in enumerate(page.read_text().splitlines(), start=1):
            for label, target in LINK.findall(line):
                if REPORT_TARGET.search(target) or REPORT_CITATION.search(label):
                    fail(problems, "%s:%d" % (rel, lineno),
                         "report reference as a link: [%s](%s)" % (label, target))
            if not in_notes and REPORT_CITATION.search(line):
                fail(problems, "%s:%d" % (rel, lineno),
                     "report number outside method-notes")
    print("policy: %d pages checked for report links" % len(pages))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--no-generate",
        action="store_true",
        help="do not regenerate the CLI reference; require it to be current",
    )
    args = parser.parse_args(argv)

    problems = []
    if not args.no_generate:
        # Regenerate only when the generated chapters are absent.  With them
        # present the `--check` below already proves they are current, and not
        # writing into the source tree means a read-only checkout still passes.
        if not (CLI_DIR / "nav-cli.yml").is_file():
            print("generating the CLI reference (tools/gen_cli_reference.py)")
            status = gen_cli_reference.main([])
            if status != 0:
                fail(problems, "docs/docs-site/docs/cli",
                     "gen_cli_reference.py failed its own count check")

    check_nav(problems)
    check_generator(problems)
    check_links(problems)
    check_key_lists(problems)
    check_report_policy(problems)

    if problems:
        for problem in problems:
            print("FAIL: " + problem)
        print("site check failed with %d problem(s)" % len(problems))
        return 1
    print("site check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
