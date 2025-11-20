defmodule Pavoi.Repo.Migrations.AddTiktokFieldsToProducts do
  use Ecto.Migration

  def change do
    # Add TikTok product ID to products table
    alter table(:products) do
      add :tiktok_product_id, :string, size: 100
    end

    # Add TikTok-specific fields to product_variants table
    alter table(:product_variants) do
      add :tiktok_sku_id, :string
      add :tiktok_price_cents, :integer
      add :tiktok_compare_at_price_cents, :integer
    end

    # Create indexes for efficient lookups
    create index(:products, [:tiktok_product_id])
    create unique_index(:product_variants, [:tiktok_sku_id], where: "tiktok_sku_id IS NOT NULL")
  end
end
