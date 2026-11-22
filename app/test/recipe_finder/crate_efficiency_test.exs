defmodule WowForeverRecipeFinder.CrateEfficiencyTest do
  use ExUnit.Case, async: true

  alias WowForeverRecipeFinder.{
    CrateEfficiency,
    FillOption,
    ItemPrice,
    PriceSnapshot,
    WaylaidCrate
  }

  # Pure-function unit tests per docs/ELIXIR_TEST_MANIFESTO.md § What
  # Still Gets a Plain Unit Test: `compute_result/2` has no I/O, so real
  # in-memory structs are enough — no fixtures, no gateway.

  defp fill_option(opts) do
    %FillOption{
      display_name: Keyword.fetch!(opts, :display_name),
      wowhead_id: Keyword.get(opts, :wowhead_id),
      quantity: Keyword.get(opts, :quantity, 20)
    }
  end

  defp crate(opts) do
    %WaylaidCrate{
      name: Keyword.get(opts, :name, "Waylaid Crate: Test"),
      tier: Keyword.get(opts, :tier, :apprentice),
      category: Keyword.get(opts, :category, "herbs"),
      variant: Keyword.get(opts, :variant),
      quality: Keyword.get(opts, :quality, :common),
      wowhead_id: Keyword.fetch!(opts, :wowhead_id),
      required_level: Keyword.get(opts, :required_level, 10),
      fill_options: Keyword.get(opts, :fill_options, [])
    }
  end

  defp snapshot(prices) do
    %PriceSnapshot{
      prices_by_item_id:
        Map.new(prices, fn {id, recent_value} ->
          {id,
           %ItemPrice{
             wowhead_id: id,
             price_copper: 999_999,
             sold_per_day: 1.0,
             sale_confidence_pct: 50.0,
             recent_value_copper: recent_value
           }}
        end)
    }
  end

  describe "compute_result/2 — happy path" do
    test "total cost is the crate's own price plus the cheapest priceable fill option" do
      c =
        crate(
          wowhead_id: 1,
          fill_options: [
            fill_option(display_name: "Peacebloom", wowhead_id: 10, quantity: 20),
            fill_option(display_name: "Silverleaf", wowhead_id: 11, quantity: 20)
          ]
        )

      # Peacebloom: 20 * 50 = 1000; Silverleaf: 20 * 30 = 600 — cheaper.
      snap = snapshot(%{1 => 500, 10 => 50, 11 => 30})

      result = CrateEfficiency.compute_result(c, snap)

      assert result.crate_cost_copper == 500
      assert result.fill_cost_copper == 600
      assert result.total_cost_copper == 1100
      assert result.best_fill_option.display_name == "Silverleaf"
      assert result.missing_data_reasons == []
    end

    test "favor_amount comes from MerchantFavorFormula (tier/quality), and price_per_favor_copper divides the total cost by it" do
      c =
        crate(
          wowhead_id: 1,
          tier: :journeyman,
          quality: :uncommon,
          fill_options: [fill_option(display_name: "Peacebloom", wowhead_id: 10, quantity: 20)]
        )

      snap = snapshot(%{1 => 400, 10 => 30})

      result = CrateEfficiency.compute_result(c, snap)

      # Journeyman(2) * Uncommon(2) * 5 = 20 Favor.
      assert result.favor_amount == 20
      # Crate 400c + fill 600c (20 * 30) = 1000c total.
      assert result.total_cost_copper == 1_000
      assert result.price_per_favor_copper == 50
    end

    test "price_per_favor_copper is nil when total_cost_copper is nil, never computed against a missing cost" do
      c = crate(wowhead_id: 1, fill_options: nil)
      snap = snapshot(%{1 => 500})

      result = CrateEfficiency.compute_result(c, snap)

      assert result.total_cost_copper == nil
      assert result.price_per_favor_copper == nil
      # favor_amount is still always known — it's derived from the
      # crate's own tier/quality, independent of any snapshot data.
      assert result.favor_amount == 5
    end
  end

  describe "compute_result/2 — boundary/edge conditions" do
    test "fill_options: nil (not captured yet) gives :no_fill_options_data, never treated as free" do
      c = crate(wowhead_id: 1, fill_options: nil)
      snap = snapshot(%{1 => 500})

      result = CrateEfficiency.compute_result(c, snap)

      assert result.fill_cost_copper == nil
      assert result.total_cost_copper == nil
      assert :no_fill_options_data in result.missing_data_reasons
    end

    test "every fill option unresolved (no wowhead_id at all) gives :no_priceable_fill_option" do
      c =
        crate(
          wowhead_id: 1,
          fill_options: [
            fill_option(display_name: "Copper Ore", wowhead_id: nil),
            fill_option(display_name: "Tin Ore", wowhead_id: nil)
          ]
        )

      snap = snapshot(%{1 => 500})

      result = CrateEfficiency.compute_result(c, snap)

      assert result.fill_cost_copper == nil
      assert result.total_cost_copper == nil
      assert :no_priceable_fill_option in result.missing_data_reasons
    end

    test "a mix of resolved and unresolved fill options still picks the cheapest resolved one" do
      c =
        crate(
          wowhead_id: 1,
          fill_options: [
            fill_option(display_name: "Plaguebloom", wowhead_id: nil, quantity: 20),
            fill_option(display_name: "Dreamfoil", wowhead_id: 20, quantity: 20),
            fill_option(display_name: "Icecap", wowhead_id: 21, quantity: 20)
          ]
        )

      snap = snapshot(%{1 => 500, 20 => 100, 21 => 40})

      result = CrateEfficiency.compute_result(c, snap)

      assert result.best_fill_option.display_name == "Icecap"
      assert result.fill_cost_copper == 800
      assert result.missing_data_reasons == []
    end

    test "a fill option priced but missing from the snapshot entirely is skipped, not treated as free" do
      c =
        crate(
          wowhead_id: 1,
          fill_options: [
            fill_option(display_name: "Not in snapshot", wowhead_id: 99, quantity: 20),
            fill_option(display_name: "Priced", wowhead_id: 20, quantity: 10)
          ]
        )

      snap = snapshot(%{1 => 500, 20 => 100})

      result = CrateEfficiency.compute_result(c, snap)

      assert result.best_fill_option.display_name == "Priced"
      assert result.fill_cost_copper == 1000
    end

    test "crate's own recent value missing gives :missing_crate_recent_value" do
      c =
        crate(
          wowhead_id: 1,
          fill_options: [fill_option(display_name: "Peacebloom", wowhead_id: 10, quantity: 20)]
        )

      snap = snapshot(%{10 => 50})

      result = CrateEfficiency.compute_result(c, snap)

      assert result.crate_cost_copper == nil
      assert result.total_cost_copper == nil
      assert :missing_crate_recent_value in result.missing_data_reasons
      # The fill option itself still resolved, independent of the crate's own price.
      assert result.fill_cost_copper == 1000
    end

    test "both missing-data reasons can appear together" do
      c = crate(wowhead_id: 1, fill_options: nil)
      snap = snapshot(%{})

      result = CrateEfficiency.compute_result(c, snap)

      assert :missing_crate_recent_value in result.missing_data_reasons
      assert :no_fill_options_data in result.missing_data_reasons
    end
  end
end
