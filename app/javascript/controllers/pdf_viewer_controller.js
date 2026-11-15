import { Controller } from "@hotwired/stimulus"
import { t } from "i18n"

// A PDF in the document viewer. Desktop browsers show it in their own viewer,
// in a frame. Phones don't: Android shows nothing in a frame and iPhones only
// the first page, so there every page is drawn with PDF.js (public/pdfjs,
// loaded only here), each one as it scrolls into view, fetching only the
// parts of the file those pages need.
export default class extends Controller {
  static targets = [ "frame", "status", "pages" ]
  static values = { url: String, pdfjs: String }

  // Starts over each time, as a page restored from Turbo's cache comes back
  // with blank pages.
  connect() {
    this.pagesTarget.replaceChildren()
    this.statusTarget.replaceChildren(t("pdf.loading"))
    this.statusTarget.hidden = false
    if (navigator.pdfViewerEnabled && !matchMedia("(pointer: coarse)").matches) return this.showFrame()
    this.draw().catch((error) => this.failed(error))
  }

  disconnect() {
    this.observer?.disconnect()
    this.loading?.destroy()
  }

  showFrame() {
    this.statusTarget.hidden = true
    this.pagesTarget.append(this.frameTarget.content.cloneNode(true))
  }

  async draw() {
    const base = this.pdfjsValue
    const pdfjs = await import(`${base}pdf.min.mjs`)
    pdfjs.GlobalWorkerOptions.workerSrc = `${base}pdf.worker.min.mjs`
    this.loading = pdfjs.getDocument({
      url: this.urlValue,
      withCredentials: true,
      // Only the parts needed for the pages being drawn, not the whole file
      // in the background (a long manual on a phone's data plan).
      disableAutoFetch: true,
      disableStream: true,
      wasmUrl: `${base}wasm/`,
      standardFontDataUrl: `${base}standard_fonts/`,
      iccUrl: `${base}iccs/`
    })
    const pdf = await this.loading.promise
    if (!this.element.isConnected) return

    // Placeholders the size of the first page keep the scroll position steady
    // while pages are drawn; each takes its own shape once it's drawn.
    const first = (await pdf.getPage(1)).getViewport({ scale: 1 })
    // Pages are drawn as they come near the screen and let go once they're
    // far from it, so a long manual doesn't use up a phone's memory.
    this.observer = new IntersectionObserver((entries) => {
      for (const { target, isIntersecting } of entries) {
        target.dataset.near = isIntersecting
        if (isIntersecting && !target.dataset.drawn) this.drawPage(pdf, target)
        else if (!isIntersecting && target.dataset.drawn) { delete target.dataset.drawn; target.replaceChildren() }
      }
    }, { rootMargin: "200% 0px" })

    for (let number = 1; number <= pdf.numPages; number++) {
      const page = document.createElement("div")
      page.className = "relative w-full bg-white shadow-sm ring-1 ring-slate-200"
      page.style.aspectRatio = `${first.width} / ${first.height}`
      page.dataset.page = number
      page.setAttribute("role", "img")
      page.setAttribute("aria-label", t("pdf.page", { page: number, pages: pdf.numPages }))
      this.pagesTarget.append(page)
      this.observer.observe(page)
    }
    this.statusTarget.hidden = true
  }

  async drawPage(pdf, holder) {
    holder.dataset.drawn = "drawing"
    try {
      const page = await pdf.getPage(Number(holder.dataset.page))
      const natural = page.getViewport({ scale: 1 })
      holder.style.aspectRatio = `${natural.width} / ${natural.height}`
      // Sharp on the screen and when pinched in a little.
      const density = Math.min((window.devicePixelRatio || 1) * 1.25, 2.5)
      const viewport = page.getViewport({ scale: (holder.clientWidth * density) / natural.width })
      const canvas = document.createElement("canvas")
      canvas.width = Math.floor(viewport.width)
      canvas.height = Math.floor(viewport.height)
      canvas.className = "block h-auto w-full"
      await page.render({ canvas, canvasContext: canvas.getContext("2d"), viewport }).promise
      page.cleanup()
      if (holder.dataset.near !== "true") { canvas.width = canvas.height = 0; delete holder.dataset.drawn; return } // scrolled away meanwhile
      holder.dataset.drawn = "drawn"
      holder.replaceChildren(canvas)
    } catch (_) {
      holder.dataset.drawn = "failed"
      holder.replaceChildren(Object.assign(document.createElement("p"), { className: "p-6 text-center text-sm text-slate-500", textContent: t("pdf.page_failed") }))
    }
  }

  // Can't draw it here (an old browser, or not a readable PDF): the browser's own viewer is one tap away.
  failed(error) {
    if (!this.element.isConnected) return
    console.warn("PDF viewer:", error)
    this.statusTarget.hidden = false
    this.statusTarget.replaceChildren(t("pdf.failed"), " ")
    this.statusTarget.append(Object.assign(document.createElement("a"), { href: this.urlValue, target: "_blank", rel: "noopener", className: "link", textContent: t("pdf.open") }))
  }
}
