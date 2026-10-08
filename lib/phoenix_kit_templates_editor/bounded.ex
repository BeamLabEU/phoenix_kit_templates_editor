defmodule PhoenixKitTemplatesEditor.Bounded do
  @moduledoc false
  # Runs work the page waits on — a conversion, a preview, `git status` — in
  # a task with a deadline, so a pathological input or a stuck process costs
  # at most `timeout` ms of the LiveView, never the page.
  #
  # An exception, throw or exit inside the work is re-raised in the caller,
  # with its stacktrace, so the caller's own error handling sees it as if the
  # work had run there. The page's language (the module's Gettext backend and
  # the global locale) goes along into the task.

  @default_timeout 5_000

  @doc false
  @spec run((-> value), timeout()) :: {:ok, value} | {:error, :timeout} when value: term()
  def run(fun, timeout \\ @default_timeout) when is_function(fun, 0) do
    locales = {Gettext.get_locale(), Gettext.get_locale(PhoenixKitTemplatesEditor.Gettext)}

    task =
      Task.async(fn ->
        put_locales(locales)

        try do
          {:ok, fun.()}
        rescue
          exception -> {:raise, exception, __STACKTRACE__}
        catch
          kind, reason -> {:caught, kind, reason, __STACKTRACE__}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, value}} -> {:ok, value}
      {:ok, {:raise, exception, stacktrace}} -> reraise exception, stacktrace
      {:ok, {:caught, kind, reason, stacktrace}} -> :erlang.raise(kind, reason, stacktrace)
      {:exit, reason} -> exit(reason)
      nil -> {:error, :timeout}
    end
  end

  defp put_locales({global, own}) do
    Gettext.put_locale(global)
    Gettext.put_locale(PhoenixKitTemplatesEditor.Gettext, own)
  end
end
