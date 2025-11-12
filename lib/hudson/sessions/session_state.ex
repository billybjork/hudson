defmodule Hudson.Sessions.SessionState do
  use Ecto.Schema
  import Ecto.Changeset

  schema "session_states" do
    field :current_image_index, :integer, default: 0
    field :updated_at, :utc_datetime

    belongs_to :session, Hudson.Sessions.Session
    belongs_to :current_session_product, Hudson.Sessions.SessionProduct
  end

  @doc false
  def changeset(state, attrs) do
    state
    |> cast(attrs, [:session_id, :current_session_product_id, :current_image_index])
    |> validate_required([:session_id])
    |> validate_number(:current_image_index, greater_than_or_equal_to: 0)
    |> unique_constraint(:session_id)
    |> foreign_key_constraint(:session_id)
    |> foreign_key_constraint(:current_session_product_id)
    |> put_change(:updated_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
