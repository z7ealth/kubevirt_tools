import { Network } from "vis-network"
import { DataSet } from "vis-data"

function truncate(s, max) {
  if (s.length <= max) return s
  return s.slice(0, Math.max(0, max - 1)) + "…"
}

/** Read theme tokens from `[data-vm-topology-root]` (Daisy `--color-*` via app.css). */
function readTopologyTheme(el) {
  const s = getComputedStyle(el)
  const v = (name, fallback) => {
    const x = s.getPropertyValue(name).trim()
    return x || fallback
  }

  const pair = (bg, border, hiBg, hiBorder, hoverBg, hoverBorder) => ({
    background: bg,
    border,
    highlight: { background: hiBg, border: hiBorder },
    hover: { background: hoverBg, border: hoverBorder },
  })

  const hoverBg = v("--topology-hover-bg", "#ffffff")
  const hoverBorder = v("--topology-hover-border", "#0d5c56")

  return {
    canvasBg: v("--topology-canvas-bg", "#1a2332"),
    shadow: v("--topology-shadow", "rgba(0,0,0,0.25)"),
    edge: v("--topology-edge", "#64748b"),
    edgeHighlight: v("--topology-edge-hover-accent", "#0d5c56"),
    edgeHover: v("--topology-edge-hover-accent", "#0d5c56"),
    hoverLabel: v("--topology-hover-label", "#0a4a45"),
    nodeLabel: v("--topology-node-label", "#e2e8f0"),
    hostReady: pair(
      v("--topology-hr-bg", "#1e3a5f"),
      v("--topology-hr-border", "#3b82f6"),
      v("--topology-hr-hi-bg", "#2563eb"),
      v("--topology-hr-hi-border", "#60a5fa"),
      hoverBg,
      hoverBorder
    ),
    hostCordoned: pair(
      v("--topology-hc-bg", "#5c2e0a"),
      v("--topology-hc-border", "#ea580c"),
      v("--topology-hc-hi-bg", "#c2410c"),
      v("--topology-hc-hi-border", "#fb923c"),
      hoverBg,
      hoverBorder
    ),
    hostDown: pair(
      v("--topology-hd-bg", "#5c1a1a"),
      v("--topology-hd-border", "#dc2626"),
      v("--topology-hd-hi-bg", "#991b1b"),
      v("--topology-hd-hi-border", "#f87171"),
      hoverBg,
      hoverBorder
    ),
    hostUnsched: pair(
      v("--topology-hu-bg", "#5c1a1a"),
      v("--topology-hu-border", "#dc2626"),
      v("--topology-hu-hi-bg", "#991b1b"),
      v("--topology-hu-hi-border", "#f87171"),
      hoverBg,
      hoverBorder
    ),
    vmRunning: pair(
      v("--topology-vr-bg", "#14532d"),
      v("--topology-vr-border", "#22c55e"),
      v("--topology-vr-hi-bg", "#166534"),
      v("--topology-vr-hi-border", "#4ade80"),
      hoverBg,
      hoverBorder
    ),
    vmStopped: pair(
      v("--topology-vs-bg", "#5c1a1a"),
      v("--topology-vs-border", "#ef4444"),
      v("--topology-vs-hi-bg", "#991b1b"),
      v("--topology-vs-hi-border", "#f87171"),
      hoverBg,
      hoverBorder
    ),
    vmOther: pair(
      v("--topology-vo-bg", "#5c3d0a"),
      v("--topology-vo-border", "#eab308"),
      v("--topology-vo-hi-bg", "#854d0e"),
      v("--topology-vo-hi-border", "#facc15"),
      hoverBg,
      hoverBorder
    ),
  }
}

function hostColors(hostStatus, t) {
  switch (hostStatus) {
    case "ready":
      return t.hostReady
    case "cordoned":
      return t.hostCordoned
    case "unscheduled":
      return t.hostUnsched
    default:
      return t.hostDown
  }
}

function vmColors(vmStatus, t) {
  switch (vmStatus) {
    case "running":
      return t.vmRunning
    case "stopped":
      return t.vmStopped
    default:
      return t.vmOther
  }
}

function mapVisNode(n, t) {
  if (n.group === "host") {
    const c = hostColors(n.hostStatus || "not_ready", t)
    return {
      id: n.id,
      label: truncate(n.label, 24),
      title: n.label,
      shape: "box",
      margin: 14,
      font: { color: t.nodeLabel, size: 13 },
      color: c,
      borderWidth: 2,
    }
  }

  const c = vmColors(n.vmStatus || "other", t)
  return {
    id: n.id,
    label: truncate(n.label, 20),
    title: n.label,
    shape: "dot",
    size: 16,
    font: { color: t.nodeLabel, size: 11 },
    color: c,
    borderWidth: 2,
  }
}

function baseOptions(t) {
  return {
    nodes: {
      shadow: {
        enabled: true,
        color: t.shadow,
        size: 12,
        x: 2,
        y: 2,
      },
      chosen: {
        node(values, _id, _selected, hovering) {
          if (hovering) {
            const prev = values.font && typeof values.font === "object" ? values.font : {}
            values.font = { ...prev, color: t.hoverLabel }
          }
        },
      },
    },
    edges: {
      color: { color: t.edge, highlight: t.edgeHighlight, hover: t.edgeHover },
      smooth: { type: "continuous", roundness: 0.35 },
      width: 1,
      chosen: {
        edge(values, _id, _selected, hovering) {
          if (hovering) {
            values.color = t.edgeHover
            values.width = Math.max(values.width || 1, 2)
          }
        },
      },
    },
    interaction: {
      hover: true,
      tooltipDelay: 120,
      navigationButtons: false,
      keyboard: false,
    },
  }
}

