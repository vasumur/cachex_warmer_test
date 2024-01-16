defmodule CachexWarmerTest.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  import Cachex.Spec

  @impl true
  def start(_type, _args) do
    children =
      [
        CachexWarmerTestWeb.Telemetry,
        # CachexWarmerTest.Repo,
        {DNSCluster,
         query: Application.get_env(:cachex_warmer_test, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: CachexWarmerTest.PubSub},
        # Start the Finch HTTP client for sending emails
        {Finch, name: CachexWarmerTest.Finch},
        # Start a worker by calling: CachexWarmerTest.Worker.start_link(arg)
        # {CachexWarmerTest.Worker, arg},
        # Start to serve requests, typically the last entry
        CachexWarmerTestWeb.Endpoint
      ] ++ caches()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CachexWarmerTest.Supervisor]
    ret = Supervisor.start_link(children, opts)
    initialize_app()
    ret
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CachexWarmerTestWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  def caches() do
    [
      Supervisor.child_spec({Cachex, name: :cache1, warmers: []},
        id: :cache1
      ),
      Supervisor.child_spec({Cachex, name: :cache2, warmers: []},
        id: :cache2
      ),
      Supervisor.child_spec({Cachex, name: :cache3, warmers: []},
        id: :cache3
      ),
      Supervisor.child_spec({Cachex, name: :cache4, warmers: []},
        id: :cache4
      ),
      Supervisor.child_spec(
        {Cachex,
         name: :cache5,
         warmers: [warmer(module: CachexWarmerTest.Warmers.Cachex2Warmer, state: nil)]},
        id: :cache5
      ),
      Supervisor.child_spec({Cachex, name: :cache6, warmers: []},
        id: :cache6
      ),
      Supervisor.child_spec({Cachex, name: :cache7, warmers: []},
        id: :cache7
      )
    ]
  end

  def initialize_app() do
    {:ok, true} = Cachex.put(:cache1, "some", "value")
  end
end
