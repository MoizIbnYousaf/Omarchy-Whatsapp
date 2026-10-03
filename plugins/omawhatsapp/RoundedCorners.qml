import QtQuick
import QtQuick.Shapes

// Rounds square content (a photo, a video frame) by painting its four outside
// corners in `color`, the bubble's color as seen on screen. No shader, so it
// renders the same everywhere, offscreen tests included.
Item {
  id: root
  property real radius: 9
  property color color: "black"
  anchors.fill: parent

  Repeater {
    model: 4
    delegate: Shape {
      required property int index
      width: root.radius
      height: root.radius
      x: index % 2 === 0 ? 0 : root.width - root.radius
      y: index < 2 ? 0 : root.height - root.radius
      rotation: [0, 90, 270, 180][index]
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillColor: root.color
        startX: 0
        startY: 0
        PathLine { x: root.radius; y: 0 }
        PathArc {
          x: 0
          y: root.radius
          radiusX: root.radius
          radiusY: root.radius
          direction: PathArc.Counterclockwise
        }
        PathLine { x: 0; y: 0 }
      }
    }
  }
}
