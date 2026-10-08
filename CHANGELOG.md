# Changelog

## 0.1.0 — unreleased

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
  root, `0664`/`2775` after a write (no ownership changes), `git status`
  without hooks or `GIT_*` variables and with a deadline, `safe_read/2`
  refusing links, paths out of the root and oversized files.
- `PhoenixKitTemplatesEditor.Watcher`: where files are edited or watched, a
  change on disk drops the cache within 2 s.
- `PhoenixKitTemplatesEditor.Converters` and `PhoenixKitTemplatesEditor.HtmlText`
  (moved from Andi): Markdown/HTML to text and Markdown to HTML with
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
- Translations: English, Estonian, Russian.
