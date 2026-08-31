import QtQuick
import Quickshell.Io
import "AccountModel.js" as AccountModel

// Local notification acknowledgement is independent of settings and sync
// controls. Exact account+chat refs are coalesced, then drained in order.
Item {
  id: root
  visible: false
  width: 0
  height: 0

  required property string helper
  property var pendingRefs: []
  property var currentRef: AccountModel.chatRef("", "")
  readonly property bool running: acknowledgeProcess.running

  signal completed(var chatRef)
  signal failed(string message, var chatRef)

  function sameRequest(left, right) {
    if (!left || !right) return false
    if (String(left.jid || "") === "" || String(right.jid || "") === "")
      return String(left.jid || "") === "" && String(right.jid || "") === ""
        && String(left.account || "") === String(right.account || "")
    return AccountModel.sameRef(left, right)
  }

  function contains(ref) {
    if ((acknowledgeProcess.running || String(currentRef.key || "") !== "")
        && sameRequest(currentRef, ref)) return true
    return pendingRefs.some(function(candidate) {
      return sameRequest(candidate, ref)
    })
  }

  function enqueue(account, jid) {
    var ref = AccountModel.chatRef(String(account || ""), String(jid || ""))
    if (contains(ref)) return false
    var next = pendingRefs.slice()
    if (ref.jid === "") {
      // A not-yet-started aggregate acknowledgement subsumes older queued
      // exact refs. A later exact ref still queues behind a running aggregate.
      next = [ref]
    } else {
      var aggregatePending = next.some(function(candidate) {
        return String(candidate.jid || "") === ""
      })
      if (aggregatePending) return false
      next.push(ref)
    }
    pendingRefs = next
    runNext()
    return true
  }

  function runNext() {
    if (acknowledgeProcess.running || String(currentRef.key || "") !== ""
        || pendingRefs.length === 0) return
    var next = pendingRefs.slice()
    currentRef = next.shift()
    pendingRefs = next
    acknowledgeProcess.payload = JSON.stringify({
      account: currentRef.account, jid: currentRef.jid
    })
    acknowledgeProcess.stdinEnabled = true
    acknowledgeProcess.running = true
  }

  Process {
    id: acknowledgeProcess
    objectName: "notificationAcknowledgeProcess"
    property string payload: ""
    command: [root.helper, "acknowledge"]
    stdinEnabled: true
    stdout: StdioCollector {
      id: acknowledgeOutput
      objectName: "notificationAcknowledgeOutput"
    }
    stderr: StdioCollector {
      id: acknowledgeError
      objectName: "notificationAcknowledgeError"
    }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      var finished = root.currentRef
      root.currentRef = AccountModel.chatRef("", "")
      var response = null
      try { response = JSON.parse(String(acknowledgeOutput.text || "")) } catch (error) {}
      if (exitCode === 0 && response && response.ok === true) {
        root.completed(finished)
      } else {
        root.failed((response && response.error)
          || String(acknowledgeError.text || "Notification acknowledgement failed.").trim(),
          finished)
      }
      Qt.callLater(root.runNext)
    }
  }
}
