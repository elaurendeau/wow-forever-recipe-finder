defmodule WowForeverRecipeFinder.ReputationReward do
  @moduledoc """
  One faction's reputation amount a Craftsman's Writ grants on
  turn-in. See docs/PRD.md § 7.8. The faction's display name is
  denormalized here at the gateway boundary — nothing outside the
  Gateways layer needs to look up a separate `Faction` row.
  """

  @enforce_keys [:faction_display_name, :amount]
  defstruct [:faction_display_name, :amount]

  @type t :: %__MODULE__{faction_display_name: String.t(), amount: pos_integer()}
end
