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
"""Consistency check of the `--help-values` legal value sets.

The option table of ``src/xhelp.f90`` declares a **legal value set** for every
option that constrains its argument, ``--help <OPTION>`` prints it as a uniform
``Values: ...`` line and ``--help-values`` dumps the whole table as the stable,
line oriented contract a shell completion generator codes against.  A declared
value the program does not actually accept would corrupt such a completion lane
silently, so this gate checks the declaration against the **built binary** and
not against another copy of the table.

Three checks, all against the executable:

  dump
      ``--help-values`` parses as the documented format 1: every record has
      three TAB separated fields, the ``# options: N with values: M`` header
      counts match, and no value token contains whitespace.

  topic page
      for every option of the dump that has a value set, ``--help <OPTION>``
      resolves and prints a ``Values:`` line with the same set.  The two
      surfaces cannot disagree.

  acceptance
      for every option whose flag rejects a bogus value (the parser reports a
      ``prog_main_parseArguments`` error, or a solvent that is not
      parametrized), every declared value has to be accepted by the real
      binary: only a value the parser does **not** know may produce the
      rejection marker.  This is the falsifiable half - a wrong declared value
      turns the gate red.

An option whose flag does not reject anything is a failure: every option that
declares a value set has to reject the sentinel, so the set is falsifiable.

Usage:

    landscape_values_check.py <oxtb> [rundir]

Exit status is non-zero when the dump is malformed, a ``Values:`` line
disagrees, a declared value is rejected by the binary, or a flag does not
reject the sentinel at all.
"""

import re
import subprocess
import sys
from pathlib import Path

#: The parser labels every command line rejection with this source, so a bogus
#: value surfaces here before any geometry is read.
PARSE_SOURCE = "prog_main_parseArguments"
#: A value no option accepts; the sentinel probe proves the flag validates.
SENTINEL = "zzqq"
#: The solver rejection of an unknown solvent (the only oracle that needs a
#: geometry, see `PROBE_EXTRA`).
SOLVENT_REJECT = "is not parametrized"

SPLIT = re.compile(r"[,\s]+")
VALUES_LINE = re.compile(r"^Values: (.*)$", re.M)

#: The saddle and IRC method names of `--method`; every other name is a
#: minimisation or native engine name and is accepted by `--opt`.
SADDLE = {"prfo", "bprfo", "dimer", "neb", "cineb", "autoneb", "string", "gsm"}
IRC = {"gs", "hpc", "lqa", "eulerpc"}

#: Options whose rejection needs a real geometry before the value is used.
#: `--gbsa`/`--alpb` read the solvent only inside a single point run.
PROBE_EXTRA = {
    "--gbsa": (["--sp"], SOLVENT_REJECT),
    "--alpb": (["--sp"], SOLVENT_REJECT),
}

#: A water geometry for the `PROBE_EXTRA` options (bohr, GFN2 is fast).
WATER = (
    "3\nwater\n"
    "O  0.0000000  0.0000000  0.0000000\n"
    "H  0.0000000  0.0000000  1.8000000\n"
    "H  1.7000000  0.0000000 -0.5000000\n"
)


def run(binary, args, rundir):
    """Run the binary, return (exit status, stdout, stdout+stderr).

    The `--help-values` dump is read from stdout alone (the termination
    message goes to stderr); the rejection probes read the merge, because the
    parser reports on either stream.
    """
    proc = subprocess.run(
        [binary, *args],
        cwd=rundir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=300,
    )
    return proc.returncode, proc.stdout, proc.stdout + proc.stderr


def parse_dump(text):
    """The `--help-values` records as (category, spellings, values)."""
    records = []
    header = None
    for line in text.splitlines():
        if not line:
            continue
        if line.startswith("#"):
            if line.startswith("# options: "):
                header = line
            continue
        fields = line.split("\t")
        if len(fields) != 3:
            raise AssertionError("malformed --help-values line: %r" % line)
        category, spellings, values = fields
        records.append((category, spellings, values.split()))
    return records, header


