import { Controller } from "@hotwired/stimulus"

// Closes a <details> dropdown when clicking elsewhere or pressing Escape.
export default class extends Controller {
  closeOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  close() {
    this.element.removeAttribute("open")
  }
}
