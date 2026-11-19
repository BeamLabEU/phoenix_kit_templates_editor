defmodule PhoenixKitTemplatesEditor.Web.Editor.VariablesPanel do
  @moduledoc false
  use Phoenix.Component
  use Gettext, backend: PhoenixKitTemplatesEditor.Gettext

  import PhoenixKitWeb.Components.Core.Accordion, only: [accordion: 1]
  import PhoenixKitWeb.Components.Core.Button, only: [button: 1]
  import PhoenixKitWeb.Components.Core.Badge, only: [status_badge: 1]

  attr(:id, :string, required: true)
  attr(:rows, :list, required: true)
  attr(:form, :string, default: nil)
  attr(:leaf, :any, default: nil)

  # The variables of a part: a button each that puts it into the form
  # (`form`), or, read only, just the names. Collapsible, closed at first.
  def variables_panel(assigns) do
    ~H"""
    <.accordion id={@id}>
      <:title>{gettext("Variables")}</:title>
      <:content>
        <ul
          id={"#{@id}-list"}
          phx-hook={if(@leaf, do: "PhoenixKitTemplatesEditorKeepFocus")}
          class="flex min-w-0 flex-col gap-2 text-sm"
        >
          <li
            :for={row <- @rows}
            id={"#{@id}-#{row.name}"}
            class="flex min-w-0 flex-wrap items-baseline gap-x-2 gap-y-1"
          >
            <.button
              :if={@form}
              type="submit"
              variant="outline"
              size="xs"
              class="font-mono"
              form={@form}
              name="action"
              value={"insert:#{row.name}"}
              data-variable={placeholder(row)}
            >
              {placeholder(row)}
            </.button>
            <%!-- A letter's variable goes into Leaf at its caret. The button does not
                 take the focus (the module's hook on the list stops its mousedown), or
                 the caret would be gone by the click. --%>
            <.button
              :if={@leaf}
              type="button"
              variant="outline"
              size="xs"
              class="font-mono"
              phx-click="insert_variable"
              phx-value-name={row.name}
              phx-target={@leaf}
              data-keep-focus
            >
              {placeholder(row)}
            </.button>
            <code :if={!@form and !@leaf} class="break-all font-mono">{placeholder(row)}</code>
            <span :if={row.sample not in [nil, ""]} class="break-all font-mono text-xs opacity-60">
              {row.sample}
            </span>
            <span :if={row.description} class="break-words text-xs">{row.description}</span>
            <.status_badge
              :if={row.scope == :markdown}
              status="markdown"
              label={gettext("Markdown only")}
              size={:xs}
            />
            <.status_badge
              :if={row.scope == :html}
              status="html"
              label={gettext("rendered HTML, three braces")}
              size={:xs}
            />
          </li>
        </ul>
      </:content>
    </.accordion>
    """
  end

  def placeholder(%{scope: :html, name: name}), do: "{{{#{name}}}}"
  def placeholder(%{name: name}), do: "{{#{name}}}"
end
