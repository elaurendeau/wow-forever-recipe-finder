defmodule WowForeverRecipeFinder.WritShoppingListTest do
  use ExUnit.Case, async: true

  alias WowForeverRecipeFinder.{Writ, WritEfficiencyResult, WritShoppingList}

  # Pure-function unit tests per docs/ELIXIR_TEST_MANIFESTO.md § What
  # Still Gets a Plain Unit Test.

  defp writ(opts) do
    %Writ{
      id: Keyword.fetch!(opts, :id),
      name: Keyword.get(opts, :name, "Craftsman's Writ: Test"),
      wowhead_quest_id: 90_000,
      writ_item_wowhead_id: 1,
      writ_item_display_name: Keyword.get(opts, :writ_item_display_name, "Writ Item"),
      profession_slugs: ["alchemy"],
      tier: :journeyman,
      reward_money_copper: 0,
      resolution_status: :complete,
      required_items: [],
      reputation_rewards: []
    }
  end

  defp result(opts) do
    %WritEfficiencyResult{
      writ: writ(opts),
      writ_item_cost_copper: Keyword.get(opts, :writ_item_cost),
      total_reputation: Keyword.get(opts, :reputation, 75),
      missing_data_reasons: [],
      required_item_breakdown: Keyword.get(opts, :required_item_breakdown, [])
    }
  end

  test "build/2 includes the writ item and required items only for selected writs" do
    selected =
      result(
        id: 1,
        writ_item_display_name: "Craftsman's Writ: Elixir of Ogre's Strength",
        writ_item_cost: 300,
        required_item_breakdown: [
          %{
            display_name: "Elixir of Ogre Strength",
            quantity: 1,
            unit_price_copper: 300,
            line_total_copper: 300
          }
        ]
      )

    unselected =
      result(id: 2, writ_item_display_name: "Craftsman's Writ: Unselected", writ_item_cost: 999)

    lines = WritShoppingList.build([selected, unselected], MapSet.new([1]))

    assert Enum.map(lines, & &1.display_name) == [
             "Craftsman's Writ: Elixir of Ogre's Strength",
             "Elixir of Ogre Strength"
           ]

    refute Enum.any?(lines, &(&1.display_name == "Craftsman's Writ: Unselected"))
  end

  test "build/2 sums quantities when two selected writs need the same item name" do
    a =
      result(
        id: 1,
        writ_item_display_name: "Craftsman's Writ: A",
        writ_item_cost: 100,
        required_item_breakdown: [
          %{
            display_name: "Thorium Bar",
            quantity: 2,
            unit_price_copper: 50,
            line_total_copper: 100
          }
        ]
      )

    b =
      result(
        id: 2,
        writ_item_display_name: "Craftsman's Writ: B",
        writ_item_cost: 100,
        required_item_breakdown: [
          %{
            display_name: "Thorium Bar",
            quantity: 5,
            unit_price_copper: 50,
            line_total_copper: 250
          }
        ]
      )

    lines = WritShoppingList.build([a, b], MapSet.new([1, 2]))
    thorium = Enum.find(lines, &(&1.display_name == "Thorium Bar"))

    assert thorium.quantity == 7
    assert thorium.line_total_copper == 350
  end

  test "build/2 keeps an item on the list even when its cost is unknown, never dropping it" do
    pending =
      result(
        id: 1,
        writ_item_display_name: "Craftsman's Writ: Pending",
        writ_item_cost: nil,
        required_item_breakdown: [
          %{
            display_name: "Mystery Item",
            quantity: 1,
            unit_price_copper: nil,
            line_total_copper: nil
          }
        ]
      )

    lines = WritShoppingList.build([pending], MapSet.new([1]))
    mystery = Enum.find(lines, &(&1.display_name == "Mystery Item"))

    assert mystery.quantity == 1
    assert mystery.line_total_copper == nil
  end

  test "total_cost_copper/1 is nil, not a partial sum, when any line's cost is unknown" do
    lines = [
      %{display_name: "A", quantity: 1, unit_price_copper: 100, line_total_copper: 100},
      %{display_name: "B", quantity: 1, unit_price_copper: nil, line_total_copper: nil}
    ]

    assert WritShoppingList.total_cost_copper(lines) == nil
  end

  test "total_cost_copper/1 sums every line when all costs are known" do
    lines = [
      %{display_name: "A", quantity: 1, unit_price_copper: 100, line_total_copper: 100},
      %{display_name: "B", quantity: 2, unit_price_copper: 50, line_total_copper: 100}
    ]

    assert WritShoppingList.total_cost_copper(lines) == 200
  end

  test "total_cost_copper/1 is 0 for an empty list" do
    assert WritShoppingList.total_cost_copper([]) == 0
  end

  test "total_reputation/2 sums only selected writs' reputation" do
    a = result(id: 1, reputation: 75)
    b = result(id: 2, reputation: 150)

    assert WritShoppingList.total_reputation([a, b], MapSet.new([1])) == 75
    assert WritShoppingList.total_reputation([a, b], MapSet.new([1, 2])) == 225
    assert WritShoppingList.total_reputation([a, b], MapSet.new()) == 0
  end

  test "to_auctionator_text/2 matches Auctionator's real Shopping List format: *** header then one name per line, no quantities" do
    lines = [
      %{
        display_name: "Dark Iron Ore",
        quantity: 20,
        unit_price_copper: 100,
        line_total_copper: 2_000
      },
      %{display_name: "Thorium Bar", quantity: 7, unit_price_copper: 50, line_total_copper: 350}
    ]

    text = WritShoppingList.to_auctionator_text("WoW Forever Writs", lines)

    assert text == "*** WoW Forever Writs\nDark Iron Ore\nThorium Bar\n"
    refute text =~ "20"
    refute text =~ "7"
  end
end
