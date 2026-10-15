import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma
import "../plugins/omawhatsapp/ShortcutModel.js" as Model

TestCase {
  id: testCase
  name: "CustomShortcuts"
  width: 1000; height: 750
  visible: true; when: windowShown
  Component {
    id: serviceComponent
    Item {
      property var shortcuts: ({})
      property bool enterSends: true
      property bool accept: true
      property var writes: []
      signal settingsCompleted()
      signal settingsFailed(string message)
      function setPreference(key, value) {
        if (!accept) return false
        writes = writes.concat([{key: key, value: value}]); return true
      }
      function complete() { shortcuts = writes[writes.length - 1].value; settingsCompleted() }
    }
  }
  Component { id: hostComponent; Item { width: testCase.width; height: testCase.height } }
  Component { id: settingsComponent; Oma.ShortcutSettings { width: Math.min(700, parent.width) } }
  Component { id: catcherComponent; Oma.ShortcutKeyCatcher {} }
  function create(demo) {
    var host = createTemporaryObject(hostComponent, testCase)
    var service = createTemporaryObject(serviceComponent, host)
    var view = createTemporaryObject(settingsComponent, host, { service: service, overlayHost: host, demoMode: demo === true })
    verify(view !== null); wait(0)
    return {host:host, service:service, view:view}
  }
  function test_exact_matching_and_send_defaults() {
    compare(Model.eventSequence({key:Qt.Key_G, modifiers:Qt.ControlModifier|Qt.AltModifier}), "Ctrl+Alt+G")
    compare(Model.eventSequence({key:Qt.Key_Shift, modifiers:Qt.ShiftModifier}), "")
    verify(Model.matches("newChat", {key:Qt.Key_N, modifiers:Qt.ControlModifier}, {}, true))
    verify(!Model.matches("newChat", {key:Qt.Key_N, modifiers:Qt.ControlModifier|Qt.AltModifier}, {}, true))
    verify(!Model.matches("newChat", {key:Qt.Key_N, modifiers:Qt.ControlModifier}, {newChat:[]}, true))
    compare(Model.bindings("send", {}, false), ["Ctrl+Enter"])
    compare(Model.bindings("send", {send:["Alt+S"]}, false), ["Alt+S"])
    verify(!Model.safeWhileTyping({key:Qt.Key_A, modifiers:Qt.NoModifier}))
    verify(!Model.safeWhileTyping({key:Qt.Key_Space, modifiers:Qt.NoModifier}))
    verify(Model.safeWhileTyping({key:Qt.Key_Escape, modifiers:Qt.NoModifier}))
    verify(Model.safeWhileTyping({key:Qt.Key_G, modifiers:Qt.ControlModifier}))
    compare(Model.configurationError({}, true), "")
    compare(Model.configurationError({}, false), "")
  }
  function test_conflicts_respect_context_and_protect_typing() {
    verify(Model.conflict("find", ["Ctrl+N"], {}, true).indexOf("Start a new chat") >= 0)
    compare(Model.conflict("find", ["Ctrl+N"], {newChat:[]}, true), "")
    compare(Model.conflict("dropdownRefresh", ["R"], {}, true), "")
    compare(Model.conflict("bold", ["Ctrl+B"], {}, true), "")
    verify(Model.captureError("send", "S") !== "")
    verify(Model.captureError("forwardSend", "F") !== "")
    verify(Model.captureError("find", "Tab") !== "")
    verify(Model.captureError("find", "Escape") !== "")
  }
  function test_click_capture_cancel_save_and_failure() {
    var h=create()
    mouseClick(findChild(h.view, "shortcut-find-0"))
    compare(h.view.editing, "find")
    var capture=findChild(h.host, "shortcutCapture")
    tryVerify(function() { return capture.activeFocus })
    keyClick(Qt.Key_G, Qt.ControlModifier|Qt.AltModifier)
    compare(h.view.candidate, "Ctrl+Alt+G")
    verify(h.view.save()); compare(h.service.writes.length, 1)
    compare(h.service.writes[0].key, "shortcuts")
    compare(h.service.shortcuts, ({}), "do not claim persistence before helper success")
    h.service.settingsFailed("Disk is full")
    compare(h.view.error, "Disk is full"); compare(h.view.editing, "find")
    verify(h.view.save()); h.service.complete()
    compare(h.view.editing, ""); compare(h.service.shortcuts.find, ["Ctrl+Alt+G"])
    h.view.edit("find", 0); keyClick(Qt.Key_Escape)
    compare(h.view.editing, ""); compare(h.service.writes.length, 2)
  }
  function test_conflicting_key_cannot_save_and_unbound_action_can_be_set() {
    var h=create()
    h.view.edit("find", 0); h.view.candidate="Ctrl+N"
    verify(h.view.conflict !== ""); verify(!h.view.save()); compare(h.service.writes.length, 0)
    h.view.cancel(); h.service.shortcuts={find:[]}
    mouseClick(findChild(h.view,"addShortcut-find"))
    h.view.candidate="Alt+F"; verify(h.view.save()); h.service.complete()
    compare(h.service.shortcuts.find,["Alt+F"])
  }
  function test_remove_reset_and_demo_isolation() {
    var h=create(true)
    h.view.edit("record",0); verify(h.view.remove()); compare(h.view.keys("record"),[])
    verify(h.view.reset("record")); compare(h.view.keys("record"),["Ctrl+Shift+V"])
    h.view.edit("find",0); h.view.candidate="Alt+F"; verify(h.view.save())
    compare(h.view.keys("find"),["Alt+F"]); compare(h.service.writes.length,0)
    verify(h.view.commit(({}))); compare(h.view.keys("find"),["Ctrl+F"])
  }
  function test_custom_mini_client_navigation_and_old_key_disabled() {
    var catcher=createTemporaryObject(catcherComponent,testCase,{shortcuts:{next:["Alt+J"]}})
    var moves=[]; catcher.moveRequested.connect(function(dx,dy){moves.push(dy)})
    catcher.forceActiveFocus()
    keyClick(Qt.Key_J); compare(moves.length,0)
    keyClick(Qt.Key_J,Qt.AltModifier); compare(moves,[1])
    catcher.blocked=true; keyClick(Qt.Key_J,Qt.AltModifier); compare(moves.length,1)
  }
  function test_narrow_dialog_and_search() {
    var h=create(true); h.host.width=360; h.view.width=360
    var search=findChild(h.view,"shortcutSearch"); search.text="zoom"
    compare(h.view.filtered().length,3)
    h.view.edit("zoomIn",0); wait(0)
    var capture=findChild(h.host,"shortcutCapture")
    verify(capture.width <= 360); verify(capture.mapToItem(h.host,0,0).x >= 0)
    h.view.cancel(); search.text="no matching action"; compare(h.view.filtered().length,0)
  }
}
