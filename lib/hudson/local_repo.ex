defmodule Hudson.LocalRepo do
  @moduledoc """
  SQLite-backed Ecto repository for local data caching in desktop mode.
  """
  use Ecto.Repo,
    otp_app: :hudson,
    adapter: Ecto.Adapters.SQLite3
end
