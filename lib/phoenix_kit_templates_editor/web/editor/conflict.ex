defmodule PhoenixKitTemplatesEditor.Web.Editor.Conflict do
  @moduledoc false

  alias PhoenixKitTemplatesEditor.Files

  @part_extensions %{label: "txt", subject: "txt", text: "txt", markdown: "md", html: "html"}
  # The parts about to change whose file is no longer what the form was
  # given: `{part, content on disk now}` (`nil` — no file, `:unreadable`).
  def conflicts(socket, changes) do
    %{root: root, selected: name, locale: locale, hashes: hashes} = socket.assigns

    for {part, _change} <- changes,
        path = part_path(root, name, part, locale),
        {fingerprint, content} = fingerprint(root, path),
        fingerprint != Map.get(hashes, part, :none),
        do: {part, content}
  end

  # `{fingerprint, content}` of the file at `path`: its sha256 and text,
  # `:none` when there is no file, or the reason it cannot be read.
  defp fingerprint(root, path) do
    case Files.safe_read(root, path) do
      {:ok, content} ->
        {:crypto.hash(:sha256, content),
         if(String.valid?(content), do: content, else: :unreadable)}

      {:error, :enoent} ->
        {:none, nil}

      {:error, reason} ->
        {{:error, reason}, :unreadable}
    end
  end

  def fingerprints(%{selected: nil}, _parts), do: %{}

  def fingerprints(%{root: root, selected: name, locale: locale}, parts) when is_binary(root) do
    Map.new(parts, fn part ->
      {part, root |> fingerprint(part_path(root, name, part, locale)) |> elem(0)}
    end)
  end

  def fingerprints(_assigns, _parts), do: %{}

  # The file `Overrides.write/5` writes for this part.
  def part_path(root, name, part, locale) do
    file =
      Enum.join(
        [Atom.to_string(part), locale, @part_extensions[part]] |> Enum.reject(&is_nil/1),
        "."
      )

    Path.join([root, name, file])
  end
end
