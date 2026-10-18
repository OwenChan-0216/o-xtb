#!/usr/bin/env python3
"""Render the AsciiDoc man-page subset of ``man/*.adoc`` to roff (``-man``).

The repository has no AsciiDoc tool chain (no ``asciidoctor``, ``a2x``,
``pandoc`` or ``mandoc``); ``groff`` and ``man`` are present, but they cannot
read ``.adoc``.  This converter is the missing renderer for the constructs the
two manual pages actually use, so ``man`` can read a real page instead of the
source:

* the ``NAME(SECTION)`` title and its ``=`` underline,
* attribute entries and ``//`` / ``////`` comments (deliberately skipped),
* ``NAME`` / ``SYNOPSIS`` / ... section titles (``-`` underline) and the
  ``~`` sub-sections, including ``$``-prefixed instruction titles in
  ``xcontrol.7``,
* ``*term*::`` definition lists, with a same-line description, an indented
  description, or both,
* bullet (``- ``) and numbered (``. ``) lists,
* ``NOTE:`` admonitions,
* inline ``*bold*`` / ``**bold**`` / ``_italic_`` / ``'italic'`` / ```code```
  / ``~subscript~`` / ``^superscript^`` / ``+literal+`` / ``<url>``.

Any construct outside that set is a **hard error** that names the file and the
line: the converter never silently drops or mangles content.  The two inputs
are rendered to ``man/oxtb.1`` and ``man/xcontrol.7``; ``--check`` re-renders
in memory and compares with the committed artifact (the drift gate
``xtb/landscape-man-render``), so a changed source that was not re-rendered
turns the test red.

Stdlib only, deterministic: the same source always produces byte-identical
roff, and the output carries no date or absolute path.
"""

from __future__ import annotations

import argparse
import difflib
import re
import sys
from pathlib import Path

UNDERLINE_LEVEL = {"=": 0, "-": 1, "~": 2, "^": 3, "+": 4}
ADMONITIONS = ("NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION")

# Block constructs this converter does not implement.  Matching one at a
# block-start position is a hard error, never a silent drop.
UNSUPPORTED_BLOCK = (
    (re.compile(r"^\|={3,}\s*$"), "a table"),
    (re.compile(r"^={4,}\s*$"), "an example/literal block"),
    (re.compile(r"^-{4,}\s*$"), "a literal block"),
    (re.compile(r"^\.{4,}\s*$"), "a literal block"),
    (re.compile(r"^_{4,}\s*$"), "a quote block"),
    (re.compile(r"^\*{4,}\s*$"), "a sidebar block"),
    (re.compile(r"^\+{4,}\s*$"), "a passthrough block"),
    (re.compile(r"^\[[^\]]*\]\s*$"), "an attribute list / block attribute"),
    (re.compile(r"^\s*\+\s*$"), "a paragraph continuation"),
    (re.compile(r"^(include|image|video|toc|ifdef|ifndef|endif|ifeval)::"), "a directive"),
)

# Inline constructs this converter does not implement.
UNSUPPORTED_INLINE = (
    (
        re.compile(
            r"(^|[^\w])(link|image|video|xref|footnote|kbd|btn|menu|pass|stem|icon):"
        ),
        "an inline macro",
    ),
    (re.compile(r"<<[^>]*>>"), "a cross reference"),
)

TITLE_RE = re.compile(r"^([A-Za-z0-9_.+-]+)\(([0-9A-Za-z]+)\)$")
TERM_RE = re.compile(r"^(?P<term>.*?)\s*::(?P<rest>.*)$")
ATTR_RE = re.compile(r"^:(!?[A-Za-z0-9_][A-Za-z0-9_-]*):(\s|$)")
BLOCK_COMMENT_RE = re.compile(r"^/{4,}\s*$")
LINE_COMMENT_RE = re.compile(r"^//(?!/)")
AUTOLINK_RE = re.compile(r"<((?:https?|ftp)://[^>\s]+|mailto:[^>\s]+)>")


class ConvertError(Exception):
    """A construct outside the implemented subset, with its source line."""

    def __init__(self, line: int, message: str) -> None:
        super().__init__(message)
        self.line = line
        self.message = message


# --------------------------------------------------------------------------
# inline markup
# --------------------------------------------------------------------------


