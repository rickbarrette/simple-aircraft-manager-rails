import { Controller } from "@hotwired/stimulus"
import { t } from "i18n"
import { DirectUpload } from "@rails/activestorage"

// Bulk document upload. Picked files (or a whole folder) are listed with an
// editable document name each; files sharing a name become one document. On
// submit every file goes straight to storage (a few at a time, with progress),
// then the form is submitted with just the signed ids and names.
//
// Without JavaScript the file field posts the files itself and the server
// names each document after its file.
export default class extends Controller {
  static targets = [ "input", "folder", "folderField", "panel", "list", "summary", "group", "groupField", "submit", "status" ]
  static values = { url: String, maxBytes: Number }

  connect() {
    this.items = []
    this.ready = false
    this.uploading = false
    this.inputTarget.removeAttribute("name") // the signed ids are sent instead
    if ("webkitdirectory" in this.folderTarget) this.folderFieldTarget.hidden = false
    this.beforeUnload = (event) => { if (this.uploading) event.preventDefault() }
    window.addEventListener("beforeunload", this.beforeUnload)
  }

  disconnect() {
    window.removeEventListener("beforeunload", this.beforeUnload)
  }

  add(event) {
    for (const file of event.target.files) {
      const item = { file, path: file.webkitRelativePath || file.name, state: "pending", progress: 0 }
      if (file.size > this.maxBytesValue) Object.assign(item, { state: "error", error: `over the ${Math.round(this.maxBytesValue / 1048576)} MB limit` })
      this.items.push(item)
    }
    event.target.value = ""
    this.items.sort((a, b) => a.path.localeCompare(b.path, undefined, { numeric: true, sensitivity: "base" }))
    this.items.forEach((item) => { if (!item.custom) item.name = this.defaultName(item) })
    this.groupFieldTarget.hidden = !this.items.some((item) => item.path.includes("/"))
    this.render()
  }

  regroup() {
    this.items.forEach((item) => { item.custom = false; item.name = this.defaultName(item) })
    this.render()
  }

  clear() {
    if (this.uploading) return
    this.items = []
    this.render()
  }

  defaultName(item) {
    const parts = item.path.split("/")
    if (this.groupTarget.checked && parts.length > 1) return parts[parts.length - 2]
    return parts[parts.length - 1].replace(/\.[^.]+$/, "").replace(/_/g, " ").replace(/\s+/g, " ").trim() || t("bulk_upload.untitled")
  }

  render() {
    this.panelTarget.hidden = this.items.length === 0
    this.listTarget.replaceChildren(...this.items.map((item, index) => this.row(item, index)))
    this.updateSummary()
  }

  row(item, index) {
    const li = document.createElement("li")
    li.className = "flex items-start gap-3 px-3 py-2"

    const body = document.createElement("div")
    body.className = "min-w-0 flex-1"
    const name = document.createElement("input")
    name.type = "text"
    name.className = "input"
    name.value = item.name
    name.setAttribute("aria-label", t("bulk_upload.name_for", { path: item.path }))
    name.disabled = this.uploading
    name.addEventListener("input", () => { item.name = name.value; item.custom = true; this.updateSummary() })

    const meta = document.createElement("p")
    meta.className = "mt-1 truncate text-xs text-slate-500"
    const bar = document.createElement("div")
    bar.className = "mt-1 h-1 overflow-hidden rounded bg-slate-100"
    bar.hidden = item.state === "pending" || item.state === "error"
    const fill = document.createElement("div")
    fill.className = "h-full bg-sky-600 transition-[width]"
    bar.append(fill)
    body.append(name, meta, bar)

    const remove = document.createElement("button")
    remove.type = "button"
    remove.className = "btn-secondary btn-sm"
    remove.textContent = "✕"
    remove.setAttribute("aria-label", t("bulk_upload.remove", { path: item.path }))
    remove.disabled = this.uploading
    remove.addEventListener("click", () => { this.items.splice(index, 1); this.render() })

    li.append(body, remove)
    item.update = () => {
      const status = { pending: "", uploading: ` · ${item.progress}%`, done: " · uploaded", error: ` · ${item.error}` }[item.state]
      meta.textContent = `${item.path} · ${this.size(item.file.size)}${status}`
      meta.classList.toggle("text-red-600", item.state === "error")
      meta.classList.toggle("text-slate-500", item.state !== "error")
      bar.hidden = item.state === "pending" || item.state === "error"
      fill.style.width = `${item.state === "done" ? 100 : item.progress}%`
    }
    item.update()
    return li
  }

