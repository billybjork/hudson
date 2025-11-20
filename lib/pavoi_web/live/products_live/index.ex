defmodule PavoiWeb.ProductsLive.Index do
  use PavoiWeb, :live_view

  on_mount {PavoiWeb.NavHooks, :set_current_page}

  alias Pavoi.AI
  alias Pavoi.Catalog
  alias Pavoi.Catalog.Product
  alias Pavoi.Settings
  alias Pavoi.Workers.ShopifySyncWorker
  alias Pavoi.Workers.TiktokSyncWorker

  import PavoiWeb.ProductComponents
  import PavoiWeb.ViewHelpers

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to Shopify sync events, TikTok sync events, and AI generation events
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Pavoi.PubSub, "shopify:sync")
      Phoenix.PubSub.subscribe(Pavoi.PubSub, "tiktok:sync")
      Phoenix.PubSub.subscribe(Pavoi.PubSub, "ai:talking_points")
    end

    brands = Catalog.list_brands()
    last_sync_at = Settings.get_shopify_last_sync_at()
    tiktok_last_sync_at = Settings.get_tiktok_last_sync_at()

    socket =
      socket
      |> assign(:brands, brands)
      |> assign(:last_sync_at, last_sync_at)
      |> assign(:syncing, false)
      |> assign(:tiktok_last_sync_at, tiktok_last_sync_at)
      |> assign(:tiktok_syncing, false)
      |> assign(:platform_filter, "")
      |> assign(:editing_product, nil)
      |> assign(:product_edit_form, to_form(Product.changeset(%Product{}, %{})))
      |> assign(:current_edit_image_index, 0)
      |> assign(:generating_in_modal, false)
      |> assign(:product_search_query, "")
      |> assign(:product_sort_by, "")
      |> assign(:product_page, 1)
      |> assign(:product_total_count, 0)
      |> assign(:products_has_more, false)
      |> assign(:loading_products, false)
      |> assign(:search_touched, false)
      |> stream(:products, [])
      |> assign(:generating_product_id, nil)

    # Don't load products here - handle_params will do it based on URL params
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> apply_url_params(params)
      |> apply_search_params(params)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:sync_started}, socket) do
    socket =
      socket
      |> assign(:syncing, true)
      |> put_flash(:info, "Syncing product catalog from Shopify...")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:sync_completed, _counts}, socket) do
    # Reload products and update last sync timestamp
    last_sync_at = Settings.get_shopify_last_sync_at()

    socket =
      socket
      |> assign(:syncing, false)
      |> assign(:last_sync_at, last_sync_at)
      |> assign(:product_page, 1)
      |> assign(:loading_products, true)
      |> load_products_for_browse()
      |> put_flash(:info, "Shopify sync completed successfully")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:sync_failed, reason}, socket) do
    message =
      case reason do
        :rate_limited -> "Shopify sync paused due to rate limiting, will retry soon"
        _ -> "Shopify sync failed"
      end

    socket =
      socket
      |> assign(:syncing, false)
      |> put_flash(:error, message)

    {:noreply, socket}
  end

  # TikTok sync event handlers
  @impl true
  def handle_info({:tiktok_sync_started}, socket) do
    socket =
      socket
      |> assign(:tiktok_syncing, true)
      |> put_flash(:info, "Syncing product catalog from TikTok Shop...")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:tiktok_sync_completed, _counts}, socket) do
    # Reload products and update last sync timestamp
    tiktok_last_sync_at = Settings.get_tiktok_last_sync_at()

    socket =
      socket
      |> assign(:tiktok_syncing, false)
      |> assign(:tiktok_last_sync_at, tiktok_last_sync_at)
      |> assign(:product_page, 1)
      |> assign(:loading_products, true)
      |> load_products_for_browse()
      |> put_flash(:info, "TikTok sync completed successfully")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:tiktok_sync_failed, reason}, socket) do
    message = "TikTok sync failed: #{inspect(reason)}"

    socket =
      socket
      |> assign(:tiktok_syncing, false)
      |> put_flash(:error, message)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:generation_started, _generation}, socket) do
    socket =
      socket
      |> put_flash(:info, "Generating talking points...")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:generation_progress, _generation, _product_id, _product_name}, socket) do
    # No-op for individual products (could add progress indicator if needed)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:generation_completed, generation}, socket) do
    # If a product modal is currently open, refresh it with updated talking points
    socket =
      if socket.assigns.editing_product do
        product = Catalog.get_product_with_images!(socket.assigns.editing_product.id)

        changes = %{
          "talking_points_md" => product.talking_points_md
        }

        form = to_form(Product.changeset(product, changes))

        socket
        |> assign(:editing_product, product)
        |> assign(:product_edit_form, form)
      else
        socket
      end

    # Reload products to show updated talking points
    socket =
      socket
      |> assign(:generating_product_id, nil)
      |> assign(:generating_in_modal, false)
      |> assign(:product_page, 1)
      |> assign(:loading_products, true)
      |> load_products_for_browse()
      |> put_flash(
        :info,
        "Successfully generated talking points for #{generation.completed_count} product(s)!"
      )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:generation_failed, _generation, reason}, socket) do
    socket =
      socket
      |> assign(:generating_product_id, nil)
      |> assign(:generating_in_modal, false)
      |> put_flash(:error, "Failed to generate talking points: #{inspect(reason)}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("trigger_shopify_sync", _params, socket) do
    # Enqueue a Shopify sync job
    %{}
    |> ShopifySyncWorker.new()
    |> Oban.insert()

    socket =
      socket
      |> assign(:syncing, true)
      |> put_flash(:info, "Shopify sync initiated...")

    {:noreply, socket}
  end

  @impl true
  def handle_event("trigger_tiktok_sync", _params, socket) do
    # Enqueue a TikTok sync job
    %{}
    |> TiktokSyncWorker.new()
    |> Oban.insert()

    socket =
      socket
      |> assign(:tiktok_syncing, true)
      |> put_flash(:info, "TikTok sync initiated...")

    {:noreply, socket}
  end

  @impl true
  def handle_event("platform_filter_changed", %{"platform" => platform}, socket) do
    # Build query params preserving search query, sort, and adding platform filter
    query_params =
      %{}
      |> maybe_add_param(:q, socket.assigns.product_search_query)
      |> maybe_add_param(:sort, socket.assigns.product_sort_by)
      |> maybe_add_param(:platform, platform)

    {:noreply, push_patch(socket, to: ~p"/products?#{query_params}")}
  end

  @impl true
  def handle_event("show_edit_product_modal", %{"product-id" => product_id}, socket) do
    # Update URL to include product ID, preserving all other query params
    query_params =
      %{p: product_id}
      |> maybe_add_param(:q, socket.assigns.product_search_query)
      |> maybe_add_param(:sort, socket.assigns.product_sort_by)
      |> maybe_add_param(:platform, socket.assigns.platform_filter)

    {:noreply, push_patch(socket, to: ~p"/products?#{query_params}")}
  end

  @impl true
  def handle_event("close_edit_product_modal", _params, socket) do
    # Preserve all query params when closing modal
    query_params =
      %{}
      |> maybe_add_param(:q, socket.assigns.product_search_query)
      |> maybe_add_param(:sort, socket.assigns.product_sort_by)
      |> maybe_add_param(:platform, socket.assigns.platform_filter)

    socket =
      socket
      |> assign(:editing_product, nil)
      |> assign(:product_edit_form, to_form(Product.changeset(%Product{}, %{})))
      |> assign(:current_edit_image_index, 0)
      |> push_patch(to: ~p"/products?#{query_params}")

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
    # Mark search as touched to disable animations on subsequent loads
    socket = assign(socket, :search_touched, true)

    # Use push_patch to update URL - handle_params will handle the actual search
    # Preserve the current sort option and platform filter
    query_params =
      %{}
      |> maybe_add_param(:q, query)
      |> maybe_add_param(:sort, socket.assigns.product_sort_by)
      |> maybe_add_param(:platform, socket.assigns.platform_filter)

    {:noreply, push_patch(socket, to: ~p"/products?#{query_params}")}
  end

  @impl true
  def handle_event("sort_changed", %{"sort" => sort_by}, socket) do
    # Build query params preserving search query, sort, and platform filter
    query_params =
      %{}
      |> maybe_add_param(:q, socket.assigns.product_search_query)
      |> maybe_add_param(:sort, sort_by)
      |> maybe_add_param(:platform, socket.assigns.platform_filter)

    {:noreply, push_patch(socket, to: ~p"/products?#{query_params}")}
  end

  @impl true
  def handle_event("load_more_products", _params, socket) do
    socket =
      socket
      |> assign(:loading_products, true)
      |> load_products_for_browse(append: true)

    {:noreply, socket}
  end

  # Carousel navigation handlers for product edit modal
  @impl true
  def handle_event("goto_image", %{"index" => index_value}, socket) do
    # Only handle if editing a product (modal context)
    if socket.assigns.editing_product do
      # Handle both string and integer index values
      index = if is_binary(index_value), do: String.to_integer(index_value), else: index_value
      max_index = length(socket.assigns.editing_product.product_images) - 1
      safe_index = max(0, min(index, max_index))

      {:noreply, assign(socket, current_edit_image_index: safe_index)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("next_image", _params, socket) do
    # Only handle if editing a product (modal context)
    if socket.assigns.editing_product do
      max_index = length(socket.assigns.editing_product.product_images) - 1
      new_index = min(socket.assigns.current_edit_image_index + 1, max_index)

      {:noreply, assign(socket, current_edit_image_index: new_index)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("previous_image", _params, socket) do
    # Only handle if editing a product (modal context)
    if socket.assigns.editing_product do
      new_index = max(socket.assigns.current_edit_image_index - 1, 0)

      {:noreply, assign(socket, current_edit_image_index: new_index)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("generate_product_talking_points", %{"product-id" => product_id}, socket) do
    product_id = String.to_integer(product_id)

    case AI.generate_talking_points_async(product_id) do
      {:ok, _generation} ->
        socket =
          socket
          |> assign(:generating_product_id, product_id)
          |> assign(:generating_in_modal, true)

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> put_flash(:error, "Failed to start generation: #{reason}")

        {:noreply, socket}
    end
  end

  # Helper functions

  defp load_products_for_browse(socket, opts \\ [append: false]) do
    append = Keyword.get(opts, :append, false)
    search_query = socket.assigns.product_search_query
    sort_by = socket.assigns.product_sort_by
    platform_filter = socket.assigns.platform_filter
    page = if append, do: socket.assigns.product_page + 1, else: 1

    try do
      result =
        Catalog.search_products_paginated(
          search_query: search_query,
          sort_by: sort_by,
          platform_filter: platform_filter,
          page: page,
          per_page: 20
        )

      # Add stream_index to each product for staggered animations
      # Always start from 0 for each batch so infinite scroll doesn't have huge delays
      products_with_index =
        result.products
        |> Enum.with_index(0)
        |> Enum.map(fn {product, index} ->
          Map.put(product, :stream_index, index)
        end)

      # Products already have primary_image field from Catalog context
      socket
      |> assign(:loading_products, false)
      |> stream(:products, products_with_index,
        reset: !append,
        at: if(append, do: -1, else: 0)
      )
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

  defp apply_url_params(socket, params) do
    # Read "p" param for product modal
    case params["p"] do
      nil ->
        # No product in URL, close modal if open
        socket
        |> assign(:editing_product, nil)
        |> assign(:product_edit_form, to_form(Product.changeset(%Product{}, %{})))

      product_id_str ->
        try do
          product_id = String.to_integer(product_id_str)
          # Load the product and open modal
          product = Catalog.get_product_with_images!(product_id)

          # Convert prices from cents to dollars for display
          changes = %{
            "original_price_cents" => format_cents_to_dollars(product.original_price_cents),
            "sale_price_cents" => format_cents_to_dollars(product.sale_price_cents)
          }

          changeset = Product.changeset(product, changes)

          socket
          |> assign(:editing_product, product)
          |> assign(:product_edit_form, to_form(changeset))
          |> assign(:current_edit_image_index, 0)
        rescue
          Ecto.NoResultsError ->
            # Product not found, clear param by redirecting
            push_patch(socket, to: ~p"/products")

          ArgumentError ->
            # Invalid ID format, clear param by redirecting
            push_patch(socket, to: ~p"/products")
        end
    end
  end

  defp apply_search_params(socket, params) do
    # Read "q" param for search query, "sort" param for sorting, and "platform" for filtering
    search_query = params["q"] || ""
    sort_by = params["sort"] || ""
    platform_filter = params["platform"] || ""

    # Reload products if search query OR sort OR platform changed OR if products haven't been loaded yet
    should_load =
      socket.assigns.product_search_query != search_query ||
        socket.assigns.product_sort_by != sort_by ||
        socket.assigns.platform_filter != platform_filter ||
        socket.assigns.product_total_count == 0

    if should_load do
      socket
      |> assign(:product_search_query, search_query)
      |> assign(:product_sort_by, sort_by)
      |> assign(:platform_filter, platform_filter)
      |> assign(:product_page, 1)
      |> assign(:loading_products, true)
      |> load_products_for_browse()
    else
      socket
    end
  end

  # Helper to build query params, only including non-empty values
  defp maybe_add_param(params, _key, ""), do: params
  defp maybe_add_param(params, key, value), do: Map.put(params, key, value)
end
