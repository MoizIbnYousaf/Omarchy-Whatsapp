import QtQuick
import QtQuick.Controls as Controls
import OmaWhatsApp.Inputs as Native
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Native.TextField {
  id: root
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color selectionTint: Qt.rgba(accent.r, accent.g, accent.b, 0.3)
  property bool password: false
  property real horizontalPadding: Style.space(8)
  property real verticalPadding: Style.space(6)
  property bool hasCursor: false
  property string placeholderText: ""
  onBackgroundChanged: if (background) {
    background.parent = root
    background.anchors.fill = root
    background.z = -1
  }
  readonly property bool hovered: hover.hovered
  HoverHandler { id: hover }
  Text {
    textFormat: Text.PlainText
    x: root.leftPadding
    y: root.topPadding
    text: root.placeholderText
    color: root.placeholderTextColor
    font: root.font
    visible: root.text.length === 0 && !root.inputMethodComposing
  }
  property string clipboardError: ""
  selectByMouse: true
  verticalAlignment: TextInput.AlignVCenter
  echoMode: password ? TextInput.Password : TextInput.Normal
  font.family: Style.font.family
  font.pixelSize: Style.font.body
  color: foreground
  selectionColor: selectionTint
  selectedTextColor: foreground
  property color placeholderTextColor: Qt.darker(foreground, 1.6)
  leftPadding: horizontalPadding
  rightPadding: horizontalPadding
  topPadding: verticalPadding
  bottomPadding: verticalPadding
  implicitHeight: Math.max(contentHeight + topPadding + bottomPadding, Style.space(30))
  property Item background: Rectangle {
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
    border.width: 1
    border.color: root.activeFocus ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)
    radius: Style.cornerRadius
  }
  onPasteFailed: message => { clipboardError = message; errorTimer.restart() }
  Controls.ToolTip.visible: clipboardError !== ""
  Controls.ToolTip.text: clipboardError
  Timer { id: errorTimer; interval: 5000; onTriggered: root.clipboardError = "" }
}
