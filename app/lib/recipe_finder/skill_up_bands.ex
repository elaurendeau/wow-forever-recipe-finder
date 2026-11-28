defmodule WowForeverRecipeFinder.SkillUpBands do
  @moduledoc """
  A pattern's real, Forever-verified skill-up thresholds — read from
  Wowhead's own `g_listviews.spells.data[].colors` field (a 4-element
  `[orange, yellow, green, grey]` array), not assumed from Classic
  WoW's generic formula. See docs/PRD.md § 7.13 and
  docs/DATA_SOURCES.md for the full provenance and how this was
  verified against ~2,300 real captured recipes.

  **A `nil` band means Wowhead's own data skips it for this recipe —
  never a literal "skill 0" threshold.** Checked directly across the
  real capture: a skipped band is always a leading one (orange, then
  orange+yellow, then orange+yellow+green — never a gap in the
  middle), and `grey` is never `0`/skipped in any of ~2,300 recipes
  checked. A pattern simply stops giving skill-ups once the visitor's
  skill reaches `grey` — that's the one number every recipe has.

  The *probability* of a skill-up within a band the visitor's current
  skill falls into (100% orange, high-but-not-certain yellow, low
  green) is **not** in this data — Wowhead's own page doesn't carry
  per-recipe percentages, only the band boundaries. `ProfessionLeveling`
  applies a labeled-approximate standard curve for that; the
  boundaries themselves are real, not approximated.
  """

  @enforce_keys [:grey]
  defstruct [:orange, :yellow, :green, :grey]

  @type t :: %__MODULE__{
          orange: pos_integer() | nil,
          yellow: pos_integer() | nil,
          green: pos_integer() | nil,
          grey: pos_integer()
        }

  @doc "Whether this recipe can still grant a skill-up at the given skill level at all — strictly below `grey`, never equal to or above it. The real, factual boundary; see `worth_crafting_at?/2` for the Profession Leveling page's own, stricter cutoff."
  @spec still_useful_at?(t(), non_neg_integer()) :: boolean()
  def still_useful_at?(%__MODULE__{grey: grey}, skill), do: skill < grey

  @doc """
  Whether this recipe is still *worth* crafting for leveling — strictly
  below `green`, not `grey`. A visitor's own explicit choice: once a
  recipe turns green, its skill-up chance is low enough (see
  `SkillUpCurve`) that switching to a different recipe, or accepting a
  gap, beats grinding it out. Falls back to `grey` when `green` itself
  is unknown (Wowhead's own leading-zero-skip, or the rare recipe with
  no band data past grey at all) — never silently treating an unknown
  green threshold as "always past it."
  """
  @spec worth_crafting_at?(t(), non_neg_integer()) :: boolean()
  def worth_crafting_at?(%__MODULE__{green: green, grey: grey}, skill),
    do: skill < (green || grey)
end
