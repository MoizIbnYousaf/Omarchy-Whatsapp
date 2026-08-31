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

function filterChats(chats, scope, query, limit) {
  var values = Array.isArray(chats) ? chats : []
  var account = String(scope || "")
  var needle = String(query || "").trim().toLowerCase()
  var filtered = values.filter(function(chat) {
    if (account !== "" && accountOf(chat) !== account) return false
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