function physicsOrganic() {
  return {
    physics: {
      enabled: true,
      barnesHut: {
        gravitationalConstant: -14_000,
        centralGravity: 0.18,
        springLength: 200,
        springConstant: 0.045,
        damping: 0.55,
        avoidOverlap: 0.65,
      },
      stabilization: { iterations: 220, updateInterval: 25 },
    },
  }
}

function physicsHierarchical() {
  return {
    physics: {
      enabled: false,
    },
    layout: {
      hierarchical: {
        enabled: true,
        direction: "UD",
        sortMethod: "directed",
        levelSeparation: 160,
        nodeSpacing: 145,
        treeSpacing: 220,
        blockShifting: true,
        edgeMinimization: true,
        parentCentralization: true,
      },
    },
  }
}

function applySummary(el, summary) {
  const root = el.closest("[data-vm-topology-root]")
  if (!root || !summary) return
  const fmt = (k) => {
    const n = summary[k]
    return typeof n === "number" ? String(n) : "—"
  }
  const set = (sel, val) => {
    const node = root.querySelector(sel)
    if (node) node.textContent = val
  }
  set("[data-topology-summary-nodes]", fmt("nodes"))
  set("[data-topology-summary-vms]", fmt("vms"))
  set("[data-topology-summary-running]", fmt("running"))
  set("[data-topology-summary-stopped]", fmt("stopped"))
}

export const VmTopologyHook = {
  mounted() {
    this._onClick = (e) => this.handleClick(e)
    this._onChange = (e) => this.handleChange(e)
    this._onTheme = () => this.rerenderForTheme()
    this.el.addEventListener("click", this._onClick)
    this.el.addEventListener("change", this._onChange)
    window.addEventListener("phx:set-theme", this._onTheme)
    this._io = null
    this.renderGraph()
    this.observeVisibility()
  },

  updated() {
    this.renderGraph()
    this.observeVisibility()
  },

  destroyed() {
    this.el.removeEventListener("click", this._onClick)
    this.el.removeEventListener("change", this._onChange)
    window.removeEventListener("phx:set-theme", this._onTheme)
    if (this._io) {
      this._io.disconnect()
      this._io = null
    }
    this.destroyNetwork()
  },

  rerenderForTheme() {
    if (!this.network) return
    this.destroyNetwork()
    this.renderGraph()
  },

  observeVisibility() {
    if (this._io) this._io.disconnect()
    this._io = new IntersectionObserver(
      (entries) => {
        const e = entries[0]
        if (e?.isIntersecting && this.network) {
          requestAnimationFrame(() => {
            this.network.fit({ animation: false })
          })
        }
      },
      { threshold: 0.04 }
    )
    this._io.observe(this.el)
  },

  handleClick(e) {
    if (e.target.closest("[data-topology-fit]")) {
      this.network?.fit({ animation: { duration: 380, easingFunction: "easeInOutQuad" } })
    }
    if (e.target.closest("[data-topology-reset]")) {
      this.destroyNetwork()
      this.renderGraph()
    }
  },

  handleChange(e) {
    if (e.target.matches("[data-topology-layout]")) {
      this.destroyNetwork()
      this.renderGraph()
    }
  },

  destroyNetwork() {
    if (this.network) {
      this.network.destroy()
      this.network = null
    }
  },

  layoutMode() {
    const sel = this.el.querySelector("[data-topology-layout]")
    return sel?.value || "organic"
  },

  renderGraph() {
    const raw = this.el.dataset.topology
    if (!raw) return

    let payload
    try {
      payload = JSON.parse(raw)
    } catch {
      return
    }

    applySummary(this.el, payload.summary)

    const container = this.el.querySelector("[data-topology-canvas]")
    if (!container) return

    const theme = readTopologyTheme(this.el)
    const nodes = new DataSet((payload.nodes || []).map((n) => mapVisNode(n, theme)))
    const edges = new DataSet(payload.edges || [])

    this.destroyNetwork()

    const layout =
      this.layoutMode() === "hierarchical" ? physicsHierarchical() : physicsOrganic()

    const options = { ...baseOptions(theme), ...layout }

    this.network = new Network(container, { nodes, edges }, options)

    const bg = theme.canvasBg
    this.network.on("beforeDrawing", (ctx) => {
      // vis-network applies translate/scale before this event; filling in that space
      // draws a wrong-sized slab in “graph coordinates” (the darker rectangle artifact).
      const c = ctx.canvas
      ctx.save()
      ctx.setTransform(1, 0, 0, 1, 0, 0)
      ctx.fillStyle = bg
      ctx.fillRect(0, 0, c.width, c.height)
      ctx.restore()
    })
    this.network.redraw()

    if (this.layoutMode() === "hierarchical") {
      requestAnimationFrame(() => this.network.fit({ animation: false }))
    } else {
      this.network.once("stabilizationIterationsDone", () => {
        this.network.fit({ animation: false })
      })
    }
  },
}
