defmodule PhoenixKitTemplatesEditor.Test.EditorHost do
  @moduledoc false
  # A host LiveView rendering the editor the way an application would. The
  # test process gets every after_write call as a message, unless the test
  # passes an after_write of its own. A "locale" in the session is put on the
  # module's Gettext backend, the way core sets the page's language.
  use Phoenix.LiveView

  alias PhoenixKit.Templates

  @impl true
  def mount(_params, %{"opts" => opts, "test_pid" => test_pid} = session, socket) do
    if locale = session["locale"],
      do: Gettext.put_locale(PhoenixKitTemplatesEditor.Gettext, locale)

    opts =
      opts
      |> Map.put_new(:after_write, fn paths -> send(test_pid, {:after_write, paths}) end)
      |> Map.put_new(:after_change, fn name -> send(test_pid, {:after_change, name}) end)
      |> maybe_render_preview()

    {:ok, assign(socket, opts: opts)}
  end

  @impl true
  def handle_info({:put, changes}, socket) do
    {:noreply, assign(socket, opts: Map.merge(socket.assigns.opts, changes))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component module={PhoenixKitTemplatesEditor.Web.Editor} id="editor" {@opts} />
    """
  end

  # Renders the files themselves, to show a preview reads what was just saved.
  defp maybe_render_preview(%{preview: :render, root: root} = opts) do
    preview = fn name, locale ->
      parts = Templates.render(name, %{}, %{}, locale: locale, paths: [root])
      {parts.subject, parts.html || parts.text}
    end

    %{opts | preview: preview}
  end

  defp maybe_render_preview(opts), do: opts

  def preview("order_broken", _locale), do: {:error, :boom}
  def preview("order_timeout", _locale), do: exit(:timeout)
  def preview("order_shapeless", _locale), do: %{subject: "S"}

  def preview("order_safe", _locale) do
    {{:safe, ~s(<b id="pwned-subject">S</b>)},
     {:safe, ~s("></iframe><b id="pwned">x</b><iframe srcdoc=")}}
  end

  def preview(name, locale) do
    {"Subject of #{name} (#{locale})",
     "<p>Hello from #{name}</p><script>window.parent.alert(1)</script>"}
  end

  def failing_after_write(_paths), do: raise("chown failed")
  def failing_after_change(_name), do: raise("refresh failed")

  # A host's text and HTML versions, the way a mailer would build them.
  def preview_with_text(name, locale) do
    {subject, html} = preview(name, locale)
    {subject, html, "Hello from #{name} <as text>"}
  end

  # Crude stand-ins for a host's Markdown renderer: like a real one, they
  # leave a placeholder they are given no value for as it is.
  def to_text(:markdown, markdown), do: String.replace(markdown, "**", "")
  def to_text(:html, html), do: String.replace(html, ~r/<[^>]*>/, "")

  def markdown_to_html(markdown) do
    "<p>" <> String.replace(markdown, ~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>") <> "</p>"
  end

  def failing_to_text(_format, _source), do: raise("converter down")
  def refusing_to_text(_format, _source), do: {:error, "cannot convert this"}
  def shapeless_to_text(_format, _source), do: {:ok, "text"}
  def latin_to_text(_format, _source), do: <<"Tere ", 0xE4>>
end
