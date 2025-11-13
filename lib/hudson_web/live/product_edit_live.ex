defmodule HudsonWeb.ProductEditLive do
  use HudsonWeb, :live_view

  alias Hudson.Catalog
  alias Hudson.Catalog.Product

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    product = Catalog.get_product_with_images!(id)
    brands = Catalog.list_brands()

    socket =
      socket
      |> assign(:product, product)
      |> assign(:brands, brands)
      |> assign(:page_title, "Edit Product")
      |> assign(:form, to_form(Product.changeset(product, %{})))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"product" => product_params}, socket) do
    changeset =
      socket.assigns.product
      |> Product.changeset(product_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"product" => product_params}, socket) do
    # Convert price fields from dollars to cents
    product_params = convert_prices_to_cents(product_params)

    case Catalog.update_product(socket.assigns.product, product_params) do
      {:ok, _product} ->
        socket =
          socket
          |> put_flash(:info, "Product updated successfully")
          |> push_navigate(to: ~p"/products")

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        socket =
          socket
          |> assign(:form, to_form(changeset))
          |> put_flash(:error, "Please fix the errors below")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/products")}
  end

  # Helper functions

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
        # If value contains decimal point, treat as dollars, otherwise as cents
        if String.contains?(value, ".") do
          case Float.parse(value) do
            {dollars, _} -> Map.put(params, field, round(dollars * 100))
            :error -> params
          end
        else
          params
        end

      value when is_integer(value) ->
        params

      _ ->
        params
    end
  end

  def format_price_for_input(nil), do: ""

  def format_price_for_input(cents) when is_integer(cents) do
    # Convert cents to dollars for display
    :erlang.float_to_binary(cents / 100, decimals: 2)
  end

  def primary_image(product) do
    product.product_images
    |> Enum.find(& &1.is_primary)
    |> case do
      nil -> List.first(product.product_images)
      image -> image
    end
  end

  def public_image_url(path) do
    Hudson.Media.public_image_url(path)
  end
end
