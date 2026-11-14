import { Controller } from "@hotwired/stimulus"

// After a release, offers to reload so this page picks up the new version.
export default class extends Controller {
  static targets = [ "banner" ]

  connect() {
    this.show = () => this.bannerTarget.classList.remove("hidden")
    document.addEventListener("app:updated", this.show)
  }

  disconnect() { document.removeEventListener("app:updated", this.show) }

  reload() { location.reload() }
}
