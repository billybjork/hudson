defmodule HudsonWeb.NavHooks do
  @moduledoc """
  LiveView lifecycle hooks for navigation state.
  """
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:set_current_page, _params, _session, socket) do
    # Get the view module from the socket's private data
    view_module = socket.private[:phoenix_live_view][:view] || socket.view
    current_page = get_current_page(view_module)

    {:cont, assign(socket, :current_page, current_page)}
  end

  defp get_current_page(HudsonWeb.SessionsLive.Index), do: :sessions
  defp get_current_page(HudsonWeb.ProductsLive.Index), do: :products
  defp get_current_page(HudsonWeb.ProductUploadLive), do: :products
  # Producer and host views return nil so navbar doesn't show
  defp get_current_page(HudsonWeb.SessionHostLive), do: nil
  defp get_current_page(HudsonWeb.SessionProducerLive), do: nil
  defp get_current_page(_), do: nil
end
