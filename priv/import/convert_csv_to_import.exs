# Convert CSV and PDF to import format
#
# Usage:
#   mix run priv/import/convert_csv_to_import.exs <csv_path> <pdf_path> <output_folder>
#
# Example:
#   mix run priv/import/convert_csv_to_import.exs \
#     "priv/import/_temp/PAVOI HOLIDAY FAVORITES - BFCM Heroes and Bundles.csv" \
#     "priv/import/_temp/PAVOI HOLIDAY FAVORITES - BFCM Heroes and Bundles.pdf" \
#     "priv/import/bfcm-sample"

require Logger

# Parse arguments
{_opts, args, _} = OptionParser.parse(System.argv(), strict: [])

{csv_path, pdf_path, output_folder} =
  case args do
    [csv, pdf, output] ->
      {csv, pdf, output}

    _ ->
      IO.puts(:stderr, """
      Error: Missing arguments

      Usage: mix run priv/import/convert_csv_to_import.exs <csv_path> <pdf_path> <output_folder>

      Example:
        mix run priv/import/convert_csv_to_import.exs \\
          "priv/import/_temp/PAVOI HOLIDAY FAVORITES - BFCM Heroes and Bundles.csv" \\
          "priv/import/_temp/PAVOI HOLIDAY FAVORITES - BFCM Heroes and Bundles.pdf" \\
          "priv/import/bfcm-sample"
      """)

      System.halt(1)
  end

# Verify files exist
unless File.exists?(csv_path) do
  IO.puts(:stderr, "Error: CSV file not found: #{csv_path}")
  System.halt(1)
end

unless File.exists?(pdf_path) do
  IO.puts(:stderr, "Error: PDF file not found: #{pdf_path}")
  System.halt(1)
end

IO.puts("""
╔═══════════════════════════════════════════╗
║     CSV to Import Converter               ║
╚═══════════════════════════════════════════╝

CSV:    #{csv_path}
PDF:    #{pdf_path}
Output: #{output_folder}
""")

# Helper: Parse price string to cents
defmodule PriceParser do
  def parse(nil), do: nil
  def parse(""), do: nil

  def parse(price_str) when is_binary(price_str) do
    # Remove $ and whitespace, convert to float, then to cents
    price_str
    |> String.trim()
    |> String.replace("$", "")
    |> String.replace(",", "")
    |> case do
      "" -> nil
      cleaned ->
        case Float.parse(cleaned) do
          {dollars, _} -> round(dollars * 100)
          :error -> nil
        end
    end
  end

  def parse(_), do: nil
end

# Helper: Extract product name and talking points from DETAILS field
defmodule DetailsParser do
  def parse(details) when is_binary(details) do
    lines =
      details
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case lines do
      [] ->
        {"Untitled Product", ""}

      [name] ->
        {name, ""}

      [name | talking_points] ->
        {name, Enum.join(talking_points, "\n")}
    end
  end

  def parse(_), do: {"Untitled Product", ""}
end

# Step 1: Parse CSV
IO.puts("Step 1: Parsing CSV...")

