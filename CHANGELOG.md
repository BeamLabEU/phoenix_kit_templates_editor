# Changelog

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
