defmodule PavoiWeb.TiktokShopController do
  @moduledoc """
  Handles TikTok Shop OAuth callbacks and API operations.
  """
  use PavoiWeb, :controller

  alias Pavoi.TiktokShop

  @doc """
  OAuth callback handler.
  Called when TikTok redirects back after user authorization.
  Exchanges the authorization code for access tokens and fetches shop information.
  """
  def callback(conn, %{"code" => auth_code} = _params) do
    case TiktokShop.exchange_code_for_token(auth_code) do
      {:ok, _auth} ->
        # After getting the access token, fetch the authorized shops
        case TiktokShop.get_authorized_shops() do
          {:ok, auth} ->
            conn
            |> put_flash(
              :info,
              "Successfully connected to TikTok Shop: #{auth.shop_name || auth.shop_id}"
            )
            |> redirect(to: "/")

          {:error, error} ->
            conn
            |> put_flash(:error, "Failed to get shop information: #{inspect(error)}")
            |> redirect(to: "/")
        end

      {:error, error} ->
        conn
        |> put_flash(:error, "Authorization failed: #{inspect(error)}")
        |> redirect(to: "/")
    end
  end

  def callback(conn, params) do
    # If there's an error in the OAuth flow
    error = Map.get(params, "error", "Unknown error")
    error_description = Map.get(params, "error_description", "")

    conn
    |> put_flash(:error, "TikTok Shop authorization error: #{error} - #{error_description}")
    |> redirect(to: "/")
  end

  @doc """
  Test endpoint to verify TikTok Shop API is working.
  Makes a simple API call to get shop information.
  """
  def test(conn, _params) do
    case TiktokShop.make_api_request(:get, "/authorization/202309/shops", %{}) do
      {:ok, response} ->
        json(conn, %{success: true, data: response})

      {:error, error} ->
        conn
        |> put_status(500)
        |> json(%{success: false, error: inspect(error)})
    end
  end
end
