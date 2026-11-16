defmodule WowForeverRecipeFinder.Gateways.Schema.Item do
  @moduledoc """
  Ecto-backed persistence shape for `WowForeverRecipeFinder.Item` — see
  docs/CODE_STYLE.md § Clean Architecture for why these are two separate
  modules rather than one. Nothing outside the Gateways layer should
  reference this module directly.
  """

  use Ecto.Schema

  schema "item" do
    field :wowhead_id, :integer
    field :display_name, :string
    field :wiki_slug, :string

    timestamps(type: :utc_datetime)
  end
end
