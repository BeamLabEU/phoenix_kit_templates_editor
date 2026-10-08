defmodule PhoenixKitTemplatesEditor.ThrottleTest do
  use ExUnit.Case, async: true

  alias PhoenixKitTemplatesEditor.Throttle

  test "once per interval and key; another key is free" do
    key = {:test, make_ref()}

    assert Throttle.hit(key, 30_000) == :ok
    assert {:error, {:wait, seconds}} = Throttle.hit(key, 30_000)
    assert seconds in 29..30
    assert Throttle.hit({:test, make_ref()}, 30_000) == :ok
  end

  test "free again once the interval is over" do
    key = {:test, make_ref()}

    assert Throttle.hit(key, 20) == :ok
    Process.sleep(30)
    assert Throttle.hit(key, 20) == :ok
  end

  test "of two at the same moment, one goes" do
    key = {:test, make_ref()}

    results =
      1..20
      |> Enum.map(fn _ -> Task.async(fn -> Throttle.hit(key, 30_000) end) end)
      |> Enum.map(&Task.await/1)

    assert Enum.count(results, &(&1 == :ok)) == 1
  end

  test "a module child" do
    assert Throttle in PhoenixKitTemplatesEditor.children()
  end
end
