defmodule WowForeverRecipeFinder.ProfitComputation do
  @moduledoc """
  The use case behind docs/PRD.md § 7.3: join a profession's catalog
  against an uploaded `PriceSnapshot` to produce one `ProfitResult` per
  pattern. Fetching the catalog goes through the configured
  `CatalogRepositoryGateway` (Dependency Inversion, per
  docs/CODE_STYLE.md § SOLID); the join/compute itself is a pure
  function with no I/O, independently unit-testable — see
  `compute_result/2` and docs/ELIXIR_TEST_MANIFESTO.md § What Still
  Gets a Plain Unit Test.
  """

  alias WowForeverRecipeFinder.{Pattern, PriceSnapshot, ProfitResult, TsmExportParser}

  @doc """
  Parses an uploaded TSM export into a `PriceSnapshot`. A thin pass-
  through to `TsmExportParser` — exists so Web only ever calls into this
  context module, never a parser/gateway directly, per
  docs/CODE_STYLE.md's Humble Object rule.
  """
  @spec parse_export(binary()) :: {:ok, PriceSnapshot.t()} | {:error, term()}
  def parse_export(export_text), do: TsmExportParser.parse(export_text)

  @doc "Every profession slug that has a built catalog — per docs/PRD.md § 7.4, tabs with none yet render a placeholder instead."
  @spec known_profession_slugs() :: [String.t()]
  def known_profession_slugs, do: catalog_gateway().known_profession_slugs()

  @doc """
  Every `ProfitResult` for a profession, given an already-parsed
  `PriceSnapshot`. Results are sorted by net profit/day descending, with
  patterns missing a computable profit sorted last — mirrors the
  ordering this project's own earlier Python prototype used.
  """
  @spec compute_results(String.t(), PriceSnapshot.t()) :: [ProfitResult.t()]
  def compute_results(profession_slug, %PriceSnapshot{} = snapshot) do
    profession_slug
    |> catalog_gateway().list_patterns()
    |> Enum.map(&compute_result(&1, snapshot))
    |> Enum.sort_by(&sort_key/1)
  end

  @doc """
  The pure join/compute for one pattern against one snapshot — no
  gateway call, no I/O. A field is `nil`, with its reason recorded in
  `missing_data_reasons`, whenever the data to compute it isn't there;
  never a fabricated zero. See docs/ARCHITECTURE.md § Validate at the
  Boundary, Fail Loudly.
  """
  @spec compute_result(Pattern.t(), PriceSnapshot.t()) :: ProfitResult.t()
  def compute_result(%Pattern{} = pattern, %PriceSnapshot{} = snapshot) do
    reasons = []

    {price, sold_per_day, confidence, reasons} =
      case PriceSnapshot.fetch_price(snapshot, pattern.crafted_item.wowhead_id) do
        {:ok, item_price} ->
          {item_price.price_copper, item_price.sold_per_day, item_price.sale_confidence_pct, reasons}

        :error ->
          {nil, nil, nil, [:no_sale_data | reasons]}
      end

    {mat_cost, reasons} =
      case pattern.reagents do
        [] ->
          {nil, [:no_reagents_found | reasons]}

        reagents ->
          sum_reagent_cost(reagents, snapshot, reasons)
      end

    {net_profit_per_unit, net_profit_per_day} =
      case {price, mat_cost, sold_per_day} do
        {p, m, spd} when is_integer(p) and is_integer(m) and is_float(spd) ->
          unit = p - m
          {unit, unit * spd}

        _incomplete ->
          {nil, nil}
      end

    %ProfitResult{
      pattern: pattern,
      price_copper: price,
      sold_per_day: sold_per_day,
      sale_confidence_pct: confidence,
      mat_cost_copper: mat_cost,
      net_profit_per_unit_copper: net_profit_per_unit,
      net_profit_per_day_copper: net_profit_per_day,
      missing_data_reasons: Enum.reverse(reasons)
    }
  end

  defp sum_reagent_cost(reagents, snapshot, reasons) do
    reagent_costs =
      Enum.map(reagents, fn reagent ->
        case PriceSnapshot.fetch_price(snapshot, reagent.item.wowhead_id) do
          {:ok, item_price} -> {:ok, item_price.price_copper * reagent.quantity}
          :error -> :error
        end
      end)

    if Enum.any?(reagent_costs, &(&1 == :error)) do
      {nil, [:missing_reagent_price | reasons]}
    else
      total = reagent_costs |> Enum.map(fn {:ok, cost} -> cost end) |> Enum.sum()
      {total, reasons}
    end
  end

  defp sort_key(%ProfitResult{net_profit_per_day_copper: nil}), do: {1, 0.0}
  defp sort_key(%ProfitResult{net_profit_per_day_copper: profit}), do: {0, -profit}

  defp catalog_gateway do
    Application.get_env(
      :recipe_finder,
      :catalog_repository_gateway,
      WowForeverRecipeFinder.Gateways.EctoCatalogRepositoryGateway
    )
  end
end
