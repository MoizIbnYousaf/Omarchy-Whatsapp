import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// WhatsApp formatting over a selection in the composer, as on Telegram or
// Slack: it appears above the selected text and goes away with the selection.
// It never takes the keyboard from the composer.
Popup {
  id: root
  objectName: "formatBar"

  // The TextEdit whose selection this formats; the bar sits above `anchorItem`.
  property Item editor: null
  property Item anchorItem: parent
  property bool enabledHere: true
  property color foreground: Color.foreground
  property color surface: Color.background
  property color accent: Color.accent
  property color muted: foreground
  property string fontFamily: Style.font.family
  signal chosen(string kind)

  readonly property var options: [
    { kind: "bold", glyph: "B", tip: "Bold · Ctrl+B" },
    { kind: "italic", glyph: "I", tip: "Italic · Ctrl+I" },
    { kind: "strike", glyph: "S", tip: "Strikethrough · Ctrl+Shift+X" },
    { kind: "mono", glyph: "M", tip: "Monospace · Ctrl+Shift+M" },
    { kind: "code", glyph: "`", tip: "Inline code" },
    { kind: "bullet", glyph: "•", tip: "Bulleted list" },
    { kind: "numbered", glyph: "1.", tip: "Numbered list" },
    { kind: "quote", glyph: "❝", tip: "Quote" }
  ]
  // The pointer over the bar keeps it: a click may take focus from the
  // composer for a moment before the format lands.
  readonly property bool wanted: enabledHere && editor !== null && editor.selectedText !== ""
    && (editor.activeFocus || barHover.hovered)
  onWantedChanged: wanted ? open() : close()

  readonly property rect selectionRect: editor
    ? editor.positionToRectangle(editor.selectionStart) : Qt.rect(0, 0, 0, 0)
  x: {
    if (!editor || !anchorItem) return 0
    var point = editor.mapToItem(anchorItem, selectionRect.x, selectionRect.y)
    return Math.max(0, Math.min(anchorItem.width - width, point.x - Style.space(12)))
  }
  y: -height - Style.space(6)
  padding: Style.space(4)
  focus: false
  modal: false
  closePolicy: Popup.NoAutoClose

  background: Rectangle {
    radius: Style.cornerRadius
    color: root.surface
    border.width: 1
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
  }

  contentItem: Row {
    spacing: Style.space(2)
    HoverHandler { id: barHover }
    Repeater {
      model: root.options
      delegate: Rectangle {
        required property var modelData
        objectName: "formatBarOption-" + modelData.kind
        width: Style.space(30)
        height: Style.space(30)
        radius: Style.cornerRadius
        color: optionHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: modelData.glyph
          color: optionHover.hovered ? root.accent : root.foreground
          font.family: modelData.kind === "mono" || modelData.kind === "code" ? "monospace" : root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: modelData.kind === "bold"
          font.italic: modelData.kind === "italic"
          font.strikeout: modelData.kind === "strike"
        }
        HoverHandler { id: optionHover; cursorShape: Qt.PointingHandCursor }
        PanelToolTip { visible: optionHover.hovered; text: modelData.tip }
        TapHandler { onTapped: root.chosen(modelData.kind) }
      }
    }
  }
}
