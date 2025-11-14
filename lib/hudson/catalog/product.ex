defmodule Hudson.Catalog.Product do
  @moduledoc """
  Represents a product in the catalog.

  Products belong to brands and contain details like name, pricing, descriptions,
  talking points, and associated images. Products can be featured in live sessions.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "products" do
    field :name, :string
    field :description, :string
    field :talking_points_md, :string
    field :original_price_cents, :integer
    field :sale_price_cents, :integer
    field :pid, :string
    field :sku, :string

    belongs_to :brand, Hudson.Catalog.Brand
    has_many :product_images, Hudson.Catalog.ProductImage, preload_order: [asc: :position]
    has_many :session_products, Hudson.Sessions.SessionProduct

    timestamps()
  end

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, [
      :brand_id,
      :name,
      :description,
      :talking_points_md,
      :original_price_cents,
      :sale_price_cents,
      :pid,
      :sku
    ])
    |> validate_required([:brand_id, :name, :original_price_cents])
    |> validate_number(:original_price_cents, greater_than: 0)
    |> validate_sale_price()
    |> unique_constraint(:pid)
    |> foreign_key_constraint(:brand_id)
  end

  defp validate_sale_price(changeset) do
    case get_field(changeset, :sale_price_cents) do
      nil -> changeset
      price when price > 0 -> changeset
      _ -> add_error(changeset, :sale_price_cents, "must be nil or greater than 0")
    end
  end
end
