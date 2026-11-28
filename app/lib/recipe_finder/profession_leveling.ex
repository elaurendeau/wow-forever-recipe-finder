defmodule WowForeverRecipeFinder.ProfessionLeveling do
  @moduledoc """
  The use case behind docs/PRD.md § 7.13: a full 1→max-skill leveling
  path for a profession, built from the visitor's own stated priority —
  **never lose money, and among the recipes that don't, craft whichever
  sells fastest.** *Which* recipe is a candidate at a given skill level
  is decided purely from its own real, Forever-verified skill-up band
  (`SkillUpBands`, `nil` for recipes with no known band — never treated
  as available) — specifically `worth_crafting_at?/2`'s green cutoff,
  per the visitor's own explicit "stop once it turns green" choice, not
  grey. No probability is involved in *that* decision at all.

  A segment's `expected_crafts` (and the total cost/total sell that
  depend on it) is a different matter: those genuinely need a
  per-skill probability, which no public source has for WoW Forever, so
  `SkillUpCurve`'s estimated Classic-era formula is used there — see its
  own moduledoc. Keeping the ranking decision probability-free while
  still offering an estimated craft count is a deliberate split, not an
  inconsistency: one is real data, the other is clearly labeled as a
  guess wherever it's shown.

  Reuses `ProfitComputation`'s own per-craft profit math (same price
  basis as every other page) rather than duplicating it — this
  context's only job is the one-time recipe cost and the path itself.
  """

  alias WowForeverRecipeFinder.{
    LevelingResult,
    Pattern,
    PriceSnapshot,
    ProfitComputation
  }

  @type path_segment :: %{
          from_skill: pos_integer(),
          to_skill: pos_integer(),
          result: LevelingResult.t() | nil,
          # Estimated — see `SkillUpCurve`'s own doc. `nil` for a gap
          # segment (no result at all).
          expected_crafts: float() | nil
        }

  @doc """
  Every `LevelingResult` for a profession, given an already-parsed
  `PriceSnapshot` and the visitor's chosen price basis — one per
  pattern, no filtering (filtering by skill/profit happens in
  `build_path/2` and `candidates_at/3`).
  """
  @spec compute_results(String.t(), PriceSnapshot.t(), ProfitComputation.price_basis()) :: [
          LevelingResult.t()
        ]
  def compute_results(profession_slug, %PriceSnapshot{} = snapshot, price_basis) do
    profession_slug
    |> catalog_gateway().list_patterns()
    |> Enum.map(&compute_result(&1, snapshot, price_basis))
  end

  @doc """
  The pure join/compute for one pattern — no gateway call, no I/O.
  """
  @spec compute_result(Pattern.t(), PriceSnapshot.t(), ProfitComputation.price_basis()) ::
          LevelingResult.t()
  def compute_result(%Pattern{} = pattern, %PriceSnapshot{} = snapshot, price_basis) do
    profit_result = ProfitComputation.compute_result(pattern, snapshot, price_basis)

    %LevelingResult{
      pattern: pattern,
      profit_result: profit_result,
      recipe_cost_copper: recipe_cost_copper(pattern, snapshot, price_basis)
    }
  end

  @doc """
  Every result that still gives a skill-up at `skill` and never loses
  money, sorted by sold/day descending (unknown sold/day sorts last,
  never treated as "fast"). The visitor's own actual choice, not just
  the winner — useful for a "why this one" breakdown.
  """
  @spec candidates_at([LevelingResult.t()], non_neg_integer()) :: [LevelingResult.t()]
  def candidates_at(results, skill) do
    results
    |> Enum.filter(
      &(LevelingResult.still_useful_at?(&1, skill) and LevelingResult.never_loses_money?(&1))
    )
    |> Enum.sort_by(&sold_per_day_sort_key/1)
  end

  @doc """
  The best single candidate at `skill` — highest sold/day among every
  recipe that's both still useful and never loses money. `nil` (never
  a fabricated pick) when nothing qualifies at that skill level.
  """
  @spec best_at([LevelingResult.t()], non_neg_integer()) :: LevelingResult.t() | nil
  def best_at(results, skill) do
    case candidates_at(results, skill) do
      [best | _rest] -> best
      [] -> nil
    end
  end

  @doc """
  The full path from skill 1 to the highest `grey` threshold any
  pattern in this profession actually has (never a hardcoded 300 —
  professions can cap at different real skill levels, and assuming one
  universal cap would be exactly the kind of un-verified guess this
  feature exists to avoid). Consecutive skill levels recommending the
  same result are collapsed into one segment; a segment with `result:
  nil` means no known recipe both still gives a skill-up and is known
  not to lose money at that skill — shown, never hidden, so a gap in
  the data or the market is visible rather than silently skipped.
  """
  @spec build_path([LevelingResult.t()]) :: [path_segment()]
  def build_path(results) do
    case max_skill(results) do
      nil ->
        []

      max ->
        1..max
        |> Enum.map(&{&1, best_at(results, &1)})
        |> Enum.chunk_by(fn {_skill, result} ->
          result && result.pattern.crafted_item.wowhead_id
        end)
        |> Enum.map(&to_segment/1)
    end
  end

  defp to_segment(chunk) do
    {from_skill, _} = List.first(chunk)
    {to_skill, result} = List.last(chunk)

    %{
      from_skill: from_skill,
      to_skill: to_skill,
      result: result,
      expected_crafts: result && LevelingResult.expected_crafts(result, from_skill, to_skill)
    }
  end

  defp max_skill(results) do
    results
    |> Enum.flat_map(fn
      %{pattern: %{skill_up_bands: %{grey: grey}}} -> [grey]
      _without_bands -> []
    end)
    |> case do
      [] -> nil
      greys -> Enum.max(greys)
    end
  end

  defp sold_per_day_sort_key(%LevelingResult{profit_result: %{sold_per_day: nil}}), do: {1, 0.0}
  defp sold_per_day_sort_key(%LevelingResult{profit_result: %{sold_per_day: spd}}), do: {0, -spd}

  # The recipe's own one-time cost — never conflated with the per-craft
  # mat_cost_copper. `nil` whenever any part of the chain is unknown
  # (no recipe_cost_item at all, or no price for it in this snapshot),
  # never a fabricated zero or a silent fallback to "free."
  defp recipe_cost_copper(%Pattern{recipe_cost_item: nil}, _snapshot, _basis), do: nil

  defp recipe_cost_copper(%Pattern{recipe_cost_item: item}, snapshot, basis) do
    case PriceSnapshot.fetch_price(snapshot, item.wowhead_id) do
      {:ok, %{price_copper: region_avg, recent_value_copper: recent}} ->
        case basis do
          :region_avg -> region_avg
          :recent -> recent
        end

      :error ->
        nil
    end
  end

  defp catalog_gateway do
    Application.get_env(
      :recipe_finder,
      :catalog_repository_gateway,
      WowForeverRecipeFinder.Gateways.EctoCatalogRepositoryGateway
    )
  end
end
