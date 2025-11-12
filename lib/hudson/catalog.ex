defmodule Hudson.Catalog do
  @moduledoc """
  The Catalog context handles product management, brands, and product images.
  """

  import Ecto.Query, warn: false
  alias Hudson.Repo

  alias Hudson.Catalog.{Brand, Product, ProductImage}

  ## Brands

  @doc """
  Returns the list of brands.
  """
  def list_brands do
    Repo.all(Brand)
  end

  @doc """
  Gets a single brand.
  Raises `Ecto.NoResultsError` if the Brand does not exist.
  """
  def get_brand!(id), do: Repo.get!(Brand, id)

  @doc """
  Gets a brand by slug.
  """
  def get_brand_by_slug(slug) do
    Repo.get_by(Brand, slug: slug)
  end

  def get_brand_by_slug!(slug) do
    Repo.get_by!(Brand, slug: slug)
  end

  @doc """
  Creates a brand.
  """
  def create_brand(attrs \\ %{}) do
    %Brand{}
    |> Brand.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a brand.
  """
  def update_brand(%Brand{} = brand, attrs) do
    brand
    |> Brand.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a brand.
  """
  def delete_brand(%Brand{} = brand) do
    Repo.delete(brand)
  end

  ## Products

  @doc """
  Returns the list of products with optional filters.
  """
  def list_products(filters \\ []) do
    Product
    |> apply_product_filters(filters)
    |> Repo.all()
  end

  defp apply_product_filters(query, []), do: query

  defp apply_product_filters(query, [{:brand_id, brand_id} | rest]) do
    query
    |> where([p], p.brand_id == ^brand_id)
    |> apply_product_filters(rest)
  end

  defp apply_product_filters(query, [{:preload, preloads} | rest]) do
    query
    |> preload(^preloads)
    |> apply_product_filters(rest)
  end

  defp apply_product_filters(query, [_ | rest]) do
    apply_product_filters(query, rest)
  end

  @doc """
  Gets a single product.
  Raises `Ecto.NoResultsError` if the Product does not exist.
  """
  def get_product!(id), do: Repo.get!(Product, id)

  @doc """
  Gets a product with images preloaded.
  """
  def get_product_with_images!(id) do
    ordered_images = from(pi in ProductImage, order_by: [asc: pi.position])

    Product
    |> where([p], p.id == ^id)
    |> preload(product_images: ^ordered_images)
    |> Repo.one!()
  end

  @doc """
  Creates a product.
  """
  def create_product(attrs \\ %{}) do
    %Product{}
    |> Product.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a product.
  """
  def update_product(%Product{} = product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a product.
  """
  def delete_product(%Product{} = product) do
    Repo.delete(product)
  end

  ## Product Images

  @doc """
  Creates a product image.
  """
  def create_product_image(attrs \\ %{}) do
    %ProductImage{}
    |> ProductImage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a product image.
  """
  def update_product_image(%ProductImage{} = image, attrs) do
    image
    |> ProductImage.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a product image.
  """
  def delete_product_image(%ProductImage{} = image) do
    Repo.delete(image)
  end
end
