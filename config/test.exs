import Config

# :error, not :warning — the settings cache is deliberately not started
# (a cached value would outlive each test's sandbox rollback), and core warns
# about the missing cache on every settings read.
config :logger, level: :error

# Integration tests run against a real PostgreSQL database. Create it with:
#   mix test.setup
config :phoenix_kit_templates_editor, ecto_repos: [PhoenixKitTemplatesEditor.Test.Repo]

# `PGDATABASE` lets this suite point at a database the test role isn't
# allowed to CREATE (e.g. a shared instance) instead of the name Hex CI
# provisions for itself. Same mechanism as core phoenix_kit's
# config/test.exs. Left unset (CI's case), this falls back to the module's
# own name.
pg_test_db =
  case System.get_env("PGDATABASE") do
    value when is_binary(value) and value != "" -> String.trim(value)
    _ -> "phoenix_kit_templates_editor_test#{System.get_env("MIX_TEST_PARTITION")}"
  end

# `PGPOOL` bounds the connection pool the same way core does — the default
# (`schedulers_online() * 2`) opens dozens of connections on a many-core
# box, which is fine against a private local Postgres but not against a
# shared instance already near its connection ceiling.
pg_test_pool =
  case System.get_env("PGPOOL") do
    value when is_binary(value) and value != "" ->
      case Integer.parse(String.trim(value)) do
        {size, ""} when size > 0 -> size
        _ -> raise "PGPOOL must be a positive integer, got: #{inspect(value)}"
      end

    _ ->
      System.schedulers_online() * 2
  end

config :phoenix_kit_templates_editor, PhoenixKitTemplatesEditor.Test.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  database: pg_test_db,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: pg_test_pool

# `PhoenixKit.RepoHelper` resolves this — without it every Settings call
# falls into its own rescue and returns a plausible nothing.
config :phoenix_kit, repo: PhoenixKitTemplatesEditor.Test.Repo
