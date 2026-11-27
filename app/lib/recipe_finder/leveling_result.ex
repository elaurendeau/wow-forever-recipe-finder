defmodule WowForeverRecipeFinder.LevelingResult do
  @moduledoc """
  A `Pattern` joined against a `PriceSnapshot` for the Profession
  Leveling page — reuses `ProfitComputation`'s own per-craft profit
  math (same price basis, never duplicated) and adds the one-time
  recipe cost (if the recipe must be bought) and the real skill-up
  band this recipe has. See docs/PRD.md § 7.13.
  """

  alias WowForeverRecipeFinder.{Pattern, ProfitResult}

  @enforce_keys [:pattern, :profit_result]
  defstruct [:pattern, :profit_result, :recipe_cost_copper]

  @type t :: %__MODULE__{
          pattern: Pattern.t(),
          profit_result: ProfitResult.t(),
          # The recipe's own one-time AH cost (not per-craft) — `nil`
          # for trainer-taught recipes (no AH cost applies) and for
          # non-trainer recipes with no known recipe_cost_item, or
          # whose item has no price in the snapshot. Never conflated
          # with mat_cost_copper (the per-craft reagent cost).
          recipe_cost_copper: non_neg_integer() | nil
        }

  @doc "Never a real loss, per the pattern's `net_profit_per_unit_copper` — `nil` (unknown) does not count as safe."
  @spec never_loses_money?(t()) :: boolean()
  def never_loses_money?(%__MODULE__{profit_result: %{net_profit_per_unit_copper: nil}}),
    do: false

  def never_loses_money?(%__MODULE__{profit_result: %{net_profit_per_unit_copper: p}}), do: p >= 0

  @doc """
  Still gives a skill-up at the given skill level — both learnable
  (`skill >= pattern.skill`) and not yet grey. `false` (never a
  fabricated yes) when the recipe has no known skill-up band at all.
  """
  @spec still_useful_at?(t(), non_neg_integer()) :: boolean()
  def still_useful_at?(%__MODULE__{pattern: %{skill_up_bands: nil}}, _skill), do: false

  def still_useful_at?(%__MODULE__{pattern: %{skill: learned_at, skill_up_bands: bands}}, skill),
    do: skill >= learned_at and WowForeverRecipeFinder.SkillUpBands.still_useful_at?(bands, skill)
end
