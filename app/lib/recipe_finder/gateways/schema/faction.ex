defmodule WowForeverRecipeFinder.Gateways.Schema.Faction do
  @moduledoc """
  Ecto-backed persistence shape for a faction row. See
  docs/CODE_STYLE.md § Clean Architecture and docs/SCHEMA.md §
  Craftsman's Writ catalog.
  """

  use Ecto.Schema

  schema "faction" do
    field :wowhead_faction_id, :integer
    field :display_name, :string

    timestamps(type: :utc_datetime)
  end
end
