defmodule Pavoi.TiktokShop do
  @moduledoc """
  The TiktokShop context handles TikTok Shop API authentication and operations.
  """

  import Ecto.Query, warn: false
  alias Pavoi.Repo
  alias Pavoi.TiktokShop.Auth

  # Configuration
  defp app_key, do: System.get_env("TTS_APP_KEY")
  defp app_secret, do: System.get_env("TTS_APP_SECRET")
  defp service_id, do: System.get_env("TTS_SERVICE_ID")
  defp region, do: System.get_env("TTS_REGION", "Global")
  defp auth_base, do: System.get_env("TTS_AUTH_BASE", "https://auth.tiktok-shops.com")
  defp api_base, do: System.get_env("TTS_API_BASE", "https://open-api.tiktokglobalshop.com")

  @doc """
  Generates an authorization URL for the user to approve the app.

  Returns the URL as a string that the user should visit in their browser.
  After authorization, they'll be redirected to the configured redirect_uri with an auth code.
  """
  def generate_authorization_url do
    # Determine the correct authorization base URL based on region
    auth_url_base =
      case region() do
        "US" -> "https://services.us.tiktokshop.com"
        _ -> "https://services.tiktokshop.com"
      end

    state = generate_state()

    "#{auth_url_base}/open/authorize?service_id=#{service_id()}&state=#{state}"
  end

  @doc """
  Exchanges an authorization code for access and refresh tokens.

  This should be called in your OAuth callback handler after the user approves the app.
  Stores the tokens in the database and returns the auth record.
  """
  def exchange_code_for_token(auth_code) do
    url = "#{auth_base()}/api/v2/token/get"

    params = [
      app_key: app_key(),
      app_secret: app_secret(),
      auth_code: auth_code,
      grant_type: "authorized_code"
    ]

    case Req.get(url, params: params) do
      {:ok, %Req.Response{status: 200, body: %{"data" => token_data}}} ->
        store_tokens(token_data)

      {:ok, %Req.Response{status: 200, body: response}} ->
        {:error, "Token exchange failed: #{inspect(response)}"}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, error} ->
        {:error, "Request failed: #{inspect(error)}"}
    end
  end

  @doc """
  Refreshes the access token using the refresh token.

  Should be called when the access token expires.
  Updates the tokens in the database.
  """
  def refresh_access_token do
    case get_auth() do
      nil ->
        {:error, :no_auth_record}

      auth ->
        url = "#{auth_base()}/api/v2/token/get"

        params = [
          app_key: app_key(),
          app_secret: app_secret(),
          refresh_token: auth.refresh_token,
          grant_type: "refresh_token"
        ]

        case Req.get(url, params: params) do
          {:ok, %Req.Response{status: 200, body: %{"data" => token_data}}} ->
            update_tokens(auth, token_data)

          {:ok, %Req.Response{status: 200, body: response}} ->
            {:error, "Token refresh failed: #{inspect(response)}"}

          {:ok, %Req.Response{status: status, body: body}} ->
            {:error, "HTTP #{status}: #{inspect(body)}"}

          {:error, error} ->
            {:error, "Request failed: #{inspect(error)}"}
        end
    end
  end

  @doc """
  Gets the authorized shops and extracts shop_id and shop_cipher.

  This should be called after obtaining an access token to get shop-specific credentials.
  Updates the auth record with shop information.
  """
  def get_authorized_shops do
    case get_auth() do
      nil ->
        {:error, :no_auth_record}

      auth ->
        path = "/authorization/202309/shops"

        case make_api_request(:get, path, %{}) do
          {:ok, %{"data" => %{"shops" => [_ | _] = shops}}} ->
            # Take the first shop
            shop = List.first(shops)

            attrs = %{
              shop_id: shop["shop_id"],
              shop_cipher: shop["cipher"],
              shop_name: shop["shop_name"],
              shop_code: shop["code"],
              region: shop["region"]
            }

            update_auth(auth, attrs)

          {:ok, %{"data" => %{"shops" => []}}} ->
            {:error, "No authorized shops found"}

          {:ok, response} ->
            {:error, "Unexpected response: #{inspect(response)}"}

          {:error, error} ->
            {:error, error}
        end
    end
  end

  @doc """
  Makes an authenticated API request to TikTok Shop.

  Automatically handles signature generation and token refresh if needed.
  """
  def make_api_request(method, path, params \\ %{}, body \\ "") do
    case get_auth() do
      nil ->
        {:error, :no_auth_record}

      auth ->
        # Check if token is expired and refresh if needed
        auth = ensure_valid_token(auth)

        timestamp = :os.system_time(:second)

        # Build common parameters
        common_params = %{
          app_key: app_key(),
          timestamp: timestamp,
          access_token: auth.access_token
        }

        # Add shop_cipher if available and not already in params
        common_params =
          if auth.shop_cipher && !Map.has_key?(params, :shop_cipher) do
            Map.put(common_params, :shop_cipher, auth.shop_cipher)
          else
            common_params
          end

        # Merge with provided params
        all_params = Map.merge(common_params, params)

        # Generate signature
        sign = generate_signature(path, all_params, body)
        all_params = Map.put(all_params, :sign, sign)

        # Make the request
        url = "#{api_base()}#{path}"

        case method do
          :get ->
            case Req.get(url, params: all_params) do
              {:ok, %Req.Response{status: 200, body: response_body}} ->
                {:ok, response_body}

              {:ok, %Req.Response{status: status, body: response_body}} ->
                {:error, "HTTP #{status}: #{inspect(response_body)}"}

              {:error, error} ->
                {:error, "Request failed: #{inspect(error)}"}
            end

          :post ->
            case Req.post(url, json: body, params: all_params) do
              {:ok, %Req.Response{status: 200, body: response_body}} ->
                {:ok, response_body}

              {:ok, %Req.Response{status: status, body: response_body}} ->
                {:error, "HTTP #{status}: #{inspect(response_body)}"}

              {:error, error} ->
                {:error, "Request failed: #{inspect(error)}"}
            end
        end
    end
  end

  @doc """
  Generates HMAC-SHA256 signature for TikTok Shop API requests.

  The signature algorithm:
  1. Collect all parameters except 'sign' and 'access_token'
  2. Sort parameters alphabetically by key
  3. Concatenate as key1value1key2value2...
  4. Prepend the API path
  5. Append request body (if any)
  6. Wrap with app_secret at beginning and end
  7. Generate HMAC-SHA256 hash
  8. Convert to hexadecimal string
  """
  def generate_signature(path, params, body \\ "") do
    # Remove sign and access_token from params
    params =
      params
      |> Map.delete(:sign)
      |> Map.delete("sign")
      |> Map.delete(:access_token)
      |> Map.delete("access_token")

    # Sort parameters alphabetically and build string
    param_string =
      params
      |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
      |> Enum.map(fn {k, v} -> "#{k}#{v}" end)
      |> Enum.join("")

    # Build input string: secret + path + params + body + secret
    input = "#{app_secret()}#{path}#{param_string}#{body}#{app_secret()}"

    # Generate HMAC-SHA256
    :crypto.mac(:hmac, :sha256, app_secret(), input)
    |> Base.encode16(case: :lower)
  end

  ## Private Helper Functions

  defp generate_state do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp store_tokens(token_data) do
    # Calculate expiration times
    now = DateTime.utc_now()
    access_expires_in = Map.get(token_data, "access_token_expire_in", 0)
    refresh_expires_in = Map.get(token_data, "refresh_token_expire_in", 0)

    attrs = %{
      access_token: token_data["access_token"],
      refresh_token: token_data["refresh_token"],
      access_token_expires_at: DateTime.add(now, access_expires_in, :second),
      refresh_token_expires_at: DateTime.add(now, refresh_expires_in, :second)
    }

    # Upsert: if record exists, update it; otherwise create new one
    case Repo.one(Auth) do
      nil ->
        %Auth{}
        |> Auth.changeset(attrs)
        |> Repo.insert()

      existing_auth ->
        existing_auth
        |> Auth.changeset(attrs)
        |> Repo.update()
    end
  end

  defp update_tokens(auth, token_data) do
    now = DateTime.utc_now()
    access_expires_in = Map.get(token_data, "access_token_expire_in", 0)
    refresh_expires_in = Map.get(token_data, "refresh_token_expire_in", 0)

    attrs = %{
      access_token: token_data["access_token"],
      refresh_token: token_data["refresh_token"],
      access_token_expires_at: DateTime.add(now, access_expires_in, :second),
      refresh_token_expires_at: DateTime.add(now, refresh_expires_in, :second)
    }

    auth
    |> Auth.changeset(attrs)
    |> Repo.update()
  end

  defp update_auth(auth, attrs) do
    auth
    |> Auth.changeset(attrs)
    |> Repo.update()
  end

  defp get_auth do
    Repo.one(Auth)
  end

  defp ensure_valid_token(auth) do
    # Check if access token is expired or about to expire (within 5 minutes)
    now = DateTime.utc_now()
    expires_soon = DateTime.add(now, 5 * 60, :second)

    if DateTime.compare(auth.access_token_expires_at, expires_soon) == :lt do
      # Token expired or expiring soon, refresh it
      case refresh_access_token() do
        {:ok, updated_auth} -> updated_auth
        {:error, _} -> auth  # Return original if refresh fails
      end
    else
      auth
    end
  end
end
