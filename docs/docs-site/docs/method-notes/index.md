# Method notes

This chapter explains how selected mechanisms of the task suite work, at the
level of detail a user needs to trust a number.  It is **not** a reproduction
of the project's internal engineering records.

## Policy

* A **report number** may appear only on the pages of this chapter.
* A report number is **plain text, never a link**.  The internal records are
  not part of this site, so a link to one would be a broken link - and the
  site's `--strict` build rejects broken links, which enforces the policy for
  free.
* **Each page restates every number it uses.**  A reader never needs the
  report; the report id is a provenance tag ("where this measurement was made,
  quote it in a bug report"), not a bibliography entry.
* A number is quoted only when it belongs to a quantitative claim a maintainer
  could re-check by re-running the named experiment.

## Pages

* [The IRC line search](irc-line-search.md) - the `gs` corrector on the
  constraint sphere.

!!! note "Why a separate chapter"
    The user guide and the reference describe what the program does.  This
    chapter describes why a particular numerical choice was made, and records
    the measurement that justified it, in a form that stands alone.
