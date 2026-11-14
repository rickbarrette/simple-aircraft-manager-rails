import { Controller } from "@hotwired/stimulus"

// Profile → This device: install the app. Chrome and Android offer a button;
// iPhone and iPad install from Safari's Share menu; elsewhere the browser's menu.
export default class extends Controller {
  static targets = [ "button", "installed", "ios", "other" ]

  connect() {
    this.offer = () => this.render()
    document.addEventListener("install:available", this.offer)
    this.render()
  }

  disconnect() { document.removeEventListener("install:available", this.offer) }

  render() {
    const installed = matchMedia("(display-mode: standalone)").matches || navigator.standalone === true
    const ios = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
    const prompt = !installed && !!window.samInstallPrompt
    this.installedTarget.hidden = !installed
    this.buttonTarget.hidden = !prompt
    this.iosTarget.hidden = installed || prompt || !ios
    this.otherTarget.hidden = installed || prompt || ios
  }

  async install() {
    const offer = window.samInstallPrompt
    if (!offer) return
    offer.prompt()
    await offer.userChoice
    window.samInstallPrompt = null
    this.render()
  }
}