def primary_flag(spellings):
    """The long spelling of a record, or its first spelling."""
    tokens = [t for t in SPLIT.split(spellings.strip()) if t.startswith("-")]
    for token in tokens:
        if token.startswith("--"):
            return token
    return tokens[0] if tokens else None


def probe_argv(flag, value, geometry):
    """The argument vector that makes `flag` consume `value`."""
    if flag in PROBE_EXTRA:
        extra, _ = PROBE_EXTRA[flag]
        return [geometry, *extra, flag, value]
    if flag == "--method":
        # `--method` only validates once a landscape run type is selected.
        if value in SADDLE:
            return ["--lts", "--method", value]
        if value in IRC:
            return ["--lirc", "--method", value]
        return ["--opt", "--method", value]
    return [flag, value]


def reject_marker(flag):
    """The stderr text that marks a rejected value for `flag`."""
    return PROBE_EXTRA[flag][1] if flag in PROBE_EXTRA else PARSE_SOURCE


def error_line(text, marker):
    for line in text.splitlines():
        if marker in line:
            return line.strip()
    return marker


def main(argv):
    if len(argv) not in (2, 3):
        print("usage: landscape_values_check.py <oxtb> [rundir]")
        return 2
    binary = argv[1]
    rundir = Path(argv[2]) if len(argv) == 3 else Path.cwd()
    rundir.mkdir(parents=True, exist_ok=True)
    geometry = str(rundir / "water.xyz")
    (rundir / "water.xyz").write_text(WATER)

    print("landscape --help-values check")
    print("  oxtb   = %s" % binary)
    print("  rundir = %s" % rundir)

    status, out, _ = run(binary, ["--help-values"], rundir)
    if status != 0:
        print("FAIL: --help-values exited %d\n%s" % (status, out))
        return 1
    dump = out
    if "# oxtb --help-values format 1" not in dump:
        print("FAIL: --help-values does not open with the format 1 header")
        return 1

    records, header = parse_dump(dump)
    valued = [r for r in records if r[2]]
    print("dump: %d options, %d with a value set" % (len(records), len(valued)))
    if header is None:
        print("FAIL: --help-values carries no '# options:' header")
        return 1
    expected_header = "# options: %d with values: %d" % (len(records), len(valued))
    if header != expected_header:
        print("FAIL: header %r, expected %r" % (header, expected_header))
        return 1
    print("PASS: %s" % header)

    failures = []
    checked = 0
    accepted_values = 0

    # 1. every valued option resolves as a `--help` topic and prints the same set
    for _, spellings, values in valued:
        flag = primary_flag(spellings)
        if flag is None:
            failures.append("%s: no spelling to probe" % spellings)
            continue
        status, out, _ = run(binary, ["--help", flag], rundir)
        match = VALUES_LINE.search(out)
        if status != 0 or match is None:
            failures.append("%s: `--help %s` prints no Values: line" % (flag, flag))
            continue
        topic_values = [t.strip() for t in match.group(1).split(",")]
        if topic_values != values:
            failures.append(
                "%s: --help %r != --help-values %r" % (flag, topic_values, values)
            )
    print("topic: %d value sets compared between --help and --help-values" %
          len(valued))

    # 2. the declared value of every flag with a rejection oracle is accepted
    for _, spellings, values in valued:
        flag = primary_flag(spellings)
        if flag is None:
            continue
        marker = reject_marker(flag)
        _, _, out = run(binary, probe_argv(flag, SENTINEL, geometry), rundir)
        if marker not in out:
            failures.append(
                "%s: the flag does not reject the sentinel %r, so the value "
                "set cannot be verified" % (flag, SENTINEL)
            )
            continue
        checked += 1
        for value in values:
            _, _, out = run(binary, probe_argv(flag, value, geometry), rundir)
            if marker in out:
                failures.append(
                    "%s: declared value %r is rejected: %s"
                    % (flag, value, error_line(out, marker))
                )
            else:
                accepted_values += 1

    print("acceptance: %d validating flags probed, %d declared values accepted" %
          (checked, accepted_values))

    if failures:
        for failure in failures:
            print("FAIL: %s" % failure)
        return 1
    print("PASS: every declared value of a validating flag is accepted")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
