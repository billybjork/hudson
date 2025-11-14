# Create a session from imported products
#
# Usage:
#   mix run priv/import/create_session.exs <session_name> <slug> [options]
#
# Options:
#   --brand-id=N  Specify brand ID (default: 1)
#
# Examples:
#   mix run priv/import/create_session.exs "Holiday Favorites" holiday-favorites
#   mix run priv/import/create_session.exs "BFCM 2024" bfcm-2024

alias Hudson.{Repo, Sessions, Catalog}
alias Hudson.Catalog.Product

# Parse arguments
{opts, args, _} = OptionParser.parse(
  System.argv(),
  strict: [
    brand_id: :integer
  ]
)

# Get session name and slug
{session_name, slug} = case args do
  [name, slug | _] -> {name, slug}
  _ ->
    IO.puts(:stderr, """
    Error: Missing arguments

    Usage: mix run priv/import/create_session.exs <session_name> <slug> [options]

    Examples:
      mix run priv/import/create_session.exs "Holiday Favorites" holiday-favorites
      mix run priv/import/create_session.exs "BFCM 2024" bfcm-2024
    """)
    System.halt(1)
end

# Parse options
brand_id = opts[:brand_id] || 1

# Display banner
IO.puts("""
╔═══════════════════════════════════════════╗
║     Hudson Session Creator                ║
╚═══════════════════════════════════════════╝

Session Name: #{session_name}
Slug:         #{slug}
Brand ID:     #{brand_id}
""")

# Get products for this brand
import Ecto.Query

products = from(p in Product,
  where: p.brand_id == ^brand_id,
  preload: [:product_images])
|> Repo.all()

if Enum.empty?(products) do
  IO.puts(:stderr, "Error: No products found for brand ID #{brand_id}")
  System.halt(1)
end

IO.puts("Found #{length(products)} product(s):")
products
|> Enum.take(10)
|> Enum.each(fn p ->
  image_count = length(p.product_images)
  IO.puts("  #{p.name} (#{image_count} image#{if image_count != 1, do: "s", else: ""})")
end)

if length(products) > 10 do
  IO.puts("  ... and #{length(products) - 10} more")
end

IO.puts("")

# Confirm
IO.write("Create this session? [y/N] ")

case IO.gets("") |> String.trim() |> String.downcase() do
  "y" -> :ok
  _ ->
    IO.puts("Session creation cancelled.")
    System.halt(0)
end

IO.puts("")

# Create session
IO.puts("Creating session...")

case Sessions.create_session(%{
  brand_id: brand_id,
  name: session_name,
  slug: slug,
  notes: "Created by import script"
}) do
  {:ok, session} ->
    IO.puts("✓ Session created (ID: #{session.id})")

    # Add products to session
    IO.puts("Adding products to session...")

    session_products = products
    |> Enum.with_index(1)
    |> Enum.map(fn {product, position} ->
      case Sessions.add_product_to_session(session.id, product.id, %{position: position}) do
        {:ok, sp} ->
          IO.puts("  ✓ #{position}. #{product.name}")
          sp
        {:error, reason} ->
          IO.puts(:stderr, "  ✗ Failed to add product #{product.id}: #{inspect(reason)}")
          nil
      end
    end)
    |> Enum.filter(& !is_nil(&1))

    # Initialize session state to first product
    if length(session_products) > 0 do
      first_sp = List.first(session_products)

      case Sessions.initialize_session_state(session.id) do
        {:ok, _state} ->
          IO.puts("✓ Session state initialized to first product")
        {:error, reason} ->
          IO.puts(:stderr, "Warning: Could not initialize state: #{inspect(reason)}")
      end
    end

    IO.puts("")
    IO.puts("═══════════════════════════════════════════")
    IO.puts("✅ Session created successfully!")
    IO.puts("═══════════════════════════════════════════")
    IO.puts("")
    IO.puts("Session ID:    #{session.id}")
    IO.puts("Products:      #{length(session_products)}")
    IO.puts("View at:       http://localhost:4000/sessions/#{session.id}/producer")
    IO.puts("")

  {:error, changeset} ->
    IO.puts(:stderr, "Failed to create session:")
    IO.puts(:stderr, inspect(changeset.errors, pretty: true))
    System.halt(1)
end
