defmodule WowForeverRecipeFinder.Writ do
  @moduledoc """
  One Craftsman's Writ — a daily quest asking for a crafted item — per
  docs/PRD.md § 7.8. Plain entity: produced by
  `Gateways.PrivFileWritAtlasGateway` from `priv/writs/craftsmans_writs.json`,
  placed on the world map by `WritAtlas`.

  `hand_in` is always present; its coordinate fields are `nil` when
  Wowhead doesn't know the turn-in NPC yet (see docs/DATA_SOURCES.md §
  Wowhead WoW Forever).
  """

  alias WowForeverRecipeFinder.WritHandIn

  @enforce_keys [:name, :wowhead_id, :quest_id, :tier, :professions, :required_items, :hand_in, :rewards]
  defstruct @enforce_keys

  @type tier :: :journeyman | :expert | :artisan

  @type required_item :: %{
          wowhead_id: pos_integer(),
          display_name: String.t(),
          quantity: pos_integer(),
          skill: non_neg_integer() | nil
        }

  @type rewards :: %{
          reputation: non_neg_integer(),
          money_copper: non_neg_integer(),
          item_names: [String.t()]
        }

  @type t :: %__MODULE__{
          name: String.t(),
          wowhead_id: pos_integer(),
          quest_id: pos_integer(),
          tier: tier(),
          professions: [String.t()],
          required_items: [required_item()],
          hand_in: WritHandIn.t(),
          rewards: rewards()
        }
end
