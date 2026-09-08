import QtQuick
import QtQuick.Controls
import QtTest
import "../plugins/omawhatsapp" as Oma

TestCase {
  id: testCase
  name: "ComposerInteraction"
  width: 1080
  height: 720
  visible: true
  when: windowShown

  Component { id: appComponent; Oma.App { demoMode: true; opened: true } }
  Component { id: dropdownComponent; Oma.Dropdown { demoMode: true } }

  function harness(dropdown) {
    var view = createTemporaryObject(dropdown ? dropdownComponent : appComponent, testCase)
    verify(view !== null)
    if (dropdown) {
      view.width = 420
      view.height = 620
      view.openConversation(view.demoChats[0])
    }
    wait(0)
    var input = findChild(view, "composerInput")
    var flick = findChild(view, "composerFlickable")
    verify(input !== null)
    verify(flick !== null)
    return { view: view, input: input, flick: flick }
  }

  function assertCursorVisible(h) {
    var r = h.input.cursorRectangle
    verify(r.y >= h.flick.contentY - 1,
      "Cursor is above viewport: " + JSON.stringify([r.y, h.flick.contentY]))
    verify(r.y + r.height <= h.flick.contentY + h.flick.height + 1,
      "Cursor is below viewport: " + JSON.stringify([r.y, r.height, h.flick.contentY, h.flick.height]))
  }

  function test_shrinking_limit_keeps_cursor_visible_data() {
    return [{ tag: "app", dropdown: false }, { tag: "dropdown", dropdown: true }]
  }
  function test_shrinking_limit_keeps_cursor_visible(data) {
    var h = harness(data.dropdown)
    h.view.composerMaxLines = 10
    h.input.text = "1\n2\n3\n4\n5\n6\n7\n8\n9\n10"
    h.input.cursorPosition = h.input.length
    h.input.forceActiveFocus()
    wait(10)
    assertCursorVisible(h)
    h.view.composerMaxLines = 4
    wait(10)
    assertCursorVisible(h)
  }

  function test_typing_and_navigation_keep_cursor_visible_data() {
    return [{ tag: "app", dropdown: false }, { tag: "dropdown", dropdown: true }]
  }
  function test_typing_and_navigation_keep_cursor_visible(data) {
    var h = harness(data.dropdown)
    h.input.forceActiveFocus()
    for (var i = 0; i < 14; i++) {
      keyClick(Qt.Key_A)
      keyClick(Qt.Key_Return, Qt.ShiftModifier)
    }
    wait(10)
    compare(h.input.lineCount, 15)
    assertCursorVisible(h)
    keyClick(Qt.Key_Home, Qt.ControlModifier)
    wait(10)
    assertCursorVisible(h)
    keyClick(Qt.Key_End, Qt.ControlModifier)
    wait(10)
    assertCursorVisible(h)
  }

  function test_clicking_empty_composer_space_focuses_input() {
    var h = harness(false)
    var surface = findChild(h.view, "composerSurface")
    h.input.focus = false
    mouseClick(surface, surface.width / 2, surface.height - 12)
    tryCompare(h.input, "activeFocus", true)
    keyClick(Qt.Key_A)
    compare(h.input.text, "a")
  }

  function test_line_limit_bounds_the_actual_viewport_data() {
    var cases = []
    ;[false, true].forEach(function(dropdown) {
      ;[4, 6, 8, 10].forEach(function(limit) {
        cases.push({ tag: (dropdown ? "dropdown-" : "app-") + limit,
          dropdown: dropdown, limit: limit })
      })
    })
    return cases
  }
  function test_line_limit_bounds_the_actual_viewport(data) {
    var h = harness(data.dropdown)
    h.view.composerMaxLines = data.limit
    h.input.text = "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12"
    h.input.cursorPosition = h.input.length
    wait(10)
    var lineHeight = h.input.positionToRectangle(2).y - h.input.positionToRectangle(0).y
    verify(lineHeight > 0)
    verify(h.flick.height <= data.limit * lineHeight + 1,
      "The viewport exceeds its configured line limit")
    assertCursorVisible(h)
  }
}