def escape_chunk(text: str) -> str:
    """Escape a literal fragment for a roff text line.

    Backslash is doubled, ``-`` becomes ``\\-`` (which is also what protects an
    option name at a line-break point), a non-ASCII character becomes the
    device-independent ``\\[uXXXX]`` escape (bare ``groff -Tutf8`` reads its
    input as latin1 and would otherwise print mojibake), and everything else is
    kept verbatim.
    """
    out = []
    for ch in text:
        if ch == "\\":
            out.append("\\\\")
        elif ch == "-":
            out.append("\\-")
        elif ord(ch) > 126:
            out.append("\\[u%04X]" % ord(ch))
        else:
            out.append(ch)
    return "".join(out)


def _opens(text: str, index: int) -> bool:
    """True when ``text[index]`` starts a delimited span (word boundary before)."""
    return index == 0 or not text[index - 1].isalnum()


def _find_close(text: str, start: int, delim: str) -> int:
    """Index of the closing delimiter, or -1.

    A close requires a non-space before it and no word character directly after
    it, so ``Turbomole's`` never opens a span and ``24*nat`` never closes one.
    """
    index = start
    while True:
        index = text.find(delim, index)
        if index == -1:
            return -1
        after = index + len(delim)
        if index > 0 and not text[index - 1].isspace() and (
            after >= len(text) or not text[after].isalnum()
        ):
            return index
        index += len(delim)


def render_inline(text: str, line: int) -> str:
    """Convert one run of inline AsciiDoc to roff."""
    for pattern, what in UNSUPPORTED_INLINE:
        if pattern.search(text):
            raise ConvertError(line, "the converter does not implement %s: %r" % (what, text.strip()))

    out = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch == "`":
            run = 1
            while i + run < n and text[i + run] == "`":
                run += 1
            delim = "`" * run
            close = text.find(delim, i + run)
            if close == -1:
                # A backtick run without a matching close is literal text (the
                # same rule Asciidoctor applies); `xcontrol.7.adoc:76` carries
                # such a lone backtick.
                out.append(escape_chunk(delim))
                i += run
                continue
            out.append("\\f(CR" + escape_chunk(text[i + run:close]) + "\\fP")
            i = close + run
            continue
        if text.startswith("**", i):
            close = text.find("**", i + 2)
            if close > i + 2:
                out.append("\\fB" + render_inline(text[i + 2:close], line) + "\\fP")
                i = close + 2
                continue
        if text.startswith("__", i):
            close = text.find("__", i + 2)
            if close > i + 2:
                out.append("\\fI" + render_inline(text[i + 2:close], line) + "\\fP")
                i = close + 2
                continue
        if ch == "*" and _opens(text, i) and i + 1 < n and not text[i + 1].isspace() and text[i + 1] != "*":
            close = _find_close(text, i + 1, "*")
            if close != -1 and close > i + 1:
                out.append("\\fB" + render_inline(text[i + 1:close], line) + "\\fP")
                i = close + 1
                continue
        if ch == "_" and _opens(text, i) and i + 1 < n and not text[i + 1].isspace() and text[i + 1] != "_":
            close = _find_close(text, i + 1, "_")
            if close != -1 and close > i + 1:
                out.append("\\fI" + render_inline(text[i + 1:close], line) + "\\fP")
                i = close + 1
                continue
        if ch == "'" and _opens(text, i) and i + 1 < n and not text[i + 1].isspace():
            close = _find_close(text, i + 1, "'")
            if close != -1 and close > i + 1:
                out.append("\\fI" + render_inline(text[i + 1:close], line) + "\\fP")
                i = close + 1
                continue
        if ch in "~^":
            close = text.find(ch, i + 1)
            if close > i + 1 and not text[i + 1].isspace() and not text[close - 1].isspace():
                inner = render_inline(text[i + 1:close], line)
                out.append(("\\d" + inner + "\\u") if ch == "~" else ("\\u" + inner + "\\d"))
                i = close + 1
                continue
        if ch == "+" and _opens(text, i) and i + 1 < n and not text[i + 1].isspace():
            close = text.find("+", i + 1)
            if close > i + 1:
                out.append(escape_chunk(text[i + 1:close]))
                i = close + 1
                continue
        if ch == "<":
            match = AUTOLINK_RE.match(text, i)
            if match:
                out.append("\\fI" + escape_chunk(match.group(1)) + "\\fP")
                i = match.end()
                continue
        out.append(escape_chunk(ch))
        i += 1
    return "".join(out)


def text_line(text: str, line: int) -> str:
    """Render a source text line as a roff input line.

    A leading ``.`` or ``'`` would be read as a request or a control line, so it
    is hidden behind ``\\&``; the rest is inline markup.
    """
    rendered = render_inline(text, line)
    if rendered[:1] in (".", "'"):
        rendered = "\\&" + rendered
    return rendered


