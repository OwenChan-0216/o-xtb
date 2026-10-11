# Fortran API reference

!!! warning "Not published yet"
    This section is a **placeholder**.  The Fortran API reference is **not
    generated or published** at this time; nothing below describes existing API
    documentation.

## What it will be

The Fortran sources carry **FORD** doc comments (`!>`) - 14020 comment blocks
across 277 files, the same convention the mctc-lib project (a separate
dependency) uses and publishes as a static site.  When enabled, this section will contain the generated
module / type / procedure reference built from those comments.

## What is missing before it can be enabled

1. a FORD project file (for example `docs/docs-site/ford.md`) - none exists
   today;
2. `ford` added to `docs/docs-site/requirements.txt` (pinned);
3. a build step that runs FORD and drops its output under
   `docs/docs-site/docs/api/`;
4. a decision on the **public** module list - the comments exist for internal
   modules too, so a published API is a curation decision, not just a build
   step.

## The exact command that would enable it

```bash
pip install ford                       # or a pinned `ford` in requirements.txt
ford docs/docs-site/ford.md            # reads the `!>` comments, emits its site
# ford.md would set:  output_dir: docs/docs-site/docs/api
```

The output directory `docs/docs-site/docs/api/` is already reserved by
`.gitignore` and will hold generated files only.  The single hand-written file
in it is this entry point, `index.md`, which `.gitignore` re-includes on
purpose; nothing else there is ever hand-edited.
