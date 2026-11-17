defmodule WowForeverRecipeFinder.WritCatalogSeederTest do
  @moduledoc """
  Integration test against the real sandboxed Postgres DB — no mocks
  at this boundary, per docs/ELIXIR_TEST_MANIFESTO.md. Loads the real
  committed fixture (test/fixtures/writs/sample_writs.json) through
  the actual seeder and the actual Ecto-backed gateway, proving the
  full round trip rather than asserting against raw JSON shape alone
  (that's catalog_seeds_test.exs's job for the profession catalogs).
  """
  use WowForeverRecipeFinder.DataCase, async: true

  alias WowForeverRecipeFinder.Gateways.EctoWritRepositoryGateway
  alias WowForeverRecipeFinder.{ReputationReward, Writ, WritCatalogSeeder, WritRequiredItem}

  @fixture_path Path.join([__DIR__, "..", "fixtures", "writs", "sample_writs.json"])

  defp writ!(writs, name),
    do: Enum.find(writs, &(&1.name == name)) || flunk("no writ named #{inspect(name)}")

  test "loads every writ, required item, and reputation reward from the real fixture file" do
    :ok = WritCatalogSeeder.load_from_file!(@fixture_path)

    writs = EctoWritRepositoryGateway.list_writs()
    assert length(writs) == 3

    complete = writ!(writs, "Craftsman's Writ: Elixir of Ogre's Strength")
    assert %Writ{resolution_status: :complete, tier: :journeyman, repeat: "daily"} = complete
    assert complete.profession_slugs == ["alchemy"]
    assert complete.hand_in.npc_id == 257_281
    assert complete.hand_in.npc_name == "Sos'mol"
    assert complete.hand_in.zone == "Alterac Mountains"
    assert complete.hand_in.zone_id == 36
    assert complete.hand_in.way_x == 38.4
    assert complete.hand_in.way_y == 61.2
    assert complete.hand_in.friendly_to == [:alliance, :horde]

    assert complete.required_items == [
             %WritRequiredItem{
               wowhead_id: 264_031,
               display_name: "Elixir of Ogre Strength",
               quantity: 1
             }
           ]

    assert Enum.sort_by(complete.reputation_rewards, & &1.faction_display_name) == [
             %ReputationReward{faction_display_name: "Azeroth Commerce Authority", amount: 75},
             %ReputationReward{faction_display_name: "Durotar Supply and Logistics", amount: 75}
           ]
  end

  test "a pending_quest_page writ is loaded too, never dropped, with an empty required_items list" do
    :ok = WritCatalogSeeder.load_from_file!(@fixture_path)

    pending = writ!(EctoWritRepositoryGateway.list_writs(), "Craftsman's Writ: Heavy Bronze Mace")

    assert pending.resolution_status == :pending_quest_page
    assert pending.required_items == []
    assert pending.repeat == nil
    assert pending.hand_in.npc_name == "Gorgrash"
    assert pending.hand_in.way_x == nil
    assert pending.hand_in.friendly_to == []
  end

  test "a hand-in reported hostile to one faction and friendly to the other keeps both, not collapsed" do
    :ok = WritCatalogSeeder.load_from_file!(@fixture_path)

    rocket_fuel =
      writ!(EctoWritRepositoryGateway.list_writs(), "Craftsman's Writ: Goblin Rocket Fuel")

    # Wowhead reaction: 1 friendly, 0 neutral, -1 hostile — only
    # strictly-friendly factions are listed; -1 (Alliance here) is
    # excluded the same way 0/neutral would be.
    assert rocket_fuel.hand_in.friendly_to == [:horde]
  end

  test "a writ listing more than one profession keeps the full set" do
    :ok = WritCatalogSeeder.load_from_file!(@fixture_path)

    rocket_fuel =
      writ!(EctoWritRepositoryGateway.list_writs(), "Craftsman's Writ: Goblin Rocket Fuel")

    assert rocket_fuel.profession_slugs == ["alchemy", "engineering"]
  end

  test "re-running the seeder replaces the catalog atomically rather than duplicating rows" do
    :ok = WritCatalogSeeder.load_from_file!(@fixture_path)
    :ok = WritCatalogSeeder.load_from_file!(@fixture_path)

    writs = EctoWritRepositoryGateway.list_writs()
    assert length(writs) == 3

    assert Repo.aggregate(WowForeverRecipeFinder.Gateways.Schema.Faction, :count) == 2
  end
end
