import { Controller } from "@hotwired/stimulus"
import { t } from "i18n"

// The top bar shows the connection at a glance (as SilverBullet does):
// - it turns red when the server can't be reached: the device is offline, or
//   a request failed (signal but no internet, or the proxy answering for the
//   app). While red it checks /up every so often and turns back on its own;
// - a ring fills while pages are being saved for offline use or flights and
//   squawks logged offline are being sent, with the percentage in its middle;
// - while some are waiting to send, the ring is amber with how many.
// Others report with events on document:
//   sam:progress    { source, done, total }  (done >= total when finished)
//   sam:waiting     { count }
//   sam:unreachable / sam:reachable
// and it says when the server answers again with sam:back-online (what was
// logged offline is sent then).
// The header is replaced on every page, so the state and the listeners live
// in this module and the header on the page just shows them.
const RETRY_EVERY = 15 * 1000
const UNREACHABLE = [ 502, 503, 504 ]
const OFFLINE_COLOR = "#b91c1c" // red-700, for the phone's status bar
const state = { online: navigator.onLine, progress: {}, waiting: 0 }
let header = null // the controller on the page
let checking = null
let timer = null
let normalColor = null

// Any answer from the app (even a sign-in redirect) means it's reachable.
async function check() {
  checking ||= fetch("/up", { cache: "no-store", redirect: "manual", credentials: "same-origin" })
    .then((response) => !UNREACHABLE.includes(response.status), () => false)
    .finally(() => { checking = null })
  setOnline(await checking)
}

function setOnline(online) {
  clearTimeout(timer)
  if (!online) timer = setTimeout(check, RETRY_EVERY)
  if (state.online === online) return
  state.online = online
  header?.announce(online ? t("connection.back_online") : t("connection.offline"))
  update()
  if (online) document.dispatchEvent(new CustomEvent("sam:back-online"))
}

// Several reports often arrive together (done sending, then none waiting):
// show them once, on the next frame, so the ring doesn't flicker between.
let frame = null
function update() {
  frame ||= requestAnimationFrame(() => { frame = null; header?.render() })
}

window.addEventListener("online", check)
window.addEventListener("offline", () => setOnline(false))
document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible" && !state.online) check() })
document.addEventListener("sam:unreachable", () => setOnline(false))
document.addEventListener("turbo:fetch-request-error", () => setOnline(false))
document.addEventListener("sam:reachable", () => setOnline(true))
document.addEventListener("sam:progress", ({ detail }) => { state.progress[detail.source] = detail; update() })
document.addEventListener("sam:waiting", ({ detail }) => { state.waiting = detail.count; update() })

// Whether the server answered last time (false while the top bar is red).
export const serverReachable = () => state.online

export default class extends Controller {
  static targets = [ "ring", "label", "announce" ]

  connect() {
    header = this
    this.themeColor = document.querySelector("meta[name=theme-color]")
    normalColor ||= this.themeColor?.content
    if (!navigator.onLine) setOnline(false)
    else if (!state.online || this.fromSavedCopy()) check() // a fresh page, or maybe the offline copy
    this.render()
  }

  disconnect() {
    if (header === this) header = null
  }

  fromSavedCopy() {
    const rendered = Date.parse(document.querySelector("meta[name=rendered-at]")?.content || "")
    return rendered && Date.now() - rendered > 60 * 1000
  }

  announce(text) {
    if (this.hasAnnounceTarget) this.announceTarget.textContent = text
  }

  render() {
    this.element.classList.toggle("is-offline", !state.online)
    this.element.title = state.online ? "" : t("connection.offline")
    if (this.themeColor && normalColor) this.themeColor.content = state.online ? normalColor : OFFLINE_COLOR

    const busy = Object.values(state.progress).filter((p) => p.total && p.done < p.total)
    if (busy.length) {
      const done = busy.reduce((sum, p) => sum + p.done, 0)
      const total = busy.reduce((sum, p) => sum + p.total, 0)
      const percent = Math.floor((done / total) * 100)
      const what = busy.some((p) => p.source === "send") ? "sending" : "saving"
      this.showRing({ percent, number: percent, waiting: false, text: t(`connection.${what}`, { percent }) })
    } else if (state.waiting) {
      this.showRing({ percent: 100, number: state.waiting, waiting: true, text: t("connection.waiting", { count: state.waiting }) })
    } else {
      this.ringTarget.hidden = true
    }
  }

  showRing({ percent, number, waiting, text }) {
    const ring = this.ringTarget
    ring.hidden = false
    ring.classList.toggle("is-waiting", waiting)
    ring.style.setProperty("--progress", `${percent}%`)
    ring.title = text
    ring.setAttribute("aria-label", text)
    this.labelTarget.textContent = number
  }
}
