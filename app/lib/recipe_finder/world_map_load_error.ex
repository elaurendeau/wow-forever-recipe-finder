defmodule WowForeverRecipeFinder.WorldMapLoadError do
  @moduledoc """
  A named, specific error for a missing/malformed world-map vector
  file — per docs/CODE_STYLE.md § Error Handling: validate at the
  boundary, fail loudly, never a bare string or a silently empty map.
  """

  @enforce_keys [:file, :reason]
  defstruct @enforce_keys

  @type t :: %__MODULE__{file: String.t(), reason: term()}
end
