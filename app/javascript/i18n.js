// Strings for the page's scripts: the "js" keys of config/locales, which the
// layout puts in <script type="application/json" id="i18n">.
//   t("bulk_upload.uploading", { done: 1, total: 4 })
//   t("offline.sent", { count: 2 })   // one/other plurals pick by count
let strings

function load() {
  if (!strings) {
    try { strings = JSON.parse(document.getElementById("i18n")?.textContent || "{}") } catch { strings = {} }
  }
  return strings
}

export function t(key, vars = {}) {
  let value = key.split(".").reduce((node, part) => node?.[part], load())
  if (value && typeof value === "object") value = value[vars.count === 1 ? "one" : "other"]
  if (typeof value !== "string") return key
  return value.replace(/%\{(\w+)\}/g, (_, name) => vars[name] ?? "")
}

// The page's language, for number and date formatting.
export const locale = () => document.documentElement.lang || "en"
