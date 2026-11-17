defmodule WowForeverRecipeFinder.WritAtlasLoadError do
  @moduledoc """
  A writ or world-map data file couldn't be read or didn't have the
  expected shape. Carries which file and why, per docs/CODE_STYLE.md §
  Error Handling.
  """

  @enforce_keys [:file, :reason]
  defstruct @enforce_keys

  @type t :: %__MODULE__{file: Path.t(), reason: term()}
end
