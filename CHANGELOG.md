# Changelog

## 0.1.0 — unreleased

### Added

- `PhoenixKitTemplatesEditor` as a `PhoenixKit.Module`: key `templates_editor`,
  off by default (`templates_editor_enabled`), a card on Admin › Modules, the
  permission `templates_editor` with the sub-permission `templates_editor.write`.
- The "Email templates" section on Settings › Emails Transactional, with a
  button beside "Preview emails"; for now it checks the config and shows a
  placeholder.
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
  with a delete button.
- Translations: English, Estonian, Russian.
