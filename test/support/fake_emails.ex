defmodule PhoenixKitTemplatesEditor.Test.FakeProvider do
  @moduledoc false
  # The legacy database templates of the Emails module, played by the
  # application environment: `put_db_templates/1` (a map of name to template),
  # served by `FakeTemplateExport.active_template/1`.

  def put_db_templates(templates) do
    Application.put_env(:phoenix_kit_templates_editor, :fake_db_templates, templates)

    ExUnit.Callbacks.on_exit(fn ->
      Application.delete_env(:phoenix_kit_templates_editor, :fake_db_templates)
    end)
  end
end

defmodule PhoenixKitTemplatesEditor.Test.FakeTemplateExport do
  @moduledoc false
  # `PhoenixKit.Modules.Emails.TemplateExport` in miniature: the plan's
  # files, `en` locale-less as the real one writes its fallback locale.
  def default_html_mode, do: :body

  def active_template(name),
    do: Map.get(Application.get_env(:phoenix_kit_templates_editor, :fake_db_templates, %{}), name)

  def plan([template], [], opts) do
    out = Keyword.fetch!(opts, :out)

    if pid = Application.get_env(:phoenix_kit_templates_editor, :export_test_pid),
      do: send(pid, {:export_plan, template.name, opts})

    files =
      for {field, stem, ext} <- [
            {:subject, "subject", "txt"},
            {:text_body, "text", "txt"},
            {:html_body, "html", "html"}
          ],
          {locale, content} <- Map.get(template, field, %{}) do
        suffix = if locale == "en", do: "", else: ".#{locale}"
        {Path.join([out, template.name, "#{stem}#{suffix}.#{ext}"]), content}
      end

    %{files: files}
  end
end
