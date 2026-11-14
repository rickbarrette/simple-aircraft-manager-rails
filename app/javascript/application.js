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

// Installable app (PWA): the service worker keeps an offline page, forms and
// pre-flight pages, sends saved items in the background and shows notifications.
if ("serviceWorker" in navigator) {
  // A new release's worker takes over open pages: offer a reload (not on the first install).
  const hadWorker = !!navigator.serviceWorker.controller
  navigator.serviceWorker.addEventListener("controllerchange", () => {
    if (hadWorker) document.dispatchEvent(new CustomEvent("app:updated"))
  })
  // The worker sent saved items in the background: refresh the counts.
  navigator.serviceWorker.addEventListener("message", (event) => {
    if (event.data?.type === "queue-changed") document.dispatchEvent(new CustomEvent("offline-queue:changed"))
  })
  window.addEventListener("load", () => navigator.serviceWorker.register("/service-worker.js", { scope: "/" }).catch(() => {}))
}

// Chrome and Android offer to install the app; keep the offer for the button on the profile page.
window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault()
  window.samInstallPrompt = event
  document.dispatchEvent(new CustomEvent("install:available"))
})

// The device's time zone, so times show in it and "today" is the local date
// (unless a zone is chosen in Profile).
try {
  const zone = Intl.DateTimeFormat().resolvedOptions().timeZone
  if (zone && !document.cookie.split("; ").includes(`tz=${encodeURIComponent(zone)}`)) {
    document.cookie = `tz=${encodeURIComponent(zone)}; path=/; max-age=31536000; samesite=lax`
  }
} catch (_) { /* no Intl */ }

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
  if (target.type === "checkbox") showSelectionActions()
})

// Actions on ticked rows (e.g. "Print selected") appear once a row is ticked:
// data-needs-selection names the form the row checkboxes belong to.
function showSelectionActions() {
  document.querySelectorAll("[data-needs-selection]").forEach((el) => {
    el.hidden = !document.querySelector(`input[form="${el.dataset.needsSelection}"]:checked`)
  })
}
document.addEventListener("turbo:load", showSelectionActions)

document.addEventListener("change", (event) => {
  if (event.target.matches?.("[data-submit-on-change]")) event.target.form?.requestSubmit()
})

document.addEventListener("click", (event) => {
  if (event.target.closest?.("[data-print]")) window.print()
})
