defmodule WowForeverRecipeFinder do
  @moduledoc """
  WowForeverRecipeFinder keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  # Core boundary (Entities + Contexts + Gateways), per docs/CODE_STYLE.md
  # § Clean Architecture. `Repo` is deliberately left unexported: nothing
  # outside this boundary may call it directly — every read/write goes
  # through a context function, per the Humble Object rule for LiveView.
  # `exports` grows to list each context module as one is added; nothing
  # to export yet since no context API exists. `DataCase` is exported
  # because it's genuinely meant to be used from any test, anywhere
  # (that's its whole purpose as a shared `ExUnit.CaseTemplate`) — not a
  # loosening of the rule for real application code. Deliberately no
  # other `deps` on the web boundary — see
  # `WowForeverRecipeFinder.Application` for the one place that
  # legitimately needs one, carved out as its own nested boundary so
  # this top-level one stays acyclic with Web's own
  # `deps: [WowForeverRecipeFinder]`.
  # `DataCase` is only ever compiled under MIX_ENV=test (it lives in
  # test/support, outside :dev/:prod's elixirc_paths), so it's only
  # listed as an export in :test — statically listing it otherwise
  # would itself warn ("unknown module listed as export") since the
  # module doesn't exist to check in those environments.
  test_only_exports = if Mix.env() == :test, do: [DataCase], else: []
  use Boundary,
    deps: [],
    exports: [ProfitComputation, CatalogSeeder, ProfitResult, ResultsFilter] ++ test_only_exports
end
