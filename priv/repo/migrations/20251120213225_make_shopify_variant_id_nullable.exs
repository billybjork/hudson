defmodule Pavoi.Repo.Migrations.MakeShopifyVariantIdNullable do
  use Ecto.Migration

  def change do
    # Make shopify_variant_id nullable to support TikTok-only products
    alter table(:product_variants) do
      modify :shopify_variant_id, :string, null: true
    end
  end
end
