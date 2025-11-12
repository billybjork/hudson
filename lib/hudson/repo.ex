defmodule Hudson.Repo do
  use Ecto.Repo,
    otp_app: :hudson,
    adapter: Ecto.Adapters.Postgres
end
