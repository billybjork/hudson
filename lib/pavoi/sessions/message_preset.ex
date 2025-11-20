defmodule Pavoi.Sessions.MessagePreset do
  @moduledoc """
  Represents a preset message template that can be sent to the host.

  Presets are global and can be used across all sessions. Each preset includes
  a label, message text, and color for visual styling on the host view.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_colors ~w(amber blue green red purple gray)

  schema "message_presets" do
    field :message_text, :string
    field :color, :string
    field :position, :integer

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of valid color options.
  """
  def valid_colors, do: @valid_colors

  @doc false
  def changeset(message_preset, attrs) do
    message_preset
    |> cast(attrs, [:message_text, :color, :position])
    |> validate_required([:message_text, :color])
    |> validate_length(:message_text, min: 1, max: 1000)
    |> validate_inclusion(:color, @valid_colors)
    |> validate_number(:position, greater_than_or_equal_to: 0)
  end
end
