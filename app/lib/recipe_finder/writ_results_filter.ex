defmodule WowForeverRecipeFinder.WritResultsFilter do
  @moduledoc """
  Pure filtering/sorting for a `WritEfficiencyResult` list — same
  pattern as `ResultsFilter` (per docs/CODE_STYLE.md § Clean
  Architecture's Humble Object rule), kept as its own module rather
  than extending `ResultsFilter` since the underlying fields genuinely
  differ (multi-profession, free-text zone, a pending-data state).
  See docs/PRD.md § 7.8.
  """

  alias WowForeverRecipeFinder.WritEfficiencyResult

  @type criteria :: %{
          optional(:search) => String.t(),
          optional(:min_reputation) => non_neg_integer() | nil,
          optional(:max_cost_copper) => non_neg_integer() | nil,
          optional(:sort_by) => :cost | :reputation | :rep_per_gold,
          optional(:sort_dir) => :asc | :desc
        }

  @default_criteria %{
    search: "",
    min_reputation: nil,
    max_cost_copper: nil,
    sort_by: :rep_per_gold,
    sort_dir: :desc
  }

  @spec default_criteria() :: criteria()
  def default_criteria, do: @default_criteria

  @spec apply([WritEfficiencyResult.t()], criteria()) :: [WritEfficiencyResult.t()]
  def apply(results, criteria) do
    criteria = Map.merge(@default_criteria, criteria)

    results
    |> Enum.filter(&matches?(&1, criteria))
    |> sort(criteria.sort_by, criteria.sort_dir)
  end

  defp matches?(%WritEfficiencyResult{} = result, criteria) do
    search_match?(result, criteria.search) and
      threshold_match?(result.total_reputation, criteria.min_reputation, :min) and
      threshold_match?(result.total_cost_copper, criteria.max_cost_copper, :max)
  end

  defp search_match?(_result, ""), do: true

  defp search_match?(%WritEfficiencyResult{writ: writ}, search) do
    String.contains?(String.downcase(writ.name), String.downcase(search))
  end

  # A threshold that isn't set never excludes a row. A row missing the
  # underlying value (nil) is excluded once a threshold IS set, per
  # docs/ARCHITECTURE.md § Validate at the Boundary — same rule as
  # ResultsFilter.
  defp threshold_match?(_value, nil, _kind), do: true
  defp threshold_match?(nil, _threshold, _kind), do: false
  defp threshold_match?(value, threshold, :min), do: value >= threshold
  defp threshold_match?(value, threshold, :max), do: value <= threshold

  defp sort(results, field, dir) do
    Enum.sort_by(results, &sort_key(&1, field, dir), :asc)
  end

  defp sort_key(result, field, dir) do
    case field_value(result, field) do
      nil -> {1, 0.0}
      value -> {0, signed(value, dir)}
    end
  end

  defp signed(value, :asc), do: value * 1.0
  defp signed(value, :desc), do: value * -1.0

  defp field_value(%WritEfficiencyResult{total_cost_copper: v}, :cost), do: v
  defp field_value(%WritEfficiencyResult{total_reputation: v}, :reputation), do: v
  defp field_value(%WritEfficiencyResult{rep_per_gold: v}, :rep_per_gold), do: v
end
