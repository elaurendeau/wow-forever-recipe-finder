defmodule WowForeverRecipeFinder.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  # Nested boundary, distinct from the parent `WowForeverRecipeFinder` one:
  # the composition root legitimately needs to reference Web modules
  # (Endpoint, Telemetry) to build the supervision tree. Scoping this
  # dependency to just this module — rather than giving the whole Core
  # boundary a dep on Web — keeps the dependency graph acyclic (Web already
  # depends on Core) and keeps every other Core module from being able to
  # reach into Web.
  use Boundary, deps: [WowForeverRecipeFinderWeb], top_level?: true

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WowForeverRecipeFinderWeb.Telemetry,
      WowForeverRecipeFinder.Repo,
      {DNSCluster, query: Application.get_env(:recipe_finder, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: WowForeverRecipeFinder.PubSub},
      # Start a worker by calling: WowForeverRecipeFinder.Worker.start_link(arg)
      # {WowForeverRecipeFinder.Worker, arg},
      # Start to serve requests, typically the last entry
      WowForeverRecipeFinderWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WowForeverRecipeFinder.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WowForeverRecipeFinderWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
