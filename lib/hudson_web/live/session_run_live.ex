defmodule HudsonWeb.SessionRunLive do
  use HudsonWeb, :live_view

  alias Hudson.Sessions
  alias Hudson.Sessions.SessionProduct

  @impl true
  def mount(%{"id" => session_id}, _session, socket) do
    session = Sessions.get_session!(session_id)

    socket =
      assign(socket,
        session: session,
        session_id: String.to_integer(session_id),
        page_title: session.name,
        current_session_product: nil,
        current_product: nil,
        current_position: nil,
        current_image_index: 0,
        talking_points_html: nil,
        product_images: [],
        total_products: length(session.session_products)
      )

    # Subscribe to PubSub ONLY after WebSocket connection
    if connected?(socket) do
      subscribe_to_session(session_id)
      socket = load_initial_state(socket)

      # Set temporary assigns for memory management
      {:ok, socket, temporary_assigns: [
        current_session_product: nil,
        current_product: nil,
        talking_points_html: nil,
        product_images: []
      ]}
    else
      # Minimal work during HTTP mount
      {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Handle URL parameter changes (from push_patch or back button)
    socket =
      case params do
        %{"sp" => sp_id, "img" => img_idx} ->
          load_by_session_product_id(socket, String.to_integer(sp_id), String.to_integer(img_idx))

        _ ->
          socket
      end

    {:noreply, socket}
  end

  ## Event Handlers

  # PRIMARY NAVIGATION: Direct jump to product by number
  @impl true
  def handle_event("jump_to_product", %{"position" => position}, socket) do
    position = String.to_integer(position)

    case Sessions.jump_to_product(socket.assigns.session_id, position) do
      {:ok, new_state} ->
        socket =
          push_patch(socket,
            to:
              ~p"/sessions/#{socket.assigns.session_id}/run?sp=#{new_state.current_session_product_id}&img=0"
          )

        {:noreply, socket}

      {:error, :invalid_position} ->
        {:noreply, put_flash(socket, :error, "Invalid product number")}
    end
  end

  # CONVENIENCE: Sequential next/previous with arrow keys
  @impl true
  def handle_event("next_product", _params, socket) do
    case Sessions.advance_to_next_product(socket.assigns.session_id) do
      {:ok, new_state} ->
        socket =
          push_patch(socket,
            to:
              ~p"/sessions/#{socket.assigns.session_id}/run?sp=#{new_state.current_session_product_id}&img=#{new_state.current_image_index}"
          )

        {:noreply, socket}

      {:error, :end_of_session} ->
        {:noreply, put_flash(socket, :info, "End of session reached")}
    end
  end

  @impl true
  def handle_event("previous_product", _params, socket) do
    case Sessions.go_to_previous_product(socket.assigns.session_id) do
      {:ok, new_state} ->
        socket =
          push_patch(socket,
            to:
              ~p"/sessions/#{socket.assigns.session_id}/run?sp=#{new_state.current_session_product_id}&img=#{new_state.current_image_index}"
          )

        {:noreply, socket}

      {:error, :start_of_session} ->
        {:noreply, put_flash(socket, :info, "Already at first product")}
    end
  end

  @impl true
  def handle_event("next_image", _params, socket) do
    case Sessions.cycle_product_image(socket.assigns.session_id, :next) do
      {:ok, _state} -> {:noreply, socket}
      {:error, _} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("previous_image", _params, socket) do
    case Sessions.cycle_product_image(socket.assigns.session_id, :previous) do
      {:ok, _state} -> {:noreply, socket}
      {:error, _} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("jump_to_first", _params, socket) do
    # Jump to position 1 (first product)
    case Sessions.jump_to_product(socket.assigns.session_id, 1) do
      {:ok, new_state} ->
        socket =
          push_patch(socket,
            to:
              ~p"/sessions/#{socket.assigns.session_id}/run?sp=#{new_state.current_session_product_id}&img=0"
          )

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("jump_to_last", _params, socket) do
    # Jump to last product (total_products)
    last_position = socket.assigns.total_products

    case Sessions.jump_to_product(socket.assigns.session_id, last_position) do
      {:ok, new_state} ->
        socket =
          push_patch(socket,
            to:
              ~p"/sessions/#{socket.assigns.session_id}/run?sp=#{new_state.current_session_product_id}&img=0"
          )

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # Handle PubSub broadcasts from other clients
  @impl true
  def handle_info({:state_changed, new_state}, socket) do
    socket = load_state_from_session_state(socket, new_state)
    {:noreply, socket}
  end

  ## Private Helpers

  defp subscribe_to_session(session_id) do
    Phoenix.PubSub.subscribe(Hudson.PubSub, "session:#{session_id}:state")
  end

  defp load_initial_state(socket) do
    session_id = socket.assigns.session_id

    # Try to load existing state, or initialize to first product
    case Sessions.get_session_state(session_id) do
      {:ok, state} ->
        load_state_from_session_state(socket, state)

      {:error, :not_found} ->
        # Initialize to first product
        case Sessions.initialize_session_state(session_id) do
          {:ok, state} -> load_state_from_session_state(socket, state)
          {:error, _} -> socket
        end
    end
  end

  defp load_by_session_product_id(socket, session_product_id, image_index) do
    session_product = Sessions.get_session_product!(session_product_id)
    product = session_product.product

    assign(socket,
      current_session_product: session_product,
      current_product: product,
      current_image_index: image_index,
      current_position: session_product.position,
      talking_points_html:
        render_markdown(
          session_product.featured_talking_points_md || product.talking_points_md
        ),
      product_images: product.product_images
    )
  end

  defp load_state_from_session_state(socket, state) do
    if state.current_session_product_id do
      load_by_session_product_id(
        socket,
        state.current_session_product_id,
        state.current_image_index
      )
    else
      socket
    end
  end

  defp render_markdown(nil), do: nil

  defp render_markdown(markdown) do
    case Earmark.as_html(markdown) do
      {:ok, html, _} -> Phoenix.HTML.raw(html)
      _ -> nil
    end
  end

  ## Helper functions for template

  def format_price(nil), do: ""

  def format_price(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    cents_remainder = rem(cents, 100)
    "$#{dollars}.#{String.pad_leading(Integer.to_string(cents_remainder), 2, "0")}"
  end

  def get_effective_name(session_product) do
    SessionProduct.effective_name(session_product)
  end

  def get_effective_prices(session_product) do
    SessionProduct.effective_prices(session_product)
  end

  def public_image_url(path) do
    Hudson.Media.public_image_url(path)
  end
end
