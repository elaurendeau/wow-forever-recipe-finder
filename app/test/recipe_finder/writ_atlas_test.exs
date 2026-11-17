defmodule WowForeverRecipeFinder.WritAtlasTest do
  @moduledoc """
  docs/PRD.md § 7.8, against the real committed data in priv/writs and
  priv/world_map (local files, no network) — the same files the page
  ships with, so a data refresh that breaks a use case fails here.
  """
  use ExUnit.Case, async: true

  alias WowForeverRecipeFinder.WritAtlas

  setup_all do
    {:ok, atlas} = WritAtlas.load_atlas()
    %{writs: atlas.writs, world_map: atlas.world_map}
  end

  defp criteria(overrides), do: Map.merge(WritAtlas.default_criteria(), Map.new(overrides))
  defp writ_named(writs, name), do: Enum.find(writs, &(&1.name == name))

  describe "load_atlas/0" do
    test "loads all 150 writs and the vector map", %{writs: writs, world_map: world_map} do
      assert length(writs) == 150
      assert Enum.map(world_map.continents, & &1.key) |> Enum.sort() == ["eastern-kingdoms", "kalimdor", "zephras-isle"]
      assert Enum.any?(world_map.zones, &(&1.name == "Dustwallow Marsh"))
    end

    test "normalizes a writ: short name, tier, profession, required item, skill, one faction's reputation",
         %{writs: writs} do
      writ = writ_named(writs, "Steel Weapon Chain")

      assert writ.tier == :expert
      assert writ.professions == ["blacksmithing"]
      assert writ.quest_id == 94_270
      assert [%{display_name: "Steel Weapon Chain", quantity: 1, skill: 190, wowhead_id: 6041}] = writ.required_items
      assert writ.rewards.reputation == 125
      assert writ.rewards.money_copper == 0
      assert writ.hand_in.npc_name == "Ugbert"
      assert writ.hand_in.friendly_to == [:horde]
    end

    test "places a hand-in on the canvas from its zone rectangle", %{writs: writs} do
      # Dustwallow Marsh's rect is [[17320, 18336], [22360, 21696]]; Ugbert is at 40.8, 28.
      hand_in = writ_named(writs, "Steel Weapon Chain").hand_in

      assert_in_delta hand_in.canvas_x, 17_320 + 5040 * 0.408, 0.01
      assert_in_delta hand_in.canvas_y, 18_336 + 3360 * 0.28, 0.01
    end

    test "a writ with no known hand-in stays unplaced instead of being dropped", %{writs: writs} do
      writ = writ_named(writs, "Dark Iron Bomb")

      refute WritAtlas.placed?(writ)
      assert writ.hand_in.canvas_x == nil
    end
  end

  describe "placed / unplaced split" do
    test "122 writs are on the map and 28 are not", %{writs: writs} do
      assert length(WritAtlas.placed_writs(writs, criteria([]))) == 122
      assert length(WritAtlas.unplaced_writs(writs, criteria([]))) == 28
    end

    test "filters still apply to unplaced writs", %{writs: writs} do
      unplaced = WritAtlas.unplaced_writs(writs, criteria(search: "dark iron bomb"))

      assert Enum.map(unplaced, & &1.name) == ["Dark Iron Bomb"]
    end
  end

  describe "filter_writs/2" do
    test "profession filter; a two-profession writ matches either", %{writs: writs} do
      leatherworking = WritAtlas.filter_writs(writs, criteria(professions: MapSet.new(["leatherworking"])))
      tailoring = WritAtlas.filter_writs(writs, criteria(professions: MapSet.new(["tailoring"])))

      assert writ_named(leatherworking, "Gordok Ogre Suit")
      assert writ_named(tailoring, "Gordok Ogre Suit")
      assert length(tailoring) == 31
    end

    test "tier filter", %{writs: writs} do
      artisan = WritAtlas.filter_writs(writs, criteria(tiers: MapSet.new([:artisan])))

      assert length(artisan) == 45
      assert Enum.all?(artisan, &(&1.tier == :artisan))
    end

    test "search matches NPC name, case-insensitive and trimmed", %{writs: writs} do
      assert [%{name: "Steel Weapon Chain"}] = WritAtlas.filter_writs(writs, criteria(search: "  UGBERT "))
    end

    test "search matches the required item and the zone", %{writs: writs} do
      assert writ_named(WritAtlas.filter_writs(writs, criteria(search: "steel weapon")), "Steel Weapon Chain")
      dustwallow = WritAtlas.filter_writs(writs, criteria(search: "dustwallow"))
      assert Enum.all?(dustwallow, &(&1.hand_in.zone == "Dustwallow Marsh"))
    end

    test "empty filters return everything", %{writs: writs} do
      assert length(WritAtlas.filter_writs(writs, criteria([]))) == 150
    end
  end

  describe "hand_in_pins/2" do
    test "one pin per hand-in NPC", %{writs: writs} do
      assert length(WritAtlas.hand_in_pins(writs, criteria([]))) == 84
    end

    test "faction filter hides NPCs that aren't friendly to that faction", %{writs: writs} do
      alliance = WritAtlas.hand_in_pins(writs, criteria(side: :alliance))
      horde = WritAtlas.hand_in_pins(writs, criteria(side: :horde))

      assert length(alliance) == 59
      assert length(horde) == 60
      refute WritAtlas.find_pin(alliance, "npc-270919")
      assert WritAtlas.find_pin(horde, "npc-270919")
    end

    test "a pin's writ count follows the filters; an NPC with no matching writ has no pin", %{writs: writs} do
      pins = WritAtlas.hand_in_pins(writs, criteria(professions: MapSet.new(["tailoring"])))

      refute WritAtlas.find_pin(pins, "npc-270919")
      assert Enum.sum(Enum.map(pins, &length(&1.writs))) == 24
    end

    test "a hand-in with coordinates but no NPC still gets its own pin", %{writs: writs} do
      writ = writ_named(writs, "Silver Skeleton Key")
      pin = WritAtlas.find_pin(WritAtlas.hand_in_pins(writs, criteria([])), WritAtlas.pin_id_for(writ))

      assert pin.npc_name == nil
      assert Enum.map(pin.writs, & &1.name) == ["Silver Skeleton Key"]
    end
  end

  describe "group_by_zone/1 and counts" do
    test "zones come out alphabetical", %{writs: writs} do
      zones = writs |> WritAtlas.placed_writs(criteria([])) |> WritAtlas.group_by_zone() |> Enum.map(&elem(&1, 0))

      assert Enum.take(zones, 3) == ["Alterac Mountains", "Arathi Highlands", "Ashenvale"]
      assert zones == Enum.sort(zones)
    end

    test "a two-profession writ counts for both professions", %{writs: writs} do
      counts = WritAtlas.profession_counts(writs)

      assert counts["tailoring"] == 31
      assert counts |> Map.values() |> Enum.sum() == 151
    end
  end

  describe "waypoint_command/1" do
    test "formats whole and fractional coordinates the way /way expects" do
      assert WritAtlas.waypoint_command(%{zone: "Dustwallow Marsh", way_x: 40.8, way_y: 28.0}) ==
               "/way Dustwallow Marsh 40.8 28"
    end
  end
end
