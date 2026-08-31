pragma Singleton
import QtQuick

QtObject {
  readonly property color foreground: "#eeeeee"
  readonly property color background: "#111111"
  readonly property color accent: "#66ccaa"
  readonly property color urgent: "#ee6666"
  readonly property QtObject popups: QtObject {
    readonly property color background: "#111111"
  }
}
