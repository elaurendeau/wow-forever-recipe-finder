defmodule WowForeverRecipeFinder.CatalogSeedsTest do
  @moduledoc """
  Guards the committed `priv/catalog_seeds/*.json` files against the
  regression found on 2026-11-16: the original seeds carried Classic-era
  reagent lists (scraped from Warcraft Wiki), Season of Discovery item IDs
  that don't exist in WoW Forever, and wrong reagent item IDs. The seeds are
  now synced to Wowhead's WoW Forever recipe data — see
  docs/DATA_SOURCES.md § Wowhead (WoW Forever recipe data).
  """
  use ExUnit.Case, async: true

  @seed_dir Path.expand("../../priv/catalog_seeds", __DIR__)
  @professions ~w(alchemy enchanting engineering tailoring blacksmithing leatherworking cooking firstaid)
  @tiers ~w(apprentice journeyman expert artisan)
  @sources [nil, "trainer", "vendor", "drop", "quest"]
  @statuses ~w(resolved no_wiki_page reagent_cost_incomplete)

  defp seed(slug), do: @seed_dir |> Path.join("#{slug}.json") |> File.read!() |> Jason.decode!()

  defp pattern!(slug, name) do
    case Enum.filter(seed(slug)["patterns"], &(&1["name"] == name)) do
      [pattern] ->
        pattern

      other ->
        flunk("expected exactly one #{slug} pattern named #{inspect(name)}, got #{length(other)}")
    end
  end

  defp reagent_map(pattern), do: Map.new(pattern["reagents"], &{&1["wowhead_id"], &1["quantity"]})

  for slug <- @professions do
    describe "#{slug}.json structure" do
      test "every pattern has the fields the seeder and schema require" do
        for p <- seed(unquote(slug))["patterns"] do
          assert is_binary(p["name"]) and p["name"] != ""
          assert p["tier"] in @tiers, "bad tier on #{p["name"]}"
          assert is_integer(p["skill"]) and p["skill"] > 0, "bad skill on #{p["name"]}"
          assert p["source"] in @sources, "bad source on #{p["name"]}"
          assert p["resolution_status"] in @statuses, "bad status on #{p["name"]}"
          assert is_binary(p["wiki_slug"]) and p["wiki_slug"] != ""

          for item <- [p["crafted_item"] | p["reagents"]] do
            assert is_integer(item["wowhead_id"])
            assert is_binary(item["display_name"]) and item["display_name"] != ""
            assert is_binary(item["wiki_slug"]) and item["wiki_slug"] != ""
          end

          ids = Enum.map(p["reagents"], & &1["wowhead_id"])

          assert ids == Enum.uniq(ids),
                 "duplicate reagent on #{p["name"]} (violates pattern_reagent unique index)"

          assert Enum.all?(p["reagents"], &(&1["quantity"] >= 1))
        end
      end
    end
  end

  test "an item ID maps to the same display name across every seed file" do
    names =
      for slug <- @professions,
          p <- seed(slug)["patterns"],
          item <- [p["crafted_item"] | p["reagents"]],
          reduce: %{} do
        acc ->
          Map.update(
            acc,
            item["wowhead_id"],
            MapSet.new([item["display_name"]]),
            &MapSet.put(&1, item["display_name"])
          )
      end

    conflicts = for {id, set} <- names, MapSet.size(set) > 1, do: {id, MapSet.to_list(set)}
    assert conflicts == []
  end

  describe "pinned WoW Forever recipes (differ from Classic)" do
    test "Bolt of Runecloth takes 5 Runecloth, not Classic's 4" do
      assert reagent_map(pattern!("tailoring", "Bolt of Runecloth")) == %{14047 => 5}
    end

    test "Enchanted Mageweave Pouch uses real Vision Dust (11137), not the wrong ID 156930" do
      assert reagent_map(pattern!("tailoring", "Enchanted Mageweave Pouch")) ==
               %{4339 => 4, 11137 => 4, 8343 => 2}
    end

    test "Flask of the Titans uses Forever's 30 Gromsblood / 10 Stonescale Oil and a Crystal Vial" do
      assert reagent_map(pattern!("alchemy", "Flask of the Titans")) ==
               %{8846 => 30, 13423 => 10, 13468 => 1, 8925 => 1}
    end

    test "Engineering schematics use Blank Parchment (10648), not the WotLK-era item 39354" do
      assert reagent_map(pattern!("engineering", "Goblin Rocket Fuel Recipe")) == %{
               10648 => 1,
               10647 => 1
             }
    end

    test "Season of Discovery-only items are not in the Forever catalog" do
      crafted_ids =
        for slug <- @professions,
            p <- seed(slug)["patterns"],
            into: MapSet.new(),
            do: p["crafted_item"]["wowhead_id"]

      # Phoenix Bindings, Scarlet Augur's Hood, Soul Vessel, Elixir of Coalesced Regret, Speedstone
      for sod_id <- [210_781, 238_264, 211_427, 210_708, 233_990] do
        refute MapSet.member?(crafted_ids, sod_id), "SoD item #{sod_id} found in a Forever seed"
      end
    end
  end
end
