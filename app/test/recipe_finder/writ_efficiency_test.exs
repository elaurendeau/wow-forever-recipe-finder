defmodule WowForeverRecipeFinder.WritEfficiencyTest do
  use ExUnit.Case, async: true

  alias WowForeverRecipeFinder.{
    ItemPrice,
    PriceSnapshot,
    ReputationReward,
    Writ,
    WritEfficiency,
    WritRequiredItem
  }

  # Pure-function unit tests per docs/ELIXIR_TEST_MANIFESTO.md § What
  # Still Gets a Plain Unit Test: `compute_result/2` has no I/O, so real
  # in-memory structs are enough — no fixtures, no gateway.

  defp required_item(wowhead_id, quantity \\ 1) do
    %WritRequiredItem{
      wowhead_id: wowhead_id,
      display_name: "Required Item #{wowhead_id}",
      quantity: quantity
    }
  end

  defp reward(faction, amount),
    do: %ReputationReward{faction_display_name: faction, amount: amount}

  defp writ(opts) do
    %Writ{
      name: Keyword.get(opts, :name, "Craftsman's Writ: Test"),
      wowhead_quest_id: Keyword.get(opts, :wowhead_quest_id, 90_000),
      writ_item_wowhead_id: Keyword.fetch!(opts, :writ_item_wowhead_id),
      writ_item_display_name: "Writ Item",
      profession_slugs: Keyword.get(opts, :profession_slugs, ["alchemy"]),
      tier: Keyword.get(opts, :tier, :journeyman),
      repeat: Keyword.get(opts, :repeat, "daily"),
      reward_money_copper: Keyword.get(opts, :reward_money_copper, 0),
      resolution_status: Keyword.get(opts, :resolution_status, :complete),
      required_items: Keyword.get(opts, :required_items, []),
      reputation_rewards:
        Keyword.get(opts, :reputation_rewards, [reward("Azeroth Commerce Authority", 75)])
    }
  end

  defp snapshot(prices) do
    %PriceSnapshot{
      prices_by_item_id:
        Map.new(prices, fn {id, recent_value} ->
          {id,
           %ItemPrice{
             wowhead_id: id,
             # price_copper deliberately set far from recent_value in every
             # test below — proves compute_result/2 never reads it at all.
             price_copper: 999_999,
             sold_per_day: 1.0,
             sale_confidence_pct: 50.0,
             recent_value_copper: recent_value
           }}
        end)
    }
  end

  test "full data: total cost is writ item + required items, both at Recent Value, never region Sale Avg" do
    w =
      writ(
        writ_item_wowhead_id: 1,
        required_items: [required_item(2, 1)],
        reputation_rewards: [
          reward("Azeroth Commerce Authority", 75),
          reward("Durotar Supply and Logistics", 75)
        ]
      )

    snap = snapshot([{1, 300}, {2, 300}])

    result = WritEfficiency.compute_result(w, snap)

    assert result.writ_item_cost_copper == 300
    assert result.required_items_cost_copper == 300
    assert result.total_cost_copper == 600
    assert result.total_reputation == 150
    # 150 rep / (600 copper / 10_000 copper-per-gold) = 150 / 0.06 = 2500.0
    assert_in_delta result.rep_per_gold, 2500.0, 0.0001
    assert result.missing_data_reasons == []

    assert result.required_item_breakdown == [
             %{
               display_name: "Required Item 2",
               quantity: 1,
               unit_price_copper: 300,
               line_total_copper: 300
             }
           ]
  end

  test "a required item needed more than once multiplies its unit Recent Value by quantity" do
    w = writ(writ_item_wowhead_id: 1, required_items: [required_item(2, 3)])
    snap = snapshot([{1, 100}, {2, 50}])

    result = WritEfficiency.compute_result(w, snap)

    assert result.required_items_cost_copper == 150
    assert result.total_cost_copper == 250
  end

  test "more than one required item: the tooltip breakdown shows each line independently, even if one is missing a price" do
    w = writ(writ_item_wowhead_id: 1, required_items: [required_item(2, 2), required_item(3, 1)])
    # item 3 is missing from the snapshot
    snap = snapshot([{1, 100}, {2, 50}])

    result = WritEfficiency.compute_result(w, snap)

    assert result.required_items_cost_copper == nil
    assert :missing_required_item_recent_value in result.missing_data_reasons

    assert result.required_item_breakdown == [
             %{
               display_name: "Required Item 2",
               quantity: 2,
               unit_price_copper: 50,
               line_total_copper: 100
             },
             %{
               display_name: "Required Item 3",
               quantity: 1,
               unit_price_copper: nil,
               line_total_copper: nil
             }
           ]
  end

  test "resolution_status: pending_quest_page never costs the writ as free — required_items cost is nil with a reason" do
    w = writ(writ_item_wowhead_id: 1, resolution_status: :pending_quest_page, required_items: [])
    snap = snapshot([{1, 300}])

    result = WritEfficiency.compute_result(w, snap)

    assert result.writ_item_cost_copper == 300
    assert result.required_items_cost_copper == nil
    assert result.total_cost_copper == nil
    assert result.rep_per_gold == nil
    assert :no_required_items_data in result.missing_data_reasons
  end

  test "resolution_status: complete with an empty required_items list is treated the same as pending, not as free" do
    w = writ(writ_item_wowhead_id: 1, resolution_status: :complete, required_items: [])
    snap = snapshot([{1, 300}])

    result = WritEfficiency.compute_result(w, snap)

    assert result.total_cost_copper == nil
    assert :no_required_items_data in result.missing_data_reasons
  end

  test "writ item has no Recent Value in the uploaded snapshot: cost is nil, reason recorded, never a fabricated zero" do
    w = writ(writ_item_wowhead_id: 1, required_items: [required_item(2)])
    # item 1 (the writ item) is absent from the snapshot entirely
    snap = snapshot([{2, 300}])

    result = WritEfficiency.compute_result(w, snap)

    assert result.writ_item_cost_copper == nil
    assert result.total_cost_copper == nil
    assert :missing_writ_item_recent_value in result.missing_data_reasons
  end

  test "a required item has no Recent Value (e.g. it's a commodity): cost is nil, reason recorded" do
    w = writ(writ_item_wowhead_id: 1, required_items: [required_item(2)])
    snap = snapshot([{1, 300}])

    result = WritEfficiency.compute_result(w, snap)

    assert result.required_items_cost_copper == nil
    assert result.total_cost_copper == nil
    assert :missing_required_item_recent_value in result.missing_data_reasons
  end

  test "rep_per_gold is undefined (nil), not zero or infinite, when total cost can't be computed" do
    w = writ(writ_item_wowhead_id: 1, required_items: [required_item(2)])
    snap = snapshot([{1, 300}])

    result = WritEfficiency.compute_result(w, snap)

    assert result.rep_per_gold == nil
  end
end
