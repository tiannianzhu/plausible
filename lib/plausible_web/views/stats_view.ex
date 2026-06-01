defmodule PlausibleWeb.StatsView do
  use PlausibleWeb, :view
  use Plausible

  require Plausible.Billing

  def plausible_url do
    PlausibleWeb.URL.base_url()
  end

  def large_number_format(n, opts \\ []) do
    k = if Keyword.get(opts, :capitalize_k?, false), do: "K", else: "k"

    cond do
      n >= 1_000 && n < 1_000_000 ->
        thousands = trunc(n / 100) / 10

        if thousands == trunc(thousands) || n >= 100_000 do
          "#{trunc(thousands)}" <> k
        else
          "#{thousands}" <> k
        end

      n >= 1_000_000 && n < 1_000_000_000 ->
        millions = trunc(n / 100_000) / 10

        if millions == trunc(millions) || n > 100_000_000 do
          "#{trunc(millions)}M"
        else
          "#{millions}M"
        end

      n >= 1_000_000_000 && n < 1_000_000_000_000 ->
        billions = trunc(n / 100_000_000) / 10

        if billions == trunc(billions) || n > 100_000_000_000 do
          "#{trunc(billions)}B"
        else
          "#{billions}B"
        end

      is_integer(n) ->
        Integer.to_string(n)
    end
  end

  def stats_container_class(conn) do
    cond do
      conn.assigns[:embedded] && conn.params["width"] == "manual" -> "px-6"
      conn.assigns[:embedded] -> "max-w-screen-xl mx-auto px-6"
      !conn.assigns[:embedded] -> "container print:max-w-full"
    end
  end

  @doc """
  Returns a readable stats URL.
  """
  def pretty_stats_url(%Plausible.Site{} = site) do
    PlausibleWeb.URL.site_url(site)
  end
end
