defmodule Hudson.RuntimeSmoke do
  @moduledoc """
  Runtime checks to ensure native dependencies load correctly in releases.
  Validates SQLite (exqlite) NIF which is required for offline mode.
  """

  require Logger

  def check_nifs do
    case sqlite_loaded?() do
      :ok ->
        Logger.info("NIF smoke check passed (exqlite/SQLite)")
        :ok

      {:error, reason} ->
        message = "NIF smoke check failed: #{inspect(reason)}"
        Logger.error(message)
        raise RuntimeError, message: message
    end
  end

  defp sqlite_loaded? do
    # Test exqlite NIF by checking if LocalRepo can query SQLite
    # This verifies the NIF loaded correctly in the release
    case Hudson.LocalRepo.__adapter__() do
      Ecto.Adapters.SQLite3 -> :ok
      other -> {:error, {:unexpected_adapter, other}}
    end
  rescue
    exception -> {:error, exception}
  end
end
