defmodule WowForeverRecipeFinder.WritMapPlacementTest do
  @moduledoc """
  Pure placement/grouping tests against a small, real-shaped
  `WorldMap` (no gateway, no I/O) — per docs/ELIXIR_TEST_MANIFESTO.md
  § What Still Gets a Plain Unit Test.
  """
  use ExUnit.Case, async: true

  alias WowForeverRecipeFinder.{
    WorldMap,
    Writ,
    WritEfficiencyResult,
    WritHandIn,
    WritMapPlacement
  }

  @world_map %WorldMap{
    continents: [],
    towns: [],
    zones: [
      %{
        area: 14,
        name: "Durotar",
        continent: "kalimdor",
        label: {20_806, 16_340},
        rect: {{18_268, 14_648}, {23_344, 18_032}},
        polygons: []
      }
    ]
  }

  defp result(name, hand_in) do
    writ = %Writ{
      name: name,
      wowhead_quest_id: 90_000,
      writ_item_wowhead_id: 1,
      writ_item_display_name: name,
      profession_slugs: ["alchemy"],
      tier: :journeyman,
      reward_money_copper: 0,
      resolution_status: :complete,
      required_items: [],
      reputation_rewards: [],
      hand_in: hand_in
    }

    %WritEfficiencyResult{writ: writ, total_reputation: 75, missing_data_reasons: []}
  end

  describe "placed?/2 and the placed/unplaced split" do
    test "a hand-in with a known zone_id and coordinates is placed" do
      placed =
        result("Placed", %WritHandIn{
          zone_id: 14,
          npc_name: "Sos'mol",
          way_x: 40.8,
          way_y: 28.0,
          friendly_to: []
        })

      assert WritMapPlacement.placed?(placed, @world_map)
    end

    test "a hand-in with no zone_id at all is not placed" do
      unplaced = result("Unplaced", %WritHandIn{friendly_to: []})

      refute WritMapPlacement.placed?(unplaced, @world_map)
    end

    test "a hand-in whose zone_id has no matching rect on the map is not placed" do
      no_rect =
        result("No rect", %WritHandIn{zone_id: 999_999, way_x: 1.0, way_y: 1.0, friendly_to: []})

      refute WritMapPlacement.placed?(no_rect, @world_map)
    end

    test "placed_results/2 and unplaced_results/2 partition the list without dropping anything" do
      placed =
        result("Placed", %WritHandIn{zone_id: 14, way_x: 50.0, way_y: 50.0, friendly_to: []})

      unplaced = result("Unplaced", %WritHandIn{friendly_to: []})

      assert WritMapPlacement.placed_results([placed, unplaced], @world_map) == [placed]
      assert WritMapPlacement.unplaced_results([placed, unplaced], @world_map) == [unplaced]
    end
  end

  describe "hand_in_pins/2" do
    test "places a hand-in on the canvas from its zone rectangle (Durotar's real rect; Sos'mol's real 40.8/28)" do
      # Durotar's rect is {{18268,14648},{23344,18032}} — a 5076 x 3384
      # box; 40.8%/28% in should land here.
      placed =
        result("Steel Weapon Chain", %WritHandIn{
          npc_id: 257_281,
          npc_name: "Sos'mol",
          zone: "Durotar",
          zone_id: 14,
          way_x: 40.8,
          way_y: 28.0,
          friendly_to: [:horde]
        })

      [pin] = WritMapPlacement.hand_in_pins([placed], @world_map)

      assert_in_delta pin.x, 18_268 + 5076 * 0.408, 0.01
      assert_in_delta pin.y, 14_648 + 3384 * 0.28, 0.01
      assert pin.id == "npc-257281"
      assert pin.npc_name == "Sos'mol"
      assert pin.friendly_to == [:horde]
    end

    test "two writs at the same NPC share one pin, carrying both results" do
      same_npc = %WritHandIn{npc_id: 1, zone_id: 14, way_x: 10.0, way_y: 10.0, friendly_to: []}
      a = result("A writ", same_npc)
      b = result("B writ", same_npc)

      assert [pin] = WritMapPlacement.hand_in_pins([a, b], @world_map)
      assert Enum.map(pin.results, & &1.writ.name) |> Enum.sort() == ["A writ", "B writ"]
    end

    test "a hand-in with coordinates but no NPC id still gets its own pin, keyed by zone + spot" do
      no_npc_id =
        result("Container writ", %WritHandIn{
          zone_id: 14,
          way_x: 12.5,
          way_y: 33.0,
          friendly_to: []
        })

      assert [pin] = WritMapPlacement.hand_in_pins([no_npc_id], @world_map)
      assert pin.id == "spot-14-12.5-33.0"
      assert pin.npc_name == nil
    end

    test "an unplaced hand-in (no zone_id) never appears as a pin" do
      unplaced = result("Unplaced", %WritHandIn{friendly_to: []})

      assert WritMapPlacement.hand_in_pins([unplaced], @world_map) == []
    end

    test "pins are sorted by zone then NPC name" do
      z_npc =
        result("Z writ", %WritHandIn{
          npc_id: 1,
          zone: "Zzz",
          zone_id: 14,
          way_x: 1.0,
          way_y: 1.0,
          friendly_to: []
        })

      a_npc =
        result("A writ", %WritHandIn{
          npc_id: 2,
          zone: "Aaa",
          zone_id: 14,
          way_x: 1.0,
          way_y: 1.0,
          friendly_to: []
        })

      pins = WritMapPlacement.hand_in_pins([z_npc, a_npc], @world_map)

      assert Enum.map(pins, & &1.zone) == ["Aaa", "Zzz"]
    end
  end

  describe "waypoint_command/1" do
    test ~S|formats a /way command, trimming a whole-number coordinate to an integer| do
      pin = %{zone: "Dustwallow Marsh", way_x: 40.8, way_y: 28.0}

      assert WritMapPlacement.waypoint_command(pin) == "/way Dustwallow Marsh 40.8 28"
    end
  end
end
