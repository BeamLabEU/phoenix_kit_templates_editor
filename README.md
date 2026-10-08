# PhoenixKitTemplatesEditor

A [PhoenixKit](https://github.com/BeamLabEU/phoenix_kit) module that edits your
app's email template files — the [`phoenix_kit_templates`](https://github.com/BeamLabEU/phoenix_kit_templates)
overrides PhoenixKit renders its emails from — in a tab of
**Settings › Emails Transactional**.

Your templates stay yours: one directory of files in your app, deployed with
your code. This package is only the tool, plus a block of config that tells it
which templates are yours and how to show them.

> Status: 0.1.0, unreleased.

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

### Let the tab know who is acting

PhoenixKit mounts the tab with nothing but its id, so the module needs a hook
in PhoenixKit's live sessions to check, on every save, who is saving:

```elixir
# config/config.exs
config :phoenix_kit,
  extra_live_session_on_mount: [PhoenixKitTemplatesEditor.Web.ScopeHook]
```

This is read when your router compiles. Without it the tab works, but shows the
templates read-only and says why.

### The variables panel's hook

A click on a variable puts it at the cursor through a LiveView hook the module
ships prebuilt (`priv/static/assets/phoenix_kit_templates_editor.js`, declared
by `js_sources/0`). PhoenixKit's `:phoenix_kit_js_sources` compiler folds it
into your LiveSocket — no inline script, no `app.js` edit — provided your
`mix.exs` lists the compiler:

```elixir
compilers: [:phoenix_kit_js_sources, :phoenix_live_view] ++ Mix.compilers()
```

Without it the panel still works: a click puts the variable at the end of the
body instead.

### Where templates are edited: the directory

The module never changes a file's owner. Where `editable: true`, make the
templates root a setgid directory of the group that owns your tree, so what the
server writes stays editable by the people who commit it:

```bash
chgrp -R devs priv/phoenix_kit_templates
chmod -R g+rwX priv/phoenix_kit_templates
find priv/phoenix_kit_templates -type d -exec chmod g+s {} +
```

New files are written `0664`, new directories `2775`.

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
| `name_prefixes` | `[]` | which templates the editor sees and may write — nothing until you say. A prefix shaped like a layout part (`_header-shop`) allows that part of layout `shop` and `shop-…`, not every name starting with the string |
| `locales` | PhoenixKit's enabled languages (base codes), else just `base_locale` | the language tabs, in order |
| `base_locale` | first of `locales`, else PhoenixKit's default language, else `"en"` | the language labels and notes fall back to |
| `layout_group` | `nil` | the layout (`_header-<g>`, `_footer-<g>`, `_layout-<g>`) of an email without `layout.txt` |
| `layout_groups` | `[layout_group]` | layout namespaces the editor may show and create: `g` and `g-…` (not `gx`) |
| `preview` | `nil` | your preview callback; without one the module renders its own |
| `sample_variables` | `%{}` | a map, or `{module, function}` returning one |
| `describe_variables` | `nil` | `(name) -> %{variable => description}`, shown in the variables panel |
| `complete?` | `nil` | `(name, locale) -> boolean`; default: subject and body on `base_locale` |
| `sent_by` | `nil` | `(name) -> :core \| :host` — who sends the email; default: PhoenixKit for the emails of its catalogue, your app for your own |
| `test_send` | `nil` | `(name, locale, user) -> :ok \| {:ok, term} \| {:error, reason}` — your own way to send "Send to me" (your test mode included); default: `PhoenixKit.Mailer` |
| `block_placeholders` | `[]` | variables that stand as a block of their own |
| `raw_variables` | `[]` | variables allowed in `{{{x}}}` besides `content`, `header`, `footer` |
| `email_fallback` | `true` | whether emails get a locale-less *Fallback* tab |
| `shared_layout_editable` | `false` | whether the shared `_header`/`_footer`/`_layout` (PhoenixKit's own system emails) may be edited |
| `overridable` | `:all` | which emails PhoenixKit and its modules send may be given a file here: `:all` — every one but the sign-in emails (account confirmation, password reset, email change, magic link); a list — exactly those names |
| `catalog` | `false` | whether your templates are offered to PhoenixKit's email preview |
| `watch` | same as `editable` | whether the files are re-read when they change on disk |

Callbacks are `{module, function}` or a function of that arity. A config that
does not check out is shown on the tab as a list of problems — the page itself
keeps working.

## The tab

- **Notes for your editors.** Put `README.<language>.md` (or `README.md`) in the
  templates root — the language of the page first, then `base_locale`, then
  `README.md`. It is shown above the editor as Markdown (sanitized), read-only
  servers included. Write there what only your project knows: which variables
  an email may use, what stops it from being sent. The template list skips
  files in the root, so the notes never show up as a template.
- **Not committed yet.** Where `editable: true`, a button lists the files under
  the root that differ from git's last commit, and the list refreshes after
  every change made in the editor. Git runs without the repository's hooks or
  `GIT_*` variables and never rewrites the index.
- **Layouts.** A layout `g` is `_header-g`, `_footer-g` and `_layout-g`; a part
  it lacks comes from the shared `_header`/`_footer`/`_layout`, else
  PhoenixKit's own. The tab lists the layouts in `layout_groups` — the default
  (`layout_group`) first — with which parts are their own, which are inherited,
  and the emails using each. A new layout is a copy of an existing one; a layout
  goes only when no email uses it. An email's *Layout* field writes its
  `layout.txt` (or deletes it for the default), and the preview follows at once.
- **Names it never touches.** Whatever `name_prefixes` say: the shared
  `_header`/`_footer`/`_layout` (they wrap PhoenixKit's sign-in and password
  emails too) unless `shared_layout_editable: true`, and the emails PhoenixKit
  or another module sends — but through *Module emails*, below.
- **Module emails.** Every email PhoenixKit and its modules send (their
  catalogue, the one *Preview emails* lists), read only — the built-in text in
  each language — until it has a file here. Where `overridable` allows it, a
  writer creates the file from the built-in text, one per language of
  `locales` (from then on module updates no longer change that email's text),
  or, with the Emails module installed and an active database template of that
  name, from that row by the Emails module's own export. A module's own layout
  (`layout: "billing"` in its catalogue entry) gets its header, footer and page
  layout the same way, from your shared one or PhoenixKit's. The sign-in emails
  are left out of `:all` and carry a warning wherever they are shown.
- **What is sent.** For an email PhoenixKit sends, each part — subject, text,
  HTML, Markdown — says where it comes from, asked of PhoenixKit's own
  resolution: this file, another file, an empty file (the part is left out),
  the built-in text, or the Emails module's database template, which wins over
  every file (a red notice says so). An email your app sends itself
  (`sent_by`) says the files are what it uses.
- **Variables.** Beside the form, the variables of the part's kind of
  template, with a sample and your `describe_variables` text: an email's own
  (its catalogue samples, or `sample_variables`), the branding (`logo_url`,
  `accent_color`) in Markdown — everywhere for an email PhoenixKit sends — or,
  for a header, footer or layout, the layout's. A click puts one in the field.
  A save is checked: a variable of the other kind (`{{site_url}}` in an
  email's body) is saved only after "Save anyway"; an unknown one with a
  warning; `{{{x}}}` only for `raw_variables` (and a page layout's `content`,
  `header`, `footer`); a subject one line of at most 998 bytes.
- **Send to me.** One email, with the sample variables, in its layout, to the
  address of the user asking and nobody else — once in 30 s per user, logged,
  read-only servers included. Your `test_send` callback sends it if you give
  one; otherwise `PhoenixKit.Mailer`.
- **Someone else changed the file.** A part's file is fingerprinted when the
  form is given it; a save of a part whose file has changed on disk since — by
  hand, by `git pull`, by another user — is refused, showing what is on disk
  now, and your text stays in the form. *Reload* reads everything again.
- **Activity log.** Every save, deletion, copy, file made for a module's
  email and change of layout is in PhoenixKit's activity log: who, which
  template, part and language, and a short diff.
- **Copying a template** takes every file of its directory; your own files
  beside the parts (`audience.txt`, say) are listed to untick.
- **Preview.** Without a `preview` callback the module renders the email as
  PhoenixKit would from these files: HTML from `html`, else Markdown, else text;
  text from `text`, else Markdown, else the HTML; your sample variables filled
  in; wrapped in the layout of the email's `layout.txt`, else `layout_group`.
  A header, footer or layout is shown around the first email using that layout
  (else the first email, else a Lorem ipsum). The
  preview frame runs no scripts and loads no images but from your site's origin.
- **Converters.** *Fill text from content* and *Markdown → HTML* keep
  `{{placeholders}}` as typed (link targets too); a variable in
  `block_placeholders` alone in a paragraph comes out of the `<p>`.
- **Files changed on disk.** Where the files are edited (or `watch: true`), the
  module looks at them every 2 s and drops PhoenixKit's cached templates when
  they change — a hand edit or a `git pull` shows in the next email.
- **Preview emails.** With `catalog: true` your emails (names under
  `name_prefixes`, no leading `_`) appear in PhoenixKit's *Preview emails* —
  provided `root` is the directory PhoenixKit reads emails from
  (`config :phoenix_kit, :template_paths`); otherwise the tab says so.
- **What is never read.** A template file that is a symbolic link, leads out of
  the root or is larger than 256 KiB is shown as unavailable, never read.

## What this module does NOT do

- **Ship templates.** No header, footer or email text comes with it; they are
  your app's files.
- **Write in production by default.** `editable` is off unless your config says
  `true`; template changes reach production through your repository and deploy.
- **Commit to git.** It writes files; committing them is yours.
- **Change file owners.** Writes keep the server's user; group access comes
  from the setgid root (above).
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
