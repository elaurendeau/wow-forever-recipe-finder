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

  test "build_groups/2 returns one group per selected writ, numbered in selection order" do
    a = result(id: 1, name: "Craftsman's Writ: A")
    b = result(id: 2, name: "Craftsman's Writ: B")
    c = result(id: 3, name: "Craftsman's Writ: C")

    # Selected B first, then A — numbering follows selection order, not writ id.
    groups = WritShoppingList.build_groups([a, b, c], [2, 1])

    assert Enum.map(groups, &{&1.number, &1.writ.name}) == [
             {1, "Craftsman's Writ: B"},
             {2, "Craftsman's Writ: A"}
           ]
  end

  test "build_groups/2 excludes unselected writs" do
    selected = result(id: 1, name: "Craftsman's Writ: Selected")
    unselected = result(id: 2, name: "Craftsman's Writ: Unselected")

    groups = WritShoppingList.build_groups([selected, unselected], [1])

    assert length(groups) == 1
    assert hd(groups).writ.name == "Craftsman's Writ: Selected"
  end

  test "each group's lines are the writ item followed by its required items, never merged with another writ's" do
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
        writ_item_cost: 200,
        required_item_breakdown: [
          %{
            display_name: "Thorium Bar",
            quantity: 5,
            unit_price_copper: 50,
            line_total_copper: 250
          }
        ]
      )

    [group_a, group_b] = WritShoppingList.build_groups([a, b], [1, 2])

    # Both groups independently list "Thorium Bar" with their OWN
    # writ's quantity — not summed into one shared line.
    assert group_a.lines == [
             %{
               display_name: "Craftsman's Writ: A",
               quantity: 1,
               unit_price_copper: 100,
               line_total_copper: 100
             },
             %{
               display_name: "Thorium Bar",
               quantity: 2,
               unit_price_copper: 50,
               line_total_copper: 100
             }
           ]

    assert group_b.lines == [
             %{
               display_name: "Craftsman's Writ: B",
               quantity: 1,
               unit_price_copper: 200,
               line_total_copper: 200
             },
             %{
               display_name: "Thorium Bar",
               quantity: 5,
               unit_price_copper: 50,
               line_total_copper: 250
             }
           ]
  end

  test "a group's lines still appear even when the writ's cost is unknown, never dropped" do
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

    [group] = WritShoppingList.build_groups([pending], [1])
    mystery = Enum.find(group.lines, &(&1.display_name == "Mystery Item"))

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

  test "total_cost_copper/1 sums every line across every group, even repeated item names" do
    lines = [
      %{display_name: "Thorium Bar", quantity: 2, unit_price_copper: 50, line_total_copper: 100},
      %{display_name: "Thorium Bar", quantity: 5, unit_price_copper: 50, line_total_copper: 250}
    ]

    assert WritShoppingList.total_cost_copper(lines) == 350
  end

  test "total_cost_copper/1 is 0 for an empty list" do
    assert WritShoppingList.total_cost_copper([]) == 0
  end

  test "total_reputation/2 sums only selected writs' reputation, in no particular order" do
    a = result(id: 1, reputation: 75)
    b = result(id: 2, reputation: 150)

    assert WritShoppingList.total_reputation([a, b], [1]) == 75
    assert WritShoppingList.total_reputation([a, b], [2, 1]) == 225
    assert WritShoppingList.total_reputation([a, b], []) == 0
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

  test "to_auctionator_text/2 lists a repeated item name only once, across groups" do
    lines = [
      %{display_name: "Thorium Bar", quantity: 2, unit_price_copper: 50, line_total_copper: 100},
      %{display_name: "Thorium Bar", quantity: 5, unit_price_copper: 50, line_total_copper: 250}
    ]

    assert WritShoppingList.to_auctionator_text("WoW Forever Writs", lines) ==
             "*** WoW Forever Writs\nThorium Bar\n"
  end
end
