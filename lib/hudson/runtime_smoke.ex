defmodule Hudson.RuntimeSmoke do
  @moduledoc """
  Pilot-time runtime checks to ensure native dependencies load correctly in releases.
  """

  require Logger

  def check_nifs do
    with :ok <- bcrypt_loaded?(),
         :ok <- lazy_html_loaded?() do
      Logger.info("Pilot NIF smoke checks passed (bcrypt_elixir, lazy_html)")
      :ok
    else
      {:error, reason} ->
        message = "Pilot NIF smoke check failed: #{inspect(reason)}"
        Logger.error(message)
        raise RuntimeError, message: message
    end
  end

  defp bcrypt_loaded? do
    sample = "pilot-check"
    hash = Bcrypt.hash_pwd_salt(sample)

    if Bcrypt.verify_pass(sample, hash) do
      :ok
    else
      {:error, :bcrypt_verify_failed}
    end
  rescue
    exception -> {:error, exception}
  end

  defp lazy_html_loaded? do
    _ = LazyHTML.from_fragment("<div></div>")
    :ok
  rescue
    exception -> {:error, exception}
  end
end
