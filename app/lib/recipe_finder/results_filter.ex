defmodule WowForeverRecipeFinder.ResultsFilter do
  @moduledoc """
  Pure filtering/sorting for a `ProfitResult` list — per docs/CODE_STYLE.md
  § Clean Architecture's Humble Object rule, this logic lives here, not
  inlined in a LiveView `handle_event/3`. See docs/PRD.md § 7.5.
  """

  alias WowForeverRecipeFinder.ProfitResult

  @known_sources ~w(trainer vendor drop quest)

  @type criteria :: %{
          optional(:search) => String.t(),
          optional(:sources) => MapSet.t(String.t()),
          optional(:profitable_only?) => boolean(),
          optional(:min_skill) => non_neg_integer() | nil,
          optional(:max_skill) => non_neg_integer() | nil,
          optional(:min_sold_per_day) => float() | nil,
          optional(:min_confidence_pct) => float() | nil,
          optional(:max_price_copper) => non_neg_integer() | nil,
          optional(:min_profit_copper) => integer() | nil,
          optional(:min_profit_pct) => float() | nil,
          optional(:sort_by) => :sold_per_day | :confidence | :price | :profit | :profit_pct,
          optional(:sort_dir) => :asc | :desc
        }

  @default_criteria %{
    search: "",
    sources: MapSet.new(@known_sources),
    profitable_only?: true,
    min_skill: nil,
    max_skill: nil,
    min_sold_per_day: nil,
    min_confidence_pct: nil,
    max_price_copper: nil,
    min_profit_copper: nil,
    min_profit_pct: nil,
    sort_by: :sold_per_day,
    sort_dir: :desc
  }

  @spec default_criteria() :: criteria()
  def default_criteria, do: @default_criteria

  @doc "Every source category a pattern can have, for rendering the filter checkboxes."
  @spec known_sources() :: [String.t()]
  def known_sources, do: @known_sources

  @spec apply(list(ProfitResult.t()), criteria()) :: list(ProfitResult.t())
  def apply(results, criteria) do
    criteria = Map.merge(@default_criteria, criteria)

    results
    |> Enum.filter(&matches?(&1, criteria))
    |> sort(criteria.sort_by, criteria.sort_dir)
  end

  defp matches?(%ProfitResult{} = result, criteria) do
    search_match?(result, criteria.search) and
      source_match?(result, criteria.sources) and
      profitable_match?(result, criteria.profitable_only?) and
      skill_match?(result, criteria) and
      threshold_match?(result.sold_per_day, criteria.min_sold_per_day, :min) and
      threshold_match?(result.sale_confidence_pct, criteria.min_confidence_pct, :min) and
      threshold_match?(result.price_copper, criteria.max_price_copper, :max) and
      threshold_match?(result.net_profit_per_unit_copper, criteria.min_profit_copper, :min) and
      threshold_match?(result.profit_pct, criteria.min_profit_pct, :min)
  end

  defp skill_match?(%ProfitResult{pattern: %{skill: skill}}, criteria) do
    threshold_match?(skill, criteria.min_skill, :min) and
      threshold_match?(skill, criteria.max_skill, :max)
  end

  defp search_match?(_result, ""), do: true

  defp search_match?(%ProfitResult{pattern: pattern}, search) do
    String.contains?(String.downcase(pattern.name), String.downcase(search))
  end

  # A pattern with no source category (e.g. a starting recipe) isn't one
  # of the checkbox options at all, so it always passes — the checkboxes
  # filter among known categories, they don't hide uncategorized rows.
  defp source_match?(%ProfitResult{pattern: %{source: nil}}, _sources), do: true

  defp source_match?(%ProfitResult{pattern: %{source: source}}, sources),
    do: MapSet.member?(sources, to_string(source))

  defp profitable_match?(_result, false), do: true
  defp profitable_match?(result, true), do: ProfitResult.profitable?(result)

  # A threshold that isn't set never excludes a row. A row missing the
  # underlying value (nil) is excluded once a threshold IS set — showing
  # it would silently misrepresent an unknown value as passing the
  # filter, per docs/ARCHITECTURE.md § Validate at the Boundary.
  defp threshold_match?(_value, nil, _kind), do: true
  defp threshold_match?(nil, _threshold, _kind), do: false
  defp threshold_match?(value, threshold, :min), do: value >= threshold
  defp threshold_match?(value, threshold, :max), do: value <= threshold

  # Always sorts the composite key ascending — "descending" is achieved
  # by negating the value inside the key, not by flipping `Enum.sort_by`'s
  # own order, specifically so the missing-data flag (0 = present, 1 =
  # missing) always sorts the same way regardless of the chosen
  # direction: `nil`s sort last whether you asked for ascending or
  # descending, never silently in the middle of real numbers.
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

  defp field_value(%ProfitResult{sold_per_day: v}, :sold_per_day), do: v
  defp field_value(%ProfitResult{sale_confidence_pct: v}, :confidence), do: v
  defp field_value(%ProfitResult{price_copper: v}, :price), do: v
  defp field_value(%ProfitResult{net_profit_per_unit_copper: v}, :profit), do: v
  defp field_value(%ProfitResult{profit_pct: v}, :profit_pct), do: v
end
