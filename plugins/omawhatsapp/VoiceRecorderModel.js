function normalizeState(value) {
  var state = String(value || "idle").trim().toLowerCase()
  var allowed = ["idle", "preparing", "recording", "finalizing", "review",
    "sending", "discarding", "error"]
  return allowed.indexOf(state) >= 0 ? state : "idle"
}

function hasDraft(value) {
  var state = normalizeState(value)
  return state !== "idle"
}

function isCapturing(value) {
  var state = normalizeState(value)
  return state === "preparing" || state === "recording" || state === "finalizing"
}

function canReview(value) {
  return normalizeState(value) === "review"
}

function stateLabel(value, offline) {
  var state = normalizeState(value)
  if (state === "preparing") return "Opening microphone…"
  if (state === "recording") return "Recording voice note"
  if (state === "finalizing") return "Preparing preview…"
  if (state === "review") return offline === true ? "Voice draft · offline" : "Voice draft ready"
  if (state === "sending") return "Sending voice note…"
  if (state === "discarding") return "Discarding…"
  if (state === "error") return "Voice note unavailable"
  return ""
}

function elapsedLabel(milliseconds) {
  var total = Math.max(0, Math.min(3599999, Math.floor(Number(milliseconds) || 0)))
  var seconds = Math.floor(total / 1000)
  var minutes = Math.floor(seconds / 60)
  var remainder = seconds % 60
  return (minutes < 10 ? "0" : "") + minutes + ":"
    + (remainder < 10 ? "0" : "") + remainder
}

function progress(position, duration) {
  var total = Number(duration || 0)
  if (!isFinite(total) || total <= 0) return 0
  return Math.max(0, Math.min(1, Number(position || 0) / total))
}
