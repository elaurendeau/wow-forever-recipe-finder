defmodule WowForeverRecipeFinder.RecipeCostItem do
  @moduledoc """
  The purchasable item that teaches a `Pattern` — a "Pattern: X" /
  "Plans: X" / "Formula: X" item, for recipes bought rather than
  trained (source `:vendor` | `:drop` | `:quest`; `nil` on the
  `Pattern` itself for `:trainer` recipes, which cost a trivial gold
  fee at an NPC, never an AH purchase). See docs/PRD.md § 7.13 and
  docs/DATA_SOURCES.md for where this came from — a real Wowhead data
  capture, not every non-trainer recipe could be matched to one.
  """

  @enforce_keys [:wowhead_id, :display_name]
  defstruct [:wowhead_id, :display_name, :source_detail]

  @type t :: %__MODULE__{
          wowhead_id: pos_integer(),
          display_name: String.t(),
          source_detail: String.t() | nil
        }
end