  updateSummary() {
    const files = this.items.length
    const docs = new Set(this.items.map((item) => item.name.trim() || t("bulk_upload.untitled"))).size
    this.summaryTarget.textContent = `${files} ${files === 1 ? "file" : "files"} → ${docs} ${docs === 1 ? "document" : "documents"}`
    this.submitTarget.textContent = files ? t("bulk_upload.upload_count", { count: docs }) : t("bulk_upload.upload")
  }

  size(bytes) {
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1048576) return `${Math.round(bytes / 1024)} KB`
    return `${(bytes / 1048576).toFixed(1)} MB`
  }

  async submit(event) {
    if (this.ready) return
    event.preventDefault()
    if (this.uploading) return
    if (this.items.length === 0) return this.say(t("bulk_upload.choose_files"))
    if (this.items.some((item) => item.file.size > this.maxBytesValue)) {
      return this.say(t("bulk_upload.remove_red"))
    }

    this.items.forEach((item) => { if (item.state === "error") item.state = "pending" })
    this.setUploading(true)
    const queue = this.items.filter((item) => item.state === "pending")
    const total = queue.length
    let finished = 0
    this.say(t("bulk_upload.uploading", { done: 0, total }))
    const worker = async () => {
      for (let item = queue.shift(); item; item = queue.shift()) {
        await this.upload(item)
        this.say(t("bulk_upload.uploading", { done: ++finished, total }))
      }
    }
    await Promise.all([ worker(), worker(), worker() ])

    const failed = this.items.filter((item) => item.state === "error").length
    if (failed) {
      this.setUploading(false)
      return this.say(`${failed} ${failed === 1 ? "file" : "files"} didn't upload. Press Upload to retry, or remove ${failed === 1 ? "it" : "them"}.`)
    }

    this.element.querySelectorAll("input[data-bulk-upload-hidden]").forEach((el) => el.remove())
    for (const item of this.items) {
      this.hidden("files[]", item.signedId)
      this.hidden("names[]", item.name)
    }
    this.uploading = false
    this.ready = true
    this.say(t("bulk_upload.saving"))
    // When nothing was left to upload this all ran inside the click's submit
    // event, during which the browser ignores requestSubmit, so wait a tick.
    setTimeout(() => this.element.requestSubmit())
  }

  upload(item) {
    item.state = "uploading"
    item.progress = 0
    item.update()
    return new Promise((resolve) => {
      const delegate = {
        directUploadWillStoreFileWithXHR: (xhr) => {
          xhr.upload.addEventListener("progress", (e) => {
            if (e.lengthComputable) { item.progress = Math.round((e.loaded / e.total) * 100); item.update() }
          })
        }
      }
      new DirectUpload(item.file, this.urlValue, delegate).create((error, blob) => {
        if (error) {
          Object.assign(item, { state: "error", error: /Status: 422/.test(error) ? "not an allowed file type" : "upload failed" })
        } else {
          Object.assign(item, { state: "done", signedId: blob.signed_id })
        }
        item.update()
        resolve()
      })
    })
  }

  hidden(name, value) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    input.dataset.bulkUploadHidden = ""
    this.element.append(input)
  }

  setUploading(on) {
    this.uploading = on
    this.submitTarget.disabled = on
    this.render()
  }

  say(message) {
    this.statusTarget.textContent = message
  }
}
