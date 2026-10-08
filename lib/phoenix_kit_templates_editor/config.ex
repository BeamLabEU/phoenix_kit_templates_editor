defmodule PhoenixKitTemplatesEditor.Config do
  @moduledoc """
  The host's `config :phoenix_kit_templates_editor`, read and checked.

      config :phoenix_kit_templates_editor,
        root: nil,
        editable: false,
        name_prefixes: ["shop_order_", "_header-shop", "_footer-shop"],
        locales: ~w(et ru en),
        base_locale: "et",
        layout_group: "shop",
        preview: {MyApp.Emails, :preview},
        sample_variables: {MyApp.Emails, :sample_variables},
        block_placeholders: ["documents_list"],
        catalog: true

  | Key | Default | Meaning |
  |---|---|---|
  | `root` | first of `PhoenixKit.Email.Content.override_paths/0` | the templates directory; must exist |
  | `editable` | `false` | `true` (exactly) allows writing; anything else is read-only |
  | `name_prefixes` | `[]` | which templates the editor sees and writes; `[]` shows none |
  | `locales` | PhoenixKit's enabled languages (base codes), else `[base_locale]` | the language tabs, in order |
  | `base_locale` | first of `locales`, else PhoenixKit's default language, else `"en"` | the language labels and notes fall back to |
  | `layout_group` | `nil` | the layout (`_header-<g>`, `_footer-<g>`, `_layout-<g>`) of an email without `layout.txt` |
  | `layout_groups` | `[layout_group]` | layout namespaces the editor may show and write: `g` and `g-…` |
  | `preview` | `nil` | `(name, locale) -> {subject, html, text}`; `nil` — the module's own preview |
  | `sample_variables` | `%{}` | a map, or `() -> map` |
  | `describe_variables` | `nil` | `(name) -> %{variable => description}` |
  | `complete?` | `nil` | `(name, locale) -> boolean`; `nil` — subject and body on `base_locale` |
  | `sent_by` | `nil` | `(name) -> :core \\| :host` |
  | `test_send` | `nil` | `(name, locale, scope) -> :ok \\| {:error, reason}` |
  | `block_placeholders` | `[]` | variables that stand as a block of their own (taken out of `<p>`) |
  | `raw_variables` | `[]` | variables allowed in `{{{x}}}` besides `content`, `header`, `footer` |
  | `email_fallback` | `true` | whether emails get a locale-less *Fallback* tab |
  | `shared_layout_editable` | `false` | whether the shared `_header`/`_footer`/`_layout` (core's system emails) are editable |
  | `overridable` | `:all` | which catalogue emails may get a file: `:all` or a list of names |
  | `catalog` | `false` | whether the templates are offered to core's email preview |
  | `watch` | `editable` | whether a watcher re-reads the files on change |

  Callbacks are `{module, function}` or a function of the given arity.

  `load/1` never raises: a bad value is an `{:error, messages}` the section
  shows instead of the editor. The messages name the key, never a file path.
  Keys it does not know are ignored.
  """

  alias PhoenixKit.Email.Content
  alias PhoenixKit.Email.Layout
  alias PhoenixKit.Modules.Languages
  alias PhoenixKit.Modules.Languages.DialectMapper
  alias PhoenixKit.Templates.Overrides

  @type callback :: {module(), atom()} | function() | nil

  @type t :: %__MODULE__{
          root: Path.t(),
          editable: boolean(),
          name_prefixes: [String.t()],
          locales: [String.t()],
          base_locale: String.t(),
          layout_group: String.t() | nil,
          layout_groups: [String.t()],
          preview: callback(),
          sample_variables: map() | callback(),
          describe_variables: callback(),
          complete?: callback(),
          sent_by: callback(),
          test_send: callback(),
          block_placeholders: [String.t()],
          raw_variables: [String.t()],
          email_fallback: boolean(),
          shared_layout_editable: boolean(),
          overridable: :all | [String.t()],
          catalog: boolean(),
          watch: boolean()
        }

  defstruct root: nil,
            editable: false,
            name_prefixes: [],
            locales: [],
            base_locale: "en",
            layout_group: nil,
            layout_groups: [],
            preview: nil,
            sample_variables: %{},
            describe_variables: nil,
            complete?: nil,
            sent_by: nil,
            test_send: nil,
            block_placeholders: [],
            raw_variables: [],
            email_fallback: true,
            shared_layout_editable: false,
            overridable: :all,
            catalog: false,
            watch: false

  # `PhoenixKit.Templates.Overrides`' own locale pattern.
  @locale_pattern ~r/\A[A-Za-z]{2,3}(-[A-Za-z0-9]{1,8}){0,3}\z/
  # `PhoenixKit.Templates.Substitution`'s variable name.
  @variable_pattern ~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/
  # A prefix of a valid template name: the name pattern of `Overrides`.
  @prefix_pattern ~r/\A_?[a-z0-9][a-z0-9_\-]*\z/

  @callbacks [
    preview: 2,
    describe_variables: 1,
    complete?: 2,
    sent_by: 1,
    test_send: 3
  ]

  @doc """
  Reads `env` (the application environment of `:phoenix_kit_templates_editor`
  by default) into a `t:t/0`, or every problem found.
  """
  @spec load(keyword()) :: {:ok, t()} | {:error, [String.t()]}
  def load(env \\ Application.get_all_env(:phoenix_kit_templates_editor)) do
    results =
      [
        root: root(Keyword.get(env, :root)),
        editable: boolean(env, :editable, false),
        name_prefixes: strings(env, :name_prefixes, &Regex.match?(@prefix_pattern, &1)),
        sample_variables: sample_variables(Keyword.get(env, :sample_variables)),
        block_placeholders:
          strings(env, :block_placeholders, &Regex.match?(@variable_pattern, &1)),
        raw_variables: strings(env, :raw_variables, &Regex.match?(@variable_pattern, &1)),
        email_fallback: boolean(env, :email_fallback, true),
        shared_layout_editable: boolean(env, :shared_layout_editable, false),
        catalog: boolean(env, :catalog, false),
        overridable: overridable(Keyword.get(env, :overridable, :all))
      ] ++
        Enum.map(@callbacks, fn {key, arity} ->
          {key, callback(key, Keyword.get(env, key), arity)}
        end) ++
        locales(Keyword.get(env, :locales), Keyword.get(env, :base_locale)) ++
        layout_groups(Keyword.get(env, :layout_group), Keyword.get(env, :layout_groups)) ++
        watch(Keyword.get(env, :watch), Keyword.get(env, :editable))

    case for({_key, {:error, message}} <- results, do: message) do
      [] -> {:ok, struct!(__MODULE__, for({key, {:ok, value}} <- results, do: {key, value}))}
      messages -> {:error, messages}
    end
  end

  @doc """
  The root the watcher looks after (`PhoenixKitTemplatesEditor.Watcher`):
  `{:ok, root}` where the files are edited (`editable` is exactly `true`) or
  watched (`watch: true`) — `watch` given as a boolean wins — `:off`
  elsewhere, and with a root that is not a directory. Reads only `root`,
  `editable` and `watch`: no database, so it is safe at boot.
  """
  @spec watch_root(keyword()) :: {:ok, Path.t()} | :off
  def watch_root(env \\ Application.get_all_env(:phoenix_kit_templates_editor)) do
    with [watch: {:ok, true}] <- watch(Keyword.get(env, :watch), Keyword.get(env, :editable)),
         {:ok, root} <- root(Keyword.get(env, :root)) do
      {:ok, root}
    else
      _off -> :off
    end
  rescue
    _ -> :off
  end

  # ── root ────────────────────────────────────────────────────────────────

  defp root(nil) do
    case Content.override_paths() do
      [path | _] when is_binary(path) ->
        root(path)

      _none ->
        {:error,
         "root: not set, and core has no template path " <>
           "(config :phoenix_kit, :template_paths, or the host app's priv/phoenix_kit_templates)"}
    end
  end

  defp root(path) when is_binary(path) and path != "" do
    expanded = Path.expand(path)

    if File.dir?(expanded),
      do: {:ok, expanded},
      else: {:error, "root: the directory does not exist"}
  end

  defp root(_other), do: {:error, "root: expected a directory path (a string) or nil"}

  # ── scalars and lists ───────────────────────────────────────────────────

  defp boolean(env, key, default) do
    case Keyword.get(env, key, default) do
      value when is_boolean(value) -> {:ok, value}
      value -> {:error, "#{key}: expected true or false, got #{inspect(value)}"}
    end
  end

  defp strings(env, key, valid?) do
    case Keyword.get(env, key, []) do
      list when is_list(list) ->
        case Enum.reject(list, &(is_binary(&1) and valid?.(&1))) do
          [] -> {:ok, Enum.uniq(list)}
          bad -> {:error, "#{key}: invalid entries #{inspect(bad)}"}
        end

      value ->
        {:error, "#{key}: expected a list of strings, got #{inspect(value)}"}
    end
  end

  defp overridable(:all), do: {:ok, :all}

  defp overridable(names) when is_list(names) do
    case Enum.reject(names, &Overrides.valid_name?/1) do
      [] -> {:ok, Enum.uniq(names)}
      bad -> {:error, "overridable: invalid template names #{inspect(bad)}"}
    end
  end

  defp overridable(value),
    do: {:error, "overridable: expected :all or a list of template names, got #{inspect(value)}"}

  defp watch(nil, editable), do: [watch: {:ok, editable == true}]
  defp watch(value, _editable) when is_boolean(value), do: [watch: {:ok, value}]

  defp watch(value, _editable),
    do: [watch: {:error, "watch: expected true or false, got #{inspect(value)}"}]

  # ── callbacks ───────────────────────────────────────────────────────────

  defp sample_variables(nil), do: {:ok, %{}}
  defp sample_variables(map) when is_map(map), do: {:ok, map}
  defp sample_variables(value), do: callback(:sample_variables, value, 0)

  defp callback(_key, nil, _arity), do: {:ok, nil}

  defp callback(key, {module, function} = callback, arity)
       when is_atom(module) and is_atom(function) do
    if Code.ensure_loaded?(module) and function_exported?(module, function, arity),
      do: {:ok, callback},
      else: {:error, "#{key}: #{inspect(module)}.#{function}/#{arity} is not defined"}
  end

  defp callback(_key, fun, arity) when is_function(fun, arity), do: {:ok, fun}

  defp callback(key, value, arity) do
    {:error,
     "#{key}: expected {module, function} or a function of arity #{arity}, got #{inspect(value)}"}
  end

  # ── locales ─────────────────────────────────────────────────────────────

  defp locales(locales, base) do
    with {:ok, locales} <- given_locales(locales),
         {:ok, base} <- given_base(base) do
      resolve_locales(locales, base)
    else
      {:error, key, message} -> [{key, {:error, message}}]
    end
  end

  defp given_locales(nil), do: {:ok, nil}

  defp given_locales([_ | _] = locales) do
    case Enum.reject(locales, &locale?/1) do
      [] -> {:ok, Enum.uniq(locales)}
      bad -> {:error, :locales, "locales: invalid locales #{inspect(bad)}"}
    end
  end

  defp given_locales(value),
    do: {:error, :locales, "locales: expected a non-empty list of locales, got #{inspect(value)}"}

  defp given_base(nil), do: {:ok, nil}

  defp given_base(base) do
    if locale?(base),
      do: {:ok, base},
      else: {:error, :base_locale, "base_locale: invalid locale #{inspect(base)}"}
  end

  defp resolve_locales(nil, base) do
    base = base || phoenix_kit_default_base()
    derived = phoenix_kit_locales()
    locales = if base in derived, do: derived, else: [base | derived]
    [locales: {:ok, locales}, base_locale: {:ok, base}]
  end

  defp resolve_locales(locales, nil),
    do: [locales: {:ok, locales}, base_locale: {:ok, hd(locales)}]

  defp resolve_locales(locales, base) do
    if base in locales do
      [locales: {:ok, locales}, base_locale: {:ok, base}]
    else
      [base_locale: {:error, "base_locale: #{inspect(base)} is not one of the locales"}]
    end
  end

  defp locale?(value), do: is_binary(value) and Regex.match?(@locale_pattern, value)

  # PhoenixKit's languages are dialects ("et-EE"); template files and tabs go
  # by the base code, which the template lookup falls back to anyway.
  defp phoenix_kit_locales do
    if Languages.enabled?() do
      Languages.get_enabled_language_codes()
      |> Enum.map(&DialectMapper.extract_base/1)
      |> Enum.uniq()
    else
      []
    end
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  defp phoenix_kit_default_base do
    case Languages.get_default_language() do
      %{code: code} when is_binary(code) -> DialectMapper.extract_base(code)
      _none -> "en"
    end
  rescue
    _ -> "en"
  catch
    :exit, _ -> "en"
  end

  # ── layout groups ───────────────────────────────────────────────────────

  defp layout_groups(group, groups) do
    with {:ok, group} <- layout_group(group),
         {:ok, groups} <- given_layout_groups(groups, group) do
      if is_nil(group) or Enum.any?(groups, &in_namespace?(group, &1)) do
        [layout_group: {:ok, group}, layout_groups: {:ok, groups}]
      else
        [layout_group: {:error, "layout_group: #{inspect(group)} is outside layout_groups"}]
      end
    else
      {:error, key, message} -> [{key, {:error, message}}]
    end
  end

  defp layout_group(nil), do: {:ok, nil}

  defp layout_group(group) do
    if Layout.valid_group?(group),
      do: {:ok, group},
      else: {:error, :layout_group, "layout_group: invalid group name #{inspect(group)}"}
  end

  defp given_layout_groups(nil, nil), do: {:ok, []}
  defp given_layout_groups(nil, group), do: {:ok, [group]}

  defp given_layout_groups(groups, _group) when is_list(groups) do
    case Enum.reject(groups, &Layout.valid_group?/1) do
      [] -> {:ok, Enum.uniq(groups)}
      bad -> {:error, :layout_groups, "layout_groups: invalid group names #{inspect(bad)}"}
    end
  end

  defp given_layout_groups(value, _group),
    do:
      {:error, :layout_groups,
       "layout_groups: expected a list of group names, got #{inspect(value)}"}

  # "andi" covers "andi" and "andi-…", not "andix".
  defp in_namespace?(group, namespace),
    do: group == namespace or String.starts_with?(group, namespace <> "-")
end
