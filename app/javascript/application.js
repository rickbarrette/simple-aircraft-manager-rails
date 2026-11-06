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
