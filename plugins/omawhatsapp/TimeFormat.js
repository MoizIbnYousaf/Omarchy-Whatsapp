.pragma library

// Callers supply Qt.locale().timeFormat(Locale.ShortFormat) for System mode.
// Keep the same clock pattern across chat previews, messages, and media.
function clockPattern(preference, systemPattern) {
  if (preference === "12h") return "h:mm AP"
  if (preference === "24h") return "HH:mm"
  return String(systemPattern || "HH:mm")
}
