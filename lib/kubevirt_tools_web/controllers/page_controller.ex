defmodule KubevirtToolsWeb.PageController do
  use KubevirtToolsWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/dashboard")
  end
end
