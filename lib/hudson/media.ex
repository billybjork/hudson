defmodule Hudson.Media do
  @moduledoc """
  Media upload and management for product images.
  Uses Supabase Storage with service role for uploads.
  """

  require Logger

  @bucket "products"

  @doc """
  Uploads a product image to Supabase Storage.

  Uploads both full-size and thumbnail versions:
  - Full: {product_id}/full/{position}.jpg
  - Thumbnail: {product_id}/thumb/{position}.jpg (20px wide, blurred)

  Returns {:ok, %{path: ..., thumbnail_path: ...}} on success.
  """
  def upload_product_image(file_path, product_id, position) do
    client = build_client()
    storage = Supabase.Storage.from(client, @bucket)

    # Upload full-size image
    full_path = "#{product_id}/full/#{position}.jpg"

    with {:ok, _response} <- Supabase.Storage.File.upload(storage, file_path, full_path, %{
           content_type: "image/jpeg",
           upsert: true
         }) do
      # Generate and upload thumbnail
      case generate_and_upload_thumbnail(storage, file_path, product_id, position) do
        {:ok, thumb_path} ->
          {:ok, %{path: full_path, thumbnail_path: thumb_path}}

        {:error, reason} ->
          Logger.warning("Thumbnail generation failed: #{inspect(reason)}, using full image")
          # If thumbnail fails, use full image as fallback
          {:ok, %{path: full_path, thumbnail_path: full_path}}
      end
    end
  end

  # Generates a thumbnail and uploads it to Supabase Storage.
  # Uses ImageMagick to create a 20px wide, blurred thumbnail for LQIP.
  defp generate_and_upload_thumbnail(storage, source_file, product_id, position) do
    thumb_tmp = Path.join(System.tmp_dir!(), "thumb_#{product_id}_#{position}.jpg")

    # Using ImageMagick convert command (tries v7 'magick' first, falls back to 'convert')
    {cmd, args} =
      case System.cmd("magick", ["--version"], stderr_to_stdout: true) do
        {_, 0} -> {"magick", ["convert" | [source_file, "-resize", "20x", "-quality", "50", "-blur", "0x2", thumb_tmp]]}
        _ -> {"convert", [source_file, "-resize", "20x", "-quality", "50", "-blur", "0x2", thumb_tmp]}
      end

    case System.cmd(cmd, args) do
      {_, 0} ->
        thumb_path = "#{product_id}/thumb/#{position}.jpg"

        with {:ok, _response} <-
               Supabase.Storage.File.upload(storage, thumb_tmp, thumb_path, %{
                 content_type: "image/jpeg",
                 upsert: true
               }) do
          File.rm(thumb_tmp)
          {:ok, thumb_path}
        end

      {output, exit_code} ->
        Logger.error("ImageMagick failed (exit #{exit_code}): #{output}")
        {:error, :thumbnail_generation_failed}
    end
  end

  @doc """
  Constructs a public URL for an image path.

  Example:
    iex> Hudson.Media.public_image_url("9/full/1.jpg")
    "https://wqyufugasulvfrpgixqu.supabase.co/storage/v1/object/public/products/9/full/1.jpg"
  """
  def public_image_url(path) when is_binary(path) do
    # Read from env var at runtime
    storage_public_url = System.get_env("SUPABASE_STORAGE_PUBLIC_URL") ||
      Application.get_env(:hudson, :storage_public_url) ||
      ""

    "#{storage_public_url}/#{@bucket}/#{path}"
  end

  def public_image_url(_), do: "/images/placeholder.png"

  # Builds a Supabase client with service role credentials.
  defp build_client do
    # Read directly from env vars at runtime since config may be nil
    supabase_url = System.get_env("SUPABASE_URL") ||
      Application.get_env(:hudson, :supabase_url) ||
      raise "SUPABASE_URL not configured"

    service_role_key = System.get_env("SUPABASE_SERVICE_ROLE_KEY") ||
      Application.get_env(:hudson, :supabase_service_role_key) ||
      raise "SUPABASE_SERVICE_ROLE_KEY not configured"

    Supabase.init_client!(supabase_url, service_role_key)
  end

  @doc """
  Checks if ImageMagick is available on the system.
  """
  def imagemagick_available? do
    # Try v7 'magick' command first, then fall back to 'convert'
    case System.cmd("magick", ["--version"], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      _ ->
        case System.cmd("convert", ["-version"], stderr_to_stdout: true) do
          {output, 0} -> {:ok, output}
          _ -> {:error, :not_found}
        end
    end
  end
end
