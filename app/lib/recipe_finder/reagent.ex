defmodule WowForeverRecipeFinder.Reagent do
  @moduledoc """
  One material a pattern consumes: an `Item` plus the quantity required.
  Plain struct — see docs/CODE_STYLE.md § Clean Architecture.
  """

  alias WowForeverRecipeFinder.Item

  @enforce_keys [:item, :quantity]
  defstruct [:item, :quantity]

  @type t :: %__MODULE__{item: Item.t(), quantity: pos_integer()}
end
