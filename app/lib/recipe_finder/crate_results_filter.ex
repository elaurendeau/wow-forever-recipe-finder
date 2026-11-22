defmodule WowForeverRecipeFinder.CrateResultsFilter do
  @moduledoc """
  Pure filtering/sorting for a `CrateEfficiencyResult` list — same
  pattern as `WritResultsFilter` (per docs/CODE_STYLE.md § Clean
  Architecture's Humble Object rule), kept as its own module since the
  underlying fields genuinely differ (tier/category/quality instead
  of profession/zone). See docs/PRD.md § 7.11.
  """

  alias WowForeverRecipeFinder.CrateEfficiencyResult

  @type sort_field :: :total_cost | :price_per_favor

  @type criteria :: %{
          optional(:search) => String.t(),
          optional(:tier) => WowForeverRecipeFinder.WaylaidCrate.tier() | :any,
          optional(:max_cost_copper) => non_neg_integer() | nil,
          optional(:sort_by) => sort_field(),
          optional(:sort_dir) => :asc | :desc
        }

  # Cheapest cost-per-Favor first by default — per docs/PRD.md § 7.11,
  # "most cost-effective" means the lowest price per Merchant's Favor
  # earned, not raw total cost: two crates can cost the same but pay
  # different amounts of Favor (see MerchantFavorFormula), so cost
  # alone doesn't actually answer "which is most cost-effective" on
  # its own. Total cost is still shown and still sortable.
  @default_criteria %{
    search: "",
    tier: :any,
    max_cost_copper: nil,
    sort_by: :price_per_favor,
    sort_dir: :asc
  }

  @spec default_criteria() :: criteria()
  def default_criteria, do: @default_criteria

  @spec apply([CrateEfficiencyResult.t()], criteria()) :: [CrateEfficiencyResult.t()]
  def apply(results, criteria) do
    criteria = Map.merge(@default_criteria, criteria)

    results
    |> Enum.filter(&matches?(&1, criteria))
    |> sort(criteria.sort_by, criteria.sort_dir)
  end

  defp matches?(%CrateEfficiencyResult{} = result, criteria) do
    search_match?(result, criteria.search) and
      tier_match?(result, criteria.tier) and
      threshold_match?(result.total_cost_copper, criteria.max_cost_copper)
  end

  defp search_match?(_result, ""), do: true

  defp search_match?(%CrateEfficiencyResult{crate: crate}, search) do
    needle = String.downcase(search)

    String.contains?(String.downcase(crate.name), needle) or
      String.contains?(crate.category, needle)
  end

  defp tier_match?(_result, :any), do: true
  defp tier_match?(%CrateEfficiencyResult{crate: %{tier: tier}}, tier), do: true
  defp tier_match?(_result, _tier), do: false

  # A threshold that isn't set never excludes a row. A row missing the
  # underlying value (nil) is excluded once a threshold IS set, per
  # docs/ARCHITECTURE.md § Validate at the Boundary — same rule as
  # ResultsFilter/WritResultsFilter.
  defp threshold_match?(_value, nil), do: true
  defp threshold_match?(nil, _threshold), do: false
  defp threshold_match?(value, threshold), do: value <= threshold

  defp sort(results, sort_by, dir) do
    Enum.sort_by(results, &sort_key(&1, sort_by, dir), :asc)
  end

  defp sort_value(%CrateEfficiencyResult{total_cost_copper: v}, :total_cost), do: v
  defp sort_value(%CrateEfficiencyResult{price_per_favor_copper: v}, :price_per_favor), do: v

  defp sort_key(result, sort_by, dir) do
    case sort_value(result, sort_by) do
      nil -> {1, 0.0}
      v when dir == :asc -> {0, v * 1.0}
      v when dir == :desc -> {0, v * -1.0}
    end
  end
end
