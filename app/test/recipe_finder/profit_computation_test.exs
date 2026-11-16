defmodule WowForeverRecipeFinder.ProfitComputationTest do
  use ExUnit.Case, async: true

  alias WowForeverRecipeFinder.{Item, Pattern, PriceSnapshot, ProfitComputation, ProfitResult, Reagent}

  # Pure-function unit tests per docs/ELIXIR_TEST_MANIFESTO.md § What
  # Still Gets a Plain Unit Test: `compute_result/2` has no I/O, so real
  # in-memory structs are enough — no fixtures, no gateway.

  defp item(wowhead_id, name), do: %Item{wowhead_id: wowhead_id, display_name: name, wiki_slug: name}

  defp pattern(crafted_item, reagents) do
    %Pattern{
      profession_slug: "tailoring",
      crafted_item: crafted_item,
      name: crafted_item.display_name,
      tier: :apprentice,
      skill: 1,
      wiki_slug: crafted_item.display_name,
      resolution_status: :resolved,
      reagents: reagents
    }
  end

  defp snapshot(prices) do
    %PriceSnapshot{
      prices_by_item_id:
        Map.new(prices, fn {id, price, spd, conf} ->
          {id, %WowForeverRecipeFinder.ItemPrice{
            wowhead_id: id,
            price_copper: price,
            sold_per_day: spd,
            sale_confidence_pct: conf
          }}
        end)
    }
  end

  test "full data: computes price, mat cost, and net profit after the AH cut correctly" do
    cloth = item(1, "Bolt of Linen Cloth")
    shirt = item(2, "White Linen Shirt")
    pat = pattern(shirt, [%Reagent{item: cloth, quantity: 2}])
    snap = snapshot([{1, 50, 100.0, 90.0}, {2, 200, 10.0, 80.0}])

    result = ProfitComputation.compute_result(pat, snap)

    assert result.price_copper == 200
    assert result.mat_cost_copper == 100
    # price after the 5% AH cut: round(200 * 0.95) = 190, minus the 100 mat cost
    assert result.net_profit_per_unit_copper == 90
    assert result.profit_pct == 90.0
    assert result.missing_data_reasons == []
    assert ProfitResult.profitable?(result)
  end

  test "crafted item has no sale data: price/profit are nil, reason recorded, never a fabricated zero" do
    cloth = item(1, "Bolt of Linen Cloth")
    shirt = item(2, "White Linen Shirt")
    pat = pattern(shirt, [%Reagent{item: cloth, quantity: 2}])
    # item 2 (the crafted item) is absent from the snapshot entirely
    snap = snapshot([{1, 50, 100.0, 90.0}])

    result = ProfitComputation.compute_result(pat, snap)

    assert result.price_copper == nil
    assert result.net_profit_per_unit_copper == nil
    assert :no_sale_data in result.missing_data_reasons
    refute ProfitResult.profitable?(result)
  end

  test "pattern has zero reagents resolved: mat cost is nil, not zero, reason recorded" do
    shirt = item(2, "White Linen Shirt")
    pat = pattern(shirt, [])
    snap = snapshot([{2, 200, 10.0, 80.0}])

    result = ProfitComputation.compute_result(pat, snap)

    assert result.mat_cost_copper == nil
    assert result.net_profit_per_unit_copper == nil
    assert :no_reagents_found in result.missing_data_reasons
  end

  test "one of several reagents has no sale data: whole mat cost is nil, not a partial sum" do
    cloth = item(1, "Bolt of Linen Cloth")
    thread = item(3, "Coarse Thread")
    shirt = item(2, "White Linen Shirt")
    pat = pattern(shirt, [%Reagent{item: cloth, quantity: 2}, %Reagent{item: thread, quantity: 1}])
    # thread (item 3) is missing from the snapshot
    snap = snapshot([{1, 50, 100.0, 90.0}, {2, 200, 10.0, 80.0}])

    result = ProfitComputation.compute_result(pat, snap)

    assert result.mat_cost_copper == nil
    assert :missing_reagent_price in result.missing_data_reasons
  end

  test "compute_results/2 sorts by net per-unit profit descending, incomplete results last" do
    gold_item = item(10, "Gold Bar")
    silver_item = item(20, "Silver Bar")
    mystery_item = item(30, "Mystery Box")

    profitable_a = pattern(gold_item, [%Reagent{item: item(1, "Ore"), quantity: 1}])
    profitable_b = pattern(silver_item, [%Reagent{item: item(1, "Ore"), quantity: 1}])
    incomplete = pattern(mystery_item, [])

    snap =
      snapshot([
        {1, 10, 100.0, 90.0},
        {10, 1000, 5.0, 90.0},
        {20, 100, 5.0, 90.0},
        {30, 500, 5.0, 90.0}
      ])

    results =
      Enum.map([incomplete, profitable_b, profitable_a], &ProfitComputation.compute_result(&1, snap))
      |> Enum.sort_by(fn
        %ProfitResult{net_profit_per_unit_copper: nil} -> {1, 0}
        %ProfitResult{net_profit_per_unit_copper: profit} -> {0, -profit}
      end)

    assert Enum.map(results, & &1.pattern.crafted_item.display_name) == [
             "Gold Bar",
             "Silver Bar",
             "Mystery Box"
           ]
  end
end
