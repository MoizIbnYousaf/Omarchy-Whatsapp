import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

TestCase {
  id: testCase
  name: "AccountSwitcher"

  Component {
    id: switcherComponent
    Oma.AccountSwitcher {
      width: 320
      accounts: [{ account: "work", label: "Work" },
                 { account: "home", label: "Home" }]
      foreground: "#ffffff"
      background: "#101010"
      accent: "#22c55e"
      muted: "#aaaaaa"
      urgent: "#ef4444"
      fontFamily: "sans"
    }
  }

  function test_completion_status_remains_visible_after_busy_clears() {
    var switcher = createTemporaryObject(switcherComponent, testCase, {
      avatarBusy: false,
      statusMessage: "Chat photos are current"
    })
    verify(switcher !== null)
    var status = findChild(switcher, "accountOperationStatus")
    verify(switcher.hasStatus)
    compare(status.text, "Chat photos are current")
    verify(status.implicitHeight > 0)
    verify(switcher.implicitHeight > switcher.controlHeight)
  }
}
