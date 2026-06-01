defmodule PlausibleWeb.URL do
  @moduledoc false

  alias Plausible.Site

  def base_url do
    PlausibleWeb.Endpoint.config(:url)
    |> base_url()
  end

  @doc false
  def base_url(url_config) do
    %URI{
      scheme: to_string(Keyword.get(url_config, :scheme, "http")),
      host: Keyword.fetch!(url_config, :host),
      port: Keyword.get(url_config, :port),
      path: Keyword.get(url_config, :path, "/")
    }
    |> URI.to_string()
    |> String.trim_trailing("/")
  end

  def path(path) do
    PlausibleWeb.Endpoint.config(:url)
    |> path(path)
  end

  @doc false
  def path(url_config, path) do
    Path.join(Keyword.get(url_config, :path) || "/", path)
  end

  def url(path) do
    Path.join(base_url(), path)
  end

  def site_path(%Site{} = site, extra \\ nil, params \\ []) do
    site
    |> site_param()
    |> append_path(extra)
    |> path()
    |> append_query(params)
  end

  def site_url(%Site{} = site, extra \\ nil, params \\ []) do
    site
    |> site_param()
    |> append_path(extra)
    |> url()
    |> append_query(params)
  end

  def site_action_path(%Site{} = site, extra \\ nil, params \\ []) do
    "sites"
    |> Path.join(site_param(site))
    |> append_path(extra)
    |> path()
    |> append_query(params)
  end

  defp site_param(%Site{} = site), do: "s/#{site.id}"

  defp append_path(base, extra) when extra in [nil, ""], do: base
  defp append_path(base, extra), do: Path.join(base, extra)

  defp append_query(path, params) when params in [%{}, []], do: path

  defp append_query(path, params), do: path <> "?" <> URI.encode_query(params)
end
