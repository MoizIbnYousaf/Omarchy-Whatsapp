import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

TestCase {
  id: testCase
  name: "DropdownNotifications"

  Component {
    id: dropdownComponent
    Oma.Dropdown { demoMode: true }
  }

  function test_toggle_opens_closes_and_reopens() {
    // No service is attached: this never reads a private store or sends receipts.
    var dropdown = createTemporaryObject(dropdownComponent, testCase, { demoMode: false })
    verify(dropdown !== null)
    compare(dropdown.opened, false)
    dropdown.toggle()
    compare(dropdown.opened, true)
    dropdown.toggle()
    compare(dropdown.opened, false)
    dropdown.toggle()
    compare(dropdown.opened, true)
    dropdown.close()
  }

  function test_clear_all_requires_confirmation_and_stays_local() {
    var dropdown = createTemporaryObject(dropdownComponent, testCase)
    verify(dropdown !== null)
    compare(dropdown.notificationCount, 4)

    verify(dropdown.requestClearNotifications())
    compare(dropdown.clearConfirmOpen, true)
    var confirmation = findChild(dropdown, "clearNotificationsConfirm")
    verify(confirmation !== null)
    verify(confirmation.handleKey({ key: Qt.Key_Escape }))
    compare(dropdown.clearConfirmOpen, false)
    compare(dropdown.notificationCount, 4)

    verify(dropdown.requestClearNotifications())
    verify(confirmation.handleKey({ key: Qt.Key_Return }))
    compare(dropdown.clearConfirmOpen, false)
    compare(dropdown.notificationCount, 0)
    compare(dropdown.requestClearNotifications(), false)
  }
}
