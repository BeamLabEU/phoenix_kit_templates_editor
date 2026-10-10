defmodule PhoenixKitTemplatesEditor.Integration.TestSendTest do
  # "Send to me" (spec §4.11 П3): to the user asking only, once in 30 s,
  # by the host's callback or by PhoenixKit's mailer, logged.
  use PhoenixKitTemplatesEditor.DataCase, async: false

  import ExUnit.CaptureLog

  alias PhoenixKit.Templates.Overrides
  alias PhoenixKit.Users.Auth.Scope
  alias PhoenixKit.Users.Auth.User
  alias PhoenixKitTemplatesEditor.Config
  alias PhoenixKitTemplatesEditor.TestSend

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    root = Path.join(tmp, "templates")
    File.mkdir_p!(Path.join(root, "shop_offer"))
    File.write!(Path.join([root, "shop_offer", "subject.en.txt"]), "Offer {{order_number}}")
    File.write!(Path.join([root, "shop_offer", "text.en.txt"]), "Hello")
    on_exit(fn -> Overrides.reset_cache([root]) end)

    {:ok, _} = PhoenixKitTemplatesEditor.enable_system()

    user = %User{
      uuid: UUIDv7.generate(),
      email: "me-#{System.unique_integer([:positive])}@example.com"
    }

    scope = %Scope{user: user, cached_permissions: MapSet.new(["settings", "templates_editor"])}

    {:ok, config} =
      Config.load(
        root: root,
        name_prefixes: ["shop_"],
        locales: ["en"],
        sample_variables: %{"order_number" => "37"}
      )

    %{config: config, scope: scope, user: user, root: root}
  end

  defp with_test_mailer(fun) do
    previous = Application.get_env(:phoenix_kit, PhoenixKit.Mailer)
    Application.put_env(:phoenix_kit, PhoenixKit.Mailer, adapter: Swoosh.Adapters.Test)

    try do
      fun.()
    after
      if previous,
        do: Application.put_env(:phoenix_kit, PhoenixKit.Mailer, previous),
        else: Application.delete_env(:phoenix_kit, PhoenixKit.Mailer)
    end
  end

  test "the host's callback, with the email, the language and the user", ctx do
    test_pid = self()

    config = %{
      ctx.config
      | test_send: fn name, locale, user ->
          send(test_pid, {:sent, name, locale, user.email})
          :ok
        end
    }

    assert TestSend.deliver(config, ctx.scope, "shop_offer", "en", nil) == {:ok, ctx.user.email}
    assert_received {:sent, "shop_offer", "en", email}
    assert email == ctx.user.email
  end

  # The host's own way of sending may send elsewhere (a test mode): the
  # notice names where the email went, not where it was meant to.
  test "the address the host's callback says it sent to", ctx do
    config = %{ctx.config | test_send: fn _name, _locale, _user -> {:ok, "test@shop.example"} end}

    assert TestSend.deliver(config, ctx.scope, "shop_offer", "en", nil) ==
             {:ok, "test@shop.example"}
  end

  test "an answer that names no address: the user's", ctx do
    config = %{ctx.config | test_send: fn _name, _locale, _user -> {:ok, %{id: 1}} end}
    assert TestSend.deliver(config, ctx.scope, "shop_offer", "en", nil) == {:ok, ctx.user.email}
  end

  test "once in 30 s per user", ctx do
    config = %{ctx.config | test_send: fn _name, _locale, _user -> :ok end}

    assert {:ok, _} = TestSend.deliver(config, ctx.scope, "shop_offer", "en", nil)
    assert {:error, message} = TestSend.deliver(config, ctx.scope, "shop_offer", "en", nil)
    assert message =~ "wait"
  end

  test "no user, or not allowed to see the tab: nothing is sent", ctx do
    config = %{ctx.config | test_send: fn _name, _locale, _user -> flunk("sent") end}

    assert {:error, _} = TestSend.deliver(config, nil, "shop_offer", "en", nil)

    narrow = %{ctx.scope | cached_permissions: MapSet.new(["settings"])}
    assert {:error, message} = TestSend.deliver(config, narrow, "shop_offer", "en", nil)
    assert message =~ "may not"
  end

  test "a refused attempt is logged too: no user, no access, too soon", ctx do
    config = %{ctx.config | test_send: fn _name, _locale, _user -> :ok end}
    narrow = %{ctx.scope | cached_permissions: MapSet.new(["settings"])}

    Logger.put_module_level(TestSend, :info)
    on_exit(fn -> Logger.delete_module_level(TestSend) end)

    log =
      capture_log(fn ->
        assert {:error, _} = TestSend.deliver(config, nil, "shop_offer", "en", nil)
        assert {:error, _} = TestSend.deliver(config, narrow, "shop_offer", "en", nil)
        assert {:ok, _} = TestSend.deliver(config, ctx.scope, "shop_offer", "en", nil)
        assert {:error, _} = TestSend.deliver(config, ctx.scope, "shop_offer", "en", nil)
      end)

    assert log =~ ~s|test email "shop_offer" (en) to an unknown user: refused: no user|
    assert log =~ ~s|test email "shop_offer" (en) to user #{ctx.user.uuid}: refused: no access|
    assert log =~ ~s|test email "shop_offer" (en) to user #{ctx.user.uuid}: sent|
    assert log =~ ~s|test email "shop_offer" (en) to user #{ctx.user.uuid}: refused: too soon|
  end

  test "a callback's error is told, and logged", ctx do
    config = %{
      ctx.config
      | test_send: fn _name, _locale, _user -> {:error, "test mode is off"} end
    }

    Logger.put_module_level(TestSend, :info)
    on_exit(fn -> Logger.delete_module_level(TestSend) end)

    log =
      capture_log(fn ->
        assert TestSend.deliver(config, ctx.scope, "shop_offer", "en", nil) ==
                 {:error, "test mode is off"}
      end)

    assert log =~
             ~s|test email "shop_offer" (en) to user #{ctx.user.uuid}: failed: "test mode is off"|
  end

  test "a reason with a line break stays on one line of the log", ctx do
    config = %{
      ctx.config
      | test_send: fn _name, _locale, _user -> {:error, "line one\nFORGED log line"} end
    }

    Logger.put_module_level(TestSend, :info)
    on_exit(fn -> Logger.delete_module_level(TestSend) end)

    log = capture_log(fn -> TestSend.deliver(config, ctx.scope, "shop_offer", "en", nil) end)

    assert log =~ ~s|failed: "line one\\nFORGED log line"|
    refute log =~ ~r/^FORGED/m
  end

  test "without a callback, the host's own email through PhoenixKit's mailer", ctx do
    with_test_mailer(fn ->
      assert {:ok, _} = TestSend.deliver(ctx.config, ctx.scope, "shop_offer", "en", nil)
    end)

    assert_received {:email, email}
    assert email.to == [{"", ctx.user.email}]
    assert email.subject == "Offer 37"
    assert email.html_body =~ "Hello"
  end

  # Spec §4.11 П3: the host's callback sends the host's own emails; an email
  # PhoenixKit or a module sends goes through PhoenixKit's mailer, as it is
  # sent for real.
  test "with a callback, a module's email still through PhoenixKit's mailer", ctx do
    config = %{ctx.config | test_send: fn _name, _locale, _user -> flunk("host callback") end}

    entry = %{
      name: "billing_invoice",
      label: "Invoice",
      defaults: fn -> %{subject: "Invoice {{n}}", text: "Pay {{n}}"} end,
      variables: fn -> %{"n" => "INV-1"} end
    }

    with_test_mailer(fn ->
      assert {:ok, _} = TestSend.deliver(config, ctx.scope, "billing_invoice", "en", entry)
    end)

    assert_received {:email, email}
    assert email.to == [{"", ctx.user.email}]
    assert email.subject == "Invoice INV-1"
  end

  test "without a callback, a module's email in its built-in text", ctx do
    entry = %{
      name: "billing_invoice",
      label: "Invoice",
      defaults: fn -> %{subject: "Invoice {{n}}", text: "Pay {{n}}"} end,
      variables: fn -> %{"n" => "INV-1"} end
    }

    with_test_mailer(fn ->
      assert {:ok, _} = TestSend.deliver(ctx.config, ctx.scope, "billing_invoice", "en", entry)
    end)

    assert_received {:email, email}
    assert email.subject == "Invoice INV-1"
    assert email.text_body == "Pay INV-1"
  end
end
