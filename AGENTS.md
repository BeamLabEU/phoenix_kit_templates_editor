# AGENTS.md

Guidance for AI agents working on `phoenix_kit_templates_editor`.

## Overview

A PhoenixKit module that edits the host's email template files — the `phoenix_kit_templates` overrides core renders its emails from — in a tab of Settings › Emails Transactional (`/admin/settings/email-sending?tab=module_templates_editor`). The host keeps its templates (one directory of files) and a `config :phoenix_kit_templates_editor` block; the tool lives here, so another project gets the same tab by adding the dependency and the config. The tab is a `Phoenix.LiveComponent` core mounts through `email_settings_sections/0`: the config check, an introduction and hints, the project's README notes, the uncommitted-files list and the editor.

- **Depends on:** `phoenix_kit` `>= 2.57.0 and < 3.0.0` (Hex; 2.57.0 is the first core whose section contract carries `:link`), `phoenix_kit_templates` `~> 0.2.3` (hard: the file API, first in 0.2.3), `phoenix_live_view` `~> 1.1`, `gettext` `~> 1.0`. No sibling `phoenix_kit_*` module deps.
- **Consumed by:** host apps only.
- **Admin surface:** no admin tab or route of its own. One section on core's email settings page (`id: :templates_editor`, button beside "Preview emails" via `:link`) and a card on Admin › Modules.
- **Module key** `"templates_editor"`; settings prefix `templates_editor_` (one key: `templates_editor_enabled`, default off). Sub-permission `templates_editor.write`.

## What this module does NOT do

- **Owns no templates.** The files, their notes (`README.<locale>.md` beside them) and the host's own rules stay in the host; nothing project-specific (a header, a footer, a sending rule) belongs in this package.
- **Is not part of `phoenix_kit_templates`.** That library is a leaf core depends on; a `PhoenixKit.Module` there would make `phoenix_kit ⇄ phoenix_kit_templates` a dependency cycle. The library keeps the renderer and the file API; the UI lives here.
- **Does not widen access.** Core gates the email settings page by `settings`; the section's own key can only narrow that, so a role without `settings` never reaches the tab.
- **Never reads `editable` from the database or a request.** Whether files may be written is the host's config, exactly `true`; production stays read-only by leaving it unset.
- **Owns no tables and no migrations** — settings only.

## Commands

```bash
mix deps.get
mix test.setup               # once; creates phoenix_kit_templates_editor_test (DB-backed tests are tagged :integration and auto-skip without it)
mix test
mix precommit                # compile --warnings-as-errors + deps.unlock --check-unused + hex.audit + format check + credo --strict + dialyzer
```

`phoenix_kit*` deps resolve from Hex. To run against a local checkout, export
`<APP>_PATH` (the dep's app name upper-cased plus `_PATH`: `PHOENIX_KIT_PATH`,
`PHOENIX_KIT_TEMPLATES_PATH`); `pk_dep/3` in `mix.exs` swaps the Hex pin for a
`path:` dep at resolve time. Unset means the Hex pin, so `mix hex.publish` is
unaffected. Run `mix deps.get` with the var exported before the first
`mix test`, and never commit a hand-edited `path:` tuple.

```bash
PHOENIX_KIT_PATH=../phoenix_kit mix deps.get && PHOENIX_KIT_PATH=../phoenix_kit mix test
```

`mix test.setup` (`ecto.create`) and `mix test.reset` (`ecto.drop` + create) run in `:test` by themselves (`cli/0` `preferred_envs`).

Repo-local aliases:

- `mix quality` — `format` + `credo --strict` + `dialyzer` (applies formatting).
- `mix quality.ci` — `format --check-formatted` + `credo --strict` + `dialyzer`: it CHECKS formatting rather than applying it, so run `mix format` first.

## Conventions

