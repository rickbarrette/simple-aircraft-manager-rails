import { Controller } from "@hotwired/stimulus"
import { t } from "i18n"

// Airport code field with suggestions from the airport database.
//   <div data-controller="airport-autocomplete" data-airport-autocomplete-url-value="/airports/search?aircraft_id=1">
//     <input data-airport-autocomplete-target="input" ...>
//     <ul data-airport-autocomplete-target="list" hidden></ul>
//     <p data-airport-autocomplete-target="hint"></p>
//   </div>
export default class extends Controller {
  static targets = ["input", "list", "hint"]
  static values = { url: String }

  connect() {
    this.results = []
    this.active = -1
    this.inputTarget.setAttribute("autocomplete", "off")
    this.inputTarget.setAttribute("role", "combobox")
    this.inputTarget.setAttribute("aria-autocomplete", "list")
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.listTarget.id ||= `${this.inputTarget.id}-suggestions`
    this.inputTarget.setAttribute("aria-controls", this.listTarget.id)
    this.describe() // e.g. From pre-filled from the last flight
  }

  disconnect() { clearTimeout(this.timer) }

  search() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.fetch(), 150)
  }

  async fetch() {
    const q = this.inputTarget.value.trim()
    if (q.length < 2) { this.close(); this.setHint(""); return }
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", q)
    const response = await fetch(url, { headers: { Accept: "application/json" } })
    if (!response.ok || q !== this.inputTarget.value.trim()) return
    this.results = await response.json()
    this.active = -1
    this.render()
    this.updateHint()
  }

  render() {
    this.listTarget.replaceChildren(...this.results.map((airport, i) => {
      const li = document.createElement("li")
      li.id = `${this.listTarget.id}-${i}`
      li.setAttribute("role", "option")
      li.className = "cursor-pointer px-3 py-1.5 text-sm hover:bg-sky-50"
      const code = document.createElement("span")
      code.className = "font-mono font-semibold"
      code.textContent = airport.code
      const name = document.createElement("span")
      name.className = "ml-2 text-slate-700"
      name.textContent = airport.name
      const place = document.createElement("span")
      place.className = "ml-1 text-xs text-slate-500"
      place.textContent = [airport.place, airport.aka?.length ? `also ${airport.aka.join(", ")}` : null, airport.kind].filter(Boolean).join(" · ")
      li.append(code, name, place)
      li.addEventListener("mousedown", (event) => { event.preventDefault(); this.choose(i) })
      return li
    }))
    const open = this.results.length > 0
    this.listTarget.hidden = !open
    this.inputTarget.setAttribute("aria-expanded", String(open))
  }

  keydown(event) {
    if (this.listTarget.hidden) return
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      const step = event.key === "ArrowDown" ? 1 : -1
      this.active = (this.active + step + this.results.length) % this.results.length
      this.highlight()
    } else if (event.key === "Enter" && this.active >= 0) {
      event.preventDefault()
      this.choose(this.active)
    } else if (event.key === "Escape") {
      this.close()
    }
  }

  highlight() {
    Array.from(this.listTarget.children).forEach((li, i) => {
      li.classList.toggle("bg-sky-100", i === this.active)
      li.setAttribute("aria-selected", String(i === this.active))
    })
    this.inputTarget.setAttribute("aria-activedescendant", this.active >= 0 ? `${this.listTarget.id}-${this.active}` : "")
  }

  choose(index) {
    const airport = this.results[index]
    this.inputTarget.value = airport.code
    this.setHint(this.describeAirport(airport))
    this.close()
  }

  blur() { setTimeout(() => this.close(), 100) }

  close() {
    this.listTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
  }

  // Show the airport name for a typed code, or note that it isn't in the database.
  updateHint() {
    const code = this.inputTarget.value.trim().toUpperCase()
    const match = this.results.find((a) => a.code === code || (a.aka || []).includes(code))
    if (match) this.setHint(this.describeAirport(match))
    else if (code.length >= 2 && code.length <= 4 && !code.includes(" ")) this.setHint(t("airports.not_found"), true)
    else this.setHint("")
  }

  async describe() {
    if (!this.inputTarget.value.trim()) return
    await this.fetch()
    this.close()
  }

  describeAirport(a) {
    return [a.name, a.place].filter(Boolean).join(", ")
  }

  setHint(text, warn = false) {
    if (!this.hasHintTarget) return
    this.hintTarget.textContent = text
    this.hintTarget.classList.toggle("text-amber-700", warn)
  }
}
