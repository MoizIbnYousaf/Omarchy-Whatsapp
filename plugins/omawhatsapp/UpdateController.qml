import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property bool active: false
  property bool online: false
  property bool checkOnLaunch: false
  property bool checkedThisLaunch: false
  readonly property bool busy: checker.running
  property var release: null
  property string message: "Check for a stable release on GitHub."
  readonly property string script: decodeURIComponent(String(Qt.resolvedUrl("updates.py")).replace(/^file:\/\//, ""))
  signal updateAvailable(string version)

  function maybeCheck() {
    if (active && online && checkOnLaunch && !checkedThisLaunch) check()
  }
  function check() {
    if (!active || !online || busy) return false
    checkedThisLaunch = true
    release = null
    message = "Checking for updates…"
    checker.running = true
    return true
  }
  function acceptResult(text, exitCode) {
    var result = null
    try { result = JSON.parse(text) } catch (error) {}
    release = null
    if (exitCode !== 0 || !result || result.ok !== true
        || !/^v?\d+\.\d+\.\d+$/.test(String(result.version))
        || !/^[0-9a-f]{40}$/.test(String(result.commit))) {
      message = "Could not check for updates. Try again when connected."
      return
    }
    release = result
    message = result.available ? result.version + " is available."
      : "You’re up to date (" + result.current + ")."
    if (result.available && active) updateAvailable(result.version)
  }
  function install() {
    if (!active || !online || busy || !release || !release.available
        || !release.standalone) return false
    Quickshell.execDetached(["omarchy", "launch", "terminal", "python3", script,
      "install", "--version", release.version, "--commit", release.commit])
    message = "Confirm the full-app update in the terminal that opened."
    return true
  }
  onActiveChanged: {
    if (!active) checkedThisLaunch = false
    maybeCheck()
  }
  onOnlineChanged: {
    if (!online && checker.running) checker.running = false
    maybeCheck()
  }
  onCheckOnLaunchChanged: maybeCheck()
  Process {
    id: checker
    objectName: "releaseChecker"
    command: ["python3", root.script, "check"]
    stdout: StdioCollector { id: output }
    stderr: StdioCollector {}
    onExited: function(code) { root.acceptResult(output.text, code) }
  }
  Timer {
    interval: 65000
    running: checker.running
    onTriggered: checker.running = false
  }
}
