import { Controller } from "@hotwired/stimulus"
import { currentUser } from "controllers/offline_queue"

// Saves, ahead of time, what's needed to work without signal: the Fleet page
// and, for each of your aircraft, its Overview, W&B, Log Flight and Report
// Squawk pages (fetching them through the service worker keeps a copy, see
// service-worker.js) and its photo (kept in sam-images, shown when offline). Done in the background at most once an hour, or when
// your aircraft change. Signing out clears it.
const EVERY = 60 * 60 * 1000

export default class extends Controller {
  static values = { aircraft: Array }

  connect() {
    if (!navigator.onLine || !("serviceWorker" in navigator)) return
    navigator.serviceWorker.ready.then(() => this.prepare()).catch(() => {})
  }

  async prepare() {
    const signature = `${currentUser()}:${JSON.stringify(this.aircraftValue)}`
    let last = {}
    try { last = JSON.parse(localStorage.getItem("sam-offline-prep") || "{}") } catch (_) { /* storage off */ }
    if (last.signature === signature && Date.now() - last.at < EVERY) return
    if (!navigator.serviceWorker.controller) return // first visit: the worker takes over on the next page

    const forms = {}
    const paths = [ "/" ]
    for (const a of this.aircraftValue) {
      paths.push(...a.pages, a.flight, a.squawk)
      forms[a.flight] = { tail: a.tail, kind: "flight" }
      forms[a.squawk] = { tail: a.tail, kind: "squawk" }
    }
    for (const path of paths) {
      if (!navigator.onLine) return
      // One at a time, after the page has settled, so it never competes with what you're doing.
      await new Promise((resolve) => (window.requestIdleCallback || setTimeout)(resolve, { timeout: 2000 }))
      try { await fetch(path, { credentials: "same-origin", headers: { Accept: "text/html" } }) } catch (_) { return }
    }
    await this.savePictures(this.aircraftValue.flatMap((a) => a.pictures || []))
    try {
      localStorage.setItem("sam-offline-forms", JSON.stringify({ ...JSON.parse(localStorage.getItem("sam-offline-forms") || "{}"), ...forms }))
      localStorage.setItem("sam-offline-prep", JSON.stringify({ signature, at: Date.now() }))
    } catch (_) { /* storage off */ }
  }

  // The aircraft photos: refreshed, and those of aircraft you no longer have dropped.
  async savePictures(urls) {
    try {
      const cache = await caches.open("sam-images")
      const wanted = urls.map((url) => [ url, imageKey(url) ]).filter(([ , key ]) => key)
      for (const request of await cache.keys()) if (!wanted.some(([ , key ]) => key === request.url)) await cache.delete(request)
      for (const [ url, key ] of wanted) {
        const response = await fetch(url, { credentials: "same-origin" }).catch(() => null)
        if (response?.ok) await cache.put(key, response)
      }
    } catch (_) { /* no Cache API */ }
  }
}

// Photo links carry an expiry, so they change with every page; the saved copy
// is filed under the upload's id (and size) instead (same rule in service-worker.js).
function imageKey(url) {
  try {
    const [ , signed, size ] = new URL(url, location.origin).pathname.match(/\/(?:blobs|representations)\/redirect\/([^/]+?)--[^/]+\/(?:([^/]+)\/)?/)
    const id = JSON.parse(atob(decodeURIComponent(signed)))._rails.data
    return `${location.origin}/offline-image/${id}${size ? `/${size}` : ""}`
  } catch (_) { return null }
}
