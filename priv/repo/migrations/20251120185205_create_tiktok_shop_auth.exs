defmodule Pavoi.Repo.Migrations.CreateTiktokShopAuth do
  use Ecto.Migration

  def change do
    create table(:tiktok_shop_auth) do
      add :access_token, :text
      add :refresh_token, :text
      add :access_token_expires_at, :utc_datetime
      add :refresh_token_expires_at, :utc_datetime
      add :shop_id, :string
      add :shop_cipher, :text
      add :shop_name, :string
      add :shop_code, :string
      add :region, :string

      timestamps()
    end

    # We only support one TikTok Shop account for now
    # This will fail if we try to insert more than one record
    create unique_index(:tiktok_shop_auth, [:id])
  end
end
