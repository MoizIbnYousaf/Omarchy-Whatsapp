import QtQuick
import QtQuick.Controls as Controls
import OmaWhatsApp.Inputs as Native

Native.TextEdit {
  id: root
  textFormat: TextEdit.PlainText
  property string clipboardError: ""
  onPasteFailed: message => { clipboardError = message; errorTimer.restart() }
  Controls.ToolTip.visible: clipboardError !== ""
  Controls.ToolTip.text: clipboardError
  Timer { id: errorTimer; interval: 5000; onTriggered: root.clipboardError = "" }
}
