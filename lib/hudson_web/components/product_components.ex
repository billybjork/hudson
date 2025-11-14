defmodule HudsonWeb.ProductComponents do
  @moduledoc """
  Reusable components for product management features.

  ## Stream + LiveComponent Pattern with Embedded Selection State

  This module implements a pattern for rendering product grids with streams AND
  dynamic state (like selection checkmarks). The solution embeds selection state
  in the stream data itself, enabling proper re-rendering via stream_insert.

  ### How It Works:

  1. **Selection state is part of stream data** - Each product in the stream includes
     a `:selected` boolean field that gets updated when selection changes.

  2. **Product loading includes selection state** - When loading products, we pre-compute
     the `:selected` field based on the current selection MapSet.

  3. **Event handlers use stream_insert** - When a product is selected/deselected:
     - Update the selection MapSet (for persistence/logic)
     - Use `stream_insert` to update that specific product in the stream with the new `:selected` value
     - The SelectCardComponent receives the updated product and re-renders

  4. **SelectCardComponent uses the `:selected` prop** - Simply reads `@product.selected`
     instead of checking against a MapSet, making it simple and reliable.

  ### Pattern in SessionsLive.Index:

  ```elixir
  # When loading products, include selection state
  products_with_state = Enum.map(products, fn product ->
    Map.put(product, :selected, MapSet.member?(socket.assigns.selected_product_ids, product.id))
  end)
  socket |> stream(:new_session_products, products_with_state, reset: true)

  # When toggling selection
  def handle_event("toggle_product_selection", %{"product-id" => product_id}, socket) do
    # Update the MapSet for persistence
    new_selected_ids = toggle_in_set(socket.assigns.selected_product_ids, product_id)

    # Update the stream item with new selection state
    product = find_product_in_stream(socket.assigns.streams.new_session_products, product_id)
    updated_product = Map.put(product, :selected, MapSet.member?(new_selected_ids, product_id))

    socket
    |> assign(:selected_product_ids, new_selected_ids)
    |> stream_insert(:new_session_products, updated_product)
  end
  ```

  ### SelectCardComponent in product_components.ex:

  ```elixir
  <div class={["product-card-select", @product.selected && "product-card-select--selected"]}>
    <div class={["product-card-select__checkmark", !@product.selected && "product-card-select__checkmark--hidden"]}>
      <!-- checkmark SVG -->
    </div>
  </div>
  ```

  The component simply reads `@product.selected` - no complex MapSet logic needed.
  """
  use Phoenix.Component

  import HudsonWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: HudsonWeb.Endpoint,
    router: HudsonWeb.Router,
    statics: HudsonWeb.static_paths()

  alias Phoenix.LiveView.JS

  @doc """
  Renders the product edit modal dialog.

  This component handles editing product details including basic info, pricing,
  product details, and settings. It displays the product's primary image and
  provides form validation and submission.

  ## Required Assigns
  - `editing_product` - The product being edited (must have product_images preloaded)
  - `product_edit_form` - The form bound to the product changeset
  - `brands` - List of available brands for the dropdown

  ## Example

      <.product_edit_modal
        editing_product={@editing_product}
        product_edit_form={@product_edit_form}
        brands={@brands}
      />
  """
  attr :editing_product, :any, required: true, doc: "The product being edited"
  attr :product_edit_form, :any, required: true, doc: "The product form"
  attr :brands, :list, required: true, doc: "List of available brands"

  def product_edit_modal(assigns) do
    ~H"""
    <%= if @editing_product do %>
      <.modal
        id="edit-product-modal"
        show={true}
        on_cancel={JS.push("close_edit_product_modal")}
      >
        <div class="modal__header">
          <h2 class="modal__title">Edit Product</h2>
        </div>

        <div class="modal__body">
          <%= if image = primary_image(@editing_product) do %>
            <div class="box box--bordered" style="max-width: 400px; margin-bottom: var(--space-md);">
              <img
                src={Hudson.Media.public_image_url(image.path)}
                alt={image.alt_text}
                style="width: 100%; height: auto; display: block; border-radius: var(--radius-sm);"
              />
              <p
                class="text-sm text-secondary"
                style="margin-top: var(--space-xs); text-align: center;"
              >
                Product Image {if image.is_primary, do: "(Primary)"}
              </p>
              <div style="margin-top: var(--space-sm); text-align: center;">
                <.button
                  navigate={~p"/products/upload?product_id=#{@editing_product.id}"}
                  variant="primary"
                  size="sm"
                >
                  Manage Images
                </.button>
              </div>
            </div>
          <% end %>

          <.form
            for={@product_edit_form}
            phx-change="validate_product"
            phx-submit="save_product"
            class="stack stack--lg"
          >
            <div class="stack">
              <.input
                field={@product_edit_form[:brand_id]}
                type="select"
                label="Brand"
                options={Enum.map(@brands, fn b -> {b.name, b.id} end)}
                prompt="Select a brand"
              />

              <.input
                field={@product_edit_form[:name]}
                type="text"
                label="Product Name"
                placeholder="e.g., Tennis Bracelet"
              />

              <.input
                field={@product_edit_form[:description]}
                type="textarea"
                label="Description"
                placeholder="Detailed product description"
              />

              <.input
                field={@product_edit_form[:talking_points_md]}
                type="textarea"
                label="Talking Points"
                placeholder="- Point 1&#10;- Point 2&#10;- Point 3"
              />
            </div>

            <div class="stack">
              <.input
                field={@product_edit_form[:original_price_cents]}
                type="number"
                label="Original Price"
                placeholder="e.g., 19.95"
                step="0.01"
              />

              <.input
                field={@product_edit_form[:sale_price_cents]}
                type="number"
                label="Sale Price (optional)"
                placeholder="e.g., 14.95"
                step="0.01"
              />
            </div>

            <div class="stack">
              <.input
                field={@product_edit_form[:pid]}
                type="text"
                label="Product ID (PID)"
                placeholder="External product ID"
              />

              <.input
                field={@product_edit_form[:sku]}
                type="text"
                label="SKU"
                placeholder="Stock keeping unit"
              />
            </div>

            <div class="modal__footer">
              <.button
                type="button"
                phx-click={
                  JS.push("close_edit_product_modal")
                  |> HudsonWeb.CoreComponents.hide_modal("edit-product-modal")
                }
              >
                Cancel
              </.button>
              <.button type="submit" variant="primary" phx-disable-with="Saving...">
                Save Changes
              </.button>
            </div>
          </.form>
        </div>
      </.modal>
    <% end %>
    """
  end

  @doc """
  Renders a reusable product grid that can be used in different contexts.

  Supports two modes:
  - `:browse` - For browsing/editing products (/products page)
  - `:select` - For selecting products (New Session modal)

  ## Attributes
  - `products` - List of products to display (must have product_images preloaded)
  - `mode` - `:browse` or `:select` (default: :browse)
  - `search_query` - Current search query (for display)
  - `has_more` - Boolean indicating if more products are available
  - `on_product_click` - Event name to trigger when product is clicked
  - `on_search` - Event name to trigger on search (optional)
  - `on_load_more` - Event name to trigger on load more (optional)
  - `selected_ids` - MapSet of selected product IDs (for :select mode)
  - `show_prices` - Whether to show price info (default: false)
  - `show_search` - Whether to show search input (default: true)

  ## Example - Browse Mode (on /products page)

      <.product_grid
        products={@products}
        mode={:browse}
        search_query={@product_search_query}
        has_more={@products_has_more}
        on_product_click="show_edit_product_modal"
        on_search="search_products"
        on_load_more="load_more_products"
        show_prices={true}
        show_search={true}
      />

  ## Example - Select Mode (in New Session modal)

      <.product_grid
        products={@new_session_products}
        mode={:select}
        search_query={@product_search_query}
        has_more={@new_session_has_more}
        selected_ids={@selected_product_ids}
        on_product_click="toggle_product_selection"
        on_search="search_products"
        on_load_more="load_more_products"
        show_search={true}
      />
  """
  attr :products, :any, required: true, doc: "List of products to display"
  attr :mode, :atom, default: :browse, values: [:browse, :select], doc: "Grid mode"
  attr :search_query, :string, default: "", doc: "Current search query"
  attr :has_more, :boolean, default: false, doc: "Whether more products are available"
  attr :on_product_click, :string, required: true, doc: "Event to trigger on product click"
  attr :on_search, :string, default: nil, doc: "Event to trigger on search"
  attr :on_load_more, :string, default: nil, doc: "Event to trigger on load more"
  attr :selected_ids, :any, default: MapSet.new(), doc: "Selected product IDs (for select mode)"
  attr :show_prices, :boolean, default: false, doc: "Whether to show prices"
  attr :show_search, :boolean, default: true, doc: "Whether to show search input"
  attr :loading, :boolean, default: false, doc: "Whether products are currently loading"

  attr :search_placeholder, :string,
    default: "Search products...",
    doc: "Placeholder text for search input"

  attr :is_empty, :boolean, required: true, doc: "Whether the products collection is empty"

  def product_grid(assigns) do
    ~H"""
    <div class={["product-grid", "product-grid--#{@mode}"]}>
      <%= if @show_search do %>
        <div class="product-grid__header">
          <div class="product-grid__search">
            <input
              type="text"
              placeholder={@search_placeholder}
              value={@search_query}
              phx-keyup={@on_search}
              phx-debounce="300"
              class="input input--sm"
            />
          </div>
          <%= if @mode == :select do %>
            <div class="product-grid__count">
              ({MapSet.size(@selected_ids)} selected)
            </div>
          <% end %>
        </div>
      <% end %>

      <div class="product-grid__grid" id="product-grid" phx-update="stream">
        <%= if @is_empty do %>
          <div id="product-grid-empty" class="product-grid__empty">
            No products found. Try a different search.
          </div>
        <% else %>
          <%= for {dom_id, product} <- @products do %>
            <%= if @mode == :browse do %>
              <.product_card_browse
                id={dom_id}
                product={product}
                on_click={@on_product_click}
                show_prices={@show_prices}
              />
            <% else %>
              <.live_component
                module={HudsonWeb.ProductComponents.SelectCardComponent}
                id={dom_id}
                product={product}
                on_click={@on_product_click}
              />
            <% end %>
          <% end %>

          <%= if @has_more do %>
            <div id="product-grid-loader" class="product-grid__loader">
              <.button
                type="button"
                phx-click={@on_load_more}
                size="sm"
                disabled={@loading}
                phx-disable-with="Loading..."
              >
                Load More Products
              </.button>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  # Browse mode card - for /products page
  attr :id, :string, default: nil
  attr :product, :map, required: true
  attr :on_click, :string, required: true
  attr :show_prices, :boolean, default: true

  defp product_card_browse(assigns) do
    ~H"""
    <div
      id={@id}
      class="product-card-browse"
      phx-click={@on_click}
      phx-value-product-id={@product.id}
      role="button"
      tabindex="0"
      aria-label={"Open #{@product.name}"}
    >
      <%= if @product.primary_image do %>
        <img
          src={
            Hudson.Media.public_image_url(
              @product.primary_image.thumbnail_path || @product.primary_image.path
            )
          }
          alt={@product.primary_image.alt_text}
          class="product-card-browse__image"
        />
      <% else %>
        <div class="product-card-browse__image-placeholder">
          No Image
        </div>
      <% end %>

      <div class="product-card-browse__info">
        <p class="product-card-browse__name">{@product.name}</p>

        <%= if @show_prices do %>
          <div class="product-card-browse__pricing">
            <%= if @product.sale_price_cents do %>
              <span class="product-card-browse__price-original">
                ${format_price(@product.original_price_cents)}
              </span>
              <span class="product-card-browse__price-sale">
                ${format_price(@product.sale_price_cents)}
              </span>
            <% else %>
              <span class="product-card-browse__price">
                <%= if @product.original_price_cents do %>
                  ${format_price(@product.original_price_cents)}
                <% else %>
                  Price not set
                <% end %>
              </span>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Select mode card - for New Session modal
  attr :id, :string, default: nil
  attr :product, :map, required: true
  attr :on_click, :string, required: true
  attr :selected, :boolean, default: false

  defp product_card_select(assigns) do
    ~H"""
    <div
      id={@id}
      class={["product-card-select", @selected && "product-card-select--selected"]}
      phx-click={@on_click}
      phx-value-product-id={@product.id}
      role="button"
      tabindex="0"
      aria-pressed={@selected}
      aria-label={"Select #{@product.name}"}
    >
      <div class={[
        "product-card-select__checkmark",
        !@selected && "product-card-select__checkmark--hidden"
      ]}>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 20 20"
          fill="currentColor"
          class="w-5 h-5"
        >
          <path
            fill-rule="evenodd"
            d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
            clip-rule="evenodd"
          />
        </svg>
      </div>

      <%= if @product.primary_image do %>
        <img
          src={
            Hudson.Media.public_image_url(
              @product.primary_image.thumbnail_path || @product.primary_image.path
            )
          }
          alt={@product.primary_image.alt_text}
          class="product-card-select__image"
        />
      <% else %>
        <div class="product-card-select__image-placeholder">
          No Image
        </div>
      <% end %>

      <p class="product-card-select__name">{@product.name}</p>
    </div>
    """
  end

  # Helper to format price cents to dollars
  defp format_price(nil), do: "0.00"

  defp format_price(cents) when is_integer(cents) do
    (cents / 100) |> Float.round(2) |> Float.to_string()
  end

  # Helper to get the primary image from a product
  defp primary_image(product) when is_nil(product), do: nil

  defp primary_image(product) do
    product.product_images
    |> Enum.find(& &1.is_primary)
    |> case do
      nil -> List.first(product.product_images)
      image -> image
    end
  end

  # ============================================================================
  # LIVE COMPONENT: Product Selection Card
  # ============================================================================
  # This is a live_component that renders a selectable product card with a checkmark.
  # It's only used in :select mode for product grids with selection checkmarks.
  # The :selected state is embedded in the product data and updated via stream_insert.

  defmodule SelectCardComponent do
    use Phoenix.LiveComponent

    @moduledoc """
    A live component that renders a selectable product card with a checkbox indicator.

    Displays a product with its primary image and title, with visual feedback
    indicating selection state. Selection is toggled via the `on_click` callback.
    """

    @impl true
    def render(assigns) do
      ~H"""
      <div
        id={@id}
        class={["product-card-select", @product.selected && "product-card-select--selected"]}
        phx-click={@on_click}
        phx-value-product-id={@product.id}
        role="button"
        tabindex="0"
        aria-pressed={@product.selected}
        aria-label={"Select #{@product.name}"}
      >
        <div class={[
          "product-card-select__checkmark",
          !@product.selected && "product-card-select__checkmark--hidden"
        ]}>
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 20 20"
            fill="currentColor"
            class="w-5 h-5"
          >
            <path
              fill-rule="evenodd"
              d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
              clip-rule="evenodd"
            />
          </svg>
        </div>

        <%= if @product.primary_image do %>
          <img
            src={
              Hudson.Media.public_image_url(
                @product.primary_image.thumbnail_path || @product.primary_image.path
              )
            }
            alt={@product.primary_image.alt_text}
            class="product-card-select__image"
          />
        <% else %>
          <div class="product-card-select__image-placeholder">
            No Image
          </div>
        <% end %>

        <p class="product-card-select__name">{@product.name}</p>
      </div>
      """
    end
  end
end
