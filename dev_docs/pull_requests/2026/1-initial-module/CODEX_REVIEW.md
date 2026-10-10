# PR #1 — Follow-up review after Claude

Reviewer: Codex. Reviewed merge `05d097e` and Claude's local fix `de7cd90`.
Date: 2026-10-10.

## Scope

Checked Claude's two fixes and two deferred notes, then traced their callers
through file checks, the sources view, previews, override creation, saves,
layout selection and test sending. Read the relevant renderer implementations
in the installed dependencies to establish which lookups actually read and
cache files. This is a focused follow-up, not a complete line-by-line review
of the initial module or its dependencies.

Used the `pr-review-release` workflow and the repository's conventions. Its
referenced `elixir:*` thinking skills are not installed in this environment;
the review used source inspection and executable regressions directly.

## Findings and fixes

### BUG - HIGH — The sources view bypasses the file checks

`Sources.of/4` called `Content.resolve_with_sources/5` directly. That call
renders the email and its chrome through `Overrides.locate/4`, which follows
links and caches their contents. Opening a module email could therefore read
and cache a linked file even though the editor's separate preview refused it.

Fixed: check the email before resolution and check its chrome before core
renders it. The defaults wrapper preserves core's lazy evaluation in the
recipient's locale, including not evaluating defaults when a database row
wins. It checks groups supplied by the entry, `layout.txt` or a defaults
callback. Regression tests verify refusal and that a subsequent safe file is
read without a stale cache entry.

### BUG - HIGH — Test sending checks the wrong layout for module emails

`Editor.preview_names/2` took the layout from a file template or the host's
default group. It ignored a catalogue entry's explicit `layout`. With host
group `shop` and module group `billing`, a linked billing footer escaped the
checks before the test-send callback.

Fixed: an explicit module group takes precedence, matching core's resolution.
A LiveView regression proves the callback is not called when that group's
chrome contains a link.

### BUG - MEDIUM — Oversized files are checked after the renderer reads them

`Files.check_template/2` checked file types but not sizes. The default preview
then called `Templates.sources/3` before checking its resulting file paths;
the renderer had already read and cached oversized contents. Host previews
and test sends relied on the same incomplete directory check.

Fixed: inspect each visible regular file's size in `check_template/2`, return
`{:error, {:too_large, path}}`, and reuse the existing translated refusal.
Tests cover the directory check, source resolution and the default preview's
absence of cache entries. The oversized-copy assertion now expects the
earlier error to name the offending file.

### BUG - MEDIUM — The realpath fix still normalizes the input too early

Claude correctly changed how link targets handle `..`, but `realpath/1` still
started with `Path.expand/1`. For input `root/link/..`, with the link leading
to `outside/sub`, it returned `root` instead of `outside`. Missing components
could disappear the same way. Traversing a regular file with `..`, `.` or a
trailing slash also incorrectly succeeded, and a forty-first link targeting
`/` escaped the link limit because the empty-components clause came first.

Fixed: use `Path.absname/1` without removing dot components, preserve trailing
directory requirements, require intermediate components to be directories,
and enforce the link limit before returning success. Tests cover absolute
and relative inputs, missing components, file traversal, link targets and
the exact forty/forty-one boundary.

### BUG - MEDIUM — Override creation ignores the root's byte limit

`Editor.override/3` checked `max_templates`, then called
`limit_refusal(socket, 1, 0)`. Built-in, database and layout overrides could
all grow the root beyond `max_root_bytes`.

Fixed: pass the byte limit into `Overriding`, sum the complete planned files
and compare with current usage before creating anything. Tests cover the
multilingual plan, exact capacity, database export, layout defaults and the
LiveView button. Refused creation leaves no files or success journal event.

### BUG - MEDIUM — Saves count replacement bytes twice

The save check added each replacement's full size to usage that already
included its old contents. At the limit, even replacing a subject with a
shorter subject was refused.

Fixed: count only positive growth for each changed part. Shrinks and deletes
do not consume space; their freed space is not credited against other parts
in the same request because saves can succeed only in part. A regression
verifies a smaller replacement succeeds at the limit; the existing growth
refusal remains covered.

### BUG - MEDIUM — Choosing an email's layout bypasses the byte limit

`Editor.set_layout/2` wrote `layout.txt` without a root-capacity check.

Fixed: check the file's positive growth before writing. A LiveView regression
verifies that creating the file at capacity is refused and replacing an
existing layout with a shorter group still succeeds.

### IMPROVEMENT - MEDIUM — Check override destinations explicitly

`Overriding.fresh/2` used `File.exists?/1`, which treats a dangling link as
absent. The filesystem would usually reject the subsequent mkdir, but this
did not satisfy the repository's explicit pre-write directory check.

Fixed: use `Files.check_template_dir/2` before planning and immediately before
the write batch. A dangling-link regression verifies an unsafe-path refusal
and preservation of the link and its missing target.

## Claude's other conclusions

The escaped git regex and tolerant filter-key parsing are correct; their
regression and existing filter-neutralization tests pass.

Leave the two nitpicks unchanged: config/README refresh remains inexpensive,
and standalone editors intentionally allow `editable: true` without an
authorization callback. The Settings section always supplies its authorizer.

The dependency's lookup/copy race remains the accepted limitation documented
in AGENTS.md. These checks do not claim atomic filesystem operations or a
global lock across concurrent editors.

## Validation

New path, sources, oversized-file and override-capacity regressions failed
before the respective changes (seven failures in the initial focused run).
The module-layout send regression and both additional capacity regressions
also failed before their fixes.

Final validation: `mix test` — 566 tests, 0 failures, including integration
tests. `mix precommit` — clean. `git diff --check` — clean.

Changes and this review are committed locally. No push, version bump, Hex
publish or tag was requested.
