import { Controller } from "@hotwired/stimulus"

// Write / Preview tabs for a Markdown textarea. The preview is rendered by the
// server, with the same Markdown rules and sanitizing as the saved note.
export default class extends Controller {
  static targets = [ "input", "output", "writeTab", "previewTab" ]
  static values = { url: String }

  connect() {
    this.select(false)
  }

  write() {
    this.select(false)
    this.inputTarget.focus()
  }

  async preview() {
    this.select(true)
    this.outputTarget.textContent = "Loading preview…"
    const token = document.querySelector("meta[name=csrf-token]")?.content
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded", "X-CSRF-Token": token, Accept: "text/html" },
        body: new URLSearchParams({ text: this.inputTarget.value }),
        credentials: "same-origin"
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      this.outputTarget.innerHTML = await response.text() // sanitized server-side
    } catch (error) {
      this.outputTarget.textContent = `Couldn't load the preview (${error.message}).`
    }
  }

  select(previewing) {
    this.inputTarget.hidden = previewing
    this.outputTarget.hidden = !previewing
    const tabs = [ [ this.writeTabTarget, !previewing ], [ this.previewTabTarget, previewing ] ]
    tabs.forEach(([ tab, active ]) => {
      tab.setAttribute("aria-selected", active)
      tab.classList.toggle("bg-slate-200", active)
      tab.classList.toggle("text-slate-900", active)
      tab.classList.toggle("text-slate-500", !active)
    })
  }
}
