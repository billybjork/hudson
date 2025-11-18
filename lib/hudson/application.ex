defmodule Hudson.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      HudsonWeb.Telemetry,
      Hudson.Repo,
      Hudson.LocalRepo,
      {Oban, Application.fetch_env!(:hudson, Oban)},
      {DNSCluster, query: Application.get_env(:hudson, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Hudson.PubSub},
      # Start a worker by calling: Hudson.Worker.start_link(arg)
      # {Hudson.Worker, arg},
      # Start to serve requests, typically the last entry
      HudsonWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Hudson.Supervisor]
    {:ok, supervisor_pid} = Supervisor.start_link(children, opts)

    Hudson.LocalRepoMigrator.migrate()
    Hudson.RuntimeSmoke.check_nifs()

    {:ok, supervisor_pid}
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HudsonWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
