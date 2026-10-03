.pragma library

// A chat is only unique together with the account it came from: the same
// contact or group can be reachable from more than one linked phone.

function accountOf(chat) {
  return chat ? String(chat.account || "") : ""
}

function chatKey(account, jid) {
  var target = String(jid || "")
  return target === "" ? "" : String(account || "") + "\n" + target
}

// Account and JID are one identity everywhere outside map storage. Keeping the
// derived key beside them prevents callers from accidentally using that key as
// a transport JID.
function chatRef(account, jid) {
  var scope = String(account || "")
  var target = String(jid || "")
  return { account: scope, jid: target, key: chatKey(scope, target) }
}

function refOf(chat) {
  return chatRef(accountOf(chat), chat ? chat.jid : "")
}

function sameRef(left, right) {
  if (!left || !right) return false
  return String(left.jid || "") !== ""
    && String(left.jid || "") === String(right.jid || "")
    && String(left.account || "") === String(right.account || "")
}

function sameChat(chat, account, jid) {
  if (!chat) return false
  return String(chat.jid || "") === String(jid || "")
    && accountOf(chat) === String(account || "")
}

function findChat(chats, ref) {
  var values = Array.isArray(chats) ? chats : []
  if (!ref || String(ref.jid || "") === "") return null
  return values.find(function(chat) {
    return sameChat(chat, ref.account, ref.jid)
  }) || null
}

// Message/member responses do not echo the account. The Process that issued
// them owns that part of the identity, so accept a response only while its
// immutable request still names the currently selected chat.
function responseMatches(responseChat, requestedRef, selectedRef) {
  return sameRef(requestedRef, selectedRef)
    && !!responseChat
    && String(responseChat.jid || "") === String(requestedRef.jid || "")
}

function labelOf(chat) {
  if (!chat) return ""
  return String(chat.account_label || chat.account || "")
}

function isMultiAccount(accounts) {
  return Array.isArray(accounts) && accounts.length > 1
}

// Where an account sits in the configured order; its color follows it.
function accountIndex(accounts, name) {
  var values = Array.isArray(accounts) ? accounts : []
  var wanted = String(name || "")
  for (var i = 0; i < values.length; i++) {
    if (String(values[i] && values[i].account || "") === wanted) return i
  }
  return -1
}

function accountOptions(accounts) {
  var values = Array.isArray(accounts) ? accounts : []
  var options = []
  var seen = []
  for (var i = 0; i < values.length; i++) {
    var account = values[i] || ({})
    var scope = String(account.account || "")
    if (seen.indexOf(scope) >= 0) continue
    seen.push(scope)
    options.push({
      scope: scope,
      label: String(account.label || account.account || "default")
    })
  }
  return options.length > 1
    ? [{ scope: "", label: "All" }].concat(options) : options
}

function normalizeScope(scope, accounts) {
  var value = String(scope || "")
  if (value === "") return ""
  var options = accountOptions(accounts)
  for (var i = 0; i < options.length; i++)
    if (options[i].scope === value) return value
  return ""
}

// Rail views, as in WhatsApp: archived chats live in their own view and stay
// out of the others, except that a search looks through them too.
var CHAT_VIEWS = ["all", "unread", "groups", "archived"]
function matchesView(chat, view, searching) {
  var archived = chat && chat.archived === true
  var name = String(view || "all")
  if (name === "archived") return archived
  if (archived && !(searching && name === "all")) return false
  if (name === "unread") return Number(chat.unread || 0) > 0
  if (name === "groups") return String(chat.kind || "") === "group"
  // People whose message is the last one in the chat: replies you owe.
  if (name === "reply") return String(chat.kind || "") === "dm"
    && chat.last_from_me !== true && Number(chat.timestamp || 0) > 0
  return true
}
function viewCount(chats, scope, view) {
  var account = String(scope || "")
  return (Array.isArray(chats) ? chats : []).filter(function(chat) {
    return (account === "" || accountOf(chat) === account) && matchesView(chat, view, false)
  }).length
}

function filterChats(chats, scope, query, limit, view) {
  var values = Array.isArray(chats) ? chats : []
  var account = String(scope || "")
  var needle = String(query || "").trim().toLowerCase()
  var filtered = values.filter(function(chat) {
    if (account !== "" && accountOf(chat) !== account) return false
    if (view !== undefined && !matchesView(chat, view, needle !== "")) return false
    return needle === ""
      || String(chat.name || "").toLowerCase().indexOf(needle) >= 0
      || String(chat.preview || "").toLowerCase().indexOf(needle) >= 0
  })
  var maximum = Number(limit || 0)
  return maximum > 0 ? filtered.slice(0, Math.max(1, maximum)) : filtered
}

function accountNameError(value, legacyAccount) {
  var name = String(value || "").trim()
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(name))
    return "Use 1–64 letters, digits, dots, underscores, or hyphens."
  if (legacyAccount === true && name === "primary")
    return "primary is reserved for your existing account."
  return ""
}

// Status has two deliberate scopes: the merged rail is available when any
// one account is usable, while mutations require the selected account itself.
function statusReadiness(payload) {
  var value = payload || ({})
  var authenticated = value.authenticated === true
  var databaseReady = value.database_ready === true
  return {
    authenticated: authenticated,
    databaseReady: databaseReady,
    accountReady: authenticated && databaseReady,
    railReady: value.rail_ready === true
  }
}

function unreadyAccountLabels(accounts) {
  var labels = []
  var values = Array.isArray(accounts) ? accounts : []
  for (var i = 0; i < values.length; i++) {
    var account = values[i] || ({})
    if (account.authenticated === true && account.database_ready === true) continue
    var label = String(account.label || account.account || "").trim()
    if (label !== "" && labels.indexOf(label) < 0) labels.push(label)
  }
  return labels
}