- **Module key** `"templates_editor"` is identical in `module_key/0`, `permission_metadata/0`'s `:key`, the section's `:permission` and the settings prefix.
- **Access is two keys plus the switch.** `accessible?/1` = module enabled and the scope holds `settings` and `templates_editor`; `authorize(scope, :write)` adds `Scope.can?(scope, "templates_editor.write")`. Every event that changes a file calls `authorize/2` again — never trust what was checked at mount.
- **The section gets nothing from core but its `id`.** Core mounts `<.live_component module={…} id={…} />` with no other assigns, so the host's data comes from `PhoenixKitTemplatesEditor.Config` (and `{module, function}` callbacks in it), never from assigns. The scope comes from `Web.ScopeHook` (a host-added `extra_live_session_on_mount` hook keeping the page's `:phoenix_kit_current_scope` in the connected LiveView process: after `handle_params` and every render; the disconnected first render keeps none — its process is the HTTP connection's — and the section is read only there for a moment); the editor's `authorize` reads it at each event. No hook — no scope — read only.
- **Which names are touched is `Names.check/2`, never a bare `String.starts_with?`.** The shared `_header`/`_footer`/`_layout` only with `shared_layout_editable: true`; a layout part by its group's exact namespace (`layout_groups`, or a prefix shaped like a part — `_header-shop` covers `shop`/`shop-…`, not `shopx`); the emails core and other modules send (`Names.reserved_names/0`) and a module's own layout group only where `overridable` allows (default `[]`, none; `:all` = all but `Names.auth_emails/0`), and never by the plain "New template" form — only by the Module emails buttons (`Overriding`).
- **Every change on disk is journalled.** A new write path in the editor calls `journal/2` with an event `PhoenixKitTemplatesEditor.Journal` lists; the section logs it to `PhoenixKit.Activity` with the scope of the moment.
- **A save is checked before it writes** (`Web.Editor.save/3`): the part's file still as fingerprinted at open (else a conflict, nothing written), the subject (one line, at most 998 bytes), raw braces (`{{{x}}}` only for the HTML variables), variables of the other kind (`Variables.check/3`, confirmed by "Save anyway").
- **Every template file is read through `Files.safe_read/2`**, and before a library call reads a template's files (`Overrides.locate/4` follows links and caches what it read; the host's preview and test send read that way) the template directory goes through `Files.check_template/2` — through `Preview.check_templates/2` for an email and its chrome: no symlinks, nothing whose real path leaves the root, nothing over `Overrides.max_bytes/0`. A write first checks the template directory is no link (`Files.check_template_dir/2`). Messages name files relative to the root (`Files.relative/2`).
- **Work the page waits on runs bounded** (`Bounded.run/2`, 5 s): converters, the default and the host's preview, `git status`.
- **git runs nothing the repository configures** (`Files.uncommitted/1`): `core.fsmonitor=false`, every filter driver's commands set empty by `-c`, submodules ignored, no lazy fetch, a clean `GIT_*` environment, `timeout -s KILL`. Asking it is a writer's action, once in 5 s.
- **Modes and owners are never changed after a write** (no `chmod`/`chown` anywhere, `Files` moduledoc): the server's umask and the root's setgid bit give `0664`/`2775` (README, installation).
- **The cache is dropped once per change by this module** (the section's `after_change` → `Files.reload/1`, under core's own paths to the root too); the library drops it for the root on every write itself. No `after_write` in the section.
- **The root's limits** (`max_templates`, `max_root_bytes` in `Config`) are checked before a new template, a copy, an override or a save.
- **`Config.load/1` never raises.** A bad config is `{:error, messages}`, shown as an alert on the tab; messages name the config key and never an absolute path.
- **`enabled?/0` must never raise.** It `rescue`s and catches `:exit`, returning `false` from every branch.
- **Never hardcode a path.** Links go through `tab_path/1`, which wraps `PhoenixKit.Utils.Routes.path/2` (URL prefix, admin segment, locale).
- **Gettext** is the module's own backend, `PhoenixKitTemplatesEditor.Gettext` (`priv/gettext`: en, et, ru). Components `use PhoenixKitWeb, :live_component` and then `use Gettext, backend: PhoenixKitTemplatesEditor.Gettext`, which rebinds the macros. Labels core translates itself (`permission_metadata/0`) are raw msgids marked with `gettext_noop/1` so `mix gettext.extract` sees them. The module never sets the locale; core does for its LiveViews.
- **Locales are base codes** (`et`, not `et-EE`). PhoenixKit's languages are dialects; `Config` reduces them with `DialectMapper.extract_base/1`, and the template lookup falls back from a dialect to its base anyway.
- **`css_sources/0` returns `[:phoenix_kit_templates_editor]`** — the host's Tailwind finds the module's classes through core's `:phoenix_kit_css_sources` compiler, no hand-written `@source`.
- **Keep the core pin in the compound form** (`>= 2.57.0 and < 3.0.0`). `test/core_pin_conformance_test.exs` fails the build on a narrowed pin and on a committed `path:` dep.

### Landmines

- **`Scope.can?(scope, "templates_editor.write")` is false while the module is not in `PhoenixKit.ModuleRegistry`** — the sub-permission and the module switch resolve through it — so a write check fails as "forbidden" with every key held. `test_helper.exs` starts the registry; a host needs the module discovered (it is, by `use PhoenixKit.Module` and `:phoenix_kit` in `applications`).
- **A settings read in a unit test answers the default, not the database** (no sandbox checkout in that process). A test about the switch or access with the module on belongs under `:integration`.

## Architecture

