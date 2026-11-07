// Configure your import map in config/importmap.rb.
import "@hotwired/turbo-rails"
import "controllers"
import "chartkick"
import "Chart.bundle"

// Chart text and grid colors follow the light/dark theme.
function styleCharts() {
  if (!window.Chart) return
  const dark = document.documentElement.dataset.theme === "dark"
  window.Chart.defaults.color = dark ? "#a3b1c6" : "#64748b"
  window.Chart.defaults.borderColor = dark ? "rgba(148, 163, 184, 0.18)" : "rgba(100, 116, 139, 0.15)"
}
function restyleCharts() {
  styleCharts()
  if (window.Chartkick) window.Chartkick.eachChart((chart) => chart.redraw())
}
styleCharts()
// Charts can be created before this module runs, so restyle after each page load too.
document.addEventListener("turbo:load", restyleCharts)
window.addEventListener("theme:change", restyleCharts)

// Installable app (PWA): the service worker adds an offline page and caches static assets.
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => navigator.serviceWorker.register("/service-worker.js", { scope: "/" }).catch(() => {}))
}

// Label each table cell with its column header, so phone CSS can show rows as
// cards ("Status: In Service"). Skips tables marked .table-keep.
function labelTableCells(root = document) {
  root.querySelectorAll("table.table:not(.table-keep)").forEach((table) => {
    const headers = [ ...table.querySelectorAll("thead th") ].map((th) => th.textContent.trim().replace(/\s+/g, " "))
    if (headers.length === 0) return
    table.querySelectorAll("tbody tr").forEach((row) => {
      let column = 0
      for (const cell of row.children) {
        if (!cell.hasAttribute("data-label")) cell.setAttribute("data-label", headers[column] || "")
        column += cell.colSpan || 1
      }
    })
  })
}
document.addEventListener("turbo:load", () => labelTableCells())
document.addEventListener("turbo:frame-load", (event) => labelTableCells(event.target))

// Small behaviours that used to be inline onclick handlers (blocked by the CSP).
document.addEventListener("click", (event) => {
  const target = event.target
  if (!(target instanceof HTMLInputElement)) return
  if (target.matches("[data-select-on-click]")) target.select()
  if (target.matches("[data-check-all]")) {
    target.closest("table")?.querySelectorAll("tbody input[type=checkbox]").forEach((box) => { box.checked = target.checked })
  }
})

document.addEventListener("change", (event) => {
  if (event.target.matches?.("[data-submit-on-change]")) event.target.form?.requestSubmit()
})

document.addEventListener("click", (event) => {
  if (event.target.closest?.("[data-print]")) window.print()
})
