import { Controller } from "@hotwired/stimulus"

const CHOICES = ["system", "light", "dark"]
const LABELS = { system: "System", light: "Light", dark: "Dark" }

// Light / dark / follow-the-OS theme toggle. The choice is kept in
// localStorage; the layout's inline script applies it before first paint.
export default class extends Controller {
  connect() {
    this.media = window.matchMedia("(prefers-color-scheme: dark)")
    this.onSystemChange = () => { if (this.choice === "system") this.apply() }
    this.media.addEventListener("change", this.onSystemChange)
    this.apply()
  }

  disconnect() {
    this.media.removeEventListener("change", this.onSystemChange)
  }

  cycle() {
    this.choice = CHOICES[(CHOICES.indexOf(this.choice) + 1) % CHOICES.length]
    this.apply()
  }

  get choice() {
    try { return localStorage.getItem("theme") || "system" } catch { return "system" }
  }

  set choice(value) {
    try { localStorage.setItem("theme", value) } catch {}
  }

  apply() {
    const choice = this.choice
    const dark = choice === "dark" || (choice === "system" && this.media.matches)
    const theme = dark ? "dark" : "light"
    const changed = document.documentElement.dataset.theme !== theme
    document.documentElement.dataset.theme = theme

    this.element.querySelectorAll("[data-theme-icon]").forEach((icon) => {
      icon.classList.toggle("hidden", icon.dataset.themeIcon !== choice)
    })
    const label = `Theme: ${LABELS[choice]}${choice === "system" ? ` (${theme})` : ""}`
    this.element.title = label
    this.element.setAttribute("aria-label", label)
    if (changed) window.dispatchEvent(new CustomEvent("theme:change", { detail: { theme } }))
  }
}
