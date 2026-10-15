import QtQuick
import "ShortcutModel.js" as Shortcuts

// Mini-client navigation shares the same persisted action map as the full app.
Item {
  id: root
  property bool blocked: false
  property var shortcuts: ({})
  signal moveRequested(int dx, int dy)
  signal activateRequested()
  signal closeRequested()
  signal tabRequested(int direction)
  signal actionRequested(string action)
  focus: true
  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (blocked) return
    function matches(id) { return Shortcuts.matches(id, event, root.shortcuts, true) }
    if (matches("back")) root.closeRequested()
    else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
      root.tabRequested((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
    else if (matches("next")) root.moveRequested(0, 1)
    else if (matches("previous")) root.moveRequested(0, -1)
    else if (matches("panelNext")) root.moveRequested(1, 0)
    else if (matches("panelPrevious")) root.moveRequested(-1, 0)
    else if (matches("openChat") || matches("openMedia")) root.activateRequested()
    else {
      var action = ["search", "dropdownRefresh", "expand", "dropdownCompose"].filter(matches)[0]
      if (!action) return
      root.actionRequested(action)
    }
    event.accepted = true
  }
}
