import { Controller } from "@hotwired/stimulus"

// Shows parts of a form only when a select has a given value, e.g. the
// inspection result only for inspection entries. A part hidden by changing
// the select is cleared, so it isn't saved.
//   <select data-show-when-target="source" data-action="show-when#update">
//   <div data-show-when-target="item" data-show-when-value="INSPECTION">
export default class extends Controller {
  static targets = [ "source", "item" ]

  connect() { this.update() }

  update(event) {
    for (const item of this.itemTargets) {
      const show = item.dataset.showWhenValue.split(" ").includes(this.sourceTarget.value)
      if (event && !show && !item.hidden) item.querySelectorAll("select, input:not([type=hidden]), textarea").forEach((el) => { el.value = "" })
      item.hidden = !show
    }
  }
}