# --------------------------------------------------------------------------
# block structure
# --------------------------------------------------------------------------


def _is_underline(text: str) -> bool:
    return len(text) >= 2 and text[0] in UNDERLINE_LEVEL and set(text) == {text[0]}


def _is_continuation(text: str) -> bool:
    return bool(text) and text[0] in " \t" and bool(text.strip())


class Renderer:
    def __init__(self, source: str) -> None:
        self.lines = source.split("\n")
        self.out: list[str] = []

    def error(self, line: int, message: str) -> "ConvertError":
        return ConvertError(line, message)

    # -- helpers ----------------------------------------------------------
    def _starts_block(self, index: int) -> bool:
        """True when ``self.lines[index]`` opens a new block.

        A paragraph runs until a blank line or the first line that is a
        comment, an attribute, a heading (a title followed by an underline), an
        unsupported block marker, an admonition, a definition term, a list item
        or a hard delimiter.
        """
        lines = self.lines
        n = len(lines)
        if index >= n:
            return True
        line = lines[index]
        if line.strip() == "":
            return True
        if BLOCK_COMMENT_RE.match(line) or LINE_COMMENT_RE.match(line.strip()):
            return True
        if ATTR_RE.match(line):
            return True
        if index + 1 < n and _is_underline(lines[index + 1]):
            return True
        if any(pattern.match(line) for pattern, _ in UNSUPPORTED_BLOCK):
            return True
        if re.match(r"^(%s):[ \t]" % "|".join(ADMONITIONS), line):
            return True
        if TERM_RE.match(line) or line.startswith("- ") or line.startswith(". "):
            return True
        return False

    def _paragraph(self, index: int) -> int:
        """Emit the plain paragraph starting at 0-based ``index``."""
        self.out.append(".sp")
        while index < len(self.lines) and not self._starts_block(index):
            self.out.append(text_line(self.lines[index].strip(), index + 1))
            index += 1
        return index

    def _definition(self, index: int) -> int:
        line_no = index + 1
        raw = self.lines[index]
        match = TERM_RE.match(raw)
        term = match.group("term").rstrip()
        rest = match.group("rest").strip()
        self.out.append(".sp")
        # Every term in these pages is written `*bold*::`, which already makes
        # it bold, so the term is rendered as-is (no extra \fB wrapper).
        self.out.append(render_inline(term, line_no))
        body = []
        if rest:
            body.append((rest, line_no))
        cursor = index + 1
        while cursor < len(self.lines) and _is_continuation(self.lines[cursor]):
            body.append((self.lines[cursor].strip(), cursor + 1))
            cursor += 1
        self.out.append(".RS 4")
        for text, text_line_no in body:
            self.out.append(text_line(text, text_line_no))
        self.out.append(".RE")
        return cursor

    def _list_item(self, index: int, marker: str, number: int) -> int:
        """Emit one bullet (``number`` 0) or numbered list item."""
        line_no = index + 1
        text = self.lines[index][len(marker):].strip()
        if number:
            self.out.append('.IP "%d." 4' % number)
        else:
            self.out.append(".IP \\(bu 2")
        self.out.append(text_line(text, line_no))
        cursor = index + 1
        while cursor < len(self.lines) and _is_continuation(self.lines[cursor]):
            self.out.append(text_line(self.lines[cursor].strip(), cursor + 1))
            cursor += 1
        return cursor

    def _admonition(self, index: int, label: str, first: str) -> int:
        self.out.append(".RS 4")
        self.out.append("\\fB" + label + ":\\fP " + text_line(first, index + 1))
        cursor = index + 1
        while cursor < len(self.lines) and _is_continuation(self.lines[cursor]):
            self.out.append(text_line(self.lines[cursor].strip(), cursor + 1))
            cursor += 1
        self.out.append(".RE")
        return cursor

    # -- driver -----------------------------------------------------------
    def run(self) -> list[str]:
        lines = self.lines
        n = len(lines)
        index = 0
        while index < n and lines[index].strip() == "":
            index += 1

        # document title
        if index + 1 >= n or not _is_underline(lines[index + 1]) or UNDERLINE_LEVEL[lines[index + 1][0]] != 0:
            raise self.error(index + 1, "expected the document title followed by an '=' underline")
        title = lines[index].strip()
        match = TITLE_RE.match(title)
        if not match:
            raise self.error(index + 1, "document title %r is not NAME(SECTION)" % title)
        self._title, self._section = match.group(1), match.group(2)
        index += 2

        number = 0
        while index < n:
            line = lines[index]
            line_no = index + 1
            if line.strip() == "":
                index += 1
                continue
            stripped = line.strip()
            if BLOCK_COMMENT_RE.match(line):
                index += 1
                closed = False
                while index < n:
                    if BLOCK_COMMENT_RE.match(lines[index]):
                        index += 1
                        closed = True
                        break
                    index += 1
                if not closed:
                    raise self.error(line_no, "unterminated //// comment block")
                continue
            if LINE_COMMENT_RE.match(stripped):
                index += 1
                continue
            if ATTR_RE.match(line):
                # Deliberately skipped: `:doctype: manpage` and friends carry no
                # content for the rendered page (listed in the report).
                index += 1
                continue
            if index + 1 < n and _is_underline(lines[index + 1]):
                level = UNDERLINE_LEVEL[lines[index + 1][0]]
                if level == 0:
                    raise self.error(line_no, "a second document title is not implemented")
                command = ".SH" if level == 1 else ".SS"
                self.out.append('%s "%s"' % (command, render_inline(stripped, line_no)))
                index += 2
                number = 0
                continue
            for pattern, what in UNSUPPORTED_BLOCK:
                if pattern.match(line):
                    raise self.error(line_no, "the converter does not implement %s" % what)
            match = re.match(r"^(%s):[ \t]*(.*)$" % "|".join(ADMONITIONS), line)
            if match:
                index = self._admonition(index, match.group(1), match.group(2))
                number = 0
                continue
            if TERM_RE.match(line):
                index = self._definition(index)
                number = 0
                continue
            if line.startswith("- "):
                index = self._list_item(index, "- ", 0)
                number = 0
                continue
            if line.startswith(". "):
                number += 1
                index = self._list_item(index, ". ", number)
                continue
            index = self._paragraph(index)
            number = 0
        return self.out


