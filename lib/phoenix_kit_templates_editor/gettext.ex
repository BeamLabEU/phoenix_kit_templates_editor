defmodule PhoenixKitTemplatesEditor.Gettext do
  @moduledoc """
  Gettext backend for the module's own translations (`priv/gettext`: en, et,
  ru).

  The section components `use PhoenixKitWeb, :live_component`, which binds the
  `gettext/1` macros to core's `PhoenixKitWeb.Gettext`; they additionally
  `use Gettext, backend: PhoenixKitTemplatesEditor.Gettext`, which rebinds them
  here. The locale is the process-global one core sets for its own LiveViews,
  so the module never sets it.

  Core stores the resolved dialect as the locale (`en` becomes `en-US`), so a
  new catalog is named by the dialect code; `et` and `ru` map to themselves.
  """
  use Gettext.Backend, otp_app: :phoenix_kit_templates_editor
end
