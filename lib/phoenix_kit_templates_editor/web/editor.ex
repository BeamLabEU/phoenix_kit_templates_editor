defmodule PhoenixKitTemplatesEditor.Web.Editor do
  @moduledoc """
  A `Phoenix.LiveComponent` for editing a host's override files in place.

  Moved here from `phoenix_kit_templates` 0.2.4 (`PhoenixKit.Templates.Editor`),
  where it was plain English; here every string goes through the module's
  Gettext backend (`PhoenixKitTemplatesEditor.Gettext`, en/et/ru) in the
  language of the page. The markup is HEEx with daisyUI class names; the
  host's Tailwind finds them through the module's `css_sources/0`.

      <.live_component
        module={PhoenixKitTemplatesEditor.Web.Editor}
        id="email-templates"
        root={MyApp.EmailTemplates.root()}
        editable={true}
        name_prefixes={["order_", "_header-shop", "_footer-shop"]}
        locales={["et", "ru", "en"]}
        preview={{MyApp.EmailPreview, :preview}}
        sample_variables={%{"order_number" => "37"}}
        after_write={{MyApp.EmailTemplates, :after_write}}
        convert={%{to_text: {MyApp.EmailTemplates, :to_text}}}
      />

  Everything is read and written through `PhoenixKit.Templates.Overrides`
  on the one `root`, so the renderer's cache is reset for that root after
  every change — pass the same root string the host renders with.

  ## Attributes

    * `:root` (required) — the host's template directory. Anything but a
      string shows an error and nothing can be written. Keep it fixed for
      the life of the page: the open form's notion of what the user left
      alone belongs to the root it was opened from.
    * `:editable` — `true` to allow saving, creating and deleting; anything
      else shows the files read-only. Default `false`. Checked again by every
      event, not only by what is rendered.
    * `:name_prefixes` — which templates this editor sees **and** may write
      or delete: names starting with one of these strings. Checked on every
      select, save, create, copy and delete. Anything but a list counts as
      `[]`, and entries that are not non-empty strings are dropped. Default
      `[]`, which shows nothing. A prefix shaped like a layout part
      (`_header-shop`) is a namespace, not a string prefix: it allows that
      part of layout `shop` and `shop-…`, not `_header-shopx`; a plain
      prefix never allows a layout part. Whatever the prefixes, the shared
      `_header`/`_footer`/`_layout` are refused unless
      `:shared_layout_editable` is `true`, and so is every name in
      `:reserved_names` (`PhoenixKitTemplatesEditor.Names`).
    * `:layout_group` — the layout of an email without `layout.txt`: listed
      first, marked default, and the *default* choice of an email's layout.
      Default `nil`.
    * `:layout_groups` — layout namespaces: every part of `g` and `g-…`
      may be shown, created and written. Default `[]`.
    * `:shared_layout_editable` — `true` to allow the shared
      `_header`/`_footer`/`_layout`, which core's own emails use too.
      Default `false`.
    * `:reserved_names` — names never shown or created. Default `:catalog`:
      the emails core and every other module send
      (`PhoenixKitTemplatesEditor.Names.reserved_names/0`), asked on each
      update.
    * `:locales` — the language tabs, in order; anything but a list of
      non-empty strings is cleaned the way `:name_prefixes` is. A last tab, *Fallback*, edits
      the locale-less files (`text.txt`), used for any language without its
      own file.
    * `:preview` — `{module, function}` or a 2-arity function called as
      `preview(name, locale)` (`locale` is `nil` on the fallback tab, and
      `name` may be a shared part such as `_header-x`). It returns
      `{subject, html}` or `{subject, html, text}` — each a string or `nil`
      — or `{:error, reason}`. With a text version the preview has two
      tabs, *HTML* and *Text*, and a template opens on HTML (on Text when
      its HTML is `nil`); the text is shown as plain text. The HTML is
      shown in an `<iframe sandbox srcdoc>` without `allow-scripts`, so
      nothing in an edited template runs in the admin page; a
      `{:safe, iodata}` is escaped like a string, never trusted.
      Any other result, an exception, throw or exit is shown as an error
      rather than crashing the page, and the last three are logged. It is
      called on selecting a template or tab, after a save or copy, and when
      the host re-renders with a new callback, new variables or changed
      files — not for a template with no files yet. It runs in a task with
      a deadline (`:preview_timeout`), and not at all while the template,
      its layout's chrome (or, for a layout part, any email) has a link
      among its files (`PhoenixKitTemplatesEditor.Files.check_template/2`):
      the library's lookup a host reads with follows links. *Send to me* is
      checked the same way. No callback, no preview pane.
    * `:sample_variables` — the variables of the host's own emails, as a
      map of name to a sample value: listed in an email's variables panel,
      and any placeholder in the current template that is not among them is
      flagged.
    * `:layout_variables` — the variables of headers, footers and layouts
      with sample values. Default: core's, with this site's values
      (`PhoenixKitTemplatesEditor.Variables.layout_variables/1`).
    * `:raw_variables` — variables the host lets a template write with three
      braces (`{{{x}}}`, not escaped), besides a page layout's `content`,
      `header` and `footer`. Default `[]`.
    * `:describe_variables` — `{module, function}` or a 1-arity function,
      `describe_variables(name)` → `%{variable => description}`, shown in
      the panel. A failure is logged and describes nothing.
    * `:module_emails` — the catalogue entries of the emails core and other
      modules send (`PhoenixKit.Email.Catalog`); their samples are an
      email's variables. Default `[]`.
    * `:sent_by` — `{module, function}` or a 1-arity function,
      `sent_by(name)` → `:core` or `:host`. Default: `:core` for an email of
      `:module_emails` or `:reserved_names`, `:host` otherwise.
    * `:overridable` — which of those emails (and parts of a module's own
      layout group) may be given a file here: `:all` — every one but core's
      sign-in emails (`PhoenixKitTemplatesEditor.Names.auth_emails/0`) — or a
      list of names. Default `[]`: none.
    * `:test_send` — a 2-arity function, `test_send(name, locale)` →
      `{:ok, address}` or `{:error, message}`: the *Send to me* button on an
      email (read only too). The host checks who asks and how often
      (`PhoenixKitTemplatesEditor.TestSend`). Default `nil`: no button.
    * `:after_write` — `{module, function}` or a 1-arity function, called
      with the list of paths created by a save or a copy (a new template
      directory first, then files) — for example to change their owner.
      This package never does. The files are written before it is called;
      if it raises, throws or exits, that is shown as an error after the
      save's own result and logged with its stacktrace.
    * `:after_change` — `{module, function}` or a 1-arity function, called
      with the template's name after any change on disk: a save that wrote
      or deleted files, a copy (the new name) or a deleted template — for
      example to refresh what the host shows about the files. Not called
      when nothing changed. Reported and logged like `:after_write`.
    * `:convert` — the host's converters, a map with either or both keys,
      each `{module, function}` or a function. Each adds a button to the
      form; without them, and read-only, there are none.
      * `to_text: callback`, called as `to_text(:markdown, markdown)` or
        `to_text(:html, html)` — the *Fill text from content* button: the
        form's Markdown if it is not blank, else its HTML, made into plain
        text and put in the Text field.
      * `markdown_to_html: callback`, called as `markdown_to_html(markdown)`
        — the *Markdown → HTML* button: the form's Markdown rendered into
        the HTML field.

      A converter returns a string or `{:error, reason}`; anything else, an
      exception, throw or exit is an error, reported like the other
      callbacks, and the form is left as it was. It gets what is in the
      form, saved or not, with placeholders as typed, and should give them
      back as they are — `{{name}}` is for the message to fill in later:
      not substituted, and in a link target (`[Pay]({{url}})`) neither
      percent-encoded nor dropped. A Markdown renderer called with no
      variables may do either to a link target, so protect placeholders
      through it (the README's note on `markdown`). Nothing is written:
      the result waits in the form, the user's other unsaved fields as
      they were, until the user saves it.
    * `:authorize` — `{module, function}` or a 1-arity function, asked on
      the server before every change, as `authorize(action)` with `:save`,
      `:convert`, `:create`, `:delete` (the delete button and its
      confirmation each ask) or `:reload` (*Reload*, which drops the
      library's cache: a writer's action, once in 5 s). `:ok` allows it; anything else — an error, a
      callback that cannot be called, an exception, throw or exit (logged)
      — refuses it: nothing is written and a notice says so. Asked only when
      `:editable` is `true`, which is checked first. Default `nil`: editable
      is all it takes. A host passes its permission check here (for
      example `fn _action -> MyApp.authorize(scope, :write) end`), so a
      permission taken away while the page is open counts at once.
    * `:max_templates`, `:max_root_bytes` — the most templates the root may
      hold, and the most bytes its files may take: a save,
      copy or new file past either is refused. Default `nil`: no limit.
    * `:preview_timeout` — how long `:preview` may take, in ms, before it
      is shown as too slow. Default `5_000`.
    * `:journal` — `{module, function}` or a 1-arity function, called with
      an event map after every change on disk — `%{action: :file_saved,
      template:, part:, locale:, before:, after:}` and the like
      (`PhoenixKitTemplatesEditor.Journal` lists them) — for an activity
      log. A failure is logged; the change stands. Default `nil`.
    * `:base_locale` — the language an email must be complete in to be
      sent (a host's send window leaves out the rest). Default: the first
      of `:locales`; none, no check.
    * `:complete?` — `{module, function}` or a 2-arity function, called as
      `complete?(name, base_locale)` for every email (a name without a
      leading `_`) on each listing; `false` flags the email in the list:
      it will not be offered for sending. Anything else flags nothing, and
      an exception, throw or exit is logged. Default `nil`: complete is a
      subject and a body part (HTML, Markdown or text) in `base_locale`
      itself — the locale-less fallback does not count — none of them blank.
    * `:email_fallback` — `false` for a host that sends an email only in
      its own languages, never from its locale-less files: an email has no
      Fallback tab then. Locale-less parts an email still has are shown on
      a Fallback tab marked "not used", read-only, with a button to delete
      them (after a confirmation; `layout.txt` and a host's own files stay).
      Headers, footers and layouts (a leading `_`) keep their Fallback tab,
      which is used. Default `true`.

  ## What it does

    * Lists the visible templates, captioned with their `label` part: the
      emails, then the layouts (`PhoenixKitTemplatesEditor.Layouts`) — the
      default first, each with its header, footer and page layout, its own
      (opened in the editor) or inherited (the shared part, or core's), and
      the emails using it — then any other name starting with `_`.
    * Creates a layout as a copy of one with parts of its own (every part
      directory, `Overrides.copy_template/3`), and deletes one no email
      uses — the emails using it are named instead — after a confirmation
      that asks again. `:create` and `:delete` for `authorize`.
    * Gives an open email (on disk) a *Layout* field: the default, or one of
      the layouts; it writes `layout.txt` or deletes it for the default
      (`:save` for `authorize`), and the preview is drawn again at once.
    * Edits the `label`, `subject`, `text`, `markdown` and `html` parts per
      language tab. Saving writes the parts that changed; a part saved empty
      has its file deleted, so the message falls back to the next file in
      line — and a template left with no files loses its directory, staying
      open as an unsaved one. Line breaks are stored as `\\n`. A save that
      is partly refused (one part too large, say) names the parts it saved
      and the ones it did not, and what was typed into those stays in the
      form to be fixed and saved again. Each tab is saved on its own:
      switching to another tab or template, or a reconnect, drops unsaved
      changes.
    * A part is written only when the user changed it from what the form
      was given (on opening the template or tab, or after a save): a part
      left alone is never written back over another session's change made
      meanwhile. An edited part whose file is no longer what the form was
      given (a sha256 taken then: changed, created or deleted on disk since)
      is not written either: the save is refused, the file as it is now is
      shown, and the form keeps what the user typed.
      *Reload* drops the cache and reads the list and the open part again.
      A part filled by a converter counts as edited.
    * The variables panel lists the open part's variables by the kind of
      template (`PhoenixKitTemplatesEditor.Variables`): an email's, or the
      layout's for a header, footer or page layout — with a sample and the
      host's description. A click puts one at the cursor of the field last
      typed in (the module's JS hook, `js_sources/0`); without the hook, at
      the end of the body, in the form only.
    * A save is checked first: a subject one line of at most 998 bytes,
      `{{{x}}}` only for the HTML variables (refused otherwise), a variable
      of the other kind of template (`{{site_url}}` in an email's body)
      saved only after "Save anyway"; an unknown one is saved with a
      warning.
    * The form's buttons all submit it, Save first (the form's default
      button), and a submit that names no button saves. A converter's
      button is told apart by the `action` it submits, which LiveView's
      client sends along since 1.0 — this package's minimum.
    * The host's callbacks (`preview`, `after_write`, `after_change`, the
      converters) run in the LiveView's process and block the page while
      they run: keep them fast.
    * Creates a template empty (it exists on disk once its first part is
      saved) or as a copy of a listed one — every file in its directory,
      including any of the host's own beside the parts
      (`Overrides.copy_template/3`) and its `layout.txt`. The host's own
      files are listed in the form, ticked, once the source is chosen; one
      left unticked is removed from the copy.
    * A file that is not UTF-8 is shown as such, read-only, and never
      written over: fix it on disk.
    * Deletes a template, after a confirmation.
    * Lists *Module emails* (`:module_emails`): read only — the built-in text
      by language, and where each part comes from — until one has a file;
      where `:overridable` allows, a button writes one from the built-in
      text or from the Emails module's active database template
      (`PhoenixKitTemplatesEditor.Overriding`), and from then on it is
      edited like any template. A module's own layout group (`layout:` of
      its entries) gets its parts the same way. The sign-in emails carry a
      warning wherever they are shown.
    * For an email core sends, says where each part comes from
      (`PhoenixKitTemplatesEditor.Sources`) — a red notice when a database
      template wins over the files; for one the host sends, that the files
      are what it uses.

  A reason a host's callback gives (a preview's or a converter's
  `{:error, reason}`) is shown in the host's own words, untranslated.
  """
  use Phoenix.LiveComponent
  use Gettext, backend: PhoenixKitTemplatesEditor.Gettext

  require Logger

  alias PhoenixKit.Email.Layout
  alias PhoenixKit.Templates
  alias PhoenixKit.Templates.Overrides
  alias PhoenixKit.Utils.RecipientLocale
  alias PhoenixKitTemplatesEditor.Bounded
  alias PhoenixKitTemplatesEditor.Files
  alias PhoenixKitTemplatesEditor.Layouts
  alias PhoenixKitTemplatesEditor.Names
  alias PhoenixKitTemplatesEditor.Overriding
  alias PhoenixKitTemplatesEditor.Preview
  alias PhoenixKitTemplatesEditor.Sources
  alias PhoenixKitTemplatesEditor.Variables

  @parts [:label, :subject, :text, :markdown, :html]

  @part_rows %{label: 1, subject: 2, text: 10, markdown: 6, html: 10}

  @part_extensions %{label: "txt", subject: "txt", text: "txt", markdown: "md", html: "html"}

  # RFC 5322's limit for one line of a message header.
  @max_subject_bytes 998

  # The form's `action` values for the host's converters, and their arity.
  @conversions %{"to_text" => :to_text, "md_to_html" => :markdown_to_html}
  @converter_arity %{to_text: 2, markdown_to_html: 1}

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       editable: false,
       name_prefixes: [],
       locales: [],
       preview: nil,
       sample_variables: %{},
       after_write: nil,
       after_change: nil,
       convert: nil,
       authorize: nil,
       preview_image_origins: [],
       base_locale: nil,
       complete?: nil,
       base_language: nil,
       layout_group: nil,
       layout_groups: [],
       shared_layout_editable: false,
       reserved_names: :catalog,
       rules: %{prefixes: [], layout_groups: [], shared_layout_editable: false, reserved: []},
       templates: [],
       layouts: [],
       confirm_layout_delete: nil,
       create_name: "",
       create_from: nil,
       create_extras: [],
       selected: nil,
       draft?: false,
       locale: nil,
       contents: %{},
       baseline: %{},
       # The form's unsaved values, drawn instead of the files' until the
       # template, tab or files change (`load_contents/1`), and a counter
       # bumped by every conversion: it is rendered on every field, so a
       # conversion's reply redraws them all — the browser then replaces
       # what was retyped in a field it does not have focused.
       form_values: %{},
       form_rev: 0,
       confirm_delete?: false,
       email_fallback: true,
       confirm_fallback_delete?: false,
       preview_result: nil,
       preview_tab: :html,
       missing: [],
       notice: nil,
       raw_variables: [],
       describe_variables: nil,
       layout_variables: nil,
       layout_values: nil,
       sent_by: nil,
       module_emails: [],
       overridable: [],
       journal: nil,
       test_send: nil,
       # The root's limits: `nil` — none.
       max_templates: nil,
       max_root_bytes: nil,
       # How long the host's preview may take, in ms.
       preview_timeout: 5_000,
       # When this page last read everything again (`System.monotonic_time/1`, ms).
       reloaded_at: nil,
       # Where each part of the open email comes from, when core sends it
       # (`Sources.of/4`), and the names with a directory in the root.
       sources: nil,
       disk_names: MapSet.new(),
       # An email of `module_emails` shown without being a template here: no
       # file yet, or one this editor may not touch.
       module_selected: nil,
       module_locale: nil,
       module_view: nil,
       # The variables of the open part (`Variables.context/2`), made when
       # the form is given it.
       var_context: nil,
       # A save waiting for "save anyway": a variable of the other kind of
       # template (`Variables.check/3`).
       confirm_variables: nil,
       # Each part's file as the form was given it (sha256, or `:none`), and
       # the parts a save found changed on disk since.
       hashes: %{},
       conflict: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    previous_files = files_of(socket, socket.assigns.selected)
    socket = socket |> assign(assigns) |> sanitize_options() |> assign_layout_values()

    socket =
      if editable?(socket.assigns), do: socket, else: no_confirmations(socket)

    socket = socket |> load_templates() |> settle_draft() |> keep_selection()
    {:ok, refresh_preview(socket, previous_files)}
  end

  @impl true
  # The open template or tab clicked again keeps the form (unsaved values
  # included) and only clears what is transient: a notice, a pending delete.
  def handle_event("select", %{"name" => name}, %{assigns: %{selected: name}} = socket),
    do: {:noreply, clear_transient(socket)}

  def handle_event("select", %{"name" => name}, socket) do
    if visible?(socket, name) do
      {:noreply, socket |> assign(notice: nil, draft?: false) |> select(name)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("locale", %{"locale" => locale}, socket) do
    locale = if locale == "", do: nil, else: locale

    cond do
      socket.assigns.selected && locale == socket.assigns.locale ->
        {:noreply, clear_transient(socket)}

      socket.assigns.selected && locale in tabs(socket.assigns, socket.assigns.selected) ->
        {:noreply,
         socket
         |> assign(locale: locale, notice: nil, confirm_fallback_delete?: false)
         |> load_contents()
         |> preview()}

      true ->
        {:noreply, socket}
    end
  end

  # A conversion button submits the form like Save, with its own `action`.
  def handle_event("save", %{"action" => action, "parts" => parts}, socket)
      when is_map_key(@conversions, action) and is_map(parts) do
    conversion = Map.fetch!(@conversions, action)

    {:noreply,
     permitted(socket, :convert, fn socket ->
       if form_writable?(socket) and converter(socket.assigns, conversion) != nil,
         do: convert(socket, conversion, parts),
         else: socket
     end)}
  end

  # A variable button of the panel without the module's JS hook: the
  # variable goes at the end of the body, in the form only.
  def handle_event("save", %{"action" => "insert:" <> variable, "parts" => parts}, socket)
      when is_map(parts) do
    if form_writable?(socket),
      do: {:noreply, insert_variable(socket, variable, parts)},
      else: {:noreply, socket}
  end

  # A submit that names no button, or names Save, saves.
  def handle_event("save", %{"parts" => parts} = params, socket) when is_map(parts) do
    if Map.get(params, "action", "save") == "save" do
      {:noreply,
       permitted(socket, :save, fn socket ->
         if form_writable?(socket), do: save(socket, parts), else: socket
       end)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("confirm_save", _params, socket) do
    {:noreply,
     permitted(socket, :save, fn socket ->
       case socket.assigns.confirm_variables do
         %{parts: parts} ->
           if form_writable?(socket),
             do: socket |> assign(confirm_variables: nil) |> save(parts, confirmed: true),
             else: assign(socket, confirm_variables: nil)

         nil ->
           socket
       end
     end)}
  end

  def handle_event("cancel_save", _params, socket),
    do: {:noreply, assign(socket, confirm_variables: nil)}

  # The files again from disk, the cache dropped: after a hand edit, a git
  # pull or another user's save. Dropping the cache costs the whole VM a
  # collection per entry, so it is a writer's action, and
  # once in a few seconds; where nothing is written, nothing changes on disk
  # but by a deploy (or the watcher reads it).
  def handle_event("reload", _params, socket),
    do: {:noreply, permitted(socket, :reload, &reload_throttled/1)}

  # An email core or a module sends: opened in the editor once it is a
  # template here, else shown read only with its built-in text.
  def handle_event("select_module", %{"name" => name}, socket) when is_binary(name) do
    cond do
      module_email(socket.assigns, name) == nil -> {:noreply, socket}
      exists?(socket, name) -> {:noreply, socket |> assign(notice: nil) |> select(name)}
      true -> {:noreply, socket |> assign(notice: nil) |> open_module(name)}
    end
  end

  def handle_event("module_locale", %{"locale" => locale}, socket) do
    if socket.assigns.module_selected && locale in socket.assigns.locales,
      do: {:noreply, socket |> assign(module_locale: locale) |> load_module_view()},
      else: {:noreply, socket}
  end

  def handle_event("override_default", %{"name" => name}, socket) when is_binary(name),
    do: {:noreply, permitted(socket, :create, &override(&1, name, :default))}

  def handle_event("override_db", %{"name" => name}, socket) when is_binary(name),
    do: {:noreply, permitted(socket, :create, &override(&1, name, :db))}

  def handle_event("override_layout", %{"name" => name}, socket) when is_binary(name),
    do: {:noreply, permitted(socket, :create, &override(&1, name, :layout))}

  # Not a change: works read only too. The host's callback checks who asks.
  def handle_event("test_send", _params, socket), do: {:noreply, test_send(socket)}

  def handle_event("preview_tab", %{"tab" => "html"}, socket),
    do: {:noreply, assign(socket, preview_tab: :html)}

  def handle_event("preview_tab", %{"tab" => "text"}, socket),
    do: {:noreply, assign(socket, preview_tab: :text)}

  def handle_event("create", %{"create" => %{"name" => name} = params}, socket)
      when is_binary(name) do
    case Map.get(params, "copy_from", "") do
      copy_from when is_binary(copy_from) ->
        name = String.trim(name)
        on_disk = socket.assigns.disk_names

        {:noreply,
         socket
         |> assign_create_form(params)
         |> permitted(:create, &create(&1, name, copy_from, params))
         |> clear_create_form(name, on_disk)}

      _malformed ->
        {:noreply, socket}
    end
  end

  def handle_event("delete", _params, socket) do
    {:noreply,
     socket
     |> assign(notice: nil)
     |> permitted(:delete, fn socket ->
       assign(socket, confirm_delete?: writable?(socket, socket.assigns.selected))
     end)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, confirm_delete?: false)}
  end

  def handle_event("confirm_delete", _params, socket) do
    {:noreply,
     permitted(socket, :delete, fn socket ->
       if socket.assigns.confirm_delete? and writable?(socket, socket.assigns.selected),
         do: delete(socket),
         else: assign(socket, confirm_delete?: false)
     end)}
  end

  def handle_event("delete_fallback", _params, socket) do
    {:noreply,
     socket
     |> assign(notice: nil)
     |> permitted(:delete, fn socket ->
       assign(socket, confirm_fallback_delete?: fallback_deletable?(socket))
     end)}
  end

  def handle_event("cancel_delete_fallback", _params, socket) do
    {:noreply, assign(socket, confirm_fallback_delete?: false)}
  end

  def handle_event("confirm_delete_fallback", _params, socket) do
    {:noreply,
     permitted(socket, :delete, fn socket ->
       if socket.assigns.confirm_fallback_delete? and fallback_deletable?(socket),
         do: delete_fallback(socket),
         else: assign(socket, confirm_fallback_delete?: false)
     end)}
  end

  # The create form's name and source are kept here and drawn from here: a
  # browser redraws a field it does not have focused from the page, so one
  # left to the browser is emptied by any redraw of the form (the list of
  # the host's files coming in, say).
  def handle_event("create_change", %{"create" => %{} = params}, socket),
    do: {:noreply, assign_create_form(socket, params)}

  def handle_event("set_layout", %{"email_layout" => %{"group" => group}}, socket)
      when is_binary(group) do
    {:noreply,
     permitted(socket, :save, fn socket ->
       if email_layout_writable?(socket), do: set_layout(socket, group), else: socket
     end)}
  end

  def handle_event(
        "create_layout",
        %{"layout_create" => %{"name" => name, "copy_from" => from}},
        socket
      )
      when is_binary(name) and is_binary(from) do
    {:noreply, permitted(socket, :create, &create_layout(&1, String.trim(name), from))}
  end

  def handle_event("delete_layout", %{"group" => group}, socket) when is_binary(group) do
    {:noreply,
     socket
     |> assign(notice: nil, confirm_layout_delete: nil)
     |> permitted(:delete, &request_layout_delete(&1, group))}
  end

  def handle_event("cancel_delete_layout", _params, socket),
    do: {:noreply, assign(socket, confirm_layout_delete: nil)}

  def handle_event("confirm_delete_layout", _params, socket) do
    {:noreply,
     permitted(socket, :delete, fn socket ->
       case socket.assigns.confirm_layout_delete do
         nil -> socket
         group -> delete_layout(socket, group)
       end
     end)}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  ## Actions

  # Every change is checked here, on the server, whatever the page showed:
  # the editor must be editable (the host's config, strictly `true`) and the
  # host's `authorize` must answer `:ok` for this user, now — a permission
  # taken away while the page is open counts at once. A refusal changes
  # nothing and says so.
  defp permitted(socket, action, fun) do
    case permission(socket, action) do
      :ok -> fun.(socket)
      {:error, message} -> socket |> no_confirmations() |> notice(:error, message)
    end
  end

  defp permission(socket, action) do
    cond do
      not editable?(socket.assigns) ->
        {:error, gettext("These templates are read-only here: nothing was changed.")}

      authorized?(socket.assigns.authorize, action) ->
        :ok

      true ->
        {:error, gettext("You are not allowed to change templates: nothing was changed.")}
    end
  end

  # No callback: editable is all it takes. One that cannot be called, raises
  # or answers anything but `:ok` refuses.
  defp authorized?(nil, _action), do: true

  defp authorized?(callback, action) do
    callable?(callback, 1) and
      safely({"authorize", callback, [action]}, fn -> call(callback, [action]) end) == :ok
  end

  defp select(socket, name) do
    socket
    |> assign(selected: name, module_selected: nil, module_view: nil)
    |> no_confirmations()
    |> assign(locale: initial_locale(socket, name))
    |> load_contents()
    |> preview()
    |> open_preview()
  end

  # A template opens on its HTML preview, or on its text version when it
  # has no HTML; switching language tabs keeps the preview tab.
  defp open_preview(socket) do
    tab =
      case socket.assigns.preview_result do
        {:ok, _subject, nil, text} when is_binary(text) -> :text
        _other -> :html
      end

    assign(socket, preview_tab: tab)
  end

  # The parts the user changed, checked before anything is written: the
  # file still as the form was given it, a subject one line, three braces
  # only for HTML variables, no variable of the other kind of template
  # unless confirmed.
  defp save(socket, params, opts \\ []) do
    %{contents: contents, baseline: baseline} = socket.assigns

    changes =
      Enum.flat_map(@parts, fn part ->
        with value when is_binary(value) <- params[Atom.to_string(part)],
             value = normalize_newlines(value),
             # Left as the form was given it: another session's change to
             # this part since then must not be written back over.
             false <- value == Map.get(baseline, part, ""),
             {:ok, change} <- change(Map.get(contents, part), value) do
          [{part, change}]
        else
          _unchanged -> []
        end
      end)

    findings = check_variables(socket.assigns.var_context, changes)

    cond do
      (conflicts = conflicts(socket, changes)) != [] ->
        socket |> assign(conflict: conflicts, notice: nil) |> keep_form(params)

      message = subject_refusal(changes) ->
        socket |> notice(:error, message) |> keep_form(params)

      message = directory_refusal(socket, socket.assigns.selected) ->
        socket |> notice(:error, not_saved(message)) |> keep_form(params)

      message = limit_refusal(socket, new_templates(socket), written_bytes(changes)) ->
        socket |> notice(:error, not_saved(message)) |> keep_form(params)

      findings.raw != [] ->
        socket |> notice(:error, raw_refusal(socket, findings.raw)) |> keep_form(params)

      findings.forbidden != [] and opts[:confirmed] != true ->
        socket
        |> assign(confirm_variables: %{parts: params, names: findings.forbidden}, notice: nil)
        |> keep_form(params)

      true ->
        write_changes(socket, changes, params, findings.unknown)
    end
  end

  defp write_changes(socket, changes, params, unknown) do
    %{root: root, selected: name, locale: locale, preview_result: previous_preview} =
      socket.assigns

    results =
      for {part, change} <- changes, do: {part, apply_change(change, root, name, part, locale)}

    paths = for {_part, {:ok, paths}} <- results, path <- paths, do: path
    saved = for {part, {:ok, _paths}} <- results, do: part
    errors = for {part, {:error, reason}} <- results, do: {part, reason}

    for {part, change} <- changes, part in saved do
      journal(socket, saved_event(change, name, part, locale, socket.assigns.contents[part]))
    end

    notified =
      socket
      |> notify_written(paths)
      |> then_notify_changed(socket, if(saved == [], do: nil, else: name))

    notice =
      save_notice(saved, errors)
      |> with_notified(notified)
      |> with_notified(unknown_warning(saved, unknown))

    socket
    |> assign(notice: notice, conflict: nil, confirm_variables: nil)
    |> load_templates()
    |> redraft()
    |> load_contents()
    |> assign(form_values: refused_values(errors, params))
    |> preview()
    |> open_first_preview(previous_preview)
  end

  # A draft's first save gives it its first preview, opened like a
  # selected template's.
  defp open_first_preview(socket, :unsaved), do: open_preview(socket)
  defp open_first_preview(socket, _previous), do: socket

  defp saved_event({:write, value}, name, part, locale, file) do
    %{
      action: :file_saved,
      template: name,
      part: part,
      locale: locale,
      before: file_content(file),
      after: value
    }
  end

  defp saved_event(:delete, name, part, locale, file) do
    %{
      action: :file_deleted,
      template: name,
      part: part,
      locale: locale,
      before: file_content(file),
      after: nil
    }
  end

  defp file_content(%{content: content}), do: content
  defp file_content(_none), do: nil

  # A refused save leaves the form as the user sent it.
  defp keep_form(socket, params) do
    values =
      for part <- @parts,
          value = params[Atom.to_string(part)],
          is_binary(value) and String.valid?(value),
          into: %{},
          do: {part, normalize_newlines(value)}

    assign(socket, form_values: values)
  end

  # The parts about to change whose file is no longer what the form was
  # given: `{part, content on disk now}` (`nil` — no file, `:unreadable`).
  defp conflicts(socket, changes) do
    %{root: root, selected: name, locale: locale, hashes: hashes} = socket.assigns

    for {part, _change} <- changes,
        path = part_path(root, name, part, locale),
        {fingerprint, content} = fingerprint(root, path),
        fingerprint != Map.get(hashes, part, :none),
        do: {part, content}
  end

  # `{fingerprint, content}` of the file at `path`: its sha256 and text,
  # `:none` when there is no file, or the reason it cannot be read.
  defp fingerprint(root, path) do
    case Files.safe_read(root, path) do
      {:ok, content} ->
        {:crypto.hash(:sha256, content),
         if(String.valid?(content), do: content, else: :unreadable)}

      {:error, :enoent} ->
        {:none, nil}

      {:error, reason} ->
        {{:error, reason}, :unreadable}
    end
  end

  defp fingerprints(%{selected: nil}), do: %{}

  defp fingerprints(%{root: root, selected: name, locale: locale}) when is_binary(root) do
    Map.new(@parts, fn part ->
      {part, root |> fingerprint(part_path(root, name, part, locale)) |> elem(0)}
    end)
  end

  defp fingerprints(_assigns), do: %{}

  # The file `Overrides.write/5` writes for this part.
  defp part_path(root, name, part, locale) do
    file =
      Enum.join(
        [Atom.to_string(part), locale, @part_extensions[part]] |> Enum.reject(&is_nil/1),
        "."
      )

    Path.join([root, name, file])
  end

  # A subject is one line of a message header.
  defp subject_refusal(changes) do
    case List.keyfind(changes, :subject, 0) do
      {:subject, {:write, value}} ->
        subject = String.trim(value)

        if String.contains?(subject, ["\n", "\r"]) or byte_size(subject) > @max_subject_bytes,
          do:
            gettext("Not saved: the subject must be one line of at most %{max} bytes.",
              max: @max_subject_bytes
            )

      _none ->
        nil
    end
  end

  defp check_variables(nil, _changes), do: %{forbidden: [], unknown: [], raw: []}

  defp check_variables(context, changes) do
    found =
      for {part, {:write, value}} <- changes, do: Variables.check(value, part, context)

    for key <- [:forbidden, :unknown, :raw], into: %{} do
      {key, found |> Enum.flat_map(&Map.fetch!(&1, key)) |> Enum.uniq()}
    end
  end

  defp raw_refusal(socket, names) do
    names = Enum.map_join(names, ", ", &"{{{#{&1}}}}")

    case raw_allowed(socket.assigns) do
      [] ->
        gettext(
          "Not saved: %{names} would be put into the message without escaping. Write them with two braces: no variable is written with three here.",
          names: names
        )

      allowed ->
        gettext(
          "Not saved: %{names} would be put into the message without escaping. Write them with two braces; three are only for %{allowed}.",
          names: names,
          allowed: Enum.map_join(allowed, ", ", &"{{{#{&1}}}}")
        )
    end
  end

  defp raw_allowed(%{var_context: %{kind: :layout, raw: raw}}),
    do: raw ++ ~w(content header footer)

  defp raw_allowed(%{var_context: %{raw: raw}}), do: raw
  defp raw_allowed(_assigns), do: []

  defp unknown_warning([], _unknown), do: :ok
  defp unknown_warning(_saved, []), do: :ok

  defp unknown_warning(_saved, unknown) do
    {:warning,
     gettext("%{names} is not a variable of this template: it stays in the message as typed.",
       names: Enum.map_join(unknown, ", ", &"{{#{&1}}}")
     )}
  end

  # Without the JS hook a panel button submits the form: its variable goes
  # at the end of the body — the Markdown, else the HTML when it holds
  # anything, else the text; a header's, footer's or layout's HTML.
  defp insert_variable(socket, variable, params) do
    values =
      for part <- @parts,
          value = params[Atom.to_string(part)],
          is_binary(value),
          into: %{},
          do: {part, normalize_newlines(value)}

    row = Enum.find(panel_rows(socket.assigns), &(&1.name == variable))

    if row && Enum.all?(values, fn {_part, value} -> String.valid?(value) end) do
      target = insert_target(socket.assigns.var_context, values)

      assign(socket,
        form_values: Map.update(values, target, placeholder(row), &(&1 <> placeholder(row))),
        form_rev: socket.assigns.form_rev + 1,
        notice: nil
      )
    else
      socket
    end
  end

  defp insert_target(%{kind: :email}, values),
    do: Enum.find([:markdown, :html], :text, &present?(values[&1]))

  defp insert_target(_context, _values), do: :html

  defp placeholder(%{scope: :html, name: name}), do: "{{{#{name}}}}"
  defp placeholder(%{name: name}), do: "{{#{name}}}"

  defp panel_rows(%{var_context: nil}), do: []
  defp panel_rows(%{var_context: context}), do: Variables.panel(context)

  @reload_interval_ms 5_000

  defp reload_throttled(socket) do
    now = System.monotonic_time(:millisecond)

    case socket.assigns.reloaded_at do
      last when is_integer(last) and now - last < @reload_interval_ms ->
        notice(
          socket,
          :info,
          gettext("Read again a moment ago: wait %{seconds} s.",
            seconds: div(last + @reload_interval_ms - now + 999, 1000)
          )
        )

      _long_ago ->
        socket |> assign(reloaded_at: now) |> reload()
    end
  end

  defp reload(socket) do
    if is_binary(socket.assigns.root), do: Files.reload(socket.assigns.root)

    socket =
      socket
      |> assign(notice: {:info, gettext("Read again from disk.")})
      |> no_confirmations()
      |> load_templates()
      |> settle_draft()
      |> keep_selection()

    if socket.assigns.selected,
      do: socket |> load_contents() |> preview(),
      else: socket
  end

  # A refused part stays in the form as the user sent it: drawn from the
  # file again, a part a conversion filled would be lost. Text that is not
  # UTF-8 cannot be drawn at all.
  defp refused_values(errors, params) do
    for {part, _reason} <- errors,
        value = params[Atom.to_string(part)],
        is_binary(value) and String.valid?(value),
        into: %{},
        do: {part, normalize_newlines(value)}
  end

  # Puts a converted part into the form, not on disk: `form_values` keeps
  # every field as the browser sent it, so the user's other unsaved changes
  # are drawn back as they were, and `baseline` stays as it is, so Save
  # writes the converted part like any part the user edited.
  defp convert(socket, conversion, params) do
    values =
      for part <- @parts,
          value = params[Atom.to_string(part)],
          is_binary(value),
          into: %{},
          do: {part, normalize_newlines(value)}

    target = conversion_target(conversion)

    cond do
      not Enum.all?(values, fn {_part, value} -> String.valid?(value) end) ->
        not_converted(socket, describe(:invalid_content))

      invalid_on_disk?(socket, target) ->
        notice(socket, :error, invalid_on_disk(socket, target))

      true ->
        case conversion_source(socket, conversion, values) do
          nil ->
            notice(socket, :info, nothing_to_convert(conversion))

          {:invalid, part} ->
            notice(socket, :error, invalid_on_disk(socket, part))

          {format, source} ->
            socket
            |> run_converter(conversion, format, source)
            |> converted(socket, values, target, format)
        end
    end
  end

  defp conversion_target(:to_text), do: :text
  defp conversion_target(:markdown_to_html), do: :html

  # Markdown when there is any, else HTML: the content the text is made from.
  defp conversion_sources(:to_text), do: [:markdown, :html]
  defp conversion_sources(:markdown_to_html), do: [:markdown]

  # The first source with content. One that is not UTF-8 on disk has no
  # field, so nothing to tell whether it is blank: it stops the search
  # rather than being passed over as empty.
  defp conversion_source(socket, conversion, values) do
    Enum.find_value(conversion_sources(conversion), fn part ->
      cond do
        invalid_on_disk?(socket, part) -> {:invalid, part}
        present?(values[part]) -> {part, values[part]}
        true -> nil
      end
    end)
  end

  defp invalid_on_disk?(socket, part),
    do: match?(%{invalid: true}, socket.assigns.contents[part])

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp nothing_to_convert(:to_text),
    do: gettext("Nothing to convert: Markdown and HTML are empty.")

  defp nothing_to_convert(:markdown_to_html),
    do: gettext("Nothing to convert: Markdown is empty.")

  defp invalid_on_disk(socket, part) do
    case socket.assigns.contents[part] do
      %{reason: :invalid_content} ->
        gettext("Not converted: %{part} is not valid UTF-8 text on disk; fix it there first.",
          part: part_title(part)
        )

      _unreadable ->
        gettext("Not converted: %{part} cannot be read here.", part: part_title(part))
    end
  end

  defp not_converted(socket, reason),
    do: notice(socket, :error, gettext("Not converted: %{reason}", reason: reason))

  defp run_converter(socket, conversion, format, source) do
    callback = converter(socket.assigns, conversion)
    args = if conversion == :to_text, do: [format, source], else: [source]

    safely({Atom.to_string(conversion), callback, args}, fn ->
      callback |> call(args) |> conversion_result()
    end)
  end

  # The module's own converters' limits are told in words; any other reason
  # is the host's own.
  defp conversion_result({:error, reason}) when reason in [:too_large, :timeout],
    do: {:error, describe(reason)}

  defp conversion_result({:error, reason}), do: {:error, describe_host(reason)}

  defp conversion_result(value) when is_binary(value) do
    if String.valid?(value), do: {:ok, value}, else: {:error, gettext("unexpected result")}
  end

  defp conversion_result(_other), do: {:error, gettext("unexpected result")}

  # `form_rev` changes on every conversion, so the reply touches every field
  # and the browser redraws them from what it was sent. Without it, a
  # conversion coming out as the server already had the form (the user
  # retyped only its target since the last one) sends nothing, and the
  # browser keeps the retyped text.
  defp converted({:ok, value}, socket, values, target, format) do
    socket
    |> assign(
      form_values: Map.put(values, target, normalize_newlines(value)),
      form_rev: socket.assigns.form_rev + 1
    )
    |> notice(
      :info,
      gettext("Filled %{target} from %{source}. It is not saved yet: check it, then Save.",
        target: part_title(target),
        source: part_title(format)
      )
    )
  end

  defp converted({:error, reason}, socket, _values, _target, _format),
    do: not_converted(socket, reason)

  defp save_notice([], []), do: {:info, gettext("No changes.")}
  defp save_notice(_saved, []), do: {:info, gettext("Saved.")}

  defp save_notice([], errors),
    do: {:error, gettext("Not saved: %{errors}", errors: describe_errors(errors))}

  # Some files did change: saying only "Not saved" would hide that.
  defp save_notice(saved, errors) do
    {:error,
     gettext("Saved: %{saved}. Not saved: %{errors}",
       saved: Enum.map_join(saved, ", ", &part_title/1),
       errors: describe_errors(errors)
     )}
  end

  defp change(%{invalid: true}, _value), do: :none
  defp change(nil, ""), do: :none
  defp change(_file, ""), do: {:ok, :delete}
  defp change(nil, value), do: {:ok, {:write, value}}

  defp change(%{content: content}, value) do
    if normalize_newlines(content) == value, do: :none, else: {:ok, {:write, value}}
  end

  defp apply_change(:delete, root, name, part, locale) do
    case Overrides.delete(root, name, part, locale) do
      :ok -> {:ok, []}
      error -> error
    end
  end

  defp apply_change({:write, value}, root, name, part, locale) do
    Overrides.write(root, name, part, locale, value)
  end

  defp create(socket, name, copy_from, params) do
    cond do
      not Overrides.valid_name?(name) ->
        notice(
          socket,
          :error,
          gettext(
            "“%{name}” is not a valid template name: use lowercase letters, digits, " <>
              "“_” and “-”, with at most one leading “_”.",
            name: name
          )
        )

      # An email core or a module sends gets a file only from its own
      # buttons, never by this form.
      refusal = name_refusal(socket, name, overridable: []) ->
        notice(socket, :error, refusal)

      File.exists?(Path.join(socket.assigns.root, name)) ->
        notice(socket, :error, gettext("“%{name}” already exists.", name: name))

      copy_from == "" ->
        socket |> assign(notice: nil, draft?: true) |> select(name)

      # Only a template on disk can be copied; a draft has no directory.
      # Every file of it is checked first: the library's copy reads them by
      # following links.
      exists?(socket, copy_from) ->
        checked_copy(socket, copy_from, name, params)

      true ->
        notice(socket, :error, gettext("There is no “%{name}” to copy.", name: copy_from))
    end
  end

  # Why a write into template `name` is refused: its directory is a link,
  # which a write would follow out of the root — `nil` when it is a real
  # one, or none yet.
  defp directory_refusal(%{assigns: %{root: root}}, name) do
    case Files.check_template_dir(root, name) do
      :ok ->
        nil

      {:error, {_reason, path}} ->
        gettext("%{file} is a link or outside the template directory: nothing is written there.",
          file: Files.relative(root, path)
        )
    end
  end

  # Why the files of template `name` (or of `names`) may not be read by the
  # library: a link among them — `nil` when there is none.
  defp template_refusal(socket, name), do: check_refusal(socket, [name])

  defp check_refusal(%{assigns: %{root: root}}, _names) when not is_binary(root), do: nil

  defp check_refusal(%{assigns: %{root: root}}, names) do
    case Preview.check_templates(root, names) do
      :ok -> nil
      {:error, message} -> message
    end
  end

  # Why the root may not take `new_templates` more templates and `bytes`
  # more bytes — `nil` within the host's limits.
  defp limit_refusal(%{assigns: %{max_templates: nil, max_root_bytes: nil}}, _new, _bytes),
    do: nil

  defp limit_refusal(%{assigns: %{root: root} = assigns}, new_templates, bytes) do
    usage = Files.usage(root)
    max_templates = assigns.max_templates
    max_bytes = assigns.max_root_bytes

    cond do
      is_integer(max_templates) and new_templates > 0 and
          usage.templates + new_templates > max_templates ->
        gettext(
          "the templates directory already holds %{count} templates, as many as it may here.",
          count: usage.templates
        )

      is_integer(max_bytes) and bytes > 0 and usage.bytes + bytes > max_bytes ->
        gettext("the templates directory may not grow past %{size} KiB here.",
          size: div(max_bytes, 1024)
        )

      true ->
        nil
    end
  end

  # A save of a draft makes its directory.
  defp new_templates(%{assigns: %{root: root, selected: name}}),
    do: if(File.dir?(Path.join(root, name)), do: 0, else: 1)

  defp written_bytes(changes),
    do: Enum.reduce(changes, 0, fn {_part, change}, sum -> sum + change_bytes(change) end)

  defp change_bytes({:write, value}), do: byte_size(value)
  defp change_bytes(:delete), do: 0

  defp template_bytes(%{assigns: %{root: root}}, name), do: Files.template_bytes(root, name)

  defp not_saved(message), do: gettext("Not saved: %{errors}", errors: message)

  defp checked_copy(socket, from, name, params) do
    case template_refusal(socket, from) || limit_refusal(socket, 1, template_bytes(socket, from)) do
      nil -> copy(socket, from, name, skipped_files(socket, from, params))
      message -> notice(socket, :error, gettext("Not copied: %{reason}", reason: message))
    end
  end

  # Why `rules` refuse a name, in words; `nil` when they allow it.
  defp name_refusal(socket, name, opts) do
    rules = Map.merge(socket.assigns.rules, Map.new(opts))

    case Names.check(name, rules) do
      :ok ->
        nil

      {:error, :reserved} ->
        gettext("“%{name}” is not created here: core or a module sends this email.", name: name)

      {:error, :shared} ->
        gettext(
          "“%{name}” is shared by every email, core’s own (sign-in, password reset) among them: not editable here.",
          name: name
        )

      {:error, :namespace} ->
        gettext("“%{name}” is not in this editor’s layouts (%{layouts}).",
          name: name,
          layouts: describe_namespaces(socket)
        )

      {:error, :prefix} ->
        gettext("“%{name}” is not allowed here: names must start with %{prefixes}.",
          name: name,
          prefixes: Enum.map_join(plain_prefixes(socket), ", ", &"“#{&1}”")
        )
    end
  end

  defp plain_prefixes(socket), do: Enum.reject(socket.assigns.name_prefixes, &Names.chrome/1)

  defp describe_namespaces(socket) do
    case Names.namespaces(socket.assigns.rules) do
      [] -> gettext("none")
      namespaces -> Enum.map_join(namespaces, ", ", &"“#{&1}”, “#{&1}-…”")
    end
  end

  # The host's own files the user left unticked in the create form — only
  # when the form's list was made for this very source.
  defp skipped_files(socket, from, %{"keep_for" => from, "keep" => keep}) when is_list(keep),
    do: Files.host_files(socket.assigns.root, from) -- Enum.filter(keep, &is_binary/1)

  defp skipped_files(_socket, _from, _params), do: []

  # The whole directory, not just the parts this editor shows: a host's own
  # files beside them (who a message is for, say) belong to the template,
  # but for those the user chose to leave out.
  defp copy(socket, from, name, skipped) do
    case Overrides.copy_template(socket.assigns.root, from, name) do
      {:ok, paths} ->
        {paths, left} = leave_out(socket.assigns.root, name, paths, skipped)
        journal(socket, %{action: :template_copied, template: name, from: from})

        notified =
          socket |> notify_written(paths) |> then_notify_changed(socket, name)

        notice =
          {:info, gettext("Created “%{name}” as a copy of “%{from}”.", name: name, from: from)}
          |> with_notified(left)

        socket
        |> assign(notice: with_notified(notice, notified), draft?: false)
        |> load_templates()
        |> select(name)

      {:error, reason} ->
        notice(socket, :error, gettext("Not copied: %{reason}", reason: describe(reason)))
    end
  end

  # Removes the files a copy was told to leave out from the new template.
  defp leave_out(_root, _name, paths, []), do: {paths, :ok}

  defp leave_out(root, name, paths, skipped) do
    results = for file <- skipped, do: {file, File.rm(Path.join([root, name, file]))}
    removed = for {file, :ok} <- results, do: Path.join([root, name, file])

    left =
      case for({file, {:error, _reason}} <- results, do: file) do
        [] ->
          :ok

        files ->
          {:warning,
           gettext("%{files} could not be left out of the copy.", files: Enum.join(files, ", "))}
      end

    {paths -- removed, left}
  end

  defp delete(socket) do
    %{root: root, selected: name} = socket.assigns

    result = if socket.assigns.draft?, do: :ok, else: Overrides.delete_template(root, name)

    notice =
      case result do
        :ok ->
          changed = if socket.assigns.draft?, do: nil, else: name
          if changed, do: journal(socket, %{action: :template_deleted, template: name})

          with_notified(
            {:info, gettext("Deleted “%{name}”.", name: name)},
            notify_changed(socket, changed)
          )

        {:error, reason} ->
          {:error, gettext("Not deleted: %{reason}", reason: describe(reason))}
      end

    socket = socket |> assign(notice: notice) |> no_confirmations() |> load_templates()
    if result == :ok, do: deselect(socket), else: keep_selection(socket)
  end

  # The open email's locale-less parts, which nothing reads: the files go,
  # the rest of the template (its languages, `layout.txt`, a host's own
  # files) stays.
  defp delete_fallback(socket) do
    %{root: root, selected: name} = socket.assigns

    results =
      for %{part: part} <- fallback_files(socket.assigns, name),
          do: {part, Overrides.delete(root, name, part, nil)}

    deleted = for {part, :ok} <- results, do: part
    errors = for {part, {:error, reason}} <- results, do: {part, reason}

    notice =
      case errors do
        [] ->
          {:info, gettext("Deleted the files without a language of “%{name}”.", name: name)}

        errors ->
          {:error, gettext("Not deleted: %{errors}", errors: describe_errors(errors))}
      end

    if deleted != [],
      do: journal(socket, %{action: :fallback_deleted, template: name, parts: deleted})

    notified = notify_changed(socket, if(deleted == [], do: nil, else: name))

    socket
    |> assign(notice: with_notified(notice, notified), confirm_fallback_delete?: false)
    |> load_templates()
    |> keep_selection()
    |> preview_selected()
  end

  ## Module emails

  defp open_module(socket, name) do
    socket
    |> deselect()
    |> assign(
      module_selected: name,
      module_locale: socket.assigns.base_language || hd_or_nil(socket.assigns.locales)
    )
    |> load_module_view()
  end

  defp hd_or_nil([first | _]), do: first
  defp hd_or_nil(_none), do: nil

  # What the read-only view of a module's email shows: its built-in text
  # in the tab's language, where each part comes from, and what may be done.
  defp load_module_view(%{assigns: %{module_selected: nil}} = socket),
    do: assign(socket, module_view: nil)

  defp load_module_view(socket) do
    %{module_selected: name, module_locale: locale, root: root} = assigns = socket.assigns
    entry = module_email(assigns, name)

    context =
      Variables.context(name,
        email: email_variables(assigns, name, locale),
        layout: assigns.layout_values || %{},
        raw: assigns.raw_variables,
        sent_by: :core,
        descriptions: descriptions(assigns, name)
      )

    view = %{
      entry: entry,
      defaults: Overriding.defaults(entry, locale),
      sources:
        if(is_binary(root) and is_binary(locale), do: Sources.of(root, name, locale, entry)),
      file?: MapSet.member?(assigns.disk_names, name),
      overridable?: Names.check(name, assigns.rules) == :ok,
      db?: Overriding.db_template?(name),
      variables: Variables.panel(context)
    }

    assign(socket, module_view: view)
  end

  # Files for an email core or a module sends, only where the rules
  # let it be overridden and it has none yet.
  defp override(socket, name, source) do
    socket = load_templates(socket)
    %{root: root, rules: rules} = assigns = socket.assigns

    cond do
      not override_source?(assigns, name, source) ->
        socket

      Names.check(name, rules) != :ok ->
        notice(socket, :error, gettext("“%{name}” may not be overridden here.", name: name))

      File.exists?(Path.join(root, name)) ->
        notice(socket, :error, gettext("“%{name}” already exists.", name: name))

      message = limit_refusal(socket, 1, 0) ->
        notice(socket, :error, gettext("Not created: %{reason}", reason: message))

      true ->
        result =
          case source do
            :default ->
              Overriding.from_defaults(root, module_email(assigns, name), assigns.locales)

            :db ->
              Overriding.from_db(root, name)

            :layout ->
              Overriding.from_layout_default(root, name)
          end

        overridden(socket, name, source, result)
    end
  end

  defp override_source?(assigns, name, :layout), do: name in module_layout_names(assigns)
  defp override_source?(assigns, name, _source), do: module_email(assigns, name) != nil

  defp overridden(socket, name, source, {:ok, paths}) do
    action = if source == :db, do: :created_from_db, else: :created_from_default
    journal(socket, %{action: action, template: name})
    notified = socket |> notify_written(paths) |> then_notify_changed(socket, name)

    message =
      case source do
        :db ->
          gettext("Created “%{name}” from the Emails module's database template.", name: name)

        _built_in ->
          gettext("Created “%{name}” from its built-in text.", name: name)
      end

    socket
    |> assign(notice: with_notified({:info, message}, notified))
    |> load_templates()
    |> select(name)
  end

  defp overridden(socket, _name, _source, {:error, reason}),
    do: notice(socket, :error, gettext("Not created: %{reason}", reason: describe(reason)))

  # The parts of the layouts module emails name (`layout: "<g>"`) that the
  # host's own layout namespaces do not cover.
  defp module_layout_names(assigns) do
    for group <- module_groups(assigns), kind <- Names.kinds(), do: Names.part_name(kind, group)
  end

  defp module_groups(assigns) do
    assigns.module_emails
    |> Names.module_groups()
    |> Enum.reject(&Names.group_allowed?(&1, assigns.rules))
  end

  # "Send to me": the host's callback, with the open email and language.
  defp test_send(socket) do
    %{test_send: callback} = assigns = socket.assigns

    with {name, locale} <- test_send_target(assigns),
         nil <- check_refusal(socket, preview_names(assigns, name)),
         answer when answer != :none <- ask(callback, "test_send", [name, locale]) do
      test_sent(answer, socket)
    else
      message when is_binary(message) -> test_sent({:error, message}, socket)
      _none -> socket
    end
  end

  defp test_sent({:ok, address}, socket) when is_binary(address),
    do: notice(socket, :info, gettext("Sent to %{address}.", address: address))

  defp test_sent({:error, message}, socket) when is_binary(message),
    do: notice(socket, :error, gettext("Not sent: %{reason}", reason: message))

  defp test_sent(other, socket),
    do: notice(socket, :error, gettext("Not sent: %{reason}", reason: describe_host(other)))

  # The email to send: the open one (an email on disk, not a layout part),
  # or the module email shown; in the tab's language, else the base one.
  defp test_send_target(%{module_selected: name, module_locale: locale})
       when is_binary(name),
       do: {name, locale}

  defp test_send_target(%{selected: "_" <> _}), do: nil
  defp test_send_target(%{selected: nil}), do: nil
  defp test_send_target(%{draft?: true}), do: nil

  defp test_send_target(%{selected: name, locale: locale, base_language: base}),
    do: {name, locale || base}

  ## Layouts

  # The open email's layout: its `layout.txt` written with the group, or
  # deleted for the default. Only a layout the rules allow; the preview is
  # drawn in it at once.
  defp set_layout(socket, group) do
    %{root: root, selected: name} = socket.assigns
    template = Enum.find(socket.assigns.templates, &(&1.name == name))
    file? = Enum.any?(template.files, &(&1.part == :layout))

    result =
      cond do
        message = directory_refusal(socket, name) ->
          {:error, message}

        group == "" and not file? ->
          :unchanged

        group == "" ->
          with :ok <- Overrides.delete(root, name, :layout, nil), do: {:ok, []}

        not layout_allowed?(socket, group) ->
          {:error, :not_a_layout}

        group == template.layout ->
          :unchanged

        true ->
          Overrides.write(root, name, :layout, nil, group)
      end

    socket |> layout_set(result, name, group) |> load_templates() |> keep_selection() |> preview()
  end

  defp layout_set(socket, :unchanged, _name, _group),
    do: notice(socket, :info, gettext("No changes."))

  defp layout_set(socket, {:error, :not_a_layout}, _name, group) do
    notice(
      socket,
      :error,
      gettext("“%{group}” is not one of this editor’s layouts: nothing was changed.",
        group: group
      )
    )
  end

  defp layout_set(socket, {:error, reason}, _name, _group),
    do: notice(socket, :error, gettext("Not saved: %{errors}", errors: describe(reason)))

  defp layout_set(socket, {:ok, paths}, name, group) do
    journal(socket, %{action: :layout_set, template: name, layout: if(group != "", do: group)})
    notified = socket |> notify_written(paths) |> then_notify_changed(socket, name)

    message =
      if group == "",
        do: gettext("“%{name}” now has the default layout.", name: name),
        else: gettext("“%{name}” now has the layout “%{group}”.", name: name, group: group)

    assign(socket, notice: with_notified({:info, message}, notified))
  end

  defp layout_allowed?(socket, group),
    do: Layout.valid_group?(group) and Names.group_allowed?(group, socket.assigns.rules)

  # A new layout: every part of its own an existing layout has, copied
  # under the new name.
  defp create_layout(socket, group, from) do
    socket = load_templates(socket)
    kinds = own_kinds(socket.assigns, from)

    cond do
      not Layout.valid_group?(group) ->
        notice(
          socket,
          :error,
          gettext(
            "“%{name}” is not a valid layout name: use lowercase letters, digits and “-”.",
            name: group
          )
        )

      not layout_allowed?(socket, group) or
          not Enum.all?(kinds, &Names.part_allowed?(&1, group, socket.assigns.rules)) ->
        notice(
          socket,
          :error,
          gettext("“%{name}” is not in this editor’s layouts (%{layouts}).",
            name: group,
            layouts: describe_namespaces(socket)
          )
        )

      layout_exists?(socket, group) ->
        notice(socket, :error, gettext("“%{name}” already exists.", name: group))

      kinds == [] ->
        notice(socket, :error, gettext("There is no layout “%{name}” to copy.", name: from))

      message =
          check_refusal(socket, Enum.map(kinds, &Names.part_name(&1, from))) ||
            limit_refusal(socket, length(kinds), 0) ->
        notice(socket, :error, gettext("Not copied: %{reason}", reason: message))

      true ->
        copy_layout(socket, from, group, kinds)
    end
  end

  defp copy_layout(socket, from, group, kinds) do
    case Layouts.copy(socket.assigns.root, from, group, kinds) do
      {:ok, created} ->
        journal(socket, %{action: :layout_created, layout: group, from: from})
        written = notify_written(socket, Enum.flat_map(created, &elem(&1, 1)))
        changed = for {name, _paths} <- created, do: notify_changed(socket, name)

        notice =
          {:info,
           gettext("Created the layout “%{name}” as a copy of “%{from}”.",
             name: group,
             from: from
           )}

        socket
        |> assign(notice: with_notified(notice, first_failure([written | changed])))
        |> load_templates()

      {:error, reason} ->
        notice(socket, :error, gettext("Not copied: %{reason}", reason: describe(reason)))
    end
  end

  defp layout_exists?(socket, group) do
    Enum.any?(socket.assigns.layouts, &(&1.group == group)) or
      Enum.any?(Names.kinds(), fn kind ->
        File.exists?(Path.join(socket.assigns.root, Names.part_name(kind, group)))
      end)
  end

  # The parts of `group` that are its own and this editor shows.
  defp own_kinds(assigns, group) do
    shown = MapSet.new(assigns.templates, & &1.name)

    case Enum.find(assigns.layouts, &(&1.group == group)) do
      %{parts: parts} ->
        for %{source: :own} = part <- parts, MapSet.member?(shown, part.name), do: part.kind

      nil ->
        []
    end
  end

  # Asks for a confirmation — unless an email uses the layout: then it says
  # which, and nothing more happens.
  defp request_layout_delete(socket, group) do
    socket = load_templates(socket)

    case layout_deletable(socket, group) do
      {:ok, _kinds} -> assign(socket, confirm_layout_delete: group)
      {:in_use, emails} -> notice(socket, :error, layout_in_use(socket, group, emails))
      :error -> socket
    end
  end

  # Asked again on the confirmation: an email may have taken the layout
  # since.
  defp delete_layout(socket, group) do
    socket = socket |> assign(confirm_layout_delete: nil) |> load_templates()

    case layout_deletable(socket, group) do
      {:ok, kinds} ->
        {result, deleted} =
          case Layouts.delete(socket.assigns.root, group, kinds) do
            {:ok, deleted} ->
              {{:info, gettext("Deleted the layout “%{name}”.", name: group)}, deleted}

            {:error, reason, deleted} ->
              {{:error, gettext("Not deleted: %{reason}", reason: describe(reason))}, deleted}
          end

        if deleted != [], do: journal(socket, %{action: :layout_deleted, layout: group})
        changed = for name <- deleted, do: notify_changed(socket, name)

        socket
        |> assign(notice: with_notified(result, first_failure(changed)))
        |> load_templates()
        |> keep_selection()

      {:in_use, emails} ->
        notice(socket, :error, layout_in_use(socket, group, emails))

      :error ->
        socket
    end
  end

  defp layout_deletable(socket, group) do
    %{layouts: layouts} = socket.assigns

    case {Enum.find(layouts, &(&1.group == group)), own_kinds(socket.assigns, group)} do
      {nil, _kinds} -> :error
      {_layout, []} -> :error
      {%{emails: []}, kinds} -> {:ok, kinds}
      {%{emails: emails}, _kinds} -> {:in_use, emails}
    end
  end

  defp layout_in_use(socket, group, emails) do
    gettext("“%{group}” is the layout of %{emails}: give them another layout first.",
      group: group,
      emails: describe_emails(socket.assigns, emails)
    )
  end

  # Emails by name, but those this editor does not show only counted.
  defp describe_emails(assigns, emails) do
    shown = MapSet.new(assigns.templates, & &1.name)
    {shown, hidden} = Enum.split_with(emails, &MapSet.member?(shown, &1))

    case {shown, length(hidden)} do
      {shown, 0} ->
        Enum.join(shown, ", ")

      {[], count} ->
        gettext("%{count} not shown here", count: count)

      {shown, count} ->
        gettext("%{emails} and %{count} more not shown here",
          emails: Enum.join(shown, ", "),
          count: count
        )
    end
  end

  defp first_failure(results), do: Enum.find(results, :ok, &(&1 != :ok))

  # The open email (not a draft, not a layout part) whose layout.txt may be
  # written.
  defp email_layout_writable?(socket) do
    %{selected: name, draft?: draft?} = socket.assigns

    is_binary(name) and not String.starts_with?(name, "_") and not draft? and
      exists?(socket, name) and writable?(socket, name)
  end

  ## State

  defp load_templates(socket) do
    %{root: root, rules: rules, layout_group: default} = socket.assigns
    listing = Overrides.list(root)

    templates =
      for %{name: name, files: files} <- listing,
          allowed?(socket, name) do
        %{
          name: name,
          files: files,
          caption: caption(socket, name, files),
          # Core resolves its emails part by part, falling back to the
          # built-in text: one of them is never incomplete.
          incomplete?:
            not module_name?(socket.assigns, name) and incomplete?(socket.assigns, name, files),
          layout:
            if(String.starts_with?(name, "_"), do: nil, else: Layouts.email_layout(root, files))
        }
      end

    socket
    |> assign(
      templates: templates,
      layouts: Layouts.list(listing, root, rules, default),
      disk_names: MapSet.new(listing, & &1.name)
    )
    |> assign_create_extras()
  end

  # The create form as the user left it; a source that changed lists the
  # host's own files in it to choose from (all taken by default).
  defp assign_create_form(socket, params) do
    socket =
      case params do
        %{"name" => name} when is_binary(name) -> assign(socket, create_name: name)
        _other -> socket
      end

    case params do
      %{"copy_from" => from} when is_binary(from) and from != socket.assigns.create_from ->
        socket |> assign(create_from: from) |> assign_create_extras()

      _same ->
        socket
    end
  end

  # A template made empties the form; a refused one leaves it as given, to
  # correct. Made: open, and either no error said (an empty one) or on disk
  # now and not before (a copy, whatever the host's callbacks said after).
  defp clear_create_form(socket, name, on_disk) do
    if created?(socket.assigns, name, on_disk),
      do: assign(socket, create_name: "", create_from: nil, create_extras: []),
      else: socket
  end

  defp created?(%{selected: name, notice: {:error, _message}} = assigns, name, on_disk),
    do: MapSet.member?(assigns.disk_names, name) and not MapSet.member?(on_disk, name)

  defp created?(%{selected: name}, name, _on_disk), do: true
  defp created?(_assigns, _name, _on_disk), do: false

  # The host's own files in the create form's source, to tick.
  defp assign_create_extras(socket) do
    %{root: root, create_from: from} = socket.assigns

    extras =
      if is_binary(root) and is_binary(from) and exists?(socket, from),
        do: Files.host_files(root, from),
        else: []

    assign(socket, create_extras: extras)
  end

  # An email (no leading "_") not complete in the base language: a host's
  # send window leaves it out, so the list says so. The host's `complete?`
  # decides when it gives one; only its `false` flags — a failure is logged
  # and flags nothing.
  defp incomplete?(%{base_language: nil}, _name, _files), do: false
  defp incomplete?(_assigns, "_" <> _shared, _files), do: false

  defp incomplete?(%{complete?: nil, base_language: locale, root: root}, _name, files),
    do: not complete_files?(root, files, locale)

  defp incomplete?(%{complete?: callback, base_language: locale}, name, _files) do
    callable?(callback, 2) and
      safely({"complete?", callback, [name, locale]}, fn -> call(callback, [name, locale]) end) ==
        false
  end

  # A subject and a body part (HTML, Markdown or text) in `locale` itself —
  # the locale-less fallback does not count — none of them blank.
  defp complete_files?(root, files, locale) do
    present =
      for %{locale: ^locale, part: part, path: path} <- files, filled?(root, path), do: part

    :subject in present and Enum.any?([:html, :markdown, :text], &(&1 in present))
  end

  defp filled?(root, path) do
    case Files.safe_read(root, path) do
      {:ok, content} -> content |> String.replace_invalid() |> String.trim() != ""
      {:error, _reason} -> false
    end
  end

  # A parent re-render, a deletion or a change of prefixes may leave the
  # selection pointing at something this editor can no longer show.
  defp keep_selection(%{assigns: %{selected: nil}} = socket), do: socket

  defp keep_selection(socket) do
    if visible?(socket, socket.assigns.selected) do
      if socket.assigns.locale in tabs(socket.assigns, socket.assigns.selected),
        do: refresh_contents(socket),
        else: socket |> reset_locale() |> load_contents()
    else
      deselect(socket)
    end
  end

  # A parent re-render calls the host's preview again only when something it
  # depends on changed: the callback or variables, the tab, or the files —
  # another session may have saved them.
  defp refresh_preview(%{assigns: %{selected: nil}} = socket, _previous_files), do: socket

  defp refresh_preview(socket, previous_files) do
    if files_of(socket, socket.assigns.selected) != previous_files or
         Enum.any?(
           [:root, :preview, :sample_variables, :locale, :contents],
           &changed?(socket, &1)
         ) do
      preview(socket)
    else
      socket
    end
  end

  # A draft that now exists on disk — saved here, or by another session — is
  # an ordinary template again, so deleting it deletes its directory.
  defp settle_draft(socket) do
    assign(socket,
      draft?: socket.assigns.draft? and not exists?(socket, socket.assigns.selected)
    )
  end

  # After a save the template is a draft exactly when it has no directory:
  # a first save makes it an ordinary template, and emptying its last file
  # (`Overrides.delete/4` removes the directory with it) makes it a draft
  # again, still selected and still writable.
  defp redraft(socket) do
    assign(socket, draft?: not exists?(socket, socket.assigns.selected))
  end

  defp reset_locale(socket),
    do: assign(socket, locale: initial_locale(socket, socket.assigns.selected))

  defp clear_transient(socket), do: socket |> assign(notice: nil) |> no_confirmations()

  defp no_confirmations(socket),
    do:
      assign(socket,
        confirm_delete?: false,
        confirm_fallback_delete?: false,
        confirm_layout_delete: nil,
        confirm_variables: nil
      )

  defp deselect(socket) do
    assign(socket,
      selected: nil,
      draft?: false,
      contents: %{},
      baseline: %{},
      form_values: %{},
      preview_result: nil,
      missing: [],
      confirm_delete?: false,
      confirm_fallback_delete?: false,
      confirm_variables: nil,
      var_context: nil,
      hashes: %{},
      conflict: nil
    )
  end

  # What the form is drawn from. `baseline` is what the form was last given
  # for this template and tab (on select, a tab switch or a save); a parent
  # re-render refreshes `contents` from disk but keeps it, so `save/2` can
  # tell a part the user left alone from one they edited. `form_values`,
  # the fields as a conversion left them, go too: the form is drawn from the
  # files again (but for the parts a save refused: `save/2`).
  defp load_contents(socket) do
    socket = refresh_contents(socket)

    socket
    |> assign(
      baseline: baseline(socket.assigns.contents),
      form_values: %{},
      hashes: fingerprints(socket.assigns),
      conflict: nil,
      confirm_variables: nil
    )
    |> assign_var_context()
    |> assign_sources()
  end

  # Where each part of the open email comes from — only for one core
  # sends, in a language (core resolves a recipient's language, never the
  # fallback tab itself).
  defp assign_sources(%{assigns: %{var_context: %{kind: :email, sent_by: :core}}} = socket) do
    %{root: root, selected: name, locale: locale, draft?: draft?} = socket.assigns

    sources =
      if is_binary(root) and is_binary(locale) and not draft?,
        do: Sources.of(root, name, locale, module_email(socket.assigns, name))

    assign(socket, sources: sources)
  end

  defp assign_sources(socket), do: assign(socket, sources: nil)

  defp assign_var_context(%{assigns: %{selected: nil}} = socket),
    do: assign(socket, var_context: nil)

  defp assign_var_context(socket) do
    %{selected: name, locale: locale} = assigns = socket.assigns

    context =
      Variables.context(name,
        email: email_variables(assigns, name, locale),
        layout: assigns.layout_values || %{},
        raw: assigns.raw_variables,
        sent_by: sent_by(assigns, name),
        descriptions: descriptions(assigns, name)
      )

    assign(socket, var_context: context)
  end

  # An email core or a module sends has its catalogue entry's samples,
  # evaluated in the tab's language as core's preview does; the host's own,
  # the host's sample variables.
  defp email_variables(assigns, name, locale) do
    case module_email(assigns, name) do
      %{variables: variables} -> module_variables(variables, locale || assigns.base_language)
      _host -> assigns.sample_variables
    end
  end

  defp module_variables(variables, locale) do
    case safely({"variables", variables, []}, fn -> evaluate_variables(variables, locale) end) do
      map when is_map(map) -> map
      _failed -> %{}
    end
  end

  defp evaluate_variables(fun, locale) when is_function(fun, 0),
    do: RecipientLocale.in_locale(locale, fun)

  defp evaluate_variables(map, _locale), do: map

  # A host's 1-arity callback's answer to `args`; `:none` without one, or
  # when it cannot be called. A failure is logged and answers its error.
  defp ask(nil, _role, _args), do: :none

  defp ask(callback, role, args) do
    if callable?(callback, length(args)),
      do: safely({role, callback, args}, fn -> call(callback, args) end),
      else: :none
  end

  defp module_email(assigns, name), do: Enum.find(assigns.module_emails, &(&1.name == name))

  # An email core or a module sends: in the catalogue, or a reserved name.
  defp module_name?(assigns, name),
    do: name in assigns.rules.reserved or module_email(assigns, name) != nil

  # Who sends the email: the host's `sent_by` when it gives `:core` or
  # `:host`, else core for an email of the catalogue (`module_emails`), the
  # host for its own.
  defp sent_by(assigns, name) do
    default = if module_name?(assigns, name), do: :core, else: :host

    case ask(assigns.sent_by, "sent_by", [name]) do
      answer when answer in [:core, :host] -> answer
      _other -> default
    end
  end

  defp descriptions(%{describe_variables: callback}, name) do
    case ask(callback, "describe_variables", [name]) do
      %{} = map ->
        for {key, value} <- map, is_binary(value), into: %{}, do: {to_string(key), value}

      _other ->
        %{}
    end
  end

  defp refresh_contents(socket) do
    %{root: root, selected: name, locale: locale} = socket.assigns

    contents =
      for %{part: part, locale: ^locale, path: path, mtime: mtime} <- files_of(socket, name),
          part in @parts,
          file = read_part(root, path, mtime),
          file != nil,
          into: %{},
          do: {part, file}

    socket |> assign(contents: contents) |> load_missing()
  end

  # Every file is read through `Files.safe_read/2`: a link, a file leading
  # out of the root or one larger than a template may be is never read —
  # shown as unavailable, like text that is not UTF-8, and never written
  # over from here.
  defp read_part(root, path, mtime) do
    case Files.safe_read(root, path) do
      {:ok, content} -> file_contents(content, mtime)
      {:error, reason} when reason in [:unsafe_path, :too_large] -> unreadable(reason, mtime)
      {:error, _gone} -> nil
    end
  end

  defp unreadable(reason, mtime), do: %{invalid: true, reason: reason, mtime: mtime}

  defp baseline(contents) do
    for {part, %{content: content}} <- contents,
        into: %{},
        do: {part, normalize_newlines(content)}
  end

  # A file put on disk by hand may not be UTF-8, which the page cannot carry:
  # such a part is shown as broken and is never written over from here.
  defp file_contents(content, mtime) do
    if String.valid?(content),
      do: %{content: content, mtime: mtime},
      else: unreadable(:invalid_content, mtime)
  end

  defp load_missing(socket) do
    %{root: root, selected: name, locale: locale, sample_variables: variables} = socket.assigns

    # A template with no files (a draft) has nothing to check, and looking it
    # up would leave cache entries behind for a name that may never be saved.
    if variables == %{} or files_of(socket, name) == [] do
      assign(socket, missing: [])
    else
      assign(socket, missing: missing_variables(name, variables, locale, root))
    end
  end

  # Only when every file the check would read passes `Files.check/2`: a
  # link or a file out of the root is never read, not even for its
  # placeholders.
  defp missing_variables(name, variables, locale, root) do
    opts = [locale: locale, paths: [root]]

    if Files.check_template(root, name) == :ok and
         sources_safe?(root, Templates.sources(name, %{}, opts)),
       do: unbound(name, variables, opts),
       else: []
  end

  defp sources_safe?(root, sources) do
    Enum.all?(sources, fn
      {_part, {:file, path}} -> match?({:ok, _stat}, Files.check(root, path))
      {_part, _default} -> true
    end)
  end

  defp unbound(name, variables, opts) do
    name
    |> Templates.missing_variables(%{}, variables, opts)
    |> Map.values()
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp preview_selected(%{assigns: %{selected: nil}} = socket), do: socket
  defp preview_selected(socket), do: preview(socket)

  defp preview(%{assigns: %{preview: nil}} = socket), do: assign(socket, preview_result: nil)

  defp preview(socket) do
    %{preview: callback, selected: name, locale: locale} = socket.assigns

    # A template with no files (a draft) has nothing to show, and rendering
    # it would leave cache entries behind for a name that may never be saved.
    result =
      cond do
        files_of(socket, name) == [] ->
          :unsaved

        # The host reads the files by the library's lookup, which follows
        # links: none of them may be one.
        message = check_refusal(socket, preview_names(socket.assigns, name)) ->
          {:error, message}

        true ->
          bounded_preview(callback, name, locale, socket.assigns.preview_timeout)
      end

    assign(socket, preview_result: result)
  end

  # In a task with a deadline, as the module's own preview: a slow template
  # costs the page at most that long.
  defp bounded_preview(callback, name, locale, timeout) do
    safely({"preview", callback, [name, locale]}, fn ->
      callback |> run_bounded([name, locale], timeout) |> bounded_result()
    end)
  end

  defp run_bounded(callback, args, timeout),
    do: Bounded.run(fn -> call(callback, args) end, timeout)

  defp bounded_result({:ok, result}), do: preview_result(result)
  defp bounded_result({:error, :timeout}), do: {:error, describe(:timeout)}

  # The templates a preview of `name` reads: an email and its layout's
  # chrome; a layout part, its group's chrome and the emails it may be
  # shown around.
  defp preview_names(assigns, "_" <> _ = name) do
    group =
      case Names.chrome(name) do
        {_kind, group} -> group
        nil -> assigns.layout_group
      end

    Preview.chrome_names(group) ++
      for(%{name: email} <- assigns.templates, not String.starts_with?(email, "_"), do: email)
  end

  defp preview_names(assigns, name) do
    group =
      case Enum.find(assigns.templates, &(&1.name == name)) do
        %{layout: layout} when is_binary(layout) -> layout
        _none -> assigns.layout_group
      end

    [name | Preview.chrome_names(group)]
  end

  # Only text is trusted into the page: `{:safe, iodata}` is turned back into
  # a string so it is escaped like any other — inside `srcdoc` a raw one
  # would break out of the attribute and the sandbox.
  defp preview_result({:error, reason}), do: {:error, describe_host(reason)}

  # `:none` marks a host that gives no text version (`{subject, html}`):
  # its preview has no Text tab, as before there was one. A host's own
  # `{subject, html, :none}` is an error like any text that is no string.
  defp preview_result({subject, html}), do: preview_texts(subject, html, :none)

  defp preview_result({subject, html, text}) do
    case preview_text(text) do
      {:ok, text} -> preview_texts(subject, html, text)
      :error -> {:error, unexpected_preview()}
    end
  end

  defp preview_result(_other), do: {:error, unexpected_preview()}

  defp preview_texts(subject, html, text) do
    with {:ok, subject} <- preview_text(subject),
         {:ok, html} <- preview_text(html) do
      {:ok, subject, html, text}
    else
      :error -> {:error, unexpected_preview()}
    end
  end

  defp unexpected_preview, do: gettext("unexpected preview result")

  defp preview_text(nil), do: {:ok, nil}

  defp preview_text({:safe, _iodata} = safe),
    do: preview_text(Phoenix.HTML.safe_to_string(safe))

  defp preview_text(text) when is_binary(text) do
    if String.valid?(text), do: {:ok, text}, else: :error
  end

  defp preview_text(_other), do: :error

  # The files are written by now, whatever the host's callback does with them.
  defp notify_written(_socket, []), do: :ok
  defp notify_written(%{assigns: %{after_write: nil}}, _paths), do: :ok

  defp notify_written(socket, paths) do
    callback = socket.assigns.after_write

    safely({"after_write", callback, [paths]}, fn ->
      case call(callback, [paths]) do
        {:warning, message} when is_binary(message) -> {:warning, message}
        _other -> :ok
      end
    end)
    |> tag_failure("after_write")
  end

  defp notify_changed(_socket, nil), do: :ok
  defp notify_changed(%{assigns: %{after_change: nil}}, _name), do: :ok

  defp notify_changed(socket, name) do
    callback = socket.assigns.after_change

    safely({"after_change", callback, [name]}, fn ->
      call(callback, [name])
      :ok
    end)
    |> tag_failure("after_change")
  end

  # What was changed, for the host's activity log; a failing callback is
  # logged and changes nothing about the change.
  defp journal(%{assigns: %{journal: nil}}, _event), do: :ok

  defp journal(socket, event) do
    callback = socket.assigns.journal

    if callable?(callback, 1),
      do: safely({"journal", callback, [event]}, fn -> call(callback, [event]) end)

    :ok
  end

  defp tag_failure(:ok, _role), do: :ok
  defp tag_failure({:warning, _message} = warning, _role), do: warning
  defp tag_failure({:error, reason}, role), do: {:error, {role, reason}}

  # Both callbacks run even when the first fails; the notice reports the
  # first failure, and every failure is logged (`safely/2`).
  defp then_notify_changed(:ok, socket, name), do: notify_changed(socket, name)

  defp then_notify_changed(written_error, socket, name) do
    notify_changed(socket, name)
    written_error
  end

  defp with_notified(notice, :ok), do: notice

  # The files are saved; something the host does after (setting their
  # mode, say) did not quite work out. A warning, not an error.
  defp with_notified({:info, message}, {:warning, warning}),
    do: {:warning, gettext("%{message} But: %{warning}", message: message, warning: warning)}

  defp with_notified({kind, message}, {:warning, warning}),
    do: {kind, gettext("%{message} But: %{warning}", message: message, warning: warning)}

  defp with_notified({_kind, message}, {:error, {role, reason}}),
    do:
      {:error,
       gettext("%{message} But the host's %{role} failed: %{reason}",
         message: message,
         role: role,
         reason: reason
       )}

  # A host callback that raises, throws or exits is reported, not a crash —
  # and logged with its stacktrace, since the notice is gone with the page.
  defp safely(context, fun) do
    fun.()
  rescue
    exception ->
      log_failure(context, :error, exception, __STACKTRACE__)
      {:error, Exception.message(exception)}
  catch
    kind, reason ->
      log_failure(context, kind, reason, __STACKTRACE__)
      {:error, Exception.format_banner(kind, reason)}
  end

  defp log_failure({role, callback, args}, kind, reason, stacktrace) do
    Logger.error(
      "#{inspect(__MODULE__)}: the host's #{role} callback " <>
        "#{describe_callback(callback, length(args))} " <>
        "failed for #{inspect(args)}:\n" <> Exception.format(kind, reason, stacktrace)
    )
  end

  defp describe_callback({module, function}, arity),
    do: Exception.format_mfa(module, function, arity)

  defp describe_callback(fun, _arity), do: inspect(fun)

  # A converter the host passed in a shape that cannot be called counts as
  # none: no button, and its event is ignored.
  defp converter(%{convert: [_ | _] = convert} = assigns, conversion) do
    if Keyword.keyword?(convert),
      do: converter(%{assigns | convert: Map.new(convert)}, conversion),
      else: nil
  end

  defp converter(%{convert: %{} = convert}, conversion) do
    arity = Map.fetch!(@converter_arity, conversion)

    case Map.get(convert, conversion) do
      {module, function} = callback when is_atom(module) and is_atom(function) -> callback
      fun when is_function(fun, arity) -> fun
      _none -> nil
    end
  end

  defp converter(_assigns, _conversion), do: nil

  defp callable?({module, function}, _arity), do: is_atom(module) and is_atom(function)
  defp callable?(fun, arity), do: is_function(fun, arity)

  defp call({module, function}, args), do: apply(module, function, args)
  defp call(fun, args) when is_function(fun, length(args)), do: apply(fun, args)

  defp notice(socket, kind, message), do: assign(socket, notice: {kind, message})

  ## Queries

  # With no usable root there is nothing to write to, whatever the host says.
  defp editable?(assigns), do: assigns.editable == true and is_binary(assigns.root)

  # The shared layout parts, the emails core and other modules send, and
  # layout groups outside the namespace are refused whatever the prefixes
  # say (`PhoenixKitTemplatesEditor.Names`).
  defp allowed?(socket, name), do: Names.check(name, socket.assigns.rules) == :ok

  # A host's mistake (no list, an empty prefix that would match every name)
  # allows nothing rather than everything, or a crash. The same goes for
  # `locales` and `sample_variables`, which the page would otherwise crash on.
  defp sanitize_options(socket) do
    %{
      name_prefixes: prefixes,
      locales: locales,
      sample_variables: variables,
      preview_image_origins: origins
    } = socket.assigns

    locales = locales |> non_empty_strings() |> Enum.uniq()
    prefixes = non_empty_strings(prefixes)

    layout_groups =
      socket.assigns.layout_groups |> non_empty_strings() |> Enum.filter(&Layout.valid_group?/1)

    layout_group = socket.assigns.layout_group

    assign(socket,
      name_prefixes: prefixes,
      raw_variables: non_empty_strings(socket.assigns.raw_variables),
      module_emails: module_emails(socket.assigns.module_emails),
      locales: locales,
      sample_variables: if(is_map(variables), do: variables, else: %{}),
      preview_image_origins: origins |> non_empty_strings() |> Enum.filter(&origin?/1),
      base_language: base_language(socket.assigns.base_locale, locales),
      layout_group: if(Layout.valid_group?(layout_group), do: layout_group),
      rules: %{
        prefixes: prefixes,
        layout_groups: layout_groups,
        shared_layout_editable: socket.assigns.shared_layout_editable == true,
        reserved: reserved_names(socket.assigns.reserved_names),
        overridable: overridable(socket.assigns.overridable),
        module_groups: socket.assigns.module_emails |> module_emails() |> Names.module_groups()
      }
    )
  end

  # The layout's variables with this site's values: the host's, or core's,
  # read once.
  defp assign_layout_values(%{assigns: %{layout_variables: %{} = variables}} = socket),
    do: assign(socket, layout_values: Map.new(variables, fn {k, v} -> {to_string(k), v} end))

  defp assign_layout_values(%{assigns: %{layout_values: %{}}} = socket), do: socket

  defp assign_layout_values(socket),
    do: assign(socket, layout_values: Variables.layout_variables(socket.assigns.layout_group))

  defp overridable(:all), do: :all
  defp overridable(names), do: non_empty_strings(names)

  # Catalogue entries (`PhoenixKit.Email.Catalog`): a map with a name each.
  defp module_emails(entries) when is_list(entries),
    do: for(%{name: name} = entry <- entries, is_binary(name), do: entry)

  defp module_emails(_other), do: []

  # The emails core and other modules send; a host may pass its own list.
  defp reserved_names(names) when is_list(names), do: non_empty_strings(names)
  defp reserved_names(_catalog), do: Names.reserved_names()

  defp base_language(locale, _locales) when is_binary(locale) and locale != "", do: locale
  defp base_language(_none, locales), do: List.first(locales)

  # An origin goes into the frame's policy as it is: only a plain
  # `http(s)://host[:port]`, nothing that could end the directive.
  defp origin?(origin), do: Regex.match?(~r/\Ahttps?:\/\/[a-z0-9.\-]+(?::[0-9]{1,5})?\z/i, origin)

  defp non_empty_strings(list) when is_list(list),
    do: Enum.filter(list, &(is_binary(&1) and &1 != ""))

  defp non_empty_strings(_other), do: []

  defp writable?(socket, name), do: editable?(socket.assigns) and visible?(socket, name)

  # The form of the open tab may be saved or converted into — not on an
  # email's fallback tab nothing reads, which is shown read-only.
  defp form_writable?(socket),
    do: writable?(socket, socket.assigns.selected) and not unused_fallback?(socket.assigns)

  # Locale-less files of the open email that nothing reads, on its tab.
  defp fallback_deletable?(socket) do
    %{selected: name} = socket.assigns

    writable?(socket, name) and unused_fallback?(socket.assigns) and
      fallback_files(socket.assigns, name) != []
  end

  # Listed templates are already filtered by prefix; a draft is checked here,
  # since the host may have changed the prefixes since it was created.
  defp visible?(socket, name) do
    exists?(socket, name) or
      (socket.assigns.draft? and name == socket.assigns.selected and allowed?(socket, name))
  end

  defp exists?(socket, name), do: Enum.any?(socket.assigns.templates, &(&1.name == name))

  defp files_of(socket, name), do: template_files(socket.assigns, name)

  defp template_files(assigns, name) do
    case Enum.find(assigns.templates, &(&1.name == name)) do
      %{files: files} -> files
      nil -> []
    end
  end

  # The language tabs of template `name`, then Fallback (`nil`) — which an
  # email has only while the host uses it, or while locale-less files of it
  # are left over, to be seen and deleted.
  defp tabs(assigns, name) do
    if fallback_used?(assigns, name) or fallback_files(assigns, name) != [],
      do: assigns.locales ++ [nil],
      else: assigns.locales
  end

  # A header, footer or layout (a leading "_") always falls back; an email
  # does unless the host says it never does (`email_fallback: false`). With
  # no languages, the fallback is all there is.
  defp fallback_used?(%{email_fallback: false, locales: [_ | _]}, name) when is_binary(name),
    do: String.starts_with?(name, "_")

  defp fallback_used?(_assigns, _name), do: true

  defp fallback_files(assigns, name) do
    for %{locale: nil, part: part} = file <- template_files(assigns, name),
        part in @parts,
        do: file
  end

  # The open tab is an email's fallback nothing reads.
  defp unused_fallback?(%{selected: nil}), do: false

  defp unused_fallback?(assigns),
    do: assigns.locale == nil and not fallback_used?(assigns, assigns.selected)

  # The first tab that has a file, so a locale-less shared part opens on
  # its fallback tab rather than on an empty first language — but never an
  # unused fallback.
  defp initial_locale(socket, name) do
    files = files_of(socket, name)
    tabs = tabs(socket.assigns, name)
    candidates = if fallback_used?(socket.assigns, name), do: tabs, else: List.delete(tabs, nil)
    Enum.find(candidates, hd(tabs), fn tab -> Enum.any?(files, &(&1.locale == tab)) end)
  end

  defp caption(socket, name, files) do
    labels = for %{part: :label} = file <- files, into: %{}, do: {file.locale, file.path}

    Enum.find_value(socket.assigns.locales ++ [nil], name, fn tab ->
      with path when is_binary(path) <- labels[tab],
           {:ok, label} <- Files.safe_read(socket.assigns.root, path),
           true <- String.valid?(label),
           label when label != "" <- String.trim(label) do
        label
      else
        _no_label -> nil
      end
    end)
  end

  defp normalize_newlines(value), do: String.replace(value, "\r\n", "\n")

  defp describe_errors(errors) do
    Enum.map_join(errors, "; ", fn {part, reason} ->
      "#{part_title(part)}: #{describe(reason)}"
    end)
  end

  defp describe(:too_large),
    do: gettext("larger than %{size} KiB", size: div(Overrides.max_bytes(), 1024))

  defp describe(:timeout), do: gettext("it took too long")
  defp describe(:invalid_content), do: gettext("not valid UTF-8 text")
  defp describe(:invalid_name), do: gettext("not a valid template name")
  defp describe(:invalid_part), do: gettext("not a part this editor writes")
  defp describe(:invalid_locale), do: gettext("not a valid language tag")
  defp describe(:invalid_root), do: gettext("the template directory does not exist")

  defp describe(:unsafe_path),
    do: gettext("the path leads outside the template directory")

  defp describe(:enoent), do: gettext("already gone")
  defp describe(reason) when is_atom(reason), do: reason |> :file.format_error() |> to_string()
  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)

  # A host's own reason is not a file error: shown as it is, not as POSIX.
  defp describe_host(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp describe_host(reason) when is_binary(reason) do
    if String.valid?(reason), do: reason, else: inspect(reason)
  end

  defp describe_host(reason), do: inspect(reason)

  ## Rendering

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        messages:
          Enum.reject(
            assigns.templates,
            &(String.starts_with?(&1.name, "_") or module_name?(assigns, &1.name))
          ),
        module_list: module_list(assigns),
        module_layouts: module_layouts(assigns),
        auth_warning: (assigns.selected || assigns.module_selected) in Names.auth_emails(),
        can_test_send: assigns.test_send != nil and test_send_target(assigns) != nil,
        own_paths:
          if(assigns.selected && is_binary(assigns.root),
            do:
              Map.new(@parts, fn part ->
                {part, part_path(assigns.root, assigns.selected, part, assigns.locale)}
              end),
            else: %{}
          ),
        shared: Enum.filter(assigns.templates, &shared_part?(&1.name)),
        layout_sources:
          for(%{group: group} <- assigns.layouts, own_any?(assigns, group), do: group),
        email: selected_email(assigns),
        layout_emails:
          Map.new(assigns.layouts, &{&1.group, describe_layout_emails(assigns, &1.emails)}),
        tabs: tabs(assigns, assigns.selected),
        fallback_used: fallback_used?(assigns, assigns.selected),
        fallback_unused: unused_fallback?(assigns),
        parts: @parts,
        can_edit: editable?(assigns),
        form_shown:
          assigns.selected != nil and editable?(assigns) and not unused_fallback?(assigns),
        variable_rows: panel_rows(assigns),
        can_fill_text: converter(assigns, :to_text) != nil,
        can_render_markdown: converter(assigns, :markdown_to_html) != nil
      )

    ~H"""
    <div id={@id} class="flex flex-col gap-4">
      <div :if={!is_binary(@root)} role="alert" class="alert alert-error">
        {gettext("No template directory is configured.")}
      </div>
      <div :if={@notice} role="alert" class={notice_class(elem(@notice, 0))}>
        {elem(@notice, 1)}
      </div>

      <div class="grid gap-6 lg:grid-cols-4">
        <aside class="flex flex-col gap-4 lg:col-span-1">
          <button
            :if={@can_edit}
            id={"#{@id}-reload"}
            type="button"
            phx-click="reload"
            phx-target={@myself}
            class="btn btn-sm btn-ghost self-start"
            title={
              gettext("Read the templates again from disk: after a change by hand or a git pull.")
            }
          >
            {gettext("Reload")}
          </button>
          <p :if={@templates == []} class="text-sm opacity-70">{gettext("No templates yet.")}</p>

          <.template_group
            :if={@messages != []}
            id={"#{@id}-messages"}
            title={gettext("Messages")}
            templates={@messages}
            selected={@selected}
            base_language={@base_language}
            myself={@myself}
          />
          <div :if={@layouts != []} id={"#{@id}-layouts"} class="flex flex-col gap-2">
            <span class="text-sm font-semibold">{gettext("Layouts")}</span>
            <.layout_entry
              :for={layout <- @layouts}
              id={"#{@id}-layout-#{layout.group}"}
              layout={layout}
              selected={@selected}
              templates={@templates}
              can_delete={@can_edit && layout.group in @layout_sources}
              emails={@layout_emails[layout.group]}
              myself={@myself}
            />

            <div
              :if={@confirm_layout_delete}
              id={"#{@id}-layouts-delete"}
              role="alert"
              class="alert alert-warning flex-col items-start text-sm"
            >
              <span>
                {gettext(
                  "Delete the layout “%{name}”: its own header, footer and page layout, in every language?",
                  name: @confirm_layout_delete
                )}
              </span>
              <div class="flex gap-2">
                <button
                  id={"#{@id}-layouts-delete-confirm"}
                  type="button"
                  phx-click="confirm_delete_layout"
                  phx-target={@myself}
                  class="btn btn-sm btn-error"
                >
                  {gettext("Delete")}
                </button>
                <button
                  id={"#{@id}-layouts-delete-cancel"}
                  type="button"
                  phx-click="cancel_delete_layout"
                  phx-target={@myself}
                  class="btn btn-sm btn-ghost"
                >
                  {gettext("Cancel")}
                </button>
              </div>
            </div>

            <form
              :if={@can_edit && @layout_sources != []}
              id={"#{@id}-layouts-create"}
              phx-submit="create_layout"
              phx-target={@myself}
              class="flex flex-col gap-2"
            >
              <span class="text-sm font-semibold">{gettext("New layout")}</span>
              <input
                type="text"
                name="layout_create[name]"
                aria-label={gettext("Layout name")}
                class="input input-sm w-full font-mono"
                placeholder={List.first(Names.namespaces(@rules), gettext("name"))}
                autocomplete="off"
              />
              <select
                name="layout_create[copy_from]"
                aria-label={gettext("Start from")}
                class="select select-sm w-full"
              >
                <option :for={group <- @layout_sources} value={group}>
                  {gettext("Copy of layout %{name}", name: group)}
                </option>
              </select>
              <button type="submit" class="btn btn-sm">{gettext("Create layout")}</button>
            </form>
          </div>

          <div
            :if={@module_list != [] or @module_layouts != []}
            id={"#{@id}-module-emails"}
            class="flex flex-col gap-2"
          >
            <span class="text-sm font-semibold">{gettext("Module emails")}</span>
            <p class="text-xs opacity-70">
              {gettext(
                "Sent by PhoenixKit and its modules in their built-in text, until an email has a file here."
              )}
            </p>
            <ul :if={@module_list != []} class="menu menu-sm w-full p-0">
              <li :for={item <- @module_list}>
                <button
                  type="button"
                  phx-click={if(item.template?, do: "select", else: "select_module")}
                  phx-value-name={item.name}
                  phx-target={@myself}
                  class={[
                    "flex flex-col items-start gap-0",
                    item.name in [@selected, @module_selected] && "menu-active"
                  ]}
                >
                  <span>{item.label}</span>
                  <span class="flex items-center gap-1 font-mono text-xs opacity-60">
                    {item.name}
                    <span class="badge badge-ghost badge-xs">
                      {if(item.file?, do: gettext("file"), else: gettext("built-in text"))}
                    </span>
                  </span>
                </button>
              </li>
            </ul>
            <div
              :for={layout <- @module_layouts}
              id={"#{@id}-module-layout-#{layout.group}"}
              class="rounded-box border border-base-300 p-2 flex flex-col gap-1"
            >
              <span class="font-mono text-sm font-semibold">{layout.group}</span>
              <div :for={part <- layout.parts} class="flex items-center gap-2 text-sm">
                <span class="opacity-70">{kind_title(part.kind)}</span>
                <span :if={part.file?} class="text-xs opacity-60">{gettext("has its own file")}</span>
                <span :if={!part.file?} class="text-xs opacity-60">
                  {part_source(part.inherited)}
                </span>
                <button
                  :if={!part.file? && @can_edit && part.overridable?}
                  id={"#{@id}-module-layout-#{layout.group}-#{part.kind}-create"}
                  type="button"
                  phx-click="override_layout"
                  phx-value-name={part.name}
                  phx-target={@myself}
                  class="btn btn-xs ml-auto"
                >
                  {gettext("Create file")}
                </button>
              </div>
            </div>
          </div>

          <.template_group
            :if={@shared != []}
            id={"#{@id}-shared"}
            title={gettext("Shared parts")}
            templates={@shared}
            selected={@selected}
            myself={@myself}
          />

          <form
            :if={@can_edit}
            id={"#{@id}-create"}
            phx-submit="create"
            phx-change="create_change"
            phx-target={@myself}
            class="flex flex-col gap-2"
          >
            <span class="text-sm font-semibold">{gettext("New template")}</span>
            <input
              type="text"
              name="create[name]"
              aria-label={gettext("Template name")}
              class="input input-sm w-full font-mono"
              placeholder={List.first(@name_prefixes, gettext("name"))}
              autocomplete="off"
              value={@create_name}
            />
            <select
              name="create[copy_from]"
              aria-label={gettext("Start from")}
              class="select select-sm w-full"
            >
              <option value="" selected={@create_from in [nil, ""]}>{gettext("Empty")}</option>
              <option
                :for={template <- @templates}
                value={template.name}
                selected={template.name == @create_from}
              >
                {gettext("Copy of %{name}", name: template.name)}
              </option>
            </select>
            <fieldset
              :if={@create_extras != []}
              id={"#{@id}-create-extras"}
              class="fieldset text-sm"
            >
              <legend class="fieldset-legend">{gettext("Also copy the host’s own files:")}</legend>
              <input type="hidden" name="create[keep_for]" value={@create_from} />
              <input type="hidden" name="create[keep][]" value="" />
              <label :for={file <- @create_extras} class="label font-mono text-xs">
                <input
                  type="checkbox"
                  name="create[keep][]"
                  value={file}
                  checked
                  class="checkbox checkbox-xs"
                />
                {file}
              </label>
            </fieldset>
            <button type="submit" class="btn btn-sm">{gettext("Create")}</button>
          </form>
        </aside>

        <section class="flex flex-col gap-4 lg:col-span-3">
          <p :if={is_nil(@selected) && is_nil(@module_view)} class="text-sm opacity-70">
            {gettext("Select a template.")}
          </p>

          <div
            :if={@auth_warning}
            id={"#{@id}-auth-warning"}
            role="alert"
            class="alert alert-warning text-sm"
          >
            {gettext(
              "This email lets people into their account or warns them about a sign-in: a mistake in it can keep everyone out or hide an intrusion. Send it to yourself before relying on it."
            )}
          </div>

          <div :if={@module_view} id={"#{@id}-module-email"} class="flex flex-col gap-3">
            <div class="flex flex-wrap items-center gap-2">
              <h3 class="text-lg font-semibold">{@module_view.entry[:label] || @module_selected}</h3>
              <span class="font-mono text-sm opacity-60">{@module_selected}</span>
              <button
                :if={@can_test_send}
                id={"#{@id}-test-send"}
                type="button"
                phx-click="test_send"
                phx-target={@myself}
                class="btn btn-sm ml-auto"
              >
                {gettext("Send to me")}
              </button>
            </div>
            <p :if={is_binary(@module_view.entry[:description])} class="text-sm opacity-70">
              {@module_view.entry[:description]}
            </p>
            <div
              :if={!@module_view.overridable?}
              id={"#{@id}-module-email-not-overridable"}
              class="alert alert-info alert-soft text-sm"
            >
              {gettext("This email may not be overridden here: it is shown read only.")}
            </div>
            <div role="tablist" class="tabs tabs-box w-fit">
              <button
                :for={tab <- @locales}
                type="button"
                role="tab"
                phx-click="module_locale"
                phx-value-locale={tab}
                phx-target={@myself}
                aria-selected={to_string(tab == @module_locale)}
                class={["tab", tab == @module_locale && "tab-active"]}
              >
                {tab}
              </button>
            </div>
            <.sources_box
              :if={@module_view.sources}
              id={"#{@id}-module-email-sources"}
              result={@module_view.sources}
              root={@root}
            />
            <div class="flex flex-col gap-2">
              <span class="text-sm font-semibold">{gettext("Built-in text")}</span>
              <%= case @module_view.defaults do %>
                <% {:ok, parts} -> %>
                  <dl class="flex flex-col gap-2">
                    <div :for={part <- Enum.filter([:subject, :markdown, :text, :html], &parts[&1])}>
                      <dt class="text-sm opacity-70">{part_title(part)}</dt>
                      <dd>
                        <pre class="whitespace-pre-wrap rounded-box bg-base-200 p-3 text-sm">{parts[part]}</pre>
                      </dd>
                    </div>
                  </dl>
                <% {:error, message} -> %>
                  <p class="text-sm text-error">
                    {gettext("Could not tell: %{reason}", reason: message)}
                  </p>
              <% end %>
            </div>
            <div
              :if={@can_edit && @module_view.overridable? && !@module_view.file?}
              class="flex flex-col items-start gap-2"
            >
              <p class="text-sm">
                {gettext(
                  "A file made here is this email's text from then on: translations a module update brings no longer reach this email."
                )}
              </p>
              <div class="flex flex-wrap gap-2">
                <button
                  id={"#{@id}-module-create-default"}
                  type="button"
                  phx-click="override_default"
                  phx-value-name={@module_selected}
                  phx-target={@myself}
                  class="btn btn-sm"
                >
                  {gettext("Create file from the built-in text")}
                </button>
                <button
                  :if={@module_view.db?}
                  id={"#{@id}-module-create-db"}
                  type="button"
                  phx-click="override_db"
                  phx-value-name={@module_selected}
                  phx-target={@myself}
                  class="btn btn-sm"
                >
                  {gettext("Create file from the database template")}
                </button>
              </div>
            </div>
            <.variables_panel
              :if={@module_view.variables != []}
              id={"#{@id}-module-email-variables"}
              rows={@module_view.variables}
            />
          </div>

          <div :if={@selected} class="flex flex-wrap items-center gap-2">
            <h3 class="font-mono text-lg font-semibold">{@selected}</h3>
            <span :if={@draft?} class="badge badge-warning badge-sm">{gettext("not saved yet")}</span>
            <button
              :if={@can_test_send}
              id={"#{@id}-test-send"}
              type="button"
              phx-click="test_send"
              phx-target={@myself}
              class="btn btn-sm"
            >
              {gettext("Send to me")}
            </button>
            <button
              :if={@can_edit}
              id={"#{@id}-delete"}
              type="button"
              phx-click="delete"
              phx-target={@myself}
              class="btn btn-sm btn-outline btn-error ml-auto"
            >
              {gettext("Delete")}
            </button>
          </div>

          <form
            :if={@email && @can_edit}
            id={"#{@id}-email-layout"}
            phx-change="set_layout"
            phx-target={@myself}
            class="flex items-center gap-2"
          >
            <label for={"#{@id}-email-layout-group"} class="text-sm font-semibold">
              {gettext("Layout")}
            </label>
            <select
              id={"#{@id}-email-layout-group"}
              name="email_layout[group]"
              class="select select-sm w-auto"
            >
              <option value="" selected={is_nil(@email.layout)}>
                {default_layout_label(@layout_group)}
              </option>
              <option
                :for={group <- layout_options(@layouts, @email.layout)}
                value={group}
                selected={group == @email.layout}
              >
                {group}
              </option>
            </select>
          </form>
          <p :if={@email && !@can_edit} id={"#{@id}-email-layout-current"} class="text-sm">
            <span class="font-semibold">{gettext("Layout")}:</span>
            {@email.layout || default_layout_label(@layout_group)}
          </p>

          <p
            :if={
              @selected && !@draft? && @var_context && @var_context.kind == :email &&
                @var_context.sent_by == :host
            }
            id={"#{@id}-sent-by-host"}
            class="text-sm opacity-70"
          >
            {gettext("Sent by the application itself: these files are what it sends.")}
          </p>
          <.sources_box
            :if={@selected && @sources}
            id={"#{@id}-sources"}
            result={@sources}
            own={@own_paths}
            root={@root}
          />

          <div :if={@confirm_delete?} role="alert" class="alert alert-warning">
            <span>{gettext("Delete “%{name}” and all its files?", name: @selected)}</span>
            <div class="flex gap-2">
              <button
                id={"#{@id}-delete-confirm"}
                type="button"
                phx-click="confirm_delete"
                phx-target={@myself}
                class="btn btn-sm btn-error"
              >
                {gettext("Delete")}
              </button>
              <button
                id={"#{@id}-delete-cancel"}
                type="button"
                phx-click="cancel_delete"
                phx-target={@myself}
                class="btn btn-sm btn-ghost"
              >
                {gettext("Cancel")}
              </button>
            </div>
          </div>

          <div :if={@selected} role="tablist" class="tabs tabs-box w-fit">
            <button
              :for={tab <- @tabs}
              type="button"
              role="tab"
              phx-click="locale"
              phx-value-locale={tab || ""}
              phx-target={@myself}
              aria-selected={to_string(tab == @locale)}
              class={["tab", tab == @locale && "tab-active"]}
              title={if(is_nil(tab), do: gettext("Used for any language without its own file"))}
            >
              {tab || gettext("Fallback")}
              <span :if={is_nil(tab) && !@fallback_used} class="badge badge-ghost badge-xs ml-1">
                {gettext("not used")}
              </span>
            </button>
          </div>

          <div
            :if={@fallback_unused}
            id={"#{@id}-fallback-unused"}
            role="alert"
            class="alert alert-warning text-sm"
          >
            <span>
              {gettext(
                "These files without a language are not used: an email is sent only in its own languages."
              )}
            </span>
            <button
              :if={@can_edit && !@confirm_fallback_delete?}
              id={"#{@id}-fallback-delete"}
              type="button"
              phx-click="delete_fallback"
              phx-target={@myself}
              class="btn btn-sm btn-outline btn-error"
            >
              {gettext("Delete")}
            </button>
          </div>

          <div
            :if={@fallback_unused && @confirm_fallback_delete?}
            role="alert"
            class="alert alert-warning"
          >
            <span>
              {gettext("Delete the files without a language of “%{name}”?", name: @selected)}
            </span>
            <div class="flex gap-2">
              <button
                id={"#{@id}-fallback-delete-confirm"}
                type="button"
                phx-click="confirm_delete_fallback"
                phx-target={@myself}
                class="btn btn-sm btn-error"
              >
                {gettext("Delete")}
              </button>
              <button
                id={"#{@id}-fallback-delete-cancel"}
                type="button"
                phx-click="cancel_delete_fallback"
                phx-target={@myself}
                class="btn btn-sm btn-ghost"
              >
                {gettext("Cancel")}
              </button>
            </div>
          </div>

          <div
            :if={@conflict}
            id={"#{@id}-conflict"}
            role="alert"
            class="alert alert-error flex-col items-start text-sm"
          >
            <span>
              {gettext(
                "Not saved: the file changed on disk since you opened it — edited by hand, by a git pull or by another user. Your changes are still in the form; reload to work on what is on disk now."
              )}
            </span>
            <div :for={{part, content} <- @conflict} class="w-full">
              <span class="font-semibold">{gettext("%{part} on disk now:", part: part_title(part))}</span>
              <pre
                :if={is_binary(content)}
                class="whitespace-pre-wrap rounded-box bg-base-200 p-2 text-xs"
              >{content}</pre>
              <span :if={is_nil(content)} class="opacity-70">{gettext("no file")}</span>
              <span :if={content == :unreadable} class="opacity-70">
                {gettext("cannot be read here")}
              </span>
            </div>
            <button
              id={"#{@id}-conflict-reload"}
              type="button"
              phx-click="reload"
              phx-target={@myself}
              class="btn btn-sm"
            >
              {gettext("Reload")}
            </button>
          </div>

          <div
            :if={@confirm_variables}
            id={"#{@id}-confirm-variables"}
            role="alert"
            class="alert alert-warning flex-col items-start text-sm"
          >
            <span>{confirm_variables_message(@var_context, @confirm_variables.names)}</span>
            <div class="flex gap-2">
              <button
                id={"#{@id}-confirm-variables-save"}
                type="button"
                phx-click="confirm_save"
                phx-target={@myself}
                class="btn btn-sm btn-warning"
              >
                {gettext("Save anyway")}
              </button>
              <button
                id={"#{@id}-confirm-variables-cancel"}
                type="button"
                phx-click="cancel_save"
                phx-target={@myself}
                class="btn btn-sm btn-ghost"
              >
                {gettext("Cancel")}
              </button>
            </div>
          </div>

          <div
            :if={@selected}
            id={"#{@id}-form"}
            phx-hook={if(@form_shown, do: "PhoenixKitTemplatesEditorInsertVariable")}
            class="flex flex-col gap-4"
          >
            <form
              :if={@form_shown}
              id={"#{@id}-parts"}
              phx-submit="save"
              phx-target={@myself}
              class="flex flex-col gap-3"
            >
              <.part_field
                :for={part <- @parts}
                id={"#{@id}-part-#{part}"}
                part={part}
                file={@contents[part]}
                value={@form_values[part]}
                rev={@form_rev}
              />
              <p class="text-xs opacity-70">
                {gettext(
                  "Each language is saved on its own: switching tabs or templates drops unsaved changes. A part saved empty has its file deleted."
                )}
              </p>
              <%!-- Save comes first: the form's default button. --%>
              <div class="flex flex-wrap gap-2">
                <button type="submit" name="action" value="save" class="btn btn-primary btn-sm">
                  {gettext("Save")}
                </button>
                <button
                  :if={@can_fill_text}
                  id={"#{@id}-to-text"}
                  type="submit"
                  name="action"
                  value="to_text"
                  class="btn btn-sm"
                  title={
                    gettext(
                      "Put the Markdown, or else the HTML, as plain text in Text. Not saved until you Save."
                    )
                  }
                >
                  {gettext("Fill text from content")}
                </button>
                <button
                  :if={@can_render_markdown}
                  id={"#{@id}-md-to-html"}
                  type="submit"
                  name="action"
                  value="md_to_html"
                  class="btn btn-sm"
                  title={gettext("Put the Markdown, rendered, in HTML. Not saved until you Save.")}
                >
                  {gettext("Markdown → HTML")}
                </button>
              </div>
            </form>

            <dl :if={@selected && (!@can_edit || @fallback_unused)} class="flex flex-col gap-3">
              <div :for={part <- @parts}>
                <dt class="text-sm font-semibold">{part_title(part)}</dt>
                <dd :if={@contents[part] && @contents[part][:invalid]} class="text-sm text-error">
                  {unreadable_message(@contents[part])}
                </dd>
                <dd :if={@contents[part] && !@contents[part][:invalid]}>
                  <pre class="whitespace-pre-wrap rounded-box bg-base-200 p-3 text-sm">{@contents[part].content}</pre>
                </dd>
                <dd :if={!@contents[part]} class="text-sm opacity-60">{gettext("No file.")}</dd>
              </div>
            </dl>

            <div
              :if={@selected && @missing != []}
              id={"#{@id}-missing"}
              role="alert"
              class="alert alert-warning text-sm"
            >
              {gettext("Unknown placeholders: %{names}",
                names: Enum.map_join(@missing, ", ", &"{{#{&1}}}")
              )}
            </div>

            <.variables_panel
              :if={@variable_rows != []}
              id={"#{@id}-variables"}
              rows={@variable_rows}
              form={if(@form_shown, do: "#{@id}-parts")}
            />
          </div>

          <div :if={@selected && @preview_result} id={"#{@id}-preview"} class="flex flex-col gap-2">
            <span class="text-sm font-semibold">{gettext("Preview")}</span>
            <.preview_pane
              id={@id}
              result={@preview_result}
              tab={@preview_tab}
              csp={preview_csp(@preview_image_origins)}
              myself={@myself}
            />
          </div>
        </section>
      </div>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:templates, :list, required: true)
  attr(:selected, :string, default: nil)
  attr(:base_language, :string, default: nil)
  attr(:myself, :any, required: true)

  defp template_group(assigns) do
    ~H"""
    <div id={@id}>
      <span class="text-sm font-semibold">{@title}</span>
      <ul class="menu menu-sm w-full p-0">
        <li :for={template <- @templates}>
          <button
            type="button"
            phx-click="select"
            phx-value-name={template.name}
            phx-target={@myself}
            class={["flex flex-col items-start gap-0", template.name == @selected && "menu-active"]}
          >
            <span>{template.caption}</span>
            <span :if={template.caption != template.name} class="font-mono text-xs opacity-60">
              {template.name}
            </span>
            <span
              :if={template.incomplete?}
              id={"#{@id}-incomplete-#{template.name}"}
              class="flex items-baseline gap-1 text-xs text-warning"
            >
              <span class="badge badge-warning badge-xs" aria-hidden="true">!</span>
              {gettext("Not offered for sending: no subject or body in %{locale}.",
                locale: @base_language
              )}
            </span>
          </button>
        </li>
      </ul>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:layout, :map, required: true)
  attr(:selected, :string, default: nil)
  attr(:templates, :list, required: true)
  attr(:can_delete, :boolean, default: false)
  attr(:emails, :string, required: true)
  attr(:myself, :any, required: true)

  # One layout: its parts, each its own (opens in the editor) or inherited,
  # and the emails using it.
  defp layout_entry(assigns) do
    assigns = assign(assigns, shown: MapSet.new(assigns.templates, & &1.name))

    ~H"""
    <div id={@id} class="rounded-box border border-base-300 p-2 flex flex-col gap-1">
      <div class="flex items-center gap-2">
        <span class="font-mono text-sm font-semibold">{@layout.group}</span>
        <span :if={@layout.default?} class="badge badge-ghost badge-xs">{gettext("default")}</span>
        <button
          :if={@can_delete}
          id={"#{@id}_delete"}
          type="button"
          phx-click="delete_layout"
          phx-value-group={@layout.group}
          phx-target={@myself}
          class="btn btn-xs btn-ghost text-error ml-auto"
        >
          {gettext("Delete")}
        </button>
      </div>
      <ul class="menu menu-sm w-full p-0">
        <li :for={part <- @layout.parts} id={"#{@id}_#{part.kind}"}>
          <button
            :if={part.source == :own and MapSet.member?(@shown, part.name)}
            type="button"
            phx-click="select"
            phx-value-name={part.name}
            phx-target={@myself}
            class={["flex flex-col items-start gap-0", part.name == @selected && "menu-active"]}
          >
            <span>{kind_title(part.kind)}</span>
            <span class="font-mono text-xs opacity-60">{part.name}</span>
          </button>
          <span
            :if={part.source != :own or not MapSet.member?(@shown, part.name)}
            class="flex flex-col items-start gap-0 pointer-events-none"
          >
            <span class="opacity-70">{kind_title(part.kind)}</span>
            <span class="text-xs opacity-60">{part_source(part.source)}</span>
          </span>
        </li>
      </ul>
      <p id={"#{@id}_emails"} class="text-xs opacity-70">{@emails}</p>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:rows, :list, required: true)
  attr(:form, :string, default: nil)

  # The variables of a part: a button each that puts it into the form
  # (`form`), or, read only, just the names.
  defp variables_panel(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col gap-1 text-sm">
      <span class="font-semibold">{gettext("Variables")}</span>
      <p :if={@form} class="text-xs opacity-70">
        {gettext("Click a variable to put it where the cursor is in the field you were typing in.")}
      </p>
      <ul class="flex flex-col gap-1">
        <li :for={row <- @rows} id={"#{@id}-#{row.name}"} class="flex flex-wrap items-baseline gap-2">
          <button
            :if={@form}
            type="submit"
            form={@form}
            name="action"
            value={"insert:#{row.name}"}
            data-variable={placeholder(row)}
            class="btn btn-xs font-mono"
          >
            {placeholder(row)}
          </button>
          <code :if={!@form} class="font-mono">{placeholder(row)}</code>
          <span :if={row.sample not in [nil, ""]} class="font-mono text-xs opacity-60">
            {row.sample}
          </span>
          <span :if={row.description} class="text-xs">{row.description}</span>
          <span :if={row.scope == :markdown} class="badge badge-ghost badge-xs">
            {gettext("Markdown only")}
          </span>
          <span :if={row.scope == :html} class="badge badge-ghost badge-xs">
            {gettext("rendered HTML, three braces")}
          </span>
        </li>
      </ul>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:result, :any, required: true)
  attr(:own, :map, default: %{})
  attr(:root, :string, required: true)

  # Where each part of an email core sends comes from.
  defp sources_box(assigns) do
    {sources, error} =
      case assigns.result do
        {:ok, sources} -> {sources, nil}
        {:error, message} -> {nil, message}
      end

    assigns = assign(assigns, sources: sources, error: error)

    ~H"""
    <div id={@id} class="rounded-box border border-base-300 p-3 text-sm flex flex-col gap-2">
      <span class="font-semibold">{gettext("What is sent")}</span>
      <div :if={@sources && @sources.db?} id={"#{@id}-db"} role="alert" class="alert alert-error">
        {gettext(
          "The Emails module has an active database template of this name: that is what is sent, not these files."
        )}
      </div>
      <dl :if={@sources} class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1">
        <%= for part <- [:subject, :text, :html, :markdown] do %>
          <dt class="opacity-70">{part_title(part)}</dt>
          <dd>{source_label(@sources[part], @own[part], @root)}</dd>
        <% end %>
      </dl>
      <p :if={@sources && @sources.html == nil && @sources.html_from} class="text-xs opacity-70">
        {gettext("The HTML is made from the %{part}.", part: body_from(@sources.html_from))}
      </p>
      <p :if={@error} class="text-error">
        {gettext("Could not tell: %{reason}", reason: @error)}
      </p>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:part, :atom, required: true)
  attr(:file, :map, default: nil)
  attr(:value, :string, default: nil)
  attr(:rev, :integer, default: 0)

  defp part_field(%{file: %{invalid: true}} = assigns) do
    ~H"""
    <div class="flex flex-col gap-1">
      <span class="text-sm font-semibold">{part_title(@part)}</span>
      <div id={"#{@id}-invalid"} role="alert" class="alert alert-error text-sm">
        {unreadable_message(@file)}
      </div>
    </div>
    """
  end

  defp part_field(assigns) do
    assigns =
      assign(assigns,
        value: assigns.value || if(assigns.file, do: assigns.file.content, else: ""),
        rows: Map.fetch!(@part_rows, assigns.part)
      )

    ~H"""
    <div class="flex flex-col gap-1">
      <label for={@id} class="flex items-baseline gap-2 text-sm">
        <span class="font-semibold">{part_title(@part)}</span>
        <span class="opacity-60">{part_hint(@part)}</span>
        <span :if={@file} class="ml-auto text-xs opacity-60">
          {gettext("changed %{time}", time: Calendar.strftime(@file.mtime, "%Y-%m-%d %H:%M UTC"))}
        </span>
      </label>
      <textarea
        id={@id}
        name={"parts[#{@part}]"}
        rows={@rows}
        data-form-rev={@rev}
        class="textarea w-full font-mono text-sm"
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:result, :any, required: true)
  attr(:tab, :atom, default: :html)
  attr(:csp, :string, required: true)
  attr(:myself, :any, required: true)

  defp preview_pane(%{result: {:ok, subject, html, text}} = assigns) do
    assigns =
      assign(assigns,
        subject: subject,
        html: html,
        text: text,
        show_html?: text == :none or assigns.tab == :html
      )

    ~H"""
    <p id={"#{@id}-preview-subject"} class="text-sm">
      <span class="opacity-60">{gettext("Subject:")}</span> {@subject}
    </p>
    <div :if={@text != :none} role="tablist" class="tabs tabs-border w-fit">
      <button
        :for={{tab, title} <- [html: part_title(:html), text: part_title(:text)]}
        id={"#{@id}-preview-tab-#{tab}"}
        type="button"
        role="tab"
        phx-click="preview_tab"
        phx-value-tab={tab}
        phx-target={@myself}
        aria-selected={to_string(tab == @tab)}
        class={["tab", tab == @tab && "tab-active"]}
      >
        {title}
      </button>
    </div>
    <%!-- bg-white, not a theme colour: an email is drawn on white whatever the admin theme. --%>
    <%!-- Nothing in an edited template runs (no allow-scripts), leaks the
         admin page's address, or loads anything from outside but images
         from the origins the host names (`csp` on the frame, which only
         Chromium honours, and the same policy as a meta tag at the top of
         the document, which every browser does). --%>
    <iframe
      :if={@show_html? && @html}
      sandbox=""
      referrerpolicy="no-referrer"
      csp={@csp}
      srcdoc={with_policy(@html, @csp)}
      title={gettext("Preview")}
      class="h-[32rem] w-full rounded-box border border-base-300 bg-white"
    ></iframe>
    <p :if={@show_html? && !@html} class="text-sm opacity-70">{gettext("No HTML.")}</p>
    <pre
      :if={!@show_html? && @text}
      id={"#{@id}-preview-text"}
      class="whitespace-pre-wrap rounded-box bg-base-200 p-3 text-sm"
    >{@text}</pre>
    <p :if={!@show_html? && !@text} class="text-sm opacity-70">{gettext("No text.")}</p>
    """
  end

  defp preview_pane(%{result: :unsaved} = assigns) do
    ~H"""
    <p class="text-sm opacity-70">{gettext("Save the template to preview it.")}</p>
    """
  end

  defp preview_pane(%{result: {:error, message}} = assigns) do
    assigns = assign(assigns, message: message)

    ~H"""
    <div role="alert" class="alert alert-error text-sm">
      {gettext("Preview unavailable: %{reason}", reason: @message)}
    </div>
    """
  end

  defp unreadable_message(%{reason: :unsafe_path}),
    do: gettext("This file is a link or outside the template directory: it is not read here.")

  defp unreadable_message(%{reason: :too_large}),
    do:
      gettext("This file is larger than %{size} KiB: it is not read here.",
        size: div(Overrides.max_bytes(), 1024)
      )

  defp unreadable_message(_invalid),
    do: gettext("This file is not valid UTF-8 text; fix it on disk to edit it here.")

  defp part_title(:label), do: gettext("Label")
  defp part_title(:subject), do: gettext("Subject")
  defp part_title(:text), do: gettext("Text")
  defp part_title(:markdown), do: gettext("Markdown")
  defp part_title(:html), do: gettext("HTML")

  defp kind_title(:header), do: gettext("Header")
  defp kind_title(:footer), do: gettext("Footer")
  defp kind_title(:layout), do: gettext("Page layout")

  defp part_source(:own), do: gettext("its own, not editable here")
  defp part_source(:shared), do: gettext("inherited: the shared one")
  defp part_source(:core), do: gettext("inherited: core’s default")

  defp default_layout_label(nil), do: gettext("default")
  defp default_layout_label(group), do: gettext("default (%{group})", group: group)

  # The layouts listed, and the email's own when it is not among them (one
  # outside this editor's namespace, kept as it is).
  defp layout_options(layouts, current) do
    groups = Enum.map(layouts, & &1.group)
    if is_nil(current) or current in groups, do: groups, else: groups ++ [current]
  end

  defp describe_layout_emails(_assigns, []), do: gettext("No email uses it.")

  defp describe_layout_emails(assigns, emails),
    do: gettext("Used by %{emails}.", emails: describe_emails(assigns, emails))

  # A layout part of a listed layout is shown with its layout; the rest of
  # the names with a leading "_" (a shared part, where allowed) on their own.
  defp shared_part?("_" <> _ = name) do
    case Names.chrome(name) do
      {_kind, group} when is_binary(group) -> false
      _shared_or_other -> true
    end
  end

  defp shared_part?(_name), do: false

  defp own_any?(assigns, group), do: own_kinds(assigns, group) != []

  # The open template when it is an email on disk (not a draft, not a
  # layout part): it has a layout to choose.
  defp selected_email(%{selected: "_" <> _}), do: nil
  defp selected_email(%{draft?: true}), do: nil

  defp selected_email(assigns),
    do: Enum.find(assigns.templates, &(&1.name == assigns.selected))

  # The module emails to list: the catalogue's, then any other email core
  # or a module sends that is a template here.
  defp module_list(assigns) do
    listed =
      for entry <- assigns.module_emails do
        %{
          name: entry.name,
          label: Map.get(entry, :label) || entry.name,
          template?: exists?(%{assigns: assigns}, entry.name),
          file?: MapSet.member?(assigns.disk_names, entry.name)
        }
      end

    names = MapSet.new(listed, & &1.name)

    others =
      for %{name: name} <- assigns.templates,
          not String.starts_with?(name, "_"),
          name in assigns.rules.reserved,
          not MapSet.member?(names, name),
          do: %{name: name, label: name, template?: true, file?: true}

    listed ++ others
  end

  # The layouts of module emails outside the host's namespaces, part by
  # part: its own file (then it is under Layouts), or inherited.
  defp module_layouts(assigns) do
    for group <- module_groups(assigns) do
      parts =
        for kind <- Names.kinds() do
          name = Names.part_name(kind, group)

          %{
            kind: kind,
            name: name,
            file?: MapSet.member?(assigns.disk_names, name),
            overridable?: Names.check(name, assigns.rules) == :ok,
            inherited:
              if(MapSet.member?(assigns.disk_names, Names.part_name(kind, nil)),
                do: :shared,
                else: :core
              )
          }
        end

      %{group: group, parts: parts}
    end
  end

  defp source_label(:db, _own, _root), do: gettext("the Emails module's database template")
  defp source_label({:file, path}, path, _root), do: gettext("this file")

  defp source_label({:file, path}, _own, root),
    do: gettext("the file %{file}", file: Files.relative(root, path))

  defp source_label({:blank_file, path}, _own, root),
    do: gettext("an empty file (%{file}): the part is left out", file: Files.relative(root, path))

  defp source_label(:default, _own, _root), do: gettext("built-in text")
  defp source_label(nil, _own, _root), do: gettext("none")

  defp body_from(:html), do: part_title(:html)
  defp body_from(:markdown), do: part_title(:markdown)
  defp body_from(:text), do: part_title(:text)

  defp confirm_variables_message(%{kind: :email}, names) do
    gettext(
      "%{names} belongs to the header, footer and layout, not to this email: in its body it stays as typed. Save anyway?",
      names: Enum.map_join(names, ", ", &"{{#{&1}}}")
    )
  end

  defp confirm_variables_message(_context, names) do
    gettext(
      "%{names} is not a variable of headers, footers and layouts — an email's, or the page layout's: here it stays as typed. Save anyway?",
      names: Enum.map_join(names, ", ", &"{{#{&1}}}")
    )
  end

  defp part_hint(:label), do: gettext("The caption in lists. Never sent.")
  defp part_hint(:subject), do: gettext("One line.")
  defp part_hint(:text), do: gettext("The plain-text body.")
  defp part_hint(:markdown), do: gettext("Optional, an alternative to HTML.")
  defp part_hint(:html), do: gettext("Optional.")

  # The preview frame's policy: no script, no frame, no connection, no font
  # or stylesheet from outside; inline styles (every email has them) and
  # images inline or from the host's own origins (its logo).
  defp preview_csp(origins) do
    images = Enum.join(["data:" | origins], " ")
    "default-src 'none'; img-src #{images}; style-src 'unsafe-inline'"
  end

  @doctype ~r/\A\s*+<!doctype\b[^<>]*+>/i

  # The policy as the document's first element, so Firefox and Safari keep
  # an edited template's remote image (a tracking pixel) out as well: a
  # `<meta>` before anything else lands in the document's head. After a
  # doctype, not before it: the document keeps its rendering mode.
  defp with_policy(html, csp) do
    meta = ~s(<meta http-equiv="Content-Security-Policy" content="#{csp}">)

    case Regex.run(@doctype, html, return: :index) do
      [{0, length}] ->
        binary_part(html, 0, length) <>
          meta <> binary_part(html, length, byte_size(html) - length)

      nil ->
        meta <> html
    end
  end

  defp notice_class(:info), do: "alert alert-success"
  defp notice_class(:warning), do: "alert alert-warning"
  defp notice_class(:error), do: "alert alert-error"
end
