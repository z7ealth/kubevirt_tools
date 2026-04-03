# Seeds N Fedora VMs from `dv_fedora_vm.yaml` + `fedora_vm.yaml` templates (same layout as
# ~/Projects/kubevirt). Override template dir with KUBEVIRT_TEMPLATE_DIR if you want to read
# those files directly.
#
#   mix run priv/seed_fedora_vms.exs
#
# Env (optional):
#   KUBECONFIG              — kubeconfig path (default: ~/.kube/config)
#   KUBEVIRT_TEMPLATE_DIR   — directory containing dv_fedora_vm.yaml + fedora_vm.yaml
#   VM_NAMESPACE            — default: virt
#   VM_COUNT                — default: 8
#   VM_CORES                — default: 1
#   VM_MEMORY               — default: 2Gi
#   VM_DISK                 — default: 30Gi
#   STORAGE_CLASS           — default: standard (from template; override if needed)
#   VM_SSH_KEY              — optional; appended to cloud-init as ssh_authorized_keys
#
# Requires a running OTP app (`mix run` without `--no-start`) so :k8s can reach the API.
#

defmodule KubevirtTools.SeedFedoraVms do
  @moduledoc false

  def main do
    count = env_int("VM_COUNT", 8)
    ns = System.get_env("VM_NAMESPACE", "virt")
    cores = env_int("VM_CORES", 1)
    memory = System.get_env("VM_MEMORY", "2Gi")
    disk = System.get_env("VM_DISK", "30Gi")
    storage_class = System.get_env("STORAGE_CLASS", "standard")
    ssh_key = System.get_env("VM_SSH_KEY", "") |> String.trim()

    template_dir = template_root()
    dv_path = Path.join(template_dir, "dv_fedora_vm.yaml")
    vm_path = Path.join(template_dir, "fedora_vm.yaml")

    unless File.exists?(dv_path) and File.exists?(vm_path) do
      IO.puts(:stderr, "Missing #{dv_path} or #{vm_path}")
      System.halt(1)
    end

    {:ok, conn} =
      case kube_conn() do
        {:ok, _} = ok ->
          ok

        {:error, reason} ->
          IO.puts(:stderr, "Kubeconfig: #{inspect(reason)}")
          System.halt(1)
      end

    base_dv = K8s.Resource.from_file!(dv_path, [])
    base_vm = K8s.Resource.from_file!(vm_path, [])

    for i <- 1..count do
      vm_name = "fedora-vm-#{i}"
      dv_name = "fedora-vm-#{i}-dv"

      dv =
        base_dv
        |> put_in(["metadata", "name"], dv_name)
        |> put_in(["metadata", "namespace"], ns)
        |> put_in(["spec", "storage", "storageClassName"], storage_class)
        |> put_in(["spec", "storage", "resources", "requests", "storage"], disk)

      vm =
        base_vm
        |> put_in(["metadata", "name"], vm_name)
        |> put_in(["metadata", "namespace"], ns)
        |> put_in(["spec", "template", "spec", "domain", "cpu", "cores"], cores)
        |> put_in(["spec", "template", "spec", "domain", "resources", "requests", "memory"], memory)
        |> update_in(["spec", "template", "spec", "volumes"], fn vols ->
          Enum.map(vols, fn
            %{"name" => "disk0"} = v ->
              put_in(v, ["persistentVolumeClaim", "claimName"], dv_name)

            %{"name" => "cloudinitdisk", "cloudInitNoCloud" => %{"userData" => ud}} = v ->
              ud2 = cloud_init_for_vm(ud, vm_name, ssh_key)
              put_in(v, ["cloudInitNoCloud", "userData"], ud2)

            v ->
              v
          end)
        end)

      :ok = apply_resource!(conn, dv)
      IO.puts("Applied DataVolume #{ns}/#{dv_name}")

      :ok = apply_resource!(conn, vm)
      IO.puts("Applied VirtualMachine #{ns}/#{vm_name}")
    end

    IO.puts("Done. Created or updated #{count} VM(s) in namespace #{inspect(ns)}.")
  end

  defp cloud_init_for_vm(user_data, hostname, ssh_key) do
    ud =
      user_data
      |> String.replace("hostname: fedora-vm", "hostname: #{hostname}")

    if ssh_key != "" do
      String.trim_trailing(ud) <>
        "\n            ssh_authorized_keys:\n            - #{ssh_key}\n"
    else
      ud
    end
  end

  defp apply_resource!(conn, resource) do
    op =
      K8s.Client.apply(resource,
        field_manager: "kubevirt-tools-seed",
        force: true
      )

    case K8s.Client.run(conn, op) do
      {:ok, _} ->
        :ok

      {:error, err} ->
        IO.puts(:stderr, "Apply failed: #{inspect(err)}")
        System.halt(1)
    end
  end

  defp template_root do
    case System.get_env("KUBEVIRT_TEMPLATE_DIR") do
      dir when is_binary(dir) and dir != "" ->
        Path.expand(dir)

      _ ->
        Path.join(Path.dirname(__ENV__.file), "kubevirt_templates")
    end
  end

  defp kube_conn do
    path =
      case System.get_env("KUBECONFIG") do
        p when is_binary(p) and p != "" -> Path.expand(p)
        _ -> Path.expand("~/.kube/config")
      end

    K8s.Conn.from_file(path)
  end

  defp env_int(name, default) do
    case System.get_env(name) do
      nil -> default
      "" -> default
      s -> String.to_integer(String.trim(s))
    end
  end
end

KubevirtTools.SeedFedoraVms.main()
