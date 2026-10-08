defmodule PhoenixKitTemplatesEditor.DataCase do
  @moduledoc """
  Test case for tests that hit the database.

  Tests using this case are tagged `:integration` and are excluded
  automatically when PostgreSQL is unavailable, so `mix test` still runs the
  unit half on a machine with no database.

      defmodule PhoenixKitTemplatesEditor.Integration.SomethingTest do
        use PhoenixKitTemplatesEditor.DataCase, async: true
      end
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @moduletag :integration

      alias PhoenixKitTemplatesEditor.Test.Repo
    end
  end

  alias Ecto.Adapters.SQL.Sandbox
  alias PhoenixKitTemplatesEditor.Test.Repo, as: TestRepo

  setup tags do
    pid = Sandbox.start_owner!(TestRepo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end
end
