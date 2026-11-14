import { Controller } from "@hotwired/stimulus"

// A new document's name, when left blank, comes from its first file's name
// ("annual-2026_scan.pdf" → "annual 2026 scan").
export default class extends Controller {
  static targets = [ "name", "file" ]

  fill() {
    const file = this.fileTarget.files[0]
    if (!file || this.nameTarget.value.trim()) return
    this.nameTarget.value = file.name.replace(/\.[^.]+$/, "").replace(/[_-]+/g, " ").replace(/\s+/g, " ").trim()
  }
}