function unreadyAccountSummary(accounts) {
  var labels = unreadyAccountLabels(accounts)
  return labels.length > 0 ? labels.join(", ") + " unavailable" : ""
}

// The rail is merged, so a row names its account before its preview. With one
// account that prefix would be noise.
function previewPrefix(chat, multiAccount) {
  if (multiAccount !== true) return ""
  var label = labelOf(chat)
  return label === "" ? "" : label + " · "
}

function storeDirectories(accounts, fallback) {
  var stores = []
  var values = Array.isArray(accounts) ? accounts : []
  for (var i = 0; i < values.length; i++) {
    var store = String(values[i] && values[i].store || "")
    if (store.charAt(0) === "/" && stores.indexOf(store) < 0) stores.push(store)
  }
  if (stores.length > 0) return stores
  var single = String(fallback || "")
  return single.charAt(0) === "/" ? [single] : []
}

function defaultStoreDirectory(configured, stateHome, home) {
  var explicit = String(configured || "").trim()
  if (explicit.charAt(0) === "/") return explicit
  var base = String(stateHome || "").trim()
  if (base.charAt(0) !== "/") {
    var userHome = String(home || "").trim()
    if (userHome.charAt(0) !== "/") return ""
    base = userHome + "/.local/state"
  }
  return base + "/wacli"
}

// Forwarding never crosses an account: wacli can only forward inside one store.
function forwardTargets(chats, chat) {
  var values = Array.isArray(chats) ? chats : []
  var account = accountOf(chat)
  var jid = chat ? String(chat.jid || "") : ""
  return values.filter(function(candidate) {
    return accountOf(candidate) === account && String(candidate.jid || "") !== jid
  })
}

// A forward picker belongs to the chat that opened it, not to whichever chat
// the shared service selects while the modal is still visible.
function forwardTargetsForRef(chats, ref) {
  var origin = findChat(chats, ref)
  return origin ? forwardTargets(chats, origin) : []
}

// The message the "N unread messages" divider sits above: the Nth newest
// message from someone else when the chat opened. Anchoring to that message,
// not to a position from the bottom, keeps your own replies and anything that
// arrives later below the divider. Lists are newest first.
function unreadAnchorId(messages, count) {
  var wanted = Number(count || 0)
  var items = messages || []
  var anchor = ""
  var seen = 0
  for (var i = 0; i < items.length && seen < wanted; i++) {
    var item = items[i]
    if (!item || item.from_me === true || item.pending === true) continue
    anchor = String(item.id || "")
    seen++
  }
  return anchor
}

// Row of a message in a list whose albums fold several messages into one row.
function messageIndexOf(items, id) {
  var target = String(id || "")
  var rows = items || []
  if (target === "") return -1
  for (var i = 0; i < rows.length; i++) {
    if (!rows[i]) continue
    if (String(rows[i].id || "") === target) return i
    var album = rows[i].album_items || []
    for (var j = 0; j < album.length; j++)
      if (album[j] && String(album[j].id || "") === target) return i
  }
  return -1
}

// Messages loaded for this chat, not counting bubbles still being sent.
function hasStoredMessages(messages) {
  var items = messages || []
  for (var i = 0; i < items.length; i++)
    if (items[i] && items[i].pending !== true) return true
  return false
}

// Two messages form one run when the same person sent them within ten
// minutes: timelines tighten the gap and name the sender once.
function sameRun(older, newer) {
  if (!older || !newer) return false
  if ((older.from_me === true) !== (newer.from_me === true)) return false
  if (older.from_me !== true
      && String(older.sender_jid || older.sender || "") !== String(newer.sender_jid || newer.sender || ""))
    return false
  return Math.abs(Number(newer.timestamp || 0) - Number(older.timestamp || 0)) < 600
}

// The list's preview for the latest message: media gets its kind, and a bare
// "[image]"-style placeholder reads as a word. A caption or file name stays.
var PREVIEW_KINDS = {
  image: { kind: "photo", label: "Photo" },
  video: { kind: "video", label: "Video" },
  gif: { kind: "gif", label: "GIF" },
  sticker: { kind: "sticker", label: "Sticker" },
  audio: { kind: "voice", label: "Voice message" },
  document: { kind: "document", label: "Document" },
  location: { kind: "location", label: "Location" }
}

function previewParts(chat) {
  var text = String(chat && chat.preview || "")
  var entry = PREVIEW_KINDS[String(chat && chat.last_media_type || "").toLowerCase()]
  if (!entry) return { kind: "", text: text }
  var placeholder = /^\[[a-z]+\]$/i.test(text.trim()) || text.trim() === ""
  return { kind: entry.kind, text: placeholder ? entry.label : text }
}

// A group's preview names who wrote it, by first name, as on the phone.
function previewSender(chat) {
  if (!chat || chat.kind !== "group" || chat.last_from_me === true) return ""
  var name = String(chat.last_sender || "").trim().split(/\s+/)[0] || ""
  return name === "" ? "" : name + ": "
}

// Nerd Font glyphs shared by the full app and the dropdown: a sent message's
// delivery state ("" when none is known) and the kind of a preview.
function deliveryGlyph(status) {
  var value = String(status || "")
  if (value === "sent") return "󰄬"
  if (value === "delivered" || value === "read" || value === "played") return "󰄭"
  if (value === "pending") return "󰅐"
  if (value === "error") return "󰀦"
  return ""
}

function previewKindGlyph(kind) {
  return ({ photo: "󰄀", video: "󰕧", gif: "󰵸", sticker: "󰞅", voice: "󰍬",
    document: "󰈙", location: "󰍎" })[String(kind || "")] || ""
}
