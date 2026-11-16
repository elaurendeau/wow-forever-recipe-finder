defmodule WowForeverRecipeFinder.Pattern do
  @moduledoc """
  A profession recipe: scraped from Warcraft Wiki, stored in the shared
  catalog (docs/SCHEMA.md). Plain struct — see docs/CODE_STYLE.md § Clean
  Architecture. The Ecto-backed persistence shape is
  `WowForeverRecipeFinder.Gateways.Schema.Pattern`.
  """

  alias WowForeverRecipeFinder.{Item, Reagent}

  @enforce_keys [
    :profession_slug,
    :crafted_item,
    :name,
    :tier,
    :skill,
    :wiki_slug,
    :resolution_status,
    :reagents
  ]
  defstruct [
    :id,
    :profession_slug,
    :crafted_item,
    :name,
    :tier,
    :skill,
    :source,
    :wiki_slug,
    :resolution_status,
    :reagents
  ]

  @type tier :: :apprentice | :journeyman | :expert | :artisan
  @type source :: :trainer | :vendor | :drop | :quest | nil
  @type resolution_status :: :resolved | :no_wiki_page | :reagent_cost_incomplete

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          profession_slug: String.t(),
          crafted_item: Item.t(),
          name: String.t(),
          tier: tier(),
          skill: non_neg_integer(),
          source: source(),
          wiki_slug: String.t(),
          resolution_status: resolution_status(),
          reagents: [Reagent.t()]
        }
end
