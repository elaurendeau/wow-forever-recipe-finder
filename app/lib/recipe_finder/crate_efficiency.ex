defmodule WowForeverRecipeFinder.CrateEfficiency do
  @moduledoc """
  The use case behind docs/PRD.md § 7.11: join the Waylaid Crate
  catalog against an uploaded `PriceSnapshot` to produce one
  `CrateEfficiencyResult` per crate, ranking crates by total AH cost
  (the crate itself plus the cheapest priceable fill option) — cheaper
  is more cost-effective, since every crate becomes exactly one Sealed
  Crate of its own tier regardless of which fill option is used.
  Fetching the catalog goes through the configured
  `CrateRepositoryGateway` (Dependency Inversion, per docs/CODE_STYLE.md
  § SOLID); the join/compute itself is a pure function with no I/O,
  independently unit-testable — see `compute_result/2`.

  **Cost is always the AH "Recent Value"** (`recent_value_copper`,
  TSM's realm-level figure), same deliberate choice as `WritEfficiency`
  — never this app's crafting-reagent-cost engine.
  """

  alias WowForeverRecipeFinder.{CrateEfficiencyResult, FillOption, PriceSnapshot, WaylaidCrate}

  @doc "Every crate in the catalog, joined against an already-parsed `PriceSnapshot`, sorted by total cost ascending (cheapest first)."
  @spec compute_results(PriceSnapshot.t()) :: [CrateEfficiencyResult.t()]
  def compute_results(%PriceSnapshot{} = snapshot) do
    crate_gateway().list_crates()
    |> Enum.map(&compute_result(&1, snapshot))
    |> Enum.sort_by(&sort_key/1)
  end

  @doc """
  The pure join/compute for one crate against one snapshot — no
  gateway call, no I/O. A field is `nil`, with its reason recorded in
  `missing_data_reasons`, whenever the data to compute it isn't
  there; never a fabricated zero.
  """
  @spec compute_result(WaylaidCrate.t(), PriceSnapshot.t()) :: CrateEfficiencyResult.t()
  def compute_result(%WaylaidCrate{} = crate, %PriceSnapshot{} = snapshot) do
    reasons = []

    {crate_cost, reasons} =
      case fetch_recent_value(crate.wowhead_id, snapshot) do
        {:ok, copper} -> {copper, reasons}
        :error -> {nil, [:missing_crate_recent_value | reasons]}
      end

    {best_option, fill_cost, reasons} =
      pick_best_fill_option(crate.fill_options, snapshot, reasons)

    %CrateEfficiencyResult{
      crate: crate,
      crate_cost_copper: crate_cost,
      best_fill_option: best_option,
      fill_cost_copper: fill_cost,
      total_cost_copper: sum_if_both_present(crate_cost, fill_cost),
      missing_data_reasons: Enum.reverse(reasons)
    }
  end

  # `nil` means the extraction hasn't captured this crate's fill
  # options at all yet — never treat that as "needs nothing".
  defp pick_best_fill_option(nil, _snapshot, reasons) do
    {nil, nil, [:no_fill_options_data | reasons]}
  end

  defp pick_best_fill_option(options, snapshot, reasons) do
    priced =
      options
      |> Enum.map(&{&1, priced_option_cost(&1, snapshot)})
      |> Enum.reject(fn {_option, cost} -> cost == nil end)

    case priced do
      [] ->
        {nil, nil, [:no_priceable_fill_option | reasons]}

      priced ->
        {option, cost} = Enum.min_by(priced, fn {_option, cost} -> cost end)
        {option, cost, reasons}
    end
  end

  # A fill option with no `wowhead_id` at all (this app's catalog
  # never resolved it — e.g. raw Ore, see docs/DATA_SOURCES.md) can
  # never be priced, same as one whose price isn't in this snapshot.
  defp priced_option_cost(%FillOption{wowhead_id: nil}, _snapshot), do: nil

  defp priced_option_cost(%FillOption{wowhead_id: wowhead_id, quantity: quantity}, snapshot) do
    case fetch_recent_value(wowhead_id, snapshot) do
      {:ok, copper} -> copper * quantity
      :error -> nil
    end
  end

  defp fetch_recent_value(wowhead_id, snapshot) do
    case PriceSnapshot.fetch_price(snapshot, wowhead_id) do
      {:ok, %{recent_value_copper: copper}} when is_integer(copper) -> {:ok, copper}
      _missing -> :error
    end
  end

  defp sum_if_both_present(a, b) when is_integer(a) and is_integer(b), do: a + b
  defp sum_if_both_present(_a, _b), do: nil

  defp sort_key(%CrateEfficiencyResult{total_cost_copper: nil}), do: {1, 0}
  defp sort_key(%CrateEfficiencyResult{total_cost_copper: v}), do: {0, v}

  defp crate_gateway do
    Application.get_env(
      :recipe_finder,
      :crate_repository_gateway,
      WowForeverRecipeFinder.Gateways.EctoCrateRepositoryGateway
    )
  end
end
