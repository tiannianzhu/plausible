defmodule PlausibleWeb.AvatarController do
  @moduledoc """
  This module proxies requests to BASE_URL/avatar/:hash to www.gravatar.com/avatar/:hash.

  The purpose is to make use of Gravatar's convenient avatar service without exposing information
  that could be used for tracking the Plausible user. Compared to requesting the Gravatar directly
  from the browser, this proxy module protects the Plausible user from disclosing to Gravatar:
  1. The client IP address
  2. User-Agent
  3. Referer header which can be used to track which site the user is visiting (i.e. plausible.io or self-hosted URL)

  The downside is the added latency from the request having to go through the Plausible server, rather than contacting the
  local CDN server operated by Gravatar's service.
  """
  use PlausibleWeb, :controller
  alias Plausible.HTTPClient

  @gravatar_base_url "https://www.gravatar.com"
  def avatar(conn, params) do
    url = Path.join(@gravatar_base_url, ["avatar/", params["hash"]]) <> "?s=150&d=identicon"

    case HTTPClient.impl().get(url) do
      {:ok, %Finch.Response{status: 200, body: body, headers: headers}} ->
        conn
        |> forward_headers(headers)
        |> send_resp(200, body)

      {:error, _} ->
        conn
        |> put_resp_content_type("image/svg+xml")
        |> put_resp_header("cache-control", "public, max-age=86400")
        |> send_resp(200, fallback_avatar_svg(params["hash"]))
    end
  end

  @forwarded_headers ["content-type", "cache-control", "expires"]
  defp forward_headers(%Plug.Conn{} = conn, headers) do
    headers_to_forward = Enum.filter(headers, fn {k, _} -> k in @forwarded_headers end)
    %Plug.Conn{conn | resp_headers: headers_to_forward}
  end

  defp fallback_avatar_svg(hash) do
    color =
      case to_string(hash) do
        <<color::binary-size(6), _::binary>> -> "#" <> color
        _ -> "#6366f1"
      end

    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 150 150" fill="none">
      <rect width="150" height="150" rx="75" fill="#F3F4F6"/>
      <circle cx="75" cy="54" r="26" fill="#FFFFFF"/>
      <path d="M35 124C35 100.804 53.804 82 77 82H73C96.196 82 115 100.804 115 124V150H35V124Z" fill="#FFFFFF"/>
      <circle cx="75" cy="75" r="69" stroke="#{color}" stroke-width="12"/>
    </svg>
    """
  end
end
