defmodule Hudson.Import do
  @moduledoc """
  Import products from Google Sheets export.

  Handles:
  - Parsing products.json
  - Uploading images to Supabase
  - Creating/updating products and product images
  - Validating data before import
  """

  require Logger
  import Ecto.Query

  alias Hudson.{Catalog, Media, Repo}
  alias Hudson.Catalog.{Brand, Product, ProductImage}

  @doc """
  Import products from an export folder.

  ## Options
  - `:dry_run` - Preview changes without writing to database (default: false)
  - `:brand_id` - Brand ID to assign products to (required)
  - `:update_existing` - Update products if they already exist (default: false)

  ## Example

      Hudson.Import.import_from_folder("priv/import/holiday-favorites", brand_id: 1)

  """
  def import_from_folder(folder_path, opts \\ []) do
    with {:ok, data} <- read_import_data(folder_path),
         :ok <- validate_data(data),
         {:ok, brand} <- get_or_create_brand(opts) do
      if Keyword.get(opts, :dry_run, false) do
        {:ok, preview: preview_import(data, brand)}
      else
        do_import(data, brand, folder_path, opts)
      end
    end
  end

  @doc """
  Read and parse products.json from export folder.
  """
  def read_import_data(folder_path) do
    json_path = Path.join(folder_path, "products.json")

    with true <- File.exists?(json_path),
         {:ok, content} <- File.read(json_path),
         {:ok, data} <- Jason.decode(content, keys: :atoms) do
      {:ok, data}
    else
      false ->
        {:error, "products.json not found in #{folder_path}"}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, "Failed to parse JSON: #{inspect(error)}"}

      {:error, reason} ->
        {:error, "Failed to read file: #{inspect(reason)}"}
    end
  end

  @doc """
  Validate import data structure.
  """
  def validate_data(%{products: products}) when is_list(products) do
    errors =
      products
      |> Enum.with_index(fn product, idx ->
        validate_product(product, idx + 1)
      end)
      |> Enum.filter(fn result -> result != :ok end)

    if Enum.empty?(errors) do
      :ok
    else
      {:error, {:validation_failed, errors}}
    end
  end

  def validate_data(_), do: {:error, "Invalid data format: missing products array"}

  defp validate_product(product, line) do
    required = [:name]
    missing = Enum.filter(required, fn key -> !Map.has_key?(product, key) end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, line, "Missing required fields: #{inspect(missing)}"}
    end
  end

  @doc """
  Preview import without making changes.
  """
  def preview_import(%{products: products}, _brand) do
    products
    |> Enum.map(fn product ->
      %{
        action: if(product_exists?(product), do: :skip, else: :create),
        name: product.name,
        has_image: !is_nil(product.image_filename),
        prices: {product.original_price_cents, product.sale_price_cents}
      }
    end)
  end

  @doc """
  Perform the actual import.
  """
  def do_import(%{products: products}, brand, folder_path, opts) do
    update_existing = Keyword.get(opts, :update_existing, false)
    images_path = Path.join(folder_path, "images")

    results =
      Repo.transaction(fn ->
        Enum.map(products, fn product_data ->
          import_product(product_data, brand, images_path, update_existing)
        end)
      end)

    case results do
      {:ok, imported} ->
        successes = Enum.count(imported, fn {status, _} -> status == :ok end)
        failures = Enum.count(imported, fn {status, _} -> status == :error end)

        {:ok,
         %{
           total: length(imported),
           successes: successes,
           failures: failures,
           results: imported
         }}

      {:error, reason} ->
        {:error, "Transaction failed: #{inspect(reason)}"}
    end
  end

  defp import_product(product_data, brand, images_path, update_existing) do
    # Check if product exists by PID (unique identifier)
    existing =
      Repo.get_by(Product, pid: product_data.pid)

    cond do
      is_nil(existing) ->
        create_product_with_images(product_data, brand, images_path)

      update_existing ->
        update_product_with_images(existing, product_data, images_path)

      true ->
        {:skipped, "Product #{product_data.name} already exists"}
    end
  end

  defp create_product_with_images(product_data, brand, images_path) do
    # Create product
    product_attrs = %{
      brand_id: brand.id,
      name: product_data.name,
      talking_points_md: product_data.talking_points_md,
      original_price_cents: product_data.original_price_cents,
      sale_price_cents: product_data.sale_price_cents,
      pid: product_data.pid,
      sku: product_data.sku
    }

    case Catalog.create_product(product_attrs) do
      {:ok, product} ->
        # Upload and attach image if present
        if product_data.image_filename do
          upload_product_image(product, product_data.image_filename, images_path, 0)
        end

        Logger.info("Created product: #{product.name}")
        {:ok, product}

      {:error, changeset} ->
        Logger.error(
          "Failed to create product: #{inspect(changeset.errors)}"
        )

        {:error, "Failed to create product: #{inspect(changeset.errors)}"}
    end
  end

  defp update_product_with_images(existing_product, product_data, images_path) do
    # Update product
    update_attrs = %{
      name: product_data.name,
      talking_points_md: product_data.talking_points_md,
      original_price_cents: product_data.original_price_cents,
      sale_price_cents: product_data.sale_price_cents,
      pid: product_data.pid,
      sku: product_data.sku
    }

    case Catalog.update_product(existing_product, update_attrs) do
      {:ok, product} ->
        # Upload image if present and no images exist
        if product_data.image_filename && !has_images?(product) do
          upload_product_image(product, product_data.image_filename, images_path, 0)
        end

        Logger.info("Updated product: #{product.name}")
        {:ok, product}

      {:error, changeset} ->
        Logger.error(
          "Failed to update product: #{inspect(changeset.errors)}"
        )

        {:error, "Failed to update product: #{inspect(changeset.errors)}"}
    end
  end

  defp upload_product_image(product, filename, images_path, position) do
    image_file_path = Path.join(images_path, filename)

    with true <- File.exists?(image_file_path),
         {:ok, %{path: path, thumbnail_path: thumb_path}} <-
           Media.upload_product_image(image_file_path, product.id, position),
         {:ok, _image} <-
           Catalog.create_product_image(%{
             product_id: product.id,
             path: path,
             thumbnail_path: thumb_path,
             position: position,
             is_primary: position == 0,
             alt_text: "#{product.name} - Image #{position + 1}"
           }) do
      Logger.info("Uploaded image for product #{product.display_number}: #{filename}")
    else
      false ->
        Logger.warning("Image file not found: #{image_file_path}")

      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.error(
          "Failed to create product_image record for product: #{inspect(changeset.errors)}"
        )

      {:error, reason} ->
        Logger.error(
          "Failed to upload image: #{inspect(reason)}"
        )
    end
  end

  defp product_exists?(product_data) do
    Repo.exists?(
      from p in Product,
        where: p.pid == ^product_data.pid
    )
  end

  defp has_images?(product) do
    Repo.exists?(
      from pi in ProductImage,
        where: pi.product_id == ^product.id
    )
  end

  defp get_or_create_brand(opts) do
    case Keyword.fetch(opts, :brand_id) do
      {:ok, brand_id} ->
        case Repo.get(Brand, brand_id) do
          nil -> {:error, "Brand with ID #{brand_id} not found"}
          brand -> {:ok, brand}
        end

      :error ->
        # Try to get default "Pavoi" brand or create it
        case Repo.get_by(Brand, slug: "pavoi") do
          nil ->
            Logger.info("Creating default 'Pavoi' brand...")

            Catalog.create_brand(%{
              name: "Pavoi",
              slug: "pavoi",
              notes: "Default brand for imports"
            })

          brand ->
            {:ok, brand}
        end
    end
  end
end
