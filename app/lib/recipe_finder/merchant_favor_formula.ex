defmodule WowForeverRecipeFinder.MerchantFavorFormula do
  @moduledoc """
  How much Merchant's Favor a Sealed Crate pays when turned in, by the
  Waylaid Crate's own tier/quality. See docs/PRD.md § 7.11.

  **This is an INFERRED formula, not a fact read off a Wowhead quest
  page.** The source extraction's 8 captured "A Sealed Crate" hand-in
  quests all have `sealed_crate_id: null` — there is no direct
  Sealed-Crate-to-Favor-amount mapping in the data at all. What IS
  known is 8 raw Favor amounts from those quests: 5, 10, 15, 20, 10,
  20, 30, 40. Those 8 numbers fit, exactly and with zero error,
  `favor = 5 * tier_index * quality_multiplier` for tier_index
  Apprentice=1/Journeyman=2/Expert=3/Artisan=4 and quality_multiplier
  Common=1/Uncommon=2 — the only two quality levels this app's real
  30-crate catalog actually has, so every value this formula is ever
  asked to produce is backed by a real data point, not extrapolated.

  Still: nobody has read a Wowhead quest page confirming "turning in a
  Sealed Apprentice Crate (Common) pays exactly 5 Favor" — Wowhead's
  own CloudFront blocks this app's tooling outright, so that
  confirmation isn't available. Every place this number is shown to a
  visitor says "estimated" — see merchant_favor_live.html.heex — per
  CLAUDE.md's Diagnosis Discipline: a strong pattern-fit is not the
  same thing as a verified fact, and a visitor is about to spend real
  gold on this.
  """

  alias WowForeverRecipeFinder.WaylaidCrate

  @tier_index %{apprentice: 1, journeyman: 2, expert: 3, artisan: 4}
  @quality_multiplier %{common: 1, uncommon: 2}

  @spec favor_amount(WaylaidCrate.tier(), WaylaidCrate.quality()) :: pos_integer()
  def favor_amount(tier, quality) do
    5 * Map.fetch!(@tier_index, tier) * Map.fetch!(@quality_multiplier, quality)
  end
end
