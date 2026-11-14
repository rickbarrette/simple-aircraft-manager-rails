// Flights and squawks saved without a connection, kept in this browser
// (IndexedDB, so attached files are kept too) until they can be sent. Each
// is tagged with the user who saved it and only ever sent while they're
// signed in. The service worker reads the same store to send in the background.
const DB = "sam-offline"
const STORE = "flights" // holds every kind; the name predates squawks

function open() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB, 1)
    req.onupgradeneeded = () => req.result.createObjectStore(STORE, { keyPath: "id" })
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error)
  })
}

async function run(mode, fn) {
  const db = await open()
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, mode)
    const result = fn(tx.objectStore(STORE))
    tx.oncomplete = () => resolve(result && "result" in result ? result.result : undefined)
    tx.onerror = () => reject(tx.error)
  })
}

// The signed-in user (from the layout), or "" on a page without one.
export const currentUser = () => document.querySelector("meta[name=current-user]")?.content || ""

// item: { id, kind: "flight" | "squawk", url, tail, user, savedAt, fields: [[name, value]], error }
export const queue = {
  add: async (item) => {
    await run("readwrite", (s) => s.put(item))
    // Ask the browser not to clear this site's storage under pressure, so
    // unsent items aren't lost; and to send them even if the app is closed.
    try { await navigator.storage?.persist?.() } catch (_) { /* not supported */ }
    try { await (await navigator.serviceWorker?.ready)?.sync?.register("sam-queue") } catch (_) { /* not supported or turned off */ }
  },
  put: (item) => run("readwrite", (s) => s.put(item)),
  remove: (id) => run("readwrite", (s) => s.delete(id)),
  all: async () => ((await run("readonly", (s) => s.getAll())) || []).sort((a, b) => a.savedAt.localeCompare(b.savedAt)),
  // Items this user saved (items from before tagging count as theirs).
  mine: async () => (await queue.all()).filter((i) => !i.user || i.user === currentUser()),
}

export function formFields(form) {
  return [ ...new FormData(form).entries() ].filter(([ name, value ]) => !(value instanceof File && value.size === 0) && name !== "authenticity_token")
}

export function newKey() {
  return (crypto.randomUUID && crypto.randomUUID()) || `${Date.now()}-${Math.random().toString(36).slice(2)}`
}
