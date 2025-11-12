defmodule Hudson.Catalog.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "products" do
    field :display_number, :integer
    field :name, :string
    field :short_name, :string
    field :description, :string
    field :talking_points_md, :string
    field :original_price_cents, :integer
    field :sale_price_cents, :integer
    field :pid, :string
    field :sku, :string
    field :stock, :integer
    field :is_featured, :boolean, default: false
    field :tags, {:array, :string}, default: []
    field :external_url, :string

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
      :display_number,
      :name,
      :short_name,
      :description,
      :talking_points_md,
      :original_price_cents,
      :sale_price_cents,
      :pid,
      :sku,
      :stock,
      :is_featured,
      :tags,
      :external_url
    ])
    |> validate_required([:brand_id, :name, :original_price_cents])
    |> validate_number(:original_price_cents, greater_than: 0)
    |> validate_number(:sale_price_cents, greater_than: 0)
    |> validate_number(:stock, greater_than_or_equal_to: 0)
    |> unique_constraint(:pid)
    |> foreign_key_constraint(:brand_id)
  end
end
