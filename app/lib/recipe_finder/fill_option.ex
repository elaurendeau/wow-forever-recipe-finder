defmodule WowForeverRecipeFinder.FillOption do
  @moduledoc """
  One material bundle that can fill a `WaylaidCrate` — any ONE of a
  crate's fill options turns it into a Sealed Crate (see
  docs/PRD.md § 7.11). `wowhead_id` is `nil` when this app's
  catalog has no item-ID resolution for the material (e.g. raw Ore —
  Mining was never scraped into the profession catalogs, since it has
  no crafted output; see docs/DATA_SOURCES.md), in which case this
  option's cost can never be computed, not even once a snapshot is
  uploaded.
  """

  @enforce_keys [:display_name, :quantity]
  defstruct [:display_name, :wowhead_id, :quantity]

  @type t :: %__MODULE__{
          display_name: String.t(),
          wowhead_id: pos_integer() | nil,
          quantity: pos_integer()
        }
end
