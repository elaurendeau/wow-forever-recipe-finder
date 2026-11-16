defmodule WowForeverRecipeFinder.Gateways.Schema.WritRequiredItem do
  @moduledoc """
  Ecto-backed persistence shape for one writ-required-item row. See
  docs/CODE_STYLE.md § Clean Architecture and docs/SCHEMA.md §
  Craftsman's Writ catalog.
  """

  use Ecto.Schema

  alias WowForeverRecipeFinder.Gateways.Schema.Writ

  schema "writ_required_item" do
    field :wowhead_id, :integer
    field :display_name, :string
    field :quantity, :integer

    belongs_to :writ, Writ

    timestamps(type: :utc_datetime)
  end
end
