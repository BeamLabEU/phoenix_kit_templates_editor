defmodule PhoenixKitTemplatesEditor.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/BeamLabEU/phoenix_kit_templates_editor"

  def project do
    [
      app: :phoenix_kit_templates_editor,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Hex
      description:
        "Email templates editor for PhoenixKit — a tab on the email settings page " <>
          "for the host's phoenix_kit_templates files",
      package: package(),

      # Dialyzer
      dialyzer: [plt_add_apps: [:phoenix_kit, :mix]],

      # Docs
      name: "PhoenixKitTemplatesEditor",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :phoenix_kit]
    ]
  end

  # `test.setup` / `test.reset` touch the test repo, which only compiles in :test.
  def cli do
    [preferred_envs: ["test.setup": :test, "test.reset": :test]]
  end

  # test/support/ is compiled only in :test so the test repo doesn't leak into
  # the published package.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      quality: ["format", "credo --strict", "dialyzer"],
      "quality.ci": ["format --check-formatted", "credo --strict", "dialyzer"],
      precommit: [
        "compile --force --warnings-as-errors",
        "deps.unlock --check-unused",
        # Scan for retired Hex deps. Run via `cmd` so Hex bootstraps in a fresh
        # process — the hex.* archive tasks aren't resolvable via Mix.Task.run
        # inside an alias.
        "cmd mix hex.audit",
        "quality.ci"
      ],
      "test.setup": [
        "ecto.create --quiet -r PhoenixKitTemplatesEditor.Test.Repo"
      ],
      "test.reset": [
        "ecto.drop --quiet -r PhoenixKitTemplatesEditor.Test.Repo",
        "test.setup"
      ]
    ]
  end

  # phoenix_kit deps resolve from Hex by default. For cross-repo work against a
  # local checkout, export <APP>_PATH — e.g. PHOENIX_KIT_PATH=../phoenix_kit or
  # PHOENIX_KIT_TEMPLATES_PATH=../phoenix_kit_templates. Unset => the published
  # pin, so mix hex.publish is unaffected.
  defp pk_dep(app, requirement, opts \\ []) do
    env_var = String.upcase(Atom.to_string(app)) <> "_PATH"

    case System.get_env(env_var) do
      nil when opts == [] -> {app, requirement}
      nil -> {app, requirement, opts}
      path -> {app, [path: path, override: true] ++ opts}
    end
  end

  defp deps do
    [
      # PhoenixKit provides the Module behaviour, Settings and the email
      # settings page this module adds a tab to. 2.57.0 is the floor: the
      # section's `:link` (the button beside "Preview emails") first ships
      # there. Compound form so the ceiling stays open through every later
      # 2.x minor (see test/core_pin_conformance_test.exs).
      pk_dep(:phoenix_kit, ">= 2.57.0 and < 4.0.0"),

      # mdex_native (pulled in transitively through phoenix_kit's mdex dep)
      # builds from source when MDEX_NATIVE_BUILD=1 is set in the
      # environment; that path requires rustler itself, not just
      # rustler_precompiled. Same declaration as phoenix_kit's own mix.exs.
      {:rustler, ">= 0.0.0", optional: true},

      # The template files API (Overrides.write/delete/list/copy_template,
      # first in 0.2.3; 0.2.4 changed only the library's own editor, which
      # this module does not use). Core depends on it too; declared here
      # because this module calls it directly.
      pk_dep(:phoenix_kit_templates, "~> 0.2.3"),

      # LiveView is needed for the settings section.
      {:phoenix_live_view, "~> 1.1"},

      # The module's own translations (priv/gettext).
      {:gettext, "~> 1.0"},

      # Optional: add ex_doc for generating documentation
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},

      # Code quality
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},

      # HTML parser for Phoenix.LiveViewTest in LiveView smoke tests
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "PhoenixKitTemplatesEditor",
      source_ref: @version
    ]
  end
end
