import QtQuick

Item {
  property bool opened: false
  property string message: ""
  property string confirmText: "Confirm"
  property int selectedIndex: 1
  property color background: "transparent"
  property color foreground: "white"
  property color selectedBackground: "transparent"
  property color selectedText: "white"
  property string fontFamily: ""
  property int cornerRadius: 0

  signal canceled()
  signal confirmed()

  function handleKey(event) {
    if (!opened) return false
    if (event.key === Qt.Key_Escape) {
      canceled()
      return true
    }
    if (event.key === Qt.Key_Left || event.key === Qt.Key_Right
        || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      selectedIndex = selectedIndex === 0 ? 1 : 0
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (selectedIndex === 0) canceled()
      else confirmed()
      return true
    }
    return false
  }
}
