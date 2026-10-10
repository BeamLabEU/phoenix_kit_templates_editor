defmodule PhoenixKitTemplatesEditor.Catalog do
  @moduledoc """
  The host's emails as a list: the order the editor's preview takes its
  "first email" from (`emails/2`), and the entries the module gives core's
  "Preview emails" (`entries/1`, through
  `c:PhoenixKit.Module.email_templates/0`) when the host sets
  `catalog: true`.

  An email is a template under `name_prefixes` whose name does not start
  with `_`; an incomplete one is listed too (a preview of it is useful).
  Its label is its `label` in the language asked, else in `base_locale`,
  else its name; the list is ordered by label (case-insensitively), then by
  name. Its layout group is its `layout.txt`, else `layout_group`. Every
  file is read through `PhoenixKitTemplatesEditor.Files.safe_read/2`.
  """

  require Logger

  alias PhoenixKit.Email.Catalog, as: CoreCatalog
  alias PhoenixKit.Email.Content
  alias PhoenixKit.Modules.Languages.DialectMapper
  alias PhoenixKit.Templates.Overrides
  alias PhoenixKitTemplatesEditor.Config
  alias PhoenixKitTemplatesEditor.Files
  alias PhoenixKitTemplatesEditor.Layouts

  @type email :: %{name: String.t(), label: String.t(), layout: String.t() | nil}

  @doc "The emails of `config`'s root, labelled in `locale` and ordered (see the moduledoc)."
  @spec emails(Config.t(), String.t() | nil) :: [email()]
  def emails(%Config{root: root} = config, locale) do
    for %{name: name, files: files} <- Overrides.list(root),
        email?(config, name) do
      %{name: name, label: label(config, name, files, locale), layout: group(config, files)}
    end
    |> Enum.sort_by(&{String.downcase(&1.label), &1.name})
  end

  @doc """
  The entries for core's email catalog (`PhoenixKit.Email.Catalog`), labelled
  in PhoenixKit's language (`PhoenixKitWeb.Gettext`): `name`, `label`,
  `variables` (the sample variables: a map, or a function of none for a
  callback) and `layout` when there is a group — no `defaults`, the files
  being the text.

  `[]` unless `catalog: true`. Also `[]`, with a warning in the log, when
  core does not read the root (`root_read_by_core?/1`): its preview would
  show other files than these.
  """
  @spec entries(Config.t()) :: [map()]
  def entries(%Config{catalog: true} = config) do
    if root_read_by_core?(config) do
      locale = page_locale()

      for email <- emails(config, locale) do
        %{name: email.name, label: email.label, variables: variables(config.sample_variables)}
        |> put_layout(email.layout)
      end
    else
      Logger.warning(
        "[PhoenixKitTemplatesEditor] catalog: true, but the templates root is not a directory " <>
          "core reads emails from (config :phoenix_kit, :template_paths); no emails offered " <>
          "to core's email preview"
      )

      []
    end
  end

  def entries(%Config{}), do: []

  @doc """
  Core's email catalogue (`PhoenixKit.Email.Catalog.entries/0`: core's own
  emails, then every enabled module's) without this module's entries —
  the host's files, which the editor lists as its own. Labels in the
  current language. `[]` when the catalogue cannot be read.
  """
  @spec core_entries() :: [map()]
  def core_entries do
    for entry <- CoreCatalog.entries(),
        Map.get(entry, :module) != PhoenixKitTemplatesEditor,
        do: entry
  rescue
    exception ->
      Logger.warning(
        "[PhoenixKitTemplatesEditor] email catalogue: #{Exception.message(exception)}"
      )

      []
  catch
    kind, reason ->
      Logger.warning(
        "[PhoenixKitTemplatesEditor] email catalogue: #{Exception.format_banner(kind, reason)}"
      )

      []
  end

  @doc """
  Whether core reads emails from `config`'s root: one of
  `PhoenixKit.Email.Content.override_paths/0` is the same directory
  (`PhoenixKitTemplatesEditor.Files.same_dir?/2`), whatever path names it.
  """
  @spec root_read_by_core?(Config.t()) :: boolean()
  def root_read_by_core?(%Config{root: root}) do
    Enum.any?(Content.override_paths(), &(is_binary(&1) and Files.same_dir?(&1, root)))
  rescue
    _ -> false
  end

  @doc """
  The layout group of an email: its `layout.txt` when that names a valid
  group, else `layout_group`.
  """
  @spec group(Config.t(), [Overrides.file_entry()]) :: String.t() | nil
  def group(%Config{root: root, layout_group: default}, files),
    do: Layouts.email_layout(root, files) || default

  defp email?(%Config{name_prefixes: prefixes}, name),
    do: not String.starts_with?(name, "_") and String.starts_with?(name, prefixes)

  defp label(%Config{root: root, base_locale: base}, name, files, locale) do
    Enum.find_value(Enum.uniq([locale, base]), name, fn wanted ->
      with %{path: path} <- Enum.find(files, &(&1.part == :label and &1.locale == wanted)),
           {:ok, content} <- Files.safe_read(root, path),
           true <- String.valid?(content),
           label when label != "" <- String.trim(content) do
        label
      else
        _none -> nil
      end
    end)
  end

  defp variables({module, function}), do: fn -> apply(module, function, []) end
  defp variables(variables), do: variables

  defp put_layout(entry, nil), do: entry
  defp put_layout(entry, group), do: Map.put(entry, :layout, group)

  defp page_locale do
    PhoenixKitWeb.Gettext |> Gettext.get_locale() |> DialectMapper.extract_base()
  rescue
    _ -> nil
  end
end
