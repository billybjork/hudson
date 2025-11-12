# Hudson Product Import Guide

This directory contains tools for importing products from Google Sheets into Hudson.

## Quick Start

### 1. Extract Data from Google Sheets

1. Open your Google Sheet with product data
2. Go to **Extensions → Apps Script**
3. Delete any existing code
4. Copy and paste the contents of `extract_sheets_images.gs`
5. Save (Ctrl+S / Cmd+S)
6. Run the function: `extractImagesAndData`
7. Grant permissions when prompted
8. Wait for completion (check progress in Execution log)
9. A folder will be created in your Google Drive with:
   - `products.json` (product data)
   - `images/` folder (extracted images)
   - `README.txt` (instructions)

### 2. Download and Import

```bash
# Download the folder from Google Drive
# Extract to your Hudson project
cd /path/to/hudson

# Import products
mix run priv/import/import_products.exs /path/to/import/folder

# Create a session
mix run priv/import/create_session.exs "Session Name" session-slug
```

---

## Detailed Workflow

### Step 1: Prepare Your Google Sheet

Your sheet should have these columns:

- `#` - Product display number (1, 2, 3, ...)
- `PIC` - Product image (embedded in cell)
- `DETAILS/TALKING POINTS` - Product description and talking points
- `ORIGINAL PRICE` - Original price (e.g., "$49.95" or "49.95")
- `SALE PRICE` - Sale price (optional)
- `PID` - Product ID (TikTok Shop ID, etc.)
- `PAVOI SKU` - Internal SKU code
- `STOCK` - Stock count (optional)

Example:

| # | PIC | DETAILS/TALKING POINTS | ORIGINAL PRICE | SALE PRICE | PID | PAVOI SKU | STOCK |
|---|-----|------------------------|----------------|------------|-----|-----------|-------|
| 1 | 🖼️ | Tennis Bracelet<br>- 3mm CZ stones<br>- Hypoallergenic | $49.95 | $29.99 | 173... | TB-001 | 150 |

### Step 2: Extract with Apps Script

**Why?** Google Sheets doesn't allow direct image export. The Apps Script extracts both data and images.

**What it does:**
- Reads all product data from the sheet
- Extracts images from cells
- Downloads images to Google Drive
- Creates a JSON file with product metadata
- Packages everything in a downloadable folder

**Running the script:**

```javascript
// In Apps Script editor
extractImagesAndData()
```

**Output structure:**
```
Hudson_Import_[SheetName]_[Timestamp]/
├── products.json          # Product data
├── images/               # Extracted images
│   ├── 1.jpg
│   ├── 2.jpg
│   └── 3.jpg
└── README.txt           # Import instructions
```

### Step 3: Import Products

**Preview first (dry run):**
```bash
mix run priv/import/import_products.exs priv/import/holiday-favorites --dry-run
```

This shows what will be imported without making changes.

**Import for real:**
```bash
mix run priv/import/import_products.exs priv/import/holiday-favorites
```

**Options:**
- `--dry-run` - Preview changes without importing
- `--update-existing` - Update products that already exist (default: skip)
- `--brand-id=N` - Specify brand ID (default: auto-detect "Pavoi")

**What happens:**
1. Validates `products.json` structure
2. Shows summary and asks for confirmation
3. Creates products in database
4. Uploads images to Supabase (full + thumbnail)
5. Creates ProductImage records
6. Shows detailed results

### Step 4: Create Session

```bash
mix run priv/import/create_session.exs "Holiday Favorites - Dec 2024" holiday-dec-2024
```

**Options:**
- `--brand-id=N` - Brand ID to pull products from (default: 1)
- `--duration=N` - Session duration in minutes (default: 180)
- `--display-numbers=1,2,3` - Only include specific products
- `--scheduled-at="2024-12-15T18:00:00"` - Schedule time

**Examples:**

```bash
# Create session with all products from brand 1
mix run priv/import/create_session.exs "Holiday Stream" holiday-stream

# Create session with only products 1-10
mix run priv/import/create_session.exs "Top 10 Products" top-10 \
  --display-numbers=1,2,3,4,5,6,7,8,9,10

# Create 4-hour session scheduled for tomorrow at 6pm
mix run priv/import/create_session.exs "Extended Stream" extended \
  --duration=240 \
  --scheduled-at="2024-12-15T18:00:00"
```

### Step 5: Start Streaming

```bash
# Start Phoenix server
mix phx.server

# Open session
open http://localhost:4000/sessions/2/producer
```

