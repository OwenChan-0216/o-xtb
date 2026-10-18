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
"""Consistency check of the two man pages against the implementation.

The repository has no AsciiDoc tool chain in the build (no asciidoctor, a2x,
pandoc or mandoc); ``man/tools/adoc2man.py`` renders the pages and
``xtb/landscape-man-render`` keeps the committed roff artifacts in step with
the sources.  This check is the **coverage** gate next to that render gate: it
is what prevents the prose from drifting away from the parser again.

``man/oxtb.1.adoc``, both directions:

  forward
      every implemented CLI spelling is either an **entry** of the man page
      (a ``*--flag*::`` line with a description below it) or is listed in the
      explicit allowlist below with a one-line reason.  A spelling that only
      occurs in prose does not count (the CLI-redesign review found several
      "documented in passing" flags no reader could find).

  forward, aliases covered
      the merged house styles are written out, so ``--copy``/``--nocopy``,
      ``--restart``/``--norestart``, ``--charge`` and ``--gfn0``/``--gfn1``/
      ``--gfn2`` are entries of their twin and need no allowlist entry.

  reverse
      every flag-shaped spelling of the man page is implemented and documented
      by ``--help``.  Long spellings are checked wherever they occur (prose
      included), short spellings only on entry lines, which keeps shell
      commands such as ``ulimit -s`` out of the check.  This direction catches
      a page that promises a flag the parser does not implement (the former
      ``--temp``/``--reactor`` entries).

  structure
      every entry has an indented line of text, every section underline has
      exactly the title's length, every monospace and bold span is closed on
      its own line, and no flag appears in two entries.

``man/xcontrol.7.adoc``:

  blocks
      every ``$block`` name the ``xcontrol`` dispatcher of
      ``src/set_module.f90`` accepts appears in the page.  The page is not
      gated at the key level: the many legacy/debug keys are covered by the
      "these keys exist and are accepted, see ``--copy``" pointer paragraph,
      so only the block names can rot unnoticed (report 163).

The option spellings of ``main.F90``/``xhelp.f90`` are extracted with exactly
the rules of ``landscape_help_check.py`` (imported from the same directory, so
the two gates cannot disagree about what a spelling is).  Usage:

    landscape_man_check.py <main.F90> <xhelp.f90> <man/oxtb.1.adoc> \\
        <man/xcontrol.7.adoc> <src/set_module.f90> [rundir]

The exit status is non-zero when a gate fails.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import landscape_help_check as hc  # noqa: E402  (path is set up above)

#: An entry line of the man page (`*--flag* 'ARG'::`); the SYNOPSIS line
#: `*oxtb* ...` is not an entry because it does not end in `::`
ENTRY = re.compile(r"^\*.*::\s*$")
#: A flag-shaped token: one or two dashes, then an identifier that starts with
#: a letter.  The letter is what separates an option from the level keywords
#: `-1`/`-2`/`-3` and from the AsciiDoc underline runs (`----`), neither of
#: which may be read as a spelling.
FLAG = re.compile(r"(?<![\w-])-{1,2}[A-Za-z][A-Za-z0-9_-]*")
#: A section title underline (AsciiDoc two-line style)
UNDERLINE = re.compile(r"^[-~^+]{2,}$")
#: A commented-out block delimiter (`//////////////////`)
COMMENT_DELIMITER = re.compile(r"^/{4,}$")
#: The `xcontrol` dispatcher: `select case(line(2:))` ... `case('name')`
BLOCK_DISPATCH_OPEN = "select case(line(2:))"
CASE_LABEL = re.compile(r"case\s*\(\s*'([a-z0-9_]+)'\s*\)")

#: Implemented spellings that are deliberately **not** man entries.  Every
#: entry carries a one-line reason; the list must stay small and explicit, so
#: a new spelling is documented rather than quietly allowed.
MAN_ALLOWLIST = {
    "--coffee": "easter egg: documented by `--help`, deliberately absent from the man page",
    "--siman": "parsed but not a registered run type (aborts in set_runtyp; removed from `--help`)",
    "--gmd": "parsed but not a registered run type (aborts in set_runtyp; removed from `--help`)",
}


def read(path):
    with open(path) as handle:
        return handle.read()


def is_option(token):
    """Whether a spelling is an option (a letter follows the dashes)."""
    return FLAG.fullmatch(token) is not None


def option_flags(tokens):
    """The option-shaped spellings of a token set."""
    return {token for token in tokens if is_option(token)}


def man_entries(text):
    """The option spellings on the entry lines (`*--flag*::`)."""
    entries = set()
    for line in text.splitlines():
        if ENTRY.match(line):
            entries.update(FLAG.findall(line))
    return entries


def man_reverse_tokens(text):
    """The flag-shaped spellings the man page must not invent.

    Long spellings (`--x`) are collected wherever they occur, prose included,
    because a phantom option can hide in a sentence.  Short spellings (`-x`)
    are collected only from the entry lines: a bare `-s` in the prose is a
    shell option (`ulimit -s`), not a program spelling.
    """
    tokens = set()
    for line in text.splitlines():
        found = FLAG.findall(line)
        if ENTRY.match(line):
            tokens.update(found)
        else:
            tokens.update(token for token in found if token.startswith("--"))
    return tokens


def xcontrol_blocks(set_module_source):
    """The `$block` names of the ``xcontrol`` dispatcher."""
    start = set_module_source.index(BLOCK_DISPATCH_OPEN)
    end = set_module_source.index("end select", start)
    return set(CASE_LABEL.findall(set_module_source[start:end]))


def xcontrol_mentions(text):
    """The `$name` tokens of the ``xcontrol`` man page."""
    return set(re.findall(r"\$([a-z0-9_]+)", text))


def structural_findings(text):
    """Return the structural defects of `man/oxtb.1.adoc`.

    The commented-out block (a `////` delimiter pair) is skipped, exactly like
    a renderer would.
    """
    findings = []
    duplicates = []
    counts = {}
    lines = text.splitlines()
    in_comment = False

    for number, line in enumerate(lines, start=1):
        stripped = line.strip()
        if COMMENT_DELIMITER.match(stripped):
            in_comment = not in_comment
            continue
        if in_comment:
            continue

        # (b) a section title is any non-indented line followed by an
        # underline; the underline has to have exactly the title's length
        if number >= 2 and UNDERLINE.match(line):
            title = lines[number - 2]
            if title.strip() and len(title) != len(line):
                findings.append(
                    "line {0}: underline of length {1} for the title {2!r} "
                    "(length {3})".format(number, len(line), title, len(title))
                )

        # (a) every entry needs at least one indented line of text
        if ENTRY.match(line):
            following = lines[number:] if number < len(lines) else []
            first = next((l for l in following if l.strip()), "")
            if not first.startswith(" "):
                findings.append(
                    "line {0}: entry without a description: {1!r}".format(
                        number, line
                    )
                )
            for flag in FLAG.findall(line):
                counts[flag] = counts.get(flag, 0) + 1

        # (c) markup has to be closed on the same line
        if line.count("`") % 2:
            findings.append(
                "line {0}: unclosed monospace span: {1!r}".format(number, line)
            )
        outside = re.sub(r"`[^`]*`", "", line)
        if outside.count("*") % 2:
            findings.append(
                "line {0}: unclosed bold span: {1!r}".format(number, line)
            )

    # (d) no flag may appear in two entries
    for flag, count in sorted(counts.items()):
        if count > 1:
            duplicates.append((flag, count))
    for flag, count in duplicates:
        findings.append("flag {0} appears in {1} entries".format(flag, count))
    return findings


def main():
    if len(sys.argv) < 6:
        print(
            "usage: landscape_man_check.py main.F90 xhelp.F90 man/oxtb.1.adoc "
            "man/xcontrol.7.adoc src/set_module.f90 [rundir]"
        )
        return 2

    main_source = read(sys.argv[1])
    help_source = read(sys.argv[2])
    man_source = read(sys.argv[3])
    xcontrol_source = read(sys.argv[4])
    set_module_source = read(sys.argv[5])

    implemented = option_flags(hc.implemented_flags(main_source))
    documented = option_flags(hc.documented_flags(help_source, expand_no=True))
    entries = man_entries(man_source)
    reverse = man_reverse_tokens(man_source)

    print("landscape man page consistency check")
    print("  main     = " + sys.argv[1])
    print("  help     = " + sys.argv[2])
    print("  man      = " + sys.argv[3])
    print("  xcontrol = " + sys.argv[4])
    print("  set      = " + sys.argv[5])
    print(
        "implementation spellings: implemented = {0} (option-shaped), "
        "documented = {1}, man entries = {2}".format(
            len(implemented), len(documented), len(entries)
        )
    )

    failed = False

    # coverage, forward: every implemented spelling is an entry or allowlisted
    allowlisted = sorted(implemented & set(MAN_ALLOWLIST))
    missing = sorted(implemented - entries - set(MAN_ALLOWLIST))
    print(
        "implemented spellings without a man entry ({0}): {1}".format(
            len(missing), " ".join(missing) or "(none)"
        )
    )
    if missing:
        failed = True
    print(
        "allowlisted, not in the man page on purpose ({0}): {1}".format(
            len(allowlisted),
            " | ".join(
                "{0} ({1})".format(f, MAN_ALLOWLIST[f]) for f in allowlisted
            )
            or "(none)",
        )
    )
    for flag, reason in MAN_ALLOWLIST.items():
        if flag not in implemented:
            print(
                "FAIL: allowlist entry {0} is not an implemented spelling "
                "({1})".format(flag, reason)
            )
            failed = True

    # coverage, reverse: no man spelling the parser does not implement
    not_implemented = sorted(reverse - implemented)
    print(
        "man spellings that are not implemented ({0}): {1}".format(
            len(not_implemented), " ".join(not_implemented) or "(none)"
        )
    )
    if not_implemented:
        failed = True
    not_documented = sorted(reverse - documented)
    print(
        "man spellings that are not documented by `--help` ({0}): {1}".format(
            len(not_documented), " ".join(not_documented) or "(none)"
        )
    )
    if not_documented:
        failed = True

    # structure
    findings = structural_findings(man_source)
    print(
        "structural findings ({0}): {1}".format(
            len(findings), " | ".join(findings) or "(none)"
        )
    )
    if findings:
        failed = True

    # xcontrol: every dispatched $block name is mentioned in the page
    blocks = xcontrol_blocks(set_module_source)
    mentions = xcontrol_mentions(xcontrol_source)
    missing_blocks = sorted(blocks - mentions)
    print(
        "xcontrol blocks: code = {0}, page mentions = {1}, missing = {2}: {3}".format(
            len(blocks),
            len(mentions),
            len(missing_blocks),
            " ".join("$" + b for b in missing_blocks) or "(none)",
        )
    )
    if missing_blocks:
        failed = True

    if failed:
        print("FAIL: the man pages and the implementation disagree")
        return 1
    print("PASS: every implemented spelling is a man entry or allowlisted")
    print("PASS: the man page promises no spelling the parser lacks")
    print("PASS: the man page is structurally sound")
    print("PASS: every xcontrol block is documented in xcontrol(7)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
