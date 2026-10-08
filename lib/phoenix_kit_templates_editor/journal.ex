defmodule PhoenixKitTemplatesEditor.Journal do
  @moduledoc """
  The template changes made through the tab, in PhoenixKit's activity log
  (`PhoenixKit.Activity`, spec §4.10 Б3): who made the change, the
  template, the part and its language, and a short diff — so "who changed
  the password-reset email, and how" has an answer.

  An entry is `module: "templates_editor"`, `action: "templates_editor.<event>"`,
  `resource_type: "email_template"`, the user's uuid as the actor, and in
  `metadata` the keys the event has: `template`, `part`, `locale`, `from`
  (a copy's source), `layout`, `parts`, `diff`.

  | event | when |
  |---|---|
  | `file_saved` / `file_deleted` | a part written / saved empty |
  | `template_copied` / `template_deleted` | a template copied / deleted |
  | `fallback_deleted` | an email's unused locale-less parts deleted |
  | `created_from_default` / `created_from_db` | a module's email given files (П2) |
  | `layout_set` | an email's layout chosen |
  | `layout_created` / `layout_deleted` | a layout copied / deleted |

  Logging never fails the change it describes: `PhoenixKit.Activity.log/3`
  does not raise, and anything else is caught here.
  """

  require Logger

  alias PhoenixKit.Activity
  alias PhoenixKit.Users.Auth.Scope

  @module_key "templates_editor"
  @metadata_keys [:template, :part, :locale, :from, :layout, :parts]
  @side_chars 240

  @type event :: %{required(:action) => atom(), optional(atom()) => term()}

  @doc "Logs `event` (see the moduledoc) as done by the user of `scope`."
  @spec log(Scope.t() | nil, event()) :: :ok
  def log(scope, %{action: action} = event) when is_atom(action) do
    Activity.log(@module_key, action(action),
      actor_uuid: Scope.user_uuid(scope),
      resource_type: "email_template",
      metadata: metadata(event)
    )

    :ok
  rescue
    exception ->
      Logger.warning("[PhoenixKitTemplatesEditor] journal: #{Exception.message(exception)}")
      :ok
  catch
    kind, reason ->
      Logger.warning(
        "[PhoenixKitTemplatesEditor] journal: #{Exception.format_banner(kind, reason)}"
      )

      :ok
  end

  @doc "The activity action of `event`: `templates_editor.<event>`."
  @spec action(atom()) :: String.t()
  def action(event), do: "#{@module_key}.#{event}"

  @doc "The entry's metadata: the event's keys as strings, and the diff of `before`/`after`."
  @spec metadata(event()) :: map()
  def metadata(event) do
    base =
      for key <- @metadata_keys, Map.has_key?(event, key), into: %{} do
        {Atom.to_string(key), plain(Map.fetch!(event, key))}
      end

    if Map.has_key?(event, :before) or Map.has_key?(event, :after),
      do: Map.put(base, "diff", diff(event[:before], event[:after])),
      else: base
  end

  defp plain(value) when is_atom(value) and not is_nil(value) and not is_boolean(value),
    do: Atom.to_string(value)

  defp plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  defp plain(value), do: value

  @doc """
  A short diff of two versions of a file (`nil` — no file): where the
  change starts (`@line:column`), what was taken out (`- `) and what was
  put in (`+ `), the text both share before and after left out, each side
  cut to #{@side_chars} characters.
  """
  @spec diff(String.t() | nil, String.t() | nil) :: String.t()
  def diff(nil, nil), do: ""

  def diff(before, after_) do
    before = text(before)
    after_ = text(after_)

    prefix = common(before, after_, :prefix)
    before_rest = drop_prefix(before, prefix)
    after_rest = drop_prefix(after_, prefix)
    suffix = common(before_rest, after_rest, :suffix)
    removed = drop_suffix(before_rest, suffix)
    added = drop_suffix(after_rest, suffix)

    [
      position(binary_part(before, 0, prefix)),
      if(removed != "", do: "- " <> clip(removed)),
      if(added != "", do: "+ " <> clip(added))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp text(nil), do: ""
  defp text(value) when is_binary(value), do: if(String.valid?(value), do: value, else: "")

  # The length in bytes of what `a` and `b` share at the start or the end,
  # never splitting a character.
  defp common(a, b, :prefix), do: whole(a, :binary.longest_common_prefix([a, b]), :prefix)
  defp common(a, b, :suffix), do: whole(a, :binary.longest_common_suffix([a, b]), :suffix)

  defp whole(_a, 0, _side), do: 0

  defp whole(a, length, side) do
    part =
      if side == :prefix,
        do: binary_part(a, 0, length),
        else: binary_part(a, byte_size(a) - length, length)

    if String.valid?(part), do: length, else: whole(a, length - 1, side)
  end

  defp drop_prefix(value, length), do: binary_part(value, length, byte_size(value) - length)
  defp drop_suffix(value, length), do: binary_part(value, 0, byte_size(value) - length)

  defp position(prefix) do
    lines = String.split(prefix, "\n")
    "@#{length(lines)}:#{String.length(List.last(lines)) + 1}"
  end

  defp clip(text) do
    if String.length(text) > @side_chars,
      do: String.slice(text, 0, @side_chars) <> "…",
      else: text
  end
end
