defmodule Hudson.LocalRepo.Migrations.CreatePilotMarkers do
  use Ecto.Migration

  def change do
    create table(:pilot_markers) do
      add :label, :string, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
