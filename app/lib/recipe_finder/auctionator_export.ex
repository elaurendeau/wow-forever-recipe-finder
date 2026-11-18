defmodule WowForeverRecipeFinder.AuctionatorExport do
  @moduledoc """
  Auctionator's real Shopping List import/export text format, shared
  by `WritShoppingList` and `CrateShoppingList` — verified directly
  from Auctionator's own Lua source (`Atr_ShpList_Export_GetText` /
  `Atr_SList_ImportCore` in `AuctionatorConfig.lua`) rather than
  assumed: a `*** <list name>` header line, then one plain item
  display name per line, **no item IDs and no quantities at all**.
  Quantities are each feature's own display concern and are dropped
  entirely on export; a name appearing more than once is deduplicated,
  since a repeated watch-list entry would be meaningless to it.
  """

  @type line :: %{display_name: String.t()}

  @spec to_text(String.t(), [line()]) :: String.t()
  def to_text(list_name, lines) do
    names = lines |> Enum.uniq_by(& &1.display_name) |> Enum.map(& &1.display_name)
    "*** #{list_name}\n" <> Enum.join(names, "\n") <> "\n"
  end
end
