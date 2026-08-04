defmodule PlausibleWeb.FaviconTest do
  use Plausible.DataCase, async: true
  import Plug.Test
  alias PlausibleWeb.Favicon

  import Mox
  setup :verify_on_exit!

  setup_all do
    opts = PlausibleWeb.Favicon.init(nil)
    fetcher = fn _url -> {:ok, Req.Response.new(status: 404)} end
    cache_name = String.to_atom("favicon_test_#{System.unique_integer([:positive])}")

    %{plug_opts: Keyword.merge(opts, favicon_fetcher: fetcher, cache_name: cache_name)}
  end

  test "ignores request on a URL it does not need to handle", %{plug_opts: plug_opts} do
    old_conn = conn(:get, "/irrelevant")
    new_conn = Favicon.call(old_conn, plug_opts)

    refute new_conn.halted
    assert old_conn == new_conn
  end

  test "proxies request on favicon URL to duckduckgo", %{plug_opts: plug_opts} do
    expect(
      Plausible.HTTPClient.Mock,
      :get,
      fn "https://icons.duckduckgo.com/ip3/plausible.io.ico" ->
        {:ok, %Finch.Response{status: 200, body: "favicon response body"}}
      end
    )

    conn =
      conn(:get, "/favicon/sources/plausible.io")
      |> Favicon.call(plug_opts)

    assert conn.halted
    assert conn.status == 200
    assert conn.resp_body == "favicon response body"
  end

  test "requests favicon from DDG by hostname only (strips pathname)", %{plug_opts: plug_opts} do
    expect(
      Plausible.HTTPClient.Mock,
      :get,
      fn "https://icons.duckduckgo.com/ip3/site.com.ico" ->
        {:ok, %Finch.Response{status: 200, body: "favicon response body"}}
      end
    )

    conn =
      conn(:get, "/favicon/sources/site.com/subfolder")
      |> Favicon.call(plug_opts)

    assert conn.halted
    assert conn.status == 200
    assert conn.resp_body == "favicon response body"
  end

  test "probes a site path on the backend and caches the result", %{plug_opts: plug_opts} do
    cache_name = String.to_atom("favicon_test_#{System.unique_integer([:positive])}")
    start_supervised!({ConCache, name: cache_name, ttl_check_interval: 1_000, global_ttl: 60_000})

    test_pid = self()

    fetcher = fn url ->
      send(test_pid, {:favicon_fetch, url})

      {:ok,
       Req.Response.new(
         status: 200,
         headers: %{"content-type" => ["image/png"]},
         body: "path favicon"
       )}
    end

    opts =
      Keyword.merge(plug_opts,
        cache_name: cache_name,
        favicon_fetcher: fetcher
      )

    conn =
      conn(:get, "/favicon/sources/example.com/docs")
      |> Favicon.call(opts)

    assert conn.resp_body == "path favicon"
    assert_receive {:favicon_fetch, "https://example.com/docs/favicon.ico"}

    conn =
      conn(:get, "/favicon/sources/example.com/docs")
      |> Favicon.call(opts)

    assert conn.resp_body == "path favicon"
    refute_receive {:favicon_fetch, _url}
  end

  test "accepts a favicon larger than one megabyte", %{plug_opts: plug_opts} do
    large_favicon = String.duplicate("x", 1_000_001)

    fetcher = fn url ->
      if String.ends_with?(url, "/favicon.ico") do
        {:ok,
         Req.Response.new(
           status: 200,
           headers: %{"content-type" => ["image/x-icon"]},
           body: large_favicon
         )}
      else
        {:ok,
         Req.Response.new(
           status: 200,
           headers: %{"content-type" => ["image/x-icon"]},
           body: "fallback favicon"
         )}
      end
    end

    opts = Keyword.put(plug_opts, :favicon_fetcher, fetcher)

    conn =
      conn(:get, "/favicon/sources/example.com")
      |> Favicon.call(opts)

    assert conn.resp_body == large_favicon
  end

  test "does not set security headers for non-SVG images", %{plug_opts: plug_opts} do
    expect(
      Plausible.HTTPClient.Mock,
      :get,
      fn "https://icons.duckduckgo.com/ip3/plausible.io.ico" ->
        {:ok, %Finch.Response{status: 200, body: "favicon response body"}}
      end
    )

    conn =
      conn(:get, "/favicon/sources/plausible.io")
      |> Favicon.call(plug_opts)

    assert conn.halted
    assert conn.status == 200
    assert conn.resp_body == "favicon response body"
    assert Plug.Conn.get_resp_header(conn, "content-security-policy") == []
    assert Plug.Conn.get_resp_header(conn, "content-disposition") == []
  end

  test "maps a categorized source to URL for favicon", %{plug_opts: plug_opts} do
    expect(
      Plausible.HTTPClient.Mock,
      :get,
      fn "https://icons.duckduckgo.com/ip3/facebook.com.ico" ->
        {:ok, %Finch.Response{status: 200, body: "favicon response body"}}
      end
    )

    conn =
      conn(:get, "/favicon/sources/Facebook")
      |> Favicon.call(plug_opts)

    assert conn.halted
    assert conn.status == 200
    assert conn.resp_body == "favicon response body"
  end

  for {source, domain} <- %{
        "Linktree" => "linktr.ee",
        "Bluesky" => "bsky.app",
        "Mastodon" => "mastodon.social",
        "X (Twitter)" => "x.com",
        "Kagi" => "kagi.com",
        "Microsoft 365" => "office.com"
      } do
    test "maps custom source #{source} to #{domain} for favicon", %{plug_opts: plug_opts} do
      expect(
        Plausible.HTTPClient.Mock,
        :get,
        fn "https://icons.duckduckgo.com/ip3/#{unquote(domain)}.ico" ->
          {:ok, %Finch.Response{status: 200, body: "favicon response body"}}
        end
      )

      conn =
        conn(:get, "/favicon/sources/#{URI.encode_www_form(unquote(source))}")
        |> Favicon.call(plug_opts)

      assert conn.halted
      assert conn.status == 200
      assert conn.resp_body == "favicon response body"
    end
  end

  test "copies content-type header from the proxied response", %{plug_opts: plug_opts} do
    expect(
      Plausible.HTTPClient.Mock,
      :get,
      fn "https://icons.duckduckgo.com/ip3/plausible.io.ico" ->
        {:ok,
         %Finch.Response{
           status: 200,
           body: "favicon response body",
           headers: [
             {"transfer-encoding", "chunked"},
             {"content-type", "should-pass-through"}
           ]
         }}
      end
    )

    conn =
      conn(:get, "/favicon/sources/plausible.io")
      |> Favicon.call(plug_opts)

    assert conn.halted
    assert conn.status == 200
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["should-pass-through"]
  end

  test "overrides content-type header if proxied response starts with <svg", %{
    plug_opts: plug_opts
  } do
    expect(
      Plausible.HTTPClient.Mock,
      :get,
      fn "https://icons.duckduckgo.com/ip3/plausible.io.ico" ->
        {:ok,
         %Finch.Response{
           status: 200,
           body: "<svg>icon</svg>",
           headers: [{"content-type", "image/x-icon"}]
         }}
      end
    )

    conn =
      conn(:get, "/favicon/sources/plausible.io")
      |> Favicon.call(plug_opts)

    assert conn.halted
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["image/svg+xml; charset=utf-8"]
    assert Plug.Conn.get_resp_header(conn, "content-security-policy") == ["script-src 'none'"]
    assert Plug.Conn.get_resp_header(conn, "content-disposition") == ["attachment"]
  end

  describe "Fallback to placeholder icon" do
    @placeholder_icon File.read!("priv/link_favicon.svg")

    test "falls back to placeholder when DDG returns a non-2xx response", %{plug_opts: plug_opts} do
      expect(
        Plausible.HTTPClient.Mock,
        :get,
        fn "https://icons.duckduckgo.com/ip3/plausible.io.ico" ->
          res = %Finch.Response{status: 503, body: "bad gateway"}
          {:error, Plausible.HTTPClient.Non200Error.new(res)}
        end
      )

      conn =
        conn(:get, "/favicon/sources/plausible.io")
        |> Favicon.call(plug_opts)

      assert conn.halted
      assert conn.status == 200
      assert conn.resp_body == @placeholder_icon
    end

    test "falls back to placeholder in case of a network error", %{plug_opts: plug_opts} do
      expect(
        Plausible.HTTPClient.Mock,
        :get,
        fn "https://icons.duckduckgo.com/ip3/plausible.io.ico" ->
          {:error, %Finch.TransportError{reason: :closed}}
        end
      )

      conn =
        conn(:get, "/favicon/sources/plausible.io")
        |> Favicon.call(plug_opts)

      assert conn.halted
      assert conn.status == 200
      assert conn.resp_body == @placeholder_icon
    end

    test "falls back to placeholder when DDG returns a broken image response", %{
      plug_opts: plug_opts
    } do
      expect(
        Plausible.HTTPClient.Mock,
        :get,
        fn "https://icons.duckduckgo.com/ip3/plausible.io.ico" ->
          {:ok, %Finch.Response{status: 200, body: <<137, 80, 78, 71, 13, 10, 26, 10>>}}
        end
      )

      conn =
        conn(:get, "/favicon/sources/plausible.io")
        |> Favicon.call(plug_opts)

      assert conn.halted
      assert conn.status == 200
      assert conn.resp_body == @placeholder_icon
    end
  end
end
