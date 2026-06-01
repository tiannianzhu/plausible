defmodule PlausibleWeb.RequireLoggedOutPlug do
  alias PlausibleWeb.Router.Helpers, as: Routes
  import Plug.Conn

  def init(opts \\ []) do
    opts
  end

  def call(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> PlausibleWeb.UserAuth.set_logged_in_cookie()
      |> Phoenix.Controller.redirect(to: Routes.site_path(conn, :index))
      |> halt()
    else
      conn
    end
  end
end
