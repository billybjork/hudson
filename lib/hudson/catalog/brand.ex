defmodule Hudson.Catalog.Brand do
  use Ecto.Schema
  import Ecto.Changeset

  schema "brands" do
    field :name, :string
    field :slug, :string
    field :notes, :string

    has_many :products, Hudson.Catalog.Product
    has_many :sessions, Hudson.Sessions.Session

    timestamps()
  end

  @doc false
  def changeset(brand, attrs) do
    brand
    |> cast(attrs, [:name, :slug, :notes])
    |> validate_required([:name, :slug])
    |> unique_constraint(:name)
    |> unique_constraint(:slug)
  end
end
