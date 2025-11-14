defmodule HudsonWeb.ProductUploadLive do
  use HudsonWeb, :live_view

  on_mount {HudsonWeb.NavHooks, :set_current_page}

  alias Hudson.{Catalog, Media}

  @impl true
  def mount(params, _session, socket) do
    products = Catalog.list_products()

    # Auto-select product if product_id is in query params
    selected_product_id =
      case params["product_id"] do
        nil -> nil
        id when is_binary(id) -> String.to_integer(id)
        id when is_integer(id) -> id
      end

    socket =
      socket
      |> assign(
        page_title: "Upload Product Images",
        products: products,
        selected_product_id: selected_product_id,
        uploading: false,
        upload_progress: 0,
        upload_results: []
      )
      |> allow_upload(:product_images,
        accept: ~w(.jpg .jpeg .png),
        max_entries: 5,
        max_file_size: 10_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_product", %{"product_id" => product_id}, socket) do
    {:noreply, assign(socket, selected_product_id: String.to_integer(product_id))}
  end

  @impl true
  def handle_event("upload", _params, socket) do
    socket =
      if socket.assigns.selected_product_id do
        socket = assign(socket, uploading: true, upload_progress: 0, upload_results: [])
        product_id = socket.assigns.selected_product_id

        # Get entries with their upload order (0-indexed positions)
        entries_with_positions =
          socket.assigns.uploads.product_images.entries
          |> Enum.with_index(fn entry, index -> {entry, index} end)

        # Process uploads
        uploaded_files =
          consume_uploaded_entries(socket, :product_images, fn %{path: path}, entry ->
            # Find the position for this entry
            {_matched_entry, position} =
              Enum.find(entries_with_positions, fn {e, _pos} -> e.ref == entry.ref end)

            process_image_upload(path, product_id, position, entry)
          end)

        socket
        |> assign(
          uploading: false,
          upload_progress: 100,
          upload_results: uploaded_files
        )
        |> put_flash(:info, "Uploaded #{length(uploaded_files)} image(s) successfully!")
      else
        put_flash(socket, :error, "Please select a product first")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :product_images, ref)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="upload-container">
      <div class="back-link">
        <.link navigate={~p"/products"} class="back-link__text">
          ← Back to Products
        </.link>
      </div>
      <h1>Upload Product Images</h1>
      
    <!-- Product Selection -->
      <form phx-change="select_product" class="product-select">
        <label for="product-selector">Select Product:</label>
        <select id="product-selector" name="product_id">
          <option value="">-- Choose a product --</option>
          <%= for product <- @products do %>
            <option value={product.id} selected={@selected_product_id == product.id}>
              {product.name}
            </option>
          <% end %>
        </select>
      </form>
      
    <!-- Upload Area -->
      <%= if @selected_product_id do %>
        <div class="upload-area">
          <form id="upload-form" phx-change="validate" phx-submit="upload">
            <div class="file-input-wrapper">
              <div class="file-input-label">
                <div class="file-input-button">
                  Choose Files
                </div>
                <span class="file-input-text">or drag and drop</span>
                <.live_file_input upload={@uploads.product_images} />
              </div>
              <p class="help-text">
                Select up to 5 images (JPG, PNG). Max 10MB each.
              </p>
            </div>
            
    <!-- Preview Uploaded Files -->
            <%= for entry <- @uploads.product_images.entries do %>
              <div class="upload-entry">
                <div class="preview">
                  <.live_img_preview entry={entry} width="75" />
                </div>
                <div class="info">
                  <p>{entry.client_name}</p>
                  <progress value={entry.progress} max="100">{entry.progress}%</progress>
                </div>
                <button
                  type="button"
                  phx-click="cancel_upload"
                  phx-value-ref={entry.ref}
                  aria-label="cancel"
                >
                  &times;
                </button>
              </div>

              <%= for err <- upload_errors(@uploads.product_images, entry) do %>
                <p class="error">{error_to_string(err)}</p>
              <% end %>
            <% end %>
            
    <!-- Upload Button -->
            <%= if @uploads.product_images.entries != [] do %>
              <button type="submit" disabled={@uploading}>
                {if @uploading, do: "Uploading...", else: "Upload Images"}
              </button>
            <% end %>
          </form>
          
    <!-- Upload Results -->
          <%= if @upload_results != [] do %>
            <div class="upload-results">
              <h3>Upload Results:</h3>
              <%= for result <- @upload_results do %>
                <div class={"result #{if result.success, do: "success", else: "error"}"}>
                  <%= if result.success do %>
                    ✓ {result.filename} uploaded successfully
                  <% else %>
                    ✗ {result.filename} failed: {inspect(result.error)}
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>

    <style>
      .upload-container {
        max-width: 800px;
        margin: 2rem auto;
        padding: 2rem;
        background: var(--bg-dark, #1a1a1a);
        color: var(--text-primary, #ffffff);
      }

      .back-link {
        margin-bottom: 1rem;
      }

      .back-link__text {
        display: inline-flex;
        align-items: center;
        color: var(--accent, #0066cc);
        text-decoration: none;
        font-size: 0.875rem;
        transition: color 0.2s;
      }

      .back-link__text:hover {
        color: var(--accent-light, #3388dd);
        text-decoration: underline;
      }

      .product-select {
        margin-bottom: 2rem;
      }

      .product-select label {
        display: block;
        margin-bottom: 0.5rem;
        font-weight: 600;
      }

      .product-select select {
        width: 100%;
        padding: 0.75rem;
        font-size: 1rem;
        background: var(--bg-medium, #2a2a2a);
        color: var(--text-primary, #ffffff);
        border: 1px solid var(--border-color, #444);
        border-radius: 4px;
      }

      .upload-area {
        margin-top: 2rem;
      }

      .file-input-wrapper {
        margin-bottom: 2rem;
      }

      .file-input-label {
        display: block;
        padding: 2rem;
        border: 2px dashed var(--border-color, #444);
        border-radius: 8px;
        text-align: center;
        transition: all 0.2s;
        background: var(--bg-medium, #2a2a2a);
      }

      .file-input-label:hover {
        border-color: var(--accent, #0066cc);
        background: var(--bg-light, #333);
      }

      .file-input-button {
        display: block;
        padding: 0.75rem 1.5rem;
        background: var(--accent, #0066cc);
        color: white;
        border-radius: 4px;
        font-weight: 600;
        margin: 0 auto 0.5rem;
        width: fit-content;
      }

      .file-input-text {
        display: block;
        color: var(--text-secondary, #999);
        font-size: 0.875rem;
        margin-bottom: 1rem;
      }

      .file-input-wrapper input[type="file"] {
        display: block;
        margin: 1rem auto 0;
        padding: 0.5rem;
        max-width: 400px;
        color: var(--text-primary, #ffffff);
      }

      .help-text {
        margin-top: 0.5rem;
        font-size: 0.875rem;
        color: var(--text-secondary, #999);
      }

      .upload-entry {
        display: flex;
        align-items: center;
        gap: 1rem;
        padding: 1rem;
        margin-bottom: 0.5rem;
        background: var(--bg-medium, #2a2a2a);
        border-radius: 4px;
      }

      .upload-entry .preview {
        flex-shrink: 0;
      }

      .upload-entry .info {
        flex-grow: 1;
      }

      .upload-entry button {
        flex-shrink: 0;
        width: 2rem;
        height: 2rem;
        border: none;
        background: var(--danger, #dc3545);
        color: white;
        border-radius: 50%;
        cursor: pointer;
        font-size: 1.5rem;
        line-height: 1;
      }

      .upload-entry progress {
        width: 100%;
        height: 8px;
      }

      button[type="submit"] {
        margin-top: 1rem;
        padding: 0.75rem 1.5rem;
        font-size: 1rem;
        background: var(--accent, #0066cc);
        color: white;
        border: none;
        border-radius: 4px;
        cursor: pointer;
      }

      button[type="submit"]:disabled {
        background: var(--bg-light, #444);
        cursor: not-allowed;
      }

      .upload-results {
        margin-top: 2rem;
        padding: 1rem;
        background: var(--bg-medium, #2a2a2a);
        border-radius: 4px;
      }

      .result {
        padding: 0.5rem;
        margin-bottom: 0.5rem;
      }

      .result.success {
        color: var(--success, #28a745);
      }

      .result.error {
        color: var(--danger, #dc3545);
      }

      .error {
        color: var(--danger, #dc3545);
        margin-top: 0.25rem;
        font-size: 0.875rem;
      }
    </style>
    """
  end

  defp error_to_string(:too_large), do: "File is too large (max 10MB)"
  defp error_to_string(:not_accepted), do: "File type not accepted (only JPG, PNG)"
  defp error_to_string(:too_many_files), do: "Too many files (max 5)"
  defp error_to_string(err), do: "Upload error: #{inspect(err)}"

  defp process_image_upload(path, product_id, position, entry) do
    with {:ok, %{path: img_path, thumbnail_path: thumb_path}} <-
           Media.upload_product_image(path, product_id, position),
         {:ok, product_image} <-
           Catalog.create_product_image(%{
             product_id: product_id,
             path: img_path,
             thumbnail_path: thumb_path,
             position: position,
             is_primary: position == 0,
             alt_text: "#{entry.client_name}"
           }) do
      {:ok, %{success: true, filename: entry.client_name, image: product_image}}
    else
      {:error, %Ecto.Changeset{}} ->
        {:postpone,
         %{success: false, filename: entry.client_name, error: "Failed to create DB record"}}

      {:error, reason} ->
        {:postpone, %{success: false, filename: entry.client_name, error: reason}}
    end
  end
end
