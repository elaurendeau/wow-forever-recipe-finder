defmodule WowForeverRecipeFinder.Gateways.Schema.PatternReagent do
  @moduledoc """
  Ecto-backed persistence shape for one pattern-reagent row. See
  docs/CODE_STYLE.md § Clean Architecture and docs/SCHEMA.md.
  """

  use Ecto.Schema

  alias WowForeverRecipeFinder.Gateways.Schema.{Item, Pattern}

  schema "pattern_reagent" do
    field :quantity, :integer

    belongs_to :pattern, Pattern
    belongs_to :item, Item

    timestamps(type: :utc_datetime)
  end
end
