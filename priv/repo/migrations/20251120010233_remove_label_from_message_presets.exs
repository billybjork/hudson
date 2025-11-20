defmodule Pavoi.Repo.Migrations.RemoveLabelFromMessagePresets do
  use Ecto.Migration

  def change do
    # Only drop the column if it exists (production has it, local dev might not)
    execute(
      "ALTER TABLE message_presets DROP COLUMN IF EXISTS label",
      "ALTER TABLE message_presets ADD COLUMN label VARCHAR(255)"
    )
  end
end
