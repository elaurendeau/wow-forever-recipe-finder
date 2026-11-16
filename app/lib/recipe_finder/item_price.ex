defmodule WowForeverRecipeFinder.ItemPrice do
  @moduledoc """
  One item's region-wide price/volume figures from a TSM export's
  `AUCTIONDB_REGION_SALE` table. See docs/DATA_SOURCES.md § TSM Export
  Format for the field scaling (`sold_per_day`/`sale_confidence_pct` are
  already descaled here — never the raw base-32-decoded integers).
  """

  @enforce_keys [:wowhead_id, :price_copper, :sold_per_day, :sale_confidence_pct]
  defstruct [:wowhead_id, :price_copper, :sold_per_day, :sale_confidence_pct]

  @type t :: %__MODULE__{
          wowhead_id: pos_integer(),
          price_copper: non_neg_integer(),
          sold_per_day: float(),
          sale_confidence_pct: float()
        }
end
