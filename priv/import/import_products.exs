# Import products from Google Sheets export
#
# Usage:
#   mix run priv/import/import_products.exs <folder_path> [options]
#
# Options:
#   --dry-run          Preview changes without importing
#   --update-existing  Update products that already exist
#   --brand-id=N       Specify brand ID (default: auto-detect Pavoi)
#
# Examples:
#   mix run priv/import/import_products.exs priv/import/holiday-favorites
#   mix run priv/import/import_products.exs priv/import/holiday-favorites --dry-run
#   mix run priv/import/import_products.exs priv/import/holiday-favorites --update-existing --brand-id=1

alias Hudson.Import

# Parse arguments
{opts, args, _} = OptionParser.parse(
  System.argv(),
  strict: [
    dry_run: :boolean,
    update_existing: :boolean,
    brand_id: :integer
  ]
)

# Get folder path
folder_path = case args do
  [path | _] -> path
  [] ->
    IO.puts(:stderr, """
    Error: No folder path provided

    Usage: mix run priv/import/import_products.exs <folder_path> [options]

    Options:
      --dry-run          Preview changes without importing
      --update-existing  Update products that already exist
      --brand-id=N       Specify brand ID (default: auto-detect Pavoi)
    """)
    System.halt(1)
end

# Verify folder exists
unless File.dir?(folder_path) do
  IO.puts(:stderr, "Error: Folder not found: #{folder_path}")
  System.halt(1)
end

# Check for products.json
json_path = Path.join(folder_path, "products.json")
unless File.exists?(json_path) do
  IO.puts(:stderr, "Error: products.json not found in #{folder_path}")
  IO.puts(:stderr, "\nExpected structure:")
  IO.puts(:stderr, "  #{folder_path}/")
  IO.puts(:stderr, "    ├── products.json")
  IO.puts(:stderr, "    └── images/")
  System.halt(1)
end

# Display banner
IO.puts("""
╔═══════════════════════════════════════════╗
║     Hudson Product Import                 ║
╚═══════════════════════════════════════════╝

Folder: #{folder_path}
Mode:   #{if opts[:dry_run], do: "DRY RUN (preview only)", else: "LIVE IMPORT"}
""")

# Read and display data summary
case Import.read_import_data(folder_path) do
  {:ok, %{sheet_name: sheet_name, products: products, exported_at: exported_at}} ->
    IO.puts("""
    Source Sheet:  #{sheet_name}
    Exported:      #{exported_at}
    Products:      #{length(products)}
    With Images:   #{Enum.count(products, & &1.image_filename)}
    """)

    # Show first few products
    IO.puts("First 5 products:")
    products
    |> Enum.take(5)
    |> Enum.each(fn p ->
      IO.puts("  #{p.name} #{if p.image_filename, do: "📷", else: ""}")
    end)

    if length(products) > 5 do
      IO.puts("  ... and #{length(products) - 5} more")
    end

    IO.puts("")

  {:error, reason} ->
    IO.puts(:stderr, "Error reading import data: #{reason}")
    System.halt(1)
end

# Confirm before proceeding (unless dry-run)
unless opts[:dry_run] do
  IO.puts("⚠️  This will import products into your database.")
  IO.write("Continue? [y/N] ")

  case IO.gets("") |> String.trim() |> String.downcase() do
    "y" -> :ok
    _ ->
      IO.puts("Import cancelled.")
      System.halt(0)
  end

  IO.puts("")
end

# Perform import
IO.puts("Starting import...")
IO.puts("")

start_time = System.monotonic_time(:millisecond)

case Import.import_from_folder(folder_path, opts) do
  {:ok, preview: preview} ->
    # Dry run results
    IO.puts("Preview Results:")
    IO.puts("────────────────────────────────────────────")

    preview
    |> Enum.group_by(& &1.action)
    |> Enum.each(fn {action, items} ->
      IO.puts("#{action |> to_string() |> String.upcase()}: #{length(items)}")
      Enum.each(items, fn item ->
        IO.puts("  #{item.display_number}. #{item.name}")
      end)
      IO.puts("")
    end)

    IO.puts("ℹ️  This was a dry run. No changes were made.")
    IO.puts("   Run without --dry-run to import for real.")

  {:ok, %{total: total, successes: successes, failures: failures, results: results}} ->
    # Live import results
    elapsed = System.monotonic_time(:millisecond) - start_time

    IO.puts("Import Complete!")
    IO.puts("────────────────────────────────────────────")
    IO.puts("Total:      #{total}")
    IO.puts("Successful: #{successes}")
    IO.puts("Failed:     #{failures}")
    IO.puts("Time:       #{elapsed}ms")
    IO.puts("")

    # Show any failures
    failures_list = Enum.filter(results, fn {status, _} -> status == :error end)
    if length(failures_list) > 0 do
      IO.puts("Failures:")
      Enum.each(failures_list, fn {:error, reason} ->
        IO.puts("  ✗ #{reason}")
      end)
      IO.puts("")
    end

    # Show skipped
    skipped = Enum.filter(results, fn {status, _} -> status == :skipped end)
    if length(skipped) > 0 do
      IO.puts("Skipped #{length(skipped)} existing products")
      IO.puts("(Use --update-existing to update them)")
      IO.puts("")
    end

    if successes > 0 do
      IO.puts("✅ Successfully imported #{successes} product(s)!")
      IO.puts("")
      IO.puts("Next steps:")
      IO.puts("  1. Visit http://localhost:4000/products/upload to add more images")
      IO.puts("  2. Create a session:")
      IO.puts("     mix run priv/import/create_session.exs \"Session Name\" session-slug")
    end

  {:error, {:validation_failed, errors}} ->
    IO.puts(:stderr, "Validation Failed:")
    IO.puts(:stderr, "────────────────────────────────────────────")
    Enum.each(errors, fn {:error, line, message} ->
      IO.puts(:stderr, "  Line #{line}: #{message}")
    end)
    System.halt(1)

  {:error, reason} ->
    IO.puts(:stderr, "Import failed: #{inspect(reason)}")
    System.halt(1)
end
