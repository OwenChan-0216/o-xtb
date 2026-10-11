# Command line

The command-line reference on this site is **generated from the program
itself**.  There is no hand-written option table: the reference is built from
the option table that `oxtb --help` prints, which lives in `src/xhelp.f90`, so
the pages are the program's own table.  An option that exists but does nothing
yet says so on its page (`--siman`, `--gmd`, `--lvib-odlr`).

Generate it after a source change:

```bash
python docs/docs-site/tools/gen_cli_reference.py
```

The generator reuses the extraction rules of the `--help` coverage gate
(`test/unit/landscape_help_check.py`), so the documented and the implemented
spelling sets are compared with one rule.  `--check` writes nothing and exits
non-zero when the files on disk differ from what the current source would
produce; the site gate (`docs/docs-site/tools/check_site.py`) and CI use it.

## How the reference is organised

The option table is grouped into 17 categories, one page each; the grouped
index is printed by `oxtb --help` and a single category by
`oxtb --help <category>` (for example `oxtb --help saddle`).  The same category
keys are the page names:

**[Open the generated reference](../cli/index.md)** - it lists every option, its
argument placeholders and its full help text, grouped by category.

To read one option on the terminal:

```bash
oxtb --help --lirc-method          # the full text of one option
oxtb --help irc                    # one whole category
oxtb --help                        # the grouped index of all 17 categories
```

!!! note "Generated pages are not committed"
    `docs/docs-site/docs/cli/` is generated output and is not tracked by git;
    the single source of truth is `src/xhelp.f90`.  Run the generator before a
    local build, exactly as the CI job does.
