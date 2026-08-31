import QtQuick

// One resident lease arbitrates every Qt media player across the full app,
// dropdown, and viewer. Acquiring a lease is atomic: the previous owner's
// binding becomes false immediately and its player stops.
QtObject {
  id: root

  property var lease: ({
    surface: "", account: "", jid: "", messageId: ""
  })

  function acquire(surface, chatRef, messageId) {
    var owner = String(surface || "")
    var account = String(chatRef && chatRef.account || "")
    var jid = String(chatRef && chatRef.jid || "")
    var message = String(messageId || "")
    if (owner === "" || jid === "" || message === "") return false
    lease = {
      surface: owner, account: account, jid: jid, messageId: message
    }
    return true
  }

  function owns(surface, chatRef, messageId) {
    return String(lease.surface || "") === String(surface || "")
      && String(lease.account || "") === String(chatRef && chatRef.account || "")
      && String(lease.jid || "") === String(chatRef && chatRef.jid || "")
      && String(lease.messageId || "") === String(messageId || "")
  }

  function messageFor(surface, chatRef) {
    return String(lease.surface || "") === String(surface || "")
      && String(lease.account || "") === String(chatRef && chatRef.account || "")
      && String(lease.jid || "") === String(chatRef && chatRef.jid || "")
      ? String(lease.messageId || "") : ""
  }

  function releaseSurface(surface) {
    if (String(lease.surface || "") !== String(surface || "")) return false
    lease = { surface: "", account: "", jid: "", messageId: "" }
    return true
  }
}
