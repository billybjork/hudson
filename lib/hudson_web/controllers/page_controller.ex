defmodule HudsonWeb.PageController do
  use HudsonWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
