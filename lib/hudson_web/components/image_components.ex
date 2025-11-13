defmodule HudsonWeb.ImageComponents do
  @moduledoc """
  Image components with progressive loading (LQIP pattern).

  LQIP = Low Quality Image Placeholder
  Provides smooth blur-to-sharp transitions for better perceived performance.
  """

  use Phoenix.Component

  @doc """
  Renders an image with progressive loading (LQIP pattern).

  Shows:
  1. Skeleton loader (animated gradient)
  2. Low-quality placeholder (blurred thumbnail)
  3. Full-quality image (sharp, fades in)

  ## Attributes

  - `id` (required) - Unique identifier for the image
  - `src` (required) - Full-quality image URL
  - `thumb_src` (required) - Low-quality thumbnail URL
  - `alt` (optional) - Alt text for accessibility
  - `class` (optional) - Additional CSS classes

  ## Examples

      <.lqip_image
        id="product-img-1"
        src={Hudson.Media.public_image_url(image.path)}
        thumb_src={Hudson.Media.public_image_url(image.thumbnail_path)}
        alt="Product name"
        class="product-image"
      />
  """
  attr :id, :string, required: true
  attr :src, :string, required: true
  attr :thumb_src, :string, required: true
  attr :alt, :string, default: ""
  attr :class, :string, default: ""

  def lqip_image(assigns) do
    ~H"""
    <div class={"lqip-container #{@class}"}>
      <%!-- Skeleton loader (shown while thumbnail loads) --%>
      <div id={"skeleton-#{@id}"} class="lqip-skeleton" />

      <%!-- Low-quality placeholder (blurred thumbnail) --%>
      <img
        id={"placeholder-#{@id}"}
        class="lqip-placeholder"
        src={@thumb_src}
        alt=""
        aria-hidden="true"
      />

      <%!-- High-quality image (main image) --%>
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
