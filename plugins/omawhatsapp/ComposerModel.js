.pragma library

function ownsOperation(owner, expected) {
  return String(owner || "") === String(expected || "")
}

function demoMessage(text, hasAttachment, reply, nowMilliseconds) {
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
    reactions: [],
    quoted_id: String(reply && reply.id || ""),
    quoted_sender: String(reply && reply.sender || ""),
    quoted_text: String(reply && reply.text || ""),
    quoted_media_type: String(reply && reply.media_type || "")
  }
}

// A failed multi-file send may already have delivered a prefix. Remove only
// those exact paths; preserving every unsent or newly-added attachment makes
// the next send safe instead of duplicating WhatsApp mutations.
function attachmentKey(value) {
  var text = String(value || "")
  if (text.indexOf("file://") !== 0) return text
  var path = text.slice(7)
  if (path.indexOf("localhost/") === 0) path = path.slice(9)
  try { return decodeURIComponent(path) } catch (error) { return path }
}

function remainingAttachments(current, partial) {
  var values = Array.isArray(current) ? current.slice() : []
  var sent = partial && Array.isArray(partial.sent_paths)
    ? partial.sent_paths.map(attachmentKey) : []
  if (sent.length === 0) return values
  return values.filter(function(path) {
    return sent.indexOf(attachmentKey(path)) < 0
  })
}

function copyState(current) {
  var state = Object.assign({
    text: "", attachments: [], stickerPath: "", reply: null, edit: null,
    draftBeforeEdit: "", draftMentionsBeforeEdit: [], mentions: [], error: ""
  }, current || ({}))
  state.attachments = Array.isArray(state.attachments)
    ? state.attachments.slice() : []
  state.mentions = Array.isArray(state.mentions) ? state.mentions.slice() : []
  state.draftMentionsBeforeEdit = Array.isArray(state.draftMentionsBeforeEdit)
    ? state.draftMentionsBeforeEdit.slice() : []
  return state
}

function copyRequest(current) {
  var request = Object.assign({}, current || ({}))
  ;["paths", "mentions", "options"].forEach(function(key) {
    if (Array.isArray(request[key])) request[key] = request[key].slice()
  })
  return request
}

// A transport result belongs to the immutable account/chat and submitted
// composer state captured before the process starts. Surfaces must never
// reconstruct that identity from the currently selected chat.
function writeIntent(chatRef, kind, request, submitted) {
  var account = String(chatRef && chatRef.account || "")
  var jid = String(chatRef && chatRef.jid || "")
  return {
    chatRef: {
      account: account,
      jid: jid,
      key: jid === "" ? "" : account + "\n" + jid
    },
    kind: String(kind || ""),
    request: copyRequest(request),
    submitted: copyState(submitted)
  }
}

function validWriteIntent(intent) {
  return !!intent && String(intent.kind || "") !== ""
    && !!intent.chatRef && String(intent.chatRef.jid || "") !== ""
}

function writeIntentMatches(intent, chatRef, kind) {
  var resultKind = String(kind || "")
  return validWriteIntent(intent) && !!chatRef
    && String(intent.chatRef.account || "") === String(chatRef.account || "")
    && String(intent.chatRef.jid || "") === String(chatRef.jid || "")
    && (resultKind === "" || String(intent.kind || "") === resultKind)
}

function startedIntentState(intent) {
  if (!validWriteIntent(intent)) return copyState({})
  return startedState(intent.submitted, intent.kind, intent.request)
}

function completedIntentState(current, intent) {
  if (!validWriteIntent(intent)) return copyState(current)
  return completedState(current, intent.kind, intent.request)
}

function failedIntentState(current, intent, details) {
  if (!validWriteIntent(intent)) return copyState(current)
  return failedState(current, intent.kind, intent.request,
                     intent.submitted, details)
}

