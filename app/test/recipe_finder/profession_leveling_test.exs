defmodule WowForeverRecipeFinder.ProfessionLevelingTest do
  use ExUnit.Case, async: true

  alias WowForeverRecipeFinder.{
    Item,
    ItemPrice,
    LevelingResult,
    Pattern,
    PriceSnapshot,
    ProfessionLeveling,
    RecipeCostItem,
    SkillUpBands
  }

  # Pure-function unit tests per docs/ELIXIR_TEST_MANIFESTO.md § What
  # Still Gets a Plain Unit Test: no I/O here, real in-memory structs
  # are enough.

  defp item(wowhead_id, name),
    do: %Item{wowhead_id: wowhead_id, display_name: name, wiki_slug: name}

  defp bands(nil), do: nil

  defp bands(opts) do
    %SkillUpBands{
      orange: Keyword.get(opts, :orange),
      yellow: Keyword.get(opts, :yellow),
      green: Keyword.get(opts, :green),
      grey: Keyword.fetch!(opts, :grey)
    }
  end

  defp pattern(opts) do
    crafted = item(Keyword.fetch!(opts, :wowhead_id), Keyword.get(opts, :name, "Test Item"))

    %Pattern{
      profession_slug: "tailoring",
      crafted_item: crafted,
      name: Keyword.get(opts, :name, "Test Item"),
      tier: :apprentice,
      skill: Keyword.fetch!(opts, :skill),
      source: Keyword.get(opts, :source, :trainer),
      wiki_slug: "test",
      resolution_status: :resolved,
      reagents: Keyword.get(opts, :reagents, []),
      skill_up_bands: bands(Keyword.get(opts, :bands)),
      recipe_cost_item: Keyword.get(opts, :recipe_cost_item)
    }
  end

  defp snapshot(prices) do
    %PriceSnapshot{
      prices_by_item_id:
        Map.new(prices, fn {id, region_avg, recent} ->
          {id,
           %ItemPrice{
             wowhead_id: id,
             price_copper: region_avg,
             sold_per_day: 1.0,
             sale_confidence_pct: 50.0,
             recent_value_copper: recent
           }}
        end)
    }
  end

  describe "LevelingResult.never_loses_money?/1" do
    defp result_with_profit(profit) do
      %LevelingResult{
        pattern: pattern(wowhead_id: 1, skill: 1),
        profit_result: %WowForeverRecipeFinder.ProfitResult{
          pattern: pattern(wowhead_id: 1, skill: 1),
          net_profit_per_unit_copper: profit,
          missing_data_reasons: []
        }
      }
    end

    test "nil profit (unknown) is never treated as safe" do
      refute LevelingResult.never_loses_money?(result_with_profit(nil))
    end

    test "a real loss is not safe" do
      refute LevelingResult.never_loses_money?(result_with_profit(-1))
    end

    test "breaking even or better is safe" do
      assert LevelingResult.never_loses_money?(result_with_profit(0))
      assert LevelingResult.never_loses_money?(result_with_profit(100))
    end
  end

  describe "LevelingResult.still_useful_at?/2" do
    defp result_with_bands(skill, bands_opts) do
      %LevelingResult{
        pattern: pattern(wowhead_id: 1, skill: skill, bands: bands_opts),
        profit_result: %WowForeverRecipeFinder.ProfitResult{
          pattern: pattern(wowhead_id: 1, skill: skill),
          missing_data_reasons: []
        }
      }
    end

    test "no known band is never treated as available" do
      refute LevelingResult.still_useful_at?(result_with_bands(10, nil), 20)
    end

    test "below the recipe's own learned-at skill is not available" do
      refute LevelingResult.still_useful_at?(result_with_bands(50, grey: 100), 20)
    end

    test "within the band (learned_at <= skill < grey) is available" do
      assert LevelingResult.still_useful_at?(result_with_bands(10, grey: 50), 30)
    end

    test "at or above grey is no longer available" do
      refute LevelingResult.still_useful_at?(result_with_bands(10, grey: 50), 50)
      refute LevelingResult.still_useful_at?(result_with_bands(10, grey: 50), 60)
    end
  end

  describe "compute_result/3 — recipe cost" do
    test "a trainer recipe (no recipe_cost_item) has nil recipe_cost_copper" do
      p = pattern(wowhead_id: 1, skill: 1, source: :trainer)
      snap = snapshot([{1, 100, 90}])

      result = ProfessionLeveling.compute_result(p, snap, :region_avg)

      assert result.recipe_cost_copper == nil
    end

    test "a non-trainer recipe's cost comes from the chosen price basis" do
      recipe_item = %RecipeCostItem{wowhead_id: 2, display_name: "Pattern: Test Item"}
      p = pattern(wowhead_id: 1, skill: 1, source: :vendor, recipe_cost_item: recipe_item)
      snap = snapshot([{1, 100, 90}, {2, 500, 600}])

      assert ProfessionLeveling.compute_result(p, snap, :region_avg).recipe_cost_copper == 500
      assert ProfessionLeveling.compute_result(p, snap, :recent).recipe_cost_copper == 600
    end

    test "a recipe_cost_item with no price in the snapshot is nil, never a fabricated zero" do
      recipe_item = %RecipeCostItem{wowhead_id: 2, display_name: "Pattern: Test Item"}
      p = pattern(wowhead_id: 1, skill: 1, source: :vendor, recipe_cost_item: recipe_item)
      snap = snapshot([{1, 100, 90}])

      assert ProfessionLeveling.compute_result(p, snap, :region_avg).recipe_cost_copper == nil
    end
  end

  describe "candidates_at/2 and best_at/2" do
    defp leveling_result(opts) do
      p =
        pattern(
          wowhead_id: Keyword.fetch!(opts, :wowhead_id),
          name: Keyword.get(opts, :name, "Item"),
          skill: Keyword.get(opts, :learned_at, 1),
          bands: Keyword.get(opts, :bands, grey: 300)
        )

      %LevelingResult{
        pattern: p,
        profit_result: %WowForeverRecipeFinder.ProfitResult{
          pattern: p,
          sold_per_day: Keyword.get(opts, :sold_per_day),
          net_profit_per_unit_copper: Keyword.get(opts, :profit, 0),
          missing_data_reasons: []
        }
      }
    end

    test "excludes a result that loses money even if it sells fastest" do
      results = [
        leveling_result(wowhead_id: 1, name: "Fast but loses", sold_per_day: 100.0, profit: -1),
        leveling_result(wowhead_id: 2, name: "Slower but safe", sold_per_day: 10.0, profit: 1)
      ]

      assert Enum.map(ProfessionLeveling.candidates_at(results, 50), & &1.pattern.name) == [
               "Slower but safe"
             ]
    end

    test "excludes a result not yet learnable or already grey at this skill" do
      results = [
        leveling_result(
          wowhead_id: 1,
          name: "Not learned yet",
          learned_at: 100,
          sold_per_day: 50.0
        ),
        leveling_result(
          wowhead_id: 2,
          name: "Already grey",
          bands: [grey: 20],
          sold_per_day: 50.0
        ),
        leveling_result(
          wowhead_id: 3,
          name: "In range",
          learned_at: 10,
          bands: [grey: 200],
          sold_per_day: 5.0
        )
      ]

      assert Enum.map(ProfessionLeveling.candidates_at(results, 50), & &1.pattern.name) == [
               "In range"
             ]
    end

    test "sorts by sold_per_day descending, unknown sold_per_day last" do
      results = [
        leveling_result(wowhead_id: 1, name: "Unknown speed", sold_per_day: nil),
        leveling_result(wowhead_id: 2, name: "Slow", sold_per_day: 5.0),
        leveling_result(wowhead_id: 3, name: "Fast", sold_per_day: 50.0)
      ]

      assert Enum.map(ProfessionLeveling.candidates_at(results, 10), & &1.pattern.name) == [
               "Fast",
               "Slow",
               "Unknown speed"
             ]
    end

    test "best_at/2 picks the single highest sold/day candidate" do
      results = [
        leveling_result(wowhead_id: 1, name: "Slow", sold_per_day: 5.0),
        leveling_result(wowhead_id: 2, name: "Fast", sold_per_day: 50.0)
      ]

      assert ProfessionLeveling.best_at(results, 10).pattern.name == "Fast"
    end

    test "best_at/2 is nil when nothing qualifies, never a fabricated pick" do
      results = [
        leveling_result(wowhead_id: 1, name: "Loses money", sold_per_day: 100.0, profit: -1)
      ]

      assert ProfessionLeveling.best_at(results, 10) == nil
    end
  end

  describe "build_path/1" do
    defp path_result(wowhead_id, name, learned_at, grey, sold_per_day) do
      p =
        pattern(
          wowhead_id: wowhead_id,
          name: name,
          skill: learned_at,
          bands: [grey: grey]
        )

      %LevelingResult{
        pattern: p,
        profit_result: %WowForeverRecipeFinder.ProfitResult{
          pattern: p,
          sold_per_day: sold_per_day,
          net_profit_per_unit_copper: 1,
          missing_data_reasons: []
        }
      }
    end

    test "collapses consecutive skill levels recommending the same recipe into one segment" do
      results = [path_result(1, "Early Item", 1, 10, 50.0)]

      path = ProfessionLeveling.build_path(results)

      # grey: 10 means skill 10 itself is already grey (still_useful_at? is
      # strictly < grey) — the recipe is only useful for 1..9, with skill 10
      # correctly surfacing as its own no-recipe-left gap, never hidden.
      assert Enum.map(path, &{&1.from_skill, &1.to_skill, &1.result && &1.result.pattern.name}) ==
               [
                 {1, 9, "Early Item"},
                 {10, 10, nil}
               ]
    end

    test "a gap with no qualifying recipe is its own segment with result: nil, never silently skipped" do
      results = [
        path_result(1, "Early Item", 1, 5, 50.0),
        path_result(2, "Later Item", 20, 30, 50.0)
      ]

      path = ProfessionLeveling.build_path(results)

      assert Enum.map(path, &{&1.from_skill, &1.to_skill, &1.result && &1.result.pattern.name}) ==
               [
                 {1, 4, "Early Item"},
                 {5, 19, nil},
                 {20, 29, "Later Item"},
                 {30, 30, nil}
               ]
    end

    test "switches segment when a better (higher sold/day) recipe becomes available mid-range" do
      results = [
        path_result(1, "Steady", 1, 100, 10.0),
        path_result(2, "Faster once learned", 30, 100, 90.0)
      ]

      path = ProfessionLeveling.build_path(results)

      assert Enum.map(path, &{&1.from_skill, &1.to_skill, &1.result && &1.result.pattern.name}) ==
               [
                 {1, 29, "Steady"},
                 {30, 99, "Faster once learned"},
                 {100, 100, nil}
               ]
    end

    test "max skill is the highest grey threshold actually present, never a hardcoded 300" do
      results = [path_result(1, "Low cap item", 1, 40, 10.0)]

      path = ProfessionLeveling.build_path(results)

      assert List.last(path).to_skill == 40
    end

    test "no results with any band at all gives an empty path, not a crash" do
      assert ProfessionLeveling.build_path([]) == []
    end
  end
end
