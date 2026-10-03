pragma Singleton
import QtQuick

QtObject {
  readonly property real cornerRadius: 6
  readonly property QtObject font: QtObject {
    readonly property string family: "monospace"
    readonly property int caption: 12
    readonly property int bodySmall: 14
    readonly property int body: 16
    readonly property int icon: 20
    readonly property int iconLarge: 28
    readonly property int heading: 20
    readonly property int title: 24
  }

  function space(value) { return Number(value) }
  // The shell's fills are translucent tints of the foreground (0.04, 0.08,
  // 0.18); solid stand-ins once hid a strip the text showed through.
  function tint(foreground, alpha) {
    var color = Qt.color(foreground || "#eeeeee")
    return Qt.rgba(color.r, color.g, color.b, alpha)
  }
  function normalFillFor(foreground, accent) { return tint(foreground, 0.04) }
  function hoverFillFor(foreground, accent) { return tint(foreground, 0.08) }
  function selectedFillFor(foreground, accent) { return tint(foreground, 0.18) }
  function hoverBorderFor(foreground, accent) { return tint(foreground, 0.25) }
}
