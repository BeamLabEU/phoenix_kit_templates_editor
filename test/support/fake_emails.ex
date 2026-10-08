defmodule PhoenixKitTemplatesEditor.Test.FakeProvider do
  @moduledoc false
  # Core's email provider seam (`config :phoenix_kit, :email_provider`) with
  # the database templates of the Emails module played by the application
  # environment: `put_db_templates/1` (a map of name to template).

  def put_db_templates(templates) do
    previous = Application.get_env(:phoenix_kit, :email_provider)
    Application.put_env(:phoenix_kit, :email_provider, __MODULE__)
    Application.put_env(:phoenix_kit_templates_editor, :fake_db_templates, templates)

    ExUnit.Callbacks.on_exit(fn ->
      Application.delete_env(:phoenix_kit_templates_editor, :fake_db_templates)

      if previous,
        do: Application.put_env(:phoenix_kit, :email_provider, previous),
        else: Application.delete_env(:phoenix_kit, :email_provider)
    end)
  end

  def get_active_template_by_name(name),
    do: Map.get(Application.get_env(:phoenix_kit_templates_editor, :fake_db_templates, %{}), name)

  def render_template(template, _variables, locale) do
    %{
      subject: template.subject["en"],
      html_body: template.html_body[locale] || template.html_body["en"],
      text_body: template.text_body["en"]
    }
  end

  def render_template(template, variables), do: render_template(template, variables, "en")
  def track_usage(_template), do: :ok
  def intercept_before_send(email, _opts), do: email
  def handle_after_send(_email, _result), do: :ok
  def get_source_module(_template), do: nil
end

defmodule PhoenixKitTemplatesEditor.Test.FakeTemplateExport do
  @moduledoc false
  # `PhoenixKit.Modules.Emails.TemplateExport` in miniature: the plan's
  # files, `en` locale-less as the real one writes its fallback locale.
  def default_html_mode, do: :body

  def plan([template], [], opts) do
    out = Keyword.fetch!(opts, :out)
    send(self(), {:export_plan, template.name, opts})

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
