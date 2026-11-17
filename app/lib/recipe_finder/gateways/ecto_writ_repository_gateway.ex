defmodule WowForeverRecipeFinder.Gateways.EctoWritRepositoryGateway do
  @moduledoc """
  The real, Postgres-backed implementation of `WritRepositoryGateway`.
  Converts `Gateways.Schema.*` rows into plain `WowForeverRecipeFinder.*`
  domain structs at this boundary — nothing past this module ever sees
  an `Ecto.Schema` struct for the writ catalog. See docs/CODE_STYLE.md
  § Clean Architecture.
  """

  @behaviour WowForeverRecipeFinder.Gateways.WritRepositoryGateway

  alias WowForeverRecipeFinder.Repo
  alias WowForeverRecipeFinder.{ReputationReward, Writ, WritHandIn, WritRequiredItem}
  alias WowForeverRecipeFinder.Gateways.Schema

  @impl true
  def list_writs do
    Schema.Writ
    |> Repo.all()
    |> Repo.preload(writ_required_items: [], writ_reputation_rewards: :faction)
    |> Enum.map(&to_domain/1)
  end

  defp to_domain(%Schema.Writ{} = row) do
    %Writ{
      id: row.id,
      name: row.name,
      wowhead_quest_id: row.wowhead_quest_id,
      writ_item_wowhead_id: row.writ_item_wowhead_id,
      writ_item_display_name: row.writ_item_display_name,
      profession_slugs: row.profession_slugs,
      tier: parse_tier!(row.tier),
      repeat: row.repeat,
      hand_in: to_hand_in(row),
      reward_money_copper: row.reward_money_copper,
      resolution_status: parse_resolution_status!(row.resolution_status),
      required_items: Enum.map(row.writ_required_items, &to_required_item/1),
      reputation_rewards: Enum.map(row.writ_reputation_rewards, &to_reputation_reward/1)
    }
  end

  defp to_hand_in(%Schema.Writ{} = row) do
    %WritHandIn{
      npc_id: row.hand_in_npc_id,
      npc_name: row.hand_in_npc_name,
      zone: row.hand_in_zone,
      zone_id: row.hand_in_zone_id,
      way_x: row.hand_in_way_x,
      way_y: row.hand_in_way_y,
      friendly_to: Enum.map(row.hand_in_friendly_to || [], &parse_faction!/1)
    }
  end

  defp parse_faction!("alliance"), do: :alliance
  defp parse_faction!("horde"), do: :horde

  defp parse_faction!(other),
    do: raise(ArgumentError, "unknown writ hand-in faction: #{inspect(other)}")

  # Explicit, closed mappings — see EctoCatalogRepositoryGateway for
  # why this beats String.to_existing_atom/1 here.
  defp parse_tier!("apprentice"), do: :apprentice
  defp parse_tier!("journeyman"), do: :journeyman
  defp parse_tier!("expert"), do: :expert
  defp parse_tier!("artisan"), do: :artisan
  defp parse_tier!(other), do: raise(ArgumentError, "unknown writ tier: #{inspect(other)}")

  defp parse_resolution_status!("complete"), do: :complete
  defp parse_resolution_status!("pending_quest_page"), do: :pending_quest_page

  defp parse_resolution_status!(other),
    do: raise(ArgumentError, "unknown writ resolution_status: #{inspect(other)}")

  defp to_required_item(%Schema.WritRequiredItem{} = row) do
    %WritRequiredItem{
      wowhead_id: row.wowhead_id,
      display_name: row.display_name,
      quantity: row.quantity
    }
  end

  defp to_reputation_reward(%Schema.WritReputationReward{} = row) do
    %ReputationReward{faction_display_name: row.faction.display_name, amount: row.amount}
  end
end
