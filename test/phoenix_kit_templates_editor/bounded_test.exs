defmodule PhoenixKitTemplatesEditor.BoundedTest do
  use ExUnit.Case, async: true

  alias PhoenixKitTemplatesEditor.Bounded

  test "the work's result" do
    assert Bounded.run(fn -> 1 + 1 end) == {:ok, 2}
  end

  test "work past the deadline is killed and reported" do
    parent = self()

    assert Bounded.run(
             fn ->
               send(parent, {:worker, self()})
               Process.sleep(:infinity)
             end,
             50
           ) == {:error, :timeout}

    assert_received {:worker, worker}
    refute Process.alive?(worker)
  end

  test "an exception, a throw and an exit reach the caller as they were" do
    assert_raise RuntimeError, "boom", fn -> Bounded.run(fn -> raise "boom" end) end
    assert catch_throw(Bounded.run(fn -> throw(:ball) end)) == :ball
    assert catch_exit(Bounded.run(fn -> exit(:gone) end)) == :gone
  end

  test "the page's language goes along" do
    Gettext.put_locale(PhoenixKitTemplatesEditor.Gettext, "et")

    assert Bounded.run(fn -> Gettext.get_locale(PhoenixKitTemplatesEditor.Gettext) end) ==
             {:ok, "et"}
  end
end
