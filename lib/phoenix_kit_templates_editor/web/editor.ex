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
    * `:locales` — the languages of the switcher, in order; anything but a list of
      non-empty strings is cleaned the way `:name_prefixes` is. A last entry, *Default*, edits
      the locale-less files (`text.txt`), used for any language without its
      own file.
    * `:preview` — `{module, function}` or a 2-arity function called as
      `preview(name, locale)` (`locale` is `nil` for the Default entry, and
      `name` may be a layout part such as `_header-x`). It returns
      `{subject, html}` or `{subject, html, text}` — each a string or `nil`
      — or `{:error, reason}`. A letter's preview is one view, its HTML (its
      text when the host gives no HTML). For a header, footer or layout with
      a text version the preview has two tabs, *HTML* and *Text*, and the
      template opens on HTML (on Text when its HTML is `nil`); the text is
      shown as plain text. The HTML is
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
      form of a header, footer or layout (a letter's body is one Leaf editor,
      and its text version is derived on a save: `to_text` is what makes it,
      `PhoenixKitTemplatesEditor.Converters.to_text/2` otherwise); without
      them, and read-only, there are none.
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
    * `:open` — the template to open on the first render, taken once (the
      page's `?template=`); only a name the editor shows is opened, else
      the first message of the list. Default `nil`.
    * `:patch_path` — the page's path: with it, the editor keeps the open
      template in the address (`?template=`) by patching the LiveView to it,
      replacing the history entry. Default `nil`: the address is left alone.
    * `:block_placeholders` — variables the host fills with a block of their
      own (a list): the break a letter's body writes next to one is left out
      (`PhoenixKitTemplatesEditor.Body.from_editor/2`). Default `[]`.
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
    * `:list_actions` — a slot drawn at the top right of the list, beside its
      first heading: the page's own actions (a menu), so they take no row of
      their own
    * `:show_reload` — `false` where the host puts the Reload action elsewhere
      (it sends the editor `reload` itself). Default `true`.
    * `:email_fallback` — `false` for a host that sends an email only in
      its own languages, never from its locale-less files: an email has no
      Default entry then. Locale-less parts an email still has are shown on
      a Default entry, read-only with a note that they are not used, and a button to delete
      them (after a confirmation; `layout.txt` and a host's own files stay).
      Headers, footers and layouts (a leading `_`) keep their Default entry,
      which is used. Default `true`.

  ## What it does

    * Lists the visible templates, captioned with their `label` part (in the
      page's language when it has one, else the first of `:locales` that
      has one, else the key; the open template's heading is the same): the
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
    * Edits a letter's `label` and `subject` in fields and its body in one Leaf
      editor (`PhoenixKitTemplatesEditor.Web.Letter`): the Markdown file is
      the body and the text file is derived from it on a save; a hand-written
      HTML file keeps a code field. A header, footer or layout has a field
      per part. The `label`, `subject`, `text`, `markdown` and `html` parts
      are edited per language. Saving writes the parts that changed; a part saved empty
      has its file deleted, so the message falls back to the next file in
      line — and a template left with no files loses its directory, staying
      open as an unsaved one. Line breaks are stored as `\\n`. A save that
      is partly refused (one part too large, say) names the parts it saved
      and the ones it did not, and what was typed into those stays in the
      form to be fixed and saved again. Each language is saved on its own:
      switching to another language or template, or a reload, asks first
      when a letter has something unsaved (body, label, subject or HTML) and
      drops it on a «Discard»; a header, footer or layout drops its unsaved
      changes without asking.
    * A part is written only when the user changed it from what the form
      was given (on opening the template or language, or after a save): a part
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
      client sends along since LiveView 1.0 (this package requires 1.1).
    * The host's callbacks run in the LiveView's process. `preview` runs in
      a task with a deadline (`:preview_timeout`), so a slow one costs the
      page at most that long; the rest (`after_write`, `after_change`,
      `authorize`, `journal`, `test_send`, the converters and the variable
      callbacks) hold the page while they run: keep them fast.
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

  alias Phoenix.LiveView.JS

  # PhoenixKit's components, by name: the editor's own private functions
  # (`select/2`, `tabs/2`, `preview/…`) must not meet a blanket import.
  import PhoenixKitWeb.Components.Core.Accordion, only: [accordion: 1]
  import PhoenixKitWeb.Components.Core.Badge, only: [status_badge: 1]
  import PhoenixKitWeb.Components.Core.Button, only: [button: 1]
  import PhoenixKitWeb.Components.Core.Checkbox, only: [checkbox: 1]
  import PhoenixKitWeb.Components.Core.EmptyState, only: [empty_state: 1]
  import PhoenixKitWeb.Components.Core.FormSection, only: [form_section: 1]
  import PhoenixKitWeb.Components.Core.Icon, only: [icon: 1]
  import PhoenixKitWeb.Components.Core.Input, only: [input: 1]
  import PhoenixKitWeb.Components.Core.Modal, only: [modal: 1]
  import PhoenixKitTemplatesEditor.Web.Editor.LayoutsPanel, only: [layouts_panel: 1]
  import PhoenixKitTemplatesEditor.Web.Editor.ModuleEmails
  import PhoenixKitTemplatesEditor.Web.Editor.PanelHelpers
  import PhoenixKitTemplatesEditor.Web.Editor.PreviewPane
  import PhoenixKitTemplatesEditor.Web.Editor.VariablesPanel
  alias PhoenixKitTemplatesEditor.Web.Editor.{Conflict, LayoutActions, Save}

  import PhoenixKitWeb.Components.Core.PopoverPanel,
    only: [popover_panel: 1, toggle_popover: 1, hide_popover: 2]

  import PhoenixKitWeb.Components.Core.Select, only: [select: 1]
  import PhoenixKitWeb.Components.Core.Textarea, only: [textarea: 1]

  require Logger

  alias PhoenixKit.Email.Layout
  alias PhoenixKit.Templates
  alias PhoenixKit.Templates.Overrides
  alias PhoenixKit.Utils.RecipientLocale
  alias PhoenixKitTemplatesEditor.Body
  alias PhoenixKitTemplatesEditor.Bounded
  alias PhoenixKitTemplatesEditor.Converters
  alias PhoenixKitTemplatesEditor.Files
  alias PhoenixKitTemplatesEditor.Languages
  alias PhoenixKitTemplatesEditor.Layouts
  alias PhoenixKitTemplatesEditor.Names
  alias PhoenixKitTemplatesEditor.Overriding
  alias PhoenixKitTemplatesEditor.Preview
  alias PhoenixKitTemplatesEditor.Sources
  alias PhoenixKitTemplatesEditor.Variables
  alias PhoenixKitTemplatesEditor.Web.Letter
  alias PhoenixKitWeb.Components.LanguageSwitcher

  @parts [:label, :subject, :text, :markdown, :html]

  @part_rows %{text: 10, markdown: 6, html: 10}

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
       # What a phone shows: the list (`:list`) or the open template
       # (`:detail`). From `lg` up both are always shown.
       pane: :list,
       # The template the page's address asks for (`?template=`), taken once,
       # and the page's own path: with it the open template is kept in the
       # address, so a reload returns to it.
       open: nil,
       patch_path: nil,
       opened?: false,
       show_reload: true,
       list_actions: [],
       draft?: false,
       locale: nil,
       contents: %{},
       baseline: %{},
       # The form's unsaved values, drawn instead of the files' until the
       # template, language or files change (`load_contents/1`), and a counter
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
       conflict: nil,
       # A letter's body in Leaf (`Web.Letter`): the open document, nil for
       # anything but a letter; the mode the writer chose; a switch of
       # language or template waiting for "discard"; the text version's dialog.
       body: nil,
       focused_body: nil,
       pending_body_action: nil,
       body_mode: :visual,
       body_rev: 0,
       confirm_switch: nil,
       form_dirty?: false,
       block_placeholders: [],
       text_version?: false
     )}
  end

  @impl true
  # A message of the Leaf editor (`notify:`). It only tells what the editor
  # holds; nothing is written until the Save event.
  def update(
        %{leaf: {:leaf_focus, %{editor_id: doc}}},
        %{assigns: %{body: %{doc: doc}}} = socket
      ),
      do: {:ok, assign(socket, focused_body: doc)}

  def update(
        %{leaf: {:leaf_flushed, %{editor_id: doc, ref: ref}}},
        %{assigns: %{body: %{doc: doc}, pending_body_action: {doc, ref, event, params}}} = socket
      ) do
    # Leaf delivers the matching change (including its dirty flag) before the acknowledgement.
    {:noreply, socket} = dispatch_event(event, params, assign(socket, pending_body_action: nil))
    {:ok, socket}
  end

  def update(%{leaf: message}, socket), do: {:ok, Letter.receive(socket, message)}

  def update(assigns, socket) do
    previous_files = files_of(socket, socket.assigns.selected)
    socket = socket |> assign(assigns) |> sanitize_options() |> assign_layout_values()
    languages = Languages.languages(socket.assigns.locales, socket.assigns.base_language)
    socket = assign(socket, module_language_items: languages)

    socket =
      if editable?(socket.assigns), do: socket, else: no_confirmations(socket)

    socket = socket |> load_templates() |> settle_draft() |> keep_selection()

    if nothing_open?(socket),
      do: {:ok, open_initial(socket)},
      else:
        {:ok, socket |> assign(opened?: true) |> refresh_preview(previous_files) |> described()}
  end

  # The host's word about the open template (what its variables are, who
  # sends it) may come with a later render than the one that opened it.
  defp described(%{assigns: %{selected: nil}} = socket), do: socket
  defp described(socket), do: socket |> assign_var_context() |> assign_sources()

  defp nothing_open?(%{assigns: %{selected: nil, module_selected: nil}}), do: true
  defp nothing_open?(_socket), do: false

  # An empty pane beside the list reads as a failure: with nothing chosen the
  # template the address names is opened — once, on the first render — else
  # the first message of the list. A phone still starts from the list unless
  # the address names a template.
  #
  # Not on the disconnected render: the page is drawn again once the socket
  # connects, and the host's preview, the sources lookup and the variables
  # check would run twice for the same document.
  defp open_initial(socket) do
    if connected?(socket), do: open_initial_connected(socket), else: socket
  end

  defp open_initial_connected(socket) do
    wanted = if socket.assigns.opened?, do: nil, else: socket.assigns.open
    socket = assign(socket, opened?: true)

    if is_binary(wanted) and visible?(socket, wanted),
      do: select(socket, wanted),
      else: open_first(socket)
  end

  defp open_first(socket) do
    case first_message(socket.assigns) do
      nil -> socket
      %{name: name} -> socket |> select(name) |> assign(pane: :list)
    end
  end

  defp first_message(assigns), do: List.first(messages(assigns))

  defp messages(assigns) do
    Enum.reject(
      assigns.templates,
      &(String.starts_with?(&1.name, "_") or module_name?(assigns, &1.name))
    )
  end

  # The open template in the page's address (replacing the entry: the list
  # is not a history to walk back through).
  defp patch_address(%{assigns: %{patch_path: path}} = socket) when is_binary(path) do
    query =
      case socket.assigns do
        %{selected: name, pane: :detail} when is_binary(name) ->
          "?" <> URI.encode_query(%{"template" => name})

        _other ->
          ""
      end

    push_patch(socket, to: path <> query, replace: true)
  end

  defp patch_address(socket), do: socket

  # What changes the open document, with something unsaved in a letter (its
  # body in Leaf, its label, subject or HTML in the form): asked first, in a dialog,
  # before it is thrown away. Reload is one of them: it reads the files again.
  @document_events ~w(select_module create create_layout override_default override_db override_layout reload)

  defguardp unsaved?(assigns)
            when (is_map(assigns.body) and assigns.body.dirty? == true) or
                   assigns.form_dirty? == true

  @flush_events @document_events ++ ~w(save confirm_save select locale set_layout)

  @impl true
  def handle_event(event, params, %{assigns: %{body: %{doc: doc}, focused_body: doc}} = socket)
      when event in @flush_events do
    ref = System.unique_integer([:positive]) |> Integer.to_string()
    send_update(Leaf, id: doc, action: :flush, ref: ref)
    {:noreply, assign(socket, pending_body_action: {doc, ref, event, params})}
  end

  def handle_event(event, params, socket), do: dispatch_event(event, params, socket)

  defp dispatch_event(
         "select",
         %{"name" => name},
         %{assigns: %{selected: selected} = assigns} = socket
       )
       when name != selected and unsaved?(assigns),
       do: {:noreply, assign(socket, confirm_switch: {"select", %{"name" => name}})}

  defp dispatch_event(
         "locale",
         %{"language" => language},
         %{assigns: %{locale: locale} = assigns} = socket
       )
       when language != locale and not (language == "" and is_nil(locale)) and unsaved?(assigns),
       do: {:noreply, assign(socket, confirm_switch: {"locale", %{"language" => language}})}

  defp dispatch_event(event, params, %{assigns: assigns} = socket)
       when event in @document_events and unsaved?(assigns),
       do: {:noreply, assign(socket, confirm_switch: {event, params})}

  # What Save would write is what the form shows: after «Discard» the open
  # document is drawn from its files again whenever the event that follows
  # did not open another one (a refused «create», a template gone meanwhile).
  defp dispatch_event(
         "confirm_switch",
         _params,
         %{assigns: %{confirm_switch: {event, params}}} = socket
       ) do
    %{selected: selected, locale: locale, body_rev: rev} = socket.assigns
    socket = socket |> assign(confirm_switch: nil, form_dirty?: false) |> discard_body()

    {:noreply, socket} = dispatch_event(event, params, socket)
    {:noreply, redraw_unless_moved(socket, {selected, locale, rev})}
  end

  defp dispatch_event("confirm_switch", _params, socket), do: {:noreply, socket}

  defp dispatch_event("cancel_switch", _params, socket),
    do: {:noreply, assign(socket, confirm_switch: nil)}

  # A variable of the panel into the letter's body, at the caret of Leaf.
  defp dispatch_event("insert_variable", %{"name" => name}, socket) when is_binary(name) do
    row = Enum.find(panel_rows(socket.assigns), &(&1.name == name))

    if row && socket.assigns.body && form_writable?(socket) do
      send_update(Leaf,
        id: socket.assigns.body.doc,
        action: :insert_markdown,
        text: placeholder(row)
      )
    end

    {:noreply, socket}
  end

  # What the writer typed in a letter's label, subject or hand-written HTML,
  # only to know whether leaving it asks first; nothing is written.
  defp dispatch_event("form_changed", %{"parts" => parts}, socket) when is_map(parts) do
    baseline = socket.assigns.baseline

    dirty? =
      Letter.letter?(socket.assigns) and
        Enum.any?(~w(label subject html)a, fn part ->
          value = parts[Atom.to_string(part)]

          is_binary(value) and String.valid?(value) and
            not Save.unchanged?(
              part,
              value |> Save.normalize_newlines() |> Save.one_line(part),
              Map.get(baseline, part, "")
            )
        end)

    {:noreply, assign(socket, form_dirty?: dirty?)}
  end

  defp dispatch_event("form_changed", _params, socket), do: {:noreply, socket}

  defp dispatch_event("text_version", _params, socket),
    do: {:noreply, assign(socket, text_version?: text_version(socket.assigns) != nil)}

  defp dispatch_event("close_text_version", _params, socket),
    do: {:noreply, assign(socket, text_version?: false)}

  # The open template or language clicked again keeps the form (unsaved values
  # included) and only clears what is transient: a notice, a pending delete.
  defp dispatch_event("select", %{"name" => name}, %{assigns: %{selected: name}} = socket),
    do: {:noreply, socket |> assign(pane: :detail) |> clear_transient() |> patch_address()}

  defp dispatch_event("select", %{"name" => name}, socket) do
    if visible?(socket, name) do
      {:noreply, socket |> assign(notice: nil, draft?: false) |> select(name) |> patch_address()}
    else
      {:noreply, socket}
    end
  end

  # The phone's way back to the list: the open template, and what is typed
  # in it, stay.
  defp dispatch_event("back", _params, socket),
    do: {:noreply, socket |> assign(pane: :list) |> patch_address()}

  # From the language switcher (`phx-value-language`); the files without a
  # language are its entry with the empty code.
  defp dispatch_event("locale", %{"language" => locale}, socket) do
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
  defp dispatch_event("save", %{"action" => action, "parts" => parts}, socket)
       when is_map_key(@conversions, action) and is_map(parts) do
    conversion = Map.fetch!(@conversions, action)

    {:noreply,
     permitted(socket, :convert, fn socket ->
       if form_writable?(socket) and not Letter.letter?(socket.assigns) and
            converter(socket.assigns, conversion) != nil,
          do: convert(socket, conversion, parts),
          else: socket
     end)}
  end

  # A variable button of the panel without the module's JS hook: the
  # variable goes at the end of the body, in the form only.
  defp dispatch_event("save", %{"action" => "insert:" <> variable, "parts" => parts}, socket)
       when is_map(parts) do
    if form_writable?(socket) and not Letter.letter?(socket.assigns),
      do: {:noreply, insert_variable(socket, variable, parts)},
      else: {:noreply, socket}
  end

  # A submit that names no button, or names Save, saves.
  defp dispatch_event("save", %{"parts" => parts} = params, socket) when is_map(parts) do
    if Map.get(params, "action", "save") == "save" do
      {:noreply,
       permitted(socket, :save, fn socket ->
         if form_writable?(socket), do: save(socket, parts), else: socket
       end)}
    else
      {:noreply, socket}
    end
  end

  defp dispatch_event("confirm_save", _params, socket) do
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

  defp dispatch_event("cancel_save", _params, socket),
    do: {:noreply, assign(socket, confirm_variables: nil)}

  # The files again from disk, the cache dropped: after a hand edit, a git
  # pull or another user's save. Dropping the cache costs the whole VM a
  # collection per entry, so it is a writer's action, and
  # once in a few seconds; where nothing is written, nothing changes on disk
  # but by a deploy (or the watcher reads it).
  defp dispatch_event("reload", _params, socket),
    do: {:noreply, permitted(socket, :reload, &reload_throttled/1)}

  # An email core or a module sends: opened in the editor once it is a
  # template here, else shown read only with its built-in text.
  defp dispatch_event("select_module", %{"name" => name}, socket) when is_binary(name) do
    cond do
      module_email(socket.assigns, name) == nil ->
        {:noreply, socket}

      exists?(socket, name) ->
        {:noreply, socket |> assign(notice: nil) |> select(name) |> patch_address()}

      true ->
        {:noreply, socket |> assign(notice: nil) |> open_module(name) |> patch_address()}
    end
  end

  defp dispatch_event("module_locale", %{"language" => locale}, socket) do
    if socket.assigns.module_selected && locale in socket.assigns.locales,
      do: {:noreply, socket |> assign(module_locale: locale) |> load_module_view()},
      else: {:noreply, socket}
  end

  defp dispatch_event("override_default", %{"name" => name}, socket) when is_binary(name),
    do: {:noreply, permitted(socket, :create, &override(&1, name, :default))}

  defp dispatch_event("override_db", %{"name" => name}, socket) when is_binary(name),
    do: {:noreply, permitted(socket, :create, &override(&1, name, :db))}

  defp dispatch_event("override_layout", %{"name" => name}, socket) when is_binary(name),
    do: {:noreply, permitted(socket, :create, &override(&1, name, :layout))}

  # Not a change: works read only too. The host's callback checks who asks.
  defp dispatch_event("test_send", _params, socket), do: {:noreply, test_send(socket)}

  defp dispatch_event("preview_tab", %{"tab" => "html"}, socket),
    do: {:noreply, assign(socket, preview_tab: :html)}

  defp dispatch_event("preview_tab", %{"tab" => "text"}, socket),
    do: {:noreply, assign(socket, preview_tab: :text)}

  defp dispatch_event("create", %{"create" => %{"name" => name} = params}, socket)
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

  defp dispatch_event("delete", _params, socket) do
    {:noreply,
     socket
     |> assign(notice: nil)
     |> permitted(:delete, fn socket ->
       assign(socket, confirm_delete?: writable?(socket, socket.assigns.selected))
     end)}
  end

  defp dispatch_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, confirm_delete?: false)}
  end

  defp dispatch_event("confirm_delete", _params, socket) do
    {:noreply,
     permitted(socket, :delete, fn socket ->
       if socket.assigns.confirm_delete? and writable?(socket, socket.assigns.selected),
         do: delete(socket),
         else: assign(socket, confirm_delete?: false)
     end)}
  end

  defp dispatch_event("delete_fallback", _params, socket) do
    {:noreply,
     socket
     |> assign(notice: nil)
     |> permitted(:delete, fn socket ->
       assign(socket, confirm_fallback_delete?: fallback_deletable?(socket))
     end)}
  end

  defp dispatch_event("cancel_delete_fallback", _params, socket) do
    {:noreply, assign(socket, confirm_fallback_delete?: false)}
  end

  defp dispatch_event("confirm_delete_fallback", _params, socket) do
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
  defp dispatch_event("create_change", %{"create" => %{} = params}, socket),
    do: {:noreply, assign_create_form(socket, params)}

  defp dispatch_event("set_layout", %{"email_layout" => %{"group" => group}}, socket)
       when is_binary(group) do
    {:noreply,
     permitted(socket, :save, fn socket ->
       if email_layout_writable?(socket),
         do: LayoutActions.set_layout(socket, group),
         else: socket
     end)}
  end

  defp dispatch_event(
         "create_layout",
         %{"layout_create" => %{"name" => name, "copy_from" => from}},
         socket
       )
       when is_binary(name) and is_binary(from) do
    {:noreply,
     permitted(socket, :create, &LayoutActions.create_layout(&1, String.trim(name), from))}
  end

  defp dispatch_event("delete_layout", %{"group" => group}, socket) when is_binary(group) do
    {:noreply,
     socket
     |> assign(notice: nil, confirm_layout_delete: nil)
     |> permitted(:delete, &LayoutActions.request_layout_delete(&1, group))}
  end

  defp dispatch_event("cancel_delete_layout", _params, socket),
    do: {:noreply, assign(socket, confirm_layout_delete: nil)}

  defp dispatch_event("confirm_delete_layout", _params, socket) do
    {:noreply,
     permitted(socket, :delete, fn socket ->
       case socket.assigns.confirm_layout_delete do
         nil -> socket
         group -> LayoutActions.delete_layout(socket, group)
       end
     end)}
  end

  defp dispatch_event(_event, _params, socket), do: {:noreply, socket}

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
    |> assign(selected: name, module_selected: nil, module_view: nil, pane: :detail)
    |> no_confirmations()
    |> assign(locale: initial_locale(socket, name))
    |> load_contents()
    |> preview()
    |> open_preview()
  end

  # A template opens on its HTML preview, or on its text version when it
  # has no HTML; switching language keeps the preview tab.
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
  defp save(socket, form_params, opts \\ []) do
    case letter_params(socket, form_params) do
      {:ok, params} ->
        save_params(socket, form_params, params, opts)

      {:error, message} ->
        socket |> notice(:error, not_saved(message)) |> keep_form(form_params)
    end
  end

  # A letter has no text, Markdown or HTML field of its own to post: whatever
  # arrives under those names is not read. Its body is what Leaf holds —
  # when the writer changed it — as Markdown, and the text derived from that;
  # a hand-written HTML file keeps its field.
  defp letter_params(socket, params) do
    if Letter.letter?(socket.assigns) do
      keys = ["label", "subject"] ++ if(socket.assigns.contents[:html], do: ["html"], else: [])
      letter_body(socket, Map.take(params, keys))
    else
      {:ok, params}
    end
  end

  defp letter_body(%{assigns: %{body: %{dirty?: true, markdown: markdown}}} = socket, params) do
    if byte_size(markdown) > Overrides.max_bytes() do
      {:error,
       gettext("Body: %{reason}",
         reason: gettext("larger than %{size} KiB", size: div(Overrides.max_bytes(), 1024))
       )}
    else
      body_changes(socket, markdown, params)
    end
  end

  defp letter_body(_socket, params), do: {:ok, params}

  # The Markdown that is stored leaves the line next to a block placeholder
  # as Leaf has it (the send puts the block there); the text is made from the
  # same body with every line break marked, so it keeps the line.
  defp body_changes(socket, markdown, params) do
    baseline = socket.assigns.baseline

    stored =
      markdown
      |> Body.from_editor(socket.assigns.block_placeholders)
      |> Save.normalize_newlines()
      |> keep_final_newline(baseline[:markdown])

    source = markdown |> Body.from_editor() |> Save.normalize_newlines()

    with {:ok, text} <- derive_text(socket, source) do
      {:ok,
       params
       |> Map.put("markdown", stored)
       |> Map.put("text", keep_final_newline(text, baseline[:text]))}
    end
  end

  # The file's own final newline stays: an edit changes the text, not that.
  defp keep_final_newline("", _given), do: ""

  defp keep_final_newline(value, given) when is_binary(given) do
    if String.ends_with?(given, "\n") and not String.ends_with?(value, "\n"),
      do: value <> "\n",
      else: value
  end

  defp keep_final_newline(value, _none), do: value

  # The text version of a body, by the host's converter, else this module's.
  defp derive_text(_socket, markdown) when markdown in ["", "\n"], do: {:ok, ""}

  # Room left on purpose (`Body.room?/1`) stays in the text version: each
  # stretch between two runs of blank lines is converted on its own.
  defp derive_text(socket, markdown) do
    callback = converter(socket.assigns, :to_text) || (&Converters.to_text/2)

    case Bounded.run(fn -> convert_body(callback, markdown) end) do
      {:ok, result} -> result
      {:error, :timeout} -> {:error, describe(:timeout)}
    end
  end

  defp convert_body(callback, markdown) do
    if Body.room?(markdown) do
      with {:ok, text} <- Body.keeping_room(markdown, &derive_stretch(callback, &1)),
           do: {:ok, keep_end(text, markdown)}
    else
      derive_stretch(callback, markdown)
    end
  end

  defp keep_end(text, markdown),
    do: if(String.ends_with?(markdown, "\n"), do: text <> "\n", else: text)

  defp derive_stretch(_callback, markdown) when markdown in ["", "\n"], do: {:ok, ""}

  defp derive_stretch(callback, markdown) do
    args = [:markdown, markdown]

    case safely({"to_text", callback, args}, fn ->
           callback |> call(args) |> conversion_result()
         end) do
      {:ok, text} ->
        {:ok, Save.normalize_newlines(text)}

      {:error, reason} ->
        {:error, gettext("the text version could not be made: %{reason}", reason: reason)}
    end
  end

  defp save_params(socket, form_params, params, opts) do
    %{contents: contents, baseline: baseline} = socket.assigns

    changes = Save.changes(params, contents, baseline, @parts)
    findings = check_variables(socket.assigns.var_context, changes)

    cond do
      (conflicts = Conflict.conflicts(socket, changes)) != [] ->
        socket |> assign(conflict: conflicts, notice: nil) |> keep_form(params)

      message = Save.subject_refusal(changes) ->
        socket |> notice(:error, message) |> keep_form(params)

      message = directory_refusal(socket, socket.assigns.selected) ->
        socket |> notice(:error, not_saved(message)) |> keep_form(params)

      message = limit_refusal(socket, new_templates(socket), written_bytes(changes, contents)) ->
        socket |> notice(:error, not_saved(message)) |> keep_form(params)

      findings.raw != [] ->
        socket |> notice(:error, raw_refusal(socket, findings.raw)) |> keep_form(params)

      findings.forbidden != [] and opts[:confirmed] != true ->
        socket
        |> assign(
          confirm_variables: %{parts: form_params, names: findings.forbidden},
          notice: nil
        )
        |> keep_form(params)

      true ->
        write_changes(socket, changes, params, findings.unknown)
    end
  end

  defp write_changes(socket, changes, params, unknown) do
    %{selected: name, locale: locale, preview_result: previous_preview} = socket.assigns

    results = Save.write_in_order(socket, changes)

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
    |> retain_body(errors, params)
    |> assign(form_values: refused_values(errors, params))
    |> preview()
    |> open_first_preview(previous_preview)
  end

  # A draft's first save gives it its first preview, opened like a
  # selected template's.
  defp open_first_preview(socket, :unsaved), do: open_preview(socket)
  defp open_first_preview(socket, _previous), do: socket

  # A body part a save refused is still typed into the form: Leaf is opened with
  # it again, and it stays unsaved.
  defp retain_body(socket, errors, params) do
    refused? = Enum.any?(errors, fn {part, _reason} -> part in [:markdown, :text] end)

    if refused? and socket.assigns.body != nil and is_binary(params["markdown"]),
      do: Letter.open(socket, Body.to_editor(params["markdown"])),
      else: socket
  end

  defp redraw_unless_moved(
         %{assigns: %{selected: selected, locale: locale, body_rev: rev}} = socket,
         {selected, locale, rev}
       )
       when is_binary(selected),
       do: socket |> load_contents() |> preview()

  defp redraw_unless_moved(socket, _before), do: socket

  defp discard_body(%{assigns: %{body: %{} = body}} = socket),
    do: assign(socket, body: %{body | dirty?: false, markdown: nil, retained: nil})

  defp discard_body(socket), do: socket

  # The text a recipient's mail program shows: the host's preview of it, else
  # the text file.
  defp text_version(assigns) do
    case assigns.preview_result do
      {:ok, _subject, _html, text} when is_binary(text) and text != "" -> text
      _other -> file_text(assigns.contents[:text])
    end
  end

  defp file_text(%{content: content}) when content != "", do: content
  defp file_text(_none), do: nil

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
          do: {part, Save.normalize_newlines(value)}

    assign(socket, form_values: values)
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
          do: {part, Save.normalize_newlines(value)}

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
        do: {part, Save.normalize_newlines(value)}
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
          do: {part, Save.normalize_newlines(value)}

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
      form_values: Map.put(values, target, Save.normalize_newlines(value)),
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
  def directory_refusal(%{assigns: %{root: root}}, name) do
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

  def check_refusal(%{assigns: %{root: root}}, _names) when not is_binary(root), do: nil

  def check_refusal(%{assigns: %{root: root}}, names) do
    case Preview.check_templates(root, names) do
      :ok -> nil
      {:error, message} -> message
    end
  end

  # Why the root may not take `new_templates` more templates and `bytes`
  # more bytes — `nil` within the host's limits.
  def limit_refusal(%{assigns: %{max_templates: nil, max_root_bytes: nil}}, _new, _bytes),
    do: nil

  def limit_refusal(%{assigns: %{root: root} = assigns}, new_templates, bytes) do
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

  # Only growth consumes room. Do not count bytes being replaced again,
  # or credit another part's deletion: saves can succeed only in part.
  defp written_bytes(changes, contents) do
    Enum.reduce(changes, 0, fn {part, change}, sum ->
      sum + change_growth(change, file_content(contents[part]))
    end)
  end

  def change_growth({:write, value}, before) do
    previous = if is_binary(before), do: byte_size(before), else: 0
    max(byte_size(value) - previous, 0)
  end

  def change_growth(:delete, _before), do: 0

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

  def describe_namespaces(socket) do
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

    if result == :ok,
      do: socket |> deselect() |> open_first() |> patch_address(),
      else: keep_selection(socket)
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
      pane: :detail,
      module_selected: name,
      module_locale: socket.assigns.base_language || hd_or_nil(socket.assigns.locales)
    )
    |> load_module_view()
  end

  defp hd_or_nil([first | _]), do: first
  defp hd_or_nil(_none), do: nil

  # What the read-only view of a module's email shows: its built-in text
  # in the open language, where each part comes from, and what may be done.
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
        opts = [max_root_bytes: assigns.max_root_bytes]

        result =
          case source do
            :default ->
              Overriding.from_defaults(root, module_email(assigns, name), assigns.locales, opts)

            :db ->
              Overriding.from_db(root, name, opts)

            :layout ->
              Overriding.from_layout_default(root, name, opts)
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

  defp overridden(socket, _name, _source, {:error, :root_limit}) do
    reason =
      gettext("the templates directory may not grow past %{size} KiB here.",
        size: div(socket.assigns.max_root_bytes, 1024)
      )

    notice(socket, :error, gettext("Not created: %{reason}", reason: reason))
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
  # or the module email shown; in the open language, else the base one.
  defp test_send_target(%{module_selected: name, module_locale: locale})
       when is_binary(name),
       do: {name, locale}

  defp test_send_target(%{selected: "_" <> _}), do: nil
  defp test_send_target(%{selected: nil}), do: nil
  defp test_send_target(%{draft?: true}), do: nil

  defp test_send_target(%{selected: name, locale: locale, base_language: base}),
    do: {name, locale || base}

  # The open email (not a draft, not a layout part) whose layout.txt may be
  # written.
  defp email_layout_writable?(socket) do
    %{selected: name, draft?: draft?} = socket.assigns

    is_binary(name) and not String.starts_with?(name, "_") and not draft? and
      exists?(socket, name) and writable?(socket, name)
  end

  ## State

  def load_templates(socket) do
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
  def keep_selection(%{assigns: %{selected: nil}} = socket), do: socket

  def keep_selection(socket) do
    if visible?(socket, socket.assigns.selected) do
      if socket.assigns.locale in tabs(socket.assigns, socket.assigns.selected),
        do: refresh_contents(socket),
        else: socket |> reset_locale() |> load_contents()
    else
      deselect(socket)
    end
  end

  # A parent re-render calls the host's preview again only when something it
  # depends on changed: the callback or variables, the language, or the files —
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
        confirm_variables: nil,
        confirm_switch: nil,
        text_version?: false
      )

  defp deselect(socket) do
    assign(socket,
      selected: nil,
      draft?: false,
      contents: %{},
      baseline: %{},
      form_values: %{},
      form_dirty?: false,
      preview_result: nil,
      missing: [],
      confirm_delete?: false,
      confirm_fallback_delete?: false,
      confirm_variables: nil,
      var_context: nil,
      hashes: %{},
      conflict: nil,
      body: nil,
      text_version?: false
    )
  end

  # What the form is drawn from. `baseline` is what the form was last given
  # for this template and language (on select, a language switch or a save); a parent
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
      form_dirty?: false,
      # Every field is drawn again: what was typed in one the server's value
      # did not change would otherwise stay on the screen of a form the server
      # holds as clean.
      form_rev: socket.assigns.form_rev + 1,
      hashes: Conflict.fingerprints(socket.assigns, @parts),
      conflict: nil,
      confirm_variables: nil
    )
    |> assign_var_context()
    |> assign_sources()
    |> Letter.open()
  end

  # Where each part of the open email comes from — only for one core
  # sends, in a language (core resolves a recipient's language, never the
  # Default entry itself).
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
  # evaluated in the open language as core's preview does; the host's own,
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
        do: {part, Save.normalize_newlines(content)}
  end

  # A file put on disk by hand may not be UTF-8, which the page cannot carry:
  # such a part is shown as broken and is never written over from here.
  defp file_contents(content, mtime) do
    if String.valid?(content),
      do: %{content: content, mtime: mtime},
      else: unreadable(:invalid_content, mtime)
  end

  defp load_missing(socket) do
    %{root: root, selected: name, locale: locale} = socket.assigns

    # What the template may use is its own kind's: an email's variables in an
    # email, the layout's (`site_url`, `logo_url`, …) in a header, a footer
    # and a page layout — a header is not checked against an email's.
    variables =
      case Variables.kind(name) do
        :email -> email_variables(socket.assigns, name, locale)
        _layout_part -> socket.assigns.layout_values || %{}
      end

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

  def preview(%{assigns: %{preview: nil}} = socket), do: assign(socket, preview_result: nil)

  def preview(socket) do
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
      case module_email(assigns, name) do
        %{layout: layout} when is_binary(layout) ->
          layout

        _none ->
          case Enum.find(assigns.templates, &(&1.name == name)) do
            %{layout: layout} when is_binary(layout) -> layout
            _none -> assigns.layout_group
          end
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
  def notify_written(_socket, []), do: :ok
  def notify_written(%{assigns: %{after_write: nil}}, _paths), do: :ok

  def notify_written(socket, paths) do
    callback = socket.assigns.after_write

    safely({"after_write", callback, [paths]}, fn ->
      case call(callback, [paths]) do
        {:warning, message} when is_binary(message) -> {:warning, message}
        _other -> :ok
      end
    end)
    |> tag_failure("after_write")
  end

  def notify_changed(_socket, nil), do: :ok
  def notify_changed(%{assigns: %{after_change: nil}}, _name), do: :ok

  def notify_changed(socket, name) do
    callback = socket.assigns.after_change

    safely({"after_change", callback, [name]}, fn ->
      call(callback, [name])
      :ok
    end)
    |> tag_failure("after_change")
  end

  # What was changed, for the host's activity log; a failing callback is
  # logged and changes nothing about the change.
  def journal(%{assigns: %{journal: nil}}, _event), do: :ok

  def journal(socket, event) do
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
  def then_notify_changed(:ok, socket, name), do: notify_changed(socket, name)

  def then_notify_changed(written_error, socket, name) do
    notify_changed(socket, name)
    written_error
  end

  def with_notified(notice, :ok), do: notice

  # The files are saved; something the host does after (setting their
  # mode, say) did not quite work out. A warning, not an error.
  def with_notified({:info, message}, {:warning, warning}),
    do: {:warning, gettext("%{message} But: %{warning}", message: message, warning: warning)}

  def with_notified({kind, message}, {:warning, warning}),
    do: {kind, gettext("%{message} But: %{warning}", message: message, warning: warning)}

  def with_notified({_kind, message}, {:error, {role, reason}}),
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

  def notice(socket, kind, message), do: assign(socket, notice: {kind, message})

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
      block_placeholders: non_empty_strings(socket.assigns.block_placeholders),
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

  # The form of the open language may be saved or converted into — not on an
  # email's Default entry nothing reads, which is shown read-only.
  defp form_writable?(socket),
    do: writable?(socket, socket.assigns.selected) and not unused_fallback?(socket.assigns)

  # Locale-less files of the open email that nothing reads, in its Default entry.
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

  # The languages of template `name`, then Default (`nil`) — which an
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

  # The open language is an email's Default nothing reads.
  defp unused_fallback?(%{selected: nil}), do: false

  defp unused_fallback?(assigns),
    do: assigns.locale == nil and not fallback_used?(assigns, assigns.selected)

  # The first language that has a file, so a locale-less shared part opens on
  # its Default entry rather than on an empty first language — but never an
  # unused fallback.
  defp initial_locale(socket, name) do
    files = files_of(socket, name)
    tabs = tabs(socket.assigns, name)
    candidates = if fallback_used?(socket.assigns, name), do: tabs, else: List.delete(tabs, nil)
    Enum.find(candidates, hd(tabs), fn tab -> Enum.any?(files, &(&1.locale == tab)) end)
  end

  defp caption(socket, name, files) do
    labels = for %{part: :label} = file <- files, into: %{}, do: {file.locale, file.path}

    # The page's language first, when the template has a label in it; then
    # the module's languages in their order, then the label without one.
    Enum.find_value(caption_order(socket.assigns.locales), name, fn tab ->
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

  defp caption_order(locales) do
    page_language =
      PhoenixKitTemplatesEditor.Gettext
      |> Gettext.get_locale()
      |> String.split(["-", "_"])
      |> hd()

    Enum.uniq([page_language | locales] ++ [nil])
  end

  defp describe_errors(errors) do
    Enum.map_join(errors, "; ", fn {part, reason} ->
      "#{part_title(part)}: #{describe(reason)}"
    end)
  end

  def describe(:too_large),
    do: gettext("larger than %{size} KiB", size: div(Overrides.max_bytes(), 1024))

  def describe(:timeout), do: gettext("it took too long")
  def describe(:invalid_content), do: gettext("not valid UTF-8 text")
  def describe(:invalid_name), do: gettext("not a valid template name")
  def describe(:invalid_part), do: gettext("not a part this editor writes")
  def describe(:invalid_locale), do: gettext("not a valid language tag")
  def describe(:invalid_root), do: gettext("the template directory does not exist")

  def describe(:unsafe_path),
    do: gettext("the path leads outside the template directory")

  def describe(:enoent), do: gettext("already gone")
  def describe(reason) when is_atom(reason), do: reason |> :file.format_error() |> to_string()
  def describe(reason) when is_binary(reason), do: reason
  def describe(reason), do: inspect(reason)

  # A host's own reason is not a file error: shown as it is, not as POSIX.
  defp describe_host(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp describe_host(reason) when is_binary(reason) do
    if String.valid?(reason), do: reason, else: inspect(reason)
  end

  defp describe_host(reason), do: inspect(reason)

  ## Rendering

  # The open template's heading: its label, else its key.
  defp selected_caption(%{selected: nil}), do: nil

  defp selected_caption(%{selected: name, templates: templates}) do
    case Enum.find(templates, &(&1.name == name)) do
      %{caption: caption} when is_binary(caption) and caption != "" -> caption
      _none -> name
    end
  end

  defp own_paths(%{selected: selected, root: root} = assigns)
       when selected != nil and is_binary(root) do
    Map.new(@parts, fn part ->
      {part, Conflict.part_path(root, selected, part, assigns.locale)}
    end)
  end

  defp own_paths(_assigns), do: %{}

  defp form_shown?(assigns),
    do: assigns.selected != nil and editable?(assigns) and not unused_fallback?(assigns)

  defp detail?(assigns),
    do: assigns.pane == :detail and (assigns.selected != nil or assigns.module_view != nil)

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        messages: messages(assigns),
        module_list: module_list(assigns),
        module_layouts: module_layouts(assigns),
        auth_warning: (assigns.selected || assigns.module_selected) in Names.auth_emails(),
        can_test_send: assigns.test_send != nil and test_send_target(assigns) != nil,
        own_paths: own_paths(assigns),
        shared: Enum.filter(assigns.templates, &shared_part?(&1.name)),
        layout_sources:
          for(%{group: group} <- assigns.layouts, own_any?(assigns, group), do: group),
        email: selected_email(assigns),
        selected_caption: selected_caption(assigns),
        layout_emails:
          Map.new(assigns.layouts, &{&1.group, describe_layout_emails(assigns, &1.emails)}),
        tabs: tabs(assigns, assigns.selected),
        fallback_used: fallback_used?(assigns, assigns.selected),
        fallback_unused: unused_fallback?(assigns),
        parts: @parts,
        can_edit: editable?(assigns),
        form_shown: form_shown?(assigns),
        variable_rows: panel_rows(assigns),
        letter?: Letter.letter?(assigns),
        can_fill_text: converter(assigns, :to_text) != nil and not Letter.letter?(assigns),
        can_render_markdown:
          converter(assigns, :markdown_to_html) != nil and not Letter.letter?(assigns),
        text_version: if(Letter.letter?(assigns), do: text_version(assigns)),
        detail?: detail?(assigns)
      )

    assigns =
      assign(assigns,
        language_items:
          Languages.with_default(assigns.module_language_items, assigns.tabs, gettext("Default"))
      )

    ~H"""
    <div id={@id} class="flex min-w-0 flex-col gap-4">
      <div :if={!is_binary(@root)} role="alert" class="alert alert-error">
        {gettext("No template directory is configured.")}
      </div>
      <div :if={@notice} role="alert" class={notice_class(elem(@notice, 0))}>
        {elem(@notice, 1)}
      </div>

      <%!-- A phone shows one pane at a time: the list, or the open template
           (`pane`); from `lg` up both stand side by side. Grid children carry
           `min-w-0` so a long key can never push into the other pane. --%>
      <div id={"#{@id}-panes"} class="grid min-w-0 gap-6 lg:grid-cols-4">
        <aside
          id={"#{@id}-list"}
          class={[
            "min-w-0 flex-col gap-3 lg:col-span-1",
            if(@detail?, do: "hidden lg:flex", else: "flex")
          ]}
          phx-hook="PhoenixKitTemplatesEditorFolds"
        >
          <.button
            :if={@can_edit and @show_reload}
            id={"#{@id}-reload"}
            type="button"
            variant="ghost"
            size="sm"
            class="self-start"
            phx-click="reload"
            phx-target={@myself}
            title={
              gettext("Read the templates again from disk: after a change by hand or a git pull.")
            }
          >
            <.icon name="hero-arrow-path" class="size-4" />
            {gettext("Reload")}
          </.button>
          <.empty_state :if={@templates == []} title={gettext("No templates yet.")} class="py-4" />

          <%!-- Making something new is the small plus beside the section's
               title, with a panel under it; the sections themselves fold. --%>
          <.template_group
            :if={@messages != [] or @can_edit or @list_actions != []}
            id={"#{@id}-messages"}
            title={gettext("Messages")}
            templates={@messages}
            selected={@selected}
            base_language={@base_language}
            myself={@myself}
          >
            <:actions>
              <div :if={@can_edit} class="relative">
                <.button
                  id={"#{@id}-create-open"}
                  type="button"
                  variant="ghost"
                  size="xs"
                  class="btn-square"
                  title={gettext("New message")}
                  aria-label={gettext("New message")}
                  phx-click={toggle_popover("#{@id}-create-box")}
                >
                  <.icon name="hero-plus" class="size-4" />
                </.button>
                <.popover_panel
                  id={"#{@id}-create-box"}
                  align="start"
                  width_class="sm:w-72"
                  class="p-4 max-sm:!top-20"
                >
                  <div class="flex flex-col gap-2">
                    <span class="text-sm font-semibold">{gettext("New message")}</span>
                    <form
                      id={"#{@id}-create"}
                      phx-submit={
                        JS.push("create", target: @myself) |> hide_popover("#{@id}-create-box")
                      }
                      phx-change="create_change"
                      phx-target={@myself}
                      class="flex flex-col gap-2"
                    >
                      <.input
                        type="text"
                        name="create[name]"
                        aria-label={gettext("Template name")}
                        class="input-sm font-mono"
                        placeholder={gettext("name")}
                        autocomplete="off"
                        value={if(@create_name == "", do: name_start(@rules), else: @create_name)}
                      />
                      <.select
                        name="create[copy_from]"
                        aria-label={gettext("Start from")}
                        class="select-sm"
                        options={
                          [{gettext("Empty"), ""}] ++
                            for(
                              template <- @templates,
                              do: {gettext("Copy of %{name}", name: template.name), template.name}
                            )
                        }
                        value={@create_from || ""}
                      />
                      <fieldset
                        :if={@create_extras != []}
                        id={"#{@id}-create-extras"}
                        class="fieldset min-w-0 text-sm"
                      >
                        <legend class="fieldset-legend">
                          {gettext("Also copy the host’s own files:")}
                        </legend>
                        <input type="hidden" name="create[keep_for]" value={@create_from} />
                        <input type="hidden" name="create[keep][]" value="" />
                        <.checkbox
                          :for={file <- @create_extras}
                          name="create[keep][]"
                          value={file}
                          unchecked_value={nil}
                          checked
                          class="checkbox-xs"
                          wrapper_class="font-mono text-xs break-all"
                        >
                          {file}
                        </.checkbox>
                      </fieldset>
                      <.button type="submit" variant="outline" size="sm">{gettext("Create")}</.button>
                    </form>
                  </div>
                </.popover_panel>
              </div>
              <div :if={@list_actions != []}>{render_slot(@list_actions)}</div>
            </:actions>
          </.template_group>
          <.layouts_panel
            layouts={@layouts}
            id={@id}
            selected={@selected}
            templates={@templates}
            can_edit={@can_edit}
            layout_sources={@layout_sources}
            layout_emails={@layout_emails}
            myself={@myself}
            confirm_layout_delete={@confirm_layout_delete}
            rules={@rules}
          />

          <.module_emails_list
            module_list={@module_list}
            module_layouts={@module_layouts}
            id={@id}
            module_selected={@module_selected}
            myself={@myself}
            selected={@selected}
            can_edit={@can_edit}
          />

          <.template_group
            :if={@shared != []}
            id={"#{@id}-shared"}
            title={gettext("Shared parts")}
            templates={@shared}
            selected={@selected}
            myself={@myself}
          />
        </aside>

        <section
          id={"#{@id}-detail"}
          class={[
            "min-w-0 flex-col gap-4 lg:col-span-3",
            if(@detail?, do: "flex", else: "hidden lg:flex")
          ]}
        >
          <.button
            id={"#{@id}-back"}
            type="button"
            variant="ghost"
            size="sm"
            class="self-start lg:hidden"
            phx-click="back"
            phx-target={@myself}
          >
            <.icon name="hero-arrow-left" class="size-4" />
            {gettext("Back to the list")}
          </.button>

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

          <.module_email
            module_view={@module_view}
            id={@id}
            module_selected={@module_selected}
            can_test_send={@can_test_send}
            myself={@myself}
            can_edit={@can_edit}
            module_language_items={@module_language_items}
            module_locale={@module_locale}
            root={@root}
          />

          <div
            :if={@selected}
            id={"#{@id}-header"}
            class="flex min-w-0 flex-col gap-x-2 gap-y-2 sm:flex-row sm:flex-wrap sm:items-center"
          >
            <div class="min-w-0 sm:flex-1">
              <div class="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1">
                <h3 id={"#{@id}-title"} class="min-w-0 break-words text-lg font-semibold">
                  {@selected_caption}
                </h3>
                <.status_badge
                  :if={@draft?}
                  status="draft"
                  label={gettext("not saved yet")}
                  size={:sm}
                />
              </div>
              <span
                :if={@selected_caption != @selected}
                id={"#{@id}-key"}
                class="block break-all font-mono text-xs opacity-60"
              >
                {@selected}
              </span>
            </div>
            <div class="flex flex-wrap gap-x-2 gap-y-2">
              <.button
                :if={@text_version}
                id={"#{@id}-text-version"}
                type="button"
                variant="ghost"
                size="sm"
                phx-click="text_version"
                phx-target={@myself}
              >
                <.icon name="hero-document-text" class="size-4" />
                {gettext("Text version")}
              </.button>
              <.button
                :if={@can_test_send}
                id={"#{@id}-test-send"}
                type="button"
                variant="outline"
                size="sm"
                phx-click="test_send"
                phx-target={@myself}
              >
                {gettext("Send to me")}
              </.button>
              <.button
                :if={@can_edit}
                id={"#{@id}-delete"}
                type="button"
                variant="outline"
                size="sm"
                class="btn-error"
                phx-click="delete"
                phx-target={@myself}
              >
                {gettext("Delete")}
              </.button>
            </div>
          </div>

          <.sources_box
            :if={@selected && @sources}
            id={"#{@id}-sources"}
            result={@sources}
            own={@own_paths}
            root={@root}
          />

          <.modal show={@confirm_delete?} id={"#{@id}-delete-modal"} on_close="cancel_delete">
            <:title>
              <.icon name="hero-exclamation-triangle" class="size-5 text-warning" />
              {gettext("Delete")}
            </:title>
            <p class="break-words text-sm">
              {gettext("Delete “%{name}” and all its files?", name: @selected)}
            </p>
            <:actions>
              <.button
                id={"#{@id}-delete-cancel"}
                type="button"
                variant="ghost"
                size="sm"
                phx-click="cancel_delete"
                phx-target={@myself}
              >
                {gettext("Cancel")}
              </.button>
              <.button
                id={"#{@id}-delete-confirm"}
                type="button"
                variant="error"
                size="sm"
                phx-click="confirm_delete"
                phx-target={@myself}
              >
                {gettext("Delete")}
              </.button>
            </:actions>
          </.modal>

          <.modal
            :if={@text_version}
            show={@text_version?}
            id={"#{@id}-text-version-modal"}
            on_close="close_text_version"
          >
            <:title>{gettext("Text version")}</:title>
            <p class="mb-2 text-xs opacity-70">
              {gettext("Made from the body when you save; it is not edited by hand.")}
            </p>
            <pre id={"#{@id}-text-version-text"} class={pre_class()}>{@text_version}</pre>
            <:actions>
              <.button
                id={"#{@id}-text-version-close"}
                type="button"
                variant="ghost"
                size="sm"
                phx-click="close_text_version"
                phx-target={@myself}
              >
                {gettext("Close")}
              </.button>
            </:actions>
          </.modal>

          <.modal
            show={@confirm_switch != nil}
            id={"#{@id}-confirm-switch"}
            on_close="cancel_switch"
          >
            <:title>
              <.icon name="hero-exclamation-triangle" class="size-5 text-warning" />
              {gettext("Unsaved changes")}
            </:title>
            <p class="break-words text-sm">
              {gettext("There are changes that are not saved. Leave without saving them?")}
            </p>
            <:actions>
              <.button
                id={"#{@id}-confirm-switch-cancel"}
                type="button"
                variant="ghost"
                size="sm"
                phx-click="cancel_switch"
                phx-target={@myself}
              >
                {gettext("Stay")}
              </.button>
              <.button
                id={"#{@id}-confirm-switch-discard"}
                type="button"
                variant="warning"
                size="sm"
                phx-click="confirm_switch"
                phx-target={@myself}
              >
                {gettext("Discard the changes")}
              </.button>
            </:actions>
          </.modal>

          <%!-- One row: the languages, and beside them the layout the email
               goes out in (its header and footer). The row sits close to the
               form it switches. --%>
          <div
            :if={@selected}
            id={"#{@id}-language-row"}
            class="-mb-3 flex min-w-0 flex-wrap items-center gap-x-4 gap-y-2"
          >
            <LanguageSwitcher.language_switcher
              id={"#{@id}-languages"}
              languages={@language_items}
              current_language={@locale || ""}
              on_click="locale"
              phx_target={@myself}
              variant={:tabs}
              size={:sm}
              display={:auto}
              auto_threshold={5}
              show_flags
              show_primary
              primary_divider
              class="w-full sm:w-auto sm:min-w-0 sm:flex-1"
            />
            <form
              :if={@email && @can_edit}
              id={"#{@id}-email-layout"}
              phx-change="set_layout"
              phx-target={@myself}
              class="flex shrink-0 flex-wrap items-center gap-x-2 gap-y-1"
            >
              <label for={"#{@id}-email-layout-group"} class="text-sm font-semibold">
                {gettext("Layout")}
              </label>
              <.select
                id={"#{@id}-email-layout-group"}
                name="email_layout[group]"
                class="select-sm"
                options={
                  [{default_layout_label(@layout_group), ""}] ++
                    for(group <- layout_options(@layouts, @email.layout), do: {group, group})
                }
                value={@email.layout || ""}
              />
            </form>
            <p :if={@email && !@can_edit} id={"#{@id}-email-layout-current"} class="shrink-0 text-sm">
              <span class="font-semibold">{gettext("Layout")}:</span>
              {@email.layout || default_layout_label(@layout_group)}
            </p>
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
            <.button
              :if={@can_edit && !@confirm_fallback_delete?}
              id={"#{@id}-fallback-delete"}
              type="button"
              variant="outline"
              size="sm"
              class="btn-error"
              phx-click="delete_fallback"
              phx-target={@myself}
            >
              {gettext("Delete")}
            </.button>
          </div>

          <.modal
            show={@fallback_unused && @confirm_fallback_delete?}
            id={"#{@id}-fallback-delete-modal"}
            on_close="cancel_delete_fallback"
          >
            <:title>
              <.icon name="hero-exclamation-triangle" class="size-5 text-warning" />
              {gettext("Delete")}
            </:title>
            <p class="break-words text-sm">
              {gettext("Delete the files without a language of “%{name}”?", name: @selected)}
            </p>
            <:actions>
              <.button
                id={"#{@id}-fallback-delete-cancel"}
                type="button"
                variant="ghost"
                size="sm"
                phx-click="cancel_delete_fallback"
                phx-target={@myself}
              >
                {gettext("Cancel")}
              </.button>
              <.button
                id={"#{@id}-fallback-delete-confirm"}
                type="button"
                variant="error"
                size="sm"
                phx-click="confirm_delete_fallback"
                phx-target={@myself}
              >
                {gettext("Delete")}
              </.button>
            </:actions>
          </.modal>

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
            <div :for={{part, content} <- @conflict} class="w-full min-w-0">
              <span class="font-semibold">{gettext("%{part} on disk now:", part: part_title(part))}</span>
              <pre :if={is_binary(content)} class={pre_class("p-2 text-xs")}>{content}</pre>
              <span :if={is_nil(content)} class="opacity-70">{gettext("no file")}</span>
              <span :if={content == :unreadable} class="opacity-70">
                {gettext("cannot be read here")}
              </span>
            </div>
            <.button
              id={"#{@id}-conflict-reload"}
              type="button"
              variant="outline"
              size="sm"
              phx-click="reload"
              phx-target={@myself}
            >
              {gettext("Reload")}
            </.button>
          </div>

          <.modal
            show={@confirm_variables != nil}
            id={"#{@id}-confirm-variables"}
            on_close="cancel_save"
          >
            <:title>
              <.icon name="hero-exclamation-triangle" class="size-5 text-warning" />
              {gettext("Save anyway")}
            </:title>
            <p :if={@confirm_variables} class="break-words text-sm">
              {confirm_variables_message(@var_context, @confirm_variables.names)}
            </p>
            <:actions>
              <.button
                id={"#{@id}-confirm-variables-cancel"}
                type="button"
                variant="ghost"
                size="sm"
                phx-click="cancel_save"
                phx-target={@myself}
              >
                {gettext("Cancel")}
              </.button>
              <.button
                id={"#{@id}-confirm-variables-save"}
                type="button"
                variant="warning"
                size="sm"
                phx-click="confirm_save"
                phx-target={@myself}
              >
                {gettext("Save anyway")}
              </.button>
            </:actions>
          </.modal>

          <div
            :if={@selected}
            id={"#{@id}-form"}
            phx-hook={if(@form_shown and not @letter?, do: "PhoenixKitTemplatesEditorInsertVariable")}
            class="flex min-w-0 flex-col gap-4"
          >
            <.form_section :if={@form_shown} body_class="px-4 pb-4 pt-2">
              <form
                id={"#{@id}-parts"}
                phx-submit="save"
                phx-change={if(@letter?, do: "form_changed")}
                phx-target={@myself}
                class="flex min-w-0 flex-col gap-3"
              >
                <%!-- A letter: label and subject, then its body in Leaf (the text
                     version is made from it on a save), and the HTML only where a
                     hand-written file already exists. Anything else keeps a field
                     per part. --%>
                <.part_field
                  :for={part <- field_parts(@letter?)}
                  id={"#{@id}-part-#{part}"}
                  part={part}
                  file={@contents[part]}
                  value={@form_values[part]}
                  rev={@form_rev}
                />
                <%= if @letter? do %>
                  <.part_field
                    :for={part <- Letter.unreadable(@contents)}
                    id={"#{@id}-part-#{part}"}
                    part={part}
                    file={@contents[part]}
                    rev={@form_rev}
                  />
                  <Letter.body_field
                    :if={@body}
                    id={"#{@id}-body"}
                    body={@body}
                    mode={@body_mode}
                    notify={{__MODULE__, @id}}
                  />
                  <div :if={@contents[:html]} class="flex min-w-0 flex-col gap-1">
                    <p id={"#{@id}-html-note"} class="text-xs opacity-70">
                      {gettext(
                        "This letter’s HTML is written by hand: Leaf does not edit it, and it is what the recipient sees."
                      )}
                    </p>
                    <.part_field
                      id={"#{@id}-part-html"}
                      part={:html}
                      file={@contents[:html]}
                      value={@form_values[:html]}
                      rev={@form_rev}
                    />
                  </div>
                <% end %>
                <p :if={not @letter?} class="text-xs opacity-70">
                  {gettext("Switching language or template drops unsaved changes.")}
                </p>
                <%!-- Save comes first: the form's default button. The rows are
                     `gap-x-2 gap-y-2`, not `gap-2`: core's stylesheet stretches a
                     button in a `.flex.gap-2` row to the full width on a phone. --%>
                <div class="flex flex-wrap gap-x-2 gap-y-2">
                  <.button type="submit" name="action" value="save" size="sm">
                    {gettext("Save")}
                  </.button>
                  <.button
                    :if={@can_fill_text}
                    id={"#{@id}-to-text"}
                    type="submit"
                    name="action"
                    value="to_text"
                    variant="outline"
                    size="sm"
                    title={
                      gettext(
                        "Put the Markdown, or else the HTML, as plain text in Text. Not saved until you Save."
                      )
                    }
                  >
                    {gettext("Fill text from content")}
                  </.button>
                  <.button
                    :if={@can_render_markdown}
                    id={"#{@id}-md-to-html"}
                    type="submit"
                    name="action"
                    value="md_to_html"
                    variant="outline"
                    size="sm"
                    title={gettext("Put the Markdown, rendered, in HTML. Not saved until you Save.")}
                  >
                    {gettext("Markdown → HTML")}
                  </.button>
                </div>
              </form>
            </.form_section>

            <dl
              :if={@selected && (!@can_edit || @fallback_unused)}
              class="flex min-w-0 flex-col gap-3"
            >
              <div :for={part <- @parts} class="min-w-0">
                <dt class="text-sm font-semibold">{part_title(part)}</dt>
                <dd :if={@contents[part] && @contents[part][:invalid]} class="text-sm text-error">
                  {unreadable_message(@contents[part])}
                </dd>
                <dd :if={@contents[part] && !@contents[part][:invalid]}>
                  <pre class={pre_class()}>{@contents[part].content}</pre>
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
              form={if(@form_shown and not @letter?, do: "#{@id}-parts")}
              leaf={if(@form_shown and @letter? and @body != nil, do: @myself)}
            />
          </div>

          <.accordion :if={@selected && @preview_result} id={"#{@id}-preview"} open>
            <:title>{gettext("Preview")}</:title>
            <:content>
              <.preview_pane
                id={@id}
                result={@preview_result}
                tab={@preview_tab}
                single={@letter?}
                csp={preview_csp(@preview_image_origins)}
                myself={@myself}
              />
            </:content>
          </.accordion>
        </section>
      </div>
    </div>
    """
  end

  # What a new name has to begin with, where the host's rules say so: typed
  # into the field already, so the writer goes on from it instead of reading
  # a hint and typing it over.
  defp name_start(rules), do: List.first(Names.message_prefixes(rules)) || ""

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:templates, :list, required: true)
  attr(:selected, :string, default: nil)
  attr(:base_language, :string, default: nil)
  attr(:myself, :any, required: true)
  slot(:actions)

  defp template_group(assigns) do
    ~H"""
    <div class="relative min-w-0">
      <.accordion id={@id} open title_class="!py-2 !min-h-0">
        <:title>{@title}</:title>
        <:content>
          <ul class={list_class()}>
            <li :for={template <- @templates} class="min-w-0">
              <.button
                variant="ghost"
                type="button"
                phx-click="select"
                phx-value-name={template.name}
                phx-target={@myself}
                class={[list_button_class(), template.name == @selected && "menu-active"]}
              >
                <span class="w-full break-words">{template.caption}</span>
                <span
                  :if={template.caption != template.name}
                  class="w-full break-all font-mono text-xs opacity-60"
                >
                  {template.name}
                </span>
                <span
                  :if={template.incomplete?}
                  id={"#{@id}-incomplete-#{template.name}"}
                  class="flex w-full items-baseline gap-1 text-xs text-warning"
                >
                  <.status_badge status="draft" label="!" size={:xs} class="shrink-0" />
                  <span class="min-w-0 break-words">
                    {gettext("Not offered for sending: no subject or body in %{locale}.",
                      locale: @base_language
                    )}
                  </span>
                </span>
              </.button>
            </li>
          </ul>
        </:content>
      </.accordion>
      <div :if={@actions != []} class={section_actions_class()}>
        {render_slot(@actions)}
      </div>
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
    <div class="flex min-w-0 flex-col gap-1">
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
        rows: Map.get(@part_rows, assigns.part),
        single_line?: assigns.part in [:label, :subject]
      )

    ~H"""
    <div class="flex min-w-0 flex-col gap-1">
      <label for={@id} class="flex flex-wrap items-baseline gap-x-2 text-sm">
        <span class="font-semibold">{part_title(@part)}</span>
        <span :if={@file} class="ml-auto text-xs opacity-60">
          {gettext("changed %{time}", time: Calendar.strftime(@file.mtime, "%Y-%m-%d %H:%M UTC"))}
        </span>
      </label>
      <.input
        :if={@single_line?}
        id={@id}
        type="text"
        name={"parts[#{@part}]"}
        value={Save.single_line(@value)}
        data-form-rev={@rev}
        class="font-mono text-sm"
      />
      <.textarea
        :if={!@single_line?}
        id={@id}
        name={"parts[#{@part}]"}
        value={@value}
        rows={@rows}
        data-form-rev={@rev}
        class="font-mono text-sm"
      />
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

  defp field_parts(true), do: [:label, :subject]
  defp field_parts(false), do: @parts

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
    do: gettext("Used by %{emails}.", emails: LayoutActions.describe_emails(assigns, emails))

  # A layout part of a listed layout is shown with its layout; the rest of
  # the names with a leading "_" (a shared part, where allowed) on their own.
  defp shared_part?("_" <> _ = name) do
    case Names.chrome(name) do
      {_kind, group} when is_binary(group) -> false
      _shared_or_other -> true
    end
  end

  defp shared_part?(_name), do: false

  defp own_any?(assigns, group), do: LayoutActions.own_kinds(assigns, group) != []

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

  defp notice_class(:info), do: "alert alert-success"
  defp notice_class(:warning), do: "alert alert-warning"
  defp notice_class(:error), do: "alert alert-error"
end
