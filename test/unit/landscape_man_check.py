#!/usr/bin/env python3
"""`man/xtb.1.adoc` consistency check of the landscape suite options.

The repository has no rendering tool chain (asciidoctor, a2x, pandoc, groff
and man are all absent), so the man page cannot be rendered here.  This check
replaces the missing renderer with a **structural** validation and a
**coverage** gate, and it is the gate a later edit has to pass before the
documentation may drift away from the implementation again:

  coverage, forward
      every implemented suite spelling (`--l*` plus `--method`) appears as an
      **entry** of the man page, i.e. on a `*--flag*::` line with a
      description below it.  A spelling that only occurs in prose does not
      count as documented (the review of the CLI redesign found several
      "documented in passing" flags that no reader could find).

  coverage, reverse
      every `--l*` spelling that occurs **anywhere** in the man page - entry
      or prose - is implemented and documented by `--help`.  This direction
      catches a man page that promises a flag that does not exist.

  structure
      every entry has at least one indented line of text, every section title
      carries an underline of exactly its own length, every monospace span
      (backtick) and every bold span (`*`) is closed on its own line, and no
      suite flag appears in two entries.

The suite spelling sets are extracted with exactly the rules of
`landscape_help_check.py` (imported from the same directory, so the two gates
cannot drift apart).  Usage:

    landscape_man_check.py <src/prog/main.F90> <src/xhelp.f90> <man/xtb.1.adoc> [rundir]

The exit status is non-zero when a gate fails; the diagnostic lists of the
native (non-suite) spellings are printed but never gated.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import landscape_help_check as hc  # noqa: E402  (path is set up above)

#: An entry line of the man page (`*--flag* 'ARG'::`); the SYNOPSIS line
#: `*xtb* ...` is not an entry because it does not end in `::`
ENTRY = re.compile(r"^\*.*::\s*$")
#: A flag token, in an entry line or in prose
MAN_TOKEN = re.compile(r"--[a-z0-9-]+")
#: A section title underline (AsciiDoc two-line style)
UNDERLINE = re.compile(r"^[-~]{2,}$")
#: A commented-out block delimiter (`//////////////////`)
COMMENT_DELIMITER = re.compile(r"^/{4,}$")


def read(path):
    with open(path) as handle:
        return handle.read()


def man_entry_flags(text):
    """Suite spellings of the man **entries** (`*--flag*::` lines)."""
    flags = set()
    for line in text.splitlines():
        if ENTRY.match(line):
            flags.update(MAN_TOKEN.findall(line))
    return hc.suite_flags(flags)


def man_occurrence_flags(text):
    """Every suite spelling anywhere in the man page (entry or prose)."""
    return hc.suite_flags(set(MAN_TOKEN.findall(text)))


def structural_findings(text):
    """Return the structural defects of the man page.

    The commented-out block (a `////` delimiter pair) is skipped, exactly like
    a renderer would.  The known, pre-existing duplicate of the native
    `--chrg` entry (two entries with different argument shapes, `INT` and
    `INT:INT`) is reported separately: it is outside the suite namespace.
    """
    findings = []
    suite_duplicates = []
    native_duplicates = []
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
            for flag in MAN_TOKEN.findall(line):
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

    # (d) no suite flag in two entries; native duplicates stay diagnostic
    for flag, count in sorted(counts.items()):
        if count > 1:
            if hc.suite_flags({flag}):
                suite_duplicates.append((flag, count))
            else:
                native_duplicates.append((flag, count))
    for flag, count in suite_duplicates:
        findings.append(
            "suite flag {0} appears in {1} entries".format(flag, count)
        )
    return findings, native_duplicates


def main():
    if len(sys.argv) < 4:
        print(
            "usage: landscape_man_check.py main.F90 xhelp.F90 man/xtb.1.adoc "
            "[rundir]"
        )
        return 2

    main_source = read(sys.argv[1])
    help_source = read(sys.argv[2])
    man_source = read(sys.argv[3])

    implemented = hc.suite_flags(hc.implemented_flags(main_source))
    documented = hc.suite_flags(hc.documented_flags(help_source, expand_no=True))
    entries = man_entry_flags(man_source)
    occurrences = man_occurrence_flags(man_source)

    print("landscape man page consistency check")
    print("  main = " + sys.argv[1])
    print("  help = " + sys.argv[2])
    print("  man  = " + sys.argv[3])
    print(
        "extraction rules (imported from landscape_help_check.py for the two "
        "spelling sets of main/help, hardcoded here for the man page):"
    )
    print("  man entry       a `*--flag*::` entry line of the man page")
    print("  man occurrence  every suite token of the man page, entry or prose")
    print(
        "  suite flags     implemented = {0}, documented = {1}, "
        "man entries = {2}, man occurrences = {3}".format(
            len(implemented), len(documented), len(entries), len(occurrences)
        )
    )

    failed = False

    # coverage, forward: every implemented suite flag is a man entry
    missing = sorted(implemented - entries)
    print(
        "implemented suite flags without a man entry ({0}): {1}".format(
            len(missing), " ".join(missing) or "(none)"
        )
    )
    if missing:
        failed = True

    # coverage, forward (help): every documented suite flag is a man entry
    help_missing = sorted(documented - entries)
    print(
        "documented suite flags without a man entry ({0}): {1}".format(
            len(help_missing), " ".join(help_missing) or "(none)"
        )
    )
    if help_missing:
        failed = True

    # coverage, reverse: no man spelling that the parser does not implement
    extra = sorted(occurrences - implemented)
    print(
        "man suite spellings that are not implemented ({0}): {1}".format(
            len(extra), " ".join(extra) or "(none)"
        )
    )
    if extra:
        failed = True

    # structure
    findings, native_duplicates = structural_findings(man_source)
    print(
        "structural findings ({0}): {1}".format(
            len(findings), " | ".join(findings) or "(none)"
        )
    )
    if findings:
        failed = True
    print(
        "known native duplicate entries (diagnostic, not gated): {0}".format(
            " ".join("{0} x{1}".format(f, n) for f, n in native_duplicates)
            or "(none)"
        )
    )

    if failed:
        print("FAIL: the man page and the implementation disagree")
        return 1
    print("PASS: every suite option is documented as a man entry")
    print("PASS: the man page promises no option that is not implemented")
    print("PASS: the man page is structurally sound")
    return 0


if __name__ == "__main__":
    sys.exit(main())
