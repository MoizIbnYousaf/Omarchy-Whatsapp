import QtQuick
import Quickshell
import Quickshell.Io

// The app is a git checkout made by `omarchy plugin add`. Checking compares it
// with the repository (contacting GitHub only); updating runs
// `omarchy plugin update` in a terminal, which shows the changes and asks
// first, then restarts the shell to load them.
Item {
  id: root
  property string helper: ""
  property bool active: false
  property bool online: false
  property bool checkOnLaunch: false
  property bool checkedThisLaunch: false
  readonly property bool busy: checker.running
  property var release: null
  property string message: "Check whether a newer version is available."
  signal updateAvailable(string version)

  function maybeCheck() {
    if (active && online && checkOnLaunch && !checkedThisLaunch) check()
  }
  function check() {
    if (!active || !online || busy || helper === "") return false
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
    if (exitCode !== 0 || !result || result.ok !== true) {
      message = "Could not check for updates. Try again when connected."
      return
    }
    release = result
    if (result.managed !== true) {
      message = "This copy was not installed with omarchy plugin add, so it updates from where it came from."
      return
    }
    message = result.available ? "A newer version is available."
      : "You’re up to date" + (result.current ? " (" + result.current + ")." : ".")
    if (result.available && active) updateAvailable(String(result.current || ""))
  }
  function install() {
    if (!active || !online || busy || !release || release.available !== true
        || release.managed !== true) return false
    Quickshell.execDetached(["/usr/bin/xdg-terminal-exec", "--title=Update OmaWhatsApp",
      "--hold", "--", helper, "self-update"])
    message = "Confirm the update in the terminal that opened; the shell restarts when it is done."
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
    command: [root.helper, "update-check"]
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
