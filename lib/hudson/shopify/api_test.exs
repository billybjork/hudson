defmodule Hudson.Shopify.ApiTest do
  @moduledoc """
  Quick test module to verify Shopify GraphQL API connectivity and explore available data.

  Usage in iex:
    iex -S mix
    Hudson.Shopify.ApiTest.test_connectivity()
    Hudson.Shopify.ApiTest.fetch_sample_products()
  """

  def test_connectivity do
    IO.puts("Testing Shopify API connectivity...")

    case make_request(simple_query()) do
      {:ok, response} ->
        IO.puts("\n✅ Connected! Response:")
        IO.inspect(response, pretty: true, limit: :infinity)
        {:ok, response}

      {:error, reason} ->
        IO.puts("\n❌ Error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def fetch_sample_products do
    IO.puts("Fetching sample products from Shopify...")

    case make_request(products_query()) do
      {:ok, %{"data" => %{"products" => %{"nodes" => products}}}} ->
        IO.puts("\n✅ Found #{length(products)} products. First product:")
        IO.inspect(List.first(products), pretty: true, limit: :infinity)
        {:ok, products}

      {:ok, response} ->
        IO.puts("\n⚠️  Got response but unexpected structure:")
        IO.inspect(response, pretty: true, limit: :infinity)
        {:ok, response}

      {:error, reason} ->
        IO.puts("\n❌ Error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def check_rate_limits do
    IO.puts("Checking rate limit status...")

    case make_request(rate_limit_query()) do
      {:ok, %{"extensions" => %{"cost" => cost_info}}} ->
        IO.puts("\n✅ Rate limit info:")
        IO.inspect(cost_info, pretty: true)
        {:ok, cost_info}

      {:ok, response} ->
        IO.puts("\n⚠️  Got response but no cost info:")
        IO.inspect(response, pretty: true, limit: :infinity)
        {:ok, response}

      {:error, reason} ->
        IO.puts("\n❌ Error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ============================================================================
  # GraphQL Queries
  # ============================================================================

  defp simple_query do
    """
    {
      shop {
        name
        primaryDomain {
          url
        }
      }
    }
    """
  end

  defp products_query do
    """
    {
      products(first: 5) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          id
          title
          handle
          vendor
          productType
          tags
          descriptionHtml
          createdAt
          updatedAt
          variants(first: 3) {
            nodes {
              id
              title
              price
              compareAtPrice
              sku
              barcode
              inventoryQuantity
              selectedOptions {
                name
                value
              }
            }
          }
          images(first: 3) {
            nodes {
              id
              url
              altText
              height
              width
            }
          }
        }
      }
    }
    """
  end

  defp rate_limit_query do
    """
    {
      products(first: 1) {
        nodes {
          id
          title
        }
      }
    }
    """
  end

  # ============================================================================
  # HTTP Request Handling
  # ============================================================================

  defp make_request(query) do
    token = Application.get_env(:hudson, :shopify_access_token)
    store = Application.get_env(:hudson, :shopify_store_name)

    if !token || token == "your_access_token_here" do
      {:error,
       "SHOPIFY_ACCESS_TOKEN not configured in .env. Please add your token and restart iex."}
    else
      if !store || store == "your-store-name" do
        {:error,
         "SHOPIFY_STORE_NAME not configured in .env. Please add your store name and restart iex."}
      else
        endpoint = "https://#{store}.myshopify.com/admin/api/2025-10/graphql.json"

        headers = [
          {"X-Shopify-Access-Token", token},
          {"Content-Type", "application/json"}
        ]

        body = Jason.encode!(%{query: query})

        case HTTPoison.post(endpoint, body, headers) do
          {:ok, %{status_code: 200, body: response_body}} ->
            Jason.decode(response_body)

          {:ok, %{status_code: 429}} ->
            {:error, "Rate limited (429). Wait before retrying."}

          {:ok, %{status_code: 401}} ->
            {:error, "Unauthorized (401). Check SHOPIFY_ACCESS_TOKEN."}

          {:ok, %{status_code: 403}} ->
            {:error, "Forbidden (403). Check scopes - need 'read_products' at minimum."}

          {:ok, %{status_code: code, body: response_body}} ->
            {:error, "HTTP #{code}: #{response_body}"}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end
end
