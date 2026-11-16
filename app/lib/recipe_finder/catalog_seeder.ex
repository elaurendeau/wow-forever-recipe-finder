defmodule WowForeverRecipeFinder.CatalogSeeder do
  @moduledoc """
  Loads a profession's catalog from a `priv/catalog_seeds/<slug>.json`
  file (produced by the scrape pipeline — see docs/ARCHITECTURE.md §
  Catalog Construction) into Postgres. Used by `priv/repo/seeds.exs` and
  safe to re-run: each run atomically replaces that profession's
  patterns/reagents rather than appending duplicates, per
  docs/ARCHITECTURE.md's "replace atomically" rule.
  """

  import Ecto.Query

  alias WowForeverRecipeFinder.Repo
  alias WowForeverRecipeFinder.Gateways.Schema.{Item, Pattern, PatternReagent, Profession}

  @spec load_from_file!(Path.t()) :: :ok
  def load_from_file!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
    |> load!()

    :ok
  end

  defp load!(%{"profession" => profession_attrs, "patterns" => patterns}) do
    Repo.transaction(fn ->
      profession = upsert_profession!(profession_attrs)
      delete_existing_patterns!(profession)
      Enum.each(patterns, &insert_pattern!(profession, &1))
      mark_catalog_built!(profession)
    end)
  end

  defp upsert_profession!(%{"slug" => slug, "display_name" => display_name}) do
    case Repo.get_by(Profession, slug: slug) do
      nil -> Repo.insert!(%Profession{slug: slug, display_name: display_name})
      existing -> existing
    end
  end

  defp delete_existing_patterns!(%Profession{id: profession_id}) do
    # `pattern_reagent` rows cascade via the migration's `on_delete:
    # :delete_all` foreign key — deleting here is enough.
    Pattern
    |> where([p], p.profession_id == ^profession_id)
    |> Repo.delete_all()
  end

  defp insert_pattern!(profession, attrs) do
    crafted_item = upsert_item!(attrs["crafted_item"])

    pattern =
      Repo.insert!(%Pattern{
        profession_id: profession.id,
        crafted_item_id: crafted_item.id,
        name: attrs["name"],
        tier: attrs["tier"],
        skill: attrs["skill"],
        source: attrs["source"],
        wiki_slug: attrs["wiki_slug"],
        resolution_status: attrs["resolution_status"]
      })

    Enum.each(attrs["reagents"], fn reagent_attrs ->
      reagent_item = upsert_item!(reagent_attrs)

      Repo.insert!(%PatternReagent{
        pattern_id: pattern.id,
        item_id: reagent_item.id,
        quantity: reagent_attrs["quantity"]
      })
    end)

    pattern
  end

  defp upsert_item!(%{"wowhead_id" => wowhead_id, "display_name" => display_name, "wiki_slug" => wiki_slug}) do
    case Repo.get_by(Item, wowhead_id: wowhead_id) do
      nil -> Repo.insert!(%Item{wowhead_id: wowhead_id, display_name: display_name, wiki_slug: wiki_slug})
      existing -> existing
    end
  end

  defp mark_catalog_built!(profession) do
    profession
    |> Ecto.Changeset.change(catalog_built_at: DateTime.truncate(DateTime.utc_now(), :second))
    |> Repo.update!()
  end
end
