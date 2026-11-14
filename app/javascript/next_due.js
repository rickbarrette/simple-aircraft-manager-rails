import { t, locale } from "i18n"

// Next-due math, mirroring Compliance.next_due in app/services/compliance.rb:
// months land on the END of the month, then days are added; hours are added
// to the hours at completion. Dates are "YYYY-MM-DD" strings (no timezones).

export function nextDue(rule, dateStr, hours) {
  const due = {}
  if (!rule) return due
  const months = Number(rule.months) || 0
  const days = Number(rule.days) || 0
  const interval = Number(rule.hours) || 0

  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateStr || "")
  if (m && (months > 0 || days > 0)) {
    let d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
    if (months > 0) d = new Date(d.getFullYear(), d.getMonth() + months + 1, 0) // last day of month
    if (days > 0) d.setDate(d.getDate() + days)
    due.date = [d.getFullYear(), String(d.getMonth() + 1).padStart(2, "0"), String(d.getDate()).padStart(2, "0")].join("-")
  }

  const base = parseFloat(hours)
  if (interval > 0 && !Number.isNaN(base)) due.hours = Math.round((base + interval) * 10) / 10
  return due
}

export function describeDue(due) {
  const parts = []
  if (due.hours != null) parts.push(t("next_due.tach", { hours: due.hours.toLocaleString(locale(), { minimumFractionDigits: 1, maximumFractionDigits: 1 }) }))
  if (due.date) {
    const [y, mo, d] = due.date.split("-").map(Number)
    parts.push(new Date(y, mo - 1, d).toLocaleDateString(locale(), { month: "short", day: "numeric", year: "numeric" }))
  }
  if (parts.length === 0) return ""
  return parts.length > 1 ? t("next_due.either", { first: parts[0], second: parts[1] }) : parts[0]
}
