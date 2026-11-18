defmodule WowForeverRecipeFinder.CrateResultsFilterTest do
  use ExUnit.Case, async: true

  alias WowForeverRecipeFinder.{CrateEfficiencyResult, CrateResultsFilter, WaylaidCrate}

  defp result(name, opts \\ []) do
    crate = %WaylaidCrate{
      name: name,
      tier: Keyword.get(opts, :tier, :apprentice),
      category: Keyword.get(opts, :category, "herbs"),
      quality: :common,
      wowhead_id: 1,
      required_level: 10,
      fill_options: []
    }

    %CrateEfficiencyResult{
      crate: crate,
      total_cost_copper: Keyword.get(opts, :cost),
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

  test "defaults to cheapest-first (ascending cost), unknowns always last" do
    results = [
      result("Pricey", cost: 5_000),
      result("Unknown", cost: nil, reasons: [:no_fill_options_data]),
      result("Cheap", cost: 100)
    ]

    sorted = CrateResultsFilter.apply(results, %{})

    assert Enum.map(sorted, & &1.crate.name) == ["Cheap", "Pricey", "Unknown"]
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
