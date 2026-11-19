defmodule PhoenixKitTemplatesEditor.Languages do
  @moduledoc """
  The entries of the editor's language switcher
  (`PhoenixKitWeb.Components.LanguageSwitcher.language_switcher/1`), drawn
  the way core's `multilang_tabs` draws a record's languages.

  The editor's languages are the host's `locales` — base codes (`et`, `en`),
  not PhoenixKit's enabled languages. A code that is the base of an enabled
  language is shown as that language is shown on every other form (the name
  and flag of `PhoenixKit.Utils.Multilang.build_language_tabs/0`). Any other
  code gets its own name and flag from PhoenixKit's language list, looked up
  by the default dialect of the base code (`en` ↔ `en-US`). The files are
  never renamed: an entry's `code` is the base code the files carry.

  The files without a language (the *Default*) are the last entry, with the
  empty string as its code — what the editor's `locale` event reads as `nil`.
  """

  alias PhoenixKit.Modules.Languages
  alias PhoenixKit.Modules.Languages.DialectMapper
  alias PhoenixKit.Utils.Multilang

  @doc """
  The switcher's entries for `tabs`: language codes in order, and `nil` for
  the files without a language, which is shown last as `default_label`.
  `primary` is the code marked as the primary language (the star).
  """
  @spec items([String.t() | nil], String.t(), String.t() | nil) :: [map()]
  def items(tabs, default_label, primary \\ nil) do
    codes = Enum.filter(tabs, &is_binary/1)

    with_default(languages(codes, primary), tabs, default_label)
  end

  @doc false
  def with_default(languages, tabs, default_label) do
    languages ++
      if(nil in tabs,
        do: [%{code: "", name: default_label, short_code: default_label, is_primary: false}],
        else: []
      )
  end

  @doc "The entries for the language codes `codes`, in order."
  @spec languages([String.t()], String.t() | nil) :: [map()]
  def languages(codes, primary \\ nil) do
    enabled = enabled_tabs()
    Enum.map(codes, &(&1 |> entry(enabled) |> Map.put(:is_primary, &1 == primary)))
  end

  defp enabled_tabs do
    Multilang.build_language_tabs()
  rescue
    _ -> []
  end

  defp entry(code, enabled) do
    case Enum.find(enabled, &(DialectMapper.extract_base(&1.code) == code)) do
      %{name: name} = tab ->
        %{code: code, name: name, flag: tab[:flag], short_code: String.upcase(code)}

      nil ->
        predefined(code)
    end
  end

  # A language PhoenixKit has not enabled: by its own name (Eesti, Русский).
  # PhoenixKit's native name carries the country of a dialect ("English (US)"),
  # which one base code does not need.
  defp predefined(code) do
    case Languages.get_predefined_language(DialectMapper.base_to_dialect(code)) do
      nil ->
        %{code: code, name: String.upcase(code), flag: nil, short_code: String.upcase(code)}

      info ->
        %{code: code, name: own_name(info), flag: info.flag, short_code: String.upcase(code)}
    end
  end

  defp own_name(%{native: native}) when is_binary(native) and native != "",
    do: native |> String.replace(~r/\s*\(.*\)\s*$/, "") |> String.trim()

  defp own_name(%{name: name}), do: name
end
