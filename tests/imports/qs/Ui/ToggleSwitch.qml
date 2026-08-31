import QtQuick

Item {
  property bool checked: false
  property bool busy: false
  property color foreground: "white"
  property color accent: "white"
  signal toggled()
  implicitWidth: 42
  implicitHeight: 24
}
