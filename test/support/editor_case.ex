defmodule PhoenixKitTemplatesEditor.EditorCase do
  @moduledoc """
  Test case for the editor component (`PhoenixKitTemplatesEditor.Web.Editor`):
  each test gets a `tmp_dir` as the template root, and the helpers mount the
  editor in `PhoenixKitTemplatesEditor.Test.EditorHost` through
  `live_isolated/3` and drive it the way a browser would.

      use PhoenixKitTemplatesEditor.EditorCase, async: true
  """

  use ExUnit.CaseTemplate

  import Phoenix.ConnTest, only: [build_conn: 0]
  import Phoenix.LiveViewTest

  # `live_isolated/3` is a macro: it reads `@endpoint` here, where it expands.
  @endpoint PhoenixKitTemplatesEditor.Test.Endpoint

  using do
    quote do
      import ExUnit.CaptureLog
      import Phoenix.LiveViewTest
      import PhoenixKitTemplatesEditor.EditorCase

      alias PhoenixKit.Templates
      alias PhoenixKit.Templates.Overrides
      alias PhoenixKitTemplatesEditor.Test.EditorHost, as: Host

      @endpoint PhoenixKitTemplatesEditor.Test.Endpoint
      @moduletag :tmp_dir
    end
  end

  @doc "Writes `content` to `<root>/<name>/<file>`."
  def put(root, name, file, content) do
    File.mkdir_p!(Path.join(root, name))
    File.write!(Path.join([root, name, file]), content)
  end

  @doc "A few templates: an email under the prefixes, a header, and one outside them."
  def seed(root) do
    put(root, "order_offer", "label.et.txt", "Pakkumiskiri\n")
    put(root, "order_offer", "label.en.txt", "Price offer\n")
    put(root, "order_offer", "subject.et.txt", "Pakkumine {{order_number}}\n")
    put(root, "order_offer", "text.et.txt", "Tere!\n\n{{documents_list}}\n")
    put(root, "order_offer", "subject.ru.txt", "Предложение\n")
    put(root, "_header-shop", "html.html", "<p>Shop</p>\n")
    put(root, "secret_other", "text.txt", "not for this editor\n")
  end

  @doc """
  Mounts the editor on `root` with `opts` over the defaults. `opts` may hold
  `:locale`, the page's language, which is not an editor attribute.

  A session cannot carry a function, so an option holding one is handed to
  the host right after the mount, as a host re-render.
  """
  def mount_editor(root, opts \\ %{}) do
    {locale, opts} = Map.pop(opts, :locale)
    {functions, opts} = Map.split_with(opts, fn {_key, value} -> function?(value) end)

    opts =
      Map.merge(
        %{
          root: root,
          editable: true,
          name_prefixes: ["order_", "_header-shop", "_footer-shop", "_layout-shop"],
          locales: ["et", "ru", "en"],
          preview: {PhoenixKitTemplatesEditor.Test.EditorHost, :preview},
          sample_variables: %{"order_number" => "37", "documents_list" => "- offer.pdf"}
        },
        opts
      )

    session = %{"opts" => opts, "test_pid" => self(), "locale" => locale}

    {:ok, view, _html} =
      live_isolated(build_conn(), PhoenixKitTemplatesEditor.Test.EditorHost, session: session)

    if functions != %{} do
      send(view.pid, {:put, functions})
      _ = render(view)
    end

    view
  end

  defp function?(value) when is_function(value), do: true
  defp function?(value) when is_map(value), do: value |> Map.values() |> Enum.any?(&function?/1)
  defp function?(value) when is_list(value), do: Enum.any?(value, &function?/1)
  defp function?(value) when is_tuple(value), do: value |> Tuple.to_list() |> function?()
  defp function?(_value), do: false

  def select(view, name) do
    view |> element("#editor [phx-click=select][phx-value-name=#{name}]") |> render_click()
  end

  def tab(view, locale) do
    view |> element("#editor [phx-click=locale][phx-value-locale='#{locale}']") |> render_click()
  end

  def save(view, parts) do
    view |> form("#editor-parts", parts: parts) |> render_submit()
  end

  def create(view, name, copy_from \\ "") do
    view |> form("#editor-create", create: %{name: name, copy_from: copy_from}) |> render_submit()
  end

  @doc "Presses a conversion button, the browser sending every field as it stands."
  def convert(view, action, parts) do
    view
    |> form("#editor-parts", parts: parts)
    |> put_submitter("#editor-parts button[name=action][value=#{action}]")
    |> render_submit()
  end

  @doc "What a field holds in the page, unescaped."
  def field(view, part) do
    view
    |> element("#editor-parts textarea[name='parts[#{part}]']")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> String.replace_prefix("\n", "")
  end
end
