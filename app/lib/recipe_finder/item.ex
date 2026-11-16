defmodule WowForeverRecipeFinder.Item do
  @moduledoc """
  A WoW item: either a pattern's crafted output or one of its reagents.
  The same struct serves both roles — see docs/SCHEMA.md.

  Plain struct, no `Ecto.Schema` — see docs/CODE_STYLE.md § Clean
  Architecture. The Ecto-backed persistence shape is
  `WowForeverRecipeFinder.Gateways.Schema.Item`.
  """

  @enforce_keys [:wowhead_id, :display_name, :wiki_slug]
  defstruct [:id, :wowhead_id, :display_name, :wiki_slug]

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          wowhead_id: pos_integer(),
          display_name: String.t(),
          wiki_slug: String.t()
        }
end
