defmodule WowForeverRecipeFinder.WritRequiredItem do
  @moduledoc """
  One item a Craftsman's Writ requires as a turn-in, alongside the
  quantity needed. Always costed at its AH Recent Value, never via
  this app's crafting-reagent-cost engine, even for an item we
  already track as a pattern elsewhere — see docs/PRD.md § 7.8.

  Deliberately not the same `WowForeverRecipeFinder.Item` struct used
  by the profession catalogs: a writ's items are Wowhead-sourced
  AH-tradeable items, not Warcraft-Wiki-resolved crafting-catalog
  entries, and have no meaningful `wiki_slug` — see docs/SCHEMA.md §
  Craftsman's Writ catalog.
  """

  @enforce_keys [:wowhead_id, :display_name, :quantity]
  defstruct [:wowhead_id, :display_name, :quantity]

  @type t :: %__MODULE__{
          wowhead_id: pos_integer(),
          display_name: String.t(),
          quantity: pos_integer()
        }
end
