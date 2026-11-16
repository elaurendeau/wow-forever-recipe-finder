defmodule WowForeverRecipeFinder.Gateways.Schema.WritReputationReward do
  @moduledoc """
  Ecto-backed persistence shape for one writ-reputation-reward row.
  See docs/CODE_STYLE.md § Clean Architecture and docs/SCHEMA.md §
  Craftsman's Writ catalog.
  """

  use Ecto.Schema

  alias WowForeverRecipeFinder.Gateways.Schema.{Faction, Writ}

  schema "writ_reputation_reward" do
    field :amount, :integer

    belongs_to :writ, Writ
    belongs_to :faction, Faction

    timestamps(type: :utc_datetime)
  end
end
