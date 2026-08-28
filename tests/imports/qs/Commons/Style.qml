pragma Singleton
import QtQuick

QtObject {
  readonly property real cornerRadius: 6
  readonly property QtObject font: QtObject {
    readonly property string family: "monospace"
    readonly property int caption: 12
    readonly property int body: 16
    readonly property int icon: 20
    readonly property int heading: 20
    readonly property int title: 24
  }

  function space(value) { return Number(value) }
}
