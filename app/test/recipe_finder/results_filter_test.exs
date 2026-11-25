defmodule WowForeverRecipeFinder.ResultsFilterTest do
  use ExUnit.Case, async: true

  alias WowForeverRecipeFinder.{Item, Pattern, ProfitResult, ResultsFilter}

  defp result(name, source, opts \\ []) do
    pattern = %Pattern{
      profession_slug: "tailoring",
      crafted_item: %Item{wowhead_id: 1, display_name: name, wiki_slug: name},
      name: name,
      tier: :apprentice,
      skill: 1,
      source: source,
      wiki_slug: name,
      resolution_status: :resolved,
      reagents: []
    }

    %ProfitResult{
      pattern: pattern,
      price_copper: Keyword.get(opts, :price, 100),
      sold_per_day: Keyword.get(opts, :spd, 10.0),
      sale_confidence_pct: Keyword.get(opts, :conf, 50.0),
      mat_cost_copper: 10,
      net_profit_per_unit_copper: Keyword.get(opts, :profit, 90),
      profit_pct: Keyword.get(opts, :profit_pct, 900.0),
      missing_data_reasons: Keyword.get(opts, :reasons, [])
    }
  end

  test "search filters by substring, case-insensitive" do
    results = [result("Bolt of Linen Cloth", :trainer), result("Red Woolen Bag", :drop)]

    filtered = ResultsFilter.apply(results, %{search: "woolen", profitable_only?: false})

    assert Enum.map(filtered, & &1.pattern.name) == ["Red Woolen Bag"]
  end

  test "source filter" do
    results = [result("A", :trainer), result("B", :drop), result("C", :vendor)]

    filtered =
      ResultsFilter.apply(results, %{sources: MapSet.new(["drop"]), profitable_only?: false})

    assert Enum.map(filtered, & &1.pattern.name) == ["B"]
  end

  test "source filter always shows patterns with no source category" do
    results = [result("A", :trainer), result("Uncategorized", nil)]

    filtered =
      ResultsFilter.apply(results, %{sources: MapSet.new(["vendor"]), profitable_only?: false})

    assert Enum.map(filtered, & &1.pattern.name) == ["Uncategorized"]
  end

  test "profitable_only? excludes non-positive and nil profit results" do
    results = [
      result("Profitable", :trainer, profit: 100.0),
      result("Break even", :trainer, profit: 0.0),
      result("Unknown", :trainer, profit: nil, reasons: [:no_sale_data])
    ]

    filtered = ResultsFilter.apply(results, %{profitable_only?: true})

    assert Enum.map(filtered, & &1.pattern.name) == ["Profitable"]
  end

  test "threshold filters: a row missing the underlying value is excluded once a threshold is set" do
    results = [
      result("Has data", :trainer, spd: 50.0),
      result("Missing data", :trainer, spd: nil)
    ]

    filtered = ResultsFilter.apply(results, %{min_sold_per_day: 1.0, profitable_only?: false})

    assert Enum.map(filtered, & &1.pattern.name) == ["Has data"]
  end

  test "sorting: nils always sort last regardless of direction" do
    results = [
      result("High", :trainer, profit: 500),
      result("Missing", :trainer, profit: nil, reasons: [:no_sale_data]),
      result("Low", :trainer, profit: 10)
    ]

    desc =
      ResultsFilter.apply(results, %{sort_by: :profit, sort_dir: :desc, profitable_only?: false})

    assert Enum.map(desc, & &1.pattern.name) == ["High", "Low", "Missing"]

    asc =
      ResultsFilter.apply(results, %{sort_by: :profit, sort_dir: :asc, profitable_only?: false})

    assert Enum.map(asc, & &1.pattern.name) == ["Low", "High", "Missing"]
  end

  test "sorting by profit percentage" do
    results = [
      result("Low ROI", :trainer, profit_pct: 20.0),
      result("High ROI", :trainer, profit_pct: 300.0),
      result("No ROI", :trainer, profit_pct: nil, reasons: [:no_reagents_found])
    ]

    desc =
      ResultsFilter.apply(results, %{
        sort_by: :profit_pct,
        sort_dir: :desc,
        profitable_only?: false
      })

    assert Enum.map(desc, & &1.pattern.name) == ["High ROI", "Low ROI", "No ROI"]
  end

  test "threshold filter on profit percentage excludes rows below the minimum" do
    results = [
      result("Low ROI", :trainer, profit_pct: 20.0),
      result("High ROI", :trainer, profit_pct: 300.0)
    ]

    filtered = ResultsFilter.apply(results, %{min_profit_pct: 100.0, profitable_only?: false})

    assert Enum.map(filtered, & &1.pattern.name) == ["High ROI"]
  end
end
