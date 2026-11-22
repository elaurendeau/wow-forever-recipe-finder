defmodule WowForeverRecipeFinder.CrateEfficiencyResult do
  @moduledoc """
  A `WaylaidCrate` joined against a `PriceSnapshot` — the row the
  Merchant's Favor page renders. See docs/PRD.md § 7.11. A field is
  `nil` (never a fabricated zero) when the underlying data to compute
  it is missing — see `missing_data_reasons` and docs/ARCHITECTURE.md
  § Validate at the Boundary, Fail Loudly.
  """

  alias WowForeverRecipeFinder.WaylaidCrate

  @enforce_keys [:crate, :favor_amount, :missing_data_reasons]
  defstruct [
    :crate,
    :crate_cost_copper,
    :best_fill_option,
    :fill_cost_copper,
    :total_cost_copper,
    :favor_amount,
    :price_per_favor_copper,
    :missing_data_reasons
  ]

  @type missing_data_reason ::
          :missing_crate_recent_value
          | :no_fill_options_data
          | :no_priceable_fill_option

  @type t :: %__MODULE__{
          crate: WaylaidCrate.t(),
          crate_cost_copper: non_neg_integer() | nil,
          best_fill_option: WowForeverRecipeFinder.FillOption.t() | nil,
          fill_cost_copper: non_neg_integer() | nil,
          total_cost_copper: non_neg_integer() | nil,
          # Per MerchantFavorFormula's own doc: an inferred, not a
          # Wowhead-confirmed figure — always shown as "estimated".
          favor_amount: pos_integer(),
          price_per_favor_copper: non_neg_integer() | nil,
          missing_data_reasons: [missing_data_reason()]
        }
end
