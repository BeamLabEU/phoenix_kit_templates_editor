defmodule PhoenixKitTemplatesEditor.Web.Section do
  @moduledoc """
  What `PhoenixKitTemplatesEditor.Web.SettingsLive` shows: the host's config
  checked, the notices that matter, and the editor.

  A config that does not load (`PhoenixKitTemplatesEditor.Config`) is shown
  as an error here rather than taking the page down. The section:

    * says, where the files are editable but not by this user, why they are
      read only;
    * says when the templates directory is not the one core reads emails
      from (so "Preview emails" does not offer them);
    * where the files are editable, lists those not committed to git
      (`PhoenixKitTemplatesEditor.Files.uncommitted/1`): on a button only a
      writer has (asked again on the click, once in 5 s), and again after
      every change the editor makes — never on opening the page;
    * mounts `PhoenixKitTemplatesEditor.Web.Editor` with everything the
      config says.

  The project's own notes (`README.<locale>.md` beside the templates) are
  not shown on the page: the files stay where they are, for the people who
  work with the folder.

  ## Who may write

  `editable: true` in the config **and** `PhoenixKitTemplatesEditor.authorize(scope, :write)`
  — the module enabled, `settings`, `templates_editor` and
  `templates_editor.write`. Asked when the page renders (no form for anyone
  else) and again by the editor on every change. The scope is the page's
  `:phoenix_kit_current_scope`, handed in as an assign by the page
  (`PhoenixKitTemplatesEditor.Web.SettingsLive`); a section mounted without
  one is read only.

  The editor's `after_change` runs in the page's process, which has no
  `handle_info` for this component: it tells the section by `send_update/2`.
  """
  use PhoenixKitWeb, :live_component
  use Gettext, backend: PhoenixKitTemplatesEditor.Gettext

  alias PhoenixKit.Utils.Routes
  alias PhoenixKitTemplatesEditor.Catalog
  alias PhoenixKitTemplatesEditor.Config
  alias PhoenixKitTemplatesEditor.Converters
  alias PhoenixKitTemplatesEditor.Files
  alias PhoenixKitTemplatesEditor.Journal
  alias PhoenixKitTemplatesEditor.Preview
  alias PhoenixKitTemplatesEditor.TestSend
  alias PhoenixKitTemplatesEditor.Web.Editor

  @impl true
  def mount(socket), do: {:ok, assign(socket, uncommitted: nil, uncommitted_at: nil)}

  @impl true
  # From the editor's `after_change`: the files changed.
  def update(%{refresh_uncommitted: true}, socket), do: {:ok, assign_uncommitted(socket)}

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    case Config.load() do
      {:ok, config} -> {:ok, configure(socket, config)}
      {:error, messages} -> {:ok, assign(socket, config: nil, errors: messages)}
    end
  end

  @impl true
  # A writer's action (git runs as the server's user), asked again now, and
  # not more often than once in a few seconds.
  def handle_event("check_uncommitted", _params, socket) do
    now = System.monotonic_time(:millisecond)

    cond do
      socket.assigns.config == nil or socket.assigns.authorize.(:check) != :ok ->
        {:noreply, socket}

      recently?(socket.assigns.uncommitted_at, now) ->
        {:noreply, socket}

      true ->
        {:noreply, socket |> assign(uncommitted_at: now) |> assign_uncommitted()}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @uncommitted_interval_ms 5_000

  defp recently?(nil, _now), do: false
  defp recently?(last, now), do: now - last < @uncommitted_interval_ms

  defp configure(socket, config) do
    scope = socket.assigns[:phoenix_kit_current_scope]
    write = if config.editable, do: PhoenixKitTemplatesEditor.authorize(scope, :write)

    socket
    |> assign(
      config: config,
      errors: [],
      can_write: write == :ok,
      no_write: if(config.editable and write != :ok, do: no_write_reason(write)),
      catalog_off: config.catalog and not Catalog.root_read_by_core?(config),
      authorize: authorizer(scope),
      journal: journaller(scope)
    )
    |> assign_new(:module_emails, fn -> module_emails() end)
    |> then(&assign(&1, test_send: test_sender(config, scope, &1.assigns.module_emails)))
    |> assign_new(:sample_variables, fn -> Preview.sample_variables(config) end)
    |> assign_new(:image_origins, fn -> image_origins() end)
    |> assign_new(:callbacks, fn -> callbacks(socket.assigns.id, config) end)
  end

  # Asked by the editor on every change, with the scope the page gave last.
  defp authorizer(scope) do
    fn _action -> PhoenixKitTemplatesEditor.authorize(scope, :write) end
  end

  # The emails core and the other modules send (core's catalogue, in the
  # page's language), not the host's own this module offers it.
  defp module_emails, do: Catalog.core_entries()

  # "Send to me", to the user of the page at the moment of the click.
  defp test_sender(config, scope, module_emails) do
    fn name, locale ->
      entry = Enum.find(module_emails, &(&1.name == name))
      TestSend.deliver(config, scope, name, locale, entry)
    end
  end

  # Every change, in PhoenixKit's activity log, as done by the user then.
  defp journaller(scope) do
    fn event -> Journal.log(scope, event) end
  end

  # The editor's callbacks, made once: a new function on every update would
  # look like a new preview to the editor and render it again. The library
  # drops its cache for `root` on every write; `after_change`, which follows
  # every change, drops it once more under core's own paths to the root
  # (`Files.reload/1`) — no `after_write`, which would do it again.
  defp callbacks(id, %Config{root: root} = config) do
    blocks = config.block_placeholders

    %{
      preview: config.preview || fn name, locale -> Preview.preview(config, name, locale) end,
      convert: %{
        to_text: &Converters.to_text/2,
        markdown_to_html: &Converters.markdown_to_html(&1, block_placeholders: blocks)
      },
      after_change: fn _name ->
        Files.reload(root)
        send_update(__MODULE__, id: id, refresh_uncommitted: true)
        :ok
      end
    }
  end

  # Asked of git only where the files are editable, and only once the page
  # is live (a button, or a change).
  defp assign_uncommitted(%{assigns: %{config: %Config{editable: true, root: root}}} = socket) do
    if connected?(socket),
      do: assign(socket, uncommitted: Files.uncommitted(root)),
      else: socket
  end

  defp assign_uncommitted(socket), do: socket

  defp no_write_reason({:error, :disabled}),
    do: gettext("The templates editor is switched off: the templates are shown read only.")

  defp no_write_reason(_forbidden),
    do:
      gettext(
        "Editing needs the “%{permission}” permission: the templates are shown read only.",
        permission: gettext("Edit email templates")
      )

  # The site's own origin, for images (its logo) in the preview frame.
  defp image_origins do
    case URI.parse(Routes.base_url()) do
      %URI{scheme: scheme, host: host, port: port}
      when scheme in ["http", "https"] and is_binary(host) ->
        default_port = if scheme == "https", do: 443, else: 80
        ["#{scheme}://#{host}" <> if(port in [nil, default_port], do: "", else: ":#{port}")]

      _other ->
        []
    end
  rescue
    _ -> []
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="templates-editor-section" class="flex flex-col gap-4">
      <%!-- The title row stays one row on a phone too: the actions menu is laid
           over its right end instead of taking the admin header's `actions` row. --%>
      <div class="relative pr-12">
        <.admin_page_header
          back={Routes.path("/admin/settings")}
          back_label={gettext("Settings")}
          title={gettext("Email templates")}
          class="mb-0"
        />
        <div
          :if={@config != nil and @config.editable and @can_write}
          class="absolute inset-y-0 right-0 flex items-center"
        >
          <.table_row_menu
            id="templates-editor-actions"
            label={gettext("Actions")}
            trigger_size="md"
          >
            <.table_row_menu_button
              id="templates-editor-reload"
              phx-click="reload"
              phx-target="#templates-editor"
              icon="hero-arrow-path"
              label={gettext("Reload")}
              title={
                gettext("Read the templates again from disk: after a change by hand or a git pull.")
              }
            />
            <.table_row_menu_button
              id="templates-editor-uncommitted-check"
              phx-click="check_uncommitted"
              phx-target={@myself}
              icon="hero-code-bracket-square"
              label={gettext("Show what is not committed to git")}
            />
          </.table_row_menu>
        </div>
      </div>

      <div :if={@config == nil} role="alert" class="alert alert-error alert-soft">
        <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
        <div>
          <p class="font-semibold">
            {gettext("The templates editor is not configured correctly.")}
          </p>
          <ul class="list-disc list-inside text-sm">
            <li :for={message <- @errors}>{message}</li>
          </ul>
        </div>
      </div>

      <%= if @config do %>
        <div
          :if={@no_write}
          id="templates-editor-no-write"
          role="alert"
          class="alert alert-info alert-soft text-sm"
        >
          {@no_write}
        </div>

        <div
          :if={@catalog_off}
          id="templates-editor-catalog-off"
          role="alert"
          class="alert alert-warning alert-soft text-sm"
        >
          {gettext(
            "These templates are not offered to “Preview emails”: the templates directory is not the one the emails are read from."
          )}
        </div>

        <div :if={@config.editable and @can_write} class="flex flex-col items-start gap-2">
          <div
            :if={@uncommitted not in [nil, []]}
            id="templates-editor-uncommitted"
            class="alert alert-warning flex-col items-start text-sm"
          >
            <span>
              {gettext("Changed on this server and not yet committed to git:")}
            </span>
            <ul class="font-mono text-xs break-all">
              <li :for={path <- @uncommitted} data-path={path}>{path}</li>
            </ul>
          </div>
          <p
            :if={@uncommitted == []}
            id="templates-editor-uncommitted-none"
            class="text-sm text-base-content/60"
          >
            {gettext("Everything here is committed to git.")}
          </p>
        </div>

        <.live_component
          module={Editor}
          id="templates-editor"
          root={@config.root}
          editable={@can_write}
          show_reload={false}
          name_prefixes={@config.name_prefixes}
          layout_group={@config.layout_group}
          layout_groups={@config.layout_groups}
          shared_layout_editable={@config.shared_layout_editable}
          locales={@config.locales}
          base_locale={@config.base_locale}
          complete?={@config.complete?}
          email_fallback={@config.email_fallback}
          sample_variables={@sample_variables}
          raw_variables={@config.raw_variables}
          block_placeholders={@config.block_placeholders}
          describe_variables={@config.describe_variables}
          preview={@callbacks.preview}
          preview_image_origins={@image_origins}
          convert={@callbacks.convert}
          after_change={@callbacks.after_change}
          authorize={@authorize}
          journal={@journal}
          module_emails={@module_emails}
          overridable={@config.overridable}
          sent_by={@config.sent_by}
          test_send={@test_send}
          max_templates={@config.max_templates}
          max_root_bytes={@config.max_root_bytes}
        />
      <% end %>
    </div>
    """
  end
end
