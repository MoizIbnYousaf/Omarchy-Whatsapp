.pragma library

function clampIndex(index, length) {
  var count = Math.max(0, Number(length) || 0)
  if (count === 0) return 0
  return Math.max(0, Math.min(count - 1, Number(index) || 0))
}

// Compact conversations render newest-first data with BottomToTop, so a
// positive visual delta moves toward a lower model index.
function visualMessageIndex(index, visualDelta, length) {
  return clampIndex(Number(index || 0) - Number(visualDelta || 0), length)
}

function fullAppPayload(chat) {
  if (!chat || !chat.jid) return {}
  return {
    account: String(chat.account || ""),
    jid: String(chat.jid),
    conversation: true
  }
}

function demoMessage(text, hasAttachment, nowMilliseconds) {
  var now = Number(nowMilliseconds) || Date.now()
  return {
    id: "demo-" + now,
    text: String(text || ""),
    sender: "You",
    timestamp: Math.floor(now / 1000),
    from_me: true,
    media_type: hasAttachment === true ? "document" : "",
    mime_type: "",
    local_path: "",
    reactions: []
  }
}
