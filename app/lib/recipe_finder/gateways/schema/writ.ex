defmodule WowForeverRecipeFinder.Gateways.Schema.Writ do
  @moduledoc """
  Ecto-backed persistence shape for a writ row. See
  docs/CODE_STYLE.md § Clean Architecture and docs/SCHEMA.md §
  Craftsman's Writ catalog.
  """

  use Ecto.Schema

  alias WowForeverRecipeFinder.Gateways.Schema.{WritReputationReward, WritRequiredItem}

  schema "writ" do
    field :name, :string
    field :wowhead_quest_id, :integer
    field :writ_item_wowhead_id, :integer
    field :writ_item_display_name, :string
    field :profession_slugs, {:array, :string}
    field :tier, :string
    field :repeat, :string
    field :hand_in_npc_name, :string
    field :hand_in_npc_id, :integer
    field :hand_in_zone, :string
    field :hand_in_zone_id, :integer
    field :hand_in_way_x, :float
    field :hand_in_way_y, :float
    field :hand_in_friendly_to, {:array, :string}
    field :reward_money_copper, :integer
    field :resolution_status, :string

    has_many :writ_required_items, WritRequiredItem
    has_many :writ_reputation_rewards, WritReputationReward

    timestamps(type: :utc_datetime)
  end
end
