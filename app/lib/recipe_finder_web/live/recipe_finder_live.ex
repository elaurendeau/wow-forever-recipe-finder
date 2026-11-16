defmodule WowForeverRecipeFinderWeb.RecipeFinderLive do
  @moduledoc """
  The whole product, per docs/PRD.md: upload a TSM export, pick a
  profession tab, see computed profit results. Per docs/CODE_STYLE.md's
  Humble Object rule, this module only calls context functions
  (`ProfitComputation`, `ResultsFilter`) and assigns their results —
  the actual parsing/joining/filtering logic all lives there, not here.
  """

  use WowForeverRecipeFinderWeb, :live_view

  alias WowForeverRecipeFinder.{ProfitComputation, ResultsFilter}

  @professions [
    {"tailoring", "Tailoring"},
    {"enchanting", "Enchanting"},
    {"blacksmithing", "Blacksmithing"},
    {"leatherworking", "Leatherworking"},
    {"alchemy", "Alchemy"},
    {"engineering", "Engineering"},
    {"jewelcrafting", "Jewelcrafting"},
    {"inscription", "Inscription"},
    {"cooking", "Cooking"},
    {"firstaid", "First Aid"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    known_slugs = MapSet.new(ProfitComputation.known_profession_slugs())

    socket =
      socket
      |> assign(
        active_profession: "tailoring",
        known_slugs: known_slugs,
        price_snapshot: nil,
        captured_at: nil,
        results: [],
        upload_error: nil,
        filter: ResultsFilter.default_criteria()
      )
      |> allow_upload(:tsm_export, accept: ~w(.lua), max_entries: 1, max_file_size: 20_000_000)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_tab", %{"slug" => slug}, socket) do
    {:noreply, socket |> assign(active_profession: slug) |> recompute_results()}
  end

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

  # Fired by the TsmSnapshot JS hook on mount when the browser has a
  # previously-uploaded export cached in localStorage — lets a revisit
  # skip re-uploading entirely, since no browser lets a script prefill
  # an <input type="file">'s path for a user. See assets/js/app.js.
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
      |> assign(price_snapshot: nil, captured_at: nil, results: [], upload_error: nil)
      |> push_event("clear_snapshot", %{})

    {:noreply, socket}
  end

  def handle_event("filter_changed", %{"filter" => params}, socket) do
    filter =
      socket.assigns.filter
      |> Map.merge(%{
        search: Map.get(params, "search", socket.assigns.filter.search),
        sources: MapSet.new(Map.get(params, "sources", [])),
        profitable_only?: Map.has_key?(params, "profitable_only"),
        min_sold_per_day: parse_float(Map.get(params, "min_sold_per_day")),
        min_confidence_pct: parse_float(Map.get(params, "min_confidence_pct")),
        max_price_copper: parse_int(Map.get(params, "max_price_copper")),
        min_profit_per_day_copper: parse_float(Map.get(params, "min_profit_per_day_copper"))
      })

    {:noreply, assign(socket, filter: filter)}
  end

  def handle_event("sort_by", %{"field" => field}, socket) do
    field = String.to_existing_atom(field)
    current = socket.assigns.filter

    new_dir =
      if current.sort_by == field and current.sort_dir == :desc, do: :asc, else: :desc

    {:noreply, assign(socket, filter: %{current | sort_by: field, sort_dir: new_dir})}
  end

  defp load_export(socket, export_text, captured_at) do
    case ProfitComputation.parse_export(export_text) do
      {:ok, snapshot} ->
        socket =
          socket
          |> assign(price_snapshot: snapshot, captured_at: captured_at, upload_error: nil)
          |> recompute_results()

        {:ok, socket}

      {:error, reason} ->
        {:error, assign(socket, upload_error: format_parse_error(reason))}
    end
  end

  defp recompute_results(socket) do
    case socket.assigns.price_snapshot do
      nil ->
        assign(socket, results: [])

      snapshot ->
        assign(socket, results: ProfitComputation.compute_results(socket.assigns.active_profession, snapshot))
    end
  end

  defp parse_float(nil), do: nil
  defp parse_float(""), do: nil

  defp parse_float(str) do
    case Float.parse(str) do
      {value, _} -> value
      :error -> nil
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

  defp format_parse_error({:no_load_data_lines_found}),
    do: "That doesn't look like a TSM AppData.lua export — no price tables were found in it."

  defp format_parse_error({:table_not_found, table}),
    do: "This export has no #{table} table — it may be from an unsupported TSM version."

  defp format_parse_error({:no_usable_rows, table}),
    do: "This export's #{table} table has no price data yet — try running a fresh AH scan in TSM first."

  defp format_parse_error(_other), do: "Couldn't read this file as a TSM export."

  defp professions, do: @professions

  defp source_label(source), do: String.capitalize(source)

  defp profession_label(slug) do
    Enum.find_value(@professions, slug, fn {s, label} -> s == slug && label end)
  end

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

  defp format_number(nil), do: "—"
  defp format_number(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp format_number(n), do: Integer.to_string(n)

  defp format_pct(nil), do: "—"
  defp format_pct(n), do: "#{:erlang.float_to_binary(n * 1.0, decimals: 0)}%"

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
