# PhoenixKitTemplatesEditor

A [PhoenixKit](https://github.com/BeamLabEU/phoenix_kit) module that edits your
app's email template files — the [`phoenix_kit_templates`](https://github.com/BeamLabEU/phoenix_kit_templates)
overrides PhoenixKit renders its emails from — in a tab of
**Settings › Emails Transactional**.

Your templates stay yours: one directory of files in your app, deployed with
your code. This package is only the tool, plus a block of config that tells it
which templates are yours and how to show them.

> Status: 0.1.0, unreleased. The module registers, gates access and checks the
> config; the editor itself is not wired into the tab yet.

## Installation

```elixir
# mix.exs
{:phoenix_kit_templates_editor, "~> 0.1"}
```

Then `mix deps.get`. PhoenixKit discovers the module by itself — no config line
in `:phoenix_kit, :modules` is needed. Switch it on at **Admin › Modules**
(*Templates editor*); it is off by default, and a switched-off module shows no
tab.

Requires `phoenix_kit` 2.57.0 or later.

## Who sees the tab

The email settings page is behind PhoenixKit's `settings` permission. The tab
adds the module's own key, `templates_editor`, so it can only narrow that:

| To | A role needs |
|---|---|
| see the tab | `settings` and `templates_editor`, with the module switched on |
| save, create or delete files | the above and `templates_editor.write`, and `editable: true` in config |

Owner holds every permission. Admin is granted the module's keys when PhoenixKit
first discovers it; revoke them in the roles matrix to hide the editor from
Admins.

For your own "Edit templates" links:

```elixir
if PhoenixKitTemplatesEditor.accessible?(scope) do
  # href = PhoenixKitTemplatesEditor.tab_path()        # URL prefix and locale applied
end
```

## Configuration

```elixir
# config/config.exs
config :phoenix_kit_templates_editor,
  root: nil,                    # nil: the first of PhoenixKit.Email.Content.override_paths/0
  name_prefixes: ["shop_order_", "_header-shop", "_footer-shop", "_layout-shop"],
  locales: ~w(et ru en),
  base_locale: "et",
  layout_group: "shop",
  preview: {MyApp.Emails, :preview},                    # (name, locale) -> {subject, html, text}
  sample_variables: {MyApp.Emails, :sample_variables},  # () -> map
  block_placeholders: ["documents_list"],
  catalog: true

# config/dev.exs — only where templates are edited
config :phoenix_kit_templates_editor, editable: true
```

| Key | Default | Meaning |
|---|---|---|
| `root` | first of `PhoenixKit.Email.Content.override_paths/0` | the templates directory; it must exist |
| `editable` | `false` | exactly `true` allows writing; anything else is read-only. Leave it unset in production |
| `name_prefixes` | `[]` | which templates the editor sees and may write — nothing until you say |
| `locales` | PhoenixKit's enabled languages (base codes), else just `base_locale` | the language tabs, in order |
| `base_locale` | first of `locales`, else PhoenixKit's default language, else `"en"` | the language labels and notes fall back to |
| `layout_group` | `nil` | the layout (`_header-<g>`, `_footer-<g>`, `_layout-<g>`) of an email without `layout.txt` |
| `layout_groups` | `[layout_group]` | layout namespaces the editor may show: `g` and `g-…` |
| `preview` | `nil` | your preview callback; without one the module renders its own |
| `sample_variables` | `%{}` | a map, or `{module, function}` returning one |
| `describe_variables` | `nil` | `(name) -> %{variable => description}` |
| `complete?` | `nil` | `(name, locale) -> boolean`; default: subject and body on `base_locale` |
| `sent_by` | `nil` | `(name) -> :core \| :host` — who sends the email |
| `test_send` | `nil` | `(name, locale, scope) -> :ok \| {:error, reason}` |
| `block_placeholders` | `[]` | variables that stand as a block of their own |
| `raw_variables` | `[]` | variables allowed in `{{{x}}}` besides `content`, `header`, `footer` |
| `email_fallback` | `true` | whether emails get a locale-less *Fallback* tab |
| `shared_layout_editable` | `false` | whether the shared `_header`/`_footer`/`_layout` (PhoenixKit's own system emails) may be edited |
| `overridable` | `:all` | which catalogue emails may get a file: `:all` or a list of names |
| `catalog` | `false` | whether your templates are offered to PhoenixKit's email preview |
| `watch` | same as `editable` | whether the files are re-read when they change on disk |

Callbacks are `{module, function}` or a function of that arity. A config that
does not check out is shown on the tab as a list of problems — the page itself
keeps working.

## What this module does NOT do

- **Ship templates.** No header, footer or email text comes with it; they are
  your app's files.
- **Write in production by default.** `editable` is off unless your config says
  `true`; template changes reach production through your repository and deploy.
- **Commit to git.** It writes files; committing them is yours.
- **Grant access beyond `settings`.** Its key can only narrow who sees the
  email settings page.
- **Own database tables.** One setting row (`templates_editor_enabled`) is all
  it stores.

## Development

```bash
mix deps.get
mix test.setup     # once; creates the test database
mix test
mix precommit
```

See `AGENTS.md` for conventions and the test setup.

## License

MIT — see `LICENSE`, which also carries the notice for code derived from
`phoenix_kit_templates`.
