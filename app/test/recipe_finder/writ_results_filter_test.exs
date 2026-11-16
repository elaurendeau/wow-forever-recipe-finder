defmodule WowForeverRecipeFinder.WritResultsFilterTest do
  use ExUnit.Case, async: true

  alias WowForeverRecipeFinder.{Writ, WritEfficiencyResult, WritResultsFilter}

  defp result(name, opts \\ []) do
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
      reputation_rewards: []
    }

    %WritEfficiencyResult{
      writ: writ,
      total_cost_copper: Keyword.get(opts, :cost),
      total_reputation: Keyword.get(opts, :reputation, 75),
      rep_per_gold: Keyword.get(opts, :rep_per_gold),
      missing_data_reasons: Keyword.get(opts, :reasons, [])
    }
  end

  test "search filters by writ name, case-insensitive" do
    results = [result("Elixir of Ogre's Strength"), result("Heavy Bronze Mace")]

    filtered = WritResultsFilter.apply(results, %{search: "bronze"})

    assert Enum.map(filtered, & &1.writ.name) == ["Heavy Bronze Mace"]
  end

  test "threshold filter: a row missing total_cost_copper is excluded once a max-cost threshold is set" do
    results = [
      result("Known cost", cost: 500),
      result("Unknown cost", cost: nil, reasons: [:no_required_items_data])
    ]

    filtered = WritResultsFilter.apply(results, %{max_cost_copper: 1_000})

    assert Enum.map(filtered, & &1.writ.name) == ["Known cost"]
  end

  test "threshold filter on minimum reputation" do
    results = [result("Low rep", reputation: 50), result("High rep", reputation: 150)]

    filtered = WritResultsFilter.apply(results, %{min_reputation: 100})

    assert Enum.map(filtered, & &1.writ.name) == ["High rep"]
  end

  test "sorting by rep_per_gold descending, nils always last regardless of direction" do
    results = [
      result("High", rep_per_gold: 2500.0),
      result("Unknown", rep_per_gold: nil, reasons: [:no_required_items_data]),
      result("Low", rep_per_gold: 100.0)
    ]

    desc = WritResultsFilter.apply(results, %{sort_by: :rep_per_gold, sort_dir: :desc})
    assert Enum.map(desc, & &1.writ.name) == ["High", "Low", "Unknown"]

    asc = WritResultsFilter.apply(results, %{sort_by: :rep_per_gold, sort_dir: :asc})
    assert Enum.map(asc, & &1.writ.name) == ["Low", "High", "Unknown"]
  end

  test "sorting by cost ascending" do
    results = [result("Pricey", cost: 900), result("Cheap", cost: 100)]

    sorted = WritResultsFilter.apply(results, %{sort_by: :cost, sort_dir: :asc})

    assert Enum.map(sorted, & &1.writ.name) == ["Cheap", "Pricey"]
  end

  test "sorting by reputation descending" do
    results = [result("Low rep", reputation: 75), result("High rep", reputation: 125)]

    sorted = WritResultsFilter.apply(results, %{sort_by: :reputation, sort_dir: :desc})

    assert Enum.map(sorted, & &1.writ.name) == ["High rep", "Low rep"]
  end
end
