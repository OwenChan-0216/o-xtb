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
"""`--help` coverage check of the command line parser.

The CLI redesign (`docs/_simplify-recon/11-cli-redesign.md` sections 8.4, 8.6
and 17.4) splits the command line spellings into two sets:

  set S  every spelling that starts with ``--l`` or is exactly ``--method``
         (the landscape suite, plus the native ``--lmo``)
  set N  every other spelling (the native xtb command line)

The **gate** of stage 1 is that set S is documented: ``S(main) == S(help)``,
i.e. the difference is empty.  Set N was only **printed** in stage 1: the audit
registered 30 implemented but undocumented and 4 documented but unimplemented
native spellings, and closing that list was stage 4 (section 8.6).  Stage 4
closed it - in **dialect A** both N differences are 0 - and this check now
**gates** them (a non-zero dialect A N difference fails).  Set S alone cannot
catch a *wrong* description either: stage 3b redeployed ``--opt``/``--ohess`` to
the suite while ``--help`` still described the native block, and the S gate
stayed green (HIGH-2 of ``52-stage3b-review.md``).  Dialect B keeps its inherent
4/2 residual (the two merged ``--[no]x`` spellings, see ``main``) and stays
print only.

Two extraction rules are implemented here.  Both are written down in the code
below and printed with the run, because the numbers of set N depend on the
rule - the redesign says so explicitly (section 8.4) and the gate of set S is
designed to be rule independent:

  dialect A  the option lines of `src/xhelp.f90` are split at commas and
             whitespace and a merged ``--[no]x`` spelling is expanded to its
             two spellings ``--x`` and ``--nox`` (the rule of the audit,
             `docs/_simplify-recon/02-cli-audit.md` section 2.1)
  dialect B  the same, but the merged ``--[no]x`` spelling is kept literally
             instead of being expanded

Usage:

    landscape_help_check.py <src/prog/main.F90> <src/xhelp.f90> [rundir]

The exit status is non-zero when a **gated** difference is non-empty: set S in
either dialect, or a dialect A N difference.  Dialect B's N counts stay
diagnostic.
"""

import re
import sys

# --- extraction rules (hardcoded, printed by `describe_rules`) -------------

#: Implemented spellings: the quoted strings of every `case (...)` label of the
#: argument parser that start with `-`.  Labels may use either quote character
#: (`case ('--efield')` and `case ("--efield")` both occur) and may list
#: several comma separated aliases.
CASE_LABEL = re.compile(r"case\s*\(([^)]*)\)")
QUOTED = re.compile(r"'([^']*)'|\"([^\"]*)\"")
#: A help text line of `src/xhelp.f90`, which is one quoted string per line.
HELP_LINE = re.compile(r'"([^"]*)"')
#: A spelling token: one or two leading dashes, then an identifier character or
#: the `[no]` merge bracket; the argument placeholders (`INT`, `REAL`, ...) and
#: the prose of the descriptions are dropped by this filter.
TOKEN = re.compile(r"^-+[A-Za-z0-9_\[]")
SPLIT = re.compile(r"[,\s]+")

RULE_CHECKS = ("main", "help")
SET_S_PREFIX = "--l"
SET_S_EXTRA = "--method"

#: Implemented spellings that are deliberately **not** documented by `--help`.
#: `--siman` and `--gmd` are parsed by `src/prog/main.F90` but are not
#: registered run types: the `set_runtyp` dispatcher has no `siman`/`gmd`
#: case, so a run aborts with that honest message instead of "Unknown
#: option".  Advertising them in the help table would promise a capability
#: this build does not have, so they stay out of it and this allowlist keeps
#: the dialect-A gate meaningful (report 163).  Every entry needs a reason.
HELP_ALLOWLIST = {
    "--siman": "parsed but not a registered run type (aborts in set_runtyp)",
    "--gmd": "parsed but not a registered run type (aborts in set_runtyp)",
}


def describe_rules():
    """Print the extraction rules that produce the counts below."""
    print("extraction rules (hardcoded in landscape_help_check.py):")
    print("  main  every quoted string of a `case (...)` label of main.F90")
    print("        that starts with `-` (both quote characters, comma")
    print("        separated aliases are separate spellings)")
    print("  help  every help text line of xhelp.f90 whose string starts")
    print("        with `-`, split at commas and whitespace")
    print("        dialect A: `--[no]x` expands to `--x` and `--nox`")
    print("        dialect B: `--[no]x` stays literal")


def quoted_strings(text):
    """Yield the content of every single or double quoted string."""
    for match in QUOTED.finditer(text):
        yield match.group(1) if match.group(1) is not None else match.group(2)


def implemented_flags(main_source):
    """Set S_N(main): the spellings of the `case (...)` labels."""
    flags = set()
    for line in main_source.splitlines():
        label = CASE_LABEL.search(line)
        if label is None:
            continue
        for token in quoted_strings(label.group(1)):
            token = token.strip()
            if token.startswith("-"):
                flags.add(token)
    return flags


