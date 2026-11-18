defmodule WowForeverRecipeFinder.Gateways.Schema.WaylaidCrateFillOption do
  @moduledoc """
  Ecto-backed persistence shape for one crate fill-option row. See
  docs/CODE_STYLE.md § Clean Architecture and docs/SCHEMA.md §
  Waylaid Crate catalog.
  """

  use Ecto.Schema

  alias WowForeverRecipeFinder.Gateways.Schema.WaylaidCrate

  schema "waylaid_crate_fill_option" do
    field :display_name, :string
    field :wowhead_id, :integer
    field :quantity, :integer

    belongs_to :waylaid_crate, WaylaidCrate

    timestamps(type: :utc_datetime)
  end
end
