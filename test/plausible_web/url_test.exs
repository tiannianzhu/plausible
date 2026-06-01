defmodule PlausibleWeb.URLTest do
  use ExUnit.Case, async: true

  alias Plausible.Site
  alias PlausibleWeb.URL

  test "paths default to the root when endpoint path is nil" do
    assert URL.path([path: nil], "s/4") == "/s/4"
  end

  test "paths include the configured endpoint path" do
    assert URL.path([path: "/analytics"], "s/4") == "/analytics/s/4"
  end

  test "base URLs include the configured endpoint path" do
    assert URL.base_url(scheme: "https", host: "example.com", path: "/analytics") ==
             "https://example.com/analytics"
  end

  test "site paths use site id for all domains" do
    site = %Site{id: 4, domain: "example.com"}

    assert URL.site_path(site) == "/s/4"
    assert URL.site_path(site, "settings/integrations") == "/s/4/settings/integrations"
  end

  test "site action paths use site id for all domains" do
    site = %Site{id: 4, domain: "example.com"}

    assert URL.site_action_path(site, "make-public") == "/sites/s/4/make-public"
  end
end
