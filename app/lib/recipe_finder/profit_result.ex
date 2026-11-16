defmodule WowForeverRecipeFinder.ProfitResult do
  @moduledoc """
  A `Pattern` joined against a `PriceSnapshot` — the row the UI renders.
  See docs/PRD.md § 7.3. A field is `nil` (never a fabricated zero) when
  the underlying data to compute it is missing — see
  `missing_data_reasons` and docs/ARCHITECTURE.md § Validate at the
  Boundary, Fail Loudly.
  """

  alias WowForeverRecipeFinder.Pattern

  @enforce_keys [:pattern, :missing_data_reasons]
  defstruct [
    :pattern,
    :price_copper,
    :sold_per_day,
    :sale_confidence_pct,
    :mat_cost_copper,
    :net_profit_per_unit_copper,
    :profit_pct,
    :missing_data_reasons
  ]

  @type missing_data_reason ::
          :no_item_id | :no_sale_data | :no_reagents_found | :missing_reagent_price

  @type t :: %__MODULE__{
          pattern: Pattern.t(),
          price_copper: non_neg_integer() | nil,
          sold_per_day: float() | nil,
          sale_confidence_pct: float() | nil,
          mat_cost_copper: non_neg_integer() | nil,
          net_profit_per_unit_copper: integer() | nil,
          profit_pct: float() | nil,
          missing_data_reasons: [missing_data_reason()]
        }

  @spec profitable?(t()) :: boolean()
  def profitable?(%__MODULE__{net_profit_per_unit_copper: nil}), do: false
  def profitable?(%__MODULE__{net_profit_per_unit_copper: profit}), do: profit > 0
end
