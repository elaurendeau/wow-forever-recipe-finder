defmodule WowForeverRecipeFinder.ItemPrice do
  @moduledoc """
  One item's price/volume figures from a TSM export. `price_copper`,
  `sold_per_day` and `sale_confidence_pct` come from the region-wide
  `AUCTIONDB_REGION_SALE` table (see docs/DATA_SOURCES.md § TSM Export
  Format for the field scaling — already descaled here, never the raw
  base-32-decoded integers). `recent_value_copper` is a separate,
  optional figure from the realm-level `AUCTIONDB_NON_COMMODITY_DATA`
  table ("Recent Value" in TSM's own tooltip) — `nil` for any item TSM
  only tracks as a commodity, which that table doesn't cover at all.
  """

  @enforce_keys [:wowhead_id, :price_copper, :sold_per_day, :sale_confidence_pct]
  defstruct [:wowhead_id, :price_copper, :sold_per_day, :sale_confidence_pct, :recent_value_copper]

  @type t :: %__MODULE__{
          wowhead_id: pos_integer(),
          price_copper: non_neg_integer(),
          sold_per_day: float(),
          sale_confidence_pct: float(),
          recent_value_copper: non_neg_integer() | nil
        }
end
