defmodule PlausibleWeb.Favicon do
  @referer_domains_file "priv/referer_favicon_domains.json"
  @cache_name :favicon
  @favicon_names ~w(favicon.ico favicon.png favicon.svg apple-touch-icon.png)
  @success_ttl :timer.hours(24)
  @negative_ttl :timer.hours(1)
  @max_favicon_size 2_000_000
  @default_content_type "image/x-icon"

  @moduledoc """
  A Plug that resolves favicon images and returns them to the Plausible frontend.

  Path-based sites are checked for a favicon under their configured path before
  falling back to DuckDuckGo. Resolved responses are cached so the browser only
  makes one request and the server does not repeat the external probes on every
  page load.

  The proxying is there so we can reduce the number of third-party domains that
  the browser clients need to connect to. Our goal is to have 0 third-party domain
  connections on the website for privacy reasons.

  This module also maps between categorized sources and their respective URLs for favicons.
  What does that mean exactly? During ingestion we use `PlausibleWeb.RefInspector.parse/1` to
  categorize our referrer sources like so:

  google.com -> Google
  google.co.uk -> Google
  google.com.au -> Google

  So when we show Google as a source in the dashboard, the request to this plug will come as:
  https://plausible/io/favicon/sources/Google

  Now, when we want to show a favicon for Google, we need to convert Google -> google.com or
  some other hostname owned by Google:
  https://icons.duckduckgo.com/ip3/google.com.ico

  The mapping from source category -> source hostname is stored in "#{@referer_domains_file}" and
  managed by `Mix.Tasks.GenerateReferrerFavicons.run/1`
  """
  import Plug.Conn
  alias Plausible.HTTPClient

  @placeholder_icon_location "priv/link_favicon.svg"
  @placeholder_icon File.read!(@placeholder_icon_location)
  @external_resource @placeholder_icon_location
  @custom_icons %{
    "Brave" => "search.brave.com",
    "Kagi" => "kagi.com",
    "Sogou" => "sogou.com",
    "Wikipedia" => "en.wikipedia.org",
    "Discord" => "discord.com",
    "Perplexity" => "perplexity.ai",
    "Microsoft Teams" => "microsoft.com",
    "LinkedIn" => "linkedin.com",
    "Linktree" => "linktr.ee",
    "Bluesky" => "bsky.app",
    "Mastodon" => "mastodon.social",
    "Google Gemini" => "gemini.google.com",
    "ChatGPT" => "chatgpt.com",
    "Claude" => "claude.ai",
    "Phind" => "phind.com",
    "DeepSeek" => "deepseek.com",
    "Microsoft Copilot" => "copilot.com",
    "Grok" => "grok.com",
    "X (Twitter)" => "x.com",
    "Microsoft 365" => "office.com"
  }

  def init(_) do
    domains =
      File.read!(Application.app_dir(:plausible, @referer_domains_file))
      |> Jason.decode!()
      |> Map.merge(@custom_icons)

    [
      favicon_domains: domains,
      favicon_fetcher: &Plausible.SSRF.get/1,
      cache_name: @cache_name
    ]
  end

  @ddg_broken_icon <<137, 80, 78, 71, 13, 10, 26, 10>>
  @doc """
  Resolves a favicon from the configured site path and then the DuckDuckGo
  favicon service.

  ## Placeholder

  Cases where we show a placeholder icon instead:

  1. In case of network error to DuckDuckGo
  2. In case of non-2xx status code from DuckDuckGo
  3. In case of broken image response body from DuckDuckGo

  I'm not sure why DDG sometimes returns a broken PNG image in their response
  but we filter that out.  When the icon request fails, we show a placeholder
  favicon instead. The placeholder is an svg from [https://heroicons.com/](https://heroicons.com/).

  DuckDuckGo favicon service has some issues with [SVG favicons](https://css-tricks.com/svg-favicons-and-all-the-fun-things-we-can-do-with-them/).
  For some reason, they return them with `content-type=image/x-icon` whereas SVG
  icons should be returned with `content-type=image/svg+xml`. This Plug detects
  when the response body starts with `<svg` and will override the `Content-Type`
  to correct it.

  ## Preventing XSS vulnerabilities

  SVGs may contain `<script>` tags, and as these SVGs come from external
  sources, we need to prevent untrusted code from running on the browser.

  - This Plug sets a strict `Content-Security-Policy` header telling the browser
    not to run scripts.

  - This Plug sets `Content-Disposition=attachment` to prevent the SVG from
    rendering when navigating to `/favicon/sources/:domain` directly.

  - Browsers do not execute scripts from `<img>` tags, therefore it is safe to
    use `<img src="https://plausible.io/favicon/sources/dummy.site"></img>`

  """
  def call(conn, opts) do
    favicon_domains = Keyword.fetch!(opts, :favicon_domains)
    favicon_fetcher = Keyword.get(opts, :favicon_fetcher, &Plausible.SSRF.get/1)
    cache_name = Keyword.get(opts, :cache_name, @cache_name)

    case conn.request_path do
      "/favicon/sources/placeholder" ->
        send_placeholder(conn)

      "/favicon/sources/" <> domain ->
        domain = URI.decode_www_form(domain)

        domain
        |> cached_favicon(favicon_domains, favicon_fetcher, cache_name)
        |> send_favicon(conn)

      _ ->
        conn
    end
  end

  defp cached_favicon(domain, favicon_domains, favicon_fetcher, cache_name) do
    source_domain = Map.get(favicon_domains, domain, domain)
    resolver = fn -> resolve_favicon(source_domain, favicon_fetcher) end

    if cache_available?(cache_name) do
      Plausible.Cache.Adapter.get(cache_name, source_domain, fn ->
        response = resolver.()
        %ConCache.Item{value: response, ttl: response.ttl}
      end)
    else
      resolver.()
    end
  end

  defp cache_available?(cache_name) when is_atom(cache_name),
    do: is_pid(Process.whereis(cache_name))

  defp cache_available?(_cache_name), do: false

  defp resolve_favicon(domain, favicon_fetcher) do
    Enum.find_value(favicon_sources(domain), &fetch_direct_favicon(&1, favicon_fetcher)) ||
      fetch_duckduckgo_favicon(domain)
  end

  defp favicon_sources(domain) do
    case URI.parse("https://#{domain}") do
      %URI{host: host, path: path, port: port} when is_binary(host) and host != "" ->
        path = String.trim_trailing(path || "", "/")
        authority = if port in [nil, 443], do: host, else: "#{host}:#{port}"
        path_prefixes = if path == "", do: [""], else: [path, ""]

        Enum.flat_map(path_prefixes, fn prefix ->
          Enum.map(@favicon_names, fn name ->
            "https://#{authority}#{prefix}/#{name}"
          end)
        end)

      _ ->
        []
    end
  end

  defp fetch_direct_favicon(url, fetcher) do
    case fetcher.(url) do
      {:ok, %Req.Response{status: status, body: body} = response}
      when status in 200..299 and is_binary(body) ->
        if valid_direct_favicon?(response, body) do
          content_type = response_content_type(response)

          %{
            body: body,
            content_type: content_type,
            secure?: svg_content_type?(content_type),
            ttl: @success_ttl
          }
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp valid_direct_favicon?(response, body) do
    byte_size(body) > 0 and byte_size(body) <= @max_favicon_size and
      case Req.Response.get_header(response, "content-type") do
        [] -> true
        [content_type | _] -> String.starts_with?(String.downcase(content_type), "image/")
      end
  end

  defp fetch_duckduckgo_favicon(domain) do
    hostname = domain |> String.split("/", parts: 2) |> hd()

    case HTTPClient.impl().get("https://icons.duckduckgo.com/ip3/#{hostname}.ico") do
      {:ok, %Finch.Response{status: 200, body: body, headers: headers}}
      when is_binary(body) and body != @ddg_broken_icon ->
        content_type = ddg_content_type(body, headers)

        %{
          body: body,
          content_type: content_type,
          secure?: svg_content_type?(content_type),
          ttl: @success_ttl
        }

      _ ->
        placeholder_response()
    end
  end

  defp response_content_type(response) do
    case Req.Response.get_header(response, "content-type") do
      [content_type | _] -> content_type
      [] -> @default_content_type
    end
  end

  defp ddg_content_type(body, headers) do
    content_type = header_value(headers, "content-type") || @default_content_type

    if String.starts_with?(body, "<svg"),
      do: "image/svg+xml; charset=utf-8",
      else: content_type
  end

  defp svg_content_type?(content_type),
    do: String.starts_with?(String.downcase(content_type), "image/svg")

  defp header_value(headers, name) do
    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(key) == name, do: value
    end)
  end

  defp placeholder_response do
    %{body: @placeholder_icon, content_type: "image/svg+xml", secure?: false, ttl: @negative_ttl}
  end

  defp send_placeholder(conn) do
    placeholder_response() |> send_favicon(conn)
  end

  defp send_favicon(response, conn) do
    conn =
      conn
      |> put_resp_header("content-type", response.content_type)
      |> put_resp_header("cache-control", "public, max-age=#{div(response.ttl, 1000)}")

    conn = if response.secure?, do: prevent_javascript_execution(conn), else: conn

    conn
    |> send_resp(200, response.body)
    |> halt()
  end

  defp prevent_javascript_execution(conn) do
    conn
    |> put_resp_header("content-security-policy", "script-src 'none'")
    |> put_resp_header("content-disposition", "attachment")
  end
end