// File-picker results use the same composer shape whether they arrive while
// their chat is visible or after the user has moved elsewhere. The caller can
// store `state` under the captured chat key and dispose only `rejected` private
// stages; no result ever needs to fall through to the newly selected chat.
function pickedState(current, incoming, kind, limit) {
  var state = copyState(current)
  var values = Array.isArray(incoming) ? incoming.map(String).filter(function(path) {
    return path.indexOf("file://") === 0
  }) : []
  var maximum = Math.max(1, Number(limit || 10))
  var rejected = []
  var mode = String(kind || "document")

  if (mode === "sticker") {
    var sticker = values.length > 0 ? values[0] : ""
    if (sticker === "") return { state: state, rejected: values, overflow: false }
    rejected = state.attachments.filter(function(path) { return path !== sticker })
      .concat(values.slice(1))
    state.attachments = [sticker]
    state.stickerPath = sticker
    state.error = ""
    return { state: state, rejected: rejected, overflow: values.length > 1 }
  }

  var existing = state.stickerPath !== "" ? [] : state.attachments.slice()
  if (state.stickerPath !== "") rejected = rejected.concat(
    state.attachments.filter(function(path) { return values.indexOf(path) < 0 }))
  state.stickerPath = ""
  for (var i = 0; i < values.length; i++) {
    var path = values[i]
    if (existing.indexOf(path) >= 0) continue
    if (existing.length < maximum) existing.push(path)
    else rejected.push(path)
  }
  state.attachments = existing
  state.error = rejected.length > 0 ? "Up to " + maximum + " attachments at once" : ""
  return { state: state, rejected: rejected, overflow: rejected.length > 0 }
}

function sameList(left, right) {
  var a = Array.isArray(left) ? left : []
  var b = Array.isArray(right) ? right : []
  if (a.length !== b.length) return false
  for (var i = 0; i < a.length; i++) {
    if (JSON.stringify(a[i]) !== JSON.stringify(b[i])) return false
  }
  return true
}

function sameContext(left, right) {
  if (!left || !right) return !left && !right
  return String(left.id || "") === String(right.id || "")
}

// Consume composer-owned fields as soon as a write starts. Later success
// signals must not guess whether text still belongs to that request.
function startedState(current, kind, request) {
  var state = copyState(current)
  var payload = request || ({})
  if (kind === "send" || kind === "files") {
    state.text = ""
    state.mentions = []
  } else if (kind === "edit") {
    state.text = String(state.draftBeforeEdit || "")
    state.mentions = state.draftMentionsBeforeEdit.slice()
    state.edit = null
    state.draftBeforeEdit = ""
    state.draftMentionsBeforeEdit = []
  }
  var submittedReply = String(payload.reply_id || "")
  if (submittedReply !== "" && state.reply
      && String(state.reply.id || "") === submittedReply) state.reply = null
  state.error = ""
  return state
}

// A successful write only confirms which staged attachments were consumed.
// Text, mentions, and composer context were already consumed at start and may
// since have been replaced by fresh user input.
function completedState(current, kind, request) {
  var state = copyState(current)
  var payload = request || ({})
  if (kind === "files") {
    state.attachments = remainingAttachments(state.attachments, {
      sent_paths: Array.isArray(payload.paths) ? payload.paths : []
    })
  } else if (kind === "sticker") {
    state.attachments = remainingAttachments(state.attachments, {
      sent_paths: [String(payload.path || "")]
    })
    if (String(state.stickerPath || "") === String(payload.path || ""))
      state.stickerPath = ""
  }
  return state
}

// Restore a failed request only while each consumed field still has its exact
// post-start value. Fresh input therefore always wins, even when it happens
// while the process is in flight. Confirmed partial-file successes stay gone.
function failedState(current, kind, request, submitted, details) {
  var state = copyState(current)
  var snapshot = copyState(submitted)
  var consumed = startedState(snapshot, kind, request)
  if (kind === "files") state.attachments = remainingAttachments(state.attachments, details)

  var textUntouched = String(state.text || "") === String(consumed.text || "")
    && sameList(state.mentions, consumed.mentions)
  if (kind === "send" || kind === "files") {
    if (textUntouched) {
      state.text = String(snapshot.text || "")
      state.mentions = snapshot.mentions.slice()
    }
  } else if (kind === "edit" && textUntouched
             && sameContext(state.edit, consumed.edit)) {
    state.text = String(snapshot.text || "")
    state.mentions = snapshot.mentions.slice()
    state.edit = snapshot.edit
    state.draftBeforeEdit = String(snapshot.draftBeforeEdit || "")
    state.draftMentionsBeforeEdit = snapshot.draftMentionsBeforeEdit.slice()
  }

  if (sameContext(state.reply, consumed.reply)) state.reply = snapshot.reply
  return state
}
