defmodule PhoenixKitTemplatesEditor.Web.Section do
  @moduledoc """
  The "Email templates" tab of Settings › Emails Transactional.

  Core mounts it as `<.live_component module={…} id={:templates_editor} />`
  with no other assigns, so everything comes from the host's config
  (`PhoenixKitTemplatesEditor.Config`); a config that does not load is shown
  as an error here rather than taking the page down. The section:

    * introduces the files — editable here, or read only (neutral words: the
      module does not know the host's servers);
    * where the user may write, gives the general hints: what the
      converter buttons do, what the *Fallback* tab is, which variables only
      the header and footer have (`PhoenixKit.Email.Layout.render_parts/2`
      of `layout_group`, less the branding's);
    * shows the project's own notes, `README.<page language>.md`, else
      `README.<base_locale>.md`, else `README.md` in the templates root, as
      Markdown through core's sanitizer — read only too;
    * where the files are editable, lists those not committed to git
      (`PhoenixKitTemplatesEditor.Files.uncommitted/1`): on a button, and
      again after every change the editor makes — never on opening the tab;
    * mounts `PhoenixKitTemplatesEditor.Web.Editor` with everything the
      config says.

  ## Who may write

  `editable: true` in the config **and** `PhoenixKitTemplatesEditor.authorize(scope, :write)`
  — the module enabled, `settings`, `templates_editor` and
  `templates_editor.write`. Asked when the tab renders (no form for anyone
  else) and again by the editor on every change. The scope is the page's
  `:phoenix_kit_current_scope` as `PhoenixKitTemplatesEditor.Web.ScopeHook`
  keeps it (core passes the section none); without the hook the files are
  read only, and the tab says so.

  The editor's `after_change` runs in core's LiveView process, which has no
  `handle_info` for this component: it tells the section by `send_update/2`.
  """
  use PhoenixKitWeb, :live_component
  use Gettext, backend: PhoenixKitTemplatesEditor.Gettext

  require Logger

  alias PhoenixKit.Email.Branding
  alias PhoenixKit.Email.Layout
  alias PhoenixKit.Modules.Languages.DialectMapper
  alias PhoenixKit.Utils.Routes
  alias PhoenixKitTemplatesEditor.Catalog
  alias PhoenixKitTemplatesEditor.Config
  alias PhoenixKitTemplatesEditor.Converters
  alias PhoenixKitTemplatesEditor.Files
  alias PhoenixKitTemplatesEditor.Journal
  alias PhoenixKitTemplatesEditor.Preview
  alias PhoenixKitTemplatesEditor.TestSend
  alias PhoenixKitTemplatesEditor.Web.Editor
  alias PhoenixKitTemplatesEditor.Web.ScopeHook

  @impl true
  def mount(socket), do: {:ok, assign(socket, uncommitted: nil)}

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
  def handle_event("check_uncommitted", _params, socket),
    do: {:noreply, assign_uncommitted(socket)}

  defp configure(socket, config) do
    assigned_scope = socket.assigns[:phoenix_kit_current_scope]
    scope = current_scope(assigned_scope)
    write = if config.editable, do: PhoenixKitTemplatesEditor.authorize(scope, :write)

    socket
    |> assign(
      config: config,
      errors: [],
      can_write: write == :ok,
      no_write: if(config.editable and write != :ok, do: no_write_reason(scope, write)),
      readme: readme(config),
      catalog_off: config.catalog and not Catalog.root_read_by_core?(config),
      authorize: authorizer(assigned_scope),
      journal: journaller(assigned_scope)
    )
    |> assign_new(:module_emails, fn -> module_emails() end)
    |> then(&assign(&1, test_send: test_sender(config, assigned_scope, &1.assigns.module_emails)))
    |> assign_new(:sample_variables, fn -> Preview.sample_variables(config) end)
    |> assign_new(:layout_variables, fn -> layout_variables(config) end)
    |> assign_new(:image_origins, fn -> image_origins() end)
    |> assign_new(:callbacks, fn -> callbacks(socket.assigns.id, config) end)
  end

  # Core passes no scope (`:phoenix_kit_current_scope` is there only for a
  # host that mounts the section itself); the scope hook's is the page's.
  defp current_scope(nil), do: ScopeHook.current_scope()
  defp current_scope(scope), do: scope

  # Asked by the editor on every change, with the scope as it is then.
  defp authorizer(assigned_scope) do
    fn _action -> PhoenixKitTemplatesEditor.authorize(current_scope(assigned_scope), :write) end
  end

  # The emails core and the other modules send (core's catalogue, in the
  # page's language), not the host's own this module offers it.
  defp module_emails, do: Catalog.core_entries()

  # "Send to me", to the user of the page at the moment of the click.
  defp test_sender(config, assigned_scope, module_emails) do
    fn name, locale ->
      entry = Enum.find(module_emails, &(&1.name == name))
      TestSend.deliver(config, current_scope(assigned_scope), name, locale, entry)
    end
  end

  # Every change, in PhoenixKit's activity log, as done by the user then.
  defp journaller(assigned_scope) do
    fn event -> Journal.log(current_scope(assigned_scope), event) end
  end

  # The editor's callbacks, made once: a new function on every update would
  # look like a new preview to the editor and render it again.
  defp callbacks(id, %Config{root: root} = config) do
    blocks = config.block_placeholders

    %{
      preview: config.preview || fn name, locale -> Preview.preview(config, name, locale) end,
      convert: %{
        to_text: &Converters.to_text/2,
        markdown_to_html: &Converters.markdown_to_html(&1, block_placeholders: blocks)
      },
      after_write: &Files.after_write(root, &1),
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

  defp no_write_reason(nil, _write),
    do:
      gettext(
        "The templates are editable on this server, but the page does not tell the editor who you are, so they are shown read only (the module's scope hook is not set up)."
      )

  defp no_write_reason(_scope, {:error, :disabled}),
    do: gettext("The templates editor is switched off: the templates are shown read only.")

  defp no_write_reason(_scope, _forbidden),
    do:
      gettext(
        "The templates are editable on this server, but not by you: changing them needs the “%{permission}” permission.",
        permission: gettext("Edit email templates")
      )

  # The project's notes beside the templates, in the page's language.
  defp readme(%Config{root: root, base_locale: base}) do
    names = Enum.uniq(["README.#{page_locale()}.md", "README.#{base}.md", "README.md"])

    Enum.find_value(names, &read_note(root, &1))
  end

  defp read_note(root, name) do
    with {:ok, content} <- Files.safe_read(root, Path.join(root, name)),
         true <- String.valid?(content) do
      content
    else
      _none -> nil
    end
  end

  defp page_locale do
    PhoenixKitTemplatesEditor.Gettext |> Gettext.get_locale() |> DialectMapper.extract_base()
  end

  # The variables core gives a header and footer (and the layout) but not an
  # email's body, less the branding's, which a Markdown body has as well.
  # Rendered without reading any file: only the names are wanted.
  defp layout_variables(%Config{layout_group: group}) do
    parts = Layout.render_parts(nil, group: group, paths: [])

    (Map.keys(parts.variables) -- Map.keys(Branding.variables()))
    |> Enum.sort()
  rescue
    exception ->
      Logger.warning(
        "[PhoenixKitTemplatesEditor] layout variables: #{Exception.message(exception)}"
      )

      []
  end

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
        <p id="templates-editor-intro" class="text-sm text-base-content/60">
          <%= if @config.editable do %>
            {gettext(
              "The email templates of this server, as files. A change saved here changes the file; it reaches other servers once it is committed to git."
            )}
          <% else %>
            {gettext(
              "Read only on this server: the templates are changed where editing is allowed and come here with the program."
            )}
          <% end %>
        </p>

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

        <ul
          :if={@can_write}
          id="templates-editor-hints"
          class="list-disc pl-5 text-sm text-base-content/60 space-y-1"
        >
          <li>
            {gettext(
              "“%{fill}” writes the Markdown — or the HTML when there is no Markdown — into Text as plain text; “%{render}” writes the Markdown into HTML, with today's accent colour written into it for good. Neither saves: check the field, then “%{save}”.",
              fill: gettext("Fill text from content"),
              render: gettext("Markdown → HTML"),
              save: gettext("Save")
            )}
          </li>
          <li>
            {gettext(
              "The “%{fallback}” tab holds the files without a language: a language with no file of its own gets them.",
              fallback: gettext("Fallback")
            )}
          </li>
          <li :if={@layout_variables != []} id="templates-editor-layout-variables">
            {gettext("%{variables} work only in the header, the footer and the layout.",
              variables: Enum.map_join(@layout_variables, ", ", &"{{#{&1}}}")
            )}
          </li>
        </ul>

        <div
          :if={@readme}
          id="templates-editor-readme"
          class="rounded-box border border-base-300 p-4"
        >
          <PhoenixKitWeb.Components.Core.Markdown.markdown content={@readme} compact />
        </div>

        <div :if={@config.editable} class="flex flex-col items-start gap-2">
          <button
            id="templates-editor-uncommitted-check"
            type="button"
            phx-click="check_uncommitted"
            phx-target={@myself}
            class="btn btn-sm btn-ghost"
          >
            <.icon name="hero-arrow-path" class="size-4" />
            {gettext("Show what is not committed to git")}
          </button>
          <div
            :if={@uncommitted not in [nil, []]}
            id="templates-editor-uncommitted"
            class="alert alert-warning flex-col items-start text-sm"
          >
            <span>
              {gettext("Changed on this server and not yet committed to git:")}
            </span>
            <ul class="font-mono text-xs">
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
          describe_variables={@config.describe_variables}
          preview={@callbacks.preview}
          preview_image_origins={@image_origins}
          convert={@callbacks.convert}
          after_write={@callbacks.after_write}
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
