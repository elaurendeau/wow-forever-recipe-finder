defmodule WowForeverRecipeFinderWeb.WritsLive do
  @moduledoc """
  The Craftsman's Writs map, per docs/PRD.md § 7.8 and the reference
  mockup docs/mockups/writs-map-reference.html. Humble Object: loading,
  placing, filtering and grouping all live in `WritAtlas`; this module
  only holds the filter state and shapes data for the template. Zoom and
  pan are client-side (the `WritMap` hook in assets/js/app.js), so they
  survive filter changes without a server round trip.
  """

  use WowForeverRecipeFinderWeb, :live_view

  alias WowForeverRecipeFinder.WritAtlas

  @professions [
    {"alchemy", "Alchemy"},
    {"blacksmithing", "Blacksmithing"},
    {"engineering", "Engineering"},
    {"leatherworking", "Leatherworking"},
    {"tailoring", "Tailoring"}
  ]

  @tier_labels %{journeyman: "Journeyman", expert: "Expert", artisan: "Artisan"}
  @tiers_by_param %{"journeyman" => :journeyman, "expert" => :expert, "artisan" => :artisan}
  @sides [{"any", "Either"}, {"alliance", "Alliance"}, {"horde", "Horde"}]
  @sides_by_param %{"any" => :any, "alliance" => :alliance, "horde" => :horde}

  # The visible part of Wowhead's world canvas: Kalimdor's art starts at
  # x = 8192, and nothing sits above y = 4000.
  @world_view_box [8192, 4000, 36352, 30000]
  @continent_labels [
    {"world", "Azeroth"},
    {"kalimdor", "Kalimdor"},
    {"zephras-isle", "Zephras Isle"},
    {"eastern-kingdoms", "Eastern Kingdoms"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Craftsman's Writs", criteria: WritAtlas.default_criteria(), selected_pin_id: nil)
      |> assign(view: "world")
      |> assign_atlas(WritAtlas.load_atlas())
      |> assign_derived()

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_profession", %{"profession" => profession}, socket) do
    if List.keymember?(@professions, profession, 0) do
      {:noreply, update_criteria(socket, :professions, &toggle(&1, profession))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_tier", %{"tier" => param}, socket) do
    case Map.fetch(@tiers_by_param, param) do
      {:ok, tier} -> {:noreply, update_criteria(socket, :tiers, &toggle(&1, tier))}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("set_side", %{"side" => param}, socket) do
    case Map.fetch(@sides_by_param, param) do
      {:ok, side} -> {:noreply, update_criteria(socket, :side, fn _ -> side end)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("search", %{"search" => text}, socket) do
    {:noreply, update_criteria(socket, :search, fn _ -> text end)}
  end

  def handle_event("select_pin", %{"id" => id}, socket) do
    {:noreply, socket |> assign(selected_pin_id: id) |> assign_derived()}
  end

  def handle_event("select_writ", %{"pin" => id}, socket) do
    socket = socket |> assign(selected_pin_id: id) |> assign_derived()

    case socket.assigns.selected_pin do
      nil -> {:noreply, socket}
      pin -> {:noreply, push_event(socket, "focus_pin", %{x: pin.x, y: pin.y})}
    end
  end

  def handle_event("clear_pin", _params, socket) do
    {:noreply, socket |> assign(selected_pin_id: nil) |> assign_derived()}
  end

  def handle_event("show_view", %{"view" => view}, socket) do
    case view_box(socket.assigns.world_map, view) do
      nil -> {:noreply, socket}
      box -> {:noreply, socket |> assign(view: view) |> push_event("show_view", %{view_box: box})}
    end
  end

  defp assign_atlas(socket, {:ok, %{world_map: world_map, writs: writs}}) do
    hot_areas = writs |> Enum.filter(&WritAtlas.placed?/1) |> MapSet.new(& &1.hand_in.zone_id)

    assign(socket,
      world_map: world_map,
      writs: writs,
      hot_areas: hot_areas,
      profession_counts: WritAtlas.profession_counts(writs),
      tier_counts: WritAtlas.tier_counts(writs),
      load_error: nil
    )
  end

  defp assign_atlas(socket, {:error, error}) do
    assign(socket,
      world_map: nil,
      writs: [],
      hot_areas: MapSet.new(),
      profession_counts: %{},
      tier_counts: %{},
      load_error: error
    )
  end

  defp update_criteria(socket, key, fun) do
    socket
    |> assign(criteria: Map.update!(socket.assigns.criteria, key, fun))
    |> assign_derived()
  end

  defp assign_derived(socket) do
    %{writs: writs, criteria: criteria, selected_pin_id: selected_pin_id} = socket.assigns
    pins = WritAtlas.hand_in_pins(writs, criteria)

    assign(socket,
      pins: pins,
      selected_pin: WritAtlas.find_pin(pins, selected_pin_id),
      placed_by_zone: writs |> WritAtlas.placed_writs(criteria) |> WritAtlas.group_by_zone(),
      unplaced: WritAtlas.unplaced_writs(writs, criteria)
    )
  end

  defp toggle(set, value) do
    if MapSet.member?(set, value), do: MapSet.delete(set, value), else: MapSet.put(set, value)
  end

  attr :writ, :map, required: true
  attr :with_location, :boolean, required: true

  defp writ_row(assigns) do
    ~H"""
    <div class="wm-writ" phx-click="select_writ" phx-value-pin={WritAtlas.pin_id_for(@writ)}>
      <div class="wm-writ-top">
        <span class="wm-writ-name">{@writ.name}</span>
        <span class={["wm-tier", Atom.to_string(@writ.tier)]}>{tier_label(@writ.tier)}</span>
      </div>
      <div class="wm-writ-meta">
        <span>{professions_text(@writ)}</span>
        <span :if={@with_location}>{@writ.hand_in.npc_name || "Unknown NPC"} · {@writ.hand_in.zone}</span>
      </div>
      <div :for={item <- @writ.required_items} class="wm-need">
        <span class="wm-qty">{item.quantity}×</span>
        <a href={wowhead_item_url(item.wowhead_id)} target="_blank" rel="noopener">{item.display_name}</a>
      </div>
      <div class="wm-rewards">
        <span :for={{kind, text} <- reward_parts(@writ)} class={"wm-reward #{kind}"}>{text}</span>
      </div>
    </div>
    """
  end

  # ---- template helpers (pure formatting only) ----

  defp professions, do: @professions
  defp sides, do: @sides
  defp continent_labels, do: @continent_labels
  defp tiers, do: WritAtlas.tiers()
  defp tier_label(tier), do: Map.fetch!(@tier_labels, tier)

  defp profession_label(slug) do
    Enum.find_value(@professions, String.capitalize(slug), fn {s, label} -> s == slug && label end)
  end

  defp professions_text(writ) do
    labels = professions_label(writ, " / ")

    case writ.required_items do
      [%{skill: skill} | _] when is_integer(skill) -> "#{labels} #{skill}"
      _ -> labels
    end
  end

  defp professions_label(writ, separator), do: Enum.map_join(writ.professions, separator, &profession_label/1)

  defp side_selected?(criteria, param), do: Map.fetch!(@sides_by_param, param) == criteria.side

  defp writ_count_label(1), do: "1 writ"
  defp writ_count_label(n), do: "#{n} writs"

  defp placed_count(placed_by_zone) do
    placed_by_zone |> Enum.map(fn {_zone, writs} -> length(writs) end) |> Enum.sum()
  end

  defp reward_parts(%{rewards: rewards}) do
    money = if rewards.money_copper > 0, do: [{:money, format_money(rewards.money_copper)}], else: []
    [{:rep, "+#{rewards.reputation} rep"}] ++ money ++ Enum.map(rewards.item_names, &{:item, &1})
  end

  defp format_money(copper) do
    [{div(copper, 10_000), "g"}, {div(rem(copper, 10_000), 100), "s"}, {rem(copper, 100), "c"}]
    |> Enum.reject(fn {value, _unit} -> value == 0 end)
    |> Enum.map_join(" ", fn {value, unit} -> "#{value}#{unit}" end)
  end

  defp wowhead_item_url(wowhead_id), do: "https://www.wowhead.com/forever/item=#{wowhead_id}"

  defp initial_view_box, do: Enum.join(@world_view_box, " ")

  defp view_box(_world_map, "world"), do: @world_view_box
  defp view_box(nil, _view), do: nil

  defp view_box(world_map, view) do
    case Enum.find(world_map.continents, &(&1.key == view)) do
      %{rect: {{x1, y1}, {x2, y2}}} -> [x1, y1, x2 - x1, y2 - y1]
      nil -> nil
    end
  end

  # Polygons → one SVG path (draw with fill-rule="evenodd" so holes such as
  # lakes stay open).
  defp svg_path(polygons) do
    Enum.map_join(polygons, fn rings ->
      Enum.map_join(rings, fn [{x0, y0} | rest] ->
        "M#{x0} #{y0}" <> Enum.map_join(rest, fn {x, y} -> "L#{x} #{y}" end) <> "Z"
      end)
    end)
  end

  defp zone_labels(world_map), do: Enum.filter(world_map.zones, &(&1.name && &1.label && &1.kind != "capital"))

  defp zone_title(%{name: nil}), do: nil
  defp zone_title(zone), do: zone.name

  defp pin_title(pin), do: "#{pin.npc_name || "Unknown NPC"} — #{pin.zone} (#{pin.way_x}, #{pin.way_y})"

  defp format_load_error(%{file: file, reason: reason}) do
    "The writ data couldn't be loaded (#{file}: #{inspect(reason)}). " <>
      "The map is unavailable until the data file is fixed."
  end
end