def convert(source: str) -> str:
    """Render one AsciiDoc man page to roff text."""
    renderer = Renderer(source)
    body = renderer.run()
    header = [
        "'\\\" t",
        '.\\"     Title: %s' % renderer._title.lower(),
        '.\\"    Manual: %s manual' % renderer._title.lower(),
        '.\\" Generator: man/tools/adoc2man.py',
        '.\\"  Language: English',
        '.\\"',
        '.TH "%s" "%s" "" "" ""' % (renderer._title.upper(), renderer._section),
        ".ie \\n(.g .ds Aq \\(aq",
        ".el       .ds Aq '",
        ".nh",
        ".ad l",
    ]
    return "\n".join(header + body) + "\n"


# --------------------------------------------------------------------------
# entry point
# --------------------------------------------------------------------------


def fail(message: str) -> "None":
    sys.stderr.write("adoc2man.py: error: %s\n" % message)
    raise SystemExit(1)


def main(argv: "list[str] | None" = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("source", help="AsciiDoc man page (man/oxtb.1.adoc)")
    parser.add_argument("output", help="rendered roff page (man/oxtb.1)")
    parser.add_argument(
        "--check",
        action="store_true",
        help="write nothing; exit 1 when the committed page is stale",
    )
    args = parser.parse_args(argv)

    source_path = Path(args.source)
    output_path = Path(args.output)
    try:
        text = source_path.read_text(encoding="utf-8")
    except OSError as exc:
        fail("cannot read %s: %s" % (source_path, exc))
    try:
        rendered = convert(text)
    except ConvertError as exc:
        fail("%s:%d: %s" % (source_path, exc.line, exc.message))

    if args.check:
        try:
            current = output_path.read_text(encoding="utf-8")
        except OSError as exc:
            fail("cannot read the committed page %s: %s (run adoc2man.py to render it)" % (output_path, exc))
        if current == rendered:
            return 0
        diff = list(
            difflib.unified_diff(
                current.splitlines(),
                rendered.splitlines(),
                fromfile="%s (committed)" % output_path,
                tofile="%s (re-rendered)" % output_path,
                lineterm="",
                n=1,
            )
        )
        summary = "\n".join(diff[:40])
        if len(diff) > 40:
            summary += "\n... (%d further diff lines)" % (len(diff) - 40)
        sys.stderr.write(
            "adoc2man.py: %s is stale against %s; re-render it with\n"
            "  python3 %s %s %s\n%s\n"
            % (output_path, source_path, Path(__file__).name, source_path, output_path, summary)
        )
        return 1

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(rendered, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
