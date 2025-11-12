# Script for populating the database with sample data for Hudson
# Run with: mix run priv/repo/seeds.exs

alias Hudson.{Repo, Catalog, Sessions}
alias Hudson.Catalog.{Brand, Product, ProductImage}
alias Hudson.Sessions.{Session, SessionProduct, SessionState}

# Clean existing data (be careful in production!)
IO.puts("Cleaning existing data...")
Repo.delete_all(SessionState)
Repo.delete_all(SessionProduct)
Repo.delete_all(Session)
Repo.delete_all(ProductImage)
Repo.delete_all(Product)
Repo.delete_all(Brand)

IO.puts("Creating brand...")

# Create Pavoi brand
{:ok, pavoi} =
  Catalog.create_brand(%{
    name: "Pavoi",
    slug: "pavoi",
    notes: "Premium jewelry brand specializing in affordable luxury"
  })

IO.puts("Created brand: #{pavoi.name}")

IO.puts("Creating products...")

# Create sample products
products_data = [
  %{
    display_number: 1,
    name: "CZ Lariat Station Necklace - Gold",
    talking_points_md: """
    - High-quality cubic zirconia stones that sparkle like diamonds
    - Adjustable lariat style for perfect fit
    - Perfect for layering with other necklaces
    - Tarnish-free 14K gold plating lasts for years
    - Best seller - limited stock available
    """,
    original_price_cents: 4999,
    sale_price_cents: 2999,
    pid: "TT12345",
    sku: "NECK-001",
    stock: 150,
    tags: ["necklace", "gold", "holiday", "bestseller"]
  },
  %{
    display_number: 2,
    name: "Tennis Bracelet - Rose Gold",
    talking_points_md: """
    - Classic tennis bracelet design with modern rose gold finish
    - 50 brilliant-cut cubic zirconia stones
    - Secure box clasp with safety latch
    - Hypoallergenic - safe for sensitive skin
    - Perfect gift for any occasion
    """,
    original_price_cents: 5999,
    sale_price_cents: 3499,
    pid: "TT12346",
    sku: "BRAC-001",
    stock: 85,
    tags: ["bracelet", "rose-gold", "tennis", "gift"]
  },
  %{
    display_number: 3,
    name: "Huggie Hoop Earrings - Silver",
    talking_points_md: """
    - Small huggie hoops perfect for everyday wear
    - 925 sterling silver - authentic quality
    - Comfortable lightweight design
    - Secure click closure
    - Great for stacking with other earrings
    """,
    original_price_cents: 3499,
    sale_price_cents: 1999,
    pid: "TT12347",
    sku: "EAR-001",
    stock: 200,
    tags: ["earrings", "silver", "hoops", "everyday"]
  },
  %{
    display_number: 4,
    name: "Infinity Symbol Ring - White Gold",
    talking_points_md: """
    - Beautiful infinity symbol represents eternal love
    - Elegant white gold finish
    - Comfortable band width
    - Available in sizes 5-10
    - Makes a meaningful gift
    """,
    original_price_cents: 3999,
    sale_price_cents: 2499,
    pid: "TT12348",
    sku: "RING-001",
    stock: 120,
    tags: ["ring", "white-gold", "infinity", "symbolic"]
  },
  %{
    display_number: 5,
    name: "Pearl Drop Earrings - Gold",
    talking_points_md: """
    - Freshwater pearl drops with 14K gold posts
    - Classic elegant style
    - Perfect for formal occasions
    - Lightweight and comfortable
    - Comes with storage pouch
    """,
    original_price_cents: 4499,
    sale_price_cents: 2799,
    pid: "TT12349",
    sku: "EAR-002",
    stock: 95,
    tags: ["earrings", "pearl", "gold", "formal"]
  },
  %{
    display_number: 6,
    name: "Chain Link Bracelet - Gold",
    talking_points_md: """
    - Bold chain link design
    - 18K gold vermeil finish
    - Adjustable length 7-8 inches
    - Statement piece that stands out
    - Trending style right now
    """,
    original_price_cents: 5499,
    sale_price_cents: 3299,
    pid: "TT12350",
    sku: "BRAC-002",
    stock: 65,
    tags: ["bracelet", "gold", "chain", "trending"]
  },
  %{
    display_number: 7,
    name: "Stud Earrings Set - Mixed Metals",
    talking_points_md: """
    - Set of 3 pairs in gold, silver, and rose gold
    - Perfect for everyday mixing and matching
    - Secure butterfly backs
    - Hypoallergenic posts
    - Amazing value - 3 pairs for the price of 1
    """,
    original_price_cents: 2999,
    sale_price_cents: 1999,
    pid: "TT12351",
    sku: "EAR-003",
    stock: 175,
    tags: ["earrings", "set", "mixed-metals", "value"]
  },
  %{
    display_number: 8,
    name: "Pendant Necklace - Heart Design",
    talking_points_md: """
    - Delicate heart pendant with CZ accent
    - 16-18 inch adjustable chain
    - Perfect for Valentine's Day or anniversaries
    - Comes in beautiful gift box
    - Made to last a lifetime
    """,
    original_price_cents: 3999,
    sale_price_cents: 2499,
    pid: "TT12352",
    sku: "NECK-002",
    stock: 110,
    tags: ["necklace", "heart", "pendant", "romantic"]
  }
]

