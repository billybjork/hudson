# Implementation Guide

This guide tracks implementation progress and provides instructions for remaining features.

## Implementation Status

### ✅ Completed (Core MVP)

- [x] **Project Setup** - Phoenix 1.8 with LiveView, no Tailwind
- [x] **Database Configuration** - Supabase support with SSL/TLS, local PostgreSQL fallback
- [x] **Dependencies** - supabase_potion, earmark, bcrypt_elixir, castore
- [x] **Domain Model** - All schemas and migrations (brands, products, product_images, sessions, session_products, session_states)
- [x] **Contexts** - Catalog and Sessions contexts with CRUD operations
- [x] **SessionRunLive** - Core LiveView with real-time state sync
- [x] **Template** - Dark theme UI optimized for live streaming (3-foot viewing distance)
- [x] **Keyboard Navigation** - JS hooks for hands-free control (direct jump + arrow keys)
- [x] **State Management** - PubSub broadcasting, URL persistence, temporary assigns
- [x] **Seed Data** - 8 sample products with talking points

### 🚧 In Progress / Next Steps

- [ ] **Supabase Storage** - Image upload with public read access (§1)
- [ ] **LQIP Image Loading** - Thumbnail generation, smooth transitions (§2)
- [ ] **CSV Import** - Bulk product import with validation (§3)
- [ ] **Testing** - Context and LiveView tests (§4)

### 📦 Post-MVP Features

- [ ] **Authentication Gate** - Hash shared secrets, session tokens, rate limiting (§5)
- [ ] **Production Deployment** - Windows service, desktop packaging (§6)

---

## 1. Supabase Storage Integration

**Status:** Configuration ready, upload functionality not implemented
**Priority:** High for MVP

### MVP Approach (No Authentication)

Since Hudson is used locally by internal team only, we're skipping authentication for MVP. This simplifies the storage setup:

- **Public read access** - No RLS policies needed
- **Service role for writes** - Upload images using SUPABASE_SERVICE_ROLE_KEY
- **Simple bucket permissions** - Single "products" bucket with public visibility

### 1.1 Create Storage Bucket

In Supabase Dashboard:
1. Navigate to Storage → Create bucket
2. Bucket name: `products`
3. Set as **Public bucket** (toggle on)
4. Click "Create bucket"

### 1.2 Verify Bucket Configuration

No RLS policies needed since bucket is public. All images will be publicly readable via:
```
https://[project-ref].supabase.co/storage/v1/object/public/products/[path]
```

### 1.3 Upload Implementation

Create `lib/hudson/media.ex`:

```elixir
defmodule Hudson.Media do
  @moduledoc """
  Media upload and management for product images.
  Uses Supabase Storage with service role for uploads.
  """

  alias Supabase.Storage

  @storage_public_url Application.compile_env(:hudson, :storage_public_url)

  def upload_product_image(file_path, product_id, position) do
    client = build_client()

    # Upload full-size image
    full_path = "#{product_id}/full/#{position}.jpg"

    with {:ok, file_binary} <- File.read(file_path),
         {:ok, _response} <- Storage.upload(client, "products", full_path, file_binary, [
           content_type: "image/jpeg",
           upsert: true
         ]) do
      # Generate and upload thumbnail
      case generate_and_upload_thumbnail(client, file_path, product_id, position) do
        {:ok, thumb_path} ->
          {:ok, %{path: full_path, thumbnail_path: thumb_path}}

        {:error, _reason} ->
          # If thumbnail fails, still return success with full image
          {:ok, %{path: full_path, thumbnail_path: full_path}}
      end
    end
  end

  defp generate_and_upload_thumbnail(client, source_file, product_id, position) do
    # Generate 20px wide thumbnail with blur
    thumb_tmp = System.tmp_dir!() <> "/thumb_#{product_id}_#{position}.jpg"

    # Using ImageMagick convert command
    case System.cmd("convert", [
      source_file,
      "-resize", "20x",
      "-quality", "50",
      "-blur", "0x2",
      thumb_tmp
    ]) do
      {_, 0} ->
        thumb_path = "#{product_id}/thumb/#{position}.jpg"

        with {:ok, thumb_binary} <- File.read(thumb_tmp),
             {:ok, _response} <- Storage.upload(client, "products", thumb_path, thumb_binary, [
               content_type: "image/jpeg",
               upsert: true
             ]) do
          File.rm(thumb_tmp)
          {:ok, thumb_path}
        end

      _ ->
        {:error, :thumbnail_generation_failed}
    end
  end

  def public_image_url(path) when is_binary(path) do
    "#{@storage_public_url}/products/#{path}"
  end

  def public_image_url(_), do: "/images/placeholder.png"

  defp build_client do
    Supabase.init_client!(
      Application.fetch_env!(:hudson, :supabase_url),
      Application.fetch_env!(:hudson, :supabase_service_role_key)
    )
  end
end
```

