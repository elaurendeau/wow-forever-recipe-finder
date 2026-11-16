defmodule WowForeverRecipeFinder.PriceSnapshot do
  @moduledoc """
  A whole parsed TSM export: every item's `ItemPrice`, keyed by Wowhead
  item ID, plus when the export itself was taken (if determinable) for
  the data-freshness indicator (docs/PRD.md § 7.7). Never persisted —
  see docs/ARCHITECTURE.md § Processing Architecture and
  docs/SCHEMA.md's "Deliberately not a table" section.
  """

  alias WowForeverRecipeFinder.ItemPrice

  @enforce_keys [:prices_by_item_id]
  defstruct [:prices_by_item_id, :captured_at]

  @type t :: %__MODULE__{
          prices_by_item_id: %{pos_integer() => ItemPrice.t()},
          captured_at: DateTime.t() | nil
        }

  @spec fetch_price(t(), pos_integer()) :: {:ok, ItemPrice.t()} | :error
  def fetch_price(%__MODULE__{prices_by_item_id: prices}, wowhead_id) do
    Map.fetch(prices, wowhead_id)
  end
end
