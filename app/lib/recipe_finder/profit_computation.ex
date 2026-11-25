defmodule WowForeverRecipeFinder.ProfitComputation do
  @moduledoc """
  The use case behind docs/PRD.md § 7.3: join a profession's catalog
  against an uploaded `PriceSnapshot` to produce one `ProfitResult` per
  pattern. Fetching the catalog goes through the configured
  `CatalogRepositoryGateway` (Dependency Inversion, per
  docs/CODE_STYLE.md § SOLID); the join/compute itself is a pure
  function with no I/O, independently unit-testable — see
  `compute_result/3` and docs/ELIXIR_TEST_MANIFESTO.md § What Still
  Gets a Plain Unit Test.

  **The pricing basis is a single visitor-chosen toggle, applied
  consistently to both sides of the profit calculation.** Earlier
  revisions used Region Sale Avg (`price_copper`) for crafted-item sale
  price and reagent cost alike, with a second always-on "Recent"/"Recent
  Profit" pair computed from Recent Value on the side — an inconsistency
  against the Writs and Merchant's Favor pages, which settled on Recent
  Value as the one cost basis everywhere. Revised 2026-11-25: a single
  `price_basis/0` (`:recent` or `:region_avg`, **`:recent` is the
  default**) now decides which TSM figure both the crafted item's sale
  price AND every reagent's unit cost read — never a mix of the two
  within one result. There is exactly one Price, one Cost, and one
  Profit/% pair; the old separate Recent/Recent Profit columns are gone,
  replaced by switching the toggle.

  **A real consequence of defaulting to `:recent`, not a bug:** TSM's
  `AUCTIONDB_NON_COMMODITY_DATA` table (Recent Value's source) only
  covers non-commodity items — most raw-material reagents (ore, cloth,
  herbs, …) are commodities and simply have no Recent Value at all. A
  visitor will see far more "no sale data" rows by default than under
  Region Sale Avg, which is tracked region-wide for every item. This is
  the real shape of TSM's own data, not something to paper over by
  quietly falling back to the other basis.
  """

  alias WowForeverRecipeFinder.{Pattern, PriceSnapshot, ProfitResult, TsmExportParser}

  @type price_basis :: :recent | :region_avg

  # The standard WoW/Classic cut taken on a successful auction sale.
  @ah_cut_pct 0.05

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

  @doc "DB Recent Value is the default — see this module's own doc for why."
  @spec default_price_basis() :: price_basis()
  def default_price_basis, do: :recent

  @doc """
  Every `ProfitResult` for a profession, given an already-parsed
  `PriceSnapshot` and the visitor's chosen `price_basis`. Results are
  sorted by per-unit profit descending, with patterns missing a
  computable profit sorted last.
  """
  @spec compute_results(String.t(), PriceSnapshot.t(), price_basis()) :: [ProfitResult.t()]
  def compute_results(profession_slug, %PriceSnapshot{} = snapshot, price_basis) do
    profession_slug
    |> catalog_gateway().list_patterns()
    |> Enum.map(&compute_result(&1, snapshot, price_basis))
    |> Enum.sort_by(&sort_key/1)
  end

  @doc """
  The pure join/compute for one pattern against one snapshot and price
  basis — no gateway call, no I/O. A field is `nil`, with its reason
  recorded in `missing_data_reasons`, whenever the data to compute it
  isn't there; never a fabricated zero. See docs/ARCHITECTURE.md §
  Validate at the Boundary, Fail Loudly.
  """
  @spec compute_result(Pattern.t(), PriceSnapshot.t(), price_basis()) :: ProfitResult.t()
  def compute_result(%Pattern{} = pattern, %PriceSnapshot{} = snapshot, price_basis) do
    reasons = []

    {price, sold_per_day, confidence, reasons} =
      case PriceSnapshot.fetch_price(snapshot, pattern.crafted_item.wowhead_id) do
        {:ok, item_price} ->
          case price_for_basis(item_price, price_basis) do
            # Known item, but the chosen basis has no figure for it —
            # same "no sale data" reason as not finding the item at
            # all, never a fabricated zero (e.g. :recent on a
            # commodity item TSM's AUCTIONDB_NON_COMMODITY_DATA
            # simply doesn't cover — see this module's own doc).
            nil ->
              {nil, item_price.sold_per_day, item_price.sale_confidence_pct,
               [:no_sale_data | reasons]}

            price ->
              {price, item_price.sold_per_day, item_price.sale_confidence_pct, reasons}
          end

        :error ->
          {nil, nil, nil, [:no_sale_data | reasons]}
      end

    {mat_cost, reasons} =
      case pattern.reagents do
        [] ->
          {nil, [:no_reagents_found | reasons]}

        reagents ->
          sum_reagent_cost(reagents, snapshot, price_basis, reasons)
      end

    reagent_breakdown = build_reagent_breakdown(pattern.reagents, snapshot, price_basis)

    {net_profit_per_unit, profit_pct} = compute_profit(price, mat_cost)

    %ProfitResult{
      pattern: pattern,
      price_copper: price,
      sold_per_day: sold_per_day,
      sale_confidence_pct: confidence,
      mat_cost_copper: mat_cost,
      net_profit_per_unit_copper: net_profit_per_unit,
      profit_pct: profit_pct,
      missing_data_reasons: Enum.reverse(reasons),
      reagent_breakdown: reagent_breakdown
    }
  end

  defp price_for_basis(%{price_copper: v}, :region_avg), do: v
  defp price_for_basis(%{recent_value_copper: v}, :recent), do: v

  defp compute_profit(sale_price, mat_cost) do
    case {sale_price, mat_cost} do
      {p, m} when is_integer(p) and is_integer(m) ->
        price_after_cut = round(p * (1 - @ah_cut_pct))
        profit = price_after_cut - m
        pct = if m > 0, do: profit / m * 100, else: nil
        {profit, pct}

      _incomplete ->
        {nil, nil}
    end
  end

  # For the Cost column's hover tooltip — per-reagent lines, independent
  # of whether the aggregate mat_cost_copper above could be computed (a
  # single missing reagent price shouldn't hide the ones that did
  # resolve; the tooltip shows exactly which reagent is missing instead).
  defp build_reagent_breakdown(reagents, snapshot, price_basis) do
    Enum.map(reagents, fn reagent ->
      unit_price =
        case PriceSnapshot.fetch_price(snapshot, reagent.item.wowhead_id) do
          {:ok, item_price} -> price_for_basis(item_price, price_basis)
          :error -> nil
        end

      %{
        display_name: reagent.item.display_name,
        quantity: reagent.quantity,
        unit_price_copper: unit_price,
        line_total_copper: unit_price && unit_price * reagent.quantity
      }
    end)
  end

  defp sum_reagent_cost(reagents, snapshot, price_basis, reasons) do
    reagent_costs =
      Enum.map(reagents, fn reagent ->
        case PriceSnapshot.fetch_price(snapshot, reagent.item.wowhead_id) do
          {:ok, item_price} ->
            case price_for_basis(item_price, price_basis) do
              nil -> :error
              unit_price -> {:ok, unit_price * reagent.quantity}
            end

          :error ->
            :error
        end
      end)

    if Enum.any?(reagent_costs, &(&1 == :error)) do
      {nil, [:missing_reagent_price | reasons]}
    else
      total = reagent_costs |> Enum.map(fn {:ok, cost} -> cost end) |> Enum.sum()
      {total, reasons}
    end
  end

  defp sort_key(%ProfitResult{net_profit_per_unit_copper: nil}), do: {1, 0}
  defp sort_key(%ProfitResult{net_profit_per_unit_copper: profit}), do: {0, -profit}

  defp catalog_gateway do
    Application.get_env(
      :recipe_finder,
      :catalog_repository_gateway,
      WowForeverRecipeFinder.Gateways.EctoCatalogRepositoryGateway
    )
  end
end
