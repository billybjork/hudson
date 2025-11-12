defmodule Hudson.Sessions do
  @moduledoc """
  The Sessions context handles live streaming sessions, session products, and real-time state management.
  """

  import Ecto.Query, warn: false
  alias Hudson.Repo

  alias Hudson.Sessions.{Session, SessionProduct, SessionState}
  alias Hudson.Catalog.ProductImage

  ## Sessions

  @doc """
  Returns the list of sessions.
  """
  def list_sessions do
    Repo.all(Session)
  end

  @doc """
  Gets a single session.
  Raises `Ecto.NoResultsError` if the Session does not exist.
  """
  def get_session!(id) do
    ordered_images = from(pi in ProductImage, order_by: [asc: pi.position])

    Session
    |> preload(session_products: [product: [:brand, product_images: ^ordered_images]])
    |> Repo.get!(id)
  end

  @doc """
  Gets a session by slug.
  """
  def get_session_by_slug!(slug) do
    ordered_images = from(pi in ProductImage, order_by: [asc: pi.position])

    Session
    |> where([s], s.slug == ^slug)
    |> preload(session_products: [product: [:brand, product_images: ^ordered_images]])
    |> Repo.one!()
  end

  @doc """
  Creates a session.
  """
  def create_session(attrs \\ %{}) do
    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a session.
  """
  def update_session(%Session{} = session, attrs) do
    session
    |> Session.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a session.
  """
  def delete_session(%Session{} = session) do
    Repo.delete(session)
  end

  ## Session Products

  @doc """
  Gets a single session product.
  """
  def get_session_product!(id) do
    ordered_images = from(pi in ProductImage, order_by: [asc: pi.position])

    SessionProduct
    |> preload(product: [:brand, product_images: ^ordered_images])
    |> Repo.get!(id)
  end

  @doc """
  Adds a product to a session with the given position and optional overrides.
  """
  def add_product_to_session(session_id, product_id, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put(:session_id, session_id)
      |> Map.put(:product_id, product_id)

    %SessionProduct{}
    |> SessionProduct.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets adjacent session products (for preloading).
  Returns products at positions: current_position ± range.
  """
  def get_adjacent_session_products(session_id, current_position, range \\ 2) do
    ordered_images = from(pi in ProductImage, order_by: [asc: pi.position])

    from(sp in SessionProduct,
      where:
        sp.session_id == ^session_id and
          sp.position >= ^(current_position - range) and
          sp.position <= ^(current_position + range),
      order_by: [asc: sp.position],
      preload: [product: [:brand, product_images: ^ordered_images]]
    )
    |> Repo.all()
  end

  ## Session State Management

  @doc """
  Gets the current session state.
  """
  def get_session_state(session_id) do
    case Repo.get_by(SessionState, session_id: session_id) do
      nil ->
        {:error, :not_found}

      state ->
        # Preload with ordered images
        state =
          state
          |> Repo.preload(current_session_product: [product: :brand])
          |> Repo.preload(current_session_product: [product: [product_images: from(pi in ProductImage, order_by: [asc: pi.position])]])
        {:ok, state}
    end
  end

  @doc """
  Initializes session state to the first product.
  """
  def initialize_session_state(session_id) do
    # Get first session product
    first_sp =
      from(sp in SessionProduct,
        where: sp.session_id == ^session_id,
        order_by: [asc: sp.position],
        limit: 1
      )
      |> Repo.one()

    if first_sp do
      %SessionState{}
      |> SessionState.changeset(%{
        session_id: session_id,
        current_session_product_id: first_sp.id,
        current_image_index: 0
      })
      |> Repo.insert()
      |> broadcast_state_change()
    else
      {:error, :no_products}
    end
  end

  @doc """
  PRIMARY NAVIGATION: Jumps directly to a product by its position number.
  This is the main navigation method for the talent view.
  """
  def jump_to_product(session_id, position) do
    case Repo.get_by(SessionProduct, session_id: session_id, position: position) do
      nil ->
        {:error, :invalid_position}

      sp ->
        update_session_state(session_id, %{
          current_session_product_id: sp.id,
          current_image_index: 0
        })
    end
  end

  @doc """
  CONVENIENCE: Advances to the next product in sequence.
  Used for arrow key navigation, not the primary method.
  """
  def advance_to_next_product(session_id) do
    with {:ok, current_state} <- get_session_state(session_id),
         {:ok, current_sp} <- get_current_session_product(current_state),
         {:ok, next_sp} <- get_next_session_product(session_id, current_sp.position) do
      update_session_state(session_id, %{
        current_session_product_id: next_sp.id,
        current_image_index: 0
      })
    else
      {:error, :no_next_product} -> {:error, :end_of_session}
      error -> error
    end
  end

  @doc """
  CONVENIENCE: Goes to the previous product in sequence.
  Used for arrow key navigation, not the primary method.
  """
  def go_to_previous_product(session_id) do
    with {:ok, current_state} <- get_session_state(session_id),
         {:ok, current_sp} <- get_current_session_product(current_state),
         {:ok, prev_sp} <- get_previous_session_product(session_id, current_sp.position) do
      update_session_state(session_id, %{
        current_session_product_id: prev_sp.id,
        current_image_index: 0
      })
    else
      {:error, :no_previous_product} -> {:error, :start_of_session}
      error -> error
    end
  end

  @doc """
  Cycles through product images (next or previous).
  """
  def cycle_product_image(session_id, direction) do
    with {:ok, state} <- get_session_state(session_id),
         {:ok, sp} <- get_current_session_product(state),
         product <- Repo.preload(sp.product, :product_images),
         image_count when image_count > 0 <- length(product.product_images) do
      new_index =
        case direction do
          :next -> rem(state.current_image_index + 1, image_count)
          :previous -> rem(state.current_image_index - 1 + image_count, image_count)
        end

      update_session_state(session_id, %{current_image_index: new_index})
    else
      0 -> {:error, :no_images}
      error -> error
    end
  end

  ## Private Helpers

  defp update_session_state(session_id, attrs) do
    Repo.transaction(fn ->
      # Lock the row to prevent concurrent updates
      state =
        from(ss in SessionState,
          where: ss.session_id == ^session_id,
          lock: "FOR UPDATE"
        )
        |> Repo.one!()
        |> SessionState.changeset(attrs)
        |> Repo.update!()

      broadcast_state_change({:ok, state})
      state
    end)
    |> case do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:error, reason}
    end
  end

  defp broadcast_state_change({:ok, %SessionState{} = state}) do
    Phoenix.PubSub.broadcast(
      Hudson.PubSub,
      "session:#{state.session_id}:state",
      {:state_changed, state}
    )

    {:ok, state}
  end

  defp broadcast_state_change(error), do: error

  defp get_current_session_product(%SessionState{current_session_product_id: nil}),
    do: {:error, :no_current_product}

  defp get_current_session_product(state) do
    case Repo.get(SessionProduct, state.current_session_product_id) do
      nil ->
        {:error, :not_found}

      sp ->
        # Preload with ordered images
        sp =
          sp
          |> Repo.preload(product: :brand)
          |> Repo.preload(product: [product_images: from(pi in ProductImage, order_by: [asc: pi.position])])
        {:ok, sp}
    end
  end

  defp get_next_session_product(session_id, current_position) do
    from(sp in SessionProduct,
      where: sp.session_id == ^session_id and sp.position > ^current_position,
      order_by: [asc: sp.position],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :no_next_product}
      sp -> {:ok, sp}
    end
  end

  defp get_previous_session_product(session_id, current_position) do
    from(sp in SessionProduct,
      where: sp.session_id == ^session_id and sp.position < ^current_position,
      order_by: [desc: sp.position],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :no_previous_product}
      sp -> {:ok, sp}
    end
  end
end
