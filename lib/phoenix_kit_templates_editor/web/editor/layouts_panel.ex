defmodule PhoenixKitTemplatesEditor.Web.Editor.LayoutsPanel do
  @moduledoc false
  use Phoenix.Component
  use Gettext, backend: PhoenixKitTemplatesEditor.Gettext

  import PhoenixKitTemplatesEditor.Web.Editor.PanelHelpers
  import PhoenixKitWeb.Components.Core.Accordion, only: [accordion: 1]
  import PhoenixKitWeb.Components.Core.Badge, only: [status_badge: 1]
  import PhoenixKitWeb.Components.Core.Button, only: [button: 1]
  import PhoenixKitWeb.Components.Core.Modal, only: [modal: 1]
  import PhoenixKitWeb.Components.Core.Icon, only: [icon: 1]
  import PhoenixKitWeb.Components.Core.Input, only: [input: 1]
  import PhoenixKitWeb.Components.Core.Select, only: [select: 1]
  import PhoenixKitWeb.Components.Core.PopoverPanel
  alias Phoenix.LiveView.JS
  alias PhoenixKitTemplatesEditor.Names

  def layouts_panel(assigns) do
    ~H"""
    <div :if={@layouts != []} class="relative min-w-0">
      <.accordion
        id={"#{@id}-layouts"}
        open={is_binary(@selected) and String.starts_with?(@selected, "_")}
        title_class="!py-2 !min-h-0"
      >
        <:title>{gettext("Layouts")}</:title>
        <:content>
          <div class="flex min-w-0 flex-col gap-2">
            <.layout_entry
              :for={layout <- @layouts}
              id={"#{@id}-layout-#{layout.group}"}
              layout={layout}
              selected={@selected}
              templates={@templates}
              can_delete={@can_edit && layout.group in @layout_sources}
              emails={@layout_emails[layout.group]}
              myself={@myself}
            />

            <.modal
              show={@confirm_layout_delete != nil}
              id={"#{@id}-layouts-delete"}
              on_close="cancel_delete_layout"
            >
              <:title>
                <.icon name="hero-exclamation-triangle" class="size-5 text-warning" />
                {gettext("Delete")}
              </:title>
              <p class="text-sm">
                {gettext(
                  "Delete the layout “%{name}”: its own header, footer and page layout, in every language?",
                  name: @confirm_layout_delete
                )}
              </p>
              <:actions>
                <.button
                  id={"#{@id}-layouts-delete-cancel"}
                  type="button"
                  variant="ghost"
                  size="sm"
                  phx-click="cancel_delete_layout"
                  phx-target={@myself}
                >
                  {gettext("Cancel")}
                </.button>
                <.button
                  id={"#{@id}-layouts-delete-confirm"}
                  type="button"
                  variant="error"
                  size="sm"
                  phx-click="confirm_delete_layout"
                  phx-target={@myself}
                >
                  {gettext("Delete")}
                </.button>
              </:actions>
            </.modal>
          </div>
        </:content>
      </.accordion>
      <div class={section_actions_class()}>
        <div :if={@can_edit && @layout_sources != []} class="relative">
          <.button
            id={"#{@id}-layouts-create-open"}
            type="button"
            variant="ghost"
            size="xs"
            class="btn-square"
            title={gettext("New layout")}
            aria-label={gettext("New layout")}
            phx-click={toggle_popover("#{@id}-layouts-create-box")}
          >
            <.icon name="hero-plus" class="size-4" />
          </.button>
          <.popover_panel
            id={"#{@id}-layouts-create-box"}
            align="start"
            width_class="sm:w-72"
            class="p-4 max-sm:!top-20"
          >
            <div class="flex flex-col gap-2">
              <span class="text-sm font-semibold">{gettext("New layout")}</span>
              <form
                id={"#{@id}-layouts-create"}
                phx-submit={
                  JS.push("create_layout", target: @myself)
                  |> hide_popover("#{@id}-layouts-create-box")
                }
                phx-target={@myself}
                class="flex flex-col gap-2"
              >
                <.input
                  type="text"
                  name="layout_create[name]"
                  value={layout_name_start(@rules)}
                  aria-label={gettext("Layout name")}
                  class="input-sm font-mono"
                  placeholder={gettext("name")}
                  autocomplete="off"
                />
                <.select
                  name="layout_create[copy_from]"
                  aria-label={gettext("Start from")}
                  class="select-sm"
                  options={
                    for group <- @layout_sources,
                        do: {gettext("Copy of layout %{name}", name: group), group}
                  }
                  value={nil}
                />
                <.button type="submit" variant="outline" size="sm">
                  {gettext("Create layout")}
                </.button>
              </form>
            </div>
          </.popover_panel>
        </div>
      </div>
    </div>
    """
  end

  defp layout_name_start(rules) do
    case Names.namespaces(rules) do
      [namespace | _] -> namespace <> "-"
      [] -> ""
    end
  end

  attr(:id, :string, required: true)
  attr(:layout, :map, required: true)
  attr(:selected, :string, default: nil)
  attr(:templates, :list, required: true)
  attr(:can_delete, :boolean, default: false)
  attr(:emails, :string, required: true)
  attr(:myself, :any, required: true)

  # One layout: its parts, each its own (opens in the editor) or inherited,
  # and the emails using it.
  defp layout_entry(assigns) do
    assigns = assign(assigns, shown: MapSet.new(assigns.templates, & &1.name))

    ~H"""
    <div id={@id} class="flex min-w-0 flex-col gap-1 rounded-box border border-base-300 p-2">
      <div class="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1">
        <span class="min-w-0 break-all font-mono text-sm font-semibold">{@layout.group}</span>
        <.status_badge :if={@layout.default?} status="default" label={gettext("default")} size={:xs} />
        <.button
          :if={@can_delete}
          id={"#{@id}_delete"}
          type="button"
          variant="ghost"
          size="xs"
          class="ml-auto text-error"
          phx-click="delete_layout"
          phx-value-group={@layout.group}
          phx-target={@myself}
        >
          {gettext("Delete")}
        </.button>
      </div>
      <ul class={list_class()}>
        <li :for={part <- @layout.parts} id={"#{@id}_#{part.kind}"} class="min-w-0">
          <.button
            :if={part.source == :own and MapSet.member?(@shown, part.name)}
            variant="ghost"
            type="button"
            phx-click="select"
            phx-value-name={part.name}
            phx-target={@myself}
            class={[list_button_class(), part.name == @selected && "menu-active"]}
          >
            <span class="w-full break-words">{kind_title(part.kind)}</span>
            <span class="w-full break-all font-mono text-xs opacity-60">{part.name}</span>
          </.button>
          <span
            :if={part.source != :own or not MapSet.member?(@shown, part.name)}
            class="pointer-events-none flex w-full min-w-0 flex-col items-start gap-0"
          >
            <span class="opacity-70">{kind_title(part.kind)}</span>
            <span class="break-words text-xs opacity-60">{part_source(part.source)}</span>
          </span>
        </li>
      </ul>
      <p id={"#{@id}_emails"} class="break-words text-xs opacity-70">{@emails}</p>
    </div>
    """
  end
end
