defmodule HudsonWeb.PageControllerTest do
  use HudsonWeb.ConnCase

  test "GET / redirects to /sessions", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/sessions"
  end
end
