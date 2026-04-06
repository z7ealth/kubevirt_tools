defmodule KubevirtTools.DashboardCharts do
  @moduledoc "Builds ApexCharts option maps for the KubeVirt dashboard."

  # DaisyUI semantic tokens — series and chrome track `data-theme` (light/dark).
  @colors %{
    green: "var(--color-success)",
    # Stopped / “negative” slices — soft red (`--color-stopped` in app.css), not alert `--color-error`.
    red: "var(--color-stopped)",
    amber: "var(--color-warning)",
    blue: "var(--color-info)",
    violet: "var(--color-accent)",
    slate: "var(--color-neutral)"
  }

  @empty_series_color "var(--color-base-300)"

  defp axis_label_style(font_size) when font_size in ["10px", "11px"] do
    %{
      "colors" => "color-mix(in oklch, var(--color-base-content) 48%, transparent)",
      "fontSize" => font_size
    }
  end

  def base_theme do
    %{
      "chart" => %{
        "type" => "bar",
        "fontFamily" => "Bitter, ui-serif, Georgia, Cambria, serif",
        "toolbar" => %{"show" => false},
        "background" => "transparent",
        "foreColor" => "var(--color-base-content)",
        "animations" => %{"enabled" => true, "speed" => 400},
        "offsetX" => 0,
        "offsetY" => 0,
        "parentHeightOffset" => 0
      },
      "dataLabels" => %{"enabled" => false},
      "grid" => %{
        "borderColor" => "color-mix(in oklch, var(--color-base-content) 12%, transparent)",
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
      "tooltip" => %{
        "theme" => false,
        # Default pie/donut uses fillSeriesColor: true → teal row bg + dark foreColor = unreadable.
        "fillSeriesColor" => false
      }
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
      "labels" => %{
        "colors" => "color-mix(in oklch, var(--color-base-content) 52%, transparent)"
      }
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
        {[1], [Keyword.get(opts, :empty_label, "No data")], [@empty_series_color]}
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
  and not ready (other phases or NotReady condition).
  """
  def node_scheduling_donut(schedulable, cordoned, not_ready)
      when is_integer(schedulable) and is_integer(cordoned) and is_integer(not_ready) do
    labels = ["Schedulable", "Cordoned", "Not ready"]
    series = [schedulable, cordoned, not_ready]

    {series, labels, colors} =
      if Enum.sum(series) == 0 do
        {[1], ["No nodes"], [@empty_series_color]}
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

  @doc """
  Pixel height for horizontal per-node bar charts so many nodes stay readable (scroll page / card).
  """
  def node_horizontal_chart_height_px(category_count)
      when is_integer(category_count) and category_count >= 0 do
    cond do
      category_count <= 0 -> 200
      category_count == 1 -> 200
      category_count <= 3 -> 228
      category_count <= 6 -> 280
      category_count <= 12 -> min(520, 44 * category_count + 80)
      true -> min(640, 36 * category_count + 100)
    end
  end

  @doc """
  Horizontal bars: one row per node (scales better than vertical columns for many nodes).
  """
  def vms_per_node_bar(labels, counts) do
    labels = List.wrap(labels)
    counts = List.wrap(counts)
    n = length(labels)
    h = node_horizontal_chart_height_px(n)

    chart_with_opts(%{
      "chart" => %{"type" => "bar", "height" => h},
      "series" => [%{"name" => "VMIs", "data" => counts}],
      "plotOptions" => %{
        "bar" => %{
          "horizontal" => true,
          "borderRadius" => 3,
          "barHeight" => bar_height_percent(n)
        }
      },
      "xaxis" => %{
        "categories" => labels,
        "labels" => %{
          "trim" => true,
          "maxHeight" => 120,
          "style" => axis_label_style("10px")
        }
      },
      "yaxis" => %{
        "labels" => %{
          "maxWidth" => 220,
          "style" => axis_label_style("10px")
        }
      },
      "colors" => [@colors.blue],
      "legend" => %{"show" => false},
      "grid" => %{"padding" => %{"left" => 8, "right" => 10, "top" => 6, "bottom" => 8}}
    })
  end

  @doc false
  def vmis_per_node_bar(labels, counts), do: vms_per_node_bar(labels, counts)

  def horizontal_bar(title, categories, values, color \\ nil) do
    color = color || @colors.red
    n = length(categories)
    h = node_horizontal_chart_height_px(n)

    chart_with_opts(%{
      "chart" => %{"type" => "bar", "height" => h},
      "series" => [%{"name" => title, "data" => values}],
      "plotOptions" => %{
        "bar" => %{
          "horizontal" => true,
          "borderRadius" => 3,
          "barHeight" => bar_height_percent(n)
        }
      },
      "xaxis" => %{
        "categories" => categories,
        "labels" => %{
          "trim" => true,
          "style" => axis_label_style("10px")
        }
      },
      "yaxis" => %{
        "labels" => %{
          "maxWidth" => 220,
          "style" => axis_label_style("10px")
        }
      },
      "colors" => [color],
      "legend" => %{"show" => false},
      "grid" => %{"padding" => %{"left" => 8, "right" => 10, "top" => 6, "bottom" => 8}}
    })
  end

  defp bar_height_percent(n) when n <= 1, do: "78%"
  defp bar_height_percent(n) when n <= 4, do: "72%"
  defp bar_height_percent(n) when n <= 10, do: "68%"
  defp bar_height_percent(_n), do: "62%"

  def pvc_storage_class_pie(labels, series) do
    {labels, series, pie_colors} =
      if labels == [] or Enum.sum(series) == 0 do
        {["No PVCs"], [1], [@empty_series_color]}
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
        {[1], ["No PVCs"], [@empty_series_color]}
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
    n = length(categories)
    h = max(220, node_horizontal_chart_height_px(n))

    # Same token as memory / “healthy” donuts — `info` is a brighter cyan in our theme.
    chart_with_opts(%{
      "chart" => %{"type" => "bar", "height" => h},
      "series" => [%{"name" => "Nodes", "data" => values}],
      "plotOptions" => %{
        "bar" => %{
          "horizontal" => true,
          "borderRadius" => 3,
          "barHeight" => bar_height_percent(n)
        }
      },
      "xaxis" => %{
        "categories" => categories,
        "labels" => %{"style" => axis_label_style("11px")}
      },
      "yaxis" => %{
        "labels" => %{
          "maxWidth" => 120,
          "style" => axis_label_style("11px")
        }
      },
      "colors" => [@colors.green],
      "legend" => %{"show" => false},
      "grid" => %{"padding" => %{"left" => 12, "right" => 8, "top" => 4, "bottom" => 28}}
    })
  end
end
