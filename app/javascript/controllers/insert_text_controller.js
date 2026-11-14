import { Controller } from "@hotwired/stimulus"
import { t } from "i18n"

// Fills a textarea with suggested text (asks before replacing what's there).
export default class extends Controller {
  static targets = ["field"]
  static values = { text: String }

  insert(event) {
    event.preventDefault()
    const field = this.fieldTarget
    if (field.value.trim() && !confirm(t("insert_text.confirm"))) return
    field.value = this.textValue
    field.focus()
    field.setSelectionRange(0, 0)
    field.scrollTop = 0
  }
}
