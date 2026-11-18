defmodule WowForeverRecipeFinder.WaylaidCrate do
  @moduledoc """
  A Waylaid Crate: an AH-tradeable (or looted) item that, filled with
  any ONE of its `fill_options`, becomes a Sealed Crate turned in for
  Merchant's Favor. See docs/PRD.md § 7.11. Plain struct — see
  docs/CODE_STYLE.md § Clean Architecture. The Ecto-backed persistence
  shape is `WowForeverRecipeFinder.Gateways.Schema.WaylaidCrate`.

  Turning a crate in for Merchant's Favor isn't modeled yet — the
  mapping from a Sealed Crate to how much Favor it pays isn't resolved
  in the source extraction (see docs/DATA_SOURCES.md). This struct
  only carries what's needed to rank crates by AH cost.
  """

  alias WowForeverRecipeFinder.FillOption

  @enforce_keys [
    :name,
    :tier,
    :category,
    :quality,
    :wowhead_id,
    :required_level,
    :fill_options
  ]
  defstruct [
    :id,
    :name,
    :tier,
    :category,
    :variant,
    :quality,
    :wowhead_id,
    :required_level,
    :fill_options
  ]

  @type tier :: :apprentice | :journeyman | :expert | :artisan
  @type quality :: :common | :uncommon

  @typedoc """
  `nil` means the fill options for this crate weren't captured yet
  (Wowhead rate-limited the extraction session) — not that the crate
  needs nothing. Never treat `nil` as an empty list.
  """
  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          name: String.t(),
          tier: tier(),
          category: String.t(),
          variant: String.t() | nil,
          quality: quality(),
          wowhead_id: pos_integer(),
          required_level: pos_integer(),
          fill_options: [FillOption.t()] | nil
        }
end
