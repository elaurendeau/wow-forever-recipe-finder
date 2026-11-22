defmodule WowForeverRecipeFinderWeb.MerchantFavorLive do
  @moduledoc """
  Per docs/PRD.md § 7.11: a separate page ranking Waylaid Crates by AH
  cost (the crate itself plus the cheapest priceable fill option) —
  the most cost-effective way to buy straight into a Sealed Crate.
  Shares its uploaded TSM snapshot with `RecipeFinderLive`/`WritsLive`
  via the same client-held `localStorage` keys (see assets/js/app.js's
  `TsmSnapshot` hook) — a visitor who already uploaded elsewhere never
  re-uploads here.

  Per docs/CODE_STYLE.md's Humble Object rule, this module only calls
  context functions (`CrateEfficiency`, `CrateResultsFilter`,
  `CrateShoppingList`, `ProfitComputation.parse_export/1`) and assigns
  their results — the actual parsing/joining/filtering logic all lives
  there, not here.
  """

  use WowForeverRecipeFinderWeb, :live_view

  alias WowForeverRecipeFinder.{
    CrateEfficiency,
    CrateResultsFilter,
    CrateShoppingList,
    PriceSnapshot,
    ProfitComputation
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
        filter: CrateResultsFilter.default_criteria(),
        # crate id => chosen quantity. Session-only, not persisted to
        # localStorage, same deliberate scope cut as the writs' own
        # selection — see docs/PRD.md § 7.9.
        quantities: %{},
        shopping_list_open?: false,
        shopping_list_unseen?: false
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

        case load_export(socket, export_text, captured_at, nil) do
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

  # Same cross-page restore contract as RecipeFinderLive/WritsLive —
  # see assets/js/app.js's TsmSnapshot hook.
  def handle_event("restore_snapshot", %{"data" => export_text} = params, socket) do
    captured_at =
      case DateTime.from_iso8601(params["captured_at"] || "") do
        {:ok, dt, _offset} -> dt
        {:error, _reason} -> DateTime.utc_now()
      end

    case load_export(socket, export_text, captured_at, params["realm"]) do
      {:ok, socket} -> {:noreply, socket}
      {:error, socket} -> {:noreply, push_event(socket, "clear_snapshot", %{})}
    end
  end

  # Same shared realm selector as every page — see RecipeFinderLive's
  # own handler for the full rationale.
  def handle_event("select_realm", %{"realm" => realm}, socket) do
    snapshot = PriceSnapshot.for_realm(socket.assigns.price_snapshot, realm)

    socket =
      socket
      |> assign(price_snapshot: snapshot, results: CrateEfficiency.compute_results(snapshot))
      |> push_event("store_realm", %{realm: realm})

    {:noreply, socket}
  end

  def handle_event("clear_snapshot", _params, socket) do
    socket =
      socket
      |> assign(
        price_snapshot: nil,
        captured_at: nil,
        results: [],
        upload_error: nil,
        quantities: %{},
        shopping_list_open?: false,
        shopping_list_unseen?: false
      )
      |> push_event("clear_snapshot", %{})

    {:noreply, socket}
  end

  def handle_event("set_quantity", %{"id" => id_str, "value" => value_str}, socket) do
    id = String.to_integer(id_str)
    quantity = max(parse_int(value_str) || 0, 0)
    quantities = Map.put(socket.assigns.quantities, id, quantity)

    {:noreply,
     assign(socket,
       quantities: quantities,
       shopping_list_unseen?: not socket.assigns.shopping_list_open?
     )}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply,
     assign(socket,
       quantities: %{},
       shopping_list_open?: false,
       shopping_list_unseen?: false
     )}
  end

  def handle_event("toggle_shopping_list_panel", _params, socket) do
    open? = not socket.assigns.shopping_list_open?
    unseen? = if open?, do: false, else: socket.assigns.shopping_list_unseen?

    {:noreply, assign(socket, shopping_list_open?: open?, shopping_list_unseen?: unseen?)}
  end

  def handle_event("filter_changed", %{"filter" => params}, socket) do
    filter =
      socket.assigns.filter
      |> Map.merge(%{
        search: Map.get(params, "search", socket.assigns.filter.search),
        max_cost_copper: parse_int(Map.get(params, "max_cost_copper"))
      })

    {:noreply, assign(socket, filter: filter)}
  end

  def handle_event("set_tier", %{"tier" => tier}, socket) do
    filter = %{socket.assigns.filter | tier: String.to_existing_atom(tier)}
    {:noreply, assign(socket, filter: filter)}
  end

  def handle_event("toggle_sort_dir", _params, socket) do
    new_dir = if socket.assigns.filter.sort_dir == :asc, do: :desc, else: :asc
    {:noreply, assign(socket, filter: %{socket.assigns.filter | sort_dir: new_dir})}
  end

  defp load_export(socket, export_text, captured_at, saved_realm) do
    case ProfitComputation.parse_export(export_text) do
      {:ok, snapshot} ->
        snapshot = PriceSnapshot.for_realm(snapshot, saved_realm)

        socket =
          socket
          |> assign(price_snapshot: snapshot, captured_at: captured_at, upload_error: nil)
          |> assign(results: CrateEfficiency.compute_results(snapshot))

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

  # Same messages as RecipeFinderLive's/WritsLive's — all three pages
  # parse the exact same upload shape via the same context function.
  defp format_parse_error({:no_load_data_lines_found}),
    do: "That doesn't look like a TSM AppData.lua export — no price tables were found in it."

  defp format_parse_error({:table_not_found, table}),
    do: "This export has no #{table} table — it may be from an unsupported TSM version."

  defp format_parse_error({:no_usable_rows, table}),
    do:
      "This export's #{table} table has no price data yet — try running a fresh AH scan in TSM first."

  defp format_parse_error(_other), do: "Couldn't read this file as a TSM export."

  defp tier_label(tier), do: tier |> to_string() |> String.capitalize()
  defp quality_label(quality), do: quality |> to_string() |> String.capitalize()
  defp category_label(category), do: String.capitalize(category)

  defp tiers,
    do: [
      {"any", "Any"},
      {"apprentice", "Apprentice"},
      {"journeyman", "Journeyman"},
      {"expert", "Expert"},
      {"artisan", "Artisan"}
    ]

  defp tier_selected?(filter, tier_param), do: Atom.to_string(filter.tier) == tier_param

  # The "/forever" shape is this project's own server — see
  # docs/DATA_SOURCES.md § Warcraft Wiki for the three observed item
  # URL shapes.
  defp wowhead_item_url(wowhead_id), do: "https://www.wowhead.com/forever/item=#{wowhead_id}"

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

  defp no_fill_data?(result), do: :no_fill_options_data in result.missing_data_reasons
  defp no_priceable_fill?(result), do: :no_priceable_fill_option in result.missing_data_reasons

  defp sort_indicator(filter) do
    if filter.sort_dir == :desc, do: " ▼", else: " ▲"
  end
end