```
lib/
├── phoenix_kit_templates_editor.ex         # PhoenixKit.Module: callbacks, tab_path/1, accessible?/1, authorize/2
└── phoenix_kit_templates_editor/
    ├── bounded.ex                           # run work in a task with a deadline (internal)
    ├── catalog.ex                           # the host's emails: list order, entries for core's email preview
    ├── config.ex                            # Config.load/1 — config :phoenix_kit_templates_editor, checked
    ├── converters.ex                        # the editor's buttons: to_text/3, markdown_to_html/2
    ├── files.ex                             # reload, uncommitted (git), safe_read, check_template, usage, realpath
    ├── gettext.ex                           # Gettext backend (priv/gettext)
    ├── html_text.ex                         # HTML → plain text (public)
    ├── journal.ex                           # changes in PhoenixKit's activity log, with a short diff
    ├── layouts.ex                           # a root's layouts: parts own/inherited, emails using each, copy/delete
    ├── names.ex                             # which names an editor may touch (shared parts, namespaces, reserved emails, overridable)
    ├── overriding.ex                        # files for a module's email: from its built-in text, the Emails DB row, a layout default
    ├── preview.ex                           # the default preview (no host preview)
    ├── sources.ex                           # where each part of an email core sends comes from (Content.resolve_with_sources)
    ├── test_send.ex                         # "Send to me": the user's own address, throttled, logged
    ├── throttle.ex                          # child: once-per-interval ETS table
    ├── variables.ex                         # a part's variables by template kind; the save check
    ├── watcher.ex                           # child: re-reads the files every 2 s where edited/watched
    └── web/
        ├── editor.ex                        # Web.Editor — the editor LiveComponent (from phoenix_kit_templates 0.2.4)
        ├── scope_hook.ex                    # on_mount hook: the page's scope for the section
        └── section.ex                       # the tab's LiveComponent (core mounts it)
priv/static/assets/phoenix_kit_templates_editor.js  # the variables hook (js_sources/0), no build step
```

| Callback | Value |
|---|---|
| `enabled?/0` | `templates_editor_enabled`, default `false` |
| `permission_metadata/0` | key `templates_editor`, icon `hero-document-text`, sub-permission `write`, `gettext_backend` |
| `email_settings_sections/0` | `%{id: :templates_editor, permission: "templates_editor", component: Web.Section, link: %{label: …}}` |
| `email_templates/0` | `Catalog.entries/1` with `catalog: true`, else `[]` |
| `children/0` | `[Watcher, Throttle]` (the Watcher decides in `init/1`) |
| `css_sources/0` | `[:phoenix_kit_templates_editor]` |
| `js_sources/0` | `priv/static/assets/phoenix_kit_templates_editor.js`, global `PhoenixKitTemplatesEditorHooks` |
| `migration_module/0` | not set |

Config keys and defaults: `PhoenixKitTemplatesEditor.Config` `@moduledoc` (the table there is the reference).

## Database & migrations

None — settings only. `migration_module/0` is not set; the one setting row (`templates_editor_enabled`) is written by core's `Settings.update_boolean_setting_with_module/3`.

## Testing

- Test DB `phoenix_kit_templates_editor_test` (suffix `MIX_TEST_PARTITION`; `PGDATABASE` overrides the name). Env honoured: `PGUSER` (default `postgres`), `PGPASSWORD` (default `postgres`), `PGHOST` (default `localhost`), `PGDATABASE`, `PGPOOL` (pool size; on a shared Postgres use a small one and `--max-cases`).
- Without Postgres: behaviour, `Config`, section render, i18n and conformance tests run; `test/integration/` is tagged `:integration` through `DataCase` and excluded automatically.
- `test_helper.exs` probes the database with core's `PhoenixKit.TestSupport.PostgresPreflight`, starts `Test.Repo`, builds the schema with `PhoenixKit.Migration.ensure_current/2`, starts `PhoenixKit.PubSub.Manager` and `PhoenixKit.ModuleRegistry`, and sets core's URL-prefix cache to `"/"`.
- The settings cache (`PhoenixKit.Cache`) is deliberately not started: a cached value would outlive each test's sandbox rollback. Core logs a warning about it on every settings read, so `config/test.exs` sets the logger to `:error`.
- Editor tests (`test/phoenix_kit_templates_editor/web/editor*_test.exs`) use `PhoenixKitTemplatesEditor.EditorCase`: a `tmp_dir` root, the editor mounted in `Test.EditorHost` (a LiveView) on `Test.Endpoint` through `live_isolated/3`. A session cannot carry a function, so `mount_editor/2` hands function-valued options to the host right after the mount. The page language is `opts[:locale]`, put on the module's Gettext backend in the host's `mount`.
- `Config` tests that pass `root: nil` change `config :phoenix_kit, :template_paths` and restore it; that file and the section test are not `async`.
- Section tests use `PhoenixKitTemplatesEditor.SectionCase`: `configure/1` sets the module's config keys for one test, `mount_section/1` mounts `Test.SectionHost` (core's page in miniature: it puts a session scope on the socket, runs `Web.ScopeHook`, mounts the section with only its id; `{:scope, scope}` swaps the scope). Writing needs the module enabled, so those tests are `:integration`.
- `test_helper.exs` also starts `Throttle` (a module child in a host).
- `Test.FakeProvider` (core's `:email_provider` seam: the Emails module's database templates from the app env) and `Test.FakeTemplateExport` (set as `:template_export`, an internal seam of `Overriding`) stand in for `phoenix_kit_emails`, which is not a dependency; tests using them change the application env and are not `async`.
- The test logger level is `:error`; a test about a warning sets `Logger.put_module_level(Module, :warning)` and deletes it on exit.