# Simple CSV parser that handles quoted fields
defmodule SimpleCSV do
  def parse(content) do
    content
    |> String.split("\n")
    |> parse_rows([])
    |> Enum.reverse()
  end

  defp parse_rows([], acc), do: acc

  defp parse_rows([line | rest], acc) do
    case parse_line(line, rest) do
      {:ok, row, remaining} ->
        parse_rows(remaining, [row | acc])
      {:skip} ->
        parse_rows(rest, acc)
    end
  end

  defp parse_line(line, rest) do
    # Count quotes
    quote_count = String.graphemes(line) |> Enum.count(&(&1 == "\""))

    # If odd number of quotes, this line continues to next line
    if rem(quote_count, 2) == 1 and rest != [] do
      # Merge with next line(s) until we have matching quotes
      merge_multiline(line, rest, [])
    else
      # Parse single line
      row = split_csv_line(line)
      {:ok, row, rest}
    end
  end

  defp merge_multiline(current, [], _acc), do: {:ok, split_csv_line(current), []}

  defp merge_multiline(current, [next | rest], acc) do
    merged = current <> "\n" <> next
    quote_count = String.graphemes(merged) |> Enum.count(&(&1 == "\""))

    if rem(quote_count, 2) == 0 do
      # Found matching quote
      {:ok, split_csv_line(merged), rest}
    else
      # Keep merging
      merge_multiline(merged, rest, acc)
    end
  end

  defp split_csv_line(line) do
    # Simple regex-based CSV split (handles quoted commas)
    ~r/,(?=(?:[^"]*"[^"]*")*[^"]*$)/
    |> Regex.split(line)
    |> Enum.map(fn field ->
      field
      |> String.trim()
      |> String.trim("\"")
    end)
  end
end

csv_content = File.read!(csv_path)

products =
  csv_content
  |> SimpleCSV.parse()
  |> Enum.drop(1)  # Skip header row
  |> Enum.map(fn {row, index} ->
    # Extract fields from CSV row
    [_display_num, _pic, details, original_price, sale_price, pid, sku | _] =
      row ++ List.duplicate("", 9)

    # Parse details into name and talking points
    {name, talking_points_md} = DetailsParser.parse(details)

    # Parse prices
    original_price_cents = PriceParser.parse(original_price)
    sale_price_cents = PriceParser.parse(sale_price)

    # Build product map (use PID for image filename if available, otherwise use index)
    image_filename = if pid != "" do
      "#{String.slice(pid, 0, 50)}.jpg"
    else
      "#{index}.jpg"
    end

    %{
      name: String.slice(name, 0, 500),
      talking_points_md: talking_points_md,
      original_price_cents: original_price_cents,
      sale_price_cents: sale_price_cents,
      pid: if(pid != "", do: String.slice(pid, 0, 100), else: nil),
      sku: if(sku != "", do: String.slice(sku, 0, 100), else: nil),
      image_filename: image_filename
    }
  end)
  |> Enum.map(fn product ->
    # Set default price for products without one
    product = if is_nil(product.original_price_cents) || product.original_price_cents == 0 do
      IO.puts("  ⚠️  Product (#{product.name}) missing price, using $0.01")
      %{product | original_price_cents: 1}
    else
      product
    end
    product
  end)
  |> Enum.filter(fn product ->
    # Only keep products with valid name
    product.name != "" && product.name != "Untitled Product"
  end)

IO.puts("Found #{length(products)} valid products")

# Show first few
IO.puts("\nFirst 3 products:")

products
|> Enum.take(3)
|> Enum.each(fn p ->
  IO.puts("""
    #{p.name}
       Price: $#{p.original_price_cents / 100}#{if p.sale_price_cents, do: " → $#{p.sale_price_cents / 100}", else: ""}
       PID: #{p.pid || "N/A"}
       SKU: #{p.sku || "N/A"}
  """)
end)

# Step 2: Extract images from PDF
IO.puts("\nStep 2: Extracting images from PDF...")

# Create output folder
images_folder = Path.join(output_folder, "images")
File.mkdir_p!(images_folder)

# Use ImageMagick to convert PDF pages to images
# First, check if ImageMagick is installed
case System.cmd("magick", ["--version"], stderr_to_stdout: true) do
  {output, 0} ->
    IO.puts("✓ ImageMagick found: #{String.split(output, "\n") |> List.first()}")

    # Extract images (one per page)
    IO.puts("  Converting PDF pages to images...")

    temp_pattern = Path.join(images_folder, "page-%d.jpg")

    case System.cmd(
           "magick",
           [
             "-density",
             "300",
             # High quality
             pdf_path,
             "-quality",
             "90",
             # JPEG quality
             "-background",
             "white",
             "-alpha",
             "remove",
             # Remove transparency
             temp_pattern
           ],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        # Rename files to match display numbers
        images_folder
        |> File.ls!()
        |> Enum.filter(&String.starts_with?(&1, "page-"))
        |> Enum.sort()
        |> Enum.with_index(1)
        |> Enum.each(fn {temp_name, display_num} ->
          old_path = Path.join(images_folder, temp_name)
          new_path = Path.join(images_folder, "#{display_num}.jpg")
          File.rename!(old_path, new_path)
        end)

        image_count = File.ls!(images_folder) |> length()
        IO.puts("  ✓ Extracted #{image_count} images")

      {error, _} ->
        IO.puts(:stderr, "  ✗ Failed to extract images: #{error}")
        IO.puts(:stderr, "  Continuing without images...")
    end

  {_, _} ->
    IO.puts(:stderr, "  ✗ ImageMagick not found")
    IO.puts(:stderr, "  Install: brew install imagemagick")
    IO.puts(:stderr, "  Continuing without images...")
end

# Step 3: Generate products.json
IO.puts("\nStep 3: Generating products.json...")

sheet_name = Path.basename(csv_path, ".csv")
exported_at = DateTime.utc_now() |> DateTime.to_iso8601()

import_data = %{
  sheet_name: sheet_name,
  exported_at: exported_at,
  products: products
}

json_path = Path.join(output_folder, "products.json")
json_content = Jason.encode!(import_data, pretty: true)
File.write!(json_path, json_content)

IO.puts("✓ Created #{json_path}")

# Step 4: Summary
IO.puts("""

╔═══════════════════════════════════════════╗
║     Conversion Complete!                  ║
╚═══════════════════════════════════════════╝

Output folder: #{output_folder}
  ├── products.json (#{length(products)} products)
  └── images/ (#{File.ls!(images_folder) |> length()} images)

Next steps:
  1. Review the output:
     cat #{json_path}

  2. Preview import (dry run):
     mix run priv/import/import_products.exs #{output_folder} --dry-run

  3. Import for real:
     mix run priv/import/import_products.exs #{output_folder}

  4. Create a session:
     mix run priv/import/create_session.exs "BFCM Sample" bfcm-sample
""")
