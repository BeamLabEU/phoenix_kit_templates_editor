defmodule PhoenixKitTemplatesEditor.Web.Section do
  @moduledoc """
  The "Email templates" tab of Settings › Emails Transactional.

  Core mounts it as `<.live_component module={…} id={:templates_editor} />`
  with no other assigns, so everything comes from the host's config
  (`PhoenixKitTemplatesEditor.Config`). A config that does not load is shown
  as an error here rather than taking the page down.

  A placeholder for now: the editor itself is not wired in yet.
  """
  use PhoenixKitWeb, :live_component
  use Gettext, backend: PhoenixKitTemplatesEditor.Gettext

  alias PhoenixKitTemplatesEditor.Config

  @impl true
  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign(:config, Config.load())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="templates-editor-section" class="flex flex-col gap-4">
      <%= case @config do %>
        <% {:error, messages} -> %>
          <div role="alert" class="alert alert-error alert-soft">
            <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
            <div>
              <p class="font-semibold">
                {gettext("The templates editor is not configured correctly.")}
              </p>
              <ul class="list-disc list-inside text-sm">
                <li :for={message <- messages}>{message}</li>
              </ul>
            </div>
          </div>
        <% {:ok, _config} -> %>
          <p class="text-sm text-base-content/70">
            {gettext("The templates editor will appear here.")}
          </p>
      <% end %>
    </div>
    """
  end
end
