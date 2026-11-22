defmodule WowForeverRecipeFinder.CrateResultsFilterTest do
  use ExUnit.Case, async: true

  alias WowForeverRecipeFinder.{
    CrateEfficiencyResult,
    CrateResultsFilter,
    MerchantFavorFormula,
    WaylaidCrate
  }

  defp result(name, opts \\ []) do
    tier = Keyword.get(opts, :tier, :apprentice)
    quality = Keyword.get(opts, :quality, :common)
    cost = Keyword.get(opts, :cost)
    favor_amount = MerchantFavorFormula.favor_amount(tier, quality)

    crate = %WaylaidCrate{
      name: name,
      tier: tier,
      category: Keyword.get(opts, :category, "herbs"),
      quality: quality,
      wowhead_id: 1,
      required_level: 10,
      fill_options: []
    }

    %CrateEfficiencyResult{
      crate: crate,
      total_cost_copper: cost,
      favor_amount: favor_amount,
      price_per_favor_copper: cost && round(cost / favor_amount),
      missing_data_reasons: Keyword.get(opts, :reasons, [])
    }
  end

  test "search filters by crate name, case-insensitive" do
    results = [
      result("Waylaid Crate: Apprentice Herbs"),
      result("Waylaid Crate: Apprentice Ore", category: "ore")
    ]

    filtered = CrateResultsFilter.apply(results, %{search: "herbs"})

    assert Enum.map(filtered, & &1.crate.name) == ["Waylaid Crate: Apprentice Herbs"]
  end

  test "search also matches on category" do
    results = [result("A", category: "herbs"), result("B", category: "ore")]

    filtered = CrateResultsFilter.apply(results, %{search: "ore"})

    assert Enum.map(filtered, & &1.crate.name) == ["B"]
  end

  test "tier filter" do
    results = [result("A", tier: :apprentice), result("B", tier: :artisan)]

    filtered = CrateResultsFilter.apply(results, %{tier: :artisan})

    assert Enum.map(filtered, & &1.crate.name) == ["B"]
  end

  test "tier: :any shows every tier" do
    results = [result("A", tier: :apprentice), result("B", tier: :artisan)]

    filtered = CrateResultsFilter.apply(results, %{tier: :any})

    assert length(filtered) == 2
  end

  test "threshold filter: a row missing total_cost_copper is excluded once a max-cost threshold is set" do
    results = [
      result("Known", cost: 500),
      result("Unknown", cost: nil, reasons: [:no_fill_options_data])
    ]

    filtered = CrateResultsFilter.apply(results, %{max_cost_copper: 1_000})

    assert Enum.map(filtered, & &1.crate.name) == ["Known"]
  end

  test "defaults to cheapest-cost-per-Favor-first, unknowns always last" do
    results = [
      result("Pricey", cost: 5_000),
      result("Unknown", cost: nil, reasons: [:no_fill_options_data]),
      result("Cheap", cost: 100)
    ]

    sorted = CrateResultsFilter.apply(results, %{})

    assert Enum.map(sorted, & &1.crate.name) == ["Cheap", "Pricey", "Unknown"]
  end

  test "sort_by: :price_per_favor and :total_cost can disagree when crates pay different amounts of Favor" do
    results = [
      # Artisan pays 4x an Apprentice crate's Favor (MerchantFavorFormula),
      # so despite costing more in raw copper, it's cheaper per Favor.
      result("Cheaper raw cost, worse per Favor", tier: :apprentice, cost: 100),
      result("Pricier raw cost, better per Favor", tier: :artisan, cost: 200)
    ]

    by_total_cost = CrateResultsFilter.apply(results, %{sort_by: :total_cost})

    assert Enum.map(by_total_cost, & &1.crate.name) == [
             "Cheaper raw cost, worse per Favor",
             "Pricier raw cost, better per Favor"
           ]

    by_price_per_favor = CrateResultsFilter.apply(results, %{sort_by: :price_per_favor})

    assert Enum.map(by_price_per_favor, & &1.crate.name) == [
             "Pricier raw cost, better per Favor",
             "Cheaper raw cost, worse per Favor"
           ]
  end

  test "sort_dir: :desc reverses the priced rows but unknowns stay last" do
    results = [
      result("Cheap", cost: 100),
      result("Pricey", cost: 5_000),
      result("Unknown", cost: nil)
    ]

    sorted = CrateResultsFilter.apply(results, %{sort_dir: :desc})

    assert Enum.map(sorted, & &1.crate.name) == ["Pricey", "Cheap", "Unknown"]
  end
end
