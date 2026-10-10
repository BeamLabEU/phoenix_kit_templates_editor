defmodule PhoenixKitTemplatesEditor.Layouts do
  @moduledoc """
  Layouts: what a group's emails are wrapped in.

  Core's model (`PhoenixKit.Email.Layout`, unchanged): layout `g` is the
  templates `_header-g`, `_footer-g` and `_layout-g`; a part `g` lacks is the
  shared one (`_header`, …), else core's own. An email picks its layout with
  `layout.txt` (no language), else it gets the host's default group
  (`layout_group`).

  This module answers for one root: which layouts there are (`list/4`), the
  layout an email names (`email_layout/2`), and copies or deletes a layout's
  parts (`copy/4`, `delete/3`). What a user may do with them is the editor's
  business (`PhoenixKitTemplatesEditor.Names`, `editable`, `authorize`).
  """

  alias PhoenixKit.Email.Layout
  alias PhoenixKit.Templates.Overrides
  alias PhoenixKitTemplatesEditor.Files
  alias PhoenixKitTemplatesEditor.Names

  @type source :: :own | :shared | :core

  @type part :: %{kind: Names.kind(), name: String.t(), source: source()}

  @type t :: %{
          group: String.t(),
          default?: boolean(),
          parts: [part()],
          emails: [String.t()]
        }

  @doc """
  The group an email's `layout.txt` names — read through
  `PhoenixKitTemplatesEditor.Files.safe_read/2`, a byte-order mark and
  surrounding whitespace dropped — when it is a valid group; else `nil`.
  `files` are the email's entries from `PhoenixKit.Templates.Overrides.list/1`.
  """
  @spec email_layout(Path.t(), [Overrides.file_entry()]) :: String.t() | nil
  def email_layout(root, files) do
    with %{path: path} <- Enum.find(files, &(&1.part == :layout and &1.locale == nil)),
         {:ok, content} <- Files.safe_read(root, path),
         group = content |> String.trim_leading("\u{FEFF}") |> String.trim(),
         true <- Layout.valid_group?(group) do
      group
    else
      _none -> nil
    end
  end

  @doc """
  The layouts of `listing` (`Overrides.list(root)`): the default group
  first, then every group that has a part of its own the `rules` allow, or
  that an email names and the `rules` allow, by name.

  For each, its `parts` — `:own`, else inherited: `:shared` when the root
  has the shared part, else `:core` — and the `emails` using it: every
  email of the root (a name without `_`, under the prefixes or not) whose
  `layout.txt` names it, or that has none when it is the default.
  """
  @spec list(
          [%{name: String.t(), files: [Overrides.file_entry()]}],
          Path.t(),
          Names.rules(),
          String.t() | nil
        ) :: [t()]
  def list(listing, root, rules, default) do
    names = MapSet.new(listing, & &1.name)
    used = emails_by_group(listing, root, default)

    own =
      for %{name: name} <- listing,
          {_kind, group} when is_binary(group) <- [Names.chrome(name)],
          Names.check(name, rules) == :ok,
          do: group

    named = for {_email, group} <- used, Names.group_allowed?(group, rules), do: group

    [default | Enum.sort(own ++ named)]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.map(fn group ->
      %{
        group: group,
        default?: group == default,
        parts: Enum.map(Names.kinds(), &part(&1, group, names)),
        emails: for({email, ^group} <- used, do: email)
      }
    end)
  end

  defp part(kind, group, names) do
    name = Names.part_name(kind, group)

    source =
      cond do
        MapSet.member?(names, name) -> :own
        MapSet.member?(names, Names.part_name(kind, nil)) -> :shared
        true -> :core
      end

    %{kind: kind, name: name, source: source}
  end

  # Every email of the root with its group, by name.
  defp emails_by_group(listing, root, default) do
    for %{name: name, files: files} <- listing,
        not String.starts_with?(name, "_"),
        group = email_layout(root, files) || default,
        group != nil,
        do: {name, group}
  end

  @doc """
  Copies part `kind` of layout `from` to layout `to` for each of `kinds`
  (`Overrides.copy_template/3`: every file of the part's directory).
  `{:ok, [{new_name, paths}]}`; on the first failure, the parts copied so
  far are deleted again and `{:error, reason}` returned.
  """
  @spec copy(Path.t(), String.t(), String.t(), [Names.kind()]) ::
          {:ok, [{String.t(), [Path.t()]}]} | {:error, term()}
  def copy(root, from, to, kinds) do
    Enum.reduce_while(kinds, {:ok, []}, fn kind, {:ok, done} ->
      name = Names.part_name(kind, to)

      case Overrides.copy_template(root, Names.part_name(kind, from), name) do
        {:ok, paths} ->
          {:cont, {:ok, done ++ [{name, paths}]}}

        {:error, reason} ->
          {:halt, take_back(root, done, reason)}
      end
    end)
  end

  defp take_back(root, done, reason) do
    for {created, _paths} <- done, do: Overrides.delete_template(root, created)
    {:error, reason}
  end

  @doc """
  Deletes part `kind` of layout `group` for each of `kinds`
  (`Overrides.delete_template/2`). `{:ok, deleted_names}`, or
  `{:error, reason, deleted_names}` at the first failure.
  """
  @spec delete(Path.t(), String.t(), [Names.kind()]) ::
          {:ok, [String.t()]} | {:error, term(), [String.t()]}
  def delete(root, group, kinds) do
    Enum.reduce_while(kinds, {:ok, []}, fn kind, {:ok, done} ->
      name = Names.part_name(kind, group)

      case Overrides.delete_template(root, name) do
        :ok -> {:cont, {:ok, done ++ [name]}}
        {:error, reason} -> {:halt, {:error, reason, done}}
      end
    end)
  end
end