```bash
mix test                                   # all tests (:integration excluded without a DB)
mix test test/phoenix_kit_templates_editor # Config and section only
mix test --only integration
```

## Feature notes

None yet. Behaviour is documented in `@moduledoc`s (`PhoenixKitTemplatesEditor`, `Config`, `Web.Section`) and the README.

## Versioning & releases

SemVer. The version is single-sourced in `mix.exs` (`@version`); `version/0`
reads it at compile time and the behaviour test asserts against
`Mix.Project.config()[:version]`, so nothing else needs bumping.

Release procedure (the steps the maintainer runs):

1. Bump `@version` in `mix.exs`; add a `CHANGELOG.md` entry headed `## x.y.z - YYYY-MM-DD`.
2. `mix precommit` clean.
3. Commit (`"Bump version to x.y.z"`) and push; verify the push landed.
4. `mix hex.publish`.
5. Tag, matching the form of the newest existing tag (`git tag --sort=-creatordate | head -1` shows it), and push the tag.
6. GitHub release via `gh release create` if the repo does those (`gh release list` shows whether it does).

Tags are immutable pointers: never tag before the commit is pushed and the
publish has succeeded.

## Pull requests & commits

- Commit messages start with an action verb (`Add`, `Update`, `Fix`, `Remove`, `Merge`). No AI attribution and no `Co-Authored-By` trailers.
- Version bumps and CHANGELOG entries land with the release commit on upstream, not in feature PRs.
- Review files live in `dev_docs/pull_requests/{year}/{pr_number}-{slug}/{AGENT}_REVIEW.md`, one file per reviewing agent, never edited by another agent; `FOLLOW_UP.md` records how each finding was resolved. Severities: `BUG - CRITICAL/HIGH/MEDIUM`, `IMPROVEMENT - HIGH/MEDIUM`, `NITPICK`.

## TODOs

- **The scope comes through a host-added hook** (`Web.ScopeHook`: the page's scope kept in the LiveView process's dictionary, and an `extra_live_session_on_mount` line in every host). A one-line core change makes it unnecessary: core's `email_sending.html.heex` passing `phoenix_kit_current_scope={@phoenix_kit_current_scope}` to the section's `<.live_component>`. `Web.Section` already prefers an assigned `:phoenix_kit_current_scope`, so nothing here changes but dropping the hook and its README step. Trigger: a core release with that change.
- **Variable descriptions come from the host** (`describe_variables`); core's catalogue has no description field. Trigger: a core PR adding one.
- **The library's cache is reset key by key** (`Overrides.reset_cache/1` walks `:persistent_term`, and every erase costs the VM a global collection); resetting by a generation counter is a library change. Trigger: a `phoenix_kit_templates` release with generation-based cache reset. Until then Reload is a writer's, once in 5 s.
- **The library's lookup follows links** (`Overrides.locate/4`, `copy_template/3`): the module checks the template directories before calling it (`Files.check_template/2`), which leaves a race between the check and the read. A library change making `locate` and `copy_template` refuse links closes it. Trigger: a `phoenix_kit_templates` release whose lookup and copy refuse links.
- **No transfer of an Emails database row over existing files**: "Create file from the database template" is offered only while the email has no file. Doing it over files needs a diff and a confirmation. Trigger: a host that keeps database rows and files of the same email.
- **`Web.Editor` is one 3.9k-line component** (`render/1` alone ~730 lines), its controls raw `<input>`/`<select>`/`<button>` rather than core's components. Committed: before any new feature lands in the editor, it is split — the layouts panel, the module emails view, the variables panel and the preview pane into function-component modules, the save, conflict and layout actions into plain modules — and its controls move to core's components (`<.input>`, `<.select>`, `<.button>`, `<.modal>`), with no behaviour change. Trigger: the next feature in the editor, which waits for that split.
