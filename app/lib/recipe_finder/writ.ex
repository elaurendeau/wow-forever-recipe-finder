defmodule WowForeverRecipeFinder.Writ do
  @moduledoc """
  A Craftsman's Writ: bought from the AH, turned in with specific
  required items at a named NPC for reputation (and sometimes gold).
  See docs/PRD.md § 7.8. Plain struct — see docs/CODE_STYLE.md §
  Clean Architecture. The Ecto-backed persistence shape is
  `WowForeverRecipeFinder.Gateways.Schema.Writ`.
  """

  alias WowForeverRecipeFinder.{ReputationReward, WritHandIn, WritRequiredItem}

  @enforce_keys [
    :name,
    :wowhead_quest_id,
    :writ_item_wowhead_id,
    :writ_item_display_name,
    :profession_slugs,
    :tier,
    :reward_money_copper,
    :resolution_status,
    :required_items,
    :reputation_rewards
  ]
  defstruct [
    :id,
    :name,
    :wowhead_quest_id,
    :writ_item_wowhead_id,
    :writ_item_display_name,
    :profession_slugs,
    :tier,
    :repeat,
    :reward_money_copper,
    :resolution_status,
    :required_items,
    :reputation_rewards,
    hand_in: %WritHandIn{friendly_to: []}
  ]

  @type tier :: :apprentice | :journeyman | :expert | :artisan

  @typedoc """
  `:complete` means every required item is known. `:pending_quest_page`
  means the extraction hasn't fetched them yet — not that none
  exist — and `required_items` is `[]` in that state; never treat an
  empty list as "this writ needs nothing" without checking this field
  first. See docs/PRD.md § 7.8.
  """
  @type resolution_status :: :complete | :pending_quest_page

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          name: String.t(),
          wowhead_quest_id: pos_integer(),
          writ_item_wowhead_id: pos_integer(),
          writ_item_display_name: String.t(),
          profession_slugs: [String.t()],
          tier: tier(),
          repeat: String.t() | nil,
          hand_in: WritHandIn.t(),
          reward_money_copper: non_neg_integer(),
          resolution_status: resolution_status(),
          required_items: [WritRequiredItem.t()],
          reputation_rewards: [ReputationReward.t()]
        }
end
