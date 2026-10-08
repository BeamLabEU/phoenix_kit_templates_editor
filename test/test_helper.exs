# Test helper for PhoenixKitTemplatesEditor.
#
# Two levels:
#
#   * unit — the module's callbacks, `Config`, the section's render. Always
#     run, no database needed.
#   * integration — tagged `:integration` via `PhoenixKitTemplatesEditor.DataCase`,
#     excluded automatically when PostgreSQL is unavailable.
#
# First-time setup:
#
#     mix test.setup
#
# The module owns no tables; the schema (settings, roles, permissions) is
# core's, built by `PhoenixKit.Migration.ensure_current/2` — the same call a
# host app makes.

alias PhoenixKitTemplatesEditor.Test.Repo, as: TestRepo

repo_config = Application.get_env(:phoenix_kit_templates_editor, TestRepo, [])
db_name = repo_config[:database]

# One classified connection attempt with the repo's own credentials before
# anything starts the pool: an unreachable database otherwise shows up
# minutes later as pool checkout timeouts that read like flaky tests.
reachable? =
  case PhoenixKit.TestSupport.PostgresPreflight.check(repo_config) do
    :ok ->
      true

    {:error, _reason, message} ->
      IO.puts(:stderr, "\n" <> message)
      false
  end

repo_available =
  reachable? and
    try do
      {:ok, _} = TestRepo.start_link()
      PhoenixKit.Migration.ensure_current(TestRepo, log: false)
      Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual)
      true
    rescue
      e ->
        IO.puts(:stderr, "\nCould not prepare #{inspect(db_name)}: #{Exception.message(e)}")
        false
    catch
      :exit, reason ->
        IO.puts(:stderr, "\nCould not prepare #{inspect(db_name)}: #{inspect(reason)}")
        false
    end

unless repo_available do
  IO.puts("""

    Integration tests excluded — could not reach #{inspect(db_name)}.
    Run: mix test.setup
  """)
end

Application.put_env(:phoenix_kit_templates_editor, :test_repo_available, repo_available)

# Minimal PhoenixKit services: PubSub for settings broadcasts, and the module
# registry — `Scope.can?/2` resolves sub-permissions and module enablement
# through it.
{:ok, _pid} = PhoenixKit.PubSub.Manager.start_link([])
{:ok, _pid} = PhoenixKit.ModuleRegistry.start_link([])

# Routes.path/1 reads the URL prefix from this cache; "/" means none.
:persistent_term.put({PhoenixKit.Config, :url_prefix}, "/")

# The endpoint `live_isolated/3` mounts the editor's test host on.
Application.put_env(:phoenix_kit_templates_editor, PhoenixKitTemplatesEditor.Test.Endpoint,
  secret_key_base: String.duplicate("phoenix_kit_templates_editor", 3),
  live_view: [signing_salt: "editor-test"],
  server: false
)

{:ok, _pid} = PhoenixKitTemplatesEditor.Test.Endpoint.start_link()

if repo_available do
  ExUnit.start()
else
  ExUnit.start(exclude: [:integration])
end
