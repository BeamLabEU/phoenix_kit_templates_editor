defmodule PhoenixKitTemplatesEditor.Web.Letter do
  @moduledoc """
  The body of a letter (a template without a leading `_`) in the editor: one
  Leaf editor, not three fields.

  The body is the Markdown file (`PhoenixKitTemplatesEditor.Body`); the text
  file is derived from it on a save. A letter that has only a text file opens
  in Leaf with the text turned into Markdown, and nothing is written until
  Save. Headers, footers and layouts are not letters: they keep their code
  fields.

  ## One Leaf per document

  Every time the form is given a template, a language or the files (`open/2`)
  the editor mounts a Leaf of a new id, `<editor id>-leaf-<n>`, so a text
  can never be carried over into another language or template: the old Leaf
  is simply gone, and a message of it (`receive/2` drops any whose
  `editor_id` is not the open one) cannot arrive late and be taken for the
  new one's.

  ## What the server knows

  Leaf tells the editor what it holds in `{:leaf_changed, …}` (delivered by
  `notify:` as an update of the editor component). The editor keeps the last
  Markdown of an edited document, and nothing else: no message writes a file.
  Only the Save event does, from that Markdown, after every check a save has.
  A message that says the document is clean (Leaf compares with what it
  opened with) drops the pending text — undoing every edit leaves nothing to
  write.

  The modes are Leaf's own switch, visual and Markdown: `deny` takes away
  the hybrid and HTML modes, the second because Leaf does not turn a
  hand-edited HTML back into Markdown. The toolbar is Leaf's `:simple` one:
  what a letter carries — undo and redo, bold, italic, lists, a link, clear
  formatting — and, since that preset cannot be trimmed further, strike-through,
  inline code and emoji, all of which the letter's renderer draws.
  """

  use PhoenixKitWeb, :html
  use Gettext, backend: PhoenixKitTemplatesEditor.Gettext

  alias PhoenixKitTemplatesEditor.Body
  alias PhoenixKitTemplatesEditor.Variables

  @body_parts [:markdown, :text]
  @modes [:visual, :markdown]

  @type body :: %{
          doc: String.t(),
          content: String.t(),
          dirty?: boolean(),
          markdown: String.t() | nil,
          retained: String.t() | nil,
          room?: boolean()
        }

  @doc "Is the open template a letter?"
  @spec letter?(map()) :: boolean()
  def letter?(%{selected: name}) when is_binary(name), do: Variables.kind(name) == :email
  def letter?(_assigns), do: false

  @doc "The body parts of the open language that cannot be read here (not UTF-8, a link, too large)."
  @spec unreadable(map()) :: [atom()]
  def unreadable(contents) do
    for part <- @body_parts, match?(%{invalid: true}, contents[part]), do: part
  end

  @doc """
  Gives the form a new Leaf document for the open letter, or none (`body: nil`)
  for anything else — and for a letter whose body files cannot be read, which
  is never written over. `retained` is a body a refused save left in the
  form: the new document starts with it and the editor still holds it as
  unsaved.
  """
  @spec open(Phoenix.LiveView.Socket.t(), String.t() | nil) :: Phoenix.LiveView.Socket.t()
  def open(socket, retained \\ nil) do
    %{contents: contents, id: id} = socket.assigns
    rev = socket.assigns.body_rev + 1

    body =
      if letter?(socket.assigns) and unreadable(contents) == [] do
        content = retained || initial(contents)

        %{
          doc: "#{id}-leaf-#{rev}",
          content: content,
          dirty?: retained != nil,
          markdown: retained,
          retained: retained,
          room?: Body.room?(content)
        }
      end

    Phoenix.Component.assign(socket,
      body: body,
      body_mode: mode_for(socket.assigns, body),
      body_rev: rev
    )
  end

  # A letter with room left on purpose (`Body.room?/1`) opens in Markdown
  # mode: the visual editor cannot hold more than one blank line in a row, so
  # a first edit there would drop the room without a word. Any other letter
  # opens in the mode the writer chose last, and the one after a frame letter
  # in the default mode again.
  defp mode_for(_assigns, %{room?: true}), do: :markdown
  defp mode_for(%{body: %{room?: true}}, _body), do: :visual
  defp mode_for(%{body_mode: mode}, _body), do: mode

  @doc """
  What Leaf opens with: the Markdown file, else the text file as Markdown,
  else nothing. A blank file counts as none, as it does for the renderer.
  """
  @spec initial(map()) :: String.t()
  def initial(contents) do
    cond do
      present?(contents[:markdown]) ->
        contents.markdown.content |> normalize() |> Body.to_editor()

      present?(contents[:text]) ->
        contents.text.content |> normalize() |> Body.from_text()

      true ->
        ""
    end
  end

  defp present?(%{content: content}), do: String.trim(content) != ""
  defp present?(_none), do: false

  defp normalize(content), do: String.replace(content, "\r\n", "\n")

  @doc """
  A message of the Leaf editor of the open document; anything else — another
  document's, a message of no interest, malformed — changes nothing.
  """
  @spec receive(Phoenix.LiveView.Socket.t(), term()) :: Phoenix.LiveView.Socket.t()
  def receive(socket, {:leaf_changed, %{editor_id: doc, markdown: markdown, dirty: dirty}})
      when is_binary(markdown) do
    case socket.assigns.body do
      %{doc: ^doc} = body ->
        if String.valid?(markdown), do: put_change(socket, body, markdown, dirty), else: socket

      _other ->
        socket
    end
  end

  def receive(socket, {:leaf_mode_changed, %{editor_id: doc, mode: mode}}) when mode in @modes do
    case socket.assigns.body do
      %{doc: ^doc} -> Phoenix.Component.assign(socket, body_mode: mode)
      _other -> socket
    end
  end

  def receive(socket, _message), do: socket

  # Clean: nothing of Leaf's own is pending, only what a refused save left.
  defp put_change(socket, body, _markdown, false),
    do:
      Phoenix.Component.assign(socket,
        body: %{body | dirty?: body.retained != nil, markdown: body.retained}
      )

  defp put_change(socket, body, markdown, _dirty),
    do: Phoenix.Component.assign(socket, body: %{body | dirty?: true, markdown: markdown})

  @doc "Leaf's own modes the writer may use."
  @spec denied_modes() :: [atom()]
  def denied_modes, do: [:html_mode, :hybrid_mode]

  attr(:id, :string, required: true)
  attr(:body, :map, required: true)
  attr(:mode, :atom, default: :visual)
  attr(:notify, :any, required: true)

  @doc "The Leaf editor of a letter's body."
  def body_field(assigns) do
    ~H"""
    <div id={@id} class="flex min-w-0 flex-col gap-1">
      <span class="text-sm font-semibold">{gettext("Body")}</span>
      <p
        :if={@body.room? and @mode == :visual}
        id={"#{@id}-room-note"}
        class="text-xs text-warning"
      >
        {gettext(
          "This letter leaves room for text: several blank lines in a row. The visual mode keeps only one of them; use the Markdown mode to keep them all."
        )}
      </p>
      <.live_component
        module={Leaf}
        id={@body.doc}
        content={@body.content}
        mode={@mode}
        preset={:simple}
        deny={denied_modes()}
        notify={@notify}
        placeholder={gettext("Write the letter here")}
        height="420px"
        debounce={400}
      />
    </div>
    """
  end
end
