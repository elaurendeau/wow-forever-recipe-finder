defmodule WowForeverRecipeFinder.LevelingResult do
  @moduledoc """
  A `Pattern` joined against a `PriceSnapshot` for the Profession
  Leveling page — reuses `ProfitComputation`'s own per-craft profit
  math (same price basis, never duplicated) and adds the one-time
  recipe cost (if the recipe must be bought) and the real skill-up
  band this recipe has. See docs/PRD.md § 7.13.
  """

  alias WowForeverRecipeFinder.{Pattern, ProfitResult, SkillUpBands, SkillUpCurve}

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
  Still worth crafting at the given skill level for leveling — both
  learnable (`skill >= pattern.skill`) and not yet turned green (per
  the visitor's own explicit "stop once it's green" preference; see
  `SkillUpBands.worth_crafting_at?/2`). `false` (never a fabricated
  yes) when the recipe has no known skill-up band at all.
  """
  @spec still_useful_at?(t(), non_neg_integer()) :: boolean()
  def still_useful_at?(%__MODULE__{pattern: %{skill_up_bands: nil}}, _skill), do: false

  def still_useful_at?(%__MODULE__{pattern: %{skill: learned_at, skill_up_bands: bands}}, skill),
    do: skill >= learned_at and SkillUpBands.worth_crafting_at?(bands, skill)

  @doc """
  Estimated crafts needed to go from `from_skill` through `to_skill`
  with this recipe — see `SkillUpCurve`'s own doc for the formula and
  why it's an estimate, never a fact. `nil` when this recipe has no
  known skill-up band at all (never a fabricated number).
  """
  @spec expected_crafts(t(), pos_integer(), pos_integer()) :: float() | nil
  def expected_crafts(%__MODULE__{pattern: %{skill_up_bands: nil}}, _from, _to), do: nil

  def expected_crafts(
        %__MODULE__{pattern: %{skill: learned_at, skill_up_bands: bands}},
        from,
        to
      ),
      do: SkillUpCurve.expected_crafts(bands, learned_at, from, to)

  @doc "Total reagent cost across `crafts` crafts — the per-craft `mat_cost_copper` times `crafts`. Always known for a result that `never_loses_money?/1` ever accepted (that already required a known mat cost)."
  @spec total_reagent_cost_copper(t(), pos_integer()) :: non_neg_integer()
  def total_reagent_cost_copper(%__MODULE__{profit_result: %{mat_cost_copper: cost}}, crafts),
    do: cost * crafts

  @doc """
  Total cost across `crafts` crafts: the reagent total, plus the
  recipe's own one-time AH purchase if it has one. Branches on
  `recipe_cost_item` itself, never on `pattern.source` — a pattern with
  no recorded source at all (a real, non-trivial share of the catalog —
  see docs/DATA_SOURCES.md) is not "unknown whether it needs a
  purchase," it's simply read the same as a trainer recipe: no
  `recipe_cost_item` attached, no one-time cost to add. Only a recipe
  whose purchase item IS known but whose price isn't in the current
  snapshot makes the whole total `nil` — that's the one case where a
  real cost exists and genuinely can't be quantified; never silently
  treated as free.
  """
  @spec total_cost_copper(t(), pos_integer()) :: non_neg_integer() | nil
  def total_cost_copper(%__MODULE__{pattern: %{recipe_cost_item: nil}} = result, crafts),
    do: total_reagent_cost_copper(result, crafts)

  def total_cost_copper(%__MODULE__{recipe_cost_copper: nil}, _crafts), do: nil

  def total_cost_copper(%__MODULE__{recipe_cost_copper: recipe_cost} = result, crafts),
    do: total_reagent_cost_copper(result, crafts) + recipe_cost

  @doc "Total gross sale value across `crafts` crafts — the per-craft list price times `crafts`, before the AH cut (same convention as the Price column elsewhere in this app)."
  @spec total_sell_copper(t(), pos_integer()) :: non_neg_integer()
  def total_sell_copper(%__MODULE__{profit_result: %{price_copper: price}}, crafts),
    do: price * crafts

  @doc """
  Total profit or loss across `crafts` crafts: total sell minus total
  cost — unlike `profit_result.net_profit_per_unit_copper` (per-craft,
  reagents only), this nets out the recipe's own one-time purchase too,
  so it's the real bottom line for actually leveling through this
  segment. `nil` whenever `total_cost_copper/2` itself is (a known
  one-time purchase with no price in the snapshot) — never a partial
  sum presented as the whole.
  """
  @spec total_profit_copper(t(), pos_integer()) :: integer() | nil
  def total_profit_copper(%__MODULE__{} = result, crafts) do
    case total_cost_copper(result, crafts) do
      nil -> nil
      cost -> total_sell_copper(result, crafts) - cost
    end
  end
end
