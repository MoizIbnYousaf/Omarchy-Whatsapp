import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma
TestCase {
  id: suite
  name: "SafeInputs"
  when: windowShown
  width: 400; height: 300
  Component { id: line; Oma.SafeTextField { width: 300; height: 40 } }
  Component { id: area; Oma.SafeTextArea { width: 300; height: 150 } }
  function test_native_typing_and_undo_data() { return [{tag:"field",component:line},{tag:"area",component:area}] }
  function test_native_typing_and_undo(data) {
    var editor=createTemporaryObject(data.component,suite)
    verify(editor!==null)
    editor.forceActiveFocus()
    keyClick("a"); keyClick("b"); keyClick("c")
    compare(editor.text,"abc")
    keyClick(Qt.Key_A,Qt.ControlModifier)
    keyClick("x")
    compare(editor.text,"x")
    keyClick(Qt.Key_Z,Qt.ControlModifier)
    compare(editor.text,"abc")
    editor.readOnly=true
    keyClick("y")
    compare(editor.text,"abc")
    editor.readOnly=false
    editor.deselect();editor.cursorPosition=editor.length
    keyClick("z")
    compare(editor.text,"abcz")
  }
  function test_native_paste_error_preserves_text() {
    var editor=createTemporaryObject(line,suite)
    editor.text="Keep me"
    editor.forceActiveFocus()
    keyClick(Qt.Key_V,Qt.ControlModifier)
    // This suite runs with a nonexistent Wayland display: never private clipboard.
    tryVerify(function(){return editor.clipboardError!==""},4500)
    compare(editor.text,"Keep me")
  }
}
