# PR #1 — Initial module (`timujinne/feat/initial-module`)

Reviewer: Claude. Merge commit `05d097e`; 89 files, ~21k lines.

## Scope of this review

Read line by line: `PhoenixKitTemplatesEditor` (callbacks, access), `Web.ScopeHook`,
`Bounded`, `Throttle`, `Watcher`, `Files`, `Names`, `TestSend`, `Web.Section`
(config/authorisation half), and the event/authorisation layer of `Web.Editor`
(`handle_event/3`, `permitted/3`). **Not** read line by line: `Web.Editor`'s render and
save internals, `Preview`, `Converters`, `Overriding`, `Config`, `Layouts`, `Journal`,
`Catalog`, `Sources`, `Variables`, `HtmlText`, the gettext catalogues. Those are covered by
the test suite (548 tests green before the fixes) but have had no independent read.

Overall: the access model matches AGENTS.md — every writing event goes through
`permitted/3` → `authorize` callback → `PhoenixKitTemplatesEditor.authorize(scope, :write)`,
the scope read at event time; `editable` comes only from config; names go through
`Names.check/2`; template reads go through `Files.safe_read/2`/`check_template/2`.

## Findings

### BUG - MEDIUM — `Files.neutral_filters/2`: unescaped regex crashes the page for some git configs (fixed)

`~w(config -z --get-regexp ^filter\.)` — inside a lowercase `~w` sigil `\.` is an escape
and yields `.`, so git was asked for `^filter.` (any character). A repository whose config
has a section such as `[filtering]` or `[filter-repo]` returned keys like `filtering.mode`;
`filter_names/1` then did a hard match `"filter." <> rest = key`, raising `MatchError`.
`Bounded.run/2` re-raises in the caller, which is the LiveView process, so *Check
uncommitted files* and every `after_change` refresh took the page down for those repos.

Fix: pass the regex as a plain string (`"^filter\\."`), and iterate with
`"filter." <> rest <- [key]` so a key not shaped like a driver's is skipped instead of
matched hard. Test: "a config section merely starting with `filter` is no driver"
(failed with the `MatchError` before the fix).

### BUG - LOW — `Files.realpath/1` resolves `..` in a link target lexically (fixed)

A link target was passed through `Path.expand/2`, which removes `..` textually before the
links earlier in the target are resolved. For `root/a -> /outside/sub` and
`root/b -> a/..` the kernel gives `/outside`, `realpath/1` gave `root`. `realpath/1` backs
the containment checks (`check/2`, `check_template_dir/2`, `same_dir?/2`), so a check could
answer "inside the root" for a path that leaves it. Exploiting it needs a link already in
the root and one the other checks do not reject (they refuse links among template files and
require the template directory itself to be a real directory), so the practical risk is
small — fixed anyway because the function is the primitive the guarantees rest on.

Fix: resolve `.`/`..` component by component (`..` goes up from the already-resolved real
directory); relative targets resolve from the link's directory. Test: "`..` after a link in
a target is taken from the linked directory".

### NITPICK — `Web.Section.update/2` rereads the config and README on every update

`Config.load/1` and `readme/1` (a file read) run on each `update/2`, i.e. on each parent
re-render of the settings page. Cheap today (small files, no DB), so left as is; if the page
ever re-renders often, cache the README by mtime.

### NITPICK — `Editor.authorized?(nil, _) -> true`

An editor mounted without an `:authorize` callback is writable whenever `editable: true`.
Documented behaviour, and `Web.Section` always passes one; noted because it is the only
place access is open by default. No change.

### Known and accepted (already in AGENTS.md TODOs)

Scope via host-added hook, library cache reset key-by-key, link-following `locate`/
`copy_template` TOCTOU, and the 3.9k-line `Web.Editor` split. Not repeated here.

## Gate

`mix test`: 550 tests, 0 failures (548 + the 2 added). `mix precommit` clean.
Release phases not run: the request named PR #1 only, and the module is still `0.1.0 —
unreleased` (a first Hex publish is not undone by retagging).
