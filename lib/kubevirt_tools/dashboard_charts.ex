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
          "left" => 16,
          "right" => 20,
          "top" => 12,
          "bottom" => 12
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
      "offsetY" => 4,
      "height" => 52,
      "fontSize" => "11px",
      "itemMargin" => %{"horizontal" => 10, "vertical" => 3},
      "markers" => %{"width" => 8, "height" => 8, "radius" => 2},
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
      "chart" => %{"type" => "donut"},
      "series" => series,
      "labels" => labels,
      "colors" => colors,
      "legend" => %{
        "position" => "bottom",
        "horizontalAlign" => "center",
        "offsetY" => 2,
        "height" => 56,
        "itemMargin" => %{"horizontal" => 8, "vertical" => 4}
      },
      "plotOptions" => %{
        "pie" => %{
          "donut" => %{
            "size" => "58%",
            "labels" => %{
              "show" => true,
              "name" => %{"show" => true},
              "value" => %{"show" => true}
            }
          }
        }
      },
      "stroke" => %{"width" => 0},
      "grid" => %{"padding" => %{"bottom" => 8, "top" => 4}}
    })
  end

  def vms_per_node_bar(labels, counts) when is_list(labels) and is_list(counts) do
    chart_with_opts(%{
      "chart" => %{"type" => "bar", "height" => 280},
      "series" => [%{"name" => "VMIs", "data" => counts}],
      "xaxis" => %{
        "categories" => labels,
        "labels" => %{
          "rotate" => -35,
          "rotateAlways" => false,
          "maxHeight" => 72,
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
      "plotOptions" => %{"bar" => %{"borderRadius" => 4, "columnWidth" => "58%"}},
      "legend" => %{"show" => false},
      "grid" => %{"padding" => %{"bottom" => 20, "left" => 8, "right" => 8}}
    })
  end

  def horizontal_bar(title, categories, values, color \\ nil) do
    color = color || @colors.red

    chart_with_opts(%{
      "chart" => %{"type" => "bar", "height" => 280},
      "series" => [%{"name" => title, "data" => values}],
      "plotOptions" => %{
        "bar" => %{"horizontal" => true, "borderRadius" => 4, "barHeight" => "65%"}
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
      "grid" => %{"padding" => %{"left" => 28, "right" => 20, "top" => 10, "bottom" => 14}}
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
      "chart" => %{"type" => "pie"},
      "series" => series,
      "labels" => labels,
      "colors" => pie_colors,
      "legend" => %{
        "position" => "bottom",
        "horizontalAlign" => "center",
        "offsetY" => 4,
        "height" => 52,
        "itemMargin" => %{"horizontal" => 8, "vertical" => 3}
      },
      "stroke" => %{"width" => 0},
      "plotOptions" => %{"pie" => %{"expandOnClick" => false}},
      "grid" => %{"padding" => %{"bottom" => 6, "top" => 4}}
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
      "chart" => %{"type" => "donut"},
      "series" => series,
      "labels" => labels,
      "colors" => colors,
      "legend" => %{
        "position" => "bottom",
        "horizontalAlign" => "center",
        "offsetY" => 2,
        "height" => 58,
        "itemMargin" => %{"horizontal" => 6, "vertical" => 4}
      },
      "plotOptions" => %{
        "pie" => %{
          "donut" => %{"size" => "56%"}
        }
      },
      "stroke" => %{"width" => 0},
      "grid" => %{"padding" => %{"bottom" => 8, "top" => 4}}
    })
  end

  def node_load_placeholder(categories, values) do
    chart_with_opts(%{
      "chart" => %{"type" => "bar", "height" => 280},
      "series" => [%{"name" => "Nodes", "data" => values}],
      "plotOptions" => %{
        "bar" => %{"horizontal" => true, "borderRadius" => 4, "barHeight" => "65%"}
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
      "grid" => %{"padding" => %{"left" => 28, "right" => 20, "top" => 8, "bottom" => 36}},
      "subtitle" => %{
        "text" => "Placeholder — wire metrics-server / Prometheus for real load",
        "align" => "left",
        "offsetY" => 6,
        "style" => %{"color" => "#737373", "fontSize" => "11px"}
      }
    })
  end
end
