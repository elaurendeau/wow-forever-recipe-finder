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
    WritMapPlacement,
    WritResultsFilter,
    WritShoppingList
  }

  # The whole populated canvas minus Wowhead's dead left margin — see
  # docs/DATA_SOURCES.md § Wowhead WoW Forever World Map. Loaded once
  # at mount since it's static reference data, same for every visitor.
  @full_view_box "8192 0 36352 37888"

  @impl true
  def mount(_params, _session, socket) do
    {world_map, map_load_error} =
      case WritMapPlacement.load_world_map() do
        {:ok, world_map} -> {world_map, nil}
        {:error, error} -> {nil, error}
      end

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
        # uploaded snapshot is. An ordered list, not a MapSet — order
        # is the source of the number shown next to each checked row
        # and each shopping-list group.
        selected_writ_ids: [],
        # The shopping list lives behind a FAB + popup (not inline in
        # the page flow, so selecting rows never shifts the table) —
        # `shopping_list_unseen?` drives the FAB's "modified since you
        # last opened it" badge.
        shopping_list_open?: false,
        shopping_list_unseen?: false,
        # The map lives behind its own FAB + popup, stacked above the
        # shopping-cart one — per docs/PRD.md § 7.10. Loaded once at
        # mount (not per-filter-change): it's the same static vector
        # data for every visitor regardless of what's checked/filtered.
        world_map: world_map,
        map_load_error: map_load_error,
        map_open?: false,
        selected_pin_id: nil
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
        selected_writ_ids: [],
        shopping_list_open?: false,
        shopping_list_unseen?: false,
        map_open?: false,
        selected_pin_id: nil
      )
      |> push_event("clear_snapshot", %{})

    {:noreply, socket}
  end

  def handle_event("toggle_writ_selection", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    selected = socket.assigns.selected_writ_ids

    # Appended, not prepended — the first writ checked is #1. A
    # writ's number is just its position in this list, recomputed on
    # every render (selection_number/2 below), so unchecking one
    # shifts everything after it down by one — same as removing a
    # line from a numbered list. Re-checking it later appends it
    # again at the end, with whatever number that position is now.
    selected = if id in selected, do: List.delete(selected, id), else: selected ++ [id]

    # Only flag "unseen" while the popup is closed — a change made
    # while it's open is already visible, no badge needed for it.
    {:noreply,
     assign(socket,
       selected_writ_ids: selected,
       shopping_list_unseen?: not socket.assigns.shopping_list_open?
     )}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply,
     assign(socket,
       selected_writ_ids: [],
       shopping_list_open?: false,
       shopping_list_unseen?: false
     )}
  end

  def handle_event("toggle_shopping_list_panel", _params, socket) do
    open? = not socket.assigns.shopping_list_open?
    # Opening it marks everything seen; closing it leaves "seen" as-is.
    unseen? = if open?, do: false, else: socket.assigns.shopping_list_unseen?

    socket =
      socket
      |> assign(shopping_list_open?: open?, shopping_list_unseen?: unseen?)
      # Only one floating panel at a time — otherwise they stack and
      # cover each other (and the FAB that would close them).
      |> then(fn s -> if open?, do: assign(s, map_open?: false), else: s end)

    {:noreply, socket}
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

  def handle_event("set_side", %{"side" => side}, socket) do
    filter = %{socket.assigns.filter | side: String.to_existing_atom(side)}
    {:noreply, assign(socket, filter: filter, selected_pin_id: nil)}
  end

  def handle_event("toggle_map_panel", _params, socket) do
    open? = not socket.assigns.map_open?
    # Same mutual-exclusion rule as the shopping list's own toggle.
    socket =
      socket
      |> assign(map_open?: open?)
      |> then(fn s -> if open?, do: assign(s, shopping_list_open?: false), else: s end)

    {:noreply, socket}
  end

  def handle_event("select_pin", %{"id" => id}, socket) do
    {:noreply, assign(socket, selected_pin_id: id)}
  end

  def handle_event("clear_pin", _params, socket) do
    {:noreply, assign(socket, selected_pin_id: nil)}
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

  # SVG path data for a WorldMap polygon list — `fill-rule="evenodd"`
  # on the element lets several rings (a landmass plus an island, a
  # zone plus a lake carved out of it) share one path and render
  # holes correctly, per docs/CODE_STYLE.md's Humble Object rule:
  # pure view-formatting, no business logic.
  defp svg_path(polygons) do
    Enum.map_join(polygons, " ", fn rings -> Enum.map_join(rings, " ", &ring_path/1) end)
  end

  defp ring_path([]), do: ""

  defp ring_path([{x0, y0} | rest]) do
    "M#{fmt_coord(x0)} #{fmt_coord(y0)}" <>
      Enum.map_join(rest, "", fn {x, y} -> " L#{fmt_coord(x)} #{fmt_coord(y)}" end) <> " Z"
  end

  defp fmt_coord(n) when is_integer(n), do: Integer.to_string(n)
  defp fmt_coord(n), do: :erlang.float_to_binary(n * 1.0, decimals: 1)

  # The little number shown next to a checked row's checkbox, and the
  # same number tagging that writ's group in the shopping-list popup —
  # nil (not rendered) for a writ that isn't selected at all.
  defp selection_number(selected_writ_ids, writ_id) do
    case Enum.find_index(selected_writ_ids, &(&1 == writ_id)) do
      nil -> nil
      index -> index + 1
    end
  end

  defp full_view_box, do: @full_view_box

  defp sides, do: [{"horde", "Horde"}, {"alliance", "Alliance"}, {"any", "Either"}]

  defp side_selected?(filter, side_param), do: Atom.to_string(filter.side) == side_param

  # The pin currently open in the side panel, or nil — looked up by id
  # each render rather than carried as a full pin in the socket so a
  # filter change that drops a pin's last writ also drops the panel.
  defp selected_pin(_pins, nil), do: nil
  defp selected_pin(pins, id), do: Enum.find(pins, &(&1.id == id))

  defp pin_title(%{npc_name: nil}), do: "Unknown NPC"
  defp pin_title(%{npc_name: name}), do: name

  defp continent_label("kalimdor"), do: "Kalimdor"
  defp continent_label("eastern-kingdoms"), do: "Eastern Kingdoms"
  defp continent_label("zephras-isle"), do: "Zephras Isle"
  defp continent_label(key), do: String.capitalize(key)

  defp rect_view_box({{x1, y1}, {x2, y2}}), do: "#{x1} #{y1} #{x2 - x1} #{y2 - y1}"

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
