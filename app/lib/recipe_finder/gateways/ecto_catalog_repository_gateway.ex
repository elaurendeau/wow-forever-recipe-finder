defmodule WowForeverRecipeFinder.Gateways.EctoCatalogRepositoryGateway do
  @moduledoc """
  The real, Postgres-backed implementation of `CatalogRepositoryGateway`.
  Converts `Gateways.Schema.*` rows into plain `WowForeverRecipeFinder.*`
  domain structs at this boundary — nothing past this module ever sees
  an `Ecto.Schema` struct for the catalog. See docs/CODE_STYLE.md §
  Clean Architecture.
  """

  @behaviour WowForeverRecipeFinder.Gateways.CatalogRepositoryGateway

  import Ecto.Query

  alias WowForeverRecipeFinder.Repo
  alias WowForeverRecipeFinder.{Item, Pattern, Reagent}
  alias WowForeverRecipeFinder.Gateways.Schema

  @impl true
  def list_patterns(profession_slug) do
    query =
      from p in Schema.Pattern,
        join: prof in assoc(p, :profession),
        where: prof.slug == ^profession_slug,
        preload: [:crafted_item, pattern_reagents: :item]

    query
    |> Repo.all()
    |> Enum.map(&to_domain(&1, profession_slug))
  end

  @impl true
  def known_profession_slugs do
    Schema.Profession
    |> where([p], not is_nil(p.catalog_built_at))
    |> select([p], p.slug)
    |> Repo.all()
  end

  defp to_domain(%Schema.Pattern{} = row, profession_slug) do
    %Pattern{
      id: row.id,
      profession_slug: profession_slug,
      crafted_item: to_item(row.crafted_item),
      name: row.name,
      tier: parse_tier!(row.tier),
      skill: row.skill,
      source: row.source && parse_source!(row.source),
      wiki_slug: row.wiki_slug,
      resolution_status: parse_resolution_status!(row.resolution_status),
      reagents: Enum.map(row.pattern_reagents, &to_reagent/1)
    }
  end

  # Explicit, closed mappings rather than `String.to_existing_atom/1` —
  # that function only succeeds if some *other* already-executed code
  # happened to reference the atom literally first, which these never
  # were (only in a `@type` spec, which creates no atom at runtime). A
  # row holding anything outside this known set fails loudly rather
  # than crashing on an unrelated-looking `ArgumentError` deep in Ecto's
  # preload path — see docs/ARCHITECTURE.md § Validate at the Boundary.
  defp parse_tier!("apprentice"), do: :apprentice
  defp parse_tier!("journeyman"), do: :journeyman
  defp parse_tier!("expert"), do: :expert
  defp parse_tier!("artisan"), do: :artisan
  defp parse_tier!(other), do: raise(ArgumentError, "unknown pattern tier: #{inspect(other)}")

  defp parse_source!("trainer"), do: :trainer
  defp parse_source!("vendor"), do: :vendor
  defp parse_source!("drop"), do: :drop
  defp parse_source!("quest"), do: :quest
  defp parse_source!(other), do: raise(ArgumentError, "unknown pattern source: #{inspect(other)}")

  defp parse_resolution_status!("resolved"), do: :resolved
  defp parse_resolution_status!("no_wiki_page"), do: :no_wiki_page
  defp parse_resolution_status!("reagent_cost_incomplete"), do: :reagent_cost_incomplete

  defp parse_resolution_status!(other),
    do: raise(ArgumentError, "unknown pattern resolution_status: #{inspect(other)}")

  defp to_item(%Schema.Item{} = row) do
    %Item{id: row.id, wowhead_id: row.wowhead_id, display_name: row.display_name, wiki_slug: row.wiki_slug}
  end

  defp to_reagent(%Schema.PatternReagent{} = row) do
    %Reagent{item: to_item(row.item), quantity: row.quantity}
  end
end
