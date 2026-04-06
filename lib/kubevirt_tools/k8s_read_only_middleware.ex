defmodule KubevirtTools.K8sReadOnlyMiddleware do
  @moduledoc """
  Rejects Kubernetes API calls that are not safe reads (`GET`).

  Prepended to `K8s.Conn.middleware` so **create / update / patch / delete**
  never reach the cluster from this application, even if the uploaded kubeconfig
  grants those permissions.
  """

  @behaviour K8s.Middleware.Request

  alias K8s.Middleware.Request

  @impl true
  def call(%Request{method: :get} = req), do: {:ok, req}

  def call(%Request{method: _method}) do
    {:error,
     {:read_only_cluster,
      "KubeVirt Tools only allows read-only API access — mutating requests are not permitted."}}
  end
end
