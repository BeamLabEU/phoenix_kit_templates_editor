defmodule PhoenixKitTemplatesEditor.Variables do
  @moduledoc """
  Which placeholders a part may hold, by the kind of template it belongs to
  — for the editor's variables panel and its check on saving.

    * **An email** (no leading `_`) is rendered with its own variables:
      the catalogue entry's samples for an email core or a module sends,
      the host's `sample_variables` for the host's own. The branding
      (`{{logo_url}}`, `{{accent_color}}`, `PhoenixKit.Email.Branding`) is
      there too — in the Markdown part for an email the host sends, in every
      part when core sends it (`PhoenixKit.Email.Content` binds it so).
    * **A header or footer** (`_header…`, `_footer…`, any other name with a
      leading `_`) has the layout's variables (`PhoenixKit.Email.Layout`:
      `subject`, `site_name`, `site_url`, `logo_url`, `accent_color`) — not
      an email's: the parts are shared by every email of the layout.
    * **A page layout** (`_layout…`) has those and the rendered `content`,
      `header` and `footer`.

  A placeholder of the other kind — `{{site_url}}` in an email's body
  where the email does not pass it, an email's variable in a footer — is
  *forbidden here*: it stays in the message as typed. One of neither kind
  is *unknown*. `{{{x}}}` (inserted without escaping) is allowed only for
  the host's `raw_variables` and, in a page layout, `content`, `header` and
  `footer`; anywhere else it is refused, since its value would go into the
  message unescaped. The `label` part is never
  sent and is not checked.
  """

  alias PhoenixKit.Email.Branding
  alias PhoenixKit.Email.Layout

  @html_variables ~w(content header footer)

  # `PhoenixKit.Templates.Substitution`'s placeholder: it starts with
  # literal braces, so a long input cannot make it backtrack.
  @placeholder ~r/\{\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}\}|\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}/

  @type kind :: :email | :chrome | :layout

  @type context :: %{
          kind: kind(),
          email: %{String.t() => term()},
          layout: %{String.t() => term()},
          raw: [String.t()],
          sent_by: :core | :host,
          descriptions: %{String.t() => String.t()}
        }

  @type findings :: %{forbidden: [String.t()], unknown: [String.t()], raw: [String.t()]}

  @type row :: %{
          name: String.t(),
          sample: String.t() | nil,
          description: String.t() | nil,
          scope: :all | :markdown | :html
        }

  @doc "The kind of template `name` is (see the moduledoc)."
  @spec kind(String.t()) :: kind()
  def kind("_layout" <> _), do: :layout
  def kind("_" <> _), do: :chrome
  def kind(_email), do: :email

  @doc """
  The context of template `name`. `opts`: `:email` (its variables, a map of
  name to sample), `:layout` (`layout_variables/1`), `:raw` (the host's
  `raw_variables`), `:sent_by` (`:core` or `:host`, default `:host`) and
  `:descriptions` (name to text).
  """
  @spec context(String.t(), map() | keyword()) :: context()
  def context(name, opts) do
    opts = Map.new(opts)

    %{
      kind: kind(name),
      email: stringify(Map.get(opts, :email, %{})),
      layout: stringify(Map.get(opts, :layout, %{})),
      raw: Map.get(opts, :raw, []),
      sent_by: if(Map.get(opts, :sent_by) == :core, do: :core, else: :host),
      descriptions: stringify(Map.get(opts, :descriptions) || %{})
    }
  end

  @doc """
  The variables core gives a header, footer and page layout, with this
  site's values (`PhoenixKit.Email.Layout.render_parts/2` of `group`,
  rendered without reading any file). `%{}` when that fails.
  """
  @spec layout_variables(String.t() | nil) :: %{String.t() => term()}
  def layout_variables(group) do
    Layout.render_parts(nil, group: group, paths: []).variables
  rescue
    _ -> %{}
  end

  @doc """
  The placeholder names in `content`: written with two braces, and with
  three — each once, in order of first use.
  """
  @spec placeholders(String.t()) :: %{double: [String.t()], triple: [String.t()]}
  def placeholders(content) when is_binary(content) do
    matches = Regex.scan(@placeholder, content, capture: :all_but_first)

    %{
      double: for([_triple, double] <- matches, double != "", do: double) |> Enum.uniq(),
      triple: for([triple | _] <- matches, triple != "", do: triple) |> Enum.uniq()
    }
  end

  @doc """
  What is wrong with the placeholders in `content`, part `part` of the
  template `context` describes: `raw` — names in `{{{x}}}` not allowed so;
  `forbidden` — names of the other kind of template; `unknown` — the
  rest that are not allowed here.
  """
  @spec check(String.t(), atom(), context()) :: findings()
  def check(_content, :label, _context), do: %{forbidden: [], unknown: [], raw: []}

  def check(content, part, context) do
    %{double: double, triple: triple} = placeholders(content)
    allowed = allowed(context, part)
    other = other_kind(context, part)
    names = Enum.uniq(double ++ triple)

    %{
      forbidden: Enum.filter(names, &(&1 not in allowed and &1 in other)),
      unknown: Enum.reject(names, &(&1 in allowed or &1 in other)),
      raw: Enum.reject(triple, &(&1 in raw_allowed(context)))
    }
  end

  @doc """
  The variables a template of `context` may use, for the panel: name, a
  sample value (as text), the host's description, and where it works —
  `:all`, `:markdown` (the branding in an email the host sends) or `:html`
  (a page layout's rendered parts, with three braces).
  """
  @spec panel(context()) :: [row()]
  def panel(%{kind: :email} = context) do
    own = rows(context.email, context, :all)

    branding_scope = if context.sent_by == :core, do: :all, else: :markdown

    branding =
      context.layout
      |> Map.take(branding_names())
      |> Map.drop(Map.keys(context.email))
      |> rows(context, branding_scope)

    own ++ branding
  end

  def panel(%{kind: kind} = context) do
    html =
      if kind == :layout,
        do: rows(Map.new(@html_variables, &{&1, nil}), context, :html),
        else: []

    rows(context.layout, context, :all) ++ html
  end

  defp rows(variables, context, scope) do
    variables
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {name, sample} ->
      %{
        name: name,
        sample: sample(sample),
        description: Map.get(context.descriptions, name),
        scope: scope
      }
    end)
  end

  defp sample(nil), do: nil
  defp sample(value) when is_binary(value), do: value
  defp sample(value), do: inspect(value)

  defp allowed(%{kind: :email} = context, part) do
    branding =
      if context.sent_by == :core or part == :markdown, do: branding_names(), else: []

    Map.keys(context.email) ++ branding
  end

  defp allowed(%{kind: :chrome} = context, _part), do: Map.keys(context.layout)
  defp allowed(%{kind: :layout} = context, _part), do: Map.keys(context.layout) ++ @html_variables

  # The variables of the other kind of template: present in the message,
  # but not where this part is rendered.
  defp other_kind(%{kind: :email} = context, _part),
    do: Map.keys(context.layout) ++ branding_names() ++ @html_variables

  defp other_kind(context, _part), do: Map.keys(context.email) ++ @html_variables

  defp raw_allowed(%{kind: :layout, raw: raw}), do: raw ++ @html_variables
  defp raw_allowed(%{raw: raw}), do: raw

  defp branding_names, do: Map.keys(Branding.variables())

  defp stringify(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
  defp stringify(_other), do: %{}
end
