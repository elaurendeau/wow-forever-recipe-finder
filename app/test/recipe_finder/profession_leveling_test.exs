defmodule WowForeverRecipeFinder.ProfessionLevelingTest do
  use ExUnit.Case, async: true

  alias WowForeverRecipeFinder.{
    Item,
    ItemPrice,
    LevelingResult,
    LevelingShoppingList,
    Pattern,
    PriceSnapshot,
    ProfessionLeveling,
    RecipeCostItem,
    SkillUpBands,
    SkillUpCurve
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

    test "stops at green (the leveling page's own stricter, visitor-chosen cutoff), not grey" do
      assert LevelingResult.still_useful_at?(result_with_bands(10, green: 40, grey: 50), 39)
      refute LevelingResult.still_useful_at?(result_with_bands(10, green: 40, grey: 50), 40)
    end
  end

  describe "SkillUpBands.worth_crafting_at?/2" do
    test "stops at green, not grey — the visitor's own explicit choice" do
      bands = %SkillUpBands{orange: 1, yellow: 10, green: 20, grey: 30}
      assert SkillUpBands.worth_crafting_at?(bands, 19)
      refute SkillUpBands.worth_crafting_at?(bands, 20)
      refute SkillUpBands.worth_crafting_at?(bands, 25)
    end

    test "falls back to grey when green itself is unknown" do
      bands = %SkillUpBands{orange: nil, yellow: nil, green: nil, grey: 30}
      assert SkillUpBands.worth_crafting_at?(bands, 29)
      refute SkillUpBands.worth_crafting_at?(bands, 30)
    end
  end

  describe "SkillUpCurve.probability/3" do
    test "always succeeds before yellow (the orange range)" do
      bands = %SkillUpBands{yellow: 20, grey: 40}
      assert SkillUpCurve.probability(bands, 1, 1) == 1.0
      assert SkillUpCurve.probability(bands, 19, 1) == 1.0
    end

    test "declines linearly from 1.0 at yellow to 0.0 at grey" do
      bands = %SkillUpBands{yellow: 20, grey: 40}
      assert SkillUpCurve.probability(bands, 20, 1) == 1.0
      assert SkillUpCurve.probability(bands, 30, 1) == 0.5
      assert_in_delta SkillUpCurve.probability(bands, 39, 1), 0.05, 0.001
    end

    test "never succeeds at or past grey" do
      bands = %SkillUpBands{yellow: 20, grey: 40}
      assert SkillUpCurve.probability(bands, 40, 1) == 0.0
      assert SkillUpCurve.probability(bands, 50, 1) == 0.0
    end

    test "anchors the decline at learned_at when yellow itself is unknown" do
      bands = %SkillUpBands{yellow: nil, grey: 20}
      assert SkillUpCurve.probability(bands, 10, 10) == 1.0
      assert SkillUpCurve.probability(bands, 15, 10) == 0.5
    end
  end

  describe "SkillUpCurve.expected_crafts/4" do
    test "is exactly the number of skill points when every one is guaranteed (orange)" do
      bands = %SkillUpBands{yellow: 100, grey: 200}
      assert SkillUpCurve.expected_crafts(bands, 1, 1, 10) == 10.0
    end

    test "grows larger than the number of skill points once probability drops below 1.0" do
      bands = %SkillUpBands{yellow: 10, grey: 20}
      assert SkillUpCurve.expected_crafts(bands, 1, 10, 15) > 6
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

    test "best_at/2 is nil only when no in-range recipe has a computable profit at all" do
      results = [
        leveling_result(wowhead_id: 1, name: "Unknown profit", sold_per_day: 100.0, profit: nil)
      ]

      assert ProfessionLeveling.best_at(results, 10) == nil
    end

    test "best_at/2 falls back to the least-bad losing recipe once nothing is safe" do
      results = [
        leveling_result(wowhead_id: 1, name: "Loses a lot", sold_per_day: 100.0, profit: -50),
        leveling_result(wowhead_id: 2, name: "Loses a little", sold_per_day: 1.0, profit: -1)
      ]

      assert ProfessionLeveling.best_at(results, 10).pattern.name == "Loses a little"
    end

    test "loss_candidates_at/2 excludes a recipe with an unknown profit, never a fabricated loss" do
      results = [
        leveling_result(wowhead_id: 1, name: "Unknown profit", sold_per_day: 100.0, profit: nil)
      ]

      assert ProfessionLeveling.loss_candidates_at(results, 10) == []
    end

    test "loss_candidates_at/2 never includes a safe (non-losing) recipe" do
      results = [
        leveling_result(wowhead_id: 1, name: "Breaks even", sold_per_day: 100.0, profit: 0)
      ]

      assert ProfessionLeveling.loss_candidates_at(results, 10) == []
    end

    test "a safe recipe always wins over a losing one, regardless of sold/day" do
      results = [
        leveling_result(wowhead_id: 1, name: "Loses but fast", sold_per_day: 100.0, profit: -1),
        leveling_result(wowhead_id: 2, name: "Safe but slow", sold_per_day: 1.0, profit: 1)
      ]

      assert ProfessionLeveling.best_at(results, 10).pattern.name == "Safe but slow"
    end

    test "stops recommending a recipe once skill reaches its own green threshold, not grey" do
      results = [
        leveling_result(
          wowhead_id: 1,
          name: "Early",
          bands: [green: 20, grey: 40],
          sold_per_day: 50.0
        )
      ]

      assert ProfessionLeveling.candidates_at(results, 19) != []
      assert ProfessionLeveling.candidates_at(results, 20) == []
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

    test "recommends the least-bad losing recipe rather than a gap when nothing is safe" do
      p = pattern(wowhead_id: 1, name: "Only Option", skill: 1, bands: [grey: 10])

      results = [
        %LevelingResult{
          pattern: p,
          profit_result: %WowForeverRecipeFinder.ProfitResult{
            pattern: p,
            sold_per_day: 5.0,
            net_profit_per_unit_copper: -1,
            missing_data_reasons: []
          }
        }
      ]

      path = ProfessionLeveling.build_path(results)

      assert Enum.map(path, &{&1.from_skill, &1.to_skill, &1.result && &1.result.pattern.name}) ==
               [{1, 9, "Only Option"}, {10, 10, nil}]
    end
  end

  describe "LevelingResult.expected_crafts/3" do
    test "nil when the recipe has no known skill-up band at all, never a fabricated number" do
      p = pattern(wowhead_id: 1, skill: 1, bands: nil)

      lr = %LevelingResult{
        pattern: p,
        profit_result: %WowForeverRecipeFinder.ProfitResult{pattern: p, missing_data_reasons: []}
      }

      assert LevelingResult.expected_crafts(lr, 1, 10) == nil
    end

    test "delegates to SkillUpCurve using the pattern's own bands and learned-at skill" do
      p = pattern(wowhead_id: 1, skill: 1, bands: [yellow: 100, grey: 200])

      lr = %LevelingResult{
        pattern: p,
        profit_result: %WowForeverRecipeFinder.ProfitResult{pattern: p, missing_data_reasons: []}
      }

      assert LevelingResult.expected_crafts(lr, 1, 10) == 10.0
    end
  end

  describe "LevelingResult.total_cost_copper/2 and total_sell_copper/2" do
    defp cost_result(opts) do
      p =
        pattern(
          wowhead_id: 1,
          skill: 1,
          source: Keyword.get(opts, :source, :trainer),
          recipe_cost_item: Keyword.get(opts, :recipe_cost_item)
        )

      %LevelingResult{
        pattern: p,
        profit_result: %WowForeverRecipeFinder.ProfitResult{
          pattern: p,
          price_copper: Keyword.fetch!(opts, :price_copper),
          mat_cost_copper: Keyword.fetch!(opts, :mat_cost_copper),
          missing_data_reasons: []
        },
        recipe_cost_copper: Keyword.get(opts, :recipe_cost_copper)
      }
    end

    test "a trainer recipe's total cost is just the reagent total, over every craft" do
      result = cost_result(source: :trainer, price_copper: 100, mat_cost_copper: 10)

      assert LevelingResult.total_cost_copper(result, 5) == 50
    end

    test "a non-trainer recipe's total cost adds its own one-time purchase" do
      item = %RecipeCostItem{wowhead_id: 2, display_name: "Pattern: Test"}

      result =
        cost_result(
          source: :vendor,
          recipe_cost_item: item,
          recipe_cost_copper: 1000,
          price_copper: 100,
          mat_cost_copper: 10
        )

      assert LevelingResult.total_cost_copper(result, 5) == 50 + 1000
    end

    test "a non-trainer recipe with an unknown purchase price makes the whole total unknown" do
      item = %RecipeCostItem{wowhead_id: 2, display_name: "Pattern: Test"}

      result =
        cost_result(
          source: :vendor,
          recipe_cost_item: item,
          recipe_cost_copper: nil,
          price_copper: 100,
          mat_cost_copper: 10
        )

      assert LevelingResult.total_cost_copper(result, 5) == nil
    end

    test "a recipe with no recorded source at all, but no recipe_cost_item either, is just the reagent total" do
      # Regression: the first clause used to key off pattern.source ==
      # :trainer, so a pattern with no recorded source (a real,
      # non-trivial share of the catalog) fell through to "unknown
      # total" even with no recipe_cost_item at all to justify it.
      result = cost_result(source: nil, price_copper: 100, mat_cost_copper: 10)

      assert LevelingResult.total_cost_copper(result, 5) == 50
    end

    test "total sell is the gross list price over every craft, before the AH cut" do
      result = cost_result(price_copper: 100, mat_cost_copper: 10)

      assert LevelingResult.total_sell_copper(result, 5) == 500
    end
  end

  describe "LevelingResult.total_profit_copper/2" do
    test "total sell minus total cost, for a trainer recipe (reagents only)" do
      result = cost_result(source: :trainer, price_copper: 100, mat_cost_copper: 10)

      # sell: 100 * 5 = 500; cost: 10 * 5 = 50
      assert LevelingResult.total_profit_copper(result, 5) == 450
    end

    test "nets out the recipe's own one-time purchase too, unlike per-craft profit" do
      item = %RecipeCostItem{wowhead_id: 2, display_name: "Pattern: Test"}

      result =
        cost_result(
          source: :vendor,
          recipe_cost_item: item,
          recipe_cost_copper: 200,
          price_copper: 100,
          mat_cost_copper: 10
        )

      # sell: 100 * 5 = 500; cost: 10 * 5 + 200 = 250
      assert LevelingResult.total_profit_copper(result, 5) == 250
    end

    test "nil when the one-time purchase price is unknown, never a partial sum" do
      item = %RecipeCostItem{wowhead_id: 2, display_name: "Pattern: Test"}

      result =
        cost_result(
          source: :vendor,
          recipe_cost_item: item,
          recipe_cost_copper: nil,
          price_copper: 100,
          mat_cost_copper: 10
        )

      assert LevelingResult.total_profit_copper(result, 5) == nil
    end
  end

  describe "LevelingShoppingList" do
    test "a trainer recipe's lines are just its reagents, scaled by crafts needed" do
      p = pattern(wowhead_id: 1, skill: 1, source: :trainer)

      result = %LevelingResult{
        pattern: p,
        profit_result: %WowForeverRecipeFinder.ProfitResult{
          pattern: p,
          reagent_breakdown: [
            %{
              display_name: "Linen Cloth",
              quantity: 2,
              unit_price_copper: 10,
              line_total_copper: 20
            }
          ],
          missing_data_reasons: []
        }
      }

      assert LevelingShoppingList.build_lines(result, 5) == [
               %{
                 display_name: "Linen Cloth",
                 quantity: 10,
                 unit_price_copper: 10,
                 line_total_copper: 100
               }
             ]
    end

    test "a non-trainer recipe's lines lead with its own one-time purchase, quantity 1 regardless of crafts needed" do
      item = %RecipeCostItem{wowhead_id: 2, display_name: "Pattern: Test"}
      p = pattern(wowhead_id: 1, skill: 1, source: :vendor, recipe_cost_item: item)

      result = %LevelingResult{
        pattern: p,
        profit_result: %WowForeverRecipeFinder.ProfitResult{
          pattern: p,
          reagent_breakdown: [
            %{
              display_name: "Linen Cloth",
              quantity: 1,
              unit_price_copper: 10,
              line_total_copper: 10
            }
          ],
          missing_data_reasons: []
        },
        recipe_cost_copper: 500
      }

      assert LevelingShoppingList.build_lines(result, 5) == [
               %{
                 display_name: "Pattern: Test",
                 quantity: 1,
                 unit_price_copper: 500,
                 line_total_copper: 500
               },
               %{
                 display_name: "Linen Cloth",
                 quantity: 5,
                 unit_price_copper: 10,
                 line_total_copper: 50
               }
             ]
    end

    test "total_cost_copper/1 sums every line, or nil if any line's cost is unknown" do
      assert LevelingShoppingList.total_cost_copper([
               %{display_name: "a", quantity: 1, unit_price_copper: 10, line_total_copper: 10},
               %{display_name: "b", quantity: 1, unit_price_copper: 20, line_total_copper: 20}
             ]) == 30

      assert LevelingShoppingList.total_cost_copper([
               %{display_name: "a", quantity: 1, unit_price_copper: nil, line_total_copper: nil}
             ]) == nil
    end

    test "to_auctionator_text/2 reuses the real Auctionator format" do
      lines = [
        %{
          display_name: "Linen Cloth",
          quantity: 10,
          unit_price_copper: 10,
          line_total_copper: 100
        }
      ]

      assert LevelingShoppingList.to_auctionator_text("Test List", lines) ==
               "*** Test List\nLinen Cloth\n"
    end
  end
end
