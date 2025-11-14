defmodule HudsonWeb.ProductsLive.Index do
  use HudsonWeb, :live_view

  alias Hudson.Catalog
  alias Hudson.Catalog.Product

  import HudsonWeb.ProductComponents

  @impl true
  def mount(_params, _session, socket) do
    brands = Catalog.list_brands()

    socket =
      socket
      |> assign(:brands, brands)
      |> assign(:editing_product, nil)
      |> assign(:product_edit_form, to_form(Product.changeset(%Product{}, %{})))
      |> assign(:product_search_query, "")
      |> assign(:product_page, 1)
      |> assign(:product_total_count, 0)
      |> assign(:products_has_more, false)
      |> assign(:loading_products, false)
      |> stream(:products, [])
      |> load_products_for_browse()

    {:ok, socket}
  end

  @impl true
  def handle_event("show_edit_product_modal", %{"product-id" => product_id}, socket) do
    product = Catalog.get_product_with_images!(product_id)

    # Convert prices from cents to dollars for display by passing as changes
    changes = %{
      "original_price_cents" => format_cents_to_dollars(product.original_price_cents),
      "sale_price_cents" => format_cents_to_dollars(product.sale_price_cents)
    }

    changeset = Product.changeset(product, changes)

    socket =
      socket
      |> assign(:editing_product, product)
      |> assign(:product_edit_form, to_form(changeset))

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_edit_product_modal", _params, socket) do
    socket =
      socket
      |> assign(:editing_product, nil)
      |> assign(:product_edit_form, to_form(Product.changeset(%Product{}, %{})))

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_product", %{"product" => product_params}, socket) do
    changeset =
      socket.assigns.editing_product
      |> Product.changeset(product_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :product_edit_form, to_form(changeset))}
  end

  @impl true
  def handle_event("save_product", %{"product" => product_params}, socket) do
    # Convert price fields from dollars to cents
    product_params = convert_prices_to_cents(product_params)

    case Catalog.update_product(socket.assigns.editing_product, product_params) do
      {:ok, _product} ->
        socket =
          socket
          |> assign(:product_page, 1)
          |> assign(:loading_products, true)
          |> load_products_for_browse()
          |> assign(:editing_product, nil)
          |> assign(:product_edit_form, to_form(Product.changeset(%Product{}, %{})))
          |> put_flash(:info, "Product updated successfully")

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        socket =
          socket
          |> assign(:product_edit_form, to_form(changeset))
          |> put_flash(:error, "Please fix the errors below")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("search_products", %{"value" => query}, socket) do
    socket =
      socket
      |> assign(:product_search_query, query)
      |> assign(:product_page, 1)
      |> assign(:loading_products, true)
      |> load_products_for_browse()

    {:noreply, socket}
  end

  @impl true
  def handle_event("load_more_products", _params, socket) do
    socket =
      socket
      |> assign(:loading_products, true)
      |> load_products_for_browse(append: true)

    {:noreply, socket}
  end

  # Helper functions

  defp load_products_for_browse(socket, opts \\ [append: false]) do
    append = Keyword.get(opts, :append, false)
    search_query = socket.assigns.product_search_query
    page = if append, do: socket.assigns.product_page + 1, else: 1

    try do
      result =
        Catalog.search_products_paginated(
          search_query: search_query,
          page: page,
          per_page: 20
        )

      # Precompute primary images for all products
      products_with_images = Enum.map(result.products, &add_primary_image/1)

      socket
      |> assign(:loading_products, false)
      |> stream(:products, products_with_images, reset: !append)
      |> assign(:product_total_count, result.total)
      |> assign(:product_page, result.page)
      |> assign(:products_has_more, result.has_more)
    rescue
      _e ->
        socket
        |> assign(:loading_products, false)
        |> put_flash(:error, "Failed to load products")
    end
  end

  defp add_primary_image(product) do
    primary_image =
      product.product_images
      |> Enum.find(& &1.is_primary)
      |> case do
        nil -> List.first(product.product_images)
        image -> image
      end

    Map.put(product, :primary_image, primary_image)
  end

  defp format_cents_to_dollars(nil), do: nil
  defp format_cents_to_dollars(cents) when is_integer(cents) do
    cents / 100
  end

  defp convert_prices_to_cents(params) do
    params
    |> convert_price_field("original_price_cents")
    |> convert_price_field("sale_price_cents")
  end

  defp convert_price_field(params, field) do
    case Map.get(params, field) do
      nil ->
        params

      "" ->
        Map.put(params, field, nil)

      value when is_binary(value) ->
        parse_price_value(params, field, value)

      value when is_integer(value) ->
        params

      _ ->
        params
    end
  end

  defp parse_price_value(params, field, value) do
    case String.contains?(value, ".") do
      true -> convert_dollars_to_cents(params, field, value)
      false -> params
    end
  end

  defp convert_dollars_to_cents(params, field, value) do
    case Float.parse(value) do
      {dollars, _} -> Map.put(params, field, round(dollars * 100))
      :error -> params
    end
  end

end
