.pragma library

// Callers supply Qt.locale().timeFormat(Locale.ShortFormat) for System mode.
// Keep the same clock pattern across chat previews, messages, and media.
function clockPattern(preference, systemPattern) {
  if (preference === "12h") return "h:mm AP"
  if (preference === "24h") return "HH:mm"
  return String(systemPattern || "HH:mm")
}

// Day grouping for the conversation. Timestamps are Unix seconds; `now` is a
// Date so tests can pin "today".
function dayKey(timestamp) {
  var date = new Date(Number(timestamp || 0) * 1000)
  return date.getFullYear() + "-" + date.getMonth() + "-" + date.getDate()
}

function dayLabel(timestamp, now) {
  var date = new Date(Number(timestamp || 0) * 1000)
  var today = now ? new Date(now.getTime()) : new Date()
  today.setHours(0, 0, 0, 0)
  var day = new Date(date.getTime())
  day.setHours(0, 0, 0, 0)
  var days = Math.round((today.getTime() - day.getTime()) / 86400000)
  if (days === 0) return "Today"
  if (days === 1) return "Yesterday"
  var names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
  if (days > 1 && days < 7) return names[date.getDay()]
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  var label = date.getDate() + " " + months[date.getMonth()]
  return date.getFullYear() === today.getFullYear() ? label : label + " " + date.getFullYear()
}

// Newest-first lists (the timeline's order): a message starts a new day when
// the next, older, message falls on another day or there is none.
function startsDay(messages, index) {
  if (!Array.isArray(messages) || index < 0 || index >= messages.length) return false
  if (index === messages.length - 1) return true
  return dayKey(messages[index].timestamp) !== dayKey(messages[index + 1].timestamp)
}

// The chat list's stamp for its latest message: the time today, then
// "Yesterday", the weekday within the week, and a short date after that. The
// date keeps the locale's day/month order; the year shows only when it differs.
function listStamp(timestamp, now, clock, localeDatePattern) {
  var seconds = Number(timestamp || 0)
  if (!isFinite(seconds) || seconds <= 0) return ""
  var date = new Date(seconds * 1000)
  var today = now ? new Date(now.getTime()) : new Date()
  today.setHours(0, 0, 0, 0)
  var day = new Date(date.getTime())
  day.setHours(0, 0, 0, 0)
  var days = Math.round((today.getTime() - day.getTime()) / 86400000)
  if (days <= 0) return Qt.formatTime(date, String(clock || "HH:mm"))
  if (days === 1) return "Yesterday"
  if (days < 7) return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][date.getDay()]
  var monthFirst = /^[^d]*M/.test(String(localeDatePattern || "dd/MM/yyyy"))
  var pattern = monthFirst ? "MM/dd" : "dd/MM"
  if (date.getFullYear() !== today.getFullYear()) pattern += "/yy"
  return Qt.formatDate(date, pattern)
}