products =
  Enum.map(products_data, fn product_attrs ->
    attrs = Map.put(product_attrs, :brand_id, pavoi.id)
    {:ok, product} = Catalog.create_product(attrs)

    # Add placeholder images for each product
    # In real use, these would be actual Supabase storage paths
    image_paths = [
      "#{product.id}/image-1.jpg",
      "#{product.id}/image-2.jpg",
      "#{product.id}/image-3.jpg"
    ]

    Enum.with_index(image_paths, fn path, idx ->
      Catalog.create_product_image(%{
        product_id: product.id,
        path: path,
        position: idx,
        is_primary: idx == 0,
        alt_text: "#{product.name} - View #{idx + 1}"
      })
    end)

    IO.puts("Created product #{product.display_number}: #{product.name}")
    product
  end)

IO.puts("Creating session...")

# Create a sample session
{:ok, session} =
  Sessions.create_session(%{
    brand_id: pavoi.id,
    name: "Holiday Favorites - December 2024",
    slug: "holiday-favorites-dec-2024",
    scheduled_at: ~N[2024-12-15 18:00:00],
    duration_minutes: 180,
    status: "draft",
    notes: "Holiday season kickoff stream"
  })

IO.puts("Created session: #{session.name}")

IO.puts("Adding products to session...")

# Add all products to the session
session_products =
  products
  |> Enum.with_index(1)
  |> Enum.map(fn {product, position} ->
    {:ok, sp} =
      Sessions.add_product_to_session(session.id, product.id, %{
        position: position
      })

    IO.puts("  Added product #{position}: #{product.name}")
    sp
  end)

IO.puts("Initializing session state...")

# Initialize session state to first product
first_sp = List.first(session_products)

{:ok, _state} =
  Repo.insert(%SessionState{
    session_id: session.id,
    current_session_product_id: first_sp.id,
    current_image_index: 0,
    updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
  })

IO.puts("\n✅ Seed data created successfully!")
IO.puts("\nYou can now:")
IO.puts("  1. Start the server: mix phx.server")
IO.puts("  2. Visit the session: http://localhost:4000/sessions/#{session.id}/run")
IO.puts("\nKeyboard shortcuts:")
IO.puts("  - Type a number (1-8) and press Enter to jump to that product")
IO.puts("  - ↑/↓ arrows for previous/next product (convenience)")
IO.puts("  - ←/→ arrows for previous/next image")
IO.puts("  - Home/End for first/last product")
