import QtQuick
import Quickshell.Io
import qs.Ui as Ui

// Account IDs are bounded ASCII identifiers, not free-form text. Keep Qt's
// editor read-only permanently: even an idle editable TextInput asks the
// native clipboard for text on dataChanged (before a paste or validation).
// Navigation/selection/copy remain native; mutations are explicit and bounded.
Ui.TextField {
  id: root
  objectName: "accountNameField"
  readOnly: true
  selectByMouse: true
  maximumLength: 64
  cursorVisible: activeFocus
  property string helper: "omawhatsapp"
  property int revision: 0
  property var undoStates: []
  property var redoStates: []
  signal pasteFailed(string message)

  function reset() {
    pasteProcess.running = false
    text = ""
    undoStates = []
    redoStates = []
    revision++
  }
  function snapshot() {
    return {text: text, cursor: cursorPosition}
  }
  function restore(state) {
    text = state.text
    cursorPosition = state.cursor
  }
  function replaceSelection(value) {
    var start = selectionStart
    var end = selectionEnd
    var next = text.slice(0, start) + value + text.slice(end)
    if (next.length > 64 || !/^[A-Za-z0-9._-]*$/.test(next)) return false
    undoStates = undoStates.concat([snapshot()]).slice(-64)
    redoStates = []
    text = next
    cursorPosition = start + value.length
    return true
  }
  function undoEdit() {
    if (!undoStates.length) return
    redoStates = redoStates.concat([snapshot()]).slice(-64)
    var previous = undoStates[undoStates.length - 1]
    undoStates = undoStates.slice(0, -1)
    restore(previous)
  }
  function redoEdit() {
    if (!redoStates.length) return
    undoStates = undoStates.concat([snapshot()]).slice(-64)
    var next = redoStates[redoStates.length - 1]
    redoStates = redoStates.slice(0, -1)
    restore(next)
  }
  // Never call the inherited paste(): it invokes Qt's unbounded reader.
  function requestPaste() {
    if (!activeFocus || pasteProcess.running) return
    pasteProcess.requestRevision = revision
    pasteProcess.running = true
  }
  function applyPaste(result, requestedRevision) {
    if (!activeFocus || revision !== requestedRevision) return
    if (!result || result.ok !== true || typeof result.text !== "string") {
      pasteFailed("The account name could not be pasted.")
      return
    }
    if (!replaceSelection(result.text))
      pasteFailed("Use at most 64 letters, numbers, dots, underscores or hyphens.")
  }
  onTextChanged: revision++
  onSelectionStartChanged: revision++
  onSelectionEndChanged: revision++
  onActiveFocusChanged: {
    revision++
    if (!activeFocus) pasteProcess.running = false
  }
  Keys.priority: Keys.BeforeItem
  Keys.onPressed: event => {
    if (event.matches(StandardKey.Paste)) {
      requestPaste()
      event.accepted = true
    } else if (event.matches(StandardKey.Cut)) {
      copy()
      replaceSelection("")
      event.accepted = true
    } else if (event.matches(StandardKey.Undo)) {
      undoEdit()
      event.accepted = true
    } else if (event.matches(StandardKey.Redo)) {
      redoEdit()
      event.accepted = true
    } else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
      if (selectionStart === selectionEnd) {
        var from = event.key === Qt.Key_Backspace ? Math.max(0, cursorPosition - 1) : cursorPosition
        var to = event.key === Qt.Key_Delete ? Math.min(text.length, cursorPosition + 1) : cursorPosition
        if (event.modifiers & Qt.ControlModifier) {
          if (event.key === Qt.Key_Backspace) from = 0
          else to = text.length
        }
        select(from, to)
      }
      replaceSelection("")
      event.accepted = true
    } else if (event.text && event.text.charCodeAt(0) >= 32 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
               && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter
               && event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab) {
      replaceSelection(event.text)
      event.accepted = true
    }
  }

  Process {
    id: pasteProcess
    objectName: "accountNamePasteProcess"
    property int requestRevision: 0
    command: [root.helper, "paste-account-name"]
    stdout: StdioCollector { id: pasteOutput }
    onExited: code => {
      var result = null
      if (code === 0) {
        try { result = JSON.parse(pasteOutput.text) } catch (_) {}
      }
      root.applyPaste(result, requestRevision)
    }
  }
}