**Note:** This implementation requires ImageMagick installed locally:
```bash
# macOS
brew install imagemagick

# Ubuntu/Debian
apt-get install imagemagick
```

### 1.4 Update Seeds for Testing

After uploading real images, update `priv/repo/seeds.exs` to use actual paths instead of placeholders.

---

## 2. LQIP Image Loading Pattern

**Status:** Basic placeholders implemented, LQIP pattern not complete
**Priority:** High for production (improves perceived performance)

### Current Implementation

Basic image display with placeholder URLs:
```elixir
# lib/hudson_web/live/session_run_live.ex:255-260
def public_image_url(path) when is_binary(path) do
  base_url = Application.get_env(:hudson, :storage_public_url, "")
  "#{base_url}/products/#{path}"
end
```

### Remaining Work

#### 2.1 Generate Thumbnails

Create helper to generate low-quality placeholders:

```elixir
# lib/hudson/media.ex
defmodule Hudson.Media do
  @storage_public_url Application.fetch_env!(:hudson, :storage_public_url)

  def generate_thumbnail(source_path, output_path, width \\ 20) do
    # Using ImageMagick or similar
    System.cmd("convert", [
      source_path,
      "-resize", "#{width}x",
      "-quality", "50",
      "-blur", "0x2",
      output_path
    ])
  end

  def upload_with_thumbnail(file_path, product_id) do
    # Upload full-size image
    full_path = upload_to_supabase(file_path, "products/#{product_id}/full/")

    # Generate and upload thumbnail
    thumb_tmp_path = generate_thumbnail_path(file_path)
    generate_thumbnail(file_path, thumb_tmp_path)
    thumb_storage_path = upload_to_supabase(thumb_tmp_path, "products/#{product_id}/thumb/")

    {:ok, %{full_path: full_path, thumb_path: thumb_storage_path}}
  end

  def public_image_url(path) do
    URI.merge(@storage_public_url <> "/", path)
    |> URI.to_string()
  end
end
```

#### 2.2 LQIP Component

```elixir
# lib/hudson_web/components/image_components.ex
defmodule HudsonWeb.ImageComponents do
  use Phoenix.Component

  attr :src, :string, required: true
  attr :thumb_src, :string, required: true
  attr :alt, :string, default: ""
  attr :class, :string, default: ""
  attr :id, :string, required: true

  def lqip_image(assigns) do
    ~H"""
    <div class={"lqip-container #{@class}"}>
      <!-- Skeleton loader -->
      <div id={"skeleton-#{@id}"} class="lqip-skeleton" />

      <!-- Low-quality placeholder -->
      <img
        id={"placeholder-#{@id}"}
        class="lqip-placeholder"
        src={@thumb_src}
        alt=""
        aria-hidden="true"
      />

      <!-- High-quality image -->
      <img
        id={@id}
        class="lqip-image"
        src={@src}
        alt={@alt}
        loading="lazy"
        phx-hook="ImageLoadingState"
        data-js-loading="true"
      />
    </div>
    """
  end
end
```

#### 2.3 LQIP CSS

Add to `assets/css/app.css`:

```css
/* LQIP Image Loading */
.lqip-container {
  position: relative;
  width: 100%;
  height: 100%;
}

.lqip-image {
  width: 100%;
  height: 100%;
  object-fit: contain;
  filter: blur(20px);
  transform: scale(1.05);
  opacity: 0;
  transition:
    filter 0.8s ease-out,
    transform 0.8s ease-out,
    opacity 0.8s ease-out;
}

.lqip-image[data-js-loading="false"] {
  filter: blur(0);
  transform: scale(1);
  opacity: 1;
}

.lqip-placeholder {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  width: 100%;
  height: 100%;
  object-fit: contain;
  opacity: 1;
  transition: opacity 0.8s ease-out;
  filter: blur(20px);
  transform: scale(1.05);
}

.lqip-placeholder[data-js-placeholder-loaded="true"] {
  opacity: 0;
  pointer-events: none;
}

.lqip-skeleton {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: linear-gradient(
    90deg,
    var(--bg-medium) 25%,
    var(--bg-light) 50%,
    var(--bg-medium) 75%
  );
  background-size: 200% 100%;
  animation: loading 1.5s infinite;
}

@keyframes loading {
  0% { background-position: 200% 0; }
  100% { background-position: -200% 0; }
}
```

