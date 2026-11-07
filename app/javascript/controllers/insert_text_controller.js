import { Controller } from "@hotwired/stimulus"

// Fills a textarea with suggested text (asks before replacing what's there).
export default class extends Controller {
  static targets = ["field"]
  static values = { text: String }

  insert(event) {
    event.preventDefault()
    const field = this.fieldTarget
    if (field.value.trim() && !confirm("Replace what's in the box with the suggested text?")) return
    field.value = this.textValue
    field.focus()
    field.setSelectionRange(0, 0)
    field.scrollTop = 0
  }
}
