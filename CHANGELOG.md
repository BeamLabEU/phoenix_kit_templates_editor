# Changelog

## 0.3.0 - 2026-11-23

### Added

- **The editor has a page of its own**, Settings › Email templates
  (`/admin/settings/email-templates`): a Settings item (`settings_tabs/0`)
  that core routes for the `templates_editor` permission, with the page
  asking the whole rule itself (`accessible?/1` — the module on, `settings`
  and `templates_editor`) at mount and on every render. Core's email settings
  page keeps no section of this module (`email_settings_sections/0` is `[]`).
- **A letter's body is one Leaf editor** (new dependency `leaf`,
  `~> 0.11.0 or ~> 0.12.0 or ~> 0.13.0`; core 3.5 and later loads its
  JavaScript itself, through its lazy `Leaf` hook in
  `window.PhoenixKitHooks`): visual or Markdown mode, never hybrid or HTML.
  A save writes the Markdown file and derives the text file from it; a
  text-only letter opens with its text turned into Markdown, and nothing is
  written until Save. `PhoenixKitTemplatesEditor.Body` keeps the round trip
  exact: line breaks, the placeholders Leaf percent-encodes or
  backslash-escapes, and the room a frame letter leaves on purpose.
- **The open template in the page's address** (`?template=`), language tabs
  as on other forms, folding list sections whose state the browser keeps,
  create forms and the layout choice in small panels, a back button on
  phones, and the module's three JS hooks
  (`PhoenixKitTemplatesEditorInsertVariable`,
  `PhoenixKitTemplatesEditorKeepFocus`, `PhoenixKitTemplatesEditorFolds`).

### Changed

- **The page shows no introduction, hints or `README.<language>.md` notes**,
  and the scope comes from the page's own assign:
  `PhoenixKitTemplatesEditor.Web.ScopeHook` is no longer used by the page
  (the module stays, so a host config naming it still compiles).
- **The editor's internals are split**: the layouts, module emails, variables
  and preview panels are function-component modules, and the save, conflict
  and layout actions plain modules; the controls are core's components.

### Fixed

- **Core 3.7's `app_connected` notice is a sign-in email**
  (`Names.auth_emails/0`): it tells an account that an application was
  connected to it through the OAuth sign-in, and `overridable: :all` no
  longer lets a host replace it.
- **A save or a document switch waits for Leaf's final edit**: the editor
  asks the focused Leaf to flush and runs the action on the matching
  acknowledgement, so a debounced last keystroke can no longer be lost or
  carried into the next document.
- **A letter's text version is made in one bounded task** (not one per
  section, each with its own deadline), and **a layout copy counts its
  source files against the root's byte limit before creating anything**.

## 0.2.1 - 2026-11-15

### Fixed

- **Core 3.6's passkey notices are sign-in emails** (`Names.auth_emails/0`):
  `passkey_added` and `passkey_removed` warn an account's owner of a change
  to how it signs in, and `overridable: :all` no longer lets a host replace
  them. On 0.2.0 with core 3.6 they were overridable.

### Changed

- **Core floor raised to 3.5.0** (`>= 3.5.0 and < 4.0.0`), the ecosystem-wide
  minimum; the fallbacks for older cores are gone.
- **`phoenix_kit_templates` `~> 0.2.5`**: the converters and the save check read
  placeholders with `Substitution.split/1`, the grammar the renderer
  substitutes by, instead of a copy of its regex.
- **The JS bundle is admin-scoped** (`scope: :admin`, its hook listed): on core
  3.6 public pages no longer download it. An older core ignores both keys.

## 0.2.0 - 2026-10-27

### Changed

- **Core pin widened to accept core 3.x** (ceiling `< 4.0.0`; the floor is unchanged).

## 0.1.0 - 2026-10-10

### Added

- `PhoenixKitTemplatesEditor` as a `PhoenixKit.Module`: key `templates_editor`,
  off by default (`templates_editor_enabled`), a card on Admin › Modules, the
  permission `templates_editor` with the sub-permission `templates_editor.write`.
- The "Email templates" section on Settings › Emails Transactional, with a
  button beside "Preview emails": an introduction, hints, the project's
  `README.<language>.md` from the templates root, the files not committed to
  git (on a button and after every change), and the editor wired to the
  config. Writing needs `editable: true` and `templates_editor.write`, checked
  through `PhoenixKitTemplatesEditor.Web.ScopeHook` (a live-session hook the
  host adds).
