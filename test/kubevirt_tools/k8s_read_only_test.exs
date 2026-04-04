defmodule KubevirtTools.K8sReadOnlyTest do
  use ExUnit.Case, async: true

  alias K8s.Middleware.Request
  alias KubevirtTools.K8sConn
  alias KubevirtTools.K8sReadOnlyMiddleware

  @fixture Path.join(__DIR__, "../support/fixtures/minimal_kubeconfig.yaml")

  describe "K8sReadOnlyMiddleware" do
    test "allows GET" do
      req = %Request{
        method: :get,
        conn: nil,
        uri: URI.parse("https://example.test/api/v1/namespaces/default/pods"),
        body: nil,
        headers: [],
        opts: []
      }

      assert {:ok, %Request{method: :get}} = K8sReadOnlyMiddleware.call(req)
    end

    test "rejects mutating HTTP methods" do
      req = %Request{
        method: :post,
        conn: nil,
        uri: URI.parse("https://example.test/api/v1/namespaces/default/pods"),
        body: "{}",
        headers: [],
        opts: []
      }

      assert {:error, {:read_only_cluster, msg}} = K8sReadOnlyMiddleware.call(req)
      assert msg =~ "read-only"
      assert msg =~ "post"
    end
  end

  describe "K8sConn" do
    test "from_kubeconfig_string prepends read-only middleware" do
      yaml = File.read!(@fixture)
      assert {:ok, conn} = K8sConn.from_kubeconfig_string(yaml)
      assert hd(conn.middleware.request) == K8sReadOnlyMiddleware
    end
  end
end
