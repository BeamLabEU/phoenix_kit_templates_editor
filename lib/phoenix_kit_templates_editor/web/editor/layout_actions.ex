defmodule PhoenixKitTemplatesEditor.Web.Editor.LayoutActions do
  @moduledoc false
  use Gettext, backend: PhoenixKitTemplatesEditor.Gettext

  import Phoenix.Component, only: [assign: 2]
  alias PhoenixKit.Email.Layout
  alias PhoenixKit.Templates.Overrides
  alias PhoenixKitTemplatesEditor.{Files, Layouts, Names}
  alias PhoenixKitTemplatesEditor.Web.Editor

  ## Layouts

  # The open email's layout: its `layout.txt` written with the group, or
  # deleted for the default. Only a layout the rules allow; the preview is
  # drawn in it at once.
  def set_layout(socket, group) do
    %{root: root, selected: name} = socket.assigns
    template = Enum.find(socket.assigns.templates, &(&1.name == name))
    file? = Enum.any?(template.files, &(&1.part == :layout))

    result =
      cond do
        message = Editor.directory_refusal(socket, name) ->
          {:error, message}

        group == "" and not file? ->
          :unchanged

        group == "" ->
          with :ok <- Overrides.delete(root, name, :layout, nil), do: {:ok, []}

        not layout_allowed?(socket, group) ->
          {:error, :not_a_layout}

        group == template.layout ->
          :unchanged

        message = Editor.limit_refusal(socket, 0, layout_growth(socket, name, group)) ->
          {:error, message}

        true ->
          Overrides.write(root, name, :layout, nil, group)
      end

    socket
    |> layout_set(result, name, group)
    |> Editor.load_templates()
    |> Editor.keep_selection()
    |> Editor.preview()
  end

  defp layout_growth(%{assigns: %{root: root}}, name, group) do
    before =
      case Files.safe_read(root, Path.join([root, name, "layout.txt"])) do
        {:ok, content} -> content
        {:error, _reason} -> nil
      end

    Editor.change_growth({:write, group}, before)
  end

  defp layout_set(socket, :unchanged, _name, _group),
    do: Editor.notice(socket, :info, gettext("No changes."))

  defp layout_set(socket, {:error, :not_a_layout}, _name, group) do
    Editor.notice(
      socket,
      :error,
      gettext("“%{group}” is not one of this editor’s layouts: nothing was changed.",
        group: group
      )
    )
  end

  defp layout_set(socket, {:error, reason}, _name, _group),
    do:
      Editor.notice(
        socket,
        :error,
        gettext("Not saved: %{errors}", errors: Editor.describe(reason))
      )

  defp layout_set(socket, {:ok, paths}, name, group) do
    Editor.journal(socket, %{
      action: :layout_set,
      template: name,
      layout: if(group != "", do: group)
    })

    notified = socket |> Editor.notify_written(paths) |> Editor.then_notify_changed(socket, name)

    message =
      if group == "",
        do: gettext("“%{name}” now has the default layout.", name: name),
        else: gettext("“%{name}” now has the layout “%{group}”.", name: name, group: group)

    assign(socket, notice: Editor.with_notified({:info, message}, notified))
  end

  defp layout_allowed?(socket, group),
    do: Layout.valid_group?(group) and Names.group_allowed?(group, socket.assigns.rules)

  # A new layout: every part of its own an existing layout has, copied
  # under the new name.
  def create_layout(socket, group, from) do
    socket = Editor.load_templates(socket)
    kinds = own_kinds(socket.assigns, from)
    sources = Enum.map(kinds, &Names.part_name(&1, from))

    cond do
      not Layout.valid_group?(group) ->
        Editor.notice(
          socket,
          :error,
          gettext(
            "“%{name}” is not a valid layout name: use lowercase letters, digits and “-”.",
            name: group
          )
        )

      not layout_allowed?(socket, group) or
          not Enum.all?(kinds, &Names.part_allowed?(&1, group, socket.assigns.rules)) ->
        Editor.notice(
          socket,
          :error,
          gettext("“%{name}” is not in this editor’s layouts (%{layouts}).",
            name: group,
            layouts: Editor.describe_namespaces(socket)
          )
        )

      layout_exists?(socket, group) ->
        Editor.notice(socket, :error, gettext("“%{name}” already exists.", name: group))

      kinds == [] ->
        Editor.notice(
          socket,
          :error,
          gettext("There is no layout “%{name}” to copy.", name: from)
        )

      message =
          Editor.check_refusal(socket, sources) || copy_limit(socket, sources) ->
        Editor.notice(socket, :error, gettext("Not copied: %{reason}", reason: message))

      true ->
        copy_layout(socket, from, group, kinds)
    end
  end

  defp copy_limit(socket, sources) do
    bytes =
      Enum.reduce(sources, 0, fn name, sum ->
        sum + Files.template_bytes(socket.assigns.root, name)
      end)

    Editor.limit_refusal(socket, length(sources), bytes)
  end

  defp copy_layout(socket, from, group, kinds) do
    case Layouts.copy(socket.assigns.root, from, group, kinds) do
      {:ok, created} ->
        Editor.journal(socket, %{action: :layout_created, layout: group, from: from})
        written = Editor.notify_written(socket, Enum.flat_map(created, &elem(&1, 1)))
        changed = for {name, _paths} <- created, do: Editor.notify_changed(socket, name)

        notice =
          {:info,
           gettext("Created the layout “%{name}” as a copy of “%{from}”.",
             name: group,
             from: from
           )}

        socket
        |> assign(notice: Editor.with_notified(notice, first_failure([written | changed])))
        |> Editor.load_templates()

      {:error, reason} ->
        Editor.notice(
          socket,
          :error,
          gettext("Not copied: %{reason}", reason: Editor.describe(reason))
        )
    end
  end

  defp layout_exists?(socket, group) do
    Enum.any?(socket.assigns.layouts, &(&1.group == group)) or
      Enum.any?(Names.kinds(), fn kind ->
        File.exists?(Path.join(socket.assigns.root, Names.part_name(kind, group)))
      end)
  end

  # The parts of `group` that are its own and this editor shows.
  def own_kinds(assigns, group) do
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
  def request_layout_delete(socket, group) do
    socket = Editor.load_templates(socket)

    case layout_deletable(socket, group) do
      {:ok, _kinds} -> assign(socket, confirm_layout_delete: group)
      {:in_use, emails} -> Editor.notice(socket, :error, layout_in_use(socket, group, emails))
      :error -> socket
    end
  end

  # Asked again on the confirmation: an email may have taken the layout
  # since.
  def delete_layout(socket, group) do
    socket = socket |> assign(confirm_layout_delete: nil) |> Editor.load_templates()

    case layout_deletable(socket, group) do
      {:ok, kinds} ->
        {result, deleted} =
          case Layouts.delete(socket.assigns.root, group, kinds) do
            {:ok, deleted} ->
              {{:info, gettext("Deleted the layout “%{name}”.", name: group)}, deleted}

            {:error, reason, deleted} ->
              {{:error, gettext("Not deleted: %{reason}", reason: Editor.describe(reason))},
               deleted}
          end

        if deleted != [], do: Editor.journal(socket, %{action: :layout_deleted, layout: group})
        changed = for name <- deleted, do: Editor.notify_changed(socket, name)

        socket
        |> assign(notice: Editor.with_notified(result, first_failure(changed)))
        |> Editor.load_templates()
        |> Editor.keep_selection()

      {:in_use, emails} ->
        Editor.notice(socket, :error, layout_in_use(socket, group, emails))

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
  def describe_emails(assigns, emails) do
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
end
