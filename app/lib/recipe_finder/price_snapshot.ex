defmodule WowForeverRecipeFinder.PriceSnapshot do
  @moduledoc """
  A whole parsed TSM export: every item's `ItemPrice`, keyed by Wowhead
  item ID, plus when the export itself was taken (if determinable) for
  the data-freshness indicator (docs/PRD.md § 7.7). Never persisted —
  see docs/ARCHITECTURE.md § Processing Architecture and
  docs/SCHEMA.md's "Deliberately not a table" section.

  Per docs/PRD.md's realm-selection requirement: `price_copper`/
  `sold_per_day`/`sale_confidence_pct` come from the region-wide
  `AUCTIONDB_REGION_SALE` table and are the same regardless of realm,
  but `recent_value_copper` comes from the realm-level
  `AUCTIONDB_NON_COMMODITY_DATA` table, and TSM keeps history for
  every realm it has ever scanned (not just the one currently played)
  — so a visitor's export can carry several, and the "right" one isn't
  something this app can guess correctly on its own. `recent_values_by_realm`
  keeps every realm's figures separately; `prices_by_item_id`'s
  `recent_value_copper` reflects whichever realm is currently selected
  (`realm`) — call `for_realm/2` to switch. Never blended across
  realms: an item's Recent Value is either the selected realm's own
  figure or `nil`, never a different realm's figure standing in for it.
  """

  alias WowForeverRecipeFinder.ItemPrice

  @enforce_keys [:prices_by_item_id]
  defstruct [
    :prices_by_item_id,
    :captured_at,
    :realm,
    available_realms: [],
    recent_values_by_realm: %{}
  ]

  @type t :: %__MODULE__{
          prices_by_item_id: %{pos_integer() => ItemPrice.t()},
          captured_at: DateTime.t() | nil,
          realm: String.t() | nil,
          available_realms: [String.t()],
          recent_values_by_realm: %{String.t() => %{pos_integer() => non_neg_integer()}}
        }

  @spec fetch_price(t(), pos_integer()) :: {:ok, ItemPrice.t()} | :error
  def fetch_price(%__MODULE__{prices_by_item_id: prices}, wowhead_id) do
    Map.fetch(prices, wowhead_id)
  end

  @doc """
  Returns a snapshot whose `recent_value_copper` figures come only
  from `realm`'s own `AUCTIONDB_NON_COMMODITY_DATA` data — an item
  that realm never scanned gets `nil`, never another realm's figure.
  A no-op (same snapshot back, keeping whichever realm it already had
  — e.g. the parser's own most-recently-scanned default) when `realm`
  is `nil` or isn't one of `available_realms`, so a caller can pass
  "no explicit choice yet" or a stale/unknown saved choice safely,
  without that ever meaning "show no Recent Values at all."
  """
  @spec for_realm(t(), String.t() | nil) :: t()
  def for_realm(%__MODULE__{available_realms: available} = snapshot, realm) do
    if realm in available do
      realm_values = Map.get(snapshot.recent_values_by_realm, realm, %{})

      prices =
        Map.new(snapshot.prices_by_item_id, fn {wowhead_id, price} ->
          {wowhead_id, %{price | recent_value_copper: Map.get(realm_values, wowhead_id)}}
        end)

      %{snapshot | realm: realm, prices_by_item_id: prices}
    else
      snapshot
    end
  end
end
