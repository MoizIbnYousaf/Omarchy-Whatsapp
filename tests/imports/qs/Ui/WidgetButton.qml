import QtQuick

// The slice of Omarchy's WidgetButton that the plugin's bar item sets.
Item {
  property var bar: null
  property string text: ""
  property bool active: false
  property bool dimmed: false
  property real horizontalMargin: 8.5
  property string tooltipText: ""
  signal pressed(int button)
  implicitWidth: 40
  implicitHeight: 24
}
