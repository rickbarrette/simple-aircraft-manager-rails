// The offline page: follows the chosen theme, reloads when the connection is
// back, and links to what this device kept for working without one: the Log
// Flight and Report Squawk forms, and aircraft overviews saved for pre-flight.
(function () {
  try {
    var choice = localStorage.getItem("theme")
    if (choice === "light" || choice === "dark") document.documentElement.dataset.theme = choice
  } catch (e) { /* storage off */ }
  window.addEventListener("online", function () { location.reload() })
  document.getElementById("retry").addEventListener("click", function () { location.reload() })
  if (!window.caches) return

  var forms = document.getElementById("forms")
  try {
    var kept = JSON.parse(localStorage.getItem("sam-offline-forms") || "{}")
    Object.keys(kept).forEach(function (path) {
      if (!/^\/aircraft\/\d+\/(flight_logs|squawks)\/new$/.test(path)) return
      var info = typeof kept[path] === "string" ? { tail: kept[path], kind: "flight" } : kept[path]
      // Only offer forms the service worker actually kept; others just loop back here.
      caches.open("sam-forms").then(function (c) { return c.match(location.origin + path) }).then(function (hit) {
        if (!hit) return
        var a = document.createElement("a")
        a.href = path
        a.textContent = forms.dataset[info.kind === "squawk" ? "squawk" : "flight"].replace("%{tail}", info.tail)
        forms.appendChild(a)
        forms.hidden = false
      }).catch(function () {})
    })
  } catch (e) { /* storage off */ }

  var pages = document.getElementById("pages")
  caches.open("sam-pages").then(function (c) { return c.keys() }).then(function (keys) {
    keys.forEach(function (request) {
      var path = new URL(request.url).pathname
      var m = path.match(/^\/aircraft\/(\d+)$/)
      if (!m) return
      caches.match(request).then(function (r) { return r && r.text() }).then(function (html) {
        var tail = html && (html.match(/<meta name="aircraft-tail" content="([^"]+)"/) || [])[1]
        var a = document.createElement("a")
        a.href = path
        a.textContent = pages.dataset.label.replace("%{tail}", tail || path)
        pages.appendChild(a)
        pages.hidden = false
      })
    })
  }).catch(function () {})
})()
