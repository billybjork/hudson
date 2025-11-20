defmodule Pavoi.TiktokShop.Auth do
  @moduledoc """
  Schema for TikTok Shop authentication credentials.
  Stores access tokens, refresh tokens, and shop-specific information.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "tiktok_shop_auth" do
    field :access_token, :string
    field :refresh_token, :string
    field :access_token_expires_at, :utc_datetime
    field :refresh_token_expires_at, :utc_datetime
    field :shop_id, :string
    field :shop_cipher, :string
    field :shop_name, :string
    field :shop_code, :string
    field :region, :string

    timestamps()
  end

  @doc false
  def changeset(auth, attrs) do
    auth
    |> cast(attrs, [
      :access_token,
      :refresh_token,
      :access_token_expires_at,
      :refresh_token_expires_at,
      :shop_id,
      :shop_cipher,
      :shop_name,
      :shop_code,
      :region
    ])
    |> validate_required([:access_token, :refresh_token])
  end
end
