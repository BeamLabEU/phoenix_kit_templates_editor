defmodule PhoenixKitTemplatesEditor.SectionCase do
  @moduledoc """
  Helpers for the section (`PhoenixKitTemplatesEditor.Web.Section`): the
  host's config set for one test (and restored), the section mounted in
  `PhoenixKitTemplatesEditor.Test.SectionHost` — core's page in miniature —
  with a scope and a page language.

  Not async-safe: the config is the application environment.
  """

  import Phoenix.ConnTest, only: [build_conn: 0]
  import Phoenix.LiveViewTest

  alias PhoenixKit.Users.Auth.Scope

  @endpoint PhoenixKitTemplatesEditor.Test.Endpoint

  @config_keys ~w(root editable name_prefixes locales base_locale layout_group layout_groups
                  preview sample_variables describe_variables complete? sent_by test_send
                  block_placeholders raw_variables email_fallback shared_layout_editable
                  overridable catalog watch)a

  @doc "Sets the keys of `config :phoenix_kit_templates_editor` to `values` for this test."
  def configure(values) do
    previous =
      for key <- @config_keys,
          do: {key, Application.fetch_env(:phoenix_kit_templates_editor, key)}

    for key <- @config_keys, do: Application.delete_env(:phoenix_kit_templates_editor, key)
    for {key, value} <- values, do: Application.put_env(:phoenix_kit_templates_editor, key, value)

    ExUnit.Callbacks.on_exit(fn -> Enum.each(previous, &restore/1) end)
  end

  defp restore({key, {:ok, value}}),
    do: Application.put_env(:phoenix_kit_templates_editor, key, value)

  defp restore({key, :error}), do: Application.delete_env(:phoenix_kit_templates_editor, key)

  @doc "A scope holding `keys`."
  def scope(keys), do: %Scope{cached_permissions: MapSet.new(keys)}

  @doc "Every key the editor needs to write."
  def writer, do: scope(["settings", "templates_editor", "templates_editor.write"])

  @doc "Mounts the section; `opts`: `:scope`, `:locale`."
  def mount_section(opts \\ []) do
    session = %{"scope" => opts[:scope], "locale" => opts[:locale]}

    {:ok, view, _html} =
      live_isolated(build_conn(), PhoenixKitTemplatesEditor.Test.SectionHost, session: session)

    view
  end

  @doc "Writes `content` to `<root>/<name>/<file>`."
  def put(root, name, file, content) do
    File.mkdir_p!(Path.join(root, name))
    File.write!(Path.join([root, name, file]), content)
  end
end
