defmodule PhoenixKitTemplatesEditor.Web.Editor.PanelHelpers do
  @moduledoc false
  use Gettext, backend: PhoenixKitTemplatesEditor.Gettext

  # The lists: `flex-nowrap` and `min-w-0` keep daisyUI's menu (which wraps and
  # never shrinks its items) inside the column, whatever the key's length.
  def list_class, do: "menu menu-sm w-full min-w-0 flex-nowrap p-0"

  def list_button_class,
    do: "h-auto w-full min-w-0 flex-col items-start gap-0.5 py-1 text-left font-normal"

  # Beside a folding section's title, left of its arrow.
  def section_actions_class, do: "absolute right-10 top-1.5 z-10 flex items-center gap-1"

  def pre_class(extra \\ "p-3 text-sm"),
    do: "whitespace-pre-wrap break-words rounded-box bg-base-200 #{extra}"

  def part_title(:label), do: gettext("Label")
  def part_title(:subject), do: gettext("Subject")
  def part_title(:text), do: gettext("Text")
  def part_title(:markdown), do: gettext("Markdown")
  def part_title(:html), do: gettext("HTML")

  def kind_title(:header), do: gettext("Header")
  def kind_title(:footer), do: gettext("Footer")
  def kind_title(:layout), do: gettext("Page layout")

  def part_source(:own), do: gettext("its own, not editable here")
  def part_source(:shared), do: gettext("inherited: the shared one")
  def part_source(:core), do: gettext("inherited: core’s default")
end