#### 2.4 Image Loading Hook

Add to `assets/js/hooks.js`:

```javascript
Hooks.ImageLoadingState = {
  mounted() {
    const mainImage = this.el
    const placeholderId = `placeholder-${mainImage.id}`
    const skeletonId = `skeleton-${mainImage.id}`
    const placeholder = document.getElementById(placeholderId)
    const skeleton = document.getElementById(skeletonId)

    // Handle main image load
    const handleLoad = () => {
      mainImage.setAttribute('data-js-loading', 'false')
      if (placeholder) {
        placeholder.setAttribute('data-js-placeholder-loaded', 'true')
      }
      this.pushEvent("image_loaded", {id: mainImage.id})
    }

    mainImage.addEventListener('load', handleLoad)

    // Handle placeholder load (hide skeleton)
    if (placeholder) {
      placeholder.addEventListener('load', () => {
        if (skeleton) skeleton.style.display = 'none'
      })
    }

    // Trigger load if already cached
    if (mainImage.complete) {
      handleLoad()
    }
  },

  beforeUpdate() {
    // Reset loading state when src changes
    this.el.setAttribute('data-js-loading', 'true')
  }
}
```

#### 2.5 Use in Template

Update `session_run_live.html.heex`:

```elixir
<% image = Enum.at(@product_images, @current_image_index) %>
<.lqip_image
  id={"product-img-#{@current_product.id}-#{@current_image_index}"}
  src={Hudson.Media.public_image_url(image.path)}
  thumb_src={
    image.thumbnail_path &&
      Hudson.Media.public_image_url(image.thumbnail_path)
      || Hudson.Media.public_image_url(image.path)
  }
  alt={image.alt_text}
  class="product-image"
/>
```

---

## 3. CSV Import System

**Status:** Not implemented
**Priority:** Medium (manual entry sufficient for MVP)

### Implementation

```elixir
# lib/hudson/import.ex
defmodule Hudson.Import do
  alias NimbleCSV.RFC4180, as: CSV
  alias Ecto.Multi
  alias Hudson.Repo

  def import_csv(file_path, opts) do
    {rows, errors} =
      file_path
      |> File.stream!()
      |> CSV.parse_stream(skip_headers: false)
      |> Stream.drop(1) # remove header row
      |> Stream.with_index(2) # CSV line numbers
      |> Enum.reduce({[], []}, fn {row, line}, {acc, errs} ->
        case normalize_row(row) do
          {:ok, normalized} -> {[normalized | acc], errs}
          {:error, reason} -> {acc, [{line, reason} | errs]}
        end
      end)

    if errors != [] do
      {:error, :invalid_rows, Enum.reverse(errors)}
    else
      rows = Enum.reverse(rows)

      if Keyword.get(opts, :dry_run, false) do
        {:ok, preview: rows}
      else
        import_rows(rows, opts)
      end
    end
  end

  defp normalize_row(row) do
    # Parse CSV row and validate
    # Return {:ok, normalized_map} or {:error, reason}
  end

  defp import_rows(rows, opts) do
    Repo.transaction(fn ->
      Enum.each(rows, fn row ->
        Multi.new()
        |> Multi.run(:product, fn _repo, _changes ->
          upsert_product(row, opts)
        end)
        |> Multi.run(:session_product, fn _repo, %{product: product} ->
          upsert_session_product(product, row, opts)
        end)
        |> Repo.transaction()
        |> case do
          {:ok, _} -> :ok
          {:error, failed_step, reason, _} ->
            Repo.rollback({failed_step, reason})
        end
      end)
    end)
  end
end
```

**CSV Format:**
```csv
index,name,talking_points,original_price,sale_price,pid,sku
1,"Necklace","High quality\nBest seller",$49.99,$29.99,TT123,NECK-001
```

**Run Import:**
```bash
mix run priv/import/import_session.exs
```

---

## 4. Testing

**Status:** Not implemented
**Priority:** Medium

### 5.1 Context Tests

