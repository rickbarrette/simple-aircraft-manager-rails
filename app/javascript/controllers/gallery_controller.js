import { Controller } from "@hotwired/stimulus"

// In-app photo viewer for a set of image links. Click a photo to open it
// full-screen; ←/→, swipe or the arrow buttons move between photos, Esc or a
// click on the backdrop closes. Ctrl/⌘-click still opens the image in a tab.
export default class extends Controller {
  static targets = [ "item", "dialog", "image", "caption", "counter", "download", "original", "nav" ]

  connect() {
    this.index = 0
  }

  disconnect() {
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
  }

  open(event) {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button > 0) return
    event.preventDefault()
    this.show(this.itemTargets.indexOf(event.currentTarget))
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  next() { this.show(this.index + 1) }
  previous() { this.show(this.index - 1) }

  keydown(event) {
    if (event.key === "ArrowRight") { event.preventDefault(); this.next() }
    if (event.key === "ArrowLeft") { event.preventDefault(); this.previous() }
  }

  // The backdrop is the dialog element itself; clicks on the photo or controls aren't.
  backdrop(event) {
    if (event.target === this.dialogTarget || event.target.dataset.galleryClose !== undefined) this.close()
  }

  touchstart(event) {
    this.touchX = event.changedTouches[0].clientX
  }

  touchend(event) {
    if (this.touchX == null) return
    const dx = event.changedTouches[0].clientX - this.touchX
    this.touchX = null
    if (Math.abs(dx) > 50) dx < 0 ? this.next() : this.previous()
  }

  show(index) {
    const items = this.itemTargets
    this.index = (index + items.length) % items.length
    const item = items[this.index]
    const name = item.dataset.galleryName

    this.imageTarget.src = item.href
    this.imageTarget.alt = name
    this.captionTarget.textContent = name
    this.downloadTarget.href = item.dataset.galleryDownload
    this.originalTarget.href = item.href
    this.counterTarget.textContent = items.length > 1 ? `${this.index + 1} / ${items.length}` : ""
    this.navTargets.forEach((el) => { el.hidden = items.length < 2 })

    // Preload the neighbours so swiping feels instant.
    if (items.length > 1) [ this.index + 1, this.index - 1 ].forEach((i) => { new Image().src = items[(i + items.length) % items.length].href })
  }
}
