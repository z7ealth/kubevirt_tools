defmodule KubevirtTools.DashboardCharts do
  @moduledoc "Builds ApexCharts option maps for the KubeVirt dashboard."

  @colors %{
    green: "#22c55e",
    red: "#ef4444",
    amber: "#eab308",
    blue: "#38bdf8",
    violet: "#a78bfa",
    slate: "#94a3b8"
  }

  def base_theme do
    %{
      "chart" => %{
        "type" => "bar",
        "toolbar" => %{"show" => false},
        "background" => "transparent",
        "foreColor" => "#d4d4d4",
        "animations" => %{"enabled" => true, "speed" => 400},
        "offsetX" => 0,
        "offsetY" => 0,
        "parentHeightOffset" => 0
      },
      "theme" => %{"mode" => "dark"},
      "dataLabels" => %{"enabled" => false},
      "grid" => %{
        "borderColor" => "rgba(255,255,255,0.08)",
        "strokeDashArray" => 4,
        "padding" => %{
          "left" => 8,
          "right" => 8,
          "top" => 6,
          "bottom" => 6
        },
        "xaxis" => %{"lines" => %{"show" => true}},
        "yaxis" => %{"lines" => %{"show" => false}}
      },
      "legend" => legend_bottom_compact(),
      "tooltip" => %{"theme" => "dark"}
    }
  end

  defp legend_bottom_compact do
    %{
      "show" => true,
      "position" => "bottom",
      "horizontalAlign" => "center",
      "floating" => false,
      "offsetY" => 0,
      "height" => 36,
      "fontSize" => "10px",
      "itemMargin" => %{"horizontal" => 6, "vertical" => 2},
      "markers" => %{"width" => 6, "height" => 6, "radius" => 2},
      "labels" => %{"colors" => "#a3a3a3"}
    }
  end

  @doc """
  Merges user `opts` into the shared dark theme.
  Deep-merges: chart, grid, legend, plotOptions, xaxis, yaxis, stroke, subtitle.
  """
  def chart_with_opts(extra_opts) when is_map(extra_opts) do
    base = base_theme()

    base
    |> Map.merge(Map.drop(extra_opts, deep_keys()))
    |> then(fn merged ->
      Enum.reduce(deep_keys(), merged, fn key, acc ->
        Map.put(acc, key, deep_merge_map(Map.get(base, key, %{}), Map.get(extra_opts, key, %{})))
      end)
    end)
  end

  defp deep_keys,
    do: ~w(chart grid legend plotOptions xaxis yaxis stroke subtitle)

  defp deep_merge_map(a, b) when is_map(a) and is_map(b) do
    Map.merge(a, b, fn
      _k, va, vb when is_map(va) and is_map(vb) -> deep_merge_map(va, vb)
      _k, _va, vb -> vb
    end)
  end

  defp deep_merge_map(_, b) when is_map(b), do: b
  defp deep_merge_map(a, _), do: a

  def vm_status_donut(running, stopped, other, opts \\ []) do
    labels = Keyword.get(opts, :labels, ["Running", "Stopped", "Other"])
    series = [running, stopped, other]

    {series, labels, colors} =
      if Enum.sum(series) == 0 do
        {[1], [Keyword.get(opts, :empty_label, "No data")], ["#64748b"]}
      else
        {series, labels, [@colors.green, @colors.red, @colors.amber]}
      end

    chart_with_opts(%{
      "chart" => %{"type" => "donut", "height" => 200},
      "series" => series,
      "labels" => labels,
      "colors" => colors,
      "legend" => %{
        "position" => "bottom",
        "horizontalAlign" => "center",
        "offsetY" => 0,
        "height" => 38,
        "fontSize" => "10px",
        "itemMargin" => %{"horizontal" => 6, "vertical" => 2}
      },
      "plotOptions" => %{
        "pie" => %{
          "donut" => %{
            "size" => "72%",
            "labels" => %{
              "show" => true,
              "name" => %{"show" => true, "fontSize" => "11px"},
              "value" => %{"show" => true, "fontSize" => "11px"}
            }
          }
        }
      },
      "stroke" => %{"width" => 0},
      "grid" => %{"padding" => %{"bottom" => 4, "top" => 2}}
    })
  end

  @doc """
  Donut for Kubernetes nodes: schedulable (Ready, not cordoned), cordoned (Ready + unschedulable),
  not ready — similar to vSphere hosts connected vs maintenance vs failed.
  """
  def node_scheduling_donut(schedulable, cordoned, not_ready)
      when is_integer(schedulable) and is_integer(cordoned) and is_integer(not_ready) do
    labels = ["Schedulable", "Cordoned", "Not ready"]
    series = [schedulable, cordoned, not_ready]

    {series, labels, colors} =
      if Enum.sum(series) == 0 do
        {[1], ["No nodes"], ["#64748b"]}
      else
        {series, labels, [@colors.green, @colors.amber, @colors.red]}
      end

    chart_with_opts(%{
      "chart" => %{"type" => "donut", "height" => 200},
      "series" => series,
      "labels" => labels,
      "colors" => colors,
      "legend" => %{
        "position" => "bottom",
        "horizontalAlign" => "center",
        "offsetY" => 0,
        "height" => 38,
        "fontSize" => "10px",
        "itemMargin" => %{"horizontal" => 5, "vertical" => 2}
      },
      "plotOptions" => %{
        "pie" => %{
          "donut" => %{
            "size" => "72%",
            "labels" => %{
              "show" => true,
              "name" => %{"show" => true, "fontSize" => "11px"},
              "value" => %{"show" => true, "fontSize" => "11px"}
            }
          }
        }
      },
      "stroke" => %{"width" => 0},
      "grid" => %{"padding" => %{"bottom" => 4, "top" => 2}}
    })
  end

  def vms_per_node_bar(labels, counts) when is_list(labels) and is_list(counts) do
    chart_with_opts(%{
      "chart" => %{"type" => "bar", "height" => 200},
      "series" => [%{"name" => "VMIs", "data" => counts}],
      "xaxis" => %{
        "categories" => labels,
        "labels" => %{
          "rotate" => -35,
          "rotateAlways" => false,
          "maxHeight" => 48,
          "trim" => true,
          "style" => %{"colors" => "#a3a3a3", "fontSize" => "11px"}
        }
      },
      "yaxis" => %{
        "min" => 0,
        "decimalsInFloat" => 0,
        "labels" => %{"style" => %{"colors" => "#a3a3a3", "fontSize" => "11px"}}
      },
      "colors" => [@colors.blue],
      "plotOptions" => %{"bar" => %{"borderRadius" => 3, "columnWidth" => "55%"}},
      "legend" => %{"show" => false},
      "grid" => %{"padding" => %{"bottom" => 8, "left" => 4, "right" => 4, "top" => 4}}
    })
  end

  def horizontal_bar(title, categories, values, color \\ nil) do
    color = color || @colors.red

    chart_with_opts(%{
      "chart" => %{"type" => "bar", "height" => 200},
      "series" => [%{"name" => title, "data" => values}],
      "plotOptions" => %{
        "bar" => %{"horizontal" => true, "borderRadius" => 3, "barHeight" => "75%"}
      },
      "xaxis" => %{
        "categories" => categories,
        "labels" => %{"style" => %{"colors" => "#a3a3a3", "fontSize" => "11px"}}
      },
      "yaxis" => %{
        "labels" => %{
          "maxWidth" => 160,
          "style" => %{"colors" => "#a3a3a3", "fontSize" => "11px"}
        }
      },
      "colors" => [color],
      "legend" => %{"show" => false},
      "grid" => %{"padding" => %{"left" => 12, "right" => 8, "top" => 4, "bottom" => 6}}
    })
  end

  def pvc_storage_class_pie(labels, series) do
    {labels, series, pie_colors} =
      if labels == [] or Enum.sum(series) == 0 do
        {["No PVCs"], [1], ["#64748b"]}
      else
        {labels, series,
         [
           @colors.blue,
           @colors.violet,
           @colors.green,
           @colors.amber,
           @colors.red,
           @colors.slate
         ]}
      end

    chart_with_opts(%{
      "chart" => %{"type" => "pie", "height" => 200},
      "series" => series,
      "labels" => labels,
      "colors" => pie_colors,
      "legend" => %{
        "position" => "bottom",
        "horizontalAlign" => "center",
        "offsetY" => 0,
        "height" => 36,
        "fontSize" => "10px",
        "itemMargin" => %{"horizontal" => 6, "vertical" => 2}
      },
      "stroke" => %{"width" => 0},
      "plotOptions" => %{"pie" => %{"expandOnClick" => false}},
      "grid" => %{"padding" => %{"bottom" => 4, "top" => 2}}
    })
  end

  def pvc_status_donut(bound, pending, lost, other) do
    series = [bound, pending, lost, other]

    {series, labels, colors} =
      if Enum.sum(series) == 0 do
        {[1], ["No PVCs"], ["#64748b"]}
      else
        {series, ["Bound", "Pending", "Lost", "Other"],
         [@colors.green, @colors.amber, @colors.red, @colors.slate]}
      end

    chart_with_opts(%{
      "chart" => %{"type" => "donut", "height" => 200},
      "series" => series,
      "labels" => labels,
      "colors" => colors,
      "legend" => %{
        "position" => "bottom",
        "horizontalAlign" => "center",
        "offsetY" => 0,
        "height" => 40,
        "fontSize" => "10px",
        "itemMargin" => %{"horizontal" => 5, "vertical" => 2}
      },
      "plotOptions" => %{
        "pie" => %{
          "donut" => %{"size" => "70%"}
        }
      },
      "stroke" => %{"width" => 0},
      "grid" => %{"padding" => %{"bottom" => 4, "top" => 2}}
    })
  end

  def node_load_placeholder(categories, values) do
    chart_with_opts(%{
      "chart" => %{"type" => "bar", "height" => 220},
      "series" => [%{"name" => "Nodes", "data" => values}],
      "plotOptions" => %{
        "bar" => %{"horizontal" => true, "borderRadius" => 3, "barHeight" => "72%"}
      },
      "xaxis" => %{
        "categories" => categories,
        "labels" => %{"style" => %{"colors" => "#a3a3a3", "fontSize" => "11px"}}
      },
      "yaxis" => %{
        "labels" => %{"maxWidth" => 72, "style" => %{"colors" => "#a3a3a3", "fontSize" => "11px"}}
      },
      "colors" => [@colors.violet],
      "legend" => %{"show" => false},
      "grid" => %{"padding" => %{"left" => 12, "right" => 8, "top" => 4, "bottom" => 28}}
    })
  end
end
