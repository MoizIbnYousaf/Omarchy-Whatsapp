.pragma library

// Links inside a plain-text message. Only http(s) and bare www. addresses are
// offered; message text itself stays plain, so no markup is ever rendered.
var PATTERN = /\b(?:https?:\/\/|www\.)[^\s<>"'`]+/gi

function trimTrailing(url) {
  return url.replace(/[.,;:!?)\]}]+$/, "")
}

function extract(text, limit) {
  var found = []
  var seen = {}
  var value = String(text || "")
  var match
  PATTERN.lastIndex = 0
  while ((match = PATTERN.exec(value)) !== null) {
    var url = trimTrailing(match[0])
    var target = /^www\./i.test(url) ? "https://" + url : url
    if (!seen[target]) {
      seen[target] = true
      found.push({ label: url.replace(/^https?:\/\//i, ""), url: target })
      if (found.length >= (limit || 3)) break
    }
  }
  return found
}
