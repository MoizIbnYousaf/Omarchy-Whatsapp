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
  function normalFillFor(foreground, accent) { return "#181818" }
  function hoverFillFor(foreground, accent) { return "#242424" }
  function selectedFillFor(foreground, accent) { return "#303030" }
  function hoverBorderFor(foreground, accent) { return "#555555" }
}
