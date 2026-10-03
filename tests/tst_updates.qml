import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// The app is a git checkout made by omarchy plugin add: checking asks the
// helper, updating runs omarchy plugin update in a terminal.
TestCase {
  id: testCase
  name: "Updates"
  Component { id: controller; Oma.UpdateController { helper: "/checkout/bin/omawhatsapp" } }
  readonly property string commit: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  function test_disabled_offline_and_demo_never_check() {
    var item = createTemporaryObject(controller, testCase)
    verify(!item.check())
    item.active = true
    verify(!item.check())
    verify(!item.busy)
    item.active = false
    item.online = true
    item.checkOnLaunch = true
    verify(!item.check())
    verify(!item.busy)
  }

  function test_the_check_asks_the_helper() {
    var item = createTemporaryObject(controller, testCase)
    item.online = true
    item.active = true
    verify(item.check())
    compare(findChild(item, "releaseChecker").command, ["/checkout/bin/omawhatsapp", "update-check"])
  }

  function test_only_a_checkout_updates_from_the_app() {
    var item = createTemporaryObject(controller, testCase)
    item.active = true
    item.online = true
    item.acceptResult(JSON.stringify({ ok: true, managed: false, current: "0.15.0", available: false }), 0)
    verify(item.message.indexOf("not installed with omarchy plugin add") >= 0)
    verify(!item.install())
    var seen = []
    item.updateAvailable.connect(function(version) { seen.push(version) })
    item.acceptResult(JSON.stringify({ ok: true, managed: true, current: "0.15.0", commit: commit,
      remote_commit: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", available: true }), 0)
    compare(seen, ["0.15.0"])
    verify(item.install())
    verify(item.message.indexOf("terminal") >= 0)
  }

  function test_response_errors_clear_stale_updates() {
    var item = createTemporaryObject(controller, testCase)
    item.acceptResult(JSON.stringify({ ok: true, managed: true, current: "0.15.0", commit: commit,
      remote_commit: commit, available: false }), 0)
    verify(item.message.indexOf("up to date") >= 0)
    item.acceptResult("not json", 0)
    compare(item.release, null)
    verify(item.message.indexOf("Could not check") >= 0)
    item.acceptResult(JSON.stringify({ ok: false, error: "offline" }), 1)
    compare(item.release, null)
  }

  function test_auto_check_once_per_open_and_offline_cancels() {
    var item = createTemporaryObject(controller, testCase)
    item.online = true
    item.checkOnLaunch = true
    verify(!item.busy)
    item.active = true
    verify(item.busy)
    verify(item.checkedThisLaunch)
    var process = findChild(item, "releaseChecker")
    process.running = false
    item.maybeCheck()
    verify(!item.busy)
    item.active = false
    item.active = true
    verify(item.busy)
    item.online = false
    verify(!item.busy)
  }
}
