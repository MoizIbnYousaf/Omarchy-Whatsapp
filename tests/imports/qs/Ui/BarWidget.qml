import QtQuick

// The slice of Omarchy's BarWidget that the plugin's bar item reads.
Item {
  property QtObject bar: null
  property string moduleName: ""
  property var settings: ({})
  readonly property bool vertical: bar ? bar.vertical === true : false
}
