defmodule PhoenixKitTemplatesEditor.Web.Editor.Save do
  @moduledoc false
  use Gettext, backend: PhoenixKitTemplatesEditor.Gettext

  alias PhoenixKit.Templates.Overrides
  alias PhoenixKitTemplatesEditor.Web.Letter

  # Fields that are one line: a caption and a message header.
  @single_line_parts [:label, :subject]
  # RFC 5322's limit for one line of a message header.
  @max_subject_bytes 998

  def changes(params, contents, baseline, parts) do
    Enum.flat_map(parts, fn part ->
      with value when is_binary(value) <- params[Atom.to_string(part)],
           value = value |> normalize_newlines() |> one_line(part),
           given = Map.get(baseline, part, ""),
           # Left as the form was given it: another session's change to
           # this part since then must not be written back over.
           false <- unchanged?(part, value, given),
           value = with_final_newline(part, value, given),
           {:ok, change} <- change(part, Map.get(contents, part), value) do
        [{part, change}]
      else
        _unchanged -> []
      end
    end)
  end

  # A one-line field (`label`, `subject`) is an `<input>`; a value that
  # reaches the server with a line break at its end (pasted, or sent by
  # another client) is the same line. One inside it is left for the save to
  # refuse.
  def one_line(value, part) when part in @single_line_parts,
    do: String.trim_trailing(value, "\n")

  def one_line(value, _part), do: value

  # A one-line field is given without the file's own trailing newline, so it
  # comes back without it — that is no change.
  def unchanged?(part, value, baseline) when part in @single_line_parts,
    do: value == baseline or value == single_line(baseline)

  def unchanged?(_part, value, baseline), do: value == baseline

  # A one-line field never sends the line break a file ended with; an edited
  # one-line file gets it back, so the edit is the only difference.
  defp with_final_newline(part, value, given)
       when part in @single_line_parts and value != "" do
    if String.ends_with?(given, "\n") and not String.ends_with?(value, "\n"),
      do: value <> "\n",
      else: value
  end

  defp with_final_newline(_part, value, _given), do: value

  def single_line(value),
    do: value |> String.trim_trailing("\n") |> String.replace(~r/\r?\n/, " ")

  # A subject is one line of a message header.
  def subject_refusal(changes) do
    case List.keyfind(changes, :subject, 0) do
      {:subject, {:write, value}} ->
        subject = String.trim(value)

        if String.contains?(subject, ["\n", "\r"]) or byte_size(subject) > @max_subject_bytes,
          do:
            gettext("Not saved: the subject must be one line of at most %{max} bytes.",
              max: @max_subject_bytes
            )

      _none ->
        nil
    end
  end

  defp change(_part, %{invalid: true}, _value), do: :none
  defp change(_part, nil, ""), do: :none
  defp change(_part, _file, ""), do: {:ok, :delete}
  defp change(_part, nil, value), do: {:ok, {:write, value}}

  defp change(part, %{content: content}, value) do
    if unchanged?(part, value, normalize_newlines(content)),
      do: :none,
      else: {:ok, {:write, value}}
  end

  # A letter's Markdown is its canon and its text is made from it: the
  # canon is written first, and when it is refused the text made from it is
  # not written beside the old one.
  def write_in_order(socket, changes) do
    %{root: root, selected: name, locale: locale} = socket.assigns
    write = fn {part, change} -> {part, apply_change(change, root, name, part, locale)} end

    case {Letter.letter?(socket.assigns), Enum.split_with(changes, &match?({:markdown, _}, &1))} do
      {true, {[markdown], rest}} ->
        {_part, result} = written = write.(markdown)

        rest =
          if match?({:error, _reason}, result),
            do: Enum.reject(rest, &match?({:text, _change}, &1)),
            else: rest

        [written | Enum.map(rest, write)]

      _not_both ->
        Enum.map(changes, write)
    end
  end

  defp apply_change(:delete, root, name, part, locale) do
    case Overrides.delete(root, name, part, locale) do
      :ok -> {:ok, []}
      error -> error
    end
  end

  defp apply_change({:write, value}, root, name, part, locale) do
    Overrides.write(root, name, part, locale, value)
  end

  def normalize_newlines(value), do: String.replace(value, "\r\n", "\n")
end
