// Flights logged without a connection, kept in this browser (IndexedDB, so
// attached track and engine files are kept too) until they can be sent.
const DB = "sam-offline"
const STORE = "flights"

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

// item: { id, url, tail, savedAt, fields: [[name, value]], error }
export const queue = {
  add: (item) => run("readwrite", (s) => s.put(item)),
  put: (item) => run("readwrite", (s) => s.put(item)),
  remove: (id) => run("readwrite", (s) => s.delete(id)),
  all: async () => ((await run("readonly", (s) => s.getAll())) || []).sort((a, b) => a.savedAt.localeCompare(b.savedAt)),
}

export function formFields(form) {
  return [ ...new FormData(form).entries() ].filter(([ name, value ]) => !(value instanceof File && value.size === 0) && name !== "authenticity_token")
}

export function newKey() {
  return (crypto.randomUUID && crypto.randomUUID()) || `${Date.now()}-${Math.random().toString(36).slice(2)}`
}
