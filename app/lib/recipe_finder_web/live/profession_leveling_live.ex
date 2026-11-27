defmodule WowForeverRecipeFinderWeb.ProfessionLevelingLive do
  @moduledoc """
  The page behind docs/PRD.md § 7.13: pick a profession, see a full
  1→max-skill leveling path, one recipe recommended per skill range —
  never lose money, and among the recipes that don't, craft whichever
  sells fastest. Per docs/CODE_STYLE.md's Humble Object rule, this
  module only calls `ProfessionLeveling` and assigns its result; the
  actual join/ranking/path-building logic all lives there.
  """

  use WowForeverRecipeFinderWeb, :live_view

  alias WowForeverRecipeFinder.{PriceSnapshot, ProfessionLeveling, ProfitComputation}

  # Mining, Herbalism, Skinning and Fishing are excluded per docs/PRD.md
  # § 7.13 — confirmed via the real capture to have zero recipe_items,
  # and they were never part of this app's catalog to begin with.
  @professions [
    {"tailoring", "Tailoring"},
    {"enchanting", "Enchanting"},
    {"blacksmithing", "Blacksmithing"},
    {"leatherworking", "Leatherworking"},
    {"alchemy", "Alchemy"},
    {"engineering", "Engineering"},
    {"cooking", "Cooking"},
    {"firstaid", "First Aid"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        active_profession: "tailoring",
        price_snapshot: nil,
        captured_at: nil,
        path: [],
        upload_error: nil,
        price_basis: ProfitComputation.default_price_basis()
      )
      |> allow_upload(:tsm_export, accept: ~w(.lua), max_entries: 1, max_file_size: 20_000_000)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_tab", %{"slug" => slug}, socket) do
    {:noreply, socket |> assign(active_profession: slug) |> recompute_path()}
  end

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

  # See RecipeFinderLive's own copy of this handler for why: lets a
  # revisit skip re-uploading, since no browser lets a script prefill
  # an <input type="file">'s path. See assets/js/app.js.
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

  def handle_event("clear_snapshot", _params, socket) do
    socket =
      socket
      |> assign(price_snapshot: nil, captured_at: nil, path: [], upload_error: nil)
      |> push_event("clear_snapshot", %{})

    {:noreply, socket}
  end

  def handle_event("select_realm", %{"realm" => realm}, socket) do
    socket =
      socket
      |> assign(price_snapshot: PriceSnapshot.for_realm(socket.assigns.price_snapshot, realm))
      |> recompute_path()
      |> push_event("store_realm", %{realm: realm})

    {:noreply, socket}
  end

  def handle_event("set_price_basis", %{"basis" => basis}, socket) do
    {:noreply, socket |> assign(price_basis: String.to_existing_atom(basis)) |> recompute_path()}
  end

  defp load_export(socket, export_text, captured_at, saved_realm) do
    case ProfitComputation.parse_export(export_text) do
      {:ok, snapshot} ->
        snapshot = PriceSnapshot.for_realm(snapshot, saved_realm)

        socket =
          socket
          |> assign(price_snapshot: snapshot, captured_at: captured_at, upload_error: nil)
          |> recompute_path()

        {:ok, socket}

      {:error, reason} ->
        {:error, assign(socket, upload_error: format_parse_error(reason))}
    end
  end

  defp recompute_path(socket) do
    case socket.assigns.price_snapshot do
      nil ->
        assign(socket, path: [])

      snapshot ->
        results =
          ProfessionLeveling.compute_results(
            socket.assigns.active_profession,
            snapshot,
            socket.assigns.price_basis
          )

        assign(socket, path: ProfessionLeveling.build_path(results))
    end
  end

  defp format_parse_error({:no_load_data_lines_found}),
    do: "That doesn't look like a TSM AppData.lua export — no price tables were found in it."

  defp format_parse_error({:table_not_found, table}),
    do: "This export has no #{table} table — it may be from an unsupported TSM version."

  defp format_parse_error({:no_usable_rows, table}),
    do:
      "This export's #{table} table has no price data yet — try running a fresh AH scan in TSM first."

  defp format_parse_error(_other), do: "Couldn't read this file as a TSM export."

  defp professions, do: @professions

  # The "/forever" shape is this project's own server — see
  # docs/DATA_SOURCES.md § Warcraft Wiki for the three observed shapes;
  # the numeric item ID is shared across all of them.
  defp wowhead_url(wowhead_id), do: "https://www.wowhead.com/forever/item=#{wowhead_id}"

  defp skill_range_label(from_skill, from_skill), do: "#{from_skill}"
  defp skill_range_label(from_skill, to_skill), do: "#{from_skill}–#{to_skill}"

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
  defp format_number(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 3)
  defp format_number(n), do: Integer.to_string(n)

  defp format_profit(nil), do: "—"
  defp format_profit(copper), do: "(#{format_copper(copper)} profit)"
end
