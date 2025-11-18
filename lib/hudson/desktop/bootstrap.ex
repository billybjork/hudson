defmodule Hudson.Desktop.Bootstrap do
  @moduledoc """
  Helpers for desktop bootstrap during the Tauri pilot:
  - Picks loopback ports
  - Writes the port handshake file consumed by Tauri
  - Generates/persists secrets so first-run boot does not fail
  """

  @handshake_file "hudson_port.json"
  @secret_file "secret_key_base"

  @doc "Resolve a writable per-user data directory (platform aware)."
  def data_dir do
    :filename.basedir(:user_data, ~c"Hudson")
    |> IO.iodata_to_binary()
  end

  def ensure_data_dir! do
    data_dir()
    |> Path.dirname()
    |> File.mkdir_p!()

    File.mkdir_p!(data_dir())
  end

  def local_db_path do
    Path.join(data_dir(), "local.db")
  end

  @doc "Path used by the Tauri shell to read the chosen port."
  def handshake_path do
    case :os.type() do
      {:unix, :darwin} -> "/tmp/#{@handshake_file}"
      {:win32, _} -> Path.join(data_dir(), "port.json")
      _ -> Path.join(System.tmp_dir!(), @handshake_file)
    end
  end

  @doc "Pick an available loopback port for the embedded endpoint."
  def pick_ephemeral_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  @doc "Always write the handshake file so Tauri can discover the port."
  def write_handshake!(port) do
    path = handshake_path()

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, Jason.encode!(%{port: port}))
    path
  end

  @doc """
  First-run friendly secret key base.

  Prefers env, otherwise loads from disk, falling back to generating and persisting a new value.
  """
  def ensure_secret_key_base do
    System.get_env("SECRET_KEY_BASE") ||
      read_secret_from_disk() ||
      generate_and_store_secret()
  end

  def database_url do
    System.get_env("DATABASE_URL") || default_database_url()
  end

  def default_database_url do
    username = System.get_env("DATABASE_USER", "postgres")
    password = System.get_env("DATABASE_PASSWORD", "postgres")
    host = System.get_env("DATABASE_HOST", "localhost")
    db = System.get_env("DATABASE_NAME", "hudson_dev")

    "ecto://#{username}:#{password}@#{host}/#{db}"
  end

  defp secret_key_path, do: Path.join(data_dir(), @secret_file)

  defp read_secret_from_disk do
    case File.read(secret_key_path()) do
      {:ok, secret} -> String.trim(secret)
      _ -> nil
    end
  end

  defp generate_and_store_secret do
    secret =
      64
      |> :crypto.strong_rand_bytes()
      |> Base.encode64()

    path = secret_key_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, secret)
    secret
  end
end
