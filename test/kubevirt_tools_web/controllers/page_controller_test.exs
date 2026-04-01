defmodule KubevirtToolsWeb.PageControllerTest do
  use KubevirtToolsWeb.ConnCase

  test "GET / redirects to dashboard", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/dashboard"
  end
end