```elixir
# test/hudson/sessions_test.exs
defmodule Hudson.SessionsTest do
  use Hudson.DataCase
  alias Hudson.Sessions

  describe "jump_to_product/2" do
    setup do
      session = insert(:session)
      sp1 = insert(:session_product, session: session, position: 1)
      sp10 = insert(:session_product, session: session, position: 10)
      {:ok, _state} = Sessions.initialize_session_state(session.id)

      {:ok, session: session, sp1: sp1, sp10: sp10}
    end

    test "jumps directly to product by position", %{session: session, sp10: sp10} do
      Phoenix.PubSub.subscribe(Hudson.PubSub, "session:#{session.id}:state")

      {:ok, new_state} = Sessions.jump_to_product(session.id, 10)

      assert new_state.current_session_product_id == sp10.id
      assert new_state.current_image_index == 0
      assert_receive {:state_changed, ^new_state}
    end

    test "returns error for invalid position", %{session: session} do
      {:error, :invalid_position} = Sessions.jump_to_product(session.id, 999)
    end
  end
end
```

### 5.2 LiveView Tests

```elixir
# test/hudson_web/live/session_run_live_test.exs
defmodule HudsonWeb.SessionRunLiveTest do
  use HudsonWeb.ConnCase
  import Phoenix.LiveViewTest

  test "loads session and displays first product", %{conn: conn} do
    session = insert(:session)
    sp1 = insert(:session_product, session: session, position: 1)

    {:ok, view, html} = live(conn, ~p"/sessions/#{session}/run")

    assert html =~ session.name
    assert has_element?(view, "#product-img-#{sp1.product_id}-0")
  end
end
```

---

## 5. Authentication Gate (Post-MVP)

**Status:** Not implemented
**Priority:** Low for MVP (local/internal use only)

### MVP Approach

Hudson is designed for local use by internal team members. Authentication is deferred to post-MVP because:

- **Local deployment only** - Runs on localhost, not exposed to internet
- **Trusted network** - Used by internal team on secure network
- **Simplified onboarding** - No login required, just start the server
- **Focus on core features** - Prioritize session control and image loading

### Future Implementation (When Needed)

When deploying to production or remote access is required:

1. **Create role-specific secrets** and store in `.env`:
   ```bash
   PRODUCER_SHARED_SECRET=...
   TALENT_SHARED_SECRET=...
   ADMIN_SHARED_SECRET=...
   ```

2. **Hash secrets on boot** in `config/runtime.exs`:
   ```elixir
   config :hudson, Hudson.Auth,
     producer_secret_hash: Bcrypt.hash_pwd_salt(System.fetch_env!("PRODUCER_SHARED_SECRET")),
     talent_secret_hash: Bcrypt.hash_pwd_salt(System.fetch_env!("TALENT_SHARED_SECRET")),
     admin_secret_hash: Bcrypt.hash_pwd_salt(System.fetch_env!("ADMIN_SHARED_SECRET")),
     session_ttl: 4 * 60 * 60
   ```

3. **Verify logins** with `Bcrypt.verify_pass/2`; issue signed session tokens
4. **Throttle** `/login` route (e.g., using `Hammer`) to 5 attempts/min/IP
5. **Log audit events** (login, logout, elevated actions) with structured metadata

Designate plugs (`HudsonWeb.RequireProducer`, etc.) now so migrating to `mix phx.gen.auth` later is drop-in.

---

## 6. Production Deployment (Post-MVP)

**Status:** Not implemented
**Priority:** Low (localhost sufficient for MVP)

### 6.1 Windows Service Setup (NSSM)

```powershell
# Install service
nssm install Hudson "C:\path\to\hudson.exe"
nssm set Hudson AppDirectory "C:\path\to\app"
nssm set Hudson Start SERVICE_AUTO_START
nssm start Hudson
```

### 6.2 Desktop Packaging Options

- **Burrito** (Recommended for MVP) - Single executable, ~15MB
- **Elixir Desktop** (Long-term) - Native app with installers
- **Tauri + Burrito** (Advanced) - Smallest binary (3-10MB), complex setup

See [Future Roadmap](future_roadmap.md) for detailed comparison.

### 6.3 Production Configuration

```elixir
# config/runtime.exs
if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "DATABASE_URL not set"

  config :hudson, Hudson.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    ssl: true,
    ssl_opts: [
      cacertfile: System.fetch_env!("SUPABASE_CA_CERT"),
      server_name_indication: ~c"db.supabase.net"
    ]

  config :hudson, HudsonWeb.Endpoint,
    server: true,  # CRITICAL for deployment
    http: [port: String.to_integer(System.get_env("PORT") || "4000")]
end
```

