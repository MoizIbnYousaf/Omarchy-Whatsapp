import QtQuick
import QtQuick.Window
import QtTest
import "../plugins/omawhatsapp" as Oma

TestCase {
  id: suite
  name: "AccountNameField"
  when: windowShown
  width: 400
  height: 120
  Component {
    id: fieldComponent
    Oma.AccountNameField { width: 300; height: 40 }
  }
  function typeText(value) {
    for (var i = 0; i < value.length; i++) keyClick(value[i])
  }
  function field() {
    var item = createTemporaryObject(fieldComponent, suite)
    verify(item !== null)
    item.forceActiveFocus()
    tryCompare(item, "activeFocus", true)
    return item
  }
  function test_native_editor_stays_readonly_while_typing() {
    var item = field()
    compare(item.readOnly, true)
    typeText("work.one_2-test")
    compare(item.text, "work.one_2-test")
    keyClick(Qt.Key_A, Qt.ControlModifier)
    typeText("personal")
    compare(item.text, "personal")
    keyClick(Qt.Key_Backspace)
    compare(item.text, "persona")
    keyClick(Qt.Key_Z, Qt.ControlModifier)
    compare(item.text, "personal")
    keyClick(Qt.Key_Z, Qt.ControlModifier | Qt.ShiftModifier)
    compare(item.text, "persona")
    compare(item.readOnly, true)
  }
  function test_limits_invalid_characters_and_middle_insertion() {
    var item = field()
    typeText("abcd")
    item.cursorPosition = 2
    keyClick(Qt.Key_Delete)
    compare(item.text, "abd")
    typeText(" /\\@")
    compare(item.text, "abd")
    item.selectAll()
    verify(item.replaceSelection("a".repeat(64)))
    typeText("b")
    compare(item.text.length, 64)
  }
  function test_explicit_paste_is_bounded_and_selection_aware() {
    var item = field()
    typeText("work")
    item.selectAll()
    item.requestPaste()
    var process = findChild(item, "accountNamePasteProcess")
    verify(process.running)
    compare(process.command[1], "paste-account-name")
    item.applyPaste({ok:true, text:"home"}, process.requestRevision)
    compare(item.text, "home")
    compare(item.readOnly, true)
  }
  function test_late_paste_cannot_replace_new_edit_or_reopened_field() {
    var item = field()
    typeText("work")
    var revision = item.revision
    typeText("2")
    item.applyPaste({ok:true, text:"stale"}, revision)
    compare(item.text, "work2")
    revision = item.revision
    item.focus = false
    item.forceActiveFocus()
    item.applyPaste({ok:true, text:"stale"}, revision)
    compare(item.text, "work2")
  }
  function test_reset_discards_previous_edit_history() {
    var item = field()
    typeText("work")
    item.reset()
    item.undoEdit()
    compare(item.text, "")
    compare(item.redoStates.length, 0)
  }
  function test_failed_paste_preserves_input() {
    var item = field()
    typeText("work")
    item.applyPaste({ok:false}, item.revision)
    compare(item.text, "work")
    item.applyPaste({ok:true,text:"x".repeat(65)}, item.revision)
    compare(item.text, "work")
  }
}
