defmodule WowForeverRecipeFinder.WritCatalogSeeder do
  @moduledoc """
  Loads the Craftsman's Writ catalog from a Wowhead-sourced extraction
  JSON file (see docs/PRD.md § 7.8 and docs/SCHEMA.md § Craftsman's
  Writ catalog for provenance and shape) into Postgres. Used by
  `priv/repo/seeds.exs` and safe to re-run: each run atomically
  replaces the whole writ catalog rather than appending duplicates or
  leaving a partial reseed half-done — same "replace atomically" rule
  as `CatalogSeeder`.

  Consumes the extraction's own raw shape directly (`factions` +
  `writs`, as delivered) rather than a pre-normalized shape — unlike
  the profession catalogs, there is no separate export tool producing
  an already-our-shape seed file for writs yet.
  """

  alias WowForeverRecipeFinder.Repo

  alias WowForeverRecipeFinder.Gateways.Schema.{
    Faction,
    Writ,
    WritReputationReward,
    WritRequiredItem
  }

  @spec load_from_file!(Path.t()) :: :ok
  def load_from_file!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
    |> load!()

    :ok
  end

  defp load!(%{"factions" => factions, "writs" => writs}) do
    Repo.transaction(fn ->
      faction_ids_by_external_id = upsert_factions!(factions)
      Repo.delete_all(Writ)
      Enum.each(writs, &insert_writ!(&1, faction_ids_by_external_id))
    end)
  end

  defp upsert_factions!(factions) do
    Map.new(factions, fn {external_id_str, display_name} ->
      external_id = String.to_integer(external_id_str)

      faction =
        case Repo.get_by(Faction, wowhead_faction_id: external_id) do
          nil ->
            Repo.insert!(%Faction{wowhead_faction_id: external_id, display_name: display_name})

          existing ->
            existing
        end

      {external_id, faction.id}
    end)
  end

  defp insert_writ!(attrs, faction_ids_by_external_id) do
    writ_item = attrs["writ_item"]
    hand_in = attrs["hand_in"] || %{}
    rewards = attrs["rewards"] || %{}

    writ =
      Repo.insert!(%Writ{
        name: attrs["name"],
        wowhead_quest_id: attrs["quest_id"],
        writ_item_wowhead_id: writ_item["wowhead_id"],
        writ_item_display_name: writ_item["display_name"],
        profession_slugs: attrs["professions"] || [],
        tier: attrs["tier"],
        repeat: attrs["repeat"],
        hand_in_npc_name: hand_in["npc_name"],
        hand_in_zone: hand_in["zone"],
        reward_money_copper: rewards["money_copper"] || 0,
        resolution_status: attrs["data_status"]
      })

    Enum.each(attrs["required_items"] || [], &insert_required_item!(writ, &1))

    Enum.each(
      rewards["reputation"] || [],
      &insert_reputation_reward!(writ, &1, faction_ids_by_external_id)
    )

    writ
  end

  defp insert_required_item!(writ, item_attrs) do
    Repo.insert!(%WritRequiredItem{
      writ_id: writ.id,
      wowhead_id: item_attrs["wowhead_id"],
      display_name: item_attrs["display_name"],
      quantity: item_attrs["quantity"]
    })
  end

  defp insert_reputation_reward!(writ, rep_attrs, faction_ids_by_external_id) do
    faction_id = Map.fetch!(faction_ids_by_external_id, rep_attrs["faction_id"])

    Repo.insert!(%WritReputationReward{
      writ_id: writ.id,
      faction_id: faction_id,
      amount: rep_attrs["amount"]
    })
  end
end
