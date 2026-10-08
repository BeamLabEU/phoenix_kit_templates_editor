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
- Translations: English, Estonian, Russian.
