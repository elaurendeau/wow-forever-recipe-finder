defmodule WowForeverRecipeFinder.WritEfficiency do
  @moduledoc """
  The use case behind docs/PRD.md § 7.8: join the Craftsman's Writ
  catalog against an uploaded `PriceSnapshot` to produce one
  `WritEfficiencyResult` per writ. Fetching the catalog goes through
  the configured `WritRepositoryGateway` (Dependency Inversion, per
  docs/CODE_STYLE.md § SOLID); the join/compute itself is a pure
  function with no I/O, independently unit-testable — see
  `compute_result/2`.

  **Cost is always the AH "Recent Value"** (`recent_value_copper`,
  TSM's realm-level figure) for both the writ item and every required
  item — never this app's crafting-reagent-cost engine, even for a
  required item already tracked as a pattern elsewhere. This is a
  deliberate decision locked in for this feature (see docs/PRD.md §
  7.8), not an oversight: `price_copper` (region Sale Avg) is never
  read here at all.
  """

  alias WowForeverRecipeFinder.{PriceSnapshot, Writ, WritEfficiencyResult}

  @doc "Every writ in the catalog, joined against an already-parsed `PriceSnapshot`, sorted by rep-per-gold descending."
  @spec compute_results(PriceSnapshot.t()) :: [WritEfficiencyResult.t()]
  def compute_results(%PriceSnapshot{} = snapshot) do
    writ_gateway().list_writs()
    |> Enum.map(&compute_result(&1, snapshot))
    |> Enum.sort_by(&sort_key/1)
  end

  @doc """
  The pure join/compute for one writ against one snapshot — no
  gateway call, no I/O. A field is `nil`, with its reason recorded in
  `missing_data_reasons`, whenever the data to compute it isn't
  there; never a fabricated zero.
  """
  @spec compute_result(Writ.t(), PriceSnapshot.t()) :: WritEfficiencyResult.t()
  def compute_result(%Writ{} = writ, %PriceSnapshot{} = snapshot) do
    reasons = []

    {writ_item_cost, reasons} =
      case fetch_recent_value(writ.writ_item_wowhead_id, snapshot) do
        {:ok, copper} -> {copper, reasons}
        :error -> {nil, [:missing_writ_item_recent_value | reasons]}
      end

    {required_items_cost, reasons} = compute_required_items_cost(writ, snapshot, reasons)

    total_cost = sum_if_both_present(writ_item_cost, required_items_cost)
    total_reputation = Enum.sum(Enum.map(writ.reputation_rewards, & &1.amount))
    rep_per_gold = compute_rep_per_gold(total_reputation, total_cost)

    %WritEfficiencyResult{
      writ: writ,
      writ_item_cost_copper: writ_item_cost,
      required_items_cost_copper: required_items_cost,
      total_cost_copper: total_cost,
      total_reputation: total_reputation,
      rep_per_gold: rep_per_gold,
      missing_data_reasons: Enum.reverse(reasons),
      required_item_breakdown: build_required_item_breakdown(writ.required_items, snapshot)
    }
  end

  # For the Cost column's hover tooltip — per-item lines, independent
  # of whether the aggregate required_items_cost_copper above could be
  # computed (one missing price shouldn't hide the ones that did
  # resolve). Same discipline as ProfitComputation's reagent breakdown.
  defp build_required_item_breakdown(required_items, snapshot) do
    Enum.map(required_items, fn item ->
      unit_price =
        case fetch_recent_value(item.wowhead_id, snapshot) do
          {:ok, copper} -> copper
          :error -> nil
        end

      %{
        display_name: item.display_name,
        quantity: item.quantity,
        unit_price_copper: unit_price,
        line_total_copper: unit_price && unit_price * item.quantity
      }
    end)
  end

  # `resolution_status: :pending_quest_page` means the extraction
  # hasn't fetched the required items yet — `required_items` is `[]`
  # in that state, which must never be read as "costs nothing." An
  # empty list under `:complete` is equally untrustworthy (it would
  # mean a writ with a real turn-in requirement that somehow needs
  # nothing), so both get the same "data's not really there" reason
  # rather than silently pricing the writ as free.
  defp compute_required_items_cost(
         %Writ{resolution_status: :pending_quest_page},
         _snapshot,
         reasons
       ) do
    {nil, [:no_required_items_data | reasons]}
  end

  defp compute_required_items_cost(
         %Writ{resolution_status: :complete, required_items: []},
         _snapshot,
         reasons
       ) do
    {nil, [:no_required_items_data | reasons]}
  end

  defp compute_required_items_cost(
         %Writ{resolution_status: :complete, required_items: items},
         snapshot,
         reasons
       ) do
    line_costs =
      Enum.map(items, fn item ->
        case fetch_recent_value(item.wowhead_id, snapshot) do
          {:ok, copper} -> {:ok, copper * item.quantity}
          :error -> :error
        end
      end)

    if Enum.any?(line_costs, &(&1 == :error)) do
      {nil, [:missing_required_item_recent_value | reasons]}
    else
      total = line_costs |> Enum.map(fn {:ok, cost} -> cost end) |> Enum.sum()
      {total, reasons}
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

  # Undefined (not zero or infinite) when cost can't be computed at
  # all — same "undefined ROI" discipline as ProfitComputation's
  # profit_pct for a free craft.
  defp compute_rep_per_gold(_total_reputation, nil), do: nil
  defp compute_rep_per_gold(_total_reputation, 0), do: nil

  defp compute_rep_per_gold(total_reputation, total_cost_copper),
    do: total_reputation / (total_cost_copper / 10_000)

  defp sort_key(%WritEfficiencyResult{rep_per_gold: nil}), do: {1, 0.0}
  defp sort_key(%WritEfficiencyResult{rep_per_gold: v}), do: {0, -v}

  defp writ_gateway do
    Application.get_env(
      :recipe_finder,
      :writ_repository_gateway,
      WowForeverRecipeFinder.Gateways.EctoWritRepositoryGateway
    )
  end
end
