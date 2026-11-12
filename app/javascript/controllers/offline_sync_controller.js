import { Controller } from "@hotwired/stimulus"
import { queue } from "controllers/offline_queue"

// On every page: sends flights logged offline once there's a connection, and
// says what happened. A rejected flight stays until it's discarded.
export default class extends Controller {
  static targets = [ "banner" ]

  connect() {
    this.sync = this.sync.bind(this)
    window.addEventListener("online", this.sync)
    document.addEventListener("offline-queue:changed", this.sync)
    this.sync()
  }

  disconnect() {
    window.removeEventListener("online", this.sync)
    document.removeEventListener("offline-queue:changed", this.sync)
  }

  async sync() {
    let items
    try { items = await queue.all() } catch (_) { return }
    if (!items.length) return this.show("")
    if (!navigator.onLine || this.running) return this.status(items)
    this.running = true
    let sent = 0
    try {
      for (const item of items.filter((i) => !i.error)) {
        const result = await this.send(item)
        if (result === "sent") { await queue.remove(item.id); sent++ }
        else if (result === "signin") { this.show("Sign in to send the flights logged offline."); return }
        else if (result === "offline") break
        else { item.error = result; await queue.put(item) }
      }
    } finally { this.running = false }
    this.status(await queue.all(), sent)
  }

  async send(item) {
    const body = new FormData()
    for (const [ name, value ] of item.fields) body.append(name, value)
    const token = document.querySelector("meta[name=csrf-token]")?.content
    if (token) body.append("authenticity_token", token)
    let response
    try {
      response = await fetch(item.url, { method: "POST", body, credentials: "same-origin", headers: { Accept: "text/html" } })
    } catch (_) { return "offline" }
    if (response.url.includes("/session/new")) return "signin"
    if (response.ok) return "sent"
    const html = await response.text()
    const doc = new DOMParser().parseFromString(html, "text/html")
    const message = [ ...doc.querySelectorAll("[role=alert], .field-error") ].map((e) => e.textContent.trim()).filter(Boolean).join(" ")
    return message || `Not accepted (${response.status}).`
  }

  status(items, sent = 0) {
    const failed = items.filter((i) => i.error)
    const waiting = items.length - failed.length
    const parts = []
    if (sent) parts.push(`Sent ${sent} flight${sent > 1 ? "s" : ""} logged offline.`)
    if (waiting) parts.push(`${waiting} flight${waiting > 1 ? "s" : ""} logged offline waiting for a connection.`)
    this.show(parts.join(" "), failed)
  }

  show(text, failed = []) {
    const banner = this.bannerTarget
    banner.replaceChildren()
    if (text) banner.append(Object.assign(document.createElement("p"), { textContent: text }))
    for (const item of failed) {
      const date = (item.fields.find(([ n ]) => n === "flight_log[date]") || [])[1] || ""
      const row = document.createElement("p")
      row.textContent = `${item.tail} flight ${date} logged offline wasn't accepted: ${item.error} `
      const discard = Object.assign(document.createElement("button"), { type: "button", textContent: "Discard", className: "btn-secondary btn-sm ml-1" })
      discard.addEventListener("click", async () => { await queue.remove(item.id); this.sync() })
      row.append(discard)
      banner.append(row)
    }
    banner.classList.toggle("hidden", !text && !failed.length)
  }
}