- `PhoenixKitTemplatesEditor.Files`: cache reload under every path naming the
  root; no mode or owner changed after a write (they come from a setgid root
  and the server's umask, see the README); `git status` without hooks, filter
  drivers or `GIT_*` variables, with a deadline and its stderr dropped;
  `safe_read/2` refusing links, paths out of the root and oversized files.
- `PhoenixKitTemplatesEditor.Watcher`: where files are edited or watched, a
  change on disk drops the cache within 2 s.
- `PhoenixKitTemplatesEditor.Converters` and `PhoenixKitTemplatesEditor.HtmlText`
  (extracted from a host application): Markdown/HTML to text and Markdown to HTML with
  placeholders kept, size limit, deadline, linear-time patterns.
- `PhoenixKitTemplatesEditor.Preview`: the default preview in the email's
  layout group; `PhoenixKitTemplatesEditor.Catalog`: the host's emails for
  core's "Preview emails" with `catalog: true`.
- `tab_path/1`, `accessible?/1` and `authorize/2` for hosts and for per-event
  checks.
- `PhoenixKitTemplatesEditor.Config`: reads and checks
  `config :phoenix_kit_templates_editor`, returning every problem instead of
  raising.
- `PhoenixKitTemplatesEditor.Web.Editor`, the editor component moved from
  `phoenix_kit_templates` 0.2.4 (`PhoenixKit.Templates.Editor`), now in the
  page's language. New: every change checks `editable` and the host's
  `authorize` on the server; an email incomplete in the base language is
  flagged (`base_locale`, `complete?`); `email_fallback: false` hides an
  email's unused Fallback tab, showing left-over locale-less files read-only
  with a delete button. Every file is read through `Files.safe_read/2`; the
  preview frame has `referrerpolicy="no-referrer"` and a `csp` allowing
  images only inline and from the host's origins.
- Layouts (`_header-<g>`, `_footer-<g>`, `_layout-<g>`) in the editor: the
  layouts of `layout_groups` with their own and inherited parts and the emails
  using each, a new layout as a copy of another, deleting one no email uses,
  and an email's layout choice (`layout.txt`). The default preview shows a
  layout's part around the first email using it.
- `PhoenixKitTemplatesEditor.Names`: the shared layout parts only with
  `shared_layout_editable: true`, the emails core and other modules send never,
  layout groups by exact namespace (a prefix `_header-shop` no longer allows
  `_header-shopx`). `PhoenixKitTemplatesEditor.Layouts`: a root's layouts.
- A copy of a template lists the host's own files in it to leave out.
- Module emails: the emails core and other modules send, read only until
  given a file — from the built-in text by language, or from the Emails
  module's active database template by its export — where `overridable`
  allows it: none by default, a list by name, or `overridable: :all` as an
  explicit choice of every one but core's sign-in emails (which carry a
  warning wherever shown). A module's own layout group the same way.
  `PhoenixKitTemplatesEditor.Overriding`.
- What is sent: for an email core sends, the source of each part through
  core's resolution, with a red notice when a database template wins over the
  file (`PhoenixKitTemplatesEditor.Sources`); an email the host sends says so
  (`sent_by`).
- The variables panel (`PhoenixKitTemplatesEditor.Variables`): a part's
  variables by its kind of template with samples and the host's
  descriptions, inserted at the cursor by a JS hook (`js_sources/0`) or at
  the end of the body without it; saves checked — a variable of the other kind
  only after "Save anyway", an unknown one with a warning, `{{{x}}}` only for
  `raw_variables` and a layout's `content`/`header`/`footer`, a subject one
  line of at most 998 bytes.
- Send to me (`PhoenixKitTemplatesEditor.TestSend`, `Throttle`): to the user
  asking only, once in 30 s, logged; the host's own emails by its
  `test_send`, if any, the rest by `PhoenixKit.Mailer`.
- A part changed on disk since it was opened is not saved over; *Reload*
  reads the files again.
- Every change in PhoenixKit's activity log (`PhoenixKitTemplatesEditor.Journal`).
- Translations: English, Estonian, Russian.
