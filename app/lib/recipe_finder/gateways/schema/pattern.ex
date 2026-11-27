defmodule WowForeverRecipeFinder.Gateways.Schema.Pattern do
  @moduledoc """
  Ecto-backed persistence shape for a pattern row. See
  docs/CODE_STYLE.md § Clean Architecture and docs/SCHEMA.md.
  """

  use Ecto.Schema

  alias WowForeverRecipeFinder.Gateways.Schema.{Item, PatternReagent, Profession}

  schema "pattern" do
    field :name, :string
    field :tier, :string
    field :skill, :integer
    field :source, :string
    field :wiki_slug, :string
    field :resolution_status, :string
    field :skill_up_colors, {:array, :integer}
    field :recipe_cost_item, :map

    belongs_to :profession, Profession
    belongs_to :crafted_item, Item
    has_many :pattern_reagents, PatternReagent

    timestamps(type: :utc_datetime)
  end
end