---

## Performance Checklist

Critical patterns already implemented:

- [x] ✅ Use `temporary_assigns` for render-only data
- [x] ✅ Preload associations to avoid N+1 queries
- [x] ✅ Subscribe to PubSub only in `connected?(socket)`
- [x] ✅ Use `push_patch` instead of full navigation
- [x] ✅ Debounce rapid user input (keyboard buffer with timeout)
- [x] ✅ Clean up event listeners in hook `destroyed()`
- [ ] ⏳ Use LQIP for smooth image loading
- [ ] ⏳ Monitor socket memory with telemetry
- [ ] ⏳ Use `streams` for large collections (if needed later)

---

## Current Architecture

### File Structure

```
lib/
├── hudson/
│   ├── catalog/              # Product catalog schemas
│   │   ├── brand.ex
│   │   ├── product.ex
│   │   └── product_image.ex
│   ├── sessions/             # Live session schemas
│   │   ├── session.ex
│   │   ├── session_product.ex
│   │   └── session_state.ex
│   ├── catalog.ex            # Catalog context (CRUD)
│   └── sessions.ex           # Sessions context (state management)
└── hudson_web/
    ├── live/
    │   ├── session_run_live.ex        # Main LiveView
    │   └── session_run_live.html.heex # Template
    └── router.ex

assets/
├── js/
│   ├── app.js
│   └── hooks.js              # Keyboard control + connection status
└── css/
    └── app.css               # Dark theme styles

priv/
└── repo/
    ├── migrations/           # 6 migrations
    └── seeds.exs             # Sample data (8 products, 1 session)
```

### Key Implementation Details

**Temporary Assigns (Memory Management):**
```elixir
# lib/hudson_web/live/session_run_live.ex:31-36
{:ok, socket, temporary_assigns: [
  current_session_product: nil,
  current_product: nil,
  talking_points_html: nil,
  product_images: []
]}
```

**State Synchronization:**
```elixir
# lib/hudson/sessions.ex:258-266
defp broadcast_state_change({:ok, %SessionState{} = state}) do
  Phoenix.PubSub.broadcast(
    Hudson.PubSub,
    "session:#{state.session_id}:state",
    {:state_changed, state}
  )
  {:ok, state}
end
```

**Keyboard Navigation:**
- **Primary (Direct Jump):** Type number + Enter (e.g., "23" + Enter)
- **Convenience (Sequential):** ↑/↓ arrows, J/K keys, Space
- **Images:** ←/→ arrows, H/L keys
- **Quick Jump:** Home (first), End (last)

**Database Timestamp Handling:**
```elixir
# lib/hudson/sessions/session_state.ex:22
|> put_change(:updated_at, DateTime.utc_now() |> DateTime.truncate(:second))
```
_Note: PostgreSQL `:utc_datetime` rejects microseconds, must truncate to seconds_

---

## Known Issues & Solutions

### Issue: Navigation crashes with "reconnecting..."

**Cause:** `SessionState.updated_at` field rejected microseconds
**Solution:** Truncate timestamps to seconds in changeset (line 22 of `session_state.ex`)

### Issue: Template errors when state not loaded

**Cause:** Template tried to render before WebSocket connected and loaded state
**Solution:** Wrap product display in conditional checks for nil assigns

### Issue: Image 404s

**Expected:** Seed data uses placeholder paths (`/products/9/image-1.jpg`)
**Solution:** Upload real images to Supabase storage or use public URLs

---

## Next Session Checklist

When you're ready to continue development:

1. **Upload real product images** - Test with Supabase storage
2. **Implement LQIP pattern** - Smooth image transitions
3. **Add authentication** - Hash secrets, session tokens, rate limiting
4. **Build CSV import** - Bulk product management
5. **Write tests** - Context and LiveView coverage
6. **Deploy to production** - Windows service or desktop app

---

## Summary

**Core MVP is complete and functional:**
- Real-time session control with PubSub synchronization
- Keyboard-driven navigation optimized for live streaming
- Dark theme UI with proper contrast for 3-foot viewing
- Memory-optimized for 3-4 hour sessions
- URL-based state persistence (survives refreshes)
- Database schema with proper associations and constraints

**Ready for use:**
```bash
mix phx.server
# Visit: http://localhost:4000/sessions/2/run
```

**Next priorities:**
1. Image loading optimization (LQIP)
2. Supabase storage integration
3. Authentication gate
