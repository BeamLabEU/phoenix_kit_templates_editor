# AGENTS.md

Guidance for AI agents working on `phoenix_kit_templates_editor`.

## Overview

A PhoenixKit module that edits the host's email template files — the `phoenix_kit_templates` overrides core renders its emails from — in a tab of Settings › Emails Transactional (`/admin/settings/email-sending?tab=module_templates_editor`). The host keeps its templates (one directory of files) and a `config :phoenix_kit_templates_editor` block; the tool lives here, so another project gets the same tab by adding the dependency and the config. The tab is a `Phoenix.LiveComponent` core mounts through `email_settings_sections/0`: the config check, an introduction and hints, the project's README notes, the uncommitted-files list and the editor.

- **Depends on:** `phoenix_kit` `>= 2.57.0 and < 3.0.0` (Hex; 2.57.0 is the first core whose section contract carries `:link`), `phoenix_kit_templates` `~> 0.2.4` (hard: the file API), `phoenix_live_view` `~> 1.1`, `gettext` `~> 1.0`. No sibling `phoenix_kit_*` module deps.
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
- **The section gets nothing from core but its `id`.** Core mounts `<.live_component module={…} id={…} />` with no other assigns, so the host's data comes from `PhoenixKitTemplatesEditor.Config` (and `{module, function}` callbacks in it), never from assigns. The scope comes from `Web.ScopeHook` (a host-added `extra_live_session_on_mount` hook keeping the page's `:phoenix_kit_current_scope` in the LiveView process: after `handle_params` and every render); the editor's `authorize` reads it at each event. No hook — no scope — read only.
- **Every template file is read through `Files.safe_read/2`** (or checked with `Files.check/2` before a library call reads it): no symlinks, nothing whose real path leaves the root, nothing over `Overrides.max_bytes/0`. Messages name files relative to the root (`Files.relative/2`).
- **Work the page waits on runs bounded** (`Bounded.run/2`, 5 s): converters, the default preview, `git status`.
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
    ├── files.ex                             # reload, after_write (modes), uncommitted (git), safe_read, realpath
    ├── gettext.ex                           # Gettext backend (priv/gettext)
    ├── html_text.ex                         # HTML → plain text (public)
    ├── preview.ex                           # the default preview (no host preview)
    ├── watcher.ex                           # child: re-reads the files every 2 s where edited/watched
    └── web/
        ├── editor.ex                        # Web.Editor — the editor LiveComponent (from phoenix_kit_templates 0.2.4)
        ├── scope_hook.ex                    # on_mount hook: the page's scope for the section
        └── section.ex                       # the tab's LiveComponent (core mounts it)
```

| Callback | Value |
|---|---|
| `enabled?/0` | `templates_editor_enabled`, default `false` |
| `permission_metadata/0` | key `templates_editor`, icon `hero-document-text`, sub-permission `write`, `gettext_backend` |
| `email_settings_sections/0` | `%{id: :templates_editor, permission: "templates_editor", component: Web.Section, link: %{label: …}}` |
| `email_templates/0` | `Catalog.entries/1` with `catalog: true`, else `[]` |
| `children/0` | `[Watcher]` (decides in `init/1`) |
| `css_sources/0` | `[:phoenix_kit_templates_editor]` |
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

- **The scope comes through a host-added hook** (`Web.ScopeHook`). A core change passing `:phoenix_kit_current_scope` to email settings sections would make it unnecessary; the section already prefers an assigned scope. Trigger: a core release that passes it.
- **The library's cache is reset key by key** (`Overrides.reset_cache/1` walks `:persistent_term`); generation-based reset (spec §4.10 Б12) is a library change. Trigger: the library PR planned after block L.
