# PhoenixKitTemplatesEditor

A [PhoenixKit](https://github.com/BeamLabEU/phoenix_kit) module that edits your
app's email template files — the [`phoenix_kit_templates`](https://github.com/BeamLabEU/phoenix_kit_templates)
overrides PhoenixKit renders its emails from — on a page of its own,
**Settings › Email templates** (`/admin/settings/email-templates`).

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
menu item and refuses the page.

Requires `phoenix_kit` 3.5.0 or later (below 4.0).

### No hook for the scope

The page is a LiveView of its own and hands its `phoenix_kit_current_scope`
straight to the editor, so nothing has to be added to PhoenixKit's live
sessions. A host that still lists `PhoenixKitTemplatesEditor.Web.ScopeHook` in
`extra_live_session_on_mount` (an older setup needed it) can drop the line: the
module stays, the page does not use it.

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
body instead. The bundle is admin-scoped (core 3.6 and later): public pages do
not download it; the admin page fetches it with PhoenixKit's admin bundle.

### The letter's body: Leaf

A letter's body (a template without a leading `_`) is one
[Leaf](https://hex.pm/packages/leaf) editor — visual or Markdown mode, never
hybrid or HTML. The Markdown file is the body; on *Save* the editor writes it
and the text file derived from it (so the text version of a letter is never
typed). A letter that has only a text file opens in Leaf with the text turned
into Markdown, and nothing is written until *Save*. A letter that also has an
HTML file keeps that file in a code field with a note. Headers, footers and
layouts keep their code fields. *Text version* in the template's actions shows
the derived text, read only.

The module depends on `leaf` (`~> 0.11.0 or ~> 0.12.0 or ~> 0.13.0`). Leaf is a
LiveComponent with a JavaScript hook, and PhoenixKit already takes care of it:
core 3.5 and later registers a lazy `Leaf` hook in `window.PhoenixKitHooks`
that loads the installed copy of Leaf's `leaf.js` (copied to
`priv/static/assets/vendor/lib/` by PhoenixKit's own asset step) the first time
an editor mounts, so a page without one — a public page included — downloads
nothing. A host needs no `app.js` line for it.

Only a host that does not use `PhoenixKitHooks` loads Leaf itself: in `app.js`,
`import "../../deps/leaf/priv/static/assets/leaf.js"` (it registers
`window.LeafHooks`) and spread `...(window.LeafHooks || {})` into the
LiveSocket's `hooks`, as in Leaf's own README. The JS and the Hex package must
be the same version, or the body stays on its loading text. Leaf's own buttons
are in English.

**What the first save changes in how a letter is built.** Core makes an
email's HTML from the first of these that exists: the `html` file, the
Markdown file, the text file (each line of it a line of the letter). A letter
that has only a text file is therefore sent from its text; once its body is
saved here it has a Markdown file, and its HTML is made from that. The two
paths differ in what core does, not in what this module writes:

- the value of a variable that has line breaks (an address, a signature) is
  put in after the Markdown is rendered and is escaped, with no `<br>` — in
  the text path every line of a value was a `<br>`, in the Markdown path they
  run together;
- Markdown makes lists, headings and tables of what the text path showed as
  typed, and sets quotes and dashes in typographic form;
- a paragraph of one link becomes a button, a paragraph of only empty
  variables disappears.

The substitution is core's (`PhoenixKit.Email.Markdown`), so this module does
not change it; the preview shows what core sends. The letter's own line
breaks are kept: Leaf's lines are written with an explicit break (a trailing
`\`), except beside a placeholder of a block variable
(`block_placeholders`, say `documents_list`): there the block is put in place
of the placeholder together with the line break next to it, so no break is
written after a line that ends with such a placeholder or before a line that
starts with one, and the text version still keeps every line. Leaf's toolbar is its compact one; it keeps
strike-through, inline code and emoji, which the preset cannot drop, and the
phone toolbar's «Heading».

**Known limits of the body.** Several blank lines in a row are one in Leaf's
visual mode (it writes an empty paragraph as nothing) and in core's text
version of a Markdown file. A letter with room left on purpose (more than one
blank line in a row, where a writer of a frame letter types) is therefore
opened in Markdown mode, where the run of blank lines is kept as typed and
goes into both files; if the writer switches to the visual mode, the form says
that only one blank line of each run survives an edit. A letter without room
opens in the mode chosen last, except the one right after a frame letter,
which opens in the visual mode again. A letter with room that is never edited keeps
its files as they are.

A line that ends with a bare web address (`https://…`, any other `scheme://…`,
`www.…`) is followed by
a break of two spaces, not of a trailing `\`: the renderer's autolink would take
that backslash into the address.

Opening a letter in Markdown mode (the mode the writer chose last is kept),
switching to visual and leaving the field can rewrite the body into Leaf's own
normal form (`*x*` for `_x_`, its list marks, its spacing) although nothing was
typed: Leaf then reports the body as changed, and the next *Save* writes it and
the text made from it.

A picture pasted from the clipboard (a screenshot) is put into the body as an
inline `data:` image, which an email does not carry: it is dropped from the
letter. Leaf's `deny: [:images]` would not stop that paste, and it would strip
the images (`![Logo]({{logo_url}})`) a letter already has the first time Leaf
opens it, so it is not set.

### Where templates are edited: the directory

The module never changes a file's owner. Where `editable: true`, make the
templates root a setgid directory of the group that owns your tree, so what the
server writes stays editable by the people who commit it:

```bash
chgrp -R devs priv/phoenix_kit_templates
chmod -R g+rwX priv/phoenix_kit_templates
find priv/phoenix_kit_templates -type d -exec chmod g+s {} +
```

Then give the server process the umask `0002` (supervisord `umask=002`,
systemd `UMask=0002`): new files come out `0664` and new directories `2775`,
in the root's group. The module sets no mode and no owner itself: doing that
after a write, as the server's user, in a directory other people can write to,
could be turned onto another file through a link put there in the meantime.

## Upgrading from 0.2

0.2 put the editor in a section of Settings › Emails Transactional; this
version gives it a page of its own, and a letter's body is edited in Leaf. What
changes for a host:

- **The address.** The page is `/admin/settings/email-templates`. A link to the
  old section (`?tab=module_templates_editor`) is not redirected: build links
  with `PhoenixKitTemplatesEditor.tab_path/1`.
- **Gone from the page**: the introduction and the hints, the block that showed
  the project's own `README.<language>.md` notes (the files stay where they are,
  for the people who work with the folder; the page does not show them), and the
  line naming the variables that work only in a header, footer or layout.
- **Scope.** `PhoenixKitTemplatesEditor.Web.Section` takes the user's scope only
  from its `phoenix_kit_current_scope` assign, which the page gives it; it no
  longer falls back to `PhoenixKitTemplatesEditor.Web.ScopeHook`. A host that
  mounts the section itself has to pass the assign, or the editor is read only.
  The hook module stays, so a config naming it still compiles; the page does not
  use it, and the line can be dropped from `extra_live_session_on_mount`.
- **A letter's body.** A letter has one Leaf editor instead of the text,
  Markdown and HTML fields and the conversion buttons. The first *Save* of a
  body writes the Markdown file and derives the text file from it, replacing a
  hand-written text file; for what that changes in the sent letter, see
  «What the first save changes» above. A letter with a hand-written HTML file
  keeps that file in a code field.
- **A new dependency**: `leaf` (see above for its JavaScript).

## Who sees the page

PhoenixKit routes the Settings item for the module's own key,
`templates_editor`; a route carries one key, so the page asks the whole rule
itself, when it opens and again whenever PhoenixKit refreshes the scope: the
module is on and the user holds `settings` **and** `templates_editor`.

| To | A role needs |
|---|---|
| open the page | `settings` and `templates_editor`, with the module switched on |
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
  preview: {MyApp.Emails, :preview},                    # (name, locale) -> {subject, html, text}, see below
  sample_variables: {MyApp.Emails, :sample_variables},  # () -> map
  block_placeholders: ["documents_list"],
  catalog: true

# config/dev.exs — only where templates are edited
config :phoenix_kit_templates_editor, editable: true
```

| Key | Default | Meaning |
|---|---|---|
| `root` | first of `PhoenixKit.Email.Content.override_paths/0` | the templates directory; it must exist |
| `editable` | `false` | `true` allows writing, `false` shows the files read-only; any other value is a config error (the page lists it, no editor). Leave it unset in production |
| `name_prefixes` | `[]` | which templates the editor sees and may write — nothing until you say. A prefix shaped like a layout part (`_header-shop`) allows that part of layout `shop` and `shop-…`, not every name starting with the string |
| `locales` | PhoenixKit's enabled languages (base codes), else just `base_locale` | the languages of the switcher, in order |
| `base_locale` | first of `locales`, else PhoenixKit's default language, else `"en"` | the language labels and notes fall back to |
| `layout_group` | `nil` | the layout (`_header-<g>`, `_footer-<g>`, `_layout-<g>`) of an email without `layout.txt` |
| `layout_groups` | `[layout_group]` | layout namespaces the editor may show and create: `g` and `g-…` (not `gx`) |
| `preview` | `nil` | your preview callback (below); without one the module renders its own |
| `sample_variables` | `%{}` | a map, or a callback returning one (below) |
| `describe_variables` | `nil` | `(name) -> %{variable => description}`, shown in the variables panel (below) |
| `complete?` | `nil` | `(name, base_locale) -> boolean` (below); default: subject and body on `base_locale` |
| `sent_by` | `nil` | `(name) -> :core \| :host` — who sends the email (below); default: PhoenixKit for the emails of its catalogue, your app for your own |
| `test_send` | `nil` | `(name, locale, user)` — your own way to send "Send to me" for your own emails (below); default, and always for the emails PhoenixKit and its modules send: `PhoenixKit.Mailer` |
| `block_placeholders` | `[]` | variables that stand as a block of their own |
| `raw_variables` | `[]` | variables allowed in `{{{x}}}` besides `content`, `header`, `footer` |
| `email_fallback` | `true` | whether emails get the *Default* entry (the locale-less files) in the language switcher |
| `shared_layout_editable` | `false` | whether the shared `_header`/`_footer`/`_layout` (PhoenixKit's own system emails) may be edited |
| `overridable` | `[]` | which emails PhoenixKit and its modules send may be given a file here — none until you say: a list — exactly those names; `:all`, your explicit choice — every one but the emails about getting into an account (account confirmation, password reset, email change, magic link sign-in and registration, organization invitation, the new-login and failed-sign-in alerts), which only a list names; "every one but" is this package's own list of those emails (`Names.auth_emails/0`), not core's current set, so a sign-in email a newer core adds is overridable under `:all` until the package is updated |
| `catalog` | `false` | whether your templates are offered to PhoenixKit's email preview |
| `watch` | same as `editable` | whether the files are re-read when they change on disk |
| `max_templates` | `500` | the most templates the root may hold: a new one past it is refused (`nil` — no limit) |
| `max_root_bytes` | `52_428_800` (50 MiB) | the most bytes the root's files may take: a save, copy or new file past it is refused (`nil` — no limit) |

A config that does not check out is shown on the page as a list of problems —
the page itself keeps working.

### Callbacks

Each is `{module, function}` or a function of the arity shown. One that raises,
throws or exits is logged and never takes the page down.

- **`preview(name, locale)`** — the preview of the template open in the editor.
  `name` is one of your emails, an email PhoenixKit or a module sends once it
  has files here, or a layout part: `_header-<g>`, `_footer-<g>`, `_layout-<g>`
  (and the shared `_header`, `_footer`, `_layout` with
  `shared_layout_editable: true`). `locale` is `nil` for the *Default* entry.
  Return `{subject, html}`, `{subject, html, text}` — each a string or `nil`;
  a `{:safe, iodata}` is escaped like a string — or `{:error, reason}`, shown
  in your words. Anything else is shown as an error. It runs with a 5 s
  deadline, past which the preview says it is too slow; it is not called for a
  template with no files yet, nor while the template or its layout has a file
  the module will not read (see *What is never read*).
- **`sample_variables()`** — or a plain map: your emails' variables,
  `%{name => sample}`, read when the page is mounted. Anything but a map is
  logged and taken as `%{}`.
- **`describe_variables(name)`** — `%{variable => description}` for the
  variables panel of template `name`, layout parts included. Descriptions that
  are not strings are left out; any other answer describes nothing.
- **`complete?(name, base_locale)`** — asked for each of your emails (no
  leading `_`) on every listing; only `false` flags the email in the list: it
  will not be offered for sending.
- **`sent_by(name)`** — `:core` or `:host` for the open template; any other
  answer is the default (PhoenixKit for the emails of its catalogue, your app
  for your own).
- **`test_send(name, locale, user)`** — "Send to me" for one of your own
  emails: never a layout part, never an email PhoenixKit or a module sends
  (those go through `PhoenixKit.Mailer`, as they do for real). `locale` is the
  open language's, `base_locale` for *Default*; `user` is the user asking, once
  the module has checked that the page says who it is, that they may see the
  page and that they sent none in the last 30 s. Return `{:ok, address}` when
  it went elsewhere than to the user (your test mode, say — the notice names
  that address), `:ok` or `{:ok, _}` when it went to the user, or
  `{:error, reason}`. It runs in the page's process with no deadline: keep it
  fast.

## The page

- **Screen.** The list of templates on the left, the open template on the
  right; on a phone the list is the first screen and a chosen template the
  second, with a *Back to the list* button. The language is chosen with
  PhoenixKit's language switcher — the languages of `locales`, named by
  PhoenixKit's list — and the files without a language are its last entry,
  *Default*. The variables and the preview are collapsible sections. There is
  no introduction or hint text at the top, and the project's own
  `README.<language>.md` beside the templates is not shown on the page (the
  files stay in the folder; the template list skips files in the root).
- **Not committed yet.** Where `editable: true`, a button lists the files under
  the root that differ from git's last commit, and the list refreshes after
  every change made in the editor. Git runs without the repository's hooks or
  `GIT_*` variables and never rewrites the index.
- **Layouts.** A layout `g` is `_header-g`, `_footer-g` and `_layout-g`; a part
  it lacks comes from the shared `_header`/`_footer`/`_layout`, else
  PhoenixKit's own. The page lists the layouts in `layout_groups` — the default
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
  each language — until it has a file here. Where `overridable` allows it (none
  by default, see `overridable`), a
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
  (`sent_by`) says the files are what it uses. Turning that database row into
  the files is offered only while the email has none ("Create file from the
  database template"); once it has, there is no button to overwrite them from
  the row — the row is exported by the Emails module's own task and the files
  merged by hand. Not done yet: decided, not forgotten.
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
  read-only servers included. Your `test_send` callback sends your own emails
  if you give one; `PhoenixKit.Mailer` sends the rest, and the emails
  PhoenixKit and its modules send always.
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
- **Converters.** For a header, footer or layout, *Fill text from content* and
  *Markdown → HTML* keep `{{placeholders}}` as typed (link targets too); a
  variable in `block_placeholders` alone in a paragraph comes out of the `<p>`.
  A letter has no such buttons: its text is derived on *Save* with the same
  `to_text` (the host's, else the module's own), and Leaf's Markdown is put
  right first: a placeholder Leaf percent-encoded in a link target
  (`%7B%7Bname%7D%7D`) is written back as `{{name}}`, a `\_` Leaf put inside
  `{{…}}` loses its backslash, and Leaf's bare line breaks become explicit
  ones (a trailing `\`), so the email shows them.
- **Files changed on disk.** Where the files are edited (or `watch: true`), the
  module looks at them every 2 s and drops PhoenixKit's cached templates when
  they change — a hand edit or a `git pull` shows in the next email. It then
  broadcasts `{:templates_editor, :files_changed}` on
  `PhoenixKitTemplatesEditor.Watcher.topic/0` through PhoenixKit's PubSub, for
  a page of your own that shows something made of the files (the page itself
  does not listen).
- **Preview emails.** With `catalog: true` your emails (names under
  `name_prefixes`, no leading `_`) appear in PhoenixKit's *Preview emails* —
  provided `root` is the directory PhoenixKit reads emails from
  (`config :phoenix_kit, :template_paths`); otherwise the page says so.
- **What is never read.** A template file that is a symbolic link, leads out of
  the root or is larger than 256 KiB is shown as unavailable, never read. A
  template with such a file is not previewed, sent to you or copied, and its
  layout's are not either: PhoenixKit's own lookup follows links.

## What this module does NOT do

- **Ship templates.** No header, footer or email text comes with it; they are
  your app's files.
- **Write in production by default.** `editable` is off unless your config says
  `true`; template changes reach production through your repository and deploy.
- **Commit to git.** It writes files; committing them is yours.
- **Change file owners.** Writes keep the server's user; group access comes
  from the setgid root (above).
- **Grant access beyond `settings`.** The page needs `settings` as well as the
  module's key.
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
