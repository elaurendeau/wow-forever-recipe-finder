defmodule WowForeverRecipeFinder.CrateResultsFilter do
  @moduledoc """
  Pure filtering/sorting for a `CrateEfficiencyResult` list — same
  pattern as `WritResultsFilter` (per docs/CODE_STYLE.md § Clean
  Architecture's Humble Object rule), kept as its own module since the
  underlying fields genuinely differ (tier/category/quality instead
  of profession/zone). See docs/PRD.md § 7.11.
  """

  alias WowForeverRecipeFinder.CrateEfficiencyResult

  @type criteria :: %{
          optional(:search) => String.t(),
          optional(:tier) => WowForeverRecipeFinder.WaylaidCrate.tier() | :any,
          optional(:max_cost_copper) => non_neg_integer() | nil,
          optional(:sort_by) => :cost,
          optional(:sort_dir) => :asc | :desc
        }

  # Cheapest first by default — "most cost-effective" means lowest
  # total AH cost, per docs/PRD.md § 7.11 (every crate becomes exactly
  # one Sealed Crate of its own tier regardless of fill option, so
  # cost alone ranks them, no ratio needed).
  @default_criteria %{
    search: "",
    tier: :any,
    max_cost_copper: nil,
    sort_by: :cost,
    sort_dir: :asc
  }

  @spec default_criteria() :: criteria()
  def default_criteria, do: @default_criteria

  @spec apply([CrateEfficiencyResult.t()], criteria()) :: [CrateEfficiencyResult.t()]
  def apply(results, criteria) do
    criteria = Map.merge(@default_criteria, criteria)

    results
    |> Enum.filter(&matches?(&1, criteria))
    |> sort(criteria.sort_dir)
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

  defp sort(results, dir) do
    Enum.sort_by(results, &sort_key(&1, dir), :asc)
  end

  defp sort_key(%CrateEfficiencyResult{total_cost_copper: nil}, _dir), do: {1, 0.0}
  defp sort_key(%CrateEfficiencyResult{total_cost_copper: v}, :asc), do: {0, v * 1.0}
  defp sort_key(%CrateEfficiencyResult{total_cost_copper: v}, :desc), do: {0, v * -1.0}
end
