defmodule PhoenixKitTemplatesEditor.Web.Editor.PreviewPane do
  @moduledoc false
  use Phoenix.Component
  use Gettext, backend: PhoenixKitTemplatesEditor.Gettext

  import PhoenixKitTemplatesEditor.Web.Editor.PanelHelpers
  import PhoenixKitWeb.Components.Core.NavTabs, only: [nav_tabs: 1]

  attr(:id, :string, required: true)
  attr(:result, :any, required: true)
  attr(:tab, :atom, default: :html)
  attr(:single, :boolean, default: false)
  attr(:csp, :string, required: true)
  attr(:myself, :any, required: true)

  def preview_pane(%{result: {:ok, subject, html, text}} = assigns) do
    assigns =
      assign(assigns,
        subject: subject,
        html: html,
        text: text,
        show_html?: assigns.single or text == :none or assigns.tab == :html
      )

    ~H"""
    <div class="flex min-w-0 flex-col gap-2">
      <p id={"#{@id}-preview-subject"} class="break-words text-sm">
        <span class="opacity-60">{gettext("Subject:")}</span> {@subject}
      </p>
      <%!-- A wrapper carries the id: `nav_tabs` has an `id` attribute only from core 3.6.0. --%>
      <div :if={@text != :none and not @single} id={"#{@id}-preview-tabs"}>
        <.nav_tabs
          active_tab={to_string(@tab)}
          on_change="preview_tab"
          target={@myself}
          variant={:border}
          tabs={[
            %{id: "html", label: part_title(:html)},
            %{id: "text", label: part_title(:text)}
          ]}
        />
      </div>
      <%!-- bg-white, not a theme colour: an email is drawn on white whatever the admin theme. --%>
      <%!-- Nothing in an edited template runs (no allow-scripts), leaks the
           admin page's address, or loads anything from outside but images
           from the origins the host names (`csp` on the frame, which only
           Chromium honours, and the same policy as a meta tag at the top of
           the document, which every browser does). --%>
      <iframe
        :if={@show_html? && @html}
        sandbox=""
        referrerpolicy="no-referrer"
        csp={@csp}
        srcdoc={with_policy(@html, @csp)}
        title={gettext("Preview")}
        class="h-[32rem] w-full rounded-box border border-base-300 bg-white"
      ></iframe>
      <p :if={@show_html? && !@html && !(@single && is_binary(@text))} class="text-sm opacity-70">
        {gettext("No HTML.")}
      </p>
      <pre :if={@show_html? && !@html && @single && is_binary(@text)} class={pre_class()}>{@text}</pre>
      <pre :if={!@show_html? && @text} id={"#{@id}-preview-text"} class={pre_class()}>{@text}</pre>
      <p :if={!@show_html? && !@text} class="text-sm opacity-70">{gettext("No text.")}</p>
    </div>
    """
  end

  def preview_pane(%{result: :unsaved} = assigns) do
    ~H"""
    <p class="text-sm opacity-70">{gettext("Save the template to preview it.")}</p>
    """
  end

  def preview_pane(%{result: {:error, message}} = assigns) do
    assigns = assign(assigns, message: message)

    ~H"""
    <div role="alert" class="alert alert-error text-sm">
      {gettext("Preview unavailable: %{reason}", reason: @message)}
    </div>
    """
  end

  # The preview frame's policy: no script, no frame, no connection, no font
  # or stylesheet from outside; inline styles (every email has them) and
  # images inline or from the host's own origins (its logo).
  def preview_csp(origins) do
    images = Enum.join(["data:" | origins], " ")
    "default-src 'none'; img-src #{images}; style-src 'unsafe-inline'"
  end

  @doctype ~r/\A\s*+<!doctype\b[^<>]*+>/i

  # The policy as the document's first element, so Firefox and Safari keep
  # an edited template's remote image (a tracking pixel) out as well: a
  # `<meta>` before anything else lands in the document's head. After a
  # doctype, not before it: the document keeps its rendering mode.
  defp with_policy(html, csp) do
    meta = ~s(<meta http-equiv="Content-Security-Policy" content="#{csp}">)

    case Regex.run(@doctype, html, return: :index) do
      [{0, length}] ->
        binary_part(html, 0, length) <>
          meta <> binary_part(html, length, byte_size(html) - length)

      nil ->
        meta <> html
    end
  end
end