def documented_flags(help_source, expand_no):
    """Set S_N(help): the spellings of the option lines of `xhelp.f90`."""
    flags = set()
    for match in HELP_LINE.finditer(help_source):
        line = match.group(1)
        if not line.startswith("-"):
            continue
        for token in SPLIT.split(line.strip()):
            if not TOKEN.match(token):
                continue
            if "[no]" in token and expand_no:
                flags.add(token.replace("[no]", ""))
                flags.add(token.replace("[no]", "no"))
            else:
                flags.add(token)
    return flags


def suite_flags(flags):
    """Set S: the suite spellings (`--l*` plus `--method`)."""
    return {
        flag
        for flag in flags
        if flag.startswith(SET_S_PREFIX) or flag == SET_S_EXTRA
    }


def report(name, main_source, help_source, expand_no):
    """Print the counts of one dialect and return the three differences."""
    main = implemented_flags(main_source)
    help_ = documented_flags(help_source, expand_no)
    s_main = suite_flags(main)
    s_help = suite_flags(help_)
    s_difference = sorted(s_main ^ s_help)
    implemented_undocumented = sorted(main - help_)
    documented_unimplemented = sorted(help_ - main)

    print(
        "dialect {0}: S(main) = {1}, S(help) = {2}, difference = {3}".format(
            name, len(s_main), len(s_help), len(s_difference)
        )
    )
    print("dialect {0}: S: {1} differences".format(name, len(s_difference)))
    print(
        "dialect {0}: N(implemented, undocumented) = {1}".format(
            name, len(implemented_undocumented)
        )
    )
    print(
        "dialect {0}: N(documented, unimplemented) = {1}".format(
            name, len(documented_unimplemented)
        )
    )
    print(
        "dialect {0}: implemented, undocumented: {1}".format(
            name, " ".join(implemented_undocumented) or "(none)"
        )
    )
    print(
        "dialect {0}: documented, unimplemented: {1}".format(
            name, " ".join(documented_unimplemented) or "(none)"
        )
    )
    return s_difference, implemented_undocumented, documented_unimplemented


def main():
    if len(sys.argv) < 3:
        print("usage: landscape_help_check.py main.F90 xhelp.F90 [rundir]")
        return 2
    with open(sys.argv[1]) as handle:
        main_source = handle.read()
    with open(sys.argv[2]) as handle:
        help_source = handle.read()

    print("landscape help coverage check")
    print("  main = " + sys.argv[1])
    print("  help = " + sys.argv[2])
    describe_rules()

    # The gate of dialect A is now the **whole** documented/implemented
    # relation, not only set S.  Set S (`--l*` and `--method`) says that every
    # suite spelling has a help entry; it says nothing about the *native*
    # spellings, and that hole was used by real defects: stage 3b deployed
    # `--opt`/`--ohess` to the suite while the help still described the old
    # native block, and the S gate stayed green (HIGH-2 of
    # `52-stage3b-review.md`).  Dialect A is the rule of the audit
    # (`docs/_simplify-recon/02-cli-audit.md` section 2.1) and it reached
    # N = 0/0 in stage 4, so both of its differences are hard gates: an
    # implemented but undocumented flag, and a documented but unimplemented
    # one, fail the check.
    #
    # Dialect B stays **print only**.  Its numbers are an artefact of the
    # extraction rule and not a defect of the parser: without the `--[no]x`
    # expansion it sees the two merged help spellings `--[no]copy` and
    # `--[no]restart` as "documented but unimplemented" while the four real
    # `case` labels `--copy`, `--nocopy`, `--restart`, `--norestart` stay
    # "implemented but undocumented", which is the registered, inherent 4/2
    # residual of that dialect.  Gating it would demand help entries for
    # spellings that are merged on purpose.
    failed = []
    for name, expand_no in (("A", True), ("B", False)):
        s_difference, implemented_undocumented, documented_unimplemented = report(
            name, main_source, help_source, expand_no
        )
        if s_difference:
            failed.append((name, s_difference))
        if name == "A":
            allowed = [
                flag
                for flag in implemented_undocumented
                if flag in HELP_ALLOWLIST
            ]
            if allowed:
                print(
                    "dialect A: allowlisted, not documented on purpose: {0}".format(
                        " ".join(
                            "{0} ({1})".format(f, HELP_ALLOWLIST[f])
                            for f in allowed
                        )
                    )
                )
            gated = [
                flag
                for flag in implemented_undocumented
                if flag not in HELP_ALLOWLIST
            ]
            if gated:
                failed.append((name, gated))
            if documented_unimplemented:
                failed.append((name, documented_unimplemented))

    if failed:
        for name, difference in failed:
            print(
                "FAIL: dialect {0} documents no help for: {1}".format(
                    name, " ".join(difference)
                )
            )
        return 1
    print("PASS: set S is documented by `--help` in both dialects")
    print("PASS: dialect A has no implemented/undocumented difference")
    return 0


if __name__ == "__main__":
    sys.exit(main())
