defmodule WowForeverRecipeFinder.Gateways.Schema.WaylaidCrate do
  @moduledoc """
  Ecto-backed persistence shape for a waylaid crate row. See
  docs/CODE_STYLE.md § Clean Architecture and docs/SCHEMA.md §
  Waylaid Crate catalog.
  """

  use Ecto.Schema

  alias WowForeverRecipeFinder.Gateways.Schema.WaylaidCrateFillOption

  schema "waylaid_crate" do
    field :wowhead_id, :integer
    field :name, :string
    field :tier, :string
    field :category, :string
    field :variant, :string
    field :quality, :string
    field :required_level, :integer
    field :fill_options_captured, :boolean

    has_many :fill_options, WaylaidCrateFillOption

    timestamps(type: :utc_datetime)
  end
end
