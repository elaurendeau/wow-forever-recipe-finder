defmodule WowForeverRecipeFinder.SkillUpCurve do
  @moduledoc """
  **ESTIMATED, not Forever-verified** — per-craft skill-up probability
  within a recipe's real `SkillUpBands`, used only to project an
  "expected crafts" count (and the total cost/total sell that depend on
  it) for the Profession Leveling page. It plays no part in deciding
  *which* recipe is still worth crafting at a given skill — that
  decision (`SkillUpBands.worth_crafting_at?/2`) uses only the real
  captured band boundaries, never this curve. Same "estimated, inferred,
  not confirmed" discipline as `MerchantFavorFormula`.

  **The formula:** a single linear decline from 100% at the recipe's own
  `yellow` threshold down to 0% at `grey`, with 100% below `yellow` (the
  orange range) and 0% at or past `grey`:

      P(skill) = 1.0                              , skill < yellow
      P(skill) = (grey - skill) / (grey - yellow)  , yellow <= skill < grey
      P(skill) = 0.0                               , skill >= grey

  This is the commonly-cited Classic-era WoW community formula (see
  Gamerant's WotLK Classic professions guide, which credits it to the
  `SkillUpProbability` addon's own stated source) — **not** official
  Blizzard documentation, **not** Forever-specific, and it deliberately
  ignores `green` as a separate breakpoint: green is treated as a
  cosmetic recoloring partway down the same declining line, not a
  second slope. No public source has a real per-recipe probability
  curve for WoW Forever, so this is the best available estimate, used
  only where the visitor explicitly asked for a craft-count projection
  and accepted that it would be an estimate (see docs/PRD.md § 7.13).

  **When `yellow` is unknown** (Wowhead's own leading-zero-skip — the
  recipe starts already yellow or green the moment it's learnable, see
  `SkillUpBands`'s own doc), there is no "100%-until-here" point to
  anchor the decline to. The recipe's own `skill` (learned-at) field is
  used as the anchor instead: the decline is treated as starting
  immediately, which is the closest honest reading of "no orange or
  yellow phase was recorded for this recipe."
  """

  alias WowForeverRecipeFinder.SkillUpBands

  @doc "Estimated chance this recipe grants a skill-up at `skill`, given it was learned at `learned_at`. See this module's own doc for the formula and its real-world caveats."
  @spec probability(SkillUpBands.t(), pos_integer(), pos_integer()) :: float()
  def probability(%SkillUpBands{yellow: yellow, grey: grey}, skill, learned_at) do
    anchor = yellow || learned_at

    cond do
      skill < anchor -> 1.0
      skill >= grey -> 0.0
      true -> (grey - skill) / (grey - anchor) * 1.0
    end
  end

  @doc """
  Estimated number of crafts needed to go from `from_skill` through
  `to_skill` (inclusive on both ends — every skill point in that range
  needs its own skill-up) — the sum of `1 / probability(skill)` across
  that range, since each skill point needs on average that many crafts
  to land one success. A rough, labeled estimate, never shown as fact.
  """
  @spec expected_crafts(SkillUpBands.t(), pos_integer(), pos_integer(), pos_integer()) :: float()
  def expected_crafts(%SkillUpBands{} = bands, learned_at, from_skill, to_skill) do
    from_skill..to_skill
    |> Enum.map(&(1.0 / probability(bands, &1, learned_at)))
    |> Enum.sum()
  end
end
