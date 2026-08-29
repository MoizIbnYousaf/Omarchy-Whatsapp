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

function sameChat(chat, account, jid) {
  if (!chat) return false
  return String(chat.jid || "") === String(jid || "")
    && accountOf(chat) === String(account || "")
}

function labelOf(chat) {
  if (!chat) return ""
  return String(chat.account_label || chat.account || "")
}

function isMultiAccount(accounts) {
  return Array.isArray(accounts) && accounts.length > 1
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
    if (store !== "" && stores.indexOf(store) < 0) stores.push(store)
  }
  if (stores.length > 0) return stores
  var single = String(fallback || "")
  return single === "" ? [] : [single]
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
