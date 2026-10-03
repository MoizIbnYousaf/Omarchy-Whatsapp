import QtQuick
import QtQuick.Controls
import qs.Commons

// WhatsApp's formatting options for the composer. Each row applies to the
// selection (or the cursor, or the current line) and shows how the phone
// writes it, so the markers are never a mystery. As the composer's right-click
// menu it also carries the editing actions above them.
Popup {
  id: root
  objectName: "formatMenu"

  property color foreground: Color.foreground
  property color surface: Color.background
  property color accent: Color.accent
  property color muted: foreground
  property string fontFamily: Style.font.family
  // Cut, copy, paste and select all above the formats (the right-click menu).
  property bool editActions: false
  property bool hasSelection: false
  signal chosen(string kind)

  readonly property var editOptions: [
    { kind: "cut", label: "Cut", keys: "Ctrl+X", needsSelection: true },
    { kind: "copy", label: "Copy", keys: "Ctrl+C", needsSelection: true },
    { kind: "paste", label: "Paste", keys: "Ctrl+V", needsSelection: false },
    { kind: "select-all", label: "Select all", keys: "Ctrl+A", needsSelection: false }
  ]

  readonly property var options: [
    { kind: "bold", label: "Bold", hint: "*text*", keys: "Ctrl+B" },
    { kind: "italic", label: "Italic", hint: "_text_", keys: "Ctrl+I" },
    { kind: "strike", label: "Strikethrough", hint: "~text~", keys: "Ctrl+Shift+X" },
    { kind: "mono", label: "Monospace", hint: "```text```", keys: "Ctrl+Shift+M" },
    { kind: "code", label: "Inline code", hint: "`text`", keys: "" },
    { kind: "bullet", label: "Bulleted list", hint: "- text", keys: "" },
    { kind: "numbered", label: "Numbered list", hint: "1. text", keys: "" },
    { kind: "quote", label: "Quote", hint: "> text", keys: "" }
  ]

  function choose(kind) {
    close()
    chosen(String(kind || ""))
  }

  width: Style.space(300)
  padding: Style.space(6)
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

  background: Rectangle {
    radius: Style.cornerRadius
    color: root.surface
    border.width: 1
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
  }

  contentItem: Column {
    spacing: Style.space(2)
    Repeater {
      model: root.editActions ? root.editOptions : []
      delegate: Rectangle {
        required property var modelData
        readonly property bool usable: !modelData.needsSelection || root.hasSelection
        objectName: "formatEdit-" + modelData.kind
        width: root.availableWidth
        height: Style.space(32)
        radius: Style.cornerRadius
        color: editHover.hovered && usable ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
        opacity: usable ? 1 : 0.45
        Text {
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          textFormat: Text.PlainText
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.keys
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        HoverHandler { id: editHover; cursorShape: parent.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: parent.usable; onTapped: root.choose(modelData.kind) }
      }
    }
    Rectangle {
      visible: root.editActions
      width: root.availableWidth
      height: Style.space(9)
      color: "transparent"
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
      }
    }
    Repeater {
      model: root.options
      delegate: Rectangle {
        required property var modelData
        objectName: "formatOption-" + modelData.kind
        width: root.availableWidth
        height: Style.space(32)
        radius: Style.cornerRadius
        color: optionHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
        Text {
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: modelData.kind === "bold"
          font.italic: modelData.kind === "italic"
          font.strikeout: modelData.kind === "strike"
        }
        Text {
          textFormat: Text.PlainText
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.hint + (modelData.keys !== "" ? "   " + modelData.keys : "")
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        HoverHandler { id: optionHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.choose(modelData.kind) }
      }
    }
  }
}
