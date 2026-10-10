defmodule PhoenixKitTemplatesEditor.Overriding do
  @moduledoc """
  Files for an email core or another module sends — an override of it in
  the host's templates root. The editor offers these only
  where the email is overridable (`PhoenixKitTemplatesEditor.Names`) and
  has no file yet.

    * `from_defaults/3` — the email's built-in text (its catalogue entry's
      `defaults`), one file per part and language of `locales`, each
      evaluated in its language as core's email preview does
      (`PhoenixKit.Utils.RecipientLocale.in_locale/2`). From then on the
      file is the text: a translation an update of the module brings no
      longer reaches the email.
    * `from_db/2` — the Emails module's active database template, written
      by that module's own export logic
      (`PhoenixKit.Modules.Emails.TemplateExport.plan/3`: the body cut out
      of a stored document for core's layout, the locale every recipient
      falls back to written without a language). Only with that module
      installed (`emails_module?/0`).
    * `from_layout_default/2` — a part of a module's own layout group
      (`_header-billing`): the shared part's HTML when the root has one,
      else core's own, without a language.

  Every file goes through `PhoenixKit.Templates.Overrides.write/5` (names,
  languages, sizes checked); a failure part way takes back what was written.
  """

  alias PhoenixKit.Email.Branding
  alias PhoenixKit.Email.Layout
  alias PhoenixKit.Email.Provider
  alias PhoenixKit.Templates.Overrides
  alias PhoenixKit.Utils.RecipientLocale
  alias PhoenixKit.Utils.Routes
  alias PhoenixKitTemplatesEditor.Files
  alias PhoenixKitTemplatesEditor.Names

  @text_parts [:subject, :text, :markdown, :html]

  @export_parts %{"subject" => :subject, "text" => :text, "html" => :html}

  @type result :: {:ok, [Path.t()]} | {:error, atom() | String.t()}
  @type option :: {:max_root_bytes, pos_integer() | nil}

  @doc """
  The built-in parts of catalogue `entry` in `locale`: its `defaults` (a
  map or a function of none, evaluated in the language), without the blank
  ones. `{:error, message}` when the function fails.
  """
  @spec defaults(map(), String.t() | nil) :: {:ok, map()} | {:error, String.t()}
  def defaults(entry, locale) do
    defaults =
      case Map.get(entry, :defaults) do
        fun when is_function(fun, 0) -> RecipientLocale.in_locale(locale, fun)
        map when is_map(map) -> map
        _none -> %{}
      end

    parts =
      for {part, value} <- defaults || %{},
          part in [:layout | @text_parts],
          is_binary(value) and String.trim(value) != "",
          into: %{},
          do: {part, value}

    {:ok, parts}
  rescue
    exception -> {:error, Exception.message(exception)}
  catch
    kind, reason -> {:error, Exception.format_banner(kind, reason)}
  end

  @doc """
  Writes `entry`'s built-in text as files in each of `locales` (see the moduledoc).
  Options: `:max_root_bytes`, checked against the complete plan before any write.
  """
  @spec from_defaults(Path.t(), map(), [String.t()], [option()]) :: result()
  def from_defaults(root, %{name: name} = entry, locales, opts \\ []) do
    with :ok <- fresh(root, name),
         {:ok, files} <- default_files(entry, locales) do
      write_all(root, name, files, opts)
    end
  end

  defp default_files(entry, locales) do
    Enum.reduce_while(locales, {:ok, []}, fn locale, {:ok, files} ->
      case defaults(entry, locale) do
        {:ok, parts} -> {:cont, {:ok, files ++ locale_files(parts, locale, files)}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  # The parts of one language, and `layout.txt` once (it has no language).
  defp locale_files(parts, locale, earlier) do
    own = for part <- @text_parts, value = parts[part], do: {part, locale, value}
    layout = if parts[:layout], do: [{:layout, nil, String.trim(parts.layout)}], else: []
    own ++ Enum.reject(layout, &(&1 in earlier))
  end

  @doc "Whether the Emails module (its template export) is installed."
  @spec emails_module?() :: boolean()
  def emails_module?, do: Code.ensure_loaded?(export_module())

  @doc "Whether the Emails module has an active database template named `name`."
  @spec db_template?(String.t()) :: boolean()
  def db_template?(name), do: emails_module?() and db_template(name) != nil

  defp db_template(name) do
    Provider.current().get_active_template_by_name(name)
  rescue
    _ -> nil
  catch
    _kind, _reason -> nil
  end

  @doc """
  Writes the Emails module's active database template `name` as files (see the moduledoc).
  Options: `:max_root_bytes`, checked before any write.
  """
  @spec from_db(Path.t(), String.t(), [option()]) :: result()
  def from_db(root, name, opts \\ []) do
    with true <- emails_module?() || {:error, :no_emails_module},
         template when is_map(template) <- db_template(name) || {:error, :no_db_template},
         :ok <- fresh(root, name),
         {:ok, files} <- export(root, name, template) do
      write_all(root, name, files, opts)
    end
  end

  # The export's own plan, read back into parts: `<root>/<name>/<part>[.<locale>].<ext>`.
  defp export(root, name, template) do
    module = export_module()
    opts = [out: root, html: module.default_html_mode()]
    plan = module.plan([Map.put(template, :is_system, true)], [], opts)

    files =
      for {path, content} <- plan.files,
          Path.dirname(path) == Path.join(root, name),
          {:ok, part, locale} <- [export_file(Path.basename(path))],
          do: {part, locale, content}

    {:ok, files}
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp export_file(file) do
    case String.split(file, ".") do
      [stem, _ext] when is_map_key(@export_parts, stem) ->
        {:ok, @export_parts[stem], nil}

      [stem, locale, _ext] when is_map_key(@export_parts, stem) ->
        {:ok, @export_parts[stem], locale}

      _other ->
        :error
    end
  end

  # An internal seam for tests: the Emails module is not a dependency.
  defp export_module do
    Application.get_env(
      :phoenix_kit_templates_editor,
      :template_export,
      PhoenixKit.Modules.Emails.TemplateExport
    )
  end

  @doc """
  The HTML a module layout's part (`_header-billing`) starts from: the
  shared part's (`_header/html.html` in the root, read through
  `PhoenixKitTemplatesEditor.Files.safe_read/2`), else core's own.
  """
  @spec layout_default(Path.t(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def layout_default(root, name) do
    case Names.chrome(name) do
      {kind, group} when is_binary(group) -> {:ok, shared_part(root, kind) || core_part(kind)}
      _not_a_part -> {:error, :not_a_layout_part}
    end
  end

  @doc """
  Writes `layout_default/2` as the part's locale-less HTML.
  Options: `:max_root_bytes`, checked before any write.
  """
  @spec from_layout_default(Path.t(), String.t(), [option()]) :: result()
  def from_layout_default(root, name, opts \\ []) do
    with :ok <- fresh(root, name),
         {:ok, html} <- layout_default(root, name) do
      write_all(root, name, [{:html, nil, html}], opts)
    end
  end

  defp shared_part(root, kind) do
    case Files.safe_read(root, Path.join([root, Names.part_name(kind, nil), "html.html"])) do
      {:ok, html} -> if String.valid?(html), do: html
      {:error, _none} -> nil
    end
  end

  defp core_part(:header), do: Layout.default_header_html(logo: Branding.logo_url() != "")

  defp core_part(:footer),
    do:
      Layout.default_footer_html(
        link: String.starts_with?(Routes.base_url(), ["http://", "https://"])
      )

  defp core_part(:layout),
    do: Layout.default_html(accent_bar: Branding.configured_accent_color() != nil)

  # Only a name with no files yet: an override is made once, then edited.
  defp fresh(root, name) do
    case Files.check_template_dir(root, name) do
      :ok -> if File.exists?(Path.join(root, name)), do: {:error, :exists}, else: :ok
      {:error, _unsafe} -> {:error, :unsafe_path}
    end
  end

  defp write_all(_root, _name, [], _opts), do: {:error, :empty}

  defp write_all(root, name, files, opts) do
    with :ok <- root_limit(root, files, opts[:max_root_bytes]),
         :ok <- fresh(root, name) do
      write_files(root, name, files)
    end
  end

  defp root_limit(_root, _files, nil), do: :ok

  defp root_limit(root, files, max_bytes) do
    bytes =
      Enum.reduce(files, 0, fn {_part, _locale, content}, sum -> sum + byte_size(content) end)

    if Files.usage(root).bytes + bytes > max_bytes, do: {:error, :root_limit}, else: :ok
  end

  defp write_files(root, name, files) do
    Enum.reduce_while(files, {:ok, []}, fn {part, locale, content}, {:ok, paths} ->
      case Overrides.write(root, name, part, locale, content) do
        {:ok, written} ->
          {:cont, {:ok, paths ++ written}}

        {:error, reason} ->
          _ = Overrides.delete_template(root, name)
          {:halt, {:error, reason}}
      end
    end)
  end
end
