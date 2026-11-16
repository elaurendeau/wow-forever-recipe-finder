defmodule WowForeverRecipeFinder.WritEfficiencyResult do
  @moduledoc """
  A `Writ` joined against a `PriceSnapshot` — the row the Writs page
  renders. See docs/PRD.md § 7.8. A field is `nil` (never a
  fabricated zero) when the underlying data to compute it is
  missing — see `missing_data_reasons` and docs/ARCHITECTURE.md §
  Validate at the Boundary, Fail Loudly.
  """

  alias WowForeverRecipeFinder.Writ

  @enforce_keys [:writ, :total_reputation, :missing_data_reasons]
  defstruct [
    :writ,
    :writ_item_cost_copper,
    :required_items_cost_copper,
    :total_cost_copper,
    :total_reputation,
    :rep_per_gold,
    :missing_data_reasons,
    required_item_breakdown: []
  ]

  @type missing_data_reason ::
          :no_required_items_data
          | :missing_writ_item_recent_value
          | :missing_required_item_recent_value

  @typedoc "One required-item line for the Cost column's hover tooltip — see docs/PRD.md § 7.8."
  @type required_item_line :: %{
          display_name: String.t(),
          quantity: pos_integer(),
          unit_price_copper: non_neg_integer() | nil,
          line_total_copper: non_neg_integer() | nil
        }

  @type t :: %__MODULE__{
          writ: Writ.t(),
          writ_item_cost_copper: non_neg_integer() | nil,
          required_items_cost_copper: non_neg_integer() | nil,
          total_cost_copper: non_neg_integer() | nil,
          total_reputation: non_neg_integer(),
          rep_per_gold: float() | nil,
          missing_data_reasons: [missing_data_reason()],
          required_item_breakdown: [required_item_line()]
        }
end
