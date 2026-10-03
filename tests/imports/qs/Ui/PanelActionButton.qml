import QtQuick

Rectangle {
  id: root
  property string iconText: ""
  property string tooltipText: ""
  property color foreground: "#eeeeee"
  property color hoverColor: foreground
  property string fontFamily: "monospace"
  property real fontSize: 20
  property real size: 22
  property bool focusable: false
  property bool hasCursor: false
  property bool bordered: false
  signal clicked()
  signal hovered(bool isHovered)
  implicitWidth: size
  implicitHeight: size
  color: "transparent"
  Text { anchors.centerIn: parent; text: root.iconText }
  MouseArea { anchors.fill: parent; onClicked: root.clicked() }
}
