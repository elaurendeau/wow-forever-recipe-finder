defmodule WowForeverRecipeFinder.Gateways.Schema.Profession do
  @moduledoc """
  Ecto-backed persistence shape for a profession row. See
  docs/CODE_STYLE.md § Clean Architecture.
  """

  use Ecto.Schema

  schema "profession" do
    field :slug, :string
    field :display_name, :string
    field :catalog_built_at, :utc_datetime

    has_many :patterns, WowForeverRecipeFinder.Gateways.Schema.Pattern

    timestamps(type: :utc_datetime)
  end
end
