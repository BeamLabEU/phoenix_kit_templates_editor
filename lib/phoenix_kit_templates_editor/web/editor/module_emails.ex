defmodule PhoenixKitTemplatesEditor.Web.Editor.ModuleEmails do
  @moduledoc false
  use Phoenix.Component
  use Gettext, backend: PhoenixKitTemplatesEditor.Gettext

  import PhoenixKitTemplatesEditor.Web.Editor.PanelHelpers
  import PhoenixKitWeb.Components.Core.Accordion, only: [accordion: 1]
  import PhoenixKitWeb.Components.Core.Button, only: [button: 1]
  import PhoenixKitWeb.Components.Core.Badge, only: [status_badge: 1]
  import PhoenixKitTemplatesEditor.Web.Editor.VariablesPanel, only: [variables_panel: 1]
  alias PhoenixKitTemplatesEditor.Files
  alias PhoenixKitWeb.Components.LanguageSwitcher

  def module_emails_list(assigns) do
    ~H"""
    <%!-- Folded: the emails core and the modules send are looked at
         rarely, and the list is long. Open when one of them is. --%>
    <.accordion
      :if={@module_list != [] or @module_layouts != []}
      id={"#{@id}-module-emails"}
      open={@module_selected != nil}
      title_class="!py-2 !min-h-0"
    >
      <:title>{gettext("Module emails")}</:title>
      <:content>
        <div class="flex min-w-0 flex-col gap-2">
          <ul :if={@module_list != []} class={list_class()}>
            <li :for={item <- @module_list} class="min-w-0">
              <.button
                variant="ghost"
                type="button"
                phx-click={if(item.template?, do: "select", else: "select_module")}
                phx-value-name={item.name}
                phx-target={@myself}
                class={[
                  list_button_class(),
                  item.name in [@selected, @module_selected] && "menu-active"
                ]}
              >
                <span class="w-full break-words">{item.label}</span>
                <span class="w-full break-all font-mono text-xs opacity-60">{item.name}</span>
                <span>
                  <.status_badge
                    status={if(item.file?, do: "file", else: "built_in")}
                    label={if(item.file?, do: gettext("file"), else: gettext("built-in text"))}
                    size={:xs}
                  />
                </span>
              </.button>
            </li>
          </ul>
          <div
            :for={layout <- @module_layouts}
            id={"#{@id}-module-layout-#{layout.group}"}
            class="flex min-w-0 flex-col gap-1 rounded-box border border-base-300 p-2"
          >
            <span class="break-all font-mono text-sm font-semibold">{layout.group}</span>
            <div
              :for={part <- layout.parts}
              class="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm"
            >
              <span class="opacity-70">{kind_title(part.kind)}</span>
              <span :if={part.file?} class="text-xs opacity-60">{gettext("has its own file")}</span>
              <span :if={!part.file?} class="text-xs opacity-60">
                {part_source(part.inherited)}
              </span>
              <.button
                :if={!part.file? && @can_edit && part.overridable?}
                id={"#{@id}-module-layout-#{layout.group}-#{part.kind}-create"}
                type="button"
                variant="outline"
                size="xs"
                class="ml-auto"
                phx-click="override_layout"
                phx-value-name={part.name}
                phx-target={@myself}
              >
                {gettext("Create file")}
              </.button>
            </div>
          </div>
        </div>
      </:content>
    </.accordion>
    """
  end

  def module_email(assigns) do
    ~H"""
    <div :if={@module_view} id={"#{@id}-module-email"} class="flex min-w-0 flex-col gap-3">
      <div class="flex min-w-0 flex-col gap-x-2 gap-y-2 sm:flex-row sm:flex-wrap sm:items-center">
        <div class="min-w-0 sm:flex-1">
          <h3 class="break-words text-lg font-semibold">
            {@module_view.entry[:label] || @module_selected}
          </h3>
          <span class="break-all font-mono text-sm opacity-60">{@module_selected}</span>
        </div>
        <.button
          :if={@can_test_send}
          id={"#{@id}-test-send"}
          type="button"
          variant="outline"
          size="sm"
          phx-click="test_send"
          phx-target={@myself}
        >
          {gettext("Send to me")}
        </.button>
      </div>
      <p :if={is_binary(@module_view.entry[:description])} class="text-sm opacity-70">
        {@module_view.entry[:description]}
      </p>
      <div
        :if={@can_edit && @module_view.overridable? && !@module_view.file?}
        id={"#{@id}-module-replace"}
        class="flex flex-col items-start gap-2"
      >
        <p class="text-sm">
          {gettext(
            "A file made here is this email's text from then on: translations a module update brings no longer reach this email."
          )}
        </p>
        <div class="flex flex-wrap gap-x-2 gap-y-2">
          <.button
            id={"#{@id}-module-create-default"}
            type="button"
            variant="primary"
            size="sm"
            phx-click="override_default"
            phx-value-name={@module_selected}
            phx-target={@myself}
          >
            {gettext("Replace with my own text")}
          </.button>
          <.button
            :if={@module_view.db?}
            id={"#{@id}-module-create-db"}
            type="button"
            variant="outline"
            size="sm"
            phx-click="override_db"
            phx-value-name={@module_selected}
            phx-target={@myself}
          >
            {gettext("Create file from the database template")}
          </.button>
        </div>
      </div>
      <div
        :if={!@module_view.overridable?}
        id={"#{@id}-module-email-not-overridable"}
        class="alert alert-info alert-soft text-sm"
      >
        {gettext(
          "This email is protected and shown read only. Which emails may be replaced here is set in the application's configuration (the `overridable` key)."
        )}
      </div>
      <LanguageSwitcher.language_switcher
        id={"#{@id}-module-languages"}
        languages={@module_language_items}
        current_language={@module_locale}
        on_click="module_locale"
        phx_target={@myself}
        variant={:tabs}
        size={:sm}
        display={:auto}
        auto_threshold={5}
        show_flags
        show_primary
        primary_divider
        class="w-full"
      />
      <.sources_box
        :if={@module_view.sources}
        id={"#{@id}-module-email-sources"}
        result={@module_view.sources}
        root={@root}
      />
      <div class="flex min-w-0 flex-col gap-2">
        <span class="text-sm font-semibold">{gettext("Built-in text")}</span>
        <%= case @module_view.defaults do %>
          <% {:ok, parts} -> %>
            <dl class="flex min-w-0 flex-col gap-2">
              <div
                :for={part <- Enum.filter([:subject, :markdown, :text, :html], &parts[&1])}
                class="min-w-0"
              >
                <dt class="text-sm opacity-70">{part_title(part)}</dt>
                <dd>
                  <pre class={pre_class()}>{parts[part]}</pre>
                </dd>
              </div>
            </dl>
          <% {:error, message} -> %>
            <p class="text-sm text-error">
              {gettext("Could not tell: %{reason}", reason: message)}
            </p>
        <% end %>
      </div>
      <.variables_panel
        :if={@module_view.variables != []}
        id={"#{@id}-module-email-variables"}
        rows={@module_view.variables}
      />
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:result, :any, required: true)
  attr(:own, :map, default: %{})
  attr(:root, :string, required: true)

  # Where each part of an email core sends comes from.
  def sources_box(assigns) do
    {sources, error} =
      case assigns.result do
        {:ok, sources} -> {sources, nil}
        {:error, message} -> {nil, message}
      end

    assigns = assign(assigns, sources: sources, error: error)

    ~H"""
    <div id={@id} class="flex min-w-0 flex-col gap-2 rounded-box border border-base-300 p-3 text-sm">
      <span class="font-semibold">{gettext("What is sent")}</span>
      <dl :if={@sources} class="grid grid-cols-[auto_minmax(0,1fr)] gap-x-3 gap-y-1">
        <%= for part <- [:subject, :text, :html, :markdown] do %>
          <dt class="opacity-70">{part_title(part)}</dt>
          <dd class="break-words">{source_label(@sources[part], @own[part], @root)}</dd>
        <% end %>
      </dl>
      <p :if={@sources && @sources.html == nil && @sources.html_from} class="text-xs opacity-70">
        {gettext("The HTML is made from the %{part}.", part: body_from(@sources.html_from))}
      </p>
      <p :if={@error} class="text-error">
        {gettext("Could not tell: %{reason}", reason: @error)}
      </p>
    </div>
    """
  end

  defp source_label(:db, _own, _root), do: gettext("the Emails module's database template")
  defp source_label({:file, path}, path, _root), do: gettext("this file")

  defp source_label({:file, path}, _own, root),
    do: gettext("the file %{file}", file: Files.relative(root, path))

  defp source_label({:blank_file, path}, _own, root),
    do: gettext("an empty file (%{file}): the part is left out", file: Files.relative(root, path))

  defp source_label(:default, _own, _root), do: gettext("built-in text")
  defp source_label(nil, _own, _root), do: gettext("none")

  defp body_from(:html), do: part_title(:html)
  defp body_from(:markdown), do: part_title(:markdown)
  defp body_from(:text), do: part_title(:text)
end