**Keyboard shortcuts:**
- Type number (e.g., "23") + Enter → Jump to product 23
- ↑/↓ arrows or J/K → Previous/next product
- ←/→ arrows or H/L → Previous/next image
- Home → First product
- End → Last product
- Space → Next product

---

## Manual Image Upload

To add more images to existing products:

1. Visit http://localhost:4000/products/upload
2. Select product from dropdown
3. Drag and drop images (up to 5 at once)
4. Images are uploaded in order: first becomes position 0, second becomes position 1, etc.

**Image handling:**
- Full-size image uploaded to: `{product_id}/full/{position}.jpg`
- Thumbnail (20px wide, blurred) uploaded to: `{product_id}/thumb/{position}.jpg`
- Both stored in Supabase Storage → `products` bucket

---

## Troubleshooting

### Google Apps Script Issues

**"Image file not found"**
- Images might be stored as formulas or drawings
- Try re-inserting images using Insert → Image → Upload

**"Permission denied"**
- Click "Advanced" → "Go to Untitled project (unsafe)"
- Grant access to Google Drive and Sheets

**Script times out**
- Large sheets may timeout (6 min limit)
- Solution: Split into multiple sheets or reduce image count

### Import Issues

**"products.json not found"**
- Check folder structure
- Ensure you extracted the ZIP correctly

**"Brand with ID X not found"**
- Use `--brand-id=1` or create brand first

**"Upload failed: Authentication error"**
- Check `.env` file has correct `SUPABASE_SERVICE_ROLE_KEY`
- Verify bucket is named "products" and set as public

**"Thumbnail generation failed"**
- Check ImageMagick is installed: `magick --version`
- Install: `brew install imagemagick` (macOS)
- Import continues with full image as fallback

### Session Issues

**"Session not found"**
- Check session ID in URL: `/sessions/2/producer` or `/sessions/2/host`
- List sessions: `Hudson.Sessions.list_sessions() |> Hudson.Repo.all()`

**Images show as 404**
- Check Supabase bucket exists and is public
- Verify `SUPABASE_STORAGE_PUBLIC_URL` in `.env`
- Check ProductImage records have correct paths

---

## File Reference

| File | Purpose |
|------|---------|
| `extract_sheets_images.gs` | Google Apps Script for extraction |
| `import_products.exs` | Command-line import script |
| `create_session.exs` | Session creation helper |
| `lib/hudson/import.ex` | Core import logic module |

---

## Data Flow

```
Google Sheet
    ↓ (Apps Script)
products.json + images/
    ↓ (import_products.exs)
Database (products + product_images)
    +
Supabase Storage (full + thumbnails)
    ↓ (create_session.exs)
Session + SessionProducts + SessionState
    ↓ (mix phx.server)
Host View @ /sessions/:id/host
Producer Console @ /sessions/:id/producer
```

---

## Tips & Best Practices

### Image Quality
- Use high-res images (min 1000px width) for best results
- JPEG recommended for photos, PNG for graphics
- Keep file sizes under 5MB for fast uploads

### Talking Points
- Use markdown format for better rendering:
  ```
  - Bullet point 1
  - **Bold for emphasis**
  - *Italic for notes*
  ```

### Organization
- Use consistent naming: `BRAND-EVENT-DATE` (e.g., `pavoi-bfcm-2024`)
- Keep imports in dated folders: `priv/import/2024-12-01-holiday/`
- Document changes in session notes

### Performance
- Import products in batches of 20-30 for faster processing
- Use `--dry-run` first to catch errors early
- Upload additional images via UI (faster than re-importing)

---

## Need Help?

- Check implementation guide: `docs/implementation_guide.md`
- Review architecture: `docs/architecture.md`
- Check logs: Look for error messages during import
- Test in iex: `iex -S mix` then `Hudson.Import.read_import_data("path")`

---

## Example: Complete Workflow

```bash
# 1. Extract from Google Sheet (in browser)
# → Run extract_sheets_images.gs
# → Download folder from Drive

# 2. Move to project
cd ~/Downloads
mv Hudson_Import_* ~/hudson/priv/import/holiday-bfcm/

# 3. Preview import
cd ~/hudson
mix run priv/import/import_products.exs priv/import/holiday-bfcm --dry-run

# 4. Import products
mix run priv/import/import_products.exs priv/import/holiday-bfcm

# 5. Create session
mix run priv/import/create_session.exs "BFCM Heroes 2024" bfcm-2024

# 6. Start server and test
mix phx.server
open http://localhost:4000/sessions/2/producer

# 7. Upload more images (optional)
open http://localhost:4000/products/upload
```

Done! 🎉
