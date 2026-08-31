import QtQuick
import Quickshell.Io

// The only networkful account-rail operations live here. Both require an
// explicit click; ordinary chat refreshes remain local-only.
Item {
  id: root

  required property string helper
  required property var accounts
  property bool avatarBusy: false
  property string statusMessage: ""
  property string linkPhase: "idle"
  property string linkTarget: ""
  property int linkPolls: 0
  readonly property bool linkBusy: linkPhase !== "idle"
  readonly property bool busy: linkBusy || avatarBusy

  signal refreshRequested()

  function parseJson(raw) {
    try { return JSON.parse(String(raw || "{}")) } catch (error) { return null }
  }

  function linkCommand(name) {
    return ["/usr/bin/xdg-terminal-exec",
      "--title=OmaWhatsApp · Link " + String(name || ""), "--hold", "--",
      helper, "link-account", String(name || ""), "--authorize", "interactive"]
  }

  function linkAccount(name) {
    var value = String(name || "").trim()
    if (busy || value === "") return false
    linkPhase = "running"
    linkTarget = value
    linkPolls = 0
    statusMessage = "Finish linking " + value + " in the terminal"
    linkProcess.command = linkCommand(value)
    linkProcess.running = true
    linkPoll.restart()
    return true
  }

  function refreshAvatars() {
    if (busy) return false
    avatarBusy = true
    statusMessage = "Refreshing recent chat photos…"
    avatarProcess.payload = JSON.stringify({
      authorization: "remote-read", limit: 12
    })
    avatarProcess.stdinEnabled = true
    avatarProcess.running = true
    return true
  }

  function reconcileLink() {
    if (linkPhase === "idle" || linkTarget === "") return
    for (var i = 0; i < accounts.length; i++) {
      var account = accounts[i] || ({})
      if (String(account.account || "") !== linkTarget) continue
      if (account.authenticated === true) {
        statusMessage = linkTarget + " linked"
        linkTarget = ""
        linkPhase = linkPhase === "running" ? "reconciled" : "idle"
        linkPoll.stop()
      }
      return
    }
  }

  function recordLinkExit(exitCode) {
    if (linkPhase === "reconciled") {
      linkPhase = "idle"
      return false
    }
    if (linkPhase !== "running" || linkTarget === "") return false
    linkPhase = "probing"
    statusMessage = "Checking whether " + linkTarget + " finished linking…"
    linkPoll.stop()
    return true
  }

  function handleLinkExit(exitCode) {
    if (!recordLinkExit(exitCode)) return
    linkProbe.command = [helper, "session-ready", "--account", linkTarget]
    linkProbe.running = true
    refreshRequested()
  }

  function handleLinkProbeExit(exitCode) {
    if (linkPhase !== "probing" || linkTarget === "") return
    statusMessage = Number(exitCode) === 0
      ? linkTarget + " linked"
      : "Linking was not finished; use the same name to resume"
    linkPhase = "idle"
    linkTarget = ""
    refreshRequested()
  }

  function handleLinkPoll() {
    linkPolls += 1
    if (linkPhase === "running") {
      if (linkPolls >= 150)
        statusMessage = "Linking is still open in the terminal"
      refreshRequested()
      return
    }
  }

  function finishAvatarRefresh(exitCode, stdoutText, stderrText) {
    avatarBusy = false
    var response = parseJson(stdoutText)
    if (exitCode !== 0 || !response || response.ok !== true) {
      statusMessage = (response && response.error)
        || String(stderrText || "Chat photos could not be refreshed.").trim()
      return
    }
    var checked = Math.max(0, Number(response.checked || 0))
    var failed = Math.max(0, Number(response.failed || 0))
    var refreshed = Math.max(0, Number(response.refreshed || 0))
    if (checked > 0 && failed >= checked) {
      statusMessage = "Chat photos could not be refreshed"
    } else if (failed > 0) {
      statusMessage = (refreshed > 0 ? String(refreshed) + " refreshed; " : "")
        + String(failed) + " chat photos could not be refreshed"
    } else {
      statusMessage = refreshed > 0
        ? String(refreshed) + " chat photos refreshed"
        : (response.cached > 0 ? "Chat photos are current" : "No chat photos available")
    }
    refreshRequested()
  }

  onAccountsChanged: reconcileLink()

  Timer {
    id: linkPoll
    interval: 2000
    repeat: true
    onTriggered: root.handleLinkPoll()
  }

  Process {
    id: linkProcess
    command: []
    onExited: function(exitCode) { root.handleLinkExit(exitCode) }
  }

  Process {
    id: linkProbe
    command: []
    onExited: function(exitCode) { root.handleLinkProbeExit(exitCode) }
  }

  Process {
    id: avatarProcess
    property string payload: ""
    command: [root.helper, "avatars"]
    stdinEnabled: true
    stdout: StdioCollector { id: avatarOutput }
    stderr: StdioCollector { id: avatarError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      root.finishAvatarRefresh(exitCode, avatarOutput.text, avatarError.text)
    }
  }
}
