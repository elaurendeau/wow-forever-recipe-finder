defmodule WowForeverRecipeFinder.CrateShoppingListTest do
  use ExUnit.Case, async: true

  alias WowForeverRecipeFinder.{
    CrateEfficiencyResult,
    CrateShoppingList,
    FillOption,
    WaylaidCrate
  }

  defp crate(opts) do
    %WaylaidCrate{
      id: Keyword.fetch!(opts, :id),
      name: Keyword.get(opts, :name, "Waylaid Crate: Test"),
      tier: :apprentice,
      category: "herbs",
      quality: :common,
      wowhead_id: Keyword.fetch!(opts, :id),
      required_level: 10,
      fill_options: Keyword.get(opts, :fill_options, [])
    }
  end

  defp result(opts) do
    %CrateEfficiencyResult{
      crate: crate(opts),
      crate_cost_copper: Keyword.get(opts, :crate_cost),
      best_fill_option: Keyword.get(opts, :best_fill_option),
      fill_cost_copper: Keyword.get(opts, :fill_cost),
      missing_data_reasons: Keyword.get(opts, :reasons, [])
    }
  end

  test "build_groups/2 returns one group per crate with a non-zero quantity, crate id order" do
    a = result(id: 1, name: "Waylaid Crate: A", crate_cost: 100)
    b = result(id: 2, name: "Waylaid Crate: B", crate_cost: 200)

    groups = CrateShoppingList.build_groups([a, b], %{1 => 3, 2 => 0})

    assert Enum.map(groups, &{&1.crate.name, &1.quantity}) == [{"Waylaid Crate: A", 3}]
  end

  test "each group's lines are the crate (x quantity) then its cheapest fill material (x quantity)" do
    option = %FillOption{display_name: "Peacebloom", wowhead_id: 10, quantity: 20}

    a =
      result(
        id: 1,
        name: "Waylaid Crate: Apprentice Herbs",
        crate_cost: 500,
        best_fill_option: option,
        fill_cost: 1_000
      )

    [group] = CrateShoppingList.build_groups([a], %{1 => 3})

    assert group.lines == [
             %{
               display_name: "Waylaid Crate: Apprentice Herbs",
               quantity: 3,
               unit_price_copper: 500,
               line_total_copper: 1_500
             },
             %{
               display_name: "Peacebloom",
               quantity: 60,
               unit_price_copper: 50,
               line_total_copper: 3_000
             }
           ]
  end

  test "a crate with no resolvable fill option still forms its own group, just with no material line" do
    a =
      result(id: 1, name: "Waylaid Crate: Expert Fabrics", crate_cost: 500, best_fill_option: nil)

    [group] = CrateShoppingList.build_groups([a], %{1 => 2})

    assert group.lines == [
             %{
               display_name: "Waylaid Crate: Expert Fabrics",
               quantity: 2,
               unit_price_copper: 500,
               line_total_copper: 1_000
             }
           ]
  end

  test "a crate with unknown own cost still appears, cost shown as unknown rather than fabricated" do
    a =
      result(
        id: 1,
        name: "Waylaid Crate: Unknown",
        crate_cost: nil,
        reasons: [:missing_crate_recent_value]
      )

    [group] = CrateShoppingList.build_groups([a], %{1 => 1})
    [line] = group.lines

    assert line.unit_price_copper == nil
    assert line.line_total_copper == nil
  end

  test "total_cost_copper/1 is nil, not a partial sum, when any line's cost is unknown" do
    lines = [
      %{display_name: "A", quantity: 1, unit_price_copper: 100, line_total_copper: 100},
      %{display_name: "B", quantity: 1, unit_price_copper: nil, line_total_copper: nil}
    ]

    assert CrateShoppingList.total_cost_copper(lines) == nil
  end

  test "total_cost_copper/1 sums every line across every group, even repeated item names" do
    lines = [
      %{
        display_name: "Peacebloom",
        quantity: 20,
        unit_price_copper: 50,
        line_total_copper: 1_000
      },
      %{display_name: "Peacebloom", quantity: 40, unit_price_copper: 50, line_total_copper: 2_000}
    ]

    assert CrateShoppingList.total_cost_copper(lines) == 3_000
  end

  test "total_cost_copper/1 is 0 for an empty list" do
    assert CrateShoppingList.total_cost_copper([]) == 0
  end

  test "to_auctionator_text/2 matches Auctionator's real Shopping List format: *** header then one name per line, no quantities" do
    lines = [
      %{
        display_name: "Waylaid Crate: Apprentice Herbs",
        quantity: 3,
        unit_price_copper: 500,
        line_total_copper: 1_500
      },
      %{display_name: "Peacebloom", quantity: 60, unit_price_copper: 50, line_total_copper: 3_000}
    ]

    text = CrateShoppingList.to_auctionator_text("WoW Forever Crates", lines)

    assert text == "*** WoW Forever Crates\nWaylaid Crate: Apprentice Herbs\nPeacebloom\n"
    refute text =~ "60"
    refute text =~ "3"
  end
end
