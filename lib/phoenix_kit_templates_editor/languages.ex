defmodule PhoenixKitTemplatesEditor.Languages do
  @moduledoc """
  The entries of the editor's language switcher
  (`PhoenixKitWeb.Components.LanguageSwitcher.language_switcher/1`).

  The editor's languages are the host's `locales` — base codes (`et`, `en`),
  not PhoenixKit's enabled languages. Each gets its name and flag from
  PhoenixKit's language list, looked up by the default dialect of the base
  code (`en` ↔ `en-US`), and shown by the language's own name (Eesti, Русский,
  English), never translated into the page's language. The files are never
  renamed: an entry's `code` is the base code the files carry.

  The files without a language (the *Default*) are the last entry, with the
  empty string as its code — what the editor's `locale` event reads as `nil`.
  """

  alias PhoenixKit.Modules.Languages
  alias PhoenixKit.Modules.Languages.DialectMapper

  @doc """
  The switcher's entries for `tabs`: language codes in order, and `nil` for
  the files without a language, which is shown last as `default_label`.
  """
  @spec items([String.t() | nil], String.t()) :: [map()]
  def items(tabs, default_label) do
    codes = Enum.filter(tabs, &is_binary/1)

    languages(codes) ++
      if(nil in tabs, do: [%{code: "", name: default_label, short_code: default_label}], else: [])
  end

  @doc "The entries for the language codes `codes`, in order."
  @spec languages([String.t()]) :: [map()]
  def languages(codes), do: Enum.map(codes, &entry/1)

  # Each language by its own name (Eesti, Русский, English) whatever the
  # language of the page: a person looks for their language by how it is
  # written there. PhoenixKit's native name carries the country of a dialect
  # ("English (US)"), which one base code does not need.
  defp entry(code) do
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
