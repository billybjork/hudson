defmodule Hudson.LocalRepoMigrator do
  @moduledoc """
  Ensures the SQLite local cache schema is migrated on startup.
  """

  require Logger
  alias Hudson.Desktop.Bootstrap

  @migrations_path Application.app_dir(:hudson, "priv/local_repo/migrations")

  def migrate do
    Bootstrap.ensure_data_dir!()

    if File.dir?(@migrations_path) do
      Logger.info("Running local SQLite migrations for Hudson.LocalRepo")

      Ecto.Migrator.with_repo(Hudson.LocalRepo, fn repo ->
        Ecto.Migrator.run(repo, @migrations_path, :up, all: true)
      end)
    else
      Logger.warning("SQLite migrations path missing: #{@migrations_path}")
      :ok
    end
  end
end
