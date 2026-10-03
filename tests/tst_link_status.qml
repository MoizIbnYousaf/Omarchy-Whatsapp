import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

TestCase {
  name: "LinkStatus"
  width: 400
  height: 100
  visible: true
  when: windowShown
  Component { id: component; Oma.LinkStatus { width: 360; actionEnabled: true } }
  function test_link_states_and_action() {
    var card = createTemporaryObject(component, this)
    card.state = "connected"
    compare(card.label, "Linked · connected")
    verify(card.visible)
    compare(card.action, "")
    card.state = "relink-required"
    compare(card.label, "Link expired")
    compare(card.action, "Link again")
    var action = findChild(card, "railLinkAction")
    verify(action.visible)
    var calls = 0
    card.actionRequested.connect(function() { calls += 1 })
    mouseClick(action)
    compare(calls, 1)
    card.busy = true
    mouseClick(action)
    compare(calls, 1)
    card.busy = false
    card.demo = true
    mouseClick(action)
    compare(calls, 1)
    card.demo = false
    action.forceActiveFocus()
    keyClick(Qt.Key_Return)
    compare(calls, 2)
    card.state = "offline"
    compare(card.action, "Go online")
    card.state = "stopped"
    compare(card.action, "Resume")
    card.pauseReason = "loading media"
    compare(card.action, "")
    compare(card.label, "Sync paused · loading media")
  }
}
