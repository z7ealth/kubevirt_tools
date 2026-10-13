defmodule KubevirtToolsWeb.ChartComponents do
  @moduledoc """
  Reusable [ApexCharts](https://apexcharts.com/) mount via a colocated LiveView hook.

  Pass a full ApexCharts options map as `opts` (atoms keys are JSON-encoded as strings).
  The hook decodes `data-chart-opts-b64` on mount/update and calls `ApexCharts` accordingly.
  """
  use Phoenix.Component

  import KubevirtToolsWeb.CoreComponents, only: [banner: 1]

  @doc """
  Renders a chart. **Required:** unique `id` (include a version suffix when data refreshes).

  - `opts` — ApexCharts options map (serializable with Jason).
  - `title` — optional card title above the chart.
  - `height` — fixed CSS height for the plot area so cards stay compact (default ~200px).
  - `dependency_overlay` — when set, dims the plot and shows a warning banner explaining
    what must be installed or configured (e.g. Prometheus).
  """
  attr :id, :string, required: true
  attr :opts, :map, required: true
  attr :title, :string, default: nil
  attr :class, :any, default: nil
  attr :height, :string, default: "200px"
  attr :dependency_overlay, :string, default: nil

  def apex_chart(assigns) do
    json = Jason.encode!(assigns.opts)
    b64 = Base.encode64(json)
    assigns = assign(assigns, :opts_b64, b64)

    ~H"""
    <section class={[
      "rounded-pp-md border border-pp-outline-variant bg-pp-surface",
      "p-4 min-w-0 w-full overflow-hidden flex flex-col gap-2",
      @class
    ]}>
      <h3
        :if={@title}
        class="pp-title-small text-pp-on-surface-variant shrink-0"
      >
        {@title}
      </h3>
      <div class="relative w-full min-w-0 shrink-0" style={"height: #{@height};"}>
        <div
          :if={@dependency_overlay}
          class={[
            "absolute inset-0 z-20 flex items-center justify-center p-2 rounded-pp-sm",
            "bg-pp-surface-container/70 backdrop-blur-[3px]"
          ]}
        >
          <.banner
            kind={:warning}
            icon="hero-puzzle-piece"
            title="Setup required"
            class="max-h-full max-w-[min(100%,22rem)] overflow-y-auto pp-elevation-2"
          >
            {@dependency_overlay}
          </.banner>
        </div>
        <div
          id={@id}
          phx-hook=".ApexChart"
          class={[
            "absolute inset-0 w-full min-w-0 apex-chart-canvas",
            @dependency_overlay && "opacity-[0.18] pointer-events-none select-none"
          ]}
          data-chart-opts-b64={@opts_b64}
        >
        </div>
      </div>
    </section>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".ApexChart">
      import ApexCharts from "apexcharts"

      function decodeOpts(el) {
        const b64 = el.dataset.chartOptsB64
        if (!b64) return null
        try {
          const binary = atob(b64)
          const bytes = new Uint8Array(binary.length)
          for (let i = 0; i < binary.length; i++) {
            bytes[i] = binary.charCodeAt(i)
          }
          const json = new TextDecoder("utf-8").decode(bytes)
          return JSON.parse(json)
        } catch (e) {
          console.error("ApexChart: invalid chart opts", e)
          return null
        }
      }

      function hasLayoutSize(el) {
        const { width, height } = el.getBoundingClientRect()
        return width >= 2 && height >= 2
      }

      /**
       * ApexCharts v3 had chart.resize(); v4 removed the public API and uses
       * internal _windowResize() (same as the window "resize" listener) or updateOptions.
       */
      function refreshChartLayout(chart) {
        if (!chart) return
        if (typeof chart.resize === "function") {
          chart.resize()
          return
        }
        if (typeof chart._windowResize === "function") {
          chart._windowResize()
          return
        }
        if (typeof chart.updateOptions === "function") {
          try {
            chart.updateOptions({}, true, true, true)
          } catch (e) {
            console.error("ApexChart: updateOptions failed", e)
          }
          return
        }
        window.dispatchEvent(new Event("resize"))
      }

      export default {
        mounted() {
          this._optsB64 = null
          this._structuralJson = null
          this.chart = null
          this._resizeObserver = null
          this._layoutRaf = null
          this._tabPanelObserver = null
          this._intersectionObserver = null
          this._visibilityRetry = null
          this.bindResizeObserver()
          this.bindTabPanelObserver()
          this.bindIntersectionObserver()
          this.scheduleLayout()
        },
        updated() {
          // Deciding full-rebuild vs. smooth updateSeries needs the decoded
          // opts (see syncChart) — don't teardown here, just re-sync.
          this.scheduleLayout()
          this.scheduleLayoutDeferred()
        },
        destroyed() {
          if (this._resizeObserver) {
            this._resizeObserver.disconnect()
            this._resizeObserver = null
          }
          if (this._tabPanelObserver) {
            this._tabPanelObserver.disconnect()
            this._tabPanelObserver = null
          }
          if (this._intersectionObserver) {
            this._intersectionObserver.disconnect()
            this._intersectionObserver = null
          }
          if (this._visibilityRetry) {
            clearTimeout(this._visibilityRetry)
            this._visibilityRetry = null
          }
          if (this._layoutRaf) {
            cancelAnimationFrame(this._layoutRaf)
            this._layoutRaf = null
          }
          this.teardownChart()
        },
        bindResizeObserver() {
          this._resizeObserver = new ResizeObserver(() => this.scheduleLayout())
          this._resizeObserver.observe(this.el)
        },
        bindTabPanelObserver() {
          const panel = this.el.closest('[role="tabpanel"]')
          if (!panel) return
          this._tabPanelObserver = new MutationObserver(() => {
            this.scheduleLayout()
            this.scheduleLayoutDeferred()
          })
          this._tabPanelObserver.observe(panel, {
            attributes: true,
            attributeFilter: ["hidden", "class"]
          })
        },
        bindIntersectionObserver() {
          this._intersectionObserver = new IntersectionObserver(
            (entries) => {
              for (const e of entries) {
                if (e.isIntersecting) {
                  this.scheduleLayout()
                  this.scheduleLayoutDeferred()
                }
              }
            },
            { root: null, threshold: [0, 0.01, 0.5, 1] }
          )
          this._intersectionObserver.observe(this.el)
        },
        scheduleLayout() {
          if (this._layoutRaf) cancelAnimationFrame(this._layoutRaf)
          this._layoutRaf = requestAnimationFrame(() => {
            this._layoutRaf = null
            this.syncChart()
          })
        },
        scheduleLayoutDeferred() {
          if (this._visibilityRetry) {
            clearTimeout(this._visibilityRetry)
            this._visibilityRetry = null
          }
          requestAnimationFrame(() => {
            requestAnimationFrame(() => {
              this.scheduleLayout()
              this._visibilityRetry = setTimeout(() => {
                this._visibilityRetry = null
                this.scheduleLayout()
              }, 50)
            })
          })
        },
        teardownChart() {
          this._optsB64 = null
          this._structuralJson = null
          if (this.chart) {
            this.chart.destroy()
            this.chart = null
          }
        },
        syncChart() {
          const opts = decodeOpts(this.el)
          if (!opts) return

          const b64 = this.el.dataset.chartOptsB64

          if (!hasLayoutSize(this.el)) {
            return
          }

          if (this.chart && b64 === this._optsB64) {
            refreshChartLayout(this.chart)
            requestAnimationFrame(() => {
              if (this.chart && this.el.dataset.chartOptsB64 === b64) {
                refreshChartLayout(this.chart)
              }
            })
            return
          }

          // Only the series data changed (new poll, same chart shape/config) —
          // animate the transition in place instead of destroying and
          // re-rendering the whole chart, which flashes/redraws visibly.
          const { series, ...structural } = opts
          const structuralJson = JSON.stringify(structural)

          if (this.chart && structuralJson === this._structuralJson) {
            this._optsB64 = b64
            this.chart.updateSeries(series, true)
            refreshChartLayout(this.chart)
            requestAnimationFrame(() => {
              if (this.chart) refreshChartLayout(this.chart)
            })
            return
          }

          this.teardownChart()
          this._optsB64 = b64
          this._structuralJson = structuralJson
          this.chart = new ApexCharts(this.el, opts)
          const chart = this.chart
          const afterRender = () => {
            if (!this.chart || this.chart !== chart) return
            refreshChartLayout(this.chart)
            requestAnimationFrame(() => {
              if (this.chart === chart) refreshChartLayout(this.chart)
            })
          }
          const p = this.chart.render()
          if (p && typeof p.then === "function") {
            p.then(afterRender).catch((e) => console.error("ApexChart: render failed", e))
          } else {
            afterRender()
          }
        }
      }
    </script>
    """
  end
end
