defmodule Hudson.Sessions.Session do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sessions" do
    field :name, :string
    field :slug, :string
    field :scheduled_at, :naive_datetime
    field :duration_minutes, :integer
    field :notes, :string
    field :status, :string, default: "draft"

    belongs_to :brand, Hudson.Catalog.Brand
    has_many :session_products, Hudson.Sessions.SessionProduct, preload_order: [asc: :position]
    has_one :session_state, Hudson.Sessions.SessionState

    timestamps()
  end

  @doc false
  def changeset(session, attrs) do
    session
    |> cast(attrs, [:brand_id, :name, :slug, :scheduled_at, :duration_minutes, :notes, :status])
    |> validate_required([:brand_id, :name, :slug])
    |> validate_inclusion(:status, ["draft", "live", "complete"])
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:brand_id)
  end
end
