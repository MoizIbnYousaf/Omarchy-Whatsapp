import QtQuick
import QtQuick.Controls as Controls
import OmaWhatsApp.Inputs as Native

Native.TextArea {
  padding: 6
  id: root
  textFormat: TextEdit.PlainText
  property string placeholderText: ""
  property color placeholderTextColor: "#777777"
  property Item background: null
  onBackgroundChanged: if (background) {
    background.parent = root
    background.anchors.fill = root
    background.z = -1
  }
  property string clipboardError: ""
  implicitHeight: contentHeight + topPadding + bottomPadding
  Text {
    textFormat: Text.PlainText
    x: root.leftPadding
    y: root.topPadding
    text: root.placeholderText
    color: root.placeholderTextColor
    font: root.font
    visible: root.text.length === 0 && !root.inputMethodComposing
  }
  onPasteFailed: message => { clipboardError = message; errorTimer.restart() }
  Controls.ToolTip.visible: clipboardError !== ""
  Controls.ToolTip.text: clipboardError
  Timer { id: errorTimer; interval: 5000; onTriggered: root.clipboardError = "" }
}
