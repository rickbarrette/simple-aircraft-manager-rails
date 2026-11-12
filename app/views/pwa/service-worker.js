// Makes the app installable and gives it an offline page. Cached: public,
// static files (the offline page, icons, fingerprinted /assets/) and, so a
// flight can be logged without signal, the Log Flight forms you've opened
// (tail number and meter readings only). Other aircraft pages are never cached.
const VERSION = "v2"
const FORM_CACHE = "sam-flight-forms"
const FLIGHT_FORM = /^\/aircraft\/\d+\/flight_logs\/new$/
const SHELL_CACHE = `sam-shell-${VERSION}`
const ASSET_CACHE = "sam-assets"
const MAX_ASSETS = 80
const SHELL = [ "/offline.html", "/offline.js", "/icon.svg", "/icon-192.png" ]

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(SHELL_CACHE).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting()))
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k.startsWith("sam-shell-") && k !== SHELL_CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  )
})

self.addEventListener("fetch", (event) => {
  const request = event.request
  if (request.method !== "GET") return
  const url = new URL(request.url)
  if (url.origin !== self.location.origin) return

  if (request.mode === "navigate" && FLIGHT_FORM.test(url.pathname)) {
    event.respondWith(flightForm(request))
  } else if (request.mode === "navigate") {
    // Always go to the network for pages; show the offline page if it's unreachable.
    event.respondWith(fetch(request).catch(() => caches.match("/offline.html")))
  } else if (url.pathname.startsWith("/assets/")) {
    event.respondWith(cachedAsset(request))
  }
})

// Fingerprinted assets never change, so serve them from cache once fetched.
async function cachedAsset(request) {
  const cache = await caches.open(ASSET_CACHE)
  const hit = await cache.match(request)
  if (hit) return hit
  const response = await fetch(request)
  if (response.ok) {
    await cache.put(request, response.clone())
    trim(cache)
  }
  return response
}

// Old deploys' assets pile up; keep only the most recent entries.
async function trim(cache) {
  const keys = await cache.keys()
  await Promise.all(keys.slice(0, Math.max(0, keys.length - MAX_ASSETS)).map((k) => cache.delete(k)))
}

// The Log Flight form: fresh from the network when there is one (and kept),
// the kept copy when there isn't.
async function flightForm(request) {
  const cache = await caches.open(FORM_CACHE)
  try {
    const response = await fetch(request)
    if (response.ok && !response.redirected) await cache.put(request.url.split("?")[0], response.clone())
    return response
  } catch (_) {
    return (await cache.match(request.url.split("?")[0])) || caches.match("/offline.html")
  }
}
