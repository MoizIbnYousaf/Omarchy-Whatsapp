.pragma library
.import "ShortcutCatalog.js" as Catalog

var actions = Catalog.actions
function action(id) { return actions.filter(function(a) { return a.id === id })[0] || null }
function bindings(id, overrides, enterSends) {
  if (overrides && Object.prototype.hasOwnProperty.call(overrides, id)) return overrides[id]
  if (id === "send" && enterSends === false) return ["Ctrl+Enter"]
  var item = action(id)
  return item ? item.keys : []
}
function label(sequence) { return String(sequence).replace(/Meta\+/g, "Super+").replace(/Escape/g, "Esc") }
function eventSequence(event) {
  var key = event.key
  if ([Qt.Key_Control, Qt.Key_Shift, Qt.Key_Alt, Qt.Key_Meta, Qt.Key_AltGr].indexOf(key) >= 0) return ""
  var names = ({})
  names[Qt.Key_Return] = "Enter"; names[Qt.Key_Enter] = "Enter"
  names[Qt.Key_Escape] = "Escape"; names[Qt.Key_Space] = "Space"
  names[Qt.Key_Tab] = "Tab"; names[Qt.Key_Backtab] = "Tab"
  names[Qt.Key_Backspace] = "Backspace"; names[Qt.Key_Delete] = "Delete"
  names[Qt.Key_Up] = "Up"; names[Qt.Key_Down] = "Down"
  names[Qt.Key_Left] = "Left"; names[Qt.Key_Right] = "Right"
  names[Qt.Key_PageUp] = "PageUp"; names[Qt.Key_PageDown] = "PageDown"
  names[Qt.Key_Home] = "Home"; names[Qt.Key_End] = "End"
  names[Qt.Key_Insert] = "Insert"
  var name = names[key] || (key >= Qt.Key_F1 && key <= Qt.Key_F35 ? "F" + (key - Qt.Key_F1 + 1)
    : key >= 32 && key <= 126 ? String.fromCharCode(key).toUpperCase() : "")
  if (!name) return ""
  var parts = []
  if (event.modifiers & Qt.ControlModifier) parts.push("Ctrl")
  if (event.modifiers & Qt.AltModifier) parts.push("Alt")
  // Shift on a symbol is represented by the symbol itself, e.g. + and /.
  if ((event.modifiers & Qt.ShiftModifier) && !/^[^A-Z0-9]$/.test(name)) parts.push("Shift")
  if (event.modifiers & Qt.MetaModifier) parts.push("Meta")
  return parts.concat([name]).join("+")
}
function matches(id, event, overrides, enterSends) {
  return bindings(id, overrides, enterSends).indexOf(eventSequence(event)) >= 0
}
function overlap(a, b) {
  if (a.scope === b.scope) return true
  if (a.scope === "viewer" || b.scope === "viewer" || a.scope === "forward" || b.scope === "forward") return false
  // Full-app-only navigation and mini-client-only actions do not compete.
  if ((a.scope === "navigation" && b.scope === "dropdown") || (b.scope === "navigation" && a.scope === "dropdown"))
    return ["next", "previous", "openChat", "back", "search", "openMedia"].indexOf(a.scope === "navigation" ? a.id : b.id) >= 0
  return a.scope === "window" || b.scope === "window"
}
function conflict(id, sequences, overrides, enterSends) {
  var item = action(id)
  if (!item) return ""
  for (var i = 0; i < actions.length; i++) {
    var other = actions[i]
    if (other.id === id || !overlap(item, other)) continue
    // Existing context-sensitive Ctrl+B: selected text formats, otherwise sidebar.
    if ((id === "bold" && other.id === "sidebar") || (id === "sidebar" && other.id === "bold")) continue
    var used = bindings(other.id, overrides, enterSends)
    for (var j = 0; j < sequences.length; j++)
      if (used.indexOf(sequences[j]) >= 0) return label(sequences[j]) + " is already used for “" + other.title + "”."
  }
  return ""
}
function captureError(id, sequence) {
  if (!sequence) return "Press a letter, number, function key or navigation key."
  if (sequence === "Tab" || sequence === "Shift+Tab") return "Tab and Shift+Tab stay available for moving between controls."
  if (sequence === "Escape" && ["back", "viewerClose"].indexOf(id) < 0) return "Esc stays available to cancel and go back."
  if (["Ctrl+A", "Ctrl+C", "Ctrl+X", "Ctrl+Z", "Ctrl+Shift+Z", "Ctrl+Y"].indexOf(sequence) >= 0)
    return "This key stays available for standard text editing."
  var item = action(id)
  if (!item) return ""
  if ((item.scope === "window" || item.scope === "composer") && !/(Ctrl|Alt|Meta)\+/.test(sequence)
      && !(id === "send" && sequence === "Enter") && !/(^|\+)F\d+$/.test(sequence))
    return "Use Ctrl, Alt or Super with a key so typing stays safe."
  return ""
}

function configurationError(overrides, enterSends) {
  for (var i = 0; i < actions.length; i++) {
    var item = actions[i]
    var error = conflict(item.id, bindings(item.id, overrides, enterSends), overrides, enterSends)
    if (error) return error
  }
  return ""
}
