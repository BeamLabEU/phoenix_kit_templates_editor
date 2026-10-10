defmodule PhoenixKitTemplatesEditor.Names do
  @moduledoc """
  Which template names an editor may show and write.

  A name is one of three kinds:

    * **a shared layout part** — `_header`, `_footer`, `_layout`. Core's own
      emails (sign-in, password reset) are wrapped in them, so they are
      refused unless the host says `shared_layout_editable: true`, whatever
      the name prefixes say;
    * **a layout part of a group** — `_header-<g>`, `_footer-<g>`,
      `_layout-<g>` (`g` as `PhoenixKit.Email.Layout.valid_group?/1`). Allowed
      when `g` is in the namespace of one of `layout_groups`, or of a name
      prefix shaped like such a part (`"_header-andi"` allows the header of
      `andi` and `andi-…`). A namespace is exact: `andi` covers `andi` and
      `andi-supplier`, not `andix`. A plain prefix (`"_"`) never allows one;
    * **anything else** — allowed when it starts with a plain name prefix.

  Before all of that, a name in `reserved` — an email core or another module
  sends (`reserved_names/0`) — is refused, unless the rules' `overridable`
  lets it in (`overridable?/2`): `:all` is every such email
  but core's emails about getting into an account (`auth_emails/0`), a
  list exactly its names.
  The same goes for a part of a module's own layout group (`module_groups`,
  the groups catalogue entries name with `layout: "<g>"`, exact — not
  namespaces): `_header-billing` is allowed only when it is overridable.

  `overridable` and `module_groups` are optional in the rules: without them
  nothing is overridden.
  """

  require Logger

  alias PhoenixKit.Email.CoreTemplates
  alias PhoenixKit.Email.Layout
  alias PhoenixKit.ModuleRegistry

  @type kind :: :header | :footer | :layout

  @type overridable :: :all | [String.t()]

  @type rules :: %{
          required(:prefixes) => [String.t()],
          required(:layout_groups) => [String.t()],
          required(:shared_layout_editable) => boolean(),
          required(:reserved) => [String.t()],
          optional(:overridable) => overridable(),
          optional(:module_groups) => [String.t()]
        }

  @kinds [:header, :footer, :layout]
  @kind_names Map.new(@kinds, &{Atom.to_string(&1), &1})

  # Core's emails about getting into an account: each
  # carries a link that signs a user in, registers or confirms an address
  # (`confirmation_url`, `reset_url`, `update_url`, `magic_link_url`,
  # `registration_url`), or warns the owner about a sign-in
  # (`security_url`). A file that breaks one locks people out, or hides an
  # intrusion from them. The test checks every email of
  # `PhoenixKit.Email.CoreTemplates` is either here or named as not about
  # access, so a new one is decided on, not let through.
  @auth_emails ~w(register reset_password update_email magic_link magic_link_registration
                  organization_invitation new_login_alert failed_login_alert)

  @chrome ~r/\A_(header|footer|layout)(?:-([a-z0-9-]+))?\z/

  @doc "The parts of a layout, in order: `[:header, :footer, :layout]`."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc """
  `{kind, group}` for a layout part (`group` is `nil` for a shared one),
  `nil` for any other name.
  """
  @spec chrome(term()) :: {kind(), String.t() | nil} | nil
  def chrome(name) when is_binary(name) do
    case Regex.run(@chrome, name, capture: :all_but_first) do
      [kind] -> {Map.fetch!(@kind_names, kind), nil}
      [kind, ""] -> {Map.fetch!(@kind_names, kind), nil}
      [kind, group] -> {Map.fetch!(@kind_names, kind), group}
      nil -> nil
    end
  end

  def chrome(_name), do: nil

  @doc "The template name of part `kind` of `group` (`nil` — the shared part)."
  @spec part_name(kind(), String.t() | nil) :: String.t()
  def part_name(kind, nil), do: "_#{kind}"
  def part_name(kind, group), do: "_#{kind}-#{group}"

  @doc "Whether `group` is `namespace` or one of its `namespace-…`."
  @spec in_namespace?(String.t(), String.t()) :: boolean()
  def in_namespace?(group, namespace),
    do: group == namespace or String.starts_with?(group, namespace <> "-")

  @doc """
  `:ok` when `rules` allow `name`, else why not: `:reserved`, `:shared`,
  `:namespace` (a layout part outside every namespace) or `:prefix`.
  """
  @spec check(term(), rules()) :: :ok | {:error, :reserved | :shared | :namespace | :prefix}
  def check(name, rules) when is_binary(name) do
    cond do
      name not in rules.reserved -> check_kind(chrome(name), name, rules)
      overridable?(name, Map.get(rules, :overridable)) -> :ok
      true -> {:error, :reserved}
    end
  end

  def check(_name, _rules), do: {:error, :prefix}

  defp check_kind({_kind, nil}, _name, rules) do
    if rules.shared_layout_editable == true, do: :ok, else: {:error, :shared}
  end

  defp check_kind({kind, group}, name, rules) do
    cond do
      part_allowed?(kind, group, rules) -> :ok
      module_part?(name, group, rules) -> :ok
      true -> {:error, :namespace}
    end
  end

  defp check_kind(nil, name, rules) do
    if String.starts_with?(name, plain_prefixes(rules)), do: :ok, else: {:error, :prefix}
  end

  defp module_part?(name, group, rules) do
    group in Map.get(rules, :module_groups, []) and
      overridable?(name, Map.get(rules, :overridable))
  end

  @doc "Whether `rules` allow part `kind` of `group`."
  @spec part_allowed?(kind(), String.t(), rules()) :: boolean()
  def part_allowed?(kind, group, rules) do
    Layout.valid_group?(group) and
      Enum.any?(rules.layout_groups ++ prefix_namespaces(rules, kind), &in_namespace?(group, &1))
  end

  @doc "Whether `rules` allow any part of `group`."
  @spec group_allowed?(String.t(), rules()) :: boolean()
  def group_allowed?(group, rules), do: Enum.any?(@kinds, &part_allowed?(&1, group, rules))

  @doc "The namespaces `rules` allow layouts in, for messages: `layout_groups`, then the prefixes'."
  @spec namespaces(rules()) :: [String.t()]
  def namespaces(rules) do
    Enum.uniq(rules.layout_groups ++ Enum.flat_map(@kinds, &prefix_namespaces(rules, &1)))
  end

  defp prefix_namespaces(rules, kind) do
    for prefix <- rules.prefixes,
        {^kind, group} when is_binary(group) <- [chrome(prefix)],
        do: group
  end

  defp plain_prefixes(rules), do: Enum.reject(rules.prefixes, &chrome/1)

  @doc """
  The names of core's emails about getting into an account: those with a
  link that signs in, registers or confirms (account confirmation,
  password reset, email change, magic link sign-in and registration,
  organization invitation) and the sign-in alerts (new login, failed
  sign-ins). Never overridable by `:all`, only by name, and warned about
  when they are.
  """
  @spec auth_emails() :: [String.t()]
  def auth_emails, do: @auth_emails

  @doc """
  Whether a name core or a module sends may be given a file here:
  `overridable` `:all` — any but `auth_emails/0`; a list — exactly its
  names; anything else — none.
  """
  @spec overridable?(String.t(), term()) :: boolean()
  def overridable?(name, :all), do: name not in @auth_emails
  def overridable?(name, names) when is_list(names), do: name in names
  def overridable?(_name, _none), do: false

  @doc """
  The layout groups catalogue `entries` name (`layout: "<g>"`, a valid
  group), each once, in order.
  """
  @spec module_groups([map()]) :: [String.t()]
  def module_groups(entries) do
    for(%{layout: group} <- entries, Layout.valid_group?(group), do: group) |> Enum.uniq()
  end

  @doc """
  The names of the emails core and every other registered module send
  (`PhoenixKit.Email.CoreTemplates`, `c:PhoenixKit.Module.email_templates/0`)
  — never this module's own, which are the host's files. A catalogue that
  fails to answer is logged and skipped; core's sign-in emails
  (`auth_emails/0`) are reserved even then.
  """
  @spec reserved_names() :: [String.t()]
  def reserved_names, do: reserved_names(&CoreTemplates.entries/0)

  @doc false
  # `core_entries` stands in for core's catalogue in the tests.
  @spec reserved_names((-> [map()])) :: [String.t()]
  def reserved_names(core_entries) when is_function(core_entries, 0) do
    core = safely(:core, core_entries)

    modules =
      for module <- registered_modules(),
          module != PhoenixKitTemplatesEditor,
          entry <- safely(module, fn -> module_templates(module) end),
          do: entry

    Enum.uniq(
      @auth_emails ++ for(%{name: name} when is_binary(name) <- core ++ modules, do: name)
    )
  end

  defp registered_modules, do: safely(:registry, &ModuleRegistry.all_modules/0)

  defp module_templates(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :email_templates, 0),
      do: List.wrap(module.email_templates()),
      else: []
  end

  defp safely(source, fun) do
    fun.()
  rescue
    exception -> log_reserved(source, Exception.message(exception))
  catch
    kind, reason -> log_reserved(source, Exception.format_banner(kind, reason))
  end

  defp log_reserved(source, message) do
    Logger.warning(
      "[PhoenixKitTemplatesEditor] reserved names: #{inspect(source)} failed: #{message}"
    )

    []
  end
end
