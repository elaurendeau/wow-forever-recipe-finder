defmodule WowForeverRecipeFinderWeb.WritsLive do
  @moduledoc """
  Per docs/PRD.md § 7.8: a separate page ranking Craftsman's Writs by
  reputation gained per gold spent. Shares its uploaded TSM snapshot
  with `RecipeFinderLive` via the same client-held `localStorage` keys
  (see assets/js/app.js's `TsmSnapshot` hook) — a visitor who already
  uploaded on the main page never re-uploads here.

  Per docs/CODE_STYLE.md's Humble Object rule, this module only calls
  context functions (`WritEfficiency`, `WritResultsFilter`,
  `ProfitComputation.parse_export/1`) and assigns their results — the
  actual parsing/joining/filtering logic all lives there, not here.
  The upload/snapshot event handling below deliberately mirrors
  `RecipeFinderLive`'s own (same localStorage contract, same parse
  path) rather than sharing a Web-layer helper — only two consumers
  exist so far and both are small; worth extracting if a third shows up.
  """

  use WowForeverRecipeFinderWeb, :live_view

  alias WowForeverRecipeFinder.{
    ProfitComputation,
    WritEfficiency,
    WritResultsFilter,
    WritShoppingList
  }

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        price_snapshot: nil,
        captured_at: nil,
        results: [],
        upload_error: nil,
        filter: WritResultsFilter.default_criteria(),
        # Per docs/PRD.md § 7.9: selection is session-only for this
        # round, deliberately not persisted to localStorage like the
        # uploaded snapshot is.
        selected_writ_ids: MapSet.new()
      )
      |> allow_upload(:tsm_export, accept: ~w(.lua), max_entries: 1, max_file_size: 20_000_000)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("process_upload", _params, socket) do
    case consume_uploaded_entries(socket, :tsm_export, fn %{path: path}, _entry ->
           {:ok, File.read!(path)}
         end) do
      [export_text] ->
        captured_at = DateTime.utc_now()

        case load_export(socket, export_text, captured_at) do
          {:ok, socket} ->
            {:noreply,
             push_event(socket, "store_snapshot", %{
               data: export_text,
               captured_at: DateTime.to_iso8601(captured_at)
             })}

          {:error, socket} ->
            {:noreply, socket}
        end

      [] ->
        {:noreply, assign(socket, upload_error: "No file was uploaded.")}
    end
  end

  # Same cross-page restore contract as RecipeFinderLive — see
  # assets/js/app.js's TsmSnapshot hook.
  def handle_event("restore_snapshot", %{"data" => export_text} = params, socket) do
    captured_at =
      case DateTime.from_iso8601(params["captured_at"] || "") do
        {:ok, dt, _offset} -> dt
        {:error, _reason} -> DateTime.utc_now()
      end

    case load_export(socket, export_text, captured_at) do
      {:ok, socket} -> {:noreply, socket}
      {:error, socket} -> {:noreply, push_event(socket, "clear_snapshot", %{})}
    end
  end

  def handle_event("clear_snapshot", _params, socket) do
    socket =
      socket
      |> assign(
        price_snapshot: nil,
        captured_at: nil,
        results: [],
        upload_error: nil,
        selected_writ_ids: MapSet.new()
      )
      |> push_event("clear_snapshot", %{})

    {:noreply, socket}
  end

  def handle_event("toggle_writ_selection", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    selected = socket.assigns.selected_writ_ids

    selected =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, assign(socket, selected_writ_ids: selected)}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, selected_writ_ids: MapSet.new())}
  end

  def handle_event("filter_changed", %{"filter" => params}, socket) do
    filter =
      socket.assigns.filter
      |> Map.merge(%{
        search: Map.get(params, "search", socket.assigns.filter.search),
        min_reputation: parse_int(Map.get(params, "min_reputation")),
        max_cost_copper: parse_int(Map.get(params, "max_cost_copper"))
      })

    {:noreply, assign(socket, filter: filter)}
  end

  def handle_event("sort_by", %{"field" => field}, socket) do
    field = String.to_existing_atom(field)
    current = socket.assigns.filter

    new_dir = if current.sort_by == field and current.sort_dir == :desc, do: :asc, else: :desc

    {:noreply, assign(socket, filter: %{current | sort_by: field, sort_dir: new_dir})}
  end

  defp load_export(socket, export_text, captured_at) do
    case ProfitComputation.parse_export(export_text) do
      {:ok, snapshot} ->
        socket =
          socket
          |> assign(price_snapshot: snapshot, captured_at: captured_at, upload_error: nil)
          |> assign(results: WritEfficiency.compute_results(snapshot))

        {:ok, socket}

      {:error, reason} ->
        {:error, assign(socket, upload_error: format_parse_error(reason))}
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(str) do
    case Integer.parse(str) do
      {value, _} -> value
      :error -> nil
    end
  end

  # Same messages as RecipeFinderLive's — both pages parse the exact
  # same upload shape via the same context function.
  defp format_parse_error({:no_load_data_lines_found}),
    do: "That doesn't look like a TSM AppData.lua export — no price tables were found in it."

  defp format_parse_error({:table_not_found, table}),
    do: "This export has no #{table} table — it may be from an unsupported TSM version."

  defp format_parse_error({:no_usable_rows, table}),
    do:
      "This export's #{table} table has no price data yet — try running a fresh AH scan in TSM first."

  defp format_parse_error(_other), do: "Couldn't read this file as a TSM export."

  defp profession_label("firstaid"), do: "First Aid"
  defp profession_label(slug), do: String.capitalize(slug)

  defp tier_label(tier), do: tier |> to_string() |> String.capitalize()

  # The "/forever" shape is this project's own server — see
  # docs/DATA_SOURCES.md § Warcraft Wiki for the three observed item
  # URL shapes; quests use their own numeric-ID shape.
  defp wowhead_quest_url(quest_id), do: "https://www.wowhead.com/forever/quest=#{quest_id}"

  defp format_copper(nil), do: "—"

  defp format_copper(copper) do
    copper = round(copper)
    neg = copper < 0
    copper = abs(copper)
    gold = div(copper, 10_000)
    silver = div(rem(copper, 10_000), 100)
    cop = rem(copper, 100)

    parts =
      [{gold, "g"}, {silver, "s"}, {cop, "c"}]
      |> Enum.drop_while(fn {v, unit} -> v == 0 and unit != "c" end)
      |> Enum.map(fn {v, unit} -> "#{v}#{unit}" end)
      |> Enum.join(" ")

    if neg, do: "-" <> parts, else: parts
  end

  defp format_rep_per_gold(nil), do: "—"
  defp format_rep_per_gold(v), do: "#{:erlang.float_to_binary(v * 1.0, decimals: 1)} rep/g"

  defp pending_data?(result), do: :no_required_items_data in result.missing_data_reasons

  defp sort_indicator(filter, field) do
    cond do
      filter.sort_by != field -> ""
      filter.sort_dir == :desc -> " ▼"
      true -> " ▲"
    end
  end

  defp th_class(filter, field) do
    if filter.sort_by == field, do: "num sorted", else: "num"
  end
end
