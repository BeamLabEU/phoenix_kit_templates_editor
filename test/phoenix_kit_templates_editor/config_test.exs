defmodule PhoenixKitTemplatesEditor.ConfigTest do
  # Not async: the `root: nil` tests change `config :phoenix_kit, :template_paths`.
  use ExUnit.Case, async: false

  alias PhoenixKitTemplatesEditor.Config

  defmodule Callbacks do
    @moduledoc false
    def preview(_name, _locale), do: {"subject", "<p>html</p>", "text"}
    def sample_variables, do: %{"order_number" => "37"}
    def describe_variables(_name), do: %{}
    def complete?(_name, _locale), do: true
    def sent_by(_name), do: :core
    def test_send(_name, _locale, _scope), do: :ok
  end

  @moduletag :tmp_dir

  defp load(tmp_dir, env), do: Config.load(Keyword.put_new(env, :root, tmp_dir))

  defp errors(tmp_dir, env) do
    assert {:error, messages} = load(tmp_dir, env)
    assert is_list(messages) and messages != []
    Enum.join(messages, "\n")
  end

  describe "defaults" do
    test "everything but the root has a safe default", %{tmp_dir: tmp_dir} do
      assert {:ok, %Config{} = config} = Config.load(root: tmp_dir)

      assert config.root == tmp_dir
      assert config.editable == false
      assert config.name_prefixes == []
      # No database here, so PhoenixKit's Languages reads as switched off:
      # base locale "en", and only it.
      assert config.base_locale == "en"
      assert config.locales == ["en"]
      assert config.layout_group == nil
      assert config.layout_groups == []
      assert config.preview == nil
      assert config.sample_variables == %{}
      assert config.describe_variables == nil
      assert config.complete? == nil
      assert config.sent_by == nil
      assert config.test_send == nil
      assert config.block_placeholders == []
      assert config.raw_variables == []
      assert config.email_fallback == true
      assert config.shared_layout_editable == false
      assert config.overridable == :all
      assert config.catalog == false
      assert config.watch == false
    end

    test "keys this module does not know are ignored (a host's repo config, say)",
         %{tmp_dir: tmp_dir} do
      assert {:ok, %Config{}} =
               load(tmp_dir, ecto_repos: [SomeRepo], some_other_key: :whatever)
    end

    test "load/0 reads the application environment", %{tmp_dir: tmp_dir} do
      previous = Application.get_all_env(:phoenix_kit_templates_editor)
      Application.put_env(:phoenix_kit_templates_editor, :root, tmp_dir)
      Application.put_env(:phoenix_kit_templates_editor, :name_prefixes, ["shop_"])

      on_exit(fn ->
        Application.delete_env(:phoenix_kit_templates_editor, :root)
        Application.delete_env(:phoenix_kit_templates_editor, :name_prefixes)
        for {k, v} <- previous, do: Application.put_env(:phoenix_kit_templates_editor, k, v)
      end)

      assert {:ok, %Config{root: ^tmp_dir, name_prefixes: ["shop_"]}} = Config.load()
    end
  end

  describe "root" do
    test "an explicit root is expanded to an absolute path", %{tmp_dir: tmp_dir} do
      relative = Path.relative_to_cwd(tmp_dir)
      assert {:ok, %Config{root: ^tmp_dir}} = Config.load(root: relative)
    end

    test "nil takes the first of core's override paths", %{tmp_dir: tmp_dir} do
      put_template_paths([tmp_dir, "/nonexistent/second"])
      assert {:ok, %Config{root: ^tmp_dir}} = Config.load(root: nil)
      assert {:ok, %Config{root: ^tmp_dir}} = Config.load([])
    end

    test "nil with no override paths is an error", %{tmp_dir: _tmp_dir} do
      put_template_paths([])
      assert {:error, [message]} = Config.load(root: nil)
      assert message =~ "root"
    end

    test "a directory that does not exist is an error that names no path",
         %{tmp_dir: tmp_dir} do
      missing = Path.join(tmp_dir, "missing")
      assert {:error, [message]} = Config.load(root: missing)
      assert message =~ "root"
      refute message =~ tmp_dir
    end

    test "anything but a string is an error", %{tmp_dir: _tmp_dir} do
      assert {:error, [message]} = Config.load(root: :priv)
      assert message =~ "root"
    end

    defp put_template_paths(paths) do
      previous = Application.fetch_env(:phoenix_kit, :template_paths)
      Application.put_env(:phoenix_kit, :template_paths, paths)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(:phoenix_kit, :template_paths, value)
          :error -> Application.delete_env(:phoenix_kit, :template_paths)
        end
      end)
    end
  end

  describe "editable (strictly true)" do
    test "true allows editing", %{tmp_dir: tmp_dir} do
      assert {:ok, %Config{editable: true}} = load(tmp_dir, editable: true)
    end

    test "false is read-only", %{tmp_dir: tmp_dir} do
      assert {:ok, %Config{editable: false}} = load(tmp_dir, editable: false)
    end

    test "a truthy non-boolean is an error, never editable", %{tmp_dir: tmp_dir} do
      for value <- ["true", 1, :yes, [true]] do
        assert errors(tmp_dir, editable: value) =~ "editable"
      end
    end
  end

  describe "watch" do
    test "follows editable by default", %{tmp_dir: tmp_dir} do
      assert {:ok, %Config{watch: true}} = load(tmp_dir, editable: true)
      assert {:ok, %Config{watch: false}} = load(tmp_dir, editable: false)
    end

    test "an explicit boolean wins", %{tmp_dir: tmp_dir} do
      assert {:ok, %Config{watch: false}} = load(tmp_dir, editable: true, watch: false)
      assert {:ok, %Config{watch: true}} = load(tmp_dir, watch: true)
    end

    test "anything else is an error", %{tmp_dir: tmp_dir} do
      assert errors(tmp_dir, watch: "yes") =~ "watch"
    end
  end

  describe "name_prefixes" do
    test "a list of template-name prefixes", %{tmp_dir: tmp_dir} do
      prefixes = ["andi_order_", "_header-andi", "_footer-andi", "_layout-andi"]
      assert {:ok, %Config{name_prefixes: ^prefixes}} = load(tmp_dir, name_prefixes: prefixes)
    end

    test "duplicates are dropped", %{tmp_dir: tmp_dir} do
      assert {:ok, %Config{name_prefixes: ["a_"]}} = load(tmp_dir, name_prefixes: ["a_", "a_"])
    end

    test "an empty prefix, a non-string, a bad name or a non-list is an error",
         %{tmp_dir: tmp_dir} do
      for value <- [[""], [:shop], ["Shop_"], ["../x"], ["_"], "shop_"] do
        assert errors(tmp_dir, name_prefixes: value) =~ "name_prefixes"
      end
    end
  end

  describe "locales and base_locale" do
    test "base_locale defaults to the first of the given locales", %{tmp_dir: tmp_dir} do
      assert {:ok, %Config{locales: ["et", "ru", "en"], base_locale: "et"}} =
               load(tmp_dir, locales: ~w(et ru en))
    end

    test "an explicit base_locale among the locales", %{tmp_dir: tmp_dir} do
      assert {:ok, %Config{locales: ["en", "et"], base_locale: "et"}} =
               load(tmp_dir, locales: ~w(en et), base_locale: "et")
    end

    test "an explicit base_locale without locales gives that one locale", %{tmp_dir: tmp_dir} do
      assert {:ok, %Config{locales: ["et"], base_locale: "et"}} = load(tmp_dir, base_locale: "et")
    end

    test "a base_locale outside the given locales is an error", %{tmp_dir: tmp_dir} do
      assert errors(tmp_dir, locales: ~w(ru en), base_locale: "et") =~ "base_locale"
    end

    test "duplicate locales are dropped", %{tmp_dir: tmp_dir} do
      assert {:ok, %Config{locales: ["et", "ru"]}} = load(tmp_dir, locales: ~w(et ru et))
    end

    test "an invalid locale, an empty list or a non-list is an error", %{tmp_dir: tmp_dir} do
      for value <- [["e/t"], [""], [:et], [], "et"] do
        assert errors(tmp_dir, locales: value) =~ "locales"
      end
    end

    test "an invalid base_locale is an error", %{tmp_dir: tmp_dir} do
      for value <- ["e/t", "", :et] do
        assert errors(tmp_dir, base_locale: value) =~ "base_locale"
      end
    end
  end

  describe "layout_group and layout_groups" do
    test "layout_groups defaults to the layout_group", %{tmp_dir: tmp_dir} do
      assert {:ok, %Config{layout_group: "andi", layout_groups: ["andi"]}} =
               load(tmp_dir, layout_group: "andi")
    end

    test "explicit layout_groups that cover the layout_group", %{tmp_dir: tmp_dir} do
      assert {:ok, %Config{layout_group: "andi-supplier", layout_groups: ["andi"]}} =
               load(tmp_dir, layout_group: "andi-supplier", layout_groups: ["andi"])
    end

    test "a layout_group outside the layout_groups is an error", %{tmp_dir: tmp_dir} do
      # "andix" is not in the "andi" namespace: only "andi" and "andi-…" are.
      assert errors(tmp_dir, layout_group: "andix", layout_groups: ["andi"]) =~ "layout_group"
    end

    test "an invalid group name is an error", %{tmp_dir: tmp_dir} do
      for value <- ["Andi", "_andi", "andi_x", "", :andi] do
        assert errors(tmp_dir, layout_group: value) =~ "layout_group"
      end

      for value <- [["Andi"], [""], "andi"] do
        assert errors(tmp_dir, layout_groups: value) =~ "layout_groups"
      end
    end
  end

  describe "host callbacks" do
    test "{module, function} of the right arity", %{tmp_dir: tmp_dir} do
      env = [
        preview: {Callbacks, :preview},
        sample_variables: {Callbacks, :sample_variables},
        describe_variables: {Callbacks, :describe_variables},
        complete?: {Callbacks, :complete?},
        sent_by: {Callbacks, :sent_by},
        test_send: {Callbacks, :test_send}
      ]

      assert {:ok, %Config{} = config} = load(tmp_dir, env)
      for {key, value} <- env, do: assert(Map.fetch!(config, key) == value)
    end

    test "functions of the right arity", %{tmp_dir: tmp_dir} do
      preview = fn _name, _locale -> {"s", "h"} end
      variables = fn -> %{} end

      assert {:ok, %Config{preview: ^preview, sample_variables: ^variables}} =
               load(tmp_dir, preview: preview, sample_variables: variables)
    end

    test "sample_variables may be a plain map", %{tmp_dir: tmp_dir} do
      assert {:ok, %Config{sample_variables: %{"a" => "1"}}} =
               load(tmp_dir, sample_variables: %{"a" => "1"})
    end

    test "a wrong arity, a missing function or garbage is an error", %{tmp_dir: tmp_dir} do
      for {key, value} <- [
            preview: {Callbacks, :sample_variables},
            preview: {Callbacks, :no_such_function},
            preview: {NoSuchModule, :preview},
            preview: fn _ -> :ok end,
            preview: "Callbacks.preview",
            sample_variables: [1, 2],
            describe_variables: {Callbacks, :preview},
            complete?: fn -> true end,
            sent_by: :core,
            test_send: {Callbacks, :sent_by}
          ] do
        assert errors(tmp_dir, [{key, value}]) =~ Atom.to_string(key)
      end
    end
  end

  describe "variable lists" do
    test "block_placeholders and raw_variables are variable names", %{tmp_dir: tmp_dir} do
      assert {:ok, %Config{block_placeholders: ["documents_list"], raw_variables: ["table"]}} =
               load(tmp_dir, block_placeholders: ["documents_list"], raw_variables: ["table"])
    end

    test "anything but variable names is an error", %{tmp_dir: tmp_dir} do
      for value <- [["{{x}}"], ["1x"], [:x], "x"] do
        assert errors(tmp_dir, block_placeholders: value) =~ "block_placeholders"
        assert errors(tmp_dir, raw_variables: value) =~ "raw_variables"
      end
    end
  end

  describe "booleans" do
    test "accept booleans", %{tmp_dir: tmp_dir} do
      assert {:ok, config} =
               load(tmp_dir,
                 email_fallback: false,
                 shared_layout_editable: true,
                 catalog: true
               )

      assert config.email_fallback == false
      assert config.shared_layout_editable == true
      assert config.catalog == true
    end

    test "anything else is an error", %{tmp_dir: tmp_dir} do
      for key <- [:email_fallback, :shared_layout_editable, :catalog] do
        assert errors(tmp_dir, [{key, "true"}]) =~ Atom.to_string(key)
      end
    end
  end

  describe "overridable" do
    test ":all or a list of template names", %{tmp_dir: tmp_dir} do
      assert {:ok, %Config{overridable: :all}} = load(tmp_dir, overridable: :all)

      assert {:ok, %Config{overridable: ["invoice_sent"]}} =
               load(tmp_dir, overridable: ["invoice_sent"])

      assert {:ok, %Config{overridable: []}} = load(tmp_dir, overridable: [])
    end

    test "anything else is an error", %{tmp_dir: tmp_dir} do
      for value <- [true, "all", ["Bad Name"], [:x]] do
        assert errors(tmp_dir, overridable: value) =~ "overridable"
      end
    end
  end

  test "every problem is reported, not just the first", %{tmp_dir: tmp_dir} do
    assert {:error, messages} = load(tmp_dir, editable: "yes", catalog: 1, locales: "et")
    assert length(messages) == 3
  end
end
