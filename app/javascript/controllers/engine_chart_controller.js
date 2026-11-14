import { Controller } from "@hotwired/stimulus"
import { t } from "i18n"

// Interactive viewer for engine monitor charts. Clicking a chart opens it large
// with higher-resolution data (fetched once, on first open): a crosshair shows
// every series' value at that moment, dragging across the chart zooms into that
// stretch of the flight, and the table shows min/avg/max for the visible range.
// Times are shown as monitor (local) time, like the peaks table.
const STEPS = [ 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600 ].map((s) => s * 1000)
const MIN_ZOOM_MS = 5000

export default class extends Controller {
  static targets = [ "dialog", "tabs", "canvas", "frame", "selection", "status", "stats", "range", "reset", "zoomOut" ]
  static values = { url: String }

  connect() {
    this.group = 0
    this.zoom = null // [min, max] in ms since epoch, or null for the whole recording
    this.restyle = () => this.chart?.update("none")
    window.addEventListener("theme:change", this.restyle)
  }

  disconnect() {
    window.removeEventListener("theme:change", this.restyle)
    this.chart?.destroy()
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  async open(event) {
    event.preventDefault()
    this.group = Number(event.params.group) || 0
    this.dialogTarget.showModal()
    try {
      this.series ||= await this.load()
      this.renderTabs()
      this.render()
    } catch (error) {
      this.statusTarget.hidden = false
      this.statusTarget.textContent = t("engine.load_failed", { message: error.message })
    }
  }

  close() {
    this.dialogTarget.close()
  }

  closed() {
    this.endDrag()
  }

  keydown(event) {
    if (event.target.closest("[role=tablist]") && (event.key === "ArrowRight" || event.key === "ArrowLeft")) {
      event.preventDefault()
      const count = this.series.groups.length
      this.select((this.group + (event.key === "ArrowRight" ? 1 : -1) + count) % count, true)
    }
  }

  async load() {
    const response = await fetch(this.urlValue, { headers: { Accept: "application/json" }, credentials: "same-origin" })
    const body = await response.json().catch(() => ({}))
    if (!response.ok) throw new Error(body.error || `HTTP ${response.status}`)
    const times = body.times.map((t) => body.started_at + t)
    return { ...body, times, end: times[times.length - 1], start: times[0] }
  }

  // ---- metric tabs ----

  renderTabs() {
    this.tabsTarget.replaceChildren(...this.series.groups.map((group, i) => {
      const tab = document.createElement("button")
      tab.type = "button"
      tab.setAttribute("role", "tab")
      tab.textContent = group.title
      tab.className = "shrink-0 rounded-md px-3 py-1.5 text-sm font-medium whitespace-nowrap"
      tab.addEventListener("click", () => this.select(i))
      return tab
    }))
    this.highlightTab()
  }

  highlightTab() {
    Array.from(this.tabsTarget.children).forEach((tab, i) => {
      const active = i === this.group
      tab.setAttribute("aria-selected", active)
      tab.tabIndex = active ? 0 : -1
      tab.classList.toggle("bg-accent", active)
      tab.classList.toggle("text-white", active)
      tab.classList.toggle("text-slate-600", !active)
      tab.classList.toggle("hover:bg-slate-100", !active)
    })
  }

  select(index, focus = false) {
    this.group = index
    this.highlightTab()
    if (focus) this.tabsTarget.children[index].focus()
    this.tabsTarget.children[index].scrollIntoView({ block: "nearest", inline: "nearest" })
    this.render()
  }

  // ---- chart ----

  render() {
    const { groups, channels, times } = this.series
    const group = groups[this.group]
    const datasets = group.keys.map((key, i) => {
      const channel = channels[key]
      const color = group.colors[i % group.colors.length]
      return {
        label: channel.label,
        unit: channel.unit,
        data: channel.values.map((y, j) => ({ x: times[j], y })),
        borderColor: color,
        backgroundColor: color,
        borderWidth: 1.5,
        pointRadius: 0,
        pointHoverRadius: 3,
        tension: 0
      }
    })

    this.chart?.destroy()
    this.statusTarget.hidden = true
    this.chart = new window.Chart(this.canvasTarget, {
      type: "line",
      data: { datasets },
      options: this.options(group, datasets.length > 1),
      plugins: [ crosshair ]
    })
    this.applyZoom()
  }

  options(group, legend) {
    const format = (ms, seconds) => this.clock(ms, seconds)
    return {
      animation: false,
      parsing: false,
      normalized: true,
      responsive: true,
      maintainAspectRatio: false,
      spanGaps: false,
      interaction: { mode: "index", intersect: false },
      scales: {
        x: {
          type: "linear",
          ticks: { maxRotation: 0, autoSkipPadding: 12, includeBounds: false, callback: (value) => format(value, this.step < 60000) }
        },
        y: { title: { display: true, text: group.unit } }
      },
      plugins: {
        legend: {
          display: legend,
          position: "bottom",
          labels: { boxWidth: 12, boxHeight: 2 },
          onClick: (event, item, legendBox) => {
            window.Chart.defaults.plugins.legend.onClick.call(legendBox, event, item, legendBox)
            this.renderStats()
          }
        },
        tooltip: {
          callbacks: {
            title: (items) => items.length ? format(items[0].parsed.x, true) : "",
            label: (item) => `${item.dataset.label}: ${number(item.parsed.y, item.dataset.unit)} ${item.dataset.unit}`
          }
        }
      }
    }
  }

  // ---- zoom ----

  applyZoom() {
    const [ min, max ] = this.zoom || [ this.series.start, this.series.end ]
    this.step = niceStep(max - min)
    const x = this.chart.options.scales.x
    x.min = min
    x.max = max
    x.ticks.stepSize = this.step
    this.chart.update("none")
    this.resetTarget.disabled = this.zoomOutTarget.disabled = !this.zoom
    this.rangeTarget.textContent = `${this.clock(min, true)} – ${this.clock(max, true)} (${duration(max - min)})`
    this.renderStats()
  }

  zoomTo(min, max) {
    const { start, end } = this.series
    if (max - min < MIN_ZOOM_MS) {
      const mid = (min + max) / 2
      min = mid - MIN_ZOOM_MS / 2
      max = mid + MIN_ZOOM_MS / 2
    }
    min = Math.max(start, min)
    max = Math.min(end, max)
    this.zoom = (min <= start && max >= end) ? null : [ min, max ]
    this.applyZoom()
  }

  zoomOut() {
    if (!this.zoom) return
    const [ min, max ] = this.zoom
    const half = max - min
    this.zoomTo(min - half / 2, max + half / 2)
  }

  resetZoom() {
    this.zoom = null
    if (this.chart) this.applyZoom()
  }

  // Drag across the plot area to select a time range.
  dragStart(event) {
    if (!this.chart || event.button > 0) return
    const x = this.plotX(event)
    const y = event.clientY - this.canvasTarget.getBoundingClientRect().top
    if (x == null || y < this.chart.chartArea.top || y > this.chart.chartArea.bottom) return // e.g. the legend
    this.drag = { from: x, to: x, pointer: event.pointerId }
  }

  dragMove(event) {
    if (!this.drag || event.pointerId !== this.drag.pointer) return
    this.drag.to = this.plotX(event, true)
    const left = Math.min(this.drag.from, this.drag.to)
    const width = Math.abs(this.drag.to - this.drag.from)
    if (width < 4) return
    // Capture only once it's really a drag, so plain clicks still reach the chart.
    if (!this.frameTarget.hasPointerCapture(event.pointerId)) this.frameTarget.setPointerCapture(event.pointerId)
    const area = this.chart.chartArea
    const offset = this.canvasTarget.offsetLeft
    Object.assign(this.selectionTarget.style, {
      left: `${offset + left}px`, width: `${width}px`,
      top: `${this.canvasTarget.offsetTop + area.top}px`, height: `${area.bottom - area.top}px`
    })
    this.selectionTarget.hidden = false
  }

  dragEnd(event) {
    if (!this.drag || event.pointerId !== this.drag.pointer) return
    const { from, to } = this.drag
    this.endDrag()
    if (Math.abs(to - from) < 8) return // a tap or click, not a drag
    const scale = this.chart.scales.x
    const area = this.chart.chartArea
    this.zoomTo(scale.getValueForPixel(area.left + Math.min(from, to)), scale.getValueForPixel(area.left + Math.max(from, to)))
  }

  dragCancel() {
    this.endDrag()
  }

  endDrag() {
    this.drag = null
    if (this.hasSelectionTarget) this.selectionTarget.hidden = true
  }

  // Pointer x within the chart's plot area (clamped when dragging out of it).
  plotX(event, clamp = false) {
    const area = this.chart.chartArea
    const x = event.clientX - this.canvasTarget.getBoundingClientRect().left - area.left
    const width = area.right - area.left
    if (clamp) return Math.min(Math.max(x, 0), width)
    return x >= 0 && x <= width ? x : null
  }

  // ---- stats ----

  renderStats() {
    if (!this.chart) return
    const [ min, max ] = this.zoom || [ this.series.start, this.series.end ]
    const rows = this.chart.data.datasets.map((dataset, i) => {
      const values = dataset.data.filter((p) => p.x >= min && p.x <= max && p.y != null).map((p) => p.y)
      const hidden = !this.chart.isDatasetVisible(i)
      const row = document.createElement("tr")
      if (hidden) row.className = "opacity-40"
      const name = document.createElement("td")
      const swatch = document.createElement("span")
      swatch.className = "mr-2 inline-block h-2.5 w-2.5 rounded-full align-middle"
      swatch.style.background = dataset.borderColor
      name.append(swatch, dataset.label)
      row.append(name)
      const stats = values.length ? [ Math.min(...values), values.reduce((a, b) => a + b, 0) / values.length, Math.max(...values) ] : [ null, null, null ]
      stats.forEach((value) => {
        const cell = document.createElement("td")
        cell.className = "text-right tabular-nums"
        cell.textContent = value == null ? "—" : `${number(value, dataset.unit)} ${dataset.unit}`
        row.append(cell)
      })
      return row
    })
    this.statsTarget.replaceChildren(...rows)
  }

  // ---- formatting ----

  // Monitor wall-clock time for an epoch-ms value.
  clock(ms, seconds) {
    const d = new Date(ms + this.series.utc_offset * 1000)
    const pad = (n) => String(n).padStart(2, "0")
    return `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}${seconds ? `:${pad(d.getUTCSeconds())}` : ""}`
  }
}

// The smallest "round" tick interval that gives at most ~8 ticks.
function niceStep(range) {
  return STEPS.find((step) => range / step <= 8) || STEPS[STEPS.length - 1]
}

function duration(ms) {
  const s = Math.round(ms / 1000)
  if (s >= 3600) return `${Math.floor(s / 3600)}h ${String(Math.floor(s % 3600 / 60)).padStart(2, "0")}m`
  return `${Math.floor(s / 60)}m ${String(s % 60).padStart(2, "0")}s`
}

// Temperatures, RPM and pressures read as whole numbers; volts, flows and fuel to a tenth.
const TENTHS = [ "inHg", "gph", "V", "A", "gal" ]

function number(value, unit) {
  const digits = TENTHS.includes(unit) ? 1 : 0
  return value.toLocaleString(undefined, { maximumFractionDigits: digits, minimumFractionDigits: digits })
}

// Vertical line at the hovered time.
const crosshair = {
  id: "crosshair",
  afterDatasetsDraw(chart) {
    const active = chart.tooltip?.getActiveElements?.()
    if (!active?.length) return
    const x = active[0].element.x
    const { top, bottom } = chart.chartArea
    const ctx = chart.ctx
    ctx.save()
    ctx.beginPath()
    ctx.moveTo(x, top)
    ctx.lineTo(x, bottom)
    ctx.lineWidth = 1
    ctx.strokeStyle = window.Chart.defaults.color
    ctx.globalAlpha = 0.5
    ctx.stroke()
    ctx.restore()
  }
}
