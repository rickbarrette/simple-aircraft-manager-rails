import { Controller } from "@hotwired/stimulus"

// "Sign as": fills the signer's name, kind of certificate and number from one
// of the current user's certificates.
export default class extends Controller {
  static targets = [ "choice", "name", "kind", "number" ]

  fill() {
    const option = this.choiceTarget.selectedOptions[0]
    if (!option?.dataset.number) return
    if (this.hasNameTarget) this.nameTarget.value = option.dataset.name
    if (this.hasKindTarget) this.kindTarget.value = option.dataset.kind
    if (this.hasNumberTarget) this.numberTarget.value = option.dataset.number
  }
}
