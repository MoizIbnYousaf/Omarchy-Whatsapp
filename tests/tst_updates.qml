import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

TestCase {
  id: testCase
  name: "Updates"
  Component { id: controller; Oma.UpdateController {} }
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
  function test_response_errors_clear_stale_updates() {
    var item = createTemporaryObject(controller, testCase)
    item.acceptResult(JSON.stringify({ok: true, version: "v0.12.0", current: "0.11.2",
      commit: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", available: true, standalone: false}), 0)
    verify(item.release.available)
    verify(!item.install())
    item.acceptResult("not json", 0)
    compare(item.release, null)
    verify(item.message.indexOf("Could not check") >= 0)
    item.acceptResult(JSON.stringify({ok: true, version: "oops", commit: "bad"}), 0)
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
